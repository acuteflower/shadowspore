extends Node
## Ground surfaces. Ground TileMapLayers register themselves; every tile carries a "surface"
## custom-data string (see world/tileset.tres) whose speed multiplier lives in data/terrain.json.
## Later layers win, so a path or bed layer on top of the ground overrides it.

const SURFACE_DATA: String = "surface"
const DEFAULT_SURFACE: String = "grass"

var relief: Relief ## the world's height levels (set by the world level): stairs and slopes have their own surfaces
var patches: Array[Node] = [] ## things that paint their own surface (`surface_at(pos) -> String`, "" = none): the ground decals (stone, footpath)
var _layers: Array[TileMapLayer] = []


func register_layer(layer: TileMapLayer) -> void:
	_layers.append(layer)
	layer.tree_exiting.connect(func() -> void: _layers.erase(layer))


func surface_at(world_pos: Vector2) -> String:
	var surface: String = DEFAULT_SURFACE
	for layer: TileMapLayer in _layers:
		var data: TileData = layer.get_cell_tile_data(layer.local_to_map(layer.to_local(world_pos)))
		if data != null:
			var id: String = data.get_custom_data(SURFACE_DATA)
			if id != "":
				surface = id
	for patch: Node in patches:
		var own: String = String(patch.call("surface_at", world_pos))
		if own != "":
			surface = own
	if relief != null:
		var stepped: String = relief.surface_at(world_pos)
		if stepped != "":
			surface = stepped
	return surface


func surface_data(surface: String) -> Dictionary:
	return DataRegistry.get_entry("terrain", surface)


func speed_multiplier_at(world_pos: Vector2) -> float:
	return float(DataRegistry.get_entry("terrain", surface_at(world_pos)).get("speed", 1.0))
