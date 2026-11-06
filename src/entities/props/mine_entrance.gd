class_name MineEntrance
extends Node2D
## The old mine's gate on the surface (art: tools/art_mine.py -> assets/mine/props/entrance.png): a mound of rock with a timber frame, two lanterns and the
## rails running in. Solid except for the opening; E at the gate (`MineGate`) takes the local player down to level 1 of the mine, or opens the `LiftMenu` once
## a lift down there has been mended. Placed from data/ground.json "mines": {id, tile, clear_radius}. `exit_position` is where she stands when she comes back.

const FRAME: Vector2i = Vector2i(216, 176)
const FEET: int = 156

var exit_position: Vector2 ## world px, in front of the gate


func _ready() -> void:
	y_sort_enabled = true
	var picture: Sprite2D = Sprite2D.new()
	picture.texture = load("res://assets/mine/props/entrance.png") as Texture2D
	picture.offset = Vector2(0, FRAME.y / 2.0 - FEET)
	add_child(picture)
	var glow: Sprite2D = Sprite2D.new() ## the lanterns
	glow.texture = load("res://assets/mine/props/entrance_glow.png") as Texture2D
	glow.offset = picture.offset
	glow.material = Unlit.material()
	add_child(glow)
	for side: float in [-1.0, 1.0]:
		var light: NightLight = NightLight.new()
		light.position = Vector2(34.0 * side, -26.0)
		light.radius = 44
		light.squash = 0.7
		light.base_energy = 0.55
		light.glow_color = Color("ffb561")
		add_child(light)
	var body: StaticBody2D = StaticBody2D.new() ## the mound, with the opening left free (the gate is deeper in than she can walk)
	for rect: Rect2 in [Rect2(-102, -30, 80, 30), Rect2(22, -30, 80, 30), Rect2(-24, -40, 48, 14)]:
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.position + rect.size / 2.0
		body.add_child(shape)
	add_child(body)
	var gate: MineGate = MineGate.new()
	gate.position = Vector2(0, -8)
	add_child(gate)
	exit_position = global_position + Vector2(0, 16)


## E at the opening.
class MineGate:
	extends Interactable

	func prompt() -> String:
		return "BETRETEN"

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 18.0

	func prompt_position() -> Vector2:
		return Vector2(0, -50)

	func interact(player: Player) -> void:
		var mines: MineManager = get_tree().get_first_node_in_group("mines") as MineManager
		if mines == null:
			return
		if mines.unlocked_stations().is_empty():
			mines.travel(player, 1, "entry")
		else:
			LiftMenu.open(get_tree(), player, 0)
