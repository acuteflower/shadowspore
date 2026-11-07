class_name FeatherField
extends Node2D
## Everything Mornath's feathers do to the arena floor, on every peer (docs/boss_sky_cleaver.md): the warnings (lanes, discs and rings of flowing red pixels on the
## flagstones, `feather_zones.gdshader`), feathers that fall out of the sky, fly through the air and stick in the ground, and the damage of it all.
## Cosmetics run on every peer from the same schedule; only the host hurts (`host`): the area drawn is the area that hurts, and it hurts at the moment it was
## announced. Times are on this node's own clock (`now()`); callers pass `now() + delay`.
## Built by SkyCleaver (top level, so everything is in world coordinates) and freed with it.
## Cheap by design: nothing is drawn or pushed to the shader while nothing is going on; falling feathers sit in one bucket per picture so each picture is looked up
## and drawn in one run; every list is pruned in place; the picture cache is filled in the background (`VoidFeather.warm_step`) from the moment the field exists.

const SHADER: Shader = preload("res://assets/shaders/feather_zones.gdshader")
const MAX_SHAPES: int = 64
const GROUND_Z: int = -3 ## warnings over the floor, under every entity (enemy warnings use -3 as well)
const SKY_Z: int = 7
const STICK_LIFE: float = 0.5 ## a landed rain feather stays this long, then crumbles
const HOT: Color = Color("ecd2ff")
const WARM_BUDGET_USEC: int = 2200

var host: bool = false
var damage_scale: float = 1.0
var time_scale: float = 1.0 ## the fight's haste: this node's clock runs this much faster than real time
var _clock: float = 0.0
var _zones: Array[Dictionary] = []
var _buckets: Array = [] ## falling feathers: one array per (lean, variant)
var _fall_count: int = 0
var _flights: Array[Dictionary] = []
var _bits: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _hands: Array[Dictionary] = [] ## blades that sweep over the floor like the hands of a clock (cosmetic: the damage is the lanes')
var _cages: Array[Dictionary] = [] ## rings of feather stakes that close in
var _ground: ColorRect
var _material: ShaderMaterial = ShaderMaterial.new()
var _sky: Node2D
var _sky_glow: Node2D
var _mask_bytes: PackedByteArray = PackedByteArray()
var _mask_origin: Vector2 = Vector2.ZERO
var _mask_w: int = 0
var _mask_h: int = 0
var _overflow_warned: bool = false
var _warmed: bool = false
var _shape_a: PackedVector4Array = PackedVector4Array()
var _shape_b: PackedVector4Array = PackedVector4Array()
var _shape_c: PackedVector4Array = PackedVector4Array()
var _shapes_on: bool = false
var _drew: bool = false
var stat_us: int = 0 ## profiling: microseconds spent in _process and the two draws since the reader last reset it


## `decal`: the arena's baked ground decal (data/ground_baked.json "decals" entry: texture, mask, x, y). Its mask says where the stone floor is.
func setup(decal: Dictionary, p_host: bool) -> void:
	host = p_host
	top_level = true
	global_position = Vector2.ZERO
	z_index = 0
	var mask_texture: Texture2D = load(String(decal["mask"])) as Texture2D
	var image: Image = mask_texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	_mask_bytes = image.get_data()
	_mask_w = image.get_width()
	_mask_h = image.get_height()
	_mask_origin = Vector2(float(decal["x"]), float(decal["y"]))
	_material.shader = SHADER
	_material.set_shader_parameter("floor_mask", mask_texture)
	_material.set_shader_parameter("mask_origin", _mask_origin)
	_material.set_shader_parameter("mask_size", Vector2(_mask_w, _mask_h))
	_shape_a.resize(MAX_SHAPES)
	_shape_b.resize(MAX_SHAPES)
	_shape_c.resize(MAX_SHAPES)
	for i: int in 12:
		_buckets.append([])
	_ground = ColorRect.new()
	_ground.name = "Zones"
	_ground.color = Color.WHITE
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.position = _mask_origin
	_ground.size = Vector2(_mask_w, _mask_h)
	_ground.z_index = GROUND_Z
	_ground.material = _material
	_ground.visible = false
	add_child(_ground)
	_sky = Node2D.new()
	_sky.name = "Sky"
	_sky.z_index = SKY_Z
	add_child(_sky)
	_sky_glow = Node2D.new()
	_sky_glow.name = "Glow"
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sky_glow.material = add
	_sky.add_child(_sky_glow)
	_sky.draw.connect(_draw_sky)
	_sky_glow.draw.connect(_draw_glow)


func now() -> float:
	return _clock


