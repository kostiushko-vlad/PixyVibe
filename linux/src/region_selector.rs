pub struct RegionState {
    start_x: f64,
    start_y: f64,
    current_dx: f64,
    current_dy: f64,
    has_selection: bool,
}

impl RegionState {
    pub fn new() -> Self {
        RegionState {
            start_x: 0.0,
            start_y: 0.0,
            current_dx: 0.0,
            current_dy: 0.0,
            has_selection: false,
        }
    }

    pub fn start(&mut self, x: f64, y: f64) {
        self.start_x = x;
        self.start_y = y;
        self.current_dx = 0.0;
        self.current_dy = 0.0;
        self.has_selection = true;
    }

    pub fn update(&mut self, dx: f64, dy: f64) {
        self.current_dx = dx;
        self.current_dy = dy;
    }

    /// Returns (x, y, width, height) of the selection rectangle.
    pub fn selection_rect(&self) -> Option<(f64, f64, f64, f64)> {
        if !self.has_selection {
            return None;
        }

        let end_x = self.start_x + self.current_dx;
        let end_y = self.start_y + self.current_dy;

        let x = self.start_x.min(end_x);
        let y = self.start_y.min(end_y);
        let w = (self.current_dx).abs();
        let h = (self.current_dy).abs();

        if w < 1.0 || h < 1.0 {
            return None;
        }

        Some((x, y, w, h))
    }
}
