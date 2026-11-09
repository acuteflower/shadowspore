class_name FireArena
extends Node2D
## The fire and the light of Mornath's third phase on the arena floor (docs/boss_phase3_konzept.md), everything that burns or falls out of the sky and is not a feather
## (feathers are `FeatherField`'s):
##  - fire fields (`light`): a ring warns, then the floor catches fire for a few seconds (scorch, tongues of flame, sparks) and sets whoever stands in it alight;
##  - sky splinters (`column`): a hairline of light falls from above, a column of light strikes (the damage is a ring of the `FeatherField`), the floor keeps burning for a moment;
##  - the brand mark (`seal`): a seal turns over a player's head, counts down, sinks into the floor where she stood and burns there as a sigil until it bursts;
##  - the burning floor (`set_edge`, `set_floor`): the rim of the arena burns for good in the last fifth of his health, the whole floor in the last judgement; `cold_islands` are
##    the last turquoise light of the floor, where it does not burn and the burning is put out.
## Every peer draws it from the same moments (this node's own clock, real time); only the host sets alight (`burn` of `StatusEffects`). Unshaded, additive for all that glows.

const OUTLINE: Color = Color("0b0614")
const SCORCH: Color = Color("2a0a2e")
const SCORCH_RIM: Color = Color("6a0f42")
const EMBER: Color = Color("c0307f")
const MAGENTA: Color = Color("ff4fd8")
const PALE: Color = Color("ffb8ec")
const HOT: Color = Color("fff0fb")
const VIOLET: Color = Color("a23cff")
const TEAL: Color = Color("5fe3d4")
const TEAL_DARK: Color = Color("0c3d4a")
const HOST_TICK: float = 0.4
const REDRAW: float = 1.0 / 30.0
const EDGE_STRIDE: float = 12.0
const FLOOR_STRIDE: float = 22.0
const SEAL_HEIGHT: float = 78.0

var field: FeatherField
var boss: SkyCleaver
var host: bool = false
var floor_scale: float = 0.5 ## the strength of the burning floor (the damage scale of `burn`)
var floor_burn: float = 1.6 ## seconds the burning lasts after the last tick on the floor
var edge_width: float = 22.0
var _t: float = 0.0
var _fires: Array[Dictionary] = []
var _columns: Array[Dictionary] = []
var _seals: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _bits: Array[Dictionary] = []
var _cold: Array[Dictionary] = []
var _edge: float = 0.0
var _edge_to: float = 0.0
var _edge_secs: float = 1.0
var _floor: float = 0.0
var _floor_to: float = 0.0
var _floor_secs: float = 1.0
var _edge_spots: PackedVector2Array = PackedVector2Array()
var _spots_ready: bool = false
var _edge_flames: PixelFlames
var _floor_flames: PixelFlames
var _scorch: Node2D
var _glow: Node2D
var _sky: Node2D
var _acc: float = 0.0
var _host_acc: float = 0.0
var _drew: bool = false


func setup(p_boss: SkyCleaver, p_field: FeatherField, spec: Dictionary) -> void:
	boss = p_boss
	field = p_field
	host = multiplayer.is_server()
	top_level = true
	global_position = Vector2.ZERO
	floor_scale = float(spec.get("scale", 0.5))
	floor_burn = float(spec.get("burn_seconds", 1.6))
	edge_width = float(spec.get("edge_width", 22.0))
	_scorch = Node2D.new()
	_scorch.name = "Scorch"
	_scorch.z_index = -2
	_scorch.draw.connect(_draw_scorch)
	add_child(_scorch)
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Node2D.new()
	_glow.name = "Glow"
	_glow.z_index = -2
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_sky = Node2D.new()
	_sky.name = "Sky"
	_sky.z_index = 8
	_sky.material = add
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	_edge_flames = PixelFlames.new()
	_edge_flames.name = "EdgeFlames"
	_edge_flames.z_index = -2
	add_child(_edge_flames)
	_floor_flames = PixelFlames.new()
	_floor_flames.name = "FloorFlames"
	_floor_flames.z_index = -2
	add_child(_floor_flames)


static func _n(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 4.1414) * 43758.5453, 1.0)


# --- the fire fields -----------------------------------------------------------------------------------------------


