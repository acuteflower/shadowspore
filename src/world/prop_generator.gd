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
]
const WITCH_KINDS: Array[String] = ["hag_tree", "bone_tree", "thorn_hedge", "grave_candle", "witch_hat", "toad_cap", "ghost_fern", "mandrake", "curse_rock"] ## the Hexenwald's own plant world (tools/art_hexenwald.py): grows only where the biome is `bare` of the meadow's
const SHORE_KINDS: Array[String] = ["marsh_gold", "moon_iris", "brook_mint", "cattail"] ## may grow at the water's edge
const TREE_KINDS: Array[String] = ["tree", "willow", "blossom", "birch", "hag_tree", "bone_tree"] ## what has a trunk and a crown
const WITCH_SHARED: Array[String] = ["bush"] ## meadow plants the Hexenwald shares: the plain, unpickable bushes (more of them there, see `_witch`)
const PRIORITY: Dictionary = {"tree": 4.0, "rock": 3.0, "iron_rock": 3.05, "berry_bush": 2.2, "bush": 2.0, "pebble": 1.0, "mushroom": 0.0, "grass": 0.6, "ember_bush": 2.1, "willow": 3.5, "blossom": 3.4, "birch": 3.3, "ember_morel": 0.1, "moon_parasol": 0.1, "moon_iris": 0.3, "brook_mint": 0.25, "marsh_gold": 0.3, "moonbell": 0.2, "wound_leaf": 0.2, "puffseed": 0.25, "glowfern": 0.3, "cattail": 0.35, "sunbloom": 0.3, "voidbloom": 0.2, "earth_tuber": 0.15, "ember_carrot": 0.25, "night_beet": 0.25, "mist_lily": 0.3, "spark_poppy": 0.25, "snapper": 0.3, "hag_tree": 4.0, "bone_tree": 3.6, "curse_rock": 3.05, "thorn_hedge": 2.0, "ghost_fern": 0.3, "grave_candle": 0.25, "witch_hat": 0.25, "toad_cap": 0.1, "mandrake": 0.2} ## mushrooms give way to everything, so they never change what else stands where
const BED_RX: Array[float] = [40.0, 48.0, 56.0, 64.0, 72.0, 80.0] ## px, the gravel beds (assets/props/stonebed.png)
const BED_FLATTEN: float = 0.64
const GAP: float = 3.0 ## px kept free between footprints
const CROWN_OVERLAP: float = 0.8 ## crowns may just touch (x their half widths): the minimum distance of two trees is this x the sum of their crown half widths
const DENSE_CROWN_OVERLAP: float = 0.6 ## the same for two trees of a grove or a wood: their crowns reach into each other and close into one canopy (a smaller factor lets them stand closer)
const FOREST_BED_RX: Array[float] = [28.0, 36.0, 44.0, 52.0, 60.0, 70.0] ## px, the forest floor under every tree of a wood (assets/props/forestbed.png, tools/art_forestbed.py)
const KRUMMHOLZ_LEVEL: float = 1.6 ## relief level (0..3, smooth) from which trees and bushes are stunted by wind and cold
const BUSH_KINDS: Array[String] = ["bush", "berry_bush", "ember_bush"]
const YOUNG_GROW_DAYS: float = 7.0 ## days a generated sapling needs to become a fir (WorldLevel counts them from day 1)
const BUCKET: float = 72.0 ## px, grid for the overlap search (bigger than any two footprints together)
const SMALL_ROCKS: Array[int] = [0, 1, 4, 5, 6]
const BIG_ROCKS: Array[int] = [1, 2, 3, 5, 6, 7]
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
const LAYER_NEEDS: Dictionary = {"lone_bush": 2, "lone_grass": 1, "tussock": 1, "lone_mushroom": 2, "lone_snapper": 2, "lone_flora": 2, "lone_root": 1, "shroom_patch": 2, "flora_patch": 2} ## layers that read the slope (1) or slope and damp (2) of a cluster


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


