class_name TinyWildlife
extends Node2D
## Small ordinary residents. Host chooses paths; peers replay reliable segments.
## Tree snails draw under the crown as children of the actual trunk sprite.
## The Hexenwald (docs/hexenwald_leben_konzept.md): toads hop between the toadstools, bats flit between the crowns and hang under them
## (their drawing a child of the tree's Crown), and its moths never sleep (the wood is always in dusk).
enum State { REST, MOVE, FEED, WITHDRAW, FLY }
var species: String = "snail"
var appearance: int = 0
var home: Vector2
var tree_path: String = ""
var tree_offset: Vector2 = Vector2.ZERO
var flowers: Array[Vector2] = []
var state: State = State.REST
var _spec: Dictionary
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _from: Vector2
var _to: Vector2
var _elapsed: float = 0.0
var _duration: float = 3.0
var _heading: float = 0.0
var _clock: float = 0.0
var _sense: float = 0.0
var _visual: Node2D
var _population: Node
var _dusk: bool = false ## lives in the Hexenwald (BiomeBlend at home >= 0.5): a moth flies there by day too
var _bout: int = 0 ## host, toads: hops left in this run
var _h_from: float = 0.0 ## bats: flight height at the start / end of this segment (every peer derives them from the segments)
var _h_to: float = 0.0
var _voice: AudioStreamPlayer2D ## toads: the croak, cosmetic, every peer on its own clock
var _croak_left: float = 0.0

const TOAD: Array[String] = [ ## facing east, rows from the top, the feet on the last row: o ink, d dark, b body, l lit back, w wart, e eye, y belly
	"...oo.oo..",
	"..oleoleo.",
	".olwlllwbo",
	"obbbwbbbbo",
	"obdbbbdyyo",
	".oo.oooo..",
]
const TOAD_HOP: Array[String] = [ ## mid-hop: stretched out, the hind legs trailing
	"......oo.oo",
	"....ooleoleo",
	"..oollwlllbo",
	"oddbbbbwbyyo",
	".oo.oooooo..",
]
const TOAD_TONES: Array[Array] = [ ## dark, body, lit, wart, belly: three muted coats (olive, umber, ash)
	[Color("2a2a1e"), Color("4a4632"), Color("6a6448"), Color("7e7452"), Color("8a7a5a")],
	[Color("2a2020"), Color("4a3a30"), Color("6a5444"), Color("80684e"), Color("907a60")],
	[Color("22222a"), Color("3e3c44"), Color("5c5a62"), Color("767070"), Color("80786a")],
]


func _ready() -> void:
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	_spec = DataRegistry.get_entry("wildlife", species)
	_rng.seed = hash(name)
	_population = get_parent().get_parent()
	_dusk = BiomeBlend.amount_at(home) >= 0.5
	_h_from = _bat_cruise() if species == "bat" and tree_path.is_empty() else -tree_offset.y
	_h_to = _h_from
	_croak_left = _range("croak_seconds") if _spec.has("croak_seconds") else -1.0
	_from = tree_offset if not tree_path.is_empty() else global_position
	_to = _from
	_visual = Node2D.new()
	add_child(_visual)
	_visual.draw.connect(_draw_animal)
	_attach()
	if multiplayer.is_server():
		_duration = 0.2 if species == "bat" else _range("rest_seconds") ## a bat cannot hover: it starts flitting at once
	else:
		_request.rpc_id(1)


func _range(key: String) -> float:
	var pair: Array = _spec[key]
	return _rng.randf_range(float(pair[0]), float(pair[1]))


func _tree() -> FirTree:
	return get_node_or_null(NodePath(tree_path)) as FirTree if not tree_path.is_empty() else null


