class_name RockSquareBuilder
extends RefCounted
## Modular builder & QA suite for Square 5 (`x = +1344..+1728`, `y = -144..+144`: Glimmtal-Steinhang):
## - Constructs `RockyGround` (stony mineral loam, Voronoi angular slate/greywacke scree, stratified
##   exposed bedrock shelves, crustose map-lichens, crevice moss pockets, quarry footpath & 16 detail sprites)
## - Populates 15 `LivingRock` outcrops across all 5 size stages (`s0..s4`) and all 12 geological archetypes
##   with varied random props & ecological "Befall" (`moss`, `lichen`, `ivy`, `fern`, `fungi` + async `Jobs` microclimate)
## - Provides automated functional tests & close-up visual capture helpers for `GrassLab` and `test_living_rock`.

const ROCK_SCENE: PackedScene = preload("res://src/entities/props/living_rock.tscn")
const SQ5_RECT: Rect2 = Rect2(1344.0, -144.0, 384.0, 288.0)
const SQ5_GROUND_BOUNDS: Rect2 = Rect2(1280.0, -144.0, 448.0, 288.0) ## Overlaps 64px into Square 4's east margin for seamless blending!
const SQ5_CENTER: Vector2 = Vector2(1536.0, 12.0)

var rocky_ground: RockyGround = null
var rocks_root: Node2D = null
var rocks: Array[LivingRock] = []
var hero_tor_s4: LivingRock = null
var hero_monolith_s3: LivingRock = null
var hero_quarry_s2: LivingRock = null
var hero_loose_s0: LivingRock = null


func setup_ground(parent: Node2D) -> RockyGround:
	rocky_ground = RockyGround.new()
	rocky_ground.name = "RockyGround"
	parent.add_child(rocky_ground)
	rocky_ground.setup(SQ5_GROUND_BOUNDS, 2.0)

	# 1. Organic Highland Rocky Slope base transitioning seamlessly out of Square 4's Oak Glade (`x = 1310..1380`)
	rocky_ground.paint_rocky_highland_zone(SQ5_RECT, 52.0, 701)

	# 2. Meandering worn stony footpath leading from Square 4's eastern oaks right onto the stone terrace
	var quarry_trail: Array[Vector2] = [
		Vector2(1292.0, 22.0),
		Vector2(1358.0, 14.0),
		Vector2(1434.0, 8.0),
		Vector2(1516.0, 18.0),
		Vector2(1602.0, 6.0),
		Vector2(1674.0, -8.0),
	]
	rocky_ground.paint_quarry_trail(quarry_trail, 9.5, 887)

	# 3. Exposed Stratified Bedrock Terraces (`stone` underfoot, crustose ochre & sage map-lichens, 1px chiseled bevels)
	rocky_ground.paint_bedrock_shelf(Vector2(1564.0, -58.0), Vector2(74.0, 40.0), 0.96, 811)
	rocky_ground.paint_bedrock_shelf(Vector2(1652.0, 44.0), Vector2(52.0, 32.0), 0.92, 823)

	# 4. Angular Fractured Slate & Greywacke Scree / Talus Fans (`gravel` underfoot)
	rocky_ground.paint_scree_fan(Vector2(1488.0, -18.0), Vector2(52.0, 30.0), 0.88, 853)
	rocky_ground.paint_scree_fan(Vector2(1588.0, 84.0), Vector2(62.0, 34.0), 0.92, 863)

	# 5. Shaded Western Woodland-Edge Cushion-Moss Pockets (`moss` underfoot, nourished by Square 4 oak shade)
	rocky_ground.paint_moss_pocket(Vector2(1396.0, -52.0), Vector2(40.0, 26.0), 0.90, 911)
	rocky_ground.paint_moss_pocket(Vector2(1408.0, 74.0), Vector2(36.0, 24.0), 0.86, 919)

	# Pre-stamp boulder collars before `commit()` so `RockyGround` & `LivingGrass` know exact footprints!
	for spec: Dictionary in _outcrop_specs():
		var p: Vector2 = spec["p"] as Vector2
		var stg: int = int(spec["s"])
		var hw: float = [8.0, 14.0, 21.0, 30.0, 44.0][clampi(stg, 0, 4)]
		var hh: float = [4.0, 6.0, 8.0, 11.0, 14.0][clampi(stg, 0, 4)]
		rocky_ground.register_rock_outcrop(p, hw, hh, int(spec["seed"]))

	_populate_ground_details()
	rocky_ground.commit()
	return rocky_ground


