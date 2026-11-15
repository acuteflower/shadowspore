class_name SunShadows
extends Node2D
## Cast shadows from the sun (and faintly from the moon) for every registered thing: Ellie and other players, settlers,
## animals, trees, bushes, rocks, buildings (docs/sonnenschatten.md). Cosmetic and local on every peer.
##
## Same registry as the mirror images (`WaterReflections.watch`). A few times a second the things whose shadow can reach
## the view are chosen (at most `MAX_ITEMS` sprite copies, nearest first). Right before every draw each visible Sprite2D
## part is copied into a SubViewport the size of the view as a solid silhouette, sheared about the thing's foot line by
## the sun: a point h px above the feet lands at feet + `cast` * h. Resting things are re-sheared round robin (every
## `ROUND` frames), walking ones every frame. A quad right above the ground layers multiplies the ground with a cool tone
## where the buffer holds a silhouette (sun_shadow.gdshader). By day the sun moves from east (shadows west, long) over
## the south (short shadows to the north) to the west; at night the moon throws faint ones the same way.
## Nothing in rooms, the mine, or while the sun and moon are too weak: then the buffer does not render at all.

const MAX_ITEMS: int = 380 ## sprite copies at most
const REBUILD: float = 0.25 ## s between choosing the casters
const ROUND: int = 6 ## resting things are re-sheared every ROUND frames (the sun moves slowly)
const TALL: float = 220.0 ## px: how tall a caster may be (how far outside the view a shadow can come from)
const DAWN: float = 0.21 ## time of day the sun stands on the eastern horizon ...
const DUSK: float = 0.79 ## ... and on the western one
const MIN_STRENGTH: float = 0.02
const FLORA_UNIFORMS: PackedStringArray = ["frame_size", "pivot_row", "amount", "flutter", "cell_w", "origin", "phase_seed"]
const ROWS_UNIFORMS: PackedStringArray = ["pivot_row", "dir", "amount", "flutter", "speed", "cell_w", "wind", "time"]
const SWAY_STEP: float = 0.004 ## radians of sway before a copy is re-angled (about half a pixel at a crown's height)
const SUN_SIDE: float = 0.65 ## how strongly the sun's side of a thing is warmed and the far side cooled (day_sun_side)
const FORESHORTEN: float = 0.62 ## north-south distances on the ground look this much shorter in the 3/4 view

static var current: SunShadows

var enabled: bool = true
var strength: float = 0.0 ## 0..1 how dark a full shadow is right now
var cast: Vector2 = Vector2(0.0, -0.4) ## where a point 1 px above the feet throws its shadow (px)
var cost_usec: int = 0 ## main-thread time of the last drawing pass (for checks)
var drawn_items: int = 0
var cost_avg: float = 0.0 ## the same, smoothed over about 30 passes
var swayed_items: int = 0 ## copies only re-angled in the last pass (wind sway)

var _viewport: SubViewport
var _root: Node2D
var _overlay: Polygon2D
var _overlay_material: ShaderMaterial
var _silhouette: ShaderMaterial
var _items: Array[RID] = []
var _item_shown: PackedByteArray = []
var _active: Array[Node2D] = []
var _slot_start: PackedInt32Array = []
var _slot_cap: PackedInt32Array = []
var _slot_moving: PackedByteArray = []
var _slot_dirty: PackedByteArray = [] ## 1 = (re)drawn in the next pass whatever the round robin says
var _slot_sway: PackedByteArray = [] ## 1 = swings in the wind (crowns, bushes): its copies are re-angled every frame
var _slot_sprite: Array = [] ## per copy slot: the Sprite2D it copies (untyped: it may be freed meanwhile)
var _slot_angle: PackedFloat32Array = [] ## per copy slot: skew + rotation of its sprite when it was last placed
var _item_mat: Array[RID] = [] ## per copy slot: the silhouette material it draws with
var _sil_mats: Dictionary = {} ## instance id of a caster's wind material -> {"src": ShaderMaterial, "mat": ShaderMaterial, "rows": bool, "t": msec}
var _flora_shader: Shader
var _rows_shader: Shader
var _owner: PackedInt64Array = [] ## per copy slot: the instance id that owns it (0 = free)
var _alloc: Dictionary = {} ## instance id -> Vector2i(first slot, slot count): a thing keeps its copies while it stays chosen
var _parts: Dictionary = {} ## instance id -> {"t": msec, "list": Array[Sprite2D]}
var _wait: float = 0.0
var _frame: int = 0
var _on: bool = false
var _last_on: bool = false


