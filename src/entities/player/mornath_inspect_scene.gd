class_name MornathInspectScene
extends Node
## She searches the dead knight at the arena's east pillar (quest `mornath`, step `inspect`; started by `ArenaStory.inspect` through `WorldLevel.start_mornath_inspect`).
## A child of the local player. She is held (`story_lock`) and walks to the spot in front of him (`Player.auto_walk`), stoops over him (the picking animation, the
## clink of the plate), speaks her thoughts (dialogue `mornath_inspect`); then a scream comes from above: the black in him flares, the ground shakes, she gasps
## (bark `mornath_cry`), the flag `mornath_inspected` moves the quest on and the boss is called (`WorldLevel.request_arena_boss`: the host lets him fly in, the entrance
## screen is the old one). Control returns before he arrives. All texts are placeholders.

var _player: Player
var _story: ArenaStory


func start(player: Player, story: ArenaStory) -> void:
	_player = player
	_story = story
	_run()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _dialogue(id: String) -> void:
	var runner: BubbleRunner = BubbleRunner.find(_player)
	if runner != null:
		await runner.play(id, _story.knight)


func _release() -> void:
	_player.auto_walk = Vector2.INF
	_player.auto_walk_factor = -1.0
	_player.story_lock = false
	InputManager.ui_blocking = false


func _run() -> void:
	var knight: ArenaKnight = _story.knight
	_player.story_lock = true
	InputManager.ui_blocking = true
	var goal: Vector2 = knight.stand_point()
	_player.auto_walk_factor = 0.5
	_player.auto_walk = goal
	var waited: float = 0.0
	while waited < 8.0 and _player.global_position.distance_to(goal) > 5.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if not is_instance_valid(_player) or _player.health.current <= 0.0:
			_release()
			queue_free()
			return
	if _player.global_position.distance_to(goal) > 14.0:
		_player.global_position = goal ## stuck on something: she is there
	_player.auto_walk = Vector2.INF
	_player.auto_walk_factor = -1.0
	var toward: Vector2 = (knight.global_position + ArenaKnight.BODY - _player.global_position).normalized()
	_player.facing = toward
	await _wait(0.3)
	_player.begin_pick(toward, knight.clink) ## she goes through his things: the plate clinks when her hand closes on it
	await _wait(1.25)
	await _dialogue("mornath_inspect")
	# the scream from above
	knight.flare(1.0)
	_player.add_shake(3.0)
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.play("mornath_cry")
	await _wait(0.9)
	_player.quests.set_flag("mornath_inspected")
	_release()
	_story.level.request_arena_boss(_story.arena_id, _player.global_position)
	await _wait(2.4)
	if box != null and is_instance_valid(_player) and _player.health.current > 0.0:
		box.play("mornath_echo")
	queue_free()
