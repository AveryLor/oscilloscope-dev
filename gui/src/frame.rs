//! Parser for the ESP32 sample stream. Wire format lives in `docs/STREAM.md`;
//! the writer is `esp32/main/stream.c`. Keep all three in step.

pub const MAGIC: u32 = 0x5343_4F50; // "SCOP"
pub const VERSION: u8 = 1;
pub const HDR_BYTES: usize = 36;

/// Guards against a corrupt length driving a huge allocation.
pub const MAX_COLS: usize = 8192;

// frame flags
const FLAG_PEAK: u8 = 1 << 0;
const FLAG_TRIGGERED: u8 = 1 << 1;
const FLAG_OVERRANGE: u8 = 1 << 2;

// afe_flags
const AFE_DC_COUPLED: u8 = 1 << 0;
const AFE_TERM_50R: u8 = 1 << 1;
const AFE_PREAMP_HG: u8 = 1 << 2;

/// ADC mid-scale; the AD9215 is 10-bit and mid-scale is 0 V at the input.
pub const CODE_MID: f64 = 512.0;

/// Sample rate after the PL133 clock, before decimation.
pub const SAMPLE_RATE_HZ: f64 = 105_000_000.0;

#[derive(Clone, Debug)]
pub struct Frame {
    pub seq: u32,
    pub peak: bool,
    pub triggered: bool,
    pub overrange: bool,
    pub sample_count: u32,
    pub dec_factor: u16,
    pub pre_count: u16,
    pub post_count: u16,
    pub trig_ptr: u32,
    pub trig_level: u16,
    pub afe_atten: u8,
    pub dc_coupled: bool,
    pub term_50r: bool,
    pub preamp_hg: bool,
    pub lmh_atten: u8,
    pub dac_offset: u16,
    /// Per column, the lowest and highest code seen.
    pub cols: Vec<(u16, u16)>,
}

impl Frame {
    /// Seconds per sample after decimation.
    pub fn sample_period(&self) -> f64 {
        (self.dec_factor as f64 + 1.0) / SAMPLE_RATE_HZ
    }

    /// Full record duration in seconds.
    pub fn duration(&self) -> f64 {
        self.sample_count as f64 * self.sample_period()
    }

    /// Volts per ADC count at the probe tip.
    ///
    /// The ESP32 sends the front-end settings raw, so the dB arithmetic happens
    /// here in floating point rather than being rounded into an integer field.
    /// Chain: input divider, then the LMH6518 preamp, then its 2 dB ladder.
    pub fn volts_per_count(&self) -> f64 {
        let divider = match self.afe_atten {
            0 => 1.0,
            1 => 10.0,
            _ => 100.0,
        };
        let preamp_db = if self.preamp_hg { 38.8 } else { 18.8 };
        let gain_db = preamp_db - 2.0 * self.lmh_atten as f64;
        let gain = 10f64.powf(gain_db / 20.0);

        // AD9215 full scale is 2 Vpp across 1024 codes, referred back through
        // the amplifier chain and the input divider.
        const ADC_FULL_SCALE_V: f64 = 2.0;
        (ADC_FULL_SCALE_V / 1024.0) / gain * divider
    }

    /// Convert a raw code to volts at the probe tip.
    pub fn code_to_volts(&self, code: u16) -> f64 {
        (code as f64 - CODE_MID) * self.volts_per_count()
    }

    /// Where the trigger sits as a fraction across the record, 0.0 to 1.0.
    pub fn trig_fraction(&self) -> Option<f64> {
        if self.sample_count == 0 {
            return None;
        }
        let f = self.trig_ptr as f64 / self.sample_count as f64;
        (0.0..=1.0).contains(&f).then_some(f)
    }
}

fn u16_at(b: &[u8], at: usize) -> u16 {
    u16::from_le_bytes([b[at], b[at + 1]])
}

fn u32_at(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}

/// CRC-32, reflected `0xEDB88320`, matching `crc32()` in `esp32/main/stream.c`.
pub fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xEDB8_8320 & mask);
        }
    }
    !crc
}

#[derive(Debug)]
pub enum ParseError {
    BadVersion(u8),
    BadColumnCount(u16),
    BadCrc,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::BadVersion(v) => {
                write!(f, "unsupported frame version {v} (expected {VERSION})")
            }
            ParseError::BadColumnCount(n) => write!(f, "implausible column count {n}"),
            ParseError::BadCrc => write!(f, "CRC mismatch"),
        }
    }
}