func _attach() -> void:
	var tree: FirTree = _tree()
	var parent: Node = tree.get_node("Crown" if species == "bat" else "Sprite") if tree != null else self ## a bat hangs under the crown
	if not is_instance_valid(_visual):
		_visual = Node2D.new()
		add_child(_visual)
		_visual.draw.connect(_draw_animal)
	if _visual.get_parent() != parent:
		_visual.reparent(parent, false)
	_visual.position = tree_offset if tree != null else Vector2.ZERO


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if multiplayer.is_server():
		if species == "moth" and not TimeManager.is_night() and not _dusk:
			queue_free()
			return
		if not tree_path.is_empty():
			var tree: FirTree = _tree()
			if (tree == null or int(tree.state.get("f", 0)) != 0 or tree.is_queued_for_deletion()) and species == "bat":
				_bat_fly() ## its tree fell: it simply flies off
				return
			if tree == null or int(tree.state.get("f", 0)) != 0 or tree.is_queued_for_deletion():
				var ground: Vector2 = global_position + Vector2(12 if tree_offset.x >= 0 else -12, 6)
				if _population.can_crawl(global_position + Vector2(ground.x - global_position.x, 6), ground):
					_act.rpc(State.REST, ground, ground, 3.0, "", Vector2.ZERO, 0.0)
				else:
					queue_free()
				return
		_sense -= delta
		if _sense <= 0.0:
			_sense = 0.35
			for player: Player in Player.all:
				if player.health.current > 0 and global_position.distance_to(player.global_position) < float(_spec["scatter_range"]):
					if species == "snail" and state != State.WITHDRAW:
						_choose(State.WITHDRAW, _range("withdraw_seconds"))
					elif species == "snail" and state == State.WITHDRAW:
						_elapsed = minf(_elapsed, _duration - 0.4)
					elif species in ["bee", "ladybug", "moth"] and state == State.FEED and ((TimeManager.is_night() or _dusk) if species == "moth" else TimeManager.night_amount() < 0.5):
						_fly(player.global_position)
					elif species == "toad" and state != State.MOVE:
						_bout = 2
						_hop(player.global_position)
					elif species == "bat" and state == State.REST:
						_bat_fly()
					break
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	if state in [State.MOVE, State.FLY]:
		var point: Vector2 = _from.lerp(_to, smoothstep(0.0, 1.0, t) if _flying() else t)
		if _flying():
			point += (_to - _from).orthogonal().normalized() * sin(t * PI) * sin(t * PI * (3.0 if species == "moth" else 1.5)) * (7.0 if species == "moth" else 5.0)
		if tree_path.is_empty():
			global_position = point
		else:
			tree_offset = point
		_heading = (_to - _from).angle()
	if multiplayer.is_server() and t >= 1.0:
		if species == "toad":
			if state == State.MOVE and _bout > 0:
				_hop()
			elif state == State.MOVE:
				_choose(State.REST, _range("rest_seconds"))
			else:
				var bout: Array = _spec["bout"]
				_bout = _rng.randi_range(int(bout[0]), int(bout[1]))
				_hop()
			return
		if species == "bat":
			if state == State.FLY and _hang_target != null and is_instance_valid(_hang_target):
				var half: float = float((_hang_target.spec()["crown_half_width"] as Array)[_hang_target.variant])
				var hang: Vector2 = Vector2(clampf(global_position.x - _hang_target.global_position.x, -half * 0.5, half * 0.5), -_bat_hang_height(_hang_target))
				_act.rpc(State.REST, global_position, global_position, _range("rest_seconds"), String(_hang_target.get_path()), hang, 0.0)
				_hang_target = null
			else:
				_bat_fly()
			return
		if species in ["bee", "moth"]:
			if state == State.MOVE:
				_choose(State.FEED if species == "moth" or TimeManager.night_amount() < 0.5 else State.REST, _range("feed_seconds"))
			elif species == "bee" and TimeManager.night_amount() > 0.5:
				_choose(State.REST, _range("rest_seconds"))
			else:
				_fly()
		elif species == "ladybug":
			if TimeManager.night_amount() > 0.5:
				_choose(State.REST, _range("rest_seconds"))
			elif state in [State.MOVE, State.FLY]:
				_choose(State.FEED, _range("feed_seconds"))
			elif _rng.randf() < 0.3:
				_fly()
			else:
				_crawl()
		elif state == State.MOVE or _rng.randf() < (0.2 if TimeManager.night_amount() > 0.3 else 0.45):
			_choose(State.REST, _range("rest_seconds"))
		else:
			_crawl()


