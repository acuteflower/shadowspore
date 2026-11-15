class_name WaterReflections
extends Node
## Mirror images in water and rain puddles (docs/wasserspiegelung.md).
##
## Things that can be mirrored register themselves (`watch`): Ellie and other players, settlers, the
## knight, animals, trees, bushes, rocks, buildings. A few times a second the system picks those whose
## mirror image would fall on water inside the camera view (rivers and lakes from the baked
## `WorldRivers` field; while puddles lie on the ground, everything near the camera), at most
## `MAX_ITEMS` pictures, nearest to the camera first. Right before every draw it copies their visible
## Sprite2D parts upside down about their waterline into a small SubViewport the size of the view
## (same texture frame, same material: hair, blood, wetness and glow stay right). Custom painters
## (Ellie's sword arm) are replayed by `reflection_painters()`. Water shaders read the result through
## the global `g_reflect` (assets/shaders/water_reflect.gdshaderinc). Nothing on water in view = the
## viewport does not render at all and the shaders skip the lookup.
##
## Cosmetic and local: every peer mirrors what it sees. Shadow creatures are drawn procedurally and
## have no mirror image (fitting: the void throws none).

const BUCKET: float = 256.0 ## px, grid of the resting things
const MAX_ITEMS: int = 140 ## sprite copies per frame at most (rivers and lakes)
const PUDDLE_ITEMS: int = 56 ## ... while only puddles are in play (nearest to the view's middle win)
const MAX_PAINTERS: int = 4 ## custom-drawn parts (Ellie's sword arm) per frame
const REBUILD: float = 0.2 ## s between choosing what to mirror
const REACH_UP: float = 230.0 ## things this far above the view may still mirror into it
const SAMPLE: float = 12.0 ## px between water probes of a mirror image
const PUDDLE_MIN: float = 0.04 ## WeatherManager.puddle from which the ground mirrors too

static var current: WaterReflections
static var _buckets: Dictionary = {} ## Vector2i -> Array[Node2D] (resting things)
static var _where: Dictionary = {} ## instance id -> Vector2i bucket
static var _pending: Array[Node2D] = [] ## resting things not yet sorted into a bucket (their position may still be set)
static var _moving: Array[Node2D] = []
static var _ticks: Dictionary = {} ## instance id -> [position a tick ago, position now, physics frame] (drawn_offset)

var rivers: WorldRivers
var enabled: bool = true

var _viewport: SubViewport
var _root: Node2D
var _items: Array[RID] = []
var _item_material: Array[RID] = []
var _item_z: PackedInt32Array = []
var _item_shown: PackedByteArray = []
var _slot_start: PackedInt32Array = [] ## per chosen thing: its first sprite copy ...
var _slot_cap: PackedInt32Array = [] ## ... and how many copies it may use (stable until the next rebuild)
var _slot_moving: PackedByteArray = [] ## 1 = redrawn every frame; resting things every third frame
var _fresh: bool = true ## the choice changed: redraw everything once
var _frame: int = 0
var _painters: Array[Node2D] = []
var _painter_calls: Array[Callable] = []
var _active: Array[Node2D] = [] ## chosen at the last rebuild, nearest first
var _water_cache: Dictionary = {} ## instance id -> bool (resting things only)
var _parts: Dictionary = {} ## instance id -> {"t": msec, "list": Array[Sprite2D]}
var _wait: float = 0.0
var _on: bool = false
var _last_on: bool = false
var _last_reflect_rect: Vector4 = Vector4(INF, INF, INF, INF)
var cost_usec: int = 0 ## main-thread time of the last drawing pass (for checks)
var drawn_items: int = 0 ## sprite copies in the last drawing pass


## Registers a thing that may appear in water. `moving` = it walks or flies (checked anew every rebuild).
static func watch(node: Node2D, moving: bool = false) -> void:
	if moving:
		if not _moving.has(node):
			_moving.append(node)
	else:
		_pending.append(node)


static func unwatch(node: Node2D) -> void:
	_moving.erase(node)
	_ticks.erase(node.get_instance_id())
	_pending.erase(node)
	var id: int = node.get_instance_id()
	if _where.has(id):
		var list: Array = _buckets.get(_where[id], []) as Array
		list.erase(node)
		_where.erase(id)
	if current != null:
		current._water_cache.erase(id)
		current._parts.erase(id)


## Sorts resting things that registered since the last call into their buckets (shared with SunShadows).
static func settle() -> void:
	for node: Node2D in _pending:
		if is_instance_valid(node) and node.is_inside_tree():
			var key: Vector2i = Vector2i((node.global_position / BUCKET).floor())
			_where[node.get_instance_id()] = key
			if not _buckets.has(key):
				_buckets[key] = []
			(_buckets[key] as Array).append(node)
	_pending.clear()


