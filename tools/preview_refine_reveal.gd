extends Node2D
## The reveal card of a refinement. Godot --rendering-driver opengl3 --path . tools/preview_refine_reveal.tscn -- --capture=/abs.png [--fail] [--level=10] [--late] [--build]
## --fail: a failed attempt, --level=N: the level that was reached (default 8), --build: the heating phase, --late: the end of the answer.


func _ready() -> void:
	var fail: bool = false
	var level: int = 8
	var build: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--fail": fail = true
		elif arg == "--build": build = true
		elif arg.begins_with("--level="): level = arg.get_slice("=", 1).to_int()
	var before: Dictionary = {"id": "sword_iron", "count": 1, "r": level - 1}
	var after: Dictionary = RefineRules.result(before, not fail)
	await get_tree().process_frame
	var reveal: RefineReveal = RefineReveal.present(get_tree(), before, after, not fail, RefineRules.refund(before, level) if fail else {})
	await get_tree().create_timer(0.7 if build else 1.9).timeout
	await RenderingServer.frame_post_draw
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	reveal.queue_free()
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("4f7d4a"))
