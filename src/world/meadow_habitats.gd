class_name MeadowHabitats
extends RefCounted
## Pure, deterministic, thread-safe macro-habitat field for the standard meadow biome (`docs/wiesenbiom_ausbau_konzept.md` Stufe 2).
## Divides the shared 5-area meadow (`super 0..4`) into breathing 130–240-tile macro-landscapes while leaving normal meadow between them
## and strictly protecting all story corridors, Glimmrast, Hallgrat, Mornath's arena, Hexenwald (`gloom`), Sonnenquarz-Öde (`arid`),
## Waystones, VistaPoints, and Puzzles:
##  1. `deep_forest`  — Der Tiefe Urforst (Dunkeltannen-Dom): dense giant `ancient_fir` cathedral canopies, moss & fern seas, owls, shrines.
##  2. `wind_meadow`  — Offene Windwiesen & Blütenmeere: 100+ conifer-free open grass hills, huge monoculture flower drifts, solitary hilltop oak.
##  3. `old_pasture`  — Alte Kulturspuren (Verlassenes Weideland): former rows of `orchard_apple` / `orchard_pear`, dry-stone walls, broken fences, sunken paving.
## Pre-baked once on the main thread into `275 x 275` (`RegionMap.CELL = 4` tiles) immutable `PackedFloat32Array` / `PackedByteArray` grids,
## so `PropGenerator` worker threads read them with zero locks, zero allocations, and bit-exact determinism.

const CELL: int = RegionMap.CELL ## 4 tiles per cell -> 275x275 grid

static var _side: int = 0
static var _deep: PackedFloat32Array = PackedFloat32Array()
static var _wind: PackedFloat32Array = PackedFloat32Array()
static var _pasture: PackedFloat32Array = PackedFloat32Array()
static var _flower_idx: PackedByteArray = PackedByteArray()
static var _wind_flowers: PackedStringArray = PackedStringArray(["sunbloom", "moonbell", "spark_poppy", "puffseed"])
static var _installed: bool = false


static func is_installed() -> bool:
	return _installed and _side > 0


