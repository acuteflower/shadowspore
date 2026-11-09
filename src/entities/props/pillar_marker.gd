class_name PillarMarker
extends Node2D
## The call to action on an armed arena pillar (docs/boss_sky_cleaver.md): while Mornath rests on a pillar or splits the sky from it, weapons must break that pillar.
## Three pieces in the vine language, all unlit and purely local (every peer draws its own, the pillar's state is already replicated):
##  - a dashed ring on the floor round the pillar's foot (where the blow lands) with ripples that run inwards, gold, white when a blow lands;
##  - three chevrons that pour down the shaft towards the foot;
##  - a leaf of bark paper ("SÄULE ZERSCHLAGEN") hung on a twig from the side of the shaft, on the side facing the arena's middle (high over the capital it would be cut
##    off by the screen's edge and the boss bar), with a crack of light under the words whose length is what is left of the pillar (it runs out with every blow). In the judgement the leaf turns magenta and stutters with the meter (`urgency`, set by the fight).
## It appears with `ArenaPillar.set_armed(true)` and goes with the pillar's burst or `set_armed(false)`. Only drawn while a living local player is near.

const PAPER: Color = Color("120d22")
const PAPER_VOID: Color = Color("07030f")
const GOLD: Color = Color("ffd98a")
const MAGENTA: Color = Color("ff4fd8")
const VEIN_LIGHT: Color = Color("a98af0")
const CORE_HOT: Color = Color("fff7ff")
const TEXT: String = "SÄULE ZERSCHLAGEN"
const HEIGHT: int = 21
const TWIG: int = 8 ## the twig from the shaft to the leaf
const SHAFT_HALF: float = 12.0 ## where the twig leaves the pillar
const LEAF_Y: float = -66.0 ## the leaf's middle above the foot (the shaft: the boss sits higher up)
const RISE_SECONDS: float = 0.35
const NEAR_RANGE: float = 700.0
const RING_RX: float = 23.0 ## the ring on the floor, squashed like every ground circle of the arena
const RING_RY: float = 15.0
const CHEVRON_Y: float = -46.0

var urgency: float = 0.0 ## 0 .. 1: the judgement's clock running out (the leaf turns magenta and stutters)
var _pillar: ArenaPillar
var _ground: Node2D ## the ring, under everything that stands on the floor
var _alpha: float = 0.0
var _age: float = 0.0
var _time: float = 0.0
var _flash: float = 0.0
var _near: bool = false
var _near_check: float = 0.0
var _side: float = 1.0 ## the leaf hangs on this side of the shaft (towards the arena's middle)


func setup(pillar: ArenaPillar) -> void:
	_pillar = pillar
	z_index = 40
	material = Unlit.material()
	_ground = Node2D.new()
	_ground.name = "MarkerRing"
	_ground.z_index = -1
	_ground.material = Unlit.material()
	_ground.draw.connect(_draw_ground)
	pillar.add_child(_ground)
	pillar.worn.connect(_on_worn)
	_side = _side_towards_arena()
	visible = false
	_ground.visible = false


## The side of the shaft that faces the middle of the arena's pillars (the leaf has the most room there). Pillars are set up one after the other: asked again when shown.
func _side_towards_arena() -> float:
	if not _pillar.is_inside_tree():
		return _side
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for node: Node in _pillar.get_tree().get_nodes_in_group("arena_pillars"):
		var other: ArenaPillar = node as ArenaPillar
		if other != null and other.arena == _pillar.arena:
			sum += other.global_position
			count += 1
	if count < 2:
		return _side
	var dx: float = sum.x / float(count) - _pillar.global_position.x
	return 1.0 if dx >= 0.0 else -1.0


func _on_worn(_left: float, _maximum: float) -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if _pillar == null:
		return
	_time += delta
	_near_check -= delta
	if _near_check <= 0.0:
		_near_check = 0.3
		_near = _local_player_near()
	var want: bool = _pillar.is_armed() and _near
	if want and _alpha <= 0.0:
		_age = 0.0
		_side = _side_towards_arena()
	_alpha = move_toward(_alpha, 1.0 if want else 0.0, delta * (3.0 if want else 5.0))
	_flash = maxf(_flash - delta * 4.0, 0.0)
	var shown: bool = _alpha > 0.0
	visible = shown
	_ground.visible = shown
	if shown:
		_age += delta
		queue_redraw()
		_ground.queue_redraw()


