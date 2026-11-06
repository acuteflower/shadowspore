extends Node
## The story of the town (quest `town_start`, docs/town.md): after the renewal the town founds itself, the next morning Valdric hands over tools, a lamp post and a workshop
## follow, the stranger (Gustav) walks into the light and moves in. Run with `--fixed-fps 60`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN STORY FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _step(player: Player) -> String:
	return String(player.quests.current().get("step_id", ""))


func _site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 16):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 10.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for id: String in ["lamp_post", "workshop"]:
		(TownRules.piece(id) as Dictionary)["build_seconds"] = 0.6
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	var quests: QuestComponent = player.quests
	quests.import_data({"active": {}, "done": ["find_help", "lumberjack", "rebuild_hut"], "flags": {"rebuild_done": true, "knows_adventurer": true, "hud_unlocked": true}})
	quests.start("town_start")
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(150)
	_check(town.founded, "the town founds itself from the quest flag")
	_check(_step(player) == "town_night" and String(quests.current().text).begins_with("RUHE DICH AUS"), "the town quest waits for the morning (%s)" % _step(player))
	var bed: StorySpot = (world.get_node("Interiors") as Interiors).interior("hut").get_node("BedRest") as StorySpot
	_check(bed.prompt() == "SCHLAFEN", "the bed can be used again in the town quest's night")
	TimeManager.set_time(0.9) ## late in the night
	var day_before: int = TimeManager.day
	bed.interact(player)
	await _frames(420)
	_check(TimeManager.day == day_before + 1 and quests.has_flag("town_morning"), "sleeping brings the morning and opens the quest (day %d -> %d)" % [day_before, TimeManager.day])
	_check(player.get_node_or_null("WakeScene") != null, "she wakes up in the bed")
	(player.get_node("WakeScene") as WakeScene)._finish()
	await _frames(10)
	_check(quests.has_flag("town_morning") and _step(player) == "town_valdric", "the morning opens the quest (%s)" % _step(player))
	var valdric: Settler = town.settler_node("valdric")
	_check(valdric != null and world.knight_taken and not town.residents.is_empty(), "Valdric lives in the town from its founding (the story's actor is put away)")
	var knight_at: Vector2 = valdric.actor_position("knight") if valdric != null else Vector2.INF
	_check(knight_at != Vector2.INF and quests.current().target == knight_at, "the quest marker follows Valdric")
	player.request_teleport(knight_at + Vector2(20, 10))
	await _frames(30)
	_check(_step(player) == "town_intro", "reaching Valdric starts the talk (%s)" % _step(player))
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	_check(box != null and box.is_active(), "the dialogue opens")
	box._end()
	await _frames(5)
	_check(quests.has_flag("town_intro_done") and player.inventory.has_item("sickle_basic") and player.inventory.has_item("pickaxe_basic"), "Valdric hands over the sickle and the pickaxe")
	_check(_step(player) == "build_lamp" and String(quests.current().hint) == "build", "next: a lamp post, with the build lesson (%s)" % _step(player))
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(90)
	player.inventory.give("wood", 40)
	player.inventory.give("glow_cap", 2)
	player.inventory.give("stone", 12)
	player.inventory.give("plant_fiber", 6)
	var lamp: Vector2 = _site(town, "lamp_post", hut.position + Vector2(50, 110))
	town.request_place("lamp_post", lamp, false)
	await _frames(240)
	_check(town.has_built("lamp_post") and quests.has_flag("built_lamp_post"), "the lamp post is built")
	_check(_step(player) == "build_workshop", "next: the workshop (%s)" % _step(player))
	var shop: Vector2 = _site(town, "workshop", hut.position + Vector2(0, 130))
	player.request_teleport(shop + Vector2(0, 40))
	await _frames(40)
	town.request_place("workshop", shop, false)
	await _frames(240)
	_check(town.has_built("workshop") and quests.has_flag("built_workshop"), "the workshop is built")
	_check(_step(player) == "meet_stranger", "and a stranger is on his way (%s)" % _step(player))
	for i: int in 900:
		await get_tree().process_frame
		if town.residents.has("gustav"):
			break
	_check(town.residents.has("gustav"), "Gustav walks into the light")
	var gustav: Settler = town.settler_node("gustav")
	_check(gustav != null and quests.current().target == gustav.global_position, "the marker follows him")
	player.request_teleport(gustav.global_position + Vector2(24, 10))
	await _frames(30)
	_check(_step(player) == "gustav_hello" or box.is_active(), "meeting him starts the conversation (%s)" % _step(player))
	box = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	_check(box != null and box.is_active(), "the dialogue opens")
	box._end()
	await _frames(5)
	_check(quests.has_flag("gustav_joined") and quests.is_finished("town_start"), "he moves in and the quest is done")
	_check(town.trust_of("gustav") == 10, "the first talk counts as the day's talk")
	_check(town.level() >= 1, "the town has grown to a hamlet (worth %s)" % town.worth())
	_check(valdric.plan_at(0.3).spot == "door" and valdric.plan_at(0.45).spot == "repair" and valdric.plan_at(0.6).spot == "practice" and valdric.plan_at(0.95).spot == "night" and valdric.plan_at(0.1).spot == "night", "Valdric has a day: door, repairs, fire, sword practice, guard, fire, night")
	_check(valdric.visible and valdric.prompt() == "ANSPRECHEN", "he can always be talked to")
	var lines: Dictionary = {}
	for i: int in 40:
		lines[valdric._chat_line(player)] = true
	_check(lines.size() >= 4 and not lines.has(""), "he says different things (%d)" % lines.size())
	quests.import_data({"active": {"town_start": 3}, "active_steps": {"town_start": "build_lamp"}, "done": [], "flags": {}})
	var about_lamp: bool = false
	for i: int in 60:
		about_lamp = about_lamp or valdric._chat_line(player).contains("Lichtpfosten")
	_check(about_lamp, "with a quest step he sometimes speaks about it")
	print("TOWN STORY: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
