class_name WaystoneTravel
extends Node
## Travelling from an awakened waystone (a child of the player, local only; E at the statue): she walks up close to the statue, lays both palms on it (the same
## touch animation as when it was woken), the map opens in travel mode (`MapWindow.open_travel`: the other awakened statues are highlighted, holding the mouse or E
## on one chooses it). Chosen: the statue flares, the screen floods with light, she is set down in front of the other statue and the light recedes. Closing the
## map without choosing just lets her step back. The teleport itself is the owner moving herself (`Player.request_teleport`, the synchronizer tells the others).

const ARRIVE: Vector2 = Vector2(0, 28) ## where she stands in front of the destination (the plinth's collision ends about 9 px south of its middle)
const APPROACH: Vector2 = Vector2(0, 15)

var _done: bool = false
var _chosen: String = ""


func start(player: Player, statue: WaystoneStatue) -> void:
	var manager: Waystones = Waystones.of(get_tree())
	player.story_lock = true
	player.auto_walk = statue.global_position + APPROACH
	player.auto_walk_factor = 0.5
	var waited: float = 0.0
	while waited < 3.0 and is_instance_valid(player) and player.global_position.distance_to(player.auto_walk) > 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not is_instance_valid(player):
		queue_free()
		return
	player.auto_walk = Vector2.INF
	player.auto_walk_factor = -1.0
	player.velocity = Vector2.ZERO
	player.begin_touch((statue.global_position + Vector2(0, -8) - player.global_position).normalized(), Callable())
	await get_tree().create_timer(0.55).timeout
	statue.flare(0.5)
	var map: MapWindow = get_tree().get_first_node_in_group("map_window") as MapWindow
	if map == null or not is_instance_valid(player) or not map.open_travel(statue.id):
		_finish(player)
		return
	map.travel_chosen.connect(_on_chosen)
	map.travel_cancelled.connect(_on_cancelled)
	while not _done and is_instance_valid(player):
		await get_tree().process_frame
	if map.travel_chosen.is_connected(_on_chosen):
		map.travel_chosen.disconnect(_on_chosen)
	if map.travel_cancelled.is_connected(_on_cancelled):
		map.travel_cancelled.disconnect(_on_cancelled)
	var target: WaystoneStatue = manager.statue_node(_chosen) if manager != null else null
	if _chosen == "" or target == null or not is_instance_valid(player):
		_finish(player)
		return
	# the light takes her
	player.release_touch()
	statue.flare(1.0)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 96
	var flood: ColorRect = ColorRect.new()
	flood.color = Color(0.85, 1.0, 0.97, 0.0)
	flood.set_anchors_preset(Control.PRESET_FULL_RECT)
	flood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flood)
	add_child(layer)
	var fade_in: Tween = create_tween().set_ignore_time_scale(true)
	fade_in.tween_property(flood, "color:a", 1.0, 0.7)
	await fade_in.finished
	player.request_teleport(target.global_position + ARRIVE)
	var settle: Tween = create_tween().set_ignore_time_scale(true)
	settle.tween_property(flood, "color", Color(0.03, 0.02, 0.07, 1.0), 0.5)
	await settle.finished
	await get_tree().create_timer(0.9).timeout ## the world streams in round the new place
	target.flare(0.9)
	var fade_out: Tween = create_tween().set_ignore_time_scale(true)
	fade_out.tween_property(flood, "color:a", 0.0, 1.0)
	await fade_out.finished
	_finish(player)


func _on_chosen(_from: String, to: String) -> void:
	_chosen = to
	_done = true


func _on_cancelled() -> void:
	_done = true


func _finish(player: Player) -> void:
	if is_instance_valid(player):
		player.release_touch()
		player.story_lock = false
		player.auto_walk = Vector2.INF
		player.auto_walk_factor = -1.0
	queue_free()
