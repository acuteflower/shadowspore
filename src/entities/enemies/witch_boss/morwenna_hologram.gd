class_name MorwennaHologram
extends Interactable
## The glitched hologram of Morwenna in front of the Rabenbaum, once she has been released (docs/enemies/boss_mora.md): E calls her back for another fight
## (`WitchArena.request_rematch`). Built like `MornathHologram` so the two read as one kind of thing: the same projector ring on the floor
## (`MornathHologram.draw_projector`, teal with a witch-green accent instead of magenta), the same hologram shader over a SubViewport, in which her real
## picture (`WitchBody`, idle, slowly turning) stands. The map shows its own marker while it stands (`map_marker`, style `morwenna` in data/map_markers.json).
## Cosmetic and local: every peer sees its own; the arena turns it on and off.

const SHADER: Shader = preload("res://assets/shaders/mornath_hologram.gdshader")
const VIEW: Vector2i = Vector2i(120, 108)
const FEET_AT: Vector2 = Vector2(60.0, 96.0) ## where her feet stand in the viewport
const SPRITE_AT: Vector2 = Vector2(0.0, -46.0)
const TEAL: Color = Color("6fe8ff")
const GREEN: Color = Color("a8ff6a")
const SOUNDS: Dictionary = {
	"appear": preload("res://assets/audio/boss_intro/shimmer.wav"),
	"use": preload("res://assets/audio/boss_intro/riser.wav"),
	"crackle": preload("res://assets/audio/boss_intro/crackle.wav"),
}

var arena: WitchArena
var active: bool = false
var _viewport: SubViewport
var _body: WitchBody
var _sprite: Sprite2D
var _base: Node2D
var _motes: CPUParticles2D
var _light: NightLight
var _material: ShaderMaterial
var _appear: float = 0.0
var _glitch: float = 0.0
var _clock: float = 0.0
var _burst: float = 0.0
var _glitch_timer: float = 3.0


func _ready() -> void:
	add_to_group("quest_actors") ## so the map finds `map_marker`
	_viewport = SubViewport.new()
	_viewport.size = VIEW
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_body = WitchBody.new()
	_body.name = "Morwenna"
	_body.phantom = true ## no shadow, scanlines, green fires: right for a projection
	_body.position = FEET_AT
	_viewport.add_child(_body)
	_base = Node2D.new()
	_base.material = _additive()
	_base.z_index = -1
	_base.draw.connect(func() -> void: MornathHologram.draw_projector(_base, _clock, _appear, _glitch, TEAL, GREEN))
	add_child(_base)
	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = SPRITE_AT
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("tint_b", Color(GREEN.r, GREEN.g, GREEN.b, 1.0)) ## her ghost is witch green where his is magenta
	_sprite.material = _material
	add_child(_sprite)
	_motes = CPUParticles2D.new()
	_motes.position = Vector2(0, -2)
	_motes.amount = 16
	_motes.lifetime = 2.6
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 30.0
	_motes.direction = Vector2(0, -1)
	_motes.spread = 12.0
	_motes.initial_velocity_min = 8.0
	_motes.initial_velocity_max = 22.0
	_motes.gravity = Vector2.ZERO
	_motes.color = TEAL
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	_motes.color_ramp = fade
	_motes.material = Unlit.material()
	_motes.emitting = false
	add_child(_motes)
	_light = NightLight.new()
	_light.position = Vector2(0, -8)
	_light.radius = 92
	_light.base_energy = 0.0
	_light.glow_color = Color("63b9ff")
	add_child(_light)
	_apply_visibility()


func _additive() -> CanvasItemMaterial:
	var material: CanvasItemMaterial = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material


func map_marker() -> Dictionary:
	if not active or _appear < 0.5:
		return {}
	return {"id": "morwenna", "position": global_position}


func actor_position(_id: String) -> Vector2:
	return Vector2.INF


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_apply_visibility()
	if on:
		_play("appear", -10.0, 1.0)
		_burst = 0.5


func prompt() -> String:
	return "MORWENNA RUFEN" if active and _appear > 0.92 and _burst <= 0.0 else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 20.0


func prompt_position() -> Vector2:
	return Vector2(0, -60)


func interact(_player: Player) -> void:
	if arena != null:
		arena.request_rematch()


## It breaks up (the call): a long tear, a riser; it is gone when she falls out of the crown.
func touched() -> void:
	_burst = 1.6
	_play("use", -6.0, 1.0)
	_play("crackle", -9.0, 0.9)


func _play(sound: String, volume: float, pitch: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = SOUNDS[sound] as AudioStream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.max_distance = 420.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _apply_visibility() -> void:
	var shown: bool = active or _appear > 0.0
	visible = shown
	set_process(shown)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	_motes.emitting = shown and _appear > 0.3


func _process(delta: float) -> void:
	var was: bool = visible
	_clock += delta
	_appear = move_toward(_appear, 1.0 if active else 0.0, delta * (0.55 if active else 1.4))
	if (active or _appear > 0.0) != was:
		_apply_visibility()
	elif not active and _appear <= 0.0:
		return
	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		_glitch_timer = randf_range(2.2, 6.0)
		_burst = maxf(_burst, randf_range(0.12, 0.35))
	_burst = maxf(0.0, _burst - delta)
	_glitch = clampf(_burst * 1.5, 0.0, 1.0) if _burst > 0.0 else 0.0
	_body.show_pose("idle", _clock, PI * 0.5 + sin(_clock * 0.45) * 0.75, true) ## she turns slowly towards the camera and back
	_material.set_shader_parameter("clock", _clock)
	_material.set_shader_parameter("appear", ease(_appear, 0.8))
	_material.set_shader_parameter("glitch", _glitch)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_light.base_energy = 0.55 * _appear * (0.8 + 0.2 * sin(_clock * 3.1)) * (1.0 - 0.6 * _glitch)
	_sprite.position = SPRITE_AT + Vector2(0.0, roundf(sin(_clock * 1.3) * 2.0))
	_base.queue_redraw()
