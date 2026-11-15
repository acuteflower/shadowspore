class_name AurelithHologram
extends Interactable
## Glitched solar-turquoise & zenith-gold hologram of `Aurelith, Herz des Sonnenquarzes` above the central
## sun-compass seal of the Singing Basin once he has been defeated (`AurelithArena.released == true`).
##
## Built on the shared boss-hologram architecture (`MornathHologram` / `MorwennaHologram`):
## - Renders the real `AurelithRig` inside a transparent `SubViewport` through `mornath_hologram.gdshader`.
## - Projects the rotating floor rune ring via `MornathHologram.draw_projector`.
## - Exposes `map_marker() -> {"id": "aurelith", "position": global_position}` for `MapWindow` (`data/map_markers.json`).
## - Pressing `E` (`"AURELITH RUFEN"`) calls `arena.request_rematch()` to re-summon the colossus anytime.

const SHADER: Shader = preload("res://assets/shaders/mornath_hologram.gdshader")
const VIEW: Vector2i = Vector2i(216, 188)
const RIG_AT: Vector2 = Vector2(108.0, 166.0)
const SPRITE_AT: Vector2 = Vector2(0.0, -72.0)
const TURQUOISE: Color = Color("78f4e6")
const GOLD: Color = Color("ffd86b")
const SOUNDS: Dictionary = {
	"appear": preload("res://assets/audio/boss_intro/shimmer.wav"),
	"use": preload("res://assets/audio/boss_intro/riser.wav"),
	"crackle": preload("res://assets/audio/boss_intro/crackle.wav"),
}

var arena: AurelithArena
var active: bool = false

var _viewport: SubViewport
var _rig: AurelithRig
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
	add_to_group("quest_actors") ## discovered by `MapWindow._live_markers`
	_viewport = SubViewport.new()
	_viewport.size = VIEW
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	var holder: Node2D = Node2D.new()
	holder.name = "AurelithHolder"
	holder.position = RIG_AT
	_viewport.add_child(holder)

	_rig = AurelithRig.new()
	_rig.name = "Rig"
	var body: Node2D = Node2D.new()
	body.name = "Body"
	_rig.add_child(body)
	var glow: Node2D = Node2D.new() ## normal blend inside transparent SubViewport so glow writes alpha
	glow.name = "Glow"
	glow.material = Unlit.material()
	_rig.add_child(glow)
	holder.add_child(_rig)
	_rig.prism_release = 0.65
	_rig.start_pose(AurelithRig.Pose.IDLE, 1.0)

	_base = Node2D.new()
	_base.material = _additive()
	_base.z_index = -1
	_base.draw.connect(func() -> void: MornathHologram.draw_projector(_base, _clock, _appear, _glitch, TURQUOISE, GOLD))
	add_child(_base)

	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = SPRITE_AT
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("tint_a", Color(TURQUOISE.r, TURQUOISE.g, TURQUOISE.b, 1.0))
	_material.set_shader_parameter("tint_b", Color(GOLD.r, GOLD.g, GOLD.b, 1.0))
	_sprite.material = _material
	add_child(_sprite)

	_motes = CPUParticles2D.new()
	_motes.position = Vector2(0, -4)
	_motes.amount = 18
	_motes.lifetime = 2.6
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 34.0
	_motes.direction = Vector2(0, -1)
	_motes.spread = 14.0
	_motes.initial_velocity_min = 9.0
	_motes.initial_velocity_max = 24.0
	_motes.gravity = Vector2.ZERO
	_motes.scale_amount_min = 1.0
	_motes.scale_amount_max = 2.0
	_motes.color = TURQUOISE
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	_motes.color_ramp = fade
	_motes.material = Unlit.material()
	_motes.emitting = false
	add_child(_motes)

	_light = NightLight.new()
	_light.position = Vector2(0, -12)
	_light.radius = 104
	_light.squash = 0.72
	_light.base_energy = 0.0
	_light.glow_color = TURQUOISE
	add_child(_light)

	_apply_visibility()


func _additive() -> CanvasItemMaterial:
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


func map_marker() -> Dictionary:
	if not active or _appear < 0.5:
		return {}
	return {"id": "aurelith", "position": global_position}


func actor_position(_id: String) -> Vector2:
	return Vector2.INF


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_apply_visibility()
	if on:
		_play("appear", -9.0, 0.94)
		_burst = 0.5


func prompt() -> String:
	return "AURELITH RUFEN" if active and _appear > 0.92 and _burst <= 0.0 else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 24.0


func prompt_position() -> Vector2:
	return Vector2(0, -76)


func interact(_player: Player) -> void:
	if arena != null:
		arena.request_rematch()


func touched() -> void:
	_burst = 1.6
	_play("use", -6.0, 0.92)
	_play("crackle", -9.0, 0.88)


func _play(sound: String, volume: float, pitch: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = SOUNDS[sound] as AudioStream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.max_distance = 460.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _apply_visibility() -> void:
	var shown: bool = active or _appear > 0.0
	visible = shown
	set_process(shown)
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if _motes != null:
		_motes.emitting = shown and _appear > 0.3


func _process(delta: float) -> void:
	var was: bool = visible
	_clock += delta
	_appear = move_toward(_appear, 1.0 if active else 0.0, delta * (0.58 if active else 1.4))
	if (active or _appear > 0.0) != was:
		_apply_visibility()
	elif not active and _appear <= 0.0:
		return

	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		_glitch_timer = randf_range(2.2, 5.8)
		_burst = maxf(_burst, randf_range(0.12, 0.34))
	_burst = maxf(0.0, _burst - delta)
	_glitch = clampf(_burst * 1.5, 0.0, 1.0) if _burst > 0.0 else 0.0

	var heading_a: float = PI * 0.5 + sin(_clock * 0.42) * 0.68
	_rig.update_rig(delta, Vector2.ZERO, heading_a)
	_material.set_shader_parameter("clock", _clock)
	_material.set_shader_parameter("appear", ease(_appear, 0.8))
	_material.set_shader_parameter("glitch", _glitch)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_light.base_energy = 0.60 * _appear * (0.82 + 0.18 * sin(_clock * 3.1)) * (1.0 - 0.6 * _glitch)
	_sprite.position = SPRITE_AT + Vector2(0.0, roundf(sin(_clock * 1.25) * 2.0))
	_base.queue_redraw()
