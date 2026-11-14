extends Node
## Captures ingame MultiplayerHud (bottom-left) and PauseMenu KOOP tab.
## `-- --dir=/abs/folder` -> writes `hud_mp.png` and `pause_koop.png`.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
	GameSettings.set_value("player_name", "ELLIE")
	NetworkManager.host_multiplayer(17965, "K7M4XP", 4, "preview_id", "WALDLICHTUNG", "")
	# Populate representative roster entries so HUD & KOOP tab show multi-player crew visually
	NetworkManager.set("_peer_names", {1: "ELLIE", 2: "MIRA", 3: "KAI"})
	NetworkManager.set("_peer_slots", {1: 0, 2: 1, 3: 2})
	NetworkManager.set("_roster", [
		{"id": 1, "name": "ELLIE", "is_host": true, "slot": 0},
		{"id": 2, "name": "MIRA", "is_host": false, "slot": 1},
		{"id": 3, "name": "KAI", "is_host": false, "slot": 2},
	])
	NetworkManager.session_changed.emit()

	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	var deadline: int = Time.get_ticks_msec() + 30000
	var player: Player = null
	while Time.get_ticks_msec() < deadline:
		player = world.get_node_or_null("Players/1") as Player
		if player != null:
			break
		await get_tree().process_frame
	if player == null:
		printerr("FAIL: player did not spawn")
		get_tree().quit(1)
		return
	var guide: Node = player.get_node_or_null("OpeningGuide")
	if guide != null:
		guide.set_process(false)
	var stumbles: Node = player.get_node_or_null("StumbleGuide")
	if stumbles != null:
		stumbles.set_process(false)
	if world.has_method("finish_opening"):
		world.call("finish_opening")
	TimeManager.unlock()
	TimeManager.time_of_day = 0.48
	for _i: int in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/hud_mp.png" % dir)

	var hud: CanvasLayer = player.get("_hud") as CanvasLayer
	var pause: PauseMenu = hud.get_node("PauseMenu") as PauseMenu
	pause.call("_set_open", true)
	pause.call("_select_tab", 4) # KOOP tab
	for _i: int in 65:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/pause_koop.png" % dir)

	NetworkManager.leave()
	print("preview multiplayer hud done")
	get_tree().quit(0)
