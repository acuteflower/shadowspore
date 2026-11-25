class_name VorgathRig
extends Node2D
## Procedural pixel-art rig for Vorgath, Brut der Mole (Dungeon #1 Endboss).
## Shadowspore shadow-creature palette: #040208 outline, #0b0718..#261942 void carapace,
## #4df2e0 glowing turquoise barnacles, #ff4fd8 3-eyed visor, heavy iron anchor-chain,
## and a detachable glowing amber Hafenlaterne hooked on his hunched back.

var facing: Vector2 = Vector2.DOWN
var anim_state: String = "idle" ## idle, walk, sweep_windup, sweep, spit, counter, charge, stagger, tide, stunned, dead
var anim_t: float = 0.0
var lantern_intact: bool = true
var hit_flash: float = 0.0
var counter_open: bool = false
var stagger_active: bool = false
var exposed: bool = false

var _glow: _VorgathGlow = null
var _t: float = 0.0


class _VorgathGlow extends Node2D:
	var rig: VorgathRig = null

	func _ready() -> void:
		material = Unlit.material()
		z_index = 2

	func _draw() -> void:
		if rig == null:
			return
		rig._draw_glow_layer(self)


func _ready() -> void:
	_glow = _VorgathGlow.new()
	_glow.rig = self
	add_child(_glow)


func _process(delta: float) -> void:
	_t += delta
	anim_t += delta
	if hit_flash > 0.0:
		hit_flash = maxf(hit_flash - delta * 6.0, 0.0)
	queue_redraw()
	if _glow != null:
		_glow.queue_redraw()


func _body_bob() -> float:
	if anim_state == "stunned":
		return 5.0 + sin(_t * 10.0) * 1.0
	if anim_state == "dead":
		return minf(anim_t * 14.0, 18.0)
	if anim_state == "walk":
		return sin(_t * 7.0) * 2.5
	return sin(_t * 2.8) * 1.5


func _flip_x() -> float:
	return -1.0 if facing.x < -0.15 else 1.0


