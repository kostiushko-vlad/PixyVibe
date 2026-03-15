pub mod server;

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct ScreenshotRequest {
    pub target_id: Option<String>,
    pub region: Option<Region>,
}

#[derive(Debug, Deserialize)]
pub struct Region {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Deserialize)]
pub struct GifRequest {
    pub action: String,
    pub target_id: Option<String>,
    pub fps: Option<u32>,
    pub region: Option<Region>,
}

#[derive(Debug, Deserialize)]
pub struct DiffRequest {
    pub target_id: Option<String>,
    pub region: Option<Region>,
}

#[derive(Debug, Serialize)]
pub struct ScreenshotResponse {
    pub image_base64: String,
    pub metadata: Metadata,
}

#[derive(Debug, Serialize)]
pub struct Metadata {
    pub source_title: String,
    pub dimensions: String,
    pub timestamp: String,
    pub file_path: String,
}

#[derive(Debug, Serialize)]
pub struct GifResponse {
    pub gif_base64: String,
    pub frame_count: usize,
    pub duration_seconds: f64,
    pub file_path: String,
}

#[derive(Debug, Serialize)]
pub struct DiffResponse {
    pub diff_base64: String,
    pub change_percentage: f32,
    pub file_path: String,
}

#[derive(Debug, Serialize)]
pub struct StatusResponse {
    pub status: String,
    pub version: String,
    pub has_capture_callback: bool,
    pub companion_count: usize,
    pub active_gif_sessions: usize,
    pub diff_pending: bool,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
}
