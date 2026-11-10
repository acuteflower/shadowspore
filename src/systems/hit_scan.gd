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


## Every hurtbox on `mask` inside a lane: from `origin` along `dir`, `length` long and `half_width` to either side.
static func lane(from: Node2D, origin: Vector2, dir: Vector2, length: float, half_width: float, mask: int) -> Array[HurtboxComponent]:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(length, half_width * 2.0)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(dir.angle(), origin + dir.normalized() * length * 0.5)
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
	if arc > PI - 0.01:
		# A fan wider than a half circle is concave and a convex shape cannot hold it:
		# two fans side by side cover the same area.
		var found_wide: Array[HurtboxComponent] = []
		for half: float in [-1.0, 1.0]:
			var part_dir: Vector2 = dir.rotated(half * arc / 4.0)
			for target: HurtboxComponent in fan(from, origin, part_dir, reach, minf(arc / 2.0 + 0.02, PI - 0.02), mask):
				if not found_wide.has(target):
					found_wide.append(target)
		return found_wide
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
