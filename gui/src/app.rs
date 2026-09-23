//! The scope window: connection controls, the trace plot, and a readout panel.

use std::time::{Duration, Instant};

use eframe::egui;
use egui_plot::{Line, Plot, PlotPoints, Polygon, VLine};

use crate::frame::Frame;
use crate::link::{self, Event, Link};

const TRACE: egui::Color32 = egui::Color32::from_rgb(0x33, 0xFF, 0x66);
const TRIG_LEVEL: egui::Color32 = egui::Color32::from_rgb(0xFF, 0x90, 0x20);
const TRIG_POS: egui::Color32 = egui::Color32::from_rgb(0x20, 0xA0, 0xFF);
const WARN: egui::Color32 = egui::Color32::from_rgb(0xFF, 0x3B, 0x30);

pub struct ScopeApp {
    ports: Vec<String>,
    selected: Option<String>,
    baud: u32,
    link: Option<Link>,
    status: String,

    latest: Option<Frame>,
    last_seq: Option<u32>,
    dropped: u64,
    bad: u64,
    last_bad: Option<String>,

    frames: u32,
    fps: f64,
    fps_since: Instant,
}

impl Default for ScopeApp {
    fn default() -> Self {
        let ports = link::list_ports();
        Self {
            selected: ports.first().cloned(),
            ports,
            baud: link::DEFAULT_BAUD,
            link: None,
            status: "not connected".to_owned(),
            latest: None,
            last_seq: None,
            dropped: 0,
            bad: 0,
            last_bad: None,
            frames: 0,
            fps: 0.0,
            fps_since: Instant::now(),
        }
    }
}

impl ScopeApp {
    /// Connect immediately, for the `--port` shortcut.
    pub fn with_port(port: String, baud: u32) -> Self {
        let mut app = Self {
            selected: Some(port),
            baud,
            ..Default::default()
        };
        app.connect();
        app
    }

    fn connect(&mut self) {
        let Some(port) = self.selected.clone() else {
            self.status = "no port selected".to_owned();
            return;
        };
        match Link::open(&port, self.baud) {
            Ok(l) => {
                self.link = Some(l);
                self.status = format!("connected to {port}");
                self.last_seq = None;
                self.dropped = 0;
                self.bad = 0;
                self.last_bad = None;
            }
            Err(e) => {
                self.status = format!("{port}: {e}");
            }
        }
    }

    fn disconnect(&mut self) {
        self.link = None;
        self.status = "not connected".to_owned();
    }

    fn pump(&mut self) {
        let mut disconnect_reason = None;

        if let Some(link) = &self.link {
            for ev in link.events.try_iter() {
                match ev {
                    Event::Frame(f) => {
                        if let Some(prev) = self.last_seq {
                            // seq counts captures at the source, so a gap is
                            // frames the link or the UI could not keep up with.
                            self.dropped += f.seq.wrapping_sub(prev).saturating_sub(1) as u64;
                        }
                        self.last_seq = Some(f.seq);
                        self.latest = Some(*f);
                        self.frames += 1;
                    }
                    Event::Bad(why) => {
                        self.bad += 1;
                        self.last_bad = Some(why);
                    }
                    Event::Disconnected(why) => disconnect_reason = Some(why),
                }
            }
        }

        if let Some(why) = disconnect_reason {
            self.link = None;
            self.status = format!("link lost: {why}");
        }

        let elapsed = self.fps_since.elapsed();
        if elapsed >= Duration::from_secs(1) {
            self.fps = self.frames as f64 / elapsed.as_secs_f64();
            self.frames = 0;
            self.fps_since = Instant::now();
        }
    }

