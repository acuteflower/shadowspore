class_name NightRules
extends RefCounted
## The pure rules of the night (docs/nacht_monster_konzept.md): when the night spawns, how many shadow creatures a group of players may meet, how tough they are,
## which kinds appear. No nodes, so the director, the tests and the dev tools all ask the same functions. All numbers live in data/night.json.


static func config() -> Dictionary:
	return DataRegistry.table("night")


static func _sect(name: String) -> Dictionary:
	return config().get(name, {}) as Dictionary


## 0..1 through the spawning window of the night (-1 outside it). The window starts at `window.start` of the day and ends at `window.end`; the clock wraps at midnight.
static func progress(time_of_day: float) -> float:
	var window: Dictionary = _sect("window")
	var start: float = float(window.start)
	var length: float = fposmod(float(window.end) - start, 1.0)
	var into: float = fposmod(time_of_day - start, 1.0)
	return into / length if into < length else -1.0


## Length of the window in days (0..1 of the clock).
static func window_length() -> float:
	var window: Dictionary = _sect("window")
	return fposmod(float(window.end) - float(window.start), 1.0)


## The share of the night's budget that may have been spawned by now (cumulative). The night is a curve, not three steps: data `window.release` lists
## [progress, share] points that are joined by straight lines (a flat stretch is a lull, a steep one a push); before the first point the first share holds.
static func released(progress_value: float) -> float:
	if progress_value < 0.0:
		return 0.0
	var points: Array = _sect("window").release as Array
	var previous: Array = points[0] as Array
	if progress_value <= float(previous[0]):
		return float(previous[1])
	for raw: Variant in points:
		var point: Array = raw as Array
		if progress_value <= float(point[0]):
			return lerpf(float(previous[1]), float(point[1]), inverse_lerp(float(previous[0]), float(point[0]), progress_value))
		previous = point
	return float(previous[1])


## The beat of the night ("scouts", "build", "lull", "call", "peak", "last_rush"; "" outside the window): the dramaturgy the director follows.
static func beat(progress_value: float) -> String:
	if progress_value < 0.0:
		return ""
	for raw: Variant in _sect("window").beats as Array:
		var entry: Dictionary = raw as Dictionary
		if progress_value >= float(entry.from) and progress_value < float(entry.to):
			return String(entry.id)
	return "last_rush"


## 1 at the new moon, 0 at the full moon (`phase` as `TimeManager.moon_phase()`: 0 new .. 0.5 full).
static func moon_dark(phase: float) -> float:
	return 0.5 + 0.5 * cos(TAU * phase)


## Budget factor of the moon: the new moon brings more, the full moon fewer.
static func moon_budget(phase: float) -> float:
	var moon: Dictionary = _sect("moon")
	return lerpf(float((moon.full as Dictionary).budget), float((moon.new as Dictionary).budget), moon_dark(phase))


## Courage the moon adds (or takes) for every creature of the night.
static func moon_courage(phase: float) -> float:
	var moon: Dictionary = _sect("moon")
	return lerpf(float((moon.full as Dictionary).courage), float((moon.new as Dictionary).courage), moon_dark(phase))


## The stage of the night ladder for night number `night_id` (data `stages`, the last one whose `from` has been reached): {id, budget, species, packs, raids, scouts, memory, last_rush, elite}.
static func stage_for(night_id: int) -> Dictionary:
	var best: Dictionary = (config().stages as Array)[0] as Dictionary
	for raw: Variant in config().stages as Array:
		var entry: Dictionary = raw as Dictionary
		if night_id >= int(entry.from):
			best = entry
	return best


## A pack size between the stage's limits, drawn with `rng` (and never more than the budget `left` can pay for at one point each).
static func pack_size(stage: Dictionary, left: float, rng: RandomNumberGenerator) -> int:
	var span: Array = stage.packs as Array
	var size: int = rng.randi_range(int(span[0]), int(span[1]))
	return clampi(size, 1, maxi(int(floor(left + 0.5)), 1))


## Sector (0 .. count-1) of a direction angle round the town.
static func sector_of(angle: float, count: int) -> int:
	return posmod(int(floor(fposmod(angle, TAU) / TAU * float(count))), count)


## Angle of the middle of a sector.
static func sector_angle(sector: int, count: int) -> float:
	return (float(sector) + 0.5) / float(count) * TAU


## Spawning stops late in the night (the morning is theirs to leave, not to arrive).
static func spawning(progress_value: float) -> bool:
	return progress_value >= 0.0 and progress_value <= float(_sect("window").spawn_end_progress)


## The night's budget of one group: base * level * day * players. `level` is the strongest player's level.
static func budget(level: int, day: int, players: int) -> float:
	var b: Dictionary = _sect("budget")
	var by_level: float = 1.0 + float(b.per_level) * float(maxi(level - 1, 0))
	var by_day: float = minf(float(b.day_cap), 1.0 + float(b.per_day) * float(maxi(day - 1, 0)))
	var by_players: float = pow(float(maxi(players, 1)), float(b.player_exp))
	return float(b.base) * by_level * by_day * by_players