## True where the stone floor of the arena is (what the warnings and the damage are cut to).
func on_floor(point: Vector2) -> bool:
	var x: int = int(floorf(point.x - _mask_origin.x))
	var y: int = int(floorf(point.y - _mask_origin.y))
	if x < 0 or y < 0 or x >= _mask_w or y >= _mask_h:
		return false
	return _mask_bytes[(y * _mask_w + x) * 4 + 3] > 127


# --- announcing ----------------------------------------------------------------------------------------------------


## A lane (a segment with a half width). `warn`/`hit` are on `now()`'s clock; `ticks` are further moments of damage (a lingering zone).
func add_lane(a: Vector2, b: Vector2, half: float, warn: float, hit: float, damage: float, knock: float = 80.0, kind: int = 0, ticks: PackedFloat32Array = PackedFloat32Array(), patch: Vector2i = Vector2i.ZERO, hold: float = 0.16) -> void:
	_add_zone(0, a, b, half, 0.0, warn, hit, damage, knock, kind, ticks, patch, hold)


## A disc or a ring (`inner` > 0) round `centre`.
func add_ring(centre: Vector2, outer: float, inner: float, warn: float, hit: float, damage: float, knock: float = 80.0, kind: int = 0, ticks: PackedFloat32Array = PackedFloat32Array(), patch: Vector2i = Vector2i.ZERO, hold: float = 0.16) -> void:
	_add_zone(1, centre, Vector2.ZERO, outer, inner, warn, hit, damage, knock, kind, ticks, patch, hold)


func _add_zone(type: int, a: Vector2, b: Vector2, w: float, inner: float, warn: float, hit: float, damage: float, knock: float, kind: int, ticks: PackedFloat32Array, patch: Vector2i, hold: float) -> void:
	var hits: PackedFloat32Array = PackedFloat32Array([hit])
	hits.append_array(ticks)
	_zones.append({
		"type": type, "a": a, "b": b, "w": w, "inner": inner, "warn": warn, "hits": hits, "next": 0,
		"damage": damage, "knock": knock, "kind": kind, "patch": patch, "hold": hold, "end": hits[hits.size() - 1] + hold,
		"seed": randf() * 100.0,
	})


## A feather that falls out of the sky onto `ground` and lands at `hit` (cosmetic: the damage is the zone's). `variant` 0..3, `lean` -1/0/1 (a third of a radian each way).
func add_fall(ground: Vector2, hit: float, variant: int, lean: int, height: float = 130.0, fall: float = 0.26) -> void:
	var li: int = clampi(lean, -1, 1) + 1
	(_buckets[li * 4 + (variant & 3)] as Array).append({"ground": ground, "drop": hit - fall, "hit": hit, "h": height, "landed": false})
	_fall_count += 1


## A feather that flies from a point in the air (`src` on the ground, `src_h` high) to `dst` (on the ground, `dst_h` high) between `t0` and `t1`, and stays stuck
## there for `stay` seconds. With `damage` > 0 (host) it hurts whoever it passes through on its way (the ground distance to the flight line is below `radius`).
## `size` is the thrown feather's (length, width), `stuck_size` the one that stays in the ground.
func add_flight(src: Vector2, src_h: float, dst: Vector2, dst_h: float, t0: float, t1: float, size: Vector2i, variant: int, stay: float = 0.0, damage: float = 0.0, knock: float = 120.0, radius: float = 9.0, stuck_size: Vector2i = Vector2i.ZERO, ease_out: bool = false) -> void:
	_flights.append({
		"ease": ease_out, "src": src, "src_h": src_h, "dst": dst, "dst_h": dst_h, "t0": t0, "t1": t1, "len": size.x, "wid": size.y, "var": variant & 1, "stay": stay,
		"damage": damage, "knock": knock, "radius": radius, "struck": [], "landed": false, "stuck": stuck_size if stuck_size != Vector2i.ZERO else Vector2i(size.x * 3 / 2, size.y * 4 / 3),
		"lean": (float(variant % 3) - 1.0) * 0.26,
	})


## How far along its flight a feather is (0..1); thrown ones leave fast and slow down.
func _flight_s(f: Dictionary) -> float:
	var s: float = clampf((_clock - float(f["t0"])) / maxf(float(f["t1"]) - float(f["t0"]), 0.001), 0.0, 1.0)
	return 1.0 - (1.0 - s) * (1.0 - s) if bool(f["ease"]) else s


## A blade that lies on the floor at `origin` and sweeps round from angle `a0` to `a1` (radians) between `t0` and `t1`, `length` px long. It grows out of
## the pillar from `show` on, fades after `t1`. Cosmetic: the sweep's damage is a row of lanes added with `add_lane`.
func add_hand(origin: Vector2, a0: float, a1: float, length: float, show: float, t0: float, t1: float) -> void:
	_hands.append({"o": origin, "a0": a0, "a1": a1, "len": length, "show": show, "t0": t0, "t1": t1})


