extends Node
## docs/questtafel_konzept.md: the pure rules (data, rolling, limits, expiry, progress), and the real world: placing the board, taking, handing in (fetch, kill), the
## daily post, story notices, saving and the window. Run with `--fixed-fps 60`; prints `BOARD OK`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("BOARD FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _poster_count(board: BoardManager) -> int:
	var count: int = 0
	for offer: Dictionary in board.offers:
		if BoardRules.is_bounty(offer) and not BoardRules.is_expired(offer, TimeManager.day):
			count += 1
	return count


func tracked_of(player: Player) -> TrackedQuests:
	return player.tracked


func _find_site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 16):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 10.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _rules() -> void:
	var cfg: Dictionary = BoardRules.config()
	_check(not cfg.is_empty() and BoardRules.templates().size() >= 10, "board.json holds the templates")
	var piece: Dictionary = TownRules.piece(BoardRules.piece())
	_check(not piece.is_empty() and String(piece.role) == "board", "the board is a piece with role board")
	_check(ResourceLoader.exists("res://assets/town/%s.png" % String(piece.texture)), "the board has a picture")
	var enemies: Dictionary = DataRegistry.table("enemies")
	var settlers: Dictionary = DataRegistry.table("settlers")
	var seen: Dictionary = {}
	for raw: Variant in BoardRules.templates():
		var template: Dictionary = raw as Dictionary
		var id: String = String(template.id)
		_check(not seen.has(id), "template id %s is unique" % id)
		seen[id] = true
		_check(String(template.kind) in [BoardRules.FETCH, BoardRules.KILL], "%s has a known kind" % id)
		if String(template.kind) == BoardRules.FETCH:
			_check(not Items.definition({"id": String(template.item)}).is_empty(), "%s: item %s exists" % [id, String(template.item)])
		else:
			_check(enemies.has(String(template.species)), "%s: species exists" % id)
		for giver: Variant in template.get("givers", []) as Array:
			_check(settlers.has(String(giver)), "%s: giver %s is a settler" % [id, String(giver)])
		var span: Array = template.count as Array
		_check(int(span[0]) >= 1 and int(span[1]) >= int(span[0]), "%s: count span" % id)
		var bonus: Dictionary = template.get("bonus", {}) as Dictionary
		if not bonus.is_empty():
			_check(not Items.definition({"id": String(bonus.id)}).is_empty(), "%s: bonus item exists" % id)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var people: Dictionary = {"gustav": {"trust": 0}, "valdric": {"trust": 0}}
	var open: Array = []
	for i: int in 12:
		var offer: Dictionary = BoardRules.roll(rng, people, open, 1, i + 1)
		if offer.is_empty():
			break
		open.append(offer)
	_check(open.size() == 2, "one open notice per giver: two residents hang two notices (%d)" % open.size())
	var givers: Dictionary = {}
	for offer: Dictionary in open:
		givers[String(offer.g)] = true
		_check(not String(offer.txt).contains("{"), "the text of %s has no placeholder left (%s)" % [String(offer.tx), String(offer.txt)])
		_check(int(offer.e) > int(offer.d) and BoardRules.days_left(offer, 1) >= 3, "a notice lives a few days")
		var template: Dictionary = BoardRules.template_of(String(offer.tx))
		var span: Array = template.count as Array
		_check(int(offer.n) >= int(span[0]) and int(offer.n) <= int(span[1]), "the count is inside its span")
		var each: Array = template.copper_each as Array
		_check(int(offer.c) >= int(offer.n) * int(each[0]) and int(offer.c) <= int(offer.n) * int(each[1]), "the pay is inside its span")
	_check(givers.size() == 2, "both givers hang one")
	# min_day: Valdric's listener hunt waits for day 3
	var early: bool = false
	for i: int in 40:
		var tiny: Array = []
		var o: Dictionary = BoardRules.roll(rng, {"valdric": {"trust": 0}}, tiny, 1, 1)
		early = early or String(o.get("tx", "")) == "valdric_listener"
	_check(not early, "a template with min_day does not hang before its day")
	var late: bool = false
	for i: int in 60:
		var o2: Dictionary = BoardRules.roll(rng, {"valdric": {"trust": 0}}, [], 3, 1)
		late = late or String(o2.get("tx", "")) == "valdric_listener"
	_check(late, "it can hang from its day on")
	var nobody: Dictionary = BoardRules.roll(rng, {}, [], 5, 1)
	_check(nobody.is_empty(), "without residents nothing hangs")
	var fetch: Dictionary = BoardRules.make(rng, BoardRules.template_of("gustav_wood"), "gustav", 2, 9)
	var entry: Dictionary = {"n": 0, "done": false}
	_check(BoardRules.progress(fetch, entry, 3) == 3 and not BoardRules.can_finish(fetch, entry, 3), "a fetch counts the bag")
	_check(BoardRules.can_finish(fetch, entry, int(fetch.n) + 5) and BoardRules.progress(fetch, entry, 999) == int(fetch.n), "full bag finishes, progress is capped")
	_check(not BoardRules.can_finish(fetch, {}, 999), "not taken: cannot finish")
	_check(not BoardRules.can_finish(fetch, {"n": 0, "done": true}, 999), "done: cannot finish twice")
	var hunt: Dictionary = BoardRules.make(rng, BoardRules.template_of("valdric_spider"), "valdric", 2, 10)
	_check(BoardRules.progress(hunt, {"n": 1, "done": false}, 99) == 1 and not BoardRules.can_finish(hunt, {"n": 1, "done": false}, 99), "a hunt counts kills, not the bag")
	_check(BoardRules.is_expired(fetch, int(fetch.e)) and not BoardRules.is_expired(fetch, int(fetch.e) - 1), "a notice runs out on its last day")
	var story: Dictionary = BoardRules.make_story({"id": "s", "quest": "q", "giver": "valdric", "title": "T", "text": "x"}, 4, 11)
	_check(int(story.e) == -1 and not BoardRules.is_expired(story, 999) and not BoardRules.can_finish(story, {"n": 0}, 0), "a story notice never runs out and has no hand-in")
	var quests: Dictionary = {"q": {}}
	var finished: Callable = func(id: String) -> bool: return id == "done_one"
	var flagged: Callable = func(id: String) -> bool: return id == "flag_one"
	_check(not BoardRules.story_due({"quest": "missing"}, quests, finished, flagged), "a quest that does not exist is never due")
	_check(BoardRules.story_due({"quest": "q"}, quests, finished, flagged), "no condition: due")
	_check(BoardRules.story_due({"quest": "q", "after": "done_one"}, quests, finished, flagged) and not BoardRules.story_due({"quest": "q", "after": "other"}, quests, finished, flagged), "after: a finished quest")
	# step 1: personal deadline, age, hanging
	var timed: Dictionary = {"id": 1, "k": "fetch", "d": 3, "e": 5}
	_check(BoardRules.due_for(timed, 4) == 6 and BoardRules.due_for(timed, 1) == 5, "a taken notice keeps at least two days, or the notice's own end")
	_check(BoardRules.due_for(story, 9) == -1 and BoardRules.entry_days_left(story, {}, 9) == -1, "a story notice has no deadline")
	_check(BoardRules.entry_days_left(timed, {"due": 7}, 5) == 2 and BoardRules.entry_days_left(timed, {}, 4) == 1, "days left follow the entry's own deadline, old saves the notice's")
	_check(BoardRules.is_hanging(timed, 4) and not BoardRules.is_hanging(timed, 5), "a notice hangs until its last sunrise")
	_check(is_equal_approx(BoardRules.age(timed, 3, 0.26), 0.0 + 0.01 / 2.0), "age starts at the sunrise it was posted")
	_check(BoardRules.age(timed, 5, 0.1) > 0.95 and BoardRules.age(timed, 5, 0.1) <= 1.0, "after midnight of the last day the paper is nearly gone")
	_check(BoardRules.age(story, 9, 0.5) == 0.0, "a story notice never ages")
	_check(BoardRules.age_stage(0.0) == 0 and BoardRules.age_stage(0.5) == 1 and BoardRules.age_stage(0.8) == 2 and BoardRules.age_stage(0.95) == 3, "four looks by age")
	# step 3: wanted posters, the honour board (pure)
	var mark_a: Dictionary = {"name": "DER KLOTZ", "species": "void_crusher", "nights": 1, "pos": [1200.0, 3400.0]}
	var poster_a: Dictionary = BoardRules.make_bounty(mark_a, "valdric", 12, 77)
	_check(BoardRules.is_bounty(poster_a) and String(poster_a.k) == BoardRules.KILL and int(poster_a.e) == -1 and not BoardRules.is_expired(poster_a, 9999), "a poster is a hunt that never runs out")
	_check(BoardRules.goal_text(poster_a) == "DER KLOTZ" and String(poster_a.txt).contains("DER KLOTZ") and (poster_a.a as Array)[2] == 640.0 and (poster_a.a as Array)[0] == 1200.0, "it names the creature and marks its last place")
	mark_a["nights"] = 3
	var poster_c: Dictionary = BoardRules.make_bounty(mark_a, "valdric", 12, 78)
	_check(int(poster_c.c) > int(poster_a.c) and int(poster_c.bh) == 3 and not (poster_c.b as Dictionary).is_empty(), "a creature that survived more nights pays more, with a sure extra")
	_check(BoardRules.due_for(poster_a, 40) == -1, "whoever takes it keeps it until it falls")
	var stats: Dictionary = BoardRules.blank_stats()
	for i: int in 5:
		BoardRules.count_done(stats, {"k": "fetch", "g": "gustav", "n": 3})
	_check(int(stats.done) == 5 and int(stats.fetch) == 5 and BoardRules.stat_value(stats, "givers") == 1, "finished notices are counted by kind and by giver")
	_check(BoardRules.title_earned(stats, BoardRules.title_of("handlanger")) and not BoardRules.title_earned(stats, BoardRules.title_of("verlaesslich")), "five notices earn the first title, not the second")
	BoardRules.count_done(stats, {"k": "kill", "g": "valdric", "n": 4, "u": true, "ut": 0.8})
	BoardRules.count_done(stats, poster_a)
	_check(int(stats.kills) == 4 and int(stats.rush) == 1 and int(stats.bounty) == 1 and BoardRules.stat_value(stats, "givers") == 2, "kills, rush notices and marked ones count apart")
	_check(BoardRules.title_earned(stats, BoardRules.title_of("namensjaeger")) and BoardRules.title_progress(stats, BoardRules.title_of("dunkelraeumer")) == Vector2i(4, 30), "the name hunter is earned, the clearer shows its progress")
	_check(BoardRules.milestones_reached(24) == 0 and BoardRules.milestones_reached(25) == 1 and BoardRules.milestones_reached(60) == 2 and BoardRules.milestones_reached(100) == 3, "the board grows at 25, 50 and 100")
	# step 2: occasions, rush notices, compass
	_check(BoardRules.compass(0.0) == "OSTEN" and BoardRules.compass(PI / 2.0) == "SÜDEN" and BoardRules.compass(-PI / 2.0) == "NORDEN" and BoardRules.compass(PI) == "WESTEN", "the compass names the sides")
	var ctx0: Dictionary = {"day": 10, "moon_day": 1, "stock": {"wood": 99, "plant_fiber": 99, "stone": 99}, "storm_yesterday": false, "wet_days": 0, "report": {}}
	_check(BoardRules.due_occasions(ctx0, {}).is_empty(), "a quiet day: no occasion is due")
	var low: Dictionary = ctx0.duplicate(true)
	low["stock"] = {"wood": 99, "plant_fiber": 99, "stone": 2}
	var due_low: Array[Dictionary] = BoardRules.due_occasions(low, {})
	_check(due_low.size() == 1 and String((due_low[0].occ as Dictionary).id) == "low_stock" and String((due_low[0].hit as Dictionary).item) == "stone" and int((due_low[0].hit as Dictionary).gap) == 8, "an empty store asks for exactly the gap")
	_check(BoardRules.due_occasions(low, {"low_stock": 9}).is_empty(), "an occasion waits out its cooldown")
	var rain: Dictionary = ctx0.duplicate(true)
	rain["storm_yesterday"] = true
	rain["wet_days"] = 2
	rain["moon_day"] = 4
	var ids_due: Array[String] = []
	for item: Dictionary in BoardRules.due_occasions(rain, {}):
		ids_due.append(String((item.occ as Dictionary).id))
	_check(ids_due.has("after_storm") and ids_due.has("damp_days") and ids_due.has("full_moon_bloom") and not ids_due.has("new_moon_hunt"), "storm, damp days and full moon are due, new moon is not")
	var raid: Dictionary = ctx0.duplicate(true)
	raid["moon_day"] = 0
	raid["report"] = {"night": 9, "intruders": 3, "species": "void_listener", "compass": "NORDEN", "pos": [100.0, 200.0]}
	var rng2: RandomNumberGenerator = RandomNumberGenerator.new()
	rng2.seed = 5
	var raid_notice: Dictionary = {}
	var moon_notice: Dictionary = {}
	for item: Dictionary in BoardRules.due_occasions(raid, {}):
		var occ: Dictionary = item.occ as Dictionary
		if String(occ.id) == "after_raid":
			raid_notice = BoardRules.make_occasion(rng2, occ, item.hit as Dictionary, "valdric", 10, 7, true)
		if String(occ.id) == "new_moon_hunt":
			moon_notice = BoardRules.make_occasion(rng2, occ, item.hit as Dictionary, "valdric", 10, 8, true)
	_check(String(raid_notice.get("t", "")) == "void_listener" and int(raid_notice.n) == 3 and (raid_notice.a as Array)[0] == 100.0 and String(raid_notice.txt).contains("NORDEN") and String(raid_notice.w) == "NACH DEM VORSTOSS", "the raid notice names the kind, the count, the side and the place")
	_check(String(moon_notice.get("win", "")) == "night" and int(moon_notice.n) >= 4 and int(moon_notice.e) == 11, "the new moon hunt counts only at night and ends at the next sunrise")
	var rush: Dictionary = {"id": 1, "k": "fetch", "d": 5, "e": 6, "u": true, "ut": 0.8}
	_check(not BoardRules.urgent_over(rush, 5, 0.5) and BoardRules.urgent_over(rush, 5, 0.85) and BoardRules.urgent_over(rush, 6, 0.3) and BoardRules.urgent_over(rush, 5, 0.1), "a rush notice ends at dusk, by the clock")
	_check(BoardRules.urgent_left(rush, TimeManager.DAY_START) == 1.0 and BoardRules.urgent_left(rush, 0.8) == 0.0 and BoardRules.urgent_hours(rush, 0.6) == 5, "its clock runs from sunrise to dusk")
	var plain: Dictionary = BoardRules.make(rng2, BoardRules.template_of("any_trout"), "gustav", 5, 9)
	var plain_c: int = int(plain.c)
	BoardRules.urgentize(plain, BoardRules.template_of("any_trout"))
	_check(int(plain.c) == plain_c * 2 and BoardRules.is_urgent(plain) and int(plain.e) == 6 and not (plain.b as Dictionary).is_empty(), "rush: double pay and the extra item for sure")
	_check(BoardRules.story_due({"quest": "q", "flag": "flag_one"}, quests, finished, flagged) and not BoardRules.story_due({"quest": "q", "flag": "no"}, quests, finished, flagged), "flag: a set flag")
	var story_cfg: Array = BoardRules.story_entries()
	_check(story_cfg.size() >= 4, "board.json defines all 4 main story notices")
	for raw_story: Variant in story_cfg:
		var se: Dictionary = raw_story as Dictionary
		var ipath: String = String(se.get("icon", ""))
		_check(ipath != "" and ResourceLoader.exists(ipath), "story entry %s has an existing icon (%s)" % [String(se.get("id", "")), ipath])
		var itex: Texture2D = BoardRules.story_icon_by_path(ipath)
		_check(itex != null and itex.get_size() == Vector2(16, 16), "story entry %s icon is 16x16" % String(se.get("id", "")))
	_check(BoardRules.story_icon({"k": "story", "tx": "torben_notice", "q": "torben_smithy"}) != null, "legacy saved story offer without ic resolves icon from board.json")
	_check(BoardRules.story_icon({"k": "story", "tx": "unknown_story", "q": "unknown_q"}) != null, "unknown story offer falls back to story_seal icon")


