class_name RiftWall
extends Node2D
## The rift of the second phase of the fight with Mornath (docs/boss_sky_cleaver.md): he tears the sky open along the line between the two pillars that still stand,
## from one edge of the arena floor to the other. It is solid (everybody, so the arena is split in two) and it hurts whoever touches it (a tick and a knock back);
## feathers fly over it. It "breathes": now and then a gap opens in it for a few seconds (`gap`), so nobody is locked in half of the arena. It collapses when the
## phase ends (`collapse`).
## Every peer builds the same line from the same two points and the arena's floor mask (no randomness that is not seeded), and plays the same timeline from the
## fight's reliable RPCs; only the host hurts.
## Look: a jagged crack of black void with a cold violet rim and a thread of white light that beats with the shadow creatures' pulse (`VoidGlow.beat`), side cracks, and a
## standing curtain of light shards over it (additive, unshaded) that flickers; lightning runs along it now and then. The gap fades the curtain and mends the crack.

signal collapsed

const FLOOR_Z: int = -2
const VEIL_Z: int = 2
const STEP: float = 12.0 ## px between the points of the jagged line
const OUTLINE: Color = Color("040208")
const DARK: Color = Color("07040d")
const RIM: Color = Color("5a36b8")
const ROCK2: Color = Color("262440")
const ROCK3: Color = Color("45436a")
const VEIN: Color = Color("7d57e0")
const VEIN_LIGHT: Color = Color("a98af0")
const CORE: Color = Color("ecd2ff")
const CORE_HOT: Color = Color("fff7ff")
const MAGENTA: Color = Color("ff4fd8")
const COLLAPSE_TIME: float = 0.9

var host: bool = false
var damage: float = 7.0
var knock: float = 200.0
var tick: float = 0.5
var hurt_range: float = 11.5
var half_width: float = 4.5
var damage_scale: float = 1.0
var _pts: PackedVector2Array = PackedVector2Array()
var _cum: PackedFloat32Array = PackedFloat32Array()
var _length: float = 0.0
var _start: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _normal: Vector2 = Vector2.DOWN
var _origin_s: float = 0.0 ## where along the line it tears open (the first pillar)
var _clock: float = 0.0
var _open_at: float = -1.0
var _open_len: float = 1.0
var _collapse_at: float = -1.0
var _gap_s: float = 0.0
var _gap_half: float = 39.0
var _gap_t0: float = -100.0
var _gap_warn: float = 1.1
var _gap_open: float = 4.0
var _cd: Dictionary = {}
var _body: StaticBody2D
var _pieces: Array[CollisionShape2D] = []
var _piece_on: Array[bool] = []
var _spurs: Array[PackedVector2Array] = [] ## side cracks (rift-local), each starts on the line
var _spur_s: PackedFloat32Array = PackedFloat32Array()
var _floor: Node2D
var _veil: Node2D
var _bolts: Array[Dictionary] = []
var _bolt_next: float = 0.4
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _dead: bool = false
var _pillar_s: PackedFloat32Array = PackedFloat32Array()
var _sheet: Node2D ## the standing tear (dark void, lit from behind)
var _dense: PackedVector2Array = PackedVector2Array() ## one sample per pixel along the crack (screen point)
var _dense_s: PackedFloat32Array = PackedFloat32Array() ## its distance along the line
var _prof: PackedFloat32Array = PackedFloat32Array() ## its random jaggedness 0..1
var _shards: Array[Dictionary] = [] ## pieces of the broken sky that hang over the tear and drift up