## Installs the immutable macro-habitat grids on the main thread right after `BiomeBlend.install`.
static func install(map: RegionMap, relief: Relief, sdf: PackedByteArray) -> void:
	var cfg_table: Dictionary = DataRegistry.table("meadow_habitats")
	var settings: Dictionary = cfg_table.get("settings", {}) as Dictionary
	var affinities: Dictionary = cfg_table.get("super_affinity", {}) as Dictionary
	var wf_arr: Array = settings.get("wind_flowers", ["sunbloom", "moonbell", "spark_poppy", "puffseed"]) as Array
	_wind_flowers.clear()
	for entry: Variant in wf_arr:
		_wind_flowers.append(String(entry))
	if _wind_flowers.is_empty():
		_wind_flowers = PackedStringArray(["sunbloom", "moonbell", "spark_poppy", "puffseed"])

	var side: int = map.grid_size
	_side = side
	var total: int = side * side
	_deep.resize(total)
	_wind.resize(total)
	_pasture.resize(total)
	_flower_idx.resize(total)

	var sanctuaries: PackedVector3Array = _collect_sanctuaries(map)
	var hallgrat_rect: Rect2 = _hallgrat_rect()

	var macro_scale: float = maxf(float(settings.get("macro_scale_tiles", 168.0)), 64.0)
	var warp_amp: float = float(settings.get("warp_tiles", 42.0))
	var sanc_fade: float = maxf(float(settings.get("sanctuary_fade_tiles", 22.0)), 6.0)
	var coast_fade: float = maxf(float(settings.get("coast_fade_tiles", 16.0)), 4.0)
	var seed_base: int = map.world_seed

	var n_warp_x: FastNoiseLite = _make_noise(seed_base + 3101, 1.0 / (macro_scale * 0.72), 2)
	var n_warp_y: FastNoiseLite = _make_noise(seed_base + 3109, 1.0 / (macro_scale * 0.72), 2)
	var n_deep: FastNoiseLite = _make_noise(seed_base + 3121, 1.0 / macro_scale, 2)
	var n_wind: FastNoiseLite = _make_noise(seed_base + 3137, 1.0 / (macro_scale * 1.12), 2)
	var n_pasture: FastNoiseLite = _make_noise(seed_base + 3163, 1.0 / (macro_scale * 0.82), 2)
	var n_flower: FastNoiseLite = _make_noise(seed_base + 3187, 1.0 / 210.0, 1)

	for gy: int in side:
		for gx: int in side:
			var idx: int = gy * side + gx
			var tx: float = float(gx * CELL) + 2.0
			var ty: float = float(gy * CELL) + 2.0
			var tile_i: Vector2i = Vector2i(int(tx), int(ty))
			var super_id: int = map.super_at(tile_i)
			if super_id < 0 or super_id >= 5:
				_deep[idx] = 0.0
				_wind[idx] = 0.0
				_pasture[idx] = 0.0
				_flower_idx[idx] = 0
				continue

			var pos_px: Vector2 = Vector2(tx, ty) * 16.0
			var gloom: float = BiomeBlend.amount_at(pos_px)
			var arid: float = BiomeBlend.arid_at(pos_px)
			if gloom >= 0.12 or arid >= 0.12:
				_deep[idx] = 0.0
				_wind[idx] = 0.0
				_pasture[idx] = 0.0
				_flower_idx[idx] = 0
				continue

			var biome_mask: float = (1.0 - smoothstep(0.01, 0.12, gloom)) * (1.0 - smoothstep(0.01, 0.12, arid))

			# Coast distance mask (keep extreme void shore intact)
			var sdf_idx: int = clampi(tile_i.y, 0, RegionMap.WORLD_TILES - 1) * RegionMap.WORLD_TILES + clampi(tile_i.x, 0, RegionMap.WORLD_TILES - 1)
			var coast_tiles: float = (float(sdf[sdf_idx]) - 128.0) / 8.0
			var coast_mask: float = smoothstep(5.0, 5.0 + coast_fade, coast_tiles)
			if coast_mask <= 0.001:
				_deep[idx] = 0.0
				_wind[idx] = 0.0
				_pasture[idx] = 0.0
				_flower_idx[idx] = 0
				continue

			# Sanctuary protection mask (Glimmrast corridor, Hallgrat, Arena, Waystones, Vistas, Puzzles)
			var sanc_mask: float = _sanctuary_mask(Vector2(tx, ty), sanctuaries, hallgrat_rect, sanc_fade)
			var total_mask: float = biome_mask * coast_mask * sanc_mask
			if total_mask <= 0.001:
				_deep[idx] = 0.0
				_wind[idx] = 0.0
				_pasture[idx] = 0.0
				_flower_idx[idx] = 0
				continue

			var wx: float = tx + n_warp_x.get_noise_2d(tx, ty) * warp_amp
			var wy: float = ty + n_warp_y.get_noise_2d(tx, ty) * warp_amp

			var aff: Dictionary = affinities.get(str(super_id), {}) as Dictionary
			var bias_deep: float = float(aff.get("deep_forest", 0.0))
			var bias_wind: float = float(aff.get("wind_meadow", 0.0))
			var bias_past: float = float(aff.get("old_pasture", 0.0))

			var elev: float = relief.level_at(pos_px)
			var lake_d: float = BiomeBlend.lake_tiles_at(pos_px)
			var dry_land_mask: float = smoothstep(1.0, 5.5, lake_d) if lake_d > -90.0 else 1.0

			# Raw macro fields in [0..1]
			var r_deep: float = (n_deep.get_noise_2d(wx, wy) * 0.5 + 0.5) + bias_deep * 0.45 - maxf(elev - 1.8, 0.0) * 0.14
			var r_wind: float = (n_wind.get_noise_2d(wx, wy) * 0.5 + 0.5) + bias_wind * 0.45 + clampf(elev * 0.06, 0.0, 0.14)
			var r_past: float = (n_pasture.get_noise_2d(wx, wy) * 0.5 + 0.5) + bias_past * 0.42 - maxf(elev - 1.35, 0.0) * 0.24

			# Mutual exclusivity so macro-landscapes never mush into one another and ~40% remains classic mixed meadow:
			var w_deep: float = smoothstep(0.57, 0.76, r_deep) * total_mask * dry_land_mask
			var w_wind: float = smoothstep(0.56, 0.74, r_wind) * (1.0 - smoothstep(0.15, 0.48, w_deep)) * total_mask * dry_land_mask
			var w_past: float = smoothstep(0.58, 0.76, r_past) * (1.0 - smoothstep(0.15, 0.45, w_deep)) * (1.0 - smoothstep(0.20, 0.55, w_wind)) * total_mask * dry_land_mask

			_deep[idx] = clampf(w_deep, 0.0, 1.0)
			_wind[idx] = clampf(w_wind, 0.0, 1.0)
			_pasture[idx] = clampf(w_past, 0.0, 1.0)

			# Dominant monoculture flower index per contiguous Windwiese basin
			var fn: float = n_flower.get_noise_2d(wx * 0.85, wy * 0.85) * 0.5 + 0.5
			var slope_s: float = clampf((relief.level_at(pos_px + Vector2(0.0, -48.0)) - relief.level_at(pos_px + Vector2(0.0, 48.0))) * 1.1, -1.0, 1.0)
			var f_pick: int = 0
			if fn < 0.34:
				f_pick = 0 ## sunbloom (Goldauge / Sonnenwende)
			elif fn < 0.58:
				f_pick = 2 if slope_s >= -0.1 else 1 ## spark_poppy on sunny crests, moonbell on cooler basins
			elif fn < 0.80:
				f_pick = 1 ## moonbell
			else:
				f_pick = 3 ## puffseed
			_flower_idx[idx] = clampi(f_pick, 0, _wind_flowers.size() - 1)

	_installed = true


