class_name WitchFx
extends Node2D
## Everything Morwenna's fight puts into the hollow besides the warnings on the floor (those are the `FeatherField`'s zones): root spears, drops of
## cursed sap and the puddles they leave, mirror shards that bounce off the slate, the threads of the mirror cage, the earth mound of her burrowing,
## curse seams, the beams of the glitch split, the pulses of the tree, mist puffs, golden dust, and the feather storm of the panicking ravens.
## On every peer, on the field's clock (`FeatherField.now()`), so all of it is in step with the warnings. Only the host hurts: shards in flight and the
## cage's threads are checked here (`host`), the puddles slow the peer's OWN player (movement is the owner's).

const GROUND_Z: int = -3
const AMBER: Color = Color("c47c1c")
const AMBER_HOT: Color = Color("f0c468")
const GREEN: Color = Color("a8ff6a")
const VIOLET: Color = Color("cf7aff")
const MAGENTA: Color = Color("ff58d0")
const MIRROR: Color = Color("a6c0cc")
const MIRROR_HOT: Color = Color("ecf8fb")
const BARK: Color = Color("2e201a")
const BARK_LIT: Color = Color("6a523c")
const INK: Color = Color("090612")
const GOLD: Color = Color("ffe9a0")

var host: bool = false
var damage_scale: float = 1.0
var field: FeatherField
var hurt_total: int = 0
var mound: Vector2 = Vector2.INF ## where the burrowing witch is (set every frame by the fight), INF = none
var _ground: Node2D
var _ground_glow: Node2D
var _sky: Node2D
var _sky_glow: Node2D
var _spears: Array[Dictionary] = []
var _drops: Array[Dictionary] = []
var _puddles: Array[Dictionary] = []
var _shots: Array[Dictionary] = []
var _cages: Array[Dictionary] = []
var _seams: Array[Dictionary] = []
var _beams: Array[Dictionary] = []
var _pulses: Array[Dictionary] = []
var _bits: Array[Dictionary] = []
var _slowing: bool = false
var _mound_bits: float = 0.0
var _storm: Control
var _storm_layer: CanvasLayer
var _storm_until: float = -1.0
var _storm_from: float = 0.0
var _storm_seed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(p_field: FeatherField, p_host: bool) -> void:
	field = p_field
	host = p_host
	top_level = true
	global_position = Vector2.ZERO
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ground = _layer("Ground", GROUND_Z + 1, null, _draw_ground)
	_ground_glow = _layer("GroundGlow", 0, add, _draw_ground_glow, _ground)
	_sky = _layer("Sky", 6, null, _draw_sky)
	_sky_glow = _layer("SkyGlow", 0, add, _draw_sky_glow, _sky)


func _layer(node_name: String, z: int, mat: Material, fn: Callable, parent: Node = null) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = node_name
	node.z_index = z
	node.material = mat
	node.draw.connect(fn)
	(parent if parent != null else self).add_child(node)
	return node


func now() -> float:
	return field.now()


# --- what the fight asks for ---------------------------------------------------------------------------------------


## Thorned roots break out of the ground at `pos` at `t_hit` (the zone's moment) and stand for a breath.
func add_spear(pos: Vector2, t_hit: float, tall: float = 30.0) -> void:
	_spears.append({"p": pos, "t": t_hit, "tall": tall, "seed": _rng.randf() * 99.0, "dusted": false})


## A drop of cursed sap thrown from `src` (`src_h` above the ground) lands at `dst` at `t1` and leaves a puddle of `radius` for `stay` seconds (it slows).
func add_drop(src: Vector2, src_h: float, dst: Vector2, t0: float, t1: float, radius: float, stay: float) -> void:
	_drops.append({"a": src, "ah": src_h, "b": dst, "t0": t0, "t1": t1, "r": radius, "stay": stay})


## A mirror shard that flies along `path` (a polyline: it has bounced off the slate at every corner) from `t0` at `speed`. Host: it hurts whom it touches, once.
func add_shot(path: PackedVector2Array, t0: float, speed: float, damage: float, knock: float, show: float) -> void:
	var total: float = 0.0
	for i: int in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	_shots.append({"path": path, "t0": t0, "speed": speed, "len": total, "damage": damage, "knock": knock, "show": show, "hit": {}, "spin": _rng.randf() * TAU})


## The mirror cage: splinters are rammed into the ground at `posts` at `t_plant`, the threads between them burn from `t_on` to `t_off` (host: a tick for whoever touches one).
func add_cage(posts: PackedVector2Array, t_plant: float, t_on: float, t_off: float, damage: float, knock: float) -> void:
	_cages.append({"posts": posts, "plant": t_plant, "on": t_on, "off": t_off, "damage": damage, "knock": knock, "tick": t_on, "planted": false})