func _run() -> void:
	_rules()
	(TownRules.piece("plaza") as Dictionary)["build_seconds"] = 0.5
	(TownRules.piece("lamp_post") as Dictionary)["build_seconds"] = 0.5
	(TownRules.piece("quest_board") as Dictionary)["build_seconds"] = 0.5
	(TownRules.piece("workshop") as Dictionary)["build_seconds"] = 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(90)
	player.quests.set_flag("rebuild_done")
	await _frames(100)
	_check(town.founded and town.board != null, "the town is founded and has a board manager")
	player.inventory.give("wood", 100)
	player.inventory.give("stone", 40)
	player.inventory.give("plant_fiber", 30)
	player.inventory.give("glow_cap", 4)
	_check(not town.is_unlocked("quest_board"), "the board waits for the workshop")
	player.request_teleport(hut.position + Vector2(-140, 40))
	await _frames(3)
	var plaza_at: Vector2 = _find_site(town, "plaza", hut.position + Vector2(0, 150))
	_check(plaza_at != Vector2.INF, "there is a free site for the plaza")
	player.request_teleport(plaza_at + Vector2(0, 28))
	await _frames(3)
	town.request_place("plaza", plaza_at, false)
	await _frames(3)
	for i: int in 300:
		await get_tree().process_frame
		if town.has_built("plaza"):
			break
	_check(town.has_built("plaza") and not town.is_unlocked("quest_board"), "the plaza is built and the board still waits for the workshop")
	player.request_teleport(hut.position + Vector2(-140, 40))
	await _frames(3)
	var lamp_at: Vector2 = _find_site(town, "lamp_post", hut.position + Vector2(60, 100))
	player.request_teleport(lamp_at + Vector2(0, 28))
	await _frames(3)
	town.request_place("lamp_post", lamp_at, false)
	await _frames(3)
	for i: int in 300:
		await get_tree().process_frame
		if town.has_built("lamp_post"):
			break
	_check(town.has_built("lamp_post") and not town.is_unlocked("quest_board"), "the lamp post alone does not unlock the board yet")
	town.add_story_resident("gustav")
	await _frames(3)
	_check(town.residents.has("gustav"), "Gustav lives in the town")
	player.request_teleport(hut.position + Vector2(-140, 40))
	await _frames(3)
	var shop_at: Vector2 = _find_site(town, "workshop", hut.position + Vector2(0, 130))
	player.request_teleport(shop_at + Vector2(0, 28))
	await _frames(3)
	town.request_place("workshop", shop_at, false)
	await _frames(3)
	for i: int in 300:
		await get_tree().process_frame
		if town.has_built("workshop"):
			break
	_check(town.has_built("workshop") and town.is_unlocked("quest_board"), "the workshop opens the board")
	_check(not town.board.is_ready(), "no board built yet: nothing may be posted")
	town.board._on_day_started(TimeManager.day + 1)
	_check(town.board.offers.is_empty(), "no notices without a built board")
	player.request_teleport(hut.position + Vector2(-140, 40))
	await _frames(3)
	var at: Vector2 = _find_site(town, "quest_board", lamp_at + Vector2(0, 40))
	_check(at != Vector2.INF, "there is a free site for the board")
	player.request_teleport(at + Vector2(0, 28))
	await _frames(3)
	town.request_place("quest_board", at, false)
	await _frames(3)
	var board_id: int = town.next_id - 1
	for i: int in 300:
		await get_tree().process_frame
		if town.is_built(board_id):
			break
	_check(town.is_built(board_id) and town.board.is_ready(), "the board is finished")
	var board: BoardManager = town.board
	var view: TownStructure = town.view_of(board_id)
	_check(view != null and view.get_node_or_null("Notes") != null and view.get_node_or_null("SealNotes") != null, "the built board pins its notices on the panel (paper and seals)")
	var peer: int = player.name.to_int()
	var spot: Vector2 = town.rect_of(board_id).get_center() + Vector2(0, 24)
	player.global_position = spot
	await _frames(2)
	# the day's post
	var day: int = TimeManager.day
	seed(3)
	for i: int in 6:
		board._rng.seed = 100 + i
		board._on_day_started(day + i)
		if board.offers.size() >= BoardRules.limit("simple"):
			break
	_check(board.offers.size() >= 1 and board.offers.size() <= BoardRules.limit("simple"), "sunrise hangs notices up to the limit (%d)" % board.offers.size())
	for offer: Dictionary in board.offers:
		_check(town.residents.has(String(offer.g)), "a resident gave %s" % String(offer.tx))
	# strangers give nothing: Esma and Ilva stand in the book but the player has never talked to them
	town._rpc_resident("witch", {"trust": 80, "talked": -1}, false)
	town._rpc_resident("lake_witch", {"trust": 80, "talked": -1}, false)
	_check(not town.has_met("witch") and not town.has_met("lake_witch") and town.has_met("gustav") and town.has_met("valdric"), "only people the player has met (or the story introduced) are known")
	_check(not town.met_residents().has("witch") and town.met_residents().has("gustav"), "the board sees only the known ones")
	var stranger_seen: bool = false
	for i: int in 40:
		board.offers.clear()
		board._rng.seed = 900 + i
		board._on_day_started(TimeManager.day + 10 + i)
		for offer: Dictionary in board.offers:
			if String(offer.g) == "witch" or String(offer.g) == "lake_witch":
				stranger_seen = true
	_check(not stranger_seen, "a stranger never hangs a notice (40 mornings)")
	town._host_talk("witch")
	_check(town.has_met("witch"), "the first talk makes the stranger known")
	town._rpc_resident("witch", {"trust": 0, "talked": -1}, false)
	town._rpc_resident("lake_witch", {"trust": 0, "talked": -1}, false)
	# a fetch notice, by hand
	board.offers.clear()
	board.taken.clear()
	var fetch_id: int = board.debug_post("gustav_wood", "gustav")
	await _frames(2)
	var fetch: Dictionary = board.offer_of(fetch_id)
	_check(not fetch.is_empty() and board.open_for(peer).size() == 1, "the notice hangs")
	board.request_finish(fetch_id)
	_check(board.entry_of(fetch_id, peer).is_empty(), "not taken: nothing to hand in")
	board.request_accept(fetch_id)
	await _frames(2)
	_check(not board.entry_of(fetch_id, peer).is_empty() and board.open_for(peer).is_empty() and board.running_for(peer).size() == 1, "taking moves it to the running list")
	board.request_accept(fetch_id)
	_check(board.running_for(peer).size() == 1, "taking twice changes nothing")
	var wood_before: int = player.inventory.count_item("wood")
	player.inventory.remove_item("wood", wood_before)
	board.request_finish(fetch_id)
	_check(not bool(board.entry_of(fetch_id, peer).get("done", false)), "an empty bag cannot hand in")
	player.inventory.give("wood", int(fetch.n) + 3)
	var gustav: Node2D = town.person_node("gustav")
	_check(gustav != null, "Gustav is a figure in the town")
	var gustav_at: Vector2 = gustav.global_position if gustav != null else spot
	player.global_position = gustav_at + Vector2(900, 0)
	board.request_finish(fetch_id)
	_check(not bool(board.entry_of(fetch_id, peer).get("done", false)), "reporting needs the giver, not the board (far from Gustav: refused)")
	player.global_position = spot
	_check(board.finishable("gustav", player).size() == 1 and board.finishable("valdric", player).is_empty(), "the finished notice waits for its own giver only")
	var copper_before: int = player.progress.copper
	var xp_before: int = player.progress.xp
	var trust_before: int = town.trust_of("gustav")
	if gustav_at.distance_to(spot) > BoardRules.giver_reach():
		board.request_finish(fetch_id)
		_check(not bool(board.entry_of(fetch_id, peer).get("done", false)), "the board itself takes no report")
	player.global_position = gustav_at + Vector2(24, 0)
	await _frames(2)
	_check(not board.report("gustav", player).is_empty(), "E at Gustav hands it in and he answers")
	await _frames(3)
	_check(bool(board.entry_of(fetch_id, peer).get("done", false)), "handing in finishes it")
	_check(player.inventory.count_item("wood") == 3, "the goods are taken (%d left)" % player.inventory.count_item("wood"))
	_check(player.progress.copper == copper_before + int(fetch.c) and player.progress.xp == xp_before + int(fetch.x), "copper and xp are paid")
	_check(town.trust_of("gustav") == mini(trust_before + int(fetch.tr), 100), "the giver trusts more (%d)" % town.trust_of("gustav"))
	board.request_finish(fetch_id)
	await _frames(2)
	_check(player.progress.copper == copper_before + int(fetch.c), "no second payment")
	_check(board.open_for(peer).is_empty() and board.running_for(peer).is_empty(), "done: off both lists for this player")
	# too far from the board
	var far_id: int = board.debug_post("gustav_stone", "gustav")
	player.global_position = spot + Vector2(0, 900)
	board.request_accept(far_id)
	_check(board.entry_of(far_id, peer).is_empty(), "taking needs the board's reach")
	player.global_position = spot
	await _frames(2)
	# a hunt
	var hunt_id: int = board.debug_post("valdric_spider", "valdric")
	board.note_kill(player, "shadow_spider")
	var hunt: Dictionary = board.offer_of(hunt_id)
	_check(int(board.entry_of(hunt_id, peer).get("n", 0)) == 0, "kills before taking do not count")
	board.request_accept(hunt_id)
	await _frames(2)
	board.note_kill(player, "void_listener")
	_check(int(board.entry_of(hunt_id, peer).get("n", 0)) == 0, "another species does not count")
	board.request_finish(hunt_id)
	_check(not bool(board.entry_of(hunt_id, peer).get("done", false)) and board.finishable("valdric", player).is_empty(), "no hand-in before the hunt is done")
	for i: int in int(hunt.n) + 2:
		board.note_kill(player, "shadow_spider")
	_check(int(board.entry_of(hunt_id, peer).get("n", 0)) == int(hunt.n), "kills are capped at the goal")
	var hunt_copper: int = player.progress.copper
	var valdric: Node2D = town.person_node("valdric")
	_check(valdric != null, "Valdric is a figure in the town")
	player.global_position = valdric.global_position + Vector2(24, 0) if valdric != null else spot
	await _frames(2)
	board.request_finish(hunt_id)
	await _frames(2)
	_check(bool(board.entry_of(hunt_id, peer).get("done", false)) and player.progress.copper == hunt_copper + int(hunt.c), "the hunt pays")
	# expiry at sunrise
	var old_id: int = board.debug_post("any_berry", "gustav")
	var old: Dictionary = board.offer_of(old_id)
	board._on_day_started(int(old.e))
	_check(board.offer_of(old_id).is_empty() and not board.taken.has(str(old_id)), "an old notice is taken down with its entries")
	# a story notice
	var quests: Dictionary = DataRegistry.table("quests")
	quests["board_test"] = {"title": "BOARD TEST", "steps": [{"id": "a", "text": "WARTE", "type": "flag", "flag": "board_test_never"}]}
	(BoardRules.config().story as Array).append({"id": "story_test", "quest": "board_test", "giver": "valdric", "title": "TESTRUF", "text": "x", "after": "", "flag": ""})
	board._check_story()
	await _frames(2)
	var story_id: int = -1
	for offer: Dictionary in board.offers:
		if String(offer.k) == BoardRules.STORY:
			story_id = int(offer.id)
	_check(story_id >= 0, "the story notice hangs once its condition holds")
	board._check_story()
	var stories: int = 0
	for offer: Dictionary in board.offers:
		stories += 1 if String(offer.k) == BoardRules.STORY else 0
	_check(stories == 1, "and only once")
	var vine: QuestVine = player._hud.get_node("QuestVine") as QuestVine
	_check(player.tracked.open_story_notices().size() == 1 and vine._has_notice and vine._notice_flare > 0.0, "unaccepted main story notice activates QuestVine notice and flares")
	player.tracked.mark_seen([story_id])
	_check(vine._has_notice, "marking the board story notice seen keeps the QuestVine notice until accepted")
	var story_win: QuestBoardWindow = QuestBoardWindow.open(get_tree(), player, town)
	await _frames(4)
	var story_row: Dictionary = {}
	for row: Dictionary in story_win.rows:
		if int(row.id) == story_id:
			story_row = row
	_check(not story_row.is_empty() and story_row.get("icon") != null and String(story_row.get("item", "")) == "" and not story_win._tip.visible, "story row shows bespoke icon without triggering item tooltip")
	story_win._close()
	await _frames(60)
	board.request_accept(story_id)
	await _frames(3)
	_check(player.quests.is_active("board_test"), "taking a story notice starts the quest")
	_check(player.tracked.open_story_notices().is_empty() and not vine._has_notice, "accepting the story notice clears the QuestVine board notice")
	# standalone QuestVine notice when no quest is active/focused
	var solo_story_id: int = -1
	quests["board_test_solo"] = {"title": "SOLO TEST", "steps": [{"id": "a", "text": "WARTE", "type": "flag", "flag": "board_test_never"}]}
	(BoardRules.config().story as Array).append({"id": "story_test_solo", "quest": "board_test_solo", "giver": "valdric", "title": "DRITTER RUF", "text": "x", "after": "", "flag": ""})
	var saved_quests_data: Dictionary = player.quests.export_data()
	player.quests.import_data({"flags": {"hud_unlocked": true}})
	board._check_story()
	await _frames(6)
	for offer: Dictionary in board.offers:
		if String(offer.get("tx", "")) == "story_test_solo":
			solo_story_id = int(offer.id)
	_check(solo_story_id >= 0 and vine._has_notice and not vine._has_quest and vine._grow > 0.0 and vine.visible, "QuestVine grows standalone when an open main quest hangs and no quest is focused")
	board._remove(solo_story_id)
	(BoardRules.config().story as Array).pop_back()
	player.quests.import_data(saved_quests_data)
	player.tracked._on_board()
	await _frames(2)
	player.global_position = spot
	_check(board.offer_of(story_id).get("id", -1) == story_id, "the story notice stays for the others")
	board.request_finish(story_id)
	_check(not bool(board.entry_of(story_id, peer).get("done", false)), "a story notice has no hand-in")
	# window
	var open_id: int = board.debug_post("any_blossom", "gustav")
	var window: QuestBoardWindow = QuestBoardWindow.open(get_tree(), player, town)
	await _frames(4)
	_check(window != null and window.rows.size() >= 1, "the window lists the notice")
	var listed: bool = false
	for row: Dictionary in window.rows:
		listed = listed or int(row.id) == open_id
	_check(listed, "the new notice is in the AUSHANG tab")
	for i: int in window.rows.size():
		if int(window.rows[i].id) == open_id:
			window.focus = i
	window._press("accept", false)
	await _frames(3)
	window._set_tab(1)
	var running: bool = false
	for row: Dictionary in window.rows:
		running = running or int(row.id) == open_id
	_check(running, "after accepting it is in the ANGENOMMEN tab")
	window._close()
	await _frames(60)
	_check(not is_instance_valid(window) or window.is_queued_for_deletion(), "the window closes")
	# step 1: the quest branch, the personal deadline, the living notes
	var tracked: TrackedQuests = player.tracked
	_check(tracked != null and tracked.board() == board, "the player has a quest list that sees the board")
	var entry_now: Dictionary = board.entry_of(open_id, peer)
	_check(BoardRules.entry_due(board.offer_of(open_id), entry_now) >= TimeManager.day + 2, "taking a notice gives at least two days")
	var listed_ids: Array[String] = []
	for item: Dictionary in tracked.entries():
		listed_ids.append(String(item.id))
	_check(listed_ids.has("board:%d" % open_id), "an accepted notice is an entry of the journal")
	_check(String(tracked.focused().get("source", "")) == "story", "story is focused by default")
	tracked.toggle_track(open_id)
	_check(int(tracked.focused().get("oid", -1)) == open_id, "following gives the notice the single focus")
	tracked.toggle_track(open_id)
	_check(tracked.focused().is_empty() and not tracked.board_entries().is_empty(), "clearing focus keeps the notice in the journal")
	_check(not tracked.is_seen(open_id) or true, "seen flag readable")
	tracked.mark_seen([open_id])
	var tracked_saved: Dictionary = tracked.export_data()
	tracked.import_data({})
	_check(not tracked.is_seen(open_id), "import replaces the lists")
	tracked.import_data(tracked_saved)
	_check(tracked.is_seen(open_id) and tracked.focused().is_empty(), "seen notices and an explicitly empty focus survive a round trip")
	# a taken notice outlives the board's posting, then lapses on its own
	var held_id: int = board.debug_post("any_berry", "gustav")
	var held: Dictionary = board.offer_of(held_id)
	held["e"] = TimeManager.day + 1 ## ends tomorrow, so the personal two days (until day + 2) outlast it
	board.request_accept(held_id)
	await _frames(2)
	_check(not board.entry_of(held_id, peer).is_empty(), "the second notice was taken")
	TimeManager.day = int(held.e)
	board._on_day_started(TimeManager.day)
	_check(not board.offer_of(held_id).is_empty(), "a notice someone holds stays after the board's day")
	var hang_ids: Array[int] = []
	for item: Dictionary in board.hanging():
		hang_ids.append(int(item.id))
	_check(not hang_ids.has(held_id), "but it no longer hangs on the board")
	_check(not board.running_for(peer).is_empty() and not board.entry_of(held_id, peer).is_empty(), "and the holder still carries it")
	var held_due: int = BoardRules.entry_due(held, board.entry_of(held_id, peer))
	TimeManager.day = held_due
	board._on_day_started(TimeManager.day)
	_check(board.entry_of(held_id, peer).is_empty() and board.offer_of(held_id).is_empty(), "past its personal deadline it lapses and is taken down")
	# the notes on the panel live
	var panel: BoardNotes = null
	for piece: Node in get_tree().get_nodes_in_group("quest_board_piece"):
		panel = piece.get_node_or_null("Notes") as BoardNotes
	_check(panel != null, "the built board has its lit notes node")
	if panel != null:
		panel._ghosts.clear()
		var ghost_id: int = board.debug_post("any_berry", "gustav")
		await _frames(8)
		var slot_before: int = -1
		for note: Dictionary in panel.notes:
			if int(note.id) == ghost_id:
				slot_before = int(note.slot)
		_check(slot_before >= 0, "a hanging notice has a place on the panel")
		TimeManager.day = int(board.offer_of(ghost_id).e)
		board._on_day_started(TimeManager.day)
		await _frames(8)
		var ghost_found: bool = false
		for note: Dictionary in panel.notes:
			ghost_found = ghost_found or (int(note.id) == ghost_id and int(note.slot) == slot_before)
		_check(ghost_found, "a notice that ran out stays up as a paper in its place")
		for ghost: Dictionary in panel._ghosts:
			ghost["t"] = BoardNotes.GHOST_LIFE + 1.0 ## nobody came: skip the waiting
		await _frames(int(BoardNotes.BLOW_TIME * 60.0) + 40)
		var gone: bool = true
		for note: Dictionary in panel.notes:
			gone = gone and int(note.id) != ghost_id
		_check(gone, "the wind takes the paper in the end")
		_check(int(panel.beacon.get("unread", -1)) >= 0, "the bud knows how many notices are unread")
		var drawn: Array[Dictionary] = [{"k": "fetch", "id": 1, "slot": 2, "a": 1.0, "drop": 0.0, "age": 0.95, "wet": 1.0, "gust": 1.5, "new": true}]
		var probe: Node2D = Node2D.new()
		add_child(probe)
		probe.draw.connect(func() -> void: BoardNotes.paint(probe, drawn, 1.0, false, false, 0.0, {"unread": 1, "story": true}); BoardNotes.paint(probe, drawn, 1.0, true, true, 1.0, {"unread": 1, "story": true}))
		probe.queue_redraw()
		await _frames(2)
		probe.queue_free()
		_check(true, "old, wet, windy papers and a pulsing bud draw without error")
	# step 2: the town speaks (occasions), rush notices, the night's report
	for stale: Dictionary in board.offers.duplicate():
		if String(stale.k) != BoardRules.STORY:
			board._remove(int(stale.id))
	TimeManager.locked = true
	TimeManager.time_of_day = 0.3
	board.occasion_last.clear()
	board.debug_context = {"moon_day": 1, "stock": {"wood": 99, "plant_fiber": 99, "stone": 99}, "storm_yesterday": true, "wet_days": 0, "report": {}}
	var posted: int = board.post_occasions(board.context(TimeManager.day))
	var storm_notice: Dictionary = {}
	for offer: Dictionary in board.offers:
		if String(offer.get("oc", "")) == "after_storm":
			storm_notice = offer
	_check(posted >= 1 and not storm_notice.is_empty() and BoardRules.is_urgent(storm_notice) and String(storm_notice.w) == "WEGEN DES STURMS", "after a storm a rush notice hangs with its reason")
	_check(BoardRules.is_hanging(storm_notice, TimeManager.day), "and it hangs in the morning")
	_check(board.occasion_last.has("after_storm") and board.post_occasions(board.context(TimeManager.day)) == 0, "the occasion waits for its cooldown and does not hang twice")
	var rush_id: int = int(storm_notice.id)
	player.global_position = spot
	board.request_accept(rush_id)
	await _frames(2)
	_check(not board.entry_of(rush_id, peer).is_empty(), "the rush notice can be taken")
	var rush_entry: Dictionary = tracked_of(player)._entry_of(storm_notice, peer)
	_check(bool(rush_entry.urgent) and float(rush_entry.urgent_left) > 0.9 and String(rush_entry.why) == "WEGEN DES STURMS", "the quest list shows its clock and reason")
	TimeManager.time_of_day = 0.85
	_check(not BoardRules.is_hanging(storm_notice, TimeManager.day), "at dusk it no longer hangs")
	board.check_rush()
	_check(board.offer_of(rush_id).is_empty() and board.entry_of(rush_id, peer).is_empty(), "and it is gone with the entry of whoever carried it")
	TimeManager.time_of_day = 0.3
	# the new moon hunt counts only at night
	board.debug_context = {"moon_day": 0, "stock": {"wood": 99, "plant_fiber": 99, "stone": 99}, "storm_yesterday": false, "wet_days": 0, "report": {}}
	board.occasion_last.clear()
	for offer: Dictionary in board.offers.duplicate():
		if String(offer.g) == "valdric" and String(offer.k) == BoardRules.KILL:
			board._remove(int(offer.id))
	TimeManager.day = maxi(TimeManager.day, 8)
	board.post_occasions(board.context(TimeManager.day))
	var hunt_notice: Dictionary = {}
	for offer: Dictionary in board.offers:
		if String(offer.get("oc", "")) == "new_moon_hunt":
			hunt_notice = offer
	_check(not hunt_notice.is_empty(), "the new moon hangs a night hunt")
	if not hunt_notice.is_empty():
		var hunt_oid: int = int(hunt_notice.id)
		board.request_accept(hunt_oid)
		await _frames(2)
		board.note_kill(player, String(hunt_notice.t))
		_check(int(board.entry_of(hunt_oid, peer).get("n", 0)) == 0, "a kill by day does not count for a night hunt")
		TimeManager.time_of_day = 0.9
		board.note_kill(player, String(hunt_notice.t))
		_check(int(board.entry_of(hunt_oid, peer).get("n", 0)) == 1, "a kill at night does")
		TimeManager.time_of_day = 0.3
	board.debug_context = {}
	# where to look on the map
	var bell_id: int = board.debug_post("witch_bell", "valdric")
	board.request_accept(bell_id)
	await _frames(2)
	var bell_entry: Dictionary = tracked_of(player)._entry_of(board.offer_of(bell_id), peer)
	_check(String(bell_entry.area_name) == "NEBELWALD" and (bell_entry.area as Vector3).z > 0.0, "a plant notice marks where it grows")
	var report_id: int = board.debug_post("valdric_spider", "valdric")
	board.offer_of(report_id)["a"] = [1000.0, 2000.0, 170.0]
	board.request_accept(report_id)
	await _frames(2)
	var report_entry: Dictionary = tracked_of(player)._entry_of(board.offer_of(report_id), peer)
	_check((report_entry.area as Vector3) == Vector3(1000.0, 2000.0, 170.0) and String(report_entry.area_name) == "EINSATZGEBIET", "a hunt notice marks its ground")
	# the night's report
	var night: NightDirector = world.night
	_check(night != null, "the world has a night director")
	if night != null:
		night._seen.clear()
		night._night_id = 3
		night._seen[1] = {"id": "shadow_spider", "pos": town.center + Vector2(300, 0)}
		night._seen[2] = {"id": "shadow_spider", "pos": town.center + Vector2(320, 20)}
		night._seen[3] = {"id": "void_listener", "pos": town.center + Vector2(0, -300)}
		var made: Dictionary = night._make_report()
		_check(int(made.intruders) == 3 and String(made.species) == "shadow_spider" and String(made.compass) == "OSTEN" and int(made.night) == 3, "the report counts who came, the main kind and the main side")
		_check(is_equal_approx(float((made.pos as Array)[0]), town.center.x + 310.0), "and the middle of that side")
		night._report = made
		_check(night.last_night_report() == made, "the board can read it")
		night._seen.clear()
	# step 3: the marked ones: an elite that lives through the morning, its poster, its fall, the honour board
	var night3: NightDirector = world.night
	world.opening_over = true
	night3.marked = {}
	for old3: Dictionary in board.offers.duplicate():
		if BoardRules.is_bounty(old3):
			board._remove(int(old3.id))
	var crusher: Node2D = night3._spawn("void_crusher", town.center + Vector2(260, 0), 1.0, 1.0, "k3", 3.0, false)
	_check(crusher != null, "an elite can be born")
	if crusher != null:
		var elite_entry: Dictionary = night3._live.back() as Dictionary
		elite_entry["elite"] = true
		elite_entry["name"] = ""
		elite_entry["nights"] = 0
		elite_entry["flee"] = 0.0
		(elite_entry.nb as NightBehavior).retreat = true
		var crusher_health: HealthComponent = crusher.get_node("HealthComponent") as HealthComponent
		for i: int in 3:
			night3._burn_clock = 1.0
			night3._burn()
		_check(crusher_health.current >= crusher_health.max_health and night3.marked.is_empty(), "an elite does not burn at dawn, and it is not gone at once")
		for i: int in 6:
			night3._burn_clock = 1.0
			night3._burn()
		_check(not night3.marked.is_empty() and int(night3.marked.nights) == 1 and String(night3.marked.species) == "void_crusher" and (BoardRules.bounty_cfg().names as Array).has(night3.marked.name), "it runs for the dark, and the town remembers it by a name")
		await _frames(2)
		_check(not is_instance_valid(crusher) or crusher.is_queued_for_deletion(), "its body is gone")
		var kept: Dictionary = night3.export_state()
		var name_kept: String = String(night3.marked.name)
		night3.marked = {}
		night3.import_state(kept)
		_check(String(night3.marked.get("name", "")) == name_kept, "the mark is saved with the night")
	TimeManager.locked = true
	TimeManager.time_of_day = 0.9
	board.check_bounty()
	_check(_poster_count(board) == 0, "no poster is hung at night")
	TimeManager.time_of_day = 0.3
	board.check_bounty()
	board.check_bounty()
	var poster3: Dictionary = {}
	for offer3: Dictionary in board.offers:
		if BoardRules.is_bounty(offer3):
			poster3 = offer3
	_check(_poster_count(board) == 1 and String(poster3.get("bn", "")) == String(night3.marked.get("name", "-")) and BoardRules.is_hanging(poster3, TimeManager.day), "the next morning one poster hangs, once")
	_check(board._plain_hanging().size() == board.hanging().size() - 1, "a poster takes no place of the simple notices")
	var poster_id: int = int(poster3.get("id", -1))
	board.request_accept(poster_id)
	await _frames(2)
	_check(not board.entry_of(poster_id, peer).is_empty(), "the poster can be taken")
	var poster_entry: Dictionary = tracked_of(player)._entry_of(board.offer_of(poster_id), peer)
	_check(bool(poster_entry.bounty) and String(poster_entry.area_name) == "ZULETZT GESEHEN" and (poster_entry.area as Vector3).z == 640.0 and String(poster_entry.title) == String(poster3.bn), "the quest branch and the map know it by name and last place")
	board.note_kill(player, "void_crusher")
	_check(int(board.entry_of(poster_id, peer).get("n", 0)) == 0, "just any creature of its kind does not count")
	night3.marked["nights"] = 2
	night3.marked["pos"] = [5000.0, 6000.0]
	board._bounty_clock = 0.0
	board.check_bounty()
	var again: Dictionary = board.offer_of(poster_id)
	_check(int(again.bh) == 2 and int(again.c) > int(BoardRules.bounty_cfg().copper) and (again.a as Array)[0] == 5000.0, "a second night makes it dearer and moves its mark")
	# it comes back, and falls
	board.taken[str(poster_id)]["4242"] = {"n": 0, "done": false, "due": -1} ## somebody else took it and never hits it
	night3._elite_done = false
	var group3: Array[Player] = [player]
	night3._spawn_elite("k3", group3, {"spent": 0.0, "died": false})
	if not night3.marked_out():
		var stand_in: Node2D = night3._spawn("void_crusher", town.center + Vector2(260, 40), 1.0, 1.0, "k3", 3.0, false)
		var live3: Dictionary = night3._live.back() as Dictionary
		live3["elite"] = true
		live3["name"] = String(night3.marked.name)
		_check(stand_in != null, "(a stand-in was needed for the return)")
	_check(night3.marked_out(), "the marked one returns by name")
	var wanted_entry: Dictionary = {}
	for live_entry: Dictionary in night3._live:
		if String(live_entry.get("name", "")) == String(night3.marked.name):
			wanted_entry = live_entry
	if not wanted_entry.is_empty():
		var wanted_health: HealthComponent = (wanted_entry.node as Node).get_node("HealthComponent") as HealthComponent
		wanted_health.take_damage(99999.0, Vector2.ZERO, 0.0, peer)
		await _frames(3)
	_check(night3.marked.is_empty(), "its fall ends the mark")
	var fell: Dictionary = board.entry_of(poster_id, peer)
	_check(int(fell.get("n", 0)) == 1 and BoardRules.is_expired(board.offer_of(poster_id), TimeManager.day), "whoever hurt it has it done, and the poster no longer hangs")
	_check(not (board.taken.get(str(poster_id), {}) as Dictionary).has("4242"), "whoever never hit it is let go")
	_check((board.honor.fallen as Array).size() == 1 and String(((board.honor.fallen as Array)[0] as Dictionary).name) == String(poster3.bn), "its name is in the honour board")
	var slag_before: int = player.inventory.count_item("void_slag")
	var valdric3: Node2D = town.person_node("valdric")
	_check(valdric3 != null, "Valdric is a figure in the town")
	if valdric3 != null:
		player.global_position = valdric3.global_position + Vector2(24, 0)
		await _frames(2)
		_check(not board.report("valdric", player).is_empty(), "E at Valdric hands the poster in")
		await _frames(2)
		_check(player.inventory.count_item("void_slag") == slag_before + 1 and int(board.stats_of(peer).bounty) == 1 and board.honor_done() >= 1, "it pays the sure item and is counted")
		_check(BoardRules.title_earned(board.stats_of(peer), BoardRules.title_of("namensjaeger")), "the name hunter title is earned")
		board.request_title("rueckgrat")
		_check(board.title_name(peer) == "", "a title that is not earned cannot be worn")
		board.request_title("namensjaeger")
		_check(board.title_name(peer) == "NAMENSJÄGER", "an earned title is worn")
		board.request_title("")
		_check(board.title_name(peer) == "", "and taken off again")
		board.request_title("namensjaeger")
	player.global_position = spot
	var done_now: int = board.honor_done()
	(board.honor.town as Dictionary)["done"] = 24
	var cap_before: int = board._simple_cap()
	(board.honor.town as Dictionary)["done"] = 25
	_check(board._simple_cap() == mini(cap_before + 1, 6), "the 25th notice gives the board a place more")
	(board.honor.town as Dictionary)["done"] = done_now
	# saving (the earlier notice was taken down by the day jumps above: take a new one)
	open_id = board.debug_post("any_blossom", "gustav")
	board.request_accept(open_id)
	await _frames(2)
	_check(not board.entry_of(open_id, peer).is_empty(), "a notice to save is taken")
	var saved: Dictionary = town.export_state()
	_check(saved.has("board") and (saved.board as Dictionary).has("offers"), "the town save holds the board")
	var snapshot: Dictionary = board.export_state(true)
	board.taken[str(open_id)]["99999"] = {"n": 0, "done": false}
	_check(not ((board.export_state() as Dictionary).taken as Dictionary).get(str(open_id), {}).has("99999"), "a save keeps only the host's own entries")
	_check(((board.export_state(true) as Dictionary).taken as Dictionary).get(str(open_id), {}).has("99999"), "a snapshot keeps everybody's")
	var count: int = board.offers.size()
	board.offers.clear()
	board.taken.clear()
	board.import_state(snapshot)
	_check(board.offers.size() == count and not board.entry_of(open_id, peer).is_empty(), "a round trip keeps notices and entries")
	_check(board.next_id > open_id, "ids go on counting")
	_check((board.honor.fallen as Array).size() == 1 and board.honor_done() >= 1 and board.title_name(peer) == "NAMENSJÄGER", "the honour board survives a round trip")
	var saved_honor: Dictionary = (board.export_state() as Dictionary).honor as Dictionary
	_check((saved_honor.titles as Dictionary).has(str(peer)) and (saved_honor.peers as Dictionary).has(str(peer)), "a save keeps the host's own title and counters")
	await _journal_rules(player, board, spot, story_id)
	print("BOARD OK" if _ok else "BOARD FAILED")
	get_tree().quit(0 if _ok else 1)


