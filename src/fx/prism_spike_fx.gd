class_name PrismSpikeFx
extends Node2D
## Perk `PRISMENBRUCH` of `Fessel des Ersten Schmelzers` (docs/enemies/boss_aurelith.md):
## Left at `from` whenever a wearer performs a `Schattenschritt`.
## A multi-faceted sun-quartz cathedral cluster erupts out of a carved golden sun-seal collar,
## charges for `delay` (0.6 s), and shatters in a radial burst of spinning sun-quartz & gold shrapnel —
## dealing host-authoritative AoE damage (and launching Aurelith's `Resonanz-Kerne` if triggered beside one!).

const SQUASH: float = 0.72
const BURST_LIFE: float = 0.54
const CHIME_WAV: String = "res://assets/audio/aurelith/core_deflect.wav"
const TEX_SPIKE: Texture2D = preload("res://assets/enemies/aurelith_fx/prism_spike_and_shards.png")
const TEX_SPIKE_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/prism_spike_and_shards_glow.png")
const CELL_W: float = 56.0
const CELL_H: float = 64.0

const COL_GOLD: Color = Color("ffd86b")
const COL_TURQ: Color = Color("78f4e6")
const COL_VIOL: Color = Color("cbaaff")

var _owner_player: Player
var _delay: float = 0.6
var _damage: float = 28.0
var _radius: float = 56.0
var _knockback: float = 150.0
var _age: float = 0.0
var _detonated: bool = false
var _shards: Array[Dictionary] = []
var _motes: Array[Dictionary] = []

var _seal_layer: Node2D
var _glow_layer: Node2D


static func spawn(parent: Node, owner_player: Player, at: Vector2, cfg: Dictionary) -> PrismSpikeFx:
	if parent == null:
		return null
	var node: PrismSpikeFx = PrismSpikeFx.new()
	node.position = at.round()
	node._owner_player = owner_player
	node._delay = float(cfg.get("delay", 0.6))
	node._damage = float(cfg.get("damage", 28.0))
	node._radius = float(cfg.get("radius", 56.0))
	node._knockback = float(cfg.get("knockback", 150.0))
	parent.add_child(node)
	return node


func _ready() -> void:
	z_index = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_seal_layer = Node2D.new()
	_seal_layer.name = "SealLayer"
	_seal_layer.z_index = -1
	_seal_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_seal_layer.material = Unlit.material()
	_seal_layer.draw.connect(_draw_seal)
	add_child(_seal_layer)

	_glow_layer = Node2D.new()
	_glow_layer.name = "GlowLayer"
	_glow_layer.z_index = 1
	_glow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var add_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	add_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = add_mat
	_glow_layer.draw.connect(_draw_glow)
	add_child(_glow_layer)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position)) ^ 0xA9E1
	for i: int in 12:
		var ang: float = TAU * float(i) / 12.0 + rng.randf_range(-0.16, 0.16)
		_shards.append({
			"dir": Vector2.from_angle(ang),
			"reach": rng.randf_range(0.54, 1.04) * _radius,
			"rise": rng.randf_range(14.0, 32.0),
			"rot0": rng.randf_range(0.0, TAU),
			"spin": rng.randf_range(-11.0, 11.0),
			"kind": i % 4,
			"scale": rng.randf_range(0.76, 1.04),
		})
	for m: int in 10:
		_motes.append({
			"ang": TAU * float(m) / 10.0 + rng.randf_range(-0.2, 0.2),
			"rad": rng.randf_range(0.32, 0.92) * _radius,
			"spd": rng.randf_range(16.0, 30.0),
			"phase": rng.randf_range(0.0, 1.0),
			"gold": m % 2 == 0,
		})


func _process(delta: float) -> void:
	_age += delta
	if not _detonated and _age >= _delay:
		_detonate()
	if _detonated and _age >= _delay + BURST_LIFE:
		queue_free()
		return
	queue_redraw()
	_seal_layer.queue_redraw()
	_glow_layer.queue_redraw()


