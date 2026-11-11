class_name LakeWitchStory
extends Node
## The lake witch's entry quest "Der Ring am See" (docs/seehexe_konzept.md 8; quest `lake_witch` in data/quests.json, hung on the quest board from level 10
## after Esma's quest `spiegelhexe`, data/board.json story). A node of `WorldLevel` beside the lake witch's house and its `WardRing`; it does what no step type
## does by itself, for the local player only (quests are their owner's):
##  - lw_lake:   the house comes into view -> flag `lake_witch_seen`;
##  - lw_door:   while the ring sleeps the door is locked; a `StorySpot` "ANKLOPFEN" plays `lw_door` (Ilva behind the door, gives three Seeglimmer);
##  - lw_feed:   the ring's `fed` / `ambush` become the task flags `lake_witch_fed_a/b/c` and `lake_witch_shadows`; barks when the void opens and the ring wakes;
##  - lw_socket: the staff in her bag holds a spell crystal and a gem -> `lake_witch_socketed`; lw_cast: her first spell -> `lake_witch_cast`.
## The talk steps are `InteriorResident` (quest step `talk_to` + `talk`). The host restores the ring's quest state from the host player's flags (nothing of
## `fed` is saved). Dev: `debug_start` / `debug_known` (pause menu ENTWICKLER).

const FEED_FLAGS: Array[String] = ["lake_witch_fed_a", "lake_witch_fed_b", "lake_witch_fed_c"]
const SEEN_RANGE: float = 260.0

var hut: Hut
var ring: WardRing
var _knock: StorySpot
var _clock: float = 0.0
var _ambush_seen: int = 0
var _restored: bool = false
var _cast_hooked: SpellComponent


func setup(the_hut: Hut, the_ring: WardRing) -> void:
	hut = the_hut
	ring = the_ring


func _ready() -> void:
	name = "LakeWitchStory"
	add_to_group("lake_witch_story")
	if ring != null:
		ring.changed.connect(_on_ring_changed)
		ring.quest_changed.connect(_on_quest_changed)
	_knock = StorySpot.new()
	_knock.name = "Knock"
	_knock.label = "ANKLOPFEN"
	_knock.step = "lw_door"
	_knock.radius = 16.0
	_knock.height = 56.0
	_knock.position = Vector2(0, 6)
	_knock.use = func(player: Player) -> void:
		var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
		if world != null:
			world.play_story_dialogue(player, "lw_door")
	if hut != null:
		hut.add_child(_knock)
	_lock_door()


func _local() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


func _lock_door() -> void:
	if hut != null and hut.doorway != null and ring != null:
		hut.doorway.locked = not ring.awake


func _on_ring_changed(awake: bool) -> void:
	_lock_door()
	var player: Player = _local()
	if awake and player != null and player.quests != null and player.quests.is_active("lake_witch"):
		_bark("lw_woken")


func _on_quest_changed() -> void:
	var player: Player = _local()
	if player == null or player.quests == null or not player.quests.is_active("lake_witch"):
		return
	if ring.ambush == WardRing.AMBUSH_RUNNING and _ambush_seen != WardRing.AMBUSH_RUNNING:
		_bark("lw_ambush")
	_ambush_seen = ring.ambush
	_sync_flags(player)


func _bark(id: String) -> void:
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.play(id)


## The ring's shared state becomes the local player's task flags.
func _sync_flags(player: Player) -> void:
	if ring == null or not player.quests.has_active_step("lw_feed"):
		return
	for k: int in mini(ring.feed.size(), FEED_FLAGS.size()):
		if ring.fed.has(ring.feed[k]) or ring.awake:
			player.quests.set_flag(FEED_FLAGS[k])
	if ring.ambush == WardRing.AMBUSH_DONE or ring.awake:
		player.quests.set_flag("lake_witch_shadows")


