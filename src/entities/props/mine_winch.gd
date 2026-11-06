class_name MineWinch
extends Interactable
## The lift of a level's rest room. It starts broken (the rope jams): E mends it with the picking animation (the host writes `station:<level>` into the mine's
## table, so it stays and is saved). Afterwards E opens the `LiftMenu`: up to the gate or down/up to every other mended lift.

var level: int = 1


func _mines() -> MineManager:
	return get_tree().get_first_node_in_group("mines") as MineManager


func prompt() -> String:
	var mines: MineManager = _mines()
	return "AUFZUG BENUTZEN" if mines != null and mines.station_unlocked(level) else "AUFZUG INSTANDSETZEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 26.0


func prompt_position() -> Vector2:
	return Vector2(0, -52)


func interact(player: Player) -> void:
	var mines: MineManager = _mines()
	if mines == null:
		return
	if mines.station_unlocked(level):
		LiftMenu.open(get_tree(), player, level)
		return
	player.begin_pick((global_position - player.global_position).normalized(), func() -> void:
		mines.request_station(level)
		var puff: CPUParticles2D = CPUParticles2D.new() ## the rope frees itself: a cloud of dust and rust
		puff.one_shot = true
		puff.emitting = true
		puff.amount = 18
		puff.lifetime = 0.9
		puff.explosiveness = 0.9
		puff.direction = Vector2.UP
		puff.spread = 70.0
		puff.gravity = Vector2(0, 60)
		puff.initial_velocity_min = 14.0
		puff.initial_velocity_max = 36.0
		puff.color = Color(0.72, 0.62, 0.55, 0.8)
		puff.position = Vector2(0, -30)
		add_child(puff)
		get_tree().create_timer(1.5).timeout.connect(puff.queue_free))
