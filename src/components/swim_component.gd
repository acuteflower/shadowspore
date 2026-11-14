class_name SwimComponent
extends Node
## docs/schwimmen_konzept.md, step 1 (logic only): swimming on the water surface. A child of every Player. The owner decides (`step`), every peer
## sees the technique in `Player.swim`. The deep-water colliders (`RiverDepth`, group `river_depth`) are skipped by this body alone through
## collision exceptions, so animals, enemies and navigation stay out.

signal transition(kind: String) ## "enter" or "exit" (the clips of step 2 hang here)

var active: bool = false ## in swimming mode (hysteresis)
var state: int = SwimRules.NONE
var tired: bool = false
var blend: float = 0.0 ## 0 wading .. 1 swimming, eased over `blend_seconds`

var _body: CharacterBody2D
var _since: float = 0.0
var _deep_dist: float = 0.0 ## px walked through deep water without swimming yet (a brook is waded, a lake is swum)
var _deep_idle: float = 0.0 ## seconds standing in deep water without swimming yet
var _last_pos: Vector2 = Vector2.INF
var _scan: float = 0.0
var _excepted: Dictionary = {} ## instance id -> StaticBody2D


func setup(body: CharacterBody2D) -> void:
	_body = body


## Owner, every physics frame. `amount` is the depth share (0..1) under the feet, `water` whether she stands in river water at all, `allowed` whether
## the story and place permit swimming. Returns the technique (SwimRules.NONE while on foot).
func step(delta: float, amount: float, water: bool, allowed: bool, moving: bool, sprint_held: bool, stamina: StaminaComponent, wounded: bool) -> int:
	_since += delta
	tired = SwimRules.next_tired(tired, stamina.current, stamina.max_stamina)
	var here: Vector2 = _body.global_position if _body != null else Vector2.ZERO
	var moved: float = 0.0 if _last_pos == Vector2.INF else minf(here.distance_to(_last_pos), 40.0)
	_last_pos = here
	if active or not water or amount < float(SwimRules.cfg()["exit_amount"]):
		_deep_dist = 0.0
		_deep_idle = 0.0
	elif amount >= float(SwimRules.cfg()["enter_amount"]):
		_deep_dist += moved
		_deep_idle = _deep_idle + delta if moved < 0.2 else 0.0
	var wade: Dictionary = SwimRules.cfg().get("wade_through", {}) as Dictionary
	var committed: bool = active or _deep_dist >= float(wade.get("distance", 0.0)) or _deep_idle >= float(wade.get("idle_time", 0.0))
	var want: bool = water and committed and SwimRules.wants_swim(active, amount) and (allowed or active) ## a swimmer is never thrown out of the water by a ban, it only keeps her from starting
	if want != active and _since >= float(SwimRules.cfg()["min_state_time"]):
		active = want
		_since = 0.0
		transition.emit("enter" if active else "exit")
	var wanted_blend: float = 1.0 if active else 0.0
	var seconds: Dictionary = SwimRules.cfg()["blend_seconds"]
	var span: float = maxf(float(seconds["enter"] if active else seconds["exit"]), 0.01)
	blend = move_toward(blend, wanted_blend, delta / span)
	var pass_depth: bool = (water and (allowed or active)) or (_body != null and _body.has_meta("water_deck"))
	if pass_depth:
		_scan -= delta
		if _scan <= 0.0:
			_scan = float(SwimRules.cfg()["exception_scan"])
			sync_exceptions()
	elif not active:
		clear_exceptions()
	if not active:
		state = SwimRules.NONE
		return state
	state = SwimRules.technique(moving, sprint_held, stamina.current, tired, wounded)
	var rate: float = SwimRules.cost(state)
	if rate > 0.0:
		stamina.drain(rate, delta)
	return state


## Top speed in px/s for the current technique (0 on foot).
func speed(wounded: bool) -> float:
	return SwimRules.speed(state, tired, wounded)


## Lets this body pass every loaded deep-water collider (new chunks are picked up on the next scan).
func sync_exceptions() -> void:
	if _body == null:
		return
	for node: Node in get_tree().get_nodes_in_group("river_depth"):
		var wall: StaticBody2D = node as StaticBody2D
		if wall != null and not _excepted.has(wall.get_instance_id()):
			_body.add_collision_exception_with(wall)
			_excepted[wall.get_instance_id()] = wall
	for id: int in _excepted.keys():
		if not is_instance_valid(_excepted[id]):
			_excepted.erase(id)


func clear_exceptions() -> void:
	if _body == null:
		return
	for id: int in _excepted.keys():
		var wall: Variant = _excepted[id]
		if is_instance_valid(wall):
			_body.remove_collision_exception_with(wall as StaticBody2D)
	_excepted.clear()


func exception_count() -> int:
	return _excepted.size()


## Out of the water by other means (teleport, death, story): back on foot at once.
func reset() -> void:
	active = false
	state = SwimRules.NONE
	blend = 0.0
	_since = 0.0
	clear_exceptions()
