extends Node2D
## Render regression: Godot --path . tools/test_wildlife_sort.tscn
## Animal and prop containers must participate in the same nested Y-sort, including while hopping.

var _failures: int = 0


func _ready() -> void:
	y_sort_enabled = true
	var props: Node2D = Node2D.new()
	props.y_sort_enabled = true
	add_child(props)
	var tree: Node2D = _marker(Vector2(100, 160), Vector2i(40, 80), Vector2(-20, -80), Color.BLUE)
	props.add_child(tree)
	var wildlife: Node = load("res://src/world/wildlife_population.tscn").instantiate()
	add_child(wildlife)
	wildlife.set_process(false)
	var rabbit: Node2D = _marker(Vector2(100, 120), Vector2i(20, 20), Vector2(-10, -20), Color.MAGENTA)
	wildlife.get_node("Animals").add_child(rabbit)
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().get_pixel(200, 220).r < 0.1, "Rabbit behind the tree is drawn on its crown")
	rabbit.position.y = 170
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().get_pixel(200, 310).r > 0.8, "Rabbit in front of the tree is incorrectly hidden")
	(rabbit.get_child(0) as Sprite2D).position.y = -40.0
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().get_pixel(200, 230).r > 0.8, "Airborne sprite height replaced the feet as the sort origin")
	print("Wildlife rendering: 3 checks, %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _marker(at: Vector2, size: Vector2i, offset: Vector2, color: Color) -> Node2D:
	var marker: Node2D = Node2D.new()
	marker.position = at
	var sprite: Sprite2D = Sprite2D.new()
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.centered = false
	sprite.offset = offset
	marker.add_child(sprite)
	return marker


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
