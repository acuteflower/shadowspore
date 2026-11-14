extends Node
## Host-authoritative ENet. Singleplayer is a local host with one player.
## Supports room codes, world-scoped saves, host IP discovery, live player roster sync, and ping.

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const IDENTITY_PATH: String = "user://coop_identity.key"
const IDENTITY_BYTES: int = 32
const PROTOCOL_VERSION: int = 1
const PING_INTERVAL: float = 2.5

signal peer_joined(id: int)
signal peer_left(id: int)
signal session_changed()
signal join_rejected(reason: String)

var active_world_id: String = ""
var active_world_name: String = "KOOP-WELT"
var active_room_code: String = ""
var active_save_path: String = ""
var active_port: int = DEFAULT_PORT
var active_max_players: int = MAX_PLAYERS
var last_join_error: String = ""
var last_ping_ms: int = 0

var _guest_owners: Dictionary = {} ## ENet peer -> durable, host-only board owner
var _identity: PackedByteArray
var _peer_nonces: Dictionary = {} ## server-side peer -> auth challenge nonce
var _peer_names: Dictionary = {} ## server-side peer -> display name
var _peer_slots: Dictionary = {} ## server-side peer -> color slot (0..3)
var _roster: Array[Dictionary] = [] ## synced list of {"id": int, "name": String, "is_host": bool, "slot": int}
var _pending_join_code: String = ""
var _last_join_address: String = ""
var _last_join_port: int = DEFAULT_PORT
var _client_saw_challenge: bool = false
var _recent_recorded: bool = false
var _ping_timer: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	api.auth_timeout = 20.0 ## a guest can still be loading the world when the host asks for their identity
	api.peer_authenticating.connect(_on_authenticating)
	api.peer_authentication_failed.connect(_on_auth_failed)


func _process(delta: float) -> void:
	if not is_multiplayer_session():
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.is_server():
		return
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_rpc_ping.rpc_id(1, Time.get_ticks_msec())


static func local_ips() -> PackedStringArray:
	var preferred: Array[String] = []
	var other: Array[String] = []
	for raw: String in IP.get_local_addresses():
		var addr: String = raw.strip_edges()
		if addr.is_empty() or ":" in addr or not ("." in addr):
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254.") or addr == "0.0.0.0":
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or _is_private_172(addr):
			if not preferred.has(addr):
				preferred.append(addr)
		elif not other.has(addr):
			other.append(addr)
	var combined: PackedStringArray = PackedStringArray()
	for a: String in preferred:
		combined.append(a)
	for a: String in other:
		combined.append(a)
	if combined.is_empty():
		combined.append("127.0.0.1")
	return combined


static func _is_private_172(addr: String) -> bool:
	if not addr.begins_with("172."):
		return false
	var parts: PackedStringArray = addr.split(".")
	if parts.size() != 4 or not parts[1].is_valid_int():
		return false
	var second: int = parts[1].to_int()
	return second >= 16 and second <= 31


static func primary_ip() -> String:
	return local_ips()[0]


func is_multiplayer_session() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func roster() -> Array[Dictionary]:
	if is_multiplayer_session() and multiplayer.is_server() and _roster.is_empty():
		_rebuild_roster()
	var copy: Array[Dictionary] = []
	for entry: Dictionary in _roster:
		copy.append(entry.duplicate())
	return copy


func player_name_for(peer_id: int) -> String:
	for entry: Dictionary in _roster:
		if int(entry.get("id", 0)) == peer_id:
			return String(entry.get("name", "SPIELER"))
	if peer_id == 1:
		return _local_player_name()
	return "SPIELER"


func player_slot_for(peer_id: int) -> int:
	for entry: Dictionary in _roster:
		if int(entry.get("id", 0)) == peer_id:
			return clampi(int(entry.get("slot", 0)), 0, 3)
	return 0


func guest_owner(peer: int) -> String:
	return String(_guest_owners.get(peer, ""))


func guest_peer(owner: String) -> int:
	var peer: Variant = _guest_owners.find_key(owner)
	return int(peer) if peer != null else 0


