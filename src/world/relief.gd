class_name Relief
extends RefCounted
## The world's height levels (baked by tools/bake_relief.py into assets/world/relief.png, 1 pixel
## per tile; layout in that script). Heights are flat map data, not a third dimension: a plateau
## is a region at a higher level with a smooth contour (relief_field.png, the blurred level masks),
## the 3/4 camera sees a 32 px wall below its south contour, the other edges are thin walls, and
## ramps, stairs and rock steps (`RAMP`, `STAIRS`, `STEPS`, whole tiles in relief.png) are the only
## ways between two levels. The collision comes from relief_block.png (4 px cells, baked with the
## same rule the shader draws by). The picture is drawn by `ReliefLayer`; this class answers every
## question about the data (collision, props, footsteps). The per-tile `FACE` kind is only the
## tile-grid approximation of the wall that props are kept away from.

const TEXTURE: Texture2D = preload("res://assets/world/relief.png")
const FIELD: Texture2D = preload("res://assets/world/relief_field.png")
const WOBBLE: Texture2D = preload("res://assets/world/relief_wobble.png")
const BLOCK: Texture2D = preload("res://assets/world/relief_block.png")
const CELLS: int = 4 ## collision cells per tile side (4 px each)
const PROP_MARGIN: float = 12.0 ## px props keep from anything that is not their own flat floor (the smooth contour strays from the tile edge)
const FLOOR: int = 0
const FACE: int = 1
const RAMP: int = 2
const STAIRS: int = 3
const STEPS: int = 4
const TILE: float = 16.0

var _bytes: PackedByteArray
var _side: int
var _field: PackedByteArray ## RGB per tile
var _block: PackedByteArray ## one byte per 4 px cell, non-zero = blocked
var _block_side: int


func _init() -> void:
	var image: Image = TEXTURE.get_image()
	image.convert(Image.FORMAT_RGBA8)
	_bytes = image.get_data()
	_side = image.get_width()
	_apply_world_biome()
	var field: Image = FIELD.get_image()
	field.convert(Image.FORMAT_RGB8)
	_field = field.get_data()
	var block: Image = BLOCK.get_image()
	block.convert(Image.FORMAT_L8)
	_block = block.get_data()
	_block_side = block.get_width()


## Restyle materials without moving heights, walls, connectors or collision cells.
## The immutable bake keeps its original material ids for future authoring.
func _apply_world_biome() -> void:
	var active: String = String(DataRegistry.table("world_map").get("biome", ""))
	if active.is_empty():
		return
	var biome: int = DataRegistry.table("biomes").keys().find(active)
	if biome < 0:
		return
	for i: int in range(0, _bytes.size(), 4):
		if _bytes[i + 3] == 0:
			continue
		_bytes[i + 3] = 200 + biome
		if active == "meadow":
			var style: int = _bytes[i + 1] >> 4
			if style >= 2:
				_bytes[i + 1] = (_bytes[i + 1] & 15) | ((0 if style == 4 else 1) << 4)


func _at(x: int, y: int, channel: int) -> int:
	if x < 0 or y < 0 or x >= _side or y >= _side:
		return 0
	return _bytes[(y * _side + x) * 4 + channel]


func is_land(x: int, y: int) -> bool:
	return _at(x, y, 3) != 0


func level(x: int, y: int) -> int:
	return _at(x, y, 0)


func kind(x: int, y: int) -> int:
	return _at(x, y, 1) & 15


func style(x: int, y: int) -> int:
	return _at(x, y, 1) >> 4


## True if any land tile in `rect` (tile coordinates) has crystal (3) or void (4) style.
func has_glow_style(rect: Rect2i) -> bool:
	var x0: int = maxi(0, rect.position.x)
	var y0: int = maxi(0, rect.position.y)
	var x1: int = mini(_side, rect.end.x)
	var y1: int = mini(_side, rect.end.y)
	for y: int in range(y0, y1):
		var row: int = y * _side * 4
		for x: int in range(x0, x1):
			var idx: int = row + x * 4
			if _bytes[idx + 3] != 0: ## land
				var st: int = _bytes[idx + 1] >> 4
				if st >= 3:
					return true
	return false


