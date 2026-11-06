class_name FallenLogScatter
extends RefCounted
## One deterministic candidate per 8x8 tiles, prepared cooperatively with the chunk.
static func candidate(world: Variant,c: Vector2i,index: int,obstacles: Array[Dictionary]) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var x: int = index%4
	var y: int = index/4
	rng.seed = hash(Vector3i(c.x*4+x,c.y*4+y,world._map.world_seed+12409))
	var pos: Vector2 = Vector2(c*32)*16+Vector2(x*128+64,y*128+64)+Vector2(rng.randf_range(-20,20),rng.randf_range(-20,20)).round()
	var tile: Vector2i = Vector2i(pos/16.0)
	if not world._land_at(tile.x,tile.y): return {}
	var trees: int = _trees_near(pos, obstacles)
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
	for obstacle: Dictionary in obstacles:
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
static func _trees_near(pos: Vector2, obstacles: Array[Dictionary]) -> int:
	var count: int = 0
	for obstacle: Dictionary in obstacles:
		if PropGenerator.TREE_KINDS.has(String(obstacle.kind)) and (obstacle.pos as Vector2).distance_to(pos) < 80.0:
			count += 1
	return count
