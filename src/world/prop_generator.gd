class_name PropGenerator
extends RefCounted
## Decides which props (data/plants.json) stand where. Everything is a pure function of the world
## seed, the ground noise and the baked coast, so every peer and every chunk load gets the same
## result. Two kinds of layers:
##  - a background that keeps the whole meadow populated and even: one candidate per cell of a
##    jittered grid (lone firs, lone bushes, single pebbles and a few single small rocks, glow caps
##    in the shade, single clumps of whisper grass);
##  - clusters on top: groves of firs (giants in the middle, smaller toward the edge, bushes between),
##    thickets, and rock formations, which are the only place where stones lie in groups: each one
##    comes with its own bed of gravel (a decal under it) and everything stony stays on that bed.
## No two props overlap: every candidate has a footprint and a priority (tree, rock, berry bush, bush,
## pebble, plus a seeded tie-break), and a candidate is dropped when a higher-priority candidate
## overlaps it. That only looks at candidates nearby, so any chunk gets the same answer.

const LAYERS: Array[Dictionary] = [
	{"id": 1, "name": "grove", "cell": 26, "reach": 20},
	{"id": 2, "name": "formation", "cell": 36, "reach": 10},
	{"id": 3, "name": "thicket", "cell": 18, "reach": 10},
	{"id": 4, "name": "lone_tree", "cell": 14, "reach": 4},
	{"id": 5, "name": "lone_bush", "cell": 8, "reach": 4},
	{"id": 6, "name": "lone_stone", "cell": 11, "reach": 4},
	{"id": 7, "name": "lone_mushroom", "cell": 9, "reach": 3},
	{"id": 8, "name": "lone_grass", "cell": 6, "reach": 3},
	{"id": 9, "name": "tussock", "cell": 16, "reach": 6},
	{"id": 10, "name": "willow_stand", "cell": 24, "reach": 10},
	{"id": 11, "name": "orchard", "cell": 28, "reach": 10},
	{"id": 12, "name": "lone_blossom", "cell": 17, "reach": 4},
	{"id": 13, "name": "wood", "cell": 30, "reach": 16},
	{"id": 14, "name": "copse", "cell": 12, "reach": 5},
	{"id": 15, "name": "lone_flora", "cell": 7, "reach": 3},
	{"id": 16, "name": "flora_patch", "cell": 15, "reach": 7},
	{"id": 17, "name": "lone_root", "cell": 18, "reach": 3},
	{"id": 18, "name": "birch_grove", "cell": 26, "reach": 12},
	{"id": 19, "name": "lone_birch", "cell": 13, "reach": 4},
	{"id": 20, "name": "shroom_patch", "cell": 17, "reach": 5},
	{"id": 21, "name": "fairy_ring", "cell": 44, "reach": 9},
	{"id": 22, "name": "water_edge", "cell": 4, "reach": 4},
	{"id": 23, "name": "lone_snapper", "cell": 21, "reach": 3},
	{"id": 24, "name": "lone_ore", "cell": 28, "reach": 4},
	{"id": 25, "name": "ore_formation", "cell": 60, "reach": 10},
	{"id": 26, "name": "witch_wood", "cell": 22, "reach": 13},
	{"id": 27, "name": "witch_tree", "cell": 8, "reach": 4},
	{"id": 28, "name": "witch_flora", "cell": 4, "reach": 3},
	{"id": 29, "name": "witch_patch", "cell": 10, "reach": 5},
	{"id": 30, "name": "witch_ore", "cell": 22, "reach": 4},
	{"id": 31, "name": "bloom_drift", "cell": 21, "reach": 9},
	{"id": 32, "name": "boulder_nook", "cell": 33, "reach": 7},
	{"id": 33, "name": "lake_stones", "cell": 5, "reach": 3},
	{"id": 34, "name": "desert_garden", "cell": 23, "reach": 10},
	{"id": 35, "name": "desert_cactus", "cell": 13, "reach": 5},
	{"id": 36, "name": "desert_scrub", "cell": 8, "reach": 5},
	{"id": 37, "name": "desert_quartz", "cell": 7, "reach": 4},
	{"id": 38, "name": "desert_tuber", "cell": 16, "reach": 4},
	{"id": 39, "name": "oasis_palm", "cell": 5, "reach": 6},
	{"id": 40, "name": "oasis_flora", "cell": 4, "reach": 4},
	{"id": 41, "name": "desert_rock_cluster", "cell": 16, "reach": 9},
	{"id": 42, "name": "desert_rock_lone", "cell": 9, "reach": 6},
	{"id": 43, "name": "urforst_dome", "cell": 16, "reach": 15},
	{"id": 44, "name": "pasture_trace", "cell": 22, "reach": 15},
]
const WITCH_KINDS: Array[String] = ["hag_tree", "bone_tree", "thorn_hedge", "grave_candle", "witch_hat", "toad_cap", "ghost_fern", "mandrake", "curse_rock", "hex_shrub", "witch_broom"] ## the Hexenwald's own plant world (tools/art_hexenwald.py): grows only where the biome is `bare` of the meadow's
const DESERT_KINDS: Array[String] = ["crown_cactus", "prickly_pear", "barrel_cactus", "desert_scrub", "tumble_scrub", "dune_grass", "glass_aloe", "night_cactus", "sand_tuber", "sun_palm", "oasis_reed", "oasis_lily", "sun_quartz_rock", "prism_vein", "ruin_sandstone"] ## Sonnenquarz-Öde's own desert flora & ores (tools/art_desert.py, tools/art_desert_ruins.py): grows only where `is_desert_bare` (`bare == 2`)
const DESERT_SHARED: Array[String] = ["bush", "grass"] ## meadow plants allowed into the outer steppe fringe (arid < 0.35), where they warm and give way to desert scrub/grass
const SHORE_KINDS: Array[String] = ["marsh_gold", "moon_iris", "brook_mint", "cattail", "lake_glimmer", "lake_moonstone", "oasis_reed", "oasis_lily"] ## may grow at the water's edge
const LAKE_KINDS: Array[String] = ["lake_glimmer", "lake_moonstone"] ## the lake witch's raw stones (docs/seehexe_konzept.md 6): only on the shores of the Hexenwald's waters
const TREE_KINDS: Array[String] = ["tree", "ancient_fir", "orchard_apple", "orchard_pear", "willow", "blossom", "birch", "hag_tree", "bone_tree", "crown_cactus", "sun_palm"] ## what has a trunk and a crown
const WITCH_SHARED: Array[String] = ["bush"] ## meadow plants the Hexenwald shares: only along its fringe, deeper in every "bush" becomes one of its own (`_hex_bush`)
const WITCH_CLEARING: int = 15 ## percent of the witch_wood cells that are a clearing with a witches' ring instead of a wood (`_in_clearing`)
const WITCH_CLEARING_R: float = 7.5 ## tiles: no tree or bush grows that close to a clearing's middle
const PRIORITY: Dictionary = {"ancient_fir": 4.35, "tree": 4.0, "orchard_apple": 3.45, "orchard_pear": 3.45, "dry_stone_wall": 3.15, "rock": 3.0, "iron_rock": 3.05, "broken_fence": 2.35, "berry_bush": 2.2, "bush": 2.0, "pebble": 1.0, "mushroom": 0.0, "grass": 0.6, "ember_bush": 2.1, "willow": 3.5, "blossom": 3.4, "birch": 3.3, "ember_morel": 0.1, "moon_parasol": 0.1, "moon_iris": 0.3, "brook_mint": 0.25, "marsh_gold": 0.3, "moonbell": 0.2, "wound_leaf": 0.2, "puffseed": 0.25, "glowfern": 0.3, "cattail": 0.35, "sunbloom": 0.3, "voidbloom": 0.2, "earth_tuber": 0.15, "ember_carrot": 0.25, "night_beet": 0.25, "mist_lily": 0.3, "spark_poppy": 0.25, "snapper": 0.3, "hag_tree": 4.0, "bone_tree": 3.6, "curse_rock": 3.05, "thorn_hedge": 2.0, "ghost_fern": 0.3, "grave_candle": 0.25, "witch_hat": 0.25, "toad_cap": 0.1, "mandrake": 0.2, "hex_shrub": 1.9, "witch_broom": 1.8, "lake_glimmer": -1.0, "lake_moonstone": -1.0, "crown_cactus": 3.8, "prickly_pear": 2.15, "barrel_cactus": 1.85, "desert_scrub": 1.9, "tumble_scrub": 1.6, "dune_grass": 0.65, "glass_aloe": 1.4, "night_cactus": 1.5, "sand_tuber": 0.25, "sun_palm": 3.95, "sun_quartz_rock": 3.08, "prism_vein": 3.12, "ruin_sandstone": 3.06, "oasis_lily": 1.45, "oasis_reed": 1.35} ## mushrooms give way to everything, so they never change what else stands where
const BED_RX: Array[float] = [40.0, 48.0, 56.0, 64.0, 72.0, 80.0] ## px, the gravel beds (assets/props/stonebed.png)
const BED_FLATTEN: float = 0.64
const GAP: float = 3.0 ## px kept free between footprints
const CROWN_OVERLAP: float = 0.8 ## crowns may just touch (x their half widths): the minimum distance of two trees is this x the sum of their crown half widths
const DENSE_CROWN_OVERLAP: float = 0.6 ## the same for two trees of a grove or a wood: their crowns reach into each other and close into one canopy (a smaller factor lets them stand closer)
const FOREST_BED_RX: Array[float] = [28.0, 36.0, 44.0, 52.0, 60.0, 70.0] ## px, the forest floor under every tree of a wood (assets/props/forestbed.png, tools/art_forestbed.py); variants 6-11 are the same sizes in the Hexenwald's floor (row 1)
const KRUMMHOLZ_LEVEL: float = 1.6 ## relief level (0..3, smooth) from which trees and bushes are stunted by wind and cold
const BUSH_KINDS: Array[String] = ["bush", "berry_bush", "ember_bush", "prickly_pear", "desert_scrub"]
const YOUNG_GROW_DAYS: float = 7.0 ## days a generated sapling needs to become a fir (WorldLevel counts them from day 1)
const BUCKET: float = 112.0 ## px, grid for the overlap search (bigger than any two giant ancient_fir footprints/crowns together)
const DECAL_KINDS: Array[String] = ["stonebed", "moss_carpet", "pasture_paving"]
const SMALL_ROCKS: Array[int] = [0, 1, 4, 5, 6]
const BIG_ROCKS: Array[int] = [1, 2, 3, 5, 6, 7]
const QUARTZ_ROCK_BASE_HW: Array[float] = [11.5, 12.5, 15.0, 9.5, 17.5, 13.5] ## px half-width of each sun_quartz_rock variant's basal quartz skirt; every sample must lie on ground quartz
const PRISM_VEIN_BASE_HW: Array[float] = [12.5, 14.0, 15.0, 13.5] ## px half-width of each prism_vein variant's basal quartz skirt
const ORE_VARIANT: Array[int] = [0, 1, 2, 3, 4, 3, 1, 5] ## the iron rock (data/plants.json "iron_rock", 6 variants) that stands in for each stone rock variant
const ORE_IN_FORMATION: int = 6 ## percent of the small rocks of an ordinary rock formation that are iron ore instead (decided by position: no random draw, so the rest stays as it was)
const ORE_IN_ORE_FORMATION: int = 45 ## the same inside an ore formation (its big rock is always ore)

var water_clear: Callable
var water_dist: Callable ## px from the nearest water's edge at a world position (INF when none is near), set by the world level
var _zone: FastNoiseLite
var _sdf: PackedByteArray
var _relief: Relief
var blocked_cells: Dictionary = {} ## tiles kept clear of props (the footpath, the manhole cover), set by the world level
var extra_props: Array[Dictionary] = [] ## hand-placed props {cell, kind, variant}, set by the world level (data/ground.json "props"); they win over generated ones
var berry_free_cells: Dictionary = {} ## tiles where no berry grows (the start of the story: nothing may heal her); berry bushes become plain bushes there
var tree_free_cells: Dictionary = {} ## tiles (old flagstones) where no tree stands, set by the world level
var bare: PackedByteArray = PackedByteArray() ## one byte per map cell (RegionMap.bare_cells), 1 = a biome without props yet (the Hexenwald), set by the world level; empty = none
var _exclude: Rect2i
var _seed: int
var _plants: Dictionary
var _cache: Dictionary = {}
var _cluster_rng: RandomNumberGenerator = RandomNumberGenerator.new()
const CACHE_LIMIT: int = 40000 ## clusters kept at most; beyond it the cache starts over (one chunk alone asks for ~4000, neighbours share most of them)
const LAYER_NEEDS: Dictionary = {"lone_bush": 2, "lone_grass": 1, "tussock": 1, "lone_mushroom": 2, "lone_snapper": 2, "lone_flora": 2, "lone_root": 1, "shroom_patch": 2, "flora_patch": 2, "bloom_drift": 2, "boulder_nook": 2} ## layers that read the slope (1) or slope and damp (2) of a cluster


