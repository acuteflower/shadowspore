extends Control
## Inventory (Tab or I): the vines grow into the screen. On the left stands the heroine in her ritual circle and looks at the
## cursor; what she wears hangs around her from one canopy branch: the talismans as charms on a garland strung over her head,
## armour on a liana to her left, what she holds on a liana to her right. The rucksack hangs from branches growing out of the
## right edge. The hotbar vine stays where it is and is part of it. Items glow in their rarity colour, pendants lift when
## hovered, empty places show a pictogram of what belongs there, places that take the stack on the cursor light up.
## **Extending it:** an equipment place is one entry in data/equipment_slots.json (`group`: "charm" garland / "armor" left
## liana / "hand" right liana, `glyph`: pictogram rows of "#" and "."); every group spreads its places itself. The rucksack lays
## out InventoryComponent.BACKPACK_SIZE in rows of COLUMNS.
## **The cursor stack** (the host holds it, `InventoryComponent.held`): LMB takes a whole stack and puts it down (tops up, swaps);
## RMB takes half of a stack / puts ONE down / equips a single piece of gear; SHIFT+LMB moves a stack at once (gear to its slot, else
## hotbar <-> rucksack); the number keys 1-8 over a slot swap it with that hotbar slot (with a stack on the cursor they put it there);
## Q over a slot or with a stack on the cursor throws ONE piece out, CTRL+Q everything; a click on nothing throws the stack (RMB: one);
## R stacks and sorts the rucksack. Closing the window puts the cursor stack back into the bag.

const COLUMNS: int = 8
const OPEN_SECONDS: float = 0.75
const CLOSE_SECONDS: float = 0.3
const HERO_FEET: Vector2 = Vector2(150, 262)
const HERO_SHEET: Texture2D = preload("res://assets/characters/player.png")
const HERO_FRAME: Vector2i = Vector2i(48, 56)
const HERO_FEET_IN_FRAME: Vector2 = Vector2(24, 51)
const CANOPY: Vector2 = Vector2(78.0, 292.0) ## the branch everything she wears hangs from: y at the root, length (grows from the left edge)
const GARLAND: Vector2 = Vector2(86.0, 214.0) ## the charm string of the talismans: from x to x along the canopy
const GARLAND_SAG: float = 15.0
const LIANA_X: Dictionary = {"armor": 60.0, "hand": 240.0} ## the two lianas beside her; their places sit on twigs towards her
const LIANA_MID: float = 180.0 ## the places of a liana are spread round this height
const LIANA_STRIDE: float = 28.0
const LIANA_SPAN: float = 96.0 ## at most this far from the first to the last place of a liana
const TWIG: float = 23.0
const BAG_RIGHT: float = 64.0 ## the last rucksack column, from the right edge
const BAG_STRIDE: float = 30.0
const BAG_TOP: float = 92.0
const BAG_ROW: float = 50.0
const BAG_SPAN: float = 112.0 ## at most this far from the first to the last rucksack branch
const BACK: Color = Color("0b0714") ## the dark husk behind every place
const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]

var _inventory: InventoryComponent
var _slots: Array[ItemSlot] = []
var _hotbar_slots: Array[ItemSlot] = []
var _tags: Array[Dictionary] = [] ## per slot: {group ("bag" / "charm" / a liana), delay, len; bag: row, col; equipment: index in its group}
var _counts: Dictionary = {} ## equipment group -> number of places
var _rows: int = 1
var _lift: Array[float] = []
var _pop: Array[float] = []
var _last: Array[Dictionary] = []
var _tooltip: ItemTooltip
var _overlay: Control
var _vignette: GradientTexture2D
var _pool: GradientTexture2D ## a soft dark pool behind each group, so items read over a bright world
var _hover: ItemSlot
var _open_t: float = 0.0
var _opening: bool = false
var _time: float = 0.0
var _ritual_pulse: float = 0.0
var _hero_sector: int = 2
var _refuse_text: String = "" ## "SCHON EIN ARMBAND ANGELEGT": shown under the slot that said no
var _refuse_slot: ItemSlot
var _refuse_t: float = 0.0