    fn controls(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            let connected = self.link.is_some();

            let ports = self.ports.clone();
            ui.add_enabled_ui(!connected, |ui| {
                egui::ComboBox::from_id_salt("port")
                    .selected_text(self.selected.clone().unwrap_or_else(|| "—".to_owned()))
                    .show_ui(ui, |ui| {
                        for p in &ports {
                            ui.selectable_value(&mut self.selected, Some(p.clone()), p);
                        }
                    });
                if ui.button("Rescan").clicked() {
                    self.ports = link::list_ports();
                    if self.selected.is_none() {
                        self.selected = self.ports.first().cloned();
                    }
                }
            });

            if connected {
                if ui.button("Disconnect").clicked() {
                    self.disconnect();
                }
            } else if ui.button("Connect").clicked() {
                self.connect();
            }

            ui.separator();
            ui.label(&self.status);
        });
    }

    fn readout(&self, ui: &mut egui::Ui) {
        let Some(f) = &self.latest else {
            ui.label("waiting for a capture…");
            return;
        };

        egui::Grid::new("readout").num_columns(2).show(ui, |ui| {
            let vpc = f.volts_per_count();
            ui.label("Volts/div");
            ui.label(fmt_volts(vpc * 128.0)); // 8 vertical divisions over 1024 codes
            ui.end_row();

            ui.label("Time/div");
            ui.label(fmt_secs(f.duration() / 10.0)); // 10 horizontal divisions
            ui.end_row();

            ui.label("Samples");
            ui.label(format!("{}", f.sample_count));
            ui.end_row();

            ui.label("Coupling");
            ui.label(if f.dc_coupled { "DC" } else { "AC" });
            ui.end_row();

            ui.label("Input");
            ui.label(match f.afe_atten {
                0 => "1x",
                1 => "10x",
                _ => "100x",
            });
            ui.end_row();

            ui.label("Termination");
            ui.label(if f.term_50r { "50 Ω" } else { "1 MΩ" });
            ui.end_row();

            ui.label("Trigger");
            ui.label(if f.triggered { "triggered" } else { "auto" });
            ui.end_row();

            ui.label("Pre/post");
            ui.label(format!("{} / {}", f.pre_count, f.post_count));
            ui.end_row();

            ui.label("Acquisition");
            ui.label(if f.peak { "peak detect" } else { "sampled" });
            ui.end_row();

            ui.label("Offset code");
            ui.label(format!("{}", f.dac_offset));
            ui.end_row();

            ui.label("Frames/s");
            ui.label(format!("{:.1}", self.fps));
            ui.end_row();

            ui.label("Dropped");
            ui.label(format!("{}", self.dropped));
            ui.end_row();

            ui.label("Bad frames");
            ui.label(format!("{}", self.bad));
            ui.end_row();
        });

        if f.overrange {
            ui.colored_label(WARN, "input clipping");
        }
        if let Some(why) = &self.last_bad {
            ui.colored_label(WARN, format!("last bad frame: {why}"));
        }
    }

    fn plot(&self, ui: &mut egui::Ui) {
        let Some(f) = &self.latest else {
            ui.centered_and_justified(|ui| ui.label("no signal"));
            return;
        };

        let n = f.cols.len() as f64;
        let dur = f.duration();
        let x_of = |i: usize| if n > 1.0 { i as f64 / (n - 1.0) * dur } else { 0.0 };

        Plot::new("trace")
            .allow_drag(false)
            .allow_zoom(false)
            .allow_scroll(false)
            .x_axis_formatter(|m, _| fmt_secs(m.value))
            .y_axis_formatter(|m, _| fmt_volts(m.value))
            .show(ui, |plot| {
                // Each column is a min/max band, so a transient narrower than a
                // column still shows as height rather than vanishing. Draw the
                // band as a polygon down the top edge and back along the bottom.
                let mut hull: Vec<[f64; 2]> = Vec::with_capacity(f.cols.len() * 2);
                for (i, &(_, ymax)) in f.cols.iter().enumerate() {
                    hull.push([x_of(i), f.code_to_volts(ymax)]);
                }
                for (i, &(ymin, _)) in f.cols.iter().enumerate().rev() {
                    hull.push([x_of(i), f.code_to_volts(ymin)]);
                }
                plot.polygon(
                    Polygon::new(PlotPoints::from(hull))
                        .fill_color(TRACE.gamma_multiply(0.35))
                        .stroke(egui::Stroke::new(1.0_f32, TRACE)),
                );

                // Midline of each column, so a flat trace still reads as a line.
                let mid: PlotPoints = f
                    .cols
                    .iter()
                    .enumerate()
                    .map(|(i, &(lo, hi))| {
                        [x_of(i), f.code_to_volts(((lo as u32 + hi as u32) / 2) as u16)]
                    })
                    .collect();
                plot.line(Line::new(mid).color(TRACE).width(1.5_f32));

                plot.hline(
                    egui_plot::HLine::new(f.code_to_volts(f.trig_level))
                        .color(TRIG_LEVEL)
                        .style(egui_plot::LineStyle::dashed_loose()),
                );

                if let Some(frac) = f.trig_fraction() {
                    plot.vline(
                        VLine::new(frac * dur)
                            .color(TRIG_POS)
                            .style(egui_plot::LineStyle::dashed_loose()),
                    );
                }
            });
    }
}

impl eframe::App for ScopeApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.pump();

        egui::TopBottomPanel::top("controls").show(ctx, |ui| self.controls(ui));
        egui::SidePanel::right("readout")
            .resizable(false)
            .default_width(190.0)
            .show(ctx, |ui| self.readout(ui));
        egui::CentralPanel::default().show(ctx, |ui| self.plot(ui));

        // Frames arrive on their own schedule, so drive repaints rather than
        // waiting for input events.
        if self.link.is_some() {
            ctx.request_repaint_after(Duration::from_millis(16));
        }
    }
}

fn fmt_volts(v: f64) -> String {
    let a = v.abs();
    if a >= 1.0 {
        format!("{v:.2} V")
    } else if a >= 1e-3 {
        format!("{:.1} mV", v * 1e3)
    } else {
        format!("{:.0} µV", v * 1e6)
    }
}

fn fmt_secs(s: f64) -> String {
    let a = s.abs();
    if a >= 1.0 {
        format!("{s:.2} s")
    } else if a >= 1e-3 {
        format!("{:.2} ms", s * 1e3)
    } else if a >= 1e-6 {
        format!("{:.2} µs", s * 1e6)
    } else {
        format!("{:.0} ns", s * 1e9)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scales_units_by_magnitude() {
        assert_eq!(fmt_volts(1.5), "1.50 V");
        assert_eq!(fmt_volts(0.0015), "1.5 mV");
        assert_eq!(fmt_secs(0.000002), "2.00 µs");
        assert_eq!(fmt_secs(2.0), "2.00 s");
    }
}
