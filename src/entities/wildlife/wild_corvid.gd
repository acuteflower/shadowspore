class_name WildCorvid
extends CharacterBody2D
## Ground-foraging corvids with flock alarms, watch turns, social spacing and real tree perches.
## Host chooses complete actions. Reliable packets replay motion and height on peers, including joins.

enum State { IDLE, PECK, WALK, PREEN, WATCH, SOCIAL, FLY, ROOST, FEED } ## FEED: eating from a hand (docs/pet_konzept.md)

var species: String = "crow":
	set(value):
		species = value
		if is_node_ready():
			_load_species()
var appearance: int = 0
var flock_id: String = ""
var home: Vector2 = Vector2.ZERO
var facing: float = 0.0
var ambient_event: bool = false
var pet_key: String = "" ## who this bird is, for the bond with a player (PetRegistry); empty = never tamed (town visitors)
var offered_peer: int = 0 ## the player it offers to take food from right now (every peer knows it: the prompt "E FÜTTERN")
var visit_roof: bool = false ## a visitor of the town (TownCritters): it wants a roof, not a tree or a log
var state: State = State.IDLE
var _spec: Dictionary
var _population: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _duration: float = 2.0
var _moving: bool = false
var _start: Vector2
var _end: Vector2
var _bend: Vector2
var _height_from: float = 0.0
var _height_to: float = 0.0
var _cruise: float = 0.0
var _height: float = 0.0
var _perch_path: String = ""
var _sense_left: float = 0.0
var _call_left: float = 10.0
var _call_pose: float = 0.0
var _caution_left: float = 0.0
var _panic_delay: float = -1.0
var _threat: Vector2 = Vector2.ZERO
var _danger: bool = false
var _rally: Vector2 = Vector2.INF
var _shadow: Node2D
var _pet: PetBehavior ## host only, crows and ravens with a key
var _ring: Sprite2D ## the leg ring of a registered bird (tools/art_pet_marks.py), tinted with its colour
var rider: int = 0 ## peer of the player whose shoulder it sits on (0 = none), set by `_ride` on every peer
var companion_peer: int = 0 ## host: the player this bird is the companion of: it does not flee from anyone
var territory: Vector2 = Vector2.INF ## host: the place of a registered bird right now (PetSchedule): its walks lean towards it
var _calls: Array[AudioStream] = []

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _voice: AudioStreamPlayer2D = $Voice


func _ready() -> void:
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	_load_species()
	_start = global_position
	_end = global_position
	_population = get_parent().get_parent()
	_rng.seed = hash(name) + hash(flock_id)
	add_to_group("corvids")
	_shadow = Node2D.new()
	_shadow.show_behind_parent = true
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)
	if bool(_spec.get("pet", false)) and pet_key != "":
		var spot: PetFeedSpot = PetFeedSpot.new()
		spot.name = "PetFeedSpot"
		add_child(spot)
		var tag: PetTag = PetTag.new()
		tag.name = "PetTag"
		add_child(tag)
		_ring = Sprite2D.new()
		_ring.name = "Ring"
		_ring.texture = load("res://assets/wildlife/pet_marks.png") as Texture2D
		_ring.hframes = 50
		_ring.vframes = 48
		_ring.centered = false
		_ring.offset = Vector2(-24, -35)
		_ring.material = _sprite.material
		_ring.visible = false
		add_child(_ring)
	if multiplayer.is_server():
		if bool(_spec.get("pet", false)) and pet_key != "":
			_pet = PetBehavior.new(self)
		_duration = _range("idle_seconds")
		_call_left = _range("call_seconds")
		_sense_left = _rng.randf_range(0.0, float(_spec["sense_interval"]))
	else:
		_request_snapshot.rpc_id(1)


func _load_species() -> void:
	_spec = DataRegistry.get_entry("wildlife", species)
	if _sprite != null and _spec.has("texture"):
		_sprite.texture = load(String(_spec["texture"])) as Texture2D
	_calls.clear()
	for i: int in 2:
		_calls.append(load("res://assets/audio/wildlife/%s_%d.wav" % [species, i]) as AudioStream)


func _exit_tree() -> void:
	if _voice != null:
		_voice.stop()
		_voice.stream = null
	_calls.clear()


func _rest_time() -> bool:
	return TimeManager.is_night() and bool(_spec["night_roost"])


