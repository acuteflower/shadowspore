class_name VeilThreadPickup
extends Interactable
## Procedural buried & living Schattenfrucht collectible (`docs/schattenfruechte_und_menue_konzept.md` §1).
## Supports 4 living behavioral archetypes (`calm`, `shy`, `nocturnal`, `stubborn`), spatial warm-cold
## acoustic pings & wind-drifted spore trails, `Player.begin_pull` heave, living-in-hand wiggling,
## and pocket tuck synchronized across all co-op peers.

const UPROOT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/town/uproot_a.wav"),
	preload("res://assets/audio/town/uproot_b.wav"),
	preload("res://assets/audio/town/uproot_c.wav"),
]
const RUSTLE_WAV: AudioStream = preload("res://assets/audio/hut/rustle.wav")
const BURST_WAV: AudioStream = preload("res://assets/audio/magic/root_burst.wav")
const POP_WAV: AudioStream = preload("res://assets/audio/sfx/drop_pop.wav")
const CHIME_WAV: AudioStream = preload("res://assets/audio/waystone/chime_b.wav")
const POCKET_WAV: AudioStream = preload("res://assets/audio/sfx/item_pickup.wav")

const PLANTED_OFFSET: Vector2 = Vector2(0.0, -7.0) ## 24x24 planted sprite, soil pivot at y=19
const HOLE_OFFSET: Vector2 = Vector2(0.0, -2.0) ## 24x16 crater sprite, center at y=10

const POP_DURATION: float = 0.28
const HAND_END: float = 1.32
const POCKET_END: float = 1.72
const HOLE_FADE_END: float = 4.20

const SOIL_COLORS: Array[Color] = [
	Color("30233a"),
	Color("4b384f"),
	Color("644c58"),
	Color("1b1526"),
]

var thread_id: String = ""
var zone_id: StringName = &""
var place_id: StringName = &""
var trait_kind: String = "calm" ## calm | shy | nocturnal | stubborn
var hint_text: String = ""

var _art: Dictionary = {}
var _accent: Color = Color("78f4e6")
var _accent_mid: Color = Color("3cc0c6")
var _chime_pitch: float = 1.0
var _fruit_bodies: Array[ImageTexture] = []
var _fruit_glows: Array[ImageTexture] = []

var _body: Sprite2D
var _glow: Sprite2D
var _light: NightLight
var _motes: CPUParticles2D

var _held_root: Node2D = null
var _held_body: Sprite2D = null
var _held_glow: Sprite2D = null
var _held_light: NightLight = null
var _collector: Player = null

var _time: float = 0.0
var _phase: float = 0.0
var _pulling: bool = false
var _pull_t: float = 0.0
var _collecting: bool = false
var _collect_t: float = 0.0
var _chime_played: bool = false
var _pocket_played: bool = false
var _spent: bool = false

# Archetype runtime states
var _visual_mode: String = "planted" ## planted | hiding | closed | half | hole
var _shy_hidden: bool = false
var _shy_quiet_t: float = 0.0
var _nocturnal_open: bool = true
var _stubborn_stage: int = 0
var _stubborn_timer: float = 0.0
var _sleep_shake_t: float = 0.0

# Ambient warm-cold ping & wind-spore trail timers
var _ping_timer: float = 1.5
var _wind_spore_timer: float = 1.2