## True where the map's biome carries no props (data/biomes.json `bare`).
func is_bare(cell: Vector2i) -> bool:
	if bare.is_empty():
		return false
	var side: int = RegionMap.WORLD_TILES / RegionMap.CELL
	return bare[clampi(cell.y / RegionMap.CELL, 0, side - 1) * side + clampi(cell.x / RegionMap.CELL, 0, side - 1)] == 1


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
					if candidate.kind != "stonebed":
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
					if SHORE_KINDS.has(candidate.kind): ## waterside plants may stand right at the bank, just not in the water
						if _generator.water_dist.is_valid() and float(_generator.water_dist.call(candidate.pos)) < 4.0: continue
					elif _generator.water_clear.is_valid() and not bool(_generator.water_clear.call(candidate.pos, float(candidate.get("foot", 80.0)))): continue
					if not _expanded.has_point(cell): continue
					var wanted: int = 3 if int(entry.mask) == 3 and _rect.has_point(cell) else 2
					var blocked: int = 0 if candidate.kind == "stonebed" else _dominated(candidate, wanted)
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
	var found: Array[Dictionary] = []
	match String(layer.name):
		"grove":
			if rng.randf() < lerpf(0.55, 1.0, wild):
				_grove(found, rng, center, wild)
		"formation":
			if rng.randf() < 0.45 + 0.35 * wild + 0.3 * shore:
				_formation(found, rng, center)
		"thicket":
			if rng.randf() < lerpf(0.45, 0.9, wild):
				_thicket(found, rng, center)
		"lone_tree":
			if rng.randf() < lerpf(0.5, 0.8, wild):
				_add(found, rng, "tree", [0, 0, 1, 1, 2][rng.randi() % 5], center)
		"lone_bush":
			if rng.randf() < 0.42 * lush:
				var kind: String = _berry_kind(center, "berry_bush") if rng.randf() < 0.12 else "bush"
				_add(found, rng, kind, _weighted(rng, kind), center)
		"lone_stone":
			if rng.randf() < 0.4 + 0.15 * shore + (0.3 if _relief.wall_above(Vector2i(floori(center.x), floori(center.y))) else 0.0): ## rubble lies at the foot of a cliff
				if rng.randf() < 0.12: ## now and then a single small rock instead
					_add(found, rng, "rock", SMALL_ROCKS[rng.randi() % SMALL_ROCKS.size()], center)
				else:
					_add(found, rng, "pebble", _weighted(rng, "pebble"), center)
		"lone_ore": ## single iron rocks: rarer than stone, more at the foot of cliffs and on the high ground, a little more in the wild
			var tile: Vector2i = Vector2i(floori(center.x), floori(center.y))
			if rng.randf() < 0.2 + 0.3 * (1.0 if _relief.wall_above(tile) else 0.0) + 0.08 * smoothstep(0.5, 2.0, _relief.level_at(center * 16.0)) + 0.08 * wild:
				_add(found, rng, "iron_rock", _weighted(rng, "iron_rock"), center)
		"ore_formation": ## a rock formation whose big rock is iron ore, with ore among the smaller ones
			if rng.randf() < 0.3 + 0.25 * wild:
				_formation(found, rng, center, true)
		"lone_mushroom":
			if rng.randf() < (0.1 + 0.5 * shade) * (0.5 + damp): ## they like the shade (and north slopes and cliff feet) and the damp
				_add(found, rng, "mushroom", _weighted(rng, "mushroom"), center)
		"lone_grass":
			if rng.randf() < 0.5 - 0.3 * wild + 0.15 * maxf(slope, 0.0): ## more in the open meadow and on sunny slopes
				_add(found, rng, "grass", _weighted(rng, "grass"), center)
		"tussock":
			if rng.randf() < 0.55 - 0.25 * wild + 0.2 * maxf(slope, 0.0):
				_tussock(found, rng, center)
		"willow_stand":
			if rng.randf() < 0.16 + 0.55 * shore + 0.12 * wild: ## willows like the wet, shaded ground near the coast
				_willow_stand(found, rng, center)
		"orchard":
			if rng.randf() < 0.08 + 0.4 * (1.0 - wild): ## blossom trees stand in the open
				_orchard(found, rng, center)
		"wood":
			if rng.randf() < 0.15 + 0.5 * wild: ## big mixed woods, mostly in the shaded, wild ground
				_wood(found, rng, center)
		"copse":
			if rng.randf() < 0.3:
				_copse(found, rng, center)
		"lone_blossom":
			if rng.randf() < 0.1 + 0.16 * (1.0 - wild):
				_add(found, rng, "blossom", _weighted(rng, "blossom"), center)
		"lone_snapper": ## the odd night flower of the dark, damp shade (it only bites at night, and not inside the town's light)
			if rng.randf() < 0.04 + 0.22 * shade * damp:
				_add(found, rng, "snapper", _weighted(rng, "snapper"), center)
		"lone_flora":
			if rng.randf() < 0.5 * lush:
				var flora: String = _flora_kind(rng, center, shade, shore, slope)
				_add(found, rng, flora, _weighted(rng, flora), center)
		"lone_root": ## the odd root vegetable out in the wild: nightbeets in deep shade, ember carrots toward the light
			if rng.randf() < 0.22 + 0.4 * shade:
				var root: String = "night_beet" if rng.randf() < 0.1 + 0.75 * wild else "ember_carrot"
				_add(found, rng, root, _weighted(rng, root), center)
		"birch_grove": ## drifts of moon birches in the open and at the light edge of woods, young ones around the old
			if rng.randf() < 0.16 + 0.4 * (1.0 - wild):
				_birch_grove(found, rng, center)
		"lone_birch":
			if rng.randf() < 0.08 + 0.12 * (1.0 - wild):
				_add(found, rng, "birch", _weighted(rng, "birch"), center, -0.4)
		"shroom_patch": ## glow morels and moon parasols in small groups, in the shade and on the edge of the birch drifts
			if rng.randf() < (0.1 + 0.4 * shade) * (0.5 + damp):
				var shroom: String = "ember_morel" if rng.randf() < 0.55 else "moon_parasol"
				for _i: int in rng.randi_range(2, 5):
					_add(found, rng, shroom, _weighted(rng, shroom), center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 3.5))
		"fairy_ring": ## rare: moon parasols standing in a perfect ring, with a glow cap in the middle
			if rng.randf() < 0.2 + 0.25 * wild:
				_fairy_ring(found, rng, center)
		"water_edge": ## the damp strip along rivers and lakes: marsh marigolds right at the water, irises a little back, mint further out
			var gap: float = _water_gap(center)
			if gap >= 6.0 and gap <= 120.0 and rng.randf() < 0.75 * (1.0 - 0.5 * smoothstep(20.0, 120.0, gap)):
				_water_edge(found, rng, center)
		"flora_patch":
			if rng.randf() < 0.5 * lush:
				_flora_patch(found, rng, center, shade, shore, slope)
		"witch_wood", "witch_tree", "witch_flora", "witch_patch", "witch_ore":
			if is_bare(Vector2i(floori(center.x), floori(center.y))):
				_witch(String(layer.name), found, rng, center, wild)
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
	var radius: float = rng.randf_range(9.0, 14.0) * (0.8 + 0.4 * _wild(center))
	var wanted: int = clampi(int(radius * 1.5), 12, 24)
	var planted: int = 0
	## A real clearing in most woods (a seeded stream of its own, so it never moves the trees): sunlit flowers in the middle of the trees.
	var open_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	open_rng.seed = hash(Vector3i(floori(center.x * 4.0), floori(center.y * 4.0), _seed + 911))
	var clearing: Vector3 = Vector3.ZERO ## x, y (tiles), z radius; 0 = no clearing
	if open_rng.randf() < 0.65:
		var spot: Vector2 = center + Vector2.from_angle(open_rng.randf() * TAU) * radius * open_rng.randf_range(0.15, 0.55)
		clearing = Vector3(spot.x, spot.y, radius * open_rng.randf_range(0.2, 0.32))
	for _i: int in wanted * 10:
		if planted >= wanted:
			break
		var t: float = sqrt(rng.randf())
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * t
		var kind: String = _tree_kind(rng, at)
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
		var kind: String = "mushroom" if roll < 0.25 else ("grass" if roll < 0.45 else ("ember_bush" if roll < 0.55 else "bush"))
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
	if not water_dist.is_valid():
		return INF
	return float(water_dist.call(at * 16.0))


