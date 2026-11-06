extends Node
## Godot --headless --path . res://tools/test_adventurer_art.tscn
var failures: int = 0
var strike_count: int = 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var knight: Adventurer = Adventurer.new()
	add_child(knight)
	knight.set_process(false)
	var rig: Dictionary = DataRegistry.table("adventurer_rig")
	var frames: int = int(rig.frames)
	check(Adventurer.SHEET.get_size() == Vector2(frames * 84, 800), "all eight character rows have the expected dimensions")
	check(Adventurer.SHEET.get_size() == Adventurer.GLOW.get_size(), "glow and character atlases have the same layout")
	check(knight._sprite.offset == Vector2(0, -34), "the foot anchor remains at the scene origin")
	for sector: int in 8:
		var direction: Vector2 = Vector2.RIGHT.rotated(float(sector) * PI / 4.0)
		knight.play("walk", direction)
		check(knight._sector == sector and knight._sprite.frame == sector * frames + int(rig.clips.walk.start), "walk selects sector %d" % sector)
		check(knight._sprite.frame == knight._glow.frame and not knight._sprite.flip_h, "sector %d keeps glow aligned and is not mirrored" % sector)
	var follow: KnightWalkScene = KnightWalkScene.new()
	follow._knight = knight
	follow._play("walk", Vector2.RIGHT)
	knight._clip_time = 0.25
	follow._play("walk", Vector2.DOWN)
	check(is_equal_approx(knight._clip_time, 0.25) and knight._sector == 2, "turning while walking preserves stride phase")
	knight.walk_speed_scale = 0.6
	knight._process(0.1)
	check(is_equal_approx(knight._clip_time, 0.31), "walk cadence follows the scene speed")
	follow._play("stand", Vector2.DOWN)
	check(is_zero_approx(knight._clip_time) and is_equal_approx(knight.walk_speed_scale, 1.0), "changing clips resets timing and cadence")
	knight.strike.connect(func() -> void: strike_count += 1)
	knight.play("slash_a", Vector2.RIGHT)
	knight._process(2.1 / float(rig.clips.slash_a.fps))
	knight._process(0.01)
	check(strike_count == 1, "sword strike fires once at the preserved contact frame")
	knight.play("mine", Vector2.RIGHT)
	knight._process(6.1 / float(rig.clips.mine.fps))
	check(strike_count == 2, "mining retains its contact frame")
	follow.free()
	print("ADVENTURER ART: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
