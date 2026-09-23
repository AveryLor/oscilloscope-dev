//! Entry point for the oscilloscope display. See `lib.rs` for the pieces.

use scope_gui::app::ScopeApp;
use scope_gui::link;

fn main() -> eframe::Result<()> {
    // --port <dev> [--baud <n>] connects on launch; with no arguments the
    // window opens and waits for a port to be picked.
    let mut args = std::env::args().skip(1);
    let mut port = None;
    let mut baud = link::DEFAULT_BAUD;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--port" => port = args.next(),
            "--baud" => {
                if let Some(v) = args.next().and_then(|v| v.parse().ok()) {
                    baud = v;
                }
            }
            "--list" => {
                for p in link::list_ports() {
                    println!("{p}");
                }
                return Ok(());
            }
            other => eprintln!("ignoring unknown argument: {other}"),
        }
    }

    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_inner_size([1100.0, 640.0])
            .with_title("Oscilloscope"),
        ..Default::default()
    };

    eframe::run_native(
        "Oscilloscope",
        options,
        Box::new(move |_cc| {
            Ok(Box::new(match port {
                Some(p) => ScopeApp::with_port(p, baud),
                None => ScopeApp::default(),
            }))
        }),
    )
}
