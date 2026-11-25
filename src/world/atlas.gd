class_name Atlas
extends RefCounted
## The world of Shadowspore 2.0 as data (docs/v2_zonenwelt_atlas_konzept.md, sections 2-5 and 11): continents, zones,
## places, landmarks and thresholds, all in REAL continent tile coordinates (decision 1: a zone lies at its `origin` on
## its continent; zone-local data in the files is shifted by it while building). Every continent has its own coordinate
## system from (0, 0); pockets live in the negative quadrant (`PocketSpace`).
##
## Pure and immutable once built: the same answers on every peer, safe to query from `Jobs` workers. Build it on the
## main thread (`Atlas.shared()` loads data/world/ through `DataRegistry.json`); `Atlas.from_data` builds one from plain
## dictionaries (tests, tools). Data problems never stop the build: they are collected in `problems`.
##
## Files: data/world/atlas.json (continents), data/world/continents/<id>.json (size, regions, zone ids, thresholds file,
## `seams`), data/world/zones/<id>/zone.json (one zone), the thresholds file named by the continent.
##
## Planned edges (concept 3.5): a continent's `seams` are hand-drawn polylines shared by two neighbouring zones; a zone's
## `footprint` may splice one in with {"seam": id} (its direction is found from the points around it). With
## `"curve": true` the zone's own control points become a smooth curve (Catmull-Rom through every point) while seam runs
## stay exactly as drawn, so both neighbours share the same edge. A threshold may lie on a seam (`seam`, `span`
## [from, to] as shares of its length): its line is then that piece of the seam (a polyline).

const TILE_PX: float = 16.0
const BUCKET_TILES: float = 64.0 ## spatial buckets of zone bounding boxes for `zone_at`
const LINE_REACH: float = 2.5 ## tiles: a seamless threshold's line must lie this close to both zones
const SEAMLESS_KINDS: Array[StringName] = [&"path", &"pass", &"ford", &"bridge", &"jump"]
const HARD_KINDS: Array[StringName] = [&"tunnel", &"ferry", &"ship"]
const ZONE_KINDS: Array[StringName] = [&"field", &"home", &"settlement", &"pass", &"wonder", &"coast", &"void"]
const DANGERS: Dictionary = {"ruhig": 0.0, "rau": 0.2, "wild": 0.4} ## concept 6.6: extra night budget, elites, pack size
const CURVE_STEP: float = 1.5 ## tiles between the points of a smoothed outline
const SIZE_CLASSES: Dictionary = {"S": Vector2i(96, 160), "M": Vector2i(160, 256), "L": Vector2i(256, 384), "XL": Vector2i(384, 576)}


class Place:
	extends RefCounted
	var id: StringName
	var name: String
	var poly: PackedVector2Array ## continent tiles
	var bbox: Rect2
	var raw: Dictionary = {} ## the place's own entry (mood lean, later: discovery text)


class Landmark:
	extends RefCounted
	var id: StringName
	var kind: StringName
	var name: String
	var pos: Vector2 ## continent tiles


class Zone:
	extends RefCounted
	var id: StringName
	var name: String
	var subtitle: String
	var continent: StringName
	var region: StringName
	var kind: StringName
	var size_class: String
	var origin: Vector2i ## continent tiles
	var size: Vector2i
	var biomes: PackedStringArray
	var mood: StringName
	var night: StringName
	var danger: String
	var unlock_flag: StringName
	var placeholder: bool
	var footprint: PackedVector2Array ## the playable area, continent tiles (smoothed when `curve`)
	var plan: PackedVector2Array ## the authored control points (+ seam points), continent tiles
	var seams: PackedStringArray ## seams spliced into the footprint
	var bbox: Rect2
	var places: Array[Place] = []
	var landmarks: Array[Landmark] = []
	var borders: Array[Dictionary] = []
	var raw: Dictionary = {}

	## Average of the footprint's corners (a stand-in for "the middle" of the zone, e.g. a route's start).
	func center() -> Vector2:
		if footprint.is_empty():
			return bbox.get_center()
		var sum: Vector2 = Vector2.ZERO
		for point: Vector2 in footprint:
			sum += point
		return sum / float(footprint.size())

	func contains(tile: Vector2) -> bool:
		return bbox.has_point(tile) and Geometry2D.is_point_in_polygon(tile, footprint)