func _preferred_cruise(_panic: bool, _goal_height: float) -> float:
	return float(_spec["flight_height"])


func _range(key: String) -> float:
	var values: Array = _spec[key]
	return _rng.randf_range(float(values[0]), float(values[1]))


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if rider != 0:
		_sit_on_shoulder()
		return
	_call_pose = maxf(0.0, _call_pose - delta)
	_caution_left = maxf(0.0, _caution_left - delta)
	if multiplayer.is_server():
		_sense_left -= delta
		if _sense_left <= 0.0:
			_sense_left = float(_spec["sense_interval"])
			_sense()
		if _panic_delay >= 0.0:
			_panic_delay -= delta
			if _panic_delay <= 0.0:
				_panic_delay = -1.0
				if state != State.FLY:
					_take_wing(true, false)
		if not _moving and (not ambient_event or _danger):
			_think()
		_call_left -= delta
		if _call_left <= 0.0 and state != State.FLY:
			_request_call(false)
	if _moving:
		_advance()


## Every peer: the bird sits on a player's shoulder (peer != 0) or leaves it (0). It is pinned to her every physics frame.
@rpc("authority", "call_local", "reliable")
func _ride(peer: int) -> void:
	rider = peer
	_moving = false
	if peer == 0:
		_height = 0.0
		state = State.WATCH
		_elapsed = 0.0
		_duration = 1.0
	else:
		state = State.ROOST
		_perch_path = ""
		_start = global_position
		_end = global_position


func _carrier() -> Player:
	for player: Player in Player.all:
		if player.name == str(rider):
			return player
	return null


func _sit_on_shoulder() -> void:
	var carrier: Player = _carrier()
	if carrier == null:
		return
	var cfg: Dictionary = PetRules.table()["companion"] as Dictionary
	var off: Array = cfg["shoulder_offset"] as Array
	global_position = carrier.global_position + Vector2(float(off[0]), float(off[1]))
	_height = float(cfg["shoulder_height"])
	state = State.ROOST
	if carrier.velocity.length() > 5.0:
		facing = carrier.velocity.angle()


## Host: fly to a point (the whistle, the companion following). The landing is not refused for being close to a player.
func fly_to(goal: Vector2) -> bool:
	if not multiplayer.is_server() or state == State.FLY or rider != 0:
		return false
	if _pet != null:
		_pet.reset()
	if _population.has_method("release_perch"):
		_population.call("release_perch", self)
	var dist: float = global_position.distance_to(goal)
	if dist < 6.0:
		return false
	var bend: Vector2 = (goal - global_position).orthogonal().normalized() * minf(40.0, dist * 0.15)
	if _population.has_method("route_bend"):
		bend = _population.call("route_bend", global_position, goal, bend)
	var cruise: float = maxf(float(_spec["flight_height"]), _height + float(_spec["flight_clearance"]))
	if _population.has_method("flight_clearance"):
		cruise = maxf(cruise, float(_population.call("flight_clearance", global_position, goal, bend)))
	var duration: float = maxf(float(_spec["flight_seconds_min"]), (dist + bend.length() * 0.7) / float(_spec["flight_speed"]))
	_act.rpc(State.FLY, duration, (goal - global_position).angle(), global_position, goal, bend, _height, 0.0, cruise, "", 0.0)
	return true


