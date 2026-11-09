class_name LeafCritter
extends Node2D
## Sparse, seed/day-stable plant residents. A colony belongs to one 16-tile square,
## with a two-tile empty border and at most one resident. Squares divide streaming
## chunks exactly; catching/depleting its winner never promotes a replacement.
const ITEMS: Dictionary = {"beetle": "shimmer_beetle", "caterpillar": "leaf_caterpillar", "snail": "leaf_snail"}
const BODY: Rect2i = Rect2i(-4, -4, 9, 5)
static var _images: Dictionary = {}
static var _sites: Dictionary = {}
static var _colonies: Dictionary = {} ## Vector3i(world instance, square x/y) -> Array[LeafCritter]
static var _winners: Dictionary = {}
static var _dirty: Dictionary = {}

var kind: String = ""
var _bush: WorldProp
var _colony: Vector3i
var _anchor: Vector2
var _end: Vector2
var _dir: float = 1.0
var _clock: float = 0.0
var _gait: float = 0.0
var _withdraw: float = 0.0
var _flee: float = -1.0
var _flight_origin: Vector2
var _flight_dir: float = 1.0
var _effect: String = ""
var _effect_day: int = -1
var _route_cycle: int = -1
var _frame: int = -1
var _sense: float = 0.0
var _near: bool = false
var _settled: bool = true
var _day: int = -1
var _redraw: float = 0.0
var _rest_point: Vector2 = Vector2.ZERO
var _leaf_cover: int = 0


static func config() -> Dictionary:
	return DataRegistry.table("leaf_critters")


static func _roll(cell: Vector2i, salt: int) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([Moisture.world_seed, TimeManager.day, cell, salt])
	return rng.randf()


static func _raw_kind(thing: WorldProp) -> String:
	var spec: Dictionary = thing.spec().get("critters", {})
	if spec.is_empty(): return ""
	var population: Dictionary = config().population
	var square: int = int(population.square_tiles)
	var border: int = int(population.border_tiles)
	var inside: Vector2i = Vector2i(posmod(thing.cell.x, square), posmod(thing.cell.y, square))
	if inside.x < border or inside.y < border or inside.x >= square - border or inside.y >= square - border:
		return ""
	if _roll(thing.cell, 3917) >= float(spec.chance): return ""
	var wet: bool = Moisture.is_wet_day(TimeManager.day)
	var share: float = float(population.wet_snail_share if wet else population.dry_snail_share)
	share = clampf(share * float(spec.get("snail_bias", 1.0)), 0.0, 0.85)
	var roll: float = _roll(thing.cell, 3918)
	var animal: String = "snail" if roll < share else ("beetle" if roll < share + (1.0 - share) * 0.5 else "caterpillar")
	return animal if not sites_for(thing, animal, true).is_empty() else ""


static func today(thing: WorldProp) -> String:
	var bush: Bush = thing as Bush
	if bush == null or bush._critter == null or thing.is_depleted() or int(thing.state.get("c", 0)) == TimeManager.day + 1:
		return ""
	var key: Vector3i = bush._critter._colony
	var cached: Dictionary = _winners.get(key, {})
	if int(cached.get("day", -1)) != TimeManager.day:
		var best: LeafCritter = null
		var priority: float = INF
		for animal: LeafCritter in _colonies.get(key, []):
			if not is_instance_valid(animal) or _raw_kind(animal._bush).is_empty(): continue
			var rank: float = _roll(animal._bush.cell, 3919)
			if rank < priority:
				priority = rank
				best = animal
		_winners[key] = {"day": TimeManager.day, "winner": weakref(best) if best != null else null}
		cached = _winners[key]
	var winner: WeakRef = cached.winner as WeakRef
	if winner == null or winner.get_ref() != bush._critter: return ""
	var species: String = _raw_kind(thing)
	return species if not sites_for(thing, species).is_empty() else ""


## Shared by the prompt, host hand catch and sickle; hidden/night/departing animals
## cannot be harvested through a stale prompt. A withdrawn snail's shell is visible.
static func can_catch(thing: WorldProp) -> bool:
	var bush: Bush = thing as Bush
	return bush != null and bush._critter != null and today(thing) != "" and bush._critter.available()


func available() -> bool:
	return _settled and kind != "" and _flee < 0.0 and _active()


func setup(bush: WorldProp) -> void:
	_bush = bush
	name = "Critter"
	z_index = 1
	material = WorldProp._day_material()
	y_sort_enabled = false
	var square: int = int(config().population.square_tiles)
	var scope: int = bush.level.get_instance_id() if bush.level != null else bush.get_tree().root.get_instance_id()
	_colony = Vector3i(scope, floori(float(bush.cell.x) / square), floori(float(bush.cell.y) / square))
	if not _colonies.has(_colony): _colonies[_colony] = []
	(_colonies[_colony] as Array).append(self)
	_invalidate_colony()
	TimeManager.day_started.connect(func(_day: int) -> void: refresh(""))


