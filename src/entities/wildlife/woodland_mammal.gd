class_name WoodlandMammal
extends CharacterBody2D
## Host-owned ground wildlife. Every species has its own life, gaits and threat response;
## reliable actions carry mood, route, facing, vertical climb/perch height and elapsed time atomically to all peers.

enum Mood { REST, FORAGE, WALK, ALERT, FLEE, GROOM, SLEEP, SPECIAL, RETURN, HIDDEN, UNROLL, EMERGE, LISTEN, REAR, SWIPE, PLAY, CHASE, LOWER, BARK, STALK, STAND_UP, CLIMB }

var species: String = "deer":
	set(value):
		species = value
		if is_node_ready():
			_load_species()
var appearance: int = 0:
	set(value):
		appearance = value
		if is_node_ready():
			_load_species()
var family_id: String = ""
var home: Vector2
var facing: float = 0.0
var ambient_event: bool = false
var visit: Vector2 = Vector2.INF ## a visitor of the town (TownCritters, host only): where it goes to sniff, and what it looks at there
var visit_look: Vector2 = Vector2.ZERO
var _visit_stage: int = 0
var _visit_sniffs: int = 0
var _leave_hops: int = 0
var _step_limit: float = INF
var mood: Mood = Mood.REST
var _spec: Dictionary
var _population: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _duration: float = 2.0
var _moving: bool = false
var _start: Vector2
var _end: Vector2
var _sense_left: float = 0.0
var _danger: bool = false
var _threat: Vector2
var _safe_time: float = 0.0
var _alarm_delay: float = -1.0
var _forage_visits: int = 0
var _gait_phase: float = 0.0
var _gait_start: float = 0.0
var _rolling: bool = false
var _visual_facing: float = 0.0
var _bark_pending: bool = false
var _climb_from: float = 0.0
var _climb_to: float = 0.0
var _climb_height: float = 0.0
var _perch_node: Node2D = null
var _bluff_cool: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	_load_species()
	_population = get_parent().get_parent()
	_rng.seed = hash(name) + hash(family_id)
	_start = global_position
	_end = global_position
	_visual_facing = facing
	add_to_group("woodland_mammals")
	if species in ["fox", "lynx"]:
		add_to_group("wildlife_hunters")
	if species == "lynx":
		add_to_group("apex_hunters")
	if species in ["boar", "hex_goat"] and not is_young():
		add_to_group("tough_ungulates")
	if multiplayer.is_server():
		_duration = _range("rest_seconds")
		_sense_left = _rng.randf_range(0.0, float(_spec["sense_interval"]))
	else:
		_request_snapshot.rpc_id(1)


func _load_species() -> void:
	_spec = DataRegistry.get_entry("wildlife", species)
	_sprite.texture = load(String(_spec["texture"])) as Texture2D
	var cols: int = int(_spec.get("sheet_cols", 44))
	var builds: int = int(_spec.get("builds", 3))
	_sprite.hframes = cols
	_sprite.vframes = builds * 8
	var body: CircleShape2D = CircleShape2D.new()
	body.radius = float(_spec["body_radius"]) * (0.7 if is_young() else 1.0)
	($CollisionShape2D as CollisionShape2D).shape = body


func is_fawn() -> bool:
	return species == "deer" and appearance == 2


func is_piglet() -> bool:
	return species == "boar" and appearance == 2


func is_kid() -> bool:
	return species == "hex_goat" and appearance == 3


func is_young() -> bool:
	return is_fawn() or is_piglet() or is_kid() or (species == "badger" and appearance == 2)


func _range(key: String) -> float:
	var bounds: Array = _spec[key]
	return _rng.randf_range(float(bounds[0]), float(bounds[1]))


func _rest_hours() -> bool:
	if species == "squirrel":
		return TimeManager.night_amount() > 0.55
	if not bool(_spec["nocturnal"]):
		return false
	return TimeManager.night_amount() < float(_spec.get("awake_threshold", 0.4))


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if multiplayer.is_server():
		_bluff_cool = maxf(0.0, _bluff_cool - delta)
		if _perch_node != null and (not is_instance_valid(_perch_node) or (_perch_node.has_method("is_depleted") and bool(_perch_node.call("is_depleted")))):
			_perch_node = null
			if _climb_height > 0.5:
				_climb_action(Mood.FLEE, global_position + Vector2.from_angle(facing) * 28.0, 0.42, _climb_height, 0.0)
		_sense_left -= delta
		if _sense_left <= 0.0:
			_sense_left = float(_spec["sense_interval"])
			_sense()
		_safe_time = 0.0 if _danger else _safe_time + delta
		if _alarm_delay >= 0.0:
			_alarm_delay -= delta
			if _alarm_delay <= 0.0:
				_alarm_delay = -1.0
				_step((global_position - _threat).normalized(), Mood.FLEE)
		if not _moving and (not ambient_event or _danger):
			_think()
	if _moving:
		_advance()


