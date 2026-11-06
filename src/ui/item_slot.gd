class_name ItemSlot
extends Control
## One inventory or equipment cell. Draws the item with a rarity-colored ring, supports
## drag & drop, and right-click / double-click to equip or unequip.

signal hovered(slot: ItemSlot)
signal unhovered

const SIZE: int = 20 ## outline + rarity ring + 16px icon

var kind: String = "inv" ## "inv" (ref = index) or "equip" (ref = slot name)
var ref: Variant = 0
var inventory: InventoryComponent
var selected: bool = false
var bare: bool = false ## no frame: only the icon and count (the hotbar draws its own setting)
var hint: String = "" ## dim text shown while empty (slot name or hotbar number)


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
	var count: int = int(item.get("count", 1))
	if count > 1:
		var label: String = str(count)
		PixelText.draw(self, label, Vector2i(SIZE - 2 - PixelText.width(label), SIZE - 9), UiStyle.TEXT, UiStyle.OUTLINE)


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT or (click.button_index == MOUSE_BUTTON_LEFT and click.double_click):
		if kind == "inv":
			inventory.request("equip", [ref, ""])
		else:
			inventory.request("unequip", [ref, -1])


func _get_drag_data(_at: Vector2) -> Variant:
	var item: Dictionary = stack()
	if item.is_empty():
		return null
	var preview: TextureRect = TextureRect.new()
	preview.texture = Items.icon(item)
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"kind": kind, "ref": ref}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("kind") and data.has("ref") and inventory != null and inventory.can_drop(data["kind"], data["ref"], kind, ref)


func _drop_data(_at: Vector2, data: Variant) -> void:
	inventory.drop(data["kind"], data["ref"], kind, ref)
