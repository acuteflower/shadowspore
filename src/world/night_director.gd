class_name NightDirector
extends Node
## The night (docs/nacht_monster_konzept.md): host only. By day a few weakened leftovers lurk in the shade; once the dark has fallen, creatures climb out of the
## the dark ground and the edge of the world (the spider's own birth animation, `ShadowBirth`), patrol the dark, keep away from the town's light and, when the life in the base lures them, rush it
## through its gaps. How many and how tough follows the strongest player's level, the day, the players and the town (`NightRules`, data/night.json).
## It spawns through `WorldLevel.spawn_species`, so the enemies replicate like every other; the AI hooks live in `NightBehavior`.
##
## The night is told, not rolled (docs/nacht_monster_konzept.md "Das lebendige System"): the moon sets the weight (new moon = more and bolder, full moon = fewer), the
## ladder of stages (`NightRules.stage_for`) opens kinds, packs, scouts, raids, memory and the last rush as the nights go by, the night itself has beats (scouts, build,
## lull, call, peak, last rush), creatures come in packs of their own courage, hear what the players do (evidence), probe the dim edge of the light, remember where the
## base was weak (saved) and the people of the town run for cover while the dark is near.

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
var _stage_seen: String = "" ## the last stage whose omen was shown (saved, so a reload does not announce it again)
var _ledger: Dictionary = {} ## group key -> {spent: float, died: bool}
var _live: Array[Dictionary] = [] ## {node, nb, key, cost, id, breached}
var _died: Dictionary = {} ## player name -> the night (id) it fell in
var _hooked: Dictionary = {} ## player instance id -> true
var _hunters_left: int = 0
var _raid: Dictionary = {"state": "idle", "time": 0.0, "target": null, "members": []}
var _raid_cooldown: float = 0.0
var _force_raid: bool = false ## dev / tests: a raid may start whatever the stage and the beat say
var _dawn_marked: bool = false
var _pack_id: int = 0
var _scouted: bool = false ## a scout has watched the base tonight: the raids of the night are open
var _scout_wait: float = 0.0
var _caller_wait: float = 0.0
var _call_left: float = 0.0
var _rush_done: bool = false
var _elite_done: bool = false
var _breather: Dictionary = {} ## group key -> seconds left in which nothing new is born (the players are hurt or swamped)
var _evidence: Array[Dictionary] = [] ## {pos, ttl, w}: what the players did that they could hear
var _noise: Dictionary = {} ## player name -> accumulated noise
var _memory: Dictionary = {} ## sector (int) -> {"b": breaches, "d": defended}: where the base was weak or held (saved)
var _radii: PackedFloat32Array = PackedFloat32Array() ## per sector: how far the light reaches from the middle of the town
var _radii_age: float = 1000.0
var _fear_calm: float = 0.0


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
## A story scene that spawns its own creatures (Gustav's escort) holds the director back: it stays silent while this is true.
var story_hold: bool = false


func active() -> bool:
	if story_hold or not multiplayer.is_server() or not bool(_world.opening_over):
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


## The ladder stage of tonight (see `NightRules.stage_for`).
func stage() -> Dictionary:
	return NightRules.stage_for(TimeManager.day)


## The budget one group of players has tonight (see `NightRules.budget`; the moon, the stage, the special night and a fall earlier tonight change it).
func group_budget(members: Array[Player], died: bool = false) -> float:
	var levels: Array[int] = []
	for member: Player in members:
		levels.append(member.progress.level)
	var value: float = NightRules.budget(NightRules.group_level(levels), TimeManager.day, members.size()) * float(NightRules.special_spec(special).budget)
	value *= NightRules.moon_budget(TimeManager.moon_phase()) * float(stage().budget)
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


# ---------------------------------------------------------------------------------- save

## What the night remembers between sessions: where the base held and where it gave way, and which stage has been announced.
func export_state() -> Dictionary:
	var memory: Dictionary = {}
	for sector: Variant in _memory:
		memory[str(sector)] = (_memory[sector] as Dictionary).duplicate()
	return {"memory": memory, "stage_seen": _stage_seen}


func import_state(data: Dictionary) -> void:
	_memory.clear()
	var memory: Dictionary = data.get("memory", {}) as Dictionary
	for sector: Variant in memory:
		var rec: Dictionary = memory[sector] as Dictionary
		_memory[int(String(sector))] = {"b": float(rec.get("b", 0.0)), "d": float(rec.get("d", 0.0))}
	_stage_seen = String(data.get("stage_seen", ""))


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
	for key: Variant in _breather.keys():
		_breather[key] = maxf(0.0, float(_breather[key]) - TICK)
	_scout_wait = maxf(0.0, _scout_wait - TICK)
	_radii_age += TICK
	if window:
		_night(players, progress)
		_evidence_tick(players)
		_scout_tick()
		_courage_tick()
	else:
		_day(players)
	_lure_tick(players, progress)
	_fear_tick()
	_dawn(window)
	_assign_goals(players)
	_burn()


