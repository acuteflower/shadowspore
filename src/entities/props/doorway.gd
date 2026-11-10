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
var opens: bool = false ## a door to the room next door: E only opens it (and it stays open), nobody is moved
var is_open: bool = false
var blocker: CollisionShape2D ## what keeps the shut door shut
var locked_text: String = "" ## a door that cannot be opened (a room that is only there for the looks): E rattles it and she says this
var to_interior: String = "" ## a passage (the stair inside the witch's tower): E takes her into this interior ...
var to_spot: Vector2 = Vector2.ZERO ## ... to this place in it (room px) ...
var to_face: Vector2 = Vector2.DOWN ## ... looking this way
var needs: String = "" ## a quest flag of the local player that has to be set before the door answers (Ellie's door: the broom is taken)


func prompt() -> String:
	if locked or is_open:
		return ""
	if locked_text != "":
		return label
	if needs != "":
		var manager: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
		var player: Player = manager.local_player() if manager != null else null
		if player == null or player.quests == null or not player.quests.has_flag(needs):
			return ""
	return label


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - reach_radius


func prompt_position() -> Vector2:
	return Vector2(0, -prompt_height)


func interact(player: Player) -> void:
	if locked_text != "":
		_rattle(player)
		return
	if opens:
		open_now(true)
		if player.quests != null:
			player.quests.set_flag("door_open_" + interior_id) ## a saved game opens it again (Interiors)
		return
	var manager: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if manager != null and to_interior != "":
		manager.use_passage(player, self)
	elif manager != null:
		manager.use_door(player, self)


## 0 shut .. 1 wide open: the leaf squeezes towards its hinge (seen from the front it swings away).
func set_open(amount: float) -> void:
	if leaf != null:
		leaf.scale.x = lerpf(1.0, 0.16, clampf(amount, 0.0, 1.0))
		leaf.modulate = Color.WHITE.lerp(Color(0.62, 0.55, 0.62), clampf(amount, 0.0, 1.0))


## The door to the next room is open for good (`animate`: it swings with a creak, else it simply is open, as in a saved game).
func open_now(animate: bool) -> void:
	if is_open:
		return
	is_open = true
	if blocker != null:
		blocker.set_deferred("disabled", true)
	if not animate:
		set_open(1.0)
		return
	var manager: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if manager != null:
		manager.door_sound("open", -4.0)
	create_tween().tween_method(set_open, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The shut door does not give: it shudders in its frame, creaks, and she says so.
func _rattle(player: Player) -> void:
	var manager: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if manager != null:
		manager.door_sound("creak_a", -8.0)
	if leaf != null:
		var tween: Tween = create_tween()
		for k: float in [0.05, -0.04, 0.03, 0.0]:
			tween.tween_property(leaf, "skew", k, 0.05)
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null and player.is_multiplayer_authority():
		box.speak("ELLIE", locked_text)
