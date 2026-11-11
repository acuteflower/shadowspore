extends Node
## The lake witch's house, step 1 (docs/seehexe_konzept.md 11): the house stands on its tile at the Hexenwald lake, flat and between lake and void;
## its door leads into the room `lake_hut` and back; the ward ring stands, lights the night (magic light), keeps the mist's lies out, wakes stone by
## stone and round-trips through the save; the lake stones grow at the shore (Seeglimmer only at night). Prints `LAKE HUT OK`.
## `-- --capture=/abs/dir` saves pictures (needs a window, `--rendering-driver opengl3`).
var _ok: bool = true
var _dir: String = ""
var _checks: int = 0


func _check(name: String, value: bool) -> void:
	_checks += 1
	if not value:
		_ok = false
		print("FAILED: ", name)


func _shot(name: String) -> void:
	if _dir == "":
		return
	for _i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_dir = arg.trim_prefix("--capture=")
	_run.call_deferred()


func _settle(world: WorldLevel, frames: int = 400) -> void:
	for _i: int in frames:
		await get_tree().process_frame
		if world._pending_commit == null and _i > 30:
			var player: Player = world._players.get_child(0) as Player
			var chunk: Vector2i = Vector2i((player.global_position / (16.0 * 32.0)).floor())
			if world._chunks.has(chunk):
				break


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.health.heal_full()
	var spec: Dictionary = {}
	for h: Dictionary in DataRegistry.table("ground").get("huts", []) as Array:
		if String(h.id) == "lake_hut":
			spec = h
	_check("ground.json has the lake hut", not spec.is_empty())
	var hut: Hut = world.get_node_or_null("Hut_lake_hut") as Hut
	_check("the house stands", hut != null and hut.art == "lake")
	var tile: Vector2i = Vector2i(738, 936)
	_check("on its tile", hut.position.is_equal_approx(Vector2(tile) * 16.0 + Vector2(8, 8)))
	# the ground: flat level 0, Hexenwald, between the lake (north) and the void (south)
	var relief: Relief = Terrain.relief as Relief
	if relief != null:
		_check("flat ground under the house", relief.flat_around(hut.position + Vector2(0, -12), 40.0))
		_check("level 0", relief.level_at(hut.position) < 0.5)
	_check("Hexenwald (gloom) at the house", BiomeBlend.amount_at(hut.position) > 0.5)
	# the door: in and out
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	_check("room lake_hut is known", interiors.interior("lake_hut") != null)
	player.global_position = hut.exit_position
	await _settle(world)
	await _shot("0_house_day")
	interiors.use_door(player, hut.doorway)
	await get_tree().create_timer(1.8).timeout
	_check("inside the room", Interiors.slot_at(player.global_position) >= 0)
	await _shot("1_room")
	var room: Interior = interiors.interior("lake_hut")
	interiors.use_door(player, room.door)
	await get_tree().create_timer(1.8).timeout
	_check("back outside at the door", player.global_position.distance_to(hut.exit_position) < 4.0)
	# the ward ring
	var ring: WardRing = world.get_node_or_null("WardRing_lake_hut") as WardRing
	_check("the ward ring stands", ring != null and ring.stones.size() == 9)
	_check("asleep until the quest wakes it", not ring.awake)
	ring._rpc_state(true, false) ## (the entry quest does this: tools/test_lake_quest.tscn)
	_check("its light is a night light", TownManager.magic_lights.has(ring.get_instance_id()))
	var circle: Vector3 = TownManager.magic_lights[ring.get_instance_id()] as Vector3
	_check("circle round the house", Vector2(circle.x, circle.y).distance_to(hut.position) < 50.0 and circle.z >= 240.0)
	_check("the house is sheltered", WardRing.shelters(hut.position))
	_check("far away is not", not WardRing.shelters(hut.position + Vector2(400, 0)))
	for stone: Array in ring.stones:
		var at: Vector2 = ring.to_global(stone[0] as Vector2)
		_check("stone on land %s" % at, world._land_at(int(at.x / 16.0), int(at.y / 16.0)))
	# the mist tells no lies inside the ring, it does outside
	player.global_position = hut.exit_position + Vector2(0, 10)
	player.effects._breathe_mist()
	_check("no hallucination inside the ring", not player.effects.has("hallucinated"))
	ring._rpc_state(false, false)
	_check("asleep: no light", not TownManager.magic_lights.has(ring.get_instance_id()) and not WardRing.shelters(hut.position))
	player.effects._breathe_mist()
	_check("asleep: the mist lies here too", player.effects.has("hallucinated"))
	ring.set_awake(true)
	_check("waking starts dark", ring._lit_count() == 0)
	await get_tree().create_timer(2.2).timeout
	_check("the stones woke one by one", ring._lit_count() == ring.stones.size() and ring.awake)
	player.effects._breathe_mist()
	_check("awake again: the lies are gone", not player.effects.has("hallucinated"))
	# save round trip
	var saved: Dictionary = {}
	ring._rpc_state(false, false)
	for node: Node in get_tree().get_nodes_in_group("ward_rings"):
		saved[(node as WardRing).id] = (node as WardRing).export_state()
	_check("export holds the ring", saved.get("lake_hut", true) == false)
	ring._rpc_state(true, false)
	WardRing.by_id(get_tree(), "lake_hut").import_state(bool(saved.lake_hut))
	_check("import restores it", not ring.awake)
	ring._rpc_state(true, false)
	# the lake stones at the shore: walk along the south and east shore so the chunks there load
	var kinds: Dictionary = {}
	for at: Vector2i in [Vector2i(726, 930), Vector2i(708, 920), Vector2i(700, 900), Vector2i(752, 912), Vector2i(745, 890), Vector2i(720, 885)]:
		player.global_position = Vector2(at) * 16.0
		await _settle(world, 240)
		for cell: Vector2i in world._things:
			var prop: WorldProp = world._things[cell] as WorldProp
			if is_instance_valid(prop) and (prop.kind == "lake_glimmer" or prop.kind == "lake_moonstone"):
				kinds[prop.kind] = int(kinds.get(prop.kind, 0)) + 1
				if prop.kind == "lake_glimmer" and not kinds.has("glim_node"):
					kinds["glim_node"] = prop
	print("lake stones: ", {"glimmer": kinds.get("lake_glimmer", 0), "moonstone": kinds.get("lake_moonstone", 0)})
	_check("Seeglimmer grows at the water", int(kinds.get("lake_glimmer", 0)) >= 4)
	_check("Seemondstein lies on the shore", int(kinds.get("lake_moonstone", 0)) >= 2)
	var glim: Pebble = kinds.get("glim_node") as Pebble
	if glim != null:
		TimeManager.set_time(0.5)
		glim.set_night(0.0)
		_check("by day the Seeglimmer is hidden", glim.prompt() == "" and not glim._sprite.visible)
		TimeManager.set_time(0.0)
		glim.set_night(1.0)
		_check("at night it can be picked", glim.prompt() == "SAMMELN" and glim._sprite.visible)
	_check("the items exist", DataRegistry.table("items").has("lake_glimmer") and DataRegistry.table("items").has("lake_moonstone"))
	if _dir != "":
		player.global_position = hut.exit_position + Vector2(0, 40)
		TimeManager.set_time(0.5)
		await _settle(world)
		await get_tree().create_timer(0.6).timeout
		await _shot("2_house_noon")
		TimeManager.set_time(0.0)
		await get_tree().create_timer(1.0).timeout
		await _shot("3_house_night")
	print("%d checks" % _checks)
	print("LAKE HUT OK" if _ok else "LAKE HUT FAILED")
	get_tree().quit(0 if _ok else 1)
