class_name Hallgrat
extends Node2D
## The stone town in the west on the Glaskamm (docs/stadt_westen_konzept.md; stage 1: the ground plan). It reads data/hallgrat.json, puts up the
## milestones of the Westweg (`Milestone`), names the town on the map (`map_marker`, style `hallgrat` in data/map_markers.json, shown once the
## forum has been seen) and, for the developer, draws the ground plan onto the real ground (`HallgratPlan`: districts, places, ways, gates,
## guide stones; ENTWICKLER -> HALLGRAT: PLAN). The town itself (houses, walls, people) is not built yet. Node of `WorldLevel`, group `hallgrat`.
## Nothing here is state: every peer builds the same from the data.

var forum: Vector2 = Vector2.INF ## px: the Wächterin des Glaskamms in the middle of the forum
var milestones: Array[Milestone] = []
var plan: HallgratPlan
var buildings: Array[HallgratBuilding] = []
var deco: Array[HallgratBuilding] = [] ## the small things of the streets
var low_walls: Array[HallgratBuilding] = [] ## the pieces of the low walls along the ways
var leitsteine: Array[HallgratLeitstein] = []
var bell_at: Vector2 = Vector2.INF ## px: the moon tower's bell
var people: HallgratPeople ## the town's residents (docs/hallgrat_bewohner_konzept.md)
var _last_time: float = -1.0
var _clear: Array[Vector2i] = []
var _buckets_ready: bool = false
var _buckets: Dictionary = {} ## Vector2i (512 px cell) -> Array[HallgratBuilding]
var _active_buildings: Array[HallgratBuilding] = []
var _town_bounds: Rect2 = Rect2()
var _wake_clock: float = 0.0

const WAKE_BUCKET: float = 512.0
const WAKE_RADIUS_SQ: float = 720.0 * 720.0


