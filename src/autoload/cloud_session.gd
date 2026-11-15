extends Node
## Nakama cloud session, UID profile, and split cloud saves (`player_profile` + `world_state`).
## Talks to Nakama HTTP REST API with strict static typing and zero external addon dependencies.

const DEFAULT_URL: String = "https://s.shadowspore.com"
const DEFAULT_DEV_URL: String = "http://127.0.0.1:7350"
const RelayPeer: GDScript = preload("res://src/autoload/nakama_relay_peer.gd")
const DEFAULT_SERVER_KEY: String = "shadowspore_live_client_v1"
const DEFAULT_DEV_SERVER_KEY: String = "shadowspore_dev_server_key"
const BUILD_AUTH_PATH: String = "res://data/build_auth.json"
const SESSION_PATH: String = "user://cloud_session.json"
const CONFIG_PATH: String = "user://cloud_config.json"
const AUTO_SAVE_INTERVAL_SEC: float = 20.0
const DIRTY_SAVE_DEBOUNCE_SEC: float = 1.25
const SNAPSHOT_REFRESH_SEC: float = 1.5
const QUIT_FLUSH_TIMEOUT_MSEC: int = 3200
const COOP_PORTABLE_KEYS: PackedStringArray = ["health", "copper", "xp", "claimed", "skill_tree", "slots", "equipment", "raw_rolls", "bandaged", "appearance"]
const COOP_PRESERVE_KEYS: PackedStringArray = ["pos", "quests", "board_local"]

signal auth_changed(logged_in: bool)
signal profile_loaded(profile: Dictionary)
signal save_info_changed()
signal auto_save_finished(ok: bool)
signal _async_local_save_finished(ok: bool)
signal friends_changed()
signal friends_list_loaded(friends: Array)
signal notifications_changed()
signal ipc_command_received(cmd: Dictionary)

var server_url: String = DEFAULT_URL
var server_key: String = DEFAULT_SERVER_KEY
var token: String = ""
var refresh_token: String = ""
var user_id: String = ""
var username: String = ""
const VALID_ROLES: PackedStringArray = ["player", "tester", "moderator", "admin"]
const VALID_JOIN_MODES: PackedStringArray = ["private", "ask", "open"]

var display_name: String = ""
var uid: String = ""
var world_join_mode: String = "ask"
var role: String = "player"
var license_active: bool = false
var license_edition: String = ""
var license_expires_at: int = 0
var license_error: String = ""
var banned: bool = false
var ban_reason: String = ""
var launch_ticket: String = ""
var launcher_exe_sha256: String = ""
var launcher_pid: int = 0
var strict_override: bool = false
var has_cloud_save: bool = false
var cloud_save_day: int = -1
var cloud_save_time: float = 0.0
var cloud_save_at: int = 0
var last_error: String = ""
var friends_cache: Array[Dictionary] = []
var notifications: Array[Dictionary] = []

var _notif_ws: WebSocketPeer = WebSocketPeer.new()
var _notif_ws_token: String = ""
var _notif_ws_retry_t: float = 0.0
var _ipc_server: TCPServer = null
var _ipc_port: int = 0
var _ipc_secret: String = ""
var _ipc_clients: Array[Dictionary] = []
var _ipc_path: String = ""
var _auto_save_timer: float = AUTO_SAVE_INTERVAL_SEC
var _dirty_save_timer: float = -1.0
var _snapshot_timer: float = 0.0
var _save_in_flight: bool = false
var _save_pending_again: bool = false
var _dirty: bool = false
var _autosave_suppressed: bool = false
var allow_headless_autosave: bool = false
var _quit_in_progress: bool = false
var _cached_player_snapshot: Dictionary = {}
var _cached_world_snapshot: Dictionary = {}
var _cached_snapshot_is_server: bool = true
var _solo_profile_preserve: Dictionary = {}
var _watched_world_id: int = 0
var _watched_player_id: int = 0
var _http_timeout_override_msec: int = 0


class _AutoSaveDriver extends Node:
	var owner_session: Node = null

	func _process(delta: float) -> void:
		if owner_session != null:
			owner_session.call("_tick_autosave", delta)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_CLOSE_REQUEST and owner_session != null:
			owner_session.call("graceful_quit")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.is_debug_build() and not strict_override:
		server_url = DEFAULT_DEV_URL
		server_key = DEFAULT_DEV_SERVER_KEY
	else:
		_load_bundled_release_auth()
	_load_config()
	_read_cmdline_args()
	_read_env_launch_credentials()
	_start_ipc_server()
	var auto_driver: _AutoSaveDriver = _AutoSaveDriver.new()
	auto_driver.name = "AutoSaveDriver"
	auto_driver.process_mode = Node.PROCESS_MODE_ALWAYS
	auto_driver.owner_session = self
	add_child(auto_driver)
	if DisplayServer.get_name() != "headless":
		get_tree().auto_accept_quit = false
	if not TimeManager.day_started.is_connected(_on_autosave_day_started):
		TimeManager.day_started.connect(_on_autosave_day_started)
	if not TimeManager.sleep_state_changed.is_connected(_on_autosave_dirty_signal):
		TimeManager.sleep_state_changed.connect(_on_autosave_dirty_signal)
	if is_logged_in() and DisplayServer.get_name() != "headless":
		fetch_my_profile.call_deferred()


func _load_bundled_release_auth() -> void:
	server_url = DEFAULT_URL
	server_key = DEFAULT_SERVER_KEY
	if not FileAccess.file_exists(BUILD_AUTH_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_AUTH_PATH))
	if parsed is Dictionary:
		var cfg: Dictionary = parsed as Dictionary
		var bundled_url: String = String(cfg.get("server_url", "")).strip_edges()
		var bundled_key: String = String(cfg.get("server_key", "")).strip_edges()
		if not bundled_url.is_empty():
			server_url = bundled_url
		if not bundled_key.is_empty():
			server_key = bundled_key


## True in exported Release builds (or when `--strict-guard` / test override is enabled).
func is_strict_release() -> bool:
	return not OS.is_debug_build() or strict_override


func is_entitled() -> bool:
	return is_logged_in() and license_active and not banned


func _read_env_launch_credentials() -> void:
	var env_ticket: String = OS.get_environment("SHADOWSPORE_LAUNCH_TICKET").strip_edges()
	var env_tok: String = OS.get_environment("SHADOWSPORE_NAKAMA_TOKEN").strip_edges()
	var env_ref: String = OS.get_environment("SHADOWSPORE_NAKAMA_REFRESH").strip_edges()
	var env_sha: String = OS.get_environment("SHADOWSPORE_EXE_SHA256").strip_edges().to_lower()
	var env_pid: String = OS.get_environment("SHADOWSPORE_LAUNCHER_PID").strip_edges()
	if not env_ticket.is_empty():
		launch_ticket = env_ticket
		OS.set_environment("SHADOWSPORE_LAUNCH_TICKET", "")
	if not env_sha.is_empty():
		launcher_exe_sha256 = env_sha
		OS.set_environment("SHADOWSPORE_EXE_SHA256", "")
	if env_pid.is_valid_int():
		launcher_pid = int(env_pid)
		OS.set_environment("SHADOWSPORE_LAUNCHER_PID", "")
	if not env_tok.is_empty():
		_apply_session_tokens(env_tok, env_ref)
		OS.set_environment("SHADOWSPORE_NAKAMA_TOKEN", "")
		OS.set_environment("SHADOWSPORE_NAKAMA_REFRESH", "")


