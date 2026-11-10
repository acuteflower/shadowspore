class_name Hotbar
extends Control
## The 8 quick slots (inventory slots 0-7: tools and consumables, never weapons), drawn as a
## living vine with items hanging from it on threads of uneven length, swaying in a breeze.
## Number keys or the mouse wheel pick the slot: its thread shortens, it glows and a bloom opens
## on the vine above it. By night the void creeps in from both ends: bark blackens, leaves turn
## violet, tendrils crawl, pendants glow violet. The slots are real controls (drag & drop works).
## XP and level grow along the same vine: a thin golden light runs through it up to a bud at the
## current XP, the level number sits above it (no exact XP). A gain makes the light surge and shows "+XP"; a
## level-up fills the vine, the light sweeps across and blooms open one after another.

signal use_requested(slot: int) ## the number key of the already selected slot was pressed again

const W: float = 224.0
const BASE_Y: float = 8.0
const PAD: float = 8.0
const STRIDE: float = 24.0
const SKILL_X: float = 212.0 ## where the skill crystal hangs (see BlinkIcon)
const LIFT: float = 3.0
const POP: float = 3.0
const XP_START: float = 4.0
const XP_END: float = W - 4.0
const BLOOMS: int = 9
const BURST_SECONDS: float = 2.4

var selected: int = 0

var _slots: Array[ItemSlot] = []
var _lift: Array[float] = []
var _pop: Array[float] = []
var _last: Array[Dictionary] = []
var _inventory: InventoryComponent
var _overlay: Control
var _cursor_x: float = 0.0
var _time: float = 0.0
var _drag_ok: Array[bool] = [] ## while dragging: slots that accept the dragged stack
var _dragging: bool = false
var _drag_any: bool = false
var _progress: ProgressComponent
var _animate: bool = false ## a gain just came in: let the XP light run instead of snapping
var _display_level: int = 1
var _shown: float = 0.0 ## XP light, 0..1 along the vine
var _surge: float = 0.0 ## 1 -> 0 after a gain
var _burst: float = 0.0 ## 1 -> 0 after a level-up
var _gain: int = 0
var _gain_age: float = 9.0
var _badge: Control ## the LV label is a button: it opens the Fortschritt window
var _badge_hover: bool = false
var _ready_pulse: float = 0.0 ## rewards waiting: the bud beats
var _deny: Array[float] = [] ## 1 -> 0: the slot shook its head (nothing to heal, a pause runs)


## The vine's height at `x`: it sags in the middle and meets the sap vines at both ends.
static func vine_y(x: float) -> float:
	var u: float = 2.0 * x / W - 1.0
	return BASE_Y + (5.0 + sin(x * 0.13) * 0.8) * (1.0 - u * u)


func bind(inventory: InventoryComponent) -> void:
	_inventory = inventory
	add_to_group("hotbar")
	for i: int in InventoryComponent.HOTBAR_SIZE:
		var slot: ItemSlot = ItemSlot.new()
		slot.inventory = inventory
		slot.ref = i
		slot.bare = true
		add_child(slot)
		_slots.append(slot)
		_lift.append(0.0)
		_pop.append(0.0)
		_last.append(inventory.stack_at("inv", i).duplicate())
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	inventory.changed.connect(_on_inventory_changed)
	_update_drag_targets()
	_select(0)
	_cursor_x = _center_x(0)
	_place_slots()


## The slot controls (the inventory window adds tooltips to them).
func get_slots() -> Array[ItemSlot]:
	return _slots


func bind_progress(progress: ProgressComponent) -> void:
	_progress = progress
	_display_level = progress.level
	_shown = Levels.fraction(progress.xp)
	progress.gained.connect(_on_gained)
	progress.leveled.connect(func(_level: int) -> void: _ready_pulse = 1.0)
	_badge = Control.new()
	_badge.position = Vector2(W / 2.0 - 34.0, roundf(vine_y(W / 2.0)) - 20.0)
	_badge.size = Vector2(68, 14)
	_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	_badge.mouse_entered.connect(func() -> void: _badge_hover = true)
	_badge.mouse_exited.connect(func() -> void:
		_badge_hover = false
		GameCursor.set_hint(_badge, &""))
	_badge.gui_input.connect(_on_badge_input)
	add_child(_badge)


