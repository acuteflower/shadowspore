class_name RefineRules
extends RefCounted
## The pure rules of refining (docs/refinement_konzept.md, numbers in data/refine.json): which weapon can reach which level, what an attempt costs and takes, how likely
## it is, what a level gives. No nodes, so Torben's window, the host, the tooltip and the tests all ask the same functions.
## A refined weapon is an ordinary stack with two more keys: "r" = level 0..15 (missing = 0) and "rp" = failures at the step it stands on now (the forge's "Glut",
## missing = 0). Rarity and material belong together: the rarer the weapon, the rarer the material ladder, the dearer and the harder every attempt.

const KEY_LEVEL: String = "r"
const KEY_PITY: String = "rp"
const TIER_SIZE: int = 5


static func config() -> Dictionary:
	return DataRegistry.table("refine")


static func max_level() -> int:
	return int(config().get("max", 15))


## Who refines (a settler of data/settlers.json) and at which building (a piece of data/town.json).
static func maker() -> String:
	return String(config().get("maker", "torben"))


static func station() -> String:
	return String(config().get("station", "smithy"))


# ---------- the weapon ----------

static func is_refinable(stack: Dictionary) -> bool:
	return not stack.is_empty() and bool(Items.definition(stack).get("refinable", false))


## The level this weapon stands on (0 = not refined).
static func level(stack: Dictionary) -> int:
	return clampi(int(stack.get(KEY_LEVEL, 0)), 0, max_level())


## Failures at the step the weapon stands before now: each makes the next attempt a little likelier.
static func pity(stack: Dictionary) -> int:
	return maxi(int(stack.get(KEY_PITY, 0)), 0)


## The highest level this weapon can reach: by rarity (common +5, uncommon +10, rare and above +15); an item may name its own `refine_cap`.
static func cap(stack: Dictionary) -> int:
	return mini(max_level(), int(Items.definition(stack).get("refine_cap", rarity_entry(stack).get("cap", max_level()))))


static func can_refine(stack: Dictionary) -> bool:
	return is_refinable(stack) and level(stack) < cap(stack)


static func next_level(stack: Dictionary) -> int:
	return level(stack) + 1


static func rarity_entry(stack: Dictionary) -> Dictionary:
	var rarities: Dictionary = config().get("rarity", {}) as Dictionary
	return rarities.get(String(Items.definition(stack).get("rarity", "common")), rarities.get("common", {})) as Dictionary


## The material ladder of a weapon: the rarity's own, unless the item names another one in `refine_ladder` (a rarity id).
static func ladder(stack: Dictionary) -> Array:
	var all: Dictionary = config().get("ladder", {}) as Dictionary
	var key: String = String(Items.definition(stack).get("refine_ladder", Items.definition(stack).get("rarity", "common")))
	return all.get(key, all.get("common", [])) as Array


# ---------- the steps ----------

## 0 = ANSCHMIEDEN (+1..+5), 1 = HÄRTEN (+6..+10), 2 = LEERENSCHMIEDEN (+11..+15) for a target level.
static func tier_index(target: int) -> int:
	return clampi((target - 1) / TIER_SIZE, 0, (config().get("tiers", []) as Array).size() - 1)


static func tier(target: int) -> Dictionary:
	return (config().get("tiers", []) as Array)[tier_index(target)] as Dictionary


## Position inside the tier, 0..4.
static func _step(target: int) -> int:
	return clampi((target - 1) % TIER_SIZE, 0, TIER_SIZE - 1)


static func trust_needed(target: int) -> int:
	return int(tier(target).get("trust", 0))


static func base_chance(target: int) -> float:
	var table: Array = config().get("base_chance", []) as Array
	return float(table[clampi(target - 1, 0, table.size() - 1)])


## Chance of an attempt that takes the weapon to `target` (default: the next level). Up to +5 it cannot fail. Above, the base chance is
## scaled by the weapon's rarity and raised by the Glut of earlier failures at this very step.
static func chance(stack: Dictionary, target: int = -1) -> float:
	var goal: int = next_level(stack) if target < 0 else target
	var base: float = base_chance(goal)
	if base >= 1.0:
		return 1.0
	var steps: Dictionary = tier(goal)
	var bonus: float = 0.0
	if goal == next_level(stack):
		bonus = minf(float(pity(stack)) * float(steps.get("pity", 0.0)), float(steps.get("pity_cap", 0.0)))
	return clampf(base * float(rarity_entry(stack).get("chance", 1.0)) + bonus, 0.0, float(config().get("chance_cap", 0.95)))


## The Glut part of the chance, for the window's gold segment.
static func pity_bonus(stack: Dictionary) -> float:
	var steps: Dictionary = tier(next_level(stack))
	return minf(float(pity(stack)) * float(steps.get("pity", 0.0)), float(steps.get("pity_cap", 0.0))) if base_chance(next_level(stack)) < 1.0 else 0.0


