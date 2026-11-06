class_name DayNight
extends CanvasModulate
## Tints the whole world with the time of day and lets the night lights know how dark it is.
## HUD layers and anything with an unshaded material (see Unlit) stay untouched.

var _last_night: float = -1.0
var _glow: ShaderMaterial
var _ground: ShaderMaterial
var _sun_glow: ShaderMaterial
var _ambience: DayAmbience
var _atmosphere: NightAtmosphere
var _interiors: Interiors
var _mines: MineManager


func _ready() -> void:
	var glow: Node = get_parent().get_node_or_null("Glow")
	if glow != null:
		_glow = (glow as CanvasItem).material as ShaderMaterial
	var ground: Node = get_parent().get_node_or_null("Ground")
	if ground != null:
		_ground = (ground as CanvasItem).material as ShaderMaterial
	_add_sun_glow()
	_ambience = DayAmbience.new()
	add_child(_ambience)
	_atmosphere = NightAtmosphere.new() ## moonlight, violet ambient light, night fog (docs/nacht_atmosphaere.md)
	add_child(_atmosphere)
	get_parent().add_child.call_deferred(DayMotes.new())
	_interiors = get_parent().get_node_or_null("Interiors") as Interiors
	_mines = get_parent().get_node_or_null("Mines") as MineManager
	_update()


## One additive, dithered quad under the HUD: warm light falling in from the top left.
func _add_sun_glow() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 0
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun_glow = ShaderMaterial.new()
	_sun_glow.shader = load("res://assets/shaders/sun_glow.gdshader") as Shader
	rect.material = _sun_glow
	layer.add_child(rect)
	add_child(layer)


var _budget_clock: float = 0.0


func _process(delta: float) -> void:
	_update()
	_budget_clock -= delta
	if _budget_clock <= 0.0 and TimeManager.night_amount() > 0.01:
		_budget_clock = 0.3
		var camera: Camera2D = get_viewport().get_camera_2d()
		if camera != null:
			NightLight.budget(get_tree(), camera.get_screen_center_position())


func _update() -> void:
	if _mines == null: ## the level adds the mine after this node is ready
		_mines = get_parent().get_node_or_null("Mines") as MineManager
	var room: Color = _interiors.ambient_color() if _interiors != null else Color(0, 0, 0, 0)
	if room.a <= 0.0 and _mines != null:
		room = _mines.ambient_color() ## the mine has the colour of its zone
	color = room if room.a > 0.0 else TimeManager.ambient_color() ## inside a room it has its own light
	var indoors: bool = room.a > 0.0 ## rooms and the mine have their own light, no sun
	var sun: float = 0.0 if indoors else TimeManager.sun_amount()
	if _ground != null:
		_ground.set_shader_parameter("sun", sun)
		_ground.set_shader_parameter("golden", 0.0 if indoors else TimeManager.golden_amount())
	if _sun_glow != null:
		_sun_glow.set_shader_parameter("sun", sun)
		_sun_glow.set_shader_parameter("golden", 0.0 if indoors else TimeManager.golden_amount())
	RenderingServer.global_shader_parameter_set("g_sun", sun) ## water glints, crystal and flora sparkle, void lip
	RenderingServer.global_shader_parameter_set("g_night", 0.0 if indoors else TimeManager.night_amount())
	RenderingServer.global_shader_parameter_set("g_dew", 0.0 if indoors else TimeManager.dew_amount())
	var night: float = TimeManager.night_amount()
	if absf(night - _last_night) > 0.002:
		_last_night = night
		get_tree().call_group("night_lights", "set_night", night)
	_ambience.follow(sun, night, indoors, get_process_delta_time())
	_atmosphere.update(indoors)
	if _glow != null:
		_glow.set_shader_parameter("night", night)
