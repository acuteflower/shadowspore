class_name WildlifeEvents
extends Node
## Rare host-directed encounters between existing animals. All motion uses their
## reliable native action packets; fear, collisions and escape take precedence.
signal event_started(kind: String)
signal event_finished(kind: String,outcome: String)
var kind: String = ""
var last_outcome: String = ""
var _world: Variant ## avoid the WorldLevel -> player -> HUD -> WorldLevel preload cycle
var _a: Node2D
var _b: Node2D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spec: Dictionary
var _clock: float = 0.0
var _wait: float = 15.0
var _elapsed: float = 0.0
var _next: float = 0.0
var _retreats: int = 0
var _pounces: int = 0
var _pouncing: bool = false
var _cooldowns: Dictionary = {}

func setup(world: Variant) -> void:
	_world = world
	_rng.seed = world._map.world_seed+36219
	_spec = DataRegistry.table("wildlife_events")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(multiplayer.is_server())
	add_to_group("wildlife_events")

func _range(key: String) -> float:
	var span: Array = _spec[key]
	return _rng.randf_range(float(span[0]),float(span[1]))

func _process(delta: float) -> void:
	_clock += delta
	if kind != "":
		advance_event(delta)
		return
	_wait -= delta
	if _wait > 0.0: return
	_wait = _range("interval")
	if not _scene_clear(): return
	_choose_event()
	for id: int in _cooldowns.keys():
		if float(_cooldowns[id]) < _clock: _cooldowns.erase(id)

func _scene_clear() -> bool:
	if InputManager.ui_blocking or InputManager.map_open: return false
	for player: Player in Player.all:
		if player.story_lock or player.intro != null or player.fainting: return false
	return true

func _eligible(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not _world.navigation_floor(actor.global_position): return false
	if float(_cooldowns.get(actor.get_instance_id(),0.0))>_clock: return false
	var in_view: bool = false
	var view: Array = _spec.get("view_range",[75,340])
	for player: Player in Player.all:
		var distance: float = actor.global_position.distance_to(player.global_position)
		if distance < float(view[0]): return false
		if distance < float(view[1]): in_view = true
	for node: Node in get_tree().get_nodes_in_group("predators"):
		if actor.global_position.distance_to((node as Node2D).global_position)<170.0: return false
	return in_view

func _choose_event() -> void:
	var rabbits: Array[Node] = get_tree().get_nodes_in_group("wildlife")
	rabbits.shuffle()
	var prefer_hunt: bool = _rng.randf()<0.5
	var hunters: Array[Node] = get_tree().get_nodes_in_group("wildlife_hunters") ## fetched once, not per rabbit
	var birds: Array[Node] = get_tree().get_nodes_in_group("corvids")
	for node: Node in rabbits:
		var rabbit: WildRabbit = node as WildRabbit
		if rabbit == null or rabbit.captured or not _eligible(rabbit): continue
		if prefer_hunt:
			for hunter: WoodlandMammal in hunters:
				if not hunter._rest_hours() and not hunter._danger and not hunter._moving and _eligible(hunter) and hunter.global_position.distance_to(rabbit.global_position)<float(_spec["fox_hunt_range"]):
					if begin_event("fox_hunt",hunter,rabbit): return
		if rabbit._has_threat or rabbit._hopping or rabbit.state==WildRabbit.State.FLEE: continue
		for bird: WildCorvid in birds:
			if bird.species=="crow" and not bird._danger and not bird._rest_time() and bird._height<1.0 and not bird._moving and _eligible(bird) and bird.global_position.distance_to(rabbit.global_position)<float(_spec["rabbit_crow_range"]):
				if begin_event("rabbit_crow",rabbit,bird): return
		for other: Node in rabbits:
			var partner: WildRabbit = other as WildRabbit
			if partner != null and partner != rabbit and not partner.captured and not partner._has_threat and not partner._hopping and _eligible(partner) and partner.global_position.distance_to(rabbit.global_position)<float(_spec["rabbit_play_range"]):
				if begin_event("rabbit_play",rabbit,partner): return

func begin_event(event_kind: String,a: Node2D,b: Node2D) -> bool:
	if not multiplayer.is_server() or kind!="" or a==b or not is_instance_valid(a) or not is_instance_valid(b): return false
	if event_kind not in ["fox_hunt","rabbit_crow","rabbit_play"]: return false
	if event_kind=="fox_hunt" and (not a is WoodlandMammal or not b is WildRabbit): return false
	if event_kind=="rabbit_crow" and (not a is WildRabbit or not b is WildCorvid): return false
	if event_kind=="rabbit_play" and (not a is WildRabbit or not b is WildRabbit): return false
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a.global_position,b.global_position,1)
	if not a.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return false
	kind = event_kind
	_a = a
	_b = b
	_elapsed = 0.0
	_next = 0.5
	_retreats = 0
	_pounces = 0
	_pouncing = false
	_a.set("ambient_event",true)
	if kind!="fox_hunt": _b.set("ambient_event",true)
	if kind=="fox_hunt":
		(a as WoodlandMammal)._issue(WoodlandMammal.Mood.LISTEN,0.5,(b.global_position-a.global_position).angle())
	else:
		(a as WildRabbit)._set_mood.rpc(WildRabbit.State.ALERT,0.5,(b.global_position-a.global_position).angle())
		if b is WildCorvid: (b as WildCorvid)._set_mood(WildCorvid.State.WATCH,1.0)
	event_started.emit(kind)
	return true

