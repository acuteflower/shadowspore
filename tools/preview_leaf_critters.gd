extends Node2D
## Art/attachment workbench, intentionally shows all species together, not spawn density.
## Godot --rendering-driver opengl3 --path . tools/preview_leaf_critters.tscn -- --capture=/absolute/folder
class PreviewWind:
	extends WorldWind
	func exposure(_at: Vector2) -> float: return 1.0

var animals: Array[LeafCritter] = []
var plants: Array[Bush] = []
var species_list: Array[String] = []
var wind: WorldWind
var output: String = ""
var tint: CanvasModulate

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): output = arg.trim_prefix("--capture=")
	Moisture.world_seed = 4242
	TimeManager.day = 3
	TimeManager.locked = true
	TimeManager.time_of_day = 0.5
	RenderingServer.set_default_clear_color(Color("315b46"))
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(320, 180)
	add_child(camera)
	wind = PreviewWind.new()
	add_child(wind)
	wind.set_process(false)
	tint = CanvasModulate.new()
	add_child(tint)
	var ids: Array[String] = ["bush", "berry_bush", "ember_bush", "grass", "glowfern", "cattail"]
	for row: int in ids.size():
		var spec: Dictionary = DataRegistry.get_entry("plants", ids[row])
		var label: Label = Label.new()
		label.text = ids[row]
		label.position = Vector2(16, 47 + row * 47)
		label.add_theme_font_size_override("font_size", 10)
		add_child(label)
		for col: int in 3:
			var bush: Bush = (load(String(spec.scene)) as PackedScene).instantiate() as Bush
			bush.setup(null, Vector2i(3 + (row * 3 + col) * 16, 5), ids[row], 1)
			bush.position = Vector2(190 + col * 150, 68 + row * 47)
			add_child(bush)
			bush.set_process(false)
			var species: String = ["beetle", "caterpillar", "snail"][col]
			if LeafCritter.sites_for(bush, species).is_empty():
				for variant: int in int(spec.columns):
					bush.variant = variant
					bush.apply_state({}, "")
					if not LeafCritter.sites_for(bush, species).is_empty(): break
			plants.append(bush)
			animals.append(bush._critter)
			species_list.append(species)
	for col: int in 3:
		var label: Label = Label.new()
		label.text = ["SCHIMMERKAEFER", "BLATTRAUPE", "LAUBSCHNECKE"][col]
		label.position = Vector2(146 + col * 150, 8)
		label.add_theme_font_size_override("font_size", 10)
		add_child(label)
	shoot.call_deferred()

func shoot() -> void:
	await get_tree().process_frame
	for stage: String in ["rest", "crawl", "wind", "flight", "night"]:
		wind.clock = 8.0 if stage == "wind" else 0.0
		wind.gust = 1.0 if stage == "wind" else 0.0
		RenderingServer.global_shader_parameter_set("g_wind_dir", Vector2.RIGHT)
		RenderingServer.global_shader_parameter_set("g_wind_clock", wind.clock)
		RenderingServer.global_shader_parameter_set("g_wind_gust", wind.gust)
		for i: int in animals.size():
			var animal: LeafCritter = animals[i]
			var bush: Bush = plants[i]
			animal.set_process(false)
			animal.kind = species_list[i]
			animal._flee = -1.0
			(bush.get_node("Sprite") as Sprite2D).skew = 0.12 if stage == "wind" else 0.0
			animal._route_cycle = -1
			animal._clock = 0.22 + i * 0.1
			var spec: Dictionary = LeafCritter.config().species[animal.kind]
			var period: float = float(spec.rest_seconds) + float(spec.move_seconds)
			var phase: float = float(spec.rest_seconds) * 0.3 if stage != "crawl" else float(spec.rest_seconds) + float(spec.move_seconds) * 0.55
			TimeManager.time_of_day = TimeManager.DAY_START + (period * 3.0 + phase - LeafCritter._roll(bush.cell, 73) * period) / TimeManager.DAY_LENGTH_SEC
			if not LeafCritter.sites_for(bush, animal.kind).is_empty():
				animal._pose(0.0)
				animal.visible = true
			else: animal.visible = false
			if stage == "flight" and animal.kind == "beetle" and animal.visible:
				animal.refresh("depart")
				animal._process(0.6)
				animal.set_process(false)
			if stage == "night":
				TimeManager.time_of_day = 0.95
				animal._process(0.1)
			animal.queue_redraw()
		TimeManager.time_of_day = 0.95 if stage == "night" else 0.5
		tint.color = TimeManager.ambient_color()
		for frame: int in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not output.is_empty(): get_viewport().get_texture().get_image().save_png(output.path_join(stage + ".png"))
	get_tree().quit()
