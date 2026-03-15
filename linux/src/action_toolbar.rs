use gtk4::prelude::*;
use gtk4::Window;

use crate::capture;

/// Show a floating toolbar near the selected region with S/G/D actions.
pub fn show(rect: (f64, f64, f64, f64), parent: &Window) {
    let (rx, ry, rw, rh) = rect;

    let toolbar = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    toolbar.set_margin_start(8);
    toolbar.set_margin_end(8);
    toolbar.set_margin_top(8);
    toolbar.set_margin_bottom(8);

    let btn_screenshot = gtk4::Button::with_label("Screenshot (S)");
    let btn_gif = gtk4::Button::with_label("Record GIF (G)");
    let btn_diff = gtk4::Button::with_label("Diff (D)");

    toolbar.append(&btn_screenshot);
    toolbar.append(&btn_gif);
    toolbar.append(&btn_diff);

    let popup = Window::builder()
        .decorated(false)
        .build();
    popup.set_child(Some(&toolbar));

    let parent_clone = parent.clone();
    btn_screenshot.connect_clicked(move |_| {
        parent_clone.close();
        handle_screenshot(rx as u32, ry as u32, rw as u32, rh as u32);
    });

    let parent_clone = parent.clone();
    btn_gif.connect_clicked(move |_| {
        parent_clone.close();
        handle_gif(rx as u32, ry as u32, rw as u32, rh as u32);
    });

    let parent_clone = parent.clone();
    btn_diff.connect_clicked(move |_| {
        parent_clone.close();
        handle_diff(rx as u32, ry as u32, rw as u32, rh as u32);
    });

    // Handle keyboard shortcuts
    let key_ctrl = gtk4::EventControllerKey::new();
    let p1 = parent.clone();
    let p2 = parent.clone();
    let p3 = parent.clone();
    key_ctrl.connect_key_pressed(move |_, key, _, _| {
        match key {
            gtk4::gdk::Key::s | gtk4::gdk::Key::S => {
                p1.close();
                handle_screenshot(rx as u32, ry as u32, rw as u32, rh as u32);
                gtk4::glib::Propagation::Stop
            }
            gtk4::gdk::Key::g | gtk4::gdk::Key::G => {
                p2.close();
                handle_gif(rx as u32, ry as u32, rw as u32, rh as u32);
                gtk4::glib::Propagation::Stop
            }
            gtk4::gdk::Key::d | gtk4::gdk::Key::D => {
                p3.close();
                handle_diff(rx as u32, ry as u32, rw as u32, rh as u32);
                gtk4::glib::Propagation::Stop
            }
            _ => gtk4::glib::Propagation::Proceed,
        }
    });
    popup.add_controller(key_ctrl);

    popup.present();
}

fn handle_screenshot(x: u32, y: u32, w: u32, h: u32) {
    match capture::capture_region(x, y, w, h) {
        Ok((pixels, width, height)) => {
            let stride = width * 4;
            match screenshottool::process_screenshot(&pixels, width, height, stride) {
                Ok(result) => {
                    tracing::info!("Screenshot saved to {}", result.file_path.display());
                    // TODO: copy to clipboard via GTK clipboard API
                }
                Err(e) => tracing::error!("Failed to process screenshot: {}", e),
            }
        }
        Err(e) => tracing::error!("Failed to capture region: {}", e),
    }
}

fn handle_gif(x: u32, y: u32, w: u32, h: u32) {
    match screenshottool::gif_start() {
        Ok(session_id) => {
            tracing::info!("GIF recording started: {}", session_id);
            // TODO: start frame capture timer, show recording pill
            // For now, capture a few frames
            for _ in 0..30 {
                if let Ok((pixels, width, height)) = capture::capture_region(x, y, w, h) {
                    let stride = width * 4;
                    let _ = screenshottool::gif_add_frame(&session_id, &pixels, width, height, stride);
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            match screenshottool::gif_finish(&session_id) {
                Ok(result) => {
                    tracing::info!("GIF saved to {}", result.file_path.display());
                }
                Err(e) => tracing::error!("Failed to encode GIF: {}", e),
            }
        }
        Err(e) => tracing::error!("Failed to start GIF: {}", e),
    }
}

fn handle_diff(x: u32, y: u32, w: u32, h: u32) {
    match capture::capture_region(x, y, w, h) {
        Ok((pixels, width, height)) => {
            let stride = width * 4;
            match screenshottool::diff_store_before(&pixels, width, height, stride) {
                Ok(()) => {
                    tracing::info!("Before captured — make changes, then press Shift+Ctrl+6 again");
                    // TODO: set diff-pending state, change tray icon
                }
                Err(e) => tracing::error!("Failed to store before: {}", e),
            }
        }
        Err(e) => tracing::error!("Failed to capture region: {}", e),
    }
}
