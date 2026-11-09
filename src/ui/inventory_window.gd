extends Control
## Inventory (Tab or I): the vines grow into the screen. Equipment hangs like wind chimes from a
## branch out of the left edge around the heroine, who stands in a ritual circle and looks at the
## cursor; the rucksack hangs from three branches growing out of the right edge. The hotbar vine
## stays where it is and is part of it. Items glow in their rarity color, pendants lift when hovered,
## empty equipment slots are rune rings, slots that take the stack on the cursor light up.
## **The cursor stack** (the host holds it, `InventoryComponent.held`): LMB takes a whole stack and puts it down (tops up, swaps);
## RMB takes half of a stack / puts ONE down / equips a single piece of gear; SHIFT+LMB moves a stack at once (gear to its slot, else
## hotbar <-> rucksack); the number keys 1-8 over a slot swap it with that hotbar slot (with a stack on the cursor they put it there);
## Q over a slot or with a stack on the cursor throws ONE piece out, CTRL+Q everything; a click on nothing throws the stack (RMB: one);
## R stacks and sorts the rucksack. Closing the window puts the cursor stack back into the bag.

const COLUMNS: int = 8
const ROWS: int = 3
const OPEN_SECONDS: float = 0.75
const CLOSE_SECONDS: float = 0.3
const HERO_FEET: Vector2 = Vector2(176, 262)
const HERO_SHEET: Texture2D = preload("res://assets/characters/player.png")
const HERO_FRAME: Vector2i = Vector2i(48, 56)
const HERO_FEET_IN_FRAME: Vector2 = Vector2(24, 51)
const EQUIP_BRANCH: Vector2 = Vector2(84.0, 340.0) ## y at the root, length (grows from the left edge)
const ROW_Y: Array[float] = [90.0, 152.0, 214.0]
const BACK_TIP_X: float = 320.0 ## where the rucksack branches end (they grow from the right edge)
const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
## Equipment chimes: slot name -> (x along the branch, thread length)
const EQUIP_LAYOUT: Dictionary = {
	"head": Vector2(176, 40), "chest": Vector2(108, 100), "legs": Vector2(80, 134), "feet": Vector2(52, 168),
	"main_hand": Vector2(246, 96), "talisman_1": Vector2(272, 62), "talisman_2": Vector2(296, 108), "talisman_3": Vector2(320, 76),
}

var _inventory: InventoryComponent
var _slots: Array[ItemSlot] = []
var _hotbar_slots: Array[ItemSlot] = []
var _tags: Array[Dictionary] = [] ## per slot: {anchor_x, len, row (-1 equipment), delay}
var _lift: Array[float] = []
var _pop: Array[float] = []
var _last: Array[Dictionary] = []
var _tooltip: ItemTooltip
var _overlay: Control
var _vignette: GradientTexture2D
var _hover: ItemSlot
var _open_t: float = 0.0
var _opening: bool = false
var _time: float = 0.0
var _ritual_pulse: float = 0.0
var _hero_sector: int = 2


func _ready() -> void:
	visible = false
	_vignette = VineStyle.make_vignette()


func bind(inventory: InventoryComponent, hotbar: Hotbar) -> void:
	_inventory = inventory
	for slot_name: String in DataRegistry.table("equipment_slots").keys():
		var layout: Vector2 = EQUIP_LAYOUT.get(slot_name, Vector2(150, 80))
		_make_slot("equip", slot_name, {"anchor_x": layout.x, "len": layout.y, "row": -1, "delay": 0.2 + layout.x / EQUIP_BRANCH.y * 0.4})
	for i: int in InventoryComponent.BACKPACK_SIZE:
		var row: int = i / COLUMNS
		var col: int = i % COLUMNS
		_make_slot("inv", InventoryComponent.HOTBAR_SIZE + i, {"anchor_x": -(56.0 + (COLUMNS - 1 - col) * 34.0), "len": 8.0 + VineStyle.rand(i + 11) * 9.0, "row": row, "delay": 0.15 + row * 0.12 + col * 0.04})
	for slot: ItemSlot in hotbar.get_slots(): ## hovering the hotbar shows tooltips too and counts for the number keys
		slot.hovered.connect(func(s: ItemSlot) -> void: _hover = s; _on_slot_hovered(s))
		slot.unhovered.connect(func() -> void: _hover = null; _tooltip.hide())
		_hotbar_slots.append(slot)
	_tooltip = ItemTooltip.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 20 ## above the HUD vines, which draw after this window
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 15 ## the stack on the cursor lies over the HUD vines (the tooltip is at 20)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	add_child(_tooltip)
	inventory.changed.connect(_on_inventory_changed)


