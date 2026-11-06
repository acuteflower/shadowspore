class_name FallenLog
extends Node2D
## Baked 3/4-view trunk; no collecting. Ground footprint and Y anchor follow its
## rendered facing. Perches expose the real top of the log to existing birds.
const TEXTURE: Texture2D = preload("res://assets/props/fallen_logs.png")
const GLOW: Texture2D = preload("res://assets/props/fallen_logs_glow.png")
var frame: int = 0
var _spec: Dictionary
var perch_point: Vector2
var perch_height: float = 9.0

func setup(at: Vector2, index: int) -> void:
	position = at
	frame = index
	_spec = (DataRegistry.table("fallen_logs").frames as Array)[index]

func _ready() -> void:
	add_to_group("fallen_logs")
	if _spec.is_empty():
		return
	var anchor: Array = _spec.anchor
	var a: Vector2 = Vector2(float(_spec.a[0]),float(_spec.a[1]))
	var b: Vector2 = Vector2(float(_spec.b[0]),float(_spec.b[1]))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.hframes = 8
	sprite.vframes = 3
	sprite.frame = frame
	sprite.centered = false
	sprite.position = -Vector2(float(anchor[0]),float(anchor[1]))
	add_child(sprite)
	var emission: Sprite2D = Sprite2D.new()
	emission.texture = GLOW
	emission.hframes = 8
	emission.vframes = 3
	emission.frame = frame
	emission.centered = false
	emission.material = Unlit.material()
	emission.modulate.a = 0.45
	sprite.add_child(emission)
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = float(_spec.radius)
	capsule.height = a.distance_to(b)+capsule.radius*2
	shape.shape = capsule
	shape.position = (a+b)*0.5
	shape.rotation = (b-a).angle()+PI*0.5
	body.add_child(shape)
	add_child(body)
	perch_point = global_position+(a+b)*0.5
	queue_redraw()

func is_depleted() -> bool:
	return false

func _draw() -> void:
	if _spec.is_empty(): return
	var a: Vector2 = Vector2(float(_spec.a[0]),float(_spec.a[1]))
	var b: Vector2 = Vector2(float(_spec.b[0]),float(_spec.b[1]))
	draw_line(a,b,Color(0.025,0.018,0.04,0.25),10.0)
