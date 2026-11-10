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
	_check(BoardRules.story_due({"quest": "q", "flag": "flag_one"}, quests, finished, flagged) and not BoardRules.story_due({"quest": "q", "flag": "no"}, quests, finished, flagged), "flag: a set flag")


func _run() -> void:
	_rules()
	(TownRules.piece("lamp_post") as Dictionary)["build_seconds"] = 0.5
	(TownRules.piece("quest_board") as Dictionary)["build_seconds"] = 0.5
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
	player.inventory.give("wood", 60)
	player.inventory.give("plant_fiber", 20)
	player.inventory.give("glow_cap", 4)
	_check(not town.is_unlocked("quest_board"), "the board waits for the lamp post")
	var lamp_at: Vector2 = _find_site(town, "lamp_post", hut.position + Vector2(60, 100))
	town.request_place("lamp_post", lamp_at, false)
	await _frames(3)
	for i: int in 300:
		await get_tree().process_frame
		if town.has_built("lamp_post"):
			break
	_check(town.has_built("lamp_post") and town.is_unlocked("quest_board"), "the lamp post opens the board")
	_check(not town.board.is_ready(), "no board built yet: nothing may be posted")
	town.board._on_day_started(TimeManager.day + 1)
	_check(town.board.offers.is_empty(), "no notices without a built board")
	var at: Vector2 = _find_site(town, "quest_board", lamp_at + Vector2(0, 40))
	_check(at != Vector2.INF, "there is a free site for the board")
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
	town.add_story_resident("gustav")
	await _frames(3)
	_check(town.residents.has("gustav"), "Gustav lives in the town")
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
	var copper_before: int = player.progress.copper
	var xp_before: int = player.progress.xp
	var trust_before: int = town.trust_of("gustav")
	board.request_finish(fetch_id)
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
	_check(not bool(board.entry_of(hunt_id, peer).get("done", false)), "no hand-in before the hunt is done")
	for i: int in int(hunt.n) + 2:
		board.note_kill(player, "shadow_spider")
	_check(int(board.entry_of(hunt_id, peer).get("n", 0)) == int(hunt.n), "kills are capped at the goal")
	var hunt_copper: int = player.progress.copper
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
	board.request_accept(story_id)
	await _frames(3)
	_check(player.quests.is_active("board_test"), "taking a story notice starts the quest")
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
	# saving
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
	print("BOARD OK" if _ok else "BOARD FAILED")
	get_tree().quit(0 if _ok else 1)
