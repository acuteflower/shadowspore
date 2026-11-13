class_name RootWeave
extends WorldTrial
## The root weave (Wurzelgeflecht, docs/raetsel_konzept.md 6a). A cube of the Wächterin's stone sits half swallowed by the earth and hums teal (the
## heart). E "LÖSCHEN" puts it out: roots tear out of the ground and the first cubes rise. Touching a cube ("BERÜHREN", Ellie's palms) switches it
## and sends a pulse down every root that leads away from it, which switches the cube at the other end. Seeds grow more roots and cubes the first
## time they are lit (and what grew stays), thorns cannot be touched, one-way roots carry a pulse one way only. Goal "all": every cube lit at once;
## goal "path": a chain of lit cubes carries the heart's light to the crown. Solved, a golden wave runs through the weave, the heart rights itself
## and roots lift the chest out of the earth. "ZURÜCKZIEHEN" at the heart (or nobody near for a minute) takes everything back. Failing costs nothing.
## Rules: `WeaveRules` (pure, also tools/check_root_weave.py). Host-authoritative: the host checks a press and sends it (`_rpc_press`); every peer
## plays it on its own copy of the state, which stays the same because the rules are deterministic. A joining peer gets the state.

const SOUND_DIR: String = "res://assets/audio/weave/"
const BARK: Array[Color] = [Color("1a1322"), Color("34283c"), Color("55435a"), Color("85697a")]
const EARTH: Array[Color] = [Color("1c1410"), Color("38281e"), Color("584030"), Color("7c6048")]
const SAP_DARK: Color = Color("181129")
const SAP_LIT: Color = Color("5fd6c8")
const SAP_FLOW: Color = Color("aaf8ee")
const SAP_GOLD: Color = Color("ffb347")
const THORN: Color = Color("0c0814")
const THORN_TIP: Color = Color("6a4ab0")

var rules: WeaveRules
var cfg: Dictionary = {}
var active: bool = false ## the heart is out: the weave stands
var lit: int = 0
var pres: int = 0
var done: bool = false

var _heart_pos: Vector2 = Vector2.ZERO
var _cubes: Array[WeaveCube] = [] ## by bit
var _roots: Array = [] ## {a, b, one, pts: PackedVector2Array}
var _shown_lit: int = 0 ## what the cubes show (the logic is ahead while pulses run)
var _rise_t: Array[float] = [] ## by bit: when it starts to rise (INF = not)
var _root_t: Array[float] = [] ## by bit: when roots start to grow towards it
var _sinking: float = -1.0 ## the withdraw's clock (-1 = not)
var _events: Array = [] ## [time, Callable], played in order
var _sparks: Array = [] ## {root, from_a, t0}
var _clods: Array = [] ## [pos, vel, age, life, colour]
var _gold_t: float = INF
var _focus_bit: int = -1
var _time: float = 0.0
var _lock: float = 0.0 ## host: no press while a pulse still runs
var _away: float = 0.0 ## host: seconds without anybody near
var _root_node: Node2D
var _sap_node: Node2D
var _fx_node: Node2D
var _runes: Dictionary = {}
var _rune_order: Array = []


func setup(entry: Dictionary, tuning: Dictionary) -> void:
	super.setup(entry, tuning)
	cfg = tuning
	var t: Array = entry.get("tile", [0, 0]) as Array
	_heart_pos = Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8, 8)
	position = _heart_pos
	rules = WeaveRules.new(entry)
	var rune_table: Dictionary = DataRegistry.table("puzzle_runes")
	_runes = rune_table.get("runes", {}) as Dictionary
	_rune_order = rune_table.get("order", []) as Array


