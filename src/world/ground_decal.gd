class_name GroundDecal
extends Sprite2D
## A hand-authored patch of ground (old flagstones, the footpath) lying on the meadow, baked by tools/bake_ground.py from
## data/ground.json: a picture and a mask picture of the same size (R: 60 stone, 80 path). It paints its own surface, so
## footsteps and speed follow what you see (`Terrain.patches`). Added by `WorldLevel._add_ground_decals`.

const SURFACES: Dictionary = {60: "stone", 80: "path"} ## mask value -> surface (data/terrain.json)

var _mask: Image
var _mask_bytes: PackedByteArray = PackedByteArray()
var _mask_width: int = 0
var _mask_height: int = 0


func setup(texture_path: String, mask_path: String, top_left: Vector2) -> void:
	texture = load(texture_path) as Texture2D
	_mask = (load(mask_path) as Texture2D).get_image()
	_mask.convert(Image.FORMAT_R8)
	_mask_bytes = _mask.get_data()
	_mask_width = _mask.get_width()
	_mask_height = _mask.get_height()
	centered = false
	position = top_left
	z_index = -9
	Terrain.patches.append(self)
	tree_exiting.connect(func() -> void: Terrain.patches.erase(self))


## The surface under a world position: "" off the decal or where it has nothing.
func surface_at(world_pos: Vector2) -> String:
	var local: Vector2 = world_pos - position
	var x: int = int(floorf(local.x))
	var y: int = int(floorf(local.y))
	if x < 0 or y < 0 or x >= _mask_width or y >= _mask_height:
		return ""
	var val: int = _mask_bytes[y * _mask_width + x]
	return String(SURFACES.get(val, ""))