func _init(zone: FastNoiseLite, sdf: PackedByteArray, relief: Relief, exclude: Rect2i, world_seed: int) -> void:
	_zone = zone
	_sdf = sdf
	_relief = relief
	_exclude = exclude
	_seed = world_seed
	_plants = DataRegistry.table("plants")


## A second generator with the same world inputs but its own cluster cache and random generator, for a worker thread
## (`_cache` and `_cluster_rng` are scratch state of one query at a time). Every fork answers exactly like the original.
func fork() -> PropGenerator:
	var copy: PropGenerator = PropGenerator.new(_zone, _sdf, _relief, _exclude, _seed)
	copy.sync_inputs(self)
	return copy


## Takes over the world inputs the level set on `source` (references: they are read-only while queries run).
func sync_inputs(source: PropGenerator) -> void:
	water_clear = source.water_clear
	water_dist = source.water_dist
	blocked_cells = source.blocked_cells
	extra_props = source.extra_props
	berry_free_cells = source.berry_free_cells
	tree_free_cells = source.tree_free_cells
	bare = source.bare


## True where the map's biome suppresses meadow props (`bare` in data/biomes.json: 1 = witch_forest, 2 = other bare biomes).
func is_bare(cell: Vector2i) -> bool:
	if bare.is_empty():
		return false
	var side: int = RegionMap.WORLD_TILES / RegionMap.CELL
	return bare[clampi(cell.y / RegionMap.CELL, 0, side - 1) * side + clampi(cell.x / RegionMap.CELL, 0, side - 1)] != 0


## True specifically in the Hexenwald (`bare == 1`), which grows its own plant world.
func is_witch(cell: Vector2i) -> bool:
	if bare.is_empty():
		return false
	var side: int = RegionMap.WORLD_TILES / RegionMap.CELL
	return bare[clampi(cell.y / RegionMap.CELL, 0, side - 1) * side + clampi(cell.x / RegionMap.CELL, 0, side - 1)] == 1


## True in bare biomes that currently carry zero props at all (`bare == 2`, e.g. stage-1 `quartz_desert`).
func is_desert_bare(cell: Vector2i) -> bool:
	if bare.is_empty():
		return false
	var side: int = RegionMap.WORLD_TILES / RegionMap.CELL
	return bare[clampi(cell.y / RegionMap.CELL, 0, side - 1) * side + clampi(cell.x / RegionMap.CELL, 0, side - 1)] == 2


## Where a prop in `cell` stands (px, at its feet): a little off the middle so rows never look ruled.
static func position_of(cell: Vector2i) -> Vector2:
	var h: int = absi(hash(Vector2i(cell.x, cell.y * 7 + 3)))
	return Vector2(cell) * 16.0 + Vector2(8 + h % 9 - 4, 13 + (h / 9) % 5 - 2)


## The props of one chunk (`rect` in tiles): [{cell, kind, variant, pos}] (+ `scale` for stunted trees on high ground, `young` for saplings).
## Kinds "stonebed" (gravel under a rock formation) and "forestbed" (litter under a tree of a wood) are ground decals (variant = their
## size), not props.
func props_for_chunk(rect: Rect2i) -> Array[Dictionary]:
	var query: Query = Query.new(self, rect, rect)
	query.advance()
	return query.inner


## Both exact query windows share clusters, spatial buckets and overlap tests. Membership
## bits retain the old window-specific candidate sets (including their original order).
func begin_chunk(rect: Rect2i) -> Query:
	return Query.new(self, rect, rect.grow(5))


class Query:
	extends RefCounted
	var inner: Array[Dictionary] = []
	var outer: Array[Dictionary] = []
	var done: bool = false
	var _generator: PropGenerator
	var _rect: Rect2i
	var _expanded: Rect2i
	var _near: Array[Dictionary] = []
	var _grid: Dictionary = {}
	var _phase: int = 0
	var _layer: int = -1
	var _cursor: Vector2i
	var _lo: Vector2i
	var _hi: Vector2i
	var _inner_bounds: Rect2i
	var _index: int = 0

	func _init(generator: PropGenerator, rect: Rect2i, expanded: Rect2i) -> void:
		_generator = generator
		_rect = rect
		_expanded = expanded
		_next_layer()

	## A zero deadline drains synchronously for initial loading and editor rebuilds.
	func advance(deadline: int = 0) -> bool:
		while not done:
			if deadline > 0 and Time.get_ticks_usec() >= deadline:
				return false
			match _phase:
				0:
					var mask: int = 3 if _inner_bounds.has_point(_cursor) else 2
					for candidate: Dictionary in _generator._cluster(LAYERS[_layer], _cursor):
						_near.append({"candidate": candidate, "mask": mask})
					_cursor.x += 1
					if _cursor.x > _hi.x:
						_cursor.x = _lo.x
						_cursor.y += 1
						if _cursor.y > _hi.y: _next_layer()
				1:
					if _index >= _generator.extra_props.size():
						_phase = 2
						_index = 0
						continue
					var spec: Dictionary = _generator.extra_props[_index]
					_index += 1
					var plant: Dictionary = _generator._plants[String(spec.kind)]
					var cell: Vector2i = spec.cell
					var pos: Vector2 = PropGenerator.position_of(cell)
					var foot: float = _generator._foot(plant, String(spec.kind), int(spec.variant))
					if _generator._relief.flat_around(pos, maxf(foot - 8.0, 0.0)):
						_near.append({"candidate": {"cell": cell, "kind": spec.kind, "variant": int(spec.variant), "pos": pos, "foot": foot, "crown": _generator._crown(plant, String(spec.kind), int(spec.variant)), "prio": 10.0}, "mask": 3})
				2:
					if _index >= _near.size():
						_phase = 3
						_index = 0
						continue
					var entry: Dictionary = _near[_index]
					_index += 1
					var candidate: Dictionary = entry.candidate
					if not DECAL_KINDS.has(String(candidate.kind)):
						var pos: Vector2 = candidate.pos
						var bucket: Vector2i = Vector2i(floori(pos.x / BUCKET), floori(pos.y / BUCKET))
						(_grid.get_or_add(bucket, []) as Array).append(entry)
				3:
					if _index >= _near.size():
						done = true
						_near.clear()
						_grid.clear()
						continue
					var entry: Dictionary = _near[_index]
					_index += 1
					var candidate: Dictionary = entry.candidate
					var cell: Vector2i = candidate.cell
					var c_kind: String = String(candidate.kind)
					if SHORE_KINDS.has(c_kind): ## waterside plants may stand right at the bank, just not in the water
						if _generator.water_dist.is_valid() and float(_generator.water_dist.call(candidate.pos)) < 4.0: continue
					elif _generator.water_clear.is_valid() and not bool(_generator.water_clear.call(candidate.pos, float(candidate.get("foot", 80.0)))): continue
					if not _expanded.has_point(cell): continue
					var wanted: int = 3 if int(entry.mask) == 3 and _rect.has_point(cell) else 2
					var blocked: int = 0 if DECAL_KINDS.has(c_kind) else _dominated(candidate, wanted)
					var result: Dictionary = {"cell": cell, "kind": candidate.kind, "variant": candidate.variant, "pos": candidate.pos}
					if candidate.has("scale"): result["scale"] = candidate.scale
					if candidate.has("young"): result["young"] = candidate.young
					var in_inner: bool = (wanted & 1) != 0 and (blocked & 1) == 0
					var in_outer: bool = (blocked & 2) == 0
					if in_inner: inner.append(result)
					if in_outer: outer.append(result)
					if candidate.has("bed") and (in_inner or in_outer): ## a tree that stands also lays down its patch of forest floor
						var bed: Dictionary = {"cell": cell, "kind": "forestbed", "variant": int(candidate.bed), "pos": (candidate.pos as Vector2) + Vector2(0, -5)}
						if in_inner: inner.append(bed)
						if in_outer: outer.append(bed)
		return true

	func _next_layer() -> void:
		_layer += 1
		if _layer >= LAYERS.size():
			_phase = 1
			_index = 0
			return
		var layer: Dictionary = LAYERS[_layer]
		var size: float = float(layer.cell)
		var reach: int = int(layer.reach) + 6
		_lo = Vector2i(floori((_expanded.position.x - reach) / size), floori((_expanded.position.y - reach) / size))
		_hi = Vector2i(floori((_expanded.end.x + reach) / size), floori((_expanded.end.y + reach) / size))
		_cursor = _lo
		var inner_lo: Vector2i = Vector2i(floori((_rect.position.x - reach) / size), floori((_rect.position.y - reach) / size))
		var inner_hi: Vector2i = Vector2i(floori((_rect.end.x + reach) / size), floori((_rect.end.y + reach) / size))
		_inner_bounds = Rect2i(inner_lo, inner_hi - inner_lo + Vector2i.ONE)

	func _dominated(candidate: Dictionary, wanted: int) -> int:
		var pos: Vector2 = candidate.pos
		var at: Vector2i = Vector2i(floori(pos.x / BUCKET), floori(pos.y / BUCKET))
		var blocked: int = 0
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				for entry: Dictionary in _grid.get(at + Vector2i(dx, dy), []):
					var relevant: int = int(entry.mask) & wanted & ~blocked
					if relevant == 0: continue
					var other: Dictionary = entry.candidate
					# A candidate cannot outrank itself; avoid deep Dictionary comparisons.
					if float(other.prio) > float(candidate.prio) and _generator._overlap(candidate, other):
						blocked |= relevant
						if blocked == wanted: return blocked
		return blocked