## Every registered thing (resting and moving) whose position lies in `rect` (shared with SunShadows).
static func things_in(rect: Rect2) -> Array[Node2D]:
	var found: Array[Node2D] = []
	var lo: Vector2i = Vector2i((rect.position / BUCKET).floor())
	var hi: Vector2i = Vector2i((rect.end / BUCKET).floor())
	for by: int in range(lo.y, hi.y + 1):
		for bx: int in range(lo.x, hi.x + 1):
			var list: Variant = _buckets.get(Vector2i(bx, by))
			if list == null:
				continue
			for node: Variant in (list as Array):
				var thing: Node2D = node as Node2D
				if thing != null and is_instance_valid(thing) and thing.is_visible_in_tree() and rect.has_point(thing.global_position):
					found.append(thing)
	for thing: Node2D in _moving:
		if is_instance_valid(thing) and thing.is_inside_tree() and thing.is_visible_in_tree() and rect.has_point(thing.global_position):
			found.append(thing)
	return found


## True for a thing that walks or flies (registered as moving).
static func is_moving(thing: Node2D) -> bool:
	return _moving.has(thing)


## Physics interpolation (project setting) draws a moving thing between its last two physics ticks, but its transform is
## the latest tick: copies placed from it would lead the picture and jitter. This is how far the drawn picture lies behind
## the transform right now; add it to a copy of a moving thing. Zero for things that jumped (teleport) or stand still.
static func drawn_offset(thing: Node2D) -> Vector2:
	if not ProjectSettings.get_setting("physics/common/physics_interpolation", false):
		return Vector2.ZERO
	var id: int = thing.get_instance_id()
	var pos: Vector2 = thing.global_position
	var tick: int = Engine.get_physics_frames()
	var rec: Array = _ticks.get(id, []) as Array
	if rec.is_empty():
		_ticks[id] = [pos, pos, tick]
		return Vector2.ZERO
	if int(rec[2]) != tick:
		rec[0] = rec[1]
		rec[1] = pos
		rec[2] = tick
	elif (rec[1] as Vector2) != pos: ## moved outside the physics step (a teleport, a cutscene): no lag
		rec[0] = pos
		rec[1] = pos
	var before: Vector2 = rec[0]
	var now: Vector2 = rec[1]
	if before.distance_squared_to(now) > 48.0 * 48.0:
		return Vector2.ZERO
	return before.lerp(now, Engine.get_physics_interpolation_fraction()) - pos


func _ready() -> void:
	current = self
	_viewport = SubViewport.new()
	_viewport.name = "Mirror"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = Vector2i(640, 360)
	add_child(_viewport)
	_root = Node2D.new()
	_root.name = "Mirrored"
	_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_root)
	RenderingServer.global_shader_parameter_set("g_reflect", _viewport.get_texture())
	RenderingServer.global_shader_parameter_set("g_reflect_on", 0.0)
	RenderingServer.frame_pre_draw.connect(_draw_pass)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_draw_pass):
		RenderingServer.frame_pre_draw.disconnect(_draw_pass)
	RenderingServer.global_shader_parameter_set("g_reflect_on", 0.0)
	for item: RID in _items:
		RenderingServer.free_rid(item)
	_items.clear()
	if current == self:
		current = null


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REBUILD
	_rebuild()


# --- choosing ---------------------------------------------------------------------------------------

func _view_rect() -> Rect2:
	var viewport: Viewport = get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()


