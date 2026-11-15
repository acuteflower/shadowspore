class_name Relief
extends RefCounted
## The world's height levels (baked by tools/bake_relief.py into assets/world/relief.png, 1 pixel
## per tile; layout in that script). Heights are flat map data, not a third dimension: a plateau
## is a region at a higher level with a smooth contour (relief_field.png, the blurred level masks),
## the 3/4 camera sees a 32 px wall below its south contour, the other edges are thin walls, and
## ramps, stairs and rock steps (`RAMP`, `STAIRS`, `STEPS`, whole tiles in relief.png) connect
## the levels on foot. The collision comes from relief_block.png (4 px cells, baked with the
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

static var _cache_key: String = ""
static var _cache_bytes: PackedByteArray = PackedByteArray()
static var _cache_field: PackedByteArray = PackedByteArray()
static var _cache_block: PackedByteArray = PackedByteArray()
static var _cache_side: int = 0
static var _cache_block_side: int = 0
static var _cache_town_cells: int = 0
static var _cache_wobble: Image = null


static func cache_key_for(active_biome: String, own_biomes: Array, use_town_styles: bool) -> String:
	return "%s:%s:%d" % [active_biome, str(own_biomes), 1 if use_town_styles else 0]


static func has_cache(expected_key: String) -> bool:
	return _cache_key == expected_key and not _cache_bytes.is_empty()


## Pure byte-array computation of base relief data; safe to run on a worker thread (all Images & tables passed in).
static func build_base_data(tex_img: Image, field_img: Image, block_img: Image, active_biome: String, own_biomes: Array, biomes_keys: Array, hallgrat_data: Dictionary, use_town_styles: bool) -> Dictionary:
	var img: Image = tex_img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = img.get_data()
	var side: int = img.get_width()
	_apply_world_biome_bytes(bytes, active_biome, own_biomes, biomes_keys)
	var changed_cells: int = _apply_town_styles_bytes(bytes, side, hallgrat_data) if use_town_styles else 0
	var f_img: Image = field_img.duplicate() as Image
	f_img.convert(Image.FORMAT_RGB8)
	var b_img: Image = block_img.duplicate() as Image
	b_img.convert(Image.FORMAT_L8)
	return {
		"key": cache_key_for(active_biome, own_biomes, use_town_styles),
		"bytes": bytes,
		"field": f_img.get_data(),
		"block": b_img.get_data(),
		"side": side,
		"block_side": b_img.get_width(),
		"town_cells": changed_cells,
	}


static func store_cache(built: Dictionary, wobble_img: Image) -> void:
	_cache_key = String(built.get("key", ""))
	_cache_bytes = built.get("bytes", PackedByteArray()) as PackedByteArray
	_cache_field = built.get("field", PackedByteArray()) as PackedByteArray
	_cache_block = built.get("block", PackedByteArray()) as PackedByteArray
	_cache_side = int(built.get("side", 0))
	_cache_block_side = int(built.get("block_side", 0))
	_cache_town_cells = int(built.get("town_cells", 0))
	_cache_wobble = wobble_img
	Jobs.register_cleanup(Relief.clear_cache)


static func clear_cache() -> void:
	_cache_key = ""
	_cache_bytes = PackedByteArray()
	_cache_field = PackedByteArray()
	_cache_block = PackedByteArray()
	_cache_side = 0
	_cache_block_side = 0
	_cache_town_cells = 0
	_cache_wobble = null


func _init() -> void:
	var world_map_data: Dictionary = DataRegistry.table("world_map")
	var active: String = String(world_map_data.get("biome", ""))
	var own: Array = world_map_data.get("own_biomes", []) as Array
	var expected: String = cache_key_for(active, own, town_styles)
	if not has_cache(expected):
		var built: Dictionary = build_base_data(
			TEXTURE.get_image(),
			FIELD.get_image(),
			BLOCK.get_image(),
			active,
			own,
			DataRegistry.table("biomes").keys(),
			DataRegistry.table("hallgrat"),
			town_styles
		)
		store_cache(built, WOBBLE.get_image())
	_side = _cache_side
	_block_side = _cache_block_side
	town_cells = _cache_town_cells
	_bytes = _cache_bytes.duplicate()
	_field = _cache_field.duplicate()
	_block = _cache_block
	_wobble_image = _cache_wobble


