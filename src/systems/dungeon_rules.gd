class_name DungeonRules
extends RefCounted
## Pure catalog, entry validation, 1-4 player scaling, reward rolling, and record tracking
## for Shadowspore's Dungeon System (docs/dungeon_konzept.md).

static func table() -> Dictionary:
	return DataRegistry.table("dungeons")


static func all() -> Array[Dictionary]:
	var raw: Variant = table().get("dungeons", [])
	var out: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Dictionary:
				out.append(entry as Dictionary)
	return out


static func by_id(dungeon_id: String) -> Dictionary:
	for entry: Dictionary in all():
		if String(entry.get("id", "")) == dungeon_id:
			return entry
	return {}


static func in_zone(zone_id: StringName) -> Array[Dictionary]:
	var z_str: String = String(zone_id)
	var out: Array[Dictionary] = []
	for entry: Dictionary in all():
		if String(entry.get("zone", "")) == z_str:
			out.append(entry)
	return out


static func archetype_info(archetype: String) -> Dictionary:
	var map: Variant = table().get("archetypes", {})
	if map is Dictionary and (map as Dictionary).has(archetype):
		return (map as Dictionary)[archetype] as Dictionary
	return {"code": "?", "name": archetype.to_upper(), "short": archetype.to_upper(), "color": "78f4e6", "summary": ""}


static func exchange_offers() -> Array[Dictionary]:
	var raw: Variant = table().get("echo_exchange", [])
	var out: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Dictionary:
				out.append(entry as Dictionary)
	return out


static func exchange_by_id(offer_id: String) -> Dictionary:
	for offer: Dictionary in exchange_offers():
		if String(offer.get("id", "")) == offer_id:
			return offer
	return {}


## Validates whether a player at `player_level` can enter `def`.
## Returns {"ok": bool, "reason": String}.
static func can_enter(player_level: int, def: Dictionary) -> Dictionary:
	if def.is_empty():
		return {"ok": false, "reason": "UNBEKANNTES GEWÖLBE"}
	if not bool(def.get("playable", false)) or String(def.get("scene", "")).is_empty():
		return {"ok": false, "reason": "NOCH VERSIEGELT"}
	var min_lv: int = int(def.get("min_level", 1))
	if player_level < min_lv:
		return {"ok": false, "reason": "BENÖTIGT STUFE %d" % min_lv}
	return {"ok": true, "reason": ""}


static func _scale_curve(key: String, players: int, fallback: Array[float]) -> float:
	var scaling: Variant = table().get("scaling", {})
	var idx: int = clampi(players - 1, 0, 3)
	if scaling is Dictionary:
		var arr: Variant = (scaling as Dictionary).get(key)
		if arr is Array and idx < (arr as Array).size():
			return float((arr as Array)[idx])
	return fallback[idx]


static func hp_scale(player_count: int) -> float:
	return _scale_curve("hp", player_count, [1.0, 1.65, 2.25, 2.80])


static func damage_scale(player_count: int) -> float:
	return _scale_curve("damage", player_count, [1.0, 1.10, 1.18, 1.25])


static func stagger_scale(player_count: int) -> float:
	return _scale_curve("stagger", player_count, [1.0, 1.75, 2.40, 3.00])


## Updates a player's per-dungeon record table with a completed run.
## Returns {"records": Dictionary, "new_best_time": bool}.
static func record_victory(records_raw: Dictionary, dungeon_id: String, clear_sec: float, counters: int, staggers: int, damage: float, hits_taken: int) -> Dictionary:
	var records: Dictionary = records_raw.duplicate(true)
	var prev: Dictionary = {}
	if records.has(dungeon_id) and records[dungeon_id] is Dictionary:
		prev = (records[dungeon_id] as Dictionary).duplicate(true)
	var prev_best: float = float(prev.get("best_sec", 0.0))
	var new_best: bool = prev_best <= 0.0 or clear_sec < prev_best
	var best_sec: float = clear_sec if new_best else prev_best
	prev["best_sec"] = snappedf(best_sec, 0.01)
	prev["clears"] = int(prev.get("clears", 0)) + 1
	prev["best_counters"] = maxi(int(prev.get("best_counters", 0)), counters)
	prev["best_staggers"] = maxi(int(prev.get("best_staggers", 0)), staggers)
	prev["best_damage"] = maxf(float(prev.get("best_damage", 0.0)), snappedf(damage, 1.0))
	var prev_hits: int = int(prev.get("min_hits", -1))
	prev["min_hits"] = hits_taken if prev_hits < 0 else mini(prev_hits, hits_taken)
	records[dungeon_id] = prev
	return {"records": records, "new_best_time": new_best}


static func format_time(seconds: float) -> String:
	var total: int = maxi(int(floor(seconds)), 0)
	var mins: int = total / 60
	var secs: int = total % 60
	return "%02d:%02d" % [mins, secs]


