class_name RiverDesignPatch
extends Sprite2D
## Stage-one visual primitive. Geometry, depth and flow share one deterministic field.
## Not registered as world terrain until routing/collision is implemented in stage two.
var layout: Dictionary
var water_time: float = 0.0
var bank_width: float = 12.0
var bank_texture: ImageTexture
var field_image: Image
var _sections: Array[PackedVector3Array] = []
var _falls: Array[Sprite2D] = []
var _ledges: Array[Sprite2D] = []
var _settings: Dictionary

func configure(data: Dictionary, settings: Dictionary) -> void:
	layout = data
	_settings = settings
	bank_width = float(settings["bank_width"])
	_sections.clear()
	for section: Array in data["sections"]:
		var points: PackedVector3Array = []
		for value: Array in section:
			points.append(Vector3(float(value[0]), float(value[1]), float(value[2])))
		_sections.append(_smooth_path(points))
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bake()
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = load("res://assets/shaders/river_water.gdshader") as Shader
	shader_material.set_shader_parameter("bank_map", bank_texture)
	shader_material.set_shader_parameter("bank_width", bank_width)
	shader_material.set_shader_parameter("water_detail", load("res://assets/water/water_detail.png"))
	shader_material.set_shader_parameter("bank_material", load("res://assets/water/bank_material.png"))
	shader_material.set_shader_parameter("world_origin", global_position)
	material = shader_material
	set_disturbances(data.get("disturbances", []))
	set_waterfall_links(data.get("waterfalls", []))
	for fall: Sprite2D in _falls:
		fall.queue_free()
	_falls.clear()
	for ledge: Sprite2D in _ledges:
		ledge.queue_free()
	_ledges.clear()
	for point: Array in data.get("waterfalls", []):
		var ledge: Sprite2D = Sprite2D.new()
		ledge.texture = load("res://assets/water/waterfall_rock.png") as Texture2D
		ledge.centered = false
		ledge.position = Vector2(float(point[0]) - 24.0, float(point[1]))
		add_child(ledge)
		_ledges.append(ledge)
		var fall: Sprite2D = Sprite2D.new()
		fall.texture = load("res://assets/water/waterfall.png") as Texture2D
		fall.hframes = int(settings["waterfall_frames"])
		fall.centered = false
		fall.position = Vector2(float(point[0]) - 24.0, float(point[1]))
		add_child(fall)
		_falls.append(fall)

func set_waterfall_links(points: Array) -> void:
	var links: PackedVector4Array = []
	for point: Array in points.slice(0, 4):
		links.append(Vector4(float(point[0]) + global_position.x, float(point[1]) + global_position.y, float(_settings["waterfall_height"]), float(_settings["waterfall_width"])))
	var count: int = links.size()
	while links.size() < 4:
		links.append(Vector4.ZERO)
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("waterfall_links", links)
		(material as ShaderMaterial).set_shader_parameter("fall_link_count", count)

## Local anchors are converted to world space once; no random per-peer effect state.
func set_disturbances(anchors: Array) -> void:
	var values: PackedVector4Array = []
	for anchor: Array in anchors.slice(0, 8):
		values.append(Vector4(float(anchor[0]) + global_position.x, float(anchor[1]) + global_position.y, maxf(0.0, float(anchor[2])), clampf(float(anchor[3]), 0.0, 1.0)))
	var count: int = values.size()
	while values.size() < 8:
		values.append(Vector4.ZERO)
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("disturbances", values)
		(material as ShaderMaterial).set_shader_parameter("disturbance_count", count)

func _smooth_path(points: PackedVector3Array) -> PackedVector3Array:
	var curve: PackedVector3Array = []
	for i: int in points.size() - 1:
		var a: Vector3 = points[maxi(0, i - 1)]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		var d: Vector3 = points[mini(points.size() - 1, i + 2)]
		var steps: int = maxi(2, ceili(b.distance_to(c) / 12.0))
		for j: int in steps:
			var t: float = float(j) / steps
			var q: Vector3 = 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)
			q.z = maxf(2.0, q.z)
			curve.append(q)
	curve.append(points[points.size() - 1])
	return curve