class Threshold:
	extends RefCounted
	var id: StringName
	var kind: StringName
	var a: StringName
	var b: StringName
	var line_a: Vector2 ## continent tiles (first point of `line`)
	var line_b: Vector2 ## last point of `line`
	var line: PackedVector2Array ## the whole line, continent tiles (two points, or a piece of a seam)
	var seam: StringName ## the seam it lies on, or &""
	var mask: StringName
	var one_way: bool ## only a -> b
	var open_flag: StringName
	var closed_reason: String

	## The middle of the line, measured along it.
	func midpoint() -> Vector2:
		return Atlas.point_along(line, 0.5) if line.size() > 2 else (line_a + line_b) * 0.5

	func seamless() -> bool:
		return SEAMLESS_KINDS.has(kind)

	func touches(zone_id: StringName) -> bool:
		return a == zone_id or b == zone_id

	## Can it be used leaving `zone_id` (ignores whether the story has opened it)?
	func leads_from(zone_id: StringName) -> bool:
		return a == zone_id or (b == zone_id and not one_way)

	func other(zone_id: StringName) -> StringName:
		return b if zone_id == a else a


class Seam:
	extends RefCounted
	var id: StringName
	var a: StringName
	var b: StringName
	var kind: StringName ## border kind of its closed parts (concept 3.4), default forest_sea
	var pts: PackedVector2Array ## continent tiles, as drawn
	var length: float


class Continent:
	extends RefCounted
	var id: StringName
	var name: String
	var size: Vector2i ## tiles
	var chart: Rect2 ## place on the world chart (0..1)
	var regions: Array[Dictionary] = []
	var seams: Dictionary = {} ## StringName -> Seam
	var landscape: String = "" ## the continent's planned landscape (data/world/... path for `DataRegistry.json`)
	var zones: Array[Zone] = []
	var buckets: Dictionary = {} ## Vector2i -> PackedInt32Array of indices into `zones`


var continents: Dictionary = {} ## StringName -> Continent
var zones: Dictionary = {} ## StringName -> Zone
var thresholds: Dictionary = {} ## StringName -> Threshold
var problems: PackedStringArray = PackedStringArray()
var _by_zone: Dictionary = {} ## StringName -> Array[Threshold]

static var _shared: Atlas = null


## The atlas of the game's data, built once (main thread first).
static func shared() -> Atlas:
	if _shared == null:
		_shared = load_default()
		for problem: String in _shared.problems:
			push_warning("Atlas: " + problem)
	return _shared


## Drop the cached atlas (tools that rewrite data/world/ at run time).
static func forget() -> void:
	_shared = null
	DataRegistry.forget_json()


static func load_default() -> Atlas:
	var atlas_data: Dictionary = DataRegistry.json("world/atlas.json")
	var continent_list: Array[Dictionary] = []
	var zone_list: Array[Dictionary] = []
	var threshold_list: Array[Dictionary] = []
	for entry: Dictionary in _dicts(atlas_data.get("continents", [])):
		var data: Dictionary = DataRegistry.json(String(entry.get("file", "")))
		if data.is_empty():
			continue
		data = data.duplicate()
		data["chart"] = entry.get("chart", [])
		continent_list.append(data)
		var cid: StringName = StringName(String(data.get("id", "")))
		var kept_zones: Dictionary = {}
		for zone_id: Variant in data.get("zones", []) as Array:
			var zone_data: Dictionary = DataRegistry.json("world/zones/%s/zone.json" % String(zone_id))
			if zone_data.is_empty():
				push_warning("Atlas: zone file of %s is missing" % String(zone_id))
				continue
			if StringName(String(zone_data.get("continent", ""))) != cid:
				continue
			kept_zones[StringName(String(zone_data.get("id", zone_id)))] = true
			zone_list.append(zone_data)
		var file: String = String(data.get("thresholds", ""))
		if not file.is_empty():
			for t_data: Dictionary in _dicts(DataRegistry.json(file).get("thresholds", [])):
				if kept_zones.has(StringName(String(t_data.get("a", "")))) or kept_zones.has(StringName(String(t_data.get("b", "")))):
					threshold_list.append(t_data)
	return from_data(continent_list, zone_list, threshold_list)