## A curse seam she leaves on the ground along a dash: it glows from `t0` and bursts at `t_burst` (the damage is the field's lane).
func add_seam(a: Vector2, b: Vector2, t0: float, t_burst: float) -> void:
	_seams.append({"a": a, "b": b, "t0": t0, "t": t_burst, "burst": false})


## A beam charged from `src` along a -> b: it fires at `t_fire`. A phantom's (`real` false) only crackles and fizzles out.
func add_beam(src: Vector2, a: Vector2, b: Vector2, t0: float, t_fire: float, real: bool) -> void:
	_beams.append({"src": src, "a": a, "b": b, "t0": t0, "t": t_fire, "real": real, "fired": false})


## Cancels the beams that have not fired yet (she was struck out of the charge).
func cancel_beams() -> void:
	for beam: Dictionary in _beams:
		if not bool(beam["fired"]):
			beam["real"] = false


## A pulse of the tree: the band between `inner` and `outer` round `centre` flares at `t_hit`.
func add_pulse(centre: Vector2, inner: float, outer: float, t_hit: float) -> void:
	_pulses.append({"c": centre, "in": inner, "out": outer, "t": t_hit, "done": false})


## A puff of mist where a phantom is struck away or she vanishes (`green`: the phantom's colour).
func puff(pos: Vector2, green: bool, amount: int = 16) -> void:
	for i: int in amount:
		var dir: Vector2 = Vector2.from_angle(_rng.randf() * TAU)
		_bits.append({"p": pos + Vector2(dir.x * 6.0, -18.0 + dir.y * 14.0), "v": dir * _rng.randf_range(8.0, 46.0) + Vector2(0, -14.0), "age": 0.0, "life": _rng.randf_range(0.35, 0.8),
			"col": (GREEN if green else VIOLET).lerp(INK, _rng.randf_range(0.2, 0.75)), "g": -10.0, "glow": i % 3 == 0, "size": 1.0 + float(i % 2)})


## Sparks of a blade or a shard at `pos`.
func sparks(pos: Vector2, color: Color, amount: int = 8) -> void:
	for i: int in amount:
		_bits.append({"p": pos, "v": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(30.0, 110.0), "age": 0.0, "life": _rng.randf_range(0.15, 0.4), "col": color, "g": 160.0, "glow": true, "size": 1.0})


## The redemption: golden dust rises from `pos` for `seconds`.
func gold_dust(pos: Vector2, amount: int) -> void:
	for i: int in amount:
		_bits.append({"p": pos + Vector2(_rng.randf_range(-13.0, 13.0), _rng.randf_range(-30.0, 2.0)), "v": Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-34.0, -9.0)), "age": 0.0,
			"life": _rng.randf_range(1.1, 2.6), "col": GOLD.lerp(Color("ffb84a"), _rng.randf()), "g": -6.0, "glow": true, "size": 1.0 + float(i % 3 == 0)})


