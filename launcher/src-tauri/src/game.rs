use std::fs::File;
use std::io::Read;
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::models::{GameStatusView, LocalBuildInfoView, PersistedState};

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

const FORBIDDEN_PROCESS_PATTERNS: &[&str] = &[
    "cheatengine",
    "x64dbg",
    "x32dbg",
    "ollydbg",
    "processhacker",
    "systeminformer",
    "wemod",
    "artmoney",
    "frida",
    "gdsdecomp",
    "gdre_tools",
    "scyllahide",
];

#[derive(Debug, Deserialize)]
pub struct RemoteManifest {
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub download_url: String,
    #[serde(default)]
    pub sha256: String,
    #[serde(default)]
    pub exe_sha256: String,
    #[serde(default)]
    pub size_bytes: u64,
    #[serde(default)]
    pub changelog: String,
}

#[derive(Debug, Clone)]
pub struct PreparedLaunch {
    #[cfg_attr(not(debug_assertions), allow(dead_code))]
    pub project_dir: Option<PathBuf>,
    pub game_exe: Option<PathBuf>,
    #[cfg_attr(not(debug_assertions), allow(dead_code))]
    pub godot_exe: Option<PathBuf>,
    pub local_version: String,
    pub exe_sha256: String,
}

#[derive(Debug, Clone)]
pub struct LaunchBlock {
    pub kind: String,
    pub message: String,
}

#[derive(Debug, Clone)]
pub enum GameLaunchIntent {
    Play,
    HostCoop {
        world_name: Option<String>,
        join_mode: Option<String>,
    },
    JoinMatch {
        match_id: String,
        room_code: Option<String>,
        world_name: Option<String>,
    },
    JoinCode {
        room_code: String,
    },
}

pub fn installed_game_dir() -> Option<PathBuf> {
    if let Ok(local) = std::env::var("LOCALAPPDATA") {
        if !local.trim().is_empty() {
            return Some(PathBuf::from(local).join("Shadowspore").join("game"));
        }
    }
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME") {
        if !xdg.trim().is_empty() {
            return Some(PathBuf::from(xdg).join("Shadowspore").join("game"));
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        if !home.trim().is_empty() {
            return Some(
                PathBuf::from(home)
                    .join(".local")
                    .join("share")
                    .join("Shadowspore")
                    .join("game"),
            );
        }
    }
    None
}

