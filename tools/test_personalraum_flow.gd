extends Node
## Ellie's room: take the broom, the door opens, the hallway lies under shadow smoke until she steps in and then the smoke lifts, and back again. Offline, no save access.
## Godot --headless --path . --fixed-fps 60 tools/test_personalraum_flow.tscn      (native shots: --rendering-driver opengl3 ... -- --capture=/abs/dir)

var _ok: bool = true
var _checks: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_ok = false
		push_error("PERSONALRAUM FLOW: " + message)


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
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(3)
	TimeManager.time_of_day = 0.5
	var player: Player = world._players.get_child(0) as Player
	player.set_physics_process(false)
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	var room: Interior = interiors.interior("personalraum")
	var hall: Interior = interiors.interior("flur")
	_check(room != null and hall != null, "both rooms exist")
	_check(hall.veiled and not hall.revealed and not room.veiled, "the hallway is hidden, the room is not")
	player.global_position = room.room_to_global(Vector2(192, 150))
	await _frames(5)
	player.quests.start("take_broom")
	var broom: InteriorPickup = null
	for spot: Interactable in room.pickups:
		broom = spot as InteriorPickup
	_check(broom != null and broom.prop_id == "broom", "the broom can be picked up")
	_check(room.door.prompt() == "", "the door does not answer before the broom is taken")
	_check(broom.prompt() == "NEHMEN", "the broom says NEHMEN")
	broom._take(player)
	_check(player.quests.has_flag("broom_taken"), "taking it sets the flag")
	_check(not (room.props["broom"] as Sprite2D).visible and not (room.props["broom_clips"] as Sprite2D).visible and (room.props["broom_mount"] as Sprite2D).visible, "the broom and its clips are gone, the mount stays")
	_check(broom.prompt() == "", "nothing left to take")
	_check(String(player.quests.current().get("step_id", "")) == "leave_room", "the quest asks her to leave the room")
	_check(room.door.prompt() == "ÖFFNEN", "the door answers now")
	player.global_position = room.room_to_global(Vector2(192, 166))
	await _frames(2)
	await _shot(dir, "1_room")
	_check(hall.global_position.is_equal_approx(room.global_position + Vector2(-1280, 192)) and room.neighbors.has(hall) and hall.neighbors.has(room), "the hallway lies right under the room")
	var view: Rect2 = room.view_rect(Vector2(640, 360))
	_check(view.is_equal_approx(hall.view_rect(Vector2(640, 360))) and view.has_point(hall.room_to_global(Vector2(128, 90))) and view.has_point(room.room_to_global(Vector2(128, 10))), "the camera frames both")
	_check(interiors.interior_at(room.room_to_global(Vector2(100, 100))) == room and interiors.interior_at(hall.room_to_global(Vector2(100, 50))) == hall, "each place belongs to its room")
	_check(hall.veiled and not hall.revealed and not hall.lifting, "she sees the hallway, still under its smoke")
	var shut: bool = player.test_move(player.global_transform, Vector2(0, 40))
	_check(shut, "the shut door blocks her")
	room.door.interact(player)
	for i: int in 8:
		await _frames(12)
		await _shot(dir, "open_%d" % i)
	_check(room.door.is_open and room.door.prompt() == "" and room.door.blocker.disabled, "the door is open and no longer blocks")
	_check(player.quests.has_flag("door_open_personalraum"), "the open door is remembered")
	_check(not hall.lifting, "opening the door does not lift the smoke: she has not stepped in")
	player.global_position = room.room_to_global(Vector2(192, 196))
	await _frames(3)
	_check(hall.lifting, "stepping through the doorway lifts the smoke")
	_check(player.quests.has_flag("left_personalraum") and player.quests.has_flag("entered_flur"), "the flags are set")
	_check(not player.quests.is_active("take_broom"), "the quest is done")
	player.global_position = hall.room_to_global(Vector2(1470, 40))
	for i: int in 12:
		await _frames(14)
		await _shot(dir, "lift_%02d" % i)
	await _frames(60)
	_check(hall.revealed and not hall.lifting and not hall._veil.visible, "the smoke is gone")
	await _shot(dir, "4_open")
	_check(player.quests.has_flag("revealed_flur"), "the hallway is remembered as seen")
	player.global_position = hall.room_to_global(Vector2(1470, 26)) ## right below the wall: she stands in front of it, not behind it
	await _frames(4)
	await _shot(dir, "5_below_wall")
	player.global_position = hall.room_to_global(Vector2(60, 50))
	await _frames(4)
	await _shot(dir, "6_hall")
	var torch_x: Array[float] = []
	var flag_x: Array[float] = []
	for key: String in hall.props:
		var at: float = (hall.props[key] as Sprite2D).position.x
		if key.begins_with("torch"):
			torch_x.append(at)
		elif key.begins_with("flag"):
			flag_x.append(at)
	torch_x.sort()
	flag_x.sort()
	_check(torch_x == [320.0, 576.0, 832.0, 1088.0, 1344.0, 1600.0] and flag_x == [256.0, 384.0, 512.0, 640.0, 768.0, 896.0, 1024.0, 1152.0, 1280.0, 1408.0, 1536.0, 1664.0], "a torch between every two doors, a flag half way between a torch and a door")
	_check(hall.props.has("bench0") and hall.props.has("jar1"), "benches and jars stand in the hallway")
	var names: Array[String] = ["flur_l4", "flur_l2", "flur_r1"]
	var door_x: Array[float] = [192.0, 960.0, 1728.0] ## the three locked doors, in hall px
	for i: int in 3:
		var fake: Interior = interiors.interior(names[i])
		_check(fake != null and fake.veiled and fake.spec.get("fake", false) and fake.neighbors.has(room) and room.neighbors.has(fake), "%s: a fake room next to Ellie's" % names[i])
		_check(fake.size.x == room.size.x and fake.global_position.y == room.global_position.y, "%s: Ellie's width, on the row of her room" % names[i])
		_check(fake.door != null and fake.door.prompt() == "ÖFFNEN" and not fake.door.blocker.disabled and not fake.door.is_open, "%s: the door answers with ÖFFNEN but is shut" % names[i])
		player.global_position = hall.room_to_global(Vector2(door_x[i], 30))
		await _frames(4)
		_check(interiors.interior_at(player.global_position) == hall and not fake.revealed and not fake.lifting, "%s: standing before its door does not lift its smoke" % names[i])
		fake.door.interact(player)
		await _frames(8)
		_check(not fake.door.is_open and not fake.door.blocker.disabled and player.test_move(player.global_transform, Vector2(0, -40)), "%s: it is locked: E does not open it, the door keeps her out" % names[i])
		await _shot(dir, "7_door_%d" % i)
	for pair: Array in [["flur_l3", 448.0], ["flur_l1", 1216.0]]:
		var inner: Interior = interiors.interior(String(pair[0]))
		_check(inner != null and inner.veiled and not inner.spec.get("fake", false) and inner.crows_none(), "%s: a real room, no crow" % inner.id)
		_check(inner.door.prompt() == "ÖFFNEN" and not inner.door.is_open, "%s: its door can be opened" % inner.id)
		player.global_position = hall.room_to_global(Vector2(float(pair[1]), 30))
		await _frames(4)
		inner.door.interact(player)
		await _frames(30)
		_check(inner.door.is_open and inner.door.blocker.disabled and not inner.revealed, "%s: the door is open, the smoke still lies on the room" % inner.id)
		await _shot(dir, "7b_%s_open" % inner.id)
		player.global_position = inner.room_to_global(Vector2(192, 150))
		for i: int in 3:
			await _frames(25)
			await _shot(dir, "7c_%s_lift_%d" % [inner.id, i])
		await _frames(100)
		_check(inner.revealed and player.quests.has_flag("revealed_" + inner.id) and interiors.interior_at(player.global_position) == inner, "%s: stepping in lifts its smoke" % inner.id)
		await _shot(dir, "7d_%s_room" % inner.id)
	player.global_position = hall.room_to_global(Vector2(60, 50)) ## the far left end
	await _frames(4)
	_check(Interiors.slot_at(player.global_position) >= 0 and interiors.interior_at(player.global_position) == hall, "the left end of the hallway is still inside")
	await _shot(dir, "8_left_end")
	player.global_position = hall.room_to_global(Vector2(1740, 50))
	await _frames(4)
	await _shot(dir, "9_right_end")
	var gang: Interior = interiors.interior("flur_gang")
	_check(gang != null and gang.veiled and not gang.revealed and gang.neighbors.has(hall) and hall.neighbors.has(gang), "the corridor is hidden and shares the view with the hallway")
	_check(gang.global_position.is_equal_approx(hall.global_position + Vector2(640, -454)) and gang.size == Vector2(128, 454), "it leads up from where the third room's door would be, along the entrance hall")
	_check(is_equal_approx(gang.view_rect(Vector2(640, 360)).size.x, hall.view_rect(Vector2(640, 360)).size.x) and gang.view_rect(Vector2(640, 360)).is_equal_approx(hall.view_rect(Vector2(640, 360))), "the camera frames the same thing there")
	player.global_position = hall.room_to_global(Vector2(704, 40))
	await _frames(4)
	_check(not player.test_move(player.global_transform, Vector2(0, -60)), "from the hallway she can walk straight into the opening")
	_check(not gang.revealed and interiors.interior_at(player.global_position) == hall, "standing before it does not lift its smoke")
	await _shot(dir, "10_gang_closed")
	player.global_position = gang.room_to_global(Vector2(64, 290))
	for i: int in 4:
		await _frames(20)
		await _shot(dir, "11_gang_lift_%d" % i)
	await _frames(120)
	_check(gang.revealed and player.quests.has_flag("revealed_flur_gang"), "stepping in lifts the corridor's smoke")
	await _shot(dir, "12_gang_open")
	player.global_position = gang.room_to_global(Vector2(64, 110))
	await _frames(4)
	await _shot(dir, "13_gang_end")
	var saal: Interior = interiors.interior("flur_saal")
	_check(saal != null and saal.veiled and not saal.revealed and saal.neighbors.has(hall) and saal.global_position.is_equal_approx(gang.global_position + Vector2(128, -634)) and saal.size == Vector2(704, 776), "the entrance hall lies beside the corridor, its west wall on the corridor's east wall, hidden")
	_check(gang.view_rect(Vector2(640, 360)).is_equal_approx(saal.view_rect(Vector2(640, 360))) and gang.view_rect(Vector2(640, 360)).has_point(saal.room_to_global(Vector2(10, 10))), "one view for the corridor and the hall")
	player.global_position = gang.room_to_global(Vector2(70, 108)) ## at the top of the corridor, in front of the opening in its east wall
	await _frames(6)
	await _shot(dir, "14_opening")
	_check((room._back.material as ShaderMaterial).shader.resource_path.ends_with("room_veil.gdshader") and not interiors.interior("hut")._back.visible, "the free space is the veil's smoke, the dark of the hut is off while she is not there")
	_check(not player.test_move(player.global_transform, Vector2(50, 0)), "the opening in the east wall lets her through to the aisle")
	player.global_position = gang.room_to_global(Vector2(70, 300)) ## below the opening: the wall is closed
	await _frames(4)
	_check(player.test_move(player.global_transform, Vector2(40, 0)), "elsewhere the east wall is shut")
	player.global_position = saal.room_to_global(Vector2(64, 742)) ## through the opening: the hall's smoke lifts
	for i: int in 4:
		await _frames(25)
		await _shot(dir, "15_saal_lift_%d" % i)
	await _frames(100)
	_check(saal.revealed and player.quests.has_flag("revealed_flur_saal"), "stepping through the opening lifts the hall's smoke")
	await _shot(dir, "16_saal")
	var spots: Array = [["17_saal_aisle", Vector2(64, 300)], ["17_saal_nave", Vector2(352, 640)], ["17_saal_stairs", Vector2(352, 420)], ["17_saal_east", Vector2(640, 200)]]
	for spot: Array in spots:
		player.global_position = saal.room_to_global(spot[1] as Vector2)
		await _frames(40)
		await _shot(dir, String(spot[0]))
	for door_name: String in ["door_w", "door_e"]:
		var way: Doorway = null
		for child: Node in saal.get_children():
			if child is Doorway and child.position.x == (64.0 if door_name == "door_w" else 640.0):
				way = child as Doorway
		_check(way != null and way.prompt() == "ÖFFNEN" and way.locked_text != "", "%s: a locked door at the end of the aisle" % door_name)
	player.global_position = saal.room_to_global(Vector2(352, 560)) ## the steps are open: she can climb them
	await _frames(4)
	_check(not player.test_move(player.global_transform, Vector2(0, -280)), "the steps can be climbed")
	player.global_position = saal.room_to_global(Vector2(352, 150)) ## and stands on the second level
	await _frames(30)
	await _shot(dir, "18_platform")
	_check(interiors.interior_at(player.global_position) == saal and not player.test_move(player.global_transform, Vector2(0, -20)), "the platform is a floor she can walk on")
	var pillar: Sprite2D = saal.props["pillar_w2"] as Sprite2D ## behind a pillar the pillar fades away
	player.global_position = pillar.global_position + Vector2(0, -60)
	await _frames(40)
	_check(pillar.modulate.a < 0.3, "behind a pillar the pillar fades out")
	player.global_position = pillar.global_position + Vector2(80, 30)
	await _frames(60)
	_check(pillar.modulate.a > 0.9, "and comes back when she steps out")
	player.global_position = saal.room_to_global(Vector2(156, 275)) ## beside the steps the platform's edge stops her
	await _frames(4)
	_check(player.test_move(player.global_transform, Vector2(0, -40)), "the platform's front edge beside the steps is shut")
	player.global_position = hall.room_to_global(Vector2(1000, 30)) ## the seats of the benches
	await _frames(4)
	var seat: HallSeat = hall.get_node("Seat_bench3_0") as HallSeat if hall.has_node("Seat_bench3_0") else null
	_check(seat != null and seat.prompt() == "HINSETZEN", "a bench offers HINSETZEN")
	if seat != null:
		player.global_position = seat.approach_position()
		var rest: RestComponent = player.get_node("RestComponent") as RestComponent
		rest.request_sit(seat)
		await _frames(300)
		_check(rest.state != RestComponent.State.FREE and seat.occupied() and seat.prompt() == "", "she sits on the bench, the seat is taken")
		await _shot(dir, "17_sitting")
		rest.request_stand()
		await _frames(120)
		_check(rest.state == RestComponent.State.FREE and not player.story_lock, "she gets up again")
	print("personalraum flow test: %d checks, %s" % [_checks, "OK" if _ok else "FAILED"])
	get_tree().quit(0 if _ok else 1)
