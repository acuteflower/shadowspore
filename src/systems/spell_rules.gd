class_name SpellRules
extends RefCounted
## Magic (docs/magie_konzept.md), pure rules: what a staff holds and what its crystals do. Data: data/spells.json.
## A staff stack carries its crystals as extras: "sp" = the spell crystal's item id, "gm" = the gem's item id (Items.extras keeps them).
## Spell crystals ("crystal_<spell>_<tier>") carry the magic and their own recharge; gems ("gem_<mod>_<tier>") change the spell of the same staff
## when their family fits its school.

const KEY_SPELL: String = "sp"
const KEY_GEM: String = "gm"
const SOCKET_KEYS: Array[String] = ["sp", "gm", "sp2", "gm2"] ## every stone key a staff stack may carry: prong 0 ("sp"/"gm"), prong 1 ("sp2"/"gm2")


## The stack key of the spell crystal / gem of `prong` (0 = the first or only one, 1 = the second prong of a forked staff).
static func spell_key(prong: int) -> String:
	return KEY_SPELL if prong <= 0 else KEY_SPELL + "2"


static func gem_key(prong: int) -> String:
	return KEY_GEM if prong <= 0 else KEY_GEM + "2"


## Which prong a stone key belongs to, and whether it is a spell key.
static func prong_of_key(key: String) -> int:
	return 1 if key.ends_with("2") else 0


## The staff's entry in data/spells.json `staffs` ({} for anything else).
static func staff_def(staff_id: String) -> Dictionary:
	return (config().get("staffs", {}) as Dictionary).get(staff_id, {}) as Dictionary


## How many prongs (spell + gem pairs) a staff has: 1 for the Hexenulmenstab, 2 for the Bleichgabel.
static func prongs_of(staff_id: String) -> int:
	return clampi(int(staff_def(staff_id).get("spell_slots", 1)), 1, 2)


static func config() -> Dictionary:
	return DataRegistry.table("spells")


static func is_staff(stack: Dictionary) -> bool:
	return not stack.is_empty() and String(Items.definition(stack).get("tool", "")) == "staff"


static func is_spell_crystal(stack: Dictionary) -> bool:
	return not stack.is_empty() and String(Items.definition(stack).get("kind", "")) == "crystal"


static func is_gem(stack: Dictionary) -> bool:
	return not stack.is_empty() and String(Items.definition(stack).get("kind", "")) == "gem"


## "sp" for a spell crystal, "gm" for a gem, "" for anything else: the socket a stone goes into.
static func socket_of(stone: Dictionary) -> String:
	if is_spell_crystal(stone):
		return KEY_SPELL
	if is_gem(stone):
		return KEY_GEM
	return ""


## The crystal item ids set into a staff stack ("" = empty socket), of its `prong`.
static func spell_in(staff: Dictionary, prong: int = 0) -> String:
	return String(staff.get(spell_key(prong), ""))


static func gem_in(staff: Dictionary, prong: int = 0) -> String:
	return String(staff.get(gem_key(prong), ""))


## True when any stone sits in the staff.
static func has_stones(staff: Dictionary) -> bool:
	for key: String in SOCKET_KEYS:
		if String(staff.get(key, "")) != "":
			return true
	return false


## {spell, tier} of a spell crystal item id, {} for anything else.
static func spell_info(item_id: String) -> Dictionary:
	return DataRegistry.get_entry("items", item_id).get("crystal", {}) as Dictionary


## {mod, tier} of a gem item id, {} for anything else.
static func gem_info(item_id: String) -> Dictionary:
	return DataRegistry.get_entry("items", item_id).get("gem", {}) as Dictionary


static func spell_def(spell: String) -> Dictionary:
	return (config().get("spells", {}) as Dictionary).get(spell, {}) as Dictionary


static func gem_def(mod: String) -> Dictionary:
	return (config().get("gems", {}) as Dictionary).get(mod, {}) as Dictionary


