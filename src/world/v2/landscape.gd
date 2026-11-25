class_name Landscape
extends RefCounted
## The planned landscape of one continent (docs/v2_zonenwelt_atlas_konzept.md 3.5): woods, groves and orchards with
## hand-drawn outlines and glades, ways, moss and hollows, single hand-placed trees, and the forest belts ("Waldmeer")
## that close every zone's edge. Planned ONCE for the whole continent in continent tiles, so a wood that reaches over a
## seam is one wood: each zone builds only its own cut-out (`trees_of`, `stands_near`, `ways_near`).
##
## Pure and immutable once built: every tree's place, kind, stage, seed and owner zone are fixed here, on every peer the
## same. Build it on the main thread (`Landscape.of` reads the file through `DataRegistry.json`); `Jobs` workers only
## read it (`Landscape.cached`).
##
## File (named by the continent's `landscape` key), all in continent tiles:
##   stands [{id, name, outline, glades [outline...], mix [{species, w, stages}], spacing, soil, edge, seed}]
##   ways [{kind, pts, seed, damp}], moss / hollows [[cx, cy, rx, ry]...], trees [{species, pos, stage, seed, traits}],
##   turf {forest {accents, kinds}}
## Belts come from each zone's `borders` [{kind "forest_sea", depth, mix}]: trees along the footprint's rim, young and
## loose towards the open ground, old and close at the edge, a few rows beyond it (the canopy backdrop takes over there);
## they thin out and stop where a seamless threshold's mouth opens, and never stand on a way or inside a planned stand.

const BELT_SPACING: float = 4.8 ## tiles between belt trees
const BELT_OUT: float = 3.4 ## tiles of real trees beyond a footprint (the canopy backdrop takes over further out)
const WAY_GAP: float = 2.6 ## tiles kept free on both sides of a way's centre line
const MOUTH: float = 7.0 ## tiles: belts thin out this close to a seamless threshold and stop below `MOUTH_CLEAR`
const MOUTH_CLEAR: float = 2.2
const GLADE_EDGE: float = 1.4 ## tiles kept free round a glade
const GRID: float = 8.0 ## tiles per planning bucket (spacing checks)
const DEFAULT_BELT_MIX: Array = [
	{"species": "valley_oak", "w": 0.6, "stages": [3, 4, 5]},
	{"species": "silver_birch", "w": 0.4, "stages": [2, 3, 4]},
]


class Stand:
	extends RefCounted
	var id: StringName
	var name: String
	var outline: PackedVector2Array ## smoothed, continent tiles
	var glades: Array[PackedVector2Array] = []
	var bbox: Rect2
	var soil: bool = true ## paint forest floor under it
	var spacing: float = 6.0
	var edge: float = 5.0
	var seed: int = 1
	var mix: Array[Dictionary] = []

	func contains(tile: Vector2) -> bool:
		if not bbox.has_point(tile) or not Geometry2D.is_point_in_polygon(tile, outline):
			return false
		for glade: PackedVector2Array in glades:
			if Geometry2D.is_point_in_polygon(tile, glade):
				return false
		return true


var continent: StringName
var stands: Array[Stand] = []
var ways: Array[Dictionary] = [] ## {kind, pts (PackedVector2Array, tiles), seed, damp, bbox}
var moss: Array[Rect2] = [] ## Rect2(centre, radii), tiles
var hollows: Array[Rect2] = []
var turf: Dictionary = {}
## Every tree of the continent: {species, pos (tiles), stage, seed, traits, owner (zone id), kind hand|stand|belt}.
var trees: Array[Dictionary] = []
var problems: PackedStringArray = PackedStringArray()
var _by_owner: Dictionary = {} ## StringName -> PackedInt32Array (indices into `trees`, in planning order)
var _grid: Dictionary = {} ## Vector2i -> PackedVector2Array of tree tiles (planning only)
var _way_lines: Array[PackedVector2Array] = [] ## smoothed way centre lines (planning only)
var _mouths: Array[PackedVector2Array] = [] ## lines of every seamless threshold (planning only)