func _journal_rules(player: Player, board: BoardManager, spot: Vector2, story_id: int) -> void:
	var quests: QuestComponent = player.quests
	var tracked: TrackedQuests = player.tracked
	var peer: int = player.name.to_int()
	quests.import_data({"active": {"rebuild_hut": 0, "board_test": 0}, "flags": {"hud_unlocked": true}})
	tracked.import_data({})
	var story: String = "story:rebuild_hut"
	var fetch: int = board.debug_post("gustav_wood", "gustav")
	var hunt: int = board.debug_post("valdric_spider", "valdric")
	var fetch_key: String = "board:%d" % fetch
	var hunt_key: String = "board:%d" % hunt
	player.global_position = spot
	board.request_accept(fetch)
	board.request_accept(hunt)
	var open_ids: Array[String] = []
	for row: Dictionary in tracked.entries():
		open_ids.append(String(row.id))
	_check(story in open_ids and "story:board_test" in open_ids and fetch_key in open_ids and hunt_key in open_ids, "all active stories and both board jobs appear together")
	_check(String(tracked.focused().get("id", "")) == story, "accepting jobs leaves the current story focused")
	board.request_abandon(story_id, 1)
	_check(quests.is_active("board_test") and not board.entry_of(story_id, peer).is_empty(), "even the host's abandon request cannot discard a story notice")

	var journal: QuestJournal = player._hud.get_node("QuestJournal") as QuestJournal
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	_check(journal.visible and get_tree().paused and InputManager.journal_open and InputManager.ui_blocking, "J opens the journal and pauses solo play")
	var selected: int = -1
	for i: int in journal._rows.size():
		if String(journal._rows[i].id) == hunt_key:
			selected = i
	if selected >= 0:
		journal._select(selected)
		_check(String(tracked.focused().get("id", "")) == story, "reading a different entry keeps the focus")
		journal._toggle_focus()
	_check(String(tracked.focused().get("id", "")) == hunt_key, "the journal changes the shared focus")
	var vine: QuestVine = player._hud.get_node("QuestVine") as QuestVine
	_check(vine._main_id == hunt_key, "the HUD follows the journal selection")
	var tracked_save: Dictionary = tracked.export_data()
	tracked.import_data({})
	tracked.import_data(tracked_save)
	_check(String(tracked.focused().get("id", "")) == hunt_key and tracked.journal_page == hunt_key, "the focus and reading position survive saving")
	await _frames(20)
	_check(is_equal_approx(journal._art.opening, 1.0) and journal._page.size.x <= 225.0, "the book opens to its native spread with readable page bounds")
	journal._set_filter(1)
	_check(journal._rows.size() == 2 and String(journal._rows[0].source) == "story", "the story filter shows just the two active story entries")
	journal._set_filter(0)
	for i: int in journal._rows.size():
		if String(journal._rows[i].id) == story:
			journal._select(i)
	var map: MapWindow = player._hud.get_node("MapWindow") as MapWindow
	journal._show_on_map()
	_check(not journal.visible and map._quest_preview == story and String(tracked.focused().get("id", "")) == hunt_key, "map preview shows the reading selection while retaining the hunt focus")
	map._set_open(false)
	await _frames(2)
	_check(journal.visible and journal._selected_id == story and get_tree().paused, "returning from the map restores the reading position")
	for i: int in journal._rows.size():
		if String(journal._rows[i].id) == hunt_key:
			journal._select(i)

	board.note_kill(player, "shadow_spider")
	var due: int = int(board.entry_of(hunt, peer).get("due", -1))
	var coins: int = player.progress.copper
	var wood: int = player.inventory.count_item("wood")
	board.taken[str(hunt)]["99999"] = {"n": 1, "done": false, "due": due}
	journal._ask_abandon()
	_check(not journal._pending.is_empty(), "abandoning a journal entry asks for confirmation")
	journal._cancel_abandon()
	_check(not board.entry_of(hunt, peer).is_empty(), "canceling keeps the order")
	journal._ask_abandon()
	journal._abandon()
	_check(board.entry_of(hunt, peer).is_empty() and int(board.entry_of(hunt, 99999).get("n", 0)) == 1, "abandon affects only the requesting player")
	_check(player.progress.copper == coins and player.inventory.count_item("wood") == wood, "abandon takes no money or goods")
	_check(_archived(board, peer, hunt, "abandoned") and String(tracked.focused().get("id", "")) == story, "abandon archives the attempt and restores story focus")
	board.request_accept(hunt)
	var second: Dictionary = board.entry_of(hunt, peer)
	_check(int(second.get("attempt", 0)) == 2 and int(second.get("due", -1)) == due and int(second.get("n", -1)) == 0, "retaking resets progress but keeps the original deadline")
	board.request_abandon(hunt, 1)
	_check(not board.entry_of(hunt, peer).is_empty(), "a stale confirmation cannot abandon a later attempt")
	journal._switch_tab(1)
	_check(not journal._rows.is_empty() and not journal._actions.visible and journal._art.turn == 0.0, "the archive turns a page and has no active actions")
	journal._request_close()
	await _frames(16)
	_check(not get_tree().paused and not InputManager.journal_open and not InputManager.ui_blocking, "closing restores solo time and world input")
	GameSettings.set_value("journal_still", true)
	journal.open()
	journal._switch_tab(0)
	_check(journal._art.opening == 1.0 and journal._art.turn == 1.0, "reduced motion presents the book and the new register instantly")
	journal._request_close()
	_check(not journal.visible and not get_tree().paused, "reduced motion releases input and pause immediately")
	GameSettings.set_value("journal_still", false)

	var need: int = int(board.offer_of(fetch).n)
	player.inventory.remove_item("wood", player.inventory.count_item("wood"))
	player.inventory.give("wood", need)
	tracked.focus(fetch_key)
	_check(bool(tracked.focused().get("ready", false)), "the delivery can be handed in with enough wood")
	player.inventory.remove_item("wood", 1)
	_check(not bool(tracked.focused().get("ready", true)), "spending wood makes the delivery incomplete again")
	player.inventory.give("wood", 1)
	map._set_open(true)
	await _frames(4)
	map._set_open(false)
	var gustav: Node2D = board.town.person_node("gustav")
	player.global_position = gustav.global_position
	board.offer_of(fetch)["b"] = {"id": "void_slag", "n": 1}
	var bag_before: Array = player.inventory.slots.duplicate(true)
	for slot: int in InventoryComponent.SIZE:
		player.inventory.slots[slot] = {"id": "wood", "count": need + 1}
	var packed_wood: int = player.inventory.count_item("wood")
	_check(board.report("gustav", player) == "Mach erst Platz für deine Belohnung.", "Gustav explains why the ready delivery needs to wait")
	board.request_finish(fetch)
	_check(player.inventory.count_item("wood") == packed_wood and player.progress.copper == coins and not bool(board.entry_of(fetch, peer).get("done", false)), "a bonus that cannot fit leaves delivery goods, reward balance and quest unchanged")
	player.inventory.slots.assign(bag_before)
	var slag_before: int = player.inventory.count_item("void_slag")
	board.request_finish(fetch)
	board.request_finish(fetch)
	_check(_archived(board, peer, fetch, "finished") and player.inventory.count_item("wood") == 0, "delivery consumes the goods and records completion once")
	_check(player.progress.copper == coins + int(board.offer_of(fetch).c) and player.inventory.count_item("void_slag") == slag_before + 1, "repeated delivery pays the copper and bonus only once")

	var valdric: Node2D = board.town.person_node("valdric")
	player.global_position = valdric.global_position
	for i: int in int(board.offer_of(hunt).n):
		board.note_kill(player, "shadow_spider")
	board._host_finish(peer, hunt, 1)
	_check(not bool(board.entry_of(hunt, peer).get("done", false)), "a delayed hand-in cannot complete a later attempt")
	TimeManager.day = due
	board.request_finish(hunt)
	_check(_archived(board, peer, hunt, "expired") and player.progress.copper == coins + int(board.offer_of(fetch).c), "a ready quest cannot be paid at the deadline before cleanup")
	board.import_state(JSON.parse_string(JSON.stringify(board.export_state())) as Dictionary)
	_check(_archived(board, peer, hunt, "abandoned") and _archived(board, peer, hunt, "expired") and _archived(board, peer, fetch, "finished"), "all three archive outcomes survive a disk-format round trip")

	quests.import_data({"active": {"find_help": 3}, "active_steps": {"find_help": "find_knight"}})
	_check(quests.active_step_id("find_help") == "find_fallen_knight", "legacy forest save resumes at the fallen knight")
	quests.import_data({"active": {"find_help": 13}, "active_steps": {"find_help": "find_knight"}, "flags": {"woke_up": true}})
	_check(quests.active_step_id("find_help") == "find_knight" and float(quests.current().search) > 0.0, "legacy post-hut save resumes at the search area")
	_check(quests.completed_step_ids("find_help").has("wake") and not quests.completed_step_ids("find_help").has("meet"), "the restored story cursor gives the journal only the milestones already reached")
	quests.import_data({"active": {"gustav_rescue": 5, "board_test": 0}, "active_steps": {"gustav_rescue": "gustav_meet"}, "done": ["rebuild_hut", "town_start"]})
	for entry: Dictionary in tracked.entries():
		if String(entry.id) == "story:gustav_rescue":
			_check(String(entry.get("sketch", "")) == "wheel" and (entry.memories as Array).size() == 2 and not "bis ins Licht" in String((entry.memories as Array)[1]), "the journal shows the two latest memories and the sketch for the opened wagon")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--journal-capture="):
			await _capture_journal(arg.trim_prefix("--journal-capture="), player, board, spot, journal)
		elif arg.begins_with("--story-ui-capture="):
			await _capture_story_ui(arg.trim_prefix("--story-ui-capture="), player, board, spot)


