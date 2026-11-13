extends Node
## Deterministic visual samples of entrances, steady ridge journey, waystone awakening and passage into light.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir: String = "user://"
	var animation: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
		if arg == "--animation":
			animation = true
	var walk_speed: float = float(DataRegistry.table("loading").get("walk_speed", 36.0))
	var screen: LoadingScreen = LoadingScreen.new()
	screen.companions = [1, 2]
	add_child(screen)
	screen.set_process(false)
	if animation:
		for frame: int in 78:
			var t: float = frame / 12.0
			screen.age = t
			screen.chase = t - 3.8 if t >= 3.8 else -1.0
			screen.set("_travel", t * walk_speed)
			screen.update_visuals(1.0 / 12.0)
			screen.queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join("frame_%03d.png" % frame))
		get_tree().quit()
		return
	for t: float in [0.3, 0.7, 1.3, 2.2, 3.0, 3.25, 3.65, 4.2, 4.75, 5.25]:
		screen.age = t
		screen.chase = t - 3.0 if t >= 3.0 else -1.0
		screen.set("_travel", t * walk_speed)
		screen.update_visuals(1.0 / 12.0)
		screen.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("loading_%.2f.png" % t))
	print("Loading preview captured")
	get_tree().quit()