func _ready() -> void:
	var key: String = thread_id if not thread_id.is_empty() else name
	_art = ShadowFruitArt.build(key)
	_accent = _art["accent"] as Color
	_accent_mid = _art["accent_mid"] as Color
	_chime_pitch = float(_art["pitch"])
	_fruit_bodies = _art["fruit_bodies"] as Array[ImageTexture]
	_fruit_glows = _art["fruit_glows"] as Array[ImageTexture]
	_phase = fposmod(float(absi(key.hash())) * 0.137, TAU)
	_ping_timer = randf_range(1.2, 3.4)
	_wind_spore_timer = randf_range(0.8, 2.2)

	_body = Sprite2D.new()
	_body.texture = _art["planted_body"] as ImageTexture
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.offset = PLANTED_OFFSET
	add_child(_body)

	_glow = Sprite2D.new()
	_glow.texture = _art["planted_glow"] as ImageTexture
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow.offset = PLANTED_OFFSET
	_glow.material = Unlit.material()
	add_child(_glow)

	_light = NightLight.new()
	_light.position = Vector2(0.0, -7.0)
	_light.radius = 36
	_light.base_energy = 0.44
	_light.glow_color = _accent
	add_child(_light)

	_motes = CPUParticles2D.new()
	_motes.material = Unlit.material()
	_motes.z_index = 2
	_motes.position = Vector2(0.0, -7.0)
	_motes.amount = 7
	_motes.lifetime = 2.1
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(6.0, 4.0)
	_motes.direction = Vector2(0.0, -1.0)
	_motes.spread = 28.0
	_motes.initial_velocity_min = 2.5
	_motes.initial_velocity_max = 7.5
	_motes.gravity = Vector2.ZERO
	_motes.scale_amount_min = 1.0
	_motes.scale_amount_max = 1.4
	var ramp: Gradient = Gradient.new()
	ramp.colors = PackedColorArray([
		Color(_accent.r, _accent.g, _accent.b, 0.0),
		Color(_accent.r, _accent.g, _accent.b, 0.88),
		Color(_accent_mid.r, _accent_mid.g, _accent_mid.b, 0.65),
		Color(_accent_mid.r, _accent_mid.g, _accent_mid.b, 0.0),
	])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.72, 1.0])
	_motes.color_ramp = ramp
	_motes.emitting = true
	add_child(_motes)

	if trait_kind == "nocturnal":
		_nocturnal_open = _is_nocturnal_awake()
		_set_visual_mode("planted" if _nocturnal_open else "closed")


func _behaviors() -> Dictionary:
	var tbl: Dictionary = DataRegistry.table("shadow_fruits")
	return tbl.get("behaviors", {}) as Dictionary if tbl.get("behaviors") is Dictionary else {}


func _set_visual_mode(mode: String) -> void:
	if _visual_mode == mode or _body == null:
		return
	_visual_mode = mode
	match mode:
		"planted":
			_body.texture = _art["planted_body"] as ImageTexture
			_body.offset = PLANTED_OFFSET
			_glow.texture = _art["planted_glow"] as ImageTexture
			_glow.offset = PLANTED_OFFSET
			_glow.visible = true
			if _motes != null:
				_motes.emitting = true
		"hiding":
			_body.texture = _art["hiding_body"] as ImageTexture
			_body.offset = PLANTED_OFFSET
			_glow.visible = false
			if _motes != null:
				_motes.emitting = false
		"closed":
			_body.texture = _art["closed_body"] as ImageTexture
			_body.offset = PLANTED_OFFSET
			_glow.texture = _art["closed_glow"] as ImageTexture
			_glow.offset = PLANTED_OFFSET
			_glow.visible = true
			if _motes != null:
				_motes.emitting = false
		"half":
			_body.texture = _art["half_body"] as ImageTexture
			_body.offset = PLANTED_OFFSET
			_glow.texture = _art["half_glow"] as ImageTexture
			_glow.offset = PLANTED_OFFSET
			_glow.visible = true
			if _motes != null:
				_motes.emitting = true
		"hole":
			_body.texture = _art["hole_body"] as ImageTexture
			_body.offset = HOLE_OFFSET
			_glow.visible = false
			if _motes != null:
				_motes.emitting = false


func prompt() -> String:
	if _pulling or _collecting or _spent:
		return ""
	if trait_kind == "shy" and _shy_hidden:
		return ""
	if trait_kind == "nocturnal" and not _nocturnal_open:
		return "SCHLÄFT IM TAGLICHT"
	if trait_kind == "stubborn" and _stubborn_stage == 1:
		return "NOCHMAL ZIEHEN!"
	return "SCHATTENFRUCHT AUSREISSEN"


func reach_distance(from: Vector2) -> float:
	if trait_kind == "shy" and _shy_hidden:
		return INF
	return from.distance_to(global_position) - 18.0


func prompt_position() -> Vector2:
	return Vector2(0.0, -24.0)


