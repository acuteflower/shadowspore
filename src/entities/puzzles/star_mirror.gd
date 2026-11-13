class_name StarMirror
extends WorldTrial
## The star mirror (Sternenspiegel, docs/raetsel_konzept.md 6b). A still pond with a rim of old stones, a square field of meadow beside it marked by
## four corner stones with trial runes, and moonstones lying on the shore. By night the water shows a constellation that is not in the real sky:
## mirrored (`mirror` x / y / diag), turning slowly with the night (`turn` degrees from dusk to dawn), the corner runes reflected with it so the
## field can be found in it. Ellie carries the stones (E "AUFHEBEN", her carry sheet, slow, no sprint) and sets them down (E "ABLEGEN"); a stone set
## down near a free star of the field settles on it, glows, and light runs to every neighbour of the figure that is already lit; its star in the
## water burns warm. Nothing is ever reset. All stars covered: a beam rises out of the water and the chest comes out of the earth on the shore.
## The moon matters: at new moon only the brighter stars show (`faint`), some figures draw their lines only near full moon (`lines` "full_moon").
## Host-authoritative: the host checks a pick or a set-down and sends it (`_rpc_pick`, `_rpc_drop`); a joining peer gets the stones (`_rpc_state`).

const SOUND_DIR: String = "res://assets/audio/stars/"
const RIM: Texture2D = preload("res://assets/props/puzzles/star_pond.png")
const RIM_GLOW: Texture2D = preload("res://assets/props/puzzles/star_pond_glow.png")
const CORNER: Texture2D = preload("res://assets/props/puzzles/star_corner.png")
const CORNER_GLOW: Texture2D = preload("res://assets/props/puzzles/star_corner_glow.png")
const SNAP: float = 13.0 ## px: a stone set down this near a free star settles on it
const WATER: Array[Color] = [Color("142240"), Color("1c3056"), Color("26426e"), Color("3a5f8c"), Color("5d86ac")]
const STAR_COLD: Color = Color("d6ecff")
const STAR_WARM: Color = Color("fff2cc")
const LINE: Color = Color("9ff8ee")
const GOLD: Color = Color("ffb347")
const RUNE: Color = Color("b4a2f0")
const CORNER_RUNES: Array[String] = ["mond", "auge", "flamme", "feder"] ## top left, top right, bottom right, bottom left of the field
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _water_cache: Dictionary = {}

var cfg: Dictionary = {}
var done: bool = false
var stars: Array[Vector2] = [] ## field units 0..1
var bright: Array[int] = [] ## 1..3
var lines: Array = [] ## [i, j]
var mirror_mode: String = "x"
var turn: float = 0.0 ## radians over the night
var faint: bool = false
var lines_need: String = "night"

var _pond: Vector2 = Vector2.ZERO ## the water's centre, world px
var _field: Vector2 = Vector2.ZERO ## the field's centre, world px
var _size: float = 160.0
var _wrx: float = 62.0
var _wry: float = 30.0
var _starts: Array[Vector2] = [] ## the stones' first places, px from the pond
var _stones: Array[StarStone] = []
var _corners: Array[Sprite2D] = []
var _runes: Dictionary = {}
var _corner_rune_at: Vector2 = Vector2(0, -5)
var _reflect: Node2D
var _ground: Node2D
var _fx: Node2D
var _time: float = 0.0
var _solved_t: float = INF


