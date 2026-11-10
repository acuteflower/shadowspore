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


## Notices hanging that the player has not taken yet (a finished or running one is not listed: it is under `running_for` or gone).
func open_for(peer: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Dictionary in offers:
		if entry_of(int(offer.id), peer).is_empty():
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
	var gone: Array[int] = []
	for offer: Dictionary in offers:
		if BoardRules.is_expired(offer, day):
			gone.append(int(offer.id))
	for id: int in gone:
		_remove(id)
	var fresh: int = 0
	var post: Dictionary = BoardRules.config().get("post", {}) as Dictionary
	while fresh < BoardRules.limit("new_per_day") and _simple_count() < BoardRules.limit("simple"):
		if _rng.randf() > float(post.get("chance", 1.0)):
			break
		var offer: Dictionary = BoardRules.roll(_rng, town.residents, offers, day, next_id)
		if offer.is_empty():
			break
		next_id += 1
		offers.append(offer)
		fresh += 1
	if fresh > 0 or not gone.is_empty():
		_broadcast()


func _simple_count() -> int:
	var count: int = 0
	for offer: Dictionary in offers:
		if String(offer.k) != BoardRules.STORY:
			count += 1
	return count


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


func _host_accept(peer: int, id: int) -> void:
	var player: Player = _player_of(peer)
	var offer: Dictionary = offer_of(id)
	if player == null or offer.is_empty() or not _near_board(player):
		_reply(peer, "DER ZETTEL IST WEG", false)
		return
	if not entry_of(id, peer).is_empty():
		_reply(peer, "SCHON ANGENOMMEN", false)
		return
	var sheet: Dictionary = taken.get(str(id), {}) as Dictionary
	sheet[str(peer)] = {"n": 0, "done": false}
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
	if player == null or offer.is_empty() or not _near_board(player):
		_reply(peer, "DER ZETTEL IST WEG", false)
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
	_broadcast()


func _add_trust(giver: String, amount: int) -> void:
	if amount <= 0 or not town.residents.has(giver):
		return
	var data: Dictionary = (town.residents[giver] as Dictionary).duplicate()
	data["trust"] = mini(int(data.trust) + amount, 100)
	town._rpc_resident.rpc(giver, data, false)


## Host: `player` killed a creature (DropComponent). Every kill notice they took and have not finished counts it once.
func note_kill(player: Player, species: String) -> void:
	if not multiplayer.is_server() or player == null or offers.is_empty():
		return
	var peer: int = player.name.to_int()
	var moved: bool = false
	for offer: Dictionary in offers:
		if String(offer.k) != BoardRules.KILL or String(offer.t) != species:
			continue
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
	return {"offers": offers.duplicate(true), "taken": taken.duplicate(true), "next_id": next_id, "story": _story_posted.keys()}


func _apply(data: Dictionary) -> void:
	offers.clear()
	for raw: Variant in data.get("offers", []) as Array:
		offers.append(_clean(raw as Dictionary))
	taken = (data.get("taken", {}) as Dictionary).duplicate(true)
	next_id = int(data.get("next_id", 1))
	_story_posted.clear()
	for sid: Variant in data.get("story", []) as Array:
		_story_posted[String(sid)] = true


## A notice as it was written to the save: ints stay ints, missing keys get a value.
func _clean(raw: Dictionary) -> Dictionary:
	var offer: Dictionary = raw.duplicate(true)
	for key: String in ["id", "n", "c", "x", "tr", "d", "e"]:
		offer[key] = int(offer.get(key, 0))
	for key: String in ["k", "g", "tx", "t", "txt", "ti", "q"]:
		offer[key] = String(offer.get(key, ""))
	offer["b"] = offer.get("b", {}) as Dictionary
	return offer


## `snapshot`: for a joining peer, everybody's entries; a save only keeps the host's own (peer ids are not stable between sessions).
func export_state(snapshot: bool = false) -> Dictionary:
	var data: Dictionary = export_all()
	if snapshot:
		return data
	var mine: String = str(multiplayer.get_unique_id())
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
