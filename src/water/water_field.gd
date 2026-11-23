class_name WaterField
extends Node2D
## Core Water System v2 engine (WorldLevel-2.0 & grass_lab compatible).
## Owns 2x2 px `water_geo_map` & `water_flow_map` with lock-free COW PackedByteArray
## snapshots for `Jobs` workers, a camera-centered toroidal 128x128 @ 4x4 px (512x512 px)
## 30 Hz damped wave ringbuffer, greedy `river_depth` colliders, WaterReflections auto-spawn,
## `g_water_time` coordination, daytime-culled night glow, and V12 surface petals & spray motes.

const CELL_PX: float = 2.0
const WAVE_RES: int = 128
const WAVE_CELL_PX: float = 4.0
const WAVE_FIELD_SIZE: float = 512.0
const TILE_SIZE: int = 4
const TILE_GRID: int = 32
const TILE_COUNT: int = 1024
const NEUTRAL_WAVE_U32: int = 0x00808080
const RECENTER_STEP_CELLS: int = 4
const WAVE_STEP_DT: float = 1.0 / 30.0
const MAX_PETALS: int = 18
const MAX_AIR_MOTES: int = 40
const PETAL_COLORS: Array[Color] = [Color("f6d4de"), Color("f0e8d0"), Color("d8c4f4")]

const SURFACE_SHADER: Shader = preload("res://assets/shaders/water_v2_surface.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/water_v2_glow.gdshader")
const WR: GDScript = preload("res://src/water/water_rules.gd")


class SurfacePetal:
	var pos: Vector2 = Vector2.ZERO
	var phase: float = 0.0
	var age: float = 0.0
	var life: float = 12.0
	var color: Color = Color("f6d4de")
	var size_px: Vector2 = Vector2(2.0, 1.0)


class AirMote:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 2.0
	var z_vel: float = 20.0
	var age: float = 0.0
	var life: float = 0.7
	var color: Color = Color("d8f4f2")
	var size_px: Vector2 = Vector2.ONE


class SurfaceMoteLayer:
	extends Node2D
	var petals: Array[SurfacePetal] = []

	func _draw() -> void:
		for p: SurfacePetal in petals:
			var fade: float = minf(p.age * 2.0, (p.life - p.age) * 1.5)
			var c: Color = Color(p.color, clampf(fade, 0.0, 1.0) * 0.88)
			draw_rect(Rect2(p.pos.round(), p.size_px), c)


class AirMoteLayer:
	extends Node2D
	var motes: Array[AirMote] = []

	func _draw() -> void:
		for m: AirMote in motes:
			var fade: float = 1.0 - smoothstep(0.6, 1.0, m.age / maxf(m.life, 0.01))
			var draw_p: Vector2 = (m.pos - Vector2(0.0, m.z_h)).round()
			var c: Color = Color(m.color, clampf(fade, 0.0, 1.0) * 0.86)
			draw_rect(Rect2(draw_p, m.size_px), c)


class DebugOverlayLayer:
	extends Node2D
	var field: WaterField = null

	func _draw() -> void:
		if field == null or not field.debug_overlay:
			return
		var b: Rect2 = field.bounds
		draw_rect(b, Color(0.25, 0.85, 0.90, 0.25), false, 1.0)
		var step: float = 16.0
		var y: float = b.position.y + 8.0
		while y < b.end.y:
			var x: float = b.position.x + 8.0
			while x < b.end.x:
				var p: Vector2 = Vector2(x, y)
				var wf: Dictionary = field.water_field_at(p)
				var reg: int = int(wf.get("regime", 0))
				if bool(wf.get("water", false)):
					var col: Color = Color(0.20, 0.85, 0.75, 0.45)
					if reg == WR.REGIME_OCEAN:
						col = Color(0.20, 0.45, 0.95, 0.45)
					elif reg == WR.REGIME_PUDDLE:
						col = Color(0.75, 0.55, 0.95, 0.55)
					draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), col)
					var fl: Vector2 = field.water_flow_at(p)
					if fl.length_squared() > 1.0:
						draw_line(p, p + fl.limit_length(10.0), Color(0.95, 0.98, 0.75, 0.70), 1.0)
				elif bool(wf.get("wet_sand", false)):
					draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), Color(0.95, 0.75, 0.35, 0.45))
				x += step
			y += step


var bounds: Rect2 = Rect2(-1344.0, -144.0, 1152.0, 288.0)
var texel_px: float = CELL_PX
var debug_overlay: bool = false

var _map_w: int = 576
var _map_h: int = 144
var _deep_threshold: float = 0.64
var _prop_margin: float = 12.0
var _bank_width: float = 18.0
var _brook_flow_speed: float = 28.0
var _depth_min: float = 1.0
var _depth_max: float = 6.0
var _wade_speed_min: float = 0.66
var _wade_speed_max: float = 0.94

# Authoring float buffers (main thread only prior to build_maps)
var _sdf_buf: PackedFloat32Array = PackedFloat32Array()
var _depth_buf: PackedFloat32Array = PackedFloat32Array()
var _regime_buf: PackedByteArray = PackedByteArray()
var _bed_buf: PackedByteArray = PackedByteArray()
var _flow_x_buf: PackedFloat32Array = PackedFloat32Array()
var _flow_y_buf: PackedFloat32Array = PackedFloat32Array()
var _turb_buf: PackedFloat32Array = PackedFloat32Array()
var _shadow_buf: PackedFloat32Array = PackedFloat32Array()
var _petal_spawns: Array[Vector2] = []
var _maps_built: bool = false
var _committed: bool = false

# GPU images/textures & thread-safe COW byte snapshots
var _geo_img: Image = null
var _flow_img: Image = null
var _geo_tex: ImageTexture = null
var _flow_tex: ImageTexture = null
var _geo_bytes: PackedByteArray = PackedByteArray()
var _flow_bytes: PackedByteArray = PackedByteArray()
var _bytes_lock: Mutex = Mutex.new()
var _flow_dirty: bool = false
var _flow_flush_queued: bool = false

# Visual layers & materials
var _surface_rect: ColorRect = null
var _glow_rect: ColorRect = null
var _surface_mat: ShaderMaterial = null
var _glow_mat: ShaderMaterial = null
var _depth_body: StaticBody2D = null
var _surface_mote_layer: SurfaceMoteLayer = null
var _air_mote_layer: AirMoteLayer = null
var _debug_layer: DebugOverlayLayer = null

# Toroidal 128x128 @ 4x4 px wave ringbuffer
var _wave_cell_origin: Vector2i = Vector2i(-64, -64)
var _wave_origin: Vector2 = Vector2(-256.0, -256.0)
var _h_curr: PackedFloat32Array = PackedFloat32Array()
var _h_next: PackedFloat32Array = PackedFloat32Array()
var _v: PackedFloat32Array = PackedFloat32Array()
var _foam: PackedFloat32Array = PackedFloat32Array()
var _wave_bytes: PackedByteArray = PackedByteArray()
var _wave_img: Image = null
var _wave_tex: ImageTexture = null
var _wave_active: bool = false
var _wave_dirty: bool = false
var _wave_accum: float = 0.0
var _wave_step_idx: int = 0
var _act_min: Vector2i = Vector2i(0, 0)
var _act_max: Vector2i = Vector2i(-1, -1)
var _tile_active: PackedByteArray = PackedByteArray()
var _tile_next: PackedByteArray = PackedByteArray()
var _active_tiles: Array[int] = []
var _next_tiles: Array[int] = []
var _kept_tiles: Array[int] = []
var _cleared_tiles: Array[int] = []
var _swimmers: Dictionary = {} ## int -> Vector4(wx, wy, radius, energy)

# Main-thread scalar snapshots for lock-free Jobs queries & clock coordination
var _clock: float = 0.0
var _frame_water_time: float = 0.0
var _snap_wind_dir: Vector2 = Vector2.RIGHT
var _snap_wind_gust: float = 0.15
var _snap_storm: float = 0.0
var _snap_puddle: float = 0.0
var _snap_rain: float = 0.0
var _snap_golden: float = 0.0
var _snap_night: float = 0.0
var _petal_timer: float = 0.4
var _spray_timer: float = 0.15
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 41827
	if not Terrain.patches.has(self):
		Terrain.patches.append(self)
	if not tree_exiting.is_connected(_on_tree_exiting):
		tree_exiting.connect(_on_tree_exiting)
	_sync_frame_snapshots()
	_ensure_reflections.call_deferred()


func _on_tree_exiting() -> void:
	Terrain.patches.erase(self)


func _ensure_reflections() -> void:
	if not is_inside_tree():
		return
	if WaterReflections.current == null:
		var mirror: WaterReflections = WaterReflections.new()
		mirror.name = "Reflections"
		add_child(mirror)


func _active_world_rivers() -> WorldRivers:
	for patch: Node in Terrain.patches:
		if patch is WorldRivers and patch.is_inside_tree():
			return patch as WorldRivers
	return null


func _sync_frame_snapshots() -> void:
	var ww: WorldWind = WorldWind.current
	if ww != null:
		_snap_wind_dir = ww.direction
		_snap_wind_gust = ww.gust
	else:
		_snap_wind_dir = Vector2.RIGHT
		_snap_wind_gust = 0.15
	var wm: WeatherManager = WeatherManager.current
	if wm != null:
		_snap_storm = wm.storm
		_snap_puddle = wm.puddle
		_snap_rain = wm.rain
	else:
		_snap_storm = 0.0
		_snap_puddle = 0.0
		_snap_rain = 0.0
	_snap_golden = TimeManager.golden_amount()
	_snap_night = TimeManager.night_amount()


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	var wr: WorldRivers = _active_world_rivers()
	if wr != null:
		_frame_water_time = wr._clock
		_clock = _frame_water_time
	else:
		_clock += dt
		_frame_water_time = _clock
		RenderingServer.global_shader_parameter_set(&"g_water_time", _clock)

	_sync_frame_snapshots()

	if _glow_rect != null:
		var show_glow: bool = visible and _snap_night > 0.02
		_glow_rect.visible = show_glow
		if show_glow and _glow_mat != null:
			_glow_mat.set_shader_parameter("night", _snap_night)

	var vp: Viewport = get_viewport()
	if vp != null:
		var cam: Camera2D = vp.get_camera_2d()
		if cam != null:
			recenter_wave_field(cam.get_screen_center_position())

	_step_wave_ringbuffer(dt)
	_step_motes(dt)
	if debug_overlay and _debug_layer != null:
		_debug_layer.queue_redraw()


func set_debug_overlay(enabled: bool) -> void:
	debug_overlay = enabled
	if enabled and _debug_layer == null:
		_debug_layer = DebugOverlayLayer.new()
		_debug_layer.name = "WaterDebugOverlay"
		_debug_layer.z_as_relative = false
		_debug_layer.z_index = 10
		_debug_layer.field = self
		add_child(_debug_layer)
	if _debug_layer != null:
		_debug_layer.visible = enabled
		_debug_layer.queue_redraw()


# ==============================================================================
# Parametric / Procedural Builder API
# ==============================================================================