func kick_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 1:
		return
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	api.disconnect_peer(peer_id)


func set_room_code(raw_code: String) -> String:
	if not multiplayer.is_server():
		return active_room_code
	var next_code: String = MultiplayerWorlds.normalize_code(raw_code)
	if next_code.length() < 4:
		next_code = MultiplayerWorlds.generate_code()
	active_room_code = next_code
	if not active_world_id.is_empty():
		MultiplayerWorlds.update_world(active_world_id, {"code": active_room_code})
	_broadcast_session()
	session_changed.emit()
	return active_room_code


func refresh_local_name() -> void:
	if not is_multiplayer_session():
		return
	var next_name: String = _local_player_name()
	if multiplayer.is_server():
		_peer_names[1] = next_name
		_rebuild_roster()
		_broadcast_session()
		session_changed.emit()
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_rpc_update_name.rpc_id(1, next_name)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and is_multiplayer_session():
		_rebuild_roster()
		_broadcast_session()
	peer_joined.emit(id)
	session_changed.emit()


func _on_peer_left(id: int) -> void:
	peer_left.emit(id) ## the world can store the departing player's state while the binding is still known
	_guest_owners.erase(id)
	_peer_nonces.erase(id)
	_peer_names.erase(id)
	_peer_slots.erase(id)
	if multiplayer.is_server() and is_multiplayer_session():
		_rebuild_roster()
		_broadcast_session()
	session_changed.emit()


func _on_auth_failed(id: int) -> void:
	_guest_owners.erase(id)
	_peer_nonces.erase(id)
	if id == 1 or id == 0:
		last_join_error = "FALSCHER CODE ODER WELT VOLL" if _client_saw_challenge else "AUTHENTIFIZIERUNG FEHLGESCHLAGEN"
		join_rejected.emit(last_join_error)


func _on_connection_failed() -> void:
	last_join_error = "KEIN HOST UNTER DIESER ADRESSE"
	join_rejected.emit(last_join_error)


func _on_server_disconnected() -> void:
	last_join_error = "VERBINDUNG ZUM HOST VERLOREN"
	join_rejected.emit(last_join_error)
	session_changed.emit()


