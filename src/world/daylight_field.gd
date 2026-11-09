class_name DaylightField
extends Node2D
## Cosmetic local canopy map: bounded 128x96, rebuilt at 3 Hz, independent of crown visibility fades.
## Clouds/dapple are analytic and shared verbatim with daylight.gdshaderinc (CPU pollen + GPU materials).
static var current: DaylightField
const SIZE: Vector2i = Vector2i(128, 96)
const PAD: float = 192.0
var clock: float = 0.0
var sway: Vector2 = Vector2.ZERO
var strength: float = 0.0
var golden: float = 0.0
var coverage: Image
var region: Rect2 = Rect2()
var rebuild_usec: int = 0
var _texture: ImageTexture
var _wait: float = 0.0
var _config: Dictionary = {}
var _story_blocked: bool = false
var _story_wait: float = 0.0
var _shafts: ShaderMaterial
var _quad: Polygon2D

func _ready() -> void:
	_config = DataRegistry.table("daylight")
	current = self
	z_index = -7
	coverage = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_R8)
	coverage.fill(Color.BLACK)
	_texture = ImageTexture.create_from_image(coverage)
	RenderingServer.global_shader_parameter_set("g_day_cover", _texture)
	_quad = Polygon2D.new()
	_shafts = ShaderMaterial.new()
	_shafts.shader = preload("res://assets/shaders/day_shafts.gdshader")
	_quad.material = _shafts
	add_child(_quad)
	_shafts.set_shader_parameter("noon_alpha", float(_config.get("shaft_noon", 0.035)))
	_shafts.set_shader_parameter("gold_alpha", float(_config.get("shaft_golden", 0.095)))

func _exit_tree() -> void:
	if current == self:
		current = null
		RenderingServer.global_shader_parameter_set("g_day_strength", 0.0)
		RenderingServer.global_shader_parameter_set("g_day_rect", Vector4.ZERO)

func follow(indoors: bool, sun: float, gold: float) -> void:
	strength = 0.0 if indoors else maxf(sun, gold * float(DataRegistry.table("daylight").get("golden_strength", 0.85)))
	golden = 0.0 if indoors else gold
	RenderingServer.global_shader_parameter_set("g_day_strength", strength)
	RenderingServer.global_shader_parameter_set("g_day_gold", golden)
	visible = strength > 0.001

func _process(delta: float) -> void:
	_story_wait -= delta
	if _story_wait <= 0.0:
		_story_wait = 0.15
		_story_blocked = false
		for actor: Node in get_tree().get_nodes_in_group("players"):
			if actor.is_multiplayer_authority(): _story_blocked = bool(actor.get("story_lock"))
	clock += delta
	sway = WorldWind.sample(Vector2.ZERO) * 3.0
	RenderingServer.global_shader_parameter_set("g_day_sway", sway)
	RenderingServer.global_shader_parameter_set("g_day_clock", clock)
	_shafts.set_shader_parameter("air", 0.0 if air_blocked() else 1.0)
	if strength <= 0.001: return
	var view: Rect2 = view_rect()
	_wait -= delta
	if _wait <= 0.0 or not region.encloses(view.grow(32.0)):
		rebuild(view)
		_wait = float(_config.get("canopy_tick", 0.33))

static func air_blocked() -> bool:
	return (is_instance_valid(current) and current._story_blocked) or InputManager.ui_blocking or InputManager.inventory_open or InputManager.menu_open or InputManager.map_open or InputManager.skills_open

func view_rect() -> Rect2:
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()