func _on_badge_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		get_tree().call_group("progress_window", "open_window")
		_badge.accept_event()


func _on_gained(amount: int) -> void:
	_animate = true
	_surge = 1.0
	_gain = amount
	_gain_age = 0.0


func _update_xp(delta: float) -> void:
	_ready_pulse = maxf(_ready_pulse - delta * 0.8, 0.0)
	if _badge != null:
		_badge.visible = visible and not InputManager.ui_blocking
		if _badge_hover and _badge.visible:
			GameCursor.set_hint(_badge, &"click")
	_surge = maxf(_surge - 1.6 * delta, 0.0)
	_burst = maxf(_burst - delta / BURST_SECONDS, 0.0)
	_gain_age += delta
	if _progress == null:
		return
	var real: int = _progress.level
	var fraction: float = Levels.fraction(_progress.xp)
	if not _animate or _display_level > real:
		_display_level = real
		_shown = fraction
	var target: float = fraction if _display_level == real else 1.0
	_shown = move_toward(_shown, target, maxf(absf(target - _shown) * 5.0, 0.25) * delta)
	if _display_level < real and _shown >= 0.999: ## the vine is full: the level rises and the light starts over
		_display_level += 1
		_shown = 0.0
		_burst = 1.0
	elif _display_level == real and absf(_shown - fraction) < 0.002:
		_animate = false


func _center_x(i: int) -> float:
	return PAD + 12.0 + i * STRIDE


func _thread_len(i: int) -> float:
	return 4.0 + VineStyle.rand(i * 7 + 1) * 5.0


func _on_inventory_changed() -> void:
	for i: int in _slots.size():
		var now: Dictionary = _inventory.stack_at("inv", i)
		if now != _last[i] and not now.is_empty():
			_pop[i] = 1.0
		_last[i] = now.duplicate()
		_slots[i].queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_update_xp(delta)
	var pick: int = InputManager.hotbar_pick()
	if pick >= 0:
		if pick == selected: ## the same key again uses the item (eat a berry)
			use_requested.emit(pick)
		else:
			_select(pick)
	elif InputManager.hotbar_step() != 0:
		_select(posmod(selected + InputManager.hotbar_step(), InventoryComponent.HOTBAR_SIZE))
	var ease_in: float = 1.0 - exp(-14.0 * delta)
	_update_drag_targets()
	for i: int in _slots.size():
		_lift[i] = lerpf(_lift[i], LIFT if i == selected else (2.0 if _drag_ok[i] else 0.0), ease_in)
		_pop[i] = maxf(_pop[i] - 3.0 * delta, 0.0)
		if i < _deny.size():
			_deny[i] = maxf(_deny[i] - 3.5 * delta, 0.0)
	_cursor_x = lerpf(_cursor_x, _center_x(selected), 1.0 - exp(-20.0 * delta))
	_place_slots()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _update_drag_targets() -> void:
	_dragging = _inventory != null and not _inventory.held.is_empty() ## a stack on the cursor
	_drag_any = false
	_drag_ok.clear()
	for i: int in _slots.size():
		var ok: bool = _dragging and _inventory.can_place("inv", i)
		_drag_ok.append(ok)
		_drag_any = _drag_any or ok


func _select(index: int) -> void:
	selected = index
	if _inventory != null:
		_inventory.select(index) ## a tool in this slot now replaces the weapon in her hand


## The item in slot `i` cannot be used now: the pendant shakes its head.
func deny(i: int) -> void:
	while _deny.size() < InventoryComponent.HOTBAR_SIZE:
		_deny.append(0.0)
	if i >= 0 and i < _deny.size():
		_deny[i] = 1.0


## 0..1 left of the pause that blocks the item in slot `i` (the food pause after eating, the wound pause after a healing potion), 0 = none.
func _pause_left(i: int) -> float:
	var effects: StatusEffects = _inventory.get_parent().get_node_or_null("Effects") as StatusEffects if _inventory != null else null ## no Player type here: the player scene preloads the HUD
	var stack: Dictionary = _inventory.stack_at("inv", i) if _inventory != null else {}
	if effects == null or stack.is_empty():
		return 0.0
	var effect: String = AlchemyRules.pause_effect(Items.definition(stack))
	if effect == "" or not effects.has(effect):
		return 0.0
	return clampf(effects.left(effect) / maxf(effects.total(effect), 0.01), 0.0, 1.0)