func _exit_tree() -> void:
	_stop_ipc_server()
	if _notif_ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_notif_ws.close()


func _process(delta: float) -> void:
	_poll_ipc()
	_poll_notif_ws(delta)


func is_logged_in() -> bool:
	return not token.is_empty() and not user_id.is_empty()


static func normalize_role(raw: String) -> String:
	var normalized: String = raw.strip_edges().to_lower()
	return normalized if normalized in VALID_ROLES else "player"


static func _role_rank(r: String) -> int:
	match r:
		"admin":
			return 3
		"moderator":
			return 2
		"tester":
			return 1
		_:
			return 0


func is_admin() -> bool:
	return is_logged_in() and role == "admin"


func has_role(required: String) -> bool:
	if not is_logged_in():
		return false
	return _role_rank(role) >= _role_rank(normalize_role(required))


func logout() -> void:
	token = ""
	refresh_token = ""
	user_id = ""
	username = ""
	display_name = ""
	uid = ""
	world_join_mode = "ask"
	role = "player"
	license_active = false
	license_edition = ""
	license_expires_at = 0
	license_error = ""
	banned = false
	ban_reason = ""
	launch_ticket = ""
	has_cloud_save = false
	cloud_save_day = -1
	cloud_save_time = 0.0
	cloud_save_at = 0
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)
	friends_cache.clear()
	notifications.clear()
	if _notif_ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_notif_ws.close()
	_notif_ws_token = ""
	reset_autosave_state()
	notifications_changed.emit()
	save_info_changed.emit()
	auth_changed.emit(false)


## Authenticates with email + password (account creation in client/launcher is disabled; use website with license key).
func authenticate_email(email: String, password: String, create: bool = false, custom_username: String = "") -> Dictionary:
	last_error = ""
	if create and is_strict_release():
		last_error = "Registrierung nur mit gueltigem Lizenzkey auf shadowspore.com moeglich."
		return {"ok": false, "error": last_error}
	var clean_email: String = email.strip_edges().to_lower()
	if clean_email.is_empty() or password.length() < 8:
		last_error = "E-Mail oder Passwort (min. 8 Zeichen) ungueltig."
		return {"ok": false, "error": last_error}
	var query: String = "?create=%s" % ("true" if create else "false")
	if not custom_username.strip_edges().is_empty():
		query += "&username=" + custom_username.strip_edges().uri_encode()
	var body: Dictionary = {"email": clean_email, "password": password}
	var res: Dictionary = await _request_json(
		HTTPClient.METHOD_POST,
		"/v2/account/authenticate/email" + query,
		JSON.stringify(body),
		false
	)
	if not bool(res.get("ok", false)):
		last_error = String(res.get("error", "Login fehlgeschlagen"))
		return res
	var data: Dictionary = res.get("data", {}) as Dictionary
	_apply_session_tokens(String(data.get("token", "")), String(data.get("refresh_token", "")))
	var profile: Dictionary = await fetch_my_profile()
	if profile.is_empty():
		return {"ok": false, "error": last_error}
	if not is_strict_release():
		_save_session()
	auth_changed.emit(true)
	return {"ok": true, "profile": profile}


## Restores a saved session (in strict release only tokens passed securely by the launcher work).
func try_restore_session() -> bool:
	if not token.is_empty():
		var profile: Dictionary = await fetch_my_profile()
		if not profile.is_empty():
			auth_changed.emit(true)
			return true
		return false
	if is_strict_release():
		return false
	_load_session()
	if refresh_token.is_empty():
		return false
	if not await refresh_session():
		return false
	var loaded: Dictionary = await fetch_my_profile()
	if loaded.is_empty():
		return false
	auth_changed.emit(true)
	return true


func refresh_session() -> bool:
	if refresh_token.is_empty():
		return false
	var res: Dictionary = await _request_json(
		HTTPClient.METHOD_POST,
		"/v2/account/session/refresh",
		JSON.stringify({"token": refresh_token}),
		false
	)
	if not bool(res.get("ok", false)):
		last_error = String(res.get("error", "Session abgelaufen"))
		return false
	var data: Dictionary = res.get("data", {}) as Dictionary
	_apply_session_tokens(String(data.get("token", "")), String(data.get("refresh_token", "")))
	_save_session()
	return is_logged_in()


## Calls Lua RPC `get_my_profile` -> assigns/returns persistent UID and license/ban status.
func fetch_my_profile() -> Dictionary:
	var data: Dictionary = await call_rpc("get_my_profile", {})
	if data.is_empty():
		return {}
	user_id = String(data.get("user_id", user_id))
	username = String(data.get("username", ""))
	display_name = String(data.get("display_name", ""))
	uid = String(data.get("uid", ""))
	world_join_mode = String(data.get("world_join_mode", "ask"))
	role = normalize_role(String(data.get("role", "player")))
	license_active = bool(data.get("license_active", false))
	license_edition = String(data.get("license_edition", ""))
	license_expires_at = int(data.get("license_expires_at", 0))
	license_error = String(data.get("license_error", ""))
	banned = bool(data.get("banned", false))
	ban_reason = String(data.get("ban_reason", ""))
	await refresh_cloud_save_info()
	profile_loaded.emit(data)
	return data


func refresh_cloud_save_info() -> void:
	if not is_logged_in():
		_apply_world_meta({})
		return
	var state_obj: Dictionary = await read_storage("saves", "world_state")
	if not state_obj.is_empty() and not bool(state_obj.get("empty", false)):
		_apply_world_meta(state_obj)
		return
	var meta: Dictionary = await read_storage("saves", "world_meta")
	_apply_world_meta(meta)


func _apply_world_meta(meta: Dictionary) -> void:
	if meta.is_empty() or bool(meta.get("empty", false)):
		has_cloud_save = false
		cloud_save_day = -1
		cloud_save_time = 0.0
		cloud_save_at = 0
	else:
		has_cloud_save = true
		cloud_save_day = int(meta.get("day", 0))
		cloud_save_time = float(meta.get("time", 0.0))
		cloud_save_at = int(meta.get("saved_at", 0))
	save_info_changed.emit()


func cloud_save_info() -> Dictionary:
	if not has_cloud_save:
		return {}
	return {"saved_at": cloud_save_at, "day": cloud_save_day, "time": cloud_save_time}


