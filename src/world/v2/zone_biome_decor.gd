class_name ZoneBiomeDecor
extends RefCounted
## Deterministic, multiplayer-identical coastal beach, estuary, brook & rocky plateau decor builder
## for Shadowspore 2.0 `ZoneStage` zones — strictly using ONLY existing handcrafted project assets:
##   1. `assets/tiles/coastal_props.png` (+ `_glow.png`) with `coastal_prop_water.gdshader`
##      for live swash wash-over, refraction, wet capillary base darkening, WorldWind sway on
##      dune oats & brook reeds, & obstacle surf/wake injection.
##   2. `RockyGround.add_rock_detail()` (`assets/tiles/rock_ground_details.png` + `_glow.png`)
##      for geological ground details across exposed bedrock, scree fans & moss hollows.

const COASTAL_TEX_PATH: String = "res://assets/tiles/coastal_props.png"
const COASTAL_GLOW_PATH: String = "res://assets/tiles/coastal_props_glow.png"
const PROP_WATER_SHADER: Shader = preload("res://assets/shaders/coastal_prop_water.gdshader")

## Exact 28 cells of existing `assets/tiles/coastal_props.png` (from `tools/art_coastal_biome.py`)
const COASTAL_DEFS: Array[Dictionary] = [
	{"r": Rect2(0, 0, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},     # 0 lily_cluster_0
	{"r": Rect2(32, 0, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},    # 1 lily_cluster_1
	{"r": Rect2(64, 0, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},    # 2 lily_cluster_2
	{"r": Rect2(96, 0, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false},  # 3 brook_reeds_0
	{"r": Rect2(128, 0, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": true},  # 4 brook_reeds_1
	{"r": Rect2(160, 0, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 5 brook_reeds_2
	{"r": Rect2(0, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false},  # 6 bank_root_0
	{"r": Rect2(32, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 7 bank_root_1
	{"r": Rect2(64, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 8 brook_boulder_0
	{"r": Rect2(96, 32, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false}, # 9 brook_boulder_1
	{"r": Rect2(128, 32, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false}, # 10 submerged_pebbles_0
	{"r": Rect2(160, 32, 32, 32), "o": Vector2(-16, -26), "flat": false, "glow": false},# 11 driftwood_0
	{"r": Rect2(0, 64, 32, 32), "o": Vector2(-16, -26), "flat": false, "glow": false},  # 12 driftwood_1
	{"r": Rect2(32, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 13 spulsaum_shells_0
	{"r": Rect2(64, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 14 spulsaum_shells_1
	{"r": Rect2(96, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 15 spulsaum_starfish_0
	{"r": Rect2(128, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},  # 16 spulsaum_kelp_0
	{"r": Rect2(160, 64, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},  # 17 spulsaum_kelp_1
	{"r": Rect2(0, 96, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},   # 18 beach_pebbles_0
	{"r": Rect2(32, 96, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": false},  # 19 beach_pebbles_1
	{"r": Rect2(64, 96, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": true},  # 20 dune_oats_0
	{"r": Rect2(96, 96, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": true},  # 21 dune_oats_1
	{"r": Rect2(128, 96, 32, 32), "o": Vector2(-16, -28), "flat": false, "glow": false},# 22 dune_oats_2
	{"r": Rect2(160, 96, 32, 32), "o": Vector2(-16, -16), "flat": true, "glow": true},  # 23 spulsaum_mixed_0
	{"r": Rect2(0, 128, 48, 36), "o": Vector2(-24, -31), "flat": false, "glow": true},  # 24 tidepool_rock_0
	{"r": Rect2(48, 128, 48, 36), "o": Vector2(-24, -31), "flat": false, "glow": true}, # 25 tidepool_rock_1
	{"r": Rect2(96, 128, 48, 36), "o": Vector2(-24, -31), "flat": false, "glow": true}, # 26 tidepool_rock_2
	{"r": Rect2(144, 128, 48, 36), "o": Vector2(-24, -30), "flat": false, "glow": false},# 27 driftwood_hero_0
]


## Shared lightweight night-glow controller so all biome prop glow overlays cost zero drawcalls by day.
class GlowController:
	extends Node2D
	var glow_sprites: Array[Sprite2D] = []

	func _process(_delta: float) -> void:
		var night: float = TimeManager.night_amount()
		var on: bool = night > 0.03
		var pulse: float = 0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.0018)
		var alpha: float = smoothstep(0.03, 0.82, night) * pulse
		for sp: Sprite2D in glow_sprites:
			if is_instance_valid(sp):
				sp.visible = on
				if on:
					sp.modulate.a = alpha


# ==============================================================================
# Main Entrypoint called from `ZoneStage._attach_zone_content()` (Main Thread)
# ==============================================================================

static func attach(stage: ZoneStage) -> void:
	if stage == null or stage.props_root == null:
		return
	var keep_clear: Array[Vector2] = _collect_keep_clear(stage)
	var glow_ctrl: GlowController = GlowController.new()
	glow_ctrl.name = "BiomeDecorGlowCtrl"
	stage.add_child(glow_ctrl)

	if stage.water != null:
		_attach_coastal_and_brook(stage, keep_clear, glow_ctrl)
	if stage.rocky != null:
		_attach_rocky_details(stage, keep_clear)


static func _collect_keep_clear(stage: ZoneStage) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for lm: Atlas.Landmark in stage.zone.landmarks:
		pts.append(Atlas.px_of(lm.pos))
	var camp_v: Variant = stage.zone.raw.get("camp")
	if camp_v is Dictionary:
		var c: Dictionary = camp_v as Dictionary
		for key: String in ["tile", "campfire_tile", "seat_tile"]:
			var a: Variant = c.get(key)
			if a is Array and (a as Array).size() >= 2:
				pts.append(Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float((a as Array)[0]), float((a as Array)[1]))))
		var ch_v: Variant = c.get("chest")
		if ch_v is Dictionary:
			var ct: Variant = (ch_v as Dictionary).get("tile")
			if ct is Array and (ct as Array).size() >= 2:
				pts.append(Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float((ct as Array)[0]), float((ct as Array)[1]))))
	for list_key: String in ["chests", "blockers", "veil_threads", "vistas", "waystones"]:
		var arr_v: Variant = stage.zone.raw.get(list_key)
		if arr_v is Array:
			for it_v: Variant in arr_v as Array:
				if it_v is Dictionary:
					var ta: Variant = (it_v as Dictionary).get("tile")
					if ta is Array and (ta as Array).size() >= 2:
						pts.append(Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float((ta as Array)[0]), float((ta as Array)[1]))))
	return pts


static func _near_any(p: Vector2, list: Array[Vector2], min_dist: float) -> bool:
	var d2: float = min_dist * min_dist
	for q: Vector2 in list:
		if p.distance_squared_to(q) < d2:
			return true
	return false


static func _on_way_or_path(stage: ZoneStage, world_pos: Vector2) -> bool:
	if stage.surfaces != null:
		var s: String = stage.surfaces.surface_at(world_pos)
		if s in ["path", "ancient_stone", "gravel"]:
			return true
	if stage.rocky != null:
		var rs: String = stage.rocky.surface_at(world_pos)
		if rs == "slope":
			var dt: Dictionary = stage.rocky.grass_habitat_at(world_pos)
			if String(dt.get("style", "")) == "none" and float(dt.get("density", 1.0)) <= 0.02:
				return true
	return false


static func _spawn_sprite(
	parent: Node2D,
	tex: Texture2D,
	glow_tex: Texture2D,
	def: Dictionary,
	pos: Vector2,
	flip_h: bool,
	mat: Material,
	glow_ctrl: GlowController
) -> void:
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = tex
	sp.region_enabled = true
	sp.region_rect = def["r"] as Rect2
	sp.centered = false
	sp.offset = def["o"] as Vector2
	sp.flip_h = flip_h
	sp.position = pos.round()
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if mat != null:
		sp.material = mat
	parent.add_child(sp)

	if bool(def.get("glow", false)) and glow_tex != null:
		var gl: Sprite2D = Sprite2D.new()
		gl.texture = glow_tex
		gl.region_enabled = true
		gl.region_rect = def["r"] as Rect2
		gl.centered = false
		gl.offset = def["o"] as Vector2
		gl.flip_h = flip_h
		gl.material = Unlit.material()
		gl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		gl.visible = false
		sp.add_child(gl)
		glow_ctrl.glow_sprites.append(gl)


# ==============================================================================
# Part A: Existing Coastal Beach, Estuary, Brook & Pond Assets (`coastal_props.png`)
# ==============================================================================

static func _attach_coastal_and_brook(stage: ZoneStage, keep_clear: Array[Vector2], glow_ctrl: GlowController) -> void:
	var coastal_tex: Texture2D = DataRegistry.tex(COASTAL_TEX_PATH)
	var coastal_glow: Texture2D = DataRegistry.tex(COASTAL_GLOW_PATH)
	if coastal_tex == null:
		return

	var water: WaterField = stage.water
	var flat_mat: ShaderMaterial = ShaderMaterial.new()
	flat_mat.shader = PROP_WATER_SHADER
	flat_mat.set_shader_parameter("is_flat_prop", true)
	flat_mat.set_shader_parameter("map_origin", water.bounds.position)
	flat_mat.set_shader_parameter("map_size", water.bounds.size)
	flat_mat.set_shader_parameter("water_geo_map", water.geo_texture())
	flat_mat.set_shader_parameter("water_flow_map", water.flow_texture())

	var ysort_mat: ShaderMaterial = ShaderMaterial.new()
	ysort_mat.shader = PROP_WATER_SHADER
	ysort_mat.set_shader_parameter("is_flat_prop", false)
	ysort_mat.set_shader_parameter("map_origin", water.bounds.position)
	ysort_mat.set_shader_parameter("map_size", water.bounds.size)
	ysort_mat.set_shader_parameter("water_geo_map", water.geo_texture())
	ysort_mat.set_shader_parameter("water_flow_map", water.flow_texture())

	var flat_root: Node2D = Node2D.new()
	flat_root.name = "CoastalPropsFlat"
	flat_root.z_as_relative = false
	flat_root.z_index = -5
	stage.add_child(flat_root)

	var ysort_root: Node2D = stage.props_root
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([String(stage.zone.id), "coastal_decor_v3"])

	var placed_standing: Array[Vector2] = []
	var placed_flat: Array[Vector2] = []

	var camp_center: Vector2 = Vector2.INF
	var camp_v: Variant = stage.zone.raw.get("camp")
	if camp_v is Dictionary:
		var cf: Variant = (camp_v as Dictionary).get("campfire_tile")
		if cf is Array and (cf as Array).size() >= 2:
			camp_center = Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float((cf as Array)[0]), float((cf as Array)[1])))

	# 1. Existing driftwood anchor near West Silberbucht's hidden thread hint
	if String(stage.zone.id) == "windkap":
		var drift_clue: Vector2 = Atlas.px_of(Vector2(stage.zone.origin) + Vector2(31.8, 134.8)).round()
		_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[27], drift_clue, false, ysort_mat, glow_ctrl)
		placed_standing.append(drift_clue)

	# 2. Walk the coastline polyline for existing shells, pebbles, starfish, driftwood, dune oats & headland tidepool rocks
	var shore_pts: PackedVector2Array = stage._shore_pts_px
	if shore_pts.size() >= 2:
		for si: int in shore_pts.size() - 1:
			var a: Vector2 = shore_pts[si]
			var b: Vector2 = shore_pts[si + 1]
			var seg_len: float = a.distance_to(b)
			if seg_len < 1.0:
				continue
			var tang: Vector2 = (b - a) / seg_len
			var nrm: Vector2 = tang.orthogonal()
			var mid: Vector2 = (a + b) * 0.5
			if water.field_at(mid + nrm * 20.0).x < water.field_at(mid - nrm * 20.0).x:
				nrm = -nrm

			var steps: int = maxi(1, int(floorf(seg_len / 28.0)))
			for st: int in steps:
				var frac: float = (float(st) + rng.randf_range(0.15, 0.85)) / float(steps)
				var base_pt: Vector2 = a.lerp(b, frac)

				var near_brook: Vector2 = water.nearest_brook_px(base_pt)
				var brook_dist: float = base_pt.distance_to(near_brook) if near_brook != Vector2.INF else 9999.0
				var in_estuary_flank: bool = brook_dist >= 36.0 and brook_dist <= 108.0
				var in_mouth_channel: bool = brook_dist < 42.0
				if in_mouth_channel:
					continue

				# --- Band 1: Wet Swash & Rocky Headland Edge (shells, starfish, pebbles; tidepool rocks ONLY on rocky headlands!) ---
				var swash_pt: Vector2 = (base_pt + nrm * rng.randf_range(-2.0, 14.0)).round()
				var wf_sw: Dictionary = water.water_field_at(swash_pt)
				var sdf_sw: float = float(wf_sw.get("static_sdf_px", 99.0))
				var reg_sw: int = int(wf_sw.get("regime", 0))
				var bed_sw: int = int(wf_sw.get("bed_id", 0))
				if reg_sw == WaterRules.REGIME_SURF and sdf_sw >= -5.0 and sdf_sw <= 16.0:
					if camp_center == Vector2.INF or swash_pt.distance_to(camp_center) > 76.0:
						if not _near_any(swash_pt, keep_clear, 46.0):
							var roll_sw: float = rng.randf()
							if bed_sw == WaterRules.BED_ROCK and roll_sw < 0.28 and not _near_any(swash_pt, placed_standing, 96.0):
								var tr_id: int = 24 + rng.randi() % 3
								_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[tr_id], swash_pt, rng.randf() < 0.5, ysort_mat, glow_ctrl)
								water.inject_obstacle(swash_pt + Vector2(-2.0, -4.0), 10.5, 0.86)
								placed_standing.append(swash_pt)
							elif bed_sw == WaterRules.BED_SAND and roll_sw < 0.34 and not _near_any(swash_pt, placed_flat, 36.0):
								# Clean shells, starfish & smooth beach pebbles (zero green kelp blotches!)
								var flat_ids: Array[int] = [13, 14, 15, 18, 19]
								var fid: int = flat_ids[rng.randi() % flat_ids.size()]
								_spawn_sprite(flat_root, coastal_tex, coastal_glow, COASTAL_DEFS[fid], swash_pt, rng.randf() < 0.5, flat_mat, glow_ctrl)
								placed_flat.append(swash_pt)

				# --- Band 2: Mid-Beach (sun-bleached driftwood logs, clean shells & beach pebbles, estuary reeds!) ---
				var mid_pt: Vector2 = (base_pt + nrm * rng.randf_range(22.0, 50.0)).round()
				var wf_mid: Dictionary = water.water_field_at(mid_pt)
				var sdf_mid: float = float(wf_mid.get("static_sdf_px", 99.0))
				if sdf_mid >= 18.0 and sdf_mid <= 54.0 and int(wf_mid.get("bed_id", 0)) == WaterRules.BED_SAND:
					var clear_camp: bool = camp_center == Vector2.INF or mid_pt.distance_to(camp_center) > 96.0
					if clear_camp and not _near_any(mid_pt, keep_clear, 46.0) and not _on_way_or_path(stage, mid_pt):
						var r_mid: float = rng.randf()
						if in_estuary_flank and r_mid < 0.34 and not _near_any(mid_pt, placed_standing, 30.0):
							var rd_id: int = 3 + rng.randi() % 3
							_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[rd_id], mid_pt, rng.randf() < 0.5, ysort_mat, glow_ctrl)
							placed_standing.append(mid_pt)
						elif r_mid < 0.11 and not _near_any(mid_pt, placed_standing, 86.0):
							var dw_ids: Array[int] = [11, 12, 27]
							var dw_id: int = dw_ids[rng.randi() % dw_ids.size()]
							_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[dw_id], mid_pt, rng.randf() < 0.5, ysort_mat, glow_ctrl)
							water.inject_obstacle(mid_pt, 8.0, 0.62)
							placed_standing.append(mid_pt)
						elif r_mid < 0.42 and not _near_any(mid_pt, placed_flat, 32.0):
							var sh_ids: Array[int] = [13, 14, 15, 18, 19]
							var sid: int = sh_ids[rng.randi() % sh_ids.size()]
							_spawn_sprite(flat_root, coastal_tex, coastal_glow, COASTAL_DEFS[sid], mid_pt, rng.randf() < 0.5, flat_mat, glow_ctrl)
							placed_flat.append(mid_pt)

				# --- Band 3: Upper Dune Ridge (wind-swaying golden Strandhafer marram grass tufts!) ---
				var dune_pt: Vector2 = (base_pt + nrm * rng.randf_range(58.0, 96.0)).round()
				var wf_du: Dictionary = water.water_field_at(dune_pt)
				var sdf_du: float = float(wf_du.get("static_sdf_px", 99.0))
				var reg_du: int = int(wf_du.get("regime", 0))
				if reg_du == WaterRules.REGIME_LAND and sdf_du >= 50.0 and sdf_du <= 106.0:
					var clear_camp2: bool = camp_center == Vector2.INF or dune_pt.distance_to(camp_center) > 106.0
					if clear_camp2 and not _near_any(dune_pt, keep_clear, 50.0) and not _on_way_or_path(stage, dune_pt) and not _near_any(dune_pt, placed_standing, 34.0):
						if rng.randf() < 0.52:
							var do_id: int = 20 + rng.randi() % 3
							_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[do_id], dune_pt, rng.randf() < 0.5, ysort_mat, glow_ctrl)
							placed_standing.append(dune_pt)

	# 3. Brooks & Lakes: existing reeds, overhanging roots, flow-waking boulders, submerged pebbles & floating lily pads
	var raw_water: Variant = stage.zone.raw.get("water")
	if raw_water is Dictionary:
		var wcfg: Dictionary = raw_water as Dictionary
		var brooks_v: Variant = wcfg.get("brooks")
		if brooks_v is Array:
			for br_v: Variant in brooks_v as Array:
				if not (br_v is Dictionary):
					continue
				var pts_raw: Array = (br_v as Dictionary).get("pts", []) as Array
				for pi: int in pts_raw.size() - 1:
					var pa: Array = pts_raw[pi] as Array
					var pb: Array = pts_raw[pi + 1] as Array
					if pa.size() < 3 or pb.size() < 3:
						continue
					var a_px: Vector2 = Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float(pa[0]), float(pa[1])))
					var b_px: Vector2 = Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float(pb[0]), float(pb[1])))
					var rad_avg: float = (float(pa[2]) + float(pb[2])) * 0.5
					var seg_d: float = a_px.distance_to(b_px)
					if seg_d < 4.0:
						continue
					var perp: Vector2 = ((b_px - a_px) / seg_d).orthogonal()
					var bsteps: int = maxi(1, int(floorf(seg_d / 34.0)))
					for bs: int in bsteps:
						var mp: Vector2 = a_px.lerp(b_px, (float(bs) + rng.randf_range(0.15, 0.85)) / float(bsteps))
						var wf_c: Dictionary = water.water_field_at(mp)
						if int(wf_c.get("regime", 0)) == WaterRules.REGIME_SURF or int(wf_c.get("regime", 0)) == WaterRules.REGIME_OCEAN:
							continue
						for side: float in [-1.0, 1.0]:
							var bank_p: Vector2 = (mp + perp * side * (rad_avg + rng.randf_range(2.0, 11.0))).round()
							if _near_any(bank_p, keep_clear, 54.0) or _near_any(bank_p, placed_standing, 28.0) or _on_way_or_path(stage, bank_p):
								continue
							var wf_b: Dictionary = water.water_field_at(bank_p)
							var sdf_b: float = float(wf_b.get("static_sdf_px", 99.0))
							var bed_b: int = int(wf_b.get("bed_id", 0))
							if sdf_b < -2.0 or sdf_b > 15.0:
								continue
							var rb: float = rng.randf()
							if bed_b == WaterRules.BED_SAND:
								if rb < 0.34:
									var do_e: int = 20 + rng.randi() % 3
									_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[do_e], bank_p, rng.randf() < 0.5, ysort_mat, glow_ctrl)
									placed_standing.append(bank_p)
							elif rb < 0.36:
								var rd_id: int = 3 + rng.randi() % 3
								_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[rd_id], bank_p, rng.randf() < 0.5, ysort_mat, glow_ctrl)
								placed_standing.append(bank_p)
							elif rb < 0.50:
								var rt_id: int = 6 + rng.randi() % 2
								_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[rt_id], bank_p, side < 0.0, ysort_mat, glow_ctrl)
								placed_standing.append(bank_p)
							elif rb < 0.62 and sdf_b <= 4.0:
								var bb_id: int = 8 + rng.randi() % 2
								_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[bb_id], bank_p, rng.randf() < 0.5, ysort_mat, glow_ctrl)
								water.inject_obstacle(bank_p + Vector2(0.0, -3.0), 8.0, 0.85)
								placed_standing.append(bank_p)
						if float(wf_c.get("depth", 1.0)) < 0.36 and rng.randf() < 0.45 and not _near_any(mp, placed_flat, 26.0):
							_spawn_sprite(flat_root, coastal_tex, coastal_glow, COASTAL_DEFS[10], mp.round(), rng.randf() < 0.5, flat_mat, glow_ctrl)
							placed_flat.append(mp)

		var lakes_v: Variant = wcfg.get("lakes")
		if lakes_v is Array:
			for lk_v: Variant in lakes_v as Array:
				if not (lk_v is Dictionary):
					continue
				var lk: Dictionary = lk_v as Dictionary
				var ca: Array = lk.get("center", []) as Array
				var ra: Array = lk.get("radii", [5.0, 4.0]) as Array
				if ca.size() < 2 or ra.size() < 2:
					continue
				var l_center: Vector2 = Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float(ca[0]), float(ca[1])))
				var l_rad: Vector2 = Vector2(float(ra[0]), float(ra[1])) * Atlas.TILE_PX
				for _li: int in 7:
					var ang: float = rng.randf() * TAU
					var dist_f: float = rng.randf_range(0.32, 0.72)
					var lp: Vector2 = (l_center + Vector2(cos(ang) * l_rad.x, sin(ang) * l_rad.y) * dist_f).round()
					var wf_l: Dictionary = water.water_field_at(lp)
					if bool(wf_l.get("water", false)) and not _near_any(lp, placed_flat, 24.0):
						var lid: int = rng.randi() % 3
						_spawn_sprite(flat_root, coastal_tex, coastal_glow, COASTAL_DEFS[lid], lp, rng.randf() < 0.5, flat_mat, glow_ctrl)
						placed_flat.append(lp)
				for ri: int in 9:
					var ang2: float = (float(ri) / 9.0) * TAU + rng.randf_range(-0.18, 0.18)
					var rp: Vector2 = (l_center + Vector2(cos(ang2) * (l_rad.x + 4.0), sin(ang2) * (l_rad.y + 4.0))).round()
					var wf_r: Dictionary = water.water_field_at(rp)
					if float(wf_r.get("static_sdf_px", 99.0)) >= 0.0 and float(wf_r.get("static_sdf_px", 99.0)) <= 12.0 and not _near_any(rp, placed_standing, 26.0):
						_spawn_sprite(ysort_root, coastal_tex, coastal_glow, COASTAL_DEFS[3 + rng.randi() % 3], rp, rng.randf() < 0.5, ysort_mat, glow_ctrl)
						placed_standing.append(rp)


# ==============================================================================
# Part B: Existing Rocky Ground Details (`assets/tiles/rock_ground_details.png`)
# ==============================================================================

static func _attach_rocky_details(stage: ZoneStage, keep_clear: Array[Vector2]) -> void:
	var rocky: RockyGround = stage.rocky
	if rocky == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([String(stage.zone.id), "rocky_details_v3"])

	var rocky_polys: Array[PackedVector2Array] = []
	var raw_rocky: Variant = stage.zone.raw.get("rocky")
	if raw_rocky is Array:
		for entry_v: Variant in raw_rocky as Array:
			if entry_v is Dictionary:
				var pr: Variant = (entry_v as Dictionary).get("poly")
				if pr is Array and (pr as Array).size() >= 3:
					var poly: PackedVector2Array = PackedVector2Array()
					for pt_v: Variant in pr as Array:
						if pt_v is Array and (pt_v as Array).size() >= 2:
							var a: Array = pt_v as Array
							poly.append(Atlas.px_of(Vector2(stage.zone.origin) + Vector2(float(a[0]), float(a[1]))))
					rocky_polys.append(poly)
	if rocky_polys.is_empty():
		return

	var scan_rect: Rect2 = Rect2(rocky_polys[0][0], Vector2.ZERO)
	for poly: PackedVector2Array in rocky_polys:
		for pt: Vector2 in poly:
			scan_rect = scan_rect.expand(pt)
	scan_rect = scan_rect.grow(24.0)

	var rock_pts: Array[Vector2] = []
	for rp: Dictionary in stage._rock_plan:
		rock_pts.append(rp["pos"] as Vector2)

	var detail_step: float = 32.0
	var dy: float = scan_rect.position.y
	while dy <= scan_rect.end.y:
		var dx: float = scan_rect.position.x
		while dx <= scan_rect.end.x:
			var p: Vector2 = Vector2(dx + rng.randf_range(-12.0, 12.0), dy + rng.randf_range(-12.0, 12.0)).round()
			var surf: String = rocky.surface_at(p)
			if not surf.is_empty():
				var off_beach: bool = stage.water == null or (stage.water.field_at(p).x > 26.0 and not (stage.water.surface_at(p) in ["beach_sand", "wet_sand", "tide_shallow"]))
				if off_beach and not _near_any(p, keep_clear, 38.0) and not _near_any(p, rock_pts, 22.0) and not stage.in_sanctum(p, 8.0):
					if rng.randf() < 0.76:
						var v: int = 0
						var r2: float = rng.randf()
						if surf == "stone":
							v = 9 if r2 < 0.28 else (10 if r2 < 0.50 else (3 if r2 < 0.68 else (13 if r2 < 0.84 else (14 if r2 < 0.94 else 15))))
						elif surf == "gravel":
							v = 0 if r2 < 0.30 else (1 if r2 < 0.58 else (2 if r2 < 0.80 else (5 if r2 < 0.92 else 6)))
						elif surf == "moss":
							v = 11 if r2 < 0.35 else (12 if r2 < 0.65 else (6 if r2 < 0.85 else 15))
						else:
							v = 3 if r2 < 0.28 else (4 if r2 < 0.52 else (7 if r2 < 0.74 else (8 if r2 < 0.90 else 0)))
						var tv: float = rng.randf_range(0.92, 1.06)
						rocky.add_rock_detail(p, v, rng.randf() < 0.5, Color(tv, tv, tv, 1.0))
			dx += detail_step
		dy += detail_step
