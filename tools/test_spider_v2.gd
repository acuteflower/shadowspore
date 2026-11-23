extends Node
## Automated end-to-end verification suite for Shadow Spider 2.0 & V2 Combat Components (`T1`..`T7`, `V1`..`V7`):
## Godot --headless --path . res://tools/test_spider_v2.tscn

const SPIDER_SCENE: PackedScene = preload("res://src/entities/enemies/shadow_spider.tscn")
const PLAYER_SCENE: PackedScene = preload("res://src/entities/player/player.tscn")

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _run() -> void:
	var root: Node2D = Node2D.new()
	root.name = "SpiderV2TestWorld"
	add_child(root)

	var surfaces: GroundSurfaces = GroundSurfaces.new()
	root.add_child(surfaces)
	surfaces.setup(Rect2(-256.0, -256.0, 512.0, 512.0), 2.0)
	surfaces.paint_moss_patch(Vector2(-120.0, 0.0), Vector2(44.0, 44.0), 0.95, 11)
	surfaces.paint_cobble_lane([Vector2(60.0, -60.0), Vector2(180.0, -60.0)], 22.0, 22, false, false)
	surfaces.add_ancient_courtyard(Vector2(120.0, 80.0))
	surfaces.commit()

	var water: WaterField = WaterField.new()
	root.add_child(water)
	water.setup_rect(Rect2(-256.0, -256.0, 512.0, 512.0), 2.0)
	water.add_puddle(Vector2(0.0, 120.0), Vector2(28.0, 20.0), {"depth": 0.24})
	water.add_ocean(Rect2(-256.0, -256.0, 64.0, 120.0), -192.0, {"min_depth": 0.78})
	water.build_maps()
	water.commit()

	var grass: LivingGrass = LivingGrass.new()
	root.add_child(grass)
	grass.set_water_habitat_provider(water)
	grass.setup_rect(Rect2(-180.0, -180.0, 360.0, 360.0), 2026, true, surfaces)

	var enemies: Node2D = Node2D.new()
	enemies.name = "Enemies"
	root.add_child(enemies)

	var p_inst: Player = PLAYER_SCENE.instantiate() as Player
	p_inst.name = "1"
	root.add_child(p_inst)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Player = get_tree().get_first_node_in_group("players") as Player
	player.set_physics_process(false)
	player.health.max_health = 500.0
	player.health.current = 500.0
	player.health.invulnerable_seconds = 0.0

	# ---------------- 1. T1 / V1 / V2: 8-Leg Rig, 6-Row 3D Sheet, 3 Brood Variants & Terrain Traction ----------------
	var spider: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	enemies.add_child(spider)
	spider.set_physics_process(false)
	spider.set_process(false)
	await get_tree().physics_frame

	_check(spider._rig._legs.size() == 8, "SpiderRig 2.0 must have 8 true arachnid legs")
	var body_sp: Sprite2D = spider._rig.get_node("Body") as Sprite2D
	_check(body_sp.hframes == 8 and body_sp.vframes == 6, "Body sprite must configure 8x6 V2 grid")
	_check(body_sp.texture.get_width() == 320 and body_sp.texture.get_height() == 216, "3D raymarched body sheet must be 320x216")
	_check(spider._rig.get_node_or_null("GroundShadow") != null, "GroundShadow 8-point AO & SunShadows layer missing")

	spider._rig.apply_brood_variant(1)
	_check(is_equal_approx(spider._rig._body_scale_mult, 0.88) and spider._rig._leg_scale_mult > 1.0, "Scout brood phenotype scale mismatch")
	spider._rig.apply_brood_variant(2)
	_check(is_equal_approx(spider._rig._body_scale_mult, 1.14) and spider._rig._permanent_thorns, "Thorn Elder brood phenotype mismatch")
	spider._rig.apply_brood_variant(0)

	spider._rig.health_ratio = 0.35
	_check(spider._rig._select_body_row() == 5, "< 50% HP must switch body to battle-cracked carapace row 5")
	spider._rig.health_ratio = 1.0

	_check(spider._bridge.surface_speed_mult(Vector2(120.0, 80.0)) > 1.05, "Ancient stone must boost claw traction")
	_check(spider._bridge.is_deep_water(Vector2(-230.0, -210.0)), "Deep ocean water must be flagged unwalkable")
	_check(not spider._navigation_floor(Vector2(-230.0, -210.0)), "Navigation must reject deep water")

	# ---------------- 2. T2 / V4: 3-Channel Senses (Moss Stealth vs Gravel Biotremor & Spore-Kinship Hesitate) ----------------
	spider.global_position = Vector2(-80.0, 0.0)
	spider.heading = 0.0 ## Facing East (+X), so West (-120, 0) is behind its back!
	spider._senses.reset_calm()

	# Player sneaking on plush woodland moss behind spider (-120, 0): muffled (`0.52x` acoustics) -> undetected!
	player.global_position = Vector2(-120.0, 0.0)
	player.stealth.sneaking = true
	player.sprinting = false
	player.velocity = Vector2(22.0, 0.0)
	var moss_scan: Dictionary = spider._senses.scan(spider.heading, spider._clear_path, spider._sees_over_cliff, 1.0)
	_check(moss_scan["player"] == null, "Sneaking on moss behind spider should remain muffled & undetected")

	# Player sprinting on cobble/gravel behind spider: amplifies substrate biotremor -> TREMOR detected!
	spider.global_position = Vector2(180.0, -60.0)
	spider.heading = 0.0 ## Facing East, cobble lane at (90, -60) is 90 px behind!
	player.global_position = Vector2(90.0, -60.0)
	player.stealth.sneaking = false
	player.sprinting = true
	player.velocity = Vector2(125.0, 0.0)
	var gravel_scan: Dictionary = spider._senses.scan(spider.heading, spider._clear_path, spider._sees_over_cliff, 1.0)
	_check(gravel_scan["player"] == player and int(gravel_scan["trigger"]) == EnemySenseComponent.TriggerKind.TREMOR, "Sprinting on gravel/cobble must trigger substrate biotremor")

	# Calm approach in frontal outer ring -> triggers "Ellie = Shadowspore" HESITATE -> NOTICE!
	player.sprinting = false
	player.velocity = Vector2.ZERO
	spider.global_position = Vector2.ZERO
	spider.heading = 0.0
	spider._senses.reset_calm()
	player.global_position = Vector2(128.0, 0.0)
	spider._set_state(ShadowSpider.State.IDLE)
	spider._search_timer = 0.0
	spider._idle(0.016)
	_check(spider.state == ShadowSpider.State.HESITATE, "First calm outer encounter must trigger Spore-Kinship HESITATE")
	_check(spider._rig._pose == SpiderRig.Pose.HESITATE, "SpiderRig must enter curious head-tilt HESITATE pose")
	spider._physics_process(0.50) ## Let hesitate finish -> transitions to NOTICE!

	# ---------------- 3. T3 / V7: LivingGrass Scythe-Slash Wave & WaterField 30 Hz Claw Ripple ----------------
	var grass_spot: Vector2 = Vector2(0.0, -40.0)
	grass.recenter_field(grass_spot)
	spider._bridge.on_scythe_slash(grass_spot, Vector2.RIGHT, 40.0)
	_check(grass.crush_at(grass_spot + Vector2(20.0, 0.0)) >= 0.16, "Scythe slash must flatten LivingGrass blades along arc")

	water.recenter_wave_field(Vector2(0.0, 120.0))
	spider._bridge.on_claw_landed(Vector2(0.0, 120.0), true)
	_check(water._wave_active, "Claw landing in WaterField puddle must excite 30 Hz wave ringbuffer")

	# ---------------- 4. T5: Webbed Snare + Break via ShadowStep, Silk Backstep, Venom Lunge + Wundtau Cleanse ----------------
	spider.global_position = Vector2.ZERO
	spider.attack_origin = Vector2.ZERO
	spider.attack_dir = Vector2.RIGHT
	spider.anchor = Vector2(72.0, 0.0)
	player.global_position = Vector2(72.0, 0.0)
	player.air_height = 0.0
	await get_tree().physics_frame
	var g_landed: bool = spider._grapple_hit()
	_check(g_landed and player.effects.has("webbed"), "Silk Grapple hit must apply SPORENSEIDE (webbed)")
	_check(player._slow_factor() < 0.82, "SPORENSEIDE must slow player locomotion")
	# Trigger ShadowStep -> snaps silk immediately on host StatusEffects tick!
	player.play_shadow_step(player.global_position, player.global_position + Vector2(24.0, 0.0), Vector2.RIGHT)
	player.effects._physics_process(0.016)
	_check(not player.effects.has("webbed"), "ShadowStep must snap SPORENSEIDE immediately")
	player._step_t = -1.0

	# Movement 2.0 3D Height Fairness: Vault / Ledge Hop (`air_height > 6.0`) dodges low ground scythe!
	player.global_position = Vector2(26.0, 0.0)
	player.air_height = 8.5
	await get_tree().physics_frame
	var hp_air_before: float = player.health.current
	spider.attack_origin = Vector2.ZERO
	spider.attack_dir = Vector2.RIGHT
	spider._set_state(ShadowSpider.State.STRIKE)
	spider._state_time = 0.15
	spider._strike()
	_check(is_equal_approx(player.health.current, hp_air_before), "Airborne Vault/Hop player must clear low ground scythe sweep")
	player.air_height = 0.0

	# Venom Lunge: hits ground player -> applies shadow_venom -> Wundtau I cleanses shadow_venom!
	player.global_position = Vector2(24.0, 0.0)
	await get_tree().physics_frame
	spider.global_position = Vector2.ZERO
	spider._target = player
	spider._set_state(ShadowSpider.State.VENOM_WINDUP)
	spider._set_state(ShadowSpider.State.VENOM_LUNGE)
	spider._venom_lunge_step(0.05)
	_check(player.effects.has("shadow_venom"), "Venom Lunge hit must apply SCHATTENGIFT")
	_check(AlchemyRules.cleanses("heal", 1).has("shadow_venom"), "Wundtau I must cleanse SCHATTENGIFT")
	player.inventory._drink(player, {"type": "heal", "tier": 1})
	_check(not player.effects.has("shadow_venom"), "Drinking Wundtau I must remove SCHATTENGIFT")

	# Whiffed Venom Lunge -> skids into EXPOSED weakpoint window!
	player.global_position = Vector2(0.0, 120.0)
	await get_tree().physics_frame
	spider.global_position = Vector2.ZERO
	spider.attack_dir = Vector2.RIGHT
	spider._set_state(ShadowSpider.State.VENOM_LUNGE)
	spider._state_time = 0.25
	spider._venom_lunge_step(0.05)
	_check(spider.state == ShadowSpider.State.EXPOSED, "Dodged Venom Lunge must leave spider EXPOSED")

	# Directional Opisthosoma Rear Weakpoint (`1.25x`) & EXPOSED (`1.35x`) & Silk Backstep:
	var dmg_exposed: float = spider.evaluate_hurtbox_hit(20.0, Vector2(-20.0, 0.0), 40.0)
	_check(is_equal_approx(dmg_exposed, 27.0), "EXPOSED state must amplify damage by 1.35x (got %.1f)" % dmg_exposed)

	spider._set_state(ShadowSpider.State.CHASE)
	spider.heading = 0.0 ## Facing East (+X): attacker at (-24, 0) strikes rear Opisthosoma!
	var dmg_rear: float = spider.evaluate_hurtbox_hit(20.0, Vector2(-24.0, 0.0), 30.0)
	_check(is_equal_approx(dmg_rear, 25.0), "Rear Opisthosoma strike must deal 1.25x weakpoint damage (got %.1f)" % dmg_rear)

	# 2 rapid close frontal hits trigger evasive SILK_BACKSTEP!
	spider._health.max_health = 200.0
	spider._health.current = 200.0
	spider._posture.max_posture = 500.0
	spider._posture.posture = 500.0
	spider._backstep_cd = 0.0
	spider._recent_front_hits = 0
	spider.global_position = Vector2.ZERO
	spider.heading = 0.0
	spider._hurtbox.take_hit(6.0, Vector2(24.0, 0.0), 20.0)
	spider._set_state(ShadowSpider.State.CHASE)
	spider._hurtbox.take_hit(6.0, Vector2(24.0, 0.0), 20.0)
	_check(spider.state == ShadowSpider.State.SILK_BACKSTEP, "Two close frontal hits must trigger evasive SILK_BACKSTEP")

	# ---------------- 5. T4: Canopy Drop & Mycelium Tether ----------------
	var canopy_sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	canopy_sp.ambush_mode = ShadowSpider.AmbushKind.CANOPY_DROP
	canopy_sp.position = Vector2(90.0, 90.0)
	enemies.add_child(canopy_sp)
	canopy_sp.set_physics_process(false)
	await get_tree().physics_frame
	_check(canopy_sp.state == ShadowSpider.State.CANOPY_WAIT and canopy_sp._body_shape.disabled, "Canopy spider must hang concealed above ground")
	player.global_position = Vector2(106.0, 90.0)
	canopy_sp._search_timer = 0.0
	canopy_sp._canopy_wait_tick(0.016)
	_check(canopy_sp.state == ShadowSpider.State.CANOPY_DROP, "Approaching beneath Canopy spider must trigger CANOPY_DROP")

	var tether_sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	tether_sp.ambush_mode = ShadowSpider.AmbushKind.MYCELIUM_TETHER
	tether_sp.position = Vector2(-140.0, 110.0)
	tether_sp.heading = 0.0
	enemies.add_child(tether_sp)
	tether_sp.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(tether_sp._tether != null and is_instance_valid(tether_sp._tether), "MyceliumTether ambush must spawn trip-thread")
	player.stealth.sneaking = false
	player.velocity = Vector2(60.0, 0.0)
	player.global_position = tether_sp._tether.global_position
	tether_sp._tether._check_actors()
	_check(tether_sp.state == ShadowSpider.State.CHASE and player.effects.has("webbed"), "Walking into MyceliumTether must snare player & alert spider")

	# ---------------- 6. T6: CombatCoordinator Pack Flanking, Attack Tokens & PACK_RECOIL ----------------
	var p1_sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	var p2_sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	var p3_sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	p1_sp.position = Vector2(0.0, 0.0)
	p2_sp.position = Vector2(20.0, 12.0)
	p3_sp.position = Vector2(20.0, -12.0)
	enemies.add_child(p1_sp)
	enemies.add_child(p2_sp)
	enemies.add_child(p3_sp)
	p1_sp.set_physics_process(false)
	p2_sp.set_physics_process(false)
	p3_sp.set_physics_process(false)
	await get_tree().physics_frame

	var a1: float = CombatCoordinator.claim_flank_angle(p1_sp, player)
	var a2: float = CombatCoordinator.claim_flank_angle(p2_sp, player)
	var a3: float = CombatCoordinator.claim_flank_angle(p3_sp, player)
	_check(is_zero_approx(a1) and a2 > 1.0 and a3 < -1.0, "Pack spiders must claim distinct binder + right/left flank sectors")
	var tok1: bool = CombatCoordinator.request_melee_token(p1_sp, player, 0.9)
	var tok2: bool = CombatCoordinator.request_melee_token(p2_sp, player, 0.9)
	_check(tok1 and not tok2, "CombatCoordinator must prevent simultaneous overlapping pack melee strikes")
	CombatCoordinator.release_melee_token(p1_sp, player)

	p2_sp._set_state(ShadowSpider.State.CHASE)
	p1_sp.cut_down(player.global_position)
	_check(p2_sp.state == ShadowSpider.State.PACK_RECOIL, "Slaying a packmate nearby must trigger PACK_RECOIL on adjacent spider")

	print("SPIDER V2 OK: %d/%d checks passed" % [_checks - _failures, _checks])
	root.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
