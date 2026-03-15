use image::{Rgba, RgbaImage};
use std::io::Cursor;
use std::path::PathBuf;

pub struct DiffEngine {
    before: Option<RgbaImage>,
}

#[derive(Debug, Clone)]
pub struct DiffOutput {
    pub side_by_side_bytes: Vec<u8>,
    pub change_percentage: f32,
    pub change_regions: Vec<ChangeRegion>,
    pub file_path: Option<PathBuf>,
}

#[derive(Debug, Clone)]
pub struct ChangeRegion {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

impl DiffEngine {
    pub fn new() -> Self {
        DiffEngine { before: None }
    }

    pub fn store_before(&mut self, image: RgbaImage) {
        self.before = Some(image);
    }

    pub fn has_before(&self) -> bool {
        self.before.is_some()
    }

    /// Compare "after" capture against stored "before".
    /// Generates a side-by-side image with change highlights.
    pub fn compare(
        &mut self,
        after: RgbaImage,
    ) -> Result<DiffOutput, Box<dyn std::error::Error + Send + Sync>> {
        let before = self.before.take().ok_or("No 'before' image stored")?;

        let (bw, bh) = before.dimensions();
        let (aw, ah) = after.dimensions();

        // Use the larger dimensions for the output
        let max_w = bw.max(aw);
        let max_h = bh.max(ah);

        // Create side-by-side image: [before] | divider | [after]
        let divider_width = 4u32;
        let combined_width = max_w * 2 + divider_width;
        let mut combined = RgbaImage::new(combined_width, max_h);

        // Fill with dark background
        for pixel in combined.pixels_mut() {
            *pixel = Rgba([30, 30, 30, 255]);
        }

        // Draw "before" on the left
        for y in 0..bh {
            for x in 0..bw {
                combined.put_pixel(x, y, *before.get_pixel(x, y));
            }
        }

        // Draw divider line (white)
        for y in 0..max_h {
            for dx in 0..divider_width {
                combined.put_pixel(max_w + dx, y, Rgba([200, 200, 200, 255]));
            }
        }

        // Draw "after" on the right
        let right_offset = max_w + divider_width;
        for y in 0..ah {
            for x in 0..aw {
                combined.put_pixel(right_offset + x, y, *after.get_pixel(x, y));
            }
        }

        // Calculate pixel differences and highlight changes
        let compare_w = bw.min(aw);
        let compare_h = bh.min(ah);
        let mut changed_pixels = 0u64;
        let total_pixels = (compare_w as u64) * (compare_h as u64);
        let threshold = 30u8; // Color difference threshold

        // Track changed regions using a grid
        let grid_size = 16u32;
        let grid_cols = (compare_w + grid_size - 1) / grid_size;
        let grid_rows = (compare_h + grid_size - 1) / grid_size;
        let mut change_grid = vec![false; (grid_cols * grid_rows) as usize];

        for y in 0..compare_h {
            for x in 0..compare_w {
                let bp = before.get_pixel(x, y).0;
                let ap = after.get_pixel(x, y).0;

                let diff = (bp[0] as i16 - ap[0] as i16).unsigned_abs() as u8
                    + (bp[1] as i16 - ap[1] as i16).unsigned_abs() as u8
                    + (bp[2] as i16 - ap[2] as i16).unsigned_abs() as u8;

                if diff > threshold {
                    changed_pixels += 1;

                    // Mark grid cell as changed
                    let gx = x / grid_size;
                    let gy = y / grid_size;
                    change_grid[(gy * grid_cols + gx) as usize] = true;

                    // Highlight on the "after" side with red tint
                    let pixel = combined.get_pixel_mut(right_offset + x, y);
                    let r = (pixel.0[0] as u16 + 100).min(255) as u8;
                    let g = pixel.0[1].saturating_sub(30);
                    let b = pixel.0[2].saturating_sub(30);
                    *pixel = Rgba([r, g, b, 255]);
                }
            }
        }

        let change_percentage = if total_pixels > 0 {
            (changed_pixels as f32 / total_pixels as f32) * 100.0
        } else {
            0.0
        };

        // Extract change regions from grid
        let change_regions = extract_change_regions(&change_grid, grid_cols, grid_rows, grid_size);

        // Encode to PNG
        let mut png_bytes = Vec::new();
        let encoder = image::codecs::png::PngEncoder::new(Cursor::new(&mut png_bytes));
        image::ImageEncoder::write_image(
            encoder,
            combined.as_raw(),
            combined_width,
            max_h,
            image::ExtendedColorType::Rgba8,
        )?;

        Ok(DiffOutput {
            side_by_side_bytes: png_bytes,
            change_percentage,
            change_regions,
            file_path: None,
        })
    }
}

/// Extract rectangular change regions from the boolean grid.
fn extract_change_regions(
    grid: &[bool],
    cols: u32,
    rows: u32,
    cell_size: u32,
) -> Vec<ChangeRegion> {
    let mut regions = Vec::new();
    let mut visited = vec![false; grid.len()];

    for gy in 0..rows {
        for gx in 0..cols {
            let idx = (gy * cols + gx) as usize;
            if grid[idx] && !visited[idx] {
                // Flood-fill to find extent of this changed region
                let mut max_gx = gx;
                let mut max_gy = gy;

                // Expand right
                while max_gx + 1 < cols && grid[(gy * cols + max_gx + 1) as usize] {
                    max_gx += 1;
                }

                // Expand down
                'outer: while max_gy + 1 < rows {
                    for x in gx..=max_gx {
                        if !grid[((max_gy + 1) * cols + x) as usize] {
                            break 'outer;
                        }
                    }
                    max_gy += 1;
                }

                // Mark visited
                for y in gy..=max_gy {
                    for x in gx..=max_gx {
                        visited[(y * cols + x) as usize] = true;
                    }
                }

                regions.push(ChangeRegion {
                    x: gx * cell_size,
                    y: gy * cell_size,
                    width: (max_gx - gx + 1) * cell_size,
                    height: (max_gy - gy + 1) * cell_size,
                });
            }
        }
    }

    regions
}