## Build from plain dictionaries (the shapes of the JSON files; continents already carry their `chart`).
static func from_data(continent_list: Array[Dictionary], zone_list: Array[Dictionary], threshold_list: Array[Dictionary]) -> Atlas:
	var atlas: Atlas = Atlas.new()
	for data: Dictionary in continent_list:
		atlas._add_continent(data)
	for data: Dictionary in zone_list:
		atlas._add_zone(data)
	for c: Continent in atlas.continents.values():
		atlas._index(c)
	atlas._check_overlaps()
	for data: Dictionary in threshold_list:
		atlas._add_threshold(data)
	atlas._check_links()
	return atlas


# --- questions -------------------------------------------------------------------------------------------------------

static func tile_of(pos_px: Vector2) -> Vector2:
	return pos_px / TILE_PX


static func px_of(tile: Vector2) -> Vector2:
	return tile * TILE_PX


func continent(continent_id: StringName) -> Continent:
	return continents.get(continent_id) as Continent


func zone(zone_id: StringName) -> Zone:
	return zones.get(zone_id) as Zone


func zones_of(continent_id: StringName) -> Array[Zone]:
	var found: Continent = continent(continent_id)
	return found.zones if found != null else ([] as Array[Zone])


## The zone whose playable area holds this point (continent tiles), or &"" for borderland, sea, off the map or pockets.
func zone_at_tile(continent_id: StringName, tile: Vector2) -> StringName:
	var found: Continent = continent(continent_id)
	if found == null or not tile.is_finite():
		return &""
	var key: Vector2i = Vector2i(floori(tile.x / BUCKET_TILES), floori(tile.y / BUCKET_TILES))
	var list: Variant = found.buckets.get(key)
	if not (list is PackedInt32Array):
		return &""
	for index: int in list as PackedInt32Array:
		var candidate: Zone = found.zones[index]
		if candidate.contains(tile):
			return candidate.id
	return &""


func zone_at(continent_id: StringName, pos_px: Vector2) -> StringName:
	if PocketSpace.is_pocket(pos_px):
		return &""
	return zone_at_tile(continent_id, tile_of(pos_px))


func is_playable(continent_id: StringName, pos_px: Vector2) -> bool:
	return zone_at(continent_id, pos_px) != &""


## The named place under this point, or &"".
func place_at(continent_id: StringName, pos_px: Vector2) -> StringName:
	var zone_id: StringName = zone_at(continent_id, pos_px)
	if zone_id == &"":
		return &""
	var tile: Vector2 = tile_of(pos_px)
	for place: Place in zone(zone_id).places:
		if place.bbox.has_point(tile) and Geometry2D.is_point_in_polygon(tile, place.poly):
			return place.id
	return &""


func thresholds_of(zone_id: StringName) -> Array[Threshold]:
	var list: Variant = _by_zone.get(zone_id)
	if list is Array:
		return list as Array[Threshold]
	return [] as Array[Threshold]


## Story gate of a threshold: open without an `open` flag, else when the flag is set in `flags` (quest flags).
static func is_threshold_open(threshold: Threshold, flags: Dictionary) -> bool:
	return threshold.open_flag == &"" or bool(flags.get(String(threshold.open_flag), false))


func is_zone_open(zone_id: StringName, flags: Dictionary) -> bool:
	var found: Zone = zone(zone_id)
	if found == null:
		return false
	return found.unlock_flag == &"" or bool(flags.get(String(found.unlock_flag), false))


## Did a step from `from_px` to `to_px` cross the threshold's line?
static func crossed(threshold: Threshold, from_px: Vector2, to_px: Vector2) -> bool:
	var line: PackedVector2Array = threshold.line if threshold.line.size() >= 2 else PackedVector2Array([threshold.line_a, threshold.line_b])
	for i: int in line.size() - 1:
		if Geometry2D.segment_intersects_segment(tile_of(from_px), tile_of(to_px), line[i], line[i + 1]) != null:
			return true
	return false


## The seam of a continent, or null.
func seam(continent_id: StringName, seam_id: StringName) -> Seam:
	var found: Continent = continent(continent_id)
	return found.seams.get(seam_id) as Seam if found != null else null