func _invalidate_colony() -> void:
	_winners.erase(_colony)
	if not _dirty.has(_colony) or (_dirty[_colony] as WeakRef).get_ref() == null:
		_dirty[_colony] = weakref(self)
		_refresh_colony.call_deferred()


func _refresh_colony() -> void:
	_dirty.erase(_colony)
	for animal: LeafCritter in _colonies.get(_colony, []):
		if is_instance_valid(animal) and animal.is_inside_tree(): animal.refresh("")


func _exit_tree() -> void:
	if _colonies.has(_colony):
		(_colonies[_colony] as Array).erase(self)
		if (_colonies[_colony] as Array).is_empty():
			_colonies.erase(_colony)
			_dirty.erase(_colony)
		_winners.erase(_colony)


## The complete chunk has registered all candidates before anything becomes visible.
static func settle_chunk(things: Array[WorldProp]) -> void:
	for thing: WorldProp in things:
		var bush: Bush = thing as Bush
		if bush != null and bush._critter != null:
			bush._critter._settled = true
			bush._critter.refresh("")


func refresh(fx: String) -> void:
	if fx in ["catch", "scare", "depart"] and kind != "":
		_effect = fx
		_effect_day = TimeManager.day
		_flee = 0.0
		_flight_origin = global_position
		_flight_dir = _dir * signf(_bush.global_scale.x)
		set_process(true)
		return
	# Ordinary rustles must not cancel a departure or reset its path.
	if _flee >= 0.0: return
	var was: String = kind
	kind = today(_bush)
	if was != kind or _day != TimeManager.day:
		_route_cycle = -1
		_frame = -1
		_withdraw = 0.0
	_day = TimeManager.day
	visible = available()
	if _bush.level != null and _bush.level._pending_commit != null:
		if _bush.level._pending_commit.chunk.things.has(_bush):
			_settled = false
			visible = false
	set_process(kind != "")
	if kind != "": _pose(0.0)
	queue_redraw()


## Called by the host's foliage contact; the ordinary prop-state RPC makes the
## takeoff visible to everybody, persists absence and supports late joiners.
func startle() -> void:
	if kind != "beetle" or not available() or not multiplayer.is_server(): return
	if _bush.level != null:
		_bush.level.startle_critter(_bush.cell)


static func sites_for(thing: WorldProp, species: String, original: bool = false) -> PackedVector2Array:
	var sprite: Sprite2D = thing.get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null: return PackedVector2Array()
	if species.is_empty(): return PackedVector2Array()
	# Election always uses the intact base pose, even after harvesting or reloading.
	var texture: Texture2D = load(String(thing.spec().texture)) as Texture2D if original else sprite.texture
	var columns: int = int(thing.spec().columns) if original else sprite.hframes
	var rows: int = int(thing.spec().rows) if original else sprite.vframes
	var frame: int = thing.variant if original else sprite.frame
	var path: String = texture.resource_path
	var key: String = "%s:%d:%d:%d:%s" % [path, columns, rows, frame, species]
	if _sites.has(key): return _sites[key] as PackedVector2Array
	if not _images.has(path): _images[path] = texture.get_image()
	var image: Image = _images[path] as Image
	var points: PackedVector2Array = PackedVector2Array()
	if image != null and not image.is_empty():
		var size: Vector2i = Vector2i(image.get_width() / columns, image.get_height() / rows)
		var origin: Vector2i = Vector2i(frame % columns, frame / columns) * size
		var band: Array = (config().species[species] as Dictionary).leaf_band
		for y: int in range(maxi(4, floori(size.y * float(band[0]))), mini(size.y - 3, ceili(size.y * float(band[1])))):
			for x: int in range(5, size.x - 5):
				var safe: bool = true
				for by: int in range(BODY.position.y, BODY.end.y):
					for bx: int in range(BODY.position.x, BODY.end.x):
						if image.get_pixelv(origin + Vector2i(x + bx, y + by)).a < 0.9:
							safe = false
							break
					if not safe: break
				if safe: points.append(Vector2(x, y) + sprite.offset)
	_sites[key] = points
	return points


