mod app;
mod capture;
mod overlay;
mod region_selector;
mod action_toolbar;
mod recording_pill;
mod settings;

use gtk4::prelude::*;
use gtk4::Application;

fn main() {
    let app = Application::builder()
        .application_id("com.pixyvibe.screenshottool")
        .build();

    app.connect_activate(|app| {
        app::setup(app);
    });

    app.run();
}