func _ready() -> void:
	visible = false
	_vignette = _radial(Color(0.02, 0.01, 0.06, 0.62), Color(0.02, 0.01, 0.06, 0.94), 0.2, Vector2(0.45, 0.5))
	_pool = _radial(Color(0.02, 0.01, 0.05, 0.5), Color(0.02, 0.01, 0.05, 0.0), 0.3, Vector2(0.5, 0.5))


func _radial(inner: Color, outer: Color, from: float, center: Vector2) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([from, 1.0])
	gradient.colors = PackedColorArray([inner, outer])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = center
	texture.fill_to = Vector2(1.0, center.y)
	texture.width = 160
	texture.height = 90
	return texture


func bind(inventory: InventoryComponent, hotbar: Hotbar) -> void:
	_inventory = inventory
	var table: Dictionary = DataRegistry.table("equipment_slots")
	var groups: Dictionary = {} ## group -> slot names, in the table's order
	for slot_name: String in table.keys():
		var group: String = String((table[slot_name] as Dictionary).get("group", "armor"))
		if group != "charm" and not LIANA_X.has(group):
			group = "armor"
		if not groups.has(group):
			groups[group] = []
		(groups[group] as Array).append(slot_name)
	for group: String in groups:
		var names: Array = groups[group] as Array
		_counts[group] = names.size()
		for k: int in names.size():
			_make_slot("equip", String(names[k]), {"group": group, "index": k, "len": 6.0, "delay": (0.34 if group == "charm" else 0.26) + k * 0.06})
	_rows = ceili(float(InventoryComponent.BACKPACK_SIZE) / COLUMNS)
	for i: int in InventoryComponent.BACKPACK_SIZE:
		var row: int = i / COLUMNS
		var col: int = i % COLUMNS
		_make_slot("inv", InventoryComponent.HOTBAR_SIZE + i, {"group": "bag", "row": row, "col": col, "len": (6.0 + VineStyle.rand(i + 11) * 8.0) * _row_stride() / BAG_ROW, "delay": 0.15 + row * 0.12 + col * 0.04})
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
	slot.refused.connect(func(text: String) -> void: _refuse_text = text; _refuse_slot = slot; _refuse_t = 2.2)
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
	_refuse_t = maxf(_refuse_t - delta, 0.0)
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
	if open != _opening:
		Sfx.ui(self, "inv_open" if open else "inv_close", -2.0)
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

func _canopy_y(x: float) -> float:
	return CANOPY.x + 8.0 * sin(x / CANOPY.y * PI) + sin(x * 0.07) * 1.3


## The charm string: fastened to the canopy at both ends, sagging between.
func _garland_y(x: float) -> float:
	var u: float = clampf((x - GARLAND.x) / (GARLAND.y - GARLAND.x), 0.0, 1.0)
	return lerpf(_canopy_y(GARLAND.x), _canopy_y(GARLAND.y), u) + 2.0 + GARLAND_SAG * sin(u * PI)


func _liana_x(group: String, y: float) -> float:
	return float(LIANA_X[group]) + sin(y * 0.055 + (0.0 if group == "armor" else 2.0)) * 3.0


## Towards the heroine: the twigs of the left liana reach right, those of the right one left.
func _liana_dir(group: String) -> float:
	return 1.0 if float(LIANA_X[group]) < HERO_FEET.x else -1.0


func _liana_slot_y(index: int, count: int) -> float:
	var stride: float = minf(LIANA_STRIDE, LIANA_SPAN / maxf(count - 1, 1.0))
	return LIANA_MID + (index - (count - 1) / 2.0) * stride


func _row_stride() -> float:
	return minf(BAG_ROW, BAG_SPAN / maxf(_rows - 1, 1.0))