func _rebuild() -> void:
	_active.clear()
	enabled = bool(GameSettings.get_value("reflections")) and bool(Quality.get_value("reflections"))
	if not enabled or not is_inside_tree():
		_on = false
		return
	settle()
	var view: Rect2 = _view_rect()
	var reach: Rect2 = Rect2(view.position - Vector2(48.0, REACH_UP), view.size + Vector2(96.0, REACH_UP))
	var puddles: bool = WeatherManager.current != null and WeatherManager.current.puddle > PUDDLE_MIN
	var middle: Vector2 = view.get_center()
	var found: Array[Node2D] = []
	var wet: Dictionary = {} ## instance id -> true: its mirror image lies on river or lake water
	var lo: Vector2i = Vector2i((reach.position / BUCKET).floor())
	var hi: Vector2i = Vector2i((reach.end / BUCKET).floor())
	for by: int in range(lo.y, hi.y + 1):
		for bx: int in range(lo.x, hi.x + 1):
			var list: Variant = _buckets.get(Vector2i(bx, by))
			if list == null:
				continue
			for node: Variant in (list as Array):
				var thing: Node2D = node as Node2D
				if thing == null or not is_instance_valid(thing) or not thing.is_visible_in_tree():
					continue
				if not reach.has_point(thing.global_position):
					continue
				var id: int = thing.get_instance_id()
				if not _water_cache.has(id):
					_water_cache[id] = _water_below(thing, view)
				if bool(_water_cache[id]):
					wet[id] = true
				if puddles or bool(_water_cache[id]):
					found.append(thing)
	for thing: Node2D in _moving:
		if is_instance_valid(thing) and thing.is_inside_tree() and thing.is_visible_in_tree() and reach.has_point(thing.global_position):
			var on_water: bool = _water_below(thing, view)
			if on_water:
				wet[thing.get_instance_id()] = true
			if puddles or on_water:
				found.append(thing)
	found.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(middle) < b.global_position.distance_squared_to(middle))
	# nearest first until the budget is spent, then drawn back to front (by waterline)
	var max_items: int = Quality.scaled(MAX_ITEMS, "reflection_items", 24) ## graphics level
	var budget: int = max_items
	var chosen: Array[Node2D] = []
	var lines: Dictionary = {}
	for thing: Node2D in found:
		var id: int = thing.get_instance_id()
		var cost: int = _sprites_of(thing).size()
		if not wet.has(id) and budget <= max_items - Quality.scaled(PUDDLE_ITEMS, "reflection_items", 8):
			continue ## puddle-only things share a smaller budget
		if cost == 0 or cost > budget:
			continue
		budget -= cost
		chosen.append(thing)
		lines[id] = _line_of(thing)
	chosen.sort_custom(func(a: Node2D, b: Node2D) -> bool: return float(lines[a.get_instance_id()]) < float(lines[b.get_instance_id()]))
	_active = chosen
	_slot_start.resize(chosen.size())
	_slot_cap.resize(chosen.size())
	_slot_moving.resize(chosen.size())
	var next: int = 0
	for k: int in range(chosen.size()):
		_slot_start[k] = next
		_slot_cap[k] = _sprites_of(chosen[k]).size()
		_slot_moving[k] = 1 if _moving.has(chosen[k]) else 0
		next += _slot_cap[k]
	_fresh = true
	_on = not chosen.is_empty()


## True when part of the thing's mirror image (from its waterline down, as tall as the thing) lies on river or lake water.
func _water_below(thing: Node2D, _view: Rect2) -> bool:
	if rivers == null or not is_instance_valid(rivers):
		return false
	var line: float = _line_of(thing)
	var bounds: Rect2 = _bounds_of(thing)
	if bounds.size.y <= 0.0:
		return false
	var height: float = maxf(line - bounds.position.y, 8.0)
	var left: float = bounds.position.x
	var right: float = bounds.end.x
	# a quick look first: no water near the foot within the image's size = nothing to mirror
	var near: Vector2 = rivers.field_at(Vector2(thing.global_position.x, line + height * 0.5))
	if not is_finite(near.x) or near.x > height * 0.5 + (right - left) * 0.5 + SAMPLE:
		return false
	var y: float = line + 1.0
	while y <= line + height:
		var x: float = left
		while x <= right:
			if rivers.field_at(Vector2(x, y)).x <= 0.0:
				return true
			x += SAMPLE
		y += SAMPLE
	return false


func _line_of(thing: Node2D) -> float:
	if thing.has_method("reflection_line"):
		return float(thing.call("reflection_line"))
	return thing.global_position.y


## The world rect the thing's sprites cover (rough; from their frames).
func _bounds_of(thing: Node2D) -> Rect2:
	var out: Rect2 = Rect2()
	var first: bool = true
	for sprite: Sprite2D in _sprites_of(thing):
		var rect: Rect2 = sprite.get_global_transform() * sprite.get_rect()
		out = rect if first else out.merge(rect)
		first = false
	return out


## Visible Sprite2D parts of a thing, in draw order; cached for 2 s (sprites appear and go: glow, swim layers).
func _sprites_of(thing: Node2D) -> Array[Sprite2D]:
	var id: int = thing.get_instance_id()
	var now: int = Time.get_ticks_msec()
	var cached: Dictionary = _parts.get(id, {}) as Dictionary
	if not cached.is_empty() and now - int(cached["t"]) < 2000:
		return cached["list"] as Array[Sprite2D]
	var list: Array[Sprite2D] = []
	_collect(thing, thing, list)
	_parts[id] = {"t": now, "list": list}
	return list