func _detonate() -> void:
	_detonated = true
	if get_parent() != null:
		ShockRing.burst(get_parent(), global_position, _radius, 0.72)
	if DisplayServer.get_name() != "headless" and ResourceLoader.exists(CHIME_WAV):
		var sfx: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sfx.stream = load(CHIME_WAV) as AudioStream
		sfx.volume_db = -7.0
		sfx.pitch_scale = 1.18
		sfx.max_distance = 420.0
		get_parent().add_child(sfx)
		sfx.global_position = global_position
		sfx.finished.connect(sfx.queue_free)
		sfx.play()
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and is_instance_valid(_owner_player):
		var peer_id: int = _owner_player.name.to_int()
		var hit_from: Vector2 = global_position
		for hb: HurtboxComponent in HitScan.circle(_owner_player, global_position + Vector2(0.0, -10.0), _radius, AttackComponent.HURTBOX_MASK):
			hb.take_hit(_damage, hit_from, _knockback, peer_id)


func _current_stage_col(p: float) -> int:
	if p < 0.15:
		return 0
	elif p < 0.36:
		return 1
	elif p < 0.68:
		return 2
	return 3


func _shake_offset(p: float) -> Vector2:
	if p <= 0.74:
		return Vector2.ZERO
	var s: float = 1.0 if int(floorf(_age * 36.0)) % 2 == 0 else -1.0
	return Vector2(s, 0.0)


func _draw_seal() -> void:
	if not _detonated:
		var p: float = clampf(_age / maxf(_delay, 0.05), 0.0, 1.0)
		var pulse: float = 0.70 + 0.30 * sin(_age * 22.0)
		# Soft ground contact shadow beneath the sun-quartz collar
		var sh_pts: PackedVector2Array = PackedVector2Array()
		for si: int in 16:
			var sa: float = TAU * float(si) / 16.0
			sh_pts.append(Vector2(cos(sa) * 18.0, sin(sa) * 8.0 + 1.0).round())
		_seal_layer.draw_colored_polygon(sh_pts, Color(0.09, 0.05, 0.14, 0.34))

		# Outer engraved Sun-Architect astrolabe ring + 8 degree notches
		var steps: int = 36
		var outer_pts: PackedVector2Array = PackedVector2Array()
		var inner_pts: PackedVector2Array = PackedVector2Array()
		var r_in: float = maxf(6.0, _radius - 4.0)
		for i: int in range(steps + 1):
			var a: float = TAU * float(i) / float(steps)
			outer_pts.append(Vector2(cos(a) * _radius, sin(a) * _radius * SQUASH).round())
			inner_pts.append(Vector2(cos(a) * r_in, sin(a) * r_in * SQUASH).round())
		_seal_layer.draw_polyline(outer_pts, Color(COL_GOLD, (0.45 + 0.40 * p) * pulse), 1.5)
		_seal_layer.draw_polyline(inner_pts, Color(COL_TURQ, 0.36 + 0.38 * p), 1.0)

		for ti: int in 8:
			var ta: float = TAU * float(ti) / 8.0 + _age * 0.45
			var p0: Vector2 = Vector2(cos(ta) * (_radius - 6.0), sin(ta) * (_radius - 6.0) * SQUASH).round()
			var p1: Vector2 = Vector2(cos(ta) * (_radius + 2.0), sin(ta) * (_radius + 2.0) * SQUASH).round()
			_seal_layer.draw_line(p0, p1, Color(COL_GOLD if ti % 2 == 0 else COL_TURQ, 0.72), 1.5)

		# Expanding inner sun-star charge ring matching exact detonation progress
		var rx: float = _radius * p
		var ry: float = rx * SQUASH
		if rx >= 4.0:
			var star_pts: PackedVector2Array = PackedVector2Array()
			for k: int in 17:
				var ka: float = -_age * 1.6 + TAU * float(k) / 16.0
				var mod_k: float = 1.0 if k % 2 == 0 else 0.86
				star_pts.append(Vector2(cos(ka) * rx * mod_k, sin(ka) * ry * mod_k).round())
			_seal_layer.draw_polyline(star_pts, Color(Color.WHITE if p > 0.82 else COL_TURQ, 0.48 + 0.36 * p), 1.2)

		# Rising crystalline rune motes inside the seal
		for md: Dictionary in _motes:
			var u: float = fmod(float(md["phase"]) + _age * 1.35, 1.0)
			var ma: float = float(md["ang"]) + _age * 0.9
			var mr: float = float(md["rad"]) * (1.0 - 0.35 * u)
			var mp: Vector2 = Vector2(cos(ma) * mr, sin(ma) * mr * SQUASH - u * float(md["spd"]) * 0.55).round()
			var mc: Color = COL_GOLD if bool(md["gold"]) else COL_TURQ
			_seal_layer.draw_rect(Rect2(mp, Vector2(2.0, 2.0)), Color(mc, sin(u * PI) * 0.85))
	else:
		var bt: float = clampf((_age - _delay) / BURST_LIFE, 0.0, 1.0)
		var fade: float = (1.0 - bt) * 0.65
		if fade > 0.04:
			var pts_b: PackedVector2Array = PackedVector2Array()
			for i: int in 29:
				var a_b: float = TAU * float(i) / 28.0
				pts_b.append(Vector2(cos(a_b) * _radius, sin(a_b) * _radius * SQUASH).round())
			_seal_layer.draw_polyline(pts_b, Color(COL_GOLD, fade), 1.5)