## 0 far from the water .. 1 at its edge (within about 100 px).
func _near_water(at: Vector2) -> float:
	var gap: float = _water_gap(at)
	return 0.0 if gap == INF else 1.0 - smoothstep(8.0, 100.0, gap)


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


## Which tree grows at `at`: willows on wet ground near the coast, blossom trees in the open, else firs.
func _tree_kind(rng: RandomNumberGenerator, at: Vector2) -> String:
	var roll: float = rng.randf()
	if _shore(at) > 0.35 and roll < 0.3:
		return "willow"
	if _wild(at) < 0.45 and roll > 0.72:
		return "blossom"
	return "tree"


## A size for a tree `t` of the way from the middle of its wood (0) to the edge (1): tall in the middle.
func _tree_variant(rng: RandomNumberGenerator, kind: String, t: float) -> int:
	if kind != "tree":
		return _weighted(rng, kind)
	var v: float = t + rng.randf() * 0.3
	return (3 if rng.randf() < 0.5 else 2) if v < 0.25 else (2 if v < 0.55 else (1 if v < 0.85 else 0))


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
	var kind: String = "cattail" if shore > 0.35 else _flora_kind(rng, center, wild, shore * 0.0, slope)
	if _coast(center) < 12.0 and rng.randf() < 0.5: ## the void's edge: dark, pulsing blooms
		kind = "voidbloom"
	var radius: float = rng.randf_range(2.0, 5.0)
	var count: int = rng.randi_range(4, 9)
	match kind:
		"sunbloom":
			radius += 1.5
			count += 3
		"voidbloom":
			count = rng.randi_range(2, 4)
		"earth_tuber":
			count = rng.randi_range(3, 6)
		"spark_poppy": ## a poppy field
			radius += 1.0
			count += 3
		"mist_lily": ## a carpet of lilies under the shade, mostly near the damp shore
			count = rng.randi_range(3, 7)
	for _i: int in count:
		_add(found, rng, kind, _weighted(rng, kind), center + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf()))


