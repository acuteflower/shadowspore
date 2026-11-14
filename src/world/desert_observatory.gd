class_name DesertObservatory
extends Node2D
## Die Zenitwarte ("Das Zerbrochene Himmelswerk") — main exterior landmark of Sonnenquarz-Öde (Region 34).
## Multi-level ruins complex (L0..L3) north of the ancient caravan road:
##   I.   Meridian Forecourt & Split Ecliptic Gate (L0, 948,143)
##   II.  East Bastion 180-deg Monumental Sundial & Gnomon (L2, 969,161) — real-time shadow & Noon Zenith Pulse
##   III. Floating Causeway & 6 Crystal Wind-Harp Pillars (L1 -> L2 saddle) — wind shimmer & spell recharge aura
##   IV.  Summit Heart Rotunda, Astral Plaza, Sealed Star-Portal, 12-frame Armillary Orbits,
##        3 Telescope Lenses, Night Starlight Beam, Night Ghost-Dome & Arcane Lightning Surge (L3, 908,175)
##   V.   Sunken Star-Mirror Basin (cooling mist + celestial shader), Polar Ocular Vista (MapDiscovery RPC),
##        Open-Air Prism Altar & Collapsed Star-Globe (L3 west/south terraces)

const ART_META_PATH: String = "res://data/desert_observatory_art.json"
const TEX_DIR: String = "res://assets/props/observatory/"
const SFX_DIR: String = "res://assets/audio/observatory/"
const STAR_MIRROR_SHADER_PATH: String = "res://assets/shaders/desert_star_mirror.gdshader"
const BEAM_SHADER_PATH: String = "res://assets/shaders/observatory_beam.gdshader"

const GATE_TILE: Vector2i = Vector2i(948, 143)
const SUNDIAL_TILE: Vector2i = Vector2i(969, 161)
const ROTUNDA_TILE: Vector2i = Vector2i(908, 175)
const MIRROR_TILE: Vector2i = Vector2i(884, 171)
const OCULAR_TILE: Vector2i = Vector2i(880, 159)
const PRISM_ALTAR_TILE: Vector2i = Vector2i(918, 187)
const GLOBE_TILE: Vector2i = Vector2i(926, 193)

## Verified flat L1/L2 saddle tiles along the causeway ascent ([962,176] -> [936,163] -> [920,159] -> L3)
const CAUSEWAY_PILLAR_SPECS: Array[Array] = [
	[Vector2i(951, 162), 0],
	[Vector2i(950, 170), 1],
	[Vector2i(943, 161), 0],
	[Vector2i(943, 170), 1],
	[Vector2i(931, 160), 0],
	[Vector2i(932, 170), 1],
]

const PORTAL_YSORT_SHIFT: Vector2 = Vector2(0.0, -16.0)

## Decorative levitating shards orbiting cliff rims (offset in tiles from world anchors, non-blocking)
const DEBRIS_SPOTS: Array[Array] = [
	[Vector2(908.0 * 16.0 - 152.0, 175.0 * 16.0 - 94.0), 0, 16.0],
	[Vector2(908.0 * 16.0 + 154.0, 175.0 * 16.0 - 76.0), 1, 18.0],
	[Vector2(908.0 * 16.0 - 118.0, 175.0 * 16.0 + 96.0), 2, 12.0],
	[Vector2(947.0 * 16.0 + 8.0, 160.0 * 16.0 - 18.0), 3, 15.0],
	[Vector2(947.0 * 16.0 + 8.0, 170.0 * 16.0 + 14.0), 4, 14.0],
	[Vector2(969.0 * 16.0 + 116.0, 161.0 * 16.0 - 24.0), 3, 14.0],
	[Vector2(880.0 * 16.0 - 34.0, 159.0 * 16.0 - 14.0), 0, 17.0],
	[Vector2(926.0 * 16.0 + 34.0, 193.0 * 16.0 + 10.0), 4, 10.0],
]

const OPTICAL_AXIS: Vector2 = Vector2(0.78, -0.62)

var _world: Node2D
var _art_meta: Dictionary = {}
var _textures: Dictionary = {}
var _sfx_streams: Dictionary = {}

var _gate_pos: Vector2 = Vector2.ZERO
var _sundial_pos: Vector2 = Vector2.ZERO
var _rotunda_pos: Vector2 = Vector2.ZERO
var _mirror_pos: Vector2 = Vector2.ZERO
var _ocular_pos: Vector2 = Vector2.ZERO
var _altar_pos: Vector2 = Vector2.ZERO
var _globe_pos: Vector2 = Vector2.ZERO
var _causeway_center: Vector2 = Vector2.ZERO

var _night_amount: float = 0.0
var _time: float = 0.0
var _surge_timer: float = 0.0
var _noon_pulsed_day: bool = false
var _harp_audio_cd: float = 0.0
var _last_tick_step: int = -1

var _surface_patch: ObservatorySurfacePatch
var _ysort_owned: Array[Node] = []
var _night_sprites: Array[Dictionary] = [] ## [{sprite: Sprite2D, base: float, night: float}]
var _conduits: Array[ObservatoryConduit] = []

var _armillary_sprite: Sprite2D
var _armillary_glow: Sprite2D
var _armillary_frames: int = 12
var _armillary_frame_f: float = 0.0
var _armillary_cycle_t: float = 0.0
var _armillary_catch_t: float = 0.0
var _armillary_sparks: CPUParticles2D

var _lens_nodes: Array[Dictionary] = []
var _beam_mat: ShaderMaterial
var _ghost_dome: NightGhostDome
var _star_mirror_mat: ShaderMaterial
var _sundial_overlay: SundialOverlay
var _gate_ocular: Sprite2D
var _gate_ocular_glow: Sprite2D
var _gate_ocular_base_y: float = 0.0
var _gate_beam_glint: Node2D
var _portal_locks_fx: PortalLocksFx
var _prism_fx: PrismAltarFx
var _harp_overlays: Array[WindHarpOverlay] = []
var _debris_entries: Array[Dictionary] = []
var _vista_discovered: bool = false


func _ready() -> void:
	y_sort_enabled = true
	add_to_group("desert_observatory")
	add_to_group("quest_actors")
	add_to_group("resonance_obelisks")
	add_to_group("desert_spell_listeners")
	add_to_group("desert_arcane_listeners")
	add_to_group("night_lights")
	tree_exiting.connect(_cleanup_owned_nodes)


## Initializes the Observatory across Region 34 and returns `{"blocked": ..., "stones": ...}`
## for WorldLevel so procedural foliage/boulders/ruins never collide with its courts or pillars.
func setup(world: Node2D, _prior_blocked: Dictionary) -> Dictionary:
	_world = world
	_load_art_meta()
	_preload_sfx()

	_gate_pos = _tile_center(GATE_TILE)
	_sundial_pos = _tile_center(SUNDIAL_TILE)
	_rotunda_pos = _tile_center(ROTUNDA_TILE)
	_mirror_pos = _tile_center(MIRROR_TILE)
	_ocular_pos = _tile_center(OCULAR_TILE)
	_altar_pos = _tile_center(PRISM_ALTAR_TILE)
	_globe_pos = _tile_center(GLOBE_TILE)
	_causeway_center = _tile_center(Vector2i(942, 165))

	var ysort_parent: Node2D = self
	if world != null:
		var props_node: Node2D = world.get_node_or_null("Props") as Node2D
		if props_node != null:
			ysort_parent = props_node

	_build_zone_gate(ysort_parent)
	_build_zone_sundial(ysort_parent)
	_build_zone_causeway(ysort_parent)
	_build_zone_rotunda(ysort_parent)
	_build_zone_terraces(ysort_parent)
	_build_conduits()
	_register_surface_patch()
	set_night(TimeManager.night_amount() if TimeManager != null else 0.0)

	return _compute_reserved_cells()


func _cleanup_owned_nodes() -> void:
	if _surface_patch != null:
		Terrain.patches.erase(_surface_patch)
		_surface_patch = null
	for n: Node in _ysort_owned:
		if is_instance_valid(n) and n.get_parent() != self:
			n.queue_free()
	_ysort_owned.clear()


