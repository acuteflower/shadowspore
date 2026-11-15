class_name ZoneBuilder
extends RefCounted
## Deterministic synchronous builder for a single ZoneInstance in its assigned spatial slot.

const WATER_SCRIPT_FILL: Color = Color("19414f")
const WATER_SHALLOW_COLOR: Color = Color("286272")
const WATER_FOAM_COLOR: Color = Color(0.72, 0.94, 0.90, 0.35)
const RIM_TINT: Color = Color(0.58, 0.62, 0.70, 1.0)

static var _baked_cache: Dictionary = {}


static func build(world: Variant, zone_id: String, spec: Dictionary, slot_idx: int) -> ZoneInstance:
	var zone: ZoneInstance = ZoneInstance.new()
	zone.configure(zone_id, spec, slot_idx)

	var shape: Dictionary = compute_zone_shape(spec)
	var walkable: PackedByteArray = shape["walkable"] as PackedByteArray
	var water_grid: PackedFloat32Array = shape["water"] as PackedFloat32Array
	zone.walkable_grid = walkable
	zone.water_depth_grid = water_grid

	var world_seed: int = int(spec.get("world_seed", zone_id.hash()))
	var zone_noise: FastNoiseLite = _make_noise(world_seed ^ 0x18B5, 0.035, 2)

	var pond_visuals: Array[Dictionary] = shape["pond_visuals"] as Array[Dictionary]
	if not pond_visuals.is_empty():
		var water_vis: Node2D = _ZoneWaterVisual.new(pond_visuals, zone.slot_origin_px)
		water_vis.name = "WaterBasins"
		zone.decals_root.add_child(water_vis)

	## 3. Build merged physics colliders for blocked rim & deep water
	_build_merged_colliders(zone)

	## 4. Paint grass tiles & ground glow onto shared Ground/Glow TileMapLayers
	_paint_tiles(world, zone, world_seed, zone_noise)

	## 5. Ground decals & procedural earthen path patches
	var path_clear_cells: Dictionary = {}
	_build_decals_and_paths(zone, spec, path_clear_cells)

	## 6. Compute clear mask for POIs, town meadow, roads, and baked berry-free lanes
	var blocked_cells: Dictionary = {}
	var berry_free_cells: Dictionary = {}
	_populate_clear_masks(zone, spec, blocked_cells, berry_free_cells, path_clear_cells)

	## 7. Register spawns
	var w: int = zone.size_tiles.x
	var h: int = zone.size_tiles.y
	var spawns_raw: Dictionary = spec.get("spawns", {}) as Dictionary
	for spawn_key: String in spawns_raw:
		var sp: Dictionary = spawns_raw[spawn_key] as Dictionary
		var st: Array = sp.get("tile", [w / 2, h / 2]) as Array
		zone.spawns[spawn_key] = zone.slot_origin_px + Vector2(float(st[0]), float(st[1])) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)

	## 8. Town area bounding rect in global pixels (for home_valley)
	if spec.has("town_area"):
		var ta: Dictionary = spec.get("town_area", {}) as Dictionary
		var tr: Array = ta.get("tile_rect", [26, 22, 114, 106]) as Array
		if tr.size() >= 4:
			zone.town_area_px = Rect2(
				zone.slot_origin_px + Vector2(float(tr[0]), float(tr[1])) * ZoneCatalog.TILE_PX,
				Vector2(float(tr[2]), float(tr[3])) * ZoneCatalog.TILE_PX
			)

	## 9. Place landmarks & POIs (manhole, fallen_knight, signpost, hut, waystones, portals)
	_build_pois(world, zone, spec, blocked_cells)

	## 10. Visual woodland rim props along perimeter & deterministic flora inside zone
	_build_perimeter_flora(zone, spec, world_seed)
	_build_interior_props(world, zone, spec, world_seed, blocked_cells, berry_free_cells)

	return zone