## `a`, `b`: the two pillars' feet; the line runs through both and on to the edge of the floor on either side (`on_floor`: Callable(Vector2) -> bool).
func setup(a: Vector2, b: Vector2, on_floor: Callable, p_host: bool, seed_v: int) -> void:
	host = p_host
	top_level = true
	global_position = Vector2.ZERO
	_rng.seed = seed_v
	var dir: Vector2 = (b - a).normalized()
	var lo: Vector2 = a
	var hi: Vector2 = b
	var walked: float = 0.0
	while walked < 600.0 and bool(on_floor.call(lo - dir * 4.0)):
		lo -= dir * 4.0
		walked += 4.0
	walked = 0.0
	while walked < 600.0 and bool(on_floor.call(hi + dir * 4.0)):
		hi += dir * 4.0
		walked += 4.0
	lo += dir * 6.0
	hi -= dir * 6.0
	_start = lo
	_dir = (hi - lo).normalized()
	_normal = _dir.orthogonal()
	_length = lo.distance_to(hi)
	_pillar_s = PackedFloat32Array([(a - lo).dot(_dir), (b - lo).dot(_dir)])
	_origin_s = _pillar_s[0]
	var count: int = maxi(2, ceili(_length / STEP))
	var wobble: float = 0.0
	for i: int in count + 1:
		var s: float = _length * float(i) / float(count)
		var edge: float = minf(1.0, minf(s, _length - s) / 20.0) ## the ends are on the line
		wobble = lerpf(wobble, (_rng.randf() - 0.5) * 11.0, 0.55)
		_pts.append(lo + _dir * s + _normal * wobble * edge)
	_cum.resize(_pts.size())
	_cum[0] = 0.0
	for i: int in range(1, _pts.size()):
		_cum[i] = _cum[i - 1] + _pts[i - 1].distance_to(_pts[i])
	_length = _cum[_cum.size() - 1]
	_make_spurs()
	_make_body()
	_floor = Node2D.new()
	_floor.name = "Floor"
	_floor.z_index = FLOOR_Z
	_floor.draw.connect(_draw_floor)
	add_child(_floor)
	_build_dense()
	_sheet = Node2D.new()
	_sheet.name = "Sheet"
	_sheet.z_index = 1
	_sheet.draw.connect(_draw_sheet)
	add_child(_sheet)
	_veil = Node2D.new()
	_veil.name = "Veil"
	_veil.z_index = VEIL_Z
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_veil.material = add
	_veil.draw.connect(_draw_veil)
	add_child(_veil)
	set_process(true)


func _make_spurs() -> void:
	for i: int in range(2, _pts.size() - 2):
		if _rng.randf() > 0.38:
			continue
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var dir: Vector2 = (_dir * _rng.randf_range(-0.6, 0.6) + _normal * side).normalized()
		var spur: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
		var at: Vector2 = Vector2.ZERO
		var length: float = _rng.randf_range(6.0, 15.0)
		var walked: float = 0.0
		while walked < length:
			var step: float = _rng.randf_range(2.0, 4.0)
			dir = dir.rotated(_rng.randf_range(-0.5, 0.5))
			at += dir * step
			walked += step
			spur.append(at)
		_spurs.append(spur)
		_spur_s.append(_cum[i])


func _make_body() -> void:
	_body = StaticBody2D.new()
	_body.name = "Wall"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	for i: int in range(0, _pts.size() - 1):
		var a: Vector2 = _pts[i]
		var b: Vector2 = _pts[i + 1]
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(a.distance_to(b) + 2.0, half_width * 2.0)
		shape.shape = rect
		shape.position = (a + b) * 0.5
		shape.rotation = (b - a).angle()
		shape.disabled = true
		_body.add_child(shape)
		_pieces.append(shape)
		_piece_on.append(false)


# --- the timeline --------------------------------------------------------------------------------------------------


## The rift tears open from the first pillar outwards in both directions, taking `duration` seconds to reach both ends.
func open(duration: float) -> void:
	_open_at = _clock
	_open_len = maxf(duration, 0.05)


## Already open (a peer that joined late, a fight restarted at the second phase).
func open_now() -> void:
	_open_at = _clock - 100.0
	_open_len = 1.0


## A gap in the wall: it flickers for `warn` seconds, then stays open for `open` seconds. `where` is a fraction of the line (0..1).
func gap(where: float, warn: float, open_seconds: float, length: float) -> void:
	_gap_s = clampf(where, 0.2, 0.8) * _length
	_gap_half = length * 0.5
	_gap_warn = warn
	_gap_open = open_seconds
	_gap_t0 = _clock


## The phase is over: the rift shatters into light and is gone.
func collapse() -> void:
	if _collapse_at >= 0.0:
		return
	_collapse_at = _clock
	_set_all_pieces(false)


