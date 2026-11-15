class_name ZoneCatalog
extends RefCounted
## Central lookup for continents, zone metadata, deterministic spatial slots, and zone JSON layouts.

const ZONE_DIR: String = "res://data/zones/"
const SLOT_STRIDE_TILES: int = 512
const TILE_PX: float = 16.0
const SLOT_STRIDE_PX: float = float(SLOT_STRIDE_TILES) * TILE_PX ## 8192 px per spatial slot

static var _zone_specs: Dictionary = {}
static var _slot_cache: Dictionary = {}
static var _continent_layouts: Dictionary = {}


static func continents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = DataRegistry.table("continents").get("continents", [])
	if raw is Array:
		for item: Variant in raw as Array:
			if item is Dictionary:
				out.append(item as Dictionary)
	return out


static func continent(continent_id: String = "main") -> Dictionary:
	for entry: Dictionary in continents():
		if String(entry.get("id", "")) == continent_id:
			return entry
	return {}


static func main_continent() -> Dictionary:
	return continent("main")


static func zone_summaries(continent_id: String = "main") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cont: Dictionary = continent(continent_id)
	var raw: Variant = cont.get("zones", [])
	if raw is Array:
		for item: Variant in raw as Array:
			if item is Dictionary:
				out.append(item as Dictionary)
	return out


static func zone_summary(zone_id: String) -> Dictionary:
	for cont: Dictionary in continents():
		var raw: Variant = cont.get("zones", [])
		if not (raw is Array):
			continue
		for item: Variant in raw as Array:
			if item is Dictionary and String((item as Dictionary).get("id", "")) == zone_id:
				return item as Dictionary
	return {}


static func zone_spec(zone_id: String) -> Dictionary:
	if _zone_specs.has(zone_id):
		return _zone_specs[zone_id] as Dictionary
	var path: String = "%s%s.json" % [ZONE_DIR, zone_id]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_zone_specs[zone_id] = parsed
		return parsed as Dictionary
	push_error("ZoneCatalog: %s is not a valid JSON object" % path)
	return {}


static func clear_cache() -> void:
	_zone_specs.clear()
	_slot_cache.clear()
	_continent_layouts.clear()


static func is_zone_playable(zone_id: String) -> bool:
	var summary: Dictionary = zone_summary(zone_id)
	if not summary.is_empty() and not bool(summary.get("unlocked", false)):
		return false
	return not zone_spec(zone_id).is_empty()


static func playable_zone_ids(continent_id: String = "main") -> Array[String]:
	var out: Array[String] = []
	for z: Dictionary in zone_summaries(continent_id):
		var zid: String = String(z.get("id", ""))
		if not zid.is_empty() and is_zone_playable(zid):
			out.append(zid)
	return out


static func start_zone_id(_continent_id: String = "main") -> String:
	return "start_path"


static func home_zone_id(continent_id: String = "main") -> String:
	for z: Dictionary in zone_summaries(continent_id):
		if bool(z.get("is_home", false)):
			return String(z.get("id", "home_valley"))
	return "home_valley"


## Deterministic slot index per zone_id so prop cells, buildings, and saves stay invariant across unloads.
static func slot_index_for(zone_id: String) -> int:
	if _slot_cache.is_empty():
		var idx: int = 0
		for cont: Dictionary in continents():
			var zones: Variant = cont.get("zones", [])
			if zones is Array:
				for z: Variant in zones as Array:
					if z is Dictionary:
						var zid: String = String((z as Dictionary).get("id", ""))
						if not zid.is_empty() and not _slot_cache.has(zid):
							_slot_cache[zid] = idx
							idx += 1
	if _slot_cache.has(zone_id):
		return int(_slot_cache[zone_id])
	var next_idx: int = _slot_cache.size()
	_slot_cache[zone_id] = next_idx
	return next_idx


static func slot_origin_tile(zone_id: String) -> Vector2i:
	return Vector2i(slot_index_for(zone_id) * SLOT_STRIDE_TILES, 0)


static func slot_origin_px(zone_id: String) -> Vector2:
	return Vector2(slot_origin_tile(zone_id)) * TILE_PX


static func zone_bounds_px(zone_id: String) -> Rect2:
	var spec: Dictionary = zone_spec(zone_id)
	if spec.is_empty():
		return Rect2()
	var origin: Vector2 = slot_origin_px(zone_id)
	var size: Vector2 = Vector2(float(spec.get("width", 104)), float(spec.get("height", 130))) * TILE_PX
	return Rect2(origin, size)


static func zone_id_at(world_pos: Vector2) -> String:
	if world_pos.x < 0.0 or world_pos.y < 0.0 or world_pos.x >= 262144.0 or world_pos.y >= 50000.0:
		return ""
	var slot_idx: int = floori(world_pos.x / SLOT_STRIDE_PX)
	for cont: Dictionary in continents():
		var zones: Variant = cont.get("zones", [])
		if not (zones is Array):
			continue
		for z: Variant in zones as Array:
			if z is Dictionary:
				var zid: String = String((z as Dictionary).get("id", ""))
				if not zid.is_empty() and slot_index_for(zid) == slot_idx:
					return zid
	return ""


