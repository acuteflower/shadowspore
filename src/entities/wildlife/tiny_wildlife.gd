class_name TinyWildlife
extends Node2D
## Small ordinary residents. Host chooses paths; peers replay reliable segments.
## Tree snails draw under the crown as children of the actual trunk sprite.
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


func _ready() -> void:
	_spec = DataRegistry.get_entry("wildlife", species)
	_rng.seed = hash(name)
	_population = get_parent().get_parent()
	_from = tree_offset if not tree_path.is_empty() else global_position
	_to = _from
	_visual = Node2D.new()
	add_child(_visual)
	_visual.draw.connect(_draw_animal)
	_attach()
	if multiplayer.is_server():
		_duration = _range("rest_seconds")
	else:
		_request.rpc_id(1)


func _range(key: String) -> float:
	var pair: Array = _spec[key]
	return _rng.randf_range(float(pair[0]), float(pair[1]))


func _tree() -> FirTree:
	return get_node_or_null(NodePath(tree_path)) as FirTree if not tree_path.is_empty() else null


func _attach() -> void:
	var tree: FirTree = _tree()
	var parent: Node = tree.get_node("Sprite") if tree != null else self
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
		if species == "moth" and not TimeManager.is_night():
			queue_free()
			return
		if not tree_path.is_empty():
			var tree: FirTree = _tree()
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
					elif species in ["bee", "ladybug", "moth"] and state == State.FEED and (TimeManager.is_night() if species == "moth" else TimeManager.night_amount() < 0.5):
						_fly(player.global_position)
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
	_visual.visible = species != "moth" or TimeManager.is_night()
	if tree_path.is_empty() and species in ["bee", "moth", "ladybug"]:
		_visual.position.y = -2.0 - (sin(clampf(_elapsed / _duration, 0, 1) * PI) * float(_spec["flight_height"]) if _flying() else 0.0)
	_visual.queue_redraw()


func _flying() -> bool:
	return state == State.FLY or (species in ["bee", "moth"] and state == State.MOVE)


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
