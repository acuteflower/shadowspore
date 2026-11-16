extends Node
## Host-authoritative ENet. Singleplayer is a local host with one player.
## Supports room codes, world-scoped saves, host IP discovery, live player roster sync, and ping.

const DEFAULT_PORT: int = 7777
const RelayPeer: GDScript = preload("res://src/autoload/nakama_relay_peer.gd")
const MAX_PLAYERS: int = 4
const IDENTITY_PATH: String = "user://coop_identity.key"
const IDENTITY_BYTES: int = 32
const PROTOCOL_VERSION: int = 1
const PING_INTERVAL: float = 2.5
const HEARTBEAT_INTERVAL: float = 25.0

signal peer_joined(id: int)
signal peer_left(id: int)
signal peer_identity_verified(id: int)
signal session_changed()
signal join_rejected(reason: String)

var transport_mode: String = "offline" ## "offline" | "enet" | "relay"
var active_world_id: String = ""
var active_world_name: String = "KOOP-WELT"
var active_room_code: String = ""
var active_match_id: String = ""
var active_join_mode: String = "ask"
var active_save_path: String = ""
var active_port: int = DEFAULT_PORT
var active_max_players: int = MAX_PLAYERS
var last_join_error: String = ""
var last_ping_ms: int = 0

var _guest_owners: Dictionary = {} ## peer -> durable, host-only board owner
var _identity: PackedByteArray
var _peer_nonces: Dictionary = {} ## server-side peer -> auth challenge nonce
var _peer_names: Dictionary = {} ## server-side peer -> display name
var _peer_slots: Dictionary = {} ## server-side peer -> color slot (0..3)
var _peer_user_ids: Dictionary = {} ## peer -> verified Nakama user_id (if available)
var _peer_uids: Dictionary = {} ## peer -> Nakama UID (if available)
var _peer_roles: Dictionary = {} ## server-verified role per peer ("player", "tester", "moderator", "admin")
var _peer_tickets: Dictionary = {} ## server-side peer -> pending ENet identity ticket
var _pending_ticket: Dictionary = {} ## guest pre-fetched ticket {"ticket", "user_id", "uid", "display_name"}
var _roster: Array[Dictionary] = [] ## synced list of {"id": int, "name": String, "is_host": bool, "slot": int, "uid": String}
var _pending_join_code: String = ""
var _pending_enet_addr: String = ""
var _pending_enet_port: int = DEFAULT_PORT
var _last_join_address: String = ""
var _last_join_port: int = DEFAULT_PORT
var _client_saw_challenge: bool = false
var _recent_recorded: bool = false
var _ping_timer: float = 0.0
var _heartbeat_timer: float = 0.0
var _session_is_guest: bool = false
var _handling_server_disconnect: bool = false
var explicit_coop_hud: bool = false


## Client placeholder peer while WorldLevel runs stepped init: keeps `multiplayer.is_server() == false`
## and `rpc_ready == false` without opening sockets before child nodes exist.
class _PendingClientPeer extends MultiplayerPeerExtension:
	var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_CONNECTING
	var _transfer_channel: int = 0
	var _transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()

	func _put_packet_script(_p_buffer: PackedByteArray) -> Error:
		return ERR_UNCONFIGURED

	func _get_available_packet_count() -> int:
		return 0

	func _get_max_packet_size() -> int:
		return 1024

	func _get_packet_channel() -> int:
		return 0

	func _get_packet_mode() -> TransferMode:
		return _transfer_mode

	func _set_transfer_channel(p_channel: int) -> void:
		_transfer_channel = clampi(p_channel, 0, 255)

	func _get_transfer_channel() -> int:
		return _transfer_channel

	func _set_transfer_mode(p_mode: TransferMode) -> void:
		_transfer_mode = p_mode

	func _get_transfer_mode() -> TransferMode:
		return _transfer_mode

	func _set_target_peer(_p_peer: int) -> void:
		pass

	func _get_packet_peer() -> int:
		return 0

	func _is_server() -> bool:
		return false

	func _poll() -> void:
		pass

	func _close() -> void:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED

	func _disconnect_peer(_p_peer: int, _p_force: bool) -> void:
		pass

	func _get_unique_id() -> int:
		return 0

	func _set_refuse_new_connections(_p_enable: bool) -> void:
		pass

	func _is_refusing_new_connections() -> bool:
		return false

	func _is_server_relay_supported() -> bool:
		return true

	func _get_connection_status() -> ConnectionStatus:
		return _status


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	api.auth_timeout = 20.0 ## a guest can still be loading the world when the host asks for their identity
	api.peer_authenticating.connect(_on_authenticating)
	api.peer_authentication_failed.connect(_on_auth_failed)


