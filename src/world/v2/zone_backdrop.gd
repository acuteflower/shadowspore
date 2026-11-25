class_name ZoneBackdrop
extends Sprite2D
## The distant view beyond one zone's edge (docs/v2_zonenwelt_atlas_konzept.md 3.4 "Waldmeer", 13.3): a sea of crowns
## (`zone_backdrop.gdshader`) that starts a few tiles past the footprint, under the outer belt trees, and hazes into the
## dark further out. Its texture is the mask, one texel per tile: R = coverage, G = depth.
##
## Built off the tree (`build`, worker-safe): a chamfer distance transform from every zone's footprint gives each tile
## outside the zones its distance and its nearest zone; a zone covers only the tiles nearest to it, so two neighbours
## never paint the same sky of crowns twice. `commit()` (main thread, attach) uploads the texture.

const SHADER: Shader = preload("res://assets/shaders/zone_backdrop.gdshader")
const OCEAN_SHADER: Shader = preload("res://assets/shaders/ocean_horizon.gdshader")
const MARGIN_TILES: float = 26.0 ## how far out the backdrop reaches
const OCEAN_EXTEND_TILES: float = 160.0 ## endless sea extent far past VistaPoint 0.56x zoom
const START: float = 1.6 ## tiles beyond the footprint where the canopy may begin
const FULL: float = 4.2 ## tiles beyond the footprint where it is closed
const HAZE_FROM: float = 4.0
const HAZE_SPAN: float = 20.0

const KIND_MEADOW: int = 0
const KIND_FOREST: int = 1
const KIND_CLIFF: int = 2
const KIND_WATER: int = 3

var _image: Image
var area: Rect2 ## tiles
var _has_water_border: bool = false
var _ocean_rect_px: Rect2 = Rect2()
var _ocean_clip_nw_px: Vector2 = Vector2(-1e9, -1e9)
var _ocean_clip_se_px: Vector2 = Vector2(1e9, 1e9)
var _ocean_center_px: Vector2 = Vector2.ZERO
var _ocean_node: ColorRect = null


static func build(atlas: Atlas, zone: Atlas.Zone) -> ZoneBackdrop:
	var view: ZoneBackdrop = ZoneBackdrop.new()
	view.name = "Backdrop"
	view.area = Rect2(zone.bbox.position.floor(), zone.bbox.size.ceil()).grow(MARGIN_TILES)
	view._image = _mask(atlas, zone, view.area)
	view._configure_ocean_horizon(zone)
	view.centered = false
	view.position = Atlas.px_of(view.area.position)
	view.scale = Vector2(Atlas.TILE_PX, Atlas.TILE_PX)
	view.z_as_relative = false
	view.z_index = -7
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("rect_px", Vector4(view.position.x, view.position.y, view.area.size.x * Atlas.TILE_PX, view.area.size.y * Atlas.TILE_PX))
	view.material = mat
	return view


func _configure_ocean_horizon(zone: Atlas.Zone) -> void:
	_has_water_border = false
	var water_from: float = 0.0
	var water_to: float = 0.0
	for b: Dictionary in zone.borders:
		if String(b.get("kind", "")) == "water":
			_has_water_border = true
			water_from = float(b.get("from", 0.0))
			water_to = float(b.get("to", 1.0))
			break
	if not _has_water_border:
		return
	var z_px: Rect2 = Rect2(Atlas.px_of(zone.bbox.position), Atlas.px_of(zone.bbox.size))
	var ext: float = OCEAN_EXTEND_TILES * Atlas.TILE_PX
	_ocean_rect_px = Rect2(z_px.position - Vector2(ext, ext * 0.45), z_px.size + Vector2(ext * 1.65, ext * 1.55))
	_ocean_center_px = z_px.get_center()
	# Determine NW & SE endpoints of the water border for clean inland clipping
	if zone.footprint.size() >= 3:
		var ring: PackedVector2Array = zone.footprint.duplicate()
		ring.append(zone.footprint[0])
		var p_a: Vector2 = Atlas.px_of(Atlas.point_along(ring, water_from))
		var p_b: Vector2 = Atlas.px_of(Atlas.point_along(ring, water_to))
		_ocean_clip_nw_px = p_b if p_b.y < p_a.y else p_a
		_ocean_clip_se_px = p_a if p_b.y < p_a.y else p_b


