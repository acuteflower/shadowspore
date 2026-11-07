class_name WildBear
extends WoodlandMammal
## Shy omnivore: retreat first, warn persistent pursuers, briefly defend personal space.
## Cub follow/play and hunting use the same reliable, late-joinable action timeline.
var _pressure: Dictionary = {}
var _provoker: Player
var _defending: bool = false
var _defense_left: float = 0.0
var _attack_cd: float = 0.0
var _struck: Array[int] = []
var _prey: WildRabbit
var _hunt_left: float = 0.0
var _meal_cd: float = 10.0
var _last_swipe_elapsed: float = 0.0

func _init() -> void:
	species = "bear"

func _ready() -> void:
	super._ready()
	add_to_group("bears")
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	if not is_cub():
		add_to_group("predators")
	_meal_cd = _range("hunt_cooldown") * 0.3

func is_cub() -> bool:
	return appearance == 2

func _load_species() -> void:
	super._load_species()
	var shape: CircleShape2D = ($CollisionShape2D as CollisionShape2D).shape as CircleShape2D
	shape.radius = float(_spec["body_radius"]) * (0.55 if is_cub() else 1.0)
	if is_cub():
		_spec = _spec.duplicate(true)
		_spec["walk_speed"] = float(_spec["walk_speed"]) * float(_spec["cub_speed_factor"])
		_spec["run_speed"] = float(_spec["run_speed"]) * float(_spec["cub_speed_factor"])

func _adult() -> WoodlandMammal:
	for node: Node in get_tree().get_nodes_in_group("bears"):
		var bear: WildBear = node as WildBear
		if bear != self and bear.family_id == family_id and not bear.is_cub():
			return bear
	return null

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_attack_cd = maxf(0.0, _attack_cd - delta)
		_meal_cd = maxf(0.0, _meal_cd - delta)
		if _defending:
			_defense_left -= delta
		if is_instance_valid(_prey):
			_hunt_left -= delta
			if _danger or _hunt_left <= 0.0 or _prey.captured:
				_prey = null
			elif mood == Mood.CHASE and global_position.distance_to(_prey.global_position) < float(_spec["hunt_contact"]) and _line_clear(_prey.global_position):
				_prey.caught_by_predator()
				_prey = null
				_meal_cd = _range("hunt_cooldown")
				_issue(Mood.FORAGE, _range("forage_seconds"))
		if mood == Mood.SWIPE:
			_swipe_hit()
	super._physics_process(delta)

func _line_clear(point: Vector2) -> bool:
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, point, 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _sense() -> void:
	_danger = false
	var nearest: float = INF
	var visible_players: Array[int] = []
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.story_lock or player.fainting:
			continue
		var distance: float = global_position.distance_to(player.global_position)
		var alert: float = float(_spec["safe_range"] if mood == Mood.FLEE else _spec["alert_range"])
		if player.stealth.sneaking:
			alert *= float(_spec["sneak_multiplier"])
		if player.sprinting:
			alert *= float(_spec["sprint_multiplier"])
		if distance > alert or not _line_clear(player.global_position):
			continue
		visible_players.append(player.get_instance_id())
		var pressure: float = float(_pressure.get(player.get_instance_id(), 0.0))
		var following: bool = player.velocity.dot((global_position - player.global_position).normalized()) > 8.0
		var near_cub: bool = false
		if not is_cub():
			for relative: Node in get_tree().get_nodes_in_group("bears"):
				var cub: WildBear = relative as WildBear
				if cub.is_cub() and cub.family_id == family_id and cub.global_position.distance_to(player.global_position) < float(_spec["maternal_pressure_range"]):
					near_cub = true
		if not is_cub() and distance < float(_spec["pursuit_range"]) and (mood == Mood.FLEE and following or distance < float(_spec["pressure_range"]) or near_cub):
			pressure += float(_spec["sense_interval"])
		else:
			pressure = maxf(0.0, pressure - float(_spec["sense_interval"]) * float(_spec["pursuit_decay"]))
		_pressure[player.get_instance_id()] = pressure
		if pressure >= float(_spec["maternal_pursuit_seconds"] if near_cub else _spec["pursuit_seconds"]):
			_provoker = player
		_danger = true
		if distance < nearest:
			nearest = distance
			_threat = player.global_position
	for id: int in _pressure.keys():
		if not visible_players.has(id):
			_pressure[id] = maxf(0.0, float(_pressure[id]) - float(_spec["sense_interval"]) * float(_spec["pursuit_decay"]))
	# Shadows frighten bears too; other bear families do not.
	for node: Node in get_tree().get_nodes_in_group("predators"):
		if node is WildBear:
			continue
		var predator: Node2D = node as Node2D
		if global_position.distance_to(predator.global_position) < float(_spec["flee_range"]) and _line_clear(predator.global_position):
			_danger = true
			_threat = predator.global_position
			if mood not in [Mood.FLEE, Mood.SWIPE]:
				_step((global_position - _threat).normalized(), Mood.FLEE)
			return
	if _defending or mood in [Mood.REAR, Mood.LOWER, Mood.SWIPE]:
		return
	if not is_cub() and is_instance_valid(_provoker) and float(_pressure.get(_provoker.get_instance_id(), 0.0)) >= float(_spec["maternal_pursuit_seconds"]) and visible_players.has(_provoker.get_instance_id()):
		_defending = true
		_defense_left = float(_spec["chase_seconds"])
		_prey = null
		_issue(Mood.REAR, float(_spec["warning_seconds"]), (_provoker.global_position - global_position).angle())
		return
	if _danger and mood != Mood.FLEE:
		_prey = null
		_step((global_position - _threat).normalized(), Mood.FLEE)

