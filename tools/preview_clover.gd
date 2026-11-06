extends Node
## Shows the clump pictures of six clover fields (each field paints its own): `-- --out=/abs/file.png [--seed=1]`, one row per field, 3x.
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var out: String = ""
	var seed_base: int = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--seed="): seed_base = int(arg.trim_prefix("--seed="))
	var sheet: Image = Image.create(CloverField.CELL.x * CloverField.CELLS, CloverField.CELL.y * 6, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("4f8f4a"))
	for i: int in 6:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_base * 100 + i
		var field: CloverField = CloverField.new()
		field.setup(CloverField.plan(rng), Vector2.ZERO)
		sheet.blend_rect(field.atlas_image, Rect2i(Vector2i.ZERO, field.atlas_image.get_size()), Vector2i(0, i * CloverField.CELL.y))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	get_tree().quit()
