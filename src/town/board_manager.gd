class_name BoardManager
extends Node
## The state of the quest board (docs/questtafel_konzept.md): the notices that hang and who took which. One child of the `TownManager` (`town.board`), created in the
## same place on every peer so the RPCs find each other. The host decides (rolling new notices at sunrise, taking, counting kills, paying), everyone mirrors; the whole
## table travels in the town's snapshot (`export_state` / `import_state`) and is saved with it. Rules without nodes: `BoardRules`. The window: `QuestBoardWindow`.
## `taken`: notice id (String) -> {peer id (String) -> {n: kills so far, done}}. Peer ids are not stable between sessions, so only the host's own entries are saved.

signal changed ## the table changed on this peer (a notice came or went, somebody took or finished one)
signal result(text: String, good: bool) ## the answer to the local player's request

var town: TownManager
var offers: Array[Dictionary] = []
var taken: Dictionary = {}
var next_id: int = 1
var _story_posted: Dictionary = {} ## story entry id -> true
var _story_clock: float = 0.0
var _urgent_clock: float = 0.0
var occasion_last: Dictionary = {} ## occasion id -> day it was posted last (the cooldowns; saved)
var debug_context: Dictionary = {} ## tests: keys put over the day's context
var honor: Dictionary = {"town": {}, "peers": {}, "titles": {}, "fallen": []} ## the honour board (saved): the town's counters, each player's, their chosen title, the names of the marked ones that fell
var _night_hooked: bool = false
var _bounty_clock: float = 0.0
var _bounty_sent: Vector2 = Vector2.INF ## the last place of the marked one that went out to the peers
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(owner_town: TownManager) -> void:
	town = owner_town
	_rng.randomize()
	if multiplayer.is_server():
		TimeManager.day_started.connect(_on_day_started)


func _exit_tree() -> void:
	if TimeManager.day_started.is_connected(_on_day_started):
		TimeManager.day_started.disconnect(_on_day_started)


# ---------- questions ----------

## Is there a finished board in the town? Without one nothing is posted and nothing can be taken.
func is_ready() -> bool:
	return town != null and town.founded and town.has_built(BoardRules.piece())


func offer_of(id: int) -> Dictionary:
	for offer: Dictionary in offers:
		if int(offer.id) == id:
			return offer
	return {}


func entry_of(id: int, peer: int) -> Dictionary:
	return ((taken.get(str(id), {}) as Dictionary).get(str(peer), {}) as Dictionary)


## What the bag of `player` holds for a fetch notice (0 for the other kinds).
func have_of(offer: Dictionary, player: Player) -> int:
	return player.inventory.count_item(String(offer.t)) if String(offer.k) == BoardRules.FETCH and player != null else 0


