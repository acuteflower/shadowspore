extends Node
## Offline integration checks, no save access or listening socket:
## Godot --headless --path . tools/test_void_predator.tscn

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var level: Node2D = Node2D.new()
	var enemies: Node2D = Node2D.new()
	enemies.name = "Enemies"
	level.add_child(enemies)
	var actor: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	actor.name = "2"
	level.add_child(actor)
	add_child(level)
	await get_tree().physics_frame
	var player: Player = get_tree().get_first_node_in_group("players") as Player
	player.set_physics_process(false)
	player.position = Vector2(26, 0)
	await get_tree().physics_frame
	player.health.invulnerable_seconds = 0.0
	var spider: ShadowSpider = load("res://src/entities/enemies/shadow_spider.tscn").instantiate() as ShadowSpider
	level.get_node("Enemies").add_child(spider)
	spider.set_physics_process(false)
	spider.set_process(false)
	spider._target = player
	await get_tree().physics_frame
	_check(spider._health.max_health == 48.0, "Enemy balance did not load")

	spider._set_state(ShadowSpider.State.WINDUP)
	spider._health.take_damage(5.0, player.position, 40.0)
	_check(spider.state == ShadowSpider.State.WINDUP, "Light hit cancelled a committed attack")
	spider._health.take_damage(8.0, player.position, 80.0)
	_check(spider.state == ShadowSpider.State.HURT, "Heavy finisher did not stagger")
	_check(spider.velocity.length() <= 36.1, "Knockback resistance not applied")

	spider.position = Vector2.ZERO
	spider._set_state(ShadowSpider.State.WINDUP)
	spider._state_time = 0.29
	spider._windup()
	var locked: Vector2 = spider.attack_dir
	player.position = Vector2(0, 26)
	spider._state_time = 0.4
	spider._windup()
	_check(spider.attack_dir.is_equal_approx(locked), "Attack retargeted after the lock")

	player.position = Vector2(26, 0)
	await get_tree().physics_frame
	spider._set_state(ShadowSpider.State.WINDUP)
	spider._set_state(ShadowSpider.State.STRIKE)
	var before: float = player.health.current
	spider._state_time = 0.03
	spider._strike()
	_check(player.health.current == before, "Melee hit before the limb extended")
	spider._state_time = 0.14
	spider._strike()
	_check(player.health.current == before - 14.0, "Melee sweep missed the announced sector")
	spider._state_time = 0.2
	spider._strike()
	_check(player.health.current == before - 14.0, "Melee hit twice in one sweep")

	player.position = Vector2(-26, 0)
	await get_tree().physics_frame
	spider._set_state(ShadowSpider.State.STRIKE)
	spider._state_time = 0.15
	before = player.health.current
	spider._strike()
	_check(player.health.current == before, "Melee hit behind its warning sector")

	# A solid obstacle prevents both melee and the ranged endpoint from hurting through it.
	var wall: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(4, 60)
	shape.shape = box
	wall.position = Vector2(14, 0)
	wall.add_child(shape)
	level.add_child(wall)
	await get_tree().physics_frame
	player.position = Vector2(26, 0)
	await get_tree().physics_frame
	spider.attack_dir = Vector2.RIGHT
	spider._set_state(ShadowSpider.State.STRIKE)
	spider._state_time = 0.15
	before = player.health.current
	spider._strike()
	_check(player.health.current == before, "Melee hit through a world wall")
	spider.anchor = player.position
	spider._grapple_hit()
	_check(player.health.current == before, "Grapple hit through a world wall")
	_check(not spider._clear_path(Vector2.ZERO, player.position), "World feeler did not detect wall")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	spider.anchor = Vector2(80, 0)
	player.position = Vector2(80, 28)
	await get_tree().physics_frame
	spider._grapple_hit()
	_check(player.health.current == before, "Grapple damaged a player outside its landing disc")
	player.position = Vector2(80, 0)
	await get_tree().physics_frame
	spider._grapple_hit()
	_check(player.health.current == before - 17.0, "Grapple endpoint did not deal 17 damage")
	spider._set_state(ShadowSpider.State.GRAPPLE_PULL)
	spider._set_state(ShadowSpider.State.RECOVER)
	_check(spider._recover_time() >= 0.8, "Grapple has no safe recovery window")

	# All eight directions, both slash sides: visible tip covers the same full sector as combat.
	var rig: SpiderRig = spider._rig
	rig.set_process(false)
	for sector: int in 8:
		var direction: Vector2 = Vector2.from_angle(sector * PI / 4.0)
		for side: float in [-1.0, 1.0]:
			rig.attack_side = side
			rig.set_aim(direction)
			rig.start_pose(SpiderRig.Pose.LOCOMOTION, 1.0)
			rig.update_rig(0.01, Vector2.ZERO, direction.angle())
			rig.start_pose(SpiderRig.Pose.WINDUP, 0.58)
			rig.update_rig(0.58, Vector2.ZERO, direction.angle())
			rig.start_pose(SpiderRig.Pose.STRIKE, 0.24)
			rig.update_rig(0.14, Vector2.ZERO, direction.angle())
			for leg: SpiderRig.Leg in rig._legs:
				_check(leg.points[-1].distance_to(leg.foot + Vector2(0, -leg.height)) < 0.01, "Curve endpoint slipped off its ground contact")
				for point: Vector2 in leg.points:
					if not point.is_finite():
						_check(false, "Non-finite limb curve")
				if leg.grabber and leg.side == side:
					var expected: Vector2 = spider.position + Vector2(0, 2) + direction.rotated(-side * rig.strike_arc * 0.5) * rig.strike_reach
					_check(leg.foot.distance_to(expected) < 0.05, "Strike tip disagrees with the combat sector")
	# Ground anchors do not wander with procedural noise.
	rig.start_pose(SpiderRig.Pose.WINDUP, 0.58)
	var planted: Vector2 = rig._legs[4].foot
	rig.update_rig(0.1, Vector2.ZERO, 0.0)
	rig.update_rig(0.1, Vector2.ZERO, 0.0)
	_check(rig._legs[4].foot.is_equal_approx(planted), "Supporting foot slid during windup")

	# Emission is palette-masked: all eyes/veins survive, no dark flesh becomes emissive.
	var source: Image = rig.get_node("Body").texture.get_image()
	var mask: Image = ShadowEmission.mask_for(rig.get_node("Body").texture).get_image()
	var preserves_glow: bool = true
	var masks_flesh: bool = true
	var lit: int = 0
	for y: int in source.get_height():
		for x: int in source.get_width():
			var pixel: Color = source.get_pixel(x, y)
			if pixel.a > 0.0 and ShadowEmission.COLORS.has(pixel.to_html(false)):
				lit += 1
				preserves_glow = preserves_glow and mask.get_pixel(x, y).is_equal_approx(pixel)
			else:
				masks_flesh = masks_flesh and mask.get_pixel(x, y).a == 0.0
	_check(lit > 0 and preserves_glow, "Emission mask lost eye/vein pixels")
	_check(masks_flesh, "Emission mask lights up dark flesh or outlines")

	# Exercise the actual host state machine over a moving target, including missed pulls.
	player.health.max_health = 1000.0
	player.health.current = 1000.0
	spider._health.current = 48.0
	spider.position = Vector2.ZERO
	spider._grapple_cd = 0.0
	spider._set_state(ShadowSpider.State.IDLE)
	spider._target = null
	var visited: Dictionary = {}
	for frame: int in 600:
		player.position = spider.position + Vector2(90 if frame < 200 or frame >= 400 else 28, 0)
		await get_tree().physics_frame
		spider._physics_process(1.0 / 60.0)
		spider._process(1.0 / 60.0)
		visited[spider.state] = true
		if not spider.position.is_finite():
			_check(false, "Non-finite movement in pursuit")
	for expected: int in [ShadowSpider.State.NOTICE, ShadowSpider.State.CHASE, ShadowSpider.State.WINDUP, ShadowSpider.State.STRIKE, ShadowSpider.State.GRAPPLE_WINDUP, ShadowSpider.State.GRAPPLE_THROW, ShadowSpider.State.GRAPPLE_PULL, ShadowSpider.State.RECOVER]:
		_check(visited.has(expected), "Fight never reached state %s" % ShadowSpider.State.keys()[expected])
	_check(player.health.current < 1000.0, "Enemy never landed a hit in the live simulation")

	print("Void predator: %d checks, %d failures" % [_checks, _failures])
	level.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
