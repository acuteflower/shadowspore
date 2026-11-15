extends Node
## Nakama cloud session, UID profile, and split cloud saves (`player_profile` + `world_state`).
## Talks to Nakama HTTP REST API with strict static typing and zero external addon dependencies.

const DEFAULT_URL: String = "http://127.0.0.1:7350"
const DEFAULT_SERVER_KEY: String = "shadowspore_dev_server_key"
const SESSION_PATH: String = "user://cloud_session.json"
const CONFIG_PATH: String = "user://cloud_config.json"

signal auth_changed(logged_in: bool)
signal profile_loaded(profile: Dictionary)
signal save_info_changed()
signal friends_changed()

var server_url: String = DEFAULT_URL
var server_key: String = DEFAULT_SERVER_KEY
var token: String = ""
var refresh_token: String = ""
var user_id: String = ""
var username: String = ""
const VALID_ROLES: PackedStringArray = ["player", "tester", "moderator", "admin"]

var display_name: String = ""
var uid: String = ""
var world_join_mode: String = "ask"
var role: String = "player"
var has_cloud_save: bool = false
var cloud_save_day: int = -1
var cloud_save_time: float = 0.0
var cloud_save_at: int = 0
var last_error: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_read_cmdline_args()


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
	has_cloud_save = false
	cloud_save_day = -1
	cloud_save_time = 0.0
	cloud_save_at = 0
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)
	save_info_changed.emit()
	auth_changed.emit(false)


## Authenticates with email + password. Set `create = true` to auto-register new accounts.
func authenticate_email(email: String, password: String, create: bool = true, custom_username: String = "") -> Dictionary:
	last_error = ""
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
	_save_session()
	auth_changed.emit(true)
	return {"ok": true, "profile": profile}


## Restores a saved session (e.g. from launcher or previous login) via refresh token.
func try_restore_session() -> bool:
	if not token.is_empty():
		var profile: Dictionary = await fetch_my_profile()
		if not profile.is_empty():
			auth_changed.emit(true)
			return true
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
		"/v2/account/authenticate/session/refresh",
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


## Calls Lua RPC `get_my_profile` -> assigns/returns persistent UID.
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
	await refresh_cloud_save_info()
	profile_loaded.emit(data)
	return data


func refresh_cloud_save_info() -> void:
	if not is_logged_in():
		_apply_world_meta({})
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
	return await write_storage("saves", "player_profile", player_data, 1, 1)


func load_player_profile() -> Dictionary:
	return await read_storage("saves", "player_profile")


func save_world_state(world_data: Dictionary) -> bool:
	var day_val: int = int(world_data.get("day", 0))
	var time_val: float = float(world_data.get("time", 0.0))
	var saved_val: int = int(world_data.get("saved_at", int(Time.get_unix_time_from_system())))
	var wrapped: Dictionary = {
		"version": SaveGame.VERSION,
		"day": day_val,
		"time": time_val,
		"saved_at": saved_val,
		"gz": SaveGame.compress_json(world_data),
	}
	var ok: bool = await write_storage("saves", "world_state", wrapped, 1, 1)
	if ok:
		var meta: Dictionary = {"day": day_val, "time": time_val, "saved_at": saved_val}
		await write_storage("saves", "world_meta", meta, 1, 1)
		_apply_world_meta(meta)
	return ok


func load_world_state() -> Dictionary:
	var wrapped: Dictionary = await read_storage("saves", "world_state")
	if wrapped.is_empty() or bool(wrapped.get("empty", false)):
		return {}
	return SaveGame.decompress_json(String(wrapped.get("gz", "")))


## Loads account's `player_profile` and (if server/host) `world_state` into the active world.
func load_cloud_into(tree: SceneTree, resume: bool = true) -> bool:
	if not is_logged_in() or tree.get_first_node_in_group("sandbox") != null:
		return false
	var player: Player = SaveGame._local_player(tree)
	if player == null:
		return false
	var pdata: Dictionary = await load_player_profile()
	if not pdata.is_empty():
		SaveGame.import_player_data(player, pdata, tree.root.multiplayer.is_server())
	if tree.root.multiplayer.is_server():
		var wdata: Dictionary = await load_world_state()
		if wdata.is_empty():
			return false
		return SaveGame.import_world_data(tree, wdata, player, resume)
	return not pdata.is_empty()


## Saves local player's profile and (if server/host) the world state to Nakama.
func save_cloud_all(tree: SceneTree) -> bool:
	if not is_logged_in() or tree.get_first_node_in_group("sandbox") != null:
		return false
	var player: Player = null
	for node: Node in tree.get_nodes_in_group("players"):
		if node.is_multiplayer_authority():
			player = node as Player
			break
	if player == null:
		return false
	var ok_player: bool = await save_player_profile(SaveGame.export_player_data(player))
	if not ok_player:
		return false
	if tree.root.multiplayer.is_server():
		return await save_world_state(SaveGame.export_world_data(tree))
	return true


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

	var deadline_ms: int = Time.get_ticks_msec() + 10000
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
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		var cfg: Dictionary = parsed as Dictionary
		server_url = String(cfg.get("server_url", server_url))
		server_key = String(cfg.get("server_key", server_key))


func _read_cmdline_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg: String in all_args:
		if arg.begins_with("--nakama-url="):
			server_url = arg.substr("--nakama-url=".length())
		elif arg.begins_with("--nakama-token="):
			_apply_session_tokens(arg.substr("--nakama-token=".length()), "")
		elif arg.begins_with("--nakama-refresh="):
			refresh_token = arg.substr("--nakama-refresh=".length())


func _save_session() -> void:
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
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if parsed is Dictionary:
		var data: Dictionary = parsed as Dictionary
		refresh_token = String(data.get("refresh_token", ""))
		user_id = String(data.get("user_id", ""))
		uid = String(data.get("uid", ""))
