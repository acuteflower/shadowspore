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
static func flame(canvas: CanvasItem, base: Vector2, w: float, h: float, t: float, salt: float, strength: float) -> void:
	if h < 2.0 or strength <= 0.01:
		return
	var rows: int = int(h)
	var step_t: float = floorf(t * 13.0)
	for r: int in rows:
		var k: float = float(r) / float(rows)
		var wob: float = _n(salt * 13.0 + float(r) * 0.7 + step_t)
		if k > 0.68 and wob < 0.3: ## the licks at the top break up
			continue
		var half: float = w * 0.5 * (1.0 - pow(k, 1.6)) * (0.55 + 0.45 * smoothstep(0.0, 0.25, k)) * (0.65 + 0.7 * wob)
		var width: int = maxi(1, roundi(half * 2.0))
		var sway: float = sin(t * 8.0 + salt * 3.0 + k * 3.5) * k * w * 0.45
		var x: float = roundf(base.x + sway - float(width) * 0.5)
		var y: float = roundf(base.y) - float(r)
		var color: Color = VIOLET.lerp(MAGENTA, k / 0.3) if k < 0.3 else MAGENTA.lerp(PALE, (k - 0.3) / 0.7)
		var a: float = strength * (1.0 - k * 0.55)
		canvas.draw_rect(Rect2(x, y, float(width), 1.0), Color(color, a))
		if width >= 3 and k < 0.7:
			canvas.draw_rect(Rect2(x + 1.0, y, float(width - 2), 1.0), Color(color.lerp(WHITE_HOT, 0.55), a * 0.8))
	for e: int in 2: ## sparks rise out of it
		var phase: float = fposmod(t * 0.9 + salt * 0.37 + float(e) * 0.5, 1.0)
		var ex: float = base.x + sin(salt + float(e) * 3.0 + phase * 6.0) * w * 0.6
		var ey: float = base.y - phase * h * 1.8
		canvas.draw_rect(Rect2(roundf(ex), roundf(ey), 1.0, 1.0), Color(PALE, strength * (1.0 - phase)))
