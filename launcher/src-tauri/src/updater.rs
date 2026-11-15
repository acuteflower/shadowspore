//! Verified ZIP downloader & installer for Shadowspore release builds.

use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};

use futures_util::StreamExt;
use reqwest::Client;
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Emitter};
use zip::ZipArchive;

use crate::game::{self, RemoteManifest};
use crate::models::{GameStatusView, PersistedState, UpdateProgressPayload};

fn emit_progress(
    app: &AppHandle,
    stage: &str,
    downloaded_bytes: u64,
    total_bytes: u64,
    message: &str,
) {
    let percent = if total_bytes > 0 {
        ((downloaded_bytes.saturating_mul(100)) / total_bytes).min(100) as u8
    } else if stage == "done" {
        100
    } else {
        0
    };
    let _ = app.emit(
        "updater://progress",
        UpdateProgressPayload {
            stage: stage.to_string(),
            downloaded_bytes,
            total_bytes,
            percent,
            message: message.to_string(),
        },
    );
}

pub fn staging_dir() -> Result<PathBuf, String> {
    let game_dir = game::installed_game_dir()
        .ok_or_else(|| "Konnte lokalen Installationspfad (%LOCALAPPDATA%) nicht bestimmen.".to_string())?;
    let parent = game_dir
        .parent()
        .ok_or_else(|| "Ungueltiger Installationspfad.".to_string())?;
    Ok(parent.join("game_staging"))
}

pub async fn install_update(
    app: &AppHandle,
    client: &Client,
    state: &PersistedState,
) -> Result<GameStatusView, String> {
    let manifest_url = state.manifest_url.trim();
    if manifest_url.is_empty() {
        return Err("Keine Update-Manifest-URL in den Einstellungen hinterlegt.".to_string());
    }

    emit_progress(app, "checking", 0, 0, "Manifest wird geprueft ...");
    let resp = client
        .get(manifest_url)
        .send()
        .await
        .map_err(|e| format!("Update-Manifest nicht erreichbar: {}", e))?;
    if !resp.status().is_success() {
        return Err(format!("Manifest-Fehler HTTP {}", resp.status().as_u16()));
    }
    let manifest = resp
        .json::<RemoteManifest>()
        .await
        .map_err(|e| format!("Ungueltiges Update-Manifest: {}", e))?;

    let expected_sha = manifest.sha256.trim().to_ascii_lowercase();
    let dl_url = manifest.download_url.trim().to_string();
    let remote_version = manifest.version.trim().to_string();
    if remote_version.is_empty() || dl_url.is_empty() {
        return Err("Manifest enthaelt keine Version oder Download-URL.".to_string());
    }
    if expected_sha.len() != 64 || !expected_sha.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Manifest enthaelt keine gueltige SHA-256-Pruefsumme.".to_string());
    }
    if !dl_url.starts_with("https://") && !dl_url.starts_with("http://127.0.0.1") && !dl_url.starts_with("http://localhost") {
        return Err("Download-URL muss HTTPS verwenden.".to_string());
    }

    let install_dir = game::installed_game_dir()
        .ok_or_else(|| "Konnte lokalen Installationspfad nicht bestimmen.".to_string())?;
    let stage = staging_dir()?;
    let zip_path = stage.with_extension("download.zip");
    if stage.exists() {
        let _ = fs::remove_dir_all(&stage);
    }
    if let Some(parent) = zip_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("Ordnerfehler: {}", e))?;
    }

    let dl_resp = client
        .get(&dl_url)
        .send()
        .await
        .map_err(|e| format!("Download fehlgeschlagen: {}", e))?;
    if !dl_resp.status().is_success() {
        return Err(format!("Download fehlgeschlagen (HTTP {}).", dl_resp.status().as_u16()));
    }
    let total_bytes = dl_resp.content_length().unwrap_or(manifest.size_bytes);
    let mut downloaded: u64 = 0;

    {
        let mut out_file = File::create(&zip_path)
            .map_err(|e| format!("Konnte temporaere ZIP-Datei nicht anlegen: {}", e))?;
        let mut hasher = Sha256::new();
        let mut stream = dl_resp.bytes_stream();
        while let Some(chunk_res) = stream.next().await {
            let chunk = chunk_res.map_err(|e| format!("Netzwerkfehler beim Download: {}", e))?;
            io::Write::write_all(&mut out_file, &chunk)
                .map_err(|e| format!("Schreibfehler beim Download: {}", e))?;
            hasher.update(&chunk);
            downloaded = downloaded.saturating_add(chunk.len() as u64);
            emit_progress(
                app,
                "downloading",
                downloaded,
                total_bytes,
                &format!("Lade v{} herunter ...", remote_version),
            );
        }
        let actual_sha = format!("{:x}", hasher.finalize());
        emit_progress(app, "verifying", downloaded, total_bytes, "Pruefe SHA-256 Signatur ...");
        if actual_sha != expected_sha {
            drop(out_file);
            let _ = fs::remove_file(&zip_path);
            let msg = "SHA-256 Pruefsumme stimmt nicht ueberein! Update abgebrochen.".to_string();
            emit_progress(app, "error", 0, total_bytes, &msg);
            return Err(msg);
        }
    }

    emit_progress(app, "extracting", downloaded, total_bytes, "Entpacke Spiel-Dateien ...");
    let stage_clone = stage.clone();
    let zip_clone = zip_path.clone();
    let ver_clone = remote_version.clone();
    tauri::async_runtime::spawn_blocking(move || extract_verified_zip(&zip_clone, &stage_clone, &ver_clone))
        .await
        .map_err(|e| e.to_string())??;
    let _ = fs::remove_file(&zip_path);

    let backup_dir = install_dir.with_extension("backup");
    if backup_dir.exists() {
        let _ = fs::remove_dir_all(&backup_dir);
    }
    if install_dir.exists() {
        fs::rename(&install_dir, &backup_dir).map_err(|e| {
            format!(
                "Bestehende Installation ist gesperrt (bitte Spiel schliessen): {}",
                e
            )
        })?;
    }
    if let Err(err) = fs::rename(&stage, &install_dir) {
        if backup_dir.exists() {
            let _ = fs::rename(&backup_dir, &install_dir);
        }
        return Err(format!("Konnte neue Version nicht aktivieren: {}", err));
    }
    if backup_dir.exists() {
        let _ = fs::remove_dir_all(&backup_dir);
    }

    emit_progress(
        app,
        "done",
        total_bytes,
        total_bytes,
        &format!("Shadowspore v{} installiert!", remote_version),
    );
    Ok(game::inspect_game_status(client, state).await)
}