func _local_player_near() -> bool:
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(_pillar.global_position) < NEAR_RANGE:
			return true
	return false


func _accent() -> Color:
	return GOLD.lerp(MAGENTA, urgency).lerp(CORE_HOT, _flash * 0.6)


# --- the ring on the floor -----------------------------------------------------------------------------------------


func _draw_ground() -> void:
	if _alpha <= 0.0:
		return
	var accent: Color = _accent()
	var pulse: float = 0.6 + 0.4 * sin(_time * 4.0)
	var steps: int = 140
	var shift: int = int(_time * 14.0)
	for s: int in steps:
		if (s + shift) % 10 >= 6: ## marching dashes
			continue
		var angle: float = TAU * float(s) / float(steps)
		var p: Vector2 = Vector2(roundf(cos(angle) * RING_RX), roundf(sin(angle) * RING_RY - 2.0))
		_ground.draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(VineStyle.OUTLINE, 0.6 * _alpha))
		_ground.draw_rect(Rect2(p, Vector2.ONE), Color(accent, _alpha * (0.6 + 0.4 * pulse)))
	for r: int in 2: ## ripples run in towards the foot: strike here
		var k: float = 1.0 - fposmod(_time * 1.1 + float(r) * 0.5, 1.0)
		var count: int = 72
		for s2: int in count:
			if s2 % 3 != 0:
				continue
			var angle2: float = TAU * float(s2) / float(count)
			var q: Vector2 = Vector2(roundf(cos(angle2) * RING_RX * k), roundf(sin(angle2) * RING_RY * k - 2.0))
			_ground.draw_rect(Rect2(q, Vector2.ONE), Color(accent, _alpha * k * 0.55))


# --- the chevrons and the leaf -------------------------------------------------------------------------------------


func _draw() -> void:
	if _alpha <= 0.0 or _pillar == null:
		return
	var void_level: float = VineStyle.void_amount()
	var accent: Color = _accent()
	_draw_chevrons(accent)
	var rise: float = 1.0 - pow(1.0 - clampf(_age / RISE_SECONDS, 0.0, 1.0), 3.0)
	var a: float = _alpha * rise
	var stutter: float = 1.0
	if urgency > 0.6:
		stutter = 1.0 if fmod(_time * (9.0 + 8.0 * urgency), 1.0) > 0.18 else 0.4
	var text_w: int = PixelText.width(TEXT)
	var width: int = text_w + 22
	var bob: float = roundf(sin(_time * 2.0))
	var slide: float = roundf((1.0 - rise) * 8.0) ## the leaf slides out of the shaft
	var left: int = int(roundf(SHAFT_HALF + float(TWIG) - slide)) if _side > 0.0 else int(roundf(-SHAFT_HALF - float(TWIG) + slide)) - width
	var top: int = int(LEAF_Y) - HEIGHT / 2 + int(bob)
	_draw_twig(top, left, width, a, void_level, accent)
	_draw_paper(left, top, width, a, void_level)
	VineStyle.bloom(self, Vector2(left + 7, top + 7), a, _time, void_level, accent)
	PixelText.draw(self, TEXT, Vector2i(left + 14, top + 3), Color(accent.lerp(UiStyle.TEXT, 0.35), a * stutter), Color(VineStyle.OUTLINE, a))
	_draw_crack(left + 8, top + 15, width - 16, a * stutter, accent)
	VineStyle.leaf(self, Vector2(left + width - 2, top + 2), 1, -1, 3, Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), a), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level), a))
	if void_level > 0.3:
		VineStyle.tendril(self, Vector2(left + 1, top + HEIGHT - 2), Vector2(-0.8, 0.6).normalized(), int(2 + 4 * void_level), _time, 7)


## Three small chevrons pour down the shaft towards the foot (a wave, brightest at the bottom).
func _draw_chevrons(accent: Color) -> void:
	var bob: float = roundf(sin(_time * 2.0))
	for i: int in 3:
		var wave: float = 0.25 + 0.75 * maxf(0.0, sin(_time * 5.0 - float(i) * 0.9))
		var y: float = CHEVRON_Y + float(i) * 5.0 + bob
		for dx: int in range(-3, 4):
			var dy: float = 3.0 - float(absi(dx))
			var p: Vector2 = Vector2(float(dx), y + dy)
			draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(VineStyle.OUTLINE, 0.7 * _alpha))
		for dx2: int in range(-3, 4):
			var dy2: float = 3.0 - float(absi(dx2))
			draw_rect(Rect2(Vector2(float(dx2), y + dy2), Vector2.ONE), Color(accent, _alpha * wave))