## The panicking ravens dive through the hollow: feathers and wings sweep over the picture of every player near `centre` for `seconds`.
func feather_storm(centre: Vector2, seconds: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.global_position.distance_to(centre) < 620.0:
			if _storm == null:
				_storm_layer = CanvasLayer.new()
				_storm_layer.layer = 0
				add_child(_storm_layer)
				_storm = Control.new()
				_storm.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_storm.set_anchors_preset(Control.PRESET_FULL_RECT)
				_storm.draw.connect(_draw_storm)
				_storm_layer.add_child(_storm)
			_storm_from = now()
			_storm_until = now() + seconds
			_storm_seed = _rng.randf() * 50.0
			return


func clear() -> void:
	_spears.clear()
	_drops.clear()
	_puddles.clear()
	_shots.clear()
	_cages.clear()
	_seams.clear()
	_beams.clear()
	_pulses.clear()
	mound = Vector2.INF
	_storm_until = -1.0
	_release_slow()


func _exit_tree() -> void:
	_release_slow()


func _release_slow() -> void:
	if not _slowing:
		return
	_slowing = false
	for player: Player in Player.all:
		if is_instance_valid(player) and player.is_multiplayer_authority():
			player.clear_slow(self)


# --- the clock -----------------------------------------------------------------------------------------------------


func _process(delta: float) -> void:
	if field == null:
		return
	var t: float = now()
	for i: int in range(_spears.size() - 1, -1, -1):
		var s: Dictionary = _spears[i]
		if not bool(s["dusted"]) and t >= float(s["t"]):
			s["dusted"] = true
			_dirt(s["p"] as Vector2, 7)
		if t > float(s["t"]) + 1.05:
			_spears.remove_at(i)
	for i: int in range(_drops.size() - 1, -1, -1):
		var d: Dictionary = _drops[i]
		if t >= float(d["t1"]):
			_puddles.append({"p": d["b"], "r": d["r"], "t0": t, "until": t + float(d["stay"]), "seed": _rng.randf() * 99.0})
			sparks(d["b"] as Vector2, AMBER_HOT, 6)
			_drops.remove_at(i)
	for i: int in range(_puddles.size() - 1, -1, -1):
		if t > float(_puddles[i]["until"]):
			_puddles.remove_at(i)
	_step_slow(t)
	_step_shots(t)
	_step_cages(t)
	for i: int in range(_seams.size() - 1, -1, -1):
		var seam: Dictionary = _seams[i]
		if not bool(seam["burst"]) and t >= float(seam["t"]):
			seam["burst"] = true
			var a: Vector2 = seam["a"] as Vector2
			var b: Vector2 = seam["b"] as Vector2
			for k: int in 9:
				sparks(a.lerp(b, (float(k) + 0.5) / 9.0), VIOLET, 3)
		if t > float(seam["t"]) + 0.45:
			_seams.remove_at(i)
	for i: int in range(_beams.size() - 1, -1, -1):
		var beam: Dictionary = _beams[i]
		if not bool(beam["fired"]) and t >= float(beam["t"]):
			beam["fired"] = true
			if not bool(beam["real"]):
				puff((beam["src"] as Vector2), true, 8)
		if t > float(beam["t"]) + 0.5:
			_beams.remove_at(i)
	for i: int in range(_pulses.size() - 1, -1, -1):
		var pulse: Dictionary = _pulses[i]
		if not bool(pulse["done"]) and t >= float(pulse["t"]):
			pulse["done"] = true
			ShockRing.burst(get_tree().current_scene, pulse["c"] as Vector2, float(pulse["out"]) * 0.6, 1.0)
		if t > float(pulse["t"]) + 0.5:
			_pulses.remove_at(i)
	if mound.is_finite():
		_mound_bits -= delta
		if _mound_bits <= 0.0:
			_mound_bits = 0.05
			_dirt(mound, 2)
	for i: int in range(_bits.size() - 1, -1, -1):
		var bit: Dictionary = _bits[i]
		bit["age"] = float(bit["age"]) + delta
		if float(bit["age"]) >= float(bit["life"]):
			_bits.remove_at(i)
			continue
		var v: Vector2 = bit["v"] as Vector2
		v.y += float(bit["g"]) * delta
		v *= 1.0 - 1.6 * delta
		bit["v"] = v
		bit["p"] = (bit["p"] as Vector2) + v * delta
	var busy: bool = not (_spears.is_empty() and _drops.is_empty() and _puddles.is_empty() and _shots.is_empty() and _cages.is_empty() and _seams.is_empty() and _beams.is_empty() and _pulses.is_empty() and _bits.is_empty()) or mound.is_finite()
	if busy or _ground.visible:
		_ground.visible = busy
		_sky.visible = busy
		_ground.queue_redraw()
		_ground_glow.queue_redraw()
		_sky.queue_redraw()
		_sky_glow.queue_redraw()
	if _storm != null:
		_storm.visible = t < _storm_until
		if _storm.visible:
			_storm.queue_redraw()


func _dirt(pos: Vector2, amount: int) -> void:
	for i: int in amount:
		_bits.append({"p": pos + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-2.0, 2.0)), "v": Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-58.0, -18.0)), "age": 0.0,
			"life": _rng.randf_range(0.3, 0.6), "col": BARK.lerp(BARK_LIT, _rng.randf()), "g": 210.0, "glow": false, "size": 1.0 + float(i % 2)})


## The sap is sticky: the peer's own player wades slowly while she stands in a puddle.
func _step_slow(_t: float) -> void:
	var inside: bool = false
	var mine: Player
	for player: Player in Player.all:
		if not player.is_multiplayer_authority():
			continue
		mine = player
		for puddle: Dictionary in _puddles:
			var d: Vector2 = player.global_position - (puddle["p"] as Vector2)
			d.y *= 1.5
			if d.length() <= float(puddle["r"]):
				inside = true
				break
	if mine == null:
		return
	if inside and not _slowing:
		_slowing = true
		mine.set_slow(self, 0.5)
	elif not inside and _slowing:
		_slowing = false
		mine.clear_slow(self)


static func point_on(path: PackedVector2Array, distance: float) -> Vector2:
	var left: float = distance
	for i: int in range(path.size() - 1):
		var seg: float = path[i].distance_to(path[i + 1])
		if left <= seg:
			return path[i].lerp(path[i + 1], left / maxf(seg, 0.001))
		left -= seg
	return path[path.size() - 1]


