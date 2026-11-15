extends Node
## Always-online session guard, launcher launch-ticket attestation, and anti-cheat watchdog.
## Enforces valid license + online server connection in Release builds (and `--strict-guard` tests),
## runs periodic heartbeats, detects speedhacks/stat tampering, and handles the 60s reconnect grace period.

const OVERLAY_SCRIPT: GDScript = preload("res://src/ui/access_gate_overlay.gd")
const HEARTBEAT_INTERVAL_SEC: float = 25.0
const RECONNECT_GRACE_SEC: float = 60.0
const GRACE_RETRY_INTERVAL_SEC: float = 4.0

signal access_blocked(title: String, reason: String, can_retry: bool)
signal reconnect_state_changed(reconnecting: bool, seconds_left: float, message: String)
signal access_restored()

var initialized: bool = false
var verified: bool = false
var locked: bool = false
var lock_title: String = ""
var lock_reason: String = ""
var lock_can_retry: bool = false

var reconnecting: bool = false
var grace_remaining: float = 0.0
var session_nonce: String = ""

var _start_usec: int = 0
var _last_unix_sec: float = 0.0
var _last_ticks_msec: int = 0
var _heartbeat_timer: float = HEARTBEAT_INTERVAL_SEC
var _grace_retry_timer: float = GRACE_RETRY_INTERVAL_SEC
var _heartbeat_in_flight: bool = false
var _paused_by_guard: bool = false
var _ui_blocked_by_guard: bool = false
var _grace_emit_accum: float = 0.0
var _tamper_strikes: int = 0
var _overlay: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_usec = Time.get_ticks_usec()
	_last_unix_sec = Time.get_unix_time_from_system()
	_last_ticks_msec = Time.get_ticks_msec()
	if DisplayServer.get_name() != "headless":
		_install_overlay.call_deferred()


func _install_overlay() -> void:
	if _overlay != null or get_tree() == null:
		return
	var inst: CanvasLayer = OVERLAY_SCRIPT.new() as CanvasLayer
	_overlay = inst
	get_tree().root.add_child(inst)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		CloudSession.graceful_quit()


func is_strict_mode() -> bool:
	return CloudSession.is_strict_release()


func is_gameplay_allowed() -> bool:
	if locked:
		return false
	if is_strict_mode():
		return verified and CloudSession.is_entitled()
	return true


## Verifies launcher ticket, license entitlement, and executable SHA-256 on game boot.
func verify_startup_async(force_strict: bool = false) -> Dictionary:
	if force_strict:
		CloudSession.strict_override = true
	var strict: bool = is_strict_mode()
	initialized = true
	locked = false
	lock_title = ""
	lock_reason = ""
	lock_can_retry = false

	if not strict and not CloudSession.is_logged_in():
		verified = true
		access_restored.emit()
		return {"ok": true, "mode": "dev_offline"}

	if not CloudSession.is_logged_in():
		if not await CloudSession.try_restore_session():
			return _block("LAUNCHER ERFORDERLICH",
				"Shadowspore muss ueber den angemeldeten Shadowspore Launcher gestartet werden.",
				false)

	var profile: Dictionary = await CloudSession.fetch_my_profile()
	if profile.is_empty():
		var err_msg: String = CloudSession.last_error
		if err_msg.is_empty():
			err_msg = "Keine Verbindung zum Shadowspore-Server (%s)." % CloudSession.server_url
		return _block("SERVER NICHT ERREICHBAR", err_msg, true)

	if CloudSession.banned:
		var reason: String = CloudSession.ban_reason if not CloudSession.ban_reason.is_empty() else "Konto dauerhaft gesperrt."
		return _block("KONTO GESPERRT", reason, false)

	if not CloudSession.license_active:
		var lic_msg: String = CloudSession.license_error if not CloudSession.license_error.is_empty() else "Keine gueltige Shadowspore-Lizenz aktiv. Bitte Key auf shadowspore.com einloesen."
		return _block("LIZENZ ERFORDERLICH", lic_msg, false)

	var ticket: String = CloudSession.launch_ticket
	if ticket.is_empty():
		if strict:
			CloudSession.report_security_event("MISSING_LAUNCH_TICKET", "Game started without launcher ticket", "warn")
			return _block("DIREKTSTART BLOCKIERT",
				"Bitte starte Shadowspore direkt ueber den offiziellen Shadowspore Launcher.",
				false)
		verified = true
		session_nonce = "DEV-" + str(Time.get_unix_time_from_system())
		_heartbeat_timer = HEARTBEAT_INTERVAL_SEC
		access_restored.emit()
		return {"ok": true, "mode": "dev_logged_in"}

	var exe_sha: String = compute_self_exe_sha256()
	var redeem_res: Dictionary = await CloudSession.redeem_launch_ticket(ticket, exe_sha)
	CloudSession.launch_ticket = ""
	if not bool(redeem_res.get("ok", false)):
		return _block("START-VERIFIZIERUNG FEHLGESCHLAGEN",
			String(redeem_res.get("error", "Startticket ungueltig oder abgelaufen. Bitte ueber den Launcher neu starten.")),
			false)

	session_nonce = String(redeem_res.get("session_nonce", ""))
	verified = true
	_heartbeat_timer = float(redeem_res.get("heartbeat_interval", HEARTBEAT_INTERVAL_SEC))
	_last_unix_sec = Time.get_unix_time_from_system()
	_last_ticks_msec = Time.get_ticks_msec()
	access_restored.emit()
	return {"ok": true, "session_nonce": session_nonce}


