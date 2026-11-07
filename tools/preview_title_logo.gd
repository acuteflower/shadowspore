extends Node2D
## The title logo on its own, with its idle animation. Offline, no save access.
## `Godot --path . tools/preview_title_logo.tscn` (add `-- --build` to play the build-up, B plays it again); capture a still: `-- --capture=/abs.png [--t=3.5] [--build]`;
## a frame strip: `-- --strip=/abs_dir [--t=0] [--n=12] [--dt=0.25] [--build]` (with --build the build-up starts at clock 0)
const ORIGIN: Vector2 = Vector2(100, 60) ## 640 x 360 picture: the 440 x 240 logo sits in the middle


func _ready() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("040208")
	add_child(bg)
	var logo: TitleLogo = TitleLogo.new()
	logo.position = ORIGIN
	add_child(logo)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var t0: float = 0.0
	var count: int = 1
	var dt: float = 0.25
	var capture: String = ""
	var strip: String = ""
	for arg: String in args:
		if arg.begins_with("--t="):
			t0 = float(arg.trim_prefix("--t="))
		elif arg.begins_with("--n="):
			count = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--dt="):
			dt = float(arg.trim_prefix("--dt="))
		elif arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--strip="):
			strip = arg.trim_prefix("--strip=")
	var build: bool = args.has("--build")
	if build:
		logo.set_time(0.0)
		logo.play_build()
	if capture == "" and strip == "":
		if build:
			logo.release_time()
			logo.play_build()
		return
	if strip != "":
		DirAccess.make_dir_recursive_absolute(strip)
		for i: int in count:
			logo.set_time(t0 + float(i) * dt)
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/f%02d.png" % [strip, i])
	else:
		logo.set_time(t0)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture)
	get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_B:
		for c: Node in get_children():
			if c is TitleLogo:
				(c as TitleLogo).play_build()
