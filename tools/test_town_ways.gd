extends Node
## docs/town.md: the natural trampled ways without a world (TownWays / TownPathArt): the way starts and ends where it should, keeps out of the obstacles, bends smoothly
## (no ruler line, no kink), is deterministic, keeps a person's distance from a wall, joins an older way at a shallow angle and ends there, and its picture is drawn.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN WAYS FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _length(p: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, p.size()):
		total += p[i - 1].distance_to(p[i])
	return total


## The sharpest turn between two neighbouring segments (degrees), ends left out.
func _kink(p: PackedVector2Array) -> float:
	var worst: float = 0.0
	for i: int in range(2, p.size() - 2):
		worst = maxf(worst, rad_to_deg(absf((p[i] - p[i - 1]).angle_to(p[i + 1] - p[i]))))
	return worst


func _inside(p: PackedVector2Array, rects: Array[Rect2]) -> bool:
	for pt: Vector2 in p:
		for r: Rect2 in rects:
			if r.has_point(pt):
				return true
	return false


func _run() -> void:
	var open: Callable = func(_p: Vector2) -> bool: return true
	var none: Array[PackedVector2Array] = []
	var no_solids: Array[Rect2] = []
	# --- open ground: a long, gently bent way, not a ruler line
	var door: Vector2 = Vector2(100, 200)
	var goal: Vector2 = Vector2(300, 120)
	var made: Dictionary = TownWays.route(door, goal, no_solids, open, none, 5)
	var way: PackedVector2Array = made.p as PackedVector2Array
	_check(way.size() > 10 and way[0].distance_to(door) < 0.01 and way[way.size() - 1].distance_to(goal) < 0.5, "a way runs from the door to the goal")
	_check(not bool(made.joined), "with nothing to join it runs to the goal")
	var straight: float = door.distance_to(goal)
	_check(_length(way) >= straight and _length(way) < straight * 1.2, "it is a little longer than the straight line, never a detour (%.0f vs %.0f)" % [_length(way), straight])
	var off: float = 0.0
	for pt: Vector2 in way:
		var along: Vector2 = Geometry2D.get_closest_point_to_segment(pt, door, goal)
		off = maxf(off, pt.distance_to(along))
	_check(off > 1.0, "it is not a ruler line (strays %.1f px)" % off)
	_check(_kink(way) < 30.0, "and has no kink (%.0f degrees)" % _kink(way))
	var again: Dictionary = TownWays.route(door, goal, no_solids, open, none, 5)
	_check((again.p as PackedVector2Array) == way, "the same inputs give the same way")
	var other: Dictionary = TownWays.route(door, goal, no_solids, open, none, 6)
	_check((other.p as PackedVector2Array) != way, "another seed bends it another way")
	# --- a wall in the middle: round it, at a distance, smoothly
	var wall: Rect2 = Rect2(180, 120, 24, 100)
	var walls: Array[Rect2] = [wall]
	var round_it: PackedVector2Array = TownWays.route(door, goal, walls, open, none, 5).p as PackedVector2Array
	_check(round_it.size() > 5 and not _inside(round_it, walls), "the way keeps out of a wall")
	var closest: float = INF
	for pt: Vector2 in round_it:
		closest = minf(closest, Vector2(clampf(pt.x, wall.position.x, wall.end.x), clampf(pt.y, wall.position.y, wall.end.y)).distance_to(pt))
	_check(closest >= 3.0, "and keeps a person's distance from it (%.1f px)" % closest)
	_check(_kink(round_it) < 45.0, "going round it bends smoothly (%.0f degrees)" % _kink(round_it))
	_check(_length(round_it) < straight * 1.5, "without a long detour (%.0f)" % _length(round_it))
	# --- ground one cannot stand on
	var wet: Callable = func(p: Vector2) -> bool: return not Rect2(150, 100, 60, 130).has_point(p)
	var dry: PackedVector2Array = TownWays.route(door, goal, no_solids, wet, none, 5).p as PackedVector2Array
	var wet_hit: bool = false
	for pt: Vector2 in dry:
		wet_hit = wet_hit or Rect2(150, 100, 60, 130).has_point(pt)
	_check(dry.size() > 5 and not wet_hit, "the way avoids ground that cannot be walked")
	# --- an older way: join it, do not run on, and not at a right angle
	var old: PackedVector2Array = PackedVector2Array([Vector2(60, 100), Vector2(300, 100)])
	var trails: Array[PackedVector2Array] = [TownWays.resample(old, TownWays.STEP)]
	var joining: Dictionary = TownWays.route(Vector2(130, 230), Vector2(300, 100), no_solids, open, trails, 3)
	var join: PackedVector2Array = joining.p as PackedVector2Array
	_check(join.size() > 4, "a way is found next to an old one")
	_check(bool(joining.joined), "it joins the old way")
	if join.size() > 4:
		var end: Vector2 = join[join.size() - 1]
		_check(absf(end.y - 100.0) < 6.5, "and ends on it (%.1f px from its line)" % absf(end.y - 100.0))
		var heading: Vector2 = (join[join.size() - 1] - join[join.size() - 4]).normalized()
		_check(absf(heading.x) > 0.35, "arriving along it, not square onto it (heading %s)" % str(heading))
		_check(_length(join) < Vector2(130, 230).distance_to(Vector2(300, 100)) * 0.97, "it does not run on to the far goal")
	# --- a person walking somewhere (no joining): all the way to the goal, along the old way where it leads the right way
	var walk: PackedVector2Array = TownWays.route(Vector2(70, 130), Vector2(290, 130), no_solids, open, trails, 3, false).p as PackedVector2Array
	_check(walk.size() > 5 and walk[walk.size() - 1].distance_to(Vector2(290, 130)) < 0.5, "a walker arrives at the goal, it does not stop at the old way")
	var on_trail: int = 0
	for pt: Vector2 in walk:
		if absf(pt.y - 100.0) < 5.0:
			on_trail += 1
	_check(float(on_trail) / float(maxi(walk.size(), 1)) > 0.5, "and walks along the trodden way for most of it (%d of %d points)" % [on_trail, walk.size()])
	var blocked_walk: PackedVector2Array = TownWays.route(Vector2(100, 200), Vector2(300, 120), walls, open, none, 3, false).p as PackedVector2Array
	_check(blocked_walk.size() > 5 and not _inside(blocked_walk, walls), "a walker goes round a wall, never through it")
	# --- the picture
	var art: Dictionary = TownPathArt.image(way, 9, true)
	_check(not art.is_empty() and (art.image as Image).get_width() > 150, "the way has a picture")
	if not art.is_empty():
		var img: Image = art.image as Image
		var filled: int = 0
		for y: int in img.get_height():
			for x: int in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					filled += 1
		var area: float = _length(way) * 8.0
		_check(float(filled) > area * 0.5 and float(filled) < area * 2.0, "worn ground covers about the way's width (%d px)" % filled)
		var first: Vector2i = Vector2i(way[0] - (art.origin as Vector2))
		_check(img.get_pixel(first.x, first.y).a > 0.0, "the door is worn")
	print("TOWN WAYS: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