func _ready() -> void:
	current = self
	name = "SunShadows"
	z_as_relative = false
	z_index = -5 ## above ground (-10), decals (-9), relief and meadow details (-8), water (-7), river glow (-6); below all that stands
	_viewport = SubViewport.new()
	_viewport.name = "ShadowBuffer"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = Vector2i(640, 360)
	add_child(_viewport)
	_root = Node2D.new()
	_root.name = "Casters"
	_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_root)
	_silhouette = ShaderMaterial.new()
	_silhouette.shader = load("res://assets/shaders/shadow_silhouette.gdshader") as Shader
	_flora_shader = load("res://assets/shaders/shadow_silhouette_flora.gdshader") as Shader
	_rows_shader = load("res://assets/shaders/shadow_silhouette_rows.gdshader") as Shader
	_overlay = Polygon2D.new()
	_overlay.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_overlay.name = "Shade"
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = load("res://assets/shaders/sun_shadow.gdshader") as Shader
	_overlay_material.set_shader_parameter("shadow_tex", _viewport.get_texture())
	_overlay.material = _overlay_material
	_overlay.visible = false
	add_child(_overlay)
	RenderingServer.frame_pre_draw.connect(_draw_pass)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("g_sun_side", Vector2.ZERO)
	if RenderingServer.frame_pre_draw.is_connected(_draw_pass):
		RenderingServer.frame_pre_draw.disconnect(_draw_pass)
	for item: RID in _items:
		RenderingServer.free_rid(item)
	_items.clear()
	if current == self:
		current = null


## Where the shadow of a point 1 px above the ground falls, for the sun at `time` (0..1 of the day). Long and to the west
## in the morning, short and to the north (up the screen) at noon, long and to the east in the evening.
static func sun_cast(time: float) -> Vector2:
	var u: float = clampf((time - DAWN) / (DUSK - DAWN), 0.0, 1.0)
	return path_cast(u)


## The same for any light crossing the sky from east (`run` 0) to west (`run` 1), e.g. the moon over the night.
static func path_cast(run: float) -> Vector2:
	var angle: float = PI * clampf(run, 0.0, 1.0)
	var elevation: float = deg_to_rad(lerpf(7.0, 56.0, sin(angle)))
	var length: float = clampf(0.85 / tan(elevation), 0.42, 2.3)
	return Vector2(-cos(angle), -FORESHORTEN * sin(angle)) * length ## north on the ground is foreshortened in the 3/4 view


