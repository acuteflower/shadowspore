class_name MapDiscovery
extends Node
## Which parts of the world have been seen (the fog of the map, M).
## Dual-mode:
## - Legacy (`_atlas == null`): one byte per 4x4-tile cell on the RegionMap `GRID x GRID` (275x275).
## - v2 (`_atlas != null`): per-zone 2x2-tile cells (`V2_CELL = 2`), zstd-compressed per zone,
##   continent zone status (`unbekannt` / `gesichtet` / `betreten`), continent unlock flag, and coop RPCs.

signal revealed(cells: PackedInt32Array) ## legacy: cell indices that just became known
signal replaced ## the whole table / atlas state changed (snapshot, loaded save)
signal zone_fog_changed(zone_id: StringName, cells: PackedInt32Array)
signal zone_status_changed(zone_id: StringName, status: StringName)
signal continent_unlocked_changed(unlocked: bool)

const LEGACY_WORLD_TILES: int = 1024
const LEGACY_CELL: int = 4
const GRID: int = LEGACY_WORLD_TILES / LEGACY_CELL
const CELL_PX: float = float(LEGACY_CELL) * 16.0
const RADIUS: float = 7.5 ## cells around a player that count as seen (30 tiles, a bit more than the screen)
const RAGGED: float = 1.6 ## cells the edge of that disc wanders
const TICK: float = 0.4

const V2_CELL: int = 2
const V2_RADIUS_TILES: float = RADIUS * float(LEGACY_CELL) ## 30.0 tiles
const V2_RAGGED_TILES: float = 4.0
const STATUS_UNKNOWN: StringName = &"unbekannt"
const STATUS_SIGHTED: StringName = &"gesichtet"
const STATUS_ENTERED: StringName = &"betreten"
const MAX_ZONE_GRID_DIM: int = 4096

## Legacy state
var _seen: PackedByteArray = PackedByteArray()
var _count: int = 0
var _timer: float = 0.0
var _before: PackedByteArray = PackedByteArray() ## the table as it was before the developer's "whole map" reveal; empty = no reveal active
var _export_cache: PackedByteArray = PackedByteArray()

## v2 Atlas state
var _atlas: Atlas = null
var _continent_id: StringName = &"main"
var _zone_fog: Dictionary = {} ## StringName -> {w: int, h: int, bytes: PackedByteArray, seen_count: int, playable_seen: int, export_cache: PackedByteArray, image: Image, texture: ImageTexture}
var _zone_playable: Dictionary = {} ## StringName -> {mask: PackedByteArray, total: int}
var _zone_status: Dictionary = {} ## StringName -> StringName
var _continent_unlocked: bool = false
var _v2_reveal_all: bool = false
var _before_zones: Dictionary = {} ## StringName -> PackedByteArray


func _ready() -> void:
	add_to_group("map_discovery")
	_seen.resize(GRID * GRID)
	_try_auto_attach_atlas()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)


func _on_peer_connected(id: int) -> void:
	if not NetworkManager.rpc_ready(self):
		return
	if _atlas != null:
		_rpc_v2_snapshot.rpc_id(id, _build_v2_snapshot())
	else:
		_rpc_snapshot.rpc_id(id, export_data())


func _try_auto_attach_atlas() -> void:
	if _atlas != null:
		return
	var dir: ZoneDirector = null
	if is_inside_tree():
		var tree: SceneTree = get_tree()
		dir = tree.get_first_node_in_group("zone_director") as ZoneDirector
		if dir == null and get_parent() != null:
			for child: Node in get_parent().get_children():
				if child is ZoneDirector:
					dir = child as ZoneDirector
					break
		if dir == null:
			var world: Node = tree.get_first_node_in_group("world")
			if world != null and world.has_method("director"):
				var candidate: Variant = world.call("director")
				if candidate is ZoneDirector:
					dir = candidate as ZoneDirector
	if dir != null and dir.atlas != null:
		setup_atlas(dir.atlas, dir.continent_id)
		if not dir.zone_changed.is_connected(_on_director_zone_changed):
			dir.zone_changed.connect(_on_director_zone_changed)


func _on_director_zone_changed(_peer_id: int, zone_id: StringName) -> void:
	if multiplayer.is_server() and zone_id != &"":
		mark_zone_entered(zone_id)


func setup_atlas(atlas: Atlas, continent_id: StringName = &"main") -> void:
	_atlas = atlas
	_continent_id = continent_id
	_zone_playable.clear()
	if _atlas != null:
		var stale_fog: Array[StringName] = []
		for zid: StringName in _zone_fog:
			if _atlas.zone(zid) == null:
				stale_fog.append(zid)
		for zid: StringName in stale_fog:
			_zone_fog.erase(zid)
		var stale_status: Array[StringName] = []
		for zid: StringName in _zone_status:
			if _atlas.zone(zid) == null:
				stale_status.append(zid)
		for zid: StringName in stale_status:
			_zone_status.erase(zid)
		var stale_before: Array[StringName] = []
		for zid: StringName in _before_zones:
			if _atlas.zone(zid) == null:
				stale_before.append(zid)
		for zid: StringName in stale_before:
			_before_zones.erase(zid)
		for z: Atlas.Zone in _atlas.zones_of(_continent_id):
			_reconcile_zone_entry(z)
			if not _zone_status.has(z.id):
				_zone_status[z.id] = STATUS_UNKNOWN
	replaced.emit()


