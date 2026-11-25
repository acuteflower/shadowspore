extends Node
## Shared history. "game" is the Nakama room, "group" is this host's roster.
## A DM key addresses either a cloud account or a peer in the current session.
signal changed()
signal incoming(key: String, author: String)
signal admin_reply(ok: bool, lines: PackedStringArray)
signal system_broadcast(kind: String, text: String)
const ROOM: String = "shadowspore-spiel"
const LIMIT: int = 320
var lines: Array[Dictionary] = []
var contacts: Dictionary = {}
var reply_to: String = ""
var _reply_time: String = ""
var _channels: Dictionary = {}
var _joining: Dictionary = {}
var _requests: Dictionary = {}
var _sequence: int = 0
var _line_sequence: int = 0
var _generation: int = 0
var _account: String = ""
var _session: MultiplayerPeer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CloudSession.realtime_envelope.connect(_envelope)
	CloudSession.realtime_connected.connect(_connected)
	CloudSession.realtime_disconnected.connect(_disconnected)
	CloudSession.auth_changed.connect(_auth_changed)
	NetworkManager.session_changed.connect(_session_changed)


func _session_changed() -> void:
	if multiplayer.multiplayer_peer == _session:
		return
	_session = multiplayer.multiplayer_peer
	lines = lines.filter(func(row: Dictionary) -> bool: return row.key != "group" and not String(row.key).begins_with("peer/"))
	for key: String in contacts.keys():
		if key.begins_with("peer/"):
			contacts.erase(key)
	if reply_to.begins_with("peer/"):
		reply_to = ""
		_reply_time = ""
	changed.emit()


func _auth_changed(_logged_in: bool) -> void:
	if _account == CloudSession.user_id:
		return
	_account = CloudSession.user_id
	_disconnected()
	lines.clear()
	contacts.clear()
	reply_to = ""
	_reply_time = ""
	changed.emit()


func _connected() -> void:
	_auth_changed(true)
	join_channel("game")
	CloudSession.fetch_notifications()
	for key: String in contacts.keys():
		if key.begins_with("dm/"):
			join_channel(key)


func _disconnected() -> void:
	_generation += 1
	_channels.clear()
	_joining.clear()
	_requests.clear()
	changed.emit()


func _request(body: Dictionary) -> Dictionary:
	_sequence += 1
	var cid: String = "chat-%d" % _sequence
	body.cid = cid
	if CloudSession.send_realtime(body) != OK:
		return {}
	var generation: int = _generation
	var deadline: int = Time.get_ticks_msec() + 6000
	_requests[cid] = {}
	while generation == _generation and Time.get_ticks_msec() < deadline:
		var result: Dictionary = _requests.get(cid, {})
		if not result.is_empty():
			_requests.erase(cid)
			return result
		await get_tree().process_frame
	_requests.erase(cid)
	return {}


func join_channel(key: String) -> String:
	if _channels.has(key):
		return String(_channels[key])
	var generation: int = _generation
	if _joining.has(key):
		while generation == _generation and _joining.has(key):
			await get_tree().process_frame
		return String(_channels.get(key, ""))
	_joining[key] = true
	var room: bool = key == "game"
	var result: Dictionary = await _request({"channel_join": {"type": 1 if room else 2, "target": ROOM if room else key.trim_prefix("dm/"), "persistence": true, "hidden": room}})
	if generation != _generation:
		return ""
	_joining.erase(key)
	var channel: String = String(SaveGame.as_dict(result.get("channel")).get("id", ""))
	if not channel.is_empty():
		_channels[key] = channel
		_load_history(key, channel, generation)
	return channel


func _load_history(key: String, channel: String, generation: int) -> void:
	var history: Array = await CloudSession.recent_chat_messages(channel)
	if generation != _generation:
		return
	history.reverse()
	for row: Variant in history:
		if row is Dictionary:
			_cloud_line(key, row, false)


