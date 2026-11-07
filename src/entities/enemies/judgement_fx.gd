class_name JudgementFx
extends Node2D
## The weather of the judgement at the end of the second phase (docs/boss_sky_cleaver.md): while Mornath stands on the northern pillar and splits the sky,
## a ring of runes on the floor fills like a clock (from the top, clockwise), the sky darkens (a violet-black veil over the arena, under him), and a pillar of white light
## grows above him. Purely cosmetic and local to every peer; the fight decides what happens (`MornathFight`): `fail()` when the ring is full (the light widens over the whole
## arena), `discharge()` when the pillar burst in time (the light flows out and goes). Frees itself after a discharge.

const INK: Color = Color("0b0614")
const VEIN: Color = Color("7d57e0")
const VEIN_LIGHT: Color = Color("a98af0")
const CORE: Color = Color("ecd2ff")
const CORE_HOT: Color = Color("fff7ff")
const MAGENTA: Color = Color("ff4fd8")
const TICKS: int = 90
const COLUMN_HEIGHT: float = 330.0

var _boss: SkyCleaver
var _fight: MornathFight
var _radius: float = 150.0
var _dark: float = 0.5
var _t: float = 0.0
var _state: int = 0 ## 0 building, 1 failed, 2 discharging
var _state_t: float = 0.0
var _floor_node: Node2D
var _dark_node: Node2D
var _column_node: Node2D
var _centre: Vector2 = Vector2.ZERO


static func begin(boss: SkyCleaver, fight: MornathFight, radius: float, dark: float) -> JudgementFx:
	var fx: JudgementFx = JudgementFx.new()
	fx.name = "JudgementFx"
	fx._boss = boss
	fx._fight = fight
	fx._radius = radius
	fx._dark = dark
	boss.get_parent().add_child(fx)
	return fx


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	_centre = _boss.centre()
	_floor_node = Node2D.new()
	_floor_node.z_index = -3
	_floor_node.draw.connect(_draw_floor)
	add_child(_floor_node)
	_dark_node = Node2D.new()
	_dark_node.z_index = 3 ## over everybody on the floor, under the boss (his picture is on z 5)
	_dark_node.material = Unlit.material()
	_dark_node.draw.connect(_draw_dark)
	add_child(_dark_node)
	_column_node = Node2D.new()
	_column_node.z_index = 8
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_column_node.material = add
	_column_node.draw.connect(_draw_column)
	add_child(_column_node)


func fail() -> void:
	if _state == 0:
		_state = 1
		_state_t = 0.0


func discharge() -> void:
	if _state != 2:
		_state = 2
		_state_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	_state_t += delta
	if _state == 2 and _state_t > 1.3:
		queue_free()
		return
	if not is_instance_valid(_boss):
		queue_free()
		return
	_floor_node.queue_redraw()
	_dark_node.queue_redraw()
	_column_node.queue_redraw()


## 0..1: how far the clock has run.
func progress() -> float:
	if _state >= 1:
		return 1.0 if _state == 1 else 1.0
	if not is_instance_valid(_fight):
		return 0.0
	return clampf(_fight.judge_elapsed() / maxf(_fight.judge_total(), 0.01), 0.0, 1.0)


func _life() -> float:
	return 1.0 - smoothstep(0.0, 1.2, _state_t) if _state == 2 else 1.0


func _draw_floor() -> void:
	var p: float = progress()
	var life: float = _life()
	var beat: float = VoidGlow.beat(_t, 0.0, 0.9)
	var front: int = int(p * float(TICKS))
	for i: int in TICKS:
		var a: float = -PI / 2.0 + TAU * float(i) / float(TICKS)
		var dir: Vector2 = Vector2.from_angle(a)
		var filled: bool = i < front
		var rune: bool = i % 5 == 0
		var from: Vector2 = _centre + dir * (_radius - (3.0 if rune else 0.0))
		var to: Vector2 = _centre + dir * (_radius + (4.0 if rune else 1.0))
		if filled:
			var wave: float = 0.6 + 0.4 * sin(_t * 6.0 - float(i) * 0.4)
			var color: Color = VEIN_LIGHT.lerp(CORE_HOT, 0.3 + 0.4 * beat) if i > front - 6 else VEIN_LIGHT
			_floor_node.draw_line(from.round(), to.round(), Color(INK, 0.8 * life), 3.0)
			_floor_node.draw_line(from.round(), to.round(), Color(color, (0.55 + 0.4 * wave) * life), 1.0)
		else:
			_floor_node.draw_line(from.round(), to.round(), Color(INK, 0.5 * life), 3.0)
			_floor_node.draw_line(from.round(), to.round(), Color(VEIN, 0.4 * life), 1.0)
	# the hand of the clock: a faint thread from the middle to the front of the fill
	var front_angle: float = -PI / 2.0 + TAU * p
	var tip: Vector2 = _centre + Vector2.from_angle(front_angle) * (_radius - 4.0)
	_floor_node.draw_line(_centre.round(), tip.round(), Color(VEIN, 0.18 * life), 1.0)
	_floor_node.draw_rect(Rect2(tip.round() + Vector2(-2, -2), Vector2(5, 5)), Color(CORE_HOT, (0.5 + 0.4 * beat) * life))
	# twelve glyphs between the ticks
	for k: int in 12:
		var ga: float = -PI / 2.0 + TAU * (float(k) + 0.5) / 12.0
		var gp: Vector2 = _centre + Vector2.from_angle(ga) * (_radius + 12.0)
		var lit: bool = float(k) / 12.0 < p
		for gy: int in 3:
			for gx: int in 3:
				if (hash(k * 31 + gy * 5 + gx * 11) % 3) != 0 or (gx == 1 and gy == 1):
					_floor_node.draw_rect(Rect2(gp.round() + Vector2(gx - 1, gy - 1), Vector2.ONE), Color(CORE if lit else VEIN, (0.85 if lit else 0.3) * life))


