class_name BenchSeat
extends SeatSpot
## One of the places on a bench of the town (data `seats` [[x, y, sector]] of the piece, mirrored with the piece). `TownManager` makes them for every finished bench on every
## peer under `Town/Seats`, so the host can find a seat that a remote player asks for even when the bench's picture is not loaded there.

var manager: TownManager
var structure_id: int = -1
var index: int = 0


func setup(owner_manager: TownManager, id: int, seat_index: int) -> void:
	manager = owner_manager
	structure_id = id
	index = seat_index
	name = "Seat_%d_%d" % [id, seat_index]
	label = "HINSETZEN"
	radius = 14.0
	height = 30.0
	refresh()


func _entry() -> Array:
	var data: Dictionary = manager.structures[structure_id] as Dictionary
	var seats: Array = TownRules.piece(String(data.p)).get("seats", []) as Array
	return seats[index] as Array


func refresh() -> void:
	if manager == null or not manager.structures.has(structure_id):
		return
	var data: Dictionary = manager.structures[structure_id] as Dictionary
	var entry: Array = _entry()
	var flip: float = -1.0 if int(data.get("f", 0)) == 1 else 1.0
	position = Vector2(float(data.x) + float(entry[0]) * flip, float(data.y) + float(entry[1]))


func sit_sector() -> int:
	var data: Dictionary = manager.structures[structure_id] as Dictionary
	var sector: int = int(_entry()[2])
	if int(data.get("f", 0)) == 1: ## mirrored piece: east and west swap
		sector = (8 - sector) % 8
	return sector


func seat_position() -> Vector2:
	return global_position + Vector2(0.0, -3.0)


func approach_position() -> Vector2:
	return seat_position() + Vector2(0.0, 13.0)


func usable_by(player: Player) -> bool:
	return super.usable_by(player) and manager != null and manager.is_built(structure_id)


func regen_rate() -> float:
	var cfg: Dictionary = TownRules.config().get("rest", {}) as Dictionary
	return float(cfg.get("rate", 0.4)) if manager.light_depth(global_position) > 0.0 else 0.0


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.health.current <= 0.0 or player.intro != null or player.story_lock or player.fainting or InputManager.ui_blocking or manager == null or not manager.is_built(structure_id):
		return ""
	return "HINSETZEN" if not occupied() else ""


func interact(player: Player) -> void:
	if not player.is_multiplayer_authority() or prompt() == "":
		return
	(player.get_node("RestComponent") as RestComponent).request_sit(self)