func interact(player: Player) -> void:
	if _pulling or _collecting or _spent or thread_id.is_empty():
		return
	if player == null or not is_instance_valid(player):
		return
	if trait_kind == "shy" and _shy_hidden:
		return
	if trait_kind == "nocturnal" and not _nocturnal_open:
		# Gentle sleepy bud shiver + faint moonlight hint spark
		_sleep_shake_t = 0.42
		_play_sound(RUSTLE_WAV, -10.0, 0.78)
		_spawn_hand_sparkles(global_position + Vector2(0.0, -8.0), 4)
		return

	_pulling = true
	_pull_t = 0.0
	_collector = player
	set_focused(false)
	var toward: Vector2 = global_position - player.global_position
	var pull_dir: Vector2 = toward.normalized() if toward.length_squared() > 1.0 else Vector2.DOWN
	var base_pitch: float = 0.68 if (trait_kind == "stubborn" and _stubborn_stage == 0) else randf_range(0.76, 0.86)
	_play_sound(UPROOT_SOUNDS[absi(thread_id.hash()) % UPROOT_SOUNDS.size()], -8.0, base_pitch)

	var need_second_pull: bool = trait_kind == "stubborn" and _stubborn_stage == 0 and not _has_coop_pull_helper(player)
	var tid: String = thread_id
	player.begin_pull(pull_dir, func() -> void:
		if not is_instance_valid(self):
			return
		if need_second_pull:
			_pulling = false
			_stubborn_stage = 1
			var cfg: Dictionary = _behaviors()
			_stubborn_timer = float(cfg.get("stubborn_window_seconds", 6.5))
			_set_visual_mode("half")
			_body.skew = 0.0
			_glow.skew = 0.0
			_body.scale = Vector2(1.08, 0.92)
			_glow.scale = _body.scale
			_body.position = Vector2.ZERO
			_glow.position = Vector2.ZERO
			if is_instance_valid(player):
				player.add_shake(1.8)
			_play_sound(UPROOT_SOUNDS[absi(thread_id.hash() + 2) % UPROOT_SOUNDS.size()], -6.0, 0.84)
			_spawn_crumb_puff(10)
			_spawn_hand_sparkles(global_position + Vector2(0.0, -10.0), 6)
			return
		if is_instance_valid(player):
			player.add_shake(3.0 if trait_kind == "stubborn" else 2.2)
		var system: VeilThreads = VeilThreads.of(get_tree())
		if system != null:
			system.request_collect(tid))


func _has_coop_pull_helper(puller: Player) -> bool:
	var cfg: Dictionary = _behaviors()
	var max_d: float = float(cfg.get("stubborn_coop_assist_tiles", 3.5)) * 16.0
	for p: Player in Player.all:
		if p != puller and is_instance_valid(p) and p.health != null and p.health.current > 0.0:
			if p.global_position.distance_to(global_position) <= max_d:
				return true
	return false


func _is_nocturnal_awake() -> bool:
	var cfg: Dictionary = _behaviors()
	var min_night: float = float(cfg.get("nocturnal_night_min", 0.35))
	if TimeManager.night_amount() >= min_night:
		return true
	if not is_inside_tree():
		return false
	var light_px: float = float(cfg.get("nocturnal_light_tiles", 4.5)) * 16.0
	for grp: String in ["campfires", "spell_zones"]:
		for n: Node in get_tree().get_nodes_in_group(grp):
			if n is Node2D and (n as Node2D).global_position.distance_to(global_position) <= light_px:
				return true
	# Also wake if a player with Sporenlaterne milestone stands close by
	var vt: VeilThreads = VeilThreads.of(get_tree())
	if vt != null and vt.night_light_bonus() > 0.0:
		for p: Player in Player.all:
			if is_instance_valid(p) and p.global_position.distance_to(global_position) <= light_px * 0.72:
				return true
	return false


