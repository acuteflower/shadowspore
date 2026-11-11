extends Node
## Checks of the shadow step (Alt): Godot --headless --path . tools/test_shadow_step.tscn   (prints SHADOW STEP OK)
var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var start: Vector2 = player.global_position
	player.health.invulnerable_seconds = 0.0
	var stamina_before: float = player.stamina.current
	check(player._try_shadow_step(Vector2.RIGHT), "a step on open ground starts")
	check(is_equal_approx(player.step_cost(), 14.0 + float(player.progress.level)), "a step costs 14 + level")
	check(is_equal_approx(player.stamina.current, stamina_before - player.step_cost()), "the step costs its stamina")
	var health_before: float = player.health.current
	player.health.take_damage(10.0, start + Vector2(-20, 0), 0.0)
	check(player.health.current == health_before, "no blow reaches her during the step")
	var grace_left: int = player.health._invulnerable_until_msec - Time.get_ticks_msec()
	check(grace_left > 0 and grace_left <= int(player.step_grace * 1000.0) + 5, "the grace lasts only the step")
	check(player._step_t >= 0.0 and not player.stepper.is_ready(), "the step runs and its cooldown is set")
	check(player.facing.is_equal_approx(Vector2.RIGHT), "she faces the way she steps")
	var mat: ShaderMaterial = player._sprite.material as ShaderMaterial
	var dissolved: bool = false
	var formed_again: bool = false
	var moved_hidden: bool = true
	while player._step_t >= 0.0:
		player._animate(1.0 / 60.0)
		if int(mat.get_shader_parameter("step_mode")) == 1 and float(mat.get_shader_parameter("step_amt")) >= 0.99:
			dissolved = true
		if int(mat.get_shader_parameter("step_mode")) == 2:
			formed_again = true
		if player.global_position != start and player._step_t >= 0.0 and player._step_t < Player.STEP_GONE:
			moved_hidden = false
	check(dissolved and formed_again, "she dissolves fully and condenses again")
	check(moved_hidden, "she is only moved while dissolved")
	check(absf(player.global_position.distance_to(start) - player.step_range) < 0.5, "the step carries her its full range on open ground")
	check(int(mat.get_shader_parameter("step_mode")) == 0, "the shader is clean after the step")
	check((player.attack.get_node("Hand") as Node2D).visible, "the sword arm comes back")
	check(not player._try_shadow_step(Vector2.LEFT) or not player.stepper.is_ready(), "cooldown bookkeeping holds")
	# Picking / a swing are broken off: a step goes through anything she is doing.
	player.stepper.cooldown_left = 0.0
	player._busy = true
	player._busy_kind = "pick"
	check(player._try_shadow_step(Vector2.DOWN) and not player._busy, "the step breaks off picking")
	while player._step_t >= 0.0:
		player._animate(1.0 / 60.0)
	# Out of a sprint with the direction held: she comes out of the void at her speed and runs on, no stop.
	player.stepper.cooldown_left = 0.0
	player.stamina.refill()
	player.velocity = Vector2.RIGHT * player.sprint_speed
	check(player._try_shadow_step(Vector2.RIGHT), "a step out of a sprint starts")
	while player._step_t >= 0.0 and player._step_t < Player.STEP_BACK + Player.STEP_FORM:
		player._animate(1.0 / 60.0)
	Input.action_press("move_right")
	player._move(1.0 / 60.0)
	Input.action_release("move_right")
	check(player._step_t < 0.0, "with a direction held the landing is skipped")
	check(player.velocity.length() >= player.sprint_speed * 0.9, "she keeps her sprint speed through the step (%.0f px/s)" % player.velocity.length())
	# Too little stamina: no step.
	player._step_t = -1.0
	player.stepper.cooldown_left = 0.0
	player.stamina.current = player.step_cost() - 1.0
	check(not player._try_shadow_step(Vector2.RIGHT) and player._step_t < 0.0, "without enough stamina there is no step")
	player.stamina.refill()
	# A wall right in front: no step at all.
	player._step_t = -1.0
	player.stepper.cooldown_left = 0.0
	var wall: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(4, 80)
	shape.shape = box
	wall.add_child(shape)
	wall.global_position = player.global_position + Vector2(10, 0)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not player._try_shadow_step(Vector2.RIGHT), "a wall right in front cancels the step")
	print("SHADOW STEP OK" if failures == 0 else "SHADOW STEP: %d failures" % failures)
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