func is_v2() -> bool:
	return _atlas != null


func continent_size() -> Vector2i:
	if _atlas != null:
		var cont: Atlas.Continent = _atlas.continent(_continent_id)
		if cont != null and cont.size.x > 0 and cont.size.y > 0:
			return cont.size
	return Vector2i(LEGACY_WORLD_TILES, LEGACY_WORLD_TILES)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	if _atlas != null:
		_process_v2()
		return
	var fresh: PackedInt32Array = PackedInt32Array()
	for player: Player in Player.all:
		if player.effects != null and player.effects.has("hallucinated"):
			continue ## the mist: nothing she sees there can be trusted, so nothing is drawn on the map
		_scan(Interiors.outer(get_tree(), player.global_position) / CELL_PX, fresh)
	if not fresh.is_empty():
		_rpc_reveal.rpc(fresh)


func _process_v2() -> void:
	var tree: SceneTree = get_tree()
	for player: Player in Player.all:
		if player.effects != null and player.effects.has("hallucinated"):
			continue
		var raw_px: Vector2 = player.global_position
		var outer_px: Vector2 = Interiors.outer(tree, raw_px) if tree != null else Interiors.to_world(raw_px)
		if not outer_px.is_finite() or PocketSpace.is_pocket(outer_px):
			continue
		if PocketSpace.is_pocket(raw_px) and outer_px == Vector2.ZERO:
			continue
		var here: StringName = _atlas.zone_at(_continent_id, outer_px)
		if here != &"":
			mark_zone_entered(here)
		reveal_continent_disc(Atlas.tile_of(outer_px), V2_RADIUS_TILES)


func _scan(at: Vector2, fresh: PackedInt32Array, radius: float = RADIUS) -> void:
	var reach: int = ceili(radius + RAGGED)
	for y: int in range(maxi(floori(at.y) - reach, 0), mini(floori(at.y) + reach + 1, GRID)):
		for x: int in range(maxi(floori(at.x) - reach, 0), mini(floori(at.x) + reach + 1, GRID)):
			var index: int = y * GRID + x
			if _seen[index] != 0:
				continue
			var wander: float = (fposmod(sin(float(index) * 12.9898) * 43758.5453, 1.0) - 0.5) * RAGGED
			if Vector2(x + 0.5, y + 0.5).distance_to(at) <= radius + wander:
				fresh.append(index)


## Host: lifts the fog round a tile (a waystone waking up): a ragged disc of `radius_cells` cells (4 tiles/cell), told to everybody.
func reveal_disc(tile: Vector2, radius_cells: float = RADIUS) -> void:
	if not multiplayer.is_server():
		return
	if _atlas != null:
		if not tile.is_finite() or PocketSpace.is_pocket(Atlas.px_of(tile)):
			return
		reveal_continent_disc(tile, radius_cells * float(LEGACY_CELL))
		return
	var fresh: PackedInt32Array = PackedInt32Array()
	_scan(tile / float(LEGACY_CELL), fresh, radius_cells)
	if not fresh.is_empty():
		_rpc_reveal.rpc(fresh)


func reveal_continent_disc(world_tile_pos: Vector2, radius_tiles: float) -> void:
	if not multiplayer.is_server() or _atlas == null or not world_tile_pos.is_finite():
		return
	if PocketSpace.is_pocket(Atlas.px_of(world_tile_pos)):
		return
	var reach: float = maxf(0.0, radius_tiles) + V2_RAGGED_TILES
	var disc_rect: Rect2 = Rect2(world_tile_pos - Vector2.ONE * reach, Vector2.ONE * (reach * 2.0))
	for z: Atlas.Zone in _atlas.zones_of(_continent_id):
		var zone_rect: Rect2 = Rect2(Vector2(z.origin), Vector2(z.size))
		if zone_rect.intersects(disc_rect):
			reveal_zone_disc(z.id, world_tile_pos - Vector2(z.origin), radius_tiles)