func _local_identity() -> PackedByteArray:
	if _identity.size() == IDENTITY_BYTES:
		return _identity
	_identity = FileAccess.get_file_as_bytes(IDENTITY_PATH) if FileAccess.file_exists(IDENTITY_PATH) else PackedByteArray()
	if _identity.size() == IDENTITY_BYTES:
		return _identity
	_identity = Crypto.new().generate_random_bytes(IDENTITY_BYTES)
	var file: FileAccess = FileAccess.open(IDENTITY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_buffer(_identity)
	return _identity


func _local_player_name() -> String:
	return MultiplayerWorlds.sanitize_name(String(GameSettings.get_value("player_name")), "ELLIE")


func _on_authenticating(id: int) -> void:
	if multiplayer.is_server():
		var api: SceneMultiplayer = multiplayer as SceneMultiplayer
		var nonce: String = Crypto.new().generate_random_bytes(16).hex_encode()
		_peer_nonces[id] = nonce
		## Scope a guest's credential to this host. The installation's private key stays local.
		var scope_hex: String = ("shadowspore-coop:" + _local_identity().hex_encode()).sha256_text()
		var payload: Dictionary = {
			"v": PROTOCOL_VERSION,
			"scope": scope_hex,
			"nonce": nonce,
			"world_name": active_world_name,
			"requires_code": not active_room_code.is_empty(),
		}
		api.send_auth(id, JSON.stringify(payload).to_utf8_buffer())


func _authenticate(id: int, data: PackedByteArray) -> void:
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	var text: String = data.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		api.disconnect_peer(id)
		return
	var msg: Dictionary = parsed as Dictionary
	if multiplayer.is_server():
		if int(msg.get("v", 0)) != PROTOCOL_VERSION:
			api.disconnect_peer(id)
			return
		var nonce: String = String(_peer_nonces.get(id, ""))
		if nonce.is_empty():
			api.disconnect_peer(id)
			return
		var max_clients: int = clampi(active_max_players - 1, 1, MAX_PLAYERS - 1)
		if _guest_owners.size() >= max_clients and not _guest_owners.has(id):
			api.disconnect_peer(id)
			return
		if not active_room_code.is_empty():
			var expected_proof: String = ("%s:%s" % [active_room_code, nonce]).sha256_text()
			if String(msg.get("code_proof", "")) != expected_proof:
				api.disconnect_peer(id)
				return
		var cred_bytes: PackedByteArray = String(msg.get("credential", "")).hex_decode()
		if cred_bytes.size() != IDENTITY_BYTES:
			api.disconnect_peer(id)
			return
		var owner: String = "guest:" + cred_bytes.hex_encode().sha256_text()
		var current: int = guest_peer(owner)
		if current != 0 and current != id:
			api.disconnect_peer(id)
			return
		_peer_nonces.erase(id)
		_guest_owners[id] = owner
		_peer_names[id] = MultiplayerWorlds.sanitize_name(String(msg.get("name", "SPIELER")), "SPIELER")
	elif id == 1:
		_client_saw_challenge = true
		if int(msg.get("v", 0)) != PROTOCOL_VERSION:
			api.disconnect_peer(id)
			return
		var scope_bytes: PackedByteArray = String(msg.get("scope", "")).hex_decode()
		if scope_bytes.size() != IDENTITY_BYTES:
			api.disconnect_peer(id)
			return
		var nonce: String = String(msg.get("nonce", ""))
		var credential: PackedByteArray = Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _local_identity(), scope_bytes)
		var norm_code: String = MultiplayerWorlds.normalize_code(_pending_join_code)
		var proof: String = ("%s:%s" % [norm_code, nonce]).sha256_text() if bool(msg.get("requires_code", false)) or not norm_code.is_empty() else ""
		var reply: Dictionary = {
			"v": PROTOCOL_VERSION,
			"credential": credential.hex_encode(),
			"code_proof": proof,
			"name": _local_player_name(),
		}
		if api.send_auth(id, JSON.stringify(reply).to_utf8_buffer()) != OK:
			api.disconnect_peer(id)
			return
	api.complete_auth(id)


func host_singleplayer() -> Error:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer and active_world_id.is_empty() and active_save_path.is_empty():
		return OK
	leave()
	return OK


func host_multiplayer(
	port: int = DEFAULT_PORT,
	code: String = "",
	max_players: int = MAX_PLAYERS,
	world_id: String = "",
	world_name: String = "KOOP-WELT",
	save_path: String = ""
) -> Error:
	var clean_max: int = clampi(max_players, 2, MAX_PLAYERS)
	var clean_port: int = clampi(port, 1024, 65535)
	var clean_code: String = MultiplayerWorlds.normalize_code(code)
	active_world_id = world_id
	active_world_name = MultiplayerWorlds.sanitize_name(world_name, "KOOP-WELT")
	active_room_code = clean_code
	active_save_path = save_path
	active_port = clean_port
	active_max_players = clean_max
	last_join_error = ""
	var err: Error = _host(clean_max - 1, "*", clean_port)
	if err == OK:
		_peer_names[1] = _local_player_name()
		_rebuild_roster()
		session_changed.emit()
	else:
		_clear_session()
	return err


func join(address: String, port: int = DEFAULT_PORT, code: String = "") -> Error:
	var parsed: Dictionary = MultiplayerWorlds.parse_address_port(address, port)
	var clean_addr: String = String(parsed.get("address", "127.0.0.1"))
	var clean_port: int = int(parsed.get("port", port))
	_clear_session()
	_pending_join_code = MultiplayerWorlds.normalize_code(code)
	_last_join_address = clean_addr
	_last_join_port = clean_port
	active_room_code = _pending_join_code
	active_port = clean_port
	_client_saw_challenge = false
	_recent_recorded = false
	last_join_error = ""
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(clean_addr, clean_port)
	if err == OK:
		_guest_owners.clear()
		(multiplayer as SceneMultiplayer).auth_callback = _authenticate
		multiplayer.multiplayer_peer = peer
		session_changed.emit()
	else:
		last_join_error = "UNGÜLTIGE ADRESSE ODER PORT"
	return err


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	(multiplayer as SceneMultiplayer).auth_callback = Callable()
	_clear_session()
	session_changed.emit()


