class_name CrystalRules
extends RefCounted
## The lake witch's crystal craft (docs/seehexe_konzept.md 5), pure: SCHLIFF lifts a spell crystal or an amplifier gem one tier: `count` (3) equal stones of
## tier n + the tier's material + copper -> 1 stone of tier n + 1, never a failure. Numbers live in the shop's `grind` block (data/shops.json lake_counter):
## {count, tiers: {"2": {copper, trust, in {item: n}}, ... "5": ...}, gem_tiers: the same for amplifier gems}. A stone's tier comes from its item (`crystal.tier` / `gem.tier`), the next one is the
## same id with the tier number one higher (crystal_banish_2 -> crystal_banish_3).


## The tier of a crystal or gem item (0 for anything else).
static func tier_of(item: String) -> int:
	var def: Dictionary = DataRegistry.get_entry("items", item)
	if def.has("crystal"):
		return int((def.crystal as Dictionary).get("tier", 0))
	if def.has("gem"):
		return int((def.gem as Dictionary).get("tier", 0))
	return 0


## The stone one tier higher ("" when there is none: tier V, or not a stone).
static func next_of(item: String) -> String:
	var tier: int = tier_of(item)
	if tier <= 0:
		return ""
	var cut: int = item.rfind("_")
	if cut < 0:
		return ""
	var next: String = "%s_%d" % [item.substr(0, cut), tier + 1]
	return next if not DataRegistry.get_entry("items", next).is_empty() else ""


## What lifting `item` costs: {count, copper, trust, in} for its target tier ({} when it cannot be lifted).
static func cost(grind: Dictionary, item: String) -> Dictionary:
	var next: String = next_of(item)
	if next == "":
		return {}
	var table: String = "gem_tiers" if DataRegistry.get_entry("items", item).has("gem") and grind.has("gem_tiers") else "tiers" ## amplifiers are cut from moonstone, spell crystals grow from glimmer
	var tier: Dictionary = (grind.get(table, {}) as Dictionary).get(str(tier_of(item) + 1), {}) as Dictionary
	if tier.is_empty():
		return {}
	return {"count": int(grind.get("count", 3)), "copper": int(tier.get("copper", 0)), "trust": int(tier.get("trust", 0)), "in": tier.get("in", {}) as Dictionary, "out": next}


## Why lifting cannot happen now ("" = it can): `have` counts the player's items (id -> n, the stone itself included), `copper` her purse, `trust` the witch's.
static func block(grind: Dictionary, item: String, have: Dictionary, copper: int, trust: int) -> String:
	var c: Dictionary = cost(grind, item)
	if c.is_empty():
		return "HÖHER GEHT ES NICHT"
	if trust < int(c.trust):
		return "VERTRAUEN %d NÖTIG" % int(c.trust)
	if int(have.get(item, 0)) < int(c.count):
		return "%d GLEICHE STEINE NÖTIG" % int(c.count)
	for need: String in c.in as Dictionary:
		var n: int = int((c.in as Dictionary)[need]) + (int(c.count) if need == item else 0)
		if int(have.get(need, 0)) < n:
			return "ES FEHLT %s" % String(DataRegistry.get_entry("items", need).get("name", need)).to_upper()
	if copper < int(c.copper):
		return "ZU WENIG GELD"
	return ""


## Is `item` something the DEV tab may hand out (staves, crystals, gems, and the shop's listed extras)?
static func dev_allowed(dev: Dictionary, item: String) -> bool:
	if (dev.get("items", []) as Array).has(item):
		return true
	var kind: String = String(DataRegistry.get_entry("items", item).get("kind", ""))
	return (dev.get("kinds", []) as Array).has(kind) or (kind == "tool" and String(DataRegistry.get_entry("items", item).get("tool", "")) == "staff" and (dev.get("kinds", []) as Array).has("staff"))


## Every item the DEV tab lists, in a stable order (staves first, then crystals, gems, then the extras).
static func dev_items(dev: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var all: Dictionary = DataRegistry.table("items")
	for wanted: String in ["staff", "crystal", "gem"]:
		if not (dev.get("kinds", []) as Array).has(wanted):
			continue
		var ids: Array = all.keys()
		ids.sort()
		for id: Variant in ids:
			var def: Dictionary = all[id] as Dictionary
			var kind: String = String(def.get("kind", ""))
			if kind == wanted or (wanted == "staff" and kind == "tool" and String(def.get("tool", "")) == "staff"):
				out.append(String(id))
	for extra: Variant in dev.get("items", []) as Array:
		if not out.has(String(extra)) and all.has(String(extra)):
			out.append(String(extra))
	return out


# ---------- raw stones (LÄUTERN, docs/seehexe_konzept.md 14) ----------
## A raw stone (`lake_glimmer`, `lake_moonstone`) hides a stone from the moment it enters a bag: items.json `hidden` {kinds: item prefixes, tiers: {"n": weight}}.
## `InventoryComponent` rolls it (host) and keeps the rolls per raw item; Ilva's LÄUTERN shows and hands out what was rolled.

## The hidden table of `item` ({} when it is no raw stone).
static func hidden_of(item: String) -> Dictionary:
	return DataRegistry.get_entry("items", item).get("hidden", {}) as Dictionary


## One roll of a hidden table: a kind (all equal) and a tier by weight; only items that exist. `pick_kind` and `pick_tier` are 0..1 (the caller's dice).
static func roll(hidden: Dictionary, pick_kind: float, pick_tier: float) -> String:
	var kinds: Array = hidden.get("kinds", []) as Array
	var tiers: Dictionary = hidden.get("tiers", {"1": 1}) as Dictionary
	if kinds.is_empty():
		return ""
	var prefix: String = String(kinds[clampi(int(pick_kind * float(kinds.size())), 0, kinds.size() - 1)])
	var total: float = 0.0
	for key: Variant in tiers:
		total += maxf(float(tiers[key]), 0.0)
	var left: float = pick_tier * total
	var tier: int = 1
	var keys: Array = tiers.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		tier = int(key)
		left -= maxf(float(tiers[key]), 0.0)
		if left < 0.0:
			break
	while tier > 1 and DataRegistry.get_entry("items", "%s_%d" % [prefix, tier]).is_empty():
		tier -= 1
	return "%s_%d" % [prefix, tier]


## Why refreshing `amount` of `raw` cannot happen now ("" = it can). `refresh` is the shop's block {fee: {item: copper}, trust}.
static func refresh_block(refresh: Dictionary, raw: String, amount: int, have: int, copper: int, trust: int) -> String:
	var fees: Dictionary = refresh.get("fee", {}) as Dictionary
	if not fees.has(raw) or hidden_of(raw).is_empty():
		return "DAS IST KEIN ROHSTEIN"
	if trust < int(refresh.get("trust", 0)):
		return "VERTRAUEN %d NÖTIG" % int(refresh.get("trust", 0))
	if amount < 1 or have < amount:
		return "DU HAST KEINEN"
	if copper < int(fees[raw]) * amount:
		return "ZU WENIG GELD"
	return ""
