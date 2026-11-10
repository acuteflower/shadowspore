class_name PixelFlames
extends Node2D
## Pink-violet fire in whole pixels, the fire of Mornath's last phase (docs/boss_sky_cleaver.md): tongues of flame that flicker, sway and lose sparks, in
## violet at the foot, magenta in the body and pale pink at the licks. Two uses:
##  - `PixelFlames.flame(canvas, base, ...)`: one tongue drawn onto any additive canvas (the rig burns on its wings and back with it);
##  - a node: a set of flame spots on the ground or a pillar (`build`), each of which burns for a while, goes out and burns again on its own beat, so the light
##    only burns "partly" and never all at once. `amount` (0..1) is how much of it is alight; it draws nothing at 0 and only while a local player is near.
## Cosmetic and local, every peer draws its own; unshaded and additive.

const VIOLET: Color = Color("a23cff")
const MAGENTA: Color = Color("ff4fd8")
const PALE: Color = Color("ffb8ec")
const WHITE_HOT: Color = Color("fff0fb")
const TICK: float = 1.0 / 18.0 ## the node redraws at this rate: a flickering fire needs no more
const NEAR: float = 560.0

var amount: float = 0.0
var _flames: Array[Dictionary] = []
var _t: float = 0.0
var _acc: float = 0.0
var _near: bool = false
var _near_check: float = 0.0
var _centre: Vector2 = Vector2.ZERO


func _init() -> void:
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add
	visible = false


## `points` are local positions of the feet of the flames. `width` / `height` are the biggest a flame gets (each one scales between 0.6 and 1).
func build(points: PackedVector2Array, width: float, height: float, seed_value: int) -> void:
	_flames.clear()
	_centre = Vector2.ZERO
	for i: int in points.size():
		var salt: float = float(hash(Vector2i(i, seed_value)) % 1000) / 10.0
		var size: float = 0.6 + 0.4 * _n(salt * 0.31)
		_flames.append({
			"pos": points[i],
			"w": width * size,
			"h": height * size,
			"salt": salt,
			"period": 3.5 + 5.0 * _n(salt * 0.77),
			"phase": _n(salt * 1.3),
			"duty": 0.45 + 0.25 * _n(salt * 2.1),
		})
		_centre += points[i]
	if not points.is_empty():
		_centre /= float(points.size())


func flame_count() -> int:
	return _flames.size()


func _process(delta: float) -> void:
	if amount <= 0.001 or _flames.is_empty():
		visible = false
		return
	_t += delta
	_near_check -= delta
	if _near_check <= 0.0:
		_near_check = 0.5
		_near = false
		var at: Vector2 = to_global(_centre)
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.global_position.distance_to(at) < NEAR:
				_near = true
				break
	visible = _near
	if not _near:
		return
	_acc += delta
	if _acc >= TICK:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	if amount <= 0.001:
		return
	for f: Dictionary in _flames:
		var c: float = fposmod(_t / float(f["period"]) + float(f["phase"]), 1.0)
		var duty: float = float(f["duty"])
		if c >= duty:
			continue
		var k: float = smoothstep(0.0, 0.12, c) * (1.0 - smoothstep(duty - 0.18, duty, c)) ## it catches, burns, dies down
		if k <= 0.03:
			continue
		var pos: Vector2 = f["pos"] as Vector2
		var fw: float = float(f["w"]) * (0.7 + 0.3 * k)
		var fh: float = float(f["h"]) * k
		var salt: float = float(f["salt"])
		flame(self, pos + Vector2(-fw * 0.45, 1.0), fw * 0.6, fh * 0.6, _t, salt + 3.7, amount * k * 0.8) ## a cluster: the main tongue and two smaller beside it
		flame(self, pos + Vector2(fw * 0.45, 1.0), fw * 0.6, fh * 0.52, _t, salt + 8.1, amount * k * 0.8)
		flame(self, pos, fw, fh, _t, salt, amount * k)


static func _n(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 4.1414) * 43758.5453, 1.0)


