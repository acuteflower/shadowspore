class_name MeadowPois
extends Node2D
## Chunk-streamed, host-authoritative manager for the meadow's story & water POIs (`docs/wiesenbiom_ausbau_konzept.md` Stufen 3 & 4):
##  - Stage 3 (`red_order`): `OrderMonument` (`watchtower`, `patrol_camp`, `boundary_stone`) — Valdrics Vergangenheit
##  - Stage 4 (`water_works`): `OldWatermill`, `BrokenStoneBridge`, `FisherPier` + `ReedRowboatSpot`
## Also registers in `Terrain.patches` AFTER `WorldRivers` and exposes `has_water_deck_at(world_pos)` so players walk dry
## across broken stone bridge abutments (`"stone"`) and wooden lakeside fishing piers (`"wood"`) without sinking or swimming!
## Saved under `"meadow_pois"` in `SaveGame`.

const DROP_SCENE: String = "res://src/entities/drops/item_drop.tscn"

var world: WorldLevel
var _sites_by_chunk: Dictionary = {} ## Vector2i(chunk) -> Array[Dictionary]
var _live_chunks: Dictionary = {} ## Vector2i(chunk) -> Array[Node]
var _live_bridges: Array[BrokenStoneBridge] = []
var _live_piers: Array[FisherPier] = []

var _discovered_order: Dictionary = {} ## String(poi_id) -> true
var _unjammed_mills: Dictionary = {} ## String(mill_id) -> true
var _searched_boats: Dictionary = {} ## String(pier_id) -> true

var _order_spots: Array[Vector2i] = []
var _mill_spots: Array[Vector2i] = []
var _bridge_spots: Array[Vector2i] = []
var _pier_spots: Array[Vector2i] = []

var _order_xp: int = 12
var _order_reveal: float = 11.0
var _drop_serial: int = 0
var _banner: TownBanner


static func of(tree: SceneTree) -> MeadowPois:
	return tree.get_first_node_in_group("meadow_pois") as MeadowPois


func _ready() -> void:
	add_to_group("meadow_pois")
	Terrain.patches.append(self)
	tree_exiting.connect(func() -> void: Terrain.patches.erase(self))
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			_rpc_snapshot.rpc_id(
				peer,
				PackedStringArray(_discovered_order.keys()),
				PackedStringArray(_unjammed_mills.keys()),
				PackedStringArray(_searched_boats.keys())
			))


func order_tiles() -> Array[Vector2i]:
	return _order_spots


func mill_tiles() -> Array[Vector2i]:
	return _mill_spots


func bridge_tiles() -> Array[Vector2i]:
	return _bridge_spots


func pier_tiles() -> Array[Vector2i]:
	return _pier_spots


func has_progress() -> bool:
	return not _discovered_order.is_empty() or not _unjammed_mills.is_empty() or not _searched_boats.is_empty()


func is_order_discovered(poi_id: String) -> bool:
	return _discovered_order.has(poi_id)


func is_mill_unjammed(mill_id: String) -> bool:
	return _unjammed_mills.has(mill_id)


func is_boat_searched(pier_id: String) -> bool:
	return _searched_boats.has(pier_id)


