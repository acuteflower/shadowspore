class_name SleepScene
extends Node
## She goes to bed after the talk at the fire (the bed's E, quest step `sleep`): a short line, the screen closes to black, the night passes (she is healed), the flag `slept`, and
## the second morning begins as a WakeScene (`second_morning`): from there the game really starts. A child of the player; solo / host only for now.

const SHUT: AudioStream = preload("res://assets/audio/hut/creak_b.wav")


## `rest`: a later night (the town quest: "rest until morning"): the same bed, nothing of the story is set again.
func start(player: Player, world: WorldLevel, rest: bool = false) -> void:
	player.story_lock = true
	InputManager.ui_blocking = true
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 95
	var black: ColorRect = ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	add_child(layer)
	var sound: AudioStreamPlayer = AudioStreamPlayer.new()
	sound.stream = SHUT
	sound.volume_db = -6.0
	add_child(sound)
	sound.play()
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.play("sleep_in")
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(black, "color:a", 1.0, 2.2).set_delay(0.8)
	await tween.finished
	player.health.heal_full() ## the night mends her
	if not rest:
		player.quests.set_flag("slept")
	player.story_lock = false
	InputManager.ui_blocking = false
	var wake: WakeScene = WakeScene.new()
	wake.name = "WakeScene"
	player.add_child(wake)
	wake.start(player, world, false, true, rest)
	await get_tree().process_frame
	queue_free()