func _process(_delta: float) -> void:
	var col: int = 0
	match state:
		State.PECK:
			col = 4 + int(_elapsed * 5.0) % 6
		State.FEED:
			col = 4 + int(_elapsed * 6.5) % 6 ## pecking at the offered food
		State.WALK:
			col = 10 + int(_elapsed * 9.0) % 6
		State.PREEN, State.SOCIAL:
			col = 16 + int(_elapsed * 4.5) % 6
		State.WATCH, State.ROOST:
			col = 22 + int(_elapsed * 2.2) % 4
		State.FLY:
			var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
			var takeoff: float = float(_spec.get("takeoff_fraction", 0.18))
			var landing: float = float(_spec.get("landing_fraction", 0.8))
			if t < takeoff:
				col = 44 + mini(5, int(t / takeoff * 6.0))
			elif t > landing:
				col = 38 + mini(5, int((t - landing) / (1.0 - landing) * 6.0))
			elif t > float(_spec.get("glide_from", 0.45)) and t < float(_spec.get("glide_to", 0.62)):
				col = 34 ## a short glide between wing beats
			else:
				col = 30 + int(_elapsed * float(_spec["flap_fps"])) % 8
		_:
			col = int(_elapsed * 2.5) % 4
	if _call_pose > 0.0 and state != State.FLY:
		col = 26 + int(_call_pose * 10.0) % 4
	var build: int = int(_spec["build_offset"]) + clampi(appearance, 0, 2)
	var sector: int = posmod(roundi(facing / (PI / 4.0)), 8)
	_sprite.frame = (build * 8 + sector) * 50 + col
	_sprite.position.y = -roundf(_height)
	_sprite.z_index = 5 if state == State.FLY and _height > 16.0 else 0
	if rider != 0:
		_sprite.z_index = 1 ## in front of the player it sits on
	if _ring != null:
		var registry: PetRegistry = PetRegistry.of(get_tree())
		_ring.visible = registry != null and registry.has_record(pet_key) and state != State.FLY
		if _ring.visible:
			var rings: Array = (PetRules.table()["register"] as Dictionary)["ring_colors"] as Array
			_ring.modulate = Color(String(rings[int(registry.record(pet_key)["ring"]) % rings.size()]))
			_ring.frame = _sprite.frame
			_ring.position.y = _sprite.position.y
			_ring.z_index = _sprite.z_index
	_shadow.queue_redraw()


func _draw_shadow() -> void:
	if not _perch_path.is_empty() and state != State.FLY:
		return
	var fade: float = clampf(1.0 - _height / 280.0, 0.12, 1.0)
	_shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 - minf(_height / 400.0, 0.4), 0.3))
	_shadow.draw_circle(Vector2.ZERO, 7.0 if species == "raven" else 5.0, Color(0.03, 0.025, 0.07, 0.23 * fade))


func _sense() -> void:
	if companion_peer != 0:
		return ## a companion trusts everybody who walks with it
	_danger = false
	if state == State.FLY:
		return
	if not _perch_path.is_empty():
		var tree: Node = get_node_or_null(NodePath(_perch_path))
		if tree == null or bool(tree.call("is_depleted")):
			_take_wing(true)
			return
	var nearest: float = INF
	var flush: bool = false
	var candidates: Array[Node] = []
	candidates.append_array(Player.all)
	candidates.append_array(get_tree().get_nodes_in_group("predators"))
	candidates.append_array(get_tree().get_nodes_in_group("wildlife_hunters"))
	for node: Node in candidates:
		var actor: Node2D = node as Node2D
		if actor == null:
			continue
		var alert: float = float(_spec["alert_range"])
		var flee: float = float(_spec["flee_range"])
		var noisy: bool = false
		if actor is Player:
			var player: Player = actor as Player
			if player.health.current <= 0.0:
				continue
			if _pet != null and _pet.tolerates(player, global_position.distance_to(player.global_position), float(_spec["sense_interval"])):
				continue ## it trusts her right now: food in her hand, still and quiet (PetBehavior)
			var calm: float = TownManager.calm_at(get_tree(), global_position) ## used to the town's people
			if species == "crow" or species == "raven":
				calm *= 1.0 - player.talismans.corvid_calm() ## the Rissfeder: they take her for one of their own
			alert *= calm
			flee *= calm
			if player.stealth.sneaking:
				alert *= float(_spec["sneak_multiplier"])
				flee *= float(_spec["sneak_multiplier"])
			if player.sprinting:
				alert *= float(_spec["sprint_multiplier"])
				flee *= float(_spec["sprint_multiplier"])
			noisy = player.attack.is_swinging() and global_position.distance_to(player.global_position) < float(_spec["swing_range"]) * player.attack.noise_scale()
		else:
			var health: HealthComponent = actor.get_node_or_null("HealthComponent") as HealthComponent
			if health != null and health.current <= 0.0:
				continue
			alert *= 1.4
			flee *= 1.4
		if _height > 20.0:
			flee *= float(_spec["perch_fear_multiplier"])
		var distance: float = global_position.distance_to(actor.global_position)
		if distance > maxf(alert, float(_spec["swing_range"]) if noisy else 0.0):
			continue
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, actor.global_position, 1)
		if _height < 20.0 and not noisy and not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		_danger = true
		flush = flush or noisy or distance < flee
		if distance < nearest:
			nearest = distance
			_threat = actor.global_position
	if _danger:
		_caution_left = float(_spec["calm_seconds"])
		if flush:
			_take_wing(true)
		elif not _moving:
			if state != State.WATCH:
				_set_mood(State.WATCH, _range("watch_seconds"))
			facing = (_threat - global_position).angle()


