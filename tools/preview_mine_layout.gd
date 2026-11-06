extends Node
## Draws a mine level from the generator (docs/mine.md step 2). `-- --level=N --seed=S --capture=/abs/path.png` writes a PNG (1 tile = `--scale` px) and quits;
## without --capture a window shows it (Left/Right = level, Up/Down = seed).

const COLORS: Dictionary = {
	"entry": Color("3fd17a"), "exit": Color("e0483c"), "rest": Color("f0c24a"), "junction": Color("8a7cc8"), "storage": Color("b08a58"),
	"bunks": Color("a06a78"), "spider_nest": Color("6b2f5c"), "wet": Color("4a78b8"), "airshaft": Color("d0d8e8"), "treasure": Color("f0e070"),
	"forge": Color("d8743a"), "crystal": Color("58d0d0"), "voidroom": Color("c040c0"), "empty": Color("7a7488"),
}

var _level: int = 1
var _seed: int = 1
var _rect: TextureRect


func _ready() -> void:
	var scale_px: int = 4
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): _level = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seed="): _seed = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--scale="): scale_px = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--capture="): capture = arg.get_slice("=", 1)
	if capture != "":
		var image: Image = _draw(scale_px)
		image.save_png(capture)
		print("saved ", capture)
		get_tree().quit()
		return
	_rect = TextureRect.new()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	layer.add_child(_rect)
	_refresh()


func _refresh() -> void:
	_rect.texture = ImageTexture.create_from_image(_draw(4))


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_RIGHT: _level = mini(_level + 1, 20)
		KEY_LEFT: _level = maxi(_level - 1, 1)
		KEY_UP: _seed += 1
		KEY_DOWN: _seed -= 1
	_refresh()


func _draw(scale_px: int) -> Image:
	var l: MineLayout = MineGenerator.new().generate(_seed, _level)
	print("level %d seed %d: %dx%d tiles, %d rooms, way %d cells, %.0f ms" % [_level, _seed, l.edge, l.edge, l.rooms.size(), l.path_cells, l.build_ms])
	var image: Image = Image.create(l.edge * scale_px, l.edge * scale_px, false, Image.FORMAT_RGB8)
	image.fill(Color("14101c"))
	for y: int in l.edge:
		for x: int in l.edge:
			if l.tiles[y * l.edge + x] == 1:
				var room: int = l.room_at(x, y)
				var c: Color = Color("4a4458")
				if room >= 0:
					c = (COLORS.get(String(l.rooms[room].type), Color.WHITE) as Color).darkened(0.45)
				image.fill_rect(Rect2i(x * scale_px, y * scale_px, scale_px, scale_px), c)
	for tile: Vector2i in [l.entry, l.exit, l.station]:
		var c: Color = COLORS["entry"] if tile == l.entry else (COLORS["exit"] if tile == l.exit else COLORS["rest"])
		image.fill_rect(Rect2i((tile.x - 2) * scale_px, (tile.y - 2) * scale_px, 5 * scale_px, 5 * scale_px), c)
	return image