func _make_slot(kind: String, ref: Variant, tag: Dictionary) -> void:
	var slot: ItemSlot = ItemSlot.new()
	slot.kind = kind
	slot.ref = ref
	slot.inventory = _inventory
	slot.bare = true
	slot.hovered.connect(func(s: ItemSlot) -> void: _hover = s; _on_slot_hovered(s))
	slot.unhovered.connect(func() -> void: _hover = null; _tooltip.hide())
	add_child(slot)
	_slots.append(slot)
	_tags.append(tag)
	_lift.append(0.0)
	_pop.append(0.0)
	_last.append(_inventory.stack_at(kind, ref).duplicate())


func _on_inventory_changed() -> void:
	for i: int in _slots.size():
		var now: Dictionary = _inventory.stack_at(_slots[i].kind, _slots[i].ref)
		if now != _last[i]:
			_pop[i] = 1.0
			if _slots[i].kind == "equip":
				_ritual_pulse = 1.0
		_last[i] = now.duplicate()
		_slots[i].queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if InputManager.inventory_pressed() and not InputManager.menu_open and not InputManager.map_open and not (InputManager.skills_open or InputManager.progress_open) and get_tree().get_first_node_in_group("board_window") == null:
		_set_open(not _opening) ## (not while a town window hangs on the screen)
	_open_t = move_toward(_open_t, 1.0 if _opening else 0.0, delta / (OPEN_SECONDS if _opening else CLOSE_SECONDS))
	visible = _open_t > 0.0
	InputManager.item_keys_claimed = false
	if _opening and _open_t >= 0.7:
		_item_keys()
	if not visible:
		return
	_ritual_pulse = maxf(_ritual_pulse - 0.9 * delta, 0.0)
	var ease_in: float = 1.0 - exp(-14.0 * delta)
	for i: int in _slots.size():
		_lift[i] = lerpf(_lift[i], 3.0 if _slots[i] == _hover else 0.0, ease_in)
		_pop[i] = maxf(_pop[i] - 2.5 * delta, 0.0)
		_place(i)
	_look_at_cursor()
	if _tooltip.visible:
		var viewport: Vector2 = get_viewport_rect().size
		_tooltip.global_position = (get_global_mouse_position() + Vector2(12, 10)).min(viewport - _tooltip.size)
	queue_redraw()
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _opening and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


## A click on nothing: the stack on the cursor is thrown into the world (RMB: one piece). (Slots take their own clicks.)
func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or not _opening or _inventory == null or _inventory.held.is_empty():
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		_inventory.request("throw", [true])
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		_inventory.request("throw", [false])
	accept_event()


## Number keys, Q and R while the window is open (the hotbar must not also select on a number key that was used here).
func _item_keys() -> void:
	var over: bool = _hover != null and is_instance_valid(_hover)
	var holding: bool = _inventory != null and not _inventory.held.is_empty()
	InputManager.item_keys_claimed = over or holding
	for n: int in 8:
		if Input.is_action_just_pressed(InputManager.HOTBAR_ACTIONS[n]):
			if over and not (_inventory.stack_at(_hover.kind, _hover.ref).is_empty() and _inventory.stack_at("inv", n).is_empty()):
				_inventory.request("hotkey", [_hover.kind, _hover.ref, n])
			elif holding:
				_inventory.request("hotkey", ["held", 0, n])
	var all: bool = Input.is_key_pressed(KEY_CTRL)
	if Input.is_action_just_pressed("item_throw"):
		if holding:
			_inventory.request("throw", [all])
		elif over:
			_inventory.request("dropslot", [_hover.kind, _hover.ref, all])
	if Input.is_action_just_pressed("item_sort"):
		_inventory.request("sort", [0])


