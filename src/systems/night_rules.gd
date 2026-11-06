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


## The share of the night's budget that may have been spawned by now (cumulative; waves are steps in data `window.waves`: [progress it begins, share it reaches]).
static func released(progress_value: float) -> float:
	if progress_value < 0.0:
		return 0.0
	var share: float = 0.0
	for wave: Variant in _sect("window").waves as Array:
		var entry: Array = wave as Array
		if progress_value >= float(entry[0]):
			share = float(entry[1])
	return share


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


## Damage grows slower than health: a player always has 100 HP.
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
static func available(group_budget: float, level: int, day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in config().species as Array:
		var s: Dictionary = entry as Dictionary
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
