class_name NightDirector
extends Node
## The night (docs/nacht_monster_konzept.md): host only. By day a few weakened leftovers lurk in the shade; once the dark has fallen, creatures climb out of the
## the dark ground and the edge of the world (the spider's own birth animation, `ShadowBirth`), patrol the dark, keep away from the town's light and, when the life in the base lures them, rush it
## through its gaps. How many and how tough follows the strongest player's level, the day, the players and the town (`NightRules`, data/night.json).
## It spawns through `WorldLevel.spawn_species`, so the enemies replicate like every other; the AI hooks live in `NightBehavior`.

const TICK: float = 0.5

var special: String = "none" ## this night's kind: none | flood | silent
var lure: float = 0.0 ## how much life in the base draws them (0 .. threshold)

var _world: Variant ## avoids the WorldLevel -> player -> HUD -> WorldLevel preload cycle
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _clock: float = 0.0
var _spawn_clock: float = 0.0
var _burn_clock: float = 0.0
var _remnant_wait: float = 60.0
var _in_window: bool = false
var _night_id: int = -1
var _announced: int = -1
var _ledger: Dictionary = {} ## group key -> {spent: float, died: bool}
var _live: Array[Dictionary] = [] ## {node, nb, key, cost, hp}
var _died: Dictionary = {} ## player name -> the night (id) it fell in
var _hooked: Dictionary = {} ## player instance id -> true
var _hunters_left: int = 0
var _raid: Dictionary = {"state": "idle", "time": 0.0, "target": null, "members": []}
var _raid_cooldown: float = 0.0
var _dawn_marked: bool = false


func setup(world: Variant) -> void:
	_world = world
	name = "NightDirector"
	_rng.seed = hash([int(world._map.world_seed), 5113])


func _ready() -> void:
	add_to_group("night_director")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(multiplayer.is_server())


func _process(delta: float) -> void:
	_clock += delta
	if _clock < TICK:
		return
	_clock = 0.0
	tick()


# ---------------------------------------------------------------------------------- questions

## Nights only start once the town stands (the opening is told by the story, in daylight terms and at its own pace).
func active() -> bool:
	if not multiplayer.is_server() or not bool(_world.opening_over):
		return false
	var town: TownManager = _world.town()
	return town != null and town.founded


func live_count(include_remnants: bool = true) -> int:
	var count: int = 0
	for entry: Dictionary in _live:
		if include_remnants or not (entry.nb as NightBehavior).remnant:
			count += 1
	return count


func entries() -> Array[Dictionary]:
	return _live


func raid_state() -> String:
	return String(_raid.state)


func night_id() -> int:
	return _night_id


## The budget one group of players has tonight (see `NightRules.budget`, the special night and a fall earlier tonight change it).
func group_budget(members: Array[Player], died: bool = false) -> float:
	var levels: Array[int] = []
	for member: Player in members:
		levels.append(member.progress.level)
	var value: float = NightRules.budget(NightRules.group_level(levels), TimeManager.day, members.size()) * float(NightRules.special_spec(special).budget)
	return value * (float((NightRules.config().budget as Dictionary).after_death) if died else 1.0)


## Health scale of what this group meets (level + overall power).
func group_strength(members: Array[Player]) -> float:
	var levels: Array[int] = []
	var weapon: float = 0.0
	for member: Player in members:
		levels.append(member.progress.level)
		var stack: Dictionary = member.inventory.equipment.get("main_hand", {}) as Dictionary
		if not stack.is_empty():
			weapon = maxf(weapon, float((DataRegistry.get_entry("items", String(stack.id)).get("stats", {}) as Dictionary).get("damage", 0.0)))
	var town: TownManager = _world.town()
	var town_levels: int = (TownRules.config().levels as Array).size()
	return NightRules.strength(NightRules.group_level(levels), NightRules.power(weapon, town.level() if town != null else 0, town_levels))


# ---------------------------------------------------------------------------------- the tick