func _step_shots(t: float) -> void:
	for i: int in range(_shots.size() - 1, -1, -1):
		var shot: Dictionary = _shots[i]
		var gone: float = (t - float(shot["t0"])) * float(shot["speed"])
		if gone > float(shot["len"]):
			sparks(point_on(shot["path"] as PackedVector2Array, float(shot["len"])), MIRROR_HOT, 9)
			_shots.remove_at(i)
			continue
		if gone < 0.0 or not host:
			continue
		var at: Vector2 = point_on(shot["path"] as PackedVector2Array, gone)
		var struck: Dictionary = shot["hit"] as Dictionary
		for player: Player in Player.all:
			if player.health.current <= 0.0 or struck.has(player.name):
				continue
			var d: Vector2 = player.global_position - at
			d.y *= 1.4
			if d.length() < 11.0:
				struck[player.name] = true
				_hurt(player, float(shot["damage"]), float(shot["knock"]), at)


func _step_cages(t: float) -> void:
	for i: int in range(_cages.size() - 1, -1, -1):
		var cage: Dictionary = _cages[i]
		var posts: PackedVector2Array = cage["posts"] as PackedVector2Array
		if not bool(cage["planted"]) and t >= float(cage["plant"]):
			cage["planted"] = true
			for post: Vector2 in posts:
				_dirt(post, 5)
				sparks(post + Vector2(0, -8), MIRROR_HOT, 4)
		if t > float(cage["off"]) + 0.4:
			for post: Vector2 in posts:
				sparks(post + Vector2(0, -8), MIRROR, 5)
			_cages.remove_at(i)
			continue
		if not host or t < float(cage["on"]) or t > float(cage["off"]) or t < float(cage["tick"]):
			continue
		cage["tick"] = t + 0.35
		for player: Player in Player.all:
			if player.health.current <= 0.0:
				continue
			for k: int in posts.size():
				var a: Vector2 = posts[k]
				var b: Vector2 = posts[(k + 1) % posts.size()]
				var near: Vector2 = FeatherField._closest(player.global_position, a, b)
				if near.distance_to(player.global_position) < 6.0:
					_hurt(player, float(cage["damage"]), float(cage["knock"]), near)
					break


func _hurt(player: Player, damage: float, knock: float, from: Vector2) -> void:
	var box: HurtboxComponent = player.get_node_or_null("Hurtbox") as HurtboxComponent
	if box != null:
		hurt_total += 1
		box.take_hit(roundf(damage * damage_scale), from, knock)


# --- drawing -------------------------------------------------------------------------------------------------------


func _px(canvas: Node2D, at: Vector2, color: Color, size: float = 1.0) -> void:
	canvas.draw_rect(Rect2(floorf(at.x), floorf(at.y), size, size), color)


func _hash(n: float) -> float:
	return fposmod(sin(n * 127.1) * 43758.5453, 1.0)


## A flat ellipse of single pixel rows, dithered at its rim.
func _pool(canvas: Node2D, at: Vector2, radius: float, color: Color, seed_v: float, edge: float = 0.72) -> void:
	var ry: float = radius * 0.62
	for y: int in range(-ceili(ry), ceili(ry) + 1):
		var q: float = float(y) / ry
		if absf(q) > 1.0:
			continue
		var w: float = sqrt(1.0 - q * q) * radius
		w += (_hash(seed_v + float(y) * 1.7) - 0.5) * 4.0
		var inner: float = floorf(w * edge)
		canvas.draw_rect(Rect2(floorf(at.x - inner), floorf(at.y) + float(y), inner * 2.0, 1.0), color)
		for x: int in range(int(inner), int(w)):
			if (x + y) % 2 == 0:
				canvas.draw_rect(Rect2(floorf(at.x) + float(x), floorf(at.y) + float(y), 1.0, 1.0), color)
				canvas.draw_rect(Rect2(floorf(at.x) - float(x) - 1.0, floorf(at.y) + float(y), 1.0, 1.0), color)


