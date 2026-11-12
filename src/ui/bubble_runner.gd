class_name BubbleRunner
extends Node
## Plays non-fullscreen dialogues as overhead in-game speech bubbles (`SettlerBubble`),
## falling back to `SpeechBox` when the speaker is unseen, off-screen, or too far away.

signal finished

const MAX_OVERHEAD_DIST: float = 250.0

var _player: Player
var _speech: SpeechBox
var _active: bool = false
var _gen: int = 0
var _current_bubble: SettlerBubble = null
var _armed_at: float = 0.0


static func find(player: Node) -> BubbleRunner:
	if player == null:
		return null
	for child: Node in player.get_children():
		var runner: BubbleRunner = child.get_node_or_null("BubbleRunner") as BubbleRunner
		if runner != null:
			return runner
	return null


func _ready() -> void:
	add_to_group("bubble_runner")


func bind(player: Player, speech: SpeechBox) -> void:
	_player = player
	_speech = speech


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if _armed_at > 0.0:
		_armed_at = maxf(0.0, _armed_at - delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _armed_at > 0.0 or event.is_echo():
		return
	var pressed: bool = event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")
	if not pressed:
		return
	if _current_bubble != null and is_instance_valid(_current_bubble) and _current_bubble.is_showing():
		if _current_bubble.finish_or_advance():
			get_viewport().set_input_as_handled()
			_armed_at = 0.08
	elif _speech != null and _speech.is_speaking():
		if _speech.advance_or_close():
			get_viewport().set_input_as_handled()
			_armed_at = 0.08


func skip_all() -> void:
	_gen += 1
	if _current_bubble != null and is_instance_valid(_current_bubble):
		_current_bubble.clear_now()
		_current_bubble.queue_free()
		_current_bubble = null
	if _speech != null:
		_speech.skip_all()
	if _active:
		_active = false
		finished.emit()


## Plays a `data/dialogue.json` entry line by line via overhead bubbles (or `SpeechBox` fallback).
func play(id: String, anchor: Node2D = null) -> void:
	var entry: Dictionary = DataRegistry.get_entry("dialogue", id)
	var lines: Array = entry.get("lines", []) as Array
	if entry.is_empty() or lines.is_empty():
		finished.emit()
		return
	_gen += 1
	var my_gen: int = _gen
	if _current_bubble != null and is_instance_valid(_current_bubble):
		_current_bubble.clear_now()
		_current_bubble.queue_free()
		_current_bubble = null
	_active = true
	_armed_at = 0.14
	for raw: Variant in lines:
		if _gen != my_gen or not is_inside_tree():
			break
		var line: Dictionary = raw as Dictionary
		var speaker: String = _resolve_speaker(line)
		var text: String = String(line.get("text", ""))
		if text == "":
			continue
		var hold: float = float(line.get("hold", -1.0))
		var target: Node2D = _find_speaker_node(speaker, anchor)
		if target != null and _can_overhead(target):
			await _show_overhead(target, speaker, text, hold, my_gen)
		elif _speech != null:
			await _speech.speak(speaker, text, hold)
	if _gen == my_gen:
		_active = false
		finished.emit()


## Shows a single ad-hoc line over `anchor` (e.g. Settler everyday chat), or `SpeechBox` fallback.
func say_line(speaker: String, text: String, anchor: Node2D = null, hold: float = -1.0) -> void:
	if text == "":
		return
	_gen += 1
	var my_gen: int = _gen
	if _current_bubble != null and is_instance_valid(_current_bubble):
		_current_bubble.clear_now()
		_current_bubble.queue_free()
		_current_bubble = null
	_active = true
	_armed_at = 0.14
	if anchor != null and _can_overhead(anchor):
		await _show_overhead(anchor, speaker, text, hold, my_gen)
	elif _speech != null:
		await _speech.speak(speaker, text, hold)
	if _gen == my_gen:
		_active = false
		finished.emit()


func _resolve_speaker(line: Dictionary) -> String:
	var speaker: String = String(line.get("speaker", "ELLIE"))
	if line.has("known_flag") and _player != null and _player.quests != null:
		if _player.quests.has_flag(String(line.known_flag)):
			speaker = String(line.get("known_name", speaker))
	return speaker


func _find_speaker_node(speaker: String, anchor: Node2D) -> Node2D:
	var key: String = speaker.to_upper()
	if key == "ELLIE":
		return _player
	if key.contains("STIMME") or key == "???":
		return null
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager if is_inside_tree() else null
	if key == "VALDRIC" or key == "RITTER":
		if town != null:
			var node: Node2D = town.person_node("valdric")
			if node != null:
				return node
		for actor: Node in get_tree().get_nodes_in_group("quest_actors"):
			if actor is Node2D and String(actor.get("actor_id")) == "knight":
				return actor as Node2D
		return anchor
	if key == "GUSTAV" or key == "FREMDER":
		for actor: Node in get_tree().get_nodes_in_group("story_gustav"):
			if actor is Node2D:
				return actor as Node2D
		if town != null:
			var node: Node2D = town.person_node("gustav")
			if node != null:
				return node
		return anchor
	if key == "TORBEN" or key == "SCHMIED":
		for actor: Node in get_tree().get_nodes_in_group("story_torben"):
			if actor is Node2D:
				return actor as Node2D
		if town != null:
			var node: Node2D = town.person_node("torben")
			if node != null:
				return node
		return anchor
	for resident_id: String in ["maren", "esma", "ilva", "helena"]:
		if key == resident_id.to_upper():
			if town != null:
				var node: Node2D = town.person_node(resident_id)
				if node != null:
					return node
			return anchor
	return anchor


func _can_overhead(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if not target.visible:
		return false
	if _player != null and is_instance_valid(_player):
		if target.global_position.distance_to(_player.global_position) > MAX_OVERHEAD_DIST:
			return false
	return true


func _show_overhead(target: Node2D, speaker: String, text: String, hold: float, my_gen: int) -> void:
	var bubble: SettlerBubble = SettlerBubble.new()
	bubble.name = "StoryBubble"
	var offset: Vector2 = Vector2(0.0, -54.0)
	if target is Player:
		offset = Vector2(0.0, -46.0)
	elif target.has_method("prompt_position"):
		offset = (target.call("prompt_position") as Vector2) + Vector2(0.0, 2.0)
	bubble.position = offset
	target.add_child(bubble)
	_current_bubble = bubble
	bubble.show_speech(speaker, text, hold)
	await bubble.finished
	if is_instance_valid(bubble):
		bubble.queue_free()
	if _gen == my_gen and _current_bubble == bubble:
		_current_bubble = null
