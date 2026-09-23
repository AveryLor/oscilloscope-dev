//! Checks this crate's parser against bytes produced by the firmware's own
//! packer, so the two implementations of the wire format cannot drift apart
//! silently. `docs/STREAM.md` is the contract they both follow.
//!
//! The fixture holds stray log text, then two back-to-back frames, exactly as
//! the ESP32 emits them. Regenerate it after any format change:
//!
//! ```sh
//! gcc -Wall -Wextra -Werror -O2 -I esp32/main \
//!     gui/tests/fixtures/emit_frame.c esp32/main/stream_frame.c -o /tmp/emit_frame
//! /tmp/emit_frame > gui/tests/fixtures/c_frames.bin
//! ```

use scope_gui::frame;
use scope_gui::link::Demux;

const FIXTURE: &[u8] = include_bytes!("fixtures/c_frames.bin");

/// Field values written by `gui/tests/fixtures/emit_frame.c`.
fn check_metadata(f: &frame::Frame, expect_seq: u32) {
    assert_eq!(f.seq, expect_seq);
    assert_eq!(f.sample_count, 16384);
    assert_eq!(f.dec_factor, 7);
    assert_eq!(f.pre_count, 1024);
    assert_eq!(f.post_count, 2048);
    assert_eq!(f.trig_ptr, 8192);
    assert_eq!(f.trig_level, 512);
    assert_eq!(f.afe_atten, 2);
    assert_eq!(f.lmh_atten, 6);
    assert_eq!(f.dac_offset, 2048);

    assert!(f.triggered);
    assert!(f.overrange);
    assert!(!f.peak);
    assert!(f.dc_coupled);
    assert!(f.preamp_hg);
    assert!(!f.term_50r);

    assert_eq!(f.cols.len(), 1000);
    for (c, &(ymin, ymax)) in f.cols.iter().enumerate() {
        assert_eq!(ymin, (400 + c % 100) as u16, "column {c} min");
        assert_eq!(ymax, (600 + c % 100) as u16, "column {c} max");
    }
}

#[test]
fn parses_frames_built_by_the_firmware_packer() {
    let mut demux = Demux::new();
    demux.push(FIXTURE);

    let first = demux
        .next_frame()
        .expect("a frame after the leading log text")
        .expect("frame validates");
    check_metadata(&first, 0xDEAD_BEEF);

    let second = demux
        .next_frame()
        .expect("the back-to-back second frame")
        .expect("frame validates");
    check_metadata(&second, 0xDEAD_BEF0);

    assert!(demux.next_frame().is_none(), "fixture holds exactly two frames");
}

#[test]
fn resyncs_when_the_stream_is_joined_mid_frame() {
    // Start 40 bytes in, so the first frame is truncated and must be skipped.
    let mut demux = Demux::new();
    demux.push(&FIXTURE[40..]);

    let f = loop {
        match demux.next_frame() {
            Some(Ok(f)) => break f,
            Some(Err(_)) => continue, // a false magic-word hit; keep scanning
            None => panic!("expected to resync onto the second frame"),
        }
    };
    check_metadata(&f, 0xDEAD_BEF0);
}

#[test]
fn rejects_a_frame_whose_payload_was_corrupted_in_transit() {
    let mut corrupted = FIXTURE.to_vec();
    // Flip a payload byte inside the first frame; the CRC must catch it.
    let first_payload = 23 + frame::HDR_BYTES + 8;
    corrupted[first_payload] ^= 0xFF;

    let mut demux = Demux::new();
    demux.push(&corrupted);

    assert!(
        demux.next_frame().expect("something is yielded").is_err(),
        "a corrupted payload must not parse as a good frame"
    );
}
