extends Node
## Automated verification suite for `QuartzGolem` ("Quarzwächter") & `DesertGuardians`:
## 1) Planned exclusively on white ground-quartz outcrops (`BiomeBlend.is_quartz_surface`) across Sonnenquarz-Öde + 3 mineral variants.
## 2) Spawns day (0.50) and night (0.00) without burning in sunlight; stays peaceful when Ellie merely walks nearby.
## 3) Awakens immediately (+ sympathetic ally wake) when Ellie mines quartz or harvests/picks desert flora nearby.
## 4) Executes all 3 magical attacks (`SHARD_VOLLEY` 3 spikes, `SANDSTONE_SHOCK` under Ellie, `CRYSTAL_BLADE` close-range arm sword).
## 5) Pickaxe fracture bonus (`1.35x`) and guaranteed `sun_quartz` drop on death.

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("QUARTZ_GOLEM_TEST: " + message)


func _ready() -> void:
	_run.call_deferred()


func _step_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _run() -> void:
	NetworkManager.host_singleplayer()
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	await _step_frames(3)

	var hero: Player = world._players.get_child(0) as Player
	hero.intro = null
	hero.story_lock = false
	hero.wounded = false
	hero.health.floor_value = 0.0
	hero.health.max_health = 500.0
	hero.health.current = 500.0
	var guide: Node = hero.get_node_or_null("OpeningGuide")
	if guide != null:
		guide.set_process(false)
	hero.quests.set_physics_process(false)

	# 1. Verify DesertGuardians placement strictly on white ground quartz
	var guardians: DesertGuardians = world.desert_guardians
	_check(guardians != null, "WorldLevel owns DesertGuardians")
	var homes: Array[Dictionary] = guardians.all_homes()
	_check(homes.size() >= 15, "DesertGuardians planned >= 15 guardian homes across Sonnenquarz-Öde (got %d)" % homes.size())
	var off_quartz: int = 0
	var seen_variants: Dictionary = {}
	for h: Dictionary in homes:
		var pos: Vector2 = h["pos"] as Vector2
		if not BiomeBlend.is_quartz_surface(pos):
			off_quartz += 1
		seen_variants[int(h["variant"])] = true
	_check(off_quartz == 0, "100%% of planned QuartzGolem homes sit strictly on white ground quartz (off_quartz=%d)" % off_quartz)
	_check(seen_variants.has(0) and seen_variants.has(1), "Both Sun-Quartz/Ochre (0) and Mesa-Terracotta (1) variants are seeded")

	# Pick a flat white ground-quartz home spot and stream its chunk
	var home_spec: Dictionary = homes[0]
	var home_pos: Vector2 = home_spec["pos"] as Vector2
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.50 ## Blazing midday!
	hero.request_teleport(home_pos + Vector2(-34.0, 0.0))
	await _step_frames(65)

	# Force immediate guardian maintenance check at midday
	guardians._maintain_guardians()
	await _step_frames(5)
	var golem: QuartzGolem = null
	for n: Node in get_tree().get_nodes_in_group("quartz_golems"):
		if n is QuartzGolem:
			golem = n as QuartzGolem
			break
	_check(golem != null, "QuartzGolem spawns naturally on ground quartz at blazing midday (0.50)")
	if golem == null:
		get_tree().quit(1)
		return

	# 2. Verify no sun burn at midday + peaceful while Ellie stands/walks right beside it
	await _step_frames(25)
	var golem_hp: HealthComponent = golem.get_node("HealthComponent") as HealthComponent
	_check(is_equal_approx(golem_hp.current, golem_hp.max_health), "QuartzGolem takes zero sun burn damage at midday")
	_check(not golem.is_provoked() and not golem.is_in_group("predators"), "QuartzGolem stays peaceful and out of 'predators' when Ellie merely stands/walks nearby")

	# Also verify midnight (0.00) keeps it healthy and active
	TimeManager.time_of_day = 0.0
	await _step_frames(10)
	_check(is_instance_valid(golem) and is_equal_approx(golem_hp.current, golem_hp.max_health), "QuartzGolem remains active and healthy at midnight (0.00)")
	TimeManager.time_of_day = 0.50

	# 3. Spawn a dormant sibling nearby & trigger disturbance (simulating mining quartz / picking desert plant)
	var sibling: QuartzGolem = world.spawn_quartz_golem(home_pos + Vector2(28.0, 8.0), PI, 2, true) as QuartzGolem
	await _step_frames(3)
	_check(sibling.state == QuartzGolem.State.DORMANT and not sibling.is_provoked(), "Dormant sibling starts camouflaged as a collapsed quartz-sandstone pile")

	DesertGuardians.notify_disturbance(get_tree(), home_pos + Vector2(-18.0, 0.0), hero, false)
	await _step_frames(2)
	_check(golem.is_provoked() and golem.is_in_group("predators"), "Disturbance (mining/harvesting nearby) immediately provokes QuartzGolem and adds it to 'predators'")
	_check(sibling.is_provoked(), "Awakening sympathetically alerts sibling QuartzGolem on the same quartz patch")
	sibling.queue_free()
	await _step_frames(45) ## finish AWAKEN (0.62s) -> COMBAT

	# 4a. Verify Attack 3: Fast close-range Crystal Arm-Blade (`BLADE_WINDUP` -> `BLADE_SLASH`)
	hero.global_position = golem.global_position + Vector2(30.0, 0.0)
	hero.velocity = Vector2.ZERO
	golem._known = hero.global_position
	golem._blade_cd = 0.0
	golem._shard_cd = 9.0
	golem._shock_cd = 9.0
	var hp_before_blade: float = hero.health.current
	var saw_blade_slash: bool = false
	for _f: int in 75:
		await get_tree().physics_frame
		await get_tree().process_frame
		if golem.state == QuartzGolem.State.BLADE_SLASH:
			saw_blade_slash = true
	_check(saw_blade_slash and hero.health.current < hp_before_blade, "Close-range CRYSTAL_BLADE crystallizes quartz arm-sword and slashes Ellie (hp %.0f -> %.0f)" % [hp_before_blade, hero.health.current])

	# 4b. Verify Attack 1: 3-Spike Magical Sun-Quartz Volley (`SHARD_WINDUP` -> `SHARD_RELEASE`)
	hero.global_position = golem.global_position + Vector2(88.0, 0.0)
	hero.velocity = Vector2.ZERO
	golem._set_state(QuartzGolem.State.COMBAT)
	golem._known = hero.global_position
	golem.heading = 0.0
	golem._blade_cd = 9.0
	golem._shock_cd = 9.0
	golem._shard_cd = 0.0
	var hp_before_shards: float = hero.health.current
	var max_shards_seen: int = 0
	for _f2: int in 95:
		await get_tree().physics_frame
		await get_tree().process_frame
		var live_shards: int = 0
		for proj: Node in world.get_node("EnemyProjectiles").get_children():
			if proj is QuartzShard:
				live_shards += 1
		max_shards_seen = maxi(max_shards_seen, live_shards)
	_check(max_shards_seen >= 3 and hero.health.current < hp_before_shards, "SHARD_VOLLEY spawns 3 QuartzShard spikes and hits Ellie (shards=%d, hp %.0f -> %.0f)" % [max_shards_seen, hp_before_shards, hero.health.current])

	# 4c. Verify Attack 2: Subterranean Sandstone Shock (`SHOCK_WINDUP` -> `SHOCK_SLAM`)
	hero.global_position = golem.global_position + Vector2(78.0, 0.0)
	hero.velocity = Vector2.ZERO
	golem._set_state(QuartzGolem.State.COMBAT)
	golem._known = hero.global_position
	golem.heading = 0.0
	golem._blade_cd = 9.0
	golem._shard_cd = 9.0
	golem._shock_cd = 0.0
	var hp_before_shock: float = hero.health.current
	var saw_eruption: bool = false
	for _f3: int in 95:
		await get_tree().physics_frame
		await get_tree().process_frame
		if golem._erupt_age >= 0.0:
			saw_eruption = true
	_check(saw_eruption and hero.health.current < hp_before_shock, "SANDSTONE_SHOCK erupts under Ellie's feet and deals shock damage (hp %.0f -> %.0f)" % [hp_before_shock, hero.health.current])

	# 5. Verify Pickaxe Fracture Bonus (1.35x) & Sun-Quartz Loot Drop on Death
	var golem_hurt: QuartzGolemHurtbox = golem.get_node("Hurtbox") as QuartzGolemHurtbox
	hero.inventory.slots[0] = {}
	hero.inventory.selected = 0
	var g_hp0: float = golem_hp.current
	golem_hurt.take_hit(10.0, hero.global_position, 10.0, hero.name.to_int())
	var sword_dealt: float = g_hp0 - golem_hp.current

	hero.inventory.slots[0] = {"id": "pickaxe_basic", "count": 1}
	hero.inventory.selected = 0
	var g_hp1: float = golem_hp.current
	golem_hurt.take_hit(10.0, hero.global_position, 10.0, hero.name.to_int())
	var pick_dealt: float = g_hp1 - golem_hp.current
	_check(is_equal_approx(sword_dealt, 10.0) and is_equal_approx(pick_dealt, 14.0), "Pickaxe deals +35%% fracture damage (sword=%.0f, pickaxe=%.0f)" % [sword_dealt, pick_dealt])

	# Finish off the golem and check guaranteed `sun_quartz` drop
	hero.global_position = home_pos + Vector2(-90.0, 0.0) ## step back so auto-pickup doesn't swallow the drop before we inspect it
	golem_hurt.take_hit(200.0, hero.global_position, 20.0, hero.name.to_int())
	await _step_frames(8)
	var dropped_sun_quartz: bool = false
	for drop_node: Node in world.get_node("Drops").get_children():
		if String(drop_node.get("item_id")) == "sun_quartz":
			dropped_sun_quartz = true
			break
	if hero.inventory.count_item("sun_quartz") > 0:
		dropped_sun_quartz = true
	_check(dropped_sun_quartz, "Defeated QuartzGolem drops sun_quartz")

	print("QUARTZ GOLEM TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
