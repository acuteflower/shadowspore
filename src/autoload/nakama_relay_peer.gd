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
const FRAG_FLAG: int = 0x80
const FRAG_HEADER_BYTES: int = 8
const FRAG_PAYLOAD_LIMIT: int = 2400 ## Keep WebSocket JSON+base64 frames ~3.3 KB (below Nakama's 4096 B default cap)
const MAX_FRAG_GROUPS: int = 64
const FRAG_TTL_MSEC: int = 30000
const TX_FRAMES_PER_POLL: int = 8 ## Smooth bursty snapshot syncs so Nakama socket.outgoing_queue_size never overflows
const TX_UNRELIABLE_BACKLOG_LIMIT: int = 12

signal join_mode_changed(new_mode: String)

var match_id: String = ""
var room_code: String = ""
var last_error: String = ""
var forced_disconnect_reason: String = ""

var _ws: WebSocketPeer = WebSocketPeer.new()
var _is_host: bool = false
var _unique_id: int = 0
var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
var _transfer_channel: int = 0
var _transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _target_peer: int = 0
var _refuse_new: bool = false
var _join_sent: bool = false
var _deferred_connect: bool = false
var _pending_url: String = ""
var _cid: int = 0
var _next_frag_id: int = 1
var _peers: Dictionary = {} ## peer_id -> {"peer_id": int, "user_id": String, "uid": String, "username": String, "display_name": String}
var _incoming: Array[Dictionary] = []
var _rx_frags: Dictionary = {} ## "<peer>:<msg_id>" -> {"created": int, "total": int, "parts": Dictionary}
var _tx_queue: Array[Dictionary] = [] ## [{"op": int, "bytes": PackedByteArray}]
var _tx_sent_this_tick: int = 0


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
	return _connect_relay(base_http_url, jwt_token, target_match_id, code, false)


func start_client(base_http_url: String, jwt_token: String, target_match_id: String, code: String = "", defer_connect: bool = false) -> Error:
	_close()
	_is_host = false
	_unique_id = 0
	return _connect_relay(base_http_url, jwt_token, target_match_id, code, defer_connect)


func begin_connect() -> Error:
	if not _deferred_connect:
		return OK if _status != MultiplayerPeer.CONNECTION_DISCONNECTED else ERR_UNCONFIGURED
	if _pending_url.is_empty():
		last_error = "WEBSOCKET-URL FEHLT"
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		_deferred_connect = false
		return ERR_INVALID_PARAMETER
	_deferred_connect = false
	var err: Error = _ws.connect_to_url(_pending_url)
	if err != OK:
		last_error = "WEBSOCKET-VERBINDUNG FEHLGESCHLAGEN"
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return err
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK


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


func _connect_relay(base_http_url: String, jwt_token: String, target_match_id: String, code: String, defer_connect: bool = false) -> Error:
	if jwt_token.is_empty() or target_match_id.is_empty():
		last_error = "RELAY-TOKEN ODER MATCH-ID FEHLT"
		return ERR_INVALID_PARAMETER
	match_id = target_match_id
	room_code = code
	last_error = ""
	forced_disconnect_reason = ""
	_join_sent = false
	_deferred_connect = defer_connect
	_cid = 0
	_peers.clear()
	_incoming.clear()
	_rx_frags.clear()
	_tx_queue.clear()
	_tx_sent_this_tick = 0
	_ws = WebSocketPeer.new()
	_ws.outbound_buffer_size = WS_BUFFER_BYTES
	_ws.inbound_buffer_size = WS_BUFFER_BYTES
	_ws.max_queued_packets = 4096
	_pending_url = build_ws_url(base_http_url, jwt_token)
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	if defer_connect:
		return OK
	var err: Error = _ws.connect_to_url(_pending_url)
	if err != OK:
		last_error = "WEBSOCKET-VERBINDUNG FEHLGESCHLAGEN"
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return err
	return OK


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var pkt: Dictionary = _incoming.pop_front()
	return pkt.get("data", PackedByteArray()) as PackedByteArray


