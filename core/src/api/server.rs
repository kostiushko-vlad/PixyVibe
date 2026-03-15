use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use base64::Engine;
use std::sync::Arc;

use crate::api::*;
use crate::AppState;

type AppError = (StatusCode, Json<ErrorResponse>);

fn internal_error(msg: impl Into<String>) -> AppError {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(ErrorResponse {
            error: msg.into(),
        }),
    )
}

pub async fn start_server(
    state: Arc<AppState>,
) -> Result<u16, Box<dyn std::error::Error + Send + Sync>> {
    let app = Router::new()
        .route("/api/status", get(handle_status))
        .route("/api/targets", get(handle_targets))
        .route("/api/screenshot", post(handle_screenshot))
        .route("/api/gif", post(handle_gif))
        .route("/api/diff/before", post(handle_diff_before))
        .route("/api/diff/after", post(handle_diff_after))
        .route("/api/latest", get(handle_latest))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();

    tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, app).await {
            tracing::error!("HTTP API server error: {}", e);
        }
    });

    Ok(port)
}

async fn handle_status(
    State(state): State<Arc<AppState>>,
) -> Json<StatusResponse> {
    let has_callback = state.capture_callback.read().is_some();
    let companion_count = state.companion_manager.read().list_devices().len();
    let diff_pending = state.diff_engine.read().has_before();

    Json(StatusResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        has_capture_callback: has_callback,
        companion_count,
        active_gif_sessions: 0,
        diff_pending,
    })
}

async fn handle_targets(
    State(state): State<Arc<AppState>>,
) -> Json<Vec<crate::targets::companion::CompanionDevice>> {
    let devices = state.companion_manager.read().list_devices();
    Json(devices)
}

async fn handle_screenshot(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ScreenshotRequest>,
) -> Result<Json<ScreenshotResponse>, AppError> {
    // If target_id specified, try companion device
    if let Some(ref _target_id) = req.target_id {
        return Err(internal_error("Companion screenshot not yet implemented"));
    }

    // Desktop screenshot via capture callback
    let callback = {
        let cb = state.capture_callback.read();
        cb.ok_or_else(|| internal_error("No capture callback registered"))?
    };

    // Determine capture region
    let (x, y, w, h) = match req.region {
        Some(ref r) => (r.x, r.y, r.width, r.height),
        None => (0, 0, 0, 0), // Full screen — native app interprets 0,0,0,0 as full
    };

    // Invoke native capture callback
    let pixel_data = callback(x, y, w, h);
    if pixel_data.pixels.is_null() || pixel_data.width == 0 || pixel_data.height == 0 {
        return Err(internal_error("Capture callback returned empty data"));
    }

    let slice = unsafe {
        let total = pixel_data.stride as usize * pixel_data.height as usize;
        std::slice::from_raw_parts(pixel_data.pixels, total)
    };

    let capture = crate::process_screenshot(
        slice,
        pixel_data.width,
        pixel_data.height,
        pixel_data.stride,
    )
    .map_err(|e| internal_error(e.to_string()))?;

    let b64 = base64::engine::general_purpose::STANDARD.encode(&capture.image_bytes);

    Ok(Json(ScreenshotResponse {
        image_base64: b64,
        metadata: Metadata {
            source_title: "Desktop".to_string(),
            dimensions: format!("{}x{}", capture.width, capture.height),
            timestamp: chrono::Local::now().to_rfc3339(),
            file_path: capture.file_path.to_string_lossy().into_owned(),
        },
    }))
}