func compute_self_exe_sha256() -> String:
	var exe_path: String = OS.get_executable_path()
	if exe_path.is_empty() or not FileAccess.file_exists(exe_path):
		return ""
	# Im Editor verweist executable_path auf Godot.exe; im Export auf Shadowspore.exe
	if OS.is_debug_build() and not exe_path.get_file().to_lower().begins_with("shadowspore"):
		return CloudSession.launcher_exe_sha256
	return FileAccess.get_sha256(exe_path).to_lower()


func _block(title: String, reason: String, can_retry: bool) -> Dictionary:
	verified = false
	locked = true
	reconnecting = false
	lock_title = title
	lock_reason = reason
	lock_can_retry = can_retry
	_leave_world_if_needed()
	access_blocked.emit(title, reason, can_retry)
	return {"ok": false, "title": title, "error": reason}


func _leave_world_if_needed() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if _paused_by_guard:
		tree.paused = false
		_paused_by_guard = false
	if _ui_blocked_by_guard:
		InputManager.ui_blocking = false
		_ui_blocked_by_guard = false
	NetworkManager.leave()
	var world: Node = tree.get_first_node_in_group("world")
	if world != null or tree.get_first_node_in_group("sandbox") != null:
		GameLauncher.launch(tree, {})


func _process(delta: float) -> void:
	if not initialized or locked:
		return
	if DisplayServer.get_name() == "headless":
		return
	if not is_strict_mode() and not CloudSession.is_logged_in():
		return
	if not verified or session_nonce.is_empty():
		return

	if Engine.time_scale > 1.35 or Engine.time_scale < 0.0:
		_tamper_strikes += 1
		Engine.time_scale = 1.0
		if _tamper_strikes >= 2 and not _heartbeat_in_flight:
			_send_heartbeat_now("ENGINE_TIME_SCALE")

	if reconnecting:
		grace_remaining = maxf(0.0, grace_remaining - delta)
		_grace_emit_accum += delta
		if _grace_emit_accum >= 0.25:
			_grace_emit_accum = 0.0
			reconnect_state_changed.emit(true, grace_remaining, "VERBINDUNG UNTERBROCHEN")
		_grace_retry_timer -= delta
		if _grace_retry_timer <= 0.0 and not _heartbeat_in_flight:
			_grace_retry_timer = GRACE_RETRY_INTERVAL_SEC
			_send_heartbeat_now("")
		if grace_remaining <= 0.0:
			_expire_reconnect_grace()
		return

	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0 and not _heartbeat_in_flight:
		_heartbeat_timer = HEARTBEAT_INTERVAL_SEC
		_send_heartbeat_now("")


