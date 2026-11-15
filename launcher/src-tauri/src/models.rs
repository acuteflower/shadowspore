use serde::{Deserialize, Serialize};

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

impl Default for PersistedState {
    fn default() -> Self {
        Self {
            server_url: "http://127.0.0.1:7350".to_string(),
            server_key: "shadowspore_dev_server_key".to_string(),
            refresh_token: String::new(),
            game_exe_path: String::new(),
            godot_exe_path: String::new(),
            manifest_url: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CloudSaveSummary {
    pub has_save: bool,
    pub day: i64,
    pub time: f64,
    pub saved_at: i64,
}

fn default_role() -> String {
    "player".to_string()
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
    pub world_join_mode: String,
    pub server_url: String,
    pub cloud_save: CloudSaveSummary,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FriendView {
    pub user_id: String,
    pub uid: String,
    pub username: String,
    pub display_name: String,
    pub online: bool,
    pub state: i32,
    pub world_join_mode: String,
    #[serde(default = "default_role")]
    pub role: String,
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
    pub status_label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LauncherConfigView {
    pub server_url: String,
    pub server_key: String,
    pub game_exe_path: String,
    pub godot_exe_path: String,
    pub manifest_url: String,
}