func configure(world_rect: Rect2, cell_size_px: float = 2.0, params: Dictionary = {}) -> void:
	setup_rect(world_rect, cell_size_px, params)


func setup_rect(world_rect: Rect2, cell_size_px: float = 2.0, params: Dictionary = {}) -> void:
	bounds = world_rect
	texel_px = maxf(cell_size_px, 1.0)
	_map_w = maxi(8, ceili(bounds.size.x / texel_px))
	_map_h = maxi(8, ceili(bounds.size.y / texel_px))

	var rivers_cfg: Dictionary = DataRegistry.table("rivers")
	var life_cfg: Dictionary = DataRegistry.table("river_life")
	_deep_threshold = float(params.get("deep_threshold", rivers_cfg.get("deep_threshold", 0.64)))
	_prop_margin = float(params.get("prop_margin", rivers_cfg.get("prop_margin", 12.0)))
	_bank_width = float(params.get("bank_width", 18.0))
	_brook_flow_speed = float(params.get("brook_flow_speed", 28.0))
	_depth_min = float(life_cfg.get("depth_min", 1.0))
	_depth_max = float(life_cfg.get("depth_max", 6.0))
	_wade_speed_min = float(life_cfg.get("wade_speed_min", 0.66))
	_wade_speed_max = float(life_cfg.get("wade_speed_max", 0.94))

	var total: int = _map_w * _map_h
	_sdf_buf.resize(total)
	_sdf_buf.fill(127.0)
	_depth_buf.resize(total)
	_depth_buf.fill(0.0)
	_regime_buf.resize(total)
	_regime_buf.fill(WR.REGIME_LAND)
	_bed_buf.resize(total)
	_bed_buf.fill(WR.BED_NONE)
	_flow_x_buf.resize(total)
	_flow_x_buf.fill(0.0)
	_flow_y_buf.resize(total)
	_flow_y_buf.fill(0.0)
	_turb_buf.resize(total)
	_turb_buf.fill(0.0)
	_shadow_buf.resize(total)
	_shadow_buf.fill(0.0)
	_petal_spawns.clear()
	_maps_built = false


func _ensure_setup() -> void:
	if _sdf_buf.is_empty():
		setup_rect(bounds)


func _texel_world_center(ix: int, iy: int) -> Vector2:
	return bounds.position + Vector2(float(ix) + 0.5, float(iy) + 0.5) * texel_px