func _process(delta: float) -> void:
	_clock += delta
	_attach()
	_visual.visible = species != "moth" or TimeManager.is_night() or _dusk
	if tree_path.is_empty() and species in ["bee", "moth", "ladybug"]:
		_visual.position.y = -2.0 - (sin(clampf(_elapsed / _duration, 0, 1) * PI) * float(_spec["flight_height"]) if _flying() else 0.0)
	elif species == "toad":
		_visual.position.y = -sin(clampf(_elapsed / _duration, 0, 1) * PI) * 3.0 if state == State.MOVE else 0.0
		_croak(delta)
	elif species == "bat" and tree_path.is_empty():
		var t: float = smoothstep(0.0, 1.0, clampf(_elapsed / _duration, 0, 1))
		_visual.position.y = -(lerpf(_h_from, _h_to, t) + sin(_clock * 2.6 + float(appearance)) * 4.0 * sin(t * PI))
	_visual.queue_redraw()


func _flying() -> bool:
	return state == State.FLY or (species in ["bee", "moth"] and state == State.MOVE)


# ------------------------------------------------------------------ toads
## Host: one hop of a toad, 4-9 px, towards its home when it strayed, else anywhere; away from `danger` when one is given.
func _hop(danger: Vector2 = Vector2.INF) -> void:
	_bout -= 1
	var at: Vector2 = global_position
	var dir: Vector2 = Vector2.from_angle(_rng.randf() * TAU)
	if danger.is_finite():
		dir = (at - danger).normalized()
	elif at.distance_to(home) > float(_spec["home_radius"]) * 0.6:
		dir = (home - at).normalized()
	for angle: float in [0.0, 0.5, -0.5, 1.1, -1.1]:
		var end: Vector2 = (at + dir.rotated(angle + _rng.randf_range(-0.3, 0.3)) * _range("hop_distance")).round()
		if (danger.is_finite() or end.distance_to(home) <= float(_spec["home_radius"])) and _population.can_crawl(at, end, species):
			_act.rpc(State.MOVE, at, end, _range("hop_seconds"), "", Vector2.ZERO, 0.0)
			return
	_bout = 0
	_choose(State.REST, _range("rest_seconds"))


## Every peer, locally: now and then a sitting toad croaks (heard only close by, the effects volume like the birds' calls).
func _croak(delta: float) -> void:
	if _croak_left < 0.0 or state != State.REST:
		return
	_croak_left -= delta
	if _croak_left > 0.0:
		return
	_croak_left = _range("croak_seconds")
	var volume: float = float(GameSettings.get_value("sfx")) / 100.0
	if volume <= 0.001 or not _visual.is_visible_in_tree():
		return
	if _voice == null:
		_voice = AudioStreamPlayer2D.new()
		_voice.max_distance = 260.0
		add_child(_voice)
	_voice.stream = load("res://assets/audio/hexenwald/toad_%s.wav" % ["a", "b"][_rng.randi() % 2]) as AudioStream
	_voice.volume_db = float(_spec.get("croak_volume_db", -20.0)) + linear_to_db(volume)
	_voice.pitch_scale = _rng.randf_range(0.88, 1.1) * (1.0 - 0.06 * float(appearance))
	_voice.play()


# ------------------------------------------------------------------ bats
var _hang_target: FirTree = null ## host: the tree this bat flies to, to hang under its crown

func _bat_cruise() -> float:
	var heights: Array = _spec.get("flight_height", [26, 52])
	return lerpf(float(heights[0]), float(heights[1]), float(appearance) / 2.0)


