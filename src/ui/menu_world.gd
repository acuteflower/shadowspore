extends Node2D
## Lightweight v2 backdrop world for `MainMenu`: Valdric's renewed hut yard and campfire at night with no player
## and no `WorldLevel` dependency. Explicitly NOT in the `"world"` group.


class _MenuMapStub extends RefCounted:
	var world_seed: int = 9


var _map: _MenuMapStub = _MenuMapStub.new()
var _hut: Hut
var _wind: WorldWind
var _ground: TileMapLayer
var _glow: TileMapLayer


func _ready() -> void:
	y_sort_enabled = true

	var ground_mat: ShaderMaterial = ShaderMaterial.new()
	ground_mat.shader = load("res://assets/shaders/ground_tone.gdshader") as Shader
	_ground = TileMapLayer.new()
	_ground.name = "Ground"
	_ground.z_index = -10
	_ground.tile_set = load("res://src/world/tileset.tres") as TileSet
	_ground.material = ground_mat
	_paint_clearing()
	add_child(_ground)

	var glow_mat: ShaderMaterial = ShaderMaterial.new()
	glow_mat.shader = load("res://assets/shaders/glow_layer.gdshader") as Shader
	_glow = TileMapLayer.new()
	_glow.name = "Glow"
	_glow.z_index = -9
	_glow.tile_set = load("res://src/world/glow_tileset.tres") as TileSet
	_glow.material = glow_mat
	add_child(_glow)

	var day_night: DayNight = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)

	var surfaces: GroundSurfaces = GroundSurfaces.new()
	surfaces.name = "GroundSurfaces"
	surfaces.z_index = -9
	surfaces.setup(Rect2(-512.0, -320.0, 1024.0, 640.0), 2.0)
	surfaces.commit()
	add_child(surfaces)

	var grass: LivingGrass = LivingGrass.new()
	grass.name = "LivingGrass"
	grass.y_sort_enabled = true
	grass.setup_rect(Rect2(-480.0, -280.0, 960.0, 560.0), 9, false, surfaces)
	add_child(grass)

	var fireflies: Fireflies = Fireflies.new()
	fireflies.name = "Fireflies"
	add_child(fireflies)

	_wind = WorldWind.new()
	_wind.name = "WorldWind"
	_wind.setup(self)
	add_child(_wind)

	_hut = Hut.new()
	_hut.name = "Hut"
	_hut.art = "hut"
	_hut.interior_id = "hut"
	_hut.yard_props = _hut_yard_props()
	add_child(_hut)
	_hut.set_renewed(true)


func _paint_clearing() -> void:
	var tiles: Dictionary = DataRegistry.table("grass_tiles")
	var plain: Array = tiles.get("plain", [[0, 0]]) as Array
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	for y: int in range(-18, 18):
		for x: int in range(-30, 30):
			var atlas: Array = plain[rng.randi() % plain.size()] as Array
			_ground.set_cell(Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))


func _hut_yard_props() -> Array:
	return [
		{
			"id": "pit", "tex": "yard_pit.png", "pos": [34, 64], "feet": 46, "glow": true,
			"solid": [34, 14, -17, -11], "ash": 24,
			"anim": {"tex": "yard_fire.png", "frames": 8, "fps": 11, "at": [0, 0], "feet": 27},
			"light": {"color": "ff9448", "radius": 96, "squash": 0.7, "energy": 1.4, "at": [0, -6], "flicker": 0.35},
			"sparks": true, "smoke": true, "sound": "fire.wav",
		},
		{"id": "block", "tex": "yard_block.png", "pos": [94, 40], "feet": 50, "solid": [22, 10, -11, -8], "chips": 22},
		{"id": "barrel", "tex": "yard_barrel.png", "pos": [-58, 26], "feet": 46, "glow": true, "solid": [20, 10, -16, -8]},
		{
			"id": "line", "tex": "yard_line.png", "pos": [78, 16], "feet": 70, "glow": true,
			"solid": [6, 4, 30, -3],
			"layers": [{"tex": "yard_rags.png", "sway": {"pivot": 24, "dir": 1, "amount": 5.5, "flutter": 0.8, "cell": 11}}],
		},
		{"id": "seat_s", "tex": "yard_seats.png", "frames": 4, "frame": 0, "pos": [34, 92], "feet": 26, "solid": [32, 7, -16, -6]},
		{"id": "seat_e", "tex": "yard_seats.png", "frames": 4, "frame": 1, "pos": [84, 64], "feet": 26, "solid": [12, 6, -6, -4]},
		{"id": "bedroll", "tex": "yard_bedroll.png", "pos": [-40, 82], "feet": 28, "solid": [10, 6, -5, -4]},
	]


func fire_world() -> Vector2:
	return (_hut.global_position if _hut != null else Vector2.ZERO) + Vector2(34.0, 64.0)


func _land_biome(_tile: Vector2i) -> String:
	return "meadow"