## Called every frame by DayNight. `sun` = DayNight's sun (weather and Hexenwald included), `golden` the golden hour,
## `night` 0..1 and `moon` TimeManager.moon_light().
func follow(indoors: bool, sun: float, golden: float, night: float, moon: float) -> void:
	enabled = bool(GameSettings.get_value("sun_shadows"))
	var t: float = TimeManager.time_of_day
	var sun_k: float = 0.0 if indoors else clampf(sun * 1.4, 0.0, 1.0) * 0.86
	var moon_run: float = clampf(fposmod(t - 0.78, 1.0) / 0.462, 0.0, 1.0)
	var lit_part: float = 0.5 - 0.5 * cos(TAU * TimeManager.moon_phase())
	var moon_k: float = 0.0 if indoors else night * lit_part * clampf((moon - 0.6) * 2.0, 0.0, 1.0) * 0.32
	if WeatherManager.current != null:
		moon_k *= WeatherManager.current.sunlight() ## clouds hide the moon as they hide the sun
	var tone: Color
	if sun_k >= moon_k:
		strength = sun_k
		cast = sun_cast(t)
		tone = Color(0.44, 0.5, 0.68).lerp(Color(0.42, 0.4, 0.66), golden) ## the evening's shadows turn blue-violet
	else:
		strength = moon_k
		cast = path_cast(moon_run)
		tone = Color(0.5, 0.56, 0.82)
	# the sun side on the things themselves (daylight.gdshaderinc day_sun_side): where the light comes from across the screen
	var across: float = 0.0 if cast.length_squared() < 0.0001 else clampf(-cast.x / cast.length(), -1.0, 1.0)
	var side_k: float = 0.0
	if enabled and sun_k >= moon_k:
		side_k = clampf(sun_k / 0.86, 0.0, 1.0) * SUN_SIDE
	RenderingServer.global_shader_parameter_set("g_sun_side", Vector2(across, side_k))
	_overlay_material.set_shader_parameter("tone", Vector3(tone.r, tone.g, tone.b))
	_overlay_material.set_shader_parameter("strength", strength)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REBUILD
	_rebuild()


func _view_rect() -> Rect2:
	var viewport: Viewport = get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()


## Chooses the casters: everything registered whose shadow can reach the view, nearest to the middle first.
func _rebuild() -> void:
	_active.clear()
	_on = enabled and strength > MIN_STRENGTH and is_inside_tree()
	if not _on:
		return
	WaterReflections.settle()
	var view: Rect2 = _view_rect()
	var reach: Rect2 = view.merge(Rect2(view.position - cast * TALL, view.size)).grow(24.0)
	reach = reach.merge(Rect2(view.position, view.size + Vector2(0.0, 24.0)))
	var middle: Vector2 = view.get_center()
	var found: Array[Node2D] = WaterReflections.things_in(reach)
	found.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(middle) < b.global_position.distance_squared_to(middle))
	var budget: int = Quality.scaled(MAX_ITEMS, "shadow_items", 40) ## graphics level
	for thing: Node2D in found:
		var cost: int = _sprites_of(thing).size()
		if cost == 0 or cost > budget:
			continue
		budget -= cost
		_active.append(thing)
		if budget <= 0:
			break
	# every thing keeps the copy slots it had (only new ones are drawn at once, the rest follow round robin)
	var keep: Dictionary = {}
	for thing: Node2D in _active:
		if thing is FirTree and (thing as FirTree).is_falling():
			_parts.erase(thing.get_instance_id()) ## the toppling part is made of new sprites
		keep[thing.get_instance_id()] = _sprites_of(thing).size()
	for id: Variant in _alloc.keys():
		var run: Vector2i = _alloc[id]
		if int(keep.get(id, -1)) != run.y:
			_release(run)
			_alloc.erase(id)
	_slot_start.resize(_active.size())
	_slot_cap.resize(_active.size())
	_slot_moving.resize(_active.size())
	_slot_dirty.resize(_active.size())
	_slot_sway.resize(_active.size())
	for k: int in range(_active.size()):
		var id: int = _active[k].get_instance_id()
		var fresh: bool = not _alloc.has(id)
		if fresh:
			_alloc[id] = Vector2i(_claim(id, int(keep[id])), int(keep[id]))
		var run: Vector2i = _alloc[id]
		_slot_start[k] = run.x
		_slot_cap[k] = run.y
		var thing: Node2D = _active[k]
		var falling: bool = thing is FirTree and (thing as FirTree).is_falling()
		_slot_moving[k] = 1 if falling or WaterReflections.is_moving(thing) else 0
		_slot_dirty[k] = 1 if fresh else 0
		_slot_sway[k] = 1 if thing is FirTree or thing is Bush or _sways(thing) else 0
	_on = not _active.is_empty()
	var now: int = Time.get_ticks_msec()
	for id: Variant in _parts.keys(): ## forget things that left long ago
		if now - int((_parts[id] as Dictionary)["t"]) > 6000:
			_parts.erase(id)
	for id: Variant in _sil_mats.keys():
		if now - int((_sil_mats[id] as Dictionary)["t"]) > 6000:
			_sil_mats.erase(id)


