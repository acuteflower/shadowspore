class_name WaystoneStatue
extends Interactable
## A waystone: a goddess of pale stone on a stepped plinth, cracked, overgrown and with dark crystals growing out of her (art `py -3 tools/art_waystone.py`,
## docs/waystones.md). E wakes her: the crystals light up one after the other, the light runs out of them over the stone, the cracks mend, the ivy and the roots
## wither ahead of it, the pillar of light rises, a ring of force runs over the ground. The state (`awake`) is the world's and shared (`Waystones`), the
## animation runs on every peer from `awaken()`; the one who pressed E also gets the camera scene (`WaystoneScene`).
## Body = `waystone_awaken.gdshader` (dormant sheet + awakened sheet + wave map), emissive layer = `waystone_glow.gdshader` (unlit).

signal awakened

const DIR: String = "res://assets/props/waystone/"
const SHADER_BODY: Shader = preload("res://assets/shaders/waystone_awaken.gdshader")
const SHADER_GLOW: Shader = preload("res://assets/shaders/waystone_glow.gdshader")
const SHADER_BEAM: Shader = preload("res://assets/shaders/waystone_beam.gdshader")
const FRAME: Vector2 = Vector2(104, 112)
const GROUND_ROW: float = 92.0
const DISCOVER_RANGE: float = 150.0 ## first time she comes this close to any statue she says something (dialogue `waystone_discover`, flag `waystone_seen`)
const LIGHT_UP: float = 1.3 ## seconds of flickering before the first crystal catches
const WAVE_TIME: float = 3.5 ## seconds the light takes to run over the whole statue
const FLASH_AT: float = LIGHT_UP + WAVE_TIME ## the bloom
const CHIMES: Array[String] = ["chime_a", "chime_b", "chime_c"]
const LEAF_COLORS: Array[Color] = [Color("3a7550"), Color("2b5646"), Color("74b268"), Color("34283c")]

var id: String = ""
var display_name: String = ""
var reveal_cells: float = 15.0
var awake: bool = false

var _art: Dictionary = {}
var _body: Sprite2D
var _glow: Sprite2D
var _body_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _ground: Sprite2D ## the bed of flagstones under the statue (tools/art_waystone_ground.py)
var _ground_glow: Sprite2D
var _ground_mat: ShaderMaterial
var _ground_glow_mat: ShaderMaterial
var _ground_info: Dictionary = {}
var paved: bool = false ## the statue stands on a town's paving (data/waystones.json `paved`, Hallgrat's forum): its overgrown bed is not drawn, the glow of its lines stays
var _crystals: Array[Dictionary] = [] ## ground crystals round the plinth: {body, glow, delay}; sibling nodes of the statue so they sort like any prop
var _crystal_dim: float = 0.0
var _lit_strength: float = 1.0
var _beam: ColorRect
var _beam_mat: ShaderMaterial
var _ring: Node2D
var _light: NightLight
var _motes: CPUParticles2D
var _debris: CPUParticles2D
var _hum: AudioStreamPlayer2D
var _progress: float = 0.0
var _flash: float = 0.0
var _beam_level: float = 0.0
var _ring_age: float = 99.0
var _time: float = 0.0
var _busy: bool = false
var _touching: bool = false
var _discover_timer: float = 0.0
var _tween: Tween


