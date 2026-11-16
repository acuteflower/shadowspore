class_name NakamaRelayPeer
extends MultiplayerPeerExtension
## Nakama Realtime WebSocket relay implementing Godot's `MultiplayerPeerExtension`.
## Transports all RPCs and `MultiplayerSynchronizer`/`MultiplayerSpawner` packets via an
## authoritative Nakama match (`coop_relay.lua`) without router port-forwarding or NAT issues.

const OP_PACKET_RELIABLE: int = 1
const OP_PACKET_UNRELIABLE: int = 2
const OP_CONTROL: int = 10
const MAX_PACKET_SIZE: int = 1048576
const MAX_INCOMING_QUEUE: int = 8192
const WS_BUFFER_BYTES: int = 2097152

signal join_mode_changed(new_mode: String)

var match_id: String = ""
var room_code: String = ""
var last_error: String = ""

var _ws: WebSocketPeer = WebSocketPeer.new()
var _is_host: bool = false
var _unique_id: int = 0
var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
var _transfer_channel: int = 0
var _transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _target_peer: int = 0
var _refuse_new: bool = false
var _join_sent: bool = false
var _cid: int = 0
var _peers: Dictionary = {} ## peer_id -> {"peer_id": int, "user_id": String, "uid": String, "username": String, "display_name": String}
var _incoming: Array[Dictionary] = []


static func build_ws_url(base_http_url: String, jwt_token: String) -> String:
	var clean: String = base_http_url.strip_edges().trim_suffix("/")
	var ws_base: String = clean
	if clean.begins_with("https://"):
		ws_base = "wss://" + clean.substr("https://".length())
	elif clean.begins_with("http://"):
		ws_base = "ws://" + clean.substr("http://".length())
	return "%s/ws?lang=en&status=true&format=json&token=%s" % [ws_base, jwt_token.uri_encode()]


func start_host(base_http_url: String, jwt_token: String, target_match_id: String, code: String = "") -> Error:
	_close()
	_is_host = true
	_unique_id = 1
	return _connect_relay(base_http_url, jwt_token, target_match_id, code)


func start_client(base_http_url: String, jwt_token: String, target_match_id: String, code: String = "") -> Error:
	_close()
	_is_host = false
	_unique_id = 0
	return _connect_relay(base_http_url, jwt_token, target_match_id, code)


func get_peer_meta(peer_id: int) -> Dictionary:
	var info: Variant = _peers.get(peer_id, {})
	return (info as Dictionary).duplicate() if info is Dictionary else {}


func send_control_join_mode(new_mode: String) -> void:
	if _is_host and _status == MultiplayerPeer.CONNECTION_CONNECTED:
		_send_match_data(OP_CONTROL, JSON.stringify({"type": "set_join_mode", "join_mode": new_mode}).to_utf8_buffer())


func send_control_room_code(new_code: String) -> void:
	room_code = new_code
	if _is_host and _status == MultiplayerPeer.CONNECTION_CONNECTED:
		_send_match_data(OP_CONTROL, JSON.stringify({"type": "set_room_code", "room_code": new_code}).to_utf8_buffer())


