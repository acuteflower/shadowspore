class_name TalismanArt
extends RefCounted
## How jewellery looks on Ellie (docs/talisman_konzept.md section 5). The body sheets stay as they are: per frame of every sheet the player steers,
## `data/hero_jewelry.json` (tools/art_hero_jewelry.py) holds where the collar, the chest and the ear lobes are and how much the torso, head and ears face
## the camera; this class draws the chain, the pendant and the ear drops there, pixel by pixel, on any canvas (`TalismanLayer` on her sprite, the inventory doll).
## The bracelet sits on the sword arm that `AttackComponent` draws itself (`draw_bracelet`).
## A piece's picture is data in items.json `look`: `metal` (silver, gold, voidsteel, ravensteel), `stone` (colour) and the shapes `pendant` / `drop` as rows of letters:
## metal d m l h (dark .. highlight), stone s S T W (dark, mid, light, glint), '.' empty. Optional: `pulse` (the stone breathes like a void heart), `glow` (the
## stone shines on its own at night), `glint` (a light runs over the stone now and then), `stones` (how many, for the bracelet).
## A piece with the perk `ward` (the Rissfeder) goes dull while its wing beat is spent: the stone greys, no pulse, no glow (`dull` of `draw_worn`).

const STRIDE: int = 16
const SHEETS: Dictionary = {
	"player.png": "main", "player_attack.png": "attack", "player_pick.png": "pick", "player_eat.png": "eat", "player_pull.png": "pull",
	"player_touch.png": "touch", "player_heavy.png": "heavy", "player_fish.png": "fish", "player_standby.png": "standby",
}
const METALS: Dictionary = { ## dark .. highlight
	"silver": ["6b7392", "93a0bc", "d4dbec", "f6f9ff"],
	"gold": ["6a4a2a", "a07a3a", "d8b45a", "f6e0a0"],
	"voidsteel": ["14092e", "261a4a", "35227a", "7d57e0"],
	"ravensteel": ["14102a", "2c2150", "5a4a9a", "a08cf0"], ## blue-black with a violet sheen, a raven's feather (Rissfeder)
}
const INK: Color = Color("1b1a2e")
const TORSO_HIDDEN: int = -10 ## percent: the torso faces away: no chain, no pendant
const TORSO_FRONT: int = 35 ## above this the pendant shows its face, below it edge-on
const SIDE_HIDDEN: int = -15 ## a collar point or an ear whose side faces away from the camera
const HEAD_HIDDEN: int = -25 ## her face is turned away: the ears are in the hair

static var _frames: Dictionary = {} ## sheet name -> PackedInt32Array


## The 16 numbers of this frame of this sheet, empty when the sheet carries no jewellery data (a cutscene sheet).
static func frame_data(texture: Texture2D, frame: int) -> PackedInt32Array:
	if texture == null:
		return PackedInt32Array()
	var key: String = String(SHEETS.get(texture.resource_path.get_file(), ""))
	if key == "":
		return PackedInt32Array()
	if not _frames.has(key):
		var sheet: Dictionary = ((DataRegistry.table("hero_jewelry").get("sheets", {}) as Dictionary).get(key, {}) as Dictionary)
		var raw: Array = sheet.get("data", []) as Array
		var packed: PackedInt32Array = PackedInt32Array()
		packed.resize(raw.size())
		for i: int in raw.size():
			packed[i] = int(raw[i])
		_frames[key] = packed
	var all: PackedInt32Array = _frames[key]
	if frame < 0 or (frame + 1) * STRIDE > all.size():
		return PackedInt32Array()
	return all.slice(frame * STRIDE, (frame + 1) * STRIDE)


static func look_of(id: String) -> Dictionary:
	return (DataRegistry.get_entry("items", id).get("look", {}) as Dictionary)


