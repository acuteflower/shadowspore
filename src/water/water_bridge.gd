class_name WaterBridge
extends Node2D
## Ancient Stone Arch Bridge (R3 / T9) spanning Square -1's forest brook.
## Registers in `Terrain.patches` AFTER `WaterField`, provides a dry `"ancient_stone"`
## walkable deck (`has_water_deck_at`), Y-sorted north/south stone parapets (`z_index = 0`),
## deck & wet piers (`z_index = -3`), carved lunar-arch night glow (`Unlit.material()`, hidden by day),
## wayfarer `NightLight`, Layer-1 parapet colliders, and `WaterField` pier/shadow injection.

const BRIDGE_TEX: String = "res://assets/props/water_bridge.png"
const BRIDGE_GLOW: String = "res://assets/props/water_bridge_glow.png"

const WALKABLE_DECK_RECT: Rect2 = Rect2(-66.0, -14.0, 132.0, 28.0)
const NORTH_PARAPET_COLLIDER: Rect2 = Rect2(-62.0, -21.0, 124.0, 5.0)
const SOUTH_PARAPET_COLLIDER: Rect2 = Rect2(-62.0, 14.0, 124.0, 5.0)
const PIER_LEFT_OFFSET: Vector2 = Vector2(-26.0, 26.0)
const PIER_RIGHT_OFFSET: Vector2 = Vector2(26.0, 26.0)
const PIER_RADIUS_PX: float = 9.0
const ARCH_SHADOW_RECT: Rect2 = Rect2(-56.0, -14.0, 112.0, 48.0)

const REGION_DECK_BASE: Rect2 = Rect2(8.0, 8.0, 144.0, 56.0)
const REGION_PIER_LEFT: Rect2 = Rect2(8.0, 72.0, 20.0, 28.0)
const REGION_PIER_RIGHT: Rect2 = Rect2(34.0, 72.0, 20.0, 28.0)
const REGION_LANTERN_POST: Rect2 = Rect2(64.0, 72.0, 16.0, 24.0)
const REGION_PARAPET_NORTH: Rect2 = Rect2(8.0, 108.0, 128.0, 18.0)
const REGION_PARAPET_SOUTH: Rect2 = Rect2(8.0, 132.0, 128.0, 18.0)

var _glow_sprites: Array[Sprite2D] = []
var _lantern_light: NightLight = null
var _last_night: float = -1.0
var _bound_field: Node = null
var _world_origin: Vector2 = Vector2.ZERO
var _world_deck_rect: Rect2 = Rect2()
var _world_cached: bool = false


func _ready() -> void:
	z_as_relative = false
	z_index = 0
	y_sort_enabled = true
	add_to_group("flora_glow")
	set_notify_transform(true)
	_update_world_cache()

	_register_patch()
	if not tree_exiting.is_connected(_on_tree_exiting):
		tree_exiting.connect(_on_tree_exiting)

	_build_visuals()
	_build_parapet_colliders()
	_sync_night_visuals(true)

	if _bound_field != null and is_instance_valid(_bound_field):
		bind_water_field(_bound_field)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_world_cache()


func _update_world_cache() -> void:
	_world_origin = global_position if is_inside_tree() else position
	_world_deck_rect = Rect2(_world_origin + WALKABLE_DECK_RECT.position, WALKABLE_DECK_RECT.size)
	_world_cached = true


func deck_world_bounds() -> Rect2:
	if _world_cached:
		return _world_deck_rect
	return Rect2(position + WALKABLE_DECK_RECT.position, WALKABLE_DECK_RECT.size)


func _on_tree_exiting() -> void:
	Terrain.patches.erase(self)


func _register_patch() -> void:
	var wf: Node = _find_water_field()
	re_register_after(wf)


func _find_water_field() -> Node:
	if _bound_field != null and is_instance_valid(_bound_field):
		return _bound_field
	for patch: Node in Terrain.patches:
		if is_instance_valid(patch) and patch.has_method(&"water_field_at"):
			return patch
	return null


func re_register_after(water_field: Node = null) -> void:
	Terrain.patches.erase(self)
	if water_field != null and is_instance_valid(water_field):
		var idx: int = Terrain.patches.find(water_field)
		if idx >= 0:
			Terrain.patches.insert(idx + 1, self)
			return
	Terrain.patches.append(self)


func ensure_after_water_field(water_field: Node = null) -> void:
	re_register_after(water_field if water_field != null else _find_water_field())


func bind_water_field(water_field: Node) -> void:
	_bound_field = water_field
	_update_world_cache()
	re_register_after(water_field)
	if water_field == null or not is_instance_valid(water_field):
		return
	var origin: Vector2 = _world_origin
	if water_field.has_method(&"inject_obstacle"):
		water_field.call(&"inject_obstacle", origin + PIER_LEFT_OFFSET, PIER_RADIUS_PX, 1.0)
		water_field.call(&"inject_obstacle", origin + PIER_RIGHT_OFFSET, PIER_RADIUS_PX, 1.0)
	if water_field.has_method(&"inject_shadow_rect"):
		var world_shadow: Rect2 = Rect2(origin + ARCH_SHADOW_RECT.position, ARCH_SHADOW_RECT.size)
		water_field.call(&"inject_shadow_rect", world_shadow, 1.0)


