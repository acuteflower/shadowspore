mod content;
mod game;
mod models;
mod nakama;
mod updater;
mod ws_client;

use std::path::PathBuf;
use std::sync::Mutex;

use reqwest::Client;
use serde_json::json;
use tauri::{AppHandle, Manager, State};

use game::GameLaunchIntent;
use models::{
    live_server_key, AdminAccountView, AdminBuildConfigView, AdminForceJoinView, AdminOverviewView,
    AdminWorldView, CloudSaveSummary, CoopNotificationView, FriendView, GameStatusView,
    JoinRequestResultView, LauncherConfigView, LicenseKeyView, LocalBuildInfoView, LookupView,
    PersistedState, ResolveCodeView, SecurityEventView, ServerPresetsView, SessionView,
    DEV_SERVER_KEY, DEV_SERVER_URL, LIVE_MANIFEST_URL, LIVE_SERVER_URL,
};
use ws_client::WsController;

struct AppState {
    client: Client,
    persisted: Mutex<PersistedState>,
    token: Mutex<String>,
    user_id: Mutex<String>,
    ws: WsController,
}

fn state_file_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("App-Data-Pfad nicht gefunden: {}", e))?;
    std::fs::create_dir_all(&dir).map_err(|e| format!("Ordnerfehler: {}", e))?;
    Ok(dir.join("state.json"))
}

fn enforce_release_pinning(loaded: &mut PersistedState) -> bool {
    let mut changed = false;
    if loaded.server_url.trim_end_matches('/') == "https://api.shadowspore.com" {
        loaded.server_url = LIVE_SERVER_URL.to_string();
        if loaded.server_key == DEV_SERVER_KEY || loaded.server_key.is_empty() {
            loaded.server_key = live_server_key().to_string();
        }
        if loaded.manifest_url.trim().is_empty() {
            loaded.manifest_url = LIVE_MANIFEST_URL.to_string();
        }
        changed = true;
    }
    if cfg!(not(debug_assertions)) {
        if loaded.server_url != LIVE_SERVER_URL {
            loaded.server_url = LIVE_SERVER_URL.to_string();
            loaded.refresh_token.clear();
            changed = true;
        }
        if loaded.server_key != live_server_key() {
            loaded.server_key = live_server_key().to_string();
            loaded.refresh_token.clear();
            changed = true;
        }
        if loaded.manifest_url != LIVE_MANIFEST_URL {
            loaded.manifest_url = LIVE_MANIFEST_URL.to_string();
            changed = true;
        }
        if !loaded.godot_exe_path.is_empty() {
            loaded.godot_exe_path.clear();
            changed = true;
        }
    }
    changed
}

fn load_persisted(app: &AppHandle) -> PersistedState {
    let Ok(path) = state_file_path(app) else {
        return PersistedState::default();
    };
    let Ok(raw) = std::fs::read_to_string(path) else {
        return PersistedState::default();
    };
    let mut loaded = serde_json::from_str::<PersistedState>(&raw).unwrap_or_default();
    if enforce_release_pinning(&mut loaded) {
        save_persisted(app, &loaded);
    }
    loaded
}

fn save_persisted(app: &AppHandle, persisted: &PersistedState) {
    if let Ok(path) = state_file_path(app) {
        if let Ok(raw) = serde_json::to_string_pretty(persisted) {
            let _ = std::fs::write(path, raw);
        }
    }
}

fn snapshot_auth(state: &State<AppState>) -> (String, String, String, String) {
    let persisted = state.persisted.lock().unwrap();
    let token = state.token.lock().unwrap();
    let user_id = state.user_id.lock().unwrap();
    (
        persisted.server_url.clone(),
        persisted.server_key.clone(),
        token.clone(),
        user_id.clone(),
    )
}

