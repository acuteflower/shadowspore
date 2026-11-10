class_name AlchemyRules
extends RefCounted
## Pure rules of the alchemy (docs/alchemie_konzept.md, data/alchemy.json): which item is which potion, what a tier does, what it costs, when it is unlocked,
## how many come out of one brew and the pauses after eating and drinking. Nothing here touches nodes; the inventory (drinking), the stamina (Glutatem) and
## the town (Esma brews) ask it.

const TIERS: int = 5
const TYPES: Array[String] = ["heal", "stamina", "ashen", "clarity", "wisp", "leere"]
const SPECIAL: Array[String] = ["ashen", "clarity", "wisp", "leere"] ## the special potions: three tiers, own place or time of brewing, one shared pause


static func data() -> Dictionary:
	return DataRegistry.table("alchemy")


static func potion(type: String) -> Dictionary:
	return (data().get("potions", {}) as Dictionary).get(type, {}) as Dictionary


## The tier block (1..5) of a potion type, {} when there is none.
static func tier(type: String, level: int) -> Dictionary:
	var tiers: Array = potion(type).get("tiers", []) as Array
	return tiers[level - 1] as Dictionary if level >= 1 and level <= tiers.size() else {}


static func item_id(type: String, level: int) -> String:
	return String(potion(type).get("item", "potion_%s_%d")) % level


## {type, tier} of an item stack or id, {} for anything that is no potion.
static func of(stack_or_id: Variant) -> Dictionary:
	var id: String = String((stack_or_id as Dictionary).get("id", "")) if stack_or_id is Dictionary else String(stack_or_id)
	var def: Dictionary = DataRegistry.get_entry("items", id)
	if String(def.get("kind", "")) != "potion":
		return {}
	return def.get("potion", {}) as Dictionary


## Tiers a potion has: five for the everyday ones, three for the special ones.
static func tier_count(type: String) -> int:
	return maxi((potion(type).get("tiers", []) as Array).size(), 1)


static func is_special(type: String) -> bool:
	return bool(potion(type).get("special", false))


static func tier_name(level: int, type: String = "") -> String:
	var names: Array = (data().get("special_tier_names", []) if is_special(type) else data().get("tier_names", [])) as Array
	return String(names[level - 1]) if level >= 1 and level <= names.size() else str(level)


static func roman(level: int) -> String:
	return ["I", "II", "III", "IV", "V"][clampi(level, 1, TIERS) - 1]


## Name of the potion's brewing condition ("forge", "dew", "night", "" = none) and why it is not met right now ("" = fine). The weather is passed in so the rule stays pure.
static func condition_block(type: String, forge: bool, dew: float, night: float) -> String:
	var cond: Dictionary = potion(type).get("condition", {}) as Dictionary
	var met: bool = true
	match String(cond.get("kind", "")):
		"forge":
			met = forge
		"dew":
			met = dew >= 0.15
		"night":
			met = night >= 0.5
	return "" if met else String(cond.get("text", "JETZT NICHT MÖGLICH"))


## Aschenhaut: seconds, the share of burn damage that still gets through, whether burning cannot start at all.
static func ashen_spec(level: int) -> Dictionary:
	var spec: Dictionary = tier("ashen", level)
	return {"seconds": float(spec.get("seconds", 60.0)), "burn": float(spec.get("burn", 1.0)), "immune": bool(spec.get("immune", false))}


## Klarblick: seconds, the radius in which real things glint, whether shadow creatures show their eyes.
static func clarity_spec(level: int) -> Dictionary:
	var spec: Dictionary = tier("clarity", level)
	return {"seconds": float(spec.get("seconds", 60.0)), "radius": float(spec.get("radius", 120.0)), "eyes": bool(spec.get("eyes", false))}


## Irrlichtsud: seconds, the light's radius (px), speed factor of a creature inside it, push out (0..1), lure the night gains per second.
static func wisp_spec(level: int) -> Dictionary:
	var spec: Dictionary = tier("wisp", level)
	return {"seconds": float(spec.get("seconds", 45.0)), "radius": float(spec.get("radius", 40.0)), "slow": float(spec.get("slow", 0.6)),
		"push": float(spec.get("push", 0.0)), "lure": float(spec.get("lure", 0.02))}


## Leere: seconds, rift radius (px), void damage per second, lifesteal share (0..1), player self-damage per second, slow share (0..1), pull (0 or 1).
static func leere_spec(level: int) -> Dictionary:
	var spec: Dictionary = tier("leere", level)
	return {"seconds": float(spec.get("seconds", 5.0)), "radius": float(spec.get("radius", 128.0)), "dps": float(spec.get("dps", 8.0)),
		"lifesteal": float(spec.get("lifesteal", 0.0)), "self_dps": float(spec.get("self_dps", 2.0)),
		"slow": float(spec.get("slow", 0.0)), "pull": float(spec.get("pull", 0.0))}


