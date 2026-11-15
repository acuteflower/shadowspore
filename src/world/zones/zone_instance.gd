class_name ZoneInstance
extends Node2D
## Runtime container for a single dynamically loaded zone in its fixed spatial slot.

var zone_id: String = ""
var spec: Dictionary = {}
var slot_index: int = 0
var slot_origin_tile: Vector2i = Vector2i.ZERO
var slot_origin_px: Vector2 = Vector2.ZERO
var size_tiles: Vector2i = Vector2i.ZERO
var bounds_px: Rect2 = Rect2()
var is_home: bool = false

var walkable_grid: PackedByteArray = PackedByteArray() ## 1 = walkable land, 0 = blocked/rim
var water_depth_grid: PackedFloat32Array = PackedFloat32Array() ## <= 0 = land, > 0 = water depth

var decals_root: Node2D
var fx_root: Node2D
var props_root: Node2D
var collision_root: StaticBody2D

var painted_cells: Array[Vector2i] = []
var glow_cells: Array[Vector2i] = []
var decals: Array[Node] = []
var poi_nodes: Array[Node] = []
var spawns: Dictionary = {} ## spawn_id -> Vector2 global px
var portals: Dictionary = {} ## portal_id -> ZonePortal
var things: Dictionary = {} ## Vector2i global tile -> WorldProp
var enemies: Array[Node2D] = []
var wildlife: Array[Node2D] = []
var town_area_px: Rect2 = Rect2()
var hut_node: Node2D = null
var fallen_knight: Node2D = null
var cover_node: Node2D = null
var waystone_ids: Array[String] = []


func configure(id_val: String, zone_spec: Dictionary, slot_idx: int) -> void:
	zone_id = id_val
	spec = zone_spec
	slot_index = slot_idx
	slot_origin_tile = ZoneCatalog.slot_origin_tile(zone_id)
	slot_origin_px = ZoneCatalog.slot_origin_px(zone_id)
	size_tiles = Vector2i(int(zone_spec.get("width", 104)), int(zone_spec.get("height", 130)))
	bounds_px = Rect2(slot_origin_px, Vector2(size_tiles) * ZoneCatalog.TILE_PX)
	is_home = bool(zone_spec.get("is_home", false))
	name = "Zone_%s" % zone_id
	position = slot_origin_px

	decals_root = Node2D.new()
	decals_root.name = "Decals"
	decals_root.z_index = -9
	add_child(decals_root)

	fx_root = Node2D.new()
	fx_root.name = "FX"
	add_child(fx_root)

	collision_root = StaticBody2D.new()
	collision_root.name = "PerimeterCollision"
	collision_root.collision_layer = 1
	collision_root.collision_mask = 0
	add_child(collision_root)

	var total: int = size_tiles.x * size_tiles.y
	walkable_grid.resize(total)
	walkable_grid.fill(1)
	water_depth_grid.resize(total)
	water_depth_grid.fill(-1.0)


func has_world_pos(world_pos: Vector2) -> bool:
	return bounds_px.has_point(world_pos)


func local_tile(global_tile: Vector2i) -> Vector2i:
	return global_tile - slot_origin_tile


func in_zone_tile(local: Vector2i) -> bool:
	return local.x >= 0 and local.y >= 0 and local.x < size_tiles.x and local.y < size_tiles.y


func _idx(local: Vector2i) -> int:
	return local.y * size_tiles.x + local.x


func set_walkable(local: Vector2i, on: bool) -> void:
	if in_zone_tile(local):
		walkable_grid[_idx(local)] = 1 if on else 0


func is_walkable_local(local: Vector2i) -> bool:
	if not in_zone_tile(local):
		return false
	return walkable_grid[_idx(local)] == 1


func is_land_global(global_tile: Vector2i) -> bool:
	return is_walkable_local(global_tile - slot_origin_tile)


func set_water_depth(local: Vector2i, depth: float) -> void:
	if in_zone_tile(local):
		water_depth_grid[_idx(local)] = depth


func water_depth_at(world_pos: Vector2) -> float:
	var local: Vector2i = Vector2i(floori(world_pos.x / ZoneCatalog.TILE_PX), floori(world_pos.y / ZoneCatalog.TILE_PX)) - slot_origin_tile
	if not in_zone_tile(local):
		return -1.0
	return water_depth_grid[_idx(local)]


func navigation_floor_at(world_pos: Vector2) -> bool:
	var local: Vector2i = Vector2i(floori(world_pos.x / ZoneCatalog.TILE_PX), floori(world_pos.y / ZoneCatalog.TILE_PX)) - slot_origin_tile
	if not in_zone_tile(local):
		return false
	if walkable_grid[_idx(local)] == 0:
		return false
	return water_depth_grid[_idx(local)] < 0.45


func spawn_position(spawn_name: String = "default") -> Vector2:
	if spawns.has(spawn_name):
		return spawns[spawn_name] as Vector2
	if spawns.has("default"):
		return spawns["default"] as Vector2
	return bounds_px.get_center()


func clear_world_pos_clear_for_prop(world_pos: Vector2, radius_px: float = 0.0) -> bool:
	var pad_tiles: int = ceili(radius_px / ZoneCatalog.TILE_PX)
	var center: Vector2i = Vector2i(floori(world_pos.x / ZoneCatalog.TILE_PX), floori(world_pos.y / ZoneCatalog.TILE_PX)) - slot_origin_tile
	for dy: int in range(-pad_tiles, pad_tiles + 1):
		for dx: int in range(-pad_tiles, pad_tiles + 1):
			var c: Vector2i = center + Vector2i(dx, dy)
			if not in_zone_tile(c):
				return false
			if water_depth_grid[_idx(c)] > 0.02:
				return false
	return true


func unload_from_world(ground_layer: TileMapLayer, glow_layer: TileMapLayer, world_things: Dictionary, active_props_parent: Node) -> void:
	for cell: Vector2i in painted_cells:
		if ground_layer != null:
			ground_layer.erase_cell(cell)
	for cell: Vector2i in glow_cells:
		if glow_layer != null:
			glow_layer.erase_cell(cell)
	for dec: Node in decals:
		Terrain.patches.erase(dec)
	for cell: Variant in things.keys():
		var thing: Node = things[cell] as Node
		world_things.erase(cell)
		if is_instance_valid(thing):
			if thing.get_parent() == active_props_parent:
				active_props_parent.remove_child(thing)
			thing.queue_free()
	things.clear()
	for enemy: Node2D in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	for critter: Node2D in wildlife:
		if is_instance_valid(critter):
			critter.queue_free()
	wildlife.clear()
	for poi: Node in poi_nodes:
		if is_instance_valid(poi):
			if poi.get_parent() == active_props_parent:
				active_props_parent.remove_child(poi)
			poi.queue_free()
	poi_nodes.clear()
	if is_instance_valid(fallen_knight):
		fallen_knight.queue_free()
	if is_instance_valid(hut_node):
		hut_node.queue_free()
	if is_instance_valid(cover_node):
		cover_node.queue_free()
	queue_free()