func _think() -> void:
	if _panic_delay >= 0.0:
		return
	if _danger or _caution_left > 0.0:
		if _elapsed >= _duration and state != State.WATCH:
			_set_mood(State.WATCH, _range("watch_seconds"))
		return
	if _pet != null and _pet.drive(get_physics_process_delta_time()):
		return
	if _elapsed < _duration:
		return
	if _rest_time():
		if not _perch_path.is_empty():
			_set_mood(State.ROOST, _range("roost_seconds"))
			return
		if _take_wing(false):
			return
		_set_mood(State.ROOST, _range("roost_seconds"))
		return
	if not _perch_path.is_empty():
		if _rng.randf() < 0.6:
			_set_mood(State.PREEN if _rng.randf() < 0.45 else State.WATCH, _range("preen_seconds"))
		else:
			_take_wing(false, false, true)
		return
	var neighbours: Array[Node] = get_tree().get_nodes_in_group("corvids")
	for node: Node in neighbours:
		var other: WildCorvid = node as WildCorvid
		if other != self and other.state != State.FLY and other._height < 1.0 and global_position.distance_to(other.global_position) < float(_spec["personal_space"]):
			if other.species == "raven" or species == "crow":
				_walk((global_position - other.global_position).normalized())
				return
	var roll: float = _rng.randf()
	if roll < float(_spec["relocate_chance"]):
		if _take_wing(false):
			return
	if roll < 0.45:
		var center: Vector2 = _flock_center()
		var direction: Vector2 = (center - global_position).normalized() if global_position.distance_to(center) > 80.0 else Vector2.from_angle(_rng.randf() * TAU)
		_walk(direction)
	elif roll < 0.45 + float(_spec["social_chance"]) and _socialise(neighbours):
		return
	else:
		_set_mood(State.PECK if _rng.randf() < 0.72 else State.PREEN, _range("peck_seconds"))


func _flock_center() -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var bird: WildCorvid = node as WildCorvid
		if bird.flock_id == flock_id and bird.state != State.FLY:
			sum += bird.global_position
			count += 1
	if territory.is_finite():
		return territory
	return sum / count if count > 0 else home


func _socialise(neighbours: Array[Node]) -> bool:
	for node: Node in neighbours:
		var other: WildCorvid = node as WildCorvid
		if other != self and other.flock_id == flock_id and other.state in [State.IDLE, State.PECK, State.PREEN] and global_position.distance_to(other.global_position) < 42.0:
			facing = (other.global_position - global_position).angle()
			other.facing = (global_position - other.global_position).angle()
			_set_mood(State.SOCIAL, 1.6)
			other._set_mood(State.SOCIAL, 1.6)
			return true
	return false


func _walk(direction: Vector2) -> void:
	var distance: float = _range("walk_distance")
	for angle: float in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var step: Vector2 = direction.rotated(angle) * distance
		if not test_move(global_transform, step) and _can_land(global_position + step):
			_act.rpc(State.WALK, maxf(0.35, distance / float(_spec["walk_speed"])), step.angle(), global_position, global_position + step, Vector2.ZERO, 0.0, 0.0, 0.0, "", 0.0)
			return
	_set_mood(State.IDLE, 0.5)


func _can_land(point: Vector2) -> bool:
	if companion_peer != 0 and _population.has_method("can_land_companion"):
		return bool(_population.call("can_land_companion", point, self))
	if _population.has_method("can_land"):
		return bool(_population.call("can_land", point, self))
	return Terrain.relief == null or Terrain.relief.flat_around(point, 4.0)


