extends Node2D
## Visual showcase of the 6 animated sword swing VFX on Ellie (Forehand, Backhand, Thrust,
## Aufwärtshieb, Wirbelklinge, Heavy Wuchtschlag).
## Usage:
##   Godot --rendering-driver opengl3 --path . tools/preview_sword_slashes.tscn -- --capture=/abs.png [--item=sword_iron] [--mode=combos|facings] [--step=0] [--night]

const LABELS_COMBO: PackedStringArray = [
	"1 Forehand",
	"2 Backhand",
	"3 Thrust",
	"4 Aufwaerts",
	"5 Wirbel",
	"6 Wuchtschlag",
]
const FOUR_DIRS: Array[int] = [0, 2, 4, 6] # E, S, W, N


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var item: String = _arg(args, "--item=", "sword_iron")
	var mode: String = _arg(args, "--mode=", "combos")
	var step_idx: int = int(_arg(args, "--step=", "0"))
	var night: bool = args.has("--night")

	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("18152c") if night else Color("3e7652")
	add_child(bg)

	if night:
		var cm: CanvasModulate = CanvasModulate.new()
		cm.color = Color("3a3466")
		add_child(cm)

	var header: Label = Label.new()
	header.text = "%s | %s%s" % [item, mode, " (night)" if night else " (day)"]
	header.position = Vector2(6, 3)
	header.material = Unlit.material()
	header.add_theme_font_size_override("font_size", 8)
	add_child(header)

	if mode == "combos":
		await _build_combos(item, Vector2.RIGHT, 0)
	elif mode == "combos_north":
		await _build_combos(item, Vector2.UP, 6)
	elif mode == "combos_ne":
		await _build_combos(item, Vector2(1.0, -1.0).normalized(), 7)
	else:
		await _build_facings(item, step_idx)

	for arg: String in args:
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			get_tree().quit()


## 6 rows (all 6 sword attacks) x 6 columns (keyframes from ignition -> peak -> breakup -> star glints).
func _build_combos(item: String, dir: Vector2, sector: int) -> void:
	var players: Array[Player] = []
	var rows: int = 6
	var cols: int = 6
	# Unlock combo steps 4 & 5 visually for preview
	for r: int in rows:
		var lbl: Label = Label.new()
		lbl.text = LABELS_COMBO[r]
		lbl.position = Vector2(4, 24 + r * 57)
		lbl.material = Unlit.material()
		lbl.add_theme_font_size_override("font_size", 7)
		add_child(lbl)
		for c: int in cols:
			var p: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
			p.name = str(2 + r * cols + c)
			add_child(p)
			p.set_physics_process(false)
			p.set_process(false)
			p.attack.set_process(false)
			p._camera.enabled = false
			p.scale = Vector2(1.0, 1.0)
			p.position = Vector2(105 + c * 98, 48 + r * 57)
			p.facing = dir
			p._sector = sector
			p.attack.held_weapon = item
			players.append(p)

	# Time moments AFTER active phase starts (seconds): ignition, peak, stretch, split, breakup, star glints
	var moments: Array[float] = [0.02, 0.06, 0.11, 0.17, 0.24, 0.31]
	for frame: int in 90:
		for i: int in players.size():
			var p: Player = players[i]
			var r: int = i / cols
			var c: int = i % cols
			var a: AttackComponent = p.attack
			if frame == 20:
				if r == 5:
					a._heavy_swing(dir, item, 1.0, false)
				else:
					a._swing(dir, item, r)
			var windup_f: float = float(a._step.get("windup", 0.07)) * 60.0 if not a._step.is_empty() else 4.0
			var stop_f: float = 20.0 + windup_f + moments[c] * 60.0
			if frame < 20 or float(frame) < stop_f:
				p._animate(1.0 / 60.0)
				a._advance(1.0 / 60.0)
				a._update_pose(1.0 / 60.0)
				a._update_motes(1.0 / 60.0)
				a._trail.queue_redraw()
		await get_tree().process_frame


## 4 rows (E, S, W, N) x 6 moments of a chosen step at 1.5x scale so we can verify directional alignment with the blade!
func _build_facings(item: String, step_idx: int) -> void:
	var players: Array[Player] = []
	var rows: int = 4
	var cols: int = 6
	var moments: Array[float] = [0.015, 0.055, 0.10, 0.16, 0.23, 0.30]
	for r: int in rows:
		for c: int in cols:
			var sec: int = FOUR_DIRS[r]
			var p: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
			p.name = str(2 + r * cols + c)
			add_child(p)
			p.set_physics_process(false)
			p.set_process(false)
			p.attack.set_process(false)
			p._camera.enabled = false
			p.scale = Vector2(1.5, 1.5)
			p.position = Vector2(62 + c * 102, 74 + r * 86)
			p.facing = Vector2.from_angle(float(sec) * PI / 4.0)
			p._sector = sec
			p.attack.held_weapon = item
			players.append(p)

	for frame: int in 90:
		for i: int in players.size():
			var p: Player = players[i]
			var c: int = i % cols
			var a: AttackComponent = p.attack
			if frame == 20:
				if step_idx == 5:
					a._heavy_swing(p.facing, item, 1.0, false)
				else:
					a._swing(p.facing, item, step_idx)
			var windup_f: float = float(a._step.get("windup", 0.07)) * 60.0 if not a._step.is_empty() else 4.0
			var stop_f: float = 20.0 + windup_f + moments[c] * 60.0
			if frame < 20 or float(frame) < stop_f:
				p._animate(1.0 / 60.0)
				a._advance(1.0 / 60.0)
				a._update_pose(1.0 / 60.0)
				a._update_motes(1.0 / 60.0)
				a._trail.queue_redraw()
		await get_tree().process_frame


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	for arg: String in args:
		if arg.begins_with(key):
			return arg.trim_prefix(key)
	return fallback