func advance_event(delta: float) -> void:
	if kind=="": return
	_elapsed += delta
	_next -= delta
	if not is_instance_valid(_a) or not is_instance_valid(_b) or _a.is_queued_for_deletion() or _b.is_queued_for_deletion():
		finish_event("departed")
		return
	if not _scene_clear() or not _world.navigation_floor(_a.global_position) or not _world.navigation_floor(_b.global_position):
		finish_event("interrupted")
		return
	if _elapsed > float(_spec.get("maximum_duration",8.0)):
		finish_event("escaped" if kind=="fox_hunt" else "finished")
		return
	if kind=="fox_hunt": _hunt()
	else: _play()

func _play() -> void:
	var rabbit: WildRabbit = _a as WildRabbit
	if rabbit._has_threat or (_b is WildCorvid and (_b as WildCorvid)._danger) or (_b is WildRabbit and (_b as WildRabbit)._has_threat):
		finish_event("startled")
		return
	var distance: float = _a.global_position.distance_to(_b.global_position)
	if kind=="rabbit_crow":
		var bird: WildCorvid = _b as WildCorvid
		if bird.state==WildCorvid.State.FLY:
			finish_event("crow_flew_off")
			return
		if distance < 25.0 or (_retreats>=2 and _elapsed>2.0) or _elapsed>4.5:
			bird._threat = rabbit.global_position
			if bird._take_wing(true,false): finish_event("crow_flew_off")
			else: finish_event("crow_stayed")
			return
		if distance<55.0 and not bird._moving and _next<=0.0:
			bird._walk((bird.global_position-rabbit.global_position).normalized())
			_retreats += 1
	else:
		var partner: WildRabbit = _b as WildRabbit
		if _elapsed>3.2:
			rabbit._set_state(WildRabbit.State.GRAZE,2.0)
			partner._set_state(WildRabbit.State.GROOM,2.0)
			finish_event("played")
			return
		if not partner._hopping and _next<=0.0:
			partner._try_hop((partner.global_position-rabbit.global_position).rotated(0.7).normalized(),false)
	if not rabbit._hopping and _next<=0.0:
		rabbit._try_hop((_b.global_position-rabbit.global_position).normalized(),false)
		_next = 0.6

func _hunt() -> void:
	var fox: WoodlandMammal = _a as WoodlandMammal
	var rabbit: WildRabbit = _b as WildRabbit
	if fox._danger or rabbit.captured:
		finish_event("startled")
		return
	var distance: float = fox.global_position.distance_to(rabbit.global_position)
	if _pouncing and distance<10.0 and fox._elapsed>0.12:
		rabbit.caught_by_predator()
		# Let the existing pounce land; native SPECIAL -> FORAGE follows it.
		finish_event("caught")
		return
	if fox._moving or _next>0.0: return
	if _pouncing:
		_pouncing = false
		if _pounces>=2:
			fox._issue(WoodlandMammal.Mood.FORAGE,2.0)
			finish_event("escaped")
			return
	if distance<31.0:
		var target: Vector2 = rabbit.global_position
		if rabbit._hopping: target = target.lerp(rabbit._hop_end,0.5)
		if fox._can_step(target) and not fox.test_move(fox.global_transform,target-fox.global_position):
			fox._move_action(WoodlandMammal.Mood.SPECIAL,target,0.65)
			_pounces += 1
			_pouncing = true
			return
	var step: Vector2 = (rabbit.global_position-fox.global_position).limit_length(minf(44.0,maxf(8.0,distance-21.0)))
	var end: Vector2 = fox.global_position+step
	if fox._can_step(end) and fox._can_step(fox.global_position+step*0.5) and not fox.test_move(fox.global_transform,step):
		fox._safe_time = 10.0
		fox._move_action(WoodlandMammal.Mood.FLEE,end,maxf(0.2,step.length()/float(fox._spec["run_speed"])))
	else:
		finish_event("escaped")

func finish_event(outcome: String) -> void:
	var finished: String = kind
	for actor: Node2D in [_a,_b]:
		if is_instance_valid(actor):
			actor.set("ambient_event",false)
			_cooldowns[actor.get_instance_id()] = _clock+_range("actor_cooldown")
	_a = null
	_b = null
	kind = ""
	last_outcome = outcome
	_wait = _range("interval")
	event_finished.emit(finished,outcome)

func _exit_tree() -> void:
	for actor: Node2D in [_a,_b]:
		if is_instance_valid(actor): actor.set("ambient_event",false)