func _num(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


func _ready() -> void:
	y_sort_enabled = true
	_root_node = Node2D.new()
	_root_node.z_index = -8
	_root_node.draw.connect(_draw_roots)
	add_child(_root_node)
	_sap_node = Node2D.new()
	_sap_node.z_index = -7
	_sap_node.material = Unlit.material()
	_sap_node.draw.connect(_draw_sap)
	add_child(_sap_node)
	_fx_node = Node2D.new()
	_fx_node.z_index = 3
	_fx_node.draw.connect(_draw_fx)
	add_child(_fx_node)
	var cubes: Dictionary = info.get("cubes", {}) as Dictionary
	for i: int in rules.size():
		var cid: String = rules.ids[i]
		var data: Dictionary = cubes[cid] as Dictionary
		var at: Array = data.get("at", [0, 0]) as Array
		var cube: WeaveCube = WeaveCube.new()
		cube.name = "Cube_" + cid
		cube.weave = self
		cube.bit = i
		cube.kind = rules.kinds[i]
		cube.variant = int(data.get("variant", absi(hash(id + cid)) % 3))
		var rune_name: String = String(data.get("rune", _rune_order[absi(hash(cid + id)) % _rune_order.size()] if not _rune_order.is_empty() else ""))
		cube.rune = _runes.get(rune_name, []) as Array
		cube.set_meta("tone", maxi(0, _rune_order.find(rune_name)))
		cube.position = Vector2(float(at[0]), float(at[1])) * 16.0
		cube.rise = 1.0 if cube.big() else 0.0
		cube.shown = 0 if cube.kind == "heart" else (3 if cube.kind == "crown" else 0)
		if cube.kind == "crown":
			cube.rise = 0.0
		add_child(cube)
		_cubes.append(cube)
		_rise_t.append(INF)
		_root_t.append(INF)
	for r: Variant in info.get("roots", []) as Array:
		var ra: Array = r as Array
		var a: int = rules.bit_of(String(ra[0]))
		var b: int = rules.bit_of(String(ra[1]))
		if a < 0 or b < 0:
			continue
		_roots.append({"a": a, "b": b, "one": ra.size() > 2 and bool(ra[2]), "pts": _curve(a, b)})
	_reset_look()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void: _rpc_state.rpc_id(peer, active, lit, pres, done))


## A root's path: a gentle bow between the two cubes, sampled every pixel (every peer the same).
func _curve(a: int, b: int) -> PackedVector2Array:
	var pa: Vector2 = _cubes[a].position + Vector2(0, -2)
	var pb: Vector2 = _cubes[b].position + Vector2(0, -2)
	var d: Vector2 = pb - pa
	var n: Vector2 = Vector2(-d.y, d.x).normalized()
	var bow: float = float((absi(hash(rules.ids[a] + rules.ids[b] + id)) % 100) - 50) / 50.0 * d.length() * 0.16
	var ctrl: Vector2 = (pa + pb) * 0.5 + n * bow
	var steps: int = maxi(2, int(d.length()))
	var out: PackedVector2Array = []
	var last: Vector2 = Vector2.INF
	for k: int in steps + 1:
		var u: float = float(k) / float(steps)
		var p: Vector2 = (pa.lerp(ctrl, u)).lerp(ctrl.lerp(pb, u), u).round()
		if p != last:
			out.append(p)
			last = p
	return out


func start_position() -> Vector2:
	return _heart_pos + Vector2(0, 46)


func end_position() -> Vector2:
	if rules.crown >= 0:
		return global_position + _cubes[rules.crown].position + Vector2(36, 4) ## beside the crown, clear of its roots
	return _heart_pos + Vector2(0, 32)


func reward_rise() -> bool:
	return true


# ------------------------------------------------------------------ what E does
func cube_prompt(bit: int) -> String:
	var cube: WeaveCube = _cubes[bit]
	if done:
		return ""
	if cube.kind == "heart":
		return "ZURÜCKZIEHEN" if active else "LÖSCHEN"
	if not active or cube.kind == "crown" or cube.rise < 1.0 or not WeaveRules.has(pres, bit):
		return ""
	return "BERÜHREN"


func cube_hint(bit: int) -> String:
	var cube: WeaveCube = _cubes[bit]
	if cube.kind == "thorn" and active and not done:
		return "DORNEN"
	if _busy() and cube.kind != "heart" and active and not done:
		return "DAS LICHT FLIESST"
	return ""


func _busy() -> bool:
	return not _events.is_empty() or _sinking >= 0.0