## Notices hanging that the player has not taken yet (a finished or running one is not listed: it is under `running_for` or gone; one that has run out is only held by
## those who took it and no longer hangs).
func open_for(peer: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Dictionary in offers:
		if BoardRules.is_hanging(offer, TimeManager.day) and entry_of(int(offer.id), peer).is_empty():
			out.append(offer)
	return out


## Notices that hang on the board right now (the panel shows these).
func hanging() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Dictionary in offers:
		if BoardRules.is_hanging(offer, TimeManager.day):
			out.append(offer)
	return out


## Notices the player took and has not finished.
func running_for(peer: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Dictionary in offers:
		var entry: Dictionary = entry_of(int(offer.id), peer)
		if not entry.is_empty() and not bool(entry.get("done", false)) and String(offer.k) != BoardRules.STORY:
			out.append(offer)
	return out


# ---------- host: the days ----------

func _on_day_started(day: int) -> void:
	if not is_ready():
		return
	_lapse_entries(day)
	var ran_out: int = 0
	for offer: Dictionary in offers:
		if int(offer.e) == day and String(offer.k) != BoardRules.STORY:
			ran_out += 1
	var gone: Array[int] = []
	for offer: Dictionary in offers:
		if BoardRules.is_expired(offer, day) and not _held(int(offer.id)):
			gone.append(int(offer.id))
	for id: int in gone:
		_remove(id)
	var fresh: int = post_occasions(context(day))
	var post: Dictionary = BoardRules.config().get("post", {}) as Dictionary
	while fresh < BoardRules.limit("new_per_day") and _simple_count() < _simple_cap():
		if _rng.randf() > float(post.get("chance", 1.0)):
			break
		var offer: Dictionary = BoardRules.roll(_rng, town.residents, _plain_hanging(), day, next_id)
		if offer.is_empty():
			break
		_maybe_rush(offer)
		next_id += 1
		offers.append(offer)
		fresh += 1
	_broadcast() ## also when only the days moved on: notices ran out, entries lapsed, every peer's panel changes
	if ran_out > 0 and town.critters != null:
		town.critters.board_visit(ran_out)


## What the town knows at this sunrise (the occasions ask this, nothing else): the stock, yesterday's storm, damp days, the night's report, the moon.
func context(day: int) -> Dictionary:
	var seed_value: int = Moisture.world_seed
	var storm: bool = false
	var wet: int = 0
	if WeatherRules.enabled():
		for k: int in 8:
			if WeatherRules.state_at(seed_value, float(day - 1) + 0.1 + 0.1 * float(k)).storm >= 0.5:
				storm = true
		while wet < 4 and WeatherRules.wet_day(seed_value, day - wet):
			wet += 1
	var report: Dictionary = {}
	if town.world != null and town.world.night != null:
		report = town.world.night.last_night_report()
		if int(report.get("night", -9)) != day - 1: ## only the night that just ended
			report = {}
	var ctx: Dictionary = {"day": day, "moon_day": posmod(day, 8), "stock": town.stock.duplicate(), "storm_yesterday": storm, "wet_days": wet, "report": report}
	for key: String in debug_context:
		ctx[key] = debug_context[key]
	return ctx


## Host: the occasions that are due put their notices on the board first (they take places of the day's `new_per_day`). Returns how many hang now. Public for the tests.
func post_occasions(ctx: Dictionary) -> int:
	var day: int = int(ctx.day)
	var due: Array[Dictionary] = BoardRules.due_occasions(ctx, occasion_last)
	var fresh: int = 0
	var max_new: int = mini(BoardRules.limit("occasions"), BoardRules.limit("new_per_day"))
	for item: Dictionary in due:
		if fresh >= max_new:
			break
		var occ: Dictionary = item.occ as Dictionary
		var giver: String = String(occ.giver)
		if not town.residents.has(giver) or int((town.residents[giver] as Dictionary).get("trust", 0)) < int(occ.get("min_trust", 0)):
			continue
		if _giver_count(giver) > BoardRules.limit("per_giver") or _occasion_hangs(String(occ.id)):
			continue
		var offer: Dictionary = BoardRules.make_occasion(_rng, occ, item.hit as Dictionary, giver, day, next_id, _rush_free())
		if offer.is_empty():
			continue
		next_id += 1
		offers.append(offer)
		occasion_last[String(occ.id)] = day
		fresh += 1
	return fresh


func _giver_count(giver: String) -> int:
	var count: int = 0
	for offer: Dictionary in _plain_hanging():
		count += 1 if String(offer.g) == giver else 0
	return count


## What hangs, without the wanted poster (it has a place of its own).
func _plain_hanging() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Dictionary in hanging():
		if not BoardRules.is_bounty(offer):
			out.append(offer)
	return out


## How many simple notices may hang: the board grows with the town's honour (a place more at every milestone), up to the six places on the panel.
func _simple_cap() -> int:
	return mini(BoardRules.limit("simple") + BoardRules.milestones_reached(honor_done()), 6)


func _occasion_hangs(id: String) -> bool:
	for offer: Dictionary in hanging():
		if String(offer.get("oc", "")) == id:
			return true
	return false


## Is there room for a rush notice (one at a time)?
func _rush_free() -> bool:
	var count: int = 0
	for offer: Dictionary in hanging():
		count += 1 if BoardRules.is_urgent(offer) else 0
	return count < int(BoardRules.urgent_cfg().get("max_hanging", 1))


## A plain fetch notice may be upgraded to a rush notice by chance, from enough trust, when none hangs.
func _maybe_rush(offer: Dictionary) -> void:
	var cfg: Dictionary = BoardRules.urgent_cfg()
	if String(offer.k) != BoardRules.FETCH or not _rush_free() or not town.residents.has(String(offer.g)):
		return
	if int((town.residents[String(offer.g)] as Dictionary).get("trust", 0)) < int(cfg.get("min_trust", 20)):
		return
	if _rng.randf() < float(cfg.get("upgrade_chance", 0.0)):
		BoardRules.urgentize(offer, BoardRules.template_of(String(offer.tx)))
		offer["w"] = "EILIG"


func _simple_count() -> int:
	var count: int = 0
	for offer: Dictionary in _plain_hanging():
		if String(offer.k) != BoardRules.STORY:
			count += 1
	return count


## Does somebody still carry this notice (taken, not handed in)? Then it stays in the table after it ran out on the board.
func _held(id: int) -> bool:
	for entry: Variant in (taken.get(str(id), {}) as Dictionary).values():
		if not bool((entry as Dictionary).get("done", false)):
			return true
	return false


## Host, at sunrise: entries whose own deadline has come are dropped, their owner is told.
func _lapse_entries(day: int) -> void:
	for offer: Dictionary in offers:
		var sheet: Dictionary = taken.get(str(offer.id), {}) as Dictionary
		for peer_key: String in sheet.keys():
			var entry: Dictionary = sheet[peer_key] as Dictionary
			var due: int = BoardRules.entry_due(offer, entry)
			if bool(entry.get("done", false)) or due < 0 or day < due:
				continue
			sheet.erase(peer_key)
			_reply(int(peer_key), "AUFTRAG VERFALLEN", false)


## Host: dev and tests post one by hand (template id, giver).
func debug_post(template_id: String, giver: String) -> int:
	var template: Dictionary = BoardRules.template_of(template_id)
	if not multiplayer.is_server() or template.is_empty():
		return -1
	var offer: Dictionary = BoardRules.make(_rng, template, giver, TimeManager.day, next_id)
	next_id += 1
	offers.append(offer)
	_broadcast()
	return int(offer.id)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_story_clock -= delta
	if _story_clock <= 0.0:
		_story_clock = 1.0
		_check_story()
	_urgent_clock -= delta
	if _urgent_clock <= 0.0:
		_urgent_clock = 1.0
		check_rush()
		check_bounty()


## Host, once a second: a rush notice that dusk has reached is gone, with the entries of those who still carried it.
func check_rush() -> void:
	if not is_ready():
		return
	var gone: Array[int] = []
	for offer: Dictionary in offers:
		if BoardRules.urgent_over(offer, TimeManager.day, TimeManager.time_of_day):
			gone.append(int(offer.id))
	if gone.is_empty():
		return
	for id: int in gone:
		var sheet: Dictionary = taken.get(str(id), {}) as Dictionary
		for peer_key: String in sheet.keys():
			if not bool((sheet[peer_key] as Dictionary).get("done", false)):
				_reply(int(peer_key), "EILZETTEL VERFALLEN", false)
		_remove(id)
	_broadcast()


## Host, once a second: a story notice hangs as soon as its condition holds for the host's own player (quests are local to their owner).
func _check_story() -> void:
	if not is_ready():
		return
	var player: Player = town.local_player()
	if player == null or player.quests == null:
		return
	var quests: Dictionary = DataRegistry.table("quests")
	var changed_any: bool = false
	for raw: Variant in BoardRules.story_entries():
		var entry: Dictionary = raw as Dictionary
		if _story_posted.has(String(entry.id)):
			continue
		if BoardRules.story_due(entry, quests, player.quests.is_finished, player.quests.has_flag):
			_story_posted[String(entry.id)] = true
			offers.append(BoardRules.make_story(entry, TimeManager.day, next_id))
			next_id += 1
			changed_any = true
	if changed_any:
		_broadcast()


func _remove(id: int) -> void:
	for i: int in offers.size():
		if int(offers[i].id) == id:
			offers.remove_at(i)
			break
	taken.erase(str(id))


# ---------- asking ----------

func request_accept(id: int) -> void:
	if multiplayer.is_server():
		_host_accept(multiplayer.get_unique_id(), id)
	else:
		_rpc_accept.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_accept(id: int) -> void:
	if multiplayer.is_server():
		_host_accept(multiplayer.get_remote_sender_id(), id)


func request_finish(id: int) -> void:
	if multiplayer.is_server():
		_host_finish(multiplayer.get_unique_id(), id)
	else:
		_rpc_finish.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_finish(id: int) -> void:
	if multiplayer.is_server():
		_host_finish(multiplayer.get_remote_sender_id(), id)


func _player_of(peer: int) -> Player:
	for player: Player in Player.all:
		if player.name.to_int() == peer:
			return player
	return null


func _near_board(player: Player) -> bool:
	return town._near_role(player, "board", BoardRules.reach())


## Is the player within talking distance of the settler who gave the notice? Reports are made to them, not at the board.
func _near_giver(player: Player, giver: String) -> bool:
	var node: Node2D = town.person_node(giver)
	return node != null and node.is_inside_tree() and node.global_position.distance_to(player.global_position) <= BoardRules.giver_reach()


## Notices of `giver` that `player` has taken and can hand in right now (the settlers ask this for their prompt and for E).
func finishable(giver: String, player: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if player == null or player.inventory == null:
		return out
	var peer: int = player.name.to_int()
	for offer: Dictionary in running_for(peer):
		if String(offer.g) == giver and BoardRules.can_finish(offer, entry_of(int(offer.id), peer), have_of(offer, player)):
			out.append(offer)
	return out


## E at a settler: hands in every finished notice they gave. Returns what the settler says (empty = nothing to report).
func report(giver: String, player: Player) -> String:
	var ready: Array[Dictionary] = finishable(giver, player)
	if ready.is_empty():
		return ""
	for offer: Dictionary in ready:
		request_finish(int(offer.id))
	var lines: Array = BoardRules.thanks()
	return String(lines[randi() % lines.size()]) if not lines.is_empty() else ""


func _host_accept(peer: int, id: int) -> void:
	var player: Player = _player_of(peer)
	var offer: Dictionary = offer_of(id)
	if player == null or offer.is_empty() or not _near_board(player):
		_reply(peer, "DER ZETTEL IST WEG", false)
		return
	if not entry_of(id, peer).is_empty():
		_reply(peer, "SCHON ANGENOMMEN", false)
		return
	if not BoardRules.is_hanging(offer, TimeManager.day):
		_reply(peer, "DER ZETTEL IST ABGELAUFEN", false)
		return
	var sheet: Dictionary = taken.get(str(id), {}) as Dictionary
	sheet[str(peer)] = {"n": 0, "done": false, "due": BoardRules.due_for(offer, TimeManager.day)}
	taken[str(id)] = sheet
	if String(offer.k) == BoardRules.STORY:
		if peer == multiplayer.get_unique_id():
			_start_quest(String(offer.q))
		else:
			_rpc_start_quest.rpc_id(peer, String(offer.q))
	_reply(peer, "ANGENOMMEN", true)
	_broadcast()


func _host_finish(peer: int, id: int) -> void:
	var player: Player = _player_of(peer)
	var offer: Dictionary = offer_of(id)
	if player == null or offer.is_empty():
		_reply(peer, "DER ZETTEL IST WEG", false)
		return
	if not _near_giver(player, String(offer.g)):
		_reply(peer, "MELDE DICH BEIM AUFTRAGGEBER", false)
		return
	var entry: Dictionary = entry_of(id, peer)
	if entry.is_empty():
		_reply(peer, "ERST ANNEHMEN", false)
		return
	if bool(entry.get("done", false)):
		_reply(peer, "SCHON ERLEDIGT", false)
		return
	var have: int = have_of(offer, player)
	if not BoardRules.can_finish(offer, entry, have):
		_reply(peer, "NOCH NICHT GENUG" if String(offer.k) == BoardRules.FETCH else "NOCH NICHT ERLEDIGT", false)
		return
	if String(offer.k) == BoardRules.FETCH and not player.inventory.remove_item(String(offer.t), int(offer.n)):
		_reply(peer, "NOCH NICHT GENUG", false)
		return
	entry["done"] = true
	(taken[str(id)] as Dictionary)[str(peer)] = entry
	player.progress.award(int(offer.c), int(offer.x))
	_add_trust(String(offer.g), int(offer.tr))
	var bonus: Dictionary = offer.get("b", {}) as Dictionary
	if not bonus.is_empty():
		player.inventory.give(String(bonus.id), int(bonus.n))
	_reply(peer, "ERLEDIGT", true)
	_honor_count(peer, offer)
	_broadcast()


func _add_trust(giver: String, amount: int) -> void:
	if amount <= 0 or not town.residents.has(giver):
		return
	var data: Dictionary = (town.residents[giver] as Dictionary).duplicate()
	data["trust"] = mini(int(data.trust) + amount, 100)
	town._rpc_resident.rpc(giver, data, false)


# ---------- the wanted poster ----------

func _bounty_offer() -> Dictionary:
	for offer: Dictionary in offers:
		if BoardRules.is_bounty(offer) and not BoardRules.is_expired(offer, TimeManager.day):
			return offer
	return {}


## Host, once a second: a marked creature gets its poster in the morning (one at a time), the poster follows what is known of its place, a fall pays everybody who hurt it.
func check_bounty() -> void:
	if not is_ready() or town.world == null or town.world.night == null:
		return
	var night: NightDirector = town.world.night as NightDirector
	if not _night_hooked:
		_night_hooked = true
		night.bounty_fell.connect(_on_bounty_fell)
	var mark: Dictionary = night.marked
	var offer: Dictionary = _bounty_offer()
	if mark.is_empty():
		return
	var giver: String = String(BoardRules.bounty_cfg().get("giver", "valdric"))
	if offer.is_empty():
		if TimeManager.is_night() or not town.residents.has(giver):
			return ## the poster goes up in the morning
		offer = BoardRules.make_bounty(mark, giver, TimeManager.day, next_id)
		next_id += 1
		offers.append(offer)
		_bounty_sent = Vector2(float((mark.pos as Array)[0]), float((mark.pos as Array)[1]))
		_broadcast()
		if town.critters != null:
			town.critters.board_visit(1)
		return
	var changed_now: bool = false
	if String(offer.bn) != String(mark.name) or int(offer.bh) != int(mark.nights): ## it survived another night: tougher, dearer, a new place
		var fresh: Dictionary = BoardRules.make_bounty(mark, giver, int(offer.d), int(offer.id))
		for key: String in fresh:
			offer[key] = fresh[key]
		changed_now = true
	_bounty_clock -= 1.0
	if _bounty_clock <= 0.0:
		_bounty_clock = float(BoardRules.bounty_cfg().get("seen_every", 6.0))
		var at: Vector2 = Vector2(float((mark.pos as Array)[0]), float((mark.pos as Array)[1]))
		if _bounty_sent == Vector2.INF or at.distance_to(_bounty_sent) > 32.0:
			var area: Array = offer.a as Array
			offer["a"] = [at.x, at.y, float(area[2])]
			_bounty_sent = at
			changed_now = true
	if changed_now:
		_broadcast()


## Host: the marked one fell. Whoever took the poster and ever hurt it has it done; whoever took it and did not is released; the name goes into the honour board.
func _on_bounty_fell(mark: Dictionary, peers: Array) -> void:
	var day: int = TimeManager.day
	for offer: Dictionary in offers:
		if not BoardRules.is_bounty(offer) or String(offer.bn) != String(mark.name):
			continue
		var sheet: Dictionary = taken.get(str(offer.id), {}) as Dictionary
		for peer_key: String in sheet.keys():
			var entry: Dictionary = sheet[peer_key] as Dictionary
			if bool(entry.get("done", false)):
				continue
			if peers.has(int(peer_key)):
				entry["n"] = 1
				sheet[peer_key] = entry
				_reply(int(peer_key), "%s IST GEFALLEN: MELDE ES VALDRIC" % String(mark.name), true)
			else:
				sheet.erase(peer_key)
				_reply(int(peer_key), "%s FIEL OHNE DICH" % String(mark.name), false)
		taken[str(offer.id)] = sheet
		offer["e"] = day ## it no longer hangs
	(honor.fallen as Array).append({"name": String(mark.name), "species": String(mark.species), "day": day, "nights": int(mark.nights)})
	_bounty_sent = Vector2.INF
	_broadcast()


# ---------- the honour board ----------

func honor_done() -> int:
	return int((honor.town as Dictionary).get("done", 0))


## The counters of the town (peer 0) or one player.
func stats_of(peer: int) -> Dictionary:
	if peer == 0:
		return (honor.town as Dictionary) if not (honor.town as Dictionary).is_empty() else BoardRules.blank_stats()
	return ((honor.peers as Dictionary).get(str(peer), BoardRules.blank_stats())) as Dictionary


## The title this player wears ("" = none), as its display name.
func title_name(peer: int) -> String:
	var id: String = String((honor.titles as Dictionary).get(str(peer), ""))
	return String(BoardRules.title_of(id).get("name", "")) if id != "" else ""


func _honor_count(peer: int, offer: Dictionary) -> void:
	var before: Array[String] = _earned_titles(peer)
	if (honor.town as Dictionary).is_empty():
		honor["town"] = BoardRules.blank_stats()
	BoardRules.count_done(honor.town as Dictionary, offer)
	var peers: Dictionary = honor.peers as Dictionary
	if not peers.has(str(peer)):
		peers[str(peer)] = BoardRules.blank_stats()
	BoardRules.count_done(peers[str(peer)] as Dictionary, offer)
	for id: String in _earned_titles(peer):
		if not before.has(id):
			_reply(peer, "NEUER TITEL: %s" % String(BoardRules.title_of(id).name), true)


func _earned_titles(peer: int) -> Array[String]:
	var out: Array[String] = []
	var stats: Dictionary = stats_of(peer)
	for raw: Variant in BoardRules.titles():
		if BoardRules.title_earned(stats, raw as Dictionary):
			out.append(String((raw as Dictionary).id))
	return out


func request_title(id: String) -> void:
	if multiplayer.is_server():
		_host_title(multiplayer.get_unique_id(), id)
	else:
		_rpc_title.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_title(id: String) -> void:
	if multiplayer.is_server():
		_host_title(multiplayer.get_remote_sender_id(), id)


## Host: a title may be worn once earned; "" takes it off.
func _host_title(peer: int, id: String) -> void:
	if id != "" and not _earned_titles(peer).has(id):
		_reply(peer, "NOCH NICHT VERDIENT", false)
		return
	(honor.titles as Dictionary)[str(peer)] = id
	_broadcast()


## Host: `player` killed a creature (DropComponent). Every kill notice they took and have not finished counts it once.
func note_kill(player: Player, species: String) -> void:
	if not multiplayer.is_server() or player == null or offers.is_empty():
		return
	var peer: int = player.name.to_int()
	var moved: bool = false
	for offer: Dictionary in offers:
		if String(offer.k) != BoardRules.KILL or String(offer.t) != species or BoardRules.is_bounty(offer):
			continue ## a marked one counts through `_on_bounty_fell`, not as just any creature of its kind
		if String(offer.get("win", "")) == "night" and not TimeManager.is_night():
			continue ## a night hunt only counts at night
		var entry: Dictionary = entry_of(int(offer.id), peer)
		if entry.is_empty() or bool(entry.get("done", false)) or int(entry.get("n", 0)) >= int(offer.n):
			continue
		entry["n"] = int(entry.get("n", 0)) + 1
		(taken[str(offer.id)] as Dictionary)[str(peer)] = entry
		moved = true
	if moved:
		_broadcast()


func _reply(peer: int, text: String, good: bool) -> void:
	if peer == multiplayer.get_unique_id():
		result.emit(text, good)
	else:
		_rpc_result.rpc_id(peer, text, good)


@rpc("authority", "call_remote", "reliable")
func _rpc_result(text: String, good: bool) -> void:
	result.emit(text, good)


@rpc("authority", "call_remote", "reliable")
func _rpc_start_quest(quest_id: String) -> void:
	_start_quest(quest_id)


func _start_quest(quest_id: String) -> void:
	var player: Player = town.local_player()
	if player != null and player.quests != null:
		player.quests.start(quest_id)


# ---------- sync, saving ----------

func _broadcast() -> void:
	changed.emit()
	_rpc_state.rpc(export_all())


@rpc("authority", "call_remote", "reliable")
func _rpc_state(data: Dictionary) -> void:
	_apply(data)
	changed.emit()


func export_all() -> Dictionary:
	return {"offers": offers.duplicate(true), "taken": taken.duplicate(true), "next_id": next_id, "story": _story_posted.keys(), "occ": occasion_last.duplicate(), "honor": honor.duplicate(true)}


func _apply(data: Dictionary) -> void:
	offers.clear()
	for raw: Variant in data.get("offers", []) as Array:
		offers.append(_clean(raw as Dictionary))
	taken = (data.get("taken", {}) as Dictionary).duplicate(true)
	next_id = int(data.get("next_id", 1))
	occasion_last.clear()
	for key: String in (data.get("occ", {}) as Dictionary):
		occasion_last[key] = int((data.occ as Dictionary)[key])
	_story_posted.clear()
	for sid: Variant in data.get("story", []) as Array:
		_story_posted[String(sid)] = true
	_apply_honor(data.get("honor", {}) as Dictionary)


## The honour board as it was written to the save: counters are ints again, every set is complete.
func _apply_honor(raw: Dictionary) -> void:
	honor = {"town": _clean_stats(raw.get("town", {}) as Dictionary), "peers": {}, "titles": {}, "fallen": []}
	for key: String in (raw.get("peers", {}) as Dictionary):
		(honor.peers as Dictionary)[key] = _clean_stats((raw.peers as Dictionary)[key] as Dictionary)
	for key: String in (raw.get("titles", {}) as Dictionary):
		(honor.titles as Dictionary)[key] = String((raw.titles as Dictionary)[key])
	for item: Variant in raw.get("fallen", []) as Array:
		var rec: Dictionary = item as Dictionary
		(honor.fallen as Array).append({"name": String(rec.get("name", "")), "species": String(rec.get("species", "")), "day": int(rec.get("day", 0)), "nights": int(rec.get("nights", 1))})


func _clean_stats(raw: Dictionary) -> Dictionary:
	var stats: Dictionary = BoardRules.blank_stats()
	if raw.is_empty():
		return {}
	for key: String in ["done", "fetch", "kills", "rush", "bounty"]:
		stats[key] = int(raw.get(key, 0))
	for giver: String in (raw.get("givers", {}) as Dictionary):
		(stats.givers as Dictionary)[giver] = int((raw.givers as Dictionary)[giver])
	return stats


## A notice as it was written to the save: ints stay ints, missing keys get a value.
func _clean(raw: Dictionary) -> Dictionary:
	var offer: Dictionary = raw.duplicate(true)
	for key: String in ["id", "n", "c", "x", "tr", "d", "e"]:
		offer[key] = int(offer.get(key, 0))
	for key: String in ["k", "g", "tx", "t", "txt", "ti", "q"]:
		offer[key] = String(offer.get(key, ""))
	offer["b"] = offer.get("b", {}) as Dictionary
	if offer.has("u"):
		offer["u"] = bool(offer.u)
	if offer.has("ut"):
		offer["ut"] = float(offer.ut)
	for key: String in ["w", "oc", "win", "bn"]:
		if offer.has(key):
			offer[key] = String(offer[key])
	if offer.has("bh"):
		offer["bh"] = int(offer.bh)
	return offer


## `snapshot`: for a joining peer, everybody's entries; a save only keeps the host's own (peer ids are not stable between sessions).
func export_state(snapshot: bool = false) -> Dictionary:
	var data: Dictionary = export_all()
	if snapshot:
		return data
	var mine: String = str(multiplayer.get_unique_id())
	var honor_mine: Dictionary = {"town": (honor.town as Dictionary).duplicate(true), "peers": {}, "titles": {}, "fallen": (honor.fallen as Array).duplicate(true)}
	if (honor.peers as Dictionary).has(mine):
		(honor_mine.peers as Dictionary)[mine] = (honor.peers as Dictionary)[mine]
	if (honor.titles as Dictionary).has(mine):
		(honor_mine.titles as Dictionary)[mine] = (honor.titles as Dictionary)[mine]
	data["honor"] = honor_mine
	var kept: Dictionary = {}
	for key: String in taken:
		var entry: Variant = (taken[key] as Dictionary).get(mine)
		if entry != null:
			kept[key] = {mine: entry}
	data["taken"] = kept
	return data


func import_state(data: Dictionary) -> void:
	_apply(data)
	changed.emit()