async fn build_session_view(
    client: &Client,
    server_url: &str,
    token: &str,
) -> Result<(String, SessionView), String> {
    let profile = nakama::get_my_profile(client, server_url, token).await?;
    let cloud_save =
        nakama::fetch_cloud_save_summary(client, server_url, token, &profile.user_id).await;
    let uid = profile.uid.clone();
    let user_id = profile.user_id.clone();
    let view = SessionView {
        logged_in: true,
        user_id: user_id.clone(),
        username: profile.username,
        display_name: profile.display_name,
        uid,
        role: nakama::normalize_role(&profile.role),
        avatar_url: profile.avatar_url,
        world_join_mode: profile.world_join_mode,
        server_url: server_url.to_string(),
        cloud_save,
        active_lobby: profile.active_lobby,
        license_active: profile.license_active,
        license_edition: profile.license_edition,
        license_expires_at: profile.license_expires_at,
        license_error: profile.license_error,
        banned: profile.banned,
        ban_reason: profile.ban_reason,
    };
    Ok((user_id, view))
}

fn logged_out_view(server_url: &str) -> SessionView {
    SessionView {
        logged_in: false,
        role: "player".to_string(),
        server_url: server_url.to_string(),
        cloud_save: CloudSaveSummary::default(),
        ..SessionView::default()
    }
}

async fn ensure_fresh_token(app: &AppHandle, state: &State<'_, AppState>) -> (PersistedState, String) {
    let (mut persisted, mut token) = {
        let p = state.persisted.lock().unwrap().clone();
        let t = state.token.lock().unwrap().clone();
        (p, t)
    };
    if !persisted.refresh_token.is_empty() {
        if let Ok(fresh) = nakama::refresh_session(
            &state.client,
            &persisted.server_url,
            &persisted.server_key,
            &persisted.refresh_token,
        )
        .await
        {
            token = fresh.token;
            persisted.refresh_token = fresh.refresh_token.clone();
            {
                let mut p = state.persisted.lock().unwrap();
                p.refresh_token = fresh.refresh_token;
                save_persisted(app, &p);
            }
            *state.token.lock().unwrap() = token.clone();
        }
    }
    (persisted, token)
}

#[tauri::command]
async fn restore_session(app: AppHandle, state: State<'_, AppState>) -> Result<SessionView, String> {
    let (server_url, server_key, refresh_token) = {
        let p = state.persisted.lock().unwrap();
        (p.server_url.clone(), p.server_key.clone(), p.refresh_token.clone())
    };
    if refresh_token.trim().is_empty() {
        state.ws.disconnect(&app, &server_url);
        return Ok(logged_out_view(&server_url));
    }
    let Ok(tokens) = nakama::refresh_session(&state.client, &server_url, &server_key, &refresh_token).await else {
        return Ok(clear_auth_state(&app, &state));
    };

    let (user_id, view) = match build_session_view(&state.client, &server_url, &tokens.token).await {
        Ok(res) => res,
        Err(_) => {
            return Ok(clear_auth_state(&app, &state));
        }
    };
    {
        let mut p = state.persisted.lock().unwrap();
        p.refresh_token = tokens.refresh_token;
        save_persisted(&app, &p);
    }
    *state.token.lock().unwrap() = tokens.token.clone();
    *state.user_id.lock().unwrap() = user_id;
    state.ws.connect(app, server_url, tokens.token);
    Ok(view)
}

#[tauri::command]
async fn login_email(
    app: AppHandle,
    state: State<'_, AppState>,
    email: String,
    password: String,
    _username: String,
    create: bool,
) -> Result<SessionView, String> {
    if create {
        return Err("Account-Erstellung ist nur noch mit Lizenzkey ueber https://shadowspore.com moeglich.".to_string());
    }
    let (server_url, server_key) = {
        let p = state.persisted.lock().unwrap();
        (p.server_url.clone(), p.server_key.clone())
    };
    let tokens = nakama::authenticate_email(
        &state.client,
        &server_url,
        &server_key,
        &email,
        &password,
        "",
        false,
    )
    .await?;
    let (user_id, view) = build_session_view(&state.client, &server_url, &tokens.token).await?;
    {
        let mut p = state.persisted.lock().unwrap();
        p.refresh_token = tokens.refresh_token;
        save_persisted(&app, &p);
    }
    *state.token.lock().unwrap() = tokens.token.clone();
    *state.user_id.lock().unwrap() = user_id;
    state.ws.connect(app, server_url, tokens.token);
    Ok(view)
}

