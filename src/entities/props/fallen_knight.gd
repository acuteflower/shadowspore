class_name FallenKnight
extends Interactable
## Host-owned, once-per-player story loot. Pending swords survive save/load.
const ART: Texture2D = preload("res://assets/props/fallen_knight.png")
const GLOW: Texture2D = preload("res://assets/props/fallen_knight_glow.png") ## only the emissive pixels (void veins, fungi), drawn unlit
const BODY: Vector2 = Vector2(6, -2) ## where the knight himself sits in the picture (feet at the node)
var _glow: Sprite2D
var _motes: CPUParticles2D
var _time: float = 0.0
const DROP: PackedScene = preload("res://src/entities/drops/item_drop.tscn")
var states: Dictionary = {}
var _world: WorldLevel

func _ready() -> void:
	_world = get_parent() as WorldLevel
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = ART
	sprite.offset = Vector2(0, -15)
	add_child(sprite)
	_glow = Sprite2D.new() ## the void in him and on the trunk breathes; at night it is brighter
	_glow.texture = GLOW
	_glow.offset = sprite.offset
	_glow.material = Unlit.material()
	add_child(_glow)
	var light: NightLight = NightLight.new() ## a cold violet pool on the ground round him
	light.position = Vector2(2, -6)
	light.radius = 62
	light.base_energy = 0.55
	light.glow_color = Color("a65cf0")
	add_child(light)
	_motes = CPUParticles2D.new() ## dark specks rising out of the pool
	_motes.position = Vector2(2, -4)
	_motes.amount = 9
	_motes.lifetime = 3.2
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(24, 4)
	_motes.direction = Vector2(0, -1)
	_motes.spread = 20.0
	_motes.initial_velocity_min = 3.0
	_motes.initial_velocity_max = 8.0
	_motes.gravity = Vector2.ZERO
	_motes.color = Color("e45cf0")
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.25, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	_motes.color_ramp = fade
	_motes.material = Unlit.material()
	add_child(_motes)
	for part: Array in [[Vector2(84, 8), Vector2(-3, -5)], [Vector2(20, 11), Vector2(7, -1)]]: ## the felled trunk and the knight in front of it
		var body: StaticBody2D = StaticBody2D.new()
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = part[0] as Vector2
		shape.shape = box
		shape.position = part[1] as Vector2
		body.add_child(shape)
		add_child(body)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _snapshot.rpc_id(id, states))

func prompt() -> String:
	return "" if states.has(str(multiplayer.get_unique_id())) else "RITTER UNTERSUCHEN"
func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + BODY) - 12
func prompt_position() -> Vector2:
	return Vector2(6, -34)
func _process(delta: float) -> void:
	_time += delta
	_glow.modulate.a = lerpf(0.4, 1.0, TimeManager.night_amount()) * (0.72 + 0.28 * sin(_time * 1.5) * sin(_time * 0.7 + 1.0))
func interact(player: Player) -> void:
	if multiplayer.is_server(): _inspect(player.name.to_int())
	else: _request_inspect.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_inspect() -> void:
	if multiplayer.is_server(): _inspect(multiplayer.get_remote_sender_id())

func _inspect(id: int) -> void:
	if not multiplayer.is_server(): return
	var player: Player = _world._players.get_node_or_null(str(id)) as Player
	if player == null or player.health.current <= 0 or reach_distance(player.global_position) > INTERACT_RANGE + 6:
		return
	var key: String = str(id)
	if not states.has(key):
		states[key] = {"inspected": true, "claimed": false}
		_spawn_sword(id)
		_clink.rpc()
	_snapshot.rpc(states)
	_owner_flag.rpc_id(id, "knight_inspected")
	if bool((states[key] as Dictionary).get("claimed", false)):
		_owner_flag.rpc_id(id, "knight_sword_taken")

func _spawn_sword(id: int) -> void:
	var parent: Node = _world.get_node("Drops")
	if parent.has_node("KnightSword_%d" % id): return
	var drop: ItemDrop = DROP.instantiate() as ItemDrop
	drop.name = "KnightSword_%d" % id
	drop.item_id = "sword_basic"
	drop.story_owner = id
	drop.story_id = "knight_sword"
	drop.position = position + Vector2(5,10)
	drop.launch = Vector2(4,12)
	parent.add_child(drop)

func sword_taken(id: int) -> void:
	if not multiplayer.is_server() or not states.has(str(id)): return
	(states[str(id)] as Dictionary)["claimed"] = true
	_snapshot.rpc(states)
	_owner_flag.rpc_id(id, "knight_sword_taken")

@rpc("authority", "call_local", "reliable")
func _snapshot(data: Dictionary) -> void:
	states = data.duplicate(true)

@rpc("authority", "call_local", "reliable")
func _owner_flag(flag: String) -> void:
	var player: Player = _world._players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if player != null and player.quests != null: player.quests.set_flag(flag)

func export_data() -> Dictionary:
	return states.duplicate(true)
func import_data(data: Dictionary) -> void:
	if not multiplayer.is_server(): return
	for child: Node in _world.get_node("Drops").get_children():
		if child is ItemDrop and (child as ItemDrop).story_id == "knight_sword":
			child.get_parent().remove_child(child)
			child.queue_free()
	states = data.duplicate(true)
	for key: String in states:
		if not bool((states[key] as Dictionary).get("claimed", false)): _spawn_sword(int(key))
	_snapshot.rpc(states)


@rpc("authority", "call_local", "reliable")
func _clink() -> void:
	var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	sound.stream = preload("res://assets/audio/intro/lid_scrape.wav")
	sound.volume_db = -17
	sound.pitch_scale = 1.5
	sound.max_distance = 340
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
