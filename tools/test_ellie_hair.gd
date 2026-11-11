extends Node
## Integration check: Godot --headless --path . res://tools/test_ellie_hair.tscn
var failures: int = 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func is_hair(color: Color) -> bool:
	for hair: Color in [Color("8f84c2"), Color("bdb3e4"), Color("e9e3f7"), Color("fffaf0")]:
		if color.is_equal_approx(hair):
			return true
	return false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	add_child(player)
	player.set_physics_process(false)
	var sheet: Image = player._sprite.texture.get_image()
	check(sheet.get_size() == Vector2i(1056, 896), "main sheet keeps its expected frame layout")
	check(player._rig_hand.size() == 352 and player._rig_shoulder.size() == 352, "all main-sheet hand and shoulder points load")
	for sector: int in 8:
		var direction: Vector2 = Vector2.RIGHT.rotated(float(sector) * PI / 4.0)
		player.facing = direction
		player.velocity = direction * player.sprint_speed
		player.sprinting = true
		player._gait = 2
		player._sector = sector
		var masks: Array[PackedByteArray] = []
		for phase: int in 6:
			player._walk_time = float(phase)
			player._last_step = phase
			player._animate(0.0)
			check(player._sprite.frame == sector * Player.SHEET_COLS + 6 + phase, "sector %d jog phase %d selects the correct sprite" % [sector, phase])
			var mask: PackedByteArray = PackedByteArray()
			for y: int in range(5, 43):
				for x: int in 48:
					mask.append(1 if is_hair(sheet.get_pixel((6 + phase) * 48 + x, sector * 56 + y)) else 0)
			masks.append(mask)
		var changed: int = 0
		for i: int in masks[0].size():
			if masks[0][i] != masks[3][i]:
				changed += 1
		check(changed >= 5, "sector %d hair changes visibly between opposite foot contacts (%d pixels)" % [sector, changed])
	player.facing = Vector2.RIGHT
	player.velocity = Vector2.RIGHT * player.sprint_speed
	player._sector = 0
	player._walk_time = 0.0
	player._last_step = -1
	player._animate(0.1)
	check(is_equal_approx(player._walk_time, 1.0 + player.jog_fps * 0.1), "sprint animation sets off from the push-off frame at its configured speed")
	# A sprint throttled below sprint speed (Hexenwald mist, slow ground) switches to the jog cycle after a short hold, keeping the stride.
	player.velocity = Vector2.RIGHT * player.sprint_speed * 0.72
	for i: int in 4:
		player._animate(0.05)
	check(player._gait == 1 and player._sprite.frame - player._sector * Player.SHEET_COLS >= Player.JOG_COL, "a throttled sprint plays the jog cycle")
	player.velocity = Vector2.RIGHT * player.max_speed
	for i: int in 4:
		player._animate(0.05)
	check(player._gait == 0, "walking speed falls back to the walk cycle")
	# Stopping mid-stride finishes the step before the idle loop.
	player.velocity = Vector2.RIGHT * player.max_speed
	player._walk_time = 2.9
	player._animate(0.02)
	player.velocity = Vector2.ZERO
	player._animate(0.02)
	check(player._last_step >= 0 and player._sprite.frame - player._sector * Player.SHEET_COLS < Player.IDLE_COL, "a stopping stride runs on for a moment")
	for i: int in 20:
		player._animate(0.02)
	check(player._last_step == -1, "the stride settles into the idle loop")
	player.velocity = Vector2.ZERO
	player._idle_time = 0.0
	player._animate(0.3)
	check(player._sprite.frame == Player.IDLE_COL + 1, "idle animation continues when standing")
	check((player._sprite.material as ShaderMaterial).get_shader_parameter("blood_map") == Player.BLOOD_MAPS[0], "blood map remains attached to the main sheet")
	player.show_faint_frame(0, true)
	check(player._sprite.vframes == 2 and player._sprite.frame_coords.y == 1 and not player._sprite.flip_h, "fainting uses its real west-facing row")
	check(Player.FAINT_SHEET.get_size() == Player.FAINT_BLOOD.get_size(), "fainting blood map matches both facing rows")
	player.show_sit_frame(0, 4)
	check(player._sprite.vframes == 8 and player._sprite.frame_coords.y == 4 and not player._sprite.flip_h, "sitting uses its real west-facing row")
	player.show_carry_frame(0, true)
	check(player._sprite.vframes == 2 and player._sprite.frame_coords.y == 1 and not player._sprite.flip_h, "carrying uses its real west-facing row")
	print("ELLIE HAIR: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