func is_open_now() -> bool:
	return _gap_state() == 2


func random_gap_fraction(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(0.3, 0.7)


## 0 closed (no gap going on), 1 the gap flickers (still solid), 2 the gap is open, 3 it is about to close (still open but flickering)
func _gap_state() -> int:
	var t: float = _clock - _gap_t0
	if t < 0.0 or t > _gap_warn + _gap_open:
		return 0
	if t < _gap_warn:
		return 1
	if t > _gap_warn + _gap_open - 0.5:
		return 3
	return 2


func _reach() -> float:
	if _open_at < 0.0:
		return -1.0
	var k: float = clampf((_clock - _open_at) / _open_len, 0.0, 1.0)
	return (1.0 - pow(1.0 - k, 2.0)) * (maxf(_origin_s, _length - _origin_s) + 20.0)


func _visible_at(s: float) -> bool:
	return absf(s - _origin_s) <= _reach()


func _in_gap(s: float) -> bool:
	var state: int = _gap_state()
	return state >= 2 and absf(s - _gap_s) <= _gap_half


func _set_all_pieces(on: bool) -> void:
	for i: int in _pieces.size():
		_set_piece(i, on)


func _set_piece(i: int, on: bool) -> void:
	if _piece_on[i] == on:
		return
	_piece_on[i] = on
	_pieces[i].set_deferred("disabled", not on)


func _process(delta: float) -> void:
	if _dead:
		return
	_clock += delta
	if _collapse_at >= 0.0:
		if _clock - _collapse_at >= COLLAPSE_TIME:
			_dead = true
			collapsed.emit()
			queue_free()
			return
	else:
		for i: int in _pieces.size():
			var s: float = (_cum[i] + _cum[i + 1]) * 0.5
			_set_piece(i, _visible_at(s) and not _in_gap(s))
		if host:
			_hurt_step(delta)
	_step_bolts(delta)
	_floor.queue_redraw()
	_sheet.queue_redraw()
	_veil.queue_redraw()


# --- hurting -------------------------------------------------------------------------------------------------------


## The distance from `p` to the nearest solid part of the rift, and the nearest point.
func nearest(p: Vector2) -> Dictionary:
	var best: float = 1e9
	var at: Vector2 = Vector2.ZERO
	for i: int in range(0, _pts.size() - 1):
		var s: float = (_cum[i] + _cum[i + 1]) * 0.5
		if not _visible_at(s) or _in_gap(s):
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, _pts[i], _pts[i + 1])
		var d: float = q.distance_to(p)
		if d < best:
			best = d
			at = q
	return {"distance": best, "point": at}


func _hurt_step(delta: float) -> void:
	for key: Variant in _cd.keys():
		_cd[key] = float(_cd[key]) - delta
	if _collapse_at >= 0.0 or _reach() < 0.0:
		return
	for player: Player in Player.all:
		if player.health.current <= 0.0:
			continue
		var id: int = player.get_instance_id()
		if float(_cd.get(id, 0.0)) > 0.0:
			continue
		var hit: Dictionary = nearest(player.global_position)
		if float(hit["distance"]) > hurt_range:
			continue
		_cd[id] = tick
		var box: HurtboxComponent = player.get_node_or_null("Hurtbox") as HurtboxComponent
		if box != null:
			box.take_hit(roundf(damage * damage_scale), hit["point"] as Vector2, knock)


## Does the segment from `a` to `b` cross a solid part of the rift? (his chase does not cross it)
func blocks(a: Vector2, b: Vector2) -> bool:
	if _reach() < 0.0 or _collapse_at >= 0.0:
		return false
	for i: int in range(0, _pts.size() - 1):
		var s: float = (_cum[i] + _cum[i + 1]) * 0.5
		if not _visible_at(s) or _in_gap(s):
			continue
		if Geometry2D.segment_intersects_segment(a, b, _pts[i], _pts[i + 1]) != null:
			return true
	return false


## Which side of the rift `p` is on (the sign) and how far from the line.
func signed_distance(p: Vector2) -> float:
	return (p - _start).dot(_normal)