## Any part of `thing` that sways through a wind shader (its copies follow it every frame).
func _sways(thing: Node2D) -> bool:
	return _kinds_of(thing).count(0) != _kinds_of(thing).size()


## 0 = a plain picture, 1 = flora_wind (small plants), 2 = sway_rows (rags, garden plants, the crow tree).
func _wind_kind(sprite: Sprite2D) -> int:
	var material: ShaderMaterial = _wind_material(sprite)
	if material == null:
		return 0
	var path: String = material.shader.resource_path
	if path.ends_with("flora_wind.gdshader"):
		return 1
	if path.ends_with("sway_rows.gdshader"):
		return 2
	return 0


func _wind_material(sprite: Sprite2D) -> ShaderMaterial:
	var item: CanvasItem = sprite
	while item != null and item.use_parent_material:
		item = item.get_parent() as CanvasItem
	if item == null or not (item.material is ShaderMaterial):
		return null
	var material: ShaderMaterial = item.material as ShaderMaterial
	return material if material.shader != null else null


## The silhouette material a part draws with: the plain one, or a copy of its wind (same uniforms, so the shadow bends
## exactly as the picture does). One per caster material, kept while it is used.
func _material_for(sprite: Sprite2D, kind: int, plain: RID) -> RID:
	if kind == 0:
		return plain
	var source: ShaderMaterial = _wind_material(sprite)
	var id: int = source.get_instance_id()
	var entry: Dictionary = _sil_mats.get(id, {}) as Dictionary
	if entry.is_empty():
		var made: ShaderMaterial = ShaderMaterial.new()
		made.shader = _flora_shader if kind == 1 else _rows_shader
		for uniform: String in FLORA_UNIFORMS if kind == 1 else ROWS_UNIFORMS: ## set once by their owners (wind/time: every frame in the pass)
			var value: Variant = source.get_shader_parameter(uniform)
			if value != null:
				made.set_shader_parameter(uniform, value)
		entry = {"src": source, "mat": made, "rows": kind == 2, "t": 0}
		_sil_mats[id] = entry
	var mat: ShaderMaterial = entry["mat"] as ShaderMaterial
	entry["t"] = Time.get_ticks_msec()
	return mat.get_rid()


## The first of `count` free copy slots in a row (first fit), now owned by `id`.
func _claim(id: int, count: int) -> int:
	var run: int = 0
	var at: int = 0
	while at < _owner.size():
		if _owner[at] == 0:
			run += 1
			if run == count:
				break
		else:
			run = 0
		at += 1
	var start: int = at - run + 1 if run == count and count > 0 else _owner.size() - run
	while _owner.size() < start + count:
		_owner.append(0)
	for i: int in range(start, start + count):
		_owner[i] = id
	return start


## Frees a thing's copy slots and hides them.
func _release(run: Vector2i) -> void:
	for i: int in range(run.x, run.x + run.y):
		if i < _owner.size():
			_owner[i] = 0
		_hide_item(i)


## Solid Sprite2D parts of a thing (the mirror's choice minus glow and light sprites), cached for 2 s.
func _sprites_of(thing: Node2D) -> Array[Sprite2D]:
	var id: int = thing.get_instance_id()
	var now: int = Time.get_ticks_msec()
	var cached: Dictionary = _parts.get(id, {}) as Dictionary
	if not cached.is_empty() and now - int(cached["t"]) < 2000:
		return cached["list"] as Array[Sprite2D]
	var list: Array[Sprite2D] = []
	WaterReflections.collect_parts(thing, thing, list, _skip)
	var kinds: PackedByteArray = []
	for sprite: Sprite2D in list:
		kinds.append(_wind_kind(sprite))
	_parts[id] = {"t": now, "list": list, "kinds": kinds}
	return list


