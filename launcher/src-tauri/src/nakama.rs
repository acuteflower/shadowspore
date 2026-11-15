use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::Client;
use serde::{de::DeserializeOwned, Deserialize};
use serde_json::{json, Value};

use crate::models::{
    deserialize_vec_or_empty, ActiveLobbyView, AdminAccountView, AdminBuildConfigView,
    AdminForceJoinView, AdminOverviewView, AdminWorldView, CloudSaveSummary, CoopNotificationView,
    FriendView, JoinRequestResultView, LicenseKeyView, LookupView, ResolveCodeView,
    SecurityEventView,
};

#[derive(Debug, Deserialize)]
pub struct AuthTokens {
    pub token: String,
    pub refresh_token: String,
}

#[derive(Debug, Deserialize)]
pub struct RpcProfile {
    pub user_id: String,
    pub username: String,
    #[serde(default)]
    pub display_name: String,
    pub uid: String,
    #[serde(default = "default_join_mode")]
    pub world_join_mode: String,
    #[serde(default = "default_role")]
    pub role: String,
    #[serde(default, deserialize_with = "deserialize_optional_lobby")]
    pub active_lobby: Option<ActiveLobbyView>,
    #[serde(default)]
    pub avatar_url: String,
    #[serde(default)]
    pub license_active: bool,
    #[serde(default)]
    pub license_edition: String,
    #[serde(default)]
    pub license_expires_at: i64,
    #[serde(default)]
    pub license_error: String,
    #[serde(default)]
    pub banned: bool,
    #[serde(default)]
    pub ban_reason: String,
}

/// Profile pictures the launcher ships; nothing else may be written to avatar_url.
pub const AVATAR_IDS: [&str; 2] = ["ellie_lichtung", "ellie_leere"];

/// Stores the chosen profile picture id in the account's standard avatar_url field.
pub async fn set_avatar(client: &Client, base_url: &str, token: &str, avatar: &str) -> Result<(), String> {
    if !AVATAR_IDS.contains(&avatar) {
        return Err("Unbekanntes Profilbild.".to_string());
    }
    let endpoint = format!("{}/v2/account", clean_base(base_url));
    let resp = client
        .put(endpoint)
        .bearer_auth(token)
        .json(&json!({ "avatar_url": avatar }))
        .send()
        .await
        .map_err(|e| format!("Profilbild konnte nicht gespeichert werden: {}", e))?;
    if !resp.status().is_success() {
        return Err(extract_error(resp).await);
    }
    Ok(())
}

fn deserialize_optional_lobby<'de, D>(deserializer: D) -> Result<Option<ActiveLobbyView>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let val = Value::deserialize(deserializer)?;
    if val.is_null() || !val.is_object() {
        return Ok(None);
    }
    let lobby: ActiveLobbyView = serde_json::from_value(val).map_err(serde::de::Error::custom)?;
    if lobby.match_id.trim().is_empty() {
        Ok(None)
    } else {
        Ok(Some(lobby))
    }
}

fn default_join_mode() -> String {
    "ask".to_string()
}

fn default_role() -> String {
    "player".to_string()
}

pub fn normalize_role(raw: &str) -> String {
    match raw.trim().to_ascii_lowercase().as_str() {
        "admin" => "admin".to_string(),
        "moderator" => "moderator".to_string(),
        "tester" => "tester".to_string(),
        _ => "player".to_string(),
    }
}

#[derive(Debug, Deserialize)]
struct RpcEnvelope {
    payload: String,
}

#[derive(Debug, Deserialize)]
struct StorageListResponse {
    #[serde(default)]
    objects: Vec<StorageObject>,
}

#[derive(Debug, Deserialize)]
struct StorageObject {
    #[serde(default)]
    value: String,
}

#[derive(Debug, Deserialize)]
struct RpcFriendsPayload {
    #[serde(default)]
    ok: bool,
    #[serde(default, deserialize_with = "deserialize_vec_or_empty")]
    friends: Vec<FriendView>,
    #[serde(default)]
    error: String,
}