func _process(delta: float) -> void:
	_time += delta
	_surge_timer = maxf(0.0, _surge_timer - delta)
	_harp_audio_cd = maxf(0.0, _harp_audio_cd - delta)

	var night: float = TimeManager.night_amount() if TimeManager != null else _night_amount
	_night_amount = night
	var tod: float = TimeManager.time_of_day if TimeManager != null else 0.35
	var sun: float = TimeManager.sun_amount() if TimeManager != null else maxf(0.0, 1.0 - night)
	var storm: float = WeatherManager.current.desert_arcane_storm if WeatherManager.current != null else 0.0
	var res_wind: float = WeatherManager.current.desert_resonance if WeatherManager.current != null else 0.0

	# Zenith Noon Pulse around tod == 0.50
	var near_noon: bool = absf(tod - 0.50) < 0.022
	if near_noon and not _noon_pulsed_day:
		_noon_pulsed_day = true
		_surge_timer = maxf(_surge_timer, 7.0)
		_trigger_all_conduits()
		_play_sfx("noon_chime", _sundial_pos, -4.0, 0.02, 720.0)
	elif absf(tod - 0.50) > 0.08:
		_noon_pulsed_day = false

	# Zone I floating gate ocular bob
	if is_instance_valid(_gate_ocular):
		var bob: float = roundf(sin(_time * 1.45) * 2.5)
		_gate_ocular.position.y = _gate_ocular_base_y + bob
		if is_instance_valid(_gate_ocular_glow):
			_gate_ocular_glow.position.y = _gate_ocular.position.y
	if is_instance_valid(_gate_beam_glint):
		_gate_beam_glint.queue_redraw()

	# Zone II Sundial dynamic shadow & solar focus
	if is_instance_valid(_sundial_overlay):
		_sundial_overlay.update_solar(tod, sun, _surge_timer > 0.0)

	# Zone III Wind-Harps shimmer & gentle wind harmonic
	for harp: WindHarpOverlay in _harp_overlays:
		if is_instance_valid(harp):
			harp.update_wind(_time, res_wind, _surge_timer > 0.0)
	if _harp_audio_cd <= 0.0 and (res_wind > 0.20 or storm > 0.25):
		var near_p: Player = _nearest_player(_causeway_center, 150.0)
		if near_p != null:
			_harp_audio_cd = 9.5
			_play_sfx("wind_harp", near_p.global_position, -7.0, 0.08, 420.0)

	# Floating debris bob & ground shadow breathing
	for entry: Dictionary in _debris_entries:
		var spr: Sprite2D = entry["sprite"] as Sprite2D
		var gl: Sprite2D = entry["glow"] as Sprite2D
		var base_y: float = float(entry["base_y"])
		var phase: float = float(entry["phase"])
		var bob_d: float = roundf(sin(_time * 1.6 + phase) * 2.5)
		if is_instance_valid(spr):
			spr.position.y = base_y + bob_d
		if is_instance_valid(gl):
			gl.position.y = base_y + bob_d

	# Zone IV 12-frame Armillary Orbits + 13.5s Mechanical Catch
	if is_instance_valid(_armillary_sprite):
		_armillary_cycle_t += delta
		if _armillary_catch_t > 0.0:
			_armillary_catch_t = maxf(0.0, _armillary_catch_t - delta)
			# Micro-chatter during mechanical catch
			var jitter: float = -1.0 if int(_armillary_catch_t * 24.0) % 2 == 0 else 0.0
			_armillary_sprite.position.x = jitter
			_armillary_glow.position.x = jitter
		elif _armillary_cycle_t >= 13.5:
			_armillary_cycle_t = 0.0
			_armillary_catch_t = 0.45
			_armillary_frame_f = float(posmod(int(floorf(_armillary_frame_f)) - 1, _armillary_frames))
			if is_instance_valid(_armillary_sparks):
				_armillary_sparks.restart()
			_play_sfx("gear_catch", _rotunda_pos, -5.0, 0.04, 560.0)
		else:
			_armillary_sprite.position.x = 0.0
			_armillary_glow.position.x = 0.0
			var speed_fps: float = 5.5 + storm * 4.5 + (3.0 if _surge_timer > 0.0 else 0.0)
			_armillary_frame_f = fmod(_armillary_frame_f + delta * speed_fps, float(_armillary_frames))
		var fi: int = posmod(int(floorf(_armillary_frame_f)), _armillary_frames)
		_armillary_sprite.frame = fi
		_armillary_glow.frame = fi
		var tick_step: int = fi / 3
		if tick_step != _last_tick_step and _armillary_catch_t <= 0.0:
			_last_tick_step = tick_step
			if _nearest_player(_rotunda_pos, 260.0) != null:
				_play_sfx("gear_tick", _rotunda_pos, -15.0, 0.06, 320.0)

	# Telescope lens harmonic bob along SW->NE axis
	for lens: Dictionary in _lens_nodes:
		var l_spr: Sprite2D = lens["sprite"] as Sprite2D
		var l_glow: Sprite2D = lens["glow"] as Sprite2D
		var l_base: Vector2 = lens["base"] as Vector2
		var l_ph: float = float(lens["phase"])
		var l_y: float = roundf(sin(_time * 1.35 + l_ph) * 2.0)
		if is_instance_valid(l_spr):
			l_spr.position = l_base + Vector2(0.0, l_y)
		if is_instance_valid(l_glow):
			l_glow.position = l_base + Vector2(0.0, l_y)

	# Volumetric Starlight Beam & Night Ghost-Dome
	if _beam_mat != null:
		var surge_add: float = 0.55 if _surge_timer > 0.0 else 0.0
		var beam_strength: float = clampf(night * 1.05 + storm * 0.45 + surge_add, 0.0, 1.45)
		_beam_mat.set_shader_parameter("strength", beam_strength)
		_beam_mat.set_shader_parameter("time", _time)
	if is_instance_valid(_ghost_dome):
		_ghost_dome.update_state(_time, night, storm, _surge_timer > 0.0)

	# Zone V Star-Mirror Shader & FX
	if _star_mirror_mat != null:
		_star_mirror_mat.set_shader_parameter("night", night)
		_star_mirror_mat.set_shader_parameter("time", _time)
		_star_mirror_mat.set_shader_parameter("storm", storm)
	if is_instance_valid(_portal_locks_fx):
		_portal_locks_fx.tick(delta, _surge_timer > 0.0)
	if is_instance_valid(_prism_fx):
		_prism_fx.tick(delta)

	_refresh_night_glow(night, storm)


## Group contract `"night_lights"`
func set_night(amount: float) -> void:
	_night_amount = clampf(amount, 0.0, 1.0)
	var storm: float = WeatherManager.current.desert_arcane_storm if WeatherManager.current != null else 0.0
	_refresh_night_glow(_night_amount, storm)


func _refresh_night_glow(night: float, storm: float) -> void:
	var boost: float = clampf(storm * 0.45 + (0.55 if _surge_timer > 0.0 else 0.0), 0.0, 0.85)
	for entry: Dictionary in _night_sprites:
		var spr: Sprite2D = entry["sprite"] as Sprite2D
		if is_instance_valid(spr):
			var a: float = lerpf(float(entry["base"]), float(entry["night"]), night) + boost * 0.45
			spr.modulate.a = clampf(a, 0.0, 1.35)
	var surging: bool = _surge_timer > 0.0
	for c: ObservatoryConduit in _conduits:
		if is_instance_valid(c):
			c.update_glow_state(night, storm, surging)


## Group contract `"quest_actors"` -> world map icon in Region 34
func map_marker() -> Dictionary:
	return {"id": "zenitwarte", "position": _rotunda_pos}


## Group contract `"desert_observatory"` -> cooling shade / star-mirror aura in DesertHeat
func is_cooling_near(pos: Vector2) -> bool:
	if pos.distance_squared_to(_mirror_pos) <= 132.0 * 132.0:
		return true
	if pos.distance_squared_to(_rotunda_pos + Vector2(0.0, 18.0)) <= 76.0 * 76.0:
		return true
	return false


## Group contract `"resonance_obelisks"` -> +45% wand/staff crystal recharge aura in active zones
func recharge_bonus_at(pos: Vector2) -> float:
	var best: float = 0.0
	if pos.distance_squared_to(_rotunda_pos) <= 215.0 * 215.0:
		best = maxf(best, 0.45)
	if pos.distance_squared_to(_altar_pos) <= 170.0 * 170.0:
		best = maxf(best, 0.45)
	if pos.distance_squared_to(_causeway_center) <= 190.0 * 190.0:
		best = maxf(best, 0.35)
	if pos.distance_squared_to(_mirror_pos) <= 150.0 * 150.0:
		best = maxf(best, 0.30)
	if _surge_timer > 0.0 and best > 0.0:
		best += 0.25
	return best


## Group contract `"desert_spell_listeners"` -> resonance burst & rainbow prism dispersion
func on_spell_cast(caster_pos: Vector2, _target_pos: Vector2, _spell_id: String) -> void:
	if caster_pos.distance_squared_to(_altar_pos) <= 175.0 * 175.0 and is_instance_valid(_prism_fx):
		_prism_fx.trigger_dispersion()
	if caster_pos.distance_squared_to(_rotunda_pos) <= 240.0 * 240.0:
		_surge_timer = maxf(_surge_timer, 2.4)
		if is_instance_valid(_portal_locks_fx):
			_portal_locks_fx.flare(1.8)
	if caster_pos.distance_squared_to(_causeway_center) <= 220.0 * 220.0:
		_trigger_all_conduits()


## Group contract `"desert_arcane_listeners"` -> Lightning-Rod Spire absorbs & supercharges Observatory
func on_arcane_lightning(strike_pos: Vector2, _info: Dictionary = {}) -> void:
	if strike_pos.distance_squared_to(_rotunda_pos) > 360.0 * 360.0 and strike_pos.distance_squared_to(_sundial_pos) > 260.0 * 260.0:
		return
	_surge_timer = 6.5
	_trigger_all_conduits()
	if is_instance_valid(_portal_locks_fx):
		_portal_locks_fx.flare(3.5)
	if is_instance_valid(_prism_fx):
		_prism_fx.trigger_dispersion()
	if is_instance_valid(_armillary_sparks):
		_armillary_sparks.restart()
	_play_sfx("storm_surge", _rotunda_pos, -3.0, 0.04, 780.0)


func _trigger_all_conduits() -> void:
	for c: ObservatoryConduit in _conduits:
		if is_instance_valid(c):
			c.trigger_pulse()


## Zone I — Meridian Forecourt & Split Ecliptic Gate (L0, 948,143)
func _build_zone_gate(ysort_parent: Node2D) -> void:
	var floor_fx: Node2D = MeridianForecourtFloor.new()
	floor_fx.position = _gate_pos
	floor_fx.z_index = -8
	add_child(floor_fx)

	var gate_meta: Dictionary = _meta_block("ecliptic_gate")
	var feet: Vector2 = _vec2(gate_meta.get("feet", [80, 120]), Vector2(80.0, 120.0))
	var ocular_anchor: Vector2 = _vec2(gate_meta.get("ocular_anchor", [80, 26]), Vector2(80.0, 26.0))
	var gate_node: Node2D = Node2D.new()
	gate_node.name = "ObsEclipticGate"
	gate_node.position = _gate_pos
	_add_ysorted(ysort_parent, gate_node)

	_make_static_pair(gate_node, "ecliptic_gate", -feet, 0.22, 0.95)
	_add_box_collider(gate_node, Vector2(-50.0, -1.0), Vector2(31.0, 14.0))
	_add_box_collider(gate_node, Vector2(50.0, -1.0), Vector2(31.0, 14.0))
	_add_canopy_at(_gate_pos + Vector2(-46.0, 8.0), 34.0, 22.0)
	_add_canopy_at(_gate_pos + Vector2(54.0, 8.0), 34.0, 22.0)

	# Levitating gate ocular lens suspended in the split crescent gap
	var oc_meta: Dictionary = _meta_block("gate_ocular")
	var oc_center: Vector2 = _vec2(oc_meta.get("center", [24, 24]), Vector2(24.0, 24.0))
	_gate_ocular_base_y = ocular_anchor.y - feet.y
	var oc_pos_local: Vector2 = Vector2(ocular_anchor.x - feet.x, _gate_ocular_base_y)
	var oc_pair: Array[Sprite2D] = _make_static_pair(gate_node, "gate_ocular", -oc_center, 0.35, 1.05, oc_pos_local)
	_gate_ocular = oc_pair[0]
	_gate_ocular_glow = oc_pair[1]
	_gate_ocular.z_index = 1
	_gate_ocular_glow.z_index = 1

	var gate_light: NightLight = NightLight.new()
	gate_light.position = Vector2(0.0, -48.0)
	gate_light.radius = 74.0
	gate_light.base_energy = 0.65
	gate_light.glow_color = Color("78f4e6")
	gate_node.add_child(gate_light)

	_gate_beam_glint = GateOcularGlint.new()
	_gate_beam_glint.position = Vector2.ZERO
	_gate_beam_glint.z_index = -1
	gate_node.add_child(_gate_beam_glint)


