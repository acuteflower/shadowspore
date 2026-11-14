class_name OldWatermill
extends Interactable
## Riverside weathered watermill (`docs/wiesenbiom_ausbau_konzept.md` Stufe 4.1).
## Initially its wooden paddle wheel (`watermill_wheel.png`, 6 seamless frames) is jammed by tangled driftwood
## & rusted chain (`watermill_jam.png`). Pressing `E -> "VERKEILTES TREIBHOLZ LÖSEN"` asks the host (`MeadowPois`)
## to clear the jam: the driftwood breaks away, the heavy oak wheel begins rotating smoothly in the river current
## with gentle creaking & water droplets, and the mill's sealed cache chest (`LootChests`) opens beside the arched door!

const MILL_TEX: String = "res://assets/props/old_watermill.png"
const MILL_GLOW: String = "res://assets/props/old_watermill_glow.png"
const WHEEL_TEX: String = "res://assets/props/watermill_wheel.png"
const JAM_TEX: String = "res://assets/props/watermill_jam.png"
const UNJAM_WAV: String = "res://assets/audio/meadow_wonders/mill_unjam.wav"
const CREAK_WAV: String = "res://assets/audio/meadow_wonders/mill_creak_loop.wav"

const WHEEL_LOCAL: Vector2 = Vector2(44.0, -30.0) ## axle bearing at (124, 98) relative to foundation anchor (80, 128)
const DOOR_CHEST_LOCAL: Vector2 = Vector2(-24.0, 14.0)

var pois: MeadowPois
var mill_id: String = ""
var mill_name: String = "ALTE WASSERMÜHLE"
var mill_sub: String = "DAS MÜHLRAD DREHT SICH WIEDER"
var chest_tier: String = "rare"
var unjammed: bool = false

var _house: Sprite2D
var _glow: Sprite2D
var _wheel: Sprite2D
var _jam: Sprite2D
var _light: NightLight
var _splash: CPUParticles2D
var _creak: AudioStreamPlayer2D
var _wheel_phase: float = 0.0


func setup(owner_pois: MeadowPois, spec: Dictionary, pos_px: Vector2) -> void:
	pois = owner_pois
	mill_id = String(spec.get("id", ""))
	mill_name = String(spec.get("name", "ALTE WASSERMÜHLE"))
	mill_sub = String(spec.get("sub", "DAS MÜHLRAD DREHT SICH WIEDER"))
	chest_tier = String(spec.get("chest_tier", "rare"))
	position = pos_px.round()


func _ready() -> void:
	add_to_group("flora_glow")
	_build_visuals()
	_build_collider()


func _build_visuals() -> void:
	var house_off: Vector2 = Vector2(0.0, -(128.0 - 72.0)) ## anchor (80, 128) in 160x144
	if ResourceLoader.exists(MILL_TEX):
		_house = Sprite2D.new()
		_house.texture = load(MILL_TEX) as Texture2D
		_house.offset = house_off
		add_child(_house)
	if ResourceLoader.exists(MILL_GLOW):
		_glow = Sprite2D.new()
		_glow.texture = load(MILL_GLOW) as Texture2D
		_glow.offset = house_off
		_glow.material = Unlit.material()
		add_child(_glow)
	if ResourceLoader.exists(WHEEL_TEX):
		_wheel = Sprite2D.new()
		_wheel.texture = load(WHEEL_TEX) as Texture2D
		_wheel.hframes = 6
		_wheel.position = WHEEL_LOCAL
		add_child(_wheel)
	if ResourceLoader.exists(JAM_TEX):
		_jam = Sprite2D.new()
		_jam.texture = load(JAM_TEX) as Texture2D
		_jam.hframes = 2
		_jam.position = WHEEL_LOCAL + Vector2(2.0, 22.0)
		add_child(_jam)

	_splash = CPUParticles2D.new()
	_splash.position = WHEEL_LOCAL + Vector2(6.0, 24.0)
	_splash.amount = 14
	_splash.lifetime = 0.65
	_splash.direction = Vector2(0.35, -1.0)
	_splash.spread = 42.0
	_splash.gravity = Vector2(0.0, 180.0)
	_splash.initial_velocity_min = 24.0
	_splash.initial_velocity_max = 48.0
	_splash.scale_amount_min = 1.0
	_splash.scale_amount_max = 2.0
	_splash.color = Color("9ef8f0")
	_splash.material = Unlit.material()
	add_child(_splash)

	_light = NightLight.new()
	_light.position = Vector2(-6.0, -28.0)
	_light.radius = 68
	_light.base_energy = 0.35
	_light.pulse = 0.12
	_light.glow_color = Color("ffc66d")
	add_child(_light)

	if ResourceLoader.exists(CREAK_WAV):
		_creak = AudioStreamPlayer2D.new()
		_creak.stream = load(CREAK_WAV) as AudioStream
		_creak.bus = "SFX"
		_creak.volume_db = -11.0
		_creak.max_distance = 320.0
		_creak.finished.connect(func() -> void:
			if unjammed and is_inside_tree():
				_creak.play())
		add_child(_creak)

	_apply_state()