func _envelope(env: Dictionary) -> void:
	var cid: String = String(env.get("cid", ""))
	if _requests.has(cid):
		_requests[cid] = env
	var row: Dictionary = SaveGame.as_dict(env.get("channel_message"))
	if not row.is_empty():
		var key: Variant = _channels.find_key(row.get("channel_id", ""))
		# Nakama can deliver the first message in the same poll as the join reply.
		if key == null:
			var first: String = String(row.get("user_id_one", ""))
			var second: String = String(row.get("user_id_two", ""))
			if String(row.get("room_name", "")) == ROOM:
				key = "game"
			elif not first.is_empty() and not second.is_empty() and CloudSession.user_id in [first, second]:
				key = "dm/" + (second if first == CloudSession.user_id else first)
		if key != null:
			_cloud_line(String(key), row, true)
	handle_invites(SaveGame.as_array(SaveGame.as_dict(env.get("notifications")).get("notifications")))


func handle_invites(items: Array) -> void:
	for item: Variant in items:
		if item is Dictionary and int(item.get("code", 0)) == -1:
			var sender: String = String(item.get("sender_id", ""))
			if not sender.is_empty() and sender != CloudSession.user_id:
				var content: Variant = JSON.parse_string(String(item.get("content", "{}")))
				var key: String = "dm/" + sender
				if content is Dictionary:
					contacts[key] = String(content.get("username", "Spieler"))
				join_channel(key)


func _cloud_line(key: String, row: Dictionary, live: bool) -> void:
	if int(row.get("code", 0)) != 0:
		return
	var payload: Variant = JSON.parse_string(String(row.get("content", "{}")))
	if not payload is Dictionary or not payload.get("text") is String:
		return
	var own: bool = String(row.get("sender_id", "")) == CloudSession.user_id
	var author: String = String(row.get("username", "Spieler"))
	_record(key, author, String(payload.text), own, String(row.get("message_id", "")), String(row.get("create_time", "")), live)


func _record(key: String, author: String, body: String, own: bool, id: String, stamp: String, live: bool) -> void:
	if not id.is_empty():
		for existing: Dictionary in lines:
			if existing.id == id:
				return
	var clean: String = body.strip_escapes().strip_edges().left(LIMIT)
	if clean.is_empty():
		return
	if stamp.is_empty():
		stamp = Time.get_datetime_string_from_system(true) + "Z"
	if key != "game" and key != "group" and not own:
		contacts[key] = author
		if stamp >= _reply_time:
			reply_to = key
			_reply_time = stamp
	_line_sequence += 1
	lines.append({"order": _line_sequence, "key": key, "author": author.left(36), "text": clean, "own": own, "id": id, "stamp": stamp})
	var matching: int = 0
	for i: int in range(lines.size() - 1, -1, -1):
		if lines[i].key == key:
			matching += 1
			if matching > 100:
				lines.remove_at(i)
	changed.emit()
	if live and not own:
		incoming.emit(key, author)


func resolve(query: String) -> Dictionary:
	var matches: Array[Dictionary] = []
	for player: Dictionary in NetworkManager.roster():
		if String(player.name).nocasecmp_to(query) == 0:
			matches.append(player)
	if matches.size() > 1:
		return {"error": "Mehrere Spieler heißen so. Verwende die Konto-UID."}
	if matches.size() == 1:
		var player: Dictionary = matches[0]
		if int(player.id) == multiplayer.get_unique_id():
			return {"error": "Das ist dein eigener Name."}
		var uid: String = String(player.get("uid", ""))
		if uid.is_empty() or not CloudSession.is_logged_in():
			return {"key": "peer/%d" % int(player.id), "name": String(player.name)}
		query = uid
	if not CloudSession.is_logged_in():
		return {"error": "In dieser Gruppe gibt es niemanden mit diesem Namen."}
	var account: String = CloudSession.user_id
	var profile: Dictionary = await CloudSession.find_by_uid(query.trim_prefix("#"))
	if account != CloudSession.user_id or not bool(profile.get("found", false)):
		return {"error": "Spieler nicht gefunden oder Server nicht erreichbar."}
	if String(profile.user_id) == account:
		return {"error": "Das ist dein eigenes Konto."}
	return {"key": "dm/" + String(profile.user_id), "name": String(profile.username)}