## A patch of floor of `radius` that catches fire `delay` seconds from now and burns for `seconds` (a ring warns until then, if `warn`). It sets whoever stands in it
## alight with the strength `scale`.
func light(centre: Vector2, radius: float, delay: float, seconds: float, scale: float, warn: bool = true) -> void:
	var spots: Array[Dictionary] = []
	var seed_v: float = centre.x * 0.37 + centre.y * 0.91
	var ring_n: int = maxi(6, int(radius * TAU / 8.0))
	for i: int in ring_n:
		var ang: float = TAU * float(i) / float(ring_n) + _n(seed_v + float(i)) * 0.5
		var rad: float = radius * (0.8 + 0.16 * _n(seed_v * 1.7 + float(i)))
		spots.append({"o": Vector2.from_angle(ang) * rad, "salt": seed_v + float(i) * 3.3, "w": 8.0, "h": 11.0 + 7.0 * _n(seed_v + float(i) * 2.1)})
	var inner_n: int = maxi(2, int(radius / 6.5))
	for k: int in inner_n:
		var ang2: float = _n(seed_v * 2.3 + float(k)) * TAU
		var rad2: float = radius * 0.6 * sqrt(_n(seed_v * 0.7 + float(k) * 5.1))
		spots.append({"o": Vector2.from_angle(ang2) * rad2, "salt": seed_v + 50.0 + float(k) * 2.9, "w": 9.0, "h": 13.0 + 9.0 * _n(seed_v + float(k) * 4.4)})
	_fires.append({"c": centre, "r": radius, "warn_from": _t, "ignite": _t + delay, "end": _t + delay + seconds, "scale": scale, "spots": spots, "seed": seed_v, "warn": warn})
	if warn and delay > 0.05 and field != null:
		field.add_ring(centre, radius, 0.0, field.now(), field.now() + delay * field.time_scale, 0.0, 0.0) ## the red ring of the floor (no damage of its own)


## A sky splinter: a hairline of light falls to `centre` for `delay` seconds, then a column of light strikes (`radius` wide) and, with `ember` > 0, the floor burns on
## for that long. The damage is the caller's ring on the `FeatherField`.
func column(centre: Vector2, radius: float, delay: float, ember: float, scale: float) -> void:
	_columns.append({"c": centre, "r": radius, "t0": _t, "hit": _t + delay, "ember": ember, "scale": scale, "done": false, "seed": centre.x * 0.13 + centre.y * 0.29})


## Drops everything that was announced and burns less (the boss breaks off). The floor fire stays.
func clear_fields() -> void:
	for f: Dictionary in _fires:
		f["end"] = minf(float(f["end"]), _t + 0.5)
		f["ignite"] = minf(float(f["ignite"]), _t)
	_columns.clear()
	for s: Dictionary in _seals:
		if not bool(s["burst"]):
			s["burst"] = true
			s["gone"] = _t


## Everything off: the boss is dead or the fight was reset.
func clear_all() -> void:
	_fires.clear()
	_columns.clear()
	_seals.clear()
	_bursts.clear()
	_bits.clear()
	_cold.clear()
	set_edge(false, 0.0)
	set_floor(false, 0.0)


# --- the brand mark ------------------------------------------------------------------------------------------------


## A seal over `target`'s head that counts `total` seconds and bursts then with a ring of `radius`.
func seal(target: Node2D, total: float, radius: float) -> void:
	_seals.append({"node": target, "t0": _t, "total": total, "t_end": _t + total, "r": radius, "point": Vector2.INF, "lock_time": 0.0, "locked": false, "burst": false, "gone": -1.0})


## The seal sinks into the floor at `point` and stays there.
func lock_seal(point: Vector2) -> void:
	for s: Dictionary in _seals:
		if not bool(s["locked"]) and not bool(s["burst"]):
			s["locked"] = true
			s["point"] = point
			s["lock_time"] = _t
			return


func seal_active() -> bool:
	for s: Dictionary in _seals:
		if not bool(s["burst"]):
			return true
	return false


# --- the burning floor ---------------------------------------------------------------------------------------------


## The rim of the arena (`edge_width` px) burns for good (it takes `seconds` to catch).
func set_edge(on: bool, seconds: float) -> void:
	if on:
		_ensure_spots()
	_edge_to = 1.0 if on else 0.0
	_edge_secs = maxf(seconds, 0.01)
	if seconds <= 0.0:
		_edge = _edge_to


