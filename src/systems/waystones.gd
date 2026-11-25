class_name Waystones
extends Node
## The waystones of the world (the teleport points, docs/waystones.md): which of the goddess statues have been awakened.
## Dual-mode:
## - Legacy (`WorldLevel`): reads `data/waystones.json`.
## - v2 (`ZoneWorld` / `ZoneDirector`): reads all zone `waystones` & `waystone` landmarks from `Atlas.shared()`,
##   retaining full coordinates and awakened state even while zones are unloaded!

signal awakened(id: String)

var _specs: Dictionary = {} ## id -> entry {id, name, tile: [cx, cy], zone: String, reveal: float, clear_radius: int}
var _aliases: Dictionary = {} ## alias_id -> canonical_id
var _statues: Dictionary = {} ## id -> WaystoneStatue (currently loaded in scene tree)
var _awake: Dictionary = {} ## id -> true
var _settings: Dictionary = {}
var _is_v2: bool = false


static func of(tree: SceneTree) -> Waystones:
	if tree == null:
		return null
	return tree.get_first_node_in_group("waystones") as Waystones


func _ready() -> void:
	add_to_group("waystones")
	var table: Dictionary = DataRegistry.table("waystones")
	_settings = table.get("settings", {}) as Dictionary
	var dir: ZoneDirector = _find_director()
	if dir != null and dir.atlas != null:
		load_atlas_specs(dir.atlas, dir.continent_id)
	else:
		for raw_spec: Variant in table.get("statues", []) as Array:
			if raw_spec is Dictionary:
				var spec: Dictionary = (raw_spec as Dictionary).duplicate(true)
				_specs[String(spec.get("id", ""))] = spec
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			if NetworkManager.rpc_ready(self):
				_rpc_snapshot.rpc_id(peer, PackedStringArray(_awake.keys())))


func _find_director() -> ZoneDirector:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	var dir: ZoneDirector = tree.get_first_node_in_group("zone_director") as ZoneDirector
	if dir != null:
		return dir
	if get_parent() != null:
		for child: Node in get_parent().get_children():
			if child is ZoneDirector:
				return child as ZoneDirector
	var world: Node = tree.get_first_node_in_group("world")
	if world != null and world.has_method("director"):
		var cand: Variant = world.call("director")
		if cand is ZoneDirector:
			return cand as ZoneDirector
	return null


func load_atlas_specs(atlas: Atlas, continent_id: StringName = &"main") -> void:
	if atlas == null:
		return
	_is_v2 = true
	_specs.clear()
	_aliases.clear()
	for z: Atlas.Zone in atlas.zones_of(continent_id):
		var added_in_zone: Array[String] = []
		var raw_ws: Variant = z.raw.get("waystones", [])
		if raw_ws is Array:
			for entry_v: Variant in raw_ws as Array:
				if not (entry_v is Dictionary):
					continue
				var entry: Dictionary = entry_v as Dictionary
				var wid: String = String(entry.get("id", "")).strip_edges()
				var t_var: Variant = entry.get("tile")
				if wid.is_empty() or not (t_var is Array) or (t_var as Array).size() < 2:
					continue
				var pair: Array = t_var as Array
				var pt: Vector2 = Vector2(float(pair[0]), float(pair[1]))
				if not z.bbox.grow(2.0).has_point(pt):
					pt += Vector2(z.origin)
				var spec: Dictionary = {
					"id": wid,
					"name": String(entry.get("name", z.name + "-WEGSTEIN")),
					"tile": [pt.x, pt.y],
					"zone": String(z.id),
					"reveal": float(entry.get("reveal", 16.0)),
					"clear_radius": int(entry.get("clear_radius", 5)),
					"paved": bool(entry.get("paved", false)),
				}
				_specs[wid] = spec
				added_in_zone.append(wid)
		for lm: Atlas.Landmark in z.landmarks:
			if lm.kind != &"waystone":
				continue
			var lmid: String = String(lm.id)
			if _specs.has(lmid):
				continue
			if not added_in_zone.is_empty():
				_aliases[lmid] = added_in_zone[0]
				continue
			var spec_lm: Dictionary = {
				"id": lmid,
				"name": lm.name if not lm.name.is_empty() else (z.name + "-WEGSTEIN"),
				"tile": [lm.pos.x, lm.pos.y],
				"zone": String(z.id),
				"reveal": 16.0,
				"clear_radius": 5,
				"paved": true,
			}
			_specs[lmid] = spec_lm
			added_in_zone.append(lmid)
		if not added_in_zone.is_empty():
			var primary: String = added_in_zone[0]
			_aliases[String(z.id) + "_stone"] = primary
			_aliases[String(z.id) + "_waystone"] = primary