func _process(delta: float) -> void:
	_visual_facing += clampf(angle_difference(_visual_facing, facing), -delta * 7.0, delta * 7.0)
	_sprite.visible = mood != Mood.HIDDEN
	var progress: float = clampf(_elapsed / maxf(_duration, 0.1), 0.0, 1.0)
	_climb_height = lerpf(_climb_from, _climb_to, progress) if (_climb_from != _climb_to) else _climb_to
	var cols: int = int(_spec.get("sheet_cols", 44))
	var builds: int = int(_spec.get("builds", 3))
	var col: int = int(_elapsed * 2.2) % 4
	if species in ["deer", "boar", "hex_goat"] and cols >= 52:
		match mood:
			Mood.FORAGE:
				if species == "deer":
					var remaining: float = _duration - _elapsed
					if _elapsed < 0.5:
						col = 4 + mini(1, int(_elapsed / 0.25))
					elif remaining < 0.5:
						col = 10 + mini(1, int((0.5 - maxf(0.0, remaining)) / 0.25))
					else:
						col = 6 + int(_elapsed * 2.4) % 4
				else:
					col = 4 + int(_elapsed * 4.2) % 8
			Mood.WALK, Mood.RETURN:
				col = 12 + int(_gait_phase * 8.0) % 8
			Mood.ALERT, Mood.LISTEN:
				col = 20 + int(_elapsed * 2.0) % 4
			Mood.FLEE, Mood.CHASE:
				col = 24 + int(_gait_phase * 8.0) % 8
			Mood.GROOM:
				col = 32 + int(_elapsed * 2.8) % 4
			Mood.SLEEP:
				col = 36 + int(_elapsed * 1.4) % 4
			Mood.BARK, Mood.REAR:
				col = 40 + mini(5, int(clampf(_elapsed / _duration, 0.0, 0.999) * 6.0))
			Mood.SPECIAL:
				if species == "boar":
					col = 46 + int(_elapsed * 5.2) % 6
				else:
					col = 40 + mini(5, int(clampf(_elapsed / _duration, 0.0, 0.999) * 6.0))
			Mood.STAND_UP:
				col = 46 + mini(5, int(clampf(_elapsed / _duration, 0.0, 0.999) * 6.0))
	elif species in ["fox", "lynx", "squirrel", "badger"] and cols >= 52:
		match mood:
			Mood.FORAGE:
				col = 4 + int(_elapsed * 5.0) % 6
			Mood.WALK, Mood.RETURN, Mood.EMERGE:
				col = 10 + int(_gait_phase * 8.0) % 8
			Mood.ALERT, Mood.LISTEN:
				col = 18 + int(_elapsed * 2.2) % 4
			Mood.BARK:
				if species == "badger":
					col = 46 + mini(5, int(clampf(_elapsed / _duration, 0.0, 0.999) * 6.0))
				else:
					col = 18 + int(_elapsed * 6.5) % 4
			Mood.FLEE, Mood.CHASE:
				col = 22 + int(_gait_phase * 8.0) % 8
			Mood.GROOM:
				col = 30 + int(_elapsed * 3.0) % 4
			Mood.SLEEP:
				col = 34 + int(_elapsed * 1.3) % 4
			Mood.SPECIAL:
				if species in ["squirrel", "badger"]:
					col = 38 + int(_elapsed * 5.2) % 8
				else:
					col = 38 + mini(7, int(clampf(_elapsed / _duration, 0.0, 0.999) * 8.0))
			Mood.STALK:
				col = 46 + int(_gait_phase * 6.0) % 6
			Mood.CLIMB:
				col = 46 + int(_elapsed * 10.5) % 6
	elif species == "hex_toad" and cols >= 52:
		match mood:
			Mood.FORAGE:
				col = 4 + int(_elapsed * 3.5) % 6
			Mood.WALK, Mood.RETURN:
				col = 10 + mini(7, int(progress * 8.0))
			Mood.ALERT, Mood.LISTEN:
				col = 18 + int(_elapsed * 2.4) % 4
			Mood.FLEE:
				col = 22 + mini(7, int(progress * 8.0))
			Mood.GROOM:
				col = 30 + int(_elapsed * 3.2) % 4
			Mood.SLEEP:
				col = 34 + int(_elapsed * 1.1) % 4
			Mood.BARK:
				col = 38 + mini(5, int(clampf(_elapsed / _duration, 0.0, 0.999) * 6.0))
			Mood.SPECIAL:
				col = 44 + mini(7, int(clampf(_elapsed / _duration, 0.0, 0.999) * 8.0))
	else:
		match mood:
			Mood.FORAGE:
				col = 4 + int(_elapsed * 5.0) % 6
			Mood.WALK, Mood.RETURN, Mood.EMERGE:
				col = 10 + int(_gait_phase * 8.0) % 8
			Mood.ALERT, Mood.LISTEN:
				col = 18 + int(_elapsed * 2.0) % 4
			Mood.FLEE:
				col = 22 + int(_gait_phase * 8.0) % 8
			Mood.GROOM:
				col = 30 + int(_elapsed * 3.0) % 4
			Mood.SLEEP:
				col = 34 + int(_elapsed * 1.4) % 4
			Mood.SPECIAL:
				col = 38 + (mini(5, int(_elapsed / float(_spec["curl_seconds"]) * 6.0)) if species == "hedgehog" else int(_elapsed / _duration * 6.0) % 6)
			Mood.UNROLL:
				col = 43 - mini(5, int(_elapsed / _duration * 6.0))
	var sector: int = posmod(roundi(_visual_facing / (PI / 4.0)), 8)
	_sprite.frame = (clampi(appearance, 0, builds - 1) * 8 + sector) * cols + col
	_sprite.modulate.a = smoothstep(0.0, 0.7, _elapsed / _duration) if mood == Mood.EMERGE else 1.0
	var lift_y: float = 0.0
	if species in ["fox", "lynx"] and mood == Mood.SPECIAL and _moving:
		lift_y = sin(progress * PI) * float(_spec["pounce_height"])
	elif species in ["deer", "lynx", "squirrel", "hex_goat"] and mood == Mood.FLEE and _moving:
		lift_y = absf(sin(_gait_phase * PI)) * float(_spec.get("bound_height", 3.5)) * (0.78 if is_young() else 1.0)
	elif species == "hex_toad" and mood in [Mood.WALK, Mood.RETURN, Mood.FLEE] and _moving:
		lift_y = sin(progress * PI) * float(_spec.get("hop_height", 4.2)) * (1.25 if mood == Mood.FLEE else 0.85)
	_sprite.position.y = -roundf(_climb_height + lift_y)
	_sprite.z_index = 2 if _climb_height >= 12.0 else 0
	queue_redraw()


func _draw() -> void:
	if mood == Mood.HIDDEN:
		return
	var radius: float = float(_spec.get("body_radius", 4.0)) * (0.7 if is_young() else 1.0)
	var shadow_fade: float = clampf(1.0 - _climb_height / 42.0, 0.22, 1.0)
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.3, 0.4))
	draw_circle(Vector2.ZERO, radius, Color(0.035, 0.025, 0.065, 0.24 * shadow_fade))
	draw_set_transform(Vector2.ZERO)
	if (species == "badger" and mood == Mood.SPECIAL) or (species == "boar" and mood in [Mood.SPECIAL, Mood.FORAGE]):
		var dirt_col: Color = Color("6b5446") if species == "boar" else Color("8b7163")
		for i: int in 3:
			var t: float = fposmod(_elapsed * 2.2 + i * 0.31, 1.0)
			draw_rect(Rect2(Vector2((i - 1) * (2.0 + t * 4.5), -2.0 - _climb_height - sin(t * PI) * 4.5).round(), Vector2.ONE), dirt_col)
	elif species == "squirrel" and mood == Mood.SPECIAL:
		for i: int in 2:
			var t: float = fposmod(_elapsed * 1.9 + i * 0.47, 1.0)
			draw_rect(Rect2(Vector2((i * 2 - 1) * (1.5 + t * 2.0), -6.0 - _climb_height + t * 6.0).round(), Vector2.ONE), Color("7a4f34"))


