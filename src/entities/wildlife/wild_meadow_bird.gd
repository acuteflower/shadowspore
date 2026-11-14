class_name WildMeadowBird
extends WildCorvid
## Species-specific lives over the shared flight/perch/network controller:
## - Owl: daylight bark-camouflage roost, 180-deg listening head-turns, silent nocturnal glides.
## - Woodpecker: vertical FirTree trunk clinging, hitch-climbing hops, resonant bark drumming + wood chips, undulating Wellenflug.
## - Jay: woodland edge acorn caching, cache squabbles with squirrels/crows, crest-raised "Räätsch!" forest sentinel alarm.
## - Robin: low-shyness garden & glade songster, follows rooting boars, digging badgers, and gardening players for worms.
## - Hoopoe: probe, crest display, buoyant flight.

var _chip_wait: float = 0.0
var _drum_sound_wait: float = 0.0
var _trunk_hops_done: int = 0
var _soar_laps_left: int = 0
var _soar_center: Vector2 = Vector2.ZERO
var _soar_angle: float = 0.0
var _soar_radius: float = 74.0
var _soar_dir: float = 1.0
var _raptor_shadow_tick: float = 0.0


func _init() -> void:
	species = "owl"


func _rest_time() -> bool:
	if species == "owl":
		if witch or appearance == 2:
			return false
		return TimeManager.night_amount() < float(_spec["awake_threshold"])
	return super._rest_time()


func _on_tree_trunk() -> bool:
	if species != "woodpecker" or _perch_path.is_empty() or _height < 4.0:
		return false
	var node: Node = get_node_or_null(NodePath(_perch_path))
	return node is FirTree


func _process(delta: float) -> void:
	super._process(delta)
	var cols: int = maxi(1, _sprite.hframes)
	var col: int = _sprite.frame % cols
	if species == "owl" and _call_pose <= 0.0:
		if state == State.ROOST and _rest_time():
			col = (58 + int(_elapsed * 1.2) % 4) if cols >= 62 else (int(_elapsed * 1.2) % 4)
		elif state in [State.IDLE, State.ROOST]:
			col = 22 + int(_elapsed * 0.85) % 4
	elif species == "woodpecker":
		if state == State.FLY and cols >= 62:
			var t_fly: float = clampf(_elapsed / maxf(_duration, 0.1), 0.0, 1.0)
			var takeoff_f: float = float(_spec.get("takeoff_fraction", 0.16))
			var landing_f: float = float(_spec.get("landing_fraction", 0.82))
			if t_fly >= takeoff_f and t_fly <= landing_f:
				var wave: float = sin(_elapsed * TAU * float(_spec.get("flight_bob_hz", 3.1)))
				# Authentic woodpecker Wellenflug: rapid flap burst climbing, wings folded tight like a dart when dipping!
				if wave < -0.12:
					col = 50 + int(_elapsed * 6.0) % 4
				else:
					col = 30 + int(_elapsed * float(_spec["flap_fps"])) % 8
		elif _call_pose <= 0.0 and _on_tree_trunk() and cols >= 62:
			if state in [State.IDLE, State.ROOST, State.WATCH]:
				col = 58 + int(_elapsed * 1.8) % 4
			elif state == State.PECK:
				col = 4 + int(_elapsed * 18.0) % 6
		if state == State.PECK and not _moving:
			_drum_fx(delta)
	elif species == "hoopoe" and state == State.ROOST:
		col = int(_elapsed * 1.4) % 4
	elif species == "hoopoe" and state == State.WATCH and _call_pose <= 0.0:
		col = 22 + mini(3, int(_elapsed * 6.0))
	elif species == "desert_falcon" and cols >= 62:
		if state == State.FLY and _height_from > 36.0 and _height_to > 36.0:
			# Wide lazy thermal soaring: outstretched scythe wings with only rare corrective wingbeats
			if fmod(_elapsed, 4.4) < 3.85:
				col = 50 + int(_elapsed * 2.2) % 4
			else:
				col = 30 + int(_elapsed * float(_spec["flap_fps"])) % 8
		elif state == State.WATCH and _perch_path.is_empty() and _height > 36.0:
			# Brief mid-air wind-hover ("Rüttelflug") scanning the dunes below
			col = 30 + int(_elapsed * 15.0) % 8
		if multiplayer.is_server() and _height > 26.0 and state in [State.FLY, State.WATCH]:
			_raptor_shadow_tick -= delta
			if _raptor_shadow_tick <= 0.0:
				_raptor_shadow_tick = 0.38
				_cast_falcon_shadow_alarm()
	_sprite.frame = (_sprite.frame / cols) * cols + col


