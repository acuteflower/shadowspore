class_name PetRegistry
extends Node
## Who trusts whom (docs/pet_konzept.md): the bond points between every player and every wild crow or raven they fed. A node of the world level
## (group `pets`), host-authoritative: the host validates a feeding, counts the points and tells the others. Every peer keeps the table of its own
## bonds so the tag over a bird can show them. Saved as `"pets"` by `SaveGame`.
##
## A bird is known by its `pet_key` (flock id + place in the flock: the same every session, because the flocks are seeded from the chunk). The
## player is the peer id (in a single-player game always 1). Step 1 of three: the bond itself; names, territories and companions come later.

signal bond_changed(pet_key: String, peer: int, gained: float, stage_up: bool)
signal companion_changed() ## the companion table changed
signal pet_changed(pet_key: String) ## a record was made, renamed or its place was updated

var _bonds: Dictionary = {} ## pet_key -> {str(peer): {bp: float, day: int, fed: int, total: int}}
var _cooldown: Dictionary = {} ## "<key>|<peer>" -> msec when it may be fed again (never saved)
var _pets: Dictionary = {} ## pet_key -> {n name, sp species, ap look, ring, home [x, y], seen [x, y], sd day seen, rd day registered, by peer}: the birds that stay (step 2)
var _comp: Dictionary = {} ## peer (int) -> {"k": pet_key, "m": mode (0 follow, 1 stay, 2 home), "st": [x, y] where it stays, "cd": ability ready at msec (never saved)}
var _still: Dictionary = {} ## peer -> seconds the player has stood still (host)
var _whistle_held: float = -1.0 ## local: how long G has been held (-1 = not held)
var _whistle_done: bool = false
var _hoards: Dictionary = {} ## pet_key -> ItemBox: what a companion brings home (E on the bird opens it)
var _gift_left: Dictionary = {} ## peer -> seconds until the next find (host)
var _finds_day: Dictionary = {} ## peer -> {"d": day, "n": finds so far today}
var _scouts: Dictionary = {} ## peer -> {"ph": 0 out / 1 back, "t": seconds, "goal": Vector2} (host)
var _last_dir: Dictionary = {} ## peer -> the way she last walked
var _perch_left: Dictionary = {} ## peer -> seconds until a companion at home looks for a town perch
var _tick_left: float = 1.0
var _check_left: float = 2.0
var _seen_left: float = 0.0


static func of(tree: SceneTree) -> PetRegistry:
	return tree.get_first_node_in_group("pets") as PetRegistry


func _ready() -> void:
	add_to_group("pets")
	set_process(true)
	if multiplayer.is_server():
		TimeManager.day_started.connect(_on_day)
	else:
		_request_bonds.rpc_id(1)


# ---------------------------------------------------------------- reading

func entry(pet_key: String, peer: int) -> Dictionary:
	return ((_bonds.get(pet_key, {}) as Dictionary).get(str(peer), {}) as Dictionary)


func bp_of(pet_key: String, peer: int) -> float:
	return float(entry(pet_key, peer).get("bp", 0.0))


func stage_of(pet_key: String, peer: int) -> int:
	return PetRules.stage_of(bp_of(pet_key, peer))


## How often this bird was fed by this player today (the daily curve of the points looks at it).
func fed_today(pet_key: String, peer: int) -> int:
	var data: Dictionary = entry(pet_key, peer)
	return int(data.get("fed", 0)) if int(data.get("day", -1)) == TimeManager.day else 0


## Seconds before this player may feed this bird again.
func cooldown_left(pet_key: String, peer: int) -> float:
	return maxf(0.0, (float(_cooldown.get("%s|%d" % [pet_key, peer], 0)) - float(Time.get_ticks_msec())) / 1000.0)


func known_count(peer: int) -> int:
	var count: int = 0
	for key: String in _bonds:
		if (_bonds[key] as Dictionary).has(str(peer)):
			count += 1
	return count


# ---------------------------------------------------------------- host: feeding