func _set_open(open: bool) -> void:
	_opening = open
	InputManager.ui_blocking = open
	InputManager.inventory_open = open
	if open:
		_hover = null
	else:
		if _inventory != null:
			_inventory.request("stow", [0]) ## whatever is on the cursor goes back into the bag
		if _tooltip != null:
			_tooltip.hide()


# ---------- layout ----------

func _branch_y(row: int, x: float) -> float:
	if row < 0:
		return EQUIP_BRANCH.x + 9.0 * sin(x / EQUIP_BRANCH.y * PI) + sin(x * 0.07) * 1.3
	var u: float = (size.x - x) / (size.x - BACK_TIP_X)
	return ROW_Y[row] + 6.0 * pow(u, 1.4) + sin(x * 0.09 + row) * 1.3


func _anchor_point(i: int) -> Vector2:
	var tag: Dictionary = _tags[i]
	var x: float = float(tag["anchor_x"]) if int(tag["row"]) < 0 else size.x + float(tag["anchor_x"])
	return Vector2(x, _branch_y(int(tag["row"]), x))


func _progress(i: int) -> float:
	return clampf((_open_t - float(_tags[i]["delay"])) / 0.4, 0.0, 1.0)


## 0..1 with an overshoot: the pendants drop in and bounce.
func _back_out(p: float) -> float:
	var c: float = 2.2
	return 1.0 + (c + 1.0) * pow(p - 1.0, 3.0) + c * pow(p - 1.0, 2.0)


func _slot_center(i: int) -> Vector2:
	var a: Vector2 = _anchor_point(i)
	var p: float = _progress(i)
	var sway: float = sin(_time * 1.1 + i * 1.7) * 1.2 * p
	var length: float = float(_tags[i]["len"]) * _back_out(p)
	return Vector2(roundf(a.x + sway), roundf(a.y + length + ItemSlot.SIZE / 2.0 - _lift[i] - sin(_pop[i] * PI) * 3.0))


func _place(i: int) -> void:
	var slot: ItemSlot = _slots[i]
	var p: float = _progress(i)
	slot.position = _slot_center(i) - Vector2(ItemSlot.SIZE, ItemSlot.SIZE) / 2.0
	slot.modulate = Color(1, 1, 1, p).lerp(Color(0.78, 0.66, 1.0, p), _taken(slot.position.x) * 0.6)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP if p > 0.7 else Control.MOUSE_FILTER_IGNORE


func _taken(x: float) -> float:
	return VineStyle.infection(maxf(x, size.x - x) * 0.6, VineStyle.void_amount(), int(x / 5.0))


func _look_at_cursor() -> void:
	var offset: Vector2 = get_local_mouse_position() - (HERO_FEET + Vector2(0, -50))
	if offset.length() > 8.0:
		_hero_sector = posmod(roundi(offset.angle() / (PI / 4.0)), 8) ## sheet rows: E SE S SW W NW N NE


# ---------- drawing ----------

