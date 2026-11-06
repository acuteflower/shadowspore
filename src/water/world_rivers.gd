class_name WorldRivers
extends Node2D
## Immutable shared drainage bake. Graphics stream with terrain; small query fields
## remain cached for prop placement and navigation, independent of load order.
var _data: Dictionary
var _spec: Dictionary
var _queries: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _falls: Array[Sprite2D] = []
var _springs: Array[Sprite2D] = []
var _spring_glows: Array[Sprite2D] = []
var _clock: float = 0.0
var fauna: RiverFauna
const LAKE_SDF: Texture2D = preload("res://assets/world/lakes_sdf.png")
var _lake_bytes: PackedByteArray

func _ready() -> void:
	_data = DataRegistry.table("rivers_baked").duplicate(true)
	var lakes: Dictionary = DataRegistry.table("lakes_baked")
	(_data["chunks"] as Dictionary).merge(lakes.get("chunks", {}) as Dictionary, true)
	_data["lakes"] = lakes.get("lakes", [])
	var lake_image: Image = LAKE_SDF.get_image()
	lake_image.convert(Image.FORMAT_L8)
	_lake_bytes = lake_image.get_data()
	_spec = DataRegistry.table("rivers")
	y_sort_enabled = true
	fauna = load("res://src/water/river_fauna.tscn").instantiate() as RiverFauna
	add_child(fauna)
	Terrain.patches.append(self)
	tree_exiting.connect(func() -> void: Terrain.patches.erase(self))

func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

## These enclosed basins belong to water, never to the exterior abyss.
func lake_at(point: Vector2) -> bool:
	var tile: Vector2i = Vector2i((point / 16.0).floor())
	return tile.x >= 0 and tile.y >= 0 and tile.x < RegionMap.WORLD_TILES and tile.y < RegionMap.WORLD_TILES and _lake_bytes[tile.y * RegionMap.WORLD_TILES + tile.x] < 128

func _query(cell: Vector2i) -> Image:
	var key: String = _key(cell)
	if not (_data.get("chunks", {}) as Dictionary).has(key): return null
	if not _queries.has(cell):
		var path: String = String((_data["chunks"][key] as Dictionary)["query"])
		_queries[cell] = (load(path) as Texture2D).get_image()
	return _queries[cell] as Image

func field_at(point: Vector2) -> Vector2:
	var cell: Vector2i = Vector2i((point / 512.0).floor())
	var image: Image = _query(cell)
	if image == null: return Vector2(INF, 0.0)
	var local: Vector2i = Vector2i(((point - Vector2(cell) * 512.0) / 4.0).floor())
	var pixel: Color = image.get_pixel(clampi(local.x, 0, 127), clampi(local.y, 0, 127))
	return Vector2(pixel.r8 - 128.0, pixel.g)

func clear_for_prop(point: Vector2, radius: float) -> bool:
	# Distance fields are conservative minima over each 4px cell. Sampling the
	# enclosing neighbourhood also covers large props that straddle chunk edges.
	var reach: float = radius + float(_spec["prop_margin"])
	var lo: Vector2i = Vector2i(((point - Vector2.ONE * reach * 1.5) / 512.0).floor())
	var hi: Vector2i = Vector2i(((point + Vector2.ONE * reach * 1.5) / 512.0).floor())
	var nearby: bool = false
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			if (_data["chunks"] as Dictionary).has(_key(Vector2i(x, y))): nearby = true
	if not nearby: return true
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var offset: Vector2 = Vector2(dx, dy) * reach * 0.7
			if field_at(point + offset).x <= reach * 0.8: return false
	return true

func is_deep(point: Vector2) -> bool:
	var field: Vector2 = field_at(point)
	return field.x <= 0.0 and field.y > float(_spec["deep_threshold"])

func surface_at(point: Vector2) -> String:
	var field: Vector2 = field_at(point)
	if field.x > 0.0: return ""
	return "deep_water" if field.y > float(_spec["deep_threshold"]) else "shallow_water"