func set_floor(on: bool, seconds: float) -> void:
	if on:
		_ensure_spots()
	_floor_to = 1.0 if on else 0.0
	_floor_secs = maxf(seconds, 0.01)
	if seconds <= 0.0:
		_floor = _floor_to


func edge_on() -> bool:
	return _edge_to > 0.5


func floor_on() -> bool:
	return _floor_to > 0.5


## Islands where the floor does not burn (and the burning is put out): `centres` with `radius`, shrinking by `shrink` (a fraction of the radius) every `every` seconds down to `minimum`.
func cold_islands(centres: PackedVector2Array, radius: float, every: float, shrink: float, minimum: float) -> void:
	_cold.clear()
	for c: Vector2 in centres:
		_cold.append({"c": c, "r": radius, "t0": _t, "every": every, "shrink": shrink, "min": minimum})


func clear_cold() -> void:
	_cold.clear()


func _cold_radius(i: Dictionary) -> float:
	var k: float = (_t - float(i["t0"])) / maxf(float(i["every"]), 0.01)
	var grow: float = smoothstep(0.0, 0.5, _t - float(i["t0"]))
	return float(i["r"]) * maxf(1.0 - float(i["shrink"]) * k, float(i["min"])) * grow


func cold_at(p: Vector2) -> bool:
	for i: Dictionary in _cold:
		if p.distance_to(i["c"] as Vector2) <= _cold_radius(i):
			return true
	return false


## Is `p` within the burning rim of the floor? (the floor is `on_floor`, an edge is where it ends)
func in_edge_band(p: Vector2) -> bool:
	for d: float in [7.0, 14.0, edge_width]:
		for k: int in 8:
			if not field.on_floor(p + Vector2.from_angle(TAU * float(k) / 8.0) * d):
				return true
	return false


func _ensure_spots() -> void:
	if _spots_ready or field == null:
		return
	_spots_ready = true
	var rect: Rect2 = field.floor_rect()
	var edge_pts: PackedVector2Array = PackedVector2Array()
	var y: float = rect.position.y + 4.0
	while y < rect.end.y:
		var x: float = rect.position.x + 4.0
		while x < rect.end.x:
			var p: Vector2 = Vector2(x + 4.0 * _n(x * 0.31 + y * 0.17), y + 4.0 * _n(x * 0.13 + y * 0.43))
			if field.on_floor(p) and in_edge_band(p):
				edge_pts.append(p)
			x += EDGE_STRIDE
		y += EDGE_STRIDE
	_edge_spots = edge_pts
	_edge_flames.build(edge_pts, 9.0, 17.0, 7)
	var floor_pts: PackedVector2Array = PackedVector2Array()
	y = rect.position.y + 6.0
	while y < rect.end.y:
		var x2: float = rect.position.x + 6.0
		while x2 < rect.end.x:
			var q: Vector2 = Vector2(x2 + 8.0 * _n(x2 * 0.21 + y * 0.57), y + 8.0 * _n(x2 * 0.71 + y * 0.11))
			if field.on_floor(q):
				floor_pts.append(q)
			x2 += FLOOR_STRIDE
		y += FLOOR_STRIDE
	_floor_flames.build(floor_pts, 8.0, 13.0, 11)


# --- running -------------------------------------------------------------------------------------------------------


func _process(delta: float) -> void:
	_t += delta
	_edge = move_toward(_edge, _edge_to, delta / _edge_secs)
	_floor = move_toward(_floor, _floor_to, delta / _floor_secs)
	_edge_flames.amount = _edge
	_floor_flames.amount = _floor * 0.85
	_run_events(delta)
	if host:
		_host_acc += delta
		if _host_acc >= HOST_TICK:
			_host_acc = 0.0
			_host_tick()
	_acc += delta
	var active: bool = _is_active()
	if _acc >= REDRAW and (active or _drew):
		_acc = 0.0
		_scorch.queue_redraw()
		_glow.queue_redraw()
		_sky.queue_redraw()
	_drew = active


func _is_active() -> bool:
	return not _fires.is_empty() or not _columns.is_empty() or not _seals.is_empty() or not _bursts.is_empty() or not _bits.is_empty() or not _cold.is_empty() or _edge > 0.01 or _floor > 0.01