## Main thread: hand the mask to the GPU and mount the endless ocean horizon behind water borders.
func commit() -> void:
	if _image != null:
		texture = ImageTexture.create_from_image(_image)
		(material as ShaderMaterial).set_shader_parameter("mask_tex", texture)
	if _has_water_border and _ocean_node == null:
		var ocean: ColorRect = ColorRect.new()
		ocean.name = "OceanHorizon"
		ocean.z_as_relative = false
		ocean.z_index = -11
		ocean.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Child of Sprite2D scaled by TILE_PX -> convert world rect to local Sprite2D coordinates!
		ocean.position = (_ocean_rect_px.position - position) / Atlas.TILE_PX
		ocean.size = _ocean_rect_px.size / Atlas.TILE_PX
		ocean.color = Color.WHITE
		var omat: ShaderMaterial = ShaderMaterial.new()
		omat.shader = OCEAN_SHADER
		omat.set_shader_parameter("clip_enabled", 1.0)
		omat.set_shader_parameter("clip_nw_px", _ocean_clip_nw_px)
		omat.set_shader_parameter("clip_se_px", _ocean_clip_se_px)
		omat.set_shader_parameter("sea_center_px", _ocean_center_px)
		ocean.material = omat
		add_child(ocean)
		_ocean_node = ocean


## Coverage (R) and depth (G) at a tile, for tests.
func sample(tile: Vector2) -> Vector2:
	if _image == null:
		return Vector2.ZERO
	var p: Vector2i = Vector2i((tile - area.position).floor())
	if p.x < 0 or p.y < 0 or p.x >= _image.get_width() or p.y >= _image.get_height():
		return Vector2.ZERO
	var c: Color = _image.get_pixelv(p)
	return Vector2(c.r, c.g)


static func _border_kind_id(name_str: String) -> int:
	match name_str:
		"forest_sea":
			return KIND_FOREST
		"cliff":
			return KIND_CLIFF
		"water":
			return KIND_WATER
		"meadow", "none", "open":
			return KIND_MEADOW
		_:
			return KIND_FOREST


static func _kind_for_share(zone: Atlas.Zone, share: float) -> int:
	if zone.borders.is_empty():
		return KIND_FOREST
	if zone.borders.size() == 1 and not zone.borders[0].has("from") and not zone.borders[0].has("to"):
		return _border_kind_id(String(zone.borders[0].get("kind", "forest_sea")))
	for b: Dictionary in zone.borders:
		var f0: float = float(b.get("from", 0.0))
		var f1: float = float(b.get("to", 1.0))
		if share >= f0 - 0.0005 and share <= f1 + 0.0005:
			return _border_kind_id(String(b.get("kind", "forest_sea")))
	return KIND_FOREST