func _sense() -> void:
	_danger = false
	if mood in [Mood.HIDDEN, Mood.EMERGE, Mood.CLIMB]:
		return
	var nearest: float = INF
	var close: bool = false
	var threat_node: Node = null
	var candidates: Array[Node] = []
	candidates.append_array(Player.all)
	candidates.append_array(get_tree().get_nodes_in_group("predators"))
	if species in ["deer", "hedgehog", "squirrel", "boar", "badger", "hex_goat", "hex_toad"]:
		candidates.append_array(get_tree().get_nodes_in_group("wildlife_hunters"))
		candidates.append_array(get_tree().get_nodes_in_group("apex_hunters"))
	elif species == "fox":
		candidates.append_array(get_tree().get_nodes_in_group("apex_hunters"))
		candidates.append_array(get_tree().get_nodes_in_group("tough_ungulates"))
	for node: Node in candidates:
		var actor: Node2D = node as Node2D
		if actor == null or actor == self:
			continue
		var alert: float = float(_spec["alert_range"])
		var flee: float = float(_spec["flee_range"])
		if mood == Mood.FLEE:
			alert = float(_spec["safe_range"])
		var noisy: bool = false
		if actor is Player:
			var player: Player = actor as Player
			if player.health.current <= 0.0:
				continue
			var calm: float = TownManager.calm_at(get_tree(), global_position) ## used to the town's people
			alert *= calm
			flee *= calm
			if player.stealth.sneaking:
				alert *= float(_spec["sneak_multiplier"])
				flee *= float(_spec["sneak_multiplier"])
			if player.sprinting:
				alert *= float(_spec["sprint_multiplier"])
				flee *= float(_spec["sprint_multiplier"])
			noisy = player.attack.is_swinging() and global_position.distance_to(actor.global_position) < float(_spec["swing_range"]) * player.attack.noise_scale()
		elif node.is_in_group("apex_hunters"):
			alert = 148.0 if species == "deer" else (112.0 if species == "squirrel" else 82.0)
			flee = 96.0 if species == "deer" else (78.0 if species in ["squirrel", "fox"] else 54.0)
		elif node.is_in_group("tough_ungulates"):
			alert = 62.0
			flee = 44.0
		elif node.is_in_group("wildlife_hunters"):
			if species == "boar" and not is_piglet():
				alert = 84.0
				flee = 0.0
			elif species == "badger" and not is_young():
				alert = 52.0
				flee = 0.0
			elif species == "squirrel":
				alert = 104.0
				flee = 72.0
			else:
				alert = 95.0 if is_fawn() else 65.0
				flee = 55.0 if is_fawn() else 25.0
		else:
			var health: HealthComponent = actor.get_node_or_null("HealthComponent") as HealthComponent
			if health != null and health.current <= 0.0:
				continue
		var distance: float = global_position.distance_to(actor.global_position)
		if distance > alert and not noisy:
			continue
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, actor.global_position, 1)
		if _climb_height < 10.0 and not noisy and not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		_danger = true
		close = close or noisy or distance < flee
		if distance < nearest:
			nearest = distance
			_threat = actor.global_position
			threat_node = node
	if not _danger:
		return
	# Species-specific ecological threat responses
	if species == "boar" and not is_piglet() and threat_node != null and threat_node.is_in_group("wildlife_hunters") and not threat_node.is_in_group("apex_hunters"):
		if _bluff_cool <= 0.0 and mood not in [Mood.CHASE, Mood.BARK]:
			_bluff_cool = 7.0
			var to_fox: Vector2 = (_threat - global_position).normalized()
			var charge_to: Vector2 = global_position + to_fox * minf(36.0, global_position.distance_to(_threat) * 0.7)
			if _can_step(charge_to) and not test_move(global_transform, charge_to - global_position):
				_move_action(Mood.CHASE, charge_to, 0.55)
			else:
				_issue(Mood.BARK, float(_spec.get("bark_seconds", 1.05)), to_fox.angle())
		return
	if species == "badger" and not is_young() and threat_node != null and threat_node.is_in_group("wildlife_hunters") and not threat_node.is_in_group("apex_hunters"):
		if mood != Mood.BARK:
			_issue(Mood.BARK, float(_spec.get("bark_seconds", 0.95)), (_threat - global_position).angle())
		return
	if species == "squirrel":
		if _climb_height >= 16.0:
			if not _moving and mood != Mood.BARK:
				_broadcast_squirrel_alarm()
				_issue(Mood.BARK, float(_spec.get("bark_seconds", 1.25)), (_threat - global_position).angle())
			return
		if close:
			if _flee_up_tree():
				_broadcast_squirrel_alarm()
				return
			if mood != Mood.FLEE:
				_step((global_position - _threat).normalized(), Mood.FLEE)
		elif not _moving and mood not in [Mood.ALERT, Mood.BARK]:
			_issue(Mood.ALERT, 1.2, (_threat - global_position).angle())
		return
	if species == "hex_goat":
		if close:
			if not is_kid() and mood not in [Mood.REAR, Mood.FLEE] and _bluff_cool <= 0.0:
				_bluff_cool = 6.5
				_issue(Mood.REAR, float(_spec.get("rear_seconds", 1.25)), (_threat - global_position).angle())
			elif mood != Mood.FLEE and mood != Mood.REAR:
				_step((global_position - _threat).normalized(), Mood.FLEE)
		else:
			facing = (_threat - global_position).angle()
			if not _moving and mood == Mood.SLEEP:
				_issue(Mood.STAND_UP, float(_spec.get("stand_up_seconds", 0.80)), facing)
			elif not _moving and mood != Mood.ALERT:
				_issue(Mood.ALERT, 1.8, facing)
		return
	if species == "hedgehog":
		if close and mood != Mood.SPECIAL:
			var already_curled: bool = mood == Mood.SLEEP
			_issue(Mood.SPECIAL, float(_spec["curl_seconds"]), INF, float(_spec["curl_seconds"]) if already_curled else 0.0)
		elif not close and mood not in [Mood.SPECIAL, Mood.SLEEP]:
			_issue(Mood.ALERT, 1.0, (_threat - global_position).angle())
		return
	if close:
		if mood != Mood.FLEE:
			if _climb_height > 0.5:
				_perch_node = null
				_climb_action(Mood.FLEE, global_position + (global_position - _threat).normalized() * 34.0, 0.42, _climb_height, 0.0)
				return
			if species == "badger":
				var home_loaded: bool = bool(_population.call("home_loaded", home)) if _population.has_method("home_loaded") else true
				if home_loaded and global_position.distance_to(home) < 145.0 and home.distance_to(_threat) > 22.0:
					if global_position.distance_to(home) <= 10.0:
						_issue(Mood.HIDDEN, _range("sleep_seconds"))
					else:
						_step((home - global_position).normalized(), Mood.RETURN)
					return
			if species == "deer" and not is_fawn():
				_bark_pending = true
			_step((global_position - _threat).normalized(), Mood.FLEE)
			if species in ["deer", "boar"]:
				_alarm_family()
	elif not _moving and mood not in [Mood.ALERT, Mood.FLEE, Mood.BARK, Mood.STAND_UP, Mood.REAR]:
		if species in ["deer", "boar", "hex_goat"] and mood == Mood.SLEEP:
			_issue(Mood.STAND_UP, float(_spec.get("stand_up_seconds", 0.85)), (_threat - global_position).angle())
		elif species == "boar" and not is_piglet() and _bluff_cool <= 0.0:
			_bluff_cool = 5.5
			_alarm_family()
			_issue(Mood.BARK, float(_spec.get("bark_seconds", 1.05)), (_threat - global_position).angle())
		else:
			if species == "deer" and not is_fawn() and (_rng.randf() < 0.45 or (threat_node != null and threat_node.is_in_group("apex_hunters"))):
				_bark_pending = true
			_issue(Mood.ALERT, 1.4, (_threat - global_position).angle())