func _run_events(delta: float) -> void:
	for i: int in range(_columns.size() - 1, -1, -1):
		var c: Dictionary = _columns[i]
		if not bool(c["done"]) and _t >= float(c["hit"]):
			c["done"] = true
			_column_hit(c)
		if _t > float(c["hit"]) + 0.7:
			_columns.remove_at(i)
	for i2: int in range(_seals.size() - 1, -1, -1):
		var s: Dictionary = _seals[i2]
		if not bool(s["burst"]) and _t >= float(s["t_end"]):
			s["burst"] = true
			s["gone"] = _t
			if s["point"] != Vector2.INF or is_instance_valid(s["node"]):
				_seal_burst(s)
		elif bool(s["burst"]) and _t > float(s["gone"]) + 0.1:
			_seals.remove_at(i2)
	for i3: int in range(_bursts.size() - 1, -1, -1):
		if _t > float((_bursts[i3] as Dictionary)["t0"]) + 1.0:
			_bursts.remove_at(i3)
	for i4: int in range(_fires.size() - 1, -1, -1):
		if _t > float((_fires[i4] as Dictionary)["end"]) + 0.1:
			_fires.remove_at(i4)
	for i5: int in range(_bits.size() - 1, -1, -1):
		var bit: Dictionary = _bits[i5]
		bit["age"] = float(bit["age"]) + delta
		if float(bit["age"]) >= float(bit["life"]):
			_bits.remove_at(i5)
		else:
			var vel: Vector2 = bit["vel"] as Vector2
			vel.y += 240.0 * delta
			bit["vel"] = vel
			bit["pos"] = (bit["pos"] as Vector2) + vel * delta


func _sparks(at: Vector2, count: int, speed: float, up: float) -> void:
	for i: int in count:
		var dir: Vector2 = Vector2.from_angle(randf() * TAU)
		_bits.append({"pos": at, "vel": Vector2(dir.x * randf_range(0.3, 1.0) * speed, dir.y * speed * 0.4 - up * randf_range(0.5, 1.0)), "age": 0.0, "life": randf_range(0.3, 0.7), "white": randf() < 0.45})


func _column_hit(c: Dictionary) -> void:
	var at: Vector2 = c["c"] as Vector2
	ShockRing.burst(boss.get_parent(), at, float(c["r"]) * 1.4, 0.9)
	boss.shake_near(at, 1.5)
	_sparks(at, 16, 90.0, 120.0)
	if float(c["ember"]) > 0.0:
		light(at, float(c["r"]) * 0.85, 0.0, float(c["ember"]), float(c["scale"]), false)


func _seal_burst(s: Dictionary) -> void:
	var node: Node2D = s["node"] as Node2D
	var at: Vector2 = s["point"] as Vector2
	if at == Vector2.INF:
		at = node.global_position
	_bursts.append({"c": at, "r": float(s["r"]), "t0": _t})
	ShockRing.burst(boss.get_parent(), at, float(s["r"]), 1.4)
	boss.shake_near(at, 2.6)
	_sparks(at, 46, 130.0, 160.0)


## Host: whoever stands on burning ground catches fire (the floor, a field), unless she stands on cold ground (that puts it out).
func _host_tick() -> void:
	var floor_hot: bool = _floor > 0.6
	var edge_hot: bool = _edge > 0.6
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.effects == null:
			continue
		var p: Vector2 = player.global_position
		if cold_at(p):
			if player.effects.has("burn"):
				player.effects.clear("burn")
			continue
		if floor_hot and field.on_floor(p):
			player.effects.apply("burn", floor_burn, field.damage_scale * floor_scale)
		elif edge_hot and field.on_floor(p) and in_edge_band(p):
			player.effects.apply("burn", floor_burn, field.damage_scale * floor_scale)
		for f: Dictionary in _fires:
			if _t >= float(f["ignite"]) and _t < float(f["end"]) and p.distance_to(f["c"] as Vector2) <= float(f["r"]):
				player.effects.apply("burn", floor_burn + 0.4, field.damage_scale * float(f["scale"]))


# --- drawing: the floor --------------------------------------------------------------------------------------------


