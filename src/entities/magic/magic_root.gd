class_name MagicRoot
extends Node2D
## One wild root of a Wurzelgrund (docs/magie_konzept.md): it stands on its own feet (the node sits where it breaks out of the earth), so it sorts
## with everybody in the world. Drawn in whole pixels like the trees' wood: violet-plum bark (ink outline, lit left edge, dark right edge), a
## knotted foot with clods and two rootlets, a curling body that tapers to a tip, leaves that unfold, thorns from tier III, a blossom for the
## BLÜTENSCHLUSS. A child draws its light (unlit, additive): witch-green veins with pulses running up, a glowing bud at the tip.
## It breaks out with an overshoot, sways, lashes at shadow creatures (DORNEN) and withers, sinks and greys at the end.

const INK: Color = Color("1b1a2e")
const BARK: Array[Color] = [Color("3a2442"), Color("5c3d5c"), Color("85607a"), Color("aa8396")] ## dark .. lit (the trees' wood)
const DEAD: Color = Color("4a3b36")
const SOIL: Array[Color] = [Color("2a1b26"), Color("3d2a2c"), Color("5a3d33")]
const LEAF_DARK: Color = Color("3f7a2a")
const LEAF_LIT: Color = Color("8fd65a")
const LEAF_DRY: Color = Color("7a5a34")
const THORN: Color = Color("d8c8b8")
const VEIN: Color = Color("a8ff6a") ## the Hexenwald's witch green
const BUD: Color = Color("eaffc8")
const PETAL: Array[Color] = [Color("f6e6ff"), Color("ffc8ea")]
const HEART: Color = Color("ffe08a")
const GROW_TIME: float = 0.45

var lean: Vector2 = Vector2.ZERO ## which way it bends as it rises (px per px of height, x mostly)
var height: float = 16.0
var thick: float = 3.0
var curl: float = 0.0 ## -1..1: how it winds
var phase: float = 0.0
var delay: float = 0.1 ## s after the earth tore open before it breaks out
var thorny: bool = false
var leaves: int = 2
var salt: int = 0
var life: float = 0.0 ## s since the earth tore open (set by the zone)
var wither: float = 0.0 ## 0..1 the end (set by the zone)
var _lash: Vector2 = Vector2.ZERO
var _lash_t: float = 1.0 ## 0..1 a lash in progress (1 = none)
var _bloom: float = 0.0
var _blooming: bool = false
var _light: Node2D
var _spine: PackedVector2Array = PackedVector2Array()
var _widths: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_light = Node2D.new()
	_light.material = SpellZone.add_material() ## drawn right after its root (no own z): a root behind her keeps its light behind her too
	_light.draw.connect(_draw_light)
	add_child(_light)


## Lashes towards `toward` (px from its foot) for a moment.
func lash(toward: Vector2) -> void:
	if _lash_t < 1.0:
		return
	_lash = toward.normalized() * minf(toward.length(), 14.0)
	_lash_t = 0.0


func blossom() -> void:
	_blooming = true


func growth() -> float:
	var t: float = clampf((life - delay) / GROW_TIME, 0.0, 1.0)
	var g: float = 1.0 + 2.7 * pow(t - 1.0, 3.0) + 1.7 * pow(t - 1.0, 2.0) ## breaks out with an overshoot
	var sink: float = clampf(wither * 1.25, 0.0, 1.0)
	return maxf(g * (1.0 - sink * sink * (3.0 - 2.0 * sink)), 0.0)


func _process(delta: float) -> void:
	if _lash_t < 1.0:
		_lash_t = minf(_lash_t + delta / 0.35, 1.0)
	if _blooming:
		_bloom = minf(_bloom + delta / 0.3, 1.0)
	_build_spine()
	queue_redraw()
	_light.queue_redraw()


func _build_spine() -> void:
	_spine.clear()
	_widths.clear()
	var g: float = growth()
	var tall: float = height * g
	if tall < 1.0:
		return
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var whip: float = sin(_lash_t * PI) if _lash_t < 1.0 else 0.0
	var steps: int = maxi(int(tall), 2)
	for i: int in steps + 1:
		var u: float = float(i) / float(steps)
		var x: float = lean.x * pow(u, 1.3) * height + curl * sin(u * PI * 1.8 + phase * 0.3) * 3.2 * u + curl * 1.6 * sin(u * PI * 3.4 + phase) * u * u ## it winds, and winds again near the tip
		x += sin(t * 1.6 + phase) * 1.1 * u * u * (1.0 - wither) ## a slow sway, more towards the tip
		x += _lash.x * whip * u * u
		var y: float = -u * tall + _lash.y * whip * u * u * 0.4
		_spine.append(Vector2(x, y))
		_widths.append(lerpf(thick + 1.0, 1.0, pow(u, 0.75)) * (1.0 - 0.3 * wither))


func _bark(i: int) -> Color:
	return BARK[i].lerp(DEAD, wither * 0.8)


