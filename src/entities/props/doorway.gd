class_name Doorway
extends Interactable
## A way in or out (E): the hut's front door outside (`leaving` false, takes you into the interior `interior_id`), the door inside (`leaving` true, takes
## you out). `Interiors.use_door` plays the transition. `leaf` is the door's sprite, hinged on its left edge: `set_open` swings it.

var interior_id: String = ""
var leaving: bool = false
var label: String = "BETRETEN"
var leaf: Sprite2D
var reach_radius: float = 8.0
var prompt_height: float = 30.0
var locked: bool = false ## something is in the way (the board before the cabin's door): no prompt, no E


func prompt() -> String:
	return "" if locked else label


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - reach_radius


func prompt_position() -> Vector2:
	return Vector2(0, -prompt_height)


func interact(player: Player) -> void:
	var manager: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if manager != null:
		manager.use_door(player, self)


## 0 shut .. 1 wide open: the leaf squeezes towards its hinge (seen from the front it swings away).
func set_open(amount: float) -> void:
	if leaf != null:
		leaf.scale.x = lerpf(1.0, 0.16, clampf(amount, 0.0, 1.0))
		leaf.modulate = Color.WHITE.lerp(Color(0.62, 0.55, 0.62), clampf(amount, 0.0, 1.0))
