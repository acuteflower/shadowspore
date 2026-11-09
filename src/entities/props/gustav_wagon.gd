class_name GustavWagon
extends Interactable
## Gustav's wagon (quest `gustav_rescue`, data/ground.json `wagons`): a small covered wagon on its side in a grove east of the town, its rear door wedged shut with a bent beam. Gustav sits inside
## and knocks (three blows of wood on wood every ~7 s, positional, until she has seen the wagon). Steps: she sees it (`wagon_seen`, `_check_sight` like the quarry's), beats the spider
## (GustavRescueScene), then E "TÜR LÖSEN" in the step `free_gustav`: she walks up, stoops (`Player.begin_pick`), pulls the wedge, the door springs open, dust and a creak, and Gustav
## (`StoryGustav`) stumbles out; flag `wagon_opened`. The wreck stays for good. Solo / host only, like the other story scenes.
## Picture: `py -3 tools/art_wagon.py [preview.png]` -> assets/props/gustav_wagon.png (frame 0 door wedged shut, frame 1 thrown open) + `_glow` (unlit buds, fungi, void veins).

const SIGHT: float = 260.0
const ART: Texture2D = preload("res://assets/props/gustav_wagon.png")
const GLOW: Texture2D = preload("res://assets/props/gustav_wagon_glow.png") ## only the emissive pixels, drawn unlit
const FRAME: Vector2i = Vector2i(128, 80) ## the middle of the wagon is at x 64, the ground row is 60
const GROUND_ROW: int = 60
const DOOR: Vector2 = Vector2(30.0, 11.0) ## the foot of the rear door, from the wagon's feet (the wagon stands turned towards us)
const PLAYER_AT: Vector2 = Vector2(50.0, 20.0) ## where she stands to pull the wedge
const GUSTAV_AT: Vector2 = Vector2(48.0, 6.0) ## where he stands after he stepped out
const FOOTPRINT: PackedVector2Array = [Vector2(-17.0, -13.5), Vector2(34.0, 4.8), Vector2(18.0, 13.5), Vector2(-35.0, -4.8)] ## the box on the ground
const KNOCK_EVERY: float = 7.0
const HAMMER: AudioStream = preload("res://assets/audio/hut/hammer_c.wav")
const CREAK: AudioStream = preload("res://assets/audio/hut/creak_a.wav")
const THUD: AudioStream = preload("res://assets/audio/hut/door_close.wav")

var door_open: bool = false
var gustav: StoryGustav
var _busy: bool = false
var _knock_clock: float = 3.0
var _knocks_left: int = 0
var _knock_gap: float = 0.0
var _sight_clock: float = 0.0
var _heard_by_local: bool = false
var _sprite: Sprite2D
var _glow: Sprite2D
var _time: float = 0.0


func _ready() -> void:
	for tex: Texture2D in [ART, GLOW]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		sprite.hframes = tex.get_width() / FRAME.x
		sprite.frame = 1 if door_open else 0
		sprite.offset = Vector2(0.0, -(GROUND_ROW - FRAME.y / 2.0))
		if tex == GLOW:
			sprite.material = Unlit.material()
			_glow = sprite
		else:
			_sprite = sprite
		add_child(sprite)
	var light: NightLight = NightLight.new()
	light.position = Vector2(26.0, -10.0)
	light.radius = 34.0
	light.base_energy = 0.45
	light.glow_color = Color("78f4e6")
	add_child(light)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var poly: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
	poly.points = FOOTPRINT
	shape.shape = poly
	body.add_child(shape)
	add_child(body)


func _process(delta: float) -> void:
	_time += delta
	_glow.modulate.a = lerpf(0.45, 1.0, TimeManager.night_amount()) * (0.8 + 0.2 * sin(_time * 1.3 + position.x))
	var player: Player = _local_player()
	if player != null and player.quests != null and player.quests.has_flag("wagon_seen"):
		_heard_by_local = true
	_sight_clock -= delta
	if _sight_clock <= 0.0:
		_sight_clock = 0.25
		_check_sight(player)
	if door_open or _heard_by_local or player == null:
		return
	if _knocks_left > 0:
		_knock_gap -= delta
		if _knock_gap <= 0.0:
			_knocks_left -= 1
			_knock_gap = 0.32
			_sound(HAMMER, -4.0, 0.52, 380.0)
		return
	_knock_clock -= delta
	if _knock_clock <= 0.0:
		_knock_clock = KNOCK_EVERY
		_knocks_left = 3
		_knock_gap = 0.0


