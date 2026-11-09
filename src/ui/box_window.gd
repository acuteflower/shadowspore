class_name BoxWindow
extends CanvasLayer
## A container (`ItemBox`: the town's stock, later every chest) next to the player's own bag, in the vine style of the inventory. Left a bark-paper card with the box's slots, right
## one with the hotbar and the rucksack; both are real `ItemSlot`s, so everything works as in the inventory window (the cursor stack, `InventoryComponent`): LMB takes a stack /
## puts it down (tops up, swaps), RMB takes half / puts ONE down, SHIFT+LMB sends a stack to the other side at once. The host decides every move (`InventoryComponent.request`,
## kind "box"); this window only draws and sends clicks. Closing puts the cursor stack back into the bag. For a new container: `BoxWindow.open_box(tree, player, box, "TITLE")`.

const COLUMNS: int = 8
const STEP: float = 22.0 ## slot pitch (`ItemSlot.SIZE` + 2)
const PAD: float = 14.0
const HEAD: float = 44.0
const GAP: float = 14.0
const CARD_W: float = COLUMNS * STEP - 2.0 + 2.0 * PAD
const BAG_GAP: float = 30.0 ## from the hotbar row to the first rucksack row

var player: Player
var box: ItemBox
var title: String = ""

var _canvas: Control
var _overlay: Control
var _tip: ItemTooltip
var _vignette: GradientTexture2D
var _slots: Array[ItemSlot] = []
var _hover: ItemSlot
var _left: Rect2
var _right: Rect2
var _time: float = 0.0
var _open_t: float = 0.0
var _closing: bool = false
var _tick: AudioStreamPlayer


static func open_box(tree: SceneTree, for_player: Player, for_box: ItemBox, for_title: String) -> BoxWindow:
	if tree.get_first_node_in_group("board_window") != null:
		return null
	var window: BoxWindow = BoxWindow.new()
	tree.root.add_child(window)
	window.setup(for_player, for_box, for_title)
	return window


## Subclasses: the line under the title of the box card.
func _subtitle() -> String:
	return "%d VON %d PLÄTZEN BELEGT" % [_used(0, box.size()), box.size()]


func setup(for_player: Player, for_box: ItemBox, for_title: String) -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = for_player
	box = for_box
	title = for_title
	_vignette = VineStyle.make_vignette()
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)
	for i: int in box.size():
		_add_slot("box", i)
	for i: int in InventoryComponent.SIZE:
		_add_slot("inv", i)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_canvas.add_child(_overlay)
	_tip = ItemTooltip.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_tip)
	_tick = AudioStreamPlayer.new()
	_tick.stream = load("res://assets/audio/shop/tick.wav") as AudioStream
	_tick.volume_db = -9.0
	add_child(_tick)
	var open_voice: AudioStreamPlayer = AudioStreamPlayer.new()
	open_voice.stream = load("res://assets/audio/skills/open.wav") as AudioStream
	open_voice.volume_db = -14.0
	add_child(open_voice)
	open_voice.play()
	add_to_group("board_window") ## the inventory window stays shut while this one hangs on the screen
	player.story_lock = true
	InputManager.ui_blocking = true
	InputManager.inventory_open = true ## the slots take clicks
	player.inventory.open_box(box)
	player.inventory.changed.connect(_on_changed)
	_layout()


func _add_slot(kind: String, ref: int) -> void:
	var slot: ItemSlot = ItemSlot.new()
	slot.kind = kind
	slot.ref = ref
	slot.inventory = player.inventory
	slot.hovered.connect(func(s: ItemSlot) -> void: _hover = s; _show_tip(s))
	slot.unhovered.connect(func() -> void: _hover = null; _tip.hide())
	_canvas.add_child(slot)
	_slots.append(slot)


func _on_changed() -> void:
	if not _closing:
		_tick.play()
	if _hover != null and is_instance_valid(_hover):
		_show_tip(_hover)