func _begin_night() -> void:
	_night_id = TimeManager.day
	_ledger.clear()
	lure = 0.0
	_end_raid(false)
	_raid_cooldown = 0.0
	_force_raid = false
	_dawn_marked = false
	_scouted = false
	_scout_wait = 0.0
	_caller_wait = float((NightRules.config().caller as Dictionary).cooldown) * 0.3
	_rush_done = false
	_elite_done = false
	_breather.clear()
	_evidence.clear()
	_noise.clear()
	_decay_memory()
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
	var town: TownManager = _world.town() as TownManager
	if town != null and multiplayer.is_server() and town.fear_on:
		town.set_fear(false)


## The omens at dusk (the first sign that the dark will not be an ordinary one): a special night, then a new rung of the ladder, then a new moon. One banner a dusk.
func _dusk_notice() -> void:
	var cfg: Dictionary = NightRules.config().omens as Dictionary
	var t: float = TimeManager.time_of_day
	if _announced == TimeManager.day or t < float(cfg.from) or t >= float(NightRules.config().window.start):
		return
	_announced = TimeManager.day
	var town: TownManager = _world.town() as TownManager
	var kind: String = NightRules.special_for(int(_world._map.world_seed), TimeManager.day)
	var current: String = String(stage().id)
	var changed: bool = _stage_seen != "" and _stage_seen != current
	_stage_seen = current
	if kind != "none":
		town.banner(String(NightRules.special_spec(kind).notice), "")
	elif changed and (cfg.stage_notice as Dictionary).has(current):
		town.banner(String((cfg.stage_notice as Dictionary)[current]), "")
	elif NightRules.moon_dark(TimeManager.moon_phase()) >= float(cfg.new_moon_dark):
		town.banner(String(cfg.new_moon_notice), "")
	town.emit_event("omen", {"kind": kind, "stage": current})


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
			if not _try_spawn(key, members, entry, progress) and _elite_due(progress):
				_spawn_elite(key, members, entry)


## Is a group hurt or swamped? Then the dark holds back for a moment (the night breathes with the fight).
func _stressed(key: String, members: Array[Player]) -> bool:
	var cfg: Dictionary = NightRules.config().stress as Dictionary
	for member: Player in members:
		if member.health.max_health > 0.0 and member.health.current / member.health.max_health < float(cfg.low_health):
			_breather[key] = float(cfg.breather_seconds)
			return true
	return _alive_in(key) >= int(cfg.alive_soft) + int(cfg.alive_soft_per_player) * (members.size() - 1)


func _try_spawn(key: String, members: Array[Player], entry: Dictionary, progress: float) -> bool:
	var groups: Dictionary = NightRules.config().groups as Dictionary
	if live_count(false) >= int(groups.global_cap) or _alive_in(key) >= int(groups.alive_cap):
		return false
	if NightRules.beat(progress) == "lull" or float(_breather.get(key, 0.0)) > 0.0:
		return false ## the quiet before the call
	var budget: float = group_budget(members, bool(entry.died))
	var left: float = budget * NightRules.released(progress) - float(entry.spent)
	if left < 0.5 or _stressed(key, members):
		return false
	var levels: Array[int] = []
	for member: Player in members:
		levels.append(member.progress.level)
	var level: int = NightRules.group_level(levels)
	var current: Dictionary = stage()
	var spot: Dictionary = spawn_spot(members)
	if spot.is_empty():
		return false
	var spec: Dictionary = NightRules.special_spec(special)
	var strength: float = group_strength(members)
	var damage: float = NightRules.damage_scale(strength) * float(spec.damage)
	var packs: Dictionary = NightRules.config().packs as Dictionary
	if bool(current.scouts) and not _scouted and not _has_scout() and _scout_wait <= 0.0: ## the first thing of a night: one looks at the base
		var scout: Node2D = _spawn("shadow_spider", spot.pos as Vector2, strength * float(spec.health), damage, key, 1.0, false)
		if scout == null:
			return false
		(scout.get("night") as NightBehavior).scout = true
		_scout_wait = float(packs.scout_retry)
		entry.spent = float(entry.spent) + 1.0 * float(packs.scout_cost_share)
		return true
	var hunter: bool = _hunters_left > 0 and float(entry.spent) >= 2.0
	var kinds: Array[Dictionary] = NightRules.available(budget, level, TimeManager.day, current)
	var id: String = "shadow_spider" if hunter else NightRules.pick_species(kinds, left, 1.0, _rng)
	if id == "":
		return false
	var size: int = 1 if hunter else NightRules.pack_size(current, left, _rng)
	var courage: Dictionary = NightRules.config().courage as Dictionary
	var bonus: float = float(courage.pack_bonus) * float(size - 1)
	_pack_id += 1
	var spawned: int = 0
	var paid: float = 0.0
	for i: int in size:
		if _alive_in(key) >= int(groups.alive_cap):
			break
		var pick: String = id if i == 0 else NightRules.pick_species(kinds, left - paid, 1.0, _rng)
		if pick == "":
			break
		var pos: Vector2 = spot.pos as Vector2 if i == 0 else _pack_spot(spot.pos as Vector2)
		if not pos.is_finite():
			continue
		var health: float = strength * float(spec.health) * (float(spec.get("hunter_health", 1.0)) if hunter else 1.0)
		var enemy: Node2D = _spawn(pick, pos, health, damage, key, NightRules.cost_of(pick), hunter)
		if enemy == null:
			continue
		var behavior: NightBehavior = enemy.get("night") as NightBehavior
		behavior.courage += bonus
		behavior.pack = _pack_id if size > 1 else 0
		paid += NightRules.cost_of(pick)
		spawned += 1
	if spawned == 0:
		return false
	if hunter:
		_hunters_left -= 1
	entry.spent = float(entry.spent) + paid
	return true