## Zone II — East Bastion 180° Monumental Sundial & Gnomon (L2, 969,161)
func _build_zone_sundial(ysort_parent: Node2D) -> void:
	var court_meta: Dictionary = _meta_block("sundial_court")
	var c_center: Vector2 = _vec2(court_meta.get("center", [120, 96]), Vector2(120.0, 96.0))
	var c_socket: Vector2 = _vec2(court_meta.get("socket", [c_center.x, c_center.y]), c_center)
	var socket_off: Vector2 = c_socket - c_center
	var court_node: Node2D = Node2D.new()
	court_node.name = "ObsSundialCourt"
	court_node.position = _sundial_pos
	court_node.z_index = -8
	add_child(court_node)
	_make_static_pair(court_node, "sundial_court", -c_center, 0.20, 0.90)

	var markers: Array = court_meta.get("hour_markers", []) as Array
	var fan_radii: Vector2 = _vec2(court_meta.get("fan_radii", [104, 65]), Vector2(104.0, 65.0))
	_sundial_overlay = SundialOverlay.new()
	_sundial_overlay.setup(c_center, socket_off, fan_radii, markers)
	court_node.add_child(_sundial_overlay)

	# Colliders along curved north exedra parapet wall of Sundial Court so dial floor & front steps stay walkable
	for seg_i: int in 7:
		var p_ang: float = lerpf(PI * 0.10, PI * 0.90, float(seg_i) / 6.0)
		_add_box_collider(court_node, Vector2(cos(p_ang) * 95.0, -sin(p_ang) * 61.0), Vector2(28.0, 12.0))

	# Towering Y-sorted Sundial Gnomon + Falcon Perch aligned at court socket
	var gn_meta: Dictionary = _meta_block("sundial_gnomon")
	var gn_feet: Vector2 = _vec2(gn_meta.get("feet", [48, 130]), Vector2(48.0, 130.0))
	var gn_apex: Vector2 = _vec2(gn_meta.get("apex", [52, 17]), Vector2(52.0, 17.0))
	var gn_pos: Vector2 = _sundial_pos + socket_off
	var gn_node: Node2D = Node2D.new()
	gn_node.name = "ObsSundialGnomon"
	gn_node.position = gn_pos
	_add_ysorted(ysort_parent, gn_node)

	_make_static_pair(gn_node, "sundial_gnomon", -gn_feet, 0.25, 1.0)
	_add_ellipse_collider(gn_node, Vector2.ZERO, Vector2(21.0, 11.5))
	_add_canopy_at(gn_pos + Vector2(24.0, 12.0), 52.0, 32.0)

	var gn_light: NightLight = NightLight.new()
	gn_light.position = Vector2(0.0, -34.0)
	gn_light.radius = 86.0
	gn_light.base_energy = 0.6
	gn_light.glow_color = Color("ffd98a")
	gn_node.add_child(gn_light)

	var gn_perch: RoofPerch = RoofPerch.new()
	gn_perch.host = gn_node
	gn_perch.perch_height = maxf(64.0, gn_feet.y - gn_apex.y)
	gn_perch.position = Vector2(gn_apex.x - gn_feet.x, -2.0)
	gn_node.add_child(gn_perch)


## Zone III — Causeway Saddle 6 Crystal Wind-Harp Pillars & Floating Debris (L1 -> L2)
func _build_zone_causeway(ysort_parent: Node2D) -> void:
	var pil_meta: Dictionary = _meta_block("causeway_pillar")
	var grid: Vector2i = _vec2i(pil_meta.get("grid", [4, 1]), Vector2i(4, 1))
	var feet: Vector2 = _vec2(pil_meta.get("feet", [28, 84]), Vector2(28.0, 84.0))
	var focals: Array = pil_meta.get("focal_points", [[39, 44], [17, 44]]) as Array

	for idx: int in CAUSEWAY_PILLAR_SPECS.size():
		var spec: Array = CAUSEWAY_PILLAR_SPECS[idx]
		var tile: Vector2i = spec[0] as Vector2i
		var frame_idx: int = int(spec[1])
		var pos: Vector2 = _tile_center(tile)

		var p_node: Node2D = Node2D.new()
		p_node.name = "ObsCausewayPillar_%d" % idx
		p_node.position = pos
		_add_ysorted(ysort_parent, p_node)
		_make_grid_pair(p_node, "causeway_pillar", grid, frame_idx, -feet, 0.25, 0.95)
		_add_ellipse_collider(p_node, Vector2(0.0, -1.0), Vector2(13.0, 7.5))

		var focal: Vector2 = Vector2(39.0, 44.0) if frame_idx == 0 else Vector2(17.0, 44.0)
		if frame_idx < focals.size():
			focal = _vec2(focals[frame_idx], focal)
		var harp: WindHarpOverlay = WindHarpOverlay.new()
		harp.setup(focal - feet, float(idx) * 1.1)
		p_node.add_child(harp)
		_harp_overlays.append(harp)

		var p_light: NightLight = NightLight.new()
		p_light.position = Vector2(0.0, -32.0)
		p_light.radius = 52.0
		p_light.base_energy = 0.50
		p_light.glow_color = Color("78f4e6")
		p_node.add_child(p_light)

	# Levitating non-blocking ruins shards around cliff rims
	var deb_meta: Dictionary = _meta_block("floating_debris")
	var d_grid: Vector2i = _vec2i(deb_meta.get("grid", [6, 1]), Vector2i(6, 1))
	var d_center: Vector2 = _vec2(deb_meta.get("center", [20, 20]), Vector2(20.0, 20.0))
	for di: int in DEBRIS_SPOTS.size():
		var ds: Array = DEBRIS_SPOTS[di]
		var wpos: Vector2 = ds[0] as Vector2
		var d_frame: int = int(ds[1])
		var hover_h: float = float(ds[2])
		var host: Node2D = Node2D.new()
		host.name = "ObsFloatingDebris_%d" % di
		host.position = wpos
		_add_ysorted(ysort_parent, host)

		var sh: GroundShadowDisc = GroundShadowDisc.new()
		sh.radii = Vector2(11.0, 4.5)
		sh.z_index = -1
		host.add_child(sh)

		var pair: Array[Sprite2D] = _make_grid_pair(host, "floating_debris", d_grid, d_frame, -d_center, 0.25, 0.90, Vector2(0.0, -hover_h))
		_debris_entries.append({
			"sprite": pair[0],
			"glow": pair[1],
			"base_y": -hover_h,
			"phase": float(di) * 0.9,
		})


