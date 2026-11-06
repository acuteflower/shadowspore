class_name DialogueArt
extends RefCounted
## Shared portrait contract. See docs/dialogue_art.md for framing and art direction.
const LOGICAL_SIZE: Vector2i = Vector2i(103,153)
const PIXEL_SCALE: int = 2
const DISPLAY_SIZE: Vector2 = Vector2(LOGICAL_SIZE) * PIXEL_SCALE
const BOTTOM_OVERHANG: float = 14.0

static func valid_portrait(texture: Texture2D) -> bool:
	return texture != null and Vector2i(texture.get_size()) == LOGICAL_SIZE
