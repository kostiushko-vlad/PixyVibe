use gtk4::prelude::*;
use gtk4::Window;
use std::cell::Cell;
use std::rc::Rc;

pub struct RecordingPillHandle {
    window: Window,
}

impl RecordingPillHandle {
    pub fn close(&self) {
        self.window.close();
    }
}

/// Show a floating recording indicator.
pub fn show(x: f64, y: f64) -> RecordingPillHandle {
    let window = Window::builder()
        .decorated(false)
        .build();

    let container = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    container.set_margin_start(12);
    container.set_margin_end(12);
    container.set_margin_top(8);
    container.set_margin_bottom(8);

    // Red dot
    let dot = gtk4::Label::new(Some("\u{25CF}"));
    dot.add_css_class("recording-dot");

    // Timer label
    let elapsed = Rc::new(Cell::new(0u32));
    let label = gtk4::Label::new(Some("REC 0:00"));

    // Stop button
    let stop_btn = gtk4::Button::with_label("Stop");

    container.append(&dot);
    container.append(&label);
    container.append(&stop_btn);

    window.set_child(Some(&container));

    // Update timer every second
    let label_clone = label.clone();
    let elapsed_clone = elapsed.clone();
    gtk4::glib::timeout_add_seconds_local(1, move || {
        let secs = elapsed_clone.get() + 1;
        elapsed_clone.set(secs);
        let m = secs / 60;
        let s = secs % 60;
        label_clone.set_text(&format!("REC {}:{:02}", m, s));
        gtk4::glib::ControlFlow::Continue
    });

    let win_ref = window.clone();
    stop_btn.connect_clicked(move |_| {
        win_ref.close();
    });

    window.present();

    RecordingPillHandle { window }
}
