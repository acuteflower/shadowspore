use std::path::{Path, PathBuf};
use std::process::Command;

use reqwest::Client;
use serde::Deserialize;

use crate::models::{GameStatusView, PersistedState};

#[derive(Debug, Deserialize)]
struct RemoteManifest {
    #[serde(default)]
    version: String,
}

pub fn find_project_dir() -> Option<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd.clone());
        if let Some(p) = cwd.parent() {
            candidates.push(p.to_path_buf());
            if let Some(gp) = p.parent() {
                candidates.push(gp.to_path_buf());
            }
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut cur = exe.parent().map(|p| p.to_path_buf());
        for _ in 0..5 {
            if let Some(dir) = cur {
                candidates.push(dir.clone());
                cur = dir.parent().map(|p| p.to_path_buf());
            }
        }
    }
    candidates.into_iter().find(|dir| dir.join("project.godot").is_file())
}

fn detect_game_exe(configured: &str, project_dir: Option<&Path>) -> Option<PathBuf> {
    let trimmed = configured.trim();
    if !trimmed.is_empty() {
        let p = PathBuf::from(trimmed);
        if p.is_file() {
            return Some(p);
        }
    }
    let mut probes: Vec<PathBuf> = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            probes.push(dir.join("Shadowspore.exe"));
            probes.push(dir.join("game").join("Shadowspore.exe"));
        }
    }
    if let Some(proj) = project_dir {
        probes.push(proj.join("build").join("Shadowspore.exe"));
        probes.push(proj.join("Shadowspore.exe"));
    }
    probes.into_iter().find(|p| p.is_file())
}

fn detect_godot_exe(configured: &str) -> Option<PathBuf> {
    let trimmed = configured.trim();
    if !trimmed.is_empty() {
        let p = PathBuf::from(trimmed);
        if p.is_file() {
            return Some(p);
        }
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in std::env::split_paths(&path_var) {
            for name in ["godot.exe", "godot4.exe"] {
                let candidate = dir.join(name);
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
    }
    if let Ok(profile) = std::env::var("USERPROFILE") {
        let downloads = PathBuf::from(profile).join("Downloads");
        if let Ok(entries) = std::fs::read_dir(downloads) {
            let mut found_console: Option<PathBuf> = None;
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_lowercase();
                if !name.starts_with("godot_v4") {
                    continue;
                }
                let path = entry.path();
                if path.is_dir() {
                    if let Ok(sub) = std::fs::read_dir(&path) {
                        for item in sub.flatten() {
                            let sname = item.file_name().to_string_lossy().to_lowercase();
                            if sname.ends_with(".exe") && sname.starts_with("godot") {
                                if !sname.contains("console") {
                                    return Some(item.path());
                                }
                                found_console = Some(item.path());
                            }
                        }
                    }
                } else if name.ends_with(".exe") {
                    if !name.contains("console") {
                        return Some(path);
                    }
                    found_console = Some(path);
                }
            }
            if found_console.is_some() {
                return found_console;
            }
        }
    }
    None
}

fn read_local_version(project_dir: Option<&Path>) -> String {
    let Some(dir) = project_dir else {
        return "0.1.0".to_string();
    };
    let cfg_path = dir.join("project.godot");
    if let Ok(text) = std::fs::read_to_string(cfg_path) {
        for line in text.lines() {
            if let Some(rest) = line.strip_prefix("config/version=") {
                return rest.trim().trim_matches('"').to_string();
            }
        }
    }
    "dev".to_string()
}

pub async fn inspect_game_status(client: &Client, state: &PersistedState) -> GameStatusView {
    let project_dir = find_project_dir();
    let local_version = read_local_version(project_dir.as_deref());

    let mut remote_version = String::new();
    let mut update_available = false;
    let manifest_url = state.manifest_url.trim();
    if !manifest_url.is_empty() {
        if let Ok(resp) = client.get(manifest_url).send().await {
            if resp.status().is_success() {
                if let Ok(manifest) = resp.json::<RemoteManifest>().await {
                    remote_version = manifest.version;
                    update_available = !remote_version.is_empty() && remote_version != local_version;
                }
            }
        }
    }

    if let Some(game_exe) = detect_game_exe(&state.game_exe_path, project_dir.as_deref()) {
        return GameStatusView {
            mode: "release".to_string(),
            ready: true,
            resolved_exe: game_exe.to_string_lossy().to_string(),
            resolved_project_dir: project_dir
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default(),
            local_version,
            remote_version,
            update_available,
            status_label: "Spiel bereit (Build)".to_string(),
        };
    }

    if let Some(ref proj) = project_dir {
        if let Some(godot_exe) = detect_godot_exe(&state.godot_exe_path) {
            return GameStatusView {
                mode: "dev".to_string(),
                ready: true,
                resolved_exe: godot_exe.to_string_lossy().to_string(),
                resolved_project_dir: proj.to_string_lossy().to_string(),
                local_version,
                remote_version,
                update_available,
                status_label: "Dev-Modus bereit (Godot 4.7)".to_string(),
            };
        }
    }

    GameStatusView {
        mode: "missing".to_string(),
        ready: false,
        resolved_exe: String::new(),
        resolved_project_dir: project_dir
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default(),
        local_version,
        remote_version,
        update_available,
        status_label: "Shadowspore.exe oder Godot-Pfad in Einstellungen setzen".to_string(),
    }
}

pub fn spawn_shadowspore(
    state: &PersistedState,
    token: &str,
    refresh_token: &str,
) -> Result<String, String> {
    let project_dir = find_project_dir();
    let mut auth_args: Vec<String> = Vec::new();
    if !token.is_empty() {
        auth_args.push("--".to_string());
        auth_args.push(format!("--nakama-url={}", state.server_url.trim()));
        auth_args.push(format!("--nakama-token={}", token));
        if !refresh_token.is_empty() {
            auth_args.push(format!("--nakama-refresh={}", refresh_token));
        }
    }

    if let Some(game_exe) = detect_game_exe(&state.game_exe_path, project_dir.as_deref()) {
        Command::new(&game_exe)
            .args(&auth_args)
            .spawn()
            .map_err(|e| format!("Konnte {} nicht starten: {}", game_exe.display(), e))?;
        return Ok(format!("Gestartet: {}", game_exe.display()));
    }

    if let Some(proj) = project_dir {
        if let Some(godot_exe) = detect_godot_exe(&state.godot_exe_path) {
            Command::new(&godot_exe)
                .arg("--path")
                .arg(&proj)
                .args(&auth_args)
                .spawn()
                .map_err(|e| format!("Konnte Godot nicht starten: {}", e))?;
            return Ok(format!("Dev-Start via {}", godot_exe.display()));
        }
    }

    Err("Kein Shadowspore.exe oder Godot-Binary gefunden. Bitte in den Einstellungen angeben.".to_string())
}