## A place next to the pack's first creature (a pack is born together, a few steps apart).
func _pack_spot(origin: Vector2) -> Vector2:
	var spread: Array = (NightRules.config().spawn as Dictionary).pack_spread as Array
	for attempt: int in 8:
		var point: Vector2 = origin + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(float(spread[0]), float(spread[1]))
		if _clear_to_spawn_anywhere(point):
			return point.round()
	return Vector2.INF


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
	if not remnant:
		var span: Array = (NightRules.config().courage as Dictionary).base as Array
		behavior.courage = _rng.randf_range(float(span[0]), float(span[1])) ## every creature has a temper of its own
	if remnant:
		behavior.speed_cap = behavior.top_speed * float((NightRules.config().remnants as Dictionary).speed)
	enemy.set("night", behavior)
	var entry: Dictionary = {"node": enemy, "nb": behavior, "key": key, "cost": cost, "id": id, "breached": false}
	_live.append(entry)
	(enemy.get_node("HealthComponent") as HealthComponent).died.connect(_on_killed.bind(entry))
	return enemy


## A kill gives a share of its cost back to the group's budget, so a fought-off wave is followed by the next one (not by an empty night).
## A creature that fell at the edge of the light also tells the night that this side of the base held.
func _on_killed(entry: Dictionary) -> void:
	var behavior: NightBehavior = entry.nb as NightBehavior
	var node: Node = entry.node as Node
	if behavior.remnant or not is_instance_valid(node):
		return
	var town: TownManager = _world.town() as TownManager
	if town != null and town.founded and bool(entry.get("breached", false)) == false:
		var at: Vector2 = (node as Node2D).global_position
		if town.light_depth(at) > -float((NightRules.config().memory as Dictionary).defend_radius):
			_remember(_sector_at(at), "d", 1.0)
	if (node.get_node("HealthComponent") as HealthComponent).last_attacker == 0:
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


func _has_scout() -> bool:
	for entry: Dictionary in _live:
		if (entry.nb as NightBehavior).scout:
			return true
	return false


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


# ---------------------------------------------------------------------------------- the elite of a new moon

## A new moon at the top of the ladder brings one big one, late in the night.
func _elite_due(progress: float) -> bool:
	var cfg: Dictionary = NightRules.config().elite as Dictionary
	if _elite_done or not bool(stage().elite) or progress < float(cfg.progress) or progress > float(window_cfg().spawn_end_progress):
		return false
	return NightRules.moon_dark(TimeManager.moon_phase()) >= float((NightRules.config().omens as Dictionary).new_moon_dark)


func window_cfg() -> Dictionary:
	return NightRules.config().window as Dictionary


func _spawn_elite(key: String, members: Array[Player], entry: Dictionary) -> void:
	var cfg: Dictionary = NightRules.config().elite as Dictionary
	var spot: Dictionary = spawn_spot(members)
	if spot.is_empty():
		return
	var spec: Dictionary = NightRules.special_spec(special)
	var strength: float = group_strength(members)
	var enemy: Node2D = _spawn(String(cfg.species), spot.pos as Vector2, strength * float(cfg.health) * float(spec.health), NightRules.damage_scale(strength) * float(cfg.damage) * float(spec.damage), key, float(cfg.cost), false)
	if enemy == null:
		return
	(enemy.get("night") as NightBehavior).courage = 0.9 ## it fears nothing
	entry.spent = float(entry.spent) + float(cfg.cost)
	_elite_done = true
	(_world.town() as TownManager).banner(String(cfg.notice), "")


