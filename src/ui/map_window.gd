class_name MapWindow
extends Control
## The world map (M). The whole land is drawn per pixel by assets/shaders/world_map.gdshader from the
## baked world data; what nobody has seen yet lies under shadow smoke (`MapDiscovery`, shared by all
## players; new cells fade in here). The wheel zooms towards the cursor, dragging (or WASD / the left
## stick) pans with a little glide, Q/E zoom too, Space flies back to the heroine, right click sets
## or removes a waymark (four kinds, picked on the vine on the left). The path she walked is a
## dotted trail, the named areas reveal themselves once enough of them is explored. Vines frame the map like
## the inventory does and the void creeps into them at night.

const SHADER: Shader = preload("res://assets/shaders/world_map.gdshader")
const OPEN_SECONDS: float = 0.9
const CLOSE_SECONDS: float = 0.3
const SCALE_MIN: float = 0.28 ## screen pixels per tile
const SCALE_MAX: float = 5.0
const SCALE_START: float = 0.9
const WHEEL_STEP: float = 1.28
const PAN_SPEED: float = 300.0 ## screen pixels per second
const FOG_FADE: float = 1.3 ## seconds a newly seen cell takes to clear
const TRAIL_STEP: float = 6.0 ## tiles between two dots
const TRAIL_MAX: int = 900
const LABEL_CELLS: int = 150 ## seen cells of an area before the map names it
const MAX_PINS: int = 40
const ZOOM_X: float = 618.0
const ZOOM_TOP: float = 100.0
const ZOOM_BOTTOM: float = 326.0
const PIN_BRANCH_Y: float = 100.0
const LIST_BRANCH_Y: float = 206.0
const PIN_KINDS: Array[Dictionary] = [
	{"name": "WEGZEICHEN", "color": Color("b9f3ee"), "rows": ["..X..", ".X.X.", "X...X", ".X.X.", "..X.."]},
	{"name": "GEFAHR", "color": Color("ff5f8a"), "rows": ["..X..", "..X..", "..X..", ".....", "..X.."]},
	{"name": "ZIEL", "color": Color("ffd98a"), "rows": ["X...X", ".X.X.", "..X..", ".X.X.", "X...X"]},
	{"name": "LAGER", "color": Color("a6e68f"), "rows": ["..X..", ".XXX.", "XXXXX", "X...X", "X...X"]},
]
const PLAYER_TONES: Array[Color] = [Color("b9f3ee"), Color("ffd98a"), Color("ff7fd8"), Color("a6e68f")]
const BOSS_MAGENTA: Color = Color("f35cf3") ## the second ghost of Mornath's hologram marker (like `MornathHologram.MAGENTA`)
## Mornath's marker: the hologram's bird, 11 x 7, two wing beats (up, down).
const BOSS_WINGS: Array = [
	["X.........X", "XX...X...XX", ".XX.XXX.XX.", ".XXXXXXXXX.", "..XXXXXXX..", "....XXX....", ".....X....."],
	[".....X.....", "....XXX....", ".XXXXXXXXX.", "XXXXXXXXXXX", "XX.XXXXX.XX", "X...XXX...X", ".....X....."],
]

var _player: Node2D
var _discovery: MapDiscovery
var _canvas: ColorRect
var _overlay: Control
var _material: ShaderMaterial = ShaderMaterial.new()
var _vignette: GradientTexture2D
var _fog_image: Image
var _fog_texture: ImageTexture
var _fading: Dictionary = {} ## cell index -> 0..1 while it clears
var _loaded: bool = false

var _area_ids: Array[int] = []
var _area_names: Array[String] = []
var _area_colors: Array[Color] = []
var _cell_area: PackedByteArray = PackedByteArray() ## per cell: named area index, 255 = no land
var _land_total: PackedInt32Array = PackedInt32Array()
var _seen_by_area: PackedInt32Array = PackedInt32Array()
var _sum_by_area: PackedVector2Array = PackedVector2Array()
var _start_tile: Vector2 = Vector2(-1, -1)

var _open_t: float = 0.0
var _opening: bool = false
var _time: float = 0.0
var _center: Vector2 = Vector2(550, 550) ## tile in the middle of the view
var _scale: float = SCALE_START
var _scale_target: float = SCALE_START
var _anchor: Vector2 = Vector2(320, 180) ## screen point the zoom keeps still
var _velocity: Vector2 = Vector2.ZERO ## tiles per second, the glide after a drag
var _dragging: bool = false
var _since_motion: float = 0.0
var _slider_drag: bool = false
var _fly: bool = false
var _cursor: Vector2 = Vector2(-100, -100)
var _trail: PackedVector2Array = PackedVector2Array()
var _pins: Array[Dictionary] = []
var _pin_kind: int = 0
var _player_slots: Dictionary = {} ## peer id -> stable colour/number while connected
var _marker_spots: Array[Vector2] = []
var _marker_labels: Array[Rect2] = []
var _water_image: Image
var _lake_image: Image
var _hover_marker: Dictionary = {}
var _hover_id: String = ""
var _hover_t: float = 0.0
signal travel_chosen(from_id: String, to_id: String) ## travel mode: the player held on another waystone
signal travel_cancelled ## travel mode: the map was closed without choosing

var _ways: MapWaystones = MapWaystones.new()
var _pet_marks: MapPets = MapPets.new() ## the named crows and ravens (docs/pet_konzept.md)
var _ws_mouse: bool = false ## the left button is held on a waystone (travel mode)
var _present_left: float = 0.0 ## `present`: seconds the map stays open on its own (a waystone woke up)
var _present_age: float = 0.0
var _present_ring: float = 0.0 ## tiles: the radius of the ring that runs out of the statue
var _present_tile: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("map_window")
	visible = false
	z_index = 30 ## above the HUD vines (clock, hotbar, purse), like the skill window
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette = VineStyle.make_vignette()
	_canvas = ColorRect.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.material = _material
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## `player` is untyped on purpose (the player scene preloads the HUD).
func bind(player: Node) -> void:
	_player = player as Node2D


# ---------- data ----------

func _load_data() -> void:
	_discovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if _discovery == null:
		return
	_loaded = true
	var biomes: Dictionary = DataRegistry.table("biomes")
	var palette: PackedVector3Array = PackedVector3Array()
	for id: String in biomes:
		var entry: Dictionary = biomes[id]
		var base: Color = Color(entry.color as String)
		for tone: Color in [base.lerp(Color(0.04, 0.025, 0.09), 0.78), base.lerp(Color(0.14, 0.1, 0.26), 0.58), base.lerp(Color(0.9, 0.86, 1.0), 0.22)]:
			palette.append(Vector3(tone.r, tone.g, tone.b))
	_material.shader = SHADER
	_material.set_shader_parameter("pal", palette)
	_material.set_shader_parameter("relief", Relief.TEXTURE)
	_material.set_shader_parameter("field", Relief.FIELD)
	_material.set_shader_parameter("sdf", load("res://assets/world/outer_sdf.png"))
	_material.set_shader_parameter("paths", _path_texture())
	var water: Texture2D = load("res://assets/world/map_water.png") as Texture2D
	_material.set_shader_parameter("water", water)
	_water_image = water.get_image()
	_lake_image = (load("res://assets/world/lakes_sdf.png") as Texture2D).get_image()
	_material.set_shader_parameter("lake_shore", load("res://assets/world/lakes_sdf.png"))
	_material.set_shader_parameter("world_tiles", float(RegionMap.WORLD_TILES))
	var map: RegionMap = RegionMap.new(0, DataRegistry.table("world_map"))
	var area_biomes: PackedInt32Array = PackedInt32Array()
	for area: Dictionary in map.supers:
		var biome: String = RegionMap.active_biome(String(area.biome))
		_area_ids.append(int(area.id))
		_area_names.append(map.area_name(int(area.id)))
		_area_colors.append(Color(String((biomes[biome] as Dictionary).color)))
		area_biomes.append(maxi(biomes.keys().find(biome), 0))
	_material.set_shader_parameter("area_biomes", area_biomes)
	_start_tile = Vector2(map.start if map.start.x >= 0 else map.anchor(map.start_region))
	var image: Image = Relief.TEXTURE.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = image.get_data()
	var side: int = image.get_width()
	var grid: int = MapDiscovery.GRID
	var areas: Image = Image.create(grid, grid, false, Image.FORMAT_R8)
	_cell_area.resize(grid * grid)
	_land_total.resize(map.supers.size())
	for cy: int in grid:
		for cx: int in grid:
			var alpha: int = data[(((cy * RegionMap.CELL + 2) * side) + cx * RegionMap.CELL + 2) * 4 + 3]
			var tile: Vector2i = Vector2i(cx, cy) * RegionMap.CELL + Vector2i(2, 2)
			var area: int = map.super_at(tile)
			areas.set_pixel(cx, cy, Color((area + 1) / 255.0, 0, 0))
			var land_area: int = _area_near(map, tile) if alpha >= 200 else 255
			_cell_area[cy * grid + cx] = land_area
			if land_area < _land_total.size():
				_land_total[land_area] += 1
	_material.set_shader_parameter("areas", ImageTexture.create_from_image(areas))
	_rebuild_fog()
	_discovery.revealed.connect(_on_revealed)
	_discovery.replaced.connect(_rebuild_fog)