## The point `share` (0..1) of the way along a polyline.
static func point_along(line: PackedVector2Array, share: float) -> Vector2:
	if line.is_empty():
		return Vector2.ZERO
	var want: float = clampf(share, 0.0, 1.0) * polyline_length(line)
	for i: int in line.size() - 1:
		var part: float = line[i].distance_to(line[i + 1])
		if want <= part or i == line.size() - 2:
			return line[i].lerp(line[i + 1], clampf(want / maxf(part, 0.0001), 0.0, 1.0))
		want -= part
	return line[line.size() - 1]


static func polyline_length(line: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	return total


## The piece of a polyline between the shares `from` and `to` (0..1).
static func sub_polyline(line: PackedVector2Array, from: float, to: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if line.size() < 2:
		return out
	var total: float = maxf(polyline_length(line), 0.0001)
	var lo: float = clampf(minf(from, to), 0.0, 1.0) * total
	var hi: float = clampf(maxf(from, to), 0.0, 1.0) * total
	out.append(point_along(line, lo / total))
	var walked: float = 0.0
	for i: int in line.size() - 1:
		walked += line[i].distance_to(line[i + 1])
		if walked > lo and walked < hi:
			out.append(line[i + 1])
	out.append(point_along(line, hi / total))
	return out


## A closed curve through every control point (uniform Catmull-Rom), about `step` tiles between points.
static func smooth_closed(points: PackedVector2Array, step: float = CURVE_STEP) -> PackedVector2Array:
	var n: int = points.size()
	if n < 3:
		return points
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		_curve_piece(points[(i - 1 + n) % n], points[i], points[(i + 1) % n], points[(i + 2) % n], step, out)
	return out


## The open curve from `points[1]` to `points[size - 2]` (the first and last point only steer the ends).
static func smooth_open(points: PackedVector2Array, step: float = CURVE_STEP) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(1, points.size() - 2):
		_curve_piece(points[i - 1], points[i], points[i + 1], points[i + 2], step, out)
	return out


## Catmull-Rom from p1 to p2 (p1 included, p2 not), appended to `out`.
static func _curve_piece(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, step: float, out: PackedVector2Array) -> void:
	var count: int = maxi(1, ceili(p1.distance_to(p2) / maxf(step, 0.1)))
	for k: int in count:
		var t: float = float(k) / float(count)
		var t2: float = t * t
		var t3: float = t2 * t
		out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))


## The shortest way from one zone to another over open thresholds (in order). Empty when both are the same zone OR there
## is no way: ask `reachable` to tell them apart. `from_tile` (continent tiles) is where the walk starts, default the
## zone's middle. Costs are straight distances between thresholds (good enough to pick the right exit).
func route(from_zone: StringName, to_zone: StringName, flags: Dictionary, from_tile: Vector2 = Vector2.INF) -> Array[Threshold]:
	var none: Array[Threshold] = []
	var start_zone: Zone = zone(from_zone)
	if start_zone == null or zone(to_zone) == null or from_zone == to_zone:
		return none
	var start: Vector2 = from_tile if from_tile.is_finite() else start_zone.center()
	var dist: Dictionary = {} ## threshold id -> cost so far (arrived through it)
	var arrive: Dictionary = {} ## threshold id -> zone it leads into
	var prev: Dictionary = {} ## threshold id -> previous threshold id (or &"")
	var open: Array[StringName] = []
	for threshold: Threshold in thresholds_of(from_zone):
		if threshold.leads_from(from_zone) and is_threshold_open(threshold, flags):
			_relax(threshold, from_zone, start.distance_to(threshold.midpoint()), &"", dist, arrive, prev, open)
	var done: Dictionary = {}
	while not open.is_empty():
		var best: int = 0
		for i: int in range(1, open.size()):
			if float(dist[open[i]]) < float(dist[open[best]]):
				best = i
		var current_id: StringName = open[best]
		open.remove_at(best)
		if done.has(current_id):
			continue
		done[current_id] = true
		var here: StringName = arrive[current_id]
		if here == to_zone:
			var path: Array[Threshold] = []
			var step: StringName = current_id
			while step != &"":
				path.push_front(thresholds[step] as Threshold)
				step = prev[step]
			return path
		var current: Threshold = thresholds[current_id] as Threshold
		for next: Threshold in thresholds_of(here):
			if next == current or done.has(next.id):
				continue
			if not next.leads_from(here) or not is_threshold_open(next, flags):
				continue
			var cost: float = float(dist[current_id]) + current.midpoint().distance_to(next.midpoint())
			_relax(next, here, cost, current_id, dist, arrive, prev, open)
	return none


