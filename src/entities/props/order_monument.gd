class_name OrderMonument
extends Interactable
## Traces of the Red Order (`docs/wiesenbiom_ausbau_konzept.md` Stufe 3):
##  - `"watchtower"` (`order_watchtower.png` `256x144`, `2x1`, anchor `(64, 130)`): half-collapsed cliffside bastion
##  - `"patrol_camp"` (`order_patrol_camp.png` `192x64`, `2x1`, anchor `(48, 52)` + swaying `order_banner.png` `32x64` via `sway_rows.gdshader`)
##  - `"boundary_stone"` (`order_boundary_stone.png` `144x56`, `3x1`, anchor `(24, 48)`): ancient border stele
## Pressing `E` reads the weathered inscription / patrol journal (`SpeechBox`), triggers a warm crimson-gold rune answer,
## sets `"found_order_trace"` on the reader's `QuestComponent` (unlocking Valdric's town dialogue lines), and notifies
## `MeadowPois` on the host for first-time discovery XP & local map fog reveal.

const WATCHTOWER_TEX: String = "res://assets/props/order_watchtower.png"
const WATCHTOWER_GLOW: String = "res://assets/props/order_watchtower_glow.png"
const CAMP_TEX: String = "res://assets/props/order_patrol_camp.png"
const CAMP_GLOW: String = "res://assets/props/order_patrol_camp_glow.png"
const BANNER_TEX: String = "res://assets/props/order_banner.png"
const STONE_TEX: String = "res://assets/props/order_boundary_stone.png"
const STONE_GLOW: String = "res://assets/props/order_boundary_stone_glow.png"
const SWAY_SHADER: Shader = preload("res://assets/shaders/sway_rows.gdshader")
const ORDER_AUDIO: String = "res://assets/audio/meadow_wonders/order_stone.wav"

var pois: MeadowPois
var poi_id: String = ""
var monument_kind: String = "boundary_stone"
var variant: int = 0
var speaker_label: String = "STEININSCHRIFT"
var inscription_text: String = ""
var ellie_thought: String = ""
var banner_offset: Vector2 = Vector2(22.0, -4.0)
var discovered: bool = false

var _body: Sprite2D
var _glow: Sprite2D
var _banner: Sprite2D
var _banner_mat: ShaderMaterial
var _light: NightLight
var _time: float = 0.0
var _pulse: float = 99.0


func setup(owner_pois: MeadowPois, kind_name: String, spec: Dictionary, pos_px: Vector2) -> void:
	pois = owner_pois
	monument_kind = kind_name
	poi_id = String(spec.get("id", ""))
	position = pos_px.round()
	variant = int(spec.get("variant", 0))
	speaker_label = String(spec.get("speaker", "STEININSCHRIFT"))
	inscription_text = String(spec.get("text", ""))
	ellie_thought = String(spec.get("thought", ""))
	if spec.has("banner_offset"):
		var bo: Array = spec.banner_offset as Array
		banner_offset = Vector2(float(bo[0]), float(bo[1]))


func _ready() -> void:
	add_to_group("flora_glow")
	_time = fposmod(position.x * 0.017 + position.y * 0.011, 10.0)
	_build_visuals()
	_build_collider()


func _build_visuals() -> void:
	var tex_path: String = STONE_TEX
	var glow_path: String = STONE_GLOW
	var cols: int = 3
	var frame_size: Vector2 = Vector2(48.0, 56.0)
	var feet_y: float = 48.0
	var light_pos: Vector2 = Vector2(0.0, -28.0)
	var light_rad: int = 28
	var light_energy: float = 0.28

	if monument_kind == "watchtower":
		tex_path = WATCHTOWER_TEX
		glow_path = WATCHTOWER_GLOW
		cols = 2
		frame_size = Vector2(128.0, 144.0)
		feet_y = 130.0
		light_pos = Vector2(6.0, -42.0)
		light_rad = 64
		light_energy = 0.48
	elif monument_kind == "patrol_camp":
		tex_path = CAMP_TEX
		glow_path = CAMP_GLOW
		cols = 2
		frame_size = Vector2(96.0, 64.0)
		feet_y = 52.0
		light_pos = Vector2(-10.0, -20.0)
		light_rad = 38
		light_energy = 0.32

	var off: Vector2 = Vector2(0.0, -(feet_y - frame_size.y * 0.5))
	if ResourceLoader.exists(tex_path):
		_body = Sprite2D.new()
		_body.texture = load(tex_path) as Texture2D
		_body.hframes = cols
		_body.frame = clampi(variant, 0, cols - 1)
		_body.offset = off
		add_child(_body)
	if ResourceLoader.exists(glow_path):
		_glow = Sprite2D.new()
		_glow.texture = load(glow_path) as Texture2D
		_glow.hframes = cols
		_glow.frame = clampi(variant, 0, cols - 1)
		_glow.offset = off
		_glow.material = Unlit.material()
		add_child(_glow)

	if monument_kind == "patrol_camp" and ResourceLoader.exists(BANNER_TEX):
		_banner = Sprite2D.new()
		_banner.texture = load(BANNER_TEX) as Texture2D
		_banner.position = banner_offset
		_banner.offset = Vector2(0.0, -(58.0 - 32.0)) ## anchor at pole foot (16, 58) inside 32x64
		_banner_mat = ShaderMaterial.new()
		_banner_mat.shader = SWAY_SHADER
		_banner_mat.set_shader_parameter("pivot_row", 8.0)
		_banner_mat.set_shader_parameter("dir", 1.0)
		_banner_mat.set_shader_parameter("amount", 3.2)
		_banner_mat.set_shader_parameter("flutter", 0.55)
		_banner_mat.set_shader_parameter("speed", 2.6)
		_banner_mat.set_shader_parameter("cell_w", 16.0)
		_banner.material = _banner_mat
		add_child(_banner)

	_light = NightLight.new()
	_light.position = light_pos
	_light.radius = light_rad
	_light.base_energy = light_energy
	_light.pulse = 0.14
	_light.glow_color = Color("ff8e62") if monument_kind == "watchtower" else Color("e85d75")
	add_child(_light)