func _inset(x: int, bottom: bool, width: int) -> int:
	var edge: int = mini(x, width - 1 - x)
	return int(VineStyle.rand(x + (31 if bottom else 0) + TEXT.length()) * 1.7) + maxi(2 - edge, 0)


func _draw_paper(left: int, top: int, width: int, a: float, void_level: float) -> void:
	var fill: Color = PAPER.lerp(PAPER_VOID, void_level)
	var edge: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level).lerp(MAGENTA, urgency * 0.5)
	var last_top: int = 0
	var last_bottom: int = 0
	for x: int in width:
		var upper: int = _inset(x, false, width)
		var lower: int = HEIGHT - _inset(x, true, width)
		if lower <= upper:
			continue
		draw_rect(Rect2(left + x, top + upper, 1, lower - upper), Color(fill, 0.95 * a))
		draw_rect(Rect2(left + x, top + mini(upper, last_top) if x > 0 else top + upper, 1, (absi(upper - last_top) + 1) if x > 0 else 1), Color(edge, a))
		draw_rect(Rect2(left + x, top + upper + 1, 1, 1), Color(UiStyle.ACCENT, 0.55 * a)) ## a lit edge on top
		draw_rect(Rect2(left + x, top + (mini(lower - 1, last_bottom - 1) if x > 0 else lower - 1), 1, (absi(lower - last_bottom) + 1) if x > 0 else 1), Color(edge.darkened(0.3), a))
		if x == 0 or x == width - 1:
			draw_rect(Rect2(left + x, top + upper, 1, lower - upper), Color(edge, a))
		last_top = upper
		last_bottom = lower


## The twig the leaf hangs on: from the shaft to the near edge of the leaf, sagging a little, with a bud at the pillar's end.
func _draw_twig(top: int, left: int, width: int, a: float, void_level: float, accent: Color) -> void:
	var from_x: int = int(_side * SHAFT_HALF)
	var to_x: int = left if _side > 0.0 else left + width
	var y: int = top + HEIGHT / 2
	var span: int = absi(to_x - from_x)
	for i: int in span + 1:
		var x: int = from_x + int(_side) * i
		var sag: int = int(roundf(sin(float(i) / float(maxi(span, 1)) * PI) * 1.5))
		var color: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level) if i % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level)
		draw_rect(Rect2(x, y + sag, 1, 1), Color(color, a))
	var bud: Vector2 = Vector2(from_x, y)
	VineStyle.glow(self, bud, 4.0, accent, 0.7 * a)
	draw_rect(Rect2(bud, Vector2.ONE), Color(VineStyle.PETAL, a))


## What is left of the pillar as a crack of light: its length is the remaining integrity, it jumps shorter with every blow and flashes white.
func _draw_crack(x0: int, y: int, span: int, a: float, accent: Color) -> void:
	var frac: float = clampf(_pillar.integrity / maxf(_pillar.max_integrity, 1.0), 0.0, 1.0)
	var length: int = int(ceilf(float(span) * frac))
	for i: int in length:
		var jag: int = int(roundf((_smooth(float(i) * 0.2 + 3.0) - 0.5) * 2.0))
		draw_rect(Rect2(x0 + i, y + jag - 1, 1, 3), Color(VineStyle.OUTLINE, 0.8 * a))
	for i2: int in length:
		var jag2: int = int(roundf((_smooth(float(i2) * 0.2 + 3.0) - 0.5) * 2.0))
		var beat: float = VoidGlow.beat(_time - float(i2) * 0.012, 0.0, 0.8 + urgency * 0.6)
		var color: Color = accent.lerp(CORE_HOT, 0.2 + 0.45 * beat + 0.4 * _flash)
		draw_rect(Rect2(x0 + i2, y + jag2, 1, 1), Color(color, a * (0.65 + 0.35 * beat)))
	if length > 0:
		draw_rect(Rect2(x0 + length - 1, y - 1, 2, 3), Color(CORE_HOT, a))


func _smooth(x: float) -> float:
	var i: float = floorf(x)
	var f: float = x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(VineStyle.rand(int(i)), VineStyle.rand(int(i) + 1), f)