func setup(entry: Dictionary, tuning: Dictionary) -> void:
	super.setup(entry, tuning)
	cfg = tuning
	var t: Array = entry.get("tile", [0, 0]) as Array
	_pond = Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8, 8)
	position = _pond
	var f: Array = entry.get("field", [0, 9]) as Array
	_size = float(entry.get("size", 10)) * 16.0
	_field = _pond + Vector2(float(f[0]), float(f[1])) * 16.0
	mirror_mode = String(entry.get("mirror", "x"))
	turn = deg_to_rad(float(entry.get("turn", 0.0)))
	faint = bool(entry.get("faint", false))
	lines_need = String(entry.get("lines", "night"))
	for st: Variant in entry.get("stars", []) as Array:
		var a: Array = st as Array
		stars.append(Vector2(float(a[0]), float(a[1])))
		bright.append(int(a[2]) if a.size() > 2 else 2)
	lines = entry.get("links", []) as Array
	for s: Variant in entry.get("stones", []) as Array:
		var sa: Array = s as Array
		_starts.append(Vector2(float(sa[0]), float(sa[1])) * 16.0)
	var art: Dictionary = DataRegistry.table("puzzle_art").get("star_mirror", {}) as Dictionary
	var w: Array = art.get("water", [62, 30]) as Array
	_wrx = float(w[0])
	_wry = float(w[1])
	var cr: Array = art.get("corner_rune", [0, -5]) as Array
	_corner_rune_at = Vector2(float(cr[0]), float(cr[1])).round()
	_runes = DataRegistry.table("puzzle_runes").get("runes", {}) as Dictionary


func _ready() -> void:
	y_sort_enabled = true
	var art: Dictionary = DataRegistry.table("puzzle_art").get("star_mirror", {}) as Dictionary
	var water: Sprite2D = Sprite2D.new()
	water.texture = _water_texture(int(_wrx), int(_wry))
	water.z_index = -8
	add_child(water)
	_reflect = Node2D.new()
	_reflect.z_index = -7
	_reflect.material = Unlit.material()
	_reflect.draw.connect(_draw_reflection)
	add_child(_reflect)
	var pf: Array = art.get("pond_frame", [160, 92]) as Array
	var rim: Sprite2D = Sprite2D.new()
	rim.texture = RIM
	rim.centered = false
	rim.offset = Vector2(-float(pf[0]) / 2.0, -float(art.get("pond_ground", 50)))
	rim.z_index = -6
	add_child(rim)
	var rim_glow: Sprite2D = Sprite2D.new()
	rim_glow.texture = RIM_GLOW
	rim_glow.centered = false
	rim_glow.offset = rim.offset
	rim_glow.z_index = -6
	rim_glow.material = Unlit.material()
	add_child(rim_glow)
	var body: StaticBody2D = StaticBody2D.new()
	var poly: CollisionPolygon2D = CollisionPolygon2D.new()
	var pts: PackedVector2Array = []
	for k: int in 24:
		var a: float = float(k) / 24.0 * TAU
		pts.append(Vector2(cos(a) * (_wrx + 3.0), sin(a) * (_wry + 2.0)))
	poly.polygon = pts
	body.add_child(poly)
	add_child(body)
	_ground = Node2D.new()
	_ground.z_index = -7
	_ground.material = Unlit.material()
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_fx = Node2D.new()
	_fx.z_index = 4
	_fx.material = Unlit.material()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	var cf: Array = art.get("corner_frame", [22, 34]) as Array
	var cg: float = float(art.get("corner_ground", 28))
	for k: int in 4:
		var corner: Sprite2D = Sprite2D.new()
		corner.texture = CORNER
		corner.hframes = 2
		corner.centered = false
		corner.offset = Vector2(-float(cf[0]) / 2.0, -cg)
		corner.position = _field_corner(k) - _pond
		var g: Sprite2D = Sprite2D.new()
		g.texture = CORNER_GLOW
		g.hframes = 2
		g.centered = false
		g.offset = corner.offset
		g.material = Unlit.material()
		corner.add_child(g)
		var mark: Node2D = Node2D.new()
		mark.material = Unlit.material()
		var rune_name: String = CORNER_RUNES[k]
		mark.draw.connect(func() -> void: _draw_rune(mark, _corner_rune_at - Vector2(2, 2), rune_name, RUNE))
		corner.add_child(mark)
		var solid: StaticBody2D = StaticBody2D.new()
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(10, 6)
		cs.shape = rect
		cs.position = Vector2(0, -2)
		solid.add_child(cs)
		corner.add_child(solid)
		add_child(corner)
		_corners.append(corner)
	for i: int in _starts.size():
		var stone: StarStone = StarStone.new()
		stone.name = "Stone%d" % i
		stone.mirror = self
		stone.index = i
		stone.shape = i % 4
		stone.position = _starts[i]
		add_child(stone)
		_stones.append(stone)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void: _rpc_state.rpc_id(peer, _positions(), _carriers(), done))