## Server/Admin RPC: sets role ("player" | "tester" | "moderator" | "admin") for a target UID or user_id.
func set_user_role(target_query: String, new_role: String) -> Dictionary:
	var res: Dictionary = await _call_ok_rpc("admin_set_role", {
		"uid": target_query.strip_edges(),
		"role": new_role.strip_edges().to_lower(),
	})
	if bool(res.get("ok", false)) and String(res.get("user_id", "")) == user_id:
		role = normalize_role(String(res.get("role", role)))
		profile_loaded.emit(res)
	return res


func find_by_uid(target_uid: String) -> Dictionary:
	return await call_rpc("find_by_uid", {"uid": target_uid.strip_edges()})


## Sends a friend request by UID or username, or accepts an incoming invite.
func add_friend_by_uid(target_query: String) -> Dictionary:
	var res: Dictionary = await _call_ok_rpc("add_friend_by_uid", {"uid": target_query.strip_edges()})
	if bool(res.get("ok", false)):
		friends_changed.emit()
	return res


## Accepts an incoming friend invite from `target_user_id`.
func accept_friend(target_user_id: String) -> bool:
	var res: Dictionary = await _call_ok_rpc("accept_friend", {"user_id": target_user_id})
	if not bool(res.get("ok", false)):
		return false
	friends_changed.emit()
	return true


## Removes a friend or cancels/declines a friend invite.
func remove_friend(target_user_id: String) -> bool:
	var res: Dictionary = await _call_ok_rpc("remove_friend", {"user_id": target_user_id})
	if not bool(res.get("ok", false)):
		return false
	friends_changed.emit()
	return true


## Lists friends (state=0), sent invites (state=1), and received invites (state=2) with UID info.
func list_friends() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var res: Dictionary = await _call_ok_rpc("list_friends", {})
	if not bool(res.get("ok", false)):
		return out
	var raw_var: Variant = res.get("friends", [])
	if not (raw_var is Array):
		return out
	var raw_items: Array = raw_var as Array
	for item: Variant in raw_items:
		if item is Dictionary:
			out.append(item as Dictionary)
	return out


func _call_ok_rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
	var res: Dictionary = await call_rpc(rpc_id, payload)
	if res.is_empty():
		return {"ok": false, "error": last_error if not last_error.is_empty() else "Anfrage fehlgeschlagen"}
	if not bool(res.get("ok", false)):
		last_error = String(res.get("error", "Anfrage fehlgeschlagen"))
	return res


func call_rpc(rpc_id: String, payload: Dictionary = {}) -> Dictionary:
	if token.is_empty():
		last_error = "Nicht eingeloggt"
		return {}
	var inner: String = JSON.stringify(payload)
	var res: Dictionary = await _request_json(
		HTTPClient.METHOD_POST,
		"/v2/rpc/" + rpc_id.uri_encode(),
		JSON.stringify(inner),
		true
	)
	if not bool(res.get("ok", false)):
		last_error = String(res.get("error", "RPC fehlgeschlagen"))
		return {}
	var raw_payload: String = String((res.get("data", {}) as Dictionary).get("payload", "{}"))
	var parsed: Variant = JSON.parse_string(raw_payload)
	return parsed as Dictionary if parsed is Dictionary else {}


func write_storage(collection: String, key: String, value: Dictionary, permission_read: int = 1, permission_write: int = 1) -> bool:
	if token.is_empty():
		last_error = "Nicht eingeloggt"
		return false
	var body: Dictionary = {
		"objects": [
			{
				"collection": collection,
				"key": key,
				"value": JSON.stringify(value),
				"permission_read": permission_read,
				"permission_write": permission_write,
			}
		]
	}
	var res: Dictionary = await _request_json(HTTPClient.METHOD_PUT, "/v2/storage", JSON.stringify(body), true)
	if not bool(res.get("ok", false)):
		last_error = String(res.get("error", "Storage-Schreibfehler"))
		return false
	return true


func read_storage(collection: String, key: String, target_user_id: String = "") -> Dictionary:
	if token.is_empty():
		last_error = "Nicht eingeloggt"
		return {}
	var owner_id: String = user_id if target_user_id.is_empty() else target_user_id
	var body: Dictionary = {
		"object_ids": [
			{
				"collection": collection,
				"key": key,
				"user_id": owner_id,
			}
		]
	}
	var res: Dictionary = await _request_json(HTTPClient.METHOD_POST, "/v2/storage", JSON.stringify(body), true)
	if not bool(res.get("ok", false)):
		last_error = String(res.get("error", "Storage-Lesefehler"))
		return {}
	var objects: Array = (res.get("data", {}) as Dictionary).get("objects", []) as Array
	if objects.is_empty():
		return {}
	var first: Dictionary = objects[0] as Dictionary
	var parsed: Variant = JSON.parse_string(String(first.get("value", "{}")))
	return parsed as Dictionary if parsed is Dictionary else {}


func save_player_profile(player_data: Dictionary) -> bool:
	var res: Dictionary = await _call_ok_rpc("save_cloud_player", {"data": player_data})
	return bool(res.get("ok", false))


func load_player_profile() -> Dictionary:
	return await read_storage("saves", "player_profile")


func save_world_state(world_data: Dictionary) -> bool:
	var day_val: int = int(world_data.get("day", 0))
	var time_val: float = float(world_data.get("time", 0.0))
	var saved_val: int = int(world_data.get("saved_at", int(Time.get_unix_time_from_system())))
	var player_data: Dictionary = world_data.get("player", {}) as Dictionary
	var wrapped: Dictionary = {
		"version": SaveGame.VERSION,
		"day": day_val,
		"time": time_val,
		"level": Levels.level_for(int(player_data.get("xp", 0))), ## shown on the launcher's play stone, read without unpacking "gz"
		"saved_at": saved_val,
		"gz": SaveGame.compress_json(world_data),
	}
	var res: Dictionary = await _call_ok_rpc("save_cloud_world", {"data": wrapped})
	var ok: bool = bool(res.get("ok", false))
	if ok:
		_apply_world_meta({"day": day_val, "time": time_val, "saved_at": saved_val})
	return ok


func wipe_cloud_save() -> bool:
	if not is_logged_in():
		return false
	var res: Dictionary = await _call_ok_rpc("wipe_cloud_save", {})
	var ok: bool = bool(res.get("ok", false))
	if ok:
		_apply_world_meta({})
	return ok


func redeem_launch_ticket(ticket_str: String, exe_sha256: String) -> Dictionary:
	return await _call_ok_rpc("redeem_launch_ticket", {
		"ticket": ticket_str,
		"exe_sha256": exe_sha256,
	})


