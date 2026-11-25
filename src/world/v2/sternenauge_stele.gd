class_name SternenaugeStele
extends Node2D
## Runenstele am Sternenauge (`tools/art_sternenauge_plaza.py`, 3 Varianten x wild|erwacht).
## Rein visuell: folgt dem Erwachen der Statue (Gruppe `windkap_lighthouse`), y-sortiert, kleine Kollision.

const SHEET: String = "res://assets/props/sternenauge/stele.png"
const GLOW: String = "res://assets/props/sternenauge/stele_glow.png"

var variant: int = 0
var flip: bool = false

var _frame: Vector2 = Vector2(32.0, 68.0)
var _foot: Vector2 = Vector2(16.0, 64.0)
var _wild: Sprite2D = null
var _awake: Sprite2D = null
var _glow: Sprite2D = null
var _light: NightLight = null
var _statue: Sternenauge = null
var _time: float = 0.0


func _ready() -> void:
	add_to_group("flora_glow")
	var meta: Dictionary = DataRegistry.table("sternenauge_plaza")
	_frame = WindkapProps._vec2_from(meta.get("stele_frame"), _frame)
	_foot = WindkapProps._vec2_from(meta.get("stele_foot"), _foot)
	variant = clampi(variant, 0, int(meta.get("stele_variants", 3)) - 1)
	var tex: Texture2D = load(SHEET) as Texture2D
	_wild = _make("Wild", tex, 0, WindkapProps.day_material())
	_awake = _make("Awake", tex, 1, WindkapProps.day_material())
	var gtex: Texture2D = load(GLOW) as Texture2D
	if gtex != null:
		_glow = _make("Glow", gtex, 1, Unlit.material())
	_light = NightLight.new()
	_light.name = "RuneLight"
	_light.position = Vector2(0.0, -_foot.y * 0.5)
	_light.radius = 34
	_light.squash = 0.6
	_light.base_energy = 0.0
	_light.pulse = 0.18
	_light.glow_color = Color("78f4e6")
	add_child(_light)
	WindkapProps._add_box_colliders(self, "Body", [[-7, -4, 14, 6]])


func _make(n: String, tex: Texture2D, row: int, mat: Material) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.name = n
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2(_frame.x * float(variant), _frame.y * float(row), _frame.x, _frame.y)
	s.centered = false
	s.offset = -_foot
	s.flip_h = flip
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.material = mat
	add_child(s)
	return s


func _process(delta: float) -> void:
	_time += delta
	if _statue == null or not is_instance_valid(_statue):
		_statue = get_tree().get_first_node_in_group("windkap_lighthouse") as Sternenauge
	var b: float = _statue.awake_blend() if _statue != null else 0.0
	_awake.modulate.a = b
	_wild.visible = b < 1.0
	var night: float = TimeManager.night_amount()
	var breath: float = 0.84 + 0.16 * sin(_time * 2.1 + float(variant) * 1.7)
	if _glow != null:
		_glow.modulate.a = (lerpf(0.1, 0.35, night) + b * lerpf(0.4, 0.65, night)) * breath
	if _light != null:
		_light.base_energy = b * 0.45
