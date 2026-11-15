extends Node
## Automated verification for continuous online autosave, kick/disconnect preservation,
## removal of manual save UI, and live Nakama relay presence even while playing solo.

const RelayPeer: GDScript = preload("res://src/autoload/nakama_relay_peer.gd")
const TestLevelScene: PackedScene = preload("res://src/world/test_level.tscn")
const PauseMenuScript: GDScript = preload("res://src/ui/pause_menu.gd")
const MultiplayerHudScript: GDScript = preload("res://src/ui/multiplayer_hud.gd")


func _ready() -> void:
	get_tree().create_timer(35.0).timeout.connect(func() -> void: _fail("TIMEOUT after 35s"))
	await _run()


func _fail(msg: String) -> void:
	push_error(msg)
	printerr("FAIL: " + msg)
	get_tree().quit(1)


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _run() -> void:
	CloudSession.server_url = CloudSession.DEFAULT_DEV_URL
	CloudSession.server_key = CloudSession.DEFAULT_DEV_SERVER_KEY
	CloudSession.strict_override = false
	CloudSession.allow_headless_autosave = true

	print("[TEST] 1. PauseMenu UI audit")
	# ------------------------------------------------------------------ 1. PauseMenu UI audit (no manual save / "OHNE SPEICHERN")
	var pause_menu: PauseMenu = PauseMenuScript.new() as PauseMenu
	add_child(pause_menu)
	await get_tree().process_frame
	pause_menu._refresh_footer()
	var foot_ids: Array[String] = []
	for f_v: Variant in pause_menu._footer:
		if f_v is Dictionary:
			foot_ids.append(String((f_v as Dictionary).get("id", "")))
	_assert_true(foot_ids == ["menu", "quit"], "PauseMenu footer must only contain ['menu', 'quit'], got: %s" % str(foot_ids))
	pause_menu._items.clear()
	pause_menu._cursor = [0.0, 0.0]
	pause_menu._build_coop_page()
	for it_v: Variant in pause_menu._items:
		if it_v is Dictionary:
			var act: String = String((it_v as Dictionary).get("action", ""))
			_assert_true(act != "coop_save_char", "Manual 'CHARAKTER SPEICHERN' button must be removed from Coop tab")
	_assert_true(pause_menu._save_text() == "NUR DER HOST SPEICHERT" or "AUTO" in pause_menu._save_text(), "PauseMenu status label mismatch outside world: %s" % pause_menu._save_text())
	pause_menu.queue_free()
	await get_tree().process_frame

	print("[TEST] 2. Login Host & Guest")
	# ------------------------------------------------------------------ 2. Issue/login Host & Guest test accounts
	var host_auth: Dictionary = await _ensure_licensed_login("autosave_host@shadowspore.local", "testpass1234", "AutoHost")
	_assert_true(bool(host_auth.get("ok", false)), "Host login failed: %s" % String(host_auth.get("error", "")))
	var host_token: String = CloudSession.token
	var host_uid: String = CloudSession.uid
	var host_user_id: String = CloudSession.user_id

	var guest_auth: Dictionary = await _ensure_licensed_login("autosave_guest@shadowspore.local", "testpass1234", "AutoGuest")
	_assert_true(bool(guest_auth.get("ok", false)), "Guest login failed: %s" % String(guest_auth.get("error", "")))
	var guest_token: String = CloudSession.token
	var guest_user_id: String = CloudSession.user_id

	# Pre-seed Guest's solo save (pos + quests.flags.solo must survive any co-op kick!)
	_assert_true(await CloudSession.save_player_profile({
		"pos": [999.0, 888.0],
		"health": 80.0,
		"copper": 100,
		"xp": 20,
		"claimed": 1,
		"quests": {"flags": {"solo": true}},
	}), "Pre-seeding guest solo profile failed")
	CloudSession.logout()

	# Switch back to Host
	var relogin_host: Dictionary = await CloudSession.authenticate_email("autosave_host@shadowspore.local", "testpass1234", false)
	_assert_true(bool(relogin_host.get("ok", false)), "Host re-login failed")
	_assert_true(await CloudSession.wipe_cloud_save(), "Host cloud wipe failed")

	print("[TEST] 3. Solo live world & admin_list_active_worlds")
	# ------------------------------------------------------------------ 3. Solo World runs live on Nakama Relay & appears in Admin Live Worlds
	var open_1: Dictionary = await CloudSession.coop_open_world("AUTOSAVE TEST", "private", 4, true)
	_assert_true(bool(open_1.get("ok", false)), "coop_open_world #1 failed")
	var mid_1: String = String(open_1.get("match_id", ""))
	var open_2: Dictionary = await CloudSession.coop_open_world("AUTOSAVE SOLO", "private", 4, true)
	_assert_true(bool(open_2.get("ok", false)), "coop_open_world #2 failed: %s" % String(open_2.get("error", "")))
	var mid_2: String = String(open_2.get("match_id", ""))
	var room_code: String = String(open_2.get("room_code", ""))
	_assert_true(not mid_2.is_empty() and mid_2 != mid_1, "force_new must create a distinct fresh live match")

	# Stale close for mid_1 must NOT wipe active mid_2 (async leave() -> quick restart race guard)
	await CloudSession.coop_close_world(mid_1)

	# Host connects NetworkManager.host_relay (as solo player: explicit_coop_hud = false)
	var err_host: Error = NetworkManager.host_relay(mid_2, room_code, 4, "AUTOSAVE SOLO", "private")
	_assert_true(err_host == OK, "NetworkManager.host_relay failed: %s" % error_string(err_host))
	NetworkManager.explicit_coop_hud = false
	var h_deadline: int = Time.get_ticks_msec() + 6000
	while NetworkManager.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() < h_deadline:
		NetworkManager.multiplayer.multiplayer_peer.poll()
		await get_tree().process_frame
	_assert_true(NetworkManager.is_relay_session() and NetworkManager.multiplayer.get_peers().is_empty(), "Host should be connected alone on Nakama Relay")

	# Solo MultiplayerHud must stay hidden when solo (unless explicit_coop_hud or peers > 0)
	var hud: Control = MultiplayerHudScript.new() as Control
	add_child(hud)
	await get_tree().process_frame
	_assert_true(not hud.visible, "MultiplayerHud must stay hidden when alone in solo live world")
	NetworkManager.explicit_coop_hud = true
	NetworkManager.session_changed.emit()
	await get_tree().process_frame
	_assert_true(hud.visible, "MultiplayerHud must show when explicit_coop_hud is enabled")
	NetworkManager.explicit_coop_hud = false
	hud.queue_free()

	# Verify Admin RPC sees the solo private world live on Nakama!
	var admin_worlds: Dictionary = await _server_http_rpc("admin_list_active_worlds", {})
	_assert_true(bool(admin_worlds.get("ok", false)), "admin_list_active_worlds failed")
	var found_solo_world: Dictionary = {}
	for w_v: Variant in (admin_worlds.get("worlds", []) as Array):
		if w_v is Dictionary and String((w_v as Dictionary).get("match_id", "")) == mid_2:
			found_solo_world = w_v as Dictionary
			break
	_assert_true(not found_solo_world.is_empty(), "Admin Live Worlds must list solo private world (%s)" % mid_2)
	_assert_true(String(found_solo_world.get("host_uid", "")) == host_uid, "Admin Live World host_uid mismatch")
	_assert_true(String(found_solo_world.get("join_mode", "")) == "private", "Admin Live World join_mode mismatch")
	_assert_true(int(found_solo_world.get("player_count", 0)) == 1 and (found_solo_world.get("peers", []) as Array).size() == 1, "Admin Live World must show 1 active peer even when solo")

	print("[TEST] 4. Autosave signals & snapshot fallback")
	# ------------------------------------------------------------------ 4. Continuous autosave signals, coalesce & snapshot fallback on world teardown
	var level: TestLevel = TestLevelScene.instantiate() as TestLevel
	add_child(level)
	await get_tree().process_frame
	CloudSession.on_world_entered(get_tree(), "new")
	var host_player: Player = SaveGame._local_player(get_tree())
	_assert_true(host_player != null, "TestLevel did not spawn local Host Player")

	# Emit player & time milestone signals -> verifies zero signal arity errors + dirty autosave works!
	TimeManager.day = 2
	host_player.progress.copper = 77
	host_player.progress.xp = 45
	host_player.progress.changed.emit()
	host_player.inventory.changed.emit()
	TimeManager.day_started.emit(2)

	# Wait up to 4.5s for debounced dirty autosave to finish
	var auto_done: Array[bool] = [false, false]
	var on_auto_fin: Callable = func(ok: bool) -> void:
		auto_done[0] = true
		auto_done[1] = ok
	CloudSession.auto_save_finished.connect(on_auto_fin)
	var save_deadline: int = Time.get_ticks_msec() + 5000
	while not auto_done[0] and Time.get_ticks_msec() < save_deadline:
		await get_tree().process_frame
	if CloudSession.auto_save_finished.is_connected(on_auto_fin):
		CloudSession.auto_save_finished.disconnect(on_auto_fin)
	_assert_true(auto_done[0] and auto_done[1], "Debounced signal autosave failed or timed out")

	var loaded_host_p: Dictionary = await CloudSession.load_player_profile()
	var loaded_host_w: Dictionary = await CloudSession.load_world_state()
	_assert_true(int(loaded_host_p.get("copper", 0)) == 77, "Signal autosave did not persist host copper (got %s)" % str(loaded_host_p.get("copper", -1)))
	_assert_true(int(loaded_host_w.get("day", 0)) == 2, "Signal autosave did not persist host day (got %s)" % str(loaded_host_w.get("day", -1)))

	var live_pause: PauseMenu = PauseMenuScript.new() as PauseMenu
	add_child(live_pause)
	await get_tree().process_frame
	live_pause._save_info = live_pause._read_save_info()
	_assert_true("AUTO" in live_pause._save_text(), "In live host world PauseMenu status must report AUTO save, got: %s" % live_pause._save_text())
	live_pause.queue_free()
	await get_tree().process_frame

	# Mutate copper + free world right before flush -> cached snapshot fallback MUST persist 333!
	host_player.progress.copper = 333
	CloudSession.capture_live_snapshot(get_tree(), true)
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(await CloudSession.flush_cloud_save_now(get_tree()), "flush_cloud_save_now failed after world freed (snapshot fallback)")
	var post_free_p: Dictionary = await CloudSession.load_player_profile()
	_assert_true(int(post_free_p.get("copper", 0)) == 333, "Snapshot fallback did not persist copper=333 after world teardown")

	# Cleanly tear down Host Relay session & check match cleanup
	NetworkManager.leave()
	await get_tree().create_timer(0.4).timeout

	print("[TEST] 5. Co-op kick preservation")
	# ------------------------------------------------------------------ 5. Co-op Kick & Eviction Character Preservation
	# Recreate live match with Host raw NakamaRelayPeer + Guest NakamaRelayPeer
	var coop_res: Dictionary = await _user_rpc(host_token, "coop_open_world", {"world_name": "KICK TEST", "join_mode": "ask", "force_new": true})
	_assert_true(bool(coop_res.get("ok", false)), "coop_open_world for kick test failed")
	var k_mid: String = String(coop_res.get("match_id", ""))
	var k_code: String = String(coop_res.get("room_code", ""))

	# Admin/Host approves Guest via Nakama RPC? Use match_signal approve_user via admin_force_join or request+respond:
	var req_join: Dictionary = await _user_rpc(guest_token, "coop_request_join", {"room_code": k_code})
	_assert_true(bool(req_join.get("ok", false)), "Guest coop_request_join failed: %s" % str(req_join))
	var resp_join: Dictionary = await _user_rpc(host_token, "coop_respond_join_request", {"requester_user_id": guest_user_id, "accept": true})
	_assert_true(bool(resp_join.get("ok", false)) and bool(resp_join.get("accepted", false)), "Host accept join failed")

	var host_peer: RelayPeer = RelayPeer.new() as RelayPeer
	_assert_true(host_peer.start_host(CloudSession.server_url, host_token, k_mid, k_code) == OK, "Kick test start_host failed")
	var hd2: int = Time.get_ticks_msec() + 5000
	while host_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() < hd2:
		host_peer.poll()
		await get_tree().process_frame
	_assert_true(host_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "Host peer failed to connect")

	var guest_peer: RelayPeer = RelayPeer.new() as RelayPeer
	_assert_true(guest_peer.start_client(CloudSession.server_url, guest_token, k_mid, k_code) == OK, "Kick test start_client failed")
	var gd2: int = Time.get_ticks_msec() + 5000
	while guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() < gd2:
		host_peer.poll()
		guest_peer.poll()
		await get_tree().process_frame
	_assert_true(guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "Guest peer failed to connect")
	var g_pid: int = guest_peer.get_unique_id()
	_assert_true(g_pid >= 2, "Expected guest peer_id >= 2")

	# Prepare CloudSession as Guest in a co-op session, capture guest snapshot (copper=888, co-op pos=[12,34])
	CloudSession.logout()
	var g_login: Dictionary = await CloudSession.authenticate_email("autosave_guest@shadowspore.local", "testpass1234", false)
	_assert_true(bool(g_login.get("ok", false)), "Guest CloudSession login failed")
	var prior_solo: Dictionary = await CloudSession.load_player_profile()
	CloudSession._remember_solo_preserve(prior_solo)

	var guest_level: Node2D = Node2D.new()
	guest_level.add_to_group("world")
	add_child(guest_level)
	var players_box: Node2D = Node2D.new()
	players_box.name = "Players"
	guest_level.add_child(players_box)
	var guest_player: Player = TestLevel.PLAYER_SCENE.instantiate() as Player
	guest_player.name = str(g_pid)
	players_box.add_child(guest_player)
	guest_player.set_multiplayer_authority(1) ## make SaveGame._local_player find guest_player cleanly via authority
	NetworkManager._session_is_guest = true
	await get_tree().process_frame
	guest_player.progress.copper = 888
	guest_player.position = Vector2(12.0, 34.0)
	if guest_player.quests != null:
		guest_player.quests.set_flag("coop_temp")
	# Force client/guest role so capture_live_snapshot saves portable fields only!
	_assert_true(CloudSession.capture_live_snapshot(get_tree(), false, 0), "capture_live_snapshot for guest failed")

	# Host kicks Guest -> Nakama must deliver {type:"kicked", reason:"kicked"} before disconnecting!
	host_peer._disconnect_peer(g_pid, false)
	var kick_deadline: int = Time.get_ticks_msec() + 5000
	while guest_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and Time.get_ticks_msec() < kick_deadline:
		host_peer.poll()
		guest_peer.poll()
		await get_tree().process_frame
	_assert_true(guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "Guest peer was not disconnected after kick")
	_assert_true(guest_peer.last_error == "DU WURDEST VOM HOST ENTFERNT", "Expected kick reason 'DU WURDEST VOM HOST ENTFERNT', got: '%s'" % guest_peer.last_error)

	# Flush kicked Guest snapshot even after freeing dummy world, and verify Nakama preserved solo pos & quests!
	guest_level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(await CloudSession.flush_cloud_save_now(get_tree()), "Kicked guest flush_cloud_save_now failed")
	var post_kick_guest: Dictionary = await CloudSession.load_player_profile()
	_assert_true(int(post_kick_guest.get("copper", 0)) == 888, "Kicked guest did not keep co-op copper=888, got %s" % str(post_kick_guest.get("copper", -1)))
	var saved_pos: Array = post_kick_guest.get("pos", []) as Array
	_assert_true(saved_pos.size() == 2 and is_equal_approx(float(saved_pos[0]), 999.0) and is_equal_approx(float(saved_pos[1]), 888.0), "Kicked guest solo position overwritten: %s" % str(saved_pos))
	var saved_flags: Dictionary = (post_kick_guest.get("quests", {}) as Dictionary).get("flags", {}) as Dictionary
	_assert_true(bool(saved_flags.get("solo", false)) and not bool(saved_flags.get("coop_temp", false)), "Kicked guest solo quests corrupted: %s" % str(saved_flags))

	# Clean up peers and close match
	NetworkManager._session_is_guest = false
	guest_peer.close()
	host_peer.close()
	await _user_rpc(host_token, "coop_close_world", {"match_id": k_mid})
	CloudSession.logout()

	print("AUTOSAVE & LIVE WORLD VERIFICATION PASSED (host_uid=%s, match=%s)" % [host_uid, mid_2])
	get_tree().quit(0)