## A ring of feather stakes round `centre` at radius `r0` (with a gap of `gap_w` radians pointing along `gap_a`) that falls in at `t_start - 0.3`, closes to radius `r1` between
## `t_start` and `t_end` and hurts whoever the wall passes through (host). The warning (a dotted circle and the gap) shows from `show`.
func add_cage(centre: Vector2, r0: float, r1: float, gap_a: float, gap_w: float, show: float, t_start: float, t_end: float, damage: float, knock: float, wall_half: float) -> void:
	_cages.append({"c": centre, "r0": r0, "r1": r1, "ga": gap_a, "gw": gap_w, "show": show, "t0": t_start, "t1": t_end, "damage": damage, "knock": knock, "half": wall_half, "struck": [], "n": 26})


## Sparks that fly out of a point of the picture (where a feather leaves a wing).
func add_sparks(screen_pos: Vector2, count: int) -> void:
	_bits.append({"kind": 1, "pos": screen_pos, "age": 0.0, "life": 0.16, "radius": 7.0})
	for i: int in count:
		var dir: Vector2 = Vector2.from_angle(randf() * TAU)
		_bits.append({"kind": 0, "pos": screen_pos, "vel": dir * randf_range(30.0, 90.0), "age": 0.0, "life": randf_range(0.14, 0.32), "white": randf() < 0.55})


## An eye over a player's head (the one the boss is after) until `until`.
func add_mark(player: Node2D, until: float) -> void:
	_marks.append({"node": player, "until": until})


func clear_marks() -> void:
	_marks.clear()


## Everything announced and still to come is dropped (the boss breaks off); what lies stuck in the ground crumbles at once.
func clear() -> void:
	_zones.clear()
	for i: int in range(_flights.size() - 1, -1, -1):
		var f: Dictionary = _flights[i]
		if not bool(f["landed"]) or _clock >= float(f["t1"]) + float(f["stay"]):
			_flights.remove_at(i)
		else:
			f["stay"] = minf(float(f["stay"]), _clock - float(f["t1"]) + 0.25)
	for bucket: Array in _buckets:
		for i: int in range(bucket.size() - 1, -1, -1):
			if not bool((bucket[i] as Dictionary)["landed"]):
				bucket.remove_at(i)
				_fall_count -= 1
	_marks.clear()
	_hands.clear()
	_cages.clear()


func busy() -> bool:
	return not _zones.is_empty() or _fall_count > 0 or not _flights.is_empty() or not _hands.is_empty() or not _cages.is_empty()


# --- running -------------------------------------------------------------------------------------------------------


func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_clock += delta * time_scale
	if not _warmed:
		_warmed = VoidFeather.warm_step(WARM_BUDGET_USEC)
	if not _zones.is_empty():
		_run_zones()
	if _fall_count > 0:
		_run_falls()
	if not _flights.is_empty():
		_run_flights()
	if not _bits.is_empty():
		_run_bits(delta)
	if not _cages.is_empty():
		_run_cages()
	if not _hands.is_empty():
		_prune_hands()
	for i: int in range(_marks.size() - 1, -1, -1):
		if _clock >= float((_marks[i] as Dictionary)["until"]) or not is_instance_valid((_marks[i] as Dictionary)["node"]):
			_marks.remove_at(i)
	_push_shapes()
	var active: bool = _fall_count > 0 or not _flights.is_empty() or not _bits.is_empty() or not _marks.is_empty() or not _hands.is_empty() or not _cages.is_empty()
	if active or _drew:
		_sky.queue_redraw()
		_sky_glow.queue_redraw()
	_drew = active
	stat_us += Time.get_ticks_usec() - t0


func _run_zones() -> void:
	for i: int in range(_zones.size() - 1, -1, -1):
		var z: Dictionary = _zones[i]
		var hits: PackedFloat32Array = z["hits"] as PackedFloat32Array
		while int(z["next"]) < hits.size() and _clock >= hits[int(z["next"])]:
			if int(z["next"]) == 0 and (z["patch"] as Vector2i) != Vector2i.ZERO:
				ShadowPatch.spawn(get_tree().current_scene, z["a"] as Vector2, z["patch"] as Vector2i, 2.4, 1.6, 5)
			if host:
				_damage_zone(z)
			z["next"] = int(z["next"]) + 1
		if _clock > float(z["end"]):
			_zones.remove_at(i)


func _damage_zone(z: Dictionary) -> void:
	for player: Player in Player.all:
		if player.health.current <= 0.0:
			continue
		var p: Vector2 = player.global_position
		if not on_floor(p) or not _inside(z, p):
			continue
		var from: Vector2 = (z["a"] as Vector2) if int(z["type"]) == 1 else _closest(p, z["a"] as Vector2, z["b"] as Vector2)
		_hurt(player, float(z["damage"]), float(z["knock"]), from)