## Where the rucksack branches end (they grow from the right edge).
func _bag_tip() -> float:
	return size.x - BAG_RIGHT - (COLUMNS - 1) * BAG_STRIDE - 20.0


func _row_y(row: int, x: float) -> float:
	var u: float = (size.x - x) / (size.x - _bag_tip())
	return BAG_TOP + row * _row_stride() + 6.0 * pow(u, 1.4) + sin(x * 0.09 + row) * 1.3


func _is_liana(i: int) -> bool:
	return LIANA_X.has(String(_tags[i]["group"]))


func _anchor_point(i: int) -> Vector2:
	var tag: Dictionary = _tags[i]
	var group: String = String(tag["group"])
	if group == "bag":
		var x: float = size.x - BAG_RIGHT - (COLUMNS - 1 - int(tag["col"])) * BAG_STRIDE
		return Vector2(x, _row_y(int(tag["row"]), x))
	if group == "charm":
		var x: float = lerpf(GARLAND.x, GARLAND.y, (int(tag["index"]) + 1.0) / (int(_counts[group]) + 1.0))
		return Vector2(x, _garland_y(x))
	var y: float = _liana_slot_y(int(tag["index"]), int(_counts[group]))
	return Vector2(_liana_x(group, y), y)


func _slot_radius(i: int) -> int:
	match String(_tags[i]["group"]):
		"bag": return 10
		"hand": return 13
	return 11


func _progress(i: int) -> float:
	return clampf((_open_t - float(_tags[i]["delay"])) / 0.4, 0.0, 1.0)


## 0..1 with an overshoot: the pendants drop in and bounce.
func _back_out(p: float) -> float:
	var c: float = 2.2
	return 1.0 + (c + 1.0) * pow(p - 1.0, 3.0) + c * pow(p - 1.0, 2.0)


func _slot_center(i: int) -> Vector2:
	var a: Vector2 = _anchor_point(i)
	var p: float = _progress(i)
	var bounce: float = _lift[i] + sin(_pop[i] * PI) * 3.0
	if _is_liana(i): ## on a twig beside the liana: it nods instead of swinging
		var reach: float = TWIG * _back_out(p) * _liana_dir(String(_tags[i]["group"]))
		return Vector2(roundf(a.x + reach), roundf(a.y + sin(_time * 1.1 + i * 1.7) * 0.9 * p - bounce))
	var sway: float = sin(_time * 1.1 + i * 1.7) * 1.2 * p
	var length: float = float(_tags[i]["len"]) * _back_out(p)
	return Vector2(roundf(a.x + sway), roundf(a.y + length + _slot_radius(i) - bounce))


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
	draw_texture_rect(_pool, Rect2(-30.0, 40.0, 360.0, 280.0), false, Color(1, 1, 1, fade))
	draw_texture_rect(_pool, Rect2(_bag_tip() - 60.0, 40.0, size.x - _bag_tip() + 120.0, 250.0), false, Color(1, 1, 1, fade))
	if void_level > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.05, 0.4, 0.14 * void_level * fade))
	VineStyle.motes(self, size, _time, fade, void_level)
	_draw_hero(fade, void_level)

	var canopy_reach: float = clampf(_open_t / 0.5, 0.0, 1.0)
	var canopy_y: Callable = func(x: float) -> float: return _canopy_y(x)
	VineStyle.branch(self, 0.0, CANOPY.y, canopy_y, 6, void_level, 40.0, _time, canopy_reach)
	VineStyle.foliage(self, 0.0, CANOPY.y, canopy_y, 12, 120, void_level, 40.0, _time, canopy_reach)
	for group: String in LIANA_X:
		if _counts.has(group):
			_draw_liana(group, clampf((_open_t - 0.12) / 0.5, 0.0, 1.0))
	if _counts.has("charm"):
		_draw_garland(clampf((_open_t - 0.2) / 0.45, 0.0, 1.0))
	for row: int in _rows:
		var reach: float = clampf((_open_t - row * 0.12) / 0.5, 0.0, 1.0)
		var row_y: Callable = func(x: float) -> float: return _row_y(row, x)
		VineStyle.branch(self, size.x, _bag_tip(), row_y, 5, void_level, 30.0 + row * 8.0, _time, reach)
		VineStyle.foliage(self, size.x, _bag_tip(), row_y, 9, 200 + row * 17, void_level, 30.0 + row * 8.0, _time, reach)
	_draw_tag("AUSRÜSTUNG", Vector2(26, _canopy_y(26.0)), 0.25, void_level)
	var bag_tag: Vector2 = Vector2(size.x - 26, _row_y(0, size.x - 26.0))
	_draw_tag("RUCKSACK", bag_tag, 0.3, void_level)
	var used: int = 0
	for i: int in InventoryComponent.BACKPACK_SIZE:
		if _inventory != null and not _inventory.stack_at("inv", InventoryComponent.HOTBAR_SIZE + i).is_empty():
			used += 1
	var room: String = "%d/%d" % [used, InventoryComponent.BACKPACK_SIZE] ## how full the rucksack is
	var room_fade: float = clampf((_open_t - 0.55) / 0.3, 0.0, 1.0)
	PixelText.draw(self, room, Vector2i(roundi(bag_tag.x) - PixelText.width(room) / 2, roundi(bag_tag.y) + 24), Color(Color("ff8a96") if used >= InventoryComponent.BACKPACK_SIZE else UiStyle.TEXT_DIM, 0.85 * room_fade), Color(VineStyle.OUTLINE, room_fade))

	var held: Dictionary = _inventory.held if _inventory != null else {}
	for i: int in _slots.size():
		_draw_pendant(i, held, void_level)
	_draw_legend(clampf((_open_t - 0.6) / 0.3, 0.0, 1.0), void_level)