## Shared pure deterministic shape generator for both runtime ZoneBuilder carving and Tier 1 ZoneMapView rendering.
static func compute_zone_shape(spec: Dictionary) -> Dictionary:
	var zid: String = String(spec.get("id", "zone"))
	var w: int = int(spec.get("width", 104))
	var h: int = int(spec.get("height", 130))
	var world_seed: int = int(spec.get("world_seed", zid.hash()))

	var macro_noise: FastNoiseLite = _make_noise(world_seed ^ 0x29A1, 0.036, 2)
	var edge_noise: FastNoiseLite = _make_noise(world_seed ^ 0x41F2, 0.11, 2)
	var patch_noise: FastNoiseLite = _make_noise(world_seed ^ 0x7E03, 0.14, 2)

	var rim_cfg: Dictionary = spec.get("perimeter", {}) as Dictionary
	var rim_margin: float = float(rim_cfg.get("margin", 9))
	var rim_depth: float = float(rim_cfg.get("noise_depth", 11))

	var corridors: Array[Rect2i] = []
	for p_v: Variant in spec.get("portals", []) as Array:
		if not (p_v is Dictionary):
			continue
		var p: Dictionary = p_v as Dictionary
		var t_arr: Array = p.get("tile", [0, 0]) as Array
		if t_arr.size() < 2:
			continue
		var pt: Vector2i = Vector2i(int(t_arr[0]), int(t_arr[1]))
		var dir_str: String = String(p.get("dir", "east"))
		var corr: Rect2i = Rect2i(pt - Vector2i(6, 5), Vector2i(13, 11))
		match dir_str:
			"east":
				corr = Rect2i(pt.x - 14, pt.y - 5, 22, 11)
			"west":
				corr = Rect2i(2, pt.y - 5, pt.x + 12, 11)
			"north":
				corr = Rect2i(pt.x - 5, 2, 11, pt.y + 12)
			"south":
				corr = Rect2i(pt.x - 5, pt.y - 12, 11, h - pt.y + 12)
		corridors.append(corr)

	for cr_v: Variant in spec.get("clear_rects", []) as Array:
		if cr_v is Array and (cr_v as Array).size() >= 4:
			var r: Array = cr_v as Array
			corridors.append(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
	if spec.has("town_area"):
		var tr: Array = (spec.get("town_area", {}) as Dictionary).get("tile_rect", []) as Array
		if tr.size() >= 4:
			corridors.append(Rect2i(int(tr[0]), int(tr[1]), int(tr[2]), int(tr[3])))
	if spec.has("manhole"):
		var mp: Array = (spec.get("manhole", {}) as Dictionary).get("pos", [262, 240]) as Array
		corridors.append(Rect2i(int(float(mp[0]) / 16.0) - 8, int(float(mp[1]) / 16.0) - 8, 17, 17))
	if spec.has("hut"):
		var ht: Array = (spec.get("hut", {}) as Dictionary).get("tile", [88, 68]) as Array
		corridors.append(Rect2i(int(ht[0]) - 10, int(ht[1]) - 8, 21, 17))
	if spec.has("fallen_knight"):
		var kt: Array = (spec.get("fallen_knight", {}) as Dictionary).get("tile", [55, 91]) as Array
		corridors.append(Rect2i(int(kt[0]) - 6, int(kt[1]) - 6, 13, 13))
	if spec.has("signpost"):
		var st: Array = (spec.get("signpost", {}) as Dictionary).get("tile", [63, 105]) as Array
		corridors.append(Rect2i(int(st[0]) - 5, int(st[1]) - 5, 11, 11))
	for ws_v: Variant in spec.get("waystones", []) as Array:
		if ws_v is Dictionary:
			var wt: Array = (ws_v as Dictionary).get("tile", [76, 66]) as Array
			if wt.size() >= 2:
				corridors.append(Rect2i(int(wt[0]) - 5, int(wt[1]) - 5, 11, 11))

	var total: int = w * h
	var walkable: PackedByteArray = PackedByteArray()
	walkable.resize(total)
	var water: PackedFloat32Array = PackedFloat32Array()
	water.resize(total)
	water.fill(-1.0)

	var half_w: float = maxf(float(w) * 0.5 - rim_margin, 8.0)
	var half_h: float = maxf(float(h) * 0.5 - rim_margin, 8.0)
	var noise_scale: float = rim_depth / maxf(minf(half_w, half_h), 12.0)

	for ly: int in range(h):
		for lx: int in range(w):
			var nx: float = (float(lx) + 0.5 - float(w) * 0.5) / half_w
			var ny: float = (float(ly) + 0.5 - float(h) * 0.5) / half_h
			var super_r: float = pow(pow(absf(nx), 2.7) + pow(absf(ny), 2.7), 1.0 / 2.7)
			var disp: float = (macro_noise.get_noise_2d(float(lx), float(ly)) * 0.72 + edge_noise.get_noise_2d(float(lx), float(ly)) * 0.28) * noise_scale
			var dist_edge: int = mini(mini(lx, w - 1 - lx), mini(ly, h - 1 - ly))
			var is_land: bool = (super_r + disp) <= 1.04 and dist_edge >= 2
			if not is_land and dist_edge >= 2:
				var pt: Vector2i = Vector2i(lx, ly)
				for corr: Rect2i in corridors:
					if corr.has_point(pt):
						is_land = true
						break
			walkable[ly * w + lx] = 1 if is_land else 0

	## Keep curvy paths open across zone
	if zid == "start_path":
		_carve_walk_line(walkable, w, h, Vector2(17, 16), Vector2(63, 105), 5)
		_carve_walk_line(walkable, w, h, Vector2(63, 105), Vector2(96, 103), 5)
	for pp_v: Variant in spec.get("path_patches", []) as Array:
		if not (pp_v is Dictionary):
			continue
		var pts_raw: Array = (pp_v as Dictionary).get("points", []) as Array
		for i: int in range(pts_raw.size() - 1):
			var a: Array = pts_raw[i] as Array
			var b: Array = pts_raw[i + 1] as Array
			if a.size() >= 2 and b.size() >= 2:
				_carve_walk_line(walkable, w, h, Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])), 4)

	## Organic warped pond carving + shore polygons
	var pond_visuals: Array[Dictionary] = []
	for w_v: Variant in spec.get("water_rects", []) as Array:
		if not (w_v is Dictionary):
			continue
		var r_arr: Array = (w_v as Dictionary).get("tile_rect", []) as Array
		if r_arr.size() < 4:
			continue
		var rx: int = int(r_arr[0])
		var ry: int = int(r_arr[1])
		var rw: int = int(r_arr[2])
		var rh: int = int(r_arr[3])
		var cx: float = float(rx) + float(rw) * 0.5
		var cy: float = float(ry) + float(rh) * 0.5
		var rad_x: float = maxf(float(rw) * 0.5, 2.0)
		var rad_y: float = maxf(float(rh) * 0.5, 2.0)
		for ly: int in range(maxi(2, ry - 4), mini(h - 2, ry + rh + 4)):
			for lx: int in range(maxi(2, rx - 4), mini(w - 2, rx + rw + 4)):
				var nx_w: float = (float(lx) + 0.5 - cx) / rad_x
				var ny_w: float = (float(ly) + 0.5 - cy) / rad_y
				var warp: float = macro_noise.get_noise_2d(float(lx), float(ly)) * 0.22 + patch_noise.get_noise_2d(float(lx), float(ly)) * 0.14
				var dist: float = sqrt(nx_w * nx_w + ny_w * ny_w) + warp
				if dist < 1.0:
					walkable[ly * w + lx] = 1
					water[ly * w + lx] = clampf((1.0 - dist) * 1.45, 0.1, 1.0)
		var poly_local: PackedVector2Array = PackedVector2Array()
		var steps: int = 44
		for i: int in range(steps):
			var ang: float = TAU * float(i) / float(steps)
			var sx: float = cx + cos(ang) * rad_x
			var sy: float = cy + sin(ang) * rad_y
			var w_ang: float = macro_noise.get_noise_2d(sx, sy) * 0.22 + patch_noise.get_noise_2d(sx, sy) * 0.14
			var scale: float = clampf(1.0 - w_ang, 0.65, 1.28)
			poly_local.append(Vector2(cx + cos(ang) * rad_x * scale, cy + sin(ang) * rad_y * scale))
		pond_visuals.append({
			"center": Vector2(cx, cy) * ZoneCatalog.TILE_PX,
			"radius": Vector2(rad_x, rad_y) * ZoneCatalog.TILE_PX,
			"poly_tile": poly_local,
		})

	return {
		"w": w,
		"h": h,
		"walkable": walkable,
		"water": water,
		"pond_visuals": pond_visuals,
	}


