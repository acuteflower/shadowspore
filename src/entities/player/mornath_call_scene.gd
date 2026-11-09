class_name MornathCallScene
extends Node
## She lays a hand on the hologram of Mornath in the middle of the arena (`ArenaStory.hologram_use`, no quest needed): the first time she wonders about it (dialogue
## `mornath_again`, flag `mornath_hologram_seen`); then the picture tears apart (`MornathHologram.touched`), a riser swells, the camera shakes, and the boss is called
## (`WorldLevel.request_arena_boss`: the host lets him fly in again, the entrance screen is the old one). A child of the local player.

var _player: Player
var _story: ArenaStory


func start(player: Player, story: ArenaStory) -> void:
	_player = player
	_story = story
	_run()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _run() -> void:
	_player.story_lock = true
	InputManager.ui_blocking = true
	_player.facing = (_story.hologram.global_position - _player.global_position).normalized()
	if not _player.quests.has_flag("mornath_hologram_seen"):
		_player.quests.set_flag("mornath_hologram_seen")
		for child: Node in _player.get_children():
			var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
			if box != null:
				box.start("mornath_again")
				await box.finished
				break
	_story.hologram.touched()
	_player.add_shake(2.0)
	await _wait(1.7)
	_player.story_lock = false
	InputManager.ui_blocking = false
	if is_instance_valid(_player) and _player.health.current > 0.0:
		_story.level.request_arena_boss(_story.arena_id, _player.global_position)
	queue_free()