## Material of one attempt: the weapon's ladder (data/refine.json `ladder`) names a main and a side material for each tier; the amounts ramp up inside the tier,
## grow with the rarity (`amount`) and shrink with the scarcity of the material (`item_amount`, slag).
static func materials(stack: Dictionary, target: int) -> Dictionary:
	var steps: Dictionary = tier(target)
	var index: int = _step(target)
	var rungs: Array = ladder(stack)[tier_index(target)] as Array
	var scale: Dictionary = config().get("item_amount", {}) as Dictionary
	var out: Dictionary = {}
	var main: String = String(rungs[0])
	out[main] = maxi(roundi(float((steps.primary as Array)[index]) * float(rarity_entry(stack).get("amount", 1.0)) * float(scale.get(main, 1.0))), 1)
	var side: String = String(rungs[1])
	if side != "":
		var side_count: int = roundi(float((steps.secondary as Array)[index]) * float(scale.get(side, 1.0)))
		if side_count > 0:
			out[side] = side_count
	return out


static func copper(stack: Dictionary, target: int) -> int:
	var price: Dictionary = config().get("copper", {}) as Dictionary
	var raw: float = float(price.get("base", 5.0)) * pow(float(target), float(price.get("exp", 1.5))) * float(rarity_entry(stack).get("cost", 1.0))
	return maxi(roundi(raw), 1)


## Torben's seconds at the anvil for one attempt.
static func work_seconds(stack: Dictionary, target: int) -> float:
	var table: Array = config().get("work", []) as Array
	return roundf(float(table[clampi(target - 1, 0, table.size() - 1)]) * float(rarity_entry(stack).get("work", 1.0)))


## What comes back when an attempt fails (HÄRTEN: half of the iron, rounded down; LEERENSCHMIEDEN: nothing).
static func refund(stack: Dictionary, target: int) -> Dictionary:
	var share: float = float(tier(target).get("refund", 0.0))
	var back: Dictionary = {}
	var metals: Array = config().get("refund_items", []) as Array
	var spent: Dictionary = materials(stack, target)
	for item: String in spent:
		var count: int = floori(float(spent[item]) * share)
		if count > 0 and metals.has(item):
			back[item] = count
	return back


# ---------- the result ----------

## Decides an attempt from a seed (the host rolls once, when the weapon is handed in, and keeps the answer, so reloading changes nothing).
static func roll(stack: Dictionary, target: int, seed_value: int) -> bool:
	var odds: float = chance(stack, target)
	if odds >= 1.0:
		return true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randf() < odds


## The stack after an attempt: a success is one level more (Glut gone), a failure keeps the level and adds a piece of Glut.
static func result(stack: Dictionary, success: bool) -> Dictionary:
	var out: Dictionary = stack.duplicate()
	if success:
		out[KEY_LEVEL] = mini(level(stack) + 1, cap(stack))
		out.erase(KEY_PITY)
	else:
		out[KEY_PITY] = pity(stack) + 1
	return out


## Torben's verdict on the odds: 0 = good (> 70 %), 1 = risky (30 .. 70 %), 2 = bad.
static func verdict(odds: float) -> int:
	return 0 if odds > 0.7 else (1 if odds >= 0.3 else 2)


# ---------- what a level gives ----------

## Sum of the damage gains of levels 1..level (+0.80 at +15).
static func gain(level_value: int) -> float:
	var total: float = 0.0
	for lv: int in range(1, mini(level_value, max_level()) + 1):
		total += float(tier(lv).get("gain", 0.0))
	return total


## Milestone entries up to a level, e.g. [{level: 5, name, reach}].
static func milestones(level_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Dictionary = config().get("milestones", {}) as Dictionary
	var keys: Array = all.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		if int(key) <= level_value:
			var entry: Dictionary = (all[key] as Dictionary).duplicate()
			entry["level"] = int(key)
			out.append(entry)
	return out


## A stat of the weapon with its refinement: damage grows by `gain`, knockback by half of it, reach by the milestones' pixels, speed by the last milestone.
static func stat(stack: Dictionary, key: String, base: float) -> float:
	var lv: int = level(stack)
	if lv <= 0:
		return base
	match key:
		"damage":
			return base * (1.0 + gain(lv))
		"knockback":
			return base * (1.0 + gain(lv) * float(config().get("knockback_share", 0.5)))
		"reach":
			var extra: float = 0.0
			for m: Dictionary in milestones(lv):
				extra += float(m.get("reach", 0.0))
			return base + extra
		"speed":
			var faster: float = 0.0
			for m: Dictionary in milestones(lv):
				faster += float(m.get("speed", 0.0))
			return base * (1.0 + faster)
	return base