func setup(level: WorldLevel) -> Dictionary:
	world = level
	_sites_by_chunk.clear()
	_order_spots.clear()
	_mill_spots.clear()
	_bridge_spots.clear()
	_pier_spots.clear()
	var blocked: Dictionary = {}
	var table: Dictionary = DataRegistry.table("meadow_pois")
	var red_order: Dictionary = table.get("red_order", {}) as Dictionary
	_order_xp = int(red_order.get("xp_reward", 12))
	_order_reveal = float(red_order.get("reveal_cells", 11.0))

	for wt_v: Variant in red_order.get("watchtowers", []) as Array:
		var wt: Dictionary = wt_v as Dictionary
		var t_wt: Vector2i = _tile_of(wt)
		_order_spots.append(t_wt)
		_add_site(t_wt, {"group": "order", "subkind": "watchtower", "spec": wt, "tile": t_wt})
		_mark_square(blocked, t_wt, 5)

	for cp_v: Variant in red_order.get("patrol_camps", []) as Array:
		var cp: Dictionary = cp_v as Dictionary
		var t_cp: Vector2i = _tile_of(cp)
		_order_spots.append(t_cp)
		_add_site(t_cp, {"group": "order", "subkind": "patrol_camp", "spec": cp, "tile": t_cp})
		_mark_square(blocked, t_cp, 4)

	for bs_v: Variant in red_order.get("boundary_stones", []) as Array:
		var bs: Dictionary = bs_v as Dictionary
		var t_bs: Vector2i = _tile_of(bs)
		_order_spots.append(t_bs)
		_add_site(t_bs, {"group": "order", "subkind": "boundary_stone", "spec": bs, "tile": t_bs})
		_mark_square(blocked, t_bs, 2)

	var water_works: Dictionary = table.get("water_works", {}) as Dictionary
	for ml_v: Variant in water_works.get("watermills", []) as Array:
		var ml: Dictionary = ml_v as Dictionary
		var t_ml: Vector2i = _tile_of(ml)
		_mill_spots.append(t_ml)
		_add_site(t_ml, {"group": "watermill", "spec": ml, "tile": t_ml})
		_mark_square(blocked, t_ml, 6)

	for br_v: Variant in water_works.get("broken_bridges", []) as Array:
		var br: Dictionary = br_v as Dictionary
		var t_br: Vector2i = _tile_of(br)
		_bridge_spots.append(t_br)
		_add_site(t_br, {"group": "bridge", "spec": br, "tile": t_br})
		_mark_square(blocked, t_br, 5)
		if br.has("neg_bank"):
			var nb: Array = br.neg_bank as Array
			_mark_square(blocked, Vector2i(int(nb[0]), int(nb[1])), 3)
		if br.has("pos_bank"):
			var pb: Array = br.pos_bank as Array
			_mark_square(blocked, Vector2i(int(pb[0]), int(pb[1])), 3)

	for pr_v: Variant in water_works.get("fisher_piers", []) as Array:
		var pr: Dictionary = pr_v as Dictionary
		var t_pr: Vector2i = _tile_of(pr)
		_pier_spots.append(t_pr)
		_add_site(t_pr, {"group": "pier", "spec": pr, "tile": t_pr})
		_mark_square(blocked, t_pr, 3)
		if pr.has("boat_tile"):
			var bt: Array = pr.boat_tile as Array
			_mark_square(blocked, Vector2i(int(bt[0]), int(bt[1])), 2)

	return blocked


static func _tile_of(spec: Dictionary) -> Vector2i:
	var arr: Array = spec.get("tile", [0, 0]) as Array
	return Vector2i(int(arr[0]), int(arr[1]))


static func _mark_square(blocked: Dictionary, center: Vector2i, rad: int) -> void:
	for dy: int in range(-rad, rad + 1):
		for dx: int in range(-rad, rad + 1):
			blocked[center + Vector2i(dx, dy)] = true


func _add_site(tile: Vector2i, entry: Dictionary) -> void:
	var chunk_cell: Vector2i = tile / WorldLevel.CHUNK
	(_sites_by_chunk.get_or_add(chunk_cell, []) as Array).append(entry)


func surface_at(world_pos: Vector2) -> String:
	for br: BrokenStoneBridge in _live_bridges:
		if is_instance_valid(br) and br.contains_deck_point(world_pos):
			return "stone"
	for pr: FisherPier in _live_piers:
		if is_instance_valid(pr) and pr.contains_deck_point(world_pos):
			return "wood"
	return ""


func has_water_deck_at(world_pos: Vector2) -> bool:
	return surface_at(world_pos) != ""