func _smooth_path(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 2:
		return points
	var curve: PackedVector3Array = []
	for i: int in points.size() - 1:
		var a: Vector3 = points[maxi(0, i - 1)]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		var d: Vector3 = points[mini(points.size() - 1, i + 2)]
		var steps: int = maxi(2, ceili(Vector2(b.x, b.y).distance_to(Vector2(c.x, c.y)) / 10.0))
		for j: int in steps:
			var t: float = float(j) / float(steps)
			var q: Vector3 = 0.5 * (
				(2.0 * b)
				+ (-a + c) * t
				+ (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t
				+ (-a + 3.0 * b - 3.0 * c + d) * t * t * t
			)
			q.z = maxf(4.0, q.z)
			curve.append(q)
	curve.append(points[points.size() - 1])
	return curve


func add_brook(points: PackedVector3Array, params: Dictionary = {}) -> void:
	_ensure_setup()
	if points.size() < 2:
		return
	var curve: PackedVector3Array = _smooth_path(points)
	var base_depth: float = float(params.get("base_depth", 0.70))
	var bank_w: float = float(params.get("bank_width", _bank_width))
	var bed_id: int = int(params.get("bed", WR.BED_PEBBLE))
	var bank_bed: int = int(params.get("bank_bed", WR.BED_SILT))
	var fords: Array = params.get("fords", []) as Array
	var pools: Array = params.get("pools", []) as Array
	var noise_seed: float = float(params.get("shore_noise_seed", 17.0))

	# Track upstream spawn points for V12 surface petals
	if curve.size() >= 3:
		for k: int in range(1, mini(4, curve.size())):
			_petal_spawns.append(Vector2(curve[k].x, curve[k].y))

	for iy: int in _map_h:
		for ix: int in _map_w:
			var p: Vector2 = _texel_world_center(ix, iy)
			var shore_wobble: float = sin(p.y * 0.085 + noise_seed) * 2.1 + sin(p.y * 0.21 - p.x * 0.05) * 1.1
			var best_sdf: float = INF
			var best_radius: float = 24.0
			var best_flow: Vector2 = Vector2.DOWN
			for i: int in curve.size() - 1:
				var a: Vector3 = curve[i]
				var b: Vector3 = curve[i + 1]
				var a2: Vector2 = Vector2(a.x, a.y)
				var b2: Vector2 = Vector2(b.x, b.y)
				var delta: Vector2 = b2 - a2
				var l2: float = delta.length_squared()
				if l2 <= 0.0001:
					continue
				var t: float = clampf((p - a2).dot(delta) / l2, 0.0, 1.0)
				var radius: float = lerpf(a.z, b.z, t)
				var dist: float = p.distance_to(a2 + delta * t)
				var sdf: float = dist - radius - shore_wobble
				if sdf < best_sdf:
					best_sdf = sdf
					best_radius = radius
					best_flow = delta.normalized()

			if best_sdf > bank_w + 12.0:
				continue
			var idx: int = iy * _map_w + ix
			var prev_reg: int = _regime_buf[idx]
			if prev_reg == WR.REGIME_LAND or best_sdf < _sdf_buf[idx]:
				_sdf_buf[idx] = clampf(best_sdf, -128.0, 127.0)
				_regime_buf[idx] = WR.REGIME_BROOK
				_flow_x_buf[idx] = best_flow.x
				_flow_y_buf[idx] = best_flow.y
				if best_sdf <= 0.0:
					var norm_in: float = clampf(-best_sdf / maxf(best_radius, 1.0), 0.0, 1.0)
					var d_val: float = pow(norm_in, 0.72) * base_depth
					var local_bed: int = bed_id
					for pool_v: Variant in pools:
						var pool: Dictionary = pool_v as Dictionary
						var pc: Vector2 = pool.get("pos", Vector2.ZERO) as Vector2
						var pr: float = maxf(float(pool.get("radius", 28.0)), 1.0)
						var pd: float = p.distance_to(pc)
						if pd < pr:
							var pw: float = 1.0 - smoothstep(pr * 0.25, pr, pd)
							d_val = lerpf(d_val, float(pool.get("depth", 0.86)), pw)
							if pw > 0.45:
								local_bed = int(pool.get("bed", WR.BED_SILT))
					for ford_v: Variant in fords:
						var ford: Dictionary = ford_v as Dictionary
						var fc: Vector2 = ford.get("pos", Vector2.ZERO) as Vector2
						var fr: float = maxf(float(ford.get("radius", 32.0)), 1.0)
						var fd: float = p.distance_to(fc)
						if fd < fr:
							var fw: float = 1.0 - smoothstep(fr * 0.30, fr, fd)
							d_val = lerpf(d_val, minf(d_val, float(ford.get("depth", 0.26))), fw)
							local_bed = int(ford.get("bed", WR.BED_PEBBLE))
					_depth_buf[idx] = clampf(d_val, 0.03, 1.0)
					_bed_buf[idx] = local_bed
				else:
					_depth_buf[idx] = 0.0
					_bed_buf[idx] = bed_id if best_sdf < 6.0 else bank_bed


func add_lake(center: Vector2, radii: Vector2, params: Dictionary = {}) -> void:
	_ensure_setup()
	var rx: float = maxf(radii.x, 4.0)
	var ry: float = maxf(radii.y, 4.0)
	var max_depth: float = float(params.get("depth", 0.80))
	var bank_w: float = float(params.get("bank_width", _bank_width))
	var bed_id: int = int(params.get("bed", WR.BED_SILT))
	var bank_bed: int = int(params.get("bank_bed", WR.BED_MUD))
	var noise_seed: float = float(params.get("seed", 31.0))

	for iy: int in _map_h:
		for ix: int in _map_w:
			var p: Vector2 = _texel_world_center(ix, iy)
			var rel: Vector2 = Vector2((p.x - center.x) / rx, (p.y - center.y) / ry)
			var ang: float = atan2(rel.y, rel.x)
			var warp: float = 0.06 * sin(ang * 3.0 + noise_seed) + 0.035 * cos(ang * 5.0 - noise_seed * 0.7)
			var d_norm: float = rel.length() - warp
			var sdf: float = (d_norm - 1.0) * minf(rx, ry)
			if sdf > bank_w + 12.0:
				continue
			var idx: int = iy * _map_w + ix
			if _regime_buf[idx] == WR.REGIME_LAND or sdf < _sdf_buf[idx]:
				_sdf_buf[idx] = clampf(sdf, -128.0, 127.0)
				_regime_buf[idx] = WR.REGIME_LAKE
				_flow_x_buf[idx] = 0.0
				_flow_y_buf[idx] = 0.0
				if sdf <= 0.0:
					_depth_buf[idx] = clampf(pow(clampf(1.0 - d_norm, 0.0, 1.0), 0.7) * max_depth, 0.04, 1.0)
					_bed_buf[idx] = bed_id
				else:
					_depth_buf[idx] = 0.0
					_bed_buf[idx] = bank_bed


func _sample_shore_x(shore_points: PackedVector2Array, y_val: float) -> float:
	if shore_points.is_empty():
		return -748.0
	if y_val <= shore_points[0].y:
		return shore_points[0].x
	for i: int in shore_points.size() - 1:
		var a: Vector2 = shore_points[i]
		var b: Vector2 = shore_points[i + 1]
		if y_val <= b.y:
			var t: float = clampf((y_val - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0)
			return lerpf(a.x, b.x, t)
	return shore_points[shore_points.size() - 1].x


func add_coast(shore_points: PackedVector2Array, sea_side: int = -1, params: Dictionary = {}) -> void:
	_ensure_setup()
	var dir_sea: int = -1 if sea_side < 0 else 1
	var x_min: float = float(params.get("west_min_x", params.get("surf_min_x", bounds.position.x)))
	var x_max: float = float(params.get("surf_max_x", params.get("east_max_x", -576.0 if dir_sea < 0 else bounds.end.x)))
	var dry_sand_width: float = float(params.get("dry_sand_width", 148.0))
	var swash_margin: float = float(params.get("swash_margin", 40.0))
	var max_surf_depth: float = float(params.get("max_surf_depth", 0.46))
	var headlands: Array = params.get("headlands", []) as Array
	var seed_v: float = float(params.get("seed", 42.0))

	for iy: int in _map_h:
		for ix: int in _map_w:
			var p: Vector2 = _texel_world_center(ix, iy)
			if p.x < x_min or p.x > x_max:
				continue
			var shore_x: float = _sample_shore_x(shore_points, p.y)
			var shore_noise: float = sin(p.y * 0.045 + seed_v) * 4.5 + sin(p.y * 0.13 - seed_v * 0.4) * 2.0
			shore_x += shore_noise
			var sdf: float = (p.x - shore_x) * float(-dir_sea)
			var dune_wobble: float = sin(p.y * 0.055 + 1.3) * 10.0 + cos(p.y * 0.14) * 5.0
			var outer_sand_x: float = minf(shore_x + dry_sand_width + dune_wobble, x_max - 2.0 + sin(p.y * 0.08) * 6.0) if dir_sea < 0 else maxf(shore_x - dry_sand_width - dune_wobble, x_min + 2.0 + sin(p.y * 0.08) * 6.0)

			var in_headland: bool = false
			for hl_v: Variant in headlands:
				var hl: Dictionary = hl_v as Dictionary
				var hc: Vector2 = hl.get("center", Vector2.ZERO) as Vector2
				var hr: Vector2 = hl.get("radii", Vector2(40.0, 28.0)) as Vector2
				var rel: Vector2 = Vector2((p.x - hc.x) / maxf(hr.x, 1.0), (p.y - hc.y) / maxf(hr.y, 1.0))
				if rel.length() <= 1.0 + 0.12 * sin(atan2(rel.y, rel.x) * 4.0 + seed_v):
					in_headland = true
					break

			var idx: int = iy * _map_w + ix
			if sdf <= swash_margin:
				_sdf_buf[idx] = clampf(sdf, -128.0, 127.0)
				_regime_buf[idx] = WR.REGIME_SURF
				_bed_buf[idx] = WR.BED_ROCK if in_headland else WR.BED_SAND
				_flow_x_buf[idx] = float(-dir_sea) * 0.35
				_flow_y_buf[idx] = 0.0
				if sdf <= 0.0:
					var span: float = maxf((shore_x - x_min) if dir_sea < 0 else (x_max - shore_x), 24.0)
					var t_sea: float = clampf(-sdf / span, 0.0, 1.0)
					_depth_buf[idx] = clampf(0.06 + pow(t_sea, 0.78) * (max_surf_depth - 0.06), 0.04, max_surf_depth)
				else:
					_depth_buf[idx] = 0.0
			elif (p.x <= outer_sand_x if dir_sea < 0 else p.x >= outer_sand_x) or in_headland:
				_sdf_buf[idx] = clampf(sdf, -128.0, 127.0)
				_regime_buf[idx] = WR.REGIME_LAND
				_bed_buf[idx] = WR.BED_ROCK if in_headland else WR.BED_SAND
				_depth_buf[idx] = 0.0


func add_ocean(ocean_rect: Rect2, shelf_start_x: float, params: Dictionary = {}) -> void:
	_ensure_setup()
	var min_depth: float = float(params.get("min_depth", 0.465))
	var max_depth: float = float(params.get("max_depth", 1.0))
	var shelf_width: float = maxf(float(params.get("shelf_width", 210.0)), 16.0)
	var reefs: Array = params.get("reefs", []) as Array

	for iy: int in _map_h:
		for ix: int in _map_w:
			var p: Vector2 = _texel_world_center(ix, iy)
			if not ocean_rect.has_point(p):
				continue
			var idx: int = iy * _map_w + ix
			var shelf_x: float = shelf_start_x - (8.0 + sin(p.y * 0.055) * 6.0 + cos(p.y * 0.13) * 2.0)
			var dist_west: float = maxf(shelf_x - p.x, 0.0)
			var t_shelf: float = smoothstep(0.0, shelf_width, dist_west)
			var d_val: float = lerpf(min_depth, max_depth, t_shelf)
			var bed_id: int = WR.BED_SAND
			for rf_v: Variant in reefs:
				var rf: Dictionary = rf_v as Dictionary
				var rc: Vector2 = rf.get("center", Vector2.ZERO) as Vector2
				var rr: Vector2 = rf.get("radii", Vector2(44.0, 26.0)) as Vector2
				var rel: Vector2 = Vector2((p.x - rc.x) / maxf(rr.x, 1.0), (p.y - rc.y) / maxf(rr.y, 1.0))
				if rel.length() <= 1.0 + 0.14 * sin(atan2(rel.y, rel.x) * 3.0):
					bed_id = WR.BED_REEF
					d_val = maxf(min_depth, d_val - 0.10)
					break
			_sdf_buf[idx] = clampf(-dist_west - 32.0, -128.0, -16.0)
			_depth_buf[idx] = clampf(d_val, 0.10, 1.0)
			_regime_buf[idx] = WR.REGIME_OCEAN
			_bed_buf[idx] = bed_id
			_flow_x_buf[idx] = 0.25
			_flow_y_buf[idx] = 0.0


func add_puddle(center: Vector2, radii: Vector2, params: Dictionary = {}) -> void:
	_ensure_setup()
	var rx: float = maxf(radii.x, 3.0)
	var ry: float = maxf(radii.y, 3.0)
	var basin_depth: float = clampf(float(params.get("depth", 0.22)), 0.15, 0.35)
	var bed_id: int = int(params.get("bed", WR.BED_MUD))
	var rain_only: bool = bool(params.get("rain_only", false))
	var seed_v: float = float(params.get("seed", 77.0))
	var outer_margin: float = 14.0

	for iy: int in _map_h:
		for ix: int in _map_w:
			var p: Vector2 = _texel_world_center(ix, iy)
			var rel: Vector2 = Vector2((p.x - center.x) / rx, (p.y - center.y) / ry)
			var ang: float = atan2(rel.y, rel.x)
			var warp: float = 0.11 * sin(ang * 3.0 + seed_v) + 0.05 * cos(ang * 5.0 - seed_v * 0.6)
			var d_norm: float = rel.length() - warp
			var sdf: float = d_norm * minf(rx, ry) + 1.5 if rain_only else (d_norm - 1.0) * minf(rx, ry)
			if sdf > outer_margin:
				continue
			var idx: int = iy * _map_w + ix
			var cur_reg: int = int(_regime_buf[idx])
			# Never overwrite active rivers/lakes/ocean water, but DO allow full unclipped puddles on dry outer bank/sand margins!
			if cur_reg == WR.REGIME_OCEAN:
				continue
			if cur_reg in [WR.REGIME_BROOK, WR.REGIME_LAKE] and _sdf_buf[idx] <= 8.5:
				continue
			if cur_reg == WR.REGIME_SURF:
				var min_surf_sdf: float = 4.0 if int(_bed_buf[idx]) == WR.BED_ROCK else 24.0
				if _sdf_buf[idx] < min_surf_sdf:
					continue
			if cur_reg == WR.REGIME_PUDDLE and _sdf_buf[idx] < sdf:
				continue
			_sdf_buf[idx] = clampf(sdf, -128.0, 127.0)
			_depth_buf[idx] = basin_depth
			_regime_buf[idx] = WR.REGIME_PUDDLE
			_bed_buf[idx] = bed_id
			_flow_x_buf[idx] = 0.0
			_flow_y_buf[idx] = 0.0


func build_maps() -> void:
	_ensure_setup()
	_geo_img = Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	_flow_img = Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)

	var geo_raw: PackedByteArray = PackedByteArray()
	var flow_raw: PackedByteArray = PackedByteArray()
	geo_raw.resize(_map_w * _map_h * 4)
	flow_raw.resize(_map_w * _map_h * 4)

	for idx: int in _map_w * _map_h:
		var bi: int = idx * 4
		geo_raw[bi] = clampi(roundi(_sdf_buf[idx] + 128.0), 0, 255)
		geo_raw[bi + 1] = clampi(roundi(_depth_buf[idx] * 255.0), 0, 255)
		geo_raw[bi + 2] = clampi(int(_regime_buf[idx]), 0, 255)
		geo_raw[bi + 3] = clampi(int(_bed_buf[idx]), 0, 255)

		flow_raw[bi] = clampi(roundi(_flow_x_buf[idx] * 127.0 + 128.0), 1, 255)
		flow_raw[bi + 1] = clampi(roundi(_flow_y_buf[idx] * 127.0 + 128.0), 1, 255)
		flow_raw[bi + 2] = clampi(roundi(_turb_buf[idx] * 255.0), 0, 255)
		flow_raw[bi + 3] = clampi(roundi(_shadow_buf[idx] * 255.0), 0, 255)

	_geo_img.set_data(_map_w, _map_h, false, Image.FORMAT_RGBA8, geo_raw)
	_flow_img.set_data(_map_w, _map_h, false, Image.FORMAT_RGBA8, flow_raw)
	_maps_built = true
	commit()


func commit() -> void:
	if not _maps_built:
		build_maps()
		return

	var next_geo: PackedByteArray = _geo_img.get_data()
	var next_flow: PackedByteArray = _flow_img.get_data()
	_bytes_lock.lock()
	_geo_bytes = next_geo
	_flow_bytes = next_flow
	_bytes_lock.unlock()

	_geo_tex = ImageTexture.create_from_image(_geo_img)
	_flow_tex = ImageTexture.create_from_image(_flow_img)
	_init_wave_ringbuffer()
	_ensure_render_layers()
	_apply_shader_params()
	_rebuild_depth_colliders()
	_committed = true


func build_grass_lab_west() -> void:
	setup_rect(Rect2(-1344.0, -144.0, 1152.0, 288.0), CELL_PX)

	# Square -1 (x in [-576, -192]): Forest Brook, northern Kolk, southern Kiesfurt, & R5 puddles
	var brook_pts: PackedVector3Array = [
		Vector3(-396.0, -156.0, 34.0),
		Vector3(-388.0, -96.0, 38.0),
		Vector3(-376.0, -40.0, 34.0),
		Vector3(-384.0, 0.0, 34.0),
		Vector3(-394.0, 46.0, 36.0),
		Vector3(-372.0, 96.0, 38.0),
		Vector3(-368.0, 156.0, 36.0),
	]
	add_brook(brook_pts, {
		"base_depth": 0.70,
		"bank_width": 18.0,
		"bed": WR.BED_PEBBLE,
		"bank_bed": WR.BED_SILT,
		"pools": [
			{"pos": Vector2(-388.0, -94.0), "radius": 38.0, "depth": 0.86, "bed": WR.BED_SILT},
		],
		"fords": [
			{"pos": Vector2(-372.0, 96.0), "radius": 36.0, "depth": 0.26, "bed": WR.BED_PEBBLE},
		],
		"shore_noise_seed": 19.0,
	})
	# Square -1 R5 bank & bridge-approach puddles (cleanly clear of bridge parapet & bounds edges!)
	add_puddle(Vector2(-316.0, 26.0), Vector2(14.0, 9.0), {"depth": 0.22, "bed": WR.BED_MUD, "seed": 11.0})
	add_puddle(Vector2(-462.0, -40.0), Vector2(15.0, 10.0), {"depth": 0.24, "bed": WR.BED_MUD, "seed": 23.0})
	add_puddle(Vector2(-284.0, 88.0), Vector2(12.0, 8.0), {"depth": 0.20, "bed": WR.BED_MUD, "rain_only": true, "seed": 37.0})

	# Square -2 (x in [-960, -576]): Beach & Coastal Biome, northern headland + tidepools, beach puddle
	var coast_pts: PackedVector2Array = [
		Vector2(-730.0, -148.0),
		Vector2(-744.0, -76.0),
		Vector2(-756.0, -16.0),
		Vector2(-748.0, 56.0),
		Vector2(-736.0, 148.0),
	]
	add_coast(coast_pts, -1, {
		"surf_min_x": -960.0,
		"east_max_x": -556.0,
		"dry_sand_width": 130.0,
		"swash_margin": 40.0,
		"max_surf_depth": 0.46,
		"headlands": [
			{"center": Vector2(-722.0, -104.0), "radii": Vector2(54.0, 36.0)},
		],
		"seed": 42.0,
	})
	# Square -2 R5 rocky headland tidepools + beach-hollow puddle
	add_puddle(Vector2(-718.0, -106.0), Vector2(14.0, 9.0), {"depth": 0.30, "bed": WR.BED_ROCK, "seed": 53.0})
	add_puddle(Vector2(-694.0, -88.0), Vector2(12.0, 8.0), {"depth": 0.26, "bed": WR.BED_ROCK, "seed": 67.0})
	add_puddle(Vector2(-674.0, 48.0), Vector2(15.0, 10.0), {"depth": 0.20, "bed": WR.BED_SAND, "seed": 79.0})

	# Square -3 (x in [-1344, -960]): Open Ocean shelf drop-off + deep reefs
	add_ocean(Rect2(-1344.0, -144.0, 384.0, 288.0), -960.0, {
		"min_depth": 0.465,
		"max_depth": 1.0,
		"shelf_width": 210.0,
		"reefs": [
			{"center": Vector2(-1060.0, -48.0), "radii": Vector2(48.0, 28.0)},
			{"center": Vector2(-1140.0, 62.0), "radii": Vector2(56.0, 32.0)},
		],
	})

	build_maps()


func _ensure_render_layers() -> void:
	if _surface_mat == null:
		_surface_mat = ShaderMaterial.new()
		_surface_mat.shader = SURFACE_SHADER
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = GLOW_SHADER

	if _surface_rect == null:
		_surface_rect = ColorRect.new()
		_surface_rect.name = "WaterSurfaceRect"
		_surface_rect.z_as_relative = false
		_surface_rect.z_index = -7
		_surface_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface_rect.material = _surface_mat
		add_child(_surface_rect)
	_surface_rect.position = bounds.position
	_surface_rect.size = bounds.size

	if _glow_rect == null:
		_glow_rect = ColorRect.new()
		_glow_rect.name = "WaterGlowRect"
		_glow_rect.z_as_relative = false
		_glow_rect.z_index = -6
		_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow_rect.material = _glow_mat
		add_child(_glow_rect)
	_glow_rect.position = bounds.position
	_glow_rect.size = bounds.size
	_glow_rect.visible = visible and TimeManager.night_amount() > 0.02

	if _surface_mote_layer == null:
		_surface_mote_layer = SurfaceMoteLayer.new()
		_surface_mote_layer.name = "WaterSurfaceMotes"
		_surface_mote_layer.z_as_relative = false
		_surface_mote_layer.z_index = -5
		add_child(_surface_mote_layer)

	if _air_mote_layer == null:
		_air_mote_layer = AirMoteLayer.new()
		_air_mote_layer.name = "WaterAirMotes"
		_air_mote_layer.z_as_relative = false
		_air_mote_layer.z_index = 2
		add_child(_air_mote_layer)


func _apply_shader_params() -> void:
	for mat: ShaderMaterial in [_surface_mat, _glow_mat]:
		if mat == null:
			continue
		mat.set_shader_parameter("map_origin", bounds.position)
		mat.set_shader_parameter("map_size", bounds.size)
		mat.set_shader_parameter("water_geo_map", _geo_tex)
		mat.set_shader_parameter("water_flow_map", _flow_tex)
		mat.set_shader_parameter("wave_origin", _wave_origin)
		mat.set_shader_parameter("wave_field_size", WAVE_FIELD_SIZE)
		mat.set_shader_parameter("wave_ringbuffer", _wave_tex)
	if _surface_mat != null:
		_surface_mat.set_shader_parameter("bank_reach_px", _bank_width)
		_surface_mat.set_shader_parameter("deep_threshold", _deep_threshold)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("night", TimeManager.night_amount())


func _rebuild_depth_colliders() -> void:
	if _depth_body != null and is_instance_valid(_depth_body):
		_depth_body.queue_free()
		_depth_body = null

	var body: StaticBody2D = StaticBody2D.new()
	body.name = "RiverDepth"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("river_depth")
	add_child(body)
	_depth_body = body

	var mask: PackedByteArray = PackedByteArray()
	mask.resize(_map_w * _map_h)
	for idx: int in _map_w * _map_h:
		var reg: int = int(_regime_buf[idx])
		if reg != WR.REGIME_PUDDLE and _sdf_buf[idx] <= 0.0 and _depth_buf[idx] > _deep_threshold:
			mask[idx] = 1
		else:
			mask[idx] = 0

	# Greedy 2D maximal rectangle merge
	for iy: int in _map_h:
		for ix: int in _map_w:
			var start_idx: int = iy * _map_w + ix
			if mask[start_idx] == 0:
				continue
			var w: int = 1
			while ix + w < _map_w and mask[iy * _map_w + ix + w] == 1:
				w += 1
			var h: int = 1
			var can_grow: bool = true
			while iy + h < _map_h and can_grow:
				for kx: int in range(ix, ix + w):
					if mask[(iy + h) * _map_w + kx] == 0:
						can_grow = false
						break
				if can_grow:
					h += 1
			for ry: int in range(iy, iy + h):
				for rx: int in range(ix, ix + w):
					mask[ry * _map_w + rx] = 0
			var box: RectangleShape2D = RectangleShape2D.new()
			box.size = Vector2(float(w), float(h)) * texel_px
			var shape: CollisionShape2D = CollisionShape2D.new()
			shape.shape = box
			shape.position = bounds.position + (Vector2(float(ix), float(iy)) + Vector2(float(w), float(h)) * 0.5) * texel_px
			body.add_child(shape)


# ==============================================================================
# Obstacle & Shadow Injection (Main Thread, Coalesced Deferred GPU Upload)
# ==============================================================================

func inject_obstacle(world_pos: Vector2, radius_px: float, strength: float = 1.0) -> void:
	_ensure_setup()
	var r: float = maxf(radius_px, 2.0)
	var s: float = clampf(strength, 0.0, 2.0)
	var wake_reach: float = r * 3.8 + 10.0
	var min_x: int = clampi(floori((world_pos.x - wake_reach - bounds.position.x) / texel_px), 0, _map_w - 1)
	var max_x: int = clampi(ceili((world_pos.x + wake_reach - bounds.position.x) / texel_px), 0, _map_w - 1)
	var min_y: int = clampi(floori((world_pos.y - wake_reach - bounds.position.y) / texel_px), 0, _map_h - 1)
	var max_y: int = clampi(ceili((world_pos.y + wake_reach * 1.6 - bounds.position.y) / texel_px), 0, _map_h - 1)

	for iy: int in range(min_y, max_y + 1):
		for ix: int in range(min_x, max_x + 1):
			var idx: int = iy * _map_w + ix
			var reg: int = int(_regime_buf[idx])
			var bed_here: int = int(_bed_buf[idx])
			if reg == WR.REGIME_LAND and bed_here != WR.BED_SAND and bed_here != WR.BED_ROCK:
				continue
			var p: Vector2 = _texel_world_center(ix, iy)
			var base_flow: Vector2 = Vector2(_flow_x_buf[idx], _flow_y_buf[idx])
			var fdir: Vector2 = base_flow.normalized() if base_flow.length_squared() > 0.001 else Vector2.DOWN
			var across: Vector2 = Vector2(-fdir.y, fdir.x)
			var rel: Vector2 = p - world_pos
			var dist: float = rel.length()

			# Deflect flow tangentially around obstacle in flowing water
			if reg != WR.REGIME_LAND and dist < r * 2.2 and dist > 0.01:
				var side_sign: float = 1.0 if rel.dot(across) >= 0.0 else -1.0
				var tangent: Vector2 = across * side_sign * 0.85 + fdir * 0.52
				var blend_k: float = (1.0 - smoothstep(r * 0.4, r * 2.2, dist)) * clampf(s, 0.0, 1.0)
				var new_flow: Vector2 = base_flow.lerp(tangent.normalized() * maxf(base_flow.length(), 0.75), blend_k)
				_flow_x_buf[idx] = clampf(new_flow.x, -1.0, 1.0)
				_flow_y_buf[idx] = clampf(new_flow.y, -1.0, 1.0)

			var turb: float = 0.0
			if reg == WR.REGIME_BROOK or reg == WR.REGIME_LAKE:
				# Upstream bow foam collar + downstream V-shaped wake eddies
				var along: float = rel.dot(fdir)
				var side: float = absf(rel.dot(across))
				if dist >= r * 0.6 and dist <= r * 1.45 and along < r * 0.35:
					turb = maxf(turb, (1.0 - absf(dist - r) / (r * 0.55)) * 0.95)
				if along > 0.0 and along < wake_reach * 1.4:
					var v_half: float = r * 0.85 + along * 0.34
					if side <= v_half:
						var edge_v: float = 1.0 - absf(side - v_half * 0.72) / maxf(v_half * 0.45, 1.0)
						var fade_l: float = 1.0 - along / (wake_reach * 1.4)
						turb = maxf(turb, clampf(edge_v * fade_l * 0.85, 0.0, 1.0))
			else:
				# Coastal surf/sand radial obstacle halo -> drives live wave-lap surge, concentric splash foam & wet sand collar!
				var ell_d: float = Vector2(rel.x, rel.y * 1.25).length()
				if ell_d < r * 2.15:
					turb = (1.0 - smoothstep(r * 0.30, r * 2.15, ell_d)) * 0.95
			_turb_buf[idx] = clampf(maxf(_turb_buf[idx], turb * s), 0.0, 1.0)

			if _committed and _flow_img != null:
				_flow_img.set_pixel(ix, iy, Color(
					float(clampi(roundi(_flow_x_buf[idx] * 127.0 + 128.0), 1, 255)) / 255.0,
					float(clampi(roundi(_flow_y_buf[idx] * 127.0 + 128.0), 1, 255)) / 255.0,
					_turb_buf[idx],
					_shadow_buf[idx]
				))

	if _committed and _flow_img != null:
		var next_flow: PackedByteArray = _flow_img.get_data()
		_bytes_lock.lock()
		_flow_bytes = next_flow
		_bytes_lock.unlock()
		_flow_dirty = true
		if not _flow_flush_queued:
			_flow_flush_queued = true
			_flush_flow_upload.call_deferred()


func inject_shadow_rect(world_rect: Rect2, shadow_amount: float = 1.0) -> void:
	_ensure_setup()
	var sh: float = clampf(shadow_amount, 0.0, 1.0)
	var min_x: int = clampi(floori((world_rect.position.x - 2.0 - bounds.position.x) / texel_px), 0, _map_w - 1)
	var max_x: int = clampi(ceili((world_rect.end.x + 2.0 - bounds.position.x) / texel_px), 0, _map_w - 1)
	var min_y: int = clampi(floori((world_rect.position.y - 2.0 - bounds.position.y) / texel_px), 0, _map_h - 1)
	var max_y: int = clampi(ceili((world_rect.end.y + 2.0 - bounds.position.y) / texel_px), 0, _map_h - 1)

	for iy: int in range(min_y, max_y + 1):
		for ix: int in range(min_x, max_x + 1):
			var p: Vector2 = _texel_world_center(ix, iy)
			var dx: float = maxf(world_rect.position.x - p.x, p.x - world_rect.end.x)
			var dy: float = maxf(world_rect.position.y - p.y, p.y - world_rect.end.y)
			var edge_d: float = maxf(dx, dy)
			if edge_d > 2.0:
				continue
			var feather: float = 1.0 - smoothstep(-1.5, 2.0, edge_d)
			var idx: int = iy * _map_w + ix
			_shadow_buf[idx] = clampf(maxf(_shadow_buf[idx], sh * feather), 0.0, 1.0)

			if _committed and _flow_img != null:
				_flow_img.set_pixel(ix, iy, Color(
					float(clampi(roundi(_flow_x_buf[idx] * 127.0 + 128.0), 1, 255)) / 255.0,
					float(clampi(roundi(_flow_y_buf[idx] * 127.0 + 128.0), 1, 255)) / 255.0,
					_turb_buf[idx],
					_shadow_buf[idx]
				))

	if _committed and _flow_img != null:
		var next_flow: PackedByteArray = _flow_img.get_data()
		_bytes_lock.lock()
		_flow_bytes = next_flow
		_bytes_lock.unlock()
		_flow_dirty = true
		if not _flow_flush_queued:
			_flow_flush_queued = true
			_flush_flow_upload.call_deferred()


func _flush_flow_upload() -> void:
	_flow_flush_queued = false
	if _flow_dirty and _flow_tex != null and _flow_img != null:
		_flow_tex.update(_flow_img)
		_flow_dirty = false


# ==============================================================================
# Lock-Free Thread-Safe Consumer API (Jobs & Terrain.patches Compatible)
# ==============================================================================

func _snapshot_bytes() -> Array:
	_bytes_lock.lock()
	var g: PackedByteArray = _geo_bytes
	var f: PackedByteArray = _flow_bytes
	_bytes_lock.unlock()
	return [g, f]


## Returns Vector4(sdf_px, depth, float(regime), float(bed_id)) matching GPU w2_sample_geo().
func _sample_geo_from_bytes(world_pos: Vector2, geo: PackedByteArray) -> Vector4:
	var fx: float = (world_pos.x - bounds.position.x) / texel_px - 0.5
	var fy: float = (world_pos.y - bounds.position.y) / texel_px - 0.5
	var c0x: int = floori(fx)
	var c0y: int = floori(fy)
	var frx: float = fx - float(c0x)
	var fry: float = fy - float(c0y)

	var x0: int = clampi(c0x, 0, _map_w - 1)
	var x1: int = clampi(c0x + 1, 0, _map_w - 1)
	var y0: int = clampi(c0y, 0, _map_h - 1)
	var y1: int = clampi(c0y + 1, 0, _map_h - 1)

	var i00: int = (y0 * _map_w + x0) * 4
	var i10: int = (y0 * _map_w + x1) * 4
	var i01: int = (y1 * _map_w + x0) * 4
	var i11: int = (y1 * _map_w + x1) * 4

	var r0: float = lerpf(float(geo[i00]), float(geo[i10]), frx)
	var r1: float = lerpf(float(geo[i01]), float(geo[i11]), frx)
	var sdf_px: float = lerpf(r0, r1, fry) - 128.0

	var g0: float = lerpf(float(geo[i00 + 1]), float(geo[i10 + 1]), frx)
	var g1: float = lerpf(float(geo[i01 + 1]), float(geo[i11 + 1]), frx)
	var depth: float = lerpf(g0, g1, fry) / 255.0

	var nx: int = clampi(floori((world_pos.x - bounds.position.x) / texel_px), 0, _map_w - 1)
	var ny: int = clampi(floori((world_pos.y - bounds.position.y) / texel_px), 0, _map_h - 1)
	var ni: int = (ny * _map_w + nx) * 4
	var regime: int = int(geo[ni + 2])
	var bed_id: int = int(geo[ni + 3])
	return Vector4(sdf_px, depth, float(regime), float(bed_id))


func _sample_flow_from_bytes(world_pos: Vector2, flow: PackedByteArray) -> Vector4:
	var nx: int = clampi(floori((world_pos.x - bounds.position.x) / texel_px), 0, _map_w - 1)
	var ny: int = clampi(floori((world_pos.y - bounds.position.y) / texel_px), 0, _map_h - 1)
	var ni: int = (ny * _map_w + nx) * 4
	var fx: float = clampf((float(flow[ni]) - 128.0) / 127.0, -1.0, 1.0)
	var fy: float = clampf((float(flow[ni + 1]) - 128.0) / 127.0, -1.0, 1.0)
	if absf(fx) < 0.012:
		fx = 0.0
	if absf(fy) < 0.012:
		fy = 0.0
	return Vector4(fx, fy, float(flow[ni + 2]) / 255.0, float(flow[ni + 3]) / 255.0)


func has_water_deck_at(_world_pos: Vector2) -> bool:
	return false


func field_at(world_pos: Vector2) -> Vector2:
	if not bounds.has_point(world_pos):
		return Vector2(INF, 0.0)
	var snap: Array = _snapshot_bytes()
	var geo: PackedByteArray = snap[0] as PackedByteArray
	if geo.is_empty():
		return Vector2(INF, 0.0)
	var g: Vector4 = _sample_geo_from_bytes(world_pos, geo)
	return Vector2(g.x, g.y)


func water_field_at(world_pos: Vector2) -> Dictionary:
	if not bounds.has_point(world_pos):
		return {
			"in_bounds": false,
			"sdf_px": INF,
			"static_sdf_px": INF,
			"depth": 0.0,
			"regime": 0,
			"bed_id": 0,
			"water": false,
			"wet_sand": false,
			"wetness": 0.0,
			"puddle": false,
			"shadow": 0.0,
			"turbulence": 0.0,
		}
	var snap: Array = _snapshot_bytes()
	var geo: PackedByteArray = snap[0] as PackedByteArray
	var flow: PackedByteArray = snap[1] as PackedByteArray
	if geo.is_empty() or flow.is_empty():
		return {
			"in_bounds": false,
			"sdf_px": INF,
			"static_sdf_px": INF,
			"depth": 0.0,
			"regime": 0,
			"bed_id": 0,
			"water": false,
			"wet_sand": false,
			"wetness": 0.0,
			"puddle": false,
			"shadow": 0.0,
			"turbulence": 0.0,
		}

	var g: Vector4 = _sample_geo_from_bytes(world_pos, geo)
	var f: Vector4 = _sample_flow_from_bytes(world_pos, flow)
	var static_sdf: float = g.x
	var eff_sdf: float = static_sdf
	var eff_depth: float = g.y
	var regime: int = int(g.z)
	var bed_id: int = int(g.w)
	var in_water: bool = false
	var wet_sand: bool = false
	var wetness: float = 0.0
	var is_puddle: bool = false

	if regime == WR.REGIME_SURF:
		var swash_off: float = WR.swash_offset_px(world_pos.y, _frame_water_time, _snap_wind_dir, _snap_wind_gust, _snap_storm)
		eff_sdf = static_sdf - swash_off
		in_water = eff_sdf <= 0.0
		if in_water:
			wetness = 1.0
			var swash_film: float = clampf(-eff_sdf * 0.006, 0.0, 0.14)
			eff_depth = clampf(maxf(eff_depth, swash_film), 0.02, 0.46)
		else:
			wetness = WR.sand_wetness(static_sdf, world_pos.y, _frame_water_time, _snap_wind_dir, _snap_wind_gust, _snap_storm)
			wet_sand = wetness > WR.WET_THRESHOLD
			eff_depth = 0.0
	elif regime == WR.REGIME_PUDDLE:
		eff_sdf = static_sdf - WR.puddle_reach_px(_snap_puddle)
		in_water = eff_sdf <= 0.0
		is_puddle = in_water
		eff_depth = WR.puddle_depth_at(static_sdf, g.y, _snap_puddle) if in_water else 0.0
	elif regime == WR.REGIME_BROOK or regime == WR.REGIME_LAKE or regime == WR.REGIME_OCEAN:
		in_water = static_sdf <= 0.0

	return {
		"in_bounds": true,
		"sdf_px": eff_sdf,
		"static_sdf_px": static_sdf,
		"depth": eff_depth,
		"regime": regime,
		"bed_id": bed_id,
		"water": in_water,
		"wet_sand": wet_sand,
		"wetness": wetness,
		"puddle": is_puddle,
		"shadow": f.w,
		"turbulence": f.z,
	}


func water_flow_at(world_pos: Vector2) -> Vector2:
	var wf: Dictionary = water_field_at(world_pos)
	if not bool(wf["in_bounds"]) or not bool(wf["water"]):
		return Vector2.ZERO
	var regime: int = int(wf["regime"])
	if regime == WR.REGIME_LAKE or regime == WR.REGIME_PUDDLE:
		return Vector2.ZERO
	if regime == WR.REGIME_SURF or regime == WR.REGIME_OCEAN:
		return WR.flow_drift_at(world_pos, _frame_water_time, _snap_wind_dir, _snap_wind_gust, _snap_storm, regime, float(wf["depth"]))
	var snap: Array = _snapshot_bytes()
	var flow: PackedByteArray = snap[1] as PackedByteArray
	if flow.is_empty():
		return Vector2.ZERO
	var f: Vector4 = _sample_flow_from_bytes(world_pos, flow)
	var bank_taper: float = smoothstep(0.0, 6.0, -float(wf["sdf_px"]))
	var turb_drag: float = 1.0 - 0.35 * float(wf["turbulence"])
	return Vector2(f.x, f.y) * (_brook_flow_speed * bank_taper * turb_drag)


func water_color_at(world_pos: Vector2) -> Dictionary:
	var wf: Dictionary = water_field_at(world_pos)
	var regime: int = int(wf["regime"])
	var fill: Color = Color("438780")
	var rim: Color = Color("91bbae")
	var foam: Color = Color("bfe9ff")
	if regime == WR.REGIME_BROOK:
		fill = Color("2d6d64")
		rim = Color("7ec4b0")
		foam = Color("d2f0e6")
	elif regime == WR.REGIME_LAKE or regime == WR.REGIME_PUDDLE:
		fill = Color("387c78")
		rim = Color("8fc6be")
		foam = Color("d8f2f0")
	elif regime == WR.REGIME_SURF:
		fill = Color("28949a")
		rim = Color("8ee6de")
		foam = Color("eefcfa")
	elif regime == WR.REGIME_OCEAN:
		fill = Color("184b6e")
		rim = Color("66b4c8")
		foam = Color("e4f6fc")

	if _snap_golden > 0.01:
		var gold: float = clampf(_snap_golden * 0.45, 0.0, 0.55)
		rim = rim.lerp(Color("f6cf8a"), gold)
		foam = foam.lerp(Color("fff0c8"), gold * 0.8)
	if _snap_night > 0.01:
		var nk: float = clampf(_snap_night, 0.0, 1.0)
		fill = fill.lerp(Color("14243d"), nk * 0.65)
		rim = rim.lerp(Color("8fb4e8"), nk * 0.45)
	return {"fill": fill, "rim": rim, "foam": foam}


func surface_at(world_pos: Vector2) -> String:
	var wf: Dictionary = water_field_at(world_pos)
	if not bool(wf["in_bounds"]):
		return ""
	var regime: int = int(wf["regime"])
	var bed_id: int = int(wf["bed_id"])
	var eff_sdf: float = float(wf["sdf_px"])
	var depth: float = float(wf["depth"])

	if regime == WR.REGIME_PUDDLE:
		if bool(wf["water"]):
			return "puddle"
		if eff_sdf <= 4.0 and bed_id == WR.BED_SAND:
			return "wet_sand"
		if eff_sdf <= 4.0 and bed_id == WR.BED_MUD:
			return "mud"
		if bed_id == WR.BED_SAND:
			return "beach_sand"
		if bed_id == WR.BED_ROCK:
			return "stone"
		return ""

	if regime == WR.REGIME_SURF:
		if bool(wf["water"]):
			return "deep_water" if (depth > _deep_threshold and float(wf["static_sdf_px"]) <= -4.0) else "tide_shallow"
		if bool(wf["wet_sand"]):
			return "wet_sand"
		if bed_id == WR.BED_ROCK:
			return "stone"
		if bed_id == WR.BED_SAND:
			return "beach_sand"
		return ""

	if regime == WR.REGIME_OCEAN:
		return "deep_water" if depth > _deep_threshold else "shallow_water"

	if regime == WR.REGIME_BROOK or regime == WR.REGIME_LAKE:
		if bool(wf["water"]):
			return "deep_water" if depth > _deep_threshold else "shallow_water"
		if bed_id == WR.BED_SAND:
			return "beach_sand"
		return ""

	if bed_id == WR.BED_SAND:
		return "beach_sand"
	if bed_id == WR.BED_ROCK:
		return "stone"
	return ""


func wade_data(world_pos: Vector2, base: Dictionary) -> Dictionary:
	var wf: Dictionary = water_field_at(world_pos)
	if not bool(wf["in_bounds"]) or not bool(wf["water"]):
		return base
	var cols: Dictionary = water_color_at(world_pos)
	var result: Dictionary = base.duplicate(true)
	result["water_color"] = cols["fill"]
	result["water_rim"] = cols["rim"]
	result["water_foam"] = cols["foam"]
	result["ripples"] = true

	var regime: int = int(wf["regime"])
	var depth: float = float(wf["depth"])
	if regime == WR.REGIME_PUDDLE:
		# Shallow puddle: splashes, ripples & wet footprints via FootstepComponent, NEVER triggers deep swim!
		result["water"] = false
		result["depth_amount"] = clampf(depth, 0.05, 0.25)
		result["submerge"] = lerpf(1.0, 2.5, clampf(depth * 2.5, 0.0, 1.0))
		result["flow_velocity"] = Vector2.ZERO
		return result

	var amount: float = clampf(depth / _deep_threshold, 0.0, 1.0)
	result["water"] = true
	result["depth_amount"] = amount
	result["submerge"] = lerpf(_depth_min, _depth_max, amount)
	result["speed"] = lerpf(_wade_speed_max, _wade_speed_min, amount)
	result["flow_velocity"] = water_flow_at(world_pos)
	return result


func depth_amount(world_pos: Vector2) -> float:
	var wf: Dictionary = water_field_at(world_pos)
	if not bool(wf["water"]):
		return -1.0
	if int(wf["regime"]) == WR.REGIME_PUDDLE:
		return clampf(float(wf["depth"]) / _deep_threshold, 0.05, 0.55)
	return float(wf["depth"]) / _deep_threshold


func is_deep(world_pos: Vector2) -> bool:
	var wf: Dictionary = water_field_at(world_pos)
	return bool(wf["water"]) and int(wf["regime"]) != WR.REGIME_PUDDLE and float(wf["depth"]) > _deep_threshold


func clear_for_prop(world_pos: Vector2, radius: float) -> bool:
	var reach: float = radius + _prop_margin
	if not bounds.grow(reach).has_point(world_pos):
		return true
	var snap: Array = _snapshot_bytes()
	var geo: PackedByteArray = snap[0] as PackedByteArray
	if geo.is_empty():
		return true
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var probe: Vector2 = world_pos + Vector2(float(dx), float(dy)) * (reach * 0.7)
			if not bounds.has_point(probe):
				continue
			var g: Vector4 = _sample_geo_from_bytes(probe, geo)
			var reg: int = int(g.z)
			if reg != WR.REGIME_LAND and g.x <= reach * 0.8:
				return false
	return true


func reflects_at(world_pos: Vector2) -> bool:
	var wf: Dictionary = water_field_at(world_pos)
	return bool(wf["water"]) or bool(wf["wet_sand"])


func has_dynamic_water(world_pos: Vector2) -> bool:
	if not bounds.has_point(world_pos):
		return false
	var snap: Array = _snapshot_bytes()
	var geo: PackedByteArray = snap[0] as PackedByteArray
	if geo.is_empty():
		return false
	var g: Vector4 = _sample_geo_from_bytes(world_pos, geo)
	var reg: int = int(g.z)
	if reg == WR.REGIME_SURF and g.x >= -28.0 and g.x <= 44.0:
		return true
	if reg == WR.REGIME_PUDDLE and g.x >= -16.0 and g.x <= 16.0:
		return true
	if reg == WR.REGIME_OCEAN:
		return true
	return false


func geo_texture() -> Texture2D:
	return _geo_tex


func flow_texture() -> Texture2D:
	return _flow_tex


func grass_habitat_at(world_pos: Vector2) -> Dictionary:
	if not bounds.has_point(world_pos):
		return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}
	var snap: Array = _snapshot_bytes()
	var geo: PackedByteArray = snap[0] as PackedByteArray
	if geo.is_empty():
		return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}
	var g: Vector4 = _sample_geo_from_bytes(world_pos, geo)
	var sdf_px: float = g.x
	var reg: int = int(g.z)
	var bed_id: int = int(g.w)

	if reg == WR.REGIME_OCEAN or reg == WR.REGIME_LAKE:
		if sdf_px <= 2.5:
			return {"density": 0.0, "height_scale": 0.6, "style": "none"}
	if reg == WR.REGIME_PUDDLE:
		if sdf_px <= 3.0 or bed_id == WR.BED_ROCK or bed_id == WR.BED_SAND:
			return {"density": 0.0, "height_scale": 0.6, "style": "none"}
		return {"density": 0.35, "height_scale": 0.9, "style": "moss_edge"}
	if reg == WR.REGIME_BROOK:
		if sdf_px <= 2.0:
			return {"density": 0.0, "height_scale": 0.6, "style": "none"}
		if sdf_px <= 14.0:
			var bank_t: float = clampf((sdf_px - 2.0) / 12.0, 0.0, 1.0)
			return {"density": lerpf(0.32, 0.84, bank_t), "height_scale": 1.12, "style": "bank_reed"}
		return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}
	if reg == WR.REGIME_SURF:
		# Keep open surf & beach completely free of grass!
		return {"density": 0.0, "height_scale": 0.6, "style": "none"}
	if reg == WR.REGIME_LAND:
		if bed_id == WR.BED_ROCK:
			return {"density": 0.0, "height_scale": 0.6, "style": "none"}
		if bed_id == WR.BED_SAND:
			# Keep open beach sand clean; only cluster authentic Strandhafer on upper eastern dune hummocks!
			if sdf_px < 96.0:
				return {"density": 0.0, "height_scale": 0.6, "style": "none"}
			var hummock: float = 0.5 * sin(world_pos.y * 0.06 + 0.8) + 0.5 * cos(world_pos.y * 0.14 - world_pos.x * 0.05)
			if hummock < -0.10:
				return {"density": 0.0, "height_scale": 0.6, "style": "none"}
			var dune_t: float = clampf((sdf_px - 96.0) / 52.0, 0.0, 1.0)
			return {"density": lerpf(0.20, 0.50, dune_t), "height_scale": 1.06, "style": "dune_oat"}
		# Gentle coastal-sage grass transition just east of the dune ridge into Square -1!
		if world_pos.x < -540.0:
			return {"density": 0.82, "height_scale": 1.0, "style": "coastal_edge"}
	return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}