async fn handle_gif(
    State(state): State<Arc<AppState>>,
    Json(req): Json<GifRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    match req.action.as_str() {
        "start" => {
            let session_id = state.gif_sessions.write().create_session();

            // Start capture loop using callback
            let callback = {
                let cb = state.capture_callback.read();
                cb.ok_or_else(|| internal_error("No capture callback registered"))?
            };

            let fps = req.fps.unwrap_or(10);
            let (x, y, w, h) = match req.region {
                Some(ref r) => (r.x, r.y, r.width, r.height),
                None => (0, 0, 0, 0),
            };

            let sid = session_id.clone();
            let state_clone = state.clone();
            tokio::spawn(async move {
                let interval = std::time::Duration::from_millis(1000 / fps as u64);
                loop {
                    tokio::time::sleep(interval).await;

                    let pixel_data = callback(x, y, w, h);
                    if pixel_data.pixels.is_null() {
                        continue;
                    }

                    let slice = unsafe {
                        let total = pixel_data.stride as usize * pixel_data.height as usize;
                        std::slice::from_raw_parts(pixel_data.pixels, total)
                    };

                    let _ = state_clone.gif_sessions.write().add_frame(
                        &sid,
                        slice,
                        pixel_data.width,
                        pixel_data.height,
                        pixel_data.stride,
                    );
                }
            });

            Ok(Json(serde_json::json!({
                "session_id": session_id,
                "status": "recording"
            })))
        }
        "stop" => {
            // Find any active session and finish it
            // For simplicity, we need the session_id — could be passed in request
            // For now return an error asking for session_id
            Err(internal_error(
                "Please provide session_id in request to stop GIF",
            ))
        }
        _ => Err(internal_error(format!("Unknown GIF action: {}", req.action))),
    }
}

async fn handle_diff_before(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DiffRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let callback = {
        let cb = state.capture_callback.read();
        cb.ok_or_else(|| internal_error("No capture callback registered"))?
    };

    let (x, y, w, h) = match req.region {
        Some(ref r) => (r.x, r.y, r.width, r.height),
        None => (0, 0, 0, 0),
    };

    let pixel_data = callback(x, y, w, h);
    if pixel_data.pixels.is_null() {
        return Err(internal_error("Capture callback returned empty data"));
    }

    let slice = unsafe {
        let total = pixel_data.stride as usize * pixel_data.height as usize;
        std::slice::from_raw_parts(pixel_data.pixels, total)
    };

    let img = crate::processing::image::raw_pixels_to_image(
        slice,
        pixel_data.width,
        pixel_data.height,
        pixel_data.stride,
    )
    .map_err(|e| internal_error(e.to_string()))?;

    state.diff_engine.write().store_before(img);

    Ok(Json(serde_json::json!({
        "status": "before_captured",
        "message": "Before image stored. Make changes, then call /api/diff/after"
    })))
}

async fn handle_diff_after(
    State(state): State<Arc<AppState>>,
    Json(req): Json<DiffRequest>,
) -> Result<Json<DiffResponse>, AppError> {
    let callback = {
        let cb = state.capture_callback.read();
        cb.ok_or_else(|| internal_error("No capture callback registered"))?
    };

    let (x, y, w, h) = match req.region {
        Some(ref r) => (r.x, r.y, r.width, r.height),
        None => (0, 0, 0, 0),
    };

    let pixel_data = callback(x, y, w, h);
    if pixel_data.pixels.is_null() {
        return Err(internal_error("Capture callback returned empty data"));
    }

    let slice = unsafe {
        let total = pixel_data.stride as usize * pixel_data.height as usize;
        std::slice::from_raw_parts(pixel_data.pixels, total)
    };

    let img = crate::processing::image::raw_pixels_to_image(
        slice,
        pixel_data.width,
        pixel_data.height,
        pixel_data.stride,
    )
    .map_err(|e| internal_error(e.to_string()))?;

    let output = state
        .diff_engine
        .write()
        .compare(img)
        .map_err(|e| internal_error(e.to_string()))?;

    let _ = state
        .output_manager
        .save_diff(&output.side_by_side_bytes);

    let b64 = base64::engine::general_purpose::STANDARD.encode(&output.side_by_side_bytes);

    Ok(Json(DiffResponse {
        diff_base64: b64,
        change_percentage: output.change_percentage,
        file_path: output
            .file_path
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default(),
    }))
}

async fn handle_latest(
    State(state): State<Arc<AppState>>,
) -> Result<Json<ScreenshotResponse>, AppError> {
    let capture = state
        .latest_capture
        .read()
        .clone()
        .ok_or_else(|| internal_error("No captures available"))?;

    let b64 = base64::engine::general_purpose::STANDARD.encode(&capture.image_bytes);

    Ok(Json(ScreenshotResponse {
        image_base64: b64,
        metadata: Metadata {
            source_title: "Desktop".to_string(),
            dimensions: format!("{}x{}", capture.width, capture.height),
            timestamp: chrono::Local::now().to_rfc3339(),
            file_path: capture.file_path.to_string_lossy().into_owned(),
        },
    }))
}