func _area_near(map: RegionMap, tile: Vector2i) -> int:
	var area: int = map.super_at(tile)
	if area >= 0:
		return area
	for radius: int in [4, 8, 12]:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			area = map.super_at(tile + direction * radius)
			if area >= 0:
				return area
	return 0


## The fog texture and the counts from the whole table (first open, snapshot, loaded save).
func _rebuild_fog() -> void:
	var grid: int = MapDiscovery.GRID
	var seen: PackedByteArray = _discovery.bytes()
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(grid * grid)
	_seen_by_area.resize(_land_total.size())
	_seen_by_area.fill(0)
	_sum_by_area.resize(_land_total.size())
	_sum_by_area.fill(Vector2.ZERO)
	for i: int in pixels.size():
		if seen[i] != 0:
			pixels[i] = 255
			_count_cell(i)
	_fading.clear()
	_fog_image = Image.create_from_data(grid, grid, false, Image.FORMAT_R8, pixels)
	if _fog_texture == null:
		_fog_texture = ImageTexture.create_from_image(_fog_image)
		_material.set_shader_parameter("fog", _fog_texture)
	else:
		_fog_texture.update(_fog_image)


func _count_cell(index: int) -> void:
	var area: int = _cell_area[index]
	if area < _seen_by_area.size():
		_seen_by_area[area] += 1
		_sum_by_area[area] += Vector2(index % MapDiscovery.GRID, index / MapDiscovery.GRID)


func _on_revealed(cells: PackedInt32Array) -> void:
	var grid: int = MapDiscovery.GRID
	for index: int in cells:
		_count_cell(index)
		if visible:
			_fading[index] = 0.0
		else:
			_fog_image.set_pixel(index % grid, index / grid, Color.WHITE)
	if not visible:
		_fog_texture.update(_fog_image)


func _advance_fog(delta: float) -> void:
	if _fading.is_empty():
		return
	var grid: int = MapDiscovery.GRID
	var done: Array[int] = []
	for index: int in _fading:
		var t: float = minf(float(_fading[index]) + delta / FOG_FADE, 1.0)
		_fading[index] = t
		_fog_image.set_pixel(index % grid, index / grid, Color(t * t * (3.0 - 2.0 * t), 0, 0))
		if t >= 1.0:
			done.append(index)
	for index: int in done:
		_fading.erase(index)
	_fog_texture.update(_fog_image)


# ---------- state ----------

func _process(delta: float) -> void:
	_record_trail()
	if InputManager.map_pressed():
		if _opening:
			_set_open(false)
		elif not InputManager.ui_blocking:
			_set_open(true)
	if _present_left > 0.0 and _opening:
		_present_left -= delta
		_present_age += delta
		if _present_left <= 0.0:
			_set_open(false)
	_open_t = move_toward(_open_t, 1.0 if _opening else 0.0, delta / (OPEN_SECONDS if _opening else CLOSE_SECONDS))
	visible = _open_t > 0.0
	if not visible:
		return
	_time = fmod(_time + delta, 20000.0)
	_hover_t = move_toward(_hover_t, 0.0 if _hover_id.is_empty() else 1.0, delta / (0.12 if _hover_id.is_empty() else 0.18))
	if _hover_t <= 0.0 and _hover_id.is_empty():
		_hover_marker.clear()
	_pet_marks.update(get_tree(), _cursor, _to_screen)
	var pick: String = _ways.update(delta, get_tree(), _cursor, _to_screen, _ws_mouse, InputManager.interact_held() and _opening, InputManager.map_select_step() if _opening else 0)
	if pick != "":
		var from_id: String = _ways.travel_from
		_ways.travel_from = ""
		_set_open(false)
		travel_chosen.emit(from_id, pick)
	_advance_fog(delta)
	_navigate(delta)
	_push_uniforms()
	queue_redraw()
	_overlay.queue_redraw()


## Opens the map on its own, centred on `tile`, and closes it again after `seconds` (or when the player does): the waystone scene shows what its light revealed.
## `ring_tiles` > 0 runs a ring of light out of the tile to that radius, as the fog clears.
## Travel mode (at an awakened waystone): the map opens showing every awakened statue, the others highlighted; holding the mouse (or E) on one chooses it
## (`travel_chosen`), Esc / M closes without (`travel_cancelled`). Returns false when the map cannot open.
func open_travel(from_id: String) -> bool:
	if _opening:
		return false
	_ways.travel_from = from_id
	_set_open(true)
	if not _opening:
		_ways.travel_from = ""
		return false
	var tiles: Array[Vector2] = []
	var manager: Waystones = Waystones.of(get_tree())
	for entry: Dictionary in manager.entries():
		if bool(entry.awake):
			var tile: Array = entry.tile as Array
			tiles.append(Vector2(float(tile[0]), float(tile[1])))
	var lo: Vector2 = tiles[0]
	var hi: Vector2 = tiles[0]
	for t: Vector2 in tiles:
		lo = Vector2(minf(lo.x, t.x), minf(lo.y, t.y))
		hi = Vector2(maxf(hi.x, t.x), maxf(hi.y, t.y))
	_center = (lo + hi) / 2.0
	_scale = 0.4
	_scale_target = clampf(minf(size.x * 0.55 / maxf(hi.x - lo.x, 40.0), size.y * 0.5 / maxf(hi.y - lo.y, 40.0)), SCALE_MIN, 1.4)
	return true


func present(tile: Vector2, seconds: float, ring_tiles: float = 0.0) -> void:
	if _opening:
		return
	_set_open(true)
	if not _opening:
		return
	_center = tile
	_scale = 0.7
	_scale_target = clampf(1.3, SCALE_MIN, SCALE_MAX)
	_present_left = seconds
	_present_age = 0.0
	_present_ring = ring_tiles
	_present_tile = tile


func _set_open(open: bool) -> void:
	_present_left = 0.0
	_present_ring = 0.0
	_ws_mouse = false
	if not open and _ways.travel_from != "":
		_ways.travel_from = ""
		travel_cancelled.emit()
	if open and not _loaded:
		_load_data()
		if not _loaded:
			return
	_opening = open
	_hover_id = ""
	_hover_t = 0.0
	_hover_marker.clear()
	InputManager.map_open = open
	InputManager.ui_blocking = open
	if open:
		_center = _player_tile()
		_scale = _scale_target * 0.8
		_anchor = size / 2.0
		_velocity = Vector2.ZERO
		_fly = false
		_cursor = size / 2.0
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		_dragging = false
		_slider_drag = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if _opening and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _player_tile() -> Vector2:
	return Interiors.outer(get_tree(), _player.global_position) / 16.0 if _player != null else _center


## Read the same baked surface masks as the world, including future paths. Four by four
## samples per tile retain narrow bends without loading a world-sized ground image.
func _path_texture() -> ImageTexture:
	var image: Image = Image.create(RegionMap.WORLD_TILES, RegionMap.WORLD_TILES, false, Image.FORMAT_R8)
	image.fill(Color.BLACK)
	for spec: Dictionary in DataRegistry.table("ground_baked").get("decals", []) as Array:
		var mask: Image = (load(String(spec.mask)) as Texture2D).get_image()
		var origin: Vector2i = Vector2i(int(spec.x), int(spec.y))
		var first: Vector2i = Vector2i(floori(origin.x / 16.0), floori(origin.y / 16.0))
		var last: Vector2i = Vector2i(ceili((origin.x + mask.get_width()) / 16.0), ceili((origin.y + mask.get_height()) / 16.0))
		for y: int in range(maxi(first.y, 0), mini(last.y, RegionMap.WORLD_TILES)):
			for x: int in range(maxi(first.x, 0), mini(last.x, RegionMap.WORLD_TILES)):
				var covered: int = 0
				for sy: int in 4:
					for sx: int in 4:
						var at: Vector2i = Vector2i(x * 16 + sx * 4 + 2, y * 16 + sy * 4 + 2) - origin
						if at.x >= 0 and at.y >= 0 and at.x < mask.get_width() and at.y < mask.get_height() and mask.get_pixelv(at).r8 == 80:
							covered += 1
				var coverage: float = maxf(image.get_pixel(x, y).r, covered / 16.0)
				image.set_pixel(x, y, Color(coverage, 0, 0))
	return ImageTexture.create_from_image(image)


func _record_trail() -> void:
	if _player == null:
		return
	var here: Vector2 = _player_tile()
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(here) > TRAIL_STEP:
		_trail.append(here)
		if _trail.size() > TRAIL_MAX:
			_trail = _trail.slice(100)


