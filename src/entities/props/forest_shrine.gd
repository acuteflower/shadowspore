class_name ForestShrine
extends Interactable
## Hidden ancient woodland shrine (`docs/wiesenbiom_ausbau_konzept.md` Stufe 2.1) nestled in a sunlit
## fern glade beneath the giant `ancient_fir` dome of *Der Tiefe Urforst*.
## Pressing `E -> "WALDSCHREIN EHRSAM BERÜHREN"` asks the host (`MeadowLandmarks`) to awaken the shrine:
## turquoise-gold runes flare, a warm healing chord plays, nearby players receive a woodland blessing
## (heal + XP), and a mossy `Wurzelkiste` (`LootChests`) rises out of the forest roots beside it.

const TEX_PATH: String = "res://assets/props/forest_shrine.png"
const GLOW_PATH: String = "res://assets/props/forest_shrine_glow.png"
const FRAME_W: int = 64
const FRAME_H: int = 72
const FEET_Y: float = 64.0

var landmarks: MeadowLandmarks
var shrine_id: String = ""
var variant: int = 0 ## 0..2
var tier_name: String = "common"
var blessed: bool = false

var _body: Sprite2D
var _glow: Sprite2D
var _light: NightLight
var _shaft: SunbeamShaft


func setup(owner_landmarks: MeadowLandmarks, id_val: String, pos_px: Vector2, var_idx: int, chest_tier: String = "common") -> void:
	landmarks = owner_landmarks
	shrine_id = id_val
	position = pos_px.round()
	variant = clampi(var_idx, 0, 2)
	tier_name = chest_tier


func _ready() -> void:
	add_to_group("flora_glow")
	_build_visuals()
	_build_collider()


func _build_visuals() -> void:
	var off: Vector2 = Vector2(0.0, -(FEET_Y - float(FRAME_H) * 0.5))
	if ResourceLoader.exists(TEX_PATH):
		_body = Sprite2D.new()
		_body.texture = load(TEX_PATH) as Texture2D
		_body.hframes = 3
		_body.vframes = 2
		_body.offset = off
		add_child(_body)
	if ResourceLoader.exists(GLOW_PATH):
		_glow = Sprite2D.new()
		_glow.texture = load(GLOW_PATH) as Texture2D
		_glow.hframes = 3
		_glow.vframes = 2
		_glow.offset = off
		_glow.material = Unlit.material()
		add_child(_glow)
	_light = NightLight.new()
	_light.position = Vector2(0.0, -18.0)
	_light.radius = 48
	_light.base_energy = 0.28
	_light.pulse = 0.16
	_light.glow_color = Color("3cc0c6")
	add_child(_light)

	_shaft = SunbeamShaft.new()
	_shaft.setup(Vector2(0.0, 2.0), 1.12, hash(shrine_id))
	add_child(_shaft)

	_apply_visual()


func _build_collider() -> void:
	var sb: StaticBody2D = StaticBody2D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(26.0, 12.0)
	shape_node.shape = rect
	shape_node.position = Vector2(0.0, -4.0)
	sb.add_child(shape_node)
	add_child(sb)


func _apply_visual() -> void:
	var row: int = 1 if blessed else 0
	var frame_idx: int = row * 3 + variant
	if _body != null:
		_body.frame = frame_idx
	if _glow != null:
		_glow.frame = frame_idx
		_glow.modulate = Color(1.0, 1.0, 1.0, 0.96 if blessed else 0.48)
	if _light != null:
		_light.radius = 74 if blessed else 46
		_light.base_energy = 0.68 if blessed else 0.26
		_light.glow_color = Color("78f4e6") if blessed else Color("2a8c94")


func set_blessed_instant(on: bool = true) -> void:
	blessed = on
	_apply_visual()
	if blessed:
		_ensure_chest(false)


func play_bless_fx() -> void:
	blessed = true
	_apply_visual()
	set_focused(false)
	_ensure_chest(true)
	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.one_shot = true
	motes.emitting = true
	motes.amount = 26
	motes.lifetime = 2.0
	motes.explosiveness = 0.65
	motes.direction = Vector2.UP
	motes.spread = 65.0
	motes.gravity = Vector2(0.0, -14.0)
	motes.initial_velocity_min = 14.0
	motes.initial_velocity_max = 36.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.2
	motes.color = Color("78f4e6")
	motes.material = Unlit.material()
	motes.position = Vector2(0.0, -20.0)
	motes.z_index = 6
	add_child(motes)
	get_tree().create_timer(2.4).timeout.connect(motes.queue_free)
	if ResourceLoader.exists("res://assets/audio/vistas/chime.wav"):
		var audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		audio.stream = load("res://assets/audio/vistas/chime.wav") as AudioStream
		audio.volume_db = -4.5
		audio.pitch_scale = 1.12
		audio.max_distance = 260.0
		audio.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		add_child(audio)
		audio.finished.connect(audio.queue_free)
		audio.play()


func _ensure_chest(arrive: bool) -> void:
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		var chest_pos: Vector2 = global_position + Vector2(26.0 if variant % 2 == 0 else -26.0, 10.0)
		chests.appear(shrine_id, tier_name, chest_pos, arrive, variant % 2 == 1, true)


func prompt_position() -> Vector2:
	return Vector2(0.0, -56.0)


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, global_position.distance_to(from) - 18.0)


func prompt() -> String:
	if blessed or InputManager.ui_blocking:
		return ""
	return "WALDSCHREIN EHRSAM BERÜHREN"


func interact(player: Player) -> void:
	if blessed or player == null or not player.is_multiplayer_authority():
		return
	if landmarks != null:
		landmarks.request_bless_shrine(shrine_id)