func _think() -> void:
	if _elapsed < _duration:
		return
	if mood == Mood.REAR:
		if not is_instance_valid(_provoker) or global_position.distance_to(_provoker.global_position) > float(_spec["warning_release_range"]):
			_defending = false
			_pressure.clear()
		_issue(Mood.LOWER, float(_spec["lower_seconds"]))
		return
	if mood == Mood.SWIPE:
		_attack_cd = float(_spec["attack_recover"])
	if _defending:
		if not is_instance_valid(_provoker) or _provoker.health.current <= 0.0 or _provoker.story_lock or _provoker.fainting or _defense_left <= 0.0 or global_position.distance_to(home) > float(_spec["chase_leash"]) or global_position.distance_to(_provoker.global_position) > float(_spec["disengage_range"]) or not _line_clear(_provoker.global_position):
			_end_defense()
			return
		var distance: float = global_position.distance_to(_provoker.global_position)
		if distance < float(_spec["attack_range"]) - 4.0 and _attack_cd <= 0.0:
			_struck.clear()
			_last_swipe_elapsed = 0.0
			_issue(Mood.SWIPE, float(_spec["attack_seconds"]), (_provoker.global_position - global_position).angle())
		elif _attack_cd > 0.0:
			_issue(Mood.ALERT, minf(_attack_cd, 0.3), (_provoker.global_position - global_position).angle())
		else:
			_chase(_provoker.global_position)
		return
	if _danger:
		if mood != Mood.FLEE or not _moving:
			_step((global_position - _threat).normalized(), Mood.FLEE)
		return
	if mood == Mood.FLEE and _safe_time < float(_spec["safe_seconds"]):
		_step((global_position - _threat).normalized(), Mood.FLEE)
		return
	if is_cub():
		_cub_life()
		return
	if is_instance_valid(_prey) and _hunt_left > 0.0 and not _prey.captured:
		_chase(_prey.global_position)
		return
	if _meal_cd <= 0.0 and _rng.randf() < 0.35:
		for node: Node in get_tree().get_nodes_in_group("wildlife"):
			var rabbit: WildRabbit = node as WildRabbit
			if rabbit != null and not rabbit.captured and global_position.distance_to(rabbit.global_position) < float(_spec["hunt_range"]) and _line_clear(rabbit.global_position):
				_prey = rabbit
				_hunt_left = float(_spec["hunt_seconds"])
				_meal_cd = _range("hunt_cooldown")
				_issue(Mood.LISTEN, 0.7, (rabbit.global_position - global_position).angle())
				return
	var roll: float = _rng.randf()
	if roll < 0.45:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	elif roll < 0.8:
		_roam()
	elif roll < 0.93:
		_issue(Mood.GROOM, _range("groom_seconds"))
	else:
		_issue(Mood.SLEEP, _range("sleep_seconds"))

func _end_defense() -> void:
	_defending = false
	_pressure.clear()
	_provoker = null
	_issue(Mood.ALERT, 0.8)

func _cub_life() -> void:
	var parent: WoodlandMammal = _adult()
	if parent != null:
		var destination: Vector2 = parent.global_position + Vector2.from_angle(parent.facing + PI) * 26.0
		if parent._danger or parent._moving or global_position.distance_to(parent.global_position) > float(_spec["family_range"]):
			var step: Vector2 = (destination - global_position).limit_length(float(_spec["follow_step"]))
			if step.length() < float(_spec["follow_stop"]):
				_issue(Mood.ALERT, 0.5, parent.facing)
			elif _can_step(global_position + step) and not test_move(global_transform, step):
				_move_action(Mood.FLEE if parent._danger else Mood.WALK, global_position + step, maxf(0.3, step.length() / float(_spec["run_speed"] if parent._danger else _spec["walk_speed"])))
			else:
				_step(step.normalized(), Mood.FLEE if parent._danger else Mood.WALK)
			return
	if mood == Mood.PLAY:
		_issue(Mood.REST, _range("rest_seconds"))
	elif _rng.randf() < 0.45:
		# Small social approach before tumbling; every cub keeps its own timing.
		for node: Node in get_tree().get_nodes_in_group("bears"):
			var sibling: WildBear = node as WildBear
			if sibling != self and sibling.is_cub() and sibling.family_id == family_id and not sibling._danger and global_position.distance_to(sibling.global_position) < 65.0:
				if global_position.distance_to(sibling.global_position) > 22.0:
					_step((sibling.global_position - global_position).normalized(), Mood.WALK)
					return
		_issue(Mood.PLAY, _range("play_seconds"), facing + _rng.randf_range(-0.5, 0.5))
	elif _rng.randf() < 0.5:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	else:
		_roam()