func _user_rpc(tok: String, rpc_name: String, body_dict: Dictionary) -> Dictionary:
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var url: String = "%s/v2/rpc/%s" % [CloudSession.server_url.trim_suffix("/"), rpc_name]
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + tok,
	])
	var body: String = JSON.stringify(JSON.stringify(body_dict))
	var err: int = req.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return {}
	var done: Array = await req.request_completed
	req.queue_free()
	var code: int = int(done[1])
	if code < 200 or code >= 300:
		return {}
	var raw_body: String = (done[3] as PackedByteArray).get_string_from_utf8()
	var env: Variant = JSON.parse_string(raw_body)
	if not (env is Dictionary):
		return {}
	var payload_var: Variant = JSON.parse_string(String((env as Dictionary).get("payload", "{}")))
	return payload_var as Dictionary if payload_var is Dictionary else {}


func _server_http_rpc(rpc_name: String, body_dict: Dictionary) -> Dictionary:
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var url: String = "%s/v2/rpc/%s?http_key=shadowspore_dev_http_key" % [CloudSession.server_url.trim_suffix("/"), rpc_name]
	var body: String = JSON.stringify(JSON.stringify(body_dict))
	var err: int = req.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return {}
	var done: Array = await req.request_completed
	req.queue_free()
	var code: int = int(done[1])
	if code < 200 or code >= 300:
		return {}
	var raw_body: String = (done[3] as PackedByteArray).get_string_from_utf8()
	var env: Variant = JSON.parse_string(raw_body)
	if not (env is Dictionary):
		return {}
	var payload_var: Variant = JSON.parse_string(String((env as Dictionary).get("payload", "{}")))
	return payload_var as Dictionary if payload_var is Dictionary else {}


