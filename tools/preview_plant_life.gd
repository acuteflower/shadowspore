extends Node2D
## Look study of the plant-life additions: the three Fangblumen (open at night, shut by day), bushes with each undergrowth animal.
## Run: Godot --rendering-driver opengl3 --path . tools/preview_plant_life.tscn -- --capture=/abs/folder  (writes day.png and night.png)
var _dir: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_dir = arg.trim_prefix("--capture=")
	Moisture.world_seed = 7
	var ground: ColorRect = ColorRect.new()
	ground.color = Color("3a6a44")
	ground.size = Vector2(400, 200)
	ground.position = Vector2(-20, -40)
	ground.z_index = -20
	add_child(ground)
	var plants: Dictionary = DataRegistry.table("plants")
	for i: int in 3:
		var thing: Snapper = (load(String(plants.snapper.scene)) as PackedScene).instantiate() as Snapper
		thing.setup(null, Vector2i(10 + i, 10), "snapper", i)
		thing.position = Vector2(40 + i * 60, 70)
		add_child(thing)
	var shown: Dictionary = {}
	var x: int = 0
	var cell: int = 0
	while shown.size() < 3 and cell < 2000:
		cell += 1
		var bush: Bush = (load(String(plants.bush.scene)) as PackedScene).instantiate() as Bush
		bush.setup(null, Vector2i(500 + cell, 3), "bush", 1)
		bush.position = Vector2(40 + x * 60, 130)
		add_child(bush) ## (the spec is read in _ready)
		var animal: String = LeafCritter.today(bush)
		if animal != "" and not shown.has(animal):
			shown[animal] = true
			x += 1
		else:
			bush.free()
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(100, 80)
	camera.zoom = Vector2(2.5, 2.5)
	add_child(camera)
	var tint: CanvasModulate = CanvasModulate.new()
	tint.name = "Tint"
	add_child(tint)
	_shoot.call_deferred()


func _shoot() -> void:
	for phase: String in ["day", "night"]:
		TimeManager.time_of_day = 0.5 if phase == "day" else 0.95
		(get_node("Tint") as CanvasModulate).color = TimeManager.ambient_color()
		get_tree().call_group("night_lights", "set_night", TimeManager.night_amount())
		for _i: int in 40:
			await get_tree().process_frame
		if _dir != "":
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, phase])
	get_tree().quit()