## Computes MVP badges for a 2-4 player party from per-peer stats:
## `party_stats`: Array of {"peer_id": int, "name": String, "damage": float, "counters": int, "staggers": int, "hits_taken": int}.
static func assign_mvp_titles(party_stats: Array[Dictionary]) -> Dictionary:
	var titles: Dictionary = {} ## peer_id -> Array[String]
	if party_stats.size() < 2:
		return titles
	var total_dmg: float = 0.0
	var best_dmg_peer: int = -1
	var best_dmg: float = -1.0
	var best_cnt_peer: int = -1
	var best_cnt: int = 0
	var best_stg_peer: int = -1
	var best_stg: int = 0
	var cleanest_peer: int = -1
	var cleanest_hits: int = 999999

	for row: Dictionary in party_stats:
		var pid: int = int(row.get("peer_id", 0))
		titles[pid] = []
		var dmg: float = float(row.get("damage", 0.0))
		var cnt: int = int(row.get("counters", 0))
		var stg: int = int(row.get("staggers", 0))
		var hits: int = int(row.get("hits_taken", 0))
		total_dmg += dmg
		if dmg > best_dmg:
			best_dmg = dmg
			best_dmg_peer = pid
		if cnt > best_cnt:
			best_cnt = cnt
			best_cnt_peer = pid
		if stg > best_stg:
			best_stg = stg
			best_stg_peer = pid
		if hits < cleanest_hits:
			cleanest_hits = hits
			cleanest_peer = pid

	if best_dmg_peer > 0 and total_dmg > 0.0:
		var pct: int = int(round((best_dmg / total_dmg) * 100.0))
		(titles[best_dmg_peer] as Array).append("SCHICKSALSKLINGE (%d%%)" % pct)
	if best_cnt_peer > 0 and best_cnt >= 1:
		(titles[best_cnt_peer] as Array).append("KLANGBRECHER (%d)" % best_cnt)
	if best_stg_peer > 0 and best_stg >= 1:
		(titles[best_stg_peer] as Array).append("ERSCHÜTTERER (%d)" % best_stg)
	if cleanest_peer > 0 and cleanest_hits == 0:
		(titles[cleanest_peer] as Array).append("UNBERÜHRT")
	return titles


## Rolls a single player's completion rewards deterministically from `rng`.
## Returns {"xp": int, "copper": int, "echo_shards": int, "items": Array[Dictionary], "first_clear_items": Array[Dictionary]}.
static func roll_victory_rewards(def: Dictionary, rng: RandomNumberGenerator, first_clear: bool, used_resonance: bool, doubled_by_rest: bool, lantern_broken: bool = false) -> Dictionary:
	var xp: int = 0
	var copper: int = 0
	var echo: int = 0
	var items: Array[Dictionary] = []
	var fc_items: Array[Dictionary] = []

	if first_clear:
		var fc: Dictionary = def.get("first_clear", {}) as Dictionary
		xp += int(fc.get("xp", 0))
		copper += int(fc.get("copper", 0))
		var fc_list: Variant = fc.get("items", [])
		if fc_list is Array:
			for it_v: Variant in fc_list as Array:
				if it_v is Dictionary:
					var it: Dictionary = it_v as Dictionary
					fc_items.append({"id": String(it.get("id", "")), "count": maxi(int(it.get("count", 1)), 1)})

	if used_resonance:
		var mult: int = 2 if doubled_by_rest else 1
		var res_def: Dictionary = def.get("resonance_reward", {}) as Dictionary
		xp += int(res_def.get("xp", 100)) * mult
		var cop_range: Array = res_def.get("copper", [40, 60]) as Array
		var echo_range: Array = res_def.get("echo_shards", [12, 16]) as Array
		for _m: int in mult:
			if cop_range.size() >= 2:
				copper += rng.randi_range(int(cop_range[0]), int(cop_range[1]))
			if echo_range.size() >= 2:
				echo += rng.randi_range(int(echo_range[0]), int(echo_range[1]))
			var guar: Variant = res_def.get("guaranteed", [])
			if guar is Array:
				for g_v: Variant in guar as Array:
					if g_v is Dictionary:
						var gd: Dictionary = g_v as Dictionary
						var cnt: int = rng.randi_range(int(gd.get("min", 1)), int(gd.get("max", 1)))
						if cnt > 0:
							_merge_item(items, String(gd.get("id", "")), cnt)
			var excl: Variant = res_def.get("exclusive", [])
			if excl is Array:
				for e_v: Variant in excl as Array:
					if e_v is Dictionary:
						var ed: Dictionary = e_v as Dictionary
						if rng.randf() < float(ed.get("chance", 0.0)):
							_merge_item(items, String(ed.get("id", "")), 1)
							break ## at most one exclusive per resonance roll
	else:
		var rep: Dictionary = def.get("repeat_reward", {}) as Dictionary
		xp += int(rep.get("xp", 25))
		var cop_r: Array = rep.get("copper", [12, 20]) as Array
		if cop_r.size() >= 2:
			copper += rng.randi_range(int(cop_r[0]), int(cop_r[1]))
		var echo_r: Array = rep.get("echo_shards", [10, 16]) as Array
		if echo_r.size() >= 2:
			echo += rng.randi_range(int(echo_r[0]), int(echo_r[1]))
		var bonus: Variant = rep.get("bonus_items", [])
		if bonus is Array:
			for b_v: Variant in bonus as Array:
				if b_v is Dictionary:
					var bd: Dictionary = b_v as Dictionary
					if rng.randf() < float(bd.get("chance", 0.5)):
						var cnt: int = rng.randi_range(int(bd.get("min", 1)), int(bd.get("max", 1)))
						if cnt > 0:
							_merge_item(items, String(bd.get("id", "")), cnt)

	if lantern_broken:
		_merge_item(items, "lake_glimmer", 1)

	return {
		"xp": xp,
		"copper": copper,
		"echo_shards": echo,
		"items": items,
		"first_clear_items": fc_items,
	}


static func _merge_item(list: Array[Dictionary], item_id: String, count: int) -> void:
	if item_id.is_empty() or count <= 0:
		return
	var idef: Dictionary = DataRegistry.table("items").get(item_id, {}) as Dictionary
	var stackable: bool = int(idef.get("max_stack", 99)) > 1
	if stackable:
		for row: Dictionary in list:
			if String(row.get("id", "")) == item_id:
				row["count"] = int(row.get("count", 1)) + count
				return
	list.append({"id": item_id, "count": count})