func _inside(z: Dictionary, p: Vector2) -> bool:
	if int(z["type"]) == 0:
		return _closest(p, z["a"] as Vector2, z["b"] as Vector2).distance_to(p) <= float(z["w"])
	var r: float = p.distance_to(z["a"] as Vector2)
	return r <= float(z["w"]) and r >= float(z["inner"])


static func _closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var l2: float = maxf(ab.length_squared(), 0.0001)
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


func _hurt(player: Player, damage: float, knock: float, from: Vector2) -> void:
	var box: HurtboxComponent = player.get_node_or_null("Hurtbox") as HurtboxComponent
	if box != null:
		box.take_hit(roundf(damage * damage_scale), from, knock)


func _run_falls() -> void:
	for bucket: Array in _buckets:
		for i: int in range(bucket.size() - 1, -1, -1):
			var f: Dictionary = bucket[i]
			if not bool(f["landed"]) and _clock >= float(f["hit"]):
				f["landed"] = true
				_impact(f["ground"] as Vector2, 0.6)
			if _clock >= float(f["hit"]) + STICK_LIFE:
				bucket.remove_at(i)
				_fall_count -= 1


func _run_flights() -> void:
	for i: int in range(_flights.size() - 1, -1, -1):
		var f: Dictionary = _flights[i]
		var t0: float = float(f["t0"])
		var t1: float = float(f["t1"])
		if _clock >= t0:
			if _clock < t1:
				if host and float(f["damage"]) > 0.0:
					var s: float = _flight_s(f)
					var ground: Vector2 = (f["src"] as Vector2).lerp(f["dst"] as Vector2, s)
					var height: float = lerpf(float(f["src_h"]), float(f["dst_h"]), s)
					if height < 30.0:
						for player: Player in Player.all:
							if player.health.current <= 0.0 or (f["struck"] as Array).has(player.get_instance_id()):
								continue
							if player.global_position.distance_to(ground) <= float(f["radius"]):
								(f["struck"] as Array).append(player.get_instance_id())
								_hurt(player, float(f["damage"]), float(f["knock"]), f["src"] as Vector2)
			elif not bool(f["landed"]):
				f["landed"] = true
				_impact(f["dst"] as Vector2, 1.0 if float(f["stay"]) > 0.0 else 0.4)
		if _clock >= t1 + maxf(float(f["stay"]), 0.0) + 0.05:
			_flights.remove_at(i)


func _prune_hands() -> void:
	for i: int in range(_hands.size() - 1, -1, -1):
		if _clock > float((_hands[i] as Dictionary)["t1"]) + 0.5:
			_hands.remove_at(i)


func _cage_radius(c: Dictionary) -> float:
	var s: float = clampf((_clock - float(c["t0"])) / maxf(float(c["t1"]) - float(c["t0"]), 0.01), 0.0, 1.0)
	return lerpf(float(c["r0"]), float(c["r1"]), s * s * (3.0 - 2.0 * s) * 0.4 + s * 0.6)


func _in_cage_gap(c: Dictionary, angle: float) -> bool:
	return absf(angle_difference(angle, float(c["ga"]))) < float(c["gw"]) * 0.5


func _run_cages() -> void:
	for i: int in range(_cages.size() - 1, -1, -1):
		var c: Dictionary = _cages[i]
		if _clock > float(c["t1"]) + 0.5:
			_cages.remove_at(i)
			continue
		if not host or _clock < float(c["t0"]) or _clock > float(c["t1"]) + 0.1:
			continue
		var r: float = _cage_radius(c)
		for player: Player in Player.all:
			if player.health.current <= 0.0 or (c["struck"] as Array).has(player.get_instance_id()):
				continue
			var rel: Vector2 = player.global_position - (c["c"] as Vector2)
			if absf(rel.length() - r) > float(c["half"]) + 3.0 or _in_cage_gap(c, rel.angle()):
				continue
			(c["struck"] as Array).append(player.get_instance_id())
			_hurt(player, float(c["damage"]), float(c["knock"]), (c["c"] as Vector2) + rel.normalized() * r)


## A small burst where a feather lands: a flat ring, a few shards that fly up and fall back.
func _impact(at: Vector2, strength: float) -> void:
	_bits.append({"kind": 1, "pos": at, "age": 0.0, "life": 0.18 + 0.1 * strength, "radius": 6.0 + 8.0 * strength})
	for i: int in 2 + int(3.0 * strength):
		var dir: Vector2 = Vector2.from_angle(randf() * TAU)
		_bits.append({"kind": 0, "pos": at + dir * 2.0, "vel": Vector2(dir.x * randf_range(24.0, 70.0), randf_range(-70.0, -30.0)), "age": 0.0, "life": randf_range(0.22, 0.45), "white": randf() < 0.4})


