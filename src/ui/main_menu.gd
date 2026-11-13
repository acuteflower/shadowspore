class_name MainMenu
extends Node
## The main menu (docs/hauptmenue_konzept.md, "Licht ist Land"): the real world at night, Valdric's hut yard with its fire, no player in it. The camp
## is a clearing of land in the abyss (`menu_void.gdshader`, the same void as the world's edge): scorched ground and a bright dashed lip at the rim,
## banded violet haze beyond, the slow heartbeat of the abyss; the cursor carries its own little island of land. The opening: all is void, the fire
## catches and the land grows out round it, the SHADOWSPORE logo builds itself in the void above, the entries rise from the fire as embers and land as
## words in the shadow on the left (`MainMenuUi`). Specks: `MenuEmbers`. What is chosen goes to `GameLauncher`, which reloads main.tscn and starts
## the game. Preview/capture without the game around it: `tools/preview_main_menu.tscn`.

const VOID_SHADER: Shader = preload("res://assets/shaders/menu_void.gdshader")
const FIRE_AT_SCREEN: Vector2 = Vector2(468.0, 292.0) ## where the fire stands in the 640 x 360 picture
const FIRE_OFFSET: Vector2 = Vector2(34.0, 64.0) ## the fire pit from the hut's feet (data/ground.json yard "pit")
const LOGO_POS: Vector2 = Vector2(100.0, -40.0)
const NIGHT_TIME: float = 0.88
const IGNITE_AT: float = 0.7 ## seconds of void before the fire catches
const GROW_SECONDS: float = 1.8 ## the land grows out round the fire
const BUILD_AFTER: float = 0.9 ## the logo starts to build
const LETTERS_AFTER: float = 2.2 ## the entries start to rise from the fire
const DRIFT: float = 4.0 ## the camera sways this many pixels left and right

var _world: Node ## a WorldLevel (see menu_world.gd): duck-typed on purpose
var _camera: Camera2D
var _camera_home: Vector2 = Vector2.ZERO
var _dark: ColorRect
var _material: ShaderMaterial
var _embers: MenuEmbers
var _ui: MainMenuUi
var _logo: TitleLogo
var _black: ColorRect
var _t0_usec: int = 0
var _leaving: String = ""
var _leave_data: Dictionary = {}
var _leave_age: float = 0.0
var _skipped: bool = false
var _skip_bonus: float = 0.0
var _light_pos: Vector2 = Vector2.ZERO
var _light_size: float = 0.0
var _logo_started: bool = false
var _ignited: bool = false
var _fire_world: Vector2 = Vector2.ZERO
var _fire_screen: Vector2 = FIRE_AT_SCREEN
var _reach: float = 0.0
var capture_mode: bool = false ## the preview scene drives the clock itself


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputManager.ui_blocking = true
	_build_world() ## (takes a moment: the clock of the opening starts after it)
	_t0_usec = Time.get_ticks_usec()
	var dark_layer: CanvasLayer = CanvasLayer.new()
	dark_layer.layer = 10
	add_child(dark_layer)
	_dark = ColorRect.new()
	_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = VOID_SHADER
	_dark.material = _material
	dark_layer.add_child(_dark)
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.layer = 11
	add_child(ui_layer)
	_embers = MenuEmbers.new()
	ui_layer.add_child(_embers)
	_logo = TitleLogo.new()
	_logo.position = LOGO_POS
	_logo.visible = false
	ui_layer.add_child(_logo)
	_ui = MainMenuUi.new()
	_ui.chosen.connect(_on_chosen)
	ui_layer.add_child(_ui)
	var black_layer: CanvasLayer = CanvasLayer.new()
	black_layer.layer = 20
	add_child(black_layer)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	black_layer.add_child(_black)
	_update_void(0.0, 0.0)


func clock() -> float:
	return float(Time.get_ticks_usec() - _t0_usec) / 1000000.0


## The real world with nobody in it, framed on the fire at the hut.
func _build_world() -> void:
	_world = (load(GameLauncher.WORLD_PATH) as PackedScene).instantiate()
	_world.set_script(load("res://src/ui/menu_world.gd") as Script)
	add_child(_world)
	_world.set_process(false)
	var hut: Node2D = _world.call("hut_node") as Node2D
	_fire_world = hut.global_position + FIRE_OFFSET
	var view: Vector2 = Vector2(640.0, 360.0)
	_camera = Camera2D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera_home = (_fire_world - FIRE_AT_SCREEN + view / 2.0).round()
	_camera.position = _camera_home
	_camera.zoom = Vector2.ONE
	_world.add_child(_camera)
	var middle: Vector2i = Vector2i((_camera.position / 512.0).floor())
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var cell: Vector2i = middle + Vector2i(dx, dy)
			if not (_world.get("_chunks") as Dictionary).has(cell):
				_world.call("_load_chunk", cell)
	hut.call("set_renewed", true) ## the mended hut, lit window
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.day = 0
	TimeManager.time_of_day = NIGHT_TIME


