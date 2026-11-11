class_name LootRules
extends RefCounted
## Pure rules of the loot chests (docs/beutetruhen_konzept.md): what a chest of a tier holds. Data: data/loot_chests.json
## (`tiers[t].draws` = [{pool, count: [min, max], chance}], `pools[p]` = [{id, w, n: [min, max]}]).
## Inside one draw nothing is picked twice; the same item from two draws is put together. The result is sorted by rarity, the
## commonest first, so the best piece jumps out of the chest last.

const TIERS: Array[String] = ["common", "rare", "legendary"]


## The stacks [{id, count}] a chest of `tier` gives; `players` near it: every one past the first adds `per_player` picks from `extra`.
static func roll(tier: Dictionary, pools: Dictionary, rng: RandomNumberGenerator, players: int = 1) -> Array[Dictionary]:
	var got: Dictionary = {} ## id -> count, in the order found
	for draw: Dictionary in tier.get("draws", []) as Array:
		if rng.randf() > float(draw.get("chance", 1.0)):
			continue
		var span: Array = draw.get("count", [1, 1]) as Array
		_pick(pools.get(String(draw.get("pool", "")), []) as Array, rng.randi_range(int(span[0]), int(span[1])), rng, got)
	var extra: int = maxi(players - 1, 0) * int(tier.get("per_player", 0))
	if extra > 0:
		_pick(pools.get(String(tier.get("extra", "")), []) as Array, extra, rng, got)
	var out: Array[Dictionary] = []
	for id: String in got:
		out.append({"id": id, "count": int(got[id])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = rarity_rank(String(a.id))
		var rb: int = rarity_rank(String(b.id))
		return ra < rb if ra != rb else String(a.id) < String(b.id))
	return out


## `n` different entries of `entries` by weight (fewer when the pool is smaller), each with its own count.
static func _pick(entries: Array, n: int, rng: RandomNumberGenerator, got: Dictionary) -> void:
	var left: Array = entries.duplicate()
	for i: int in n:
		var total: float = 0.0
		for entry: Dictionary in left:
			total += float(entry.get("w", 1.0))
		if total <= 0.0:
			return
		var roll_at: float = rng.randf() * total
		for k: int in left.size():
			var entry: Dictionary = left[k] as Dictionary
			roll_at -= float(entry.get("w", 1.0))
			if roll_at <= 0.0 or k == left.size() - 1:
				var span: Array = entry.get("n", [1, 1]) as Array
				var id: String = String(entry.id)
				got[id] = int(got.get(id, 0)) + rng.randi_range(int(span[0]), int(span[1]))
				left.remove_at(k)
				break


## 0 common .. 4 legendary (the order of data/rarities.json); unknown items count as common.
static func rarity_rank(id: String) -> int:
	var rarity: String = String(DataRegistry.get_entry("items", id).get("rarity", "common"))
	return maxi(DataRegistry.table("rarities").keys().find(rarity), 0)


## The rarest piece of a roll (-1 for none).
static func best_rank(items: Array[Dictionary]) -> int:
	var best: int = -1
	for stack: Dictionary in items:
		best = maxi(best, rarity_rank(String(stack.id)))
	return best
