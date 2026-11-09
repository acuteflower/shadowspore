extends Node
## Headless check of the Mornath quest around the boss arena (data/ground.json arenas[].story, quest `mornath`, ArenaStory / ArenaKnight / MornathHologram):
## before the quest there is no knight and no hologram; the dev start makes the knight appear (and only him, only while the quest runs); he can be inspected only in
## the step `inspect`; the inspection ends with the boss being called; the boss's death ends the quest, the knight dissolves and the hologram stands in the middle;
## E at the hologram calls the boss again without a quest.

var _world: WorldLevel
var _player: Player
var _story: ArenaStory


func _ready() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	print("MORNATH QUEST: FAILED - ", message)
	get_tree().quit(1)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _press_interact() -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = "interact"
	down.pressed = true
	Input.parse_input_event(down)
	var up: InputEventAction = InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	Input.parse_input_event(up)


func _until_pressing(cond: Callable, max_frames: int) -> bool:
	for i: int in max_frames:
		if cond.call():
			return true
		if i % 25 == 0:
			_press_interact()
		await get_tree().physics_frame
	return false


func _until(cond: Callable, max_frames: int) -> bool:
	for i: int in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return false


func _run() -> void:
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _world._players.get_child(0) as Player
	_player.health.floor_value = 1.0
	if not _world.has_arena_story():
		return _fail("the arena has no story node")
	for child: Node in _world.get_children():
		if child is ArenaStory:
			_story = child as ArenaStory
	await _frames(40)
	# 1. before the quest: nothing
	if _story.knight.shown or _story.knight.visible:
		return _fail("the knight is there before the quest")
	if _story.hologram.active:
		return _fail("the hologram is there before the quest")
	if _player.quests.is_active("mornath"):
		return _fail("the quest runs on its own")
	# 2. dev start: the knight appears, the hologram does not
	_world.debug_mornath(_player, false)
	await _frames(40)
	if not _player.quests.is_active("mornath"):
		return _fail("the dev start did not start the quest")
	if not _story.knight.shown:
		return _fail("the knight did not appear with the quest")
	if _story.hologram.active:
		return _fail("the hologram shows while the quest runs")
	if _story.knight.prompt() != "":
		return _fail("the knight can be inspected before the step `inspect` (step %s)" % _player.quests.active_step_id("mornath"))
	# 3. at the pillar: the step `inspect` opens
	_player.quests.set_flag("mornath_arena_reached") ## harmless flag; the reach step needs her position
	_player.global_position = _story.knight.global_position + Vector2(0, 40)
	await _frames(40)
	if _player.quests.active_step_id("mornath") != "inspect":
		return _fail("the quest is at `%s`, not at `inspect`" % _player.quests.active_step_id("mornath"))
	if _story.knight.prompt() != "UNTERSUCHEN":
		return _fail("no prompt at the knight in the step inspect")
	if not get_tree().get_nodes_in_group("bosses").is_empty():
		return _fail("a boss is there before the inspection")
	# 4. the inspection: the scene runs, ends with the flag and the boss is called
	_story.knight.interact(_player)
	if _player.get_node_or_null("MornathInspectScene") == null:
		return _fail("the inspection did not start")
	for i: int in 60 * 20: ## the dialogue box waits for input: press E now and then, as the player would
		await get_tree().physics_frame
		if i % 25 == 0:
			_press_interact()
		if _player.quests.active_step_id("mornath") == "fight":
			break
	if _player.quests.active_step_id("mornath") != "fight":
		return _fail("the inspection never moved the quest to `fight` (step `%s`)" % _player.quests.active_step_id("mornath"))
	if not await _until(func() -> bool: return not get_tree().get_nodes_in_group("bosses").is_empty(), 60 * 4):
		return _fail("the boss was not called")
	if _player.story_lock:
		return _fail("she is still held after the inspection")
	var boss: SkyCleaver = get_tree().get_nodes_in_group("bosses")[0] as SkyCleaver
	if _story.hologram.active:
		return _fail("the hologram shows while the boss is there")
	# 5. the boss dies after the fight had reached the last phase (checkpoint 3, two pillars broken, the last one burning): the quest ends, the knight dissolves, the hologram comes
	var pillars: Array[ArenaPillar] = []
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		if (node as ArenaPillar).arena == _story.arena_id:
			pillars.append(node as ArenaPillar)
	pillars.sort_custom(func(a: ArenaPillar, b: ArenaPillar) -> bool: return a.index < b.index)
	_story.level._arena_phase[_story.arena_id] = 2
	pillars[0].break_silently()
	pillars[1].break_silently()
	pillars[pillars.size() - 1].ignite(0.0)
	boss._health.kill()
	if not await _until(func() -> bool: return _player.quests.is_finished("mornath"), 60 * 3):
		return _fail("the quest did not finish when the boss fell")
	if not await _until(func() -> bool: return not _story.knight.shown, 60 * 12):
		return _fail("the knight did not dissolve")
	if not await _until(func() -> bool: return get_tree().get_nodes_in_group("bosses").is_empty() or not _story.level.arena_boss_present(_story.arena_id), 60 * 30):
		return _fail("the dead boss never left")
	if not await _until_pressing(func() -> bool: return _story.hologram.active, 60 * 30): ## her last words wait for E
		return _fail("the hologram did not appear after the quest")
	# 6. the hologram calls him again, no quest
	await _frames(120)
	if _story.hologram.prompt() != "MORNATH RUFEN":
		return _fail("no prompt at the hologram (`%s`)" % _story.hologram.prompt())
	_story.hologram.interact(_player)
	if not await _until_pressing(func() -> bool: return _story.level.arena_boss_present(_story.arena_id), 60 * 20): ## first touch: her thoughts wait for E
		return _fail("the hologram did not call the boss back")
	if _player.story_lock:
		return _fail("she is still held after calling him")
	# 7. the second fight really starts from the beginning: phase 1, full health, every pillar whole and cold
	var again: SkyCleaver = null
	for node: Node in get_tree().get_nodes_in_group("bosses"):
		if node is SkyCleaver and not node.is_queued_for_deletion() and (node as SkyCleaver).arena == _story.arena_id:
			again = node as SkyCleaver
	if again == null:
		return _fail("no second boss found")
	if again.start_phase != 0:
		return _fail("the second fight starts at phase %d, not at the beginning" % again.start_phase)
	if not is_equal_approx(again._health.current, again._health.max_health):
		return _fail("the second boss is not at full health (%f / %f)" % [again._health.current, again._health.max_health])
	for pillar: ArenaPillar in pillars:
		if pillar.broken:
			return _fail("pillar %d is still broken in the second fight" % pillar.index)
		if pillar.fury() > 0.0:
			return _fail("pillar %d still burns in the second fight" % pillar.index)
	await _frames(240)
	if again.fight != null and again.fight.phase != 0:
		return _fail("the second fight jumped to phase %d" % again.fight.phase)
	for pillar: ArenaPillar in pillars:
		if pillar.broken:
			return _fail("pillar %d broke at the start of the second fight" % pillar.index)
	print("MORNATH QUEST: ok")
	get_tree().quit(0)
