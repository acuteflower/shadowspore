extends Node
## Godot --headless --path . res://tools/test_ellie_sitting.tscn
var failures: int = 0

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	add_child(player)
	player.set_physics_process(false)
	var rig: Dictionary = DataRegistry.table("hero_rig")
	var rest: Dictionary = rig.rest as Dictionary
	var sit: Dictionary = rig.sit as Dictionary
	check(int(rest.rows) == 8 and int(sit.rows) == 8, "both sitting atlases contain eight directions")
	check(RestComponent.SHEET.get_size() == RestComponent.BLOOD.get_size(), "resting injury and bandage masks match")
	check(Player.SIT_SHEET.get_size() == Player.SIT_BLOOD.get_size(), "story-sitting injury and bandage masks match")
	for sector: int in 8:
		player.show_rest_frame(int((rest.idle as Array)[0]), sector)
		check(player._sprite.frame_coords.y == sector and not player._sprite.flip_h, "rest uses true direction %d" % sector)
		check((player._sprite.material as ShaderMaterial).get_shader_parameter("blood_map") == RestComponent.BLOOD, "rest injury map is bound")
		player.show_sit_frame(int(sit.down), sector)
		check(player._sprite.frame_coords.y == sector and not player._sprite.flip_h, "story sitting uses true direction %d" % sector)
		check((player._sprite.material as ShaderMaterial).get_shader_parameter("blood_map") == Player.SIT_BLOOD, "story injury map is bound")
	var spot: CampfireSeat = CampfireSeat.new()
	for sector: int in 8:
		spot.facing_sector = sector
		check(spot.sit_sector() == sector and Adventurer.sector_of(spot.sit_direction()) == sector, "seat can select direction %d" % sector)
	spot.facing_sector = -1
	spot.which = "east"
	check(spot.sit_sector() == 4, "stump faces the fire")
	spot.which = "south"
	check(spot.sit_sector() == 5, "log faces the fire")
	spot.free()
	var component: RestComponent = player.get_node("RestComponent") as RestComponent
	component._rng.seed = 782
	component._gesture = -1
	var seen: Dictionary = {}
	for i: int in 80:
		var previous: int = component._gesture
		var next: int = component._choose_gesture()
		check(next >= 0 and next < RestComponent.GESTURE_STATES.size() and next != previous, "random choice %d avoids immediate repetition" % i)
		component._gesture = next
		seen[next] = true
	check(seen.size() == 5, "all five seated gestures are selectable")
	for gesture: int in RestComponent.GESTURE_STATES.size():
		component._set_state(RestComponent.State.IDLE)
		component._start_gesture(gesture)
		check(component.state == RestComponent.GESTURE_STATES[gesture], "host starts gesture %d" % gesture)
	var scene: KnightFireScene = KnightFireScene.new()
	add_child(scene)
	scene.set_physics_process(false)
	scene._player = player
	scene._rig = sit
	scene._rest_rig = rest
	scene._east = true
	scene._set_mode(KnightFireScene.Mode.LOOP)
	scene._sit_wait = 0.0
	scene._physics_process(0.0)
	check(scene._sit_gesture >= 0, "story sitting can choose an ambient gesture")
	scene._physics_process(0.25)
	check(player._sprite.texture == RestComponent.SHEET and player._sprite.frame_coords.y == 4, "story plays the seated gesture facing the fire")
	scene._set_mode(KnightFireScene.Mode.TAKE)
	scene._east = false
	scene._physics_process(0.0)
	check(scene._sit_gesture == -1 and player._sprite.texture == Player.SIT_SHEET and player._sprite.frame_coords.y == 5, "story mug action interrupts the gesture and uses its true northwest view")
	print("ELLIE SITTING: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
