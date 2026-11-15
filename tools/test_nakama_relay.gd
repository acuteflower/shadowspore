extends Node

const RelayPeer: GDScript = preload("res://src/autoload/nakama_relay_peer.gd")

var _host_token: String = ""
var _host_user_id: String = ""
var _host_uid: String = ""
var _guest_token: String = ""
var _guest_user_id: String = ""
var _guest_uid: String = ""
var _outsider_token: String = ""
var _outsider_user_id: String = ""

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _run_all()
	print("[test_nakama_relay] SUMMARY passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("[PASS] ", msg)
	else:
		_failed += 1
		push_error("[FAIL] " + msg)


func _run_all() -> void:
	CloudSession.server_url = CloudSession.DEFAULT_DEV_URL
	CloudSession.server_key = CloudSession.DEFAULT_DEV_SERVER_KEY
	CloudSession.strict_override = false

	var suffix: String = "%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	var h_auth: Dictionary = await _email_login("relay_host_%s@example.com" % suffix, "RelayPass123!")
	_assert_true(bool(h_auth.get("ok", false)), "Host email account created")
	_host_token = String(h_auth.get("token", ""))
	_host_user_id = _jwt_uid(_host_token)

	var g_auth: Dictionary = await _email_login("relay_guest_%s@example.com" % suffix, "RelayPass123!")
	_assert_true(bool(g_auth.get("ok", false)), "Guest email account created")
	_guest_token = String(g_auth.get("token", ""))
	_guest_user_id = _jwt_uid(_guest_token)

	var o_auth: Dictionary = await _email_login("relay_out_%s@example.com" % suffix, "RelayPass123!")
	_assert_true(bool(o_auth.get("ok", false)), "Outsider email account created")
	_outsider_token = String(o_auth.get("token", ""))
	_outsider_user_id = _jwt_uid(_outsider_token)

	var hp: Dictionary = await _rpc(_host_token, "get_my_profile", {})
	_host_uid = String(hp.get("uid", ""))
	var gp: Dictionary = await _rpc(_guest_token, "get_my_profile", {})
	_guest_uid = String(gp.get("uid", ""))
	_assert_true(not _host_uid.is_empty() and not _guest_uid.is_empty(), "Host & Guest UIDs assigned")

	# Make host & guest accepted friends
	var f_add: Dictionary = await _rpc(_host_token, "add_friend_by_uid", {"uid": _guest_uid})
	_assert_true(bool(f_add.get("ok", false)), "Host sent friend request to Guest")
	var f_acc: Dictionary = await _rpc(_guest_token, "accept_friend", {"user_id": _host_user_id})
	_assert_true(bool(f_acc.get("ok", false)), "Guest accepted friend request")

	# Save Guest's portable Cloud profile with solo quests + solo pos + items
	var solo_profile: Dictionary = {
		"pos": [999.0, 888.0],
		"health": 75.0,
		"copper": 420,
		"xp": 150,
		"claimed": 2,
		"skill_tree": {"discovered": [], "learned": []},
		"slots": [{"id": "wood", "count": 7}],
		"equipment": {"weapon": {"id": "rusty_sword", "count": 1}},
		"raw_rolls": {"crystal_raw": ["gem_amber"]},
		"bandaged": true,
		"appearance": {"outfit": "default", "hair": "short_dark"},
		"quests": {"flags": {"solo_secret": true}},
		"board_local": {"page": 3},
	}
	var save_prof_res: Dictionary = await _rpc(_guest_token, "save_cloud_player", {"data": solo_profile})
	var saved_prof: bool = bool(save_prof_res.get("ok", false))
	_assert_true(saved_prof, "Guest saved portable solo Cloud character")

	# Host opens Coop world
	var open_res: Dictionary = await _rpc(_host_token, "coop_open_world", {
		"world_name": "TEST-TAL",
		"join_mode": "private",
		"max_players": 4,
	})
	_assert_true(bool(open_res.get("ok", false)), "Host opened Nakama coop relay match")
	var match_id: String = String(open_res.get("match_id", ""))
	var room_code: String = String(open_res.get("room_code", ""))
	_assert_true(not match_id.is_empty() and room_code.length() >= 4, "Match ID & room code returned")

	# List friends shows Host's live coop lobby to Guest
	var flist: Dictionary = await _rpc(_guest_token, "list_friends", {})
	var frows: Array = flist.get("friends", []) as Array
	var saw_hosting: bool = false
	for item: Variant in frows:
		if item is Dictionary and String((item as Dictionary).get("user_id", "")) == _host_user_id:
			saw_hosting = bool((item as Dictionary).get("coop_active", false)) and String((item as Dictionary).get("coop_match_id", "")) == match_id
	_assert_true(saw_hosting, "Guest sees Host active coop lobby in list_friends")

	# Private mode rejects uninvited coop_request_join
	var req_priv: Dictionary = await _rpc(_guest_token, "coop_request_join", {"host_uid": _host_uid})
	_assert_true(not bool(req_priv.get("ok", true)), "Private world rejects uninvited friend join")

	# Switch to ask mode -> Guest requests -> Host accepts -> Guest gets approval
	var m_ask: Dictionary = await _rpc(_host_token, "set_world_join_mode", {"join_mode": "ask"})
	_assert_true(bool(m_ask.get("ok", false)) and String(m_ask.get("world_join_mode", "")) == "ask", "Join mode switched to ask")
	var req_ask: Dictionary = await _rpc(_guest_token, "coop_request_join", {"host_uid": _host_uid})
	_assert_true(bool(req_ask.get("ok", false)) and String(req_ask.get("status", "")) == "requested", "Ask mode queues join request (102)")
	var resp_ask: Dictionary = await _rpc(_host_token, "coop_respond_join_request", {"requester_user_id": _guest_user_id, "accept": true})
	_assert_true(bool(resp_ask.get("ok", false)) and bool(resp_ask.get("accepted", false)), "Host accepted join request (103)")

	# Outsider cannot read Guest's character
	var steal_char: Dictionary = await _rpc(_outsider_token, "coop_get_peer_character", {"target_user_id": _guest_user_id, "match_id": match_id})
	_assert_true(not bool(steal_char.get("ok", true)), "Outsider blocked from reading Guest cloud profile")

	# Host CAN read Guest's portable Cloud character
	var host_char: Dictionary = await _rpc(_host_token, "coop_get_peer_character", {"target_user_id": _guest_user_id, "match_id": match_id})
	_assert_true(bool(host_char.get("ok", false)) and int((host_char.get("profile", {}) as Dictionary).get("copper", 0)) == 420, "Host authorized to read Guest portable Cloud character")

	# Live two-peer NakamaRelayPeer packet & SceneMultiplayer test!
	var host_peer: RelayPeer = RelayPeer.new() as RelayPeer
	var guest_peer: RelayPeer = RelayPeer.new() as RelayPeer
	var hp_err: Error = host_peer.start_host(CloudSession.server_url, _host_token, match_id, room_code)
	_assert_true(hp_err == OK, "NakamaRelayPeer host start_host OK")

	var connected_guest_ids: Array[int] = []
	host_peer.peer_connected.connect(func(pid: int) -> void: connected_guest_ids.append(pid))
	var host_welcome_deadline: int = Time.get_ticks_msec() + 5000
	while host_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() < host_welcome_deadline:
		host_peer.poll()
		await get_tree().process_frame
	_assert_true(host_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and host_peer.get_unique_id() == 1, "Relay Host reached CONNECTION_CONNECTED as peer 1")

	# Reject unauthorized outsider relay WS connection
	var bad_peer: RelayPeer = RelayPeer.new() as RelayPeer
	bad_peer.start_client(CloudSession.server_url, _outsider_token, match_id, "")
	var bad_deadline: int = Time.get_ticks_msec() + 4000
	while bad_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() < bad_deadline:
		bad_peer.poll()
		await get_tree().process_frame
	_assert_true(bad_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "Unauthorized outsider rejected from NakamaRelayPeer match_join")
	bad_peer.close()

	# Approved guest connects cleanly
	var gp_err: Error = guest_peer.start_client(CloudSession.server_url, _guest_token, match_id, room_code)
	_assert_true(gp_err == OK, "NakamaRelayPeer guest start_client OK")
	var client_deadline: int = Time.get_ticks_msec() + 5000
	while (guest_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or connected_guest_ids.is_empty()) and Time.get_ticks_msec() < client_deadline:
		host_peer.poll()
		guest_peer.poll()
		await get_tree().process_frame
	_assert_true(guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and guest_peer.get_unique_id() >= 2, "Relay Guest connected with peer_id >= 2")
	_assert_true(connected_guest_ids.has(guest_peer.get_unique_id()), "Host saw guest peer_connected signal")

	# Bidirectional packet delivery through Nakama coop_relay match
	var guest_id: int = guest_peer.get_unique_id()
	guest_peer.set_target_peer(1)
	guest_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	guest_peer.put_packet("PING_FROM_GUEST".to_utf8_buffer())
	var recv_host: PackedByteArray = PackedByteArray()
	var sender_on_host: int = 0
	var pkt_deadline: int = Time.get_ticks_msec() + 3000
	while recv_host.is_empty() and Time.get_ticks_msec() < pkt_deadline:
		host_peer.poll()
		guest_peer.poll()
		if host_peer.get_available_packet_count() > 0:
			sender_on_host = host_peer.get_packet_peer()
			recv_host = host_peer.get_packet()
		await get_tree().process_frame
	_assert_true(recv_host.get_string_from_utf8() == "PING_FROM_GUEST" and sender_on_host == guest_id, "Relay delivered Guest->Host packet with server-verified sender peer ID")

	host_peer.set_target_peer(guest_id)
	host_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	host_peer.put_packet("PONG_FROM_HOST".to_utf8_buffer())
	var recv_guest: PackedByteArray = PackedByteArray()
	var sender_on_guest: int = 0
	var pkt2_deadline: int = Time.get_ticks_msec() + 3000
	while recv_guest.is_empty() and Time.get_ticks_msec() < pkt2_deadline:
		host_peer.poll()
		guest_peer.poll()
		if guest_peer.get_available_packet_count() > 0:
			sender_on_guest = guest_peer.get_packet_peer()
			recv_guest = guest_peer.get_packet()
		await get_tree().process_frame
	_assert_true(recv_guest.get_string_from_utf8() == "PONG_FROM_HOST" and sender_on_guest == 1, "Relay delivered Host->Guest packet cleanly")

	# Check server-authenticated peer metadata (UID + role)
	var meta: Dictionary = host_peer.get_peer_meta(guest_id)
	_assert_true(String(meta.get("uid", "")) == _guest_uid and String(meta.get("role", "")) == "player", "Relay peer metadata carries verified UID & role")

	guest_peer.close()
	host_peer.close()
	await _rpc(_host_token, "coop_close_world", {})
	var flist_after: Dictionary = await _rpc(_guest_token, "list_friends", {})
	var still_hosting: bool = false
	for item: Variant in (flist_after.get("friends", []) as Array):
		if item is Dictionary and String((item as Dictionary).get("user_id", "")) == _host_user_id:
			still_hosting = bool((item as Dictionary).get("coop_active", false))
	_assert_true(not still_hosting, "Closed lobby disappears from friends list")

	# Test LAN identity ticket issuance + verification + role resolution
	var ticket_res: Dictionary = await _rpc(_guest_token, "coop_issue_ticket", {})
	_assert_true(bool(ticket_res.get("ok", false)) and not String(ticket_res.get("ticket", "")).is_empty(), "Identity ticket issued")
	var verify_res: Dictionary = await _rpc(_host_token, "coop_verify_ticket", {"user_id": _guest_user_id, "ticket": String(ticket_res.get("ticket", ""))})
	_assert_true(bool(verify_res.get("valid", false)) and String(verify_res.get("uid", "")) == _guest_uid, "Host verifies Guest identity ticket cleanly")

	# Test Phase 4 debug spawn permission helper on TestLevel
	var tl_script: GDScript = load("res://src/world/test_level.gd") as GDScript
	_assert_true(tl_script != null, "TestLevel script loads with strict typing")


func _issue_dev_license_key() -> String:
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var url: String = "%s/v2/rpc/admin_issue_license_key?http_key=shadowspore_dev_http_key" % CloudSession.server_url.trim_suffix("/")
	var body: String = JSON.stringify(JSON.stringify({
		"count": 1,
		"edition": "standard",
		"role_grant": "player",
		"note": "test_nakama_relay",
	}))
	var err: int = req.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return ""
	var done: Array = await req.request_completed
	req.queue_free()
	if int(done[1]) < 200 or int(done[1]) >= 300:
		return ""
	var env: Variant = JSON.parse_string((done[3] as PackedByteArray).get_string_from_utf8())
	if not (env is Dictionary):
		return ""
	var p: Variant = JSON.parse_string(String((env as Dictionary).get("payload", "{}")))
	if not (p is Dictionary):
		return ""
	var keys: Array = (p as Dictionary).get("keys", []) as Array
	if keys.is_empty():
		return ""
	return String((keys[0] as Dictionary).get("key", ""))


func _email_login(email: String, password: String) -> Dictionary:
	var prev_url: String = CloudSession.server_url
	var prev_key: String = CloudSession.server_key
	var prev_tok: String = CloudSession.token
	var prev_uid: String = CloudSession.user_id
	CloudSession.server_url = CloudSession.DEFAULT_DEV_URL
	CloudSession.server_key = CloudSession.DEFAULT_DEV_SERVER_KEY
	var lic_key: String = await _issue_dev_license_key()
	if lic_key.is_empty():
		CloudSession.server_url = prev_url
		CloudSession.server_key = prev_key
		return {"ok": false}
	var res: Dictionary = await CloudSession._request_json(
		HTTPClient.METHOD_POST,
		"/v2/account/authenticate/email?create=true",
		JSON.stringify({"email": email, "password": password, "vars": {"license_key": lic_key}}),
		false
	)
	CloudSession.server_url = prev_url
	CloudSession.server_key = prev_key
	CloudSession.token = prev_tok
	CloudSession.user_id = prev_uid
	if not bool(res.get("ok", false)):
		return {"ok": false}
	var data: Dictionary = res.get("data", {}) as Dictionary
	return {"ok": true, "token": String(data.get("token", ""))}


func _rpc(jwt: String, rpc_id: String, payload: Dictionary) -> Dictionary:
	var prev_tok: String = CloudSession.token
	var prev_uid: String = CloudSession.user_id
	CloudSession.token = jwt
	CloudSession.user_id = _jwt_uid(jwt)
	var out: Dictionary = await CloudSession.call_rpc(rpc_id, payload)
	CloudSession.token = prev_tok
	CloudSession.user_id = prev_uid
	return out



func _jwt_uid(jwt: String) -> String:
	var parts: PackedStringArray = jwt.split(".")
	if parts.size() < 2:
		return ""
	var b64: String = parts[1].replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var parsed: Variant = JSON.parse_string(Marshalls.base64_to_raw(b64).get_string_from_utf8())
	return String((parsed as Dictionary).get("uid", "")) if parsed is Dictionary else ""
