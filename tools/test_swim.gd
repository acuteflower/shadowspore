extends Node
## docs/schwimmen_konzept.md step 1: the pure swim rules, the SwimComponent state machine (hysteresis, tiredness, stamina, wounds, bans) and the
## player-only collision exceptions on the deep-water colliders.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("SWIM FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_rules()
	_machine()
	await _collision()
	_assets()
	await _player_clips()
	print("SWIM ", "OK" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


func _rules() -> void:
	var c: Dictionary = SwimRules.cfg()
	_check(float(c["enter_amount"]) > float(c["exit_amount"]), "enter threshold above exit threshold (hysteresis)")
	_check(not SwimRules.wants_swim(false, 0.85), "does not start below the enter amount")
	_check(SwimRules.wants_swim(false, 0.95), "starts above the enter amount")
	_check(SwimRules.wants_swim(true, 0.85), "keeps swimming between the two thresholds")
	_check(not SwimRules.wants_swim(true, 0.7), "stops below the exit amount")
	_check(SwimRules.technique(false, true, 50.0, false, false) == SwimRules.TREAD, "no input treads water")
	_check(SwimRules.technique(true, false, 50.0, false, false) == SwimRules.BREAST, "input swims breaststroke")
	_check(SwimRules.technique(true, true, 50.0, false, false) == SwimRules.CRAWL, "sprint crawls")
	_check(SwimRules.technique(true, true, 0.0, false, false) == SwimRules.BREAST, "no stamina: no crawl")
	_check(SwimRules.technique(true, true, 50.0, true, false) == SwimRules.BREAST, "tired: no crawl")
	_check(SwimRules.technique(true, true, 50.0, false, true) == SwimRules.BREAST, "wounded: no crawl")
	var walk: float = 62.0
	_check(SwimRules.speed(SwimRules.CRAWL, false, false) > SwimRules.speed(SwimRules.BREAST, false, false), "the crawl is faster than the breaststroke")
	_check(SwimRules.speed(SwimRules.CRAWL, false, false) < walk, "swimming is slower than walking")
	_check(SwimRules.speed(SwimRules.BREAST, true, false) < SwimRules.speed(SwimRules.BREAST, false, false), "tired is slower")
	_check(SwimRules.speed(SwimRules.BREAST, false, true) < SwimRules.speed(SwimRules.BREAST, false, false), "wounded is slower")
	_check(SwimRules.speed(SwimRules.TREAD, false, false) == 0.0, "treading stands still")
	_check(SwimRules.cost(SwimRules.CRAWL) > SwimRules.cost(SwimRules.BREAST) and SwimRules.cost(SwimRules.TREAD) == 0.0, "the crawl costs most, treading nothing")
	_check(SwimRules.next_tired(false, 0.0, 100.0), "empty stamina tires")
	_check(SwimRules.next_tired(true, 5.0, 100.0), "stays tired below the resume share")
	_check(not SwimRules.next_tired(true, 20.0, 100.0), "recovers above the resume share")


func _make_swimmer() -> Array:
	var body: CharacterBody2D = CharacterBody2D.new()
	add_child(body)
	var stamina: StaminaComponent = StaminaComponent.new()
	body.add_child(stamina)
	var swimmer: SwimComponent = SwimComponent.new()
	body.add_child(swimmer)
	swimmer.setup(body)
	return [body, stamina, swimmer]


func _machine() -> void:
	var made: Array = _make_swimmer()
	var body: CharacterBody2D = made[0]
	var stamina: StaminaComponent = made[1]
	var swimmer: SwimComponent = made[2]
	var enters: Array[String] = []
	swimmer.transition.connect(func(kind: String) -> void: enters.append(kind))
	# On foot: shallow water does not start it.
	for i: int in 30:
		swimmer.step(0.05, 0.5, true, true, true, false, stamina, false)
	_check(swimmer.state == SwimRules.NONE and not swimmer.active, "shallow water: on foot")
	# Deep, a ban: cannot start.
	for i: int in 30:
		swimmer.step(0.05, 1.0, true, false, true, false, stamina, false)
	_check(not swimmer.active, "a ban keeps her from starting")
	# Deep and allowed: starts, blends in.
	var state: int = SwimRules.NONE
	for i: int in 30:
		state = swimmer.step(0.05, 1.0, true, true, true, false, stamina, false)
	_check(state == SwimRules.BREAST and swimmer.active, "deep water: breaststroke")
	_check(swimmer.blend >= 0.99, "the blend reaches swimming")
	_check(enters == ["enter"], "one enter event")
	# A ban afterwards does not throw her out.
	state = swimmer.step(0.05, 1.0, true, false, true, false, stamina, false)
	_check(state == SwimRules.BREAST, "a swimmer is not thrown out by a ban")
	# Sprint crawls and drains.
	var before: float = stamina.current
	for i: int in 20:
		state = swimmer.step(0.05, 1.0, true, true, true, true, stamina, false)
	_check(state == SwimRules.CRAWL, "sprint crawls")
	_check(stamina.current < before - 10.0, "the crawl drains stamina (%.1f -> %.1f)" % [before, stamina.current])
	# Empty stamina: tired, back to the breaststroke only.
	stamina.current = 0.0
	state = swimmer.step(0.05, 1.0, true, true, true, true, stamina, false)
	_check(state == SwimRules.BREAST and swimmer.tired, "empty stamina: tired, breaststroke")
	stamina.current = 3.0
	state = swimmer.step(0.05, 1.0, true, true, true, true, stamina, false)
	_check(state == SwimRules.BREAST, "still tired at 3 %")
	stamina.current = 60.0
	state = swimmer.step(0.05, 1.0, true, true, true, true, stamina, false)
	_check(state == SwimRules.CRAWL and not swimmer.tired, "recovered: the crawl is back")
	# No input: treading.
	state = swimmer.step(0.05, 1.0, true, true, false, false, stamina, false)
	_check(state == SwimRules.TREAD, "no input: treading")
	# Hysteresis: 0.85 keeps swimming, 0.7 stops (after the minimum time).
	for i: int in 10:
		state = swimmer.step(0.05, 0.85, true, true, true, false, stamina, false)
	_check(swimmer.active, "0.85 keeps swimming")
	for i: int in 10:
		state = swimmer.step(0.05, 0.7, true, true, true, false, stamina, false)
	_check(not swimmer.active and state == SwimRules.NONE, "0.7: back on foot")
	_check(enters == ["enter", "exit"], "enter then exit events: %s" % str(enters))
	for i: int in 20:
		swimmer.step(0.05, 0.7, true, true, true, false, stamina, false)
	_check(swimmer.blend <= 0.01, "the blend returns to wading")
	# Reset.
	swimmer.step(0.05, 1.0, true, true, true, false, stamina, false)
	swimmer.reset()
	_check(not swimmer.active and swimmer.blend == 0.0, "reset: on foot")
	body.queue_free()


func _wall() -> StaticBody2D:
	var wall: StaticBody2D = StaticBody2D.new()
	wall.add_to_group("river_depth")
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(64, 64)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector2(48, 0)
	add_child(wall)
	return wall


func _walker(at: Vector2) -> CharacterBody2D:
	var body: CharacterBody2D = CharacterBody2D.new()
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


func _collision() -> void:
	var wall: StaticBody2D = _wall()
	var made: Array = _make_swimmer()
	var swimmer_body: CharacterBody2D = made[0]
	var stamina: StaminaComponent = made[1]
	var swimmer: SwimComponent = made[2]
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	swimmer_body.add_child(shape)
	swimmer_body.position = Vector2(0, 0)
	var other: CharacterBody2D = _walker(Vector2(0, 20))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(swimmer_body.test_move(swimmer_body.global_transform, Vector2(40, 0)), "before: the wall blocks the swimmer")
	_check(other.test_move(other.global_transform, Vector2(40, 0)), "before: the wall blocks the other body")
	# In the water and allowed: exceptions are set up on the first scan.
	swimmer.step(0.3, 0.5, true, true, true, false, stamina, false)
	_check(swimmer.exception_count() == 1, "one exception for the one wall (%d)" % swimmer.exception_count())
	await get_tree().physics_frame
	_check(not swimmer_body.test_move(swimmer_body.global_transform, Vector2(40, 0)), "the swimmer passes the deep-water wall")
	_check(other.test_move(other.global_transform, Vector2(40, 0)), "an animal or enemy is still blocked")
	# Back on land, with no swimming: exceptions are given back.
	swimmer.step(0.3, 0.0, false, true, true, false, stamina, false)
	_check(swimmer.exception_count() == 0, "left the water: no exceptions")
	await get_tree().physics_frame
	_check(swimmer_body.test_move(swimmer_body.global_transform, Vector2(40, 0)), "on land the wall blocks again")
	# A freed wall is dropped from the list.
	swimmer.step(0.3, 0.5, true, true, true, false, stamina, false)
	_check(swimmer.exception_count() == 1, "again one exception")
	wall.free()
	swimmer.step(0.3, 0.5, true, true, true, false, stamina, false)
	_check(swimmer.exception_count() == 0, "an unloaded wall leaves the list")
	swimmer_body.queue_free()
	other.queue_free()


func _assets() -> void:
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("swim", {}) as Dictionary)
	var clips: Dictionary = rig.get("clips", {}) as Dictionary
	for clip: String in ["tread", "breast", "crawl", "enter", "t2b", "b2c", "dive", "shake"]:
		_check(clips.has(clip), "rig has the clip " + clip)
	var total: int = 0
	for clip: String in clips:
		total = maxi(total, int((clips[clip] as Dictionary)["start"]) + int((clips[clip] as Dictionary)["count"]))
	_check(total == int(rig.get("total", -1)), "clip ranges end at the sheet width (%d)" % total)
	var sheet: Texture2D = load("res://assets/characters/player_swim.png") as Texture2D
	_check(sheet.get_width() == total * 64 and sheet.get_height() == 8 * 72, "sheet is %d x 8 frames of 64x72" % total)
	for sound: String in ["dive_big", "dive_small", "stroke_a", "stroke_b", "kick", "breath", "bubble", "exit", "drip", "shake"]:
		_check(ResourceLoader.exists("res://assets/audio/swim/%s.wav" % sound), "sound " + sound)
	var cur: Dictionary = SwimRules.cfg().get("current", {}) as Dictionary
	_check(float(cur.get("max_drift", 1.0)) <= 0.18 + 0.001, "the drift is capped at 18 % of the walking speed")


func _player_clips() -> void:
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	await get_tree().process_frame
	player.swim = SwimRules.TREAD
	player.swimmer.blend = 1.0
	var total: int = int((player._swim_rig as Dictionary).get("total", 0))
	for i: int in 12:
		player._animate(0.05)
	_check(player._sheet == 13, "swimming draws sheet 13")
	_check(player._sprite.frame < 8 * total and player._sprite.frame >= 0, "swim frame in range")
	_check(player._swim_trans == "" or player._swim_trans == "enter", "a standing start plays enter, not the dive")
	player.swim = SwimRules.CRAWL
	for i: int in 40:
		player._animate(0.05)
	_check(player._swim_level == 2, "the technique stepped up to the crawl (level %d)" % player._swim_level)
	player.swim = SwimRules.NONE
	player._swim_swum = 3.0
	for i: int in 30:
		player._animate(0.05)
	_check(player._swim_shake_t >= 0.0 or player._sheet != 13, "after a long swim she shakes it off or is already back on foot")
	for i: int in 40:
		player._animate(0.05)
	_check(player._sheet != 13, "back on the normal sheet when the shake is over")
	player.queue_free()