static func tier_of(item_id: String) -> int:
	var info: Dictionary = spell_info(item_id) if not spell_info(item_id).is_empty() else gem_info(item_id)
	return clampi(int(info.get("tier", 1)), 1, 5)


## SPLITTER .. STERNSTEIN for spell crystals, ROHSCHLIFF .. KRONE for gems.
static func tier_name(item_id: String) -> String:
	var names: Array = (config().get("tiers", {}) as Dictionary).get("gem" if not gem_info(item_id).is_empty() else "spell", []) as Array
	var tier: int = tier_of(item_id)
	return String(names[tier - 1]) if tier - 1 < names.size() else ""


## The school of a spell crystal ("light", "root"), "" for anything else.
static func school_of(item_id: String) -> String:
	return String(spell_def(String(spell_info(item_id).get("spell", ""))).get("school", ""))


## The family of a gem (the school whose spells it works on first), "" for anything else.
static func family_of(item_id: String) -> String:
	return String(gem_def(String(gem_info(item_id).get("mod", ""))).get("family", ""))


static func school_color(school: String) -> Color:
	return Color(String(((config().get("schools", {}) as Dictionary).get(school, {}) as Dictionary).get("color", "#ffffff")))


static func family_color(family: String) -> Color:
	return Color(String(((config().get("families", {}) as Dictionary).get(family, {}) as Dictionary).get("color", "#ffffff")))


## The colour a stone (crystal or gem) glows in: its school or family.
static func stone_color(item_id: String) -> Color:
	return school_color(school_of(item_id)) if not spell_info(item_id).is_empty() else family_color(family_of(item_id))


## True when this gem works on this spell crystal (its `fits` list names the spell's school). An empty gem or crystal never fits.
static func fits(spell_item: String, gem_item: String) -> bool:
	if spell_item == "" or gem_item == "":
		return false
	var mod: Dictionary = gem_def(String(gem_info(gem_item).get("mod", "")))
	return (mod.get("fits", []) as Array).has(school_of(spell_item))


## May this stone go into this staff? (A spell crystal into the spell socket, a gem into the gem socket, not above the staff's highest tier.)
static func can_socket(staff: Dictionary, stone: Dictionary) -> bool:
	if not is_staff(staff) or stone.is_empty():
		return false
	var socket: String = socket_of(stone)
	if socket == "":
		return false
	var info: Dictionary = staff_def(String(staff.get("id", "")))
	if int(info.get("spell_slots" if socket == KEY_SPELL else "gem_slots", 1)) <= 0:
		return false
	return tier_of(String(stone["id"])) <= int(info.get("max_tier", 5))


static func _pick(values: Variant, tier: int, fallback: float = 0.0) -> float:
	var list: Array = values as Array if values is Array else []
	if list.is_empty():
		return float(values) if values is float or values is int else fallback
	return float(list[clampi(tier - 1, 0, list.size() - 1)])


