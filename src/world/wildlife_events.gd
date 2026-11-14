class_name WildlifeEvents
extends Node
## Rare host-directed encounters between existing animals. All motion uses their
## reliable native action packets; fear, collisions and escape take precedence.
signal event_started(kind: String)
signal event_finished(kind: String,outcome: String)
var story_hold: bool = false
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
	if story_hold or _is_boss_present(): return false
	if InputManager.ui_blocking or InputManager.map_open: return false
	for player: Player in Player.all:
		if player.story_lock or player.intro != null or player.fainting: return false
	return true

func _is_boss_present() -> bool:
	for node: Node in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			return true
	return false

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
				if not hunter._rest_hours() and not hunter._danger and not hunter._moving and hunter._climb_height < 0.5 and _eligible(hunter) and hunter.global_position.distance_to(rabbit.global_position)<float(_spec["fox_hunt_range"]):
					if begin_event("fox_hunt",hunter,rabbit): return
		if rabbit._has_threat or rabbit._hopping or rabbit.state==WildRabbit.State.FLEE: continue
		for bird: WildCorvid in birds:
			if bird.species=="crow" and not bird._danger and not bird._rest_time() and bird._height<1.0 and not bird._moving and _eligible(bird) and bird.global_position.distance_to(rabbit.global_position)<float(_spec["rabbit_crow_range"]):
				if begin_event("rabbit_crow",rabbit,bird): return
		for other: Node in rabbits:
			var partner: WildRabbit = other as WildRabbit
			if partner != null and partner != rabbit and not partner.captured and not partner._has_threat and not partner._hopping and _eligible(partner) and partner.global_position.distance_to(rabbit.global_position)<float(_spec["rabbit_play_range"]):
				if begin_event("rabbit_play",rabbit,partner): return
	_choose_desert_event(hunters)


func _choose_desert_event(hunters: Array[Node]) -> void:
	var mammals: Array[Node] = get_tree().get_nodes_in_group("woodland_mammals")
	mammals.shuffle()
	var tinies: Array[Node] = get_tree().get_nodes_in_group("wild_animals")
	for node: Node in mammals:
		var m: WoodlandMammal = node as WoodlandMammal
		if m == null or m.captured or m.mood == WoodlandMammal.Mood.HIDDEN or m._danger or m._moving or not _eligible(m):
			continue
		if m.species == "jerboa" and not m._rest_hours():
			for h_node: Node in hunters:
				var fennec: WoodlandMammal = h_node as WoodlandMammal
				if fennec != null and fennec.species == "fennec" and not fennec._rest_hours() and not fennec._danger and not fennec._moving and _eligible(fennec) and fennec.global_position.distance_to(m.global_position) < float(_spec.get("fennec_hunt_range", 120.0)):
					if begin_event("fennec_hunt", fennec, m):
						return
		if m.species == "agama" and not m._rest_hours():
			for other_node: Node in mammals:
				var rival: WoodlandMammal = other_node as WoodlandMammal
				if rival != null and rival != m and rival.species == "agama" and rival.mood != WoodlandMammal.Mood.HIDDEN and not rival._danger and not rival._moving and _eligible(rival) and rival.global_position.distance_to(m.global_position) < float(_spec.get("agama_duel_range", 72.0)):
					if begin_event("agama_duel", m, rival):
						return
			for t_node: Node in tinies:
				var beetle: TinyWildlife = t_node as TinyWildlife
				if beetle != null and beetle.species == "scarab" and beetle.state != TinyWildlife.State.WITHDRAW and _eligible(beetle) and beetle.global_position.distance_to(m.global_position) < float(_spec.get("agama_scarab_range", 68.0)):
					if begin_event("agama_scarab", m, beetle):
						return
		if m.species in ["jerboa", "fennec"] and not m._rest_hours():
			for p_node: Node in mammals:
				var playmate: WoodlandMammal = p_node as WoodlandMammal
				if playmate != null and playmate != m and playmate.species == m.species and playmate.mood != WoodlandMammal.Mood.HIDDEN and not playmate._danger and not playmate._moving and _eligible(playmate) and playmate.global_position.distance_to(m.global_position) < float(_spec.get("desert_play_range", 66.0)):
					if begin_event("desert_play", m, playmate):
						return
	for t_a: Node in tinies:
		var s1: TinyWildlife = t_a as TinyWildlife
		if s1 == null or s1.species != "scarab" or s1.state == TinyWildlife.State.WITHDRAW or not _eligible(s1):
			continue
		for t_b: Node in tinies:
			var s2: TinyWildlife = t_b as TinyWildlife
			if s2 != null and s2 != s1 and s2.species == "scarab" and s2.state != TinyWildlife.State.WITHDRAW and _eligible(s2) and s2.global_position.distance_to(s1.global_position) < 42.0:
				if begin_event("scarab_tussle", s1, s2):
					return


