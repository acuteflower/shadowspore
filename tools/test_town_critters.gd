extends Node
## Animals in the town (src/town/town_critters.gd): perches on the pieces, a crow that lands on a roof, a fox that walks up to the stockpile, sniffs and leaves, the wear and the
## spill pictures of the pieces, Gustav's splitting spot. Needs the finished town of the developer checkpoint. Run with `--fixed-fps 60`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN CRITTERS FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	await _frames(60)
	world.debug_jump_town()
	await _frames(120)
	_check(town.critters != null, "the town has its critters director")
	# --- perches
	var perches: Array[Node] = get_tree().get_nodes_in_group("town_perches")
	_check(perches.size() >= 12, "roofs, lamps, benches and fences offer perches (%d)" % perches.size())
	for node: Node in perches:
		_check(not (node as RoofPerch).is_depleted(), "a finished piece's perch is free to use")
	var store: Vector2 = town.position_of(town.built_ids("stockpile")[0])
	# --- a crow comes in from outside and lands on a roof
	player.request_teleport(store + Vector2(0, 200))
	await _frames(60)
	var crow: WildCorvid = town.critters.debug_visit("crow") as WildCorvid
	_check(crow != null, "a visiting crow can be spawned")
	if crow != null:
		for i: int in 900:
			await get_tree().process_frame
			if crow.state != WildCorvid.State.FLY and not crow._perch_path.is_empty():
				break
		_check(not crow._perch_path.is_empty() and crow.get_node_or_null(NodePath(crow._perch_path)) is RoofPerch, "it landed on a perch of the town (%s)" % crow._perch_path)
		_check(crow._height > 10.0, "and sits high above the ground (%.0f)" % crow._height)
	# --- a fox walks up to the stockpile and sniffs
	TimeManager.time_of_day = 0.92 ## the night: foxes are about
	player.request_teleport(store + Vector2(0, 330))
	await _frames(60)
	var fox: WoodlandMammal = town.critters.debug_visit("fox") as WoodlandMammal
	_check(fox != null, "a visiting fox can be spawned")
	if fox != null:
		var near: float = INF
		var sniffed: bool = false
		var trail: String = ""
		for i: int in 2400:
			await get_tree().process_frame
			if i % 300 == 0 and is_instance_valid(fox):
				trail += " [%d: mood %d stage %d d %.0f]" % [i, fox.mood, fox._visit_stage, fox.global_position.distance_to(fox.visit) if fox.visit.is_finite() else -1.0]
			if not is_instance_valid(fox):
				break
			near = minf(near, fox.global_position.distance_to(fox.visit_look + Vector2(0.0, 24.0)))
			sniffed = sniffed or fox.mood == WoodlandMammal.Mood.FORAGE and fox.global_position.distance_to(store) < 60.0
			if not fox.visit.is_finite() and fox._leave_hops == 0 and fox._visit_stage == 1:
				break
		_check(sniffed, "the fox sniffed within a few steps of the stockpile" + trail)
		_check(is_instance_valid(fox) and not fox.visit.is_finite(), "and left when it was done")
	# --- the wear and the lights of the pieces
	var shop_id: int = town.built_ids("workshop")[0]
	var view: TownStructure = town.view_of(shop_id)
	if view != null:
		_check(view.age_days() >= 6, "the checkpoint town has stood for days (%d)" % view.age_days())
		var shown: int = 0
		for entry: Dictionary in view._wear:
			shown += 1 if (entry.sprite as Sprite2D).visible else 0
		_check(shown == view._wear.size() and shown == 3, "all its wear shows (%d)" % shown)
		_check(view._spill != null and view._sparks != null, "the workshop has forge light and sparks")
	# --- Gustav's day has a splitting block and a bench
	var gustav: Settler = town.settler_node("gustav")
	_check(gustav != null, "Gustav is there")
	if gustav != null:
		var split: Vector2 = gustav.spot_position("split")
		_check(split.distance_to(store) < 60.0, "he splits wood beside the stockpile (%s)" % str(split - store))
		_check(gustav.resolve_spot("bench") == "bench", "the checkpoint town has a bench for his evening")
		var plan: Dictionary = gustav.plan_at(0.35)
		_check(String(plan.spot) == "split", "the morning has a splitting spell")
	print("TOWN CRITTERS: ", "ok" if _ok else "FAILED")
	get_tree().quit()