fn parse_rpc_ok(raw: &str, default_err: &str) -> Result<Value, String> {
    let val: Value = serde_json::from_str(raw).map_err(|e| e.to_string())?;
    if !val.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return Err(val
            .get("error")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(default_err)
            .to_string());
    }
    Ok(val)
}

fn parse_rpc_vec<T: DeserializeOwned>(val: &Value, key: &str) -> Result<Vec<T>, String> {
    let arr = val.get(key).cloned().unwrap_or_else(|| json!([]));
    if !arr.is_array() {
        return Ok(Vec::new());
    }
    serde_json::from_value(arr).map_err(|e| e.to_string())
}

fn build_target_payload(target: &str, uid_field: &str, uuid_field: &str) -> Value {
    let clean = target.trim();
    if clean.chars().all(|c| c.is_ascii_digit()) {
        json!({ uid_field: clean })
    } else if clean.len() == 36 && clean.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
        json!({ uuid_field: clean })
    } else {
        json!({ "query": clean })
    }
}

#[derive(Debug, Deserialize)]
struct RpcActionResponse {
    #[serde(default)]
    ok: bool,
    #[serde(default)]
    error: String,
}

fn clean_base(url: &str) -> String {
    url.trim().trim_end_matches('/').to_string()
}

fn basic_header(server_key: &str) -> String {
    let raw = format!("{}:", server_key.trim());
    format!("Basic {}", STANDARD.encode(raw.as_bytes()))
}

async fn extract_error(resp: reqwest::Response) -> String {
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if let Ok(val) = serde_json::from_str::<Value>(&text) {
        if let Some(msg) = val.get("message").and_then(|v| v.as_str()) {
            return msg.to_string();
        }
    }
    if text.trim().is_empty() {
        format!("Nakama HTTP {}", status.as_u16())
    } else {
        text
    }
}

pub async fn authenticate_email(
    client: &Client,
    base_url: &str,
    server_key: &str,
    email: &str,
    password: &str,
    _username: &str,
    create: bool,
) -> Result<AuthTokens, String> {
    if create {
        return Err("Kontoerstellung im Launcher deaktiviert. Bitte auf shadowspore.com mit Lizenzkey registrieren.".to_string());
    }
    let clean_email = email.trim().to_lowercase();
    if clean_email.is_empty() || !clean_email.contains('@') {
        return Err("Bitte eine gueltige E-Mail-Adresse eingeben.".to_string());
    }
    if password.chars().count() < 8 {
        return Err("Das Passwort muss mindestens 8 Zeichen lang sein.".to_string());
    }
    let endpoint = format!(
        "{}/v2/account/authenticate/email?create=false",
        clean_base(base_url)
    );

    let resp = client
        .post(endpoint)
        .header("Authorization", basic_header(server_key))
        .json(&json!({ "email": clean_email, "password": password }))
        .send()
        .await
        .map_err(|e| format!("Verbindung zu Nakama fehlgeschlagen: {}", e))?;

    if !resp.status().is_success() {
        return Err(extract_error(resp).await);
    }
    resp.json::<AuthTokens>()
        .await
        .map_err(|e| format!("Ungueltige Auth-Antwort: {}", e))
}

pub async fn refresh_session(
    client: &Client,
    base_url: &str,
    server_key: &str,
    refresh_token: &str,
) -> Result<AuthTokens, String> {
    let endpoint = format!("{}/v2/account/session/refresh", clean_base(base_url));
    let resp = client
        .post(endpoint)
        .header("Authorization", basic_header(server_key))
        .json(&json!({ "token": refresh_token }))
        .send()
        .await
        .map_err(|e| format!("Session-Refresh fehlgeschlagen: {}", e))?;
    if !resp.status().is_success() {
        return Err(extract_error(resp).await);
    }
    resp.json::<AuthTokens>()
        .await
        .map_err(|e| format!("Ungueltige Refresh-Antwort: {}", e))
}

