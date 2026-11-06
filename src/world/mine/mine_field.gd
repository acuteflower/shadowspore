class_name MineField
extends RefCounted
## The smooth shape of the rock around one chunk of a mine level. The tile grid (floor / wall) is upsampled to a field of 4 px cells, blurred twice with a box
## (so the corners round off) and bent with two octaves of value noise (so the walls wobble like hewn and fallen rock). The contour at 0.5 is the real edge:
## `mine_terrain.gdshader` draws it (floor, wall face, rock top) and `segments()` turns it into the collision, so what you see is what stops you.
## The field covers the chunk plus `MARGIN` tiles on every side (a wall face looks up to 48 px past the chunk's edge); outside the level it is rock.

const CELL: int = 4 ## px per cell
const MARGIN: int = 3 ## tiles around the chunk
const BLUR: int = 3 ## box radius in cells, two passes
const SIDE: int = (MineChunk.SIZE + 2 * MARGIN) * 4 ## cells per side

var chunk: Vector2i
var values: PackedFloat32Array = PackedFloat32Array() ## SIDE * SIDE, 0 floor .. 1 rock
var kinds: Image ## one pixel per tile (chunk + margin): the floor's material, see `kind_of`
var seed_value: int = 0


## Floor material per room type (docs/mine.md: the look of the ground follows what the room is for).
static func kind_of(type: String) -> int:
	match type:
		"entry", "exit", "junction", "treasure": return 1 ## flagstones
		"rest", "storage", "bunks": return 2 ## planks
		"wet": return 3 ## mud
		"spider_nest": return 4 ## dark earth
		"forge": return 5 ## ash
	return 0 ## hewn rock (6, a bed of gravel, lies under the rails)


func build(layout: MineLayout, chunk_cell: Vector2i) -> MineField:
	chunk = chunk_cell
	seed_value = layout.world_seed + layout.level * 977
	var tiles: int = MineChunk.SIZE + 2 * MARGIN
	var tx0: int = chunk.x * MineChunk.SIZE - MARGIN
	var ty0: int = chunk.y * MineChunk.SIZE - MARGIN
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(SIDE * SIDE)
	kinds = Image.create(tiles, tiles, false, Image.FORMAT_R8)
	var ballast: Dictionary = {} ## tiles with rails on them
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			for rail: Vector3i in layout.chunk_rails.get(chunk + Vector2i(dx, dy), []) as Array:
				ballast[Vector2i(rail.x, rail.y)] = true
	for ty: int in tiles:
		for tx: int in tiles:
			if layout.is_floor(tx0 + tx, ty0 + ty):
				var room: int = layout.room_at(tx0 + tx, ty0 + ty)
				var kind: int = 6 if ballast.has(Vector2i(tx0 + tx, ty0 + ty)) else 0
				if room >= 0:
					var rect: Rect2i = layout.rooms[room].rect as Rect2i
					if rect.has_point(Vector2i(tx0 + tx, ty0 + ty)):
						kind = kind_of(String(layout.rooms[room].type))
				kinds.set_pixel(tx, ty, Color8(kind, 0, 0))
				continue
			for cy: int in 4:
				var row: int = (ty * 4 + cy) * SIDE + tx * 4
				for cx: int in 4:
					raw[row + cx] = 1.0
	var blurred: PackedFloat32Array = _blur(_blur(raw))
	_bend(blurred, tx0 * 4, ty0 * 4, 3, 11, 0.20)
	_bend(blurred, tx0 * 4, ty0 * 4, 7, 29, 0.14)
	for ty: int in tiles: ## the middle of every tile keeps its kind: a one-tile pillar stays a pillar, a one-tile gap stays a gap
		for tx: int in tiles:
			var wall: bool = raw[(ty * 4 + 1) * SIDE + tx * 4 + 1] > 0.5
			for cy: int in range(1, 3):
				for cx: int in range(1, 3):
					var at: int = (ty * 4 + cy) * SIDE + tx * 4 + cx
					blurred[at] = maxf(blurred[at], 0.64) if wall else minf(blurred[at], 0.36)
	values = blurred
	return self