## Tiles from the coast (negative never happens on land).
## The Hexenwald's plant world (data/plants.json WITCH_KINDS): close, dark woods of Hexenulmen with a Bleichbaum or two at
## their edge and thorn hedges, ghost ferns and toadstools between the trunks; lone trees; flowers in the gaps (grave candles
## and witch hats in the open, toadstools and ferns in the shade, a rare mandrake); rings and drifts of one kind; cursed silver.
func _witch(layer: String, found: Array[Dictionary], rng: RandomNumberGenerator, center: Vector2, wild: float) -> void:
	match layer:
		"witch_wood":
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
					found[-1].erase("bed") ## no meadow litter under them: this ground is its own
					trees += 1
			for _i: int in rng.randi_range(7, 14):
				var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.2, 1.2)
				var under: String = ["thorn_hedge", "ghost_fern", "ghost_fern", "toad_cap", "bush", "bush"][rng.randi() % 6]
				_add(found, rng, under, _weighted(rng, under), at)
		"witch_tree":
			if rng.randf() < 0.6 + 0.2 * wild:
				var kind: String = "bone_tree" if rng.randf() < 0.4 else "hag_tree"
				_add(found, rng, kind, [0, 0, 1, 1, 2][rng.randi() % 5], center)
		"witch_flora":
			if rng.randf() < 0.85:
				var roll: float = rng.randf()
				var kind: String = "mandrake" if roll < 0.04 else ("bush" if roll < 0.24 else "thorn_hedge" if roll < 0.34 else (["ghost_fern", "toad_cap"][rng.randi() % 2] if rng.randf() < 0.25 + 0.6 * wild else ["grave_candle", "witch_hat"][rng.randi() % 2]))
				_add(found, rng, kind, _weighted(rng, kind), center)
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
	if (kind == "berry_bush" or kind == "ember_bush") and berry_free_cells.has(cell):
		kind = "bush"
	var plant: Dictionary = _plants[kind]
	var tile: int = RegionMap.WORLD_TILES
	var prio: float = float(PRIORITY[kind]) + rng.randf() * 0.9 + bias ## the random part breaks ties the same way everywhere; `bias` < 0 makes the newer woods give way to what stood before
	if cell.x < 0 or cell.y < 0 or cell.x >= tile or cell.y >= tile or _exclude.has_point(cell) or blocked_cells.has(cell):
		return
	if TREE_KINDS.has(kind) and tree_free_cells.has(cell):
		return
	if is_bare(cell) != WITCH_KINDS.has(kind) and not (is_bare(cell) and WITCH_SHARED.has(kind)): ## the Hexenwald carries its own plants (and the plain bushes of the meadow); its plants grow nowhere else
		return
	if (float(_sdf[cell.y * tile + cell.x]) - 128.0) / 8.0 < float(plant.edge_margin):
		return
	var scale: float = 1.0
	if young >= 0:
		variant = mini(variant, 1) ## a sapling grows into one of the small firs
	elif (TREE_KINDS.has(kind) or BUSH_KINDS.has(kind)) and _relief.level_at(position_of(cell)) >= KRUMMHOLZ_LEVEL:
		## Krummholz: on the high levels the wind and cold keep trees short (smallest two sizes) and everything woody a fifth smaller
		if TREE_KINDS.has(kind):
			variant = mini(variant, 1)
		scale = lerpf(0.75, 0.85, float(absi(hash(Vector2i(cell.x * 5, cell.y * 11))) % 100) / 100.0)
	var cand: Dictionary = {"cell": cell, "kind": kind, "variant": variant, "pos": position_of(cell), "foot": _foot(plant, kind, variant) * scale, "crown": _crown(plant, kind, variant) * scale, "prio": prio}
	if scale != 1.0:
		cand["scale"] = scale
	if young >= 0:
		cand["young"] = young
	if dense:
		cand["dense"] = true
		if kind in TREE_KINDS and young < 0:
			cand["bed"] = _bed_index(float(cand.crown))
	if not _relief.flat_around(cand.pos as Vector2, float(cand.foot) + 4.0): ## no feet on a wall, a ramp or a cliff edge
		return
	for other: Dictionary in found:
		if other.kind != "stonebed" and _overlap(cand, other):
			return
	found.append(cand)


func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var d: float = (a.pos as Vector2).distance_to(b.pos as Vector2)
	if d < float(a.foot) + float(b.foot) + GAP:
		return true
	var factor: float = DENSE_CROWN_OVERLAP if a.has("dense") and b.has("dense") else CROWN_OVERLAP
	return float(a.crown) > 0.0 and float(b.crown) > 0.0 and d < factor * (float(a.crown) + float(b.crown))


## The ground a prop takes up (px radius).
func _foot(plant: Dictionary, kind: String, variant: int) -> float:
	match kind:
		"tree", "willow", "blossom", "hag_tree", "bone_tree":
			return maxf(float((plant.trunk_half_width as Array)[variant]) * 1.6 + 8.0, float((plant.crown_half_width as Array)[variant]) * 0.5)
		"rock", "iron_rock", "curse_rock":
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