# ----------------------------------------------------------------------------- clusters
func _cluster(layer: Dictionary, cc: Vector2i) -> Array[Dictionary]:
	var key: Vector3i = Vector3i(int(layer.id), cc.x, cc.y)
	if _cache.has(key):
		return _cache[key]
	var rng: RandomNumberGenerator = _cluster_rng ## one generator, reseeded per cluster (a new object per cluster cost ~4000 allocations a chunk)
	rng.seed = hash(Vector4i(int(layer.id), cc.x, cc.y, _seed))
	var size: float = float(layer.cell)
	var center: Vector2 = (Vector2(cc) + Vector2(rng.randf(), rng.randf())) * size
	var wild: float = _wild(center)
	var shore: float = _shore(center)
	# Slope and damp cost ~20 us each and only some layers read them (LAYER_NEEDS); the rest skip them (they use no rng, so the result is the same).
	var needs: int = int(LAYER_NEEDS.get(String(layer.name), 0))
	var slope: float = aspect(center) if needs != 0 else 0.0 ## -1 north-facing slope / cliff foot .. +1 south-facing slope
	var shade: float = clampf(wild - 0.45 * slope, 0.0, 1.0) ## shaded, damp ground: the noise's shade plus what the slope adds
	var damp: float = damp_at(center, slope) if needs == 2 else 0.0
	var lush: float = lerpf(0.45, 1.0, smoothstep(0.1, 0.45, damp)) ## dry slopes carry less than damp ground
	var hab: Vector3 = MeadowHabitats.weights_at_tiles(center)
	var w_deep: float = hab.x
	var w_wind: float = hab.y
	var w_past: float = hab.z
	var found: Array[Dictionary] = []
	match String(layer.name):
		"grove":
			if w_wind < 0.34 and w_past < 0.25 and rng.randf() < lerpf(0.55, 1.0, wild) * (1.0 - 0.85 * smoothstep(0.15, 0.34, w_wind)):
				_grove(found, rng, center, wild)
		"formation":
			if rng.randf() < (0.45 + 0.35 * wild + 0.3 * shore) * (1.0 - 0.55 * w_wind) * (1.0 - 0.55 * w_past):
				_formation(found, rng, center)
		"thicket":
			if rng.randf() < lerpf(0.45, 0.9, wild) * (1.0 - 0.78 * w_wind) * (1.0 - 0.45 * w_deep) * (1.0 - 0.55 * w_past):
				_thicket(found, rng, center)
		"lone_tree":
			if w_wind < 0.32 and w_past < 0.22 and rng.randf() < lerpf(0.5, 0.8, wild) * (1.0 - 0.85 * smoothstep(0.12, 0.32, w_wind)):
				_add(found, rng, "tree", [0, 0, 1, 1, 2][rng.randi() % 5], center)
				if not found.is_empty(): ## a lone tree is never bare-footed: grass, a flower or a toadstool, a bush now and then (drawn after the tree, so the tree itself never moves)
					_skirt(found, rng, center, wild, shore, slope, 1.6, 4.2, rng.randi_range(2, 5))
		"lone_bush":
			if rng.randf() < 0.42 * lush * (1.0 - 0.75 * w_wind) * (1.0 - 0.35 * w_deep):
				var kind: String = _berry_kind(center, "berry_bush") if rng.randf() < 0.12 else "bush"
				_add(found, rng, kind, _weighted(rng, kind), center)
		"lone_stone":
			if rng.randf() < (0.4 + 0.15 * shore + (0.3 if _relief.wall_above(Vector2i(floori(center.x), floori(center.y))) else 0.0)) * (1.0 - 0.4 * w_wind): ## rubble lies at the foot of a cliff
				if rng.randf() < 0.12: ## now and then a single small rock instead
					_add(found, rng, "rock", SMALL_ROCKS[rng.randi() % SMALL_ROCKS.size()], center)
					if not found.is_empty():
						_skirt(found, rng, center, wild, shore, slope, 1.2, 3.0, rng.randi_range(2, 4))
				else:
					_add(found, rng, "pebble", _weighted(rng, "pebble"), center)
		"lone_ore": ## single iron rocks: rarer than stone, more at the foot of cliffs and on the high ground, a little more in the wild
			var tile: Vector2i = Vector2i(floori(center.x), floori(center.y))
			if rng.randf() < 0.2 + 0.3 * (1.0 if _relief.wall_above(tile) else 0.0) + 0.08 * smoothstep(0.5, 2.0, _relief.level_at(center * 16.0)) + 0.08 * wild:
				_add(found, rng, "iron_rock", _weighted(rng, "iron_rock"), center)
		"ore_formation": ## a rock formation whose big rock is iron ore, with ore among the smaller ones
			if rng.randf() < (0.3 + 0.25 * wild) * (1.0 - 0.4 * w_wind):
				_formation(found, rng, center, true)
		"lone_mushroom":
			if w_wind < 0.55 and rng.randf() < (0.1 + 0.5 * shade) * (0.5 + damp) * (1.0 + 1.8 * w_deep): ## they like the shade (and north slopes and cliff feet) and the damp
				_add(found, rng, "mushroom", _weighted(rng, "mushroom"), center)
		"lone_grass":
			if w_deep < 0.42 and rng.randf() < (0.5 - 0.3 * wild + 0.15 * maxf(slope, 0.0)) * (1.0 + 0.85 * w_wind) * (1.0 - smoothstep(0.20, 0.42, w_deep)): ## more in the open meadow and on sunny slopes; almost none under the Urforst dome
				_add(found, rng, "grass", _weighted(rng, "grass"), center)
		"tussock":
			if w_deep < 0.38 and rng.randf() < (0.55 - 0.25 * wild + 0.2 * maxf(slope, 0.0)) * (1.0 + 0.90 * w_wind) * (1.0 - smoothstep(0.18, 0.38, w_deep)):
				_tussock(found, rng, center)
		"willow_stand":
			if w_wind < 0.34 and rng.randf() < 0.16 + 0.55 * shore + 0.12 * wild: ## willows like the wet, shaded ground near the coast
				_willow_stand(found, rng, center)
		"orchard":
			if w_wind < 0.34 and w_deep < 0.32 and w_past < 0.30 and rng.randf() < 0.08 + 0.4 * (1.0 - wild): ## blossom trees stand in the open
				_orchard(found, rng, center)
		"wood":
			if w_wind < 0.34 and w_past < 0.25 and rng.randf() < (0.15 + 0.5 * wild + 0.35 * w_deep) * (1.0 - 0.85 * smoothstep(0.15, 0.34, w_wind)): ## big mixed woods, mostly in the shaded, wild ground
				_wood(found, rng, center)
		"copse":
			if w_wind < 0.34 and w_past < 0.25 and rng.randf() < 0.3 * (1.0 - 0.85 * smoothstep(0.15, 0.34, w_wind)):
				_copse(found, rng, center)
		"lone_blossom":
			if w_wind < 0.34 and w_deep < 0.30 and w_past < 0.30 and rng.randf() < 0.1 + 0.16 * (1.0 - wild):
				_add(found, rng, "blossom", _weighted(rng, "blossom"), center)
		"lone_snapper": ## the odd night flower of the dark, damp shade (it only bites at night, and not inside the town's light)
			if w_wind < 0.45 and rng.randf() < (0.04 + 0.22 * shade * damp) * (1.0 + 0.65 * w_deep):
				_add(found, rng, "snapper", _weighted(rng, "snapper"), center)
		"lone_flora":
			if rng.randf() < 0.5 * lush * (1.0 + 0.75 * w_wind):
				var flora: String = MeadowHabitats.wind_flower_at(center) if (w_wind >= 0.42 and rng.randf() < 0.88) else ("glowfern" if (w_deep >= 0.42 and rng.randf() < 0.82) else _flora_kind(rng, center, shade, shore, slope))
				_add(found, rng, flora, _weighted(rng, flora), center)
		"lone_root": ## the odd root vegetable out in the wild: nightbeets in deep shade, ember carrots toward the light
			if rng.randf() < 0.22 + 0.4 * shade:
				var root: String = "night_beet" if rng.randf() < 0.1 + 0.75 * wild else "ember_carrot"
				_add(found, rng, root, _weighted(rng, root), center)
		"birch_grove": ## drifts of moon birches in the open and at the light edge of woods, young ones around the old
			if w_wind < 0.34 and w_deep < 0.35 and w_past < 0.28 and rng.randf() < 0.16 + 0.4 * (1.0 - wild):
				_birch_grove(found, rng, center)
		"lone_birch":
			if w_wind < 0.34 and w_deep < 0.35 and w_past < 0.28 and rng.randf() < 0.08 + 0.12 * (1.0 - wild):
				_add(found, rng, "birch", _weighted(rng, "birch"), center, -0.4)
		"shroom_patch": ## glow morels and moon parasols in small groups, in the shade and on the edge of the birch drifts
			if w_wind < 0.50 and rng.randf() < (0.1 + 0.4 * shade) * (0.5 + damp) * (1.0 + 2.1 * w_deep):
				var shroom: String = "ember_morel" if rng.randf() < 0.55 else "moon_parasol"
				for _i: int in rng.randi_range(2, 5 + (3 if w_deep > 0.5 else 0)):
					_add(found, rng, shroom, _weighted(rng, shroom), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 3.5))
		"fairy_ring": ## rare: moon parasols standing in a perfect ring, with a glow cap in the middle
			if w_wind < 0.45 and rng.randf() < 0.2 + 0.25 * wild + 0.42 * w_deep:
				_fairy_ring(found, rng, center)
		"water_edge": ## the damp strip along rivers and lakes: marsh marigolds right at the water, irises a little back, mint further out
			var gap: float = _water_gap(center)
			if gap >= 6.0 and gap <= 120.0 and rng.randf() < 0.75 * (1.0 - 0.5 * smoothstep(20.0, 120.0, gap)):
				_water_edge(found, rng, center)
		"flora_patch":
			if rng.randf() < 0.5 * lush * (1.0 + 0.85 * w_wind + 0.45 * w_deep):
				_flora_patch(found, rng, center, shade, shore, slope)
		"bloom_drift": ## colour islands in the open meadow; in Windwiesen they expand into sweeping monoculture flower seas!
			var drift_chance: float = (0.78 - 0.58 * shade) * lush * (1.0 - 0.85 * smoothstep(0.25, 0.50, w_deep))
			if w_wind >= 0.35:
				drift_chance = maxf(drift_chance, lerpf(0.68, 0.96, w_wind))
			if shore < 0.5 and rng.randf() < drift_chance:
				_bloom_drift(found, rng, center, shade, damp, slope)
		"boulder_nook": ## a single big boulder with its own little garden round its foot: a landmark in a field
			if rng.randf() < (0.28 + 0.22 * shade + 0.2 * shore) * (1.0 - 0.55 * w_wind):
				_boulder_nook(found, rng, center, shade, shore, slope)
		"urforst_dome":
			if w_deep >= 0.32 and not is_bare(Vector2i(floori(center.x), floori(center.y))):
				_urforst_dome(found, rng, center, w_deep)
		"pasture_trace":
			if w_past >= 0.34 and not is_bare(Vector2i(floori(center.x), floori(center.y))):
				_pasture_trace(found, rng, center, w_past)
		"witch_wood", "witch_tree", "witch_flora", "witch_patch", "witch_ore":
			if is_witch(Vector2i(floori(center.x), floori(center.y))):
				_witch(String(layer.name), found, rng, center, wild)
		"lake_stones": ## Seeglimmer right at the waterline (it shows at night), Seemondstein further up the dry shore
			if is_witch(Vector2i(floori(center.x), floori(center.y))):
				_lake_stones(found, rng, center)
		"desert_garden", "desert_cactus", "desert_scrub", "desert_quartz", "desert_tuber", "oasis_palm", "oasis_flora", "desert_rock_cluster", "desert_rock_lone":
			if is_desert_bare(Vector2i(floori(center.x), floori(center.y))):
				_desert(String(layer.name), found, rng, center, wild)
	## Pure: a cluster depends only on its key, the seed and the static world inputs (set once before any chunk, and `_cache` is
	## cleared on terrain edits), so a cleared entry is simply computed again with the same result.
	if _cache.size() >= CACHE_LIMIT: _cache.clear()
	_cache[key] = found
	return found


func _grove(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float) -> void:
	var radius: float = rng.randf_range(8.0, 15.0) * (0.75 + 0.5 * wild)
	var wanted: int = clampi(int(radius), 5, 15)
	var trees: int = 0
	for _i: int in wanted * 12:
		if trees >= wanted:
			break
		var t: float = sqrt(rng.randf())
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * t
		var v: float = t + rng.randf() * 0.3
		var variant: int = ((3 if rng.randf() < 0.5 else 2) if v < 0.25 else (2 if v < 0.55 else (1 if v < 0.85 else 0)))
		if variant >= 2 and int(v * 1000.0) % 3 == 0:
			variant += 2
		var before: int = found.size()
		_add(found, rng, "tree", variant, at, 0.0, true, _young_for(at, t))
		trees += found.size() - before
	for _i: int in rng.randi_range(3, 7): ## undergrowth, mostly toward the edge
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.4, 1.15)
		var bush_kind: String = _berry_kind(at, "berry_bush") if rng.randf() < 0.22 else "bush"
		_add(found, rng, bush_kind, _weighted(rng, bush_kind), at)
	for _i: int in rng.randi_range(1, 3): ## glow caps between the trunks
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.2, 1.0)
		_add(found, rng, "mushroom", _weighted(rng, "mushroom"), at)


## A rock formation: a bed of gravel with one big rock, smaller ones around it and pebbles between.
## This is the only place stones lie in groups.
func _formation(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, ore: bool = false) -> void:
	var idx: int = rng.randi_range(1, BED_RX.size() - 1)
	var rx: float = BED_RX[idx] / 16.0 ## bed radius in tiles
	if is_bare(Vector2i(floori(center.x), floori(center.y))):
		return
	found.append({"cell": Vector2i(floori(center.x), floori(center.y)), "kind": "stonebed", "variant": idx, "pos": Vector2(floori(center.x), floori(center.y)) * 16.0 + Vector2(8, 8), "foot": 0.0, "crown": 0.0, "prio": -1.0})
	if not _bed_valid(center, rx):
		found.clear()
		return
	var big: int = BIG_ROCKS[rng.randi() % BIG_ROCKS.size()] if rng.randf() > 0.15 else 7
	if ore:
		_add(found, rng, "iron_rock", ORE_VARIANT[big], center)
	else:
		_add(found, rng, "rock", big, center)
	for i: int in rng.randi_range(2, 5):
		var at: Vector2 = center + _on_bed(rng, rx, 0.45, 0.8)
		var small: int = SMALL_ROCKS[rng.randi() % SMALL_ROCKS.size()]
		var percent: int = ORE_IN_ORE_FORMATION if ore else ORE_IN_FORMATION
		if absi(hash(Vector3i(floori(center.x), floori(center.y), 91 + i))) % 100 < percent:
			_add(found, rng, "iron_rock", ORE_VARIANT[small], at)
		else:
			_add(found, rng, "rock", small, at)
	for _i: int in rng.randi_range(7, 18):
		_add(found, rng, "pebble", _weighted(rng, "pebble"), center + _on_bed(rng, rx, 0.2, 0.95))