## Cross-species woodland sentinel reaction: rabbit thumps, squirrel chatter, and corvid warning calls alert nearby roe deer & boars.
func hear_external_alarm(from: Vector2) -> void:
	if not multiplayer.is_server() or species not in ["deer", "boar"] or _danger:
		return
	if global_position.distance_to(from) > float(_spec.get("alert_range", 165.0)) * 1.1:
		return
	_threat = from
	if mood == Mood.SLEEP:
		_issue(Mood.STAND_UP, float(_spec.get("stand_up_seconds", 0.85)), (from - global_position).angle())
	elif not _moving and mood in [Mood.REST, Mood.FORAGE, Mood.GROOM]:
		_issue(Mood.ALERT, 1.4, (from - global_position).angle())


func _broadcast_squirrel_alarm() -> void:
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var other: WoodlandMammal = node as WoodlandMammal
		if other != null and other != self and other.global_position.distance_to(global_position) < 135.0:
			other.hear_external_alarm(_threat if _threat != Vector2.ZERO else global_position)
	for node: Node in get_tree().get_nodes_in_group("wildlife"):
		var r: Node2D = node as Node2D
		if r != null and r.global_position.distance_to(global_position) < 110.0 and r.has_method("hear_alarm"):
			r.call("hear_alarm", _threat if _threat != Vector2.ZERO else global_position)


func _adult() -> WoodlandMammal:
	return _adult_leader("deer")


func _adult_leader(target_species: String) -> WoodlandMammal:
	var fallback: WoodlandMammal = null
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var animal: WoodlandMammal = node as WoodlandMammal
		if animal != self and animal.species == target_species and animal.family_id == family_id and not animal.is_young():
			if target_species == "deer" and animal.appearance in [0, 3]:
				return animal
			if target_species == "boar" and animal.appearance in [0, 3]:
				return animal
			fallback = animal
	return fallback


func _alarm_family() -> void:
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var other: WoodlandMammal = node as WoodlandMammal
		if other != self and other.species == species and other.family_id == family_id and other.mood != Mood.FLEE and other._alarm_delay < 0.0:
			other._threat = _threat
			other._issue(Mood.ALERT, 0.5)
			other._alarm_delay = _rng.randf_range(0.10, 0.36)


func _nearest_climb_tree(max_dist: float, away_from: Vector2 = Vector2.INF) -> FirTree:
	var best: FirTree = null
	var best_score: float = INF
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree == null or tree.is_depleted() or tree._falling or tree.kind == "bone_tree":
			continue
		var d: float = global_position.distance_to(tree.global_position)
		if d > max_dist:
			continue
		if away_from.is_finite() and tree.global_position.distance_to(away_from) < 34.0:
			continue
		if d < best_score:
			best_score = d
			best = tree
	return best


func _flee_up_tree() -> bool:
	var tree: FirTree = _nearest_climb_tree(92.0, _threat)
	if tree == null:
		return false
	var trunk_base: Vector2 = tree.global_position + Vector2(0.0, 2.0)
	if global_position.distance_to(trunk_base) <= 10.0:
		_perch_node = tree
		var target_h: float = _rng.randf_range(24.0, 34.0)
		_climb_action(Mood.CLIMB, trunk_base, maxf(0.35, target_h / float(_spec.get("climb_speed", 48.0))), _climb_height, target_h)
		return true
	var step_dir: Vector2 = (trunk_base - global_position)
	if not test_move(global_transform, step_dir):
		_move_action(Mood.FLEE, trunk_base, maxf(0.22, step_dir.length() / float(_spec["run_speed"])))
		return true
	return false