## Builds the milestones and returns where they stand (px), so the world keeps generated props off them.
func setup() -> Array[Vector2]:
	name = "Hallgrat"
	y_sort_enabled = true
	add_to_group("hallgrat")
	add_to_group("quest_actors") ## so the map asks `map_marker`
	var data: Dictionary = DataRegistry.table("hallgrat")
	var at: Array = data.get("forum", []) as Array
	if at.size() == 2:
		forum = Vector2(float(at[0]), float(at[1])) * 16.0 + Vector2(8, 8)
	var spots: Array[Vector2] = []
	for spec: Dictionary in data.get("milestones", []) as Array:
		var stone: Milestone = Milestone.new()
		var pos: Array = spec.pos as Array
		stone.name = "Milestone_" + String(spec.id)
		stone.number = int(spec.number)
		stone.position = Vector2(float(pos[0]), float(pos[1]))
		add_child(stone)
		milestones.append(stone)
		spots.append(stone.position)
	for spec: Dictionary in data.get("placed", []) as Array: ## stage 3b: the houses in rows along the streets, the halls, the stables, the market (tools/place_hallgrat_buildings.py)
		var feet: Array = spec.px as Array
		var house: HallgratBuilding = HallgratBuilding.new()
		house.setup(String(spec.type), Vector2(float(feet[0]), float(feet[1])), bool(spec.get("flip", false)))
		house.name = "Building_" + String(spec.id)
		add_child(house)
		buildings.append(house)
		_clear.append_array(house.footprint_cells())
	for spec: Dictionary in data.get("deco", []) as Array: ## the street furniture (tools/place_hallgrat_deco.py): low walls, barrels, lanterns, planters
		var feet2: Array = spec.px as Array
		var thing: HallgratBuilding = HallgratBuilding.new()
		thing.setup(String(spec.type), Vector2(float(feet2[0]), float(feet2[1])), bool(spec.get("flip", false)))
		thing.name = "Deco_%d" % deco.size()
		add_child(thing)
		deco.append(thing)
		_clear.append_array(thing.footprint_cells())
	for spec: Dictionary in DataRegistry.table("hallgrat_art").get("wall_pieces", []) as Array: ## the low walls along the ways, every piece its own stones (tools/art_hallgrat_walls.py)
		var at3: Array = spec.px as Array
		var piece: HallgratBuilding = HallgratBuilding.new()
		piece.setup(String(spec.type), Vector2(float(at3[0]), float(at3[1])), false)
		piece.name = "Wand_%d" % low_walls.size()
		add_child(piece)
		low_walls.append(piece)
	for wall: Dictionary in data.get("walls", []) as Array: ## stage 3c: the west wall, one stretch of parapet with merlons every 16 px
		var line: Array = wall.line as Array
		var a: Vector2 = Vector2(float((line[0] as Array)[0]), float((line[0] as Array)[1])) * 16.0
		var b: Vector2 = Vector2(float((line[1] as Array)[0]), float((line[1] as Array)[1])) * 16.0
		var steps: int = maxi(1, int(a.distance_to(b) / 16.0))
		for k: int in steps + 1:
			var stretch: HallgratBuilding = HallgratBuilding.new()
			stretch.setup(String(wall.get("type", "mauer_ns")), a.lerp(b, float(k) / steps) + Vector2(0, 16), false)
			stretch.name = "Wall_%s_%d" % [String(wall.id), k]
			add_child(stretch)
	for spec: Dictionary in data.get("leitsteine", []) as Array: ## stage 3c: the guide stones; the town still sleeps, their crystals only remember their light
		var tile: Array = spec.tile as Array
		var stone2: HallgratLeitstein = HallgratLeitstein.new()
		stone2.name = "Leitstein_" + String(spec.id)
		stone2.tone = int(spec.get("tone", 0))
		stone2.dead = bool(spec.get("dead", false))
		stone2.position = Vector2(float(tile[0]) * 16.0 + 8.0, float(tile[1]) * 16.0 + 12.0)
		add_child(stone2)
		leitsteine.append(stone2)
		_clear.append(Vector2i(int(tile[0]), int(tile[1])))
	for b2: Dictionary in data.get("placed", []) as Array: ## the dusk bell rings from the moon tower
		if String(b2.id) == "mondturm":
			var at2: Array = b2.px as Array
			bell_at = Vector2(float(at2[0]), float(at2[1]) - 60.0)
	people = HallgratPeople.new()
	people.setup()
	add_child(people)
	for district: Dictionary in data.get("districts", []) as Array: ## no wild trees or bushes between the houses of the town's core
		if not ["stille", "staffeln", "fuss"].has(String(district.id)):
			continue
		var poly: PackedVector2Array = PackedVector2Array()
		for p: Array in district.poly as Array:
			poly.append(Vector2(float(p[0]), float(p[1])))
		var box: Rect2 = Rect2(poly[0], Vector2.ZERO)
		for p: Vector2 in poly:
			box = box.expand(p)
		for ty: int in range(int(box.position.y), int(box.end.y) + 1):
			for tx: int in range(int(box.position.x), int(box.end.x) + 1):
				if Geometry2D.is_point_in_polygon(Vector2(tx + 0.5, ty + 0.5), poly):
					_clear.append(Vector2i(tx, ty))
	return spots


## The town's trees, bushes, grass and flowers on its free grass (data/hallgrat.json `greenery`): real world plants, handed to the
## `PropGenerator` as hand-placed props, so they sway, glow and can be picked or felled like any other.
func extra_props() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec: Dictionary in DataRegistry.table("hallgrat").get("greenery", []) as Array:
		var tile: Array = spec.tile as Array
		out.append({"cell": Vector2i(int(tile[0]), int(tile[1])), "kind": String(spec.kind), "variant": int(spec.variant)})
	return out


## Tiles under and round the buildings (no generated plant or stone grows there).
func clear_cells() -> Array[Vector2i]:
	return _clear


## The map (M) marks the town at its forum once that part of the land has been seen.
func map_marker() -> Dictionary:
	if not forum.is_finite():
		return {}
	return {"id": "hallgrat", "position": forum}


func actor_position(_who: String) -> Vector2:
	return Vector2.INF


## The east gate's foot on the market (dev teleport).
func gate_point() -> Vector2:
	for gate: Dictionary in DataRegistry.table("hallgrat").get("gates", []) as Array:
		if String(gate.id) == "osttor":
			var tile: Array = gate.tile as Array
			return Vector2(float(tile[0]) + 7.0, float(tile[1]) + 2.0) * 16.0 + Vector2(8, 8)
	return forum


## Where the Westweg leaves the caravan's cart road (dev teleport).
func fork_point() -> Vector2:
	var road: Dictionary = DataRegistry.table("hallgrat").get("westweg", {}) as Dictionary
	var from: Array = road.get("from", []) as Array
	return Vector2(float(from[0]), float(from[1])) * 16.0 + Vector2(8, 8) if from.size() == 2 else Vector2.INF


