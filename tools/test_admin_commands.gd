extends Node
## Automated verification suite for:
##   1. Chat Transparency / Visibility setting (30%..100% clamping & persistence)
##   2. AdminCommands strict authorization matrix (Strict Release, Online Debug, Offline Dev, Remote Peer)
##   3. Zero UI leakage for unauthorized players (no badge, no admin autocomplete, generic unknown command error)
##   4. Host-authoritative execution of Player, World & Multiplayer commands in live ZoneWorld

const HudTestWorld := preload("res://tools/hud_test_world.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("ADMIN TEST FAIL: " + label)
		print("FAIL: ", label)


func _inv_count(inv: InventoryComponent, item_id: String) -> int:
	var total: int = 0
	for s: Variant in inv.slots:
		var d: Dictionary = s as Dictionary
		if String(d.get("id", "")) == item_id:
			total += int(d.get("count", 0))
	return total


func _run() -> void:
	var prev_opacity: int = int(GameSettings.get_value("chat_opacity"))
	var prev_strict: bool = CloudSession.strict_override
	var prev_token: String = CloudSession.token
	var prev_uid: String = CloudSession.user_id
	var prev_role: String = CloudSession.role
	var prev_lic: bool = CloudSession.license_active
	var prev_verified: bool = GameGuard.verified

	var player: Player = await HudTestWorld.open(self)
	_ok(player != null, "live ZoneWorld loaded")
	if player == null:
		_finish(prev_opacity, prev_strict, prev_token, prev_uid, prev_role, prev_lic, prev_verified)
		return
	var hud: CanvasLayer = player.get("_hud") as CanvasLayer
	var chat: CanvasLayer = hud.get_node_or_null("GameChat") as CanvasLayer if hud != null else null
	if chat == null:
		chat = get_tree().get_first_node_in_group("game_chat") as CanvasLayer
	_ok(chat != null, "GameChat present in HUD")

	# ------------------------------------------------------------------ 1. Chat Opacity Slider Clamping
	GameSettings.set_value("chat_opacity", 10)
	_ok(int(GameSettings.get_value("chat_opacity")) == 30, "chat_opacity clamps below 30 -> 30")
	_ok(is_equal_approx(GameSettings.chat_opacity(), 0.30), "chat_opacity() returns 0.30 at min")
	GameSettings.set_value("chat_opacity", 140)
	_ok(int(GameSettings.get_value("chat_opacity")) == 100, "chat_opacity clamps above 100 -> 100")
	_ok(is_equal_approx(GameSettings.chat_opacity(), 1.00), "chat_opacity() returns 1.00 at max")
	GameSettings.set_value("chat_opacity", 65)
	_ok(int(GameSettings.get_value("chat_opacity")) == 65, "chat_opacity stores valid value 65")
	_ok(is_equal_approx(GameSettings.chat_opacity(), 0.65), "chat_opacity() returns 0.65")

	# ------------------------------------------------------------------ 2. Strict Security Authorization Matrix
	# Case A: Strict Release + Logged Out -> DENIED
	CloudSession.strict_override = true
	CloudSession.token = ""
	CloudSession.user_id = ""
	CloudSession.role = "player"
	NetworkManager._peer_roles.clear()
	_ok(not AdminCommands.can_use_local(), "Strict Release logged-out: can_use_local == false")
	_ok(AdminCommands.mode_badge().is_empty(), "Strict Release logged-out: mode_badge == empty")
	_ok(not AdminCommands.is_sender_authorized(1), "Strict Release logged-out: host sender denied")
	_ok(not AdminCommands.is_sender_authorized(2), "Strict Release logged-out: remote sender denied")
	var denied_a: Dictionary = AdminCommands.execute_on_server(1, "/god on", get_tree())
	_ok(not bool(denied_a.get("ok", true)), "Strict Release logged-out: execute_on_server('/god on') denied")
	_ok(not player.health.god_mode, "Strict Release logged-out: god_mode remained false")

	# Zero UI leakage check for unauthorized user
	if chat != null:
		chat.call("open_chat")
		chat.call("_on_field_changed", "/g")
		var sugs_unauth: Array = chat.get("_suggestions") as Array
		var leaked_admin: bool = false
		for s: Variant in sugs_unauth:
			if String((s as Dictionary).get("kind", "")) == "admin":
				leaked_admin = true
		_ok(not leaked_admin, "Unauthorized user sees zero admin suggestions in autocomplete")
		chat.call("_submit", "/god on")
		var hint_lbl: Label = chat.get("_hint") as Label
		_ok(hint_lbl.text.begins_with("Unbekannter Befehl"), "Unauthorized /god gets generic unknown-command hint")
		chat.call("close_chat")

	# Case B: Strict Release + Logged-In Player / Moderator -> DENIED
	CloudSession.token = "tok_test"
	CloudSession.user_id = "uid_player"
	CloudSession.role = "player"
	_ok(not AdminCommands.can_use_local(), "Strict Release player: can_use_local == false")
	_ok(not AdminCommands.is_sender_authorized(1), "Strict Release player: host sender denied")
	CloudSession.role = "moderator"
	_ok(not AdminCommands.can_use_local(), "Strict Release moderator: can_use_local == false")
	_ok(not AdminCommands.is_sender_authorized(1), "Strict Release moderator: host sender denied")

	# Case C: Strict Release + Logged-In Admin
	# First: unverified / unlicensed admin must STILL be blocked by GameGuard!
	CloudSession.role = "admin"
	CloudSession.license_active = false
	GameGuard.verified = false
	_ok(not AdminCommands.can_use_local(), "Strict Release unverified admin: blocked by GameGuard")
	_ok(not AdminCommands.is_sender_authorized(1), "Strict Release unverified admin: sender blocked by GameGuard")
	# Second: verified + entitled admin -> ALLOWED
	CloudSession.license_active = true
	GameGuard.verified = true
	_ok(AdminCommands.can_use_local(), "Strict Release verified admin: can_use_local == true")
	_ok(AdminCommands.mode_badge() == "ADM", "Strict Release verified admin: mode_badge == ADM")
	_ok(AdminCommands.is_sender_authorized(1), "Strict Release verified admin: host sender allowed")
	var ok_admin: Dictionary = AdminCommands.execute_on_server(1, "/admin", get_tree())
	_ok(bool(ok_admin.get("ok", false)), "Strict Release verified admin: /admin executes")

	# Case D: Debug Build + Logged-In Non-Admin Player -> DENIED (no debug cheat loophole online!)
	CloudSession.strict_override = false
	CloudSession.role = "player"
	_ok(not AdminCommands.can_use_local(), "Online Debug logged-in player: can_use_local == false")
	_ok(not AdminCommands.is_sender_authorized(1), "Online Debug logged-in player: host sender denied")
	var denied_d: Dictionary = AdminCommands.execute_on_server(1, "/gold 10", get_tree())
	_ok(not bool(denied_d.get("ok", true)), "Online Debug logged-in player: /gold denied")

	# Case E: Offline Debug Dev Build -> Local Host ALLOWED ("DEV"), Remote Non-Admin DENIED, Remote Admin ALLOWED
	CloudSession.token = ""
	CloudSession.user_id = ""
	CloudSession.role = "player"
	_ok(AdminCommands.can_use_local(), "Offline Debug host: can_use_local == true")
	_ok(AdminCommands.mode_badge() == "DEV", "Offline Debug host: mode_badge == DEV")
	_ok(AdminCommands.is_sender_authorized(1), "Offline Debug host: sender 1 allowed")
	_ok(not AdminCommands.is_sender_authorized(2), "Offline Debug: unknown remote peer 2 denied")
	NetworkManager._peer_roles[2] = "player"
	_ok(not AdminCommands.is_sender_authorized(2), "Remote peer 2 with role=player denied")
	var denied_remote: Dictionary = AdminCommands.execute_on_server(2, "/god on", get_tree())
	_ok(not bool(denied_remote.get("ok", true)), "Remote non-admin peer 2 execute_on_server denied")
	NetworkManager._peer_roles[2] = "admin"
	_ok(AdminCommands.is_sender_authorized(2), "Remote peer 2 with verified role=admin allowed")
	NetworkManager._peer_roles.clear()

	# ------------------------------------------------------------------ 3. Live Command Execution
	# /admin categories
	for sub: String in ["", "spieler", "welt", "multiplayer"]:
		var r_help: Dictionary = AdminCommands.execute_on_server(1, ("/admin " + sub).strip_edges(), get_tree())
		_ok(bool(r_help.get("ok", false)), "/admin %s succeeds" % sub)

	# /god
	var r_god_on: Dictionary = AdminCommands.execute_on_server(1, "/god on", get_tree())
	_ok(bool(r_god_on.get("ok", false)) and player.health.god_mode, "/god on enables god_mode")
	var r_god_off: Dictionary = AdminCommands.execute_on_server(1, "/god off", get_tree())
	_ok(bool(r_god_off.get("ok", false)) and not player.health.god_mode, "/god off disables god_mode")

	# /stamina
	var r_sta_on: Dictionary = AdminCommands.execute_on_server(1, "/stamina on", get_tree())
	_ok(bool(r_sta_on.get("ok", false)) and player.stamina.infinite, "/stamina on enables infinite stamina")
	var r_sta_off: Dictionary = AdminCommands.execute_on_server(1, "/stamina off", get_tree())
	_ok(bool(r_sta_off.get("ok", false)) and not player.stamina.infinite, "/stamina off disables infinite stamina")

	# /hp & /heal
	var r_hp: Dictionary = AdminCommands.execute_on_server(1, "/hp 35", get_tree())
	_ok(bool(r_hp.get("ok", false)) and roundi(player.health.current) == 35, "/hp 35 sets current HP to 35")
	var r_heal: Dictionary = AdminCommands.execute_on_server(1, "/heal", get_tree())
	_ok(bool(r_heal.get("ok", false)) and is_equal_approx(player.health.current, player.health.max_health), "/heal restores full HP")

	# /speed
	var r_spd: Dictionary = AdminCommands.execute_on_server(1, "/speed 2.5", get_tree())
	_ok(bool(r_spd.get("ok", false)) and is_equal_approx(player.admin_speed_scale, 2.5), "/speed 2.5 updates admin_speed_scale")
	var r_spd_rst: Dictionary = AdminCommands.execute_on_server(1, "/speed reset", get_tree())
	_ok(bool(r_spd_rst.get("ok", false)) and is_equal_approx(player.admin_speed_scale, 1.0), "/speed reset restores 1.0")

	# /give
	var sw_before: int = _inv_count(player.inventory, "sword_basic")
	var r_give: Dictionary = AdminCommands.execute_on_server(1, "/give sword_basic 2", get_tree())
	_ok(bool(r_give.get("ok", false)) and _inv_count(player.inventory, "sword_basic") == sw_before + 2, "/give sword_basic 2 adds 2 items")

	# /gold & /copper
	var copper_before: int = player.progress.copper
	var r_gold: Dictionary = AdminCommands.execute_on_server(1, "/gold 3", get_tree())
	_ok(bool(r_gold.get("ok", false)) and player.progress.copper == copper_before + 3 * Currency.GOLD, "/gold 3 awards 3 gold")
	var r_cop: Dictionary = AdminCommands.execute_on_server(1, "/copper 42", get_tree())
	_ok(bool(r_cop.get("ok", false)) and player.progress.copper == copper_before + 3 * Currency.GOLD + 42, "/copper 42 awards 42 copper")

	# /xp & /level
	var xp_before: int = player.progress.xp
	var r_xp: Dictionary = AdminCommands.execute_on_server(1, "/xp 50", get_tree())
	_ok(bool(r_xp.get("ok", false)) and player.progress.xp >= xp_before + 50, "/xp 50 awards 50 XP")
	var r_lvl: Dictionary = AdminCommands.execute_on_server(1, "/level 4", get_tree())
	_ok(bool(r_lvl.get("ok", false)) and player.progress.level >= 4, "/level 4 raises player to level 4")

	# /effect
	var r_eff: Dictionary = AdminCommands.execute_on_server(1, "/effect burn 15", get_tree())
	_ok(bool(r_eff.get("ok", false)) and player.effects.active().has("burn"), "/effect burn 15 applies burn status")
	var r_eff_clr: Dictionary = AdminCommands.execute_on_server(1, "/effect clear", get_tree())
	_ok(bool(r_eff_clr.get("ok", false)) and player.effects.active().is_empty(), "/effect clear removes active statuses")

	# /time & /day
	var r_time: Dictionary = AdminCommands.execute_on_server(1, "/time nacht", get_tree())
	_ok(bool(r_time.get("ok", false)) and absf(TimeManager.time_of_day - 0.92) < 0.02, "/time nacht sets time_of_day to 0.92")
	var r_lock: Dictionary = AdminCommands.execute_on_server(1, "/time lock", get_tree())
	_ok(bool(r_lock.get("ok", false)) and TimeManager.locked, "/time lock freezes clock")
	var r_unlock: Dictionary = AdminCommands.execute_on_server(1, "/time unlock", get_tree())
	_ok(bool(r_unlock.get("ok", false)) and not TimeManager.locked, "/time unlock resumes clock")
	var r_day: Dictionary = AdminCommands.execute_on_server(1, "/day 5", get_tree())
	_ok(bool(r_day.get("ok", false)) and TimeManager.day == 4, "/day 5 sets 0-based day 4 (Tag 5)")

	# /weather
	var r_wth: Dictionary = AdminCommands.execute_on_server(1, "/weather clear", get_tree())
	_ok(bool(r_wth.get("ok", false)), "/weather clear succeeds")
	var r_wth_a: Dictionary = AdminCommands.execute_on_server(1, "/weather auto", get_tree())
	_ok(bool(r_wth_a.get("ok", false)), "/weather auto restores automatic weather")

	# /tp
	var r_tp_z: Dictionary = AdminCommands.execute_on_server(1, "/tp windkap", get_tree())
	_ok(bool(r_tp_z.get("ok", false)), "/tp windkap succeeds")
	var r_tp_h: Dictionary = AdminCommands.execute_on_server(1, "/tp home", get_tree())
	_ok(bool(r_tp_h.get("ok", false)), "/tp home succeeds")

	# /players & /announce
	var r_pl: Dictionary = AdminCommands.execute_on_server(1, "/players", get_tree())
	_ok(bool(r_pl.get("ok", false)), "/players lists active players")

	var broadcast_seen: Array[String] = []
	var on_bc: Callable = func(kind: String, txt: String) -> void:
		broadcast_seen.append(kind + ":" + txt)
	Chat.system_broadcast.connect(on_bc)
	var r_ann: Dictionary = AdminCommands.execute_on_server(1, "/announce Test Ankündigung", get_tree())
	_ok(bool(r_ann.get("ok", false)) and broadcast_seen.has("announce:Test Ankündigung"), "/announce emits system_broadcast")
	Chat.system_broadcast.disconnect(on_bc)

	# ------------------------------------------------------------------ 4. Contextual Autocomplete & GameChat Integration
	var ac_give: Array[Dictionary] = AdminCommands.autocomplete("/give sw", get_tree())
	_ok(not ac_give.is_empty() and ac_give.any(func(d: Dictionary) -> bool: return String(d["label"]) == "sword_basic"), "autocomplete /give sw suggests sword_basic")
	var ac_tp: Array[Dictionary] = AdminCommands.autocomplete("/tp wi", get_tree())
	_ok(not ac_tp.is_empty() and ac_tp.any(func(d: Dictionary) -> bool: return String(d["label"]) == "windkap"), "autocomplete /tp wi suggests windkap")
	var ac_time: Array[Dictionary] = AdminCommands.autocomplete("/time ", get_tree())
	_ok(ac_time.any(func(d: Dictionary) -> bool: return String(d["label"]) == "nacht"), "autocomplete /time suggests nacht")

	if chat != null:
		chat.call("open_chat")
		chat.call("_on_field_changed", "/")
		var sugs_root: Array = chat.get("_suggestions") as Array
		_ok(not sugs_root.is_empty() and String((sugs_root[0] as Dictionary)["insert"]) == "/msg ", "bare '/' keeps /msg as first suggestion even for admins")
		_ok(sugs_root.any(func(d: Variant) -> bool: return String((d as Dictionary)["kind"]) == "admin"), "bare '/' includes /admin for authorized admins")
		chat.call("_submit", "/god on")
		_ok(player.health.god_mode, "GameChat._submit('/god on') executes end-to-end")
		chat.call("_submit", "/god off")
		chat.call("close_chat")

	_finish(prev_opacity, prev_strict, prev_token, prev_uid, prev_role, prev_lic, prev_verified)


func _finish(prev_opacity: int, prev_strict: bool, prev_token: String, prev_uid: String, prev_role: String, prev_lic: bool, prev_verified: bool) -> void:
	GameSettings.set_value("chat_opacity", prev_opacity)
	CloudSession.strict_override = prev_strict
	CloudSession.token = prev_token
	CloudSession.user_id = prev_uid
	CloudSession.role = prev_role
	CloudSession.license_active = prev_lic
	GameGuard.verified = prev_verified
	NetworkManager._peer_roles.clear()
	print("ADMIN COMMANDS TEST: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)