## One pass; public for the tests.
func tick() -> void:
	_prune()
	var progress: float = NightRules.progress(TimeManager.time_of_day)
	var window: bool = progress >= 0.0
	if window != _in_window:
		_in_window = window
		if window:
			_begin_night()
		else:
			_end_night()
	if not active():
		return
	_dusk_notice()
	var players: Array[Player] = _players()
	_hook_deaths()
	if window:
		_night(players, progress)
	else:
		_day(players)
	_lure_tick(players, progress)
	_dawn(window)
	_assign_goals(players)
	_burn()


func _begin_night() -> void:
	_night_id = TimeManager.day
	_ledger.clear()
	lure = 0.0
	_end_raid(false)
	_raid_cooldown = 0.0
	_dawn_marked = false
	special = NightRules.special_for(int(_world._map.world_seed), _night_id)
	_hunters_left = int(NightRules.special_spec(special).get("hunters", 0))


## The morning: the night's reward for a group that held (a banner and a little XP), and every creature turns for the dark.
func _end_night() -> void:
	if active() and not _ledger.is_empty():
		var rewarded: bool = false
		for key: String in _ledger:
			var entry: Dictionary = _ledger[key] as Dictionary
			if bool(entry.died) or float(entry.spent) <= 0.0:
				continue
			for player: Player in _players():
				if _key_has(key, player):
					var survive: Dictionary = NightRules.config().survive as Dictionary
					player.progress.award(0, roundi(float(survive.xp_base) + float(survive.xp_per_level) * float(player.progress.level)))
					rewarded = true
		if rewarded:
			(_world.town() as TownManager).banner("NACHT ÜBERSTANDEN", "TAG %d" % (TimeManager.day + 1))
			(_world.town() as TownManager).emit_event("night_survived", {})
	_end_raid(false)


## A special night is announced at dusk (the first sign that the dark will not be an ordinary one).
func _dusk_notice() -> void:
	var t: float = TimeManager.time_of_day
	if _announced == TimeManager.day or t < 0.76 or t >= float(NightRules.config().window.start):
		return
	_announced = TimeManager.day
	var kind: String = NightRules.special_for(int(_world._map.world_seed), TimeManager.day)
	if kind != "none":
		(_world.town() as TownManager).banner(String(NightRules.special_spec(kind).notice), "")


# ---------------------------------------------------------------------------------- players and groups

func _players() -> Array[Player]:
	var out: Array[Player] = []
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.story_lock or player.intro != null or player.fainting:
			continue
		if Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position):
			continue
		out.append(player)
	return out


static func _key(members: Array) -> String:
	var ids: PackedStringArray = []
	for member: Variant in members:
		ids.append(str((member as Player).name))
	ids.sort()
	return ",".join(ids)


static func _key_has(key: String, player: Player) -> bool:
	return str(player.name) in key.split(",")


func _hook_deaths() -> void:
	for player: Player in Player.all:
		if _hooked.has(player.get_instance_id()):
			continue
		_hooked[player.get_instance_id()] = true
		player.health.died.connect(func() -> void: _died[str(player.name)] = _night_id)


# ---------------------------------------------------------------------------------- the night

func _night(players: Array[Player], progress: float) -> void:
	var cfg: Dictionary = NightRules.config()
	var points: Array[Vector2] = []
	for player: Player in players:
		points.append(player.global_position)
	var groups: Array[Array] = NightRules.cluster(points, float((cfg.groups as Dictionary).radius_tiles) * TownRules.TILE)
	_spawn_clock += TICK
	var may_spawn: bool = _spawn_clock >= float((cfg.spawn as Dictionary).interval)
	if may_spawn:
		_spawn_clock = 0.0
	for group: Array in groups:
		var members: Array[Player] = []
		for index: Variant in group:
			members.append(players[index as int])
		var key: String = _key(members)
		var entry: Dictionary = _ledger.get(key, {"spent": 0.0, "died": false}) as Dictionary
		for member: Player in members:
			if int(_died.get(str(member.name), -2)) == _night_id:
				entry.died = true
		_ledger[key] = entry
		if may_spawn and NightRules.spawning(progress):
			_try_spawn(key, members, entry, progress)