func _sway(i: int) -> float:
	return sin(_time * 1.1 + i * 1.7)


func _anchor(i: int) -> Vector2:
	var x: float = _center_x(i)
	return Vector2(x, vine_y(x))


func _slot_center(i: int) -> Vector2:
	var a: Vector2 = _anchor(i)
	var y: float = a.y + _thread_len(i) - _lift[i] - sin(_pop[i] * PI) * POP + ItemSlot.SIZE / 2.0
	var shake: float = sin(_deny[i] * 40.0) * 2.0 * _deny[i] if i < _deny.size() else 0.0
	return Vector2(roundf(a.x + _sway(i) * 1.2 + shake), roundf(y))


func _place_slots() -> void:
	for i: int in _slots.size():
		_slots[i].position = _slot_center(i) - Vector2(ItemSlot.SIZE, ItemSlot.SIZE) / 2.0
		var taken: float = _taken(_anchor(i).x)
		_slots[i].modulate = Color.WHITE.lerp(Color(0.78, 0.66, 1.0), taken * 0.7)


func _taken(x: float) -> float:
	return VineStyle.infection(minf(SapVine.HEALTH_LEN + x, SapVine.STAMINA_LEN + W - x), VineStyle.void_amount(), int(x / 3.0))


func _draw() -> void:
	var void_level: float = VineStyle.void_amount()
	for xi: int in int(W) + 1: ## the vine itself
		var x: float = xi
		var y: float = roundf(vine_y(x))
		var taken: float = _taken(x)
		var glitch: float = 1.0 if taken > 0.5 and VineStyle.rand(xi + int(_time * 6.0) * 131) < 0.03 * void_level else 0.0
		y += glitch
		draw_rect(Rect2(x, y - 2, 1, 5), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		draw_rect(Rect2(x, y - 1, 1, 3), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if xi % 3 != 1:
			draw_rect(Rect2(x, y - 1, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		if taken > 0.5 and VineStyle.rand(xi * 3 + int(_time * 2.0)) < 0.06: ## violet veins pulse in the black
			draw_rect(Rect2(x, y, 1, 1), VineStyle.VOID_GLOW)

	if _drag_any: ## dragging something the hotbar takes: a teal light runs along the vine
		for xi: int in int(W) + 1:
			var phase: float = fposmod(_time * 90.0 - xi, 60.0)
			draw_rect(Rect2(xi, roundf(vine_y(xi)) + 2, 1, 1), Color(UiStyle.ACCENT, 0.35 + 0.65 * (1.0 - phase / 60.0)))
	_draw_xp(void_level)

	for k: int in 14: ## leaves and the odd bloom, scattered
		var x: float = 6.0 + k * 16.0 + VineStyle.rand(k) * 9.0
		var r: float = VineStyle.rand(k * 11 + 3)
		if r < 0.15 or x > W - 4.0:
			continue
		var taken: float = _taken(x)
		var p: Vector2 = Vector2(x, roundf(vine_y(x)))
		var up: int = -1 if k % 2 == 0 else 1
		if r > 0.82: ## a small bloom: pale by day, a violet void flower with a dark heart at night
			var petals: Color = VineStyle.PETAL.lerp(VineStyle.LEAF_VOID_LIGHT, taken)
			var up_y: float = p.y - 3.0
			for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_rect(Rect2(p.x + o.x, up_y + o.y, 1, 1), petals)
			draw_rect(Rect2(p.x, up_y, 1, 1), VineStyle.BARK_VOID if taken > 0.5 else VineStyle.WARM_GLOW)
			if taken > 0.3:
				VineStyle.glow(self, Vector2(p.x, up_y), 5.0, VineStyle.VOID_GLOW, taken * 0.8)
		else:
			VineStyle.leaf(self, p + Vector2(0, up * 2), 1 if k % 3 else -1, up, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken))

	if void_level > 0.05: ## tendrils creep along the taken stretches
		for k: int in 9:
			var x: float = VineStyle.rand(k + 70) * W
			if _taken(x) < 0.6:
				continue
			var heading: Vector2 = Vector2(VineStyle.rand(k + 5) - 0.5, -0.9 if k % 2 == 0 else 0.9).normalized()
			VineStyle.tendril(self, Vector2(x, vine_y(x)), heading, int(3 + 7 * void_level + VineStyle.rand(k) * 3.0), _time, k)

	for i: int in _slots.size(): ## threads, glows and empty buds
		var a: Vector2 = _anchor(i)
		var c: Vector2 = _slot_center(i)
		var taken: float = _taken(a.x)
		var top_y: float = c.y - ItemSlot.SIZE / 2.0 + 1.0
		var steps: int = int(top_y - a.y)
		for s: int in range(1, steps):
			var x: float = a.x + (c.x - a.x) * float(s) / steps
			draw_rect(Rect2(roundf(x), a.y + s, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if s % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		draw_rect(Rect2(c.x - 1, top_y - 1, 3, 1), VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken)) ## a little leaf cap holds the pendant
		var has_item: bool = not _inventory.stack_at("inv", i).is_empty()
		var is_pick: bool = i == selected
		var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, taken)
		if _drag_ok[i]:
			tone = UiStyle.ACCENT ## drop targets glow teal
		var glow_strength: float = (0.45 if has_item else 0.12) + (0.6 if is_pick else 0.0) + taken * 0.2 + (0.5 if _drag_ok[i] else 0.0)
		VineStyle.glow(self, c, 16.0 if is_pick else 10.0, tone, glow_strength * (0.85 + 0.15 * sin(_time * 2.5 + i)))
		if not has_item: ## a seed pod waiting to be filled
			draw_rect(Rect2(c.x - 1, c.y - 1, 3, 3), VineStyle.BARK_VOID if taken > 0.4 else VineStyle.BARK)
			draw_rect(Rect2(c.x, c.y - 1, 1, 1), tone if is_pick else VineStyle.BARK_LIGHT)

	if _burst > 0.0: ## level-up: blooms open along the vine behind the sweeping light
		var sweep: float = (1.0 - _burst) * 1.5 * W
		for k: int in BLOOMS:
			var x: float = 14.0 + k * (W - 28.0) / (BLOOMS - 1)
			var open: float = clampf((sweep - x) / 30.0, 0.0, 1.0) * sqrt(_burst)
			if open <= 0.0:
				continue
			var p: Vector2 = Vector2(x, roundf(vine_y(x)) - 4.0)
			var radius: int = 1 + int(open * 2.5)
			VineStyle.glow(self, p, 9.0 * open, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, _taken(x)), 0.9)
			for o: Vector2 in [Vector2(-radius, 0), Vector2(radius, 0), Vector2(0, -radius), Vector2(0, radius), Vector2(-radius + 1, -radius + 1), Vector2(radius - 1, -radius + 1)]:
				draw_rect(Rect2(p + o, Vector2.ONE), VineStyle.PETAL)
			draw_rect(Rect2(p, Vector2.ONE), VineStyle.WARM_GLOW)
		for k: int in 18: ## spores rise
			var sx: float = VineStyle.rand(k + 600) * W
			if sx > sweep:
				continue
			var rise: float = (1.0 - _burst) * (10.0 + VineStyle.rand(k + 650) * 18.0)
			draw_rect(Rect2(roundf(sx + sin(_time * 2.0 + k) * 2.0), roundf(vine_y(sx)) - 5.0 - rise, 1, 1), Color(VineStyle.PETAL, _burst))

	var bloom: Vector2 = Vector2(roundf(_cursor_x), roundf(vine_y(_cursor_x)) - 3.0) ## the picked slot's bloom
	var open: int = 1 + int(1.5 + 1.5 * sin(_time * 3.0))
	VineStyle.glow(self, bloom, 8.0, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, _taken(_cursor_x)), 0.9)
	for o: Vector2 in [Vector2(-open, 0), Vector2(open, 0), Vector2(0, -open), Vector2(0, open)]:
		draw_rect(Rect2(bloom + o, Vector2.ONE), VineStyle.PETAL)
	draw_rect(Rect2(bloom, Vector2.ONE), VineStyle.WARM_GLOW)


func _draw_xp(void_level: float) -> void:
	if _progress == null:
		return
	var head: float = XP_START + _shown * (XP_END - XP_START)
	var sweep: float = (1.0 - _burst) * 1.5 * W if _burst > 0.0 else -99.0
	for xi: int in range(int(XP_START), int(head) + 1):
		var x: float = xi
		var y: float = roundf(vine_y(x))
		var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, _taken(x))
		var phase: float = fposmod(_time * 24.0 - x, 70.0) ## a light runs along the thread
		var color: Color = tone.lerp(VineStyle.PETAL, 1.0 - phase / 5.0 if phase < 5.0 else 0.0)
		color = color.lerp(VineStyle.PETAL, _surge * clampf(1.0 - (head - x) / 40.0, 0.0, 1.0))
		draw_rect(Rect2(x, y - 1, 1, 1), color)
		if _surge > 0.3 and xi % 2 == 0:
			draw_rect(Rect2(x, y - 2, 1, 1), Color(tone, _surge * 0.5))
	if _burst > 0.0: ## the sweeping light of a level-up
		for xi: int in range(maxi(int(sweep) - 14, 0), mini(int(sweep) + 1, int(W) + 1)):
			var y: float = roundf(vine_y(xi))
			draw_rect(Rect2(xi, y - 2, 1, 5), Color(VineStyle.PETAL, _burst * (1.0 - (sweep - xi) / 15.0) * 0.8))
	var tip: Vector2 = Vector2(roundf(head), roundf(vine_y(head)) - 3.0) ## the bud at the current XP
	var tone_tip: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, _taken(head))
	VineStyle.glow(self, tip, 6.0 + _surge * 4.0, tone_tip, 0.6 + _surge * 0.4)
	draw_rect(Rect2(tip, Vector2.ONE), VineStyle.PETAL)
	draw_rect(Rect2(tip + Vector2(0, 1), Vector2.ONE), tone_tip)
	if void_level > 0.5 and _shown > 0.0: ## sparks off the bud, like spores
		draw_rect(Rect2(roundf(tip.x + sin(_time * 2.0) * 2.0), roundf(tip.y - fposmod(_time * 6.0, 6.0)), 1, 1), Color(tone_tip, 0.7))