static func metal(look: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	for hex: String in (METALS.get(String(look.get("metal", "silver")), METALS["silver"]) as Array):
		out.append(Color(hex))
	return out


## The colour of a letter of a shape: metal d m l h, stone s S T W.
static func letter_color(letter: String, ramp: Array[Color], stone: Color) -> Color:
	match letter:
		"d": return ramp[0]
		"m": return ramp[1]
		"l": return ramp[2]
		"h": return ramp[3]
		"s": return stone.darkened(0.5)
		"S": return stone
		"T": return stone.lightened(0.35)
		"W": return stone.lightened(0.8)
	return Color.TRANSPARENT


## Draws the worn necklaces and earrings of `ids` for one frame (`data` = frame_data). `origin` is where the feet are on `canvas`, `scale` the size of an art pixel;
## `glow` (may be the same canvas) gets the shining pixels; `night` 0..1 for the glow, `time` for sways and pulses.
static func draw_worn(canvas: CanvasItem, glow: CanvasItem, ids: PackedStringArray, data: PackedInt32Array, origin: Vector2, scale: float, time: float, night: float, flash: float = 0.0, dull: bool = false) -> void:
	if data.size() < STRIDE:
		return
	for id: String in ids:
		var def: Dictionary = DataRegistry.get_entry("items", id)
		var look: Dictionary = def.get("look", {}) as Dictionary
		match String(def.get("jewelry", "")):
			"necklace":
				_necklace(canvas, glow, look, data, origin, scale, time, night, dull and (def.get("perks", []) as Array).has("ward"))
			"earrings":
				_earrings(canvas, glow, look, data, origin, scale, time, night + flash)


static func _necklace(canvas: CanvasItem, glow: CanvasItem, look: Dictionary, d: PackedInt32Array, origin: Vector2, scale: float, time: float, night: float, dull: bool = false) -> void:
	if d[10] < TORSO_HIDDEN:
		return
	var ramp: Array[Color] = metal(look)
	var pendant: Vector2i = Vector2i(floori(d[4] / 10.0), floori(d[5] / 10.0))
	for side: int in 2:
		if d[14 + side] < SIDE_HIDDEN:
			continue
		var from: Vector2i = Vector2i(floori(d[side * 2] / 10.0), floori(d[side * 2 + 1] / 10.0))
		var steps: int = maxi(absi(pendant.x - from.x), absi(pendant.y - from.y)) * 2
		var last: Vector2i = Vector2i(99999, 99999)
		var index: int = 0
		for i: int in steps + 1:
			var at: Vector2 = Vector2(from).lerp(Vector2(pendant), float(i) / maxf(steps, 1.0))
			var cell: Vector2i = Vector2i(floori(at.x + 0.5), floori(at.y + 0.5))
			if cell == last:
				continue
			last = cell
			_px(canvas, origin, scale, cell, ramp[1] if index % 2 == 0 else ramp[0]) ## a fine chain: mid and dark, not the bright metal
			index += 1
	var shape: Array = look.get("pendant", []) as Array
	if shape.is_empty():
		return
	var stone: Color = Color(String(look.get("stone", "ffffff")))
	_shape(canvas, glow, shape, pendant, d[10] >= TORSO_FRONT, ramp, stone, look, origin, scale, time, night, 0.0, dull)


static func _earrings(canvas: CanvasItem, glow: CanvasItem, look: Dictionary, d: PackedInt32Array, origin: Vector2, scale: float, time: float, night: float) -> void:
	if d[11] < HEAD_HIDDEN:
		return
	var ramp: Array[Color] = metal(look)
	var stone: Color = Color(String(look.get("stone", "ffffff")))
	var shape: Array = look.get("drop", []) as Array
	for side: int in 2:
		if d[12 + side] < SIDE_HIDDEN:
			continue
		var lobe: Vector2i = Vector2i(floori(d[6 + side * 2] / 10.0), floori(d[7 + side * 2] / 10.0))
		_px(canvas, origin, scale, lobe, ramp[1]) ## the hook
		if shape.is_empty():
			continue
		var sway: int = roundi(sin(time * 2.1 + side * 2.0) * 0.55) ## now and then a pixel to the side
		_shape(canvas, glow, shape, lobe + Vector2i(sway, 1), true, ramp, stone, look, origin, scale, time, night, side * 1.7)


## A shape of letters hung with its top middle at `at`. `front`: seen from the front, otherwise edge-on (only the middle column).
static func _shape(canvas: CanvasItem, glow: CanvasItem, rows: Array, at: Vector2i, front: bool, ramp: Array[Color], stone: Color, look: Dictionary, origin: Vector2, scale: float, time: float, night: float, phase: float, dull: bool = false) -> void:
	var width: int = String(rows[0]).length()
	if dull:
		stone = stone.lerp(Color(0.34, 0.31, 0.42), 0.8) ## spent: the crack has gone cold
	var pulse: float = VoidGlow.pulse(time, phase) if bool(look.get("pulse", false)) and not dull else 1.0
	var shine: float = (0.2 + 0.8 * night) * pulse ## `night` carries a flash (a swallowed blow) as a value above 1
	for y: int in rows.size():
		var line: String = String(rows[y])
		for x: int in width:
			if not front and x != width / 2:
				continue ## edge-on: only the middle column
			var letter: String = line[x]
			var color: Color = letter_color(letter, ramp, stone)
			if color.a == 0.0:
				continue
			var cell: Vector2i = at + Vector2i((x - width / 2) if front else 0, y)
			_px(canvas, origin, scale, cell, color)
			if glow != null and not dull and bool(look.get("glow", false)) and letter in "STW":
				_px(glow, origin, scale, cell, Color(color.lightened(0.25), clampf(shine, 0.0, 1.0)))


## The bracelet on the sword arm: a 2x2 band in the footprint of the arm at the cuff, the stone as its lightest pixel. Coordinates are
## the arm's own pixels, `wrist` the middle of the band.
static func draw_bracelet(canvas: CanvasItem, id: String, wrist: Vector2, _direction: Vector2, time: float) -> void:
	var look: Dictionary = look_of(id)
	if look.is_empty():
		return
	var ramp: Array[Color] = metal(look)
	var stone: Color = Color(String(look.get("stone", "ffffff")))
	## The band takes exactly the footprint of the arm's two-pixel line at the cuff (the arm is 2 px thick, so nothing overhangs): metal with a light top
	## left, the stone as the lightest pixel on the side that faces the camera.
	var cell: Vector2 = wrist.round() - Vector2(1.0, 1.0)
	canvas.draw_rect(Rect2(cell, Vector2(2.0, 2.0)), ramp[1])
	canvas.draw_rect(Rect2(cell + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), ramp[2])
	canvas.draw_rect(Rect2(cell + Vector2(1.0, 1.0), Vector2(1.0, 1.0)), ramp[0])
	if int(look.get("stones", 0)) > 0:
		var shown: Color = Color.WHITE if bool(look.get("glint", false)) and fposmod(time, 3.4) < 0.18 else stone.lightened(0.3)
		canvas.draw_rect(Rect2(cell, Vector2(1.0, 1.0)), shown)
		canvas.draw_rect(Rect2(cell + Vector2(0.0, 1.0), Vector2(1.0, 1.0)), stone)


static func _px(canvas: CanvasItem, origin: Vector2, scale: float, cell: Vector2i, color: Color) -> void:
	if canvas == null:
		return
	canvas.draw_rect(Rect2(origin + Vector2(cell) * scale, Vector2(scale, scale)), color)