func _try_spawn(key: String, members: Array[Player], entry: Dictionary, progress: float) -> bool:
	var groups: Dictionary = NightRules.config().groups as Dictionary
	if live_count(false) >= int(groups.global_cap) or _alive_in(key) >= int(groups.alive_cap):
		return false
	var budget: float = group_budget(members, bool(entry.died))
	var left: float = budget * NightRules.released(progress) - float(entry.spent)
	if left < 0.5:
		return false
	var levels: Array[int] = []
	for member: Player in members:
		levels.append(member.progress.level)
	var level: int = NightRules.group_level(levels)
	var hunter: bool = _hunters_left > 0 and float(entry.spent) >= 2.0
	var id: String = "shadow_spider" if hunter else NightRules.pick_species(NightRules.available(budget, level, TimeManager.day), left, 1.0, _rng)
	if id == "":
		return false
	var spot: Dictionary = spawn_spot(members)
	if spot.is_empty():
		return false
	var spec: Dictionary = NightRules.special_spec(special)
	var strength: float = group_strength(members)
	var health: float = strength * float(spec.health) * (float(spec.get("hunter_health", 1.0)) if hunter else 1.0)
	var damage: float = NightRules.damage_scale(strength) * float(spec.damage)
	var enemy: Node2D = _spawn(id, spot.pos as Vector2, health, damage, key, NightRules.cost_of(id), hunter)
	if enemy == null:
		return false
	if hunter:
		_hunters_left -= 1
	entry.spent = float(entry.spent) + NightRules.cost_of(id)
	return true


## Spawns one creature of the night and gives it its behaviour. Public for the tests.
func _spawn(id: String, pos: Vector2, health_scale: float, damage_scale: float, key: String, cost: float, hunter: bool, remnant: bool = false) -> Node2D:
	var enemy: Node2D = _world.spawn_species(id, pos, _rng.randf() * TAU, health_scale, damage_scale, true) as Node2D
	if enemy == null:
		return null
	var def: Dictionary = DataRegistry.get_entry("enemies", id)
	var behavior: NightBehavior = NightBehavior.new()
	behavior.town = _world.town()
	behavior.key = key
	behavior.cost = cost
	behavior.hunter = hunter
	behavior.remnant = remnant
	behavior.home = pos
	behavior.top_speed = float(def.get("chase_speed", def.get("move_speed", 100.0)))
	if remnant:
		behavior.speed_cap = behavior.top_speed * float((NightRules.config().remnants as Dictionary).speed)
	enemy.set("night", behavior)
	var entry: Dictionary = {"node": enemy, "nb": behavior, "key": key, "cost": cost}
	_live.append(entry)
	(enemy.get_node("HealthComponent") as HealthComponent).died.connect(_on_killed.bind(entry))
	return enemy


## A kill gives a share of its cost back to the group's budget, so a fought-off wave is followed by the next one (not by an empty night).
func _on_killed(entry: Dictionary) -> void:
	var behavior: NightBehavior = entry.nb as NightBehavior
	var node: Node = entry.node as Node
	if behavior.remnant or not is_instance_valid(node) or (node.get_node("HealthComponent") as HealthComponent).last_attacker == 0:
		return
	_refund(String(entry.key), float(entry.cost) * float((NightRules.config().budget as Dictionary).refund_on_kill))


func _refund(key: String, amount: float) -> void:
	if _ledger.has(key):
		var ledger: Dictionary = _ledger[key] as Dictionary
		ledger.spent = maxf(0.0, float(ledger.spent) - amount)


func _alive_in(key: String) -> int:
	var count: int = 0
	for entry: Dictionary in _live:
		if String(entry.key) == key and not (entry.nb as NightBehavior).remnant:
			count += 1
	return count


## Drops entries of creatures that are gone and sends home the ones left far behind (they were born for a group that moved on); the budget they held comes back.
func _prune() -> void:
	var far: float = float((NightRules.config().groups as Dictionary).despawn_tiles) * TownRules.TILE
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _live:
		if not is_instance_valid(entry.node):
			continue
		var node: Node2D = entry.node as Node2D
		if node.is_queued_for_deletion() or (node.get_node("HealthComponent") as HealthComponent).current <= 0.0:
			continue
		var near: bool = false
		for player: Player in Player.all:
			if player.global_position.distance_to(node.global_position) <= far:
				near = true
				break
		if not near and not Player.all.is_empty():
			_refund(String(entry.key), float(entry.cost))
			node.queue_free()
			continue
		keep.append(entry)
	_live = keep