/// Number of columns declared by a header, for sizing the payload read.
pub fn cols_of(header: &[u8]) -> Result<usize, ParseError> {
    let version = header[4];
    if version != VERSION {
        return Err(ParseError::BadVersion(version));
    }
    let n = u16_at(header, 6);
    if n == 0 || n as usize > MAX_COLS {
        return Err(ParseError::BadColumnCount(n));
    }
    Ok(n as usize)
}

/// Parse a full frame: the 36-byte header, the column payload, and the CRC.
pub fn parse(buf: &[u8]) -> Result<Frame, ParseError> {
    let n_cols = cols_of(buf)?;
    let payload_end = HDR_BYTES + n_cols * 4;

    let want = u32_at(buf, payload_end);
    if crc32(&buf[4..payload_end]) != want {
        return Err(ParseError::BadCrc);
    }

    let flags = buf[5];
    let afe_flags = buf[31];

    let mut cols = Vec::with_capacity(n_cols);
    for c in 0..n_cols {
        let at = HDR_BYTES + c * 4;
        cols.push((u16_at(buf, at), u16_at(buf, at + 2)));
    }

    Ok(Frame {
        seq: u32_at(buf, 8),
        peak: flags & FLAG_PEAK != 0,
        triggered: flags & FLAG_TRIGGERED != 0,
        overrange: flags & FLAG_OVERRANGE != 0,
        sample_count: u32_at(buf, 12),
        dec_factor: u16_at(buf, 16),
        pre_count: u16_at(buf, 18),
        post_count: u16_at(buf, 20),
        trig_ptr: u32_at(buf, 22),
        trig_level: u16_at(buf, 26),
        afe_atten: buf[30],
        dc_coupled: afe_flags & AFE_DC_COUPLED != 0,
        term_50r: afe_flags & AFE_TERM_50R != 0,
        preamp_hg: afe_flags & AFE_PREAMP_HG != 0,
        lmh_atten: buf[32],
        dac_offset: u16_at(buf, 34),
        cols,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The reference check value for the reflected CRC-32 of "123456789".
    #[test]
    fn crc_matches_reference_vector() {
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    }

    fn build(n_cols: u16) -> Vec<u8> {
        let mut b = vec![0u8; HDR_BYTES + n_cols as usize * 4 + 4];
        b[0..4].copy_from_slice(&MAGIC.to_le_bytes());
        b[4] = VERSION;
        b[5] = FLAG_TRIGGERED;
        b[6..8].copy_from_slice(&n_cols.to_le_bytes());
        b[8..12].copy_from_slice(&7u32.to_le_bytes()); // seq
        b[12..16].copy_from_slice(&(n_cols as u32).to_le_bytes()); // sample_count
        b[22..26].copy_from_slice(&(n_cols as u32 / 2).to_le_bytes()); // trig_ptr
        b[30] = 2; // 100x
        for c in 0..n_cols as usize {
            let at = HDR_BYTES + c * 4;
            b[at..at + 2].copy_from_slice(&(c as u16).to_le_bytes());
            b[at + 2..at + 4].copy_from_slice(&(c as u16 + 1).to_le_bytes());
        }
        let end = HDR_BYTES + n_cols as usize * 4;
        let crc = crc32(&b[4..end]);
        b[end..end + 4].copy_from_slice(&crc.to_le_bytes());
        b
    }

    #[test]
    fn round_trips_a_built_frame() {
        let buf = build(8);
        let f = parse(&buf).expect("parses");
        assert_eq!(f.seq, 7);
        assert!(f.triggered);
        assert!(!f.overrange);
        assert_eq!(f.cols.len(), 8);
        assert_eq!(f.cols[3], (3, 4));
        assert_eq!(f.trig_fraction(), Some(0.5));
    }

    #[test]
    fn rejects_a_corrupted_payload() {
        let mut buf = build(8);
        buf[HDR_BYTES] ^= 0xFF;
        assert!(matches!(parse(&buf), Err(ParseError::BadCrc)));
    }

    #[test]
    fn rejects_a_bad_version() {
        let mut buf = build(4);
        buf[4] = 99;
        assert!(matches!(parse(&buf), Err(ParseError::BadVersion(99))));
    }

    #[test]
    fn rejects_an_absurd_column_count() {
        let mut buf = build(4);
        buf[6..8].copy_from_slice(&u16::MAX.to_le_bytes());
        assert!(matches!(parse(&buf), Err(ParseError::BadColumnCount(_))));
    }

    #[test]
    fn attenuation_scales_volts_per_count() {
        let mut f = parse(&build(4)).unwrap();
        f.afe_atten = 0;
        let at_1x = f.volts_per_count();
        f.afe_atten = 2;
        assert!((f.volts_per_count() - at_1x * 100.0).abs() < 1e-12);
    }
}
