class_name WeatherManager
extends Node
## The weather of the world (docs/wetter_konzept.md). `WeatherRules` says what the sky does at the world time (a pure function, the same on every peer);
## this node smooths it for the eye, owns the cloud field (`WeatherField`), feeds the shader globals (clouds, rain, wetness), the wind (`WorldWind`) and the
## lightning/thunder timeline, and answers what everyone else wants to know (`sunlight`, `ambient_dim`, `rain_at`, `exposure_at`, `alarm_factor`).
## Only the dev/story override travels the network (host -> everyone, and to joiners). `DayNight` creates it; `follow` runs every frame from there.

signal state_changed(id: String)
signal lightning_struck(info: Dictionary) ## {x, y, far, seed, bolt, double, color: Color} a flash is starting now
signal arcane_lightning_struck(world_pos: Vector2, info: Dictionary) ## dry prism-quartz lightning in Sonnenquarz-Öde
signal thunder_rolled(far: float) ## the sound reaches the listener now

static var current: WeatherManager

var field: WeatherField = WeatherField.new()
var cloud: float = 0.2
var rain: float = 0.0
var wind: float = 0.25
var storm: float = 0.0
var fog: float = 0.0
var dir: float = 0.26
var ground_wet: float = 0.0
var puddle: float = 0.0
var drift: Vector2 = Vector2.ZERO
var state_id: String = "fair"
var override_id: String = ""
var override_left: float = 0.0
var indoors: bool = false
var flash: float = 0.0 ## the lightning's light right now, 0..1
var flash_info: Dictionary = {}
var flash_age: float = 99.0
var local_rain: float = 0.0 ## rain on the camera's ground right now (a rain cell passes over)
var desert_resonance: float = 0.0 ## 0..1 Singender Resonanzwind (translates rain regimes in quartz_desert)
var desert_arcane_storm: float = 0.0 ## 0..1 Arkanes Quarzgewitter (translates storm regimes in quartz_desert, dry lightning)
var focus: Vector2 = Vector2.ZERO

var _target: WeatherRules.State = WeatherRules.State.new()
var _seed_built: int = -99999
var _texture_set: bool = false
var _epoch: float = 0.0
var _opened: bool = true
var _slice_seen: int = -1
var _pending_flash: Array[Dictionary] = []
var _pending_thunder: Array[Dictionary] = []
var _extra_wet: float = 0.0
var _g: Dictionary = {}
var _cfg: Dictionary = {}


func _ready() -> void:
	name = "WeatherManager"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("weather")
	current = self
	_cfg = WeatherRules.cfg()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_force.rpc_id(id, override_id, override_left))


func _exit_tree() -> void:
	if current == self:
		current = null
	for key: String in ["g_cloud_thresh", "g_rain", "g_storm", "g_wet", "g_puddle", "g_cloud_bonus"]:
		RenderingServer.global_shader_parameter_set(key, 2.0 if key == "g_cloud_thresh" else 0.0)
	RenderingServer.global_shader_parameter_set("g_cloud_shadow", 1.0)


## Dev menu / story: hold a named state for `seconds` (0 = until `release`). The host decides and tells everyone.
func force(id: String, seconds: float = 0.0) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	if id != "" and WeatherRules.state_def(id).is_empty():
		return
	if multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		_rpc_force.rpc(id, seconds)
	else:
		_rpc_force(id, seconds)


func release() -> void:
	force("", 0.0)


@rpc("authority", "call_local", "reliable")
func _rpc_force(id: String, seconds: float) -> void:
	override_id = id
	override_left = seconds if seconds > 0.0 else (1.0e9 if id != "" else 0.0)
	_pending_flash.clear()
	_pending_thunder.clear()


