class_name MeadowLandmarks
extends Node2D
## Chunk-streamed, host-authoritative landmarks for the 3 macro-landscapes of the standard meadow biome (`docs/wiesenbiom_ausbau_konzept.md` Stufe 2):
##  - `SolitaryTree` (`solitary_oak`): 1 grand gnarled hilltop oak per open *Windwiese & Blütenmeer* basin, with root bench (`var 0`) or rope swing (`var 1`).
##  - `ForestShrine` (`forest_shrine`): hidden ancient woodland shrines in *Der Tiefe Urforst*, paired with a golden `SunbeamShaft` and rising `Wurzelkiste`.
##  - `SunbeamShaft`: cathedral light shafts breaking through the `ancient_fir` canopy onto fern glades.
## Saved under `"meadow_landmarks"` in `SaveGame` (blessed shrine IDs).

const MIN_OAK_SPACING_TILES: float = 112.0
const MIN_SHRINE_SPACING_TILES: float = 78.0

var world: WorldLevel
var _sites_by_chunk: Dictionary = {} ## Vector2i(chunk) -> Array[Dictionary]
var _live_chunks: Dictionary = {} ## Vector2i(chunk) -> Array[Node]
var _blessed_shrines: Dictionary = {} ## String(shrine_id) -> true
var _oak_spots: Array[Vector2i] = []
var _shrine_spots: Array[Vector2i] = []
var _pasture_spots: Array[Vector2i] = []
var _banner: TownBanner


static func of(tree: SceneTree) -> MeadowLandmarks:
	return tree.get_first_node_in_group("meadow_landmarks") as MeadowLandmarks


func _ready() -> void:
	add_to_group("meadow_landmarks")
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			_rpc_snapshot.rpc_id(peer, PackedStringArray(_blessed_shrines.keys())))


func oak_tiles() -> Array[Vector2i]:
	return _oak_spots


func shrine_tiles() -> Array[Vector2i]:
	return _shrine_spots


func pasture_tiles() -> Array[Vector2i]:
	return _pasture_spots


func is_shrine_blessed(shrine_id: String) -> bool:
	return _blessed_shrines.has(shrine_id)


func blessed_count() -> int:
	return _blessed_shrines.size()