static func _carve_walk_line(walkable: PackedByteArray, w: int, h: int, a: Vector2, b: Vector2, rad: int) -> void:
	var dist: float = maxf(a.distance_to(b), 1.0)
	var steps: int = int(ceilf(dist)) + 1
	var r2: int = rad * rad
	for i: int in range(steps):
		var pt: Vector2 = a.lerp(b, float(i) / float(maxi(steps - 1, 1)))
		var cx: int = roundi(pt.x)
		var cy: int = roundi(pt.y)
		for dy: int in range(-rad, rad + 1):
			for dx: int in range(-rad, rad + 1):
				if dx * dx + dy * dy > r2:
					continue
				var tx: int = cx + dx
				var ty: int = cy + dy
				if tx >= 2 and ty >= 2 and tx < w - 2 and ty < h - 2:
					walkable[ty * w + tx] = 1


static func _make_noise(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


static func _build_merged_colliders(zone: ZoneInstance) -> void:
	var w: int = zone.size_tiles.x
	var h: int = zone.size_tiles.y
	var open_runs: Dictionary = {} ## "x0:x1" -> start_y
	for ly: int in range(h):
		var runs: Array[Vector2i] = []
		var run_start: int = -1
		for lx: int in range(w):
			var local: Vector2i = Vector2i(lx, ly)
			var solid: bool = (not zone.is_walkable_local(local)) or (zone.water_depth_at(zone.slot_origin_px + Vector2(lx, ly) * 16.0 + Vector2(8.0, 8.0)) >= 0.48)
			if solid and run_start < 0:
				run_start = lx
			elif not solid and run_start >= 0:
				runs.append(Vector2i(run_start, lx))
				run_start = -1
		if run_start >= 0:
			runs.append(Vector2i(run_start, w))
		var active_keys: Array[String] = []
		for run: Vector2i in runs:
			var k: String = "%d:%d" % [run.x, run.y]
			active_keys.append(k)
			if not open_runs.has(k):
				open_runs[k] = ly
		for existing: String in open_runs.keys():
			if active_keys.has(existing):
				continue
			_emit_collider_run(zone.collision_root, existing, int(open_runs[existing]), ly)
			open_runs.erase(existing)
	for remaining: String in open_runs.keys():
		_emit_collider_run(zone.collision_root, remaining, int(open_runs[remaining]), h)


static func _emit_collider_run(body: StaticBody2D, key: String, y0: int, y1: int) -> void:
	var x0: int = key.get_slice(":", 0).to_int()
	var x1: int = key.get_slice(":", 1).to_int()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(float(x1 - x0), float(y1 - y0)) * ZoneCatalog.TILE_PX
	shape.shape = rect
	shape.position = Vector2(float(x0 + x1) * 0.5, float(y0 + y1) * 0.5) * ZoneCatalog.TILE_PX
	body.add_child(shape)


static func _paint_tiles(world: Variant, zone: ZoneInstance, world_seed: int, zone_noise: FastNoiseLite) -> void:
	var ground: TileMapLayer = world.get("_ground") as TileMapLayer
	var glow: TileMapLayer = world.get("_glow") as TileMapLayer
	var tiles_table: Dictionary = DataRegistry.table("grass_tiles")
	if ground == null or tiles_table.is_empty():
		return
	var plain_opts: Array = tiles_table.get("plain", [[0, 0]]) as Array
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var w: int = zone.size_tiles.x
	var h: int = zone.size_tiles.y
	for ly: int in range(h):
		for lx: int in range(w):
			var gcell: Vector2i = zone.slot_origin_tile + Vector2i(lx, ly)
			var wpos: Vector2 = Vector2(gcell) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
			if zone.water_depth_at(wpos) >= 0.45:
				continue ## deep water basin shows through without grass tiles
			rng.seed = int(world_seed) + lx * 73856093 ^ ly * 19349663
			var density: float = zone_noise.get_noise_2d(float(lx), float(ly)) * 0.5 + 0.5
			var kind: String = "plain"
			if zone.is_walkable_local(Vector2i(lx, ly)) and zone.water_depth_at(wpos) < 0.05 and world.has_method("_pick_tile_kind"):
				kind = String(world.call("_pick_tile_kind", density, rng))
			var opts: Array = tiles_table.get(kind, plain_opts) as Array
			if opts.is_empty():
				opts = plain_opts
			var chosen_idx: int = rng.randi() % opts.size()
			var atlas: Array = opts[chosen_idx] as Array
			var atlas_coord: Vector2i = Vector2i(int(atlas[0]), int(atlas[1]))
			ground.set_cell(gcell, 0, atlas_coord)
			zone.painted_cells.append(gcell)
			if glow != null and TestLevel.GLOW_KINDS.has(kind):
				glow.set_cell(gcell, 0, atlas_coord)
				zone.glow_cells.append(gcell)
				if world.has_method("_add_glow"):
					world.call("_add_glow", gcell, kind, chosen_idx, zone.fx_root)


static func _build_decals_and_paths(zone: ZoneInstance, spec: Dictionary, path_clear_cells: Dictionary) -> void:
	for dec_v: Variant in spec.get("decals", []) as Array:
		if not (dec_v is Dictionary):
			continue
		var d: Dictionary = dec_v as Dictionary
		var tex_path: String = String(d.get("texture", ""))
		var mask_path: String = String(d.get("mask", ""))
		var pos_arr: Array = d.get("pos", [0, 0]) as Array
		if tex_path.is_empty() or pos_arr.size() < 2 or not ResourceLoader.exists(tex_path):
			continue
		var top_left: Vector2 = zone.slot_origin_px + Vector2(float(pos_arr[0]), float(pos_arr[1]))
		var glow_path: String = String(d.get("glow", ""))
		var dec: GroundDecal = GroundDecal.new()
		dec.setup(tex_path, mask_path, top_left, glow_path)
		zone.decals_root.add_child(dec)
		zone.decals.append(dec)

	for pp_v: Variant in spec.get("path_patches", []) as Array:
		if not (pp_v is Dictionary):
			continue
		var pp: Dictionary = pp_v as Dictionary
		var raw_pts: Array = pp.get("points", []) as Array
		if raw_pts.size() < 2:
			continue
		var world_pts: PackedVector2Array = PackedVector2Array()
		for pt_v: Variant in raw_pts:
			if pt_v is Array and (pt_v as Array).size() >= 2:
				var p: Array = pt_v as Array
				world_pts.append(zone.slot_origin_px + Vector2(float(p[0]), float(p[1])) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0))
		var width_px: float = float(pp.get("width", 44.0))
		var patch: ZonePathPatch = ZonePathPatch.new()
		patch.setup(world_pts, width_px, String(pp.get("surface", "path")))
		zone.decals_root.add_child(patch)
		zone.decals.append(patch)

		## Keep bushes/trees out of drawn roads
		var reach: int = ceili((width_px * 0.5 + 14.0) / ZoneCatalog.TILE_PX)
		for i: int in range(world_pts.size() - 1):
			var a: Vector2 = world_pts[i]
			var b: Vector2 = world_pts[i + 1]
			var dist: float = maxf(a.distance_to(b), 1.0)
			var steps: int = int(dist / 8.0) + 1
			for s: int in range(steps):
				var p_world: Vector2 = a.lerp(b, float(s) / float(maxi(steps - 1, 1)))
				_mark_clear_radius(path_clear_cells, p_world, reach)