fn clear_auth_state(app: &AppHandle, state: &AppState) -> SessionView {
    let server_url = {
        let mut p = state.persisted.lock().unwrap();
        p.refresh_token.clear();
        save_persisted(app, &p);
        p.server_url.clone()
    };
    *state.token.lock().unwrap() = String::new();
    *state.user_id.lock().unwrap() = String::new();
    state.ws.disconnect(app, &server_url);
    logged_out_view(&server_url)
}

#[tauri::command]
fn logout(app: AppHandle, state: State<'_, AppState>) -> SessionView {
    clear_auth_state(&app, &state)
}

#[tauri::command]
async fn refresh_profile(app: AppHandle, state: State<'_, AppState>) -> Result<SessionView, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Ok(logged_out_view(&server_url));
    }
    match build_session_view(&state.client, &server_url, &token).await {
        Ok((user_id, view)) => {
            *state.user_id.lock().unwrap() = user_id;
            Ok(view)
        }
        Err(err) => {
            let lower = err.to_ascii_lowercase();
            if lower.contains("existiert nicht mehr")
                || lower.contains("not found")
                || lower.contains("23503")
                || lower.contains("unauthorized")
            {
                return Ok(clear_auth_state(&app, &state));
            }
            Err(err)
        }
    }
}

#[tauri::command]
async fn list_friends(state: State<'_, AppState>) -> Result<Vec<FriendView>, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::list_friends(&state.client, &server_url, &token).await
}

#[tauri::command]
async fn lookup_uid(state: State<'_, AppState>, query: String) -> Result<LookupView, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::lookup_uid(&state.client, &server_url, &token, &query).await
}

#[tauri::command]
async fn add_friend(state: State<'_, AppState>, query: String) -> Result<(), String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::friend_action(
        &state.client,
        &server_url,
        &token,
        "add_friend_by_uid",
        json!({ "uid": query.trim() }),
    )
    .await
}

#[tauri::command]
async fn accept_friend(state: State<'_, AppState>, user_id: String) -> Result<(), String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::friend_action(
        &state.client,
        &server_url,
        &token,
        "accept_friend",
        json!({ "user_id": user_id }),
    )
    .await
}

#[tauri::command]
async fn remove_friend(state: State<'_, AppState>, user_id: String) -> Result<(), String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::friend_action(
        &state.client,
        &server_url,
        &token,
        "remove_friend",
        json!({ "user_id": user_id }),
    )
    .await
}

fn require_auth(state: &State<'_, AppState>) -> Result<(String, String), String> {
    let (server_url, _, token, _) = snapshot_auth(state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    Ok((server_url, token))
}

#[tauri::command]
async fn admin_set_role(
    state: State<'_, AppState>,
    target: String,
    role: String,
) -> Result<SessionView, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_set_role(&state.client, &server_url, &token, &target, &role).await?;
    let (user_id, view) = build_session_view(&state.client, &server_url, &token).await?;
    *state.user_id.lock().unwrap() = user_id;
    Ok(view)
}

#[tauri::command]
async fn admin_issue_license_key(
    state: State<'_, AppState>,
    count: i32,
    edition: String,
    role_grant: String,
    note: String,
    expires_days: Option<i32>,
) -> Result<Vec<LicenseKeyView>, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_issue_license_key(
        &state.client,
        &server_url,
        &token,
        count,
        &edition,
        &role_grant,
        &note,
        expires_days.unwrap_or(0),
    )
    .await
}

#[tauri::command]
async fn admin_list_license_keys(
    state: State<'_, AppState>,
    status: String,
    query: Option<String>,
) -> Result<Vec<LicenseKeyView>, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_list_license_keys(
        &state.client,
        &server_url,
        &token,
        &status,
        &query.unwrap_or_default(),
    )
    .await
}

#[tauri::command]
async fn admin_set_license(
    state: State<'_, AppState>,
    target: String,
    active: bool,
) -> Result<(), String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_set_license(&state.client, &server_url, &token, &target, active).await
}

#[tauri::command]
async fn admin_set_ban(
    state: State<'_, AppState>,
    target: String,
    banned: bool,
    reason: String,
) -> Result<(), String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_set_ban(&state.client, &server_url, &token, &target, banned, &reason).await
}

