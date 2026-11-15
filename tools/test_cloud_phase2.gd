extends Node
## Automated verification for Phase 2: SaveGame gzip split + live Nakama auth, UID & cloud saves.


func _ready() -> void:
	await _run()


func _fail(msg: String) -> void:
	push_error(msg)
	printerr("FAIL: " + msg)
	get_tree().quit(1)


func _run() -> void:
	# 1. Local compression round-trip
	var sample_world: Dictionary = {"version": 1, "day": 7, "time": 0.42, "things": {"a": 1, "b": "hello"}}
	var gz: String = SaveGame.compress_json(sample_world)
	if gz.is_empty():
		_fail("compress_json returned empty")
		return
	var restored: Dictionary = SaveGame.decompress_json(gz)
	if int(restored.get("day", 0)) != 7 or (restored.get("things", {}) as Dictionary).get("b") != "hello":
		_fail("decompress_json mismatch")
		return

	# 2. Live Nakama auth + UID assignment
	var auth: Dictionary = await CloudSession.authenticate_email("phase2_test@shadowspore.local", "testpass1234", true, "Phase2Tester")
	if not bool(auth.get("ok", false)):
		_fail("Nakama auth failed: %s" % String(auth.get("error", "")))
		return
	if CloudSession.uid.is_empty() or int(CloudSession.uid) < 100001:
		_fail("Invalid UID: %s" % CloudSession.uid)
		return

	# 3. UID lookup
	var lookup: Dictionary = await CloudSession.find_by_uid(CloudSession.uid)
	if not bool(lookup.get("found", false)) or String(lookup.get("user_id", "")) != CloudSession.user_id:
		_fail("find_by_uid mismatch")
		return

	# 4. Player profile cloud save/load round-trip
	var player_payload: Dictionary = {"xp": 420, "copper": 99, "claimed": 3, "slots": [{"id": "torch", "count": 2}]}
	if not await CloudSession.save_player_profile(player_payload):
		_fail("save_player_profile failed: %s" % CloudSession.last_error)
		return
	var loaded_p: Dictionary = await CloudSession.load_player_profile()
	if int(loaded_p.get("xp", 0)) != 420 or int(loaded_p.get("copper", 0)) != 99:
		_fail("load_player_profile mismatch")
		return

	# 5. World state cloud save/load round-trip + world_meta
	if not await CloudSession.save_world_state(sample_world):
		_fail("save_world_state failed: %s" % CloudSession.last_error)
		return
	if not CloudSession.has_cloud_save or CloudSession.cloud_save_day != 7:
		_fail("world_meta mismatch after save_world_state")
		return
	await CloudSession.refresh_cloud_save_info()
	if CloudSession.cloud_save_info().is_empty() or CloudSession.cloud_save_day != 7:
		_fail("refresh_cloud_save_info mismatch")
		return
	var loaded_w: Dictionary = await CloudSession.load_world_state()
	if int(loaded_w.get("day", 0)) != 7:
		_fail("load_world_state day mismatch")
		return

	# 6. Friend RPCs (Account A invites Account B by UID, B accepts, both verify, cleanup)
	var uid_a: String = CloudSession.uid
	var id_a: String = CloudSession.user_id
	var auth_b: Dictionary = await CloudSession.authenticate_email("phase2_friend@shadowspore.local", "testpass1234", true, "Phase2Friend")
	if not bool(auth_b.get("ok", false)):
		_fail("Nakama friend auth failed: %s" % String(auth_b.get("error", "")))
		return
	var uid_b: String = CloudSession.uid
	var id_b: String = CloudSession.user_id
	if uid_b.is_empty() or uid_b == uid_a:
		_fail("Invalid friend UID: %s vs %s" % [uid_b, uid_a])
		return
	# Clear any leftover relationship before asserting fresh invite flow
	await CloudSession.remove_friend(id_a)

	# Switch back to A, send friend request to B by UID
	await CloudSession.authenticate_email("phase2_test@shadowspore.local", "testpass1234", false)
	var add_res: Dictionary = await CloudSession.add_friend_by_uid(uid_b)
	if not bool(add_res.get("ok", false)):
		_fail("add_friend_by_uid failed: %s" % String(add_res.get("error", "")))
		return
	var list_a_sent: Array[Dictionary] = await CloudSession.list_friends()
	if not _has_friend(list_a_sent, id_b, uid_b, 1):
		_fail("Expected state=1 invite_sent on Account A, got: %s" % str(list_a_sent))
		return

	# Switch to B, verify state=2 incoming invite, accept, verify state=0 mutual friend
	await CloudSession.authenticate_email("phase2_friend@shadowspore.local", "testpass1234", false)
	var list_b_recv: Array[Dictionary] = await CloudSession.list_friends()
	if not _has_friend(list_b_recv, id_a, uid_a, 2):
		_fail("Expected state=2 invite_received on Account B, got: %s" % str(list_b_recv))
		return
	if not await CloudSession.accept_friend(id_a):
		_fail("accept_friend failed: %s" % CloudSession.last_error)
		return
	var list_b_acc: Array[Dictionary] = await CloudSession.list_friends()
	if not _has_friend(list_b_acc, id_a, uid_a, 0):
		_fail("Expected state=0 accepted friend on Account B, got: %s" % str(list_b_acc))
		return

	# Clean up friendship from B
	if not await CloudSession.remove_friend(id_a):
		_fail("remove_friend failed: %s" % CloudSession.last_error)
		return

	# 7. Role check & server-authoritative admin promotion/demotion
	if CloudSession.role != "player" or CloudSession.is_admin():
		_fail("Expected default player role for test account B, got: %s" % CloudSession.role)
		return
	var denied_res: Dictionary = await CloudSession.set_user_role(uid_a, "admin")
	if bool(denied_res.get("ok", false)):
		_fail("Non-admin should not be able to promote role")
		return
	var promoted: bool = await _server_set_role(uid_b, "admin")
	if not promoted:
		_fail("Server HTTP-key admin_set_role promotion failed")
		return
	await CloudSession.fetch_my_profile()
	if CloudSession.role != "admin" or not CloudSession.is_admin():
		_fail("Expected admin role after promotion, got: %s" % CloudSession.role)
		return
	var demoted_res: Dictionary = await CloudSession.set_user_role(uid_b, "player")
	if not bool(demoted_res.get("ok", false)) or CloudSession.role != "player" or CloudSession.is_admin():
		_fail("Admin demotion failed: %s" % str(demoted_res))
		return

	# 8. Check PixelText new glyphs (@, _, *) render without error
	if PixelText.width("A@B_C*") <= 0:
		_fail("PixelText width failed")
		return

	CloudSession.logout()
	if CloudSession.has_cloud_save or CloudSession.role != "player" or CloudSession.is_admin():
		_fail("CloudSession should reset save and role on logout")
		return
	print("CLOUD PHASE 2 OK (uid=%s, friend_uid=%s)" % [uid_a, uid_b])
	get_tree().quit(0)


func _server_set_role(target_uid: String, new_role: String) -> bool:
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var url: String = "%s/v2/rpc/admin_set_role?http_key=shadowspore_dev_http_key" % CloudSession.server_url.trim_suffix("/")
	var body: String = JSON.stringify(JSON.stringify({"uid": target_uid, "role": new_role}))
	var err: int = req.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return false
	var done: Array = await req.request_completed
	req.queue_free()
	var code: int = int(done[1])
	if code < 200 or code >= 300:
		return false
	var raw_body: String = (done[3] as PackedByteArray).get_string_from_utf8()
	var env: Variant = JSON.parse_string(raw_body)
	if not (env is Dictionary):
		return false
	var payload_var: Variant = JSON.parse_string(String((env as Dictionary).get("payload", "{}")))
	return payload_var is Dictionary and bool((payload_var as Dictionary).get("ok", false))


static func _has_friend(items: Array[Dictionary], expected_user_id: String, expected_uid: String, expected_state: int) -> bool:
	for item: Dictionary in items:
		if String(item.get("user_id", "")) == expected_user_id and String(item.get("uid", "")) == expected_uid and int(item.get("state", -1)) == expected_state:
			return true
	return false