## Hallgrat's stone (docs/stadt_westen_konzept.md 14.2): data/hallgrat.json `style_areas` restyle the tiles of whole districts at load time,
## after the shared meadow look: masonry walls (2) in the town, crystal veins (3) in the Glasbruch, the void (4) eating the lost quarter, and
## the rock steps in masonry areas become cut stairs (`stairs`: kind STEPS -> STAIRS). Only the style nibble and that connector kind change;
## heights, connector geometry, the field and the collision stay as baked (both kinds are connectors to every query). Returns the cells it changed.
## `town_styles` false (tests) leaves the bake's look alone.
static var town_styles: bool = true
var town_cells: int = 0


func _apply_town_styles() -> int:
	return _apply_town_styles_bytes(_bytes, _side, DataRegistry.table("hallgrat"))


static func _apply_town_styles_bytes(bytes: PackedByteArray, side: int, data: Dictionary) -> int:
	var areas: Array = data.get("style_areas", []) as Array
	var box: Array = data.get("style_rect", []) as Array
	if areas.is_empty() or box.size() != 4:
		return 0
	var polys: Dictionary = {}
	for d: Dictionary in data.get("districts", []) as Array:
		var poly: PackedVector2Array = PackedVector2Array()
		for at: Array in d.poly as Array:
			poly.append(Vector2(float(at[0]), float(at[1])))
		polys[String(d.id)] = poly
	var changed: int = 0
	for y: int in range(maxi(0, int(box[1])), mini(side, int(box[3]))):
		for x: int in range(maxi(0, int(box[0])), mini(side, int(box[2]))):
			var idx: int = (y * side + x) * 4
			if bytes[idx + 3] == 0:
				continue
			var centre: Vector2 = Vector2(x + 0.5, y + 0.5)
			var pick: Dictionary = {}
			for area: Dictionary in areas: ## later areas win where districts overlap
				for id: Variant in area.districts as Array:
					if polys.has(String(id)) and Geometry2D.is_point_in_polygon(centre, polys[String(id)] as PackedVector2Array):
						pick = area
			if pick.is_empty():
				continue
			var k: int = bytes[idx + 1] & 15
			if bool(pick.get("stairs", false)) and k == STEPS:
				k = STAIRS
			var value: int = k | (int(pick.style) << 4)
			if value != bytes[idx + 1]:
				bytes[idx + 1] = value
				changed += 1
	return changed


## Restyle materials without moving heights, walls, connectors or collision cells.
## The immutable bake keeps its original material ids for future authoring.
func _apply_world_biome() -> void:
	var world_map_data: Dictionary = DataRegistry.table("world_map")
	var active: String = String(world_map_data.get("biome", ""))
	_apply_world_biome_bytes(_bytes, active, world_map_data.get("own_biomes", []) as Array, DataRegistry.table("biomes").keys())


static func _apply_world_biome_bytes(bytes: PackedByteArray, active: String, own_biomes: Array, ids: Array) -> void:
	if active.is_empty():
		return
	var biome: int = ids.find(active)
	if biome < 0:
		return
	var own: Array = []
	for id: Variant in own_biomes: ## biomes of their own keep the bake's biome byte
		own.append(200 + ids.find(String(id)))
	for i: int in range(0, bytes.size(), 4):
		if bytes[i + 3] == 0 or own.has(int(bytes[i + 3])):
			continue
		bytes[i + 3] = 200 + biome
		if active == "meadow":
			var style: int = bytes[i + 1] >> 4
			if style >= 2:
				bytes[i + 1] = (bytes[i + 1] & 15) | ((0 if style == 4 else 1) << 4)


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


## True if any land tile in `rect` (tile coordinates) has crystal (3), void (4) or quartz-sandstone (6) style.
func has_glow_style(rect: Rect2i) -> bool:
	return (check_view_features(rect) & 1) != 0


## Bitmask for `rect` (tile coordinates): bit 0 = has glow style (3, 4, or 6), bit 1 = has elevated terrain (level > 0).
func check_view_features(rect: Rect2i) -> int:
	var x0: int = maxi(0, rect.position.x)
	var y0: int = maxi(0, rect.position.y)
	var x1: int = mini(_side, rect.end.x)
	var y1: int = mini(_side, rect.end.y)
	var mask: int = 0
	for y: int in range(y0, y1):
		var row: int = y * _side * 4
		for x: int in range(x0, x1):
			var idx: int = row + x * 4
			if _bytes[idx] > 0:
				mask |= 2
			if _bytes[idx + 3] != 0: ## land
				var st: int = _bytes[idx + 1] >> 4
				if st == 3 or st == 4 or st == 6:
					mask |= 1
			if mask == 3:
				return 3
	return mask