func spawn_outcrops(parent: Node2D, tree_positions: Array[Vector2] = []) -> Node2D:
	rocks_root = Node2D.new()
	rocks_root.name = "GlimmtalRocks"
	rocks_root.y_sort_enabled = true
	parent.add_child(rocks_root)
	rocks.clear()

	for spec: Dictionary in _outcrop_specs():
		var rk: LivingRock = ROCK_SCENE.instantiate() as LivingRock
		rk.setup_rock(spec["p"] as Vector2, int(spec["s"]), int(spec["seed"]), "valley_stone")
		var arch: int = int(spec.get("a", -1))
		var flip_v: int = int(spec.get("f", -1))
		var traits: Dictionary = spec.get("t", {}) as Dictionary
		rk.configure_traits(arch, traits, flip_v)
		rocks_root.add_child(rk)
		rocks.append(rk)

		var tag: String = String(spec.get("tag", ""))
		if tag == "hero_tor":
			hero_tor_s4 = rk
		elif tag == "hero_monolith":
			hero_monolith_s3 = rk
		elif tag == "hero_quarry":
			hero_quarry_s2 = rk
		elif tag == "hero_loose":
			hero_loose_s0 = rk

	var job: Jobs.Job = LivingRock.compute_outcrop_ecology_async(rocks, tree_positions)
	Jobs.wait(job)
	return rocks_root


func _outcrop_specs() -> Array[Dictionary]:
	return [
		# 1. Hero Stage 4 Massive Tor (`s4_a`) crowning the northern bedrock shelf (ochre/sage map-lichen + crevice fern!)
		{"p": Vector2(1560.0, -64.0), "s": 4, "a": 0, "f": 0, "seed": 401, "tag": "hero_tor",
			"t": {"moss": 0, "lichen": 1, "ivy": -1, "fern": 1, "fungi": -1}},
		# 2. Stage 4 Broad Split Erratic Massif (`s4_b`) anchoring the SE talus fan (lush moss, ivy, Sempervivum & fungi!)
		{"p": Vector2(1638.0, 82.0), "s": 4, "a": 1, "f": 0, "seed": 402,
			"t": {"moss": 1, "lichen": 0, "ivy": 0, "fern": 0, "fungi": 0}},

		# 3. West Woodland-Edge Mossy Craggy Monolith (`s3_a` — heavy moss, creeping ivy, spleenwort fern & night spore fungi!)
		{"p": Vector2(1408.0, -44.0), "s": 3, "a": 0, "f": 0, "seed": 301, "tag": "hero_monolith",
			"t": {"moss": 0, "lichen": -1, "ivy": 1, "fern": 0, "fungi": 0}},
		# 4. NE Sunlit Stratified Overhang Ledge (`s3_b` — golden/sage crustose lichens, minimal moss)
		{"p": Vector2(1664.0, -46.0), "s": 3, "a": 1, "f": 1, "seed": 302,
			"t": {"moss": -1, "lichen": 1, "ivy": -1, "fern": 1, "fungi": -1}},
		# 5. Central Diagonal Tectonic-Cleavage Outcrop (`s3_c`) beside the scree fan
		{"p": Vector2(1496.0, -78.0), "s": 3, "a": 2, "f": 0, "seed": 303,
			"t": {"moss": 1, "lichen": 0, "ivy": -1, "fern": -1, "fungi": 0}},

		# 6. Hero Quarry Showcase Block (`s2_a`) right beside the central trail (ready for live pickaxe mining!)
		{"p": Vector2(1488.0, 32.0), "s": 2, "a": 0, "f": 0, "seed": 201, "tag": "hero_quarry",
			"t": {"moss": 0, "lichen": 0, "ivy": -1, "fern": 0, "fungi": -1}},
		# 7. SW Mossy Stepped Slate Stack (`s2_b`) near Square 4 oaks
		{"p": Vector2(1402.0, 76.0), "s": 2, "a": 1, "f": 0, "seed": 202,
			"t": {"moss": 1, "lichen": -1, "ivy": 0, "fern": 1, "fungi": 0}},
		# 8. South Split Twin-Boulder (`s2_c`) in the scree apron
		{"p": Vector2(1548.0, 92.0), "s": 2, "a": 2, "f": 1, "seed": 203,
			"t": {"moss": 0, "lichen": 1, "ivy": -1, "fern": -1, "fungi": -1}},
		# 9. East Bedrock Ridge Block (`s2_a`, flipped, sun-bleached lichen)
		{"p": Vector2(1668.0, 26.0), "s": 2, "a": 0, "f": 1, "seed": 204,
			"t": {"moss": -1, "lichen": 1, "ivy": -1, "fern": 1, "fungi": -1}},

		# 10..12. Variable Small Boulders (`s1_a`, `s1_b` — natural rolled Befall!)
		{"p": Vector2(1364.0, -88.0), "s": 1, "a": 0, "f": -1, "seed": 101},
		{"p": Vector2(1448.0, -14.0), "s": 1, "a": 1, "f": -1, "seed": 102},
		{"p": Vector2(1588.0, 22.0), "s": 1, "a": 0, "f": -1, "seed": 103},
		{"p": Vector2(1462.0, 98.0), "s": 1, "a": 1, "f": -1, "seed": 104},

		# 13..16. Loose Hand-Collectible Fieldstones (`s0_a`, `s0_b` — `[E] FELDSTEIN AUFHEBEN` or 1 pickaxe hit!)
		{"p": Vector2(1434.0, 24.0), "s": 0, "a": 0, "f": 0, "seed": 51, "tag": "hero_loose"},
		{"p": Vector2(1526.0, -16.0), "s": 0, "a": 1, "f": 1, "seed": 52},
		{"p": Vector2(1612.0, -12.0), "s": 0, "a": 0, "f": 1, "seed": 53},
		{"p": Vector2(1518.0, 62.0), "s": 0, "a": 1, "f": 0, "seed": 54},
	]