static func _populate_clear_masks(zone: ZoneInstance, spec: Dictionary, blocked_cells: Dictionary, berry_free: Dictionary, path_clear_cells: Dictionary) -> void:
	blocked_cells.merge(path_clear_cells)

	for cr_v: Variant in spec.get("clear_rects", []) as Array:
		if not (cr_v is Array) or (cr_v as Array).size() < 4:
			continue
		var cr: Array = cr_v as Array
		var x0: int = int(cr[0])
		var y0: int = int(cr[1])
		var x1: int = x0 + int(cr[2])
		var y1: int = y0 + int(cr[3])
		for ly: int in range(y0, y1):
			for lx: int in range(x0, x1):
				blocked_cells[zone.slot_origin_tile + Vector2i(lx, ly)] = true

	if bool(spec.get("berry_free_baked", false)):
		var offset_arr: Array = spec.get("old_world_tile_offset", [0, 0]) as Array
		var ox: int = int(offset_arr[0]) if offset_arr.size() >= 2 else 0
		var oy: int = int(offset_arr[1]) if offset_arr.size() >= 2 else 0
		for span: Array in _baked_berry_free():
			if span.size() < 3:
				continue
			var ly: int = int(span[1]) - oy
			if ly < 0 or ly >= zone.size_tiles.y:
				continue
			var lx0: int = maxi(0, int(span[0]) - ox)
			var lx1: int = mini(zone.size_tiles.x - 1, int(span[2]) - ox)
			for lx: int in range(lx0, lx1 + 1):
				berry_free[zone.slot_origin_tile + Vector2i(lx, ly)] = true

	for p_v: Variant in spec.get("portals", []) as Array:
		if p_v is Dictionary:
			var t_arr: Array = (p_v as Dictionary).get("tile", [0, 0]) as Array
			if t_arr.size() >= 2:
				var p_world: Vector2 = zone.slot_origin_px + Vector2(float(t_arr[0]), float(t_arr[1])) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
				_mark_clear_radius(blocked_cells, p_world, 4)

	for g_v: Variant in spec.get("guards", []) as Array:
		if g_v is Dictionary:
			var pos_arr: Array = (g_v as Dictionary).get("pos", [0, 0]) as Array
			if pos_arr.size() >= 2:
				var g_world: Vector2 = zone.slot_origin_px + Vector2(float(pos_arr[0]), float(pos_arr[1]))
				_mark_clear_radius(blocked_cells, g_world, 3)


