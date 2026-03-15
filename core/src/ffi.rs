use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Screenshot result passed across FFI boundary
#[repr(C)]
pub struct FFIScreenshotResult {
    pub image_data: *mut u8,
    pub image_len: usize,
    pub file_path: *mut c_char,
    pub error: *mut c_char,
}

/// Raw pixel data received from the native capture layer
#[repr(C)]
pub struct FFIPixelData {
    pub pixels: *const u8,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
}

/// Diff result
#[repr(C)]
pub struct FFIDiffResult {
    pub image_data: *mut u8,
    pub image_len: usize,
    pub file_path: *mut c_char,
    pub change_percentage: f32,
    pub error: *mut c_char,
}

/// Capture callback — native app provides this so MCP/HTTP API can request captures
pub type CaptureCallback = extern "C" fn(u32, u32, u32, u32) -> FFIPixelData;

// Helper to create error result
fn error_result(msg: &str) -> FFIScreenshotResult {
    FFIScreenshotResult {
        image_data: std::ptr::null_mut(),
        image_len: 0,
        file_path: std::ptr::null_mut(),
        error: CString::new(msg).unwrap_or_default().into_raw(),
    }
}

fn error_diff_result(msg: &str) -> FFIDiffResult {
    FFIDiffResult {
        image_data: std::ptr::null_mut(),
        image_len: 0,
        file_path: std::ptr::null_mut(),
        change_percentage: 0.0,
        error: CString::new(msg).unwrap_or_default().into_raw(),
    }
}

fn success_result(capture: &crate::ProcessedCapture) -> FFIScreenshotResult {
    let mut bytes = capture.image_bytes.clone();
    let data_ptr = bytes.as_mut_ptr();
    let data_len = bytes.len();
    std::mem::forget(bytes);

    let path = CString::new(capture.file_path.to_string_lossy().as_ref())
        .unwrap_or_default()
        .into_raw();

    FFIScreenshotResult {
        image_data: data_ptr,
        image_len: data_len,
        file_path: path,
        error: std::ptr::null_mut(),
    }
}

unsafe fn pixel_data_to_slice(pixels: &FFIPixelData) -> Option<&[u8]> {
    if pixels.pixels.is_null() || pixels.width == 0 || pixels.height == 0 {
        return None;
    }
    let total_bytes = pixels.stride as usize * pixels.height as usize;
    Some(std::slice::from_raw_parts(pixels.pixels, total_bytes))
}

/// Initialize the core library (call once at app startup)
#[no_mangle]
pub extern "C" fn sst_init(config_json: *const c_char) -> bool {
    let config = if config_json.is_null() {
        crate::Config::default()
    } else {
        let c_str = unsafe { CStr::from_ptr(config_json) };
        match c_str.to_str() {
            Ok(s) => serde_json::from_str(s).unwrap_or_default(),
            Err(_) => crate::Config::default(),
        }
    };

    match crate::init(&config) {
        Ok(()) => true,
        Err(e) => {
            tracing::error!("Failed to initialize: {}", e);
            false
        }
    }
}

/// Shutdown the core library
#[no_mangle]
pub extern "C" fn sst_shutdown() {
    crate::shutdown();
}

/// Register the native capture function
#[no_mangle]
pub extern "C" fn sst_register_capture_callback(callback: CaptureCallback) {
    if let Some(state) = crate::get_state() {
        *state.capture_callback.write() = Some(callback);
        tracing::info!("Capture callback registered");
    }
}

