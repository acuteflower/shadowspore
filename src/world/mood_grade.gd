class_name MoodGrade
extends CanvasLayer
## The colour mood of the picture (data/mood.json, assets/shaders/mood_grade.gdshader): one pass over the finished world, under the HUD, that tones
## shade and light in opposed hues by the time of day, lifts the saturation and lets bright things glow. Cosmetic and local on every peer.
## `DayNight` creates it and calls `follow` every frame. Rooms and the mine use the `indoors` preset, the Hexenwald leans to `hex`.

const FIELDS: Array[String] = ["split", "vibrance", "contrast", "bloom", "threshold", "vignette"]

var _material: ShaderMaterial
var _keys: Array[Dictionary] = []
var _indoors: Dictionary = {}
var _hex: Dictionary = {}
var _strength: float = 1.0
var _scale: float = -1.0


func _ready() -> void:
	name = "MoodGrade"
	layer = 0
	var data: Dictionary = DataRegistry.table("mood")
	_strength = float(data.get("strength", 1.0))
	for entry: Variant in data.get("keys", []) as Array:
		_keys.append(_parse(entry as Dictionary))
	_indoors = _parse(data.get("indoors", {}) as Dictionary)
	_hex = _parse(data.get("hex", {}) as Dictionary)
	var copy: BackBufferCopy = BackBufferCopy.new() ## a fresh copy of the picture with moonlight and fog already in it
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/mood_grade.gdshader") as Shader
	rect.material = _material
	add_child(rect)
	visible = _strength > 0.0 and not _keys.is_empty()


## The mood at a time of day (0..1), pure: {shadow, light: Color, split, vibrance, contrast, bloom, threshold: float}.
func mood_at(time: float) -> Dictionary:
	if _keys.is_empty():
		return _parse({})
	if time <= float(_keys[0]["t"]) or time >= float(_keys[_keys.size() - 1]["t"]):
		return _keys[0]
	for i: int in _keys.size() - 1:
		if time < float(_keys[i + 1]["t"]):
			return blend(_keys[i], _keys[i + 1], inverse_lerp(float(_keys[i]["t"]), float(_keys[i + 1]["t"]), time))
	return _keys[0]


static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var out: Dictionary = {"shadow": (a["shadow"] as Color).lerp(b["shadow"] as Color, weight), "light": (a["light"] as Color).lerp(b["light"] as Color, weight)}
	for field: String in FIELDS:
		out[field] = lerpf(float(a[field]), float(b[field]), weight)
	return out


## Every frame (DayNight): `indoors` = a room or the mine, `gloom` = the Hexenwald's share at the camera (0..1).
func follow(indoors: bool, gloom: float) -> void:
	if not visible:
		return
	var mood: Dictionary = _indoors if indoors else mood_at(TimeManager.time_of_day)
	if not indoors and gloom > 0.0:
		mood = blend(mood, _hex, gloom)
	var shadow: Color = mood["shadow"] as Color
	var light: Color = mood["light"] as Color
	_material.set_shader_parameter("shadow_tint", Vector3(shadow.r, shadow.g, shadow.b))
	_material.set_shader_parameter("light_tint", Vector3(light.r, light.g, light.b))
	_material.set_shader_parameter("split", float(mood["split"]) * _strength)
	_material.set_shader_parameter("vibrance", float(mood["vibrance"]) * _strength)
	_material.set_shader_parameter("contrast", float(mood["contrast"]) * _strength)
	_material.set_shader_parameter("bloom", float(mood["bloom"]) * _strength)
	_material.set_shader_parameter("threshold", float(mood["threshold"]))
	_material.set_shader_parameter("vignette", float(mood["vignette"]) * _strength)
	var px_scale: float = (get_viewport().get_final_transform() * get_viewport().get_canvas_transform()).get_scale().x ## screen pixels per art pixel
	if absf(px_scale - _scale) > 0.001:
		_scale = px_scale
		_material.set_shader_parameter("px_scale", px_scale)


func _parse(entry: Dictionary) -> Dictionary:
	var out: Dictionary = {"t": float(entry.get("t", 0.0)), "shadow": _tint(entry.get("shadow", [1.0, 1.0, 1.0])), "light": _tint(entry.get("light", [1.0, 1.0, 1.0]))}
	for field: String in FIELDS:
		out[field] = float(entry.get(field, 0.6 if field == "threshold" else 0.0))
	return out


func _tint(value: Variant) -> Color:
	var list: Array = value as Array
	return Color(float(list[0]), float(list[1]), float(list[2])) if list != null and list.size() >= 3 else Color.WHITE