pub async fn call_rpc_raw(
    client: &Client,
    base_url: &str,
    token: &str,
    rpc_id: &str,
    payload: &Value,
) -> Result<String, String> {
    let endpoint = format!("{}/v2/rpc/{}", clean_base(base_url), rpc_id);
    // Nakama's REST gateway expects Rpc.payload as a JSON-encoded string literal.
    let inner = serde_json::to_string(payload).map_err(|e| e.to_string())?;
    let resp = client
        .post(endpoint)
        .bearer_auth(token)
        .json(&inner)
        .send()
        .await
        .map_err(|e| format!("RPC {} fehlgeschlagen: {}", rpc_id, e))?;
    if !resp.status().is_success() {
        return Err(extract_error(resp).await);
    }
    let env: RpcEnvelope = resp
        .json()
        .await
        .map_err(|e| format!("Ungueltige RPC-Antwort: {}", e))?;
    Ok(env.payload)
}

pub async fn get_my_profile(
    client: &Client,
    base_url: &str,
    token: &str,
) -> Result<RpcProfile, String> {
    let raw = call_rpc_raw(client, base_url, token, "get_my_profile", &json!({})).await?;
    serde_json::from_str::<RpcProfile>(&raw)
        .map_err(|e| format!("Profil konnte nicht geparst werden: {}", e))
}

pub async fn fetch_cloud_save_summary(
    client: &Client,
    base_url: &str,
    token: &str,
    user_id: &str,
) -> CloudSaveSummary {
    let endpoint = format!("{}/v2/storage", clean_base(base_url));
    let body = json!({
        "object_ids": [
            { "collection": "saves", "key": "world_state", "user_id": user_id },
            { "collection": "saves", "key": "world_meta", "user_id": user_id }
        ]
    });
    let Ok(resp) = client.post(endpoint).bearer_auth(token).json(&body).send().await else {
        return CloudSaveSummary::default();
    };
    if !resp.status().is_success() {
        return CloudSaveSummary::default();
    }
    let Ok(list) = resp.json::<StorageListResponse>().await else {
        return CloudSaveSummary::default();
    };
    for obj in list.objects {
        let Ok(meta) = serde_json::from_str::<Value>(&obj.value) else {
            continue;
        };
        if meta.get("empty").and_then(|v| v.as_bool()).unwrap_or(false) {
            continue;
        }
        if meta.get("day").is_some() || meta.get("saved_at").is_some() {
            return CloudSaveSummary {
                has_save: true,
                day: meta.get("day").and_then(|v| v.as_i64()).unwrap_or(0),
                time: meta.get("time").and_then(|v| v.as_f64()).unwrap_or(0.0),
                saved_at: meta.get("saved_at").and_then(|v| v.as_i64()).unwrap_or(0),
                level: meta.get("level").and_then(|v| v.as_i64()).unwrap_or(0),
            };
        }
    }
    CloudSaveSummary::default()
}

pub async fn issue_launch_ticket(
    client: &Client,
    base_url: &str,
    token: &str,
    exe_sha256: &str,
    build_version: &str,
    launcher_version: &str,
) -> Result<String, String> {
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "issue_launch_ticket",
        &json!({
            "exe_sha256": exe_sha256,
            "build_version": build_version,
            "launcher_version": launcher_version
        }),
    )
    .await?;
    let val: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if !val.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        let err = val
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("Startticket konnte nicht erstellt werden.");
        return Err(err.to_string());
    }
    val.get("ticket")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "Leeres Startticket erhalten.".to_string())
}

pub async fn report_security_event(
    client: &Client,
    base_url: &str,
    token: &str,
    kind: &str,
    detail: &str,
    severity: &str,
) {
    if token.is_empty() {
        return;
    }
    let _ = call_rpc_raw(
        client,
        base_url,
        token,
        "report_security_event",
        &json!({ "kind": kind, "detail": detail, "severity": severity }),
    )
    .await;
}