func _show_tip(slot: ItemSlot) -> void:
	var stack: Dictionary = slot.stack()
	if stack.is_empty() or _closing:
		_tip.hide()
		return
	_tip.show_stack(stack, false)
	_tip.show()
	_tip.move_to_front()


func _used(from: int, to: int) -> int:
	var n: int = 0
	for i: int in range(from, to):
		if not (box.slots[i] as Dictionary).is_empty():
			n += 1
	return n


func _bag_used() -> int:
	var n: int = 0
	for stack: Dictionary in player.inventory.slots:
		if not stack.is_empty():
			n += 1
	return n


func _close() -> void:
	if _closing:
		return
	_closing = true
	_tip.hide()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(player):
		player.inventory.request("stow", [0]) ## whatever is on the cursor goes back into the bag
		player.inventory.close_box()
		player.inventory.changed.disconnect(_on_changed)
		player.story_lock = false
	InputManager.ui_blocking = false
	InputManager.inventory_open = false


func _exit_tree() -> void:
	if not _closing:
		if is_instance_valid(player):
			player.story_lock = false
		InputManager.ui_blocking = false
		InputManager.inventory_open = false


# ---------- layout ----------

func _layout() -> void:
	var view: Vector2 = _canvas.size
	var rows: int = ceili(float(box.size()) / COLUMNS)
	var height: float = HEAD + STEP * float(rows) + PAD - 2.0
	var x: float = roundf((view.x - (2.0 * CARD_W + GAP)) / 2.0)
	var y: float = roundf((view.y - height) / 2.0) - 6.0
	_left = Rect2(x, y, CARD_W, height)
	_right = Rect2(x + CARD_W + GAP, y, CARD_W, height)
	var fade: float = clampf(_open_t * 1.6 - 0.4, 0.0, 1.0)
	for slot: ItemSlot in _slots:
		var index: int = int(slot.ref)
		if slot.kind == "box":
			slot.position = _left.position + Vector2(PAD + float(index % COLUMNS) * STEP, HEAD + float(index / COLUMNS) * STEP)
		elif index < InventoryComponent.HOTBAR_SIZE:
			slot.position = _right.position + Vector2(PAD + float(index) * STEP, HEAD)
		else:
			var at: int = index - InventoryComponent.HOTBAR_SIZE
			slot.position = _right.position + Vector2(PAD + float(at % COLUMNS) * STEP, HEAD + BAG_GAP + float(at / COLUMNS) * STEP)
		slot.modulate.a = fade
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if fade > 0.9 and not _closing else Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	_open_t = move_toward(_open_t, 0.0 if _closing else 1.0, delta * (3.0 if _closing else 2.2))
	if _closing and _open_t <= 0.0:
		queue_free()
		return
	_layout()
	if _tip.visible:
		_tip.position = (_canvas.get_local_mouse_position() + Vector2(12, 10)).min(_canvas.size - _tip.size)
	_canvas.queue_redraw()
	_overlay.queue_redraw()


# ---------- drawing ----------