func _thicket(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	var radius: float = rng.randf_range(3.0, 6.5)
	for _i: int in 60:
		if found.size() >= 9:
			break
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
		var berries: bool = at.distance_to(center) < radius * 0.6 and rng.randf() < 0.3
		var kind: String = _berry_kind(at, "berry_bush") if berries else "bush"
		_add(found, rng, kind, _weighted(rng, kind), at)


## A patch of whisper grass: a handful of clumps close together, the tall ones toward the middle.
func _tussock(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	var radius: float = rng.randf_range(2.0, 4.5)
	for _i: int in rng.randi_range(4, 9):
		var t: float = sqrt(rng.randf())
		_add(found, rng, "grass", _weighted(rng, "grass"), center + Vector2.from_angle(rng.randf() * TAU) * radius * t)


## A big mixed wood: firs mostly, willows where it is wet (near the coast), blossom trees where it is open, with
## undergrowth. The tall trees stand in the middle, the small ones toward the edge.
func _wood(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	var w_deep: float = MeadowHabitats.deep_forest_at(center * 16.0)
	var radius: float = rng.randf_range(9.0, 14.0) * (0.8 + 0.4 * _wild(center) + 0.18 * w_deep)
	var wanted: int = clampi(int(radius * (1.5 + 0.35 * w_deep)), 12, 26)
	var planted: int = 0
	## A real clearing in most woods (a seeded stream of its own, so it never moves the trees): sunlit flowers in the middle of the trees.
	## Under the deep Urforst dome (`w_deep >= 0.42`), the canopy stays closed rather than breaking into sunny flower clearings.
	var open_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	open_rng.seed = hash(Vector3i(floori(center.x * 4.0), floori(center.y * 4.0), _seed + 911))
	var clearing: Vector3 = Vector3.ZERO ## x, y (tiles), z radius; 0 = no clearing
	if w_deep < 0.42 and open_rng.randf() < 0.65:
		var spot: Vector2 = center + Vector2.from_angle(open_rng.randf() * TAU) * radius * open_rng.randf_range(0.15, 0.55)
		clearing = Vector3(spot.x, spot.y, radius * open_rng.randf_range(0.2, 0.32))
	for _i: int in wanted * 10:
		if planted >= wanted:
			break
		var t: float = sqrt(rng.randf())
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * t
		var kind: String = "ancient_fir" if (w_deep >= 0.45 and t < 0.62 and rng.randf() < 0.38 * w_deep) else _tree_kind(rng, at)
		if clearing.z > 0.0 and at.distance_to(Vector2(clearing.x, clearing.y)) < clearing.z:
			continue
		var before: int = found.size()
		_add(found, rng, kind, _tree_variant(rng, kind, t), at, -1.0, true, _young_for(at, t) if kind == "tree" else -1)
		planted += found.size() - before
	if clearing.z > 0.0:
		for _i: int in open_rng.randi_range(4, 8):
			var at: Vector2 = Vector2(clearing.x, clearing.y) + Vector2.from_angle(open_rng.randf() * TAU) * clearing.z * sqrt(open_rng.randf())
			var flora: String = _flora_kind(open_rng, at, 0.1, 0.0)
			_add(found, open_rng, flora, _weighted(open_rng, flora), at)
	for _i: int in rng.randi_range(5, 10): ## undergrowth and glow caps, mostly toward the edge
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.3, 1.1)
		var roll: float = rng.randf()
		var kind: String = "glowfern" if (w_deep >= 0.40 and roll < 0.48) else ("mushroom" if roll < (0.68 if w_deep >= 0.40 else 0.25) else ("grass" if (w_deep < 0.38 and roll < 0.45) else ("ember_bush" if roll < 0.55 else "bush")))
		_add(found, rng, kind, _weighted(rng, kind), at, -1.0)


## Four to nine moon birches in a loose drift: a few tall old ones in the middle, slim young ones round them, glow caps and
## ferns at their feet. The tree sizes mix on purpose: a stand of birches is never even.
func _birch_grove(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	var radius: float = rng.randf_range(4.0, 8.0)
	var count: int = rng.randi_range(4, 9)
	for i: int in count * 8:
		if found.size() >= count:
			break
		var t: float = sqrt(rng.randf())
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * t
		var variant: int = _weighted(rng, "birch")
		if t < 0.4:
			variant = maxi(variant, rng.randi_range(2, 5))
		elif t > 0.75:
			variant = mini(variant, rng.randi_range(0, 2))
		_add(found, rng, "birch", variant, at, -0.4)
	for _i: int in rng.randi_range(1, 3):
		_add(found, rng, "mushroom", _weighted(rng, "mushroom"), center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.2, 1.1))


## Px from the water's edge to a point (tiles), INF when no water is near.
func _water_gap(at: Vector2) -> float:
	var best: float = INF
	if water_dist.is_valid():
		best = float(water_dist.call(at * 16.0))
	if best > 240.0 and BiomeBlend.arid_at(at * 16.0) >= 0.35:
		best = minf(best, BiomeBlend.lake_tiles_at(at) * 16.0)
	return best


## 0 far from the water .. 1 at its edge (within about 100 px).
func _near_water(at: Vector2) -> float:
	var gap: float = _water_gap(at)
	return 0.0 if gap == INF else 1.0 - smoothstep(8.0, 100.0, gap)


## The lake stones of one cell: 1-3 Seeglimmer where the water laps (4..26 px from it), or 1-2 Seemondsteine on the dry shore (34..110 px).
func _lake_stones(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	var gap: float = _water_gap(center)
	if gap == INF:
		return
	var kind: String = ""
	if gap <= 30.0 and rng.randf() < 0.45:
		kind = "lake_glimmer"
	elif gap >= 30.0 and gap <= 110.0 and rng.randf() < 0.22:
		kind = "lake_moonstone"
	if kind.is_empty():
		return
	for _i: int in rng.randi_range(1, 3 if kind == "lake_glimmer" else 2):
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 1.4)
		var spot: float = _water_gap(at)
		if (kind == "lake_glimmer" and spot >= 4.0 and spot <= 26.0) or (kind == "lake_moonstone" and spot >= 34.0 and spot <= 110.0):
			_add(found, rng, kind, _weighted(rng, kind), at, -1.0)


## A clump of one waterside plant, 2-5 plants, each checked against the water again: marsh gold close, iris in the middle, mint far.
func _water_edge(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	var gap: float = _water_gap(center)
	var weights: PackedFloat32Array = PackedFloat32Array([3.5 * (1.0 - smoothstep(14.0, 64.0, gap)) + 0.1, 3.2 * smoothstep(6.0, 16.0, gap) * (1.0 - smoothstep(60.0, 100.0, gap)) + 0.1, 0.3 + 2.0 * smoothstep(18.0, 44.0, gap)])
	var kind: String = ["marsh_gold", "moon_iris", "brook_mint"][rng.rand_weighted(weights)]
	for _i: int in rng.randi_range(3, 6):
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 2.2)
		var spot: float = _water_gap(at)
		if spot >= 5.0 and spot <= 125.0:
			_add(found, rng, kind, _weighted(rng, kind), at)


## Seven to ten moon parasols in a ring 2.5-4 tiles wide, evenly spaced: the old story of the meadow, here it is just true.
func _fairy_ring(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	var radius: float = rng.randf_range(2.5, 4.0)
	var count: int = rng.randi_range(7, 10)
	var turn: float = rng.randf() * TAU
	for i: int in count:
		_add(found, rng, "moon_parasol", rng.randi_range(0, 2), center + Vector2.from_angle(turn + TAU * float(i) / float(count)) * radius)
	_add(found, rng, "mushroom", 3, center)


## Two to four trees together, in a mix that fits the ground.
func _copse(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	for _i: int in rng.randi_range(2, 4):
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 3.5)
		var kind: String = _tree_kind(rng, at)
		_add(found, rng, kind, _tree_variant(rng, kind, rng.randf()), at, -1.0)


## A sapling or young fir at this spot (age 0..3, else -1): 2-18 % of the trees (about 13 % on average), more toward the edge of a wood (`t` 0 middle .. 1 rim) where
## the old trees leave light. Decided from the position alone, so no random stream moves.
func _young_for(at: Vector2, t: float) -> int:
	var roll: int = absi(hash(Vector2i(floori(at.x * 5.0), floori(at.y * 5.0)))) % 1000
	return roll % 4 if float(roll) < (0.02 + 0.16 * t) * 1000.0 else -1


## Which litter patch lies under a tree: the nearest size to 1.35 x its crown (px).
func _bed_index(crown: float) -> int:
	var best: int = 0
	for i: int in FOREST_BED_RX.size():
		if absf(FOREST_BED_RX[i] - crown * 1.35) < absf(FOREST_BED_RX[best] - crown * 1.35):
			best = i
	return best


## -1 north-facing slope or the foot of a cliff (shade, damp) .. +1 south-facing slope (sun, dry), 0 level. `at` in tiles.
func aspect(at: Vector2) -> float:
	var px: Vector2 = at * 16.0
	var slope: float = clampf((_relief.level_at(px + Vector2(0, -48)) - _relief.level_at(px + Vector2(0, 48))) * 1.2, -1.0, 1.0) ## ground rising to the north looks south
	if _relief.wall_above(Vector2i(floori(at.x), floori(at.y))):
		slope = minf(slope, -0.7) ## the foot of a wall lies in its shadow
	return slope


## 0 dry .. 1 damp ground at `at` (tiles): north slopes and cliff feet, the water's edge and low ground are damp; sunny slopes and
## high ground are dry (docs/plant_life.md). Pure, so every peer and every chunk agrees.
func damp_at(at: Vector2, slope: float = INF) -> float: ## `slope` = aspect(at) when the caller has it already
	var near: float = _near_water(at)
	var height: float = _relief.level_at(at * 16.0)
	var variation: float = _zone.get_noise_2d(at.x * 0.6 + 311.0, at.y * 0.6 - 97.0) * 0.12
	return clampf(0.42 - 0.34 * (aspect(at) if slope == INF else slope) + 0.4 * near - 0.1 * height + variation, 0.0, 1.0)


## Which tree grows at `at`: willows on wet ground near the coast, blossom trees in the open (never in the deep Urforst), else firs.
func _tree_kind(rng: RandomNumberGenerator, at: Vector2) -> String:
	var roll: float = rng.randf()
	if _shore(at) > 0.35 and roll < 0.3:
		return "willow"
	if _wild(at) < 0.45 and MeadowHabitats.deep_forest_at(at * 16.0) < 0.25 and roll > 0.72:
		return "blossom"
	return "tree"


## A size for a tree `t` of the way from the middle of its wood (0) to the edge (1): tall in the middle.
func _tree_variant(rng: RandomNumberGenerator, kind: String, t: float) -> int:
	if kind == "ancient_fir":
		return 2 if t < 0.35 else (1 if t < 0.72 else 0)
	if kind != "tree":
		return _weighted(rng, kind)
	var v: float = t + rng.randf() * 0.3
	var base: int = (3 if rng.randf() < 0.5 else 2) if v < 0.25 else (2 if v < 0.55 else (1 if v < 0.85 else 0))
	if base >= 2 and int(v * 1000.0) % 3 == 0:
		return base + 2
	return base


## One to three willows with glow caps between their roots.
func _willow_stand(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	for _i: int in rng.randi_range(1, 3):
		_add(found, rng, "willow", _weighted(rng, "willow"), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 6.0))
	for _i: int in rng.randi_range(1, 3):
		_add(found, rng, "mushroom", _weighted(rng, "mushroom"), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 6.5))


## A little orchard: three to six blossom trees with patches of grass between them.
func _orchard(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2) -> void:
	for _i: int in rng.randi_range(3, 6):
		_add(found, rng, "blossom", _weighted(rng, "blossom"), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 7.0))
	for _i: int in rng.randi_range(1, 2):
		_tussock(found, rng, center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, 7.0))


