class_name NightAtmosphere
extends Node
## The night's mood (docs/nacht_atmosphaere.md), cosmetic and local on every peer: two screen quads under the HUD, both anchored in the world.
## `night_moon.gdshader` (additive): a violet ambient wash that deepens towards the edges, pools of moonlight and glints. `night_fog.gdshader`: drifting
## violet-grey fog that the town's light pushes back. The moon has phases (eight days: new moon dim and foggy, full moon bright), a fog night (special night) brings
## heavy fog and shrinks the light, a thin mist lies over the dawn. Nothing indoors or in the mine (they have their own light).

const LIGHTS: int = 8

var fog: float = 0.0 ## 0..1, what the shader uses right now (readable for tests)
var moon: float = 0.0
var hex: float = 0.0 ## 0..1, the Hexenwald's own mist on this screen (by day too)
var clearing: float = 0.0 ## px: how far the Ohrringe der Klarheit push it back round the local heroine right now
var special: String = "none" ## tonight's special kind (the same pure function the NightDirector uses, so every peer agrees)

var _layer: CanvasLayer
var _fog_material: ShaderMaterial
var _moon_material: ShaderMaterial
var _special_day: int = -999999
var _origin: Vector2 = Vector2.ZERO
var _view: Vector2 = Vector2(640, 360)
var _town: TownManager = null ## cached: the group lookup runs every frame otherwise
var _town_look_at: int = 0 ## ticks (ms) before which a missing town is not looked up again
var _last_sky: Vector4 = Vector4(INF, INF, INF, INF)
var _last_sky_view: Vector4 = Vector4(INF, INF, INF, INF)
var _last_hex_sample_pos: Vector2 = Vector2(INF, INF)
var _cached_deep: float = 0.0
var _last_sent_origin: Vector2 = Vector2(INF, INF)
var _last_sent_view: Vector2 = Vector2(INF, INF)
var _last_fog: float = -1.0
var _last_hex: float = -1.0
var _last_clear: float = -1.0
var _last_night: float = -1.0
var _last_moon: float = -1.0


## The town node, cached. While there is none it is looked up at most twice a second.
func _find_town() -> TownManager:
	if not is_instance_valid(_town):
		_town = null
		var now: int = Time.get_ticks_msec()
		if now >= _town_look_at:
			_town_look_at = now + 500
			_town = get_tree().get_first_node_in_group("town") as TownManager
	return _town


func _ready() -> void:
	name = "NightAtmosphere"
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)
	_moon_material = _add_rect("res://assets/shaders/night_moon.gdshader")
	_fog_material = _add_rect("res://assets/shaders/night_fog.gdshader")
	RenderingServer.frame_pre_draw.connect(_push_transform) ## the camera has moved by then: reading it in _process lags a frame behind and the light would slide against the ground


func _add_rect(shader_path: String) -> ShaderMaterial:
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(shader_path) as Shader
	rect.material = material
	_layer.add_child(rect)
	return material


## Called every frame by `DayNight` (which knows whether she is indoors).
func update(indoors: bool) -> void:
	var night: float = 0.0 if indoors else TimeManager.night_amount()
	moon = TimeManager.moon_light()
	if TimeManager.day != _special_day:
		_special_day = TimeManager.day
		special = NightRules.special_for(_world_seed(), _special_day)
	var window: bool = NightRules.progress(TimeManager.time_of_day) >= 0.0
	var town: TownManager = _find_town()
	if town != null:
		town.light_scale = NightRules.light_scale(special) if window else 1.0
	_update_view_rect()
	var deep: float = 0.0 ## the wood anywhere on this screen
	if not indoors:
		var centre_pos: Vector2 = _origin + _view * 0.5
		if _last_hex_sample_pos.distance_squared_to(centre_pos) > 64.0:
			_last_hex_sample_pos = centre_pos
			var sample_deep: float = 0.0
			for corner: Vector2 in [Vector2(0.5, 0.5), Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]:
				sample_deep = maxf(sample_deep, BiomeBlend.amount_at(_origin + _view * corner))
			_cached_deep = sample_deep
		deep = _cached_deep
	night = lerpf(night, 1.0, deep) ## the Hexenwald is always night: moon pools and fog run at full strength there
	var mist: float = 0.0 if indoors else 0.4 * TimeManager.dew_amount() ## the dawn: a thin mist that burns off
	fog = maxf(night * clampf(0.22 + 0.34 * (1.0 - moon) * 2.0 + NightRules.fog_boost(special), 0.0, 1.0), mist)
	hex = 0.0 if deep <= 0.003 else 0.74 + 0.22 * night
	clearing = move_toward(clearing, 230.0 if _clear_sighted() else 0.0, 150.0 * get_process_delta_time()) ## putting them on: the mist draws back as a wave
	_push_sky(night)
	_layer.visible = night > 0.003 or fog > 0.003 or hex > 0.003
	if not _layer.visible:
		return
	if absf(hex - _last_hex) > 0.0005:
		_last_hex = hex
		_fog_material.set_shader_parameter("hex", hex)
	if absf(clearing - _last_clear) > 0.05:
		_last_clear = clearing
		_fog_material.set_shader_parameter("clear_px", clearing)
	if absf(fog - _last_fog) > 0.0005:
		_last_fog = fog
		_moon_material.set_shader_parameter("fog", fog)
		_fog_material.set_shader_parameter("fog", fog)
	if absf(night - _last_night) > 0.0005:
		_last_night = night
		_moon_material.set_shader_parameter("night", night)
		_fog_material.set_shader_parameter("night", night)
	if absf(moon - _last_moon) > 0.0005:
		_last_moon = moon
		_moon_material.set_shader_parameter("moon", moon)
	_fog_material.set_shader_parameter("lights", _lights(town, _origin + _view * 0.5, _view.length() * 0.5))