func direction() -> Vector2:
	return _dir


func normal() -> Vector2:
	return _normal


func middle() -> Vector2:
	return _start + _dir * _length * 0.5


func pillar_distance(i: int) -> float:
	return _pillar_s[clampi(i, 0, 1)]


func length() -> float:
	return _length


# --- drawing -------------------------------------------------------------------------------------------------------


func _fade() -> float:
	if _collapse_at < 0.0:
		return 1.0
	return 1.0 - smoothstep(0.35, 1.0, (_clock - _collapse_at) / COLLAPSE_TIME)


## 1 where the rift is whole, lower where a gap is (flickering while it opens and closes).
func _solid(s: float) -> float:
	var state: int = _gap_state()
	if state == 0:
		return 1.0
	var inside: float = 1.0 - smoothstep(_gap_half - 14.0, _gap_half + 6.0, absf(s - _gap_s))
	if state == 2:
		return 1.0 - inside * 0.92
	var flick: float = 0.5 + 0.5 * sin(_clock * 38.0 + s * 0.2)
	return 1.0 - inside * flick * 0.6


func _draw_floor() -> void:
	var reach: float = _reach()
	if reach < 0.0:
		return
	var fade: float = _fade()
	var beat: float = VoidGlow.beat(_clock, 0.0, 0.8)
	for i: int in range(0, _pts.size() - 1):
		var s: float = (_cum[i] + _cum[i + 1]) * 0.5
		if absf(s - _origin_s) > reach:
			continue
		var solid: float = _solid(s) * fade
		if solid <= 0.02:
			continue
		var a: Vector2 = _pts[i].round()
		var b: Vector2 = _pts[i + 1].round()
		var born: float = 1.0 - clampf((absf(s - _origin_s) - (reach - 30.0)) / 30.0, 0.0, 1.0) ## the front of the tear is thin
		var w: float = 3.0 + 9.0 * born
		_floor.draw_line(a, b, Color(RIM, 0.55 * solid), w + 4.0)
		_floor.draw_line(a, b, Color(OUTLINE, 0.96 * solid), w + 2.0)
		_floor.draw_line(a, b, Color(DARK, solid), maxf(w - 2.0, 1.0))
		_floor.draw_line(a, b, Color(VEIN_LIGHT.lerp(CORE_HOT, 0.4 + 0.4 * beat), (0.55 + 0.4 * beat) * solid), 1.0)
	for k: int in _spurs.size():
		var s2: float = _spur_s[k]
		if absf(s2 - _origin_s) > reach:
			continue
		var solid2: float = _solid(s2) * fade
		if solid2 <= 0.02:
			continue
		var base: Vector2 = _point_at(s2)
		var spur: PackedVector2Array = _spurs[k]
		for n: int in spur.size() - 1:
			_floor.draw_line((base + spur[n]).round(), (base + spur[n + 1]).round(), Color(OUTLINE, solid2), 3.0 if n == 0 else 2.0)
		for n2: int in spur.size() - 1:
			var fall2: float = 1.0 - float(n2) / float(spur.size())
			_floor.draw_line((base + spur[n2]).round(), (base + spur[n2 + 1]).round(), Color(MAGENTA if k % 3 == 0 else VEIN, solid2 * (0.5 + 0.4 * beat) * fall2), 1.0)


func _point_at(s: float) -> Vector2:
	for i: int in range(0, _cum.size() - 1):
		if s <= _cum[i + 1]:
			var u: float = (s - _cum[i]) / maxf(_cum[i + 1] - _cum[i], 0.001)
			return _pts[i].lerp(_pts[i + 1], u)
	return _pts[_pts.size() - 1]