func _draw_ground() -> void:
	var t: float = now()
	for puddle: Dictionary in _puddles:
		var grow: float = smoothstep(0.0, 0.25, t - float(puddle["t0"]))
		var fade: float = smoothstep(0.0, 0.6, float(puddle["until"]) - t)
		var at: Vector2 = puddle["p"] as Vector2
		_pool(_ground, at, float(puddle["r"]) * grow, Color(0.16, 0.09, 0.03, 0.78 * fade), float(puddle["seed"]))
		_pool(_ground, at + Vector2(-1, -1), float(puddle["r"]) * grow * 0.62, Color(AMBER.r, AMBER.g, AMBER.b, 0.55 * fade), float(puddle["seed"]) + 3.0)
	if mound.is_finite():
		_pool(_ground, mound, 12.0, Color(BARK.r, BARK.g, BARK.b, 0.95), 4.0)
		_pool(_ground, mound + Vector2(-1, -3), 8.0, Color(BARK_LIT.r, BARK_LIT.g, BARK_LIT.b, 0.9), 9.0)
		for k: int in 5:
			var a: float = float(k) * 1.3 + t * 3.0
			_px(_ground, mound + Vector2(cos(a) * 9.0, sin(a) * 5.0 - 2.0), INK, 2.0)
	for seam: Dictionary in _seams:
		var a: Vector2 = seam["a"] as Vector2
		var b: Vector2 = seam["b"] as Vector2
		var n: int = int(a.distance_to(b) / 3.0)
		for k: int in n:
			var p: Vector2 = a.lerp(b, float(k) / float(maxi(n, 1)))
			p += (b - a).orthogonal().normalized() * (_hash(float(k) * 0.77) - 0.5) * 3.0
			_px(_ground, p, INK, 2.0)
	for cage: Dictionary in _cages:
		if t < float(cage["plant"]):
			continue
		for post: Vector2 in cage["posts"] as PackedVector2Array:
			_pool(_ground, post + Vector2(0, 1), 5.0, Color(0, 0, 0, 0.4), 2.0)


func _draw_ground_glow() -> void:
	var t: float = now()
	for puddle: Dictionary in _puddles:
		var fade: float = smoothstep(0.0, 0.6, float(puddle["until"]) - t)
		var at: Vector2 = puddle["p"] as Vector2
		for k: int in 5:
			var a: float = float(puddle["seed"]) + float(k) * 1.9 + t * 0.6
			var blink: float = 0.5 + 0.5 * sin(t * 5.0 + float(k) * 2.0)
			_px(_ground_glow, at + Vector2(cos(a), sin(a) * 0.6) * float(puddle["r"]) * 0.55, Color(AMBER_HOT.r, AMBER_HOT.g, AMBER_HOT.b, 0.5 * fade * blink))
	for seam: Dictionary in _seams:
		var a: Vector2 = seam["a"] as Vector2
		var b: Vector2 = seam["b"] as Vector2
		var age: float = t - float(seam["t0"])
		var left: float = float(seam["t"]) - t
		var hot: float = 1.0 if left < 0.0 else clampf(0.3 + 0.7 * (1.0 - left / maxf(float(seam["t"]) - float(seam["t0"]), 0.01)), 0.0, 1.0)
		var shown: float = clampf(age / 0.12, 0.0, 1.0)
		var n: int = int(a.distance_to(b) / 2.0 * shown)
		var total: float = maxf(a.distance_to(b) / 2.0, 1.0)
		var after: float = clampf(1.0 - (t - float(seam["t"])) / 0.45, 0.0, 1.0) if left < 0.0 else 1.0
		for k: int in n:
			var p: Vector2 = a.lerp(b, float(k) / total)
			p += (b - a).orthogonal().normalized() * (_hash(floorf(float(k) / 3.0) * 0.77) - 0.5) * 3.0
			var beat: float = 0.6 + 0.4 * sin(t * 18.0 - float(k) * 0.3)
			_px(_ground_glow, p, Color(VIOLET.r, VIOLET.g, VIOLET.b, hot * beat * after * 0.9), 1.0 if left > 0.0 else 3.0)
	for pulse: Dictionary in _pulses:
		var since: float = t - float(pulse["t"])
		if since < -0.9 or since > 0.5:
			continue
		var centre: Vector2 = pulse["c"] as Vector2
		var bright: float = clampf(1.0 - since / 0.5, 0.0, 1.0) if since >= 0.0 else 0.0
		var rim: float = clampf(1.0 + since / 0.9, 0.0, 1.0)
		for edge: float in [float(pulse["in"]), float(pulse["out"])]:
			if edge < 4.0:
				continue
			var steps: int = int(edge * 1.1)
			for k: int in steps:
				var a: float = TAU * float(k) / float(steps) + t * 0.3
				if k % 3 == 0 or since >= 0.0:
					_px(_ground_glow, centre + Vector2(cos(a) * edge, sin(a) * edge * 0.72), Color(GREEN.r, GREEN.g, GREEN.b, 0.25 * rim + 0.7 * bright), 1.0 + float(since >= 0.0))