func play_collect(collector: Player = null) -> void:
	if _collecting or _spent:
		return
	_pulling = false
	_collecting = true
	_collect_t = 0.0
	_chime_played = false
	_pocket_played = false
	if collector != null and is_instance_valid(collector):
		_collector = collector
	set_focused(false)

	# Swap buried crown to freshly uprooted dark soil crater
	_set_visual_mode("hole")
	_body.skew = 0.0
	_body.scale = Vector2.ONE
	_body.position = Vector2.ZERO
	_light.base_energy = 0.22

	# Juicy uproot audio + dirt clods + bioluminescent spore burst
	_play_sound(UPROOT_SOUNDS[absi(thread_id.hash() + 1) % UPROOT_SOUNDS.size()], -4.0, randf_range(1.04, 1.16))
	_play_sound(BURST_WAV, -7.0, randf_range(1.12, 1.24))
	_play_sound(POP_WAV, -4.0, randf_range(0.95, 1.08))
	_spawn_soil_and_spore_burst()
	if get_parent() != null:
		ShockRing.burst(get_parent(), global_position + Vector2(0.0, -4.0), 42.0 if trait_kind == "stubborn" else 34.0, 0.52)

	# Spawn the uprooted living Schattenfrucht that hops into Ellie's hand
	_held_root = Node2D.new()
	_held_root.z_index = 25
	_held_root.global_position = global_position + Vector2(0.0, -6.0)
	var parent_world: Node = get_parent() if get_parent() != null else self
	parent_world.add_child(_held_root)

	_held_body = Sprite2D.new()
	_held_body.texture = _fruit_bodies[2]
	_held_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held_root.add_child(_held_body)

	_held_glow = Sprite2D.new()
	_held_glow.texture = _fruit_glows[2]
	_held_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held_glow.material = Unlit.material()
	_held_root.add_child(_held_glow)

	_held_light = NightLight.new()
	_held_light.radius = 44
	_held_light.base_energy = 0.72
	_held_light.glow_color = _accent
	_held_root.add_child(_held_light)


func _hand_anchor() -> Vector2:
	if _collector != null and is_instance_valid(_collector):
		var f: Vector2 = _collector.facing
		if f.length_squared() < 0.01:
			f = Vector2.DOWN
		else:
			f = f.normalized()
		return _collector.global_position + Vector2(f.x * 11.0, -23.0 + f.y * 4.5)
	return global_position + Vector2(0.0, -26.0)


func _pocket_anchor() -> Vector2:
	if _collector != null and is_instance_valid(_collector):
		var f: Vector2 = _collector.facing
		var side_x: float = -3.0 if f.x >= 0.0 else 3.0
		return _collector.global_position + Vector2(side_x, -15.0)
	return global_position + Vector2(0.0, -14.0)


func _nearest_player_dist() -> float:
	var best: float = INF
	for p: Player in Player.all:
		if is_instance_valid(p) and p.health != null and p.health.current > 0.0:
			best = minf(best, p.global_position.distance_to(global_position))
	return best


func _step_archetype(delta: float) -> void:
	var cfg: Dictionary = _behaviors()

	if trait_kind == "shy":
		var base_spook: float = float(cfg.get("shy_spook_tiles", 5.5)) * 16.0
		var vt: VeilThreads = VeilThreads.of(get_tree())
		var stealth_scale: float = vt.stealth_spook_scale() if vt != null else 1.0
		var spook_px: float = base_spook * stealth_scale
		var run_spd: float = float(cfg.get("shy_run_speed", 52.0))
		var spooked_now: bool = false
		for p: Player in Player.all:
			if not is_instance_valid(p) or p.health == null or p.health.current <= 0.0:
				continue
			if p.global_position.distance_to(global_position) > spook_px:
				continue
			var sneaking: bool = p.stealth != null and p.stealth.sneaking
			var loud: bool = (not sneaking) and (p.velocity.length() > run_spd)
			if loud:
				spooked_now = true
				break
		if spooked_now:
			if not _shy_hidden:
				_shy_hidden = true
				_shy_quiet_t = 0.0
				set_focused(false)
				_set_visual_mode("hiding")
				_play_sound(RUSTLE_WAV, -7.0, randf_range(1.15, 1.28))
				_spawn_crumb_puff(6)
			else:
				_shy_quiet_t = 0.0
		elif _shy_hidden:
			_shy_quiet_t += delta
			if _shy_quiet_t >= float(cfg.get("shy_recover_seconds", 1.4)):
				_shy_hidden = false
				_set_visual_mode("planted")
				_play_sound(RUSTLE_WAV, -11.0, randf_range(0.96, 1.06))
				_spawn_crumb_puff(3)
	elif trait_kind == "nocturnal":
		var awake: bool = _is_nocturnal_awake()
		if awake != _nocturnal_open:
			_nocturnal_open = awake
			_set_visual_mode("planted" if awake else "closed")
			if awake:
				_play_sound(CHIME_WAV, -11.0, _chime_pitch)
				_spawn_hand_sparkles(global_position + Vector2(0.0, -8.0), 6)
	elif trait_kind == "stubborn" and _stubborn_stage == 1:
		_stubborn_timer -= delta
		if _stubborn_timer <= 0.0:
			_stubborn_stage = 0
			_set_visual_mode("planted")
			_play_sound(RUSTLE_WAV, -9.0, 0.78)
			_spawn_crumb_puff(5)