func _draw() -> void:
	var void_level: float = VineStyle.void_amount()
	var fade: float = _open_t
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, fade))
	if void_level > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.05, 0.4, 0.14 * void_level * fade))
	VineStyle.motes(self, size, _time, fade, void_level)
	_draw_hero(fade, void_level)

	var equip_reach: float = clampf(_open_t / 0.5, 0.0, 1.0)
	var equip_y: Callable = func(x: float) -> float: return _branch_y(-1, x)
	VineStyle.branch(self, 0.0, EQUIP_BRANCH.y, equip_y, 6, void_level, 40.0, _time, equip_reach)
	VineStyle.foliage(self, 0.0, EQUIP_BRANCH.y, equip_y, 14, 120, void_level, 40.0, _time, equip_reach)
	for row: int in ROWS:
		var reach: float = clampf((_open_t - row * 0.12) / 0.5, 0.0, 1.0)
		var row_y: Callable = func(x: float) -> float: return _branch_y(row, x)
		VineStyle.branch(self, size.x, BACK_TIP_X, row_y, 5, void_level, 30.0 + row * 8.0, _time, reach)
		VineStyle.foliage(self, size.x, BACK_TIP_X, row_y, 9, 200 + row * 17, void_level, 30.0 + row * 8.0, _time, reach)
	_draw_tag("AUSRÜSTUNG", Vector2(26, _branch_y(-1, 26.0)), 0.25, void_level)
	_draw_tag("RUCKSACK", Vector2(size.x - 24, _branch_y(0, size.x - 24.0)), 0.3, void_level)

	var held: Dictionary = _inventory.held if _inventory != null else {}
	for i: int in _slots.size():
		_draw_pendant(i, held, void_level)
	var hints: Array[String] = [
		"LMT: NEHMEN / ABLEGEN    RMT: HÄLFTE / EINES / AUSRÜSTEN    UMSCH+LMT: SCHNELL VERSCHIEBEN",
		"1-8: IN DIE HOTBAR    Q: EINES WERFEN (STRG: ALLES)    R: SORTIEREN    INS LEERE KLICKEN: WERFEN    TAB: SCHLIESSEN",
	]
	for line: int in hints.size():
		PixelText.draw(self, hints[line], Vector2i(int(size.x / 2.0) - PixelText.width(hints[line]) / 2, int(size.y) - 64 + line * 9), Color(UiStyle.TEXT_DIM, 0.5 * fade), Color(VineStyle.OUTLINE, 0.5 * fade))


func _draw_hero(fade: float, void_level: float) -> void:
	var p: float = clampf((_open_t - 0.15) / 0.5, 0.0, 1.0)
	var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, maxf(void_level, 0.4))
	var center: Vector2 = HERO_FEET + Vector2(0, 3)
	VineStyle.glow(self, center + Vector2(0, -46), 58.0 * p, tone, 0.35 * fade)
	for ring: int in 3: ## the ritual circle on the ground (a flattened ellipse)
		var radius: Vector2 = Vector2(58 - ring * 14, 17 - ring * 4) * p
		for step: int in 72:
			var angle: float = step * TAU / 72.0
			var on: bool = step % 3 != 0 or ring == 1
			if on:
				draw_rect(Rect2(roundf(center.x + cos(angle) * radius.x), roundf(center.y + sin(angle) * radius.y), 1, 1), Color(tone, (0.7 - ring * 0.18) * fade))
	for k: int in 10: ## runes orbit the circle
		var angle: float = _time * 0.5 + k * TAU / 10.0
		var spot: Vector2 = center + Vector2(cos(angle) * 58.0, sin(angle) * 17.0) * p
		draw_rect(Rect2(roundf(spot.x) - 1, roundf(spot.y), 3, 1), Color(VineStyle.PETAL, 0.8 * fade))
		draw_rect(Rect2(roundf(spot.x), roundf(spot.y) - 1, 1, 3), Color(VineStyle.PETAL, 0.8 * fade))
	if _ritual_pulse > 0.0: ## equipping makes the circle flare
		var grow: float = 1.0 - _ritual_pulse
		for step: int in 72:
			var angle: float = step * TAU / 72.0
			draw_rect(Rect2(roundf(center.x + cos(angle) * (58.0 + grow * 22.0)), roundf(center.y + sin(angle) * (17.0 + grow * 7.0)), 1, 1), Color(VineStyle.PETAL, _ritual_pulse))
		for k: int in 14:
			var rx: float = center.x + (VineStyle.rand(k + 300) - 0.5) * 90.0
			draw_rect(Rect2(roundf(rx), roundf(center.y - grow * (30.0 + VineStyle.rand(k + 330) * 60.0)), 1, 1), Color(tone, _ritual_pulse))
	var frame: int = 12 + int(_time * 4.0) % 4 ## idle loop
	var source: Rect2 = Rect2(frame * HERO_FRAME.x, _hero_sector * HERO_FRAME.y, HERO_FRAME.x, HERO_FRAME.y)
	var top_left: Vector2 = HERO_FEET - HERO_FEET_IN_FRAME * 2.0 + Vector2(0, -roundf(sin(_time * 1.5) * 1.0) - (1.0 - p) * 24.0)
	draw_texture_rect_region(HERO_SHEET, Rect2(top_left, Vector2(HERO_FRAME) * 2.0), source, Color(1, 1, 1, p * fade))