# ==============================================================================
# Toroidal 128x128 @ 4x4 px Damped 2D Wave Ringbuffer (30 Hz + Active-Sleep)
# ==============================================================================

func _init_wave_ringbuffer() -> void:
	var n: int = WAVE_RES * WAVE_RES
	_h_curr.resize(n)
	_h_curr.fill(0.0)
	_h_next.resize(n)
	_h_next.fill(0.0)
	_v.resize(n)
	_v.fill(0.0)
	_foam.resize(n)
	_foam.fill(0.0)

	_tile_active.resize(TILE_COUNT)
	_tile_active.fill(0)
	_tile_next.resize(TILE_COUNT)
	_tile_next.fill(0)
	_active_tiles.clear()
	_next_tiles.clear()
	_kept_tiles.clear()
	_cleared_tiles.clear()

	_wave_bytes.resize(n * 4)
	_fill_neutral_wave_bytes()
	_wave_img = Image.create_from_data(WAVE_RES, WAVE_RES, false, Image.FORMAT_RGBA8, _wave_bytes)
	_wave_tex = ImageTexture.create_from_image(_wave_img)

	_wave_cell_origin = Vector2i(-WAVE_RES / 2, -WAVE_RES / 2)
	_wave_origin = Vector2(_wave_cell_origin) * WAVE_CELL_PX
	_wave_active = false
	_wave_dirty = false
	_wave_accum = 0.0
	_wave_step_idx = 0
	_act_min = Vector2i(0, 0)
	_act_max = Vector2i(-1, -1)


