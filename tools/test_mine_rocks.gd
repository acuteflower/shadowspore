extends Node
## Step 7 of the mine: rocks and collapses. The layout puts them where they do not wall anyone in, chunks spawn them as props of the world (so the pickaxe,
## saving and growing back work as everywhere), mining takes them down hit by hit to rubble, collapses do not grow back, ordinary rocks do.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE ROCKS FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# layout: rocks stand on floor with rock behind them, collapses lie across passages off the main way
	for level: int in [1, 6, 12, 20]:
		var l: MineLayout = MineGenerator.new().generate(1234, level)
		var rocks: int = 0
		var piles: int = 0
		for c: Vector2i in l.chunk_rocks:
			for r: Dictionary in l.chunk_rocks[c] as Array:
				var tx: int = floori(float(r.x) / 16.0)
				var ty: int = floori(float(r.y) / 16.0)
				if String(r.kind) == "mine_rock":
					rocks += 1
					_check(l.is_floor(tx, ty) and not l.is_floor(tx, ty - 1), "level %d: a rock stands against a wall" % level)
				else:
					piles += 1
					_check(l.is_floor(tx, ty), "level %d: a collapse rock lies on floor" % level)
		_check(rocks > 0, "level %d has rocks (%d)" % [level, rocks])
		for pile: Dictionary in l.collapses:
			var key: int = int(pile.key)
			_check(not l.critical.has(key), "level %d: a collapse is not on the main way" % level)
		print("level %d: %d rocks, %d collapse rocks in %d piles" % [level, rocks, piles, l.collapses.size()])
	# in the world: spawn, mine, save, grow back
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node("Mines") as MineManager
	var player: Player = world._players.get_child(0) as Player
	player.inventory.add_item("pickaxe_basic", 1)
	var level: int = 1
	var l1: MineLayout = mines.layout(level)
	var target: Dictionary = {}
	for c: Vector2i in l1.chunk_rocks:
		if target.is_empty() and String((l1.chunk_rocks[c] as Array)[0].kind) == "mine_rock":
			target = (l1.chunk_rocks[c] as Array)[0]
	mines.enter(player, level)
	var at: Vector2 = MineManager.origin(level) + Vector2(float(target.x), float(target.y))
	player.request_teleport(at + Vector2(0, 16))
	for i: int in 30:
		await get_tree().process_frame
	var cell: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	var rock: MineRock = world._things.get(cell) as MineRock
	_check(rock != null, "the rock is a prop of the world")
	if rock == null:
		get_tree().quit(1)
		return
	# select the pickaxe
	for i: int in 8:
		if String((player.inventory.slots[i] as Dictionary).get("id", "")) == "pickaxe_basic":
			player.inventory.select(i)
	await get_tree().process_frame
	var hits: int = 0
	while not rock.is_depleted() and hits < 12:
		world.harvest_hit(rock, 1)
		hits += 1
		await get_tree().process_frame
	_check(rock.is_depleted() and hits == rock.slots(), "the rock is mined down in %d hits (%d slots)" % [hits, rock.slots()])
	_check(int(world.thing_state(cell).get("h", 0)) == rock.slots(), "the state is kept by the world")
	var saved: Dictionary = world.export_things()
	_check(saved.has("%d,%d" % [cell.x, cell.y]), "the mined rock is in the save")
	# a day passes: the ordinary rock gets a slot back after two days
	world._grow_things(2)
	await get_tree().process_frame
	_check(int(world.thing_state(cell).get("h", 0)) == rock.slots() - 1, "an ordinary rock grows back, a slot a time")
	# a collapse rock does not
	var pile: Dictionary = {}
	for c: Vector2i in l1.chunk_rocks:
		for r: Dictionary in l1.chunk_rocks[c] as Array:
			if String(r.kind) == "mine_collapse" and pile.is_empty():
				pile = r
	if not pile.is_empty():
		var pat: Vector2 = MineManager.origin(level) + Vector2(float(pile.x), float(pile.y))
		var pcell: Vector2i = Vector2i(floori(pat.x / 16.0), floori(pat.y / 16.0))
		player.request_teleport(pat + Vector2(0, 40))
		for i: int in 30:
			await get_tree().process_frame
		var heap: MineRock = world._things.get(pcell) as MineRock
		if heap != null:
			while not heap.is_depleted():
				world.harvest_hit(heap, 1)
				await get_tree().process_frame
			world._grow_things(2)
			world._grow_things(4)
			await get_tree().process_frame
			_check(heap.is_depleted(), "a collapse stays open")
	# leaving the chunk frees the rocks and the table entry stays
	mines.leave(player)
	(MineManager.config().world as Dictionary).unload_seconds = 0.1
	await get_tree().create_timer(0.5).timeout
	_check(world._things.get(cell) == null, "the rock leaves the world's table with its chunk")
	_check(int(world.thing_state(cell).get("h", 0)) > 0, "its state stays")
	print("MINE ROCKS: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