static func _build_pois(world: Variant, zone: ZoneInstance, spec: Dictionary, blocked_cells: Dictionary) -> void:
	var props_parent: Node = world.get("_props") as Node
	if props_parent == null:
		props_parent = zone

	if spec.has("manhole"):
		var mh: Dictionary = spec.get("manhole", {}) as Dictionary
		var m_pos: Array = mh.get("pos", [262, 240]) as Array
		if m_pos.size() >= 2:
			var cover: ManholeCover = ManholeCover.new()
			cover.position = zone.slot_origin_px + Vector2(float(m_pos[0]), float(m_pos[1]))
			world.add_child(cover)
			zone.cover_node = cover
			world.set("cover_node", cover)
			_mark_clear_radius(blocked_cells, cover.position, 4)

	if spec.has("fallen_knight"):
		var fk: Dictionary = spec.get("fallen_knight", {}) as Dictionary
		var kt: Array = fk.get("tile", [55, 91]) as Array
		if kt.size() >= 2:
			var knight: FallenKnight = FallenKnight.new()
			knight.name = "FallenKnight"
			knight.position = zone.slot_origin_px + Vector2(float(kt[0]), float(kt[1])) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
			props_parent.add_child(knight)
			zone.fallen_knight = knight
			world.set("fallen_knight", knight)
			_mark_clear_radius(blocked_cells, knight.position, 3)

	if spec.has("signpost"):
		var sp_spec: Dictionary = spec.get("signpost", {}) as Dictionary
		var st: Array = sp_spec.get("tile", [63, 105]) as Array
		if st.size() >= 2:
			var post: Signpost = Signpost.new()
			post.name = "Signpost_%s" % String(sp_spec.get("id", "post"))
			post.variant = int(sp_spec.get("variant", 0))
			post.dialogue_id = String(sp_spec.get("dialogue", "sign_crossroad"))
			post.flag = String(sp_spec.get("flag", "read_sign"))
			post.position = zone.slot_origin_px + Vector2(float(st[0]), float(st[1])) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
			props_parent.add_child(post)
			zone.poi_nodes.append(post)
			_mark_clear_radius(blocked_cells, post.position, 3)

	if spec.has("hut"):
		var hut_spec: Dictionary = spec.get("hut", {}) as Dictionary
		var ht: Array = hut_spec.get("tile", [88, 68]) as Array
		if ht.size() >= 2:
			var hut: Hut = Hut.new()
			hut.name = "Hut_home"
			hut.interior_id = String(hut_spec.get("interior", "hut"))
			var renewed: bool = bool(world.call("is_hut_renewed")) if world.has_method("is_hut_renewed") else false
			hut.art = "hut_renewed" if renewed else String(hut_spec.get("art", "hut"))
			hut.yard_props = (hut_spec.get("yard", {}) as Dictionary).get("props", []) as Array
			hut.position = zone.slot_origin_px + Vector2(float(ht[0]), float(ht[1])) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
			props_parent.add_child(hut)
			var interiors: Interiors = world.get("_interiors") as Interiors
			if interiors != null:
				interiors.register_entrance(hut.interior_id, hut)
			zone.hut_node = hut
			if world.has_method("set_hut_node"):
				world.call("set_hut_node", hut)
			_mark_clear_radius(blocked_cells, hut.position, 6)

	for ws_v: Variant in spec.get("waystones", []) as Array:
		if not (ws_v is Dictionary):
			continue
		var ws: Dictionary = ws_v as Dictionary
		var wt: Array = ws.get("tile", [76, 66]) as Array
		if wt.size() < 2:
			continue
		var global_tile: Vector2i = zone.slot_origin_tile + Vector2i(int(wt[0]), int(wt[1]))
		var statue: WaystoneStatue = WaystoneStatue.new()
		statue.id = String(ws.get("id", "home_valley_stone"))
		statue.display_name = String(ws.get("name", "Wegstein"))
		statue.reveal_cells = float(ws.get("reveal", 18.0))
		statue.paved = bool(ws.get("paved", false))
		statue.name = "Waystone_%s" % statue.id
		statue.position = Vector2(global_tile) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
		if world.has_method("register_zone_waystone"):
			world.call("register_zone_waystone", statue, ws, global_tile)
		props_parent.add_child(statue)
		zone.poi_nodes.append(statue)
		zone.waystone_ids.append(statue.id)
		_mark_clear_radius(blocked_cells, statue.position, 4)

	for p_v: Variant in spec.get("portals", []) as Array:
		if not (p_v is Dictionary):
			continue
		var p_spec: Dictionary = p_v as Dictionary
		var pt: Array = p_spec.get("tile", [0, 0]) as Array
		if pt.size() < 2:
			continue
		var portal: ZonePortal = ZonePortal.new()
		portal.setup(world, zone.zone_id, p_spec)
		portal.position = zone.slot_origin_px + Vector2(float(pt[0]), float(pt[1])) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
		props_parent.add_child(portal)
		zone.portals[portal.portal_id] = portal
		zone.poi_nodes.append(portal)