# ---------------------------------------------------------------------------------- where they come from

## A random point near the group to be born at: open dark ground, or a bit of coast. {} when none fits. Public for the tests.
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
		behavior.scout = false
		behavior.calling = false
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


# ---------------------------------------------------------------------------------- the base seen from the dark: sectors and memory

func _sectors() -> int:
	return int((NightRules.config().memory as Dictionary).sectors)


func _sector_at(pos: Vector2) -> int:
	var town: TownManager = _world.town() as TownManager
	return NightRules.sector_of((pos - town.center).angle(), _sectors())


## How far the light reaches from the middle of the town in every sector (the first dark point on the ray); refreshed now and then because lamps are built.
func _ensure_radii() -> void:
	var count: int = _sectors()
	if _radii.size() == count and _radii_age < float((NightRules.config().memory as Dictionary).refresh):
		return
	_radii_age = 0.0
	var town: TownManager = _world.town() as TownManager
	_radii.resize(count)
	for sector: int in count:
		var dir: Vector2 = Vector2.from_angle(NightRules.sector_angle(sector, count))
		var radius: float = 0.0
		for step: int in 64:
			radius = float(step) * 16.0
			if town.light_depth(town.center + dir * radius) < 0.0:
				break
		_radii[sector] = radius


## 0 (as far as the light goes anywhere) .. 1 (hardly any light): how thin the base is on this side.
func _weak(sector: int) -> float:
	_ensure_radii()
	var widest: float = 1.0
	for radius: float in _radii:
		widest = maxf(widest, radius)
	return clampf((widest - _radii[sector]) / widest, 0.0, 1.0)


## How attractive a side of the base is to the dark: thin light, an earlier breach, minus the defenders' luck (the last two only once the ladder has opened memory).
func sector_weight(sector: int) -> float:
	var cfg: Dictionary = NightRules.config().memory as Dictionary
	var weight: float = 1.0 + float(cfg.weak_weight) * _weak(sector)
	if bool(stage().memory):
		var rec: Dictionary = _memory.get(sector, {}) as Dictionary
		weight += float(cfg.breach_weight) * float(rec.get("b", 0.0)) - float(cfg.defended_weight) * float(rec.get("d", 0.0))
	return maxf(0.1, weight)


func _pick_sector() -> int:
	var total: float = 0.0
	var weights: Array[float] = []
	for sector: int in _sectors():
		var weight: float = sector_weight(sector)
		weights.append(weight)
		total += weight
	var roll: float = _rng.randf() * total
	for sector: int in weights.size():
		roll -= weights[sector]
		if roll <= 0.0:
			return sector
	return weights.size() - 1


func _remember(sector: int, field: String, amount: float) -> void:
	var rec: Dictionary = _memory.get(sector, {"b": 0.0, "d": 0.0}) as Dictionary
	rec[field] = minf(float(rec.get(field, 0.0)) + amount, 6.0)
	_memory[sector] = rec


## A new night forgets part of the old one.
func _decay_memory() -> void:
	var keep: float = float((NightRules.config().memory as Dictionary).decay)
	for sector: Variant in _memory.keys():
		var rec: Dictionary = _memory[sector] as Dictionary
		rec.b = float(rec.get("b", 0.0)) * keep
		rec.d = float(rec.get("d", 0.0)) * keep
		if float(rec.b) < 0.05 and float(rec.d) < 0.05:
			_memory.erase(sector)


## A dark point just outside the light in a sector (the pacing round the base).
func _ring_goal(sector: int) -> Vector2:
	var town: TownManager = _world.town() as TownManager
	var margin: float = float((NightRules.config().behavior as Dictionary).dark_margin)
	_ensure_radii()
	var dir: Vector2 = Vector2.from_angle(NightRules.sector_angle(sector, _sectors()) + _rng.randf_range(-0.08, 0.08))
	var point: Vector2 = town.center + dir * (_radii[sector] + margin + 24.0 + _rng.randf() * 30.0)
	if bool(_world.navigation_floor(point)) and town.light_depth(point) < -margin:
		return point
	return Vector2.INF


## A point on the way from `from` to `to` that lies in the dim outer band of the light (a creature that dares probes it), or infinity.
func _dim_point(from: Vector2, to: Vector2) -> Vector2:
	var town: TownManager = _world.town() as TownManager
	var limit: float = float((NightRules.config().courage as Dictionary).dim_px) * 0.8
	for i: int in 33:
		var point: Vector2 = from.lerp(to, float(i) / 32.0)
		var depth: float = town.light_depth(point)
		if depth > limit:
			return Vector2.INF
		if depth > 0.0:
			return point
	return Vector2.INF