func _run_bits(delta: float) -> void:
	for i: int in range(_bits.size() - 1, -1, -1):
		var bit: Dictionary = _bits[i]
		bit["age"] = float(bit["age"]) + delta
		if float(bit["age"]) >= float(bit["life"]):
			_bits.remove_at(i)
		elif int(bit["kind"]) == 0:
			var vel: Vector2 = bit["vel"] as Vector2
			vel.y += 260.0 * delta
			bit["vel"] = vel
			bit["pos"] = (bit["pos"] as Vector2) + vel * delta


func _push_shapes() -> void:
	if _zones.is_empty():
		if _shapes_on:
			_shapes_on = false
			_ground.visible = false
		return
	var n: int = 0
	for z: Dictionary in _zones:
		if _clock < float(z["warn"]):
			continue
		if n >= MAX_SHAPES:
			if not _overflow_warned:
				_overflow_warned = true
				push_warning("FeatherField: more than %d shapes announced at once" % MAX_SHAPES)
			break
		var hits: PackedFloat32Array = z["hits"] as PackedFloat32Array
		var first: float = hits[0]
		var strength: float = clampf((_clock - float(z["warn"])) / 0.25, 0.0, 1.0)
		var urgency: float = smoothstep(first - 0.4, first, _clock)
		var speed: float = 9.0 + 9.0 * urgency
		if _clock >= first:
			var since: float = _clock - first
			urgency = 1.0
			if int(z["kind"]) == 1:
				strength = 0.5 + 0.2 * sin(_clock * 9.0 + float(z["seed"]))
				speed = 5.0
			else:
				strength = clampf(1.0 - since / maxf(float(z["hold"]), 0.01), 0.0, 1.0)
		var za: Vector2 = z["a"] as Vector2
		var zb: Vector2 = z["b"] as Vector2
		_shape_a[n] = Vector4(za.x, za.y, zb.x, zb.y)
		_shape_b[n] = Vector4(float(z["type"]), float(z["w"]), float(z["inner"]), 0.0)
		_shape_c[n] = Vector4(float(z["kind"]), strength, speed, urgency)
		n += 1
	_material.set_shader_parameter("shape_a", _shape_a)
	_material.set_shader_parameter("shape_b", _shape_b)
	_material.set_shader_parameter("shape_c", _shape_c)
	_material.set_shader_parameter("count", n)
	_material.set_shader_parameter("time", _clock)
	_shapes_on = n > 0
	_ground.visible = _shapes_on


# --- drawing -------------------------------------------------------------------------------------------------------


func _put(canvas: CanvasItem, texture: Texture2D, tip: Vector2, at: Vector2, alpha: float = 1.0) -> void:
	canvas.draw_texture(texture, (at - tip).round(), Color(1, 1, 1, alpha))


func _bucket_art(index: int) -> Dictionary:
	return VoidFeather.art(VoidFeather.FALL.x, VoidFeather.FALL.y, PI / 2.0 + VoidFeather.LEANS[index / 4], index % 4)


func _fall_pos(f: Dictionary) -> Vector2:
	var ground: Vector2 = f["ground"] as Vector2
	var drop: float = float(f["drop"])
	if _clock >= float(f["hit"]):
		return ground
	var s: float = clampf((_clock - drop) / maxf(float(f["hit"]) - drop, 0.001), 0.0, 1.0)
	return ground + Vector2(0.0, -float(f["h"]) * (1.0 - s * s))


func _draw_sky() -> void:
	var t0: int = Time.get_ticks_usec()
	_draw_sky_body()
	stat_us += Time.get_ticks_usec() - t0


