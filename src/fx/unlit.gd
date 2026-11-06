class_name Unlit
extends RefCounted
## Shared material for things that must not take on the night tint: texts, bars, warnings, loot.

static var _material: CanvasItemMaterial


static func material() -> CanvasItemMaterial:
	if _material == null:
		_material = CanvasItemMaterial.new()
		_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _material
