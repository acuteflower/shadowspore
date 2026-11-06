class_name PixelText
extends RefCounted
## Tiny 3x5 pixel font. Cached meshes retain the original pixel layout at every scale.
## Upper case only (lower case is folded), with Ä Ö Ü ß. One pixel per font pixel, so it stays crisp at any scale.

const ADVANCE: int = 4
const HEIGHT: int = 7 ## 5 rows plus 2 above for umlaut dots
const ACCENTS: Dictionary = {"Ä": "A", "Ö": "O", "Ü": "U"}
const GLYPHS: Dictionary = {
	"A": [".X.", "X.X", "XXX", "X.X", "X.X"],
	"B": ["XX.", "X.X", "XX.", "X.X", "XX."],
	"C": [".XX", "X..", "X..", "X..", ".XX"],
	"D": ["XX.", "X.X", "X.X", "X.X", "XX."],
	"E": ["XXX", "X..", "XX.", "X..", "XXX"],
	"F": ["XXX", "X..", "XX.", "X..", "X.."],
	"G": [".XX", "X..", "X.X", "X.X", ".XX"],
	"H": ["X.X", "X.X", "XXX", "X.X", "X.X"],
	"I": ["XXX", ".X.", ".X.", ".X.", "XXX"],
	"J": ["..X", "..X", "..X", "X.X", ".X."],
	"K": ["X.X", "X.X", "XX.", "X.X", "X.X"],
	"L": ["X..", "X..", "X..", "X..", "XXX"],
	"M": ["X.X", "XXX", "XXX", "X.X", "X.X"],
	"N": ["XX.", "X.X", "X.X", "X.X", "X.X"],
	"O": [".X.", "X.X", "X.X", "X.X", ".X."],
	"P": ["XX.", "X.X", "XX.", "X..", "X.."],
	"Q": [".X.", "X.X", "X.X", "XX.", ".XX"],
	"R": ["XX.", "X.X", "XX.", "X.X", "X.X"],
	"S": [".XX", "X..", ".X.", "..X", "XX."],
	"T": ["XXX", ".X.", ".X.", ".X.", ".X."],
	"U": ["X.X", "X.X", "X.X", "X.X", "XXX"],
	"V": ["X.X", "X.X", "X.X", "X.X", ".X."],
	"W": ["X.X", "X.X", "XXX", "XXX", "X.X"],
	"X": ["X.X", "X.X", ".X.", "X.X", "X.X"],
	"Y": ["X.X", "X.X", ".X.", ".X.", ".X."],
	"Z": ["XXX", "..X", ".X.", "X..", "XXX"],
	"0": ["XXX", "X.X", "X.X", "X.X", "XXX"],
	"1": [".X.", "XX.", ".X.", ".X.", "XXX"],
	"2": ["XXX", "..X", "XXX", "X..", "XXX"],
	"3": ["XXX", "..X", "XXX", "..X", "XXX"],
	"4": ["X.X", "X.X", "XXX", "..X", "..X"],
	"5": ["XXX", "X..", "XXX", "..X", "XXX"],
	"6": ["XXX", "X..", "XXX", "X.X", "XXX"],
	"7": ["XXX", "..X", "..X", ".X.", ".X."],
	"8": ["XXX", "X.X", "XXX", "X.X", "XXX"],
	"9": ["XXX", "X.X", "XXX", "..X", "XXX"],
	".": ["...", "...", "...", "...", ".X."],
	",": ["...", "...", "...", ".X.", "X.."],
	":": ["...", ".X.", "...", ".X.", "..."],
	"-": ["...", "...", "XXX", "...", "..."],
	"+": ["...", ".X.", "XXX", ".X.", "..."],
	"/": ["..X", "..X", ".X.", "X..", "X.."],
	"%": ["X.X", "..X", ".X.", "X..", "X.X"],
	"!": [".X.", ".X.", ".X.", "...", ".X."],
	"?": ["XX.", "..X", ".X.", "...", ".X."],
	"&": [".X.", "X.X", ".X.", "X.X", ".XX"],
}


const CACHE_LIMIT: int = 512
static var _meshes: Dictionary = {}
static var _cache_order: Array[String] = []


static func width(text: String) -> int:
	return maxi(text.length() * ADVANCE - 1, 0)


## Draws `text` with its top-left at `pos`. A non-transparent `outline` adds a 1px border.
static func draw(canvas: CanvasItem, text: String, pos: Vector2i, color: Color, outline: Color = Color(0, 0, 0, 0)) -> void:
	var mesh: Mesh = _mesh(text)
	if mesh == null or mesh.get_surface_count() == 0: return
	# Canvas draw commands store mesh RIDs. Keep resources alive for static widgets
	# even after the shared cache evicts a label; replace references on their next draw.
	var retained: Dictionary = canvas.get_meta(&"_pixel_text_draw", {})
	var frame: int = Engine.get_process_frames()
	if int(retained.get("frame", -1)) != frame:
		retained = {"frame": frame, "meshes": {}}
		canvas.set_meta(&"_pixel_text_draw", retained)
	(retained.meshes as Dictionary)[mesh.get_instance_id()] = mesh
	if outline.a > 0.0:
		for offset: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			canvas.draw_mesh(mesh, null, Transform2D(0.0, Vector2(pos + offset)), outline)
	canvas.draw_mesh(mesh, null, Transform2D(0.0, Vector2(pos)), color)


## Keep the five passes (four outline offsets, then ink) separate: translucent
## outlines overlap exactly as before. Untextured quads preserve hard pixel edges
## even on a CanvasItem with linear texture filtering or a scaled clock display.
static func _mesh(text: String) -> Mesh:
	var normalized: String = text.replace("ß", "SS").to_upper()
	if normalized.is_empty(): return null
	if _meshes.has(normalized): return _meshes[normalized]
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var x: int = 0
	for character: String in normalized:
		var base: String = ACCENTS.get(character, character)
		if GLYPHS.has(base):
			var rows: Array = GLYPHS[base]
			for row: int in 5:
				for col: int in 3:
					if rows[row][col] == "X": _pixel(vertices, indices, x + col, 2 + row)
			if ACCENTS.has(character):
				_pixel(vertices, indices, x, 0)
				_pixel(vertices, indices, x + 2, 0)
		x += ADVANCE
	var mesh: ArrayMesh = ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _meshes.size() >= CACHE_LIMIT:
		_meshes.erase(_cache_order.pop_front())
	_meshes[normalized] = mesh
	_cache_order.append(normalized)
	return mesh


static func _pixel(vertices: PackedVector3Array, indices: PackedInt32Array, x: int, y: int) -> void:
	var first: int = vertices.size()
	vertices.append_array(PackedVector3Array([Vector3(x, y, 0), Vector3(x + 1, y, 0), Vector3(x + 1, y + 1, 0), Vector3(x, y + 1, 0)]))
	indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