## Zone IV — Summit Heart Rotunda, Astral Plaza, Sealed Portal, Armillary, Lenses & Starlight Beam (L3, 908,175)
func _build_zone_rotunda(ysort_parent: Node2D) -> void:
	# 1. Astral Plaza Mosaic floor (z_index = -8 below DaylightField shadows)
	var plaza_meta: Dictionary = _meta_block("plaza_mosaic")
	var p_center: Vector2 = _vec2(plaza_meta.get("center", [176, 120]), Vector2(176.0, 120.0))
	var plaza_node: Node2D = Node2D.new()
	plaza_node.name = "ObsPlazaMosaic"
	plaza_node.position = _rotunda_pos
	plaza_node.z_index = -8
	add_child(plaza_node)
	_make_static_pair(plaza_node, "plaza_mosaic", -p_center, 0.22, 0.95)

	# Soft courtyard shadow ring projected onto plaza floor beneath orbiting armillary sphere
	var arm_floor_shadow: GroundShadowDisc = GroundShadowDisc.new()
	arm_floor_shadow.position = Vector2(0.0, 4.0)
	arm_floor_shadow.radii = Vector2(54.0, 22.0)
	arm_floor_shadow.alpha = 0.24
	plaza_node.add_child(arm_floor_shadow)

	var assembly: Dictionary = _art_meta.get("assembly", {}) as Dictionary
	var flank_w_off: Vector2 = _vec2(assembly.get("flank_w_offset", [-86, 12]), Vector2(-86.0, 12.0))
	var flank_e_off: Vector2 = _vec2(assembly.get("flank_e_offset", [86, 12]), Vector2(86.0, 12.0))
	var portal_off: Vector2 = _vec2(assembly.get("portal_offset", [0, 26]), Vector2(0.0, 26.0))

	# 2. Rotunda North Vault & Shattered Half-Dome
	var v_meta: Dictionary = _meta_block("rotunda_vault")
	var v_feet: Vector2 = _vec2(v_meta.get("feet", [128, 206]), Vector2(128.0, 206.0))
	var v_apex: Vector2 = _vec2(v_meta.get("apex", [128, 20]), Vector2(128.0, 20.0))
	var v_oculus: Vector2 = _vec2(v_meta.get("oculus", [128, 80]), Vector2(128.0, 80.0))

	var vault_node: Node2D = Node2D.new()
	vault_node.name = "ObsRotundaVault"
	vault_node.position = _rotunda_pos
	_add_ysorted(ysort_parent, vault_node)
	_make_static_pair(vault_node, "rotunda_vault", -v_feet, 0.22, 1.0)
	var vault_poly: PackedVector2Array = PackedVector2Array()
	vault_poly.append(Vector2(85.0, 10.0))
	for vi: int in 13:
		var vang: float = PI * (float(vi) / 12.0)
		vault_poly.append(Vector2(cos(vang) * 85.0, -sin(vang) * 48.0))
	vault_poly.append(Vector2(-85.0, 10.0))
	_add_polygon_collider(vault_node, vault_poly)
	_add_canopy_at(_rotunda_pos + Vector2(22.0, 14.0), 98.0, 66.0)

	var r_light: NightLight = NightLight.new()
	r_light.position = Vector2(0.0, -56.0)
	r_light.radius = 180.0
	r_light.base_energy = 0.85
	r_light.glow_color = Color("78f4e6")
	vault_node.add_child(r_light)

	var spire_perch: RoofPerch = RoofPerch.new()
	spire_perch.host = vault_node
	spire_perch.perch_height = maxf(120.0, v_feet.y - v_apex.y)
	spire_perch.position = Vector2(v_apex.x - v_feet.x, -4.0)
	vault_node.add_child(spire_perch)

	# 3. West Astrolabe Flank (frame 0) & East Curved Stairs Flank (frame 1)
	var fl_meta: Dictionary = _meta_block("rotunda_flanks")
	var fl_grid: Vector2i = _vec2i(fl_meta.get("grid", [2, 1]), Vector2i(2, 1))
	var fl_feet: Vector2 = _vec2(fl_meta.get("feet", [48, 118]), Vector2(48.0, 118.0))

	var fw_node: Node2D = Node2D.new()
	fw_node.name = "ObsRotundaFlankW"
	fw_node.position = _rotunda_pos + flank_w_off
	_add_ysorted(ysort_parent, fw_node)
	_make_grid_pair(fw_node, "rotunda_flanks", fl_grid, 0, -fl_feet, 0.22, 0.95)
	_add_ellipse_collider(fw_node, Vector2(0.0, -1.0), Vector2(26.5, 15.5))
	_add_ellipse_collider(fw_node, Vector2(-19.0, -1.0), Vector2(16.0, 11.0))
	_add_canopy_at(fw_node.position + Vector2(16.0, 6.0), 48.0, 32.0)

	var fe_node: Node2D = Node2D.new()
	fe_node.name = "ObsRotundaFlankE"
	fe_node.position = _rotunda_pos + flank_e_off
	_add_ysorted(ysort_parent, fe_node)
	_make_grid_pair(fe_node, "rotunda_flanks", fl_grid, 1, -fl_feet, 0.22, 0.95)
	_add_ellipse_collider(fe_node, Vector2(0.0, -1.0), Vector2(26.5, 15.5))
	_add_ellipse_collider(fe_node, Vector2(17.0, 1.0), Vector2(18.5, 13.5))
	_add_canopy_at(fe_node.position + Vector2(16.0, 6.0), 48.0, 32.0)

	# 4. Sealed Star-Portal (Das Versiegelte Sternentor) with shifted Y-sort pivot & solid colliders
	var po_meta: Dictionary = _meta_block("rotunda_portal")
	var po_feet: Vector2 = _vec2(po_meta.get("feet", [64, 108]), Vector2(64.0, 108.0))
	var po_locks: Array = po_meta.get("locks", [[64, 48], [51, 70], [77, 70]]) as Array
	var portal_node: RotundaPortalInteractable = RotundaPortalInteractable.new()
	portal_node.name = "ObsRotundaPortal"
	portal_node.position = _rotunda_pos + portal_off + PORTAL_YSORT_SHIFT
	portal_node.observatory = self
	_add_ysorted(ysort_parent, portal_node)
	_make_static_pair(portal_node, "rotunda_portal", -po_feet - PORTAL_YSORT_SHIFT, 0.28, 1.0)
	_add_box_collider(portal_node, Vector2(0.0, -3.0), Vector2(118.0, 26.0))
	_add_box_collider(portal_node, Vector2(-35.0, 21.0), Vector2(18.0, 22.0))
	_add_box_collider(portal_node, Vector2(35.0, 21.0), Vector2(18.0, 22.0))
	_add_canopy_at(_rotunda_pos + portal_off + Vector2(12.0, 10.0), 54.0, 28.0)

	var lock_locals: Array[Vector2] = []
	for lp: Variant in po_locks:
		lock_locals.append(_vec2(lp, Vector2(64.0, 64.0)) - po_feet)
	_portal_locks_fx = PortalLocksFx.new()
	_portal_locks_fx.position = -PORTAL_YSORT_SHIFT
	_portal_locks_fx.locks = lock_locals
	portal_node.add_child(_portal_locks_fx)

	# 5. Overhead Mechanisms & Celestial Light Layer (z_index = 6 strictly above Y-sorted entities)
	var overhead: Node2D = Node2D.new()
	overhead.name = "ObsOverhead"
	overhead.position = _rotunda_pos
	overhead.z_index = 6
	add_child(overhead)

	# Ghost-Dome celestial meridian wireframe appearing at night over shattered SE side
	_ghost_dome = NightGhostDome.new()
	_ghost_dome.center_offset = Vector2(0.0, -108.0)
	_ghost_dome.z_index = 0
	overhead.add_child(_ghost_dome)

	# 12-frame 3D Armillary Orbits
	var arm_meta: Dictionary = _meta_block("armillary_rings")
	var a_grid: Vector2i = _vec2i(arm_meta.get("grid", [12, 1]), Vector2i(12, 1))
	var a_center: Vector2 = _vec2(arm_meta.get("center", [72, 72]), Vector2(72.0, 72.0))
	_armillary_frames = maxi(1, a_grid.x * a_grid.y)
	var arm_anchor: Vector2 = (v_oculus - v_feet) + Vector2(4.0, -4.0)
	var arm_pivot: Node2D = Node2D.new()
	arm_pivot.position = arm_anchor
	arm_pivot.z_index = 1
	overhead.add_child(arm_pivot)
	var arm_pair: Array[Sprite2D] = _make_grid_pair(arm_pivot, "armillary_rings", a_grid, 0, -a_center, 0.35, 1.0)
	_armillary_sprite = arm_pair[0]
	_armillary_glow = arm_pair[1]

	_armillary_sparks = CPUParticles2D.new()
	_armillary_sparks.emitting = false
	_armillary_sparks.one_shot = true
	_armillary_sparks.amount = 14
	_armillary_sparks.lifetime = 0.55
	_armillary_sparks.explosiveness = 0.92
	_armillary_sparks.spread = 180.0
	_armillary_sparks.initial_velocity_min = 24.0
	_armillary_sparks.initial_velocity_max = 68.0
	_armillary_sparks.gravity = Vector2(0.0, 48.0)
	_armillary_sparks.color = Color("ffd98a")
	_armillary_sparks.material = Unlit.material()
	arm_pivot.add_child(_armillary_sparks)

	# 3 Floating Telescope Lenses aligned along SW -> NE Optical Axis + Night Starlight Beam
	var lens_meta: Dictionary = _meta_block("telescope_lenses")
	var l_grid: Vector2i = _vec2i(lens_meta.get("grid", [3, 1]), Vector2i(3, 1))
	var l_center: Vector2 = _vec2(lens_meta.get("center", [32, 32]), Vector2(32.0, 32.0))
	var axis_dir: Vector2 = OPTICAL_AXIS.normalized()
	var beam_origin_local: Vector2 = arm_anchor + axis_dir * 88.0

	var beam_rect: ColorRect = ColorRect.new()
	beam_rect.size = Vector2(236.0, 92.0)
	beam_rect.position = beam_origin_local + Vector2(0.0, -46.0)
	beam_rect.pivot_offset = Vector2(0.0, 46.0)
	beam_rect.rotation = axis_dir.angle()
	beam_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam_rect.z_index = 2
	var beam_shader: Shader = load(BEAM_SHADER_PATH) as Shader
	if beam_shader != null:
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = beam_shader
		_beam_mat.set_shader_parameter("beam_size", Vector2(236.0, 92.0))
		_beam_mat.set_shader_parameter("strength", 0.0)
		beam_rect.material = _beam_mat
	overhead.add_child(beam_rect)

	var lens_dists: Array[float] = [-26.0, 46.0, 88.0]
	for li: int in 3:
		var l_base: Vector2 = arm_anchor + axis_dir * lens_dists[li]
		var lp: Array[Sprite2D] = _make_grid_pair(overhead, "telescope_lenses", l_grid, li, -l_center, 0.35, 1.0, l_base)
		lp[0].z_index = 3
		lp[1].z_index = 3
		_lens_nodes.append({
			"sprite": lp[0],
			"glow": lp[1],
			"base": l_base,
			"phase": float(li) * 1.4,
		})


