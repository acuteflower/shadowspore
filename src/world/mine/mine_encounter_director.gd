class_name MineEncounterDirector
extends Node
## Wakes and lets sleep the encounters of the mine levels (host only; docs/mine.md section 9). Encounters exist as data in the layout (`MineEncounters`). One
## wakes when a player comes within `wake_radius_tiles` and fewer than `awake_cap` enemies are awake on the level; its members are spawned as ordinary enemies
## (species, health and damage scaled by the level, `WorldLevel.spawn_species`). When no player is near any more it goes back to sleep (the members vanish and
## stand at their posts again next time). A member that was killed stays dead: bit `i` of the state `enc:<level>:<id>`. When nobody was in a level for
## `respawn_days` game days, its kills are forgotten (state `visit:<level>` is the day somebody was last there).

const TICK: float = 0.5

var _mines: MineManager
var _clock: float = 0.0
var _awake: Dictionary = {} ## "level:id" -> Array[Node2D] (the members that were spawned, by member index; null for the dead)


func _init() -> void:
	name = "Encounters"


func _ready() -> void:
	_mines = get_parent() as MineManager
	set_process(multiplayer.is_server())


func _process(delta: float) -> void:
	_clock += delta
	if _clock < TICK:
		return
	_clock = 0.0
	tick()


## One pass; public for the tests.
func tick() -> void:
	var cfg: Dictionary = MineManager.config().enemies
	var present: Dictionary = _mines.players_present()
	for level: int in present:
		_visit(level, int(cfg.respawn_days))
	_sleep(present, float(cfg.wake_radius_tiles) * 16.0 * float(cfg.sleep_factor))
	for level: int in present:
		_wake(level, present[level] as Array[Vector2], float(cfg.wake_radius_tiles) * 16.0, int(cfg.awake_cap))


## The spawned members of an awake encounter (null where one is dead or was killed before).
func members_of(level: int, id: int) -> Array:
	return _awake.get(_key(level, id), []) as Array


func awake_count(level: int) -> int:
	var count: int = 0
	for key: String in _awake:
		if key.begins_with("%d:" % level):
			for member: Variant in _awake[key] as Array:
				if _alive(member):
					count += 1
	return count


static func _alive(member: Variant) -> bool:
	if member == null or not is_instance_valid(member): ## (check before casting: casting a freed object is itself an error)
		return false
	var node: Node2D = member as Node2D
	if node == null or node.is_queued_for_deletion():
		return false
	return (node.get_node("HealthComponent") as HealthComponent).current > 0.0


func _key(level: int, id: int) -> String:
	return "%d:%d" % [level, id]


func _killed(level: int, id: int) -> int:
	return int(_mines.state.get("enc:%d:%d" % [level, id], 0))


## A level with players in it: remember the day, and forget the kills when it was left alone for long enough.
func _visit(level: int, respawn_days: int) -> void:
	var key: String = "visit:%d" % level
	var last: int = int(_mines.state.get(key, 0))
	var today: int = TimeManager.day + 1 ## stored plus one: the table's 0 means "not there"
	if last > 0 and today - last >= respawn_days:
		for entry: String in _mines.state.keys():
			if entry.begins_with("enc:%d:" % level):
				_mines.set_state(entry, 0)
	if last != today:
		_mines.set_state(key, today)


func _wake(level: int, players: Array[Vector2], radius: float, cap: int) -> void:
	var layout: MineLayout = _mines.layout(level)
	var awake: int = awake_count(level)
	var near: Array[Dictionary] = []
	for encounter: Dictionary in layout.encounters:
		var id: int = int(encounter.id)
		if _awake.has(_key(level, id)):
			continue
		var members: Array = encounter.members as Array
		var alive: int = members.size() - _bits(_killed(level, id), members.size())
		if alive <= 0:
			continue
		var first: Dictionary = members[0] as Dictionary
		var at: Vector2 = Vector2(float(first.x), float(first.y))
		var closest: float = INF
		for player: Vector2 in players:
			closest = minf(closest, player.distance_to(at))
		if closest <= radius:
			near.append({"encounter": encounter, "distance": closest, "alive": alive})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	for entry: Dictionary in near:
		if awake + int(entry.alive) > cap:
			continue
		awake += int(entry.alive)
		_spawn(level, entry.encounter as Dictionary)


func _bits(mask: int, count: int) -> int:
	var set: int = 0
	for i: int in count:
		if mask & (1 << i) != 0:
			set += 1
	return set


func _spawn(level: int, encounter: Dictionary) -> void:
	var world: Node = _mines.get_parent()
	if not world.has_method("spawn_species"):
		return
	var id: int = int(encounter.id)
	var killed: int = _killed(level, id)
	var members: Array = encounter.members as Array
	var spawned: Array[Node2D] = []
	for i: int in members.size():
		spawned.append(null)
		if killed & (1 << i) != 0:
			continue
		var member: Dictionary = members[i] as Dictionary
		var enemy: Node2D = world.call("spawn_species", String(member.enemy), MineManager.origin(level) + Vector2(float(member.x), float(member.y)), float(member.heading), MineManager.health_scale(level), MineManager.damage_scale(level)) as Node2D
		if enemy == null:
			continue
		spawned[i] = enemy
		(enemy.get_node("HealthComponent") as HealthComponent).died.connect(_died.bind(level, id, i))
	_awake[_key(level, id)] = spawned


func _died(level: int, id: int, index: int) -> void:
	_mines.set_state("enc:%d:%d" % [level, id], _killed(level, id) | (1 << index))


## Encounters nobody is near any more fall asleep: the survivors vanish (and wait again at their posts); a level without players sleeps altogether.
func _sleep(present: Dictionary, radius: float) -> void:
	for key: String in _awake.keys():
		var parts: PackedStringArray = key.split(":")
		var level: int = int(parts[0])
		var members: Array = _awake[key] as Array
		var any_alive: bool = false
		var watched: bool = false
		for member: Variant in members:
			if not _alive(member):
				continue
			any_alive = true
			var at: Vector2 = (member as Node2D).global_position - MineManager.origin(level)
			for player: Vector2 in (present.get(level, [] as Array[Vector2]) as Array[Vector2]):
				if player.distance_to(at) <= radius:
					watched = true
		if not any_alive:
			_awake.erase(key)
		elif not watched:
			for member: Variant in members:
				if _alive(member):
					(member as Node2D).queue_free()
			_awake.erase(key)
