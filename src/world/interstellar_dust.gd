class_name InterstellarDepthDust
extends Node2D
## Depth Layers 6, 7 & 8 of Caelia's interstellar sanctuary (docs/caelia_interstellar_konzept.md):
##   - Back layer (z = -12, Unlit):
##       * Layer 6a (parallax 0.58) & Layer 6b (parallax 0.78) wrapping crisp tumbling ice/stardust speed cues
##       * Layer 7 (parallax 1.00) reactive local stardust that swirls gently away from Ellie's wake
##       * World-space Boost-Glide / Star-Burst stardust trail motes
##   - Front layer (z = +45, Unlit, OVER Ellie & Caelia):
##       * Layer 8a (parallax 1.22) & Layer 8b (parallax 1.38) sparse foreground depth dust for true 3D immersion
##       * Soft Veil Horizon inward light filaments when a player approaches the outer boundary

const WRAP_W: float = 740.0
const WRAP_H: float = 440.0
const HALF_W: float = WRAP_W * 0.5
const HALF_H: float = WRAP_H * 0.5

const COL_ICE_DIM: Color = Color("6b7aa8")
const COL_ICE_BRIGHT: Color = Color("c9d8f4")
const COL_TEAL_SOFT: Color = Color("54d6d6")
const COL_TEAL_BRIGHT: Color = Color("c4fff8")
const COL_GOLD_SOFT: Color = Color("d8b45c")
const COL_GOLD_BRIGHT: Color = Color("fff0b4")

var _back: _DustCanvas
var _front: _DustCanvas
var _time: float = 0.0
var _cam_local: Vector2 = Vector2(1100.0, 1100.0)
var _horizon_amt: float = 0.0
var _horizon_inward: Vector2 = Vector2.UP

var _l6a: Array[Dictionary] = [] ## parallax 0.58 (behind)
var _l6b: Array[Dictionary] = [] ## parallax 0.78 (behind)
var _l8a: Array[Dictionary] = [] ## parallax 1.22 (foreground over characters)
var _l8b: Array[Dictionary] = [] ## parallax 1.38 (nearest foreground)
var _local_motes: Array[Dictionary] = [] ## Layer 7 reactive world-plane dust
var _trail_motes: Array[Dictionary] = [] ## Boost-glide & impulse stardust trail


func _ready() -> void:
	name = "InterstellarDepthDust"
	_back = _DustCanvas.new()
	_back.name = "BackDust"
	_back.z_index = -12
	_back.material = Unlit.material()
	_back.painter = _draw_back
	add_child(_back)

	_front = _DustCanvas.new()
	_front.name = "FrontDust"
	_front.z_index = 45
	_front.material = Unlit.material()
	_front.painter = _draw_front
	add_child(_front)

	_seed_wrap_layer(_l6a, 46, 101, 0.58, 0.42, 0.72)
	_seed_wrap_layer(_l6b, 32, 217, 0.78, 0.52, 0.88)
	_seed_wrap_layer(_l8a, 16, 331, 1.22, 0.34, 0.62)
	_seed_wrap_layer(_l8b, 9, 449, 1.38, 0.24, 0.46)
	_seed_local_motes(58)


func _seed_wrap_layer(arr: Array[Dictionary], count: int, seed_base: int, factor: float, alpha_min: float, alpha_max: float) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_base * 9973
	for i: int in count:
		var pick: float = rng.randf()
		var col: Color = COL_ICE_BRIGHT if pick < 0.56 else (COL_TEAL_SOFT if pick < 0.80 else (COL_GOLD_SOFT if pick < 0.94 else COL_ICE_DIM))
		arr.append({
			"x": rng.randf_range(0.0, WRAP_W),
			"y": rng.randf_range(0.0, WRAP_H),
			"vx": rng.randf_range(-2.6, 2.6) * factor,
			"vy": rng.randf_range(-1.8, 1.8) * factor,
			"col": col,
			"a0": rng.randf_range(alpha_min, alpha_max),
			"ph": rng.randf_range(0.0, TAU),
			"glint": rng.randf_range(0.6, 1.7),
			"big": rng.randf() > 0.80,
		})


func _seed_local_motes(count: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77123
	for i: int in count:
		var pick: float = rng.randf()
		var col: Color = COL_TEAL_BRIGHT if pick < 0.42 else (COL_GOLD_BRIGHT if pick < 0.72 else COL_ICE_BRIGHT)
		_local_motes.append({
			"pos": Vector2(rng.randf_range(-HALF_W, HALF_W), rng.randf_range(-HALF_H, HALF_H)) + ZeroGRules.room_center(),
			"vel": Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-2.4, 2.4)),
			"col": col,
			"ph": rng.randf_range(0.0, TAU),
			"a": rng.randf_range(0.45, 0.88),
			"big": rng.randf() > 0.78,
		})


