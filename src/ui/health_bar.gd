extends SapVine
## Player health as a crimson sap vine growing out to the left. A pale trail drains behind a drop;
## a hit shakes it and sprays sap, and it pulses red when low. Overheal (health above the maximum)
## grows out of its tip as a pale white branch that thickens with the overheal, shimmers while it
## lasts, flashes when topped up and withers in its last seconds before it drains away.

const LOW_RATIO: float = 0.25
const OVER_LEN: float = 34.0 ## px the white branch grows beyond the tip at the full overheal allowance
const OVER_WITHER: float = 10.0 ## seconds before the overheal drains in which the branch withers
const OVER_COLORS: Array[Color] = [Color("ffffff"), Color("e9e2ff"), Color("a99ad6")] ## highlight, main, shade
const OVER_LEAF: Color = Color("cfe8da")

var _health: HealthComponent
var _over: float = 0.0 ## 0..1 of the allowance
var _over_shown: float = 0.0
var _over_flash: float = 0.0
var _over_left: float = 0.0


func _init() -> void:
	dir = -1
	length = HEALTH_LEN
	base_thick = 3
	fork_at = 0.48
	drips = true
	palette = [Color("ff8fa3"), Color("e0455f"), Color("9c2a45")]
	trail_color = Color("f4d6dc")


## It ripples in its own rhythm and sinks gently towards the tip.
func _offset(t: float) -> float:
	return sin(t * TAU * 1.1 + 1.0) * 3.2 * minf(t * 3.0, 1.0) + 8.0 * t * t


func bind(health: HealthComponent) -> void:
	_health = health
	health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void: hit())
	health.healed.connect(func(_a: float) -> void: _over_flash = 1.0 if health.current > health.max_health else _over_flash)


func _update_state(delta: float) -> void:
	if _health == null:
		return
	ratio = clampf(_health.current / _health.max_health, 0.0, 1.0)
	var allowance: float = _health.max_health * _health.overheal_ratio
	_over = clampf((_health.current - _health.max_health) / allowance, 0.0, 1.0) if allowance > 0.0 else 0.0
	_over_shown = lerpf(_over_shown, _over, 1.0 - exp(-5.0 * delta))
	_over_flash = maxf(_over_flash - 2.2 * delta, 0.0)
	_over_left = _health.overheal_left
	label = str(ceili(_health.current - 0.001)) ## (float noise must not show 111)
	alert = Color("ff4d6d") if ratio < LOW_RATIO and ratio > 0.0 else Color(0, 0, 0, 0)


func _draw() -> void:
	super()
	if _over_shown < 0.02:
		return
	var reach: int = int(OVER_LEN * _over_shown)
	var wither: float = 1.0 - smoothstep(0.0, OVER_WITHER, _over_left) if _over > 0.0 else 0.0
	var flicker: float = 0.65 + 0.35 * sin(_time * 14.0) if wither > 0.0 else 1.0
	for s: int in reach + 1:
		var t: float = float(s) / OVER_LEN
		var p: Vector2 = _point(length + s)
		var thick: int = 2 if t < 0.6 else 1
		var top: float = roundf(p.y) - (thick - 1) / 2
		var body: Color = OVER_COLORS[1].lerp(OVER_COLORS[2], 0.5 * t + 0.5 * wither)
		var phase: float = fposmod(_time * 22.0 - s, 14.0) ## light pulses ride outwards
		if phase < 3.0:
			body = body.lerp(OVER_COLORS[0], (1.0 - phase / 3.0) * (1.0 - wither * 0.6))
		body = body.lerp(Color.WHITE, _over_flash * 0.7)
		draw_rect(Rect2(p.x, top - 1, 1, thick + 2), VineStyle.OUTLINE)
		draw_rect(Rect2(p.x, top, 1, thick), body * Color(1, 1, 1, flicker))
		draw_rect(Rect2(p.x, top, 1, 1), OVER_COLORS[0].lerp(OVER_COLORS[2], wither))
	for k: int in 3: ## pale leaves along the branch
		var s: float = 6.0 + k * 9.0
		if s >= reach - 2:
			break
		var up: int = -1 if k % 2 == 0 else 1
		VineStyle.leaf(self, _point(length + s) + Vector2(0, up * 2), dir, up, 3, OVER_LEAF.lerp(OVER_COLORS[2], wither), OVER_COLORS[0])
	var tip: Vector2 = _point(length + reach)
	VineStyle.glow(self, tip, 8.0, OVER_COLORS[0], (0.55 + 0.35 * sin(_time * 3.0) + _over_flash) * (1.0 - wither * 0.7))
	var open: int = 1 + int(1.0 + sin(_time * 3.0))
	for offset: Vector2 in [Vector2(-open, 0), Vector2(open, 0), Vector2(0, -open), Vector2(0, open)]:
		draw_rect(Rect2(roundf(tip.x + offset.x), roundf(tip.y + offset.y), 1, 1), OVER_COLORS[0])
	draw_rect(Rect2(roundf(tip.x), roundf(tip.y), 1, 1), VineStyle.PETAL)
	for i: int in 4: ## white spores drift up from the bud
		var rise: float = fposmod(_time * 0.7 + i * 0.25, 1.0)
		draw_rect(Rect2(roundf(tip.x + sin(_time * 1.3 + i * 2.1) * 4.0), roundf(tip.y - rise * 12.0), 1, 1), Color(OVER_COLORS[0], (1.0 - rise) * (1.0 - wither * 0.6)))
