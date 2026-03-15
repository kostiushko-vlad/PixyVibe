/// Screen capture for Linux.
/// Uses XDG Desktop Portal (Wayland) or X11 fallback.

/// Capture a region of the screen.
/// Returns RGBA pixel data, width, and height.
pub fn capture_region(
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Result<(Vec<u8>, u32, u32), Box<dyn std::error::Error>> {
    // Try XDG Desktop Portal first (works on Wayland + modern X11)
    if let Ok(result) = capture_via_portal(x, y, width, height) {
        return Ok(result);
    }

    // Fallback: use gnome-screenshot or similar CLI tool
    capture_via_cli(x, y, width, height)
}

fn capture_via_portal(
    _x: u32,
    _y: u32,
    _width: u32,
    _height: u32,
) -> Result<(Vec<u8>, u32, u32), Box<dyn std::error::Error>> {
    // ashpd (XDG Desktop Portal) integration would go here
    // For now, return an error to fall through to CLI
    Err("Portal capture not yet implemented".into())
}

fn capture_via_cli(
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Result<(Vec<u8>, u32, u32), Box<dyn std::error::Error>> {
    use std::process::Command;

    let temp_path = "/tmp/pixyvibe_capture.png";

    // Try gnome-screenshot
    let result = Command::new("gnome-screenshot")
        .args([
            "-a",
            &format!("--area={},{},{},{}", x, y, width, height),
            "-f",
            temp_path,
        ])
        .output();

    if result.is_err() {
        // Fallback to scrot
        Command::new("scrot")
            .args([
                "-a",
                &format!("{},{},{},{}", x, y, width, height),
                temp_path,
            ])
            .output()?;
    }

    // Load the captured PNG and convert to RGBA pixels
    let img = image::open(temp_path)?;
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let pixels = rgba.into_raw();

    // Clean up temp file
    let _ = std::fs::remove_file(temp_path);

    Ok((pixels, w, h))
}