func _collect(node: Node, top: Node2D, list: Array[Sprite2D]) -> void:
	collect_parts(node, top, list, _skip)


## The Sprite2D parts under `node` that belong to the thing `top` (not to a nested registered thing), in draw order; `skip` filters.
static func collect_parts(node: Node, top: Node2D, list: Array[Sprite2D], skip: Callable) -> void:
	if node is Sprite2D and not bool(skip.call(node as Sprite2D)):
		list.append(node as Sprite2D)
	for child: Node in node.get_children():
		if child is SubViewport or child is CanvasLayer:
			continue
		if child != top and child is Node2D and (_where.has(child.get_instance_id()) or _moving.has(child as Node2D) or _pending.has(child as Node2D)):
			continue ## a thing of its own (a yard prop on a hut, a door spot ...)
		collect_parts(child, top, list, skip)


func _skip(sprite: Sprite2D) -> bool:
	return skip_part(sprite)


static func skip_part(sprite: Sprite2D) -> bool:
	var named: String = String(sprite.name).to_lower()
	if named.contains("shadow") or named.contains("swimunder") or named.contains("underwater") or named.contains("decal"):
		return true
	if sprite.z_index < 0 and sprite.z_as_relative:
		return true ## ground pieces (beds, footprints, yard ground) lie flat
	if not sprite.z_as_relative and sprite.z_index < 0:
		return true
	return false


# --- drawing (right before the frame is drawn, after the camera has moved) ----------------------------

func _draw_pass() -> void:
	var show: bool = _on and enabled and is_inside_tree()
	if not show:
		if _last_on:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			RenderingServer.global_shader_parameter_set("g_reflect_on", 0.0)
			_hide_from(0, 0)
			_last_on = false
		return
	var started: int = Time.get_ticks_usec()
	var viewport: Viewport = get_viewport()
	var transform: Transform2D = viewport.get_canvas_transform()
	transform.origin = transform.origin.round()
	var size: Vector2i = Vector2i(viewport.get_visible_rect().size.ceil())
	if _viewport.size != size:
		_viewport.size = size
	_viewport.canvas_transform = transform
	var inverse: Transform2D = transform.affine_inverse()
	var top_left: Vector2 = inverse * Vector2.ZERO
	var span: Vector2 = Vector2(size) / transform.get_scale()
	var rect_vec: Vector4 = Vector4(top_left.x, top_left.y, span.x, span.y)
	if not rect_vec.is_equal_approx(_last_reflect_rect):
		_last_reflect_rect = rect_vec
		RenderingServer.global_shader_parameter_set("g_reflect_rect", rect_vec)
	var used: int = 0
	var painted: int = 0
	var z: int = -4000
	var parent: RID = _root.get_canvas_item()
	# _active is already in draw order: farther-back things first, like the world draws them. Each thing owns a
	# fixed run of copies; resting things (trees, rocks, houses) are only redrawn every third frame.
	_frame += 1
	var full: bool = _fresh
	_fresh = false
	for k: int in range(_active.size()):
		var thing: Node2D = _active[k]
		var start: int = _slot_start[k]
		var cap: int = _slot_cap[k]
		var refresh: bool = full or _slot_moving[k] == 1 or (k + _frame) % 10 == 0
		if not is_instance_valid(thing) or not thing.is_inside_tree():
			for j: int in range(cap):
				_hide_item(start + j)
			continue
		var lag: Vector2 = drawn_offset(thing) if _slot_moving[k] == 1 else Vector2.ZERO
		var line: float = _line_of(thing) + lag.y
		var mirror: Transform2D = Transform2D(Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 2.0 * line))
		if refresh:
			var n: int = 0
			for sprite: Sprite2D in _sprites_of(thing):
				if n >= cap:
					break
				if not is_instance_valid(sprite) or sprite.texture == null or not sprite.is_visible_in_tree():
					continue
				var color: Color = _color_of(sprite, thing)
				if color.a <= 0.02:
					continue
				var slot: int = start + n
				var item: RID = _item(slot, parent)
				RenderingServer.canvas_item_clear(item)
				if _item_shown[slot] == 0:
					RenderingServer.canvas_item_set_visible(item, true)
					_item_shown[slot] = 1
				RenderingServer.canvas_item_set_transform(item, mirror * sprite.get_global_transform().translated(lag))
				z = -4000 + start + k + n
				if _item_z[slot] != z:
					RenderingServer.canvas_item_set_z_index(item, z)
					_item_z[slot] = z
				var material: Material = _material_of(sprite)
				var material_rid: RID = material.get_rid() if material != null else RID()
				if _item_material[slot] != material_rid:
					RenderingServer.canvas_item_set_material(item, material_rid)
					_item_material[slot] = material_rid
				RenderingServer.canvas_item_add_texture_rect_region(item, _dest(sprite), sprite.texture.get_rid(), _source(sprite), color)
				n += 1
			for j: int in range(n, cap):
				_hide_item(start + j)
		z = -4000 + start + k + cap
		var painters: Array = thing.call("reflection_painters") if painted < MAX_PAINTERS and thing.has_method("reflection_painters") else []
		for entry: Variant in painters:
			var spec: Dictionary = entry as Dictionary
			var source: CanvasItem = spec.get("source") as CanvasItem
			if source == null or not is_instance_valid(source) or not source.is_visible_in_tree():
				continue
			var painter: Node2D = _painter(painted)
			painter.visible = true
			painter.z_index = z
			painter.transform = mirror * source.get_global_transform().translated(lag)
			painter.material = _material_of(source)
			_painter_calls[painted] = spec.get("paint") as Callable
			painter.queue_redraw() ## drawn with the next frame's flush (the arm lags one frame: not visible in water)
			painted += 1
	used = (_slot_start[_active.size() - 1] + _slot_cap[_active.size() - 1]) if not _active.is_empty() else 0
	_hide_from(used, painted)
	drawn_items = used
	cost_usec = Time.get_ticks_usec() - started
	if not _last_on:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		RenderingServer.global_shader_parameter_set("g_reflect_on", 1.0)
		_last_on = true