func send_game_heartbeat(nonce: String, uptime_sec: float, tamper_flag: String = "", debug_session: bool = false) -> Dictionary:
	var payload: Dictionary = {
		"session_nonce": nonce,
		"client_uptime_sec": uptime_sec,
		"debug_session": debug_session,
	}
	if not tamper_flag.is_empty():
		payload["tamper_flag"] = tamper_flag
	var res: Dictionary = await call_rpc("game_heartbeat", payload)
	if res.is_empty():
		return {"ok": false, "transient": true, "error": last_error}
	return res


func end_game_session(nonce: String) -> void:
	if not is_logged_in() or nonce.is_empty():
		return
	await call_rpc("end_game_session", {"session_nonce": nonce})


func report_security_event(kind: String, detail: String, severity: String = "warn") -> void:
	if not is_logged_in():
		return
	await call_rpc("report_security_event", {
		"kind": kind,
		"detail": detail,
		"severity": severity,
	})


func load_world_state() -> Dictionary:
	var wrapped: Dictionary = await read_storage("saves", "world_state")
	if wrapped.is_empty() or bool(wrapped.get("empty", false)):
		return {}
	return SaveGame.decompress_json(String(wrapped.get("gz", "")))


## Loads account's `player_profile` and (if server/host) `world_state` into the active world.
func load_cloud_into(tree: SceneTree, resume: bool = true) -> bool:
	if not is_logged_in() or tree.get_first_node_in_group("sandbox") != null:
		return false
	if not tree.root.multiplayer.is_server():
		return false
	var player: Player = SaveGame._local_player(tree)
	if player == null:
		return false
	var pdata: Dictionary = await load_player_profile()
	if not pdata.is_empty():
		_remember_solo_preserve(pdata)
		SaveGame.import_player_data(player, pdata, true, true)
	var wdata: Dictionary = await load_world_state()
	if wdata.is_empty():
		return false
	return SaveGame.import_world_data(tree, wdata, player, resume)


## Saves local player's profile and (if server/host) the world state to Nakama.
## Guests in another player's world only update their portable Cloud Character (preserving solo position & quests).
func save_cloud_all(tree: SceneTree) -> bool:
	if not is_logged_in() or tree == null or tree.get_first_node_in_group("sandbox") != null:
		return false
	if NetworkManager.is_local_coop_guest() or not tree.root.multiplayer.is_server():
		return await save_cloud_coop_character(tree)
	var player: Player = SaveGame._local_player(tree)
	if player == null:
		return false
	var live_player: Dictionary = SaveGame.export_player_data(player)
	_remember_solo_preserve(live_player)
	var ok_player: bool = await save_player_profile(live_player)
	if not ok_player:
		return false
	return await save_world_state(SaveGame.export_world_data(tree))


## Saves only portable character fields (inventory, equipment, progression, skill tree, appearance, health)
## while keeping the player's solo world position, quests, and board journal intact.
func save_cloud_coop_character(tree: SceneTree) -> bool:
	if not is_logged_in() or tree == null or tree.get_first_node_in_group("sandbox") != null:
		return false
	var player: Player = SaveGame._local_player(tree)
	var live: Dictionary = SaveGame.export_player_data(player) if player != null and is_instance_valid(player) else _cached_player_snapshot.duplicate(true)
	if live.is_empty():
		return false
	return await _save_coop_character_snapshot(live)


func _save_coop_character_snapshot(live: Dictionary) -> bool:
	if not is_logged_in() or live.is_empty():
		return false
	if _solo_profile_preserve.is_empty():
		var prev: Dictionary = await load_player_profile()
		_remember_solo_preserve(prev)
	var merged: Dictionary = _solo_profile_preserve.duplicate(true)
	for key: String in COOP_PORTABLE_KEYS:
		if live.has(key):
			merged[key] = live[key]
	for key: String in COOP_PRESERVE_KEYS:
		if not merged.has(key) and live.has(key):
			merged[key] = live[key]
	return await save_player_profile(merged)


