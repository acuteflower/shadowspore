class_name FallenLogScatter
extends RefCounted
## One deterministic candidate per 8x8 tiles, prepared cooperatively with the chunk.
## `grid` / `reach` come from `index_obstacle` (the chunk's log grid and its largest reach); an empty grid scans `obstacles`.
const BUCKET: float = 64.0 ## must equal WorldLevel.DETAIL_BUCKET

static func candidate(world: Variant,c: Vector2i,index: int,obstacles: Array[Dictionary],grid: Dictionary = {},reach: float = 0.0) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var x: int = index%4
	var y: int = index/4
	rng.seed = hash(Vector3i(c.x*4+x,c.y*4+y,world._map.world_seed+12409))
	var pos: Vector2 = Vector2(c*32)*16+Vector2(x*128+64,y*128+64)+Vector2(rng.randf_range(-20,20),rng.randf_range(-20,20)).round()
	var tile: Vector2i = Vector2i(pos/16.0)
	if not world._land_at(tile.x,tile.y): return {}
	var trees: int = _trees_near(pos, obstacles, grid)
	var chance: float = float(DataRegistry.table("fallen_logs").get("chance",0.42))
	chance *= 0.12 if trees == 0 else 1.0 + 0.15 * float(mini(trees, 4)) ## a trunk lies in or at a wood, rarely out in the open
	var biome: String = world._land_biome(tile)
	if biome == "glass_cliffs": chance *= 0.2
	elif biome == "mist_forest": chance *= 1.35
	if rng.randf() > chance: return {}
	var frame: int = rng.randi_range(0,23)
	var spec: Dictionary = (DataRegistry.table("fallen_logs").frames as Array)[frame]
	var a: Vector2 = pos+Vector2(float(spec.a[0]),float(spec.a[1]))
	var b: Vector2 = pos+Vector2(float(spec.b[0]),float(spec.b[1]))
	for i: int in 13:
		var point: Vector2 = a.lerp(b,i/12.0)
		var cell: Vector2i = Vector2i((point/16.0).floor())
		if world._rivers != null and not world._rivers.clear_for_prop(point, 14.0): return {}
		if not world._land_at(cell.x,cell.y) or not world._relief.flat_around(point,13.0) or world._generator.blocked_cells.has(cell) or world._stone_cells.has(cell) or world.edits.terrain.has(WorldEdits.key(cell)):
			return {}
		for patch: Node in Terrain.patches:
			if patch.call("surface_at",point) != "": return {}
	## Only obstacles whose centre lies within the final check's reach (radius + 14) of the log can block it.
	var margin: float = reach + 14.0
	var lo: Vector2 = Vector2(minf(a.x, b.x) - margin, minf(a.y, b.y) - margin)
	var hi: Vector2 = Vector2(maxf(a.x, b.x) + margin, maxf(a.y, b.y) + margin)
	for obstacle: Dictionary in _near(obstacles, grid, lo, hi):
		if not bool(obstacle.get("custom",false)) and obstacle.has("cell") and world.edits.props.has(WorldEdits.key(obstacle.cell as Vector2i)): continue
		var point: Vector2 = obstacle.pos as Vector2
		var radius: float = 52.0
		if String(obstacle.kind) == "forestbed": continue ## logs lie on the forest floor
		if String(obstacle.kind) != "stonebed":
			var plant: Dictionary = DataRegistry.get_entry("plants",String(obstacle.kind))
			radius = float((plant.radius as Array)[int(obstacle.variant)])*float(obstacle.get("scale",1.0))
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)) < radius+14.0: return {}
	return {"pos":pos,"frame":frame}


## How many trees stand within five tiles of `pos` (the obstacles of the chunk and its neighbours).
static func _trees_near(pos: Vector2, obstacles: Array[Dictionary], grid: Dictionary = {}) -> int:
	var count: int = 0
	for obstacle: Dictionary in _near(obstacles, grid, pos - Vector2.ONE * 80.0, pos + Vector2.ONE * 80.0):
		if PropGenerator.TREE_KINDS.has(String(obstacle.kind)) and (obstacle.pos as Vector2).distance_to(pos) < 80.0:
			count += 1
	return count


## Adds an obstacle to the chunk's log grid (one entry, in the bucket of its centre) and returns its final-check radius, 0 for
## forest beds (they never block a log). Every obstacle is indexed here, edited ones too: the tree count has always included them.
static func index_obstacle(grid: Dictionary, obstacle: Dictionary) -> float:
	var kind: String = String(obstacle.kind)
	if kind == "forestbed": return 0.0
	var radius: float = 52.0
	if kind != "stonebed":
		var plant: Dictionary = DataRegistry.get_entry("plants", kind)
		radius = float((plant.radius as Array)[int(obstacle.variant)]) * float(obstacle.get("scale", 1.0))
	var pos: Vector2 = obstacle.pos as Vector2
	var key: Vector2i = Vector2i(floori(pos.x / BUCKET), floori(pos.y / BUCKET))
	(grid.get_or_add(key, []) as Array).append(obstacle)
	return radius


## The obstacles registered in the buckets that `lo`..`hi` touches (all of them when there is no grid). A superset: callers test exactly.
static func _near(obstacles: Array[Dictionary], grid: Dictionary, lo: Vector2, hi: Vector2) -> Array[Dictionary]:
	if grid.is_empty(): return obstacles
	var found: Array[Dictionary] = []
	for y: int in range(floori(lo.y / BUCKET), floori(hi.y / BUCKET) + 1):
		for x: int in range(floori(lo.x / BUCKET), floori(hi.x / BUCKET) + 1):
			for obstacle: Dictionary in grid.get(Vector2i(x, y), []):
				found.append(obstacle)
	return found
