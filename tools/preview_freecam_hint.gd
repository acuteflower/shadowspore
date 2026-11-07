extends Node2D
## Godot --rendering-driver opengl3 --path . tools/preview_freecam_hint.tscn -- --capture=/abs.png
func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var hint: FreeCamHint = FreeCamHint.new()
	hint.feet = Vector2(7786.0, 9778.0)
	layer.add_child(hint)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	get_tree().quit()
func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("3d5f3a"))