func _disc(canvas: Node2D, c: Vector2, r: float, color: Color) -> void:
	var ri: int = int(r)
	for y: int in range(-ri, ri + 1):
		var half: float = sqrt(maxf(r * r - float(y * y), 0.0))
		if half < 0.5:
			continue
		canvas.draw_rect(Rect2(roundf(c.x - half), roundf(c.y) + float(y), roundf(half * 2.0), 1.0), color)


func _dots(canvas: Node2D, c: Vector2, r: float, count: int, rot: float, color: Color, every: int = 0) -> void:
	for i: int in count:
		var p: Vector2 = c + Vector2.from_angle(rot + TAU * float(i) / float(count)) * r
		var big: int = 2 if every > 0 and i % every == 0 else 1
		canvas.draw_rect(Rect2(roundf(p.x), roundf(p.y), float(big), float(big)), color)


func _draw_scorch() -> void:
	for f: Dictionary in _fires:
		var c: Vector2 = f["c"] as Vector2
		var r: float = float(f["r"])
		if _t < float(f["ignite"]):
			if bool(f["warn"]):
				var k: float = clampf((_t - float(f["warn_from"])) / maxf(float(f["ignite"]) - float(f["warn_from"]), 0.01), 0.0, 1.0)
				_dots(_scorch, c, r, maxi(16, int(r * 1.2)), _t * 0.8, Color(SCORCH_RIM, 0.35 + 0.5 * k), 4)
			continue
		var life: float = 1.0 - smoothstep(float(f["end"]) - 1.0, float(f["end"]), _t)
		var grow: float = smoothstep(float(f["ignite"]), float(f["ignite"]) + 0.2, _t)
		_disc(_scorch, c, r * grow, Color(SCORCH, 0.55 * life))
		_dots(_scorch, c, r * grow, maxi(20, int(r * 1.6)), 0.0, Color(SCORCH_RIM, 0.8 * life))
	for i: Dictionary in _cold:
		var cr: float = _cold_radius(i)
		if cr > 1.0:
			_disc(_scorch, i["c"] as Vector2, cr, Color(TEAL_DARK, 0.4))


func _draw_glow() -> void:
	for f: Dictionary in _fires:
		_draw_fire_glow(f)
	for i: Dictionary in _cold:
		_draw_cold(i)
	if _edge > 0.01:
		var pulse: float = 0.6 + 0.4 * sin(_t * 3.0)
		for p: Vector2 in _edge_spots:
			var a: float = 0.05 * _edge * (0.7 + 0.5 * _n(p.x * 0.7 + p.y)) * pulse
			_glow.draw_rect(Rect2(roundf(p.x) - 6.0, roundf(p.y) - 6.0, 12.0, 12.0), Color(MAGENTA, a))
	if _floor > 0.01:
		var wave: float = 0.5 + 0.5 * sin(_t * 1.6)
		var rect: Rect2 = field.floor_rect()
		var step: float = 24.0
		var y: float = rect.position.y
		while y < rect.end.y:
			var x: float = rect.position.x
			while x < rect.end.x:
				var p2: Vector2 = Vector2(x + step * 0.5, y + step * 0.5)
				if field.on_floor(p2):
					_glow.draw_rect(Rect2(x, y, step, step), Color(EMBER, 0.045 * _floor * (0.5 + 0.5 * sin(_t * 1.6 + x * 0.05 + y * 0.07)) * (0.6 + 0.4 * wave)))
				x += step
			y += step
	for s: Dictionary in _seals:
		_draw_seal_ground(s)
	for b: Dictionary in _bursts:
		_draw_burst(b)


func _draw_fire_glow(f: Dictionary) -> void:
	var c: Vector2 = f["c"] as Vector2
	var r: float = float(f["r"])
	if _t < float(f["ignite"]):
		return
	var age: float = _t - float(f["ignite"])
	var life: float = 1.0 - smoothstep(float(f["end"]) - 0.9, float(f["end"]), _t)
	var up: float = smoothstep(0.0, 0.35, age)
	var flash: float = 1.0 - smoothstep(0.0, 0.25, age) ## the ignition: a white-pink flash over the whole patch
	_disc(_glow, c, r * (0.6 + 0.4 * up), Color(MAGENTA, (0.08 + 0.1 * flash) * life))
	if flash > 0.01:
		_disc(_glow, c, r, Color(HOT, 0.28 * flash))
	for spot: Dictionary in f["spots"] as Array:
		var o: Vector2 = spot["o"] as Vector2
		var salt: float = float(spot["salt"])
		var flick: float = 0.75 + 0.25 * sin(_t * 9.0 + salt)
		PixelFlames.flame(_glow, c + o + Vector2(0.0, 1.0), float(spot["w"]), float(spot["h"]) * up * flick * (0.45 + 0.55 * life), _t, salt, 0.85 * life)


