use image::RgbaImage;
use std::collections::HashMap;
use std::time::Instant;

use super::image::{frames_identical, raw_pixels_to_image, resize_to_fit};

pub struct GifSession {
    pub id: String,
    frames: Vec<(RgbaImage, Instant)>,
    start_time: Instant,
}

impl GifSession {
    pub fn new(id: String) -> Self {
        GifSession {
            id,
            frames: Vec::new(),
            start_time: Instant::now(),
        }
    }

    /// Add a frame from raw pixel data. Deduplicates identical consecutive frames.
    pub fn add_frame(
        &mut self,
        pixels: &[u8],
        width: u32,
        height: u32,
        stride: u32,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let image = raw_pixels_to_image(pixels, width, height, stride)?;

        // Skip if identical to previous frame
        if let Some((last, _)) = self.frames.last() {
            if frames_identical(last, &image) {
                return Ok(());
            }
        }

        self.frames.push((image, Instant::now()));
        Ok(())
    }

    /// Encode all collected frames into a GIF.
    pub fn finish(self) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
        if self.frames.is_empty() {
            return Err("No frames recorded".into());
        }

        let max_gif_width = 800u32;
        let max_gif_height = 600u32;

        // Resize all frames
        let resized_frames: Vec<(RgbaImage, Instant)> = self
            .frames
            .into_iter()
            .map(|(img, time)| (resize_to_fit(&img, max_gif_width, max_gif_height), time))
            .collect();

        let (first_w, first_h) = resized_frames[0].0.dimensions();

        let mut output = Vec::new();
        {
            let mut encoder = gif::Encoder::new(&mut output, first_w as u16, first_h as u16, &[])
                .map_err(|e| format!("GIF encoder init failed: {}", e))?;

            encoder
                .set_repeat(gif::Repeat::Infinite)
                .map_err(|e| format!("Failed to set repeat: {}", e))?;

            for i in 0..resized_frames.len() {
                let (ref img, ref time) = resized_frames[i];

                // Calculate delay in centiseconds (1/100th of a second)
                let delay = if i + 1 < resized_frames.len() {
                    let duration = resized_frames[i + 1].1.duration_since(*time);
                    (duration.as_millis() / 10) as u16
                } else {
                    10 // Default 100ms for last frame
                };

                let delay = delay.max(2); // Minimum 20ms per GIF spec

                // Convert RGBA to RGB for GIF encoding
                let rgba = img.as_raw();
                let mut rgb: Vec<u8> = Vec::with_capacity((first_w * first_h * 3) as usize);
                for chunk in rgba.chunks(4) {
                    rgb.push(chunk[0]);
                    rgb.push(chunk[1]);
                    rgb.push(chunk[2]);
                }

                let mut frame =
                    gif::Frame::from_rgb(first_w as u16, first_h as u16, &rgb);
                frame.delay = delay;
                frame.dispose = gif::DisposalMethod::Any;

                encoder
                    .write_frame(&frame)
                    .map_err(|e| format!("Failed to write GIF frame: {}", e))?;
            }
        }

        Ok(output)
    }

    pub fn frame_count(&self) -> usize {
        self.frames.len()
    }

    pub fn elapsed(&self) -> std::time::Duration {
        self.start_time.elapsed()
    }
}

pub struct GifSessionManager {
    sessions: HashMap<String, GifSession>,
}

impl GifSessionManager {
    pub fn new() -> Self {
        GifSessionManager {
            sessions: HashMap::new(),
        }
    }

    pub fn create_session(&mut self) -> String {
        let id = uuid::Uuid::new_v4().to_string();
        let session = GifSession::new(id.clone());
        self.sessions.insert(id.clone(), session);
        id
    }

    pub fn add_frame(
        &mut self,
        session_id: &str,
        pixels: &[u8],
        width: u32,
        height: u32,
        stride: u32,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let session = self
            .sessions
            .get_mut(session_id)
            .ok_or_else(|| format!("GIF session not found: {}", session_id))?;
        session.add_frame(pixels, width, height, stride)
    }

    pub fn finish_session(
        &mut self,
        session_id: &str,
    ) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
        let session = self
            .sessions
            .remove(session_id)
            .ok_or_else(|| format!("GIF session not found: {}", session_id))?;
        session.finish()
    }

    pub fn get_session_info(&self, session_id: &str) -> Option<(usize, std::time::Duration)> {
        self.sessions
            .get(session_id)
            .map(|s| (s.frame_count(), s.elapsed()))
    }
}