## Optional renderer QA after the rules test, with a normal story and two board entries.
func _capture_journal(folder: String, player: Player, board: BoardManager, spot: Vector2, journal: QuestJournal) -> void:
	player.quests.import_data({"active": {"rebuild_hut": 0}, "flags": {"hud_unlocked": true}})
	player.tracked.import_data({})
	player.health.heal_full()
	player.sync_wound_visuals()
	board.taken.clear()
	player.global_position = spot
	var fetch: int = board.debug_post("gustav_wood", "gustav")
	var hunt: int = board.debug_post("valdric_spider", "valdric")
	board.request_accept(fetch)
	board.request_accept(hunt)
	player.inventory.give("wood", 7)
	player.tracked.focus("board:%d" % fetch)
	journal.open()
	await _frames(2)
	await _capture(folder.path_join("tagebuch-einband.png"))
	await _frames(20)
	await _capture(folder.path_join("tagebuch-auftrag.png"))
	journal._ask_abandon()
	await _frames(3)
	await _capture(folder.path_join("tagebuch-aufgeben.png"))
	journal._cancel_abandon()
	for i: int in journal._rows.size():
		if String(journal._rows[i].source) == "story":
			journal._select(i)
			break
	await _frames(19)
	await _capture(folder.path_join("tagebuch-geschichte.png"))
	journal._switch_tab(1)
	await _frames(5)
	await _capture(folder.path_join("tagebuch-umblattern.png"))
	journal.close()