## A drift of flowers: 12-20 plants of one kind in a stretched, tilted oval 3.5-7 tiles long with a few of another kind among them (the main kind follows the
## ground: sun flowers and poppies in the open and on sunny slopes, moonbells and lilies in the shade and the damp) and some tufts of grass between.
## Flora yields to everything woody and stony (priority), so a drift simply has a hole where a bush stands. Small colour islands, never a carpet.
func _bloom_drift(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float, damp: float, slope: float) -> void:
	var w_wind: float = MeadowHabitats.wind_meadow_at(center * 16.0)
	var open: float = 1.0 - wild
	var kinds: Array[String] = ["sunbloom", "spark_poppy", "puffseed", "moonbell", "mist_lily"]
	var weights: PackedFloat32Array = PackedFloat32Array([0.3 + 2.5 * open + 1.2 * maxf(slope, 0.0), 0.3 + 2.4 * open, 0.2 + 1.2 * open, 0.4 + 2.2 * wild, 0.2 + 1.6 * wild + 1.6 * damp])
	var main: String = MeadowHabitats.wind_flower_at(center) if w_wind >= 0.36 else kinds[rng.rand_weighted(weights)]
	var accent: String = kinds[rng.randi() % kinds.size()]
	if accent == main:
		accent = "puffseed" if main != "puffseed" else "sunbloom"
	var sea: bool = w_wind >= 0.38
	var radius: float = rng.randf_range(5.5, 9.2) if sea else rng.randf_range(3.5, 7.0)
	var turn: float = rng.randf() * PI
	var stretch: float = rng.randf_range(0.58, 0.92) if sea else rng.randf_range(0.45, 0.8)
	var plant_count: int = rng.randi_range(26, 44) if sea else rng.randi_range(12, 20)
	var accent_chance: float = 0.08 if sea else 0.22
	for _i: int in plant_count:
		var angle: float = rng.randf() * TAU
		var reach: float = sqrt(rng.randf())
		var local: Vector2 = Vector2(cos(angle) * radius * reach, sin(angle) * radius * stretch * reach).rotated(turn)
		var kind: String = accent if rng.randf() < accent_chance else main
		_add(found, rng, kind, _weighted(rng, kind), center + local)
	for _i: int in rng.randi_range(4 if sea else 2, 8 if sea else 5):
		var angle: float = rng.randf() * TAU
		var reach: float = sqrt(rng.randf())
		_add(found, rng, "grass", _weighted(rng, "grass"), center + Vector2(cos(angle) * radius * reach, sin(angle) * radius * stretch * reach).rotated(turn))


## One big boulder with a garden at its foot: tufts, flowers that fit the ground, a toadstool in the shade, pebbles and a bush now and then.
func _boulder_nook(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float, shore: float, slope: float) -> void:
	_add(found, rng, "rock", BIG_ROCKS[rng.randi() % BIG_ROCKS.size()], center)
	if found.is_empty():
		return
	_skirt(found, rng, center, wild, shore, slope, 1.8, 4.5, rng.randi_range(6, 10), true)


## Small plants round a prop at `center` (`inner` / `outer` in tiles): grass, flowers for this ground, glow caps in the shade, bushes now and then
## (and pebbles at a boulder). Every candidate is checked against everything already found, so the skirt only lives where there is room.
func _skirt(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float, shore: float, slope: float, inner: float, outer: float, count: int, stony: bool = false) -> void:
	for _i: int in count:
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(inner, outer)
		var roll: float = rng.randf()
		if roll < 0.34:
			_add(found, rng, "grass", _weighted(rng, "grass"), at)
		elif roll < 0.68:
			var flora: String = _flora_kind(rng, at, wild, shore, slope)
			_add(found, rng, flora, _weighted(rng, flora), at)
		elif roll < 0.80 and wild > 0.25:
			_add(found, rng, "mushroom", _weighted(rng, "mushroom"), at)
		elif roll < 0.90 and stony:
			_add(found, rng, "pebble", _weighted(rng, "pebble"), at)
		elif roll < 0.95:
			_add(found, rng, "bush", _weighted(rng, "bush"), at)
		else:
			_add(found, rng, "grass", _weighted(rng, "grass"), at)


## The small plants of the meadow: which one grows at `at`. Open ground likes plantain, seed heads and sun flowers, shade
## likes moonbells and glow ferns, the wet shore has cattails, and the first tiles of land at the void's edge hold the odd void bloom.
func _flora_kind(rng: RandomNumberGenerator, at: Vector2, wild: float, shore: float, slope: float = 0.0) -> String:
	var open: float = 1.0 - wild
	var edge: float = 1.0 - smoothstep(4.0, 10.0, _coast(at))
	var kinds: Array[String] = ["moonbell", "wound_leaf", "puffseed", "glowfern", "cattail", "sunbloom", "voidbloom", "earth_tuber", "mist_lily", "spark_poppy"]
	var near: float = _near_water(at)
	var weights: PackedFloat32Array = PackedFloat32Array([1.2 + 2.6 * wild + 1.0 * near, 0.7 + 2.2 * open + 0.8 * wild, 0.3 + 2.8 * open * (1.0 - 0.7 * near), 3.0 * wild + 1.0 * near, 5.0 * shore + 7.0 * near, (0.2 + 2.0 * open) * (1.0 + 1.6 * maxf(slope, 0.0)), 0.9 * edge, 0.1 + 1.0 * open, 0.2 + 2.2 * wild + 2.0 * shore + 2.5 * near, 0.2 + 2.6 * open * (1.0 - 0.5 * near)])
	return kinds[rng.rand_weighted(weights)]


## A patch of one kind: a drift of moonbells in the shade, a field of sun flowers, a reed bed on the shore, a bank of ferns.
func _flora_patch(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float, shore: float, slope: float = 0.0) -> void:
	var w_deep: float = MeadowHabitats.deep_forest_at(center * 16.0)
	var w_wind: float = MeadowHabitats.wind_meadow_at(center * 16.0)
	var kind: String = "cattail" if shore > 0.35 else _flora_kind(rng, center, wild, shore * 0.0, slope)
	if shore <= 0.35 and w_deep >= 0.38 and rng.randf() < 0.84:
		kind = "glowfern"
	elif shore <= 0.35 and w_wind >= 0.38 and rng.randf() < 0.90:
		kind = MeadowHabitats.wind_flower_at(center)
	if _coast(center) < 12.0 and rng.randf() < 0.5: ## the void's edge: dark, pulsing blooms
		kind = "voidbloom"
	var radius: float = rng.randf_range(2.0, 5.0)
	var count: int = rng.randi_range(4, 9)
	match kind:
		"sunbloom":
			radius += 1.5 + 2.2 * w_wind
			count += 3 + int(roundf(10.0 * w_wind))
		"voidbloom":
			count = rng.randi_range(2, 4)
		"earth_tuber":
			count = rng.randi_range(3, 6)
		"spark_poppy": ## a poppy field
			radius += 1.0 + 2.2 * w_wind
			count += 3 + int(roundf(10.0 * w_wind))
		"moonbell", "puffseed":
			radius += 2.0 * w_wind
			count += int(roundf(9.0 * w_wind))
		"glowfern": ## fern sea under the Urforst dome!
			radius += 2.4 * w_deep
			count += int(roundf(11.0 * w_deep))
		"mist_lily": ## a carpet of lilies under the shade, mostly near the damp shore
			count = rng.randi_range(3, 7)
	for _i: int in count:
		_add(found, rng, kind, _weighted(rng, kind), center + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf()))


## Der Tiefe Urforst (Dunkeltannen-Dom): cathedral stand of giant double-wide `ancient_fir` with moss carpets, fern seas and mushroom rings.
func _urforst_dome(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, w_deep: float) -> void:
	if rng.randf() > 0.84 + 0.16 * w_deep:
		return
	var radius: float = rng.randf_range(6.5, 11.0) * (0.85 + 0.30 * w_deep)
	# Soft mossy forest floor carpets beneath the cathedral firs
	for _m: int in rng.randi_range(2, 4):
		var m_at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.0, 0.75)
		var m_cell: Vector2i = Vector2i(floori(m_at.x), floori(m_at.y))
		if not is_bare(m_cell) and not blocked_cells.has(m_cell) and not _exclude.has_point(m_cell):
			var m_pos: Vector2 = m_cell * 16 + Vector2i(8, 8)
			if _relief.flat_around(Vector2(m_pos), 36.0):
				found.append({
					"cell": m_cell,
					"kind": "moss_carpet",
					"variant": rng.randi() % 4,
					"pos": Vector2(m_pos),
					"foot": 0.0,
					"crown": 0.0,
					"prio": -1.0,
				})
	var wanted_giants: int = clampi(int(roundf(lerpf(5.0, 11.0, w_deep))), 5, 12)
	var giants: int = 0
	for _i: int in wanted_giants * 12:
		if giants >= wanted_giants:
			break
		var t: float = sqrt(rng.randf())
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * t
		var variant: int = 2 if (t < 0.42 and rng.randf() < 0.75) else (1 if t < 0.78 else 0)
		var before: int = found.size()
		_add(found, rng, "ancient_fir", variant, at, 0.2, true)
		giants += found.size() - before
	# Standard tall firs weaving between the giant ancient firs so the dome closes tightly
	var wanted_sub: int = rng.randi_range(2, 5)
	var subs: int = 0
	for _j: int in wanted_sub * 8:
		if subs >= wanted_sub:
			break
		var t2: float = rng.randf_range(0.35, 1.05)
		var at2: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * t2
		var before2: int = found.size()
		_add(found, rng, "tree", rng.randi_range(2, 5), at2, -0.2, true)
		subs += found.size() - before2
	# Fern sea & shade mushrooms between the buttress roots (almost zero grass or meadow flowers)
	for _k: int in rng.randi_range(8, 16):
		var at3: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.15, 1.08)
		var r3: float = rng.randf()
		var under: String = "glowfern" if r3 < 0.62 else ("mushroom" if r3 < 0.84 else ("moon_parasol" if r3 < 0.94 else "ember_morel"))
		_add(found, rng, under, _weighted(rng, under), at3)


