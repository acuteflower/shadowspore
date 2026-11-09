class_name MainMenu
extends Node
## The main menu (docs/hauptmenue_konzept.md, direction "Lager + Cursor-Licht"): the real world at night, seen at Valdric's hut yard with its fire, no player in it;
## over it the dark (`menu_dark.gdshader`: it closes in from the edges, the fire and the cursor hold pools of light open), the SHADOWSPORE logo building itself,
## and the entries as name tags on a vine (`MainMenuUi`). What is chosen goes to `GameLauncher`, which reloads main.tscn and starts the game.
## Preview/capture without the game around it: `tools/preview_main_menu.tscn`.

const DARK: Shader = preload("res://assets/shaders/menu_dark.gdshader")
const FIRE_AT_SCREEN: Vector2 = Vector2(352.0, 262.0) ## where the fire stands in the 640 x 360 picture
const FIRE_OFFSET: Vector2 = Vector2(34.0, 64.0) ## the fire pit from the hut's feet (data/ground.json yard "pit")
const LOGO_POS: Vector2 = Vector2(100.0, -26.0)
const NIGHT_TIME: float = 0.88
const BUILD_AFTER: float = 0.5 ## seconds of black before the logo starts to build
const TAGS_AFTER: float = 2.0 ## the vine starts to grow this long after the logo began

var _world: Node ## a WorldLevel (see menu_world.gd): duck-typed on purpose
var _camera: Camera2D
var _dark: ColorRect
var _material: ShaderMaterial
var _ui: MainMenuUi
var _logo: TitleLogo
var _black: ColorRect
var _t0_usec: int = 0
var _fade_in: float = 1.0 ## the black over everything, 1 = black
var _leaving: String = ""
var _leave_data: Dictionary = {}
var _leave_age: float = 0.0
var _skipped: bool = false
var _skip_bonus: float = 0.0
var _light_pos: Vector2 = Vector2.ZERO
var _flare: float = 0.0
var _logo_started: bool = false
var _fire_world: Vector2 = Vector2.ZERO
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
	_material.shader = DARK
	_dark.material = _material
	dark_layer.add_child(_dark)
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.layer = 11
	add_child(ui_layer)
	_logo = TitleLogo.new()
	_logo.position = LOGO_POS
	_logo.visible = false
	ui_layer.add_child(_logo)
	_logo.impact.connect(_on_impact)
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
	_camera.position = (_fire_world - FIRE_AT_SCREEN + view / 2.0).round()
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


func _on_impact() -> void:
	_flare = 1.0


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.1)
	var t: float = clock()
	var boot: float = t - BUILD_AFTER
	# the black over everything lifts, then the logo builds
	if _leaving.is_empty():
		_fade_in = clampf(1.0 - t / 0.9, 0.0, 1.0)
	else:
		_leave_age += dt
		_fade_in = clampf(_leave_age / 0.7, 0.0, 1.0)
		if _leave_age >= 0.75:
			_finish_leaving()
			return
	_black.color.a = _fade_in
	if boot >= 0.0 and not _logo_started and not capture_mode:
		_logo_started = true
		_logo.visible = true
		_logo.play_build()
	if _skipped:
		_skip_bonus += dt * 2.0 ## a click during the build: the vine grows faster too
	if not capture_mode:
		_ui.intro = maxf(boot - TAGS_AFTER, 0.0) + _skip_bonus
	_ui.enabled = _ui.intro > 1.7 and _leaving.is_empty()
	var dim: float = 0.2 if _ui.page != MainMenuUi.Page.MAIN else 1.0
	_logo.modulate.a = move_toward(_logo.modulate.a, dim, dt * 3.0)
	_update_dark(dt, t)


func _update_dark(dt: float, t: float) -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var using_mouse: bool = InputManager.using_mouse and get_viewport().get_visible_rect().has_point(mouse)
	if Input.is_action_just_pressed("action_primary"):
		_flare = 1.0
	_flare = move_toward(_flare, 0.0, dt * 2.2)
	var light: Vector2 = mouse if using_mouse else _ui.focus_point()
	_light_pos = light if _light_pos == Vector2.ZERO else _light_pos.lerp(light, clampf(dt * 14.0, 0.0, 1.0))
	_material.set_shader_parameter("light", _light_pos)
	_material.set_shader_parameter("light_r", 74.0 if using_mouse else 54.0)
	_material.set_shader_parameter("flare", _flare)
	_material.set_shader_parameter("fire", FIRE_AT_SCREEN + Vector2(0.0, -8.0))
	_material.set_shader_parameter("fire_r", 118.0)
	_material.set_shader_parameter("time", t)
	_material.set_shader_parameter("cursor_on", 1.0)
	_material.set_shader_parameter("strength", clampf((t - 0.2) / 1.2, 0.0, 1.0))


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
	_flare = 1.0


func _finish_leaving() -> void:
	set_process(false)
	if _leaving == "quit":
		get_tree().quit()
		return
	var request: Dictionary = {"mode": _leaving}
	request.merge(_leave_data)
	GameLauncher.launch(get_tree(), request)