func _draw_sky_body() -> void:
	# one pass for everything that is a plain line or square, then the pictures bucket by bucket: the canvas merges neighbours that share a texture, so
	# a rain of a hundred feathers is a dozen draw calls, not a hundred and fifty
	if _fall_count > 0:
		for index: int in _buckets.size():
			var lean: float = VoidFeather.LEANS[index / 4]
			for f: Dictionary in (_buckets[index] as Array):
				if _clock >= float(f["drop"]) and _clock < float(f["hit"]):
					_sky.draw_rect(Rect2((_fall_pos(f) + Vector2(-lean * 8.0, -VoidFeather.FALL.x * 0.6 - 9.0)).round(), Vector2(1, 8)), Color(VoidFeather.VEIN_LIGHT, 0.4))
	for f: Dictionary in _flights:
		if _clock >= float(f["t0"]) and _clock < float(f["t1"]):
			var src: Vector2 = f["src"] as Vector2
			var dst: Vector2 = f["dst"] as Vector2
			var s: float = _flight_s(f)
			var screen: Vector2 = src.lerp(dst, s) + Vector2(0.0, -lerpf(float(f["src_h"]), float(f["dst_h"]), s))
			var motion: Vector2 = Vector2(dst.x - src.x, (dst.y - src.y) - (float(f["dst_h"]) - float(f["src_h"]))).normalized()
			var back: Vector2 = (screen - motion * (float(int(f["len"])) * 0.62 + 2.0)).round()
			_sky.draw_line(back, (back - motion * 9.0).round(), Color(VoidFeather.VEIN, 0.55), 1.0) ## a streak behind it
	if _fall_count > 0:
		for index: int in _buckets.size():
			var bucket: Array = _buckets[index]
			if bucket.is_empty():
				continue
			var art: Dictionary = _bucket_art(index)
			var texture: Texture2D = art["body"] as Texture2D
			var tip: Vector2 = art["tip"] as Vector2
			for f: Dictionary in bucket:
				if _clock < float(f["drop"]):
					continue
				if _clock < float(f["hit"]):
					_put(_sky, texture, tip, _fall_pos(f))
				else:
					_put(_sky, texture, tip, f["ground"] as Vector2, 1.0 - smoothstep(STICK_LIFE - 0.2, STICK_LIFE, _clock - float(f["hit"])))
	for f: Dictionary in _flights:
		_draw_flight(f)
	for h: Dictionary in _hands:
		_draw_hand(h, false)
	for c: Dictionary in _cages:
		_draw_cage(c, false)
	for bit: Dictionary in _bits:
		if int(bit["kind"]) == 0:
			var k: float = float(bit["age"]) / float(bit["life"])
			_sky.draw_rect(Rect2((bit["pos"] as Vector2).round(), Vector2.ONE * (2 if k < 0.5 else 1)), Color(HOT if bool(bit["white"]) else VoidFeather.VEIN_LIGHT, 1.0 - k))
	for m: Dictionary in _marks:
		_draw_mark(m)


func _draw_flight(f: Dictionary) -> void:
	var t0: float = float(f["t0"])
	var t1: float = float(f["t1"])
	if _clock < t0:
		return
	var src: Vector2 = f["src"] as Vector2
	var dst: Vector2 = f["dst"] as Vector2
	if _clock < t1:
		var s: float = _flight_s(f)
		var height: float = lerpf(float(f["src_h"]), float(f["dst_h"]), s)
		var screen: Vector2 = src.lerp(dst, s) + Vector2(0.0, -height)
		var motion: Vector2 = Vector2(dst.x - src.x, (dst.y - src.y) - (float(f["dst_h"]) - float(f["src_h"])))
		var art: Dictionary = VoidFeather.art(int(f["len"]), int(f["wid"]), motion.angle(), int(f["var"]))
		_put(_sky, art["body"] as Texture2D, art["tip"] as Vector2, screen)
	elif float(f["stay"]) > 0.0 and _clock < t1 + float(f["stay"]):
		var age: float = _clock - t1
		var fade: float = 1.0 - smoothstep(float(f["stay"]) - 0.3, float(f["stay"]), age)
		var size: Vector2i = f["stuck"] as Vector2i
		var stuck: Dictionary = VoidFeather.art(size.x, size.y, PI / 2.0 + float(f["lean"]), int(f["var"]))
		_put(_sky, stuck["body"] as Texture2D, stuck["tip"] as Vector2, dst, fade)


func _draw_mark(m: Dictionary) -> void:
	var node: Node2D = m["node"] as Node2D
	var at: Vector2 = node.global_position + Vector2(0.0, -74.0 + 2.0 * sin(_clock * 5.0))
	var rows: Array[String] = ["..#####..", "#########", "##mmmmm##", "##mmwmm##", "##mmmmm##", "#########", "..#####.."]
	for y: int in rows.size():
		for x: int in 9:
			var ch: String = rows[y][x]
			if ch == ".":
				continue
			var color: Color = VoidFeather.OUTLINE
			if ch == "m":
				color = Color("ff4fd8")
			elif ch == "w":
				color = Color("ffd6f6")
			_sky.draw_rect(Rect2((at + Vector2(x - 4, y - 3)).round(), Vector2.ONE), color)


func _draw_glow() -> void:
	var t0: int = Time.get_ticks_usec()
	_draw_glow_body()
	stat_us += Time.get_ticks_usec() - t0