## Every tick: the night's share of each creature's courage (moon, thin light on its side, many lamps).
func _courage_tick() -> void:
	var town: TownManager = _world.town() as TownManager
	if town == null or not town.founded:
		return
	var cfg: Dictionary = NightRules.config().courage as Dictionary
	var moon: float = NightRules.moon_courage(TimeManager.moon_phase())
	var lamps: float = minf(float(cfg.lamp_penalty_cap), float(cfg.lamp_penalty) * float(town.lit_circles().size()))
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		if behavior.remnant:
			continue
		var gap: float = float(cfg.dark_gap_bonus) if _weak(_sector_at((entry.node as Node2D).global_position)) > 0.5 else 0.0
		behavior.courage_extra = moon - lamps + gap


# ---------------------------------------------------------------------------------- evidence: what they hear

## The players make noise (sprinting, swinging, building); now and then it is heard in the dark and leaves a trace for a while.
func _evidence_tick(players: Array[Player]) -> void:
	var cfg: Dictionary = NightRules.config().evidence as Dictionary
	var kept: Array[Dictionary] = []
	for ev: Dictionary in _evidence:
		ev.ttl = float(ev.ttl) - TICK
		if float(ev.ttl) > 0.0:
			kept.append(ev)
	_evidence = kept
	var town: TownManager = _world.town() as TownManager
	for player: Player in players:
		var loud: float = 0.0
		if player.sprinting:
			loud += float(cfg.sprint)
		if player.attack.is_swinging():
			loud += float(cfg.swing) * player.attack.noise_scale()
		if town != null and town.is_building() and town.light_depth(player.global_position) > -float((NightRules.config().lure as Dictionary).zone_px):
			loud += float(cfg.building)
		var id: String = str(player.name)
		var heard: float = float(_noise.get(id, 0.0)) + loud * TICK
		if heard < float(cfg.min_loud):
			_noise[id] = heard
			continue
		_noise[id] = 0.0
		if _rng.randf() <= float(cfg.chance):
			_add_evidence(player.global_position)


func _add_evidence(pos: Vector2) -> void:
	var cfg: Dictionary = NightRules.config().evidence as Dictionary
	for ev: Dictionary in _evidence:
		if (ev.pos as Vector2).distance_to(pos) <= float(cfg.cell_px):
			ev.pos = (ev.pos as Vector2).lerp(pos, 0.5)
			ev.ttl = float(cfg.ttl)
			ev.w = float(ev.w) + 1.0
			return
	_evidence.append({"pos": pos, "ttl": float(cfg.ttl), "w": 1.0})
	while _evidence.size() > int(cfg.cap):
		_evidence.remove_at(0)


func evidence_count() -> int:
	return _evidence.size()


## A goal drawn by a trace of noise the creature can hear: a dark point at the edge, or (for a brave one) a point in the dim band to probe. Infinity when nothing was heard.
func _evidence_goal(pos: Vector2, behavior: NightBehavior) -> Vector2:
	var cfg: Dictionary = NightRules.config().evidence as Dictionary
	if _evidence.is_empty() or _rng.randf() > float(cfg.chance):
		return Vector2.INF
	var town: TownManager = _world.town() as TownManager
	var margin: float = float((NightRules.config().behavior as Dictionary).dark_margin)
	var hear: float = float(cfg.hear_tiles) * TownRules.TILE
	var best: Dictionary = {}
	var best_score: float = INF
	for ev: Dictionary in _evidence:
		var distance: float = (ev.pos as Vector2).distance_to(pos)
		if distance <= hear and distance / float(ev.w) < best_score:
			best_score = distance / float(ev.w)
			best = ev
	if best.is_empty():
		return Vector2.INF
	var spot: Vector2 = best.pos as Vector2
	if town.light_depth(spot) > -margin:
		if behavior.brave():
			var probe: Vector2 = _dim_point(pos, spot)
			if probe.is_finite():
				behavior.probing = true
				return probe
		spot = town.dark_edge(pos, spot, margin)
	return spot + Vector2(_rng.randf_range(-40.0, 40.0), _rng.randf_range(-40.0, 40.0))


# ---------------------------------------------------------------------------------- scouts

## A scout that has watched the base from the edge of the light for a few seconds opens the raids of the night.
func _scout_tick() -> void:
	var town: TownManager = _world.town() as TownManager
	var cfg: Dictionary = NightRules.config().packs as Dictionary
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		if not behavior.scout:
			continue
		if town.light_depth((entry.node as Node2D).global_position) > float(cfg.scout_report_depth):
			behavior.observed += TICK
		if behavior.observed >= float(cfg.scout_report_seconds):
			behavior.scout = false
			_scouted = true
			town.emit_event("scout_seen", {})