## Host: `player` hands `item` to the bird `pet_key` of `species`. Returns what happened:
## {ok, reaction, gain, bp, stage, up}. Nothing is counted for food the bird does not want (the caller keeps the item then).
func feed(pet_key: String, species: String, player_peer: int, item: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "reaction": "", "gain": 0.0, "bp": bp_of(pet_key, player_peer), "stage": stage_of(pet_key, player_peer), "up": false}
	if not multiplayer.is_server() or pet_key == "":
		return result
	var kind: String = PetRules.reaction(species, item, pet_key)
	result["reaction"] = kind
	if kind == PetRules.NO_REACTION or kind == "dislikes":
		return result
	if cooldown_left(pet_key, player_peer) > 0.0:
		return result
	var fed: int = fed_today(pet_key, player_peer)
	var gain: float = PetRules.gain(kind, fed, PetRules.traits_of(pet_key))
	var before: float = bp_of(pet_key, player_peer)
	var after: float = before + gain
	var table: Dictionary = _bonds.get_or_add(pet_key, {}) as Dictionary
	var data: Dictionary = table.get(str(player_peer), {"bp": 0.0, "day": -1, "fed": 0, "total": 0}) as Dictionary
	data["bp"] = after
	data["day"] = TimeManager.day
	data["fed"] = fed + 1
	data["total"] = int(data.get("total", 0)) + 1
	table[str(player_peer)] = data
	_cooldown["%s|%d" % [pet_key, player_peer]] = Time.get_ticks_msec() + int(float((PetRules.table()["feed"] as Dictionary)["cooldown"]) * 1000.0)
	var up: bool = PetRules.stage_of(after) > PetRules.stage_of(before)
	result.merge({"ok": true, "gain": gain, "bp": after, "stage": PetRules.stage_of(after), "up": up}, true)
	_announce(pet_key, player_peer, data, gain, up)
	return result


func _announce(pet_key: String, peer: int, data: Dictionary, gain: float, up: bool) -> void:
	bond_changed.emit(pet_key, peer, gain, up)
	if multiplayer.get_peers().size() > 0:
		_rpc_bond.rpc(pet_key, peer, float(data["bp"]), int(data["day"]), int(data["fed"]), int(data["total"]), gain, up)


@rpc("authority", "call_remote", "reliable")
func _rpc_bond(pet_key: String, peer: int, bp: float, day: int, fed: int, total: int, gain: float, up: bool) -> void:
	var table: Dictionary = _bonds.get_or_add(pet_key, {}) as Dictionary
	table[str(peer)] = {"bp": bp, "day": day, "fed": fed, "total": total}
	bond_changed.emit(pet_key, peer, gain, up)


@rpc("any_peer", "call_remote", "reliable")
func _request_bonds() -> void:
	if not multiplayer.is_server():
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var mine: Dictionary = {}
	for key: String in _bonds:
		var data: Variant = (_bonds[key] as Dictionary).get(str(peer))
		if data != null:
			mine[key] = data
	_rpc_bonds.rpc_id(peer, mine)
	_rpc_records.rpc_id(peer, _pets)


@rpc("authority", "call_remote", "reliable")
func _rpc_bonds(mine: Dictionary) -> void:
	var me: int = multiplayer.get_unique_id()
	for key: String in mine:
		(_bonds.get_or_add(key, {}) as Dictionary)[str(me)] = mine[key]
		bond_changed.emit(key, me, 0.0, false)


# ---------------------------------------------------------------- registered birds (step 2)

func has_record(pet_key: String) -> bool:
	return _pets.has(pet_key)


func record(pet_key: String) -> Dictionary:
	return _pets.get(pet_key, {}) as Dictionary


func name_of(pet_key: String) -> String:
	return String(record(pet_key).get("n", ""))


## All registered birds as {key, ...record}, in the order they were registered.
func records() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key: String in _pets:
		list.append((_pets[key] as Dictionary).merged({"key": key}, true))
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rd"]) < int(b["rd"]) or (int(a["rd"]) == int(b["rd"]) and String(a["key"]) < String(b["key"])))
	return list


## Host: after a feeding the bird may have reached the registering stage. Makes its record (name, ring, home = where it stands) once.
func ensure_record(bird: WildCorvid, peer: int) -> bool:
	if not multiplayer.is_server() or bird.pet_key == "" or _pets.has(bird.pet_key):
		return false
	var reg: Dictionary = PetRules.table()["register"] as Dictionary
	if stage_of(bird.pet_key, peer) < int(reg["stage"]):
		return false
	var rings: Array = reg["ring_colors"] as Array
	_pets[bird.pet_key] = {
		"n": _pick_name(bird.pet_key, bird.species), "sp": bird.species, "ap": bird.appearance,
		"ring": absi(hash(bird.pet_key + "ring")) % rings.size(),
		"home": [bird.global_position.x, bird.global_position.y], "seen": [bird.global_position.x, bird.global_position.y],
		"sd": TimeManager.day, "rd": TimeManager.day, "by": peer,
	}
	_send_record(bird.pet_key)
	return true


