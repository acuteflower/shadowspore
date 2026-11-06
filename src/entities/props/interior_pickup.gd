class_name InteriorPickup
extends Interactable
## Something in a room that can be taken away (the hut's glowing mushrooms; data/interiors.json props `pickup` {item, amounts [per picture frame], step, flag, all_flag}). It only
## speaks while the local player's quest step is `step`: E bends her down (the picking animation), at the grab the prop is gone (a puff of spores), the items go into her bag and the
## quest flag `flag` is set; when every pickup of the room is gone `all_flag` is set (the task "remove the mushrooms"). A saved game hides the taken ones (`WorldLevel.resume_story`).

var interior: Interior
var prop_id: String = ""
var spec: Dictionary = {}
var amount: int = 1
var gone: bool = false


func setup(room: Interior, id: String, at: Vector2, data: Dictionary, frame: int) -> void:
	interior = room
	prop_id = id
	spec = data
	position = at
	var amounts: Array = data.get("amounts", [1]) as Array
	amount = int(amounts[clampi(frame, 0, amounts.size() - 1)])
	name = "Pickup_" + id


func prompt() -> String:
	var player: Player = _local_player()
	if gone or player == null or player.quests == null or player.story_lock or InputManager.ui_blocking:
		return ""
	if String(player.quests.current().get("step_id", "")) != String(spec.get("step", "")) or player.quests.has_flag(String(spec.flag)):
		return ""
	return "ENTFERNEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 10.0


func prompt_position() -> Vector2:
	return Vector2(0, -26)


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


func interact(player: Player) -> void:
	set_focused(false)
	player.begin_pick((global_position - player.global_position).normalized(), _take.bind(player))


## Already taken in a saved game: the prop is gone, nothing is given.
func apply_gone() -> void:
	gone = true
	interior.hide_prop(prop_id)


func _take(player: Player) -> void:
	if gone:
		return
	gone = true
	interior.hide_prop(prop_id)
	ShockRing.burst(interior, position + Vector2(0, -6), 14.0, 0.2)
	var spores: CPUParticles2D = CPUParticles2D.new() ## a puff of glowing spores
	spores.position = position + Vector2(0, -8)
	spores.one_shot = true
	spores.emitting = true
	spores.amount = 14
	spores.lifetime = 1.2
	spores.explosiveness = 0.9
	spores.direction = Vector2(0, -1)
	spores.spread = 70.0
	spores.gravity = Vector2(0, -6)
	spores.initial_velocity_min = 8.0
	spores.initial_velocity_max = 22.0
	spores.color = Color("78f4e6")
	spores.material = Unlit.material()
	spores.z_index = 3
	interior.add_child(spores)
	get_tree().create_timer(1.6).timeout.connect(spores.queue_free)
	player.inventory.give(String(spec.item), amount)
	if player.quests != null:
		player.quests.set_flag(String(spec.flag))
		var all: bool = true
		for node: Interactable in interior.pickups:
			if not player.quests.has_flag(String((node as InteriorPickup).spec.flag)):
				all = false
		if all and spec.has("all_flag"):
			player.quests.set_flag(String(spec.all_flag))