## The local heroine wears a piece with the perk `clear_sight` (duck typed: this node must not name Player).
func _clear_sighted() -> bool:
	for player: Player in Player.all:
		if is_instance_valid(player) and player.is_multiplayer_authority():
			var worn: Variant = player.get("talismans")
			return worn != null and (worn.get("perks") as Dictionary).has("clear_sight")
	return false


func _update_view_rect() -> void:
	if not is_inside_tree():
		return
	var transform: Transform2D = get_viewport().get_canvas_transform()
	_origin = transform.affine_inverse() * Vector2.ZERO
	_view = get_viewport().get_visible_rect().size / transform.get_scale()
	var full: Transform2D = get_viewport().get_final_transform() * transform
	var snapped_origin: Vector2 = full.origin.round()
	var exact: Vector2 = Transform2D(full.x, full.y, snapped_origin).affine_inverse() * Vector2.ZERO
	if exact.is_finite() and exact.distance_squared_to(_origin) < 1.0:
		_origin = exact


## Hands the camera's current view (world origin and size of the screen) to both shaders. Runs right before every draw, so the pools and the fog stay nailed to the ground.
func _push_transform() -> void:
	if not is_inside_tree() or _moon_material == null:
		return
	_update_view_rect()
	var sky_view: Vector4 = Vector4(_origin.x, _origin.y, _view.x, _view.y)
	if not sky_view.is_equal_approx(_last_sky_view):
		_last_sky_view = sky_view
		RenderingServer.global_shader_parameter_set(&"g_sky_view", sky_view)
	if not _layer.visible:
		return
	if _origin.distance_squared_to(_last_sent_origin) > 0.0001 or _view.distance_squared_to(_last_sent_view) > 0.0001:
		_last_sent_origin = _origin
		_last_sent_view = _view
		for material: ShaderMaterial in [_moon_material, _fog_material]:
			material.set_shader_parameter("world_origin", _origin)
			material.set_shader_parameter("view_px", _view)


## The night sky that water mirrors (night_sky.gdshaderinc, docs/wasserspiegelung.md): x how far the night has run (dusk 0 .. dawn 1, the moon
## crosses the sky with it), y the moon's phase, z how much sky shows (0 by day and indoors; fog veils it), w how bright the moon is.
func _push_sky(night: float) -> void:
	var run: float = clampf(fposmod(TimeManager.time_of_day - 0.78, 1.0) / 0.462, 0.0, 1.0)
	var veil: float = clampf(fog, 0.0, 1.0)
	var strength: float = smoothstep(0.15, 0.8, night) * (1.0 - 0.55 * veil)
	var sky_vec: Vector4 = Vector4(run, TimeManager.moon_phase(), strength, clampf(0.55 + 0.6 * (moon - 0.65) / 0.35, 0.0, 1.0) * (1.0 - 0.5 * veil))
	if not sky_vec.is_equal_approx(_last_sky):
		_last_sky = sky_vec
		RenderingServer.global_shader_parameter_set(&"g_sky", sky_vec)


## The (up to eight) circles of light nearest to the middle of the screen that reach into it: x, y, radius.
func _lights(town: TownManager, centre: Vector2, reach: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(LIGHTS)
	if town == null or not town.founded:
		return out
	var near: Array[Vector3] = []
	for c: Vector3 in town.lit_circles():
		if Vector2(c.x, c.y).distance_to(centre) <= reach + c.z:
			near.append(c)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return Vector2(a.x, a.y).distance_to(centre) < Vector2(b.x, b.y).distance_to(centre))
	for i: int in mini(near.size(), LIGHTS):
		out[i] = near[i]
	return out


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_push_transform):
		RenderingServer.frame_pre_draw.disconnect(_push_transform)


func _world_seed() -> int:
	var level: Node = get_parent().get_parent() if get_parent() != null else null
	var map: Variant = level.get("_map") if level != null else null
	return int(map.world_seed) if map != null else 0
