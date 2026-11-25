class_name ZoneStage
extends Node2D
## One loaded zone of the 2.0 zone world (docs/v2_zonenwelt_atlas_konzept.md 6.1-6.3). Built OFF the scene tree by
## `build()` on a `Jobs` worker (a small zone takes 2-6 s: ground paint, living grass, trees), then added and attached
## on the main thread in slices (`attach_step` under a frame budget: ground upload, the tree sheets, the trees a few
## per frame), so attaching a zone never stalls a frame. Everything sits at real continent coordinates (`Atlas`), so neighbouring stages
## simply lie side by side and a seamless threshold is ordinary ground.
##
## Content (step 4, concept 3.5): the continent's planned `Landscape` gives the zone its cut-out (trees it owns incl.
## its forest belt, stands with forest floor, ways, moss, hollows); the zone's own `nature` block only keeps
## seed, turf {accents, kinds} and meadow (bool: flower carpets). Beyond the footprint: a borderland band of ground under
## the outer belt trees, the canopy sea (`ZoneBackdrop`) further out, a mist veil (`ZoneVeil`) over every closed seamless
## threshold. Node names are deterministic (zone id, T<n>), so every peer that builds the same zone gets the same paths
## for RPCs.
##
## Worker rules: `build()` never touches the tree, signals of tree nodes or shared state. `LivingGrass.setup_rect` reads
## `Terrain.patches`, so the `ZoneDirector` never changes that list (attach/detach) while a build runs.

const TREE_SCENE_PATH: String = "res://src/entities/props/living_tree.tscn"
const ROCK_SCENE_PATH: String = "res://src/entities/props/living_rock.tscn"
const BUSH_SCENE_PATH: String = "res://src/entities/props/bush.tscn"
const FLORA_SCENE_PATH: String = "res://src/entities/props/flora.tscn"
const BORDER_TILES: float = 6.0 ## ground painted this far beyond the footprint (under the outer belt, below the canopy)
const WATER_EXTEND_TILES: float = 30.0 ## offshore WaterField ocean extent beyond water borders (past 24-tile safety collider)
const OCEAN_SAFETY_TILES: float = 24.0 ## far-offshore safety collider distance from shoreline
const LINE_SNAP: float = 0.6 ## tiles: footprint pieces this close to a seamless threshold line stay open
const WALL_PIECE: float = 1.0 ## tiles: the footprint is cut into pieces this long to find the open stretches
const DEFAULT_ACCENTS: Array[String] = ["tuft", "clump", "clover", "petal", "flower"]
const TRUNK_BY_STAGE: Array[float] = [3.0, 4.0, 5.0, 7.0, 9.0, 12.0, 6.0]
const CELLS_PER_SLICE: int = 2400 ## ground tiles set per attach slice (~4 ms of quadrant rebuild)
const CROWN_BY_STAGE: Array[float] = [16.0, 24.0, 34.0, 46.0, 60.0, 78.0, 36.0]

var zone: Atlas.Zone
var atlas: Atlas
var ground: TileMapLayer
var surfaces: GroundSurfaces
var rocky: RockyGround = null
var water: WaterField = null
var grass: LivingGrass
var trees_root: Node2D
var props_root: Node2D = null
var trees: Array[LivingTree] = []
var attached: bool = false ## every slice of `attach_step` is done
var attach_frames: int = 0 ## how many frames attaching took (tests, status)
var attach_worst_ms: float = 0.0 ## the longest slice
var sheets: Array[String] = [] ## tree sprite sheets this zone uses (warmed before the trees enter the tree)
var _pending: Array[LivingTree] = [] ## built trees not yet added (attach slices)
var _phase: int = 0
var _cells: PackedInt32Array = PackedInt32Array() ## ground tiles x, y, atlas x, atlas y (set in slices: a TileMapLayer
## rebuilds every dirty quadrant at the frame's end, 20 000 tiles at once cost 30+ ms)
var _cell_index: int = 0
var _sheet_index: int = 0
var _border: StaticBody2D
var _gates: Dictionary = {} ## threshold id -> CollisionShape2D on its line (enabled = closed)
var _gate_closed: Dictionary = {} ## threshold id -> bool (what was last asked for; the shape follows deferred)
var _tree_plan: Array[Dictionary] = []
var _flora_plan: Array[Dictionary] = []
var _rock_plan: Array[Dictionary] = []
var _dry_land_poly_tiles: PackedVector2Array = PackedVector2Array()
var _dry_mask: PackedByteArray = PackedByteArray()
var _dry_mask_origin: Vector2i = Vector2i.ZERO
var _dry_mask_size: Vector2i = Vector2i.ZERO
var _shore_pts_px: PackedVector2Array = PackedVector2Array()
var _saved_state: Dictionary = {}
var prop_states: Dictionary = {} ## "x,y" -> Dictionary (harvestable flora state)
var flora_nodes: Dictionary = {} ## Vector2i cell -> WorldProp
var blockers: Dictionary = {} ## StringName threshold_id -> WindkapProps.ThresholdBlocker
var supply_chest: WindkapProps.SupplyChest = null
var starter_weapons: Dictionary = {} ## item_id -> WindkapProps.StarterWeapon
var _bridges: Array[WaterBridge] = []
var _water_ambience: WindkapProps.ZoneWaterAmbience = null
var _river_fauna: WindkapProps.ZoneRiverFauna = null
var land: Landscape
var build_ms: Dictionary = {} ## phase -> ms of `build` (lab, tests)
var backdrop: ZoneBackdrop
var _veils: Dictionary = {} ## threshold id -> ZoneVeil
var _forest: Image ## forest floor coverage, one texel per tile over `_forest_area` (blurred)
var _forest_area: Rect2 ## tiles


## Build a whole zone off the scene tree (worker-safe). `saved` is the zone's stored state (`export_state`), {} = fresh.
static func build(p_atlas: Atlas, p_zone: Atlas.Zone, tileset: TileSet, ground_material: Material, saved: Dictionary) -> ZoneStage:
	var stage: ZoneStage = ZoneStage.new()
	stage.name = String(p_zone.id)
	stage.atlas = p_atlas
	stage.zone = p_zone
	stage.y_sort_enabled = true
	stage._saved_state = saved.duplicate(true)
	stage._load_saved_props(saved)
	stage.land = Landscape.of(p_atlas, p_zone.continent) ## planned on the main thread before any build (director setup)
	var t: int = Time.get_ticks_usec()
	stage._plan_trees()
	stage._build_forest_mask()
	t = stage._lap("mask", t)
	stage._build_water()
	t = stage._lap("water", t)
	stage._build_ground(tileset, ground_material)
	t = stage._lap("ground", t)
	stage._build_surfaces()
	stage._plan_rocks()
	stage._build_rocky()
	t = stage._lap("surfaces", t)
	stage._build_grass()
	stage._apply_saved_grass(saved.get("cut_tall", []))
	t = stage._lap("grass", t)
	stage._build_trees(saved.get("trees", {}) as Dictionary)
	stage._plan_flora()
	stage._build_border()
	t = stage._lap("trees", t)
	stage.backdrop = ZoneBackdrop.build(p_atlas, p_zone)
	stage.add_child(stage.backdrop)
	stage._lap("backdrop", t)
	return stage


## Build timing per phase (ms), for the lab and tests.
func _lap(phase: String, since: int) -> int:
	var now: int = Time.get_ticks_usec()
	var ms: float = float(now - since) / 1000.0
	build_ms[phase] = ms
	if OS.get_environment("ZONE_PROFILE") == "1":
		print("ZONE_PROFILE %s.%s = %.1f ms" % [String(zone.id), phase, ms])
	return now


## Tree sprite sheets (and glow sheets) of every species the zone's trees use, all stages. Pure data reads: the
## director asks for them BEFORE the build so they load in the background meanwhile.
## Main thread only (DataRegistry caches tables; plans the landscape if it was not yet).
static func sheet_paths(p_zone: Atlas.Zone) -> Array[String]:
	var out: Array[String] = []
	for id: String in Landscape.of(Atlas.shared(), p_zone.continent).species_of(p_zone.id):
		var spec: Dictionary = DataRegistry.get_entry("trees", id)
		var rigs: Dictionary = DataRegistry.table(String(spec.get("rig", "valley_oak_rig")))
		for rig_key: Variant in rigs:
			var rig: Variant = rigs[rig_key]
			if not (rig is Dictionary):
				continue
			for field: String in ["sheet", "glow_sheet"]:
				var path: String = String((rig as Dictionary).get(field, ""))
				if not path.is_empty() and not out.has(path):
					out.append(path)
	return out


## Main thread, after `add_child`: attach one slice and return true when the zone is complete. `deadline_usec` is the
## frame's budget end (`Time.get_ticks_usec()`), 0 = do everything now. At least one unit of work per call.
func attach_step(deadline_usec: int) -> bool:
	if attached:
		return true
	var t0: int = Time.get_ticks_usec()
	attach_frames += 1
	if _phase == 0: ## ground paint to the GPU, rocky strata, water field, terrain queries, the canopy sea
		surfaces.commit()
		if rocky != null:
			rocky.commit()
		if water != null:
			water.commit()
		backdrop.commit()
		Terrain.register_layer(ground)
		_phase = 1
		if deadline_usec != 0:
			return _finish_slice(t0)
	if _phase == 1: ## ground tiles, a block of rows per frame
		var stop: int = _cells.size() if deadline_usec == 0 else mini(_cells.size(), _cell_index + CELLS_PER_SLICE * 4)
		while _cell_index < stop:
			ground.set_cell(Vector2i(_cells[_cell_index], _cells[_cell_index + 1]), 0, Vector2i(_cells[_cell_index + 2], _cells[_cell_index + 3]))
			_cell_index += 4
		if _cell_index < _cells.size():
			return _finish_slice(t0)
		_phase = 2
		if deadline_usec != 0:
			return _finish_slice(t0)
	if _phase == 2 and (deadline_usec == 0 or Time.get_ticks_usec() < deadline_usec): ## the tree sheets
		_sheet_index = Jobs.warm_step(sheets, _sheet_index, deadline_usec)
		if _sheet_index >= sheets.size():
			_phase = 3
	if _phase == 3: ## the trees, as many as fit
		var placed: int = 0
		while not _pending.is_empty() and (deadline_usec == 0 or placed == 0 or Time.get_ticks_usec() < deadline_usec):
			trees_root.add_child(_pending.pop_front())
			placed += 1
		if _pending.is_empty():
			_phase = 4
			if deadline_usec != 0:
				return _finish_slice(t0)
	if _phase == 4: ## zone landmarks, bridges, camp, ruin, waystones, vistas, blockers, rocks, flora, river fauna
		_attach_zone_content()
		attached = true
	return _finish_slice(t0)