## Spawns a short-lived unlit stardust speck behind a boost-gliding or dashing player (local room coords).
func spawn_trail_mote(local_pos: Vector2, drift_vel: Vector2, golden: bool = false) -> void:
	if _trail_motes.size() >= 72:
		_trail_motes.pop_front()
	var col: Color = COL_GOLD_BRIGHT if golden else (COL_TEAL_BRIGHT if randf() < 0.58 else COL_ICE_BRIGHT)
	_trail_motes.append({
		"pos": local_pos,
		"vel": drift_vel,
		"life": randf_range(0.45, 0.95),
		"max_life": 0.95,
		"col": col,
		"big": randf() > 0.72,
	})


func step_dust(delta: float, cam_local: Vector2, players_local: Array[Dictionary], horizon_amt: float, horizon_inward: Vector2) -> void:
	_time += delta
	_cam_local = cam_local
	_horizon_amt = horizon_amt
	_horizon_inward = horizon_inward

	# Update Layer 7 reactive world-plane motes (wrap gently around camera + wake swirl from nearby players)
	for m: Dictionary in _local_motes:
		var pos: Vector2 = m["pos"] as Vector2
		var vel: Vector2 = m["vel"] as Vector2
		var ph: float = float(m["ph"])
		var ambient_v: Vector2 = Vector2(cos(_time * 0.42 + ph) * 2.4, sin(_time * 0.36 + ph * 1.3) * 1.8)

		for pd: Dictionary in players_local:
			var p_pos: Vector2 = pd["pos"] as Vector2
			var p_vel: Vector2 = pd["vel"] as Vector2
			var p_spd: float = p_vel.length()
			if p_spd < 10.0:
				continue
			var d: Vector2 = pos - p_pos
			var dist2: float = d.length_squared()
			if dist2 < 52.0 * 52.0 and dist2 > 2.0:
				var dist: float = sqrt(dist2)
				var w: float = (1.0 - dist / 52.0) * clampf(p_spd / 110.0, 0.2, 1.4)
				var away: Vector2 = d / dist
				var swirl: Vector2 = Vector2(-away.y, away.x) * (1.0 if fmod(ph, 2.0) > 1.0 else -1.0)
				vel += (away * 34.0 + swirl * 26.0 - p_vel.normalized() * 14.0) * w * delta * 6.0

		vel = vel.lerp(ambient_v, 1.0 - exp(-2.2 * delta))
		pos += vel * delta

		# Wrap seamlessly into the camera's local window so the entire 2200x2200 space stays rich
		var rel: Vector2 = pos - cam_local
		if rel.x < -HALF_W:
			pos.x += WRAP_W
		elif rel.x > HALF_W:
			pos.x -= WRAP_W
		if rel.y < -HALF_H:
			pos.y += WRAP_H
		elif rel.y > HALF_H:
			pos.y -= WRAP_H

		m["pos"] = pos
		m["vel"] = vel

	# Update boost-glide / impulse trail motes
	var i: int = _trail_motes.size() - 1
	while i >= 0:
		var tm: Dictionary = _trail_motes[i]
		var left: float = float(tm["life"]) - delta
		if left <= 0.0:
			_trail_motes.remove_at(i)
		else:
			tm["life"] = left
			var tv: Vector2 = (tm["vel"] as Vector2) * exp(-2.4 * delta)
			tm["vel"] = tv
			tm["pos"] = (tm["pos"] as Vector2) + tv * delta
		i -= 1

	_back.queue_redraw()
	_front.queue_redraw()