#[tauri::command]
async fn admin_list_security_events(state: State<'_, AppState>) -> Result<Vec<SecurityEventView>, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_list_security_events(&state.client, &server_url, &token).await
}

#[tauri::command]
async fn admin_overview(state: State<'_, AppState>) -> Result<AdminOverviewView, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_overview(&state.client, &server_url, &token).await
}

#[tauri::command]
async fn admin_list_accounts(
    state: State<'_, AppState>,
    query: Option<String>,
    role: Option<String>,
    status: Option<String>,
) -> Result<Vec<AdminAccountView>, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_list_accounts(
        &state.client,
        &server_url,
        &token,
        &query.unwrap_or_default(),
        &role.unwrap_or_else(|| "all".to_string()),
        &status.unwrap_or_else(|| "all".to_string()),
    )
    .await
}

#[tauri::command]
async fn admin_list_active_worlds(state: State<'_, AppState>) -> Result<Vec<AdminWorldView>, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_list_active_worlds(&state.client, &server_url, &token).await
}

#[tauri::command]
async fn admin_force_join(
    state: State<'_, AppState>,
    query: Option<String>,
    match_id: Option<String>,
    room_code: Option<String>,
    host_user_id: Option<String>,
) -> Result<AdminForceJoinView, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_force_join(
        &state.client,
        &server_url,
        &token,
        &query.unwrap_or_default(),
        &match_id.unwrap_or_default(),
        &room_code.unwrap_or_default(),
        &host_user_id.unwrap_or_default(),
    )
    .await
}

#[tauri::command]
async fn admin_kick_match_peer(
    state: State<'_, AppState>,
    match_id: String,
    target_user_id: String,
    cooldown: Option<i32>,
) -> Result<(), String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_kick_match_peer(
        &state.client,
        &server_url,
        &token,
        &match_id,
        &target_user_id,
        cooldown.unwrap_or(60),
    )
    .await
}

#[tauri::command]
async fn admin_close_world(
    state: State<'_, AppState>,
    match_id: Option<String>,
    host_user_id: Option<String>,
) -> Result<(), String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_close_world(
        &state.client,
        &server_url,
        &token,
        &match_id.unwrap_or_default(),
        &host_user_id.unwrap_or_default(),
    )
    .await
}

#[tauri::command]
async fn admin_get_build_config(state: State<'_, AppState>) -> Result<AdminBuildConfigView, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_get_build_config(&state.client, &server_url, &token).await
}

#[tauri::command]
async fn admin_register_build(
    state: State<'_, AppState>,
    exe_sha256: Option<String>,
    version: Option<String>,
    enforce: Option<bool>,
    remove_sha256: Option<String>,
    clear: Option<bool>,
) -> Result<AdminBuildConfigView, String> {
    let (server_url, token) = require_auth(&state)?;
    nakama::admin_register_build(
        &state.client,
        &server_url,
        &token,
        &exe_sha256.unwrap_or_default(),
        &version.unwrap_or_default(),
        enforce,
        &remove_sha256.unwrap_or_default(),
        clear.unwrap_or(false),
    )
    .await
}

