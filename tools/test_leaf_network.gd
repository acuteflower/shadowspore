extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
## Loopback check of the real WorldLevel prop RPC, visual takeoff and late snapshot.
class TestWorld:
	extends WorldLevel
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	func coast_tiles(_point: Vector2) -> float: return 100.0

var world: WorldLevel
var bush: Bush
var ready_peer: int = 0
var completed: bool = false
var server: bool = false

func _ready() -> void:
	run.call_deferred()

func make_world() -> void:
	world = TestWorld.new()
	world.name = "World"
	for label: String in ["Ground", "Glow"]:
		var layer: TileMapLayer = TileMapLayer.new()
		layer.name = label
		world.add_child(layer)
	for label: String in ["Players", "Enemies"]:
		var group: Node2D = Node2D.new()
		group.name = label
		world.add_child(group)
	var animals: WildlifePopulation = WildlifePopulation.new()
	animals.name = "Wildlife"
	animals.process_mode = Node.PROCESS_MODE_DISABLED
	var children: Node2D = Node2D.new()
	children.name = "Animals"
	animals.add_child(children)
	world.add_child(animals)
	add_child(world)
	for i: int in 500:
		var candidate: Bush = load("res://src/entities/props/bush.tscn").instantiate() as Bush
		candidate.setup(world, Vector2i(3 + i * 16, 5), "bush", 1)
		candidate.position = PropGenerator.position_of(candidate.cell)
		world.add_child(candidate)
		world._things[candidate.cell] = candidate
		candidate.set_process(false)
		if LeafCritter.today(candidate) == "beetle":
			bush = candidate
			break
		world._things.erase(candidate.cell)
		candidate.free()

func run() -> void:
	Moisture.world_seed = 4242
	TimeManager.day = 3
	TimeManager.time_of_day = 0.5
	TimeManager.locked = true
	server = OS.get_cmdline_user_args().has("--server")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if server:
		peer.set_bind_ip("127.0.0.1")
		error = peer.create_server(17896, 1)
	else:
		error = peer.create_client("127.0.0.1", 17896)
	if error != OK:
		push_error("Leaf loopback could not open peer: %s" % error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	make_world()
	if bush == null:
		get_tree().quit(1)
		return
	await get_tree().process_frame
	if server:
		for i: int in 600:
			if ready_peer != 0: break
			await get_tree().physics_frame
		if ready_peer == 0:
			get_tree().quit(1)
			return
		world.startle_critter(bush.cell)
		var took_off: bool = bush._critter._flee >= 0.0 and int(world.thing_state(bush.cell).get("c", 0)) == TimeManager.day + 1
		for i: int in 600:
			if completed: break
			await get_tree().physics_frame
		print("LEAF NETWORK host departure=%s late_snapshot=%s" % [took_off, completed])
		get_tree().quit(0 if took_off and completed else 1)
	else:
		for i: int in 600:
			if multiplayer.get_peers().has(1): break
			await get_tree().physics_frame
		var origin: Vector2 = bush._critter.global_position
		_client_ready.rpc_id(1)
		var animated: bool = false
		for i: int in 180:
			await get_tree().physics_frame
			animated = animated or (bush._critter._flee > 0.1 and bush._critter.global_position.distance_to(origin) > 1.0)
			if int(world.thing_state(bush.cell).get("c", 0)) == TimeManager.day + 1 and bush._critter.kind == "": break
		var absent: bool = not LeafCritter.can_catch(bush) and bush.prompt() == ""
		world.free()
		make_world() ## same peer, fresh unloaded props, like a client joining later
		_request_snapshot.rpc_id(1)
		for i: int in 180:
			await get_tree().physics_frame
			if int(world.thing_state(bush.cell).get("c", 0)) == TimeManager.day + 1: break
		var late: bool = bush._critter.kind == "" and bush.prompt() == ""
		print("LEAF NETWORK client animated=%s absent=%s late_snapshot=%s" % [animated, absent, late])
		if animated and absent and late: _client_done.rpc_id(1)
		await get_tree().create_timer(0.2).timeout
		get_tree().quit(0 if animated and absent and late else 1)

@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if multiplayer.is_server(): ready_peer = multiplayer.get_remote_sender_id()

@rpc("any_peer", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server(): world._rpc_thing_snapshot.rpc_id(multiplayer.get_remote_sender_id(), world._thing_states)

@rpc("any_peer", "reliable")
func _client_done() -> void:
	if multiplayer.is_server(): completed = true