func _draw_dark() -> void:
	var p: float = progress()
	var amount: float = _dark * smoothstep(0.0, 0.85, p) * _life()
	if _state == 1:
		amount = lerpf(_dark, _dark * 1.25, smoothstep(0.0, 0.6, _state_t))
	if amount <= 0.01:
		return
	_dark_node.draw_rect(Rect2(_centre + Vector2(-760, -560), Vector2(1520, 1120)), Color(0.025, 0.0, 0.09, amount))


func _draw_column() -> void:
	var p: float = progress()
	var life: float = _life()
	var eye: Vector2 = _boss.eye_position()
	var base_y: float = eye.y - 20.0
	var top_y: float = base_y - COLUMN_HEIGHT
	var half: float = (1.5 + 10.5 * pow(p, 1.3)) * life
	var power: float = 0.35 + 0.65 * p
	if _state == 1:
		half = lerpf(half, 80.0, smoothstep(0.0, 0.95, _state_t))
		power = 1.0
	elif _state == 2:
		power = life
	if half < 0.6:
		return
	var lines: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var reach: int = int(half) + 2
	for dx: int in range(-reach, reach + 1):
		var u: float = absf(float(dx)) / maxf(half, 0.1)
		var ragged: float = float(hash(dx * 7 + int(_t * 14.0)) % 100) / 100.0 * 0.28
		if u + ragged > 1.0:
			continue
		var core: float = 1.0 - u * u
		var x: float = eye.x + float(dx)
		var flicker: float = 0.8 + 0.2 * sin(_t * 31.0 + float(dx))
		var a: float = core * power * flicker
		lines.append(Vector2(x, base_y))
		lines.append(Vector2(x, base_y - COLUMN_HEIGHT * 0.45))
		colors.append(Color(CORE_HOT, 0.65 * a))
		lines.append(Vector2(x, base_y - COLUMN_HEIGHT * 0.45))
		lines.append(Vector2(x, top_y))
		colors.append(Color(CORE, 0.3 * a))
	if lines.size() >= 2:
		_column_node.draw_multiline_colors(lines, colors, 1.0)
	# the glow where the light leaves him, and motes that rise along the column
	var pulse: float = 0.6 + 0.4 * VoidGlow.beat(_t, 0.0, 0.9)
	_column_node.draw_rect(Rect2(Vector2(eye.x - half * 1.6 - 3.0, base_y - 5.0), Vector2(half * 3.2 + 6.0, 10.0)), Color(VEIN_LIGHT, 0.2 * power * pulse))
	_column_node.draw_rect(Rect2(Vector2(eye.x - half - 1.0, base_y - 2.0), Vector2(half * 2.0 + 2.0, 4.0)), Color(CORE_HOT, 0.4 * power * pulse))
	for m: int in 14:
		var seed_v: float = float(m) * 17.13
		var rise: float = fposmod(_t * (40.0 + 23.0 * fmod(seed_v, 1.0)) + seed_v * 9.0, COLUMN_HEIGHT)
		var mx: float = eye.x + (fmod(seed_v * 3.7, 1.0) * 2.0 - 1.0) * half * 1.2
		_column_node.draw_rect(Rect2(Vector2(mx, base_y - rise).round(), Vector2.ONE * (2 if m % 3 == 0 else 1)), Color(CORE_HOT, 0.7 * power * (1.0 - rise / COLUMN_HEIGHT)))
