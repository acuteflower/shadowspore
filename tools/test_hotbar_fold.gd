extends Node
## The hotbar folds away after Hotbar.FOLD_DELAY s without switching and unfolds almost at once.
## `Godot --path . tools/test_hotbar_fold.tscn [-- --capture=/abs/folder]` (headless works without captures). Prints `HOTBAR FOLD OK`.

var failures: int = 0
var folder: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			folder = arg.trim_prefix("--capture=")
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)


func _shot(name: String) -> void:
	if folder == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(name))


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.quests.set_flag("hud_unlocked")
	world.finish_opening()
	var hud: Node = player._hud
	var bar: Hotbar = hud.get_node("Hotbar") as Hotbar
	var health: Control = hud.get_node("HealthBar") as Control
	var stamina: Control = hud.get_node("StaminaBar") as Control
	var health_x: float = health.offset_left
	var stamina_x: float = stamina.offset_left
	var bar_top: float = bar.offset_top
	await get_tree().create_timer(3.0).timeout
	check(bar.shown > 0.99 and bar.drop == 0.0 and bar.inset == 0.0, "open while fresh")
	await _shot("hotbar_open.png")

	bar._quiet = Hotbar.FOLD_DELAY - 0.1 ## skip the wait
	await get_tree().create_timer(0.5).timeout
	check(bar.shown < 1.0, "pendants start to fade after the delay")
	await get_tree().create_timer(1.0).timeout
	check(bar.shown < 0.02 and bar.drop == Hotbar.DROP and bar.inset == Hotbar.NARROW, "folded: pendants gone, branch down and narrow")
	check(not bar.get_slots()[0].visible, "folded slots take no clicks")
	check(is_equal_approx(bar.offset_top, bar_top + Hotbar.DROP), "hotbar node dropped")
	check(is_equal_approx(health.offset_left, health_x + Hotbar.NARROW) and is_equal_approx(stamina.offset_left, stamina_x - Hotbar.NARROW), "sap vines follow the narrowed vine")
	await _shot("hotbar_folded.png")

	bar.wake() ## as a scroll does
	await get_tree().create_timer(0.12).timeout
	check(bar.shown > 0.99 and bar.drop == 0.0 and bar.inset == 0.0, "unfolds almost at once")
	check(bar.get_slots()[0].visible and is_equal_approx(health.offset_left, health_x), "slots and sap vines back")

	InputManager.inventory_open = true
	bar._quiet = Hotbar.FOLD_DELAY + 5.0
	await get_tree().create_timer(0.3).timeout
	check(bar.shown > 0.99, "stays open while the inventory is open")
	InputManager.inventory_open = false

	print("HOTBAR FOLD OK" if failures == 0 else "HOTBAR FOLD: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