func _scout_post(pos: Vector2) -> Vector2:
	var town: TownManager = _world.town() as TownManager
	var post: Vector2 = town.dark_edge(pos, town.center, -float((NightRules.config().packs as Dictionary).scout_report_depth) - 40.0)
	return post + Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-30.0, 30.0))


# ---------------------------------------------------------------------------------- fear

## The people run for cover while the dark is near (a raid, a creature in the dim band, several at the edge) and come out when it has been quiet for a while.
func _fear_tick() -> void:
	var town: TownManager = _world.town() as TownManager
	if town == null or not town.founded:
		return
	var cfg: Dictionary = NightRules.config().fear as Dictionary
	var danger: bool = String(_raid.state) != "idle"
	if not danger and _in_window:
		var near: int = 0
		for entry: Dictionary in _live:
			var behavior: NightBehavior = entry.nb as NightBehavior
			if behavior.remnant or behavior.retreat:
				continue
			var depth: float = town.light_depth((entry.node as Node2D).global_position)
			if depth > 0.0:
				danger = true
				break
			if depth > -float(cfg.near_px):
				near += 1
		danger = danger or near >= 3
	if danger:
		_fear_calm = float(cfg.calm_seconds)
		if not town.fear_on:
			town.set_fear(true)
	else:
		_fear_calm -= TICK
		if _fear_calm <= 0.0 and town.fear_on:
			town.set_fear(false)


# ---------------------------------------------------------------------------------- patrol goals

func _assign_goals(players: Array[Player]) -> void:
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		var node: Node2D = entry.node as Node2D
		if behavior.excited or behavior.calling:
			continue
		if behavior.hunter:
			var target: Player = _nearest_player(node.global_position, players)
			behavior.goal = target.global_position if target != null else Vector2.INF
			continue
		if behavior.scout and not behavior.retreat:
			if not behavior.goal.is_finite():
				behavior.goal = _scout_post(node.global_position)
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
	var heard: Vector2 = _evidence_goal(pos, behavior) ## something was heard: go and look
	if heard.is_finite():
		return heard
	if town.founded and _rng.randf() < float((NightRules.config().ring_walk as Dictionary).chance):
		var round_goal: Vector2 = _ring_goal(_pick_sector()) ## pace round the base, longest on its thin side
		if round_goal.is_finite():
			return round_goal
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

## Is the night open for a raid? The ladder must allow them, a scout must have looked at the base and the beat must not be a lull.
func _raids_open(progress: float) -> bool:
	if _force_raid:
		return true
	var current: Dictionary = stage()
	if not bool(current.raids) or (bool(current.scouts) and not _scouted):
		return false
	return NightRules.beat(progress) != "lull"


## Life in the base lures them (sprinting, fighting, building, many people). Past the threshold a group gathers at the edge of the light and then rushes it.
## Besides the lure the night has two raids of its own: the call of a listener in the middle of the night and the last rush before dawn.
func _lure_tick(players: Array[Player], progress: float) -> void:
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	var town: TownManager = _world.town()
	_raid_cooldown = maxf(0.0, _raid_cooldown - TICK)
	_caller_wait = maxf(0.0, _caller_wait - TICK)
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
					rate += float(cfg.swing) * player.attack.noise_scale() if player.attack.is_swinging() else 0.0
			if in_base.size() > 1:
				rate += float(cfg.extra_player) * float(in_base.size() - 1)
			if not in_base.is_empty() and town.is_building():
				rate += float(cfg.building)
			lure = clampf(lure + (rate - float(cfg.decay)) * TICK, 0.0, float(cfg.threshold) * 1.5)
			if _rush_ready(progress, players):
				var anchor: Player = in_base[0] if not in_base.is_empty() else _nearest_player(town.center, players)
				if anchor != null and _begin_warning(anchor, players, "rush"):
					_rush_done = true
				return
			if _raid_cooldown <= 0.0 and _raids_open(progress):
				if lure >= float(cfg.threshold) and progress <= 0.95 and not in_base.is_empty():
					if _begin_warning(in_base[0], players, "lure"):
						_force_raid = false
				elif _caller_ready(progress):
					_try_call(players)
		"warning":
			_raid.time = float(_raid.time) - TICK
			if String(_raid.source) == "call":
				_call_left -= TICK
				if _call_left <= 0.0:
					_set_calling(false)
				if not _caller_alive():
					_cancel_call() ## the voice that called them is gone
					return
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


## The last rush: shortly before the light returns the night throws what it has left at the base once more.
func _rush_ready(progress: float, players: Array[Player]) -> bool:
	var cfg: Dictionary = NightRules.config().last_rush as Dictionary
	return not _rush_done and bool(stage().last_rush) and not players.is_empty() and progress >= float(cfg.from_progress) and progress <= 0.95 and (_scouted or not bool(stage().scouts))


