extends Node
## The wisp trail (docs/raetsel_konzept.md section 1) without a world: a stand-in follower walks after the wisp. Checks waking, the route
## (hops, hovers, lingering, waiting when she falls behind), fright (dart ahead, shy), going out (too shy / left alone) and coming back, the dive,
## the chest that comes down at the end, and save export/import. At the end the real world is loaded once to see the trail is placed.
## Run: Godot --headless --path . --fixed-fps 60 tools/test_wisp.tscn   (prints WISP OK)

var _ok: bool = true
var _follower: Dictionary = {"pos": Vector2.ZERO, "sneak": false, "loud": false}
var _trail: WispTrail
var _puzzles: Puzzles
var _chests: LootChests


func check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("WISP FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


## Walk the stand-in towards `goal` at `speed` px/s for at most `seconds`, keeping `keep` px away; stops early when `until` says so.
func _walk(speed: float, seconds: float, keep: float, until: Callable) -> void:
	var t: float = 0.0
	while t < seconds:
		var dt: float = get_process_delta_time()
		t += dt
		var goal: Vector2 = _trail.ground_position()
		var pos: Vector2 = _follower.pos as Vector2
		var d: float = pos.distance_to(goal)
		if d > keep:
			_follower.pos = pos.move_toward(goal, minf(speed * dt, d - keep))
		if until.is_valid() and bool(until.call()):
			return
		await get_tree().process_frame


func _run() -> void:
	Engine.time_scale = 4.0
	var root: Node2D = Node2D.new()
	add_child(root)
	_chests = LootChests.new()
	_chests.name = "LootChests"
	root.add_child(_chests)
	_puzzles = Puzzles.new()
	_puzzles.name = "Puzzles"
	root.add_child(_puzzles)
	await _frames(2)
	check(not _puzzles.ids().is_empty(), "puzzles.json places a wisp trail")
	if _puzzles.ids().is_empty():
		_finish()
		return
	var id: String = String(_puzzles.ids()[0])
	_trail = _puzzles.trial(id) as WispTrail
	_trail.followers = func() -> Array: return [_follower.duplicate()]
	check(_trail.route_length() > 900.0, "the route is long enough to be a trail (%d px)" % int(_trail.route_length()))
	var bowl: Vector2 = _trail.bowl_position()

	# asleep until she comes close
	_follower.pos = bowl + Vector2(0, 160)
	await _frames(30)
	check(_trail.state == WispTrail.State.SLEEP, "it sleeps while nobody is near")
	_follower.pos = bowl + Vector2(0, 50)
	await _frames(5)
	check(_trail.state == WispTrail.State.WAKE, "it wakes when she comes close")

	# fright: run at it
	await _walk(62.0, 15.0, 60.0, func() -> bool: return _trail.state == WispTrail.State.HOVER)
	check(_trail.state == WispTrail.State.HOVER, "it flew to its first stop and hovers")
	var before: float = _trail.s
	_follower.loud = true
	_follower.pos = _trail.ground_position() + Vector2(0, 50)
	await _frames(3)
	check(_trail.state == WispTrail.State.DART and _trail.shy == 1, "a sprint near it frightens it (dart, shy 1)")
	_follower.loud = false
	await _walk(62.0, 6.0, 70.0, func() -> bool: return _trail.state == WispTrail.State.HOVER)
	check(_trail.s > before + 100.0, "a fright sends it ahead along the route")
	_follower.pos = _trail.ground_position() + Vector2(0, 12)
	await _frames(3)
	_follower.pos = _trail.ground_position() + Vector2(0, 90)
	await _walk(62.0, 6.0, 80.0, func() -> bool: return _trail.state == WispTrail.State.HOVER)
	_follower.pos = _trail.ground_position() + Vector2(0, 12)
	await _frames(3)
	check(_trail.state == WispTrail.State.LOST, "the third fright puts it out")
	await _walk(0.0, 12.0, 0.0, func() -> bool: return _trail.state == WispTrail.State.SLEEP)
	check(_trail.state == WispTrail.State.SLEEP and _trail.shy == 0 and _trail.s == 0.0, "it comes back to its bowl")

	# left alone: she walks away
	_follower.pos = bowl + Vector2(0, 50)
	await _walk(62.0, 4.0, 60.0, func() -> bool: return _trail.state == WispTrail.State.HOVER)
	_follower.pos = _trail.ground_position() + Vector2(0, 200)
	await _frames(20)
	check(_trail.calling, "it calls when she falls behind")
	_follower.pos = _trail.ground_position() + Vector2(0, 400)
	await _walk(0.0, 16.0, 0.0, func() -> bool: return _trail.state == WispTrail.State.LOST)
	check(_trail.state == WispTrail.State.LOST, "left alone too long it goes out")
	await _walk(0.0, 12.0, 0.0, func() -> bool: return _trail.state == WispTrail.State.SLEEP)

	# the whole trail, following quietly
	_follower.sneak = true
	_follower.pos = bowl + Vector2(0, 40)
	var lingered: Array = [false]
	await _walk(62.0, 200.0, 40.0, func() -> bool:
		if _trail.state == WispTrail.State.LINGER:
			lingered[0] = true
		return _trail.state == WispTrail.State.DIVE or _trail.state == WispTrail.State.LOST)
	check(lingered[0], "on the way it lingers over something curious")
	check(_trail.state == WispTrail.State.DIVE, "following quietly leads to the end (state %d, shy %d)" % [_trail.state, _trail.shy])
	await _walk(0.0, 5.0, 0.0, func() -> bool: return _trail.state == WispTrail.State.SOLVED)
	check(_trail.state == WispTrail.State.SOLVED, "it dives into the ground")
	check(_puzzles.is_solved(id), "the trial counts as solved")
	var chest: LootChest = _chests.chest("trial_" + id)
	check(chest != null and chest.arrive, "a chest comes down in the light")
	if chest != null:
		check(chest.position.distance_to(_trail.end_position()) < 1.0, "the chest stands where it sank in")
	check(_trail.end_position().distance_to(bowl) > 300.0, "the end lies far from the bowl")

	# save and load
	var saved: Dictionary = _puzzles.export_state()
	check((saved.get("solved", []) as Array).has(id), "the save keeps the solved trial")
	_puzzles.debug_reset(id)
	await _frames(2)
	check(not _puzzles.is_solved(id) and _trail.state == WispTrail.State.SLEEP and _chests.chest("trial_" + id) == null, "dev reset opens it again")
	_puzzles.import_state(saved)
	await _frames(2)
	check(_trail.state == WispTrail.State.SOLVED and _chests.chest("trial_" + id) != null, "a loaded save puts the cold bowl and the chest back")
	Engine.time_scale = 1.0

	# the real world places it
	root.queue_free()
	await _frames(2)
	var world: Node = (load("res://src/world/world_level.tscn") as PackedScene).instantiate()
	add_child(world)
	await _frames(3)
	var placed: Puzzles = Puzzles.of(get_tree())
	check(placed != null and placed.trial(id) != null, "the world has the trail")
	_finish()


func _finish() -> void:
	print("WISP OK" if _ok else "WISP FAILED")
	get_tree().quit(0 if _ok else 1)