## Everything one cast of this crystal does, with the gem applied when it fits:
## {spell, school, kind, cast, tier, radius, seconds, cooldown, tick, range, dps, heal, thorns, perk3, perk5, every, burst, flare, bloom, gem_ok}.
static func params(spell_item: String, gem_item: String = "") -> Dictionary:
	var info: Dictionary = spell_info(spell_item)
	if info.is_empty():
		return {}
	var spell: String = String(info.get("spell", ""))
	var tier: int = clampi(int(info.get("tier", 1)), 1, 5)
	var def: Dictionary = spell_def(spell)
	var out: Dictionary = {
		"spell": spell, "school": String(def.get("school", "")), "kind": String(def.get("kind", "")), "cast": String(def.get("cast", "light")),
		"tier": tier, "radius": _pick(def.get("radius", 32), tier), "seconds": _pick(def.get("seconds", 5), tier),
		"cooldown": _pick(def.get("cooldown", 10), tier), "tick": float(def.get("tick", 1.0)), "range": _pick(def.get("range", 0), tier),
		"dps": _pick(def.get("dps", 0), tier), "heal": _pick(def.get("heal", 0), tier), "thorns": _pick(def.get("thorns", 0), tier),
		"perk3": tier >= 3, "perk5": tier >= 5, "no_water": bool(def.get("no_water", false)), "every": 0.0, "burst": 0.0, "flare": 0.0, "bloom": 0.0, "gem_ok": false,
		## Glutschwarm, Nebelschleier, Leerenschlund (0 where a spell has no such value)
		"shards": roundi(_pick(def.get("shards", 0), tier)), "damage": _pick(def.get("damage", 0), tier), "burn_dps": _pick(def.get("burn_dps", 0), tier),
		"burn_seconds": _pick(def.get("burn_seconds", 0), tier), "focus": float(def.get("focus", 1.0)), "extend": float(def.get("extend", 0.0)),
		"pull": _pick(def.get("pull", 0), tier), "price": _pick(def.get("price", 0), tier), "refund": _pick(def.get("refund", 0), tier),
		"jump": 0.0, "ring": 0.0, "ring_share": 0.0, "ghost": 0.0, "group": 0.0, "fed": 0, "devour": 0.0,
		"rekindle": 0.0, "cloud": 0.0, "cloud_radius": 0.0, "bite2": 0.0, ## gem tier V of Zunder, Dunst, Hunger
	}
	if tier >= 3:
		var perk3: Dictionary = def.get("perk3", {}) as Dictionary
		out["jump"] = float(perk3.get("jump", 0.0))
		out["ghost"] = float(perk3.get("ghost", 0.0))
		out["fed"] = int(perk3.get("fed", 0))
	if tier >= 5:
		var perk5: Dictionary = def.get("perk5", {}) as Dictionary
		out["every"] = float(perk5.get("every", 0.0))
		out["burst"] = float(perk5.get("burst", 0.0))
		out["ring"] = float(perk5.get("ring", 0.0))
		out["ring_share"] = float(perk5.get("ring_share", 0.0))
		out["group"] = float(perk5.get("group", 0.0))
		out["devour"] = float(perk5.get("devour", 0.0))
	if fits(spell_item, gem_item):
		var gem: Dictionary = gem_info(gem_item)
		var mod: Dictionary = gem_def(String(gem.get("mod", "")))
		var gem_tier: int = clampi(int(gem.get("tier", 1)), 1, 5)
		out["gem_ok"] = true
		if mod.has("burn"):
			out["dps"] = float(out["dps"]) * (1.0 + _pick(mod["burn"], gem_tier)) ## the SONNENKERN burst and the NACHBRAND are multiples of this
		if mod.has("seconds"):
			out["seconds"] = float(out["seconds"]) * (1.0 + _pick(mod["seconds"], gem_tier))
		if mod.has("burn_up"): ## Zunder: the fire burns hotter and longer
			var up: float = 1.0 + _pick(mod["burn_up"], gem_tier)
			out["burn_dps"] = float(out["burn_dps"]) * up
			out["burn_seconds"] = float(out["burn_seconds"]) * up
		if mod.has("refund_up"): ## Hunger: more life back
			out["refund"] = float(out["refund"]) * (1.0 + _pick(mod["refund_up"], gem_tier))
		if gem_tier >= 3:
			out["radius"] = float(out["radius"]) * (1.0 + float(mod.get("radius3", 0.0)))
			out["shards"] = int(out["shards"]) + int(mod.get("shard3", 0))
			out["cooldown"] = float(out["cooldown"]) * (1.0 - float(mod.get("quick3", 0.0)))
		if gem_tier >= 5:
			out["flare"] = float(mod.get("flare", 0.0))
			out["bloom"] = float(mod.get("bloom", 0.0))
			out["rekindle"] = float(mod.get("rekindle", 0.0))
			out["cloud"] = float(mod.get("cloud", 0.0))
			out["cloud_radius"] = float(mod.get("cloud_radius", 0.0))
			out["bite2"] = float(mod.get("bite2", 0.0))
	return out