#[tauri::command]
async fn inspect_local_build(state: State<'_, AppState>) -> Result<LocalBuildInfoView, String> {
    let persisted = state.persisted.lock().unwrap().clone();
    tauri::async_runtime::spawn_blocking(move || game::inspect_local_build(&persisted))
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn set_avatar(state: State<'_, AppState>, avatar: String) -> Result<SessionView, String> {
    let (server_url, _key, token, _uid) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::set_avatar(&state.client, &server_url, &token, &avatar).await?;
    let (_, view) = build_session_view(&state.client, &server_url, &token).await?;
    Ok(view)
}

#[tauri::command]
async fn get_game_status(state: State<'_, AppState>) -> Result<GameStatusView, String> {
    let persisted = state.persisted.lock().unwrap().clone();
    Ok(game::inspect_game_status(&state.client, &persisted).await)
}

#[tauri::command]
fn get_settings(state: State<'_, AppState>) -> LauncherConfigView {
    let p = state.persisted.lock().unwrap();
    LauncherConfigView {
        server_url: p.server_url.clone(),
        server_key: p.server_key.clone(),
        game_exe_path: p.game_exe_path.clone(),
        godot_exe_path: p.godot_exe_path.clone(),
        manifest_url: p.manifest_url.clone(),
    }
}

#[tauri::command]
fn get_server_presets() -> ServerPresetsView {
    ServerPresetsView {
        dev_url: DEV_SERVER_URL.to_string(),
        dev_key: DEV_SERVER_KEY.to_string(),
        live_url: LIVE_SERVER_URL.to_string(),
        live_key: live_server_key().to_string(),
        live_manifest_url: LIVE_MANIFEST_URL.to_string(),
    }
}

#[tauri::command]
fn save_settings(
    app: AppHandle,
    state: State<'_, AppState>,
    settings: LauncherConfigView,
) -> Result<LauncherConfigView, String> {
    let (url, key, manifest, godot_path) = if cfg!(not(debug_assertions)) {
        (
            LIVE_SERVER_URL.to_string(),
            live_server_key().to_string(),
            LIVE_MANIFEST_URL.to_string(),
            String::new(),
        )
    } else {
        let u = settings.server_url.trim().trim_end_matches('/').to_string();
        if u.is_empty() || (!u.starts_with("http://") && !u.starts_with("https://")) {
            return Err("Server-URL muss mit http:// oder https:// beginnen.".to_string());
        }
        let k = settings.server_key.trim().to_string();
        if k.is_empty() {
            return Err("Server-Key darf nicht leer sein.".to_string());
        }
        (
            u,
            k,
            settings.manifest_url.trim().to_string(),
            settings.godot_exe_path.trim().to_string(),
        )
    };
    let server_changed;
    let out = {
        let mut p = state.persisted.lock().unwrap();
        server_changed = p.server_url != url || p.server_key != key;
        p.server_url = url.clone();
        p.server_key = key;
        p.game_exe_path = settings.game_exe_path.trim().to_string();
        p.godot_exe_path = godot_path;
        p.manifest_url = manifest;
        if server_changed {
            p.refresh_token.clear();
        }
        save_persisted(&app, &p);
        LauncherConfigView {
            server_url: p.server_url.clone(),
            server_key: p.server_key.clone(),
            game_exe_path: p.game_exe_path.clone(),
            godot_exe_path: p.godot_exe_path.clone(),
            manifest_url: p.manifest_url.clone(),
        }
    };
    if server_changed {
        *state.token.lock().unwrap() = String::new();
        *state.user_id.lock().unwrap() = String::new();
        state.ws.disconnect(&app, &url);
    }
    Ok(out)
}

#[tauri::command]
async fn set_world_join_mode(state: State<'_, AppState>, mode: String) -> Result<SessionView, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::set_world_join_mode(&state.client, &server_url, &token, &mode).await?;
    let (user_id, view) = build_session_view(&state.client, &server_url, &token).await?;
    *state.user_id.lock().unwrap() = user_id;
    Ok(view)
}

#[tauri::command]
async fn coop_invite_friend(
    state: State<'_, AppState>,
    target_user_id: String,
) -> Result<String, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::coop_invite_friend(&state.client, &server_url, &token, &target_user_id).await
}

#[tauri::command]
async fn coop_request_join(
    state: State<'_, AppState>,
    host_user_id: String,
    host_uid: String,
    room_code: String,
) -> Result<JoinRequestResultView, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::coop_request_join(
        &state.client,
        &server_url,
        &token,
        &host_user_id,
        &host_uid,
        &room_code,
    )
    .await
}

#[tauri::command]
async fn coop_respond_join_request(
    state: State<'_, AppState>,
    requester_user_id: String,
    accept: bool,
    notification_id: String,
) -> Result<(), String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::coop_respond_join_request(&state.client, &server_url, &token, &requester_user_id, accept)
        .await?;
    if !notification_id.trim().is_empty() {
        let _ = nakama::delete_notification(&state.client, &server_url, &token, &notification_id).await;
    }
    Ok(())
}