## Zone V — Sunken Star-Mirror Basin, Polar Ocular Vista, Prism Altar & Collapsed Star-Globe (L3)
func _build_zone_terraces(ysort_parent: Node2D) -> void:
	# 1. Sunken Star-Mirror Basin (884, 171)
	var mir_meta: Dictionary = _meta_block("star_mirror_rim")
	var m_center: Vector2 = _vec2(mir_meta.get("center", [92, 58]), Vector2(92.0, 58.0))
	var pool_center: Vector2 = _vec2(mir_meta.get("pool_center", [m_center.x, m_center.y]), m_center)
	var pool_off: Vector2 = pool_center - m_center
	var pool_radii: Vector2 = _vec2(mir_meta.get("pool_radii", [65, 35]), Vector2(65.0, 35.0))

	var mir_node: Node2D = Node2D.new()
	mir_node.name = "ObsStarMirror"
	mir_node.position = _mirror_pos
	mir_node.z_index = -8
	add_child(mir_node)

	var film_size: Vector2 = pool_radii * 2.0 + Vector2(18.0, 18.0)
	var film: ColorRect = ColorRect.new()
	film.size = film_size
	film.position = pool_off - film_size * 0.5
	film.z_index = 0
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mir_shader: Shader = load(STAR_MIRROR_SHADER_PATH) as Shader
	if mir_shader != null:
		_star_mirror_mat = ShaderMaterial.new()
		_star_mirror_mat.shader = mir_shader
		_star_mirror_mat.set_shader_parameter("radii", pool_radii + Vector2(2.0, 2.0))
		_star_mirror_mat.set_shader_parameter("size_px", film_size)
		film.material = _star_mirror_mat
	mir_node.add_child(film)

	_make_static_pair(mir_node, "star_mirror_rim", -m_center, 0.25, 1.0)
	_add_ellipse_collider(mir_node, Vector2.ZERO, Vector2(82.0, 46.0))

	var mir_light: NightLight = NightLight.new()
	mir_light.position = Vector2.ZERO
	mir_light.radius = 128.0
	mir_light.base_energy = 0.75
	mir_light.glow_color = Color("8666e8")
	mir_node.add_child(mir_light)

	var cool_mist: CPUParticles2D = CPUParticles2D.new()
	cool_mist.amount = 10
	cool_mist.lifetime = 2.6
	cool_mist.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	cool_mist.emission_rect_extents = Vector2(pool_radii.x * 0.72, pool_radii.y * 0.58)
	cool_mist.direction = Vector2(0.0, -1.0)
	cool_mist.spread = 32.0
	cool_mist.initial_velocity_min = 4.0
	cool_mist.initial_velocity_max = 10.0
	cool_mist.gravity = Vector2.ZERO
	cool_mist.color = Color(0.55, 0.94, 0.96, 0.52)
	cool_mist.material = Unlit.material()
	cool_mist.z_as_relative = false
	cool_mist.z_index = 1
	mir_node.add_child(cool_mist)

	# 2. Polar Ocular Vista Telescope (880, 159)
	var pil_meta: Dictionary = _meta_block("causeway_pillar")
	var p_grid: Vector2i = _vec2i(pil_meta.get("grid", [4, 1]), Vector2i(4, 1))
	var p_feet: Vector2 = _vec2(pil_meta.get("feet", [28, 84]), Vector2(28.0, 84.0))

	var oc_node: PolarOcularInteractable = PolarOcularInteractable.new()
	oc_node.name = "ObsPolarOcular"
	oc_node.position = _ocular_pos
	oc_node.observatory = self
	_add_ysorted(ysort_parent, oc_node)
	_make_grid_pair(oc_node, "causeway_pillar", p_grid, 2, -p_feet, 0.28, 1.0)
	_add_ellipse_collider(oc_node, Vector2(0.0, -1.0), Vector2(13.0, 7.5))

	var oc_light: NightLight = NightLight.new()
	oc_light.position = Vector2(0.0, -42.0)
	oc_light.radius = 60.0
	oc_light.base_energy = 0.55
	oc_light.glow_color = Color("78f4e6")
	oc_node.add_child(oc_light)

	# 3. Open-Air Prism Altar (918, 187)
	var altar_node: Node2D = Node2D.new()
	altar_node.name = "ObsPrismAltar"
	altar_node.position = _altar_pos
	_add_ysorted(ysort_parent, altar_node)
	_make_grid_pair(altar_node, "causeway_pillar", p_grid, 3, -p_feet, 0.30, 1.0)
	_add_ellipse_collider(altar_node, Vector2(0.0, -1.0), Vector2(14.5, 8.0))

	var focals: Array = pil_meta.get("focal_points", []) as Array
	var altar_focal: Vector2 = Vector2(28.0, 53.0)
	if focals.size() > 3:
		altar_focal = _vec2(focals[3], altar_focal)
	_prism_fx = PrismAltarFx.new()
	_prism_fx.position = (altar_focal - p_feet) + Vector2(0.0, -4.0)
	altar_node.add_child(_prism_fx)

	var alt_light: NightLight = NightLight.new()
	alt_light.position = Vector2(0.0, -34.0)
	alt_light.radius = 74.0
	alt_light.base_energy = 0.65
	alt_light.glow_color = Color("ffd98a")
	altar_node.add_child(alt_light)

	# 4. Collapsed Star-Globe (926, 193)
	var deb_meta: Dictionary = _meta_block("floating_debris")
	var d_grid: Vector2i = _vec2i(deb_meta.get("grid", [6, 1]), Vector2i(6, 1))
	var d_center: Vector2 = _vec2(deb_meta.get("center", [20, 20]), Vector2(20.0, 20.0))

	var globe_cradle: StarGlobeCradle = StarGlobeCradle.new()
	globe_cradle.position = _globe_pos
	globe_cradle.z_index = -8
	add_child(globe_cradle)

	var globe_node: Node2D = Node2D.new()
	globe_node.name = "ObsCollapsedStarGlobe"
	globe_node.position = _globe_pos
	_add_ysorted(ysort_parent, globe_node)
	_make_grid_pair(globe_node, "floating_debris", d_grid, 5, -d_center, 0.25, 0.95, Vector2(0.0, -8.0))
	_add_box_collider(globe_node, Vector2(0.0, -4.0), Vector2(28.0, 14.0))

	var g_light: NightLight = NightLight.new()
	g_light.position = Vector2(0.0, -8.0)
	g_light.radius = 44.0
	g_light.base_energy = 0.45
	g_light.glow_color = Color("78f4e6")
	globe_node.add_child(g_light)


## Chained flush ObservatoryConduit inlays guiding the player from Gate -> Causeway -> Summit
func _build_conduits() -> void:
	var c_gate_w: ObservatoryConduit = ObservatoryConduit.new()
	c_gate_w.name = "ObsConduit_GateW"
	c_gate_w.setup(PackedVector2Array([_gate_pos + Vector2(-18.0, 44.0), _gate_pos + Vector2(-18.0, -34.0)]))

	var c_gate_e: ObservatoryConduit = ObservatoryConduit.new()
	c_gate_e.name = "ObsConduit_GateE"
	c_gate_e.setup(PackedVector2Array([_gate_pos + Vector2(18.0, 44.0), _gate_pos + Vector2(18.0, -34.0)]))

	var c_cw_l1: ObservatoryConduit = ObservatoryConduit.new()
	c_cw_l1.name = "ObsConduit_CausewayL1"
	c_cw_l1.setup(PackedVector2Array([
		_tile_center(Vector2i(951, 164)),
		_tile_center(Vector2i(940, 164)),
	]))

	var c_cw_l2: ObservatoryConduit = ObservatoryConduit.new()
	c_cw_l2.name = "ObsConduit_CausewayL2"
	c_cw_l2.setup(PackedVector2Array([
		_tile_center(Vector2i(934, 164)),
		_tile_center(Vector2i(931, 162)),
		_tile_center(Vector2i(926, 157)),
		_tile_center(Vector2i(921, 156)),
	]))

	var c_summit_e: ObservatoryConduit = ObservatoryConduit.new()
	c_summit_e.name = "ObsConduit_SummitE"
	c_summit_e.setup(PackedVector2Array([
		_tile_center(Vector2i(921, 161)),
		_tile_center(Vector2i(921, 175)),
		_rotunda_pos + Vector2(154.0, 0.0),
	]))

	var c_plaza_s: ObservatoryConduit = ObservatoryConduit.new()
	c_plaza_s.name = "ObsConduit_PlazaS"
	c_plaza_s.setup(PackedVector2Array([
		_rotunda_pos + Vector2(0.0, 128.0),
		_rotunda_pos + Vector2(0.0, 95.0),
	]))

	c_cw_l1.chained_conduits = [c_cw_l2]
	c_cw_l2.chained_conduits = [c_summit_e]

	for c: ObservatoryConduit in [c_gate_w, c_gate_e, c_cw_l1, c_cw_l2, c_summit_e, c_plaza_s]:
		c.z_index = -8
		add_child(c)
		_conduits.append(c)


## Multiplayer-safe Polar Ocular map discovery RPC
@rpc("any_peer", "call_local", "reliable")
func _rpc_reveal_observatory() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != multiplayer.get_unique_id():
		var ok: bool = false
		for p: Player in Player.all:
			if p.get_multiplayer_authority() == sender_id and p.global_position.distance_squared_to(_ocular_pos) <= 180.0 * 180.0:
				ok = true
				break
		if not ok:
			return
	if _vista_discovered:
		return
	_vista_discovered = true
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(Vector2(908.0, 170.0), 58.0)


func _register_surface_patch() -> void:
	_surface_patch = ObservatorySurfacePatch.new()
	_surface_patch.rotunda_pos = _rotunda_pos
	_surface_patch.sundial_pos = _sundial_pos
	_surface_patch.gate_pos = _gate_pos
	_surface_patch.mirror_pos = _mirror_pos
	_surface_patch.ocular_pos = _ocular_pos
	_surface_patch.altar_pos = _altar_pos
	add_child(_surface_patch)
	Terrain.patches.append(_surface_patch)


func _compute_reserved_cells() -> Dictionary:
	var blocked: Dictionary = {}
	var stones: Dictionary = {}
	var mark_rect: Callable = func(min_t: Vector2i, max_t: Vector2i, block_props: bool, block_stones: bool) -> void:
		for ty: int in range(min_t.y, max_t.y + 1):
			for tx: int in range(min_t.x, max_t.x + 1):
				var key: Vector2i = Vector2i(tx, ty)
				if block_props:
					blocked[key] = true
				if block_stones:
					stones[key] = true
	var mark_disc: Callable = func(center_t: Vector2i, rx: int, ry: int) -> void:
		for ty: int in range(center_t.y - ry, center_t.y + ry + 1):
			for tx: int in range(center_t.x - rx, center_t.x + rx + 1):
				var dx: float = float(tx - center_t.x) / float(maxi(1, rx))
				var dy: float = float(ty - center_t.y) / float(maxi(1, ry))
				if dx * dx + dy * dy <= 1.0:
					var key: Vector2i = Vector2i(tx, ty)
					blocked[key] = true
					stones[key] = true

	mark_disc.call(GATE_TILE, 7, 5)
	mark_disc.call(SUNDIAL_TILE, 9, 7)
	mark_disc.call(ROTUNDA_TILE, 14, 10)
	mark_disc.call(MIRROR_TILE, 8, 6)
	mark_disc.call(OCULAR_TILE, 4, 4)
	mark_disc.call(PRISM_ALTAR_TILE, 4, 4)
	mark_disc.call(GLOBE_TILE, 4, 4)
	mark_rect.call(Vector2i(920, 155), Vector2i(954, 172), true, true)
	mark_rect.call(Vector2i(917, 160), Vector2i(924, 177), true, true)
	mark_rect.call(Vector2i(965, 148), Vector2i(972, 154), true, true)
	mark_rect.call(Vector2i(960, 173), Vector2i(966, 179), true, true)

	return {"blocked": blocked, "stones": stones}


