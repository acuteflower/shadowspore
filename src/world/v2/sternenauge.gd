class_name Sternenauge
extends Node2D
## DAS STERNENAUGE — Caelias kniende Leuchtturm-Statue auf dem Windkap (Story-Startkonstrukt).
## Ersetzt den alten Steinsetzer-Leuchtturm. Zwei Zustände aus `tools/art_sternenauge.py`:
## WILD (Linse dunkel, Leerenkristalle) und ERWACHT (Linse brennt, Strahl über das Meer).
## Der Knoten sitzt im Mittelpunkt der Bodenellipse des Sockels (y-Sortierung, Kollision).
## Rein visuell: Der Zustand kommt vom Host über `set_awakened` (heute: die Kartentafel,
## später: die Story-Szene an der Linse). Gruppe `windkap_lighthouse` bleibt für Nachtschutz & Tafel.

const SHEET: String = "res://assets/props/sternenauge/sternenauge.png"
const GLOW: String = "res://assets/props/sternenauge/sternenauge_glow.png"
const PLAZA_OFFSET: Vector2 = Vector2(0.0, 4.0) ## sanctum center (steles, clear zone) relative to the statue's ground center
const BEAM_SHADER: Shader = preload("res://assets/shaders/sternenauge_beam.gdshader")
const BEAM_LENGTH: float = 440.0
const BEAM_WIDTH: float = 96.0
const BEAM_DIR: Vector2 = Vector2(-1.0, 0.42) ## zum offenen Meer (West-Südwest)
const BEAM_SWEEP: float = 0.22 ## rad, langsames Schwenken
const AWAKEN_TIME: float = 2.6
const CRYPT: String = "sternenauge_krypta" ## data/interiors.json, art: tools/art_sternenauge_crypt.py

var awakened: bool = false
var doorway: Doorway ## the crypt door at the foot of the plinth (E): into the crypt under the statue
var exit_position: Vector2 ## where she stands when she comes back out of the crypt

var _frame: Vector2 = Vector2(212.0, 379.0)
var _origin: Vector2 = Vector2(106.0, 330.0) ## Bodenellipsen-Mitte im Frame
var _lens: Vector2 = Vector2(107.0, 34.0)
var _radii: Vector2 = Vector2(102.0, 42.0)
var _wild: Sprite2D = null
var _awake: Sprite2D = null
var _glow_wild: Sprite2D = null
var _glow_awake: Sprite2D = null
var _beam_pivot: Node2D = null
var _beam: ColorRect = null
var _beam_mat: ShaderMaterial = null
var _lens_light: NightLight = null
var _base_light: NightLight = null
var _blend: float = 0.0 ## 0 = wild, 1 = erwacht
var _time: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	add_to_group("windkap_lighthouse")
	add_to_group("night_lights")
	add_to_group("flora_glow")
	WaterReflections.watch(self, false)
	tree_exiting.connect(func() -> void: WaterReflections.unwatch(self))
	_read_art()

	var tex: Texture2D = load(SHEET) as Texture2D
	var gtex: Texture2D = load(GLOW) as Texture2D
	_wild = _make_sprite("Wild", tex, 0, WindkapProps.day_material())
	_awake = _make_sprite("Awake", tex, 1, WindkapProps.day_material())
	if gtex != null:
		_glow_wild = _make_sprite("GlowWild", gtex, 0, Unlit.material())
		_glow_awake = _make_sprite("GlowAwake", gtex, 1, Unlit.material())

	var lens_pos: Vector2 = _lens - _origin
	_lens_light = NightLight.new()
	_lens_light.name = "LensLight"
	_lens_light.position = lens_pos + Vector2(0.0, 6.0)
	_lens_light.radius = 150
	_lens_light.squash = 0.8
	_lens_light.base_energy = 0.2
	_lens_light.pulse = 0.16
	_lens_light.glow_color = Color("d0fff8")
	add_child(_lens_light)

	_base_light = NightLight.new()
	_base_light.name = "BaseLight"
	_base_light.position = Vector2(0.0, 6.0)
	_base_light.radius = 96
	_base_light.squash = 0.5
	_base_light.base_energy = 0.12
	_base_light.pulse = 0.12
	_base_light.glow_color = Color("78f4e6")
	add_child(_base_light)

	_build_beam(lens_pos)
	_build_collision()
	_build_crypt_door()
	awakened = _initially_awake()
	_set_blend(1.0 if awakened else 0.0)


func _read_art() -> void:
	var art: Dictionary = DataRegistry.table("sternenauge_art")
	_frame = WindkapProps._vec2_from(art.get("frame"), _frame)
	_origin = WindkapProps._vec2_from(art.get("ground_center"), _origin)
	_lens = WindkapProps._vec2_from(art.get("lens"), _lens)
	_radii = WindkapProps._vec2_from(art.get("ground_radii"), _radii)


