class_name SapVine
extends Control
## A vine that grows out of the hotbar's end (health left, stamina right). Glowing sap fills it
## from the root outwards; life retreats towards the root, and the tip withers first. Sap
## pulses travel along it, the tip carries a breathing bud, a pale trail drains behind a
## drop, hits spray droplets, and at night the void creeps up from the tip.
## Subclasses set `ratio`, `palette`, `dim`, `label`, `alert` in `_update_state`.

const HEALTH_LEN: int = 86 ## the two sides differ a little on purpose: similar, but not mirrored
const STAMINA_LEN: int = 76
const HEIGHT: int = 44
const BASE_Y: float = 8.0 ## where the root meets the hotbar vine
const TRAIL_DRAIN: float = 0.5 ## vine fractions per second

var dir: int = -1 ## -1 grows to the left of its root, 1 to the right
var length: int = 96 ## px along the vine
var base_thick: int = 3 ## thickness at the root, thinning towards the tip
var label_y: float = BASE_Y + 6.0
var fork_at: float = 0.0 ## 0 = no side shoot, else its position along the vine (0..1)
var drips: bool = false ## sap swells at the tip and falls
var ratio: float = 1.0
var lie: float = -1.0 ## >= 0: shown instead of the real ratio (Hallucinations)
var palette: Array[Color] = [Color.WHITE, Color.GRAY, Color.DIM_GRAY] ## highlight, main, shade
var dim: float = 1.0
var label: String = ""
var alert: Color = Color(0, 0, 0, 0) ## pulsing warning color while in danger
var trail_color: Color = Color(0, 0, 0, 0) ## alpha 0 = no trail

var _shown: float = 1.0
var _trail: float = 1.0
var _flash: float = 0.0
var _time: float = 0.0
var _label_alpha: float = 0.4
var _last_label: String = ""
var _drop_pos: PackedVector2Array = PackedVector2Array()
var _drop_vel: PackedVector2Array = PackedVector2Array()
var _drop_life: PackedFloat32Array = PackedFloat32Array()
var _dirty: bool = true
var _redraw_timer: float = 0.0
const IDLE_REDRAW_INTERVAL: float = 0.066 ## ~15 FPS idle sway/breathing


func _ready() -> void:
	add_to_group("sap_vines")
	custom_minimum_size = Vector2(length, HEIGHT)
	size = Vector2(length, HEIGHT)


func _update_state(_delta: float) -> void:
	pass


## A hit: the vine flashes and shakes and sprays sap from where the life ends.
func hit() -> void:
	_flash = 1.0
	_dirty = true
	var head: Vector2 = _point(_shown * length)
	for i: int in 9:
		_drop_pos.append(head)
		_drop_vel.append(Vector2(VineStyle.rand(i + int(_time * 10.0)) * 40.0 - 20.0, -30.0 - VineStyle.rand(i * 5) * 30.0))
		_drop_life.append(0.5 + VineStyle.rand(i * 3) * 0.4)


func _root_x() -> float:
	return float(length) if dir < 0 else 0.0


## Position along the vine, `s` px from the root.
func _point(s: float) -> Vector2:
	return Vector2(_root_x() + dir * s, BASE_Y + _offset(s / length) + sin(s * 0.09 - _time * 1.4) * 1.0 * s / length)


## Vertical course of the vine (px below the root) at `t` 0..1 along it. Subclasses shape it.
func _offset(_t: float) -> float:
	return 0.0