const LAYOUT_W: int = 240
const LAYOUT_H: int = 150


## Cached organic continent landmass + 100%-coverage domain-warped Voronoi province grid.
static func continent_layout(continent_id: String = "main") -> Dictionary:
	if _continent_layouts.has(continent_id):
		return _continent_layouts[continent_id] as Dictionary
	var cont: Dictionary = continent(continent_id)
	var zones: Array[Dictionary] = zone_summaries(continent_id)
	var seed_val: int = int(cont.get("seed", 42077))

	var coast_macro: FastNoiseLite = _noise(seed_val ^ 0x11A3, 4.2, 3)
	var coast_detail: FastNoiseLite = _noise(seed_val ^ 0x55C1, 11.5, 2)
	var border_wx: FastNoiseLite = _noise(seed_val ^ 0x9E21, 5.2, 2)
	var border_wy: FastNoiseLite = _noise(seed_val ^ 0x3D47, 5.2, 2)
	var border_det: FastNoiseLite = _noise(seed_val ^ 0x7A09, 15.0, 2)

	var total: int = LAYOUT_W * LAYOUT_H
	var owner_grid: PackedInt32Array = PackedInt32Array()
	owner_grid.resize(total)
	owner_grid.fill(-1)
	var sdf_grid: PackedFloat32Array = PackedFloat32Array()
	sdf_grid.resize(total)

	var seeds_pos: Array[Vector2] = []
	var seeds_weight: Array[float] = []
	var zone_ids: Array[String] = []
	var zone_biomes: Array[String] = []
	for z: Dictionary in zones:
		var pos_arr: Array = z.get("pos", [0.5, 0.5]) as Array
		seeds_pos.append(Vector2(float(pos_arr[0]), float(pos_arr[1])))
		seeds_weight.append(maxf(float(z.get("weight", 1.0)), 0.25))
		zone_ids.append(String(z.get("id", "")))
		zone_biomes.append(String(z.get("biome", "meadow")))

	var counts: PackedInt32Array = PackedInt32Array()
	var sum_x: PackedFloat32Array = PackedFloat32Array()
	var sum_y: PackedFloat32Array = PackedFloat32Array()
	counts.resize(zones.size())
	sum_x.resize(zones.size())
	sum_y.resize(zones.size())
	counts.fill(0)
	sum_x.fill(0.0)
	sum_y.fill(0.0)

	var land_cells: int = 0
	for y: int in range(LAYOUT_H):
		var v: float = (float(y) + 0.5) / float(LAYOUT_H)
		for x: int in range(LAYOUT_W):
			var u: float = (float(x) + 0.5) / float(LAYOUT_W)
			var idx: int = y * LAYOUT_W + x
			var sdf: float = _continent_sdf(u, v, coast_macro, coast_detail)
			sdf_grid[idx] = sdf
			if sdf < 0.0:
				continue
			land_cells += 1
			var wu: float = u + border_wx.get_noise_2d(u, v) * 0.042 + border_det.get_noise_2d(u, v) * 0.011
			var wv: float = v + border_wy.get_noise_2d(u, v) * 0.042 + border_det.get_noise_2d(u + 7.3, v + 3.1) * 0.011
			var wpt: Vector2 = Vector2(wu, wv)
			var best_idx: int = 0
			var best_score: float = INF
			for zi: int in range(seeds_pos.size()):
				var d: float = wpt.distance_to(seeds_pos[zi]) / seeds_weight[zi]
				if d < best_score:
					best_score = d
					best_idx = zi
			owner_grid[idx] = best_idx
			counts[best_idx] += 1
			sum_x[best_idx] += u
			sum_y[best_idx] += v

	var centers: Dictionary = {}
	var areas: Dictionary = {}
	for zi: int in range(zone_ids.size()):
		var zid: String = zone_ids[zi]
		areas[zid] = counts[zi]
		if counts[zi] > 0:
			centers[zid] = Vector2(sum_x[zi] / float(counts[zi]), sum_y[zi] / float(counts[zi]))
		else:
			centers[zid] = seeds_pos[zi]

	## Snap coastal harbors cleanly to outer shoreline of their host zone
	var harbors_uv: Dictionary = {}
	for h_v: Variant in cont.get("harbors", []) as Array:
		if not (h_v is Dictionary):
			continue
		var hd: Dictionary = h_v as Dictionary
		var hid: String = String(hd.get("id", ""))
		var h_zid: String = String(hd.get("zone_id", ""))
		var dir_arr: Array = hd.get("anchor_dir", [0.0, 1.0]) as Array
		var dir_v: Vector2 = Vector2(float(dir_arr[0]), float(dir_arr[1])).normalized()
		var base_c: Vector2 = centers.get(h_zid, Vector2(float((hd.get("pos", [0.5, 0.5]) as Array)[0]), float((hd.get("pos", [0.5, 0.5]) as Array)[1]))) as Vector2
		var target_idx: int = zone_ids.find(h_zid)
		var best_uv: Vector2 = base_c
		var best_proj: float = -INF
		for y: int in range(1, LAYOUT_H - 1):
			for x: int in range(1, LAYOUT_W - 1):
				var idx: int = y * LAYOUT_W + x
				if owner_grid[idx] != target_idx:
					continue
				if owner_grid[idx - 1] >= 0 and owner_grid[idx + 1] >= 0 and owner_grid[idx - LAYOUT_W] >= 0 and owner_grid[idx + LAYOUT_W] >= 0:
					continue
				var uv: Vector2 = Vector2((float(x) + 0.5) / float(LAYOUT_W), (float(y) + 0.5) / float(LAYOUT_H))
				var proj: float = (uv - base_c).dot(dir_v)
				if proj > best_proj:
					best_proj = proj
					best_uv = uv
		harbors_uv[hid] = best_uv

	var layout: Dictionary = {
		"width": LAYOUT_W,
		"height": LAYOUT_H,
		"owner_grid": owner_grid,
		"sdf_grid": sdf_grid,
		"zone_ids": zone_ids,
		"zone_biomes": zone_biomes,
		"zone_centers": centers,
		"zone_areas": areas,
		"harbor_uvs": harbors_uv,
		"land_cells": land_cells,
	}
	_continent_layouts[continent_id] = layout
	return layout