func _think() -> void:
	if _alarm_delay >= 0.0:
		return
	if species == "hedgehog" and mood == Mood.SPECIAL:
		if not _danger and _safe_time >= float(_spec["safe_seconds"]) and _elapsed >= _duration:
			_issue(Mood.UNROLL, float(_spec["uncurl_seconds"]))
		return
	if species == "hex_goat" and mood == Mood.REAR and _elapsed >= _duration:
		_step((global_position - _threat).normalized(), Mood.FLEE)
		return
	if species == "badger" and mood == Mood.RETURN and _danger and global_position.distance_to(home) <= 10.0:
		_issue(Mood.HIDDEN, _range("sleep_seconds"))
		return
	if species == "squirrel" and mood == Mood.FLEE and _danger and _climb_height < 1.0:
		var tree_now: FirTree = _nearest_climb_tree(12.0, Vector2.INF)
		if tree_now != null:
			_perch_node = tree_now
			var h_up: float = _rng.randf_range(24.0, 34.0)
			_climb_action(Mood.CLIMB, tree_now.global_position + Vector2(0.0, 2.0), maxf(0.35, h_up / float(_spec.get("climb_speed", 48.0))), 0.0, h_up)
			_broadcast_squirrel_alarm()
			return
	if _danger and mood != Mood.FLEE:
		if species == "hex_goat" and mood == Mood.ALERT and _elapsed >= _duration:
			_issue(Mood.ALERT, 1.6, (_threat - global_position).angle())
		return
	if mood == Mood.FLEE and visit.is_finite(): ## scared off: it gives the visit up and leaves
		visit = Vector2.INF
		_leave_hops = 3
	if mood == Mood.FLEE:
		if _safe_time >= float(_spec["safe_seconds"]):
			_issue(Mood.ALERT, 1.5)
		elif _elapsed >= _duration:
			_step((global_position - _threat).normalized(), Mood.FLEE)
		return
	if not _rest_hours() and mood == Mood.HIDDEN:
		if species == "squirrel":
			_climb_action(Mood.CLIMB, global_position, 0.55, 28.0, 0.0)
		else:
			_move_action(Mood.EMERGE, global_position + Vector2(0, 9), float(_spec.get("emerge_seconds", 1.0)))
		return
	if not _rest_hours() and mood == Mood.SLEEP:
		if species == "hedgehog":
			_issue(Mood.UNROLL, float(_spec["uncurl_seconds"]))
			return
		elif species in ["deer", "boar", "hex_goat"]:
			if _elapsed >= _duration:
				_issue(Mood.STAND_UP, float(_spec.get("stand_up_seconds", 0.85)))
			return
		else:
			_issue(Mood.ALERT, 1.0)
			return
	if _elapsed < _duration:
		return
	if species in ["deer", "boar", "hex_goat"] and mood == Mood.STAND_UP:
		_issue(Mood.ALERT if _danger else Mood.REST, 1.1)
		return
	if species == "badger" and mood == Mood.EMERGE:
		_issue(Mood.ALERT, 1.35, facing + _rng.randf_range(-0.4, 0.4))
		return
	if species == "deer" and mood == Mood.ALERT and _bark_pending and not is_fawn():
		_bark_pending = false
		_alarm_family()
		_issue(Mood.BARK, float(_spec.get("bark_seconds", 1.1)), (_threat - global_position).angle() if _threat != Vector2.ZERO else facing)
		return
	if _rest_hours():
		var home_loaded: bool = bool(_population.call("home_loaded", home)) if _population.has_method("home_loaded") else true
		if species == "squirrel":
			var night_tree: FirTree = _nearest_climb_tree(90.0, Vector2.INF)
			if night_tree != null and global_position.distance_to(night_tree.global_position) > 10.0 and _climb_height < 1.0:
				_step((night_tree.global_position - global_position).normalized(), Mood.RETURN)
			elif night_tree != null and _climb_height < 22.0:
				_perch_node = night_tree
				_climb_action(Mood.CLIMB, night_tree.global_position + Vector2(0.0, 2.0), 0.65, _climb_height, 28.0)
			else:
				_issue(Mood.HIDDEN, _range("sleep_seconds"))
			return
		if home_loaded and global_position.distance_to(home) > 8.0:
			_step((home - global_position).normalized(), Mood.RETURN)
		elif species == "badger" and home_loaded:
			_issue(Mood.HIDDEN, _range("sleep_seconds"))
		elif species == "fox" and mood == Mood.SLEEP and _rng.randf() < 0.2:
			_issue(Mood.GROOM, _range("groom_seconds"))
		else:
			_issue(Mood.SLEEP, _range("sleep_seconds"))
		return
	if mood == Mood.HIDDEN:
		_move_action(Mood.EMERGE, global_position + Vector2(0, 9), float(_spec.get("emerge_seconds", 1.0)))
		return
	match species:
		"deer":
			_deer_life()
		"badger":
			_badger_life()
		"fox":
			_fox_life()
		"boar":
			_boar_life()
		"lynx":
			_lynx_life()
		"squirrel":
			_squirrel_life()
		"hex_goat":
			_hex_goat_life()
		"hex_toad":
			_hex_toad_life()
		_:
			_hedgehog_life()


func _deer_life() -> void:
	if is_fawn():
		var parent: WoodlandMammal = _adult_leader("deer")
		if parent != null and global_position.distance_to(parent.global_position) > float(_spec["family_range"]):
			_step((parent.global_position + Vector2(15, 12) - global_position).normalized(), Mood.WALK)
			return
		if parent != null and parent.mood == Mood.SLEEP and global_position.distance_to(parent.global_position) < 42.0:
			_issue(Mood.SLEEP, _range("sleep_seconds") * 0.85)
			return
	var weather_node: Node = get_tree().get_first_node_in_group("weather")
	var rain: float = float(weather_node.get("rain")) if weather_node != null else 0.0
	var night: float = TimeManager.night_amount()
	var bed_chance: float = 0.36 if rain >= 0.35 else (0.24 if night > 0.72 else 0.10)
	var roll: float = _rng.randf()
	if roll < bed_chance:
		_issue(Mood.SLEEP, _range("sleep_seconds"))
	elif roll < 0.56:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	elif roll < 0.80:
		_roam()
	elif roll < 0.91:
		_issue(Mood.ALERT, _range("rest_seconds"), facing + _rng.randf_range(-0.6, 0.6))
	else:
		_issue(Mood.GROOM, _range("groom_seconds"))


func _boar_life() -> void:
	if is_piglet():
		var mother: WoodlandMammal = _adult_leader("boar")
		if mother != null:
			var queue_spot: Vector2 = mother.global_position - Vector2.from_angle(mother.facing) * 18.0 + Vector2.from_angle(float(hash(name) % 7)) * 6.0
			if global_position.distance_to(queue_spot) > 16.0:
				_step_limit = global_position.distance_to(queue_spot)
				_step((queue_spot - global_position).normalized(), Mood.WALK)
				_step_limit = INF
				return
			if mother.mood == Mood.SLEEP:
				_issue(Mood.SLEEP, _range("sleep_seconds") * 0.8)
				return
	if mood == Mood.FORAGE:
		_forage_visits += 1
		if _forage_visits % 2 == 0 and not is_piglet():
			_issue(Mood.SPECIAL, _range("root_seconds"))
			return
	var night: float = TimeManager.night_amount()
	var roll: float = _rng.randf()
	if night > 0.78 and roll < 0.26:
		_issue(Mood.SLEEP, _range("sleep_seconds"))
	elif roll < 0.54:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	elif roll < 0.82:
		_roam()
	elif roll < 0.92:
		_issue(Mood.GROOM, _range("groom_seconds"))
	else:
		_issue(Mood.ALERT, _range("rest_seconds"), facing + _rng.randf_range(-0.5, 0.5))