func begin_event(event_kind: String,a: Node2D,b: Node2D) -> bool:
	if story_hold or _is_boss_present(): return false
	if not multiplayer.is_server() or kind!="" or a==b or not is_instance_valid(a) or not is_instance_valid(b): return false
	if event_kind not in ["fox_hunt","rabbit_crow","rabbit_play","fennec_hunt","agama_duel","agama_scarab","scarab_tussle","desert_play"]: return false
	if event_kind=="fox_hunt" and (not a is WoodlandMammal or not b is WildRabbit): return false
	if event_kind=="rabbit_crow" and (not a is WildRabbit or not b is WildCorvid): return false
	if event_kind=="rabbit_play" and (not a is WildRabbit or not b is WildRabbit): return false
	if event_kind in ["fennec_hunt", "agama_duel", "desert_play"] and (not a is WoodlandMammal or not b is WoodlandMammal): return false
	if event_kind=="agama_scarab" and (not a is WoodlandMammal or not b is TinyWildlife): return false
	if event_kind=="scarab_tussle" and (not a is TinyWildlife or not b is TinyWildlife): return false
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
	if kind not in ["fox_hunt", "fennec_hunt"]: _b.set("ambient_event",true)
	if kind in ["fox_hunt", "fennec_hunt"]:
		(a as WoodlandMammal)._issue(WoodlandMammal.Mood.LISTEN,0.5,(b.global_position-a.global_position).angle())
	elif kind == "agama_duel":
		(a as WoodlandMammal)._issue(WoodlandMammal.Mood.BARK, 1.1, (b.global_position - a.global_position).angle())
		(b as WoodlandMammal)._issue(WoodlandMammal.Mood.ALERT, 0.55, (a.global_position - b.global_position).angle())
	elif kind == "agama_scarab":
		(a as WoodlandMammal)._issue(WoodlandMammal.Mood.ALERT, 0.45, (b.global_position - a.global_position).angle())
	elif kind == "desert_play":
		(a as WoodlandMammal)._issue(WoodlandMammal.Mood.ALERT, 0.4, (b.global_position - a.global_position).angle())
		(b as WoodlandMammal)._issue(WoodlandMammal.Mood.ALERT, 0.4, (a.global_position - b.global_position).angle())
	elif kind == "scarab_tussle":
		var mid_s: Vector2 = (a.global_position + b.global_position) * 0.5
		(a as TinyWildlife)._act.rpc(TinyWildlife.State.MOVE, a.global_position, mid_s + (a.global_position - mid_s).normalized() * 3.0, 1.1, "", Vector2.ZERO, 0.0)
		(b as TinyWildlife)._act.rpc(TinyWildlife.State.MOVE, b.global_position, mid_s + (b.global_position - mid_s).normalized() * 3.0, 1.1, "", Vector2.ZERO, 0.0)
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
		finish_event("escaped" if kind in ["fox_hunt", "fennec_hunt"] else "finished")
		return
	match kind:
		"fox_hunt":
			_hunt()
		"fennec_hunt":
			_fennec_hunt()
		"agama_duel", "agama_scarab", "desert_play", "scarab_tussle":
			_desert_encounter()
		_:
			_play()

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
			bird._hop_step((bird.global_position-rabbit.global_position).normalized())
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
		var close_stalk: bool = distance < 58.0
		var hunt_mood: WoodlandMammal.Mood = WoodlandMammal.Mood.STALK if close_stalk else WoodlandMammal.Mood.CHASE
		var speed: float = float(fox._spec.get("stalk_speed", 22.0)) * 1.4 if close_stalk else float(fox._spec["run_speed"])
		fox._move_action(hunt_mood,end,maxf(0.2,step.length()/speed))
	else:
		finish_event("escaped")


func _fennec_hunt() -> void:
	var fennec: WoodlandMammal = _a as WoodlandMammal
	var jerboa: WoodlandMammal = _b as WoodlandMammal
	if fennec._danger or jerboa.captured or jerboa.mood == WoodlandMammal.Mood.HIDDEN:
		finish_event("escaped" if jerboa.mood == WoodlandMammal.Mood.HIDDEN else "startled")
		return
	var distance: float = fennec.global_position.distance_to(jerboa.global_position)
	if _pouncing and distance < 9.5 and fennec._elapsed > 0.14:
		jerboa.caught_by_predator()
		finish_event("caught")
		return
	if fennec._moving or _next > 0.0:
		return
	if _pouncing:
		_pouncing = false
		if _pounces >= 2:
			fennec._issue(WoodlandMammal.Mood.FORAGE, 2.0)
			finish_event("escaped")
			return
	if distance < 29.0:
		var target: Vector2 = jerboa.global_position
		if jerboa._moving:
			target = target.lerp(jerboa._end, 0.35)
		if fennec._can_step(target) and not fennec.test_move(fennec.global_transform, target - fennec.global_position):
			fennec._move_action(WoodlandMammal.Mood.SPECIAL, target, float(fennec._spec.get("pounce_seconds", 0.68)))
			_pounces += 1
			_pouncing = true
			return
	var step: Vector2 = (jerboa.global_position - fennec.global_position).limit_length(minf(38.0, maxf(8.0, distance - 19.0)))
	var end: Vector2 = fennec.global_position + step
	if fennec._can_step(end) and fennec._can_step(fennec.global_position + step * 0.5) and not fennec.test_move(fennec.global_transform, step):
		fennec._safe_time = 10.0
		var close_stalk: bool = distance < 54.0
		var hunt_mood: WoodlandMammal.Mood = WoodlandMammal.Mood.STALK if close_stalk else WoodlandMammal.Mood.CHASE
		var speed: float = float(fennec._spec.get("stalk_speed", 22.0)) * 1.35 if close_stalk else float(fennec._spec["run_speed"])
		fennec._move_action(hunt_mood, end, maxf(0.2, step.length() / speed))
	else:
		finish_event("escaped")