func _draw_glow_body() -> void:
	if _fall_count > 0:
		for index: int in _buckets.size():
			var bucket: Array = _buckets[index]
			if bucket.is_empty():
				continue
			var art: Dictionary = _bucket_art(index)
			var texture: Texture2D = art["glow"] as Texture2D
			var tip: Vector2 = art["tip"] as Vector2
			for f: Dictionary in bucket:
				if _clock < float(f["drop"]):
					continue
				var alpha: float = 1.0
				if _clock >= float(f["hit"]):
					var age: float = _clock - float(f["hit"])
					alpha = (1.0 - smoothstep(STICK_LIFE - 0.2, STICK_LIFE, age)) * (0.7 + 0.3 * sin(age * 40.0))
				_put(_sky_glow, texture, tip, _fall_pos(f), alpha)
	for f: Dictionary in _flights:
		var t0: float = float(f["t0"])
		var t1: float = float(f["t1"])
		if _clock < t0:
			continue
		var src: Vector2 = f["src"] as Vector2
		var dst: Vector2 = f["dst"] as Vector2
		if _clock < t1:
			var s: float = _flight_s(f)
			var screen: Vector2 = src.lerp(dst, s) + Vector2(0.0, -lerpf(float(f["src_h"]), float(f["dst_h"]), s))
			var motion: Vector2 = Vector2(dst.x - src.x, (dst.y - src.y) - (float(f["dst_h"]) - float(f["src_h"])))
			var art: Dictionary = VoidFeather.art(int(f["len"]), int(f["wid"]), motion.angle(), int(f["var"]))
			_put(_sky_glow, art["glow"] as Texture2D, art["tip"] as Vector2, screen)
		elif float(f["stay"]) > 0.0 and _clock < t1 + float(f["stay"]):
			var age: float = _clock - t1
			var fade: float = 1.0 - smoothstep(float(f["stay"]) - 0.3, float(f["stay"]), age)
			var size: Vector2i = f["stuck"] as Vector2i
			var stuck: Dictionary = VoidFeather.art(size.x, size.y, PI / 2.0 + float(f["lean"]), int(f["var"]))
			_put(_sky_glow, stuck["glow"] as Texture2D, stuck["tip"] as Vector2, dst, fade * (0.75 + 0.25 * sin(age * 18.0)))
	for h: Dictionary in _hands:
		_draw_hand(h, true)
	for c: Dictionary in _cages:
		_draw_cage(c, true)
	for bit: Dictionary in _bits:
		if int(bit["kind"]) == 1:
			var k: float = float(bit["age"]) / float(bit["life"])
			var radius: float = float(bit["radius"]) * (1.0 - pow(1.0 - k, 3.0))
			var steps: int = clampi(int(radius * 1.2), 6, 18)
			for i: int in steps:
				var p: Vector2 = (bit["pos"] as Vector2) + Vector2.from_angle(TAU * float(i) / float(steps)) * Vector2(radius, radius * 0.6)
				_sky_glow.draw_rect(Rect2(p.round(), Vector2.ONE), Color(HOT, (1.0 - k) * 0.85))


# --- the hands of the clock and the cage ---------------------------------------------------------------------------


func _hand_angle(h: Dictionary) -> float:
	var s: float = clampf((_clock - float(h["t0"])) / maxf(float(h["t1"]) - float(h["t0"]), 0.01), 0.0, 1.0)
	return lerpf(float(h["a0"]), float(h["a1"]), s)


