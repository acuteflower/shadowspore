class_name PetRules
extends RefCounted
## The pure rules of the bond between Ellie and a wild crow or raven (docs/pet_konzept.md). No nodes, no state: everything the
## birds, the registry and the tests ask is a function of the numbers in data/pets.json.

const NO_REACTION: String = ""


static func table() -> Dictionary:
	return DataRegistry.table("pets")


## Bond points -> stage 0..5 (FREMD .. GEFÄHRTE).
static func stage_of(bp: float) -> int:
	var limits: Array = (table()["stages"] as Dictionary)["thresholds"] as Array
	var stage: int = 0
	for i: int in limits.size():
		if bp >= float(limits[i]):
			stage = i
	return stage


static func stage_name(stage: int) -> String:
	var names: Array = (table()["stages"] as Dictionary)["names"] as Array
	return String(names[clampi(stage, 0, names.size() - 1)])


## Points at which `stage` begins (the last stage returns its own start).
static func stage_start(stage: int) -> float:
	var limits: Array = (table()["stages"] as Dictionary)["thresholds"] as Array
	return float(limits[clampi(stage, 0, limits.size() - 1)])


## 0..1 progress inside the current stage (1 at the last stage).
static func stage_progress(bp: float) -> float:
	var limits: Array = (table()["stages"] as Dictionary)["thresholds"] as Array
	var stage: int = stage_of(bp)
	if stage >= limits.size() - 1:
		return 1.0
	var from: float = float(limits[stage])
	var to: float = float(limits[stage + 1])
	return clampf((bp - from) / (to - from), 0.0, 1.0)


## "loves" / "likes" / "neutral" / "dislikes" for `item` and the species ("" = not bird food at all). `key` lets a bird love one of its
## "likes" more than the rest (its favourite, stable for that bird).
static func reaction(species: String, item: String, key: String = "") -> String:
	var foods: Dictionary = table()["foods"] as Dictionary
	if not foods.has(item):
		return NO_REACTION
	var kind: String = String((foods[item] as Dictionary).get(species, NO_REACTION))
	if kind == "likes" and key != "" and favourite(species, key) == item:
		return "loves"
	return kind


## The one "likes" food this bird is mad about, from its key (so every bird has a taste of its own).
static func favourite(species: String, key: String) -> String:
	var likes: Array[String] = []
	var foods: Dictionary = table()["foods"] as Dictionary
	for item: String in foods:
		if String((foods[item] as Dictionary).get(species, "")) == "likes":
			likes.append(item)
	likes.sort()
	if likes.is_empty():
		return ""
	return likes[absi(hash(key + species)) % likes.size()]


## 2 traits per bird, stable for the key.
static func traits_of(key: String) -> Array[String]:
	var names: Array[String] = []
	for name: String in table()["traits"] as Dictionary:
		names.append(name)
	names.sort()
	var first: int = absi(hash(key + "t1")) % names.size()
	var second: int = absi(hash(key + "t2")) % names.size()
	if second == first:
		second = (second + 1) % names.size()
	return [names[first], names[second]] as Array[String]


static func _trait_factor(traits: Array[String], field: String) -> float:
	var factor: float = 1.0
	var all: Dictionary = table()["traits"] as Dictionary
	for name: String in traits:
		factor *= float((all.get(name, {}) as Dictionary).get(field, 1.0))
	return factor


## How much of the points counts for the `count`-th feeding of the day (0 = the first).
static func daily_factor(count: int) -> float:
	var feed: Dictionary = table()["feed"] as Dictionary
	var steps: Array = feed["daily_factor"] as Array
	if count < steps.size():
		return float(steps[count])
	return float(feed["daily_floor"])


## Bond points for one feeding: the reaction, how many times the bird was fed today, whether it was hungry (the first of the day).
static func gain(reaction_kind: String, fed_today: int, traits: Array[String]) -> float:
	var feed: Dictionary = table()["feed"] as Dictionary
	var base: float = float((feed["gain"] as Dictionary).get(reaction_kind, 0.0))
	if base <= 0.0:
		return 0.0
	var hungry: float = 1.0 + float(feed["hungry_bonus"]) if fed_today == 0 else 1.0
	return base * daily_factor(fed_today) * hungry * _trait_factor(traits, "gain")


## The distance (px) within which a bird starts to trust a still, sneaking Ellie with food in her hand.
static func lure_range(species: String, stage: int, calm: float, traits: Array[String]) -> float:
	var lure: Dictionary = table()["lure"] as Dictionary
	var base: float = float((lure["range"] as Dictionary).get(species, 50.0))
	var steps: Array = lure["stage_range"] as Array
	var by_stage: float = float(steps[clampi(stage, 0, steps.size() - 1)])
	return base * by_stage * (1.0 + float(lure["calm_range"]) * calm) * _trait_factor(traits, "range")


## Trust gained per second while she stands still in range (0 for food it does not want).
static func lure_rate(reaction_kind: String, calm: float, traits: Array[String]) -> float:
	var lure: Dictionary = table()["lure"] as Dictionary
	var per_food: float = float((lure["reaction_rate"] as Dictionary).get(reaction_kind, 0.0))
	return float(lure["rate"]) * per_food * (1.0 + float(lure["calm_rate"]) * calm) * _trait_factor(traits, "rate")


## Next value of the hidden trust: it grows while all conditions hold and drains otherwise.
static func step_interest(interest: float, holds: bool, rate: float, delta: float) -> float:
	if holds:
		return minf(1.2, interest + rate * delta)
	return maxf(0.0, interest - float((table()["lure"] as Dictionary)["decay"]) * delta)
