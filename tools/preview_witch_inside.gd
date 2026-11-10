extends Node
## The inside of the witch's tower in the real game (interiors `witch_stairs` and `witch_room`, art tools/art_witch_tower_inside.py).
## Godot --rendering-driver opengl3 --path . tools/preview_witch_inside.tscn -- --dir=/abs/folder
## Writes stairs.png (she is half way up the spiral stair) and room.png (the witch's room), and checks that the stair can be walked and the two passages work.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
const SHAFT: Vector2 = Vector2(98, 222) ## the shaft's floor centre (room px)
const RADIUS: float = 76.0 ## the middle of the stair
const RISE: float = 72.0


func _ready() -> void:
	_run.call_deferred()


func _shot(dir: String, name_: String) -> void:
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name_])


func _on_stair(angle: float) -> Vector2:
	return SHAFT + Vector2(cos(angle) * RADIUS, -sin(angle) * RADIUS - RISE * angle / PI)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		Jobs.threaded = false
	var dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	add_child(world)
	var hero: Player = world._players.get_child(0) as Player
	hero.get_node("OpeningGuide").set_process(false)
	hero.quests.set_physics_process(false)
	hero.health.floor_value = hero.health.max_health
	hero.health.current = hero.health.max_health
	hero.sync_wound_visuals()
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.5
	for i: int in 40:
		await get_tree().process_frame
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	var shaft: Interior = interiors.interior("witch_stairs")
	var room: Interior = interiors.interior("witch_room")
	var failed: int = 0
	# the stair: free all the way up its middle, walled on both sides
	for step: int in 25:
		var angle: float = PI * float(step) / 24.0 * 0.97 + 0.02
		hero.global_position = shaft.room_to_global(_on_stair(angle))
		await get_tree().physics_frame
		if hero.test_move(hero.global_transform, Vector2.ZERO):
			failed += 1
			print("FAIL stair blocked at step ", step)
		for side: float in [-1.0, 1.0]:
			if not hero.test_move(hero.global_transform, Vector2(cos(angle), -sin(angle)) * side * 20.0):
				failed += 1
				print("FAIL stair open to the side at step ", step, " side ", side)
	var ways: Array[Doorway] = []
	for inside: Interior in [shaft, room]:
		for child: Node in inside.get_children():
			if child is Doorway and (child as Doorway).to_interior != "":
				ways.append(child as Doorway)
	if ways.size() != 2:
		failed += 1
		print("FAIL passages: ", ways.size())
	interiors.place_player(hero, "witch_stairs", _on_stair(PI * 0.36))
	hero.facing = Vector2(-1, -1).normalized()
	for i: int in 90:
		await get_tree().process_frame
	await _shot(dir, "stairs")
	hero.global_position = ways[0].global_position + Vector2(4, 0)
	await get_tree().physics_frame
	ways[0].interact(hero)
	for i: int in 150:
		await get_tree().process_frame
	if interiors.interior_at(hero.global_position) != room or hero.test_move(hero.global_transform, Vector2.ZERO):
		failed += 1
		print("FAIL the way up: ", hero.global_position - room.global_position)
	var behind_counter: Transform2D = Transform2D(0.0, room.room_to_global(Vector2(163, 142)))
	if hero.test_move(behind_counter, Vector2(0, 7)):
		failed += 1
		print("FAIL bare floor behind the right end of the counter is blocked")
	if not hero.test_move(behind_counter, Vector2(0, 20)):
		failed += 1
		print("FAIL the right end of the counter is passable")
	var beside_counter: Transform2D = Transform2D(0.0, room.room_to_global(Vector2(181, 130)))
	if hero.test_move(beside_counter, Vector2(0, 48)):
		failed += 1
		print("FAIL the path around the counter is blocked")
	hero.global_position = room.room_to_global(Vector2(110, 176) + Vector2(-34, 44))
	hero.facing = Vector2(0.4, -1).normalized()
	TimeManager.time_of_day = 0.64 ## Esma is at the cauldron
	for i: int in 60:
		await get_tree().process_frame
	var witch: InteriorResident = room.get_node_or_null("Witch") as InteriorResident
	var cauldron: Sprite2D = room.props["cauldron"] as Sprite2D
	if witch == null or witch._clip != "stir" or witch._sector != 0 or cauldron.position - witch.position != Vector2(22, -4):
		failed += 1
		print("FAIL Esma's stirring position")
	var fire: Sprite2D
	for animation: Dictionary in room._anims:
		var sprite: Sprite2D = animation.sprite as Sprite2D
		if sprite.texture.resource_path.ends_with("/flames.png"):
			fire = sprite
			break
	if fire == null or fire.hframes != 8 or fire.texture.get_width() != 240:
		failed += 1
		print("FAIL green campfire atlas")
	await _shot(dir, "room")
	ways[1].interact(hero)
	for i: int in 150:
		await get_tree().process_frame
	if interiors.interior_at(hero.global_position) != shaft or hero.test_move(hero.global_transform, Vector2.ZERO):
		failed += 1
		print("FAIL the way down: ", hero.global_position - shaft.global_position)
	if dir.is_empty() or true:
		interiors.place_player(hero, "witch_stairs", Vector2(98, 290))
		for i: int in 60:
			await get_tree().process_frame
		await _shot(dir, "door")
	print("WITCH INSIDE OK" if failed == 0 else "WITCH INSIDE FAILED: %d" % failed)
	get_tree().quit(failed)