func _draw() -> void:
	if _spine.size() < 2:
		return
	var g: float = growth()
	# the foot: clods of torn earth and two rootlets running off along the ground
	for k: int in 5:
		var off: int = (salt >> (k * 3)) % 5 - 2
		draw_rect(Rect2(Vector2(off * 1.5 - 1.0, -1.0 + (k % 2)), Vector2(2, 1)), SOIL[k % 3])
	for side: int in [-1, 1]:
		var reach: int = roundi((3.0 + float((salt >> (side + 4)) % 3)) * minf(g, 1.0))
		for x: int in reach:
			draw_rect(Rect2(Vector2(side * (thick * 0.5 + 1.0 + x), -float(x % 2)), Vector2.ONE), _bark(1 if x < reach - 1 else 0))
	# the outline first, then the bark over it
	for i: int in _spine.size():
		var p: Vector2 = _spine[i].round()
		var w: int = maxi(roundi(_widths[i]), 1)
		draw_rect(Rect2(p.x - floorf(w / 2.0) - 1.0, p.y - 1.0, w + 2, 3), INK)
	for i: int in _spine.size():
		var p: Vector2 = _spine[i].round()
		var w: int = maxi(roundi(_widths[i]), 1)
		var left: float = p.x - floorf(w / 2.0)
		draw_rect(Rect2(left, p.y, w, 1), _bark(1))
		if w >= 3:
			draw_rect(Rect2(left + w - 1, p.y, 1, 1), _bark(0)) ## the shaded right edge
		draw_rect(Rect2(left, p.y, 1, 1), _bark(2 if w >= 2 else 1)) ## the lit left edge
		if w >= 3 and (i + salt) % 5 == 0:
			draw_rect(Rect2(left + 1, p.y, 1, 1), _bark(3)) ## a gleam on a knot
		if w >= 2 and (i + salt) % 7 == 3:
			draw_rect(Rect2(left + 1, p.y, 1, 1), _bark(0)) ## a groove in the bark
		if thorny and i > 2 and i < _spine.size() - 2 and (i + salt) % 4 == 0: ## DORNEN: little thorns out to the sides
			var side: float = -1.0 if (i / 4 + salt) % 2 == 0 else 1.0
			var out: float = left - 1.0 if side < 0.0 else left + w
			draw_rect(Rect2(out, p.y, 1, 1), _bark(0))
			draw_rect(Rect2(out + side, p.y - 1.0, 1, 1), THORN.lerp(DEAD, wither))
	# leaves unfold along the upper half
	var open: float = clampf((life - delay - GROW_TIME * 0.7) / 0.5, 0.0, 1.0)
	for k: int in leaves:
		var at: int = clampi(roundi((0.5 + 0.17 * k) * float(_spine.size() - 1)), 1, _spine.size() - 1)
		var stem: Vector2 = _spine[at].round()
		var side2: float = -1.0 if (k + salt) % 2 == 0 else 1.0
		var size: int = roundi(open * 3.0)
		var leaf_tone: Color = LEAF_LIT.lerp(LEAF_DRY, wither)
		var leaf_dark: Color = LEAF_DARK.lerp(LEAF_DRY.darkened(0.3), wither)
		for s: int in size:
			var cell: Vector2 = stem + Vector2(side2 * (2.0 + s), -float(s) * 0.5 - 1.0).round()
			draw_rect(Rect2(cell, Vector2.ONE), leaf_tone if s < size - 1 or s == 0 else leaf_dark)
			draw_rect(Rect2(cell + Vector2(0.0, 1.0), Vector2.ONE), leaf_dark)
	# BLÜTENSCHLUSS: a blossom opens at the tip
	if _bloom > 0.0:
		var tip: Vector2 = _spine[_spine.size() - 1].round() + Vector2(0.0, -1.0)
		var r: int = roundi(_bloom * 2.0)
		for d: Vector2 in [Vector2(-r, 0), Vector2(r, 0), Vector2(0, -r), Vector2(0, r)]:
			draw_rect(Rect2(tip + d, Vector2.ONE), PETAL[0])
		if r >= 2:
			for d: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				draw_rect(Rect2(tip + d, Vector2.ONE), PETAL[1])
		draw_rect(Rect2(tip, Vector2.ONE), HEART)


func _draw_light() -> void:
	if _spine.size() < 2:
		return
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var alive: float = 1.0 - wither
	for i: int in range(1, _spine.size()):
		var u: float = float(i) / float(_spine.size() - 1)
		var vein: bool = ((i + salt) / 3) % 3 != 1 ## the vein breaks off and starts again, like the Hexenwald's trees
		if not vein:
			continue
		var run: float = fposmod(u * 1.6 - t * 0.9 + float(salt % 7) * 0.13, 1.0) ## pulses climb the root
		var strength: float = (0.25 + 0.75 * smoothstep(0.75, 1.0, run)) * alive
		var p: Vector2 = _spine[i].round()
		var w: int = maxi(roundi(_widths[i]), 1)
		var x: float = p.x - floorf(w / 2.0) + (1.0 if w >= 3 else 0.0)
		_light.draw_rect(Rect2(x, p.y, 1, 1), Color(VEIN, strength * 0.8))
	var tip: Vector2 = _spine[_spine.size() - 1].round()
	var bud: float = (0.55 + 0.45 * sin(t * 3.0 + phase)) * alive
	_light.draw_rect(Rect2(tip + Vector2(0.0, -1.0), Vector2.ONE), Color(BUD, bud))
	_light.draw_rect(Rect2(tip + Vector2(-1.0, -1.0), Vector2(3, 1)), Color(VEIN, bud * 0.35))
	_light.draw_rect(Rect2(tip + Vector2(0.0, -2.0), Vector2(1, 3)), Color(VEIN, bud * 0.35))