func _navigate(delta: float) -> void:
	if _opening:
		var pan: Vector2 = InputManager.map_pan_vector()
		if pan != Vector2.ZERO:
			_center += pan * PAN_SPEED * delta / _scale
			_velocity = Vector2.ZERO
			_fly = false
		var zoom: int = InputManager.map_zoom_step()
		if zoom != 0:
			_zoom_by(float(zoom), size / 2.0)
		if InputManager.map_center_pressed():
			_fly = true
			_scale_target = clampf(maxf(_scale_target, SCALE_START), SCALE_MIN, SCALE_MAX)
			_anchor = size / 2.0
	if _fly:
		_center = _center.lerp(_player_tile(), 1.0 - exp(-7.0 * delta))
	elif not _dragging and _velocity.length() > 0.01:
		_center += _velocity * delta
		_velocity *= exp(-5.0 * delta)
	_since_motion += delta
	var before: float = _scale
	_scale *= pow(_scale_target / _scale, 1.0 - exp(-12.0 * delta))
	if absf(_scale - _scale_target) < 0.0005 * _scale:
		_scale = _scale_target
	_center += (_anchor - size / 2.0) * (1.0 / before - 1.0 / _scale)
	_center = _center.clamp(Vector2.ZERO, Vector2.ONE * RegionMap.WORLD_TILES)


func _zoom_by(steps: float, at: Vector2) -> void:
	_scale_target = clampf(_scale_target * pow(WHEEL_STEP, steps), SCALE_MIN, SCALE_MAX)
	_anchor = at
	_fly = false


func _push_uniforms() -> void:
	_material.set_shader_parameter("view_size", size)
	_material.set_shader_parameter("center", _center)
	_material.set_shader_parameter("map_scale", _scale)
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_material.set_shader_parameter("open", _open_t * _open_t * (3.0 - 2.0 * _open_t))
	_material.set_shader_parameter("focus", _to_screen(_player_tile()).clamp(Vector2.ZERO, size))


func _to_screen(tile: Vector2) -> Vector2:
	return ((tile - _center) * _scale + size / 2.0).round()


func _tile_at(screen: Vector2) -> Vector2:
	return _center + (screen - size / 2.0) / _scale


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_cursor = motion.position
		if _slider_drag:
			_set_zoom_from(motion.position.y)
		elif _dragging:
			_center -= motion.relative / _scale
			_velocity = (-motion.relative / _scale) * 60.0 * 0.5 + _velocity * 0.5
			_since_motion = 0.0
			_fly = false
		return
	if button == null:
		return
	_cursor = button.position
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				_zoom_by(1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0, button.position)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				_press(button)
			else:
				_ws_mouse = false
				_dragging = false
				_slider_drag = false
				if _since_motion > 0.08:
					_velocity = Vector2.ZERO
		MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_toggle_pin(button.position)


func _press(button: InputEventMouseButton) -> void:
	if button.button_index == MOUSE_BUTTON_LEFT:
		if _ways.can_press():
			_ws_mouse = true ## the hold on a waystone (travel mode)
			return
		if absf(button.position.x - ZOOM_X) < 12.0 and button.position.y > ZOOM_TOP - 10.0 and button.position.y < ZOOM_BOTTOM + 10.0:
			_slider_drag = true
			_set_zoom_from(button.position.y)
			return
		for k: int in PIN_KINDS.size():
			if button.position.distance_to(_pin_slot(k)) < 11.0:
				_pin_kind = k
				return
		if button.double_click:
			_zoom_by(2.0, button.position)
			return
	_dragging = true
	_velocity = Vector2.ZERO
	_fly = false


func _set_zoom_from(y: float) -> void:
	var u: float = clampf((ZOOM_BOTTOM - y) / (ZOOM_BOTTOM - ZOOM_TOP), 0.0, 1.0)
	_scale_target = exp(lerpf(log(SCALE_MIN), log(SCALE_MAX), u))
	_anchor = size / 2.0
	_fly = false


func _toggle_pin(at: Vector2) -> void:
	for i: int in _pins.size():
		if _to_screen(_pins[i].pos as Vector2).distance_to(at) < 8.0:
			_pins.remove_at(i)
			return
	if _pins.size() < MAX_PINS:
		_pins.append({"pos": _tile_at(at), "kind": _pin_kind, "born": _time})


func _pin_slot(kind: int) -> Vector2:
	return Vector2(26.0 + kind * 26.0, PIN_BRANCH_Y + 24.0 + sin(_time * 1.1 + kind * 1.7) * 1.2)


# ---------- drawing ----------

func _draw() -> void:
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, _open_t))


func _fade() -> float:
	return clampf((_open_t - 0.4) / 0.5, 0.0, 1.0)


func _draw_overlay() -> void:
	var fade: float = _fade()
	var void_level: float = VineStyle.void_amount()
	_draw_trail(fade)
	_draw_labels(fade)
	_draw_start(fade)
	_draw_town(fade)
	_ways.draw(_overlay, _scale, fade, _time, size, [_present_tile, _present_ring, _present_age] if _present_ring > 0.0 else [])
	_pet_marks.draw(_overlay, _scale, fade, _time, size, get_tree())
	_draw_quest(fade)
	_draw_pins(fade)
	_draw_presence(fade)
	_draw_frame(fade, void_level)


func _text(text: String, pos: Vector2i, color: Color, fade: float) -> void:
	PixelText.draw(_overlay, text, pos, Color(color, color.a * fade), Color(VineStyle.OUTLINE, 0.9 * fade))


func _text_centered(text: String, at: Vector2, color: Color, fade: float) -> void:
	_text(text, Vector2i(roundi(at.x) - PixelText.width(text) / 2, roundi(at.y)), color, fade)


func _on_screen(at: Vector2, margin: float = 12.0) -> bool:
	return at.x > -margin and at.y > -margin and at.x < size.x + margin and at.y < size.y + margin


func _draw_trail(fade: float) -> void:
	var step: int = maxi(ceili(3.0 / (TRAIL_STEP * _scale)), 1) ## thin out when zoomed far out
	var count: int = _trail.size()
	for i: int in range(count - 1, -1, -step):
		var at: Vector2 = _to_screen(_trail[i])
		if not _on_screen(at, 2.0):
			continue
		var recent: float = 1.0 - float(count - 1 - i) / TRAIL_MAX
		_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.VOID_GLOW.lerp(PLAYER_TONES[0], recent), (0.18 + 0.5 * recent) * fade))


func _draw_labels(fade: float) -> void:
	var visibility: float = clampf((1.5 - _scale) / 0.5, 0.0, 1.0) * fade
	if visibility <= 0.0:
		return
	for b: int in _area_ids.size():
		if _seen_by_area[b] < LABEL_CELLS:
			continue
		var at: Vector2 = _to_screen((_sum_by_area[b] / _seen_by_area[b] + Vector2(0.5, 0.5)) * RegionMap.CELL)
		if not _on_screen(at, 80.0):
			continue
		var label: String = _area_names[b]
		var tone: Color = Color(VineStyle.PETAL).lerp(_area_colors[b], 0.35)
		_overlay.draw_set_transform(Vector2(roundf(at.x) - PixelText.width(label), roundf(at.y) - 14.0), 0.0, Vector2(2, 2))
		PixelText.draw(_overlay, label, Vector2i.ZERO, Color(tone, 0.92 * visibility), Color(VineStyle.OUTLINE, 0.9 * visibility))
		_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text_centered("%d%%" % roundi(100.0 * _seen_by_area[b] / maxi(_land_total[b], 1)), at + Vector2(0, 3), Color(VineStyle.LEAF_VOID_LIGHT, 0.8), visibility)


func _draw_start(fade: float) -> void:
	if _start_tile.x < 0.0 or not _discovery.is_seen(_start_tile):
		return
	var at: Vector2 = _to_screen(_start_tile)
	if not _on_screen(at):
		return
	VineStyle.glow(_overlay, at, 9.0, VineStyle.WARM_GLOW, 0.5 * fade * (0.8 + 0.2 * sin(_time * 2.0)))
	for offset: Vector2 in [Vector2(0, -3), Vector2(-3, 0), Vector2(3, 0), Vector2(0, 3)]:
		_overlay.draw_rect(Rect2(at + offset, Vector2.ONE), Color(VineStyle.WARM_GLOW, fade))
	_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, fade))
	if _scale > 0.6:
		_text_centered("START", at + Vector2(0, 6), Color(VineStyle.WARM_GLOW, 0.9), fade)


const TOWN_TEAL: Color = Color("78f4e6")
const TOWN_GLYPHS: Dictionary = {
	"lamp_post": [".....", "..X..", ".XXX.", "..X..", "..X.."],
	"stockpile": ["XXXXX", "X...X", "XXXXX", "X...X", "XXXXX"],
	"workshop": ["..X..", ".XXX.", "XXXXX", "X.X.X", "XXXXX"],
	"bench": [".....", ".....", "XXXXX", "X...X", "....."],
	"banner_post": ["XXX..", "XXX..", "X....", "X....", "X...."],
}
const TOWN_FLAG: Array = ["XX...", "XXX..", "XXXX.", "X....", "X...."]


