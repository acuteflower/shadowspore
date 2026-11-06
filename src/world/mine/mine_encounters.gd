class_name MineEncounters
extends RefCounted
## Where the enemies of a level sleep (docs/mine.md section 9). A pure function of the dressed layout with a random stream of its own: it spends the level's budget
## `edge^2 / budget_area * (1 + budget_per_level * (level - 1))` on encounters (templates from data/mine.json: a spider, two from the flanks, a listener covering a
## spider, a nest ...), put into rooms by their weight and into corridors, never within `safe_radius_tiles` of the way up and the lift. Members stand on open floor
## (3 x 3 tiles free of props and rocks), at least `SPACING` tiles from every other member. Results go into `layout.encounters`; `MineEncounterDirector` wakes them.

const SPACING: int = 3
const CORRIDOR_REACH: int = 6

var _l: MineLayout
var _cfg: Dictionary
var _rng: RandomNumberGenerator
var _rocks: Dictionary = {} ## tiles with a rock on them
var _taken: Array[Vector2i] = [] ## tiles of members placed so far


## Encounter points of a level.
static func budget_of(level: int, edge: int) -> float:
	var cfg: Dictionary = MineManager.config().enemies
	return float(edge * edge) / float(cfg.budget_area) * (1.0 + float(cfg.budget_per_level) * float(level - 1))


static func cost_of(members: Array) -> float:
	var costs: Dictionary = MineManager.config().enemies.costs
	var total: float = 0.0
	for enemy: Variant in members:
		total += float(costs.get(String(enemy), 1.0))
	return total


func dress(layout: MineLayout) -> void:
	_l = layout
	_cfg = MineManager.config().enemies
	_rng = RandomNumberGenerator.new()
	_rng.seed = MineGenerator._mix(MineGenerator._mix(_l.world_seed, _l.level), 400)
	_l.budget = budget_of(_l.level, _l.edge)
	for c: Vector2i in _l.chunk_rocks:
		for rock: Dictionary in _l.chunk_rocks[c] as Array:
			_rocks[Vector2i(floori(float(rock.x) / 16.0), floori(float(rock.y) / 16.0))] = true
	var spent: float = 0.0
	for _pass: int in 2: ## a second round lets a site host another group when there are fewer sites than budget
		var pool: Array[Dictionary] = _sites()
		while spent < _l.budget - 0.9 and not pool.is_empty():
			var at: int = _draw(pool)
			var site: Dictionary = pool[at]
			pool.remove_at(at)
			var template: Dictionary = _template(site, _l.budget - spent)
			if template.is_empty():
				continue
			var members: Array[Dictionary] = _place(site, template)
			if members.is_empty():
				continue
			var cost: float = cost_of(template.members as Array)
			_l.encounters.append({"id": _l.encounters.size(), "template": String(template.id), "room": int(site.room), "cost": cost, "members": members})
			spent += cost


## Rooms (by the weight of their type) and the hubs of corridor cells, minus what is too close to the way up and the lift.
func _sites() -> Array[Dictionary]:
	var weights: Dictionary = _cfg.room_weight
	var safe: float = float(_cfg.safe_radius_tiles)
	var sites: Array[Dictionary] = []
	for room: Dictionary in _l.rooms:
		var weight: float = float(weights.get(String(room.type), 1.0))
		var tile: Vector2i = room.center as Vector2i
		if weight > 0.0 and not _safe(tile, safe):
			sites.append({"tile": tile, "room": int(room.id), "type": String(room.type), "weight": weight, "region": room.rect as Rect2i})
	for index: int in _l.hubs.size():
		var hub: int = _l.hubs[index]
		if hub < 0 or _l.cell_room[index] >= 0:
			continue
		var tile: Vector2i = Vector2i(hub >> 16, hub & 0xFFFF)
		if _l.is_floor(tile.x, tile.y) and not _safe(tile, safe):
			sites.append({"tile": tile, "room": -1, "type": "corridor", "weight": float(_cfg.corridor_weight), "region": Rect2i(tile - Vector2i(CORRIDOR_REACH, CORRIDOR_REACH), Vector2i(CORRIDOR_REACH * 2 + 1, CORRIDOR_REACH * 2 + 1))})
	return sites