## A liana hanging from the canopy beside the heroine: thick at the branch, a leafy tip with a bud below its last place.
func _draw_liana(group: String, reach: float) -> void:
	var count: int = int(_counts[group])
	var top: float = roundf(_canopy_y(float(LIANA_X[group]))) + 2.0
	var bottom: float = _liana_slot_y(count - 1, count) + 14.0
	var end: int = int(lerpf(top, bottom, reach))
	var dir: float = _liana_dir(group)
	for yi: int in range(int(top), end + 1):
		var t: float = (yi - top) / (bottom - top)
		var th: int = 3 if t < 0.45 else (2 if t < 0.85 else 1)
		var x: float = roundf(_liana_x(group, yi)) - floorf(th / 2.0)
		var taken: float = _taken(x)
		draw_rect(Rect2(x - 1, yi, th + 2, 1), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		draw_rect(Rect2(x, yi, th, 1), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if yi % 3 != 1:
			draw_rect(Rect2(x, yi, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		if yi % 11 == 4 and yi < int(bottom) - 5: ## leaves, mostly on the side away from her
			var out: int = -int(dir) if (yi / 11) % 3 != 0 else int(dir)
			VineStyle.leaf(self, Vector2(x + (th - 1 if out > 0 else 0), yi), out, -1, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken))
	if reach >= 1.0: ## the tip: two leaves and a bud of light
		var tip: Vector2 = Vector2(roundf(_liana_x(group, bottom)), bottom + 1.0)
		var taken: float = _taken(tip.x)
		VineStyle.leaf(self, tip + Vector2(0, 1), 1, 1, 2, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken))
		VineStyle.leaf(self, tip + Vector2(0, 1), -1, 1, 2, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken))
		var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, maxf(taken, 0.25))
		VineStyle.glow(self, tip + Vector2(0, 2), 5.0, tone, 0.7 + 0.2 * sin(_time * 2.0 + tip.x))
		draw_rect(Rect2(tip + Vector2(0, 2), Vector2.ONE), VineStyle.PETAL)