func _draw_cold(i: Dictionary) -> void:
	var c: Vector2 = i["c"] as Vector2
	var r: float = _cold_radius(i)
	if r < 2.0:
		return
	var pulse: float = 0.6 + 0.4 * sin(_t * 2.4 + c.x)
	_dots(_glow, c, r, maxi(24, int(r * 1.6)), _t * 0.3, Color(TEAL, 0.65 * pulse), 5)
	_dots(_glow, c, r - 3.0, maxi(18, int(r * 1.2)), -_t * 0.4, Color(TEAL, 0.25), 0)
	var y: float = -r
	while y <= r:
		var half: float = sqrt(maxf(r * r - y * y, 0.0))
		var x: float = -half
		while x <= half:
			if _n(floorf((c.x + x) / 4.0) * 3.1 + floorf((c.y + y) / 4.0) * 7.7 + floorf(_t * 2.0)) < 0.16:
				_glow.draw_rect(Rect2(roundf(c.x + x), roundf(c.y + y), 1.0, 1.0), Color(TEAL, 0.5))
			x += 4.0
		y += 4.0
	for m: int in 5: ## motes rise from the cold ground
		var ph: float = fposmod(_t * 0.5 + float(m) * 0.2 + c.x * 0.01, 1.0)
		var mx: float = c.x + sin(float(m) * 2.7 + c.y) * r * 0.7
		_glow.draw_rect(Rect2(roundf(mx), roundf(c.y - ph * 22.0), 1.0, 1.0), Color(TEAL, 0.6 * (1.0 - ph)))


func _draw_seal_ground(s: Dictionary) -> void:
	var r: float = float(s["r"])
	var node: Node2D = s["node"] as Node2D
	if bool(s["burst"]):
		return
	var age: float = _t - float(s["t0"])
	var total: float = maxf(float(s["total"]), 0.01)
	if not bool(s["locked"]):
		if not is_instance_valid(node):
			return
		var k: float = clampf(age / total, 0.0, 1.0)
		var at: Vector2 = node.global_position
		_dots(_glow, at, r, 48, _t * 0.5, Color(MAGENTA, (0.12 + 0.28 * k) * smoothstep(0.0, 0.4, age)), 6) ## the radius that will burn, travelling with her
		return
	var c: Vector2 = s["point"] as Vector2
	var since: float = _t - float(s["lock_time"])
	var span: float = maxf(float(s["t_end"]) - float(s["lock_time"]), 0.01)
	var p: float = clampf(since / span, 0.0, 1.0)
	var land: float = smoothstep(0.1, 0.4, since)
	var flick: float = 0.8 + 0.2 * sin(_t * (14.0 + 20.0 * p))
	_dots(_glow, c, r, 72, _t * 0.7, Color(PALE, (0.55 + 0.4 * p) * land * flick), 6)
	_dots(_glow, c, r * 0.62, 36, -_t * 1.1, Color(MAGENTA, 0.6 * land), 4)
	_dots(_glow, c, r * 0.3, 16, _t * 1.7, Color(HOT, 0.6 * land), 4)
	for sp: int in 8: ## spokes
		var dir: Vector2 = Vector2.from_angle(_t * 0.4 + TAU * float(sp) / 8.0)
		for q: int in 6:
			var d: float = r * (0.32 + 0.3 * float(q) / 6.0)
			if _n(float(sp) * 7.0 + float(q) + floorf(_t * 8.0)) < 0.7:
				_glow.draw_rect(Rect2(roundf(c.x + dir.x * d), roundf(c.y + dir.y * d), 1.0, 1.0), Color(MAGENTA, 0.5 * land))
	var tongues: int = int(r * TAU / 11.0)
	for i: int in tongues: ## flames lick up round the sigil, higher and higher towards the burst
		var ang: float = TAU * float(i) / float(tongues) + _n(float(i)) * 0.3
		var base: Vector2 = c + Vector2.from_angle(ang) * r * 0.97
		PixelFlames.flame(_glow, base, 9.0, (5.0 + 22.0 * p * p) * land * (0.7 + 0.3 * _n(float(i) * 1.9)), _t, float(i) * 2.3, (0.25 + 0.7 * p) * land)
	PixelFlames.flame(_glow, c + Vector2(0.0, 4.0), 16.0, (8.0 + 26.0 * p * p) * land, _t, 4.4, (0.3 + 0.7 * p) * land)
	_disc(_glow, c, r, Color(MAGENTA, 0.04 + 0.12 * p * p))


