class_name GrassLab
extends "res://src/world/test_level.gd"
## 3-Square Connected Ground & Foliage Studio (72x18 tiles = 1152x288 px):
##   Square 1 (West,   x = -192..+192): Living Meadow — LivingGrass v3, blossom carpets & 2-zone trails
##   Square 2 (Center, x = +192..+576): Paths & Antique Stone Slabs — dirt path, gravel track, damp moss trail,
##                                      hero moon-ring rondell, weathered flagstones, stepping stones & ruins
##   Square 3 (East,   x = +576..+960): Woodland Floor — dark humus, fallen leaves, plush moss carpets,
##                                      creeping roots, damp earth, mud margins, mirror woodland puddles & mushrooms
##
## Run live:    Godot --path . res://tools/grass_lab.tscn
## Capture QA:  Godot --rendering-driver opengl3 --path . --fixed-fps 60 res://tools/grass_lab.tscn -- --capture=/Users/nxye/voidbloom/docs/img/ground_studio_v1
## Headless QA: Godot --headless --path . --fixed-fps 60 res://tools/grass_lab.tscn -- --test

const TREE_SCENE: PackedScene = preload("res://src/entities/props/living_tree.tscn")
const COASTAL_PROPS_TEX_PATH: String = "res://assets/tiles/coastal_props.png"
const COASTAL_PROPS_GLOW_PATH: String = "res://assets/tiles/coastal_props_glow.png"
const SQUARE_TILES: Rect2i = Rect2i(-84, -9, 192, 18) ## 8 connected 24x18 squares (-3..+5) = 3072x288 px
const BIRCH_TILES: Rect2i = Rect2i(60, -27, 24, 18)   ## Square 4N (2nd Tree Square directly north of Square 4: 384x288 px at x=960..1344, y=-432..-144)
const APPLE_TILES: Rect2i = Rect2i(60, 9, 24, 18)     ## Square 4S (3rd Tree Square directly south of Square 4: 384x288 px at x=960..1344, y=+144..+432)
const SQ_NEG3_CENTER: Vector2 = Vector2(-1120.0, 0.0)
const SQ_NEG2_CENTER: Vector2 = Vector2(-708.0, 0.0)
const SQ_NEG1_CENTER: Vector2 = Vector2(-384.0, 0.0)
const SQ1_CENTER: Vector2 = Vector2(0.0, 0.0)
const SQ2_CENTER: Vector2 = Vector2(384.0, 12.0)
const SQ3_CENTER: Vector2 = Vector2(768.0, 8.0)
const SQ4_CENTER: Vector2 = Vector2(1152.0, 12.0)
const SQ4N_CENTER: Vector2 = Vector2(1152.0, -288.0)
const SQ4S_CENTER: Vector2 = Vector2(1152.0, 288.0)
const SQ5_CENTER: Vector2 = Vector2(1536.0, 12.0)

const TIME_PRESETS: Array[Dictionary] = [
	{"name": "MITTAG (0.50)", "t": 0.50, "tag": "noon"},
	{"name": "ABENDGOLD (0.74)", "t": 0.74, "tag": "golden"},
	{"name": "MORGEN / TAU (0.27)", "t": 0.27, "tag": "morning"},
	{"name": "NACHT (0.00)", "t": 0.00, "tag": "night"},
]
const WEATHER_PRESETS: Array[Dictionary] = [
	{"name": "KLAR / RUHIG", "id": "clear", "wind": 0.25},
	{"name": "BRISE", "id": "broken", "wind": 0.62},
	{"name": "REGEN / PFÜTZEN", "id": "rain", "wind": 0.68},
	{"name": "STURM", "id": "storm", "wind": 0.95},
]
const LAYER_MODES: Array[String] = [
	"VOLL (BODEN + LIVING GRASS)",
	"NUR BODEN & STEINE (OHNE GRAS)",
	"LIVING GRASS + SPUREN-DEBUG",
]
const SYNTH_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"sprint", &"sneak", &"shadow_step", &"action_primary", &"action_secondary",
]

class LabMapStub:
	extends RefCounted
	var world_seed: int = 42

var _map: LabMapStub = LabMapStub.new()
var _wind: WorldWind
var _surfaces: GroundSurfaces
var _birch_surfaces: GroundSurfaces
var _apple_surfaces: GroundSurfaces
var _water_field: WaterField
var _water_bridge: WaterBridge
var _water_ambience: WaterAmbience
var _grass: LivingGrass
var _birch_grass: LivingGrass
var _apple_grass: LivingGrass
var _player: Player
var _trees_root: Node2D
var _trees: Array[LivingTree] = []
var _birches: Array[LivingTree] = []
var _apples: Array[LivingTree] = []
var _oak_matriarch: LivingTree
var _oak_mature: LivingTree
var _oak_pole: LivingTree
var _birch_mother: LivingTree
var _birch_clump: LivingTree
var _birch_solitary: LivingTree
var _apple_mother: LivingTree
var _apple_fruiting: LivingTree
var _apple_zwiesel: LivingTree
var _apple_phenology_cycle: int = 0
var _autumn_mode: bool = false
var _holding_axe: bool = false
var _holding_pickaxe: bool = false
var _rock_builder: RockSquareBuilder
var _rocky_ground: RockyGround
var _flora_field: LivingFloraField
var _holding_sickle: bool = false
var _flora_capture_only: bool = false
var _water_debug: bool = false
var _coastal_glow_sprites: Array[Sprite2D] = []
var _last_coastal_night: float = -1.0

var _time_idx: int = 0
var _weather_idx: int = 0
var _layer_mode: int = 0
var _zoom_macro: bool = false
var _show_ui: bool = true
var _show_game_hud: bool = false

var _demo_active: bool = true
var _demo_phase: String = "START"
var _demo_run_id: int = 0
var _capture_dir: String = ""
var _test_mode: bool = false
var _capture_only: bool = false
var _water_capture_only: bool = false
var _tree_capture_only: bool = false
var _birch_capture_only: bool = false
var _apple_capture_only: bool = false
var _rock_capture_only: bool = false
var _paths_capture_only: bool = false
var _spider_capture_only: bool = false
var _finisher_capture_only: bool = false
var _lab_spiders: Array[ShadowSpider] = []
var _next_brood_variant: int = 0
var _last_hud_surface: String = ""
var _last_hud_zone: String = ""

var _ui_layer: CanvasLayer
var _status_label: Label
var _help_label: Label
var _bg_matte: ColorRect

var _metrics: Dictionary = {
	"tuft_density": false,
	"glow_layer": false,
	"floral_petals": false,
	"toroidal_recenter": false,
	"slabs_placed": false,
	"forest_details_placed": false,
	"trees_placed": false,
	"crown_shyness": false,
	"birches_placed": false,
	"birch_crown_shyness": false,
	"apples_placed": false,
	"apple_crown_shyness": false,
	"surface_grass": false,
	"surface_path": false,
	"surface_gravel": false,
	"surface_ancient_stone": false,
	"surface_forest_floor": false,
	"surface_moss": false,
	"surface_damp_earth": false,
	"surface_mud": false,
	"surface_puddle": false,
	"idle": false,
	"walk": false,
	"walk_crush": false,
	"trail_persists": false,
	"sneak": false,
	"sprint": false,
	"sprint_crush": false,
	"shadow_step": false,
	"step_burst": false,
	"combo": false,
	"slash_wave": false,
	"heavy": false,
	"water_brook_regime": false,
	"water_ford_wade": false,
	"water_bridge_deck": false,
	"water_coastal_swash_sync": false,
	"water_ocean_swim": false,
	"water_puddles_r5": false,
	"water_ringbuffer_sleep": false,
	"water_night_glow": false,
	"water_weather_breeze": false,
	"water_perf_60fps": false,
	"rock_outcrops_placed": false,
	"rock_surfaces_active": false,
	"sanctuary_ruins_placed": false,
	"sanctuary_flora_28": false,
}


func _ready() -> void:
	add_to_group("sandbox")
	_parse_args()
	_build_matte_and_walls()
	super._ready()
	_setup_wind_and_foliage()
	_setup_studio_ui()
	_apply_time(0)
	_apply_weather(0)
	_apply_layer_mode(0)
	_prepare_player.call_deferred()


func _exit_tree() -> void:
	_release_all_synth()
	TimeManager.unlock()


func _process(delta: float) -> void:
	super._process(delta)
	_sync_coastal_glow()
	if _player != null and is_instance_valid(_player) and not _capture_only:
		var surf: String = Terrain.surface_at(_player.global_position)
		var zone: String = _zone_label_at(_player.global_position)
		if surf != _last_hud_surface or zone != _last_hud_zone:
			_last_hud_surface = surf
			_last_hud_zone = zone
			_update_ui_text()


func _zone_label(wx: float) -> String:
	return _zone_label_at(Vector2(wx, 0.0))


func _zone_label_at(pos: Vector2) -> String:
	var wx: float = pos.x
	if wx < -960.0:
		return "-3 · OFFENE SEE"
	if wx < -576.0:
		return "-2 · STRAND & KÜSTE"
	if wx < -192.0:
		return "-1 · WALDBACH & BRÜCKE"
	if wx < 192.0:
		return "1 · WIESE"
	if wx < 576.0:
		return "2 · PFADE & STEINE"
	if wx < 960.0:
		return "3 · WALDBODEN"
	if wx >= 1344.0:
		return "6 · GLIMMTAL-STEINHANG"
	if pos.y < -144.0:
		return "5 · BIRKENLICHTUNG"
	if pos.y > 144.0:
		return "7 · WILDAPFEL-AUE"
	return "4 · GLIMMTAL-HAIN"


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--water-capture="):
			_capture_dir = arg.trim_prefix("--water-capture=")
			_water_capture_only = true
			_test_mode = true
		elif arg.begins_with("--tree-capture="):
			_capture_dir = arg.trim_prefix("--tree-capture=")
			_tree_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--birch-capture="):
			_capture_dir = arg.trim_prefix("--birch-capture=")
			_birch_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--apple-capture="):
			_capture_dir = arg.trim_prefix("--apple-capture=")
			_apple_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--rock-capture="):
			_capture_dir = arg.trim_prefix("--rock-capture=")
			_rock_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--paths-capture="):
			_capture_dir = arg.trim_prefix("--paths-capture=")
			_paths_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--spider-capture="):
			_capture_dir = arg.trim_prefix("--spider-capture=")
			_spider_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--finisher-capture="):
			_capture_dir = arg.trim_prefix("--finisher-capture=")
			_finisher_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg.begins_with("--flora-capture="):
			_capture_dir = arg.trim_prefix("--flora-capture=")
			_flora_capture_only = true
			_capture_only = true
			_test_mode = true
		elif arg == "--test":
			_test_mode = true
		elif arg == "--manual":
			_demo_active = false


func _land_biome(_tile: Vector2i) -> String:
	return "meadow"


func navigation_floor(_pos: Vector2) -> bool:
	return true


func _spawn_position(_index: int) -> Vector2:
	return Vector2.ZERO


func _clamp_spawn(pos: Vector2) -> Vector2:
	if pos.x >= 960.0 and pos.x < 1344.0 and (pos.y < -144.0 or pos.y > 144.0):
		var axis_rect: Rect2 = Rect2(960.0, -432.0, 384.0, 864.0).grow(-18.0)
		return pos.clamp(axis_rect.position, axis_rect.end)
	var rect: Rect2 = Rect2(Vector2(SQUARE_TILES.position) * 16.0, Vector2(SQUARE_TILES.size) * 16.0).grow(-18.0)
	return pos.clamp(rect.position, rect.end)


## Paints the calm, velvety mossy-meadow base turf across all connected squares + Birch Clearing + Wild-Apple Meadow.
func _fill_ground() -> void:
	var tiles: Dictionary = DataRegistry.table("grass_tiles")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	for y: int in range(SQUARE_TILES.position.y, SQUARE_TILES.end.y):
		for x: int in range(SQUARE_TILES.position.x, SQUARE_TILES.end.x):
			var kind: String = _pick_lab_tile_kind(x, y, rng)
			var options: Array = tiles.get(kind, tiles["plain"]) as Array
			var atlas: Array = options[rng.randi() % options.size()] as Array
			_ground.set_cell(Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))
			if GLOW_KINDS.has(kind):
				_glow.set_cell(Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))
				_add_glow(Vector2i(x, y), kind, options.find(atlas))

	var brng: RandomNumberGenerator = RandomNumberGenerator.new()
	brng.seed = 4242
	for y: int in range(BIRCH_TILES.position.y, BIRCH_TILES.end.y):
		for x: int in range(BIRCH_TILES.position.x, BIRCH_TILES.end.x):
			var roll: float = brng.randf()
			var bkind: String = "petal" if roll < 0.04 else ("stone" if roll < 0.07 else "plain")
			var bopts: Array = tiles.get(bkind, tiles["plain"]) as Array
			var batlas: Array = bopts[brng.randi() % bopts.size()] as Array
			_ground.set_cell(Vector2i(x, y), 0, Vector2i(int(batlas[0]), int(batlas[1])))
			if GLOW_KINDS.has(bkind):
				_glow.set_cell(Vector2i(x, y), 0, Vector2i(int(batlas[0]), int(batlas[1])))
				_add_glow(Vector2i(x, y), bkind, bopts.find(batlas))

	var arng: RandomNumberGenerator = RandomNumberGenerator.new()
	arng.seed = 4343
	for y: int in range(APPLE_TILES.position.y, APPLE_TILES.end.y):
		for x: int in range(APPLE_TILES.position.x, APPLE_TILES.end.x):
			var roll: float = arng.randf()
			var akind: String = "bloom" if roll < 0.045 else ("petal" if roll < 0.095 else ("stone" if roll < 0.115 else "plain"))
			var aopts: Array = tiles.get(akind, tiles["plain"]) as Array
			var aatlas: Array = aopts[arng.randi() % aopts.size()] as Array
			_ground.set_cell(Vector2i(x, y), 0, Vector2i(int(aatlas[0]), int(aatlas[1])))
			if GLOW_KINDS.has(akind):
				_glow.set_cell(Vector2i(x, y), 0, Vector2i(int(aatlas[0]), int(aatlas[1])))
				_add_glow(Vector2i(x, y), akind, aopts.find(aatlas))


func _pick_lab_tile_kind(x: int, y: int, rng: RandomNumberGenerator) -> String:
	var roll: float = rng.randf()
	# Keep subtle under-turf accents strictly inside Square 1 (meadow, x in [-12, 12)); Squares -3..-1 & 2..4 stay clean!
	if x >= -12 and x < 12:
		if x > 4 and y > 2:
			if roll < 0.055:
				return "bloom"
			if roll < 0.11:
				return "mushroom"
			if roll < 0.16:
				return "stone"
		if x < -3 and y < -2 and roll < 0.10:
			return "petal"
	return "plain"


func _build_matte_and_walls() -> void:
	_bg_matte = ColorRect.new()
	_bg_matte.name = "StudioBackdrop"
	_bg_matte.z_index = -12
	_bg_matte.position = Vector2(-1700.0, -1050.0)
	_bg_matte.size = Vector2(4900.0, 2400.0)
	_bg_matte.color = Color("100d18")
	add_child(_bg_matte)

	var rect: Rect2 = Rect2(Vector2(SQUARE_TILES.position) * 16.0, Vector2(SQUARE_TILES.size) * 16.0)
	var brect: Rect2 = Rect2(Vector2(BIRCH_TILES.position) * 16.0, Vector2(BIRCH_TILES.size) * 16.0)
	var arect: Rect2 = Rect2(Vector2(APPLE_TILES.position) * 16.0, Vector2(APPLE_TILES.size) * 16.0)
	var border: Node2D = Node2D.new()
	border.name = "SquareFrame"
	border.z_index = -9
	add_child(border)
	var frame_color: Color = Color("1b1629")
	var tick_color: Color = Color("3c3457")
	var frame_rects: Array[Rect2] = [
		Rect2(rect.position.x - 2.0, rect.position.y - 2.0, brect.position.x - rect.position.x + 2.0, 2.0),
		Rect2(brect.position.x - 2.0, brect.position.y - 2.0, 2.0, rect.position.y - brect.position.y + 2.0),
		Rect2(brect.position.x - 2.0, brect.position.y - 2.0, brect.size.x + 4.0, 2.0),
		Rect2(brect.end.x, brect.position.y - 2.0, 2.0, rect.position.y - brect.position.y + 2.0),
		Rect2(brect.end.x, rect.position.y - 2.0, rect.end.x - brect.end.x + 2.0, 2.0),
		Rect2(rect.end.x, rect.position.y, 2.0, rect.size.y),
		Rect2(rect.position.x - 2.0, rect.end.y, arect.position.x - rect.position.x + 2.0, 2.0),
		Rect2(arect.position.x - 2.0, rect.end.y, 2.0, arect.end.y - rect.end.y + 2.0),
		Rect2(arect.position.x - 2.0, arect.end.y, arect.size.x + 4.0, 2.0),
		Rect2(arect.end.x, rect.end.y, 2.0, arect.end.y - rect.end.y + 2.0),
		Rect2(arect.end.x, rect.end.y, rect.end.x - arect.end.x + 2.0, 2.0),
		Rect2(rect.position.x - 2.0, rect.position.y, 2.0, rect.size.y),
	]
	for fr: Rect2 in frame_rects:
		var cr: ColorRect = ColorRect.new()
		cr.position = fr.position
		cr.size = fr.size
		cr.color = frame_color
		border.add_child(cr)

	for div_x: float in [-960.0, -576.0, -192.0, 192.0, 576.0, 960.0, 1344.0]:
		var top_y: float = (brect.position.y - 5.0) if (div_x >= 960.0 and div_x <= 1344.0) else (rect.position.y - 5.0)
		var bot_y: float = (arect.end.y + 1.0) if (div_x >= 960.0 and div_x <= 1344.0) else (rect.end.y + 1.0)
		for tick_y: float in [top_y, bot_y]:
			var tk: ColorRect = ColorRect.new()
			tk.position = Vector2(div_x - 1.0, tick_y)
			tk.size = Vector2(2.0, 4.0)
			tk.color = tick_color
			border.add_child(tk)
	for side_x: float in [brect.position.x - 5.0, brect.end.x + 1.0]:
		for seam_y: float in [rect.position.y - 1.0, rect.end.y - 1.0]:
			var tk_y: ColorRect = ColorRect.new()
			tk_y.position = Vector2(side_x, seam_y)
			tk_y.size = Vector2(4.0, 2.0)
			tk_y.color = tick_color
			border.add_child(tk_y)

	var body: StaticBody2D = StaticBody2D.new()
	body.name = "SquareWalls"
	body.collision_layer = 1
	var wall_rects: Array[Rect2] = [
		Rect2(rect.position.x - 16.0, rect.position.y - 16.0, brect.position.x - rect.position.x + 16.0, 16.0),
		Rect2(brect.position.x - 16.0, brect.position.y - 16.0, 16.0, rect.position.y - brect.position.y + 16.0),
		Rect2(brect.position.x - 16.0, brect.position.y - 16.0, brect.size.x + 32.0, 16.0),
		Rect2(brect.end.x, brect.position.y - 16.0, 16.0, rect.position.y - brect.position.y + 16.0),
		Rect2(brect.end.x, rect.position.y - 16.0, rect.end.x - brect.end.x + 16.0, 16.0),
		Rect2(rect.end.x, rect.position.y - 16.0, 16.0, rect.size.y + 32.0),
		Rect2(rect.position.x - 16.0, rect.end.y, arect.position.x - rect.position.x + 16.0, 16.0),
		Rect2(arect.position.x - 16.0, rect.end.y, 16.0, arect.end.y - rect.end.y + 16.0),
		Rect2(arect.position.x - 16.0, arect.end.y, arect.size.x + 32.0, 16.0),
		Rect2(arect.end.x, rect.end.y, 16.0, arect.end.y - rect.end.y + 16.0),
		Rect2(arect.end.x, rect.end.y, rect.end.x - arect.end.x + 16.0, 16.0),
		Rect2(rect.position.x - 16.0, rect.position.y, 16.0, rect.size.y),
	]
	for wr: Rect2 in wall_rects:
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rshape: RectangleShape2D = RectangleShape2D.new()
		rshape.size = wr.size
		shape.shape = rshape
		shape.position = wr.get_center()
		body.add_child(shape)
	add_child(body)