# ---------------------------------------------------------------------------------- where they come from

## A place for a new creature near the group: open dark ground, or a bit of coast. {} when none fits. Public for the tests.
func spawn_spot(members: Array[Player]) -> Dictionary:
	var spawn: Dictionary = NightRules.config().spawn as Dictionary
	var sources: Dictionary = spawn.sources as Dictionary
	var dark_first: bool = _rng.randf() * (float(sources.dark) + float(sources.edge)) < float(sources.dark)
	var spot: Dictionary = _dark_spot(members, false) if dark_first else _dark_spot(members, true)
	if spot.is_empty():
		spot = _dark_spot(members, dark_first)
	return spot


func _clear_to_spawn(pos: Vector2, members: Array[Player]) -> bool:
	var spawn: Dictionary = NightRules.config().spawn as Dictionary
	var town: TownManager = _world.town()
	if town.spawn_blocked(pos) or not bool(_world.navigation_floor(pos)):
		return false
	var nearest: float = INF
	for member: Player in members:
		nearest = minf(nearest, member.global_position.distance_to(pos))
	if nearest < float(spawn.keep_clear_tiles) * TownRules.TILE or nearest > float((spawn.ring_tiles as Array)[1]) * TownRules.TILE:
		return false
	return String(_world.town_probe(Rect2(pos - Vector2(10, 10), Vector2(20, 20)))) == ""


## A random point in the ring round a random member (`coast`: only close to the shore) that is dark, free and loaded.
func _dark_spot(members: Array[Player], coast: bool) -> Dictionary:
	var spawn: Dictionary = NightRules.config().spawn as Dictionary
	var ring: Array = spawn.ring_tiles as Array
	for attempt: int in 14:
		var member: Player = members[_rng.randi() % members.size()]
		var pos: Vector2 = member.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(float(ring[0]), float(ring[1])) * TownRules.TILE
		if coast:
			var inland: float = float(_world.coast_tiles(pos))
			if inland < 2.0 or inland > float(spawn.edge_tiles):
				continue
		if _clear_to_spawn(pos, members):
			return {"pos": pos.round()}
	return {}


# ---------------------------------------------------------------------------------- the day

## By day: now and then a weakened leftover in the shade of a tree.
func _day(players: Array[Player]) -> void:
	var remnants: Dictionary = NightRules.config().remnants as Dictionary
	_remnant_wait -= TICK
	if _remnant_wait > 0.0:
		return
	var span: Array = remnants.interval as Array
	_remnant_wait = _rng.randf_range(float(span[0]), float(span[1]))
	if TimeManager.sun_amount() < float(remnants.min_sun) or players.is_empty():
		return
	var points: Array[Vector2] = []
	for player: Player in players:
		points.append(player.global_position)
	for group: Array in NightRules.cluster(points, float((NightRules.config().groups as Dictionary).radius_tiles) * TownRules.TILE):
		var members: Array[Player] = []
		for index: Variant in group:
			members.append(players[index as int])
		var key: String = _key(members)
		var here: int = 0
		for entry: Dictionary in _live:
			if String(entry.key) == key and (entry.nb as NightBehavior).remnant:
				here += 1
		if here >= int(remnants.cap_per_group) or _rng.randf() > float(remnants.chance):
			continue
		var spot: Vector2 = _shade_spot(members)
		if spot == Vector2.INF:
			continue
		var strength: float = group_strength(members)
		_spawn("shadow_spider", spot, strength * float(remnants.health), NightRules.damage_scale(strength) * float(remnants.damage), key, 0.0, false, true)