func setup(level: WorldLevel, prior_blocked: Dictionary) -> Dictionary:
	world = level
	_sites_by_chunk.clear()
	_oak_spots.clear()
	_shrine_spots.clear()
	_pasture_spots.clear()
	var blocked: Dictionary = {}
	var seed_base: int = level._map.world_seed
	var chunks_side: int = RegionMap.WORLD_TILES / WorldLevel.CHUNK

	# 1. Plan hilltop SolitaryTrees across Windwiesen: collect candidate crests, sort highest/strongest first, enforce wide basin spacing
	var oak_candidates: Array[Dictionary] = []
	for cy: int in chunks_side:
		for cx: int in chunks_side:
			var rng_o: RandomNumberGenerator = RandomNumberGenerator.new()
			rng_o.seed = hash(Vector4i(cx, cy, seed_base, 17107))
			var cand_o: Dictionary = _best_wind_crest_in_chunk(Vector2i(cx, cy), rng_o, prior_blocked)
			if not cand_o.is_empty():
				oak_candidates.append(cand_o)
	oak_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score))

	for cand_o2: Dictionary in oak_candidates:
		var t_o: Vector2i = cand_o2.tile as Vector2i
		var too_close: bool = false
		for prev_o: Vector2i in _oak_spots:
			if Vector2(t_o).distance_to(Vector2(prev_o)) < MIN_OAK_SPACING_TILES:
				too_close = true
				break
		if too_close:
			continue
		_oak_spots.append(t_o)
		var chunk_o: Vector2i = t_o / WorldLevel.CHUNK
		var var_o: int = absi(hash(Vector3i(t_o.x, t_o.y, seed_base + 503))) % 2
		(_sites_by_chunk.get_or_add(chunk_o, []) as Array).append({
			"kind": "solitary_oak",
			"tile": t_o,
			"pos": Vector2(t_o) * 16.0 + Vector2(8.0, 8.0),
			"variant": var_o,
		})
		for dy: int in range(-4, 5):
			for dx: int in range(-4, 5):
				blocked[t_o + Vector2i(dx, dy)] = true

	# 2. Plan hidden ForestShrines & cathedral SunbeamShafts inside Der Tiefe Urforst
	var shrine_candidates: Array[Dictionary] = []
	for cy2: int in chunks_side:
		for cx2: int in chunks_side:
			var chunk_d: Vector2i = Vector2i(cx2, cy2)
			var mid_px: Vector2 = Vector2(chunk_d * WorldLevel.CHUNK + Vector2i(16, 16)) * 16.0
			var w_d: float = MeadowHabitats.deep_forest_at(mid_px)
			if w_d >= 0.36:
				var rng_d: RandomNumberGenerator = RandomNumberGenerator.new()
				rng_d.seed = hash(Vector4i(cx2, cy2, seed_base, 17389))
				var cand_s: Dictionary = _best_shrine_glade_in_chunk(chunk_d, rng_d, prior_blocked, blocked)
				if not cand_s.is_empty():
					shrine_candidates.append(cand_s)
				# Ambient SunbeamShafts in deep-forest chunks (1-2 per chunk)
				for sb_i: int in (2 if w_d >= 0.58 else 1):
					if rng_d.randf() > 0.72:
						continue
					var sb_tile: Vector2i = chunk_d * WorldLevel.CHUNK + Vector2i(rng_d.randi_range(6, WorldLevel.CHUNK - 7), rng_d.randi_range(6, WorldLevel.CHUNK - 7))
					var sb_pos: Vector2 = Vector2(sb_tile) * 16.0 + Vector2(8.0, 8.0)
					if MeadowHabitats.deep_forest_at(sb_pos) >= 0.42 and _spot_walkable(sb_tile, sb_pos, 22.0, prior_blocked, blocked):
						(_sites_by_chunk.get_or_add(chunk_d, []) as Array).append({
							"kind": "sunbeam",
							"tile": sb_tile,
							"pos": sb_pos,
							"scale": rng_d.randf_range(0.85, 1.20),
							"seed": rng_d.randi(),
						})
						blocked[sb_tile] = true
			# Also record representative Old Pasture tiles for dev inspection/tests
			var w_p: float = MeadowHabitats.old_pasture_at(mid_px)
			if w_p >= 0.48:
				var p_tile: Vector2i = chunk_d * WorldLevel.CHUNK + Vector2i(16, 16)
				if _spot_walkable(p_tile, mid_px, 24.0, prior_blocked, blocked):
					var p_close: bool = false
					for prev_p: Vector2i in _pasture_spots:
						if Vector2(p_tile).distance_to(Vector2(prev_p)) < 72.0:
							p_close = true
							break
					if not p_close:
						_pasture_spots.append(p_tile)
	_pasture_spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return MeadowHabitats.old_pasture_at(Vector2(a) * 16.0) > MeadowHabitats.old_pasture_at(Vector2(b) * 16.0))

	shrine_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score))

	for cand_s2: Dictionary in shrine_candidates:
		if _shrine_spots.size() >= 12:
			break
		var t_s: Vector2i = cand_s2.tile as Vector2i
		var s_close: bool = false
		for prev_s: Vector2i in _shrine_spots:
			if Vector2(t_s).distance_to(Vector2(prev_s)) < MIN_SHRINE_SPACING_TILES:
				s_close = true
				break
		if s_close:
			continue
		_shrine_spots.append(t_s)
		var chunk_s: Vector2i = t_s / WorldLevel.CHUNK
		var var_s: int = absi(hash(Vector3i(t_s.x, t_s.y, seed_base + 811))) % 3
		var tier_s: String = "rare" if absi(hash(Vector3i(t_s.x, t_s.y, seed_base + 997))) % 100 < 35 else "common"
		(_sites_by_chunk.get_or_add(chunk_s, []) as Array).append({
			"kind": "forest_shrine",
			"id": "forest_shrine_%d_%d" % [t_s.x, t_s.y],
			"tile": t_s,
			"pos": Vector2(t_s) * 16.0 + Vector2(8.0, 8.0),
			"variant": var_s,
			"tier": tier_s,
		})
		for dy2: int in range(-2, 3):
			for dx2: int in range(-2, 3):
				blocked[t_s + Vector2i(dx2, dy2)] = true

	return blocked