func _load_art_meta() -> void:
	if not FileAccess.file_exists(ART_META_PATH):
		return
	var f: FileAccess = FileAccess.open(ART_META_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_art_meta = parsed as Dictionary


func _preload_sfx() -> void:
	for id: String in ["gear_tick", "gear_catch", "wind_harp", "noon_chime", "storm_surge", "ocular_chime"]:
		var path: String = "%s%s.wav" % [SFX_DIR, id]
		if ResourceLoader.exists(path):
			_sfx_streams[id] = load(path) as AudioStream


func _play_sfx(id: String, at_pos: Vector2, db: float = -4.0, pitch_spread: float = 0.04, range_px: float = 520.0) -> void:
	var stream: AudioStream = _sfx_streams.get(id) as AudioStream
	if stream == null or not is_inside_tree():
		return
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = stream
	voice.volume_db = db
	voice.pitch_scale = randf_range(1.0 - pitch_spread, 1.0 + pitch_spread)
	voice.max_distance = range_px
	voice.position = to_local(at_pos)
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func _nearest_player(at_pos: Vector2, max_dist: float) -> Player:
	var best: Player = null
	var best_d2: float = max_dist * max_dist
	for p: Player in Player.all:
		if is_instance_valid(p):
			var d2: float = p.global_position.distance_squared_to(at_pos)
			if d2 <= best_d2:
				best_d2 = d2
				best = p
	return best


func _tex(file_name: String) -> Texture2D:
	if _textures.has(file_name):
		return _textures[file_name] as Texture2D
	var full: String = TEX_DIR + file_name
	var t: Texture2D = load(full) as Texture2D if ResourceLoader.exists(full) else null
	_textures[file_name] = t
	return t


func _meta_block(key: String) -> Dictionary:
	return _art_meta.get(key, {}) as Dictionary


func _make_static_pair(parent: Node2D, stem: String, offset_px: Vector2, base_a: float, night_a: float, local_pos: Vector2 = Vector2.ZERO) -> Array[Sprite2D]:
	var base: Sprite2D = Sprite2D.new()
	base.texture = _tex(stem + ".png")
	base.centered = false
	base.offset = offset_px
	base.position = local_pos
	parent.add_child(base)

	var glow: Sprite2D = Sprite2D.new()
	glow.texture = _tex(stem + "_glow.png")
	glow.centered = false
	glow.offset = offset_px
	glow.position = local_pos
	glow.material = Unlit.material()
	parent.add_child(glow)
	_night_sprites.append({"sprite": glow, "base": base_a, "night": night_a})
	return [base, glow]


func _make_grid_pair(parent: Node2D, stem: String, grid: Vector2i, frame_idx: int, offset_px: Vector2, base_a: float, night_a: float, local_pos: Vector2 = Vector2.ZERO) -> Array[Sprite2D]:
	var pair: Array[Sprite2D] = _make_static_pair(parent, stem, offset_px, base_a, night_a, local_pos)
	for spr: Sprite2D in pair:
		spr.hframes = maxi(1, grid.x)
		spr.vframes = maxi(1, grid.y)
		spr.frame = clampi(frame_idx, 0, maxi(0, grid.x * grid.y - 1))
	return pair


func _add_ysorted(ysort_parent: Node2D, node: Node) -> void:
	ysort_parent.add_child(node)
	if ysort_parent != self:
		_ysort_owned.append(node)


func _add_canopy_at(world_pos: Vector2, rx: float, ry: float) -> void:
	var c: DayCanopyNode = DayCanopyNode.new()
	c.position = to_local(world_pos)
	c.radii = Vector2(rx, ry)
	add_child(c)


func _add_box_collider(host: Node2D, center: Vector2, sz: Vector2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = sz
	shape.shape = rect
	shape.position = center
	body.add_child(shape)
	host.add_child(body)


func _add_polygon_collider(host: Node2D, pts: PackedVector2Array) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var poly: CollisionPolygon2D = CollisionPolygon2D.new()
	poly.polygon = pts
	body.add_child(poly)
	host.add_child(body)


func _add_ellipse_collider(host: Node2D, center: Vector2, radii: Vector2) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 12:
		var ang: float = TAU * (float(i) / 12.0)
		pts.append(center + Vector2(cos(ang) * radii.x, sin(ang) * radii.y))
	_add_polygon_collider(host, pts)


static func _tile_center(t: Vector2i) -> Vector2:
	return Vector2(t) * 16.0 + Vector2(8.0, 8.0)


static func _vec2(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Array:
		var a: Array = raw as Array
		if a.size() >= 2:
			return Vector2(float(a[0]), float(a[1]))
	return fallback


static func _vec2i(raw: Variant, fallback: Vector2i) -> Vector2i:
	if raw is Array:
		var a: Array = raw as Array
		if a.size() >= 2:
			return Vector2i(int(a[0]), int(a[1]))
	return fallback


## Terrain.patches helper registering quartz stone flooring across all Observatory plazas
class ObservatorySurfacePatch:
	extends Node
	var rotunda_pos: Vector2 = Vector2.ZERO
	var sundial_pos: Vector2 = Vector2.ZERO
	var gate_pos: Vector2 = Vector2.ZERO
	var mirror_pos: Vector2 = Vector2.ZERO
	var ocular_pos: Vector2 = Vector2.ZERO
	var altar_pos: Vector2 = Vector2.ZERO

	func surface_at(world_pos: Vector2) -> String:
		var dr: Vector2 = (world_pos - rotunda_pos) / Vector2(168.0, 112.0)
		if dr.length_squared() <= 1.0:
			return "quartz"
		var ds: Vector2 = (world_pos - sundial_pos) / Vector2(118.0, 78.0)
		if ds.length_squared() <= 1.0:
			return "quartz"
		var dg: Vector2 = (world_pos - gate_pos) / Vector2(82.0, 52.0)
		if dg.length_squared() <= 1.0:
			return "quartz"
		var dm: Vector2 = (world_pos - mirror_pos) / Vector2(96.0, 62.0)
		if dm.length_squared() <= 1.0:
			return "quartz"
		if world_pos.distance_squared_to(ocular_pos) <= 44.0 * 44.0 or world_pos.distance_squared_to(altar_pos) <= 44.0 * 44.0:
			return "quartz"
		if world_pos.x >= 920.0 * 16.0 and world_pos.x <= 954.0 * 16.0 and world_pos.y >= 155.0 * 16.0 and world_pos.y <= 176.0 * 16.0:
			return "quartz"
		return ""


## Positioned directly at each architectural shadow center (`distance_squared <= 19600` in DesertHeat)
class DayCanopyNode:
	extends Node2D
	var radii: Vector2 = Vector2(48.0, 32.0)

	func _ready() -> void:
		add_to_group("day_canopies")

	func day_canopy() -> Vector4:
		return Vector4(global_position.x, global_position.y, radii.x, radii.y)


## Soft elliptical ground shadow beneath hovering debris / armillary
class GroundShadowDisc:
	extends Node2D
	var radii: Vector2 = Vector2(12.0, 5.0)
	var alpha: float = 0.28

	func _draw() -> void:
		var sun: float = TimeManager.sun_amount() if TimeManager != null else 0.7
		var a: float = alpha * clampf(0.35 + 0.65 * sun, 0.25, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, radii.y / maxf(1.0, radii.x)))
		draw_circle(Vector2.ZERO, radii.x, Color(0.16, 0.10, 0.14, a))


## Engraved meridian floor sightlines & rune studs beneath Zone I Gate
class MeridianForecourtFloor:
	extends Node2D

	func _draw() -> void:
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 24, Color("9a7230"), 1.0)
		draw_line(Vector2(-38.0, 0.0), Vector2(-24.0, 0.0), Color("78f4e6"), 1.0)
		draw_line(Vector2(24.0, 0.0), Vector2(38.0, 0.0), Color("78f4e6"), 1.0)


class GateOcularGlint:
	extends Node2D

	func _draw() -> void:
		var sun: float = TimeManager.sun_amount() if TimeManager != null else 0.7
		var night: float = TimeManager.night_amount() if TimeManager != null else 0.0
		var col: Color = Color("fff0b0").lerp(Color("78f4e6"), night)
		var a: float = clampf(0.12 + 0.16 * maxf(sun, night), 0.0, 0.30)
		draw_circle(Vector2(0.0, 2.0), 14.0, Color(col.r, col.g, col.b, a * 0.45))
		draw_circle(Vector2(0.0, 2.0), 5.0, Color(col.r, col.g, col.b, a))


## Dynamic real-time Gnomon shadow polygon, active hour gem highlight, and Noon Zenith beam
class SundialOverlay:
	extends Node2D
	var _socket_local: Vector2 = Vector2.ZERO
	var _fan_radii: Vector2 = Vector2(98.0, 65.0)
	var _marker_locals: Array[Vector2] = []
	var _tod: float = 0.5
	var _sun: float = 0.8
	var _surging: bool = false

	func setup(court_center: Vector2, socket_off: Vector2, fan_radii: Vector2, raw_markers: Array) -> void:
		_socket_local = socket_off
		_fan_radii = fan_radii
		_marker_locals.clear()
		for item: Variant in raw_markers:
			if item is Array:
				var arr: Array = item as Array
				if arr.size() >= 2:
					_marker_locals.append(Vector2(float(arr[0]), float(arr[1])) - court_center)
		material = Unlit.material()

	func update_solar(tod: float, sun: float, surging: bool) -> void:
		_tod = tod
		_sun = sun
		_surging = surging
		queue_redraw()

	func _draw() -> void:
		# Sweep shadow across 180-deg northern fan (West at morning tod=0.25 -> North at 0.50 -> East at 0.75)
		var day_frac: float = clampf((_tod - 0.24) / 0.52, 0.0, 1.0)
		var ang: float = lerpf(PI * 0.96, PI * 0.04, day_frac)
		var shadow_alpha: float = clampf(_sun * 0.48, 0.0, 0.46)
		if shadow_alpha > 0.04:
			var tip: Vector2 = _socket_local + Vector2(cos(ang) * _fan_radii.x * 0.88, -sin(ang) * _fan_radii.y * 0.88).round()
			var perp: Vector2 = Vector2(-sin(ang), -cos(ang)).normalized()
			var poly: PackedVector2Array = PackedVector2Array([
				_socket_local + perp * -9.0,
				_socket_local + perp * 9.0,
				tip + perp * 2.0,
				tip - perp * 2.0,
			])
			draw_colored_polygon(poly, Color(0.11, 0.08, 0.16, shadow_alpha))

		# Highlight active solar hour marker & Noon Zenith Convergence Beam
		var near_noon: bool = absf(_tod - 0.50) < 0.025 or _surging
		if _marker_locals.size() > 0:
			var active_idx: int = clampi(int(roundf((1.0 - day_frac) * float(_marker_locals.size() - 1))), 0, _marker_locals.size() - 1)
			for i: int in _marker_locals.size():
				var p: Vector2 = _marker_locals[i]
				if near_noon:
					draw_circle(p, 3.0, Color(1.0, 0.94, 0.65, 0.85))
				elif i == active_idx and _sun > 0.15:
					draw_circle(p, 2.5, Color(0.47, 0.96, 0.90, 0.85))

		if near_noon:
			draw_line(_socket_local + Vector2(0.0, -90.0), _socket_local + Vector2(0.0, -8.0), Color(1.0, 0.93, 0.65, 0.72), 2.0)
			draw_circle(_socket_local + Vector2(0.0, -8.0), 8.0, Color(0.47, 0.96, 0.90, 0.55))


## Translucent Aeolian Wind-Harp shimmer reacting to WorldWind & Singender Resonanzwind
class WindHarpOverlay:
	extends Node2D
	var _anchor: Vector2 = Vector2.ZERO
	var _phase: float = 0.0
	var _clock: float = 0.0
	var _res: float = 0.0
	var _surge: bool = false

	func setup(anchor: Vector2, phase: float) -> void:
		_anchor = anchor
		_phase = phase
		material = Unlit.material()

	func update_wind(t: float, res_wind: float, surging: bool) -> void:
		_clock = t
		_res = res_wind
		_surge = surging
		queue_redraw()

	func _draw() -> void:
		var wind_vec: Vector2 = WorldWind.sample(global_position) if WorldWind != null else Vector2.RIGHT * 0.4
		var amp: float = clampf(0.45 + wind_vec.length() * 0.8 + _res * 1.4, 0.35, 2.2)
		var alpha: float = clampf(0.28 + _res * 0.50 + (0.32 if _surge else 0.0), 0.25, 0.92)
		for s: int in 4:
			var ox: float = float(s - 1) * 2.0
			var vib: float = roundf(sin(_clock * (7.5 + float(s) * 2.1) + _phase) * amp)
			var p0: Vector2 = _anchor + Vector2(ox, -16.0)
			var pm: Vector2 = _anchor + Vector2(ox + vib, 0.0)
			var p1: Vector2 = _anchor + Vector2(ox, 16.0)
			var col: Color = Color(0.47, 0.96, 0.90, alpha) if s % 2 == 0 else Color(0.95, 0.92, 1.0, alpha * 0.85)
			draw_line(p0, pm, col, 1.0)
			draw_line(pm, p1, col, 1.0)


## Ethereal Night Ghost-Dome meridian wireframe completing the shattered SE vault after dusk
class NightGhostDome:
	extends Node2D
	var center_offset: Vector2 = Vector2(0.0, -108.0)
	var _clock: float = 0.0
	var _vis: float = 0.0

	func _ready() -> void:
		material = Unlit.material()

	func update_state(t: float, night: float, storm: float, surging: bool) -> void:
		_clock = t
		var want: float = clampf((night - 0.15) * 1.15 + storm * 0.45 + (0.40 if surging else 0.0), 0.0, 0.95)
		if absf(want - _vis) > 0.005 or want > 0.02:
			_vis = want
			queue_redraw()

	func _draw() -> void:
		if _vis <= 0.02:
			return
		var rx: float = 78.0
		var ry: float = 52.0
		var c: Vector2 = center_offset
		var col_a: Color = Color(0.47, 0.96, 0.90, 0.34 * _vis)
		var col_b: Color = Color(0.58, 0.41, 0.93, 0.26 * _vis)
		for lat: float in [0.35, 0.65]:
			var lrx: float = rx * (1.0 - lat * 0.36)
			var lry: float = ry * (1.0 - lat * 0.36)
			var ly: float = c.y - lat * 38.0
			for seg: int in 14:
				if (seg + int(_clock * 1.8)) % 3 == 0:
					continue
				var a0: float = lerpf(0.05, PI - 0.05, float(seg) / 14.0)
				var a1: float = lerpf(0.05, PI - 0.05, float(seg + 1) / 14.0)
				draw_line(Vector2(c.x + cos(a0) * lrx, ly + sin(a0) * lry * 0.55), Vector2(c.x + cos(a1) * lrx, ly + sin(a1) * lry * 0.55), col_b, 1.0)
		for mer: float in [-0.6, -0.15, 0.3, 0.72]:
			var pts: PackedVector2Array = PackedVector2Array()
			for step_i: int in 9:
				var frac: float = float(step_i) / 8.0
				var px: float = c.x + lerpf(0.0, sin(mer) * rx, frac)
				var py: float = lerpf(c.y - 54.0, c.y + cos(mer) * 26.0, frac * frac)
				pts.append(Vector2(px, py).round())
			for seg_i: int in pts.size() - 1:
				if (seg_i + int(_clock * 2.4)) % 2 == 0:
					draw_line(pts[seg_i], pts[seg_i + 1], col_a, 1.0)


## Glowing triangle & lock pulses when Ellie inspects the Sealed Star-Portal
class PortalLocksFx:
	extends Node2D
	var locks: Array[Vector2] = []
	var _flare: float = 0.0

	func _ready() -> void:
		material = Unlit.material()

	func flare(seconds: float) -> void:
		_flare = maxf(_flare, seconds)
		queue_redraw()

	func tick(delta: float, surging: bool) -> void:
		if _flare > 0.0 or surging:
			_flare = maxf(0.0, _flare - delta)
			queue_redraw()

	func _draw() -> void:
		if _flare <= 0.01 or locks.size() < 3:
			return
		var a: float = clampf(_flare * 0.55, 0.0, 0.92)
		var gold: Color = Color(1.0, 0.92, 0.58, a)
		var turq: Color = Color(0.47, 0.96, 0.90, a * 0.85)
		draw_line(locks[0], locks[1], turq, 1.5)
		draw_line(locks[1], locks[2], turq, 1.5)
		draw_line(locks[2], locks[0], turq, 1.5)
		for lp: Vector2 in locks:
			draw_arc(lp, 9.0, 0.0, TAU, 16, gold, 1.5)


## Rainbow spectral crystal rays when spells are cast near the Open-Air Prism Altar
class PrismAltarFx:
	extends Node2D
	var _disp_t: float = 0.0
	var _clock: float = 0.0

	func _ready() -> void:
		material = Unlit.material()

	func trigger_dispersion() -> void:
		_disp_t = 1.65
		queue_redraw()

	func tick(delta: float) -> void:
		_clock += delta
		if _disp_t > 0.0:
			_disp_t = maxf(0.0, _disp_t - delta)
		queue_redraw()

	func _draw() -> void:
		var idle_a: float = 0.35 + 0.18 * sin(_clock * 2.4)
		draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.94, 0.69, idle_a))
		if _disp_t <= 0.01:
			return
		var strength: float = clampf(_disp_t / 1.65, 0.0, 1.0)
		var palette: Array[Color] = [Color("78f4e6"), Color("fff0b0"), Color("cbaaff"), Color("f29bb8"), Color("7ae582")]
		for i: int in 5:
			var ang: float = _clock * 1.4 + float(i) * (TAU / 5.0)
			var c: Color = palette[i]
			c.a = strength * 0.85
			draw_line(Vector2.ZERO, Vector2(cos(ang), sin(ang) * 0.65) * 38.0, c, 1.5)