## The wind kinds of a thing's parts (same order as `_sprites_of`).
func _kinds_of(thing: Node2D) -> PackedByteArray:
	_sprites_of(thing)
	return (_parts[thing.get_instance_id()] as Dictionary)["kinds"] as PackedByteArray


func _skip(sprite: Sprite2D) -> bool:
	if WaterReflections.skip_part(sprite):
		return true
	var named: String = String(sprite.name).to_lower()
	return named.contains("glow") or named.contains("light") or named.contains("halo") or named.contains("ripple") or named.contains("shine")


## The shadow transform of a thing standing at `foot`: a point h px above the feet moves by `by` * h, and the sprite's
## width is turned to lie across the shadow (a flat sprite has no depth: lit from the side it would cast a thin line;
## turned towards the light like a billboard, a round thing such as a tree, a bush or Ellie keeps its width).
static func shear(foot: Vector2, by: Vector2) -> Transform2D:
	var ground: Vector2 = Vector2(by.x, by.y / FORESHORTEN)
	var side: Vector2 = Vector2(1.0, 0.0) if ground.length_squared() < 0.0001 else Vector2(-ground.y, ground.x).normalized()
	if side.x < 0.0:
		side = -side
	side.y *= FORESHORTEN
	var x_axis: Vector2 = side
	var y_axis: Vector2 = -by
	var origin: Vector2 = foot - x_axis * foot.x - y_axis * foot.y
	return Transform2D(x_axis, y_axis, origin)


func _draw_pass() -> void:
	var show: bool = _on and enabled and is_inside_tree()
	if not show:
		if _last_on:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_overlay.visible = false
			_hide_from(0)
			_alloc.clear()
			_owner.fill(0)
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
	var top_left: Vector2 = transform.affine_inverse() * Vector2.ZERO
	var span: Vector2 = Vector2(size) / transform.get_scale()
	_overlay_material.set_shader_parameter("shadow_rect", Vector4(top_left.x, top_left.y, span.x, span.y))
	var area: Rect2 = Rect2(top_left, span).grow(48.0)
	_overlay.polygon = PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	_frame += 1
	swayed_items = 0
	var parent: RID = _root.get_canvas_item()
	var material: RID = _silhouette.get_rid()
	for id: Variant in _sil_mats: ## swaying pictures: their wind and clock change every frame
		var entry: Dictionary = _sil_mats[id]
		if bool(entry["rows"]) and is_instance_valid(entry["src"]):
			var source: ShaderMaterial = entry["src"] as ShaderMaterial
			var mat: ShaderMaterial = entry["mat"] as ShaderMaterial
			mat.set_shader_parameter("wind", source.get_shader_parameter("wind"))
			mat.set_shader_parameter("time", source.get_shader_parameter("time"))
	for k: int in range(_active.size()):
		var thing: Node2D = _active[k]
		var start: int = _slot_start[k]
		var cap: int = _slot_cap[k]
		var moving: bool = _slot_moving[k] == 1
		if not (_slot_dirty[k] == 1 or moving or (k + _frame) % ROUND == 0):
			if _slot_sway[k] == 1 and (k + _frame) % 2 == 0 and is_instance_valid(thing):
				_follow_sway(thing, start, cap) ## only the angle: crowns and bushes swing in the wind and when hit
			continue
		_slot_dirty[k] = 0
		if not is_instance_valid(thing) or not thing.is_inside_tree() or not thing.is_visible_in_tree():
			for j: int in range(cap):
				_hide_item(start + j)
			continue
		var lag: Vector2 = WaterReflections.drawn_offset(thing) if moving else Vector2.ZERO ## the picture is drawn interpolated
		var bend: Transform2D = shear(thing.global_position + lag, cast)
		var falling: bool = thing is FirTree and (thing as FirTree).is_falling()
		var n: int = 0
		var kinds: PackedByteArray = _kinds_of(thing)
		var part: int = -1
		for sprite: Sprite2D in _sprites_of(thing):
			part += 1
			if n >= cap:
				break
			if not is_instance_valid(sprite) or sprite.texture == null or not sprite.is_visible_in_tree():
				continue
			var slot: int = start + n
			var item: RID = _item(slot, parent, material)
			RenderingServer.canvas_item_clear(item)
			var wanted: RID = _material_for(sprite, kinds[part], material)
			if _item_mat[slot] != wanted:
				RenderingServer.canvas_item_set_material(item, wanted)
				_item_mat[slot] = wanted
			_slot_sprite[slot] = sprite
			_slot_angle[slot] = sprite.skew + sprite.rotation
			if _item_shown[slot] == 0:
				RenderingServer.canvas_item_set_visible(item, true)
				_item_shown[slot] = 1
			RenderingServer.canvas_item_set_transform(item, bend * sprite.get_global_transform().translated(lag))
			RenderingServer.canvas_item_add_texture_rect_region(item, WaterReflections.part_dest(sprite), sprite.texture.get_rid(), WaterReflections.part_source(sprite), _feet_color(thing, sprite, falling))
			n += 1
		for j: int in range(n, cap):
			_hide_item(start + j)
	var used: int = 0
	for cap: int in _slot_cap:
		used += cap
	drawn_items = used
	cost_usec = Time.get_ticks_usec() - started
	cost_avg = lerpf(cost_avg, float(cost_usec), 0.033)
	if not _last_on:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_overlay.visible = true
		_last_on = true