pub async fn admin_issue_license_key(
    client: &Client,
    base_url: &str,
    token: &str,
    count: i32,
    edition: &str,
    role_grant: &str,
    note: &str,
    expires_days: i32,
) -> Result<Vec<LicenseKeyView>, String> {
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "admin_issue_license_key",
        &json!({
            "count": count.clamp(1, 50),
            "edition": edition.trim(),
            "role_grant": role_grant.trim(),
            "note": note.trim(),
            "expires_days": expires_days.max(0)
        }),
    )
    .await?;
    let val = parse_rpc_ok(&raw, "Lizenzkey-Erzeugung fehlgeschlagen.")?;
    parse_rpc_vec(&val, "keys")
}

pub async fn admin_list_license_keys(
    client: &Client,
    base_url: &str,
    token: &str,
    status_filter: &str,
    query: &str,
) -> Result<Vec<LicenseKeyView>, String> {
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "admin_list_license_keys",
        &json!({ "status": status_filter.trim(), "query": query.trim() }),
    )
    .await?;
    let val = parse_rpc_ok(&raw, "Lizenzkeys konnten nicht geladen werden.")?;
    parse_rpc_vec(&val, "keys")
}

pub async fn admin_set_license(
    client: &Client,
    base_url: &str,
    token: &str,
    target_or_key: &str,
    active: bool,
) -> Result<(), String> {
    let clean = target_or_key.trim();
    if clean.is_empty() {
        return Err("Bitte Key, UID oder Namen angeben.".to_string());
    }
    let mut obj = if clean.to_ascii_uppercase().starts_with("SHADOW-") {
        json!({
            "license_key": clean,
            "key_status": if active { "claimed" } else { "revoked" },
            "active": active
        })
    } else {
        build_target_payload(clean, "target_uid", "target_user_id")
    };
    if let Some(map) = obj.as_object_mut() {
        map.insert("active".to_string(), json!(active));
    }
    friend_action(client, base_url, token, "admin_set_license", obj).await
}

pub async fn admin_set_ban(
    client: &Client,
    base_url: &str,
    token: &str,
    target: &str,
    banned: bool,
    reason: &str,
) -> Result<(), String> {
    let clean = target.trim();
    if clean.is_empty() {
        return Err("Bitte UID, User-ID oder Namen angeben.".to_string());
    }
    let mut obj = build_target_payload(clean, "target_uid", "target_user_id");
    if let Some(map) = obj.as_object_mut() {
        map.insert("banned".to_string(), json!(banned));
        map.insert("reason".to_string(), json!(reason.trim()));
    }
    friend_action(client, base_url, token, "admin_set_ban", obj).await
}

pub async fn admin_list_security_events(
    client: &Client,
    base_url: &str,
    token: &str,
) -> Result<Vec<SecurityEventView>, String> {
    let raw = call_rpc_raw(client, base_url, token, "admin_list_security_events", &json!({})).await?;
    let val = parse_rpc_ok(&raw, "Security-Log konnte nicht geladen werden.")?;
    parse_rpc_vec(&val, "events")
}

pub async fn admin_overview(
    client: &Client,
    base_url: &str,
    token: &str,
) -> Result<AdminOverviewView, String> {
    let raw = call_rpc_raw(client, base_url, token, "admin_overview", &json!({})).await?;
    let val = parse_rpc_ok(&raw, "Admin-Uebersicht konnte nicht geladen werden.")?;
    serde_json::from_value(val).map_err(|e| e.to_string())
}

pub async fn admin_list_accounts(
    client: &Client,
    base_url: &str,
    token: &str,
    query: &str,
    role: &str,
    status: &str,
) -> Result<Vec<AdminAccountView>, String> {
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "admin_list_accounts",
        &json!({
            "query": query.trim(),
            "role": role.trim(),
            "status": status.trim(),
            "limit": 120
        }),
    )
    .await?;
    let val = parse_rpc_ok(&raw, "Konten konnten nicht geladen werden.")?;
    parse_rpc_vec(&val, "accounts")
}