func _setup_wind_and_foliage() -> void:
	_wind = WorldWind.new()
	_wind.name = "WorldWind"
	_wind.setup(self)
	add_child(_wind)

	var rect: Rect2 = Rect2(Vector2(SQUARE_TILES.position) * 16.0, Vector2(SQUARE_TILES.size) * 16.0)
	var brect: Rect2 = Rect2(Vector2(BIRCH_TILES.position) * 16.0, Vector2(BIRCH_TILES.size) * 16.0)
	var arect: Rect2 = Rect2(Vector2(APPLE_TILES.position) * 16.0, Vector2(APPLE_TILES.size) * 16.0)
	_surfaces = GroundSurfaces.new()
	_surfaces.name = "GroundSurfaces"
	add_child(_surfaces)
	_birch_surfaces = GroundSurfaces.new()
	_birch_surfaces.name = "BirchGroundSurfaces"
	add_child(_birch_surfaces)
	_apple_surfaces = GroundSurfaces.new()
	_apple_surfaces.name = "AppleGroundSurfaces"
	add_child(_apple_surfaces)
	_build_ground_squares(rect)
	_build_birch_ground(brect)
	_build_apple_ground(arect)

	_setup_water_squares()
	_setup_rock_ground()

	_grass = LivingGrass.new()
	_grass.name = "LivingGrass"
	_grass.y_sort_enabled = true
	_grass.set_meadow_rect(Rect2(-192.0, rect.position.y, 384.0, rect.size.y))
	_grass.set_water_habitat_provider(_water_field)
	if _rocky_ground != null:
		_grass.add_habitat_provider(_rocky_ground)
	_grass.setup_rect(rect, 2026, true, _surfaces)
	add_child(_grass)

	_birch_grass = LivingGrass.new()
	_birch_grass.name = "BirchLivingGrass"
	_birch_grass.y_sort_enabled = true
	_birch_grass.set_meadow_rect(Rect2(-192.0, rect.position.y, 384.0, rect.size.y))
	_birch_grass.setup_rect(Rect2(brect.position.x, brect.position.y, brect.size.x, brect.size.y + 6.0), 2027, true, _birch_surfaces)
	add_child(_birch_grass)

	_apple_grass = LivingGrass.new()
	_apple_grass.name = "AppleLivingGrass"
	_apple_grass.y_sort_enabled = true
	_apple_grass.set_meadow_rect(arect)
	_apple_grass.setup_rect(Rect2(arect.position.x, arect.position.y - 6.0, arect.size.x, arect.size.y + 6.0), 2028, true, _apple_surfaces)
	add_child(_apple_grass)

	_build_tree_glade()
	_build_rock_outcrops()
	_build_sanctuary_flora()

	_metrics["tuft_density"] = _grass.tuft_count >= 1600
	_metrics["glow_layer"] = _grass.glow_tuft_count >= 350
	_metrics["floral_petals"] = _grass._floral_cells.size() >= 40
	_metrics["slabs_placed"] = _surfaces.slab_count >= 24
	_metrics["forest_details_placed"] = _surfaces.detail_count >= 45
	_verify_surface_probes()


func _setup_water_squares() -> void:
	_water_field = WaterField.new()
	_water_field.name = "WaterField"
	add_child(_water_field)
	_water_field.build_grass_lab_west()

	_water_bridge = WaterBridge.new()
	_water_bridge.name = "WaterBridge"
	_water_bridge.position = SQ_NEG1_CENTER
	add_child(_water_bridge)
	_water_bridge.bind_water_field(_water_field)

	_water_ambience = WaterAmbience.new()
	_water_ambience.name = "WaterAmbience"
	_water_ambience.bind_water_field(_water_field)
	add_child(_water_ambience)

	_build_coastal_props()


