mod content;
mod game;
mod models;
mod nakama;

use std::path::PathBuf;
use std::sync::Mutex;

use reqwest::Client;
use serde_json::json;
use tauri::{AppHandle, Manager, State};

use models::{
    CloudSaveSummary, FriendView, GameStatusView, LauncherConfigView, LookupView, PersistedState,
    SessionView,
};

struct AppState {
    client: Client,
    persisted: Mutex<PersistedState>,
    token: Mutex<String>,
    user_id: Mutex<String>,
}

fn state_file_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("App-Data-Pfad nicht gefunden: {}", e))?;
    std::fs::create_dir_all(&dir).map_err(|e| format!("Ordnerfehler: {}", e))?;
    Ok(dir.join("state.json"))
}

fn load_persisted(app: &AppHandle) -> PersistedState {
    let Ok(path) = state_file_path(app) else {
        return PersistedState::default();
    };
    let Ok(raw) = std::fs::read_to_string(path) else {
        return PersistedState::default();
    };
    serde_json::from_str::<PersistedState>(&raw).unwrap_or_default()
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
        world_join_mode: profile.world_join_mode,
        server_url: server_url.to_string(),
        cloud_save,
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

#[tauri::command]
async fn restore_session(app: AppHandle, state: State<'_, AppState>) -> Result<SessionView, String> {
    let (server_url, server_key, refresh_token) = {
        let p = state.persisted.lock().unwrap();
        (p.server_url.clone(), p.server_key.clone(), p.refresh_token.clone())
    };
    if refresh_token.trim().is_empty() {
        return Ok(logged_out_view(&server_url));
    }
    let Ok(tokens) = nakama::refresh_session(&state.client, &server_url, &server_key, &refresh_token).await else {
        {
            let mut p = state.persisted.lock().unwrap();
            p.refresh_token.clear();
            save_persisted(&app, &p);
        }
        *state.token.lock().unwrap() = String::new();
        *state.user_id.lock().unwrap() = String::new();
        return Ok(logged_out_view(&server_url));
    };

    let (user_id, view) = match build_session_view(&state.client, &server_url, &tokens.token).await {
        Ok(res) => res,
        Err(_) => return Ok(logged_out_view(&server_url)),
    };
    {
        let mut p = state.persisted.lock().unwrap();
        p.refresh_token = tokens.refresh_token;
        save_persisted(&app, &p);
    }
    *state.token.lock().unwrap() = tokens.token;
    *state.user_id.lock().unwrap() = user_id;
    Ok(view)
}

#[tauri::command]
async fn login_email(
    app: AppHandle,
    state: State<'_, AppState>,
    email: String,
    password: String,
    username: String,
    create: bool,
) -> Result<SessionView, String> {
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
        &username,
        create,
    )
    .await?;
    let (user_id, view) = build_session_view(&state.client, &server_url, &tokens.token).await?;
    {
        let mut p = state.persisted.lock().unwrap();
        p.refresh_token = tokens.refresh_token;
        save_persisted(&app, &p);
    }
    *state.token.lock().unwrap() = tokens.token;
    *state.user_id.lock().unwrap() = user_id;
    Ok(view)
}

#[tauri::command]
fn logout(app: AppHandle, state: State<'_, AppState>) -> SessionView {
    let server_url = {
        let mut p = state.persisted.lock().unwrap();
        p.refresh_token.clear();
        save_persisted(&app, &p);
        p.server_url.clone()
    };
    *state.token.lock().unwrap() = String::new();
    *state.user_id.lock().unwrap() = String::new();
    logged_out_view(&server_url)
}

#[tauri::command]
async fn refresh_profile(state: State<'_, AppState>) -> Result<SessionView, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Ok(logged_out_view(&server_url));
    }
    let (user_id, view) = build_session_view(&state.client, &server_url, &token).await?;
    *state.user_id.lock().unwrap() = user_id;
    Ok(view)
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

#[tauri::command]
async fn admin_set_role(
    state: State<'_, AppState>,
    target: String,
    role: String,
) -> Result<SessionView, String> {
    let (server_url, _, token, _) = snapshot_auth(&state);
    if token.is_empty() {
        return Err("Nicht angemeldet.".to_string());
    }
    nakama::admin_set_role(&state.client, &server_url, &token, &target, &role).await?;
    let (user_id, view) = build_session_view(&state.client, &server_url, &token).await?;
    *state.user_id.lock().unwrap() = user_id;
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
fn save_settings(
    app: AppHandle,
    state: State<'_, AppState>,
    settings: LauncherConfigView,
) -> Result<LauncherConfigView, String> {
    let url = settings.server_url.trim().trim_end_matches('/').to_string();
    if url.is_empty() || (!url.starts_with("http://") && !url.starts_with("https://")) {
        return Err("Server-URL muss mit http:// oder https:// beginnen.".to_string());
    }
    let key = settings.server_key.trim().to_string();
    if key.is_empty() {
        return Err("Server-Key darf nicht leer sein.".to_string());
    }
    let mut p = state.persisted.lock().unwrap();
    p.server_url = url;
    p.server_key = key;
    p.game_exe_path = settings.game_exe_path.trim().to_string();
    p.godot_exe_path = settings.godot_exe_path.trim().to_string();
    p.manifest_url = settings.manifest_url.trim().to_string();
    save_persisted(&app, &p);
    Ok(LauncherConfigView {
        server_url: p.server_url.clone(),
        server_key: p.server_key.clone(),
        game_exe_path: p.game_exe_path.clone(),
        godot_exe_path: p.godot_exe_path.clone(),
        manifest_url: p.manifest_url.clone(),
    })
}

#[tauri::command]
async fn launch_game(app: AppHandle, state: State<'_, AppState>) -> Result<String, String> {
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
                save_persisted(&app, &p);
            }
            *state.token.lock().unwrap() = token.clone();
        }
    }
    game::spawn_shadowspore(&persisted, &token, &persisted.refresh_token)
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
            get_game_status,
            get_settings,
            save_settings,
            launch_game,
            get_changelog,
            read_doc_image,
            open_external,
        ])
        .run(tauri::generate_context!())
        .expect("error while running shadowspore launcher");
}
