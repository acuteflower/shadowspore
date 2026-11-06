class_name Items
extends RefCounted
## Helpers for item stacks. A stack is {"id": String, "count": int} (more keys later, e.g.
## enchantments); an empty slot is {}. Definitions live in data/items.json.


## Icons are cached because `draw_texture` does not keep its texture alive.
static var _icons: Dictionary = {}


static func icon(stack: Dictionary) -> Texture2D:
	var path: String = String(definition(stack).get("icon", ""))
	if path != "" and not _icons.has(path):
		_icons[path] = load(path)
	return _icons.get(path) as Texture2D


static func definition(stack: Dictionary) -> Dictionary:
	return DataRegistry.get_entry("items", String(stack.get("id", "")))


static func max_stack(stack: Dictionary) -> int:
	return int(definition(stack).get("max_stack", 1))


static func rarity_color(stack: Dictionary) -> Color:
	var rarity: Dictionary = DataRegistry.get_entry("rarities", String(definition(stack).get("rarity", "common")))
	return Color(String(rarity.get("color", "#b8b8c8")))


static func fits_slot(slot_name: String, stack: Dictionary) -> bool:
	if stack.is_empty():
		return false
	var accepts: String = String(DataRegistry.get_entry("equipment_slots", slot_name).get("accepts", ""))
	return accepts != "" and String(definition(stack).get("slot", "")) == accepts


## Weapons and gear are equipped, never carried in the hotbar; tools and consumables are.
static func hotbar_ok(stack: Dictionary) -> bool:
	return stack.is_empty() or bool(definition(stack).get("hotbar", false))