static func _make_noise(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	if octaves <= 1:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n


static func _hallgrat_rect() -> Rect2:
	var bounds: Array = DataRegistry.table("hallgrat").get("bounds", [94, 290, 246, 412]) as Array
	if bounds.size() == 4:
		var x0: float = float(bounds[0])
		var y0: float = float(bounds[1])
		var x1: float = float(bounds[2])
		var y1: float = float(bounds[3])
		return Rect2(x0 - 18.0, y0 - 18.0, (x1 - x0) + 36.0, (y1 - y0) + 36.0)
	return Rect2(76.0, 272.0, 188.0, 158.0)


static func _collect_sanctuaries(map: RegionMap) -> PackedVector3Array:
	var list: PackedVector3Array = PackedVector3Array()
	var start_t: Vector2 = Vector2(map.start if map.start.x >= 0 else Vector2i(463, 616))
	# Opening footpath & Glimmrast / Valdric / Quarry / Mine / Torben / Gustav story sanctuaries (tile_x, tile_y, inner_radius_tiles)
	list.append(Vector3(start_t.x, start_t.y, 44.0))
	list.append(Vector3(482.0, 660.0, 38.0))
	list.append(Vector3(501.0, 685.0, 36.0)) ## FallenKnight

	var ground: Dictionary = DataRegistry.table("ground")
	for hut_v: Variant in ground.get("huts", []) as Array:
		var h: Dictionary = hut_v as Dictionary
		var t: Array = h.get("tile", []) as Array
		if t.size() == 2:
			var r: float = 52.0 if String(h.get("id", "")) == "hut" else 26.0
			list.append(Vector3(float(t[0]), float(t[1]), r))
	for key_arr: String in ["quarries", "wagons", "mines", "smith_camps", "arenas"]:
		for item_v: Variant in ground.get(key_arr, []) as Array:
			var d: Dictionary = item_v as Dictionary
			var t2: Array = d.get("tile", []) as Array
			if t2.size() == 2:
				var rad: float = 42.0 if key_arr == "arenas" else 30.0
				list.append(Vector3(float(t2[0]), float(t2[1]), rad))

	for st_v: Variant in DataRegistry.table("waystones").get("statues", []) as Array:
		var st: Dictionary = st_v as Dictionary
		var t3: Array = st.get("tile", []) as Array
		if t3.size() == 2:
			list.append(Vector3(float(t3[0]), float(t3[1]), 14.0))

	for vp_v: Variant in DataRegistry.table("vistas").get("vistas", []) as Array:
		var vp: Dictionary = vp_v as Dictionary
		var t4: Array = vp.get("tile", []) as Array
		if t4.size() == 2:
			list.append(Vector3(float(t4[0]), float(t4[1]), 12.0))

	for pz_v: Variant in DataRegistry.table("puzzles").get("placed", []) as Array:
		var pz: Dictionary = pz_v as Dictionary
		var t5: Array = pz.get("tile", []) as Array
		if t5.size() == 2:
			list.append(Vector3(float(t5[0]), float(t5[1]), 16.0))

	return list


static func _sanctuary_mask(tile_pos: Vector2, sanctuaries: PackedVector3Array, hallgrat: Rect2, fade: float) -> float:
	if hallgrat.has_point(tile_pos):
		return 0.0
	var mask: float = 1.0
	# Soft fade around Hallgrat rectangle
	var dx_h: float = maxf(maxf(hallgrat.position.x - tile_pos.x, 0.0), maxf(tile_pos.x - hallgrat.end.x, 0.0))
	var dy_h: float = maxf(maxf(hallgrat.position.y - tile_pos.y, 0.0), maxf(tile_pos.y - hallgrat.end.y, 0.0))
	var d_h: float = sqrt(dx_h * dx_h + dy_h * dy_h)
	if d_h < fade:
		mask = minf(mask, smoothstep(0.0, fade, d_h))
	for s: Vector3 in sanctuaries:
		var d: float = tile_pos.distance_to(Vector2(s.x, s.y))
		if d <= s.z:
			return 0.0
		if d < s.z + fade:
			mask = minf(mask, smoothstep(s.z, s.z + fade, d))
	return mask


## Bilinear sample of a 275x275 float grid at world pixel position `pos_px`. Pure & lock-free.
static func _sample(grid: PackedFloat32Array, pos_px: Vector2) -> float:
	if _side <= 0 or grid.is_empty():
		return 0.0
	var gx: float = clampf(pos_px.x / (16.0 * float(CELL)) - 0.5, 0.0, float(_side - 1))
	var gy: float = clampf(pos_px.y / (16.0 * float(CELL)) - 0.5, 0.0, float(_side - 1))
	var x0: int = int(floorf(gx))
	var y0: int = int(floorf(gy))
	var x1: int = mini(x0 + 1, _side - 1)
	var y1: int = mini(y0 + 1, _side - 1)
	var fx: float = gx - float(x0)
	var fy: float = gy - float(y0)
	var a: float = lerpf(grid[y0 * _side + x0], grid[y0 * _side + x1], fx)
	var b: float = lerpf(grid[y1 * _side + x0], grid[y1 * _side + x1], fx)
	return lerpf(a, b, fy)


## Der Tiefe Urforst (Dunkeltannen-Dom) weight `0..1` at world pixel `pos_px`.
static func deep_forest_at(pos_px: Vector2) -> float:
	return _sample(_deep, pos_px)


## Offene Windwiesen & Blütenmeere weight `0..1` at world pixel `pos_px`.
static func wind_meadow_at(pos_px: Vector2) -> float:
	return _sample(_wind, pos_px)


## Alte Kulturspuren (Verlassenes Weideland) weight `0..1` at world pixel `pos_px`.
static func old_pasture_at(pos_px: Vector2) -> float:
	return _sample(_pasture, pos_px)


## Vector3(deep_forest, wind_meadow, old_pasture) at tile coordinate `at_tiles`.
static func weights_at_tiles(at_tiles: Vector2) -> Vector3:
	var px: Vector2 = at_tiles * 16.0
	return Vector3(_sample(_deep, px), _sample(_wind, px), _sample(_pasture, px))


## Dominant habitat name at world pixel `pos_px` (`"deep_forest"`, `"wind_meadow"`, `"old_pasture"`, or `"meadow"`).
static func dominant_at(pos_px: Vector2) -> String:
	var d: float = _sample(_deep, pos_px)
	var w: float = _sample(_wind, pos_px)
	var p: float = _sample(_pasture, pos_px)
	if d >= 0.42 and d >= w and d >= p:
		return "deep_forest"
	if w >= 0.42 and w >= d and w >= p:
		return "wind_meadow"
	if p >= 0.42 and p >= d and p >= w:
		return "old_pasture"
	return "meadow"


## Single dominant monoculture flower plant id (`sunbloom`, `moonbell`, `spark_poppy`, `puffseed`) for the Windwiese at `at_tiles`.
static func wind_flower_at(at_tiles: Vector2) -> String:
	if _side <= 0 or _flower_idx.is_empty() or _wind_flowers.is_empty():
		return "sunbloom"
	var gx: int = clampi(int(at_tiles.x / float(CELL)), 0, _side - 1)
	var gy: int = clampi(int(at_tiles.y / float(CELL)), 0, _side - 1)
	var pick: int = int(_flower_idx[gy * _side + gx])
	return _wind_flowers[clampi(pick, 0, _wind_flowers.size() - 1)]
