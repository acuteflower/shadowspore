extends Node2D
## Automated headless verification suite for Square 5 (`RockyGround` + `LivingRock` 1.0):
## Run: /Users/nxye/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tools/test_living_rock.tscn

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _chk(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
	else:
		print("[PASS] ", msg)


func _step_frames(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _run() -> void:
	NetworkManager.host_singleplayer()
	await _step_frames(2)

	var drops_node: Node2D = Node2D.new()
	drops_node.name = "Drops"
	drops_node.add_to_group("drops")
	add_child(drops_node)

	var builder: RockSquareBuilder = RockSquareBuilder.new()
	var rg: RockyGround = builder.setup_ground(self)

	var grass: LivingGrass = LivingGrass.new()
	grass.add_habitat_provider(rg)
	grass.setup_rect(RockSquareBuilder.SQ5_RECT, 2026, true)
	add_child(grass)

	var fake_trees: Array[Vector2] = [Vector2(1312.0, 42.0), Vector2(1234.0, 50.0)]
	builder.spawn_outcrops(self, fake_trees)
	await _step_frames(3)

	# 1. DataRegistry tables & rig validation
	var rock_spec: Dictionary = DataRegistry.get_entry("rocks", "valley_stone")
	var rig_table: Dictionary = DataRegistry.table("valley_stone_rig")
	_chk(not rock_spec.is_empty(), "data/rocks.json loaded valley_stone spec")
	_chk(rig_table.size() >= 12, "data/valley_stone_rig.json contains all 12 geological archetypes (got %d)" % rig_table.size())

	# 2. RockyGround multi-stratum underfoot surfaces (`stone`, `gravel`, `slope`, `moss`)
	_chk(Terrain.patches.has(rg), "RockyGround registered in Terrain.patches")
	var seen_surfs: Dictionary = {}
	var y: float = -132.0
	while y <= 132.0:
		var x: float = 1350.0
		while x <= 1720.0:
			var s: String = Terrain.surface_at(Vector2(x, y))
			seen_surfs[s] = true
			x += 6.0
		y += 6.0
	_chk(seen_surfs.has("stone"), "RockyGround exposes stratified bedrock ('stone' surface)")
	_chk(seen_surfs.has("gravel"), "RockyGround exposes angular scree/talus ('gravel' surface)")
	_chk(seen_surfs.has("slope"), "RockyGround exposes stony mineral loam ('slope' surface)")
	_chk(seen_surfs.has("moss"), "RockyGround exposes highland crevice moss ('moss' surface)")
	_chk(rg.detail_count >= 30, "RockyGround placed >=30 rock ground detail sprites (got %d)" % rg.detail_count)

	# 3. LivingGrass coupling: clear over exposed bedrock & boulder faces, populated in seam/transition zones
	var bedrock_hab: Dictionary = rg.grass_habitat_at(Vector2(1564.0, -58.0))
	var boulder_south_hab: Dictionary = rg.grass_habitat_at(builder.hero_quarry_s2.position + Vector2(0.0, 6.0))
	_chk(float(bedrock_hab.get("density", 1.0)) == 0.0, "LivingGrass clears exposed bedrock core")
	_chk(float(boulder_south_hab.get("density", 1.0)) == 0.0, "LivingGrass clears +south 3/4 face of LivingRock boulders")
	_chk(grass.tuft_count > 100, "LivingGrass populates hardy seam & transition tufts across Square 5 (count=%d)" % grass.tuft_count)

	# 4. Outcrop diversity, sizes s0..s4, Jobs ecology & Befall traits
	var seen_stages: Dictionary = {}
	var seen_archs: Dictionary = {}
	var moss_count: int = 0
	var lichen_count: int = 0
	for rk: LivingRock in builder.rocks:
		seen_stages[rk.size_stage] = true
		seen_archs[rk.active_rig_key] = true
		if int(rk.rolled_traits.get("moss", -1)) >= 0:
			moss_count += 1
		if int(rk.rolled_traits.get("lichen", -1)) >= 0:
			lichen_count += 1
	_chk(seen_stages.size() == 5, "All 5 size stages (s0..s4) instantiated on Square 5")
	_chk(seen_archs.size() >= 8, "Multiple distinct geological archetypes active (got %d)" % seen_archs.size())
	_chk(moss_count >= 4 and lichen_count >= 4, "Variable Befall active across outcrops (moss=%d, lichen=%d)" % [moss_count, lichen_count])
	_chk(builder.hero_monolith_s3.shade_exposure > builder.hero_tor_s4.shade_exposure, "Jobs outcrop ecology computes higher shade exposure near western trees")

	# 5. Non-pickaxe clang vs progressive pickaxe fracture -> slab cleave -> walkable rubble -> stone drops -> regrowth!
	var q_rock: LivingRock = builder.hero_quarry_s2
	var start_hp: int = q_rock.hits_remaining()
	_chk(start_hp == 4 and q_rock.damage_tier() == 0, "Stage 2 quarry block starts intact with 4 hits")

	# Simulate non-pickaxe strike (source=0 with no pickaxe equipped -> clang, HP unchanged!)
	q_rock.harvest_hit(0)
	await _step_frames(2)
	_chk(q_rock.clang_count == 1 and q_rock.hits_remaining() == start_hp, "Non-pickaxe strike clangs with sparks without reducing rock HP")

	# Strike 1 -> damage_tier 1 (cracked_1)
	q_rock.strike_with_pickaxe(q_rock.global_position + Vector2(-18.0, 0.0))
	await _step_frames(2)
	_chk(q_rock.hits_remaining() == 3 and q_rock.damage_tier() == 1, "Pickaxe hit 1 opens cleavage cracks (tier 1)")

	# Strike 2 -> damage_tier 2 (chipped slab-cleave + cracked_2!)
	q_rock.strike_with_pickaxe(q_rock.global_position + Vector2(-18.0, 0.0))
	await _step_frames(2)
	_chk(q_rock.hits_remaining() == 2 and q_rock.damage_tier() == 2, "Pickaxe hit 2 cleaves outer stone slab (tier 2 chipped)")

	# Strikes 3 & 4 -> shatter into walkable rubble scar + spawn `stone` ItemDrops!
	var drops_before: int = drops_node.get_child_count()
	q_rock.strike_with_pickaxe(q_rock.global_position + Vector2(-18.0, 0.0))
	q_rock.strike_with_pickaxe(q_rock.global_position + Vector2(-18.0, 0.0))
	await _step_frames(3)
	var body_shape: CollisionShape2D = q_rock.get_node("Body/Shape") as CollisionShape2D
	_chk(q_rock.is_depleted() and q_rock.damage_tier() == 3, "Final pickaxe blow depletes rock into tier 3 rubble")
	_chk(body_shape.disabled, "Depleted rubble disables StaticBody2D collision so player can walk over it")
	_chk(drops_node.get_child_count() >= drops_before + 4, "Mining Stage 2 rock drops >=4 stone items (dropped %d)" % (drops_node.get_child_count() - drops_before))

	# Weathering regrowth restores intact rock
	q_rock.advance_weathering_days(5)
	await _step_frames(2)
	_chk(not q_rock.is_depleted() and q_rock.hits_remaining() == 4 and not body_shape.disabled, "Weathering regrowth restores intact rock & collision")

	# 6. Loose Stage 0 fieldstone prompt, GameCursor spec() & 1-hit shatter
	var s0: LivingRock = builder.hero_loose_s0
	var s0_spec: Dictionary = s0.spec()
	var q_spec: Dictionary = q_rock.spec()
	_chk(
		s0_spec.has("pickup") and String((q_spec.get("harvest", {}) as Dictionary).get("tool", "")) == "pickaxe",
		"LivingRock.spec() exposes pickaxe harvest & s0 pickup for GameCursor"
	)
	_chk(s0.prompt() == "FELDSTEIN AUFHEBEN", "Stage 0 loose fieldstone exposes hand-pickup prompt")
	s0.strike_with_pickaxe(s0.global_position + Vector2(-10.0, 0.0))
	await _step_frames(2)
	_chk(s0.is_depleted() and s0.prompt() == "" and not s0.spec().has("pickup"), "Stage 0 fieldstone breaks cleanly in 1 hit")

	print("LIVING ROCK TEST: %d checks, %d failures" % [_checks, _failures])
	if _failures == 0:
		print("LIVING ROCK OK")
	get_tree().quit(0 if _failures == 0 else 1)