func _build_coastal_props() -> void:
	var base_tex: Texture2D = DataRegistry.tex(COASTAL_PROPS_TEX_PATH)
	var glow_tex: Texture2D = DataRegistry.tex(COASTAL_PROPS_GLOW_PATH)
	if base_tex == null:
		return

	var prop_shader: Shader = load("res://assets/shaders/coastal_prop_water.gdshader") as Shader
	var flat_mat: ShaderMaterial = null
	var ysort_mat: ShaderMaterial = null
	if prop_shader != null and _water_field != null:
		flat_mat = ShaderMaterial.new()
		flat_mat.shader = prop_shader
		flat_mat.set_shader_parameter("is_flat_prop", true)
		flat_mat.set_shader_parameter("map_origin", _water_field.bounds.position)
		flat_mat.set_shader_parameter("map_size", _water_field.bounds.size)
		flat_mat.set_shader_parameter("water_geo_map", _water_field.geo_texture())
		flat_mat.set_shader_parameter("water_flow_map", _water_field.flow_texture())

		ysort_mat = ShaderMaterial.new()
		ysort_mat.shader = prop_shader
		ysort_mat.set_shader_parameter("is_flat_prop", false)
		ysort_mat.set_shader_parameter("map_origin", _water_field.bounds.position)
		ysort_mat.set_shader_parameter("map_size", _water_field.bounds.size)
		ysort_mat.set_shader_parameter("water_geo_map", _water_field.geo_texture())
		ysort_mat.set_shader_parameter("water_flow_map", _water_field.flow_texture())

	var flat_root: Node2D = Node2D.new()
	flat_root.name = "CoastalPropsFlat"
	flat_root.z_as_relative = false
	flat_root.z_index = -5
	add_child(flat_root)

	var ysort_root: Node2D = Node2D.new()
	ysort_root.name = "CoastalPropsYSort"
	ysort_root.z_as_relative = false
	ysort_root.z_index = 0
	ysort_root.y_sort_enabled = true
	add_child(ysort_root)

	# Exact 28-cell rects & foot offsets from tools/art_coastal_biome.py (M1 contract)
	var defs: Array[Dictionary] = [
		{"r": Rect2(0, 0, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},     # 0 lily_cluster_0
		{"r": Rect2(32, 0, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},    # 1 lily_cluster_1
		{"r": Rect2(64, 0, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},    # 2 lily_cluster_2
		{"r": Rect2(96, 0, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false},  # 3 brook_reeds_0
		{"r": Rect2(128, 0, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": true},  # 4 brook_reeds_1
		{"r": Rect2(160, 0, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 5 brook_reeds_2
		{"r": Rect2(0, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false},  # 6 bank_root_0
		{"r": Rect2(32, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 7 bank_root_1
		{"r": Rect2(64, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 8 brook_boulder_0
		{"r": Rect2(96, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 9 brook_boulder_1
		{"r": Rect2(128, 32, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false}, # 10 submerged_pebbles_0
		{"r": Rect2(160, 32, 32, 32), "o": Vector2(-16, -26), "flat": false, "glow": false},# 11 driftwood_0
		{"r": Rect2(0, 64, 32, 32), "o": Vector2(-16, -26), "flat": false, "glow": false},  # 12 driftwood_1
		{"r": Rect2(32, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 13 spulsaum_shells_0
		{"r": Rect2(64, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 14 spulsaum_shells_1
		{"r": Rect2(96, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 15 spulsaum_starfish_0
		{"r": Rect2(128, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},  # 16 spulsaum_kelp_0
		{"r": Rect2(160, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},  # 17 spulsaum_kelp_1
		{"r": Rect2(0, 96, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},   # 18 beach_pebbles_0
		{"r": Rect2(32, 96, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 19 beach_pebbles_1
		{"r": Rect2(64, 96, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": true},  # 20 dune_oats_0
		{"r": Rect2(96, 96, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": true},  # 21 dune_oats_1
		{"r": Rect2(128, 96, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false},# 22 dune_oats_2
		{"r": Rect2(160, 96, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},  # 23 spulsaum_mixed_0
		{"r": Rect2(0, 128, 48, 36), "o": Vector2(-24, -31), "flat": false, "glow": true},  # 24 tidepool_rock_0
		{"r": Rect2(48, 128, 48, 36), "o": Vector2(-24, -31), "flat": false, "glow": true}, # 25 tidepool_rock_1
		{"r": Rect2(96, 128, 48, 36), "o": Vector2(-24, -31), "flat": false, "glow": true}, # 26 tidepool_rock_2
		{"r": Rect2(144, 128, 48, 36), "o": Vector2(-24, -30), "flat": false, "glow": false},# 27 driftwood_hero_0
	]

	var placements: Array[Dictionary] = [
		# Square -1: Forest Brook (Kolk lilies, reeds, undercut roots, boulders, ford pebbles)
		{"id": 0, "p": Vector2(-400.0, -98.0), "f": false},
		{"id": 1, "p": Vector2(-378.0, -82.0), "f": false},
		{"id": 2, "p": Vector2(-396.0, -114.0), "f": true},
		{"id": 0, "p": Vector2(-366.0, -102.0), "f": true},
		{"id": 1, "p": Vector2(-402.0, 46.0), "f": false},
		{"id": 3, "p": Vector2(-422.0, -104.0), "f": false, "refl": true},
		{"id": 4, "p": Vector2(-350.0, -86.0), "f": true, "refl": true},
		{"id": 5, "p": Vector2(-414.0, -54.0), "f": false, "refl": true},
		{"id": 3, "p": Vector2(-344.0, 44.0), "f": true, "refl": true},
		{"id": 4, "p": Vector2(-424.0, 62.0), "f": false, "refl": true},
		{"id": 5, "p": Vector2(-338.0, 108.0), "f": false, "refl": true},
		{"id": 6, "p": Vector2(-420.0, -76.0), "f": false},
		{"id": 7, "p": Vector2(-346.0, -46.0), "f": true},
		{"id": 6, "p": Vector2(-428.0, 32.0), "f": false},
		{"id": 7, "p": Vector2(-340.0, 72.0), "f": true},
		{"id": 8, "p": Vector2(-364.0, -72.0), "f": false, "obs_r": 8.0, "obs_s": 0.85, "refl": true},
		{"id": 9, "p": Vector2(-410.0, 56.0), "f": false, "obs_r": 8.5, "obs_s": 0.85, "refl": true},
		{"id": 10, "p": Vector2(-374.0, 92.0), "f": false},
		{"id": 10, "p": Vector2(-364.0, 106.0), "f": true},
		{"id": 10, "p": Vector2(-382.0, -44.0), "f": false},
		# Square -2: Coastal Biome (Surf-washed Tidepool rocks, driftwood, Spülsaum shells/starfish/kelp, Strandhafer)
		{"id": 24, "p": Vector2(-748.0, -88.0), "f": false, "obs_r": 10.5, "obs_s": 0.90, "obs_off": Vector2(-2.0, -5.0), "refl": true},
		{"id": 25, "p": Vector2(-706.0, -116.0), "f": false, "obs_r": 9.5, "obs_s": 0.70, "obs_off": Vector2(-2.0, -5.0), "refl": true},
		{"id": 26, "p": Vector2(-754.0, 42.0), "f": false, "obs_r": 10.5, "obs_s": 0.90, "obs_off": Vector2(-2.0, -5.0), "refl": true},
		{"id": 27, "p": Vector2(-734.0, -24.0), "f": false, "obs_r": 9.0, "obs_s": 0.80, "obs_off": Vector2(-5.0, -3.0), "refl": true},
		{"id": 11, "p": Vector2(-668.0, 86.0), "f": false, "obs_r": 7.0, "obs_s": 0.55},
		{"id": 12, "p": Vector2(-736.0, 106.0), "f": true, "obs_r": 8.5, "obs_s": 0.85, "refl": true},
		{"id": 13, "p": Vector2(-738.0, -48.0), "f": false, "obs_r": 4.5, "obs_s": 0.45},
		{"id": 14, "p": Vector2(-742.0, -6.0), "f": true, "obs_r": 4.5, "obs_s": 0.45},
		{"id": 15, "p": Vector2(-740.0, 18.0), "f": false, "obs_r": 5.0, "obs_s": 0.50},
		{"id": 16, "p": Vector2(-732.0, 68.0), "f": false, "obs_r": 5.5, "obs_s": 0.50},
		{"id": 17, "p": Vector2(-730.0, 96.0), "f": true, "obs_r": 5.5, "obs_s": 0.50},
		{"id": 23, "p": Vector2(-720.0, -60.0), "f": false},
		{"id": 18, "p": Vector2(-724.0, 82.0), "f": false},
		{"id": 19, "p": Vector2(-718.0, 8.0), "f": true},
		# Eastern dune-ridge Strandhafer tufts (clustered strictly along upper dune ridge x in [-618..-586]!)
		{"id": 20, "p": Vector2(-606.0, -88.0), "f": false},
		{"id": 21, "p": Vector2(-590.0, -42.0), "f": false},
		{"id": 22, "p": Vector2(-602.0, 18.0), "f": true},
		{"id": 20, "p": Vector2(-588.0, 64.0), "f": false},
		{"id": 21, "p": Vector2(-608.0, 106.0), "f": true},
	]

	for pl: Dictionary in placements:
		var idx: int = int(pl["id"])
		var spec: Dictionary = defs[idx]
		var reg: Rect2 = spec["r"] as Rect2
		var off: Vector2 = spec["o"] as Vector2
		var pos: Vector2 = pl["p"] as Vector2
		var flipped: bool = bool(pl["f"])
		var is_flat: bool = bool(spec["flat"])
		var has_glow: bool = bool(spec["glow"])
		var parent: Node2D = flat_root if is_flat else ysort_root

		var sp: Sprite2D = Sprite2D.new()
		sp.texture = base_tex
		sp.region_enabled = true
		sp.region_rect = reg
		sp.centered = false
		sp.offset = off
		sp.flip_h = flipped
		sp.position = pos
		sp.material = flat_mat if is_flat else ysort_mat
		parent.add_child(sp)

		if bool(pl.get("refl", false)):
			WaterReflections.watch(sp, false)
			sp.tree_exiting.connect(func() -> void: WaterReflections.unwatch(sp))

		if has_glow and glow_tex != null:
			var gl: Sprite2D = Sprite2D.new()
			gl.texture = glow_tex
			gl.region_enabled = true
			gl.region_rect = reg
			gl.centered = false
			gl.offset = off
			gl.flip_h = flipped
			gl.material = Unlit.material()
			gl.visible = false
			sp.add_child(gl)
			_coastal_glow_sprites.append(gl)

		var obs_r: float = float(pl.get("obs_r", 0.0))
		if obs_r > 0.0 and _water_field != null:
			var obs_off: Vector2 = pl.get("obs_off", Vector2.ZERO) as Vector2
			_water_field.inject_obstacle(pos + obs_off, obs_r, float(pl.get("obs_s", 0.75)))

	_sync_coastal_glow(true)


func _sync_coastal_glow(force: bool = false) -> void:
	var night: float = TimeManager.night_amount()
	if not force and absf(night - _last_coastal_night) <= 0.001:
		return
	_last_coastal_night = night
	var glow_on: bool = night > 0.02
	var alpha: float = lerpf(0.30, 0.95, clampf(night, 0.0, 1.0)) if glow_on else 0.0
	for gl: Sprite2D in _coastal_glow_sprites:
		if is_instance_valid(gl):
			gl.visible = glow_on
			gl.modulate.a = alpha


## Composes Square 2 (harmonious country path, Voronoi cobble lane & coherent sanctuary stonework)
## and Square 3 (quantized pixel-art woodland humus, lacy cushion moss, mud & mirror puddles).
func _build_ground_squares(full_rect: Rect2) -> void:
	_surfaces.setup(full_rect, 2.0)

	# ---------------- SQUARE 2 (x = 192..576): ORDERED 4-ARM SANCTUARY CROSSROADS & PATH SYSTEM ----------------
	# Central architectural crossroads: 112x80 flush-jointed Sanctuary Courtyard at (384, 6)
	# with clean N/S/E/W stone thresholds meeting all 4 distinct way types of our Path System!
	_surfaces.add_ancient_courtyard(Vector2(384.0, 6.0))
	var gateway_slabs: Array[Dictionary] = [
		{"p": Vector2(319.0, 6.0), "v": 1, "f": false},  ## West Gateway: coursed running-bond threshold
		{"p": Vector2(449.0, 6.0), "v": 0, "f": false},  ## East Gateway: fitted paired flagstones
		{"p": Vector2(478.0, 5.0), "v": 3, "f": false},  ## East Gateway outer ashlar course
		{"p": Vector2(384.0, -37.0), "v": 2, "f": false}, ## North Gateway: wide dressed threshold stone
		{"p": Vector2(384.0, 50.0), "v": 2, "f": true},  ## South Gateway: wide dressed threshold stone
	]
	for gs: Dictionary in gateway_slabs:
		_surfaces.add_ancient_slab(gs["p"] as Vector2, int(gs["v"]), bool(gs["f"]))

	# 1. WEST ARM — Wide Trodden Country Way (`paint_way "path"`):
	# Connects continuously from Square 1's meadow (`x = 24`) across the border and meets the West Gateway flush!
	var west_country_way: Array[Vector2] = [
		Vector2(48.0, 18.0),
		Vector2(124.0, 15.0),
		Vector2(198.0, 11.0),
		Vector2(262.0, 7.0),
		Vector2(318.0, 6.0),
	]
	_surfaces.paint_way(west_country_way, "path", 17, 0.0, false, true, false)
	_surfaces.paint_junction_fillet(Vector2(316.0, 6.0), Vector2(18.0, 12.0), "path", 0.90)

	# 2. EAST ARM — Historical Twin-Rut Cart Track (`paint_way "cart"`):
	# Starts flush at the East Gateway slabs, showcases two sunken soil wheel ruts + living short-grass median,
	# and connects cleanly into Square 3's woodland trail at (592, -4)!
	var east_cart_track: Array[Vector2] = [
		Vector2(476.0, 5.0),
		Vector2(522.0, 1.0),
		Vector2(564.0, -3.0),
		Vector2(604.0, -4.0),
	]
	_surfaces.paint_way(east_cart_track, "cart", 53, 0.12, false, false, false)
	_surfaces.paint_junction_fillet(Vector2(480.0, 5.0), Vector2(16.0, 11.0), "path", 0.72)

	# 3. NORTH ARM — Hand-Laid Voronoi Cobble Avenue (`paint_cobble_lane`) & Ordered NW Sanctuary Shrine Terrace:
	# Main cobble avenue rises from the North Gateway and curves gracefully NW to an aligned 2x2 Shrine Forecourt,
	# while a shorter weathered East ruin spur branches asymmetrically at (378, -64) and tapers into scattered cobbles!
	var north_cobble_ave: Array[Vector2] = [
		Vector2(384.0, -36.0),
		Vector2(380.0, -64.0),
		Vector2(346.0, -90.0),
		Vector2(294.0, -96.0),
		Vector2(252.0, -96.0),
	]
	_surfaces.paint_cobble_lane(north_cobble_ave, 13.5, 43, false, false)
	var north_cobble_spur: Array[Vector2] = [
		Vector2(380.0, -62.0),
		Vector2(428.0, -76.0),
		Vector2(476.0, -78.0),
		Vector2(516.0, -76.0),
	]
	_surfaces.paint_cobble_lane(north_cobble_spur, 10.5, 61, true, false)
	_surfaces.paint_junction_fillet(Vector2(382.0, -62.0), Vector2(16.0, 13.0), "gravel", 0.88)

	# Orthogonally aligned 2x2 NW Sanctuary Shrine Terrace + neat roadside kerbstones + NE ruin tail-off:
	var north_masonry: Array[Dictionary] = [
		{"p": Vector2(206.0, -105.0), "v": 7, "f": false}, ## NW Shrine upper-left carved border slab
		{"p": Vector2(235.0, -105.0), "v": 1, "f": false}, ## NW Shrine upper-right coursed masonry
		{"p": Vector2(206.0, -87.0), "v": 9, "f": false},  ## NW Shrine lower-left crescent-spore relic
		{"p": Vector2(235.0, -87.0), "v": 3, "f": false},  ## NW Shrine lower-right dressed twin ashlar
		{"p": Vector2(272.0, -81.0), "v": 8, "f": false},  ## Cobble avenue south kerbstone pair
		{"p": Vector2(306.0, -81.0), "v": 8, "f": true},   ## Cobble avenue south kerbstone pair
		{"p": Vector2(502.0, -77.0), "v": 4, "f": false},  ## NE cobble spur weathered ruin slab
		{"p": Vector2(528.0, -76.0), "v": 14, "f": false}, ## NE cobble spur scattered tail-off fragments
	]
	for nm: Dictionary in north_masonry:
		_surfaces.add_ancient_slab(nm["p"] as Vector2, int(nm["v"]), bool(nm["f"]))
	_surfaces.paint_moss_patch(Vector2(218.0, -96.0), Vector2(34.0, 22.0), 0.78, 29)

	# 4. SOUTH ARM — Narrow Meadow Footpath (`paint_way "trail"`) + Rhythmic Stepping Stones & SE Damp Forest Walk:
	# 4A. South-West Stepping-Stone Garden Trail: delicate footpath punctuated by 5 evenly spaced flush stepping stones!
	var sw_stepping_trail: Array[Vector2] = [
		Vector2(376.0, 52.0),
		Vector2(344.0, 76.0),
		Vector2(298.0, 90.0),
		Vector2(246.0, 92.0),
		Vector2(188.0, 86.0),
		Vector2(142.0, 78.0),
	]
	_surfaces.paint_way(sw_stepping_trail, "trail", 71, 0.0, true, false, true)
	var stepping_stones: Array[Dictionary] = [
		{"p": Vector2(350.0, 73.0), "v": 10, "f": false},
		{"p": Vector2(316.0, 86.0), "v": 12, "f": false},
		{"p": Vector2(280.0, 92.0), "v": 13, "f": false}, ## Carved ancient blossom-seal stepping stone
		{"p": Vector2(244.0, 92.0), "v": 11, "f": false},
		{"p": Vector2(210.0, 88.0), "v": 10, "f": true},
	]
	for st: Dictionary in stepping_stones:
		_surfaces.add_ancient_slab(st["p"] as Vector2, int(st["v"]), bool(st["f"]))

	# 4B. South-East Damp Mossy Woodland Footpath (`paint_way "trail"`, damp = 0.42) leading into Square 3's spring hollow:
	var se_damp_trail: Array[Vector2] = [
		Vector2(394.0, 52.0),
		Vector2(444.0, 78.0),
		Vector2(516.0, 86.0),
		Vector2(598.0, 68.0),
	]
	_surfaces.paint_way(se_damp_trail, "trail", 79, 0.42, false, false, true)
	_surfaces.paint_moss_patch(Vector2(458.0, 86.0), Vector2(38.0, 22.0), 0.84, 21)

	# ---------------- SQUARE 3 (x = 576..960): RICH WOODLAND FLOOR VARIATIONS ----------------
	var forest_rect: Rect2 = Rect2(576.0, -144.0, 384.0, 288.0)
	_surfaces.paint_forest_zone(forest_rect, 34.0, 101)

	# Narrow damp footpath (paint_way "trail") weaving between puddles & moss banks
	var forest_trail: Array[Vector2] = [
		Vector2(592.0, -4.0),
		Vector2(668.0, 8.0),
		Vector2(742.0, 22.0),
		Vector2(826.0, 12.0),
		Vector2(912.0, -6.0),
	]
	_surfaces.paint_way(forest_trail, "trail", 131, 0.55)

	# Plush lacy emerald-teal woodland cushion-moss carpets contrasting against dark humus
	_surfaces.paint_moss_patch(Vector2(646.0, -68.0), Vector2(54.0, 36.0), 0.92, 201)
	_surfaces.paint_moss_patch(Vector2(710.0, 84.0), Vector2(56.0, 34.0), 0.90, 209)
	_surfaces.paint_moss_patch(Vector2(886.0, -34.0), Vector2(52.0, 38.0), 0.88, 217)
	_surfaces.paint_moss_patch(Vector2(632.0, 102.0), Vector2(36.0, 22.0), 0.82, 223)

	# 1) Crystal-clear standing woodland puddle with glossy mud rim & outer damp earth (NE hollow)
	_surfaces.paint_moisture_hollow(Vector2(786.0, -48.0), Vector2(58.0, 36.0), 0.96, 307)
	# 2) Rich muddy & damp earth depression (SE woodland basin — showcases damp_earth + mud!)
	_surfaces.paint_moisture_hollow(Vector2(852.0, 64.0), Vector2(54.0, 32.0), 0.72, 319)
	# 3) Small shallow spring puddle at SW forest entry (splash & carry wet bootprints onto stones!)
	_surfaces.paint_moisture_hollow(Vector2(648.0, 56.0), Vector2(32.0, 22.0), 0.90, 331)

	# Three flush mossy woodland stepping stones bridging near the forest entry & puddle shore
	_surfaces.add_ancient_slab(Vector2(616.0, 24.0), 6, false, Color(0.92, 0.96, 0.94))
	_surfaces.add_ancient_slab(Vector2(734.0, -24.0), 10, false, Color(0.86, 0.92, 0.90))
	_surfaces.add_ancient_slab(Vector2(842.0, -14.0), 12, true, Color(0.86, 0.92, 0.90))

	# Handcrafted woodland floor details: creeping roots, leaf litter, mossy boulders, twigs, glowing mushrooms & moss pillows!
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 909
	# Curated hero woodland details (creeping roots, mossy stones near puddle banks, glowing mushroom clusters)
	var hero_forest: Array[Dictionary] = [
		{"p": Vector2(618.0, -86.0), "v": 3, "f": false},
		{"p": Vector2(648.0, -96.0), "v": 4, "f": true},
		{"p": Vector2(692.0, -76.0), "v": 5, "f": false},
		{"p": Vector2(886.0, -92.0), "v": 3, "f": true},
		{"p": Vector2(918.0, -68.0), "v": 4, "f": false},
		{"p": Vector2(906.0, 96.0), "v": 5, "f": true},
		{"p": Vector2(738.0, -82.0), "v": 6, "f": false},
		{"p": Vector2(822.0, -84.0), "v": 7, "f": true},
		{"p": Vector2(842.0, -34.0), "v": 8, "f": false},
		{"p": Vector2(686.0, 44.0), "v": 6, "f": true},
		{"p": Vector2(624.0, -56.0), "v": 11, "f": false}, ## warm forest porcini on moss
		{"p": Vector2(674.0, -62.0), "v": 12, "f": false}, ## twilight violet glowing caps
		{"p": Vector2(746.0, -66.0), "v": 13, "f": false}, ## pale-teal glowing puddle bonnets
		{"p": Vector2(834.0, -56.0), "v": 13, "f": true},
		{"p": Vector2(686.0, 82.0), "v": 12, "f": true},
		{"p": Vector2(894.0, -12.0), "v": 11, "f": true},
		{"p": Vector2(764.0, 74.0), "v": 12, "f": false},
		{"p": Vector2(636.0, -28.0), "v": 14, "f": false},
		{"p": Vector2(716.0, 62.0), "v": 14, "f": true},
		{"p": Vector2(878.0, -24.0), "v": 15, "f": false},
		{"p": Vector2(812.0, 36.0), "v": 9, "f": false},
		{"p": Vector2(712.0, -14.0), "v": 10, "f": false},
		{"p": Vector2(898.0, 32.0), "v": 9, "f": true},
		{"p": Vector2(616.0, 84.0), "v": 10, "f": true},
		# Subtle edge transition leaves spilling slightly into Square 2's east rim!
		{"p": Vector2(552.0, 38.0), "v": 0, "f": false},
		{"p": Vector2(564.0, -44.0), "v": 1, "f": true},
		{"p": Vector2(568.0, 74.0), "v": 9, "f": false},
	]
	for hd: Dictionary in hero_forest:
		_surfaces.add_forest_detail(hd["p"] as Vector2, int(hd["v"]), bool(hd["f"]))

	# Organic scatter of fallen leaf-litter, twigs, small mossy stones & damp moss hummocks across Square 3
	for _i: int in 42:
		var dp: Vector2 = Vector2(rng.randf_range(592.0, 940.0), rng.randf_range(-126.0, 126.0)).round()
		var surf_here: String = _surfaces.surface_at(dp)
		if surf_here == "puddle" or surf_here == "ancient_stone":
			continue
		var roll: float = rng.randf()
		var v: int = 0
		if surf_here == "mud" or surf_here == "damp_earth":
			v = 2 if roll < 0.60 else (8 if roll < 0.85 else 9)
		elif surf_here == "moss":
			v = 14 if roll < 0.30 else (15 if roll < 0.55 else (0 if roll < 0.82 else 11))
		else:
			v = 0 if roll < 0.34 else (1 if roll < 0.62 else (9 if roll < 0.78 else (10 if roll < 0.90 else 7)))
		var tv: float = rng.randf_range(0.92, 1.06)
		_surfaces.add_forest_detail(dp, v, rng.randf() < 0.5, Color(tv, tv, tv, 1.0))

	# ---------------- SQUARE 4 (x = 960..1344): GLIMMTAL OAK GLADE & PUDDLE MIRROR ----------------
	var glade_trail: Array[Vector2] = [
		Vector2(912.0, -6.0),
		Vector2(986.0, 10.0),
		Vector2(1062.0, 18.0),
		Vector2(1148.0, 26.0),
	]
	_surfaces.paint_way(glade_trail, "trail", 157, 0.35, true)
	# Mirror woodland pond in front of the Crown-Shyness Oak Pair so all 5 canopy clusters reflect in water!
	_surfaces.paint_moisture_hollow(Vector2(1246.0, 82.0), Vector2(46.0, 26.0), 0.96, 409)
	_surfaces.paint_moss_patch(Vector2(1018.0, -68.0), Vector2(48.0, 28.0), 0.90, 419)
	# Botanical root-humus, north cushion moss & Canopy Drip-Line rings for our glade oaks!
	_surfaces.paint_tree_root_zone(Vector2(944.0, 38.0), 10.0, 70.0, 443)  ## Woodland-Edge Asymmetric Oak (`s4_c`)
	_surfaces.paint_tree_root_zone(Vector2(1032.0, 30.0), 8.0, 46.0, 303)  ## Young Pole Oak (`s3`)
	_surfaces.paint_tree_root_zone(Vector2(1124.0, 64.0), 16.0, 100.0, 505)## Stage 5 Ancient Matriarch (`s5`)
	_surfaces.paint_tree_root_zone(Vector2(1234.0, 50.0), 11.0, 76.0, 404) ## Stage 4 Solitary Oak (`s4`)
	_surfaces.paint_tree_root_zone(Vector2(1312.0, 42.0), 11.0, 72.0, 408) ## Stage 4 Twin-Stem Oak (`s4_b`)
	_surfaces.paint_tree_root_zone(Vector2(1042.0, 88.0), 5.0, 26.0, 202)  ## Stage 2 Sapling (`s2`)

	var south_to_birch_trail: Array[Vector2] = [
		Vector2(1148.0, 26.0),
		Vector2(1158.0, -38.0),
		Vector2(1146.0, -112.0),
		Vector2(1138.0, -144.0),
	]
	_surfaces.paint_way(south_to_birch_trail, "trail", 263, 0.28, false)

	var north_to_apple_trail: Array[Vector2] = [
		Vector2(1148.0, 26.0),
		Vector2(1168.0, 82.0),
		Vector2(1156.0, 122.0),
		Vector2(1148.0, 144.0),
	]
	_surfaces.paint_way(north_to_apple_trail, "trail", 271, 0.30, false)
	_surfaces.commit()


func _build_apple_ground(arect: Rect2) -> void:
	_apple_surfaces.setup(arect, 2.0)
	var orchard_trail: Array[Vector2] = [
		Vector2(1148.0, 144.0),
		Vector2(1142.0, 196.0),
		Vector2(1154.0, 276.0),
		Vector2(1184.0, 348.0),
		Vector2(1218.0, 384.0),
	]
	_apple_surfaces.paint_way(orchard_trail, "trail", 271, 0.30, true)
	var mother_branch_trail: Array[Vector2] = [
		Vector2(1154.0, 276.0),
		Vector2(1122.0, 326.0),
		Vector2(1098.0, 356.0),
	]
	_apple_surfaces.paint_way(mother_branch_trail, "trail", 277, 0.24, true)

	# Sunny orchard spring hollow & dry-stone Lesestein-Mauer slabs
	_apple_surfaces.paint_moisture_hollow(Vector2(1254.0, 378.0), Vector2(40.0, 22.0), 0.94, 613)
	_apple_surfaces.paint_moss_patch(Vector2(1008.0, 186.0), Vector2(48.0, 24.0), 0.88, 619)
	_apple_surfaces.paint_moss_patch(Vector2(1068.0, 348.0), Vector2(44.0, 24.0), 0.84, 631)
	var orchard_stones: Array[Dictionary] = [
		{"p": Vector2(1146.0, 158.0), "v": 11, "f": false},
		{"p": Vector2(1142.0, 178.0), "v": 12, "f": true},
		{"p": Vector2(984.0, 268.0), "v": 8, "f": false},
		{"p": Vector2(980.0, 296.0), "v": 9, "f": true},
		{"p": Vector2(988.0, 322.0), "v": 10, "f": false},
		{"p": Vector2(1204.0, 376.0), "v": 11, "f": false},
		{"p": Vector2(1298.0, 374.0), "v": 10, "f": true},
	]
	for os_def: Dictionary in orchard_stones:
		_apple_surfaces.add_ancient_slab(os_def["p"] as Vector2, int(os_def["v"]), bool(os_def["f"]), Color(0.98, 0.94, 0.90))

	var orchard_details: Array[Dictionary] = [
		{"p": Vector2(1036.0, 192.0), "v": 11, "f": false},
		{"p": Vector2(984.0, 198.0), "v": 14, "f": true},
		{"p": Vector2(1054.0, 358.0), "v": 0, "f": false},
		{"p": Vector2(1108.0, 362.0), "v": 1, "f": true},
		{"p": Vector2(1232.0, 352.0), "v": 0, "f": true},
		{"p": Vector2(1284.0, 354.0), "v": 9, "f": false},
		{"p": Vector2(1224.0, 392.0), "v": 13, "f": false},
		{"p": Vector2(1282.0, 388.0), "v": 6, "f": true},
	]
	for od: Dictionary in orchard_details:
		_apple_surfaces.add_forest_detail(od["p"] as Vector2, int(od["v"]), bool(od["f"]))

	_apple_surfaces.paint_tree_root_zone(Vector2(1078.0, 344.0), 13.0, 84.0, 805)
	_apple_surfaces.paint_tree_root_zone(Vector2(996.0, 292.0), 9.0, 62.0, 843)
	_apple_surfaces.paint_tree_root_zone(Vector2(1216.0, 326.0), 10.0, 68.0, 808)
	_apple_surfaces.paint_tree_root_zone(Vector2(1296.0, 334.0), 9.0, 66.0, 804)
	_apple_surfaces.paint_tree_root_zone(Vector2(1152.0, 224.0), 6.0, 44.0, 803)
	_apple_surfaces.paint_tree_root_zone(Vector2(1158.0, 398.0), 4.0, 26.0, 802)
	_apple_surfaces.commit()


func _build_birch_ground(brect: Rect2) -> void:
	_birch_surfaces.setup(brect, 2.0)
	var birch_north_trail: Array[Vector2] = [
		Vector2(1138.0, -144.0),
		Vector2(1128.0, -184.0),
		Vector2(1142.0, -258.0),
		Vector2(1176.0, -328.0),
	]
	_birch_surfaces.paint_way(birch_north_trail, "trail", 263, 0.28, true)
	_birch_surfaces.paint_moisture_hollow(Vector2(1238.0, -198.0), Vector2(42.0, 24.0), 0.96, 521)
	_birch_surfaces.paint_moss_patch(Vector2(1024.0, -384.0), Vector2(54.0, 26.0), 0.92, 531)
	_birch_surfaces.paint_moss_patch(Vector2(1088.0, -232.0), Vector2(44.0, 26.0), 0.88, 541)
	_birch_surfaces.paint_moss_patch(Vector2(1204.0, -248.0), Vector2(40.0, 24.0), 0.86, 547)
	_birch_surfaces.add_ancient_slab(Vector2(1136.0, -156.0), 11, false, Color(0.92, 0.96, 0.96))
	_birch_surfaces.add_ancient_slab(Vector2(1132.0, -176.0), 12, true, Color(0.90, 0.95, 0.96))
	_birch_surfaces.add_ancient_slab(Vector2(1188.0, -206.0), 10, false, Color(0.92, 0.96, 0.96))
	var birch_details: Array[Dictionary] = [
		{"p": Vector2(1062.0, -372.0), "v": 11, "f": false},
		{"p": Vector2(992.0, -366.0), "v": 14, "f": true},
		{"p": Vector2(1078.0, -248.0), "v": 12, "f": false},
		{"p": Vector2(1196.0, -214.0), "v": 13, "f": true},
		{"p": Vector2(1278.0, -204.0), "v": 6, "f": false},
		{"p": Vector2(1018.0, -264.0), "v": 7, "f": true},
		{"p": Vector2(1162.0, -296.0), "v": 0, "f": false},
		{"p": Vector2(1254.0, -288.0), "v": 1, "f": true},
	]
	for bd: Dictionary in birch_details:
		_birch_surfaces.add_forest_detail(bd["p"] as Vector2, int(bd["v"]), bool(bd["f"]))

	_birch_surfaces.paint_tree_root_zone(Vector2(1108.0, -218.0), 12.0, 82.0, 705)
	_birch_surfaces.paint_tree_root_zone(Vector2(1218.0, -238.0), 11.0, 62.0, 708)
	_birch_surfaces.paint_tree_root_zone(Vector2(1292.0, -246.0), 8.0, 58.0, 704)
	_birch_surfaces.paint_tree_root_zone(Vector2(998.0, -236.0), 8.0, 58.0, 743)
	_birch_surfaces.paint_tree_root_zone(Vector2(1304.0, -162.0), 6.0, 40.0, 703)
	_birch_surfaces.paint_tree_root_zone(Vector2(1182.0, -172.0), 4.0, 24.0, 702)
	_birch_surfaces.commit()


func _build_tree_glade() -> void:
	_trees_root = Node2D.new()
	_trees_root.name = "GlimmtalTrees"
	_trees_root.y_sort_enabled = true
	add_child(_trees_root)

	# ================ SQUARE 4 (SOUTH): GLIMMTAL-STIELEICHEN (`valley_oak`) ================
	_oak_matriarch = TREE_SCENE.instantiate() as LivingTree
	_oak_matriarch.setup_tree(Vector2(1124.0, 64.0), 5, 505, "valley_oak")
	_oak_matriarch.configure_traits(0, {"moss": 0, "ivy": 0, "hollow": 1, "fungi": 0, "sprig": -1, "amber": 1}, 0)
	_trees_root.add_child(_oak_matriarch)
	_trees.append(_oak_matriarch)

	_oak_mature = TREE_SCENE.instantiate() as LivingTree
	_oak_mature.setup_tree(Vector2(1234.0, 50.0), 4, 404, "valley_oak")
	_oak_mature.configure_traits(0, {"moss": -1, "ivy": -1, "hollow": 0, "fungi": -1, "sprig": 0, "amber": 1}, 0)
	_trees_root.add_child(_oak_mature)
	_trees.append(_oak_mature)

	_oak_pole = TREE_SCENE.instantiate() as LivingTree
	_oak_pole.setup_tree(Vector2(1312.0, 42.0), 4, 408, "valley_oak")
	_oak_pole.configure_traits(1, {"moss": 1, "ivy": -1, "hollow": -1, "fungi": 1, "sprig": 1, "amber": 0}, 0)
	_trees_root.add_child(_oak_pole)
	_trees.append(_oak_pole)

	var oak_asym: LivingTree = TREE_SCENE.instantiate() as LivingTree
	oak_asym.setup_tree(Vector2(944.0, 38.0), 4, 443, "valley_oak")
	oak_asym.configure_traits(2, {"moss": 0, "ivy": 1, "hollow": 2, "fungi": -1, "sprig": -1, "amber": 0}, 0)
	_trees_root.add_child(oak_asym)
	_trees.append(oak_asym)

	var oak_young_pole: LivingTree = TREE_SCENE.instantiate() as LivingTree
	oak_young_pole.setup_tree(Vector2(1032.0, 30.0), 3, 303, "valley_oak")
	oak_young_pole.configure_traits(0, {"moss": -1, "ivy": -1, "hollow": -1, "fungi": -1, "sprig": 0, "amber": 0}, 1)
	_trees_root.add_child(oak_young_pole)
	_trees.append(oak_young_pole)

	var extra_specs: Array[Dictionary] = [
		{"p": Vector2(978.0, 84.0), "s": 0, "seed": 100},
		{"p": Vector2(1008.0, 86.0), "s": 1, "seed": 101},
		{"p": Vector2(1042.0, 88.0), "s": 2, "seed": 202},
		{"p": Vector2(1016.0, -68.0), "s": 6, "seed": 606},
	]
	for es: Dictionary in extra_specs:
		var lt: LivingTree = TREE_SCENE.instantiate() as LivingTree
		lt.setup_tree(es["p"] as Vector2, int(es["s"]), int(es["seed"]), "valley_oak")
		_trees_root.add_child(lt)
		_trees.append(lt)

	# ================ SQUARE 4N (NORTH): GLIMMTAL-HÄNGEBIRKEN (`silver_birch`) ================
	_birch_mother = TREE_SCENE.instantiate() as LivingTree
	_birch_mother.setup_tree(Vector2(1108.0, -218.0), 5, 705, "silver_birch")
	_birch_mother.configure_traits(0, {"moss": 0, "ivy": 0, "hollow": 1, "fungi": 1, "sprig": -1, "amber": 1}, 0)
	_trees_root.add_child(_birch_mother)
	_trees.append(_birch_mother)
	_birches.append(_birch_mother)

	_birch_clump = TREE_SCENE.instantiate() as LivingTree
	_birch_clump.setup_tree(Vector2(1218.0, -238.0), 4, 708, "silver_birch")
	_birch_clump.configure_traits(1, {"moss": 1, "ivy": -1, "hollow": -1, "fungi": 0, "sprig": 1, "amber": 0}, 0)
	_trees_root.add_child(_birch_clump)
	_trees.append(_birch_clump)
	_birches.append(_birch_clump)

	_birch_solitary = TREE_SCENE.instantiate() as LivingTree
	_birch_solitary.setup_tree(Vector2(1292.0, -246.0), 4, 704, "silver_birch")
	_birch_solitary.configure_traits(0, {"moss": -1, "ivy": 0, "hollow": 0, "fungi": -1, "sprig": -1, "amber": 1}, 0)
	_trees_root.add_child(_birch_solitary)
	_trees.append(_birch_solitary)
	_birches.append(_birch_solitary)

	var birch_arch: LivingTree = TREE_SCENE.instantiate() as LivingTree
	birch_arch.setup_tree(Vector2(998.0, -236.0), 4, 743, "silver_birch")
	birch_arch.configure_traits(2, {"moss": 0, "ivy": 1, "hollow": 2, "fungi": -1, "sprig": 0, "amber": 0}, 0)
	_trees_root.add_child(birch_arch)
	_trees.append(birch_arch)
	_birches.append(birch_arch)

	var birch_pole: LivingTree = TREE_SCENE.instantiate() as LivingTree
	birch_pole.setup_tree(Vector2(1304.0, -162.0), 3, 703, "silver_birch")
	birch_pole.configure_traits(0, {"moss": -1, "ivy": -1, "hollow": -1, "fungi": -1, "sprig": 0, "amber": 0}, 1)
	_trees_root.add_child(birch_pole)
	_trees.append(birch_pole)
	_birches.append(birch_pole)

	var birch_extras: Array[Dictionary] = [
		{"p": Vector2(980.0, -172.0), "s": 0, "seed": 700},
		{"p": Vector2(1008.0, -168.0), "s": 1, "seed": 701},
		{"p": Vector2(1182.0, -172.0), "s": 2, "seed": 702},
		{"p": Vector2(1024.0, -384.0), "s": 6, "seed": 706},
	]
	for bs: Dictionary in birch_extras:
		var bt: LivingTree = TREE_SCENE.instantiate() as LivingTree
		bt.setup_tree(bs["p"] as Vector2, int(bs["s"]), int(bs["seed"]), "silver_birch")
		_trees_root.add_child(bt)
		_trees.append(bt)
		_birches.append(bt)

	# ================ SQUARE 4S (SOUTH): GLIMMTAL-WILDÄPFEL (`wild_apple`) ================
	# West half in Full Spring Blossom (`phenology = 1`), East half in Ripe Fruit Load (`phenology = 2`)!
	_apple_mother = TREE_SCENE.instantiate() as LivingTree
	_apple_mother.setup_tree(Vector2(1078.0, 344.0), 5, 805, "wild_apple")
	_apple_mother.configure_traits(0, {"moss": 0, "ivy": 0, "hollow": 1, "fungi": -1, "sprig": -1}, 0, 1)
	_trees_root.add_child(_apple_mother)
	_trees.append(_apple_mother)
	_apples.append(_apple_mother)

	var apple_lean: LivingTree = TREE_SCENE.instantiate() as LivingTree
	apple_lean.setup_tree(Vector2(996.0, 292.0), 4, 843, "wild_apple")
	apple_lean.configure_traits(2, {"moss": 1, "ivy": 1, "hollow": 2, "fungi": -1, "sprig": 0}, 0, 1)
	_trees_root.add_child(apple_lean)
	_trees.append(apple_lean)
	_apples.append(apple_lean)

	_apple_zwiesel = TREE_SCENE.instantiate() as LivingTree
	_apple_zwiesel.setup_tree(Vector2(1216.0, 326.0), 4, 808, "wild_apple")
	_apple_zwiesel.configure_traits(1, {"moss": 0, "ivy": -1, "hollow": -1, "fungi": 0, "sprig": 1}, 0, 2)
	_trees_root.add_child(_apple_zwiesel)
	_trees.append(_apple_zwiesel)
	_apples.append(_apple_zwiesel)

	_apple_fruiting = TREE_SCENE.instantiate() as LivingTree
	_apple_fruiting.setup_tree(Vector2(1296.0, 334.0), 4, 804, "wild_apple")
	_apple_fruiting.configure_traits(0, {"moss": -1, "ivy": 0, "hollow": 0, "fungi": 1, "sprig": 0}, 0, 2)
	_trees_root.add_child(_apple_fruiting)
	_trees.append(_apple_fruiting)
	_apples.append(_apple_fruiting)

	var apple_young: LivingTree = TREE_SCENE.instantiate() as LivingTree
	apple_young.setup_tree(Vector2(1152.0, 224.0), 3, 803, "wild_apple")
	apple_young.configure_traits(0, {"moss": 0, "ivy": -1, "hollow": -1, "fungi": -1, "sprig": 1}, 1, 2)
	_trees_root.add_child(apple_young)
	_trees.append(apple_young)
	_apples.append(apple_young)

	var apple_sapling: LivingTree = TREE_SCENE.instantiate() as LivingTree
	apple_sapling.setup_tree(Vector2(1158.0, 398.0), 2, 802, "wild_apple")
	apple_sapling.configure_traits(0, {}, 0, 1)
	_trees_root.add_child(apple_sapling)
	_trees.append(apple_sapling)
	_apples.append(apple_sapling)

	var apple_extras: Array[Dictionary] = [
		{"p": Vector2(990.0, 408.0), "s": 0, "seed": 800},
		{"p": Vector2(1018.0, 404.0), "s": 1, "seed": 801},
		{"p": Vector2(1008.0, 184.0), "s": 6, "seed": 806},
	]
	for as_def: Dictionary in apple_extras:
		var at: LivingTree = TREE_SCENE.instantiate() as LivingTree
		at.setup_tree(as_def["p"] as Vector2, int(as_def["s"]), int(as_def["seed"]), "wild_apple")
		_trees_root.add_child(at)
		_trees.append(at)
		_apples.append(at)

	var job: Jobs.Job = LivingTree.compute_stand_ecology_async(_trees)
	Jobs.wait(job)
	_metrics["trees_placed"] = _trees.size() >= 25
	_metrics["crown_shyness"] = _oak_mature.shy_right_px >= 1.0 and _oak_pole.shy_left_px >= 1.0
	_metrics["birches_placed"] = _birches.size() >= 9
	_metrics["birch_crown_shyness"] = _birch_clump.shy_right_px >= 1.0 and _birch_solitary.shy_left_px >= 1.0
	_metrics["apples_placed"] = _apples.size() >= 9
	_metrics["apple_crown_shyness"] = _apple_zwiesel.shy_right_px >= 1.0 and _apple_fruiting.shy_left_px >= 1.0


func _verify_surface_probes() -> void:
	_metrics["surface_grass"] = Terrain.surface_at(Vector2(-32.0, 0.0)) == "grass"
	_metrics["surface_path"] = Terrain.surface_at(Vector2(246.0, 9.0)) == "path"
	_metrics["surface_gravel"] = Terrain.surface_at(Vector2(348.0, -92.0)) == "gravel"
	_metrics["surface_ancient_stone"] = Terrain.surface_at(Vector2(384.0, 6.0)) == "ancient_stone"
	_metrics["surface_puddle"] = Terrain.surface_at(Vector2(786.0, -48.0)) == "puddle"
	_metrics["surface_moss"] = Terrain.surface_at(Vector2(646.0, -68.0)) == "moss"
	# Probe radial rings around Square 3 hollows & humus to verify damp_earth, mud, and forest_floor are present
	var seen: Dictionary = {}
	for y: int in range(-120, 121, 8):
		for x: int in range(584, 952, 8):
			seen[Terrain.surface_at(Vector2(float(x), float(y)))] = true
	_metrics["surface_forest_floor"] = seen.has("forest_floor")
	_metrics["surface_damp_earth"] = seen.has("damp_earth")
	_metrics["surface_mud"] = seen.has("mud")


func _prepare_player() -> void:
	await get_tree().process_frame
	if _players.get_child_count() == 0:
		return
	_player = _players.get_child(0) as Player
	if _player == null:
		return
	_player.position = SQ1_CENTER
	_player.facing = Vector2.DOWN
	_player.health.current = _player.health.max_health
	_player.stamina.current = _player.stamina.max_stamina
	_player.sync_wound_visuals()
	if _player.quests != null:
		_player.quests.set_physics_process(false)
	if _player.inventory != null and (_player.inventory.equipment.get("main_hand", {}) as Dictionary).is_empty():
		_player.inventory.give("sword_basic", 1)
		_player.inventory.give("axe_basic", 1)
		_player.inventory.give("pickaxe_basic", 1)
		_player.inventory.give("sickle_basic", 1)
		_equip_first_sword()
	if _player._hud != null and _player._hud is CanvasLayer:
		(_player._hud as CanvasLayer).visible = _show_game_hud
	_apply_camera_zoom()
	_player._camera.reset_smoothing()
	_update_ui_text()
	if _demo_active:
		_start_demo()


func _equip_first_sword() -> void:
	if _player == null or _player.inventory == null:
		return
	for i: int in _player.inventory.slots.size():
		var stack: Dictionary = _player.inventory.slots[i] as Dictionary
		if not stack.is_empty() and String(stack.get("id", "")) == "sword_basic":
			_player.inventory.request("equip", [i, "main_hand"])
			return


func _toggle_axe_in_hand() -> void:
	if _player == null or _player.inventory == null:
		return
	_holding_axe = not _holding_axe
	if _holding_axe:
		for i: int in mini(8, _player.inventory.slots.size()):
			var st: Dictionary = _player.inventory.slots[i] as Dictionary
			if not st.is_empty() and String(st.get("id", "")) == "axe_basic":
				_player.inventory.select(i)
				return
	else:
		for i: int in mini(8, _player.inventory.slots.size()):
			var st: Dictionary = _player.inventory.slots[i] as Dictionary
			if st.is_empty() or String(Items.definition(st).get("kind", "")) != "tool":
				_player.inventory.select(i)
				return


func _setup_studio_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "GrassLabUI"
	_ui_layer.layer = 95
	add_child(_ui_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(8.0, 6.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.14, 0.76)
	style.border_color = Color(0.32, 0.28, 0.48, 0.88)
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	_ui_layer.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 9)
	_status_label.add_theme_color_override("font_color", Color("e8e4f4"))
	vbox.add_child(_status_label)

	_help_label = Label.new()
	_help_label.add_theme_font_size_override("font_size", 8)
	_help_label.add_theme_color_override("font_color", Color("9c95bd"))
	_help_label.text = "[1-3] Wiese/Pfad/Wald  [4-6] Wasser  [7-0] Hain/Hang  [F1] Spinne  [F5] Rudel  [F6] Clear  [F7] Finisher (Shift:Boss)  [T] Zeit  [Z] 1x/2x"
	vbox.add_child(_help_label)
	_ui_layer.visible = _show_ui and not _capture_only


func _update_ui_text() -> void:
	if _status_label == null:
		return
	var zone_txt: String = _zone_label_at(_player.global_position) if _player != null else "1 · WIESE"
	var surf_txt: String = (Terrain.surface_at(_player.global_position) if _player != null else "grass").to_upper()
	var mode_txt: String = ("DEMO: %s" % _demo_phase) if _demo_active else "FREIES TESTEN"
	var t_name: String = String(TIME_PRESETS[_time_idx]["name"])
	var w_name: String = String(WEATHER_PRESETS[_weather_idx]["name"])
	var z_txt: String = "2x" if _zoom_macro else "1x"
	var dbg_txt: String = "  |  W-DBG" if _water_debug else ""
	_status_label.text = "%s  |  BODEN: %s  |  %s  |  %s  |  %s  |  %s%s" % [zone_txt, surf_txt, mode_txt, t_name, w_name, z_txt, dbg_txt]


func _jump_to_square(target: Vector2) -> void:
	if _player == null:
		return
	if _demo_active:
		_stop_demo()
	_player.position = target
	_player.velocity = Vector2.ZERO
	_player._camera.reset_smoothing()
	if _grass != null:
		_grass.recenter_field(target)
	if _birch_grass != null:
		_birch_grass.recenter_field(target)
	if _apple_grass != null:
		_apple_grass.recenter_field(target)
	if _water_field != null:
		_water_field.recenter_wave_field(target)
	_update_ui_text()


func _toggle_water_debug() -> void:
	_water_debug = not _water_debug
	if _water_field != null:
		_water_field.set_debug_overlay(_water_debug)
	_update_ui_text()


func _unhandled_input(event: InputEvent) -> void:
	if _capture_only:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			_jump_to_square(SQ1_CENTER)
		KEY_2:
			_jump_to_square(SQ2_CENTER)
		KEY_3:
			_jump_to_square(SQ3_CENTER)
		KEY_4:
			_jump_to_square(SQ_NEG1_CENTER)
		KEY_5:
			_jump_to_square(SQ_NEG2_CENTER)
		KEY_6:
			_jump_to_square(SQ_NEG3_CENTER)
		KEY_7:
			_jump_to_square(SQ4_CENTER)
		KEY_8:
			_jump_to_square(SQ4N_CENTER)
		KEY_0:
			_jump_to_square(SQ4S_CENTER)
		KEY_9:
			_jump_to_square(SQ5_CENTER)
		KEY_F1:
			if key.shift_pressed:
				_next_brood_variant = (_next_brood_variant + 1) % 3
			_spawn_lab_spider_near_player(_next_brood_variant)
		KEY_F5:
			_spawn_spider_ecology_scenario()
		KEY_F6:
			_clear_lab_spiders()
		KEY_F7:
			_spawn_finisher_test_spider(key.shift_pressed)
		KEY_F3:
			_toggle_water_debug()
		KEY_X:
			_toggle_axe_in_hand()
		KEY_P:
			_toggle_pickaxe_in_hand()
		KEY_M:
			_apple_phenology_cycle = (_apple_phenology_cycle + 1) % 3
			var target_ph: int = 1 if _apple_phenology_cycle == 1 else (2 if _apple_phenology_cycle == 2 else 0)
			for atr: LivingTree in _apples:
				if is_instance_valid(atr):
					atr.set_phenology_mode(target_ph)
		KEY_B:
			for tr: LivingTree in _trees:
				if is_instance_valid(tr):
					tr.advance_growth_days(5)
		KEY_N:
			_autumn_mode = not _autumn_mode
			for tr: LivingTree in _trees:
				if is_instance_valid(tr):
					tr.set_autumn_shift(0.85 if _autumn_mode else 0.0)
		KEY_K:
			for tr: LivingTree in _trees:
				if is_instance_valid(tr):
					tr.consecrate_heal()
		KEY_R:
			_start_demo()
		KEY_SPACE:
			if _demo_active:
				_stop_demo()
			else:
				_start_demo()
		KEY_T:
			_apply_time((_time_idx + 1) % TIME_PRESETS.size())
		KEY_W:
			if key.shift_pressed:
				_toggle_water_debug()
				return
			if _demo_active:
				_stop_demo()
				return
		KEY_A, KEY_S, KEY_D:
			if _demo_active:
				_stop_demo()
				return
		KEY_V, KEY_F2:
			_apply_weather((_weather_idx + 1) % WEATHER_PRESETS.size())
		KEY_G:
			_apply_layer_mode((_layer_mode + 1) % LAYER_MODES.size())
		KEY_Z:
			_zoom_macro = not _zoom_macro
			_apply_camera_zoom()
			_update_ui_text()
		KEY_H:
			_show_ui = not _show_ui
			if _ui_layer != null:
				_ui_layer.visible = _show_ui
		KEY_U:
			_show_game_hud = not _show_game_hud
			if _player != null and _player._hud != null and _player._hud is CanvasLayer:
				(_player._hud as CanvasLayer).visible = _show_game_hud


func _apply_time(idx: int) -> void:
	_time_idx = idx
	var t: float = float(TIME_PRESETS[_time_idx]["t"])
	TimeManager.lock_at(t)
	TimeManager.day = 4
	if is_instance_valid(DaylightField.current):
		DaylightField.current.clock = 12.0
	_sync_coastal_glow(true)
	_update_ui_text()


func _apply_weather(idx: int) -> void:
	_weather_idx = idx
	var spec: Dictionary = WEATHER_PRESETS[_weather_idx]
	var wid: String = String(spec["id"])
	var wind_val: float = float(spec["wind"])
	var wm: WeatherManager = WeatherManager.current
	if wm != null:
		wm.force(wid, 9999.0)
		wm.wind = wind_val
		if wid == "rain":
			wm.rain = 0.52
			wm.storm = 0.0
			wm.ground_wet = 0.92
			wm.set(&"_extra_wet", 0.95)
			wm.puddle = 0.85
		elif wid == "storm":
			wm.rain = 0.92
			wm.storm = 1.0
			wm.ground_wet = 1.0
			wm.set(&"_extra_wet", 1.0)
			wm.puddle = 0.78
		else:
			wm.rain = 0.0
			wm.storm = 0.0
			wm.ground_wet = 0.0
			wm.set(&"_extra_wet", 0.0)
			wm.puddle = 0.0
		RenderingServer.global_shader_parameter_set("g_rain", wm.rain)
		RenderingServer.global_shader_parameter_set("g_storm", wm.storm)
		RenderingServer.global_shader_parameter_set("g_wet", wm.ground_wet)
		RenderingServer.global_shader_parameter_set("g_puddle", wm.puddle)
	if _wind != null:
		var w_dir: float = wm.dir if wm != null else 0.26
		var w_storm: float = wm.storm if wm != null else (1.0 if wid == "storm" else 0.0)
		var w_rain: float = wm.rain if wm != null else (0.52 if wid == "rain" else (0.92 if wid == "storm" else 0.0))
		_wind.set_weather(wind_val, w_dir, w_storm, w_rain)
	_update_ui_text()


func _apply_layer_mode(idx: int) -> void:
	_layer_mode = idx
	if _grass != null:
		_grass.set_grass_visible(_layer_mode != 1)
		_grass.set_debug_overlay(_layer_mode == 2)
	if _birch_grass != null:
		_birch_grass.set_grass_visible(_layer_mode != 1)
		_birch_grass.set_debug_overlay(_layer_mode == 2)
	if _apple_grass != null:
		_apple_grass.set_grass_visible(_layer_mode != 1)
		_apple_grass.set_debug_overlay(_layer_mode == 2)
	_update_ui_text()


func _apply_camera_zoom() -> void:
	if _player == null or _player._camera == null:
		return
	var z: float = 2.0 if _zoom_macro else 1.0
	_player._camera.zoom = Vector2(z, z)


func _release_all_synth() -> void:
	for act: StringName in SYNTH_ACTIONS:
		if Input.is_action_pressed(act):
			Input.action_release(act)


func _stop_demo() -> void:
	_demo_run_id += 1
	_demo_active = false
	_demo_phase = "MANUELL"
	_release_all_synth()
	_update_ui_text()


func _start_demo() -> void:
	_demo_run_id += 1
	var run_id: int = _demo_run_id
	_demo_active = true
	_release_all_synth()
	_run_choreography(run_id)


func _hold(run_id: int, actions: Array[StringName], seconds: float) -> bool:
	for act: StringName in actions:
		Input.action_press(act)
	var elapsed: float = 0.0
	while elapsed < seconds:
		if run_id != _demo_run_id or not is_inside_tree():
			_release_all_synth()
			return false
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	for act: StringName in actions:
		Input.action_release(act)
	return run_id == _demo_run_id and is_inside_tree()


func _tap(run_id: int, action: StringName, hold_sec: float = 0.06) -> bool:
	Input.action_press(action)
	var elapsed: float = 0.0
	while elapsed < hold_sec:
		if run_id != _demo_run_id or not is_inside_tree():
			_release_all_synth()
			return false
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	Input.action_release(action)
	return run_id == _demo_run_id and is_inside_tree()


func _wait_sec(run_id: int, seconds: float) -> bool:
	return await _hold(run_id, [], seconds)


func _save_shot(filename: String) -> void:
	if _capture_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s" % [_capture_dir, filename])


func _run_choreography(run_id: int) -> void:
	if _player == null:
		return
	_player.position = Vector2(-28.0, 12.0)
	_player.velocity = Vector2.ZERO
	_player.facing = Vector2.DOWN
	_player.stamina.current = _player.stamina.max_stamina
	_player._camera.reset_smoothing()
	_apply_time(0)
	_apply_weather(0)
	_apply_layer_mode(0)
	_zoom_macro = false
	_apply_camera_zoom()

	if _water_capture_only:
		if not await _run_water_v2_polish_captures(run_id): return
		if not await _run_water_v2_captures(run_id): return
		get_tree().quit(0)
		return

	if _tree_capture_only:
		if not await _run_tree_v3_captures(run_id): return
		get_tree().quit(0)
		return

	if _rock_capture_only:
		if not await _run_rock_v1_captures(run_id): return
		get_tree().quit(0)
		return

	if _birch_capture_only:
		if not await _run_birch_captures(run_id): return
		get_tree().quit(0)
		return

	if _apple_capture_only:
		if not await _run_apple_captures(run_id): return
		get_tree().quit(0)
		return

	if _paths_capture_only:
		if not await _run_paths_v3_captures(run_id): return
		get_tree().quit(0)
		return

	if _spider_capture_only:
		if not await _run_spider_v2_captures(run_id): return
		get_tree().quit(0)
		return

	if _finisher_capture_only:
		if not await _run_finisher_v2_captures(run_id): return
		get_tree().quit(0)
		return

	if _flora_capture_only:
		if not await _run_flora_v2_captures(run_id): return
		get_tree().quit(0)
		return

	# 1. SQUARE 1 — MEADOW IDLE & WALK TRAIL
	_demo_phase = "01 · WIESE & FUSSSPUR"
	_update_ui_text()
	if not await _wait_sec(run_id, 0.45): return
	_metrics["idle"] = true
	await _save_shot("01_sq1_meadow_noon.png")

	if not await _hold(run_id, [&"move_right"], 0.65): return
	var walk_mid_pos: Vector2 = _player.position
	if not await _hold(run_id, [&"move_right"], 0.65): return
	_metrics["walk"] = _player.position.x > 16.0
	_metrics["walk_crush"] = _grass != null and _grass.crush_at(walk_mid_pos) >= 0.45

	if not await _hold(run_id, [&"move_left", &"move_up"], 1.10): return
	_metrics["trail_persists"] = _grass != null and _grass.crush_at(walk_mid_pos) >= 0.22

	# 2. SNEAK, SPRINT, SHADOW STEP & COMBO ON SQUARE 1
	_demo_phase = "02 · SCHLEICHEN & SPRINT"
	_update_ui_text()
	if not await _hold(run_id, [&"move_right", &"move_down", &"sneak"], 0.85): return
	_metrics["sneak"] = true

	_player.position = Vector2(-115.0, 22.0)
	_player._camera.reset_smoothing()
	_player.stamina.current = _player.stamina.max_stamina
	if not await _hold(run_id, [&"move_right", &"sprint"], 0.50): return
	var sprint_mid: Vector2 = _player.position
	if not await _hold(run_id, [&"move_right", &"sprint"], 0.55): return
	_metrics["sprint"] = true
	_metrics["sprint_crush"] = _grass != null and _grass.crush_at(sprint_mid) >= 0.70

	_player.position = Vector2(-50.0, -4.0)
	_player._camera.reset_smoothing()
	_player.stamina.current = _player.stamina.max_stamina
	var step_start: Vector2 = _player.position
	Input.action_press(&"move_right")
	if not await _tap(run_id, &"shadow_step", 0.05): return
	if not await _wait_sec(run_id, 0.35): return
	Input.action_release(&"move_right")
	_metrics["shadow_step"] = true
	_metrics["step_burst"] = _grass != null and _grass.crush_at(step_start) >= 0.65

	InputManager.using_mouse = false
	_player.facing = Vector2.RIGHT
	var slash_probe: Vector2 = _player.position + Vector2(20.0, 0.0)
	for strike: int in 3:
		if not await _tap(run_id, &"action_primary", 0.08): return
		if strike == 1 and _grass != null and _grass.crush_at(slash_probe) >= 0.18:
			_metrics["slash_wave"] = true
		if not await _wait_sec(run_id, 0.22): return
	_metrics["combo"] = true
	if not await _hold(run_id, [&"action_secondary"], 0.58): return
	_metrics["heavy"] = true

	# 3. SQUARE 2 — PATHS & ANTIQUE STONE SLABS WALKTHROUGH!
	_demo_phase = "03 · PFADE & ANTIKE STEINPLATTEN"
	_update_ui_text()
	_player.position = Vector2(210.0, 12.0)
	_player._camera.reset_smoothing()
	if _grass != null:
		_grass.recenter_field(_player.position)
	# Walk along the warm dirt path right onto the Moon-Ring Rondell (leaves dusty trail!)
	if not await _hold(run_id, [&"move_right"], 1.95): return
	await _save_shot("02_sq2_paths_stones_noon.png")

	if _capture_only:
		# 2x Macro on the Hero Moon-Ring Rondell, weathered slabs & seam grass
		_player.position = Vector2(384.0, 22.0)
		_player._camera.reset_smoothing()
		_zoom_macro = true
		_apply_camera_zoom()
		if not await _wait_sec(run_id, 0.18): return
		await _save_shot("02b_sq2_rondell_2x.png")
		# 2x Macro on NW stepping-stone arc + gravel track
		_player.position = Vector2(288.0, -56.0)
		_player._camera.reset_smoothing()
		if not await _wait_sec(run_id, 0.18): return
		await _save_shot("02c_sq2_stepping_gravel_2x.png")
		_zoom_macro = false
		_apply_camera_zoom()

	# 4. SQUARE 3 — WOODLAND FLOOR, MOSS, MUD & MIRROR PUDDLE!
	_demo_phase = "04 · WALDBODEN, MOOS & PFÜTZE"
	_update_ui_text()
	_player.position = Vector2(736.0, -48.0)
	_player._camera.reset_smoothing()
	if _grass != null:
		_grass.recenter_field(_player.position)
	# Walk right through the woodland mirror puddle -> splashes + tracks wet prints onto humus & stone!
	if not await _hold(run_id, [&"move_right"], 1.25): return
	await _save_shot("03_sq3_forest_floor_noon.png")

	if _capture_only:
		# 2x Macro on forest puddle shore, mossy stones, mushrooms & creeping roots
		_player.position = Vector2(752.0, -46.0)
		_player._camera.reset_smoothing()
		_zoom_macro = true
		_apply_camera_zoom()
		if not await _wait_sec(run_id, 0.18): return
		await _save_shot("03b_sq3_forest_puddle_2x.png")
		# 2x Macro on damp earth, mud hollow, moss banks & forest ferns
		_player.position = Vector2(822.0, 48.0)
		_player._camera.reset_smoothing()
		if not await _wait_sec(run_id, 0.18): return
		await _save_shot("03c_sq3_forest_mud_moss_2x.png")
		_zoom_macro = false
		_apply_camera_zoom()

		# Transition shot right at Square 1 <-> Square 2 boundary
		_player.position = Vector2(192.0, 6.0)
		_player._camera.reset_smoothing()
		if not await _wait_sec(run_id, 0.18): return
		await _save_shot("04_transition_meadow_to_paths.png")

		# Transition shot right at Square 2 <-> Square 3 boundary
		_player.position = Vector2(576.0, 4.0)
		_player._camera.reset_smoothing()
		if not await _wait_sec(run_id, 0.18): return
		await _save_shot("05_transition_paths_to_forest.png")

		# Golden Hour across Square 2 Antique Stones & Paths
		_player.position = Vector2(384.0, 14.0)
		_player._camera.reset_smoothing()
		_apply_time(1)
		_apply_weather(1)
		if not await _wait_sec(run_id, 0.30): return
		await _save_shot("06_sq2_golden_hour.png")

		# Night Glow across Square 2 Moon-Ring Rondell (carved runes shimmer!) & Square 3 Forest Mushrooms!
		_apply_time(3)
		_apply_weather(0)
		if not await _wait_sec(run_id, 0.30): return
		await _save_shot("07_sq2_night_ruins_glow.png")
		_player.position = Vector2(768.0, -10.0)
		_player._camera.reset_smoothing()
		if not await _wait_sec(run_id, 0.25): return
		await _save_shot("08_sq3_night_forest_glow.png")

		# Rain & Wet Sheen across Square 2 Antique Stones & Paths
		_apply_time(0)
		_apply_weather(2)
		_player.position = Vector2(384.0, 14.0)
		_player._camera.reset_smoothing()
		if not await _wait_sec(run_id, 0.30): return
		await _save_shot("09_sq2_rain_wet_stones.png")

		# ---------------- SQUARE 4: LIVING TREE 2.0 (GLIMMTAL-STIELEICHE) SHOWCASE! ----------------
		if not await _run_tree_v3_captures(run_id): return

		# Verify toroidal ring-buffer recentering preserves world-locked grass trails across shifts!
		_player.position = Vector2(0.0, 0.0)
		_player._camera.reset_smoothing()
		_grass.recenter_field(Vector2.ZERO)
		var probe_p: Vector2 = Vector2(12.0, 12.0)
		_grass.stamp_rest_nest(probe_p, 14.0, 0.9, 3.0)
		var c_before: float = _grass.crush_at(probe_p)
		var shifted: bool = _grass.recenter_field(Vector2(48.0, 32.0))
		var c_after: float = _grass.crush_at(probe_p)
		_grass.recenter_field(Vector2.ZERO)
		_metrics["toroidal_recenter"] = shifted and c_before >= 0.70 and c_after >= 0.70

		if not await _run_water_v2_captures(run_id): return
		if not await _run_water_v2_tests(run_id): return
		_finish_test_run()
		return

	if _test_mode:
		_grass.recenter_field(Vector2.ZERO)
		var probe_p: Vector2 = Vector2(12.0, 12.0)
		_grass.stamp_rest_nest(probe_p, 14.0, 0.9, 3.0)
		var c_before: float = _grass.crush_at(probe_p)
		var shifted: bool = _grass.recenter_field(Vector2(48.0, 32.0))
		var c_after: float = _grass.crush_at(probe_p)
		_metrics["toroidal_recenter"] = shifted and c_before >= 0.70 and c_after >= 0.70
		if not await _run_water_v2_tests(run_id): return
		_finish_test_run()
		return

	_demo_active = false
	_demo_phase = "FERTIG — [1-3] WIESE/PFAD/WALD  [4-6] BACH/STRAND/SEE  [7] HAIN"
	_update_ui_text()


func _move_player_for_shot(pos: Vector2) -> void:
	_player.position = pos
	_player.velocity = Vector2.ZERO
	_player._camera.reset_smoothing()
	if _grass != null:
		_grass.recenter_field(pos)
	if _birch_grass != null:
		_birch_grass.recenter_field(pos)
	if _apple_grass != null:
		_apple_grass.recenter_field(pos)
	if _water_field != null:
		_water_field.recenter_wave_field(pos)


func _run_apple_captures(run_id: int) -> bool:
	_demo_phase = "05C · WILDAPFEL-AUE (WILD APPLE)"
	_apply_time(0)
	_apply_weather(1)
	_zoom_macro = false
	_apply_camera_zoom()

	# 1. Full Noon Wild-Apple Meadow Overview (Square 4S: West Spring Blossom + East Ripe Fruit Load!)
	if is_instance_valid(_apple_mother):
		_apple_mother._spawn_petal_burst(10)
	_move_player_for_shot(Vector2(1112.0, 412.0))
	_player.facing = Vector2.UP
	_player._camera.offset = Vector2(40.0, -160.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("30_sq4s_apple_meadow_noon.png")
	_player._camera.offset = Vector2.ZERO

	# 2. Seamless Oak-to-Apple South Passage Shot (Square 4 Oaks above -> footpath -> Square 4S Wild-Apples below!)
	_move_player_for_shot(Vector2(1148.0, 152.0))
	_player.facing = Vector2.DOWN
	_player._camera.offset = Vector2(4.0, 26.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.28): return false
	await _save_shot("30b_oak_to_apple_south_passage.png")

	# 3. 2x Macro on Hollow Blossom-Mother (`s5` Sacred Mistletoe + Drehwuchs Bark Bridge + Blütenschnee) & Leaning Blossom Apple (`s4_c`)
	_zoom_macro = true
	_apply_camera_zoom()
	if is_instance_valid(_apple_mother):
		_apple_mother._spawn_petal_burst(14)
	_move_player_for_shot(Vector2(1062.0, 394.0))
	_player._camera.offset = Vector2(-24.0, -232.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("31a_sq4s_blossom_mother_mistletoe_2x.png")

	# 4. 2x Macro on Fruiting Pair (`s4_b` Streuobst-Zwiesel + `s4` Solitary with +2 px Fruit-Droop & Spring Pool!)
	_move_player_for_shot(Vector2(1254.0, 398.0))
	_player._camera.offset = Vector2(0.0, -224.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("31b_sq4s_fruiting_pair_spring_2x.png")

	# 5. 2x Tree-Shake Harvest Action: Ripe Wild Apples + Sacred Mistletoe Rain Down & Outer Boughs Spring Back Up!
	if is_instance_valid(_apple_fruiting):
		_apple_fruiting._server_pick_bark()
	if is_instance_valid(_apple_zwiesel):
		_apple_zwiesel._server_pick_bark()
	if not await _wait_sec(run_id, 0.78): return false
	await _save_shot("31c_sq4s_shake_harvest_drops_2x.png")

	# 6. 2x Walk-Behind Apple Crown: Synchronized Bayer 4x4 Iris on Cupped Rosettes & Upper Trunk!
	_player._camera.offset = Vector2.ZERO
	_move_player_for_shot(Vector2(1216.0, 274.0))
	_player.facing = Vector2.DOWN
	if not await _wait_sec(run_id, 0.28): return false
	await _save_shot("31d_sq4s_apple_walk_behind_iris_2x.png")
	_zoom_macro = false
	_apply_camera_zoom()

	# 7. Scarlet-Crimson & Apricot-Gold Orchard Autumn (`autumn_hue = 2.0`) below Bronze-Copper Oaks!
	_apply_time(1)
	_apply_weather(1)
	for tr: LivingTree in _trees:
		if is_instance_valid(tr):
			tr.set_autumn_shift(0.86)
	_move_player_for_shot(Vector2(1112.0, 412.0))
	_player._camera.offset = Vector2(40.0, -160.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("32_sq4s_scarlet_crimson_autumn.png")
	for tr: LivingTree in _trees:
		if is_instance_valid(tr):
			tr.set_autumn_shift(0.0)

	# 8. Moonlit Night: Silver-Rose Blossom Shimmer & Sacred Mistletoe Pearl Berries (`Unlit`)!
	_apply_time(3)
	_apply_weather(0)
	if not await _wait_sec(run_id, 0.40): return false
	await _save_shot("33_sq4s_night_moon_blossoms_mistletoe.png")
	_player._camera.offset = Vector2.ZERO

	# 9. Axe Felling & Salmon-Rose Heartwood Coppice (`Stockausschlag`)!
	_apply_time(0)
	_apply_weather(0)
	if is_instance_valid(_apple_zwiesel):
		var needed_hits: int = int(_apple_zwiesel.state.get("hp", 6))
		for _h: int in needed_hits:
			_apple_zwiesel.strike_with_axe(Vector2(1196.0, 326.0))
			if not await _wait_sec(run_id, 0.06): return false
		if not await _wait_sec(run_id, 1.55): return false
		_apple_zwiesel.advance_growth_days(3)
		_zoom_macro = true
		_apply_camera_zoom()
		_move_player_for_shot(Vector2(1192.0, 336.0))
		_player.facing = Vector2.RIGHT
		if not await _wait_sec(run_id, 0.25): return false
		await _save_shot("34_sq4s_apple_coppice_heartwood.png")
		_zoom_macro = false
		_apply_camera_zoom()
	return true


func _run_birch_captures(run_id: int) -> bool:
	_demo_phase = "05B · BIRKENLICHTUNG (SILVER BIRCH)"
	_apply_time(0)
	_apply_weather(1)
	_zoom_macro = false
	_apply_camera_zoom()

	# 1. Full Noon Birch Clearing Overview (Square 4N directly north of Oak Glade; 100% un-peeled crowns!)
	_move_player_for_shot(Vector2(1148.0, -154.0))
	_player.facing = Vector2.UP
	_player._camera.offset = Vector2(4.0, -134.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("20_sq4n_birch_clearing_noon.png")
	_player._camera.offset = Vector2.ZERO

	# 2. Seamless Oak-to-Birch North Passage Shot (Square 4 Oaks below -> winding trail -> Square 4N Silver Birches above!)
	_move_player_for_shot(Vector2(1142.0, -138.0))
	_player.facing = Vector2.UP
	_player._camera.offset = Vector2(10.0, -28.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.28): return false
	await _save_shot("20b_oak_to_birch_north_passage.png")

	# 3. 2x Macro on Silver Birch Bark, Borkenfuß, Multi-Stem Clump (`s4_b`), Solitary (`s4`), & Mirror Peat-Pool!
	_zoom_macro = true
	_apply_camera_zoom()
	_move_player_for_shot(Vector2(1214.0, -162.0))
	_player._camera.offset = Vector2(16.0, -104.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("21a_sq4n_birch_trunks_clump_puddle_2x.png")

	# 4. 2x Macro on Grove Mother (`s5` Funken-Chaga + Rollrinde), Wind-Arched Birch (`s4_c`), & Fallen White Nurse Log (`s6_log`)
	_move_player_for_shot(Vector2(1062.0, -162.0))
	_player._camera.offset = Vector2(6.0, -126.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("21b_sq4n_mother_arch_nurselog_2x.png")

	# 5. 2x Walk-Behind Birch Crown: Synchronized Bayer 4x4 Iris on Weeping Leaves & White Upper Stem!
	_player._camera.offset = Vector2.ZERO
	_move_player_for_shot(Vector2(1218.0, -296.0))
	_player.facing = Vector2.DOWN
	if not await _wait_sec(run_id, 0.28): return false
	await _save_shot("21c_sq4n_birch_walk_behind_iris_2x.png")
	_zoom_macro = false
	_apply_camera_zoom()

	# 6. Golden Autumn Comparison: Luminous Nordic Lemon-Gold Birches (`autumn_hue = 1.0`) above Bronze-Copper Oaks!
	_apply_time(1)
	_apply_weather(1)
	for tr: LivingTree in _trees:
		if is_instance_valid(tr):
			tr.set_autumn_shift(0.84)
	_move_player_for_shot(Vector2(1148.0, -154.0))
	_player._camera.offset = Vector2(4.0, -134.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.32): return false
	await _save_shot("22_sq4n_birch_nordic_gold_autumn.png")
	_player._camera.offset = Vector2.ZERO
	for tr: LivingTree in _trees:
		if is_instance_valid(tr):
			tr.set_autumn_shift(0.0)

	# 7. Night Moonlit White Birch Bark, Glowing Funken-Chaga & Mycorrhizal Resonance!
	_apply_time(3)
	_apply_weather(0)
	_move_player_for_shot(Vector2(1152.0, -184.0))
	_player._camera.offset = Vector2(0.0, -96.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 1.85): return false
	await _save_shot("23_sq4n_birch_night_moon_chaga.png")
	_player._camera.offset = Vector2.ZERO

	# 8. Birch Axe Chop (from right -> falls left into sunlit meadow!) -> Multi-Shoot Birch Coppice (`Stockausschlag`)!
	_apply_time(0)
	_apply_weather(0)
	_move_player_for_shot(Vector2(1316.0, -242.0))
	_player.facing = Vector2.LEFT
	_player._camera.offset = Vector2(-156.0, -44.0)
	_player._camera.reset_smoothing()
	if is_instance_valid(_birch_solitary):
		while not _birch_solitary.is_depleted():
			_birch_solitary.strike_with_axe(_player.position)
		var sw: int = 0
		while _birch_solitary.is_falling() and sw < 32:
			if not await _wait_sec(run_id, 0.12): return false
			sw += 1
		_birch_solitary.advance_growth_days(2)
		if not await _wait_sec(run_id, 0.25): return false
		await _save_shot("24_sq4n_birch_coppice_drops.png")
	_player._camera.offset = Vector2.ZERO
	return true


func _run_tree_v3_captures(run_id: int) -> bool:
	_demo_phase = "05 · GLIMMTAL-HAIN (LIVING TREE 2.0)"
	_apply_time(0)
	_apply_weather(1)
	_zoom_macro = false
	_apply_camera_zoom()

	# 1. Full Noon Glade Overview (Ellie in sunny foreground meadow outside seat prompt radius; 100% un-peeled crowns!)
	_move_player_for_shot(Vector2(1182.0, 92.0))
	_player.facing = Vector2.UP
	_player._camera.offset = Vector2(-26.0, -80.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("10_sq4_oak_glade_noon.png")
	_player._camera.offset = Vector2.ZERO

	# 2. 2x Macro on Crown anatomy, branch-wrapping foliage & trait contrast (`s5` Matriarch vs `s4` Solitary vs `s4_b` Twin)
	_zoom_macro = true
	_apply_camera_zoom()
	_move_player_for_shot(Vector2(1188.0, 92.0))
	_player._camera.offset = Vector2(24.0, -96.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.24): return false
	await _save_shot("10b_sq4_crown_anatomy_traits_2x.png")

	# 3. 2x Macro on Crown-Shyness Pair (`s4` + `s4_b`) + Woodland Mirror Puddle reflection
	_player._camera.offset = Vector2(0.0, -42.0)
	_move_player_for_shot(Vector2(1264.0, 68.0))
	if not await _wait_sec(run_id, 0.24): return false
	await _save_shot("10c_sq4_crown_shyness_puddle_2x.png")

	# 4. 2x Macro on Woodland-Edge Asymmetric Oak (`s4_c` dark ivy + root scar) & Young Pole Oak (`s3` epicormic sprig)
	_player._camera.offset = Vector2(0.0, -52.0)
	_move_player_for_shot(Vector2(996.0, 56.0))
	if not await _wait_sec(run_id, 0.24): return false
	await _save_shot("10d_sq4_asymmetric_ivy_and_pole_2x.png")

	# 5. 2x Macro Walk-Behind Crown: Synchronized Bayer 4x4 Iris on BOTH Canopy & UpperTrunk (zero bare beams!)
	_player._camera.offset = Vector2.ZERO
	_move_player_for_shot(Vector2(1224.0, -16.0))
	_player.facing = Vector2.DOWN
	if not await _wait_sec(run_id, 0.28): return false
	await _save_shot("10e_sq4_walk_behind_bayer_iris_2x.png")
	_zoom_macro = false
	_apply_camera_zoom()

	# 6. Golden Hour + Highland Autumn Bronze-Gold Phenology + Swaying Multi-Cluster SunShadows!
	_apply_time(1)
	_apply_weather(1)
	for tr: LivingTree in _trees:
		if is_instance_valid(tr):
			tr.set_autumn_shift(0.78)
	_move_player_for_shot(Vector2(1182.0, 92.0))
	_player._camera.offset = Vector2(-26.0, -80.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 0.32): return false
	await _save_shot("11_sq4_golden_autumn_shadows.png")
	_player._camera.offset = Vector2.ZERO
	for tr: LivingTree in _trees:
		if is_instance_valid(tr):
			tr.set_autumn_shift(0.0)

	# 7. Night Poetic Bioluminescence + Subtle "Ellie = Shadowspore" Mycorrhizal Root Resonance!
	_apply_time(3)
	_apply_weather(0)
	_move_player_for_shot(Vector2(1140.0, 66.0))
	_player._camera.offset = Vector2(0.0, -38.0)
	_player._camera.reset_smoothing()
	if not await _wait_sec(run_id, 1.85): return false
	await _save_shot("12_sq4_night_mycelia_glow.png")
	_player._camera.offset = Vector2.ZERO

	# 8. Noon Axe Kerf Wedge -> Nonlinear Felling onto LivingGrass -> Coppice Stockausschlag!
	_apply_time(0)
	_apply_weather(0)
	_move_player_for_shot(Vector2(1206.0, 54.0))
	_player.facing = Vector2.RIGHT
	if is_instance_valid(_oak_mature):
		for _h: int in 3:
			_oak_mature.strike_with_axe(_player.position)
		if not await _wait_sec(run_id, 0.20): return false
		await _save_shot("13a_sq4_axe_kerf_notch.png")
		while not _oak_mature.is_depleted():
			_oak_mature.strike_with_axe(_player.position)
		if not await _wait_sec(run_id, 1.55): return false
		await _save_shot("13b_sq4_felled_grass_crush.png")
		var safety_w: int = 0
		while _oak_mature.is_falling() and safety_w < 30:
			if not await _wait_sec(run_id, 0.12): return false
			safety_w += 1
		_oak_mature.advance_growth_days(3)
		if not await _wait_sec(run_id, 0.25): return false
		await _save_shot("13c_sq4_coppice_stockausschlag.png")
	return true


func _run_water_v2_captures(run_id: int) -> bool:
	_demo_phase = "06 · WATER SYSTEM v2 CAPTURES"
	# 1. Noon overview across Square -2 (beach/tidepools) & Square -1 (brook/bridge/puddles)
	_apply_time(0)
	_apply_weather(0)
	_zoom_macro = false
	_apply_camera_zoom()
	_move_player_for_shot(Vector2(-576.0, 0.0))
	if _water_field != null:
		_water_field.add_water_impulse(Vector2(-384.0, 32.0), 0.9, 8.0, Vector2.DOWN)
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("noon.png")

	# 2. Golden hour across coast & ancient stone bridge
	_apply_time(1)
	_apply_weather(1)
	_move_player_for_shot(Vector2(-576.0, 0.0))
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("golden_hour.png")

	# 3. Night bioluminescence + bridge lunar runes & lantern + coastal glow
	_apply_time(3)
	_apply_weather(0)
	_move_player_for_shot(Vector2(-660.0, 0.0))
	if _water_field != null:
		_water_field.add_water_impulse(Vector2(-754.0, 12.0), 1.1, 10.0, Vector2.RIGHT)
	if not await _wait_sec(run_id, 0.50): return false
	await _save_shot("night_biolum.png")

	# 4. Storm whitecaps on Square -3 open ocean & growing rain puddles on Square -2
	_apply_time(0)
	_apply_weather(3)
	_move_player_for_shot(Vector2(-944.0, 0.0))
	if not await _wait_sec(run_id, 0.75): return false
	await _save_shot("storm_whitecaps.png")

	# 5. Macro zoom 2x on Ancient Stone Arch Bridge, pier wakes, arch shadow & east approach puddle
	_apply_time(0)
	_apply_weather(1)
	_zoom_macro = true
	_apply_camera_zoom()
	_move_player_for_shot(Vector2(-366.0, 6.0))
	if _water_field != null:
		_water_field.add_water_impulse(Vector2(-316.0, 26.0), 0.85, 7.0, Vector2.ZERO)
	if not await _wait_sec(run_id, 0.30): return false
	await _save_shot("macro_bridge.png")

	# 6. Macro zoom 2x on coastal surf, tidepool rocks & wet swash sand
	_apply_time(0)
	_apply_weather(1)
	_move_player_for_shot(Vector2(-722.0, -48.0))
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("macro_surf.png")

	_zoom_macro = false
	_apply_camera_zoom()
	_apply_weather(0)
	_apply_time(0)
	_move_player_for_shot(Vector2.ZERO)
	return true


func _run_water_v2_polish_captures(run_id: int) -> bool:
	var prev_ui: bool = _ui_layer.visible if _ui_layer != null else true
	if _ui_layer != null:
		_ui_layer.visible = false
	_player.visible = false
	_apply_time(0)
	_apply_weather(1)

	# 1. Screenshot 1 spot: Ocean-to-shelf-to-surf smooth contour transition (3x macro)
	_move_player_for_shot(Vector2(-956.0, 0.0))
	_player._camera.zoom = Vector2(3.0, 3.0)
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("01_ocean_shelf_3x.png")

	# 2. Screenshot 2 & 6 spot: Surf lace foam, wet sand, starfish, shells & hero driftwood across 3 timestamps (0.0s, +0.5s, +1.0s)
	_move_player_for_shot(Vector2(-738.0, -4.0))
	_player._camera.zoom = Vector2(3.0, 3.0)
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("02a_surf_props_t00_3x.png")
	if not await _wait_sec(run_id, 0.50): return false
	await _save_shot("02b_surf_props_t05_3x.png")
	if not await _wait_sec(run_id, 0.50): return false
	await _save_shot("02c_surf_props_t10_3x.png")

	# 3. Screenshot 3 & 7 spot: Dry beach sand ripples + bright turquoise beach puddle (3x macro)
	_move_player_for_shot(Vector2(-676.0, 34.0))
	_player._camera.zoom = Vector2(3.0, 3.0)
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("03_beach_sand_and_puddle_3x.png")

	# 4. Screenshot 4 spot: Coastal dune Strandhafer grass & meadow transition (3x macro)
	_move_player_for_shot(Vector2(-598.0, -28.0))
	_player._camera.zoom = Vector2(3.0, 3.0)
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("04_coastal_dune_strandhafer_3x.png")

	# 5. Screenshot 5 spot: Tidepool rock on rocky surf headland with live wave-lap splash collar (3x macro, 2 phases)
	_move_player_for_shot(Vector2(-744.0, -88.0))
	_player._camera.zoom = Vector2(3.5, 3.5)
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("05a_tidepool_rock_lap_a_3x.png")
	if not await _wait_sec(run_id, 0.85): return false
	await _save_shot("05b_tidepool_rock_lap_b_3x.png")

	# 6. Screenshot 8 spot: Brookside puddles near bridge (NW & East) — unclipped & glassy (3x macro)
	_move_player_for_shot(Vector2(-456.0, -34.0))
	_player._camera.zoom = Vector2(3.2, 3.2)
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("06a_brook_puddle_nw_bridge_3x.png")
	_move_player_for_shot(Vector2(-318.0, 22.0))
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("06b_brook_puddle_east_bridge_3x.png")

	# 7. Screenshot 9 spot: Forest brook bank, riparian moss, rounded shingle, reeds & lilies across 2 timestamps (+0.5s, +1.0s)
	_move_player_for_shot(Vector2(-404.0, -82.0))
	_player._camera.zoom = Vector2(3.0, 3.0)
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("07a_brook_bank_reeds_t00_3x.png")
	if not await _wait_sec(run_id, 0.50): return false
	await _save_shot("07b_brook_bank_reeds_t05_3x.png")
	if not await _wait_sec(run_id, 0.50): return false
	await _save_shot("07c_brook_bank_reeds_t10_3x.png")

	_player.visible = true
	if _ui_layer != null:
		_ui_layer.visible = prev_ui
	_zoom_macro = false
	_apply_camera_zoom()
	return true



func _count_puddles_in_range(x_min: float, x_max: float) -> int:
	if _water_field == null:
		return 0
	var hits: int = 0
	var y: float = -132.0
	while y <= 132.0:
		var x: float = x_min
		while x <= x_max:
			var p: Vector2 = Vector2(x, y)
			if (_water_bridge == null or not _water_bridge.has_water_deck_at(p)) and _water_field.surface_at(p) == "puddle":
				hits += 1
			x += 4.0
		y += 4.0
	return hits


func _count_wet_footprints_near(center: Vector2, radius: float) -> int:
	var canvas: Node = get_tree().current_scene.get_node_or_null("FootprintCanvas") if get_tree().current_scene != null else null
	if canvas == null:
		canvas = get_node_or_null("FootprintCanvas")
	if canvas == null:
		return 0
	var pool: Variant = canvas.get(&"_pool")
	if not (pool is Array):
		return 0
	var cnt: int = 0
	var wet_col: Color = Color("#1c2b33")
	for item_v: Variant in (pool as Array):
		var item: Object = item_v as Object
		if item == null or not bool(item.get(&"active")):
			continue
		var pos: Vector2 = item.get(&"pos") as Vector2
		var col: Color = item.get(&"color") as Color
		if pos.distance_to(center) <= radius and col.is_equal_approx(wet_col):
			cnt += 1
	return cnt


func _run_water_v2_tests(run_id: int) -> bool:
	_demo_phase = "07 · WATER SYSTEM v2 QA"
	_apply_time(0)
	_apply_weather(0)
	_zoom_macro = false
	_apply_camera_zoom()

	if _water_field == null or _water_bridge == null or _player == null:
		return true

	# 1. Square -1 Brook regime & northern deep Kolk
	var kolk_pos: Vector2 = Vector2(-388.0, -94.0)
	var kolk_info: Dictionary = _water_field.water_field_at(kolk_pos)
	var brook_flow: Vector2 = _water_field.water_flow_at(Vector2(-384.0, -40.0))
	_metrics["water_brook_regime"] = (
		Terrain.patches.has(_water_field)
		and int(kolk_info.get("regime", 0)) == WaterRules.REGIME_BROOK
		and bool(kolk_info.get("water", false))
		and float(kolk_info.get("depth", 0.0)) >= 0.60
		and _water_field.is_deep(kolk_pos)
		and brook_flow.y > 0.5
	)

	# 2. Square -1 Southern Gravel Ford wading
	var ford_pos: Vector2 = Vector2(-372.0, 96.0)
	var ford_info: Dictionary = _water_field.water_field_at(ford_pos)
	_move_player_for_shot(ford_pos)
	if not await _wait_sec(run_id, 0.12): return false
	var ford_surf: Dictionary = _player.get(&"_surface") as Dictionary
	_metrics["water_ford_wade"] = (
		float(ford_info.get("depth", 1.0)) < 0.35
		and not _water_field.is_deep(ford_pos)
		and Terrain.surface_at(ford_pos) == "shallow_water"
		and String(_player.get(&"_surface_id")) == "shallow_water"
		and bool(ford_surf.get("water", false))
		and float(ford_surf.get("submerge", 0.0)) > 0.0
		and bool(ford_surf.get("ripples", false))
		and int(_player.get(&"swim")) == SwimRules.NONE
	)

	# 3. WaterBridge dry ancient_stone water_deck suppresses wading/swimming/overlay
	var wf_idx: int = Terrain.patches.find(_water_field)
	var wb_idx: int = Terrain.patches.find(_water_bridge)
	_move_player_for_shot(SQ_NEG1_CENTER)
	if not await _wait_sec(run_id, 0.12): return false
	var wo: Node = _player.get_node_or_null("WaterOverlay")
	var wo_sub: float = float(wo.get(&"submerge")) if wo != null else 0.0
	_metrics["water_bridge_deck"] = (
		wb_idx > wf_idx
		and _water_bridge.has_water_deck_at(SQ_NEG1_CENTER)
		and Terrain.surface_at(SQ_NEG1_CENTER) == "ancient_stone"
		and _player.has_meta(&"water_deck")
		and String(_player.get(&"_surface_id")) == "ancient_stone"
		and int(_player.get(&"swim")) == SwimRules.NONE
		and wo_sub <= 0.001
	)

	# 4. Coastal swash synchrony (WaterRules.shore_state_at == WaterField.surface_at for stationary player)
	var dyn_pos: Vector2 = Vector2(-752.0, 0.0)
	var best_dyn_states: int = 0
	var scan_x: float = -766.0
	while scan_x <= -734.0:
		var cand: Vector2 = Vector2(scan_x, 0.0)
		var c_info: Dictionary = _water_field.water_field_at(cand)
		if int(c_info.get("regime", 0)) == WaterRules.REGIME_SURF and _water_field.has_dynamic_water(cand):
			var c_sdf: float = float(c_info.get("static_sdf_px", 0.0))
			var st_set: Dictionary = {}
			for s_i: int in 16:
				st_set[WaterRules.shore_state_at(c_sdf, cand.y, float(s_i) * 0.34, _wind.direction, _wind.gust, 0.0)] = true
			if st_set.size() > best_dyn_states:
				best_dyn_states = st_set.size()
				dyn_pos = cand
		scan_x += 2.0
	_move_player_for_shot(dyn_pos)
	if not await _wait_sec(run_id, 0.08): return false
	var sync_hits: int = 0
	var sync_mismatches: int = 0
	var seen_coast: Dictionary = {}
	var dyn_sdf: float = float(_water_field.water_field_at(dyn_pos).get("static_sdf_px", 0.0))
	for tick_i: int in 5:
		var rule_st: String = WaterRules.shore_state_at(dyn_sdf, dyn_pos.y, _water_field._frame_water_time, _water_field._snap_wind_dir, _water_field._snap_wind_gust, _water_field._snap_storm)
		var field_st: String = _water_field.surface_at(dyn_pos)
		var p_st: String = String(_player.get(&"_surface_id"))
		seen_coast[field_st] = true
		if field_st == rule_st and p_st == field_st:
			sync_hits += 1
		else:
			sync_mismatches += 1
		if not await _wait_sec(run_id, 0.35): return false
	# Also ensure all 3 coastal regimes exist on Square -2
	var seen_sq2: Dictionary = {}
	for sx_i: int in range(-820, -640, 6):
		seen_sq2[_water_field.surface_at(Vector2(float(sx_i), 0.0))] = true
	_metrics["water_coastal_swash_sync"] = (
		sync_hits >= 4
		and sync_mismatches == 0
		and seen_sq2.has("tide_shallow")
		and (seen_sq2.has("wet_sand") or seen_coast.has("wet_sand"))
		and seen_sq2.has("beach_sand")
	)

	# 5. Open-sea swimming + flow drift + distinct biome water colors
	var ocean_pos: Vector2 = Vector2(-1200.0, 0.0)
	_move_player_for_shot(ocean_pos)
	if not await _wait_sec(run_id, 0.40): return false
	var swimmer: Object = _player.get(&"swimmer") as Object
	var ocean_flow: Vector2 = _water_field.water_flow_at(ocean_pos)
	var c_brook: Color = (_water_field.water_color_at(kolk_pos) as Dictionary).get("fill", Color.BLACK) as Color
	var c_beach: Color = (_water_field.water_color_at(Vector2(-770.0, 0.0)) as Dictionary).get("fill", Color.BLACK) as Color
	var c_ocean: Color = (_water_field.water_color_at(ocean_pos) as Dictionary).get("fill", Color.BLACK) as Color
	_metrics["water_ocean_swim"] = (
		_water_field.is_deep(ocean_pos)
		and int(_player.get(&"swim")) > 0
		and swimmer != null and bool(swimmer.get(&"active"))
		and ocean_flow.length() > 0.01
		and not c_brook.is_equal_approx(c_beach)
		and not c_beach.is_equal_approx(c_ocean)
		and not c_brook.is_equal_approx(c_ocean)
	)
	_move_player_for_shot(Vector2.ZERO)
	if not await _wait_sec(run_id, 0.15): return false

	# 6. R5 Puddles on Square -1 & -2: surface_at, rain growth, reflects_at, impulse, wet boots on dry ground
	var p1: Vector2 = Vector2(-316.0, 26.0)
	var p2: Vector2 = Vector2(-718.0, -106.0)
	_apply_weather(0)
	if not await _wait_sec(run_id, 0.15): return false
	var dry_pud_n: int = _count_puddles_in_range(-952.0, -200.0)
	_apply_weather(2)
	if not await _wait_sec(run_id, 0.35): return false
	var rain_pud_n: int = _count_puddles_in_range(-952.0, -200.0)
	var g_pud: float = WeatherManager.current.puddle if WeatherManager.current != null else 0.0

	_player.set(&"_wet", 0.0)
	var foot_comp: Node = _player.get_node_or_null("FootstepComponent")
	if foot_comp != null:
		foot_comp.set(&"_puddle_wet", 0.0)
	_move_player_for_shot(p1 - Vector2(12.0, 0.0))
	if not await _hold(run_id, [&"move_right"], 0.45): return false
	var pud_wave: bool = _water_field._wave_active
	var pud_wet_boost: float = float(foot_comp.get(&"_puddle_wet")) if foot_comp != null else 0.0
	var prints_before: int = _count_wet_footprints_near(SQ_NEG1_CENTER, 48.0)
	_move_player_for_shot(SQ_NEG1_CENTER - Vector2(14.0, 0.0))
	if not await _hold(run_id, [&"move_right"], 0.50): return false
	var prints_after: int = _count_wet_footprints_near(SQ_NEG1_CENTER, 48.0)
	_metrics["water_puddles_r5"] = (
		_water_field.surface_at(p1) == "puddle"
		and _water_field.surface_at(p2) == "puddle"
		and _water_field.reflects_at(p1)
		and _water_field.reflects_at(p2)
		and rain_pud_n > dry_pud_n
		and g_pud > 0.3
		and pud_wave
		and pud_wet_boost >= 0.40
		and prints_after > prints_before
	)
	_apply_weather(0)

	# 7. Ringbuffer wave impulse propagation & active-sleep decay
	_move_player_for_shot(kolk_pos)
	if not await _wait_sec(run_id, 0.08): return false
	_water_field.add_water_impulse(kolk_pos, 1.0, 8.0, Vector2.DOWN)
	if not await _wait_sec(run_id, 0.08): return false
	var imp_active: bool = _water_field._wave_active
	_move_player_for_shot(Vector2.ZERO)
	var slept: bool = false
	for _sl: int in 18:
		if not _water_field._wave_active:
			slept = true
			break
		if not await _wait_sec(run_id, 0.15): return false
	_metrics["water_ringbuffer_sleep"] = imp_active and slept

	# 8. Night glow visibility (off by day, on at night)
	var glow_rect: CanvasItem = _water_field.get_node_or_null("WaterGlowRect") as CanvasItem
	_apply_time(0)
	if not await _wait_sec(run_id, 0.06): return false
	var day_off: bool = glow_rect != null and not glow_rect.visible
	_apply_time(3)
	if not await _wait_sec(run_id, 0.08): return false
	var night_on: bool = glow_rect != null and glow_rect.visible
	_apply_time(0)
	if not await _wait_sec(run_id, 0.06): return false
	_metrics["water_night_glow"] = day_off and night_on

	# 9. Weather preset 1 (BRISE) vs WeatherManager._push_wind()
	_apply_weather(1)
	if not await _wait_sec(run_id, 0.45): return false
	var oid: String = WeatherManager.current.override_id if WeatherManager.current != null else ""
	_metrics["water_weather_breeze"] = oid == "broken" and _wind != null and _wind.strength > 0.30 and _wind.gust > 0.05
	_apply_weather(0)

	# 10. Frame-time performance check (avg_frame_ms <= 16.67 over 60 active frames)
	_move_player_for_shot(Vector2(-1040.0, 0.0))
	if not await _wait_sec(run_id, 0.12): return false
	var t0: int = Time.get_ticks_usec()
	for fi: int in 60:
		if fi % 10 == 0:
			_water_field.add_water_impulse(_player.global_position, 0.8, 8.0, Vector2.LEFT)
		await get_tree().physics_frame
		if run_id != _demo_run_id or not is_inside_tree():
			return false
	var avg_ms: float = float(Time.get_ticks_usec() - t0) / (60.0 * 1000.0)
	var is_headless: bool = DisplayServer.get_name() == "headless"
	_metrics["water_perf_60fps"] = avg_ms <= (16.67 if is_headless else 17.5)
	print("Water v2 60-frame avg_frame_ms: %.3f ms (headless=%s)" % [avg_ms, str(is_headless)])

	_move_player_for_shot(Vector2.ZERO)
	if not await _wait_sec(run_id, 0.12): return false
	return true


func _finish_test_run() -> void:
	var failures: int = 0
	print("LivingGrass tufts: ", _grass.tuft_count if _grass != null else 0, " (glow: ", _grass.glow_tuft_count if _grass != null else 0, ")")
	print("GroundSurfaces slabs: ", _surfaces.slab_count if _surfaces != null else 0, " | forest details: ", _surfaces.detail_count if _surfaces != null else 0)
	for k: String in _metrics.keys():
		var ok: bool = bool(_metrics[k])
		print("%s: %s" % ["PASS" if ok else "FAIL", k])
		if not ok:
			failures += 1
	print("GRASS LAB: %d failures" % failures)
	if failures == 0:
		print("GRASS LAB OK")
	get_tree().quit(1 if failures > 0 else 0)


# ---------------- SQUARE 5: GLIMMTAL-STEINHANG (`RockyGround` + `LivingRock`) ----------------

func _setup_rock_ground() -> void:
	_rock_builder = RockSquareBuilder.new()
	_rocky_ground = _rock_builder.setup_ground(self)


func _build_rock_outcrops() -> void:
	if _rock_builder == null:
		return
	var tree_pts: Array[Vector2] = []
	for tr: LivingTree in _trees:
		if is_instance_valid(tr):
			tree_pts.append(tr.position)
	_rock_builder.spawn_outcrops(self, tree_pts)
	_metrics["rock_outcrops_placed"] = _rock_builder.rocks.size() >= 15
	_metrics["rock_surfaces_active"] = (
		_rocky_ground != null
		and Terrain.surface_at(Vector2(1564.0, -58.0)) == "stone"
		and Terrain.surface_at(Vector2(1588.0, 84.0)) == "gravel"
	)


func _toggle_pickaxe_in_hand() -> void:
	if _player == null or _player.inventory == null:
		return
	_holding_pickaxe = not _holding_pickaxe
	_holding_axe = false
	if _holding_pickaxe:
		for i: int in mini(8, _player.inventory.slots.size()):
			var st: Dictionary = _player.inventory.slots[i] as Dictionary
			if not st.is_empty() and String(st.get("id", "")) == "pickaxe_basic":
				_player.inventory.select(i)
				return
	else:
		for i: int in mini(8, _player.inventory.slots.size()):
			var st: Dictionary = _player.inventory.slots[i] as Dictionary
			if st.is_empty() or String(Items.definition(st).get("kind", "")) != "tool":
				_player.inventory.select(i)
				return


func _run_rock_v1_captures(run_id: int) -> bool:
	var prev_ui: bool = _ui_layer.visible if _ui_layer != null else true
	if _ui_layer != null:
		_ui_layer.visible = false
	_apply_layer_mode(0)
	_apply_time(0)
	_apply_weather(0)
	_zoom_macro = false
	_apply_camera_zoom()

	# 1. Seamless Transition from Square 4 Oak Glade -> Square 5 Glimmtal-Steinhang (1x Noon)
	_player.visible = true
	_player.facing = Vector2.RIGHT
	_move_player_for_shot(Vector2(1388.0, 12.0))
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("01_transition_trees_to_rocks_noon.png")

	# 2. Full Square 5 Glimmtal-Steinhang Noon Overview (all 5 sizes s0..s4, bedrock, scree, stony loam & moss!)
	_player.facing = Vector2.UP
	_move_player_for_shot(Vector2(1536.0, 12.0))
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("02_sq5_rock_slope_noon.png")

	# 3. 2x Macro on Hero Stage 4 Massive Tor (`s4_a`), stratified bedrock shelf, lichens & Sempervivum!
	_player.visible = false
	_zoom_macro = true
	_apply_camera_zoom()
	_move_player_for_shot(Vector2(1572.0, -56.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("03_macro_bedrock_tor_lichens_2x.png")

	# 4. 2x Macro on Shaded West Woodland-Edge Mossy Monolith (`s3_a`: cushion moss, ivy, rock-ferns & fungi)
	_move_player_for_shot(Vector2(1418.0, -44.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("04_macro_mossy_monolith_befall_2x.png")

	# 5. 2x Macro on SE Split Erratic Massif (`s4_b`) & Angular Voronoi Scree / Talus Fan!
	_move_player_for_shot(Vector2(1604.0, 66.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("05_macro_split_erratic_scree_2x.png")

	# 6. Golden Hour Long SunShadows across Square 5 Outcrops!
	_zoom_macro = false
	_apply_camera_zoom()
	_player.visible = true
	_apply_time(1)
	_apply_weather(1)
	_move_player_for_shot(Vector2(1536.0, 12.0))
	if not await _wait_sec(run_id, 0.30): return false
	await _save_shot("06_sq5_golden_hour_shadows.png")

	# 7. Rain-Wet Slate & Greywacke Specular Darkening!
	_apply_time(0)
	_apply_weather(2)
	_move_player_for_shot(Vector2(1536.0, 12.0))
	if not await _wait_sec(run_id, 0.30): return false
	await _save_shot("07_sq5_rain_wet_stone.png")

	# 8. Night Whisper-Subtle Crevice Fungi & Dew-Spore Glimmer!
	_apply_time(3)
	_apply_weather(0)
	_move_player_for_shot(Vector2(1536.0, 12.0))
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("08_sq5_night_crevice_glow.png")

	# 9. Progressive Pickaxe Mining Sequence (2.5x Macro: Intact -> Chipped + Cleavage Cracks -> Shattered Rubble + Stone Drops!)
	_apply_time(0)
	_apply_weather(0)
	if not _holding_pickaxe:
		_toggle_pickaxe_in_hand()
	var q_rock: LivingRock = _rock_builder.hero_quarry_s2 if _rock_builder != null else null
	if is_instance_valid(q_rock):
		_player.visible = true
		_player.facing = Vector2.RIGHT
		_move_player_for_shot(q_rock.position + Vector2(-26.0, 2.0))
		_player._camera.zoom = Vector2(2.5, 2.5)
		if not await _wait_sec(run_id, 0.18): return false
		await _save_shot("09a_mining_intact_2_5x.png")

		q_rock.strike_with_pickaxe(_player.global_position)
		q_rock.strike_with_pickaxe(_player.global_position)
		if not await _wait_sec(run_id, 0.14): return false
		await _save_shot("09b_mining_chipped_cleaved_2_5x.png")

		while not q_rock.is_depleted():
			q_rock.strike_with_pickaxe(_player.global_position)
		if not await _wait_sec(run_id, 0.22): return false
		await _save_shot("09c_mining_rubble_drops_2_5x.png")

	if _ui_layer != null:
		_ui_layer.visible = prev_ui
	_zoom_macro = false
	_apply_camera_zoom()
	return true



func _run_paths_v3_captures(run_id: int) -> bool:
	var prev_ui: bool = _ui_layer.visible if _ui_layer != null else true
	if _ui_layer != null:
		_ui_layer.visible = false
	_apply_layer_mode(0)
	_apply_time(0)
	_apply_weather(0)
	_zoom_macro = false
	_apply_camera_zoom()

	# 1. Full 1x Noon Overview of Ordered Square 2 (all 4 arms + Sanctuary Crossroads + Shrine + Stepping Stones!)
	_player.visible = true
	_player.facing = Vector2.RIGHT
	_move_player_for_shot(Vector2(384.0, 0.0))
	if not await _wait_sec(run_id, 0.30): return false
	await _save_shot("01_sq2_overview_noon.png")

	# 1b. Pure Ground & Stone Layer (without LivingGrass) to inspect raw path & masonry geometry
	_apply_layer_mode(1)
	_player.visible = false
	if not await _wait_sec(run_id, 0.16): return false
	await _save_shot("01b_sq2_pure_ground_layer.png")
	_apply_layer_mode(0)

	# 2. 2x Macro: West Country Way (`"path"` — wide packed loam core + trodden grass shoulders + flush West Gateway)
	_zoom_macro = true
	_apply_camera_zoom()
	_move_player_for_shot(Vector2(246.0, 8.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("02_way_path_west_meadow_2x.png")

	# 3. 2x Macro: Central Sanctuary Crossroads Plaza (112x80 flush-jointed stonework + N/S/E/W thresholds)
	_player.visible = true
	_player.facing = Vector2.DOWN
	_move_player_for_shot(Vector2(384.0, 6.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("03_sanctuary_crossroads_2x.png")
	_player.visible = false

	# 4. 2x Macro: North Voronoi Cobble Avenue (`paint_cobble_lane`) + Kerbstones + Aligned 2x2 NW Shrine Terrace
	_move_player_for_shot(Vector2(292.0, -82.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("04_way_cobble_shrine_north_2x.png")

	# 5. 2x Macro: East Twin-Rut Cart Track (`"cart"` — sunken wheel ruts + living short-grass median -> Woodland)
	_move_player_for_shot(Vector2(526.0, 0.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("05_way_cart_track_east_2x.png")

	# 6. 2x Macro: South Meadow Footpath (`"trail"`) + 5 Rhythmic Flush Stepping Stones & Damp Trail Fork
	_move_player_for_shot(Vector2(296.0, 74.0))
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("06_way_trail_stepping_south_2x.png")

	# 7. 1x Golden Hour across Square 2 Sanctuary Stonework & Paths
	_zoom_macro = false
	_apply_camera_zoom()
	_player.visible = true
	_player.facing = Vector2.UP
	_apply_time(1)
	_apply_weather(1)
	_move_player_for_shot(Vector2(384.0, 0.0))
	if not await _wait_sec(run_id, 0.30): return false
	await _save_shot("07_sq2_golden_hour.png")

	# 8. 1x Night Sanctuary Rune Glow & Rain-Wet Sheen
	_apply_time(3)
	_apply_weather(0)
	if not await _wait_sec(run_id, 0.30): return false
	await _save_shot("08_sq2_night_glow.png")

	_apply_time(0)
	_apply_weather(2)
	if not await _wait_sec(run_id, 0.30): return false
	await _save_shot("09_sq2_rain_wet.png")

	if _ui_layer != null:
		_ui_layer.visible = prev_ui
	_zoom_macro = false
	_apply_camera_zoom()
	return true


# ====================================================================================================
# SHADOW SPIDER 2.0 — INTERACTIVE COMBAT LAB & VISUAL VERIFICATION SUITE (`T1`..`T7`, `V1`..`V7`)
# ====================================================================================================

func _spawn_lab_spider(at: Vector2, variant_idx: int = 0, ambush: int = ShadowSpider.AmbushKind.NONE, face_angle: float = PI * 0.5) -> ShadowSpider:
	if not multiplayer.is_server() or _enemies == null:
		return null
	var sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	_enemy_count += 1
	sp.name = "SpiderV2_%d" % _enemy_count
	sp.brood_variant = variant_idx
	sp.ambush_mode = ambush
	sp.position = _clamp_spawn(at)
	sp.heading = face_angle
	_enemies.add_child(sp)
	_lab_spiders.append(sp)
	return sp


func _spawn_lab_spider_near_player(variant_idx: int = 0) -> void:
	if _player == null:
		return
	if _demo_active:
		_stop_demo()
	var dir: Vector2 = _player.facing.normalized() if _player.facing.length_squared() > 0.01 else Vector2.RIGHT
	var spawn_at: Vector2 = _player.global_position + dir * 72.0
	_spawn_lab_spider(spawn_at, variant_idx, ShadowSpider.AmbushKind.NONE, (_player.global_position - spawn_at).angle())


func _clear_lab_spiders() -> void:
	for sp: ShadowSpider in _lab_spiders:
		if is_instance_valid(sp):
			sp.queue_free()
	_lab_spiders.clear()
	if _enemies != null:
		for child: Node in _enemies.get_children():
			if child is MyceliumTether:
				child.queue_free()


func _spawn_spider_ecology_scenario() -> void:
	if _demo_active:
		_stop_demo()
	_clear_lab_spiders()
	# 1. Square 1/2 Meadow-to-Path 2-Spider Flanking Pack (Common + Scout)
	_spawn_lab_spider(Vector2(148.0, -14.0), 0, ShadowSpider.AmbushKind.NONE, PI)
	_spawn_lab_spider(Vector2(168.0, 26.0), 1, ShadowSpider.AmbushKind.NONE, PI)
	# 2. Square 3 Woodland Mirror Puddle Stalker
	_spawn_lab_spider(Vector2(782.0, -36.0), 0, ShadowSpider.AmbushKind.NONE, PI * 0.75)
	# 3. Square 4 Ancient Oak Matriarch Canopy-Drop Ambush
	_spawn_lab_spider(Vector2(1124.0, 74.0), 1, ShadowSpider.AmbushKind.CANOPY_DROP, PI * 0.5)
	# 4. Square 6 Glimmtal-Steinhang Mossy Monolith Crevice-Crouch + Mycelium Tether (Thorn Elder)
	_spawn_lab_spider(Vector2(1432.0, -28.0), 2, ShadowSpider.AmbushKind.MYCELIUM_TETHER, PI * 0.5)


func _run_spider_v2_captures(run_id: int) -> bool:
	var prev_ui: bool = _ui_layer.visible if _ui_layer != null else true
	if _ui_layer != null:
		_ui_layer.visible = false
	_clear_lab_spiders()
	_apply_layer_mode(0)
	_apply_time(0)
	_apply_weather(0)
	_player.health.max_health = 2000.0
	_player.health.current = 2000.0

	# 1. 2x Macro Studio Lineup: All 3 Brood Phenotypes (Scout 0.88x, Common 1.0x, Thorn Elder 1.14x) on Sanctuary Stone & Meadow
	_player.visible = false
	_zoom_macro = true
	_apply_camera_zoom()
	_move_player_for_shot(Vector2(384.0, 6.0))
	var s_scout: ShadowSpider = _spawn_lab_spider(Vector2(342.0, 6.0), 1, ShadowSpider.AmbushKind.NONE, PI * 0.25)
	var s_common: ShadowSpider = _spawn_lab_spider(Vector2(384.0, 8.0), 0, ShadowSpider.AmbushKind.NONE, PI * 0.5)
	var s_thorn: ShadowSpider = _spawn_lab_spider(Vector2(428.0, 6.0), 2, ShadowSpider.AmbushKind.NONE, PI * 0.75)
	for sp_s: ShadowSpider in [s_scout, s_common, s_thorn]:
		if is_instance_valid(sp_s):
			sp_s.set_physics_process(false)
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("01_brood_lineup_stone_noon_2x.png")

	# 2. Golden Hour Long 8-Legged SunShadows on Sanctuary Stonework!
	_apply_time(1)
	_apply_weather(1)
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("02_brood_golden_hour_shadows_2x.png")
	_clear_lab_spiders()

	# 3. Spore-Kinship HESITATE ("Ellie = Shadowspore" curious lavender ocelli & head-tilt) on Blossom Meadow!
	_apply_time(0)
	_apply_weather(0)
	_player.visible = true
	_player.facing = Vector2.RIGHT
	_move_player_for_shot(Vector2(-32.0, 8.0))
	var s_hes: ShadowSpider = _spawn_lab_spider(Vector2(22.0, 8.0), 0, ShadowSpider.AmbushKind.NONE, PI)
	if is_instance_valid(s_hes):
		s_hes.set_physics_process(false)
		s_hes._target = _player
		s_hes._set_state(ShadowSpider.State.HESITATE)
		s_hes._state_time = 0.20
	if not await _wait_sec(run_id, 0.18): return false
	await _save_shot("03_meadow_spore_hesitate_2x.png")

	# 4. Scythe Slash Telegraph & LivingGrass Crescent Blade Sweep!
	if is_instance_valid(s_hes):
		s_hes.attack_origin = s_hes.global_position
		s_hes.attack_dir = Vector2.LEFT
		s_hes.heading = PI
		s_hes._set_state(ShadowSpider.State.WINDUP)
		s_hes._state_time = 0.42
		s_hes._aim_locked = true
		s_hes._bridge.on_scythe_slash(s_hes.global_position, Vector2.LEFT, 40.0)
	if not await _wait_sec(run_id, 0.14): return false
	await _save_shot("04_scythe_telegraph_grass_cut_2x.png")
	_clear_lab_spiders()

	# 5. Night Bioluminescence: Ocelli, Mycelium Veins & Silk Grapple Snare in Glowing Night Meadow!
	_apply_time(3)
	_apply_weather(0)
	_move_player_for_shot(Vector2(-18.0, 6.0))
	_player.facing = Vector2.RIGHT
	var s_night: ShadowSpider = _spawn_lab_spider(Vector2(54.0, 4.0), 2, ShadowSpider.AmbushKind.NONE, PI)
	var s_flank: ShadowSpider = _spawn_lab_spider(Vector2(18.0, -32.0), 1, ShadowSpider.AmbushKind.NONE, PI * 0.65)
	if is_instance_valid(s_night):
		s_night.set_physics_process(false)
		s_night._target = _player
		s_night.attack_origin = s_night.global_position
		s_night.attack_dir = (_player.global_position - s_night.global_position).normalized()
		s_night.anchor = _player.global_position
		s_night._set_state(ShadowSpider.State.GRAPPLE_WINDUP)
		s_night._state_time = 0.52
		s_night._aim_locked = true
	if is_instance_valid(s_flank):
		s_flank.set_physics_process(false)
	_player.effects.apply("webbed", 3.0)
	if not await _wait_sec(run_id, 0.24): return false
	await _save_shot("05_night_pack_grapple_webbed_2x.png")
	_player.effects.clear("webbed")
	_clear_lab_spiders()

	# 6. EXPOSED Cracked Carapace Weakpoint & Woodland Puddle Claw Ripples!
	_apply_time(0)
	_apply_weather(0)
	_move_player_for_shot(Vector2(764.0, -44.0))
	_player.facing = Vector2.RIGHT
	var s_pud: ShadowSpider = _spawn_lab_spider(Vector2(796.0, -46.0), 2, ShadowSpider.AmbushKind.NONE, PI)
	if is_instance_valid(s_pud):
		s_pud.set_physics_process(false)
		s_pud._health.current = s_pud._health.max_health * 0.32
		s_pud._set_state(ShadowSpider.State.EXPOSED)
		s_pud._bridge.on_claw_landed(s_pud.global_position, true)
	if not await _wait_sec(run_id, 0.20): return false
	await _save_shot("06_woodland_puddle_exposed_cracked_2x.png")
	_clear_lab_spiders()

	# 7. Ecological Ambush on Square 6 Glimmtal-Steinhang: Crevice-Crouch + Mycelium Trip-Tether!
	_move_player_for_shot(Vector2(1462.0, -10.0))
	_player.facing = Vector2.LEFT
	var s_amb: ShadowSpider = _spawn_lab_spider(Vector2(1418.0, -34.0), 2, ShadowSpider.AmbushKind.MYCELIUM_TETHER, PI * 0.35)
	if is_instance_valid(s_amb):
		s_amb.set_physics_process(false)
		s_amb.ambush_mode = ShadowSpider.AmbushKind.CREVICE_CROUCH
		s_amb._enter_state()
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("07_rock_crevice_ambush_tether_2x.png")
	_clear_lab_spiders()

	_zoom_macro = false
	_apply_camera_zoom()
	if _ui_layer != null:
		_ui_layer.visible = prev_ui
	return true


func _ensure_sword_selected(sword_id: String = "sword_basic") -> void:
	if _player == null or _player.inventory == null:
		return
	_holding_axe = false
	_holding_pickaxe = false
	_player.inventory.equipment["main_hand"] = {"id": sword_id, "count": 1}
	for i: int in mini(8, _player.inventory.slots.size()):
		var st: Dictionary = _player.inventory.slots[i] as Dictionary
		if st.is_empty() or String(Items.definition(st).get("kind", "")) != "tool":
			_player.inventory.select(i)
			break
	_player.inventory.changed.emit()


func _spawn_finisher_test_spider(as_boss_pack: bool = false, keep_demo: bool = false) -> void:
	if _player == null:
		return
	if _demo_active and not keep_demo:
		_stop_demo()
	_clear_lab_spiders()
	_ensure_sword_selected("sword_basic")
	var dir: Vector2 = _player.facing.normalized() if _player.facing.length_squared() > 0.01 else Vector2.RIGHT
	var target_at: Vector2 = _player.global_position + dir * 20.0
	var sp: ShadowSpider = _spawn_lab_spider(target_at, 2 if as_boss_pack else 0, ShadowSpider.AmbushKind.NONE, (-dir).angle())
	sp._health.current = 1.0
	if as_boss_pack:
		sp.set_meta("finisher_boss_override", true)
		var perp: Vector2 = dir.orthogonal()
		var m1: ShadowSpider = _spawn_lab_spider(target_at + dir * 22.0 + perp * 30.0, 1, ShadowSpider.AmbushKind.NONE, (-dir).angle())
		var m2: ShadowSpider = _spawn_lab_spider(target_at + dir * 22.0 - perp * 30.0, 1, ShadowSpider.AmbushKind.NONE, (-dir).angle())
		m1._target = _player
		m2._target = _player


func _run_finisher_v2_captures(run_id: int) -> bool:
	var prev_ui: bool = _ui_layer.visible if _ui_layer != null else true
	if _ui_layer != null:
		_ui_layer.visible = false
	_clear_lab_spiders()
	_apply_layer_mode(0)
	_apply_time(0)
	_apply_weather(0)
	InputManager.using_mouse = false
	_player.visible = true
	_player.health.max_health = 2000.0
	_player.health.current = 2000.0
	_zoom_macro = true
	_apply_camera_zoom()

	# --- SCENE A (Shots 01..03): Full 3-Beat Live Finisher Sequence on Blossom Meadow (East Facing) ---
	_ensure_sword_selected("sword_basic")
	_player.appearance.set_outfit("default")
	_player.appearance.set_hair("default")
	_move_player_for_shot(Vector2(-36.0, 8.0))
	_player.facing = Vector2.RIGHT
	var sp_meadow: ShadowSpider = _spawn_lab_spider(Vector2(-12.0, 8.0), 0, ShadowSpider.AmbushKind.NONE, PI)
	sp_meadow.set_physics_process(false)
	sp_meadow._health.current = 1.0
	if not await _wait_sec(run_id, 0.12): return false

	# Trigger real sword swing -> lethal hit intercepts into Finisher!
	_player.attack.attack(Vector2.RIGHT)
	# Wait until Beat 1 Plunge (`t_plunge = 0.24 s` + `0.07 s` windup = ~0.31 s)
	var guard_t: float = 0.0
	while (_player.finisher == null or (_player.finisher._beat_mask & 1) == 0) and guard_t < 1.2:
		if not await _wait_sec(run_id, 0.02): return false
		guard_t += 0.02
	if not await _wait_sec(run_id, 0.03): return false
	await _save_shot("01_finisher_beat1_plunge_meadow_2x.png")

	# Wait until Beat 2 Second Deep Press (`_beat_mask & 2`)!
	guard_t = 0.0
	while (_player.finisher != null and _player.finisher.active() and (_player.finisher._beat_mask & 2) == 0) and guard_t < 1.0:
		if not await _wait_sec(run_id, 0.02): return false
		guard_t += 0.02
	if not await _wait_sec(run_id, 0.04): return false
	await _save_shot("02_finisher_beat2_deep_press_meadow_2x.png")

	# Wait until Beat 3 Violent Rip-Out & Loot/Shard Shatter (`_beat_mask & 4`)!
	guard_t = 0.0
	while (_player.finisher != null and _player.finisher.active() and (_player.finisher._beat_mask & 4) == 0) and guard_t < 1.0:
		if not await _wait_sec(run_id, 0.02): return false
		guard_t += 0.02
	if not await _wait_sec(run_id, 0.05): return false
	await _save_shot("03_finisher_beat3_rip_out_burst_meadow_2x.png")

	# Let sequence finish cleanly
	while _player.finisher != null and _player.finisher.active():
		if not await _wait_sec(run_id, 0.04): return false
	if not await _wait_sec(run_id, 0.15): return false
	_clear_lab_spiders()

	# --- SCENE B (Shot 04): SE Diagonal View on Sanctuary Stone Courtyard + Perlenblüte Outfit + Himmelsriss! ---
	var rift_id: String = "sword_rift" if not DataRegistry.get_entry("items", "sword_rift").is_empty() else "sword_basic"
	_ensure_sword_selected(rift_id)
	if _player.appearance.is_valid_outfit("perlenbluete"):
		_player.appearance.set_outfit("perlenbluete")
	_move_player_for_shot(Vector2(316.0, -4.0))
	var se_dir: Vector2 = Vector2(1.0, 1.0).normalized()
	_player.facing = se_dir
	var sp_stone: ShadowSpider = _spawn_lab_spider(Vector2(330.0, 8.0), 2, ShadowSpider.AmbushKind.NONE, (-se_dir).angle())
	sp_stone.set_physics_process(false)
	sp_stone._health.current = 1.0
	if not await _wait_sec(run_id, 0.14): return false
	_player.attack.attack(se_dir)
	guard_t = 0.0
	while (_player.finisher == null or not _player.finisher.active() or (_player.finisher._beat_mask & 1) == 0) and guard_t < 1.2:
		if not await _wait_sec(run_id, 0.02): return false
		guard_t += 0.02
	if not await _wait_sec(run_id, 0.04): return false
	await _save_shot("04_finisher_se_stone_cosmetics_2x.png")
	while _player.finisher != null and _player.finisher.active():
		if not await _wait_sec(run_id, 0.04): return false
	if not await _wait_sec(run_id, 0.15): return false
	_player.appearance.set_outfit("default")
	_ensure_sword_selected("sword_basic")
	_clear_lab_spiders()

	# --- SCENE C (Shot 05): Night Bioluminescence — Beat 2 Second Press Blazing `#ecd2ff` Core & NightLight! ---
	_apply_time(3)
	_apply_weather(0)
	_ensure_sword_selected("sword_basic")
	_move_player_for_shot(Vector2(-16.0, 8.0))
	_player.facing = Vector2.RIGHT
	var sp_night: ShadowSpider = _spawn_lab_spider(Vector2(4.0, 8.0), 2, ShadowSpider.AmbushKind.NONE, PI)
	sp_night.set_physics_process(false)
	sp_night._health.current = 1.0
	if not await _wait_sec(run_id, 0.22): return false
	_player.attack.attack(Vector2.RIGHT)
	guard_t = 0.0
	while (_player.finisher == null or not _player.finisher.active() or (_player.finisher._beat_mask & 2) == 0) and guard_t < 1.4:
		if not await _wait_sec(run_id, 0.02): return false
		guard_t += 0.02
	if not await _wait_sec(run_id, 0.04): return false
	await _save_shot("05_finisher_night_deep_press_glow_2x.png")
	while _player.finisher != null and _player.finisher.active():
		if not await _wait_sec(run_id, 0.04): return false
	if not await _wait_sec(run_id, 0.15): return false
	_clear_lab_spiders()

	# --- SCENE D (Shot 06): Boss Override Rule — Executing Boss Spider Push-Scattering 2 Minions! ---
	_apply_time(0)
	_apply_weather(0)
	_move_player_for_shot(Vector2(692.0, 16.0))
	_player.facing = Vector2.RIGHT
	_spawn_finisher_test_spider(true, true)
	if not await _wait_sec(run_id, 0.14): return false
	_player.attack.attack(Vector2.RIGHT)
	guard_t = 0.0
	while (_player.finisher == null or not _player.finisher.active() or (_player.finisher._beat_mask & 2) == 0) and guard_t < 1.4:
		if not await _wait_sec(run_id, 0.02): return false
		guard_t += 0.02
	if not await _wait_sec(run_id, 0.03): return false
	await _save_shot("06_finisher_boss_override_minions_recoil_2x.png")
	while _player.finisher != null and _player.finisher.active():
		if not await _wait_sec(run_id, 0.04): return false
	_clear_lab_spiders()

	_zoom_macro = false
	_apply_camera_zoom()
	if _ui_layer != null:
		_ui_layer.visible = prev_ui
	return true


# ---------------- SANCTUARY RUINS 2.0 & LIVING FLORA 2.0 (28 SPECIES) ----------------

func _build_sanctuary_flora() -> void:
	_flora_field = LivingFloraField.new()
	_flora_field.name = "LivingFloraField"
	add_child(_flora_field)
	_flora_field.populate_sanctuary_ecosystem(_surfaces)
	_metrics["sanctuary_ruins_placed"] = _flora_field.ruins.size() >= 8
	_metrics["sanctuary_flora_28"] = _flora_field.species_placed.size() >= 28 and _flora_field.plants.size() >= 95


func _select_tool_item(item_id: String) -> void:
	if _player == null or _player.inventory == null:
		return
	for i: int in mini(8, _player.inventory.slots.size()):
		var st: Dictionary = _player.inventory.slots[i] as Dictionary
		if not st.is_empty() and String(st.get("id", "")) == item_id:
			_player.inventory.select(i)
			return


func _run_flora_v2_captures(run_id: int) -> bool:
	var prev_ui: bool = _ui_layer.visible if _ui_layer != null else true
	if _ui_layer != null:
		_ui_layer.visible = false
	_apply_layer_mode(0)
	_apply_time(0)
	_apply_weather(1) ## Gentle breeze so WorldWind sways wildflowers, bees orbit, and petals drift!
	_zoom_macro = false
	_apply_camera_zoom()

	# 1. Full 1x Noon Overview of Square 2: Ancient Stones 2.0, Standing Ruins, 4 Paths & All Flora Layers!
	_player.visible = true
	_player.facing = Vector2.RIGHT
	_move_player_for_shot(Vector2(384.0, 0.0))
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("01_sq2_sanctuary_flora_overview.png")

	# 2. 2x Macro: Sanctuary Crossroads 2.0 (chisel marks, gold inlays, tilted runic stele, Sentinel Mullein, Thyme, Saxifrage & Crevice Weeds!)
	_zoom_macro = true
	_apply_camera_zoom()
	_player.visible = true
	_player.facing = Vector2.DOWN
	_move_player_for_shot(Vector2(364.0, 2.0))
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("02_macro_crossroads_stones_weeds_2x.png")

	# 3. 2x Macro (Morning Dew `t = 0.27`): NW Shrine Parapet, Star-Dew-Filled Basin, Dew-Pearl Lady's Mantle, Periwinkle & Blooming Wild Rose!
	_player.visible = false
	_apply_time(2) ## Morning / Dew (`0.27`) -> fills `ancient_dew_basin` & `star_mantle` pearls!
	_move_player_for_shot(Vector2(226.0, -86.0))
	if not await _wait_sec(run_id, 0.45): return false
	await _save_shot("03_macro_shrine_parapet_dew_basin_2x.png")

	# 4. 2x Macro: West Country Way Wildflowers (`silver_yarrow`, morning-open `way_chicory`, `waybread`, `dew_campion` & `meadow_clock` puffballs!)
	_apply_time(0)
	_move_player_for_shot(Vector2(204.0, 6.0))
	if _flora_field != null:
		_flora_field.spawn_dandelion_seeds(Vector2(196.0, 20.0), 8)
	if not await _wait_sec(run_id, 0.28): return false
	await _save_shot("04_macro_west_roadside_wildflowers_2x.png")

	# 5. 2x Macro: NE Ruin Spur & East Cart Track (`elderberry_shrub` in bloom & berry, `fallen_column_drum` with ivy, `bramble_thicket`, `wild_teasel` & `shadow_angelica`!)
	_move_player_for_shot(Vector2(506.0, -56.0))
	if _flora_field != null:
		_flora_field.spawn_petals(Vector2(462.0, -118.0), 6, Color("f4f2fa"))
	if not await _wait_sec(run_id, 0.28): return false
	await _save_shot("05_macro_east_ruins_elder_bramble_2x.png")

	# 6. 2x Macro: South Stepping-Stone Garden & Damp Woodland Edge (`wild_rose_briar` with ruby rosehips, `meadowsweet`, `ostrich_fern`, `shadow_arum` & `wood_sorrel`!)
	_move_player_for_shot(Vector2(476.0, 70.0))
	if not await _wait_sec(run_id, 0.25): return false
	await _save_shot("06_macro_south_stepping_woodland_edge_2x.png")

	# 7. 1x Golden Hour across Square 2: Warm Gold Inlay Catchlights & Real-Time Swaying `SunShadows`!
	_zoom_macro = false
	_apply_camera_zoom()
	_player.visible = true
	_player.facing = Vector2.UP
	_apply_time(1)
	_apply_weather(1)
	_move_player_for_shot(Vector2(384.0, 0.0))
	if not await _wait_sec(run_id, 0.35): return false
	await _save_shot("07_sq2_golden_hour_sun_shadows.png")

	# 8. 1x Night Bioluminescence & Nyctinasty: Glowing Mullein Torches, Turquoise Saxifrage, Violet Columbine, Folded Sorrel & Runic Waymarkers!
	_apply_time(3)
	_apply_weather(0)
	if not await _wait_sec(run_id, 0.45): return false
	await _save_shot("08_sq2_night_mystic_glow.png")

	# 9. 2x Live Body-Parting & Dandelion Puff Interaction: Ellie striding through tall herbs & puffing a `meadow_clock`!
	_apply_time(0)
	_apply_weather(1)
	_zoom_macro = true
	_apply_camera_zoom()
	_player.visible = true
	_move_player_for_shot(Vector2(544.0, 88.0))
	_player.facing = Vector2.RIGHT
	if _flora_field != null:
		_flora_field.spawn_dandelion_seeds(Vector2(536.0, 74.0), 12)
		_flora_field.spawn_petals(Vector2(558.0, 70.0), 6, Color("f4f2fa"))
	if not await _hold(run_id, [&"move_right"], 0.22): return false
	await _save_shot("09_interactive_walk_parting_and_puff_2x.png")

	# 10. 2x Live Sickle Harvest & Dew-Scoop Interaction: Sickle cutting `nettle_clump` -> `nettle_fiber` ItemDrop + realistic green stubble!
	_apply_time(2)
	_select_tool_item("sickle_basic")
	_move_player_for_shot(Vector2(218.0, -96.0))
	_player.facing = Vector2.UP
	if _flora_field != null:
		for fp: LivingFloraProp in _flora_field.plants:
			if is_instance_valid(fp) and fp.species_id == "nettle_clump" and fp.position.distance_to(Vector2(238.0, -118.0)) < 12.0:
				fp.cut_with_sickle(_player.global_position)
				fp.cut_with_sickle(_player.global_position)
				break
		for r: SanctuaryRuin in _flora_field.ruins:
			if is_instance_valid(r) and r.ruin_kind == "ancient_dew_basin" and r.position.distance_to(Vector2(182.0, -94.0)) < 12.0:
				r._rpc_scoop_dew(1)
				break
	if not await _wait_sec(run_id, 0.22): return false
	await _save_shot("10_interactive_sickle_and_dew_harvest_2x.png")

	_zoom_macro = false
	_apply_camera_zoom()
	if _ui_layer != null:
		_ui_layer.visible = prev_ui
	return true