func has_water_deck_at(world_pos: Vector2) -> bool:
	if not is_finite(world_pos.x) or not is_finite(world_pos.y):
		return false
	if _world_cached:
		return _world_deck_rect.has_point(world_pos)
	return WALKABLE_DECK_RECT.has_point(world_pos - position)


func surface_at(world_pos: Vector2) -> String:
	return "ancient_stone" if has_water_deck_at(world_pos) else ""


func _build_visuals() -> void:
	var tex_base: Texture2D = DataRegistry.tex(BRIDGE_TEX)
	var tex_glow: Texture2D = DataRegistry.tex(BRIDGE_GLOW)

	_add_part("DeckBase", tex_base, tex_glow, REGION_DECK_BASE, Vector2.ZERO, Vector2(-72.0, -20.0), -3, true)
	_add_part("PierLeft", tex_base, null, REGION_PIER_LEFT, Vector2(-26.0, 36.0), Vector2(-10.0, -24.0), -3, false)
	_add_part("PierRight", tex_base, null, REGION_PIER_RIGHT, Vector2(26.0, 36.0), Vector2(-10.0, -24.0), -3, false)
	_add_part("ParapetNorth", tex_base, tex_glow, REGION_PARAPET_NORTH, Vector2(0.0, -13.0), Vector2(-64.0, -16.0), 0, true)
	# Mount lantern_post as sibling after parapet_north at bridge-local Vector2(-32, -13)
	_add_part("LanternPost", tex_base, tex_glow, REGION_LANTERN_POST, Vector2(-32.0, -13.0), Vector2(-8.0, -21.0), 0, true)
	_add_part("ParapetSouth", tex_base, tex_glow, REGION_PARAPET_SOUTH, Vector2(0.0, 16.0), Vector2(-64.0, -14.0), 0, true)

	_lantern_light = NightLight.new()
	_lantern_light.name = "LanternNightLight"
	_lantern_light.position = Vector2(-32.0, -23.0)
	_lantern_light.radius = 52
	_lantern_light.squash = 0.65
	_lantern_light.base_energy = 0.72
	_lantern_light.pulse = 0.12
	_lantern_light.glow_color = Color("ffcb6b")
	add_child(_lantern_light)


func _add_part(
	part_name: String,
	tex_base: Texture2D,
	tex_glow: Texture2D,
	region: Rect2,
	mount_pos: Vector2,
	spr_offset: Vector2,
	part_z: int,
	has_glow: bool
) -> void:
	if tex_base != null:
		var sp: Sprite2D = Sprite2D.new()
		sp.name = part_name
		sp.texture = tex_base
		sp.region_enabled = true
		sp.region_rect = region
		sp.centered = false
		sp.position = mount_pos
		sp.offset = spr_offset
		sp.z_as_relative = false
		sp.z_index = part_z
		add_child(sp)
	if has_glow and tex_glow != null:
		var gl: Sprite2D = Sprite2D.new()
		gl.name = part_name + "Glow"
		gl.texture = tex_glow
		gl.region_enabled = true
		gl.region_rect = region
		gl.centered = false
		gl.position = mount_pos
		gl.offset = spr_offset
		gl.z_as_relative = false
		gl.z_index = part_z
		gl.material = Unlit.material()
		gl.visible = false
		add_child(gl)
		_glow_sprites.append(gl)


func _build_parapet_colliders() -> void:
	var sb: StaticBody2D = StaticBody2D.new()
	sb.name = "ParapetColliders"
	sb.collision_layer = 1
	sb.collision_mask = 0
	for rect: Rect2 in [NORTH_PARAPET_COLLIDER, SOUTH_PARAPET_COLLIDER]:
		var cs: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = rect.size
		cs.shape = box
		cs.position = rect.get_center()
		sb.add_child(cs)
	add_child(sb)


func _process(_delta: float) -> void:
	_sync_night_visuals(false)


func _sync_night_visuals(force: bool) -> void:
	var night: float = TimeManager.night_amount()
	if not force and absf(night - _last_night) <= 0.001:
		return
	_last_night = night
	var glow_on: bool = is_visible_in_tree() and night > 0.02
	var alpha: float = lerpf(0.30, 0.95, clampf(night, 0.0, 1.0)) if glow_on else 0.0
	for gl: Sprite2D in _glow_sprites:
		if is_instance_valid(gl):
			gl.visible = glow_on
			gl.modulate.a = alpha
	if _lantern_light != null and is_instance_valid(_lantern_light):
		_lantern_light.set_night(night)