## The town on the map (docs/town_ausbau.md C19): a flag at the hut with the town's name, the rings of the light (what burns bright, what only carries the town's building ground
## faint), and from zoom 0.9 a small sign for every lamp post, store, workshop, bench and banner post (an empty or cold lamp pale).
func _draw_town(fade: float) -> void:
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
	if town == null or not town.founded:
		return
	var lit: Array[Vector3] = town.lit_circles()
	for pass_index: int in 2:
		for c: Vector3 in town.circles() if pass_index == 0 else lit:
			var around: Vector2 = _to_screen(Vector2(c.x, c.y) / 16.0)
			var radius: float = c.z / 16.0 * _scale
			if radius < 3.0 or around.x + radius < 0.0 or around.y + radius < 0.0 or around.x - radius > size.x or around.y - radius > size.y:
				continue
			var tone: Color = Color(TOWN_TEAL, (0.16 if pass_index == 0 else 0.55) * fade)
			VineStyle.ring(_overlay, around, int(radius), tone, 0.6 if pass_index == 1 else 0.3)
	var at: Vector2 = _to_screen(town.center / 16.0)
	if _on_screen(at):
		_glyph(TOWN_FLAG, at + Vector2(0, -3), TOWN_TEAL, fade)
		_overlay.draw_rect(Rect2(at + Vector2(-2, -5), Vector2(1, 8)), Color(VineStyle.BARK_LIGHT, fade))
		if _scale > 0.3:
			_text_centered(town.town_name(), at + Vector2(0, 9), Color(VineStyle.WARM_GLOW, 0.95), fade)
	if _scale < 0.9:
		return
	for id: int in town.structures:
		var data: Dictionary = town.structures[id] as Dictionary
		var rows: Variant = TOWN_GLYPHS.get(String(data.p))
		if rows == null or not town.is_built(id):
			continue
		var spot: Vector2 = _to_screen(Vector2(float(data.x), float(data.y) - 6.0) / 16.0)
		if not _on_screen(spot):
			continue
		var color: Color = VineStyle.PETAL
		if String(data.p) == "lamp_post":
			color = VineStyle.WARM_GLOW if town.is_lamp_burning(id) else Color("8a7f96")
		_glyph(rows as Array, spot, color, fade)


## The goal of the current quest: a golden bloom with rings that open outwards, a stem and its name; off screen a chevron at the edge points to it.
func _draw_quest(fade: float) -> void:
	var quests: QuestComponent = (_player.get("quests") as QuestComponent) if _player != null else null
	if quests == null:
		return
	var now: Dictionary = quests.current()
	if now.is_empty() or (now.target as Vector2) == Vector2.INF or (now.target as Vector2).x >= Interiors.POCKET_X0:
		return
	var at: Vector2 = _to_screen((now.target as Vector2) / 16.0)
	if float(now.get("search", 0.0)) > 0.0:
		_draw_search(at, float(now.search) * _scale, fade)
	if not _on_screen(at, 4.0):
		_draw_pointer(at, VineStyle.WARM_GLOW, fade)
		return
	var tone: Color = VineStyle.WARM_GLOW
	var wave: float = fposmod(_time * 0.7, 1.0)
	VineStyle.glow(_overlay, at, 14.0, tone, 0.5 * fade * (0.8 + 0.2 * sin(_time * 3.0)))
	VineStyle.ring(_overlay, at, 4 + int(wave * 11.0), Color(tone, (1.0 - wave) * 0.85 * fade), 0.7)
	VineStyle.ring(_overlay, at, 4 + int(fposmod(wave + 0.5, 1.0) * 11.0), Color(tone, (1.0 - fposmod(wave + 0.5, 1.0)) * 0.5 * fade), 0.5)
	for pass_index: int in 2: ## a four-petal bloom
		for offset: Vector2 in [Vector2(0, -3), Vector2(-3, 0), Vector2(3, 0), Vector2(0, 3), Vector2(0, -2), Vector2(-2, 0), Vector2(2, 0), Vector2(0, 2)]:
			if pass_index == 0:
				for edge: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					_overlay.draw_rect(Rect2(at + offset + edge, Vector2.ONE), Color(VineStyle.OUTLINE, 0.9 * fade))
			else:
				_overlay.draw_rect(Rect2(at + offset, Vector2.ONE), Color(tone, fade))
	_overlay.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 3)), Color(VineStyle.PETAL, fade))
	if _scale > 0.4:
		_text_centered(String(now.title), at + Vector2(0, 9), Color(tone, 0.95), fade)


## The search area of a quest step (the goal is somewhere inside, nobody knows where): a ragged ring of marching dashes in the warm gold of the quest bloom,
## a second thin ring inside that breathes, runes ticking outwards every 15 degrees, a gold dust that drifts in the circle and a soft glow along the edge.
func _draw_search(at: Vector2, radius: float, fade: float) -> void:
	if radius < 6.0:
		return
	var tone: Color = VineStyle.WARM_GLOW
	var steps: int = clampi(int(radius * 7.0), 48, 2600)
	var march: int = int(_time * 9.0)
	for pass_index: int in 2:
		var r_base: float = radius if pass_index == 0 else radius * 0.94
		for s: int in steps:
			var angle: float = s * TAU / steps
			if pass_index == 0 and (s + march) % 9 > 5:
				continue
			if pass_index == 1 and (s + 3 * march) % 5 != 0:
				continue
			var ragged: float = sin(angle * 7.0 + _time * 0.8) * 1.3 + sin(angle * 17.0 - _time * 1.7) * 0.7 + VineStyle.rand(s % 997) * 0.8
			var p: Vector2 = (at + Vector2(cos(angle), sin(angle)) * (r_base + ragged)).round()
			if not _on_screen(p, 2.0):
				continue
			if pass_index == 0:
				_overlay.draw_rect(Rect2(p + Vector2(1, 1), Vector2.ONE), Color(VineStyle.OUTLINE, 0.7 * fade))
				_overlay.draw_rect(Rect2(p, Vector2.ONE), Color(tone, 0.95 * fade))
			else:
				_overlay.draw_rect(Rect2(p, Vector2.ONE), Color(tone, (0.35 + 0.2 * sin(_time * 2.0 + angle * 3.0)) * fade))
	for k: int in 24: ## runes: short ticks pointing outwards, every second one longer
		var angle: float = k * TAU / 24.0 + _time * 0.03
		var length: int = 5 if k % 2 == 0 else 3
		for t: int in length:
			var p: Vector2 = (at + Vector2(cos(angle), sin(angle)) * (radius + 4.0 + t)).round()
			if _on_screen(p, 2.0):
				_overlay.draw_rect(Rect2(p, Vector2.ONE), Color(tone, (0.9 - t * 0.12) * fade * (0.7 + 0.3 * sin(_time * 1.6 + k))))
	for k: int in 36: ## glints of gold dust drifting inside the circle, each on its own slow orbit
		var orbit: float = sqrt(VineStyle.rand(k * 3 + 11)) * radius * 0.9
		var angle: float = VineStyle.rand(k * 5 + 2) * TAU + _time * (0.05 + 0.08 * VineStyle.rand(k))
		var p: Vector2 = (at + Vector2(cos(angle), sin(angle)) * orbit).round()
		var twinkle: float = 0.5 + 0.5 * sin(_time * 2.4 + k * 1.7)
		if _on_screen(p, 2.0) and twinkle > 0.35:
			_overlay.draw_rect(Rect2(p, Vector2.ONE), Color(VineStyle.PETAL, 0.7 * twinkle * fade))
	for k: int in 8: ## a glow at the eight points of the compass
		var angle: float = k * TAU / 8.0
		var p: Vector2 = at + Vector2(cos(angle), sin(angle)) * radius
		if _on_screen(p, 20.0):
			VineStyle.glow(_overlay, p, 10.0, tone, 0.22 * fade * (0.8 + 0.2 * sin(_time * 2.2 + k)))
	if _scale > 0.3 and _on_screen(at + Vector2(0, -radius), 20.0):
		_text_centered("SUCHGEBIET", at + Vector2(0, -radius - 12.0), Color(tone, 0.9), fade)


func _glyph(rows: Array, at: Vector2, color: Color, fade: float) -> void:
	var origin: Vector2 = (at - Vector2(2, 2)).round()
	for pass_index: int in 2:
		for y: int in 5:
			for x: int in 5:
				if String(rows[y])[x] != "X":
					continue
				if pass_index == 0:
					for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
						_overlay.draw_rect(Rect2(origin + Vector2(x, y) + offset, Vector2.ONE), Color(VineStyle.OUTLINE, 0.9 * fade))
				else:
					_overlay.draw_rect(Rect2(origin + Vector2(x, y), Vector2.ONE), Color(color, fade))