func _draw() -> void:
	var fx: float = _flip_x()
	var bob: float = _body_bob()
	var death_a: float = clampf(1.0 - maxf(anim_t - 0.35, 0.0) * 0.9, 0.0, 1.0) if anim_state == "dead" else 1.0
	if death_a <= 0.02:
		return

	var ink: Color = Color("040208", death_a)
	var void_dark: Color = Color("0b0718", death_a)
	var void_mid: Color = Color("18102e", death_a)
	var void_hi: Color = Color("2b1e4d", death_a)
	var iron_dark: Color = Color("24293b", death_a)
	var iron_hi: Color = Color("5e6d8a", death_a)
	if hit_flash > 0.05:
		void_dark = void_dark.lerp(Color("f4e8ff", death_a), hit_flash * 0.75)
		void_mid = void_mid.lerp(Color("ffffff", death_a), hit_flash * 0.8)

	## Ground shadow ellipse (cool dark violet, never pure black)
	draw_set_transform(Vector2(0.0, 2.0), 0.0, Vector2(1.0, 0.48))
	draw_circle(Vector2.ZERO, 28.0, Color(Color("0a0616"), 0.68 * death_a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## Heavy clawed legs planted in sluice water
	var stride: float = sin(_t * 7.0) * 4.0 if anim_state == "walk" else 0.0
	for side: float in [-1.0, 1.0]:
		var lx: float = side * 12.0 + side * stride * 0.5
		draw_rect(Rect2(lx - 5.0, -14.0 + bob * 0.3, 10.0, 15.0), ink)
		draw_rect(Rect2(lx - 4.0, -13.0 + bob * 0.3, 8.0, 13.0), void_dark)
		draw_rect(Rect2(lx - 4.0, -13.0 + bob * 0.3, 3.0, 9.0), void_mid)

	## Massive hunched void-crustacean carapace torso
	var cy: float = -26.0 + bob
	draw_circle(Vector2(0.0, cy), 22.0, ink)
	draw_circle(Vector2(0.0, cy), 20.5, void_dark)
	draw_circle(Vector2(-3.0 * fx, cy - 3.0), 15.0, void_mid)
	draw_circle(Vector2(-6.0 * fx, cy - 7.0), 8.0, void_hi)

	## Hunched armored shoulder hump + ridge plates
	draw_circle(Vector2(-7.0 * fx, cy - 11.0), 13.5, ink)
	draw_circle(Vector2(-7.0 * fx, cy - 11.0), 12.0, void_mid)
	draw_circle(Vector2(-10.0 * fx, cy - 14.0), 6.0, void_hi)

	## Head / abyssal visor leaning forward
	var hx: float = 9.0 * fx
	var hy: float = cy + 3.0 + (4.0 if anim_state == "stunned" else 0.0)
	draw_circle(Vector2(hx, hy), 10.5, ink)
	draw_circle(Vector2(hx, hy), 9.0, void_dark)
	draw_rect(Rect2(hx - 6.0, hy - 5.0, 12.0, 4.0), void_mid)

	## Heavy iron anchor-chain weapon on his right side
	var swing_ang: float = 0.0
	if anim_state == "sweep_windup":
		swing_ang = -1.25 * fx
	elif anim_state == "sweep":
		swing_ang = lerpf(-1.25, 1.45, clampf(anim_t / 0.28, 0.0, 1.0)) * fx
	elif anim_state == "tide":
		swing_ang = -0.8 * fx + sin(_t * 14.0) * 0.25
	else:
		swing_ang = 0.22 * fx + sin(_t * 3.0) * 0.08
	var arm_root: Vector2 = Vector2(14.0 * fx, cy + 1.0)
	var anchor_tip: Vector2 = arm_root + Vector2(18.0 * fx, 14.0).rotated(swing_ang)
	## Chain links
	draw_line(arm_root, anchor_tip, ink, 5.0)
	draw_line(arm_root, anchor_tip, iron_dark, 3.0)
	draw_line(arm_root, anchor_tip, iron_hi, 1.0)
	## Massive corroded anchor flukes at tip
	var a_dir: Vector2 = (anchor_tip - arm_root).normalized()
	var a_perp: Vector2 = Vector2(-a_dir.y, a_dir.x)
	draw_line(anchor_tip - a_perp * 10.0 - a_dir * 4.0, anchor_tip + a_perp * 10.0 - a_dir * 4.0, ink, 6.0)
	draw_line(anchor_tip - a_perp * 9.0 - a_dir * 4.0, anchor_tip + a_perp * 9.0 - a_dir * 4.0, iron_hi, 3.5)
	draw_circle(anchor_tip + a_dir * 2.0, 4.5, ink)
	draw_circle(anchor_tip + a_dir * 2.0, 3.0, iron_hi)

	## Corroded iron hook & brass Hafenlaterne on hunched back (optional weakpoint!)
	var lx_back: float = -13.0 * fx
	var ly_back: float = cy - 19.0
	draw_rect(Rect2(lx_back - 2.0, ly_back - 4.0, 4.0, 8.0), iron_hi)
	if lantern_intact:
		draw_rect(Rect2(lx_back - 5.0, ly_back - 10.0, 10.0, 11.0), ink)
		draw_rect(Rect2(lx_back - 4.0, ly_back - 9.0, 8.0, 9.0), Color("8f6e40", death_a))


func _draw_glow_layer(canvas: CanvasItem) -> void:
	var fx: float = _flip_x()
	var bob: float = _body_bob()
	var death_a: float = clampf(1.0 - maxf(anim_t - 0.35, 0.0) * 0.9, 0.0, 1.0) if anim_state == "dead" else 1.0
	if death_a <= 0.02:
		return
	var cy: float = -26.0 + bob
	var hx: float = 9.0 * fx
	var hy: float = cy + 3.0 + (4.0 if anim_state == "stunned" else 0.0)
	var pulse: float = 0.78 + 0.22 * sin(_t * 5.0)

	## 3 glowing magenta void eyes
	var eye_col: Color = Color("4df2ff", death_a) if counter_open else (Color("ffd98a", death_a) if (stagger_active or exposed) else Color("ff4fd8", death_a))
	canvas.draw_rect(Rect2(hx + 1.0 * fx, hy - 2.0, 3.0, 2.0), eye_col)
	canvas.draw_rect(Rect2(hx - 3.0 * fx, hy - 3.0, 2.0, 2.0), eye_col)
	canvas.draw_rect(Rect2(hx - 1.0 * fx, hy + 1.0, 2.0, 2.0), Color(eye_col, 0.85 * death_a))

	## Luminous turquoise sea-barnacles & tide fissures across carapace
	var barnacles: Array[Vector2] = [
		Vector2(-12.0 * fx, cy - 8.0),
		Vector2(-4.0 * fx, cy - 15.0),
		Vector2(4.0 * fx, cy - 11.0),
		Vector2(-9.0 * fx, cy + 4.0),
		Vector2(8.0 * fx, cy - 4.0),
	]
	var bcol: Color = Color("4df2ff") if counter_open else Color("4df2e0")
	for bp: Vector2 in barnacles:
		canvas.draw_rect(Rect2(bp.round(), Vector2(3.0, 2.0)), Color(bcol, 0.85 * pulse * death_a))

	## Glowing Hafenlaterne weakpoint on back (amber beacon!)
	if lantern_intact:
		var lx_back: float = -13.0 * fx
		var ly_back: float = cy - 24.0
		canvas.draw_circle(Vector2(lx_back, ly_back), 9.0 * pulse, Color(Color("ffae3d"), 0.26 * death_a))
		canvas.draw_rect(Rect2(lx_back - 3.0, ly_back - 3.0, 6.0, 6.0), Color("ffd97a", death_a))
		canvas.draw_rect(Rect2(lx_back - 1.0, ly_back - 2.0, 2.0, 4.0), Color("fff7dc", death_a))

	## Intense Ice-Blue Counter Aura during Rammflut window!
	if counter_open:
		var cp: float = 0.72 + 0.28 * sin(_t * 36.0)
		canvas.draw_arc(Vector2(0.0, cy), 25.0, 0.0, TAU, 28, Color(Color("4df2ff"), 0.92 * cp), 3.0)
		canvas.draw_arc(Vector2(0.0, cy), 29.0, 0.0, TAU, 28, Color(Color("e8ffff"), 0.55 * cp), 1.5)

	## Swirling Golden Vortex during Sog des Tiefendocks stagger check!
	if stagger_active:
		for i: int in 4:
			var ang: float = _t * 4.2 + float(i) * (PI * 0.5)
			canvas.draw_arc(Vector2(0.0, cy + 12.0), 34.0, ang, ang + 0.9, 14, Color(Color("ffd98a"), 0.82), 2.5)
	elif exposed:
		canvas.draw_arc(Vector2(0.0, cy), 24.0, 0.0, TAU, 24, Color(Color("ffd98a"), 0.55 * pulse), 2.0)