func cube_used(bit: int, player: Player) -> void:
	var cube: WeaveCube = _cubes[bit]
	if player.is_busy() or done:
		return
	if cube.kind == "thorn":
		_sound("refuse", -6.0, global_position + cube.position)
		_shake_cube(bit, 0.4)
		return
	if cube.kind != "heart" and _busy():
		return
	var dir: Vector2 = (global_position + cube.position - player.global_position).normalized()
	player.begin_touch(dir, func() -> void:
		if cube.kind == "heart":
			_ask("withdraw" if active else "start", -1)
		else:
			_ask("press", bit)
		player.release_touch())


## The local player's focus: the cubes a touch would switch tremble and their roots shimmer.
func focus(bit: int, on: bool) -> void:
	if on:
		_focus_bit = bit
	elif _focus_bit == bit:
		_focus_bit = -1


# ------------------------------------------------------------------ host
func _ask(what: String, bit: int) -> void:
	if multiplayer.is_server():
		_host_ask(what, bit)
	else:
		_rpc_ask.rpc_id(1, what, bit)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask(what: String, bit: int) -> void:
	if multiplayer.is_server():
		_host_ask(what, bit)


func _host_ask(what: String, bit: int) -> void:
	if done:
		return
	match what:
		"start":
			if not active:
				_send("start", -1)
		"withdraw":
			if active and _sinking < 0.0:
				_send("withdraw", -1)
		"press":
			if not active or _lock > 0.0 or bit < 0 or bit >= rules.size() or not rules.touchable(bit) or not WeaveRules.has(pres, bit):
				return
			_send("press", bit)


func _send(what: String, bit: int) -> void:
	if multiplayer.get_peers().is_empty():
		_rpc_do(what, bit)
	else:
		_rpc_do.rpc(what, bit)


@rpc("authority", "call_local", "reliable")
func _rpc_do(what: String, bit: int) -> void:
	match what:
		"start":
			_begin()
		"withdraw":
			_withdraw()
		"press":
			_press(bit)


## A joining peer: the state as it stands, shown at once.
@rpc("authority", "reliable")
func _rpc_state(on: bool, l: int, p: int, solved_: bool) -> void:
	_apply_state(on, l, p, solved_)


func _process(delta: float) -> void:
	_time += delta
	while not _events.is_empty() and float((_events[0] as Array)[0]) <= _time:
		var ev: Array = _events.pop_front() as Array
		(ev[1] as Callable).call()
	var moving: bool = not _events.is_empty() or not _sparks.is_empty() or not _clods.is_empty() or _sinking >= 0.0 or _time < _gold_t + 3.0
	for i: int in _cubes.size():
		var cube: WeaveCube = _cubes[i]
		var target: float = cube.rise
		if _rise_t[i] < INF:
			var u: float = clampf((_time - _rise_t[i]) / _num("rise_time", 0.85), 0.0, 1.0)
			target = 1.0 - pow(1.0 - u, 3.0) + sin(u * PI) * 0.06
			if u >= 1.0:
				target = 1.0
				_rise_t[i] = INF
		if _sinking >= 0.0 and not (cube.kind == "heart"):
			target = minf(target, 1.0 - clampf(_sinking / 0.8, 0.0, 1.0))
		var jit: Vector2 = Vector2.ZERO
		if _focus_bit >= 0 and active and not done and _events.is_empty() and rules.touchable(_focus_bit) and rules.reach(_focus_bit, pres).has(i):
			jit = Vector2(float(int(_time * 9.0 + i) % 2), 0.0)
		if cube.has_meta("shake_until") and _time < float(cube.get_meta("shake_until")):
			jit = Vector2(float(int(_time * 30.0) % 3 - 1), 0.0)
		if not is_equal_approx(target, cube.rise) or jit != cube.jitter:
			cube.rise = target
			cube.jitter = jit
			cube.refresh()
	if _sinking >= 0.0:
		_sinking += delta
		if _sinking >= 1.1:
			_finish_withdraw()
	for s: Dictionary in _sparks.duplicate():
		if _time - float(s["t0"]) > _num("pulse_time", 0.28):
			_sparks.erase(s)
	for c: Array in _clods:
		c[2] = float(c[2]) + delta
		c[0] = (c[0] as Vector2) + (c[1] as Vector2) * delta
		c[1] = (c[1] as Vector2) + Vector2(0, 260.0) * delta
	_clods = _clods.filter(func(c: Array) -> bool: return float(c[2]) < float(c[3]))
	_root_node.queue_redraw()
	_sap_node.queue_redraw()
	if moving or not _clods.is_empty():
		_fx_node.queue_redraw()
	if multiplayer.is_server():
		_lock = maxf(0.0, _lock - delta)
		if active and not done:
			var near: bool = false
			for p: Dictionary in WorldTrial.living_players():
				if (p["pos"] as Vector2).distance_to(_heart_pos) < _num("leave_radius", 420.0):
					near = true
			_away = 0.0 if near else _away + delta
			if _away > _num("leave_time", 60.0) and _sinking < 0.0:
				_away = 0.0
				_send("withdraw", -1)