func _spot_walkable(tile: Vector2i, pos_px: Vector2, flat_radius: float, prior_blocked: Dictionary, extra_blocked: Dictionary) -> bool:
	if tile.x < 8 or tile.y < 8 or tile.x >= RegionMap.WORLD_TILES - 8 or tile.y >= RegionMap.WORLD_TILES - 8:
		return false
	if world._generator.is_bare(tile):
		return false
	if not world._land_at(tile.x, tile.y) or world._sdf[tile.y * RegionMap.WORLD_TILES + tile.x] < 168:
		return false
	if not world._relief.flat_around(pos_px, flat_radius):
		return false
	if world._rivers != null and not world._rivers.clear_for_prop(pos_px, flat_radius + 14.0):
		return false
	var cell_r: int = maxi(1, int(ceilf(flat_radius / 16.0)))
	for dy: int in range(-cell_r, cell_r + 1):
		for dx: int in range(-cell_r, cell_r + 1):
			var c: Vector2i = tile + Vector2i(dx, dy)
			if prior_blocked.has(c) or extra_blocked.has(c) or world._stone_cells.has(c):
				return false
	return true


func _best_wind_crest_in_chunk(chunk_cell: Vector2i, rng: RandomNumberGenerator, prior_blocked: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1.0
	var base: Vector2i = chunk_cell * WorldLevel.CHUNK
	for _attempt: int in 10:
		var tile: Vector2i = base + Vector2i(rng.randi_range(7, WorldLevel.CHUNK - 8), rng.randi_range(7, WorldLevel.CHUNK - 8))
		var pos_px: Vector2 = Vector2(tile) * 16.0 + Vector2(8.0, 8.0)
		var w_wind: float = MeadowHabitats.wind_meadow_at(pos_px)
		if w_wind < 0.52:
			continue
		if not _spot_walkable(tile, pos_px, 56.0, prior_blocked, {}):
			continue
		var elev: float = world._relief.level_at(pos_px)
		var score: float = w_wind * 2.0 + elev * 0.45 + rng.randf() * 0.08
		if score > best_score:
			best_score = score
			best = {"tile": tile, "score": score}
	return best


func _best_shrine_glade_in_chunk(chunk_cell: Vector2i, rng: RandomNumberGenerator, prior_blocked: Dictionary, extra_blocked: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1.0
	var base: Vector2i = chunk_cell * WorldLevel.CHUNK
	for _attempt: int in 8:
		var tile: Vector2i = base + Vector2i(rng.randi_range(7, WorldLevel.CHUNK - 8), rng.randi_range(7, WorldLevel.CHUNK - 8))
		var pos_px: Vector2 = Vector2(tile) * 16.0 + Vector2(8.0, 8.0)
		var w_deep: float = MeadowHabitats.deep_forest_at(pos_px)
		if w_deep < 0.54:
			continue
		if not _spot_walkable(tile, pos_px, 44.0, prior_blocked, extra_blocked):
			continue
		var score: float = w_deep * 2.0 + rng.randf() * 0.15
		if score > best_score:
			best_score = score
			best = {"tile": tile, "score": score}
	return best


func populate_chunk(chunk_cell: Vector2i) -> void:
	if _live_chunks.has(chunk_cell) or not _sites_by_chunk.has(chunk_cell):
		return
	var spawned: Array[Node] = []
	var props_parent: Node2D = world._props if world != null and world._props != null else self
	for spec_v: Variant in _sites_by_chunk[chunk_cell] as Array:
		var spec: Dictionary = spec_v as Dictionary
		var kind: String = String(spec.kind)
		match kind:
			"solitary_oak":
				var oak: SolitaryTree = SolitaryTree.new()
				oak.name = "SolitaryOak_%d_%d" % [(spec.tile as Vector2i).x, (spec.tile as Vector2i).y]
				oak.setup(spec.pos as Vector2, int(spec.variant))
				props_parent.add_child(oak)
				spawned.append(oak)
			"forest_shrine":
				var sid: String = String(spec.id)
				var shrine: ForestShrine = ForestShrine.new()
				shrine.name = "Shrine_" + sid
				shrine.setup(self, sid, spec.pos as Vector2, int(spec.variant), String(spec.tier))
				props_parent.add_child(shrine)
				if _blessed_shrines.has(sid):
					shrine.set_blessed_instant(true)
				spawned.append(shrine)
			"sunbeam":
				var shaft: SunbeamShaft = SunbeamShaft.new()
				shaft.name = "Sunbeam_%d_%d" % [(spec.tile as Vector2i).x, (spec.tile as Vector2i).y]
				shaft.setup(spec.pos as Vector2, float(spec.scale), int(spec.seed))
				add_child(shaft)
				spawned.append(shaft)
	_live_chunks[chunk_cell] = spawned


func free_chunk(chunk_cell: Vector2i) -> void:
	if not _live_chunks.has(chunk_cell):
		return
	var list: Array = _live_chunks[chunk_cell] as Array
	_live_chunks.erase(chunk_cell)
	for n_v: Variant in list:
		var n: Node = n_v as Node
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()


func request_bless_shrine(shrine_id: String) -> void:
	if multiplayer.is_server():
		_host_bless_shrine(shrine_id, multiplayer.get_unique_id())
	else:
		_rpc_request_bless.rpc_id(1, shrine_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_bless(shrine_id: String) -> void:
	if multiplayer.is_server():
		_host_bless_shrine(shrine_id, multiplayer.get_remote_sender_id())


func _host_bless_shrine(shrine_id: String, peer_id: int) -> void:
	if not multiplayer.is_server() or _blessed_shrines.has(shrine_id):
		return
	var shrine_node: ForestShrine = _find_live_shrine(shrine_id)
	if shrine_node == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	if shrine_node.reach_distance(who.global_position) > Interactable.INTERACT_RANGE + 18.0:
		return
	_blessed_shrines[shrine_id] = true
	for p: Player in Player.all:
		if p.health.current > 0.0 and p.global_position.distance_to(shrine_node.global_position) <= 220.0:
			p.health.heal(maxf(12.0, p.health.max_health * 0.35))
			if p.progress != null:
				p.progress.award(0, 16)
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(shrine_node.global_position / 16.0, 12.0)
	if multiplayer.get_peers().is_empty():
		_rpc_shrine_blessed(shrine_id, peer_id)
	else:
		_rpc_shrine_blessed.rpc(shrine_id, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_shrine_blessed(shrine_id: String, peer_id: int) -> void:
	_blessed_shrines[shrine_id] = true
	var shrine_node: ForestShrine = _find_live_shrine(shrine_id)
	if shrine_node != null:
		shrine_node.play_bless_fx()
	if multiplayer.get_unique_id() == peer_id:
		if _banner == null:
			_banner = TownBanner.new()
			add_child(_banner)
		_banner.show_banner({
			"header": "WALDSCHREIN ERWACHT",
			"title": "SEGEN DES URFORSTS",
			"sub": "DIE WURZELN GEBEN IHREN SCHATZ FREI",
			"color": Color("22483c"),
			"emblem": -1,
		})


@rpc("authority", "reliable")
func _rpc_snapshot(ids: PackedStringArray) -> void:
	_blessed_shrines.clear()
	for id: String in ids:
		_blessed_shrines[id] = true
	for nodes_v: Variant in _live_chunks.values():
		for n_v: Variant in nodes_v as Array:
			if n_v is ForestShrine:
				var fs: ForestShrine = n_v as ForestShrine
				fs.set_blessed_instant(_blessed_shrines.has(fs.shrine_id))


func export_state() -> Array:
	return _blessed_shrines.keys()


func import_state(saved: Variant) -> void:
	_blessed_shrines.clear()
	if saved is Array:
		for entry: Variant in saved as Array:
			_blessed_shrines[String(entry)] = true
	for nodes_v: Variant in _live_chunks.values():
		for n_v: Variant in nodes_v as Array:
			if n_v is ForestShrine:
				var fs: ForestShrine = n_v as ForestShrine
				fs.set_blessed_instant(_blessed_shrines.has(fs.shrine_id))
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(PackedStringArray(_blessed_shrines.keys()))


func _find_live_shrine(shrine_id: String) -> ForestShrine:
	for nodes_v: Variant in _live_chunks.values():
		for n_v: Variant in nodes_v as Array:
			if n_v is ForestShrine and (n_v as ForestShrine).shrine_id == shrine_id:
				return n_v as ForestShrine
	return null


func _player_by_peer(peer_id: int) -> Player:
	for p: Player in Player.all:
		if p.name.to_int() == peer_id:
			return p
	return null