func _safe(tile: Vector2i, radius: float) -> bool:
	return Vector2(tile).distance_to(Vector2(_l.entry)) < radius or Vector2(tile).distance_to(Vector2(_l.station)) < radius


## A weighted random index.
func _draw(pool: Array[Dictionary]) -> int:
	var total: float = 0.0
	for site: Dictionary in pool:
		total += float(site.weight)
	var roll: float = _rng.randf() * total
	for i: int in pool.size():
		roll -= float(pool[i].weight)
		if roll <= 0.0:
			return i
	return pool.size() - 1


## A template that may stand at this site and fits into what is left of the budget (a group may overshoot it by half a point).
func _template(site: Dictionary, left: float) -> Dictionary:
	var fits: Array[Dictionary] = []
	var total: float = 0.0
	for template: Dictionary in _cfg.templates as Array:
		var rooms: Array = template.get("rooms", []) as Array
		if int(template.get("min_level", 1)) > _l.level or (not rooms.is_empty() and not rooms.has(String(site.type))):
			continue
		if cost_of(template.members as Array) > left + 0.5:
			continue
		fits.append(template)
		total += float(template.weight)
	if fits.is_empty():
		return {}
	var roll: float = _rng.randf() * total
	for template: Dictionary in fits:
		roll -= float(template.weight)
		if roll <= 0.0:
			return template
	return fits[fits.size() - 1]


func _open(t: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var n: Vector2i = t + Vector2i(dx, dy)
			if not _l.is_floor(n.x, n.y) or _l.solid[n.y * _l.edge + n.x] != 0 or _rocks.has(n):
				return false
	return true


func _apart(t: Vector2i, others: Array[Vector2i]) -> bool:
	for other: Vector2i in others:
		if absi(other.x - t.x) < SPACING and absi(other.y - t.y) < SPACING:
			return false
	return true


## Members of the template on open floor near the site: the first closest to its middle, the others `spread` tiles from the ones before.
func _place(site: Dictionary, template: Dictionary) -> Array[Dictionary]:
	var region: Rect2i = (site.region as Rect2i).intersection(Rect2i(0, 0, _l.edge, _l.edge))
	var spots: Array[Vector2i] = []
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var t: Vector2i = Vector2i(x, y)
			if _open(t) and (int(site.room) >= 0 or _l.room_at(x, y) < 0) and _apart(t, _taken) and not _safe(t, float(_cfg.safe_radius_tiles)):
				spots.append(t)
	var wanted: Array = template.members as Array
	if spots.size() < wanted.size():
		return []
	var centre: Vector2i = site.tile as Vector2i
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(Vector2(centre)) < Vector2(b).distance_squared_to(Vector2(centre)))
	var span: Array = template.get("spread", [3, 6]) as Array
	var chosen: Array[Vector2i] = [spots[0]]
	while chosen.size() < wanted.size():
		var options: Array[Vector2i] = []
		for t: Vector2i in spots:
			var d: float = Vector2(t).distance_to(Vector2(chosen[chosen.size() - 1]))
			if d >= float(span[0]) and d <= float(span[1]) and _apart(t, chosen):
				options.append(t)
		if options.is_empty(): ## relax: anything apart from the others
			for t: Vector2i in spots:
				if _apart(t, chosen):
					options.append(t)
		if options.is_empty():
			return []
		chosen.append(options[_rng.randi() % options.size()])
	var members: Array[Dictionary] = []
	for i: int in wanted.size():
		var t: Vector2i = chosen[i]
		var heading: float = (Vector2(centre) - Vector2(t)).angle() + _rng.randf_range(-0.6, 0.6)
		members.append({"enemy": String(wanted[i]), "x": t.x * 16.0 + 8.0, "y": t.y * 16.0 + 12.0, "heading": heading})
		_taken.append(t)
	return members
