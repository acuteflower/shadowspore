//! Read-only access to the game's own content for the launcher UI:
//! the changelog, the screenshots it references and a few safe external links.

use std::path::{Component, Path, PathBuf};

use base64::Engine;

use crate::game::find_project_dir;

/// Only links into the game's own GitHub repository may be opened.
const LINK_PREFIX: &str = "https://github.com/acuteflower/shadowspore";
/// Largest picture the launcher will inline (data URLs live in memory).
const MAX_IMAGE_BYTES: u64 = 12 * 1024 * 1024;

/// The project's CHANGELOG.md, or an empty string when no project folder is found
/// (the frontend then falls back to the copy bundled at build time).
pub fn read_changelog() -> String {
    let Some(dir) = find_project_dir() else {
        return String::new();
    };
    std::fs::read_to_string(dir.join("CHANGELOG.md")).unwrap_or_default()
}

/// A picture from `docs/img/` as a data URL. Any other location is refused.
pub fn read_doc_image(rel: &str) -> Result<String, String> {
    let rel = rel.trim().replace('\\', "/");
    let rel_path = Path::new(&rel);
    let mut parts = rel_path.components();
    let starts_ok = matches!(parts.next(), Some(Component::Normal(a)) if a == "docs")
        && matches!(parts.next(), Some(Component::Normal(b)) if b == "img");
    let clean = rel_path.components().all(|c| matches!(c, Component::Normal(_)));
    if !starts_ok || !clean {
        return Err("Nur Bilder aus docs/img sind erlaubt.".to_string());
    }
    let mime = match rel_path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .as_deref()
    {
        Some("png") => "image/png",
        Some("gif") => "image/gif",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("webp") => "image/webp",
        _ => return Err("Unbekanntes Bildformat.".to_string()),
    };
    let dir: PathBuf = find_project_dir().ok_or_else(|| "Projektordner nicht gefunden.".to_string())?;
    let path = dir.join(rel_path);
    let meta = std::fs::metadata(&path).map_err(|_| format!("Bild fehlt: {}", rel))?;
    if meta.len() > MAX_IMAGE_BYTES {
        return Err("Bild ist zu gross.".to_string());
    }
    let bytes = std::fs::read(&path).map_err(|e| format!("Bild nicht lesbar: {}", e))?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(bytes);
    Ok(format!("data:{};base64,{}", mime, b64))
}

/// Opens a link of the game's repository in the system browser.
pub fn open_external(url: &str) -> Result<(), String> {
    let url = url.trim();
    let allowed = url == LINK_PREFIX
        || url.starts_with(&format!("{}/", LINK_PREFIX))
        || url.starts_with(&format!("{}#", LINK_PREFIX));
    let safe_chars = url
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || "-._~:/?#[]@!$&'()*+,;=%".contains(c));
    if !allowed || !safe_chars {
        return Err("Dieser Link ist nicht erlaubt.".to_string());
    }
    #[cfg(target_os = "windows")]
    let result = std::process::Command::new("rundll32")
        .args(["url.dll,FileProtocolHandler", url])
        .spawn();
    #[cfg(target_os = "macos")]
    let result = std::process::Command::new("open").arg(url).spawn();
    #[cfg(all(unix, not(target_os = "macos")))]
    let result = std::process::Command::new("xdg-open").arg(url).spawn();
    result.map(|_| ()).map_err(|e| format!("Browser konnte nicht geöffnet werden: {}", e))
}