# ------------------------------------------------------------------ the moves (every peer)
func _begin() -> void:
	if active:
		return
	active = true
	var s: PackedInt64Array = rules.start()
	lit = s[0]
	pres = s[1]
	_shown_lit = 0
	_cubes[rules.heart].shown = 1
	_cubes[rules.heart].refresh()
	_shake_cube(rules.heart, 0.5)
	_sound("out", -2.0, _heart_pos)
	_burst(_heart_pos + Vector2(0, -6), 14, 1.4)
	_root_t[rules.heart] = _time
	var t0: float = _time + 0.35
	var order: Array[int] = []
	for i: int in rules.size():
		if WeaveRules.has(pres, i) and i != rules.heart and rules.born[i] < 0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _cubes[a].position.length() < _cubes[b].position.length())
	var k: int = 0
	for i: int in order:
		_schedule_rise(i, t0 + k * 0.11)
		k += 1
	var last: float = t0 + k * 0.11 + 0.9
	for i: int in rules.size(): ## seeds lit from the start grow at once (after their parent rose)
		if WeaveRules.has(pres, i) and rules.born[i] >= 0:
			_schedule_rise(i, last)
			last += 0.08
	_events.append([last + 0.1, func() -> void: _shown_lit = lit & pres])
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if multiplayer.is_server():
		_lock = last - _time + 0.2


func _schedule_rise(i: int, at: float) -> void:
	_root_t[i] = at - 0.35
	_events.append([at, func() -> void:
		_rise_t[i] = _time
		_sound("rise", -9.0, global_position + _cubes[i].position)
		_burst(global_position + _cubes[i].position, 10, 1.0)
		_nudge(global_position + _cubes[i].position, 1.2)])
	_events.append([at + 0.6, func() -> void: _set_lit_shown(i, WeaveRules.has(lit, i))])


func _press(bit: int) -> void:
	if not active or done:
		return
	var reach: Array[int] = rules.reach(bit, pres)
	var risen: Array = []
	var after: PackedInt64Array = rules.press(lit, pres, bit, risen)
	lit = after[0]
	pres = after[1]
	var pulse: float = _num("pulse_time", 0.28)
	_toggle_shown(bit)
	_sound("tone_%d" % int(_cubes[bit].get_meta("tone", 0)), -4.0, global_position + _cubes[bit].position)
	_shake_cube(bit, 0.25)
	var sent: bool = false
	for j: int in reach:
		if j == bit:
			continue
		for r: int in _roots.size():
			var root: Dictionary = _roots[r] as Dictionary
			if (int(root["a"]) == bit and int(root["b"]) == j) or (int(root["b"]) == bit and int(root["a"]) == j and not bool(root["one"])):
				_sparks.append({"root": r, "from_a": int(root["a"]) == bit, "t0": _time})
				break
		sent = true
		_events.append([_time + pulse, func() -> void:
			_toggle_shown(j)
			_shake_cube(j, 0.2)
			_sound("tone_%d" % int(_cubes[j].get_meta("tone", 0)), -12.0, global_position + _cubes[j].position)])
	if sent:
		_sound("pulse", -10.0, global_position + _cubes[bit].position)
	var t: float = _time + pulse + 0.12
	var seeds: Dictionary = {}
	for c: Variant in risen:
		seeds[rules.born[int(c)]] = true
	for s: Variant in seeds:
		var sb: int = int(s)
		_events.append([t, func() -> void:
			_cubes[sb].opened = true
			_cubes[sb].refresh()
			_sound("bloom", -6.0, global_position + _cubes[sb].position)
			_burst(global_position + _cubes[sb].position + Vector2(0, -16), 8, 0.6, true)])
	var k: int = 0
	for c: Variant in risen:
		_schedule_rise(int(c), t + 0.45 + k * 0.14)
		k += 1
	var end: float = t + (0.45 + k * 0.14 + 0.9 if k > 0 else 0.0)
	if rules.solved(lit, pres):
		done = true
		_events.append([end + 0.25, _play_solved])
		if multiplayer.is_server():
			_events.append([end + 2.4, func() -> void: solved.emit(id, end_position())])
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if multiplayer.is_server():
		_lock = end - _time + 0.05


