use chrono::Local;
use std::fs;
use std::path::{Path, PathBuf};

/// Create a symlink at `link` pointing to `target`. Removes existing link first.
fn symlink_latest(target: &Path, link: &Path) {
    let _ = fs::remove_file(link);
    #[cfg(unix)]
    {
        let _ = std::os::unix::fs::symlink(target, link);
    }
}

pub struct OutputManager {
    base_dir: PathBuf,
}

impl OutputManager {
    pub fn new(base_dir: &Path) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        fs::create_dir_all(base_dir)?;

        Ok(OutputManager {
            base_dir: base_dir.to_path_buf(),
        })
    }

    pub fn base_dir(&self) -> &Path {
        &self.base_dir
    }

    /// Save screenshot bytes. Creates timestamped file + overwrites latest.png.
    pub fn save_screenshot(
        &self,
        data: &[u8],
    ) -> Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
        let timestamp = Local::now().format("%Y-%m-%d_%H-%M-%S");
        let filename = format!("{}.png", timestamp);
        let timestamped_path = self.base_dir.join(&filename);
        let latest_path = self.base_dir.join("latest.png");

        fs::write(&timestamped_path, data)?;
        symlink_latest(&timestamped_path, &latest_path);

        tracing::info!("Screenshot saved: {}", timestamped_path.display());
        Ok(timestamped_path)
    }

    /// Save GIF bytes. Creates timestamped file + symlinks latest.gif.
    pub fn save_gif(
        &self,
        data: &[u8],
    ) -> Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
        let timestamp = Local::now().format("%Y-%m-%d_%H-%M-%S");
        let filename = format!("{}.gif", timestamp);
        let timestamped_path = self.base_dir.join(&filename);
        let latest_path = self.base_dir.join("latest.gif");

        fs::write(&timestamped_path, data)?;
        symlink_latest(&timestamped_path, &latest_path);

        tracing::info!("GIF saved: {}", timestamped_path.display());
        Ok(timestamped_path)
    }

    /// Save diff image bytes. Creates timestamped file + symlinks latest_diff.png.
    pub fn save_diff(
        &self,
        data: &[u8],
    ) -> Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
        let timestamp = Local::now().format("%Y-%m-%d_%H-%M-%S");
        let filename = format!("diff_{}.png", timestamp);
        let timestamped_path = self.base_dir.join(&filename);
        let latest_path = self.base_dir.join("latest_diff.png");

        fs::write(&timestamped_path, data)?;
        symlink_latest(&timestamped_path, &latest_path);

        tracing::info!("Diff saved: {}", timestamped_path.display());
        Ok(timestamped_path)
    }

    /// Remove files older than max_age_days.
    pub fn cleanup_old(
        &self,
        max_age_days: u32,
    ) -> Result<u32, Box<dyn std::error::Error + Send + Sync>> {
        let max_age = std::time::Duration::from_secs(max_age_days as u64 * 24 * 60 * 60);
        let now = std::time::SystemTime::now();
        let mut removed = 0u32;

        if let Ok(entries) = fs::read_dir(&self.base_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                // Skip "latest" files
                if path
                    .file_name()
                    .map(|n| n.to_string_lossy().starts_with("latest"))
                    .unwrap_or(false)
                {
                    continue;
                }
                if let Ok(metadata) = entry.metadata() {
                    if let Ok(modified) = metadata.modified() {
                        if let Ok(age) = now.duration_since(modified) {
                            if age > max_age {
                                if fs::remove_file(&path).is_ok() {
                                    removed += 1;
                                }
                            }
                        }
                    }
                }
            }
        }

        if removed > 0 {
            tracing::info!("Cleaned up {} old files", removed);
        }
        Ok(removed)
    }
}