fn ipc_file_path() -> Option<PathBuf> {
    if let Ok(appdata) = std::env::var("APPDATA") {
        if !appdata.trim().is_empty() {
            return Some(PathBuf::from(appdata).join("Shadowspore").join("ipc.json"));
        }
    }
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME") {
        if !xdg.trim().is_empty() {
            return Some(PathBuf::from(xdg).join("Shadowspore").join("ipc.json"));
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        if !home.trim().is_empty() {
            return Some(
                PathBuf::from(home)
                    .join(".local")
                    .join("share")
                    .join("Shadowspore")
                    .join("ipc.json"),
            );
        }
    }
    None
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
    if let Some(inst) = installed_game_dir() {
        probes.push(inst.join("Shadowspore.exe"));
    }
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

fn is_local_dev_server(url: &str) -> bool {
    let lower = url.trim().to_ascii_lowercase();
    lower.starts_with("http://127.0.0.1") || lower.starts_with("http://localhost")
}

fn select_launch_target(
    debug_mode: bool,
    server_url: &str,
    explicit_exe_configured: bool,
    detected_exe: Option<PathBuf>,
    detected_godot: Option<PathBuf>,
    has_project: bool,
) -> (Option<PathBuf>, Option<PathBuf>) {
    if !debug_mode {
        return (detected_exe, None);
    }
    if explicit_exe_configured && detected_exe.is_some() {
        return (detected_exe, None);
    }
    // Exported Shadowspore.exe bundles live auth and ignores local dev URLs, so dev mode prefers Godot sources.
    if has_project && is_local_dev_server(server_url) && detected_godot.is_some() {
        return (None, detected_godot);
    }
    if detected_exe.is_some() {
        return (detected_exe, None);
    }
    if has_project {
        return (None, detected_godot);
    }
    (None, None)
}

fn resolve_launch_binaries(
    state: &PersistedState,
    project_dir: Option<&Path>,
) -> (Option<PathBuf>, Option<PathBuf>) {
    let detected_exe = detect_game_exe(&state.game_exe_path, project_dir);
    let detected_godot = if cfg!(debug_assertions) && project_dir.is_some() {
        detect_godot_exe(&state.godot_exe_path)
    } else {
        None
    };
    select_launch_target(
        cfg!(debug_assertions),
        &state.server_url,
        !state.game_exe_path.trim().is_empty(),
        detected_exe,
        detected_godot,
        project_dir.is_some(),
    )
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

fn read_local_version(project_dir: Option<&Path>, game_exe: Option<&Path>) -> String {
    if let Some(exe) = game_exe {
        if let Some(dir) = exe.parent() {
            let ver_file = dir.join("version.txt");
            if let Ok(v) = std::fs::read_to_string(ver_file) {
                let clean = v.trim();
                if !clean.is_empty() {
                    return clean.to_string();
                }
            }
        }
        if let Some(inst) = installed_game_dir() {
            if let Ok(v) = std::fs::read_to_string(inst.join("version.txt")) {
                let clean = v.trim();
                if !clean.is_empty() {
                    return clean.to_string();
                }
            }
        }
    }
    let Some(dir) = project_dir else {
        return String::new();
    };
    let cfg_path = dir.join("project.godot");
    if let Ok(text) = std::fs::read_to_string(cfg_path) {
        for line in text.lines() {
            if let Some(rest) = line.strip_prefix("config/version=") {
                return rest.trim().trim_matches('"').to_string();
            }
        }
    }
    if game_exe.is_some() {
        "0.1.0".to_string()
    } else {
        "dev".to_string()
    }
}

pub fn compute_update_available(
    missing_game: bool,
    local_version: &str,
    remote_version: &str,
    remote_download_url: &str,
) -> bool {
    let r_ver = remote_version.trim();
    let r_url = remote_download_url.trim();
    if r_ver.is_empty() || r_url.is_empty() {
        return false;
    }
    missing_game || r_ver != local_version.trim()
}

pub async fn fetch_remote_manifest(client: &Client, manifest_url: &str) -> Option<RemoteManifest> {
    let url = manifest_url.trim();
    if url.is_empty() {
        return None;
    }
    let resp = client.get(url).send().await.ok()?;
    if !resp.status().is_success() {
        return None;
    }
    resp.json::<RemoteManifest>().await.ok()
}

pub fn sha256_file_hex(path: &Path) -> Result<String, String> {
    let mut file = File::open(path)
        .map_err(|e| format!("Konnte {} nicht lesen: {}", path.display(), e))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 65536];
    loop {
        let read_len = file
            .read(&mut buf)
            .map_err(|e| format!("Fehler beim Hashing von {}: {}", path.display(), e))?;
        if read_len == 0 {
            break;
        }
        hasher.update(&buf[..read_len]);
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|b| format!("{:02x}", b))
        .collect())
}

pub fn inspect_local_build(persisted: &PersistedState) -> LocalBuildInfoView {
    let project_dir = find_project_dir();
    let game_exe = detect_game_exe(&persisted.game_exe_path, project_dir.as_deref());
    let local_version = read_local_version(project_dir.as_deref(), game_exe.as_deref());
    match game_exe {
        Some(exe) => {
            let sha256 = sha256_file_hex(&exe).unwrap_or_default();
            LocalBuildInfoView {
                found: !sha256.is_empty(),
                exe_path: exe.display().to_string(),
                version: local_version,
                sha256,
            }
        }
        None => LocalBuildInfoView {
            found: false,
            exe_path: String::new(),
            version: local_version,
            sha256: String::new(),
        },
    }
}

