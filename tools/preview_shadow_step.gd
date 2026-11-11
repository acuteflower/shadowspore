extends Node2D
## Look study of the shadow step (Alt): Godot --path . tools/preview_shadow_step.tscn -- --dir=/absolute/folder [--angle=deg]
## Writes step_00.png .. one picture every 1/60 s of the step (the player is driven by hand, no world, no save), then quits.
## Without --dir it loops the step live for watching.

var _dir: String = ""
var _angle: float = 0.0
var _player: Player


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("3f7a52"))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--angle="):
			_angle = deg_to_rad(float(arg.trim_prefix("--angle=")))
	_player = load("res://src/entities/player/player.tscn").instantiate() as Player
	_player.name = "1"
	_player.position = Vector2(300, 190)
	add_child(_player)
	_player.set_physics_process(false)
	(_player.get_node("Camera2D") as Camera2D).enabled = false
	await get_tree().process_frame
	if _dir.is_empty():
		_loop()
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	var way: Vector2 = Vector2.from_angle(_angle)
	_player.facing = way
	_player.position = Vector2(300, 190) - way * 27.0
	_player._animate(0.0)
	await RenderingServer.frame_post_draw
	_player.play_shadow_step(_player.position, _player.position + way * 54.0, way)
	var index: int = 0
	while _player._step_t >= 0.0 or index < 4:
		for fx: Node in get_tree().current_scene.get_children():
			if fx is ShadowStepFx:
				fx.set_process(false)
				(fx as ShadowStepFx)._process(1.0 / 60.0)
		_player._animate(1.0 / 60.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/step_%02d.png" % [_dir, index])
		index += 1
	print("SHADOW STEP CAPTURED ", index)
	get_tree().quit()


func _loop() -> void:
	while true:
		var way: Vector2 = Vector2.from_angle(randf() * TAU)
		var center: Vector2 = Vector2(320, 190)
		_player.position = center - way * 27.0
		_player.play_shadow_step(_player.position, center + way * 27.0, way)
		await get_tree().create_timer(1.4).timeout


func _process(delta: float) -> void:
	if _player != null and _dir.is_empty():
		_player._animate(delta)