func _ready() -> void:
	_art = DataRegistry.table("waystone_art")
	_ground_info = DataRegistry.table("waystone_ground")
	_make_ground()
	var wave: Texture2D = load(DIR + "statue_wave.png") as Texture2D
	_body = Sprite2D.new()
	_body.texture = load(DIR + "statue_wild.png") as Texture2D
	_body.offset = Vector2(0, -(GROUND_ROW - FRAME.y / 2.0))
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = SHADER_BODY
	_body_mat.set_shader_parameter("clean_tex", load(DIR + "statue_clean.png"))
	_body_mat.set_shader_parameter("wave_tex", wave)
	_body.material = _body_mat
	add_child(_body)
	_ring = Node2D.new() ## the runes round the plinth and the ring of force on the ground
	_ring.z_index = -1
	_ring.material = Unlit.material()
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_glow = Sprite2D.new()
	_glow.texture = load(DIR + "statue_dim.png") as Texture2D
	_glow.offset = _body.offset
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = SHADER_GLOW
	_glow_mat.set_shader_parameter("lit_tex", load(DIR + "statue_glow.png"))
	_glow_mat.set_shader_parameter("wave_tex", wave)
	_glow.material = _glow_mat
	add_child(_glow)
	_beam = ColorRect.new()
	_beam.size = Vector2(36, 120)
	_beam.position = Vector2(-18, -196)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = SHADER_BEAM
	_beam_mat.set_shader_parameter("rect_size", _beam.size)
	_beam.material = _beam_mat
	_beam.z_index = 2
	_beam.visible = false
	add_child(_beam)
	_light = NightLight.new() ## a pool of light on the ground: teal under violet
	_light.position = Vector2(0, -6)
	_light.radius = 52
	_light.base_energy = 0.0
	_light.glow_color = Color("8fe8e0")
	add_child(_light)
	_make_particles()
	_make_body()
	_spawn_crystals.call_deferred()
	_hum = AudioStreamPlayer2D.new()
	_hum.stream = _wav("hum", true)
	_hum.volume_db = -14.0
	_hum.max_distance = 320.0
	_hum.attenuation = 1.6
	add_child(_hum)
	_apply(0.0, false)
	var manager: Waystones = Waystones.of(get_tree())
	if manager != null:
		manager.register(self)


## The stone bed under the statue: dormant it is cracked and overgrown, the awakening runs over it from the plinth outwards (the same shaders and the same
## `progress` as the statue) and leaves polished slabs with glowing leylines and a ring of runes. It is a ground surface of its own: "stone" under her feet.
func _make_ground() -> void:
	var wave: Texture2D = load(DIR + "ground_wave.png") as Texture2D
	_ground = Sprite2D.new()
	_ground.texture = load(DIR + "ground_wild.png") as Texture2D
	_ground.z_index = -9
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = SHADER_BODY
	_ground_mat.set_shader_parameter("clean_tex", load(DIR + "ground_clean.png"))
	_ground_mat.set_shader_parameter("wave_tex", wave)
	_ground.material = _ground_mat
	add_child(_ground)
	move_child(_ground, 0)
	_ground.visible = not paved
	_ground_glow = Sprite2D.new()
	_ground_glow.texture = load(DIR + "ground_dim.png") as Texture2D
	_ground_glow.z_index = -8
	_ground_glow_mat = ShaderMaterial.new()
	_ground_glow_mat.shader = SHADER_GLOW
	_ground_glow_mat.set_shader_parameter("lit_tex", load(DIR + "ground_glow.png"))
	_ground_glow_mat.set_shader_parameter("wave_tex", wave)
	_ground_glow.material = _ground_glow_mat
	add_child(_ground_glow)
	Terrain.patches.append(self)
	tree_exiting.connect(func() -> void: Terrain.patches.erase(self))


## "stone" on the bed (an ellipse a little inside its ragged rim), "" elsewhere.
func surface_at(world_pos: Vector2) -> String:
	var local: Vector2 = world_pos - global_position
	return "stone" if (local.x / 76.0) * (local.x / 76.0) + (local.y / 44.0) * (local.y / 44.0) <= 1.0 else ""


