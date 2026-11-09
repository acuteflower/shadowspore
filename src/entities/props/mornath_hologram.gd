class_name MornathHologram
extends Interactable
## The glitched hologram of Mornath in the middle of the boss arena. It is there for the local player once the quest `mornath` is finished (and after a wipe in the
## fight, to try again): E calls the boss back (`ArenaStory.hologram_use` -> `WorldLevel.request_arena_boss`), no quest needed. The picture is the real `SkyCleaverRig`
## (hovering, slowly turning) in a SubViewport, shown through `mornath_hologram.gdshader` (scanlines, slipping rows, a magenta and a teal ghost, written from the feet
## up); on the floor a ring of broken runes projects it, a thin cone of light rises, glitch squares drift up. Cosmetic and local: every peer sees its own.

const SHADER: Shader = preload("res://assets/shaders/mornath_hologram.gdshader")
const VIEW: Vector2i = Vector2i(220, 170)
const RIG_AT: Vector2 = Vector2(99.0, 107.0) ## where the rig's middle is in the viewport
const SPRITE_AT: Vector2 = Vector2(0.0, -50.0) ## the viewport's middle relative to the node (its feet): the bird floats above the ring
const TEAL: Color = Color("6fe8ff")
const MAGENTA: Color = Color("f35cf3")
const SOUNDS: Dictionary = {
	"appear": preload("res://assets/audio/boss_intro/shimmer.wav"),
	"use": preload("res://assets/audio/boss_intro/riser.wav"),
	"crackle": preload("res://assets/audio/boss_intro/crackle.wav"),
}

var story: ArenaStory
var active: bool = false

var _viewport: SubViewport
var _rig: SkyCleaverRig
var _sprite: Sprite2D
var _base: Node2D
var _motes: CPUParticles2D
var _light: NightLight
var _material: ShaderMaterial
var _appear: float = 0.0
var _glitch: float = 0.0
var _clock: float = 0.0
var _burst: float = 0.0 ## seconds of the "touched" glitch that are left
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
	var holder: Node2D = Node2D.new()
	holder.name = "Mornath"
	holder.position = RIG_AT
	_viewport.add_child(holder)
	_rig = SkyCleaverRig.new()
	_rig.name = "Rig"
	var body: Node2D = Node2D.new()
	body.name = "Body"
	_rig.add_child(body)
	var glow: Node2D = Node2D.new() ## drawn with the normal blend here: the additive one would leave the transparent picture empty
	glow.name = "Glow"
	glow.material = Unlit.material()
	_rig.add_child(glow)
	holder.add_child(_rig)
	_rig.tick_hz = 30.0
	_rig.ground_drop = 0.0
	_rig.start_pose(SkyCleaverRig.Pose.HOVER, 600.0)

	_base = Node2D.new()
	_base.material = _additive()
	_base.z_index = -1
	_base.draw.connect(_draw_base)
	add_child(_base)
	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = SPRITE_AT
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_sprite.material = _material
	add_child(_sprite)
	_motes = CPUParticles2D.new() ## square glitch specks rising out of the ring
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
	_motes.scale_amount_min = 1.0
	_motes.scale_amount_max = 1.0
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


## The map (M) shows his own marker while the hologram stands (`MapWindow._live_markers`, style `mornath` in data/map_markers.json): no `actor_position`, only a mark.
func map_marker() -> Dictionary:
	if not active or _appear < 0.5:
		return {}
	return {"id": "mornath", "position": global_position}


## `quest_actors` members answer this for quest steps with an `actor`; the hologram is nobody's goal.
func actor_position(_id: String) -> Vector2:
	return Vector2.INF


## The story turns it on (the quest is done, or a wipe left the arena empty) and off (the boss is there).
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_apply_visibility()
	if on:
		_play("appear", -10.0, 1.0)
		_burst = 0.5 ## it comes in with a tear


func prompt() -> String:
	return "MORNATH RUFEN" if active and _appear > 0.92 and _burst <= 0.0 else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 20.0


func prompt_position() -> Vector2:
	return Vector2(0, -50)


func interact(player: Player) -> void:
	if story != null:
		story.hologram_use(player)