func _step_bolts(delta: float) -> void:
	for bolt: Dictionary in _bolts:
		bolt["age"] = float(bolt["age"]) + delta
	_bolts = _bolts.filter(func(b: Dictionary) -> bool: return float(b["age"]) < float(b["life"]))
	if _reach() < 0.0 or _collapse_at >= 0.0:
		return
	_bolt_next -= delta
	if _bolt_next > 0.0:
		return
	_bolt_next = _rng.randf_range(0.25, 0.8)
	var reach: float = _reach()
	var s0: float = clampf(_origin_s + (_rng.randf() * 2.0 - 1.0) * reach, 0.0, _length)
	var length: float = _rng.randf_range(40.0, 90.0)
	var s1: float = clampf(s0 + length * (1.0 if _rng.randf() < 0.5 else -1.0), 0.0, _length)
	var points: PackedVector2Array = PackedVector2Array()
	var n: int = 7
	for i: int in n + 1:
		var s: float = lerpf(s0, s1, float(i) / float(n))
		var jag: Vector2 = _normal * (_rng.randf() - 0.5) * 12.0 + Vector2(0.0, -(_rng.randf() * 18.0 + 4.0) * float(i % 2))
		points.append(_point_at(s) + jag)
	_bolts.append({"pts": points, "age": 0.0, "life": _rng.randf_range(0.07, 0.14), "s": (s0 + s1) * 0.5})


func _build_dense() -> void:
	var s: float = 0.0
	var soft: float = 0.5
	var target: float = 0.5
	var i: int = 0
	while s <= _length:
		if i % 5 == 0:
			target = _rng.randf()
		soft = lerpf(soft, target, 0.35)
		_dense.append(_point_at(s).round())
		_dense_s.append(s)
		_prof.append(clampf(soft * 0.7 + _rng.randf() * 0.3, 0.0, 1.0))
		s += 1.0
		i += 1
	for k: int in 14: ## the shards that drift above the tear
		_shards.append({"s": _rng.randf() * _length, "phase": _rng.randf() * 60.0, "speed": _rng.randf_range(7.0, 16.0), "size": _rng.randi_range(1, 3), "sway": _rng.randf() * TAU})


## How tall the tear stands at sample `i` (px): a slit, tallest in the middle, torn and uneven.
func _height_at(i: int) -> float:
	var u: float = _dense_s[i] / maxf(_length, 1.0)
	var slit: float = pow(sin(PI * clampf(u, 0.0, 1.0)), 0.55)
	var beat: float = VoidGlow.beat(_clock, 0.0, 0.8)
	return ((10.0 + 40.0 * slit) * (0.5 + 0.7 * _prof[i]) + 3.0 * beat * slit) * lerpf(0.14, 1.0, _clear(_dense_s[i]))


## 0 right at a pillar, 1 from about 46 px away along the line: the tear sinks to a low crack where it runs into a pillar, so the pillar stands in front of it and is never hidden.
func _clear(s: float) -> float:
	var near: float = 1e9
	for ps: float in _pillar_s:
		near = minf(near, absf(s - ps))
	return smoothstep(12.0, 46.0, near)


## 0 at the front of the tear while it opens (it is thin there), 1 further back.
func _born(s: float, reach: float) -> float:
	return 1.0 - clampf((absf(s - _origin_s) - (reach - 34.0)) / 34.0, 0.0, 1.0)


