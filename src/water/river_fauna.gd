class_name RiverFauna
extends Node2D
## Authority-only population; bounded home chunks make unloading unambiguous.
var rivers: WorldRivers
var enabled_kinds: Array[String] = ["heron", "otter", "duck"]
var _active: Dictionary = {}
var _pending: Array[Vector2i] = []
var _fields: Dictionary = {}
var _serial: int = 0
@onready var animals: Node2D = $Animals
func _ready() -> void:
	rivers = get_parent() as WorldRivers
	set_process(multiplayer.is_server())
func chunk_loaded(cell: Vector2i) -> void:
	if _active.has(cell): return
	_active[cell] = true
	if multiplayer.is_server() and not _pending.has(cell): _pending.append(cell)
func chunk_unloaded(cell: Vector2i) -> void:
	_active.erase(cell)
	_fields.erase(cell)
	_pending.erase(cell)
	if multiplayer.is_server():
		for animal: RiverAnimal in animals.get_children():
			if Vector2i((animal.home / 512.0).floor()) == cell: animal.queue_free()
func _process(_delta: float) -> void:
	if not _pending.is_empty(): _populate(_pending.pop_front())
func count(kind: String) -> int:
	var result: int = 0
	for animal: RiverAnimal in animals.get_children():
		if animal.kind == kind and not animal.is_queued_for_deletion(): result += 1
	return result
func flow_at(point: Vector2) -> Vector2:
	var cell: Vector2i = Vector2i((point / 512.0).floor())
	if not _fields.has(cell):
		var key: String = "%d,%d" % [cell.x, cell.y]
		var record: Dictionary = rivers._data["chunks"].get(key, {})
		if record.is_empty(): return Vector2.RIGHT
		_fields[cell] = (load(String(record["field"])) as Texture2D).get_image()
	var local: Vector2i = Vector2i(point - Vector2(cell) * 512.0)
	var pixel: Color = (_fields[cell] as Image).get_pixel(clampi(local.x, 0, 511), clampi(local.y, 0, 511))
	return Vector2(pixel.b * 2 - 1, pixel.a * 2 - 1).limit_length()
func leader(id: String) -> RiverAnimal:
	for animal: RiverAnimal in animals.get_children():
		if animal.school == id and animal.member == 0 and not animal.is_queued_for_deletion(): return animal
	return null
static func _arid(point: Vector2) -> bool:
	return BiomeBlend.arid_at(point) >= 0.22


func valid_route(animal: RiverAnimal, end: Vector2, curve: Vector2) -> bool:
	var cell: Vector2i = Vector2i((animal.home / 512.0).floor())
	var bounds: Rect2 = Rect2(Vector2(cell) * 512.0 + Vector2.ONE * 16, Vector2.ONE * 480)
	if not _active.has(cell) or not bounds.has_point(end) or end.distance_to(animal.home) > float(animal._spec["range"]) or _arid(end): return false
	for i: int in range(1, 17):
		var t: float = float(i) / 16
		var point: Vector2 = animal.position.lerp(end, t) + curve * sin(t * PI)
		var field: Vector2 = rivers.field_at(point)
		if not bounds.has_point(point) or _arid(point): return false
		if animal.kind in ["shoal", "brook", "strider"] and field.x > -2.0: return false
		if animal.kind == "frog" and field.x > 10.0: return false
		if animal.kind == "duck" and (field.x < -24.0 or field.x > 8.5 or field.y > 0.78): return false
		if animal.kind == "heron" and (field.x < -10.0 or field.x > 16.0 or field.y > 0.55): return false
		if animal.kind == "otter" and (field.x < -22.0 or field.x > 12.0 or field.y > 0.88): return false
		if animal.kind == "dragonfly" and field.x > 14.0: return false
	return true
## A flight needs only the animal's own chunk (everything below it is air).
func valid_flight(animal: RiverAnimal, end: Vector2) -> bool:
	var cell: Vector2i = Vector2i((animal.home / 512.0).floor())
	return _active.has(cell) and Rect2(Vector2(cell) * 512.0 + Vector2.ONE * 16, Vector2.ONE * 480).has_point(end) and not _arid(end)

## Where a flying animal may come down: the heron in shallows or on the bank, the duck on open water, the kingfisher on a perch.
func valid_landing(animal: RiverAnimal, end: Vector2) -> bool:
	if _arid(end): return false
	var field: Vector2 = rivers.field_at(end)
	match animal.kind:
		"heron": return field.x > -8.0 and field.x < 12.0 and field.y < 0.5
		"duck": return field.x < -8.0 and field.y < 0.7
	return true

## The nearest perch (a reed) to `point` within 40 px, else `fallback`: a kingfisher flies from perch to perch.
func perch_near(from: Vector2, point: Vector2, fallback: Vector2) -> Vector2:
	var best: Vector2 = fallback
	var best_d: float = 40.0
	for node: Node in get_tree().get_nodes_in_group("river_perches"):
		var perch: Node2D = node as Node2D
		var d: float = perch.global_position.distance_to(point)
		if d < best_d and perch.global_position.distance_to(from) > 30.0:
			best_d = d
			best = perch.global_position
	return best

