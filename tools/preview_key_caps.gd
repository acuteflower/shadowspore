extends Node2D
## Contact sheet of the shared key cap (`VineStyle.key_cap`): every kind of key, idle / hinted / held, by day and by
## night, on bark paper and over the meadow, plus the interact prompt that uses it.
## Godot --rendering-driver opengl3 --path . tools/preview_key_caps.tscn -- --capture=/abs.png

const KEYS: Array[String] = ["E", "Y", "H", "M", "STRG", "LEER", "WASD", "LMT", "RMT"]


func _ready() -> void:
	var prompt: InteractPrompt = InteractPrompt.new()
	prompt.position = Vector2(60, 150)
	add_child(prompt)
	prompt.show_text("SAMMELN")
	var prompt2: InteractPrompt = InteractPrompt.new()
	prompt2.position = Vector2(170, 150)
	add_child(prompt2)
	prompt2.show_text("ANGELN")
	_capture.call_deferred()


func _capture() -> void:
	for i: int in 40:
		await get_tree().process_frame
	queue_redraw()
	await RenderingServer.frame_post_draw
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("4f7d4a"))
	for y: int in range(0, 360, 4): ## a little grass texture behind
		for x: int in range(0, 640, 4):
			if VineStyle.rand(x * 7 + y * 13) > 0.7:
				draw_rect(Rect2(x, y, 1, 2), Color("6f9c5a"))
	for night: int in 2:
		var void_level: float = float(night)
		var row_y: float = 12.0 + night * 60.0
		VineStyle.paper(self, Rect2(8, row_y, 300, 50), 1.0, void_level, 3 + night)
		var x: float = 16.0
		for key: String in KEYS:
			for state: int in 3:
				var lit: float = [0.0, 0.35, 1.0][state]
				VineStyle.key_cap(self, Vector2(x, row_y + 6 + state * 14), key, 1.0, lit, void_level)
			x += VineStyle.cap_width(key) + 6
		x = 330.0
		for key: String in KEYS: ## over open ground, no paper
			VineStyle.key_cap(self, Vector2(x, row_y + 20), key, 1.0, 0.0, void_level)
			x += VineStyle.cap_width(key) + 4