func rebuild(view: Rect2) -> void:
	var started: int = Time.get_ticks_usec()
	var area: Rect2 = view.grow(PAD)
	var step: Vector2 = Vector2(ceilf(area.size.x / SIZE.x / 4.0) * 4.0, ceilf(area.size.y / SIZE.y / 4.0) * 4.0)
	region = Rect2((area.position / step).floor() * step, step * Vector2(SIZE))
	coverage.fill(Color.BLACK)
	var rays: PackedVector4Array = PackedVector4Array()
	var candidates: Array[Node] = get_tree().get_nodes_in_group("day_canopies")
	for node: Node in candidates:
		var tree: Node2D = node as Node2D
		if tree == null or not region.grow(240.0).has_point(tree.global_position): continue
		var shape: Vector4 = tree.call("day_canopy")
		if shape.z <= 0.0: continue
		var center: Vector2 = Vector2(shape.x, shape.y)
		var radius: Vector2 = Vector2(shape.z, shape.w)
		var bounds: Rect2i = Rect2i(((center - radius - region.position) / step).floor(), (radius * 2.0 / step).ceil() + Vector2(2, 2))
		bounds = bounds.intersection(Rect2i(Vector2i.ZERO, SIZE))
		for y: int in range(bounds.position.y, bounds.end.y):
			for x: int in range(bounds.position.x, bounds.end.x):
				var p: Vector2 = region.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * step
				var d: float = ((p - center) / radius).length()
				var cover: float = (1.0 - smoothstep(0.55, 1.0, d)) * 0.88
				coverage.set_pixel(x, y, Color(maxf(coverage.get_pixel(x, y).r, cover), 0, 0))
		# Stable selection from world position; no random changes as the camera moves.
		var eligible: bool = posmod(int(tree.global_position.x) * 7 + int(tree.global_position.y) * 13, 5) == 0
		if rays.size() < clampi(int(_config.get("shaft_limit", 4)), 0, 4) and eligible and view.grow(80.0).has_point(center):
			rays.append(Vector4(center.x - radius.x * 0.3, center.y - radius.y * 0.6, minf(110.0, radius.x * 2.4), maxf(5.0, radius.x * 0.16)))
	var count: int = rays.size()
	while rays.size() < 4: rays.append(Vector4.ZERO)
	_texture.update(coverage)
	RenderingServer.global_shader_parameter_set("g_day_rect", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
	_quad.polygon = PackedVector2Array([region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)])
	_shafts.set_shader_parameter("shafts", rays)
	_shafts.set_shader_parameter("shaft_count", count)
	rebuild_usec = Time.get_ticks_usec() - started

func canopy_at(p: Vector2) -> float:
	if not region.has_point(p): return 0.0
	# Match GPU linear filtering, including the half-texel center.
	var uv: Vector2 = (p - region.position) / region.size * Vector2(SIZE) - Vector2(0.5, 0.5)
	var base: Vector2i = Vector2i(uv.floor())
	var f: Vector2 = uv - uv.floor()
	var a: float = coverage.get_pixel(clampi(base.x, 0, SIZE.x - 1), clampi(base.y, 0, SIZE.y - 1)).r
	var b: float = coverage.get_pixel(clampi(base.x + 1, 0, SIZE.x - 1), clampi(base.y, 0, SIZE.y - 1)).r
	var c: float = coverage.get_pixel(clampi(base.x, 0, SIZE.x - 1), clampi(base.y + 1, 0, SIZE.y - 1)).r
	var d: float = coverage.get_pixel(clampi(base.x + 1, 0, SIZE.x - 1), clampi(base.y + 1, 0, SIZE.y - 1)).r
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

func light_at(p: Vector2) -> float:
	var q: Vector2 = p / 270.0 - Vector2(clock * 0.009, clock * 0.004)
	var n: float = sin(q.x + sin(q.y * 0.83) * 1.2) * 0.55 + sin(q.y * 1.31 - q.x * 0.47) * 0.3
	var cloud: float = lerpf(0.62, 1.0, smoothstep(-0.35, 0.48, n))
	q = p + sway
	var dap: float = smoothstep(0.52, 0.86, sin(q.x * 0.25 + sin(q.y * 0.19)) * sin(q.y * 0.29 - q.x * 0.08))
	return cloud * (1.0 - canopy_at(p) * (0.77 - 0.55 * dap))