func _process(delta: float) -> void:
	_time += delta
	var prev_ratio: float = ratio
	_update_state(delta)
	if lie >= 0.0 and ratio > 0.01: ## a hallucination: the vine shows a value that is not true
		label = str(ceili(float(label.to_int()) / ratio * lie))
		ratio = lie
	var ratio_changing: bool = absf(ratio - prev_ratio) > 0.001
	var shown_changing: bool = absf(_shown - ratio) > 0.002
	var trail_changing: bool = trail_color.a > 0.0 and absf(_trail - ratio) > 0.002
	_shown = lerpf(_shown, ratio, 1.0 - exp(-14.0 * delta))
	_trail = maxf(_shown, move_toward(_trail, ratio, TRAIL_DRAIN * delta)) if trail_color.a > 0.0 else _shown
	var was_flashing: bool = _flash > 0.0
	_flash = maxf(_flash - 3.0 * delta, 0.0)
	if label != _last_label:
		_last_label = label
		_label_alpha = 1.0
		_dirty = true
	var label_alpha_changing: bool = _label_alpha > 0.405
	_label_alpha = maxf(_label_alpha - 0.5 * delta, 0.4)
	var has_drops: bool = not _drop_pos.is_empty()
	for i: int in range(_drop_pos.size() - 1, -1, -1):
		_drop_life[i] -= delta
		if _drop_life[i] <= 0.0:
			_drop_pos.remove_at(i)
			_drop_vel.remove_at(i)
			_drop_life.remove_at(i)
			continue
		_drop_vel[i].y += 140.0 * delta
		_drop_pos[i] += _drop_vel[i] * delta

	if not visible or modulate.a <= 0.0:
		return

	var is_animating: bool = (ratio_changing
		or shown_changing
		or trail_changing
		or was_flashing
		or has_drops
		or label_alpha_changing
		or alert.a > 0.0)

	_redraw_timer += delta
	if is_animating or _dirty or _redraw_timer >= IDLE_REDRAW_INTERVAL:
		_redraw_timer = 0.0
		_dirty = false
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(roundf(sin(_time * 90.0) * 1.5 * _flash), 0.0))
	var void_level: float = VineStyle.void_amount()
	var pulse: float = 0.5 + 0.5 * sin(_time * 8.0) if alert.a > 0.0 else 0.0
	var tint: Color = Color(dim, dim, dim).lerp(Color.WHITE, _flash * 0.6)
	var head_s: float = _shown * length
	var trail_s: float = _trail * length

	for s: int in length + 1:
		var t: float = float(s) / length
		var p: Vector2 = _point(s)
		var thick: int = base_thick if t < 0.5 else (maxi(base_thick - 1, 1) if t < 0.85 else 1)
		var top: float = roundf(p.y) - (thick - 1) / 2
		var infected: float = VineStyle.infection(length - s, void_level, s / 2)
		var rim: Color = VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, infected).lerp(alert, pulse * 0.7)
		draw_rect(Rect2(p.x, top - 1, 1, thick + 2), rim)
		var body: Color
		if s <= head_s: ## sap
			body = palette[1].lerp(palette[2], 0.5 * (1.0 - t)) * tint
			var phase: float = fposmod(_time * 26.0 - s, length / 3.0) ## pulses ride outwards
			if phase < 4.0:
				body = body.lerp(alert if alert.a > 0.0 else palette[0], 1.0 - phase / 4.0)
			draw_rect(Rect2(p.x, top, 1, thick), body)
			draw_rect(Rect2(p.x, top, 1, 1), palette[0] * tint)
		elif s <= trail_s: ## sap that was just lost
			draw_rect(Rect2(p.x, top, 1, thick), trail_color)
		else: ## withered husk
			body = VineStyle.BARK.lerp(VineStyle.BARK_VOID, infected)
			draw_rect(Rect2(p.x, top, 1, thick), body)
			if s % 3 == 0:
				draw_rect(Rect2(p.x, top, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, infected))

	for k: int in 8: ## leaves: fresh in the sap, drooping husks beyond it
		var s: float = 9.0 + k * 11.0 + VineStyle.rand(k + 40 * (dir + 2)) * 5.0
		if s >= length - 6 or VineStyle.rand(k * 3 + dir) < 0.2:
			continue
		var p: Vector2 = _point(s)
		var infected: float = VineStyle.infection(length - s, void_level, k)
		var up: int = -1 if k % 2 == 0 else 1
		if s <= head_s:
			var green: Color = VineStyle.LEAF.lerp(palette[1], 0.3).lerp(VineStyle.LEAF_VOID, infected) * tint
			var light: Color = VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, infected)
			VineStyle.leaf(self, p + Vector2(0, up * 2), -dir if k % 3 == 0 else dir, up, 3, green, light)
		else:
			VineStyle.leaf(self, p + Vector2(0, 2), dir, 1, 2, VineStyle.BARK.lerp(VineStyle.BARK_VOID, infected), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, infected))

	if void_level > 0.05: ## void tendrils crawl out of the withered part
		for k: int in 5:
			var s: float = length * (0.45 + 0.1 * k) + VineStyle.rand(k + 9) * 6.0
			if s <= head_s or VineStyle.infection(length - s, void_level, k) < 0.5:
				continue
			var up: float = -1.0 if k % 2 == 0 else 1.0
			VineStyle.tendril(self, _point(s), Vector2(0.45 * dir, up * 0.9).normalized(), int(3 + 6 * void_level + VineStyle.rand(k) * 3.0), _time, k)

	if fork_at > 0.0: ## a side shoot with its own little bud
		var root: Vector2 = _point(fork_at * length)
		var alive: bool = fork_at * length <= head_s
		var husk: Color = VineStyle.BARK.lerp(VineStyle.BARK_VOID, VineStyle.infection(length * (1.0 - fork_at), void_level, 5))
		var shoot: Vector2 = root
		for i: int in 14:
			shoot = root + Vector2(dir * i * 0.9, i * 0.55 + sin(i * 0.5 + _time * 2.0) * 0.8)
			draw_rect(Rect2(roundf(shoot.x), roundf(shoot.y), 1, 1), (palette[1] * tint) if alive else husk)
		if alive:
			VineStyle.glow(self, shoot, 5.0, palette[0], 0.8 * dim)
			draw_rect(Rect2(roundf(shoot.x), roundf(shoot.y), 1, 1), VineStyle.PETAL)

	if drips and _shown > 0.05: ## sap swells at the tip, then falls
		var tip: Vector2 = _point(head_s)
		var phase: float = fposmod(_time * 0.55, 1.0)
		if phase < 0.6:
			draw_rect(Rect2(roundf(tip.x), roundf(tip.y) + 2, 1, 1 + int(phase * 3.0)), palette[1] * tint)
		else:
			var fall: float = (phase - 0.6) / 0.4
			draw_rect(Rect2(roundf(tip.x), roundf(tip.y) + 3 + fall * fall * 18.0, 1, 2), Color(palette[0], 1.0 - fall * 0.7))

	if _shown > 0.01: ## the bud at the end of the sap
		var head: Vector2 = _point(head_s)
		var open: int = 1 + int(1.5 + 1.5 * sin(_time * 3.0))
		VineStyle.glow(self, head, 9.0, palette[0], 0.9 * dim + _flash)
		for offset: Vector2 in [Vector2(-open, 0), Vector2(open, 0), Vector2(0, -open), Vector2(0, open)]:
			draw_rect(Rect2(roundf(head.x + offset.x), roundf(head.y + offset.y), 1, 1), palette[0] * tint)
		draw_rect(Rect2(roundf(head.x), roundf(head.y), 1, 1), VineStyle.PETAL)
		for i: int in 3: ## spores drift off the bud
			var phase: float = fposmod(_time * 0.6 + i * 0.33, 1.0)
			draw_rect(Rect2(roundf(head.x + sin(_time + i * 2.0) * 3.0), roundf(head.y - phase * 10.0), 1, 1), Color(palette[0], 1.0 - phase))

	for i: int in _drop_pos.size():
		draw_rect(Rect2(roundf(_drop_pos[i].x), roundf(_drop_pos[i].y), 1, 1), Color(palette[1], clampf(_drop_life[i] * 2.0, 0.0, 1.0)))

	if label != "":
		var at: Vector2i = Vector2i(roundi(_root_x() + dir * 20.0) - PixelText.width(label) / 2, int(label_y))
		PixelText.draw(self, label, at, Color(UiStyle.TEXT, _label_alpha), Color(VineStyle.OUTLINE, _label_alpha))
	draw_set_transform(Vector2.ZERO)