## The wagon is "found" when it is in her picture, close and nothing solid is between (like the knight at the quarry).
func _check_sight(player: Player) -> void:
	if player == null or player.quests == null or String(player.quests.current().get("step_id", "")) != "follow_knocks":
		return
	var from: Vector2 = player.global_position + Vector2(0, -14)
	var to: Vector2 = global_position + Vector2(0, -16)
	var d: Vector2 = to - from
	if d.length() > SIGHT or absf(d.x) > 300.0 or absf(d.y) > 165.0:
		return
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, 1)
	if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		player.quests.set_flag("wagon_seen")
		var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
		if box != null:
			box.play("wagon_spotted")


func prompt() -> String:
	if door_open or _busy:
		return ""
	var player: Player = _local_player()
	if player == null or player.quests == null or player.story_lock or InputManager.ui_blocking:
		return ""
	return "TÜR LÖSEN" if String(player.quests.current().get("step_id", "")) == "free_gustav" else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + DOOR + Vector2(12.0, 6.0)) - 18.0


func prompt_position() -> Vector2:
	return DOOR + Vector2(0.0, -46.0)


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


func interact(player: Player) -> void:
	if door_open or _busy:
		return
	_busy = true
	set_focused(false)
	_pull_wedge(player)


func _pull_wedge(player: Player) -> void:
	player.story_lock = true
	InputManager.ui_blocking = true
	var start: Vector2 = global_position + PLAYER_AT
	player.auto_walk = start
	var waited: float = 0.0
	while waited < 4.0 and player.global_position.distance_to(start) > 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if player.global_position.distance_to(start) > 12.0:
		player.global_position = start
	player.auto_walk = Vector2.INF
	player.story_lock = false ## begin_pick holds her itself
	InputManager.ui_blocking = false
	await get_tree().physics_frame
	var done: bool = false
	player.begin_pick(Vector2(-1.0, -0.4).normalized(), func() -> void:
		_spring(player)
		done = true)
	var guard: float = 0.0
	while not done and guard < 3.0: ## the grab comes at about a third of a second
		await get_tree().process_frame
		guard += get_process_delta_time()
	if not done:
		_spring(player)


## The wedge gives: the door flies open, dust, a creak, a shout from inside, and he stumbles out.
func _spring(player: Player) -> void:
	set_open(true, true)
	ShockRing.burst(get_parent(), global_position + DOOR + Vector2(8.0, 2.0), 20.0, 0.3)
	player.add_shake(0.9)
	_sound(CREAK, -3.0, 1.0, 320.0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_sound(THUD, -6.0, 0.9, 320.0)
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.play("wagon_door")
	await get_tree().create_timer(0.9, true, false, true).timeout
	_busy = false
	if is_instance_valid(player) and player.quests != null:
		player.quests.set_flag("wagon_opened")


## `animate`: Gustav steps out of the door (a few steps); without it he already stands beside the wagon (a loaded game).
func set_open(on: bool, animate: bool = false) -> void:
	door_open = on
	if _sprite != null:
		_sprite.frame = 1 if on else 0
		_glow.frame = _sprite.frame
	if not on or gustav != null:
		return
	gustav = StoryGustav.new()
	gustav.name = "StoryGustav"
	get_parent().add_child(gustav)
	if not animate:
		gustav.global_position = global_position + GUSTAV_AT
		gustav.play("idle", Vector2(1.0, 0.6))
		return
	gustav.global_position = global_position + DOOR + Vector2(4.0, 2.0)
	gustav.play("walk", Vector2.RIGHT)
	var tween: Tween = create_tween()
	tween.tween_property(gustav, "global_position", global_position + GUSTAV_AT, 1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if is_instance_valid(gustav):
			gustav.play("idle", Vector2(-1.0, 0.4)))


func _sound(stream: AudioStream, volume: float, pitch: float, reach: float) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.max_distance = reach
	player.finished.connect(player.queue_free)
	add_child(player)
	player.position = DOOR + Vector2(0.0, -14.0)
	player.play()