#[cfg(test)]
pub fn sha256_file_hex(path: &Path) -> Result<String, String> {
    use std::io::Read;
    let mut file = File::open(path).map_err(|e| format!("Datei nicht lesbar: {}", e))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file.read(&mut buf).map_err(|e| format!("Lesefehler: {}", e))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

#[cfg(test)]
pub fn verify_and_extract_zip(
    zip_path: &Path,
    dest_dir: &Path,
    expected_sha256: &str,
    version: &str,
) -> Result<(), String> {
    let actual = sha256_file_hex(zip_path)?;
    if actual != expected_sha256.trim().to_ascii_lowercase() {
        return Err("SHA-256 Pruefsumme stimmt nicht ueberein.".to_string());
    }
    extract_verified_zip(zip_path, dest_dir, version)
}

pub fn extract_verified_zip(zip_path: &Path, dest_dir: &Path, version: &str) -> Result<(), String> {
    if dest_dir.exists() {
        fs::remove_dir_all(dest_dir).map_err(|e| format!("Staging-Fehler: {}", e))?;
    }
    fs::create_dir_all(dest_dir).map_err(|e| format!("Ordnerfehler: {}", e))?;

    let file = File::open(zip_path).map_err(|e| format!("ZIP nicht lesbar: {}", e))?;
    let mut archive = ZipArchive::new(file).map_err(|e| format!("Beschaedigtes ZIP: {}", e))?;

    for i in 0..archive.len() {
        let mut entry = archive
            .by_index(i)
            .map_err(|e| format!("ZIP-Eintrag fehlerhaft: {}", e))?;
        let Some(rel_path) = entry.enclosed_name().map(|p| p.to_path_buf()) else {
            return Err("Unsicherer Pfad im Update-Archiv blockiert.".to_string());
        };
        let target = dest_dir.join(rel_path);
        if entry.is_dir() {
            fs::create_dir_all(&target).map_err(|e| format!("Ordnerfehler: {}", e))?;
        } else {
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent).map_err(|e| format!("Ordnerfehler: {}", e))?;
            }
            let mut out = File::create(&target).map_err(|e| format!("Dateifehler: {}", e))?;
            io::copy(&mut entry, &mut out).map_err(|e| format!("Entpackfehler: {}", e))?;
        }
    }

    fs::write(dest_dir.join("version.txt"), format!("{}\n", version.trim()))
        .map_err(|e| format!("Konnte version.txt nicht schreiben: {}", e))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use zip::write::SimpleFileOptions;
    use zip::ZipWriter;

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("shadowspore_upd_{}_{}", std::process::id(), name));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn verifies_sha256_and_extracts_clean_zip() {
        let root = temp_dir("ok");
        let zip_path = root.join("release.zip");
        {
            let file = File::create(&zip_path).unwrap();
            let mut writer = ZipWriter::new(file);
            writer
                .start_file("Shadowspore.exe", SimpleFileOptions::default())
                .unwrap();
            writer.write_all(b"MZ-MOCK-BINARY").unwrap();
            writer.finish().unwrap();
        }
        let sha = sha256_file_hex(&zip_path).unwrap();
        assert_eq!(sha.len(), 64);

        let wrong = verify_and_extract_zip(
            &zip_path,
            &root.join("bad_out"),
            "0000000000000000000000000000000000000000000000000000000000000000",
            "0.2.0",
        );
        assert!(wrong.is_err());

        let out_dir = root.join("good_out");
        verify_and_extract_zip(&zip_path, &out_dir, &sha, "0.2.0").expect("extract ok");
        assert_eq!(fs::read(out_dir.join("Shadowspore.exe")).unwrap(), b"MZ-MOCK-BINARY");
        assert_eq!(fs::read_to_string(out_dir.join("version.txt")).unwrap().trim(), "0.2.0");

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn blocks_zip_slip_traversal_entries() {
        let root = temp_dir("slip");
        let zip_path = root.join("evil.zip");
        {
            let file = File::create(&zip_path).unwrap();
            let mut writer = ZipWriter::new(file);
            writer
                .start_file("../escape.txt", SimpleFileOptions::default())
                .unwrap();
            writer.write_all(b"evil").unwrap();
            writer.finish().unwrap();
        }
        let sha = sha256_file_hex(&zip_path).unwrap();
        let res = verify_and_extract_zip(&zip_path, &root.join("out"), &sha, "0.2.0");
        assert!(res.is_err());
        assert!(!root.join("escape.txt").exists());
        let _ = fs::remove_dir_all(&root);
    }
}