func _toggle_shown(i: int) -> void:
	_set_lit_shown(i, not WeaveRules.has(_shown_lit, i))


func _set_lit_shown(i: int, on: bool) -> void:
	if on:
		_shown_lit |= 1 << i
	else:
		_shown_lit &= ~(1 << i)
	var cube: WeaveCube = _cubes[i]
	if cube.kind != "heart" and cube.kind != "crown" and not done:
		cube.shown = 1 if on else 0
		cube.refresh()


func _play_solved() -> void:
	_gold_t = _time
	_sound("solved", -1.0, _heart_pos)
	var heart: WeaveCube = _cubes[rules.heart]
	heart.shown = 2
	heart.refresh()
	_burst(_heart_pos + Vector2(0, -10), 20, 1.6, true)
	_nudge(_heart_pos, 2.0)
	for i: int in _cubes.size():
		var cube: WeaveCube = _cubes[i]
		if cube.kind == "heart":
			continue
		var delay: float = cube.position.length() / 220.0
		_events.append([_time + delay, func() -> void:
			if cube.kind == "crown":
				cube.shown = 4
				cube.rise = 1.0
				_burst(global_position + cube.position + Vector2(0, -20), 14, 1.2, true)
				_sound("bloom", -3.0, global_position + cube.position)
			elif WeaveRules.has(pres, i):
				cube.shown = 2
			cube.refresh()])
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))


func _withdraw() -> void:
	if not active or done:
		return
	_events.clear()
	_sparks.clear()
	_sinking = 0.0
	_sound("withdraw", -4.0, _heart_pos)
	for i: int in _cubes.size():
		if WeaveRules.has(pres, i) and _cubes[i].kind != "heart":
			_burst(global_position + _cubes[i].position, 4, 0.6)


func _finish_withdraw() -> void:
	_sinking = -1.0
	_reset_look()
	_shake_cube(rules.heart, 0.3)


## Idle: the heart hums, nothing else is there.
func _reset_look() -> void:
	active = false
	done = false
	lit = 0
	pres = 0
	_shown_lit = 0
	_gold_t = INF
	_events.clear()
	_sparks.clear()
	for i: int in _cubes.size():
		var cube: WeaveCube = _cubes[i]
		_rise_t[i] = INF
		_root_t[i] = INF
		cube.opened = false
		if cube.kind == "heart":
			cube.shown = 0
			cube.rise = 1.0
		elif cube.kind == "crown":
			cube.shown = 3
			cube.rise = 1.0
			_root_t[i] = -100.0
		else:
			cube.shown = 0
			cube.rise = 0.0
		cube.refresh()


func _apply_state(on: bool, l: int, p: int, solved_: bool) -> void:
	_reset_look()
	if not on and not solved_:
		return
	active = true
	lit = l
	pres = p
	_shown_lit = l & p
	_root_t[rules.heart] = -100.0
	for i: int in _cubes.size():
		var cube: WeaveCube = _cubes[i]
		if WeaveRules.has(p, i) or cube.big():
			cube.rise = 1.0
			_root_t[i] = -100.0
			if rules.kinds[i] == "seed":
				var ch: Array = rules.children[i] as Array
				cube.opened = not ch.is_empty() and WeaveRules.has(p, int(ch[0]))
			if cube.kind == "heart":
				cube.shown = 2 if solved_ else 1
			elif cube.kind == "crown":
				cube.shown = 4 if solved_ else 3
			else:
				cube.shown = 2 if solved_ else (1 if WeaveRules.has(l, i) else 0)
		cube.refresh()
	if solved_:
		done = true
		_gold_t = -100.0


