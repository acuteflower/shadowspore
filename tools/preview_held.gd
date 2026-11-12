extends Node2D
## Look study of the held-item system (docs/griff_system.md): Ellie at 2x in all eight facings.
##   Godot --rendering-driver opengl3 --path . tools/preview_held.tscn -- --capture=/abs.png [--item=sword_basic] [--mode=rest|swing|walk] [--step=0] [--night]
## rest:  rows carry / ready / sprint, columns E SE S SW W NW N NE.
## swing: rows = facings E S W N, columns = 8 moments of combo step `--step` (wind-up .. recovery).
## walk:  rows = facings E S W N (ready hold), columns = 8 moments of the walk cycle (the spring follows the fist).
const SECTOR_ORDER: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
const FOUR: Array[int] = [0, 2, 4, 6]
var players: Array[Player] = []


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var item: String = _arg(args, "--item=", "sword_basic")
	var mode: String = _arg(args, "--mode=", "rest")
	var step_index: int = int(_arg(args, "--step=", "0"))
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("3c5a3c")
	add_child(bg)
	var label: Label = Label.new()
	label.text = "%s  %s%s" % [item, mode, (" step %d" % step_index) if mode == "swing" else ""]
	label.position = Vector2(4, 2)
	label.add_theme_font_size_override("font_size", 8)
	add_child(label)
	var rows: int = 3 if mode == "rest" else 4
	for row: int in rows:
		for col: int in 8:
			var sector: int = SECTOR_ORDER[col] if mode == "rest" else FOUR[row]
			var p: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
			p.name = str(2 + row * 8 + col)
			add_child(p)
			p.set_physics_process(false)
			p.set_process(false)
			p.attack.set_process(false)
			p._camera.enabled = false
			p.scale = Vector2(2.0, 2.0)
			p.position = Vector2(40 + 80 * col, 112 + 116 * row) if rows == 3 else Vector2(40 + 80 * col, 96 + 86 * row)
			p.facing = Vector2.from_angle(float(sector) * PI / 4.0)
			p._sector = sector
			p.attack.held_weapon = item
			players.append(p)
	for frame: int in 90:
		for i: int in players.size():
			var p: Player = players[i]
			var row: int = i / 8
			var col: int = i % 8
			var a: AttackComponent = p.attack
			if mode == "rest":
				a._since_swing = 0.0 if row == 1 else 5.0
				p.velocity = Vector2.ZERO
				p._animate(1.0 / 60.0)
				a.carrying = row == 2
				a.facing = p.facing
				a._update_pose(1.0 / 60.0)
			elif mode == "walk":
				if p.has_meta("done"):
					continue
				a._since_swing = 0.0
				p.velocity = p.facing * 60.0
				p._animate(1.0 / 60.0)
				a._update_pose(1.0 / 60.0)
				if frame >= 60 + col * 3: ## freeze each column a little later in the cycle
					p.set_meta("done", true)
			else:
				if frame == 30:
					a._swing(p.facing, item, step_index)
				var total: float = 0.0
				if frame >= 30 and not a._step.is_empty():
					total = float(a._step["windup"]) + float(a._step["active"]) + float(a._step["recovery"])
				var stop: float = 30.0 + (total * 60.0) * (float(col) + 0.5) / 8.0
				if frame < 30 or float(frame) < stop:
					p._animate(1.0 / 60.0)
					a._advance(1.0 / 60.0)
					a._update_pose(1.0 / 60.0)
					if a._phase == AttackComponent.Phase.ACTIVE:
						a._trail_age = 0.0
					elif a._trail_age < AttackComponent.TRAIL_FADE:
						a._trail_age += 1.0 / 60.0
					a._trail.queue_redraw()
		await get_tree().process_frame
	for arg: String in args:
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			get_tree().quit()


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	for arg: String in args:
		if arg.begins_with(key):
			return arg.trim_prefix(key)
	return fallback
