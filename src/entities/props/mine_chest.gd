class_name MineChest
extends Interactable
## A chest in a treasure room of the mine. E opens it; the host checks the distance and that it is still shut, pays out copper, XP and items
## (`MineManager.request_chest`), and everyone sees it open. The state is the manager's (`chest:<level>:<tile>`), so it stays open and is saved.

var key: String = ""
var _sprite: Sprite2D
var _open: bool = false


func setup(chest_key: String, texture_path: String, feet: int, opened: bool) -> void:
	key = chest_key
	add_to_group("mine_chests")
	var texture: Texture2D = load(texture_path) as Texture2D
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.offset = Vector2(0.0, texture.get_height() / 2.0 - feet)
	add_child(_sprite)
	var glow_path: String = texture_path.replace(".png", "_glow.png")
	if ResourceLoader.exists(glow_path):
		var glow: Sprite2D = Sprite2D.new()
		glow.texture = load(glow_path) as Texture2D
		glow.offset = _sprite.offset
		glow.material = Unlit.material()
		_sprite.add_child(glow)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(34, 9)
	shape.shape = box
	shape.position = Vector2(0, -4)
	body.add_child(shape)
	add_child(body)
	if opened:
		_show_open(false)


func prompt() -> String:
	return "" if _open else "ÖFFNEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 14.0


func prompt_position() -> Vector2:
	return Vector2(0, -34)


func interact(_player: Player) -> void:
	var mines: MineManager = get_tree().get_first_node_in_group("mines") as MineManager
	if mines != null and not _open:
		mines.request_chest(key)


## Everyone: the lid is up (dull, the glints gone) and a puff of dust.
func opened() -> void:
	_show_open(true)


func _show_open(fx: bool) -> void:
	_open = true
	_sprite.modulate = Color(0.62, 0.58, 0.7)
	for child: Node in _sprite.get_children():
		(child as CanvasItem).visible = false
	if fx:
		var puff: CPUParticles2D = CPUParticles2D.new()
		puff.one_shot = true
		puff.emitting = true
		puff.amount = 14
		puff.lifetime = 0.8
		puff.explosiveness = 0.9
		puff.direction = Vector2(0, -1)
		puff.spread = 70.0
		puff.gravity = Vector2(0, 20)
		puff.initial_velocity_min = 10.0
		puff.initial_velocity_max = 28.0
		puff.scale_amount_min = 1.0
		puff.scale_amount_max = 2.0
		puff.color = Color(0.85, 0.78, 0.6, 0.8)
		puff.position = Vector2(0, -14)
		puff.finished.connect(puff.queue_free)
		add_child(puff)
