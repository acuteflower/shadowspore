class_name PrismSeal
extends WorldTrial
## Sonnenquarz-Öde trial of the Wächterin (`prism_seal` in data/puzzles.json):
## A sunken central QuartzSeal linked by 3 stone LightConduits to 3 surrounding ResonanceObelisks (N, SW, SE).
## Stepping onto each obelisk's rune pad, casting a spell near a conduit, or catching an Arcane Quartz Storm bolt
## sends a turquoise-gold pulse inward and holds that obelisk resonant for `hold_time` seconds.
## When all 3 obelisks resonate together, the central seal locks open and raises a buried LootChest from the sand!

const MASONRY_TEX: Texture2D = preload("res://assets/props/ruin_sandstone.png")
const MASONRY_GLOW: Texture2D = preload("res://assets/props/ruin_sandstone_glow.png")

const OBELISK_OFFSETS: Array[Vector2] = [
	Vector2(0.0, -46.0),
	Vector2(-56.0, 0.0),
	Vector2(56.0, 0.0),
]

const CONDUIT_RUNS: Array[Array] = [
	[Vector2(0.0, -42.0), Vector2(0.0, -22.0)],
	[Vector2(-52.0, 0.0), Vector2(-22.0, 0.0)],
	[Vector2(52.0, 0.0), Vector2(22.0, 0.0)],
]

const CORNER_OFFSETS: Array[Vector2] = [
	Vector2(-64.0, -44.0),
	Vector2(64.0, -44.0),
	Vector2(-64.0, 38.0),
	Vector2(64.0, 38.0),
]

var _hold_time: float = 16.0
var _pad_radius: float = 26.0
var _timers: Array[float] = [0.0, 0.0, 0.0]
var _done: bool = false
var _seal_sprite: Sprite2D
var _seal_glow: Sprite2D
var _arch: DesertRuins.QuartzArch
var _conduits: Array[DesertRuins.LightConduit] = []
var _obelisks: Array[DesertRuins.ResonanceObelisk] = []
var _corner_glows: Array[Sprite2D] = []
var _ring_fx: Node2D
var _burst_t: float = -1.0


func setup(data: Dictionary, tuning: Dictionary) -> void:
	super.setup(data, tuning)
	var tile: Array = data.get("tile", [0, 0]) as Array
	position = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8.0, 8.0)
	_hold_time = float(tuning.get("hold_time", 16.0))
	_pad_radius = float(tuning.get("pad_radius", 26.0))


func start_position() -> Vector2:
	return global_position + Vector2(0.0, 62.0)


func end_position() -> Vector2:
	return global_position


func reward_rise() -> bool:
	return true