func set_solved_instant() -> void:
	var all: int = 0
	for i: int in rules.size():
		all |= 1 << i
	_apply_state(true, all, all, true)


func reset_trial() -> void:
	_reset_look()


func export_progress() -> Dictionary:
	return {"l": lit, "p": pres} if active and not done else {}


func import_progress(data: Dictionary) -> void:
	_apply_state(true, int(data.get("l", 0)), int(data.get("p", 0)), false)


# ------------------------------------------------------------------ drawing
func _root_grow(r: Dictionary) -> Array:
	## [amount 0..1, grows from a]
	var a: int = int(r["a"])
	var b: int = int(r["b"])
	var ta: float = _root_t[a]
	var tb: float = _root_t[b]
	if ta == INF or tb == INF:
		return [0.0, true]
	var start: float = maxf(ta, tb)
	var g: float = clampf((_time - start) / 0.45, 0.0, 1.0)
	if _sinking >= 0.0:
		g *= 1.0 - clampf((_sinking - 0.15) / 0.8, 0.0, 1.0)
	return [g, ta <= tb]


func _root_part(pts: PackedVector2Array, grow: Array) -> PackedVector2Array:
	var g: float = float(grow[0])
	if g >= 1.0:
		return pts
	var n: int = int(float(pts.size()) * g)
	if n <= 0:
		return PackedVector2Array()
	return pts.slice(0, n) if bool(grow[1]) else pts.slice(pts.size() - n)


func _draw_roots() -> void:
	for r: Dictionary in _roots:
		var pts: PackedVector2Array = _root_part(r["pts"] as PackedVector2Array, _root_grow(r))
		if pts.size() < 2:
			continue
		var seed_: int = absi(hash(int(r["a"]) * 31 + int(r["b"])))
		for k: int in pts.size(): ## torn earth along it
			if (k + seed_) % 5 == 0:
				var d: Vector2 = pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]
				var nrm: Vector2 = Vector2(-d.y, d.x).normalized()
				var side: float = 3.0 if (k / 5 + seed_) % 2 == 0 else -3.0
				_root_node.draw_rect(Rect2((pts[k] + nrm * side).round(), Vector2(2, 1)), EARTH[1 + (k + seed_) % 2])
		for p: Vector2 in pts:
			_root_node.draw_rect(Rect2(p - Vector2(1, 1), Vector2(4, 3)), BARK[0])
		for p: Vector2 in pts:
			_root_node.draw_rect(Rect2(p - Vector2(0, 0), Vector2(2, 2)), BARK[1])
		for k: int in pts.size():
			if (k + seed_) % 3 != 0:
				_root_node.draw_rect(Rect2(pts[k] - Vector2(0, 0), Vector2(1, 1)), BARK[2 + int((k + seed_) % 7 == 0)])
		if bool(r["one"]): ## barbs pointing the way the pulse runs
			for k: int in range(6, pts.size() - 6, 7):
				var d2: Vector2 = (pts[mini(k + 2, pts.size() - 1)] - pts[maxi(k - 2, 0)]).normalized()
				var n2: Vector2 = Vector2(-d2.y, d2.x)
				for sgn: float in [1.0, -1.0]:
					var q: Vector2 = (pts[k] - d2 * 2.0 + n2 * sgn * 2.5).round()
					_root_node.draw_rect(Rect2(q, Vector2.ONE), THORN)
					_root_node.draw_rect(Rect2((pts[k] - d2 * 1.0 + n2 * sgn * 1.5).round(), Vector2.ONE), THORN_TIP)