## A few dark crystals standing in the stone round the plinth: 5 to 7, in two or three loose groups, never in front of it, each of the ten shapes at most twice (placed from
## the statue's id, so every statue looks different). Each lights when the wave reaches its distance and glows with the statue afterwards.
func _spawn_crystals() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var frame: Array = _ground_info.get("frame", [28, 26]) as Array
	var ground_row: float = float(_ground_info.get("ground", 23))
	var variants: int = int(_ground_info.get("variants", 10))
	var reach: Array = _ground_info.get("radius", [86, 50]) as Array
	var dark: Texture2D = load(DIR + "crystals_wild.png") as Texture2D
	var lit: Texture2D = load(DIR + "crystals_lit.png") as Texture2D
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = absi(id.hash())
	var count: int = rng.randi_range(5, 7)
	var sockets: Array = (_ground_info.get("sockets", []) as Array).duplicate()
	for i: int in range(sockets.size() - 1, 0, -1): ## shuffled by the statue's id: every statue stands its crystals on other sockets
		var j: int = rng.randi() % (i + 1)
		var swap: Variant = sockets[i]
		sockets[i] = sockets[j]
		sockets[j] = swap
	var used: Dictionary = {}
	for socket: Array in sockets:
		if _crystals.size() >= count:
			break
		var at: Vector2 = Vector2(float(socket[0]), float(socket[1]) + 1.0)
		var radius: float = Vector2(at.x / float(reach[0]), at.y / float(reach[1])).length()
		var variant: int = rng.randi() % variants
		if int(used.get(variant, 0)) >= 2:
			variant = (variant + 1 + rng.randi() % (variants - 1)) % variants
		used[variant] = int(used.get(variant, 0)) + 1
		var flip: bool = rng.randi() % 2 == 1
		var body: Sprite2D = Sprite2D.new()
		body.texture = dark
		body.hframes = variants
		body.frame = variant
		body.flip_h = flip
		body.offset = Vector2(0, -(ground_row - float(frame[1]) / 2.0))
		body.position = position + at
		var glow: Sprite2D = Sprite2D.new()
		glow.texture = lit
		glow.hframes = variants
		glow.frame = variant
		glow.flip_h = flip
		glow.offset = body.offset ## the lit crystal lies exactly on the dark one (without this it sat 10 px lower)
		glow.material = Unlit.material()
		glow.modulate.a = 0.0
		body.add_child(glow)
		parent.add_child(body)
		_crystals.append({"body": body, "glow": glow, "delay": 0.18 + 0.8 * radius})
	tree_exiting.connect(func() -> void:
		for c: Dictionary in _crystals:
			if is_instance_valid(c.body):
				(c.body as Node).queue_free())
	_update_crystals()


func _update_crystals() -> void:
	for c: Dictionary in _crystals:
		var reached: float = clampf((_progress - float(c.delay)) / 0.07, 0.0, 1.0)
		var glow: Sprite2D = c.glow as Sprite2D
		glow.modulate = Color(1, 1, 1, maxf(reached * clampf(_lit_strength, 0.0, 1.0), _crystal_dim)).lerp(Color(2, 2, 2, 1), _flash * 0.5)


func _make_body() -> void:
	var body: StaticBody2D = StaticBody2D.new() ## the plinth
	var shape: CollisionPolygon2D = CollisionPolygon2D.new()
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 20:
		points.append(Vector2.from_angle(TAU * i / 20.0) * Vector2(20.0, 8.0) + Vector2(0, 1))
	shape.polygon = points
	body.add_child(shape)
	add_child(body)


func _make_particles() -> void:
	_motes = CPUParticles2D.new() ## light rising off the awakened statue
	_motes.material = Unlit.material()
	_motes.z_index = 3
	_motes.position = Vector2(0, -44)
	_motes.amount = 26
	_motes.lifetime = 4.2
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(22, 24)
	_motes.direction = Vector2(0, -1)
	_motes.spread = 18.0
	_motes.initial_velocity_min = 5.0
	_motes.initial_velocity_max = 15.0
	_motes.gravity = Vector2.ZERO
	_motes.scale_amount_min = 1.0
	_motes.scale_amount_max = 1.6
	var ramp: Gradient = Gradient.new()
	ramp.colors = PackedColorArray([Color("d0fff8", 0.0), Color("78f4e6", 0.9), Color("b99bff", 0.7), Color("b99bff", 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	_motes.color_ramp = ramp
	_motes.emitting = false
	add_child(_motes)
	_debris = CPUParticles2D.new() ## leaves, moss and stone grit shaken off by the awakening
	_debris.z_index = 3
	_debris.position = Vector2(0, -30)
	_debris.amount = 70
	_debris.lifetime = 1.7
	_debris.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_debris.emission_rect_extents = Vector2(14, 22)
	_debris.direction = Vector2(0, -0.3)
	_debris.spread = 80.0
	_debris.initial_velocity_min = 8.0
	_debris.initial_velocity_max = 32.0
	_debris.gravity = Vector2(0, 62)
	_debris.damping_min = 6.0
	_debris.damping_max = 18.0
	_debris.scale_amount_min = 1.0
	_debris.scale_amount_max = 2.0
	var fall: Gradient = Gradient.new()
	fall.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.0)])
	_debris.color_ramp = fall
	_debris.color = LEAF_COLORS[0]
	_debris.emitting = false
	add_child(_debris)


func _wav(name: String, loop: bool = false) -> AudioStreamWAV:
	var stream: AudioStreamWAV = load("res://assets/audio/waystone/%s.wav" % name) as AudioStreamWAV
	if loop and stream != null:
		stream = stream.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