func _process(delta: float) -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if is_coop_session() and (peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED):
		if _handling_server_disconnect or GameLauncher.is_join_handshake_active() or GameLauncher.is_transitioning():
			return
		var relay_peer: RelayPeer = peer as RelayPeer
		var forced_reason: String = relay_peer.forced_disconnect_reason if relay_peer != null else ""
		var err_reason: String = relay_peer.last_error if relay_peer != null and not relay_peer.last_error.is_empty() else last_join_error
		var allow_save: bool = forced_reason != "DEIN KONTO WURDE GESPERRT"
		if is_local_coop_guest():
			_force_return_to_menu(err_reason, false, allow_save)
			return
		if not forced_reason.is_empty():
			_force_return_to_menu(forced_reason, true, allow_save)
			return
		last_join_error = err_reason
		leave(false)
		return
	if not is_multiplayer_session():
		return
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.is_server():
		if transport_mode == "relay" and CloudSession.is_logged_in():
			_heartbeat_timer += delta
			if _heartbeat_timer >= HEARTBEAT_INTERVAL:
				_heartbeat_timer = 0.0
				CloudSession.coop_heartbeat(active_world_name, 1 + multiplayer.get_peers().size())
		return
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		if rpc_ready(self):
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


## True when `node` is in the scene tree and has a connected MultiplayerPeer ready for RPCs.
static func rpc_ready(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var peer: MultiplayerPeer = node.multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_coop_session() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer is ENetMultiplayerPeer or peer is RelayPeer or peer is _PendingClientPeer


func is_offline() -> bool:
	return not is_coop_session()


func is_relay_session() -> bool:
	return multiplayer.multiplayer_peer is RelayPeer and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_multiplayer_session() -> bool:
	return is_coop_session() and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func peer_user_id(peer: int) -> String:
	return String(_peer_user_ids.get(peer, ""))


func peer_uid(peer: int) -> String:
	return String(_peer_uids.get(peer, ""))


func peer_ticket(peer: int) -> String:
	return String(_peer_tickets.get(peer, ""))


func peer_role(peer: int) -> String:
	if peer == 1:
		return CloudSession.role if CloudSession.is_logged_in() else "player"
	return String(_peer_roles.get(peer, "player"))


func is_peer_admin(peer: int) -> bool:
	return peer_role(peer) == "admin"


func set_pending_ticket(ticket_data: Dictionary) -> void:
	_pending_ticket = ticket_data.duplicate()


func set_active_join_mode(mode: String) -> void:
	active_join_mode = mode
	if multiplayer.is_server() and multiplayer.multiplayer_peer is RelayPeer:
		(multiplayer.multiplayer_peer as RelayPeer).send_control_join_mode(mode)
	session_changed.emit()


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


func is_local_coop_guest() -> bool:
	return _session_is_guest or (is_coop_session() and not multiplayer.is_server())


func kick_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 1:
		return
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	api.disconnect_peer(peer_id)
	CloudSession.mark_save_dirty()


func set_room_code(raw_code: String) -> String:
	if not multiplayer.is_server():
		return active_room_code
	var next_code: String = MultiplayerWorlds.normalize_code(raw_code)
	if next_code.length() < 4:
		next_code = MultiplayerWorlds.generate_code()
	active_room_code = next_code
	if not active_world_id.is_empty():
		MultiplayerWorlds.update_world(active_world_id, {"code": active_room_code})
	if multiplayer.multiplayer_peer is RelayPeer:
		(multiplayer.multiplayer_peer as RelayPeer).send_control_room_code(active_room_code)
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
	elif rpc_ready(self):
		_rpc_update_name.rpc_id(1, next_name)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and multiplayer.multiplayer_peer is RelayPeer:
		var relay: RelayPeer = multiplayer.multiplayer_peer as RelayPeer
		var meta: Dictionary = relay.get_peer_meta(id)
		var n_user_id: String = String(meta.get("user_id", ""))
		var n_uid: String = String(meta.get("uid", ""))
		var disp: String = String(meta.get("display_name", meta.get("username", "SPIELER %d" % id)))
		if not n_uid.is_empty():
			_guest_owners[id] = "nakama:" + n_uid
		elif not n_user_id.is_empty():
			_guest_owners[id] = "nakama_id:" + n_user_id
		if not n_user_id.is_empty():
			_peer_user_ids[id] = n_user_id
		if not n_uid.is_empty():
			_peer_uids[id] = n_uid
		_peer_roles[id] = CloudSession.normalize_role(String(meta.get("role", "player")))
		_peer_names[id] = MultiplayerWorlds.sanitize_name(disp, "SPIELER %d" % id)
	if multiplayer.is_server() and is_multiplayer_session():
		_rebuild_roster()
		_broadcast_session()
		CloudSession.mark_save_dirty()
		if transport_mode == "relay" and CloudSession.is_logged_in():
			CloudSession.coop_heartbeat(active_world_name, 1 + multiplayer.get_peers().size())
	peer_joined.emit(id)
	session_changed.emit()


func _on_peer_left(id: int) -> void:
	peer_left.emit(id) ## the world can store the departing player's state while the binding is still known
	_guest_owners.erase(id)
	_peer_nonces.erase(id)
	_peer_names.erase(id)
	_peer_slots.erase(id)
	_peer_user_ids.erase(id)
	_peer_uids.erase(id)
	_peer_roles.erase(id)
	_peer_tickets.erase(id)
	if multiplayer.is_server() and is_multiplayer_session():
		_rebuild_roster()
		_broadcast_session()
		CloudSession.mark_save_dirty()
		if transport_mode == "relay" and CloudSession.is_logged_in():
			CloudSession.coop_heartbeat(active_world_name, 1 + multiplayer.get_peers().size())
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
	var was_guest: bool = is_local_coop_guest()
	var relay_peer: RelayPeer = multiplayer.multiplayer_peer as RelayPeer
	var relay_err: String = relay_peer.last_error if relay_peer != null else ""
	var forced_reason: String = relay_peer.forced_disconnect_reason if relay_peer != null else ""
	last_join_error = relay_err if not relay_err.is_empty() else "VERBINDUNG ZUM HOST VERLOREN"
	join_rejected.emit(last_join_error)
	session_changed.emit()
	if was_guest:
		_force_return_to_menu(last_join_error, false, forced_reason != "DEIN KONTO WURDE GESPERRT")


func _force_return_to_menu(reason: String, include_world_save: bool, allow_cloud_save: bool) -> void:
	if _handling_server_disconnect or GameLauncher.is_join_handshake_active() or GameLauncher.is_transitioning():
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.get_first_node_in_group("sandbox") != null:
		return
	var world: Node = tree.get_first_node_in_group("world")
	if world == null or not is_instance_valid(world):
		return
	_handling_server_disconnect = true
	var saved_ok: bool = false
	if allow_cloud_save and CloudSession.is_logged_in() and not CloudSession.banned and not GameGuard.locked:
		var force_srv: int = 1 if include_world_save else 0
		if CloudSession.capture_live_snapshot(tree, include_world_save, force_srv):
			saved_ok = await CloudSession.flush_cloud_save_now(tree, CloudSession.QUIT_FLUSH_TIMEOUT_MSEC)
	if not is_instance_valid(tree):
		_handling_server_disconnect = false
		return
	leave(false)
	var banner: String = reason if not reason.is_empty() else "VERBINDUNG ZUM HOST VERLOREN"
	if saved_ok:
		banner += " · WELT GESICHERT" if include_world_save else " · CHARAKTER GESICHERT"
	GameLauncher.menu_return = {"page": "main", "error": banner}
	GameLauncher.launch(tree, {"to_menu": true, "skip_autosave": true})
	_handling_server_disconnect = false


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
		var n_uid: String = String(msg.get("nakama_uid", ""))
		var n_user: String = String(msg.get("nakama_user_id", ""))
		var n_ticket: String = String(msg.get("nakama_ticket", ""))
		if not n_ticket.is_empty() and not n_user.is_empty():
			_peer_tickets[id] = n_ticket
			_verify_enet_identity(id, n_user, n_uid, n_ticket)
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
		if not _pending_ticket.is_empty():
			reply["nakama_ticket"] = String(_pending_ticket.get("ticket", ""))
			reply["nakama_user_id"] = String(_pending_ticket.get("user_id", ""))
			reply["nakama_uid"] = String(_pending_ticket.get("uid", ""))
		if api.send_auth(id, JSON.stringify(reply).to_utf8_buffer()) != OK:
			api.disconnect_peer(id)
			return
	api.complete_auth(id)


func _verify_enet_identity(peer_id: int, claimed_user_id: String, claimed_uid: String, ticket: String) -> void:
	if not CloudSession.is_logged_in():
		return
	var res: Dictionary = await CloudSession.coop_verify_ticket(claimed_user_id, ticket)
	if not bool(res.get("ok", false)) or not bool(res.get("valid", false)):
		return
	if not is_multiplayer_session() or not multiplayer.is_server():
		return
	if not _guest_owners.has(peer_id):
		return
	var verified_uid: String = String(res.get("uid", claimed_uid))
	_peer_user_ids[peer_id] = claimed_user_id
	_peer_uids[peer_id] = verified_uid
	_peer_roles[peer_id] = CloudSession.normalize_role(String(res.get("role", "player")))
	_guest_owners[peer_id] = "nakama:" + verified_uid if not verified_uid.is_empty() else ("nakama_id:" + claimed_user_id)
	var dname: String = String(res.get("display_name", ""))
	if not dname.is_empty():
		_peer_names[peer_id] = MultiplayerWorlds.sanitize_name(dname, String(_peer_names.get(peer_id, "SPIELER")))
	_rebuild_roster()
	_broadcast_session()
	peer_identity_verified.emit(peer_id)
	session_changed.emit()


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
	_clear_session()
	transport_mode = "enet"
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
		_peer_user_ids[1] = CloudSession.user_id
		_peer_uids[1] = CloudSession.uid
		_rebuild_roster()
		session_changed.emit()
	else:
		_clear_session()
	return err


func host_relay(
	match_id: String,
	code: String = "",
	max_players: int = MAX_PLAYERS,
	world_name: String = "KOOP-WELT",
	join_mode: String = "ask",
	world_id: String = "",
	save_path: String = ""
) -> Error:
	if match_id.is_empty() or not CloudSession.is_logged_in():
		last_join_error = "NICHT EINGELOGGT ODER KEINE MATCH-ID"
		return ERR_UNAUTHORIZED
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	_clear_session()
	var clean_max: int = clampi(max_players, 2, MAX_PLAYERS)
	transport_mode = "relay"
	active_match_id = match_id
	active_room_code = MultiplayerWorlds.normalize_code(code)
	active_world_id = world_id
	active_world_name = MultiplayerWorlds.sanitize_name(world_name, "KOOP-WELT")
	active_join_mode = join_mode
	active_save_path = save_path
	active_max_players = clean_max
	last_join_error = ""
	var peer: RelayPeer = RelayPeer.new() as RelayPeer
	var err: Error = peer.start_host(CloudSession.server_url, CloudSession.token, match_id, active_room_code)
	if err == OK:
		(multiplayer as SceneMultiplayer).auth_callback = Callable()
		multiplayer.multiplayer_peer = peer
		_peer_names[1] = _local_player_name()
		_peer_user_ids[1] = CloudSession.user_id
		_peer_uids[1] = CloudSession.uid
		_rebuild_roster()
		session_changed.emit()
	else:
		last_join_error = peer.last_error
		_clear_session()
	return err


func join(address: String, port: int = DEFAULT_PORT, code: String = "", defer_connect: bool = false) -> Error:
	var parsed: Dictionary = MultiplayerWorlds.parse_address_port(address, port)
	var clean_addr: String = String(parsed.get("address", "127.0.0.1"))
	var clean_port: int = int(parsed.get("port", port))
	_clear_session()
	transport_mode = "enet"
	_pending_join_code = MultiplayerWorlds.normalize_code(code)
	_pending_enet_addr = clean_addr
	_pending_enet_port = clean_port
	_last_join_address = clean_addr
	_last_join_port = clean_port
	active_room_code = _pending_join_code
	active_port = clean_port
	_client_saw_challenge = false
	_recent_recorded = false
	last_join_error = ""
	if defer_connect:
		_session_is_guest = true
		_guest_owners.clear()
		(multiplayer as SceneMultiplayer).auth_callback = _authenticate
		multiplayer.multiplayer_peer = _PendingClientPeer.new()
		session_changed.emit()
		return OK
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(clean_addr, clean_port)
	if err == OK:
		_session_is_guest = true
		_guest_owners.clear()
		(multiplayer as SceneMultiplayer).auth_callback = _authenticate
		multiplayer.multiplayer_peer = peer
		session_changed.emit()
	else:
		last_join_error = "UNGÜLTIGE ADRESSE ODER PORT"
	return err


func join_relay(match_id: String, code: String = "", world_name: String = "KOOP-WELT", defer_connect: bool = false) -> Error:
	if match_id.is_empty() or not CloudSession.is_logged_in():
		last_join_error = "NICHT EINGELOGGT ODER KEINE MATCH-ID"
		return ERR_UNAUTHORIZED
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	_clear_session()
	transport_mode = "relay"
	active_match_id = match_id
	active_room_code = MultiplayerWorlds.normalize_code(code)
	active_world_name = MultiplayerWorlds.sanitize_name(world_name, "KOOP-WELT")
	last_join_error = ""
	var peer: RelayPeer = RelayPeer.new() as RelayPeer
	var err: Error = peer.start_client(CloudSession.server_url, CloudSession.token, match_id, active_room_code, defer_connect)
	if err == OK:
		_session_is_guest = true
		(multiplayer as SceneMultiplayer).auth_callback = Callable()
		multiplayer.multiplayer_peer = peer
		session_changed.emit()
	else:
		last_join_error = peer.last_error
		_clear_session()
	return err


func connect_pending_guest() -> Error:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer is RelayPeer:
		var relay: RelayPeer = peer as RelayPeer
		var rerr: Error = relay.begin_connect()
		if rerr != OK:
			last_join_error = relay.last_error if not relay.last_error.is_empty() else "RELAY-VERBINDUNG FEHLGESCHLAGEN"
		return rerr
	if peer is _PendingClientPeer:
		var enet := ENetMultiplayerPeer.new()
		var err: Error = enet.create_client(_pending_enet_addr, _pending_enet_port)
		if err == OK:
			(multiplayer as SceneMultiplayer).auth_callback = _authenticate
			multiplayer.multiplayer_peer = enet
			session_changed.emit()
		else:
			last_join_error = "UNGÜLTIGE ADRESSE ODER PORT"
		return err
	return OK


func leave(close_remote_relay: bool = true) -> void:
	var closing_match_id: String = active_match_id
	if close_remote_relay and transport_mode == "relay" and multiplayer.is_server() and CloudSession.is_logged_in():
		CloudSession.coop_close_world(closing_match_id)
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
	_peer_user_ids.clear()
	_peer_uids.clear()
	_peer_roles.clear()
	_peer_tickets.clear()
	_pending_ticket.clear()
	_roster.clear()
	transport_mode = "offline"
	active_world_id = ""
	active_world_name = "KOOP-WELT"
	active_room_code = ""
	active_match_id = ""
	active_join_mode = "ask"
	active_save_path = ""
	active_port = DEFAULT_PORT
	active_max_players = MAX_PLAYERS
	_pending_join_code = ""
	_pending_enet_addr = ""
	_pending_enet_port = DEFAULT_PORT
	_client_saw_challenge = false
	_recent_recorded = false
	_heartbeat_timer = 0.0
	last_ping_ms = 0
	explicit_coop_hud = false
	_session_is_guest = false


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
			"uid": String(_peer_uids.get(id, "")),
		})


func _broadcast_session() -> void:
	if not multiplayer.is_server() or not is_multiplayer_session() or not rpc_ready(self):
		return
	for p: int in multiplayer.get_peers():
		_rpc_sync_session.rpc_id(p, active_world_name, active_room_code, active_port, active_max_players, _roster, transport_mode, active_join_mode)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_session(world_name: String, room_code: String, host_port: int, max_players: int, synced_roster: Array, mode_name: String = "enet", join_mode_name: String = "ask") -> void:
	if multiplayer.is_server():
		return
	active_world_name = MultiplayerWorlds.sanitize_name(world_name, "KOOP-WELT")
	active_room_code = MultiplayerWorlds.normalize_code(room_code)
	active_port = clampi(host_port, 1024, 65535)
	active_max_players = clampi(max_players, 2, MAX_PLAYERS)
	transport_mode = mode_name
	active_join_mode = join_mode_name
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
	if not multiplayer.is_server() or not rpc_ready(self):
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > 1 and multiplayer.get_peers().has(sender):
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