func _field_corner(k: int) -> Vector2:
	var h: float = _size * 0.5
	return _field + [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)][k]


## A star's place on the field, world px.
func star_position(i: int) -> Vector2:
	return _field + (stars[i] - Vector2(0.5, 0.5)) * _size


func start_position() -> Vector2:
	return _pond + Vector2(0, _wry + 40.0)


func end_position() -> Vector2:
	return _pond + Vector2(-_wrx - 26.0, 8.0) ## on the west shore


func reward_rise() -> bool:
	return true


func player_of(peer: int) -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer:
			return p
	return null


## Where a stone in her arms would be set down: just in front of her feet.
func drop_point(p: Player) -> Vector2:
	var sector: int = posmod(roundi(p.facing.angle() / (PI / 4.0)), 8)
	var d: Vector2 = Vector2.from_angle(float(sector) * PI / 4.0)
	return (p.global_position + Vector2(d.x * 14.0, d.y * 9.0 + 2.0)).round()


func in_water(pos: Vector2, margin: float = 6.0) -> bool:
	var q: Vector2 = pos - _pond
	return pow(q.x / (_wrx + margin), 2.0) + pow(q.y / (_wry + margin), 2.0) < 1.0


## The free star a stone set down at `pos` settles on (-1 = none). `except` = the stone itself.
func snap_star(pos: Vector2, except: int = -1) -> int:
	var best: int = -1
	var best_d: float = SNAP
	for i: int in stars.size():
		var d: float = star_position(i).distance_to(pos)
		if d > best_d:
			continue
		var taken: bool = false
		for s: StarStone in _stones:
			if s.index != except and s.carrier == 0 and s.on_star == i:
				taken = true
		if not taken:
			best = i
			best_d = d
	return best


## The star a stone lies exactly on (-1 = none).
func _star_at(pos: Vector2) -> int:
	for i: int in stars.size():
		if star_position(i).distance_to(pos) < 1.0:
			return i
	return -1


func covered() -> int:
	var n: int = 0
	for s: StarStone in _stones:
		if s.carrier == 0 and s.on_star >= 0:
			n += 1
	return n


# ------------------------------------------------------------------ what E does
func stone_prompt(stone: StarStone) -> String:
	if done:
		return ""
	var me: int = multiplayer.get_unique_id()
	if stone.carrier == me:
		return "ABLEGEN"
	if stone.carrier != 0:
		return ""
	var p: Player = player_of(me)
	if p == null or p.carry_stone != 0:
		return ""
	return "AUFHEBEN"


func stone_hint(stone: StarStone) -> String:
	if stone.carrier == multiplayer.get_unique_id() and in_water(stone.global_position):
		return "IM WASSER"
	return ""


func stone_used(stone: StarStone, player: Player) -> void:
	if done or player.climb.active() or player.swim > 0:
		return
	if stone.carrier == player.name.to_int():
		if player._carry_anim >= 0.0 or in_water(stone.global_position):
			return
		_ask("drop", stone.index, stone.global_position)
	elif stone.carrier == 0 and player.carry_stone == 0 and not player.is_busy():
		_ask("pick", stone.index, Vector2.ZERO)


func _ask(what: String, i: int, at: Vector2) -> void:
	if multiplayer.is_server():
		_host_ask(what, i, at, multiplayer.get_unique_id())
	else:
		_rpc_ask.rpc_id(1, what, i, at)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask(what: String, i: int, at: Vector2) -> void:
	if multiplayer.is_server():
		_host_ask(what, i, at, multiplayer.get_remote_sender_id())