func _sound(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = _wav(name)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = 520.0
	player.attenuation = 1.4
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# ---------------------------------------------------------------- interaction

func prompt() -> String:
	if _busy or _touching:
		return ""
	return "REISEN" if awake else "AKTIVIEREN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 20.0


func prompt_position() -> Vector2:
	return Vector2(0, -44)


func interact(player: Player) -> void:
	if _busy or _touching:
		return
	var manager: Waystones = Waystones.of(get_tree())
	if manager == null:
		return
	if awake:
		manager.begin_travel(player, self) ## walk up, touch it, choose another statue on the map
		return
	_touching = true ## she lays both palms on the stone (Player.begin_touch); where they lie the statue wakes
	get_tree().create_timer(1.6).timeout.connect(func() -> void: _touching = false) ## (a hit before that stops the animation: the statue stays asleep)
	player.begin_touch((global_position + Vector2(0, -8) - player.global_position).normalized(), func() -> void:
		_touching = false
		manager.request_activate(id))


## Where something in the picture is, in node coordinates (px of the art sheet: `data/waystone_art.json`).
func art_point(key: String) -> Vector2:
	var p: Array = _art.get(key, [64, 60]) as Array
	return Vector2(float(p[0]) - FRAME.x / 2.0, float(p[1]) - GROUND_ROW)


func center_point() -> Vector2:
	return global_position + Vector2(0, -34)


# ---------------------------------------------------------------- the awakening

## Loaded save, joining peer: already awake, nothing plays.
func set_awake_instant() -> void:
	awake = true
	_busy = false
	if _tween != null:
		_tween.kill()
	_apply(1.12, false)
	_settle()


## The animation, the same on every peer. Takes `FLASH_AT` seconds to the bloom and about two more to settle.
func awaken() -> void:
	if awake or _busy:
		return
	_busy = true
	set_focused(false)
	_sound("swell", -4.0)
	_debris.color = LEAF_COLORS[0]
	_tween = create_tween()
	_tween.set_parallel(false)
	_tween.tween_method(_flicker, 0.0, 1.0, LIGHT_UP)
	_tween.tween_callback(_start_wave)
	_tween.tween_method(func(k: float) -> void: _apply(k, true), 0.0, 1.12, WAVE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_bloom)
	_tween.tween_method(func(k: float) -> void: _flash = k * k, 1.0, 0.0, 1.1)
	_tween.tween_callback(_settle)


func _flicker(k: float) -> void: ## the dark crystals stir: a few faint pulses before any of them lights
	var pulse: float = maxf(sin(k * 31.0) * sin(k * 17.0 + 1.0), 0.0)
	_glow_mat.set_shader_parameter("dim_level", 0.35 + 1.4 * pulse * k)
	_crystal_dim = 0.55 * pulse * k
	_update_crystals()
	_light.base_energy = 0.55 * k * k


func _start_wave() -> void:
	_sound("crumble", -3.0)
	for i: int in CHIMES.size():
		get_tree().create_timer(0.25 + 0.55 * i).timeout.connect(func() -> void: _sound(CHIMES[i], -5.0, 1.0 + 0.06 * i))
	_debris.amount = 70
	_debris.emitting = true
	_motes.emitting = true
	_ring_age = 0.0
	get_tree().create_timer(WAVE_TIME * 0.82).timeout.connect(func() -> void: _debris.emitting = false)
	var beam: Tween = create_tween()
	beam.tween_method(func(k: float) -> void: _beam_level = k, 0.0, 1.0, WAVE_TIME)


func _bloom() -> void:
	_sound("bloom", -1.0)
	_ring_age = 0.0
	_flash = 1.0
	ShockRing.burst(get_parent(), global_position, 95.0, 1.0)
	for player: Player in Player.all:
		if player.global_position.distance_to(global_position) < 420.0:
			player.add_shake(5.0)


## A flare of light (the statue was touched to travel, someone arrives): the glow blooms for a moment and a ring runs over the ground.
func flare(strength: float = 1.0) -> void:
	_sound("bloom", -14.0 + 8.0 * strength, 1.0 + 0.1 * (1.0 - strength))
	_ring_age = 0.0
	var tween: Tween = create_tween()
	tween.tween_method(func(k: float) -> void: _flash = k * k * strength, 1.0, 0.0, 1.0)


func _settle() -> void:
	awake = true
	_busy = false
	_motes.emitting = true
	_debris.emitting = false
	_beam.visible = true
	_beam_level = maxf(_beam_level, 1.0)
	_hum.play()
	awakened.emit()


func _apply(progress: float, _animating: bool) -> void:
	_progress = progress
	_body_mat.set_shader_parameter("progress", progress)
	_glow_mat.set_shader_parameter("progress", progress)
	_ground_mat.set_shader_parameter("progress", progress)
	_ground_glow_mat.set_shader_parameter("progress", progress)
	_crystal_dim = 0.0
	_update_crystals()
	if progress > 0.0:
		_beam.visible = true
		_glow_mat.set_shader_parameter("dim_level", 0.35)
	if progress >= 1.12:
		_light.base_energy = 0.55
		_beam_level = 1.0
		_motes.emitting = true


func _process(delta: float) -> void:
	_time += delta
	_check_discovery(delta)
	if _ring_age < 99.0:
		_ring_age += delta
	var night: float = TimeManager.night_amount()
	var live: bool = awake or _progress > 0.0
	if live:
		var breath: float = 0.5 + 0.5 * sin(_time * 1.7 + position.x * 0.1)
		var strength: float = lerpf(0.82, 1.15, night) * (0.9 + 0.1 * breath)
		_glow_mat.set_shader_parameter("lit_level", strength)
		_ground_glow_mat.set_shader_parameter("lit_level", strength)
		_lit_strength = strength * 0.9
		_update_crystals()
		_beam_mat.set_shader_parameter("strength", _beam_level * lerpf(0.5, 1.0, night) * (0.85 + 0.15 * breath))
		_beam_mat.set_shader_parameter("time", _time)
	_glow_mat.set_shader_parameter("flash", _flash)
	_ground_glow_mat.set_shader_parameter("flash", _flash)
	if awake:
		_light.base_energy = lerpf(0.3, 0.55, night) * (0.9 + 0.1 * sin(_time * 1.3))
	if live and int(_time * 20.0) != int((_time - delta) * 20.0):
		_ring.queue_redraw()


## The first statue she comes close to: a small dialogue, once (the flag is saved with her quests).
func _check_discovery(delta: float) -> void:
	_discover_timer -= delta
	if _discover_timer > 0.0:
		return
	_discover_timer = 0.5
	for player: Player in Player.all:
		if not player.is_multiplayer_authority() or player.quests == null or player.quests.has_flag("waystone_seen"):
			continue
		if player.is_busy() or player.global_position.distance_to(global_position) > DISCOVER_RANGE:
			continue
		var runner: BubbleRunner = BubbleRunner.find(player)
		var box: DialogueBox = DialogueBox.find(player)
		if runner == null or runner.is_active() or (box != null and box.is_active()):
			continue
		player.quests.set_flag("waystone_seen")
		runner.play("waystone_discover", player)


## Dotted ellipse of light round the plinth (awake) and the rings of force on the ground (while awakening and at the bloom).
func _draw_ring() -> void:
	if not (awake or _progress > 0.0):
		return
	var night: float = TimeManager.night_amount()
	var level: float = clampf(_progress, 0.0, 1.0) * lerpf(0.35, 0.8, night)
	var steps: int = 56
	var march: int = int(_time * 6.0)
	for i: int in steps:
		if (i + march) % 4 == 0:
			continue
		var a: float = TAU * i / float(steps)
		var p: Vector2 = Vector2(cos(a) * 28.0, sin(a) * 12.0 + 2.0).round()
		_ring.draw_rect(Rect2(p, Vector2.ONE), Color("78f4e6", level * 0.8))
	if _ring_age < 3.0:
		for k: int in 3:
			var age: float = _ring_age - k * 0.22
			if age <= 0.0:
				continue
			var t: float = clampf(age / 2.2, 0.0, 1.0)
			var radius: float = 24.0 + 100.0 * (1.0 - pow(1.0 - t, 2.4))
			var fade: float = (1.0 - t) * (0.9 if k == 0 else 0.55)
			for i: int in 96:
				if (i + k) % 3 == 0:
					continue
				var a2: float = TAU * i / 96.0
				var q: Vector2 = Vector2(cos(a2) * radius, sin(a2) * radius * 0.43 + 2.0).round()
				_ring.draw_rect(Rect2(q, Vector2.ONE), Color("b99bff" if k == 1 else "9ff5ec", fade))
