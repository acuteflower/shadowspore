class_name BloomOrb
extends RefCounted
## The flower that marks a node on the vines (the Fortschritt road and the skill graph): sepals, two rings of overlapping petals with ink edges, light from the upper left,
## veins, bright tips, a dark heart with a glowing pistil and a ring of stamens. `open` 0 is a tight bud (veiled / unexplored), 1 a full bloom (collected / awake),
## in between it unfolds: holding on a node drives `open` up, so the flower opens while the reward is gathered. Every colour comes from the node's tone.
const INK: Color = Color("08050f")
const LIGHT_DIR: Vector2 = Vector2(-0.62, -0.78)
static var _petal: PackedVector2Array = PackedVector2Array()


## A rounded teardrop along +x (length 1, half width 0.5).
static func _template() -> PackedVector2Array:
	if _petal.is_empty():
		_petal = PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(0.1, -0.22), Vector2(0.3, -0.45), Vector2(0.56, -0.5), Vector2(0.8, -0.34), Vector2(0.95, -0.12), Vector2(1.0, 0.0),
			Vector2(0.95, 0.12), Vector2(0.8, 0.34), Vector2(0.56, 0.5), Vector2(0.3, 0.45), Vector2(0.1, 0.22),
		])
	return _petal


static func _petal_at(canvas: CanvasItem, at: Vector2, angle: float, length: float, width: float, fill: Color, edge: Color, vein: Color, tip: Color) -> void:
	var dir: Vector2 = Vector2.from_angle(angle)
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var template: PackedVector2Array = _template()
	canvas.draw_colored_polygon(Transform2D(dir * (length + 1.8), side * (width + 1.4), at - dir * 0.6) * template, edge)
	canvas.draw_colored_polygon(Transform2D(dir * length, side * width, at) * template, fill)
	if vein.a > 0.02:
		canvas.draw_line((at + dir * length * 0.22).round(), (at + dir * length * 0.76).round(), vein, 1.0)
	if tip.a > 0.02:
		canvas.draw_rect(Rect2((at + dir * length * 0.9).round(), Vector2.ONE), tip)


## The colour of a petal pointing along `dir`: lit on the upper left, shaded on the lower right.
static func _shade(base: Color, dir: Vector2, rim: float) -> Color:
	var lit: float = dir.dot(LIGHT_DIR)
	var out: Color = base.lightened(clampf(lit, 0.0, 1.0) * 0.26 + rim * 0.1) if lit > 0.0 else base.darkened(clampf(-lit, 0.0, 1.0) * 0.24)
	return out


