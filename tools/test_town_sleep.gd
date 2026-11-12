extends Node
## Regression: the town quest's night ("RUHE DICH AUS, BIS ES MORGEN WIRD"): she sleeps in the hut's bed, wakes up, gets up and walks out through the door.
## Nothing may stay black or locked. Run with `--fixed-fps 60`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN SLEEP FAILED: ", what)


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
	var hut: Hut = world.hut_node()
	var quests: QuestComponent = player.quests
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	quests.import_data({"active": {}, "done": ["find_help", "lumberjack", "rebuild_hut"], "flags": {"rebuild_done": true, "knows_adventurer": true, "hud_unlocked": true, "day2_started": true, "left_hut": true}})
	quests.start("town_start")
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(150)
	_check(town.founded, "the town is founded")
	# she goes in through the real door
	interiors.use_door(player, hut.doorway)
	await _frames(150)
	var room: Interior = interiors.interior("hut")
	_check(Interiors.slot_at(player.global_position) >= 0, "she is inside the hut")
	_check(not player.story_lock and not InputManager.ui_blocking, "the door released her inside")
	TimeManager.set_time(0.9)
	var bed: StorySpot = room.get_node("BedRest") as StorySpot
	bed.interact(player)
	await _frames(420)
	var wake: WakeScene = player.get_node_or_null("WakeScene") as WakeScene
	_check(wake != null, "she wakes up")
	if wake == null:
		print("TOWN SLEEP: ", "FAILED" if not _ok else "ok")
		get_tree().quit()
		return
	await _frames(600) ## the eyes open
	_check(wake._state == WakeScene.State.WAITING, "she waits for E (state %d)" % wake._state)
	wake._begin_getup()
	await _frames(900)
	_check(player.get_node_or_null("WakeScene") == null, "the wake-up is over")
	_check(not player.story_lock and not InputManager.ui_blocking, "she is free after getting up")
	_check(player.intro == null, "no intro state left")
	# out through the door
	player.global_position = room.door.global_position + Vector2(0, -10)
	interiors.use_door(player, room.door)
	await _frames(40)
	print("cover during the way out: ", interiors._cover, " busy ", interiors._busy)
	await _frames(200)
	_check(interiors._cover <= 0.001, "the dark opened again (cover %f)" % interiors._cover)
	_check(Interiors.slot_at(player.global_position) < 0, "she is outside again")
	_check(not interiors._busy and not player.story_lock, "the door released her")
	var bubbles: BubbleRunner = BubbleRunner.find(player)
	_check(bubbles != null and bubbles.is_active(), "Valdric's talk starts only after the dark has opened")
	if bubbles != null and bubbles.is_active():
		bubbles.skip_all()
		await _frames(10)
	_check(not InputManager.ui_blocking and not get_tree().paused, "everything is released after the talk")
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl: CanvasLayer = layer as CanvasLayer
		for child: Node in cl.get_children():
			if child is ColorRect and cl.visible and (child as ColorRect).visible and (child as ColorRect).color.a > 0.9 and (child as ColorRect).material == null:
				print("opaque layer: ", cl.get_path(), " layer ", cl.layer)
	print("TOWN SLEEP: ", "ok" if _ok else "FAILED")
	get_tree().quit()