## Alte Kulturspuren (Verlassenes Weideland): former rows of `orchard_apple` / `orchard_pear`, low mossy `dry_stone_wall` field borders,
## weathered `broken_fence` runs, and grass-sunken `pasture_paving` flagstones.
func _pasture_trace(found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, w_past: float) -> void:
	if rng.randf() > 0.66 + 0.28 * w_past:
		return
	var roll_type: float = rng.randf()
	# Sunken flagstone path remnants (`pasture_paving`) leading into the old farmstead / orchard
	var pav_dir: Vector2 = Vector2.RIGHT if rng.randf() < 0.55 else Vector2.DOWN
	var pav_count: int = rng.randi_range(2, 4)
	var pav_base: Vector2 = center + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
	for pi: int in pav_count:
		var p_at: Vector2 = pav_base + pav_dir * float(pi) * 3.2 + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
		var p_cell: Vector2i = Vector2i(floori(p_at.x), floori(p_at.y))
		if not is_bare(p_cell) and not blocked_cells.has(p_cell) and not _exclude.has_point(p_cell):
			var p_pos: Vector2 = Vector2(p_cell) * 16.0 + Vector2(8.0, 8.0)
			if _relief.flat_around(p_pos, 26.0):
				found.append({
					"cell": p_cell,
					"kind": "pasture_paving",
					"variant": rng.randi() % 4,
					"pos": p_pos,
					"foot": 0.0,
					"crown": 0.0,
					"prio": -1.0,
				})

	if roll_type < 0.58:
		# Overgrown orchard in recognizable former grid rows (2x3 or 3x3, with 1-2 trees missing to time)
		var main_fruit: String = "orchard_apple" if rng.randf() < 0.58 else "orchard_pear"
		var alt_fruit: String = "orchard_pear" if main_fruit == "orchard_apple" else "orchard_apple"
		var cols: int = 3
		var rows: int = 2 if rng.randf() < 0.55 else 3
		var step_x: float = 4.5
		var step_y: float = 4.2
		for ry: int in rows:
			for rx_i: int in cols:
				if rng.randf() < 0.22:
					continue ## missing old tree in the row!
				var grid_off: Vector2 = Vector2((float(rx_i) - float(cols - 1) * 0.5) * step_x, (float(ry) - float(rows - 1) * 0.5) * step_y)
				var jitter: Vector2 = Vector2(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.25, 0.25))
				var t_kind: String = alt_fruit if rng.randf() < 0.20 else main_fruit
				_add(found, rng, t_kind, _weighted(rng, t_kind), center + grid_off + jitter, 0.15)
		# Border segment of low dry-stone wall or weathered wooden fence along the orchard edge
		var border_y: float = (float(rows) * 0.5 + 0.65) * step_y * (1.0 if rng.randf() < 0.5 else -1.0)
		var use_wall: bool = rng.randf() < 0.62
		for bx: int in range(-2, 3):
			if bx == 0 and rng.randf() < 0.75:
				continue ## walk-through gap / collapsed gate
			var b_at: Vector2 = center + Vector2(float(bx) * 2.3, border_y)
			if use_wall:
				var w_var: int = 2 if abs(bx) == 2 else (rng.randi_range(0, 1) if rng.randf() < 0.7 else 5)
				_add(found, rng, "dry_stone_wall", w_var, b_at, 0.1)
			else:
				var f_var: int = rng.randi_range(0, 2)
				_add(found, rng, "broken_fence", f_var, b_at, 0.1)
	else:
		# Abandoned pasture enclosure: L-shaped dry-stone wall + decayed wooden fence corner + stray heritage fruit tree
		var sx: float = 1.0 if rng.randf() < 0.5 else -1.0
		var sy: float = 1.0 if rng.randf() < 0.5 else -1.0
		_add(found, rng, "dry_stone_wall", 4, center + Vector2(sx * 4.2, sy * 3.6), 0.15) ## mossy corner
		for ix: int in range(1, 4):
			if ix == 2 and rng.randf() < 0.45:
				_add(found, rng, "dry_stone_wall", 2, center + Vector2(sx * (4.2 - float(ix) * 2.2), sy * 3.6), 0.12) ## tumbled gap
			else:
				_add(found, rng, "dry_stone_wall", rng.randi_range(0, 1), center + Vector2(sx * (4.2 - float(ix) * 2.2), sy * 3.6), 0.12)
		for iy: int in range(1, 3):
			_add(found, rng, "dry_stone_wall", 3, center + Vector2(sx * 4.2, sy * (3.6 - float(iy) * 2.1)), 0.12)
		# Opposite side: broken wooden pasture fence
		for fx_i: int in range(-1, 3):
			if fx_i == 1:
				continue
			_add(found, rng, "broken_fence", rng.randi_range(0, 4), center + Vector2(-sx * 3.6 + float(fx_i) * 1.9, -sy * 3.2), 0.1)
		if rng.randf() < 0.72:
			var lone_fruit: String = "orchard_apple" if rng.randf() < 0.55 else "orchard_pear"
			_add(found, rng, lone_fruit, _weighted(rng, lone_fruit), center + Vector2(-sx * 1.2, sy * 0.6), 0.15)
	# Wild clover/grass tufts reclaiming the old pasture
	for _g: int in rng.randi_range(3, 6):
		var g_at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 6.5)
		_add(found, rng, "grass", _weighted(rng, "grass"), g_at)


## Tiles from the coast (negative never happens on land).
## A meadow bush that falls into the Hexenwald: along the fringe (BiomeBlend below 0.45) some stay meadow bushes, so the border is a seam and
## not a line; deeper in it is always one of the wood's own: three Dämmersträucher to two Besenginster. Decided by position, no random draw.
func _hex_bush(cell: Vector2i) -> String:
	var roll: int = absi(hash(Vector2i(cell.x * 7, cell.y * 13))) % 100
	if float(roll) / 100.0 > BiomeBlend.amount_at(Vector2(cell) * 16.0 + Vector2(8, 8)) / 0.45:
		return "bush"
	return "hex_shrub" if roll % 5 < 3 else "witch_broom"


## True within a clearing of the Hexenwald: some witch_wood cells carry no wood but a ring (see `_witch`); their middle is a pure function of
## the cell, so every layer can ask (trees and bushes keep out, flowers may grow there).
func _in_clearing(at: Vector2) -> bool:
	var size: float = 22.0
	var cc: Vector2i = Vector2i(floori(at.x / size), floori(at.y / size))
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var middle: Vector2 = _clearing_middle(cc + Vector2i(dx, dy))
			if middle.is_finite() and at.distance_to(middle) < WITCH_CLEARING_R:
				return true
	return false


## The middle of the clearing in witch_wood cell `cc`, INF when that cell is a wood.
func _clearing_middle(cc: Vector2i) -> Vector2:
	var h: int = absi(hash(Vector3i(cc.x, cc.y, _seed + 4421)))
	if h % 100 >= WITCH_CLEARING:
		return Vector2.INF
	return (Vector2(cc) + Vector2(0.3 + float(h / 100 % 40) / 100.0, 0.3 + float(h / 4000 % 40) / 100.0)) * 22.0


## The Hexenwald's plant world (data/plants.json WITCH_KINDS): close, dark woods of Hexenulmen with a Bleichbaum or two at
## their edge and thorn hedges, ghost ferns and toadstools between the trunks; lone trees; flowers in the gaps (grave candles
## and witch hats in the open, toadstools and ferns in the shade, a rare mandrake); rings and drifts of one kind; cursed silver.
func _witch(layer: String, found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float) -> void:
	match layer:
		"witch_wood":
			var cc: Vector2i = Vector2i(floori(center.x / 22.0), floori(center.y / 22.0))
			var middle: Vector2 = _clearing_middle(cc)
			if middle.is_finite(): ## a clearing: grass, a witches' ring, flowers at its rim, a mandrake in the middle now and then
				var ring_kind: String = ["toad_cap", "grave_candle", "witch_hat", "toad_cap"][rng.randi() % 4]
				var count: int = rng.randi_range(7, 10)
				var start: float = rng.randf() * TAU
				var r: float = rng.randf_range(2.6, 3.6)
				for i: int in count:
					_add(found, rng, ring_kind, 0, middle + Vector2.from_angle(start + TAU * float(i) / float(count)) * Vector2(r, r * 0.8))
				if rng.randf() < 0.55:
					_add(found, rng, "mandrake", _weighted(rng, "mandrake"), middle)
				for _i: int in rng.randi_range(6, 11): ## flowers and ferns where the wood begins
					var at: Vector2 = middle + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5.0, 7.5)
					var rim: String = ["witch_hat", "grave_candle", "ghost_fern", "ghost_fern", "toad_cap"][rng.randi() % 5]
					_add(found, rng, rim, _weighted(rng, rim), at)
				return
			if rng.randf() > 0.86 + 0.3 * wild: ## nearly every cell carries a wood (was 0.68 + 0.3 * wild): the Hexenwald is full
				return
			var radius: float = rng.randf_range(6.0, 11.0)
			var wanted: int = clampi(int(radius * 1.2), 6, 13)
			var trees: int = 0
			for _i: int in wanted * 12:
				if trees >= wanted:
					break
				var t: float = sqrt(rng.randf())
				var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * t
				var dead: bool = rng.randf() < 0.08 + 0.3 * t * t ## the dead ones stand at the edge
				var kind: String = "bone_tree" if dead else "hag_tree"
				var before: int = found.size()
				_add(found, rng, kind, _weighted(rng, kind) if dead else (3 if t < 0.25 and rng.randf() < 0.5 else (2 if t < 0.5 else (1 if t < 0.8 else 0))), at, 0.0, true)
				if found.size() > before:
					if found[-1].has("bed"): ## the Hexenwald's own floor under them (row 1 of forestbed.png: variants 6-11)
						found[-1]["bed"] = int(found[-1].bed) % FOREST_BED_RX.size() + FOREST_BED_RX.size()
					trees += 1
			for _i: int in rng.randi_range(10, 17):
				var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.2, 1.2)
				var under: String = ["thorn_hedge", "ghost_fern", "ghost_fern", "toad_cap", "bush", "bush", "witch_hat", "grave_candle", "ghost_fern"][rng.randi() % 9]
				_add(found, rng, under, _weighted(rng, under), at)
		"witch_tree":
			if rng.randf() < 0.6 + 0.2 * wild:
				var kind: String = "bone_tree" if rng.randf() < 0.4 else "hag_tree"
				_add(found, rng, kind, [0, 0, 1, 1, 2][rng.randi() % 5], center)
		"witch_flora":
			if rng.randf() < 0.85:
				var roll: float = rng.randf()
				var kind: String = "mandrake" if roll < 0.04 else ("bush" if roll < 0.2 else "thorn_hedge" if roll < 0.28 else (["ghost_fern", "toad_cap"][rng.randi() % 2] if rng.randf() < 0.25 + 0.6 * wild else ["grave_candle", "witch_hat"][rng.randi() % 2]))
				_add(found, rng, kind, _weighted(rng, kind), center)
				if kind != "bush" and kind != "thorn_hedge" and rng.randf() < 0.5: ## small plants come in twos and threes
					for _i: int in rng.randi_range(1, 2):
						_add(found, rng, kind, _weighted(rng, kind), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 1.8))
		"witch_patch":
			if rng.randf() < 0.75:
				var kind: String = ["grave_candle", "witch_hat", "toad_cap", "ghost_fern", "thorn_hedge", "bush"][rng.randi() % 6]
				var ring: bool = (kind == "toad_cap" or kind == "grave_candle") and rng.randf() < 0.4 ## a witches' ring
				var count: int = rng.randi_range(5, 8) if ring else rng.randi_range(3, 6)
				var start: float = rng.randf() * TAU
				for i: int in count:
					var at: Vector2 = center + (Vector2.from_angle(start + TAU * float(i) / float(count)) * 2.6 if ring else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 3.6))
					_add(found, rng, kind, 0 if ring else _weighted(rng, kind), at)
				if ring and rng.randf() < 0.5:
					_add(found, rng, "mandrake", _weighted(rng, "mandrake"), center)
		"witch_ore":
			if rng.randf() < 0.3:
				_add(found, rng, "curse_rock", _weighted(rng, "curse_rock"), center)


## Cliff/mesa shelter in Sonnenquarz-Öde: 1.0 directly at the foot of a wall face, 0.75 beside a higher plateau or cliff edge, 0.0 open dune.
func _cliff_shelter(tile: Vector2i) -> float:
	if _relief.wall_above(tile):
		return 1.0
	var base_lvl: int = _relief.level(tile.x, tile.y)
	for off: Vector2i in [Vector2i(0, -3), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, 3)]:
		var nx: int = tile.x + off.x
		var ny: int = tile.y + off.y
		if _relief.kind(nx, ny) == Relief.FACE or _relief.level(nx, ny) > base_lvl:
			return 0.75
	return 0.0


## Classification of white quartz outcrops at `pos` (px):
## 3 = deep crystal interior (only `sun_quartz_rock` may emerge here), 2 = outer quartz edge (`sun_quartz_rock` & `glass_aloe`),
## 1 = sand rim directly beside quartz (`glass_aloe` & `night_cactus`), 0 = open dune sand.
func _quartz_rim(pos: Vector2) -> int:
	var on_q: bool = BiomeBlend.is_quartz_surface(pos)
	var q_neighbors: int = 0
	for d: Vector2 in [Vector2(22.0, 0.0), Vector2(-22.0, 0.0), Vector2(0.0, 22.0), Vector2(0.0, -22.0)]:
		if BiomeBlend.is_quartz_surface(pos + d):
			q_neighbors += 1
	if on_q:
		return 3 if q_neighbors == 4 else 2
	return 1 if q_neighbors > 0 else 0


## True only when the entire basal crystal skirt of `sun_quartz_rock` `variant` sits inside an open white ground-quartz outcrop.
func _quartz_rock_fits(pos_px: Vector2, variant: int) -> bool:
	if BiomeBlend.arid_at(pos_px) < 0.72 or BiomeBlend.oasis_at(pos_px) >= 0.08:
		return false
	var hw: float = QUARTZ_ROCK_BASE_HW[clampi(variant, 0, QUARTZ_ROCK_BASE_HW.size() - 1)]
	for off: Vector2 in [
		Vector2.ZERO,
		Vector2(0.0, -3.0),
		Vector2(0.0, 1.0),
		Vector2(-hw, -2.0),
		Vector2(hw, -2.0),
		Vector2(-hw * 0.5, -1.0),
		Vector2(hw * 0.5, -1.0),
		Vector2(-hw * 0.85, 0.0),
		Vector2(hw * 0.85, 0.0),
	]:
		if not BiomeBlend.is_quartz_surface(pos_px + off):
			return false
	return true


