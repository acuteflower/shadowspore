extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass
var joined: bool = false
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	TimeManager.time_of_day = 0.97
	var server: bool = OS.get_cmdline_user_args().has("--server")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if server:
		peer.set_bind_ip("127.0.0.1")
		error = peer.create_server(17893, 1)
	else:
		error = peer.create_client("127.0.0.1", 17893)
	if error != OK:
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(_id: int) -> void: joined = true)
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	var pop: TinyPopulation = world.get_node("Wildlife/SmallResidents") as TinyPopulation
	if server:
		var tree: FirTree = get_tree().get_first_node_in_group("bird_perches") as FirTree
		var bee: TinyWildlife = load("res://src/entities/wildlife/tiny_wildlife.tscn").instantiate() as TinyWildlife
		bee.name = "NetBee"
		bee.species = "bee"
		bee.home = tree.position
		bee.position = tree.position + Vector2(30, 0)
		pop._animals.add_child(bee)
		bee.set_physics_process(false)
		bee._act(TinyWildlife.State.MOVE, bee.position, bee.position + Vector2(35, 8), 2, "", Vector2.ZERO, 0.4)
		var snail: TinyWildlife = load("res://src/entities/wildlife/tiny_wildlife.tscn").instantiate() as TinyWildlife
		snail.name = "NetSnail"
		snail.home = tree.position
		snail.position = tree.position
		snail.tree_path = String(tree.get_path())
		snail.tree_offset = Vector2(3, -12)
		pop._animals.add_child(snail)
		snail.set_physics_process(false)
		snail._act(TinyWildlife.State.MOVE, Vector2(3, -12), Vector2(3, -22), 10, snail.tree_path, snail.tree_offset, 3)
		for species: String in ["ladybug", "moth"]:
			var extra: TinyWildlife = load("res://src/entities/wildlife/tiny_wildlife.tscn").instantiate() as TinyWildlife
			extra.name = "Net_" + species
			extra.species = species
			extra.home = tree.position
			extra.position = tree.position + Vector2(20, 12)
			pop._animals.add_child(extra)
			extra.set_physics_process(false)
			extra._act(TinyWildlife.State.FLY if species == "ladybug" else TinyWildlife.State.MOVE, extra.position, extra.position + Vector2(25, 8), 3, "", Vector2.ZERO, 0.3)
		for i: int in 600:
			if joined: break
			await get_tree().physics_frame
		await get_tree().create_timer(0.8).timeout
		pop.chunk_unloaded(Vector2i(floori(snail.home.x / 512), floori(snail.home.y / 512)))
		await get_tree().create_timer(0.5).timeout
		print("Tiny network server: complete")
		get_tree().quit()
	else:
		var saw_bee: bool = false
		var saw_snail: bool = false
		var removed: bool = false
		var saw_lady: bool = false
		var saw_moth: bool = false
		for i: int in 600:
			await get_tree().physics_frame
			var bee: TinyWildlife = pop.get_node_or_null("Animals/NetBee") as TinyWildlife
			var snail: TinyWildlife = pop.get_node_or_null("Animals/NetSnail") as TinyWildlife
			if bee != null:
				saw_bee = saw_bee or (bee.species == "bee" and bee.state == TinyWildlife.State.MOVE and bee._elapsed >= 0.4)
			if snail != null:
				saw_snail = saw_snail or (snail._tree() != null and snail._visual.get_parent() == snail._tree().get_node("Sprite") and snail.tree_offset.y < -14)
			var lady: TinyWildlife = pop.get_node_or_null("Animals/Net_ladybug") as TinyWildlife
			var moth: TinyWildlife = pop.get_node_or_null("Animals/Net_moth") as TinyWildlife
			saw_lady = saw_lady or (lady != null and lady.state == TinyWildlife.State.FLY)
			saw_moth = saw_moth or (moth != null and moth.species == "moth" and moth._visual.visible)
			if saw_bee and saw_snail and saw_lady and saw_moth and bee == null and snail == null and lady == null and moth == null:
				removed = true
				break
		print("Tiny network: bee=%s trunk=%s ladybug=%s moth=%s cleanup=%s" % [saw_bee, saw_snail, saw_lady, saw_moth, removed])
		get_tree().quit(0 if saw_bee and saw_snail and saw_lady and saw_moth and removed else 1)