func _draw_xp_label() -> void:
	if _progress == null:
		return
	var center: float = W / 2.0
	var bounce: float = roundf(sin(minf(_burst * 3.0, 1.0) * PI) * 3.0)
	var taken: float = _taken(center)
	var base_y: int = roundi(vine_y(center)) - 16 - int(bounce)
	var number: String = str(_display_level)
	var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.LEAF_VOID_LIGHT, taken).lerp(VineStyle.PETAL, _burst)
	var dim: Color = Color(UiStyle.TEXT_DIM.lerp(VineStyle.LEAF_VOID_LIGHT, taken), 0.8)
	var total: int = PixelText.width("LV") + 3 + PixelText.width(number)
	var x: int = roundi(center) - total / 2
	PixelText.draw(_overlay, "LV", Vector2i(x, base_y), dim, VineStyle.OUTLINE)
	PixelText.draw(_overlay, number, Vector2i(x + PixelText.width("LV") + 3, base_y), tone, VineStyle.OUTLINE)
	if _badge_hover:
		VineStyle.glow(_overlay, Vector2(center, base_y + 3), 22.0, tone, 0.35)
	var waiting: int = _progress.claimable()
	if waiting > 0: ## rewards are waiting in the Fortschritt window: a golden bud beats beside the level
		var beat: float = 0.5 + 0.5 * sin(_time * 4.2)
		var bud: Vector2 = Vector2(x + total + 7, base_y + 3)
		VineStyle.glow(_overlay, bud, 8.0 + beat * 3.0 + _ready_pulse * 6.0, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, taken * 0.6), 0.55 + beat * 0.3 + _ready_pulse * 0.4)
		_overlay.draw_rect(Rect2(bud - Vector2(1, 1), Vector2(3, 3)), VineStyle.OUTLINE)
		_overlay.draw_rect(Rect2(bud, Vector2.ONE), VineStyle.PETAL)
		var note: String = "BELOHNUNG" if waiting == 1 else "%d BELOHNUNGEN" % waiting
		PixelText.draw(_overlay, note, Vector2i(roundi(center) - PixelText.width(note) / 2, base_y - 9), Color(VineStyle.WARM_GLOW, 0.55 + beat * 0.4), VineStyle.OUTLINE)
	if _gain_age < 1.4: ## "+12" floats up from the bud
		var head: float = XP_START + _shown * (XP_END - XP_START)
		var text: String = "+%d" % _gain
		var fade: float = 1.0 - _gain_age / 1.4
		PixelText.draw(_overlay, text, Vector2i(roundi(head) - PixelText.width(text) / 2, roundi(vine_y(head)) - 12 - int(_gain_age * 10.0)), Color(VineStyle.WARM_GLOW, fade), Color(VineStyle.OUTLINE, fade))