static func continent_zone_at_uv(uv: Vector2, continent_id: String = "main") -> String:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return ""
	var layout: Dictionary = continent_layout(continent_id)
	var x: int = clampi(int(uv.x * float(LAYOUT_W)), 0, LAYOUT_W - 1)
	var y: int = clampi(int(uv.y * float(LAYOUT_H)), 0, LAYOUT_H - 1)
	var grid: PackedInt32Array = layout.get("owner_grid", PackedInt32Array()) as PackedInt32Array
	var zids: Array[String] = layout.get("zone_ids", []) as Array[String]
	var owner: int = grid[y * LAYOUT_W + x]
	if owner >= 0 and owner < zids.size():
		return zids[owner]
	return ""


static func _noise(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


static func _smin(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _ell_sdf(u: float, v: float, cx: float, cy: float, rx: float, ry: float) -> float:
	var dx: float = (u - cx) / rx
	var dy: float = (v - cy) / ry
	return (sqrt(dx * dx + dy * dy) - 1.0) * minf(rx, ry)


## Smooth-min organic continent signed distance: > 0 means land inside continent.
static func _continent_sdf(u: float, v: float, n_macro: FastNoiseLite, n_detail: FastNoiseLite) -> float:
	## Sculpt natural island archipelago lobes stretching SW -> NE with bays, capes & fjord cutouts
	var d: float = _ell_sdf(u, v, 0.095, 0.870, 0.068, 0.088) ## SW start peninsula (~13% x ~17%)
	d = _smin(d, _ell_sdf(u, v, 0.215, 0.720, 0.130, 0.175), 0.075)
	d = _smin(d, _ell_sdf(u, v, 0.365, 0.720, 0.165, 0.155), 0.075)
	d = _smin(d, _ell_sdf(u, v, 0.340, 0.390, 0.165, 0.165), 0.085) ## Northern Hallgrat crags
	d = _smin(d, _ell_sdf(u, v, 0.565, 0.555, 0.195, 0.175), 0.085) ## Central Heartland
	d = _smin(d, _ell_sdf(u, v, 0.745, 0.695, 0.125, 0.140), 0.065) ## SE Nebelbucht cape
	d = _smin(d, _ell_sdf(u, v, 0.735, 0.315, 0.175, 0.165), 0.080) ## Hexenwald massif
	d = _smin(d, _ell_sdf(u, v, 0.855, 0.165, 0.095, 0.100), 0.055) ## NE Spire cape

	## Organic sea bays & fjords carved inward from coastline
	var bay_south: float = _ell_sdf(u, v, 0.530, 0.905, 0.145, 0.095)
	var bay_east: float = _ell_sdf(u, v, 0.945, 0.530, 0.095, 0.125)
	var bay_nw: float = _ell_sdf(u, v, 0.135, 0.310, 0.115, 0.155)
	d = maxf(d, -bay_south)
	d = maxf(d, -bay_east)
	d = maxf(d, -bay_nw)

	## Natural fractured shoreline displacement
	var warp: float = n_macro.get_noise_2d(u, v) * 0.042 + n_detail.get_noise_2d(u, v) * 0.014
	var signed_land: float = -(d + warp)
	if u < 0.020 or u > 0.980 or v < 0.025 or v > 0.975:
		signed_land -= 0.08
	return signed_land
