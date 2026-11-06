extends Node
var failures: int = 0
func _ready() -> void:
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.get_node("OpeningGuide").set_process(false)
	player.quests.set_physics_process(false)
	player.health.current = player.health.max_health
	player.sync_wound_visuals()
	var events: WildlifeEvents = world.get_node("WildlifeEvents") as WildlifeEvents
	events.set_process(false)
	var logs: Array[Node] = get_tree().get_nodes_in_group("fallen_logs")
	print("LOADED LOGS: ",logs.size())
	check(logs.size()>0,"fallen trunks populate streamed world")
	check(FallenLog.TEXTURE.get_size() == Vector2(896,240),"24 real texture frames loaded")
	var chosen: FallenLog
	for log_node: FallenLog in logs:
		check(log_node.get_child_count()>=2,"log has real sprite and collision")
		var pos: Vector2 = log_node.global_position
		var spec: Dictionary = log_node._spec
		var a: Vector2 = pos+Vector2(float(spec.a[0]),float(spec.a[1]))
		var b: Vector2 = pos+Vector2(float(spec.b[0]),float(spec.b[1]))
		var clear: bool = true
		for i: int in 9:
			var at: Vector2 = a.lerp(b,i/8.0)
			var tile: Vector2i = Vector2i((at/16.0).floor())
			if world._generator.blocked_cells.has(tile) or not world._relief.flat_around(at,12): clear=false
		check(clear,"whole trunk avoids paths, encounters and cliffs")
		if chosen==null or pos.distance_to(player.position)<chosen.position.distance_to(player.position): chosen=log_node
	if chosen != null:
		player.position = chosen.position+Vector2(0,45)
		player._camera.reset_smoothing()
		world._stream(true)
		TimeManager.set_time(0.4)
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/fallen-logs-world.png")
	# Existing animals and native network actions, held still for deterministic checks.
	var pop: WildlifePopulation = world._wildlife
	var rabbit: WildRabbit = load("res://src/entities/wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
	rabbit.name="EventRabbit"
	var bird_pop: CorvidPopulation = pop.get_node("Corvids") as CorvidPopulation
	var bird: WildCorvid = load("res://src/entities/wildlife/wild_corvid.tscn").instantiate() as WildCorvid
	bird.name="EventCrow"
	bird.species="crow"
	var mammal_pop: WoodlandPopulation = pop.get_node("Woodland") as WoodlandPopulation
	var fox: WoodlandMammal = load("res://src/entities/wildlife/woodland_mammal.tscn").instantiate() as WoodlandMammal
	fox.name="EventFox"
	fox.species="fox"
	var point: Vector2 = world._cover_at+Vector2(30,0)
	rabbit.position=point
	rabbit.home=point
	bird.position=point+Vector2(18,0)
	bird.home=bird.position
	fox.position=point-Vector2(22,0)
	fox.home=fox.position
	pop._animals.add_child(rabbit)
	bird_pop._birds.add_child(bird)
	mammal_pop._residents.add_child(fox)
	for actor: Node in [rabbit,bird,fox]: actor.set_physics_process(false)
	await get_tree().physics_frame
	player.position=point+Vector2(200,0)
	check(events.begin_event("rabbit_crow",rabbit,bird),"rabbit/crow event starts without teleporting actors")
	events.advance_event(0.6)
	check(events.kind=="" and events.last_outcome=="crow_flew_off" and bird.state==WildCorvid.State.FLY,"rabbit approach sends crow into actual takeoff")
	check(not rabbit.ambient_event and not bird.ambient_event,"native autonomy restored after encounter")
	check(float(events._cooldowns.get(rabbit.get_instance_id(),0))>events._clock,"participant cooldown prevents repeated scenes")
	bird.set_physics_process(false)
	check(events.begin_event("rabbit_crow",rabbit,bird),"test can start explicit encounter")
	rabbit._has_threat=true
	events.advance_event(0.1)
	check(events.kind=="" and events.last_outcome=="startled" and not rabbit.ambient_event,"fear interrupts encounter")
	rabbit._has_threat=false
	var partner: WildRabbit = load("res://src/entities/wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
	partner.name="PlayPartner"
	partner.position=point+Vector2(12,0)
	partner.home=partner.position
	pop._animals.add_child(partner)
	partner.set_physics_process(false)
	check(events.begin_event("rabbit_play",rabbit,partner),"two calm rabbits can play together")
	events.advance_event(3.4)
	check(events.last_outcome=="played" and not partner.ambient_event and rabbit.state==WildRabbit.State.GRAZE,"play ends naturally with grazing and grooming")
	check(events.begin_event("fox_hunt",fox,rabbit),"hunt can begin before story interruption")
	player.story_lock=true
	events.advance_event(0.1)
	check(events.kind=="" and not fox.ambient_event and events.last_outcome=="interrupted","cutscene cancels encounter and releases animals")
	player.story_lock=false
	check(events.begin_event("fox_hunt",fox,rabbit),"fox can pursue an existing rabbit")
	events._pouncing=true
	fox._elapsed=0.3
	events.advance_event(0.1)
	check(not rabbit.captured,"distant pounce cannot remove prey")
	fox.position=rabbit.position-Vector2(5,0)
	events.advance_event(0.1)
	check(rabbit.captured and events.last_outcome=="caught" and not fox.ambient_event,"physical contact during pounce catches rabbit")
	await get_tree().create_timer(0.4).timeout
	check(not is_instance_valid(rabbit),"caught rabbit is removed through normal host despawn")
	if chosen != null:
		bird.position=chosen.perch_point
		var perch: Dictionary = bird_pop.choose_perch(bird,Vector2.INF)
		check(not perch.is_empty() and String(perch.path)==String(chosen.get_path()) and float(perch.height)<12.0,"crow can select actual low trunk perch")
	# Stable candidate geometry and facings after rebuilding the same chunk.
	if chosen != null:
		var chunk: Vector2i = Vector2i((chosen.position/512.0).floor())
		var signature: Array = []
		for log_node: FallenLog in (world._chunks[chunk] as WorldLevel.Chunk).fallen_logs: signature.append([log_node.position,log_node.frame])
		world._unload_chunk(chunk)
		world._load_chunk(chunk)
		var rebuilt: Array = []
		for log_node: FallenLog in (world._chunks[chunk] as WorldLevel.Chunk).fallen_logs: rebuilt.append([log_node.position,log_node.frame])
		check(signature==rebuilt,"log positions and baked facings survive chunk reload")
	print("LOGS AND EVENTS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