func _fill_neutral_wave_bytes() -> void:
	var n: int = WAVE_RES * WAVE_RES
	for i: int in n:
		_wave_bytes.encode_u32(i << 2, NEUTRAL_WAVE_U32)


func _clear_wave_cell(wx: int, wy: int) -> void:
	var idx: int = ((wy & 127) << 7) | (wx & 127)
	_h_curr[idx] = 0.0
	_h_next[idx] = 0.0
	_v[idx] = 0.0
	_foam[idx] = 0.0
	_wave_bytes.encode_u32(idx << 2, NEUTRAL_WAVE_U32)


func recenter_wave_field(target_world_pos: Vector2) -> bool:
	if _wave_img == null:
		return false
	var desired_origin: Vector2i = Vector2i(
		floori(target_world_pos.x / WAVE_CELL_PX) - WAVE_RES / 2,
		floori(target_world_pos.y / WAVE_CELL_PX) - WAVE_RES / 2
	)
	var delta_c: Vector2i = desired_origin - _wave_cell_origin
	if absi(delta_c.x) < RECENTER_STEP_CELLS and absi(delta_c.y) < RECENTER_STEP_CELLS:
		return false

	var old_origin: Vector2i = _wave_cell_origin
	_wave_cell_origin = desired_origin
	_wave_origin = Vector2(_wave_cell_origin) * WAVE_CELL_PX

	if _wave_active:
		if absi(delta_c.x) >= WAVE_RES or absi(delta_c.y) >= WAVE_RES:
			_h_curr.fill(0.0)
			_h_next.fill(0.0)
			_v.fill(0.0)
			_foam.fill(0.0)
			_fill_neutral_wave_bytes()
			_tile_active.fill(0)
			_active_tiles.clear()
			_act_min = Vector2i(0, 0)
			_act_max = Vector2i(-1, -1)
			_wave_active = false
		else:
			if delta_c.x > 0:
				for wx: int in range(old_origin.x + WAVE_RES, _wave_cell_origin.x + WAVE_RES):
					for ty: int in WAVE_RES:
						_clear_wave_cell(wx, _wave_cell_origin.y + ty)
			elif delta_c.x < 0:
				for wx: int in range(_wave_cell_origin.x, old_origin.x):
					for ty: int in WAVE_RES:
						_clear_wave_cell(wx, _wave_cell_origin.y + ty)
			if delta_c.y > 0:
				for wy: int in range(old_origin.y + WAVE_RES, _wave_cell_origin.y + WAVE_RES):
					for tx: int in WAVE_RES:
						_clear_wave_cell(_wave_cell_origin.x + tx, wy)
			elif delta_c.y < 0:
				for wy: int in range(_wave_cell_origin.y, old_origin.y):
					for tx: int in WAVE_RES:
						_clear_wave_cell(_wave_cell_origin.x + tx, wy)
			_act_min = Vector2i(maxi(_act_min.x, _wave_cell_origin.x), maxi(_act_min.y, _wave_cell_origin.y))
			_act_max = Vector2i(mini(_act_max.x, _wave_cell_origin.x + WAVE_RES - 1), mini(_act_max.y, _wave_cell_origin.y + WAVE_RES - 1))
		_wave_dirty = true

	if _surface_mat != null:
		_surface_mat.set_shader_parameter("wave_origin", _wave_origin)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("wave_origin", _wave_origin)
	return true


