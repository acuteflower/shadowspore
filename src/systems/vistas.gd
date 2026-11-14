class_name Vistas
extends Node
## The panoramic cliff-edge resting places of the meadow biome (`docs/wiesenbiom_ausbau_konzept.md` Stufe 1, `data/vistas.json`).
## Shared by all players, host-authoritative: when someone sits quietly at a `VistaPoint` (`VistaPoint.rest_tick`), the host marks it
## discovered, lifts a wide valley disc in `MapDiscovery` (`reveal_disc`), grants the first-time discovery XP, and broadcasts `_rpc_discovered`
## so every peer records the vista on the map and the sitting player hears the chime + sees the valley banner. Saved as `"vistas"` in `SaveGame`.

signal discovered(id: String)

var _specs: Dictionary = {} ## id -> Dictionary from data/vistas.json
var _points: Dictionary = {} ## id -> VistaPoint
var _seen: Dictionary = {} ## id -> true
var _settings: Dictionary = {}
var _banner: TownBanner


static func of(tree: SceneTree) -> Vistas:
	return tree.get_first_node_in_group("vistas") as Vistas


func _ready() -> void:
	add_to_group("vistas")
	var table: Dictionary = DataRegistry.table("vistas")
	_settings = table.get("settings", {}) as Dictionary
	for entry: Variant in table.get("vistas", []) as Array:
		var spec: Dictionary = entry as Dictionary
		_specs[String(spec.id)] = spec
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			_rpc_snapshot.rpc_id(peer, PackedStringArray(_seen.keys())))


func settings() -> Dictionary:
	return _settings


func specs() -> Dictionary:
	return _specs


func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: String in _specs:
		var spec: Dictionary = (_specs[id] as Dictionary).duplicate()
		spec["seen"] = _seen.has(id)
		list.append(spec)
	return list


func is_discovered(id: String) -> bool:
	return _seen.has(id)


func discovered_count() -> int:
	return _seen.size()


func point_node(id: String) -> VistaPoint:
	return _points.get(id) as VistaPoint


func register(point: VistaPoint) -> void:
	_points[point.vista_id] = point
	point.set_discovered_visual(_seen.has(point.vista_id))


## Host only: called from `VistaPoint.rest_tick` once a player has sat quietly past `reveal_delay`.
func host_discover(id: String, player: Player) -> void:
	if not multiplayer.is_server() or not _specs.has(id) or _seen.has(id):
		return
	var point: VistaPoint = _points.get(id) as VistaPoint
	if point == null or player == null or player.health.current <= 0.0:
		return
	_seen[id] = true
	var spec: Dictionary = _specs[id] as Dictionary
	var tile_arr: Array = spec.tile as Array
	var base_tile: Vector2 = Vector2(float(tile_arr[0]), float(tile_arr[1]))
	var shift: float = float(_settings.get("reveal_shift_tiles", 16.0))
	var focus_tile: Vector2 = (base_tile + point.sit_direction() * shift).clamp(
		Vector2.ZERO, Vector2.ONE * float(RegionMap.WORLD_TILES - 1)
	)
	var cells: float = float(spec.get("reveal_cells", _settings.get("reveal_cells", 22.0)))
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(focus_tile, cells)
	var xp_reward: int = int(spec.get("xp_reward", _settings.get("xp_reward", 12)))
	if xp_reward > 0 and player.progress != null:
		player.progress.award(0, xp_reward)
	var peer_id: int = player.name.to_int()
	_rpc_discovered.rpc(id, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_discovered(id: String, peer_id: int) -> void:
	_seen[id] = true
	var point: VistaPoint = _points.get(id) as VistaPoint
	if point != null:
		point.set_discovered_visual(true)
		point.play_discovery_fx()
	discovered.emit(id)
	if multiplayer.get_unique_id() == peer_id and _specs.has(id):
		var spec: Dictionary = _specs[id] as Dictionary
		_show_banner(String(spec.get("name", "AUSSICHTSPUNKT")), String(spec.get("sub", "NEUER WEITBLICK")))


@rpc("authority", "reliable")
func _rpc_snapshot(ids: PackedStringArray) -> void:
	_seen.clear()
	for id: String in ids:
		_seen[id] = true
	for id: String in _points:
		(_points[id] as VistaPoint).set_discovered_visual(_seen.has(id))


func export_state() -> Array:
	return _seen.keys()


func import_state(saved: Variant) -> void:
	_seen.clear()
	if saved is Array:
		for entry: Variant in saved as Array:
			_seen[String(entry)] = true
	elif saved is Dictionary:
		for key: Variant in (saved as Dictionary).keys():
			if bool((saved as Dictionary)[key]):
				_seen[String(key)] = true
	for id: String in _points:
		(_points[id] as VistaPoint).set_discovered_visual(_seen.has(id))
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(PackedStringArray(_seen.keys()))


func _show_banner(title: String, sub: String) -> void:
	if _banner == null:
		_banner = TownBanner.new()
		add_child(_banner)
	_banner.show_banner({
		"header": "AUSSICHT ENTDECKT",
		"title": title,
		"sub": sub,
		"color": Color("243b4a"),
		"emblem": -1,
	})
	if ResourceLoader.exists("res://assets/audio/vistas/chime.wav"):
		var audio: AudioStreamPlayer = AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/vistas/chime.wav") as AudioStream
		audio.volume_db = -5.5
		audio.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		add_child(audio)
		audio.finished.connect(audio.queue_free)
		audio.play()