func _finish_slice(t0: int) -> bool:
	attach_worst_ms = maxf(attach_worst_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
	return attached


## The ground tiles this zone paints (also before it is attached: tests).
func ground_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i: int in range(0, _cells.size(), 4):
		out.append(Vector2i(_cells[i], _cells[i + 1]))
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for tree: LivingTree in _pending: ## never entered the scene: free them with the zone
			if is_instance_valid(tree):
				tree.free()
		_pending.clear()


## The zone's state to keep while it is unloaded (and in the save): tree states, cut grass, harvestable flora, camp chest & starter gear.
func export_state() -> Dictionary:
	var tree_states: Dictionary = {}
	for tree: LivingTree in trees:
		if is_instance_valid(tree) and not tree.state.is_empty():
			tree_states[String(tree.name)] = tree.state.duplicate(true)
	var out: Dictionary = {"trees": tree_states}
	if is_instance_valid(grass):
		var cut_ids: PackedInt32Array = grass.export_removed_tall()
		if not cut_ids.is_empty():
			var cut_arr: Array[int] = []
			for tid: int in cut_ids:
				cut_arr.append(tid)
			out["cut_tall"] = cut_arr
	if not prop_states.is_empty():
		out["props"] = prop_states.duplicate(true)
	if supply_chest != null and is_instance_valid(supply_chest):
		out["camp_chest"] = supply_chest.export_slots()
	if not starter_weapons.is_empty():
		var claimed: Dictionary = {}
		for item_id: String in starter_weapons:
			var sw: WindkapProps.StarterWeapon = starter_weapons[item_id] as WindkapProps.StarterWeapon
			if is_instance_valid(sw):
				claimed[item_id] = sw.export_claimed()
		out["starter_claimed"] = claimed
	return out


## Host, after attaching: catch up on `days` the zone spent unloaded (tree growth, coppice, and flora regrowth: concept 6.3).
func catch_up(days: int) -> int:
	if days <= 0 or not multiplayer.is_server():
		return 0
	var steps: int = 0
	for tree: LivingTree in trees:
		if not is_instance_valid(tree) or not tree.is_inside_tree():
			continue
		var left: int = days
		for _guard: int in 12:
			var need: int = _step_days(tree)
			if need <= 0 or left < need:
				break
			var before: String = str(tree.state)
			tree.advance_growth_days(need)
			if str(tree.state) == before:
				break
			left -= need
			steps += 1
	steps += _catch_up_flora(days)
	return steps


func _catch_up_flora(days: int) -> int:
	if prop_states.is_empty():
		return 0
	var regrown: int = 0
	var today: int = TimeManager.day
	for key: Variant in prop_states.keys():
		var skey: String = String(key)
		var st: Dictionary = prop_states[skey] as Dictionary
		if st.is_empty():
			continue
		var kind: String = String(st.get("k", ""))
		if kind.is_empty():
			continue
		var spec: Dictionary = DataRegistry.get_entry("plants", kind)
		var changed: bool = false
		if bool(st.get("p", 0)):
			var picked_day: int = int(st.get("p", 1)) - 1
			var wait_p: int = maxi(1, int((spec.get("pickup", {}) as Dictionary).get("regrow_days", 2)))
			if today - picked_day >= wait_p or days >= wait_p:
				st.erase("p")
				changed = true
		if int(st.get("h", 0)) > 0:
			var hit_day: int = int(st.get("hd", today - days))
			var wait_h: int = maxi(1, int((spec.get("harvest", {}) as Dictionary).get("regrow_days", 3)))
			if today - hit_day >= wait_h or days >= wait_h:
				st.erase("h")
				st.erase("hd")
				changed = true
		if changed:
			regrown += 1
			var clean: Dictionary = st.duplicate(true)
			if not clean.has("p") and not clean.has("h"):
				prop_states.erase(skey)
				clean = {}
			else:
				prop_states[skey] = clean
			var cell: Vector2i = _parse_cell_key(skey)
			var node: WorldProp = flora_nodes.get(cell) as WorldProp
			if node != null and is_instance_valid(node):
				node.apply_state(clean, "regrow")
	return regrown


static func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _parse_cell_key(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	if parts.size() >= 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


func _load_saved_props(saved: Dictionary) -> void:
	prop_states.clear()
	var raw_props: Variant = saved.get("props")
	if raw_props is Dictionary:
		for k: Variant in (raw_props as Dictionary):
			var v: Variant = (raw_props as Dictionary)[k]
			if v is Dictionary:
				prop_states[String(k)] = (v as Dictionary).duplicate(true)


## Days the tree's next growth step takes, 0 = it does not grow any more.
static func _step_days(tree: LivingTree) -> int:
	var spec: Dictionary = DataRegistry.get_entry("trees", tree.species_id)
	if tree.is_depleted():
		return maxi(1, int(spec.get("coppice_days", 3)))
	var stages: Dictionary = spec.get("stages", {}) as Dictionary
	var cfg: Dictionary = stages.get(str(int(tree.state.get("s", tree.stage))), {}) as Dictionary
	return int(cfg.get("grow_days", 0))


## Close (true) or open a seamless threshold's line. Closed = the neighbour is not ready or the story keeps it shut.
func set_gate(threshold_id: StringName, closed: bool) -> void:
	var shape: CollisionShape2D = _gates.get(threshold_id) as CollisionShape2D
	if shape == null:
		return
	_gate_closed[threshold_id] = closed
	var veil_n: ZoneVeil = _veils.get(threshold_id) as ZoneVeil
	if veil_n != null:
		veil_n.set_shut(closed, not veil_n.is_inside_tree())
	var blocker: WindkapProps.ThresholdBlocker = blockers.get(threshold_id) as WindkapProps.ThresholdBlocker
	if blocker != null and is_instance_valid(blocker):
		blocker.set_closed(closed)
	if shape.is_inside_tree():
		shape.set_deferred("disabled", not closed)
	else:
		shape.disabled = not closed


func has_gate(threshold_id: StringName) -> bool:
	return _gates.has(threshold_id)


func gate_closed(threshold_id: StringName) -> bool:
	return _gates.has(threshold_id) and bool(_gate_closed.get(threshold_id, true))


func veil(threshold_id: StringName) -> ZoneVeil:
	return _veils.get(threshold_id) as ZoneVeil


## Forest floor coverage at a tile, 0..1 (planned stands and belts).
func forest_at(tile: Vector2) -> float:
	if _forest == null:
		return 0.0
	var p: Vector2i = Vector2i((tile - _forest_area.position).floor())
	if p.x < 0 or p.y < 0 or p.x >= _forest.get_width() or p.y >= _forest.get_height():
		return 0.0
	return _forest.get_pixelv(p).r


## Client: take over the host's live state of this zone (trees, cut grass, flora, camp chest, starter gear).
func apply_state(data: Dictionary) -> void:
	var tree_states: Dictionary = data.get("trees", {}) as Dictionary
	for tree: LivingTree in trees:
		var kept: Variant = tree_states.get(String(tree.name))
		if is_instance_valid(tree) and kept is Dictionary and str(kept) != str(tree.state):
			tree._rpc_sync_state(kept as Dictionary, "grow", 0.0)
	_apply_saved_grass(data.get("cut_tall", []))
	_load_saved_props(data)
	for cell: Vector2i in flora_nodes:
		var prop: WorldProp = flora_nodes[cell] as WorldProp
		if prop != null and is_instance_valid(prop):
			var st: Dictionary = prop_states.get(_cell_key(cell), {}) as Dictionary
			prop.apply_state(st, "")
	if data.has("camp_chest") and supply_chest != null and is_instance_valid(supply_chest):
		supply_chest.import_slots(data["camp_chest"] as Array)
	if data.has("starter_claimed") and data["starter_claimed"] is Dictionary:
		var cl: Dictionary = data["starter_claimed"] as Dictionary
		for item_id: String in starter_weapons:
			var sw: WindkapProps.StarterWeapon = starter_weapons[item_id] as WindkapProps.StarterWeapon
			if is_instance_valid(sw) and cl.has(item_id):
				sw.import_claimed(cl[item_id])


func _apply_saved_grass(raw_ids: Variant) -> void:
	if not is_instance_valid(grass):
		return
	var packed: PackedInt32Array = PackedInt32Array()
	if raw_ids is PackedInt32Array:
		packed = raw_ids as PackedInt32Array
	elif raw_ids is Array:
		for v: Variant in raw_ids as Array:
			packed.append(int(v))
	if not packed.is_empty():
		grass.apply_removed_tall(packed)


## Pre-rasterizes dry-land polygon into a 1-byte-per-tile lookup grid (~3 ms) so `LivingGrass` never runs
## millions of `is_point_in_polygon` tests on L/XL zones.
func _ensure_dry_mask() -> void:
	if not _dry_mask.is_empty():
		return
	var poly: PackedVector2Array = _dry_land_poly_tiles if not _dry_land_poly_tiles.is_empty() else zone.footprint
	if poly.size() < 3:
		return
	var area: Rect2 = zone.bbox.grow(2.0)
	_dry_mask_origin = Vector2i(floori(area.position.x), floori(area.position.y))
	_dry_mask_size = Vector2i(maxi(1, ceili(area.end.x) - _dry_mask_origin.x), maxi(1, ceili(area.end.y) - _dry_mask_origin.y))
	_dry_mask.resize(_dry_mask_size.x * _dry_mask_size.y)
	_dry_mask.fill(0)
	var n: int = poly.size()
	var xs: Array[float] = []
	for gy: int in _dry_mask_size.y:
		var wy: float = float(_dry_mask_origin.y + gy) + 0.5
		xs.clear()
		for i: int in n:
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			if (p1.y > wy) != (p2.y > wy):
				xs.append((p2.x - p1.x) * (wy - p1.y) / (p2.y - p1.y) + p1.x)
		if xs.is_empty():
			continue
		xs.sort()
		var row_off: int = gy * _dry_mask_size.x
		var k: int = 0
		while k + 1 < xs.size():
			var x0: int = clampi(ceili(xs[k] - float(_dry_mask_origin.x) - 0.5), 0, _dry_mask_size.x - 1)
			var x1: int = clampi(floori(xs[k + 1] - float(_dry_mask_origin.x) - 0.5), 0, _dry_mask_size.x - 1)
			for gx: int in range(x0, x1 + 1):
				_dry_mask[row_off + gx] = 1
			k += 2


## Ultra-fast zero-allocation dry-land test for `LivingGrass._query_habitat` (runs first to skip ocean/outside-footprint!).
func is_dry_tile_px(world_pos: Vector2) -> bool:
	var tx: float = world_pos.x * (1.0 / Atlas.TILE_PX)
	var ty: float = world_pos.y * (1.0 / Atlas.TILE_PX)
	if not _dry_mask.is_empty():
		var gx: int = floori(tx) - _dry_mask_origin.x
		var gy: int = floori(ty) - _dry_mask_origin.y
		return gx >= 0 and gx < _dry_mask_size.x and gy >= 0 and gy < _dry_mask_size.y and _dry_mask[gy * _dry_mask_size.x + gx] == 1
	var tile: Vector2 = Vector2(tx, ty)
	if not _dry_land_poly_tiles.is_empty():
		return Geometry2D.is_point_in_polygon(tile, _dry_land_poly_tiles)
	return zone.contains(tile)


## For `LivingGrass` (habitat provider): O(1) lookup against the pre-rasterized dry-land mask.
func grass_habitat_at(world_pos: Vector2) -> Dictionary:
	if is_dry_tile_px(world_pos):
		return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}
	return {"density": 0.0, "height_scale": 1.0, "style": "none"}


# --- building --------------------------------------------------------------------------------------------------------

func _nature() -> Dictionary:
	var raw: Variant = zone.raw.get("nature", {})
	return raw as Dictionary if raw is Dictionary else {}


func _seed() -> int:
	return int(_nature().get("seed", 1)) * 7919 + hash(String(zone.id)) % 100003


func _zone_rect_px() -> Rect2:
	return Rect2(Atlas.px_of(zone.bbox.position), Atlas.px_of(zone.bbox.size)).grow(BORDER_TILES * Atlas.TILE_PX)


func _local_to_world_px(local_tile: Vector2) -> Vector2:
	return Atlas.px_of(Vector2(zone.origin) + local_tile)


func _local_to_world_tile(local_tile: Vector2) -> Vector2:
	return Vector2(zone.origin) + local_tile


func _has_water_border() -> bool:
	for b: Dictionary in zone.borders:
		if String(b.get("kind", "")) == "water":
			return true
	return false


func _water_border_range() -> Vector2:
	for b: Dictionary in zone.borders:
		if String(b.get("kind", "")) == "water":
			return Vector2(float(b.get("from", 0.0)), float(b.get("to", 1.0)))
	return Vector2(-1.0, -1.0)


func _share_in_water_border(share: float) -> bool:
	var wr: Vector2 = _water_border_range()
	return wr.y > wr.x and share >= wr.x - 0.001 and share <= wr.y + 0.001


## Worker-safe water field build (coast surf + deep ocean + brooks like Erlenbach).
func _build_water() -> void:
	var raw_water: Variant = zone.raw.get("water")
	if not (raw_water is Dictionary) or (raw_water as Dictionary).is_empty():
		return
	var wcfg: Dictionary = raw_water as Dictionary
	var coast_v: Variant = wcfg.get("coast")
	var brooks_v: Variant = wcfg.get("brooks")
	var lakes_v: Variant = wcfg.get("lakes")
	var puddles_v: Variant = wcfg.get("puddles")
	var has_coast: bool = coast_v is Dictionary and not (coast_v as Dictionary).is_empty()
	var has_brooks: bool = brooks_v is Array and not (brooks_v as Array).is_empty()
	var has_lakes: bool = lakes_v is Array and not (lakes_v as Array).is_empty()
	var has_puddles: bool = puddles_v is Array and not (puddles_v as Array).is_empty()
	if not has_coast and not has_brooks and not has_lakes and not has_puddles:
		return

	var z_px: Rect2 = Rect2(Atlas.px_of(zone.bbox.position), Atlas.px_of(zone.bbox.size))
	var pad_inland: float = BORDER_TILES * Atlas.TILE_PX
	var pad_n: float = (20.0 if has_coast else BORDER_TILES) * Atlas.TILE_PX
	var pad_sea: float = (WATER_EXTEND_TILES if has_coast else BORDER_TILES) * Atlas.TILE_PX
	var wrect: Rect2 = Rect2(
		z_px.position - Vector2(pad_sea, pad_n),
		z_px.size + Vector2(pad_sea * 2.0 if has_coast else (pad_sea + pad_inland), pad_n + pad_sea)
	)
	var water_texel: float = 8.0 if (wrect.size.x * wrect.size.y > 42000000.0) else 4.0
	water = WaterField.new()
	water.name = "Water"
	water.setup_rect(wrect, water_texel, {"bank_width": 20.0, "brook_flow_speed": 26.0})

	if has_coast:
		var coast: Dictionary = coast_v as Dictionary
		var shore_raw: Array = coast.get("shore_pts", []) as Array
		var shore_tiles: PackedVector2Array = PackedVector2Array()
		var shore_px: PackedVector2Array = PackedVector2Array()
		for pt_v: Variant in shore_raw:
			if pt_v is Array and (pt_v as Array).size() >= 2:
				var a: Array = pt_v as Array
				var wt: Vector2 = _local_to_world_tile(Vector2(float(a[0]), float(a[1])))
				shore_tiles.append(wt)
				shore_px.append(Atlas.px_of(wt))
		_shore_pts_px = shore_px
		if shore_px.size() >= 2 and zone.footprint.size() >= 3:
			var wr: Vector2 = _water_border_range()
			var ring: PackedVector2Array = zone.footprint.duplicate()
			ring.append(zone.footprint[0])
			var total_len: float = maxf(Atlas.polyline_length(ring), 1.0)
			var p_w0: Vector2 = Atlas.point_along(ring, wr.x) if wr.y > wr.x else shore_tiles[0]
			var oriented_shore: PackedVector2Array = shore_tiles.duplicate()
			if oriented_shore[oriented_shore.size() - 1].distance_to(p_w0) < oriented_shore[0].distance_to(p_w0):
				oriented_shore.reverse()

			var dry_tiles: PackedVector2Array = PackedVector2Array()
			var foot_px: PackedVector2Array = PackedVector2Array()
			var water_edges_px: PackedVector2Array = PackedVector2Array()
			var non_water_edges_px: PackedVector2Array = PackedVector2Array()
			var accum: float = 0.0
			var spliced: bool = false
			for i: int in zone.footprint.size():
				var a: Vector2 = zone.footprint[i]
				var b: Vector2 = zone.footprint[(i + 1) % zone.footprint.size()]
				foot_px.append(Atlas.px_of(a))
				var slen: float = a.distance_to(b)
				var s_start: float = accum / total_len
				var s_mid: float = (accum + slen * 0.5) / total_len
				accum += slen
				if _share_in_water_border(s_mid):
					water_edges_px.append(Atlas.px_of(a))
					water_edges_px.append(Atlas.px_of(b))
					if not spliced:
						for st_pt: Vector2 in oriented_shore:
							dry_tiles.append(st_pt)
						spliced = true
				else:
					non_water_edges_px.append(Atlas.px_of(a))
					non_water_edges_px.append(Atlas.px_of(b))
					if not _share_in_water_border(s_start):
						dry_tiles.append(a)
			_dry_land_poly_tiles = dry_tiles
			var dry_px: PackedVector2Array = PackedVector2Array()
			dry_px.resize(dry_tiles.size())
			for i: int in dry_tiles.size():
				dry_px[i] = Atlas.px_of(dry_tiles[i])

			var headlands_px: Array = []
			for hl_v: Variant in coast.get("headlands", []) as Array:
				if hl_v is Dictionary:
					var hld: Dictionary = hl_v as Dictionary
					var hc: Array = hld.get("center", [0, 0]) as Array
					var hr: Array = hld.get("radii", [4, 3]) as Array
					headlands_px.append({
						"center": _local_to_world_px(Vector2(float(hc[0]), float(hc[1]))),
						"radii": Vector2(float(hr[0]), float(hr[1])) * Atlas.TILE_PX,
					})

			var reefs_px: Array = []
			for rf_v: Variant in coast.get("reefs", []) as Array:
				if rf_v is Dictionary:
					var rfd: Dictionary = rf_v as Dictionary
					var rc: Array = rfd.get("center", [0, 0]) as Array
					var rr: Array = rfd.get("radii", [4, 3]) as Array
					reefs_px.append({
						"center": _local_to_world_px(Vector2(float(rc[0]), float(rc[1]))),
						"radii": Vector2(float(rr[0]), float(rr[1])) * Atlas.TILE_PX,
					})

			water.add_curved_coast_and_ocean(shore_px, dry_px, foot_px, water_edges_px, non_water_edges_px, {
				"dry_sand_width": float(coast.get("dry_sand_width", 6.0)) * Atlas.TILE_PX,
				"swash_margin": float(coast.get("swash_margin", 2.5)) * Atlas.TILE_PX,
				"max_surf_depth": float(coast.get("max_surf_depth", 0.465)),
				"surf_span": 7.0 * Atlas.TILE_PX,
				"shelf_width": float(coast.get("shelf_width", 14.0)) * Atlas.TILE_PX,
				"max_ocean_depth": 1.0,
				"drift_offshore_tiles": float(coast.get("drift_offshore_tiles", SwimRules.OFFSHORE_START_TILES)),
				"ocean_safety_tiles": OCEAN_SAFETY_TILES,
				"headlands": headlands_px,
				"reefs": reefs_px,
				"seed": float(_seed() % 997),
			})

	if has_brooks:
		for brook_v: Variant in brooks_v as Array:
			if not (brook_v is Dictionary):
				continue
			var brook: Dictionary = brook_v as Dictionary
			var pts_raw: Array = brook.get("pts", []) as Array
			var pts3: PackedVector3Array = PackedVector3Array()
			for pt_v: Variant in pts_raw:
				if pt_v is Array and (pt_v as Array).size() >= 3:
					var a: Array = pt_v as Array
					var wp: Vector2 = _local_to_world_px(Vector2(float(a[0]), float(a[1])))
					pts3.append(Vector3(wp.x, wp.y, float(a[2])))
			if pts3.size() < 2:
				continue
			var fords_px: Array = []
			for fd_v: Variant in brook.get("fords", []) as Array:
				if fd_v is Dictionary:
					var fd: Dictionary = fd_v as Dictionary
					var fp: Array = fd.get("pos", [0, 0]) as Array
					fords_px.append({
						"pos": _local_to_world_px(Vector2(float(fp[0]), float(fp[1]))),
						"radius": float(fd.get("radius", 4.0)) * Atlas.TILE_PX,
						"depth": float(fd.get("depth", 0.24)),
						"bed": int(fd.get("bed", WaterRules.BED_PEBBLE)),
					})
			var pools_px: Array = []
			for pl_v: Variant in brook.get("pools", []) as Array:
				if pl_v is Dictionary:
					var pl: Dictionary = pl_v as Dictionary
					var pp: Array = pl.get("pos", [0, 0]) as Array
					pools_px.append({
						"pos": _local_to_world_px(Vector2(float(pp[0]), float(pp[1]))),
						"radius": float(pl.get("radius", 3.0)) * Atlas.TILE_PX,
						"depth": float(pl.get("depth", 0.84)),
						"bed": int(pl.get("bed", WaterRules.BED_SILT)),
					})
			var bank_w_px: float = clampf(float(brook.get("bank_width", 2.0)) * 7.0, 16.0, 24.0)
			water.add_brook(pts3, {
				"base_depth": float(brook.get("base_depth", 0.64)),
				"bank_width": bank_w_px,
				"bed": int(brook.get("bed", WaterRules.BED_PEBBLE)),
				"bank_bed": int(brook.get("bank_bed", WaterRules.BED_SILT)),
				"fords": fords_px,
				"pools": pools_px,
				"shore_noise_seed": float((_seed() + 19) % 500),
			})

	if has_lakes:
		for li: int in (lakes_v as Array).size():
			var lk_v: Variant = (lakes_v as Array)[li]
			if not (lk_v is Dictionary):
				continue
			var lk: Dictionary = lk_v as Dictionary
			var c_arr: Array = lk.get("center", []) as Array
			var r_arr: Array = lk.get("radii", [4.0, 3.0]) as Array
			if c_arr.size() < 2 or r_arr.size() < 2:
				continue
			water.add_lake(
				_local_to_world_px(Vector2(float(c_arr[0]), float(c_arr[1]))),
				Vector2(float(r_arr[0]), float(r_arr[1])) * Atlas.TILE_PX,
				{
					"depth": float(lk.get("depth", 0.78)),
					"bank_width": clampf(float(lk.get("bank_width", 2.0)) * 7.0, 14.0, 24.0),
					"bed": int(lk.get("bed", WaterRules.BED_SILT)),
					"bank_bed": int(lk.get("bank_bed", WaterRules.BED_MUD)),
					"seed": float((_seed() + 31 + li * 17) % 500),
				}
			)

	if has_puddles:
		for pi: int in (puddles_v as Array).size():
			var pd_v: Variant = (puddles_v as Array)[pi]
			if not (pd_v is Dictionary):
				continue
			var pd: Dictionary = pd_v as Dictionary
			var c_arr: Array = pd.get("center", []) as Array
			var r_arr: Array = pd.get("radii", [1.0, 0.7]) as Array
			if c_arr.size() < 2 or r_arr.size() < 2:
				continue
			water.add_puddle(
				_local_to_world_px(Vector2(float(c_arr[0]), float(c_arr[1]))),
				Vector2(float(r_arr[0]), float(r_arr[1])) * Atlas.TILE_PX,
				{
					"depth": float(pd.get("depth", 0.24)),
					"bed": int(pd.get("bed", WaterRules.BED_SAND)),
					"rain_only": bool(pd.get("rain_only", false)),
					"seed": float((_seed() + 73 + pi * 19) % 500),
				}
			)

	water.build_images_only()
	add_child(water)


## Worker-safe rocky ground & coastal cliff highland strata build.
func _build_rocky() -> void:
	var rocky_list: Array = zone.raw.get("rocky", []) as Array if zone.raw.get("rocky") is Array else []
	var cliffs_v: Variant = zone.raw.get("cliffs")
	var cliffs: Dictionary = cliffs_v as Dictionary if cliffs_v is Dictionary else {}
	if rocky_list.is_empty() and cliffs.is_empty():
		return

	var zrect_r: Rect2 = _zone_rect_px()
	rocky = RockyGround.new()
	rocky.name = "RockyGround"
	rocky.setup(zrect_r, 8.0 if (zrect_r.size.x * zrect_r.size.y > 42000000.0) else 4.0)
	var base: int = _seed()

	for i: int in rocky_list.size():
		var entry_v: Variant = rocky_list[i]
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		var poly_raw: Array = entry.get("poly", []) as Array
		var poly_px: PackedVector2Array = PackedVector2Array()
		for pt_v: Variant in poly_raw:
			if pt_v is Array and (pt_v as Array).size() >= 2:
				var a: Array = pt_v as Array
				poly_px.append(_local_to_world_px(Vector2(float(a[0]), float(a[1]))))
		if poly_px.size() >= 3:
			var h_str: float = clampf(float(entry.get("height", 0.35)) * 1.8, 0.35, 1.0)
			rocky.paint_rocky_polygon(poly_px, h_str, 34.0, base + 701 + i * 37)

	for i: int in (cliffs.get("bedrock_shelves", []) as Array).size():
		var sh: Dictionary = (cliffs["bedrock_shelves"] as Array)[i] as Dictionary
		var c_arr: Array = sh.get("center", [0, 0]) as Array
		var r_arr: Array = sh.get("radii", [10, 8]) as Array
		if c_arr.size() >= 2 and r_arr.size() >= 2:
			rocky.paint_bedrock_shelf(
				_local_to_world_px(Vector2(float(c_arr[0]), float(c_arr[1]))),
				Vector2(float(r_arr[0]), float(r_arr[1])) * Atlas.TILE_PX,
				float(sh.get("strength", 0.90)),
				base + 811 + i * 29
			)

	for i: int in (cliffs.get("scree_fans", []) as Array).size():
		var sf: Dictionary = (cliffs["scree_fans"] as Array)[i] as Dictionary
		var c_arr: Array = sf.get("center", [0, 0]) as Array
		var r_arr: Array = sf.get("radii", [10, 8]) as Array
		if c_arr.size() >= 2 and r_arr.size() >= 2:
			rocky.paint_scree_fan(
				_local_to_world_px(Vector2(float(c_arr[0]), float(c_arr[1]))),
				Vector2(float(r_arr[0]), float(r_arr[1])) * Atlas.TILE_PX,
				float(sf.get("strength", 0.80)),
				base + 853 + i * 23
			)

	for i: int in (cliffs.get("quarry_trails", []) as Array).size():
		var trail_raw: Variant = (cliffs["quarry_trails"] as Array)[i]
		if trail_raw is Array:
			var pts: Array[Vector2] = []
			for pt_v: Variant in trail_raw as Array:
				if pt_v is Array and (pt_v as Array).size() >= 2:
					var a: Array = pt_v as Array
					pts.append(_local_to_world_px(Vector2(float(a[0]), float(a[1]))))
			if pts.size() >= 2:
				rocky.paint_quarry_trail(pts, 10.0, base + 887 + i * 17)

	for i: int in (cliffs.get("moss_pockets", []) as Array).size():
		var mp: Dictionary = (cliffs["moss_pockets"] as Array)[i] as Dictionary
		var c_arr: Array = mp.get("center", [0, 0]) as Array
		var r_arr: Array = mp.get("radii", [8, 6]) as Array
		if c_arr.size() >= 2 and r_arr.size() >= 2:
			rocky.paint_moss_pocket(
				_local_to_world_px(Vector2(float(c_arr[0]), float(c_arr[1]))),
				Vector2(float(r_arr[0]), float(r_arr[1])) * Atlas.TILE_PX,
				float(mp.get("strength", 0.78)),
				base + 911 + i * 19
			)

	for rp: Dictionary in _rock_plan:
		var rpos: Vector2 = rp["pos"] as Vector2
		var st: int = clampi(int(rp.get("stage", 2)), 0, 4)
		var hw: float = [8.0, 14.0, 21.0, 28.0, 38.0][st]
		var hh: float = [4.5, 6.5, 8.5, 11.5, 14.5][st]
		rocky.register_rock_outcrop(rpos, hw, hh, int(rp.get("seed", 929)))

	add_child(rocky)


func _is_placeholder_neighbor(other: Atlas.Zone) -> bool:
	return zone.continent != &"lab" and other != null and other.placeholder


## Is this borderland tile nearer to this zone than to any other zone (so two neighbours never paint the same cell)?
func _owns_borderland(tile: Vector2, own_distance: float) -> bool:
	for other: Atlas.Zone in atlas.zones_of(zone.continent):
		if other == zone or _is_placeholder_neighbor(other) or not other.bbox.grow(BORDER_TILES + 1.0).has_point(tile):
			continue
		var d: float = Atlas.edge_distance(tile, other.footprint)
		if d < own_distance or (is_equal_approx(d, own_distance) and String(other.id) < String(zone.id)):
			return false
	return true


func _build_ground(tileset: TileSet, ground_material: Material) -> void:
	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.z_index = -10
	ground.tile_set = tileset
	ground.material = ground_material
	var tiles: Dictionary = DataRegistry.table("grass_tiles")
	var turf: Dictionary = _nature().get("turf", {}) as Dictionary
	var accents: float = float(turf.get("accents", 0.05))
	var kinds: Array[String] = []
	for kind: Variant in turf.get("kinds", DEFAULT_ACCENTS) as Array:
		if tiles.has(String(kind)):
			kinds.append(String(kind))
	var forest_turf: Dictionary = (land.turf.get("forest", {}) as Dictionary) if land.turf.get("forest", {}) is Dictionary else {}
	var forest_accents: float = float(forest_turf.get("accents", accents))
	var forest_kinds: Array[String] = []
	for kind: Variant in forest_turf.get("kinds", ["fern", "mushroom", "tuft", "clump", "stone"]) as Array:
		if tiles.has(String(kind)):
			forest_kinds.append(String(kind))
	var plain: Array = tiles.get("plain", [[0, 0]]) as Array
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed()
	var area: Rect2 = zone.bbox.grow(BORDER_TILES)
	# Pre-rasterize own footprint into an O(1) 1-byte tile mask (~2 ms vs ~4800 ms of 200k polygon checks on XL zones!)
	var fx0: int = floori(area.position.x)
	var fy0: int = floori(area.position.y)
	var fw: int = maxi(1, ceili(area.end.x) - fx0)
	var fh: int = maxi(1, ceili(area.end.y) - fy0)
	var own_mask: PackedByteArray = PackedByteArray()
	own_mask.resize(fw * fh)
	own_mask.fill(0)
	var fpoly: PackedVector2Array = zone.footprint
	var fn: int = fpoly.size()
	if fn >= 3:
		var xs: Array[float] = []
		for gy: int in fh:
			var wy: float = float(fy0 + gy) + 0.5
			xs.clear()
			for i: int in fn:
				var p1: Vector2 = fpoly[i]
				var p2: Vector2 = fpoly[(i + 1) % fn]
				if (p1.y > wy) != (p2.y > wy):
					xs.append((p2.x - p1.x) * (wy - p1.y) / (p2.y - p1.y) + p1.x)
			if xs.is_empty():
				continue
			xs.sort()
			var row_off: int = gy * fw
			var k: int = 0
			while k + 1 < xs.size():
				var x0: int = clampi(ceili(xs[k] - float(fx0) - 0.5), 0, fw - 1)
				var x1: int = clampi(floori(xs[k + 1] - float(fx0) - 0.5), 0, fw - 1)
				for gx: int in range(x0, x1 + 1):
					own_mask[row_off + gx] = 1
				k += 2

	# 2-pass separable dilation (radius BORDER_TILES + 1 = 7 tiles) around own_mask so far-outside bbox tiles skip
	# water_field_at / atlas.zone_at_tile / Atlas.edge_distance completely (~15x faster on XL zones!).
	var dil_r: int = int(BORDER_TILES) + 1
	var near_x: PackedByteArray = PackedByteArray()
	near_x.resize(fw * fh)
	near_x.fill(0)
	for gy: int in fh:
		var row_off: int = gy * fw
		var run: int = 0
		for gx: int in fw:
			if own_mask[row_off + gx] == 1:
				run = dil_r + 1
			if run > 0:
				near_x[row_off + gx] = 1
				run -= 1
		run = 0
		for gx: int in range(fw - 1, -1, -1):
			if own_mask[row_off + gx] == 1:
				run = dil_r + 1
			if run > 0:
				near_x[row_off + gx] = 1
				run -= 1
	var near_own: PackedByteArray = PackedByteArray()
	near_own.resize(fw * fh)
	near_own.fill(0)
	for gx: int in fw:
		var run: int = 0
		for gy: int in fh:
			if near_x[gy * fw + gx] == 1:
				run = dil_r + 1
			if run > 0:
				near_own[gy * fw + gx] = 1
				run -= 1
		run = 0
		for gy: int in range(fh - 1, -1, -1):
			if near_x[gy * fw + gx] == 1:
				run = dil_r + 1
			if run > 0:
				near_own[gy * fw + gx] = 1
				run -= 1

	var check_sea: bool = water != null and not _dry_land_poly_tiles.is_empty()
	for gy: int in fh:
		var y: int = fy0 + gy
		var row_off: int = gy * fw
		for gx: int in fw:
			var x: int = fx0 + gx
			var roll: float = rng.randf()
			var pick: int = rng.randi()
			var is_own: bool = own_mask[row_off + gx] == 1
			if not is_own:
				if near_own[row_off + gx] == 0:
					continue
			var center: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			if not is_own:
				if check_sea:
					var wf_tile: Dictionary = water.water_field_at(Atlas.px_of(center))
					var reg: int = int(wf_tile.get("regime", 0))
					if reg == WaterRules.REGIME_OCEAN or (reg == WaterRules.REGIME_SURF and float(wf_tile.get("static_sdf_px", 0.0)) < -8.0):
						continue
				var owner: StringName = atlas.zone_at_tile(zone.continent, center)
				if owner != zone.id:
					if owner != &"" and not _is_placeholder_neighbor(atlas.zone(owner)):
						continue
					var d: float = Atlas.edge_distance(center, zone.footprint)
					if d > BORDER_TILES or not _owns_borderland(center, d):
						continue
				else:
					is_own = true
			var options: Array = plain
			var wooded: bool = forest_at(center) > 0.5
			var use_kinds: Array[String] = forest_kinds if wooded else kinds
			if is_own and roll < (forest_accents if wooded else accents) and not use_kinds.is_empty():
				options = tiles.get(use_kinds[pick % use_kinds.size()], plain) as Array
			var atlas_cell: Array = options[(pick >> 8) % options.size()] as Array
			_cells.append_array([x, y, int(atlas_cell[0]), int(atlas_cell[1])])
	add_child(ground)


func _build_surfaces() -> void:
	var zrect_s: Rect2 = _zone_rect_px()
	surfaces = GroundSurfaces.new()
	surfaces.name = "Surfaces"
	surfaces.setup(zrect_s, 4.0 if (zrect_s.size.x * zrect_s.size.y > 42000000.0) else 2.0)
	var base: int = _seed()
	var area: Rect2 = zone.bbox.grow(BORDER_TILES + 2.0)
	surfaces.set_forest_mask(_forest, Atlas.px_of(_forest_area.position), Atlas.TILE_PX, base + 101)
	for m: Rect2 in land.patches_near(land.moss, area):
		surfaces.paint_moss_patch(Atlas.px_of(m.position), Atlas.px_of(m.size), 0.88, base + 33)
	for h: Rect2 in land.patches_near(land.hollows, area):
		surfaces.paint_moisture_hollow(Atlas.px_of(h.position), Atlas.px_of(h.size), 0.94, base + 89)
	for way: Dictionary in land.ways_near(area):
		var pts: Array[Vector2] = []
		for tile: Vector2 in (way["pts"] as PackedVector2Array):
			pts.append(Atlas.px_of(tile))
		_paint_way_chunked(surfaces, pts, String(way["kind"]), int(way["seed"]), float(way["damp"]))
	# Paint soft trodden clearing around the Coastal Camp & Das Windkap ruin
	var camp_v: Variant = zone.raw.get("camp")
	if camp_v is Dictionary:
		var cf_arr: Array = (camp_v as Dictionary).get("campfire_tile", []) as Array
		if cf_arr.size() >= 2:
			surfaces.paint_junction_fillet(_local_to_world_px(Vector2(float(cf_arr[0]), float(cf_arr[1]))), Vector2(88.0, 62.0), "path", 0.58)
	# DAS STERNENAUGE: no grass through the plinth, stairs and crypt door
	var sc: Dictionary = sanctum()
	if (sc["radii"] as Vector2).x > 0.0:
		surfaces.add_stone_footprint((sc["center"] as Vector2) - Sternenauge.PLAZA_OFFSET + Vector2(0.0, 6.0), Vector2(112.0, 54.0))
	for plan: Dictionary in _tree_plan:
		var st: int = clampi(int(plan["stage"]), 0, 6)
		var pos: Vector2 = plan["pos"] as Vector2
		if forest_at(Atlas.tile_of(pos)) < 0.4: ## an open-ground tree gets its own root collar; in a wood the floor is enough
			surfaces.paint_tree_root_zone(pos, TRUNK_BY_STAGE[st], CROWN_BY_STAGE[st], int(plan["seed"]) + 401)
		else:
			surfaces.add_tree_zone(pos, TRUNK_BY_STAGE[st], CROWN_BY_STAGE[st])
	add_child(surfaces)


## Paints long cross-zone ways segment-by-segment along a Catmull-Rom curve so `GroundSurfaces.paint_way`
## only rasterizes tight per-segment bounding boxes instead of the whole-zone bounding box (5000x faster on L zones).
static func _paint_way_chunked(surf: GroundSurfaces, raw_pts: Array[Vector2], kind: String, seed_val: int, damp: float) -> void:
	if raw_pts.size() < 2:
		return
	var sub: Array[Vector2] = GroundSurfaces._subdivide_catmull(raw_pts, 4) if raw_pts.size() > 2 else raw_pts
	var n: int = sub.size()
	for i: int in n - 1:
		var seg: Array[Vector2] = [sub[i], sub[i + 1]]
		surf.paint_way(seg, kind, seed_val, damp, false, i == 0, i == n - 2)


## Forest floor coverage (worker): planned stands with `soil`, plus a soft disc round every belt tree, one texel per
## tile, blurred twice so the painted edge comes out round (the painter wobbles it further).
func _build_forest_mask() -> void:
	_forest_area = Rect2(zone.bbox.position.floor(), zone.bbox.size.ceil()).grow(BORDER_TILES + 3.0)
	var w: int = int(_forest_area.size.x)
	var h: int = int(_forest_area.size.y)
	var cover: PackedFloat32Array = PackedFloat32Array()
	cover.resize(w * h)
	var soil: Array[Landscape.Stand] = []
	for stand: Landscape.Stand in land.stands_near(_forest_area):
		if stand.soil:
			soil.append(stand)
	if not soil.is_empty():
		for stand: Landscape.Stand in soil:
			var sb: Rect2 = stand.bbox
			var sx0: int = clampi(floori(sb.position.x - _forest_area.position.x), 0, w - 1)
			var sx1: int = clampi(ceili(sb.end.x - _forest_area.position.x), 0, w - 1)
			var sy0: int = clampi(floori(sb.position.y - _forest_area.position.y), 0, h - 1)
			var sy1: int = clampi(ceili(sb.end.y - _forest_area.position.y), 0, h - 1)
			for y: int in range(sy0, sy1 + 1):
				var row_off: int = y * w
				for x: int in range(sx0, sx1 + 1):
					if cover[row_off + x] >= 1.0:
						continue
					var tile: Vector2 = _forest_area.position + Vector2(float(x) + 0.5, float(y) + 0.5)
					if stand.contains(tile):
						cover[row_off + x] = 1.0
	for tree: Dictionary in land.trees:
		if String(tree["kind"]) != "belt":
			continue
		var at: Vector2 = (tree["pos"] as Vector2) - _forest_area.position
		if at.x < -4.0 or at.y < -4.0 or at.x > float(w) + 4.0 or at.y > float(h) + 4.0:
			continue
		for y: int in range(maxi(0, floori(at.y - 3.5)), mini(h, ceili(at.y + 3.5))):
			for x: int in range(maxi(0, floori(at.x - 3.5)), mini(w, ceili(at.x + 3.5))):
				var d: float = (Vector2(float(x) + 0.5, float(y) + 0.5) - at).length()
				cover[y * w + x] = maxf(cover[y * w + x], 1.0 - smoothstep(1.8, 3.4, d))
	cover = _blur(cover, w, h)
	cover = _blur(cover, w, h)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(w * h)
	for i: int in w * h:
		bytes[i] = int(round(clampf(cover[i], 0.0, 1.0) * 255.0))
	_forest = Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes)


