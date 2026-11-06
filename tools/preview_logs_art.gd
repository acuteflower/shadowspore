extends Node
## Side-by-side art review, no game state or save writes.
func _ready() -> void:
	var view: SubViewport = SubViewport.new()
	view.size = Vector2i(960,520)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("263b35")
	bg.size = Vector2(960,520)
	view.add_child(bg)
	for i: int in 3:
		var label: Label = Label.new()
		label.text = ["REFERENZEN","BISHER","ÜBERARBEITET"][i]
		label.position = Vector2([20,366,668][i],12)
		label.add_theme_font_size_override("font_size",18)
		view.add_child(label)
	_draw_art(view,(load("res://assets/props/fallen_knight.png") as Texture2D).get_image(),Rect2i(0,0,112,64),Vector2(12,52),3)
	_draw_art(view,(load("res://assets/props/tree.png") as Texture2D).get_image(),Rect2i(250,119,58,81),Vector2(85,257),3)
	var after: Image = (load("res://assets/props/fallen_logs.png") as Texture2D).get_image()
	var before: Image = Image.load_from_file("/tmp/fallen-logs-before.png") if FileAccess.file_exists("/tmp/fallen-logs-before.png") else after
	for i: int in 3:
		var region: Rect2i = Rect2i(112 if i==1 else 0,i*80,112,80)
		_draw_art(view,before,region,Vector2(350,35+i*160),2)
		_draw_art(view,after,region,Vector2(650,35+i*160),2)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("/tmp/logs-design-comparison.png")
	print("LOG ART: comparison rendered")
	get_tree().quit()
func _draw_art(parent: Node,image: Image,region: Rect2i,at: Vector2,scale_value: int) -> void:
	var art: Sprite2D = Sprite2D.new()
	art.texture = ImageTexture.create_from_image(image.get_region(region))
	art.centered = false
	art.position = at
	art.scale = Vector2.ONE*scale_value
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(art)