pub fn scan_process_list_for_cheat_tools(csv_output: &str) -> Option<String> {
    for raw_line in csv_output.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        let first_col = line.split(',').next().unwrap_or("").trim().trim_matches('"');
        let lower = first_col.to_ascii_lowercase();
        for pat in FORBIDDEN_PROCESS_PATTERNS {
            if lower.contains(pat) {
                return Some(first_col.to_string());
            }
        }
    }
    None
}

pub fn detect_cheat_tools() -> Option<String> {
    #[cfg(target_os = "windows")]
    {
        let mut cmd = Command::new("tasklist");
        cmd.args(["/FO", "CSV", "/NH"]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        if let Ok(output) = cmd.output() {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout);
                return scan_process_list_for_cheat_tools(&text);
            }
        }
    }
    None
}

pub async fn prepare_launch_exe(
    client: &Client,
    state: &PersistedState,
) -> Result<PreparedLaunch, LaunchBlock> {
    if let Some(cheat_proc) = detect_cheat_tools() {
        return Err(LaunchBlock {
            kind: "CHEAT_TOOL_DETECTED".to_string(),
            message: format!(
                "Sicherheitspruefung fehlgeschlagen: Unerlaubtes Analyse-/Cheat-Tool erkannt ({}). Bitte schliessen und erneut versuchen.",
                cheat_proc
            ),
        });
    }

    let project_dir = find_project_dir();
    let (game_exe, godot_exe) = resolve_launch_binaries(state, project_dir.as_deref());
    let local_version = read_local_version(project_dir.as_deref(), game_exe.as_deref());

    if let Some(ref exe_path) = game_exe {
        let exe_sha256 = sha256_file_hex(exe_path).map_err(|err| LaunchBlock {
            kind: "EXE_READ_ERROR".to_string(),
            message: err,
        })?;
        if let Some(manifest) = fetch_remote_manifest(client, &state.manifest_url).await {
            let expected_hash = manifest.exe_sha256.trim().to_ascii_lowercase();
            let remote_ver = manifest.version.trim();
            if !expected_hash.is_empty()
                && !remote_ver.is_empty()
                && local_version.trim() == remote_ver
                && expected_hash != exe_sha256
            {
                return Err(LaunchBlock {
                    kind: "EXE_HASH_MISMATCH".to_string(),
                    message: "Die lokale Shadowspore.exe entspricht nicht dem signierten Build-Hash. Bitte das Spiel im Launcher reparieren/aktualisieren.".to_string(),
                });
            }
        }
        return Ok(PreparedLaunch {
            project_dir,
            game_exe,
            godot_exe: None,
            local_version,
            exe_sha256,
        });
    }

    #[cfg(not(debug_assertions))]
    {
        let _ = godot_exe;
        return Err(LaunchBlock {
            kind: "EXE_MISSING".to_string(),
            message: "Kein Shadowspore.exe gefunden. Bitte das Spiel zuerst ueber den Launcher herunterladen.".to_string(),
        });
    }

    #[cfg(debug_assertions)]
    {
        if godot_exe.is_none() || project_dir.is_none() {
            return Err(LaunchBlock {
                kind: "EXE_MISSING".to_string(),
                message: "Kein Shadowspore.exe oder Godot-Binary gefunden. Bitte in den Einstellungen angeben.".to_string(),
            });
        }
        Ok(PreparedLaunch {
            project_dir,
            game_exe: None,
            godot_exe,
            local_version,
            exe_sha256: String::new(),
        })
    }
}

