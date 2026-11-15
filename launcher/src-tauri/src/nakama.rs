use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::models::{CloudSaveSummary, FriendView, LookupView};

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
    #[serde(default, deserialize_with = "deserialize_friends_vec")]
    friends: Vec<FriendView>,
    #[serde(default)]
    error: String,
}

fn deserialize_friends_vec<'de, D>(deserializer: D) -> Result<Vec<FriendView>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let val = Value::deserialize(deserializer)?;
    // Nakama's Lua json_encode encodes an empty table `{}` as a JSON object instead of `[]`.
    if !val.is_array() {
        return Ok(Vec::new());
    }
    serde_json::from_value(val).map_err(serde::de::Error::custom)
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
    username: &str,
    create: bool,
) -> Result<AuthTokens, String> {
    let clean_email = email.trim().to_lowercase();
    if clean_email.is_empty() || !clean_email.contains('@') {
        return Err("Bitte eine gueltige E-Mail-Adresse eingeben.".to_string());
    }
    if password.chars().count() < 8 {
        return Err("Das Passwort muss mindestens 8 Zeichen lang sein.".to_string());
    }
    let mut endpoint = format!(
        "{}/v2/account/authenticate/email?create={}",
        clean_base(base_url),
        create
    );
    let clean_user = username.trim();
    if !clean_user.is_empty() {
        let encoded = reqwest::Url::parse_with_params(
            "http://dummy.local",
            &[("username", clean_user)],
        )
        .map(|u| u.query().unwrap_or_default().to_string())
        .unwrap_or_default();
        if !encoded.is_empty() {
            endpoint.push('&');
            endpoint.push_str(&encoded);
        }
    }

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
        "object_ids": [{
            "collection": "saves",
            "key": "world_meta",
            "user_id": user_id
        }]
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
    let Some(first) = list.objects.first() else {
        return CloudSaveSummary::default();
    };
    let Ok(meta) = serde_json::from_str::<Value>(&first.value) else {
        return CloudSaveSummary::default();
    };
    CloudSaveSummary {
        has_save: true,
        day: meta.get("day").and_then(|v| v.as_i64()).unwrap_or(0),
        time: meta.get("time").and_then(|v| v.as_f64()).unwrap_or(0.0),
        saved_at: meta.get("saved_at").and_then(|v| v.as_i64()).unwrap_or(0),
    }
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
    fn parses_non_empty_friends_array() {
        let raw = r#"{"ok":true,"friends":[{"user_id":"u1","uid":"100002","username":"ally","display_name":"Ally","online":true,"state":0,"world_join_mode":"ask","role":"moderator"}]}"#;
        let parsed: RpcFriendsPayload = serde_json::from_str(raw).expect("valid payload");
        assert!(parsed.ok);
        assert_eq!(parsed.friends.len(), 1);
        assert_eq!(parsed.friends[0].uid, "100002");
        assert_eq!(parsed.friends[0].role, "moderator");
        assert!(parsed.friends[0].online);
    }

    #[test]
    fn defaults_missing_role_to_player() {
        let profile: RpcProfile = serde_json::from_str(
            r#"{"user_id":"u1","username":"hero","uid":"100001","world_join_mode":"ask"}"#,
        )
        .expect("valid profile");
        assert_eq!(profile.role, "player");
        assert_eq!(normalize_role("ADMIN"), "admin");
        assert_eq!(normalize_role("unknown"), "player");
    }
}