func reveal_zone_disc(zone_id: StringName, local_tile_pos: Vector2, radius_tiles: float) -> void:
	if not multiplayer.is_server() or _atlas == null or not local_tile_pos.is_finite():
		return
	var z: Atlas.Zone = _atlas.zone(zone_id)
	if z == null:
		return
	var entry: Dictionary = _ensure_zone_entry(zone_id)
	var gw: int = int(entry["w"])
	var gh: int = int(entry["h"])
	var zone_bytes: PackedByteArray = entry["bytes"] as PackedByteArray
	var reach_cells: int = ceili((maxf(0.0, radius_tiles) + V2_RAGGED_TILES) / float(V2_CELL))
	var cx_mid: int = floori(local_tile_pos.x / float(V2_CELL))
	var cy_mid: int = floori(local_tile_pos.y / float(V2_CELL))
	var x0: int = maxi(cx_mid - reach_cells, 0)
	var x1: int = mini(cx_mid + reach_cells + 1, gw)
	var y0: int = maxi(cy_mid - reach_cells, 0)
	var y1: int = mini(cy_mid + reach_cells + 1, gh)
	var ox_cells: int = floori(float(z.origin.x) / float(V2_CELL))
	var oy_cells: int = floori(float(z.origin.y) / float(V2_CELL))
	var fresh: PackedInt32Array = PackedInt32Array()
	var touched_footprint: bool = false
	for cy: int in range(y0, y1):
		for cx: int in range(x0, x1):
			var idx: int = cy * gw + cx
			var cell_local: Vector2 = (Vector2(float(cx), float(cy)) + Vector2(0.5, 0.5)) * float(V2_CELL)
			var seed_val: float = float((oy_cells + cy) * 8191 + (ox_cells + cx))
			var wander: float = (fposmod(sin(seed_val * 12.9898) * 43758.5453, 1.0) - 0.5) * V2_RAGGED_TILES
			if cell_local.distance_to(local_tile_pos) <= radius_tiles + wander:
				if zone_bytes[idx] == 0:
					fresh.append(idx)
				if not touched_footprint and z.contains(Vector2(z.origin) + cell_local):
					touched_footprint = true
	if not fresh.is_empty():
		_apply_zone_fog_delta(zone_id, fresh)
		if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
			_rpc_zone_fog_delta.rpc(String(zone_id), fresh)
	if zone_status(zone_id) == STATUS_UNKNOWN:
		if touched_footprint or Atlas.edge_distance(Vector2(z.origin) + local_tile_pos, z.footprint) <= radius_tiles:
			mark_zone_sighted(zone_id)


@rpc("authority", "call_local", "reliable")
func _rpc_reveal(cells: PackedInt32Array) -> void:
	var added: PackedInt32Array = PackedInt32Array()
	for index: int in cells:
		if index >= 0 and index < _seen.size() and _seen[index] == 0:
			_seen[index] = 1
			_count += 1
			added.append(index)
	if not added.is_empty():
		_export_cache = PackedByteArray()
		revealed.emit(added)


@rpc("authority", "reliable")
func _rpc_snapshot(data: PackedByteArray) -> void:
	import_data(data)


@rpc("authority", "call_remote", "reliable")
func _rpc_zone_fog_delta(zone_id: String, cells: PackedInt32Array) -> void:
	_apply_zone_fog_delta(StringName(zone_id), cells)


@rpc("authority", "call_remote", "reliable")
func _rpc_zone_status(zone_id: String, status: String) -> void:
	var zid: StringName = StringName(zone_id)
	if zid == &"" or (_atlas != null and _atlas.zone(zid) == null):
		return
	var normalized: StringName = _normalize_status(status)
	if _status_rank(normalized) > _status_rank(zone_status(zid)):
		_zone_status[zid] = normalized
		zone_status_changed.emit(zid, normalized)


@rpc("authority", "call_remote", "reliable")
func _rpc_continent_unlocked(unlocked: bool) -> void:
	if _continent_unlocked != unlocked:
		_continent_unlocked = unlocked
		continent_unlocked_changed.emit(_continent_unlocked)


@rpc("authority", "call_remote", "reliable")
func _rpc_v2_snapshot(snapshot: Dictionary) -> void:
	_apply_v2_snapshot(snapshot)


func seen_count() -> int:
	if _atlas != null:
		var total: int = 0
		for zid: StringName in _zone_fog:
			var entry: Dictionary = _zone_fog[zid] as Dictionary
			if _v2_reveal_all:
				total += int(entry["w"]) * int(entry["h"])
			else:
				total += int(entry["seen_count"])
		return total
	return _count