func _take_wing(panic: bool, broadcast: bool = true, ground_only: bool = false, force_perch: bool = false) -> bool:
	if state == State.FLY:
		return false
	if _pet != null:
		_pet.reset()
	var destination: Dictionary = {}
	if _population.has_method("release_perch"):
		_population.call("release_perch", self)
	if not ground_only and _population.has_method("choose_perch") and (panic or _rest_time() or force_perch or _rng.randf() < float(_spec["perch_chance"])):
		destination = _population.call("choose_perch", self, _threat if panic else Vector2.INF)
	if destination.is_empty() and _rest_time() and not panic and not ground_only:
		return false
	if destination.is_empty() and panic and _rally.is_finite():
		for attempt: int in 8:
			var point: Vector2 = _rally + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(25.0, 65.0)
			if _can_land(point) and point.distance_to(_threat) >= float(_spec["safe_landing_range"]):
				destination = {"position": point, "height": 0.0, "path": ""}
				break
	if destination.is_empty():
		var direction: Vector2 = (global_position - _threat).normalized() if panic else Vector2.from_angle(_rng.randf() * TAU)
		for attempt: int in 20:
			var step: Vector2 = direction.rotated(_rng.randf_range(-1.25, 1.25)) * _range("flight_distance")
			var point: Vector2 = global_position + step
			if _can_land(point) and (not panic or point.distance_to(_threat) >= float(_spec["safe_landing_range"])):
				destination = {"position": point, "height": 0.0, "path": ""}
				break
	if destination.is_empty():
		# Trapped on a small island: take a shorter safe hop instead of landing in the void.
		for attempt: int in 16:
			var point: Vector2 = global_position + Vector2.from_angle(attempt * TAU / 16.0) * 55.0
			if _can_land(point):
				destination = {"position": point, "height": 0.0, "path": ""}
				break
	if destination.is_empty():
		return false
	var goal: Vector2 = destination["position"]
	var cruise: float = _preferred_cruise(panic, float(destination["height"]))
	cruise = maxf(cruise, maxf(_height, float(destination["height"])) + float(_spec["flight_clearance"]))
	var duration: float = maxf(float(_spec["flight_seconds_min"]), global_position.distance_to(goal) / float(_spec["flight_speed"]))
	var spread: float = minf(90.0, global_position.distance_to(goal) * float(_spec.get("curve_ratio", 0.25)))
	var bend: Vector2 = (goal - global_position).orthogonal().normalized() * _rng.randf_range(-spread, spread)
	if _population.has_method("route_bend"):
		bend = _population.call("route_bend", global_position, goal, bend)
	if _population.has_method("flight_clearance"):
		cruise = maxf(cruise, float(_population.call("flight_clearance", global_position, goal, bend)))
	duration = maxf(float(_spec["flight_seconds_min"]), (global_position.distance_to(goal) + bend.length() * 0.7) / float(_spec["flight_speed"]))
	_act.rpc(State.FLY, duration, (goal - global_position).angle(), global_position, goal, bend, _height, float(destination["height"]), cruise, String(destination["path"]), 0.0)
	_caution_left = float(_spec["calm_seconds"]) if panic else 0.0
	if panic and broadcast:
		_request_call(true)
		for node: Node in get_tree().get_nodes_in_group("corvids"):
			var other: WildCorvid = node as WildCorvid
			if other != self and global_position.distance_to(other.global_position) < float(_spec["alarm_range"]):
				other.hear_alarm(_threat, _end if other.flock_id == flock_id else Vector2.INF)
	return true


func hear_alarm(source: Vector2, rally: Vector2 = Vector2.INF) -> void:
	if not multiplayer.is_server() or state == State.FLY or _panic_delay >= 0.0:
		return
	if _pet != null:
		_pet.reset()
	_threat = source
	_rally = rally
	var reaction: Array = _spec.get("alarm_reaction", [0.12, 0.42])
	_panic_delay = _rng.randf_range(float(reaction[0]), float(reaction[1]))
	_set_mood(State.WATCH, 1.0)


func _request_call(alarm: bool) -> void:
	_call_left = _range("call_seconds") * (3.0 if _rest_time() else 1.0)
	if _population.has_method("authorize_call") and not bool(_population.call("authorize_call", flock_id)):
		return
	_play_call.rpc(_rng.randi_range(0, 1), _rng.randf_range(0.94, 1.04))
	if not alarm:
		for node: Node in get_tree().get_nodes_in_group("corvids"):
			var partner: WildCorvid = node as WildCorvid
			if partner != self and partner.flock_id == flock_id and partner._call_left > 4.0 and _rng.randf() < 0.25:
				partner._call_left = _rng.randf_range(1.8, 3.0)
				break


@rpc("authority", "call_local", "unreliable")
func _play_call(index: int, pitch: float) -> void:
	_call_pose = _calls[clampi(index, 0, 1)].get_length()
	var volume: float = float(GameSettings.get_value("sfx")) / 100.0
	if volume <= 0.0:
		return
	_voice.stream = _calls[clampi(index, 0, 1)]
	_voice.pitch_scale = pitch
	_voice.volume_db = float(_spec["call_volume_db"]) + linear_to_db(volume)
	_voice.play()


