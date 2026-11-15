class_name BedRestSpot
extends Interactable
## Normal bed interaction inside the player's hut once story steps (`BedSpot`, `BedRest`) are not active.
## Enforces the dynamic 10%-70% night fatigue threshold, shows "Du bist noch nicht müde." before it unlocks,
## and coordinates co-op bed readiness when multiple players are active.

var radius: float = 26.0
var height: float = 48.0
var story_spots: Array[StorySpot] = []

var _focused: bool = false
var _last_state_key: String = ""
var _speech_cooldown: float = 0.0


func _process(delta: float) -> void:
	_speech_cooldown = maxf(0.0, _speech_cooldown - delta)
	var player: Player = _local_player()
	var world: Variant = _world()
	if player != null and world != null and world.has_method("is_waiting_in_bed") and bool(world.call("is_waiting_in_bed", player)):
		if player.global_position.distance_to(global_position) > radius + 36.0:
			world.request_bed_leave(player)
	if _focused:
		var state_key: String = prompt() + "|" + prompt_hint()
		if state_key != _last_state_key:
			_last_state_key = state_key
			if _prompt_node != null:
				_prompt_node.show_text(prompt(), prompt_hint())


func set_focused(on: bool) -> void:
	_focused = on
	_last_state_key = (prompt() + "|" + prompt_hint()) if on else ""
	super.set_focused(on)


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.story_lock or player.intro != null or InputManager.ui_blocking:
		return ""
	if _story_active():
		return ""
	var world: Variant = _world()
	if world == null or (not bool(world.get("opening_over")) and TimeManager.locked):
		return ""
	var texts: Dictionary = SleepRules.text_cfg()
	if world.has_method("is_waiting_in_bed") and bool(world.call("is_waiting_in_bed", player)):
		return String(texts.get("leave_prompt", "AUFSTEHEN"))
	return String(texts.get("prompt", "SCHLAFEN"))


func prompt_hint() -> String:
	if prompt() == "":
		return ""
	var player: Player = _local_player()
	var world: Variant = _world()
	if player != null and world != null and world.has_method("is_waiting_in_bed") and bool(world.call("is_waiting_in_bed", player)):
		return ""
	if TimeManager.can_sleep_now():
		return ""
	return String(SleepRules.text_cfg().get("not_tired_hint", "DU BIST NOCH NICHT MÜDE"))


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - radius


func prompt_position() -> Vector2:
	return Vector2(0, -height)


func interact(player: Player) -> void:
	var world: Variant = _world()
	if world == null or player == null:
		return
	if world.has_method("is_waiting_in_bed") and bool(world.call("is_waiting_in_bed", player)):
		world.request_bed_leave(player)
		return
	if not TimeManager.can_sleep_now():
		if _speech_cooldown <= 0.0:
			_speech_cooldown = 2.0
			var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
			if box != null:
				box.speak("", String(SleepRules.text_cfg().get("not_tired_speech", "Ich bin noch nicht müde.")), 2.2)
		return
	world.request_bed_sleep(player)


func _story_active() -> bool:
	for spot: StorySpot in story_spots:
		if is_instance_valid(spot) and spot.prompt() != "":
			return true
	return false


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


func _world() -> Variant:
	var node: Node = get_tree().get_first_node_in_group("world")
	return node if node != null and node.is_in_group("story_world") else null