func _draw_sap() -> void:
	var shown_flow: int = rules.flow(_shown_lit, pres) if active else 0
	var gold: float = clampf((_time - _gold_t) * 1.2, 0.0, 1.0) if _gold_t < INF else 0.0
	for ri: int in _roots.size():
		var r: Dictionary = _roots[ri] as Dictionary
		var pts: PackedVector2Array = _root_part(r["pts"] as PackedVector2Array, _root_grow(r))
		if pts.size() < 2:
			continue
		var a: int = int(r["a"])
		var b: int = int(r["b"])
		var lit_a: bool = WeaveRules.has(_shown_lit, a) or (WeaveRules.has(shown_flow, a) and a == rules.heart)
		var lit_b: bool = WeaveRules.has(_shown_lit, b) or (WeaveRules.has(shown_flow, b) and b == rules.heart)
		var in_flow: bool = WeaveRules.has(shown_flow, a) and WeaveRules.has(shown_flow, b)
		var preview: bool = _focus_bit >= 0 and _events.is_empty() and not done and active and (a == _focus_bit or (b == _focus_bit and not bool(r["one"])))
		for k: int in pts.size():
			var col: Color = SAP_DARK
			if gold > 0.0:
				col = SAP_DARK.lerp(SAP_GOLD, gold) if (float(k) / pts.size() < gold * 1.5) else SAP_DARK
			elif in_flow:
				var wave: float = sin(float(k) * 0.55 - _time * 7.0)
				col = SAP_FLOW if wave > 0.55 else SAP_LIT
			elif lit_a and lit_b:
				col = SAP_LIT.darkened(0.25)
			if preview and int(_time * 6.0 + k * 0.5) % 4 == 0:
				col = col.lerp(Color("e8fffb"), 0.6)
			_sap_node.draw_rect(Rect2(pts[k], Vector2.ONE), col)
	for s: Dictionary in _sparks:
		var r2: Dictionary = _roots[int(s["root"])] as Dictionary
		var pts2: PackedVector2Array = r2["pts"] as PackedVector2Array
		var u: float = clampf((_time - float(s["t0"])) / _num("pulse_time", 0.28), 0.0, 1.0)
		if not bool(s["from_a"]):
			u = 1.0 - u
		var idx: int = clampi(int(u * float(pts2.size() - 1)), 0, pts2.size() - 1)
		var back: int = -1 if bool(s["from_a"]) else 1
		for t: int in 5:
			var q: int = clampi(idx + back * t * 2, 0, pts2.size() - 1)
			var c: Color = Color("ffffff") if t == 0 else SAP_FLOW
			c.a = 1.0 - float(t) * 0.18
			var sz: Vector2 = Vector2(2, 2) if t < 2 else Vector2.ONE
			_sap_node.draw_rect(Rect2(pts2[q] - Vector2(0, 0), sz), c)


func _draw_fx() -> void:
	for c: Array in _clods:
		var age: float = float(c[2]) / float(c[3])
		var col: Color = c[4] as Color
		col.a = 1.0 - age * age
		_fx_node.draw_rect(Rect2(((c[0] as Vector2) - global_position).round(), Vector2(2, 2) if age < 0.5 else Vector2.ONE), col)


func _burst(at: Vector2, n: int, power: float, light: bool = false) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(at) + int(_time * 1000.0)
	for k: int in n:
		var a: float = rng.randf_range(-PI, 0.0)
		var v: Vector2 = Vector2(cos(a) * rng.randf_range(20, 70), sin(a) * rng.randf_range(40, 110)) * power
		var col: Color = (SAP_FLOW if k % 2 == 0 else SAP_GOLD) if light else EARTH[rng.randi_range(1, 3)]
		_clods.append([at + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 2)), v, 0.0, rng.randf_range(0.4, 0.75), col])


func _shake_cube(i: int, sec: float) -> void:
	_cubes[i].set_meta("shake_until", _time + sec)


func _nudge(at: Vector2, amount: float) -> void:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority() and p.global_position.distance_to(at) < 220.0:
			p.add_shake(amount)


func _sound(name: String, db: float, at: Vector2) -> void:
	var path: String = SOUND_DIR + name + ".wav"
	if not ResourceLoader.exists(path) or not is_inside_tree():
		return
	var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	p.stream = load(path) as AudioStream
	p.volume_db = db
	p.pitch_scale = randf_range(0.98, 1.02)
	p.max_distance = 520.0
	p.attenuation = 1.4
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.position = at - global_position
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