## Two box blurs (rows, then columns), edges repeat.
func _blur(src: PackedFloat32Array) -> PackedFloat32Array:
	var tmp: PackedFloat32Array = PackedFloat32Array()
	tmp.resize(SIDE * SIDE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(SIDE * SIDE)
	var width: float = float(BLUR * 2 + 1)
	for j: int in SIDE:
		var row: int = j * SIDE
		var sum: float = src[row] * float(BLUR + 1)
		for k: int in range(1, BLUR + 1):
			sum += src[row + mini(k, SIDE - 1)]
		for i: int in SIDE:
			tmp[row + i] = sum / width
			sum += src[row + mini(i + BLUR + 1, SIDE - 1)] - src[row + maxi(i - BLUR, 0)]
	for i: int in SIDE:
		var sum: float = tmp[i] * float(BLUR + 1)
		for k: int in range(1, BLUR + 1):
			sum += tmp[mini(k, SIDE - 1) * SIDE + i]
		for j: int in SIDE:
			out[j * SIDE + i] = sum / width
			sum += tmp[mini(j + BLUR + 1, SIDE - 1) * SIDE + i] - tmp[maxi(j - BLUR, 0) * SIDE + i]
	return out


## Adds value noise (lattice every `scale` cells, +-amp/2) to the field: the lattice is hashed once, the cells only interpolate.
func _bend(field_values: PackedFloat32Array, gx0: int, gy0: int, scale: int, salt: int, amp: float) -> void:
	var ix0: int = floori(float(gx0) / float(scale))
	var iy0: int = floori(float(gy0) / float(scale))
	var n: int = SIDE / scale + 3
	var lattice: PackedFloat32Array = PackedFloat32Array()
	lattice.resize(n * n)
	for j: int in n:
		for i: int in n:
			lattice[j * n + i] = MineGenerator._hash2(ix0 + i, iy0 + j, seed_value + salt)
	var col_i: PackedInt32Array = PackedInt32Array()
	var col_t: PackedFloat32Array = PackedFloat32Array()
	col_i.resize(SIDE)
	col_t.resize(SIDE)
	for i: int in SIDE:
		var f: float = float(gx0 + i) / float(scale)
		col_i[i] = floori(f) - ix0
		var t: float = f - floorf(f)
		col_t[i] = t * t * (3.0 - 2.0 * t)
	for j: int in SIDE:
		var fy: float = float(gy0 + j) / float(scale)
		var iy: int = floori(fy) - iy0
		var ty: float = fy - floorf(fy)
		ty = ty * ty * (3.0 - 2.0 * ty)
		var row_a: int = iy * n
		var row_b: int = row_a + n
		for i: int in SIDE:
			var k: int = col_i[i]
			var tx: float = col_t[i]
			var top: float = lattice[row_a + k] + (lattice[row_a + k + 1] - lattice[row_a + k]) * tx
			var bottom: float = lattice[row_b + k] + (lattice[row_b + k + 1] - lattice[row_b + k]) * tx
			var at: int = j * SIDE + i
			field_values[at] = clampf(field_values[at] + (top + (bottom - top) * ty - 0.5) * amp, 0.0, 1.0)


func texture() -> ImageTexture:
	var image: Image = Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_R8, _bytes())
	return ImageTexture.create_from_image(image)


func _bytes() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SIDE * SIDE)
	for i: int in SIDE * SIDE:
		bytes[i] = int(clampf(values[i], 0.0, 1.0) * 255.0)
	return bytes


## Origin of the field in chunk px (negative: the margin).
static func origin_px() -> Vector2:
	return Vector2(-MARGIN * MineChunk.TILE, -MARGIN * MineChunk.TILE)


## Is this point (chunk px) rock? Bilinear, like the shader.
func is_rock(p: Vector2) -> bool:
	var u: float = (p.x - origin_px().x) / float(CELL) - 0.5
	var v: float = (p.y - origin_px().y) / float(CELL) - 0.5
	var i: int = clampi(floori(u), 0, SIDE - 2)
	var j: int = clampi(floori(v), 0, SIDE - 2)
	var tx: float = clampf(u - float(i), 0.0, 1.0)
	var ty: float = clampf(v - float(j), 0.0, 1.0)
	var top: float = lerpf(values[j * SIDE + i], values[j * SIDE + i + 1], tx)
	var bottom: float = lerpf(values[(j + 1) * SIDE + i], values[(j + 1) * SIDE + i + 1], tx)
	return lerpf(top, bottom, ty) >= 0.5


## The contour as line segments (chunk px, pairs of points): marching squares over the cells whose corner lies inside the chunk, so neighbours join exactly.
func segments() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var o: Vector2 = origin_px()
	var first: int = MARGIN * 4 ## the cell column / row where the chunk starts
	var last: int = first + MineChunk.SIZE * 4 ## one past: squares starting here belong to the next chunk
	for j: int in range(first - 1, last):
		for i: int in range(first - 1, last):
			var tl: float = values[j * SIDE + i]
			var tr: float = values[j * SIDE + i + 1]
			var br: float = values[(j + 1) * SIDE + i + 1]
			var bl: float = values[(j + 1) * SIDE + i]
			var index: int = (8 if tl >= 0.5 else 0) | (4 if tr >= 0.5 else 0) | (2 if br >= 0.5 else 0) | (1 if bl >= 0.5 else 0)
			if index == 0 or index == 15:
				continue
			var x: float = (float(i) + 0.5) * float(CELL) + o.x
			var y: float = (float(j) + 0.5) * float(CELL) + o.y
			if x < 0.0 or y < 0.0 or x >= float(MineChunk.SIZE * MineChunk.TILE) or y >= float(MineChunk.SIZE * MineChunk.TILE):
				continue
			var top: Vector2 = Vector2(x + _cross(tl, tr) * float(CELL), y)
			var bottom: Vector2 = Vector2(x + _cross(bl, br) * float(CELL), y + float(CELL))
			var left: Vector2 = Vector2(x, y + _cross(tl, bl) * float(CELL))
			var right: Vector2 = Vector2(x + float(CELL), y + _cross(tr, br) * float(CELL))
			var centre_rock: bool = (tl + tr + br + bl) * 0.25 >= 0.5
			var lines: Array = []
			match index:
				1, 14: lines = [left, bottom]
				2, 13: lines = [bottom, right]
				3, 12: lines = [left, right]
				4, 11: lines = [top, right]
				6, 9: lines = [top, bottom]
				7, 8: lines = [left, top]
				5: lines = [left, top, bottom, right] if centre_rock else [top, right, left, bottom]
				10: lines = [top, right, left, bottom] if centre_rock else [left, top, bottom, right]
			for k: int in range(0, lines.size(), 2):
				out.append(lines[k] as Vector2)
				out.append(lines[k + 1] as Vector2)
	return out


## Where between two cell values the 0.5 level lies (0..1).
static func _cross(a: float, b: float) -> float:
	return clampf((0.5 - a) / (b - a), 0.0, 1.0) if absf(b - a) > 0.0001 else 0.5