func wade_data(point: Vector2, base: Dictionary) -> Dictionary:
	var field: Vector2 = field_at(point)
	if field.x > 0.0: return base
	var settings: Dictionary = DataRegistry.table("river_life")
	var amount: float = clampf(field.y / float(_spec["deep_threshold"]), 0.0, 1.0)
	var result: Dictionary = base.duplicate(true)
	result["submerge"] = lerpf(float(settings["depth_min"]), float(settings["depth_max"]), amount)
	result["speed"] = lerpf(float(settings["wade_speed_max"]), float(settings["wade_speed_min"]), amount)
	return result

func attach_chunk(parent: Node2D, cell: Vector2i) -> void:
	var key: String = _key(cell)
	if not (_data["chunks"] as Dictionary).has(key): return
	var record: Dictionary = _data["chunks"][key]
	fauna.chunk_loaded(cell)
	parent.tree_exiting.connect(func() -> void:
		if is_instance_valid(fauna): fauna.chunk_unloaded(cell))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "RiverSurface"
	sprite.centered = false
	sprite.position = Vector2(cell) * 512.0
	sprite.z_index = -7
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = load(String(record["field"])) as Texture2D
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = load("res://assets/shaders/river_water.gdshader") as Shader
	shader_material.set_shader_parameter("bank_map", load(String(record["bank"])))
	shader_material.set_shader_parameter("bank_width", float(_spec["bank_width"]))
	shader_material.set_shader_parameter("bank_inner", true)
	shader_material.set_shader_parameter("water_detail", load("res://assets/water/water_detail.png"))
	shader_material.set_shader_parameter("bank_material", load("res://assets/water/bank_material.png"))
	shader_material.set_shader_parameter("world_origin", sprite.position)
	shader_material.set_shader_parameter("water_time", _clock)
	sprite.material = shader_material
	_materials.append(shader_material)
	sprite.tree_exiting.connect(func() -> void: _materials.erase(shader_material))
	parent.add_child(sprite)
	parent.y_sort_enabled = true
	var details: RiverDetails = RiverDetails.new()
	details.name = "RiverDetails"
	details.y_sort_enabled = true
	parent.add_child(details)
	details.setup(self, cell, sprite.texture.get_image())
	# Night glow pass: unlit, additive, same field; strength follows the day cycle (RiverDetails.set_night).
	var night_glow: Sprite2D = Sprite2D.new()
	night_glow.name = "RiverGlow"
	night_glow.centered = false
	night_glow.position = sprite.position
	night_glow.z_index = -6
	night_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	night_glow.texture = sprite.texture
	var glow_material: ShaderMaterial = ShaderMaterial.new()
	glow_material.shader = load("res://assets/shaders/river_glow.gdshader") as Shader
	glow_material.set_shader_parameter("bank_map", load(String(record["bank"])))
	glow_material.set_shader_parameter("bank_width", float(_spec["bank_width"]))
	glow_material.set_shader_parameter("world_origin", sprite.position)
	glow_material.set_shader_parameter("water_time", _clock)
	glow_material.set_shader_parameter("night", TimeManager.night_amount())
	night_glow.material = glow_material
	_materials.append(glow_material)
	night_glow.tree_exiting.connect(func() -> void: _materials.erase(glow_material))
	parent.add_child(night_glow)
	details.glow_materials.append(glow_material)
	var anchors: PackedVector4Array = []
	for value: Array in details.disturbances:
		anchors.append(Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3])))

	# Waterfalls in this chunk
	var falls_data: Array = record.get("waterfalls", [])
	var fall_links: PackedVector4Array = []
	for fall_spec_val: Variant in falls_data:
		var fall_spec: Array = fall_spec_val as Array
		var wx: float = float(fall_spec[0])
		var wy: float = float(fall_spec[1])
		var height: float = float(fall_spec[2])
		var width: float = float(fall_spec[3])
		var ledge: Sprite2D = Sprite2D.new()
		ledge.texture = load("res://assets/water/waterfall_rock.png") as Texture2D
		ledge.centered = false
		ledge.position = Vector2(wx - 24.0, wy)
		ledge.z_index = -5
		parent.add_child(ledge)
		var fall: Sprite2D = Sprite2D.new()
		fall.texture = load("res://assets/water/waterfall.png") as Texture2D
		fall.hframes = 8
		fall.centered = false
		fall.position = Vector2(wx - 24.0, wy)
		fall.z_index = -4
		parent.add_child(fall)
		_falls.append(fall)
		fall.tree_exiting.connect(func() -> void: _falls.erase(fall))
		if fall_links.size() < 4:
			fall_links.append(Vector4(wx, wy, height, width))
		if anchors.size() < 8:
			anchors.append(Vector4(wx, wy + 41.0, 34.0, 1.0))
	var fall_count: int = fall_links.size()
	while fall_links.size() < 4: fall_links.append(Vector4.ZERO)
	shader_material.set_shader_parameter("waterfall_links", fall_links)
	shader_material.set_shader_parameter("fall_link_count", fall_count)

	# Cliff springs (Felswand-Quelltöpfe) in this chunk
	var springs_data: Array = record.get("cliff_springs", [])
	for spring_spec_val: Variant in springs_data:
		var spring_spec: Array = spring_spec_val as Array
		var sx: float = float(spring_spec[0])
		var sy: float = float(spring_spec[1])
		var style: int = int(spring_spec[2])
		var spring: Sprite2D = Sprite2D.new()
		spring.texture = load("res://assets/water/cliff_spring.png") as Texture2D
		spring.hframes = 4
		spring.vframes = 5
		spring.frame_coords = Vector2i(0, clampi(style, 0, 4))
		spring.centered = false
		spring.position = Vector2(sx - 24.0, sy - 18.0)
		spring.z_index = -5
		parent.add_child(spring)
		_springs.append(spring)
		spring.tree_exiting.connect(func() -> void: _springs.erase(spring))
		if style in [3, 4]:
			var glow: Sprite2D = Sprite2D.new()
			glow.texture = load("res://assets/water/cliff_spring_glow.png") as Texture2D
			glow.hframes = 4
			glow.vframes = 5
			glow.frame_coords = Vector2i(0, style)
			glow.centered = false
			glow.position = spring.position
			glow.z_index = -4
			var unlit: CanvasItemMaterial = CanvasItemMaterial.new()
			unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			glow.material = unlit
			parent.add_child(glow)
			_spring_glows.append(glow)
			glow.tree_exiting.connect(func() -> void: _spring_glows.erase(glow))
		if anchors.size() < 8:
			anchors.append(Vector4(sx, sy + 10.0, 18.0, 0.75))

	var count: int = anchors.size()
	while anchors.size() < 8: anchors.append(Vector4.ZERO)
	shader_material.set_shader_parameter("disturbances", anchors)
	shader_material.set_shader_parameter("disturbance_count", count)
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "RiverDepth"
	parent.add_child(body)
	# Offline-merged rectangles avoid a 16k-pixel scan during chunk activation.
	for rect: Array in record["blocks"]:
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = Vector2(float(rect[2]), float(rect[3]))
		var shape: CollisionShape2D = CollisionShape2D.new()
		shape.shape = box
		shape.position = Vector2(cell) * 512.0 + Vector2(float(rect[0]), float(rect[1])) + box.size * 0.5
		body.add_child(shape)

func _process(delta: float) -> void:
	_clock += delta
	for shader_material: ShaderMaterial in _materials:
		shader_material.set_shader_parameter("water_time", _clock)
	var fall_frame: int = int(_clock * 10.0) % 8
	for fall: Sprite2D in _falls:
		fall.frame = fall_frame
	var spring_frame: int = int(_clock * 8.0) % 4
	for spring: Sprite2D in _springs:
		spring.frame_coords.x = spring_frame
	for glow: Sprite2D in _spring_glows:
		glow.frame_coords.x = spring_frame
