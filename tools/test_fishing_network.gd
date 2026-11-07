extends Node
## Two processes, loopback 17898. Start the server first (`-- --server`), then the client.
## Player A belongs to the host: the client only WATCHES it (state packets, shadow, fight, same species on both sides).
## Player B belongs to the client: it casts, strikes and fights over RPC, the host decides and the fish lands in B's bag.
const PORT: int = 17898
const DT: float = 1.0 / 60.0
const RULES_TEST: GDScript = preload("res://tools/test_fishing.gd") ## its `reader` plays like a person who reads the line
var server: bool = false
var rivers: WorldRivers
var fa: FishingComponent
var fb: FishingComponent
var pa: Player
var pb: Player
var client_id: int = 0
var failures: int = 0
var checks: int = 0
var spot: Dictionary = {}
var log_a: Array[int] = []
var fx_a: Array[String] = []
var b_caught: Array[String] = []
var joined: bool = false ## members, not locals: a lambda captures locals by value
var connected: bool = false
var lag_a: Dictionary = {}
var lag_b: Dictionary = {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()


func find_spot() -> Dictionary:
	var data: Dictionary = DataRegistry.table("rivers_baked")
	for ford: Array in data["fords"]:
		var centre: Vector2 = Vector2(float(ford[0]), float(ford[1]))
		for a: int in 16:
			var dir: Vector2 = Vector2.from_angle(float(a) / 16.0 * TAU)
			for r: int in range(20, 160, 2):
				var stand: Vector2 = centre + dir * float(r)
				var x: float = rivers.field_at(stand).x
				if x >= 3.0 and x <= 9.0:
					for reach: int in range(36, 120, 6):
						var target: Vector2 = stand - dir * float(reach)
						if rivers.field_at(target).x <= -12.0 and rivers.field_at(target + Vector2(10, 0)).x <= -8.0:
							return {"stand": stand, "target": target}
					break
	return {}


func make_players() -> void:
	rivers = WorldRivers.new()
	add_child(rivers)
	spot = find_spot()
	pa = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
	pa.name = "1" ## the player node is named after its owner's peer id
	pa.set_multiplayer_authority(1)
	add_child(pa)
	pb = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
	pb.name = str(client_id)
	pb.set_multiplayer_authority(client_id)
	add_child(pb)
	pa.global_position = spot["stand"] as Vector2
	pb.global_position = (spot["stand"] as Vector2) + Vector2(0, 0)
	fa = pa.fishing
	fb = pb.fishing
	fa.fx.connect(func(kind: String, _p: Vector2, _d: Dictionary) -> void: fx_a.append(kind))
	fa.state_changed.connect(func(s: int) -> void: log_a.append(s))
	fb.caught.connect(func(species: String, _l: int, _r: bool, prime: bool) -> void: b_caught.append(species + (":prime" if prime else "")))
	if fb.book != null:
		fb.book = FishBook.new("user://fish_book_net_test_only.json")
	if fa.book != null: ## never the real book of the game
		fa.book = FishBook.new("user://fish_book_net_a_test_only.json")


func run() -> void:
	TimeManager.time_of_day = 0.5
	server = OS.get_cmdline_user_args().has("--server")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if server:
		peer.set_bind_ip("127.0.0.1")
		error = peer.create_server(PORT, 1)
	else:
		error = peer.create_client("127.0.0.1", PORT)
	if error != OK:
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	if server:
		Engine.time_scale = 3.0
		multiplayer.peer_connected.connect(func(id: int) -> void:
			client_id = id
			joined = true)
		for i: int in 1800:
			if joined:
				break
			await get_tree().physics_frame
		check(joined, "the client joined")
		make_players()
		await get_tree().create_timer(4.0).timeout
		await run_server()
	else:
		multiplayer.connected_to_server.connect(func() -> void: connected = true)
		for i: int in 1800:
			if connected:
				break
			await get_tree().physics_frame
		client_id = multiplayer.get_unique_id()
		await get_tree().create_timer(1.5).timeout ## the host builds its players first
		make_players()
		await run_client()


func inventory_has(p: Player, item: String) -> bool:
	return p.inventory.count_item(item) > 0


func run_server() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fish_book_net_test_only.json"))
	check(not spot.is_empty(), "server: spot exists")
	pa.inventory.give("rod_basic", 1)
	pb.inventory.give("rod_basic", 1)
	for p: Player in [pa, pb]:
		for i: int in InventoryComponent.HOTBAR_SIZE:
			if not p.inventory.slots[i].is_empty() and String(p.inventory.slots[i]["id"]) == "rod_basic":
				p.inventory.select(i)
		p._on_inventory_changed()
	await get_tree().create_timer(1.5).timeout
	# --- A: the host's own cast, fought by a bot; the client watches
	fa._rng.seed = 21
	fa._host_request("cast", [spot["target"], "", "cork"])
	var guard: float = 0.0
	var species_a: String = ""
	while guard < 120.0:
		await get_tree().physics_frame
		guard += DT * 3.0
		if fa.state == FishingComponent.S.DRIFTING and fa._bite_t > 0.5:
			fa._bite_t = 0.5
		if fa.state == FishingComponent.S.BITE:
			species_a = fa.species
			fa._host_request("strike", [])
		if fa.state == FishingComponent.S.DRILL:
			Engine.time_scale = 1.0 ## real time, so the client can come to the bank and hold the net
			var input_a: Array = RULES_TEST.reader({"phase": fa.phase, "tension": fa.tension, "tell": fa.tell}, lag_a, 0.2, DT)
			fa._give = float(input_a[0])
			fa._reel = bool(input_a[1])
		if fa.state == FishingComponent.S.IDLE and guard > 2.0 and log_a.has(FishingComponent.S.DRILL):
			break
	Engine.time_scale = 3.0
	var item_a: String = String((FishingRules.species_table()[species_a] as Dictionary)["item"]) if species_a != "" else ""
	check(species_a != "" and inventory_has(pa, item_a), "server: A landed its fish")
	check(pa.inventory.count_item(item_a) == 2, "server: the client's net (an RPC from the helper) made it a prime catch: two fish (%d)" % pa.inventory.count_item(item_a))
	await get_tree().create_timer(1.0).timeout
	# --- B: the client's cast arrives over RPC; the host decides
	guard = 0.0
	var seen_drill: bool = false
	fb._rng.seed = 33
	while guard < 150.0:
		await get_tree().physics_frame
		guard += DT * 3.0
		if fb.state == FishingComponent.S.DRIFTING and fb._bite_t > 0.5:
			fb._bite_t = 0.5
		if fb.state == FishingComponent.S.BITE:
			fb._window = maxf(fb._window, 3.0) ## the host runs at triple speed here: leave the client time to answer over the wire
		if fb.state == FishingComponent.S.DRILL:
			seen_drill = true
		if seen_drill and fb.state == FishingComponent.S.IDLE:
			break
	var item_b: String = ""
	for id: String in FishingRules.species_table():
		var candidate: String = String((FishingRules.species_table()[id] as Dictionary)["item"])
		if inventory_has(pb, candidate):
			item_b = candidate
	check(seen_drill, "server: B's cast, strike and fight ran on the host")
	check(item_b != "", "server: the fish landed in the CLIENT player's bag")
	await get_tree().create_timer(1.5).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fish_book_net_a_test_only.json"))
	print("Fishing network server: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func run_client() -> void:
	# --- watch A
	var guard: float = 0.0
	var saw: Dictionary = {}
	var bobber_moved: bool = false
	var last_bobber: Vector2 = Vector2.ZERO
	var species_seen: String = ""
	var tension_seen: bool = false
	var net_stage: int = 0
	var net_time: float = 0.0
	while guard < 60.0:
		await get_tree().physics_frame
		guard += DT
		saw[fa.state] = true
		for s: int in log_a:
			saw[s] = true
		if fa.state == FishingComponent.S.DRIFTING:
			if last_bobber != Vector2.ZERO and fa.bobber.distance_to(last_bobber) > 0.05:
				bobber_moved = true
			last_bobber = fa.bobber
		if fa.species != "":
			species_seen = fa.species
		if fa.state == FishingComponent.S.DRILL and fa.tension > 0.05:
			tension_seen = true
		if fa.state == FishingComponent.S.DRILL:
			if net_stage == 0 and fa.dist <= 80.0:
				pb.global_position = fa.bobber + Vector2(6, 0) ## the helper wades up to the fish
				net_stage = 1
				net_time = 0.0
			elif net_stage == 1:
				net_time += DT
				pb.global_position = fa.bobber + Vector2(6, 0)
				if net_time >= 0.4 and fa.dist <= 46.0:
					fa.request_net()
					net_stage = 2
		if fa.state == FishingComponent.S.IDLE and log_a.has(FishingComponent.S.DRILL):
			break
	print("client saw A states: ", log_a, " fx: ", fx_a.size(), " guard ", guard)
	check(saw.has(FishingComponent.S.CASTING) or saw.has(FishingComponent.S.DRIFTING), "client: sees A cast")
	check(saw.has(FishingComponent.S.DRIFTING) and saw.has(FishingComponent.S.BITE) and saw.has(FishingComponent.S.DRILL), "client: sees A drift, bite and fight")
	check(species_seen != "", "client: the shadow's species was replicated")
	check(tension_seen, "client: the tension reaches the client")
	check(fx_a.has("splash") and fx_a.has("bite"), "client: effects arrive (splash, bite)")
	check(net_stage == 2 and fx_a.has("net") and fa.netted == false, "client: the helper asked for the net and the net effect arrived (stage %d)" % net_stage)
	check(fa.state == FishingComponent.S.IDLE, "client: A's line is gone afterwards")
	# --- B: the client is the owner (back on the bank first)
	pb.global_position = spot["stand"] as Vector2
	await get_tree().create_timer(1.0).timeout
	pb.inventory._rpc_request_state.rpc_id(1) ## ask for the mirror (rod in the bag)
	await get_tree().create_timer(1.0).timeout
	fb._send("cast", [spot["target"], "", "cork"])
	guard = 0.0
	var fought: bool = false
	var struck: bool = false
	var input_t: float = 0.0
	while guard < 150.0:
		await get_tree().physics_frame
		guard += DT
		if fb.state == FishingComponent.S.BITE and not struck:
			struck = true
			fb._send("strike", [])
		if fb.state == FishingComponent.S.IDLE and struck and not fought: ## missed or refused: cast again
			struck = false
			await get_tree().create_timer(0.8).timeout
			fb._send("cast", [spot["target"], "", "cork"])
		if fb.state == FishingComponent.S.DRILL:
			fought = true
			var input_b: Array = RULES_TEST.reader({"phase": fb.phase, "tension": fb.tension, "tell": fb.tell}, lag_b, 0.2, DT)
			input_t -= DT
			if input_t <= 0.0:
				input_t = 0.05
				fb._rpc_input.rpc_id(1, float(input_b[0]), bool(input_b[1]))
		if fought and fb.state == FishingComponent.S.IDLE:
			break
	check(struck and fought, "client: B struck and fought through RPC")
	await get_tree().create_timer(1.5).timeout
	check(b_caught.size() == 1 and not String(b_caught[0]).ends_with(":prime"), "client: the owner gets the (plain) catch card (%s)" % [b_caught])
	check(fb.book != null and fb.book.species.size() == 1, "client: the owner's river book recorded it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fish_book_net_test_only.json"))
	print("Fishing network client: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