func _build_collider() -> void:
	var sb: StaticBody2D = StaticBody2D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(104.0, 34.0)
	shape_node.shape = rect
	shape_node.position = Vector2(-10.0, -16.0)
	sb.add_child(shape_node)
	add_child(sb)


func _apply_state() -> void:
	if _jam != null:
		_jam.frame = 1 if unjammed else 0
	if _splash != null:
		_splash.emitting = unjammed
	if _light != null:
		_light.base_energy = 0.62 if unjammed else 0.28
		_light.radius = 84 if unjammed else 54
	if _creak != null:
		if unjammed and not _creak.playing:
			_creak.play()
		elif not unjammed and _creak.playing:
			_creak.stop()


func set_unjammed_instant(val: bool) -> void:
	unjammed = val
	_apply_state()
	if unjammed:
		var chests: LootChests = LootChests.of(get_tree())
		if chests != null:
			chests.place(mill_id + "_chest", chest_tier, global_position + DOOR_CHEST_LOCAL, false)


func play_unjam_fx() -> void:
	unjammed = true
	_apply_state()
	if ResourceLoader.exists(UNJAM_WAV):
		var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		snd.stream = load(UNJAM_WAV) as AudioStream
		snd.bus = "SFX"
		snd.volume_db = -3.0
		snd.max_distance = 460.0
		snd.finished.connect(snd.queue_free)
		add_child(snd)
		snd.play()
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		chests.appear(mill_id + "_chest", chest_tier, global_position + DOOR_CHEST_LOCAL, true, false, true)


func _process(delta: float) -> void:
	var night: float = TimeManager.night_amount()
	if _glow != null:
		var target_a: float = lerpf(0.32 if unjammed else 0.10, 0.96 if unjammed else 0.45, night)
		_glow.modulate.a = target_a
	if unjammed and _wheel != null:
		_wheel_phase = fposmod(_wheel_phase + delta * 5.4, 6.0)
		_wheel.frame = int(_wheel_phase)
	elif _wheel != null:
		# Subtle strained twitch when jammed
		_wheel.frame = 0


func is_interactable() -> bool:
	return not unjammed


func prompt() -> String:
	return "" if unjammed else "VERKEILTES TREIBHOLZ LÖSEN"


func reach_distance(from: Vector2) -> float:
	var target_pt: Vector2 = global_position + WHEEL_LOCAL + Vector2(-12.0, 22.0)
	return maxf(0.0, from.distance_to(target_pt) - 26.0)


func prompt_position() -> Vector2:
	return WHEEL_LOCAL + Vector2(0.0, -34.0)


func interact(player: Player) -> void:
	if unjammed or player == null or player.is_busy() or pois == null:
		return
	var aim: Vector2 = (global_position + WHEEL_LOCAL) - player.global_position
	var dir: Vector2 = aim.normalized() if aim.length_squared() > 1.0 else Vector2.RIGHT
	player.begin_pull(dir, func() -> void:
		if is_instance_valid(pois):
			pois.request_unjam_mill(mill_id))