func _host_ask(what: String, i: int, at: Vector2, peer: int) -> void:
	if done or i < 0 or i >= _stones.size():
		return
	var stone: StarStone = _stones[i]
	var p: Player = player_of(peer)
	if p == null or p.health == null or p.health.current <= 0.0:
		return
	match what:
		"pick":
			if stone.carrier != 0 or p.carry_stone != 0 or p.global_position.distance_to(stone.global_position) > 44.0:
				return
			for s: StarStone in _stones:
				if s.carrier == peer:
					return
			_send_pick(i, peer)
		"drop":
			if stone.carrier != peer or at.distance_to(p.global_position) > 40.0 or in_water(at):
				return
			var star: int = snap_star(at, i)
			_send_drop(i, star_position(star) if star >= 0 else at.round(), star)


func _send_pick(i: int, peer: int) -> void:
	if multiplayer.get_peers().is_empty():
		_rpc_pick(i, peer)
	else:
		_rpc_pick.rpc(i, peer)


func _send_drop(i: int, at: Vector2, star: int) -> void:
	if multiplayer.get_peers().is_empty():
		_rpc_drop(i, at, star)
	else:
		_rpc_drop.rpc(i, at, star)


@rpc("authority", "call_local", "reliable")
func _rpc_pick(i: int, peer: int) -> void:
	var stone: StarStone = _stones[i]
	stone.carrier = peer
	stone.on_star = -1
	stone.refresh()
	var p: Player = player_of(peer)
	if p != null:
		p.start_carry()
	_sound("lift", -8.0, stone.global_position)


@rpc("authority", "call_local", "reliable")
func _rpc_drop(i: int, at: Vector2, star: int) -> void:
	var stone: StarStone = _stones[i]
	var p: Player = player_of(stone.carrier)
	stone.carrier = 0
	stone.global_position = at
	stone.on_star = star
	stone.hidden_until = stone._time + Player.carry_lift_time() * 0.85 if p != null else 0.0
	stone.refresh()
	if p != null:
		p.end_carry()
	get_tree().create_timer(Player.carry_lift_time() * 0.85).timeout.connect(func() -> void:
		_sound("set", -8.0, at)
		if star >= 0:
			_sound("chime_%d" % (star % 6), -5.0, at)
			stone.set_meta("flash", _time))
	if covered() >= stars.size() and not done:
		done = true
		get_tree().create_timer(Player.carry_lift_time() + 0.4).timeout.connect(_play_solved)
		if multiplayer.is_server():
			get_tree().create_timer(Player.carry_lift_time() + 2.6).timeout.connect(func() -> void: solved.emit(id, end_position()))


## A joining peer: where the stones lie and who carries one.
@rpc("authority", "reliable")
func _rpc_state(pos: PackedVector2Array, carriers: PackedInt32Array, solved_: bool) -> void:
	_apply(pos, carriers, solved_)


func _positions() -> PackedVector2Array:
	var out: PackedVector2Array = []
	for s: StarStone in _stones:
		out.append(s.position)
	return out


func _carriers() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for s: StarStone in _stones:
		out.append(s.carrier)
	return out


func _apply(pos: PackedVector2Array, carriers: PackedInt32Array, solved_: bool) -> void:
	for i: int in mini(pos.size(), _stones.size()):
		var s: StarStone = _stones[i]
		s.position = pos[i]
		s.carrier = carriers[i] if i < carriers.size() else 0
		s.on_star = _star_at(s.global_position) if s.carrier == 0 else -1
		var p: Player = player_of(s.carrier) if s.carrier != 0 else null
		if p != null and p.carry_stone == 0:
			p.start_carry()
		s.hidden_until = 0.0
		s.refresh()
	done = solved_
	if done:
		_solved_t = -100.0