func _shade_spot(members: Array[Player]) -> Vector2:
	var remnants: Dictionary = NightRules.config().remnants as Dictionary
	var ring: Array = remnants.ring_tiles as Array
	var trees: Array[Node] = get_tree().get_nodes_in_group("bird_perches")
	trees.shuffle()
	for tree: Node in trees:
		var base: Vector2 = (tree as Node2D).global_position + Vector2(_rng.randf_range(-26.0, 26.0), 18.0)
		var nearest: float = INF
		for member: Player in members:
			nearest = minf(nearest, member.global_position.distance_to(base))
		if nearest >= float(ring[0]) * TownRules.TILE and nearest <= float(ring[1]) * TownRules.TILE and _clear_to_spawn_anywhere(base):
			return base
	return Vector2.INF


func _clear_to_spawn_anywhere(pos: Vector2) -> bool:
	var town: TownManager = _world.town()
	return not town.spawn_blocked(pos) and bool(_world.navigation_floor(pos)) and String(_world.town_probe(Rect2(pos - Vector2(10, 10), Vector2(20, 20)))) == ""


## The nearest tree whose crown shades a creature of the day (a point at its foot), or infinity.
func _nearest_tree(pos: Vector2) -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_distance: float = float((NightRules.config().remnants as Dictionary).tree_search_px)
	for tree: Node in get_tree().get_nodes_in_group("bird_perches"):
		var distance: float = (tree as Node2D).global_position.distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = (tree as Node2D).global_position + Vector2(0.0, 16.0)
	return best


func _in_shade(pos: Vector2) -> bool:
	var radius: float = float((NightRules.config().remnants as Dictionary).shade_px)
	for tree: Node in get_tree().get_nodes_in_group("bird_perches"):
		if (tree as Node2D).global_position.distance_to(pos) <= radius:
			return true
	return false


# ---------------------------------------------------------------------------------- morning

## At the first light every creature of the night turns for the dark (and burns, see `_burn`).
func _dawn(window: bool) -> void:
	var dawn: Dictionary = NightRules.config().dawn as Dictionary
	var morning: bool = not window and TimeManager.night_amount() < float(dawn.start_night_amount)
	if not morning:
		_dawn_marked = false if window else _dawn_marked
		return
	if _dawn_marked:
		return
	_dawn_marked = true
	_end_raid(false)
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		if behavior.remnant:
			continue
		behavior.retreat = true
		behavior.excited = false
		behavior.hunter = false
		behavior.queue.clear()
		behavior.goal = Vector2.INF


## Once a second: leftovers of the day burn in the sun outside the shade, creatures of the night burn from the first light on.
func _burn() -> void:
	_burn_clock += TICK
	if _burn_clock < 1.0:
		return
	_burn_clock = 0.0
	var sun: float = TimeManager.sun_amount()
	var wound: Dictionary = NightRules.config().dawn as Dictionary
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		var node: Node2D = entry.node as Node2D
		var fraction: float = 0.0
		if behavior.remnant:
			if sun > 0.05 and not _in_shade(node.global_position):
				fraction = float((NightRules.config().remnants as Dictionary).sun_wound) * sun
		elif behavior.retreat:
			fraction = float(wound.wound) + float(wound.wound_sun) * sun
		if fraction <= 0.0:
			continue
		var health: HealthComponent = node.get_node("HealthComponent") as HealthComponent
		node.set_meta("burned", true)
		health.take_damage(maxf(1.0, health.max_health * fraction), node.global_position, 0.0, 0)


# ---------------------------------------------------------------------------------- patrol goals

func _assign_goals(players: Array[Player]) -> void:
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		var node: Node2D = entry.node as Node2D
		if behavior.excited:
			continue
		if behavior.hunter:
			var target: Player = _nearest_player(node.global_position, players)
			behavior.goal = target.global_position if target != null else Vector2.INF
			continue
		if not behavior.goal.is_finite():
			behavior.goal = _pick_goal(node.global_position, behavior, players)