## Sunken sandstone/brass cradle floor under Collapsed Star-Globe (Zone V)
class StarGlobeCradle:
	extends Node2D

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.62))
		draw_circle(Vector2.ZERO, 24.0, Color("3c2824"))
		draw_circle(Vector2.ZERO, 20.0, Color("8a5d3e"))
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 24, Color("c89d42"), 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Zone IV Rotunda Portal Interactable ("STERNENTOR UNTERSUCHEN") — Exterior lore & lock flash
class RotundaPortalInteractable:
	extends Interactable
	var observatory: DesertObservatory

	func prompt() -> String:
		return "STERNENTOR UNTERSUCHEN"

	func prompt_position() -> Vector2:
		return Vector2(0.0, -70.0)

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position - PORTAL_YSORT_SHIFT) - 24.0

	func interact(player: Player) -> void:
		if observatory != null:
			if is_instance_valid(observatory._portal_locks_fx):
				observatory._portal_locks_fx.flare(2.6)
			observatory._play_sfx("ocular_chime", global_position - PORTAL_YSORT_SHIFT, -4.0, 0.03, 520.0)
		var bubble: SettlerBubble = SettlerBubble.new()
		bubble.position = Vector2(0.0, -52.0)
		add_child(bubble)
		bubble.show_text("Drei erloschene Sternenschlösser versiegeln das Innere der Zenitwarte. Die uralten Bahnen darüber warten noch auf ihr Erwachen.", 5.0)
		get_tree().create_timer(5.2, false).timeout.connect(func() -> void:
			if is_instance_valid(bubble):
				bubble.queue_free())