pub async fn admin_list_active_worlds(
    client: &Client,
    base_url: &str,
    token: &str,
) -> Result<Vec<AdminWorldView>, String> {
    let raw = call_rpc_raw(client, base_url, token, "admin_list_active_worlds", &json!({})).await?;
    let val = parse_rpc_ok(&raw, "Aktive Welten konnten nicht geladen werden.")?;
    parse_rpc_vec(&val, "worlds")
}

pub async fn admin_force_join(
    client: &Client,
    base_url: &str,
    token: &str,
    query: &str,
    match_id: &str,
    room_code: &str,
    host_user_id: &str,
) -> Result<AdminForceJoinView, String> {
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "admin_force_join",
        &json!({
            "query": query.trim(),
            "match_id": match_id.trim(),
            "room_code": room_code.trim(),
            "host_user_id": host_user_id.trim(),
        }),
    )
    .await?;
    let val = parse_rpc_ok(&raw, "Force Join fehlgeschlagen.")?;
    serde_json::from_value(val).map_err(|e| e.to_string())
}

pub async fn admin_kick_match_peer(
    client: &Client,
    base_url: &str,
    token: &str,
    match_id: &str,
    target_user_id: &str,
    cooldown: i32,
) -> Result<(), String> {
    let mut obj = build_target_payload(target_user_id, "target_uid", "target_user_id");
    if let Some(map) = obj.as_object_mut() {
        map.insert("match_id".to_string(), json!(match_id.trim()));
        map.insert("cooldown".to_string(), json!(cooldown.clamp(10, 86400)));
    }
    friend_action(client, base_url, token, "admin_kick_match_peer", obj).await
}

pub async fn admin_close_world(
    client: &Client,
    base_url: &str,
    token: &str,
    match_id: &str,
    host_user_id: &str,
) -> Result<(), String> {
    friend_action(
        client,
        base_url,
        token,
        "admin_close_world",
        json!({
            "match_id": match_id.trim(),
            "host_user_id": host_user_id.trim(),
        }),
    )
    .await
}

pub async fn admin_get_build_config(
    client: &Client,
    base_url: &str,
    token: &str,
) -> Result<AdminBuildConfigView, String> {
    let raw = call_rpc_raw(client, base_url, token, "admin_get_build_config", &json!({})).await?;
    let val = parse_rpc_ok(&raw, "Build-Konfiguration konnte nicht geladen werden.")?;
    serde_json::from_value(val).map_err(|e| e.to_string())
}

pub async fn admin_register_build(
    client: &Client,
    base_url: &str,
    token: &str,
    exe_sha256: &str,
    version: &str,
    enforce: Option<bool>,
    remove_sha256: &str,
    clear: bool,
) -> Result<AdminBuildConfigView, String> {
    let mut payload = json!({
        "exe_sha256": exe_sha256.trim(),
        "version": version.trim(),
        "remove_sha256": remove_sha256.trim(),
        "clear": clear
    });
    if let (Some(e), Some(map)) = (enforce, payload.as_object_mut()) {
        map.insert("enforce".to_string(), json!(e));
    }
    let raw = call_rpc_raw(client, base_url, token, "admin_register_build", &payload).await?;
    let val = parse_rpc_ok(&raw, "Build-Konfiguration konnte nicht gespeichert werden.")?;
    serde_json::from_value(val).map_err(|e| e.to_string())
}

pub async fn list_friends(
    client: &Client,
    base_url: &str,
    token: &str,
) -> Result<Vec<FriendView>, String> {
    let raw = call_rpc_raw(client, base_url, token, "list_friends", &json!({})).await?;
    let parsed: RpcFriendsPayload = serde_json::from_str(&raw)
        .map_err(|e| format!("Freundesliste ungueltig: {}", e))?;
    if !parsed.ok && !parsed.error.is_empty() {
        return Err(parsed.error);
    }
    Ok(parsed.friends)
}

