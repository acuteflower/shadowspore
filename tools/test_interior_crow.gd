extends Node
## The crow on the window sill of Ellie's room: sits, flies out when somebody comes near, comes back when they are gone. Offline, no save access.
## Godot --headless --path . --fixed-fps 60 tools/test_interior_crow.tscn      (native shots: --rendering-driver opengl3 ... -- --capture=/abs/dir)

var _ok: bool = true
var _checks: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_ok = false
		push_error("INTERIOR CROW: " + message)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _shot(dir: String, name: String) -> void:
	if dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			dir = arg.substr(10)
	TimeManager.set_process(false)
	TimeManager.time_of_day = 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(3)
	TimeManager.time_of_day = 0.5
	var player: Player = world._players.get_child(0) as Player
	player.set_physics_process(false)
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	var room: Interior = interiors.interior("personalraum")
	_check(room != null, "the room exists")
	var crow: InteriorCrow = null
	for child: Node in room.get_children():
		if child is InteriorCrow:
			crow = child as InteriorCrow
	_check(crow != null, "the room has its crow")
	if crow == null:
		get_tree().quit(1)
		return
	player.global_position = room.room_to_global(Vector2(104, 140))
	await _frames(30)
	_check(crow._state == InteriorCrow.State.PERCHED and crow.visible, "it sits while the player is far away")
	await _shot(dir, "1_sitting")
	player.global_position = room.room_to_global(Vector2(120, 110))
	await _frames(30)
	_check(crow._state == InteriorCrow.State.ALERT or crow._state == InteriorCrow.State.LEAVING, "somebody near: it looks and takes off")
	for i: int in 8:
		await _frames(10)
		await _shot(dir, "leave_%d" % i)
	await _frames(1)
	_check(crow.z_index == -6 and crow._state == InteriorCrow.State.LEAVING, "mid-flight it is outside the plane, behind the wall")
	await _shot(dir, "2_leaving")
	await _frames(70)
	_check(crow._state == InteriorCrow.State.AWAY and not crow._sprite.visible, "it is gone")
	await _frames(600)
	_check(crow._state == InteriorCrow.State.AWAY, "it does not come back while the player stays near")
	player.global_position = room.room_to_global(Vector2(200, 170))
	await _frames(620)
	_check(crow._state == InteriorCrow.State.RETURNING or crow._state == InteriorCrow.State.PERCHED, "player away: it comes back")
	await _frames(100)
	_check(crow._state == InteriorCrow.State.PERCHED and crow.z_index == 0 and crow.position.is_equal_approx(crow._perch), "and sits on the sill again")
	await _shot(dir, "3_back")
	for tool: Array in [["broom", 40.0], ["rake", 66.0]]: ## she can walk up to the wall mounts: behind the nightstand strip, past the bed's head
		player.global_position = room.room_to_global(Vector2(100, 84))
		await _frames(2)
		for i: int in 200:
			if player.move_and_collide(Vector2(-0.5 if player.global_position.x > room.room_to_global(Vector2(float(tool[1]), 0)).x else 0.0, 0.0)) != null:
				break
		var from_tool: float = absf(player.global_position.x - room.room_to_global(Vector2(float(tool[1]), 0)).x)
		_check(from_tool < 6.0, "she can stand at the %s (x offset %.1f)" % [tool[0], from_tool])
	print("interior crow test: %d checks, %s" % [_checks, "OK" if _ok else "FAILED"])
	get_tree().quit(0 if _ok else 1)