## Called every frame by `DayNight`.
func follow(is_indoors: bool, delta: float) -> void:
	indoors = is_indoors
	var world_seed: int = Moisture.world_seed
	if world_seed != _seed_built:
		_seed_built = world_seed
		_texture_set = false
		field = WeatherField.new()
		field.build(world_seed, _on_field_ready)
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		focus = camera.get_screen_center_position()
	if override_left > 0.0:
		override_left -= delta
		if override_left <= 0.0:
			override_id = ""
	_epoch = WeatherRules.epoch(TimeManager.day, TimeManager.time_of_day)
	var parent: Node = get_parent().get_parent() if get_parent() != null else null
	var opening: Variant = parent.get("opening_over") if parent != null else null
	var opened: bool = opening == null or bool(opening)
	_opened = opened
	if override_id != "":
		_target = WeatherRules.named(override_id)
		_target.dir = WeatherRules.state_at(world_seed, _epoch).dir
	elif not opened or not WeatherRules.enabled():
		_target = WeatherRules.named("clear") ## the night of the opening: a clear sky
	else:
		_target = WeatherRules.state_at(world_seed, _epoch)
	var raw_rain: float = _target.rain
	var raw_storm: float = _target.storm
	_apply_region(_target)
	# the eye follows with a short lag: a time jump (F4, sleep) melts instead of snapping
	var k: float = 1.0 - exp(-delta / 1.4)
	cloud = lerpf(cloud, _target.cloud, k)
	rain = lerpf(rain, _target.rain, k)
	wind = lerpf(wind, _target.wind, k)
	storm = lerpf(storm, _target.storm, k)
	fog = lerpf(fog, _target.fog, k)
	var arid_here: float = BiomeBlend.arid_at(focus)
	var arid_dry: float = 1.0 - smoothstep(0.18, 0.42, arid_here)
	var desert_share: float = 0.0 if indoors else smoothstep(0.28, 0.65, arid_here)
	var want_res: float = clampf(raw_rain * 1.35 + raw_storm * 0.35, 0.0, 1.0) * desert_share
	var want_arc: float = clampf(raw_storm * 1.25, 0.0, 1.0) * desert_share
	desert_resonance = lerpf(desert_resonance, want_res, k) * (0.0 if desert_share <= 0.001 else 1.0)
	desert_arcane_storm = lerpf(desert_arcane_storm, want_arc, k) * (0.0 if desert_share <= 0.001 else 1.0)
	rain *= arid_dry
	storm *= arid_dry
	fog *= arid_dry
	if arid_dry <= 0.001 and desert_arcane_storm < 0.05:
		_pending_flash.clear()
		_pending_thunder.clear()
	dir = lerp_angle(dir, _target.dir, k)
	drift = WeatherRules.drift_at(world_seed, _epoch)
	_update_wetness(delta, world_seed)
	var id: String = WeatherRules.nearest_id(_current_state())
	if id != state_id:
		state_id = id
		state_changed.emit(id)
	_update_field()
	_push_globals()
	_push_wind()
	_run_lightning(delta, world_seed)


func _current_state() -> WeatherRules.State:
	var s: WeatherRules.State = WeatherRules.State.new()
	s.cloud = cloud
	s.rain = rain
	s.wind = wind
	s.storm = storm
	s.fog = fog
	s.dir = dir
	return s


## The Hexenwald keeps its own sky (overcast and misty); the Sonnenquarz-Öde is bone-dry and rainless.
func _apply_region(s: WeatherRules.State) -> void:
	var hex: float = BiomeBlend.amount_at(focus)
	if hex > 0.001:
		var r: Dictionary = (_cfg.get("regions", {}) as Dictionary).get("hexenwald", {}) as Dictionary
		s.cloud = lerpf(s.cloud, maxf(s.cloud, float(r.get("cloud_min", 0.58))), hex)
		s.fog = lerpf(s.fog, maxf(s.fog, float(r.get("fog_min", 0.22))), hex)
	var arid: float = BiomeBlend.arid_at(focus)
	if arid > 0.05:
		var dry: float = smoothstep(0.12, 0.42, arid)
		var d: Dictionary = (_cfg.get("regions", {}) as Dictionary).get("quartz_desert", {}) as Dictionary
		s.rain = lerpf(s.rain, minf(s.rain, float(d.get("rain_max", 0.0))), dry)
		s.storm = lerpf(s.storm, minf(s.storm, float(d.get("storm_max", 0.0))), dry)
		s.fog = lerpf(s.fog, minf(s.fog, float(d.get("fog_max", 0.0))), dry)
		s.cloud = lerpf(s.cloud, minf(s.cloud, float(d.get("cloud_max", 0.28))), smoothstep(0.22, 0.65, arid))


