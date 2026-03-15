use gtk4::prelude::*;
use gtk4::Application;

use crate::overlay;

pub fn setup(app: &Application) {
    // Initialize the screenshottool core
    let config = screenshottool::Config::default();
    if let Err(e) = screenshottool::init(&config) {
        tracing::error!("Failed to initialize core: {}", e);
        return;
    }

    // Register global shortcut — Shift+Ctrl+6
    // On GTK4, global shortcuts require platform-specific handling.
    // For now, we register an app-level action.
    let action = gtk4::gio::SimpleAction::new("capture", None);
    action.connect_activate(move |_, _| {
        overlay::show_region_selector();
    });
    app.add_action(&action);
    app.set_accels_for_action("app.capture", &["<Shift><Control>6"]);

    // Create a hidden window to keep the app alive
    let window = gtk4::ApplicationWindow::builder()
        .application(app)
        .title("PixyVibe")
        .default_width(1)
        .default_height(1)
        .build();

    window.set_visible(false);

    tracing::info!("PixyVibe Linux app started");
}
