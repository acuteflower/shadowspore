extends Node2D
## Dev view of the RegionMap: run this scene directly (res://src/world/region_debug.tscn).
## `-- baked` shows the frozen world (data/world_map.json). R = new seed, Tab = colour by biome / super region / region / depth (steps from the start region).

const SIZE: float = 340.0 ## drawn map size in screen px
const BORDER: Color = Color(0.05, 0.03, 0.1)
const SEA: Color = Color("120e1f")

var _map: RegionMap
var _texture: ImageTexture
const MODES: Array[String] = ["BIOME", "UEBERREGIONEN", "REGIONEN", "TIEFE"]
const SUPER_COLORS: Array[Color] = [Color("5fb36b"), Color("8a6fd6"), Color("d98a4a"), Color("4aa3c9"), Color("c9506f"), Color("c9c24a")]

var _mode: int = 0
var _seed: int = 1
var _baked: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			_seed = arg.substr(5).to_int()
		elif arg == "baked":
			_baked = true
		elif arg.begins_with("mode="):
			_mode = arg.substr(5).to_int()
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		_seed = randi() % 100000
		_baked = false
		_rebuild()
	elif key.keycode == KEY_TAB:
		_mode = (_mode + 1) % MODES.size()
		_repaint()


func _rebuild() -> void:
	var t0: int = Time.get_ticks_msec()
	_map = RegionMap.new(0, DataRegistry.table("world_map")) if _baked else RegionMap.new(_seed)
	_seed = _map.world_seed
	var areas: Array[int] = []
	var max_depth: int = 0
	for reg: Dictionary in _map.regions:
		areas.append(reg.area as int / 256)
		max_depth = maxi(max_depth, reg.depth as int)
	areas.sort()
	var sizes: Array[int] = []
	for sup: Dictionary in _map.supers:
		sizes.append((sup.regions as Array).size())
	print("seed %d: %d regions, area %d..%d (16x16 tiles), depth 0..%d, supers %s, %d ms" % [_seed, areas.size(), areas[0], areas[-1], max_depth, sizes, Time.get_ticks_msec() - t0])
	_repaint()


func _repaint() -> void:
	var n: int = _map.grid_size
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var max_depth: int = 1
	for reg: Dictionary in _map.regions:
		max_depth = maxi(max_depth, reg.depth as int)
	for y: int in n:
		for x: int in n:
			var tile: Vector2i = Vector2i(x, y) * RegionMap.CELL
			var id: int = _map.region_at(tile)
			var c: Color = SEA
			if id >= 0:
				var sup: int = _map.super_at(tile)
				var shade: Color = Color.from_ok_hsl(fposmod(id * 0.618, 1.0), 0.4, 0.5)
				if _mode == 0:
					var entry: Dictionary = DataRegistry.get_entry("biomes", _map.biome_at(tile))
					c = Color(entry.get("color", "#777777") as String)
				elif _mode == 1:
					c = SUPER_COLORS[sup].lerp(shade, 0.12)
				elif _mode == 2:
					c = Color.from_ok_hsl(fposmod(id * 0.618, 1.0), 0.45, 0.5)
				else:
					c = Color("5fb36b").lerp(Color("c2314f"), float((_map.regions[id] as Dictionary).depth) / max_depth)
				var r_id: int = _map.region_at(tile + Vector2i(RegionMap.CELL, 0))
				var b_id: int = _map.region_at(tile + Vector2i(0, RegionMap.CELL))
				if _map.super_at(tile + Vector2i(RegionMap.CELL, 0)) != sup or _map.super_at(tile + Vector2i(0, RegionMap.CELL)) != sup:
					c = c.lerp(BORDER, 0.95)
				elif r_id != id or b_id != id:
					c = c.lerp(BORDER, 0.45)
			img.set_pixel(x, y, c)
	_texture = ImageTexture.create_from_image(img)
	queue_redraw()


func _draw() -> void:
	var origin: Vector2 = Vector2(10, 10)
	draw_texture_rect(_texture, Rect2(origin, Vector2(SIZE, SIZE)), false)
	var k: float = SIZE / RegionMap.WORLD_TILES
	for reg: Dictionary in _map.regions:
		var p: Vector2i = Vector2i(origin + (reg.center as Vector2) * k)
		if _mode >= 2:
			var label: String = str(reg.depth if _mode == 3 else reg.id)
			PixelText.draw(self, label, p - Vector2i(PixelText.width(label) / 2, 2), Color.WHITE, Color.BLACK)
		if reg.id == _map.start_region:
			draw_rect(Rect2(Vector2(p) - Vector2(4, 4), Vector2(8, 8)), Color.WHITE, false)
	PixelText.draw(self, "SEED %d" % _seed, Vector2i(366, 12), Color.WHITE)
	PixelText.draw(self, "R NEUER SEED", Vector2i(366, 24), Color("8a84ad"))
	PixelText.draw(self, "TAB " + MODES[_mode], Vector2i(366, 34), Color("8a84ad"))
	if _mode <= 1:
		for sup: Dictionary in _map.supers:
			var q: Vector2i = Vector2i(origin + (sup.center as Vector2) * k)
			var tag: String = "%d" % (sup.id as int + 1)
			if _mode == 0:
				tag = _map.area_name(int(sup.id))
			var half_w: int = PixelText.width(tag) / 2 + 3
			draw_rect(Rect2(Vector2(q) - Vector2(half_w, 6), Vector2(half_w * 2, 12)), Color(0, 0, 0, 0.7))
			PixelText.draw(self, tag, q - Vector2i(PixelText.width(tag) / 2, 2), Color.WHITE)
	PixelText.draw(self, "%d REGIONEN" % _map.regions.size(), Vector2i(366, 50), Color("8a84ad"))