func _remember_solo_preserve(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	for key: String in COOP_PRESERVE_KEYS:
		if profile.has(key):
			var val: Variant = profile[key]
			_solo_profile_preserve[key] = val.duplicate(true) if val is Dictionary or val is Array else val


func is_save_in_flight() -> bool:
	return _save_in_flight


func set_autosave_suppressed(suppressed: bool) -> void:
	_autosave_suppressed = suppressed
	if suppressed:
		_dirty = false
		_dirty_save_timer = -1.0


func reset_autosave_state() -> void:
	_dirty = false
	_dirty_save_timer = -1.0
	_save_pending_again = false
	_auto_save_timer = AUTO_SAVE_INTERVAL_SEC
	_cached_player_snapshot.clear()
	_cached_world_snapshot.clear()
	_solo_profile_preserve.clear()
	_watched_world_id = 0
	_watched_player_id = 0


func on_world_entered(tree: SceneTree, mode: String) -> void:
	_autosave_suppressed = false
	_dirty_save_timer = -1.0
	_auto_save_timer = AUTO_SAVE_INTERVAL_SEC
	_snapshot_timer = 0.0
	if tree == null or not _in_playable_world(tree):
		return
	capture_live_snapshot(tree, false)
	var world: Node = tree.get_first_node_in_group("world")
	var player: Player = SaveGame._local_player(tree)
	_ensure_autosave_watchers(tree, world, player)
	if mode == "new" or not has_cloud_save:
		mark_save_dirty(1.5)


func mark_save_dirty(debounce_sec: float = DIRTY_SAVE_DEBOUNCE_SEC) -> void:
	if _autosave_suppressed or _quit_in_progress:
		return
	var tree: SceneTree = get_tree()
	if tree != null and _in_playable_world(tree):
		capture_live_snapshot(tree, false)
	_dirty = true
	var delay: float = maxf(debounce_sec, 0.05)
	if _dirty_save_timer < 0.0 or _dirty_save_timer > delay:
		_dirty_save_timer = delay


func capture_live_snapshot(tree: SceneTree, include_world: bool = false, force_server_role: int = -1) -> bool:
	if not _in_playable_world(tree):
		return false
	var player: Player = SaveGame._local_player(tree)
	if player == null or not is_instance_valid(player):
		return false
	var as_server: bool = (force_server_role == 1) if force_server_role >= 0 else (not NetworkManager.is_local_coop_guest() and tree.root.multiplayer.is_server())
	_cached_snapshot_is_server = as_server
	_cached_player_snapshot = SaveGame.export_player_data(player)
	if as_server:
		_remember_solo_preserve(_cached_player_snapshot)
		if include_world:
			_cached_world_snapshot = SaveGame.export_world_data(tree)
	else:
		_cached_world_snapshot.clear()
	return true


func flush_cloud_save_now(tree: SceneTree, timeout_msec: int = QUIT_FLUSH_TIMEOUT_MSEC) -> bool:
	if tree == null or _autosave_suppressed:
		return false
	capture_live_snapshot(tree, true)
	if _cached_player_snapshot.is_empty() and not _in_playable_world(tree):
		return false
	if _save_in_flight:
		_save_pending_again = true
		var deadline: int = Time.get_ticks_msec() + timeout_msec
		while _save_in_flight and Time.get_ticks_msec() < deadline:
			await tree.process_frame
			if not is_instance_valid(tree):
				return false
		if _save_in_flight:
			return false
	return await _execute_cloud_save(tree)


func graceful_quit() -> void:
	if _quit_in_progress:
		return
	_quit_in_progress = true
	var tree: SceneTree = get_tree()
	if DisplayServer.get_name() == "headless":
		_stop_ipc_server()
		if tree != null:
			tree.quit(0)
		return
	GameSettings.save()
	var prev_timeout: int = _http_timeout_override_msec
	_http_timeout_override_msec = 2000
	if tree != null and (_in_playable_world(tree) or not _cached_player_snapshot.is_empty()):
		if not _autosave_suppressed and not GameGuard.locked:
			await flush_cloud_save_now(tree, QUIT_FLUSH_TIMEOUT_MSEC)
	_http_timeout_override_msec = 1000
	var closing_match_id: String = ""
	if NetworkManager.transport_mode == "relay" and multiplayer.is_server() and is_logged_in():
		closing_match_id = NetworkManager.active_match_id
	if is_instance_valid(tree):
		tree.paused = true
	NetworkManager.leave(false)
	if not closing_match_id.is_empty() and is_logged_in():
		await coop_close_world(closing_match_id)
	if is_logged_in() and not GameGuard.session_nonce.is_empty():
		await end_game_session(GameGuard.session_nonce)
	_http_timeout_override_msec = prev_timeout
	_stop_ipc_server()
	if is_instance_valid(tree):
		tree.quit(0)


func _on_autosave_day_started(_day: int) -> void:
	mark_save_dirty()


func _on_autosave_dirty_signal(_arg1: Variant = null, _arg2: Variant = null, _arg3: Variant = null, _arg4: Variant = null) -> void:
	mark_save_dirty()


func _in_playable_world(tree: SceneTree) -> bool:
	if tree == null or tree.get_first_node_in_group("sandbox") != null:
		return false
	var world: Node = tree.get_first_node_in_group("world")
	if world == null or not is_instance_valid(world):
		return false
	var loading_steps: Variant = world.get("loading_in_steps")
	if loading_steps is bool and bool(loading_steps):
		return false
	var player: Player = SaveGame._local_player(tree)
	return player != null and is_instance_valid(player)


func _connect_dirty_signal(target: Object, sig_name: StringName) -> void:
	if target == null or not target.has_signal(sig_name):
		return
	var cb: Callable = Callable(self, "_on_autosave_dirty_signal")
	if not target.is_connected(sig_name, cb):
		target.connect(sig_name, cb)


func _ensure_autosave_watchers(tree: SceneTree, world: Node, player: Player) -> void:
	if world != null and world.get_instance_id() != _watched_world_id:
		_watched_world_id = world.get_instance_id()
		_auto_save_timer = AUTO_SAVE_INTERVAL_SEC
		if tree.root.multiplayer.is_server() and not NetworkManager.is_local_coop_guest():
			_connect_dirty_signal(tree.get_first_node_in_group("town"), &"changed")
			_connect_dirty_signal(tree.get_first_node_in_group("board"), &"changed")
			var farm: Node = tree.get_first_node_in_group("farm")
			if farm == null:
				farm = world.get_node_or_null("FarmManager")
			_connect_dirty_signal(farm, &"cell_changed")
			_connect_dirty_signal(Waystones.of(tree), &"awakened")
			_connect_dirty_signal(Vistas.of(tree), &"discovered")
	if player != null and player.get_instance_id() != _watched_player_id:
		_watched_player_id = player.get_instance_id()
		_connect_dirty_signal(player.inventory, &"changed")
		_connect_dirty_signal(player.inventory, &"socketed")
		_connect_dirty_signal(player.progress, &"changed")
		_connect_dirty_signal(player.progress, &"leveled")
		_connect_dirty_signal(player.progress, &"claimed_changed")
		_connect_dirty_signal(player.get_node_or_null("SkillTreeComponent"), &"changed")
		_connect_dirty_signal(player.quests, &"changed")
		_connect_dirty_signal(player.appearance, &"changed")
		_connect_dirty_signal(player.talismans, &"changed")
		_connect_dirty_signal(player.talismans, &"ward_changed")
		_connect_dirty_signal(player.health, &"died")


func _tick_autosave(delta: float) -> void:
	if (DisplayServer.get_name() == "headless" and not allow_headless_autosave) or _quit_in_progress or _autosave_suppressed:
		return
	var tree: SceneTree = get_tree()
	if tree == null or GameLauncher.is_transitioning():
		return
	if not _in_playable_world(tree):
		_watched_world_id = 0
		_watched_player_id = 0
		_dirty = false
		_dirty_save_timer = -1.0
		return
	var world: Node = tree.get_first_node_in_group("world")
	var player: Player = SaveGame._local_player(tree)
	_ensure_autosave_watchers(tree, world, player)
	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_REFRESH_SEC:
		_snapshot_timer = 0.0
		capture_live_snapshot(tree, false)
	if GameGuard.locked:
		return
	_auto_save_timer -= delta
	if _dirty and _dirty_save_timer >= 0.0:
		_dirty_save_timer -= delta
		if _dirty_save_timer <= 0.0:
			_dirty_save_timer = -1.0
			if not _save_in_flight:
				_execute_cloud_save(tree)
			else:
				_save_pending_again = true
	if _auto_save_timer <= 0.0:
		_auto_save_timer = AUTO_SAVE_INTERVAL_SEC
		if not _save_in_flight:
			_execute_cloud_save(tree)
		else:
			_save_pending_again = true


func _execute_cloud_save(tree: SceneTree, sync_local: bool = false) -> bool:
	if _save_in_flight or _autosave_suppressed:
		return false
	_save_in_flight = true
	_save_pending_again = false
	_dirty = false
	_dirty_save_timer = -1.0
	_auto_save_timer = AUTO_SAVE_INTERVAL_SEC
	capture_live_snapshot(tree, true)
	var want_local: bool = not is_strict_release() and _cached_snapshot_is_server and _in_playable_world(tree)
	var want_cloud: bool = is_logged_in() and is_entitled() and not GameGuard.locked
	var local_ok: bool = false
	if want_local:
		if sync_local or _quit_in_progress:
			local_ok = SaveGame.save(tree, "", _cached_world_snapshot, _cached_player_snapshot)
		elif want_cloud:
			SaveGame.save_async(tree, Callable(), "", _cached_world_snapshot, _cached_player_snapshot)
		else:
			var started: bool = SaveGame.save_async(
				tree,
				func(saved_ok: bool) -> void: _async_local_save_finished.emit(saved_ok),
				"",
				_cached_world_snapshot,
				_cached_player_snapshot
			)
			if started:
				local_ok = await _async_local_save_finished
	var cloud_ok: bool = false
	if want_cloud:
		if _cached_snapshot_is_server:
			if not _cached_player_snapshot.is_empty():
				var ok_p: bool = await save_player_profile(_cached_player_snapshot)
				if ok_p:
					if not _cached_world_snapshot.is_empty():
						cloud_ok = await save_world_state(_cached_world_snapshot)
					else:
						cloud_ok = true
		else:
			cloud_ok = await _save_coop_character_snapshot(_cached_player_snapshot)
	var overall_ok: bool = cloud_ok if is_strict_release() or is_logged_in() else local_ok
	_save_in_flight = false
	auto_save_finished.emit(overall_ok)
	if _save_pending_again and not _quit_in_progress and not _autosave_suppressed and is_instance_valid(tree) and _in_playable_world(tree):
		_dirty = true
		_dirty_save_timer = 0.25
	elif not is_instance_valid(tree) or not _in_playable_world(tree):
		_cached_player_snapshot.clear()
		_cached_world_snapshot.clear()
	return overall_ok


## --- Coop / Lobby / Match RPCs ---

func set_world_join_mode(mode: String) -> Dictionary:
	var clean: String = mode.strip_edges().to_lower()
	if not (clean in VALID_JOIN_MODES):
		return {"ok": false, "error": "Ungueltiger Modus"}
	var res: Dictionary = await _call_ok_rpc("set_world_join_mode", {"join_mode": clean})
	if bool(res.get("ok", false)):
		world_join_mode = String(res.get("world_join_mode", clean))
		NetworkManager.set_active_join_mode(world_join_mode)
		profile_loaded.emit({"uid": uid, "world_join_mode": world_join_mode, "role": role})
	return res


func coop_open_world(world_name: String = "KOOP-WELT", join_mode: String = "", max_players: int = 4, force_new: bool = false, room_code: String = "") -> Dictionary:
	var payload: Dictionary = {
		"world_name": world_name,
		"max_players": clampi(max_players, 2, 4),
		"force_new": force_new,
	}
	if not join_mode.is_empty():
		payload["join_mode"] = join_mode
	if not room_code.is_empty():
		payload["room_code"] = room_code
	return await _call_ok_rpc("coop_open_world", payload)


func coop_close_world(target_match_id: String = "") -> void:
	if not is_logged_in():
		return
	var payload: Dictionary = {"match_id": target_match_id} if not target_match_id.is_empty() else {}
	await call_rpc("coop_close_world", payload)


func coop_heartbeat(world_name: String, player_count: int) -> void:
	if not is_logged_in():
		return
	await call_rpc("coop_heartbeat", {"world_name": world_name, "player_count": player_count})


func coop_resolve_code(code: String) -> Dictionary:
	return await _call_ok_rpc("coop_resolve_code", {"room_code": code})


func coop_invite_friend(target_user_id_or_uid: String) -> Dictionary:
	var clean: String = target_user_id_or_uid.strip_edges()
	var payload: Dictionary = {"target_user_id": clean} if "-" in clean else {"query": clean}
	return await _call_ok_rpc("coop_invite_friend", payload)


func coop_request_join(host_uid_or_user_id: String = "", room_code: String = "") -> Dictionary:
	var payload: Dictionary = {}
	var clean_host: String = host_uid_or_user_id.strip_edges()
	if not clean_host.is_empty():
		if "-" in clean_host:
			payload["host_user_id"] = clean_host
		else:
			payload["host_uid"] = clean_host
	if not room_code.strip_edges().is_empty():
		payload["room_code"] = room_code.strip_edges().to_upper()
	return await _call_ok_rpc("coop_request_join", payload)


func coop_respond_join_request(requester_user_id: String, accept: bool) -> Dictionary:
	var res: Dictionary = await _call_ok_rpc("coop_respond_join_request", {
		"requester_user_id": requester_user_id,
		"accept": accept,
	})
	if bool(res.get("ok", false)):
		dismiss_local_notifications_for_requester(requester_user_id)
	return res


func coop_get_peer_character(target_user_id: String, match_id: String = "", ticket: String = "") -> Dictionary:
	return await _call_ok_rpc("coop_get_peer_character", {
		"target_user_id": target_user_id,
		"match_id": match_id,
		"ticket": ticket,
	})


func coop_issue_ticket() -> Dictionary:
	return await _call_ok_rpc("coop_issue_ticket", {})


func coop_verify_ticket(target_user_id: String, ticket: String) -> Dictionary:
	return await _call_ok_rpc("coop_verify_ticket", {"user_id": target_user_id, "ticket": ticket})


func refresh_friends() -> Array[Dictionary]:
	if not is_logged_in():
		friends_cache.clear()
		friends_list_loaded.emit([])
		return []
	var rows: Array[Dictionary] = await list_friends()
	friends_cache = rows
	friends_changed.emit()
	friends_list_loaded.emit(rows)
	return rows


func fetch_notifications() -> Array[Dictionary]:
	if not is_logged_in():
		return notifications
	var res: Dictionary = await _request_json(HTTPClient.METHOD_GET, "/v2/notification?limit=20", "", true)
	if not bool(res.get("ok", false)):
		return notifications
	var raw_list: Array = (res.get("data", {}) as Dictionary).get("notifications", []) as Array
	var out: Array[Dictionary] = []
	for item: Variant in raw_list:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item as Dictionary
		var code: int = int(row.get("code", 0))
		if code < 101 or code > 104:
			continue
		var content_raw: String = String(row.get("content", "{}"))
		var parsed: Variant = JSON.parse_string(content_raw)
		var content: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
		out.append({
			"id": String(row.get("id", "")),
			"code": code,
			"subject": String(row.get("subject", "")),
			"sender_id": String(row.get("sender_id", "")),
			"create_time": String(row.get("create_time", "")),
			"content": content,
		})
	notifications = out
	notifications_changed.emit()
	return notifications


func delete_notification(notif_id: String) -> void:
	if not is_logged_in() or notif_id.is_empty():
		return
	await _request_json(HTTPClient.METHOD_DELETE, "/v2/notification?ids=" + notif_id.uri_encode(), "", true)
	notifications = notifications.filter(func(n: Dictionary) -> bool: return String(n.get("id", "")) != notif_id)
	notifications_changed.emit()


func dismiss_local_notifications_for_requester(requester_user_id: String) -> void:
	var kept: Array[Dictionary] = []
	for n: Dictionary in notifications:
		var c: Dictionary = n.get("content", {}) as Dictionary
		if int(n.get("code", 0)) == 102 and String(c.get("requester_user_id", "")) == requester_user_id:
			var nid: String = String(n.get("id", ""))
			if not nid.is_empty():
				delete_notification(nid)
			continue
		kept.append(n)
	notifications = kept
	notifications_changed.emit()


func _apply_session_tokens(new_token: String, new_refresh: String) -> void:
	token = new_token
	if not new_refresh.is_empty():
		refresh_token = new_refresh
	var parts: PackedStringArray = token.split(".")
	if parts.size() >= 2:
		var b64: String = parts[1].replace("-", "+").replace("_", "/")
		while b64.length() % 4 != 0:
			b64 += "="
		var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			var claims: Dictionary = parsed as Dictionary
			user_id = String(claims.get("uid", user_id))
			username = String(claims.get("usn", username))


func _request_json(method: HTTPClient.Method, path: String, body: String, use_bearer: bool) -> Dictionary:
	var parsed_url: Dictionary = _parse_http_url(server_url)
	var host: String = String(parsed_url.get("host", "127.0.0.1"))
	var port: int = int(parsed_url.get("port", 7350))
	var use_tls: bool = bool(parsed_url.get("tls", false))

	var hc: HTTPClient = HTTPClient.new()
	var tls_opts: TLSOptions = TLSOptions.client() if use_tls else null
	var err: Error = hc.connect_to_host(host, port, tls_opts)
	if err != OK:
		return {"ok": false, "error": "Verbindungsfehler (%d)" % err}

	var timeout_ms: int = mini(10000, _http_timeout_override_msec) if _http_timeout_override_msec > 0 else 10000
	var deadline_ms: int = Time.get_ticks_msec() + timeout_ms
	while hc.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		hc.poll()
		if Time.get_ticks_msec() > deadline_ms:
			return {"ok": false, "error": "Timeout beim Verbinden mit Nakama"}
		await get_tree().process_frame

	if hc.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "error": "Nakama nicht erreichbar (Status %d)" % hc.get_status()}

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Accept-Encoding: identity",
	])
	if use_bearer:
		headers.append("Authorization: Bearer " + token)
	else:
		var basic: String = Marshalls.utf8_to_base64(server_key + ":")
		headers.append("Authorization: Basic " + basic)

	err = hc.request(method, path, headers, body)
	if err != OK:
		return {"ok": false, "error": "HTTP Request Fehler (%d)" % err}

	while hc.get_status() == HTTPClient.STATUS_REQUESTING:
		hc.poll()
		if Time.get_ticks_msec() > deadline_ms:
			return {"ok": false, "error": "Timeout bei Anfrage an Nakama"}
		await get_tree().process_frame

	if not hc.has_response():
		return {"ok": false, "error": "Keine Antwort von Nakama (Status %d)" % hc.get_status()}

	var status: int = hc.get_response_code()
	var chunks: PackedByteArray = PackedByteArray()
	while hc.get_status() == HTTPClient.STATUS_BODY:
		hc.poll()
		var chunk: PackedByteArray = hc.read_response_body_chunk()
		if chunk.is_empty():
			await get_tree().process_frame
		else:
			chunks.append_array(chunk)
		if Time.get_ticks_msec() > deadline_ms:
			return {"ok": false, "error": "Timeout beim Lesen der Antwort"}

	var text: String = chunks.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var json_data: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	if status < 200 or status >= 300:
		var msg: String = String(json_data.get("message", text))
		return {"ok": false, "status": status, "error": msg}
	return {"ok": true, "status": status, "data": json_data}


