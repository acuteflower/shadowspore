class_name NightLight
extends PointLight2D
## A light that only shines at night. The DayNight node tells every NightLight how dark it is
## (`set_night`), so flowers and eyes glow up as the evening comes and fade at dawn. The light is a
## flat, slightly irregular pool on the ground that breathes slowly, each one out of step.

@export var radius: int = 26 ## px, horizontal radius
@export var squash: float = 0.6 ## flat in the 3/4 view
@export var base_energy: float = 0.9
@export var glow_color: Color = Color("b99bff"):
	set(value):
		glow_color = value
		color = value
@export var pulse: float = 0.14 ## how much the light breathes (0 = steady)

const OVERFLOW_ALPHA_SCALE: float = 0.26 ## additive soft-pool intensity matching PointLight2D brightness on night ground
const OVERFLOW_MAX_ALPHA: float = 0.48
const OVERFLOW_Z: int = -2 ## above ground/water/bridges, beneath standing entities (y-sorted at 0)

static var _overflow_material: CanvasItemMaterial
static var limit: int = 16 ## hardware PointLight2Ds at once (Quality; at most the renderer's LIGHT_LIMIT)
static var small_min: int = 4 ## small lights that always shine (Quality)
static var breath_step: float = 1.0 / 30.0 ## s between energy updates of a breathing light (Quality)

var _night: float = 0.0
var budgeted: bool = true: ## false: outside the 16 nearest PointLight2Ds; falls back to an unlit additive glow pool
	set(value):
		budgeted = value
		_update_active()
var _phase: float = 0.0
var _notifier: VisibleOnScreenNotifier2D
var _on_screen: bool = true
var _overflow: Sprite2D
var _overflow_alpha: float = -1.0
var _breath_wait: float = 0.0


func _ready() -> void:
	var variant: int = absi(int(position.x * 7.0 + position.y * 13.0)) % 3
	LightTexture.apply(self, radius * 2, squash, variant)
	color = glow_color
	_phase = fposmod(position.x * 0.37 + position.y * 0.71, TAU)
	add_to_group("night_lights")
	if DisplayServer.get_name() != "headless":
		_notifier = VisibleOnScreenNotifier2D.new()
		var reach: float = float(radius) + 16.0
		_notifier.rect = Rect2(-reach, -reach * squash, reach * 2.0, reach * 2.0 * squash)
		_notifier.screen_entered.connect(_on_screen_entered)
		_notifier.screen_exited.connect(_on_screen_exited)
		add_child(_notifier)
		var camera: Camera2D = get_viewport().get_camera_2d() if get_viewport() != null else null
		if camera != null:
			var reach_total: float = reach + 400.0
			if global_position.distance_squared_to(camera.get_screen_center_position()) > reach_total * reach_total:
				_on_screen = false
	set_night(TimeManager.night_amount())


func _on_screen_entered() -> void:
	_on_screen = true
	_update_active()


func _on_screen_exited() -> void:
	_on_screen = false
	_update_active()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_update_active()


func _breath_energy() -> float:
	var breath: float = 1.0 - pulse * 0.5 + pulse * 0.5 * sin(Time.get_ticks_msec() * 0.0013 + _phase)
	return base_energy * _night * breath


func _update_active() -> void:
	var lit: bool = _night > 0.01 and _on_screen and is_visible_in_tree()
	var hw: bool = lit and budgeted
	var overflow: bool = lit and not budgeted and texture != null
	enabled = hw
	set_process(hw or overflow)
	if not hw:
		energy = 0.0
	elif energy == 0.0:
		energy = _breath_energy()
	if overflow:
		_sync_overflow(_breath_energy(), true)
	elif _overflow != null and _overflow.visible:
		_overflow.visible = false
		_overflow_alpha = -1.0


func _sync_overflow(target_energy: float, force: bool = false) -> void:
	if _overflow == null:
		if _overflow_material == null:
			_overflow_material = CanvasItemMaterial.new()
			_overflow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			_overflow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_overflow = Sprite2D.new()
		_overflow.texture = texture
		_overflow.scale = Vector2.ONE * texture_scale
		_overflow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_overflow.material = _overflow_material
		_overflow.z_as_relative = false
		_overflow.z_index = OVERFLOW_Z
		add_child(_overflow)
	var a: float = clampf(target_energy * OVERFLOW_ALPHA_SCALE, 0.0, OVERFLOW_MAX_ALPHA)
	_overflow.visible = a > 0.004
	if _overflow.visible and (force or absf(a - _overflow_alpha) > 0.008 or _overflow.modulate.r != glow_color.r or _overflow.modulate.g != glow_color.g or _overflow.modulate.b != glow_color.b):
		_overflow_alpha = a
		_overflow.modulate = Color(glow_color.r, glow_color.g, glow_color.b, a)


func set_night(amount: float) -> void:
	amount = MineManager.night_at(self, amount)
	_night = amount
	_update_active()


func _process(delta: float) -> void:
	_breath_wait -= delta
	if _breath_wait > 0.0:
		return
	_breath_wait = breath_step
	var new_energy: float = _breath_energy()
	if budgeted:
		if absf(energy - new_energy) > 0.02:
			energy = new_energy
	else:
		_sync_overflow(new_energy)


const SMALL_RADIUS: int = 48 ## lights up to this radius (glowing plants, moonbells, shrooms, pillars, boss) share a budget
const LIGHT_LIMIT: int = 16 ## the renderer's limit per picture
const SMALL_MIN: int = 4 ## small lights that always shine, even in a crowd of big ones


## The renderer lights one picture with at most 16 PointLight2Ds, and a ground tile layer is one picture.
## Big landmark lights have priority, while nearby lights share the 16 hardware slots by distance to center.
## Any visible on-screen lights beyond those 16 fall back to an unlit additive glow pool so lights never blink off when walking away.
static func budget(tree: SceneTree, center: Vector2) -> void:
	var small: Array[NightLight] = []
	var big: Array[NightLight] = []
	for node: Node in tree.get_nodes_in_group("night_lights"):
		var light: NightLight = node as NightLight
		if light == null or light._night <= 0.01 or not light.is_visible_in_tree():
			continue
		var max_reach: float = float(light.radius) + 400.0
		var d2: float = light.global_position.distance_squared_to(center)
		if d2 > max_reach * max_reach:
			if light._on_screen:
				light._on_screen = false
				light._update_active()
			continue
		if light._notifier != null and light.is_inside_tree():
			var on_screen: bool = light._notifier.is_on_screen()
			if light._on_screen != on_screen:
				light._on_screen = on_screen
				light._update_active()
		elif not light._on_screen:
			light._on_screen = true
			light._update_active()
		if not light._on_screen:
			continue
		if light.radius <= SMALL_RADIUS:
			small.append(light)
		else:
			big.append(light)

	big.sort_custom(func(a: NightLight, b: NightLight) -> bool: return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	var cap: int = mini(limit, LIGHT_LIMIT)
	var max_big: int = cap - mini(small_min, cap)
	var allowed_big: int = 0
	for i: int in big.size():
		var allow: bool = i < max_big
		if big[i].budgeted != allow:
			big[i].budgeted = allow
		if allow:
			allowed_big += 1

	small.sort_custom(func(a: NightLight, b: NightLight) -> bool: return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	var room: int = maxi(mini(small_min, cap), cap - allowed_big)
	for i: int in small.size():
		var allowed: bool = i < room
		if small[i].budgeted != allowed:
			small[i].budgeted = allowed