pub async fn inspect_game_status(client: &Client, state: &PersistedState) -> GameStatusView {
    let project_dir = find_project_dir();
    let (game_exe, godot_exe) = resolve_launch_binaries(state, project_dir.as_deref());
    let missing_game = game_exe.is_none() && godot_exe.is_none();
    let local_version = read_local_version(project_dir.as_deref(), game_exe.as_deref());

    let mut remote_version = String::new();
    let mut remote_changelog = String::new();
    let mut remote_download_url = String::new();
    let mut remote_sha256 = String::new();
    let mut remote_size_bytes: u64 = 0;
    let mut update_available = false;
    if let Some(manifest) = fetch_remote_manifest(client, &state.manifest_url).await {
        remote_version = manifest.version.trim().to_string();
        remote_changelog = manifest.changelog;
        remote_download_url = manifest.download_url.trim().to_string();
        remote_sha256 = manifest.sha256.trim().to_string();
        remote_size_bytes = manifest.size_bytes;
        update_available = compute_update_available(
            missing_game,
            &local_version,
            &remote_version,
            &remote_download_url,
        );
    }

    if let Some(exe) = game_exe {
        return GameStatusView {
            mode: "release".to_string(),
            ready: true,
            resolved_exe: exe.to_string_lossy().to_string(),
            resolved_project_dir: project_dir
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default(),
            local_version,
            remote_version,
            update_available,
            remote_changelog,
            remote_download_url,
            remote_sha256,
            remote_size_bytes,
            status_label: "Spiel bereit (Build)".to_string(),
        };
    }

    if let (Some(ref proj), Some(godot_bin)) = (&project_dir, godot_exe) {
        return GameStatusView {
            mode: "dev".to_string(),
            ready: true,
            resolved_exe: godot_bin.to_string_lossy().to_string(),
            resolved_project_dir: proj.to_string_lossy().to_string(),
            local_version,
            remote_version,
            update_available,
            remote_changelog,
            remote_download_url,
            remote_sha256,
            remote_size_bytes,
            status_label: "Dev-Modus bereit (Godot 4.7)".to_string(),
        };
    }

    let missing_label = if update_available {
        format!("Spiel v{} bereit zum Download", remote_version)
    } else {
        "Shadowspore.exe oder Godot-Pfad in Einstellungen setzen".to_string()
    };

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
        remote_changelog,
        remote_download_url,
        remote_sha256,
        remote_size_bytes,
        status_label: missing_label,
    }
}

/// The game process this launcher started last; asked with try_wait to see whether it still runs.
static GAME_CHILD: Mutex<Option<Child>> = Mutex::new(None);
static WATCHDOG_ACTIVE: AtomicBool = AtomicBool::new(false);

fn remember_child(child: Child) {
    if let Ok(mut slot) = GAME_CHILD.lock() {
        *slot = Some(child);
    }
}

fn terminate_tracked_child() {
    if let Ok(mut slot) = GAME_CHILD.lock() {
        if let Some(ref mut child) = *slot {
            let _ = child.kill();
        }
        *slot = None;
    }
}

struct WatchdogResetGuard;

impl Drop for WatchdogResetGuard {
    fn drop(&mut self) {
        WATCHDOG_ACTIVE.store(false, Ordering::SeqCst);
    }
}

/// Polls running system processes while Shadowspore is active so cheat/reversing tools opened
/// after game launch immediately revoke the server session and stop Release builds.
pub fn spawn_runtime_watchdog(client: Client, server_url: String, token: String) {
    if token.trim().is_empty() || server_url.trim().is_empty() {
        return;
    }
    if WATCHDOG_ACTIVE
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return;
    }
    tauri::async_runtime::spawn(async move {
        let _guard = WatchdogResetGuard;
        loop {
            tokio::time::sleep(Duration::from_secs(12)).await;
            if !is_game_running(&client).await {
                break;
            }
            let detected = tokio::task::spawn_blocking(detect_cheat_tools)
                .await
                .ok()
                .flatten();
            if let Some(proc_name) = detected {
                crate::nakama::report_security_event(
                    &client,
                    &server_url,
                    &token,
                    "LAUNCHER_CHEAT_TOOL_RUNTIME",
                    &format!("Analyse-/Cheat-Tool waehrend Laufzeit erkannt: {}", proc_name),
                    "critical",
                )
                .await;
                if cfg!(not(debug_assertions)) {
                    terminate_tracked_child();
                }
                break;
            }
        }
    });
}