func _connect_relay(base_http_url: String, jwt_token: String, target_match_id: String, code: String) -> Error:
	if jwt_token.is_empty() or target_match_id.is_empty():
		last_error = "RELAY-TOKEN ODER MATCH-ID FEHLT"
		return ERR_INVALID_PARAMETER
	match_id = target_match_id
	room_code = code
	last_error = ""
	_join_sent = false
	_cid = 0
	_peers.clear()
	_incoming.clear()
	_ws = WebSocketPeer.new()
	_ws.outbound_buffer_size = WS_BUFFER_BYTES
	_ws.inbound_buffer_size = WS_BUFFER_BYTES
	_ws.max_queued_packets = 4096
	var url: String = build_ws_url(base_http_url, jwt_token)
	var err: Error = _ws.connect_to_url(url)
	if err != OK:
		last_error = "WEBSOCKET-VERBINDUNG FEHLGESCHLAGEN"
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return err
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var pkt: Dictionary = _incoming.pop_front()
	return pkt.get("data", PackedByteArray()) as PackedByteArray


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED or _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	if p_buffer.size() > MAX_PACKET_SIZE:
		return ERR_INVALID_PARAMETER
	var frame := PackedByteArray()
	frame.resize(5 + p_buffer.size())
	frame.encode_s32(0, _target_peer)
	frame[4] = _transfer_channel & 0xFF
	for i: int in p_buffer.size():
		frame[5 + i] = p_buffer[i]
	var reliable: bool = _transfer_mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return _send_match_data(OP_PACKET_RELIABLE if reliable else OP_PACKET_UNRELIABLE, frame)


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return MAX_PACKET_SIZE


func _get_packet_channel() -> int:
	if _incoming.is_empty():
		return 0
	return int(_incoming[0].get("channel", 0))