func _step_ambient_trails(delta: float) -> void:
	if (trait_kind == "shy" and _shy_hidden) or (trait_kind == "nocturnal" and not _nocturnal_open):
		return
	var d_px: float = _nearest_player_dist()
	var cfg: Dictionary = _behaviors()
	var hear_px: float = float(cfg.get("ambient_hear_tiles", 11.0)) * 16.0
	var close_px: float = float(cfg.get("ambient_close_tiles", 5.0)) * 16.0
	var wind_px: float = float(cfg.get("ambient_wind_tiles", 9.0)) * 16.0

	if d_px <= hear_px:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			var close_t: float = clampf(1.0 - (d_px - close_px) / maxf(hear_px - close_px, 16.0), 0.0, 1.0)
			_ping_timer = lerpf(4.6, 2.0, close_t) + randf_range(-0.35, 0.45)
			var vol: float = lerpf(-21.0, -13.0, close_t)
			_play_sound(CHIME_WAV, vol, _chime_pitch * randf_range(0.99, 1.01))
			_play_sound(RUSTLE_WAV, vol - 2.0, randf_range(0.95, 1.08))

	if d_px <= wind_px:
		_wind_spore_timer -= delta
		if _wind_spore_timer <= 0.0:
			_wind_spore_timer = randf_range(2.0, 3.2)
			_spawn_wind_spore_wisp()


func _spawn_wind_spore_wisp() -> void:
	var parent_n: Node = get_parent() if get_parent() != null else self
	var wdir: Vector2 = Vector2(1.0, -0.25)
	if WorldWind.current != null:
		var wd: Vector2 = WorldWind.current.direction
		if wd.length_squared() > 0.01:
			wdir = (wd.normalized() + Vector2(0.0, -0.35)).normalized()
	var sp: CPUParticles2D = CPUParticles2D.new()
	sp.material = Unlit.material()
	sp.position = global_position + Vector2(0.0, -9.0)
	sp.z_index = 8
	sp.one_shot = true
	sp.explosiveness = 0.65
	sp.amount = 2
	sp.lifetime = 1.6
	sp.direction = wdir
	sp.spread = 22.0
	sp.initial_velocity_min = 14.0
	sp.initial_velocity_max = 26.0
	sp.gravity = Vector2(0.0, -6.0)
	sp.scale_amount_min = 1.0
	sp.scale_amount_max = 1.5
	var ramp: Gradient = Gradient.new()
	ramp.colors = PackedColorArray([
		Color(_accent.r, _accent.g, _accent.b, 0.0),
		Color(_accent.r, _accent.g, _accent.b, 0.92),
		Color(_accent_mid.r, _accent_mid.g, _accent_mid.b, 0.0),
	])
	ramp.offsets = PackedFloat32Array([0.0, 0.28, 1.0])
	sp.color_ramp = ramp
	sp.emitting = true
	parent_n.add_child(sp)
	get_tree().create_timer(1.85).timeout.connect(func() -> void:
		if is_instance_valid(sp):
			sp.queue_free())


