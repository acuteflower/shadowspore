use serde::{Deserialize, Serialize};

pub const DEV_SERVER_URL: &str = "http://127.0.0.1:7350";
pub const DEV_SERVER_KEY: &str = "shadowspore_dev_server_key";
pub const LIVE_SERVER_URL: &str = "https://s.shadowspore.com";
pub const LIVE_MANIFEST_URL: &str = "https://shadowspore.com/updates/manifest.json";

pub fn live_server_key() -> &'static str {
    match option_env!("SHADOWSPORE_LIVE_SERVER_KEY") {
        Some(k) if !k.trim().is_empty() => k.trim(),
        _ => "shadowspore_live_client_v1",
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct PersistedState {
    pub server_url: String,
    pub server_key: String,
    pub refresh_token: String,
    pub game_exe_path: String,
    pub godot_exe_path: String,
    pub manifest_url: String,
}

impl PersistedState {
    pub fn default_for_mode(dev_mode: bool) -> Self {
        if dev_mode {
            Self {
                server_url: DEV_SERVER_URL.to_string(),
                server_key: DEV_SERVER_KEY.to_string(),
                refresh_token: String::new(),
                game_exe_path: String::new(),
                godot_exe_path: String::new(),
                manifest_url: String::new(),
            }
        } else {
            Self {
                server_url: LIVE_SERVER_URL.to_string(),
                server_key: live_server_key().to_string(),
                refresh_token: String::new(),
                game_exe_path: String::new(),
                godot_exe_path: String::new(),
                manifest_url: LIVE_MANIFEST_URL.to_string(),
            }
        }
    }
}

impl Default for PersistedState {
    fn default() -> Self {
        Self::default_for_mode(cfg!(debug_assertions))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CloudSaveSummary {
    pub has_save: bool,
    pub day: i64,
    pub time: f64,
    pub saved_at: i64,
    /// The player's level at the last save (0 = older save without it).
    #[serde(default)]
    pub level: i64,
}

fn default_role() -> String {
    "player".to_string()
}

fn default_max_players() -> i32 {
    4
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ActiveLobbyView {
    #[serde(default)]
    pub match_id: String,
    #[serde(default)]
    pub room_code: String,
    #[serde(default)]
    pub world_name: String,
    #[serde(default)]
    pub join_mode: String,
    #[serde(default = "default_max_players")]
    pub max_players: i32,
    #[serde(default)]
    pub player_count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SessionView {
    pub logged_in: bool,
    pub user_id: String,
    pub username: String,
    pub display_name: String,
    pub uid: String,
    #[serde(default = "default_role")]
    pub role: String,
    #[serde(default)]
    pub avatar_url: String,
    pub world_join_mode: String,
    pub server_url: String,
    pub cloud_save: CloudSaveSummary,
    #[serde(default)]
    pub active_lobby: Option<ActiveLobbyView>,
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

pub(crate) fn deserialize_vec_or_empty<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: serde::de::DeserializeOwned,
{
    let val = serde_json::Value::deserialize(deserializer)?;
    // Nakama's Lua json_encode encodes an empty table `{}` as a JSON object instead of `[]`.
    if !val.is_array() {
        return Ok(Vec::new());
    }
    serde_json::from_value(val).map_err(serde::de::Error::custom)
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LicenseKeyView {
    #[serde(default)]
    pub key: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub edition: String,
    #[serde(default)]
    pub role_grant: String,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub created_at: i64,
    #[serde(default)]
    pub expires_at: i64,
    #[serde(default)]
    pub claimed_by: String,
    #[serde(default)]
    pub claimed_by_uid: String,
    #[serde(default)]
    pub claimed_by_name: String,
    #[serde(default)]
    pub claimed_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SecurityEventView {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub user_id: String,
    #[serde(default)]
    pub uid: String,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub severity: String,
    #[serde(default)]
    pub detail: String,
    #[serde(default)]
    pub at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdminOverviewView {
    #[serde(default)]
    pub total_accounts: i64,
    #[serde(default)]
    pub banned_accounts: i64,
    #[serde(default)]
    pub online_accounts: i64,
    #[serde(default)]
    pub active_worlds: i64,
    #[serde(default)]
    pub unused_keys: i64,
    #[serde(default)]
    pub claimed_keys: i64,
    #[serde(default)]
    pub revoked_keys: i64,
    #[serde(default)]
    pub security_events: i64,
    #[serde(default)]
    pub build_enforce: bool,
    #[serde(default)]
    pub build_hash_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdminAccountView {
    #[serde(default)]
    pub user_id: String,
    #[serde(default)]
    pub uid: String,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub avatar_url: String,
    #[serde(default = "default_role")]
    pub role: String,
    #[serde(default)]
    pub world_join_mode: String,
    #[serde(default)]
    pub license_active: bool,
    #[serde(default)]
    pub license_edition: String,
    #[serde(default)]
    pub license_expires_at: i64,
    #[serde(default)]
    pub banned: bool,
    #[serde(default)]
    pub ban_reason: String,
    #[serde(default)]
    pub created_at: i64,
    #[serde(default)]
    pub game_online: bool,
    #[serde(default)]
    pub game_last_seen: i64,
    #[serde(default)]
    pub coop_active: bool,
    #[serde(default)]
    pub coop_match_id: String,
    #[serde(default)]
    pub coop_world_name: String,
    #[serde(default)]
    pub coop_room_code: String,
    #[serde(default)]
    pub coop_join_mode: String,
    #[serde(default)]
    pub coop_players: i32,
    #[serde(default = "default_max_players")]
    pub coop_max_players: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdminLobbyPeerView {
    #[serde(default)]
    pub peer_id: i32,
    #[serde(default)]
    pub user_id: String,
    #[serde(default)]
    pub uid: String,
    #[serde(default = "default_role")]
    pub role: String,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdminWorldView {
    #[serde(default)]
    pub match_id: String,
    #[serde(default)]
    pub host_user_id: String,
    #[serde(default)]
    pub host_uid: String,
    #[serde(default)]
    pub host_name: String,
    #[serde(default)]
    pub world_name: String,
    #[serde(default)]
    pub room_code: String,
    #[serde(default)]
    pub join_mode: String,
    #[serde(default)]
    pub player_count: i32,
    #[serde(default = "default_max_players")]
    pub max_players: i32,
    #[serde(default)]
    pub updated_at: i64,
    #[serde(default, deserialize_with = "deserialize_vec_or_empty")]
    pub peers: Vec<AdminLobbyPeerView>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdminForceJoinView {
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub error: String,
    #[serde(default)]
    pub match_id: String,
    #[serde(default)]
    pub room_code: String,
    #[serde(default)]
    pub world_name: String,
    #[serde(default)]
    pub join_mode: String,
    #[serde(default)]
    pub host_user_id: String,
    #[serde(default)]
    pub host_uid: String,
    #[serde(default)]
    pub host_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdminBuildHashView {
    #[serde(default)]
    pub sha256: String,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub added_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AdminBuildConfigView {
    #[serde(default)]
    pub enforce: bool,
    #[serde(default, deserialize_with = "deserialize_vec_or_empty")]
    pub hash_list: Vec<AdminBuildHashView>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LocalBuildInfoView {
    pub found: bool,
    pub exe_path: String,
    pub version: String,
    pub sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FriendView {
    pub user_id: String,
    pub uid: String,
    pub username: String,
    pub display_name: String,
    pub online: bool,
    pub state: i32,
    #[serde(default)]
    pub world_join_mode: String,
    #[serde(default = "default_role")]
    pub role: String,
    #[serde(default)]
    pub coop_active: bool,
    #[serde(default)]
    pub coop_match_id: String,
    #[serde(default)]
    pub coop_world_name: String,
    #[serde(default)]
    pub coop_join_mode: String,
    #[serde(default)]
    pub coop_players: i32,
    #[serde(default = "default_max_players")]
    pub coop_max_players: i32,
    #[serde(default)]
    pub avatar_url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CoopNotificationView {
    pub id: String,
    pub code: i32,
    pub subject: String,
    pub create_time: String,
    pub sender_id: String,
    pub kind: String,
    pub match_id: String,
    pub room_code: String,
    pub world_name: String,
    pub host_user_id: String,
    pub host_uid: String,
    pub host_name: String,
    pub join_mode: String,
    pub request_id: String,
    pub requester_user_id: String,
    pub requester_uid: String,
    pub requester_name: String,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ResolveCodeView {
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub error: String,
    #[serde(default)]
    pub match_id: String,
    #[serde(default)]
    pub room_code: String,
    #[serde(default)]
    pub world_name: String,
    #[serde(default)]
    pub join_mode: String,
    #[serde(default = "default_max_players")]
    pub max_players: i32,
    #[serde(default)]
    pub player_count: i32,
    #[serde(default)]
    pub host_user_id: String,
    #[serde(default)]
    pub host_uid: String,
    #[serde(default)]
    pub host_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct JoinRequestResultView {
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub error: String,
    #[serde(default)]
    pub match_id: String,
    #[serde(default)]
    pub room_code: String,
    #[serde(default)]
    pub world_name: String,
    #[serde(default)]
    pub host_user_id: String,
    #[serde(default)]
    pub host_uid: String,
    #[serde(default)]
    pub host_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LookupView {
    pub found: bool,
    pub user_id: String,
    pub uid: String,
    pub username: String,
    pub display_name: String,
    #[serde(default = "default_role")]
    pub role: String,
    pub error: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameStatusView {
    pub mode: String, // "release" | "dev" | "missing"
    pub ready: bool,
    pub resolved_exe: String,
    pub resolved_project_dir: String,
    pub local_version: String,
    pub remote_version: String,
    pub update_available: bool,
    #[serde(default)]
    pub remote_changelog: String,
    #[serde(default)]
    pub remote_download_url: String,
    #[serde(default)]
    pub remote_sha256: String,
    #[serde(default)]
    pub remote_size_bytes: u64,
    pub status_label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateProgressPayload {
    pub stage: String,
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub percent: u8,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LauncherConfigView {
    pub server_url: String,
    pub server_key: String,
    pub game_exe_path: String,
    pub godot_exe_path: String,
    pub manifest_url: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ServerPresetsView {
    pub dev_url: String,
    pub dev_key: String,
    pub live_url: String,
    pub live_key: String,
    pub live_manifest_url: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_for_mode_separates_dev_and_live() {
        let dev = PersistedState::default_for_mode(true);
        assert_eq!(dev.server_url, "http://127.0.0.1:7350");
        assert_eq!(dev.server_key, "shadowspore_dev_server_key");
        assert!(dev.manifest_url.is_empty());

        let live = PersistedState::default_for_mode(false);
        assert_eq!(live.server_url, "https://s.shadowspore.com");
        assert!(!live.server_key.is_empty());
        assert_ne!(live.server_key, dev.server_key);
        assert_eq!(live.manifest_url, "https://shadowspore.com/updates/manifest.json");
    }
}