func _get_packet_mode() -> TransferMode:
	if _incoming.is_empty():
		return _transfer_mode
	return int(_incoming[0].get("mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)) as TransferMode


func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = clampi(p_channel, 0, 255)


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(p_mode: TransferMode) -> void:
	_transfer_mode = p_mode


func _get_transfer_mode() -> TransferMode:
	return _transfer_mode


func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _get_packet_peer() -> int:
	if _incoming.is_empty():
		return 0
	return int(_incoming[0].get("peer", 0))


func _is_server() -> bool:
	return _is_host and _status == MultiplayerPeer.CONNECTION_CONNECTED


func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	var state: WebSocketPeer.State = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _join_sent:
			_send_match_join()
		while _ws.get_available_packet_count() > 0:
			var pkt_bytes: PackedByteArray = _ws.get_packet()
			if pkt_bytes.is_empty():
				continue
			_handle_ws_text(pkt_bytes.get_string_from_utf8())
			if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
				return
	elif state == WebSocketPeer.STATE_CLOSED:
		if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
			if last_error.is_empty():
				var reason: String = _ws.get_close_reason()
				last_error = reason if not reason.is_empty() else "RELAY-VERBINDUNG GESCHLOSSEN"
			_close()


func _close() -> void:
	var prev_status: MultiplayerPeer.ConnectionStatus = _status
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and _join_sent and not match_id.is_empty():
		if _is_host:
			_send_match_data(OP_CONTROL, JSON.stringify({"type": "close"}).to_utf8_buffer())
		else:
			_send_json({"cid": _next_cid(), "match_leave": {"match_id": match_id}})
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_join_sent = false
	var old_peers: Array = _peers.keys()
	_peers.clear()
	_incoming.clear()
	if prev_status == MultiplayerPeer.CONNECTION_CONNECTED:
		for pid: Variant in old_peers:
			var id_num: int = int(pid)
			if id_num != _unique_id:
				peer_disconnected.emit(id_num)


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if not _is_host or p_peer <= 1:
		return
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_match_data(OP_CONTROL, JSON.stringify({"type": "kick", "target_peer_id": p_peer}).to_utf8_buffer())
	if _peers.has(p_peer):
		_peers.erase(p_peer)
		peer_disconnected.emit(p_peer)


func _get_unique_id() -> int:
	return _unique_id


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse_new = p_enable


func _is_refusing_new_connections() -> bool:
	return _refuse_new


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> ConnectionStatus:
	return _status


func _next_cid() -> String:
	_cid += 1
	return str(_cid)


func _send_json(obj: Dictionary) -> Error:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	return _ws.send_text(JSON.stringify(obj))


func _send_match_join() -> void:
	_join_sent = true
	var payload: Dictionary = {
		"cid": _next_cid(),
		"match_join": {
			"match_id": match_id,
			"metadata": {
				"room_code": room_code,
			},
		},
	}
	_send_json(payload)


func _send_match_data(op_code: int, raw_bytes: PackedByteArray) -> Error:
	return _send_json({
		"match_data_send": {
			"match_id": match_id,
			"op_code": op_code,
			"data": Marshalls.raw_to_base64(raw_bytes),
		},
	})


func _handle_ws_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var env: Dictionary = parsed as Dictionary
	if env.has("error"):
		var err_dict: Dictionary = SaveGame.as_dict(env.get("error"))
		last_error = String(err_dict.get("message", "RELAY FEHLER"))
		_close()
		return
	if not env.has("match_data"):
		return
	var md: Dictionary = SaveGame.as_dict(env.get("match_data"))
	if md.is_empty():
		return
	var op: int = int(md.get("op_code", 0))
	var raw: PackedByteArray = Marshalls.base64_to_raw(String(md.get("data", "")))
	if op == OP_CONTROL:
		_handle_control(raw.get_string_from_utf8())
	elif op == OP_PACKET_RELIABLE or op == OP_PACKET_UNRELIABLE:
		if raw.size() < 6 or raw.size() > MAX_PACKET_SIZE + 5:
			return
		if _incoming.size() >= MAX_INCOMING_QUEUE:
			return
		var sender_peer: int = raw.decode_s32(0)
		var ch: int = int(raw[4])
		var payload: PackedByteArray = raw.slice(5)
		var mode: TransferMode = TRANSFER_MODE_RELIABLE if op == OP_PACKET_RELIABLE else TRANSFER_MODE_UNRELIABLE
		_incoming.append({
			"peer": sender_peer,
			"channel": ch,
			"mode": mode,
			"data": payload,
		})


func _handle_control(json_text: String) -> void:
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return
	var ctrl: Dictionary = parsed as Dictionary
	var kind: String = String(ctrl.get("type", ""))
	match kind:
		"welcome":
			var assigned: int = int(ctrl.get("self_peer_id", 1 if _is_host else 0))
			if assigned <= 0:
				last_error = "UNGÜLTIGE RELAY-PEER-ID"
				_close()
				return
			_unique_id = assigned
			var initial_remote: Array[int] = []
			for raw_p: Variant in SaveGame.as_array(ctrl.get("peers")):
				if raw_p is Dictionary:
					var pd: Dictionary = raw_p as Dictionary
					var pid: int = int(pd.get("peer_id", 0))
					if pid > 0:
						_peers[pid] = pd
						if pid != _unique_id:
							initial_remote.append(pid)
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			for pid: int in initial_remote:
				peer_connected.emit(pid)
		"peer_joined":
			var pd: Dictionary = SaveGame.as_dict(ctrl.get("peer"))
			var pid: int = int(pd.get("peer_id", 0))
			if pid > 0 and pid != _unique_id:
				var already: bool = _peers.has(pid)
				_peers[pid] = pd
				if not already:
					peer_connected.emit(pid)
		"peer_left":
			var pid: int = int(ctrl.get("peer_id", 0))
			var reason: String = String(ctrl.get("reason", ""))
			if _peers.has(pid):
				_peers.erase(pid)
				peer_disconnected.emit(pid)
			if not _is_host and pid == 1:
				last_error = "DU WURDEST VOM HOST ENTFERNT" if reason == "kicked" else "VERBINDUNG ZUM HOST VERLOREN"
				_close()
		"kicked":
			var kick_reason: String = String(ctrl.get("reason", "kicked"))
			match kick_reason:
				"kicked_admin":
					last_error = "VOM ADMIN AUS DER WELT ENTFERNT"
				"banned":
					last_error = "DEIN KONTO WURDE GESPERRT"
				"closed", "host_closed":
					last_error = "WELT VOM HOST GESCHLOSSEN"
				_:
					last_error = "DU WURDEST VOM HOST ENTFERNT"
			_close()
		"mode_changed":
			join_mode_changed.emit(String(ctrl.get("join_mode", "ask")))