func _nearest_player(pos: Vector2, players: Array[Player]) -> Player:
	var best: Player = null
	var best_distance: float = INF
	for player: Player in players:
		var distance: float = player.global_position.distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _pick_goal(pos: Vector2, behavior: NightBehavior, players: Array[Player]) -> Vector2:
	if behavior.remnant:
		return _nearest_tree(pos)
	var cfg: Dictionary = NightRules.config().behavior as Dictionary
	var town: TownManager = _world.town()
	if behavior.retreat:
		var from: Player = _nearest_player(pos, players) ## the morning: away from the people, into the dark
		var away: Vector2 = (pos - from.global_position).normalized() if from != null else Vector2.from_angle(_rng.randf() * TAU)
		return pos + away * 500.0
	var roll: float = _rng.randf()
	if roll < float(cfg.trace_chance):
		var target: Player = _nearest_player(pos, players)
		if target != null and target.global_position.distance_to(pos) < 1400.0:
			var spot: Vector2 = target.global_position
			if town.light_depth(spot) > -40.0: ## the player stands in the light: they wait at its edge and watch
				spot = town.dark_edge(pos, spot, float(cfg.dark_margin))
			return spot + Vector2(_rng.randf_range(-70.0, 70.0), _rng.randf_range(-70.0, 70.0))
	elif roll < float(cfg.trace_chance) + float(cfg.home_chance) and behavior.home.is_finite():
		return behavior.home ## back to where it was born
	var span: Array = cfg.goal_tiles as Array
	for attempt: int in 8:
		var point: Vector2 = pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(float(span[0]), float(span[1])) * TownRules.TILE
		if bool(_world.navigation_floor(point)) and town.light_depth(point) < -float(cfg.dark_margin):
			return point
	return Vector2.INF


# ---------------------------------------------------------------------------------- lure and raids

## Life in the base lures them (sprinting, fighting, building, many people). Past the threshold a group gathers at the edge of the light and then rushes it.
func _lure_tick(players: Array[Player], progress: float) -> void:
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	var town: TownManager = _world.town()
	_raid_cooldown = maxf(0.0, _raid_cooldown - TICK)
	match String(_raid.state):
		"idle":
			if progress < 0.0:
				lure = maxf(0.0, lure - float(cfg.decay) * TICK)
				return
			var rate: float = 0.0
			var in_base: Array[Player] = []
			for player: Player in players:
				if town.light_depth(player.global_position) > -float(cfg.zone_px):
					in_base.append(player)
					rate += float(cfg.sprint) if player.sprinting else 0.0
					rate += float(cfg.swing) if player.attack.is_swinging() else 0.0
			if in_base.size() > 1:
				rate += float(cfg.extra_player) * float(in_base.size() - 1)
			if not in_base.is_empty() and town.is_building():
				rate += float(cfg.building)
			lure = clampf(lure + (rate - float(cfg.decay)) * TICK, 0.0, float(cfg.threshold) * 1.5)
			if lure >= float(cfg.threshold) and _raid_cooldown <= 0.0 and progress <= 0.95 and not in_base.is_empty():
				_begin_warning(in_base[0], players)
		"warning":
			_raid.time = float(_raid.time) - TICK
			if not _raid_target_ok():
				_end_raid(true)
			elif float(_raid.time) <= 0.0:
				_begin_attack()
		"attack":
			_raid.time = float(_raid.time) - TICK
			_raid_attack_tick(players)


func _raid_player() -> Player:
	var target: Variant = _raid.target
	if target == null or not is_instance_valid(target):
		return null
	return target as Player


func _raid_target_ok() -> bool:
	var target: Player = _raid_player()
	return target != null and target.health.current > 0.0 and Interiors.slot_at(target.global_position) < 0