func _lynx_life() -> void:
	if _climb_height > 0.5:
		var log_roll: float = _rng.randf()
		if log_roll < 0.36:
			_issue(Mood.GROOM, _range("groom_seconds"))
		elif log_roll < 0.72:
			_issue(Mood.ALERT, _range("rest_seconds"), facing + _rng.randf_range(-0.85, 0.85))
		else:
			_perch_node = null
			var step_off: Vector2 = global_position + Vector2.from_angle(facing) * 18.0
			if not _can_step(step_off):
				step_off = global_position
			_climb_action(Mood.WALK, step_off, 0.55, _climb_height, 0.0)
		return
	if mood == Mood.STALK:
		_issue(Mood.ALERT, _range("listen_seconds"), facing)
		return
	if mood == Mood.ALERT and _rng.randf() < 0.34:
		var leap_to: Vector2 = global_position + Vector2.from_angle(facing) * _range("pounce_distance")
		if _can_step(leap_to) and not test_move(global_transform, leap_to - global_position):
			_move_action(Mood.SPECIAL, leap_to, float(_spec["pounce_seconds"]))
			return
	# Seek a nearby FallenLog lookout perch
	if _rng.randf() < 0.34:
		for log_node: FallenLog in get_tree().get_nodes_in_group("fallen_logs"):
			var d: float = global_position.distance_to(log_node.perch_point)
			if d < 18.0:
				_perch_node = log_node
				_climb_action(Mood.WALK, log_node.perch_point, 0.48, 0.0, log_node.perch_height)
				return
			elif d < 85.0:
				_step_limit = d - 10.0
				_step((log_node.perch_point - global_position).normalized(), Mood.WALK)
				_step_limit = INF
				return
	var roll: float = _rng.randf()
	if roll < 0.28:
		var stalk_dir: Vector2 = Vector2.from_angle(facing + _rng.randf_range(-0.7, 0.7))
		_step(stalk_dir, Mood.STALK)
	elif roll < 0.58:
		_roam()
	elif roll < 0.76:
		_issue(Mood.GROOM, _range("groom_seconds"))
	elif roll < 0.88:
		_issue(Mood.SLEEP, _range("sleep_seconds") * 0.65)
	else:
		_issue(Mood.ALERT, _range("rest_seconds"), facing + _rng.randf_range(-0.8, 0.8))


func _squirrel_life() -> void:
	if _climb_height >= 10.0:
		var trunk_roll: float = _rng.randf()
		if trunk_roll < 0.44 and mood != Mood.SPECIAL:
			_issue(Mood.SPECIAL, _range("cone_seconds"))
		elif trunk_roll < 0.68 and mood != Mood.REST:
			_issue(Mood.REST, _range("rest_seconds"))
		else:
			_perch_node = null
			var base_pt: Vector2 = global_position + Vector2.from_angle(_rng.randf() * TAU) * 8.0
			if not _can_step(base_pt):
				base_pt = global_position
			_climb_action(Mood.CLIMB, base_pt, maxf(0.38, _climb_height / float(_spec.get("climb_speed", 48.0))), _climb_height, 0.0)
		return
	# Climb a nearby conifer voluntarily
	if _rng.randf() < 0.28:
		var tree: FirTree = _nearest_climb_tree(68.0, Vector2.INF)
		if tree != null:
			var base: Vector2 = tree.global_position + Vector2(0.0, 2.0)
			if global_position.distance_to(base) <= 11.0:
				_perch_node = tree
				var up_h: float = _rng.randf_range(20.0, 32.0)
				_climb_action(Mood.CLIMB, base, maxf(0.35, up_h / float(_spec.get("climb_speed", 48.0))), 0.0, up_h)
				return
			_step_limit = global_position.distance_to(base)
			_step((base - global_position).normalized(), Mood.WALK)
			_step_limit = INF
			return
	var roll: float = _rng.randf()
	if roll < 0.30:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	elif roll < 0.48:
		_issue(Mood.SPECIAL, _range("cone_seconds"))
	elif roll < 0.80:
		_roam()
	elif roll < 0.90:
		_issue(Mood.GROOM, _range("groom_seconds"))
	else:
		_issue(Mood.REST, _range("rest_seconds"), facing + _rng.randf_range(-0.9, 0.9))


func _hex_goat_life() -> void:
	if is_kid():
		var elder: WoodlandMammal = _adult_leader("hex_goat")
		if elder != null and global_position.distance_to(elder.global_position) > float(_spec.get("family_range", 44.0)):
			_step((elder.global_position + Vector2(14, 10) - global_position).normalized(), Mood.WALK)
			return
	# Browse Hexenwald shrubs (hex_shrub / witch_broom) when close
	var roll: float = _rng.randf()
	if roll < 0.44:
		var shrub_dir: float = facing
		for world: Node in get_tree().get_nodes_in_group("world"):
			var props: Node = world.get_node_or_null("Props")
			if props != null:
				for node: Node in props.get_children():
					var prop: WorldProp = node as WorldProp
					if prop != null and prop.kind in ["hex_shrub", "witch_broom"] and prop.global_position.distance_to(global_position) < 28.0:
						shrub_dir = (prop.global_position - global_position).angle()
						break
		_issue(Mood.FORAGE, _range("forage_seconds"), shrub_dir)
	elif roll < 0.68:
		_roam()
	elif roll < 0.82:
		_issue(Mood.ALERT, _range("rest_seconds"), facing + _rng.randf_range(-0.7, 0.7))
	elif roll < 0.91:
		_issue(Mood.GROOM, _range("groom_seconds"))
	else:
		_issue(Mood.SLEEP, _range("sleep_seconds") * 0.75)


func _hex_toad_life() -> void:
	var roll: float = _rng.randf()
	if roll < 0.24:
		_issue(Mood.BARK, float(_spec.get("croak_seconds", 1.2)))
	elif roll < 0.42:
		_issue(Mood.SPECIAL, float(_spec.get("tongue_seconds", 0.85)), facing + _rng.randf_range(-0.45, 0.45))
	elif roll < 0.68:
		_roam()
	elif roll < 0.82:
		_issue(Mood.REST, _range("rest_seconds"))
	elif roll < 0.92:
		_issue(Mood.GROOM, _range("groom_seconds"))
	else:
		_issue(Mood.SLEEP, _range("sleep_seconds") * 0.6)


func _badger_life() -> void:
	if mood == Mood.FORAGE:
		_forage_visits += 1
		if _forage_visits % 2 == 0:
			_issue(Mood.SPECIAL, _range("dig_seconds"))
			return
	var roll: float = _rng.randf()
	if roll < 0.12:
		_issue(Mood.GROOM, _range("groom_seconds"))
	elif roll < 0.64:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	else:
		_roam()