func plan_shown() -> bool:
	return plan != null and plan.visible


## Dev: the ground plan drawn onto the ground (local only).
func show_plan(on: bool) -> void:
	if plan == null:
		if not on:
			return
		plan = HallgratPlan.new()
		plan.name = "Plan"
		get_parent().add_child(plan)
	plan.visible = on


## The bell of the moon tower rings at dusk (three strokes), heard round the town: local, every peer by its own clock.
func _process(delta: float) -> void:
	var now: float = TimeManager.time_of_day
	if _last_time >= 0.0 and _last_time < DUSK_BELL and now >= DUSK_BELL and bell_at.is_finite():
		ring_bell()
	_last_time = now
	if not _buckets_ready:
		_index_buildings()
	_wake_clock -= delta
	if _wake_clock <= 0.0:
		_wake_clock = 0.2
		_update_building_activity()


func _index_buildings() -> void:
	_buckets_ready = true
	_buckets.clear()
	_active_buildings.clear()
	var has_bounds: bool = false
	var bounds: Rect2 = Rect2()
	for group: Array[HallgratBuilding] in [buildings, deco, low_walls]:
		for b: HallgratBuilding in group:
			if not is_instance_valid(b):
				continue
			var pos: Vector2 = b.global_position
			var cell: Vector2i = Vector2i(floori(pos.x / WAKE_BUCKET), floori(pos.y / WAKE_BUCKET))
			if not _buckets.has(cell):
				_buckets[cell] = [] as Array[HallgratBuilding]
			(_buckets[cell] as Array[HallgratBuilding]).append(b)
			if not has_bounds:
				bounds = Rect2(pos, Vector2.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(pos)
			b.set_managed_sleep(true)
	_town_bounds = bounds.grow(768.0) if has_bounds else Rect2()
	_update_building_activity()


func _update_building_activity() -> void:
	if not _town_bounds.has_area():
		return
	var focus: Array[Vector2] = []
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	if cam != null:
		var cp: Vector2 = cam.get_screen_center_position()
		if _town_bounds.has_point(cp):
			focus.append(cp)
	for player: Player in Player.all:
		if is_instance_valid(player) and player.is_multiplayer_authority():
			var pp: Vector2 = player.global_position
			if _town_bounds.has_point(pp):
				focus.append(pp)
	if focus.is_empty():
		if not _active_buildings.is_empty():
			for b: HallgratBuilding in _active_buildings:
				if is_instance_valid(b):
					b.set_managed_sleep(true)
			_active_buildings.clear()
		return
	var wanted: Dictionary = {}
	var seen_cells: Dictionary = {}
	for fp: Vector2 in focus:
		var min_c: Vector2i = Vector2i(floori((fp.x - 720.0) / WAKE_BUCKET), floori((fp.y - 720.0) / WAKE_BUCKET))
		var max_c: Vector2i = Vector2i(floori((fp.x + 720.0) / WAKE_BUCKET), floori((fp.y + 720.0) / WAKE_BUCKET))
		for cy: int in range(min_c.y, max_c.y + 1):
			for cx: int in range(min_c.x, max_c.x + 1):
				var c: Vector2i = Vector2i(cx, cy)
				if seen_cells.has(c):
					continue
				seen_cells[c] = true
				if not _buckets.has(c):
					continue
				for b: HallgratBuilding in _buckets[c] as Array[HallgratBuilding]:
					if is_instance_valid(b) and b.global_position.distance_squared_to(fp) <= WAKE_RADIUS_SQ:
						wanted[b] = true
	for prev: HallgratBuilding in _active_buildings:
		if is_instance_valid(prev) and not wanted.has(prev):
			prev.set_managed_sleep(true)
	var next_active: Array[HallgratBuilding] = []
	for key: Variant in wanted.keys():
		var b: HallgratBuilding = key as HallgratBuilding
		b.set_managed_sleep(false)
		next_active.append(b)
	_active_buildings = next_active


const DUSK_BELL: float = 0.79


func ring_bell() -> void:
	var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	sound.stream = load("res://assets/audio/hallgrat/glocke.wav") as AudioStream
	sound.bus = "SFX"
	sound.volume_db = -2.0
	sound.position = bell_at
	sound.max_distance = 1800.0
	sound.attenuation = 0.7
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()