## Where the caster's feet lie in the sprite's own space, packed into the draw colour for the silhouette shaders (they drop
## every pixel below it: below the feet the shear would throw it forwards). A toppling piece lies on its side: no cut.
func _feet_color(thing: Node2D, sprite: Sprite2D, falling: bool) -> Color:
	var feet: float = 400.0
	if not falling:
		feet = (sprite.get_global_transform().affine_inverse() * thing.global_position).y
	return Color(clampf(feet, -490.0, 490.0) / 1000.0 + 0.5, 1.0, 1.0, 1.0)


## Re-angles the copies of a resting thing whose parts sway (node skew/rotation from WorldWind, hits, a fall): cheap, the
## copies keep their picture, only their transform follows.
func _follow_sway(thing: Node2D, start: int, cap: int) -> void:
	if not thing.is_inside_tree():
		return
	var bend: Transform2D
	var bent: bool = false
	for j: int in range(cap):
		var slot: int = start + j
		if slot >= _items.size() or _item_shown[slot] == 0:
			continue
		var held: Variant = _slot_sprite[slot]
		if not is_instance_valid(held):
			continue
		var sprite: Sprite2D = held as Sprite2D
		var angle: float = sprite.skew + sprite.rotation
		if absf(angle - _slot_angle[slot]) < SWAY_STEP:
			continue ## not enough to move the shadow by a pixel
		_slot_angle[slot] = angle
		if not bent:
			bend = shear(thing.global_position, cast)
			bent = true
		RenderingServer.canvas_item_set_transform(_items[slot], bend * sprite.get_global_transform())
		swayed_items += 1


func _item(index: int, parent: RID, material: RID) -> RID:
	while _items.size() <= index:
		var item: RID = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, parent)
		RenderingServer.canvas_item_set_interpolated(item, false) ## copies are placed every frame: physics interpolation would draw them halfway between an old and a new place (ghosts)
		RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
		RenderingServer.canvas_item_set_material(item, material)
		_items.append(item)
		_item_shown.append(0)
		_item_mat.append(material)
		_slot_angle.append(0.0)
		_slot_sprite.append(null)
	return _items[index]


func _hide_item(slot: int) -> void:
	if slot < _items.size() and _item_shown[slot] == 1:
		RenderingServer.canvas_item_set_visible(_items[slot], false)
		_item_shown[slot] = 0


func _hide_from(items: int) -> void:
	for i: int in range(items, _items.size()):
		if _item_shown[i] == 1:
			RenderingServer.canvas_item_set_visible(_items[i], false)
			_item_shown[i] = 0