func _draw_tag(text: String, at: Vector2, delay: float, _void_level: float) -> void:
	VineStyle.tag(self, text, at, clampf((_open_t - delay) / 0.4, 0.0, 1.0), _taken(at.x), _time)


func _rarity_index(stack: Dictionary) -> int:
	return maxi(RARITIES.find(String(Items.definition(stack).get("rarity", "common"))), 0)


func _draw_pendant(i: int, held: Dictionary, void_level: float) -> void:
	var p: float = _progress(i)
	if p <= 0.0:
		return
	var slot: ItemSlot = _slots[i]
	var a: Vector2 = _anchor_point(i)
	var c: Vector2 = _slot_center(i)
	var taken: float = _taken(a.x)
	var stack: Dictionary = slot.stack()
	var has_item: bool = not stack.is_empty()
	var top_y: float = c.y - ItemSlot.SIZE / 2.0 + 1.0
	var steps: int = int(top_y - a.y)
	for s: int in range(1, steps):
		var x: float = a.x + (c.x - a.x) * float(s) / steps
		draw_rect(Rect2(roundf(x), a.y + s, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if s % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p))
	draw_rect(Rect2(c.x - 1, top_y - 1, 3, 1), Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), p))

	var hovered: bool = slot == _hover
	var glow_color: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, taken)
	var strength: float = 0.14
	if has_item:
		glow_color = Items.rarity_color(stack).lerp(VineStyle.VOID_GLOW, taken * 0.4)
		strength = 0.35 + _rarity_index(stack) * 0.14
	if hovered:
		strength += 0.4
	VineStyle.glow(self, c, 17.0 if hovered else 12.0, glow_color, strength * p * (0.85 + 0.15 * sin(_time * 2.5 + i)))

	if slot.kind == "equip" and not _inventory.slot_open(String(slot.ref)): ## a talisman slot that has not woken yet: a sealed bud and the level that opens it
		var need: int = LevelRewards.talisman_level(String(slot.ref).trim_prefix("talisman_").to_int())
		VineStyle.ring(self, c, 12, Color(VineStyle.BARK_LIGHT, 0.55 * p), 0.4)
		draw_circle(c, 5.0, Color(VineStyle.OUTLINE, 0.9 * p))
		draw_circle(c + Vector2(0, -1), 3.0, Color(VineStyle.BARK_VOID_LIGHT.lerp(VineStyle.BARK_LIGHT, 0.4 - taken * 0.4), p))
		draw_rect(Rect2(c.x, c.y - 1, 1, 1), Color(VineStyle.VOID_GLOW, (0.4 + 0.3 * sin(_time * 1.8 + i)) * p))
		var seal: String = "STUFE %d" % need
		PixelText.draw(self, seal, Vector2i(roundi(c.x) - PixelText.width(seal) / 2, roundi(c.y) + 16), Color(UiStyle.TEXT_DIM, 0.8 * p))
	elif slot.kind == "equip": ## equipment: a rune ring, the slot name inside while empty
		VineStyle.ring(self, c, 12, Color(glow_color, (0.9 if has_item else 0.45) * p), 1.0 if has_item else 0.5 + 0.2 * sin(_time * 2.0 + i))
		if not has_item:
			var short: String = String(DataRegistry.get_entry("equipment_slots", String(slot.ref)).get("short", ""))
			PixelText.draw(self, short, Vector2i(roundi(c.x) - PixelText.width(short) / 2, roundi(c.y) - 3), Color(UiStyle.TEXT_DIM, 0.8 * p))
		else:
			for k: int in 3:
				var angle: float = _time * 1.4 + k * TAU / 3.0
				draw_rect(Rect2(roundf(c.x + cos(angle) * 13.0), roundf(c.y + sin(angle) * 13.0), 1, 1), Color(glow_color, p))
	elif not has_item: ## a seed pod waiting to be filled
		draw_rect(Rect2(c.x - 1, c.y - 1, 3, 3), Color(VineStyle.BARK_VOID if taken > 0.4 else VineStyle.BARK, p))
		draw_rect(Rect2(c.x, c.y - 1, 1, 1), Color(VineStyle.BARK_LIGHT, p))
	elif _rarity_index(stack) >= 3: ## epic and legendary items shed sparks
		for k: int in 2:
			var phase: float = fposmod(_time * 0.7 + k * 0.5 + i * 0.13, 1.0)
			draw_rect(Rect2(roundf(c.x + (k * 2 - 1) * 8.0 + sin(_time * 3.0 + k) * 2.0), roundf(c.y + 8.0 - phase * 20.0), 1, 1), Color(glow_color, (1.0 - phase) * p))

	if not held.is_empty() and _inventory.can_place(slot.kind, slot.ref): ## the stack on the cursor: a ring where it would land
		VineStyle.ring(self, c, 10, Color(UiStyle.ACCENT, (0.5 + 0.4 * sin(_time * 8.0)) * p), 1.0)