static func color(type: String) -> Color:
	return Color(String(potion(type).get("color", "ffffff")))


static func light(type: String) -> Color:
	return Color(String(potion(type).get("light", "ffffff")))


# ---------- effects ----------

## Health a healing potion of `level` gives at `max_health`: a share of the maximum, at least `min`.
static func heal_amount(level: int, max_health: float) -> float:
	var spec: Dictionary = tier("heal", level)
	if spec.is_empty():
		return 0.0
	return maxf(roundf(max_health * float(spec.get("ratio", 0.0))), float(spec.get("min", 0.0)))


## Status effects a potion of this tier puts out (Wundtau IV/V: burn).
static func cleanses(type: String, level: int) -> Array:
	return tier(type, level).get("cleanse", []) as Array


## True when the healing of this tier may run past the maximum into overheal even at full health (Wundtau V).
static func overheals(level: int) -> bool:
	return bool(tier("heal", level).get("overheal", false))


## Glutatem: stamina per second, seconds, factor on the regeneration pause, factor on the sprint cost.
static func stamina_spec(level: int) -> Dictionary:
	var spec: Dictionary = tier("stamina", level)
	return {"per_second": float(spec.get("per_second", 0.0)), "seconds": float(spec.get("seconds", 30.0)),
		"delay_scale": float(spec.get("delay_scale", 1.0)), "sprint_scale": float(spec.get("sprint_scale", 1.0))}


## Seconds of the pause after `kind` ("food" or "heal").
static func pause(kind: String) -> float:
	return float((data().get("pauses", {}) as Dictionary).get(kind, 0.0))


## The status effect that holds the pause after using this item ("" = none): every consumable starts the food pause,
## a healing potion the wound pause, a special potion the shared special pause. Glutatem starts nothing.
static func pause_effect(def: Dictionary) -> String:
	var kind: String = String(def.get("kind", ""))
	if kind == "consumable":
		return "food_pause"
	if kind == "potion" and String((def.get("potion", {}) as Dictionary).get("type", "")) == "heal":
		return "wound_pause"
	if kind == "potion" and SPECIAL.has(String((def.get("potion", {}) as Dictionary).get("type", ""))):
		return "special_pause"
	return ""


# ---------- brewing ----------

## Ingredients of one brew (the empty vials included: one per potion that comes out).
static func ingredients(type: String, level: int) -> Dictionary:
	var spec: Dictionary = tier(type, level)
	var out: Dictionary = (spec.get("in", {}) as Dictionary).duplicate()
	var vial: String = String(data().get("vial", ""))
	if vial != "" and not spec.is_empty():
		out[vial] = int(out.get(vial, 0)) + base_yield(type, level)
	return out


static func base_yield(type: String, level: int) -> int:
	return int(tier(type, level).get("yield", 1))


## Potions out of one brew: the base, plus the moon's gift on a full-moon night. `moon_phase` as TimeManager.moon_phase() (0 new .. 0.5 full, eight days).
static func brew_yield(type: String, level: int, moon_phase: float, night: float) -> int:
	return base_yield(type, level) + moon_extra(moon_phase, night)


static func moon_extra(moon_phase: float, night: float) -> int:
	var moon: Dictionary = data().get("moon", {}) as Dictionary
	if moon.is_empty() or roundi(moon_phase * 8.0) != int(moon.get("phase", 4)) or night < float(moon.get("night", 0.5)):
		return 0
	return int(moon.get("extra", 1))


static func trust_needed(type: String, level: int) -> int:
	return int(tier(type, level).get("trust", 0))


## Why this tier cannot be brewed yet ("" = it can), from what the brewer knows: her trust and how often each potion was brewed ("type:tier" -> count).
## Ingredients are checked elsewhere (they depend on the bag).
static func unlock_block(type: String, level: int, trust: int, brewed: Dictionary, brewer: String = "ESMA") -> String:
	if tier(type, level).is_empty():
		return "UNBEKANNT"
	if trust < trust_needed(type, level):
		return "%s TRAUT DIR NOCH NICHT (VERTRAUEN %d)" % [brewer, trust_needed(type, level)]
	if level > 1 and int(brewed.get(key(type, level - 1), 0)) <= 0:
		return "ERST STUFE %s BRAUEN" % roman(level - 1)
	return ""


static func key(type: String, level: int) -> String:
	return "%s:%d" % [type, level]
