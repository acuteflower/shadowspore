class_name HitScan
extends RefCounted
## Shape queries for melee attacks (host only). Finds hurtboxes, never bodies.


## Every hurtbox on `mask` touching a circle.
static func circle(from: Node2D, center: Vector2, radius: float, mask: int) -> Array[HurtboxComponent]:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var found: Array[HurtboxComponent] = []
	for hit: Dictionary in from.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var target: HurtboxComponent = hit["collider"] as HurtboxComponent
		if target != null and not found.has(target):
			found.append(target)
	return found


## Every hurtbox on `mask` inside a fan: apex at `origin`, pointing along `dir`, `reach` long, `arc` radians wide.
static func fan(from: Node2D, origin: Vector2, dir: Vector2, reach: float, arc: float, mask: int) -> Array[HurtboxComponent]:
	var points: PackedVector2Array = [Vector2.ZERO]
	for i: int in 7:
		points.append(Vector2.RIGHT.rotated(lerpf(-arc / 2.0, arc / 2.0, i / 6.0)) * reach)
	var shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
	shape.points = points
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(dir.angle(), origin)
	query.collision_mask = mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var found: Array[HurtboxComponent] = []
	for hit: Dictionary in from.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var target: HurtboxComponent = hit["collider"] as HurtboxComponent
		if target != null and not found.has(target):
			found.append(target)
	return found