## Where a prop or a player can stand: land that is no wall face.
func walkable(x: int, y: int) -> bool:
	return is_land(x, y) and kind(x, y) != FACE


## The height a point stands at: the smooth level (what the shader draws), plus the fraction up a ramp or flight of stairs.
func level_at(pos: Vector2) -> float:
	return sample_level_at(_bytes, _field, _side, pos)


static func sample_level_at(bytes: PackedByteArray, field: PackedByteArray, side: int, pos: Vector2) -> float:
	var inv_tile: float = 1.0 / TILE
	var ux: float = pos.x * inv_tile - 0.5
	var uy: float = pos.y * inv_tile - 0.5
	var x0: int = floori(ux)
	var y0: int = floori(uy)
	var wx: float = ux - x0
	var wy: float = uy - y0
	var max_s: int = side - 1
	var cx0: int = 0 if x0 < 0 else (max_s if x0 > max_s else x0)
	var cx1: int = 0 if x0 + 1 < 0 else (max_s if x0 + 1 > max_s else x0 + 1)
	var cy0: int = 0 if y0 < 0 else (max_s if y0 > max_s else y0)
	var cy1: int = 0 if y0 + 1 < 0 else (max_s if y0 + 1 > max_s else y0 + 1)
	var row0: int = cy0 * side
	var row1: int = cy1 * side
	var i00: int = (row0 + cx0) * 3
	var i10: int = (row0 + cx1) * 3
	var i01: int = (row1 + cx0) * 3
	var i11: int = (row1 + cx1) * 3
	var height: float = 0.0
	for channel: int in 3:
		var a: float = field[i00 + channel] + (field[i10 + channel] - field[i00 + channel]) * wx
		var b: float = field[i01 + channel] + (field[i11 + channel] - field[i01 + channel]) * wx
		if a + (b - a) * wy > 127.5:
			height += 1.0
	var x: int = floori(pos.x * inv_tile)
	var y: int = floori(pos.y * inv_tile)
	var k: int = 0 if (x < 0 or y < 0 or x >= side or y >= side) else (bytes[(y * side + x) * 4 + 1] & 15)
	if k >= RAMP:
		var geom: int = bytes[(y * side + x) * 4 + 2]
		var depth: int = ((geom >> 2) & 3) + 1
		height += (depth - (geom & 3) - fposmod(pos.y, TILE) * inv_tile) / depth
	return height


static func _sample_field_at(field: PackedByteArray, side: int, x: int, y: int, channel: int) -> float:
	var cx: int = clampi(x, 0, side - 1)
	var cy: int = clampi(y, 0, side - 1)
	return field[(cy * side + cx) * 3 + channel] / 255.0


func _field_at(x: int, y: int, channel: int) -> float:
	return _sample_field_at(_field, _side, x, y, channel)


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


func blocked_at(point: Vector2) -> bool:
	var cell: Vector2i = Vector2i((point / (TILE / CELLS)).floor())
	return cell.x >= 0 and cell.y >= 0 and cell.x < _block_side and cell.y < _block_side and _block[cell.y * _block_side + cell.x] != 0


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
var _block_dirty: bool = false

func editor_apply(edits: Dictionary) -> void:
	var first_apply: bool = editor_texture == null
	if first_apply:
		var world_map_data: Dictionary = DataRegistry.table("world_map")
		var expected: String = cache_key_for(String(world_map_data.get("biome", "")), world_map_data.get("own_biomes", []) as Array, town_styles)
		_base_bytes = _cache_bytes if has_cache(expected) else _bytes.duplicate()
		_base_field = _cache_field if has_cache(expected) else _field.duplicate()
		_base_block = _cache_block if has_cache(expected) else _block.duplicate()
		if _wobble_image == null:
			_wobble_image = WOBBLE.get_image()
	if not first_apply or not edits.is_empty():
		_bytes = _base_bytes.duplicate()
		_field = _base_field.duplicate()
		if _block_dirty or not edits.is_empty():
			_block = _base_block.duplicate()
			_block_dirty = false
		else:
			_block = _base_block
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
	if not patches.is_empty() and not _block_dirty:
		_block = _base_block.duplicate()
		_block_dirty = true
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