## The standing tear: a dark slit in the picture (void with a faint depth, torn spikes along its top and a bright edge), world-lit.
func _draw_sheet() -> void:
	var reach: float = _reach()
	if reach < 0.0:
		return
	var fade: float = _fade()
	for i: int in _dense.size():
		var s: float = _dense_s[i]
		if absf(s - _origin_s) > reach:
			continue
		var solid: float = _solid(s) * fade
		if solid <= 0.03:
			continue
		var h: float = _height_at(i) * solid * _born(s, reach)
		if h < 1.5:
			continue
		var p: Vector2 = _dense[i]
		var x: float = p.x
		var y: float = p.y
		_sheet.draw_rect(Rect2(x, y - h * 0.5, 1.0, h * 0.5 + 1.0), Color(0.012, 0.0, 0.035, 0.9 * solid))
		_sheet.draw_rect(Rect2(x, y - h * 0.82, 1.0, h * 0.32), Color(0.02, 0.0, 0.06, 0.74 * solid))
		_sheet.draw_rect(Rect2(x, y - h, 1.0, h * 0.18), Color(0.03, 0.01, 0.09, 0.45 * solid))
		_sheet.draw_rect(Rect2(x, y - h - 1.0, 1.0, 2.0), Color(OUTLINE, 0.95 * solid)) ## the torn top edge
		if i % 7 == 0: ## torn basalt plates along the lip, like the blade lamellae of his wings: dark body, a lit left edge, a violet rim on top
			var clear: float = _clear(s)
			var ph: float = (4.0 + 11.0 * _hash(i, 12)) * (0.35 + 0.65 * clear)
			var pw: float = 2.0 + floorf(_hash(i, 13) * 2.0)
			var lean: float = floorf((_hash(i, 14) - 0.5) * 3.0)
			_sheet.draw_rect(Rect2(x - 1.0, y - h - ph - 1.0 + lean, pw + 2.0, ph + 2.0), Color(OUTLINE, solid))
			_sheet.draw_rect(Rect2(x, y - h - ph + lean, pw, ph + 1.0), Color(ROCK2, solid))
			_sheet.draw_rect(Rect2(x, y - h - ph + lean, 1.0, ph + 1.0), Color(ROCK3, solid))
			_sheet.draw_rect(Rect2(x, y - h - ph + lean, pw, 1.0), Color(RIM, 0.9 * solid))
		if i % 11 == 3: ## the lips of the tear on the floor: low black teeth
			_sheet.draw_rect(Rect2(x - 1.0, y - 3.0, 3.0, 4.0), Color(OUTLINE, 0.9 * solid))