func _pick_name(pet_key: String, species: String) -> String:
	var pool: Array = ((PetRules.table()["register"] as Dictionary)["names"] as Dictionary).get(species, ["FEDER"]) as Array
	var taken: Dictionary = {}
	for key: String in _pets:
		taken[String((_pets[key] as Dictionary)["n"])] = true
	var start: int = absi(hash(pet_key + "name")) % pool.size()
	for i: int in pool.size():
		var candidate: String = String(pool[(start + i) % pool.size()])
		if not taken.has(candidate):
			return candidate
	return "%s %d" % [String(pool[start]), _pets.size() + 1]


## A player asks for a new name. The host cleans it (capitals, letters, digits, space and dash, at most `max_name`) and only a player who knows the bird may.
func request_rename(pet_key: String, text: String) -> void:
	if multiplayer.is_server():
		_do_rename(pet_key, text, 1)
	else:
		_rename.rpc_id(1, pet_key, text)


@rpc("any_peer", "call_remote", "reliable")
func _rename(pet_key: String, text: String) -> void:
	if multiplayer.is_server():
		_do_rename(pet_key, text, multiplayer.get_remote_sender_id())


static func clean_name(text: String) -> String:
	var limit: int = int((PetRules.table()["register"] as Dictionary)["max_name"])
	var out: String = ""
	for c: String in text.to_upper():
		if (c >= "A" and c <= "Z") or c in "ÄÖÜß0123456789 -":
			out += c
	return out.strip_edges().substr(0, limit).strip_edges()


func _do_rename(pet_key: String, text: String, peer: int) -> void:
	var clean: String = clean_name(text)
	if clean == "" or not _pets.has(pet_key) or stage_of(pet_key, peer) < int((PetRules.table()["register"] as Dictionary)["stage"]):
		return
	(_pets[pet_key] as Dictionary)["n"] = clean
	_send_record(pet_key)


func _send_record(pet_key: String) -> void:
	pet_changed.emit(pet_key)
	if multiplayer.get_peers().size() > 0:
		_rpc_record.rpc(pet_key, _pets[pet_key] as Dictionary)


@rpc("authority", "call_remote", "reliable")
func _rpc_record(pet_key: String, data: Dictionary) -> void:
	_pets[pet_key] = data
	pet_changed.emit(pet_key)


@rpc("authority", "call_remote", "reliable")
func _rpc_records(all: Dictionary) -> void:
	for key: String in all:
		_pets[key] = all[key]
		pet_changed.emit(key)


@rpc("authority", "call_remote", "unreliable")
func _rpc_seen(places: Dictionary) -> void:
	for key: String in places:
		if _pets.has(key):
			var data: Array = places[key] as Array
			var rec: Dictionary = _pets[key] as Dictionary
			rec["seen"] = [data[0], data[1]]
			rec["sd"] = int(data[2])


## Where the bird was last seen (x, y in world pixels, z = the day).
func seen_of(pet_key: String) -> Vector3:
	var rec: Dictionary = record(pet_key)
	if rec.is_empty():
		return Vector3.ZERO
	var at: Array = rec["seen"] as Array
	return Vector3(float(at[0]), float(at[1]), float(rec["sd"]))


# ---------------------------------------------------------------- host: keeping the birds in the world

func _process(delta: float) -> void:
	_poll_whistle(delta)
	if not multiplayer.is_server():
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = float((PetRules.table()["companion"] as Dictionary)["tick"])
		_tick_companions(_tick_left + delta)
	var terr: Dictionary = PetRules.table()["territory"] as Dictionary
	_check_left -= delta
	_seen_left -= delta
	if _check_left > 0.0:
		return
	_check_left = float(terr["check_seconds"])
	_maintain_pets(terr)
	if _seen_left <= 0.0:
		_seen_left = float(terr["seen_seconds"])
		if multiplayer.get_peers().size() > 0 and not _pets.is_empty():
			var places: Dictionary = {}
			for key: String in _pets:
				var seen: Vector3 = seen_of(key)
				places[key] = [seen.x, seen.y, int(seen.z)]
			_rpc_seen.rpc(places)