func _begin_warning(target: Player, players: Array[Player]) -> void:
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	var town: TownManager = _world.town()
	var levels: Array[int] = []
	for player: Player in players:
		levels.append(player.progress.level)
	var wanted: int = clampi(int(cfg.members_min) + NightRules.group_level(levels) / 4, int(cfg.members_min), int(cfg.members_max))
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		var node: Node2D = entry.node as Node2D
		if behavior.remnant or behavior.retreat or behavior.hunter:
			continue
		if node.global_position.distance_to(target.global_position) <= 70.0 * TownRules.TILE:
			candidates.append(entry)
	if candidates.size() < int(cfg.members_min):
		return
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.node as Node2D).global_position.distance_to(target.global_position) < (b.node as Node2D).global_position.distance_to(target.global_position))
	var members: Array = []
	for entry: Dictionary in candidates.slice(0, wanted):
		members.append(entry)
		var behavior: NightBehavior = entry.nb as NightBehavior
		behavior.queue.clear()
		behavior.goal = town.dark_edge((entry.node as Node2D).global_position, target.global_position, float((NightRules.config().behavior as Dictionary).dark_margin) + 10.0)
	_raid = {"state": "warning", "time": float(cfg.warning_seconds), "target": target, "members": members}
	town.banner("ETWAS REGT SICH IM DUNKELN", "")
	var gather: Vector2 = Vector2.ZERO
	for entry: Dictionary in members:
		gather += (entry.node as Node2D).global_position
	if not members.is_empty():
		town.set_alert(true, (gather / float(members.size()) - town.center).angle()) ## Valdric goes to the edge where they gather
		town.emit_event("alert", {})


func _begin_attack() -> void:
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	var target: Player = _raid_player()
	for entry: Dictionary in _raid.members as Array:
		if target == null or not is_instance_valid(entry.node):
			continue
		var node: Node2D = entry.node as Node2D
		var behavior: NightBehavior = entry.nb as NightBehavior
		behavior.excited = true
		behavior.queue.clear()
		behavior.goal = _find_gap(target.global_position, node.global_position)
		behavior.queue.append(target.global_position)
	_raid.state = "attack"
	_raid.time = float(cfg.raid_seconds)


## The gap in the net: a dark point 140-360 px from the target whose way to the target crosses the least light.
func _find_gap(target: Vector2, from: Vector2) -> Vector2:
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	var town: TownManager = _world.town()
	var best: Vector2 = target
	var best_score: float = INF
	for attempt: int in int(cfg.gap_tries):
		var point: Vector2 = target + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(140.0, 360.0)
		if town.light_depth(point) > -20.0 or not bool(_world.navigation_floor(point)):
			continue
		var score: float = town.lit_fraction(point, target) + 0.0015 * point.distance_to(from)
		if score < best_score:
			best_score = score
			best = point
	return best


func _raid_attack_tick(players: Array[Player]) -> void:
	var target: Player = _raid_player()
	if not _raid_target_ok():
		target = players[0] if not players.is_empty() else null
		_raid.target = target
	var alive: int = 0
	for entry: Dictionary in _raid.members as Array:
		if not is_instance_valid(entry.node) or ((entry.node as Node2D).get_node("HealthComponent") as HealthComponent).current <= 0.0:
			continue
		alive += 1
		var behavior: NightBehavior = entry.nb as NightBehavior
		if target == null:
			continue
		if behavior.queue.is_empty():
			behavior.goal = target.global_position ## the last stretch follows the player
		else:
			behavior.queue[0] = target.global_position
	if float(_raid.time) <= 0.0 or alive == 0 or target == null:
		_end_raid(true)


## Noise from the water (a long fight at the river bank, docs/fishing.md) draws them a little: the lure rises (host).
func stir(amount: float) -> void:
	if amount <= 0.0:
		return
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	lure = clampf(lure + amount, 0.0, float(cfg.threshold) * 1.5)


## `spent`: the raid really happened (the lure falls back and the base gets its calm).
func _end_raid(spent: bool) -> void:
	for entry: Variant in _raid.get("members", []) as Array:
		var behavior: NightBehavior = (entry as Dictionary).nb as NightBehavior
		behavior.excited = false
		behavior.queue.clear()
		behavior.goal = Vector2.INF
	_raid = {"state": "idle", "time": 0.0, "target": null, "members": []}
	var home: TownManager = _world.town() as TownManager
	if home != null:
		home.set_alert(false, 0.0)
	if spent:
		var cfg: Dictionary = NightRules.config().lure as Dictionary
		lure = float(cfg.reset_to)
		_raid_cooldown = float(cfg.cooldown)


## Dev / tests: lets a raid start at once with the current players (needs night creatures nearby).
func debug_force_raid() -> void:
	lure = float((NightRules.config().lure as Dictionary).threshold) + 5.0 ## a tick still lets it decay
	_raid_cooldown = 0.0