func _update_wetness(delta: float, world_seed: int) -> void:
	var arid_dry: float = 1.0 - smoothstep(0.18, 0.42, BiomeBlend.arid_at(focus))
	var from_rules: float = WeatherRules.ground_wet(world_seed, _epoch) if override_id == "" and WeatherRules.enabled() and _opened else 0.0
	# a held state (dev/story) soaks and dries the ground by itself
	_extra_wet = move_toward(_extra_wet, clampf(rain * 1.2 + fog * 0.3, 0.0, 1.0) if override_id != "" else 0.0, (0.05 if override_id != "" else 0.01) * delta)
	var target: float = maxf(from_rules, _extra_wet) * arid_dry
	ground_wet = lerpf(ground_wet, target, 1.0 - exp(-delta / 3.0)) * (0.0 if arid_dry <= 0.001 else 1.0)
	puddle = smoothstep(0.35, 0.95, ground_wet) * (0.4 + 0.6 * clampf(rain * 1.6, 0.0, 1.0)) + smoothstep(0.55, 1.0, ground_wet) * 0.3
	puddle = clampf(puddle * arid_dry, 0.0, 1.0)


func _update_field() -> void:
	if not field.ready_now:
		return
	var tile: float = WeatherField.TILE_A
	field.drift = Vector2(fposmod(drift.x, tile), fposmod(drift.y, tile))
	field.thresh = field.threshold(cloud)
	field.bonus = smoothstep(0.7, 1.0, cloud) * 0.7
	field.rain_regime = rain
	local_rain = field.rain_at(focus)


func _on_field_ready() -> void:
	if not _texture_set and field.texture != null:
		RenderingServer.global_shader_parameter_set("g_cloud_tex", field.texture)
		_texture_set = true


func _set_global(key: String, value: Variant) -> void:
	var old: Variant = _g.get(key)
	if old == null or (old is float and absf(float(old) - float(value)) > 0.0004) or (not old is float and old != value):
		_g[key] = value
		RenderingServer.global_shader_parameter_set(key, value)


func _push_globals() -> void:
	if not field.ready_now:
		return
	var light: Dictionary = _cfg.get("light", {}) as Dictionary
	_set_global("g_cloud_drift", field.drift)
	_set_global("g_cloud_thresh", field.thresh)
	_set_global("g_cloud_bonus", field.bonus)
	_set_global("g_cloud_shadow", float(light.get("shadow", 0.62)))
	_set_global("g_rain", rain)
	_set_global("g_storm", storm)
	_set_global("g_wet", ground_wet)
	_set_global("g_puddle", puddle)


func _push_wind() -> void:
	var w: WorldWind = WorldWind.current
	if w != null:
		w.set_weather(maxf(wind, desert_resonance * 0.58), dir, maxf(storm, desert_arcane_storm * 0.78), rain)


# ---------------------------------------------------------------- lightning and thunder

func _run_lightning(delta: float, world_seed: int) -> void:
	var l: Dictionary = _cfg.get("lightning", {}) as Dictionary
	var slice_len: float = float(l.get("slice", 1.0))
	var now: float = _epoch * WeatherRules.DAY_SEC
	var slice: int = floori(now / slice_len)
	var storm_drive: float = maxf(storm, desert_arcane_storm)
	if _slice_seen < 0 or slice < _slice_seen or slice - _slice_seen > 3:
		_slice_seen = slice ## a jump in time: no thunder from the past
	else:
		while _slice_seen < slice:
			_slice_seen += 1
			var event: Dictionary = WeatherRules.lightning(world_seed, _slice_seen, storm_drive)
			if not event.is_empty():
				event["time"] = float(_slice_seen) * slice_len + float(event.at)
				_pending_flash.append(event)
	var i: int = 0
	while i < _pending_flash.size():
		var event: Dictionary = _pending_flash[i]
		if now >= float(event.time):
			_pending_flash.remove_at(i)
			if now - float(event.time) < 1.2:
				_strike(event, now)
		else:
			i += 1
	i = 0
	while i < _pending_thunder.size():
		var t: Dictionary = _pending_thunder[i]
		if now >= float(t.time):
			_pending_thunder.remove_at(i)
			if now - float(t.time) < 4.0:
				thunder_rolled.emit(float(t.far))
		else:
			i += 1
	# the flash curve: a sharp rise, a flicker, a long fall
	flash_age += delta
	var peak: float = float(flash_info.get("peak", 0.0))
	var f: float = 0.0
	if peak > 0.0:
		var a: float = flash_age
		f = exp(-a * 8.0) + 0.45 * exp(-maxf(a - 0.07, 0.0) * 14.0) * (1.0 if a >= 0.07 else 0.0)
		if bool(flash_info.get("double", false)):
			f += 0.8 * exp(-maxf(a - 0.20, 0.0) * 7.0) * (1.0 if a >= 0.20 else 0.0)
		f *= peak * smoothstep(0.0, 0.012, a)
		if a > float(l.get("flash_seconds", 0.55)) + 0.3:
			f = 0.0
			flash_info = {}
	flash = clampf(f, 0.0, 1.0)