func _build_collider() -> void:
	var sb: StaticBody2D = StaticBody2D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	if monument_kind == "watchtower":
		rect.size = Vector2(78.0, 26.0)
		shape_node.position = Vector2(0.0, -12.0)
	elif monument_kind == "patrol_camp":
		rect.size = Vector2(44.0, 14.0)
		shape_node.position = Vector2(-6.0, -5.0)
	else:
		rect.size = Vector2(20.0, 8.0)
		shape_node.position = Vector2(0.0, -3.0)
	shape_node.shape = rect
	sb.add_child(shape_node)
	add_child(sb)


func _process(delta: float) -> void:
	_time += delta
	_pulse += delta
	var night: float = TimeManager.night_amount()
	var answer: float = clampf(1.0 - _pulse / 2.6, 0.0, 1.0)
	if _glow != null:
		var base_a: float = lerpf(0.28 if discovered else 0.14, 0.92 if discovered else 0.68, night)
		_glow.modulate.a = clampf(base_a * (0.86 + 0.14 * sin(_time * 1.9)) + answer * 0.75, 0.0, 1.0)
	if _light != null:
		var base_e: float = 0.48 if monument_kind == "watchtower" else (0.32 if monument_kind == "patrol_camp" else 0.24)
		_light.base_energy = base_e * (1.18 if discovered else 0.85) + answer * 0.45
	if _banner_mat != null:
		var w: Vector2 = WorldWind.sample(global_position)
		var clk: float = WorldWind.current.clock if WorldWind.current != null else _time
		_banner_mat.set_shader_parameter("wind", clampf(w.x, -1.2, 1.2))
		_banner_mat.set_shader_parameter("time", clk)


func prompt() -> String:
	match monument_kind:
		"watchtower":
			return "ORDENSINSCHRIFT LESEN"
		"patrol_camp":
			return "ROSTIGES ORDENSSCHWERT UNTERSUCHEN"
		_:
			return "GRENZSTEIN LESEN"


func reach_distance(from: Vector2) -> float:
	var pad: float = 42.0 if monument_kind == "watchtower" else (24.0 if monument_kind == "patrol_camp" else 14.0)
	return maxf(0.0, from.distance_to(global_position) - pad)


func prompt_position() -> Vector2:
	match monument_kind:
		"watchtower":
			return Vector2(0.0, -96.0)
		"patrol_camp":
			return Vector2(0.0, -48.0)
		_:
			return Vector2(0.0, -46.0)


func interact(player: Player) -> void:
	if player == null or player.is_busy():
		return
	_pulse = 0.0
	if ResourceLoader.exists(ORDER_AUDIO):
		var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		snd.stream = load(ORDER_AUDIO) as AudioStream
		snd.bus = "SFX"
		snd.volume_db = -5.0
		snd.max_distance = 420.0
		snd.finished.connect(snd.queue_free)
		add_child(snd)
		snd.play()
	if player.quests != null and not player.quests.has_flag("found_order_trace"):
		player.quests.set_flag("found_order_trace")
	if pois != null:
		pois.request_discover_order(poi_id)
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null and inscription_text != "":
		box.skip_all()
		_play_inscription(box)


func _play_inscription(box: SpeechBox) -> void:
	await box.speak(speaker_label, inscription_text, 3.2)
	if is_instance_valid(box) and ellie_thought != "":
		await box.speak("ELLIE", ellie_thought, 2.8)