func _play(path: String, db: float) -> void:
	var s: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	if s != null:
		Sfx.ui_stream(self, s, db)


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.1)
	var t: float = clock()
	# the opening: void, then the fire catches and the land grows out round it
	if not _ignited and t >= IGNITE_AT:
		_ignited = true
		_embers.burst(_fire_screen, 40, 80.0)
		_play("res://assets/audio/magic/ember_burst.wav", -8.0)
	var grow: float = clampf((t - IGNITE_AT) / GROW_SECONDS, 0.0, 1.0)
	_embers.intensity = clampf((t - IGNITE_AT) / 1.2, 0.0, 1.0)
	if _leaving.is_empty():
		_black.color.a = clampf(1.0 - t / 0.6, 0.0, 1.0)
		_reach = (1.0 - pow(1.0 - grow, 3.0)) if _ignited else 0.0
	else:
		_leave_age += dt
		_update_leaving()
		if _leave_age >= 1.15:
			_finish_leaving()
			return
	var boot: float = t - BUILD_AFTER
	if boot >= 0.0 and not _logo_started and not capture_mode:
		_logo_started = true
		_logo.visible = true
		_logo.play_build()
	if _skipped:
		_skip_bonus += dt * 2.0 ## a click during the build: the entries rise faster too
	if not capture_mode:
		_ui.intro = maxf(t - LETTERS_AFTER, 0.0) + _skip_bonus
	_ui.enabled = _ui.intro > MainMenuUi.INTRO_DONE and _leaving.is_empty()
	var dim: float = 0.2 if _ui.page != MainMenuUi.Page.MAIN else 1.0
	_logo.modulate.a = move_toward(_logo.modulate.a, dim, dt * 3.0)
	# the camera sways slowly; the fire is followed on screen
	var sway: Vector2 = Vector2(sin(t * TAU / 26.0) * DRIFT, sin(t * TAU / 37.0) * 2.0)
	_camera.position = (_camera_home + sway).round()
	_fire_screen = _fire_world - _camera.position + get_viewport().get_visible_rect().size / 2.0
	_embers.fire = _fire_screen + Vector2(0.0, -6.0)
	_ui.fire_point = _fire_screen + Vector2(0.0, -10.0)
	_update_void(dt, t)


func _update_leaving() -> void:
	var u: float = _leave_age
	if _leaving == "quit":
		# the abyss swallows the camp
		_reach = lerpf(1.0, 0.0, smoothstep(0.0, 0.9, u))
		_embers.intensity = 1.0 - smoothstep(0.0, 0.7, u)
		_black.color.a = smoothstep(0.7, 1.1, u)
	else:
		# the land grows over the whole picture, a warm white, then black
		_reach = 1.0 + 1.5 * smoothstep(0.0, 0.8, u)
		_material.set_shader_parameter("flash", smoothstep(0.35, 0.8, u) * 0.8)
		_black.color.a = smoothstep(0.75, 1.1, u)


func _update_void(dt: float, t: float) -> void:
	var viewport: Viewport = get_viewport()
	var mouse: Vector2 = viewport.get_mouse_position()
	var using_mouse: bool = InputManager.using_mouse and viewport.get_visible_rect().has_point(mouse) and _ignited
	_light_pos = mouse if _light_pos == Vector2.ZERO else _light_pos.lerp(mouse, clampf(dt * 14.0, 0.0, 1.0))
	_light_size = move_toward(_light_size, 1.0 if using_mouse else 0.0, dt * 3.0)
	_embers.light = _light_pos
	_embers.cursor_on = using_mouse
	_material.set_shader_parameter("size", viewport.get_visible_rect().size)
	_material.set_shader_parameter("fire", _fire_screen + Vector2(0.0, -6.0))
	_material.set_shader_parameter("land", _reach)
	_material.set_shader_parameter("light", _light_pos)
	_material.set_shader_parameter("light_r", 46.0 * _light_size)
	_material.set_shader_parameter("cursor_on", 1.0 if _light_size > 0.01 else 0.0)
	_material.set_shader_parameter("time", t)


func _input(event: InputEvent) -> void:
	if _skipped or not _logo_started or not _leaving.is_empty():
		return
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventKey or event is InputEventJoypadButton:
		pressed = event.is_pressed() and not event.is_echo()
	if pressed and clock() - BUILD_AFTER > 0.6 and _logo.is_building():
		_skipped = true
		_logo.skip_build()


func _on_chosen(id: String, data: Dictionary) -> void:
	if not _leaving.is_empty():
		return
	_leaving = id
	_leave_data = data
	_leave_age = 0.0
	_ui.enabled = false
	if id != "quit":
		_embers.burst(_fire_screen, 70, 120.0)
		_play("res://assets/audio/magic/ember_burst.wav", -4.0)


func _finish_leaving() -> void:
	set_process(false)
	if _leaving == "quit":
		get_tree().quit()
		return
	var request: Dictionary = {"mode": _leaving}
	request.merge(_leave_data)
	GameLauncher.launch(get_tree(), request)