func _make_sprite(n: String, tex: Texture2D, frame_idx: int, mat: Material) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.name = n
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2(_frame.x * float(frame_idx), 0.0, _frame.x, _frame.y)
	s.centered = false
	s.offset = -_origin
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.material = mat
	add_child(s)
	return s


func _build_beam(lens_pos: Vector2) -> void:
	_beam_pivot = Node2D.new()
	_beam_pivot.name = "BeamPivot"
	_beam_pivot.position = lens_pos
	_beam_pivot.rotation = BEAM_DIR.angle()
	_beam_pivot.z_index = 6
	add_child(_beam_pivot)
	_beam = ColorRect.new()
	_beam.name = "Beam"
	_beam.size = Vector2(BEAM_LENGTH, BEAM_WIDTH)
	_beam.position = Vector2(4.0, -BEAM_WIDTH * 0.5)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("rect_size", _beam.size)
	_beam_mat.set_shader_parameter("strength", 0.0)
	_beam.material = _beam_mat
	_beam.visible = false
	_beam_pivot.add_child(_beam)


func _build_collision() -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var poly: PackedVector2Array = PackedVector2Array()
	var steps: int = 20
	for i: int in steps:
		var a: float = TAU * float(i) / float(steps)
		poly.append(Vector2(cos(a) * _radii.x, sin(a) * _radii.y))
	var cp: CollisionPolygon2D = CollisionPolygon2D.new()
	cp.polygon = poly
	body.add_child(cp)
	add_child(body)


## The crypt door: a Doorway just in front of the stairs (the plinth's collider ends at the ellipse), and the way back out.
func _build_crypt_door() -> void:
	doorway = Doorway.new()
	doorway.name = "CryptDoor"
	doorway.interior_id = CRYPT
	doorway.label = "KRYPTA BETRETEN"
	doorway.reach_radius = 14.0
	doorway.prompt_height = 40.0
	doorway.position = Vector2(0.0, _radii.y + 2.0)
	add_child(doorway)
	exit_position = global_position + Vector2(0.0, _radii.y + 14.0)
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors != null:
		interiors.register_entrance(CRYPT, self)


func _initially_awake() -> bool:
	var disc: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if disc != null and disc.has_method("is_continent_unlocked") and bool(disc.call("is_continent_unlocked")):
		return true
	var p: Player = SaveGame._local_player(get_tree())
	return p != null and p.quests != null and p.quests.has_flag("atlas_continent_unlocked")


## Called by the map tablet (and later the story scene). Animates when it changes while on screen.
func set_awakened(on: bool) -> void:
	if on == awakened:
		return
	awakened = on
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		_set_blend(1.0 if on else 0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_set_blend, _blend, 1.0 if on else 0.0, AWAKEN_TIME).set_trans(Tween.TRANS_SINE)
	if on:
		_play_awaken_fx()


## Lens world position (for cameras / story scenes).
func lens_global_position() -> Vector2:
	return to_global(_lens - _origin)


func _set_blend(v: float) -> void:
	_blend = clampf(v, 0.0, 1.0)
	if _awake != null:
		_awake.modulate.a = _blend
	if _wild != null:
		_wild.visible = _blend < 1.0
	if _lens_light != null:
		_lens_light.base_energy = lerpf(0.2, 1.6, _blend)
	if _base_light != null:
		_base_light.base_energy = lerpf(0.12, 0.6, _blend)
	if _beam != null:
		_beam.visible = _blend > 0.01


func _play_awaken_fx() -> void:
	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.one_shot = true
	motes.emitting = true
	motes.amount = 40
	motes.lifetime = 2.6
	motes.explosiveness = 0.55
	motes.direction = Vector2(0.0, -1.0)
	motes.spread = 180.0
	motes.gravity = Vector2(0.0, -6.0)
	motes.initial_velocity_min = 10.0
	motes.initial_velocity_max = 34.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.0
	motes.color = Color("d0fff8")
	motes.material = Unlit.material()
	motes.position = _lens - _origin
	motes.z_index = 7
	add_child(motes)
	get_tree().create_timer(3.0).timeout.connect(motes.queue_free)


func _process(delta: float) -> void:
	_time += delta
	var night: float = TimeManager.night_amount()
	var breath: float = 0.86 + 0.14 * sin(_time * 1.9)
	if _glow_wild != null:
		_glow_wild.modulate.a = lerpf(0.25, 0.75, night) * breath * (1.0 - _blend)
	if _glow_awake != null:
		_glow_awake.modulate.a = lerpf(0.6, 1.0, night) * breath * _blend
	if _beam_mat != null and _beam.visible:
		_beam_pivot.rotation = BEAM_DIR.angle() + sin(_time * 0.21) * BEAM_SWEEP
		_beam_mat.set_shader_parameter("time", _time)
		_beam_mat.set_shader_parameter("strength", _blend * lerpf(0.18, 1.0, night))


## 0 = wild, 1 = erwacht (mid-transition values while awakening; steles follow it).
func awake_blend() -> float:
	return _blend
