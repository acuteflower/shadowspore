extends Node
## Checks the held-item system (docs/griff_system.md): GripRig geometry, the arm painter, rest holds, swings without spinning, turning with weight.
##   Godot --headless --path . tools/test_grip.tscn [-- --dump]     prints GRIP OK
var failures: int = 0
var checks: int = 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _ready() -> void:
	_geometry()
	_painter(OS.get_cmdline_user_args().has("--dump"))
	var t0: int = Time.get_ticks_usec()
	var fwd: Vector2 = Vector2.from_angle(0.6)
	var sh: Vector3 = GripRig.shoulder_3d(Vector2(-4, -31), fwd)
	for i: int in 200:
		var fist: Vector3 = GripRig.hand_3d(Vector2(-5 + i % 3, -21), sh, fwd)
		var arm: Array[Vector3] = GripRig.arm(sh, fist, GripRig.pole(fwd))
		ArmPainter.raster(sh, arm[0], arm[1], arm[2])
	var per: float = float(Time.get_ticks_usec() - t0) / 200.0
	print("arm raster: %.0f us per frame" % per)
	check(per < 1500.0, "painting the arm is cheap (%.0f us)" % per)
	await _player_checks()
	print("%d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("GRIP OK")
	get_tree().quit(1 if failures > 0 else 0)


func _geometry() -> void:
	# projection agrees with the hero renderer: up is mostly up, toward the camera is short and down
	check(GripRig.project_dir(Vector3(0, 0, 1)).is_equal_approx(Vector2(0, -GripRig.COSP)), "up projects up")
	check(absf(GripRig.project_dir(Vector3(0, 1, 0)).y - GripRig.SINP) < 0.001, "toward the camera is foreshortened")
	var back: Vector3 = GripRig.lift(Vector2(3, -20), 2.5)
	check(GripRig.screen(back).is_equal_approx(Vector2(3, -20)) and is_equal_approx(back.y, 2.5), "lift inverts screen")
	# a blade at the aim pitch shows on the aim line, for every aim
	for i: int in 16:
		var aim: Vector2 = Vector2.from_angle(TAU * i / 16.0)
		var shown: Vector2 = GripRig.project_dir(GripRig.dir(aim.angle(), GripRig.aim_pitch(aim)))
		check(shown.normalized().dot(aim) > 0.999 and shown.length() > 0.8, "contact reads on the aim %d" % i)
	# the arm keeps its lengths and its reach
	for sector: int in 8:
		var fwd: Vector2 = Vector2.from_angle(sector * PI / 4.0)
		var sh: Vector3 = GripRig.shoulder_3d(Vector2(-4, -31), fwd)
		var fist: Vector3 = GripRig.hand_3d(Vector2(-5, -21), sh, fwd)
		var arm: Array[Vector3] = GripRig.arm(sh, fist + Vector3(0, 0, 0), GripRig.pole(fwd))
		check(absf(arm[0].distance_to(sh) - GripRig.UPPER) < 0.05, "upper arm length %d" % sector)
		check(arm[2].distance_to(sh) <= GripRig.UPPER + GripRig.FORE + GripRig.PALM + 0.01, "reach %d" % sector)
		check(arm[0].z < sh.z, "the elbow hangs below the shoulder %d" % sector)
		var far: Array[Vector3] = GripRig.arm(sh, sh + Vector3(40, 0, 0), GripRig.pole(fwd))
		check(far[2].distance_to(sh) < GripRig.UPPER + GripRig.FORE + GripRig.PALM, "out of reach is clamped %d" % sector)
	# swing planes: a flat cut stays level, an overhead chop passes over the head
	var aim_e: Vector2 = Vector2.RIGHT
	var contact: Vector3 = GripRig.dir(0.0, 0.0)
	check(absf(GripRig.swing_dir(contact, aim_e, 0.0, 1.0).z) < 0.001, "a flat sweep stays level")
	check(GripRig.swing_dir(contact, aim_e, deg_to_rad(80.0), 1.4).z > 0.9, "an overhead chop goes over the head")
	check(GripRig.swing_dir(contact, aim_e, deg_to_rad(24.0), 1.0).y > 0.5, "positive theta is her right side")


func _painter(dump: bool) -> void:
	for sector: int in 8:
		var fwd: Vector2 = Vector2.from_angle(sector * PI / 4.0)
		var sh: Vector3 = GripRig.shoulder_3d(Vector2(-4, -31), fwd)
		var fist: Vector3 = GripRig.hand_3d(Vector2(-5, -21), sh, fwd)
		var arm: Array[Vector3] = GripRig.arm(sh, fist, GripRig.pole(fwd))
		var img: Dictionary = ArmPainter.raster(sh, arm[0], arm[1], arm[2])
		var codes: PackedInt32Array = img["codes"]
		var filled: PackedByteArray = img["filled"]
		var w: int = img["w"]
		var body: int = 0
		var ink: int = 0
		var mats: Dictionary = {}
		for i: int in codes.size():
			if codes[i] >= 0:
				body += 1
				mats[codes[i] / 4] = true
			elif filled[i] == 1:
				ink += 1
		check(body >= 14, "sector %d paints an arm (%d px)" % [sector, body])
		check(ink >= body / 2, "sector %d has an outline" % sector)
		check(mats.has(ArmPainter.COAT) and mats.has(ArmPainter.LEATHER), "sector %d has sleeve and leather" % sector)
		if dump:
			print("sector ", sector)
			for y: int in int(img["h"]):
				var line: String = ""
				for x: int in w:
					var c: int = codes[y * w + x]
					line += ("." if filled[y * w + x] == 0 else "o") if c < 0 else "abcdefghijklmnop"[c]
				print(line)


func _player_checks() -> void:
	var p: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	p.name = "2"
	add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	p.attack.set_process(false)
	var a: AttackComponent = p.attack
	for item: String in ["sword_basic", "axe_basic", "pickaxe_basic", "sickle_basic", "hoe_basic", "watering_can"]:
		a.held_weapon = item
		for sector: int in 8:
			p._sector = sector
			p.facing = Vector2.from_angle(sector * PI / 4.0)
			a._since_swing = 0.0
			for f: int in 40:
				p._animate(1.0 / 60.0)
				a._update_pose(1.0 / 60.0)
			check(a._dir.is_normalized() and a._fist3.is_finite(), "%s rests finite (sector %d)" % [item, sector])
			# a swing: the blade never jumps more than a few rot steps per frame while it is long on screen (no clock-hand spin)
			var steps: int = 0
			var worst: float = 0.0
			var where: String = ""
			var last: float = a._blade_angle
			var last_dir: Vector3 = a._dir
			var fastest_windup: float = 0.0
			a._swing(p.facing, item, 0)
			while a._phase != AttackComponent.Phase.IDLE and steps < 200:
				p._animate(1.0 / 60.0)
				a._advance(1.0 / 60.0)
				a._update_pose(1.0 / 60.0)
				var turned: float = absf(wrapf(a._blade_angle - last, -PI, PI))
				## the old clock-hand spin showed here: the picture turned far while the item hardly moved in space
				if a._phase == AttackComponent.Phase.RECOVERY and a._blade_length > 0.75 and turned - a._dir.angle_to(last_dir) / 0.75 > worst:
					worst = turned - a._dir.angle_to(last_dir) / 0.75
					where = "t %.3f len %.2f dir %s" % [a._time, a._blade_length, a._dir]
				if a._phase == AttackComponent.Phase.WINDUP:
					fastest_windup = maxf(fastest_windup, a._dir.angle_to(last_dir))
				last = a._blade_angle
				last_dir = a._dir
				steps += 1
			check(a._phase == AttackComponent.Phase.IDLE, "%s swing ends (sector %d)" % [item, sector])
			check(worst < 0.05, "%s no spin in the recovery (sector %d, %.2f rad/frame at %s)" % [item, sector, worst, where])
			check(fastest_windup < 0.75, "%s winds up through space, not in a snap (sector %d, %.2f rad/frame)" % [item, sector, fastest_windup])
			for f: int in 30: ## and it comes to rest without a jump
				p._animate(1.0 / 60.0)
				a._update_pose(1.0 / 60.0)
				var settle: float = absf(wrapf(a._blade_angle - last, -PI, PI))
				if a._blade_length > 0.75:
					check(settle < 0.5, "%s settles smoothly (sector %d, %.2f)" % [item, sector, settle])
				last = a._blade_angle
	# turning: the resting sword swings round with weight, it is not snapped
	a.held_weapon = "sword_basic"
	p._sector = 0
	p.facing = Vector2.RIGHT
	for f: int in 60:
		a._since_swing = 0.0
		p._animate(1.0 / 60.0)
		a._update_pose(1.0 / 60.0)
	var before: float = a._yaw
	p._sector = 4
	p.facing = Vector2.LEFT
	p._animate(1.0 / 60.0)
	a._update_pose(1.0 / 60.0)
	check(absf(wrapf(a._yaw - before, -PI, PI)) < 1.0, "a turn does not snap the blade")
	for f: int in 60:
		a._since_swing = 0.0
		p._animate(1.0 / 60.0)
		a._update_pose(1.0 / 60.0)
	var goal: Vector3 = GripRig.body_dir(Vector2.LEFT, deg_to_rad(22.0), deg_to_rad(26.0))
	check(a._dir.dot(goal) > 0.97, "after a second the blade rests in the new hold")
	# the arm material follows the sprite's (pallor, flash)
	(p._sprite.material as ShaderMaterial).set_shader_parameter("flash", 0.7)
	p._animate(1.0 / 60.0)
	check(is_equal_approx(float((a._arm.material as ShaderMaterial).get_shader_parameter("flash")), 0.7), "the arm flashes with her")
	(p._sprite.material as ShaderMaterial).set_shader_parameter("flash", 0.0)
	a.set_arm_shown(false)
	check(not a.arm_shown() and not a._arm_sort.visible, "the arm hides with the item")
	a.set_arm_shown(true)
	p.queue_free()
	await get_tree().process_frame