## x: signed bank distance, y: depth, zw: normalized downstream flow.
func sample_field(point: Vector2) -> Vector4:
	var shore_variation: float = sin(point.x * 0.093 + sin(point.y * 0.037) * 2.0) * 1.2 + sin(point.y * 0.17 + point.x * 0.034) * 0.6
	var best: float = INF
	var depth: float = 0.0
	var flow: Vector2 = Vector2.DOWN
	for section: PackedVector3Array in _sections:
		for i: int in section.size() - 1:
			var a: Vector3 = section[i]
			var b: Vector3 = section[i + 1]
			var margin: float = maxf(a.z, b.z) + bank_width + 2.0
			if point.x < minf(a.x, b.x) - margin or point.x > maxf(a.x, b.x) + margin or point.y < minf(a.y, b.y) - margin or point.y > maxf(a.y, b.y) + margin:
				continue
			var start: Vector2 = Vector2(a.x, a.y)
			var delta: Vector2 = Vector2(b.x - a.x, b.y - a.y)
			var t: float = clampf((point - start).dot(delta) / maxf(delta.length_squared(), 0.001), 0.0, 1.0)
			var radius: float = lerpf(a.z, b.z, t)
			var distance: float = point.distance_to(start + delta * t)
			var signed_distance: float = distance - radius - shore_variation
			if signed_distance < best:
				best = signed_distance
				depth = pow(clampf(1.0 - distance / radius, 0.0, 1.0), 0.8)
				flow = delta.normalized()
	# Keep the water footprint connected underneath the falling curtain. The ledge
	# art supplies the visible sides; no dry bank strip may cut across the flow.
	for point_value: Array in layout.get("waterfalls", []):
		var lip: Vector2 = Vector2(float(point_value[0]), float(point_value[1]))
		var foot: Vector2 = lip + Vector2(0.0, float(_settings["waterfall_height"]))
		var nearest: Vector2 = Vector2(lip.x, clampf(point.y, lip.y, foot.y))
		var radius: float = float(_settings["waterfall_width"]) * 0.5
		var distance: float = point.distance_to(nearest)
		var signed_distance: float = distance - radius
		if signed_distance < best:
			best = signed_distance
			depth = clampf(1.0 - distance / radius, 0.0, 1.0)
			flow = Vector2.DOWN
	for ford: Array in layout.get("fords", []):
		var distance: float = point.distance_to(Vector2(float(ford[0]), float(ford[1])))
		var along: float = absf((point - Vector2(float(ford[0]), float(ford[1]))).dot(flow))
		var blend: float = maxf(smoothstep(float(ford[2]) * 0.3, float(ford[2]), along), smoothstep(40.0, 70.0, distance))
		depth = lerpf(minf(depth, float(layout["ford_depth"])), depth, blend)
	return Vector4(best, depth, flow.x, flow.y)

func bake() -> void:
	var size: Array = layout["size"]
	var width: int = int(size[0])
	var height: int = int(size[1])
	field_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	var bank: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		for x: int in width:
			var field: Vector4 = sample_field(Vector2(x + 0.5, y + 0.5))
			field_image.set_pixel(x, y, Color(1.0 if field.x <= 0.0 else 0.0, field.y, field.z * 0.5 + 0.5, field.w * 0.5 + 0.5))
			bank.set_pixel(x, y, Color(clampf(field.x / bank_width, 0.0, 1.0), 0.0, 0.0, 1.0))
	texture = ImageTexture.create_from_image(field_image)
	bank_texture = ImageTexture.create_from_image(bank)

func _process(delta: float) -> void:
	water_time += delta
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("water_time", water_time)
	for fall: Sprite2D in _falls:
		fall.frame = int(water_time * float(_settings["waterfall_fps"])) % int(_settings["waterfall_frames"])
