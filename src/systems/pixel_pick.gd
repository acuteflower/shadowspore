class_name PixelPick
extends RefCounted
## Whether a point of the world lies on a painted pixel of a node's sprites. The cursor asks it about
## pickable things (blossoms, pebbles) and animals, so what answers is what is drawn, not a guessed
## radius. Only the node's own Sprite2D children count, and only the frame they show right now.
## Pictures are read once per texture and kept.

const PAINTED: float = 0.5 ## alpha from which a pixel counts as painted

static var _images: Dictionary = {} ## texture path (or instance id) -> Image


## True when the world point `at` lies on a painted pixel of one of `node`'s visible Sprite2D children.
static func hit(node: Node2D, at: Vector2) -> bool:
	for child: Node in node.get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite != null and sprite.is_visible_in_tree() and sprite.texture != null and _painted(sprite, at):
			return true
	return false


static func _painted(sprite: Sprite2D, at: Vector2) -> bool:
	var source: Texture2D = sprite.texture
	var origin: Vector2 = Vector2.ZERO ## top left of the drawn picture inside its source image
	var size: Vector2 = source.get_size()
	var atlas: AtlasTexture = source as AtlasTexture
	if atlas != null and atlas.atlas != null:
		source = atlas.atlas
		origin = atlas.region.position
		size = atlas.region.size
	var columns: int = maxi(sprite.hframes, 1)
	var rows: int = maxi(sprite.vframes, 1)
	var cell: Vector2 = size / Vector2(float(columns), float(rows))
	var local: Vector2 = sprite.to_local(at) - sprite.offset
	if sprite.centered:
		local += cell * 0.5
	if local.x < 0.0 or local.y < 0.0 or local.x >= cell.x or local.y >= cell.y:
		return false
	var frame: int = clampi(sprite.frame, 0, columns * rows - 1)
	var col: int = frame % columns
	var row: int = floori(float(frame) / float(columns))
	var px: Vector2i = Vector2i(floori(origin.x + float(col) * cell.x + local.x), floori(origin.y + float(row) * cell.y + local.y))
	var image: Image = _image_of(source)
	if image == null or px.x < 0 or px.y < 0 or px.x >= image.get_width() or px.y >= image.get_height():
		return false
	return image.get_pixel(px.x, px.y).a >= PAINTED


static func _image_of(source: Texture2D) -> Image:
	var key: String = source.resource_path if source.resource_path != "" else str(source.get_instance_id())
	if not _images.has(key):
		_images[key] = source.get_image()
	return _images[key] as Image
