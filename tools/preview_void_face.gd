extends Control
## The shadow face on its own (offline, needs graphics): `Godot --rendering-driver opengl3 --path . --fixed-fps 60 tools/preview_void_face.tscn -- --dir=/abs/folder`.
## Saves the word in several states: smoke condensing, full, glitching, crumbling; plus the whole alphabet and the small face.
var _dir: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _run() -> void:
	var back: ColorRect = ColorRect.new()
	back.color = Color("0d0818")
	back.size = Vector2(640, 360)
	add_child(back)
	var name_node: VoidTitle = VoidTitle.new()
	add_child(name_node)
	name_node.setup("MORNATH", "big", 1.0)
	name_node.place(Vector2(640.0 * 0.5 - name_node.ink_size.x * 0.5, 70))
	var epithet: VoidTitle = VoidTitle.new()
	add_child(epithet)
	epithet.setup("DER HIMMELSSPALTER", "small", 2.0)
	epithet.place(Vector2(640.0 * 0.5 - epithet.ink_size.x * 0.5, 190))
	var abc: VoidTitle = VoidTitle.new()
	add_child(abc)
	abc.setup("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "small", 3.0)
	abc.place(Vector2(60, 250))
	var steps: Array[Dictionary] = [
		{"n": "1_smoke", "reveal": 0.35, "dissolve": 0.0, "glitch": 0.0},
		{"n": "2_forming", "reveal": 0.75, "dissolve": 0.0, "glitch": 0.0},
		{"n": "3_full_a", "reveal": 1.4, "dissolve": 0.0, "glitch": 0.0},
		{"n": "4_full_b", "reveal": 1.4, "dissolve": 0.0, "glitch": 0.0},
		{"n": "5_glitch", "reveal": 1.4, "dissolve": 0.0, "glitch": 1.0},
		{"n": "6_crumble", "reveal": 1.4, "dissolve": 0.5, "glitch": 0.0},
		{"n": "7_gone", "reveal": 1.4, "dissolve": 0.95, "glitch": 0.0},
	]
	for step: Dictionary in steps:
		for node: VoidTitle in [name_node, epithet, abc]:
			node.set_look(float(step.reveal), float(step.dissolve), float(step.glitch), 1.0, 1.0)
		await _frames(24)
		await _shot(String(step.n))
	get_tree().quit(0)