func _draw_pins(fade: float) -> void:
	for pin: Dictionary in _pins:
		var kind: Dictionary = PIN_KINDS[int(pin.kind)]
		var at: Vector2 = _to_screen(pin.pos as Vector2)
		if not _on_screen(at):
			continue
		var age: float = _time - float(pin.born)
		var drop: float = (1.0 - VineStyle.back_out(clampf(age / 0.35, 0.0, 1.0))) * -10.0 ## planted with a bounce
		var color: Color = kind.color
		VineStyle.glow(_overlay, at + Vector2(0, drop - 4.0), 8.0, color, 0.35 * fade * (0.8 + 0.2 * sin(_time * 2.5 + at.x)))
		_overlay.draw_rect(Rect2(at + Vector2(0, -2), Vector2(1, 3)), Color(VineStyle.OUTLINE, fade)) ## the stake
		_glyph(kind.rows as Array, at + Vector2(0, drop - 6.0), color, fade)
		if _cursor.distance_to(at) < 8.0 and _opening: ## right click removes it
			VineStyle.ring(_overlay, at + Vector2(0, -5), 7, Color(color, 0.8 * fade), 0.6)


func _player_tones() -> Dictionary:
	var ids: Array[int] = []
	for player: Player in Player.all:
		ids.append(player.name.to_int())
	ids.sort()
	for id: int in _player_slots.keys():
		if not ids.has(id):
			_player_slots.erase(id)
	for id: int in ids:
		if _player_slots.has(id):
			continue
		for slot: int in PLAYER_TONES.size():
			if not _player_slots.values().has(slot):
				_player_slots[id] = slot
				break
	var out: Dictionary = {}
	for id: int in ids:
		out[id] = PLAYER_TONES[int(_player_slots.get(id, 0))]
	return out


## Read existing replicated players and resident actors every frame. No second position cache,
## no map-only RPCs: arriving/leaving peers and moving/reparented NPCs follow their real state.
func _live_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var styles: Dictionary = DataRegistry.table("map_markers")
	var quests: QuestComponent = (_player.get("quests") as QuestComponent) if _player is Player else null
	for actor: Node in get_tree().get_nodes_in_group("quest_actors"):
		if not actor.has_method("map_marker"):
			continue
		var marker: Dictionary = actor.call("map_marker") as Dictionary
		if marker.is_empty():
			continue
		var style: Dictionary = styles.get(String(marker.id), styles.get("resident", {})) as Dictionary
		var requires: String = String(style.get("requires", ""))
		if not requires.is_empty() and (quests == null or not quests.has_flag(requires)):
			continue
		var world: Vector2 = marker.position as Vector2
		var tile: Vector2 = Interiors.outer(get_tree(), world) / 16.0
		if not _world_tile(tile) or _discovery == null or not _discovery.is_seen(tile):
			continue
		marker["tile"] = tile
		marker["kind"] = String(style.get("kind", "npc")) ## "npc" or "boss" (Mornath's hologram: own look and card)
		marker["extra"] = String(style.get("extra", ""))
		marker["name"] = String(style.get("name", marker.get("name", marker.id)))
		marker["title"] = String(style.get("title", marker.get("title", "BEWOHNER")))
		marker["tone"] = Color(String(style.get("color", "a6ceae")))
		marker["rows"] = style.get("rows", (styles.get("resident", {}) as Dictionary).get("rows", []))
		marker["frames"] = style.get("frames", BOSS_WINGS) ## a boss hologram's figure: two 11 x 7 frames (Mornath's bird by default)
		marker["ghost"] = Color(String(style.get("ghost", "f35cf3")))
		marker["inside"] = Interiors.slot_at(world) >= 0 or MineManager.in_mine(world)
		markers.append(marker)
	var tones: Dictionary = _player_tones()
	for other: Player in Player.all:
		var tile: Vector2 = Interiors.outer(get_tree(), other.global_position) / 16.0
		if not _world_tile(tile):
			continue
		var id: int = other.name.to_int()
		markers.append({"id": str(id), "kind": "self" if other == _player else "player", "tile": tile,
			"name": "DU" if other == _player else "SPIELER %d" % (int(_player_slots.get(id, 0)) + 1),
			"title": "", "tone": tones[id], "position": other.global_position,
			"inside": Interiors.slot_at(other.global_position) >= 0 or MineManager.in_mine(other.global_position)})
	return markers


func _world_tile(tile: Vector2) -> bool:
	return tile.is_finite() and tile.x >= 0.0 and tile.y >= 0.0 and tile.x < RegionMap.WORLD_TILES and tile.y < RegionMap.WORLD_TILES


## Keep exact anchors but fan out crowded icons with a fine tether. Fixed screen sizes at all zooms.
func _place_marker(anchor: Vector2) -> Vector2:
	for ring: int in 5:
		for k: int in (1 if ring == 0 else 8):
			var offset: Vector2 = Vector2.ZERO if ring == 0 else Vector2.from_angle(k * TAU / 8.0) * ring * 15.0
			var at: Vector2 = (anchor + offset).round()
			if not _on_screen(at, -10.0):
				continue
			var clear: bool = true
			for used: Vector2 in _marker_spots:
				if at.distance_to(used) < 14.0:
					clear = false
					break
			if clear:
				_marker_spots.append(at)
				return at
	_marker_spots.append(anchor)
	return anchor


func _draw_presence(fade: float) -> void:
	_marker_spots.clear()
	_marker_labels.clear()
	var hovered: Dictionary = {}
	var nearest: float = 11.0
	var boss_seen: bool = false
	for marker: Dictionary in _live_markers():
		var anchor: Vector2 = _to_screen(marker.tile as Vector2)
		var tone: Color = marker.tone
		var kind: String = String(marker.kind)
		if not _on_screen(anchor, -12.0):
			if kind != "npc":
				_draw_pointer(anchor, tone, fade * (1.0 if kind == "self" else 0.65))
			continue
		var at: Vector2 = _place_marker(anchor)
		if at.distance_to(anchor) > 2.0:
			_overlay.draw_line(anchor, at, Color(VineStyle.OUTLINE, 0.8 * fade), 3.0)
			_overlay.draw_line(anchor, at, Color(tone, 0.55 * fade))
			_overlay.draw_rect(Rect2(anchor, Vector2.ONE), Color(tone, fade))
		if kind == "npc":
			var strength: float = 0.6 if bool(marker.get("resting", false)) else 1.0
			VineStyle.glow(_overlay, at, 9.0, tone, 0.27 * fade * strength)
			VineStyle.ring(_overlay, at, 6, Color(tone, 0.55 * fade * strength), 0.7)
			_glyph(marker.rows as Array, at, tone, fade * strength)
			if bool(marker.get("resting", false)):
				_text("Z", Vector2i(at + Vector2(5, -8)), tone, fade * 0.7)
		elif kind == "boss":
			_draw_boss_marker(at, tone, fade, marker.frames as Array, marker.ghost as Color)
			boss_seen = true
		elif kind == "self":
			_draw_hero(at, tone, 1.0, fade)
		else:
			VineStyle.glow(_overlay, at, 9.0, tone, 0.28 * fade)
			_glyph(["..X..", ".X.X.", "X.X.X", ".X.X.", "..X.."], at, tone, fade)
		if bool(marker.get("inside", false)):
			_glyph([".XXX.", ".X.X.", ".X.X.", ".X.X.", ".XXX."], at + Vector2(7, 5), tone, fade * 0.8)
		if kind == "boss":
			if _scale > 0.3:
				_presence_label(String(marker.name), at + Vector2(0, 3), tone.lerp(VineStyle.PETAL, 0.2), fade)
		elif _scale >= 2.0:
			_presence_label(String(marker.name), at, tone, fade * 0.85)
		var distance: float = _cursor.distance_to(at)
		if distance < nearest and not _dragging and not _slider_drag:
			nearest = distance
			hovered = marker.duplicate()
			hovered["screen"] = at
	_set_presence_hover(hovered)
	if not _hover_marker.is_empty() and _hover_t > 0.0:
		_draw_presence_tooltip(_hover_marker, fade)
	_draw_presence_legend(fade, boss_seen)


