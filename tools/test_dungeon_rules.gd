extends Node
## Headless unit tests for M1 Dungeon System foundations:
## PocketSpace.Lane.DUNGEON, ResonanceRules (4-cap, 06:00 & 18:00 UTC +2 refresh, Rest Bonus,
## monotonic clock protection, weekly Echo Shard cap & Echo Exchange), DungeonRules (catalog,
## level gating, 1-4P scaling, MVP assignment, loot rolls, Bestzeit records), and DungeonProfileComponent.
## Run: Godot --headless --path . res://tools/test_dungeon_rules.tscn  (prints DUNGEON RULES OK)

var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_pocket_dungeon_lane()
	_test_resonance_epochs_and_rest()
	_test_echo_cap_and_exchange()
	_test_dungeon_rules_and_scaling()
	_test_profile_component_roundtrip()
	if _failed == 0:
		print("DUNGEON RULES OK (%d checks)" % _checks)
	else:
		push_error("DUNGEON RULES FAILED (%d/%d failed)" % [_failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		push_error("FAIL: %s" % label)


func _test_pocket_dungeon_lane() -> void:
	_check(PocketSpace.capacity(PocketSpace.Lane.DUNGEON) == 4, "4 dungeon slots")
	_check(PocketSpace.slot_size(PocketSpace.Lane.DUNGEON) == 8192.0, "dungeon slot size 8192 px")
	var rects: Array[Rect2] = []
	for lane: PocketSpace.Lane in [PocketSpace.Lane.ROOM, PocketSpace.Lane.LARGE, PocketSpace.Lane.DUNGEON]:
		for i: int in PocketSpace.capacity(lane):
			var r: Rect2 = PocketSpace.slot_rect(lane, i)
			_check(r.end.x <= PocketSpace.LIMIT and r.end.y <= PocketSpace.LIMIT, "slot %d/%d strictly in pocket space" % [lane, i])
			rects.append(r)
	var clash: bool = false
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				clash = true
	_check(not clash, "zero overlap across ROOM, LARGE, and DUNGEON slots")
	for i: int in 4:
		var o: Vector2 = PocketSpace.slot_origin(PocketSpace.Lane.DUNGEON, i)
		_check(PocketSpace.locate(o + Vector2(512.0, 512.0)) == Vector2i(PocketSpace.Lane.DUNGEON, i), "locate dungeon slot %d" % i)
	PocketSpace.clear_pockets()
	var dr0: Rect2 = PocketSpace.slot_rect(PocketSpace.Lane.DUNGEON, 0)
	PocketSpace.register_pocket(&"dungeon_0", dr0, &"suedkap")
	_check(PocketSpace.pocket_id_at(dr0.position + Vector2(128.0, 128.0)) == &"dungeon_0", "pocket_id_at dungeon_0")
	_check(PocketSpace.parent_zone_at(dr0.position + Vector2(128.0, 128.0)) == &"suedkap", "parent_zone_at suedkap")
	PocketSpace.unregister_pocket(&"dungeon_0")


func _test_resonance_epochs_and_rest() -> void:
	## 2026-11-24 06:00:00 UTC = 1795500000 (actually compute clean base aligned to 06:00 UTC)
	var base_06: int = 21600 + 20000 * 86400 ## exact 06:00 UTC on an arbitrary day
	var e0: int = ResonanceRules.epoch_for(base_06)
	_check(ResonanceRules.epoch_for(base_06 - 1) == e0 - 1, "05:59:59 UTC is previous epoch")
	_check(ResonanceRules.epoch_for(base_06 + 43199) == e0, "17:59:59 UTC still same epoch")
	_check(ResonanceRules.epoch_for(base_06 + 43200) == e0 + 1, "18:00:00 UTC starts next epoch")
	_check(ResonanceRules.seconds_until_next_refresh(base_06 + 3600) == 39600, "countdown 11h after 07:00 UTC")

	var st: Dictionary = ResonanceRules.fresh_state(base_06 + 60)
	_check(int(st["charges"]) == 4 and int(st["rest_units"]) == 0, "fresh player starts at 4/4 charges, 0 rest")

	## Spend 3 charges (leaves 1)
	for _i: int in 3:
		var c: Dictionary = ResonanceRules.consume_for_victory(st, base_06 + 120, true)
		_check(bool(c["consumed_resonance"]) and not bool(c["consumed_rest_double"]), "consumed 1 resonance")
		st = c["state"] as Dictionary
	_check(int(st["charges"]) == 1, "1 charge left after 3 resonance clears")

	## Victory WITHOUT resonance checkbox leaves charge untouched
	var no_res: Dictionary = ResonanceRules.consume_for_victory(st, base_06 + 180, false)
	_check(not bool(no_res["consumed_resonance"]) and int((no_res["state"] as Dictionary)["charges"]) == 1, "opt-out keeps charge")
	st = no_res["state"] as Dictionary

	## 18:00 UTC refresh (+2 -> 3/4)
	st = ResonanceRules.sync_state(st, base_06 + 43200 + 10)
	_check(int(st["charges"]) == 3 and int(st["rest_units"]) == 0, "evening refresh +2 -> 3/4")

	## Next morning 06:00 UTC refresh (+2 -> 4/4 + 1 overflow into rest_units)
	st = ResonanceRules.sync_state(st, base_06 + 86400 + 10)
	_check(int(st["charges"]) == 4 and int(st["rest_units"]) == 1, "overflow +1 into rest_units")

	## Next evening 18:00 UTC refresh (+2 -> still 4/4, +2 rest_units -> 3 = 1 double ready)
	st = ResonanceRules.sync_state(st, base_06 + 129600 + 10)
	_check(int(st["charges"]) == 4 and int(st["rest_units"]) == 3, "second overflow -> rest_units 3")
	_check(ResonanceRules.rest_doubles_ready(st) == 1, "1 rest double ready at 3 units")

	## Victory WITH resonance consumes 1 charge AND 2 rest_units (doubled reward!)
	var doubled: Dictionary = ResonanceRules.consume_for_victory(st, base_06 + 129700, true)
	st = doubled["state"] as Dictionary
	_check(bool(doubled["consumed_resonance"]) and bool(doubled["consumed_rest_double"]), "rest bonus doubles reward")
	_check(int(st["charges"]) == 3 and int(st["rest_units"]) == 1, "3 charges and 1 leftover rest_unit remain")

	## Monotonic clock anti-cheat: setting clock backwards must NOT rollback or grant extra refreshes
	var tampered: Dictionary = ResonanceRules.sync_state(st, base_06)
	_check(int(tampered["charges"]) == 3 and int(tampered["last_seen_unix"]) == base_06 + 129700, "backwards clock ignored")


func _test_echo_cap_and_exchange() -> void:
	var mon_06: int = 367200 + 2900 * 604800 ## Monday 06:00 UTC
	var st: Dictionary = ResonanceRules.fresh_state(mon_06 + 100)
	var g1: Dictionary = ResonanceRules.grant_echo_shards(st, mon_06 + 120, 100)
	st = g1["state"] as Dictionary
	_check(int(g1["granted"]) == 100 and not bool(g1["capped"]), "grant 100 echo shards")
	var g2: Dictionary = ResonanceRules.grant_echo_shards(st, mon_06 + 140, 50)
	st = g2["state"] as Dictionary
	_check(int(g2["granted"]) == 20 and bool(g2["capped"]) and int(st["echo_shards"]) == 120, "weekly cap 120 enforced")

	## Pity offer locked before first clear
	var sword_offer: Dictionary = DungeonRules.exchange_by_id("ex_harbor_sword")
	_check(not sword_offer.is_empty(), "ex_harbor_sword exists")
	var fail_buy: Dictionary = ResonanceRules.purchase_exchange(st, mon_06 + 200, sword_offer, {})
	_check(not bool(fail_buy["ok"]), "pity sword locked before first clear")

	## Buy after first clear succeeds (120 - 55 = 65)
	var cleared_map: Dictionary = {"suedkap_gezeitenkammern": 1}
	var ok_buy: Dictionary = ResonanceRules.purchase_exchange(st, mon_06 + 220, sword_offer, cleared_map)
	_check(bool(ok_buy["ok"]) and String(ok_buy["item_id"]) == "harbor_guard_sword", "pity sword bought after clear")
	st = ok_buy["state"] as Dictionary
	_check(int(st["echo_shards"]) == 65, "echo shards deducted to 65")

	## Buying same 1/week offer again fails
	var second_buy: Dictionary = ResonanceRules.purchase_exchange(st, mon_06 + 240, sword_offer, cleared_map)
	_check(not bool(second_buy["ok"]), "weekly_limit=1 blocks second buy")

	## Next Monday 06:00 UTC resets weekly cap and weekly exchange limits
	var next_mon: int = mon_06 + 604800 + 10
	st = ResonanceRules.sync_state(st, next_mon)
	_check(int(st["echo_week_earned"]) == 0 and (st["exchange_bought"] as Dictionary).is_empty(), "weekly reset clears earned & bought")


func _test_dungeon_rules_and_scaling() -> void:
	var all_d: Array[Dictionary] = DungeonRules.all()
	_check(all_d.size() == 10, "10 ALTMARK dungeons catalogued")
	var d1: Dictionary = DungeonRules.by_id("suedkap_gezeitenkammern")
	_check(not d1.is_empty() and int(d1["min_level"]) == 5 and String(d1["archetype"]) == "expedition", "Sturmhafen Lv 5 expedition")
	_check(not bool(DungeonRules.can_enter(4, d1)["ok"]), "Lv 4 blocked from Lv 5 dungeon")
	_check(bool(DungeonRules.can_enter(5, d1)["ok"]), "Lv 5 allowed into Lv 5 dungeon")
	var d2: Dictionary = DungeonRules.by_id("erlenfurt_brueckenkopf")
	_check(not bool(DungeonRules.can_enter(20, d2)["ok"]), "unplayable future dungeon blocked")

	_check(is_equal_approx(DungeonRules.hp_scale(1), 1.0) and is_equal_approx(DungeonRules.hp_scale(4), 2.8), "HP scaling 1P..4P")
	_check(is_equal_approx(DungeonRules.stagger_scale(2), 1.75), "Stagger scaling 2P")

	var rec1: Dictionary = DungeonRules.record_victory({}, "suedkap_gezeitenkammern", 412.5, 2, 1, 1450.0, 3)
	_check(bool(rec1["new_best_time"]), "first clear sets best time")
	var rec2: Dictionary = DungeonRules.record_victory(rec1["records"] as Dictionary, "suedkap_gezeitenkammern", 450.0, 3, 1, 1500.0, 1)
	_check(not bool(rec2["new_best_time"]), "slower clear is not new best")
	var rec3: Dictionary = DungeonRules.record_victory(rec2["records"] as Dictionary, "suedkap_gezeitenkammern", 355.0, 4, 2, 1800.0, 0)
	_check(bool(rec3["new_best_time"]), "faster clear is new best")
	var row: Dictionary = (rec3["records"] as Dictionary)["suedkap_gezeitenkammern"] as Dictionary
	_check(int(row["clears"]) == 3 and int(row["min_hits"]) == 0 and int(row["best_counters"]) == 4, "records aggregated")

	var mvp: Dictionary = DungeonRules.assign_mvp_titles([
		{"peer_id": 1, "name": "Ellie", "damage": 900.0, "counters": 3, "staggers": 1, "hits_taken": 2},
		{"peer_id": 2, "name": "Val", "damage": 600.0, "counters": 1, "staggers": 3, "hits_taken": 0},
	])
	_check((mvp[1] as Array).size() == 2 and (mvp[2] as Array).size() == 2, "MVP titles assigned across 2 players")

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var loot_fc: Dictionary = DungeonRules.roll_victory_rewards(d1, rng, true, true, true, true)
	_check(int(loot_fc["xp"]) == 240 + 140 * 2, "first clear + doubled resonance XP")
	_check((loot_fc["first_clear_items"] as Array).size() >= 1, "first clear items populated")


func _test_profile_component_roundtrip() -> void:
	NetworkManager.host_singleplayer()
	var comp: DungeonProfileComponent = DungeonProfileComponent.new()
	comp.set_multiplayer_authority(1)
	add_child(comp)
	var t0: int = 21600 + 21000 * 86400 + 100
	comp.import_data({"resonance": ResonanceRules.fresh_state(t0)})
	comp.mark_discovered("suedkap_gezeitenkammern")
	_check(comp.is_discovered("suedkap_gezeitenkammern"), "discovered flag set")
	var vres: Dictionary = comp.apply_victory("suedkap_gezeitenkammern", true, 320.0, 2, 1, 980.0, 1, 16, t0 + 50)
	_check(bool(vres["first_clear"]) and bool(vres["consumed_resonance"]) and bool(vres["new_best_time"]), "profile apply_victory works")
	_check(comp.charges() == 3 and comp.echo_shards() == 16 and comp.clear_count("suedkap_gezeitenkammern") == 1, "profile balances updated")
	var saved: Dictionary = comp.export_data()
	var comp2: DungeonProfileComponent = DungeonProfileComponent.new()
	comp2.set_multiplayer_authority(1)
	add_child(comp2)
	comp2.import_data(saved)
	_check(comp2.charges() == 3 and comp2.echo_shards() == 16 and comp2.clear_count("suedkap_gezeitenkammern") == 1, "profile export/import roundtrip")
	comp.queue_free()
	comp2.queue_free()