## Thorned roots: three crooked spikes that shoot up, hold and sink back.
func _draw_spear(s: Dictionary, glow: bool) -> void:
	var canvas: Node2D = _sky_glow if glow else _sky
	var since: float = now() - float(s["t"])
	if since < -0.12:
		return
	var up: float = clampf((since + 0.12) / 0.14, 0.0, 1.0)
	up = 1.0 - (1.0 - up) * (1.0 - up)
	up *= 1.0 - smoothstep(0.65, 1.05, since)
	var base: Vector2 = s["p"] as Vector2
	for k: int in 3:
		var lean: float = (float(k) - 1.0) * 0.38 + (_hash(float(s["seed"]) + float(k)) - 0.5) * 0.3
		var tall: float = float(s["tall"]) * (1.0 if k == 1 else 0.68) * up
		var foot: Vector2 = base + Vector2((float(k) - 1.0) * 5.0, float(k % 2) * 2.0)
		var steps: int = int(tall)
		for j: int in steps:
			var q: float = float(j) / maxf(float(steps), 1.0)
			var at: Vector2 = foot + Vector2(sin(lean) * float(j) + sin(q * 7.0 + float(s["seed"])) * 1.4, -float(j))
			var w: float = maxf(1.0, roundf(3.0 * (1.0 - q)))
			if glow:
				if j % 5 == 2:
					_px(canvas, at, Color(GREEN.r, GREEN.g, GREEN.b, 0.85 * up))
			else:
				canvas.draw_rect(Rect2(floorf(at.x - w * 0.5), floorf(at.y), w + 1.0, 1.0), INK)
				canvas.draw_rect(Rect2(floorf(at.x - w * 0.5), floorf(at.y), w, 1.0), BARK if j % 4 else BARK_LIT)
				if j % 6 == 3 and w > 1.0: ## a thorn
					_px(canvas, at + Vector2(-w, -1.0), BARK_LIT)
					_px(canvas, at + Vector2(w + 1.0, 0.0), INK)


func _shard(canvas: Node2D, at: Vector2, angle: float, size: float, color: Color) -> void:
	if size < 0.75 or not at.is_finite(): ## too small to triangulate
		return
	## drawn in its own frame: far out in the world (x ~ 13000) the triangulation of so small a shape fails in float precision
	canvas.draw_set_transform(at, angle if is_finite(angle) else 0.0)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(size, 0.0), Vector2(0.0, size * 0.36), Vector2(-size * 0.7, 0.0), Vector2(0.0, -size * 0.36)]), color)
	canvas.draw_set_transform(Vector2.ZERO)


func _draw_sky() -> void:
	var t: float = now()
	for s: Dictionary in _spears:
		_draw_spear(s, false)
	for d: Dictionary in _drops:
		var k: float = clampf((t - float(d["t0"])) / maxf(float(d["t1"]) - float(d["t0"]), 0.01), 0.0, 1.0)
		if t < float(d["t0"]):
			continue
		var at: Vector2 = (d["a"] as Vector2).lerp(d["b"] as Vector2, k) + Vector2(0.0, -(float(d["ah"]) * (1.0 - k) + sin(k * PI) * 46.0))
		_sky.draw_rect(Rect2(floorf(at.x) - 2.0, floorf(at.y) - 2.0, 5.0, 5.0), INK)
		_sky.draw_rect(Rect2(floorf(at.x) - 1.0, floorf(at.y) - 1.0, 3.0, 3.0), AMBER)
		_px(_sky, at + Vector2(-1, -1), AMBER_HOT)
		var shade: Vector2 = (d["a"] as Vector2).lerp(d["b"] as Vector2, k)
		_sky.draw_rect(Rect2(floorf(shade.x) - 2.0, floorf(shade.y), 4.0, 1.0), Color(0, 0, 0, 0.3))
	for shot: Dictionary in _shots:
		var gone: float = (t - float(shot["t0"])) * float(shot["speed"])
		var path: PackedVector2Array = shot["path"] as PackedVector2Array
		if gone < 0.0:
			continue
		var at: Vector2 = point_on(path, gone) + Vector2(0, -9)
		var ahead: Vector2 = point_on(path, gone + 4.0) + Vector2(0, -9)
		var angle: float = (ahead - at).angle()
		_shard(_sky, at, angle, 8.0, INK)
		_shard(_sky, at, angle, 6.5, MIRROR)
		_shard(_sky, at + Vector2(-1, -1), angle, 3.0, MIRROR_HOT)
		_sky.draw_rect(Rect2(floorf(at.x) - 3.0, floorf(at.y) + 9.0, 6.0, 1.0), Color(0, 0, 0, 0.3))
	for cage: Dictionary in _cages:
		var since: float = t - float(cage["plant"])
		if since < -0.2:
			continue
		var sink: float = clampf((since + 0.2) / 0.2, 0.0, 1.0)
		for post: Vector2 in cage["posts"] as PackedVector2Array:
			var top: Vector2 = post + Vector2(0.0, -15.0 - 60.0 * (1.0 - sink) * (1.0 - sink))
			_sky.draw_colored_polygon(PackedVector2Array([top + Vector2(0, -3), top + Vector2(4, 4), post + Vector2(1, 0), post + Vector2(-2, 0), top + Vector2(-4, 5)]), INK)
			_sky.draw_colored_polygon(PackedVector2Array([top + Vector2(0, -1), top + Vector2(3, 4), post + Vector2(0, -1), top + Vector2(-3, 5)]), MIRROR)
			_sky.draw_line(top + Vector2(-1, 1), post + Vector2(-1, -3), MIRROR_HOT, 1.0)
	for bit: Dictionary in _bits:
		if not bool(bit["glow"]):
			var fade: float = 1.0 - float(bit["age"]) / float(bit["life"])
			var c: Color = bit["col"] as Color
			_px(_sky, bit["p"] as Vector2, Color(c.r, c.g, c.b, minf(1.0, fade * 2.0)), float(bit["size"]))