func _fox_life() -> void:
	if _leave_hops > 0: ## on its way out of the town
		_leave_hops -= 1
		_step((global_position - (visit_look if visit_look != Vector2.ZERO else global_position - Vector2.from_angle(facing))).normalized(), Mood.WALK)
		return
	if visit.is_finite():
		_visit_life()
		return
	if mood == Mood.LISTEN:
		var point: Vector2 = global_position + Vector2.from_angle(facing) * _range("pounce_distance")
		if _can_step(point) and not test_move(global_transform, point - global_position):
			_move_action(Mood.SPECIAL, point, float(_spec["pounce_seconds"]))
			return
	if mood == Mood.STALK:
		_issue(Mood.LISTEN, _range("listen_seconds"), facing)
		return
	if mood == Mood.SPECIAL:
		_issue(Mood.FORAGE, _range("forage_seconds"))
		return
	var roll: float = _rng.randf()
	if roll < 0.42:
		var target: Vector2 = global_position + Vector2.from_angle(facing + _rng.randf_range(-0.65, 0.65)) * 34.0
		for node: Node in get_tree().get_nodes_in_group("wildlife"):
			if node is WildRabbit and global_position.distance_to((node as Node2D).global_position) < 110.0:
				target = (node as Node2D).global_position
				break
		var dir: Vector2 = (target - global_position).normalized()
		if dir != Vector2.ZERO and _spec.has("stalk_distance") and _rng.randf() < 0.68:
			_step(dir, Mood.STALK)
		else:
			_issue(Mood.LISTEN, _range("listen_seconds"), (target - global_position).angle())
	elif roll < 0.78:
		_roam()
	elif roll < 0.92:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	else:
		_issue(Mood.GROOM, _range("groom_seconds"))


## A visit to the town: walk up to the spot (in hops that never overshoot it), then sniff along the stockpile: ground, a listening pause, ground again, looking at it; then off.
func _visit_life() -> void:
	var to: Vector2 = visit - global_position
	if _visit_stage == 0:
		if to.length() > 14.0:
			_step_limit = to.length() ## a hop that never overshoots the spot
			_step(to.normalized(), Mood.WALK)
			_step_limit = INF
			return
		_visit_stage = 1
	if _visit_stage == 1 and _visit_sniffs < 4:
		_visit_sniffs += 1
		var look: float = (visit_look - global_position).angle() + (0.0 if _visit_sniffs % 2 == 1 else _rng.randf_range(-0.5, 0.5))
		_issue(Mood.LISTEN if _visit_sniffs == 3 else Mood.FORAGE, _range("forage_seconds") * (0.7 if _visit_sniffs == 3 else 1.2), look)
		return
	visit = Vector2.INF
	_leave_hops = 5


func _hedgehog_life() -> void:
	var roll: float = _rng.randf()
	if roll < 0.15:
		_issue(Mood.REST, _range("rest_seconds"))
	elif roll < 0.75:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	else:
		_roam()


func _roam() -> void:
	var direction: Vector2 = Vector2.from_angle(facing + _rng.randf_range(-1.15, 1.15))
	if global_position.distance_to(home) > float(_spec["home_radius"]):
		direction = (home - global_position).normalized()
	_step(direction, Mood.WALK)


func _can_step(point: Vector2) -> bool:
	if _population.has_method("can_stand"):
		return bool(_population.call("can_stand", point, self))
	return Terrain.relief == null or Terrain.relief.flat_around(point, float(_spec["body_radius"]))


func _step(direction: Vector2, action: Mood) -> void:
	var fleeing: bool = action == Mood.FLEE
	var stalking: bool = action == Mood.STALK
	var distance: float = _range("run_distance" if fleeing else ("stalk_distance" if stalking and _spec.has("stalk_distance") else "walk_distance"))
	distance = minf(distance, _step_limit)
	var speed: float = float(_spec["run_speed"] if fleeing else (_spec.get("stalk_speed", _spec["walk_speed"]) if stalking else _spec["walk_speed"]))
	if is_fawn():
		speed *= float(_spec["fawn_speed_factor"])
		var parent: WoodlandMammal = _adult_leader("deer")
		if fleeing and parent != null and global_position.distance_to(parent.global_position) > 35.0:
			direction = ((parent._end if parent._moving else parent.global_position) - global_position).normalized()
	elif is_piglet():
		speed *= float(_spec.get("piglet_speed_factor", 0.94))
		var sow: WoodlandMammal = _adult_leader("boar")
		if fleeing and sow != null and global_position.distance_to(sow.global_position) > 32.0:
			direction = ((sow._end if sow._moving else sow.global_position) - global_position).normalized()
	elif is_kid():
		speed *= float(_spec.get("kid_speed_factor", 0.92))
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	for fraction: float in [1.0, 0.6, 0.3]:
		for angle: float in [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.65, -1.65, 2.1, -2.1, PI]:
			var step: Vector2 = direction.rotated(angle) * distance * fraction
			if action == Mood.RETURN:
				step = step.limit_length(global_position.distance_to(home))
			var point: Vector2 = global_position + step
			if not test_move(global_transform, step) and _can_step(point) and _can_step(global_position + step * 0.5):
				var rolling: bool = _moving and mood == action and action in [Mood.FLEE, Mood.RETURN, Mood.CHASE]
				var ramp_in: float = 0.0 if rolling else float(_spec["motion_ramp"])
				var ramp_out: float = 0.0 if fleeing or (action == Mood.RETURN and point.distance_to(home) > 8.0) else float(_spec["motion_ramp"])
				_move_action(action, point, maxf(0.2, step.length() / speed / (1.0 - (ramp_in + ramp_out) * 0.5)))
				return
	_issue(Mood.ALERT if fleeing else Mood.REST, 0.6)


func _issue(action: Mood, duration: float, direction: float = INF, elapsed: float = 0.0) -> void:
	_command.rpc(action, duration, facing if is_inf(direction) else direction, global_position, global_position, elapsed, _gait_phase, false, _climb_height, _climb_height)


func _move_action(action: Mood, point: Vector2, duration: float) -> void:
	_command.rpc(action, duration, (point - global_position).angle(), global_position, point, 0.0, _gait_phase, _moving and mood == action and action in [Mood.FLEE, Mood.RETURN, Mood.CHASE], 0.0, 0.0)


func _climb_action(action: Mood, point: Vector2, duration: float, from_h: float, to_h: float) -> void:
	var heading: float = (point - global_position).angle() if point.distance_squared_to(global_position) > 0.5 else facing
	_command.rpc(action, duration, heading, global_position, point, 0.0, _gait_phase, false, from_h, to_h)


