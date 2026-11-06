class_name CabinBoard
extends Interactable
## The old board that lies across the doorstep of the lumberjack's cabin (art tools/art_cabin.py `yard_board.png`). It is solid and the door cannot be used while it lies there: E
## (a prompt only while the local player is close) makes her stoop for it (the carry animation: she walks up to it, stoops, lifts it, walks it to the left of the door and sets it down, dust, a creak and a thud); then it lies flat beside the doorstep, the collision is gone, the door can be used and the quest flag
## `cabin_board_moved` is set (a saved game puts it aside at once: `set_moved`). Solo / host only for now, like the other story scenes.

const ART: Texture2D = preload("res://assets/interior/cabin/yard_board.png")
const GLOW: Texture2D = preload("res://assets/interior/cabin/yard_board_glow.png")
const ASIDE: Vector2 = Vector2(-30.0, 8.0) ## where it ends up, from where it stood
const START: Vector2 = Vector2(24.0, 8.0) ## where she stands to take it, from its feet
const CARRY_SPEED: float = 26.0 ## px/s while she carries it
const SOUNDS: Array[AudioStream] = [preload("res://assets/audio/hut/creak_a.wav"), preload("res://assets/audio/hut/rustle.wav"), preload("res://assets/audio/hut/door_close.wav")]

var hut: Node2D ## the cabin `Hut` (typed loosely: no circular class dependency)
var moved: bool = false
var _busy: bool = false
var _sprite: Sprite2D
var _glow: Sprite2D
var _body: StaticBody2D
var _home: Vector2 = Vector2.ZERO


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = ART
	_sprite.hframes = 2 ## 0 propped against the door, 1 lying flat
	_sprite.offset = Vector2(0, ART.get_height() / 2.0 - 48.0)
	add_child(_sprite)
	_glow = Sprite2D.new()
	_glow.texture = GLOW
	_glow.offset = _sprite.offset
	_glow.hframes = 2
	_glow.material = Unlit.material()
	_sprite.add_child(_glow)
	_body = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(28, 10) ## it bars the doorstep
	shape.shape = box
	shape.position = Vector2(0, -3)
	_body.add_child(shape)
	add_child(_body)
	_home = position


func _process(_delta: float) -> void:
	_glow.modulate.a = lerpf(0.5, 1.0, TimeManager.night_amount())


func prompt() -> String:
	if moved or _busy:
		return ""
	var player: Player = _local_player()
	return "BRETT WEGTRAGEN" if player != null and not player.story_lock and not InputManager.ui_blocking else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + Vector2(0, 6)) - 22.0


func prompt_position() -> Vector2:
	return Vector2(0, -26)


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


## E: she walks up to its end, stoops, lifts it (the carry sheet, tools/art_hero_carry.py: the board is baked into her frames), carries it aside and sets it down.
func interact(player: Player) -> void:
	if moved or _busy:
		return
	_busy = true
	set_focused(false)
	_carry(player)


func _carry(player: Player) -> void:
	var rig: Dictionary = DataRegistry.table("hero_rig").get("carry", {}) as Dictionary
	var lift: int = int(rig.get("lift", 8))
	var walk: int = int(rig.get("walk", 8))
	var lift_fps: float = float(rig.get("lift_fps", 12))
	var walk_fps: float = float(rig.get("walk_fps", 10))
	player.story_lock = true
	InputManager.ui_blocking = true
	var start: Vector2 = global_position + START
	player.auto_walk = start
	var waited: float = 0.0
	while waited < 4.0 and player.global_position.distance_to(start) > 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if player.global_position.distance_to(start) > 12.0:
		player.global_position = start
	player.auto_walk = Vector2.INF
	player.facing = Vector2.LEFT
	await get_tree().physics_frame
	# 1. she stoops and lifts it: the board in the picture gives way to the one in her hands
	player.show_carry_frame(0, true)
	_sprite.visible = false
	_body.get_child(0).set_deferred("disabled", true)
	_sound(0, -3.0)
	for i: int in lift:
		player.show_carry_frame(i, true)
		if i == 3:
			ShockRing.burst(get_parent(), position + Vector2(0.0, 4.0), 16.0, 0.25) ## dust where it lay
			_sound(1, -6.0)
		await get_tree().create_timer(1.0 / lift_fps, true, false, true).timeout
	# 2. she carries it aside
	var steps: float = ASIDE.x * -1.0
	var from_x: float = player.global_position.x
	var t: float = 0.0
	var duration: float = steps / CARRY_SPEED
	while t < duration:
		var dt: float = get_process_delta_time()
		t += dt
		player.global_position.x = from_x - minf(t * CARRY_SPEED, steps)
		player.show_carry_frame(lift + int(t * walk_fps) % walk, true)
		await get_tree().process_frame
	# 3. she lowers it and lets go
	for i: int in range(lift - 1, -1, -1):
		player.show_carry_frame(i, true)
		await get_tree().create_timer(1.0 / lift_fps, true, false, true).timeout
	position = _home + ASIDE
	_sprite.frame = 1 ## it lies flat beside the doorstep now
	_glow.frame = 1
	_sprite.visible = true
	_sprite.rotation = 0.0
	_sound(2, -7.0)
	ShockRing.burst(get_parent(), position + Vector2(0.0, 4.0), 18.0, 0.3)
	player.add_shake(0.8)
	await get_tree().create_timer(0.25, true, false, true).timeout
	player.end_faint()
	player.story_lock = false
	InputManager.ui_blocking = false
	_set_done(true)
	if player.quests != null:
		player.quests.set_flag("cabin_board_moved")


## A loaded game: the board lies beside the doorstep already.
func set_moved(on: bool) -> void:
	if on == moved:
		return
	if on:
		position = _home + ASIDE
		_sprite.frame = 1
		_glow.frame = 1
		_body.get_child(0).set_deferred("disabled", true)
	_set_done(on)


func _set_done(on: bool) -> void:
	moved = on
	_busy = false
	var cabin: Hut = hut as Hut
	if cabin != null and cabin.doorway != null:
		cabin.doorway.locked = not on


func _sound(index: int, volume: float) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = SOUNDS[index]
	player.volume_db = volume
	player.max_distance = 300.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