#[tauri::command]
async fn coop_resolve_code(
    state: State<'_, AppState>,
    room_code: String,
) -> Result<ResolveCodeView, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::coop_resolve_code(&state.client, &server_url, &token, &room_code).await
}

#[tauri::command]
async fn fetch_notifications(state: State<'_, AppState>) -> Result<Vec<CoopNotificationView>, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Ok(Vec::new());
    }
    nakama::fetch_notifications(&state.client, &server_url, &token).await
}

#[tauri::command]
async fn dismiss_notification(
    state: State<'_, AppState>,
    notification_id: String,
) -> Result<(), String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Ok(());
    }
    nakama::delete_notification(&state.client, &server_url, &token, &notification_id).await
}

#[tauri::command]
async fn game_running(state: State<'_, AppState>) -> Result<bool, String> {
    Ok(game::is_game_running(&state.client).await)
}

async fn prepare_and_launch(
    app: &AppHandle,
    state: &State<'_, AppState>,
    intent: GameLaunchIntent,
) -> Result<String, String> {
    let (persisted, token) = ensure_fresh_token(app, state).await;
    if token.trim().is_empty() {
        return Err("Anmeldung erforderlich: Bitte zuerst mit deinem Shadowspore-Konto einloggen.".to_string());
    }

    let (user_id, session) = build_session_view(&state.client, &persisted.server_url, &token).await?;
    *state.user_id.lock().unwrap() = user_id;
    if session.banned {
        let reason = if session.ban_reason.trim().is_empty() {
            "Konto gesperrt.".to_string()
        } else {
            format!("Konto gesperrt: {}", session.ban_reason)
        };
        return Err(reason);
    }
    if !session.license_active {
        let reason = if session.license_error.trim().is_empty() {
            "Keine aktive Spiellizenz. Bitte Lizenzkey auf https://shadowspore.com einloesen.".to_string()
        } else {
            format!("Lizenz inaktiv: {}", session.license_error)
        };
        return Err(reason);
    }

    let prepared = match game::prepare_launch_exe(&state.client, &persisted).await {
        Ok(p) => p,
        Err(block) => {
            nakama::report_security_event(
                &state.client,
                &persisted.server_url,
                &token,
                &block.kind,
                &block.message,
                "high",
            )
            .await;
            return Err(block.message);
        }
    };

    let ticket = nakama::issue_launch_ticket(
        &state.client,
        &persisted.server_url,
        &token,
        &prepared.exe_sha256,
        &prepared.local_version,
        env!("CARGO_PKG_VERSION"),
    )
    .await?;

    let launch_label = game::launch_or_dispatch(
        &state.client,
        &persisted,
        &token,
        &persisted.refresh_token,
        &ticket,
        &prepared,
        intent,
    )
    .await?;

    game::spawn_runtime_watchdog(state.client.clone(), persisted.server_url, token);
    Ok(launch_label)
}

#[tauri::command]
async fn launch_game(app: AppHandle, state: State<'_, AppState>) -> Result<String, String> {
    prepare_and_launch(&app, &state, GameLaunchIntent::Play).await
}

#[tauri::command]
async fn launch_host_coop(
    app: AppHandle,
    state: State<'_, AppState>,
    world_name: Option<String>,
    join_mode: Option<String>,
) -> Result<String, String> {
    prepare_and_launch(
        &app,
        &state,
        GameLaunchIntent::HostCoop { world_name, join_mode },
    )
    .await
}

#[tauri::command]
async fn launch_join_match(
    app: AppHandle,
    state: State<'_, AppState>,
    match_id: String,
    room_code: Option<String>,
    world_name: Option<String>,
) -> Result<String, String> {
    prepare_and_launch(
        &app,
        &state,
        GameLaunchIntent::JoinMatch {
            match_id,
            room_code,
            world_name,
        },
    )
    .await
}

#[tauri::command]
async fn launch_join_code(
    app: AppHandle,
    state: State<'_, AppState>,
    room_code: String,
) -> Result<String, String> {
    prepare_and_launch(&app, &state, GameLaunchIntent::JoinCode { room_code }).await
}

