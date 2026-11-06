class_name HutTree
extends Node2D
## The young tree that grows out of the hut's floor, as something to chop down (a child of `Interior`, built from the prop's `fell` {hits, drops, final_drops} in data/interiors.json).
## It takes the trunk and crown sprites of the prop and a hurtbox on physics layer 5: the hits of her axe (the normal swings, the host's hit scan) find it. Another tool only makes it
## shake. Each hit shakes the crown, chips bark and shakes needles loose, and may drop a piece of wood; the last hit fells it: the trunk cracks, then the whole tree topples away from
## her, thuds, bounces, lies a moment and fades; a stump stays. The quest flag `hut_tree_felled` is set (the task "fell the tree in the house"; a save restores the stump: `set_felled`).

const SOUNDS: Array[AudioStream] = [preload("res://assets/audio/hut/creak_a.wav"), preload("res://assets/audio/hut/rustle.wav"), preload("res://assets/audio/hut/groan.wav"), preload("res://assets/audio/hut/door_close.wav")]

var interior: Interior
var trunk: Sprite2D
var crown: Sprite2D
var spec: Dictionary = {}
var hits: int = 0
var felled: bool = false
var _feet: float = 150.0
var _hurtbox: HutTreeHurtbox
var _shake: float = 0.0
var _time: float = 0.0
var _stump: Sprite2D
var _stump_cleared: bool = false


func setup(room: Interior, trunk_sprite: Sprite2D, crown_sprite: Sprite2D, data: Dictionary, feet: float) -> void:
	interior = room
	trunk = trunk_sprite
	crown = crown_sprite
	spec = data
	_feet = feet
	_hurtbox = HutTreeHurtbox.new()
	_hurtbox.tree = self
	_hurtbox.collision_layer = 1 << 4
	_hurtbox.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(26, 62)
	shape.shape = box
	shape.position = Vector2(0, -34)
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


func _process(delta: float) -> void:
	_time += delta
	if felled or _shake <= 0.0 or crown == null:
		return
	_shake = maxf(_shake - delta * 1.6, 0.0)
	var wobble: float = sin(_time * 38.0) * _shake ## a damped shudder, the crown far more than the trunk
	crown.rotation = wobble * 0.05
	trunk.rotation = wobble * 0.008


## A hit scan found the tree (host): only an axe fells it.
func hit(source: int) -> void:
	if felled:
		return
	var tool_id: String = ""
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		if player != null and player.name.to_int() == source:
			tool_id = String(Items.definition(player.inventory.active_stack()).get("tool", ""))
	_shake = 1.0
	_sound(1, -8.0)
	if tool_id != "axe":
		return
	hits += 1
	_chips()
	if randf() < 0.5:
		DropComponent.spawn_drops(get_tree(), spec.get("drops", []) as Array, global_position + Vector2(10, 4))
	if hits >= int(spec.get("hits", 6)):
		_fell(source)
	else:
		_sound(0, -6.0)


func _chips() -> void:
	var chips: CPUParticles2D = CPUParticles2D.new()
	chips.position = Vector2(0, -22)
	chips.one_shot = true
	chips.emitting = true
	chips.amount = 8
	chips.lifetime = 0.7
	chips.explosiveness = 1.0
	chips.direction = Vector2(0, -1)
	chips.spread = 80.0
	chips.gravity = Vector2(0, 220)
	chips.initial_velocity_min = 30.0
	chips.initial_velocity_max = 70.0
	chips.color = Color("85697a")
	chips.z_index = 3
	add_child(chips)
	get_tree().create_timer(1.0).timeout.connect(chips.queue_free)


func _sound(index: int, volume: float) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = SOUNDS[index]
	player.volume_db = volume
	player.max_distance = 400.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## The last hit: the trunk cracks and shudders, then the tree topples away from the hitter, hits the floor, bounces, lies there and fades; the stump stays.
func _fell(source: int) -> void:
	felled = true
	_hurtbox.set_deferred("monitorable", false)
	_hurtbox.collision_layer = 0
	_sound(2, -2.0)
	var away: float = 1.0
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name.to_int() == source:
			away = signf(global_position.x - (node as Node2D).global_position.x)
			if away == 0.0:
				away = 1.0
	_stump_make()
	var pivot: Node2D = Node2D.new() ## hinged at the foot: the trunk and the crown fall together
	pivot.position = trunk.position
	interior.add_child(pivot)
	pivot.z_index = 2
	var trunk_at: Vector2 = trunk.position
	trunk.reparent(pivot, false)
	trunk.position = Vector2.ZERO
	if crown != null:
		crown.reparent(pivot, false)
		crown.position = Vector2.ZERO
		for i: int in interior._crowns.size(): ## the sway of a tree that is gone
			if interior._crowns[i].trunk == trunk:
				interior._crowns.remove_at(i)
				break
	trunk.rotation = 0.0
	if crown != null:
		crown.rotation = 0.0
	var shudder: Tween = create_tween()
	for k: int in 6:
		shudder.tween_property(pivot, "rotation", away * 0.02 * (1.0 if k % 2 == 0 else -0.6), 0.05)
	shudder.tween_property(pivot, "rotation", away * 1.42, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN) ## it speeds up as it falls
	await shudder.finished
	_sound(3, 0.0)
	ShockRing.burst(interior, trunk_at + Vector2(away * 60.0, 0.0), 40.0, 0.7)
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			(node as Player).add_shake(2.2)
	var bounce: Tween = create_tween()
	bounce.tween_property(pivot, "rotation", away * 1.3, 0.12)
	bounce.tween_property(pivot, "rotation", away * 1.42, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	DropComponent.spawn_drops(get_tree(), spec.get("final_drops", []) as Array, global_position + Vector2(away * 22.0, 6.0))
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		if player != null and player.is_multiplayer_authority() and player.quests != null:
			player.quests.set_flag("hut_tree_felled")
	await get_tree().create_timer(0.9).timeout
	var fade: Tween = create_tween()
	fade.tween_property(pivot, "modulate:a", 0.0, 0.6)
	await fade.finished
	pivot.queue_free()


## A saved game after the felling: the stump only.
func set_felled(on: bool) -> void:
	if not on or felled:
		return
	felled = true
	_hurtbox.collision_layer = 0
	trunk.visible = false
	if crown != null:
		crown.visible = false
		for i: int in interior._crowns.size():
			if interior._crowns[i].trunk == trunk:
				interior._crowns.remove_at(i)
				break
	_stump_make()


## What is left: the foot of the trunk, cut off flat (the lowest rows of the trunk picture).
func _stump_make() -> void:
	if _stump != null or _stump_cleared:
		return
	_stump = Sprite2D.new()
	_stump.texture = trunk.texture
	_stump.region_enabled = true
	var size: Vector2 = trunk.texture.get_size()
	_stump.region_rect = Rect2(0.0, _feet - 14.0, size.x, 14.0)
	_stump.offset = Vector2(0.0, -7.0)
	_stump.position = trunk.position
	interior.add_child(_stump)


## The hut is renewed: the planks of the new floor cover where the tree grew, no stump is left (also none made after this).
func clear_stump() -> void:
	_stump_cleared = true
	if _stump != null:
		_stump.queue_free()
		_stump = null