func _stamp_wave_impulse(world_pos: Vector2, strength: float, radius_px: float, dir: Vector2, add_foam: bool) -> void:
	if _wave_img == null:
		return
	var r_px: float = clampf(radius_px, 4.0, 40.0)
	var min_c: Vector2i = Vector2i(((world_pos - Vector2.ONE * r_px) / WAVE_CELL_PX).floor())
	var max_c: Vector2i = Vector2i(((world_pos + Vector2.ONE * r_px) / WAVE_CELL_PX).floor())
	var win_min: Vector2i = _wave_cell_origin
	var win_max: Vector2i = _wave_cell_origin + Vector2i(WAVE_RES - 1, WAVE_RES - 1)
	min_c = Vector2i(maxi(min_c.x, win_min.x), maxi(min_c.y, win_min.y))
	max_c = Vector2i(mini(max_c.x, win_max.x), mini(max_c.y, win_max.y))
	if min_c.x > max_c.x or min_c.y > max_c.y:
		return

	var r_sq: float = r_px * r_px
	var inv_r: float = 1.0 / r_px
	var dir_n: Vector2 = dir.normalized() if dir.length_squared() > 0.01 else Vector2.ZERO
	var has_dir: bool = dir_n != Vector2.ZERO
	var v_scale: float = strength * 0.45
	var do_foam: bool = add_foam and strength > 0.35
	var f_scale: float = strength * 0.38

	for wy: int in range(min_c.y, max_c.y + 1):
		var row: int = (wy & 127) << 7
		var dy_c: float = (float(wy) + 0.5) * WAVE_CELL_PX - world_pos.y
		for wx: int in range(min_c.x, max_c.x + 1):
			var dx_c: float = (float(wx) + 0.5) * WAVE_CELL_PX - world_pos.x
			var d_sq: float = dx_c * dx_c + dy_c * dy_c
			if d_sq > r_sq:
				continue
			var d: float = sqrt(d_sq)
			var falloff: float = 1.0 - d * inv_r
			var idx: int = row | (wx & 127)
			var bias: float = 1.0
			if has_dir and d > 0.5:
				bias += clampf((dx_c * dir_n.x + dy_c * dir_n.y) / d, -0.4, 0.8) * 0.45
			_v[idx] = clampf(_v[idx] - v_scale * falloff * bias, -1.0, 1.0)
			if do_foam:
				_foam[idx] = clampf(_foam[idx] + f_scale * falloff, 0.0, 1.0)

	var hmin_x: int = maxi(min_c.x - 1, win_min.x)
	var hmax_x: int = mini(max_c.x + 1, win_max.x)
	var hmin_y: int = maxi(min_c.y - 1, win_min.y)
	var hmax_y: int = mini(max_c.y + 1, win_max.y)
	for wy_b: int in range(hmin_y >> 2, (hmax_y >> 2) + 1):
		var trow: int = (wy_b & 31) << 5
		for wx_b: int in range(hmin_x >> 2, (hmax_x >> 2) + 1):
			var tidx: int = trow | (wx_b & 31)
			if _tile_active[tidx] == 0:
				_tile_active[tidx] = 1
				_active_tiles.append(tidx)

	if not _wave_active or _act_min.x > _act_max.x or _act_min.y > _act_max.y:
		_act_min = min_c
		_act_max = max_c
	else:
		_act_min = Vector2i(mini(_act_min.x, min_c.x), mini(_act_min.y, min_c.y))
		_act_max = Vector2i(maxi(_act_max.x, max_c.x), maxi(_act_max.y, max_c.y))
	_wave_active = true
	_wave_dirty = true


