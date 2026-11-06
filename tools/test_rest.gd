extends Node
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func wait_state(rest: RestComponent, target: RestComponent.State, seconds: float = 6.0) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while rest.state != target and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	check(rest.state == target, "reaches sitting state %d" % target)

func wait_gesture(rest: RestComponent, seconds: float = 12.0) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while rest.state not in RestComponent.GESTURE_STATES and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	check(rest.state in RestComponent.GESTURE_STATES, "a random seated gesture starts")

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ellie-rest-%s.png" % label)

func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.get_node("OpeningGuide").set_process(false)
	var hut: Hut = world._hut()
	var east: CampfireSeat = hut.get_node("Seat_east") as CampfireSeat
	var south: CampfireSeat = hut.get_node("Seat_south") as CampfireSeat
	var rest: RestComponent = player.get_node("RestComponent") as RestComponent
	check(east.prompt() == "" and south.prompt() == "", "free seats locked before fire dialogue")
	world.debug_return_home()
	check(east.prompt() == "HINSETZEN" and south.prompt() == "HINSETZEN", "both seats unlocked after fire dialogue")
	var quests_before: Dictionary = player.quests.export_data()
	var inventory_before: Array = player.inventory.slots.duplicate(true)
	# Requesting a distant seat must not teleport the player.
	rest.request_sit(east)
	check(rest.state == RestComponent.State.FREE, "host rejects out-of-range requests")
	for spot: CampfireSeat in [east, south]:
		player.request_teleport(spot.approach_position())
		spot.interact(player)
		await wait_state(rest, RestComponent.State.IDLE)
		check(player.story_lock and player.fainting and player.global_position.distance_to(spot.seat_position()) < 1.0, "player sits on the chosen seat")
		check(player._sprite.frame_coords.y == spot.sit_sector(), "seat uses its actual viewing direction")
		await capture(spot.which)
		check(spot.occupied() and spot.prompt() == "", "occupied seat is unavailable")
		check(rest._prompt != null, "get-up prompt is visible")
		if spot == east:
			await wait_gesture(rest)
			var previous: int = rest._gesture
			await capture("gesture")
			await wait_state(rest, RestComponent.State.IDLE, 4.0)
			rest._next_gesture = 0.0
			await wait_gesture(rest, 3.0)
			check(rest._gesture != previous, "consecutive seated gestures differ")
			rest.request_stand()
		else:
			Input.action_press("interact")
			await get_tree().physics_frame
			await get_tree().physics_frame
			Input.action_release("interact")
		await wait_state(rest, RestComponent.State.FREE)
		check(not player.story_lock and not player.fainting and rest._prompt == null, "standing restores controls and removes prompt")
		check(player.global_position.distance_to(spot.approach_position()) < 1.0, "standing returns to the front of the seat")
	check(player.quests.export_data() == quests_before and player.inventory.slots == inventory_before, "free sitting preserves quests and inventory")
	for sector: int in 8:
		east.facing_sector = sector
		check(east.sit_sector() == sector and Adventurer.sector_of(east.sit_direction()) == sector, "seat can face true sector %d" % sector)
		player.show_rest_frame(18, east.sit_sector())
		check(player._sprite.frame_coords.y == sector and not player._sprite.flip_h, "sitting uses independently rendered sector %d" % sector)
	east.facing_sector = -1
	player.end_faint()
	# Valdric's place is blocked while he remains at the fire.
	world.place_knight("fire")
	check(south.occupied() and south.prompt() == "" and east.prompt() != "", "Valdric occupies only his own seat")
	world.place_knight("door")
	player.request_teleport(east.approach_position())
	rest.request_sit(east)
	await wait_state(rest, RestComponent.State.IDLE)
	player.health.take_damage(1.0, player.global_position + Vector2(20, 0), 0.0)
	check(rest.state == RestComponent.State.FREE and not player.story_lock and not player.fainting, "damage interrupts sitting immediately")
	player.request_teleport(east.approach_position())
	rest.request_sit(east)
	await wait_state(rest, RestComponent.State.IDLE)
	player.request_teleport(hut.exit_position)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(rest.state == RestComponent.State.FREE and not player.story_lock, "teleport clears sitting without returning to seat")
	player.request_teleport(south.approach_position())
	rest.request_sit(south)
	await wait_state(rest, RestComponent.State.IDLE)
	Input.action_press("move_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_right")
	await wait_state(rest, RestComponent.State.FREE)
	check(not player.story_lock and not player.fainting, "movement stands up and restores walking")
	player.request_teleport(south.approach_position() + Vector2(15, 8))
	rest.request_sit(south)
	Input.action_press("move_right")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("move_right")
	check(rest.state == RestComponent.State.FREE and not player.story_lock, "movement cancels approach without leaving a sitting lock")
	print("REST: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