## Mornath's hologram on the map: the bird of the arena's projection (wings beating, scanlines, now and then a tear with a magenta ghost) over a ring of broken
## runes, a cone of calling rings pulsing out, glitch specks rising. Fixed screen size at every zoom, like the other marks.
func _draw_boss_marker(at: Vector2, tone: Color, fade: float, frames: Array = BOSS_WINGS, ghost: Color = BOSS_MAGENTA) -> void:
	var phase: float = 0.5 + 0.5 * sin(_time * 2.4)
	var glitch: float = _boss_glitch()
	VineStyle.glow(_overlay, at, 17.0 + 3.0 * phase, tone, 0.34 * fade)
	VineStyle.glow(_overlay, at + Vector2(0, 3), 10.0, ghost, (0.1 + 0.22 * glitch) * fade)
	for k: int in 2: # the call: two rings widening out of the bird
		var t: float = fposmod(_time * 0.45 + k * 0.5, 1.0)
		VineStyle.ring(_overlay, at, 9 + int(t * 22.0), Color(tone, (1.0 - t) * 0.55 * fade), 0.6)
	for ring: int in 2: # the floor sigil: broken arcs turning against each other
		var radius: float = 10.0 + 6.0 * ring
		var turn: float = _time * (0.5 if ring == 0 else -0.35)
		var steps: int = 40 + ring * 16
		for i: int in steps:
			if (i * 5 + ring * 3) % 7 < 2 or (glitch > 0.3 and (i + int(_time * 14.0)) % 3 == 0):
				continue
			var a: float = turn + TAU * float(i) / float(steps)
			var p: Vector2 = at + Vector2(0, 4) + Vector2(roundf(cos(a) * radius), roundf(sin(a) * radius * 0.5))
			_overlay.draw_rect(Rect2(p, Vector2.ONE), Color(tone if ring == 0 else ghost, (0.75 - 0.2 * ring) * fade))
	_draw_boss_bird(at + Vector2(0, roundf(sin(_time * 1.3) * 1.5) - 3.0), tone, fade, glitch, frames, ghost)
	for k: int in 3: # glitch specks rising
		var t: float = fposmod(_time * 0.55 + k * 0.33, 1.0)
		var speck: Vector2 = at + Vector2(roundf(sin(k * 5.1 + _time * 0.3) * 9.0), -6.0 - roundf(t * 16.0))
		_overlay.draw_rect(Rect2(speck, Vector2(2, 1) if k == 1 else Vector2.ONE), Color(ghost if k == 2 else tone, (1.0 - t) * 0.8 * fade))


## 0..1: a short tear of the hologram, every few seconds (two uneven rhythms).
func _boss_glitch() -> float:
	var a: float = clampf(1.0 - fposmod(_time, 3.3) / 0.25, 0.0, 1.0)
	var b: float = clampf(1.0 - fposmod(_time * 1.3 + 1.1, 5.7) / 0.18, 0.0, 1.0)
	return maxf(a, b)


## The bird (11 x 7, `at` = its middle) as a hologram: every second row dimmer, a bright core, and in a tear rows slip sideways over a magenta ghost.
func _draw_boss_bird(at: Vector2, tone: Color, fade: float, glitch: float, frames: Array = BOSS_WINGS, ghost: Color = BOSS_MAGENTA) -> void:
	var rows: Array = frames[int(_time * 2.2) % frames.size()] as Array
	var origin: Vector2 = (at - Vector2(5, 3)).round()
	var slip: Array[int] = []
	for y: int in 7:
		slip.append(((1 if (y + int(_time * 17.0)) % 2 == 0 else -2) if glitch > 0.0 and (y + int(_time * 30.0)) % 3 == 0 else 0))
	for pass_index: int in 3:
		for y: int in 7:
			var row: String = String(rows[y])
			for x: int in 11:
				if row[x] != "X":
					continue
				var cell: Vector2 = origin + Vector2(x + slip[y], y)
				if pass_index == 0:
					for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
						_overlay.draw_rect(Rect2(cell + offset, Vector2.ONE), Color(VineStyle.OUTLINE, 0.9 * fade))
				elif pass_index == 1:
					if glitch > 0.0:
						_overlay.draw_rect(Rect2(cell + Vector2(2, 0), Vector2.ONE), Color(ghost, 0.6 * glitch * fade))
				else:
					var color: Color = tone.lerp(VineStyle.PETAL, clampf(0.55 - float(x + y) * 0.04, 0.05, 0.55))
					if y % 2 == 1:
						color = color.darkened(0.2)
					if x == 5 and y == 3:
						color = VineStyle.PETAL
					_overlay.draw_rect(Rect2(cell, Vector2.ONE), Color(color, fade))


func _presence_label(label: String, at: Vector2, tone: Color, fade: float) -> void:
	var rect: Rect2 = Rect2(at + Vector2(-PixelText.width(label) / 2.0 - 2, 9), Vector2(PixelText.width(label) + 4, 9))
	for used: Rect2 in _marker_labels:
		if rect.intersects(used):
			return
	for used: Vector2 in _marker_spots:
		if rect.grow(5.0).has_point(used):
			return
	_marker_labels.append(rect)
	_text_centered(label, at + Vector2(0, 10), tone, fade)


func _set_presence_hover(marker: Dictionary) -> void:
	var id: String = "" if marker.is_empty() else "%s:%s" % [String(marker.kind), String(marker.id)]
	if id != _hover_id:
		if not id.is_empty():
			_hover_t = 0.0
		_hover_id = id
	if not marker.is_empty():
		_hover_marker = marker


func _presence_status(marker: Dictionary) -> String:
	if bool(marker.get("resting", false)):
		return "RUHT ZU HAUSE"
	if bool(marker.get("inside", false)):
		return "IN DER MINE" if MineManager.in_mine(marker.get("position", Vector2.ZERO) as Vector2) else "IM GEBAEUDE"
	var tile: Vector2 = marker.tile as Vector2
	if String(marker.kind) == "self":
		return "X %d   Y %d" % [roundi(tile.x), roundi(tile.y)]
	var distance: int = roundi(_player_tile().distance_to(tile))
	return "BEI DIR" if distance <= 2 else "%d M ENTFERNT" % distance


func _presence_role(marker: Dictionary) -> String:
	match String(marker.kind):
		"self": return "DEIN STANDORT"
		"player": return "MITSPIELER"
	return String(marker.get("title", "BEWOHNER"))


## An extra line under the status (only Mornath's card has one: "ERNEUTER KAMPF BEREIT").
func _presence_extra(marker: Dictionary) -> String:
	return String(marker.get("extra", ""))


func _presence_card_rect(marker: Dictionary) -> Rect2:
	var extra: String = _presence_extra(marker)
	var width: float = maxf(116.0, maxf(PixelText.width(String(marker.name)) * 2.0, PixelText.width(_presence_role(marker))) + 53.0)
	width = maxf(width, PixelText.width(_presence_status(marker)) + 25.0)
	if not extra.is_empty():
		width = maxf(width, PixelText.width(extra) + 25.0)
	var height: float = 57.0 + (12.0 if not extra.is_empty() else 0.0)
	var anchor: Vector2 = marker.screen as Vector2
	var at: Vector2 = anchor + Vector2(18, -68)
	if at.x + width > size.x - 14.0:
		at.x = anchor.x - width - 18.0
	if at.y < 50.0:
		at.y = anchor.y + 15.0
	at = at.clamp(Vector2(14, 50), size - Vector2(width + 14, 71.0 + height)).round()
	return Rect2(at, Vector2(width, height))


