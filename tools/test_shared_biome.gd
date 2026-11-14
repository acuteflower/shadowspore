extends Node
## One shared biome for the five old territories (the Hexenwald is a biome of its own, see test_hexenwald), independent names; retain terrain physics and authored placements.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass

var _checks: int = 0
var _failures: int = 0

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("SHARED BIOME: " + message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = DataRegistry.table("world_map")
	var map: RegionMap = RegionMap.new(0, data)
	var names: Array[String] = []
	for area: Dictionary in map.supers:
		names.append(map.area_name(int(area.id)))
		for id: int in area.regions:
			if int(area.id) < 5:
				_check(map.biome_at(map.anchor(id)) == "meadow", "region %d uses meadow" % id)
	_check(names.size() == 7 and names.has("Hexenwald") and names.has("Sonnenquarz-Öde") and names.has("Die Lichtung") and names.has("Nebelwald") and names.has("Glasklippen") and names.has("Versunkene Ruinen") and names.has("Das Leerenblühen"), "all area names survive including Sonnenquarz-Öde")
	var roundtrip: RegionMap = RegionMap.new(0, map.to_data())
	_check(roundtrip.to_data() == map.to_data(), "serialization preserves area names, topology and biome policy")
	_check(map.biome_at(Vector2i.ZERO).is_empty(), "outside the island stays outside the biome")
	var original: Image = Relief.TEXTURE.get_image()
	original.convert(Image.FORMAT_RGBA8)
	var old: PackedByteArray = original.get_data()
	Relief.town_styles = false ## Hallgrat's stone (data/hallgrat.json style_areas) is the one deliberate exception, checked by tools/test_hallgrat.tscn
	var relief: Relief = Relief.new()
	Relief.town_styles = true
	var geometry: bool = true
	var materials: bool = true
	for i: int in range(0, old.size(), 4):
		geometry = geometry and old[i] == relief._bytes[i] and (old[i+1] & 15) == (relief._bytes[i+1] & 15) and old[i+2] == relief._bytes[i+2] and (old[i+3] == 0) == (relief._bytes[i+3] == 0)
		if old[i+3] != 0:
			materials = materials and (relief._bytes[i+3] == 200 and (relief._bytes[i+1] >> 4) < 2 or relief._bytes[i+3] == 205 and (relief._bytes[i+1] >> 4) == 5 or relief._bytes[i+3] == 206 and (relief._bytes[i+1] >> 4) == 6)
	_check(geometry, "every height, connector kind, geometry byte and land flag is unchanged")
	_check(materials, "old land uses meadow with grass/rock materials, the Hexenwald its slate")
	var block: Image = Relief.BLOCK.get_image()
	block.convert(Image.FORMAT_L8)
	_check(relief._block == block.get_data(), "collision bake stays exact")
	var anchor: Vector2i = map.anchor(int((map.supers[1].regions as Array)[0]))
	relief.editor_apply({WorldEdits.key(anchor): {"biome": "glass_cliffs"}})
	_check(relief._at(anchor.x, anchor.y, 3) == 200, "legacy editor biome patches follow the shared biome")
	var signature: String = WorldEdits.map_signature()
	print("SHARED BIOME LAYOUT: ", signature)
	var renamed: Dictionary = data.duplicate(true)
	(renamed.supers[0] as Dictionary)["name"] = "A NEW NAME"
	renamed["biome"] = "mist_forest"
	_check(WorldEdits.map_signature(renamed) == signature, "names and biome metadata do not invalidate placed objects")
	(renamed.regions[0] as Dictionary)["center"] = [100, 100]
	_check(WorldEdits.map_signature(renamed) != signature, "real layout changes invalidate placements")
	_check(not WorldEdits.compatible_map("unrelated-world"), "unrelated legacy worlds stay rejected")
	for previous: Dictionary in data.get("editor_compatible_maps", []):
		_check(WorldEdits.compatible_map(String(previous.hash)), "previous editor save format remains accepted")
		var path: String = OS.get_temp_dir().path_join("shadowspore-shared-biome-edits.json")
		var payload: Dictionary = {"version": 1, "map": previous.hash, "props": {"10,10": {"kind": "tree", "variant": 3}}, "terrain": {"10,10": {"ground": "plain", "biome": "glass_cliffs"}}}
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(payload))
		file.close()
		var loaded: WorldEdits = WorldEdits.new()
		loaded.read(path)
		_check(JSON.parse_string(JSON.stringify(loaded.props)) == JSON.parse_string(JSON.stringify(payload.props)) and JSON.parse_string(JSON.stringify(loaded.terrain)) == JSON.parse_string(JSON.stringify(payload.terrain)), "legacy props and terrain load without rewriting the save")
		DirAccess.remove_absolute(path)
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	world.get_node("Wildlife").process_mode = Node.PROCESS_MODE_DISABLED
	for loaded: Vector2i in world._chunks.keys(): world._unload_chunk(loaded)
	for area: Dictionary in map.supers:
		if int(area.id) >= 5:
			continue
		var at: Vector2i = map.anchor(int((area.regions as Array)[0]))
		_check(world._land_biome(at) == "meadow", "world habitat in " + map.area_name(int(area.id)))
		var cell: Vector2i = at / WorldLevel.CHUNK
		world._load_chunk(cell)
		_check(world._chunks[cell].cells.has("meadow") and world._chunks[cell].cells.keys().all(func(k: String) -> bool: return k == "meadow" or map.own_biomes.has(k)), "full meadow ground painted in " + map.area_name(int(area.id)))
		world._unload_chunk(cell)
		await get_tree().process_frame
	for id: String in DataRegistry.table("biomes"):
		_check(world._layers[id] == world._ground, "legacy layer %s resolves to the same meadow ground" % id)
	var window: MapWindow = MapWindow.new()
	add_child(window)
	window._load_data()
	_check(window._area_names == names, "map keeps territory names independently of its biome palette")
	_check(window._area_colors.slice(0, 5).all(func(color: Color) -> bool: return color == Color(String(DataRegistry.get_entry("biomes", "meadow").color))), "the five old map areas share one colour")
	var area_biomes: PackedInt32Array = window._material.get_shader_parameter("area_biomes")
	_check(area_biomes == PackedInt32Array([0, 0, 0, 0, 0, 5, 6]), "the five old shader territories use meadow symbols and palette, the Hexenwald and Sonnenquarz-Öde their own")
	var texture: Texture2D = window._material.get_shader_parameter("areas") as Texture2D
	var area_image: Image = texture.get_image()
	var borders: bool = true
	for y: int in MapDiscovery.GRID:
		for x: int in MapDiscovery.GRID:
			borders = borders and area_image.get_pixel(x, y).r8 == map.super_at(Vector2i(x, y) * RegionMap.CELL + Vector2i(2, 2)) + 1
	_check(borders, "every area-boundary texel follows the original region grid")
	var discovery: MapDiscovery = window._discovery
	discovery.set_process(false)
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(MapDiscovery.GRID * MapDiscovery.GRID)
	for area_id: int in [0, 1]:
		var tile: Vector2i = map.anchor(int((map.supers[area_id].regions as Array)[0])) / RegionMap.CELL
		seen[tile.y * MapDiscovery.GRID + tile.x] = 1
	discovery.import_data(seen.compress(FileAccess.COMPRESSION_ZSTD))
	_check(window._seen_by_area[0] == 1 and window._seen_by_area[1] == 1 and window._seen_by_area[2] == 0, "discovery progress stays separate for each named territory")
	window.queue_free()
	world.queue_free()
	await get_tree().process_frame
	print("SHARED BIOME: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