func _bat_hang_height(tree: FirTree) -> float:
	return float((tree.spec()["clear"] as Array)[tree.variant]) + 1.0


## Host: a bat's next flit: to another point among the crowns of its home, now and then to hang under a crown for a while.
func _bat_fly() -> void:
	var at: Vector2 = global_position
	if not tree_path.is_empty():
		var tree: FirTree = _tree()
		at = tree.global_position + Vector2(tree_offset.x, 0) if tree != null else global_position
	_hang_target = null
	var end: Vector2 = home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(20.0, float(_spec["patch_radius"]))
	var target_h: float = 0.0
	if _rng.randf() < float(_spec["hang_chance"]) and not flowers.is_empty():
		var spot: Vector2 = flowers[_rng.randi_range(0, flowers.size() - 1)]
		for node: Node in get_tree().get_nodes_in_group("bird_perches"):
			var tree: FirTree = node as FirTree
			if tree != null and tree.global_position.distance_to(spot) < 2.0 and int(tree.state.get("f", 0)) == 0:
				_hang_target = tree
				end = tree.global_position + Vector2(_rng.randf_range(-6.0, 6.0), 0.0)
				target_h = _bat_hang_height(tree)
	var seconds: float = clampf(at.distance_to(end) / float(_spec["flight_speed"]), 1.2, 6.0)
	_act.rpc(State.FLY, at, end, seconds, "", Vector2(0, -target_h), 0.0)



func _choose(next: State, seconds: float) -> void:
	var at: Vector2 = global_position if tree_path.is_empty() else tree_offset
	_act.rpc(next, at, at, seconds, tree_path, tree_offset, 0.0)


func _crawl() -> void:
	var at: Vector2 = global_position if tree_path.is_empty() else tree_offset
	var end: Vector2 = at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4, 10)
	if not tree_path.is_empty():
		var tree: FirTree = _tree()
		var height: float = minf(24, float((tree.spec()["clear"] as Array)[tree.variant]) - 4) if tree != null else 10.0
		end = Vector2(tree_offset.x, clampf(end.y, -height, -7.0))
	elif end.distance_to(home) > float(_spec["home_radius"]) or not _population.can_crawl(at, end, species):
		_choose(State.REST, _range("rest_seconds"))
		return
	_act.rpc(State.MOVE, at, end, maxf(1, at.distance_to(end) / float(_spec["crawl_speed"])), tree_path, tree_offset, 0.0)


func _fly(danger: Vector2 = Vector2.INF) -> void:
	var choices: Array[Vector2] = []
	for point: Vector2 in flowers:
		if point.distance_to(home) <= float(_spec["patch_radius"]) and point.distance_to(global_position) > 5:
			choices.append(point)
	if choices.is_empty():
		_choose(State.REST, _range("rest_seconds"))
		return
	var end: Vector2 = choices[_rng.randi_range(0, choices.size() - 1)]
	if danger.is_finite():
		for point: Vector2 in choices:
			if point.distance_to(danger) > end.distance_to(danger):
				end = point
	_act.rpc(State.FLY if species == "ladybug" else State.MOVE, global_position, end, maxf(0.65, global_position.distance_to(end) / float(_spec["flight_speed"])), "", Vector2.ZERO, 0.0)


@rpc("authority", "call_local", "reliable")
func _act(next: int, start: Vector2, end: Vector2, seconds: float, tree: String, offset: Vector2, elapsed: float) -> void:
	if species == "bat": ## heights of the segment: from the hang it leaves (or the air), to the hang it wants (offset.y) or its cruise
		_h_from = -tree_offset.y if not tree_path.is_empty() else (_h_to if state == State.FLY else _bat_cruise())
		_h_to = -offset.y if tree.is_empty() and offset.y < 0.0 else _bat_cruise()
		if not tree.is_empty():
			_h_from = -offset.y
			_h_to = _h_from
	state = next as State
	_from = start
	_to = end
	_duration = maxf(0.1, seconds)
	_elapsed = elapsed
	tree_path = tree
	tree_offset = offset
	if tree_path.is_empty():
		global_position = start.lerp(end, clampf(elapsed / _duration, 0, 1))
	_attach()