## A small living bark sign: the same paper and leaves as the inventory, with a personal seal.
func _draw_presence_tooltip(marker: Dictionary, fade: float) -> void:
	var ease: float = 1.0 - pow(1.0 - _hover_t, 3.0)
	var alpha: float = fade * ease
	var tone: Color = marker.tone
	var void_level: float = VineStyle.void_amount()
	var salt: int = absi(String(marker.id).hash()) % 997
	var box: Rect2 = _presence_card_rect(marker)
	box.position.y += roundf((1.0 - ease) * 5.0)
	var anchor: Vector2 = marker.screen as Vector2
	var attach: Vector2 = anchor.clamp(box.position + Vector2(7, 5), box.end - Vector2(7, 5)).round()
	var tip: Vector2 = anchor + (attach - anchor).normalized() * 7.0
	_overlay.draw_line(tip, tip.lerp(attach, ease).round(), Color(VineStyle.OUTLINE, 0.85 * alpha), 3.0)
	_overlay.draw_line(tip, tip.lerp(attach, ease).round(), Color(tone, 0.45 * alpha))
	VineStyle.paper(_overlay, Rect2(box.position + Vector2(2, 3), box.size), alpha * 0.35, 1.0, salt)
	VineStyle.paper(_overlay, box, alpha, void_level, salt)
	var at: Vector2 = box.position
	# Fine grain and a little of the marker's colour caught in the upper bark edge.
	var boss: bool = String(marker.kind) == "boss"
	for x: int in range(7, int(box.size.x) - 7):
		if (x + salt) % 5 != 0:
			_overlay.draw_rect(Rect2(at + Vector2(x, 4), Vector2.ONE), Color(BOSS_MAGENTA if boss and x % 11 == 0 else tone, (0.3 if boss and x % 11 == 0 else 0.17) * alpha))
	var emblem: Vector2 = at + Vector2(21, 23)
	VineStyle.glow(_overlay, emblem, 17.0, tone, 0.32 * alpha)
	_overlay.draw_circle(emblem + Vector2(0, 1), 12.0, Color(VineStyle.OUTLINE, alpha))
	_overlay.draw_circle(emblem, 10.0, Color(VineStyle.BARK.lerp(tone, 0.15).darkened(0.45), alpha))
	VineStyle.ring(_overlay, emblem, 11, Color(VineStyle.BARK_LIGHT.lerp(tone, 0.4), alpha), 0.75)
	VineStyle.ring(_overlay, emblem, 8, Color(tone, 0.38 * alpha), 0.7)
	var rows: Array = marker.get("rows", ["..X..", ".XXX.", "XXXXX", ".XXX.", "..X.."]) as Array
	if String(marker.kind) == "player":
		rows = ["..X..", ".X.X.", "X.X.X", ".X.X.", "..X.."]
	if boss:
		_draw_boss_bird(emblem + Vector2(0, -1), tone, alpha, _boss_glitch())
	else:
		_overlay.draw_set_transform(emblem, 0.0, Vector2(2, 2))
		_glyph(rows, Vector2.ZERO, tone.lerp(VineStyle.PETAL, 0.18), alpha)
		_overlay.draw_set_transform(Vector2.ZERO)
	_overlay.draw_set_transform(at + Vector2(40, 9), 0.0, Vector2(2, 2))
	PixelText.draw(_overlay, String(marker.name), Vector2i.ZERO, Color(tone.lerp(VineStyle.PETAL, 0.28), alpha), Color(VineStyle.OUTLINE, alpha))
	_overlay.draw_set_transform(Vector2.ZERO)
	_text(_presence_role(marker), Vector2i(at + Vector2(41, 26)), Color(UiStyle.TEXT_DIM.lerp(tone, 0.25), 0.95), alpha)
	for x: int in range(11, int(box.size.x) - 11):
		_overlay.draw_rect(Rect2(at + Vector2(x, 38), Vector2.ONE), Color(VineStyle.BARK_LIGHT.lerp(tone, 0.25), (0.4 if x % 3 == 0 else 0.18) * alpha))
	_overlay.draw_rect(Rect2(at + Vector2(12, 46), Vector2(2, 2)), Color(tone, 0.8 * alpha))
	_text(_presence_status(marker), Vector2i(at + Vector2(20, 43)), Color(UiStyle.TEXT, 0.85), alpha)
	var extra: String = _presence_extra(marker)
	if not extra.is_empty():
		_overlay.draw_rect(Rect2(at + Vector2(12, 58), Vector2(2, 2)), Color(BOSS_MAGENTA, 0.85 * alpha))
		_text(extra, Vector2i(at + Vector2(20, 55)), Color(BOSS_MAGENTA.lerp(UiStyle.TEXT, 0.35), 0.95), alpha)
	_presence_card_vine(at + Vector2(-2, 3), 1, 35, tone, alpha, ease)
	_presence_card_vine(at + Vector2(box.size.x + 1, box.size.y - 3), -1, 29, tone, alpha, ease)
	VineStyle.leaf(_overlay, emblem + Vector2(-11, 5), -1, -1, 3, Color(VineStyle.LEAF, alpha), Color(tone, 0.7 * alpha))
	VineStyle.leaf(_overlay, emblem + Vector2(11, 5), 1, -1, 3, Color(VineStyle.LEAF, alpha), Color(tone, 0.7 * alpha))


func _presence_card_vine(origin: Vector2, direction: int, length: int, tone: Color, fade: float, reach: float) -> void:
	for i: int in roundi(length * reach):
		var p: Vector2 = (origin + Vector2(i * direction, sin(i * 0.16) * 1.5)).round()
		_overlay.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Color(VineStyle.OUTLINE, fade))
		_overlay.draw_rect(Rect2(p, Vector2.ONE), Color(VineStyle.BARK_LIGHT.lerp(tone, 0.2), 0.9 * fade))
		if i > 4 and i % 9 == 0:
			VineStyle.leaf(_overlay, p, direction, -1, 3, Color(VineStyle.LEAF, fade), Color(VineStyle.LEAF_LIGHT.lerp(tone, 0.35), fade))


func _draw_presence_legend(fade: float, boss: bool = false) -> void:
	var y: float = size.y - 37.0
	var x: float = size.x / 2.0 - (134.0 if boss else 112.0)
	var mine: int = int(_player_slots.get(_player.name.to_int(), 0)) if _player != null else 0
	_glyph(["..X..", ".XXX.", "XXXXX", ".XXX.", "..X.."], Vector2(x, y + 2), PLAYER_TONES[mine], fade * 0.8)
	_text("DU", Vector2i(x + 9, y), UiStyle.TEXT_DIM, fade * 0.8)
	_glyph(["..X..", ".X.X.", "X.X.X", ".X.X.", "..X.."], Vector2(x + 44, y + 2), PLAYER_TONES[1], fade * 0.8)
	_text("MITSPIELER", Vector2i(x + 53, y), UiStyle.TEXT_DIM, fade * 0.8)
	_glyph(["XXXXX", "X.X.X", "X.X.X", ".XXX.", "..X.."], Vector2(x + 132, y + 2), Color("c8b8ed"), fade * 0.8)
	_text("BEWOHNER", Vector2i(x + 141, y), UiStyle.TEXT_DIM, fade * 0.8)
	if boss:
		_glyph(["X...X", "XX.XX", ".XXX.", "..X..", "..X.."], Vector2(x + 184, y + 2), Color("6fe8ff"), fade * 0.8)
		_text("MORNATH", Vector2i(x + 193, y), UiStyle.TEXT_DIM, fade * 0.8)


## A diamond with a pulsing ring: where somebody stands.
func _draw_hero(at: Vector2, tone: Color, strength: float, fade: float) -> void:
	if not _on_screen(at):
		return
	var pulse: float = fposmod(_time * 0.8 + at.x * 0.01, 1.0)
	VineStyle.glow(_overlay, at, 11.0 * strength, tone, 0.55 * fade)
	VineStyle.ring(_overlay, at, 3 + int(pulse * 8.0 * strength), Color(tone, (1.0 - pulse) * 0.8 * fade), 0.7)
	for pass_index: int in 2:
		for dy: int in range(-4, 5):
			var half: int = (4 if pass_index == 0 else 3) - absi(dy)
			if half < 0 or (pass_index == 1 and absi(dy) > 3):
				continue
			var row: Rect2 = Rect2(at.x - half, at.y + dy, half * 2 + 1, 1)
			_overlay.draw_rect(row, Color(VineStyle.OUTLINE, fade) if pass_index == 0 else Color(tone.lerp(VineStyle.PETAL, 0.4), fade))
	_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, fade))


## A chevron on the screen edge pointing at somebody off screen.
func _draw_pointer(target: Vector2, tone: Color, fade: float) -> void:
	var middle: Vector2 = size / 2.0
	var dir: Vector2 = (target - middle).normalized()
	var half: Vector2 = middle - Vector2(30, 30)
	var k: float = minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at: Vector2 = (middle + dir * k).round()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var bob: float = sin(_time * 4.0) * 1.5
	var tip: Vector2 = at + dir * (6.0 + bob)
	_overlay.draw_colored_polygon(PackedVector2Array([tip + dir * 2.0, at + side * 6.0 - dir * 4.0, at - side * 6.0 - dir * 4.0]), Color(VineStyle.OUTLINE, fade))
	_overlay.draw_colored_polygon(PackedVector2Array([tip, at + side * 4.0 - dir * 3.0, at - side * 4.0 - dir * 3.0]), Color(tone, fade))


func _draw_frame(fade: float, void_level: float) -> void:
	var taken_at: Callable = func(x: float) -> float: return VineStyle.infection(maxf(x, size.x - x) * 0.6, void_level, int(x / 5.0))
	var plate: float = clampf((_open_t - 0.45) / 0.4, 0.0, 1.0)
	VineStyle.tag(_overlay, "KARTE", Vector2(size.x / 2.0, 0), plate, float(taken_at.call(size.x / 2.0)), _time)
	_draw_readout(fade)
	_draw_pin_vine(fade, void_level)
	_draw_list(fade, void_level)
	_draw_zoom_vine(fade, void_level)
	_draw_compass(fade)
	if _ways.travel_from != "":
		var hint: String = "WEGSTEIN WAEHLEN: MAUS ODER A D   HALTEN: REISEN   ESC: ABBRECHEN" if not _ways.destinations().is_empty() else "KEIN ANDERER WEGSTEIN ERWACHT   ESC: ABBRECHEN"
		_text_centered(hint, Vector2(size.x / 2.0, 299.0), Color(Color("9ff5ec"), 0.8), fade)
	else:
		_text_centered("ZIEHEN: SCHIEBEN   RAD: ZOOM   RECHTSKLICK: ZEICHEN   LEERTASTE: ZU MIR   M: SCHLIESSEN", Vector2(size.x / 2.0, 299.0), Color(UiStyle.TEXT_DIM, 0.6), fade)


