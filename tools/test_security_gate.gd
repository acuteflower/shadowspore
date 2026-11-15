extends Node
## Automated end-to-end verification of license keys, launcher launch-tickets,
## storage write guards, save plausibility anti-cheat, 60s reconnect grace, and bans.


func _ready() -> void:
	await _run()


func _fail(msg: String) -> void:
	CloudSession.strict_override = false
	CloudSession.logout()
	push_error(msg)
	printerr("FAIL: " + msg)
	get_tree().quit(1)


func _http_json(method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var err: int = req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"status": 0, "raw": "", "data": {}}
	var done: Array = await req.request_completed
	req.queue_free()
	var code: int = int(done[1])
	var raw: String = (done[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(raw)
	return {
		"status": code,
		"raw": raw,
		"data": parsed as Dictionary if parsed is Dictionary else {},
	}


func _server_http_rpc(rpc_name: String, payload: Dictionary) -> Dictionary:
	var base: String = CloudSession.server_url.trim_suffix("/")
	var url: String = "%s/v2/rpc/%s?http_key=shadowspore_dev_http_key" % [base, rpc_name]
	var res: Dictionary = await _http_json(
		HTTPClient.METHOD_POST,
		url,
		PackedStringArray(["Content-Type: application/json"]),
		JSON.stringify(JSON.stringify(payload)),
	)
	var status: int = int(res.get("status", 0))
	if status < 200 or status >= 300:
		return {}
	var data: Dictionary = res.get("data", {}) as Dictionary
	var p: Variant = JSON.parse_string(String(data.get("payload", "{}")))
	return p as Dictionary if p is Dictionary else {}


func _basic_headers() -> PackedStringArray:
	var basic: String = Marshalls.utf8_to_base64(CloudSession.server_key + ":")
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Basic " + basic,
	])


func _bearer_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + CloudSession.token,
	])


