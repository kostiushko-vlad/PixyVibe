use image::{ImageBuffer, RgbaImage};

/// Convert raw pixel buffer from native capture into an RgbaImage.
/// Handles stride padding (rows may be wider than width * 4 bytes).
pub fn raw_pixels_to_image(
    pixels: &[u8],
    width: u32,
    height: u32,
    stride: u32,
) -> Result<RgbaImage, Box<dyn std::error::Error + Send + Sync>> {
    let bytes_per_pixel = 4u32;
    let row_bytes = width * bytes_per_pixel;

    if stride == row_bytes {
        // No padding — use pixels directly
        let expected = (width * height * bytes_per_pixel) as usize;
        if pixels.len() < expected {
            return Err(format!(
                "Pixel buffer too small: got {}, expected {}",
                pixels.len(),
                expected
            )
            .into());
        }
        ImageBuffer::from_raw(width, height, pixels[..expected].to_vec())
            .ok_or_else(|| "Failed to create image from raw pixels".into())
    } else {
        // Stride has padding — copy row by row
        let mut raw = Vec::with_capacity((width * height * bytes_per_pixel) as usize);
        for y in 0..height {
            let row_start = (y * stride) as usize;
            let row_end = row_start + row_bytes as usize;
            if row_end > pixels.len() {
                return Err(format!(
                    "Pixel buffer too small at row {}: need {}, have {}",
                    y,
                    row_end,
                    pixels.len()
                )
                .into());
            }
            raw.extend_from_slice(&pixels[row_start..row_end]);
        }
        ImageBuffer::from_raw(width, height, raw)
            .ok_or_else(|| "Failed to create image from raw pixels".into())
    }
}

/// Check if two images are identical by sampling pixels.
/// Faster than full comparison for deduplication.
pub fn frames_identical(a: &RgbaImage, b: &RgbaImage) -> bool {
    if a.dimensions() != b.dimensions() {
        return false;
    }

    let (w, h) = a.dimensions();
    let total_pixels = (w * h) as usize;

    if total_pixels == 0 {
        return true;
    }

    // Sample ~100 evenly distributed pixels
    let sample_count = 100.min(total_pixels);
    let step = total_pixels / sample_count;

    for i in 0..sample_count {
        let idx = i * step;
        let x = (idx % w as usize) as u32;
        let y = (idx / w as usize) as u32;
        if a.get_pixel(x, y) != b.get_pixel(x, y) {
            return false;
        }
    }

    true
}

/// Resize image to fit within max dimensions while maintaining aspect ratio.
pub fn resize_to_fit(img: &RgbaImage, max_width: u32, max_height: u32) -> RgbaImage {
    let (w, h) = img.dimensions();
    if w <= max_width && h <= max_height {
        return img.clone();
    }

    let scale_w = max_width as f64 / w as f64;
    let scale_h = max_height as f64 / h as f64;
    let scale = scale_w.min(scale_h);

    let new_w = (w as f64 * scale).round() as u32;
    let new_h = (h as f64 * scale).round() as u32;

    image::imageops::resize(img, new_w, new_h, image::imageops::FilterType::Lanczos3)
}

/// Check if image has any transparent pixels.
pub fn has_transparency(img: &RgbaImage) -> bool {
    img.pixels().any(|p| p.0[3] < 255)
}