func _draw() -> void:
	if TEX_SPIKE == null:
		return
	if not _detonated:
		var p: float = clampf(_age / maxf(_delay, 0.05), 0.0, 1.0)
		var col_idx: int = _current_stage_col(p)
		var src: Rect2 = Rect2(float(col_idx) * CELL_W, 0.0, CELL_W, CELL_H)
		var dst_pos: Vector2 = (Vector2(-28.0, -52.0) + _shake_offset(p)).round()
		draw_texture_rect_region(TEX_SPIKE, Rect2(dst_pos, Vector2(CELL_W, CELL_H)), src)
	else:
		var bt: float = clampf((_age - _delay) / BURST_LIFE, 0.0, 1.0)
		var out_k: float = 1.0 - pow(1.0 - bt, 3.0)
		var alpha: float = clampf((1.0 - bt) * 1.25, 0.0, 1.0)
		for sh: Dictionary in _shards:
			var d: Vector2 = sh["dir"] as Vector2
			var reach: float = float(sh["reach"]) * out_k
			var lift: float = float(sh["rise"]) * sin(bt * PI)
			var pt: Vector2 = Vector2(d.x * reach, d.y * reach * SQUASH - lift).round()
			var rot: float = float(sh["rot0"]) + float(sh["spin"]) * bt
			var sc: float = float(sh["scale"]) * lerpf(1.0, 0.72, bt)
			var kind: int = int(sh["kind"])
			var src_s: Rect2 = Rect2(float(kind) * CELL_W, CELL_H, CELL_W, CELL_H)
			draw_set_transform(pt, rot, Vector2(sc, sc))
			draw_texture_rect_region(TEX_SPIKE, Rect2(Vector2(-28.0, -32.0), Vector2(CELL_W, CELL_H)), src_s, Color(1.0, 1.0, 1.0, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glow() -> void:
	if TEX_SPIKE_GLOW == null:
		return
	if not _detonated:
		var p: float = clampf(_age / maxf(_delay, 0.05), 0.0, 1.0)
		var col_idx: int = _current_stage_col(p)
		var pulse_a: float = clampf(0.72 + 0.28 * sin(_age * 24.0) + 0.25 * p, 0.0, 1.0)
		var src: Rect2 = Rect2(float(col_idx) * CELL_W, 0.0, CELL_W, CELL_H)
		var dst_pos: Vector2 = (Vector2(-28.0, -52.0) + _shake_offset(p)).round()
		_glow_layer.draw_texture_rect_region(TEX_SPIKE_GLOW, Rect2(dst_pos, Vector2(CELL_W, CELL_H)), src, Color(1.0, 1.0, 1.0, pulse_a))
	else:
		var bt: float = clampf((_age - _delay) / BURST_LIFE, 0.0, 1.0)
		var out_k: float = 1.0 - pow(1.0 - bt, 3.0)
		var alpha: float = clampf(1.0 - bt, 0.0, 1.0)
		for sh: Dictionary in _shards:
			var d: Vector2 = sh["dir"] as Vector2
			var reach: float = float(sh["reach"]) * out_k
			var lift: float = float(sh["rise"]) * sin(bt * PI)
			var pt: Vector2 = Vector2(d.x * reach, d.y * reach * SQUASH - lift).round()
			var rot: float = float(sh["rot0"]) + float(sh["spin"]) * bt
			var sc: float = float(sh["scale"]) * lerpf(1.0, 0.72, bt)
			var kind: int = int(sh["kind"])
			var src_s: Rect2 = Rect2(float(kind) * CELL_W, CELL_H, CELL_W, CELL_H)
			_glow_layer.draw_set_transform(pt, rot, Vector2(sc, sc))
			_glow_layer.draw_texture_rect_region(TEX_SPIKE_GLOW, Rect2(Vector2(-28.0, -32.0), Vector2(CELL_W, CELL_H)), src_s, Color(1.0, 1.0, 1.0, alpha))
		_glow_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
