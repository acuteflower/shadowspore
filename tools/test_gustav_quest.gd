extends Node
## The Gustav quest line (docs/gustav_quest_konzept.md): the chain `town_start` -> `gustav_rescue` -> `town_workshop`, no tools from Valdric, the wagon's door only in its step, the sickle given
## once by the welcome, migration of old saves, the dev checkpoint "GUSTAV GERETTET" and the escort's rules. Run with `--fixed-fps 60`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("GUSTAV QUEST FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _step(player: Player) -> String:
	return String(player.quests.current().get("step_id", ""))


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	## --- data: the chain and its steps ---
	var order: Array[String] = ["rescue_valdric", "rescue_call", "follow_knocks", "kill_wagon_spider", "free_gustav", "gustav_meet", "escort", "welcome"]
	var steps: Array = DataRegistry.get_entry("quests", "gustav_rescue").steps as Array
	_check(steps.size() == order.size(), "gustav_rescue has %d steps" % order.size())
	for i: int in mini(steps.size(), order.size()):
		_check(String((steps[i] as Dictionary).id) == order[i], "step %d is %s" % [i, order[i]])
	_check(String(DataRegistry.get_entry("quests", "town_start").get("next", "")) == "gustav_rescue", "town_start leads into the rescue")
	_check(String(DataRegistry.get_entry("quests", "gustav_rescue").get("next", "")) == "town_workshop", "the rescue leads into the workshop quest")
	for dialogue_id: String in ["gustav_call", "gustav_welcome", "workshop_done", "pickaxe_made"]:
		_check(DataRegistry.table("dialogue").has(dialogue_id), "dialogue %s exists" % dialogue_id)
	var gustav_spec: Dictionary = DataRegistry.get_entry("settlers", "gustav") as Dictionary
	_check(String(gustav_spec.get("takes_over", "")) == "story_gustav", "the settler takes over the story figure")

	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var quests: QuestComponent = player.quests
	await _frames(60)

	## --- the wagon stands where the concept says, its door answers only in the step `free_gustav` ---
	var wagon: GustavWagon = world.get_node_or_null("Wagon_gustav") as GustavWagon
	_check(wagon != null, "the wagon is placed from data/ground.json")
	if wagon != null:
		_check(wagon.position.distance_to(Vector2(884.0, 689.0) * 16.0) < 40.0, "the wagon stands at tile 884, 689")
		quests.import_data({"active": {"gustav_rescue": 3}, "active_steps": {"gustav_rescue": "kill_wagon_spider"}, "done": ["find_help", "lumberjack", "rebuild_hut", "town_start"], "flags": {"rebuild_done": true, "hud_unlocked": true}})
		_check(wagon.prompt() == "", "no door prompt while the spider lives")
		quests.import_data({"active": {"gustav_rescue": 4}, "active_steps": {"gustav_rescue": "free_gustav"}, "done": ["find_help", "lumberjack", "rebuild_hut", "town_start"], "flags": {"rebuild_done": true, "hud_unlocked": true, "wagon_seen": true, "wagon_spider_dead": true}})
		_check(wagon.prompt() != "", "the door can be opened in the step free_gustav")
		quests.import_data({"active": {"gustav_rescue": 5}, "active_steps": {"gustav_rescue": "gustav_meet"}, "done": ["find_help", "lumberjack", "rebuild_hut", "town_start"], "flags": {"rebuild_done": true, "hud_unlocked": true, "wagon_opened": true}})
		_check(wagon.prompt() == "", "and not afterwards")

	## --- Valdric no longer hands out tools; the welcome gives the sickle exactly once ---
	var gave: Dictionary = DataRegistry.get_entry("dialogue", "town_intro") as Dictionary
	_check(not str(gave).contains("sickle") and not str(gave).contains("pickaxe"), "town_intro gives nothing")
	var welcome: Dictionary = DataRegistry.get_entry("dialogue", "gustav_welcome") as Dictionary
	_check(str(welcome).contains("sickle_basic") and str(welcome).contains("gustav_joined"), "the welcome gives the sickle and sets gustav_joined")

	## --- migration of an old save ---
	var old_flags: Dictionary = {"rebuild_done": true, "hud_unlocked": true, "built_lamp_post": true, "built_workshop": true}
	quests.import_data({"active": {"town_start": 5}, "active_steps": {"town_start": "meet_stranger"}, "done": ["find_help", "lumberjack", "rebuild_hut"], "flags": old_flags})
	_check(quests.is_finished("town_start") and quests.is_finished("gustav_rescue") and quests.has_flag("gustav_joined"), "an old save at meet_stranger counts the rescue as done")
	quests.import_data({"active": {"town_start": 5}, "active_steps": {"town_start": "meet_stranger"}, "done": ["find_help", "lumberjack", "rebuild_hut"], "flags": old_flags.duplicate()})
	_check(quests.is_active("town_workshop") and _step(player) == "ws_pickaxe", "and waits for the pickaxe (%s)" % _step(player))
	var made: Dictionary = old_flags.duplicate()
	made["crafted_pickaxe"] = true
	quests.import_data({"active": {"town_start": 6}, "active_steps": {"town_start": "gustav_hello"}, "done": ["find_help", "lumberjack", "rebuild_hut"], "flags": made})
	_check(quests.is_finished("town_workshop"), "a save with a made pickaxe finishes the workshop quest")
	quests.import_data({"active": {"town_start": 4}, "active_steps": {"town_start": "build_workshop"}, "done": ["find_help", "lumberjack", "rebuild_hut"], "flags": {"rebuild_done": true, "hud_unlocked": true}})
	world.resume_story(player)
	_check(quests.is_finished("town_start") and quests.is_active("gustav_rescue") and _step(player) == "rescue_valdric", "an old save at build_workshop begins the rescue (%s)" % _step(player))

	## --- the dev checkpoint GUSTAV GERETTET ---
	world.debug_jump_gustav()
	await _frames(120)
	_check(_step(player) == "ws_gather", "the checkpoint waits at the material list (%s)" % _step(player))
	_check(quests.is_finished("gustav_rescue") and quests.has_flag("gustav_joined"), "the rescue is done")
	_check(player.inventory.has_item("sickle_basic") and not player.inventory.has_item("pickaxe_basic"), "sickle yes, pickaxe no")
	_check(town.founded and town.residents.has("gustav") and town.settler_node("gustav") != null, "Gustav lives in the town")

	## --- the escort: invulnerable, at most two spiders, the night waves held back ---
	quests.import_data({"active": {"gustav_rescue": 6}, "active_steps": {"gustav_rescue": "escort"}, "done": ["find_help", "lumberjack", "rebuild_hut", "town_start"], "flags": {"rebuild_done": true, "hud_unlocked": true, "wagon_opened": true, "gustav_packed": true}})
	if wagon != null:
		player.request_teleport(wagon.position + Vector2(40.0, 30.0))
		await _frames(90)
		world.start_gustav_escort(player)
		await _frames(120)
		var scene: GustavEscortScene = player.get_node_or_null("GustavEscortScene") as GustavEscortScene
		_check(scene != null, "the escort scene runs")
		var figure: StoryGustav = get_tree().get_first_node_in_group("story_gustav") as StoryGustav
		_check(figure != null and figure.invulnerable, "Gustav cannot be hurt during the escort")
		var peak: int = 0
		for i: int in 600:
			await get_tree().process_frame
			var alive: int = 0
			for node: Node in get_tree().get_nodes_in_group("predators"):
				if node is ShadowSpider and not (node as ShadowSpider).is_queued_for_deletion() and String((node as ShadowSpider).name).begins_with("Story"):
					alive += 1
			peak = maxi(peak, alive)
		_check(peak <= GustavEscortScene.MAX_ALIVE, "never more than two escort spiders at once (%d)" % peak)
		_check(world.night != null and world.night.story_hold, "the night waves are held back while he walks")
		if scene != null:
			scene.queue_free()
			await _frames(5)
	print("GUSTAV QUEST: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