## One tongue of flame standing on `base`: `w` wide at the foot, `h` high, `t` the clock, `salt` makes every flame its own, `strength` 0..1.
## Optimized: Draws flame tongue as a connected polygon with vertex gradient (violet -> magenta -> pale)
## and an inner white-hot core, replacing 20-35 individual draw_rect calls with 1-2 polygon calls.
static func flame(canvas: CanvasItem, base: Vector2, w: float, h: float, t: float, salt: float, strength: float) -> void:
	if h < 2.0 or strength <= 0.01:
		return

	var step_t: float = floorf(t * 13.0)
	var wob0: float = _n(salt * 13.0 + step_t)
	var wob1: float = _n(salt * 13.0 + 5.0 + step_t)
	var wob2: float = _n(salt * 13.0 + 12.0 + step_t)

	# Key heights along the flame: base (0.0), belly (0.28), mid (0.65), tip (1.0)
	var sway1: float = sin(t * 8.0 + salt * 3.0 + 0.28 * 3.5) * 0.28 * w * 0.45
	var sway2: float = sin(t * 8.0 + salt * 3.0 + 0.65 * 3.5) * 0.65 * w * 0.45
	var sway3: float = sin(t * 8.0 + salt * 3.0 + 3.5) * w * 0.45

	var half0: float = maxf(1.0, roundf(w * 0.28 * (0.8 + 0.4 * wob0)))
	var half1: float = maxf(1.5, roundf(w * 0.42 * (0.8 + 0.4 * wob1)))
	var half2: float = maxf(1.0, roundf(w * 0.22 * (0.8 + 0.4 * wob2)))

	var y0: float = roundf(base.y)
	var y1: float = roundf(base.y - h * 0.28)
	var y2: float = roundf(base.y - h * 0.65)
	var y3: float = roundf(base.y - h)

	var bx: float = base.x
	# Construct 7 vertices: Base-L, Belly-L, Mid-L, Tip, Mid-R, Belly-R, Base-R
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(roundf(bx - half0), y0),
		Vector2(roundf(bx + sway1 - half1), y1),
		Vector2(roundf(bx + sway2 - half2), y2),
		Vector2(roundf(bx + sway3), y3),
		Vector2(roundf(bx + sway2 + half2), y2),
		Vector2(roundf(bx + sway1 + half1), y1),
		Vector2(roundf(bx + half0), y0),
	])

	var col_base: Color = Color(VIOLET, strength)
	var col_belly: Color = Color(MAGENTA, strength * 0.85)
	var col_mid: Color = Color(MAGENTA.lerp(PALE, 0.4), strength * 0.65)
	var col_tip: Color = Color(PALE, strength * 0.45)

	var cols: PackedColorArray = PackedColorArray([
		col_base,
		col_belly,
		col_mid,
		col_tip,
		col_mid,
		col_belly,
		col_base,
	])

	canvas.draw_polygon(pts, cols)

	# White-hot inner core in lower body for larger flames
	if w >= 3.0 and h >= 5.0 and half1 >= 2.0:
		var in_half0: float = maxf(0.5, half0 * 0.5)
		var in_half1: float = maxf(0.5, half1 * 0.5)
		var in_pts: PackedVector2Array = PackedVector2Array([
			Vector2(roundf(bx - in_half0), y0),
			Vector2(roundf(bx + sway1 - in_half1), y1),
			Vector2(roundf(bx + sway1 + in_half1), y1),
			Vector2(roundf(bx + in_half0), y0),
		])
		canvas.draw_colored_polygon(in_pts, Color(WHITE_HOT, strength * 0.7))

	# 2 rising sparks
	for e: int in 2:
		var phase: float = fposmod(t * 0.9 + salt * 0.37 + float(e) * 0.5, 1.0)
		var ex: float = base.x + sin(salt + float(e) * 3.0 + phase * 6.0) * w * 0.6
		var ey: float = base.y - phase * h * 1.8
		canvas.draw_rect(Rect2(roundf(ex), roundf(ey), 1.0, 1.0), Color(PALE, strength * (1.0 - phase)))