func _ready() -> void:
	y_sort_enabled = true
	add_to_group("night_lights")
	add_to_group("desert_spell_listeners")
	add_to_group("desert_arcane_listeners")

	var ground_layer: Node2D = Node2D.new()
	ground_layer.name = "SealGround"
	ground_layer.z_index = -8
	add_child(ground_layer)

	var seal_var: int = int(info.get("variant", 1)) % 2
	_seal_sprite = Sprite2D.new()
	_seal_sprite.texture = DesertRuins.SEAL_TEX
	_seal_sprite.hframes = 2
	_seal_sprite.frame = seal_var
	ground_layer.add_child(_seal_sprite)

	_seal_glow = Sprite2D.new()
	_seal_glow.texture = DesertRuins.SEAL_GLOW
	_seal_glow.hframes = 2
	_seal_glow.frame = seal_var
	_seal_glow.material = Unlit.material()
	_seal_sprite.add_child(_seal_glow)

	_ring_fx = PrismSealDraw.new()
	(_ring_fx as PrismSealDraw).trial = self
	_ring_fx.material = Unlit.material()
	_ring_fx.z_index = 1
	ground_layer.add_child(_ring_fx)

	# Northern sanctuary gate (QuartzArch) + connecting stone channel into the North Obelisk
	var entry_cond: DesertRuins.LightConduit = DesertRuins.LightConduit.new()
	entry_cond.setup(Vector2(0.0, -72.0), Vector2(0.0, -50.0), false)
	ground_layer.add_child(entry_cond)

	_arch = DesertRuins.QuartzArch.new()
	_arch.setup(Vector2(0.0, -76.0), seal_var % 3)
	_arch.linked_conduit = entry_cond
	add_child(_arch)

	for i: int in 3:
		var ob_local: Vector2 = OBELISK_OFFSETS[i]
		var run_pair: Array = CONDUIT_RUNS[i]
		var cond: DesertRuins.LightConduit = DesertRuins.LightConduit.new()
		cond.setup(run_pair[0] as Vector2, run_pair[1] as Vector2, true)
		ground_layer.add_child(cond)
		_conduits.append(cond)

		var ob: DesertRuins.ResonanceObelisk = DesertRuins.ResonanceObelisk.new()
		ob.setup(ob_local, i % 2)
		add_child(ob)
		_obelisks.append(ob)

	if not _conduits.is_empty():
		entry_cond.chained_conduits = [_conduits[0]]

	# Four framing ancient sandstone colonnade piers around the sanctuary courtyard
	for ci: int in CORNER_OFFSETS.size():
		var pier: Node2D = Node2D.new()
		pier.position = CORNER_OFFSETS[ci]
		var pspr: Sprite2D = Sprite2D.new()
		pspr.texture = MASONRY_TEX
		pspr.hframes = 4
		pspr.vframes = 4
		pspr.frame = (ci + seal_var) % 4
		pspr.offset = Vector2(0.0, -16.0)
		pier.add_child(pspr)
		var pglow: Sprite2D = Sprite2D.new()
		pglow.texture = MASONRY_GLOW
		pglow.hframes = 4
		pglow.vframes = 4
		pglow.frame = pspr.frame
		pglow.offset = Vector2(0.0, -16.0)
		pglow.material = Unlit.material()
		pier.add_child(pglow)
		_corner_glows.append(pglow)
		var pbody: StaticBody2D = StaticBody2D.new()
		pbody.collision_layer = 1
		pbody.collision_mask = 0
		var pshape: CollisionShape2D = CollisionShape2D.new()
		var prect: RectangleShape2D = RectangleShape2D.new()
		prect.size = Vector2(22.0, 7.0)
		pshape.shape = prect
		pshape.position = Vector2(0.0, -3.5)
		pbody.add_child(pshape)
		pier.add_child(pbody)
		add_child(pier)

	set_night(TimeManager.night_amount())


func set_night(amount: float) -> void:
	var lit_count: int = lit_obelisks()
	var frac: float = 1.0 if _done else float(lit_count) / 3.0
	if _seal_glow != null:
		_seal_glow.modulate.a = clampf(lerpf(0.22, 0.58, amount) + frac * 0.65, 0.0, 1.0)
	var corner_a: float = clampf(lerpf(0.16, 0.52, amount) + frac * 0.42, 0.0, 1.0)
	for cg: Sprite2D in _corner_glows:
		if is_instance_valid(cg):
			cg.modulate.a = corner_a


func lit_obelisks() -> int:
	if _done:
		return 3
	var n: int = 0
	for t: float in _timers:
		if t > 0.0:
			n += 1
	return n


func activate_pillar(idx: int) -> void:
	if _done or idx < 0 or idx >= 3:
		return
	var was_cold: bool = _timers[idx] <= 0.2
	_timers[idx] = _hold_time
	if idx < _obelisks.size() and is_instance_valid(_obelisks[idx]):
		_obelisks[idx].energize(_hold_time)
	if idx < _conduits.size() and is_instance_valid(_conduits[idx]) and was_cold:
		_conduits[idx].trigger_pulse()
	set_night(TimeManager.night_amount())
	if _ring_fx != null:
		_ring_fx.queue_redraw()
	if multiplayer.is_server():
		_sync_peers()
		if _timers[0] > 0.0 and _timers[1] > 0.0 and _timers[2] > 0.0:
			_complete_host()


func _complete_host() -> void:
	if _done or not multiplayer.is_server():
		return
	_done = true
	if multiplayer.get_peers().is_empty():
		_rpc_locked()
	else:
		_rpc_locked.rpc()
	solved.emit(id, end_position())


@rpc("authority", "call_local", "reliable")
func _rpc_locked() -> void:
	_done = true
	_timers = [999.0, 999.0, 999.0]
	_burst_t = 0.0
	for ob: DesertRuins.ResonanceObelisk in _obelisks:
		if is_instance_valid(ob):
			ob.energize(30.0)
			ob.emit_prism_ring()
	Sfx.at(self, "seal_awake", global_position, -1.5, 0.03)
	set_night(TimeManager.night_amount())
	if _ring_fx != null:
		_ring_fx.queue_redraw()