func _step(direction: Vector2, action: Mood) -> void:
	if is_cub() and action == Mood.FLEE:
		var parent: WoodlandMammal = _adult()
		if parent != null and parent._moving:
			direction = (parent._end + Vector2(15, 16) - global_position).normalized()
	super._step(direction, action)

func _chase(point: Vector2) -> void:
	var step: Vector2 = (point - global_position).limit_length(float(_spec["chase_step"]))
	if step.length() > 2.0 and _can_step(global_position + step) and _can_step(global_position + step * 0.5) and not test_move(global_transform, step):
		_move_action(Mood.CHASE, global_position + step, maxf(0.2, step.length() / float(_spec["run_speed"]) / (1.0 if _moving and mood == Mood.CHASE else 1.0 - float(_spec["motion_ramp"]) * 0.5)))
	else:
		_prey = null
		if _defending:
			_end_defense()
		else:
			_issue(Mood.ALERT, 0.5)

func _swipe_hit() -> void:
	var start: float = float(_spec["attack_hit_start"])
	var end: float = float(_spec["attack_hit_end"])
	var crossed: bool = _elapsed >= start and _last_swipe_elapsed <= end
	_last_swipe_elapsed = _elapsed
	if not crossed:
		return
	for target: HurtboxComponent in HitScan.fan(self, global_position + Vector2(0, -12), Vector2.from_angle(facing), float(_spec["attack_range"]), deg_to_rad(float(_spec["attack_arc"])), 32):
		var feet: Vector2 = target.global_position + Vector2(0, 12)
		var same_floor: bool = Terrain.relief == null or absf(Terrain.relief.level_at(global_position) - Terrain.relief.level_at(feet)) < 0.45
		if not _struck.has(target.get_instance_id()) and same_floor and _line_clear(feet):
			_struck.append(target.get_instance_id())
			target.take_hit(float(_spec["attack_damage"]), global_position + Vector2(0, -12), float(_spec["attack_knockback"]))

func _process(delta: float) -> void:
	_visual_facing += clampf(angle_difference(_visual_facing, facing), -delta * 7.0, delta * 7.0)
	var col: int = int(_elapsed * 2.0) % 4
	var cols: int = 44
	var texture_path: String = String(_spec["texture"])
	match mood:
		Mood.FORAGE: col = 4 + int(_elapsed * 3.0) % 6
		Mood.WALK, Mood.RETURN: col = 10 + int(_gait_phase * 8.0) % 8
		Mood.ALERT, Mood.LISTEN: col = 18 + int(_elapsed * 2.0) % 4
		Mood.FLEE, Mood.CHASE: col = 22 + int(_gait_phase * 8.0) % 8
		Mood.GROOM: col = 30 + int(_elapsed * 3.0) % 4
		Mood.SLEEP: col = 34 + int(_elapsed * 1.4) % 4
		Mood.REAR: col = 38 + mini(5, int(_elapsed / (_duration * 0.55) * 6.0))
		Mood.LOWER: col = 43 - mini(5, int(_elapsed / _duration * 6.0))
		Mood.SWIPE:
			cols = 8
			texture_path = "res://assets/wildlife/bear_attack.png"
			col = mini(7, int(_elapsed / _duration * 8.0))
		Mood.PLAY:
			cols = 6
			texture_path = "res://assets/wildlife/bear_play.png"
			col = int(_elapsed * 3.0) % 6
	var texture: Texture2D = load(texture_path) as Texture2D
	if _sprite.texture != texture:
		_sprite.texture = texture
		_sprite.hframes = cols
		_sprite.vframes = 24
	var sector: int = posmod(roundi(_visual_facing / (PI / 4.0)), 8)
	_sprite.frame = (clampi(appearance, 0, 2) * 8 + sector) * cols + col
	queue_redraw()

func _advance() -> void:
	var chasing: bool = mood == Mood.CHASE
	super._advance()
	if multiplayer.is_server() and chasing and not _moving and mood == Mood.CHASE:
		# Decide the next pursuit segment immediately and preserve cruise/gait.
		_moving = true
		_think()
		if _start == _end:
			_moving = false