func build_outgoing_frames(target_peer: int, channel: int, reliable: bool, p_buffer: PackedByteArray) -> Array[Dictionary]:
	var ch: int = channel & 0x7F
	var out: Array[Dictionary] = []
	if p_buffer.size() <= FRAG_PAYLOAD_LIMIT:
		var frame := PackedByteArray()
		frame.resize(5)
		frame.encode_s32(0, target_peer)
		frame[4] = ch
		frame.append_array(p_buffer)
		out.append({"op": OP_PACKET_RELIABLE if reliable else OP_PACKET_UNRELIABLE, "bytes": frame})
		return out
	var msg_id: int = _next_frag_id
	_next_frag_id = 1 if _next_frag_id >= 0x7FFFFFFF else (_next_frag_id + 1)
	var total: int = ceili(float(p_buffer.size()) / float(FRAG_PAYLOAD_LIMIT))
	var offset: int = 0
	for idx: int in total:
		var end_idx: int = mini(offset + FRAG_PAYLOAD_LIMIT, p_buffer.size())
		var frag := PackedByteArray()
		frag.resize(5 + FRAG_HEADER_BYTES)
		frag.encode_s32(0, target_peer)
		frag[4] = ch | FRAG_FLAG
		frag.encode_u32(5, msg_id)
		frag.encode_u16(9, idx)
		frag.encode_u16(11, total)
		frag.append_array(p_buffer.slice(offset, end_idx))
		out.append({"op": OP_PACKET_RELIABLE, "bytes": frag})
		offset = end_idx
	return out


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED or _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	if p_buffer.size() > MAX_PACKET_SIZE:
		return ERR_INVALID_PARAMETER
	var reliable: bool = _transfer_mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if not reliable and _tx_queue.size() >= TX_UNRELIABLE_BACKLOG_LIMIT:
		return OK
	for item: Dictionary in build_outgoing_frames(_target_peer, _transfer_channel, reliable, p_buffer):
		_tx_queue.append(item)
	return _drain_tx_queue()


func _drain_tx_queue() -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED or _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return OK
	while not _tx_queue.is_empty() and _tx_sent_this_tick < TX_FRAMES_PER_POLL:
		var item: Dictionary = _tx_queue[0]
		var send_err: Error = _send_match_data(int(item["op"]), item["bytes"] as PackedByteArray)
		if send_err != OK:
			return send_err
		_tx_queue.pop_front()
		_tx_sent_this_tick += 1
	return OK


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
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED or _deferred_connect:
		return
	_tx_sent_this_tick = 0
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
		if _status == MultiplayerPeer.CONNECTION_CONNECTED and not _tx_queue.is_empty():
			var before_sent: int = _tx_sent_this_tick
			_drain_tx_queue()
			if _tx_sent_this_tick > before_sent and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				_ws.poll()
	elif state == WebSocketPeer.STATE_CLOSED:
		if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
			if last_error.is_empty():
				var reason: String = _ws.get_close_reason()
				var code: int = _ws.get_close_code()
				var phase: String = " BEIM VERBINDEN" if not _join_sent or _unique_id <= 0 else ""
				push_warning("NakamaRelayPeer WS closed (code=%d reason='%s' connecting=%s)" % [code, reason, str(not phase.is_empty())])
				if not reason.is_empty():
					last_error = reason
				elif code > 0 and code != 1000:
					last_error = "RELAY-VERBINDUNG GESCHLOSSEN%s (CODE %d)" % [phase, code]
				else:
					last_error = "RELAY-VERBINDUNG GESCHLOSSEN%s" % phase
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
	_deferred_connect = false
	_tx_queue.clear()
	_tx_sent_this_tick = 0
	var old_peers: Array = _peers.keys()
	_peers.clear()
	_incoming.clear()
	_rx_frags.clear()
	_tx_queue.clear()
	_tx_sent_this_tick = 0
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
	var b64_data: String = String(md.get("data", ""))
	if b64_data.is_empty():
		return
	var raw: PackedByteArray = Marshalls.base64_to_raw(b64_data)
	if op == OP_CONTROL:
		_handle_control(raw.get_string_from_utf8())
	elif op == OP_PACKET_RELIABLE or op == OP_PACKET_UNRELIABLE:
		if raw.size() < 6 or raw.size() > MAX_PACKET_SIZE + 5 + FRAG_HEADER_BYTES:
			return
		if _incoming.size() >= MAX_INCOMING_QUEUE:
			return
		var sender_peer: int = raw.decode_s32(0)
		var raw_ch: int = int(raw[4])
		var ch: int = raw_ch & 0x7F
		var is_frag: bool = (raw_ch & FRAG_FLAG) != 0
		var mode: TransferMode = TRANSFER_MODE_RELIABLE if op == OP_PACKET_RELIABLE else TRANSFER_MODE_UNRELIABLE
		if is_frag:
			_handle_fragment(sender_peer, ch, mode, raw)
			return
		var payload: PackedByteArray = raw.slice(5)
		_incoming.append({
			"peer": sender_peer,
			"channel": ch,
			"mode": mode,
			"data": payload,
		})