func populate_chunk(chunk_cell: Vector2i) -> void:
	if _live_chunks.has(chunk_cell) or not _sites_by_chunk.has(chunk_cell):
		return
	var spawned: Array[Node] = []
	var props_parent: Node2D = world._props if world != null and world._props != null else self
	var chests: LootChests = LootChests.of(get_tree())

	for entry_v: Variant in _sites_by_chunk[chunk_cell] as Array:
		var entry: Dictionary = entry_v as Dictionary
		var grp: String = String(entry.group)
		var spec: Dictionary = entry.spec as Dictionary
		var tile: Vector2i = entry.tile as Vector2i
		var pos_px: Vector2 = Vector2(tile) * 16.0 + Vector2(8.0, 8.0)

		match grp:
			"order":
				var subkind: String = String(entry.subkind)
				var pid: String = String(spec.get("id", ""))
				var mon: OrderMonument = OrderMonument.new()
				mon.name = "Order_" + pid
				mon.setup(self, subkind, spec, pos_px)
				mon.discovered = _discovered_order.has(pid)
				props_parent.add_child(mon)
				spawned.append(mon)
				var c_tier: String = String(spec.get("chest_tier", ""))
				if c_tier != "" and chests != null:
					var co: Array = spec.get("chest_offset", [-28, 14]) as Array
					var chest_pos: Vector2 = pos_px + Vector2(float(co[0]), float(co[1]))
					var chest_id: String = pid + "_chest"
					chests.place(chest_id, c_tier, chest_pos, float(co[0]) > 0.0)
					if multiplayer.is_server() and pid == "order_tower_nordgrat" and not chests.is_open(chest_id) and DataRegistry.table("items").has("order_signet"):
						chests.add_extra(chest_id, [{"id": "order_signet", "count": 1}])
			"watermill":
				var mid: String = String(spec.get("id", ""))
				var mill: OldWatermill = OldWatermill.new()
				mill.name = "Watermill_" + mid
				mill.setup(self, spec, pos_px)
				props_parent.add_child(mill)
				if _unjammed_mills.has(mid):
					mill.set_unjammed_instant(true)
				spawned.append(mill)
			"bridge":
				var bid: String = String(spec.get("id", ""))
				var bridge: BrokenStoneBridge = BrokenStoneBridge.new()
				bridge.name = "BrokenBridge_" + bid
				bridge.setup(spec)
				add_child(bridge)
				_live_bridges.append(bridge)
				spawned.append(bridge)
			"pier":
				var prid: String = String(spec.get("id", ""))
				var pier: FisherPier = FisherPier.new()
				pier.name = "FisherPier_" + prid
				pier.setup(self, spec)
				pier.boat_searched = _searched_boats.has(prid)
				add_child(pier)
				_live_piers.append(pier)
				spawned.append(pier)

	_live_chunks[chunk_cell] = spawned


func free_chunk(chunk_cell: Vector2i) -> void:
	if not _live_chunks.has(chunk_cell):
		return
	var list: Array = _live_chunks[chunk_cell] as Array
	_live_chunks.erase(chunk_cell)
	for n_v: Variant in list:
		var n: Node = n_v as Node
		if is_instance_valid(n):
			if n is BrokenStoneBridge:
				_live_bridges.erase(n as BrokenStoneBridge)
			elif n is FisherPier:
				_live_piers.erase(n as FisherPier)
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()


# ---------------------------------------------------------------- Red Order discovery

