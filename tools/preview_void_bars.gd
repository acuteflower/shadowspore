extends Node2D
## Contact sheet of VoidHealthBar at several health levels for the three widths, by night tone.
## Godot --rendering-driver opengl3 --path . tools/preview_void_bars.tscn -- --capture=/abs.png

const LEVELS: Array[float] = [0.95, 0.75, 0.5, 0.3, 0.15, 0.05]
const WIDTHS: Array[float] = [38.0, 48.0, 80.0]


func _ready() -> void:
	var rows: Array[Dictionary] = []
	for r: int in WIDTHS.size():
		for c: int in LEVELS.size():
			var owner_node: Node2D = Node2D.new()
			owner_node.position = Vector2(60 + c * 100, 40 + r * 40)
			add_child(owner_node)
			var hc: HealthComponent = HealthComponent.new()
			hc.name = "HealthComponent"
			owner_node.add_child(hc)
			var bar: VoidHealthBar = VoidHealthBar.new()
			bar.health = hc
			hc.max_health = WIDTHS[r]
			owner_node.add_child(bar)
			rows.append({"hc": hc, "level": LEVELS[c]})
	await get_tree().process_frame
	for row: Dictionary in rows:
		var hc: HealthComponent = row["hc"] as HealthComponent
		hc.current = hc.max_health * float(row["level"])
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("1c2a24"))