func _prune_stale_frags(now: int) -> void:
	for k: Variant in _rx_frags.keys():
		var g: Dictionary = _rx_frags[k] as Dictionary
		if now - int(g.get("created", 0)) > FRAG_TTL_MSEC:
			_rx_frags.erase(k)
	while _rx_frags.size() >= MAX_FRAG_GROUPS:
		var oldest_k: Variant = null
		var oldest_t: int = now + 1
		for k: Variant in _rx_frags.keys():
			var t: int = int((_rx_frags[k] as Dictionary).get("created", 0))
			if t < oldest_t:
				oldest_t = t
				oldest_k = k
		if oldest_k == null:
			break
		_rx_frags.erase(oldest_k)


func _drop_peer_frags(peer_id: int) -> void:
	for k: Variant in _rx_frags.keys():
		if int((_rx_frags[k] as Dictionary).get("peer", 0)) == peer_id:
			_rx_frags.erase(k)


func _handle_fragment(sender_peer: int, channel: int, mode: TransferMode, raw: PackedByteArray) -> void:
	if raw.size() < 5 + FRAG_HEADER_BYTES + 1:
		return
	var msg_id: int = raw.decode_u32(5)
	var idx: int = raw.decode_u16(9)
	var total: int = raw.decode_u16(11)
	if total < 1 or total > 1024 or idx >= total:
		return
	var now: int = Time.get_ticks_msec()
	var key: String = "%d:%d" % [sender_peer, msg_id]
	var group: Dictionary
	if _rx_frags.has(key):
		group = _rx_frags[key] as Dictionary
		if int(group.get("total", 0)) != total:
			_rx_frags.erase(key)
			return
	else:
		_prune_stale_frags(now)
		group = {
			"peer": sender_peer,
			"created": now,
			"total": total,
			"parts": {},
		}
		_rx_frags[key] = group
	var parts: Dictionary = group["parts"] as Dictionary
	parts[idx] = raw.slice(5 + FRAG_HEADER_BYTES)
	if parts.size() < total:
		return
	_rx_frags.erase(key)
	var assembled := PackedByteArray()
	for i: int in total:
		if not parts.has(i):
			return
		assembled.append_array(parts[i] as PackedByteArray)
	if assembled.is_empty() or assembled.size() > MAX_PACKET_SIZE:
		return
	_incoming.append({
		"peer": sender_peer,
		"channel": channel,
		"mode": mode,
		"data": assembled,
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
			_drop_peer_frags(pid)
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
				"closed":
					last_error = "WELT VOM ADMIN GESCHLOSSEN"
				"host_closed":
					last_error = "WELT VOM HOST GESCHLOSSEN"
				_:
					last_error = "DU WURDEST VOM HOST ENTFERNT"
			forced_disconnect_reason = last_error
			_close()
		"mode_changed":
			join_mode_changed.emit(String(ctrl.get("join_mode", "ask")))
