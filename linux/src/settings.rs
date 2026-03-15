use gtk4::prelude::*;

pub fn show_preferences() {
    let dialog = gtk4::Window::builder()
        .title("PixyVibe Settings")
        .default_width(400)
        .default_height(300)
        .build();

    let notebook = gtk4::Notebook::new();

    // General tab
    let general_box = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    general_box.set_margin_start(16);
    general_box.set_margin_end(16);
    general_box.set_margin_top(16);
    general_box.set_margin_bottom(16);

    let hotkey_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    hotkey_row.append(&gtk4::Label::new(Some("Capture shortcut:")));
    hotkey_row.append(&gtk4::Label::new(Some("Shift+Ctrl+6")));
    general_box.append(&hotkey_row);

    notebook.append_page(&general_box, Some(&gtk4::Label::new(Some("General"))));

    // GIF tab
    let gif_box = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    gif_box.set_margin_start(16);
    gif_box.set_margin_end(16);
    gif_box.set_margin_top(16);
    gif_box.set_margin_bottom(16);

    let fps_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    fps_row.append(&gtk4::Label::new(Some("Frame rate:")));
    let fps_spin = gtk4::SpinButton::with_range(5.0, 30.0, 1.0);
    fps_spin.set_value(10.0);
    fps_row.append(&fps_spin);
    fps_row.append(&gtk4::Label::new(Some("fps")));
    gif_box.append(&fps_row);

    notebook.append_page(&gif_box, Some(&gtk4::Label::new(Some("GIF"))));

    // Output tab
    let output_box = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    output_box.set_margin_start(16);
    output_box.set_margin_end(16);
    output_box.set_margin_top(16);
    output_box.set_margin_bottom(16);

    let dir_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    dir_row.append(&gtk4::Label::new(Some("Save location:")));
    dir_row.append(&gtk4::Label::new(Some("~/.screenshottool")));
    output_box.append(&dir_row);

    let cleanup_check = gtk4::CheckButton::with_label("Auto-delete old captures");
    cleanup_check.set_active(true);
    output_box.append(&cleanup_check);

    notebook.append_page(&output_box, Some(&gtk4::Label::new(Some("Output"))));

    dialog.set_child(Some(&notebook));
    dialog.present();
}