func _issue_test_license_key() -> String:
	var res: Dictionary = await _server_http_rpc("admin_issue_license_key", {
		"count": 1,
		"edition": "standard",
		"role_grant": "player",
		"note": "test_autosave",
	})
	var keys: Array = res.get("keys", []) as Array
	if keys.is_empty():
		return ""
	return String((keys[0] as Dictionary).get("key", ""))


func _ensure_licensed_login(email: String, password: String, custom_username: String) -> Dictionary:
	var login_res: Dictionary = await CloudSession.authenticate_email(email, password, false)
	if bool(login_res.get("ok", false)):
		if not CloudSession.license_active:
			var rk: String = await _issue_test_license_key()
			if rk.is_empty():
				return {"ok": false, "error": "Lizenzkey fehlgeschlagen"}
			await CloudSession.call_rpc("redeem_license_key", {"license_key": rk})
			await CloudSession.fetch_my_profile()
		return {"ok": true}
	var signup_key: String = await _issue_test_license_key()
	if signup_key.is_empty():
		return {"ok": false, "error": "Signup-Lizenzkey fehlgeschlagen"}
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var url: String = "%s/v2/account/authenticate/email?create=true&username=%s" % [CloudSession.server_url.trim_suffix("/"), custom_username.uri_encode()]
	var basic: String = Marshalls.utf8_to_base64(CloudSession.server_key + ":")
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Basic " + basic,
	])
	var body: String = JSON.stringify({
		"email": email,
		"password": password,
		"vars": {"license_key": signup_key},
	})
	var err: int = req.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "HTTP error %d" % err}
	var done: Array = await req.request_completed
	req.queue_free()
	var code: int = int(done[1])
	if code < 200 or code >= 300:
		return {"ok": false, "error": "HTTP %d" % code}
	return await CloudSession.authenticate_email(email, password, false)
