extends Node
## The Hexenwald, stage 1 (docs/hexenwald_konzept.md): own biome and area on the frozen map, soft palette field, no props, dark grass ground, map entry.
## Run: Godot --headless --path . tools/test_hexenwald.tscn   (the baked data itself: python3 tools/test_hexenwald_bake.py)
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass

var _checks: int = 0
var _failures: int = 0
const HUT: Vector2i = Vector2i(786, 676)
const CENTRE: Vector2i = Vector2i(821, 892)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("HEXENWALD: " + message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = DataRegistry.table("world_map")
	var map: RegionMap = RegionMap.new(0, data)
	_check(map.supers.size() == 6 and map.regions.size() == 32, "six areas, 32 regions")
	_check(map.own_biomes.size() == 1 and map.own_biomes[0] == "witch_forest", "own biomes are read")
	_check(map.biome_at(CENTRE) == "witch_forest" and map.biome_at(HUT) == "meadow", "the Hexenwald has its own biome, the town stays meadow")
	_check(map.area_name(5) == "Hexenwald" and map.super_at(CENTRE) == 5 and map.region_at(CENTRE) == 31, "area 5 / region 31")
	_check(RegionMap.active_biome("witch_forest") == "witch_forest" and RegionMap.active_biome("glass_cliffs") == "meadow", "legacy biome ids still fold into meadow, the Hexenwald does not")
	_check(RegionMap.new(0, map.to_data()).to_data() == map.to_data(), "serialization keeps the own biome")
	var bare: PackedByteArray = map.bare_cells()
	var bare_ok: bool = true
	for i: int in bare.size():
		bare_ok = bare_ok and (bare[i] == 1) == (map.region_at(Vector2i(i % map.grid_size, i / map.grid_size) * RegionMap.CELL) == 31)
	_check(bare_ok, "exactly the cells of region 31 carry no props")
	# the palette field
	var blend: PackedFloat32Array = BiomeBlend.compute(map)
	var side: int = map.grid_size
	var pure: bool = true
	var smooth: bool = true
	for i: int in side * side:
		var id: int = map.region_at(Vector2i(i % side, i / side) * RegionMap.CELL)
		if id >= 0 and id != 31:
			pure = pure and blend[i] == 0.0
		if i % side < side - 1 and id == 31 and map.region_at(Vector2i(i % side + 1, i / side) * RegionMap.CELL) >= 0:
			smooth = smooth and absf(blend[i] - blend[i + 1]) < 0.3
	_check(pure, "the field is exactly 0 on every old land cell: nothing existing changes colour")
	_check(smooth, "no hard step in the field inside the land")
	_check(blend[(CENTRE.y / RegionMap.CELL) * side + CENTRE.x / RegionMap.CELL] > 0.99, "deep inside the field is full")
	var ramp: PackedFloat32Array = PackedFloat32Array()
	for y: int in range(790, 893, 8):
		ramp.append(blend[(y / RegionMap.CELL) * side + CENTRE.x / RegionMap.CELL])
	var rising: bool = true
	for k: int in range(1, ramp.size()):
		rising = rising and ramp[k] >= ramp[k - 1] - 0.001
	_check(rising and ramp[0] < 0.2 and ramp[ramp.size() - 1] > 0.9, "walking south the palette grows from meadow to Hexenwald (%s)" % str(ramp))
	BiomeBlend.install(map)
	_check(BiomeBlend.amount_at(Vector2(HUT) * 16.0) == 0.0 and BiomeBlend.amount_at(Vector2(CENTRE) * 16.0) > 0.99, "amount_at agrees")
	# relief bytes
	var relief: Relief = Relief.new()
	_check(relief._at(CENTRE.x, CENTRE.y, 3) == 205 and relief._at(CENTRE.x, CENTRE.y, 0) == 0 and (relief._at(CENTRE.x, CENTRE.y, 1) & 15) == Relief.FLOOR, "flat floor with the sixth biome byte")
	_check(relief._at(HUT.x, HUT.y, 3) == 200, "the old land keeps meadow")
	_check(relief.flat_around(Vector2(CENTRE) * 16.0, 30.0), "the Hexenwald floor is flat")
	# the world
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	world.get_node("Wildlife").process_mode = Node.PROCESS_MODE_DISABLED
	for loaded: Vector2i in world._chunks.keys(): world._unload_chunk(loaded)
	_check(world._land_biome(CENTRE) == "witch_forest" and world._land_biome(HUT) == "meadow", "the level reads the biomes")
	_check(world._layers["witch_forest"] == world._ground, "the Hexenwald is painted on the shared ground layer (its palette comes from the shader)")
	var props: int = 0
	var foreign: int = 0 ## a meadow plant in the Hexenwald, or one of its plants outside
	var kinds: Dictionary = {}
	var meadow_props: int = 0
	var unbare: PropGenerator = world._generator.fork()
	unbare.bare = PackedByteArray()
	var would: int = 0
	for cy: int in range(24, 33):
		for cx: int in range(21, 31):
			var rect: Rect2i = Rect2i(Vector2i(cx, cy) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				var cell: Vector2i = entry.cell
				if String(entry.kind) == "stonebed" or String(entry.kind) == "forestbed":
					continue
				if world._generator.is_bare(cell) != (PropGenerator.WITCH_KINDS.has(String(entry.kind)) or (PropGenerator.WITCH_SHARED.has(String(entry.kind)) and world._generator.is_bare(cell))):
					foreign += 1
				if world._generator.is_bare(cell):
					props += 1
					kinds[String(entry.kind)] = int(kinds.get(String(entry.kind), 0)) + 1
				else:
					meadow_props += 1
			for entry: Dictionary in unbare.props_for_chunk(rect):
				if world._generator.is_bare(entry.cell) and not PropGenerator.WITCH_KINDS.has(String(entry.kind)) and not PropGenerator.WITCH_SHARED.has(String(entry.kind)):
					would += 1
	_check(would > 200, "without the rule the area would grow props (%d), so the check means something" % would)
	print("HEXENWALD props: %d in the sampled chunks, per kind %s" % [props, kinds])
	_check(props > 300 and kinds.size() == PropGenerator.WITCH_KINDS.size() + 1, "the Hexenwald grows every kind of its own plant world and the meadow bush (%d props, %d kinds)" % [props, kinds.size()])
	_check(foreign == 0, "no meadow plant in the Hexenwald and none of its plants outside (%d)" % foreign)
	_check(meadow_props > 0, "the meadow around it still grows its props (%d)" % meadow_props)
	# ground and details of real chunks
	var tuft: int = 0
	var plain: int = 0
	for c: Vector2i in [Vector2i(25, 27), Vector2i(26, 28)]:
		world._load_chunk(c)
		for _frame: int in 8:
			await get_tree().process_frame
		_check(world._chunks.has(c), "chunk %s loads" % str(c))
		if world._chunks.has(c):
			var chunk: Variant = world._chunks[c]
			_check(chunk.cells.has("witch_forest"), "chunk %s paints Hexenwald ground" % str(c))
			_check(chunk.clover.is_empty() and not chunk.things.is_empty(), "chunk %s has no clover, but the Hexenwald's own plants" % str(c))
			var plain_set: Array = []
			for option: Variant in (world._tiles["plain"] as Array):
				plain_set.append(Vector2i(int((option as Array)[0]), int((option as Array)[1])))
			for dy: int in WorldLevel.CHUNK:
				for dx: int in WorldLevel.CHUNK:
					var cell: Vector2i = c * WorldLevel.CHUNK + Vector2i(dx, dy)
					if world._land_at(cell.x, cell.y) and map.biome_at(cell) == "witch_forest":
						if plain_set.has(world._ground.get_cell_atlas_coords(cell)): plain += 1
						else: tuft += 1
		world._unload_chunk(c)
	var logs: int = 0
	for cy: int in range(24, 33):
		for cx: int in range(21, 31):
			for index: int in 16:
				var spec: Dictionary = FallenLogScatter.candidate(world, Vector2i(cx, cy), index, [] as Array[Dictionary])
				if not spec.is_empty() and world._generator.is_bare(Vector2i((spec.pos as Vector2) / 16.0)):
					logs += 1
	_check(logs == 0, "no fallen trunk is placed in the Hexenwald (%d)" % logs)
	_check(plain + tuft > 500 and float(tuft) / float(maxi(plain + tuft, 1)) < 0.2, "mostly plain grass tiles with a few tufts (%d plain, %d other)" % [plain, tuft])
	# the map
	var window: MapWindow = MapWindow.new()
	add_child(window)
	window._load_data()
	_check(window._area_names.has("Hexenwald") and window._area_colors.size() == 6, "the map names the area")
	_check((window._material.get_shader_parameter("area_biomes") as PackedInt32Array)[5] == 5, "the map paints it with the sixth palette")
	_check((window._material.get_shader_parameter("pal") as PackedVector3Array).size() == 18, "six palettes")
	window.queue_free()
	world.queue_free()
	await get_tree().process_frame
	print("HEXENWALD: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
