//! Kiriko — entry point.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use kiriko_ui::Shell;

const STORAGE_KEY: &str = "kiriko.shell";

struct KirikoApp {
    shell: Shell,
}

impl KirikoApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let restored = cc
            .storage
            .and_then(|s| eframe::get_value::<Shell>(s, STORAGE_KEY));
        Self {
            shell: Shell::new(&cc.egui_ctx, restored),
        }
    }
}

impl eframe::App for KirikoApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.shell.ui(ctx);
    }

    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        eframe::set_value(storage, STORAGE_KEY, &self.shell);
    }
}

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Kiriko")
            .with_inner_size([1440.0, 900.0])
            .with_min_inner_size([960.0, 600.0])
            .with_app_id("kiriko"),
        ..Default::default()
    };
    eframe::run_native(
        "kiriko",
        options,
        Box::new(|cc| Ok(Box::new(KirikoApp::new(cc)))),
    )
}