#[tauri::command]
async fn install_game_update(
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<GameStatusView, String> {
    let persisted = state.persisted.lock().unwrap().clone();
    updater::install_update(&app, &state.client, &persisted).await
}

#[tauri::command]
fn get_changelog() -> String {
    content::read_changelog()
}

#[tauri::command]
async fn read_doc_image(rel: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || content::read_doc_image(&rel))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
fn open_external(url: String) -> Result<(), String> {
    content::open_external(&url)
}

// ---------------------------------------------------------------- window while the game runs
const TRAY_ID: &str = "launcher-tray";

/// While the game runs the launcher steps aside: hidden into the tray (an icon with
/// Öffnen / Beenden) or simply minimised.
#[tauri::command]
fn hide_while_playing(app: AppHandle, tray: bool) -> Result<(), String> {
    let win = app.get_webview_window("main").ok_or("Kein Launcher-Fenster.")?;
    if !tray {
        return win.minimize().map_err(|e| e.to_string());
    }
    if app.tray_by_id(TRAY_ID).is_none() {
        use tauri::menu::{Menu, MenuItem};
        use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
        let open = MenuItem::with_id(&app, "tray-open", "Launcher öffnen", true, None::<&str>)
            .map_err(|e| e.to_string())?;
        let quit = MenuItem::with_id(&app, "tray-quit", "Launcher beenden", true, None::<&str>)
            .map_err(|e| e.to_string())?;
        let menu = Menu::with_items(&app, &[&open, &quit]).map_err(|e| e.to_string())?;
        let mut builder = TrayIconBuilder::with_id(TRAY_ID)
            .tooltip("Shadowspore Launcher")
            .menu(&menu)
            .show_menu_on_left_click(false)
            .on_menu_event(|app, event| match event.id.as_ref() {
                "tray-open" => {
                    let _ = show_launcher(app);
                }
                "tray-quit" => app.exit(0),
                _ => {}
            })
            .on_tray_icon_event(|tray, event| {
                if let TrayIconEvent::Click {
                    button: MouseButton::Left,
                    button_state: MouseButtonState::Up,
                    ..
                } = event
                {
                    let _ = show_launcher(tray.app_handle());
                }
            });
        if let Some(icon) = app.default_window_icon() {
            builder = builder.icon(icon.clone());
        }
        builder.build(&app).map_err(|e| e.to_string())?;
    }
    win.hide().map_err(|e| e.to_string())
}

fn show_launcher(app: &AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("main") {
        win.show().map_err(|e| e.to_string())?;
        let _ = win.unminimize();
        let _ = win.set_focus();
    }
    let _ = app.remove_tray_by_id(TRAY_ID);
    Ok(())
}

/// Brings the launcher back when the game has ended.
#[tauri::command]
fn restore_launcher(app: AppHandle) -> Result<(), String> {
    show_launcher(&app)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let persisted = load_persisted(app.handle());
            app.manage(AppState {
                client: Client::new(),
                persisted: Mutex::new(persisted),
                token: Mutex::new(String::new()),
                user_id: Mutex::new(String::new()),
                ws: WsController::new(),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            restore_session,
            login_email,
            logout,
            refresh_profile,
            list_friends,
            lookup_uid,
            add_friend,
            accept_friend,
            remove_friend,
            admin_set_role,
            admin_issue_license_key,
            admin_list_license_keys,
            admin_set_license,
            admin_set_ban,
            admin_list_security_events,
            admin_overview,
            admin_list_accounts,
            admin_list_active_worlds,
            admin_force_join,
            admin_kick_match_peer,
            admin_close_world,
            admin_get_build_config,
            admin_register_build,
            inspect_local_build,
            set_avatar,
            game_running,
            set_world_join_mode,
            coop_invite_friend,
            coop_request_join,
            coop_respond_join_request,
            coop_resolve_code,
            fetch_notifications,
            dismiss_notification,
            get_game_status,
            get_settings,
            get_server_presets,
            save_settings,
            launch_game,
            launch_host_coop,
            launch_join_match,
            launch_join_code,
            install_game_update,
            get_changelog,
            read_doc_image,
            open_external,
            hide_while_playing,
            restore_launcher,
        ])
        .run(tauri::generate_context!())
        .expect("error while running shadowspore launcher");
}
