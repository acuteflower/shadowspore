extends Node
const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")
## Godot --headless --path . tools/test_wildlife.tscn
## Uses OfflineMultiplayerPeer, no listening socket and no save access.

class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var rabbit: WildRabbit = load("res://src/entities/wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
	rabbit.name = "TestRabbit"
	add_child(rabbit)
	rabbit.set_physics_process(false)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(90, 0)
	await get_tree().physics_frame
	rabbit._sense()
	_check(rabbit.state == WildRabbit.State.ALERT, "Walking approach should first cause alertness")
	player.position = Vector2(40, 0)
	await get_tree().physics_frame
	rabbit._sense()
	_check(rabbit.state == WildRabbit.State.FLEE, "Close player should trigger flight")
	player.position = Vector2(250, 0)
	await get_tree().physics_frame
	rabbit._sense()
	rabbit._safe_time = 2.7
	rabbit._think()
	_check(rabbit.state == WildRabbit.State.RECOVER, "Flight should end only after sustained safety")

	player.position = Vector2(80, 0)
	player.stealth.sneaking = true
	await get_tree().physics_frame
	rabbit._set_state(WildRabbit.State.GRAZE, 3.0)
	rabbit._sense()
	_check(rabbit.state == WildRabbit.State.GRAZE, "Sneaking should permit closer observation")
	player.stealth.sneaking = false
	player.sprinting = true
	rabbit._sense()
	_check(rabbit.state == WildRabbit.State.FLEE, "Sprinting should scare the rabbit earlier")
	player.sprinting = false

	var companion: WildRabbit = load("res://src/entities/wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
	companion.name = "Companion"
	companion.position = Vector2(0, 25)
	add_child(companion)
	companion.set_physics_process(false)
	rabbit._alarm_neighbours()
	_check(companion.state == WildRabbit.State.ALERT, "Nearby rabbit ignored its companion's alarm")
	companion.queue_free()

	# Actual world collision still applies to an airborne rabbit.
	var wall: StaticBody2D = StaticBody2D.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(5, 70)
	collider.shape = shape
	wall.position = Vector2(18, 0)
	wall.add_child(collider)
	add_child(wall)
	player.position = Vector2(300, 0)
	await get_tree().physics_frame
	rabbit._begin_hop(Vector2.ZERO, Vector2(40, 0), 0.4, 7.0, 0.0)
	rabbit._advance_hop(0.4)
	_check(rabbit.position.x < 15.1 and not rabbit._hopping, "Rabbit hopped through a solid wall")
	rabbit.position = Vector2.ZERO
	rabbit._threat = Vector2(-30, 0)
	rabbit._try_hop(Vector2.RIGHT, true)
	_check(not rabbit._hopping or rabbit._hop_end.x < 14.0, "Flight planner chose a blocked landing")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	rabbit.position = Vector2.ZERO
	rabbit._begin_hop(Vector2.ZERO, Vector2(40, 0), 0.4, 7.0, 0.0)
	rabbit._advance_hop(0.05)
	_check(rabbit.position == Vector2.ZERO, "Rabbit moved during takeoff compression")
	rabbit._advance_hop(0.15)
	rabbit._process(0.0)
	_check(absf(rabbit.position.x - 20.0) < 0.1 and rabbit._sprite.position.y == -7.0, "Hop arc and ground travel disagree")
	rabbit._advance_hop(0.2)
	_check(rabbit.position.is_equal_approx(Vector2(40, 0)) and not rabbit._hopping, "Rabbit did not land on its chosen point")

	# Check every rendered pose, facing and coat, including full sheets and grounded pivot.
	for variant: int in 6:
		for sector: int in 8:
			rabbit.appearance = variant
			rabbit.facing = sector * PI / 4.0
			for mood: int in [WildRabbit.State.REST, WildRabbit.State.GRAZE, WildRabbit.State.ALERT, WildRabbit.State.GROOM]:
				rabbit.state = mood as WildRabbit.State
				rabbit._process(0.0)
				_check(rabbit._sprite.frame >= 0 and rabbit._sprite.frame < 1248, "Rabbit animation frame outside sheet")
	player.queue_free()
	rabbit.queue_free()
	await get_tree().process_frame

	# Real map integration: meadow habitats, streaming, population cap and cross-border retention.
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	for frame: int in 30:
		await get_tree().physics_frame
	var population: WildlifePopulation = world.get_node("Wildlife") as WildlifePopulation
	population.set_process(false)
	var animals: Array[Node] = population._animals.get_children()
	print("Initial meadow population: ", animals.size())
	_check(not animals.is_empty(), "Starting area has no wildlife")
	_check(animals.size() <= int(population._spec["max_loaded"]), "Population cap exceeded")
	for node: Node in animals:
		var wild: WildRabbit = node as WildRabbit
		wild.set_physics_process(false)
		_check(world._rabbit_habitat(wild.home), "Rabbit spawned outside green safe habitat")
		_check(wild.appearance >= 0 and wild.appearance < 6, "Invalid coat variant")
	if not animals.is_empty():
		var tracked: WildRabbit = animals[0] as WildRabbit
		var home_cell: Vector2i = Vector2i(floori(tracked.home.x / 512.0), floori(tracked.home.y / 512.0))
		var next_cell: Vector2i = home_cell + Vector2i(1, 0)
		tracked.position = Vector2(next_cell) * 512.0 + Vector2(200, 200)
		population._active[next_cell] = true
		population.chunk_unloaded(home_cell)
		population._collect_departed()
		_check(not tracked.is_queued_for_deletion(), "Home unload deleted a rabbit that fled into an active chunk")
		population._active.erase(next_cell)
		population._collect_departed()
		_check(tracked.is_queued_for_deletion(), "Offscreen rabbit was never cleaned up")
	world.queue_free()
	await get_tree().process_frame
	Terrain.relief = null
	print("Wildlife: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
