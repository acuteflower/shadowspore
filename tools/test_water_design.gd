extends Node
var _checks: int = 0
var _failures: int = 0
func _ready() -> void:
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)
func _run() -> void:
	var settings: Dictionary = DataRegistry.table("water_design")
	var fixture: Dictionary = {"size": [96, 64], "sections": [[[45, -10, 12], [45, 32, 12], [45, 78, 12]]], "fords": [], "waterfalls": []}
	var patch: RiverDesignPatch = RiverDesignPatch.new()
	add_child(patch)
	patch.configure(fixture, settings)
	_check(patch.sample_field(Vector2(45, 20)).x < 0.0, "Creek center dry")
	_check(patch.sample_field(Vector2(5, 20)).x > 12.0, "Distant meadow painted wet")
	_check(patch.sample_field(Vector2(45, 20)).y > patch.sample_field(Vector2(54, 20)).y, "Depth does not rise toward center")
	var flow: Vector4 = patch.sample_field(Vector2(45, 20))
	_check(absf(flow.z) < 0.01 and flow.w > 0.99, "Flow points upstream")
	_check(patch.texture.get_width() == 96 and patch.texture.get_height() == 64, "Mask dimensions wrong")
	_check(patch.field_image.get_pixel(45, 20).r == 1.0 and patch.field_image.get_pixel(5, 20).r == 0.0, "Coverage mask corrupt")
	var first: PackedByteArray = patch.field_image.get_data()
	patch.bake()
	_check(first == patch.field_image.get_data(), "Bake is not deterministic")
	var old_time: float = patch.water_time
	patch._process(0.5)
	_check(is_equal_approx(patch.water_time, old_time + 0.5), "Animation clock failed")
	patch.set_process(false)
	old_time = patch.water_time
	await get_tree().process_frame
	await get_tree().process_frame
	_check(patch.water_time == old_time, "Paused animation advances")
	fixture["fords"] = [[45, 32, 15]]
	fixture["ford_depth"] = 0.22
	patch.configure(fixture, settings)
	_check(patch.sample_field(Vector2(45, 32)).y <= 0.23, "Ford is not shallow")
	_check(patch.sample_field(Vector2(45, 2)).y > 0.8, "Ford flooded entire channel with shallow water")
	for name_value: String in ["water_detail", "bank_material", "waterfall", "waterfall_rock", "shore_details"]:
		var texture: Texture2D = load("res://assets/water/%s.png" % name_value) as Texture2D
		_check(texture != null, "Missing art: " + name_value)
	var falls: Image = (load("res://assets/water/waterfall.png") as Texture2D).get_image()
	_check(falls.get_width() == 384 and falls.get_height() == 48, "Fall frame contract broken")
	var previous: PackedByteArray = falls.get_region(Rect2i(0, 0, 48, 48)).get_data()
	for frame: int in range(1, 8):
		var next: PackedByteArray = falls.get_region(Rect2i(frame * 48, 0, 48, 48)).get_data()
		_check(next != previous, "Identical waterfall frames")
		previous = next
	_check(patch.material is ShaderMaterial and (patch.material as ShaderMaterial).shader != null, "Water shader missing")
	_check(not Terrain.patches.has(patch), "Stage one accidentally registered gameplay terrain")
	patch.position = Vector2(13, 21)
	patch.set_disturbances([[20, 25, 18, 0.8]])
	var shader_material: ShaderMaterial = patch.material as ShaderMaterial
	var anchors: PackedVector4Array = shader_material.get_shader_parameter("disturbances")
	_check(int(shader_material.get_shader_parameter("disturbance_count")) == 1, "Disturbance count missing")
	_check(anchors.size() == 8 and anchors[0] == Vector4(33, 46, 18, 0.8), "Disturbance world anchor corrupt")
	patch.set_disturbances([])
	_check(int(shader_material.get_shader_parameter("disturbance_count")) == 0, "Disturbances did not clear")
	fixture["waterfalls"] = [[45, 16]]
	fixture["sections"] = [[[45, -10, 12], [45, 10, 12]], [[45, 54, 12], [45, 78, 12]]]
	fixture["fords"] = []
	patch.configure(fixture, settings)
	var links: PackedVector4Array = (patch.material as ShaderMaterial).get_shader_parameter("waterfall_links")
	_check(links.size() == 4 and links[0] == Vector4(58, 37, 32, 28), "Waterfall link world coordinates wrong")
	_check(int((patch.material as ShaderMaterial).get_shader_parameter("fall_link_count")) == 1, "Waterfall link count wrong")
	var connected: bool = true
	for y: int in range(8, 56):
		for x: int in range(38, 53):
			connected = connected and patch.field_image.get_pixel(x, y).r > 0.9
	_check(connected, "Dry seam below waterfall curtain")
	patch._process(0.8)
	_check(patch._falls[0].frame == int(patch.water_time * 10) % 8, "Fall and surface clocks diverged")
	print("Water design: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