pub async fn lookup_uid(
    client: &Client,
    base_url: &str,
    token: &str,
    query: &str,
) -> Result<LookupView, String> {
    let clean = query.trim();
    if clean.is_empty() {
        return Err("Bitte eine UID oder einen Spielernamen eingeben.".to_string());
    }
    let raw = call_rpc_raw(client, base_url, token, "find_by_uid", &json!({ "uid": clean })).await?;
    let val: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    Ok(LookupView {
        found: val.get("found").and_then(|v| v.as_bool()).unwrap_or(false),
        user_id: val.get("user_id").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        uid: val.get("uid").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        username: val.get("username").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        display_name: val.get("display_name").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        role: normalize_role(val.get("role").and_then(|v| v.as_str()).unwrap_or("player")),
        error: val.get("error").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
    })
}

pub async fn admin_set_role(
    client: &Client,
    base_url: &str,
    token: &str,
    target: &str,
    role: &str,
) -> Result<(), String> {
    let clean_target = target.trim();
    if clean_target.is_empty() {
        return Err("Bitte Ziel-UID oder Spielernamen eingeben.".to_string());
    }
    let clean_role = role.trim().to_ascii_lowercase();
    friend_action(
        client,
        base_url,
        token,
        "admin_set_role",
        json!({ "uid": clean_target, "role": clean_role }),
    )
    .await
}

pub async fn friend_action(
    client: &Client,
    base_url: &str,
    token: &str,
    rpc_id: &str,
    payload: Value,
) -> Result<(), String> {
    let raw = call_rpc_raw(client, base_url, token, rpc_id, &payload).await?;
    let parsed: RpcActionResponse = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if !parsed.ok {
        return Err(if parsed.error.is_empty() {
            "Aktion fehlgeschlagen.".to_string()
        } else {
            parsed.error
        });
    }
    Ok(())
}

pub async fn set_world_join_mode(
    client: &Client,
    base_url: &str,
    token: &str,
    mode: &str,
) -> Result<String, String> {
    let clean = mode.trim().to_ascii_lowercase();
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "set_world_join_mode",
        &json!({ "join_mode": clean }),
    )
    .await?;
    let val: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if !val.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        let err = val
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("Modus konnte nicht geaendert werden.");
        return Err(err.to_string());
    }
    Ok(val
        .get("world_join_mode")
        .and_then(|v| v.as_str())
        .unwrap_or(&clean)
        .to_string())
}

pub async fn coop_resolve_code(
    client: &Client,
    base_url: &str,
    token: &str,
    room_code: &str,
) -> Result<ResolveCodeView, String> {
    let clean = room_code.trim().to_ascii_uppercase();
    if clean.is_empty() {
        return Err("Bitte einen Raumcode eingeben.".to_string());
    }
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "coop_resolve_code",
        &json!({ "room_code": clean }),
    )
    .await?;
    let parsed: ResolveCodeView = serde_json::from_str(&raw)
        .map_err(|e| format!("Antwort zu Raumcode ungueltig: {}", e))?;
    if !parsed.ok {
        return Err(if parsed.error.is_empty() {
            "Raumcode ungueltig.".to_string()
        } else {
            parsed.error
        });
    }
    Ok(parsed)
}

pub async fn coop_invite_friend(
    client: &Client,
    base_url: &str,
    token: &str,
    target_user_id: &str,
) -> Result<String, String> {
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "coop_invite_friend",
        &json!({ "target_user_id": target_user_id.trim() }),
    )
    .await?;
    let val: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if !val.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        let err = val
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("Einladung konnte nicht gesendet werden.");
        return Err(err.to_string());
    }
    Ok(val
        .get("match_id")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string())
}