## How long one cast takes and when its magic is released (s), by the cast motion ("light" / "root").
static func cast_timing(cast: String) -> Vector2:
	var entry: Dictionary = (config().get("cast", {}) as Dictionary).get(cast, {}) as Dictionary
	return Vector2(float(entry.get("seconds", 0.8)), float(entry.get("release", 0.4)))


## Where a ground spell lands: the aimed point, pulled back to the spell's range.
static func target_point(from: Vector2, aimed: Vector2, reach: float) -> Vector2:
	if reach <= 0.0:
		return from
	return from + (aimed - from).limit_length(reach)


## The forked staff (Bleichgabel): how the two crystals in it get on. "harmony" (GLEICHKLANG, the same school: both charge faster),
## "tension" (ZWIESPALT, opposite schools from `opposites`: both charge slower, but the fork strike is fiercer) or "" (anything else, or
## a staff with one prong or an empty prong).
static func fork_bond(staff: Dictionary) -> String:
	if prongs_of(String(staff.get("id", ""))) < 2:
		return ""
	var a: String = school_of(spell_in(staff, 0))
	var b: String = school_of(spell_in(staff, 1))
	if a == "" or b == "":
		return ""
	if a == b:
		return "harmony"
	for pair: Variant in config().get("opposites", []) as Array:
		var both: Array = pair as Array
		if (both.has(a) and both.has(b)):
			return "tension"
	return ""


## The fork's numbers for a staff: {window, echo (GABELSCHLAG power), charge (factor on every recharge)}, by its bond.
static func fork_rules(staff: Dictionary) -> Dictionary:
	var fork: Dictionary = staff_def(String(staff.get("id", ""))).get("fork", {}) as Dictionary
	var bond: String = fork_bond(staff)
	return {
		"window": float(fork.get("window", 0.0)),
		"echo": float(fork.get("tension_echo" if bond == "tension" else "echo", 1.0)),
		"charge": float(fork.get("harmony_charge", 1.0)) if bond == "harmony" else (float(fork.get("tension_charge", 1.0)) if bond == "tension" else 1.0),
		"bond": bond,
	}


## GABELSCHLAG: the cast `power` times as strong (damage, burn, healing, life back; the veil and the light last a little longer).
static func empower(p: Dictionary, power: float) -> Dictionary:
	if power <= 1.0 or p.is_empty():
		return p
	var out: Dictionary = p.duplicate()
	for key: String in ["dps", "heal", "damage", "burn_dps", "thorns", "refund"]:
		out[key] = float(out.get(key, 0.0)) * power
	if String(out.get("kind", "")) in ["veil", "aura", "ground"]:
		out["seconds"] = float(out.get("seconds", 0.0)) * (1.0 + (power - 1.0) * 0.6)
	out["power"] = power
	return out


## Glutschwarm: which target each shard flies to and how hard it hits. One shard on each of the `targets` (ordered: nearest to the pointer
## first); with fewer targets than shards they come round again, and every further shard on the same target hits `focus` times as hard.
## [[target index, damage factor]] per shard, [] without targets.
static func volley_plan(targets: int, shards: int, focus: float) -> Array:
	var out: Array = []
	if targets <= 0:
		return out
	for k: int in shards:
		out.append([k % targets, 1.0 if k < targets else focus])
	return out


## Leerenschlund: the health the cast takes (a share of her maximum) and whether she can pay it (she always keeps at least one point).
static func maw_price(max_health: float, share: float) -> float:
	return ceilf(max_health * share)


static func can_pay(current: float, max_health: float, share: float) -> bool:
	return current > maw_price(max_health, share) + 1.0