@rpc("authority", "call_local", "reliable")
func _command(action: int, duration: float, direction: float, start: Vector2, end: Vector2, elapsed: float, gait: float = 0.0, rolling: bool = false, climb_from: float = 0.0, climb_to: float = 0.0) -> void:
	mood = action as Mood
	_duration = maxf(0.1, duration)
	_elapsed = elapsed
	facing = direction
	_start = start
	_end = end
	_gait_start = gait
	_gait_phase = gait
	_rolling = rolling
	_climb_from = climb_from
	_climb_to = climb_to
	_climb_height = lerpf(climb_from, climb_to, clampf(elapsed / _duration, 0.0, 1.0)) if climb_from != climb_to else climb_to
	_moving = start.distance_squared_to(end) > 0.01 and mood in [Mood.WALK, Mood.FLEE, Mood.RETURN, Mood.SPECIAL, Mood.EMERGE, Mood.CHASE, Mood.STALK, Mood.CLIMB]
	if elapsed < 0.05:
		_voice_for(mood)
	if not _moving:
		global_position = end


## The sound set (assets/audio/sfx): what a species says when it enters a mood, with a chance so it stays rare. Every peer, cosmetic.
const VOICES: Dictionary = {
	"deer": {Mood.BARK: ["deer_call", 0.95], Mood.ALERT: ["deer_call", 0.25], Mood.FLEE: ["deer_call", 0.35]},
	"fox": {Mood.ALERT: ["fox_bark", 0.45], Mood.CHASE: ["fox_bark", 0.3], Mood.LISTEN: ["fox_bark", 0.08]},
	"badger": {Mood.BARK: ["badger_grunt", 0.85], Mood.ALERT: ["badger_grunt", 0.45], Mood.FLEE: ["badger_grunt", 0.3]},
	"boar": {Mood.BARK: ["boar_snort", 0.9], Mood.CHASE: ["boar_snort", 0.85], Mood.FORAGE: ["boar_grunt", 0.22], Mood.FLEE: ["boar_grunt", 0.4]},
	"lynx": {Mood.ALERT: ["lynx_call", 0.18], Mood.LISTEN: ["lynx_call", 0.12]},
	"squirrel": {Mood.BARK: ["squirrel_chatter", 0.92], Mood.ALERT: ["squirrel_chatter", 0.45]},
	"hex_goat": {Mood.REAR: ["goat_bleat", 0.92], Mood.BARK: ["goat_bleat", 0.85], Mood.ALERT: ["goat_bleat", 0.18]},
	"hex_toad": {Mood.BARK: ["toad_croak", 0.92]},
	"hedgehog": {Mood.FORAGE: ["hedgehog_snuffle", 0.4], Mood.UNROLL: ["hedgehog_snuffle", 0.6]},
	"bear": {Mood.REAR: ["bear_roar", 1.0], Mood.LOWER: ["bear_growl", 0.8], Mood.SWIPE: ["bear_growl", 0.5], Mood.ALERT: ["bear_growl", 0.35]},
}
var _voice_cool: float = 0.0


func _voice_for(next: Mood) -> void:
	var table: Dictionary = VOICES.get(species, {})
	if not table.has(next) or (has_method("is_cub") and bool(call("is_cub"))) or is_young():
		return
	var now: float = Time.get_ticks_msec() * 0.001
	if now < _voice_cool:
		return
	var entry: Array = table[next]
	if randf() > float(entry[1]):
		return
	_voice_cool = now + 5.5
	var loud: bool = species == "bear"
	Sfx.at(self, String(entry[0]), global_position, -2.0 if loud else -6.0, 0.06, 420.0 if loud else 260.0)


func _route_progress(t: float) -> float:
	if mood in [Mood.SPECIAL, Mood.CLIMB] or species == "hex_toad":
		return smoothstep(0.0, 1.0, t)
	var ramp_in: float = 0.0 if _rolling else float(_spec["motion_ramp"])
	var ramp_out: float = 0.0 if mood in [Mood.FLEE, Mood.CHASE] or (mood == Mood.RETURN and _end.distance_to(home) > 8.0) else float(_spec["motion_ramp"])
	var area: float = 1.0 - (ramp_in + ramp_out) * 0.5
	if ramp_in > 0.0 and t < ramp_in:
		var u: float = t / ramp_in
		return ramp_in * (u * u * u - 0.5 * u * u * u * u) / area
	if ramp_out > 0.0 and t > 1.0 - ramp_out:
		var u: float = (1.0 - t) / ramp_out
		return 1.0 - ramp_out * (u * u * u - 0.5 * u * u * u * u) / area
	return (t - ramp_in * 0.5) / area


func _advance() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var point: Vector2 = _start.lerp(_end, _route_progress(t))
	if multiplayer.is_server():
		var hit: KinematicCollision2D = null
		if _climb_from > 0.5 or _climb_to > 0.5:
			global_position = point
		else:
			hit = move_and_collide(point - global_position)
		_gait_phase = _gait_start + _start.distance_to(global_position) / float(_spec["run_stride"] if mood in [Mood.FLEE, Mood.CHASE] else _spec["walk_stride"])
		if hit == null and t >= 1.0:
			if mood == Mood.FLEE and _safe_time < float(_spec["safe_seconds"]) and _climb_to < 0.5:
				_step((global_position - _threat).normalized(), Mood.FLEE)
				return
			if mood == Mood.RETURN and (_rest_hours() or (_danger and species == "badger")) and global_position.distance_to(home) > 8.0:
				_step((home - global_position).normalized(), Mood.RETURN)
				return
		if hit != null or t >= 1.0:
			_settle.rpc(global_position, mood, _climb_to)
	else:
		global_position = point
		_gait_phase = _gait_start + _start.distance_to(global_position) / float(_spec["run_stride"] if mood in [Mood.FLEE, Mood.CHASE] else _spec["walk_stride"])
		if t >= 1.0:
			_moving = false


@rpc("authority", "call_local", "reliable")
func _settle(at: Vector2, previous: int, settled_climb: float = 0.0) -> void:
	global_position = at
	_start = at
	_end = at
	_moving = false
	_elapsed = 0.0
	_climb_from = settled_climb
	_climb_to = settled_climb
	_climb_height = settled_climb
	mood = previous as Mood if previous in [Mood.FLEE, Mood.RETURN, Mood.SPECIAL, Mood.CHASE, Mood.STALK] else Mood.REST
	_duration = 0.7 if mood == Mood.SPECIAL else 0.0


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server():
		_command.rpc_id(multiplayer.get_remote_sender_id(), mood, _duration, facing, _start, _end, _elapsed, _gait_start, _rolling, _climb_from, _climb_to)
