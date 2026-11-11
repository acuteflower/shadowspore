extends Node2D
## Isolated stage-one design bench, no world, networking, saves or gameplay changes.
var patch: RiverDesignPatch
var _tint: CanvasModulate
var _paused: bool = false
var _capture: String = ""
var _animate: String = ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): _capture = arg.trim_prefix("--capture=")
		if arg.begins_with("--animate="): _animate = arg.trim_prefix("--animate=")
	var ground: TileMapLayer = TileMapLayer.new()
	ground.tile_set = load("res://src/world/tileset.tres") as TileSet
	var ground_material: ShaderMaterial = ShaderMaterial.new()
	ground_material.shader = load("res://assets/shaders/ground_tone.gdshader") as Shader
	ground.material = ground_material
	add_child(ground)
	for y: int in 23:
		for x: int in 40:
			ground.set_cell(Vector2i(x, y), 0, Vector2i(posmod(x * 13 + y * 7, 8), 0))
	patch = RiverDesignPatch.new()
	add_child(patch)
	var settings: Dictionary = DataRegistry.table("water_design")
	patch.configure(settings["preview"], settings)
	if OS.get_cmdline_user_args().has("--no-disturbances"):
		patch.set_disturbances([])
	var props: Node2D = Node2D.new()
	props.y_sort_enabled = true
	add_child(props)
	for point: Vector2 in [Vector2(124, 87), Vector2(240, 69), Vector2(91, 262), Vector2(429, 322), Vector2(533, 237), Vector2(447, 108)]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load("res://assets/props/bush.png") as Texture2D
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 60, 34)
		sprite.centered = false
		sprite.offset = Vector2(-30, -30)
		sprite.position = point
		props.add_child(sprite)
	for point: Vector2 in [Vector2(225, 245), Vector2(314, 175), Vector2(398, 311), Vector2(513, 133)]:
		var rock: Sprite2D = Sprite2D.new()
		rock.texture = load("res://assets/props/rock.png") as Texture2D
		rock.region_enabled = true
		rock.region_rect = Rect2(0, 0, 64, 56)
		rock.centered = false
		rock.offset = Vector2(-32, -45)
		rock.position = point
		props.add_child(rock)
	for detail: Array in settings["preview"]["details"]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load("res://assets/water/shore_details.png") as Texture2D
		sprite.hframes = 4
		sprite.frame = int(detail[2])
		sprite.centered = false
		sprite.offset = Vector2(-16, -28)
		sprite.position = Vector2(float(detail[0]), float(detail[1]))
		props.add_child(sprite)
	var hero: Sprite2D = Sprite2D.new()
	hero.texture = load("res://assets/characters/player.png") as Texture2D
	hero.hframes = 22
	hero.vframes = 16
	hero.frame = 2 * 22 + 12
	hero.centered = false
	hero.offset = Vector2(-24, -51)
	hero.position = Vector2(291, 177)
	props.add_child(hero)
	_tint = CanvasModulate.new()
	add_child(_tint)
	if OS.get_cmdline_user_args().has("--night"): _night(true)
	var ui: CanvasLayer = CanvasLayer.new()
	add_child(ui)
	ui.visible = _capture.is_empty()
	var bar: HBoxContainer = HBoxContainer.new()
	bar.position = Vector2(12, 12)
	ui.add_child(bar)
	for label: String in ["Tag", "Nacht", "Animation pausieren"]:
		var button: Button = Button.new()
		button.text = label
		bar.add_child(button)
		button.pressed.connect(_control.bind(label))
	for i: int in 4: await get_tree().process_frame
	if not _animate.is_empty():
		DirAccess.make_dir_recursive_absolute(_animate)
		patch.field_image.save_png(_animate.path_join("field.png"))
		patch.bank_texture.get_image().save_png(_animate.path_join("banks.png"))
		patch.set_process(false)
		for frame: int in 40:
			patch.water_time = float(frame) / 10.0
			patch._process(0.0)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_animate.path_join("%03d.png" % frame))
	if not _capture.is_empty():
		patch.set_process(false)
		patch.water_time = 3.9
		patch._process(0.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_capture)
		print("Water design captured: ", _capture)
		get_tree().quit()

func _control(label: String) -> void:
	if label == "Tag": _night(false)
	elif label == "Nacht": _night(true)
	else:
		_paused = not _paused
		patch.set_process(not _paused)

func _night(enabled: bool) -> void:
	_tint.color = Color(0.30, 0.38, 0.58) if enabled else Color.WHITE
