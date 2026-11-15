class_name ShadowPatch
extends Node2D
## A patch of creeping shadow on the ground (see shadow_patch.gdshader). It grows, writhes for a
## few seconds, then slowly crumbles away. Drawn on the GPU, so many patches stay cheap.

const SHADER: Shader = preload("res://assets/shaders/shadow_patch.gdshader")
const GROUND_Z: int = -9 ## above the ground, below all entities
const MAX_ACTIVE: int = 36

static var _white: ImageTexture
static var _pool: Array[ShadowPatch] = []
static var _active: Array[ShadowPatch] = []
static var _pool_world_id: int = 0

var _size: Vector2i = Vector2i(14, 10)
var _life: float = 3.0
var _fade: float = 2.5
var _arms: int = 4
var _age: float = 0.0
var _material: ShaderMaterial
var _frame_slot: int = 0
var _pooled_in_active: bool = false


## `size` in pixels (keep it even), `life` seconds before the dissolve starts, `fade` how long
## the dissolve takes, `arms` how many tendrils (max 10).
static func spawn(world: Node, pos: Vector2, size: Vector2i, life: float, fade: float, arms: int = 4) -> void:
	if world == null:
		return
	var wid: int = world.get_instance_id()
	if _pool_world_id != wid:
		for stale: ShadowPatch in _pool:
			if is_instance_valid(stale):
				stale.queue_free()
		for stale_act: ShadowPatch in _active:
			if is_instance_valid(stale_act):
				stale_act.queue_free()
		_pool.clear()
		_active.clear()
		_pool_world_id = wid
	var patch: ShadowPatch = null
	while not _pool.is_empty():
		var cand: ShadowPatch = _pool.pop_back() as ShadowPatch
		if is_instance_valid(cand) and cand.get_parent() == world:
			patch = cand
			break
	if patch == null and _active.size() >= MAX_ACTIVE:
		for idx: int in _active.size():
			var act: ShadowPatch = _active[idx]
			if not is_instance_valid(act) or act.get_parent() != world:
				_active.remove_at(idx)
				continue
			if size.x > 24 or act._size.x <= 24:
				_active.remove_at(idx)
				act._pooled_in_active = false
				patch = act
				break
		if patch == null and not _active.is_empty():
			var oldest: ShadowPatch = _active[0]
			_active.remove_at(0)
			if is_instance_valid(oldest) and oldest.get_parent() == world:
				oldest._pooled_in_active = false
				patch = oldest
	var target_z: int = -4 if MineManager.in_mine(pos) else GROUND_Z ## in the mine the ground is painted at z -6
	if patch == null:
		patch = ShadowPatch.new()
		patch._size = size
		patch._life = life
		patch._fade = fade
		patch._arms = arms
		patch._frame_slot = _active.size() & 1
		patch.z_index = target_z
		patch._pooled_in_active = true
		_active.append(patch)
		world.add_child(patch)
		patch.global_position = pos.round()
	else:
		patch._reconfigure(pos.round(), target_z, size, life, fade, arms)
		patch._pooled_in_active = true
		_active.append(patch)


func _ready() -> void:
	if _white == null:
		var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(image)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("size", Vector2(_size))
	_material.set_shader_parameter("seed", randf())
	_material.set_shader_parameter("life", _life)
	_material.set_shader_parameter("fade", _fade)
	_material.set_shader_parameter("arms", _arms)
	material = _material


func _reconfigure(pos: Vector2, target_z: int, size: Vector2i, life: float, fade: float, arms: int) -> void:
	var size_changed: bool = _size != size
	if size_changed:
		_size = size
		_material.set_shader_parameter("size", Vector2(size))
		queue_redraw()
	if _life != life:
		_life = life
		_material.set_shader_parameter("life", life)
	if _fade != fade:
		_fade = fade
		_material.set_shader_parameter("fade", fade)
	if _arms != arms:
		_arms = arms
		_material.set_shader_parameter("arms", arms)
	_age = 0.0
	_material.set_shader_parameter("age", 0.0)
	z_index = target_z
	global_position = pos
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life + _fade:
		visible = false
		set_process(false)
		if _pooled_in_active:
			_pooled_in_active = false
			_active.erase(self)
			_pool.append(self)
		else:
			queue_free()
		return
	if ((Engine.get_process_frames() + _frame_slot) & 1) == 0:
		_material.set_shader_parameter("age", _age)


func _draw() -> void:
	draw_texture_rect(_white, Rect2(-_size.x / 2.0, -_size.y / 2.0, _size.x, _size.y), false)
