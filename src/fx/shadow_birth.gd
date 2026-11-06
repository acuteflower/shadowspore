class_name ShadowBirth
extends Node2D
## Reusable land emergence mouth. Ground-only screen refraction, torn ink veins,
## inward filaments and crawling fragments. Driven by game time, including slow motion.
const DURATION: float = 3.2
const LIFE: float = 4.6
const SHADER: Shader = preload("res://assets/shaders/shadow_birth.gdshader")
var age: float = 0.0
var _shader: ShaderMaterial
var _seed: float = 0.0

func _ready() -> void:
	var ground_position: Vector2 = global_position
	top_level = true
	global_position = ground_position
	z_index = -7
	_seed = randf() * 1000.0
	_shader = ShaderMaterial.new()
	_shader.shader = SHADER
	_shader.set_shader_parameter("seed",_seed)
	# Full-size even quad keeps Godot's pixel snapping from shifting a scaled 1px sprite.
	var image: Image = Image.create(128,96,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var patch: Sprite2D = Sprite2D.new()
	patch.texture = ImageTexture.create_from_image(image)
	patch.material = _shader
	add_child(patch)
	material = Unlit.material()

func _process(delta: float) -> void:
	age += delta
	_shader.set_shader_parameter("age",age)
	if age >= LIFE:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var grow: float = smoothstep(0.1,1.0,age) * (1.0-smoothstep(2.4,3.8,age))
	for i: int in 11:
		var scatter: float = fposmod(sin(i*17.13+_seed)*43758.54,1.0)
		var angle: float = scatter * TAU
		var travel: float = fposmod(age * (0.35+scatter*0.4) + scatter,1.0)
		var at: Vector2 = Vector2(cos(angle)*(18+scatter*26),sin(angle)*(9+scatter*15)) * (1.15-travel*0.8)
		at.y -= sin(travel*PI)*6.0
		var width: float = 1.0 + float(i%2)
		draw_rect(Rect2(at.round(),Vector2(width,2+sin(travel*PI)*3)),Color(0.22,0.10,0.34,grow*sin(travel*PI)*0.8))