## Where a prop or a player can stand: land that is no wall face.
func walkable(x: int, y: int) -> bool:
	return is_land(x, y) and kind(x, y) != FACE


## The height a point stands at: the smooth level (what the shader draws), plus the fraction up a ramp or flight of stairs.
func level_at(pos: Vector2) -> float:
	var u: Vector2 = pos / TILE - Vector2(0.5, 0.5)
	var x0: int = floori(u.x)
	var y0: int = floori(u.y)
	var height: float = 0.0
	for channel: int in 3:
		var amount: float = lerpf(lerpf(_field_at(x0, y0, channel), _field_at(x0 + 1, y0, channel), u.x - x0), lerpf(_field_at(x0, y0 + 1, channel), _field_at(x0 + 1, y0 + 1, channel), u.x - x0), u.y - y0)
		if amount > 0.5:
			height += 1.0
	var x: int = floori(pos.x / TILE)
	var y: int = floori(pos.y / TILE)
	if kind(x, y) >= RAMP:
		var geom: int = _at(x, y, 2)
		var depth: int = ((geom >> 2) & 3) + 1
		height += (depth - (geom & 3) - fposmod(pos.y, TILE) / TILE) / depth
	return height


func _field_at(x: int, y: int, channel: int) -> float:
	x = clampi(x, 0, _side - 1)
	y = clampi(y, 0, _side - 1)
	return _field[(y * _side + x) * 3 + channel] / 255.0


## Terrain.json surface for the footsteps ("" = whatever the ground layers say).
func surface_at(pos: Vector2) -> String:
	match kind(floori(pos.x / TILE), floori(pos.y / TILE)):
		RAMP:
			return "slope"
		STAIRS, STEPS:
			return "stone"
	return ""


## True when everything within `radius` px of `pos` is floor of the level `pos` is on: nothing that
## has to stand with its feet on the ground may straddle a wall, a ramp or an edge.
func flat_around(pos: Vector2, radius: float) -> bool:
	radius += PROP_MARGIN
	var home: int = level(floori(pos.x / TILE), floori(pos.y / TILE))
	for y: int in range(floori((pos.y - radius) / TILE), floori((pos.y + radius) / TILE) + 1):
		for x: int in range(floori((pos.x - radius) / TILE), floori((pos.x + radius) / TILE) + 1):
			if not is_land(x, y) or kind(x, y) != FLOOR or level(x, y) != home:
				return false
	return true


## 1 when a wall face stands one or two tiles north of this tile (the foot of a cliff: rubble lies there).
func wall_above(cell: Vector2i) -> bool:
	return kind(cell.x, cell.y - 1) == FACE or kind(cell.x, cell.y - 2) == FACE


## Solid rectangles (px) for the collision cells of `rect` (tiles): the walls and rims baked into
## relief_block.png, merged into as few rectangles as possible.
func blockers(rect: Rect2i) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x0: int = rect.position.x * CELLS
	var x1: int = rect.end.x * CELLS
	var y0: int = rect.position.y * CELLS
	var y1: int = rect.end.y * CELLS
	var open: Dictionary = {} ## "a:b" -> first row of a rectangle that is still growing
	var cell: float = TILE / CELLS
	for y: int in range(y0, y1 + 1):
		var keys: Array[String] = []
		if y < y1:
			var run: int = -1
			for x: int in range(x0, x1 + 1):
				var solid: bool = x < x1 and x < _block_side and y < _block_side and _block[y * _block_side + x] != 0
				if solid and run < 0:
					run = x
				elif not solid and run >= 0:
					keys.append("%d:%d" % [run, x])
					run = -1
		for key: String in open.keys():
			if keys.has(key):
				continue
			var a: int = key.get_slice(":", 0).to_int()
			var b: int = key.get_slice(":", 1).to_int()
			out.append(Rect2(Vector2(a, open[key]) * cell, Vector2(b - a, y - int(open[key])) * cell))
			open.erase(key)
		for key: String in keys:
			if not open.has(key):
				open[key] = y
	return out


# Editable relief keeps immutable copies so undo restores the original bake exactly.
var editor_texture: ImageTexture
var editor_field: ImageTexture
var _base_bytes: PackedByteArray
var _base_field: PackedByteArray
var _base_block: PackedByteArray
var _wobble_image: Image

