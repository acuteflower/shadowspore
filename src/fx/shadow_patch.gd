class_name ShadowPatch
extends Node2D
## A patch of creeping shadow on the ground (see shadow_patch.gdshader). It grows, writhes for a
## few seconds, then slowly crumbles away. Drawn on the GPU, so many patches stay cheap.

const SHADER: Shader = preload("res://assets/shaders/shadow_patch.gdshader")
const GROUND_Z: int = -9 ## above the ground, below all entities

static var _white: ImageTexture

var _size: Vector2i = Vector2i(14, 10)
var _life: float = 3.0
var _fade: float = 2.5
var _arms: int = 4
var _age: float = 0.0
var _material: ShaderMaterial


## `size` in pixels (keep it even), `life` seconds before the dissolve starts, `fade` how long
## the dissolve takes, `arms` how many tendrils (max 10).
static func spawn(world: Node, pos: Vector2, size: Vector2i, life: float, fade: float, arms: int = 4) -> void:
	var patch: ShadowPatch = ShadowPatch.new()
	patch._size = size
	patch._life = life
	patch._fade = fade
	patch._arms = arms
	patch.z_index = -4 if MineManager.in_mine(pos) else GROUND_Z ## in the mine the ground is painted at z -6
	world.add_child(patch)
	patch.global_position = pos.round()


func _ready() -> void:
	if _white == null:
		var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(image)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("size", Vector2(_size))
	_material.set_shader_parameter("seed", randf())
	_material.set_shader_parameter("life", _life)
	_material.set_shader_parameter("fade", _fade)
	_material.set_shader_parameter("arms", _arms)
	material = _material


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life + _fade:
		queue_free()
		return
	_material.set_shader_parameter("age", _age)


func _draw() -> void:
	draw_texture_rect(_white, Rect2(-_size.x / 2.0, -_size.y / 2.0, _size.x, _size.y), false)