func _host(max_clients: int, bind_ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var err: Error = peer.create_server(port, max_clients)
	if err == OK:
		_guest_owners.clear()
		_peer_nonces.clear()
		_peer_names.clear()
		_peer_slots.clear()
		_roster.clear()
		(multiplayer as SceneMultiplayer).auth_callback = _authenticate
		multiplayer.multiplayer_peer = peer
	return err


func _clear_session() -> void:
	_guest_owners.clear()
	_peer_nonces.clear()
	_peer_names.clear()
	_peer_slots.clear()
	_roster.clear()
	active_world_id = ""
	active_world_name = "KOOP-WELT"
	active_room_code = ""
	active_save_path = ""
	active_port = DEFAULT_PORT
	active_max_players = MAX_PLAYERS
	_pending_join_code = ""
	_client_saw_challenge = false
	_recent_recorded = false
	last_ping_ms = 0


func _rebuild_roster() -> void:
	var ids: Array[int] = [1]
	for p: int in multiplayer.get_peers():
		if not ids.has(p):
			ids.append(p)
	ids.sort()
	for id: int in _peer_slots.keys():
		if not ids.has(id):
			_peer_slots.erase(id)
	for id: int in ids:
		if _peer_slots.has(id):
			continue
		for slot: int in 4:
			if not _peer_slots.values().has(slot):
				_peer_slots[id] = slot
				break
	_roster.clear()
	for id: int in ids:
		var fallback: String = _local_player_name() if id == 1 else "SPIELER %d" % id
		var pname: String = String(_peer_names.get(id, fallback))
		_roster.append({
			"id": id,
			"name": pname,
			"is_host": id == 1,
			"slot": int(_peer_slots.get(id, 0)),
		})


func _broadcast_session() -> void:
	if not multiplayer.is_server() or not is_multiplayer_session():
		return
	for p: int in multiplayer.get_peers():
		_rpc_sync_session.rpc_id(p, active_world_name, active_room_code, active_port, active_max_players, _roster)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_session(world_name: String, room_code: String, host_port: int, max_players: int, synced_roster: Array) -> void:
	if multiplayer.is_server():
		return
	active_world_name = MultiplayerWorlds.sanitize_name(world_name, "KOOP-WELT")
	active_room_code = MultiplayerWorlds.normalize_code(room_code)
	active_port = clampi(host_port, 1024, 65535)
	active_max_players = clampi(max_players, 2, MAX_PLAYERS)
	_roster.clear()
	for item: Variant in synced_roster:
		if item is Dictionary:
			_roster.append((item as Dictionary).duplicate())
	if not _recent_recorded and not _last_join_address.is_empty():
		_recent_recorded = true
		MultiplayerWorlds.add_recent_host(_last_join_address, _last_join_port, active_room_code, active_world_name)
	session_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_update_name(raw_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 1:
		return
	_peer_names[sender] = MultiplayerWorlds.sanitize_name(raw_name, "SPIELER")
	_rebuild_roster()
	_broadcast_session()
	session_changed.emit()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_ping(client_msec: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > 1:
		_rpc_pong.rpc_id(sender, client_msec)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_pong(client_msec: int) -> void:
	if multiplayer.is_server():
		return
	var rtt: int = maxi(Time.get_ticks_msec() - client_msec, 0)
	if absi(rtt - last_ping_ms) >= 5 or last_ping_ms == 0:
		last_ping_ms = rtt
		session_changed.emit()
	else:
		last_ping_ms = rtt
