extends Node
## The cards of the three first talismans.
## Godot --rendering-driver opengl3 --path . tools/preview_talisman_card.tscn -- --capture=/abs/path.png
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var back: ColorRect = ColorRect.new()
	back.color = Color("0b0816")
	back.size = Vector2(640, 360)
	add_child(back)
	var shown: Array = [["silver_chain", {}], ["wuchtreif", {}], ["schweigtropfen", {}]]
	var x: float = 8.0
	for entry: Array in shown:
		var card: ItemTooltip = ItemTooltip.new()
		add_child(card)
		card.show_stack({"id": String(entry[0]), "count": 1}, true, entry[1] as Dictionary)
		card.position = Vector2(x, 12)
		x += card.size.x + 8.0
		var icon: TextureRect = TextureRect.new()
		icon.texture = Items.icon({"id": String(entry[0]), "count": 1})
		icon.scale = Vector2(3, 3)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.position = Vector2(card.position.x + 4, 220)
		add_child(icon)
	await get_tree().create_timer(0.8).timeout
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	get_tree().quit()
