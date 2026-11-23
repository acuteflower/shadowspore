class_name WaterRules
extends RefCounted
## Deterministic analytical twin for Water System v2 (swash, sand wetness, ocean swell,
## flow drift, and rain-reactive puddle expansion). Mirrors `water_optics.gdshaderinc`
## operation-for-operation so CPU gameplay queries and GPU rendering match without RPCs.

const SWASH_PERIOD: float = 5.2
const SWASH_SURGE_END: float = 0.28
const SWASH_TROUGH: float = -0.22
const SWASH_SPAN: float = 1.22
const DRY_TAU: float = 4.0
const WET_THRESHOLD: float = 0.25
const PUDDLE_MAX_REACH_PX: float = 8.0

const REGIME_LAND: int = 0
const REGIME_BROOK: int = 1
const REGIME_LAKE: int = 2
const REGIME_SURF: int = 3
const REGIME_OCEAN: int = 4
const REGIME_PUDDLE: int = 5

const BED_NONE: int = 0
const BED_PEBBLE: int = 1
const BED_SAND: int = 2
const BED_ROCK: int = 3
const BED_MUD: int = 4
const BED_SILT: int = 5
const BED_REEF: int = 6


static func swash_reach_px(wind_dir: Vector2, wind_gust: float, storm: float) -> float:
	var onshore: float = clampf(wind_dir.x, -0.5, 1.0)
	var gust_c: float = clampf(wind_gust, 0.0, 4.0)
	return 14.0 + gust_c * 2.2 * (0.55 + 0.45 * maxf(onshore, 0.0)) + clampf(storm, 0.0, 1.0) * 7.5


static func swash_phase(y_world: float, time: float, _wind_dir: Vector2 = Vector2.RIGHT, _wind_gust: float = 0.0, _storm: float = 0.0) -> float:
	var along_shift: float = y_world * 0.0038 + 0.035 * sin(fposmod(y_world * 0.014, TAU))
	return fposmod(time / SWASH_PERIOD + along_shift, 1.0)


static func swash_shape(p01: float) -> float:
	if p01 < SWASH_SURGE_END:
		var t: float = p01 / SWASH_SURGE_END
		return SWASH_TROUGH + SWASH_SPAN * (0.5 - 0.5 * cos(fposmod(t * PI, TAU)))
	var t_back: float = (p01 - SWASH_SURGE_END) / (1.0 - SWASH_SURGE_END)
	return 1.0 - SWASH_SPAN * (0.5 - 0.5 * cos(fposmod(t_back * PI, TAU)))


static func swash_offset_px(y_world: float, time: float, wind_dir: Vector2, wind_gust: float, storm: float) -> float:
	var p01: float = swash_phase(y_world, time, wind_dir, wind_gust, storm)
	var reach: float = swash_reach_px(wind_dir, wind_gust, storm)
	return swash_shape(p01) * reach


static func sand_wetness(sdf_px: float, y_world: float, time: float, wind_dir: Vector2, wind_gust: float, storm: float) -> float:
	var reach: float = maxf(swash_reach_px(wind_dir, wind_gust, storm), 0.01)
	var p01: float = swash_phase(y_world, time, wind_dir, wind_gust, storm)
	var cur_off: float = swash_shape(p01) * reach
	if sdf_px <= cur_off:
		return 1.0
	var h: float = clampf(sdf_px / reach, SWASH_TROUGH, 1.0)
	var u: float = clampf((h - SWASH_TROUGH) / SWASH_SPAN, 0.0, 1.0)
	var p_retreat: float = SWASH_SURGE_END + (1.0 - SWASH_SURGE_END) * (acos(clampf(2.0 * u - 1.0, -0.99999, 0.99999)) / PI)
	var dt_phase: float = (p01 - p_retreat) if (p01 >= p_retreat) else (p01 + 1.0 - p_retreat)
	var age_sec: float = dt_phase * SWASH_PERIOD
	var decay: float = exp(-age_sec / DRY_TAU)
	var capillary_fade: float = 1.0 - smoothstep(reach, reach + 6.0, sdf_px)
	return clampf(decay * capillary_fade, 0.0, 1.0)


static func shore_state_at(sdf_px: float, y_world: float, time: float, wind_dir: Vector2, wind_gust: float, storm: float) -> String:
	var eff_sdf: float = sdf_px - swash_offset_px(y_world, time, wind_dir, wind_gust, storm)
	if eff_sdf <= 0.0:
		return "tide_shallow"
	if sand_wetness(sdf_px, y_world, time, wind_dir, wind_gust, storm) > WET_THRESHOLD:
		return "wet_sand"
	return "beach_sand"


static func swell_height(world_pos: Vector2, time: float, wind_dir: Vector2, wind_gust: float, storm: float) -> float:
	var da_raw: Vector2 = Vector2(0.92, 0.39) + wind_dir * 0.25
	var da: Vector2 = da_raw.normalized() if da_raw.length_squared() > 0.0001 else Vector2(0.92, 0.39).normalized()
	var db_raw: Vector2 = Vector2(0.84, -0.54) + wind_dir * 0.20
	var db: Vector2 = db_raw.normalized() if db_raw.length_squared() > 0.0001 else Vector2(0.84, -0.54).normalized()
	var pa: float = fposmod(world_pos.dot(da) * 0.15 - time * (1.75 + 0.55 * storm), TAU)
	var pb: float = fposmod(world_pos.dot(db) * 0.22 - time * (2.15 + 0.65 * storm), TAU)
	var ha: float = sin(pa) + 0.22 * sin(fposmod(2.0 * pa + 0.4, TAU))
	var hb: float = sin(pb)
	var amp: float = clampf(0.45 + 0.22 * wind_gust + 0.35 * storm, 0.35, 1.35)
	return (0.65 * ha + 0.35 * hb) * amp


static func flow_drift_at(world_pos: Vector2, time: float, wind_dir: Vector2, wind_gust: float, storm: float, regime: int, depth: float) -> Vector2:
	if regime == REGIME_SURF:
		var p01: float = swash_phase(world_pos.y, time, wind_dir, wind_gust, storm)
		var surge_vx: float = 0.0
		if p01 < SWASH_SURGE_END:
			surge_vx = sin(fposmod(p01 / SWASH_SURGE_END * PI, TAU)) * 18.0
		else:
			surge_vx = -sin(fposmod((p01 - SWASH_SURGE_END) / (1.0 - SWASH_SURGE_END) * PI, TAU)) * 10.0
		var shallow_k: float = clampf(1.0 - depth * 1.4, 0.2, 1.0) * (1.0 + 0.35 * storm)
		return Vector2(surge_vx * shallow_k, wind_dir.y * (2.5 + 2.0 * storm))
	if regime == REGIME_OCEAN:
		var sh: float = swell_height(world_pos, time, wind_dir, wind_gust, storm)
		return Vector2(sh * 7.5 + wind_dir.x * (3.0 + 4.0 * storm), wind_dir.y * (3.0 + 4.0 * storm))
	return Vector2.ZERO


static func puddle_reach_px(puddle_amt: float) -> float:
	return clampf(puddle_amt, 0.0, 1.0) * PUDDLE_MAX_REACH_PX


static func puddle_depth_at(static_sdf_px: float, basin_depth: float, puddle_amt: float) -> float:
	var eff: float = static_sdf_px - puddle_reach_px(puddle_amt)
	if eff > 0.0:
		return 0.0
	return clampf(basin_depth * clampf(-eff / 10.0, 0.15, 1.0), 0.05, 0.35)