func _drum_fx(delta: float) -> void:
	_chip_wait -= delta
	_drum_sound_wait -= delta
	if _drum_sound_wait <= 0.0:
		_drum_sound_wait = _rng.randf_range(0.95, 1.55)
		Sfx.at(self, "woodpecker_drum", global_position + Vector2(0.0, -_height), -11.5, 0.06, 290.0)
	if _chip_wait <= 0.0:
		_chip_wait = _rng.randf_range(0.16, 0.28)
		_spawn_wood_chip()


func _spawn_wood_chip() -> void:
	if not is_inside_tree():
		return
	var chip: Polygon2D = Polygon2D.new()
	var poly: PackedVector2Array = PackedVector2Array([Vector2(-1.0, -0.5), Vector2(1.0, -0.5), Vector2(1.0, 0.5), Vector2(-1.0, 0.5)])
	chip.polygon = poly
	chip.color = Color(0.84, 0.68, 0.44, 0.92) if _rng.randf() < 0.6 else Color(0.56, 0.41, 0.27, 0.92)
	chip.top_level = true
	chip.z_index = 2
	add_child(chip)
	chip.global_position = global_position + Vector2(cos(facing) * 3.0, -_height - 5.0)
	var drift: Vector2 = Vector2(-cos(facing) * _rng.randf_range(5.0, 11.0) + _rng.randf_range(-3.0, 3.0), _rng.randf_range(7.0, 14.0))
	var tw: Tween = chip.create_tween()
	tw.set_parallel(true)
	tw.tween_property(chip, "global_position", chip.global_position + drift, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(chip, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(chip.queue_free)


func _preferred_cruise(panic: bool, goal_height: float) -> float:
	if species == "owl" and not panic and not _rest_time() and _height <= 1.0 and goal_height <= 1.0:
		return float(_spec["night_flight_height"])
	return super._preferred_cruise(panic, goal_height)


func _advance() -> void:
	super._advance()
	if species in ["hoopoe", "woodpecker", "robin"] and _moving and state == State.FLY and _spec.has("flight_bob"):
		var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
		_height += sin(_elapsed * TAU * float(_spec["flight_bob_hz"])) * float(_spec["flight_bob"]) * sin(t * PI)


func _finish(at: Vector2, height: float, perch: String) -> void:
	super._finish(at, height, perch)
	if species == "woodpecker" and not perch.is_empty():
		var node: Node = get_node_or_null(NodePath(perch))
		if node is FirTree:
			var tree: FirTree = node as FirTree
			facing = (tree.global_position - global_position).angle()
			if height <= 13.0:
				_trunk_hops_done = 0


func _think() -> void:
	if _panic_delay >= 0.0:
		return
	if _danger or _caution_left > 0.0:
		super._think()
		return
	match species:
		"owl":
			_owl_life()
		"woodpecker":
			_woodpecker_life()
		"jay":
			_jay_life()
		"robin":
			_robin_life()
		"desert_falcon":
			_desert_falcon_life()
		_:
			_hoopoe_life()


func _owl_life() -> void:
	if _rest_time():
		if state in [State.ROOST, State.WATCH] and _elapsed < _duration:
			return
		if _perch_path.is_empty() and _take_wing(false):
			return
		_set_mood(State.ROOST, _range("sleep_seconds"))
		return
	if state == State.ROOST:
		_set_mood(State.PECK, _range("listen_seconds"))
		return
	if _elapsed < _duration:
		return
	if state == State.PECK:
		if _height <= 1.0 and _rng.randf() < 0.35:
			_walk(Vector2.from_angle(_rng.randf() * TAU))
			return
		if _take_wing(false, false, _rng.randf() < 0.45):
			_spook_night_prey()
			return
	if _height <= 1.0 and _take_wing(false):
		return
	if _rng.randf() < 0.22:
		_set_mood(State.PREEN, _range("preen_seconds"))
	else:
		_set_mood(State.PECK, _range("listen_seconds"))


func _woodpecker_life() -> void:
	if _rest_time():
		if not _perch_path.is_empty():
			_set_mood(State.ROOST, _range("roost_seconds"))
			return
		if _take_wing(false, false, false, true):
			return
		_set_mood(State.ROOST, _range("roost_seconds"))
		return
	if _elapsed < _duration:
		return
	if _on_tree_trunk():
		var tree: FirTree = get_node_or_null(NodePath(_perch_path)) as FirTree
		if tree != null:
			facing = (tree.global_position - global_position).angle()
		var max_trunk_h: float = 19.0 if (tree != null and tree.variant == 0) else 27.0
		var roll_t: float = _rng.randf()
		# Hitch-hop vertically up the bark, drum for beetles, then bounding-fly to a fresh trunk!
		if state != State.PECK and roll_t < 0.58:
			_drum_sound_wait = 0.04
			_chip_wait = 0.08
			_set_mood(State.PECK, _range("peck_seconds"))
			return
		if _height + 4.5 <= max_trunk_h and _trunk_hops_done < 4 and roll_t < 0.86:
			_trunk_hop_up(minf(max_trunk_h, _height + _rng.randf_range(4.5, 6.5)))
			return
		if _take_wing(false, false, false, true):
			return
		_set_mood(State.WATCH, _range("watch_seconds"))
		return
	if not _perch_path.is_empty(): ## perched on a FallenLog
		if state != State.PECK and _rng.randf() < 0.56:
			_drum_sound_wait = 0.04
			_chip_wait = 0.08
			_set_mood(State.PECK, _range("peck_seconds"))
			return
		if _take_wing(false, false, false, true):
			return
		_set_mood(State.PREEN, _range("preen_seconds"))
		return
	if _take_wing(false, false, false, true):
		return
	if _rng.randf() < 0.55:
		_hop_step(Vector2.from_angle(_rng.randf() * TAU))
	else:
		_set_mood(State.PECK, _range("peck_seconds"))


func _trunk_hop_up(next_height: float) -> void:
	_trunk_hops_done += 1
	_act.rpc(State.HOP, 0.26, facing, global_position, global_position, Vector2.ZERO, _height, next_height, next_height, _perch_path, 0.0)


func _jay_life() -> void:
	if _rest_time():
		super._think()
		return
	if _elapsed < _duration:
		return
	if not _perch_path.is_empty():
		var perch_roll: float = _rng.randf()
		if perch_roll < 0.42 and _take_wing(false, false, true):
			return
		if perch_roll < 0.72:
			_set_mood(State.WATCH, _range("watch_seconds"))
		else:
			_set_mood(State.PREEN, _range("preen_seconds"))
		return
	# Cache rivalry on the forest floor: scold or hop assertively when a squirrel or crow crowds an acorn spot!
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var m: WoodlandMammal = node as WoodlandMammal
		if m != null and m.species == "squirrel" and m._climb_height < 2.0 and m.global_position.distance_to(global_position) < 34.0:
			facing = (m.global_position - global_position).angle()
			if _call_left > 2.5:
				_request_call(false)
			_set_mood(State.WATCH, 1.4)
			return
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var other: WildCorvid = node as WildCorvid
		if other != self and other.state != State.FLY and other._height < 1.0 and other.global_position.distance_to(global_position) < float(_spec["personal_space"]) * 1.25:
			_hop_step((global_position - other.global_position).normalized())
			return
	var roll: float = _rng.randf()
	if roll < float(_spec["relocate_chance"]) and _take_wing(false):
		return
	if roll < 0.48:
		var goal_dir: Vector2 = (home - global_position).normalized() if global_position.distance_to(home) > 85.0 else Vector2.from_angle(_rng.randf() * TAU)
		if _rng.randf() < 0.72:
			_hop_step(goal_dir)
		else:
			_walk(goal_dir)
	elif roll < 0.80:
		_set_mood(State.PECK, _range("peck_seconds"))
	elif roll < 0.92:
		_set_mood(State.WATCH, _range("watch_seconds") * 0.7)
	else:
		_set_mood(State.PREEN, _range("preen_seconds"))


func _robin_life() -> void:
	if _rest_time():
		super._think()
		return
	if _elapsed < _duration:
		return
	var night_amt: float = TimeManager.night_amount()
	var crepuscular_song: bool = night_amt >= 0.08 and night_amt <= 0.46
	if not _perch_path.is_empty():
		if crepuscular_song and _call_left > 3.2 and _rng.randf() < 0.55:
			_request_call(false)
			_set_mood(State.WATCH, _range("watch_seconds"))
			return
		var p_roll: float = _rng.randf()
		if p_roll < 0.44 and _take_wing(false, false, true):
			return
		if p_roll < 0.74:
			_set_mood(State.WATCH, _range("watch_seconds"))
		else:
			_set_mood(State.PREEN, _range("preen_seconds"))
		return
	# Gardener's & wild-boar companion: follow rooting boars, digging badgers, or calm players at a polite 26..40 px ring to snatch grubs!
	var disturber: Vector2 = _find_soil_disturber()
	if disturber.is_finite():
		var dist_d: float = global_position.distance_to(disturber)
		if dist_d > 42.0:
			_hop_step((disturber - global_position).normalized())
			return
		if dist_d < 22.0:
			_hop_step((global_position - disturber).normalized())
			return
		facing = (disturber - global_position).angle()
		if state != State.PECK and _rng.randf() < 0.65:
			_set_mood(State.PECK, _range("peck_seconds"))
		else:
			_set_mood(State.WATCH, _range("watch_seconds") * 0.75)
		return
	var r_roll: float = _rng.randf()
	if crepuscular_song and r_roll < 0.24 and _take_wing(false, false, false, true):
		return
	if r_roll < float(_spec["relocate_chance"]) and _take_wing(false):
		return
	if r_roll < 0.52:
		var dir: Vector2 = (home - global_position).normalized() if global_position.distance_to(home) > 70.0 else Vector2.from_angle(_rng.randf() * TAU)
		_hop_step(dir)
	elif r_roll < 0.80:
		_set_mood(State.PECK, _range("peck_seconds"))
	elif r_roll < 0.92:
		_set_mood(State.IDLE, _range("idle_seconds"))
	else:
		_set_mood(State.PREEN, _range("preen_seconds"))


func _find_soil_disturber() -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_d: float = 105.0
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var m: WoodlandMammal = node as WoodlandMammal
		if m == null:
			continue
		var digging: bool = (m.species == "boar" and m.mood in [WoodlandMammal.Mood.FORAGE, WoodlandMammal.Mood.SPECIAL]) or (m.species == "badger" and m.mood == WoodlandMammal.Mood.SPECIAL)
		if digging:
			var d: float = global_position.distance_to(m.global_position)
			if d < best_d:
				best_d = d
				best = m.global_position
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.sprinting:
			continue
		var dp: float = global_position.distance_to(player.global_position)
		if dp < best_d and dp > 24.0:
			var active_tool: String = String(Items.definition(player.inventory.active_stack()).get("tool", ""))
			if active_tool in ["hoe", "shovel", "axe", "pickaxe", "sickle"] or TownManager.calm_at(get_tree(), global_position) < 0.85:
				best_d = dp
				best = player.global_position
	return best


func _hoopoe_life() -> void:
	if _rest_time():
		super._think()
		return
	if _elapsed < _duration:
		return
	if not _perch_path.is_empty():
		if not _take_wing(false, false, true):
			_set_mood(State.PREEN, _range("preen_seconds"))
		return
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var bird: WildCorvid = node as WildCorvid
		if bird != self and bird.species in ["crow", "raven"] and bird.state != State.FLY and bird._height < 1.0 and bird.global_position.distance_to(global_position) < float(_spec["personal_space"]) * 1.4:
			_walk((global_position - bird.global_position).normalized())
			return
	var roll: float = _rng.randf()
	if state == State.PECK and roll < 0.6:
		_walk(Vector2.from_angle(_rng.randf() * TAU))
	elif roll < 0.09 and _take_wing(false, false, true):
		return
	elif roll < 0.25:
		_set_mood(State.WATCH, 1.2)
	elif roll < 0.82:
		_set_mood(State.PECK, _range("peck_seconds"))
	else:
		_set_mood(State.PREEN, _range("preen_seconds"))


func hear_alarm(source: Vector2, rally: Vector2 = Vector2.INF) -> void:
	if species == "owl" and _rest_time():
		if multiplayer.is_server() and state != State.FLY:
			_threat = source
			_set_mood(State.WATCH, _range("listen_seconds"))
		return
	super.hear_alarm(source, rally)


func _request_call(alarm: bool) -> void:
	if species == "owl" and _rest_time() and state == State.ROOST and not alarm:
		_call_left = _range("call_seconds") * 3.0
		return
	if species == "owl":
		_spook_night_prey()
	super._request_call(alarm)


func _spook_night_prey() -> void:
	if not multiplayer.is_server():
		return
	for node: Node in get_tree().get_nodes_in_group("wildlife"):
		var prey: Node2D = node as Node2D
		if prey != null and prey.global_position.distance_to(global_position) < 115.0 and prey.has_method("hear_alarm"):
			prey.call("hear_alarm", global_position)


func _cast_falcon_shadow_alarm() -> void:
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var m: WoodlandMammal = node as WoodlandMammal
		if m != null and m.species in ["agama", "jerboa"] and m.global_position.distance_to(global_position) < 88.0:
			m.hear_raptor_overhead(global_position)


func _desert_falcon_life() -> void:
	if _rest_time():
		_soar_laps_left = 0
		if not _perch_path.is_empty():
			_set_mood(State.ROOST, _range("roost_seconds"))
			return
		if _take_wing(false, false, false, true):
			return
		if _height > 2.0:
			var descend: Vector2 = home
			_act.rpc(State.FLY, 2.2, (descend - global_position).angle(), global_position, descend, Vector2.ZERO, _height, 0.0, maxf(_height, 42.0), "", 0.0)
			return
		_set_mood(State.ROOST, _range("roost_seconds"))
		return
	if _elapsed < _duration and not (_perch_path.is_empty() and _height > 36.0 and state == State.WATCH and _soar_laps_left > 0 and _elapsed >= 1.2):
		return
	# Continue or finish high-altitude thermal circle flight
	if _soar_laps_left > 0:
		if _height > 45.0 and state != State.WATCH and _rng.randf() < 0.22:
			# Brief stationary wind-hover ("Rüttelflug") scanning sand & quartz below
			_set_mood(State.WATCH, _rng.randf_range(1.1, 1.7))
			return
		_soar_laps_left -= 1
		var step_ang: float = (PI * 0.52) * _soar_dir
		var next_ang: float = _soar_angle + step_ang
		var goal: Vector2 = _soar_center + Vector2.from_angle(next_ang) * _soar_radius
		var chord: Vector2 = goal - global_position
		var sagitta: Vector2 = Vector2.from_angle(_soar_angle + step_ang * 0.5) * (_soar_radius * 0.28)
		var soar_h: float = _height if _height > 54.0 else _range("soar_height")
		var dur: float = maxf(2.0, (chord.length() + sagitta.length()) / (float(_spec["flight_speed"]) * 0.62))
		_soar_angle = next_ang
		_act.rpc(State.FLY, dur, chord.angle(), global_position, goal, sagitta, _height, soar_h, maxf(_height, soar_h) + 3.0, "", 0.0)
		return
	# Descending from thermal soar to a cactus/palm/monolith perch (or desert ridge)
	if _perch_path.is_empty() and _height > 20.0:
		if not _take_wing(false, false, false, true):
			if not _take_wing(false, false, true, false):
				_start_thermal_soar()
		return
	# Perched on crown_cactus, sun_palm, or sun_quartz_rock
	if not _perch_path.is_empty():
		var p_roll: float = _rng.randf()
		if p_roll < 0.42:
			_start_thermal_soar()
			return
		if p_roll < 0.72:
			_set_mood(State.WATCH, _range("watch_seconds"))
		elif p_roll < 0.88:
			_set_mood(State.PECK, _range("peck_seconds"))
		else:
			_set_mood(State.PREEN, _range("preen_seconds"))
		return
	# On ground: launch into thermal updrafts or hop/scan
	if _rng.randf() < 0.68:
		_start_thermal_soar()
	else:
		_set_mood(State.WATCH, _range("watch_seconds") * 0.7)


func _start_thermal_soar() -> void:
	if _population != null and _population.has_method("release_perch"):
		_population.call("release_perch", self)
	_soar_center = home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 42.0)
	_soar_radius = _range("soar_radius")
	_soar_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_soar_angle = (global_position - _soar_center).angle()
	_soar_laps_left = _rng.randi_range(3, 6)
	var first_ang: float = _soar_angle + (PI * 0.5) * _soar_dir
	var goal: Vector2 = _soar_center + Vector2.from_angle(first_ang) * _soar_radius
	var soar_h: float = _range("soar_height")
	var dur: float = maxf(2.3, global_position.distance_to(goal) / (float(_spec["flight_speed"]) * 0.72))
	_soar_angle = first_ang
	_act.rpc(State.FLY, dur, (goal - global_position).angle(), global_position, goal, (goal - global_position).orthogonal().normalized() * (_soar_dir * 26.0), _height, soar_h, soar_h + 6.0, "", 0.0)