## Host, once: a loaded game in the middle of the feeding gets its lit stones back (the host player's flags say which).
func _restore() -> void:
	_restored = true
	if not multiplayer.is_server() or ring == null or ring.awake:
		return
	var player: Player = _local()
	if player == null or player.quests == null or not player.quests.is_active("lake_witch"):
		return
	var fed: Array[int] = []
	for k: int in mini(ring.feed.size(), FEED_FLAGS.size()):
		if player.quests.has_flag(FEED_FLAGS[k]):
			fed.append(ring.feed[k])
	var ambush: int = WardRing.AMBUSH_DONE if player.quests.has_flag("lake_witch_shadows") else WardRing.AMBUSH_NONE
	if fed.size() >= ring.feed.size() - 1 and ambush == WardRing.AMBUSH_NONE:
		fed.resize(ring.feed.size() - 2) ## the fight was not won: the second stone has to be fed again (and the shadows come)
	if not fed.is_empty() or ambush != WardRing.AMBUSH_NONE:
		ring.restore_quest(fed, ambush)


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = 0.25
	var player: Player = _local()
	if player == null or player.quests == null:
		return
	if not _restored:
		_restore()
	_lock_door()
	if not player.quests.is_active("lake_witch"):
		return
	if player.quests.has_active_step("lw_lake") and hut != null and player.global_position.distance_to(hut.global_position) < SEEN_RANGE:
		player.quests.set_flag("lake_witch_seen")
	_sync_flags(player)
	if player.quests.has_flag("lake_witch_met") and not player.quests.has_flag("knows_lake_witch"):
		player.quests.set_flag("knows_lake_witch") ## she told her name: later talks show it
	if player.quests.has_active_step("lw_socket"):
		for stack: Dictionary in _staves(player):
			if String(stack.get("sp", "")) != "" and String(stack.get("gm", "")) != "":
				player.quests.set_flag("lake_witch_socketed")
	if player.spells != null and player.spells != _cast_hooked:
		_cast_hooked = player.spells
		player.spells.cast_done.connect(_on_cast)


func _on_cast(_spell: String) -> void:
	var player: Player = _local()
	if player != null and player.quests != null and player.quests.has_active_step("lw_cast"):
		player.quests.set_flag("lake_witch_cast")


## Every staff stack she carries (bag, hotbar).
func _staves(player: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stack: Variant in player.inventory.slots:
		var s: Dictionary = stack as Dictionary
		if String(s.get("id", "")) == "staff_hag_elm":
			out.append(s)
	return out


# ---------- developer jumps (pause menu ENTWICKLER) ----------

## Starts (or restarts) the quest for the local player, the ring asleep and unfed, and puts her on the path to the lake.
func debug_start() -> void:
	var player: Player = _local()
	if player == null or not multiplayer.is_server():
		return
	ring.restore_quest([], WardRing.AMBUSH_NONE)
	ring.set_awake(false, false)
	_ambush_seen = WardRing.AMBUSH_NONE
	player.quests.restart("lake_witch")
	player.request_teleport(hut.global_position + Vector2(140, -40))


## Everything of the quest done: the ring awake, the staff with a splinter and a cut stone in the bag, the quest finished; she stands at the door.
func debug_known() -> void:
	var player: Player = _local()
	if player == null or not multiplayer.is_server():
		return
	ring.set_awake(true, false)
	if not player.quests.is_finished("lake_witch"):
		if not player.quests.is_active("lake_witch"):
			player.quests.start("lake_witch")
		for flag: String in ["lake_witch_seen", "lake_witch_door", "lake_witch_fed_a", "lake_witch_fed_b", "lake_witch_fed_c", "lake_witch_shadows", "entered_lake_hut",
				"lake_witch_met", "knows_lake_witch", "lake_witch_socketed", "lake_witch_cast", "lake_witch_done"]:
			player.quests.set_flag(flag)
	for item: String in ["staff_hag_elm", "crystal_banish_1", "gem_lens_1"]:
		if not player.inventory.has_item(item):
			player.inventory.give(item, 1)
	player.request_teleport(hut.exit_position + Vector2(0, 10))
