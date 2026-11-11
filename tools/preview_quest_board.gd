extends Node2D
## The quest board with its live notices without a world: `Godot --rendering-driver opengl3 --path . tools/preview_quest_board.tscn -- --capture=/abs.png [--night]`.
## Shows a story notice, two fetch notices (one already taken by the local player: faded), a hunt and one that is just dropping into place.
## `--poster[=species]` hangs a wanted poster (`--nights=N` tallies), `--honor=N` the thank-you cord and the milestones of N finished notices (25 / 50 / 100 grow the board).

var _t: float = 0.0
var _seals: bool = false
var _beacon: Dictionary = {}
var _notes: Array[Dictionary] = [
	{"k": "story", "id": 1, "a": 1.0, "drop": 0.0}, {"k": "fetch", "id": 2, "a": 1.0, "drop": 0.0}, {"k": "kill", "id": 3, "a": 1.0, "drop": 0.0},
	{"k": "fetch", "id": 4, "a": 0.5, "drop": 0.0}, {"k": "kill", "id": 5, "a": 1.0, "drop": 0.45},
]


func _ready() -> void:
	var night: bool = "--night" in OS.get_cmdline_user_args()
	var poster: Dictionary = {}
	var done: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--poster"):
			poster = {"t": arg.substr(9) if arg.length() > 9 else "void_crusher", "nights": 1, "a": 1.0, "drop": 0.0, "id": 9}
		if arg.begins_with("--honor="):
			done = int(arg.substr(8))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--nights=") and not poster.is_empty():
			poster["nights"] = int(arg.substr(9))
	_beacon = {"unread": 1, "story": false, "poster": poster, "done": done, "swing": 0.6}
	var camera: Camera2D = Camera2D.new()
	camera.zoom = Vector2(8, 8)
	camera.position = Vector2(0, -24)
	add_child(camera)
	var ground: ColorRect = ColorRect.new()
	ground.color = Color("3a6e46")
	ground.position = Vector2(-60, -70)
	ground.size = Vector2(120, 100)
	ground.z_index = -5
	add_child(ground)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load("res://assets/town/quest_board.png") as Texture2D
	sprite.centered = false
	sprite.position = Vector2(-28, -50)
	add_child(sprite)
	var glow: Sprite2D = Sprite2D.new()
	if ResourceLoader.exists("res://assets/town/quest_board_glow.png"):
		glow.texture = load("res://assets/town/quest_board_glow.png") as Texture2D
		glow.centered = false
		glow.material = Unlit.material()
		sprite.add_child(glow)
	for lit: bool in [false, true]:
		var layer: Node2D = Node2D.new()
		layer.z_index = 1 if lit else 0
		if lit:
			layer.material = Unlit.material()
		layer.draw.connect(func() -> void: BoardNotes.paint(layer, _notes, _t, false, lit, 1.0 if night else 0.0, _beacon))
		add_child(layer)
		layer.set_meta("redraw", true)
	if night:
		var dark: CanvasModulate = CanvasModulate.new()
		dark.color = Color(0.35, 0.38, 0.6)
		add_child(dark)
	var path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			path = arg.substr(10)
	_finish.call_deferred(path)


func _process(delta: float) -> void:
	_t += delta
	for child: Node in get_children():
		if child.has_meta("redraw"):
			(child as Node2D).queue_redraw()


func _finish(path: String) -> void:
	if path == "":
		return
	for i: int in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