fn child_alive() -> bool {
    let Ok(mut slot) = GAME_CHILD.lock() else {
        return false;
    };
    let alive = match slot.as_mut() {
        Some(child) => matches!(child.try_wait(), Ok(None)),
        None => false,
    };
    if !alive {
        *slot = None;
    }
    alive
}

/// True while Shadowspore runs: a process this launcher started, or a game started
/// elsewhere that answers on its local IPC port (ipc.json).
pub async fn is_game_running(client: &Client) -> bool {
    if child_alive() {
        return true;
    }
    let Some(path) = ipc_file_path() else {
        return false;
    };
    let Ok(raw) = std::fs::read_to_string(&path) else {
        return false;
    };
    let Ok(info) = serde_json::from_str::<Value>(&raw) else {
        return false;
    };
    let port = info.get("port").and_then(|v| v.as_u64()).unwrap_or(0) as u16;
    let secret = info.get("secret").and_then(|v| v.as_str()).unwrap_or("");
    if port == 0 || secret.is_empty() {
        return false;
    }
    post_ipc_command(client, port, secret, json!({ "action": "ping" }))
        .await
        .ok()
        .and_then(|v| v.get("ok").and_then(|b| b.as_bool()))
        .unwrap_or(false)
}

async fn post_ipc_command(client: &Client, port: u16, secret: &str, body: Value) -> Result<Value, String> {
    let url = format!("http://127.0.0.1:{}/command", port);
    let resp = client
        .post(url)
        .timeout(Duration::from_millis(900))
        .bearer_auth(secret)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("IPC HTTP {}", resp.status().as_u16()));
    }
    resp.json::<Value>().await.map_err(|e| e.to_string())
}

async fn try_ipc_dispatch(
    client: &Client,
    state: &PersistedState,
    token: &str,
    refresh_token: &str,
    intent: &GameLaunchIntent,
) -> Option<String> {
    let path = ipc_file_path()?;
    let raw = std::fs::read_to_string(&path).ok()?;
    let info: Value = serde_json::from_str(&raw).ok()?;
    let port = info.get("port").and_then(|v| v.as_u64()).unwrap_or(0) as u16;
    let secret = info.get("secret").and_then(|v| v.as_str()).unwrap_or("");
    if port == 0 || secret.is_empty() {
        return None;
    }

    // Ping first so stale ipc.json from a crashed process won't be treated as active.
    let ping = post_ipc_command(client, port, secret, json!({ "action": "ping" }))
        .await
        .ok()?;
    if !ping.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return None;
    }

    if !token.is_empty() {
        let _ = post_ipc_command(
            client,
            port,
            secret,
            json!({
                "action": "update_session",
                "server_url": state.server_url.trim(),
                "server_key": state.server_key.trim(),
                "token": token,
                "refresh_token": refresh_token
            }),
        )
        .await;
    }

    let label = match intent {
        GameLaunchIntent::Play => return Some("Spiel laeuft bereits (Sitzung aktualisiert).".to_string()),
        GameLaunchIntent::HostCoop { world_name, join_mode } => {
            let res = post_ipc_command(
                client,
                port,
                secret,
                json!({
                    "action": "host_coop",
                    "world_name": world_name.as_deref().unwrap_or("KOOP-WELT"),
                    "join_mode": join_mode.as_deref().unwrap_or("")
                }),
            )
            .await
            .ok()?;
            if !res.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                return None;
            }
            "Koop-Welt wird im laufenden Spiel geoeffnet ...".to_string()
        }
        GameLaunchIntent::JoinMatch { match_id, room_code, world_name } => {
            let res = post_ipc_command(
                client,
                port,
                secret,
                json!({
                    "action": "join_match",
                    "match_id": match_id,
                    "room_code": room_code.as_deref().unwrap_or(""),
                    "world_name": world_name.as_deref().unwrap_or("KOOP-WELT")
                }),
            )
            .await
            .ok()?;
            if !res.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                return None;
            }
            "Trete Koop-Welt im laufenden Spiel bei ...".to_string()
        }
        GameLaunchIntent::JoinCode { room_code } => {
            let res = post_ipc_command(
                client,
                port,
                secret,
                json!({
                    "action": "join_code",
                    "room_code": room_code
                }),
            )
            .await
            .ok()?;
            if !res.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                return None;
            }
            "Verbinde im laufenden Spiel via Raumcode ...".to_string()
        }
    };
    Some(label)
}