func send(key: String, body: String) -> String:
	body = body.strip_escapes().strip_edges()
	if body.is_empty() or body.length() > LIMIT:
		return "Bitte 1 bis %d Zeichen eingeben." % LIMIT
	if key == "group" or key.begins_with("peer/"):
		if not NetworkManager.is_multiplayer_session() or not NetworkManager.rpc_ready(self):
			return "Dafür brauchst du eine aktive Koop-Gruppe."
		var target: int = 0 if key == "group" else int(key.trim_prefix("peer/"))
		if key != "group" and (target <= 0 or not _in_roster(target)):
			return "Der Spieler hat die Gruppe verlassen."
		if multiplayer.is_server():
			_route(1, target, body)
		else:
			_submit.rpc_id(1, target, body)
		return ""
	if not CloudSession.is_logged_in():
		return "Bitte für den Online-Chat anmelden."
	var channel: String = await join_channel(key)
	if channel.is_empty():
		return "Chat-Verbindung nicht verfügbar. Bitte erneut versuchen."
	var ack: Dictionary = await _request({"channel_message_send": {"channel_id": channel, "content": JSON.stringify({"text": body})}})
	if not ack.has("channel_message_ack"):
		return "Senden wurde nicht bestätigt."
	return ""


func _in_roster(id: int) -> bool:
	for player: Dictionary in NetworkManager.roster():
		if int(player.id) == id:
			return true
	return false


@rpc("any_peer", "call_remote", "reliable")
func _submit(target: int, body: String) -> void:
	if multiplayer.is_server():
		_route(multiplayer.get_remote_sender_id(), target, body)


func _route(sender: int, target: int, body: String) -> void:
	if not _in_roster(sender) or (target != 0 and not _in_roster(target)) or body.length() > LIMIT:
		return
	for player: Dictionary in NetworkManager.roster():
		var id: int = int(player.id)
		if target != 0 and id != sender and id != target:
			continue
		if id == 1:
			_receive(sender, target, body)
		else:
			_receive.rpc_id(id, sender, target, body)


@rpc("authority", "call_remote", "reliable")
func _receive(sender: int, target: int, body: String) -> void:
	var own: bool = sender == multiplayer.get_unique_id()
	var key: String = "group" if target == 0 else "peer/%d" % (target if own else sender)
	_record(key, NetworkManager.player_name_for(sender), body, own, "", "", true)


# ------------------------------------------------------------------ Host-authoritative Admin RPC Bridge

## Invoked by GameChat for any recognized admin slash command.
## Runs directly on the Host in singleplayer/host mode, or routes reliably over RPC from an authorized admin guest.
func run_admin_command(raw_line: String) -> Dictionary:
	if not AdminCommands.can_use_local():
		return {"ok": false, "lines": PackedStringArray(["Keine Berechtigung für Admin-Befehle."])}
	if not NetworkManager.is_multiplayer_session() or multiplayer.is_server():
		return AdminCommands.execute_on_server(1, raw_line, get_tree())
	if not NetworkManager.rpc_ready(self):
		return {"ok": false, "lines": PackedStringArray(["Keine aktive Host-Verbindung."])}
	_rpc_admin_exec.rpc_id(1, raw_line)
	return {"ok": true, "pending": true, "lines": PackedStringArray()}


## Host-only: broadcasts an official system / admin message to all connected players in the session.
func broadcast_system(kind: String, text: String) -> void:
	var clean: String = text.strip_escapes().strip_edges().left(LIMIT)
	if clean.is_empty():
		return
	if NetworkManager.is_multiplayer_session() and multiplayer.is_server() and NetworkManager.rpc_ready(self):
		_rpc_system_broadcast.rpc(kind, clean)
	else:
		system_broadcast.emit(kind, clean)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_admin_exec(raw_line: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var res: Dictionary = AdminCommands.execute_on_server(sender, raw_line, get_tree())
	var out_lines: PackedStringArray = res.get("lines", PackedStringArray()) as PackedStringArray
	if sender > 1:
		_rpc_admin_reply.rpc_id(sender, bool(res.get("ok", false)), out_lines)
	else:
		admin_reply.emit(bool(res.get("ok", false)), out_lines)


@rpc("authority", "call_remote", "reliable")
func _rpc_admin_reply(ok: bool, out_lines: PackedStringArray) -> void:
	admin_reply.emit(ok, out_lines)


@rpc("authority", "call_local", "reliable")
func _rpc_system_broadcast(kind: String, text: String) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	system_broadcast.emit(kind, text)
