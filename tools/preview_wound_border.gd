extends SceneTree
## Look study of the bleeding border (assets/shaders/wound_border.gdshader) over a dark night-blue backdrop.
## Godot --rendering-driver opengl3 --path . --script tools/preview_wound_border.gd -- --capture=/abs/folder
## Writes wound_<t>.png for a few moments (grow, heartbeat peak, rest, flash).

var _dir: String = ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_dir = arg.substr(10)
	root.size = Vector2i(1280, 720)
	var back: TextureRect = TextureRect.new() ## the grass atlas tiled, so the slipping rows can be seen
	back.texture = load("res://assets/tiles/grass.png") as Texture2D
	back.stretch_mode = TextureRect.STRETCH_TILE
	back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back.size = root.get_visible_rect().size
	back.modulate = Color(0.55, 0.6, 0.95)
	root.add_child(back)
	var rect: ColorRect = ColorRect.new()
	rect.size = root.get_visible_rect().size
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/wound_border.gdshader") as Shader
	rect.material = mat
	root.add_child(rect)
	_run(mat)


func _run(mat: ShaderMaterial) -> void:
	var shots: Array = [["grow50", 0.5, 0.6, 3.0, 0.0], ["beat", 1.0, 0.02, 5.0, 0.0], ["rest", 1.0, 0.8, 9.0, 0.0], ["flash", 1.0, 0.1, 1.0, 0.8]]
	for s: Array in shots:
		mat.set_shader_parameter("grow", float(s[1]))
		mat.set_shader_parameter("phase", float(s[2]))
		mat.set_shader_parameter("time", float(s[3]))
		mat.set_shader_parameter("flash", float(s[4]))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		if _dir != "":
			img.save_png(_dir.path_join("wound_%s.png" % String(s[0])))
	print("WOUND PREVIEW OK")
	quit()