static func _mask(atlas: Atlas, zone: Atlas.Zone, area: Rect2) -> Image:
	var w: int = int(area.size.x)
	var h: int = int(area.size.y)
	var dist: PackedFloat32Array = PackedFloat32Array()
	var label: PackedInt32Array = PackedInt32Array()
	var kind_map: PackedByteArray = PackedByteArray()
	dist.resize(w * h)
	label.resize(w * h)
	kind_map.resize(w * h)
	kind_map.fill(KIND_FOREST)
	var ids: Dictionary = {} ## zone id -> label
	var ignore_placeholders: bool = zone.continent != &"lab"
	for z: Atlas.Zone in atlas.zones_of(zone.continent):
		if ignore_placeholders and z != zone and z.placeholder:
			continue
		ids[z.id] = ids.size()
	var own: int = int(ids.get(zone.id, -2))
	var default_kind: int = KIND_FOREST
	if not zone.borders.is_empty() and zone.borders.size() == 1 and not zone.borders[0].has("from"):
		default_kind = _border_kind_id(String(zone.borders[0].get("kind", "forest_sea")))
	dist.fill(INF)
	label.fill(-1)
	kind_map.fill(default_kind)
	# Scanline-rasterize only the non-placeholder zones intersecting `area` (~2 ms vs 250k `zone_at_tile` calls!)
	var xs: Array[float] = []
	for z: Atlas.Zone in atlas.zones_of(zone.continent):
		if not ids.has(z.id) or not z.bbox.intersects(area) or z.footprint.size() < 3:
			continue
		var zid_lbl: int = int(ids[z.id])
		var poly: PackedVector2Array = z.footprint
		var pn: int = poly.size()
		var y0: int = clampi(floori(z.bbox.position.y - area.position.y), 0, h - 1)
		var y1: int = clampi(ceili(z.bbox.end.y - area.position.y), 0, h - 1)
		for y: int in range(y0, y1 + 1):
			var wy: float = area.position.y + float(y) + 0.5
			xs.clear()
			for i: int in pn:
				var p1: Vector2 = poly[i]
				var p2: Vector2 = poly[(i + 1) % pn]
				if (p1.y > wy) != (p2.y > wy):
					xs.append((p2.x - p1.x) * (wy - p1.y) / (p2.y - p1.y) + p1.x)
			if xs.is_empty():
				continue
			xs.sort()
			var row_off: int = y * w
			var k: int = 0
			while k + 1 < xs.size():
				var x0: int = clampi(ceili(xs[k] - area.position.x - 0.5), 0, w - 1)
				var x1: int = clampi(floori(xs[k + 1] - area.position.x - 0.5), 0, w - 1)
				for x: int in range(x0, x1 + 1):
					var idx: int = row_off + x
					dist[idx] = 0.0
					label[idx] = zid_lbl
				k += 2

	# Stamp exact border-kind seeds along our zone's perimeter when it has multi-section borders!
	var has_multi: bool = zone.borders.size() > 1 or (zone.borders.size() == 1 and (zone.borders[0].has("from") or zone.borders[0].has("to")))
	if has_multi and zone.footprint.size() >= 3:
		var ring: PackedVector2Array = zone.footprint.duplicate()
		ring.append(zone.footprint[0])
		var total_len: float = maxf(Atlas.polyline_length(ring), 1.0)
		var accum: float = 0.0
		for seg: int in ring.size() - 1:
			var a: Vector2 = ring[seg]
			var b: Vector2 = ring[seg + 1]
			var slen: float = a.distance_to(b)
			var steps: int = maxi(1, ceili(slen * 2.0))
			for s: int in steps + 1:
				var t: float = float(s) / float(steps)
				var share: float = (accum + slen * t) / total_len
				var k_id: int = _kind_for_share(zone, share)
				var pt: Vector2 = a.lerp(b, t)
				var gx: int = floori(pt.x - area.position.x)
				var gy: int = floori(pt.y - area.position.y)
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var nx: int = gx + dx
						var ny: int = gy + dy
						if nx >= 0 and ny >= 0 and nx < w and ny < h:
							var nidx: int = ny * w + nx
							if label[nidx] == own:
								kind_map[nidx] = k_id
			accum += slen

	# Chamfer distance with label & border-kind propagation: forward, then backward (inlined, skips interior 0-dist!).
	var diag: float = 1.4142
	for y: int in h:
		var row: int = y * w
		var prev_row: int = row - w
		for x: int in w:
			var idx: int = row + x
			var d_cur: float = dist[idx]
			if d_cur == 0.0:
				continue
			if x > 0:
				var v0: float = dist[idx - 1] + 1.0
				if v0 < d_cur:
					d_cur = v0
					label[idx] = label[idx - 1]
					kind_map[idx] = kind_map[idx - 1]
			if y > 0:
				var up: int = prev_row + x
				var v1: float = dist[up] + 1.0
				if v1 < d_cur:
					d_cur = v1
					label[idx] = label[up]
					kind_map[idx] = kind_map[up]
				if x > 0:
					var v2: float = dist[up - 1] + diag
					if v2 < d_cur:
						d_cur = v2
						label[idx] = label[up - 1]
						kind_map[idx] = kind_map[up - 1]
				if x + 1 < w:
					var v3: float = dist[up + 1] + diag
					if v3 < d_cur:
						d_cur = v3
						label[idx] = label[up + 1]
						kind_map[idx] = kind_map[up + 1]
			dist[idx] = d_cur
	for y: int in range(h - 1, -1, -1):
		var row: int = y * w
		var next_row: int = row + w
		for x: int in range(w - 1, -1, -1):
			var idx: int = row + x
			var d_cur: float = dist[idx]
			if d_cur == 0.0:
				continue
			if x + 1 < w:
				var v0: float = dist[idx + 1] + 1.0
				if v0 < d_cur:
					d_cur = v0
					label[idx] = label[idx + 1]
					kind_map[idx] = kind_map[idx + 1]
			if y + 1 < h:
				var dn: int = next_row + x
				var v1: float = dist[dn] + 1.0
				if v1 < d_cur:
					d_cur = v1
					label[idx] = label[dn]
					kind_map[idx] = kind_map[dn]
				if x + 1 < w:
					var v2: float = dist[dn + 1] + diag
					if v2 < d_cur:
						d_cur = v2
						label[idx] = label[dn + 1]
						kind_map[idx] = kind_map[dn + 1]
				if x > 0:
					var v3: float = dist[dn - 1] + diag
					if v3 < d_cur:
						d_cur = v3
						label[idx] = label[dn - 1]
						kind_map[idx] = kind_map[dn - 1]
			dist[idx] = d_cur
	var data: PackedByteArray = PackedByteArray()
	data.resize(w * h * 4)
	for i: int in w * h:
		var d: float = dist[i]
		if label[i] != own or d <= 0.0:
			continue
		var k_id: int = int(kind_map[i])
		var bi: int = i * 4
		if k_id == KIND_FOREST:
			data[bi] = int(round(smoothstep(START, FULL, d) * 255.0))
			data[bi + 1] = int(round(clampf((d - HAZE_FROM) / HAZE_SPAN, 0.0, 1.0) * 255.0))
			data[bi + 2] = 0
			data[bi + 3] = 255
		elif k_id == KIND_CLIFF:
			data[bi] = 0
			data[bi + 1] = int(round(clampf((d - 2.0) / 18.0, 0.0, 1.0) * 255.0))
			data[bi + 2] = int(round(smoothstep(0.3, 3.0, d) * 255.0))
			data[bi + 3] = 255
		elif k_id == KIND_WATER:
			data[bi] = 0
			data[bi + 1] = 0
			data[bi + 2] = 0
			data[bi + 3] = int(round(smoothstep(0.0, 2.0, d) * 255.0))
		else:
			# Open meadow border towards a placeholder neighbour: close smoothly behind the border belt trees into canopy sea.
			data[bi] = int(round(smoothstep(START, FULL, d) * 255.0))
			data[bi + 1] = int(round(clampf((d - HAZE_FROM) / HAZE_SPAN, 0.0, 1.0) * 255.0))
			data[bi + 2] = 0
			data[bi + 3] = 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


static func _relax(dist: PackedFloat32Array, label: PackedInt32Array, kind_map: PackedByteArray, w: int, h: int, x: int, y: int, nx: int, ny: int, cost: float) -> void:
	if nx < 0 or ny < 0 or nx >= w or ny >= h:
		return
	var nidx: int = ny * w + nx
	var via: float = dist[nidx] + cost
	var idx: int = y * w + x
	if via < dist[idx]:
		dist[idx] = via
		label[idx] = label[nidx]
		kind_map[idx] = kind_map[nidx]