func is_seen_cell(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < GRID and y < GRID and _seen[y * GRID + x] != 0


## `tile` in tile units (not pixels).
func is_seen(tile: Vector2) -> bool:
	if _atlas != null:
		if not tile.is_finite() or PocketSpace.is_pocket(Atlas.px_of(tile)):
			return false
		var csize: Vector2i = continent_size()
		if tile.x < 0.0 or tile.y < 0.0 or tile.x >= float(csize.x) or tile.y >= float(csize.y):
			return false
		if _v2_reveal_all:
			return true
		var zid: StringName = _atlas.zone_at_tile(_continent_id, tile)
		if zid != &"":
			return _is_zone_tile_seen(zid, tile)
		for z: Atlas.Zone in _atlas.zones_of(_continent_id):
			var zrect: Rect2 = Rect2(Vector2(z.origin), Vector2(z.size))
			if zrect.has_point(tile) and _is_zone_tile_seen(z.id, tile):
				return true
		return false
	return is_seen_cell(floori(tile.x / float(LEGACY_CELL)), floori(tile.y / float(LEGACY_CELL)))


func _is_zone_tile_seen(zone_id: StringName, world_tile: Vector2) -> bool:
	if _atlas == null:
		return false
	var z: Atlas.Zone = _atlas.zone(zone_id)
	if z == null or not _zone_fog.has(zone_id):
		return false
	var entry: Dictionary = _zone_fog[zone_id] as Dictionary
	var gw: int = int(entry["w"])
	var gh: int = int(entry["h"])
	var local: Vector2 = world_tile - Vector2(z.origin)
	var cx: int = floori(local.x / float(V2_CELL))
	var cy: int = floori(local.y / float(V2_CELL))
	if cx < 0 or cy < 0 or cx >= gw or cy >= gh:
		return false
	var zone_bytes: PackedByteArray = entry["bytes"] as PackedByteArray
	return zone_bytes[cy * gw + cx] != 0


func bytes() -> PackedByteArray:
	return _seen


func zone_fog_texture(zone_id: StringName) -> ImageTexture:
	if _atlas == null or _atlas.zone(zone_id) == null:
		return null
	var entry: Dictionary = _ensure_zone_entry(zone_id)
	if entry.get("texture") == null:
		var img: Image = _build_zone_image(zone_id)
		entry["image"] = img
		entry["texture"] = ImageTexture.create_from_image(img)
	return entry["texture"] as ImageTexture


func zone_explored_ratio(zone_id: StringName) -> float:
	if _atlas == null or _atlas.zone(zone_id) == null:
		return 0.0
	if _v2_reveal_all:
		return 1.0
	var entry: Dictionary = _ensure_zone_entry(zone_id)
	var playable: Dictionary = _ensure_playable_mask(zone_id)
	var total: int = int(playable["total"])
	return clampf(float(int(entry["playable_seen"])) / float(maxi(1, total)), 0.0, 1.0)


func zone_status(zone_id: StringName) -> StringName:
	return _zone_status.get(zone_id, STATUS_UNKNOWN) as StringName


func mark_zone_sighted(zone_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	_set_zone_status_if_higher(zone_id, STATUS_SIGHTED)


func mark_zone_entered(zone_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	_set_zone_status_if_higher(zone_id, STATUS_ENTERED)


func _set_zone_status_if_higher(zone_id: StringName, new_status: StringName) -> void:
	if zone_id == &"":
		return
	if _atlas != null and _atlas.zone(zone_id) == null:
		return
	if _status_rank(new_status) <= _status_rank(zone_status(zone_id)):
		return
	_zone_status[zone_id] = new_status
	zone_status_changed.emit(zone_id, new_status)
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_zone_status.rpc(String(zone_id), String(new_status))


func set_continent_unlocked(unlocked: bool) -> void:
	if not multiplayer.is_server():
		return
	if _continent_unlocked == unlocked:
		return
	_continent_unlocked = unlocked
	continent_unlocked_changed.emit(_continent_unlocked)
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_continent_unlocked.rpc(_continent_unlocked)


func request_continent_unlocked(unlocked: bool = true) -> void:
	if multiplayer.is_server():
		set_continent_unlocked(unlocked)
	else:
		if _continent_unlocked != unlocked:
			_continent_unlocked = unlocked
			continent_unlocked_changed.emit(_continent_unlocked)
		if NetworkManager.rpc_ready(self):
			_rpc_request_continent_unlocked.rpc_id(1, unlocked)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_continent_unlocked(unlocked: bool) -> void:
	if multiplayer.is_server() and unlocked:
		set_continent_unlocked(true)


func is_continent_unlocked() -> bool:
	return _continent_unlocked


## The table, compressed (network snapshot and save file).
func export_data() -> PackedByteArray:
	if _export_cache.is_empty():
		_export_cache = _seen.compress(FileAccess.COMPRESSION_ZSTD)
	return _export_cache


func import_data(data: PackedByteArray) -> void:
	if data.is_empty():
		return
	var raw: PackedByteArray = data.decompress(GRID * GRID, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != GRID * GRID:
		return
	_seen = raw
	_export_cache = PackedByteArray()
	_count = 0
	for value: int in _seen:
		_count += value
	replaced.emit()


## Loading a save: the host's table replaces everything, peers get it too.
func import_saved(data: PackedByteArray) -> void:
	import_data(data)
	if multiplayer.is_server() and NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(export_data())


func export_zone_fog(zone_id: StringName) -> Dictionary:
	if not _zone_fog.has(zone_id):
		if _atlas != null and _atlas.zone(zone_id) != null:
			_ensure_zone_entry(zone_id)
		else:
			return {}
	var entry: Dictionary = _zone_fog[zone_id] as Dictionary
	var cache: PackedByteArray = entry["export_cache"] as PackedByteArray
	if cache.is_empty():
		cache = (entry["bytes"] as PackedByteArray).compress(FileAccess.COMPRESSION_ZSTD)
		entry["export_cache"] = cache
	return {"w": int(entry["w"]), "h": int(entry["h"]), "zstd": cache}


func import_zone_fog(zone_id: StringName, d: Dictionary) -> void:
	if zone_id == &"" or d.is_empty():
		return
	if _atlas != null and _atlas.zone(zone_id) == null:
		return
	var w: int = _to_int(d.get("w", 0), 0)
	var h: int = _to_int(d.get("h", 0), 0)
	if w <= 0 or h <= 0 or w > MAX_ZONE_GRID_DIM or h > MAX_ZONE_GRID_DIM:
		return
	var zstd: PackedByteArray = PackedByteArray()
	var raw_zstd: Variant = d.get("zstd")
	if raw_zstd is PackedByteArray:
		zstd = raw_zstd as PackedByteArray
	elif d.has("zstd_b64"):
		zstd = _decode_b64(d.get("zstd_b64"))
	if zstd.is_empty():
		return
	var raw: PackedByteArray = zstd.decompress(w * h, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != w * h:
		return
	if _atlas != null:
		var entry: Dictionary = _ensure_zone_entry(zone_id)
		var gw: int = int(entry["w"])
		var gh: int = int(entry["h"])
		if gw == w and gh == h:
			entry["bytes"] = raw
		else:
			entry["bytes"] = _blit_bytes(raw, w, h, gw, gh)
		entry["export_cache"] = PackedByteArray()
		_recount_zone_entry(zone_id)
		_refresh_zone_texture(zone_id)
		zone_fog_changed.emit(zone_id, PackedInt32Array())
	else:
		var sc: int = 0
		for v: int in raw:
			if v != 0:
				sc += 1
		_zone_fog[zone_id] = {
			"w": w,
			"h": h,
			"bytes": raw,
			"seen_count": sc,
			"playable_seen": 0,
			"export_cache": PackedByteArray(),
			"image": null,
			"texture": null,
		}


func export_atlas_state() -> Dictionary:
	var zones_out: Dictionary = {}
	for zid: StringName in _zone_fog:
		var zdict: Dictionary = export_zone_fog(zid)
		if zdict.is_empty():
			continue
		zones_out[String(zid)] = {
			"w": int(zdict["w"]),
			"h": int(zdict["h"]),
			"zstd_b64": Marshalls.raw_to_base64(zdict["zstd"] as PackedByteArray),
		}
	var status_out: Dictionary = {}
	for zid: StringName in _zone_status:
		status_out[String(zid)] = String(_zone_status[zid])
	var before_out: Dictionary = {}
	if _v2_reveal_all:
		for zid: StringName in _before_zones:
			var b_arr: PackedByteArray = _before_zones[zid] as PackedByteArray
			var entry: Dictionary = _zone_fog.get(zid, {}) as Dictionary
			var bw: int = int(entry.get("w", 0))
			var bh: int = int(entry.get("h", 0))
			if bw > 0 and bh > 0 and b_arr.size() == bw * bh:
				before_out[String(zid)] = {
					"w": bw,
					"h": bh,
					"zstd_b64": Marshalls.raw_to_base64(b_arr.compress(FileAccess.COMPRESSION_ZSTD)),
				}
	return {
		"version": 2,
		"continent": String(_continent_id),
		"zones": zones_out,
		"status": status_out,
		"continent_unlocked": _continent_unlocked,
		"reveal_all": _v2_reveal_all,
		"before_zones": before_out,
	}


func import_atlas_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	_apply_v2_snapshot(d)
	if multiplayer.is_server() and NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_v2_snapshot.rpc(_build_v2_snapshot())


## Developer tool: the whole world counts as seen (every cell). The table from before is kept, so `reset_reveal` can give it back.
## Host only; the save file keeps both tables (`export_before`), so the reveal survives saving, quitting and restarting.
func reveal_all() -> void:
	if not multiplayer.is_server() or is_reveal_all():
		return
	if _atlas != null:
		_before_zones.clear()
		for z: Atlas.Zone in _atlas.zones_of(_continent_id):
			_ensure_zone_entry(z.id)
		for zid: StringName in _zone_fog:
			var entry: Dictionary = _zone_fog[zid] as Dictionary
			var cur_bytes: PackedByteArray = entry["bytes"] as PackedByteArray
			_before_zones[zid] = cur_bytes.duplicate()
			cur_bytes.fill(1)
			entry["bytes"] = cur_bytes
			entry["export_cache"] = PackedByteArray()
			_recount_zone_entry(zid)
			_refresh_zone_texture(zid)
			zone_fog_changed.emit(zid, PackedInt32Array())
		_v2_reveal_all = true
		replaced.emit()
		if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
			_rpc_v2_snapshot.rpc(_build_v2_snapshot())
		return
	_before = _seen.duplicate()
	var full: PackedByteArray = PackedByteArray()
	full.resize(GRID * GRID)
	full.fill(1)
	_set_table(full)


## Developer tool: the table from before `reveal_all` again (host only). Cells walked meanwhile are not lost: the reveal only ever added.
func reset_reveal() -> void:
	if not multiplayer.is_server() or not is_reveal_all():
		return
	if _atlas != null:
		_v2_reveal_all = false
		for zid: StringName in _zone_fog:
			var entry: Dictionary = _zone_fog[zid] as Dictionary
			var cur_bytes: PackedByteArray = entry["bytes"] as PackedByteArray
			if _before_zones.has(zid):
				var prev: PackedByteArray = _before_zones[zid] as PackedByteArray
				if prev.size() == cur_bytes.size():
					entry["bytes"] = prev.duplicate()
				else:
					cur_bytes.fill(0)
					entry["bytes"] = cur_bytes
			else:
				cur_bytes.fill(0)
				entry["bytes"] = cur_bytes
			entry["export_cache"] = PackedByteArray()
			_recount_zone_entry(zid)
			_refresh_zone_texture(zid)
			zone_fog_changed.emit(zid, PackedInt32Array())
		_before_zones.clear()
		replaced.emit()
		if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
			_rpc_v2_snapshot.rpc(_build_v2_snapshot())
		return
	var before: PackedByteArray = _before
	_before = PackedByteArray()
	_set_table(before)


## True while the developer reveal is active (the saved table before it is kept).
func is_reveal_all() -> bool:
	if _atlas != null:
		return _v2_reveal_all
	return _before.size() == GRID * GRID


## The table from before the reveal, compressed (save file); empty when no reveal is active.
func export_before() -> PackedByteArray:
	if _atlas != null or not is_reveal_all():
		return PackedByteArray()
	return _before.compress(FileAccess.COMPRESSION_ZSTD)


## Loading a save: restores the table from before a reveal (empty = no reveal active).
func import_before(data: PackedByteArray) -> void:
	_before = PackedByteArray()
	if data.is_empty():
		return
	var raw: PackedByteArray = data.decompress(GRID * GRID, FileAccess.COMPRESSION_ZSTD)
	if raw.size() == GRID * GRID:
		_before = raw


## Host: replaces the whole table and tells everybody else.
func _set_table(raw: PackedByteArray) -> void:
	_seen = raw
	_export_cache = PackedByteArray()
	_count = 0
	for value: int in _seen:
		_count += value
	replaced.emit()
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(export_data())


# --- v2 helpers ------------------------------------------------------------------------------------------------------

func _zone_grid_dims(z: Atlas.Zone) -> Vector2i:
	return Vector2i(maxi(1, ceili(float(z.size.x) / float(V2_CELL))), maxi(1, ceili(float(z.size.y) / float(V2_CELL))))


func _ensure_zone_entry(zone_id: StringName) -> Dictionary:
	if _zone_fog.has(zone_id):
		return _zone_fog[zone_id] as Dictionary
	var z: Atlas.Zone = _atlas.zone(zone_id) if _atlas != null else null
	var dims: Vector2i = _zone_grid_dims(z) if z != null else Vector2i(1, 1)
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(dims.x * dims.y)
	if _v2_reveal_all:
		raw.fill(1)
	var entry: Dictionary = {
		"w": dims.x,
		"h": dims.y,
		"bytes": raw,
		"seen_count": raw.size() if _v2_reveal_all else 0,
		"playable_seen": 0,
		"export_cache": PackedByteArray(),
		"image": null,
		"texture": null,
	}
	_zone_fog[zone_id] = entry
	if _v2_reveal_all:
		_recount_zone_entry(zone_id)
	return entry


func _reconcile_zone_entry(z: Atlas.Zone) -> void:
	if not _zone_fog.has(z.id):
		_ensure_zone_entry(z.id)
		return
	var entry: Dictionary = _zone_fog[z.id] as Dictionary
	var dims: Vector2i = _zone_grid_dims(z)
	var ew: int = int(entry["w"])
	var eh: int = int(entry["h"])
	if ew != dims.x or eh != dims.y:
		entry["bytes"] = _blit_bytes(entry["bytes"] as PackedByteArray, ew, eh, dims.x, dims.y)
		entry["w"] = dims.x
		entry["h"] = dims.y
		entry["export_cache"] = PackedByteArray()
		entry["image"] = null
		entry["texture"] = null
	if _v2_reveal_all:
		var filled: PackedByteArray = entry["bytes"] as PackedByteArray
		filled.fill(1)
		entry["bytes"] = filled
		entry["export_cache"] = PackedByteArray()
	_recount_zone_entry(z.id)
	_refresh_zone_texture(z.id)


func _ensure_playable_mask(zone_id: StringName) -> Dictionary:
	if _zone_playable.has(zone_id):
		return _zone_playable[zone_id] as Dictionary
	var entry: Dictionary = _ensure_zone_entry(zone_id)
	var gw: int = int(entry["w"])
	var gh: int = int(entry["h"])
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(gw * gh)
	var total: int = 0
	var z: Atlas.Zone = _atlas.zone(zone_id) if _atlas != null else null
	if z != null and not z.footprint.is_empty():
		for cy: int in gh:
			for cx: int in gw:
				var world_tile: Vector2 = Vector2(z.origin) + (Vector2(float(cx), float(cy)) + Vector2(0.5, 0.5)) * float(V2_CELL)
				if z.contains(world_tile):
					mask[cy * gw + cx] = 1
					total += 1
	if total == 0:
		mask.fill(1)
		total = gw * gh
	var info: Dictionary = {"mask": mask, "total": total}
	_zone_playable[zone_id] = info
	return info


func _recount_zone_entry(zone_id: StringName) -> void:
	if not _zone_fog.has(zone_id):
		return
	var entry: Dictionary = _zone_fog[zone_id] as Dictionary
	var zone_bytes: PackedByteArray = entry["bytes"] as PackedByteArray
	var sc: int = 0
	var p_seen: int = 0
	if _atlas != null and _atlas.zone(zone_id) != null:
		var playable: Dictionary = _ensure_playable_mask(zone_id)
		var mask: PackedByteArray = playable["mask"] as PackedByteArray
		for i: int in zone_bytes.size():
			if zone_bytes[i] != 0:
				sc += 1
				if i < mask.size() and mask[i] != 0:
					p_seen += 1
	else:
		for i: int in zone_bytes.size():
			if zone_bytes[i] != 0:
				sc += 1
	entry["seen_count"] = sc
	entry["playable_seen"] = p_seen


func _apply_zone_fog_delta(zone_id: StringName, cells: PackedInt32Array) -> void:
	if _atlas == null or _atlas.zone(zone_id) == null:
		return
	var entry: Dictionary = _ensure_zone_entry(zone_id)
	var zone_bytes: PackedByteArray = entry["bytes"] as PackedByteArray
	var playable: Dictionary = _ensure_playable_mask(zone_id)
	var mask: PackedByteArray = playable["mask"] as PackedByteArray
	var img: Image = entry.get("image") as Image
	var gw: int = int(entry["w"])
	var added: PackedInt32Array = PackedInt32Array()
	for idx: int in cells:
		if idx >= 0 and idx < zone_bytes.size() and zone_bytes[idx] == 0:
			zone_bytes[idx] = 1
			entry["seen_count"] = int(entry["seen_count"]) + 1
			if idx < mask.size() and mask[idx] != 0:
				entry["playable_seen"] = int(entry["playable_seen"]) + 1
			added.append(idx)
			if img != null:
				img.set_pixel(idx % gw, idx / gw, Color(1.0, 0.0, 0.0, 1.0))
	if not added.is_empty():
		entry["bytes"] = zone_bytes
		entry["export_cache"] = PackedByteArray()
		var tex: ImageTexture = entry.get("texture") as ImageTexture
		if tex != null and img != null:
			if DisplayServer.get_name() == "headless":
				entry["texture"] = ImageTexture.create_from_image(img)
			else:
				tex.update(img)
		zone_fog_changed.emit(zone_id, added)


func _build_zone_image(zone_id: StringName) -> Image:
	var entry: Dictionary = _zone_fog[zone_id] as Dictionary
	var gw: int = int(entry["w"])
	var gh: int = int(entry["h"])
	var img: Image = Image.create(gw, gh, false, Image.FORMAT_R8)
	_write_zone_image(zone_id, img)
	return img


func _write_zone_image(zone_id: StringName, img: Image) -> void:
	var entry: Dictionary = _zone_fog[zone_id] as Dictionary
	var gw: int = int(entry["w"])
	var gh: int = int(entry["h"])
	var zone_bytes: PackedByteArray = entry["bytes"] as PackedByteArray
	if _v2_reveal_all:
		img.fill(Color(1.0, 0.0, 0.0, 1.0))
	else:
		var pixels: PackedByteArray = PackedByteArray()
		pixels.resize(gw * gh)
		for i: int in mini(zone_bytes.size(), pixels.size()):
			pixels[i] = 255 if zone_bytes[i] != 0 else 0
		img.set_data(gw, gh, false, Image.FORMAT_R8, pixels)


func _refresh_zone_texture(zone_id: StringName) -> void:
	if not _zone_fog.has(zone_id):
		return
	var entry: Dictionary = _zone_fog[zone_id] as Dictionary
	var img: Image = entry.get("image") as Image
	var tex: ImageTexture = entry.get("texture") as ImageTexture
	if img == null or tex == null:
		return
	_write_zone_image(zone_id, img)
	if DisplayServer.get_name() == "headless":
		entry["texture"] = ImageTexture.create_from_image(img)
	else:
		tex.update(img)


static func _blit_bytes(src: PackedByteArray, sw: int, sh: int, dw: int, dh: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(dw * dh)
	var cw: int = mini(sw, dw)
	var ch: int = mini(sh, dh)
	for y: int in ch:
		for x: int in cw:
			out[y * dw + x] = src[y * sw + x]
	return out


static func _status_rank(status: StringName) -> int:
	if status == STATUS_ENTERED:
		return 2
	if status == STATUS_SIGHTED:
		return 1
	return 0


static func _to_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		return v as int
	if v is float:
		var f: float = v as float
		if is_finite(f) and absf(f) <= 2147483647.0:
			return int(f)
		return fallback
	if v is String or v is StringName:
		var s: String = str(v).strip_edges()
		if s.is_valid_int():
			var digits: String = s
			if digits.begins_with("+") or digits.begins_with("-"):
				digits = digits.substr(1)
			var first_nz: int = 0
			while first_nz < digits.length() and digits.unicode_at(first_nz) == 48:
				first_nz += 1
			if digits.length() - first_nz > 18:
				return fallback
			return s.to_int()
	return fallback


static func _to_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		return v as bool
	if v is int:
		return (v as int) != 0
	if v is float:
		var f: float = v as float
		return (f != 0.0) if is_finite(f) else fallback
	if v is String or v is StringName:
		var s: String = str(v).strip_edges().to_lower()
		if s == "true" or s == "1":
			return true
		if s == "false" or s == "0":
			return false
		return fallback
	return fallback


static func _decode_b64(s: Variant) -> PackedByteArray:
	if not (s is String or s is StringName):
		return PackedByteArray()
	var text: String = str(s).strip_edges()
	if text.is_empty() or (text.length() % 4) != 0:
		return PackedByteArray()
	var pad: int = 0
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		var is_alpha: bool = (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_digit: bool = code >= 48 and code <= 57
		var is_sym: bool = code == 43 or code == 47
		if code == 61:
			pad += 1
			if i < text.length() - 2:
				return PackedByteArray()
			continue
		if pad > 0 or not (is_alpha or is_digit or is_sym):
			return PackedByteArray()
	if pad > 2:
		return PackedByteArray()
	return Marshalls.base64_to_raw(text)


static func _normalize_status(raw: Variant) -> StringName:
	var s: String = str(raw) if (raw is String or raw is StringName) else ""
	if s == String(STATUS_ENTERED):
		return STATUS_ENTERED
	if s == String(STATUS_SIGHTED):
		return STATUS_SIGHTED
	return STATUS_UNKNOWN


func _build_v2_snapshot() -> Dictionary:
	var zones_out: Dictionary = {}
	for zid: StringName in _zone_fog:
		var zdict: Dictionary = export_zone_fog(zid)
		if not zdict.is_empty():
			zones_out[String(zid)] = zdict
	var status_out: Dictionary = {}
	for zid: StringName in _zone_status:
		status_out[String(zid)] = String(_zone_status[zid])
	var before_out: Dictionary = {}
	if _v2_reveal_all:
		for zid: StringName in _before_zones:
			var b_arr: PackedByteArray = _before_zones[zid] as PackedByteArray
			var entry: Dictionary = _zone_fog.get(zid, {}) as Dictionary
			var bw: int = int(entry.get("w", 0))
			var bh: int = int(entry.get("h", 0))
			if bw > 0 and bh > 0 and b_arr.size() == bw * bh:
				before_out[String(zid)] = {"w": bw, "h": bh, "zstd": b_arr.compress(FileAccess.COMPRESSION_ZSTD)}
	return {
		"version": 2,
		"continent": String(_continent_id),
		"zones": zones_out,
		"status": status_out,
		"continent_unlocked": _continent_unlocked,
		"reveal_all": _v2_reveal_all,
		"before_zones": before_out,
	}


func _apply_v2_snapshot(d: Dictionary) -> void:
	_zone_fog.clear()
	_zone_status.clear()
	_before_zones.clear()
	_v2_reveal_all = false

	var cont_val: Variant = d.get("continent", "")
	var cont_str: String = str(cont_val) if (cont_val is String or cont_val is StringName) else ""
	if not cont_str.is_empty() and _atlas == null:
		_continent_id = StringName(cont_str)

	var zones_in: Variant = d.get("zones", {})
	if zones_in is Dictionary:
		for key: Variant in (zones_in as Dictionary):
			var entry_d: Variant = (zones_in as Dictionary)[key]
			if entry_d is Dictionary:
				import_zone_fog(StringName(str(key)), entry_d as Dictionary)

	var status_in: Variant = d.get("status", {})
	if status_in is Dictionary:
		for key: Variant in (status_in as Dictionary):
			var zid: StringName = StringName(str(key))
			if zid == &"" or (_atlas != null and _atlas.zone(zid) == null):
				continue
			_zone_status[zid] = _normalize_status((status_in as Dictionary)[key])

	_v2_reveal_all = _to_bool(d.get("reveal_all", false), false)
	var before_in: Variant = d.get("before_zones", {})
	if _v2_reveal_all and before_in is Dictionary:
		for key: Variant in (before_in as Dictionary):
			var zid: StringName = StringName(str(key))
			if zid == &"" or (_atlas != null and _atlas.zone(zid) == null):
				continue
			var bdict: Variant = (before_in as Dictionary)[key]
			if not (bdict is Dictionary):
				continue
			var bd: Dictionary = bdict as Dictionary
			var bw: int = _to_int(bd.get("w", 0), 0)
			var bh: int = _to_int(bd.get("h", 0), 0)
			if bw <= 0 or bh <= 0 or bw > MAX_ZONE_GRID_DIM or bh > MAX_ZONE_GRID_DIM:
				continue
			var zstd: PackedByteArray = PackedByteArray()
			if bd.get("zstd") is PackedByteArray:
				zstd = bd["zstd"] as PackedByteArray
			elif bd.has("zstd_b64"):
				zstd = _decode_b64(bd.get("zstd_b64"))
			if zstd.is_empty():
				continue
			var raw: PackedByteArray = zstd.decompress(bw * bh, FileAccess.COMPRESSION_ZSTD)
			if raw.size() == bw * bh:
				_before_zones[zid] = raw

	if _atlas != null:
		for z: Atlas.Zone in _atlas.zones_of(_continent_id):
			_reconcile_zone_entry(z)
			if not _zone_status.has(z.id):
				_zone_status[z.id] = STATUS_UNKNOWN

	var unlocked_in: bool = _to_bool(d.get("continent_unlocked", false), false)
	if _continent_unlocked != unlocked_in:
		_continent_unlocked = unlocked_in
		continent_unlocked_changed.emit(_continent_unlocked)
	replaced.emit()