static func _parse_http_url(raw_url: String) -> Dictionary:
	var clean: String = raw_url.strip_edges().trim_suffix("/")
	var tls: bool = clean.begins_with("https://")
	var without_scheme: String = clean.replace("https://", "").replace("http://", "")
	var slash_idx: int = without_scheme.find("/")
	if slash_idx >= 0:
		without_scheme = without_scheme.substr(0, slash_idx)
	var colon_idx: int = without_scheme.rfind(":")
	if colon_idx >= 0:
		return {
			"host": without_scheme.substr(0, colon_idx),
			"port": int(without_scheme.substr(colon_idx + 1)),
			"tls": tls,
		}
	return {
		"host": without_scheme,
		"port": 443 if tls else 80,
		"tls": tls,
	}


func _load_config() -> void:
	if not OS.is_debug_build():
		_load_bundled_release_auth()
		return
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		var cfg: Dictionary = parsed as Dictionary
		server_url = String(cfg.get("server_url", server_url))
		server_key = String(cfg.get("server_key", server_key))


func _read_cmdline_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if not OS.is_debug_build():
		_load_bundled_release_auth()
		return
	for arg: String in all_args:
		if arg == "--strict-guard":
			strict_override = true
		elif arg.begins_with("--nakama-url="):
			server_url = arg.substr("--nakama-url=".length())
		elif arg.begins_with("--nakama-server-key="):
			server_key = arg.substr("--nakama-server-key=".length())
		elif arg.begins_with("--nakama-token="):
			_apply_session_tokens(arg.substr("--nakama-token=".length()), "")
		elif arg.begins_with("--nakama-refresh="):
			refresh_token = arg.substr("--nakama-refresh=".length())