## The charm string of the talismans: a thin thread strung under the canopy with dew lights between the charms; it grows from both ends.
func _draw_garland(reach: float) -> void:
	var span: float = GARLAND.y - GARLAND.x
	for xi: int in range(int(GARLAND.x), int(GARLAND.y) + 1):
		var u: float = (xi - GARLAND.x) / span
		if minf(u, 1.0 - u) * 2.0 > reach:
			continue
		var y: float = roundf(_garland_y(xi))
		var taken: float = _taken(xi)
		draw_rect(Rect2(xi, y + 1, 1, 1), Color(VineStyle.OUTLINE, 0.7))
		draw_rect(Rect2(xi, y, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if xi % 3 != 0 else VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken))
	if reach < 1.0:
		return
	var count: int = int(_counts["charm"])
	for k: int in count + 1: ## a dew light between every two charms
		var x: float = roundf(lerpf(GARLAND.x, GARLAND.y, (k + 0.5) / (count + 1.0)))
		var at: Vector2 = Vector2(x, roundf(_garland_y(x)) + 2.0)
		var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, maxf(_taken(x), 0.35))
		var beat: float = 0.5 + 0.5 * sin(_time * 1.7 + k * 1.3)
		VineStyle.glow(self, at, 4.0, tone, 0.35 + 0.4 * beat)
		draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, 0.55 + 0.45 * beat))
	for end_x: float in [GARLAND.x, GARLAND.y]: ## the knots on the canopy
		draw_rect(Rect2(end_x - 1, roundf(_canopy_y(end_x)) + 1, 3, 2), VineStyle.OUTLINE)
		draw_rect(Rect2(end_x, roundf(_canopy_y(end_x)) + 1, 1, 1), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, _taken(end_x)))


## What the keys do right now, as key caps under the rucksack: it follows what the pointer is over and whether a stack hangs on it.
func _draw_legend(fade: float, void_level: float) -> void:
	if fade <= 0.0 or _inventory == null:
		return
	var holding: bool = not _inventory.held.is_empty()
	var over: ItemSlot = _hover if _hover != null and is_instance_valid(_hover) and not _hover.stack().is_empty() else null
	var throw_key: String = VineStyle.key_name("item_throw", "Q")
	var rows: Array = [] ## rows of [keys, word]
	if holding:
		rows.append([[[VineStyle.MOUSE_LEFT], "ABLEGEN"], [[VineStyle.MOUSE_RIGHT], "EINES"], [["1-8"], "HOTBAR"]])
		rows.append([[[throw_key], "EINES WERFEN"], [[VineStyle.MOUSE_LEFT], "INS LEERE: WERFEN"]])
	elif over != null:
		var second: String = "HÄLFTE"
		if over.kind == "equip":
			second = "ABLEGEN"
		elif Items.definition(over.stack()).has("slot"):
			second = "ANLEGEN"
		rows.append([[[VineStyle.MOUSE_LEFT], "NEHMEN"], [[VineStyle.MOUSE_RIGHT], second], [["UMSCH", VineStyle.MOUSE_LEFT], "SCHNELL"]])
		rows.append([[["1-8"], "HOTBAR"], [[throw_key], "WERFEN"], [["STRG", throw_key], "ALLES"]])
	else:
		rows.append([[[VineStyle.key_name("item_sort", "R")], "SORTIEREN"], [[VineStyle.key_name("inventory", "TAB")], "SCHLIESSEN"]])
	for line: int in rows.size():
		var entries: Array = rows[line] as Array
		var width: int = -12
		for entry: Array in entries:
			for key: String in entry[0]:
				width += VineStyle.cap_width(key) + 2
			width += PixelText.width(String(entry[1])) + 12
		var x: float = size.x - 14.0 - width
		var y: float = 258.0 + line * 15.0
		for entry: Array in entries:
			for key: String in entry[0]:
				x += VineStyle.key_cap(self, Vector2(x, y), key, fade, 0.0, void_level) + 2
			PixelText.draw(self, String(entry[1]), Vector2i(int(x) + 2, int(y) + 3), Color(UiStyle.TEXT_DIM, 0.9 * fade), Color(VineStyle.OUTLINE, fade))
			x += PixelText.width(String(entry[1])) + 12.0


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
	if p * fade > 0.6: ## her necklace and earrings (the bracelet sits on the sword arm, which the sheet does not hold)
		TalismanArt.draw_worn(self, self, TalismanRules.worn_ids(_inventory.equipment), TalismanArt.frame_data(HERO_SHEET, _hero_sector * 22 + frame), top_left + HERO_FEET_IN_FRAME * 2.0, 2.0, _time, 0.6)