func _process(delta: float) -> void:
	_time += delta
	_reflect.queue_redraw()
	_ground.queue_redraw()
	if _time - _solved_t < 4.0:
		_fx.queue_redraw()
	var lit_k: int = 1 if _night() > 0.5 or done else 0
	for c: Sprite2D in _corners:
		if c.frame != lit_k:
			c.frame = lit_k
			(c.get_child(0) as Sprite2D).frame = lit_k
	if multiplayer.is_server():
		for s: StarStone in _stones: ## a carrier who fell or left drops the stone where she was
			if s.carrier == 0:
				continue
			var p: Player = player_of(s.carrier)
			if p == null or p.health == null or p.health.current <= 0.0:
				var at: Vector2 = s.global_position
				if in_water(at):
					at = _pond + Vector2(0, _wry + 14.0)
				_send_drop(s.index, at.round(), -1)


func _night() -> float:
	return smoothstep(0.3, 0.7, TimeManager.night_amount())


## 1 at full moon, 0 at new moon.
func moon_full() -> float:
	return 1.0 - absf(TimeManager.moon_phase() - 0.5) * 2.0


## How far the night has run (0 at dusk .. 1 at dawn); the reflection turns with it.
func _night_progress() -> float:
	var t: float = TimeManager.time_of_day
	var span: float = 1.0 - TimeManager.NIGHT_START + TimeManager.NIGHT_END
	return clampf(fposmod(t - TimeManager.NIGHT_START, 1.0) / span, 0.0, 1.0)


## A point of the field (units 0..1) as the water shows it, px from the pond's centre.
func reflect_point(uv: Vector2) -> Vector2:
	var m: Vector2 = uv
	match mirror_mode:
		"x":
			m.x = 1.0 - m.x
		"y":
			m.y = 1.0 - m.y
		"diag":
			m = Vector2(m.y, m.x)
	var p: Vector2 = (m - Vector2(0.5, 0.5)).rotated(turn * _night_progress())
	return Vector2(p.x * 1.3 * _wrx, p.y * 1.3 * _wry)


func star_visible(i: int) -> bool:
	return not faint or bright[i] >= 2 or moon_full() >= 0.3


func lines_visible() -> bool:
	return lines_need != "full_moon" or moon_full() >= 0.7


# ------------------------------------------------------------------ drawing
func _inside(q: Vector2) -> bool:
	return pow(q.x / (_wrx - 2.0), 2.0) + pow(q.y / (_wry - 2.0), 2.0) < 1.0


func _px(q: Vector2, col: Color) -> void:
	q = q.round()
	if _inside(q):
		_reflect.draw_rect(Rect2(q, Vector2.ONE), col)


func _draw_reflection() -> void:
	var night: float = _night()
	# glints on the water by day and night: short bright dashes drifting
	for k: int in 7:
		var gy: float = -_wry * 0.7 + float(k) * _wry * 0.22
		var gx: float = fposmod(float(k) * 37.0 + _time * (6.0 + k), _wrx * 2.0) - _wrx
		var c: Color = WATER[4]
		c.a = 0.25 + 0.15 * sin(_time * 1.3 + k)
		for d: int in 3 + k % 3:
			_px(Vector2(gx + d, gy), c)
	if night <= 0.01 and not done:
		return
	var vis: float = maxf(night, 1.0 if done else 0.0)
	var wob: float = 0.0
	var reflected: Array[Vector2] = []
	for i: int in stars.size():
		reflected.append(reflect_point(stars[i]))
	if lines_visible() or done:
		for l: Variant in lines:
			var la: Array = l as Array
			var i0: int = int(la[0])
			var i1: int = int(la[1])
			if not star_visible(i0) or not star_visible(i1):
				continue
			var a: Vector2 = reflected[i0]
			var b: Vector2 = reflected[i1]
			var n: int = int(a.distance_to(b))
			var col: Color = (GOLD if done else LINE)
			col.a = 0.32 * vis
			for k: int in n:
				if k % 2 == 0:
					_px(a.lerp(b, float(k) / float(n)), col)
	for k: int in 4: ## the corner runes, reflected with the field
		var at: Vector2 = reflect_point([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][k])
		var rune: Array = _runes.get(CORNER_RUNES[k], []) as Array
		var col2: Color = RUNE
		col2.a = 0.55 * vis
		for y: int in rune.size():
			var line: String = String(rune[y])
			for x: int in line.length():
				if line[x] == "X":
					_px(at + Vector2(x - 2, y - 2), col2)
	for i: int in stars.size():
		if not star_visible(i):
			continue
		var on: bool = done or _star_covered(i)
		var col3: Color = GOLD.lerp(STAR_WARM, 0.5) if done else (STAR_WARM if on else STAR_COLD)
		var tw: float = 0.75 + 0.25 * sin(_time * (2.0 + float(i) * 0.37) + float(i))
		col3.a = vis * tw * (1.0 if on else 0.85)
		wob = roundf(sin(_time * 1.6 + reflected[i].y * 0.5) * 0.6)
		var p: Vector2 = reflected[i] + Vector2(wob, 0)
		_px(p, col3)
		var b2: int = bright[i] + (1 if on else 0)
		if b2 >= 2:
			var arm: Color = col3
			arm.a *= 0.7
			for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_px(p + d, arm)
		if b2 >= 3:
			var tip: Color = col3
			tip.a *= 0.35
			for d2: Vector2 in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
				_px(p + d2, tip)