## True only when the entire basal crystal skirt of `prism_vein` `variant` sits inside an open white ground-quartz outcrop in deep desert.
func _prism_vein_fits(pos_px: Vector2, variant: int) -> bool:
	if BiomeBlend.arid_at(pos_px) < 0.75 or BiomeBlend.oasis_at(pos_px) >= 0.06:
		return false
	var hw: float = PRISM_VEIN_BASE_HW[clampi(variant, 0, PRISM_VEIN_BASE_HW.size() - 1)]
	for off: Vector2 in [
		Vector2.ZERO,
		Vector2(0.0, -3.0),
		Vector2(0.0, 1.0),
		Vector2(-hw, -2.0),
		Vector2(hw, -2.0),
		Vector2(-hw * 0.5, -1.0),
		Vector2(hw * 0.5, -1.0),
		Vector2(-hw * 0.85, 0.0),
		Vector2(hw * 0.85, 0.0),
	]:
		if not BiomeBlend.is_quartz_surface(pos_px + off):
			return false
	return true


## Picks a `sun_quartz_rock` variant whose basal footprint fits cleanly inside the ground quartz at `pos_px`, or -1 if none fits.
func _pick_quartz_rock_variant(rng: RandomNumberGenerator, pos_px: Vector2, prefer_big: bool) -> int:
	if not BiomeBlend.is_quartz_surface(pos_px):
		return -1
	if prefer_big:
		var big_pool: Array[int] = [2, 4, 5, 1]
		var start: int = rng.randi() % big_pool.size()
		for i: int in big_pool.size():
			var v: int = big_pool[(start + i) % big_pool.size()]
			if _quartz_rock_fits(pos_px, v):
				return v
	else:
		var wv: int = _weighted(rng, "sun_quartz_rock")
		if _quartz_rock_fits(pos_px, wv):
			return wv
	for v_small: int in [5, 1, 0, 3]:
		if _quartz_rock_fits(pos_px, v_small):
			return v_small
	return -1


## Position-hashed transition for surviving meadow bushes & grass in the outer desert fringe (`arid < 0.35`, zero RNG calls).
func _desert_shared_kind(cell: Vector2i, kind: String, arid: float) -> String:
	var roll: int = absi(hash(Vector2i(cell.x * 13 + 5, cell.y * 19 + 11))) % 100
	if float(roll) / 100.0 < smoothstep(0.10, 0.35, arid) * 0.55:
		return ""
	if kind == "bush":
		if arid < 0.22 and float(roll % 50) / 50.0 > arid / 0.22:
			return "bush"
		return "desert_scrub" if roll % 5 < 3 else "tumble_scrub"
	if arid < 0.18 and float(roll % 50) / 50.0 > arid / 0.18:
		return "grass"
	return "dune_grass"


## Sonnenquarz-Öde's sparse three-zone flora ecology (`DESERT_KINDS`): leaves ~85%+ of open dune sand bare and keeps quartz centers clear.
func _desert(layer: String, found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float) -> void:
	var tile: Vector2i = Vector2i(floori(center.x), floori(center.y))
	var pos_px: Vector2 = center * 16.0 + Vector2(8.0, 8.0)
	var arid: float = BiomeBlend.arid_at(pos_px)
	var oasis: float = BiomeBlend.oasis_at(pos_px)
	var lake_d: float = BiomeBlend.lake_tiles_at(pos_px)
	var shelter: float = _cliff_shelter(tile)
	match layer:
		"desert_garden":
			if arid < 0.34 or oasis > 0.45:
				return
			if rng.randf() >= (0.74 if shelter > 0.5 else 0.24 + 0.28 * wild):
				return
			var crowns: int = rng.randi_range(1, 3)
			for i: int in crowns:
				var t: float = sqrt(rng.randf())
				var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 2.8) * t
				var v: int = 4 if t < 0.35 and rng.randf() < 0.55 else (3 if t < 0.55 else (2 if t < 0.8 else _weighted(rng, "crown_cactus")))
				_add(found, rng, "crown_cactus", mini(v, 4), at)
			var mates: Array[String] = ["prickly_pear", "prickly_pear", "barrel_cactus", "barrel_cactus", "desert_scrub", "tumble_scrub", "dune_grass"]
			for _i: int in rng.randi_range(4, 7):
				var kind: String = mates[rng.randi() % mates.size()]
				var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.8, 5.2)
				_add(found, rng, kind, _weighted(rng, kind), at)
			if arid >= 0.55 and rng.randf() < 0.4:
				var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.8, 3.6)
				_add(found, rng, "night_cactus", _weighted(rng, "night_cactus"), at)
		"desert_cactus":
			if arid < 0.26 or oasis > 0.50:
				return
			if rng.randf() < 0.34 + 0.32 * shelter + 0.14 * wild:
				var r: float = rng.randf()
				if arid >= 0.44 and r < 0.28:
					_add(found, rng, "crown_cactus", _weighted(rng, "crown_cactus"), center)
					if rng.randf() < 0.55:
						var sub: String = ["barrel_cactus", "prickly_pear", "desert_scrub"][rng.randi() % 3]
						_add(found, rng, sub, _weighted(rng, sub), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.6, 2.8))
				elif r < 0.66:
					_add(found, rng, "prickly_pear", _weighted(rng, "prickly_pear"), center)
					if rng.randf() < 0.50:
						for _i: int in rng.randi_range(1, 2):
							var sub: String = ["prickly_pear", "barrel_cactus", "desert_scrub"][rng.randi() % 3]
							_add(found, rng, sub, _weighted(rng, sub), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 2.6))
				else:
					_add(found, rng, "barrel_cactus", _weighted(rng, "barrel_cactus"), center)
					if rng.randf() < 0.45:
						for _i: int in rng.randi_range(1, 2):
							var sub: String = ["barrel_cactus", "tumble_scrub", "desert_scrub"][rng.randi() % 3]
							_add(found, rng, sub, _weighted(rng, sub), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.3, 2.4))
		"desert_scrub":
			if arid < 0.12 or oasis > 0.65:
				return
			var saum: float = 1.0 - smoothstep(0.20, 0.70, arid)
			if rng.randf() < 0.52 * saum + 0.32 + 0.24 * shelter:
				var kind: String = ["dune_grass", "dune_grass", "desert_scrub", "desert_scrub", "tumble_scrub"][rng.randi() % 5] if saum > 0.35 else ["desert_scrub", "desert_scrub", "tumble_scrub", "dune_grass"][rng.randi() % 4]
				_add(found, rng, kind, _weighted(rng, kind), center)
				if rng.randf() < 0.60:
					for _i: int in rng.randi_range(1, 3):
						_add(found, rng, kind, _weighted(rng, kind), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.2, 2.8))
		"desert_quartz":
			if arid < 0.58:
				return
			for i: int in 6:
				var at: Vector2 = center + (Vector2.ZERO if i == 0 else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.8, 3.2))
				var at_cell: Vector2i = Vector2i(floori(at.x), floori(at.y))
				var rim: int = _quartz_rim(position_of(at_cell))
				if rim == 1 or rim == 2:
					if rng.randf() < 0.78:
						var q_kind: String = "glass_aloe" if (rim == 2 or rng.randf() < 0.58) else "night_cactus"
						_add(found, rng, q_kind, _weighted(rng, q_kind), at)
						if q_kind == "glass_aloe" and rng.randf() < 0.45:
							_add(found, rng, "glass_aloe", _weighted(rng, "glass_aloe"), at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.1, 2.0))
					return
			if shelter > 0.5 and arid >= 0.65 and rng.randf() < 0.08:
				_add(found, rng, "night_cactus", _weighted(rng, "night_cactus"), center)
		"desert_tuber":
			if arid < 0.38 or oasis > 0.35:
				return
			if rng.randf() < 0.22 * (1.0 - 0.45 * shelter):
				_add(found, rng, "sand_tuber", _weighted(rng, "sand_tuber"), center)
				if rng.randf() < 0.25:
					_add(found, rng, "sand_tuber", _weighted(rng, "sand_tuber"), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 2.8))
		"oasis_palm":
			if arid < 0.35 or lake_d < 0.7 or lake_d > 7.8:
				return
			var palm_chance: float = 0.86 if lake_d < 4.2 else 0.48
			if rng.randf() >= palm_chance:
				return
			var count: int = rng.randi_range(2, 3) if (lake_d < 4.0 and rng.randf() < 0.55) else 1
			for p_idx: int in count:
				var p_at: Vector2 = center + (Vector2.ZERO if p_idx == 0 else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.8, 3.4))
				var p_var: int = [1, 2, 3, 4, 5][rng.randi() % 5] if (lake_d < 3.6 and rng.randf() < 0.68) else _weighted(rng, "sun_palm")
				_add(found, rng, "sun_palm", p_var, p_at, 0.0, true)
			for _i: int in rng.randi_range(2, 4):
				var sub_kind: String = ["oasis_lily", "oasis_reed", "dune_grass", "glass_aloe"][rng.randi() % 4]
				_add(found, rng, sub_kind, _weighted(rng, sub_kind), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.1, 2.8))
			if lake_d > 2.6 and rng.randf() < 0.22:
				_add(found, rng, "prickly_pear", _weighted(rng, "prickly_pear"), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.8, 3.4))
		"oasis_flora":
			var gap: float = _water_gap(center)
			if arid < 0.35 or gap < 4.2 or gap > 96.0 or lake_d < 0.15 or lake_d > 6.4:
				return
			if gap <= 42.0:
				if rng.randf() < 0.85:
					for _i: int in rng.randi_range(3, 6):
						var pos: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 1.4)
						if _water_gap(pos) >= 3.8:
							_add(found, rng, "oasis_reed", _weighted(rng, "oasis_reed"), pos)
					for _j: int in rng.randi_range(1, 3):
						var lpos: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.4, 1.8)
						if _water_gap(lpos) >= 4.0:
							_add(found, rng, "oasis_lily", _weighted(rng, "oasis_lily"), lpos)
			elif rng.randf() < 0.58:
				for _i: int in rng.randi_range(2, 5):
					var kind: String = ["oasis_lily", "oasis_lily", "oasis_reed", "dune_grass", "glass_aloe"][rng.randi() % 5]
					var opos: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.4, 2.0)
					if _water_gap(opos) >= 5.5:
						_add(found, rng, kind, _weighted(rng, kind), opos)
		"desert_rock_cluster":
			if arid < 0.66 or oasis >= 0.12:
				return
			var anchor: Vector2 = Vector2.ZERO
			var big_v: int = -1
			for i: int in 14:
				var cand_at: Vector2 = center if i == 0 else center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.8, 5.2)
				var cand_cell: Vector2i = Vector2i(floori(cand_at.x), floori(cand_at.y))
				var v: int = _pick_quartz_rock_variant(rng, position_of(cand_cell), true)
				if v >= 0:
					anchor = cand_at
					big_v = v
					break
			if big_v < 0:
				return
			if rng.randf() >= 0.84:
				return
			var anchor_cell: Vector2i = Vector2i(floori(anchor.x), floori(anchor.y))
			var pv_big: int = absi(hash(Vector2i(anchor_cell.x * 11 + 3, anchor_cell.y * 17 + 7))) % 4
			var use_prism_big: bool = arid >= 0.76 and absi(hash(Vector2i(anchor_cell.x * 23, anchor_cell.y * 29))) % 100 < (26 if tile.x >= 820 else 16) and _prism_vein_fits(position_of(anchor_cell), pv_big)
			_add(found, rng, "prism_vein" if use_prism_big else "sun_quartz_rock", pv_big if use_prism_big else big_v, anchor)
			var placed_sub: int = 0
			for _i: int in 6:
				if placed_sub >= 2:
					break
				var sat_at: Vector2 = anchor + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.4, 3.4)
				var sat_cell: Vector2i = Vector2i(floori(sat_at.x), floori(sat_at.y))
				var sv: int = _pick_quartz_rock_variant(rng, position_of(sat_cell), false)
				if sv >= 0:
					var before: int = found.size()
					var pv_sat: int = absi(hash(Vector2i(sat_cell.x * 13 + 5, sat_cell.y * 19 + 9))) % 4
					var use_prism_sat: bool = arid >= 0.78 and absi(hash(Vector2i(sat_cell.x * 31, sat_cell.y * 37))) % 100 < 14 and _prism_vein_fits(position_of(sat_cell), pv_sat)
					_add(found, rng, "prism_vein" if use_prism_sat else "sun_quartz_rock", pv_sat if use_prism_sat else sv, sat_at)
					placed_sub += found.size() - before
			for _i: int in rng.randi_range(1, 2):
				var aloe_at: Vector2 = anchor + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 3.4)
				var aloe_rim: int = _quartz_rim(position_of(Vector2i(floori(aloe_at.x), floori(aloe_at.y))))
				if aloe_rim == 1 or aloe_rim == 2:
					_add(found, rng, "glass_aloe", _weighted(rng, "glass_aloe"), aloe_at)
		"desert_rock_lone":
			if arid < 0.66 or oasis >= 0.12 or rng.randf() >= 0.72:
				return
			for i: int in 10:
				var cand_at: Vector2 = center if i == 0 else center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.7, 3.6)
				var cand_cell: Vector2i = Vector2i(floori(cand_at.x), floori(cand_at.y))
				var lv: int = _pick_quartz_rock_variant(rng, position_of(cand_cell), false)
				if lv >= 0:
					var pv_lone: int = absi(hash(Vector2i(cand_cell.x * 17 + 1, cand_cell.y * 23 + 11))) % 4
					var use_prism_lone: bool = arid >= 0.76 and absi(hash(Vector2i(cand_cell.x * 41, cand_cell.y * 43))) % 100 < (22 if tile.x >= 820 else 13) and _prism_vein_fits(position_of(cand_cell), pv_lone)
					_add(found, rng, "prism_vein" if use_prism_lone else "sun_quartz_rock", pv_lone if use_prism_lone else lv, cand_at)
					return


