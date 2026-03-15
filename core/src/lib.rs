pub mod api;
pub mod ffi;
pub mod output;
pub mod processing;
pub mod targets;

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;

use crate::output::file::OutputManager;
use crate::processing::diff::DiffEngine;
use crate::processing::gif::GifSessionManager;
use crate::targets::companion::CompanionManager;

pub static APP_STATE: RwLock<Option<Arc<AppState>>> = RwLock::new(None);

pub struct AppState {
    pub output_manager: OutputManager,
    pub diff_engine: RwLock<DiffEngine>,
    pub gif_sessions: RwLock<GifSessionManager>,
    pub companion_manager: RwLock<CompanionManager>,
    pub capture_callback: RwLock<Option<ffi::CaptureCallback>>,
    pub latest_capture: RwLock<Option<ProcessedCapture>>,
    pub api_port: RwLock<u16>,
    pub config: Config,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub port: u16,
    #[serde(default = "default_output_dir")]
    pub output_dir: PathBuf,
    #[serde(default = "default_max_width")]
    pub max_image_width: u32,
    #[serde(default = "default_gif_fps")]
    pub gif_fps: u32,
    #[serde(default = "default_jpeg_quality")]
    pub jpeg_quality: u8,
    #[serde(default = "default_cleanup_days")]
    pub cleanup_max_age_days: u32,
}

fn default_output_dir() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".screenshottool")
}

fn default_max_width() -> u32 {
    1280
}

fn default_gif_fps() -> u32 {
    10
}

fn default_jpeg_quality() -> u8 {
    85
}

fn default_cleanup_days() -> u32 {
    30
}

impl Default for Config {
    fn default() -> Self {
        Config {
            port: 0,
            output_dir: default_output_dir(),
            max_image_width: default_max_width(),
            gif_fps: default_gif_fps(),
            jpeg_quality: default_jpeg_quality(),
            cleanup_max_age_days: default_cleanup_days(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ProcessedCapture {
    pub image_bytes: Vec<u8>,
    pub format: ImageOutputFormat,
    pub width: u32,
    pub height: u32,
    pub file_path: PathBuf,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageOutputFormat {
    Png,
    Jpeg,
}

pub fn init(config: &Config) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    tracing_subscriber::fmt::init();
    tracing::info!("Initializing screenshottool core");

    let output_manager = OutputManager::new(&config.output_dir)?;

    let state = Arc::new(AppState {
        output_manager,
        diff_engine: RwLock::new(DiffEngine::new()),
        gif_sessions: RwLock::new(GifSessionManager::new()),
        companion_manager: RwLock::new(CompanionManager::new()),
        capture_callback: RwLock::new(None),
        latest_capture: RwLock::new(None),
        api_port: RwLock::new(0),
        config: config.clone(),
    });

    {
        let mut global = APP_STATE.write();
        *global = Some(state.clone());
    }

    // Start HTTP API server in background
    let api_state = state.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let port = api::server::start_server(api_state.clone()).await.unwrap();
            *api_state.api_port.write() = port;

            // Write api.json
            let api_json = serde_json::json!({
                "port": port,
                "pid": std::process::id(),
            });
            let api_json_path = api_state.config.output_dir.join("api.json");
            if let Ok(json_str) = serde_json::to_string_pretty(&api_json) {
                let _ = std::fs::write(&api_json_path, json_str);
            }

            tracing::info!("HTTP API started on port {}", port);

            // Keep the runtime alive
            tokio::signal::ctrl_c().await.ok();
        });
    });

    // Start companion listener in background
    let companion_state = state.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            if let Err(e) = companion_state
                .companion_manager
                .write()
                .start_listener()
                .await
            {
                tracing::warn!("Failed to start companion listener: {}", e);
            }
        });
    });

    Ok(())
}

pub fn shutdown() {
    tracing::info!("Shutting down screenshottool core");
    let mut global = APP_STATE.write();
    if let Some(state) = global.take() {
        // Clean up api.json
        let api_json_path = state.config.output_dir.join("api.json");
        let _ = std::fs::remove_file(api_json_path);
    }
}

pub fn get_state() -> Option<Arc<AppState>> {
    APP_STATE.read().clone()
}

// Public Rust API (used by Linux frontend directly, no FFI needed)

pub fn process_screenshot(
    pixels: &[u8],
    width: u32,
    height: u32,
    stride: u32,
) -> Result<ProcessedCapture, Box<dyn std::error::Error + Send + Sync>> {
    let state = get_state().ok_or("Core not initialized")?;
    let img = processing::image::raw_pixels_to_image(pixels, width, height, stride)?;
    let capture = output::optimize::optimize_for_ai(&img, &state.config)?;
    let saved = state.output_manager.save_screenshot(&capture.image_bytes)?;
    let result = ProcessedCapture {
        file_path: saved,
        ..capture
    };
    *state.latest_capture.write() = Some(result.clone());
    Ok(result)
}

pub fn gif_start() -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let state = get_state().ok_or("Core not initialized")?;
    let id = state.gif_sessions.write().create_session();
    Ok(id)
}

pub fn gif_add_frame(
    session_id: &str,
    pixels: &[u8],
    width: u32,
    height: u32,
    stride: u32,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let state = get_state().ok_or("Core not initialized")?;
    state
        .gif_sessions
        .write()
        .add_frame(session_id, pixels, width, height, stride)?;
    Ok(())
}

pub fn gif_finish(
    session_id: &str,
) -> Result<ProcessedCapture, Box<dyn std::error::Error + Send + Sync>> {
    let state = get_state().ok_or("Core not initialized")?;
    let gif_bytes = state.gif_sessions.write().finish_session(session_id)?;
    let saved = state.output_manager.save_gif(&gif_bytes)?;
    Ok(ProcessedCapture {
        image_bytes: gif_bytes,
        format: ImageOutputFormat::Png, // GIF actually, but we reuse the struct
        width: 0,
        height: 0,
        file_path: saved,
    })
}

pub fn diff_store_before(
    pixels: &[u8],
    width: u32,
    height: u32,
    stride: u32,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let state = get_state().ok_or("Core not initialized")?;
    let img = processing::image::raw_pixels_to_image(pixels, width, height, stride)?;
    state.diff_engine.write().store_before(img);
    Ok(())
}

pub fn diff_compare(
    pixels: &[u8],
    width: u32,
    height: u32,
    stride: u32,
) -> Result<processing::diff::DiffOutput, Box<dyn std::error::Error + Send + Sync>> {
    let state = get_state().ok_or("Core not initialized")?;
    let img = processing::image::raw_pixels_to_image(pixels, width, height, stride)?;
    let output = state.diff_engine.write().compare(img)?;
    let _ = state
        .output_manager
        .save_diff(&output.side_by_side_bytes);
    Ok(output)
}

pub fn get_latest() -> Option<ProcessedCapture> {
    let state = get_state()?;
    let result = state.latest_capture.read().clone();
    result
}

pub fn list_companions() -> Vec<targets::companion::CompanionDevice> {
    get_state()
        .map(|s| s.companion_manager.read().list_devices())
        .unwrap_or_default()
}