func nearest_fish(from: Vector2, radius: float) -> RiverAnimal:
	var best: RiverAnimal
	var best_d: float = radius
	for animal: RiverAnimal in animals.get_children():
		if animal.kind in ["shoal", "brook"] and not animal.is_queued_for_deletion() and animal.position.distance_to(from) < best_d:
			best_d = animal.position.distance_to(from)
			best = animal
	return best

## The heron's strike: every fish near the point bolts (host only; the fish decide their own flight).
func scare_fish(at: Vector2, radius: float) -> void:
	for animal: RiverAnimal in animals.get_children():
		if animal.kind in ["shoal", "brook", "frog"] and animal.position.distance_to(at) < radius:
			animal.startle(at)

## Playful otter splashes alert or flush nearby stalking herons and swimming ducks.
func disturb_herons(at: Vector2, radius: float) -> void:
	for animal: RiverAnimal in animals.get_children():
		if animal.kind in ["heron", "duck"] and not animal.is_queued_for_deletion():
			var d: float = animal.position.distance_to(at)
			if d < 24.0:
				animal.startle(at)
			elif animal.kind == "heron" and d < radius and animal.mode == RiverAnimal.Mode.REST:
				animal._threat = at
				animal._alert_left = 1.8

func cover_target(home: Vector2) -> Vector2:
	for node: Node in get_tree().get_nodes_in_group("river_cover"):
		var rock: Node2D = node as Node2D
		if rock.global_position.distance_to(home) < 65.0:
			var point: Vector2 = rock.global_position + flow_at(rock.global_position) * 12.0
			if rivers.field_at(point).x < -3.0: return point
	return home - flow_at(home) * 15.0

func shore_target(home: Vector2, to_water: bool, rng: RandomNumberGenerator) -> Vector2:
	for i: int in 30:
		var point: Vector2 = home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10, 45)
		var field: Vector2 = rivers.field_at(point)
		if (field.x < -3.0 if to_water else field.x > 1.0 and field.x < 8.0): return point
	return home
func _populate(cell: Vector2i) -> void:
	if not _active.has(cell): return
	var chunk_origin: Vector2 = Vector2(cell) * 512.0
	if _arid(chunk_origin + Vector2(256.0, 256.0)) and _arid(chunk_origin) and _arid(chunk_origin + Vector2(512.0, 512.0)):
		return
	var settings: Dictionary = DataRegistry.table("river_animals")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, int(settings["seed"])))
	for kind: String in enabled_kinds:
		var spec: Dictionary = settings[kind]
		if count(kind) >= int(spec["cap"]): continue
		if rng.randf() > float(spec.get("chance", 1.0)): continue
		var found: bool = false
		var at: Vector2
		for attempt: int in 200:
			at = Vector2(cell) * 512.0 + Vector2(rng.randf_range(28, 484), rng.randf_range(28, 484))
			if _arid(at): continue
			var field: Vector2 = rivers.field_at(at)
			var valid: bool = field.x < -6.0 and field.y < 0.7
			if kind == "brook": valid = field.x < -8.0 and field.y > 0.45
			if kind in ["frog", "dragonfly"]: valid = field.x > 1.0 and field.x < 8.0
			if kind == "heron": valid = field.x > -6.0 and field.x < 10.0 and field.y < 0.45
			if kind == "otter": valid = field.x > -14.0 and field.x < 8.0 and field.y < 0.72
			if kind == "kingfisher": valid = field.x > 1.0 and field.x < 9.0
			if kind == "duck": valid = field.x < -12.0 and field.y > 0.1 and field.y < 0.65 and rivers.field_at(at + Vector2(14, 0)).x < -9.0 and rivers.field_at(at - Vector2(14, 0)).x < -9.0
			if valid:
				found = true
				break
		if not found: continue
		if kind == "dragonfly" or kind == "kingfisher":
			var perch: Node2D
			for node: Node in get_tree().get_nodes_in_group("river_perches"):
				var candidate: Node2D = node as Node2D
				if Vector2i((candidate.global_position / 512.0).floor()) == cell and candidate.global_position.distance_to(at) < float(spec["range"]):
					perch = candidate
					break
			if perch == null: continue
			at = perch.global_position
		var near_player: bool = false
		for player: Player in Player.all:
			if at.distance_to(player.global_position) < float(spec["fear"]) + 20.0: near_player = true
		if near_player: continue
		var family: bool = kind == "duck" and rng.randf() < 0.5 ## a hen with ducklings or a lone drake pair
		var otter_pair: bool = kind == "otter" and rng.randf() < 0.65
		var group: int = int(spec["group"]) if (kind != "duck" or family) else 2
		if kind == "otter":
			group = 2 if otter_pair else 1
		for member: int in group:
			if count(kind) >= int(spec["cap"]) or animals.get_child_count() >= int(settings["max_total"]): break
			var point: Vector2 = at + Vector2(member * 3.0, member * 2.0)
			if kind in ["shoal", "strider"] and rivers.field_at(point).x > -2.0: continue
			var animal: RiverAnimal = load("res://src/water/river_animal.tscn").instantiate() as RiverAnimal
			_serial += 1
			animal.name = "RiverAnimal%d" % _serial
			animal.kind = kind
			animal.member = member
			animal.school = "%s_%s" % ["duckfamily" if family else kind, cell]
			animal.home = at
			animal.position = point
			animal.facing = (-flow_at(point)).angle()
			animals.add_child(animal)
