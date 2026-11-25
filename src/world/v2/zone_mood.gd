class_name ZoneMood
extends Node
## The mood of the zone world (docs/v2_zonenwelt_atlas_konzept.md 7, step 5): every zone names a profile (`mood` in its
## zone.json, profiles in `data/world/moods.json`) for light, colour grade, wind, pollen and sound beds. At the camera the
## profiles of the zones round it are blended by their signed distance to each footprint: 15 tiles inside a zone = its own
## mood, on a seam = half and half, so a threshold crossing is one slow change over about 30 tiles, never a cut. A place may
## lean the mood a little (`mood` + `mood_amount` in its entry: a dark grove in a bright zone).
##
## Cosmetic and local on every peer. The blended profile is `ZoneMood.now` (static, {} while no zone world runs); the
## existing systems read it: `DayNight` (light, sun, grade), `WorldWind` (wind), `DayMotes` (pollen), `DayAmbience` (beds).
## Neutral values change nothing, so the old world is untouched.

const BLEND_TILES: float = 30.0 ## the width of a mood change across a seam
const PLACE_BLEND: float = 6.0 ## tiles inside a place until its lean is whole
const EASE: float = 1.4 ## per second towards the mood at the camera (a teleport snaps)
const SNAP_TILES: float = 40.0
const PROFILE_PATH: String = "world/moods.json"
const COLORS: Array[String] = ["tint_day", "tint_night", "shadow", "light", "hud_bark"]
const FLOATS: Array[String] = ["sun", "vibrance", "contrast", "bloom", "vignette", "wind", "motes", "amb_day", "amb_night", "amb_wind", "amb_crickets", "hud_tint", "hud_void"]
const NEUTRAL: Dictionary = {
	"tint_day": Color(1, 1, 1), "tint_night": Color(1, 1, 1), "shadow": Color(1, 1, 1), "light": Color(1, 1, 1),
	"sun": 1.0, "vibrance": 0.0, "contrast": 0.0, "bloom": 0.0, "vignette": 0.0,
	"wind": 1.0, "motes": 1.0, "amb_day": 1.0, "amb_night": 1.0, "amb_wind": 1.0, "amb_crickets": 1.0,
	"hud_bark": Color(1, 1, 1), "hud_tint": 0.0, "hud_void": 0.0, ## the HUD's bark (VineStyle.follow_mood)
}

static var now: Dictionary = {} ## the blended profile at the local camera; {} = no zone world

var atlas: Atlas
var continent_id: StringName = &"main"
var weights: Dictionary = {} ## zone id -> share at the camera (tests, status)
var place_lean: float = 0.0 ## how much the place under the camera leans the mood
var _profiles: Dictionary = {} ## mood id -> parsed profile
var _current: Dictionary = {}
var _last_tile: Vector2 = Vector2.INF


func setup(p_atlas: Atlas, p_continent: StringName) -> void:
	atlas = p_atlas
	continent_id = p_continent
	_profiles.clear()
	var data: Dictionary = DataRegistry.json(PROFILE_PATH)
	for key: Variant in (data.get("moods", {}) as Dictionary).keys():
		_profiles[StringName(String(key))] = parse((data["moods"] as Dictionary)[key] as Dictionary)


func _exit_tree() -> void:
	if now == _current:
		now = {}


func _process(delta: float) -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null or atlas == null:
		return
	var tile: Vector2 = Atlas.tile_of(camera.get_screen_center_position())
	var target: Dictionary = profile_at(tile)
	if target.is_empty():
		return
	if _current.is_empty() or not _last_tile.is_finite() or tile.distance_to(_last_tile) > SNAP_TILES:
		_current = target
	else:
		_current = blend(_current, target, 1.0 - exp(-EASE * delta))
	_last_tile = tile
	now = _current


## The profile a camera at `tile` settles to (pure apart from `weights` / `place_lean`); {} far from every zone.
func profile_at(tile: Vector2) -> Dictionary:
	weights.clear()
	var total: float = 0.0
	var mixed: Dictionary = {}
	var main_zone: Atlas.Zone = null
	var main_w: float = 0.0
	for zone: Atlas.Zone in atlas.zones_of(continent_id):
		if not zone.bbox.grow(BLEND_TILES).has_point(tile):
			continue
		var d: float = ZoneMath.rim_distance(tile, zone.footprint)
		var signed: float = -d if Geometry2D.is_point_in_polygon(tile, zone.footprint) else d
		var w: float = clampf(0.5 - signed / BLEND_TILES, 0.0, 1.0)
		if w <= 0.0:
			continue
		w = w * w * (3.0 - 2.0 * w)
		weights[zone.id] = w
		var profile: Dictionary = profile(zone.mood)
		mixed = profile if mixed.is_empty() else blend(mixed, profile, w / (total + w))
		total += w
		if w > main_w:
			main_w = w
			main_zone = zone
	if total <= 0.0:
		return {}
	for id: Variant in weights.keys():
		weights[id] = float(weights[id]) / total
	place_lean = 0.0
	if main_zone != null:
		for place: Atlas.Place in main_zone.places:
			var lean_id: StringName = StringName(String(place.raw.get("mood", "")))
			if lean_id == &"" or not place.bbox.has_point(tile) or not Geometry2D.is_point_in_polygon(tile, place.poly):
				continue
			var depth: float = ZoneMath.rim_distance(tile, place.poly)
			place_lean = clampf(depth / PLACE_BLEND, 0.0, 1.0) * float(place.raw.get("mood_amount", 0.6))
			mixed = blend(mixed, profile(lean_id), place_lean)
			break
	return mixed


## A named profile, neutral when it is unknown.
func profile(mood_id: StringName) -> Dictionary:
	return _profiles.get(mood_id, NEUTRAL) as Dictionary


static func parse(entry: Dictionary) -> Dictionary:
	var out: Dictionary = NEUTRAL.duplicate()
	for key: String in COLORS:
		var list: Variant = entry.get(key)
		if list is Array and (list as Array).size() >= 3:
			out[key] = Color(float(list[0]), float(list[1]), float(list[2]))
	for key: String in FLOATS:
		if entry.has(key):
			out[key] = float(entry[key])
	return out


static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var out: Dictionary = {}
	for key: String in COLORS:
		out[key] = (a.get(key, Color.WHITE) as Color).lerp(b.get(key, Color.WHITE) as Color, weight)
	for key: String in FLOATS:
		out[key] = lerpf(float(a.get(key, NEUTRAL[key])), float(b.get(key, NEUTRAL[key])), weight)
	return out


## A float of the current mood, `fallback` while no zone world runs.
static func value(key: String, fallback: float = 1.0) -> float:
	return float(now.get(key, fallback)) if not now.is_empty() else fallback


## A colour of the current mood, white while no zone world runs.
static func tint(key: String) -> Color:
	return now.get(key, Color.WHITE) as Color if not now.is_empty() else Color.WHITE
