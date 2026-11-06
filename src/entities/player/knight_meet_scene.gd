class_name KnightMeetScene
extends Node
## The meeting at the quarry (story step `meet`, event `meet:knight`, started by `WorldLevel.start_knight_meet` when she comes close to the knight). A child of the player:
## she is held (`story_lock`) and walks slowly, limping, to a spot beside him (`Player.auto_walk`); he stops mining and turns to her; the full dialogues `knight_meet_a`
## (he says who he is: the flag `knows_adventurer` lifts the "???" and shows his name) and `knight_meet_b`; he puts his pickaxe down against the stone (his `set` clip,
## the leaning pick prop appears when he lets go of it); then the speech box lines `knight_leave` ("come back to the hut") and control returns, the flag
## `knight_met` starts the next step (follow him). The dialogue texts are placeholders. Solo / host only for now.

var _player: Player
var _quarry: Quarry


func start(player: Player, quarry: Quarry) -> void:
	_player = player
	_quarry = quarry
	_run()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _dialogue(id: String) -> void:
	for child: Node in _player.get_children():
		var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
		if box != null:
			box.start(id)
			await box.finished
			return


var _put_done: bool = false


## He lays the pick against the stone (his `set` clip; the leaning pick appears when he lets go) and stands, facing her.
func _put_down() -> void:
	var knight: Adventurer = _quarry.knight
	knight.play("set", Vector2.LEFT)
	await _wait(0.62)
	_quarry.show_pick(true)
	await knight.clip_done
	knight.play("stand", _player.global_position - knight.global_position)
	_put_done = true


func _run() -> void:
	var knight: Adventurer = _quarry.knight
	_player.story_lock = true
	InputManager.ui_blocking = true
	var goal: Vector2 = knight.global_position + Vector2(32, 14)
	_player.auto_walk = goal
	var noticed: bool = false
	var waited: float = 0.0
	while waited < 8.0 and _player.global_position.distance_to(goal) > 5.0:
		if not noticed and _player.global_position.distance_to(knight.global_position) < 80.0:
			noticed = true ## he has heard her: he puts the pick down against the stone while she comes closer
			_put_down()
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if _player.global_position.distance_to(goal) > 14.0:
		_player.global_position = goal ## stuck on something: she is there
	_player.auto_walk = Vector2.INF
	_player.facing = (knight.global_position - _player.global_position).normalized()
	if not noticed:
		noticed = true
		_put_down()
	while not _put_done:
		await get_tree().physics_frame
	knight.face(_player.global_position - knight.global_position)
	await _wait(0.5)
	await _dialogue("knight_meet_a")
	_player.quests.set_flag("knows_adventurer")
	await _dialogue("knight_meet_b")
	await _wait(0.3)
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		await box.play("knight_leave")
	_player.story_lock = false
	InputManager.ui_blocking = false
	_player.quests.set_flag("knight_met")
	queue_free()
