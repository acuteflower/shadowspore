class_name StarHallReturnSeal
extends Interactable
## Free-floating vertical Star Return Rift in Caelia's open interstellar sanctuary.
## No floor plinth: counter-rotating pixel-snapped astrolabe rings and a luminous tear of
## warm world-light drift gently in zero-G. Pressing E returns the local player to her waystone.

const REACH: float = 34.0
const COL_GOLD_DARK: Color = Color("6f5020")
const COL_GOLD_MID: Color = Color("b48a38")
const COL_GOLD_LIT: Color = Color("e6c468")
const COL_GOLD_CORE: Color = Color("fff0b0")
const COL_TEAL_MID: Color = Color("3cc0c6")
const COL_TEAL_LIT: Color = Color("78f4e6")
const COL_TEAL_CORE: Color = Color("d0fff8")
const COL_WORLD_CORE: Color = Color("fffaf0")

var _visual: Node2D
var _light: PointLight2D
var _t: float = 0.0
var _base_y: float = 0.0
var _base_set: bool = false


func _ready() -> void:
	name = "StarHallReturnSeal"
	_visual = Node2D.new()
	_visual.name = "RiftVisual"
	_visual.material = Unlit.material()
	_visual.draw.connect(_draw_rift)
	add_child(_visual)

	_light = PointLight2D.new()
	_light.position = Vector2(0.0, -6.0)
	_light.color = Color("7cf4ea")
	_light.energy = 0.64
	LightTexture.apply(_light, 152, 0.78, 1)
	add_child(_light)


func prompt() -> String:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null and sys.is_busy():
		return ""
	return "ZURÜCKKEHREN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - REACH


func prompt_position() -> Vector2:
	return Vector2(0.0, -40.0)


func interact(player: Player) -> void:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null:
		sys.return_from_starhall(player)


func _process(delta: float) -> void:
	_t += delta
	if not _base_set:
		_base_y = position.y
		_base_set = true
	var bob: float = roundf(sin(_t * 1.35) * 3.0)
	if _visual != null:
		_visual.position = Vector2(0.0, bob)
		_visual.queue_redraw()
	if _light != null:
		_light.position = Vector2(0.0, -6.0 + bob)
		_light.energy = 0.56 + 0.14 * sin(_t * 2.0)


func _draw_rift() -> void:
	var center: Vector2 = Vector2(0.0, -6.0)

	# 1. Clean pixel-snapped soft radial aura behind the vertical rift (no checkerboard dither dots, no vector blur)
	var pulse_aura: float = 0.86 + 0.14 * sin(_t * 2.2)
	for y: int in range(-18, 19):
		for x: int in range(-15, 16):
			var ex: float = float(x) / 15.0
			var ey: float = float(y) / 18.0
			var d: float = sqrt(ex * ex + ey * ey)
			if d > 1.0:
				continue
			var band: float = floor((1.0 - d) * 4.0) / 4.0
			if band > 0.0:
				_visual.draw_rect(Rect2(center + Vector2(float(x), float(y)), Vector2(1.0, 1.0)), Color(COL_TEAL_MID.r, COL_TEAL_MID.g, COL_TEAL_MID.b, band * 0.22 * pulse_aura))

	# 2. Outer tilted antique-gold astrolabe ring (slow rotation, crisp 1px pixel loop)
	var rot_a: float = _t * 0.52
	var steps_a: int = 44
	for i: int in steps_a:
		var ang: float = float(i) / float(steps_a) * TAU + rot_a
		var rx: float = cos(ang) * 20.0
		var ry: float = sin(ang) * 10.5
		var tilt: float = -0.34
		var px: float = roundf(rx * cos(tilt) - ry * sin(tilt))
		var py: float = roundf(rx * sin(tilt) + ry * cos(tilt))
		var front: bool = sin(ang) >= 0.0
		var col: Color = COL_GOLD_LIT if front else COL_GOLD_MID
		if i % 11 == 0:
			col = COL_GOLD_CORE
		_visual.draw_rect(Rect2(center + Vector2(px, py), Vector2(1.0, 1.0)), col)

	# 3. Inner counter-rotating turquoise-starlight ring (steep opposite tilt)
	var rot_b: float = -_t * 0.78
	var steps_b: int = 36
	for i: int in steps_b:
		var ang: float = float(i) / float(steps_b) * TAU + rot_b
		var rx: float = cos(ang) * 14.5
		var ry: float = sin(ang) * 18.0
		var tilt: float = 0.42
		var px: float = roundf(rx * cos(tilt) - ry * sin(tilt))
		var py: float = roundf(rx * sin(tilt) + ry * cos(tilt))
		var col: Color = COL_TEAL_LIT if sin(ang) >= 0.0 else COL_TEAL_MID
		if i % 9 == 0:
			col = COL_TEAL_CORE
		_visual.draw_rect(Rect2(center + Vector2(px, py), Vector2(1.0, 1.0)), col)

	# 4. Central vertical diamond tear of warm world-light (breathing gently)
	var pulse: float = 0.85 + 0.15 * sin(_t * 2.6)
	var half_h: int = 12
	for dy: int in range(-half_h, half_h + 1):
		var t_y: float = 1.0 - absf(float(dy)) / float(half_h + 1)
		var half_w: int = maxi(0, int(roundf(t_y * t_y * 5.2 * pulse)))
		for dx: int in range(-half_w, half_w + 1):
			var edge: float = absf(float(dx)) / maxf(1.0, float(half_w))
			var col: Color = COL_WORLD_CORE if (edge < 0.35 and absf(float(dy)) < 7.0) else (COL_TEAL_CORE if edge < 0.72 else COL_GOLD_LIT)
			_visual.draw_rect(Rect2(center + Vector2(float(dx), float(dy)), Vector2(1.0, 1.0)), col)

	# 5. Tiny inward-spiraling return motes
	for m: int in 8:
		var ph: float = fposmod(_t * 0.55 + float(m) / 8.0, 1.0)
		var rad: float = lerpf(28.0, 5.0, ph)
		var ang: float = float(m) * 0.785 + _t * 1.1 + ph * 1.8
		var mp: Vector2 = Vector2(roundf(cos(ang) * rad), roundf(sin(ang) * rad * 0.78))
		var col: Color = COL_GOLD_CORE if m % 2 == 0 else COL_TEAL_CORE
		_visual.draw_rect(Rect2(center + mp, Vector2(1.0, 1.0)), Color(col.r, col.g, col.b, sin(ph * PI) * 0.9))