@rpc("any_peer", "call_remote", "reliable")
func _request() -> void:
	if multiplayer.is_server():
		_act.rpc_id(multiplayer.get_remote_sender_id(), state, _from, _to, _duration, tree_path, tree_offset, _elapsed)


func _draw_animal() -> void:
	if species == "toad":
		_draw_toad()
		return
	if species == "bat":
		_draw_bat()
		return
	if species == "moth":
		var side: Vector2 = Vector2.from_angle(_heading).orthogonal()
		var wing: float = 1.2 + absf(sin(_clock * 24)) * 2.0 if _flying() else 1.5
		var tones: Array[Color] = [Color("a79d8b"), Color("8b8498"), Color("b8afa0")]
		for sign_value: float in [-1, 1]:
			var at: Vector2 = (side * sign_value * wing).round()
			_visual.draw_rect(Rect2(at - Vector2.ONE, Vector2(3, 3)), Color("4a414b"))
			_visual.draw_rect(Rect2(at, Vector2(2, 2)), tones[posmod(appearance, 3)])
			_visual.draw_rect(Rect2(at, Vector2.ONE), Color("635761"))
		_visual.draw_rect(Rect2(0, -1, 1, 3), Color("443c45"))
	elif species == "ladybug":
		if _flying():
			_visual.draw_rect(Rect2(-3, -1, 2, 1), Color("c2b7a2", 0.7))
			_visual.draw_rect(Rect2(2, 0, 2, 1), Color("c2b7a2", 0.7))
		_visual.draw_rect(Rect2(-2, -1, 4, 3), Color("3b3039"))
		var tones: Array[Color] = [Color("ac6151"), Color("b57b54"), Color("945247")]
		_visual.draw_rect(Rect2(-1, -1, 3, 3), tones[posmod(appearance, 3)])
		_visual.draw_rect(Rect2(0, -1, 1, 3), Color("4a3037"))
		_visual.draw_rect(Rect2(-1, 0, 1, 1), Color("302b34"))
		_visual.draw_rect(Rect2(1, 1, 1, 1), Color("302b34"))
		_visual.draw_rect(Rect2(Vector2.from_angle(_heading).round() * 2, Vector2.ONE), Color("302b34"))
	elif species == "bee":
		var dir: Vector2 = Vector2.from_angle(_heading)
		var side: Vector2 = dir.orthogonal()
		if state == State.MOVE:
			for sign_value: float in [-1.0, 1.0]:
				_visual.draw_rect(Rect2((side * sign_value * (1.5 + sin(_clock * 80) * 0.7) - dir).round(), Vector2(2, 1)), Color("bbc7be", 0.75))
		for i: int in range(-2, 2):
			var gold: Array[Color] = [Color("b99c60"), Color("c3aa76"), Color("a48a58")]
			_visual.draw_rect(Rect2((dir * i).round(), Vector2(1, 2)), gold[posmod(appearance, 3)] if posmod(i, 2) == 0 else Color("40343b"))
		_visual.draw_rect(Rect2((dir * 2).round(), Vector2.ONE), Color("302d35"))
	else:
		var curled: bool = state == State.WITHDRAW
		var dir: Vector2 = Vector2.from_angle(_heading)
		if not curled:
			for i: int in range(-2, 4):
				_visual.draw_rect(Rect2((dir * i + Vector2(0, 1)).round(), Vector2.ONE), Color("8e8b72"))
			for side: float in [-1, 1]:
				var eye: Vector2 = dir * 4 + dir.orthogonal() * side
				_visual.draw_rect(Rect2(eye.round(), Vector2.ONE), Color("b0ad8c"))
		var colors: Array[Color] = [Color("a17c58"), Color("8b7771"), Color("b8a17b")]
		_visual.draw_rect(Rect2(-2, -1, 5, 2), Color("443b3c"))
		_visual.draw_rect(Rect2(-1, -2, 3, 4), Color("443b3c"))
		_visual.draw_rect(Rect2(-2, -2, 3, 3), colors[posmod(appearance, 3)])
		_visual.draw_rect(Rect2(-1, -1, 2, 1), Color("635049"))
		_visual.draw_rect(Rect2(-1, -2, 1, 1), Color("d0b58b"))