func _run() -> void:
	CloudSession.server_url = CloudSession.DEFAULT_DEV_URL
	CloudSession.server_key = CloudSession.DEFAULT_DEV_SERVER_KEY
	CloudSession.logout()
	var base: String = CloudSession.server_url.trim_suffix("/")
	var uniq: String = str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)

	# 1. Strict offline / unauthenticated launch is blocked and local saves disabled
	CloudSession.strict_override = true
	if SaveGame.exists():
		_fail("SaveGame.exists() should always return false in strict mode")
		return
	if SaveGame.delete():
		_fail("SaveGame.delete() should be blocked in strict mode")
		return
	var boot_unauth: Dictionary = await GameGuard.verify_startup_async(true)
	if bool(boot_unauth.get("ok", false)) or not GameGuard.locked or GameGuard.is_gameplay_allowed():
		_fail("Unauthenticated strict startup must be blocked: %s" % str(boot_unauth))
		return

	# 2. Keyless signup rejected on both client and server
	var client_reg: Dictionary = await CloudSession.authenticate_email("no_key_%s@shadowspore.local" % uniq, "testpass1234", true)
	if bool(client_reg.get("ok", false)):
		_fail("Strict client must refuse create=true signup")
		return
	var srv_no_key: Dictionary = await _http_json(
		HTTPClient.METHOD_POST,
		base + "/v2/account/authenticate/email?create=true",
		_basic_headers(),
		JSON.stringify({"email": "srv_nokey_%s@shadowspore.local" % uniq, "password": "testpass1234"}),
	)
	if int(srv_no_key.get("status", 0)) < 400:
		_fail("Server accepted keyless signup unexpectedly: %s" % str(srv_no_key))
		return

	# 3. Device authentication is blocked
	var dev_auth: Dictionary = await _http_json(
		HTTPClient.METHOD_POST,
		base + "/v2/account/authenticate/device?create=true",
		_basic_headers(),
		JSON.stringify({"id": "device_bypass_" + uniq}),
	)
	if int(dev_auth.get("status", 0)) < 400:
		_fail("Device auth must be rejected by server")
		return

	# 4. Issue license key -> register account -> reuse rejected -> login succeeds
	var key_res: Dictionary = await _server_http_rpc("admin_issue_license_key", {
		"count": 1,
		"edition": "founder",
		"role_grant": "player",
		"note": "security_gate_" + uniq,
	})
	var keys: Array = key_res.get("keys", []) as Array
	if keys.is_empty():
		_fail("admin_issue_license_key returned empty")
		return
	var test_key: String = String((keys[0] as Dictionary).get("key", ""))
	var email: String = "sec_user_%s@shadowspore.local" % uniq
	var password: String = "testpass1234"

	var reg_ok: Dictionary = await _http_json(
		HTTPClient.METHOD_POST,
		base + "/v2/account/authenticate/email?create=true&username=" + ("Sec_" + uniq).uri_encode(),
		_basic_headers(),
		JSON.stringify({"email": email, "password": password, "vars": {"license_key": test_key}}),
	)
	if int(reg_ok.get("status", 0)) != 200:
		_fail("Valid key signup failed: %s" % str(reg_ok))
		return

	var reuse_res: Dictionary = await _http_json(
		HTTPClient.METHOD_POST,
		base + "/v2/account/authenticate/email?create=true",
		_basic_headers(),
		JSON.stringify({"email": "reuse_%s@shadowspore.local" % uniq, "password": password, "vars": {"license_key": test_key}}),
	)
	if int(reuse_res.get("status", 0)) < 400:
		_fail("Reused license key must fail signup")
		return

	var login_ok: Dictionary = await CloudSession.authenticate_email(email, password, false)
	if not bool(login_ok.get("ok", false)) or not CloudSession.license_active:
		_fail("Login after licensed registration failed: %s" % str(login_ok))
		return

	# 5. Strict startup without launcher launch ticket must block
	CloudSession.launch_ticket = ""
	var boot_noticket: Dictionary = await GameGuard.verify_startup_async(true)
	if bool(boot_noticket.get("ok", false)) or GameGuard.lock_title != "DIREKTSTART BLOCKIERT":
		_fail("Expected DIREKTSTART BLOCKIERT without launch ticket, got: %s" % str(boot_noticket))
		return

	# 6. Launcher flow: issue_launch_ticket -> verify_startup_async -> replay rejected
	var issue_res: Dictionary = await CloudSession.call_rpc("issue_launch_ticket", {
		"exe_sha256": "",
		"build_version": "0.1.0",
		"launcher_version": "0.1.0",
	})
	var ticket: String = String(issue_res.get("ticket", ""))
	if not bool(issue_res.get("ok", false)) or ticket.is_empty():
		_fail("issue_launch_ticket failed: %s" % str(issue_res))
		return

	CloudSession.launch_ticket = ticket
	var boot_ok: Dictionary = await GameGuard.verify_startup_async(true)
	if not bool(boot_ok.get("ok", false)) or not GameGuard.is_gameplay_allowed():
		_fail("Expected verified startup with launch ticket, got: %s" % str(boot_ok))
		return
	if not CloudSession.launch_ticket.is_empty():
		_fail("One-time launch_ticket should be cleared after redemption")
		return

	var replay_res: Dictionary = await CloudSession.redeem_launch_ticket(ticket, "")
	if bool(replay_res.get("ok", false)):
		_fail("Launch ticket replay must be rejected")
		return

	# 6b. Player-issued ticket with launcher hash rejects empty game exe hash
	var hashed_issue: Dictionary = await CloudSession.call_rpc("issue_launch_ticket", {
		"exe_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"build_version": "0.1.0",
		"launcher_version": "0.1.0",
	})
	var hashed_ticket: String = String(hashed_issue.get("ticket", ""))
	var empty_game_hash: Dictionary = await CloudSession.redeem_launch_ticket(hashed_ticket, "")
	if bool(empty_game_hash.get("ok", false)):
		_fail("Redeeming launcher-hashed ticket with empty game exe hash must fail")
		return

	# 6c. Non-admin player cannot call admin RPCs
	var admin_denied: Dictionary = await CloudSession.call_rpc("admin_overview", {})
	if bool(admin_denied.get("ok", false)):
		_fail("Non-admin player must not access admin_overview: %s" % str(admin_denied))
		return

	# 7. Heartbeat works with verified session nonce & blocks player debug_session bypass
	var hb_res: Dictionary = await CloudSession.send_game_heartbeat(GameGuard.session_nonce, 4.0, "", false)
	if not bool(hb_res.get("ok", false)):
		_fail("Expected heartbeat ok=true, got: %s" % str(hb_res))
		return
	var fake_debug_hb: Dictionary = await CloudSession.send_game_heartbeat("DEV-999999", 4.0, "", true)
	if bool(fake_debug_hb.get("ok", false)) or String(fake_debug_hb.get("code", "")) != "DEBUG_SESSION_FORBIDDEN":
		_fail("Player must NOT be allowed to open debug_session bypass: %s" % str(fake_debug_hb))
		return
	# DEBUG_SESSION_FORBIDDEN intentionally invalidated session -> re-issue clean session for remaining checks
	var reissue: Dictionary = await CloudSession.call_rpc("issue_launch_ticket", {
		"exe_sha256": "",
		"build_version": "0.1.0",
		"launcher_version": "0.1.0",
	})
	CloudSession.launch_ticket = String(reissue.get("ticket", ""))
	var reboot_ok: Dictionary = await GameGuard.verify_startup_async(true)
	if not bool(reboot_ok.get("ok", false)):
		_fail("Session restore after bypass test failed: %s" % str(reboot_ok))
		return

	# 7b. World cloud save integrity checks (corrupt gz + impossible day/level jump rejected; valid gz accepted)
	var bad_gz_res: Dictionary = await CloudSession.call_rpc("save_cloud_world", {
		"data": {"version": 1, "day": 1, "time": 0.2, "level": 1, "saved_at": 1700000000, "gz": "bm90LWd6aXA="}
	})
	if bool(bad_gz_res.get("ok", false)):
		_fail("Non-gzip world payload must be rejected: %s" % str(bad_gz_res))
		return
	var valid_sample_gz: String = SaveGame.compress_json({"version": 1, "day": 9999, "time": 0.25, "things": {}})
	var jump_day_res: Dictionary = await CloudSession.call_rpc("save_cloud_world", {
		"data": {"version": 1, "day": 9999, "time": 0.25, "level": 1, "saved_at": 1700000000, "gz": valid_sample_gz}
	})
	if bool(jump_day_res.get("ok", false)):
		_fail("Impossible initial day jump must be rejected: %s" % str(jump_day_res))
		return
	if not await CloudSession.save_world_state({"version": 1, "day": 2, "time": 0.25, "saved_at": 1700000000, "things": {"safe": true}}):
		_fail("Valid gzip cloud world save failed: %s" % CloudSession.last_error)
		return

	# 8. Direct storage write into saves is blocked by Nakama hook
	var direct_write: Dictionary = await _http_json(
		HTTPClient.METHOD_PUT,
		base + "/v2/storage",
		_bearer_headers(),
		JSON.stringify({
			"objects": [{
				"collection": "saves",
				"key": "player_profile",
				"value": JSON.stringify({"copper": 99999999}),
			}]
		}),
	)
	if int(direct_write.get("status", 0)) < 400:
		_fail("Direct client storage write into saves must be rejected")
		return

	# 9. Server-validated RPC save rejects initial & delta copper anomalies and accepts legit save
	if await CloudSession.save_player_profile({"copper": 99999999, "xp": 100}):
		_fail("Server save_cloud_player must reject extreme initial copper")
		return
	if not await CloudSession.save_player_profile({"copper": 120, "xp": 100, "claimed": 1}):
		_fail("Legit save_cloud_player failed: %s" % CloudSession.last_error)
		return
	if await CloudSession.save_player_profile({"copper": 500000, "xp": 100, "claimed": 1}):
		_fail("Server save_cloud_player must reject sudden 500k copper jump")
		return

	# 10. 60s Reconnect Grace pauses gameplay, then locks on expiry
	GameGuard.trigger_grace_step_for_test(10.0)
	if not GameGuard.reconnecting or not get_tree().paused or GameGuard.locked:
		_fail("Grace period should pause tree without immediate lock")
		return
	GameGuard.trigger_grace_step_for_test(55.0)
	if not GameGuard.locked or GameGuard.is_gameplay_allowed() or get_tree().paused:
		_fail("Expired grace period must lock gameplay and unpause tree")
		return

	# 11. Ban blocks login; unban restores login
	var uid: String = CloudSession.uid
	var ban_res: Dictionary = await _server_http_rpc("admin_set_ban", {
		"target_uid": uid,
		"banned": true,
		"reason": "SecurityGateCheck",
	})
	if not bool(ban_res.get("ok", false)):
		_fail("admin_set_ban(true) failed")
		return
	var blocked_login: Dictionary = await CloudSession.authenticate_email(email, password, false)
	if bool(blocked_login.get("ok", false)):
		_fail("Banned account must be blocked from login")
		return
	var unban_res: Dictionary = await _server_http_rpc("admin_set_ban", {
		"target_uid": uid,
		"banned": false,
		"reason": "",
	})
	if not bool(unban_res.get("ok", false)):
		_fail("admin_set_ban(false) failed")
		return
	var restored_login: Dictionary = await CloudSession.authenticate_email(email, password, false)
	if not bool(restored_login.get("ok", false)):
		_fail("Unbanned account should log in again: %s" % str(restored_login))
		return

	var ed: String = CloudSession.license_edition
	CloudSession.strict_override = false
	CloudSession.logout()
	print("SECURITY GATE TEST OK (uid=%s, edition=%s)" % [uid, ed])
	get_tree().quit(0)