## The light of the tear (additive): depth behind the slit (stars, rising streaks of light), the bright edge, the base seam, a halo, shafts and drifting shards, bolts and the front.
func _draw_veil() -> void:
	var reach: float = _reach()
	if reach < 0.0:
		return
	var fade: float = _fade()
	var beat: float = VoidGlow.beat(_clock, 0.0, 0.8)
	var tick: int = int(_clock * 7.0)
	for i: int in _dense.size():
		var s: float = _dense_s[i]
		if absf(s - _origin_s) > reach:
			continue
		var solid: float = _solid(s) * fade
		if solid <= 0.03:
			continue
		var born: float = _born(s, reach)
		var h: float = _height_at(i) * solid * born
		if h < 1.5:
			continue
		var p: Vector2 = _dense[i]
		var x: float = p.x
		var y: float = p.y
		if i % 3 == 0: ## a soft halo of violet over and beside the tear
			_veil.draw_rect(Rect2(x - 2.0, y - h - 6.0, 5.0, h + 7.0), Color(VEIN, 0.1 * solid * (0.7 + 0.5 * beat)))
		if i % 2 == 0: ## the sky behind the tear: deep violet at the foot, magenta-hot towards the lip, slow bands of light drifting through it (dithered)
			var band: float = fposmod(0.2 * float(i / 24) + _clock * 0.06, 1.0)
			for k: int in 3:
				var f0: float = float(k) / 3.0
				var tint: Color = VEIN.lerp(MAGENTA, f0 * 0.7)
				var glow: float = (0.05 + 0.1 * f0 + 0.1 * maxf(0.0, 1.0 - absf(f0 + 0.17 - band) * 5.0)) * solid
				_veil.draw_rect(Rect2(x, y - h * (f0 + 0.34), 1.0, h * 0.34), Color(tint, glow))
		# the depth of the slit: stars that twinkle and streaks of light that climb inside it
		var star: float = _hash(i, 31)
		if star > 0.9:
			var sy: float = y - h * (0.1 + 0.8 * fposmod(star * 7.0 + _hash(i, 5), 1.0))
			_veil.draw_rect(Rect2(x, sy, 1.0, 1.0), Color(CORE if star > 0.96 else VEIN_LIGHT, (0.35 + 0.5 * absf(sin(_clock * (1.5 + 3.0 * star) + float(i)))) * solid))
		if i % 8 == 2:
			var climb: float = fposmod(_clock * (16.0 + 22.0 * _hash(i, 9)) + _hash(i, 2) * 90.0, h)
			var streak: float = 3.0 + 4.0 * _hash(i, 4)
			_veil.draw_rect(Rect2(x, y - climb - streak, 1.0, streak), Color(VEIN_LIGHT, 0.55 * (1.0 - climb / h) * solid))
		# the edge: a bright thread along the top, hot where it is high, flaring in magenta now and then
		var hot: float = 0.65 + 0.35 * beat
		_veil.draw_rect(Rect2(x, y - h - 1.0, 1.0, 1.0), Color(CORE_HOT, hot * solid))
		_veil.draw_rect(Rect2(x, y - h, 1.0, 1.0), Color(VEIN_LIGHT, 0.7 * solid))
		if _hash(i, tick) > 0.985:
			_veil.draw_rect(Rect2(x - 1.0, y - h - 3.0, 3.0, 4.0), Color(MAGENTA, 0.5 * solid))
		# the seam on the floor
		_veil.draw_rect(Rect2(x, y - 1.0, 1.0, 2.0), Color(CORE_HOT, (0.45 + 0.4 * beat) * solid))
		if i % 29 == 7: ## a shaft of light climbing out of the tear
			var rise: float = 26.0 + 30.0 * _hash(i, 8)
			_veil.draw_rect(Rect2(x, y - h - rise * 0.5, 1.0, rise * 0.5), Color(VEIN_LIGHT, 0.2 * solid))
			_veil.draw_rect(Rect2(x, y - h - rise, 1.0, rise * 0.5), Color(VEIN, 0.1 * solid))
	# pieces of the broken sky hang over the tear and drift up (lit edge and a hot dot)
	for shard: Dictionary in _shards:
		var s2: float = float(shard["s"])
		if absf(s2 - _origin_s) > reach or (_collapse_at >= 0.0 and _fade() < 0.3):
			continue
		var idx: int = clampi(int(s2), 0, _dense.size() - 1)
		var solid2: float = _solid(s2) * fade
		var rise2: float = fposmod(_clock * float(shard["speed"]) + float(shard["phase"]), 64.0)
		var base: Vector2 = _dense[idx] + Vector2(sin(_clock * 0.9 + float(shard["sway"])) * 4.0, -_height_at(idx) * 0.6 - rise2)
		var life: float = (1.0 - rise2 / 64.0) * solid2 * smoothstep(0.0, 6.0, rise2)
		var size: int = int(shard["size"])
		_veil.draw_rect(Rect2(base.round(), Vector2(size + 1, size)), Color(VEIN, 0.55 * life))
		_veil.draw_rect(Rect2(base.round(), Vector2(1, 1)), Color(CORE_HOT, 0.9 * life))
	for bolt: Dictionary in _bolts:
		var pts: PackedVector2Array = bolt["pts"] as PackedVector2Array
		var k: float = 1.0 - float(bolt["age"]) / float(bolt["life"])
		var solid3: float = _solid(float(bolt["s"])) * fade
		for i2: int in pts.size() - 1:
			_veil.draw_line(pts[i2].round(), pts[i2 + 1].round(), Color(MAGENTA, 0.55 * k * solid3), 3.0)
			_veil.draw_line(pts[i2].round(), pts[i2 + 1].round(), Color(CORE_HOT, k * solid3), 1.0)
	# the front of the tear throws a bright knot and sparks of light while it opens
	if _open_at >= 0.0 and reach < maxf(_origin_s, _length - _origin_s) + 18.0 and _collapse_at < 0.0:
		for side: float in [-1.0, 1.0]:
			var fs: float = _origin_s + side * reach
			if fs < 0.0 or fs > _length:
				continue
			var front: Vector2 = _point_at(fs).round()
			_veil.draw_rect(Rect2(front + Vector2(-2, -22), Vector2(5, 24)), Color(CORE_HOT, 0.6))
			_veil.draw_rect(Rect2(front + Vector2(-6, -30), Vector2(13, 34)), Color(VEIN_LIGHT, 0.2))
			for n: int in 3:
				var off: Vector2 = Vector2(_hash(n, tick) * 12.0 - 6.0, -_hash(n, tick + 4) * 36.0)
				_veil.draw_rect(Rect2((front + off).round(), Vector2.ONE), Color(CORE_HOT, 0.9))


func _hash(a: int, b: int) -> float:
	return float(hash(a * 7919 + b * 104729 + 17) % 1000) / 1000.0