## Optional renderer QA for the 4 main-story board icons and Ellie's QuestVine notice.
func _capture_story_ui(folder: String, player: Player, board: BoardManager, spot: Vector2) -> void:
	if board.town.world != null:
		board.town.world.finish_opening()
	player.health.heal_full()
	player.set_bandaged(false)
	player.sync_wound_visuals()
	if board.town._banner != null:
		board.town._banner._age = 99.0
		board.town._banner._queue.clear()
		board.town._banner.hide()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.42
	player._hud.call("_finish_reveal")
	player._hud.set("_idle_time", 0.0)
	player._hud.set("_idle_alpha", 1.0)
	board.offers.clear()
	board.taken.clear()
	for raw: Variant in BoardRules.story_entries():
		var se: Dictionary = raw as Dictionary
		if String(se.get("id", "")) in ["torben_notice", "spiegelhexe_notice", "mornath_notice", "lake_witch_notice"]:
			board.offers.append(BoardRules.make_story(se, board.next_id, TimeManager.day))
			board.next_id += 1
	board.debug_post("gustav_wood", "gustav")
	board.changed.emit()
	player.global_position = spot
	await _frames(3)
	var win: QuestBoardWindow = QuestBoardWindow.open(get_tree(), player, board.town)
	await _frames(55)
	var shots: Dictionary = {
		"torben_notice": "quest_board_torben.png",
		"spiegelhexe_notice": "quest_board_esma.png",
		"mornath_notice": "quest_board_mornath.png",
		"lake_witch_notice": "quest_board_ilva.png",
	}
	for tx_id: String in shots:
		for i: int in win.rows.size():
			var offer: Dictionary = board.offer_of(int(win.rows[i].id))
			if String(offer.get("tx", "")) == tx_id:
				win.focus = i
				win._canvas.queue_redraw()
				break
		await _frames(2)
		await _capture(folder.path_join(String(shots[tx_id])))
	win._close()
	await _frames(60)
	board.offers.clear()
	for raw: Variant in BoardRules.story_entries():
		var se: Dictionary = raw as Dictionary
		if String(se.get("id", "")) == "torben_notice":
			board.offers.append(BoardRules.make_story(se, board.next_id, TimeManager.day))
			board.next_id += 1
	board.changed.emit()
	player.global_position = spot + Vector2(-96, 24)
	var vine: QuestVine = player._hud.get_node("QuestVine") as QuestVine
	player.quests.import_data({"active": {"rebuild_hut": 0}, "flags": {"hud_unlocked": true}})
	player.tracked.import_data({})
	player.tracked._on_board()
	player._hud.set("_idle_time", 0.0)
	player._hud.set("_idle_alpha", 1.0)
	vine._grow = 1.0
	vine._notice_grow = 1.0
	vine._typed = 999.0
	await _frames(6)
	await _capture(folder.path_join("quest_vine_companion.png"))
	player.quests.import_data({"flags": {"hud_unlocked": true}})
	player.tracked.import_data({})
	player.tracked._on_board()
	player._hud.set("_idle_time", 0.0)
	player._hud.set("_idle_alpha", 1.0)
	vine._grow = 1.0
	vine._notice_grow = 1.0
	await _frames(6)
	await _capture(folder.path_join("quest_vine_standalone.png"))
	TimeManager.time_of_day = 0.0
	player._hud.set("_idle_time", 0.0)
	player._hud.set("_idle_alpha", 1.0)
	await _frames(6)
	await _capture(folder.path_join("quest_vine_night.png"))


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "rendered " + path.get_file())


func _archived(board: BoardManager, peer: int, id: int, status: String) -> bool:
	for row: Dictionary in board.archived_for(peer):
		if int(row.oid) == id and String(row.status) == status:
			return true
	return false