func _process(delta: float) -> void:
	_time += delta
	var night: float = TimeManager.night_amount()

	if _collecting:
		_step_collect_sequence(delta)
		return

	if _spent:
		return

	if _pulling:
		_pull_t += delta
		var u: float = clampf(_pull_t / Player.PULL_GRAB_TIME, 0.0, 1.0)
		var tremor: float = sin(_pull_t * 68.0) * (0.04 + 0.14 * u) + sin(_pull_t * 27.0) * 0.04
		var lift: float = -u * 3.0
		var stretch_y: float = 1.0 + u * 0.16
		var squash_x: float = 1.0 - u * 0.08
		_body.skew = tremor
		_glow.skew = tremor
		_body.scale = Vector2(squash_x, stretch_y)
		_glow.scale = Vector2(squash_x, stretch_y)
		var jitter_x: float = roundf(sin(_pull_t * 84.0) * (0.5 + u * 1.1))
		_body.position = Vector2(jitter_x, roundf(lift))
		_glow.position = _body.position
		_glow.modulate = Color(1.15, 1.15, 1.15, 1.0)
		_light.base_energy = lerpf(0.45, 0.85, u)
		if int(_pull_t * 14.0) != int((_pull_t - delta) * 14.0):
			_spawn_crumb_puff(3)
		if _pull_t > 1.05:
			_pulling = false
			_body.skew = 0.0
			_glow.skew = 0.0
			_body.scale = Vector2.ONE
			_glow.scale = Vector2.ONE
			_body.position = Vector2.ZERO
			_glow.position = Vector2.ZERO
		return

	_step_archetype(delta)
	_step_ambient_trails(delta)

	if _sleep_shake_t > 0.0:
		_sleep_shake_t = maxf(_sleep_shake_t - delta, 0.0)
		var sh: float = sin(_sleep_shake_t * 58.0) * 0.09 * (_sleep_shake_t / 0.42)
		_body.skew = sh
		_glow.skew = sh
		return

	# Idle animation depending on archetype visual mode
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.6 + _phase)
	if _visual_mode == "hiding":
		var shiver: float = sin(_time * 24.0 + _phase) * 0.04
		_body.scale = Vector2.ONE
		_body.skew = shiver
		_light.base_energy = 0.06
		return
	if _visual_mode == "closed":
		var slow_b: float = sin(_time * 1.4 + _phase) * 0.025
		_body.scale = Vector2(1.0 - slow_b * 0.5, 1.0 + slow_b)
		_glow.scale = _body.scale
		_body.skew = 0.0
		_glow.skew = 0.0
		_glow.modulate = Color(1.0, 1.0, 1.0, 0.30 + 0.14 * pulse)
		_light.base_energy = 0.12
		return
	if _visual_mode == "half":
		var strain: float = sin(_time * 16.0 + _phase) * 0.07
		_body.scale = Vector2(1.0 + sin(_time * 11.0) * 0.05, 1.0 - sin(_time * 11.0) * 0.05)
		_glow.scale = _body.scale
		_body.skew = strain
		_glow.skew = strain
		_glow.modulate = Color(1.15, 1.15, 1.15, 1.0)
		_light.base_energy = 0.65 + 0.15 * pulse
		return

	var breath_sy: float = 1.0 + sin(_time * 2.6 + _phase) * 0.045
	var breath_sx: float = 1.0 - sin(_time * 2.6 + _phase) * 0.025
	var sway_amp: float = 0.06 if trait_kind == "shy" else 0.035
	var sway: float = sin(_time * (2.6 if trait_kind == "shy" else 1.9) + _phase * 1.3) * sway_amp
	_body.scale = Vector2(breath_sx, breath_sy)
	_glow.scale = Vector2(breath_sx, breath_sy)
	_body.skew = sway
	_glow.skew = sway
	var glow_a: float = lerpf(0.64, 0.98, maxf(night, 0.35)) * (0.84 + 0.16 * pulse)
	_glow.modulate = Color(1.0, 1.0, 1.0, glow_a)
	_light.base_energy = lerpf(0.24, 0.56, night) * (0.86 + 0.14 * pulse)


