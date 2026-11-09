class_name DayNight
extends CanvasModulate
## Tints the whole world with the time of day and lets the night lights know how dark it is.
## HUD layers and anything with an unshaded material (see Unlit) stay untouched.

var _last_night: float = -1.0
const GLOBAL_EPSILON: float = 0.0005 ## shader globals below this change are not worth a server call
const NIGHT_CALL_MS: int = 100 ## the night lights hear about a change at most this often
var _g_sun: float = -1000.0
var _g_night: float = -1000.0
var _g_dew: float = -1000.0
var _night_sent_ms: int = -1000
var _glow: ShaderMaterial
var _ground: ShaderMaterial
var _sun_glow: ShaderMaterial
var _daylight: DaylightField
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
	_daylight = DaylightField.new()
	get_parent().add_child.call_deferred(_daylight)
	_add_sun_glow()
	_ambience = DayAmbience.new()
	add_child(_ambience)
	_atmosphere = NightAtmosphere.new() ## moonlight, violet ambient light, night fog (docs/nacht_atmosphaere.md)
	add_child(_atmosphere)
	get_parent().add_child.call_deferred(DayMotes.new())
	_interiors = get_parent().get_node_or_null("Interiors") as Interiors
	_mines = get_parent().get_node_or_null("Mines") as MineManager
	_update()


## Restrained flat fill; local sunlight and canopy shafts are world anchored in DaylightField.
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
	if not indoors:
		var wet: float = Moisture.wetness() ## a damp day or after a fog night: the world is a little cooler and darker
		color = color.lerp(color * Color(0.9, 0.95, 1.0, 1.0), wet * 0.6)
	var sun: float = 0.0 if indoors else TimeManager.sun_amount()
	_daylight.follow(indoors, sun, TimeManager.golden_amount())
	if _ground != null:
		_ground.set_shader_parameter("sun", sun)
		_ground.set_shader_parameter("golden", 0.0 if indoors else TimeManager.golden_amount())
	if _sun_glow != null:
		_sun_glow.set_shader_parameter("sun", sun)
		_sun_glow.set_shader_parameter("golden", 0.0 if indoors else TimeManager.golden_amount())
	## water glints, crystal and flora sparkle, void lip: only sent when they really moved
	var g_night: float = 0.0 if indoors else TimeManager.night_amount()
	var g_dew: float = 0.0 if indoors else maxf(TimeManager.dew_amount(), 0.7 * Moisture.wetness()) ## the wet ground shows dew drops
	if absf(sun - _g_sun) > GLOBAL_EPSILON:
		_g_sun = sun
		RenderingServer.global_shader_parameter_set("g_sun", sun)
	if absf(g_night - _g_night) > GLOBAL_EPSILON:
		_g_night = g_night
		RenderingServer.global_shader_parameter_set("g_night", g_night)
	if absf(g_dew - _g_dew) > GLOBAL_EPSILON:
		_g_dew = g_dew
		RenderingServer.global_shader_parameter_set("g_dew", g_dew)
	var night: float = TimeManager.night_amount()
	var now: int = Time.get_ticks_msec()
	if absf(night - _last_night) > 0.002 and now - _night_sent_ms >= NIGHT_CALL_MS: ## at most 10 times a second during dusk
		_night_sent_ms = now
		_last_night = night
		get_tree().call_group("night_lights", "set_night", night)
	_ambience.follow(sun, night, indoors, get_process_delta_time())
	_atmosphere.update(indoors)
	if _glow != null:
		_glow.set_shader_parameter("night", night)
