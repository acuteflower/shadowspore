extends Node
## The lake witch's entry quest "Der Ring am See" (docs/seehexe_konzept.md 8, step 3): the board notice needs Esma's quest and level 10; the house is dark
## and locked, a knock gives three Seeglimmer, the weak stones are fed, after the second the shadows climb out of the void, the third waits for them, the
## ring wakes and opens the door; inside ILVA gives the staff and two stones; socketing and the first cast; the last talk ends the quest. Also: a reload in
## the middle of the feeding gets its stones back, and the developer jumps. Prints `LAKE QUEST OK`.
var _ok: bool = true
var _checks: int = 0


func _check(name: String, value: bool) -> void:
	_checks += 1
	if not value:
		_ok = false
		print("FAILED: ", name)


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Runs every dialogue that is open to its end.
func _close_dialogue() -> void:
	for _i: int in 200:
		var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
		if box == null or not box.is_active():
			return
		box._end()
		await _frames(2)


func _run() -> void:
	# the notice on the board
	var entry: Dictionary = {}
	for raw: Variant in BoardRules.story_entries():
		if String((raw as Dictionary).id) == "lake_witch_notice":
			entry = raw as Dictionary
	var quests: Dictionary = DataRegistry.table("quests")
	var no: Callable = func(_x: String) -> bool: return false
	var yes: Callable = func(x: String) -> bool: return x == "spiegelhexe"
	_check("the notice exists", not entry.is_empty() and quests.has("lake_witch"))
	_check("not before Esma's quest", not BoardRules.story_due(entry, quests, no, no, 30))
	_check("not below level 10", not BoardRules.story_due(entry, quests, yes, no, 9))
	_check("from level 10 after Esma", BoardRules.story_due(entry, quests, yes, no, 10))
	# the world
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	player.health.heal_full()
	var hut: Hut = world.get_node("Hut_lake_hut") as Hut
	var ring: WardRing = world.get_node("WardRing_lake_hut") as WardRing
	var story: LakeWitchStory = get_tree().get_first_node_in_group("lake_witch_story") as LakeWitchStory
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	_check("the story node is there", story != null and ring != null)
	_check("the ring sleeps at first", not ring.awake and not WardRing.shelters(hut.position))
	await _wait(0.4)
	_check("the door is locked while it sleeps", hut.doorway.locked)
	# lw_lake
	player.quests.start("lake_witch")
	await _frames(2)
	_check("the quest runs", player.quests.has_active_step("lw_lake"))
	await _close_dialogue()
	player.global_position = hut.exit_position + Vector2(60, 40)
	await _wait(0.6)
	await _close_dialogue()
	_check("the house was seen", player.quests.has_active_step("lw_door"))
	# lw_door
	var knock: StorySpot = hut.get_node("Knock") as StorySpot
	player.global_position = hut.exit_position
	await _frames(4)
	_check("ANKLOPFEN at the door", knock.prompt() == "ANKLOPFEN")
	var glimmer_before: int = player.inventory.count_item("lake_glimmer")
	knock.interact(player)
	await _frames(4)
	await _close_dialogue()
	await _frames(4)
	_check("she gave three Seeglimmer", player.inventory.count_item("lake_glimmer") == glimmer_before + 3)
	_check("now: feed the stones", player.quests.has_active_step("lw_feed"))
	# lw_feed: two stones
	var spots: Array[WardFeedSpot] = []
	for i: int in ring.feed:
		spots.append(ring.get_node("Feed%d" % i) as WardFeedSpot)
	_check("three weak stones", spots.size() == 3)
	for k: int in 2:
		player.global_position = spots[k].global_position + Vector2(0, 14)
		await _frames(4)
		_check("NÄHREN at stone %d" % k, spots[k].prompt() == "NÄHREN")
		spots[k].interact(player)
		await _wait(1.3)
	_check("two stones fed", ring.fed.size() == 2 and player.inventory.count_item("lake_glimmer") == glimmer_before + 1)
	_check("the shadows came", ring.ambush == WardRing.AMBUSH_RUNNING and ring._ambushers.size() == 3)
	await _close_dialogue()
	player.global_position = spots[2].global_position + Vector2(0, 14)
	await _frames(4)
	_check("the third waits for the shadows", spots[2].prompt() == "ERST DIE SCHATTEN")
	ring.request_feed(ring.feed[2])
	await _frames(2)
	_check("the host refuses it too", ring.fed.size() == 2)
	await _frames(2)
	_check("two task flags", player.quests.has_flag("lake_witch_fed_a") and player.quests.has_flag("lake_witch_fed_b"))
	# a reload in the middle: the stones come back from the flags (the fight was not won: one stone again)
	ring._rpc_quest(PackedInt32Array(), WardRing.AMBUSH_RUNNING)
	story._restored = false
	await _wait(0.4)
	_check("reload: the first stone lit again", ring.fed.size() == 1)
	ring._rpc_quest(PackedInt32Array([ring.feed[0], ring.feed[1]]), WardRing.AMBUSH_RUNNING)
	# the fight
	for body: Node2D in ring._ambushers.duplicate():
		if is_instance_valid(body):
			var health: HealthComponent = ring._health_of(body)
			if health != null:
				health.take_damage(99999.0, body.global_position + Vector2(10, 0), 0.0, 1)
	await _wait(0.6)
	await _close_dialogue()
	_check("the shadows are gone", ring.ambush == WardRing.AMBUSH_DONE and player.quests.has_flag("lake_witch_shadows"))
	await _frames(4)
	_check("now the third stone", spots[2].prompt() == "NÄHREN")
	spots[2].interact(player)
	await _wait(1.3)
	_check("the ring woke", ring.awake and WardRing.shelters(hut.position))
	await _wait(2.4)
	await _close_dialogue()
	_check("the door is open", not hut.doorway.locked)
	_check("now: enter", player.quests.has_active_step("lw_enter"))
	# lw_enter, lw_meet
	player.global_position = hut.exit_position
	await _frames(4)
	interiors.use_door(player, hut.doorway)
	await _wait(1.8)
	_check("inside, the meeting step", player.quests.has_active_step("lw_meet"))
	var ilva: InteriorResident = null
	for node: Node in get_tree().get_nodes_in_group("quest_actors"):
		if node is InteriorResident and (node as InteriorResident).sid == "lake_witch":
			ilva = node as InteriorResident
	TimeManager.set_time(0.35)
	await _frames(30)
	player.global_position = ilva.global_position + Vector2(0, 40)
	await _frames(4)
	_check("she wants to talk", ilva.prompt() == "SPRECHEN")
	ilva.interact(player)
	await _frames(4)
	await _close_dialogue()
	await _wait(0.4)
	_check("met her", player.quests.has_flag("lake_witch_met") and player.quests.has_flag("knows_lake_witch"))
	_check("the staff and two stones", player.inventory.has_item("staff_hag_elm") and player.inventory.has_item("crystal_banish_1") and player.inventory.has_item("gem_lens_1"))
	_check("now: socket", player.quests.has_active_step("lw_socket"))
	# lw_socket
	for slot: Variant in player.inventory.slots:
		var stack: Dictionary = slot as Dictionary
		if String(stack.get("id", "")) == "staff_hag_elm":
			stack["sp"] = "crystal_banish_1"
			stack["gm"] = "gem_lens_1"
	await _wait(0.4)
	_check("socketed", player.quests.has_active_step("lw_cast"))
	# lw_cast
	player.spells.cast_done.emit("crystal_banish_1")
	await _frames(4)
	_check("the first spell", player.quests.has_active_step("lw_end"))
	await _close_dialogue()
	player.global_position = ilva.global_position + Vector2(0, 40)
	await _frames(4)
	_check("the last talk", ilva.prompt() == "SPRECHEN")
	ilva.interact(player)
	await _frames(4)
	await _close_dialogue()
	await _frames(6)
	_check("the quest is finished", player.quests.is_finished("lake_witch"))
	_check("afterwards: her shop again", ilva.prompt() == "HANDELN" or ilva.prompt() == "ANSPRECHEN")
	# the developer jumps
	story.debug_start()
	await _wait(0.5) ## the reset travels as RPCs and the quest restarts a frame later
	_check("dev start: asleep and running", not ring.awake and (player.quests.has_active_step("lw_lake") or player.quests.has_active_step("lw_door")) and ring.fed.is_empty()) ## she lands within sight of the house
	story.debug_known()
	await _wait(2.0) ## the task step is checked four times a second, then the rest follows
	_check("dev known: awake and done", ring.awake and player.quests.is_finished("lake_witch"))
	print("%d checks" % _checks)
	print("LAKE QUEST OK" if _ok else "LAKE QUEST FAILED")
	get_tree().quit(0 if _ok else 1)
