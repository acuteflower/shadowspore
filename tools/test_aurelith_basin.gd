extends Node
## Automated verification suite for Paket 2 (`AurelithArena` & `Aurelith` in the Singing Basin at `Tile 626, 69`):
## 1) Free Day-1 basin setup at `Tile (626, 69)`, clear cell reservation (zero stray wild golem homes),
##    6 radial `"quartz"` star-veins (`Terrain.surface_at`), and real daytime monument shade (`DesertHeat.is_in_shade`).
## 2) 6 basin `QuartzGolem` sentinels across all 3 variants (`0, 1, 2`) with `pickaxe_multiplier() == 1.0`.
## 3) Soul-drain progression (`1..5` kills): `soul_charge` rises, remaining sentinels awaken & boost speed/resonance.
## 4) 6th kill -> `0.85 s` `Stage.SILENCE` -> `Aurelith` (`2500 HP`) self-assembly -> double-fist slam seals
##    the 36-tooth sintered-quartz perimeter wall (`sealed == true`, `blocks_climb == true`, `Mode.ACTIVE`).
## 5) Empty-basin leash reset (`8.0 s`): boss despawns, wall unseals, `soul_charge == 0`, monument returns to `DORMANT`.

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("AURELITH_BASIN_TEST: " + message)


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
		await get_tree().process_frame
		elapsed += get_physics_process_delta_time()


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
	hero.health.max_health = 5000.0
	hero.health.current = 5000.0
	var guide: Node = hero.get_node_or_null("OpeningGuide")
	if guide != null:
		guide.set_process(false)
	hero.quests.set_physics_process(false)

	# 1. Basin existence, coordinates, clear reservation & quartz star-veins
	var arena: AurelithArena = world.aurelith_arena
	_check(arena != null, "WorldLevel owns AurelithArena")
	if arena == null:
		get_tree().quit(1)
		return

	var spot: Vector2 = arena.basin_position()
	_check(spot.is_equal_approx(Vector2(626.0 * 16.0 + 8.0, 69.0 * 16.0 + 8.0)), "Basin stands at Tile (626, 69)")
	_check(arena.stage == AurelithArena.Stage.DORMANT and not arena.released and not arena.sealed, "Basin starts DORMANT, unlocked from Day 1, and unsealed")

	var stray_homes: int = 0
	for h: Dictionary in world.desert_guardians.all_homes():
		if (h["pos"] as Vector2).distance_to(spot) < 280.0:
			stray_homes += 1
	_check(stray_homes == 0, "Zero random DesertGuardians homes overlap Aurelith's Singing Basin (got %d)" % stray_homes)

	_check(Terrain.surface_at(spot + Vector2(36.0, 0.0)) == "quartz", "Central ancient seal ring registers as quartz surface")
	var pad_quartz_ok: int = 0
	for pad_pos: Vector2 in arena._vein_pads:
		if Terrain.surface_at(pad_pos) == "quartz":
			pad_quartz_ok += 1
	_check(pad_quartz_ok == 6, "All 6 radial star-vein druse pads register as quartz surface (got %d/6)" % pad_quartz_ok)

	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.50
	await _step_frames(2)
	_check(DesertHeat.is_in_shade(get_tree(), spot + Vector2(8.0, 4.0)), "Dormant monument casts real daytime desert shade (day_canopies)")

	# 2. Teleport Ellie into the basin -> 6 sentinels spawn across all 3 variants with 1.0x pickaxe parity
	hero.request_teleport(spot + Vector2(0.0, 152.0))
	await _wait_seconds(0.45)

	_check(arena.active_guardian_count() == 6, "6 basin QuartzGolem sentinels spawn when Ellie enters the basin (got %d)" % arena.active_guardian_count())
	var variants_seen: Dictionary = {}
	var pickaxe_ok: int = 0
	for g: Node2D in arena._guardians:
		if g is QuartzGolem:
			var qg: QuartzGolem = g as QuartzGolem
			variants_seen[qg.variant] = true
			if is_equal_approx(qg.pickaxe_multiplier(), 1.0):
				pickaxe_ok += 1
	_check(variants_seen.has(0) and variants_seen.has(1) and variants_seen.has(2), "All 3 QuartzGolem mineral variants (0, 1, 2) guard the basin")
	_check(pickaxe_ok == 6, "All 6 basin sentinels enforce pure 1.0x weapon/spell parity (no extra pickaxe bonus)")

	# 3. Slay guardians 1..5 -> verify soul_charge & sentinel escalation
	for idx: int in 5:
		var g_node: Node2D = arena._guardians[idx]
		_check(g_node != null and is_instance_valid(g_node), "Sentinel %d is valid before kill" % idx)
		if g_node != null and is_instance_valid(g_node):
			var hb: HurtboxComponent = g_node.get_node("Hurtbox") as HurtboxComponent
			hb.take_hit(999.0, hero.global_position, 40.0, hero.name.to_int())
		await _step_frames(2)

	_check(arena.killed_count == 5, "Killed count reaches 5/6 after 5 sentinels fall (got %d)" % arena.killed_count)
	_check(is_equal_approx(arena.soul_charge_ratio(), 5.0 / 6.0), "Soul charge ratio is 5/6")
	_check(arena.stage == AurelithArena.Stage.DORMANT and not arena.boss_present(), "Aurelith stays DORMANT until the 6th sentinel falls")

	var last_g: QuartzGolem = arena._guardians[5] as QuartzGolem
	_check(last_g != null and last_g.is_provoked() and last_g.basin_aggro_speed > 1.05, "Remaining 6th sentinel escalated in aggression & speed")

	# 4. Slay the 6th sentinel -> 0.85s SILENCE -> Aurelith spawns -> double-fist slam seals the perimeter!
	if last_g != null:
		var hb6: HurtboxComponent = last_g.get_node("Hurtbox") as HurtboxComponent
		hb6.take_hit(999.0, hero.global_position, 40.0, hero.name.to_int())
	await _step_frames(2)

	_check(arena.stage == AurelithArena.Stage.SILENCE, "6th sentinel death triggers Stage.SILENCE (0.85 s dead silence)")
	_check(not arena.boss_present(), "Aurelith has not yet erupted during the first frames of dead silence")

	# Advance past 0.85 s silence so Aurelith erupts
	await _wait_seconds(1.05)
	_check(arena.stage == AurelithArena.Stage.BOSS and arena.boss_present(), "After 0.85 s silence, Aurelith erupts and enters Stage.BOSS")
	var boss: Aurelith = arena.boss
	_check(boss != null and is_equal_approx(boss.max_health(), 2500.0), "Aurelith spawns with 2500 solo pinnacle HP")
	_check(boss != null and is_equal_approx(boss.pickaxe_multiplier(), 1.0), "Aurelith has pickaxe_multiplier == 1.0 (zero pickaxe bonus)")

	var boss_hb: HurtboxComponent = boss.get_node("Hurtbox") as HurtboxComponent
	boss_hb.take_hit(100.0, hero.global_position, 30.0, hero.name.to_int())
	_check(is_equal_approx(boss.health_now(), 2500.0), "Aurelith is invulnerable while self-assembling in Mode.ENTRANCE")

	# Advance past the full self-assembly & double-fist ground slam (`2.90 s` entrance)
	await _wait_seconds(3.05)
	_check(arena.sealed, "Aurelith's double-fist slam seals the sintered-quartz & sandstorm perimeter")
	_check(arena.blocks_climb(spot + Vector2(250.0, 0.0), spot + Vector2(310.0, 0.0)), "Sealed basin blocks cliff climbs in/out (WallClimb)")
	_check(arena._wall_bodies.size() == 44 and arena._wall_bodies[0].collision_layer == 1, "All 44 perimeter StaticBody2D segments are solid on layer 1")
	_check(boss.mode == Aurelith.Mode.ACTIVE, "Aurelith transitions cleanly into Mode.ACTIVE after self-assembly")

	boss_hb.take_hit(100.0, hero.global_position, 30.0, hero.name.to_int())
	await _step_frames(2)
	_check(is_equal_approx(boss.health_now(), 2400.0), "Weapon/spell strike deals exact 100 damage to active Aurelith (got %.1f)" % boss.health_now())

	# 5. Teleport Ellie outside leash (`640 px`) and wait `reset_seconds` (`8.0 s`) -> clean reset!
	hero.request_teleport(spot + Vector2(920.0, 0.0))
	await _wait_seconds(8.6)

	_check(not arena.boss_present(), "Aurelith despawns cleanly after players leave leash for 8 s")
	_check(not arena.sealed and not arena.blocks_climb(spot + Vector2(250.0, 0.0), spot + Vector2(310.0, 0.0)), "Sintered-quartz storm wall unseals and re-opens climbs on reset")
	_check(arena.stage == AurelithArena.Stage.DORMANT and arena.killed_count == 0, "Basin resets cleanly to Stage.DORMANT with soul_charge 0/6")

	print("AURELITH BASIN TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