func _collect_tamper_flag(explicit_flag: String = "") -> String:
	if not explicit_flag.is_empty():
		return explicit_flag
	if Engine.time_scale > 1.35 or Engine.time_scale < 0.0:
		Engine.time_scale = 1.0
		return "ENGINE_TIME_SCALE"
	var now_unix: float = Time.get_unix_time_from_system()
	var now_msec: int = Time.get_ticks_msec()
	var unix_dt: float = now_unix - _last_unix_sec
	var ticks_dt: float = float(now_msec - _last_ticks_msec) / 1000.0
	_last_unix_sec = now_unix
	_last_ticks_msec = now_msec
	if unix_dt >= 5.0 and ticks_dt > (unix_dt * 1.65 + 8.0):
		return "CLIENT_CLOCK_DRIFT"
	if not CloudSession.is_admin() and get_tree() != null:
		for node: Node in get_tree().get_nodes_in_group("players"):
			if not node.is_multiplayer_authority():
				continue
			var prog: ProgressComponent = node.get_node_or_null("ProgressComponent") as ProgressComponent
			if prog != null:
				if prog.copper < 0 or prog.xp < 0 or prog.copper > 500000000 or prog.claimed < 1 or prog.claimed > 150:
					return "STAT_CANARY_BOUNDS"
			var hp: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
			if hp != null and (hp.current < -1.0 or hp.max_health > 50000.0):
				return "HP_CANARY_BOUNDS"
	return ""


func _send_heartbeat_now(explicit_flag: String) -> void:
	if _heartbeat_in_flight or locked or not CloudSession.is_logged_in():
		return
	_heartbeat_in_flight = true
	var tamper_flag: String = _collect_tamper_flag(explicit_flag)
	var uptime_sec: float = float(Time.get_ticks_usec() - _start_usec) / 1000000.0
	var debug_sess: bool = OS.is_debug_build() and session_nonce.begins_with("DEV-")
	var res: Dictionary = await CloudSession.send_game_heartbeat(session_nonce, uptime_sec, tamper_flag, debug_sess)
	_heartbeat_in_flight = false
	if locked:
		return
	if bool(res.get("ok", false)):
		if reconnecting:
			_exit_reconnect_grace()
		return
	if bool(res.get("kick", false)):
		_block("SITZUNG BEENDET",
			String(res.get("error", "Deine Online-Sitzung wurde beendet.")),
			false)
		return
	if is_strict_mode() and not reconnecting:
		_enter_reconnect_grace()


func _enter_reconnect_grace() -> void:
	reconnecting = true
	grace_remaining = RECONNECT_GRACE_SEC
	_grace_retry_timer = GRACE_RETRY_INTERVAL_SEC
	_grace_emit_accum = 0.0
	var tree: SceneTree = get_tree()
	if tree != null:
		if not tree.paused:
			tree.paused = true
			_paused_by_guard = true
		if not InputManager.ui_blocking:
			InputManager.ui_blocking = true
			_ui_blocked_by_guard = true
	reconnect_state_changed.emit(true, grace_remaining, "VERBINDUNG UNTERBROCHEN")


func _exit_reconnect_grace() -> void:
	reconnecting = false
	grace_remaining = 0.0
	var tree: SceneTree = get_tree()
	if tree != null:
		if _paused_by_guard:
			tree.paused = false
			_paused_by_guard = false
		if _ui_blocked_by_guard:
			InputManager.ui_blocking = false
			_ui_blocked_by_guard = false
	reconnect_state_changed.emit(false, 0.0, "")
	access_restored.emit()


func _expire_reconnect_grace() -> void:
	_block("VERBINDUNG VERLOREN",
		"Die Verbindung zum Shadowspore-Server war laenger als 60 Sekunden unterbrochen.",
		false)


## Public helper used by automated security tests (`test_security_gate.tscn`).
func trigger_grace_step_for_test(dt: float) -> void:
	if not reconnecting:
		_enter_reconnect_grace()
	grace_remaining = maxf(0.0, grace_remaining - dt)
	if grace_remaining <= 0.0:
		_expire_reconnect_grace()