func _choose_route(cycle: int) -> void:
	var points: PackedVector2Array = sites_for(_bush, kind)
	if points.is_empty(): return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([Moisture.world_seed, _bush.cell, TimeManager.day, 72])
	_anchor = points[rng.randi_range(0, points.size() - 1)]
	# Both endpoints and every rounded intermediate footprint must fit. Never
	# turn an isolated safe pixel into an unbounded horizontal pacing track.
	var options: PackedVector2Array = PackedVector2Array([_anchor])
	var reach: float = float((config().species[kind] as Dictionary).step_pixels)
	for point: Vector2 in points:
		var distance: float = point.distance_to(_anchor)
		if distance < 2.0 or distance > reach: continue
		var safe: bool = true
		for step: int in range(1, ceili(distance * 3.0) + 1):
			if not points.has(_anchor.lerp(point, float(step) / ceili(distance * 3.0)).round()):
				safe = false
				break
		if safe: options.append(point)
	_end = options[rng.randi_range(0, options.size() - 1)]
	if cycle % 2 == 1:
		var swap: Vector2 = _anchor
		_anchor = _end
		_end = swap
	var direction: float = signf(_end.x - _anchor.x)
	_dir = direction if direction != 0.0 else (1.0 if rng.randf() < 0.5 else -1.0)
	_route_cycle = cycle


func _active() -> bool:
	return kind != "" and TimeManager.night_amount() < float((config().species[kind] as Dictionary).night_limit)


func _pose(delta: float) -> void:
	var sprite: Sprite2D = _bush.get_node("Sprite") as Sprite2D
	var spec: Dictionary = config().species[kind]
	var seconds: float = fposmod(TimeManager.time_of_day - TimeManager.DAY_START, 1.0) * TimeManager.DAY_LENGTH_SEC
	var period: float = float(spec.rest_seconds) + float(spec.move_seconds)
	var local: float = seconds + _roll(_bush.cell, 73) * period
	var cycle: int = floori(local / period)
	if cycle != _route_cycle or sprite.frame != _frame:
		_choose_route(cycle)
		_frame = sprite.frame
	var phase: float = fposmod(local, period)
	var travel: float = clampf((phase - float(spec.rest_seconds)) / float(spec.move_seconds), 0.0, 1.0)
	_leaf_cover = 1 if kind == "caterpillar" and phase < float(spec.rest_seconds) * 0.45 else 0
	_gait = fposmod(travel * 3.0, 1.0) if travel > 0.0 and travel < 1.0 and _anchor != _end else 0.0
	_sense -= delta
	if _sense <= 0.0:
		_sense = 0.25
		_near = Player.all.any(func(player: Player) -> bool: return is_instance_valid(player) and player.health.current > 0.0 and player.global_position.distance_to(_bush.global_position) < float(spec.sense_range))
	_withdraw = move_toward(_withdraw, 1.0 if _near and kind == "snail" else 0.0, delta * (3.0 if _near else 0.7))
	var at: Vector2 = _anchor.lerp(_end, travel).round()
	if kind == "snail" and _withdraw > 0.2:
		# Retracting freezes the foot position, rather than sliding a closed shell.
		at = _rest_point
	else:
		_rest_point = at
	transform = sprite.transform
	if _bush is Flora: at += (_bush as Flora).critter_wind_offset(at)
	position = sprite.transform * at


func _process(delta: float) -> void:
	_clock += delta
	if _flee >= 0.0:
		var duration: float = float(config().departure_seconds) if _effect != "catch" else float(config().catch_seconds)
		_flee = minf(1.0, _flee + delta / duration)
		var t: float = smoothstep(0.12, 1.0, _flee)
		if kind == "beetle" and _effect != "catch":
			global_transform = Transform2D(0.0, _flight_origin + Vector2(_flight_dir * 28.0 * t, -sin(t * PI * 0.6) * 22.0 - t * 8.0))
		if _flee >= 1.0:
			_flee = -1.0
			kind = ""
			visible = false
			set_process(false)
			if _effect_day != TimeManager.day: refresh("")
			return
	else:
		visible = _settled and _active()
		if visible: _pose(delta)
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = 0.08
		queue_redraw()


func _draw() -> void:
	if kind == "": return
	var fade: float = 1.0
	var flying: bool = _flee >= 0.0 and kind == "beetle" and _effect != "catch"
	if _flee >= 0.0:
		fade = 1.0 - smoothstep(0.55 if flying else 0.0, 1.0, _flee)
	LeafCritterVisual.draw_animal(self, kind, _dir, _clock + _roll(_bush.cell, 74) * 7.0, _gait, flying, maxf(_withdraw, _flee if not flying else 0.0), fade)

	# A strip of the real foreground leaf hides the tail while the caterpillar
	# feeds; its upper body/head stays visible and catchable throughout.
	if kind == "caterpillar" and _leaf_cover > 0 and _flee < 0.0:
		var sprite: Sprite2D = _bush.get_node("Sprite") as Sprite2D
		var size: Vector2 = sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes)
		var origin: Vector2 = Vector2(sprite.frame % sprite.hframes, sprite.frame / sprite.hframes) * size
		var at: Vector2 = _rest_point - sprite.offset + origin
		draw_texture_rect_region(sprite.texture, Rect2(-4, -1, 9, 2), Rect2(at + Vector2(-4, -1), Vector2(9, 2)))
