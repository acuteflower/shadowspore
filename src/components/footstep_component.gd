class_name FootstepComponent
extends Node2D
## Per-step feedback from the surface data (data/terrain.json): puffs or splashes, and
## footprints on soft ground. Called by the player at every footfall, on every peer.

const FOOTPRINT: Texture2D = preload("res://assets/fx/footprint.png")
const FOOTPRINT_Z: int = -9 ## above the ground layer, below all entities
const FOOT_OFFSET: float = 2.5 ## px, feet alternate left/right of the walking line

var _left_foot: bool = false

@onready var _puff: CPUParticles2D = $Puff

static var _canvas: FootprintCanvas = null


class FootprintItem:
	var pos: Vector2 = Vector2.ZERO
	var rot: float = 0.0
	var color: Color = Color.BLACK
	var base_alpha: float = 0.7
	var age: float = 0.0
	var life: float = 10.0
	var active: bool = false


class FootprintCanvas:
	extends Node2D

	const POOL_SIZE: int = 128
	var _pool: Array[FootprintItem] = []
	var _head: int = 0
	var _has_active: bool = false
	var _tex_offset: Vector2 = Vector2.ZERO

	func _init() -> void:
		_tex_offset = -FOOTPRINT.get_size() * 0.5
		_pool.resize(POOL_SIZE)
		for i: int in POOL_SIZE:
			_pool[i] = FootprintItem.new()

	func add_footprint(pos: Vector2, rot: float, col: Color, alpha: float, life: float) -> void:
		var item: FootprintItem = _pool[_head]
		_head = (_head + 1) % POOL_SIZE
		item.pos = pos
		item.rot = rot
		item.color = col
		item.base_alpha = alpha
		item.age = 0.0
		item.life = maxf(life, 0.01)
		item.active = true
		_has_active = true
		queue_redraw()

	func _process(delta: float) -> void:
		if not _has_active:
			return
		var any_active: bool = false
		for item: FootprintItem in _pool:
			if not item.active:
				continue
			item.age += delta
			if item.age >= item.life:
				item.active = false
			else:
				any_active = true
		_has_active = any_active
		if any_active:
			queue_redraw()

	func _draw() -> void:
		if not _has_active:
			return
		for item: FootprintItem in _pool:
			if not item.active:
				continue
			var t: float = item.age / item.life
			var a: float = item.base_alpha if t < 0.6 else item.base_alpha * (1.0 - (t - 0.6) / 0.4)
			var c: Color = item.color
			c.a = a
			draw_set_transform(item.pos, item.rot, Vector2.ONE)
			draw_texture(FOOTPRINT, _tex_offset, c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _get_canvas(tree: SceneTree) -> FootprintCanvas:
	if _canvas != null and is_instance_valid(_canvas) and _canvas.is_inside_tree() and _canvas.get_tree() == tree:
		return _canvas
	var scene: Node = tree.current_scene
	if scene == null:
		return null
	_canvas = FootprintCanvas.new()
	_canvas.name = "FootprintCanvas"
	_canvas.z_index = FOOTPRINT_Z
	scene.add_child(_canvas)
	return _canvas


## `quiet` (sneaking) skips the puff but still leaves footprints.
## `wet` (0..1, soaked from a swim) leaves dark, short-lived prints on dry ground.
func step(surface: Dictionary, velocity: Vector2, quiet: bool, wet: float = 0.0) -> void:
	_left_foot = not _left_foot
	var fx: Dictionary = surface.get("step", {})
	if not fx.is_empty() and not quiet:
		_emit(fx, velocity)
	var print_data: Dictionary = surface.get("footprint", {})
	var alpha: float = 0.7
	if wet > 0.15 and not bool(surface.get("ripples", false)):
		print_data = {"color": "#1c2b33", "seconds": 1.5 + 3.0 * wet}
		alpha = 0.35 + 0.4 * wet
	if not print_data.is_empty():
		_leave_footprint(print_data, velocity, alpha)


func contact_position(velocity: Vector2) -> Vector2:
	var dir: Vector2 = velocity.normalized()
	return (global_position + Vector2(-dir.y, dir.x) * (FOOT_OFFSET if _left_foot else -FOOT_OFFSET)).round()


func _emit(fx: Dictionary, velocity: Vector2) -> void:
	_puff.color = Color(String(fx.get("color", "#ffffff")))
	_puff.amount = int(fx.get("amount", 3))
	_puff.position = to_local(contact_position(velocity))
	if fx.get("kind", "puff") == "splash":
		_puff.direction = Vector2.UP
		_puff.spread = 55.0
		_puff.gravity = Vector2(0, 240)
		_puff.amount = clampi(roundi(velocity.length() / 18.0), 2, 7)
		_puff.initial_velocity_min = lerpf(14.0, 40.0, clampf(velocity.length() / 90.0, 0.0, 1.0))
		_puff.initial_velocity_max = _puff.initial_velocity_min * 1.5
		_puff.damping_min = 0.0
		_puff.damping_max = 0.0
		_puff.lifetime = 0.4
	else:
		_puff.direction = -velocity.normalized()
		_puff.spread = 40.0
		_puff.gravity = Vector2.ZERO
		_puff.initial_velocity_min = 15.0
		_puff.initial_velocity_max = 35.0
		_puff.damping_min = 50.0
		_puff.damping_max = 70.0
		_puff.lifetime = 0.3
	_puff.restart()


func _leave_footprint(data: Dictionary, velocity: Vector2, alpha: float = 0.7) -> void:
	var canvas: FootprintCanvas = _get_canvas(get_tree())
	if canvas == null:
		return
	var dir: Vector2 = velocity.normalized()
	var rot: float = roundf(dir.angle() / (PI / 4.0)) * (PI / 4.0) ## 8 directions keep the pixels clean
	var global_pos: Vector2 = (global_position + Vector2(-dir.y, dir.x) * (FOOT_OFFSET if _left_foot else -FOOT_OFFSET)).round()
	var local_pos: Vector2 = canvas.to_local(global_pos)
	var col: Color = Color(String(data.get("color", "#000000")))
	var seconds: float = float(data.get("seconds", 10.0))
	canvas.add_footprint(local_pos, rot, col, alpha, seconds)