func add_water_impulse(world_pos: Vector2, strength: float = 1.0, radius_px: float = 8.0, dir: Vector2 = Vector2.ZERO) -> void:
	if _wave_img == null:
		return
	var wf: Dictionary = water_field_at(world_pos)
	if not bool(wf["in_bounds"]):
		return
	if int(wf["regime"]) == WR.REGIME_PUDDLE and not bool(wf["water"]):
		return
	if not bool(wf["water"]) and float(wf["sdf_px"]) > 18.0:
		return
	_stamp_wave_impulse(world_pos, clampf(strength, 0.05, 2.0), radius_px, dir, true)

	if strength >= 0.45 and _air_mote_layer != null:
		var cols: Dictionary = water_color_at(world_pos)
		var drop_c: Color = cols.get("foam", Color("d8f2f0")) as Color
		var count: int = clampi(roundi(strength * 3.0), 2, 5)
		_spawn_splash_motes(world_pos, count, drop_c, dir)


func set_swimmer(key: int, slot: Vector4) -> void:
	if slot.w <= 0.0:
		_swimmers.erase(key)
		return
	_swimmers[key] = slot
	if _wave_img != null:
		_wave_active = true


func _step_wave_ringbuffer(delta: float) -> void:
	if _wave_img == null or _wave_tex == null:
		return
	if not _wave_active and not _wave_dirty and _swimmers.is_empty():
		return

	_wave_accum += delta
	if _wave_accum < WAVE_STEP_DT:
		if _wave_dirty:
			_wave_img.set_data(WAVE_RES, WAVE_RES, false, Image.FORMAT_RGBA8, _wave_bytes)
			_wave_tex.update(_wave_img)
			_wave_dirty = false
		return

	while _wave_accum >= WAVE_STEP_DT:
		_wave_accum -= WAVE_STEP_DT
		_wave_step_idx += 1
		if not _swimmers.is_empty():
			var sw_i: int = 0
			for slot_v: Variant in _swimmers.values():
				if ((_wave_step_idx + sw_i) & 1) == 1:
					var slot: Vector4 = slot_v as Vector4
					var sw_r: float = clampf(slot.z, 5.0, 7.5)
					_stamp_wave_impulse(Vector2(slot.x, slot.y), slot.w * 0.40, sw_r, Vector2.ZERO, true)
				sw_i += 1

		if not _wave_active:
			continue

		var ox: int = _wave_cell_origin.x & 127
		var oy: int = _wave_cell_origin.y & 127
		_tile_next.fill(0)
		_next_tiles.clear()
		_kept_tiles.clear()
		_cleared_tiles.clear()

		# Single-pass step + normal/height/foam RGBA8 packing + 1-cell halo propagation
		for tidx: int in _active_tiles:
			var bx: int = tidx & 31
			var by: int = tidx >> 5
			var tx0: int = bx << 2
			var ty0: int = by << 2
			var tx_l0: int = (tx0 - 1) & 127
			var tx_r3: int = (tx0 + 4) & 127
			var tile_max_e: float = 0.0
			var e_l: float = 0.0
			var e_r: float = 0.0
			var e_u: float = 0.0
			var e_d: float = 0.0

			for ly: int in TILE_SIZE:
				var ty: int = ty0 + ly
				var row: int = ty << 7
				var row_u: int = ((ty - 1) & 127) << 7
				var row_d: int = ((ty + 1) & 127) << 7
				var i0: int = row + tx0
				var i1: int = i0 + 1
				var i2: int = i0 + 2
				var i3: int = i0 + 3
				var hl: float = _h_curr[row + tx_l0]
				var h0: float = _h_curr[i0]
				var h1: float = _h_curr[i1]
				var h2: float = _h_curr[i2]
				var h3: float = _h_curr[i3]
				var hr: float = _h_curr[row + tx_r3]

				var hu0: float = _h_curr[row_u + tx0]
				var hd0: float = _h_curr[row_d + tx0]
				var hu1: float = _h_curr[row_u + tx0 + 1]
				var hd1: float = _h_curr[row_d + tx0 + 1]
				var hu2: float = _h_curr[row_u + tx0 + 2]
				var hd2: float = _h_curr[row_d + tx0 + 2]
				var hu3: float = _h_curr[row_u + tx0 + 3]
				var hd3: float = _h_curr[row_d + tx0 + 3]

				var v0: float = (_v[i0] + 0.40 * ((hl + h1 + hu0 + hd0) * 0.25 - h0)) * 0.80
				var hn0: float = (h0 + v0) * 0.88
				var fn0: float = _foam[i0] * 0.86
				_v[i0] = v0
				_h_next[i0] = hn0
				_foam[i0] = fn0

				var v1: float = (_v[i1] + 0.40 * ((h0 + h2 + hu1 + hd1) * 0.25 - h1)) * 0.80
				var hn1: float = (h1 + v1) * 0.88
				var fn1: float = _foam[i1] * 0.86
				_v[i1] = v1
				_h_next[i1] = hn1
				_foam[i1] = fn1

				var v2: float = (_v[i2] + 0.40 * ((h1 + h3 + hu2 + hd2) * 0.25 - h2)) * 0.80
				var hn2: float = (h2 + v2) * 0.88
				var fn2: float = _foam[i2] * 0.86
				_v[i2] = v2
				_h_next[i2] = hn2
				_foam[i2] = fn2

				var v3: float = (_v[i3] + 0.40 * ((h2 + hr + hu3 + hd3) * 0.25 - h3)) * 0.80
				var hn3: float = (h3 + v3) * 0.88
				var fn3: float = _foam[i3] * 0.86
				_v[i3] = v3
				_h_next[i3] = hn3
				_foam[i3] = fn3

				var nx0: int = clampi(int((hl - h1) * 304.8 + 128.5), 1, 255)
				var ny0: int = clampi(int((hu0 - hd0) * 304.8 + 128.5), 1, 255)
				_wave_bytes.encode_u32(i0 << 2, nx0 | (ny0 << 8) | (clampi(int(hn0 * 127.0 + 128.5), 1, 255) << 16) | (clampi(int(fn0 * 255.0 + 0.5), 0, 255) << 24))

				var nx1: int = clampi(int((h0 - h2) * 304.8 + 128.5), 1, 255)
				var ny1: int = clampi(int((hu1 - hd1) * 304.8 + 128.5), 1, 255)
				_wave_bytes.encode_u32(i1 << 2, nx1 | (ny1 << 8) | (clampi(int(hn1 * 127.0 + 128.5), 1, 255) << 16) | (clampi(int(fn1 * 255.0 + 0.5), 0, 255) << 24))

				var nx2: int = clampi(int((h1 - h3) * 304.8 + 128.5), 1, 255)
				var ny2: int = clampi(int((hu2 - hd2) * 304.8 + 128.5), 1, 255)
				_wave_bytes.encode_u32(i2 << 2, nx2 | (ny2 << 8) | (clampi(int(hn2 * 127.0 + 128.5), 1, 255) << 16) | (clampi(int(fn2 * 255.0 + 0.5), 0, 255) << 24))

				var nx3: int = clampi(int((h2 - hr) * 304.8 + 128.5), 1, 255)
				var ny3: int = clampi(int((hu3 - hd3) * 304.8 + 128.5), 1, 255)
				_wave_bytes.encode_u32(i3 << 2, nx3 | (ny3 << 8) | (clampi(int(hn3 * 127.0 + 128.5), 1, 255) << 16) | (clampi(int(fn3 * 255.0 + 0.5), 0, 255) << 24))

				var el_v: float = maxf(maxf(absf(hn0), absf(v0)), fn0)
				if el_v > e_l:
					e_l = el_v
				var er_v: float = maxf(maxf(absf(hn3), absf(v3)), fn3)
				if er_v > e_r:
					e_r = er_v
				var em1: float = maxf(maxf(absf(hn1), absf(v1)), fn1)
				var em2: float = maxf(maxf(absf(hn2), absf(v2)), fn2)
				var row_e: float = maxf(maxf(el_v, er_v), maxf(em1, em2))
				if row_e > tile_max_e:
					tile_max_e = row_e
				if ly == 0:
					e_u = row_e
				elif ly == 3:
					e_d = row_e

			if tile_max_e < 0.002:
				_cleared_tiles.append(tidx)
			else:
				_kept_tiles.append(tidx)
				if _tile_next[tidx] == 0:
					_tile_next[tidx] = 1
					_next_tiles.append(tidx)
				if e_l >= 0.002 and ((tx0 - ox) & 127) > 0:
					var nt: int = (by << 5) | ((bx - 1) & 31)
					if _tile_next[nt] == 0:
						_tile_next[nt] = 1
						_next_tiles.append(nt)
				if e_r >= 0.002 and ((tx0 + 3 - ox) & 127) < 127:
					var nt: int = (by << 5) | ((bx + 1) & 31)
					if _tile_next[nt] == 0:
						_tile_next[nt] = 1
						_next_tiles.append(nt)
				if e_u >= 0.002 and ((ty0 - oy) & 127) > 0:
					var nt: int = (((by - 1) & 31) << 5) | bx
					if _tile_next[nt] == 0:
						_tile_next[nt] = 1
						_next_tiles.append(nt)
				if e_d >= 0.002 and ((ty0 + 3 - oy) & 127) < 127:
					var nt: int = (((by + 1) & 31) << 5) | bx
					if _tile_next[nt] == 0:
						_tile_next[nt] = 1
						_next_tiles.append(nt)

		var tmp_h: PackedFloat32Array = _h_curr
		_h_curr = _h_next
		_h_next = tmp_h

		# Zero dead tiles back to neutral so inactive tiles stay clean
		for tidx: int in _cleared_tiles:
			var tx0: int = (tidx & 31) << 2
			var ty0: int = (tidx >> 5) << 2
			for ly: int in TILE_SIZE:
				var i0: int = ((ty0 + ly) << 7) | tx0
				_h_curr[i0] = 0.0
				_h_curr[i0 + 1] = 0.0
				_h_curr[i0 + 2] = 0.0
				_h_curr[i0 + 3] = 0.0
				_h_next[i0] = 0.0
				_h_next[i0 + 1] = 0.0
				_h_next[i0 + 2] = 0.0
				_h_next[i0 + 3] = 0.0
				_v[i0] = 0.0
				_v[i0 + 1] = 0.0
				_v[i0 + 2] = 0.0
				_v[i0 + 3] = 0.0
				_foam[i0] = 0.0
				_foam[i0 + 1] = 0.0
				_foam[i0 + 2] = 0.0
				_foam[i0 + 3] = 0.0
				_wave_bytes.encode_u32(i0 << 2, NEUTRAL_WAVE_U32)
				_wave_bytes.encode_u32((i0 + 1) << 2, NEUTRAL_WAVE_U32)
				_wave_bytes.encode_u32((i0 + 2) << 2, NEUTRAL_WAVE_U32)
				_wave_bytes.encode_u32((i0 + 3) << 2, NEUTRAL_WAVE_U32)

		if _kept_tiles.is_empty():
			_tile_active.fill(0)
			_active_tiles.clear()
			if _swimmers.is_empty():
				_wave_active = false
			_act_min = Vector2i(0, 0)
			_act_max = Vector2i(-1, -1)
		else:
			var tmp_t: PackedByteArray = _tile_active
			_tile_active = _tile_next
			_tile_next = tmp_t
			var tmp_l: Array[int] = _active_tiles
			_active_tiles = _next_tiles
			_next_tiles = tmp_l

		_wave_dirty = true

	if _wave_dirty:
		_wave_img.set_data(WAVE_RES, WAVE_RES, false, Image.FORMAT_RGBA8, _wave_bytes)
		_wave_tex.update(_wave_img)
		_wave_dirty = false