func _draw_overlay() -> void:
	_draw_xp_label()
	for i: int in _slots.size():
		var c: Vector2 = _slot_center(i)
		var is_pick: bool = i == selected
		var has_item: bool = not _inventory.stack_at("inv", i).is_empty()
		var taken: float = _taken(_center_x(i))
		var color: Color = VineStyle.PETAL if is_pick else UiStyle.TEXT_DIM.lerp(VineStyle.LEAF_VOID_LIGHT, taken)
		if has_item:
			PixelText.draw(_overlay, str(i + 1), Vector2i(roundi(c.x) - 10, roundi(c.y) - 11), color, VineStyle.OUTLINE)
		else:
			PixelText.draw(_overlay, str(i + 1), Vector2i(roundi(c.x) - 1, roundi(c.y) + 3), Color(color, 0.7), VineStyle.OUTLINE)
	for i: int in _slots.size(): ## a pause blocks this item: a dim ring runs out around it (the part still to wait)
		var left: float = _pause_left(i)
		if left <= 0.0:
			continue
		var spot: Vector2 = _slot_center(i)
		var steps: int = 28
		for k: int in steps:
			var along: float = float(k) / float(steps)
			if along > left:
				break
			var angle: float = -PI / 2.0 + along * TAU
			_overlay.draw_rect(Rect2((spot + Vector2(cos(angle) * 10.0, sin(angle) * 10.0)).round(), Vector2.ONE), Color(VineStyle.PETAL, 0.75))
		_overlay.draw_rect(Rect2(spot - Vector2(7, 7), Vector2(14, 14)), Color(0.05, 0.02, 0.1, 0.35 * left))
	if _dragging and not _drag_any: ## the hotbar only takes tools: show that nothing fits
		for i: int in _slots.size():
			var spot: Vector2 = _slot_center(i)
			for o: Vector2 in [Vector2(-2, -2), Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1), Vector2(2, 2), Vector2(2, -2), Vector2(1, -1), Vector2(-1, 1), Vector2(-2, 2)]:
				_overlay.draw_rect(Rect2(spot + o, Vector2.ONE), Color("c04a6a", 0.7))
	for i: int in _slots.size(): ## dragging an item: slots that take it light up with a pulsing ring and arrows
		if _drag_ok[i]:
			var spot: Vector2 = _slot_center(i)
			VineStyle.ring(_overlay, spot, 11, Color(UiStyle.ACCENT, 0.55 + 0.4 * sin(_time * 8.0)))
			var bob: float = roundf(sin(_time * 6.0 + i) * 1.0)
			for o: Vector2 in [Vector2(-1, -16), Vector2(0, -15), Vector2(1, -16)]:
				_overlay.draw_rect(Rect2(spot + o + Vector2(0, bob), Vector2.ONE), Color(UiStyle.ACCENT, 0.9))
	var c: Vector2 = _slot_center(selected)
	for k: int in 3: ## motes circle the picked pendant
		var angle: float = _time * 2.0 + k * TAU / 3.0
		_overlay.draw_rect(Rect2(roundf(c.x + cos(angle) * 13.0), roundf(c.y + sin(angle) * 8.0), 1, 1), VineStyle.PETAL)