func _item(index: int, parent: RID) -> RID:
	while _items.size() <= index:
		var item: RID = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, parent)
		RenderingServer.canvas_item_set_interpolated(item, false) ## copies are placed every frame: physics interpolation would draw them halfway between an old and a new place (ghosts)
		RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
		_items.append(item)
		_item_material.append(RID())
		_item_z.append(-99999)
		_item_shown.append(0)
	return _items[index]


func _painter(index: int) -> Node2D:
	while _painters.size() <= index:
		var painter: Node2D = Node2D.new()
		painter.z_as_relative = false
		painter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var slot: int = _painters.size()
		painter.draw.connect(func() -> void:
			var call: Callable = _painter_calls[slot]
			if call.is_valid():
				call.call(painter))
		_root.add_child(painter)
		_painters.append(painter)
		_painter_calls.append(Callable())
	return _painters[index]


func _hide_item(slot: int) -> void:
	if slot < _items.size() and _item_shown[slot] == 1:
		RenderingServer.canvas_item_set_visible(_items[slot], false)
		_item_shown[slot] = 0


func _hide_from(items: int, painters: int) -> void:
	for i: int in range(items, _items.size()):
		if _item_shown[i] == 1:
			RenderingServer.canvas_item_set_visible(_items[i], false)
			_item_shown[i] = 0
	for i: int in range(painters, _painters.size()):
		_painters[i].visible = false
		_painter_calls[i] = Callable()


func _material_of(sprite: CanvasItem) -> Material:
	var node: CanvasItem = sprite
	while node != null:
		if not node.use_parent_material:
			return node.material
		node = node.get_parent() as CanvasItem
	return null


## The sprite's tint as the world shows it, from the thing down to the sprite (the thing's own fade is ignored:
## a tree that turns see-through for a player behind it keeps a whole mirror image).
func _color_of(sprite: Sprite2D, top: Node2D) -> Color:
	var color: Color = sprite.self_modulate
	var node: Node = sprite
	while node != null and node is CanvasItem:
		var tint: Color = (node as CanvasItem).modulate
		if node == top:
			color *= Color(tint.r, tint.g, tint.b, 1.0)
			break
		color *= tint
		node = node.get_parent()
	return color


func _source(sprite: Sprite2D) -> Rect2:
	return part_source(sprite)


## The texture rect of the sprite's current frame.
static func part_source(sprite: Sprite2D) -> Rect2:
	var whole: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, sprite.texture.get_size())
	var frame: Vector2 = whole.size / Vector2(maxi(sprite.hframes, 1), maxi(sprite.vframes, 1))
	return Rect2(whole.position + frame * Vector2(sprite.frame_coords), frame)


func _dest(sprite: Sprite2D) -> Rect2:
	return part_dest(sprite)


## Where the sprite draws its frame in its own space (flips included).
static func part_dest(sprite: Sprite2D) -> Rect2:
	var rect: Rect2 = sprite.get_rect() ## the same rect Sprite2D draws (centring and pixel snapping included)
	if sprite.flip_h:
		rect.size.x = -rect.size.x
	if sprite.flip_v:
		rect.size.y = -rect.size.y
	return rect