func _draw_burst(b: Dictionary) -> void:
	var c: Vector2 = b["c"] as Vector2
	var r: float = float(b["r"])
	var k: float = clampf((_t - float(b["t0"])) / 0.9, 0.0, 1.0)
	var out: float = 1.0 - pow(1.0 - k, 3.0)
	_disc(_glow, c, r * (0.5 + 0.55 * out), Color(MAGENTA, 0.3 * (1.0 - k) * (1.0 - k)))
	_disc(_glow, c, r * 0.5 * (1.0 - k), Color(HOT, 0.5 * (1.0 - k)))
	_dots(_glow, c, r * (0.45 + 0.7 * out), 96, 0.0, Color(PALE, 0.9 * (1.0 - k)), 3)
	for i: int in 18:
		var ang: float = TAU * float(i) / 18.0 + _n(float(i)) * 0.4
		var rad: float = r * (0.25 + 0.6 * _n(float(i) * 3.7))
		PixelFlames.flame(_glow, c + Vector2.from_angle(ang) * rad, 11.0, 40.0 * (1.0 - k * 0.6), _t, float(i) * 1.7, 1.0 - k)


# --- drawing: the sky ----------------------------------------------------------------------------------------------


func _draw_sky() -> void:
	for c: Dictionary in _columns:
		_draw_column(c)
	for s: Dictionary in _seals:
		_draw_seal_head(s)
	for b: Dictionary in _bursts:
		var k: float = clampf((_t - float(b["t0"])) / 0.8, 0.0, 1.0)
		var half: float = 0.55 * float(b["r"]) * (1.0 - k) * 0.5
		var at: Vector2 = b["c"] as Vector2
		var y: float = 0.0
		while y < 220.0:
			var w: float = half * (1.0 - y / 300.0) * (0.8 + 0.4 * _n(y * 0.31 + floorf(_t * 20.0)))
			_sky.draw_rect(Rect2(roundf(at.x - w), roundf(at.y - y), roundf(w * 2.0), 2.0), Color(MAGENTA, 0.35 * (1.0 - k)))
			_sky.draw_rect(Rect2(roundf(at.x - w * 0.4), roundf(at.y - y), roundf(w * 0.8), 2.0), Color(HOT, 0.7 * (1.0 - k)))
			y += 2.0
	for bit: Dictionary in _bits:
		var k2: float = float(bit["age"]) / float(bit["life"])
		_sky.draw_rect(Rect2((bit["pos"] as Vector2).round(), Vector2.ONE * (2.0 if k2 < 0.5 else 1.0)), Color(HOT if bool(bit["white"]) else PALE, 1.0 - k2))