## Zone V Polar Ocular Interactable ("DURCH DAS POLAR-OKULAR BLICKEN") — Vista pan/zoom + MapDiscovery
class PolarOcularInteractable:
	extends Interactable
	var observatory: DesertObservatory
	var _vista_active: bool = false
	var _vista_timer: float = 0.0
	var _cam_tween: Tween
	var _active_player: Player

	func _process(delta: float) -> void:
		if not _vista_active:
			return
		_vista_timer += delta
		if _vista_timer >= 4.5 or InputManager.move_vector().length_squared() > 0.04:
			_end_vista()

	func prompt() -> String:
		return "ZURÜCKTRETEN" if _vista_active else "DURCH DAS POLAR-OKULAR BLICKEN"

	func prompt_position() -> Vector2:
		return Vector2(0.0, -68.0)

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 14.0

	func interact(player: Player) -> void:
		if _vista_active:
			_end_vista()
			return
		_start_vista(player)

	func _start_vista(player: Player) -> void:
		if player == null:
			return
		_active_player = player
		_vista_active = true
		_vista_timer = 0.0
		if observatory != null:
			observatory._play_sfx("ocular_chime", global_position, -3.0, 0.03, 520.0)
			observatory._rpc_reveal_observatory.rpc()

		var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
		if world != null:
			world.set_vista_focus(Vector2(908.0, 170.0) * 16.0, 2)
		var hud: Node = player.get("_hud") as Node
		if hud == null:
			hud = player.get_node_or_null("Hud")
		if hud != null:
			hud.set("vista_hide", true)
		var cam: Camera2D = player.view_camera()
		if cam != null:
			if _cam_tween != null and _cam_tween.is_valid():
				_cam_tween.kill()
			_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_cam_tween.tween_property(cam, "zoom", Vector2(0.58, 0.58), 1.45)
			var pan_vec: Vector2 = ((observatory._rotunda_pos - global_position) * 0.62).round() if observatory != null else Vector2(220.0, 140.0)
			_cam_tween.tween_property(player, "view_shift", pan_vec, 1.45)

	func _end_vista() -> void:
		_vista_active = false
		_vista_timer = 0.0
		var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
		if world != null:
			world.clear_vista_focus()
		if _active_player != null and is_instance_valid(_active_player):
			var hud: Node = _active_player.get("_hud") as Node
			if hud == null:
				hud = _active_player.get_node_or_null("Hud")
			if hud != null:
				hud.set("vista_hide", false)
			var cam: Camera2D = _active_player.view_camera()
			if cam != null:
				if _cam_tween != null and _cam_tween.is_valid():
					_cam_tween.kill()
				_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				_cam_tween.tween_property(cam, "zoom", Vector2.ONE, 0.85)
				_cam_tween.tween_property(_active_player, "view_shift", Vector2.ZERO, 0.85)
		_active_player = null


## Flush inlaid sandstone, brass & crystal meridian conduit with octagonal relay medallions
class ObservatoryConduit:
	extends Node2D
	var world_points: PackedVector2Array = PackedVector2Array()
	var points_local: PackedVector2Array = PackedVector2Array()
	var seg_lengths: PackedFloat32Array = PackedFloat32Array()
	var total_length: float = 0.0
	var chained_conduits: Array[ObservatoryConduit] = []
	var _pulse_t: float = -1.0
	var _cooldown: float = 0.0
	var _night: float = 0.0
	var _storm: float = 0.0
	var _surging: bool = false
	var _glow: ObservatoryConduitGlow

	func setup(pts: PackedVector2Array) -> void:
		if pts.is_empty():
			return
		position = pts[0]
		world_points = pts
		points_local.clear()
		seg_lengths.clear()
		total_length = 0.0
		for p: Vector2 in pts:
			points_local.append(p - pts[0])
		for i: int in points_local.size() - 1:
			var seg_len: float = points_local[i].distance_to(points_local[i + 1])
			seg_lengths.append(seg_len)
			total_length += seg_len
		_glow = ObservatoryConduitGlow.new()
		_glow.owner_conduit = self
		_glow.material = Unlit.material()
		_glow.z_index = 1
		add_child(_glow)

	func _ready() -> void:
		add_to_group("desert_spell_listeners")
		add_to_group("desert_arcane_listeners")
		_night = TimeManager.night_amount() if TimeManager != null else 0.0
		queue_redraw()
		if is_instance_valid(_glow):
			_glow.queue_redraw()

	func is_pulsing() -> bool:
		return _pulse_t >= 0.0

	func trigger_pulse() -> void:
		if _cooldown > 0.0 or _pulse_t >= 0.0:
			return
		_pulse_t = 0.0
		_cooldown = 0.9
		if is_instance_valid(_glow):
			_glow.queue_redraw()

	func update_glow_state(night: float, storm: float, surging: bool) -> void:
		if absf(_night - night) > 0.01 or absf(_storm - storm) > 0.02 or _surging != surging:
			_night = night
			_storm = storm
			_surging = surging
			if is_instance_valid(_glow):
				_glow.queue_redraw()

	func on_spell_cast(caster_pos: Vector2, target_pos: Vector2, _spell_id: String) -> void:
		for i: int in world_points.size():
			var wp: Vector2 = world_points[i]
			if wp.distance_to(caster_pos) <= 96.0 or wp.distance_to(target_pos) <= 96.0:
				trigger_pulse()
				return
			if i + 1 < world_points.size():
				var mid: Vector2 = wp.lerp(world_points[i + 1], 0.5)
				if mid.distance_to(caster_pos) <= 96.0 or mid.distance_to(target_pos) <= 96.0:
					trigger_pulse()
					return

	func on_arcane_lightning(strike_pos: Vector2, _info: Dictionary = {}) -> void:
		for wp: Vector2 in world_points:
			if wp.distance_to(strike_pos) <= 140.0:
				trigger_pulse()
				return

	func sample_at(frac: float) -> Vector2:
		if points_local.is_empty():
			return Vector2.ZERO
		if points_local.size() == 1 or total_length <= 0.01:
			return points_local[0]
		var target_d: float = clampf(frac, 0.0, 1.0) * total_length
		var accum: float = 0.0
		for i: int in seg_lengths.size():
			var sl: float = seg_lengths[i]
			if accum + sl >= target_d and sl > 0.001:
				var t: float = (target_d - accum) / sl
				return points_local[i].lerp(points_local[i + 1], t)
			accum += sl
		return points_local[points_local.size() - 1]

	func _process(delta: float) -> void:
		if _cooldown > 0.0:
			_cooldown = maxf(0.0, _cooldown - delta)
		if _pulse_t >= 0.0:
			var travel_time: float = maxf(0.45, total_length / 190.0)
			_pulse_t += delta / travel_time
			if _pulse_t >= 1.0:
				_pulse_t = -1.0
				for next_c: ObservatoryConduit in chained_conduits:
					if is_instance_valid(next_c):
						next_c.trigger_pulse()
			if is_instance_valid(_glow):
				_glow.queue_redraw()

	func _draw_strip(width: float, col: Color) -> void:
		for i: int in points_local.size() - 1:
			draw_line(points_local[i], points_local[i + 1], col, width)
		for j: int in range(1, points_local.size() - 1):
			draw_circle(points_local[j], width * 0.5, col)

	func _octagon_points(c: Vector2, r: float) -> PackedVector2Array:
		var pts: PackedVector2Array = PackedVector2Array()
		for k: int in 8:
			var ang: float = PI * 0.125 + TAU * (float(k) / 8.0)
			pts.append(c + Vector2(cos(ang) * r, sin(ang) * r))
		return pts

	func _draw() -> void:
		if points_local.size() < 2:
			return
		_draw_strip(8.0, Color("5a3b2c"))
		_draw_strip(6.0, Color("cfa060"))
		for i: int in seg_lengths.size():
			var a: Vector2 = points_local[i]
			var b: Vector2 = points_local[i + 1]
			var sl: float = seg_lengths[i]
			if sl < 18.0:
				continue
			var dir: Vector2 = (b - a) / sl
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			var dist: float = 12.0
			while dist <= sl - 9.0:
				var tick_c: Vector2 = a + dir * dist
				draw_line(tick_c - perp * 3.0, tick_c + perp * 3.0, Color("8a5f3c"), 1.0)
				dist += 12.0
		_draw_strip(4.0, Color("dfbe6a"))
		_draw_strip(2.0, Color("241e38"))
		_draw_strip(1.0, Color("52c4bc"))
		for wp: Vector2 in points_local:
			draw_colored_polygon(_octagon_points(wp, 6.5), Color("5a3b2c"))
			draw_colored_polygon(_octagon_points(wp, 5.2), Color("cfa060"))
			draw_colored_polygon(_octagon_points(wp, 3.8), Color("dfbe6a"))
			draw_colored_polygon(_octagon_points(wp, 2.4), Color("241e38"))
			draw_circle(wp, 1.4, Color("78f4e6"))


## Unlit crystal filament & travelling pulse comet over an ObservatoryConduit
class ObservatoryConduitGlow:
	extends Node2D
	var owner_conduit: ObservatoryConduit

	func _draw() -> void:
		if owner_conduit == null or owner_conduit.points_local.size() < 2:
			return
		var alpha: float = clampf(0.14 + owner_conduit._night * 0.65 + owner_conduit._storm * 0.35 + (0.35 if owner_conduit._surging else 0.0), 0.0, 0.95)
		var line_col: Color = Color(0.47, 0.96, 0.90, alpha)
		for i: int in owner_conduit.points_local.size() - 1:
			draw_line(owner_conduit.points_local[i], owner_conduit.points_local[i + 1], line_col, 1.0)
		for wp: Vector2 in owner_conduit.points_local:
			draw_circle(wp, 1.8, line_col)
		if owner_conduit.is_pulsing() and owner_conduit.total_length > 1.0:
			var tail_frac: float = clampf(owner_conduit._pulse_t - (26.0 / owner_conduit.total_length), 0.0, 1.0)
			var head_frac: float = clampf(owner_conduit._pulse_t, 0.0, 1.0)
			var prev_p: Vector2 = owner_conduit.sample_at(tail_frac)
			for step_i: int in range(1, 6):
				var f: float = lerpf(tail_frac, head_frac, float(step_i) / 5.0)
				var cur_p: Vector2 = owner_conduit.sample_at(f)
				draw_line(prev_p, cur_p, Color(0.47, 0.96, 0.90, 0.85), 2.5)
				if step_i >= 3:
					draw_line(prev_p, cur_p, Color(1.0, 0.92, 0.62, 0.95), 1.4)
				prev_p = cur_p
			var head_p: Vector2 = owner_conduit.sample_at(head_frac)
			draw_circle(head_p, 4.5, Color(0.47, 0.96, 0.90, 0.45))
			draw_circle(head_p, 2.2, Color(1.0, 0.97, 0.86, 0.98))
