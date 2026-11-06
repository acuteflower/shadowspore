extends Node
## Step 9 of the mine: the gate on the surface, the stairs, the lift and its menu, the table that is saved, death in the mine.

var _ok: bool = true
var _world: WorldLevel
var _mines: MineManager
var _player: Player


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE WAYS FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _find(kind: GDScript, near: Vector2) -> Interactable:
	var best: Interactable = null
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if is_instance_of(node, kind) and (best == null or (node as Node2D).global_position.distance_to(near) < best.global_position.distance_to(near)):
			best = node as Interactable
	return best


func _run() -> void:
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	await _frames(2)
	_mines = _world.get_node("Mines") as MineManager
	_player = _world._players.get_child(0) as Player
	_player.health.floor_value = 1.0
	# the gate on the surface
	var gate: MineEntrance = _world.get_node_or_null("MineEntrance_old_mine") as MineEntrance
	_check(gate != null, "the gate stands in the world")
	if gate == null:
		get_tree().quit(1)
		return
	_check(_mines.entrance == gate.exit_position and gate.exit_position.y > gate.global_position.y, "the mine knows where its gate is")
	_player.request_teleport(gate.exit_position)
	await _frames(20)
	_check(_world.navigation_floor(gate.exit_position), "the way in front of the gate is land")
	var door: Interactable = _find(MineEntrance.MineGate, _player.global_position)
	_check(door != null and door.prompt() == "BETRETEN" and door.reach_distance(_player.global_position) < Interactable.INTERACT_RANGE, "the gate can be used from in front of it")
	# in: level 1
	door.interact(_player)
	await get_tree().create_timer(2.2).timeout
	_check(MineManager.level_at(_player.global_position) == 1, "the gate leads into level 1")
	_check(_player.global_position.distance_to(_mines.arrival(1, "entry")) < 2.0, "she arrives in the entry hall")
	_check(not _player.story_lock and not InputManager.ui_blocking, "control is back after the iris")
	_check(_mines.deepest() == 1, "the deepest level is 1")
	var banner: MineBanner = null
	for child: Node in _mines.get_children():
		if child is MineAtmosphere:
			banner = (child as MineAtmosphere)._banner
	await _frames(5)
	_check(banner != null and banner.is_showing(), "the level's title is shown on arrival")
	await _frames(20)
	# the stairs up lead out again
	var up: MineStairs = _find(MineStairs, _mines.arrival(1, "entry")) as MineStairs
	_check(up != null and up.up and up.prompt() == "NACH DRAUSSEN", "the stairs up of level 1 lead outside")
	_player.request_teleport(up.global_position + Vector2(0, 16))
	await _frames(5)
	up.interact(_player)
	await get_tree().create_timer(2.2).timeout
	_check(MineManager.level_at(_player.global_position) == -1 and _player.global_position.distance_to(gate.exit_position) < 2.0, "the stairs bring her out of the gate")
	# down the stairs of level 1
	_player.request_teleport(_mines.arrival(1, "exit"))
	await _frames(30)
	var down: MineStairs = _find(MineStairs, _player.global_position) as MineStairs
	_check(down != null and not down.up and down.prompt() == "HINUNTER", "the stairs down at the far end")
	_check(down.reach_distance(_player.global_position) < Interactable.INTERACT_RANGE, "she can reach them from where the way arrives")
	down.interact(_player)
	await get_tree().create_timer(2.2).timeout
	_check(MineManager.level_at(_player.global_position) == 2 and _player.global_position.distance_to(_mines.arrival(2, "entry")) < 2.0, "the stairs down lead to level 2")
	_check(_mines.deepest() == 2, "deepest is 2")
	await _frames(20)
	var back: MineStairs = _find(MineStairs, _player.global_position) as MineStairs
	_check(back != null and back.up and back.prompt() == "HINAUF", "level 2 has stairs up")
	# the lift of level 2
	_player.request_teleport(_mines.arrival(2, "station"))
	await _frames(30)
	var winch: MineWinch = _find(MineWinch, _player.global_position) as MineWinch
	_check(winch != null and winch.prompt() == "AUFZUG INSTANDSETZEN", "a broken lift offers to be mended")
	_check(winch.reach_distance(_player.global_position) < Interactable.INTERACT_RANGE, "she can reach the lift from the rest room's front")
	_mines.request_station(2) ## what the picking animation does at its grab
	await _frames(3)
	_check(_mines.station_unlocked(2) and _mines.unlocked_stations().size() == 1 and _mines.unlocked_stations()[0] == 2, "the lift is mended")
	_check(winch.prompt() == "AUFZUG BENUTZEN", "now it can be used")
	var far: Vector2 = _player.global_position
	_player.request_teleport(far + Vector2(2000, 0))
	_mines.request_station(5) ## not within reach of that lift: refused
	await _frames(3)
	_check(not _mines.station_unlocked(5), "a lift far away cannot be mended")
	_player.request_teleport(far)
	await _frames(30)
	winch = _find(MineWinch, far) as MineWinch ## the chunk was freed while she was away
	# menu from inside: to the gate
	winch.interact(_player)
	await _frames(3)
	var menu: LiftMenu = get_tree().get_first_node_in_group("lift_menu") as LiftMenu
	_check(menu != null and menu._rows.size() == 1 and _player.story_lock, "the lift menu offers the gate (%d rows)" % (menu._rows.size() if menu != null else -1))
	menu._choose(0)
	await get_tree().create_timer(2.2).timeout
	_check(MineManager.level_at(_player.global_position) == -1, "the lift takes her to the gate")
	_check(get_tree().get_first_node_in_group("lift_menu") == null and not _player.story_lock, "the menu is gone and she is free")
	# the gate now offers the lift too
	_check(is_instance_valid(door) and is_instance_valid(gate), "gate nodes still exist (%s %s)" % [is_instance_valid(door), is_instance_valid(gate)])
	_player.request_teleport(gate.exit_position)
	await _frames(10)
	door.interact(_player)
	await _frames(3)
	menu = get_tree().get_first_node_in_group("lift_menu") as LiftMenu
	_check(menu != null and menu._rows.size() == 2, "the gate offers level 1 and the mended lift")
	menu._choose(1)
	await get_tree().create_timer(2.2).timeout
	_check(MineManager.level_at(_player.global_position) == 2 and _player.global_position.distance_to(_mines.arrival(2, "station")) < 2.0, "from outside the lift goes down to level 2")
	# the table is what is saved
	var saved: Dictionary = _mines.export_state()
	_check(int(saved.get("deepest", 0)) == 2 and saved.has("station:2"), "the table holds depth and lift")
	_mines.state.clear()
	_mines.import_state(saved)
	_check(_mines.station_unlocked(2) and _mines.deepest() == 2, "and gives them back")
	# a save file keeps all of it, also where she stood
	var path: String = "user://test_mine_save.json"
	_check(SaveGame.save(get_tree(), path), "the game saves inside the mine")
	var here: Vector2 = _player.global_position
	_mines.state.clear()
	_player.request_teleport(Vector2(500.0, 500.0))
	await _frames(5)
	_check(SaveGame.load_into(get_tree(), path), "the save loads")
	await _frames(40)
	_check(_mines.station_unlocked(2) and _mines.deepest() == 2, "the mended lift and the depth are back")
	_check(_player.global_position.distance_to(here) < 1.0 and MineManager.level_at(_player.global_position) == 2, "she stands in level 2 again")
	_check(_mines.level_node(2) != null and (_mines.level_node(2).chunks as Dictionary).size() > 0, "the level around her is built")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# death in the mine: back to the base, nothing is kept in the mine
	_player.health.floor_value = 0.0
	_player.health.take_damage(99999.0, Vector2.ZERO, 0.0)
	await _frames(5)
	_player.request_respawn()
	await get_tree().create_timer(4.5).timeout
	_check(MineManager.level_at(_player.global_position) == -1 and _player.health.current > 0.0, "after death she is back in the world, alive")
	await _frames(5)
	var camera: Camera2D = _player.get("_camera") as Camera2D
	_check(camera.limit_left < -1000000, "the camera is free again")
	print("MINE WAYS: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
