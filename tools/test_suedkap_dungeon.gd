extends Node
## End-to-end headless playthrough test of Dungeon #1: Die Gezeitenkammern von Sturmhafen.
## Tests level gating, PocketSpace.Lane.DUNGEON mount, Section 1-4 mechanics,
## Secret Smuggler Alcove, West Tide Bell water lowering, East Weight Stone -> Winch -> Checkpoint Brazier,
## Endboss Vorgath (Rammflut Blue Counter, Hafenlaterne weakpoint break, 60% Golden Stagger Check,
## 30% Springflut bollard shelter & puddle washout), Victory Reliquary, Bestzeit, Resonance consumption,
## and clean exit & unmount via DungeonExitSeal.
## Run: Godot --headless --path . res://tools/test_suedkap_dungeon.tscn

var _checks: int = 0
var _failed: int = 0
var _victory_payload: Dictionary = {}


func _ready() -> void:
	NetworkManager.host_singleplayer()
	call_deferred("_run_all")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		push_error("FAIL: %s" % label)


func _run_all() -> void:
	var dm: DungeonManager = DungeonManager.new()
	dm.instant_transitions = true
	dm.respawn_delay_sec = 0.0
	add_child(dm)
	dm.run_victory_received.connect(func(sum: Dictionary) -> void: _victory_payload = sum)

	var player: Player = preload("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	var overworld_origin: Vector2 = Vector2(1200.0, 800.0)
	player.global_position = overworld_origin
	add_child(player)
	await get_tree().process_frame

	## 1. Level gating: Lv 1 must be blocked from entering Lv 5 dungeon
	player.dungeons.mark_discovered("suedkap_gezeitenkammern")
	dm.request_enter_solo("suedkap_gezeitenkammern", true)
	await get_tree().process_frame
	_check(not dm.is_player_in_dungeon(1), "Lv 1 player rejected from Lv 5 dungeon")

	## Level player to Lv 5 & enter Dungeon #1 solo
	player.progress.award(0, Levels.xp_at(5))
	player.progress.request_claim(5)
	_check(player.progress.level >= 5, "player reached Lv 5")
	var charges_before: int = player.dungeons.charges()
	_check(charges_before == 4, "fresh player has 4 resonance charges")

	dm.request_enter_solo("suedkap_gezeitenkammern", true)
	for _i: int in 4:
		await get_tree().process_frame
	_check(dm.is_player_in_dungeon(1), "Lv 5 player mounted into Dungeon #1")
	_check(PocketSpace.locate(player.global_position).x == PocketSpace.Lane.DUNGEON, "player inside PocketSpace.Lane.DUNGEON")

	var scene: SuedkapGezeitenkammern = dm.active_scene_for_peer(1) as SuedkapGezeitenkammern
	_check(scene != null, "SuedkapGezeitenkammern scene mounted")
	if scene == null:
		_finish()
		return

	## 2. Section 1: Clear 4 ShadowSpiders warmup -> opens West Gate
	_check(not scene.section1_cleared, "Section 1 starts locked")
	for n: Node in scene._s1_enemies.duplicate():
		if is_instance_valid(n):
			var hc: HealthComponent = n.get_node_or_null("HealthComponent") as HealthComponent
			if hc != null:
				hc.take_damage(999.0, player.global_position, 0.0, 1)
	await get_tree().process_frame
	_check(scene.section1_cleared, "Section 1 cleared -> West Gate opens")

	## 3. Secret Smuggler Alcove: smash planks & loot chest
	_check(scene._planks_node != null and not scene.planks_broken, "Smuggler planks intact initially")
	scene._planks_node.health.take_damage(100.0, player.global_position, 0.0, 1)
	await get_tree().process_frame
	_check(scene.planks_broken, "Smuggler planks smashed")
	var iron_before: int = player.inventory.count_item("iron_ingot")
	scene._smuggler_chest.interact(player)
	_check(scene.smuggler_looted and player.inventory.count_item("iron_ingot") >= iron_before + 2, "Smuggler chest granted bonus iron_ingot")

	## 4. Section 2: Sever 3 Spore Tendrils & ring West Tide Bell -> lowers tide 1.0 -> 0.5
	_check(scene.tendrils_cut == 0 and not scene.bell_rung, "West Tide Bell starts overgrown")
	for td: Node in scene._tendrils.duplicate():
		if is_instance_valid(td):
			var hc2: HealthComponent = td.get_node_or_null("HealthComponent") as HealthComponent
			if hc2 != null:
				hc2.take_damage(100.0, player.global_position, 0.0, 1)
	await get_tree().process_frame
	_check(scene.tendrils_cut == 3, "all 3 spore tendrils severed")
	scene._tide_bell.interact(player)
	for _i: int in 3:
		await get_tree().process_frame
	_check(scene.bell_rung and scene._target_tide < 0.6, "West Tide Bell rung -> tide lowering to 0.5")

	## 5. Section 3: Carry East Weight Stone to Winch -> opens Floodgate + Checkpoint Brazier
	player.health.take_damage(20.0, player.global_position, 0.0, 0)
	var hp_pre_brazier: float = player.health.current
	scene._weight_stone.interact(player)
	_check(scene.stone_carrier_peer == 1, "player picked up East Weight Stone")
	scene._east_winch.interact(player)
	_check(scene.floodgate_open and scene.brazier_lit, "East Winch opened Floodgate & lit Checkpoint Brazier")
	_check(player.health.current > hp_pre_brazier, "Checkpoint Brazier healed player")

	## 6. Section 4: Trigger Vorgath Boss Fight & verify all Lost-Ark mechanics!
	var boss: VorgathBoss = scene.vorgath
	_check(boss != null, "VorgathBoss spawned in Schleusenbecken")
	player.global_position = scene.global_position + Vector2(0.0, -110.0)
	for _i: int in 3:
		await get_tree().process_frame
	_check(scene.boss_started and boss.state == VorgathBoss.State.CHASE, "entering Schleusenbecken activates Vorgath")

	## 6a. Rammflut Blue-Flash Counter
	boss._enter_state(VorgathBoss.State.RAM_COUNTER)
	_check(boss.counter.window_open, "Rammflut opened blue Counter window")
	var front_attacker_pos: Vector2 = boss.global_position + boss.facing * 26.0
	var countered: bool = CounterComponent.try_hit_counter(boss, front_attacker_pos, 1)
	_check(countered and boss.counter.is_stunned() and boss.state == VorgathBoss.State.STUNNED, "frontal hit triggered Klangkonter + stun")
	_check(is_equal_approx(CounterComponent.vulnerability_of(boss), 1.25), "countered Vorgath takes +25% vuln")

	## 6b. Hafenlaterne rear weakpoint break
	_check(boss.lantern_intact, "Hafenlaterne starts intact")
	boss.damage_lantern(200.0, 1)
	_check(not boss.lantern_intact and scene.bonus_part_broken, "Hafenlaterne shattered -> bonus_part_broken = true")

	## 6c. 60% Sog des Tiefendocks Golden Stagger Check
	boss.counter.stun_left = 0.0
	boss._enter_state(VorgathBoss.State.STAGGER_CAST)
	_check(boss.stagger.active, "Sog des Tiefendocks opened golden Stagger Check")
	var broke: bool = StaggerComponent.try_hit_stagger(boss, 180.0, 1)
	_check(broke and boss.stagger.is_exposed() and boss.state == VorgathBoss.State.EXPOSED, "heavy stagger hits triggered TAUMELBRUCH -> EXPOSED")
	_check(is_equal_approx(StaggerComponent.vulnerability_of(boss), 1.30), "exposed Vorgath takes +30% vuln")

	## 6d. 30% Springflut Bollard Shelter + Puddle Washout
	var b0: Vector2 = boss.bollard_positions[0]
	_check(boss.is_sheltered_by_bollard(b0 + Vector2(0.0, 32.0)), "standing south behind bollard is SHELTERED")
	_check(not boss.is_sheltered_by_bollard(boss.arena_center + Vector2(0.0, 70.0)), "standing in open basin is EXPOSED to wave")
	boss._puddles.append({"pos": boss.arena_center, "life": 6.0, "radius": 24.0, "tick": 1.0})
	boss._enter_state(VorgathBoss.State.TIDE_WAVE)
	boss._wave_y = boss.arena_center.y + 40.0
	boss._physics_process(0.016)
	_check(boss._puddles.is_empty(), "Springflut tidal wave washed away Brackwasser puddles")

	## 7. Defeat Vorgath -> Victory, Reliquary, Bestzeit, Resonance consumed, Echo Shards, Exit Seal!
	boss.health.take_damage(9999.0, player.global_position, 0.0, 1)
	for _i: int in 4:
		await get_tree().process_frame
	_check(scene.completed, "DungeonScene marked completed on Vorgath death")
	_check(not _victory_payload.is_empty(), "DungeonManager emitted victory_shown summary")
	_check(bool(_victory_payload.get("first_clear", false)), "victory marked as First Clear")
	_check(bool(_victory_payload.get("used_resonance", false)), "Resonance consumed on victory")
	_check(bool(_victory_payload.get("bonus_part_broken", false)), "bonus_part_broken forwarded to victory summary")
	_check(player.dungeons.charges() == charges_before - 1, "player charges decremented 4 -> 3")
	_check(player.dungeons.echo_shards() >= 14, "player received >= 14 Echo Shards")
	_check(player.dungeons.clear_count("suedkap_gezeitenkammern") == 1, "clear_count recorded as 1")
	_check(float(player.dungeons.record_for("suedkap_gezeitenkammern").get("best_sec", 0.0)) > 0.0, "Bestzeit recorded")

	## 8. Leave via DungeonExitSeal -> returns cleanly to saved overworld spot & unmounts scene
	var seal: DungeonExitSeal = scene.get_node_or_null("DungeonExitSeal") as DungeonExitSeal
	_check(seal != null, "DungeonExitSeal spawned in boss arena")
	if seal != null:
		seal.interact(player)
	for _i: int in 4:
		await get_tree().process_frame
	_check(not dm.is_player_in_dungeon(1), "player left dungeon cleanly")
	_check(player.global_position.distance_to(overworld_origin) < 2.0, "player restored to exact overworld return spot")

	player.queue_free()
	dm.queue_free()
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("SUEDKAP DUNGEON OK (%d checks)" % _checks)
	else:
		push_error("SUEDKAP DUNGEON FAILED (%d/%d failed)" % [_failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)