pub async fn coop_request_join(
    client: &Client,
    base_url: &str,
    token: &str,
    host_user_id: &str,
    host_uid: &str,
    room_code: &str,
) -> Result<JoinRequestResultView, String> {
    let mut payload = serde_json::Map::new();
    if !host_user_id.trim().is_empty() {
        payload.insert("host_user_id".into(), Value::String(host_user_id.trim().into()));
    }
    if !host_uid.trim().is_empty() {
        payload.insert("host_uid".into(), Value::String(host_uid.trim().into()));
    }
    if !room_code.trim().is_empty() {
        payload.insert(
            "room_code".into(),
            Value::String(room_code.trim().to_ascii_uppercase()),
        );
    }
    let raw = call_rpc_raw(
        client,
        base_url,
        token,
        "coop_request_join",
        &Value::Object(payload),
    )
    .await?;
    let parsed: JoinRequestResultView = serde_json::from_str(&raw)
        .map_err(|e| format!("Antwort auf Beitrittsanfrage ungueltig: {}", e))?;
    if !parsed.ok {
        return Err(if parsed.error.is_empty() {
            "Beitritt nicht moeglich.".to_string()
        } else {
            parsed.error
        });
    }
    Ok(parsed)
}

pub async fn coop_respond_join_request(
    client: &Client,
    base_url: &str,
    token: &str,
    requester_user_id: &str,
    accept: bool,
) -> Result<(), String> {
    friend_action(
        client,
        base_url,
        token,
        "coop_respond_join_request",
        json!({ "requester_user_id": requester_user_id.trim(), "accept": accept }),
    )
    .await
}

