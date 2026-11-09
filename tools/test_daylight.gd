extends Node2D
var failures: int = 0
class Canopy:
	extends Node2D
	var standing: bool = true
	func day_canopy() -> Vector4:
		return Vector4(global_position.x, global_position.y, 72.0, 48.0) if standing else Vector4.ZERO
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _run() -> void:
	var camera: Camera2D = Camera2D.new()
	add_child(camera)
	var field: DaylightField = DaylightField.new()
	field.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(field)
	field.set_process(false)
	var tree: Canopy = Canopy.new()
	add_child(tree)
	tree.add_to_group("day_canopies")
	var view: Rect2 = Rect2(-320, -180, 640, 360)
	field.follow(false, 1.0, 0.0)
	field.rebuild(view)
	check(field.canopy_at(Vector2.ZERO) > 0.8, "standing crown shades its world footprint")
	check(field.canopy_at(Vector2(200, 0)) < 0.01, "open meadow is outside the canopy")
	var anchor: float = field.canopy_at(Vector2.ZERO)
	field.rebuild(Rect2(view.position + Vector2(64, 0), view.size))
	check(absf(field.canopy_at(Vector2.ZERO) - anchor) < 0.01, "camera movement leaves world shadow fixed")
	tree.modulate.a = 0.28
	field.rebuild(view)
	check(field.canopy_at(Vector2.ZERO) > 0.8, "visibility fade does not remove physical canopy")
	tree.standing = false
	field.rebuild(view)
	check(field.canopy_at(Vector2.ZERO) == 0.0, "felling removes canopy")
	tree.standing = true
	field.rebuild(view)
	check(field.canopy_at(Vector2.ZERO) > 0.8, "regrowth restores canopy")
	tree.queue_free()
	await get_tree().process_frame
	field.rebuild(view)
	check(field.canopy_at(Vector2.ZERO) == 0.0, "chunk unload removes canopy")
	field.follow(false, TimeManager.sun_at(0.757), TimeManager.golden_at(0.757))
	check(field.strength > 0.8, "golden hour retains local sunlight")
	field.follow(true, 1.0, 1.0)
	check(field.strength == 0.0 and not field.visible, "interiors and mines suppress daylight")
	field.follow(false, 0.0, 0.0)
	check(field.strength == 0.0 and not field.visible, "night suppresses daylight")
	InputManager.inventory_open = true
	check(DaylightField.air_blocked(), "inventory suppresses airborne effects")
	InputManager.inventory_open = false
	camera.zoom = Vector2(2, 2)
	await get_tree().process_frame
	var motes: DayMotes = DayMotes.new()
	add_child(motes)
	check(motes._view_rect().size.is_equal_approx(get_viewport_rect().size / 2.0), "pollen bounds respect camera zoom")
	check(motes._motes.size() <= 40, "pollen has a hard budget")
	field.set_process(true)
	field.follow(false, 1.0, 0.0)
	await get_tree().process_frame
	var before: float = field.clock
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(field.clock == before, "light animation pauses with game")
	get_tree().paused = false
	# Shader compile/render coverage, plus CPU/GPU local-light parity on actual framebuffer.
	field.set_process(false)
	field.clock = 12.0
	RenderingServer.global_shader_parameter_set("g_day_clock", field.clock)
	var rect: ColorRect = ColorRect.new()
	rect.position = Vector2(-160, -90)
	rect.size = Vector2(320, 180)
	var mat: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = 'shader_type canvas_item; render_mode unshaded;\n#include "res://assets/shaders/daylight.gdshaderinc"\nvarying vec2 p; void vertex() {p=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy;} void fragment() {COLOR=vec4(vec3(day_local(p)),1.0);}'
	mat.shader = shader
	rect.material = mat
	add_child(rect)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var center: Vector2i = img.get_size() / 2
		var measured: float = img.get_pixelv(center).r
		check(absf(measured - field.light_at(Vector2.ZERO)) < 0.035, "CPU pollen and GPU surface light agree")
	print("DAYLIGHT failures=", failures, " canopy rebuild us=", field.rebuild_usec)
	get_tree().quit(1 if failures > 0 else 0)
