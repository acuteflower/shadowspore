class_name VoidTitle
extends ColorRect
## A word in the shadow face (docs/void_face.md): razor letters of black void flesh with a cold violet rim, a pulsing magenta vein along every thick
## stroke, glimmering stars, an aura of violet dust, edges that morph and tendrils that melt down from them. It condenses out of smoke (`reveal`) and
## crumbles upwards (`dissolve`). Used for the names of bosses (`BossIntro`, `BossBar`); anything that belongs to the void may use it.
## `setup(text, face)` composes the word from the atlas (assets/ui/void_face_<face>.png, metrics data/void_face.json, both made by
## `py -3 tools/art_void_face.py`) into one texture with room round it for the aura and the tendrils; the shader (assets/shaders/void_title.gdshader) does the rest.
## Faces: "big" (cap height 44 px), "small" (17 px) and "tiny" (11 px, the boss bar). The face is shown 1:1 (never scaled): it is drawn for the 640 x 360 picture.
## `set_ink(1.0)` makes the word blacker (a black outline, a dimmer rim): for words on a busy picture.
## `place(cap_left, cap_top)` puts the word so that its first letter's top left corner of the capitals is at that point.

const SHADER: Shader = preload("res://assets/shaders/void_title.gdshader")
const MARGIN: int = 26 ## px of room round the word (aura, tendrils)

static var _meta: Dictionary = {}
static var _atlas: Dictionary = {} ## face -> PackedByteArray (RGBA8), plus size
static var _cache: Dictionary = {} ## "face|text" -> ImageTexture

var text: String = ""
var face: String = "big"
var ink_size: Vector2i = Vector2i.ZERO ## the letters only (without the room round them)
var cap_top: int = 0 ## row of the top of the capitals inside the texture
var baseline: int = 0 ## row of the baseline inside the texture
var lead: int = 0 ## column where the first letter's box starts
var _material: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0
var _seed: float = 0.0


static func metrics() -> Dictionary:
	if _meta.is_empty():
		_meta = DataRegistry.table("void_face")
	return _meta


static func _normalize(value: String) -> String:
	return value.replace("ß", "SS").to_upper()


## Builds the word: the texture, the metrics and the shader. Safe to call again with another text.
func setup(p_text: String, p_face: String = "big", p_seed: float = 0.0) -> void:
	text = p_text
	face = p_face
	_seed = p_seed
	var f: Dictionary = (metrics()["faces"] as Dictionary)[face] as Dictionary
	var texture: ImageTexture = _compose(text, face)
	var meta: Dictionary = _layout(text, face)
	ink_size = Vector2i(int(meta["width"]), int(f["cap"]))
	cap_top = MARGIN + int(f["top"])
	baseline = MARGIN + int(f["baseline"])
	lead = MARGIN + int(meta["lead"])
	size = Vector2(texture.get_width(), texture.get_height())
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = SHADER
	_material.set_shader_parameter("face", texture)
	_material.set_shader_parameter("tex_size", Vector2(texture.get_width(), texture.get_height()))
	_material.set_shader_parameter("sdf_range", float(metrics()["sdf_range"]))
	_material.set_shader_parameter("margin", float(MARGIN))
	_material.set_shader_parameter("seed", _seed)
	_material.set_shader_parameter("goo", 1.0 if face == "big" else 0.0)
	_material.set_shader_parameter("detail", clampf(float(f["cap"]) / 44.0 * 1.15, 0.25, 1.0))
	material = _material
	set_look(1.4, 0.0, 0.0, 1.0, 1.0)


## reveal 0..1.4 (the letters condense, left to right), dissolve 0..1 (they crumble upwards), glitch 0..1, power 0..1 (how alive: morph and aura), drip 0..1.
func set_look(reveal: float, dissolve: float, glitch: float, power: float, drip: float) -> void:
	_material.set_shader_parameter("reveal", reveal)
	_material.set_shader_parameter("dissolve", dissolve)
	_material.set_shader_parameter("glitch", glitch)
	_material.set_shader_parameter("power", power)
	_material.set_shader_parameter("drip", drip)


## 0..1: blacker (a black outline round the letters, a dimmer rim and aura).
func set_ink(amount: float) -> void:
	_material.set_shader_parameter("ink", amount)


## Puts the word so that the top left corner of the capitals of its first letter lies at `cap_left_top`.
func place(cap_left_top: Vector2) -> void:
	position = (cap_left_top - Vector2(lead, cap_top)).round()


func _process(delta: float) -> void:
	_clock += delta
	_material.set_shader_parameter("time", _clock)


# --- composing -----------------------------------------------------------------------------------------------------


## Where every letter goes: {entries: [[char, x]], width (px of the letters without the gap after the last), lead}.
static func _layout(value: String, face_name: String) -> Dictionary:
	var f: Dictionary = (metrics()["faces"] as Dictionary)[face_name] as Dictionary
	var glyphs: Dictionary = f["glyphs"] as Dictionary
	var entries: Array = []
	var x: int = 0
	var first_lead: int = 0
	for character: String in _normalize(value):
		if character == " ":
			x += int(f["space"])
			continue
		if not glyphs.has(character):
			continue
		var g: Dictionary = glyphs[character] as Dictionary
		if entries.is_empty():
			first_lead = int(g["lead"])
		entries.append([character, x])
		x += int(g["adv"])
	return {"entries": entries, "width": maxi(x - int(round(float(f["cap"]) * 0.13)), 1), "lead": first_lead, "end": x}


static func _compose(value: String, face_name: String) -> ImageTexture:
	var key: String = "%s|%s" % [face_name, _normalize(value)]
	if _cache.has(key):
		return _cache[key] as ImageTexture
	var f: Dictionary = (metrics()["faces"] as Dictionary)[face_name] as Dictionary
	var glyphs: Dictionary = f["glyphs"] as Dictionary
	if not _atlas.has(face_name):
		var image: Image = (load(String(f["image"])) as Texture2D).get_image()
		image.convert(Image.FORMAT_RGBA8)
		_atlas[face_name] = {"data": image.get_data(), "w": image.get_width()}
	var src: PackedByteArray = (_atlas[face_name] as Dictionary)["data"] as PackedByteArray
	var src_w: int = int((_atlas[face_name] as Dictionary)["w"])
	var layout: Dictionary = _layout(value, face_name)
	var glyph_h: int = int(f["height"])
	var total_w: int = int(layout["end"]) + int(layout["lead"]) * 2 + 2 * MARGIN + 8
	var total_h: int = glyph_h + 2 * MARGIN
	var dst: PackedByteArray = PackedByteArray()
	dst.resize(total_w * total_h * 4)
	for i: int in range(3, dst.size(), 4):
		dst[i] = 255
	for entry: Array in layout["entries"] as Array:
		var g: Dictionary = glyphs[entry[0]] as Dictionary
		var gx: int = int(g["x"])
		var gw: int = int(g["w"])
		var ox: int = MARGIN + int(entry[1]) - int(g["lead"]) + int(layout["lead"])
		for y: int in glyph_h:
			var s_row: int = (y * src_w + gx) * 4
			var d_row: int = ((y + MARGIN) * total_w + ox) * 4
			for x: int in gw:
				var si: int = s_row + x * 4
				var di: int = d_row + x * 4
				if di < 0 or di + 3 >= dst.size():
					continue
				for c: int in 3:
					if src[si + c] > dst[di + c]:
						dst[di + c] = src[si + c]
	var image: Image = Image.create_from_data(total_w, total_h, false, Image.FORMAT_RGBA8, dst)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