func _draw_hand(h: Dictionary, glow: bool) -> void:
	if _clock < float(h["show"]):
		return
	var canvas: Node2D = _sky_glow if glow else _sky
	var grow: float = smoothstep(float(h["show"]), float(h["t0"]), _clock)
	var fade: float = 1.0 - smoothstep(float(h["t1"]), float(h["t1"]) + 0.4, _clock)
	var length: float = float(h["len"]) * grow
	if length < 4.0 or fade <= 0.0:
		return
	var origin: Vector2 = (h["o"] as Vector2) + Vector2(0.0, -4.0)
	var angle: float = _hand_angle(h)
	if _clock >= float(h["t0"]):
		var span: float = float(h["a1"]) - float(h["a0"])
		for k: int in range(4, 0, -1): ## afterimages behind the blade
			var back: float = angle - signf(span) * 0.07 * float(k)
			if (back - float(h["a0"])) * signf(span) < 0.0:
				continue
			var tail: Vector2 = origin + Vector2.from_angle(back) * length
			if glow:
				canvas.draw_line(origin.round(), tail.round(), Color(VoidFeather.VEIN, 0.07 * fade / float(k)), 5.0)
			else:
				canvas.draw_line((origin + Vector2.from_angle(back) * 8.0).round(), tail.round(), Color(VoidFeather.VEIN, 0.16 * fade / float(k)), 1.0)
	var dir: Vector2 = Vector2.from_angle(angle)
	var root: Vector2 = (origin + dir * 8.0).round()
	var tip: Vector2 = (origin + dir * length).round()
	var mid: Vector2 = root.lerp(tip, 0.55).round()
	var pulse: float = 0.7 + 0.3 * sin(_clock * 30.0)
	if glow:
		canvas.draw_line(root, tip, Color(VoidFeather.VEIN, 0.2 * fade), 9.0)
		canvas.draw_line(root, tip, Color(HOT, 0.4 * fade * pulse), 3.0)
		canvas.draw_rect(Rect2(tip + Vector2(-2, -2), Vector2(5, 5)), Color(HOT, 0.8 * fade))
		canvas.draw_rect(Rect2(origin.round() + Vector2(-5, -5), Vector2(11, 11)), Color(VoidFeather.VEIN_LIGHT, 0.3 * fade * pulse))
	else:
		canvas.draw_line(root, tip, Color(VoidFeather.OUTLINE, 0.92 * fade), 7.0)
		canvas.draw_line(root, mid, Color(VoidFeather.RIM, fade), 5.0)
		canvas.draw_line(mid, tip, Color(VoidFeather.RIM, fade), 3.0)
		canvas.draw_line(root, tip, Color(VoidFeather.CORE, fade), 3.0 if grow > 0.6 else 1.0)
		canvas.draw_line(root, tip, Color("fff7ff", fade), 1.0)


func _draw_cage(c: Dictionary, glow: bool) -> void:
	if _clock < float(c["show"]) or _clock > float(c["t1"]) + 0.5:
		return
	var canvas: Node2D = _sky_glow if glow else _sky
	var centre: Vector2 = c["c"] as Vector2
	var t0: float = float(c["t0"])
	var gap_a: float = float(c["ga"])
	var gap_w: float = float(c["gw"])
	if _clock < t0 - 0.3:
		# the warning: a dotted circle where the wall will fall, the gap lit by two bright edges and arrows pointing out of it
		if not glow:
			return
		var urgency: float = smoothstep(float(c["show"]), t0, _clock)
		var r0: float = float(c["r0"])
		for k: int in 90:
			var a: float = TAU * float(k) / 90.0
			if _in_cage_gap(c, a):
				continue
			var p: Vector2 = centre + Vector2.from_angle(a) * r0
			canvas.draw_rect(Rect2(p.round(), Vector2.ONE * (2 if k % 3 == 0 else 1)), Color(1.0, 0.45 + 0.4 * urgency, 0.6 + 0.2 * urgency, 0.45 + 0.4 * urgency))
		for side: float in [-1.0, 1.0]:
			var edge: float = gap_a + side * gap_w * 0.5
			for step: int in 6:
				var q: Vector2 = centre + Vector2.from_angle(edge) * (r0 - 4.0 + float(step) * 3.0)
				canvas.draw_rect(Rect2(q.round(), Vector2(1, 1)), Color(HOT, 0.8))
		var out: Vector2 = Vector2.from_angle(gap_a)
		var side_v: Vector2 = out.orthogonal()
		for ring: int in 3:
			var base: Vector2 = centre + out * (r0 + 8.0 + float(ring) * 7.0 + fposmod(_clock * 14.0, 7.0))
			var alpha: float = (1.0 - float(ring) / 3.0) * (0.5 + 0.4 * urgency)
			for w: int in 5:
				canvas.draw_rect(Rect2((base - out * absf(float(w - 2)) + side_v * float(w - 2)).round(), Vector2.ONE), Color(HOT, alpha))
		return
	var radius: float = _cage_radius(c)
	var drop: float = clampf((_clock - (t0 - 0.3)) / 0.3, 0.0, 1.0)
	var fade: float = 1.0 - smoothstep(float(c["t1"]), float(c["t1"]) + 0.45, _clock)
	var n: int = int(c["n"])
	var span: float = TAU - gap_w
	for i: int in n:
		var a2: float = gap_a + gap_w * 0.5 + span * (float(i) + 0.5) / float(n)
		var pos: Vector2 = centre + Vector2.from_angle(a2) * radius + Vector2(0.0, -90.0 * (1.0 - drop * drop))
		var lean: int = (i % 3) - 1
		var art: Dictionary = VoidFeather.art(VoidFeather.FALL.x, VoidFeather.FALL.y, PI / 2.0 + VoidFeather.LEANS[lean + 1], i % 4)
		if glow:
			_put(canvas, art["glow"] as Texture2D, art["tip"] as Vector2, pos, fade * (0.7 + 0.3 * sin(_clock * 22.0 + float(i))))
		else:
			_put(canvas, art["body"] as Texture2D, art["tip"] as Vector2, pos, fade)