## How tough the creatures are (health scale): level plus a share of the overall power (0..1).
static func strength(level: int, power: float) -> float:
	var s: Dictionary = _sect("strength")
	return 1.0 + float(s.per_level) * float(maxi(level - 1, 0)) + float(s.power_weight) * clampf(power, 0.0, 1.0)


## Damage grows slower than health: the player's own health grows only slowly with the collected levels (LevelRewards), so blows must not outrun it.
static func damage_scale(strength_value: float) -> float:
	return 1.0 + float(_sect("strength").damage_share) * (strength_value - 1.0)


## The strongest decides (docs: "der Stärkste"), but never below 1.
static func group_level(levels: Array[int]) -> int:
	var best: int = 1
	for level: int in levels:
		best = maxi(best, level)
	return best


## 0..1 from the weapon in the hand and the town's level (`town_level` 0..4 over `town_levels`).
static func power(weapon_damage: float, town_level: int, town_levels: int) -> float:
	var gear: float = clampf(weapon_damage / float(_sect("strength").gear_damage_full), 0.0, 1.0)
	var town: float = float(town_level) / float(maxi(town_levels - 1, 1))
	return 0.5 * gear + 0.5 * clampf(town, 0.0, 1.0)


## Kinds that may appear for this group, with their cost and weight: [{id, cost, weight}].
## `stage` (a `stage_for` result, optional) narrows the kinds to those the ladder has opened by then.
static func available(group_budget: float, level: int, day: int, stage: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in config().species as Array:
		var s: Dictionary = entry as Dictionary
		if not stage.is_empty() and not String(s.id) in (stage.species as Array):
			continue
		if group_budget >= float(s.min_budget) and level >= int(s.min_level) and day >= int(s.min_day):
			out.append(s)
	return out


## A weighted pick among `kinds` that costs at most `left` (plus half a point of slack, so the last point is not wasted); "" when nothing fits.
static func pick_species(kinds: Array[Dictionary], left: float, cost_scale: float, rng: RandomNumberGenerator) -> String:
	var fits: Array[Dictionary] = []
	var total: float = 0.0
	for s: Dictionary in kinds:
		if float(s.cost) * cost_scale <= left + 0.5:
			fits.append(s)
			total += float(s.weight)
	if fits.is_empty():
		return ""
	var roll: float = rng.randf() * total
	for s: Dictionary in fits:
		roll -= float(s.weight)
		if roll <= 0.0:
			return String(s.id)
	return String((fits[-1] as Dictionary).id)


static func cost_of(id: String) -> float:
	for entry: Variant in config().species as Array:
		if String((entry as Dictionary).id) == id:
			return float((entry as Dictionary).cost)
	return 1.0


## Groups of players: indices into `points`, joined greedily while someone is within `radius` of a member (single linkage).
static func cluster(points: Array[Vector2], radius: float) -> Array[Array]:
	var groups: Array[Array] = []
	var assigned: Array[bool] = []
	assigned.resize(points.size())
	for i: int in points.size():
		if assigned[i]:
			continue
		var group: Array = [i]
		assigned[i] = true
		var cursor: int = 0
		while cursor < group.size():
			var from: Vector2 = points[group[cursor] as int]
			for j: int in points.size():
				if not assigned[j] and from.distance_to(points[j]) <= radius:
					assigned[j] = true
					group.append(j)
			cursor += 1
		groups.append(group)
	return groups


## "none", "flood" or "silent": decided by the world seed and the night, so a reloaded game and every test agree.
static func special_for(world_seed: int, night_id: int) -> String:
	var special: Dictionary = _sect("special")
	if night_id < int(special.from_day):
		return "none"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([world_seed, night_id, 4177])
	if rng.randf() >= float(special.chance):
		return "none"
	var kinds: Dictionary = special.kinds as Dictionary
	var total: float = 0.0
	for id: String in kinds:
		total += float((kinds[id] as Dictionary).weight)
	var roll: float = rng.randf() * total
	for id: String in kinds:
		roll -= float((kinds[id] as Dictionary).weight)
		if roll <= 0.0:
			return id
	return "none"


static func special_spec(kind: String) -> Dictionary:
	return (_sect("special").kinds as Dictionary).get(kind, {"budget": 1.0, "health": 1.0, "damage": 1.0, "hunters": 0}) as Dictionary


## Fog nights shrink the town's light (`TownManager.light_scale`); 1 for every other night.
static func light_scale(kind: String) -> float:
	return float(special_spec(kind).get("light_scale", 1.0))


## Extra fog density (0..1) of a special night.
static func fog_boost(kind: String) -> float:
	return float(special_spec(kind).get("fog", 0.0))