static func _build_perimeter_flora(zone: ZoneInstance, spec: Dictionary, world_seed: int) -> void:
	var rim_cfg: Dictionary = spec.get("perimeter", {}) as Dictionary
	if not bool(rim_cfg.get("tree_wall", true)):
		return
	var tree_entry: Dictionary = DataRegistry.get_entry("plants", "tree")
	var rock_entry: Dictionary = DataRegistry.get_entry("plants", "rock")
	var tree_tex_path: String = String(tree_entry.get("texture", "res://assets/props/tree.png"))
	var rock_tex_path: String = String(rock_entry.get("texture", "res://assets/props/rock.png"))
	var tree_tex: Texture2D = load(tree_tex_path) as Texture2D if ResourceLoader.exists(tree_tex_path) else null
	var rock_tex: Texture2D = load(rock_tex_path) as Texture2D if ResourceLoader.exists(rock_tex_path) else null
	if tree_tex == null:
		return
	var tree_cols: int = maxi(int(tree_entry.get("columns", 6)), 1)
	var tree_rows: int = maxi(int(tree_entry.get("rows", 1)), 1)
	var rock_cols: int = maxi(int(rock_entry.get("columns", 4)), 1)
	var w: int = zone.size_tiles.x
	var h: int = zone.size_tiles.y
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x55AA1234

	var wall_props: Node2D = Node2D.new()
	wall_props.name = "PerimeterFlora"
	wall_props.y_sort_enabled = true
	zone.add_child(wall_props)

	for ly: int in range(3, h - 3, 2):
		for lx: int in range(3, w - 3, 2):
			var local: Vector2i = Vector2i(lx, ly)
			if zone.is_walkable_local(local):
				continue
			## Skip outer 2 border tiles to avoid visual bleed outside zone bounds
			var near_land: bool = false
			for dy: int in range(-4, 5):
				for dx: int in range(-4, 5):
					if zone.is_walkable_local(Vector2i(lx + dx, ly + dy)):
						near_land = true
						break
				if near_land:
					break
			if not near_land:
				continue
			if rng.randf() > 0.42:
				continue
			var jitter: Vector2 = Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
			var sp: Sprite2D = Sprite2D.new()
			sp.position = Vector2(lx, ly) * ZoneCatalog.TILE_PX + Vector2(8.0, 12.0) + jitter
			if rock_tex != null and rng.randf() < 0.22:
				sp.texture = rock_tex
				sp.hframes = rock_cols
				sp.vframes = 1
				sp.frame = rng.randi() % rock_cols
				var rh: float = float(rock_tex.get_height())
				sp.offset = Vector2(0.0, -rh * 0.38)
			else:
				sp.texture = tree_tex
				sp.hframes = tree_cols
				sp.vframes = tree_rows
				sp.frame = rng.randi() % tree_cols
				var th: float = float(tree_tex.get_height()) / float(tree_rows)
				sp.offset = Vector2(0.0, -th * 0.42)
				sp.modulate = RIM_TINT
			wall_props.add_child(sp)