func _step_collect_sequence(delta: float) -> void:
	_collect_t += delta
	var t: float = _collect_t
	var hand_pos: Vector2 = _hand_anchor()
	var pocket_pos: Vector2 = _pocket_anchor()
	var start_pos: Vector2 = global_position + Vector2(0.0, -6.0)

	if _held_root != null and is_instance_valid(_held_root):
		if t < POP_DURATION:
			var u: float = clampf(t / POP_DURATION, 0.0, 1.0)
			var ease_u: float = 1.0 - pow(1.0 - u, 2.2)
			var arc_y: float = -sin(u * PI) * (24.0 if trait_kind == "stubborn" else 20.0)
			_held_root.global_position = start_pos.lerp(hand_pos, ease_u) + Vector2(0.0, arc_y)
			var sy: float = lerpf(1.32, 0.94, u)
			var sx: float = lerpf(0.76, 1.08, u)
			_held_root.scale = Vector2(sx, sy)
			_held_root.rotation = sin(u * PI) * 0.22 * (1.0 if (absi(thread_id.hash()) % 2) == 0 else -1.0)
			_set_held_frame(2 if u < 0.65 else 0)
		elif t < HAND_END:
			if not _chime_played:
				_chime_played = true
				_play_sound(CHIME_WAV, -4.0, _chime_pitch)
				_spawn_hand_sparkles(hand_pos, 7)
			var ht: float = t - POP_DURATION
			var h_dur: float = HAND_END - POP_DURATION
			var hu: float = clampf(ht / h_dur, 0.0, 1.0)
			var seq: Array[int] = [1, 2, 3, 0, 1, 2, 3, 2, 0]
			var idx: int = mini(int(hu * float(seq.size())), seq.size() - 1)
			_set_held_frame(seq[idx])
			var energy_mul: float = 1.25 if trait_kind == "shy" else 1.0
			var hop: float = absf(sin(ht * 10.5 * energy_mul)) * 4.2 * (1.0 - hu * 0.25)
			var wiggle_x: float = sin(ht * 19.0 * energy_mul) * 1.4
			var rock: float = sin(ht * 16.5 * energy_mul) * 0.18
			var sq: float = sin(ht * 21.0) * 0.11
			_held_root.global_position = (hand_pos + Vector2(wiggle_x, -hop)).round()
			_held_root.scale = Vector2(1.0 + sq, 1.0 - sq)
			_held_root.rotation = rock
			var pulse_g: float = 1.0 + 0.35 * absf(sin(ht * 12.0))
			_held_glow.modulate = Color(pulse_g, pulse_g, pulse_g, 1.0)
			_held_light.base_energy = 0.68 + 0.24 * absf(sin(ht * 12.0))
			if int(ht * 6.0) != int((ht - delta) * 6.0):
				_spawn_hand_sparkles(_held_root.global_position, 2)
		elif t < POCKET_END:
			if not _pocket_played:
				_pocket_played = true
				_play_sound(POCKET_WAV, -3.5, randf_range(1.04, 1.14))
			var pu: float = clampf((t - HAND_END) / (POCKET_END - HAND_END), 0.0, 1.0)
			var ease_p: float = pu * pu * (3.0 - 2.0 * pu)
			var arc_p: float = -sin(pu * PI) * 8.0
			_held_root.global_position = hand_pos.lerp(pocket_pos, ease_p) + Vector2(0.0, arc_p)
			var sc: float = lerpf(1.0, 0.14, ease_p)
			_held_root.scale = Vector2(sc * 0.85, sc * 1.18)
			_held_root.rotation = lerpf(_held_root.rotation, 0.35, ease_p)
			_held_body.modulate.a = 1.0 - smoothstep(0.62, 1.0, pu)
			_held_glow.modulate.a = 1.0 - smoothstep(0.68, 1.0, pu)
			_held_light.base_energy = lerpf(0.65, 0.0, pu)
			_set_held_frame(2)
		else:
			_spawn_hand_sparkles(pocket_pos, 9)
			_held_root.queue_free()
			_held_root = null
			_held_body = null
			_held_glow = null
			_held_light = null

	if t > POCKET_END:
		var fu: float = clampf((t - POCKET_END) / (HOLE_FADE_END - POCKET_END), 0.0, 1.0)
		_body.modulate.a = 1.0 - smoothstep(0.55, 1.0, fu)
		_light.base_energy = lerpf(0.18, 0.0, fu)
		if t >= HOLE_FADE_END:
			_spent = true
			queue_free()


func _set_held_frame(frame_i: int) -> void:
	var idx: int = clampi(frame_i, 0, _fruit_bodies.size() - 1)
	if _held_body != null:
		_held_body.texture = _fruit_bodies[idx]
	if _held_glow != null:
		_held_glow.texture = _fruit_glows[idx]


