class_name WitchCloneHurtbox
extends HurtboxComponent
## The hurtbox of one of Morwenna's glitch clones (a child of its `WitchBody`): weapon hit scans find it like any enemy, but a clone has no health:
## a blade going through it makes it crumble into mist on the host (`MirrorWitchFight.clone_struck`), and it forms again a few seconds later.
## Open only while the clone stands formed (`set_open`, set every frame by the fight).

const LAYER: int = 1 << 4

var fight: MirrorWitchFight
var index: int = 1
var _open: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = 0
	collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 13.0
	shape.shape = circle
	shape.position = Vector2(0, -14)
	add_child(shape)


func set_open(on: bool) -> void:
	if on == _open:
		return
	_open = on
	set_deferred("collision_layer", LAYER if on else 0)


func take_hit(_damage: float, from: Vector2, _knockback: float, _source: int = 0) -> void:
	if fight != null and multiplayer.is_server():
		fight.clone_struck(index, from)