static func _build_interior_props(world: Variant, zone: ZoneInstance, spec: Dictionary, world_seed: int, blocked_cells: Dictionary, berry_free: Dictionary) -> void:
	var props_parent: Node = world.get("_props") as Node
	if props_parent == null:
		return
	var town_mgr: Variant = world.call("town") if world.has_method("town") else null
	var cleared_map: Dictionary = (town_mgr.get("cleared") as Dictionary) if town_mgr != null else {}
	var world_things: Dictionary = world.get("_things") as Dictionary

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var w: int = zone.size_tiles.x
	var h: int = zone.size_tiles.y
	var occupied_trees: Array[Vector2] = []
	var home_center: Vector2 = zone.bounds_px.get_center()
	var is_start: bool = (zone.zone_id == "start_path")

	for ly: int in range(6, h - 6):
		for lx: int in range(6, w - 6):
			var local: Vector2i = Vector2i(lx, ly)
			if not zone.is_walkable_local(local):
				continue
			var gcell: Vector2i = zone.slot_origin_tile + local
			if blocked_cells.has(gcell) or cleared_map.has(gcell):
				continue
			var wpos: Vector2 = PropGenerator.position_of(gcell)
			if not zone.clear_world_pos_clear_for_prop(wpos, 18.0):
				continue
			rng.seed = world_seed + lx * 49157 + ly * 98317
			var roll: float = rng.randf()
			var kind: String = ""

			var dist_home_ratio: float = wpos.distance_to(home_center) / maxf(float(mini(w, h)) * 8.0, 1.0)
			if roll < (0.018 if is_start else clampf(0.008 + dist_home_ratio * 0.015, 0.006, 0.024)):
				if _far_from(wpos, occupied_trees, 56.0):
					kind = "birch" if rng.randf() < 0.25 else "tree"
					occupied_trees.append(wpos)
			elif roll < 0.036:
				kind = "iron_rock" if (not is_start and rng.randf() < 0.28) else "rock"
				if not _far_from(wpos, occupied_trees, 34.0):
					kind = ""
			elif roll < 0.068 and not berry_free.has(gcell):
				kind = "berry_bush" if rng.randf() < 0.42 else "bush"
			elif roll < 0.095:
				var small_pool: Array[String] = ["grass", "blossom", "pebble", "mushroom", "moonbell", "wound_leaf", "glowfern"]
				kind = small_pool[rng.randi() % small_pool.size()]

			if kind.is_empty():
				continue
			var entry: Dictionary = DataRegistry.get_entry("plants", kind)
			var scene_path: String = String(entry.get("scene", ""))
			if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
				continue
			var cols: int = maxi(int(entry.get("columns", 1)), 1)
			var variant: int = rng.randi() % cols
			var scene: PackedScene = load(scene_path) as PackedScene
			var thing: WorldProp = scene.instantiate() as WorldProp
			thing.setup(world, gcell, kind, variant)
			thing.position = wpos
			props_parent.add_child(thing)
			zone.things[gcell] = thing
			world_things[gcell] = thing
			if world.has_method("thing_state"):
				var saved_state: Dictionary = world.call("thing_state", gcell) as Dictionary
				if not saved_state.is_empty():
					thing.apply_state(saved_state, "")