static var _cache: Dictionary = {} ## StringName -> Landscape


## The continent's landscape, planned once (main thread first: it reads data files).
static func of(atlas: Atlas, continent_id: StringName) -> Landscape:
	if _cache.has(continent_id):
		return _cache[continent_id] as Landscape
	var c: Atlas.Continent = atlas.continent(continent_id)
	var data: Dictionary = {}
	if c != null and not c.landscape.is_empty():
		data = DataRegistry.json(c.landscape)
	var built: Landscape = from_data(atlas, continent_id, data)
	for problem: String in built.problems:
		push_warning("Landscape %s: %s" % [continent_id, problem])
	_cache[continent_id] = built
	return built


## Worker-safe: the landscape `of` has built before (an empty one if it never was).
static func cached(continent_id: StringName) -> Landscape:
	var found: Variant = _cache.get(continent_id)
	if found is Landscape:
		return found as Landscape
	var empty: Landscape = Landscape.new()
	empty.continent = continent_id
	return empty


static func forget() -> void:
	_cache.clear()


static func from_data(atlas: Atlas, continent_id: StringName, data: Dictionary) -> Landscape:
	var land: Landscape = Landscape.new()
	land.continent = continent_id
	land._parse(data)
	for t: Atlas.Threshold in atlas.thresholds.values():
		var tz: Atlas.Zone = atlas.zone(t.a)
		if t.seamless() and tz != null and tz.continent == continent_id:
			land._mouths.append(t.line)
	land._plan_hand_trees(atlas, data)
	for stand: Stand in land.stands:
		land._plan_stand(atlas, stand)
	for z: Atlas.Zone in atlas.zones_of(continent_id):
		land._plan_belt(atlas, z)
	land._index_owners()
	land._grid.clear()
	land._way_lines.clear()
	land._mouths.clear()
	return land


# --- questions --------------------------------------------------------------------------------------------------------