func request_discover_order(poi_id: String) -> void:
	if poi_id == "":
		return
	if multiplayer.is_server():
		_host_discover_order(poi_id, multiplayer.get_unique_id())
	else:
		_rpc_request_order.rpc_id(1, poi_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_order(poi_id: String) -> void:
	if multiplayer.is_server():
		_host_discover_order(poi_id, multiplayer.get_remote_sender_id())


func _host_discover_order(poi_id: String, peer_id: int) -> void:
	if not multiplayer.is_server() or _discovered_order.has(poi_id):
		return
	var node: OrderMonument = _find_live_order(poi_id)
	if node == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	if node.reach_distance(who.global_position) > Interactable.INTERACT_RANGE + 24.0:
		return
	_discovered_order[poi_id] = true
	for p: Player in Player.all:
		if p.health.current > 0.0 and p.global_position.distance_to(node.global_position) <= 220.0 and p.progress != null:
			p.progress.award(0, _order_xp)
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(node.global_position / 16.0, _order_reveal)
	var spec: Dictionary = _order_spec_by_id(poi_id)
	var title_str: String = String(spec.get("name", ""))
	var sub_str: String = String(spec.get("sub", ""))
	if multiplayer.get_peers().is_empty():
		_rpc_order_discovered(poi_id, peer_id, title_str, sub_str)
	else:
		_rpc_order_discovered.rpc(poi_id, peer_id, title_str, sub_str)


@rpc("authority", "call_local", "reliable")
func _rpc_order_discovered(poi_id: String, peer_id: int, title_str: String, sub_str: String) -> void:
	_discovered_order[poi_id] = true
	var node: OrderMonument = _find_live_order(poi_id)
	if node != null:
		node.discovered = true
	if title_str != "" and multiplayer.get_unique_id() == peer_id:
		_show_banner("SPUREN DES ROTEN ORDENS", title_str, sub_str, Color("5a2230"))


# ---------------------------------------------------------------- Watermill unjamming

func request_unjam_mill(mill_id: String) -> void:
	if mill_id == "":
		return
	if multiplayer.is_server():
		_host_unjam_mill(mill_id, multiplayer.get_unique_id())
	else:
		_rpc_request_unjam.rpc_id(1, mill_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_unjam(mill_id: String) -> void:
	if multiplayer.is_server():
		_host_unjam_mill(mill_id, multiplayer.get_remote_sender_id())


func _host_unjam_mill(mill_id: String, peer_id: int) -> void:
	if not multiplayer.is_server() or _unjammed_mills.has(mill_id):
		return
	var mill: OldWatermill = _find_live_mill(mill_id)
	if mill == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	if mill.reach_distance(who.global_position) > Interactable.INTERACT_RANGE + 28.0:
		return
	_unjammed_mills[mill_id] = true
	for p: Player in Player.all:
		if p.health.current > 0.0 and p.global_position.distance_to(mill.global_position) <= 240.0 and p.progress != null:
			p.progress.award(0, 20)
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(mill.global_position / 16.0, 12.0)
	if multiplayer.get_peers().is_empty():
		_rpc_mill_unjammed(mill_id, peer_id)
	else:
		_rpc_mill_unjammed.rpc(mill_id, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_mill_unjammed(mill_id: String, peer_id: int) -> void:
	_unjammed_mills[mill_id] = true
	var mill: OldWatermill = _find_live_mill(mill_id)
	if mill != null:
		mill.play_unjam_fx()
		if multiplayer.get_unique_id() == peer_id:
			_show_banner("WASSERMÜHLE BEFREIT", mill.mill_name, mill.mill_sub, Color("24444a"))


# ---------------------------------------------------------------- Reed Rowboat search

func request_search_rowboat(pier_id: String) -> void:
	if pier_id == "":
		return
	if multiplayer.is_server():
		_host_search_rowboat(pier_id, multiplayer.get_unique_id())
	else:
		_rpc_request_rowboat.rpc_id(1, pier_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_rowboat(pier_id: String) -> void:
	if multiplayer.is_server():
		_host_search_rowboat(pier_id, multiplayer.get_remote_sender_id())


func _host_search_rowboat(pier_id: String, peer_id: int) -> void:
	if not multiplayer.is_server() or _searched_boats.has(pier_id):
		return
	var pier: FisherPier = _find_live_pier(pier_id)
	if pier == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	if who.global_position.distance_to(pier.boat_world_pos) > 84.0:
		return
	_searched_boats[pier_id] = true
	if who.progress != null:
		who.progress.award(14, 10)
	_spawn_rowboat_drops(pier.boat_world_pos, hash(pier_id))
	if multiplayer.get_peers().is_empty():
		_rpc_rowboat_searched(pier_id)
	else:
		_rpc_rowboat_searched.rpc(pier_id)


func _spawn_rowboat_drops(origin: Vector2, seed_val: int) -> void:
	var container: Node = get_tree().get_first_node_in_group("drops")
	if container == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val
	var items_table: Dictionary = DataRegistry.table("items")
	var stacks: Array[Dictionary] = []
	for candidate: Array in [
		["meadow_apple", 2],
		["moon_pear", 1],
		["wood", 4],
		["lake_glimmer", 1],
	]:
		var cid: String = String(candidate[0])
		if items_table.has(cid):
			stacks.append({"id": cid, "count": int(candidate[1])})
	# Pick 2 deterministic stacks from the rowboat
	var chosen: Array[Dictionary] = []
	if stacks.size() >= 2:
		var idx_a: int = absi(seed_val) % stacks.size()
		var idx_b: int = (idx_a + 1 + (absi(seed_val >> 3) % (stacks.size() - 1))) % stacks.size()
		chosen.append(stacks[idx_a])
		chosen.append(stacks[idx_b])
	else:
		chosen = stacks
	for i: int in chosen.size():
		var st: Dictionary = chosen[i]
		var drop: ItemDrop = (load(DROP_SCENE) as PackedScene).instantiate() as ItemDrop
		_drop_serial += 1
		drop.name = "BoatDrop_%d" % _drop_serial
		drop.item_id = String(st.id)
		drop.count = int(st.count)
		drop.position = origin + Vector2(0.0, -4.0)
		var angle: float = lerpf(PI * 0.25, PI * 0.75, float(i) / float(maxi(chosen.size() - 1, 1))) + rng.randf_range(-0.15, 0.15)
		drop.launch = Vector2.from_angle(angle) * rng.randf_range(24.0, 38.0)
		drop.rise = 10.0
		drop.pop = 44.0
		drop.life = 240.0
		container.add_child(drop)


@rpc("authority", "call_local", "reliable")
func _rpc_rowboat_searched(pier_id: String) -> void:
	_searched_boats[pier_id] = true
	var pier: FisherPier = _find_live_pier(pier_id)
	if pier != null:
		pier.set_boat_searched(true)


# ---------------------------------------------------------------- Sync & Save

@rpc("authority", "reliable")
func _rpc_snapshot(order_ids: PackedStringArray, mill_ids: PackedStringArray, boat_ids: PackedStringArray) -> void:
	_discovered_order.clear()
	_unjammed_mills.clear()
	_searched_boats.clear()
	for oid: String in order_ids:
		_discovered_order[oid] = true
	for mid: String in mill_ids:
		_unjammed_mills[mid] = true
	for bid: String in boat_ids:
		_searched_boats[bid] = true
	_refresh_live_nodes()


func export_state() -> Dictionary:
	return {
		"order": _discovered_order.keys(),
		"mills": _unjammed_mills.keys(),
		"boats": _searched_boats.keys(),
	}


func import_state(saved: Variant) -> void:
	_discovered_order.clear()
	_unjammed_mills.clear()
	_searched_boats.clear()
	if saved is Dictionary:
		var d: Dictionary = saved as Dictionary
		for oid: Variant in d.get("order", []) as Array:
			_discovered_order[String(oid)] = true
		for mid: Variant in d.get("mills", []) as Array:
			_unjammed_mills[String(mid)] = true
		for bid: Variant in d.get("boats", []) as Array:
			_searched_boats[String(bid)] = true
	_refresh_live_nodes()
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(
			PackedStringArray(_discovered_order.keys()),
			PackedStringArray(_unjammed_mills.keys()),
			PackedStringArray(_searched_boats.keys())
		)


func _refresh_live_nodes() -> void:
	for nodes_v: Variant in _live_chunks.values():
		for n_v: Variant in nodes_v as Array:
			if n_v is OrderMonument:
				var om: OrderMonument = n_v as OrderMonument
				om.discovered = _discovered_order.has(om.poi_id)
			elif n_v is OldWatermill:
				var ml: OldWatermill = n_v as OldWatermill
				ml.set_unjammed_instant(_unjammed_mills.has(ml.mill_id))
			elif n_v is FisherPier:
				var pr: FisherPier = n_v as FisherPier
				pr.set_boat_searched(_searched_boats.has(pr.pier_id))


func _show_banner(hdr: String, title_str: String, sub_str: String, col: Color) -> void:
	if _banner == null:
		_banner = TownBanner.new()
		add_child(_banner)
	_banner.show_banner({
		"header": hdr,
		"title": title_str,
		"sub": sub_str,
		"color": col,
		"emblem": -1,
	})


func _order_spec_by_id(poi_id: String) -> Dictionary:
	var red_order: Dictionary = DataRegistry.table("meadow_pois").get("red_order", {}) as Dictionary
	for key: String in ["watchtowers", "patrol_camps", "boundary_stones"]:
		for sp_v: Variant in red_order.get(key, []) as Array:
			var sp: Dictionary = sp_v as Dictionary
			if String(sp.get("id", "")) == poi_id:
				return sp
	return {}


func _find_live_order(poi_id: String) -> OrderMonument:
	for nodes_v: Variant in _live_chunks.values():
		for n_v: Variant in nodes_v as Array:
			if n_v is OrderMonument and (n_v as OrderMonument).poi_id == poi_id:
				return n_v as OrderMonument
	return null


func _find_live_mill(mill_id: String) -> OldWatermill:
	for nodes_v: Variant in _live_chunks.values():
		for n_v: Variant in nodes_v as Array:
			if n_v is OldWatermill and (n_v as OldWatermill).mill_id == mill_id:
				return n_v as OldWatermill
	return null


func _find_live_pier(pier_id: String) -> FisherPier:
	for nodes_v: Variant in _live_chunks.values():
		for n_v: Variant in nodes_v as Array:
			if n_v is FisherPier and (n_v as FisherPier).pier_id == pier_id:
				return n_v as FisherPier
	return null


func _player_by_peer(peer_id: int) -> Player:
	for p: Player in Player.all:
		if p.name.to_int() == peer_id:
			return p
	return null
