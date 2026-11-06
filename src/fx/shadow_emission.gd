class_name ShadowEmission
extends RefCounted
## Shared shadow-creature emission. Keep only exact eye/vein palette pixels, so black flesh and
## outlines still receive world lighting. Cached once per sheet; the child follows its body's rig.

const SHADER: Shader = preload("res://assets/shaders/shadow_emission.gdshader")
const COLORS: Array[String] = ["ff4fd8", "ffe3fb", "8a4dff", "5c2fb8", "ecd2ff"]
static var _masks: Dictionary = {}


static func attach(body: Sprite2D) -> Sprite2D:
	var emission: Sprite2D = Sprite2D.new()
	emission.name = "Emission"
	emission.texture = mask_for(body.texture)
	emission.hframes = body.hframes
	emission.vframes = body.vframes
	emission.offset = body.offset
	emission.centered = body.centered
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	emission.material = material
	body.add_child(emission)
	return emission


static func mask_for(texture: Texture2D) -> Texture2D:
	var key: int = texture.get_instance_id()
	if _masks.has(key):
		return _masks[key] as Texture2D
	var image: Image = texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.0 or not COLORS.has(pixel.to_html(false)):
				image.set_pixel(x, y, Color.TRANSPARENT)
	var mask: ImageTexture = ImageTexture.create_from_image(image)
	_masks[key] = mask
	return mask