func _draw_sky_glow() -> void:
	var t: float = now()
	for s: Dictionary in _spears:
		_draw_spear(s, true)
	for shot: Dictionary in _shots:
		var path: PackedVector2Array = shot["path"] as PackedVector2Array
		var until: float = float(shot["t0"]) - t
		var gone: float = maxf(-until * float(shot["speed"]), 0.0)
		if until > float(shot["show"]):
			continue
		## the way it will take: a thin dotted glint along the whole path, running ahead of the shard
		var reveal: float = clampf(1.0 - until / maxf(float(shot["show"]), 0.01), 0.0, 1.0) if until > 0.0 else 1.0
		var total: float = float(shot["len"])
		var k: float = gone
		while k < total * reveal:
			var blink: float = 0.35 + 0.35 * sin(t * 20.0 - k * 0.2)
			if int(k / 4.0) % 2 == 0:
				_px(_sky_glow, point_on(path, k) + Vector2(0, -2), Color(MIRROR_HOT.r, MIRROR_HOT.g, MIRROR_HOT.b, blink * 0.7))
			k += 4.0
		if until <= 0.0:
			var at: Vector2 = point_on(path, gone) + Vector2(0, -9)
			for j: int in 5:
				_px(_sky_glow, point_on(path, maxf(gone - float(j) * 5.0, 0.0)) + Vector2(0, -9), Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.6 - 0.11 * float(j)), 2.0)
			_px(_sky_glow, at, Color(1, 1, 1, 0.8), 2.0)
	for cage: Dictionary in _cages:
		var posts: PackedVector2Array = cage["posts"] as PackedVector2Array
		if t < float(cage["plant"]):
			continue
		var on: bool = t >= float(cage["on"]) and t <= float(cage["off"])
		var warm: float = clampf((t - float(cage["plant"])) / maxf(float(cage["on"]) - float(cage["plant"]), 0.01), 0.0, 1.0)
		var dying: bool = float(cage["off"]) - t < 0.5 and fmod(t * 14.0, 1.0) < 0.4
		for k: int in posts.size():
			var a: Vector2 = posts[k] + Vector2(0, -11)
			var b: Vector2 = posts[(k + 1) % posts.size()] + Vector2(0, -11)
			if on and not dying:
				_sky_glow.draw_line(a, b, Color(GREEN.r, GREEN.g, GREEN.b, 0.3), 3.0)
				var n: int = int(a.distance_to(b) / 2.0)
				for j: int in n:
					var p: Vector2 = a.lerp(b, float(j) / float(maxi(n, 1))) + Vector2(0, sin(t * 30.0 + float(j) * 0.9) * 0.8)
					_px(_sky_glow, p, Color(0.92, 1.0, 0.8, 0.95))
				## what it burns on the floor: the thread's foot line (where it hurts)
				_sky_glow.draw_line(posts[k], posts[(k + 1) % posts.size()], Color(GREEN.r, GREEN.g, GREEN.b, 0.22), 1.0)
			elif t < float(cage["on"]):
				var n2: int = int(a.distance_to(b) / 5.0)
				for j: int in n2:
					if float(j) / float(maxi(n2, 1)) < warm:
						_px(_sky_glow, a.lerp(b, float(j) / float(maxi(n2, 1))), Color(GREEN.r, GREEN.g, GREEN.b, 0.5))
			_px(_sky_glow, a + Vector2(0, -4), Color(1, 1, 1, 0.7 if on else 0.4 * warm), 2.0)
	for beam: Dictionary in _beams:
		var a: Vector2 = beam["a"] as Vector2
		var b: Vector2 = beam["b"] as Vector2
		var src: Vector2 = beam["src"] as Vector2
		var real: bool = bool(beam["real"])
		var tint: Color = VIOLET if real else GREEN
		var charge: float = clampf((t - float(beam["t0"])) / maxf(float(beam["t"]) - float(beam["t0"]), 0.01), 0.0, 1.0)
		var since: float = t - float(beam["t"])
		if since < 0.0:
			for j: int in 7: ## motes drawn into the mask
				var a2: float = float(j) * 0.9 + t * 4.0
				var r: float = 18.0 * (1.0 - fposmod(t * 1.6 + float(j) * 0.14, 1.0))
				_px(_sky_glow, src + Vector2(cos(a2) * r, sin(a2) * r * 0.7 - 30.0), Color(tint.r, tint.g, tint.b, 0.8))
			var n: int = int(a.distance_to(b) / 3.0)
			for j: int in int(float(n) * charge):
				if (j + int(t * 20.0)) % 3 != 0:
					_px(_sky_glow, a.lerp(b, float(j) / float(maxi(n, 1))) + Vector2(0, -3), Color(tint.r, tint.g, tint.b, 0.35 + 0.4 * charge))
		elif real and since < 0.4:
			var k: float = 1.0 - since / 0.4
			var across: Vector2 = (b - a).orthogonal().normalized()
			_sky_glow.draw_line(a, b, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.5 * k), 16.0 * k + 2.0)
			_sky_glow.draw_line(a, b, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.6 * k), 8.0 * k + 1.0)
			_sky_glow.draw_line(a, b, Color(1, 1, 1, 0.9 * k), 3.0 * k + 1.0)
			for j: int in 14:
				var q: float = _hash(float(j) + floorf(t * 30.0))
				_px(_sky_glow, a.lerp(b, q) + across * (_hash(float(j) * 3.1 + t) - 0.5) * 26.0, Color(1, 0.8, 1, k), 2.0)
		elif not real and since < 0.3: ## the phantom's beam is nothing: static
			var n3: int = int(a.distance_to(b) / 6.0)
			for j: int in n3:
				if _hash(float(j) * 1.3 + floorf(t * 24.0)) > 0.6:
					_px(_sky_glow, a.lerp(b, float(j) / float(maxi(n3, 1))) + Vector2(0, -3), Color(GREEN.r, GREEN.g, GREEN.b, 0.5 * (1.0 - since / 0.3)), 2.0)
	for bit: Dictionary in _bits:
		if bool(bit["glow"]):
			var fade: float = 1.0 - float(bit["age"]) / float(bit["life"])
			var c: Color = bit["col"] as Color
			_px(_sky_glow, bit["p"] as Vector2, Color(c.r, c.g, c.b, fade), float(bit["size"]))