fn spawn_with_launch_env(
    mut cmd: Command,
    spawn_args: &[String],
    token: &str,
    refresh_token: &str,
    launch_ticket: &str,
    exe_sha256: &str,
) -> Result<Child, std::io::Error> {
    cmd.args(spawn_args)
        .env("SHADOWSPORE_LAUNCH_TICKET", launch_ticket)
        .env("SHADOWSPORE_NAKAMA_TOKEN", token)
        .env("SHADOWSPORE_NAKAMA_REFRESH", refresh_token)
        .env("SHADOWSPORE_EXE_SHA256", exe_sha256)
        .env("SHADOWSPORE_LAUNCHER_PID", std::process::id().to_string());
    cmd.spawn()
}

pub async fn launch_or_dispatch(
    client: &Client,
    state: &PersistedState,
    token: &str,
    refresh_token: &str,
    launch_ticket: &str,
    prepared: &PreparedLaunch,
    intent: GameLaunchIntent,
) -> Result<String, String> {
    if token.trim().is_empty() || launch_ticket.trim().is_empty() {
        return Err("Anmeldung und Startticket erforderlich.".to_string());
    }

    if let Some(msg) = try_ipc_dispatch(client, state, token, refresh_token, &intent).await {
        return Ok(msg);
    }

    let mut user_args: Vec<String> = Vec::new();
    if cfg!(debug_assertions) {
        user_args.push(format!("--nakama-url={}", state.server_url.trim()));
        user_args.push(format!("--nakama-server-key={}", state.server_key.trim()));
    }
    match &intent {
        GameLaunchIntent::Play => {}
        GameLaunchIntent::HostCoop { world_name, join_mode } => {
            user_args.push("--host-coop".to_string());
            if let Some(wn) = world_name {
                if !wn.trim().is_empty() {
                    user_args.push(format!("--world-name={}", wn.trim()));
                }
            }
            if let Some(jm) = join_mode {
                if !jm.trim().is_empty() {
                    user_args.push(format!("--join-mode={}", jm.trim()));
                }
            }
        }
        GameLaunchIntent::JoinMatch { match_id, room_code, world_name } => {
            user_args.push(format!("--join-match={}", match_id.trim()));
            if let Some(rc) = room_code {
                if !rc.trim().is_empty() {
                    user_args.push(format!("--room-code={}", rc.trim()));
                }
            }
            if let Some(wn) = world_name {
                if !wn.trim().is_empty() {
                    user_args.push(format!("--world-name={}", wn.trim()));
                }
            }
        }
        GameLaunchIntent::JoinCode { room_code } => {
            user_args.push(format!("--join-code={}", room_code.trim().to_ascii_uppercase()));
        }
    }

    let mut spawn_args: Vec<String> = Vec::new();
    if !user_args.is_empty() {
        spawn_args.push("--".to_string());
        spawn_args.extend(user_args);
    }

    if let Some(ref game_exe) = prepared.game_exe {
        let cmd = Command::new(game_exe);
        let child = spawn_with_launch_env(
            cmd,
            &spawn_args,
            token,
            refresh_token,
            launch_ticket,
            &prepared.exe_sha256,
        )
        .map_err(|e| format!("Konnte {} nicht starten: {}", game_exe.display(), e))?;
        remember_child(child);
        return Ok(format!("Gestartet: {}", game_exe.display()));
    }

    #[cfg(debug_assertions)]
    if let (Some(ref proj), Some(ref godot_exe)) = (&prepared.project_dir, &prepared.godot_exe) {
        let mut cmd = Command::new(godot_exe);
        cmd.arg("--path").arg(proj);
        let child = spawn_with_launch_env(
            cmd,
            &spawn_args,
            token,
            refresh_token,
            launch_ticket,
            &prepared.exe_sha256,
        )
        .map_err(|e| format!("Konnte Godot nicht starten: {}", e))?;
        remember_child(child);
        return Ok(format!("Dev-Start via {}", godot_exe.display()));
    }

    Err("Kein gueltiger Spielstart moeglich (Binary fehlt).".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_game_enables_initial_download_even_for_first_version() {
        assert!(compute_update_available(
            true,
            "",
            "0.1.0",
            "https://shadowspore.com/updates/Shadowspore-0.1.0-win64.zip"
        ));
        assert!(!compute_update_available(true, "", "0.1.0", ""));
        assert!(!compute_update_available(
            false,
            "0.1.0",
            "0.1.0",
            "https://shadowspore.com/updates/Shadowspore-0.1.0-win64.zip"
        ));
        assert!(compute_update_available(
            false,
            "0.1.0",
            "0.2.0",
            "https://shadowspore.com/updates/Shadowspore-0.2.0-win64.zip"
        ));
    }

    #[test]
    fn cheat_process_scanner_detects_known_tools_case_insensitively() {
        let clean_csv = "\"explorer.exe\",\"1024\",\"Console\",\"1\",\"55,000 K\"\n\"Discord.exe\",\"2048\",\"Console\",\"1\",\"120,000 K\"";
        assert_eq!(scan_process_list_for_cheat_tools(clean_csv), None);

        let dirty_csv = "\"explorer.exe\",\"1024\",\"Console\",\"1\",\"55,000 K\"\n\"CheatEngine-x86_64-SSE4-AVX2.exe\",\"9999\",\"Console\",\"1\",\"80,000 K\"";
        assert_eq!(
            scan_process_list_for_cheat_tools(dirty_csv).as_deref(),
            Some("CheatEngine-x86_64-SSE4-AVX2.exe")
        );

        let dbg_csv = "\"x64dbg.exe\",\"4444\",\"Console\",\"1\",\"40,000 K\"";
        assert_eq!(
            scan_process_list_for_cheat_tools(dbg_csv).as_deref(),
            Some("x64dbg.exe")
        );

        let decomp_csv = "\"gdre_tools.exe\",\"7777\",\"Console\",\"1\",\"90,000 K\"";
        assert_eq!(
            scan_process_list_for_cheat_tools(decomp_csv).as_deref(),
            Some("gdre_tools.exe")
        );
    }

    #[test]
    fn dev_mode_prefers_godot_sources_over_bundled_release_exe_on_local_server() {
        let exe = Some(PathBuf::from("build/Shadowspore.exe"));
        let godot = Some(PathBuf::from("C:/Godot/godot.exe"));

        // Dev launcher pointed at local Nakama uses Godot sources even when build/Shadowspore.exe exists.
        let (chosen_exe, chosen_godot) = select_launch_target(
            true,
            "http://127.0.0.1:7350",
            false,
            exe.clone(),
            godot.clone(),
            true,
        );
        assert_eq!(chosen_exe, None);
        assert_eq!(chosen_godot, godot);

        // Dev launcher pointed at live server or with an explicit game_exe_path runs Shadowspore.exe.
        let (live_exe, live_godot) = select_launch_target(
            true,
            "https://s.shadowspore.com",
            false,
            exe.clone(),
            godot.clone(),
            true,
        );
        assert_eq!(live_exe, exe);
        assert_eq!(live_godot, None);

        let (manual_exe, manual_godot) = select_launch_target(
            true,
            "http://127.0.0.1:7350",
            true,
            exe.clone(),
            godot.clone(),
            true,
        );
        assert_eq!(manual_exe, exe);
        assert_eq!(manual_godot, None);

        // Release builds never select Godot.
        let (rel_exe, rel_godot) = select_launch_target(
            false,
            "http://127.0.0.1:7350",
            false,
            exe.clone(),
            godot,
            true,
        );
        assert_eq!(rel_exe, exe);
        assert_eq!(rel_godot, None);
    }
}
