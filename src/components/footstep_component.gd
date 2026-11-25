class_name FootstepComponent
extends Node2D
## Per-step feedback from the surface data (data/terrain.json): puffs or splashes, and
## footprints on soft ground. Called by the player at every footfall, on every peer.

const FOOTPRINT: Texture2D = preload("res://assets/fx/footprint.png")
const FOOTPRINT_Z: int = -6 ## above WaterField sand (-7) & ground surfaces (-10), below flat props (-5) and entities (0)
const FOOT_OFFSET: float = 2.5 ## px, feet alternate left/right of the walking line

const STYLE_DEFAULT: int = 0
const STYLE_DRY_SAND: int = 1
const STYLE_WET_SAND: int = 2

var _left_foot: bool = false

@onready var _puff: CPUParticles2D = $Puff

static var _canvas: FootprintCanvas = null


class FootprintItem:
	var pos: Vector2 = Vector2.ZERO
	var world_pos: Vector2 = Vector2.ZERO
	var rot: float = 0.0
	var color: Color = Color.BLACK
	var base_alpha: float = 0.7
	var age: float = 0.0
	var life: float = 10.0
	var style: int = 0
	var washable: bool = false
	var washing: bool = false
	var active: bool = false


class FootprintCanvas:
	extends Node2D

	const POOL_SIZE: int = 160
	var _pool: Array[FootprintItem] = []
	var _head: int = 0
	var _has_active: bool = false
	var _tex_offset: Vector2 = Vector2.ZERO
	var _wash_timer: float = 0.0

	func _init() -> void:
		_tex_offset = -FOOTPRINT.get_size() * 0.5
		_pool.resize(POOL_SIZE)
		for i: int in POOL_SIZE:
			_pool[i] = FootprintItem.new()

	func add_footprint(pos: Vector2, world_pos: Vector2, rot: float, col: Color, alpha: float, life: float, style: int = 0, washable: bool = false) -> void:
		var item: FootprintItem = _pool[_head]
		_head = (_head + 1) % POOL_SIZE
		item.pos = pos
		item.world_pos = world_pos
		item.rot = rot
		item.color = col
		item.base_alpha = alpha
		item.age = 0.0
		item.life = maxf(life, 0.01)
		item.style = style
		item.washable = washable
		item.washing = false
		item.active = true
		_has_active = true
		queue_redraw()

	func _process(delta: float) -> void:
		if not _has_active:
			return
		_wash_timer += delta
		var check_wash: bool = _wash_timer >= 0.10
		if check_wash:
			_wash_timer = 0.0
		var wf_node: Node = null
		if check_wash:
			for patch: Node in Terrain.patches:
				if is_instance_valid(patch) and patch.has_method(&"water_field_at"):
					wf_node = patch
					break
		var any_active: bool = false
		for item: FootprintItem in _pool:
			if not item.active:
				continue
			if check_wash and item.washable and wf_node != null:
				var wf: Dictionary = wf_node.call(&"water_field_at", item.world_pos) as Dictionary
				if bool(wf.get("in_bounds", false)):
					if bool(wf.get("water", false)):
						# Incoming ocean swash wave rolls over the print and washes it away!
						item.washing = true
						item.style = STYLE_WET_SAND
					elif item.style == STYLE_DRY_SAND and bool(wf.get("wet_sand", false)):
						item.style = STYLE_WET_SAND
						item.color = Color("#3d332d")
			var rate: float = 9.5 if item.washing else 1.0
			item.age += delta * rate
			if item.age >= item.life:
				item.active = false
			else:
				any_active = true
		_has_active = any_active
		if any_active:
			queue_redraw()

	func _draw() -> void:
		if not _has_active:
			return
		var night: float = TimeManager.night_amount()
		for item: FootprintItem in _pool:
			if not item.active:
				continue
			var t: float = clampf(item.age / item.life, 0.0, 1.0)
			var fade: float = 1.0 if t < 0.58 else (1.0 - (t - 0.58) / 0.42)
			var a: float = item.base_alpha * clampf(fade, 0.0, 1.0)
			if a <= 0.015:
				continue
			draw_set_transform(item.pos, item.rot, Vector2.ONE)
			if item.style == STYLE_DRY_SAND:
				# Crisp 3D pixel-art dry-sand boot depression: sunlit NW raised sand rim + shaded sole & heel!
				var rim_c: Color = Color(0.95, 0.87, 0.69).lerp(Color(0.45, 0.50, 0.66), night * 0.72)
				rim_c.a = a * 0.78
				draw_rect(Rect2(-2.5, -2.0, 4.0, 1.0), rim_c)
				draw_rect(Rect2(-3.0, -1.0, 1.0, 2.0), rim_c)
				var dep_c: Color = item.color.lerp(Color(0.14, 0.16, 0.27), night * 0.72)
				dep_c.a = a * 0.88
				draw_rect(Rect2(-2.0, -1.0, 5.0, 2.0), dep_c)
				draw_rect(Rect2(-1.0, 1.0, 3.0, 1.0), dep_c)
				var core_c: Color = dep_c.darkened(0.26)
				core_c.a = a * 0.72
				draw_rect(Rect2(-1.0, -0.5, 2.0, 1.0), core_c)
				draw_rect(Rect2(1.5, -0.5, 1.0, 1.0), core_c)
			elif item.style == STYLE_WET_SAND:
				# Glistening dark water-filled wet-sand depression with tiny sky-sheen meniscus!
				var wdep_c: Color = item.color.lerp(Color(0.08, 0.11, 0.20), night * 0.70)
				wdep_c.a = a * 0.92
				draw_rect(Rect2(-2.0, -1.5, 5.0, 3.0), wdep_c)
				draw_rect(Rect2(-1.0, -2.0, 3.0, 1.0), wdep_c)
				var sheen_c: Color = Color(0.60, 0.82, 0.84).lerp(Color(0.36, 0.48, 0.76), night)
				sheen_c.a = a * (0.48 if not item.washing else 0.72)
				draw_rect(Rect2(-1.0, 0.0, 2.0, 1.0), sheen_c)
				draw_rect(Rect2(1.5, -0.5, 1.0, 1.0), sheen_c)
			else:
				var c: Color = item.color
				c.a = a
				draw_texture(FOOTPRINT, _tex_offset, c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _get_canvas(tree: SceneTree) -> FootprintCanvas:
	if _canvas != null and is_instance_valid(_canvas) and _canvas.is_inside_tree() and _canvas.get_tree() == tree:
		return _canvas
	var scene: Node = tree.current_scene
	if scene == null:
		return null
	_canvas = FootprintCanvas.new()
	_canvas.name = "FootprintCanvas"
	_canvas.z_as_relative = false
	_canvas.z_index = FOOTPRINT_Z
	scene.add_child(_canvas)
	return _canvas


## `quiet` (sneaking) skips the puff but still leaves footprints.
## `wet` (0..1, soaked from a swim) leaves dark, short-lived prints on dry ground.
## `gait` (-1 auto from speed, 0 walk, 1 jog, 2 sprint; overridden to sneak when `quiet` is true).
func step(surface: Dictionary, velocity: Vector2, quiet: bool, wet: float = 0.0, gait: int = -1) -> void:
	_left_foot = not _left_foot
	var contact_pos: Vector2 = contact_position(velocity)
	var puddle_hit: float = _play_sound(surface, velocity, quiet, wet, gait, contact_pos)
	var fx: Dictionary = surface.get("step", {}) as Dictionary
	if puddle_hit > 0.0 and not bool(surface.get("ripples", false)) and String(surface.get("sound", "")) != "puddle":
		fx = {"kind": "splash", "color": "#bfe9ff", "amount": 4}
	if not fx.is_empty() and not quiet:
		_emit(fx, velocity)
	var print_data: Dictionary = surface.get("footprint", {}) as Dictionary
	var alpha: float = 0.7
	var boot_wet: float = maxf(wet, _puddle_wet)
	if boot_wet > 0.15 and not bool(surface.get("ripples", false)):
		print_data = {"color": "#1c2b33", "seconds": 1.5 + 3.0 * boot_wet}
		alpha = 0.35 + 0.4 * boot_wet
	if not print_data.is_empty():
		_leave_footprint(print_data, velocity, alpha)


## Step sounds (`assets/audio/steps/<sound>_<gait>_1..4.wav`, generated by `tools/audio_footsteps.py`):
## four distinct gaits (`sneak`, `walk`, `jog`, `sprint`) across all 13 surfaces, non-repeating variants,
## plus exact rain-puddle splashes (`BiomeBlend.puddle_at`) and wet-sole layering for soaked boots / rain.
const STEP_VARIANTS: int = 4
const GAIT_NAMES: Array[String] = ["sneak", "walk", "jog", "sprint"]
const GAIT_DB: Array[float] = [-12.5, -10.5, -9.0, -7.5]
const GAIT_RANGE: Array[float] = [165.0, 240.0, 290.0, 340.0]

static var _step_cache: Dictionary = {}
var _last_variant: Dictionary = {}
var _puddle_wet: float = 0.0 ## 0..1 dampness picked up from stepping through shallow puddles, fades over ~3 steps


static func _step_stream(sound: String, gait_name: String, variant: int) -> AudioStream:
	var key: String = "%s_%s_%d" % [sound, gait_name, variant]
	if not _step_cache.has(key):
		var wav_path: String = "res://assets/audio/steps/%s.wav" % key
		if ResourceLoader.exists(wav_path):
			_step_cache[key] = load(wav_path)
		else:
			var fallback_path: String = "res://assets/audio/steps/%s_walk_%d.wav" % [sound, variant]
			_step_cache[key] = load(fallback_path) if ResourceLoader.exists(fallback_path) else null
	return _step_cache[key] as AudioStream


func _next_variant(bucket: String) -> int:
	var last: int = int(_last_variant.get(bucket, 0))
	var variant: int = 1 + (last + randi() % (STEP_VARIANTS - 1)) % STEP_VARIANTS
	_last_variant[bucket] = variant
	return variant


static func _resolve_gait_index(velocity: Vector2, quiet: bool, gait: int) -> int:
	if quiet:
		return 0
	if gait >= 0:
		return clampi(gait + 1, 1, 3)
	var speed: float = velocity.length()
	if speed >= 104.0:
		return 3
	if speed >= 70.0:
		return 2
	return 1


func _spawn_step_player(stream: AudioStream, db: float, pitch: float, max_dist: float, contact_pos: Vector2) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = pitch
	player.max_distance = max_dist
	player.position = to_local(contact_pos)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Plays the surface step (and any rain-puddle / wet-sole layer); returns standing puddle depth (0..1).
func _play_sound(surface: Dictionary, velocity: Vector2, quiet: bool, wet: float, gait: int, contact_pos: Vector2) -> float:
	var sound: String = String(surface.get("sound", ""))
	if sound.is_empty():
		return 0.0
	var gait_idx: int = _resolve_gait_index(velocity, quiet, gait)
	var gait_name: String = GAIT_NAMES[gait_idx]
	var max_dist: float = GAIT_RANGE[gait_idx]
	var base_db: float = GAIT_DB[gait_idx] + float(surface.get("sound_gain", 0.0)) + (0.8 if _left_foot else 0.0)
	var base_pitch: float = randf_range(0.96, 1.04) * (0.992 if _left_foot else 1.008)

	var in_water: bool = bool(surface.get("ripples", false))
	var is_puddle_surface: bool = sound == "puddle"
	var prev_puddle_wet: float = _puddle_wet
	_puddle_wet = maxf(_puddle_wet - 0.24, 0.0)

	var puddle_depth: float = 0.0
	var rain_wet: float = 0.0
	if not in_water and not is_puddle_surface and Interiors.slot_at(contact_pos) < 0 and not MineManager.in_mine(contact_pos):
		var wm: WeatherManager = WeatherManager.current
		var puddle_amt: float = wm.puddle if wm != null else clampf((Moisture.wetness() - 0.45) * 1.4, 0.0, 0.75)
		puddle_depth = BiomeBlend.puddle_at(contact_pos, puddle_amt)
		var raw_wet: float = wm.ground_wet if wm != null else Moisture.wetness()
		rain_wet = raw_wet * (1.0 - smoothstep(0.18, 0.48, BiomeBlend.arid_at(contact_pos)))

	if is_puddle_surface:
		_puddle_wet = maxf(_puddle_wet, 0.65)
	elif puddle_depth > 0.0:
		_puddle_wet = maxf(_puddle_wet, 0.45 + 0.45 * puddle_depth)

	var boot_wet: float = maxf(wet, prev_puddle_wet)
	var damp: float = maxf(boot_wet, rain_wet * 0.65)

	var main_variant: int = _next_variant("%s_%s" % [sound, gait_name])
	var main_stream: AudioStream = _step_stream(sound, gait_name, main_variant)
	var main_db: float = base_db
	var main_pitch: float = base_pitch
	if puddle_depth > 0.0:
		main_db -= lerpf(1.5, 3.5, puddle_depth)
		main_pitch *= 0.96
	elif not in_water and not is_puddle_surface and damp > 0.22:
		main_pitch *= lerpf(1.0, 0.96, damp)
	_spawn_step_player(main_stream, main_db, main_pitch, max_dist, contact_pos)

	# Layer shallow puddle splash or subtle soaked-boot / rain-sheen slap on dry surfaces
	if not in_water and not is_puddle_surface:
		if puddle_depth > 0.0:
			var pud_var: int = _next_variant("puddle_%s" % gait_name)
			var pud_stream: AudioStream = _step_stream("puddle", gait_name, pud_var)
			var pud_db: float = GAIT_DB[gait_idx] + lerpf(-2.2, 0.6, puddle_depth) + (0.6 if _left_foot else 0.0)
			_spawn_step_player(pud_stream, pud_db, base_pitch * randf_range(0.98, 1.04), max_dist, contact_pos)
		elif damp > 0.22:
			var wet_var: int = _next_variant("puddle_%s" % gait_name)
			var wet_stream: AudioStream = _step_stream("puddle", gait_name, wet_var)
			var wet_db: float = GAIT_DB[gait_idx] + lerpf(-13.5, -5.8, clampf((damp - 0.22) / 0.78, 0.0, 1.0))
			_spawn_step_player(wet_stream, wet_db, base_pitch * randf_range(1.02, 1.08), max_dist * 0.85, contact_pos)
	return puddle_depth


func contact_position(velocity: Vector2) -> Vector2:
	var dir: Vector2 = velocity.normalized()
	return (global_position + Vector2(-dir.y, dir.x) * (FOOT_OFFSET if _left_foot else -FOOT_OFFSET)).round()


func _emit(fx: Dictionary, velocity: Vector2) -> void:
	_puff.color = Color(String(fx.get("color", "#ffffff")))
	_puff.amount = int(fx.get("amount", 3))
	_puff.position = to_local(contact_position(velocity))
	if fx.get("kind", "puff") == "splash":
		_puff.direction = Vector2.UP
		_puff.spread = 55.0
		_puff.gravity = Vector2(0, 240)
		_puff.amount = clampi(roundi(velocity.length() / 18.0), 2, 7)
		_puff.initial_velocity_min = lerpf(14.0, 40.0, clampf(velocity.length() / 90.0, 0.0, 1.0))
		_puff.initial_velocity_max = _puff.initial_velocity_min * 1.5
		_puff.damping_min = 0.0
		_puff.damping_max = 0.0
		_puff.lifetime = 0.4
	else:
		_puff.direction = -velocity.normalized()
		_puff.spread = 40.0
		_puff.gravity = Vector2.ZERO
		_puff.initial_velocity_min = 15.0
		_puff.initial_velocity_max = 35.0
		_puff.damping_min = 50.0
		_puff.damping_max = 70.0
		_puff.lifetime = 0.3
	_puff.restart()


func _leave_footprint(data: Dictionary, velocity: Vector2, alpha: float = 0.7) -> void:
	var canvas: FootprintCanvas = _get_canvas(get_tree())
	if canvas == null:
		return
	var dir: Vector2 = velocity.normalized()
	var rot: float = roundf(dir.angle() / (PI / 4.0)) * (PI / 4.0) ## 8 directions keep the pixels clean
	var global_pos: Vector2 = (global_position + Vector2(-dir.y, dir.x) * (FOOT_OFFSET if _left_foot else -FOOT_OFFSET)).round()
	var local_pos: Vector2 = canvas.to_local(global_pos)
	var col: Color = Color(String(data.get("color", "#000000")))
	var seconds: float = float(data.get("seconds", 10.0))
	var style_name: String = String(data.get("style", ""))
	var style_id: int = STYLE_DEFAULT
	if style_name == "dry_sand":
		style_id = STYLE_DRY_SAND
	elif style_name == "wet_sand":
		style_id = STYLE_WET_SAND
	var washable: bool = bool(data.get("washable", false))
	canvas.add_footprint(local_pos, global_pos, rot, col, alpha, seconds, style_id, washable)