func _maintain_pets(terr: Dictionary) -> void:
	if _pets.is_empty():
		return
	var population: CorvidPopulation = get_tree().get_first_node_in_group("corvid_population") as CorvidPopulation
	if population == null:
		return
	var loaded: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var bird: WildCorvid = node as WildCorvid
		if bird != null and bird.pet_key != "" and _pets.has(bird.pet_key) and not bird.is_queued_for_deletion():
			loaded[bird.pet_key] = bird
	for key: String in _pets:
		var rec: Dictionary = _pets[key] as Dictionary
		var place: Vector2 = PetSchedule.place(rec, key, TimeManager.time_of_day)
		var peer_c: int = peer_of_companion(key)
		var mode_c: int = mode_of(peer_c) if peer_c != 0 else 2
		if peer_c != 0 and mode_c == 0:
			var carrier: Player = _player(peer_c)
			if carrier == null or _indoors(carrier):
				continue ## nothing to keep in the world while she is inside
			place = carrier.global_position
		elif peer_c != 0 and mode_c == 1:
			var stay: Array = (_comp[peer_c] as Dictionary)["st"] as Array
			place = Vector2(float(stay[0]), float(stay[1]))
		var bird: WildCorvid = loaded.get(key) as WildCorvid
		if bird == null:
			if loaded.size() < int(terr["max_loaded"]) and population.is_active_at(place):
				var spawned: WildCorvid = population.spawn_pet(key, rec, place, float(terr["spawn_clear"]) if peer_c == 0 else 0.0)
				if spawned != null:
					loaded[key] = spawned
			continue
		bird.territory = place
		if peer_c != 0 and bird.rider != 0:
			continue
		var away: float = bird.global_position.distance_to(place)
		if away > float(terr["leash"]) and bird.state != WildCorvid.State.FLY and bird.offered_peer == 0 and not _watched(bird.global_position, float(terr["leash_hidden"])):
			bird.global_position = place ## nobody can see it: it is simply back in its territory
		var at: Vector2 = bird.global_position
		var rec_seen: Array = rec["seen"] as Array
		rec_seen[0] = at.x
		rec_seen[1] = at.y
		rec["sd"] = TimeManager.day
		if not population.is_active_at(at) and not (bird._moving and population.is_active_at(bird._end)):
			population.remove_pet(bird)
			loaded.erase(key)


# ---------------------------------------------------------------- companions (step 3, docs/pet_konzept.md 11)

func peer_of_companion(key: String) -> int:
	for peer: int in _comp:
		if String((_comp[peer] as Dictionary)["k"]) == key:
			return peer
	return 0


func companion_of(peer: int) -> String:
	return String((_comp[peer] as Dictionary)["k"]) if _comp.has(peer) else ""


## 0 follow, 1 stay, 2 home.
func mode_of(peer: int) -> int:
	return int((_comp[peer] as Dictionary)["m"]) if _comp.has(peer) else 2


func mode_name(peer: int) -> String:
	return String(((PetRules.table()["companion"] as Dictionary)["modes"] as Array)[mode_of(peer)])


func _player(peer: int) -> Player:
	for player: Player in Player.all:
		if player.name == str(peer):
			return player
	return null


func _indoors(player: Player) -> bool:
	return Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position)


func _bird_of(key: String) -> WildCorvid:
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var bird: WildCorvid = node as WildCorvid
		if bird != null and bird.pet_key == key and not bird.is_queued_for_deletion():
			return bird
	return null


## Anyone: ask the host for something about the companion. kind: "take" (key), "release", "mode", "come".
func ask(kind: String, key: String = "") -> void:
	if multiplayer.is_server():
		_ask(kind, key)
	else:
		_ask.rpc_id(1, kind, key)