func resolve_id(raw_id: String) -> String:
	if _specs.has(raw_id):
		return raw_id
	if _aliases.has(raw_id):
		return String(_aliases[raw_id])
	return raw_id


## Every statue of the data table (known even when its zone is unloaded).
func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: String in _specs:
		var spec: Dictionary = (_specs[id] as Dictionary).duplicate()
		spec["awake"] = _awake.has(id)
		list.append(spec)
	return list


func specs() -> Dictionary:
	return _specs


func spec_for(id: String) -> Dictionary:
	var cid: String = resolve_id(id)
	if _specs.has(cid):
		var out: Dictionary = (_specs[cid] as Dictionary).duplicate()
		out["awake"] = _awake.has(cid)
		return out
	return {}


func waystones_in_zone(zone_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var target_z: String = String(zone_id)
	for id: String in _specs:
		var spec: Dictionary = _specs[id] as Dictionary
		if String(spec.get("zone", "")) == target_z:
			var copy: Dictionary = spec.duplicate()
			copy["awake"] = _awake.has(id)
			if not copy.has("id"):
				copy["id"] = id
			out.append(copy)
	return out


func awake_waystone_in_zone(zone_id: StringName) -> Dictionary:
	for spec: Dictionary in waystones_in_zone(zone_id):
		if bool(spec.get("awake", false)):
			return spec
	return {}


func register_spec(id: String, spec: Dictionary) -> void:
	var cid: String = resolve_id(id)
	if _specs.has(cid):
		return
	_specs[id] = spec


func is_awake(id: String) -> bool:
	return _awake.has(resolve_id(id))


func awake_count() -> int:
	return _awake.size()


func statue_node(id: String) -> WaystoneStatue:
	var cid: String = resolve_id(id)
	var st: WaystoneStatue = _statues.get(cid) as WaystoneStatue
	return st if (st != null and is_instance_valid(st)) else null


func arrival_position(id: String) -> Vector2:
	var st: WaystoneStatue = statue_node(id)
	if st != null:
		return st.global_position + Vector2(0.0, 28.0)
	var cid: String = resolve_id(id)
	if not _specs.has(cid):
		return Vector2.INF
	var spec: Dictionary = _specs[cid] as Dictionary
	var tile: Variant = spec.get("tile")
	if tile is Array and (tile as Array).size() >= 2:
		var arr: Array = tile as Array
		return Atlas.px_of(Vector2(float(arr[0]), float(arr[1]))) + Vector2(8.0, 28.0)
	return Vector2.INF


func zone_of(id: String) -> StringName:
	var cid: String = resolve_id(id)
	if _specs.has(cid):
		return StringName(String((_specs[cid] as Dictionary).get("zone", "")))
	return &""


## Ensures the destination waystone's zone is loaded on both Host and local ZoneDirector before teleporting.
func request_prepare_zone(id: String) -> void:
	var cid: String = resolve_id(id)
	if cid.is_empty():
		return
	_prepare_zone_local(cid)
	if not multiplayer.is_server() and NetworkManager.rpc_ready(self):
		_rpc_prepare_zone.rpc_id(1, cid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_prepare_zone(id: String) -> void:
	if not multiplayer.is_server():
		return
	var cid: String = resolve_id(id)
	if not _awake.has(cid):
		return
	_prepare_zone_local(cid)


func _prepare_zone_local(cid: String) -> void:
	var zid: StringName = zone_of(cid)
	if zid == &"":
		return
	var dir: ZoneDirector = _find_director()
	if dir != null and not dir.is_loaded(zid):
		dir.load_now(zid)


## Local player: E at an awakened statue: she walks up, touches it and chooses where to go on the map (`WaystoneTravel`).
func begin_travel(player: Player, statue: WaystoneStatue) -> void:
	if player.get_node_or_null("WaystoneTravel") != null or player.is_busy():
		return
	var travel: WaystoneTravel = WaystoneTravel.new()
	travel.name = "WaystoneTravel"
	player.add_child(travel)
	travel.start(player, statue)


func register(statue: WaystoneStatue) -> void:
	var cid: String = resolve_id(statue.id)
	if cid != statue.id and _specs.has(cid):
		statue.id = cid
	_statues[statue.id] = statue
	var bound_id: String = statue.id
	statue.tree_exiting.connect(func() -> void:
		if _statues.get(bound_id) == statue:
			_statues.erase(bound_id))
	if _awake.has(statue.id):
		statue.set_awake_instant()


# ---------------------------------------------------------------- activating

## Local player: E at a dormant statue.
func request_activate(id: String) -> void:
	var cid: String = resolve_id(id)
	if multiplayer.is_server():
		_host_activate(cid, multiplayer.get_unique_id())
	elif NetworkManager.rpc_ready(self):
		_rpc_request.rpc_id(1, cid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(id: String) -> void:
	if multiplayer.is_server():
		_host_activate(resolve_id(id), multiplayer.get_remote_sender_id())


func _host_activate(id: String, peer: int) -> void:
	var cid: String = resolve_id(id)
	if not _specs.has(cid) or _awake.has(cid):
		return
	var statue: WaystoneStatue = statue_node(cid)
	if statue == null:
		return
	var who: Player = null
	for player: Player in Player.all:
		if player.name == str(peer):
			who = player
	if who == null or who.health.current <= 0.0:
		return
	if who.global_position.distance_to(statue.global_position) > float(_settings.get("reach", 46.0)) + 40.0:
		return
	_awake[cid] = true
	if NetworkManager.rpc_ready(self):
		_rpc_awakened.rpc(cid, peer)
	else:
		_rpc_awakened(cid, peer)
	var spec: Dictionary = _specs[cid] as Dictionary
	var tile: Array = spec.tile as Array
	var delay: float = float(_settings.get("reveal_delay", 5.6))
	get_tree().create_timer(delay).timeout.connect(func() -> void: _reveal(Vector2(float(tile[0]), float(tile[1])), float(spec.get("reveal", 15.0))))


func _reveal(tile: Vector2, cells: float) -> void:
	if not is_inside_tree():
		return
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(tile, cells)


@rpc("authority", "call_local", "reliable")
func _rpc_awakened(id: String, peer: int) -> void:
	var cid: String = resolve_id(id)
	_awake[cid] = true
	var statue: WaystoneStatue = statue_node(cid)
	if statue != null:
		statue.awaken()
	if peer == multiplayer.get_unique_id() and statue != null and _specs.has(cid):
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.get_node_or_null("WaystoneScene") == null:
				var scene: WaystoneScene = WaystoneScene.new()
				scene.name = "WaystoneScene"
				player.add_child(scene)
				scene.start(player, statue, _specs[cid] as Dictionary)
				break
	awakened.emit(cid)


@rpc("authority", "reliable")
func _rpc_snapshot(ids: PackedStringArray) -> void:
	_apply_awake(ids)


func _apply_awake(ids: PackedStringArray) -> void:
	for raw_id: String in ids:
		var cid: String = resolve_id(raw_id)
		_awake[cid] = true
		var statue: WaystoneStatue = statue_node(cid)
		if statue != null and not statue.awake:
			statue.set_awake_instant()


# ---------------------------------------------------------------- save file

func export_state() -> Dictionary:
	return {"awake": _awake.keys()}


func import_state(data: Dictionary) -> void:
	var ids: PackedStringArray = PackedStringArray()
	for id: Variant in SaveGame.as_array(data.get("awake")):
		ids.append(resolve_id(String(id)))
	_apply_awake(ids)
	if multiplayer.is_server() and NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(ids)
