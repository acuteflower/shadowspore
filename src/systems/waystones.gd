class_name Waystones
extends Node
## The waystones of the world (the teleport points, docs/waystones.md): which of the goddess statues have been awakened. Shared by everybody, host-authoritative:
## the player presses E at a statue (`WaystoneStatue.interact` -> `request_activate`), the host checks the reach, marks it awake, tells everyone to play the
## awakening (`_rpc_awakened`: every peer runs the animation, the one who pressed E also gets the camera scene) and, when the light has run over the statue,
## reveals the map round it (`MapDiscovery.reveal_disc`, so the map window shows the fog lifting). A joining peer gets the table, the save file keeps it (`"waystones"`).
## Data: data/waystones.json (settings + statues {id, name, tile, reveal (map cells), clear_radius}). Travelling between statues is not built yet.

signal awakened(id: String)

var _specs: Dictionary = {} ## id -> entry of data/waystones.json
var _statues: Dictionary = {} ## id -> WaystoneStatue
var _awake: Dictionary = {} ## id -> true
var _settings: Dictionary = {}


static func of(tree: SceneTree) -> Waystones:
	return tree.get_first_node_in_group("waystones") as Waystones


func _ready() -> void:
	add_to_group("waystones")
	var table: Dictionary = DataRegistry.table("waystones")
	_settings = table.get("settings", {}) as Dictionary
	for spec: Dictionary in table.get("statues", []) as Array:
		_specs[String(spec.id)] = spec
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void: _rpc_snapshot.rpc_id(peer, PackedStringArray(_awake.keys())))


## Every statue of the data table (what the map draws and a travel menu will list later).
func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: String in _specs:
		var spec: Dictionary = (_specs[id] as Dictionary).duplicate()
		spec["awake"] = _awake.has(id)
		list.append(spec)
	return list


func specs() -> Dictionary:
	return _specs


func is_awake(id: String) -> bool:
	return _awake.has(id)


func awake_count() -> int:
	return _awake.size()


func statue_node(id: String) -> WaystoneStatue:
	return _statues.get(id) as WaystoneStatue


## Local player: E at an awakened statue: she walks up, touches it and chooses where to go on the map (`WaystoneTravel`).
func begin_travel(player: Player, statue: WaystoneStatue) -> void:
	if player.get_node_or_null("WaystoneTravel") != null or player.is_busy():
		return
	var travel: WaystoneTravel = WaystoneTravel.new()
	travel.name = "WaystoneTravel"
	player.add_child(travel)
	travel.start(player, statue)


func register(statue: WaystoneStatue) -> void:
	_statues[statue.id] = statue
	if _awake.has(statue.id):
		statue.set_awake_instant()


# ---------------------------------------------------------------- activating

## Local player: E at a dormant statue.
func request_activate(id: String) -> void:
	if multiplayer.is_server():
		_host_activate(id, multiplayer.get_unique_id())
	else:
		_rpc_request.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(id: String) -> void:
	if multiplayer.is_server():
		_host_activate(id, multiplayer.get_remote_sender_id())


func _host_activate(id: String, peer: int) -> void:
	if not _specs.has(id) or _awake.has(id) or not _statues.has(id):
		return
	var statue: WaystoneStatue = _statues[id] as WaystoneStatue
	var who: Player = null
	for player: Player in Player.all:
		if player.name == str(peer):
			who = player
	if who == null or who.health.current <= 0.0:
		return
	if who.global_position.distance_to(statue.global_position) > float(_settings.get("reach", 46.0)) + 40.0:
		return
	_awake[id] = true
	_rpc_awakened.rpc(id, peer)
	var spec: Dictionary = _specs[id] as Dictionary
	var tile: Array = spec.tile as Array
	var delay: float = float(_settings.get("reveal_delay", 5.6))
	get_tree().create_timer(delay).timeout.connect(func() -> void: _reveal(Vector2(float(tile[0]), float(tile[1])), float(spec.get("reveal", 15.0))))


func _reveal(tile: Vector2, cells: float) -> void:
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(tile, cells)


@rpc("authority", "call_local", "reliable")
func _rpc_awakened(id: String, peer: int) -> void:
	_awake[id] = true
	var statue: WaystoneStatue = _statues.get(id) as WaystoneStatue
	if statue != null:
		statue.awaken()
	if peer == multiplayer.get_unique_id() and statue != null:
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.get_node_or_null("WaystoneScene") == null:
				var scene: WaystoneScene = WaystoneScene.new()
				scene.name = "WaystoneScene"
				player.add_child(scene)
				scene.start(player, statue, _specs[id] as Dictionary)
				break
	awakened.emit(id)


@rpc("authority", "reliable")
func _rpc_snapshot(ids: PackedStringArray) -> void:
	_apply_awake(ids)


func _apply_awake(ids: PackedStringArray) -> void:
	for id: String in ids:
		_awake[id] = true
		var statue: WaystoneStatue = _statues.get(id) as WaystoneStatue
		if statue != null and not statue.awake:
			statue.set_awake_instant()


# ---------------------------------------------------------------- save file

func export_state() -> Dictionary:
	return {"awake": _awake.keys()}


func import_state(data: Dictionary) -> void:
	var ids: PackedStringArray = PackedStringArray()
	for id: Variant in data.get("awake", []) as Array:
		ids.append(String(id))
	_apply_awake(ids)
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(ids)
