extends SceneTree
## Contact sheet of Mornath's feathers (VoidFeather): `Godot --headless --path . --script tools/preview_feathers.gd -- --out=/abs/sheet.png [--scale=6]`
## Each cell shows the feather on a dark floor with its glow layer added on top; no renderer needed.
const BG: Color = Color("2a2548")


func _init() -> void:
	var out: String = "feathers.png"
	var scale_by: int = 6
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scale="):
			scale_by = int(arg.trim_prefix("--scale="))
	var cells: Array[Dictionary] = []
	for v: int in 4:
		cells.append({"len": 46, "wid": 16, "ang": PI / 2.0 + (float(v) - 1.5) * 0.17, "var": v})
	for v: int in 4:
		cells.append({"len": 28, "wid": 10, "ang": PI / 2.0 + (float(v % 3) - 1.0) * 0.26, "var": v})
	for k: int in 8:
		cells.append({"len": 34, "wid": 12, "ang": TAU * float(k) / 8.0 + 0.2, "var": k})
	for k: int in 4:
		cells.append({"len": 22, "wid": 8, "ang": TAU * float(k) / 4.0 + 0.4, "var": k})
	var cell: int = 60
	var cols: int = 8
	var rows: int = (cells.size() + cols - 1) / cols
	var sheet: Image = Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for n: int in cells.size():
		var c: Dictionary = cells[n]
		var art: Dictionary = VoidFeather.art(int(c["len"]), int(c["wid"]), float(c["ang"]), int(c["var"]))
		var body: Image = (art["body"] as Texture2D).get_image()
		var glow: Image = (art["glow"] as Texture2D).get_image()
		var middle: Vector2 = VoidFeather.middle(art)
		var origin: Vector2i = Vector2i(int(n % cols) * cell + cell / 2, int(n / cols) * cell + cell / 2) - Vector2i(int(middle.x), int(middle.y))
		for y: int in body.get_height():
			for x: int in body.get_width():
				var px: Vector2i = origin + Vector2i(x, y)
				if px.x < 0 or px.y < 0 or px.x >= sheet.get_width() or px.y >= sheet.get_height():
					continue
				var b: Color = body.get_pixel(x, y)
				if b.a > 0.0:
					sheet.set_pixel(px.x, px.y, b)
				var g: Color = glow.get_pixel(x, y)
				if g.a > 0.0:
					var base: Color = sheet.get_pixel(px.x, px.y)
					sheet.set_pixel(px.x, px.y, Color(minf(base.r + g.r * g.a, 1.0), minf(base.g + g.g * g.a, 1.0), minf(base.b + g.b * g.a, 1.0), 1.0))
	sheet.resize(sheet.get_width() * scale_by, sheet.get_height() * scale_by, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("saved ", out)
	quit(0)
