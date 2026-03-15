use image::RgbaImage;
use std::io::Cursor;

use crate::processing::image::{has_transparency, resize_to_fit};
use crate::{Config, ImageOutputFormat, ProcessedCapture};

/// Optimize an image for AI consumption.
/// Resizes to max width, compresses, and strips alpha if opaque.
pub fn optimize_for_ai(
    img: &RgbaImage,
    config: &Config,
) -> Result<ProcessedCapture, Box<dyn std::error::Error + Send + Sync>> {
    let max_width = config.max_image_width;
    let max_height = max_width * 2; // Allow tall screenshots

    // Resize if needed
    let resized = resize_to_fit(img, max_width, max_height);
    let (width, height) = resized.dimensions();

    // Try PNG first
    let png_bytes = encode_png(&resized)?;

    // If PNG is too large (>500KB), try JPEG
    if png_bytes.len() > 500_000 && !has_transparency(&resized) {
        let jpeg_bytes = encode_jpeg(&resized, config.jpeg_quality)?;
        if jpeg_bytes.len() < png_bytes.len() {
            return Ok(ProcessedCapture {
                image_bytes: jpeg_bytes,
                format: ImageOutputFormat::Jpeg,
                width,
                height,
                file_path: std::path::PathBuf::new(), // Caller sets this
            });
        }
    }

    Ok(ProcessedCapture {
        image_bytes: png_bytes,
        format: ImageOutputFormat::Png,
        width,
        height,
        file_path: std::path::PathBuf::new(), // Caller sets this
    })
}

fn encode_png(img: &RgbaImage) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    let mut buf = Vec::new();
    let encoder = image::codecs::png::PngEncoder::new_with_quality(
        Cursor::new(&mut buf),
        image::codecs::png::CompressionType::Best,
        image::codecs::png::FilterType::Adaptive,
    );
    let (w, h) = img.dimensions();
    image::ImageEncoder::write_image(encoder, img.as_raw(), w, h, image::ExtendedColorType::Rgba8)?;
    Ok(buf)
}

fn encode_jpeg(
    img: &RgbaImage,
    quality: u8,
) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    // Convert RGBA to RGB for JPEG
    let (w, h) = img.dimensions();
    let rgb_img = image::DynamicImage::ImageRgba8(img.clone()).to_rgb8();

    let mut buf = Vec::new();
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(
        Cursor::new(&mut buf),
        quality,
    );
    image::ImageEncoder::write_image(
        encoder,
        rgb_img.as_raw(),
        w,
        h,
        image::ExtendedColorType::Rgb8,
    )?;
    Ok(buf)
}
