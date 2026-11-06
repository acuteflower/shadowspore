extends Node
## Step 8 of the mine: the budget is spent on sleeping encounters on open floor away from the way up and the lift, enemies grow tougher with depth, wake near
## the players, sleep again when they are gone, stay dead and come back after three days.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE ENEMIES FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_plan()
	_scaling()
	await _world()
	print("MINE ENEMIES: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


func _plan() -> void:
	var cfg: Dictionary = MineManager.config().enemies
	for level: int in [1, 2, 5, 10, 20]:
		for s: int in 6:
			var seed_value: int = 77 + s * 4001
			var l: MineLayout = MineGenerator.new().generate(seed_value, level)
			var tag: String = "level %d seed %d" % [level, seed_value]
			var spent: float = 0.0
			var taken: Array[Vector2i] = []
			for encounter: Dictionary in l.encounters:
				spent += float(encounter.cost)
				for member: Dictionary in encounter.members as Array:
					var t: Vector2i = Vector2i(floori(float(member.x) / 16.0), floori(float(member.y) / 16.0))
					_check(l.is_floor(t.x, t.y) and l.solid[t.y * l.edge + t.x] == 0, tag + ": a member stands on free floor")
					_check(Vector2(t).distance_to(Vector2(l.entry)) >= float(cfg.safe_radius_tiles) and Vector2(t).distance_to(Vector2(l.station)) >= float(cfg.safe_radius_tiles), tag + ": members keep away from the way up and the lift")
					for other: Vector2i in taken:
						_check(absi(other.x - t.x) >= 3 or absi(other.y - t.y) >= 3, tag + ": members stand apart")
					taken.append(t)
					if level == 1:
						_check(String(member.enemy) == "shadow_spider", tag + ": level 1 has spiders only")
			_check(absf(l.budget - MineEncounters.budget_of(level, l.edge)) < 0.001, tag + ": budget")
			_check(spent <= l.budget + 0.6 and spent >= l.budget * 0.7, tag + ": the budget is spent (%.1f of %.1f)" % [spent, l.budget])
			if s == 0:
				var again: MineLayout = MineGenerator.new().generate(seed_value, level)
				_check(again.encounters == l.encounters, tag + ": deterministic")
		var sample: MineLayout = MineGenerator.new().generate(77, level)
		print("level %2d: budget %.1f, %d groups, %d enemies" % [level, sample.budget, sample.encounters.size(), _members(sample)])


func _members(l: MineLayout) -> int:
	var n: int = 0
	for encounter: Dictionary in l.encounters:
		n += (encounter.members as Array).size()
	return n


func _scaling() -> void:
	var spider: Dictionary = DataRegistry.get_entry("enemies", "shadow_spider")
	_check(EnemyScaling.scaled(spider, 1.0, 1.0) == spider, "level 1 changes nothing")
	var tough: Dictionary = EnemyScaling.scaled(spider, MineManager.health_scale(10), MineManager.damage_scale(10))
	_check(is_equal_approx(MineManager.health_scale(10), 2.08) and is_equal_approx(MineManager.damage_scale(10), 1.54), "scales of level 10")
	_check(int(tough.max_health) == 100 and int(tough.damage) == 22 and int((tough.grapple as Dictionary).damage) == 26, "spider of level 10: %s hp, %s damage" % [tough.max_health, tough.damage])
	_check(int(spider.max_health) == 48 and int(spider.damage) == 14, "the shared table is untouched")
	var listener: Dictionary = EnemyScaling.scaled(DataRegistry.get_entry("enemies", "void_listener"), 2.0, 2.0)
	_check(int((listener.scream as Dictionary).damage) == 18, "the scream scales")
	for path: String in ["res://src/entities/enemies/shadow_spider.tscn", "res://src/entities/enemies/void_listener.tscn"]:
		var node: Node = (load(path) as PackedScene).instantiate()
		var names: Array[String] = []
		for property: NodePath in (node.get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer).replication_config.get_properties():
			names.append(String(property))
		for wanted: String in [".:enemy_id", ".:health_scale", ".:damage_scale"]:
			_check(names.has(wanted), "%s replicates %s on spawn" % [path.get_file(), wanted])
		node.free()


func _world() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node("Mines") as MineManager
	var director: MineEncounterDirector = mines.get_node("Encounters") as MineEncounterDirector
	var player: Player = world._players.get_child(0) as Player
	player.health.floor_value = 1.0 ## the spiders may hit her, she does not die here
	var level: int = 6
	var l: MineLayout = mines.layout(level)
	_check(l.encounters.size() >= 3, "level %d has encounters" % level)
	mines.enter(player, level)
	var target: Dictionary = {}
	for encounter: Dictionary in l.encounters:
		if (encounter.members as Array).size() >= 2 and target.is_empty():
			target = encounter
	var first: Dictionary = (target.members as Array)[0] as Dictionary
	var second: Dictionary = (target.members as Array)[1] as Dictionary ## open floor a few tiles from the first member
	var near: Vector2 = MineManager.origin(level) + Vector2(float(second.x), float(second.y))
	player.request_teleport(near)
	for i: int in 20:
		await get_tree().process_frame
	director.tick()
	var count: int = (target.members as Array).size()
	var found: Array[Node2D] = []
	for enemy: Node in world._enemies.get_children():
		found.append(enemy as Node2D)
	_check(found.size() >= count, "the encounter woke (%d enemies)" % found.size())
	var spider: ShadowSpider = null
	for enemy: Node2D in found:
		if enemy is ShadowSpider:
			spider = enemy as ShadowSpider
	_check(spider != null and is_equal_approx(spider.health_scale, MineManager.health_scale(level)), "its enemies carry the level's scale")
	if spider != null:
		var expected: float = roundf(48.0 * MineManager.health_scale(level))
		_check(is_equal_approx((spider.get_node("HealthComponent") as HealthComponent).max_health, expected), "a spider of level %d has %.0f health" % [level, expected])
	_check(director.awake_count(level) >= count, "the director counts them awake")
	# they find her and attack (real navigation inside the level)
	await get_tree().create_timer(2.5).timeout
	var busy: bool = false
	for enemy: Node2D in found:
		if enemy is ShadowSpider and (enemy as ShadowSpider).state != ShadowSpider.State.IDLE:
			busy = true
		if enemy is VoidListener and (enemy as VoidListener).state != VoidListener.State.LISTEN:
			busy = true
	_check(busy, "the woken enemies notice the player and act")
	# kill one: stays dead
	var victim: Node2D = null
	for member: Variant in director.members_of(level, int(target.id)):
		if member != null and victim == null:
			victim = member as Node2D
	_check(victim != null, "the encounter's members are known to the director")
	(victim.get_node("HealthComponent") as HealthComponent).take_damage(99999.0, Vector2.ZERO, 0.0)
	for i: int in 3:
		await get_tree().process_frame
	await get_tree().process_frame
	var key: String = "enc:%d:%d" % [level, int(target.id)]
	_check(int(mines.state.get(key, 0)) != 0, "the kill is remembered (%s)" % key)
	# leave: the rest fall asleep
	player.request_teleport(Vector2(500.0, 500.0)) ## out of the mine
	for i: int in 10:
		await get_tree().process_frame
	director.tick()
	for i: int in 3:
		await get_tree().process_frame
	var left: int = 0
	for enemy: Node in world._enemies.get_children():
		if not enemy.is_queued_for_deletion() and (enemy.get_node("HealthComponent") as HealthComponent).current > 0.0 and MineManager.in_mine((enemy as Node2D).global_position):
			left += 1
	_check(left == 0, "far from the players the encounters sleep (%d left)" % left)
	# come back: only the living wake
	player.request_teleport(near)
	for i: int in 10:
		await get_tree().process_frame
	director.tick()
	var again: int = 0
	for enemy: Node in world._enemies.get_children():
		if not enemy.is_queued_for_deletion() and (enemy.get_node("HealthComponent") as HealthComponent).current > 0.0 and enemy.global_position.distance_to(near) < 400.0:
			again += 1
	_check(again == count - 1, "the dead stay dead (%d of %d wake)" % [again, count])
	# three days without anybody there
	player.request_teleport(Vector2(500.0, 500.0)) ## out of the mine
	for i: int in 10:
		await get_tree().process_frame
	director.tick()
	TimeManager.day += 3
	player.request_teleport(near)
	for i: int in 10:
		await get_tree().process_frame
	director.tick()
	_check(not mines.state.has(key), "after three days the kills are forgotten")
	# the awake cap
	var big_level: int = 12
	var big: MineLayout = mines.layout(big_level)
	var cfg: Dictionary = MineManager.config().enemies
	cfg.awake_cap = 3
	mines.enter(player, big_level)
	var middle: Vector2 = MineManager.origin(big_level) + Vector2(float(big.edge) * 8.0, float(big.edge) * 8.0)
	for encounter: Dictionary in big.encounters: ## the crowd of the middle: the player stands at the first group that is far from the way up
		var member: Dictionary = (encounter.members as Array)[0] as Dictionary
		var p: Vector2 = Vector2(float(member.x), float(member.y))
		if p.distance_to(middle - MineManager.origin(big_level)) < 700.0:
			middle = MineManager.origin(big_level) + p
			break
	player.request_teleport(middle)
	for i: int in 20:
		await get_tree().process_frame
	director.tick()
	_check(director.awake_count(big_level) <= 3, "no more than the cap are awake (%d)" % director.awake_count(big_level))
	cfg.awake_cap = 14
