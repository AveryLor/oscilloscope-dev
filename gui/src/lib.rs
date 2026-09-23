//! Host-side display for the Tang Nano 20K / ESP32 oscilloscope.
//!
//! The FPGA captures and the ESP32 streams column-reduced records over the
//! USB-UART link (see `docs/STREAM.md`); everything graphical happens here.

pub mod app;
pub mod frame;
pub mod link;