func reachable(from_zone: StringName, to_zone: StringName, flags: Dictionary) -> bool:
	if from_zone == to_zone:
		return zone(from_zone) != null
	return not route(from_zone, to_zone, flags).is_empty()


## 1.0 + the zone's danger grade (RUHIG 1.0, RAU 1.2, WILD 1.4), for the night budget, elites and pack size.
func danger_scale(zone_id: StringName) -> float:
	var found: Zone = zone(zone_id)
	if found == null:
		return 1.0
	return 1.0 + float(DANGERS.get(found.danger, 0.0))


## The size class whose range holds the longer edge ("" if none).
static func size_class_for(size: Vector2i) -> String:
	var edge: int = maxi(size.x, size.y)
	for key: String in ["S", "M", "L", "XL"]:
		var span: Vector2i = SIZE_CLASSES[key]
		if edge >= span.x and edge <= span.y:
			return key
	return ""


# --- building --------------------------------------------------------------------------------------------------------

static func _dicts(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if raw is Array:
		for item: Variant in raw as Array:
			if item is Dictionary:
				out.append(item as Dictionary)
	return out


static func _vec(raw: Variant, fallback: Vector2 = Vector2.INF) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		var pair: Array = raw as Array
		return Vector2(float(pair[0]), float(pair[1]))
	return fallback


static func _poly(raw: Variant, offset: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if raw is Array:
		for point: Variant in raw as Array:
			var v: Vector2 = _vec(point)
			if v.is_finite():
				out.append(v + offset)
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var box: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for point: Vector2 in poly:
		box = box.expand(point)
	return box


## Tiles from a point to a polygon (0 inside).
static func edge_distance(point: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() >= 3 and Geometry2D.is_point_in_polygon(point, poly):
		return 0.0
	var best: float = INF
	for i: int in poly.size():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, point.distance_to(closest))
	return best


func _add_continent(data: Dictionary) -> void:
	var c: Continent = Continent.new()
	c.id = StringName(String(data.get("id", "")))
	if c.id == &"":
		problems.append("a continent without id")
		return
	if continents.has(c.id):
		problems.append("continent %s twice" % c.id)
		return
	c.name = String(data.get("name", ""))
	var size: Vector2 = _vec(data.get("size"), Vector2.ZERO)
	c.size = Vector2i(int(size.x), int(size.y))
	if c.size.x <= 0 or c.size.y <= 0:
		problems.append("continent %s has no size" % c.id)
	var chart: Variant = data.get("chart", [])
	if chart is Array and (chart as Array).size() >= 4:
		var r: Array = chart as Array
		c.chart = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	c.regions = _dicts(data.get("regions", []))
	c.landscape = String(data.get("landscape", ""))
	for entry: Dictionary in _dicts(data.get("seams", [])):
		var cut: Seam = Seam.new()
		cut.id = StringName(String(entry.get("id", "")))
		cut.a = StringName(String(entry.get("a", "")))
		cut.b = StringName(String(entry.get("b", "")))
		cut.kind = StringName(String(entry.get("kind", "forest_sea")))
		cut.pts = _poly(entry.get("pts", []), Vector2.ZERO)
		cut.length = polyline_length(cut.pts)
		if cut.id == &"" or cut.pts.size() < 2:
			problems.append("continent %s: a seam without id or points" % c.id)
			continue
		if c.seams.has(cut.id):
			problems.append("continent %s: seam %s twice" % [c.id, cut.id])
			continue
		c.seams[cut.id] = cut
	continents[c.id] = c


func _add_zone(data: Dictionary) -> void:
	var z: Zone = Zone.new()
	z.raw = data
	z.id = StringName(String(data.get("id", "")))
	if z.id == &"":
		problems.append("a zone without id")
		return
	if zones.has(z.id):
		problems.append("zone %s twice" % z.id)
		return
	z.name = String(data.get("name", ""))
	z.subtitle = String(data.get("subtitle", ""))
	z.continent = StringName(String(data.get("continent", "")))
	z.region = StringName(String(data.get("region", "")))
	z.kind = StringName(String(data.get("kind", "field")))
	z.size_class = String(data.get("size_class", ""))
	var origin: Vector2 = _vec(data.get("origin"), Vector2.ZERO)
	var size: Vector2 = _vec(data.get("size"), Vector2.ZERO)
	z.origin = Vector2i(int(origin.x), int(origin.y))
	z.size = Vector2i(int(size.x), int(size.y))
	z.biomes = PackedStringArray(data.get("biomes", []) as Array)
	z.mood = StringName(String(data.get("mood", "")))
	z.night = StringName(String(data.get("night", "")))
	z.danger = String(data.get("danger", "ruhig"))
	var unlock: Variant = data.get("unlock", {})
	z.unlock_flag = StringName(String((unlock as Dictionary).get("flag", ""))) if unlock is Dictionary else &""
	z.placeholder = bool(data.get("placeholder", false))
	var shift: Vector2 = Vector2(z.origin)
	z.footprint = _outline(z, data.get("footprint", []), shift, bool(data.get("curve", false)))
	if z.footprint.size() < 3:
		z.footprint = PackedVector2Array([shift, shift + Vector2(size.x, 0.0), shift + size, shift + Vector2(0.0, size.y)])
	z.bbox = _bounds(z.footprint)
	z.borders = _dicts(data.get("borders", []))
	for entry: Dictionary in _dicts(data.get("places", [])):
		var place: Place = Place.new()
		place.id = StringName(String(entry.get("id", "")))
		place.name = String(entry.get("name", ""))
		place.raw = entry
		place.poly = _poly(entry.get("poly", []), shift)
		place.bbox = _bounds(place.poly)
		if place.poly.size() < 3:
			problems.append("place %s of %s has no shape" % [place.id, z.id])
			continue
		if not Geometry2D.is_point_in_polygon(place.bbox.get_center(), z.footprint):
			problems.append("place %s lies outside zone %s" % [place.id, z.id])
		z.places.append(place)
	for entry: Dictionary in _dicts(data.get("landmarks", [])):
		var mark: Landmark = Landmark.new()
		mark.id = StringName(String(entry.get("id", "")))
		mark.kind = StringName(String(entry.get("kind", "")))
		mark.name = String(entry.get("name", ""))
		mark.pos = _vec(entry.get("pos"), Vector2.ZERO) + shift
		if not Geometry2D.is_point_in_polygon(mark.pos, z.footprint):
			problems.append("landmark %s lies outside zone %s" % [mark.id, z.id])
		z.landmarks.append(mark)
	_check_zone(z)
	zones[z.id] = z
	_by_zone[z.id] = [] as Array[Threshold]
	var home: Continent = continent(z.continent)
	if home != null:
		home.zones.append(z)


## The zone's playable outline: control points (+ origin) and spliced seams; `curve` smooths the control points.
func _outline(z: Zone, raw: Variant, shift: Vector2, curve: bool) -> PackedVector2Array:
	var runs: Array[Dictionary] = [] ## {seam: bool, pts: PackedVector2Array}
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Dictionary:
				var seam_id: StringName = StringName(String((entry as Dictionary).get("seam", "")))
				var cut: Seam = seam(z.continent, seam_id)
				if cut == null:
					problems.append("zone %s: unknown seam '%s'" % [z.id, seam_id])
					continue
				if cut.a != z.id and cut.b != z.id:
					problems.append("zone %s uses seam %s of %s / %s" % [z.id, seam_id, cut.a, cut.b])
				z.seams.append(String(seam_id))
				runs.append({"seam": true, "pts": cut.pts})
			else:
				var v: Vector2 = _vec(entry)
				if not v.is_finite():
					continue
				if runs.is_empty() or bool(runs[runs.size() - 1]["seam"]):
					runs.append({"seam": false, "pts": PackedVector2Array()})
				var own: PackedVector2Array = runs[runs.size() - 1]["pts"] as PackedVector2Array
				own.append(v + shift)
				runs[runs.size() - 1]["pts"] = own
	# Turn every seam so it continues from the point before it.
	for i: int in runs.size():
		if not bool(runs[i]["seam"]):
			continue
		var pts: PackedVector2Array = runs[i]["pts"] as PackedVector2Array
		var before: Vector2 = Vector2.INF
		if i > 0:
			var prev: PackedVector2Array = runs[i - 1]["pts"] as PackedVector2Array
			before = prev[prev.size() - 1]
		elif runs.size() > 1:
			var last: PackedVector2Array = runs[runs.size() - 1]["pts"] as PackedVector2Array
			before = last[last.size() - 1]
		if before.is_finite() and before.distance_to(pts[pts.size() - 1]) < before.distance_to(pts[0]):
			var flipped: PackedVector2Array = pts.duplicate()
			flipped.reverse()
			runs[i]["pts"] = flipped
	z.plan = PackedVector2Array()
	for run: Dictionary in runs:
		z.plan.append_array(run["pts"] as PackedVector2Array)
	if not curve:
		return z.plan
	var has_seam: bool = false
	for run: Dictionary in runs:
		has_seam = has_seam or bool(run["seam"])
	if not has_seam:
		return smooth_closed(z.plan)
	# Smooth each run of control points between the seams' ends; seams stay exactly as drawn.
	var out: PackedVector2Array = PackedVector2Array()
	var count: int = runs.size()
	for i: int in count:
		var pts: PackedVector2Array = runs[i]["pts"] as PackedVector2Array
		if bool(runs[i]["seam"]):
			out.append_array(pts)
			continue
		var prev_pts: PackedVector2Array = runs[(i - 1 + count) % count]["pts"] as PackedVector2Array
		var next_pts: PackedVector2Array = runs[(i + 1) % count]["pts"] as PackedVector2Array
		var chain: PackedVector2Array = PackedVector2Array()
		chain.append(prev_pts[maxi(0, prev_pts.size() - 2)])
		chain.append(prev_pts[prev_pts.size() - 1])
		chain.append_array(pts)
		chain.append(next_pts[0])
		chain.append(next_pts[mini(1, next_pts.size() - 1)])
		var curve_pts: PackedVector2Array = smooth_open(chain)
		if not curve_pts.is_empty():
			curve_pts.remove_at(0) ## the previous seam's last point is already in
		out.append_array(curve_pts)
	return out


func _check_zone(z: Zone) -> void:
	var home: Continent = continent(z.continent)
	if home == null:
		problems.append("zone %s: unknown continent '%s'" % [z.id, z.continent])
	elif not Rect2(Vector2.ZERO, Vector2(home.size)).encloses(z.bbox):
		problems.append("zone %s reaches outside continent %s" % [z.id, z.continent])
	if not ZONE_KINDS.has(z.kind):
		problems.append("zone %s: unknown kind '%s'" % [z.id, z.kind])
	if not DANGERS.has(z.danger):
		problems.append("zone %s: unknown danger '%s'" % [z.id, z.danger])
	var fitted: String = size_class_for(z.size)
	if fitted.is_empty() or fitted != z.size_class:
		problems.append("zone %s: size %s does not fit class '%s' (fits '%s')" % [z.id, z.size, z.size_class, fitted])
	var frame: Rect2 = Rect2(Vector2(z.origin), Vector2(z.size)).grow(0.01)
	if not frame.encloses(z.bbox):
		problems.append("zone %s: footprint is larger than its size %s" % [z.id, z.size])


func _index(c: Continent) -> void:
	for i: int in c.zones.size():
		var box: Rect2 = c.zones[i].bbox.grow(1.0)
		var lo: Vector2i = Vector2i(floori(box.position.x / BUCKET_TILES), floori(box.position.y / BUCKET_TILES))
		var hi: Vector2i = Vector2i(floori(box.end.x / BUCKET_TILES), floori(box.end.y / BUCKET_TILES))
		for by: int in range(lo.y, hi.y + 1):
			for bx: int in range(lo.x, hi.x + 1):
				var key: Vector2i = Vector2i(bx, by)
				var list: PackedInt32Array = c.buckets.get(key, PackedInt32Array()) as PackedInt32Array
				list.append(i)
				c.buckets[key] = list


func _check_overlaps() -> void:
	for c: Continent in continents.values():
		for i: int in c.zones.size():
			for j: int in range(i + 1, c.zones.size()):
				var first: Zone = c.zones[i]
				var second: Zone = c.zones[j]
				if not first.bbox.intersects(second.bbox):
					continue
				var area: float = 0.0
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(first.footprint, second.footprint):
					area += absf(_area(piece))
				if area > 0.5:
					problems.append("zones %s and %s overlap (%.1f tiles)" % [first.id, second.id, area])


static func _area(poly: PackedVector2Array) -> float:
	var sum: float = 0.0
	for i: int in poly.size():
		sum += poly[i].cross(poly[(i + 1) % poly.size()])
	return sum * 0.5


func _add_threshold(data: Dictionary) -> void:
	var t: Threshold = Threshold.new()
	t.id = StringName(String(data.get("id", "")))
	if t.id == &"":
		problems.append("a threshold without id")
		return
	if thresholds.has(t.id):
		problems.append("threshold %s twice" % t.id)
		return
	t.kind = StringName(String(data.get("kind", "path")))
	t.a = StringName(String(data.get("a", "")))
	t.b = StringName(String(data.get("b", "")))
	var line: Variant = data.get("line", [])
	if line is Array and (line as Array).size() >= 2:
		t.line = _poly(line, Vector2.ZERO)
	t.seam = StringName(String(data.get("seam", "")))
	t.mask = StringName(String(data.get("mask", "")))
	t.one_way = bool(data.get("one_way", false))
	var gate: Variant = data.get("open", {})
	t.open_flag = StringName(String((gate as Dictionary).get("flag", ""))) if gate is Dictionary else &""
	t.closed_reason = String(data.get("closed_reason", ""))
	var za: Zone = zone(t.a)
	var zb: Zone = zone(t.b)
	if za == null or zb == null:
		problems.append("threshold %s joins unknown zones %s / %s" % [t.id, t.a, t.b])
		return
	if t.seam != &"":
		var cut: Seam = seam(za.continent, t.seam)
		if cut == null:
			problems.append("threshold %s: unknown seam '%s'" % [t.id, t.seam])
		else:
			if not ((cut.a == t.a and cut.b == t.b) or (cut.a == t.b and cut.b == t.a)):
				problems.append("threshold %s lies on seam %s of other zones" % [t.id, t.seam])
			var span: Vector2 = _vec(data.get("span"), Vector2(0.0, 1.0))
			t.line = sub_polyline(cut.pts, span.x, span.y)
	if t.line.size() >= 2:
		t.line_a = t.line[0]
		t.line_b = t.line[t.line.size() - 1]
	if t.a == t.b:
		problems.append("threshold %s joins zone %s with itself" % [t.id, t.a])
		return
	if not SEAMLESS_KINDS.has(t.kind) and not HARD_KINDS.has(t.kind):
		problems.append("threshold %s: unknown kind '%s'" % [t.id, t.kind])
	if t.kind != &"ship" and za.continent != zb.continent:
		problems.append("threshold %s crosses continents but is no ship" % t.id)
	if t.seamless():
		if t.line_a.distance_to(t.line_b) < 1.0:
			problems.append("threshold %s has no line" % t.id)
		for side: Zone in [za, zb]:
			if edge_distance(t.midpoint(), side.footprint) > LINE_REACH:
				problems.append("threshold %s: its line is not at the edge of %s" % [t.id, side.id])
	thresholds[t.id] = t
	(_by_zone[t.a] as Array[Threshold]).append(t)
	(_by_zone[t.b] as Array[Threshold]).append(t)


func _check_links() -> void:
	for c: Continent in continents.values():
		if c.zones.size() < 2:
			continue
		for z: Zone in c.zones:
			if thresholds_of(z.id).is_empty():
				problems.append("zone %s has no threshold" % z.id)


static func _relax(threshold: Threshold, from_zone: StringName, cost: float, before: StringName, dist: Dictionary, arrive: Dictionary, prev: Dictionary, open: Array[StringName]) -> void:
	if dist.has(threshold.id) and float(dist[threshold.id]) <= cost:
		return
	dist[threshold.id] = cost
	arrive[threshold.id] = threshold.other(from_zone)
	prev[threshold.id] = before
	open.append(threshold.id)