func _star_covered(i: int) -> bool:
	for s: StarStone in _stones:
		if s.carrier == 0 and s.on_star == i and s._time >= s.hidden_until:
			return true
	return false


func _draw_ground() -> void:
	var gold: float = clampf((_time - _solved_t) * 0.8, 0.0, 1.0) if _solved_t < INF else 0.0
	for l: Variant in lines: ## light runs between neighbours of the figure that both lie right
		var la: Array = l as Array
		var i0: int = int(la[0])
		var i1: int = int(la[1])
		if not (_star_covered(i0) and _star_covered(i1)):
			continue
		var a: Vector2 = star_position(i0) - _pond + Vector2(0, -3)
		var b: Vector2 = star_position(i1) - _pond + Vector2(0, -3)
		var n: int = int(a.distance_to(b))
		for k: int in range(6, n - 6):
			var u: float = float(k) / float(n)
			var wave: float = sin(float(k) * 0.4 - _time * 5.0)
			var col: Color = LINE.lerp(GOLD, gold)
			col.a = 0.35 + 0.35 * maxf(0.0, wave)
			_ground.draw_rect(Rect2(a.lerp(b, u).round(), Vector2.ONE), col)
	for s: StarStone in _stones: ## a ring of light under every stone that lies right, a flash when it settles
		if s.carrier != 0 or s.on_star < 0 or s._time < s.hidden_until:
			continue
		var c: Vector2 = s.position
		var flash: float = 0.0
		if s.has_meta("flash"):
			flash = clampf(1.0 - (_time - float(s.get_meta("flash"))) / 0.8, 0.0, 1.0)
		var r: float = 9.0 + flash * 10.0
		var col2: Color = LINE.lerp(GOLD, gold)
		col2.a = 0.3 + 0.5 * flash
		for k2: int in 20:
			var a2: float = float(k2) / 20.0 * TAU + _time * 0.6
			_ground.draw_rect(Rect2((c + Vector2(cos(a2) * r, sin(a2) * r * 0.5)).round(), Vector2.ONE), col2)


func _draw_fx() -> void:
	var t: float = _time - _solved_t
	if t < 0.0 or t > 4.0:
		return
	var k: float = clampf(t / 0.4, 0.0, 1.0) * (1.0 - clampf((t - 2.6) / 1.4, 0.0, 1.0))
	for y: int in range(0, 220, 1): ## a column of light out of the water into the sky
		var w: float = (5.0 + 3.0 * sin(float(y) * 0.2 - t * 9.0)) * (1.0 - float(y) / 260.0)
		var col: Color = STAR_WARM.lerp(GOLD, float(y) / 220.0)
		col.a = k * (1.0 - float(y) / 220.0) * 0.8
		_fx.draw_rect(Rect2(Vector2(-roundf(w), -float(y)), Vector2(roundf(w) * 2.0, 1.0)), col)
	for i: int in 24: ## sparks rising in it
		var u: float = fposmod(float(i) * 0.137 + t * 0.6, 1.0)
		var col2: Color = STAR_WARM
		col2.a = k * (1.0 - u)
		_fx.draw_rect(Rect2(Vector2(roundf(sin(float(i) * 2.3 + t * 3.0) * 7.0), -u * 200.0), Vector2.ONE * (2.0 if i % 3 == 0 else 1.0)), col2)