func _exit_tree() -> void:
	if is_instance_valid(_visual) and _visual.get_parent() != self:
		_visual.queue_free()


func _draw_toad() -> void:
	var hop: bool = state == State.MOVE and sin(clampf(_elapsed / _duration, 0, 1) * PI) > 0.35
	var rows: Array[String] = TOAD_HOP if hop else TOAD
	var flip: bool = cos(_heading) < 0.0
	var tones: Array = TOAD_TONES[posmod(appearance, 3)]
	var lift: int = rows.size()
	_visual.draw_rect(Rect2(-4, -1, 9, 2), Color(0.02, 0.02, 0.05, 0.28)) ## its shadow stays on the ground
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			var c: Color
			match row[x]:
				"o": c = Color("120e14")
				"d": c = tones[0]
				"b": c = tones[1]
				"l": c = tones[2]
				"w": c = tones[3]
				"y": c = tones[4]
				"e": c = Color("c8a040")
				_: continue
			var px: int = (x - row.length() / 2) * (-1 if flip else 1)
			_visual.draw_rect(Rect2(px, y - lift, 1, 1), c)


func _draw_bat() -> void:
	var hanging: bool = not tree_path.is_empty()
	var body: Color = Color("1a1420")
	var wing: Color = Color("3a2e48")
	var rim: Color = Color("6a5a7a") ## the wing's edge catches the dusk, so the silhouette reads against the dark floor
	if hanging: ## upside down under the bough, wings wrapped round it, a twitch of the ears now and then
		_visual.draw_rect(Rect2(-1, 0, 3, 5), body)
		_visual.draw_rect(Rect2(-1, 1, 1, 3), wing)
		_visual.draw_rect(Rect2(1, 1, 1, 3), rim)
		var ear: int = 1 if sin(_clock * 0.7 + float(appearance) * 2.0) > 0.97 else 0
		_visual.draw_rect(Rect2(-1, 5, 1, 1 + ear), body)
		_visual.draw_rect(Rect2(1, 5, 1, 1), body)
		_visual.draw_rect(Rect2(0, -1, 1, 1), Color("0c0812")) ## the feet on the bough
		return
	var h: float = -_visual.position.y
	_visual.draw_rect(Rect2(-1, round(h), 3, 1), Color(0.02, 0.02, 0.05, 0.22)) ## a faint shadow far below
	var beat: int = int(_clock * 13.0 + float(appearance) * 1.7) % 4
	var lift: Array[int] = [-2, 0, 2, 0]
	for side: int in [-1, 1]:
		for k: int in range(1, 6):
			var y: int = int(round(float(lift[beat]) * float(k) / 5.0)) + (1 if k == 5 and beat == 1 else 0)
			_visual.draw_rect(Rect2(side * (k + 1) - (1 if side < 0 else 0), y, 1, 1), rim if k == 5 else wing)
			if k < 5 and k % 2 == 1:
				_visual.draw_rect(Rect2(side * (k + 1) - (1 if side < 0 else 0), y + 1, 1, 1), wing) ## the membrane hangs between the fingers
	_visual.draw_rect(Rect2(-1, -1, 3, 3), body)
	_visual.draw_rect(Rect2(-1, -2, 1, 1), body)
	_visual.draw_rect(Rect2(1, -2, 1, 1), body)