@rpc("any_peer", "call_remote", "reliable")
func _ask(kind: String, key: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var peer: int = 1 if sender == 0 else sender
	match kind:
		"take":
			_take_companion(key, peer)
		"release":
			_release_companion(peer)
		"mode":
			_cycle_mode(peer)
		"come":
			_come(peer)


func _take_companion(key: String, peer: int) -> bool:
	var cfg: Dictionary = PetRules.table()["companion"] as Dictionary
	if not _pets.has(key) or stage_of(key, peer) < int(cfg["stage"]):
		return false
	var other: int = peer_of_companion(key)
	if other != 0 and other != peer:
		return false ## already somebody else's companion
	_release_companion(peer)
	_comp[peer] = {"k": key, "m": 0, "st": [0.0, 0.0], "cd": 0}
	_after_change(key, "MIT DIR")
	return true


func _release_companion(peer: int) -> void:
	if not _comp.has(peer):
		return
	var key: String = companion_of(peer)
	var bird: WildCorvid = _bird_of(key)
	if bird != null:
		bird.companion_peer = 0
		if bird.rider != 0:
			bird._ride.rpc(0)
	_comp.erase(peer)
	_after_change(key, "FREI")


func _cycle_mode(peer: int) -> void:
	if not _comp.has(peer):
		return
	var data: Dictionary = _comp[peer] as Dictionary
	var key: String = String(data["k"])
	var bird: WildCorvid = _bird_of(key)
	var next: int = (int(data["m"]) + 1) % 3
	data["m"] = next
	if next == 1:
		var at: Vector2 = bird.global_position if bird != null else Vector2.ZERO
		data["st"] = [at.x, at.y]
		if bird != null and bird.rider != 0:
			bird._ride.rpc(0)
	_after_change(key, mode_name(peer))


func _come(peer: int) -> void:
	if not _comp.has(peer):
		return
	var data: Dictionary = _comp[peer] as Dictionary
	var player: Player = _player(peer)
	var bird: WildCorvid = _bird_of(String(data["k"]))
	if player == null or bird == null or _indoors(player):
		return
	var scout: Dictionary = (PetRules.table()["companion"] as Dictionary)["scout"] as Dictionary
	if bird.species == "raven" and int(data["m"]) == 0 and not _scouts.has(peer) and (bird.rider != 0 or bird.global_position.distance_to(player.global_position) < 60.0) \
			and Time.get_ticks_msec() >= int(data.get("sc", 0)):
		data["sc"] = Time.get_ticks_msec() + int(float(scout["cooldown"]) * 1000.0)
		_start_scout(peer, bird, player, scout)
		return
	if int(data["m"]) == 2:
		data["m"] = 0
	if bird.rider != 0:
		return
	if int(data["m"]) == 1:
		data["st"] = [player.global_position.x, player.global_position.y]
	_still[peer] = 0.0
	bird._play_call.rpc(0, 1.12)
	var cfg: Dictionary = PetRules.table()["companion"] as Dictionary
	var goal: Vector2 = player.global_position + Vector2.from_angle(randf() * TAU) * 24.0
	if bird.global_position.distance_to(player.global_position) > float(cfg["teleport_distance"]):
		bird.global_position = player.global_position + Vector2(60.0, 0.0)
	bird.fly_to(goal)
	_after_change(String(data["k"]), "KOMMT", "whistle")


## The raven flies a loop ahead of her (Kundschafterflug): where it turns the fog lifts and shadow creatures near the turning point are marked.
func _start_scout(peer: int, bird: WildCorvid, player: Player, scout: Dictionary) -> void:
	var dir: Vector2 = player.velocity.normalized() if player.velocity.length() > 8.0 else (_last_dir.get(peer, Vector2.RIGHT) as Vector2)
	var goal: Vector2 = player.global_position + dir * float(scout["range"])
	if bird.rider != 0:
		bird._ride.rpc(0)
	bird.global_position = player.global_position + Vector2(7.0, 1.0)
	bird.state = WildCorvid.State.WATCH
	bird._moving = false
	_scouts[peer] = {"ph": 0, "t": 0.0, "goal": goal}
	bird.fly_to(goal)
	_after_change(bird.pet_key, "SPÄHT", "whistle")


func _tick_scout(peer: int, bird: WildCorvid, player: Player, delta: float) -> void:
	var scout: Dictionary = (PetRules.table()["companion"] as Dictionary)["scout"] as Dictionary
	var s: Dictionary = _scouts[peer] as Dictionary
	s["t"] = float(s["t"]) + delta
	var goal: Vector2 = s["goal"] as Vector2
	if int(s["ph"]) == 0:
		if (bird.state != WildCorvid.State.FLY and bird.global_position.distance_to(goal) < 48.0) or float(s["t"]) > float(scout["timeout"]):
			var seen: int = 0
			for node: Node in get_tree().get_nodes_in_group("predators"):
				var enemy: Node2D = node as Node2D
				if enemy != null and enemy.global_position.distance_to(bird.global_position) < float(scout["enemy_radius"]) and seen < 4:
					seen += 1
					if multiplayer.get_peers().size() > 0:
						_rpc_glint.rpc(enemy.global_position, true, 6.0, bird.pet_key, "")
					_glint(enemy.global_position, true, 6.0, bird.pet_key, "")
			var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
			if discovery != null:
				discovery.reveal_disc(bird.global_position / 16.0, float(scout["reveal_cells"]))
			_after_change(bird.pet_key, "FEINDE VORAUS" if seen > 0 else "ALLES RUHIG", "gift")
			s["ph"] = 1
			s["t"] = 0.0
			bird.state = WildCorvid.State.WATCH
			bird._moving = false
			bird.fly_to(player.global_position)
	elif (bird.state != WildCorvid.State.FLY and bird.global_position.distance_to(player.global_position) < 56.0) or float(s["t"]) > float(scout["timeout"]) * 2.0:
		_scouts.erase(peer)


func _after_change(key: String, word: String, sound: String = "mode") -> void:
	var table: Dictionary = {}
	for peer: int in _comp:
		table[peer] = _comp[peer]
	if multiplayer.get_peers().size() > 0:
		_rpc_comp.rpc(table)
		_rpc_flash.rpc(key, word, sound)
	_flash(key, word, sound)
	companion_changed.emit()
	pet_changed.emit(key)


@rpc("authority", "call_remote", "reliable")
func _rpc_comp(table: Dictionary) -> void:
	_comp.clear()
	for peer: int in table:
		_comp[peer] = table[peer]
	companion_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_flash(key: String, word: String, sound: String) -> void:
	_flash(key, word, sound)


func _flash(key: String, word: String, sound: String = "") -> void:
	var bird: WildCorvid = _bird_of(key)
	if bird != null:
		var tag: PetTag = bird.get_node_or_null("PetTag") as PetTag
		if tag != null:
			tag.flash(word)
		if sound == "whistle":
			var near: Player = null
			for candidate: Player in Player.all:
				if near == null or candidate.global_position.distance_to(bird.global_position) < near.global_position.distance_to(bird.global_position):
					near = candidate
			if near != null:
				var notes: PetGlint = PetGlint.new()
				notes.notes = true
				notes.life = 1.4
				near.add_child(notes)
		var volume: float = float(GameSettings.get_value("sfx")) / 100.0
		if sound != "" and volume > 0.0:
			var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			voice.stream = load("res://assets/audio/pets/%s.wav" % sound) as AudioStream
			voice.volume_db = -8.0 + linear_to_db(volume)
			voice.max_distance = 320.0
			bird.add_child(voice)
			voice.finished.connect(voice.queue_free)
			voice.play()


## Host, every `tick` seconds: companions follow, take the shoulder, leave it again and use their gift.
func _tick_companions(delta: float) -> void:
	if _comp.is_empty():
		return
	var cfg: Dictionary = PetRules.table()["companion"] as Dictionary
	for peer: int in _comp.keys():
		var data: Dictionary = _comp[peer] as Dictionary
		var key: String = String(data["k"])
		var player: Player = _player(peer)
		var bird: WildCorvid = _bird_of(key)
		if bird != null:
			bird.companion_peer = peer
		if player == null:
			continue
		if _indoors(player) or player.story_lock or player.intro != null or player.health.current <= 0.0:
			if bird != null:
				if bird.rider != 0:
					bird._ride.rpc(0)
				if _indoors(player):
					var population: CorvidPopulation = get_tree().get_first_node_in_group("corvid_population") as CorvidPopulation
					if population != null:
						population.remove_pet(bird)
			continue
		if player.velocity.length() > 8.0:
			_last_dir[peer] = player.velocity.normalized()
		if bird != null and _scouts.has(peer):
			_tick_scout(peer, bird, player, delta)
			continue
		if bird != null:
			_tick_finds(peer, data, bird, delta)
		if bird != null and int(data["m"]) == 2:
			_tick_home_perch(peer, bird, delta)
		if bird == null or int(data["m"]) != 0:
			continue
		var gap: float = bird.global_position.distance_to(player.global_position)
		var moving: bool = player.velocity.length() > 8.0
		_still[peer] = 0.0 if moving or player.attack.is_swinging() else float(_still.get(peer, 0.0)) + delta
		if bird.rider != 0:
			if player.sprinting or player.attack.is_swinging() or player.velocity.length() > 70.0:
				bird._ride.rpc(0)
				_still[peer] = 0.0
				bird.fly_to(player.global_position + Vector2.from_angle(randf() * TAU) * 26.0)
			continue
		if gap > float(cfg["teleport_distance"]) and not _watched_by_other(bird.global_position, float(cfg["teleport_hidden"]), player):
			bird.global_position = player.global_position + Vector2.from_angle(randf() * TAU) * 40.0
		elif gap > float(cfg["follow_distance"]) and bird.state != WildCorvid.State.FLY and bird.offered_peer == 0:
			bird.fly_to(player.global_position + Vector2.from_angle(randf() * TAU) * 28.0)
		elif float(_still[peer]) >= float(cfg["shoulder_after"]) and gap < float(cfg["shoulder_reach"]) and bird.state != WildCorvid.State.FLY:
			bird._ride.rpc(peer)
		_ability(peer, data, bird, player, cfg)


## At home a companion looks for a roof, lamp arm, bench or fence of the town (the same perches the visiting crows use).
func _tick_home_perch(peer: int, bird: WildCorvid, delta: float) -> void:
	_perch_left[peer] = float(_perch_left.get(peer, 0.0)) - delta
	if float(_perch_left[peer]) > 0.0:
		return
	_perch_left[peer] = float((PetRules.table()["companion"] as Dictionary)["perch_seconds"])
	if bird.rider != 0 or bird.state == WildCorvid.State.FLY or not bird._perch_path.is_empty() or get_tree().get_nodes_in_group("town_perches").is_empty():
		return
	bird.visit_roof = true
	bird._take_wing(false, false, false, true)


## Now and then the companion brings something home into its hoard (Mitbringsel / Glitzerfund).
func _tick_finds(peer: int, data: Dictionary, bird: WildCorvid, delta: float) -> void:
	var cfg: Dictionary = (PetRules.table()["companion"] as Dictionary)["finds"] as Dictionary
	if not _gift_left.has(peer):
		var span: Array = cfg["seconds"] as Array
		_gift_left[peer] = randf_range(float(span[0]), float(span[1]))
	_gift_left[peer] = float(_gift_left[peer]) - delta
	if float(_gift_left[peer]) > 0.0 or bird.state == WildCorvid.State.FLY:
		return
	var day_data: Dictionary = _finds_day.get(peer, {"d": TimeManager.day, "n": 0}) as Dictionary
	if int(day_data["d"]) != TimeManager.day:
		day_data = {"d": TimeManager.day, "n": 0}
	var span2: Array = cfg["seconds"] as Array
	if int(day_data["n"]) >= int(cfg["daily"]):
		_gift_left[peer] = randf_range(float(span2[0]), float(span2[1]))
		_finds_day[peer] = day_data
		return
	var table: Dictionary = cfg[bird.species] as Dictionary
	var total: float = 0.0
	for row: Array in table["items"] as Array:
		total += float(row[1])
	var roll: float = randf() * total
	var item: String = String((table["items"] as Array)[0][0])
	for row: Array in table["items"] as Array:
		roll -= float(row[1])
		if roll <= 0.0:
			item = String(row[0])
			break
	if hoard(bird.pet_key).add_item(item, 1) > 0:
		_gift_left[peer] = float(cfg["retry"]) ## the hoard is full: it keeps the find for later
		return
	hoard(bird.pet_key).touch()
	day_data["n"] = int(day_data["n"]) + 1
	_finds_day[peer] = day_data
	_gift_left[peer] = randf_range(float(span2[0]), float(span2[1]))
	if multiplayer.get_peers().size() > 0:
		_rpc_glint.rpc(bird.global_position, false, 3.0, bird.pet_key, String(table["name"]))
	_glint(bird.global_position, false, 3.0, bird.pet_key, String(table["name"]))


# ---------------------------------------------------------------- the hoard

func hoard(key: String) -> ItemBox:
	if not _hoards.has(key):
		var box: ItemBox = ItemBox.new("hoard:" + key, int((PetRules.table()["companion"] as Dictionary)["hoard_slots"]))
		box.reach_ok = func(who: Node2D) -> bool:
			var bird: WildCorvid = _bird_of(key)
			return who is Player and bird != null and who.global_position.distance_to(bird.global_position) < 90.0
		box.changed.connect(func() -> void:
			if multiplayer.is_server() and multiplayer.get_peers().size() > 0:
				_rpc_hoard.rpc(key, box.slots))
		_hoards[key] = box
	return _hoards[key] as ItemBox


@rpc("authority", "call_remote", "reliable")
func _rpc_hoard(key: String, slots: Array) -> void:
	hoard(key).import_slots(slots)


func open_hoard(player: Player, key: String) -> void:
	BoxWindow.open_box(get_tree(), player, hoard(key), "HORT " + name_of(key))


func can_take(key: String, peer: int) -> bool:
	var other: int = peer_of_companion(key)
	return _pets.has(key) and stage_of(key, peer) >= int((PetRules.table()["companion"] as Dictionary)["stage"]) and (other == 0 or other == peer) and companion_of(peer) != key


func _watched_by_other(point: Vector2, radius: float, except: Player) -> bool:
	for player: Player in Player.all:
		if player != except and player.global_position.distance_to(point) < radius:
			return true
	return false


## Crow: Fundnase, a glint on something near that can be picked. Raven: Warnruf, a flare over a shadow creature that comes near. Neither is a weapon.
func _ability(peer: int, data: Dictionary, bird: WildCorvid, player: Player, cfg: Dictionary) -> void:
	if Time.get_ticks_msec() < int(data["cd"]):
		return
	var spec: Dictionary = (cfg["ability"] as Dictionary)[bird.species] as Dictionary
	var target: Node2D = null
	if bird.species == "crow":
		var best: float = float(spec["range"])
		for node: Node in get_tree().get_nodes_in_group("interactables"):
			var prop: WorldProp = node as WorldProp
			if prop == null or not prop.is_inside_tree() or prop.prompt() == "":
				continue
			var d: float = prop.global_position.distance_to(player.global_position)
			if d > float(spec["min"]) and d < best:
				best = d
				target = prop
	else:
		var best_r: float = float(spec["range"])
		for node: Node in get_tree().get_nodes_in_group("predators"):
			var enemy: Node2D = node as Node2D
			if enemy == null:
				continue
			var d: float = enemy.global_position.distance_to(player.global_position)
			if d < best_r:
				best_r = d
				target = enemy
	if target == null:
		return
	data["cd"] = Time.get_ticks_msec() + int(float(spec["cooldown"]) * 1000.0)
	bird._play_call.rpc(1 if bird.species == "raven" else 0, 1.0)
	var word: String = String(spec["name"])
	if multiplayer.get_peers().size() > 0:
		_rpc_glint.rpc(target.global_position, bird.species == "raven", float(spec["seconds"]), bird.pet_key, word)
	_glint(target.global_position, bird.species == "raven", float(spec["seconds"]), bird.pet_key, word)


@rpc("authority", "call_remote", "reliable")
func _rpc_glint(at: Vector2, warning: bool, seconds: float, key: String, word: String) -> void:
	_glint(at, warning, seconds, key, word)


func _glint(at: Vector2, warning: bool, seconds: float, key: String, word: String) -> void:
	if word != "":
		_flash(key, word, "gift")
	var fx: PetGlint = PetGlint.new()
	fx.warning = warning
	fx.life = seconds
	fx.global_position = at
	get_tree().current_scene.add_child(fx)


## Local, every frame: G. A tap calls the companion, holding it (hold seconds) changes how it behaves.
func _poll_whistle(delta: float) -> void:
	var me: int = multiplayer.get_unique_id()
	if not _comp.has(me) or InputManager.ui_blocking or InputManager.menu_open:
		_whistle_held = -1.0
		return
	var hold: float = float((PetRules.table()["companion"] as Dictionary)["whistle_hold"])
	if Input.is_action_just_pressed("pet_whistle"):
		_whistle_held = 0.0
		_whistle_done = false
	elif _whistle_held >= 0.0 and Input.is_action_pressed("pet_whistle"):
		_whistle_held += delta
		if _whistle_held >= hold and not _whistle_done:
			_whistle_done = true
			ask("mode")
	elif _whistle_held >= 0.0:
		if not _whistle_done:
			ask("come")
		_whistle_held = -1.0


func _watched(point: Vector2, radius: float) -> bool:
	for player: Player in Player.all:
		if player.global_position.distance_to(point) < radius:
			return true
	return false


## Sunrise (host): bonds that were left alone for more than `grace_days` cool a little each day, never below the start of the stage before the one
## reached and never below the registering stage for a registered bird.
func _on_day(day: int) -> void:
	var cfg: Dictionary = PetRules.table()["decay"] as Dictionary
	for key: String in _bonds:
		for peer_text: String in _bonds[key] as Dictionary:
			var data: Dictionary = (_bonds[key] as Dictionary)[peer_text] as Dictionary
			if day - int(data.get("day", day)) <= int(cfg["grace_days"]):
				continue
			var before: float = float(data["bp"])
			var floor_bp: float = PetRules.stage_start(maxi(PetRules.stage_of(before) - 1, 0))
			if _pets.has(key):
				floor_bp = maxf(floor_bp, PetRules.stage_start(int(cfg["registered_floor_stage"])))
			var after: float = minf(before, maxf(before - float(cfg["per_day"]), floor_bp))
			if after < before:
				data["bp"] = after
				_announce(key, peer_text.to_int(), data, after - before, false)


# ---------------------------------------------------------------- save

func export_state() -> Dictionary:
	var comp: Dictionary = {}
	for peer: int in _comp:
		var data: Dictionary = (_comp[peer] as Dictionary).duplicate(true)
		data.erase("cd")
		comp[str(peer)] = data
	var hoards: Dictionary = {}
	for key: String in _hoards:
		var slots: Array = (_hoards[key] as ItemBox).slots
		for stack: Dictionary in slots:
			if not stack.is_empty():
				hoards[key] = slots.duplicate(true)
				break
	return {"bonds": _bonds.duplicate(true), "birds": _pets.duplicate(true), "comp": comp, "hoards": hoards}


func import_state(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_bonds = (data.get("bonds", {}) as Dictionary).duplicate(true)
	_pets = (data.get("birds", {}) as Dictionary).duplicate(true)
	_cooldown.clear()
	_comp.clear()
	var stored: Dictionary = data.get("hoards", {}) as Dictionary
	for key: String in stored:
		hoard(key).import_slots(stored[key] as Array)
	var saved: Dictionary = data.get("comp", {}) as Dictionary
	for peer_text: String in saved:
		var d: Dictionary = (saved[peer_text] as Dictionary).duplicate(true)
		if _pets.has(String(d.get("k", ""))):
			d["cd"] = 0
			_comp[peer_text.to_int()] = d
	for key: String in _pets:
		pet_changed.emit(key)
	companion_changed.emit()