func _play_solved() -> void:
	_solved_t = _time
	_sound("solved", -1.0, _pond)
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority() and p.global_position.distance_to(_pond) < 260.0:
			p.add_shake(1.6)


func _draw_rune(node: Node2D, top: Vector2, rune_name: String, col: Color) -> void:
	var rune: Array = _runes.get(rune_name, []) as Array
	for y: int in rune.size():
		var line: String = String(rune[y])
		for x: int in line.length():
			if line[x] == "X":
				node.draw_rect(Rect2(top + Vector2(x, y), Vector2.ONE), col)


## The pond's water: a dithered oval, deeper in the middle, lighter at the far edge (made once per size).
static func _water_texture(rx: int, ry: int) -> Texture2D:
	var key: String = "%d_%d" % [rx, ry]
	if _water_cache.has(key):
		return _water_cache[key] as Texture2D
	var img: Image = Image.create(rx * 2 + 2, ry * 2 + 2, false, Image.FORMAT_RGBA8)
	for y: int in ry * 2 + 2:
		for x: int in rx * 2 + 2:
			var q: Vector2 = Vector2(float(x) - rx - 0.5, float(y) - ry - 0.5)
			var e: float = pow(q.x / (rx + 1.0), 2.0) + pow(q.y / (ry + 1.0), 2.0)
			if e >= 1.0:
				continue
			var depth: float = 1.0 - e ## 1 in the middle
			var v: float = 3.2 - depth * 3.0 + clampf(-q.y / ry, 0.0, 1.0) * 0.6 ## the far (upper) water catches the sky
			v += float(BAYER[(y % 4) * 4 + x % 4]) / 16.0 - 0.47
			img.set_pixel(x, y, WATER[clampi(int(v), 0, 3)])
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_water_cache[key] = tex
	return tex


# ------------------------------------------------------------------ save, reset
func set_solved_instant() -> void:
	for i: int in mini(stars.size(), _stones.size()):
		_stones[i].position = star_position(i) - _pond
		_stones[i].on_star = i
		_stones[i].carrier = 0
		_stones[i].refresh()
	done = true
	_solved_t = -100.0


func reset_trial() -> void:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.carry_stone != 0:
			p.end_carry()
	for i: int in _stones.size():
		var s: StarStone = _stones[i]
		s.carrier = 0
		s.on_star = -1
		s.position = _starts[i]
		s.hidden_until = 0.0
		s.refresh()
	done = false
	_solved_t = INF


func export_progress() -> Dictionary:
	if done:
		return {}
	var moved: bool = false
	var out: Array = []
	for i: int in _stones.size():
		var s: StarStone = _stones[i]
		var p: Vector2 = s.position
		if s.carrier != 0:
			var pl: Player = player_of(s.carrier)
			p = (pl.global_position - _pond).round() if pl != null else _starts[i]
		out.append([p.x, p.y])
		moved = moved or p.distance_to(_starts[i]) > 0.5
	return {"s": out} if moved else {}


func import_progress(data: Dictionary) -> void:
	var pos: PackedVector2Array = []
	var carriers: PackedInt32Array = []
	for a: Variant in data.get("s", []) as Array:
		var pa: Array = a as Array
		pos.append(Vector2(float(pa[0]), float(pa[1])))
		carriers.append(0)
	_apply(pos, carriers, false)


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