## The trees a zone builds, in a fixed order (node names T<n> follow it).
func trees_of(zone_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in (_by_owner.get(zone_id, PackedInt32Array()) as PackedInt32Array):
		out.append(trees[i])
	return out


## Every species a zone's trees use (to warm their sheets).
func species_of(zone_id: StringName) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for tree: Dictionary in trees_of(zone_id):
		var id: String = String(tree["species"])
		if not out.has(id):
			out.append(id)
	return out


func stands_near(area: Rect2) -> Array[Stand]:
	var out: Array[Stand] = []
	for stand: Stand in stands:
		if stand.bbox.intersects(area):
			out.append(stand)
	return out


func ways_near(area: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for way: Dictionary in ways:
		if (way["bbox"] as Rect2).intersects(area):
			out.append(way)
	return out


func patches_near(list: Array[Rect2], area: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for patch: Rect2 in list:
		if Rect2(patch.position - patch.size, patch.size * 2.0).intersects(area):
			out.append(patch)
	return out


## Which planned stand covers this tile (glades excluded), or null.
func stand_at(tile: Vector2) -> Stand:
	for stand: Stand in stands:
		if stand.contains(tile):
			return stand
	return null


# --- parsing ----------------------------------------------------------------------------------------------------------

func _parse(data: Dictionary) -> void:
	turf = data.get("turf", {}) as Dictionary if data.get("turf", {}) is Dictionary else {}
	for entry: Dictionary in Atlas._dicts(data.get("stands", [])):
		var stand: Stand = Stand.new()
		stand.id = StringName(String(entry.get("id", "")))
		stand.name = String(entry.get("name", ""))
		var raw: PackedVector2Array = Atlas._poly(entry.get("outline", []), Vector2.ZERO)
		if raw.size() < 3:
			problems.append("stand %s has no outline" % stand.id)
			continue
		stand.outline = Atlas.smooth_closed(raw)
		for glade_raw: Variant in entry.get("glades", []) as Array:
			var glade: PackedVector2Array = Atlas._poly(glade_raw, Vector2.ZERO)
			if glade.size() >= 3:
				stand.glades.append(Atlas.smooth_closed(glade))
		stand.bbox = Atlas._bounds(stand.outline)
		stand.soil = bool(entry.get("soil", true))
		stand.spacing = maxf(2.5, float(entry.get("spacing", 6.0)))
		stand.edge = maxf(0.0, float(entry.get("edge", 5.0)))
		stand.seed = int(entry.get("seed", 1))
		stand.mix = Atlas._dicts(entry.get("mix", []))
		if stand.mix.is_empty():
			stand.mix = Atlas._dicts(DEFAULT_BELT_MIX)
		stands.append(stand)
	for entry: Dictionary in Atlas._dicts(data.get("ways", [])):
		var pts: PackedVector2Array = Atlas._poly(entry.get("pts", []), Vector2.ZERO)
		if pts.size() < 2:
			continue
		ways.append({"kind": String(entry.get("kind", "trail")), "pts": pts, "seed": int(entry.get("seed", 263)), "damp": float(entry.get("damp", 0.0)), "bbox": Atlas._bounds(pts).grow(WAY_GAP + 2.0)})
		_way_lines.append(Atlas.smooth_open(pts, 1.0))
	for key: String in ["moss", "hollows"]:
		for raw: Variant in data.get(key, []) as Array:
			if raw is Array and (raw as Array).size() >= 4:
				var r: Array = raw as Array
				var patch: Rect2 = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
				if key == "moss":
					moss.append(patch)
				else:
					hollows.append(patch)


# --- planning ---------------------------------------------------------------------------------------------------------

func _plan_hand_trees(atlas: Atlas, data: Dictionary) -> void:
	for entry: Dictionary in Atlas._dicts(data.get("trees", [])):
		var pos: Vector2 = Atlas._vec(entry.get("pos"))
		if not pos.is_finite():
			continue
		_add_tree(atlas, String(entry.get("species", "valley_oak")), pos, int(entry.get("stage", 4)), int(entry.get("seed", 0)), "hand", entry.get("traits", {}))


func _plan_stand(atlas: Atlas, stand: Stand) -> void:
	var sp: float = stand.spacing
	var from: Vector2i = Vector2i(floori(stand.bbox.position.x / sp), floori(stand.bbox.position.y / sp))
	var to: Vector2i = Vector2i(ceili(stand.bbox.end.x / sp), ceili(stand.bbox.end.y / sp))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for gy: int in range(from.y, to.y + 1):
		for gx: int in range(from.x, to.x + 1):
			rng.seed = hash([stand.seed, gx, gy]) ## per cell: the stand's trees never shift when its outline is redrawn elsewhere
			var tile: Vector2 = Vector2((float(gx) + 0.12 + rng.randf() * 0.76) * sp, (float(gy) + 0.12 + rng.randf() * 0.76) * sp)
			var keep: float = rng.randf()
			var pick: float = rng.randf()
			var age: float = rng.randf()
			var tree_seed: int = rng.randi_range(1, 99999)
			if not stand.bbox.has_point(tile) or not Geometry2D.is_point_in_polygon(tile, stand.outline):
				continue
			var glade_d: float = INF
			for glade: PackedVector2Array in stand.glades:
				glade_d = minf(glade_d, -1.0 if Geometry2D.is_point_in_polygon(tile, glade) else Atlas.edge_distance(tile, glade))
			if glade_d < GLADE_EDGE:
				continue
			var thin: float = 1.0
			if stand.edge > 0.0:
				thin = clampf(minf(ZoneMath.rim_distance(tile, stand.outline) / stand.edge, (glade_d - GLADE_EDGE) / (stand.edge * 0.6)), 0.0, 1.0)
			if keep > lerpf(0.38, 1.0, thin) or _near_ways(tile, WAY_GAP) or _in_mouth(tile) or _crowded(tile, sp * 0.8):
				continue
			var entry: Dictionary = _pick(stand.mix, pick)
			var stages: Array = entry.get("stages", [4]) as Array
			var index: int = clampi(int(age * float(stages.size()) * lerpf(0.55, 1.0, thin)), 0, stages.size() - 1)
			_add_tree(atlas, String(entry.get("species", "valley_oak")), tile, int(stages[index]), tree_seed, "stand", {})


## The forest belt round one zone's footprint (concept 3.4 Waldmeer). Respects multi-border zones (`from..to` shares)
## so belts only grow along `"forest_sea"` borders and never into ocean, cliffs or open meadow seams.
func _plan_belt(atlas: Atlas, z: Atlas.Zone) -> void:
	if z.footprint.size() < 3 or (continent != &"lab" and z.placeholder):
		return
	var forest_borders: Array[Dictionary] = []
	if z.borders.is_empty():
		forest_borders.append({"kind": "forest_sea", "from": 0.0, "to": 1.0, "depth": 5.0})
	else:
		for b: Dictionary in z.borders:
			var bkind: String = String(b.get("kind", "forest_sea"))
			if bkind == "forest_sea":
				forest_borders.append(b)
			elif bkind == "meadow" and continent != &"lab":
				# Open meadow seam to a placeholder neighbour: frame its far side with belt trees so it merges into ZoneBackdrop.
				var bcopy: Dictionary = b.duplicate()
				bcopy["depth"] = 2.0
				forest_borders.append(bcopy)
	if forest_borders.is_empty():
		return
	var ring: PackedVector2Array = z.footprint.duplicate()
	ring.append(z.footprint[0])
	var total: float = Atlas.polyline_length(ring)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var steps: int = maxi(1, int(total / BELT_SPACING))
	for i: int in steps:
		var share: float = float(i) / float(steps)
		var border: Dictionary = {}
		for b: Dictionary in forest_borders:
			var f0: float = float(b.get("from", 0.0))
			var f1: float = float(b.get("to", 1.0))
			if share >= f0 and share <= f1:
				border = b
				break
		if border.is_empty():
			continue
		var depth: float = maxf(1.0, float(border.get("depth", 5.0)))
		var mix: Array[Dictionary] = Atlas._dicts(border.get("mix", []))
		if mix.is_empty():
			mix = Atlas._dicts(DEFAULT_BELT_MIX)
		var rows: Array[float] = []
		var d: float = -depth
		while d <= BELT_OUT + 0.01:
			rows.append(d)
			d += BELT_SPACING * 0.78
		var p: Vector2 = Atlas.point_along(ring, share)
		var ahead: Vector2 = Atlas.point_along(ring, minf(1.0, share + 0.5 / total))
		var behind: Vector2 = Atlas.point_along(ring, maxf(0.0, share - 0.5 / total))
		var tangent: Vector2 = (ahead - behind).normalized()
		if tangent == Vector2.ZERO:
			continue
		var normal: Vector2 = tangent.orthogonal()
		if z.contains(p + normal * 0.6):
			normal = -normal ## outward
		for r: int in rows.size():
			rng.seed = hash([String(z.id), i, r])
			var q: Vector2 = p + normal * (rows[r] + rng.randf_range(-0.45, 0.45)) + tangent * rng.randf_range(-0.38, 0.38) * BELT_SPACING
			var keep: float = rng.randf()
			var pick: float = rng.randf()
			var age: float = rng.randf()
			var tree_seed: int = rng.randi_range(1, 99999)
			var chance: float = 1.0 if rows[r] >= 0.0 else lerpf(1.0, 0.28, -rows[r] / depth)
			var mouth_d: float = INF
			for line: PackedVector2Array in _mouths:
				mouth_d = minf(mouth_d, ZoneMath.polyline_distance(q, line))
			if mouth_d < MOUTH_CLEAR:
				continue
			chance *= smoothstep(MOUTH_CLEAR, MOUTH, mouth_d)
			if keep > chance:
				continue
			var inside: StringName = _effective_zone(atlas, q)
			if inside != &"" and inside != z.id:
				continue ## that zone's own belt covers its side
			if stand_at(q) != null or _near_ways(q, WAY_GAP) or _crowded(q, BELT_SPACING * 0.74):
				continue
			var entry: Dictionary = _pick(mix, pick)
			var stages: Array = entry.get("stages", [4]) as Array
			var old: float = clampf((rows[r] + depth) / (depth + BELT_OUT), 0.0, 1.0) ## young towards the open ground
			var index: int = clampi(int(roundf(lerpf(0.0, float(stages.size() - 1), old) + (age - 0.5) * 1.2)), 0, stages.size() - 1)
			_add_tree(atlas, String(entry.get("species", "valley_oak")), q, int(stages[index]), tree_seed, "belt", {})


func _effective_zone(atlas: Atlas, tile: Vector2) -> StringName:
	var inside: StringName = atlas.zone_at_tile(continent, tile)
	if inside != &"" and continent != &"lab":
		var oz: Atlas.Zone = atlas.zone(inside)
		if oz != null and oz.placeholder:
			return &""
	return inside


func _add_tree(atlas: Atlas, species: String, tile: Vector2, stage: int, tree_seed: int, kind: String, traits: Variant) -> void:
	var owner: StringName = _owner_of(atlas, tile)
	if owner == &"":
		return
	trees.append({"species": species, "pos": tile, "stage": clampi(stage, 0, 6), "seed": tree_seed, "traits": traits if traits is Dictionary else {}, "owner": owner, "kind": kind})
	var cell: Vector2i = Vector2i(floori(tile.x / GRID), floori(tile.y / GRID))
	var list: PackedVector2Array = _grid.get(cell, PackedVector2Array()) as PackedVector2Array
	list.append(tile)
	_grid[cell] = list


## The zone a tree belongs to: the one it stands in, else the nearest within `BELT_OUT` (borderland), else none.
func _owner_of(atlas: Atlas, tile: Vector2) -> StringName:
	var inside: StringName = _effective_zone(atlas, tile)
	if inside != &"":
		return inside
	var best: StringName = &""
	var best_d: float = BELT_OUT + 0.6
	for z: Atlas.Zone in atlas.zones_of(continent):
		if (continent != &"lab" and z.placeholder) or not z.bbox.grow(best_d).has_point(tile):
			continue
		var dist: float = Atlas.edge_distance(tile, z.footprint)
		if dist < best_d or (is_equal_approx(dist, best_d) and String(z.id) < String(best)):
			best_d = dist
			best = z.id
	return best


func _crowded(tile: Vector2, gap: float) -> bool:
	var cell: Vector2i = Vector2i(floori(tile.x / GRID), floori(tile.y / GRID))
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			for other: Vector2 in (_grid.get(cell + Vector2i(ox, oy), PackedVector2Array()) as PackedVector2Array):
				if tile.distance_to(other) < gap:
					return true
	return false


## Inside a seamless threshold's clear mouth (no tree may block the way through).
func _in_mouth(tile: Vector2) -> bool:
	for line: PackedVector2Array in _mouths:
		if ZoneMath.polyline_distance(tile, line) < MOUTH_CLEAR:
			return true
	return false


func _near_ways(tile: Vector2, gap: float) -> bool:
	for line: PackedVector2Array in _way_lines:
		if ZoneMath.polyline_distance(tile, line) < gap:
			return true
	return false


static func _pick(mix: Array[Dictionary], roll: float) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in mix:
		total += maxf(0.0, float(entry.get("w", 1.0)))
	var at: float = roll * total
	for entry: Dictionary in mix:
		at -= maxf(0.0, float(entry.get("w", 1.0)))
		if at <= 0.0:
			return entry
	return mix[mix.size() - 1] if not mix.is_empty() else {}


func _index_owners() -> void:
	_by_owner.clear()
	for i: int in trees.size():
		var owner: StringName = trees[i]["owner"] as StringName
		var list: PackedInt32Array = _by_owner.get(owner, PackedInt32Array()) as PackedInt32Array
		list.append(i)
		_by_owner[owner] = list
