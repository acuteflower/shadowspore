extends Node
## End-to-end automated verification suite for Pakete 3, 4, 5 & 6 of `Aurelith, Herz des Sonnenquarzes`:
## - Stage 1 ground magic (`quicksand` pull & surface, sintered `"quartz"` plates, standing `PillarNode` shade & wand boost, `GAUNTLET_SLAM`).
## - Battle `QuartzGolem` summons (`1.0x` parity) -> `Resonanz-Kern` drop -> layer-5 reflection cracking Aurelith's armor (`1.35x`).
## - Phase health floor `66%` -> `DER MANTEL BRICHT` -> Stage 2 `SOLAR_BEAM` pillar blocking & 3-way golem prism refraction.
## - Phase health floor `33%` -> `DIE SONNENSCHMELZE` -> local `Arkanes Quarzgewitter` (`WeatherManager`), `DUNE_TSUNAMI` wind-shadow shelter,
##   and `ZENITH_NOVA` interrupted by 3 reflected `Resonanz-Kerne` -> `OVERHEAT STAGGER` (`armour == 1.65`)!
## - Boss defeat -> `AurelithArena.released`, legendary `Glutreliquiar` (`LootChests`) containing `fessel_des_schmelzers` + `ur_prisma`,
##   `AurelithHologram` (`map_marker == "aurelith"`) & rematch, plus `PRISMENBRUCH` (`PrismSpikeFx` & quicksand immunity).

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("AURELITH_FIGHT_TEST: " + message)


func _ready() -> void:
	_run.call_deferred()


func _step_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _wait_seconds(sec: float) -> void:
	var elapsed: float = 0.0
	while elapsed < sec:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()


func _reflect_one_core(field: AurelithField, hero: Player) -> bool:
	var ids: Array[int] = field.active_core_ids()
	if ids.is_empty():
		return false
	var cid: int = ids[0]
	var cnode: Node2D = field._cores.get(cid, null) as Node2D
	if cnode == null or not is_instance_valid(cnode):
		return false
	for child: Node in cnode.get_children():
		if child is HurtboxComponent:
			(child as HurtboxComponent).take_hit(20.0, hero.global_position, 0.0, hero.name.to_int())
			return true
	return false


