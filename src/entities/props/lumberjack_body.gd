class_name LumberjackBody
extends Interactable
## The dead lumberjack in the cabin (art tools/art_lumberjack.py): sat against the back wall, the void eating him like the knight under the fallen tree: glowing veins that breathe, a
## cold violet pool of light on the floor and dark specks rising out of it. His axe lies beside him as a sprite of its own. E ("UNTERSUCHEN", once) opens Ellie's short monologue
## (dialogue `lumberjack_found`), the axe leaves the floor in a little burst of dust and goes into her hotbar (slot 4, `axe_basic`), the flag `lumberjack_found` ends the search and
## the next step of the quest begins ("report to the knight", with the tutorial card about felling trees). Built by `Interior` from data/interiors.json `body`. Solo / host only for now.

const DIR: String = "res://assets/interior/cabin/"
const DROP: PackedScene = preload("res://src/entities/drops/item_drop.tscn")

var axe_at: Vector2 = Vector2.ZERO ## room position of the axe's feet
var _sprite: Sprite2D
var _glow: Sprite2D
var _axe: Sprite2D
var _motes: CPUParticles2D
var _time: float = 0.0
var _busy: bool = false


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(DIR + "lumberjack.png") as Texture2D
	_sprite.offset = Vector2(0, _sprite.texture.get_height() / 2.0 - 54.0)
	add_child(_sprite)
	_glow = Sprite2D.new() ## the void in him breathes
	_glow.texture = load(DIR + "lumberjack_glow.png") as Texture2D
	_glow.offset = _sprite.offset
	_glow.material = Unlit.material()
	add_child(_glow)
	_axe = Sprite2D.new()
	_axe.texture = load(DIR + "lumberjack_axe.png") as Texture2D
	_axe.offset = Vector2(0, _axe.texture.get_height() / 2.0 - 16.0)
	_axe.position = axe_at - position
	add_child(_axe)
	var interior: Interior = get_parent() as Interior
	if interior != null:
		interior._light(self, Vector2(4, -8), Color("a65cf0"), 52, 0.8, 0.5, 0.0, false)
	_motes = CPUParticles2D.new()
	_motes.position = Vector2(4, -4)
	_motes.amount = 8
	_motes.lifetime = 3.0
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(18, 3)
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
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(30, 12)
	shape.shape = box
	shape.position = Vector2(0, -6)
	body.add_child(shape)
	add_child(body)


func _process(delta: float) -> void:
	_time += delta
	_glow.modulate.a = 0.7 + 0.3 * sin(_time * 1.7) * sin(_time * 0.6 + 1.0)


func prompt() -> String:
	var player: Player = _local_player()
	if _busy or player == null or player.quests == null or player.story_lock or InputManager.ui_blocking or player.quests.has_flag("lumberjack_found"):
		return ""
	return "UNTERSUCHEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + Vector2(0, 8)) - 26.0


func prompt_position() -> Vector2:
	return Vector2(0, -52)


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


func interact(player: Player) -> void:
	if _busy:
		return
	_busy = true
	set_focused(false)
	_search(player)


func _search(player: Player) -> void:
	player.story_lock = true
	InputManager.ui_blocking = true
	player.facing = (global_position - player.global_position).normalized()
	await get_tree().create_timer(0.4, true, false, true).timeout
	var runner: BubbleRunner = BubbleRunner.find(player)
	if runner != null:
		await runner.play("lumberjack_found", player)
	_take_axe(player)
	player.story_lock = false
	InputManager.ui_blocking = false
	if player.quests != null:
		player.quests.set_flag("lumberjack_found")


## The axe drops out of his hands like the sword out of the knight: it pops up and lands beside him, only she can pick it up (the magnet draws it in), it never expires.
func _take_axe(player: Player) -> void:
	if _axe != null:
		ShockRing.burst(get_parent(), axe_at, 14.0, 0.25)
		var tween: Tween = create_tween()
		tween.tween_property(_axe, "modulate:a", 0.0, 0.3)
		tween.tween_callback(_axe.queue_free)
		_axe = null
	var world: Node = get_tree().get_first_node_in_group("world")
	var drops: Node = world.get_node_or_null("Drops") if world != null else null
	if drops == null:
		player.inventory.give("axe_basic", 1)
		return
	var drop: ItemDrop = DROP.instantiate() as ItemDrop
	drop.name = "LumberjackAxe"
	drop.item_id = "axe_basic"
	drop.story_owner = player.name.to_int()
	drop.story_id = "lumberjack_axe"
	drop.position = global_position + Vector2(2, 8)
	drop.launch = ((player.global_position - drop.position).normalized() * 16.0).limit_length(16.0) ## it pops out towards her, inside the magnet's reach
	drops.add_child(drop)