func _draw_column(c: Dictionary) -> void:
	var at: Vector2 = c["c"] as Vector2
	var r: float = float(c["r"])
	var t0: float = float(c["t0"])
	var hit: float = float(c["hit"])
	var top: float = 300.0
	if _t < hit:
		var s: float = clampf((_t - t0) / maxf(hit - t0, 0.01), 0.0, 1.0)
		var reach: float = top * (1.0 - pow(1.0 - s, 2.0)) ## the hairline falls from above and reaches the floor at the hit
		var seed_v: float = float(c["seed"])
		var y: float = 0.0
		while y < reach:
			var wob: float = (_n(seed_v + floorf(y / 6.0) + floorf(_t * 9.0)) - 0.5) * 3.0 * (1.0 - s * 0.5)
			var a: float = (0.35 + 0.6 * s) * (1.0 - y / (top + 30.0) * 0.4)
			_sky.draw_rect(Rect2(roundf(at.x + wob), roundf(at.y - top + (top - reach) + y) - 0.0, 1.0, 3.0), Color(PALE, a))
			y += 3.0
		_dots(_sky, at, r, maxi(18, int(r * 1.3)), _t * 1.5, Color(HOT, 0.3 + 0.6 * s), 5)
		return
	var u: float = clampf((_t - hit) / 0.5, 0.0, 1.0)
	var half: float = r * 0.9 * (1.0 - u * u)
	var yy: float = 0.0
	while yy < top:
		var jag: float = 0.8 + 0.35 * _n(floorf(yy / 4.0) * 1.3 + float(c["seed"]) + floorf(_t * 24.0))
		var w: float = half * jag
		var fade: float = 1.0 - yy / (top + 40.0)
		_sky.draw_rect(Rect2(roundf(at.x - w), roundf(at.y - yy), roundf(w * 2.0), 3.0), Color(MAGENTA, 0.32 * (1.0 - u) * fade))
		_sky.draw_rect(Rect2(roundf(at.x - w * 0.6), roundf(at.y - yy), roundf(w * 1.2), 3.0), Color(PALE, 0.55 * (1.0 - u) * fade))
		_sky.draw_rect(Rect2(roundf(at.x - w * 0.25), roundf(at.y - yy), roundf(w * 0.5), 3.0), Color(HOT, 0.95 * (1.0 - u) * fade))
		yy += 3.0
	_disc(_sky, at, r * (0.5 + 0.6 * u), Color(HOT, 0.5 * (1.0 - u) * (1.0 - u)))


func _draw_seal_head(s: Dictionary) -> void:
	if bool(s["burst"]):
		return
	var node: Node2D = s["node"] as Node2D
	if not is_instance_valid(node):
		return
	var age: float = _t - float(s["t0"])
	var total: float = maxf(float(s["total"]), 0.01)
	var left: float = float(s["t_end"]) - _t
	var appear: float = smoothstep(0.0, 0.3, age)
	var fall: float = 0.0
	var head: Vector2 = node.global_position + Vector2(0.0, -SEAL_HEIGHT + 2.0 * sin(_t * 5.0))
	var centre: Vector2 = head
	if bool(s["locked"]):
		fall = smoothstep(0.0, 0.32, _t - float(s["lock_time"]))
		centre = head.lerp(s["point"] as Vector2, fall * fall)
		if fall >= 1.0:
			return
	var urgency: float = 1.0 - clampf(left / total, 0.0, 1.0)
	var spin: float = _t * (2.0 + 5.0 * urgency)
	var flicker: float = 1.0 if left > 1.2 or fmod(_t * 14.0, 1.0) > 0.3 else 0.45
	var a: float = appear * (1.0 - fall) * flicker
	_disc(_sky, centre, 7.0 + 2.0 * sin(_t * 8.0), Color(MAGENTA, 0.16 * a))
	_dots(_sky, centre, 12.0, 20, spin, Color(PALE, 0.9 * a), 5)
	_dots(_sky, centre, 7.0, 10, -spin * 1.3, Color(MAGENTA, 0.9 * a), 0)
	for k: int in 4:
		var ang: float = -spin * 0.6 + TAU * float(k) / 4.0
		var p0: Vector2 = centre + Vector2.from_angle(ang) * 14.0
		_sky.draw_rect(Rect2(roundf(p0.x), roundf(p0.y), 2.0, 2.0), Color(HOT, a))
	var glyph: Array[String] = StatusTags.GLYPH
	for row: int in glyph.size():
		var line: String = glyph[row]
		for col: int in line.length():
			if line[col] == "#":
				_sky.draw_rect(Rect2(roundf(centre.x) - 2.0 + float(col), roundf(centre.y) - 3.0 + float(row), 1.0, 1.0), Color(HOT.lerp(PALE, float(row) / 6.0), a))
	var secs: String = str(maxi(ceili(left), 0))
	PixelText.draw(_sky, secs, Vector2i(int(roundf(centre.x)) - PixelText.width(secs) / 2, int(roundf(centre.y)) + 16), Color(HOT, a), Color(0, 0, 0, 0))
	var bar: float = 22.0 * clampf(left / total, 0.0, 1.0) ## a crack of light under it: the time that is left
	_sky.draw_rect(Rect2(roundf(centre.x) - 11.0, roundf(centre.y) + 14.0, bar, 1.0), Color(MAGENTA, 0.9 * a))