func _desert_encounter() -> void:
	if (_a is WoodlandMammal and (_a as WoodlandMammal)._danger) or (_b is WoodlandMammal and (_b as WoodlandMammal)._danger):
		finish_event("startled")
		return
	if kind == "agama_duel":
		var ag_a: WoodlandMammal = _a as WoodlandMammal
		var ag_b: WoodlandMammal = _b as WoodlandMammal
		if _elapsed > 3.1:
			ag_b._step((ag_b.global_position - ag_a.global_position).normalized(), WoodlandMammal.Mood.WALK)
			ag_a._issue(WoodlandMammal.Mood.REST, 2.0, (ag_b.global_position - ag_a.global_position).angle())
			finish_event("yielded")
			return
		if _next <= 0.0 and not ag_b._moving and _retreats == 0:
			ag_b._issue(WoodlandMammal.Mood.BARK, 1.15, (ag_a.global_position - ag_b.global_position).angle())
			_retreats = 1
			_next = 1.2
	elif kind == "agama_scarab":
		var agama: WoodlandMammal = _a as WoodlandMammal
		var scarab: TinyWildlife = _b as TinyWildlife
		var dist: float = agama.global_position.distance_to(scarab.global_position)
		if scarab.state == TinyWildlife.State.WITHDRAW:
			if not agama._moving and _elapsed > 1.8:
				agama._issue(WoodlandMammal.Mood.ALERT, 1.6, (scarab.global_position - agama.global_position).angle() + 0.25)
				finish_event("burrowed")
			return
		if dist <= 15.0:
			scarab._choose(TinyWildlife.State.WITHDRAW, scarab._range("withdraw_seconds"))
			agama._issue(WoodlandMammal.Mood.FORAGE, 0.85, (scarab.global_position - agama.global_position).angle())
			_next = 0.9
			return
		if not agama._moving and _next <= 0.0:
			var rush: Vector2 = (scarab.global_position - agama.global_position).limit_length(maxf(8.0, dist - 11.0))
			var rush_to: Vector2 = agama.global_position + rush
			if agama._can_step(rush_to) and not agama.test_move(agama.global_transform, rush):
				agama._move_action(WoodlandMammal.Mood.CHASE, rush_to, maxf(0.22, rush.length() / float(agama._spec["run_speed"])))
				_next = 0.35
			else:
				finish_event("escaped")
	elif kind == "scarab_tussle":
		var sc_a: TinyWildlife = _a as TinyWildlife
		var sc_b: TinyWildlife = _b as TinyWildlife
		if sc_a.state == TinyWildlife.State.WITHDRAW or sc_b.state == TinyWildlife.State.WITHDRAW:
			finish_event("startled")
			return
		if _elapsed > 2.6:
			var away_pt: Vector2 = (sc_b.global_position + (sc_b.global_position - sc_a.global_position).normalized() * 10.0).round()
			sc_b._act.rpc(TinyWildlife.State.MOVE, sc_b.global_position, away_pt, 1.6, "", Vector2.ZERO, 0.0)
			finish_event("settled")
	elif kind == "desert_play":
		var p_a: WoodlandMammal = _a as WoodlandMammal
		var p_b: WoodlandMammal = _b as WoodlandMammal
		if _elapsed > 3.4:
			p_a._issue(WoodlandMammal.Mood.GROOM, 1.8)
			p_b._issue(WoodlandMammal.Mood.REST, 1.8)
			finish_event("played")
			return
		if _next <= 0.0:
			if not p_a._moving:
				p_a._step((p_b.global_position - p_a.global_position).rotated(0.55).normalized(), WoodlandMammal.Mood.WALK)
			if not p_b._moving:
				p_b._step((p_a.global_position - p_b.global_position).rotated(-0.65).normalized(), WoodlandMammal.Mood.WALK)
			_next = 0.65

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
