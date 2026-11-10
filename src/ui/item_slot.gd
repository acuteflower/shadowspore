class_name ItemSlot
extends Control
## One inventory or equipment cell. Draws the item with a rarity-colored ring; clicks go to the inventory
## (the cursor stack model: take, put down, half, one, shift-click, number keys, see InventoryWindow).

signal hovered(slot: ItemSlot)
signal unhovered
signal refused(text: String) ## a piece of jewellery of a kind that is worn already was meant for this equipment slot

const SIZE: int = 20 ## outline + rarity ring + 16px icon

var kind: String = "inv" ## "inv" (ref = index) or "equip" (ref = slot name)
var ref: Variant = 0
var inventory: InventoryComponent
var selected: bool = false
var bare: bool = false ## no frame: only the icon and count (the hotbar draws its own setting)
var hint: String = "" ## dim text shown while empty (slot name or hotbar number)
var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_entered.connect(func() -> void: hovered.emit(self))
	mouse_exited.connect(func() -> void: unhovered.emit())


func stack() -> Dictionary:
	return inventory.stack_at(kind, ref)


func _draw() -> void:
	var item: Dictionary = stack()
	if not bare:
		draw_rect(Rect2(0, 0, SIZE, SIZE), UiStyle.OUTLINE)
		draw_rect(Rect2(1, 1, SIZE - 2, SIZE - 2), UiStyle.RIM if item.is_empty() else Items.rarity_color(item))
		draw_rect(Rect2(2, 2, SIZE - 4, SIZE - 4), UiStyle.SLOT_BG)
		if selected:
			draw_rect(Rect2(0, 0, SIZE, SIZE), UiStyle.ACCENT, false)
	if item.is_empty():
		if hint != "":
			PixelText.draw(self, hint, Vector2i((SIZE - PixelText.width(hint)) / 2, (SIZE - PixelText.HEIGHT) / 2 + 1), UiStyle.TEXT_DIM)
		return
	var icon: Texture2D = Items.icon(item)
	if icon:
		draw_texture(icon, Vector2(2, 2))
	RefineStyle.draw_badge(self, Items.refine(item), SIZE - 2, SIZE - 2) ## "+7" of a refined weapon
	var count: int = int(item.get("count", 1))
	if count > 1:
		var label: String = str(count)
		PixelText.draw(self, label, Vector2i(SIZE - 2 - PixelText.width(label), SIZE - 9), UiStyle.TEXT, UiStyle.OUTLINE)


## Clicks while the inventory is open (the host decides what they do, see InventoryComponent.request):
## LMB takes a stack / puts the stack on the cursor down, SHIFT+LMB moves it at once, RMB takes half (or puts ONE down).
func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or inventory == null or not InputManager.inventory_open:
		return
	var carrying: bool = not inventory.held.is_empty()
	var sound: String = "equip" if kind == "equip" else ("item_put" if carrying else "item_take")
	var has_sound: bool = carrying or not stack().is_empty() ## nothing happens on an empty slot with an empty cursor
	if click.button_index == MOUSE_BUTTON_LEFT:
		if kind == "equip" and not inventory.held.is_empty():
			var why: String = inventory.refusal(String(ref), inventory.held)
			if why != "":
				refused.emit(why)
				accept_event()
				return
		inventory.request("quick" if click.shift_pressed else "click", [kind, ref])
		if has_sound:
			Sfx.ui(self, sound, -2.0)
		accept_event()
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		inventory.request("rclick", [kind, ref])
		if has_sound:
			Sfx.ui(self, sound, -2.0)
		accept_event()