func _caller_ready(progress: float) -> bool:
	var cfg: Dictionary = NightRules.config().caller as Dictionary
	if _caller_wait > 0.0 or progress < float(cfg.from_progress) or progress >= float((NightRules.config().last_rush as Dictionary).from_progress):
		return false
	return _rng.randf() <= float(cfg.chance)


func _caller_alive() -> bool:
	var entry: Variant = _raid.get("caller", null)
	if entry == null:
		return false
	var node: Variant = (entry as Dictionary).get("node", null)
	if node == null or not is_instance_valid(node) or (node as Node).is_queued_for_deletion():
		return false
	return ((node as Node).get_node("HealthComponent") as HealthComponent).current > 0.0


## A listener stands still and calls the dark together; the raid follows after a while unless it is silenced first.
func _try_call(players: Array[Player]) -> void:
	var cfg: Dictionary = NightRules.config().caller as Dictionary
	var town: TownManager = _world.town()
	var reach: float = 70.0 * TownRules.TILE
	var options: Array[Dictionary] = []
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		var node: Node2D = entry.node as Node2D
		if String(entry.id) != "void_listener" or behavior.remnant or behavior.retreat or behavior.hunter or behavior.excited:
			continue
		var near: Player = _nearest_player(node.global_position, players)
		if near != null and near.global_position.distance_to(node.global_position) <= reach:
			options.append(entry)
	if options.is_empty():
		_caller_wait = 10.0
		return
	var caller: Dictionary = options[_rng.randi() % options.size()] as Dictionary
	var at: Vector2 = (caller.node as Node2D).global_position
	var target: Player = _nearest_player(at, players)
	if target == null or not _begin_warning(target, players, "call", caller):
		_caller_wait = 10.0
		return
	_caller_wait = float(cfg.cooldown)
	_call_left = float(cfg.call_seconds)
	_set_calling(true)
	_rpc_call.rpc(at)
	town.emit_event("call", {})


func _set_calling(on: bool) -> void:
	var entry: Variant = _raid.get("caller", null)
	if entry == null:
		return
	var behavior: NightBehavior = (entry as Dictionary).nb as NightBehavior
	behavior.calling = on
	behavior.caller = true
	if not on:
		behavior.goal = Vector2.INF


func _cancel_call() -> void:
	_end_raid(false)
	_raid_cooldown = 20.0
	(_world.town() as TownManager).emit_event("call_broken", {})


## The call, seen and heard on every peer: a ring running out over the ground and the listener's own voice, lowered.
@rpc("authority", "call_local", "reliable")
func _rpc_call(at: Vector2) -> void:
	var level: Node2D = _world as Node2D
	if level == null:
		return
	ShockRing.burst(level, level.to_local(at), 70.0, 0.8)
	var audio: Dictionary = DataRegistry.get_entry("enemies", "void_listener").get("audio", {}) as Dictionary
	var path: String = String(audio.get("scream", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = load(path) as AudioStream
	voice.volume_db = float(audio.get("volume_db", -8.0)) + 3.0
	voice.pitch_scale = 0.72
	voice.max_distance = 1500.0
	level.add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	voice.play()


## `source`: "lure" (the base's life), "call" (a listener, `caller` is its entry) or "rush" (the last rush). False when too few creatures are near to make a raid.
func _begin_warning(target: Player, players: Array[Player], source: String = "lure", caller: Dictionary = {}) -> bool:
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	var rush: Dictionary = NightRules.config().last_rush as Dictionary
	var call_cfg: Dictionary = NightRules.config().caller as Dictionary
	var town: TownManager = _world.town()
	var levels: Array[int] = []
	for player: Player in players:
		levels.append(player.progress.level)
	var members_min: int = int(cfg.members_min)
	var members_max: int = int(cfg.members_max)
	var warning: float = float(cfg.warning_seconds)
	var attack: float = float(cfg.raid_seconds)
	var anchor: Vector2 = target.global_position
	var reach: float = 70.0 * TownRules.TILE
	var wanted: int = clampi(members_min + int(float(NightRules.group_level(levels)) / 4.0), members_min, members_max)
	match source:
		"rush":
			members_min = int(rush.members_min)
			members_max = int(rush.members_max)
			warning = float(rush.warning_seconds)
			attack = float(rush.raid_seconds)
			wanted = members_max
		"call":
			members_min = int(call_cfg.members_min)
			warning = float(call_cfg.delay)
			anchor = (caller.node as Node2D).global_position
			reach = float(call_cfg.gather_tiles) * TownRules.TILE
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _live:
		var behavior: NightBehavior = entry.nb as NightBehavior
		var node: Node2D = entry.node as Node2D
		if behavior.remnant or behavior.retreat or behavior.hunter or behavior.calling or entry == caller:
			continue
		if node.global_position.distance_to(anchor) <= reach:
			candidates.append(entry)
	if candidates.size() < members_min:
		return false
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.node as Node2D).global_position.distance_to(anchor) < (b.node as Node2D).global_position.distance_to(anchor))
	var members: Array = []
	for entry: Dictionary in candidates.slice(0, wanted):
		members.append(entry)
		var behavior: NightBehavior = entry.nb as NightBehavior
		behavior.queue.clear()
		behavior.scout = false
		behavior.goal = town.dark_edge((entry.node as Node2D).global_position, target.global_position, float((NightRules.config().behavior as Dictionary).dark_margin) + 10.0)
	_raid = {"state": "warning", "time": warning, "attack": attack, "source": source, "target": target, "members": members, "caller": (caller as Variant) if source == "call" else (null as Variant)}
	match source:
		"rush":
			town.banner(String(rush.notice), "")
		"call":
			town.banner(String(call_cfg.notice), "")
		_:
			town.banner("ETWAS REGT SICH IM DUNKELN", "")
	var gather: Vector2 = Vector2.ZERO
	for entry: Dictionary in members:
		gather += (entry.node as Node2D).global_position
	if not members.is_empty():
		town.set_alert(true, (gather / float(members.size()) - town.center).angle()) ## Valdric goes to the edge where they gather
		town.emit_event("alert", {})
	return true