## 3x3 box blur, rows then columns.
static func _blur(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var mid: PackedFloat32Array = PackedFloat32Array()
	mid.resize(w * h)
	for y: int in h:
		for x: int in w:
			mid[y * w + x] = (src[y * w + maxi(0, x - 1)] + src[y * w + x] + src[y * w + mini(w - 1, x + 1)]) / 3.0
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(w * h)
	for y: int in h:
		for x: int in w:
			out[y * w + x] = (mid[maxi(0, y - 1) * w + x] + mid[y * w + x] + mid[mini(h - 1, y + 1) * w + x]) / 3.0
	return out


func _build_grass() -> void:
	_ensure_dry_mask()
	grass = LivingGrass.new()
	grass.name = "Grass"
	grass.y_sort_enabled = true
	var rect: Rect2 = Rect2(Atlas.px_of(zone.bbox.position), Atlas.px_of(zone.bbox.size)).grow(Atlas.TILE_PX) ## grass never grows outside the footprint
	if bool(_nature().get("meadow", true)):
		grass.set_meadow_rect(rect)
	else:
		grass.set_meadow_rect(Rect2(rect.position - Vector2(99999.0, 99999.0), Vector2.ONE)) ## no flower carpets
	grass.add_habitat_provider(self)
	if water != null:
		grass.add_habitat_provider(water)
	if rocky != null:
		grass.add_habitat_provider(rocky)
	grass.setup_rect(rect, _seed() + 2026, true, surfaces)
	add_child(grass)


## Where the trees stand: the zone's cut-out of the planned landscape (stands, single trees and its forest belt).
func _plan_trees() -> void:
	_tree_plan.clear()
	for tree: Dictionary in land.trees_of(zone.id):
		_tree_plan.append({"species": String(tree["species"]), "pos": Atlas.px_of(tree["pos"] as Vector2).round(), "stage": int(tree["stage"]), "seed": int(tree["seed"]), "traits": tree.get("traits", {}), "kind": String(tree["kind"])})


func _build_trees(saved: Dictionary) -> void:
	trees_root = Node2D.new()
	trees_root.name = "Trees"
	trees_root.y_sort_enabled = true
	add_child(trees_root)
	var keep_clear: Array[Vector2] = _landmark_keep_clear_px()
	var blockers_v: Variant = zone.raw.get("blockers")
	if blockers_v is Array:
		for b_v: Variant in blockers_v as Array:
			if b_v is Dictionary:
				var ta: Array = (b_v as Dictionary).get("tile", []) as Array
				if ta.size() >= 2:
					keep_clear.append(_local_to_world_px(Vector2(float(ta[0]), float(ta[1]))))
	var scene: PackedScene = load(TREE_SCENE_PATH) as PackedScene
	for i: int in _tree_plan.size():
		var plan: Dictionary = _tree_plan[i]
		var tpos: Vector2 = plan["pos"] as Vector2
		if water != null and water.field_at(tpos).x <= 6.0:
			continue ## keep trees out of brook channel & bay surf
		var blocked_lm: bool = false
		for kc: Vector2 in keep_clear:
			if tpos.distance_squared_to(kc) < 58.0 * 58.0:
				blocked_lm = true
				break
		if blocked_lm or in_sanctum(tpos, 40.0):
			continue
		var tree: LivingTree = scene.instantiate() as LivingTree
		tree.name = "T%d" % i
		tree.setup_tree(tpos, int(plan["stage"]), int(plan["seed"]), String(plan["species"]))
		var traits: Variant = plan.get("traits", {})
		if traits is Dictionary and not (traits as Dictionary).is_empty():
			tree.configure_traits(-1, traits as Dictionary)
		var kept: Variant = saved.get(String(tree.name))
		if kept is Dictionary and not (kept as Dictionary).is_empty():
			tree.state = (kept as Dictionary).duplicate(true)
		trees.append(tree)
		_pending.append(tree) ## added by `attach_step`, a few per frame


## Worker-safe planning of harvestable bushes & flora patches from `zone.raw["flora"]`.
func _plan_flora() -> void:
	_flora_plan.clear()
	var flora_v: Variant = zone.raw.get("flora")
	if not (flora_v is Dictionary):
		return
	var flora: Dictionary = flora_v as Dictionary
	var plants: Dictionary = DataRegistry.table("plants")
	var used_cells: Dictionary = {}
	var keep_clear: Array[Vector2] = _landmark_keep_clear_px()

	var bushes: Array = flora.get("bushes", []) as Array
	for i: int in bushes.size():
		var b_v: Variant = bushes[i]
		if not (b_v is Dictionary):
			continue
		var b: Dictionary = b_v as Dictionary
		var kind: String = String(b.get("kind", "berry_bush"))
		var t_arr: Array = b.get("tile", []) as Array
		if t_arr.size() < 2 or not plants.has(kind):
			continue
		var pos_px: Vector2 = _local_to_world_px(Vector2(float(t_arr[0]), float(t_arr[1]))).round()
		if in_sanctum(pos_px, 12.0):
			continue
		var cell: Vector2i = Vector2i((pos_px / 16.0).floor())
		if used_cells.has(cell):
			continue
		used_cells[cell] = true
		var cols: int = maxi(1, int((plants[kind] as Dictionary).get("columns", 1)))
		_flora_plan.append({"kind": kind, "pos": pos_px, "cell": cell, "variant": absi(hash([String(zone.id), i, kind])) % cols})

	var patches: Array = flora.get("patches", []) as Array
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for pi: int in patches.size():
		var p_v: Variant = patches[pi]
		if not (p_v is Dictionary):
			continue
		var patch: Dictionary = p_v as Dictionary
		var kind: String = String(patch.get("kind", ""))
		var c_arr: Array = patch.get("center", []) as Array
		if kind.is_empty() or c_arr.size() < 2 or not plants.has(kind):
			continue
		var center_local: Vector2 = Vector2(float(c_arr[0]), float(c_arr[1]))
		var rad_tiles: float = maxf(2.0, float(patch.get("radius", 10.0)))
		var count: int = clampi(int(patch.get("count", 8)), 1, 32)
		var cols: int = maxi(1, int((plants[kind] as Dictionary).get("columns", 1)))
		var is_riparian: bool = kind in ["cattail", "brook_mint", "marsh_gold"]
		rng.seed = hash([String(zone.id), pi, kind, _seed()])
		var placed: int = 0
		for _attempt: int in count * 14:
			if placed >= count:
				break
			var ang: float = rng.randf() * TAU
			var dist: float = sqrt(rng.randf()) * rad_tiles
			var wt: Vector2 = _local_to_world_tile(center_local + Vector2.from_angle(ang) * dist)
			if not _dry_land_poly_tiles.is_empty():
				if not Geometry2D.is_point_in_polygon(wt, _dry_land_poly_tiles):
					continue
			elif not zone.contains(wt):
				continue
			var pos_px: Vector2 = Atlas.px_of(wt).round()
			if water != null:
				var f: Vector2 = water.field_at(pos_px)
				if is_riparian:
					if f.x < 2.0 or f.x > 46.0:
						continue
				else:
					if f.x < 10.0:
						continue
			var too_close: bool = false
			for kc: Vector2 in keep_clear:
				if pos_px.distance_squared_to(kc) < 38.0 * 38.0:
					too_close = true
					break
			if too_close or in_sanctum(pos_px, 8.0):
				continue
			var cell: Vector2i = Vector2i((pos_px / 16.0).floor())
			if used_cells.has(cell):
				continue
			used_cells[cell] = true
			_flora_plan.append({"kind": kind, "pos": pos_px, "cell": cell, "variant": rng.randi() % cols})
			placed += 1


func _landmark_keep_clear_px() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for lm: Atlas.Landmark in zone.landmarks:
		pts.append(Atlas.px_of(lm.pos))
	var camp_v: Variant = zone.raw.get("camp")
	if camp_v is Dictionary:
		var c: Dictionary = camp_v as Dictionary
		for key: String in ["campfire_tile", "seat_tile"]:
			var a: Variant = c.get(key)
			if a is Array and (a as Array).size() >= 2:
				pts.append(_local_to_world_px(Vector2(float((a as Array)[0]), float((a as Array)[1]))))
	return pts


## DAS STERNENAUGE sanctum: the clear zone around the statue and its steles (world px center, elliptic radii) or radii ZERO.
## Pure data (zone.raw + DataRegistry), safe for worker-side planning.
func sanctum() -> Dictionary:
	var ruin_v: Variant = zone.raw.get("ruin")
	if not (ruin_v is Dictionary):
		return {"center": Vector2.ZERO, "radii": Vector2.ZERO}
	var lh_arr: Array = (ruin_v as Dictionary).get("lighthouse_tile", (ruin_v as Dictionary).get("tile", [])) as Array
	if lh_arr.size() < 2:
		return {"center": Vector2.ZERO, "radii": Vector2.ZERO}
	var meta: Dictionary = DataRegistry.table("sternenauge_plaza")
	var radii: Vector2 = WindkapProps._vec2_from(meta.get("sanctum_radii"), Vector2(171.0, 96.0))
	var c: Vector2 = _local_to_world_px(Vector2(float(lh_arr[0]), float(lh_arr[1]))).round() + Sternenauge.PLAZA_OFFSET
	return {"center": c, "radii": radii}


## Is `p` in the Sternenauge sanctum (grown by `margin` px)? Rocks, details, flora and trees stay off it.
func in_sanctum(p: Vector2, margin: float = 0.0) -> bool:
	var sc: Dictionary = sanctum()
	var r: Vector2 = (sc["radii"] as Vector2) + Vector2(margin, margin * 0.6)
	if r.x <= 0.0:
		return false
	return ((p - (sc["center"] as Vector2)) / r).length() < 1.0


func _plan_rocks() -> void:
	_rock_plan.clear()
	var keep_clear: Array[Vector2] = _landmark_keep_clear_px()
	for list_key: String in ["chests", "blockers", "veil_threads", "vistas", "waystones"]:
		var arr_v: Variant = zone.raw.get(list_key)
		if arr_v is Array:
			for it_v: Variant in arr_v as Array:
				if it_v is Dictionary:
					var ta: Variant = (it_v as Dictionary).get("tile")
					if ta is Array and (ta as Array).size() >= 2:
						keep_clear.append(_local_to_world_px(Vector2(float((ta as Array)[0]), float((ta as Array)[1]))))

	var placed_pts: Array[Vector2] = []
	var cliffs_v: Variant = zone.raw.get("cliffs")
	if cliffs_v is Dictionary:
		for rock_v: Variant in (cliffs_v as Dictionary).get("rocks", []) as Array:
			if not (rock_v is Dictionary):
				continue
			var rk: Dictionary = rock_v as Dictionary
			var t_arr: Array = rk.get("tile", []) as Array
			if t_arr.size() < 2:
				continue
			var rpos: Vector2 = _local_to_world_px(Vector2(float(t_arr[0]), float(t_arr[1]))).round()
			if in_sanctum(rpos, 26.0):
				continue
			_rock_plan.append({
				"pos": rpos,
				"stage": clampi(int(rk.get("stage", 2)), 0, 4),
				"seed": int(rk.get("seed", 1101)),
			})
			placed_pts.append(rpos)

	# Deterministically scatter natural companion boulders (s1..s2) & loose hand-collectible fieldstones (s0)
	# across all rocky highland polygons so stone areas feel geologically sculpted, alive & harvestable!
	var rocky_list: Array = zone.raw.get("rocky", []) as Array if zone.raw.get("rocky") is Array else []
	if rocky_list.is_empty():
		return
	var polys_px: Array[PackedVector2Array] = []
	for entry_v: Variant in rocky_list:
		if entry_v is Dictionary:
			var pr: Variant = (entry_v as Dictionary).get("poly")
			if pr is Array and (pr as Array).size() >= 3:
				var poly: PackedVector2Array = PackedVector2Array()
				for pt_v: Variant in pr as Array:
					if pt_v is Array and (pt_v as Array).size() >= 2:
						var a: Array = pt_v as Array
						poly.append(_local_to_world_px(Vector2(float(a[0]), float(a[1]))))
				polys_px.append(poly)
	if polys_px.is_empty():
		return

	var bb: Rect2 = Rect2(polys_px[0][0], Vector2.ZERO)
	for poly: PackedVector2Array in polys_px:
		for pt: Vector2 in poly:
			bb = bb.expand(pt)

	var trail_pts: Array[Vector2] = []
	if cliffs_v is Dictionary:
		for tr_v: Variant in (cliffs_v as Dictionary).get("quarry_trails", []) as Array:
			if tr_v is Array:
				for tp_v: Variant in tr_v as Array:
					if tp_v is Array and (tp_v as Array).size() >= 2:
						trail_pts.append(_local_to_world_px(Vector2(float((tp_v as Array)[0]), float((tp_v as Array)[1]))))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([String(zone.id), "rocky_scatter_v2", _seed()])
	var max_extra: int = 34
	var added: int = 0
	var seed_seq: int = 2100
	for _attempt: int in 420:
		if added >= max_extra:
			break
		var cand: Vector2 = Vector2(
			rng.randf_range(bb.position.x + 20.0, bb.end.x - 20.0),
			rng.randf_range(bb.position.y + 20.0, bb.end.y - 20.0)
		).round()
		var inside: bool = false
		for poly: PackedVector2Array in polys_px:
			if Geometry2D.is_point_in_polygon(cand, poly):
				inside = true
				break
		if not inside:
			continue
		if water != null and water.field_at(cand).x < 34.0:
			continue
		if surfaces != null and surfaces.surface_at(cand) in ["path", "ancient_stone"]:
			continue
		if in_sanctum(cand, 30.0):
			continue
		var blocked: bool = false
		for kc: Vector2 in keep_clear:
			if cand.distance_squared_to(kc) < 62.0 * 62.0:
				blocked = true
				break
		if blocked:
			continue
		for tp: Vector2 in trail_pts:
			if cand.distance_squared_to(tp) < 34.0 * 34.0:
				blocked = true
				break
		if blocked:
			continue
		var roll_s: float = rng.randf()
		var stage_v: int = 0 if roll_s < 0.46 else (1 if roll_s < 0.80 else (2 if roll_s < 0.95 else 3))
		var min_gap: float = 48.0 if stage_v <= 1 else 74.0
		for ex: Vector2 in placed_pts:
			if cand.distance_squared_to(ex) < min_gap * min_gap:
				blocked = true
				break
		if blocked:
			continue
		seed_seq += 17
		_rock_plan.append({"pos": cand, "stage": stage_v, "seed": seed_seq})
		placed_pts.append(cand)
		added += 1


## Collision along the footprint (open at seamless threshold lines AND along water borders so players swim freely!),
## plus a far-offshore safety collider at ~24 tiles out in deep ocean beyond water borders.
func _build_border() -> void:
	_border = StaticBody2D.new()
	_border.name = "Border"
	_border.collision_layer = 1
	_border.collision_mask = 0
	add_child(_border)
	var lines: Array[Atlas.Threshold] = []
	for t: Atlas.Threshold in atlas.thresholds_of(zone.id):
		if t.seamless():
			lines.append(t)
	var poly: PackedVector2Array = zone.footprint
	var has_water: bool = _has_water_border()
	var total_len: float = 1.0
	if has_water and poly.size() >= 3:
		var ring: PackedVector2Array = poly.duplicate()
		ring.append(poly[0])
		total_len = maxf(Atlas.polyline_length(ring), 1.0)
	var walls: PackedVector2Array = PackedVector2Array() ## segment pairs, px
	var accum: float = 0.0
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var slen: float = a.distance_to(b)
		var seg_mid_share: float = (accum + slen * 0.5) / total_len
		accum += slen
		if has_water and _share_in_water_border(seg_mid_share):
			continue ## water border stays open for free coastal & open-ocean swimming!
		var pieces: int = maxi(1, ceili(slen / WALL_PIECE))
		var run_from: int = -1
		for k: int in pieces + 1:
			var closed: bool = k < pieces and not _piece_open(a.lerp(b, float(k) / float(pieces)), a.lerp(b, float(k + 1) / float(pieces)), lines)
			if closed and run_from < 0:
				run_from = k
			elif not closed and run_from >= 0:
				walls.append(Atlas.px_of(a.lerp(b, float(run_from) / float(pieces))))
				walls.append(Atlas.px_of(a.lerp(b, float(k) / float(pieces))))
				run_from = -1
	var wall_shape: CollisionShape2D = CollisionShape2D.new()
	wall_shape.name = "Edge"
	var concave: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
	concave.segments = walls
	wall_shape.shape = concave
	_border.add_child(wall_shape)

	# Far-offshore safety collider at ~24 tiles seaward of shore_pts (never blocks beach or bay!)
	if has_water and _shore_pts_px.size() >= 2:
		var safety_segs: PackedVector2Array = _build_offshore_safety_segments()
		if not safety_segs.is_empty():
			var safety_shape: CollisionShape2D = CollisionShape2D.new()
			safety_shape.name = "OffshoreSafety"
			var sc: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
			sc.segments = safety_segs
			safety_shape.shape = sc
			_border.add_child(safety_shape)

	var blocked_ids: Dictionary = {}
	var raw_blockers: Variant = zone.raw.get("blockers")
	if raw_blockers is Array:
		for b_v: Variant in raw_blockers as Array:
			if b_v is Dictionary:
				blocked_ids[StringName(String((b_v as Dictionary).get("threshold_id", "")))] = true
	for t: Atlas.Threshold in lines:
		var chain: PackedVector2Array = PackedVector2Array()
		var line: PackedVector2Array = t.line if t.line.size() >= 2 else PackedVector2Array([t.line_a, t.line_b])
		for i: int in range(line.size() - 1):
			chain.append(Atlas.px_of(line[i]))
			chain.append(Atlas.px_of(line[i + 1]))
		var gate: CollisionShape2D = CollisionShape2D.new()
		gate.name = "Gate_" + String(t.id)
		var gate_shape: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
		gate_shape.segments = chain
		gate.shape = gate_shape
		_border.add_child(gate)
		_gates[t.id] = gate
		if not blocked_ids.has(t.id):
			var veil_node: ZoneVeil = ZoneVeil.build(zone, line)
			veil_node.name = "Veil_" + String(t.id)
			add_child(veil_node)
			_veils[t.id] = veil_node


func _build_offshore_safety_segments() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = _shore_pts_px.size()
	if n < 2:
		return out
	var dist_px: float = OCEAN_SAFETY_TILES * Atlas.TILE_PX
	var arc: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		var prev_p: Vector2 = _shore_pts_px[maxi(0, i - 1)]
		var next_p: Vector2 = _shore_pts_px[mini(n - 1, i + 1)]
		var tang: Vector2 = (next_p - prev_p).normalized()
		if tang == Vector2.ZERO:
			continue
		var nrm: Vector2 = tang.orthogonal()
		var probe_tile: Vector2 = Atlas.tile_of(_shore_pts_px[i] + nrm * 24.0)
		if not _dry_land_poly_tiles.is_empty() and Geometry2D.is_point_in_polygon(probe_tile, _dry_land_poly_tiles):
			nrm = -nrm
		arc.append(_shore_pts_px[i] + nrm * dist_px)
	if arc.size() < 2:
		return out
	# Side wings connecting water-border endpoints out to the 24-tile offshore arc
	out.append(_shore_pts_px[0])
	out.append(arc[0])
	for i: int in arc.size() - 1:
		out.append(arc[i])
		out.append(arc[i + 1])
	out.append(arc[arc.size() - 1])
	out.append(_shore_pts_px[n - 1])
	return out


static func _piece_open(a: Vector2, b: Vector2, lines: Array[Atlas.Threshold]) -> bool:
	for t: Atlas.Threshold in lines:
		var line: PackedVector2Array = t.line if t.line.size() >= 2 else PackedVector2Array([t.line_a, t.line_b])
		if ZoneMath.polyline_distance(a, line) <= LINE_SNAP and ZoneMath.polyline_distance(b, line) <= LINE_SNAP and ZoneMath.polyline_distance((a + b) * 0.5, line) <= LINE_SNAP:
			return true
	return false


# --- main-thread zone landmarks, bridges, camp, ruin, waystones, vistas, blockers, flora ------------------------------

func _attach_zone_content() -> void:
	if props_root != null:
		return
	props_root = Node2D.new()
	props_root.name = "Props"
	props_root.y_sort_enabled = true
	add_child(props_root)

	_attach_bridges_and_water_life()
	_attach_camp()
	_attach_ruin()
	SuedkapProps.attach(self)
	_attach_waystones()
	_attach_vistas()
	_attach_blockers()
	_attach_rocks()
	_attach_flora()
	ZoneBiomeDecor.attach(self)


func _attach_bridges_and_water_life() -> void:
	var raw_water: Variant = zone.raw.get("water")
	if raw_water is Dictionary:
		var bridges_v: Variant = (raw_water as Dictionary).get("bridges")
		if bridges_v is Array:
			for br_v: Variant in bridges_v as Array:
				if not (br_v is Dictionary):
					continue
				var br: Dictionary = br_v as Dictionary
				var t_arr: Array = br.get("tile", []) as Array
				if t_arr.size() < 2:
					continue
				var bridge: WaterBridge = WaterBridge.new()
				bridge.name = "Bridge_" + String(br.get("id", "main"))
				bridge.position = _local_to_world_px(Vector2(float(t_arr[0]), float(t_arr[1]))).round()
				props_root.add_child(bridge)
				if water != null:
					bridge.bind_water_field(water)
				_bridges.append(bridge)
	if water != null:
		_water_ambience = WindkapProps.ZoneWaterAmbience.new()
		_water_ambience.name = "WaterAmbience"
		_water_ambience.bind_water_field(water)
		add_child(_water_ambience)

		_river_fauna = WindkapProps.ZoneRiverFauna.new()
		_river_fauna.name = "RiverFauna"
		_river_fauna.setup_for_field(water)
		props_root.add_child(_river_fauna)
		_river_fauna.populate_zone_chunks()


func _attach_camp() -> void:
	var camp_v: Variant = zone.raw.get("camp")
	if not (camp_v is Dictionary):
		return
	var camp: Dictionary = camp_v as Dictionary
	var cf_arr: Array = camp.get("campfire_tile", []) as Array
	var fire_px: Vector2 = Vector2.ZERO
	if cf_arr.size() >= 2:
		fire_px = _local_to_world_px(Vector2(float(cf_arr[0]), float(cf_arr[1]))).round()
		var fire: WindkapProps.Campfire = WindkapProps.Campfire.new()
		fire.name = "Campfire"
		fire.position = fire_px
		props_root.add_child(fire)

	var seat_arr: Array = camp.get("seat_tile", []) as Array
	if seat_arr.size() >= 2:
		var seat_px: Vector2 = _local_to_world_px(Vector2(float(seat_arr[0]), float(seat_arr[1]))).round()
		var bench: WindkapProps.CampSeat = WindkapProps.CampSeat.new()
		bench.name = "CampBench"
		bench.part_key = "driftwood_bench_h"
		bench.position = seat_px
		bench.facing_sector = posmod(roundi((fire_px - seat_px).angle() / (PI / 4.0)), 8) if fire_px != Vector2.ZERO else 4
		props_root.add_child(bench)

		# Second cozy driftwood stump seat & camp clutter around the fire
		var stump_px: Vector2 = (fire_px + Vector2(-36.0, 12.0)).round()
		var stump: WindkapProps.CampSeat = WindkapProps.CampSeat.new()
		stump.name = "CampStumpSeat"
		stump.part_key = "driftwood_stump"
		stump.position = stump_px
		stump.facing_sector = posmod(roundi((fire_px - stump_px).angle() / (PI / 4.0)), 8)
		props_root.add_child(stump)

		var decor_specs: Array = [
			["CampPack", "beach_pack_prop", fire_px + Vector2(-52.0, -20.0)],
			["CampRope", "camp_rope_coil", fire_px + Vector2(28.0, 26.0)],
			["CampKindling", "camp_kindling", fire_px + Vector2(-24.0, -26.0)],
			["CampPebbles", "camp_pebbles", fire_px + Vector2(18.0, 34.0)],
		]
		for d_spec: Array in decor_specs:
			var dec: WindkapProps.CampDecor = WindkapProps.CampDecor.new()
			dec.name = String(d_spec[0])
			dec.part_key = String(d_spec[1])
			dec.position = (d_spec[2] as Vector2).round()
			props_root.add_child(dec)

		# Living SporeBed right beside the camp clearing where every collected Schattenfrucht settles in!
		var spore_bed: SporeBed = SporeBed.new()
		spore_bed.name = "CampSporeBed"
		spore_bed.position = (fire_px + Vector2(56.0, -20.0)).round()
		props_root.add_child(spore_bed)

	var chest_v: Variant = camp.get("chest")
	if chest_v is Dictionary:
		var cd: Dictionary = chest_v as Dictionary
		var ct_arr: Array = cd.get("tile", []) as Array
		if ct_arr.size() >= 2:
			supply_chest = WindkapProps.SupplyChest.new()
			supply_chest.name = "CampSupplyChest"
			supply_chest.box_id = String(cd.get("id", "windkap_camp_chest"))
			supply_chest.position = _local_to_world_px(Vector2(float(ct_arr[0]), float(ct_arr[1]))).round()
			props_root.add_child(supply_chest)
			if _saved_state.has("camp_chest") and _saved_state["camp_chest"] is Array:
				supply_chest.import_slots(_saved_state["camp_chest"] as Array)

	var saved_claimed: Dictionary = _saved_state.get("starter_claimed", {}) as Dictionary if _saved_state.get("starter_claimed") is Dictionary else {}
	for item_v: Variant in camp.get("starter_items", []) as Array:
		if not (item_v is Dictionary):
			continue
		var it: Dictionary = item_v as Dictionary
		var it_id: String = String(it.get("id", ""))
		var it_arr: Array = it.get("tile", []) as Array
		if it_id.is_empty() or it_arr.size() < 2:
			continue
		var sw: WindkapProps.StarterWeapon = WindkapProps.StarterWeapon.new()
		sw.name = "Starter_" + it_id
		sw.item_id = it_id
		sw.position = _local_to_world_px(Vector2(float(it_arr[0]), float(it_arr[1]))).round()
		if saved_claimed.has(it_id):
			sw.import_claimed(saved_claimed[it_id])
		props_root.add_child(sw)
		starter_weapons[it_id] = sw


func _attach_ruin() -> void:
	var ruin_v: Variant = zone.raw.get("ruin")
	if not (ruin_v is Dictionary):
		return
	var ruin: Dictionary = ruin_v as Dictionary
	var lh_arr: Array = ruin.get("lighthouse_tile", ruin.get("tile", [])) as Array
	if lh_arr.size() >= 2:
		var lh_px: Vector2 = _local_to_world_px(Vector2(float(lh_arr[0]), float(lh_arr[1]))).round()
		# DAS STERNENAUGE: Caelias kniende Leuchtturm-Statue (ersetzt den alten Steinsetzer-Turm)
		var tower: Sternenauge = Sternenauge.new()
		tower.name = "WindkapLighthouse"
		tower.position = lh_px
		props_root.add_child(tower)
		# Four rune steles around the statue; they wake with it
		var steles: Array = [[Vector2(-152.0, -40.0), 0, false], [Vector2(150.0, -44.0), 1, true],
			[Vector2(-150.0, 58.0), 2, false], [Vector2(152.0, 54.0), 0, true]]
		for i: int in steles.size():
			var sd: Array = steles[i] as Array
			var stele: SternenaugeStele = SternenaugeStele.new()
			stele.name = "SternenaugeStele%d" % i
			stele.variant = int(sd[1])
			stele.flip = bool(sd[2])
			stele.position = (lh_px + Sternenauge.PLAZA_OFFSET + (sd[0] as Vector2)).round()
			props_root.add_child(stele)

	var tab_v: Variant = ruin.get("tablet")
	if tab_v is Dictionary:
		var td: Dictionary = tab_v as Dictionary
		var tt_arr: Array = td.get("tile", []) as Array
		if tt_arr.size() >= 2:
			var tablet: WindkapProps.MapTablet = WindkapProps.MapTablet.new()
			tablet.name = "WindkapMapTablet"
			tablet.tablet_id = String(td.get("id", "windkap_map_tablet"))
			tablet.position = _local_to_world_px(Vector2(float(tt_arr[0]), float(tt_arr[1]))).round()
			props_root.add_child(tablet)


func _attach_waystones() -> void:
	var ws_list_v: Variant = zone.raw.get("waystones")
	if not (ws_list_v is Array):
		return
	var mgr: Waystones = Waystones.of(get_tree())
	for ws_v: Variant in ws_list_v as Array:
		if not (ws_v is Dictionary):
			continue
		var ws: Dictionary = ws_v as Dictionary
		var wid: String = String(ws.get("id", ""))
		var t_arr: Array = ws.get("tile", []) as Array
		if wid.is_empty() or t_arr.size() < 2:
			continue
		var world_tile: Vector2 = _local_to_world_tile(Vector2(float(t_arr[0]), float(t_arr[1])))
		var world_px: Vector2 = Atlas.px_of(world_tile).round()
		if mgr != null and not mgr.specs().has(wid):
			mgr.load_atlas_specs(atlas, zone.continent)
		var statue: WaystoneStatue = WaystoneStatue.new()
		statue.name = "Waystone_" + wid
		statue.id = wid
		statue.display_name = String(ws.get("name", "WÄCHTERIN"))
		statue.reveal_cells = float(ws.get("reveal", 16.0))
		statue.paved = false ## Show mossy/awakening sanctuary flagstones & glowing leylines in the grove!
		statue.position = world_px
		props_root.add_child(statue)


func _attach_vistas() -> void:
	var v_list_v: Variant = zone.raw.get("vistas")
	if not (v_list_v is Array):
		return
	var mgr: Vistas = Vistas.of(get_tree())
	for vp_v: Variant in v_list_v as Array:
		if not (vp_v is Dictionary):
			continue
		var vp: Dictionary = vp_v as Dictionary
		var vid: String = String(vp.get("id", ""))
		var t_arr: Array = vp.get("tile", []) as Array
		if vid.is_empty() or t_arr.size() < 2:
			continue
		var world_tile: Vector2 = _local_to_world_tile(Vector2(float(t_arr[0]), float(t_arr[1])))
		var world_px: Vector2 = Atlas.px_of(world_tile).round()
		if mgr != null:
			mgr.register_spec(vid, {
				"id": vid,
				"name": String(vp.get("name", "AUSSICHTSPUNKT")),
				"sub": String(vp.get("sub", "WEITBLICK")),
				"tile": [world_tile.x, world_tile.y],
				"sector": int(vp.get("sector", 3)),
				"variant": int(vp.get("variant", 0)),
				"reveal_cells": float(vp.get("reveal_cells", 24.0)),
				"xp_reward": int(vp.get("xp_reward", 12)),
				"zone": String(zone.id),
			})
		var node: VistaPoint = VistaPoint.new()
		node.name = "Vista_" + vid
		node.vista_id = vid
		node.vista_name = String(vp.get("name", "AUSSICHTSPUNKT"))
		node.vista_sub = String(vp.get("sub", "WEITBLICK"))
		node.sector = int(vp.get("sector", 3))
		node.variant = int(vp.get("variant", 0))
		node.position = world_px
		props_root.add_child(node)


func _attach_blockers() -> void:
	var b_list_v: Variant = zone.raw.get("blockers")
	if not (b_list_v is Array):
		return
	for b_v: Variant in b_list_v as Array:
		if not (b_v is Dictionary):
			continue
		var bd: Dictionary = b_v as Dictionary
		var tid: StringName = StringName(String(bd.get("threshold_id", "")))
		var t_arr: Array = bd.get("tile", []) as Array
		if tid == &"" or t_arr.size() < 2:
			continue
		var blocker: WindkapProps.ThresholdBlocker = WindkapProps.ThresholdBlocker.new()
		blocker.name = "Blocker_" + String(tid)
		blocker.threshold_id = tid
		blocker.blocker_kind = String(bd.get("kind", "rockfall"))
		blocker.fallback_hint = String(bd.get("hint", ""))
		blocker.closed = bool(_gate_closed.get(tid, true))
		blocker.position = _local_to_world_px(Vector2(float(t_arr[0]), float(t_arr[1]))).round()
		props_root.add_child(blocker)
		blockers[tid] = blocker


func _attach_rocks() -> void:
	if _rock_plan.is_empty():
		return
	var rock_scene: PackedScene = load(ROCK_SCENE_PATH) as PackedScene
	if rock_scene == null:
		return
	var spawned: Array[LivingRock] = []
	for i: int in _rock_plan.size():
		var rp: Dictionary = _rock_plan[i]
		var rk: LivingRock = rock_scene.instantiate() as LivingRock
		rk.name = "Rock%d" % i
		rk.setup_rock(rp["pos"] as Vector2, int(rp["stage"]), int(rp["seed"]), "valley_stone")
		props_root.add_child(rk)
		spawned.append(rk)
	# Compute genuine woodland-shade microclimate ecology (moss, lichen, ivy, ferns, fungi) asynchronously!
	if not spawned.is_empty():
		var tree_pts: Array[Vector2] = []
		for tp: Dictionary in _tree_plan:
			tree_pts.append(tp["pos"] as Vector2)
		LivingRock.compute_outcrop_ecology_async(spawned, tree_pts)


func _attach_flora() -> void:
	if _flora_plan.is_empty():
		return
	var world: Node = get_tree().get_first_node_in_group("world")
	var plants: Dictionary = DataRegistry.table("plants")
	var bush_scene: PackedScene = load(BUSH_SCENE_PATH) as PackedScene
	var flora_scene: PackedScene = load(FLORA_SCENE_PATH) as PackedScene
	for i: int in _flora_plan.size():
		var fp: Dictionary = _flora_plan[i]
		var kind: String = String(fp["kind"])
		var spec: Dictionary = plants.get(kind, {}) as Dictionary
		var scene_path: String = String(spec.get("scene", FLORA_SCENE_PATH))
		var scene: PackedScene = bush_scene if scene_path == BUSH_SCENE_PATH else flora_scene
		if scene == null:
			continue
		var prop: WorldProp = scene.instantiate() as WorldProp
		var cell: Vector2i = fp["cell"] as Vector2i
		prop.setup(world, cell, kind, int(fp["variant"]))
		prop.position = fp["pos"] as Vector2
		if kind == "cattail":
			prop.add_to_group("river_perches") ## kingfishers & dragonflies perch along Erlenbach!
		props_root.add_child(prop)
		flora_nodes[cell] = prop