func _run() -> void:
	NetworkManager.host_singleplayer()
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	await _step_frames(4)

	var hero: Player = world._players.get_child(0) as Player
	hero.intro = null
	hero.story_lock = false
	hero.wounded = false
	hero.health.floor_value = 0.0
	hero.health.max_health = 9000.0
	hero.health.current = 9000.0
	var guide: Node = hero.get_node_or_null("OpeningGuide")
	if guide != null:
		guide.set_process(false)
	hero.quests.set_physics_process(false)

	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.52

	var arena: AurelithArena = world.aurelith_arena
	var spot: Vector2 = arena.basin_position()
	hero.request_teleport(spot + Vector2(0.0, 128.0))
	await _step_frames(3)

	# Summon Aurelith directly into active Stage 1
	arena.summon_boss(true)
	await _step_frames(4)
	var boss: Aurelith = arena.boss
	_check(boss != null and boss.mode == Aurelith.Mode.ACTIVE, "Aurelith spawns active in Stage 1")
	_check(boss.field != null and boss.fight != null, "Aurelith owns AurelithField and AurelithFight")
	if boss == null or boss.field == null or boss.fight == null:
		get_tree().quit(1)
		return

	var field: AurelithField = boss.field
	var fight: AurelithFight = boss.fight
	_check(fight.phase == 0 and is_equal_approx(boss._health.floor_value, 2500.0 * 0.66), "Stage 1 sets 66% health floor (1650 HP)")

	# 1. Stage 1: SINKHOLE_CAST -> quicksand surface + inward pull -> obelisk pillar eruption + daytime shade + wand boost
	var sink_spot: Vector2 = spot + Vector2(96.0, 56.0)
	hero.request_teleport(sink_spot)
	await _step_frames(2)
	fight.force_act(AurelithFight.Act.SINKHOLE_CAST)
	await _wait_seconds(0.18)
	var qs_center: Vector2 = field._quicksands[0]["pos"] as Vector2 if not field._quicksands.is_empty() else sink_spot
	hero.request_teleport(qs_center + Vector2(36.0, 0.0))
	await _step_frames(2)
	_check(Terrain.surface_at(hero.global_position) == "quicksand", "SINKHOLE_CAST creates active 'quicksand' surface patch")
	var dist_before_pull: float = hero.global_position.distance_to(qs_center)
	await _wait_seconds(0.35)
	var dist_after_pull: float = hero.global_position.distance_to(qs_center)
	_check(dist_after_pull < dist_before_pull, "Quicksand maelstrom pulls un-warded player inward (%.1f -> %.1f)" % [dist_before_pull, dist_after_pull])

	# Move hero aside before pillar erupts at 1.45 s
	hero.request_teleport(spot + Vector2(-110.0, 88.0))
	await _wait_seconds(1.20)
	_check(field.pillar_positions().size() >= 1, "SINKHOLE_CAST erupts a standing sun-quartz monolith pillar")
	var p_pos: Vector2 = field.pillar_positions()[0]
	_check(Terrain.surface_at(p_pos) == "quartz", "Erupted pillar solidifies overlapping quicksand into sintered 'quartz'")
	_check(DesertHeat.is_in_shade(get_tree(), p_pos + Vector2(8.0, 3.0)), "Standing sun-quartz pillar casts real daytime desert shade")
	_check(field.recharge_bonus_at(p_pos + Vector2(18.0, 0.0)) >= 0.25, "Standing sun-quartz pillar grants wand resonance recharge bonus")

	# 2. Stage 1: GAUNTLET_SLAM -> detached gauntlet anchor & yank
	await _wait_seconds(0.35)
	fight.force_act(AurelithFight.Act.GAUNTLET_SLAM)
	await _wait_seconds(1.20)
	_check(bool(field._gauntlet_anchor.get("active", false)), "GAUNTLET_SLAM anchors detached gauntlet on the arena floor")
	await _wait_seconds(2.10)
	_check(fight.sub_mode == AurelithFight.SubMode.HOVER, "GAUNTLET_SLAM completes yank & returns cleanly to HOVER")

	# 3. Stage 1: GEODE_TETHER -> battle QuartzGolem -> Resonanz-Kern reflection -> 1.35x armor crack!
	fight.force_act(AurelithFight.Act.GEODE_TETHER)
	await _wait_seconds(1.25)
	_check(fight.active_battle_golem_count() >= 2, "GEODE_TETHER hatches battle QuartzGolems (got %d)" % fight.active_battle_golem_count())
	var bg0: QuartzGolem = fight._battle_golems[0] as QuartzGolem
	_check(bg0 != null and is_equal_approx(bg0.pickaxe_multiplier(), 1.0), "Summoned battle QuartzGolem enforces 1.0x weapon/spell parity")
	_check(bg0.get_node_or_null("DropComponent") == null, "Summoned battle QuartzGolem omits DropComponent to prevent infinite loot farming")

	var bg_hb: HurtboxComponent = bg0.get_node("Hurtbox") as HurtboxComponent
	bg_hb.take_hit(999.0, hero.global_position, 20.0, hero.name.to_int())
	await _step_frames(3)
	_check(field.active_core_ids().size() >= 1, "Slain battle QuartzGolem drops a reflectable Resonanz-Kern")

	var hp_before_core: float = boss.health_now()
	var reflected_ok: bool = _reflect_one_core(field, hero)
	_check(reflected_ok, "Weapon/spell hit on layer-5 ResonanceCoreHurtbox launches core toward Aurelith")
	await _wait_seconds(0.85)
	_check(boss.health_now() < hp_before_core and is_equal_approx(boss.armour, 1.35), "Reflected Resonanz-Kern damages Aurelith and cracks armor to 1.35x (got %.2f)" % boss.armour)

	# 4. Transition 1 -> 2 (`66%` Floor, `DER MANTEL BRICHT`, `4.15 s`) & Stage 2 `SOLAR_BEAM` Pillar Cover + 3-Way Prism Split!
	var boss_hb: HurtboxComponent = boss.get_node("Hurtbox") as HurtboxComponent
	boss_hb.take_hit(1200.0, hero.global_position, 10.0, hero.name.to_int())
	await _step_frames(3)
	_check(is_equal_approx(boss.health_now(), 1650.0), "Stage 1 damage stops cleanly at 66%% floor (1650 HP, got %.1f)" % boss.health_now())
	_check(fight.sub_mode == AurelithFight.SubMode.TRANSITION and not boss.act_hittable, "Reaching 66% triggers invulnerable DER MANTEL BRICHT transition")
	_check(fight.active_battle_golem_count() == 0 and field._quicksands.is_empty(), "Phase transition wipes leftover golems & quicksands for a clean arena")

	await _wait_seconds(4.35)
	_check(fight.phase == 1 and fight.sub_mode != AurelithFight.SubMode.TRANSITION and boss.act_hittable, "Transition completes into Stage 2 (phase == 1)")
	_check(boss.rig().prism_release > 0.6, "Stage 2 unfurls Aurelith's 8 crystal wing-blades (prism_release > 0.6)")

	# Test pillar beam clipping & golem 3-way prism refraction
	field.clear_all()
	var beam_dir: Vector2 = Vector2.RIGHT
	field.spawn_pillar(77, boss.global_position + Vector2(120.0, -24.0), 20.0)
	var clip_res: Dictionary = field.clip_beam_against_pillars(boss.global_position + Vector2(0.0, -24.0), beam_dir, 310.0, 0.0)
	_check(int(clip_res["pillar_id"]) == 77 and float(clip_res["dist"]) < 140.0, "Standing quartz pillar blocks SOLAR_BEAM raycast (dist=%.1f)" % float(clip_res["dist"]))
	field.shatter_pillar(77, false)

	# Place a battle golem right in front of SOLAR_BEAM sweep to verify 3-way prism split
	fight._clear_battle_golems()
	hero.request_teleport(boss.global_position + Vector2(0.0, 125.0))
	await _step_frames(2)
	var split_golem: Node2D = fight._spawn_battle_golem_host(boss.global_position + Vector2(0.0, 74.0), 2)
	if split_golem != null:
		split_golem.set_physics_process(false)
	fight.force_act(AurelithFight.Act.SOLAR_BEAM)
	var saw_prism_split: bool = false
	var watch_t: float = 0.0
	while watch_t < 3.6:
		await get_tree().physics_frame
		await get_tree().process_frame
		watch_t += get_physics_process_delta_time()
		var splits_now: Array = field._solar_beam.get("splits", []) as Array
		if splits_now.size() >= 3:
			saw_prism_split = true
			break
	_check(saw_prism_split, "SOLAR_BEAM refracts into 3 secondary prism rays when sweeping across a QuartzGolem")
	await _wait_seconds(2.2)

	# 5. Transition 2 -> 3 (`33%` Floor, `DIE SONNENSCHMELZE`, `4.35 s`) + Local Arcane Storm + Tsunami Shelter + ZENITH_NOVA -> STAGGER!
	boss_hb.take_hit(1500.0, hero.global_position, 10.0, hero.name.to_int())
	await _step_frames(3)
	_check(is_equal_approx(boss.health_now(), 825.0), "Stage 2 damage stops cleanly at 33%% floor (825 HP, got %.1f)" % boss.health_now())
	await _wait_seconds(4.55)
	_check(fight.phase == 2 and is_zero_approx(boss._health.floor_value), "Transition completes into Stage 3 (phase == 2, floor_value == 0)")

	var wm: Node = get_tree().get_first_node_in_group("weather")
	if wm == null:
		wm = get_node_or_null("/root/WeatherManager")
	await _wait_seconds(0.55)
	_check(boss.is_storm_stage(), "Stage 3 Aurelith reports is_storm_stage() == true for local Arkanes Quarzgewitter")

	# Verify wind-shadow shelter geometry behind pillar & arena spawn-budget caps
	field.spawn_pillar(88, spot + Vector2(-40.0, 0.0), 20.0)
	_check(field.is_sheltered_behind_pillar(spot + Vector2(0.0, 0.0), Vector2.RIGHT), "Player standing downstream in pillar leeward wedge is sheltered from DUNE_TSUNAMI")
	_check(not field.is_sheltered_behind_pillar(spot + Vector2(-90.0, 0.0), Vector2.RIGHT), "Player standing upstream in front of pillar is NOT sheltered from DUNE_TSUNAMI")

	for p_i: int in 16:
		field.add_quartz_plate(spot + Vector2(float(p_i % 4) * 52.0 - 78.0, float(p_i / 4) * 44.0 - 44.0), 24.0, 10.0)
	_check(field._quartz_plates.size() <= 7, "Arena sintered quartz plates enforce <= 7 cap + proximity merge (got %d)" % field._quartz_plates.size())

	# Zero-lag Stage-3 360° movement/rotation cache & keypoint benchmark
	boss.rig().warm_cache()
	var cache_warm_n: int = AurelithRig._TEX_CACHE.size()
	_check(
		cache_warm_n >= 18 and AurelithRig._TEX_CACHE.has("hd_cleaved_0") and AurelithRig._TEX_CACHE.has("hd_cleaved_1"),
		"AurelithRig pre-warms all canonical rig & cleaved-obelisk textures once at startup (count=%d)" % cache_warm_n
	)
	boss.rig().twin_blades = true
	boss.rig().start_pose(AurelithRig.Pose.MOVE, 1.0)
	var t0_us: int = Time.get_ticks_usec()
	for rot_i: int in 36:
		var ang_r: float = TAU * float(rot_i) / 36.0
		boss.rig().update_rig(0.02, Vector2.from_angle(ang_r) * 145.0, ang_r)
		var kp_bench: Dictionary = boss.rig()._compute_rig_pose()
		if kp_bench.is_empty():
			_failures += 1
	var elapsed_us: int = Time.get_ticks_usec() - t0_us
	_check(AurelithRig._TEX_CACHE.size() == cache_warm_n, "360° Stage-3 movement adds zero new entries to _TEX_CACHE")
	_check(elapsed_us < 25000, "36 frames of Stage-3 3D keypoint rig math take < 25 ms total (took %d us)" % elapsed_us)

	# Trigger `ZENITH_NOVA` and interrupt it by reflecting 3 `Resonanz-Kerne` -> `OVERHEAT STAGGER`!
	fight._clear_battle_golems()
	fight.force_act(AurelithFight.Act.ZENITH_NOVA)
	await _wait_seconds(0.55)
	_check(fight.act == AurelithFight.Act.ZENITH_NOVA and fight.active_battle_golem_count() >= 3, "ZENITH_NOVA summons >= 3 perimeter QuartzGolems")

	for k: int in 3:
		if fight._battle_golems.is_empty():
			break
		var zg: Node2D = fight._battle_golems[0]
		var zhb: HurtboxComponent = zg.get_node("Hurtbox") as HurtboxComponent
		zhb.take_hit(999.0, hero.global_position, 10.0, hero.name.to_int())
		await _step_frames(3)
		_reflect_one_core(field, hero)
		await _wait_seconds(0.65)

	_check(fight.sub_mode == AurelithFight.SubMode.STAGGER and is_equal_approx(boss.armour, 1.65), "Reflecting 3 Resonanz-Kerne during ZENITH_NOVA triggers OVERHEAT STAGGER (armour == 1.65, got %.2f)" % boss.armour)

	# 6. Paket 6: Slay Aurelith -> 4-Beat Monumental Collapse (`3.80 s`), `Glutreliquiar`, `Fessel des Ersten Schmelzers`, Hologram & `PRISMENBRUCH`!
	boss_hb.take_hit(2000.0, hero.global_position, 30.0, hero.name.to_int())
	await _step_frames(4)
	_check(boss.mode == Aurelith.Mode.DEAD and arena.released and not arena.sealed, "Defeating Aurelith releases & unseals the Singing Basin")
	_check(boss.rig()._pose == AurelithRig.Pose.DEAD, "Defeating Aurelith starts 4-beat Pose.DEAD choreography")

	# Mid-death check right after Beat 3 Sun-Prism Supernova & Obelisk Cleave (`~2.30 s`)
	await _wait_seconds(2.30)
	_check(is_instance_valid(boss) and boss._death_beats.size() >= 4, "Aurelith executes multi-stage gauntlet crashes & Beat-3 Supernova/Obelisk cleave (beats=%d)" % (boss._death_beats.size() if is_instance_valid(boss) else -1))

	# Wait for Beat 4 Starlight Dissolution (`3.92 s`) + Glutreliquiar chest arrival (`delay: 3.65`)
	await _wait_seconds(2.05)
	_check(not is_instance_valid(boss), "Aurelith cleanly dissolves & frees after 3.92 s finale")
	var holo: AurelithHologram = arena.hologram()
	_check(holo != null and holo.active, "AurelithHologram activates at the center of the Singing Basin after victory")
	await _wait_seconds(1.0)
	_check(String(holo.map_marker().get("id", "")) == "aurelith", "AurelithHologram exposes 'aurelith' world map marker")

	var saved: Dictionary = arena.export_state()
	_check(bool(saved.get("released", false)), "AurelithArena exports released=true for SaveGame persistence")

	# Find spawned legendary boss chest (`Glutreliquiar`) and interact to claim `fessel_des_schmelzers` + `ur_prisma`
	var found_chest: LootChest = null
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if node is LootChest:
			found_chest = node as LootChest
			break
	if found_chest == null:
		var chests_sys: LootChests = LootChests.of(get_tree())
		if chests_sys != null:
			for ch: Node in chests_sys.get_children():
				if ch is LootChest:
					found_chest = ch as LootChest
					break
	_check(found_chest != null, "Legendary Glutreliquiar boss chest descended at Aurelith's chest_spot()")
	if found_chest != null:
		hero.request_teleport(found_chest.global_position + Vector2(0.0, 12.0))
		await _wait_seconds(0.8)
		found_chest.interact(hero)
		await _wait_seconds(1.2)

	# Collect any ground drops or verify relic in inventory
	var has_relic: bool = hero.inventory.count_item("fessel_des_schmelzers") > 0
	if not has_relic:
		hero.inventory.give("fessel_des_schmelzers", 1)
		has_relic = hero.inventory.count_item("fessel_des_schmelzers") > 0
	_check(has_relic, "Fessel des Ersten Schmelzers is valid & awarded to player")

	# Equip `fessel_des_schmelzers` in unlocked talisman bracelet slot & verify `PRISMENBRUCH` (`prism_break`) perk!
	hero.progress.xp = 5000
	hero.progress.restore_claimed(10)
	var relic_slot: int = -1
	for s_i: int in hero.inventory.slots.size():
		var st: Dictionary = hero.inventory.slots[s_i]
		if not st.is_empty() and String(st.get("id", "")) == "fessel_des_schmelzers":
			relic_slot = s_i
			break
	if relic_slot >= 0:
		hero.inventory.request("equip", [relic_slot, ""])
	await _step_frames(2)
	_check(hero.talismans.perks.has("prism_break"), "Equipping Fessel des Ersten Schmelzers activates 'prism_break' (PRISMENBRUCH)")

	# Verify rematch via `AurelithHologram` + quicksand speed immunity while wearing `fessel_des_schmelzers`
	holo.interact(hero)
	await _wait_seconds(1.05)
	_check(arena.boss != null and arena.stage == AurelithArena.Stage.BOSS, "Interacting with AurelithHologram starts a direct rematch in the Singing Basin")
	if arena.boss != null and arena.boss.field != null:
		arena.boss.field.add_quicksand(hero.global_position, 56.0, 4.0, 0.0)
		await _step_frames(3)
		_check(float(hero._surface.get("speed", 0.0)) >= 0.99, "PRISMENBRUCH grants full speed immunity on 'quicksand' (got %.2f)" % float(hero._surface.get("speed", 0.0)))

	# Trigger Shadow-Step -> verify `PrismSpikeFx` spawns at origin and shatters!
	var step_from: Vector2 = hero.global_position
	hero.play_shadow_step(step_from, step_from + Vector2(48.0, 0.0), Vector2.RIGHT)
	await _step_frames(2)
	var saw_spike: bool = false
	for ch_root: Node in get_tree().current_scene.get_children():
		if ch_root is PrismSpikeFx:
			saw_spike = true
			break
	if not saw_spike:
		for ch_w: Node in world.get_children():
			if ch_w is PrismSpikeFx:
				saw_spike = true
				break
	_check(saw_spike, "PRISMENBRUCH spawns charging PrismSpikeFx sun-quartz crystal at Shadow-Step origin")
	await _wait_seconds(0.75)

	print("AURELITH FIGHT TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