func _draw_readout(fade: float) -> void:
	var tile: Vector2 = _tile_at(_cursor)
	var inside: bool = tile.x >= 0.0 and tile.y >= 0.0 and tile.x < RegionMap.WORLD_TILES and tile.y < RegionMap.WORLD_TILES
	var place: String = "UNBEKANNT"
	var tone: Color = Color(UiStyle.TEXT_DIM, 0.9)
	if inside and _discovery.is_seen(tile):
		var area: int = _cell_area[(int(tile.y) / RegionMap.CELL) * MapDiscovery.GRID + int(tile.x) / RegionMap.CELL]
		place = _area_names[area].to_upper() if area < _area_names.size() else "DIE LEERE"
		tone = Color(UiStyle.TEXT, 0.95)
		if _water_image != null and _water_image.get_pixelv(Vector2i(tile)).r > 0.25:
			place = "SEE" if _lake_image.get_pixelv(Vector2i(tile)).r < 0.5 else "FLUSS"
			tone = Color("8fc9c6")
	_text_centered("X %d   Y %d" % [roundi(tile.x), roundi(tile.y)] if inside else "JENSEITS", Vector2(size.x / 2.0, 26.0), Color(UiStyle.TEXT_DIM, 0.8), fade)
	_text_centered(place, Vector2(size.x / 2.0, 35.0), tone, fade)


func _draw_pin_vine(fade: float, void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.35) / 0.45, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return PIN_BRANCH_Y + 4.0 * sin(x / 128.0 * PI) + sin(x * 0.08) * 1.2
	VineStyle.branch(_overlay, 0.0, 128.0, course, 5, void_level, 40.0, _time, reach)
	VineStyle.foliage(_overlay, 0.0, 128.0, course, 8, 410, void_level, 40.0, _time, reach)
	for k: int in PIN_KINDS.size():
		var p: float = clampf((reach - 0.3 - k * 0.1) / 0.4, 0.0, 1.0)
		if p <= 0.0:
			continue
		var kind: Dictionary = PIN_KINDS[k]
		var slot: Vector2 = _pin_slot(k)
		slot.y = PIN_BRANCH_Y + 6.0 + (slot.y - PIN_BRANCH_Y - 6.0) * VineStyle.back_out(p)
		var anchor: Vector2 = Vector2(slot.x, float(course.call(slot.x)))
		for y: int in range(int(anchor.y) + 1, int(slot.y) - 9):
			_overlay.draw_rect(Rect2(slot.x, y, 1, 1), Color(VineStyle.BARK_LIGHT if y % 2 == 0 else VineStyle.BARK, p))
		var chosen: bool = k == _pin_kind
		var tone: Color = kind.color
		VineStyle.glow(_overlay, slot, 13.0 if chosen else 9.0, tone, (0.55 if chosen else 0.18) * p * fade)
		VineStyle.ring(_overlay, slot, 8, Color(tone, (0.95 if chosen else 0.4) * p * fade), 1.0 if chosen else 0.5)
		_glyph(kind.rows as Array, slot, tone, p * fade * (1.0 if chosen else 0.7))
	_text(String(PIN_KINDS[_pin_kind].name), Vector2i(12, int(PIN_BRANCH_Y) + 40), Color(PIN_KINDS[_pin_kind].color, 0.9), fade)


func _draw_list(fade: float, void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.5) / 0.4, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return LIST_BRANCH_Y + 3.0 * sin(x / 110.0 * PI) + sin(x * 0.07 + 2.0) * 1.1
	VineStyle.branch(_overlay, 0.0, 110.0, course, 4, void_level, 50.0, _time, reach)
	VineStyle.foliage(_overlay, 0.0, 110.0, course, 6, 470, void_level, 50.0, _time, reach)
	var total_land: int = 0
	var total_seen: int = 0
	for b: int in _land_total.size():
		total_land += _land_total[b]
		total_seen += _seen_by_area[b]
	_text("ERKUNDET %d%%" % roundi(100.0 * total_seen / maxi(total_land, 1)), Vector2i(10, int(LIST_BRANCH_Y) + 7), Color(UiStyle.TEXT, 0.95), fade * reach)
	for b: int in _area_ids.size():
		var p: float = clampf((reach - 0.4 - b * 0.08) / 0.4, 0.0, 1.0)
		var y: int = int(LIST_BRANCH_Y) + 20 + b * 11
		var known: bool = _seen_by_area[b] > 0
		var tone: Color = _area_colors[b] if known else Color(VineStyle.BARK_LIGHT)
		if known:
			VineStyle.glow(_overlay, Vector2(14, y + 3), 6.0, tone, 0.4 * p * fade)
		for dy: int in range(-2, 3):
			_overlay.draw_rect(Rect2(14 - (2 - absi(dy)), y + 3 + dy, (2 - absi(dy)) * 2 + 1, 1), Color(tone, p * fade) if known or absi(dy) == 2 or dy == 0 else Color(VineStyle.OUTLINE, p * fade))
		var line: String = "%s %d%%" % [_area_names[b], roundi(100.0 * _seen_by_area[b] / maxi(_land_total[b], 1))] if known else "???"
		_text(line, Vector2i(22, y), Color(UiStyle.TEXT if known else UiStyle.TEXT_DIM, 0.9), fade * p)


func _zoom_u() -> float:
	return clampf((log(_scale_target) - log(SCALE_MIN)) / (log(SCALE_MAX) - log(SCALE_MIN)), 0.0, 1.0)


## The zoom: a vine climbing the right edge, a glowing bead on it.
func _draw_zoom_vine(fade: float, void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.45) / 0.45, 0.0, 1.0)
	var top: float = ZOOM_BOTTOM - (ZOOM_BOTTOM - ZOOM_TOP) * reach
	var y: float = ZOOM_BOTTOM
	while y > top:
		var t: float = (ZOOM_BOTTOM - y) / (ZOOM_BOTTOM - ZOOM_TOP)
		var x: float = ZOOM_X + sin(y * 0.06) * 1.5
		var thick: int = maxi(roundi(lerpf(3.0, 1.0, t)), 1)
		var taken: float = VineStyle.infection((ZOOM_BOTTOM - y) * 0.5 + 40.0, void_level, int(y / 3.0))
		_overlay.draw_rect(Rect2(x - 1, y, thick + 2, 1), Color(VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken), fade))
		_overlay.draw_rect(Rect2(x, y, thick, 1), Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), fade))
		if int(y) % 3 != 1:
			_overlay.draw_rect(Rect2(x, y, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken), fade))
		y -= 1.0
	for k: int in 5: ## notches with a leaf each
		var ky: float = lerpf(ZOOM_BOTTOM, ZOOM_TOP, k / 4.0)
		if ky < top:
			continue
		VineStyle.leaf(_overlay, Vector2(ZOOM_X - 2.0, ky), -1, -1 if k % 2 == 0 else 1, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level))
	var bead: Vector2 = Vector2(ZOOM_X + sin(lerpf(ZOOM_BOTTOM, ZOOM_TOP, _zoom_u()) * 0.06) * 1.5 + 1.0, lerpf(ZOOM_BOTTOM, ZOOM_TOP, _zoom_u()))
	var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, maxf(void_level, 0.3))
	VineStyle.glow(_overlay, bead, 11.0, tone, 0.6 * fade * reach)
	_overlay.draw_rect(Rect2(bead - Vector2(2, 2), Vector2(5, 5)), Color(VineStyle.OUTLINE, fade * reach))
	_overlay.draw_rect(Rect2(bead - Vector2(1, 1), Vector2(3, 3)), Color(tone, fade * reach))
	_overlay.draw_rect(Rect2(bead, Vector2.ONE), Color(VineStyle.PETAL, fade * reach))
	_text("+", Vector2i(int(ZOOM_X) - 1, int(ZOOM_TOP) - 17), Color(UiStyle.TEXT_DIM, 0.8), fade * reach)
	_text("-", Vector2i(int(ZOOM_X) - 1, int(ZOOM_BOTTOM) + 6), Color(UiStyle.TEXT_DIM, 0.8), fade * reach)


func _draw_compass(fade: float) -> void:
	var at: Vector2 = Vector2(582, 280)
	var glow: float = 0.7 + 0.3 * sin(_time * 1.6)
	VineStyle.glow(_overlay, at, 14.0, VineStyle.VOID_GLOW, 0.3 * fade * glow)
	VineStyle.ring(_overlay, at, 9, Color(VineStyle.BARK_LIGHT, 0.7 * fade), 0.5)
	for i: int in range(-8, 9):
		var arm: float = 1.0 - absf(i) / 8.0
		var light: Color = VineStyle.VOID_GLOW if i < 0 else VineStyle.BARK_LIGHT ## north is the glowing arm
		_overlay.draw_rect(Rect2(at.x, at.y + i, 1, 1), Color(light.lerp(VineStyle.PETAL, arm * 0.4 if i < 0 else 0.0), fade * (0.5 + 0.5 * arm)))
		if absi(i) <= 5:
			_overlay.draw_rect(Rect2(at.x + i, at.y, 1, 1), Color(VineStyle.BARK_LIGHT, fade * (0.4 + 0.4 * arm)))
	_overlay.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 3)), Color(VineStyle.OUTLINE, fade))
	_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, fade))
	_text_centered("N", at + Vector2(0, -19), Color(VineStyle.LEAF_VOID_LIGHT, 0.95), fade)
