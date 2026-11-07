extends Node2D
## Captures the boss bar at its key moments: tearing open, full, after hits, last phase, death.
## Godot --rendering-driver opengl3 --path . tools/preview_boss_bar.tscn -- --capture=/abs/folder/

var _dir: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_dir = arg.trim_prefix("--capture=")
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var bar: BossBar = BossBar.new()
	layer.add_child(bar)
	var hc: HealthComponent = HealthComponent.new()
	hc.max_health = 600.0
	add_child(hc)
	await get_tree().process_frame
	bar.track("MORNATH", hc)
	await _shot("1_open", 0.55)
	await _shot("2_full", 1.2)
	hc.take_damage(150.0, Vector2.ZERO, 0.0)
	await _shot("3_hit", 0.12)
	hc.take_damage(120.0, Vector2.ZERO, 0.0)
	await _shot("4_phase", 0.2)
	hc.take_damage(200.0, Vector2.ZERO, 0.0)
	await _shot("5_last", 0.9)
	hc.take_damage(120.0, Vector2.ZERO, 0.0)
	await _shot("6_low", 1.0)
	hc.take_damage(999.0, Vector2.ZERO, 0.0)
	hc.died.emit()
	await _shot("7_death", 0.35)
	get_tree().quit()


func _shot(name: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	if _dir != "":
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("3d5f3a"))
