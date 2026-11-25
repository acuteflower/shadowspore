extends Node
## Visual capture suite for Shadowspore's Whisper Vine Chat in the live v2 Windkap world.
## Usage:
##   Godot --rendering-driver opengl3 --path . tools/preview_chat.tscn -- --dir=<abs_dir>
## Captures:
##   1. chat_night_convo.png      (Night forest, active chat with timestamps, authors, /ort, /me, unread DM pip)
##   2. chat_night_autocomplete.png (Night forest, slash-command autocomplete leaf open)
##   3. chat_night_loggedout.png  (Night forest, logged-out SPIEL state — direct comparison to old screenshot)
##   4. chat_day_convo.png        (Bright sunlit Windkap meadow, day moss vines & bark-vellum contrast)
##   5. chat_night_ambient.png    (Closed chat with ambient boxless floating whisper feed + unread spore bud)

const HudTestWorld := preload("res://tools/hud_test_world.gd")

var out_dir: String = ""
var player: Player
var hud: CanvasLayer
var chat: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			out_dir = arg.trim_prefix("--dir=")
	_run.call_deferred()


func _run() -> void:
	player = await HudTestWorld.open(self)
	if player == null:
		push_error("PREVIEW CHAT: world did not load")
		get_tree().quit(1)
		return
	hud = player.get("_hud") as CanvasLayer
	chat = hud.get_node_or_null("GameChat") as CanvasLayer
	if chat == null:
		chat = get_tree().get_first_node_in_group("game_chat") as CanvasLayer
	if chat == null:
		push_error("PREVIEW CHAT: GameChat not found")
		get_tree().quit(1)
		return
	GameCursor.visible = false
	for id: String in ["sickle_basic", "pickaxe_basic", "axe_basic", "rod_basic"]:
		player.inventory.give(id, 1)
	if player.quests != null:
		player.quests.start("lumberjack")

	# 1. Night logged-out SPIEL comparison
	TimeManager.set_time(0.92)
	await _wait(0.8)
	Chat.lines.clear()
	Chat.contacts.clear()
	chat.call("open_chat")
	chat.call("_select", "game")
	(chat.get("_field") as LineEdit).text = "h"
	(chat.get("_field") as LineEdit).caret_column = 1
	chat.call("_on_field_changed", "h")
	await _wait(0.5)
	await _shot("chat_night_loggedout")

	# 2. Night active conversation with rich formatting, DM tab & unread pip
	NetworkManager._roster.assign([
		{"id": 1, "name": "Ellie", "slot": 0, "is_host": true},
		{"id": 2, "name": "Mira", "slot": 1, "is_host": false},
		{"id": 3, "name": "Kai", "slot": 2, "is_host": false},
	])
	Chat.contacts["dm/mira"] = "Mira"
	Chat._record("group", "Mira", "Kommst du mit zur Silberbucht?", false, "m1", "2026-11-25T21:41:00Z", false)
	Chat._record("group", "Ellie", "Klar! Bin gleich am Wegstein.", true, "m2", "2026-11-25T21:41:20Z", false)
	Chat._record("group", "Kai", "[Ort] Windkap · Die Silberbucht (Tag 2, 22:05)", false, "m3", "2026-11-25T21:42:00Z", false)
	Chat._record("group", "Mira", "* winkt am Lagerfeuer *", false, "m4", "2026-11-25T21:42:15Z", false)
	Chat._record("dm/mira", "Mira", "Psst — hast du schon den Schleierfaden gefunden?", false, "m5", "2026-11-25T21:42:30Z", true)
	chat.call("_select", "group")
	(chat.get("_field") as LineEdit).text = "Unterwegs mit Fackel!"
	(chat.get("_field") as LineEdit).caret_column = 21
	chat.call("_on_field_changed", "Unterwegs mit Fackel!")
	await _wait(0.55)
	await _shot("chat_night_convo")

	# 3. Night slash-command autocomplete leaf
	(chat.get("_field") as LineEdit).text = "/"
	(chat.get("_field") as LineEdit).caret_column = 1
	chat.call("_on_field_changed", "/")
	await _wait(0.4)
	await _shot("chat_night_autocomplete")

	# 4. Day bright meadow contrast check
	TimeManager.set_time(0.45)
	(chat.get("_field") as LineEdit).text = ""
	chat.call("_on_field_changed", "")
	await _wait(0.8)
	await _shot("chat_day_convo")

	# 5. Night closed ambient whisper feed + unread spore bud
	TimeManager.set_time(0.92)
	chat.call("close_chat")
	await _wait(0.45)
	Chat._record("group", "Kai", "Achtung, ein Leerenhorcher am Klippenrand!", false, "m6", "2026-11-25T21:43:00Z", true)
	Chat._record("dm/mira", "Mira", "Ich bringe Mondtränke mit!", false, "m7", "2026-11-25T21:43:08Z", true)
	await _wait(0.55)
	await _shot("chat_night_ambient")

	# 6. Chat Transparency 30% (Night) vs 100% (Day)
	var prev_op: int = int(GameSettings.get_value("chat_opacity"))
	chat.call("open_chat")
	chat.call("_select", "group")
	GameSettings.set_value("chat_opacity", 30)
	await _wait(0.45)
	await _shot("chat_opacity_30")

	TimeManager.set_time(0.45)
	GameSettings.set_value("chat_opacity", 100)
	await _wait(0.55)
	await _shot("chat_opacity_100")
	GameSettings.set_value("chat_opacity", 85)

	# 7. Admin contextual autocomplete (/tp ) + DEV badge at night
	TimeManager.set_time(0.92)
	(chat.get("_field") as LineEdit).text = "/tp "
	(chat.get("_field") as LineEdit).caret_column = 4
	chat.call("_on_field_changed", "/tp ")
	await _wait(0.45)
	await _shot("chat_admin_autocomplete")

	# 8. Admin command execution (/god, /admin, /announce) with ADM badge & golden replies
	CloudSession.token = "preview_tok"
	CloudSession.user_id = "preview_uid"
	CloudSession.role = "admin"
	chat.call("_submit", "/god on")
	chat.call("_submit", "/admin spieler")
	chat.call("_submit", "/announce Blutmond erhebt sich über Windkap!")
	await _wait(0.6)
	await _shot("chat_admin_reply")
	CloudSession.token = ""
	CloudSession.user_id = ""
	CloudSession.role = "player"

	# 9. Settings UI showing CHAT-SICHTBARKEIT slider in Feldcodex SystemTab
	chat.call("close_chat")
	GameSettings.set_value("chat_opacity", 65)
	var game_menu: GameMenu = hud.get_node_or_null("GameMenu") as GameMenu
	if game_menu != null:
		game_menu.open_tab("system", true)
		await _wait(0.45)
		await _shot("settings_chat_slider")
		game_menu.close(true)

	GameSettings.set_value("chat_opacity", prev_op)
	NetworkManager._roster.clear()
	print("PREVIEW CHAT OK")
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _shot(name_id: String) -> void:
	if out_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return
	var path: String = out_dir.path_join(name_id + ".png")
	img.save_png(path)
	print("SAVED ", path)