func _coast(at: Vector2) -> float:
	var cell: Vector2i = Vector2i(clampi(floori(at.x), 0, RegionMap.WORLD_TILES - 1), clampi(floori(at.y), 0, RegionMap.WORLD_TILES - 1))
	return (float(_sdf[cell.y * RegionMap.WORLD_TILES + cell.x]) - 128.0) / 8.0


## Some of the berry bushes are ember brambles instead (decided by where they stand, so the random
## stream, and with it everything else that stands there, stays as it was).
func _berry_kind(at: Vector2, fallback: String) -> String:
	return "ember_bush" if absi(hash(Vector2i(floori(at.x * 3.0), floori(at.y * 3.0)))) % 100 < 38 else fallback


## A point on the flattened gravel bed (tiles from its center), `from`..`to` of the way to its rim.
func _on_bed(rng: RandomNumberGenerator, rx: float, from: float, to: float) -> Vector2:
	var offset: Vector2 = Vector2.from_angle(rng.randf() * TAU) * rx * rng.randf_range(from, to)
	return Vector2(offset.x, offset.y * BED_FLATTEN)


## The bed (and what lies on it) must not reach into the void or the cleared test area.
func _bed_valid(center: Vector2, rx: float) -> bool:
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var at: Vector2 = center + Vector2.from_angle(angle) * rx * 1.1
		var cell: Vector2i = Vector2i(floori(at.x), floori(at.y))
		if cell.x < 0 or cell.y < 0 or cell.x >= RegionMap.WORLD_TILES or cell.y >= RegionMap.WORLD_TILES or _exclude.has_point(cell) or blocked_cells.has(cell):
			return false
		if (float(_sdf[cell.y * RegionMap.WORLD_TILES + cell.x]) - 128.0) / 8.0 < 3.0:
			return false
	return _relief.flat_around(center * 16.0, rx * 16.0 * 1.1) ## the bed lies on one level


## Adds a candidate if it is valid and clear of what this cluster already placed.
func _add(found: Array[Dictionary], rng: RandomNumberGenerator, kind: String, variant: int, at: Vector2, bias: float = 0.0, dense: bool = false, young: int = -1) -> void:
	var cell: Vector2i = Vector2i(floori(at.x), floori(at.y))
	var desert_shared_tie: float = -1.0
	if DESERT_KINDS.has(kind):
		if not is_desert_bare(cell):
			return
		var pos_px_d: Vector2 = position_of(cell)
		var rim: int = _quartz_rim(pos_px_d)
		var in_oasis: bool = (kind == "oasis_reed" or kind == "oasis_lily" or kind == "sun_palm") and BiomeBlend.oasis_at(pos_px_d) > 0.25
		if kind == "sun_quartz_rock":
			if not _quartz_rock_fits(pos_px_d, variant):
				return
		elif kind == "prism_vein":
			if not _prism_vein_fits(pos_px_d, variant):
				return
		elif not in_oasis and (rim >= 3 or (rim == 2 and kind != "glass_aloe")):
			return
	elif is_desert_bare(cell):
		if not DESERT_SHARED.has(kind):
			return
		var pos_px: Vector2 = position_of(cell)
		var arid: float = BiomeBlend.arid_at(pos_px)
		if arid >= 0.35 or BiomeBlend.is_quartz_surface(pos_px):
			return
		kind = _desert_shared_kind(cell, kind, arid)
		if kind.is_empty():
			return
		var cols: int = int((_plants[kind] as Dictionary).columns)
		variant = absi(hash(Vector2i(cell.x * 7 + 1, cell.y * 23 + 3))) % cols
		desert_shared_tie = float(absi(hash(Vector2i(cell.x * 29, cell.y * 31))) % 900) / 1000.0
	if (kind == "berry_bush" or kind == "ember_bush") and berry_free_cells.has(cell):
		kind = "bush"
	if kind == "bush" and is_witch(cell):
		kind = _hex_bush(cell)
		if kind != "bush":
			variant = [0, 0, 0, 1, 1, 1, 2, 2][absi(hash(Vector2i(cell.x * 3, cell.y * 17))) % 8]
	if (TREE_KINDS.has(kind) or kind == "thorn_hedge" or kind == "hex_shrub" or kind == "witch_broom" or kind == "bush") and is_witch(cell) and _in_clearing(at):
		return
	var plant: Dictionary = _plants[kind]
	var tile: int = RegionMap.WORLD_TILES
	var prio: float = float(PRIORITY[kind]) + (desert_shared_tie if desert_shared_tie >= 0.0 else rng.randf() * 0.9) + bias ## the random part breaks ties the same way everywhere; `bias` < 0 makes the newer woods give way to what stood before
	if cell.x < 0 or cell.y < 0 or cell.x >= tile or cell.y >= tile or _exclude.has_point(cell) or blocked_cells.has(cell):
		return
	if TREE_KINDS.has(kind) and tree_free_cells.has(cell):
		return
	# In open Windwiesen (`w_wind >= 0.36`), keep 100+ tile expanses strictly conifer-free and tree-free (only the hilltop SolitaryTree landmark stands there).
	if TREE_KINDS.has(kind) and not is_bare(cell) and MeadowHabitats.wind_meadow_at(position_of(cell)) >= 0.36:
		return
	if is_witch(cell) != (WITCH_KINDS.has(kind) or LAKE_KINDS.has(kind)) and not (is_witch(cell) and WITCH_SHARED.has(kind)): ## the Hexenwald carries its own plants (and the plain bushes of the meadow); its plants grow nowhere else
		return
	if (float(_sdf[cell.y * tile + cell.x]) - 128.0) / 8.0 < float(plant.edge_margin):
		return
	var scale: float = 1.0
	if young >= 0:
		variant = mini(variant, 1) ## a sapling grows into one of the small firs
	elif (TREE_KINDS.has(kind) or BUSH_KINDS.has(kind)) and _relief.level_at(position_of(cell)) >= KRUMMHOLZ_LEVEL:
		## Krummholz: on the high levels the wind and cold keep ordinary trees short (smallest two sizes) and everything woody a fifth smaller
		if TREE_KINDS.has(kind) and not (kind in ["sun_palm", "ancient_fir", "orchard_apple", "orchard_pear"]):
			variant = mini(variant, 1)
		scale = lerpf(0.75, 0.85, float(absi(hash(Vector2i(cell.x * 5, cell.y * 11))) % 100) / 100.0)
	var cand: Dictionary = {"cell": cell, "kind": kind, "variant": variant, "pos": position_of(cell), "foot": _foot(plant, kind, variant) * scale, "crown": _crown(plant, kind, variant) * scale, "prio": prio}
	if scale != 1.0:
		cand["scale"] = scale
	if young >= 0:
		cand["young"] = young
	if dense:
		cand["dense"] = true
		if kind in TREE_KINDS and kind != "crown_cactus" and kind != "sun_palm" and young < 0:
			cand["bed"] = 5 if kind == "ancient_fir" else _bed_index(float(cand.crown))
	if not _relief.flat_around(cand.pos as Vector2, float(cand.foot) + 4.0): ## no feet on a wall, a ramp or a cliff edge
		return
	for other: Dictionary in found:
		if not DECAL_KINDS.has(String(other.kind)) and _overlap(cand, other):
			return
	found.append(cand)


func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var d: float = (a.pos as Vector2).distance_to(b.pos as Vector2)
	if d < float(a.foot) + float(b.foot) + GAP:
		return true
	var factor: float = DENSE_CROWN_OVERLAP if a.has("dense") and b.has("dense") else CROWN_OVERLAP
	if a.has("dense") and b.has("dense") and (String(a.kind) == "ancient_fir" or String(b.kind) == "ancient_fir"):
		factor = 0.48 ## giant Urforst fir crowns interlock into a closed cathedral vault
	return float(a.crown) > 0.0 and float(b.crown) > 0.0 and d < factor * (float(a.crown) + float(b.crown))


## The ground a prop takes up (px radius).
func _foot(plant: Dictionary, kind: String, variant: int) -> float:
	match kind:
		"ancient_fir":
			return maxf(float((plant.trunk_half_width as Array)[variant]) * 1.45 + 8.0, float((plant.crown_half_width as Array)[variant]) * 0.34)
		"tree", "willow", "blossom", "orchard_apple", "orchard_pear", "hag_tree", "bone_tree":
			return maxf(float((plant.trunk_half_width as Array)[variant]) * 1.6 + 8.0, float((plant.crown_half_width as Array)[variant]) * 0.5)
		"crown_cactus":
			return maxf(float((plant.trunk_half_width as Array)[variant]) * 1.5 + 6.0, float((plant.crown_half_width as Array)[variant]) * 0.42)
		"sun_palm":
			return maxf(float((plant.trunk_half_width as Array)[variant]) * 1.4 + 6.0, float((plant.crown_half_width as Array)[variant]) * 0.36)
		"rock", "iron_rock", "curse_rock", "sun_quartz_rock", "prism_vein", "ruin_sandstone", "dry_stone_wall":
			return float((plant.radius as Array)[variant]) * 0.9
		"pebble":
			return float((plant.radius as Array)[variant]) * 0.6
	return float((plant.radius as Array)[variant]) * 0.85


func _crown(plant: Dictionary, kind: String, variant: int) -> float:
	return float((plant.crown_half_width as Array)[variant]) if kind in TREE_KINDS else 0.0


func _weighted(rng: RandomNumberGenerator, kind: String) -> int:
	return rng.rand_weighted(PackedFloat32Array((_plants[kind] as Dictionary).weights))


## 0 open meadow .. 1 shaded, wild ground (the same noise paints the ferns and mushrooms).
func _wild(at: Vector2) -> float:
	return smoothstep(0.5, 0.78, 1.0 - (_zone.get_noise_2d(at.x, at.y) * 0.5 + 0.5))


## 1 within the stony shore band (3-16 tiles from the coast).
func _shore(at: Vector2) -> float:
	var cell: Vector2i = Vector2i(clampi(floori(at.x), 0, RegionMap.WORLD_TILES - 1), clampi(floori(at.y), 0, RegionMap.WORLD_TILES - 1))
	var coast: float = (float(_sdf[cell.y * RegionMap.WORLD_TILES + cell.x]) - 128.0) / 8.0
	return smoothstep(3.0, 6.0, coast) * (1.0 - smoothstep(12.0, 16.0, coast))