func _set_mood(mood: State, duration: float) -> void:
	_act.rpc(mood, duration, facing, global_position, global_position, Vector2.ZERO, _height, _height, _height, _perch_path, 0.0)


@rpc("authority", "call_local", "reliable")
func _act(mood: int, duration: float, direction: float, start: Vector2, end: Vector2, bend: Vector2, from_height: float, to_height: float, cruise: float, perch: String, elapsed: float) -> void:
	state = mood as State
	_duration = maxf(0.1, duration)
	_elapsed = elapsed
	facing = direction
	_start = start
	_end = end
	_bend = bend
	_height_from = from_height
	_height_to = to_height
	_cruise = cruise
	_perch_path = perch
	_height = from_height
	_moving = state in [State.WALK, State.FLY]
	if not _moving:
		global_position = end


func _advance() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var progress: float = smoothstep(0.0, 1.0, t) if state == State.FLY else t
	var next: Vector2 = _start.lerp(_end, progress) + _bend * (4.0 * progress * (1.0 - progress))
	if state == State.FLY:
		# Forward motion and altitude start/end together: a climbing arc and a long shallow approach,
		# with no stationary ascent, cruising plateau or vertical landing segment.
		if t < 0.42:
			_height = lerpf(_height_from, _cruise, smoothstep(0.0, 0.42, t))
		else:
			_height = lerpf(_cruise, _height_to, smoothstep(0.42, 1.0, t))
		var tangent: Vector2 = _end - _start + _bend * (4.0 * (1.0 - 2.0 * progress))
		if tangent.length_squared() > 0.01:
			facing = tangent.angle()
		global_position = next
	else:
		if multiplayer.is_server() and move_and_collide(next - global_position) != null:
			_finish.rpc(global_position, 0.0, "")
			return
		elif not multiplayer.is_server():
			global_position = next
	if t >= 1.0:
		if multiplayer.is_server():
			if state == State.FLY:
				var tree: Node = get_node_or_null(NodePath(_perch_path)) if not _perch_path.is_empty() else null
				var valid_perch: bool = tree != null and not bool(tree.call("is_depleted"))
				if (_perch_path.is_empty() and (_height_to > 0.0 or not _can_land(_end))) or (not _perch_path.is_empty() and not valid_perch):
					_reroute()
					return
			_finish.rpc(global_position, _height_to, _perch_path)
		else:
			_moving = false


func _reroute() -> void:
	state = State.WATCH
	_moving = false
	if not _take_wing(true, false, true):
		# A temporarily occupied landing sends the bird around for another approach, never into a hover.
		var direction: Vector2 = Vector2.from_angle(facing + PI * 0.6)
		_act.rpc(State.FLY, 0.9, direction.angle(), global_position, global_position + direction * 55.0, direction.orthogonal() * 22.0, _height, maxf(_height, 24.0), maxf(_height, 36.0), "", 0.0)


@rpc("authority", "call_local", "reliable")
func _finish(at: Vector2, height: float, perch: String) -> void:
	global_position = at
	_start = at
	_end = at
	_height = height
	_perch_path = perch
	_moving = false
	state = State.ROOST if not perch.is_empty() else State.WATCH
	_elapsed = 0.0
	_duration = float(_spec["calm_seconds"])


## Every peer: who the bird offers to take food from now (0 = nobody).
@rpc("authority", "call_local", "reliable")
func _offer(peer: int) -> void:
	offered_peer = peer


## Every peer: the bird eats from a hand for `duration` seconds, looking at `angle`.
@rpc("authority", "call_local", "reliable")
func _eat(duration: float, angle: float) -> void:
	offered_peer = 0
	_act(State.FEED, duration, angle, global_position, global_position, Vector2.ZERO, 0.0, 0.0, 0.0, "", 0.0)


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server():
		_offer.rpc_id(multiplayer.get_remote_sender_id(), offered_peer)
		if rider != 0:
			_ride.rpc_id(multiplayer.get_remote_sender_id(), rider)
		_act.rpc_id(multiplayer.get_remote_sender_id(), state, _duration, facing, _start, _end, _bend, _height_from if _moving else _height, _height_to if _moving else _height, _cruise, _perch_path, _elapsed)