/// Process a screenshot captured by the native layer
#[no_mangle]
pub extern "C" fn sst_process_screenshot(pixels: FFIPixelData) -> FFIScreenshotResult {
    let slice = match unsafe { pixel_data_to_slice(&pixels) } {
        Some(s) => s,
        None => return error_result("Invalid pixel data"),
    };

    match crate::process_screenshot(slice, pixels.width, pixels.height, pixels.stride) {
        Ok(capture) => success_result(&capture),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Start a new GIF recording session
#[no_mangle]
pub extern "C" fn sst_gif_start() -> *mut c_char {
    match crate::gif_start() {
        Ok(id) => CString::new(id).unwrap_or_default().into_raw(),
        Err(e) => {
            tracing::error!("Failed to start GIF session: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Add a frame to the active GIF recording
#[no_mangle]
pub extern "C" fn sst_gif_add_frame(
    session_id: *const c_char,
    pixels: FFIPixelData,
) -> bool {
    if session_id.is_null() {
        return false;
    }
    let id = match unsafe { CStr::from_ptr(session_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };
    let slice = match unsafe { pixel_data_to_slice(&pixels) } {
        Some(s) => s,
        None => return false,
    };

    crate::gif_add_frame(id, slice, pixels.width, pixels.height, pixels.stride).is_ok()
}

/// Stop GIF recording and encode all collected frames
#[no_mangle]
pub extern "C" fn sst_gif_finish(session_id: *const c_char) -> FFIScreenshotResult {
    if session_id.is_null() {
        return error_result("Null session ID");
    }
    let id = match unsafe { CStr::from_ptr(session_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return error_result("Invalid session ID string"),
    };

    match crate::gif_finish(id) {
        Ok(capture) => success_result(&capture),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Store a "before" image for diff comparison
#[no_mangle]
pub extern "C" fn sst_diff_store_before(pixels: FFIPixelData) -> bool {
    let slice = match unsafe { pixel_data_to_slice(&pixels) } {
        Some(s) => s,
        None => return false,
    };
    crate::diff_store_before(slice, pixels.width, pixels.height, pixels.stride).is_ok()
}

/// Compare "after" image against stored "before" and generate diff
#[no_mangle]
pub extern "C" fn sst_diff_compare(pixels: FFIPixelData) -> FFIDiffResult {
    let slice = match unsafe { pixel_data_to_slice(&pixels) } {
        Some(s) => s,
        None => return error_diff_result("Invalid pixel data"),
    };

    match crate::diff_compare(slice, pixels.width, pixels.height, pixels.stride) {
        Ok(output) => {
            let mut bytes = output.side_by_side_bytes.clone();
            let data_ptr = bytes.as_mut_ptr();
            let data_len = bytes.len();
            std::mem::forget(bytes);

            let path = CString::new(
                output
                    .file_path
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_default(),
            )
            .unwrap_or_default()
            .into_raw();

            FFIDiffResult {
                image_data: data_ptr,
                image_len: data_len,
                file_path: path,
                change_percentage: output.change_percentage,
                error: std::ptr::null_mut(),
            }
        }
        Err(e) => error_diff_result(&e.to_string()),
    }
}

/// Get latest processed screenshot as PNG bytes
#[no_mangle]
pub extern "C" fn sst_get_latest() -> FFIScreenshotResult {
    match crate::get_latest() {
        Some(capture) => success_result(&capture),
        None => error_result("No captures available"),
    }
}

/// Get connected companion devices as JSON string
#[no_mangle]
pub extern "C" fn sst_list_companions() -> *mut c_char {
    let devices = crate::list_companions();
    let json = serde_json::to_string(&devices).unwrap_or_else(|_| "[]".to_string());
    CString::new(json).unwrap_or_default().into_raw()
}

/// Request screenshot from a companion device
#[no_mangle]
pub extern "C" fn sst_companion_screenshot(device_id: *const c_char) -> FFIScreenshotResult {
    if device_id.is_null() {
        return error_result("Null device ID");
    }
    let _id = match unsafe { CStr::from_ptr(device_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return error_result("Invalid device ID string"),
    };

    // TODO: implement companion screenshot request via WebSocket
    error_result("Companion screenshot not yet implemented")
}

/// Free memory allocated by the core library for screenshot results
#[no_mangle]
pub extern "C" fn sst_free_result(result: FFIScreenshotResult) {
    unsafe {
        if !result.image_data.is_null() {
            let _ = Vec::from_raw_parts(result.image_data, result.image_len, result.image_len);
        }
        if !result.file_path.is_null() {
            let _ = CString::from_raw(result.file_path);
        }
        if !result.error.is_null() {
            let _ = CString::from_raw(result.error);
        }
    }
}

/// Free memory allocated by the core library for diff results
#[no_mangle]
pub extern "C" fn sst_free_diff_result(result: FFIDiffResult) {
    unsafe {
        if !result.image_data.is_null() {
            let _ = Vec::from_raw_parts(result.image_data, result.image_len, result.image_len);
        }
        if !result.file_path.is_null() {
            let _ = CString::from_raw(result.file_path);
        }
        if !result.error.is_null() {
            let _ = CString::from_raw(result.error);
        }
    }
}

/// Free a string allocated by the core library
#[no_mangle]
pub extern "C" fn sst_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}