func _strike(event: Dictionary, now: float) -> void:
	var l: Dictionary = _cfg.get("lightning", {}) as Dictionary
	var far: float = float(event.far)
	var tint: Color = Color(0.80, 0.84, 1.0)
	var arid: float = BiomeBlend.arid_at(focus)
	var hex: float = BiomeBlend.amount_at(focus)
	if arid > 0.35:
		var arcane_cols: Array[Color] = [Color(0.86, 0.54, 1.0), Color(1.0, 0.78, 0.42), Color(0.46, 0.96, 0.90)]
		var pick_col: Color = arcane_cols[posmod(int(event.seed), arcane_cols.size())]
		tint = tint.lerp(pick_col, smoothstep(0.32, 0.68, arid))
	elif hex > 0.05:
		var rr: Array = ((_cfg.get("regions", {}) as Dictionary).get("hexenwald", {}) as Dictionary).get("flash", [0.62, 1.0, 0.36]) as Array
		tint = tint.lerp(Color(float(rr[0]), float(rr[1]), float(rr[2])), clampf(hex * 1.4, 0.0, 1.0))
	var level: Node = get_parent().get_parent() if get_parent() != null else null
	if level != null and level.has_method("coast_tiles") and arid < 0.35:
		var coast: float = float(level.call("coast_tiles", focus))
		if coast < 18.0: ## at the edge of the void the light turns magenta
			tint = tint.lerp(Color(0.95, 0.42, 1.0), 1.0 - clampf((coast + 2.0) / 20.0, 0.0, 1.0))
	var strike_x: float = float(event.x)
	var strike_y: float = float(event.y)
	var strike_world: Vector2 = focus + Vector2((strike_x - 0.5) * 420.0, (strike_y - 0.55) * 240.0)
	if arid > 0.35 and is_inside_tree():
		var best_d2: float = 220.0 * 220.0
		for node: Node in get_tree().get_nodes_in_group("resonance_obelisks"):
			var ob: Node2D = node as Node2D
			if ob != null and ob.global_position.distance_squared_to(strike_world) < best_d2:
				best_d2 = ob.global_position.distance_squared_to(strike_world)
				strike_world = ob.global_position
				strike_x = clampf(0.5 + (strike_world.x - focus.x) / 640.0, 0.08, 0.92)
				strike_y = clampf(0.5 + (strike_world.y - focus.y) / 360.0, 0.12, 0.88)
	flash_info = {"x": strike_x, "y": strike_y, "far": far, "seed": event.seed, "bolt": event.bolt, "double": event.double, "color": tint, "peak": lerpf(1.0, 0.42, far), "arcane": arid > 0.35}
	flash_age = 0.0
	lightning_struck.emit(flash_info)
	if arid > 0.35:
		arcane_lightning_struck.emit(strike_world, flash_info)
		if is_inside_tree():
			get_tree().call_group("desert_arcane_listeners", "on_arcane_lightning", strike_world, flash_info)
	var d: Array = l.get("delay", [0.25, 3.2]) as Array
	_pending_thunder.append({"time": now + lerpf(float(d[0]), float(d[1]), far), "far": far})