func _draw_wrap_layer(canvas: CanvasItem, arr: Array[Dictionary], factor: float) -> void:
	# Convert camera-anchored parallax coordinates back into room-local draw positions:
	# screen_pos = base - cam_local * factor  =>  room_pos = cam_local + wrap(base - cam_local * factor)
	var cam_shift: Vector2 = (_cam_local * factor).floor()
	var cam_snap: Vector2 = _cam_local.floor()
	for entry: Dictionary in arr:
		var raw_x: float = float(entry["x"]) + _time * float(entry["vx"]) - cam_shift.x
		var raw_y: float = float(entry["y"]) + _time * float(entry["vy"]) - cam_shift.y
		var sx: float = fposmod(raw_x + HALF_W, WRAP_W) - HALF_W
		var sy: float = fposmod(raw_y + HALF_H, WRAP_H) - HALF_H
		var draw_p: Vector2 = Vector2(floorf(cam_snap.x + sx), floorf(cam_snap.y + sy))
		var ph: float = float(entry["ph"])
		var glint: float = 0.62 + 0.38 * sin(_time * float(entry["glint"]) + ph)
		var base_c: Color = entry["col"] as Color
		var col: Color = Color(base_c.r, base_c.g, base_c.b, float(entry["a0"]) * glint)
		if bool(entry["big"]) and glint > 0.72:
			canvas.draw_rect(Rect2(draw_p, Vector2(2.0, 1.0)), col)
			canvas.draw_rect(Rect2(draw_p + Vector2(0.0, 1.0), Vector2(1.0, 1.0)), Color(col.r, col.g, col.b, col.a * 0.55))
		else:
			canvas.draw_rect(Rect2(draw_p, Vector2(1.0, 1.0)), col)


func _draw_back(canvas: CanvasItem) -> void:
	_draw_wrap_layer(canvas, _l6a, 0.58)
	_draw_wrap_layer(canvas, _l6b, 0.78)

	# Layer 7: Reactive local stardust in Ellie's plane
	for m: Dictionary in _local_motes:
		var pos: Vector2 = (m["pos"] as Vector2).round()
		var ph: float = float(m["ph"])
		var pulse: float = 0.55 + 0.45 * sin(_time * 1.45 + ph)
		var bc: Color = m["col"] as Color
		var c: Color = Color(bc.r, bc.g, bc.b, float(m["a"]) * pulse)
		if bool(m["big"]):
			canvas.draw_rect(Rect2(pos, Vector2(1.0, 1.0)), c)
			var dim: Color = Color(c.r, c.g, c.b, c.a * 0.42)
			canvas.draw_rect(Rect2(pos + Vector2(-1.0, 0.0), Vector2(1.0, 1.0)), dim)
			canvas.draw_rect(Rect2(pos + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), dim)
		else:
			canvas.draw_rect(Rect2(pos, Vector2(1.0, 1.0)), c)

	# Boost-glide / Star-burst stardust trail
	for tm: Dictionary in _trail_motes:
		var pos: Vector2 = (tm["pos"] as Vector2).round()
		var ratio: float = clampf(float(tm["life"]) / float(tm["max_life"]), 0.0, 1.0)
		var bc: Color = tm["col"] as Color
		var c: Color = Color(bc.r, bc.g, bc.b, ratio * 0.90)
		canvas.draw_rect(Rect2(pos, Vector2(1.0, 1.0)), c)
		if bool(tm["big"]) and ratio > 0.45:
			var halo: Color = Color(bc.r, bc.g, bc.b, ratio * 0.40)
			canvas.draw_rect(Rect2(pos + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), halo)
			canvas.draw_rect(Rect2(pos + Vector2(0.0, 1.0), Vector2(1.0, 1.0)), halo)


func _draw_front(canvas: CanvasItem) -> void:
	# Layer 8a & 8b: Delicate sparse foreground depth dust gliding OVER Ellie & Caelia
	_draw_wrap_layer(canvas, _l8a, 1.22)
	_draw_wrap_layer(canvas, _l8b, 1.38)

	# Soft Veil Horizon: gentle inward-flowing turquoise-gold light filaments when approaching outer space rim
	if _horizon_amt > 0.03:
		var dir: Vector2 = _horizon_inward.normalized() if _horizon_inward.length_squared() > 0.001 else Vector2.UP
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var count: int = int(lerpf(6.0, 22.0, _horizon_amt))
		for k: int in count:
			var seed_v: float = float(k) * 1.6180339
			var phase: float = fposmod(_time * (0.45 + fmod(seed_v, 0.35)) + seed_v * 3.1, 1.0)
			var lateral: float = (fmod(seed_v * 113.7, 1.0) - 0.5) * 440.0
			var along: float = lerpf(-210.0, 190.0, phase)
			var origin: Vector2 = (_cam_local + dir * along + perp * lateral).round()
			var fade: float = sin(phase * PI) * _horizon_amt
			var tint: Color = COL_TEAL_BRIGHT if k % 3 != 0 else COL_GOLD_BRIGHT
			var seg_len: int = 3 + (k % 4)
			for s: int in seg_len:
				var sp: Vector2 = (origin + dir * float(s * 2)).round()
				var a: float = fade * (0.55 - 0.10 * float(s))
				if a > 0.04:
					canvas.draw_rect(Rect2(sp, Vector2(1.0, 1.0)), Color(tint.r, tint.g, tint.b, a))


class _DustCanvas:
	extends Node2D
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)