func _sync_peers() -> void:
	if not multiplayer.get_peers().is_empty():
		_rpc_timers.rpc(_timers[0], _timers[1], _timers[2])


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_timers(t0: float, t1: float, t2: float) -> void:
	if _done:
		return
	_timers[0] = t0
	_timers[1] = t1
	_timers[2] = t2
	set_night(TimeManager.night_amount())
	if _ring_fx != null:
		_ring_fx.queue_redraw()


func set_solved_instant() -> void:
	_done = true
	_timers = [999.0, 999.0, 999.0]
	for ob: DesertRuins.ResonanceObelisk in _obelisks:
		if is_instance_valid(ob):
			ob.energize(999.0)
	set_night(TimeManager.night_amount())
	if _ring_fx != null:
		_ring_fx.queue_redraw()


func reset_trial() -> void:
	_done = false
	_timers = [0.0, 0.0, 0.0]
	_burst_t = -1.0
	for ob: DesertRuins.ResonanceObelisk in _obelisks:
		if is_instance_valid(ob):
			ob.energized_timer = 0.0
	set_night(TimeManager.night_amount())
	if _ring_fx != null:
		_ring_fx.queue_redraw()


func on_spell_cast(caster_pos: Vector2, target_pos: Vector2, _spell_id: String) -> void:
	if _done or not multiplayer.is_server():
		return
	for i: int in 3:
		var ob_world: Vector2 = global_position + OBELISK_OFFSETS[i]
		if ob_world.distance_to(caster_pos) <= 56.0 or ob_world.distance_to(target_pos) <= 56.0:
			activate_pillar(i)


func on_arcane_lightning(strike_pos: Vector2, _info: Dictionary = {}) -> void:
	if _done or not multiplayer.is_server():
		return
	for i: int in 3:
		var ob_world: Vector2 = global_position + OBELISK_OFFSETS[i]
		if ob_world.distance_to(strike_pos) <= 120.0:
			activate_pillar(i)


func _process(delta: float) -> void:
	if _burst_t >= 0.0:
		_burst_t += delta * 1.25
		if _burst_t >= 1.0:
			_burst_t = -1.0
		if _ring_fx != null:
			_ring_fx.queue_redraw()
	if _done:
		return
	var changed: bool = false
	for i: int in 3:
		if _timers[i] > 0.0:
			_timers[i] = maxf(0.0, _timers[i] - delta)
			changed = true
	if multiplayer.is_server():
		for entry_v: Variant in WorldTrial.living_players():
			var p_pos: Vector2 = (entry_v as Dictionary).pos as Vector2
			for i: int in 3:
				var pad_world: Vector2 = global_position + OBELISK_OFFSETS[i] + Vector2(0.0, 8.0)
				if p_pos.distance_to(pad_world) <= _pad_radius and _timers[i] < _hold_time - 0.35:
					activate_pillar(i)
	if changed:
		set_night(TimeManager.night_amount())
		if _ring_fx != null:
			_ring_fx.queue_redraw()


class PrismSealDraw extends Node2D:
	var trial: PrismSeal

	func _draw() -> void:
		if trial == null:
			return
		for i: int in 3:
			var pad: Vector2 = PrismSeal.OBELISK_OFFSETS[i] + Vector2(0.0, 8.0)
			var active: bool = trial._done or trial._timers[i] > 0.0
			var col: Color = Color(0.47, 0.96, 0.90, 0.72) if active else Color(0.88, 0.78, 0.56, 0.28)
			_ellipse(pad, 15.0, 9.0, col, 1.6)
			if active:
				draw_circle(pad, 2.5, Color(1.0, 0.92, 0.58, 0.9))
		if trial._burst_t >= 0.0:
			var t: float = clampf(trial._burst_t, 0.0, 1.0)
			var rx: float = lerpf(10.0, 76.0, t)
			_ellipse(Vector2.ZERO, rx, rx * 0.64, Color(0.47, 0.96, 0.90, (1.0 - t) * 0.95), 2.4)
			_ellipse(Vector2.ZERO, maxf(rx - 6.0, 2.0), maxf((rx - 6.0) * 0.64, 1.5), Color(1.0, 0.88, 0.48, (1.0 - t) * 0.8), 1.6)

	func _ellipse(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		for k: int in 25:
			var ang: float = TAU * float(k) / 24.0
			pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
		draw_polyline(pts, col, width)
