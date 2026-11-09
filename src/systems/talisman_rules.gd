class_name TalismanRules
extends RefCounted
## The pure rules of the talismans (docs/talisman_konzept.md, numbers in data/talismans.json and the `bonus` of each item): which kind of
## jewellery a stack is, that only one piece of each kind can be worn, and what the worn pieces add up to. No nodes, so the inventory, the
## host's combat code, every peer's health bar, the tooltip and the tests all ask the same functions.
## An item is a talisman when its kind is "talisman"; `jewelry` (necklace / earrings / bracelet) is its kind of jewellery and `bonus` {stat: value}
## its effect. `combine` gives a plain Dictionary of the same stat keys (missing = no effect).

const SLOT_PREFIX: String = "talisman_"


static func catalog() -> Dictionary:
	return DataRegistry.table("talismans")


static func is_talisman(stack: Dictionary) -> bool:
	return not stack.is_empty() and String(Items.definition(stack).get("kind", "")) == "talisman"


## "necklace", "earrings", "bracelet" or "" for anything else.
static func type_of(stack: Dictionary) -> String:
	return String(Items.definition(stack).get("jewelry", "")) if is_talisman(stack) else ""


static func type_info(type: String) -> Dictionary:
	return (catalog().get("types", {}) as Dictionary).get(type, {}) as Dictionary


static func bonus_of(stack: Dictionary) -> Dictionary:
	return Items.definition(stack).get("bonus", {}) as Dictionary if is_talisman(stack) else {}


## The slot (other than `slot_name`) that already holds the same kind of jewellery as `stack`, "" when there is none.
static func conflict(equipment: Dictionary, slot_name: String, stack: Dictionary) -> String:
	var type: String = type_of(stack)
	if type == "":
		return ""
	for other: String in equipment:
		if other != slot_name and type_of(equipment[other] as Dictionary) == type:
			return other
	return ""


## Why `stack` cannot go into `slot_name` ("" = it can): "SCHON EIN ARMBAND ANGELEGT".
static func refusal(equipment: Dictionary, slot_name: String, stack: Dictionary) -> String:
	if conflict(equipment, slot_name, stack) == "":
		return ""
	var type: String = type_of(stack)
	var article: String = {"necklace": "EINE", "earrings": "EIN PAAR", "bracelet": "EIN"}.get(type, "EIN")
	return "SCHON %s %s ANGELEGT" % [article, String(type_info(type).get("name", "")).to_upper()]


## The worn talismans of an equipment table, in slot order, as item ids (what a peer needs to show them and to recompute the bonus).
static func worn_ids(equipment: Dictionary) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for slot_name: String in equipment:
		var stack: Dictionary = equipment[slot_name] as Dictionary
		if slot_name.begins_with(SLOT_PREFIX) and is_talisman(stack):
			ids.append(String(stack["id"]))
	return ids


static func stacks_of(ids: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids:
		out.append({"id": id, "count": 1})
	return out


## What the worn pieces add up to. Everything adds except `alarm`, which multiplies (two -50 % pieces are -75 %, not -100 %); every sum
## stays inside the limits of the catalogue. Only the first piece of each kind counts (the inventory never lets two in, a damaged save might).
static func combine(stacks: Array) -> Dictionary:
	var stats: Dictionary = catalog().get("stats", {}) as Dictionary
	var seen: Dictionary = {}
	var sum: Dictionary = {}
	var alarm: float = 1.0
	for entry: Variant in stacks:
		var stack: Dictionary = entry as Dictionary
		var type: String = type_of(stack)
		if type == "" or seen.has(type):
			continue
		seen[type] = true
		var bonus: Dictionary = bonus_of(stack)
		for key: String in bonus:
			if key == "alarm":
				alarm *= 1.0 + float(bonus[key])
			elif stats.has(key):
				sum[key] = float(sum.get(key, 0.0)) + float(bonus[key])
	if alarm != 1.0:
		sum["alarm"] = alarm - 1.0
	for key: String in sum:
		var limits: Dictionary = stats.get(key, {}) as Dictionary
		sum[key] = clampf(float(sum[key]), float(limits.get("min", -INF)), float(limits.get("max", INF)))
	return sum


## Multiplier on a weapon hit: all hits (`damage`) and, for the heavy blow, `heavy_damage` on top.
static func damage_factor(bonus: Dictionary, heavy: bool) -> float:
	var factor: float = 1.0 + float(bonus.get("damage", 0.0))
	return factor * (1.0 + float(bonus.get("heavy_damage", 0.0))) if heavy else factor


## How much faster the heavy blow charges (1.25 = a quarter faster).
static func charge_rate(bonus: Dictionary) -> float:
	return 1.0 + float(bonus.get("charge_speed", 0.0))


## Multiplier on the distance at which shadow creatures notice her (0.5 = only half as far).
static func alarm_scale(bonus: Dictionary) -> float:
	return clampf(1.0 + float(bonus.get("alarm", 0.0)), 0.25, 1.5)


## The share of every hit that is swallowed (0.25 = a quarter).
static func absorb(bonus: Dictionary) -> float:
	return clampf(float(bonus.get("absorb", 0.0)), 0.0, 0.5)


## One line of a card: "+8 % SCHADEN", "+12 LEBEN", "-50 % ALARMREICHWEITE".
static func line(key: String, value: float) -> String:
	var info: Dictionary = (catalog().get("stats", {}) as Dictionary).get(key, {}) as Dictionary
	var label: String = String(info.get("label", key.to_upper()))
	var sign: String = "+" if value >= 0.0 else "-"
	if String(info.get("unit", "flat")) == "percent":
		return "%s%d %% %s" % [sign, roundi(absf(value) * 100.0), label]
	return "%s%d %s" % [sign, roundi(absf(value)), label]


## Is `a` better than `b` for this stat? (+1 better, -1 worse, 0 equal): for the comparison on a card. Lower `alarm` is better.
static func better(key: String, a: float, b: float) -> int:
	if is_equal_approx(a, b):
		return 0
	var higher: bool = a > b
	if key == "alarm":
		higher = not higher
	return 1 if higher else -1
