//! Serial reader. Owns the port on a background thread, resyncs on the magic
//! word, and hands parsed frames to the UI thread.

use std::io::Read;
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TrySendError};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::thread;
use std::time::Duration;

use crate::frame::{self, Frame, HDR_BYTES, MAGIC};

pub const DEFAULT_BAUD: u32 = 921_600;

pub enum Event {
    Frame(Box<Frame>),
    /// A frame arrived but failed to parse; carries a short reason.
    Bad(String),
    Disconnected(String),
}

/// Pulls frames out of a byte stream that may start mid-frame, carry stray log
/// text, or split a frame across reads. Kept separate from the serial port so
/// the framing rules can be tested against recorded bytes.
#[derive(Default)]
pub struct Demux {
    buf: Vec<u8>,
}

impl Demux {
    pub fn new() -> Self {
        Self { buf: Vec::with_capacity(16 * 1024) }
    }

    pub fn push(&mut self, bytes: &[u8]) {
        self.buf.extend_from_slice(bytes);
    }

    /// Next frame, or `Err` describing one that failed to validate. `None` means
    /// more bytes are needed.
    pub fn next_frame(&mut self) -> Option<Result<Frame, String>> {
        let magic = MAGIC.to_le_bytes();

        loop {
            // Drop anything ahead of the next magic word. Stray log text or a
            // mid-stream connection lands here.
            let Some(start) = find(&self.buf, &magic) else {
                // A magic word may straddle two reads, so keep a short tail.
                let keep = self.buf.len().saturating_sub(magic.len() - 1);
                self.buf.drain(..keep);
                return None;
            };
            if start > 0 {
                self.buf.drain(..start);
            }
            if self.buf.len() < HDR_BYTES {
                return None;
            }

            let n_cols = match frame::cols_of(&self.buf) {
                Ok(n) => n,
                Err(e) => {
                    // Not a real frame start after all; step over this magic
                    // word and keep scanning.
                    self.buf.drain(..magic.len());
                    return Some(Err(e.to_string()));
                }
            };

            let total = HDR_BYTES + n_cols * 4 + 4;
            if self.buf.len() < total {
                return None; // wait for the rest
            }

            let result = frame::parse(&self.buf[..total]);
            match result {
                Ok(f) => {
                    self.buf.drain(..total);
                    return Some(Ok(f));
                }
                Err(e) => {
                    self.buf.drain(..magic.len());
                    return Some(Err(e.to_string()));
                }
            }
        }
    }
}

pub struct Link {
    pub events: Receiver<Event>,
    stop: Arc<AtomicBool>,
}

impl Link {
    pub fn open(port: &str, baud: u32) -> Result<Link, serialport::Error> {
        let handle = serialport::new(port, baud)
            .timeout(Duration::from_millis(200))
            .open()?;

        // Depth 2: the UI only ever draws the newest capture, so a slow repaint
        // should drop frames rather than build a backlog of stale ones.
        let (tx, rx) = sync_channel(2);
        let stop = Arc::new(AtomicBool::new(false));
        let stop_thread = Arc::clone(&stop);

        thread::spawn(move || read_loop(handle, tx, stop_thread));

        Ok(Link { events: rx, stop })
    }
}

impl Drop for Link {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

fn send(tx: &SyncSender<Event>, ev: Event) -> bool {
    match tx.try_send(ev) {
        Ok(()) => true,
        // A full channel means the UI is behind; dropping is intended.
        Err(TrySendError::Full(_)) => true,
        Err(TrySendError::Disconnected(_)) => false,
    }
}

fn read_loop(
    mut port: Box<dyn serialport::SerialPort>,
    tx: SyncSender<Event>,
    stop: Arc<AtomicBool>,
) {
    let mut demux = Demux::new();
    let mut chunk = [0u8; 4096];

    while !stop.load(Ordering::Relaxed) {
        match port.read(&mut chunk) {
            Ok(0) => continue,
            Ok(n) => demux.push(&chunk[..n]),
            Err(ref e) if e.kind() == std::io::ErrorKind::TimedOut => continue,
            Err(e) => {
                let _ = tx.try_send(Event::Disconnected(e.to_string()));
                return;
            }
        }

        while let Some(item) = demux.next_frame() {
            let ev = match item {
                Ok(f) => Event::Frame(Box::new(f)),
                Err(why) => Event::Bad(why),
            };
            if !send(&tx, ev) {
                return;
            }
        }
    }
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if haystack.len() < needle.len() {
        return None;
    }
    haystack.windows(needle.len()).position(|w| w == needle)
}

pub fn list_ports() -> Vec<String> {
    serialport::available_ports()
        .map(|ports| ports.into_iter().map(|p| p.port_name).collect())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_a_pattern_and_reports_absence() {
        assert_eq!(find(b"xxSCOPyy", b"SCOP"), Some(2));
        assert_eq!(find(b"nothing", b"SCOP"), None);
        assert_eq!(find(b"ab", b"SCOP"), None);
    }

    #[test]
    fn waits_for_more_bytes_instead_of_yielding_a_partial_frame() {
        let mut d = Demux::new();
        d.push(&MAGIC.to_le_bytes());
        assert!(d.next_frame().is_none());
    }

    #[test]
    fn skips_leading_noise_that_never_contains_a_frame() {
        let mut d = Demux::new();
        d.push(b"no frame here at all, just log spew");
        assert!(d.next_frame().is_none());
        // The tail kept for a straddling magic word must stay bounded.
        assert!(d.buf.len() < 4);
    }
}