## Rows of values for a stone's card: [[label, value]].
static func value_lines(item_id: String) -> Array:
	var out: Array = []
	if not spell_info(item_id).is_empty():
		var p: Dictionary = params(item_id)
		match String(p["kind"]):
			"volley":
				out.append(["SPLITTER", "%d" % int(p["shards"])])
				out.append(["TREFFER", "%s" % _num(float(p["damage"]))])
				out.append(["BRAND", "%s / S  %s S" % [_num(float(p["burn_dps"])), _num(float(p["burn_seconds"]))]])
				out.append(["BÜNDELUNG", "X%s" % _num(float(p["focus"]))])
				out.append(["REICHWEITE", "%d PX" % roundi(float(p["range"]))])
				out.append(["AUFLADEN", "%s S" % _num(float(p["cooldown"]))])
				return out
			"veil":
				out.append(["SCHLEIER", "%s S" % _num(float(p["seconds"]))])
				out.append(["REICHWEITE", "%d PX" % roundi(float(p["range"]))])
				out.append(["AUFLADEN", "%s S" % _num(float(p["cooldown"]))])
				return out
			"maw":
				out.append(["PREIS", "%d %% LEBEN" % roundi(float(p["price"]) * 100.0)])
				out.append(["BISS", "%s" % _num(float(p["damage"]))])
				out.append(["RÜCKFLUSS", "%s %% JE BEUTE" % _num(float(p["refund"]) * 100.0)])
				out.append(["SOG", "%d PX" % roundi(float(p["radius"]))])
				out.append(["REICHWEITE", "%d PX" % roundi(float(p["range"]))])
				out.append(["AUFLADEN", "%s S" % _num(float(p["cooldown"]))])
				return out
		out.append(["RADIUS", "%d PX" % roundi(float(p["radius"]))])
		out.append(["DAUER", "%s S" % _num(float(p["seconds"]))])
		if float(p["dps"]) > 0.0:
			out.append(["BRAND", "%s / S" % _num(float(p["dps"]))])
		if float(p["heal"]) > 0.0:
			out.append(["HEILUNG", "%s %% / S" % _num(float(p["heal"]) * 100.0)])
		if float(p["range"]) > 0.0:
			out.append(["REICHWEITE", "%d PX" % roundi(float(p["range"]))])
		out.append(["AUFLADEN", "%s S" % _num(float(p["cooldown"]))])
		return out
	var gem: Dictionary = gem_info(item_id)
	if gem.is_empty():
		return out
	var mod: Dictionary = gem_def(String(gem.get("mod", "")))
	var tier: int = clampi(int(gem.get("tier", 1)), 1, 5)
	if mod.has("burn"):
		out.append(["BRAND", "+%d %%" % roundi(_pick(mod["burn"], tier) * 100.0)])
	if mod.has("seconds"):
		out.append(["DAUER", "+%d %%" % roundi(_pick(mod["seconds"], tier) * 100.0)])
	if mod.has("burn_up"):
		out.append(["BRAND", "+%d %%" % roundi(_pick(mod["burn_up"], tier) * 100.0)])
	if mod.has("refund_up"):
		out.append(["RÜCKFLUSS", "+%d %%" % roundi(_pick(mod["refund_up"], tier) * 100.0)])
	return out


## The two milestone perks of a stone: [{name, text, at, on}].
static func perks(item_id: String) -> Array:
	var def: Dictionary = spell_def(String(spell_info(item_id).get("spell", ""))) if not spell_info(item_id).is_empty() else gem_def(String(gem_info(item_id).get("mod", "")))
	var tier: int = tier_of(item_id)
	var out: Array = []
	for at: int in [3, 5]:
		var perk: Dictionary = def.get("perk%d" % at, {}) as Dictionary
		if not perk.is_empty():
			out.append({"name": String(perk.get("name", "")), "text": String(perk.get("text", "")), "at": at, "on": tier >= at})
	return out


static func _num(value: float) -> String:
	return "%d" % roundi(value) if absf(value - roundf(value)) < 0.05 else "%.1f" % value