func _populate_ground_details() -> void:
	if rocky_ground == null:
		return
	var curated: Array[Dictionary] = [
		{"p": Vector2(1522.0, -48.0), "v": 3, "f": false}, ## flat slate plate on bedrock edge
		{"p": Vector2(1596.0, -42.0), "v": 4, "f": true},
		{"p": Vector2(1624.0, -72.0), "v": 13, "f": false}, ## Sempervivum rosette in bedrock joint
		{"p": Vector2(1542.0, -86.0), "v": 14, "f": true},
		{"p": Vector2(1426.0, -36.0), "v": 12, "f": false}, ## crevice rock-fern with dew glimmer
		{"p": Vector2(1418.0, 88.0), "v": 11, "f": true},
		{"p": Vector2(1572.0, -34.0), "v": 15, "f": false}, ## damp crevice quartz-pebble cluster
		{"p": Vector2(1622.0, 62.0), "v": 15, "f": true},
		{"p": Vector2(1474.0, -12.0), "v": 0, "f": false},  ## angular scree splinters
		{"p": Vector2(1506.0, 44.0), "v": 1, "f": true},
		{"p": Vector2(1574.0, 78.0), "v": 2, "f": false},
		{"p": Vector2(1382.0, -56.0), "v": 6, "f": false},  ## mossy gravel pocket near oaks
		{"p": Vector2(1372.0, 54.0), "v": 7, "f": true},
	]
	for cd: Dictionary in curated:
		rocky_ground.add_rock_detail(cd["p"] as Vector2, int(cd["v"]), bool(cd["f"]))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2055
	for _i: int in 34:
		var dp: Vector2 = Vector2(rng.randf_range(1348.0, 1712.0), rng.randf_range(-128.0, 128.0)).round()
		if _near_any_outcrop(dp, 18.0):
			continue
		var surf: String = rocky_ground.surface_at(dp)
		var roll: float = rng.randf()
		var v: int = 0
		if surf == "stone":
			v = 9 if roll < 0.38 else (10 if roll < 0.65 else (13 if roll < 0.86 else 14))
		elif surf == "gravel":
			v = 0 if roll < 0.34 else (1 if roll < 0.64 else (2 if roll < 0.84 else 5))
		elif surf == "moss":
			v = 6 if roll < 0.40 else (11 if roll < 0.75 else 12)
		else:
			v = 3 if roll < 0.32 else (4 if roll < 0.58 else (7 if roll < 0.82 else 8))
		var tv: float = rng.randf_range(0.93, 1.05)
		rocky_ground.add_rock_detail(dp, v, rng.randf() < 0.5, Color(tv, tv, tv, 1.0))


func _near_any_outcrop(p: Vector2, min_dist: float) -> bool:
	for spec: Dictionary in _outcrop_specs():
		if p.distance_to(spec["p"] as Vector2) < min_dist:
			return true
	return false