func _draw_tag(text: String, at: Vector2, delay: float, _void_level: float) -> void:
	VineStyle.tag(self, text, at, clampf((_open_t - delay) / 0.4, 0.0, 1.0), _taken(at.x), _time)


func _rarity_index(stack: Dictionary) -> int:
	return maxi(RARITIES.find(String(Items.definition(stack).get("rarity", "common"))), 0)


func _draw_pendant(i: int, held: Dictionary, _void_level: float) -> void:
	var p: float = _progress(i)
	if p <= 0.0:
		return
	var slot: ItemSlot = _slots[i]
	var group: String = String(_tags[i]["group"])
	var a: Vector2 = _anchor_point(i)
	var c: Vector2 = _slot_center(i)
	var radius: int = _slot_radius(i)
	var taken: float = _taken(a.x)
	var stack: Dictionary = slot.stack()
	var has_item: bool = not stack.is_empty()
	var bark_a: Color = Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken), p)
	var bark_b: Color = Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), p)
	if _is_liana(i): ## a twig from the liana, bowing a little
		var dir: float = signf(c.x - a.x)
		var steps: int = int(absf(c.x - a.x)) - radius
		for s: int in range(1, steps + 1):
			var k: float = float(s) / maxf(steps, 1.0)
			var y: float = roundf(lerpf(a.y, c.y, k) - sin(k * PI) * 2.0)
			draw_rect(Rect2(a.x + dir * s, y + 1, 1, 1), Color(VineStyle.OUTLINE, 0.8 * p))
			draw_rect(Rect2(a.x + dir * s, y, 1, 1), bark_a if s % 3 != 0 else bark_b)
		draw_rect(Rect2(c.x - dir * (radius + 1), c.y - 1, 1, 3), Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), p)) ## a leaf cuff holds the place
	else: ## a thread from the branch (or the garland)
		var top_y: float = c.y - radius + 1.0
		var steps: int = int(top_y - a.y)
		for s: int in range(1, steps):
			var x: float = a.x + (c.x - a.x) * float(s) / steps
			draw_rect(Rect2(roundf(x), a.y + s, 1, 1), bark_a if s % 2 == 0 else bark_b)
		draw_rect(Rect2(c.x - 1, top_y - 1, 3, 1), Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), p))

	var hovered: bool = slot == _hover
	var sealed: bool = slot.kind == "equip" and not _inventory.slot_open(String(slot.ref))
	var glow_color: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, taken)
	var strength: float = 0.14
	if has_item:
		glow_color = Items.rarity_color(stack).lerp(VineStyle.VOID_GLOW, taken * 0.4)
		strength = 0.35 + _rarity_index(stack) * 0.14
	if hovered:
		strength += 0.4
	VineStyle.glow(self, c, radius + (7.0 if hovered else 3.0), glow_color, strength * p * (0.85 + 0.15 * sin(_time * 2.5 + i)))
	draw_circle(c + Vector2(0.5, 0.5), radius, Color(BACK, (0.72 if has_item else 0.5) * p)) ## the dark husk: items read over any ground

	var rim: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken)
	if group == "bag":
		if has_item:
			var rare: int = _rarity_index(stack)
			VineStyle.ring(self, c, radius, Color(rim.lerp(glow_color, 0.75) if rare > 0 else rim, (0.6 + rare * 0.08) * p))
			if rare >= 3: ## epic and legendary items shed sparks
				for k: int in 2:
					var phase: float = fposmod(_time * 0.7 + k * 0.5 + i * 0.13, 1.0)
					draw_rect(Rect2(roundf(c.x + (k * 2 - 1) * 8.0 + sin(_time * 3.0 + k) * 2.0), roundf(c.y + 8.0 - phase * 20.0), 1, 1), Color(glow_color, (1.0 - phase) * p))
		else: ## a seed pod waiting to be filled
			VineStyle.ring(self, c, radius, Color(rim, (0.5 if hovered else 0.3) * p), 0.5)
			draw_rect(Rect2(c.x - 1, c.y - 1, 3, 3), Color(VineStyle.BARK_VOID if taken > 0.4 else VineStyle.BARK, p))
			draw_rect(Rect2(c.x, c.y - 1, 1, 1), Color(VineStyle.BARK_LIGHT, p))
	elif sealed: ## a talisman place that has not woken yet: a sealed bud and the level that opens it
		var need: int = LevelRewards.talisman_level(String(slot.ref).trim_prefix("talisman_").to_int())
		VineStyle.ring(self, c, radius, Color(rim, 0.5 * p), 0.4)
		for petal: Vector2 in [Vector2(-2, 1), Vector2(2, 1), Vector2(0, -2)]: ## closed petals round a dark heart
			draw_rect(Rect2(c + petal - Vector2(1, 2), Vector2(3, 5)), Color(VineStyle.OUTLINE, 0.95 * p))
			draw_rect(Rect2(c + petal - Vector2(0, 1), Vector2(1, 3)), Color(VineStyle.BARK_VOID_LIGHT.lerp(VineStyle.BARK_LIGHT, 0.4 - taken * 0.4), p))
		draw_rect(Rect2(c.x, c.y, 1, 1), Color(VineStyle.VOID_GLOW, (0.5 + 0.4 * sin(_time * 1.8 + i)) * p))
		var seal: String = "LV %d" % need
		PixelText.draw(self, seal, Vector2i(roundi(c.x) - PixelText.width(seal) / 2, roundi(c.y) + radius + 4), Color(UiStyle.TEXT_DIM, 0.85 * p), Color(VineStyle.OUTLINE, p))
	else: ## equipment: a setting in the colour of what it holds, a pictogram of what belongs there while empty
		var tone: Color = glow_color
		if group == "charm" and has_item: ## a worn talisman's setting takes the colour of its kind (body / void / attack)
			var kind_info: Dictionary = (TalismanRules.catalog().get("types", {}) as Dictionary).get(TalismanRules.type_of(stack), {}) as Dictionary
			tone = Color(String(kind_info.get("color", "ffffff"))).lerp(VineStyle.VOID_GLOW, taken * 0.3)
		VineStyle.ring(self, c, radius, Color(tone, (0.95 if has_item else 0.45) * p), 1.0 if has_item else 0.5 + 0.2 * sin(_time * 2.0 + i))
		if group == "charm": ## a jewel setting: four claws and the eye the thread runs through
			for claw: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var at: Vector2 = c + claw * (radius - 3.0)
				draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 3)), Color(VineStyle.OUTLINE, p))
				draw_rect(Rect2(at, Vector2.ONE), Color(tone if has_item else rim, (1.0 if has_item else 0.7) * p))
			draw_rect(Rect2(c.x - 1, c.y - radius - 2, 3, 3), Color(VineStyle.OUTLINE, p))
			draw_rect(Rect2(c.x, c.y - radius - 1, 1, 1), Color(tone if has_item else rim, p))
		elif group == "hand": ## what she holds: a second, slowly turning ring
			for k: int in 8:
				var angle: float = _time * 0.35 + k * TAU / 8.0
				draw_rect(Rect2(roundf(c.x + cos(angle) * (radius + 3.0)), roundf(c.y + sin(angle) * (radius + 3.0)), 1, 1), Color(tone, (0.75 if has_item else 0.3) * p))
		if has_item:
			for k: int in 3:
				var angle: float = _time * 1.4 + k * TAU / 3.0
				draw_rect(Rect2(roundf(c.x + cos(angle) * (radius + 1.0)), roundf(c.y + sin(angle) * (radius + 1.0)), 1, 1), Color(VineStyle.PETAL, p))
		else:
			var info: Dictionary = DataRegistry.get_entry("equipment_slots", String(slot.ref))
			if not _draw_missing_jewellery(String(slot.ref), c, p):
				_draw_glyph(info.get("glyph", []) as Array, c, Color(rim.lightened(0.15), (0.95 if hovered else 0.65) * p))
			if hovered and _refuse_t <= 0.0: ## its name while the pointer is on it
				var title: String = String(info.get("name", "")).to_upper()
				PixelText.draw(self, title, Vector2i(roundi(c.x) - PixelText.width(title) / 2, roundi(c.y) + radius + 4), Color(UiStyle.TEXT, p), Color(VineStyle.OUTLINE, p))

	if not held.is_empty() and _inventory.can_place(slot.kind, slot.ref): ## the stack on the cursor: a ring where it would land
		VineStyle.ring(self, c, radius - 2, Color(UiStyle.ACCENT, (0.5 + 0.4 * sin(_time * 8.0)) * p), 1.0)
	if slot == _refuse_slot and _refuse_t > 0.0: ## "no": a red ring and the reason under the slot
		var fade: float = clampf(_refuse_t / 0.5, 0.0, 1.0)
		VineStyle.ring(self, c, radius, Color("ff5a6a", 0.8 * fade * p), 1.0)
		PixelText.draw(self, _refuse_text, Vector2i(roundi(c.x) - PixelText.width(_refuse_text) / 2, roundi(c.y) + radius + 4), Color("ff8a96", fade * p), UiStyle.OUTLINE)