func editor_apply(edits: Dictionary) -> void:
	if editor_texture == null:
		_base_bytes = _bytes.duplicate()
		_base_field = _field.duplicate()
		_base_block = _block.duplicate()
		_wobble_image = WOBBLE.get_image()
	_bytes = _base_bytes.duplicate()
	_field = _base_field.duplicate()
	_block = _base_block.duplicate()
	var dirty: Dictionary = {}
	for key_string: String in edits:
		var cell: Vector2i = WorldEdits.cell(key_string)
		if not is_land(cell.x, cell.y):
			continue
		var spec: Dictionary = edits[key_string]
		if spec.has("biome"):
			var biome_ids: Array = DataRegistry.table("biomes").keys()
			_bytes[(cell.y * _side + cell.x) * 4 + 3] = 200 + maxi(0, biome_ids.find(RegionMap.active_biome(String(spec.biome))))
		if not spec.has("height"):
			continue
		dirty[cell] = true
		var idx: int = (cell.y * _side + cell.x) * 4
		var height: int = clampi(int(spec.height), 0, 3)
		_bytes[idx] = height
		var style: int = clampi(int(spec.get("style", 0)), 0, 4)
		if String(DataRegistry.table("world_map").get("biome", "")) == "meadow" and style >= 2:
			style = 0 if style == 4 else 1
		_bytes[idx + 1] = clampi(int(spec.get("kind", 0)), 0, 4) | (style << 4)
		_bytes[idx + 2] = int(spec.get("geom", 0))
		for ch: int in 3:
			_field[(cell.y * _side + cell.x) * 3 + ch] = 255 if height > ch else 0
	# Recompute only collision patches affected by edits: bilinear filter, rims,
	# and the 32 px south-facing wall. Sampling matches the existing bake.
	var patches: Dictionary = {}
	for cell: Vector2i in dirty:
		for y: int in range(maxi(0, cell.y - 1), mini(_side, cell.y + 5)):
			for x: int in range(maxi(0, cell.x - 1), mini(_side, cell.x + 2)):
				patches[Vector2i(x, y)] = true
	var heights: Dictionary = {}
	for cell: Vector2i in patches:
		for dy: int in CELLS:
			for dx: int in CELLS:
				var c: Vector2i = cell * CELLS + Vector2i(dx, dy)
				var home: int = _editor_level(c, heights)
				var solid: bool = false
				for d: int in range(1, 9):
					if _editor_level(c - Vector2i(0, d), heights) > home:
						solid = true
				for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					solid = solid or _editor_level(c + dir, heights) != home
				# Connectors clear their wall and half a tile above their start.
				var connector: bool = kind(cell.x, cell.y) >= RAMP
				if dy >= 2 and kind(cell.x, cell.y + 1) >= RAMP:
					connector = true
				_block[c.y * _block_side + c.x] = 255 if solid and is_land(cell.x, cell.y) and not connector else 0
	var image: Image = Image.create_from_data(_side, _side, false, Image.FORMAT_RGBA8, _bytes)
	var field: Image = Image.create_from_data(_side, _side, false, Image.FORMAT_RGB8, _field)
	if editor_texture == null:
		editor_texture = ImageTexture.create_from_image(image)
		editor_field = ImageTexture.create_from_image(field)
	else:
		editor_texture.update(image)
		editor_field.update(field)

func _editor_level(c: Vector2i, cache: Dictionary) -> int:
	if cache.has(c):
		return int(cache[c])
	var pos: Vector2 = Vector2(c) * 4.0 + Vector2(2, 2)
	var uv: Vector2 = pos / TILE - Vector2(0.5, 0.5)
	var x: int = floori(uv.x)
	var y: int = floori(uv.y)
	var wobble: float = _wobble_image.get_pixel(posmod(int(pos.x), 256), posmod(int(pos.y), 256)).r - 128.0 / 255.0
	var result: int = 0
	for ch: int in 3:
		var amount: float = lerpf(lerpf(_field_at(x, y, ch), _field_at(x + 1, y, ch), uv.x - x), lerpf(_field_at(x, y + 1, ch), _field_at(x + 1, y + 1, ch), uv.x - x), uv.y - y)
		if amount + wobble > 0.5:
			result += 1
	cache[c] = result
	return result