# ==============================================================================
# V12 Surface Petals & Storm Spray / Splash Motes
# ==============================================================================

func _spawn_splash_motes(at: Vector2, count: int, drop_color: Color, dir: Vector2) -> void:
	if _air_mote_layer == null:
		return
	var base_dir: Vector2 = dir.normalized() if dir.length_squared() > 0.01 else Vector2.ZERO
	for _i: int in count:
		if _air_mote_layer.motes.size() >= MAX_AIR_MOTES:
			_air_mote_layer.motes.pop_front()
		var m: AirMote = AirMote.new()
		var ang: float = _rng.randf() * TAU
		var spd: float = _rng.randf_range(12.0, 32.0)
		m.pos = at + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-2.0, 2.0))
		m.vel = Vector2.from_angle(ang) * spd + base_dir * 12.0
		m.z_h = _rng.randf_range(1.0, 3.0)
		m.z_vel = _rng.randf_range(24.0, 44.0)
		m.life = _rng.randf_range(0.32, 0.58)
		m.color = drop_color
		m.size_px = Vector2.ONE
		_air_mote_layer.motes.append(m)


func _step_motes(delta: float) -> void:
	if _surface_mote_layer != null:
		var had_petals: bool = not _surface_mote_layer.petals.is_empty()
		if not _petal_spawns.is_empty():
			_petal_timer -= delta
			if _petal_timer <= 0.0 and _surface_mote_layer.petals.size() < MAX_PETALS:
				_petal_timer = _rng.randf_range(0.65, 1.45)
				var sp: SurfacePetal = SurfacePetal.new()
				var origin: Vector2 = _petal_spawns[_rng.randi_range(0, _petal_spawns.size() - 1)]
				sp.pos = origin + Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-8.0, 8.0))
				sp.phase = _rng.randf() * TAU
				sp.life = _rng.randf_range(10.0, 16.0)
				sp.color = PETAL_COLORS[_rng.randi_range(0, PETAL_COLORS.size() - 1)]
				sp.size_px = Vector2(2.0, 1.0) if _rng.randf() < 0.45 else Vector2.ONE
				_surface_mote_layer.petals.append(sp)

		for i: int in range(_surface_mote_layer.petals.size() - 1, -1, -1):
			var p: SurfacePetal = _surface_mote_layer.petals[i]
			p.age += delta
			var wf: Dictionary = water_field_at(p.pos)
			if p.age >= p.life or not bool(wf["water"]) or int(wf["regime"]) != WR.REGIME_BROOK:
				_surface_mote_layer.petals.remove_at(i)
				continue
			var fl: Vector2 = water_flow_at(p.pos)
			if fl.length_squared() < 1.0:
				fl = Vector2(0.0, 18.0)
			var across: Vector2 = Vector2(-fl.y, fl.x).normalized()
			p.pos += (fl * 0.72 + across * sin(_clock * 1.9 + p.phase) * 4.5) * delta

		if had_petals or not _surface_mote_layer.petals.is_empty():
			_surface_mote_layer.queue_redraw()

	if _air_mote_layer != null:
		var had_air: bool = not _air_mote_layer.motes.is_empty()
		if _snap_storm > 0.35:
			_spray_timer -= delta
			if _spray_timer <= 0.0 and _air_mote_layer.motes.size() < MAX_AIR_MOTES:
				_spray_timer = _rng.randf_range(0.08, 0.22)
				var sx: float = _rng.randf_range(bounds.position.x + 12.0, minf(bounds.end.x - 12.0, -720.0))
				var sy: float = _rng.randf_range(bounds.position.y + 8.0, bounds.end.y - 8.0)
				var swf: Dictionary = water_field_at(Vector2(sx, sy))
				if bool(swf["water"]) and (int(swf["regime"]) == WR.REGIME_SURF or int(swf["regime"]) == WR.REGIME_OCEAN):
					var sm: AirMote = AirMote.new()
					sm.pos = Vector2(sx, sy)
					sm.vel = _snap_wind_dir.normalized() * _rng.randf_range(28.0, 56.0) + Vector2(0.0, _rng.randf_range(-8.0, 8.0))
					sm.z_h = _rng.randf_range(2.0, 5.0)
					sm.z_vel = _rng.randf_range(12.0, 26.0)
					sm.life = _rng.randf_range(0.45, 0.90)
					sm.color = Color("dcf8f6")
					sm.size_px = Vector2(2.0, 1.0) if _rng.randf() < 0.3 else Vector2.ONE
					_air_mote_layer.motes.append(sm)

		for i: int in range(_air_mote_layer.motes.size() - 1, -1, -1):
			var m: AirMote = _air_mote_layer.motes[i]
			m.age += delta
			if m.age >= m.life:
				_air_mote_layer.motes.remove_at(i)
				continue
			m.pos += m.vel * delta
			m.z_vel -= 68.0 * delta
			m.z_h = maxf(0.0, m.z_h + m.z_vel * delta)
			if m.z_h <= 0.0:
				m.z_vel = 0.0
				m.vel *= 0.6

		if had_air or not _air_mote_layer.motes.is_empty():
			_air_mote_layer.queue_redraw()