func _poll_notif_ws(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not is_logged_in():
		if _notif_ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			_notif_ws.close()
		_notif_ws_token = ""
		return
	var state: WebSocketPeer.State = _notif_ws.get_ready_state()
	if _notif_ws_token != token and state == WebSocketPeer.STATE_CLOSED:
		_notif_ws_retry_t = 0.0
	if state == WebSocketPeer.STATE_CLOSED:
		_notif_ws_retry_t -= delta
		if _notif_ws_retry_t <= 0.0:
			_notif_ws_retry_t = 12.0
			_notif_ws_token = token
			_notif_ws = WebSocketPeer.new()
			var ws_url: String = RelayPeer.build_ws_url(server_url, token)
			_notif_ws.connect_to_url(ws_url)
		return
	_notif_ws.poll()
	if state == WebSocketPeer.STATE_OPEN:
		while _notif_ws.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _notif_ws.get_packet()
			if pkt.is_empty():
				continue
			var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary:
				_handle_ws_envelope(parsed as Dictionary)


func _handle_ws_envelope(env: Dictionary) -> void:
	if not env.has("notifications"):
		return
	var container: Dictionary = env.get("notifications", {}) as Dictionary
	var raw_items: Array = container.get("notifications", []) as Array
	var changed: bool = false
	for item: Variant in raw_items:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item as Dictionary
		var code: int = int(row.get("code", 0))
		if code < 101 or code > 104:
			continue
		var parsed: Variant = JSON.parse_string(String(row.get("content", "{}")))
		var content: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
		var nid: String = String(row.get("id", ""))
		if not nid.is_empty():
			notifications = notifications.filter(func(existing: Dictionary) -> bool: return String(existing.get("id", "")) != nid)
		notifications.push_front({
			"id": nid,
			"code": code,
			"subject": String(row.get("subject", "")),
			"sender_id": String(row.get("sender_id", "")),
			"create_time": String(row.get("create_time", "")),
			"content": content,
		})
		changed = true
		if code == 103 and String(content.get("match_id", "")) != "" and NetworkManager.is_offline():
			EventBus.toast("BEITRITTSANFRAGE ANGENOMMEN: %s" % String(content.get("world_name", "KOOP")))
	if changed:
		notifications_changed.emit()


func _ipc_file_path() -> String:
	return OS.get_data_dir().path_join("Shadowspore/ipc.json")


func _start_ipc_server() -> void:
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.has("--no-ipc"):
		return
	_ipc_server = TCPServer.new()
	if _ipc_server.listen(0, "127.0.0.1") != OK:
		_ipc_server = null
		return
	_ipc_port = _ipc_server.get_local_port()
	_ipc_secret = Crypto.new().generate_random_bytes(24).hex_encode()
	_ipc_path = _ipc_file_path()
	DirAccess.make_dir_recursive_absolute(_ipc_path.get_base_dir())
	var f: FileAccess = FileAccess.open(_ipc_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"pid": OS.get_process_id(),
			"port": _ipc_port,
			"secret": _ipc_secret,
			"user_id": user_id,
		}))
		f.close()