static func _far_from(p: Vector2, existing: Array[Vector2], min_dist: float) -> bool:
	var d2: float = min_dist * min_dist
	for o: Vector2 in existing:
		if p.distance_squared_to(o) < d2:
			return false
	return true


static func _mark_clear_radius(map: Dictionary, world_pos: Vector2, radius_tiles: int) -> void:
	var c: Vector2i = Vector2i(floori(world_pos.x / ZoneCatalog.TILE_PX), floori(world_pos.y / ZoneCatalog.TILE_PX))
	for dy: int in range(-radius_tiles, radius_tiles + 1):
		for dx: int in range(-radius_tiles, radius_tiles + 1):
			map[c + Vector2i(dx, dy)] = true


static func _baked_berry_free() -> Array:
	if _baked_cache.has("berry_free"):
		return _baked_cache["berry_free"] as Array
	var data: Dictionary = DataRegistry.table("ground_baked")
	var arr: Array = data.get("berry_free", []) as Array
	_baked_cache["berry_free"] = arr
	return arr


class _ZoneWaterVisual extends Node2D:
	var _ponds: Array[Dictionary] = []
	var _origin: Vector2 = Vector2.ZERO
	var _t: float = 0.0

	func _init(ponds: Array[Dictionary], origin: Vector2) -> void:
		_ponds = ponds
		_origin = origin
		z_as_relative = false
		z_index = -9

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for pond: Dictionary in _ponds:
			var center: Vector2 = pond["center"] as Vector2
			var poly_t: PackedVector2Array = pond.get("poly_tile", PackedVector2Array()) as PackedVector2Array
			if poly_t.size() >= 3:
				_draw_scaled_poly(poly_t, center, 1.02, WATER_SHALLOW_COLOR, true)
				_draw_scaled_poly(poly_t, center, 0.78, WATER_SCRIPT_FILL, true)
				var ripple_scale: float = 0.68 + 0.04 * sin(_t * 1.6)
				_draw_scaled_poly(poly_t, center, ripple_scale, WATER_FOAM_COLOR, false)
			else:
				var r: Vector2 = pond["radius"] as Vector2
				_draw_ellipse(center, r * 1.02, WATER_SHALLOW_COLOR)
				_draw_ellipse(center, r * 0.78, WATER_SCRIPT_FILL)
				var ripple_scale: float = 0.68 + 0.04 * sin(_t * 1.6)
				_draw_ellipse(center, r * ripple_scale, WATER_FOAM_COLOR, false)

	func _draw_scaled_poly(poly_tiles: PackedVector2Array, center: Vector2, scale: float, col: Color, filled: bool) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		for pt: Vector2 in poly_tiles:
			var world_p: Vector2 = pt * ZoneCatalog.TILE_PX
			pts.append(center + (world_p - center) * scale)
		if filled:
			draw_colored_polygon(pts, col)
		else:
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0, true)

	func _draw_ellipse(center: Vector2, radius: Vector2, col: Color, filled: bool = true) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		var steps: int = 36
		for i: int in range(steps):
			var a: float = TAU * float(i) / float(steps)
			pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
		if filled:
			draw_colored_polygon(pts, col)
		else:
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0, true)