func _begin_attack() -> void:
	var target: Player = _raid_player()
	for entry: Dictionary in _raid.members as Array:
		if target == null or not is_instance_valid(entry.node):
			continue
		var node: Node2D = entry.node as Node2D
		var behavior: NightBehavior = entry.nb as NightBehavior
		behavior.excited = true
		behavior.queue.clear()
		if String(entry.id) == "void_crusher": ## the brute rams the weakest side
			behavior.ram = true
			behavior.goal = _ram_point(target.global_position, node.global_position)
		else:
			behavior.goal = _find_gap(target.global_position, node.global_position)
		behavior.queue.append(target.global_position)
	_raid.state = "attack"
	_raid.time = float(_raid.attack)


## The gap in the net: a dark point 140-360 px from the target whose way to the target crosses the least light (and, once the night remembers, lies on a side that gave way before).
func _find_gap(target: Vector2, from: Vector2) -> Vector2:
	var cfg: Dictionary = NightRules.config().lure as Dictionary
	var town: TownManager = _world.town()
	var remembering: bool = bool(stage().memory)
	var best: Vector2 = target
	var best_score: float = INF
	for attempt: int in int(cfg.gap_tries):
		var point: Vector2 = target + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(140.0, 360.0)
		if town.light_depth(point) > -20.0 or not bool(_world.navigation_floor(point)):
			continue
		var score: float = town.lit_fraction(point, target) + 0.0015 * point.distance_to(from)
		if remembering:
			score -= 0.2 * (sector_weight(_sector_at(point)) - 1.0)
		if score < best_score:
			best_score = score
			best = point
	return best


## The weakest side of the base as a point just outside its light.
func _ram_point(target: Vector2, from: Vector2) -> Vector2:
	var town: TownManager = _world.town() as TownManager
	var best_sector: int = 0
	var best_weight: float = -1.0
	for sector: int in _sectors():
		var weight: float = sector_weight(sector)
		if weight > best_weight:
			best_weight = weight
			best_sector = sector
	_ensure_radii()
	var dir: Vector2 = Vector2.from_angle(NightRules.sector_angle(best_sector, _sectors()))
	var point: Vector2 = town.center + dir * (_radii[best_sector] + 48.0)
	if bool(_world.navigation_floor(point)) and town.light_depth(point) < -10.0:
		return point
	return _find_gap(target, from)


func _raid_attack_tick(players: Array[Player]) -> void:
	var target: Player = _raid_player()
	var town: TownManager = _world.town()
	if not _raid_target_ok():
		target = players[0] if not players.is_empty() else null
		_raid.target = target
	var alive: int = 0
	for entry: Dictionary in _raid.members as Array:
		if not is_instance_valid(entry.node) or ((entry.node as Node2D).get_node("HealthComponent") as HealthComponent).current <= 0.0:
			continue
		alive += 1
		var behavior: NightBehavior = entry.nb as NightBehavior
		if not bool(entry.get("breached", false)) and town.light_depth((entry.node as Node2D).global_position) > 24.0:
			entry["breached"] = true ## it got into the light: this side of the base gave way
			_remember(_sector_at((entry.node as Node2D).global_position), "b", 1.0)
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
		behavior.ram = false
		behavior.queue.clear()
		behavior.goal = Vector2.INF
	var caller: Variant = _raid.get("caller", null)
	if caller != null:
		((caller as Dictionary).nb as NightBehavior).calling = false
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
	_force_raid = true