func _spawn_crumb_puff(count: int) -> void:
	var parent_n: Node = get_parent() if get_parent() != null else self
	var p: CPUParticles2D = CPUParticles2D.new()
	p.position = global_position + Vector2(0.0, -2.0)
	p.z_index = 4
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = count
	p.lifetime = 0.36
	p.direction = Vector2(0.0, -1.0)
	p.spread = 65.0
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 34.0
	p.gravity = Vector2(0.0, 140.0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.8
	p.color = SOIL_COLORS[randi() % SOIL_COLORS.size()]
	p.emitting = true
	parent_n.add_child(p)
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


func _spawn_soil_and_spore_burst() -> void:
	var parent_n: Node = get_parent() if get_parent() != null else self
	var soil: CPUParticles2D = CPUParticles2D.new()
	soil.position = global_position + Vector2(0.0, -3.0)
	soil.z_index = 6
	soil.one_shot = true
	soil.explosiveness = 0.94
	soil.amount = 24 if trait_kind == "stubborn" else 18
	soil.lifetime = 0.58
	soil.direction = Vector2(0.0, -1.0)
	soil.spread = 72.0
	soil.initial_velocity_min = 28.0
	soil.initial_velocity_max = 76.0 if trait_kind == "stubborn" else 68.0
	soil.gravity = Vector2(0.0, 185.0)
	soil.scale_amount_min = 1.2
	soil.scale_amount_max = 2.4
	var s_ramp: Gradient = Gradient.new()
	s_ramp.colors = PackedColorArray([SOIL_COLORS[2], SOIL_COLORS[1], Color(SOIL_COLORS[0].r, SOIL_COLORS[0].g, SOIL_COLORS[0].b, 0.0)])
	s_ramp.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	soil.color_ramp = s_ramp
	soil.emitting = true
	parent_n.add_child(soil)

	var spores: CPUParticles2D = CPUParticles2D.new()
	spores.material = Unlit.material()
	spores.position = global_position + Vector2(0.0, -6.0)
	spores.z_index = 12
	spores.one_shot = true
	spores.explosiveness = 0.88
	spores.amount = 20 if trait_kind == "stubborn" else 16
	spores.lifetime = 0.82
	spores.direction = Vector2(0.0, -1.0)
	spores.spread = 110.0
	spores.initial_velocity_min = 14.0
	spores.initial_velocity_max = 42.0
	spores.gravity = Vector2(0.0, -18.0)
	spores.scale_amount_min = 1.0
	spores.scale_amount_max = 2.0
	var g_ramp: Gradient = Gradient.new()
	g_ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		_accent,
		Color(_accent_mid.r, _accent_mid.g, _accent_mid.b, 0.0),
	])
	g_ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	spores.color_ramp = g_ramp
	spores.emitting = true
	parent_n.add_child(spores)

	get_tree().create_timer(1.1).timeout.connect(func() -> void:
		if is_instance_valid(soil):
			soil.queue_free()
		if is_instance_valid(spores):
			spores.queue_free())


func _spawn_hand_sparkles(world_pos: Vector2, count: int) -> void:
	var parent_n: Node = get_parent() if get_parent() != null else self
	var sp: CPUParticles2D = CPUParticles2D.new()
	sp.material = Unlit.material()
	sp.position = world_pos
	sp.z_index = 26
	sp.one_shot = true
	sp.explosiveness = 0.9
	sp.amount = count
	sp.lifetime = 0.48
	sp.direction = Vector2(0.0, -1.0)
	sp.spread = 180.0
	sp.initial_velocity_min = 8.0
	sp.initial_velocity_max = 24.0
	sp.gravity = Vector2(0.0, -10.0)
	sp.scale_amount_min = 1.0
	sp.scale_amount_max = 1.6
	var r: Gradient = Gradient.new()
	r.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.95), _accent, Color(_accent.r, _accent.g, _accent.b, 0.0)])
	r.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	sp.color_ramp = r
	sp.emitting = true
	parent_n.add_child(sp)
	get_tree().create_timer(0.65).timeout.connect(func() -> void:
		if is_instance_valid(sp):
			sp.queue_free())


func _play_sound(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if stream == null or not is_inside_tree():
		return
	var audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	audio.stream = stream
	audio.volume_db = vol_db
	audio.pitch_scale = pitch
	audio.max_distance = 360.0
	audio.finished.connect(audio.queue_free)
	add_child(audio)
	audio.play()


func _exit_tree() -> void:
	if _held_root != null and is_instance_valid(_held_root):
		_held_root.queue_free()
		_held_root = null