## Dark wings and feathers streaking over the screen: the sight is cut down, the warnings on the floor still show through the gaps.
func _draw_storm() -> void:
	var t: float = now()
	var view: Vector2 = _storm.size
	var age: float = t - _storm_from
	var k: float = smoothstep(0.0, 0.5, age) * smoothstep(0.0, 0.7, _storm_until - t)
	_storm.draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.01, 0.05, 0.3 * k))
	for i: int in 46:
		var h1: float = _hash(float(i) * 1.37 + _storm_seed)
		var h2: float = _hash(float(i) * 2.91 + _storm_seed)
		var speed: float = 0.5 + h1 * 0.9
		var u: float = fposmod(age * speed + h2, 1.3) - 0.15
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var x: float = (u if side > 0.0 else 1.0 - u) * view.x
		var y: float = (h1 * 1.2 - 0.1 + u * 0.35 * (h2 - 0.3)) * view.y
		var at: Vector2 = Vector2(x, y)
		var big: bool = i % 5 == 0
		var flap: float = sin(age * (17.0 + h1 * 9.0) + float(i))
		var ink: Color = Color(0.03, 0.02, 0.07, (0.92 if big else 0.8) * k)
		if big: ## a raven: body and two beating wings
			var span: float = 26.0 + 12.0 * h2
			_storm.draw_colored_polygon(PackedVector2Array([at + Vector2(side * 12.0, 0), at + Vector2(0, -3), at + Vector2(-side * 14.0, 1), at + Vector2(0, 4)]), ink)
			_storm.draw_colored_polygon(PackedVector2Array([at, at + Vector2(-side * 6.0, -span * flap), at + Vector2(-side * 16.0, -span * 0.5 * flap), at + Vector2(-side * 8.0, 2)]), ink)
			_storm.draw_colored_polygon(PackedVector2Array([at + Vector2(side * 2.0, 1), at + Vector2(-side * 3.0, span * 0.8 * flap), at + Vector2(-side * 13.0, span * 0.4 * flap), at + Vector2(-side * 7.0, 3)]), ink)
		else: ## a feather tumbling
			var a: float = age * (3.0 + h2 * 4.0) + float(i)
			var f: Vector2 = Vector2.from_angle(a) * (7.0 + 5.0 * h1)
			var s: Vector2 = f.orthogonal() * 0.28
			_storm.draw_colored_polygon(PackedVector2Array([at + f, at + s, at - f, at - s]), ink)
			_storm.draw_line(at - f, at + f, Color(0.3, 0.16, 0.5, 0.5 * k), 1.0)