## A pictogram from rows of "#" and ".", centred on `c` (or starting at x `left`).
func _draw_glyph(rows: Array, c: Vector2, colour: Color, left: float = NAN) -> void:
	if rows.is_empty():
		return
	var origin: Vector2 = Vector2(roundf(c.x - String(rows[0]).length() / 2.0) if is_nan(left) else left, roundf(c.y - rows.size() / 2.0))
	for y: int in rows.size():
		var line: String = String(rows[y])
		for x: int in line.length():
			if line[x] == "#":
				draw_rect(Rect2(origin + Vector2(x, y), Vector2.ONE), colour)


## An empty talisman slot shows the kinds of jewellery that are not worn yet (small pictograms in their colours), so one sees what is missing. False for any
## other slot, or when every kind is worn.
func _draw_missing_jewellery(slot_name: String, c: Vector2, p: float) -> bool:
	if not slot_name.begins_with(TalismanRules.SLOT_PREFIX):
		return false
	var types: Dictionary = TalismanRules.catalog().get("types", {}) as Dictionary
	var missing: Array[String] = []
	for type: String in types:
		var worn: bool = false
		for other: String in _inventory.equipment:
			if TalismanRules.type_of(_inventory.equipment[other] as Dictionary) == type:
				worn = true
		if not worn:
			missing.append(type)
	if missing.is_empty():
		return false
	var span: int = missing.size() * 6 - 1
	for k: int in missing.size():
		var info: Dictionary = types[missing[k]] as Dictionary
		_draw_glyph(info.get("glyph", []) as Array, c, Color(String(info.get("color", "ffffff")), 0.8 * p), roundf(c.x - span / 2.0) + k * 6)
	return true


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
	var replaces: Dictionary = {}
	if slot.kind == "inv" and TalismanRules.is_talisman(item): ## jewellery of the same kind that is worn would be replaced
		var same: String = TalismanRules.conflict(_inventory.equipment, "", item)
		if same != "":
			replaces = _inventory.equipment[same] as Dictionary
	_tooltip.show_stack(item, equippable, replaces)
	_tooltip.show()
	_tooltip.move_to_front()
