extends Node
## Godot --headless --path . res://tools/test_ellie_standby.tscn
var failures: int = 0

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2" ## no local HUD is needed for this isolated test
	add_child(player)
	player.set_physics_process(false)
	player.set_multiplayer_authority(1)
	check(player._rig_standby_hand.size() == 8 * Player.STANDBY_COLS and player._rig_standby_shoulder.size() == 8 * Player.STANDBY_COLS, "all eight directions have matching hand and shoulder positions")
	check(Player.STANDBY_SHEET.get_size() == Vector2(Player.STANDBY_COLS * 48, 8 * 56), "standby atlas has four 24-frame clips in eight directions")
	check(Player.STANDBY_SHEET.get_size() == Player.STANDBY_BLOOD.get_size(), "blood atlas matches standby sprites")
	for sector: int in 8:
		player.facing = Vector2.RIGHT.rotated(float(sector) * PI / 4.0)
		player._sector = sector
		for clip: int in Player.STANDBY_CLIPS:
			player._start_standby(clip)
			player._standby_time = 0.5
			player._animate(0.0)
			var index: int = sector * Player.STANDBY_COLS + clip * Player.STANDBY_FRAMES + 6
			check(player._sprite.texture == Player.STANDBY_SHEET and player._sprite.frame == index, "gesture %d selects sector %d and the correct phase" % [clip, sector])
			check(player.attack.rig_hand.is_equal_approx(player._rig_standby_hand[index] + Vector2(0.0, player._sink + player._limp_dip)), "gesture %d sector %d uses its hand rig" % [clip, sector])
			check((player._sprite.material as ShaderMaterial).get_shader_parameter("blood_map") == Player.STANDBY_BLOOD, "standby blood map is active")
	player.facing = Vector2.RIGHT
	player._sector = 0
	player._start_standby(0)
	player.velocity = Vector2(20, 0)
	player._animate(0.0)
	check(player._standby_clip == -1 and player._sprite.texture != Player.STANDBY_SHEET, "moving interrupts the gesture immediately")
	player.velocity = Vector2.ZERO
	player._start_standby(0)
	Input.action_press("move_right")
	player._animate(0.0)
	Input.action_release("move_right")
	check(player._standby_clip == -1, "trying to move interrupts the gesture even against an obstacle")
	player._start_standby(1)
	player._busy = true
	player._animate(0.0)
	check(player._standby_clip == -1, "interaction interrupts the gesture")
	player._busy = false
	player._start_standby(1)
	player.wounded = true
	player._animate(0.2)
	check(player._standby_clip == 1 and is_equal_approx(player._standby_time, 0.13), "wounded Ellie can make gestures more slowly")
	player.wounded = false
	player._start_standby(2)
	player.stealth.sneaking = true
	player._animate(0.0)
	check(player._standby_clip == -1, "sneaking interrupts the gesture")
	player.stealth.sneaking = false
	player._start_standby(1)
	player.attack._phase = AttackComponent.Phase.WINDUP
	player._animate(0.0)
	check(player._standby_clip == -1, "attacking interrupts the gesture")
	player.attack._phase = AttackComponent.Phase.IDLE
	player._start_standby(1)
	player.attack._since_swing = 1.0
	player._animate(0.0)
	check(player._standby_clip == -1, "gestures stay suppressed while the weapon is still out")
	player.attack._since_swing = AttackComponent.OUT_OF_COMBAT + 1.0
	player._start_standby(2)
	player.story_lock = true
	player._animate(0.0)
	check(player._standby_clip == -1, "story scenes interrupt the gesture")
	player.story_lock = false
	player._start_standby(2)
	InputManager.ui_blocking = true
	player._animate(0.0)
	check(player._standby_clip == -1, "open UI interrupts the local player's gesture")
	InputManager.ui_blocking = false
	player._standby_wait = 0.001
	player._idle_time = 1.5
	player._animate(0.01)
	check(player._standby_clip == -1 and is_zero_approx(player._standby_wait), "expired timer waits for the matching idle phase")
	player._idle_time = 0.0
	player._animate(0.0)
	check(player._standby_clip >= 0, "gesture begins at the matching idle phase")
	var last: int = player._standby_clip
	player._stop_standby()
	player._standby_last = last
	player._standby_wait = 0.0
	player._idle_time = 0.0
	player._animate(0.0)
	check(player._standby_clip >= 0 and player._standby_clip != last, "successive random gestures do not repeat")
	last = player._standby_clip
	var seen: Dictionary = {}
	player._standby_rng.seed = 1234
	for attempt: int in 60:
		player._stop_standby()
		player._standby_wait = 0.0
		player._idle_time = 0.0
		player._animate(0.0)
		check(player._standby_clip >= 0 and player._standby_clip != last, "random selection %d never repeats the last gesture" % attempt)
		last = player._standby_clip
		seen[last] = true
	check(seen.size() == 3, "all three gestures can be chosen")
	# When heated in Sonnenquarz-Öde, Ellie picks her 4th standby clip ('sweat' brow-wipe)
	player.heat_amount = 0.85
	player._stop_standby()
	player._standby_last = -1
	player._standby_wait = 0.0
	player._idle_time = 0.0
	player._animate(0.0)
	check(player._standby_clip == Player.HEAT_STANDBY_CLIP, "heated Ellie chooses the brow-wipe sweat standby gesture")
	player.heat_amount = 0.0
	player._stop_standby()
	player._start_standby(0)
	player._standby_time = 1.99
	player._animate(0.02)
	check(player._standby_clip == -1 and player._sprite.frame == Player.IDLE_COL, "completed gesture returns to the matching idle frame")
	player.set_multiplayer_authority(2)
	player._standby_wait = 0.0
	player._idle_time = 0.0
	player._animate(1.0)
	check(player._standby_clip == -1, "remote peers do not independently choose random gestures")
	player._start_standby(2)
	player._animate(0.5)
	check(player._standby_clip == 2 and player._sprite.texture == Player.STANDBY_SHEET, "remote peers play the authority's gesture")
	print("ELLIE STANDBY: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