## It breaks up (the call): a long tear, a riser, then it is gone when the boss comes.
func touched() -> void:
	_burst = 1.6
	_play("use", -6.0, 1.0)
	_play("crackle", -9.0, 0.9)


func _play(sound: String, volume: float, pitch: float) -> void:
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
	# the idle glitch: now and then it tears for a moment
	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		_glitch_timer = randf_range(2.2, 6.0)
		_burst = maxf(_burst, randf_range(0.12, 0.35))
	_burst = maxf(0.0, _burst - delta)
	_glitch = clampf(_burst * 1.5, 0.0, 1.0) if _burst > 0.0 else 0.0
	# the bird turns slowly towards the south (the camera) and back, wings beating
	var heading: float = PI * 0.5 + sin(_clock * 0.45) * 0.75
	_rig.update_rig(delta, Vector2.ZERO, heading, 0.0)
	_material.set_shader_parameter("clock", _clock)
	_material.set_shader_parameter("appear", ease(_appear, 0.8))
	_material.set_shader_parameter("glitch", _glitch)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_light.base_energy = 0.55 * _appear * (0.8 + 0.2 * sin(_clock * 3.1)) * (1.0 - 0.6 * _glitch)
	_sprite.position = SPRITE_AT + Vector2(0.0, roundf(sin(_clock * 1.3) * 2.0)) ## it bobs in whole pixels
	_base.queue_redraw()


## The ring on the floor: three flattened ellipses of broken arcs and ticks, turning slowly against each other, a faint cone of light up to the bird.
func _draw_base() -> void:
	var a: float = _appear
	if a <= 0.0:
		return
	var squash: float = 0.5
	for ring: int in 3:
		var radius: float = 26.0 + 11.0 * float(ring)
		var turn: float = _clock * (0.35 - 0.2 * float(ring)) * (1.0 if ring % 2 == 0 else -1.0)
		var segments: int = 10 + ring * 4
		for k: int in segments:
			var from: float = turn + TAU * float(k) / float(segments)
			var length: float = TAU / float(segments) * (0.55 if (k * 7 + ring * 3) % 5 != 0 else 0.2)
			var gate: float = fmod(_clock * 0.5 + float(k) * 0.37 + float(ring), 3.0) ## some segments are missing for a moment
			if gate < 0.25 or (_glitch > 0.3 and (k + int(_clock * 12.0)) % 3 == 0):
				continue
			var points: PackedVector2Array = PackedVector2Array()
			for s: int in 7:
				var ang: float = from + length * float(s) / 6.0
				points.append(Vector2(roundf(cos(ang) * radius), roundf(sin(ang) * radius * squash)))
			var color: Color = (TEAL if ring != 1 else MAGENTA)
			color.a = (0.55 - 0.1 * float(ring)) * a
			_base.draw_polyline(points, color, 1.0)
	# runes: small ticks between the rings
	for k: int in 12:
		var ang: float = _clock * 0.2 + TAU * float(k) / 12.0
		var c: float = cos(ang)
		var s_: float = sin(ang)
		var p0: Vector2 = Vector2(roundf(c * 33.0), roundf(s_ * 33.0 * squash))
		var p1: Vector2 = Vector2(roundf(c * 37.0), roundf(s_ * 37.0 * squash))
		_base.draw_line(p0, p1, Color(TEAL.r, TEAL.g, TEAL.b, 0.5 * a), 1.0)
	# the cone of light up to the bird, dithered
	for row: int in 28:
		var y: float = -2.0 - float(row) * 2.0
		var half: float = 22.0 * (1.0 - float(row) / 30.0)
		var strength: float = (1.0 - float(row) / 28.0) * 0.16 * a
		for edge: int in 2:
			var xe: float = half if edge == 0 else -half
			if (row + edge) % 2 == 0:
				_base.draw_rect(Rect2(Vector2(roundf(xe), roundf(y)), Vector2(1, 1)), Color(TEAL.r, TEAL.g, TEAL.b, strength * 3.0))
		if row % 2 == 0:
			_base.draw_rect(Rect2(Vector2(roundf(-half * 0.5), roundf(y)), Vector2(roundf(half), 1)), Color(TEAL.r, TEAL.g, TEAL.b, strength * 0.6))