pub fn parse_notification_json(item: &Value) -> Option<CoopNotificationView> {
    let code = item.get("code").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    if !(101..=104).contains(&code) {
        return None;
    }
    let content_val: Value = match item.get("content") {
        Some(Value::String(s)) => serde_json::from_str(s).unwrap_or_else(|_| json!({})),
        Some(v) if v.is_object() => v.clone(),
        _ => json!({}),
    };
    let s = |obj: &Value, key: &str| -> String {
        obj.get(key)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    Some(CoopNotificationView {
        id: s(item, "id"),
        code,
        subject: s(item, "subject"),
        create_time: s(item, "create_time"),
        sender_id: s(item, "sender_id"),
        kind: s(&content_val, "kind"),
        match_id: s(&content_val, "match_id"),
        room_code: s(&content_val, "room_code"),
        world_name: s(&content_val, "world_name"),
        host_user_id: s(&content_val, "host_user_id"),
        host_uid: s(&content_val, "host_uid"),
        host_name: s(&content_val, "host_name"),
        join_mode: s(&content_val, "join_mode"),
        request_id: s(&content_val, "request_id"),
        requester_user_id: s(&content_val, "requester_user_id"),
        requester_uid: s(&content_val, "requester_uid"),
        requester_name: s(&content_val, "requester_name"),
        expires_at: content_val.get("expires_at").and_then(|v| v.as_i64()).unwrap_or(0),
    })
}

pub async fn fetch_notifications(
    client: &Client,
    base_url: &str,
    token: &str,
) -> Result<Vec<CoopNotificationView>, String> {
    let endpoint = format!("{}/v2/notification?limit=25", clean_base(base_url));
    let resp = client
        .get(endpoint)
        .bearer_auth(token)
        .send()
        .await
        .map_err(|e| format!("Benachrichtigungen nicht erreichbar: {}", e))?;
    if !resp.status().is_success() {
        return Err(extract_error(resp).await);
    }
    let val: Value = resp
        .json()
        .await
        .map_err(|e| format!("Ungueltige Notification-Antwort: {}", e))?;
    let mut list = Vec::new();
    if let Some(items) = val.get("notifications").and_then(|v| v.as_array()) {
        for item in items {
            if let Some(parsed) = parse_notification_json(item) {
                list.push(parsed);
            }
        }
    }
    Ok(list)
}

pub async fn delete_notification(
    client: &Client,
    base_url: &str,
    token: &str,
    notification_id: &str,
) -> Result<(), String> {
    let clean = notification_id.trim();
    if clean.is_empty() {
        return Ok(());
    }
    let endpoint = format!("{}/v2/notification", clean_base(base_url));
    let resp = client
        .delete(endpoint)
        .bearer_auth(token)
        .query(&[("ids", clean)])
        .send()
        .await
        .map_err(|e| format!("Loeschen fehlgeschlagen: {}", e))?;
    if !resp.status().is_success() {
        return Err(extract_error(resp).await);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handles_empty_lua_object_friends_list() {
        let parsed: RpcFriendsPayload =
            serde_json::from_str(r#"{"ok":true,"friends":{}}"#).expect("valid payload");
        assert!(parsed.ok);
        assert!(parsed.friends.is_empty());
    }

    #[test]
    fn parses_non_empty_friends_array_with_coop() {
        let raw = r#"{"ok":true,"friends":[{"user_id":"u1","uid":"100002","username":"ally","display_name":"Ally","online":true,"state":0,"world_join_mode":"ask","role":"moderator","coop_active":true,"coop_match_id":"m1.","coop_world_name":"TEST","coop_join_mode":"open","coop_players":2,"coop_max_players":4}]}"#;
        let parsed: RpcFriendsPayload = serde_json::from_str(raw).expect("valid payload");
        assert!(parsed.ok);
        assert_eq!(parsed.friends.len(), 1);
        assert_eq!(parsed.friends[0].uid, "100002");
        assert_eq!(parsed.friends[0].role, "moderator");
        assert!(parsed.friends[0].online);
        assert!(parsed.friends[0].coop_active);
        assert_eq!(parsed.friends[0].coop_match_id, "m1.");
        assert_eq!(parsed.friends[0].coop_players, 2);
    }

    #[test]
    fn defaults_missing_role_to_player_and_handles_null_lobby() {
        let profile: RpcProfile = serde_json::from_str(
            r#"{"user_id":"u1","username":"hero","uid":"100001","world_join_mode":"ask","active_lobby":null}"#,
        )
        .expect("valid profile");
        assert_eq!(profile.role, "player");
        assert!(profile.active_lobby.is_none());
        assert_eq!(normalize_role("ADMIN"), "admin");
        assert_eq!(normalize_role("unknown"), "player");
    }

    #[test]
    fn parses_coop_notification_content_json_string() {
        let item = json!({
            "id": "n-1",
            "code": 102,
            "subject": "Anfrage",
            "sender_id": "u2",
            "create_time": "2026-11-15T12:00:00Z",
            "content": "{\"kind\":\"coop_join_request\",\"match_id\":\"m1.\",\"requester_user_id\":\"u2\",\"requester_uid\":\"100009\",\"requester_name\":\"Maren\",\"world_name\":\"WALDRAND\"}"
        });
        let notif = parse_notification_json(&item).expect("coop notif parsed");
        assert_eq!(notif.code, 102);
        assert_eq!(notif.requester_name, "Maren");
        assert_eq!(notif.match_id, "m1.");
    }

    #[test]
    fn parses_admin_build_and_worlds_with_empty_lua_objects() {
        let build_cfg: AdminBuildConfigView =
            serde_json::from_str(r#"{"ok":true,"enforce":false,"hash_list":{}}"#)
                .expect("build cfg");
        assert!(!build_cfg.enforce);
        assert!(build_cfg.hash_list.is_empty());

        let world: AdminWorldView = serde_json::from_str(
            r#"{"match_id":"m9","world_name":"TEST","room_code":"AB12CD","join_mode":"private","peers":{}}"#,
        )
        .expect("admin world");
        assert_eq!(world.match_id, "m9");
        assert!(world.peers.is_empty());
    }
}