## `radius` is the flower's reach (petal tips); `life` 0..1 dims an unlit flower; `breath` 0..1 pulses it; `seed_value` makes each flower its own (turn, petal count variety).
static func draw(canvas: CanvasItem, at: Vector2, radius: float, tone: Color, alpha: float, open: float, life: float, breath: float, time: float, seed_value: int, rim: float = 0.0, petals: int = 8) -> void:
	if alpha <= 0.01 or radius < 3.0:
		return
	at = at.round()
	var o: float = clampf(open, 0.0, 1.0)
	var phase: float = VineStyle.rand(seed_value * 3 + 1) * TAU
	var turn: float = phase + sin(time * 0.45 + phase) * 0.07 ## the whole flower sways a little
	var dim: float = (1.0 - clampf(life, 0.0, 1.0)) * 0.55
	var base: Color = tone.darkened(dim * 0.6)
	var edge: Color = Color(INK.lerp(tone.darkened(0.88), 0.4), alpha)
	var vein: Color = Color(tone.lightened(0.3), alpha * (0.2 + 0.35 * o) * life)
	var tip: Color = Color(VineStyle.PETAL, alpha * o * life * (0.55 + breath * 0.35))
	var reach: float = radius * (1.0 + breath * 0.025 * o)
	canvas.draw_circle(at + Vector2(0, 2), reach * 0.86, Color(INK, alpha * 0.5))
	# sepals: a green star under the bud that the petals leave bare when the flower opens
	var sepal_tone: Color = VineStyle.LEAF.lerp(tone.darkened(0.55), 0.3 + dim * 0.4)
	for k: int in 5:
		var angle: float = turn * 0.6 + float(k) * TAU / 5.0 + 0.3
		var dir: Vector2 = Vector2.from_angle(angle)
		_petal_at(canvas, at, angle, reach * lerpf(0.78, 0.7, o), reach * 0.17, Color(_shade(sepal_tone, dir, 0.0), alpha), edge, Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	var count: int = maxi(petals, 5)
	# back ring: wide and dark, the petals' undersides
	for k: int in count:
		var angle: float = turn + float(k) * TAU / count + sin(time * 1.3 + float(k) * 1.7 + phase) * 0.03 * o
		var dir: Vector2 = Vector2.from_angle(angle)
		var length: float = reach * lerpf(0.56, 1.0, o)
		var width: float = reach * lerpf(0.52, 0.37, o) * (8.0 / float(count)) ** 0.5
		_petal_at(canvas, at, angle, length, width, Color(_shade(base.darkened(0.36), dir, rim), alpha), edge, vein.darkened(0.3), Color(0, 0, 0, 0))
	# front ring: brighter, between the back petals
	for k: int in count:
		var angle: float = turn + (float(k) + 0.5) * TAU / count + sin(time * 1.1 + float(k) * 2.1 + phase) * 0.04 * o
		var dir: Vector2 = Vector2.from_angle(angle)
		var length: float = reach * lerpf(0.5, 0.8, o)
		var width: float = reach * lerpf(0.52, 0.35, o) * (8.0 / float(count)) ** 0.5
		_petal_at(canvas, at, angle, length, width, Color(_shade(base.lightened(0.06), dir, rim), alpha), edge, vein, tip)
	if count >= 10: ## milestones carry a third, small and bright ring (a crown)
		for k: int in count / 2:
			var angle: float = turn * 1.3 + (float(k) + 0.25) * TAU / (count / 2)
			var dir: Vector2 = Vector2.from_angle(angle)
			_petal_at(canvas, at, angle, reach * lerpf(0.34, 0.52, o), reach * 0.2, Color(_shade(base.lightened(0.16), dir, rim), alpha), edge, vein, tip)
	# the heart: a dark bowl with a glowing pistil and a ring of stamens
	var heart: float = reach * lerpf(0.26, 0.42, o)
	canvas.draw_circle(at, heart + 1.0, Color(INK, alpha))
	canvas.draw_circle(at, heart, Color(tone.darkened(0.9), alpha))
	canvas.draw_circle(at + Vector2(-1, -1), heart * 0.72, Color(tone.darkened(0.78), alpha * (0.5 + breath * 0.15)))
	var pistil: Vector2 = at + Vector2(sin(time * 0.9 + phase), cos(time * 0.7 + phase)).round() * (0.5 + o * 0.5)
	canvas.draw_circle(pistil, maxf(heart * 0.3, 1.0), Color(tone, alpha * life * (0.38 + breath * 0.22 + rim * 0.2)))
	if o > 0.4:
		var stamen: float = clampf((o - 0.4) / 0.4, 0.0, 1.0)
		for j: int in 8:
			var dir: Vector2 = Vector2.from_angle(turn * 2.0 + float(j) * TAU / 8.0)
			var spot: Vector2 = (at + dir * heart * 0.86).round()
			canvas.draw_rect(Rect2(spot, Vector2.ONE), Color(VineStyle.WARM_GLOW, alpha * stamen * life * 0.8))
			if j % 2 == 0:
				canvas.draw_rect(Rect2(spot + (dir * 1.0).round(), Vector2.ONE), Color(VineStyle.PETAL, alpha * stamen * life * 0.7))
