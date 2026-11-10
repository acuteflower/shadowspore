class_name EnemyNavigation
extends Node
## Host-only, incremental A* over the actual loaded physics world. Swept body-sized
## edges find stairs and routes around props; optional species links cross climbable cliffs.
## No navigation bake to go stale when the world streams or a tree is felled.

const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
const SHARED_USEC: int = 2400 ## all searching creatures together get at most this much A* time per physics frame
const MIN_SHARE_USEC: int = 250 ## every searcher still gets a little, so nobody starves at the end of the tree order
static var _frame: int = -1
static var _frame_used: int = 0
static var _searchers: int = 0 ## searchers seen in the current physics frame
static var _searchers_last: int = 1 ## ... and in the previous one: the share is split between them
var climb_target: Vector2 = Vector2.INF
var searching: bool = false
var path: Array[Dictionary] = []
var expanded: int = 0

var _actor: CharacterBody2D
var _shape: CollisionShape2D
var _spec: Dictionary
var _floor: Callable
var _climb: Callable
var _origin: Vector2
var _goal: Vector2 = Vector2.INF
var _bounds: Rect2
var _heap: Array[Vector3] = []
var _cost: Dictionary = {}
var _parent: Dictionary = {}
var _links: Dictionary = {}
var _closed: Dictionary = {}
var _open_cells: Dictionary = {}
var _index: int = 0
var _retry: float = 0.0
var _age: float = 0.0
var _cached_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()


func configure(actor: CharacterBody2D, body: CollisionShape2D, spec: Dictionary, floor_check: Callable, climb_link: Callable = Callable()) -> void:
	_actor = actor
	_shape = body
	_spec = spec
	_floor = floor_check
	_climb = climb_link


func invalidate() -> void:
	searching = false
	path.clear()
	_heap.clear()
	_goal = Vector2.INF
	climb_target = Vector2.INF
	_retry = 0.0
	_age = 0.0


func can_occupy(point: Vector2, exclude: Array[RID] = [], mask: int = 1) -> bool:
	if _floor.is_valid() and not bool(_floor.call(point)):
		return false
	var query: PhysicsShapeQueryParameters2D = _query(point, exclude, mask)
	return _actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func segment_clear(from: Vector2, to: Vector2, exclude: Array[RID] = [], mask: int = 1) -> bool:
	if not can_occupy(to, exclude, mask):
		return false
	# Loaded land must cover the whole route, including longer smoothing/climb links.
	var samples: int = maxi(1, ceili(from.distance_to(to) / float(_spec["cell_size"])))
	if _floor.is_valid():
		for i: int in range(1, samples):
			if not bool(_floor.call(from.lerp(to, float(i) / samples))):
				return false
	var query: PhysicsShapeQueryParameters2D = _query(from, exclude, mask)
	query.motion = to - from
	var fractions: PackedFloat32Array = _actor.get_world_2d().direct_space_state.cast_motion(query)
	return fractions[0] >= 0.9999


func _query(point: Vector2, exclude: Array[RID], mask: int) -> PhysicsShapeQueryParameters2D:
	_cached_query.shape = _shape.shape
	_cached_query.transform = Transform2D(_actor.global_rotation, point) * _shape.transform
	_cached_query.margin = 0.25
	_cached_query.collision_mask = mask
	_cached_query.exclude = exclude
	_cached_query.motion = Vector2.ZERO
	return _cached_query


func direction_to(goal: Vector2, delta: float) -> Vector2:
	climb_target = Vector2.INF
	if not multiplayer.is_server():
		return Vector2.ZERO
	_retry -= delta
	_age += delta
	if not searching and not path.is_empty() and _goal != Vector2.INF and _goal.distance_to(goal) > float(_spec["target_repath_distance"]) and _age < float(_spec["refresh_seconds"]):
		_retarget(goal) ## the target moved: keep the route when its last leg still reaches the new goal
	if _goal == Vector2.INF or (not searching and (_goal.distance_to(goal) > float(_spec["target_repath_distance"]) or _age >= float(_spec["refresh_seconds"]))):
		_begin(goal)
	if searching:
		_search()
	if path.is_empty():
		if not searching and _retry <= 0.0:
			_begin(goal)
		return Vector2.ZERO
	var at: Vector2 = _actor.global_position
	while _index < path.size():
		var step: Dictionary = path[_index]
		var point: Vector2 = step["point"]
		if bool(step["climb"]):
			var takeoff: Vector2 = step["from"]
			if at.distance_to(takeoff) > 2.5:
				if not segment_clear(at, takeoff):
					invalidate()
					return Vector2.ZERO
				return (takeoff - at).normalized()
			climb_target = point
			return Vector2.ZERO
		if at.distance_to(point) < 3.0:
			_index += 1
			continue
		# Only shortcut ground edges; never skip a climb's takeoff or cross a new obstacle.
		var next: int = _index + 1
		while next < path.size() and not bool(path[next]["climb"]) and segment_clear(at, path[next]["point"]):
			_index = next
			point = path[next]["point"]
			next += 1
		if not segment_clear(at, point):
			invalidate()
			return Vector2.ZERO
		return (point - at).normalized()
	invalidate()
	return Vector2.ZERO


