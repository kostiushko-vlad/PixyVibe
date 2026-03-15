use gtk4::prelude::*;
use gtk4::{DrawingArea, Window};
use std::cell::RefCell;
use std::rc::Rc;

use crate::action_toolbar;
use crate::region_selector::RegionState;

pub fn show_region_selector() {
    let window = Window::builder()
        .decorated(false)
        .fullscreened(true)
        .build();

    window.set_opacity(1.0);

    let state = Rc::new(RefCell::new(RegionState::new()));
    let drawing_area = DrawingArea::new();
    drawing_area.set_hexpand(true);
    drawing_area.set_vexpand(true);

    // Drawing
    let state_draw = state.clone();
    drawing_area.set_draw_func(move |_, cr, width, height| {
        let state = state_draw.borrow();

        // Semi-transparent overlay
        cr.set_source_rgba(0.0, 0.0, 0.0, 0.35);
        cr.paint().unwrap();

        if let Some(rect) = state.selection_rect() {
            // Clear the selected region
            cr.set_operator(gtk4::cairo::Operator::Clear);
            cr.rectangle(rect.0, rect.1, rect.2, rect.3);
            cr.fill().unwrap();
            cr.set_operator(gtk4::cairo::Operator::Over);

            // White border
            cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
            cr.set_line_width(2.0);
            cr.rectangle(rect.0, rect.1, rect.2, rect.3);
            cr.stroke().unwrap();

            // Dimensions label
            let label = format!("{} x {}", rect.2 as i32, rect.3 as i32);
            cr.set_font_size(13.0);
            let extents = cr.text_extents(&label).unwrap();
            let lx = rect.0 + rect.2 / 2.0 - extents.width() / 2.0;
            let ly = rect.1 + rect.3 + 20.0;

            cr.set_source_rgba(0.0, 0.0, 0.0, 0.7);
            cr.rectangle(
                lx - 4.0,
                ly - extents.height() - 2.0,
                extents.width() + 8.0,
                extents.height() + 4.0,
            );
            cr.fill().unwrap();

            cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
            cr.move_to(lx, ly);
            cr.show_text(&label).unwrap();
        }
    });

    // Mouse drag for region selection
    let gesture = gtk4::GestureDrag::new();
    let state_begin = state.clone();
    gesture.connect_drag_begin(move |_, x, y| {
        state_begin.borrow_mut().start(x, y);
    });

    let state_update = state.clone();
    let da_ref = drawing_area.clone();
    gesture.connect_drag_update(move |_, dx, dy| {
        state_update.borrow_mut().update(dx, dy);
        da_ref.queue_draw();
    });

    let state_end = state.clone();
    let win_ref = window.clone();
    gesture.connect_drag_end(move |_, _, _| {
        let rect = state_end.borrow().selection_rect();
        if let Some(rect) = rect {
            if rect.2 > 10.0 && rect.3 > 10.0 {
                action_toolbar::show(rect, &win_ref);
            }
        }
    });
    drawing_area.add_controller(gesture);

    // Keyboard: ESC to cancel
    let key_ctrl = gtk4::EventControllerKey::new();
    let win_esc = window.clone();
    key_ctrl.connect_key_pressed(move |_, key, _, _| {
        if key == gtk4::gdk::Key::Escape {
            win_esc.close();
            return gtk4::glib::Propagation::Stop;
        }
        gtk4::glib::Propagation::Proceed
    });
    window.add_controller(key_ctrl);

    window.set_child(Some(&drawing_area));
    window.present();
}