func _draw_overlay() -> void:
	if _opening and _inventory != null and not _inventory.held.is_empty(): ## the stack on the cursor
		var held: Dictionary = _inventory.held
		var at: Vector2 = _overlay.get_local_mouse_position().round() + Vector2(6, 6)
		VineStyle.glow(_overlay, at, 13.0, Items.rarity_color(held), 0.45)
		var icon: Texture2D = Items.icon(held)
		if icon != null:
			_overlay.draw_texture(icon, at - Vector2(8, 8))
		var count: int = int(held.get("count", 1))
		if count > 1:
			var label: String = str(count)
			PixelText.draw(_overlay, label, Vector2i(int(at.x) + 8 - PixelText.width(label), int(at.y) + 1), UiStyle.TEXT, UiStyle.OUTLINE)
	for i: int in _slots.size(): ## a flash of sparks when a slot's content changes
		if _pop[i] > 0.0 and _progress(i) >= 1.0:
			var c: Vector2 = _slot_center(i)
			var tone: Color = Items.rarity_color(_slots[i].stack()) if not _slots[i].stack().is_empty() else VineStyle.PETAL
			for k: int in 6:
				var angle: float = k * TAU / 6.0 + _pop[i] * 2.0
				var r: float = (1.0 - _pop[i]) * 13.0 + 4.0
				_overlay.draw_rect(Rect2(roundf(c.x + cos(angle) * r), roundf(c.y + sin(angle) * r), 1, 1), Color(tone, _pop[i]))


func _on_slot_hovered(slot: ItemSlot) -> void:
	var item: Dictionary = slot.stack()
	if item.is_empty() or not _opening:
		return
	var equippable: bool = slot.kind == "inv" and Items.definition(item).has("slot")
	_tooltip.show_stack(item, equippable)
	_tooltip.show()
	_tooltip.move_to_front()