## Moves the end of the current path to `goal` when the last ground leg can still sweep there (one cast instead of a new search).
func _retarget(goal: Vector2) -> void:
	var last: Dictionary = path[path.size() - 1]
	if bool(last["climb"]):
		return
	var from: Vector2 = last["from"]
	if from.distance_to(goal) > float(_spec["search_margin"]) or not segment_clear(from, goal):
		return
	last["point"] = goal
	_goal = goal


func _begin(goal: Vector2) -> void:
	_origin = _actor.global_position
	_goal = goal
	_bounds = Rect2(_origin, Vector2.ZERO).expand(goal).grow(float(_spec["search_margin"]))
	_heap.clear()
	_cost.clear()
	_parent.clear()
	_links.clear()
	_closed.clear()
	_open_cells.clear()
	path.clear()
	_index = 0
	_age = 0.0
	expanded = 0
	searching = true
	_cost[Vector2i.ZERO] = 0.0
	_push(Vector2i.ZERO, _origin.distance_to(goal))
	_retry = float(_spec["retry_seconds"])


func _point(cell: Vector2i) -> Vector2:
	return _origin + Vector2(cell) * float(_spec["cell_size"])


func _cell_open(cell: Vector2i) -> bool:
	if not _open_cells.has(cell):
		var point: Vector2 = _point(cell)
		_open_cells[cell] = _bounds.has_point(point) and can_occupy(point)
	return bool(_open_cells[cell])


func _search() -> void:
	var began: int = Time.get_ticks_usec()
	var frame: int = Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_frame_used = 0
		_searchers_last = maxi(1, _searchers)
		_searchers = 0
	_searchers += 1
	var share: int = maxi(MIN_SHARE_USEC, mini(int(_spec["usec_per_frame"]), mini(SHARED_USEC / _searchers_last, SHARED_USEC - _frame_used)))
	_search_for(began, share)
	_frame_used += Time.get_ticks_usec() - began


func _search_for(began: int, share: int) -> void:
	var budget: int = int(_spec["nodes_per_frame"])
	while not _heap.is_empty() and budget > 0:
		if Time.get_ticks_usec() - began >= share:
			return
		var cell: Vector2i = _pop()
		if _closed.has(cell):
			continue
		_closed[cell] = true
		expanded += 1
		budget -= 1
		var from: Vector2 = _point(cell)
		if from.distance_to(_goal) <= float(_spec["cell_size"]) * 1.5 and segment_clear(from, _goal):
			_finish(cell)
			return
		if expanded >= int(_spec["max_nodes"]):
			break
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = cell + offset
			var to: Vector2 = _point(next)
			var climbing: bool = false
			if _cell_open(next) and segment_clear(from, to):
				pass
			elif _climb.is_valid():
				to = _climb.call(from, Vector2(offset) * float(_spec["cell_size"]))
				if not to.is_finite():
					continue
				next = Vector2i(((to - _origin) / float(_spec["cell_size"])).round())
				if not _cell_open(next):
					continue
				climbing = true
			else:
				continue
			if _closed.has(next):
				continue
			var cost: float = float(_cost[cell]) + from.distance_to(to) + (float(_spec["climb_penalty"]) if climbing else 0.0)
			if cost >= float(_cost.get(next, INF)):
				continue
			_cost[next] = cost
			_parent[next] = cell
			_links[next] = climbing
			_push(next, cost + to.distance_to(_goal))
	if not _heap.is_empty() and expanded < int(_spec["max_nodes"]):
		return
	searching = false
	_retry = float(_spec["retry_seconds"])


func _finish(cell: Vector2i) -> void:
	var reverse: Array[Dictionary] = [{"point": _goal, "from": _point(cell), "climb": false}]
	while _parent.has(cell):
		var previous: Vector2i = _parent[cell]
		reverse.append({"point": _point(cell), "from": _point(previous), "climb": bool(_links.get(cell, false))})
		cell = previous
	reverse.reverse()
	path = reverse
	searching = false
	_age = 0.0


func _push(cell: Vector2i, priority: float) -> void:
	var entry: Vector3 = Vector3(cell.x, cell.y, priority)
	var i: int = _heap.size()
	_heap.append(entry)
	while i > 0:
		var parent: int = (i - 1) / 2
		if _heap[parent].z <= priority:
			break
		_heap[i] = _heap[parent]
		i = parent
	_heap[i] = entry


func _pop() -> Vector2i:
	var first: Vector3 = _heap[0]
	var last: Vector3 = _heap.pop_back()
	if not _heap.is_empty():
		var i: int = 0
		while i * 2 + 1 < _heap.size():
			var child: int = i * 2 + 1
			if child + 1 < _heap.size() and _heap[child + 1].z < _heap[child].z:
				child += 1
			if last.z <= _heap[child].z:
				break
			_heap[i] = _heap[child]
			i = child
		_heap[i] = last
	return Vector2i(int(first.x), int(first.y))