func _text(pos: Vector2, text: String, color: Color, scale: float = 1.0) -> void:
	if scale == 1.0:
		PixelText.draw(_canvas, text, Vector2i(int(pos.x), int(pos.y)), color, BoardWindow.SHADOW)
		return
	_canvas.draw_set_transform(pos, 0.0, Vector2(scale, scale))
	PixelText.draw(_canvas, text, Vector2i.ZERO, color, BoardWindow.SHADOW)
	_canvas.draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	var p: float = clampf(_open_t, 0.0, 1.0)
	var void_level: float = VineStyle.void_amount()
	var view: Vector2 = _canvas.size
	_canvas.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, view), false, Color(1, 1, 1, p))
	VineStyle.motes(_canvas, view, _time, p, void_level)
	var reach: float = clampf((_open_t - 0.1) / 0.6, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return _left.position.y - 22.0 + 2.0 * sin((view.x - x) * 0.05) ## the branch from the right edge, the cards hang from it
	for x: float in [_left.position.x + 26.0, _left.end.x - 26.0, _right.position.x + 26.0, _right.end.x - 26.0]:
		_canvas.draw_line(Vector2(x, float(course.call(x)) + 2.0), Vector2(x, _left.position.y + 3.0), Color(VineStyle.BARK_LIGHT, p), 1.0)
	VineStyle.paper(_canvas, _left, minf(p * 1.6, 1.0), void_level, 71)
	VineStyle.paper(_canvas, _right, minf(p * 1.6, 1.0), void_level, 83)
	VineStyle.branch(_canvas, view.x, _left.position.x - 4.0, course, 6, void_level, 40.0, _time, reach)
	VineStyle.foliage(_canvas, view.x, _left.position.x - 4.0, course, 18, 330, void_level, 40.0, _time, reach)
	if p < 0.5:
		return
	_text(_left.position + Vector2(PAD, 10), title, BoardWindow.GOLD, 2.0)
	_text(_left.position + Vector2(PAD, 28), _subtitle(), BoardWindow.DIM)
	_text(_right.position + Vector2(PAD, 10), "RUCKSACK", BoardWindow.GOLD, 2.0)
	_text(_right.position + Vector2(PAD, 28), "%d VON %d PLÄTZEN BELEGT" % [_bag_used(), InventoryComponent.SIZE], BoardWindow.DIM)
	_canvas.draw_rect(Rect2(_right.position + Vector2(PAD, HEAD + BAG_GAP - 6.0), Vector2(CARD_W - 2.0 * PAD, 1.0)), Color(VineStyle.BARK_LIGHT, 0.7))
	var hints: Array[String] = [
		"LMT: NEHMEN / ABLEGEN    RMT: HÄLFTE / EINES    UMSCH+LMT: AUF DIE ANDERE SEITE",
		"ESC ODER TAB: SCHLIESSEN",
	]
	for line: int in hints.size():
		_text(Vector2(roundf(view.x / 2.0) - float(PixelText.width(hints[line])) / 2.0, _left.end.y + 14.0 + 9.0 * float(line)), hints[line], Color(BoardWindow.DIM, 0.8))


func _draw_overlay() -> void:
	if _open_t < 0.6:
		return
	var holding: bool = not player.inventory.held.is_empty()
	for slot: ItemSlot in _slots:
		var rect: Rect2 = Rect2(slot.position, Vector2(ItemSlot.SIZE, ItemSlot.SIZE))
		if holding and player.inventory.can_place(slot.kind, slot.ref):
			_overlay.draw_rect(rect, Color(UiStyle.ACCENT, 0.35 + 0.25 * sin(_time * 8.0)), false)
		if slot == _hover:
			_overlay.draw_rect(rect.grow(1.0), Color(BoardWindow.LIT, 0.8), false)
	if holding: ## the stack on the cursor
		var held: Dictionary = player.inventory.held
		var at: Vector2 = _overlay.get_local_mouse_position().round() + Vector2(6, 6)
		VineStyle.glow(_overlay, at, 13.0, Items.rarity_color(held), 0.45)
		var icon: Texture2D = Items.icon(held)
		if icon != null:
			_overlay.draw_texture(icon, at - Vector2(8, 8))
		var count: int = int(held.get("count", 1))
		if count > 1:
			var label: String = str(count)
			PixelText.draw(_overlay, label, Vector2i(int(at.x) + 8 - PixelText.width(label), int(at.y) + 1), UiStyle.TEXT, UiStyle.OUTLINE)


# ---------- input ----------

func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel") or (event.is_action_pressed("inventory") and not event.is_echo()):
		_close()
		get_viewport().set_input_as_handled()


## A click beside both cards leaves (slots take their own clicks).
func _on_gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if _closing or click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if player.inventory.held.is_empty() and not _left.grow(8.0).has_point(click.position) and not _right.grow(8.0).has_point(click.position):
		_close()