# ---------------------------------------------------------------- questions the world asks

## How much direct sun reaches the ground (multiplies sun, golden hour, glints): 1 clear .. about 0.1 under a storm.
func sunlight() -> float:
	return clampf(1.0 - 0.86 * smoothstep(0.15, 0.95, cloud) - 0.2 * rain - 0.1 * storm, 0.04, 1.0)


## A global dimming of the daylight tint (the sky's own light): 1 clear .. about 0.5 in a storm.
func ambient_dim() -> float:
	var l: Dictionary = _cfg.get("light", {}) as Dictionary
	return clampf(1.0 - float(l.get("cloud_dim", 0.24)) * pow(cloud, 1.5) - float(l.get("rain_dim", 0.14)) * rain - float(l.get("storm_dim", 0.18)) * storm, 0.4, 1.0)


## Rain on the ground at a world position, 0..1 (a rain cell passes over).
func rain_at(pos: Vector2) -> float:
	return field.rain_at(pos) if field.ready_now else 0.0


## How much of that rain actually reaches someone standing there: crowns shelter, rooms keep it out.
func exposure_at(pos: Vector2) -> float:
	if Interiors.slot_at(pos) >= 0:
		return 0.0
	return rain_at(pos) * (1.0 - 0.85 * canopy_at(pos))


## 0 open sky .. 1 dense crown above this world position (the daylight field's canopy map).
func canopy_at(pos: Vector2) -> float:
	var daylight: DaylightField = DaylightField.current
	if daylight == null or daylight.coverage == null or daylight.region.size.x <= 0.0:
		return 0.0
	var uv: Vector2 = (pos - daylight.region.position) / daylight.region.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return 0.0
	return daylight.coverage.get_pixel(int(uv.x * float(daylight.coverage.get_width())), int(uv.y * float(daylight.coverage.get_height()))).r


func display_name() -> String:
	if BiomeBlend.arid_at(focus) > 0.45:
		if desert_arcane_storm > 0.25:
			return "QUARZGEWITTER"
		if desert_resonance > 0.25:
			return "RESONANZWIND"
		if wind > 0.55:
			return "DÜNENWIND"
		if TimeManager.sun_amount() > 0.68:
			return "GLUTSONNE"
	return WeatherRules.display_name(state_id)


## Hearing and sight of shadow creatures shrink in rain and thunder (a chance for sneaking, never a punishment).
func alarm_factor() -> float:
	var g: Dictionary = _cfg.get("gameplay", {}) as Dictionary
	return clampf(1.0 - float(g.get("alarm_rain", 0.25)) * clampf(local_rain, 0.0, 1.0) - float(g.get("alarm_storm", 0.1)) * storm, float(g.get("alarm_min", 0.6)), 1.0)


## The same at a place: the rain on that very spot (a cell may miss her), crowns do not matter to the ear.
func alarm_factor_at(pos: Vector2) -> float:
	var g: Dictionary = _cfg.get("gameplay", {}) as Dictionary
	var here: float = rain_at(pos) if Interiors.slot_at(pos) < 0 else 0.0
	return clampf(1.0 - float(g.get("alarm_rain", 0.25)) * clampf(here, 0.0, 1.0) - float(g.get("alarm_storm", 0.1)) * storm, float(g.get("alarm_min", 0.6)), 1.0)


# static shortcuts: safe when there is no weather (arena tests, menu)
static func sun_scale() -> float:
	return current.sunlight() if current != null else 1.0


static func rain_now() -> float:
	return current.local_rain if current != null else 0.0


static func storm_now() -> float:
	return current.storm if current != null else 0.0


static func wet_now() -> float:
	return current.ground_wet if current != null else 0.0


## Rain or storm over the land: butterflies, bees and ladybugs rest (host decisions of the ambient wildlife).
static func sky_wet() -> bool:
	return current != null and (current.rain > 0.3 or current.storm > 0.25)


static func alarm_scale() -> float:
	return current.alarm_factor() if current != null else 1.0


static func resonance_now() -> float:
	return current.desert_resonance if current != null else 0.0


static func arcane_storm_now() -> float:
	return current.desert_arcane_storm if current != null else 0.0
