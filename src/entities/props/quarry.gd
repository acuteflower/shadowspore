class_name Quarry
extends Node2D
## The quarry where the knight is found, mining (story: find him; art tools/art_quarry.py -> assets/props/quarry/, his clip `mine` in tools/art_adventurer.py;
## data/ground.json quarries[]: {id, tile (the spot he stands on), clear_radius, knight {face}, yard {trample, tracks, props, palette gravel}}). The props
## (the worked outcrop, cut blocks, a handcart, tools, rubble) are a `HutYard` with this art folder, the gravel on the ground is the baked decal `<id>_yard`.
## `knight` is the `Adventurer` actor: he swings his pick in a loop and every strike (`strike` fires on the frame where the pick bites) makes a ring of iron
## on stone you can hear from far off (positional), a burst of chips, a flash of sparks and a puff of dust. `stop_mining()` / `start_mining()` are for the cutscenes.

const DIR: String = "res://assets/props/quarry/"
const SOUNDS: Array[AudioStream] = [preload("res://assets/audio/quarry/pick_a.wav"), preload("res://assets/audio/quarry/pick_b.wav"), preload("res://assets/audio/quarry/pick_c.wav")]
const SIGHT: float = 260.0 ## px: how far she must be to notice him, and he must be on her screen
const PICK_AT: Vector2 = Vector2(-17.0, 2.0) ## where his pick leans once he has put it down (his `set` clip lets go of it there)
const TIP: Vector2 = Vector2(-32.0, -10.0) ## where the pick bites, from his feet

var spec: Dictionary = {}
var knight: Adventurer
var props: HutYard
var knight_left: bool = false ## he walked off (the follow scene took him over)
var _face: Vector2 = Vector2.LEFT
var _pick: Sprite2D
var _body: StaticBody2D
var _sight_clock: float = 0.0
var _sound: AudioStreamPlayer2D
var _chips: CPUParticles2D
var _sparks: CPUParticles2D
var _dust: CPUParticles2D


func _ready() -> void:
	add_to_group("quest_actors")
	y_sort_enabled = true
	props = HutYard.new()
	props.name = "Props"
	props.setup((spec.get("yard", {}) as Dictionary).get("props", []) as Array, DIR)
	add_child(props)
	var look: Array = (spec.get("knight", {}) as Dictionary).get("face", [-1, 0]) as Array
	_face = Vector2(float(look[0]), float(look[1]))
	knight = Adventurer.new()
	knight.name = "Knight"
	add_child(knight)
	knight.strike.connect(_on_strike)
	start_mining()
	_pick = Sprite2D.new() ## his pickaxe leaning against the stone, there once he has put it down
	_pick.texture = load(DIR + "quarry_pick.png") as Texture2D
	_pick.offset = Vector2(0, _pick.texture.get_height() / 2.0 - 46.0)
	_pick.position = PICK_AT
	_pick.visible = false
	add_child(_pick)
	var body: StaticBody2D = StaticBody2D.new() ## he is not walked through
	_body = body
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(12, 6)
	shape.shape = box
	shape.position = Vector2(0, -3)
	body.add_child(shape)
	add_child(body)
	_sound = AudioStreamPlayer2D.new()
	_sound.position = TIP
	_sound.max_distance = 300.0
	_sound.attenuation = 1.6
	_sound.volume_db = -3.0
	add_child(_sound)
	_chips = _burst(14, 0.7, Color("c5c2d6"), Color("47446a"), Vector2(0, 260), 40.0, 100.0, 1.4, false)
	_sparks = _burst(5, 0.16, Color("fff2c8"), Color("ffb060"), Vector2.ZERO, 30.0, 70.0, 1.0, true)
	_dust = _burst(5, 0.9, Color(0.72, 0.7, 0.82, 0.45), Color(0.5, 0.48, 0.62, 0.0), Vector2(0, -6), 6.0, 20.0, 2.6, false)


## Where `id` stands now (the quest steps with an `actor` point at him: marker, distance, "reach").
func actor_position(id: String) -> Vector2:
	return knight.global_position if id == "knight" and knight != null and knight.visible else Vector2.INF ## (hidden: a settler is him now, `WorldLevel.take_knight`)


## The actor is reparented during the story; always follow the live knight.
func map_marker() -> Dictionary:
	if not is_instance_valid(knight) or not knight.is_visible_in_tree() or knight.modulate.a <= 0.01:
		return {}
	return {"id": "valdric", "position": knight.global_position}


func show_pick(on: bool) -> void:
	_pick.visible = on


## The knight leaves the quarry (the walk back): he and his collider move to `level`, so he sorts with the world and with her, not with the quarry's props.
func hand_over_knight(level: Node) -> void:
	knight.reparent(level, true)
	_body.reparent(level, true)
	set_knight_solid(false) ## while he walks the walker is what collides
	knight_left = true


func set_knight_solid(on: bool) -> void:
	(_body.get_child(0) as CollisionShape2D).set_deferred("disabled", not on)
	sync_knight_body()


func sync_knight_body() -> void:
	_body.global_position = knight.global_position


func colliders() -> Array[RID]:
	return [props.body_rid(), _body.get_rid()]


func _process(delta: float) -> void:
	_sight_clock -= delta
	if _sight_clock <= 0.0:
		_sight_clock = 0.25
		_check_sight()


## The step "find the knight" is done when he is in sight: near enough, on her screen and no wall or tree between (his own props do not count).
func _check_sight() -> void:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		if player == null or not player.is_multiplayer_authority() or player.quests == null:
			continue
		if String(player.quests.current().get("step_id", "")) != "find_knight":
			continue
		var from: Vector2 = player.global_position + Vector2(0, -14)
		var to: Vector2 = knight.global_position + Vector2(0, -22)
		var d: Vector2 = to - from
		if d.length() > SIGHT or absf(d.x) > 300.0 or absf(d.y) > 165.0:
			continue
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, 1, colliders())
		if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			player.quests.set_flag("knight_seen")


func start_mining() -> void:
	knight.play("mine", _face)


## He lowers the pick (a cutscene takes him over): the loop stops on the first frame of the clip.
func stop_mining(toward: Vector2 = Vector2.INF) -> void:
	knight.pose("mine", 0, _face if toward == Vector2.INF else toward)


func _burst(amount: int, life: float, from: Color, to: Color, gravity: Vector2, v_min: float, v_max: float, scale_k: float, unlit: bool) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.position = TIP
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector2(1.0, -0.7)
	p.spread = 55.0
	p.gravity = gravity
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.scale_amount_min = scale_k * 0.7
	p.scale_amount_max = scale_k
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([from, to])
	p.color_ramp = fade
	p.z_index = 2
	if unlit:
		p.material = Unlit.material()
	add_child(p)
	return p


func _on_strike() -> void:
	_sound.stream = SOUNDS[randi() % SOUNDS.size()]
	_sound.pitch_scale = randf_range(0.93, 1.07)
	_sound.play()
	for p: CPUParticles2D in [_chips, _sparks, _dust]:
		p.restart()