func _stop_ipc_server() -> void:
	for entry: Dictionary in _ipc_clients:
		var stream: StreamPeerTCP = entry.get("stream") as StreamPeerTCP
		if stream != null:
			stream.disconnect_from_host()
	_ipc_clients.clear()
	if _ipc_server != null:
		_ipc_server.stop()
		_ipc_server = null
	if not _ipc_path.is_empty() and FileAccess.file_exists(_ipc_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_ipc_path))
		if parsed is Dictionary and int((parsed as Dictionary).get("pid", 0)) == OS.get_process_id():
			DirAccess.remove_absolute(_ipc_path)


func _poll_ipc() -> void:
	if _ipc_server == null or not _ipc_server.is_listening():
		return
	while _ipc_server.is_connection_available():
		var client: StreamPeerTCP = _ipc_server.take_connection()
		if client != null:
			client.set_no_delay(true)
			_ipc_clients.append({"stream": client, "buf": "", "created": Time.get_ticks_msec()})
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _ipc_clients:
		var client: StreamPeerTCP = entry.get("stream") as StreamPeerTCP
		if client == null or client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if Time.get_ticks_msec() - int(entry.get("created", 0)) > 3000:
			client.disconnect_from_host()
			continue
		var avail: int = client.get_available_bytes()
		if avail > 0:
			var got: Array = client.get_partial_data(avail)
			if int(got[0]) == OK:
				entry["buf"] = String(entry["buf"]) + (got[1] as PackedByteArray).get_string_from_utf8()
		var buf: String = String(entry["buf"])
		var hdr_end: int = buf.find("\r\n\r\n")
		if hdr_end >= 0:
			var head: String = buf.substr(0, hdr_end)
			var content_len: int = 0
			var auth_ok: bool = false
			for line: String in head.split("\r\n"):
				var lower: String = line.to_lower()
				if lower.begins_with("content-length:"):
					content_len = line.substr(15).strip_edges().to_int()
				elif lower.begins_with("authorization:"):
					var val: String = line.substr(14).strip_edges()
					if val == "Bearer " + _ipc_secret:
						auth_ok = true
			var body_start: int = hdr_end + 4
			if buf.length() >= body_start + content_len:
				var body: String = buf.substr(body_start, content_len)
				var resp_obj: Dictionary = _handle_ipc_request(auth_ok, body)
				var resp_json: String = JSON.stringify(resp_obj)
				var status_line: String = "HTTP/1.1 200 OK" if auth_ok else "HTTP/1.1 401 Unauthorized"
				var http_resp: String = "%s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
					status_line,
					resp_json.to_utf8_buffer().size(),
					resp_json,
				]
				client.put_data(http_resp.to_utf8_buffer())
				client.disconnect_from_host()
				continue
		keep.append(entry)
	_ipc_clients = keep


func _handle_ipc_request(auth_ok: bool, body: String) -> Dictionary:
	if not auth_ok:
		return {"ok": false, "error": "unauthorized"}
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "invalid json"}
	var cmd: Dictionary = parsed as Dictionary
	var action: String = String(cmd.get("action", ""))
	if action == "ping":
		return {
			"ok": true,
			"pid": OS.get_process_id(),
			"user_id": user_id,
			"uid": uid,
			"coop_active": NetworkManager.is_multiplayer_session(),
			"match_id": NetworkManager.active_match_id,
		}
	if action == "update_session":
		var new_tok: String = String(cmd.get("token", ""))
		var new_ref: String = String(cmd.get("refresh_token", ""))
		var new_url: String = String(cmd.get("server_url", ""))
		var new_key: String = String(cmd.get("server_key", ""))
		if OS.is_debug_build():
			if not new_url.is_empty():
				server_url = new_url
			if not new_key.is_empty():
				server_key = new_key
		if not new_tok.is_empty():
			_apply_session_tokens(new_tok, new_ref)
			fetch_my_profile()
		return {"ok": true}
	if action == "host_coop" or action == "join_match" or action == "join_code":
		ipc_command_received.emit(cmd)
		_execute_ipc_launch.call_deferred(cmd)
		return {"ok": true}
	return {"ok": false, "error": "unknown action"}


func _execute_ipc_launch(cmd: Dictionary) -> void:
	DisplayServer.window_move_to_foreground()
	var action: String = String(cmd.get("action", ""))
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if is_logged_in() and not NetworkManager.is_offline() and not tree.root.multiplayer.is_server():
		await save_cloud_coop_character(tree)
	elif is_logged_in() and tree.root.multiplayer.is_server() and tree.get_first_node_in_group("world") != null:
		await save_cloud_all(tree)
	if action == "host_coop":
		GameLauncher.launch(tree, {
			"mode": "host_relay",
			"world_name": String(cmd.get("world_name", "KOOP-WELT")),
			"join_mode": String(cmd.get("join_mode", world_join_mode)),
			"room_code": String(cmd.get("room_code", "")),
		})
	elif action == "join_match":
		GameLauncher.launch(tree, {
			"mode": "join_relay",
			"match_id": String(cmd.get("match_id", "")),
			"code": String(cmd.get("room_code", "")),
			"world_name": String(cmd.get("world_name", "KOOP-WELT")),
		})
	elif action == "join_code":
		GameLauncher.launch(tree, {
			"mode": "join_relay",
			"code": String(cmd.get("room_code", "")),
		})


func _save_session() -> void:
	if is_strict_release():
		return
	var file: FileAccess = FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"refresh_token": refresh_token,
		"user_id": user_id,
		"uid": uid,
	}))
	file.close()


func _load_session() -> void:
	if is_strict_release():
		return
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if parsed is Dictionary:
		var data: Dictionary = parsed as Dictionary
		refresh_token = String(data.get("refresh_token", ""))
		user_id = String(data.get("user_id", ""))
		uid = String(data.get("uid", ""))
