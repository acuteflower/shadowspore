class_name Interior
extends Node2D
## One interior (data/interiors.json, art tools/art_hut.py), built at its own slot in the pocket space far outside the world (`Interiors`), so the inside can
## be bigger than the outside. Everything is laid out in room pixels (x right, y down, origin at the top left of the room): the dark backdrop, the shell (floor,
## back wall, side walls), decals, furniture (sprites that sort with the people by their feet), the glowing parts (unlit second sheets), hanging things that swing
## (herbs, a lantern), animated things (the fire), a young tree whose crown sways, water dripping from the roof, moths round the glowing mushrooms, the lights
## (`InteriorLight`), sunbeams through the windows, drifting dust, the colliders of walls and furniture, the front lip with the doorway and the door.
## The camera stays on the room (`view_rect`), the world's tint is replaced by the room's own ambient colour (`ambient`).

const RAY_FRAMES: int = 3
const DRIP: Texture2D = preload("res://assets/interior/hut/drip.png")
const SPLASH: Texture2D = preload("res://assets/interior/hut/splash.png")
const DRIP_SOUND: AudioStream = preload("res://assets/audio/hut/drip.wav")
const DARK: Shader = preload("res://assets/shaders/interior_dark.gdshader")
const EDGE: Shader = preload("res://assets/shaders/interior_edge.gdshader")
const VEIL: Shader = preload("res://assets/shaders/room_veil.gdshader")
const VEIL_SOUND: AudioStream = preload("res://assets/audio/room_intro/veil_lift.wav")
const VEIL_TIME: float = 2.8 ## s the shadow smoke takes to lift out of a veiled room

var id: String = ""
var spec: Dictionary = {}
var size: Vector2 = Vector2(432, 312)
var door: Doorway ## the main door (the way out)
var neighbors: Array[Interior] = [] ## rooms that lie right next to this one (data `adjacent`): they are seen from here, share the camera and the dark round them
var veiled: bool = false ## data `veiled`: the room lies under shadow smoke until somebody steps in (`lift_veil`)
var revealed: bool = true
var lifting: bool = false
var _veil: ColorRect
var _veil_t: float = 0.0
var _veil_origin: Vector2 = Vector2.ZERO
var _veil_top: float = 0.0 ## the smoke reaches this far above the rect (hard edge) ...
var _veil_off: Vector2 = Vector2.ZERO ## ... and this far beyond its left and top sides (together with the soft edges): the veil's picture starts at -_veil_off
var _group_rect: Rect2 = Rect2()
var _fading: Array[Sprite2D] = [] ## props that fade out while they hide a player standing behind them (data prop `fades`: the tall pillars)
var _over_player: Array[Sprite2D] = [] ## wall pieces that lie over a player standing behind their foot (data `front` `over_player`)
var _has_group: bool = false
var _veil_sound: AudioStreamPlayer2D
var props: Dictionary = {} ## prop id -> Sprite2D
var _dir: String = ""
var _rays: Array[Sprite2D] = []
var _hanging: Array[Dictionary] = [] ## {node, sway, speed, phase}
var _anims: Array[Dictionary] = [] ## {sprite, frames, fps, time}
var _crowns: Array[Dictionary] = [] ## {trunk, crown, sway, phase}
var _drips: Array[Dictionary] = [] ## {pos, land, every, left}
var _glows: Dictionary = {} ## prop id -> its glow Sprite2D (follows the frame)
var _prop_lights: Dictionary = {} ## prop id -> its InteriorLight
var tree: Node2D ## the young tree that can be felled (a `HutTree`; typed loosely so the classes do not depend on each other in a circle), if the room has one
var pickups: Array[Interactable] = [] ## the `InteriorPickup`s: props that can be picked up (the hut's mushrooms)
var _fresh: bool = false ## the hut is renewed: every picture that has a counterpart in `fresh/` shows that one (tools/art_hut_fresh.py)
var _mushrooms: Array[Vector2] = []
var _moths: Node2D
var _back: ColorRect
var _smoke_back: bool = false
var _edge: ColorRect
var _time: float = 0.0


func setup(interior_id: String, data: Dictionary) -> void:
	id = interior_id
	spec = data
	name = "Interior_" + id
	y_sort_enabled = true
	_dir = String(data.dir)
	size = _vec(data.size)
	_backdrop()
	for item: Dictionary in data.shell as Array:
		var sprite: Sprite2D = _sprite_sorted(String(item.tex), _vec(item.pos)) if bool(item.get("sorted", false)) else _sprite(String(item.tex), _vec(item.pos), int(item.get("z", 0)))
		if bool(item.get("glow", false)):
			var glow_name: String = String(item.tex).replace(".png", "_glow.png")
			if ResourceLoader.exists(_dir + glow_name):
				var glow: Sprite2D = _sprite(glow_name, _vec(item.pos), int(item.get("z", 0)) + 1, true)
				glow.flip_h = sprite.flip_h
	for decal: Dictionary in data.get("decals", []) as Array:
		var d: Sprite2D = _sprite(String(decal.tex), _vec(decal.pos), int(decal.get("z", 0)))
		d.flip_h = bool(decal.get("flip", false))
		d.set_meta("sway", 0.05)
		d.set_meta("phase", _vec(decal.pos).x * 0.1)
		if String(decal.tex) == "web.png":
			_hanging.append({"node": d, "sway": 0.0, "speed": 0.0, "phase": 0.0, "skew": 0.04, "pivot": _vec(decal.pos)})
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Colliders"
	add_child(body)
	for wall: Array in data.get("walls", []) as Array:
		_box(body, Rect2(float(wall[0]), float(wall[1]), float(wall[2]), float(wall[3])))
	for prop: Dictionary in data.get("props", []) as Array:
		_prop(prop, body)
	for prop: Dictionary in data.get("props", []) as Array: ## what can be picked up or felled (story: renewing the hut)
		if prop.has("pickup"):
			var spot: InteriorPickup = InteriorPickup.new()
			spot.setup(self, String(prop.id), _vec(prop.pos), prop.pickup as Dictionary, int(prop.get("frame", 0)))
			add_child(spot)
			pickups.append(spot)
		if prop.has("fell"):
			_make_tree(prop)
	for item: Dictionary in data.get("hanging", []) as Array:
		_hang(item)
	for item: Dictionary in data.get("anims", []) as Array:
		_anim(item)
	for item: Dictionary in data.get("drips", []) as Array:
		_drips.append({"pos": _vec(item.pos), "land": _vec(item.land), "every": float(item.every), "left": randf_range(0.5, float(item.every))})
	for light: Dictionary in data.get("lights", []) as Array:
		_light(self, _vec(light.pos), Color(String(light.color)), int(light.radius), float(light.get("squash", 0.8)), float(light.energy), float(light.get("flicker", 0.0)), bool(light.get("day", false)))
	for ray: Dictionary in data.get("rays", []) as Array:
		_ray(_vec(ray.pos), float(ray.get("scale", 1.0)), _rays.size())
	_front()
	for item: Dictionary in data.get("doors", []) as Array: ## more doors (the locked doors at the ends of the hall's aisles): a picture on the wall and a Doorway that only rattles
		_door(item, "ÖFFNEN", false, false)
	if data.has("front"): ## the front wall of a room without a doorway (the hallway); a list for several pieces (the corridor: its arch at the top and the lip of the rooms' wall at the bottom)
		var walls_front: Array = data.front as Array if data.front is Array else [data.front]
		for wall: Dictionary in walls_front:
			var piece: Sprite2D = _sprite_sorted(String(wall.tex), _vec(wall.pos)) ## it sorts by its foot: she is behind its top edge when she stands at it
			if bool(wall.get("over_player", false)): ## a wall she walks through (the arch): over her while she is behind its foot, behind her in front of it
				_over_player.append(piece)
	_make_veil()
	if not bool(spec.get("fake", false)): ## a room that cannot be entered (only its shut door shows) has no dust and no moths
		_dust()
		_make_moths()
	for item: Dictionary in data.get("crows", []) as Array: ## a crow on the window sill that flies out when somebody comes near
		var crow: InteriorCrow = InteriorCrow.new()
		crow.setup(_vec(item.perch), _vec(item.exit))
		add_child(crow)
	if data.has("body"): ## the dead lumberjack of the cabin and his axe (story: the search for the lumberjack's hut)
		var corpse: LumberjackBody = LumberjackBody.new()
		corpse.name = "Lumberjack"
		corpse.position = _vec((data.body as Dictionary).pos)
		corpse.axe_at = _vec((data.body as Dictionary).axe)
		add_child(corpse)
	if data.has("bed_anchor"): ## story: "go to sleep" (the first night in the hut) and, later, "rest until morning" (the town quest's first night)
		for entry: Array in [["sleep", false], ["town_night", true]]:
			var spot: StorySpot = StorySpot.new()
			spot.name = "BedSpot" if not bool(entry[1]) else "BedRest"
			spot.label = "SCHLAFEN"
			spot.step = String(entry[0])
			spot.radius = 26.0
			spot.height = 48.0
			spot.position = _vec(data.bed_anchor) + Vector2(0, -4)
			var rest: bool = bool(entry[1])
			spot.use = func(player: Player) -> void:
				var world: Node = get_tree().get_first_node_in_group("world")
				if world is WorldLevel:
					(world as WorldLevel).start_sleep(player, rest)
			add_child(spot)


## The room together with the rooms next to it (global): what the camera frames and the dark and the creeping shadow go round.
## No crow on the sill (a test asks; the crow of Ellie's window is the room's `crows`).
func crows_none() -> bool:
	return not spec.has("crows")


func union_rect() -> Rect2:
	if _has_group:
		return _group_rect
	var rect: Rect2 = Rect2(global_position, size)
	for other: Interior in neighbors:
		rect = rect.merge(Rect2(other.global_position, other.size))
	return rect


## `other` lies right next to this room (the hallway under it): both frame the same view and share the dark round them.
## All the rooms that hang together (neighbours of neighbours) frame the same view: `Interiors` sets the rect of the whole group.
func set_group_rect(rect: Rect2) -> void:
	_group_rect = rect
	_has_group = true
	_fit_union()


func join(other: Interior) -> void:
	neighbors.append(other)
	other.neighbors.append(self)
	_fit_union()
	other._fit_union()


func _fit_union() -> void:
	if _back == null:
		return
	var rect: Rect2 = union_rect()
	var at: Vector2 = rect.position - global_position
	(_back.material as ShaderMaterial).set_shader_parameter("room", Vector4(_back.size.x / 2.0 - size.x / 2.0 + at.x, _back.size.y / 2.0 - size.y / 2.0 + at.y, rect.size.x, rect.size.y))
	_edge.position = at
	_edge.size = rect.size
	(_edge.material as ShaderMaterial).set_shader_parameter("rect_size", rect.size)


func _vec(raw: Variant) -> Vector2:
	var a: Array = raw as Array
	return Vector2(float(a[0]), float(a[1]))


func _texture(file: String) -> Texture2D:
	if _fresh and not file.begins_with("res://") and ResourceLoader.exists(_dir + "fresh/" + file):
		return load(_dir + "fresh/" + file) as Texture2D
	return load(file if file.begins_with("res://") else _dir + file) as Texture2D


## The texture of `file` for a sprite that remembers which file it shows (so the renewal can swap it later).
func _tex(sprite: Sprite2D, file: String) -> Texture2D:
	sprite.set_meta("file", file)
	return _texture(file)


func _sprite(file: String, at: Vector2, z: int, unlit: bool = false) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _tex(sprite, file)
	sprite.centered = false
	sprite.position = at
	sprite.z_index = z
	if unlit:
		sprite.material = Unlit.material()
	add_child(sprite)
	return sprite


## A picture in the wall between two rooms: it sorts with the people by its bottom edge, so somebody standing below it is in front of it and somebody above it behind it.
func _sprite_sorted(file: String, top_left: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _tex(sprite, file)
	sprite.centered = false
	var height: float = float(sprite.texture.get_height())
	sprite.offset = Vector2(0.0, -height)
	sprite.position = top_left + Vector2(0.0, height)
	add_child(sprite)
	return sprite


## The dark behind the room (the world's void quads would show through otherwise): bigger than any view.
func _backdrop() -> void:
	if not bool(spec.get("backdrop", true)): ## a room next door lies in the dark of its neighbour
		return
	_back = ColorRect.new()
	_smoke_back = bool(spec.get("smoke_backdrop", false)) ## all the free space round the rooms in the veil's own smoke (the same world-space field, so it flows into every veil without a seam)
	_back.size = Vector2(4600, 2800) if _smoke_back else Vector2(1200, 800) ## the smoke one is bigger than all the rooms next to each other (the hallway is a thousand px wide, the hall beyond the corridor lies far above)
	_back.position = size / 2.0 - _back.size / 2.0
	_back.z_index = -7
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	var smoke: bool = _smoke_back
	material.shader = VEIL if smoke else DARK
	material.set_shader_parameter("rect_size", _back.size)
	if smoke:
		material.set_shader_parameter("reveal", 0.0)
	else:
		material.set_shader_parameter("room", Vector4(_back.size.x / 2.0 - size.x / 2.0, _back.size.y / 2.0 - size.y / 2.0, size.x, size.y))
	_back.material = material
	add_child(_back)
	if smoke:
		material.set_shader_parameter("world", _back.global_position.round())
	_edge = ColorRect.new() ## the shadow creeping in from the edges of the room, over everything
	_edge.size = size
	_edge.z_index = 5
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge_material: ShaderMaterial = ShaderMaterial.new()
	edge_material.shader = EDGE
	edge_material.set_shader_parameter("rect_size", size)
	if spec.has("exit_door"):
		var leaf: Array = (spec.exit_door as Dictionary).leaf as Array
		edge_material.set_shader_parameter("door", Vector4(float(leaf[0]) - 4.0, float(leaf[1]), 60.0, size.y - float(leaf[1])))
	_edge.material = edge_material
	add_child(_edge)


func _box(body: StaticBody2D, rect: Rect2) -> void:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.position + rect.size / 2.0
	body.add_child(shape)


## A sprite that stands with its feet row on `pos` (so it sorts with the people).
func _standing(file: String, frames: int, frame: int, feet: float, at: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	var texture: Texture2D = _tex(sprite, file)
	sprite.texture = texture
	sprite.hframes = frames
	sprite.frame = frame
	var frame_size: Vector2 = Vector2(texture.get_width() / float(frames), texture.get_height())
	sprite.offset = Vector2(0.0, frame_size.y / 2.0 - feet)
	sprite.position = at
	add_child(sprite)
	return sprite


## Furniture and the like: an optional unlit glow sheet and light, a footprint, a crown that sways (the young tree).
func _prop(prop: Dictionary, body: StaticBody2D) -> void:
	var frames: int = int(prop.get("frames", 1))
	var feet: float = float(prop.get("feet", 0))
	var at: Vector2 = _vec(prop.pos)
	var sprite: Sprite2D = _standing(String(prop.tex), frames, int(prop.get("frame", 0)), feet, at)
	sprite.name = String(prop.id)
	props[String(prop.id)] = sprite
	if bool(prop.get("fades", false)):
		_fading.append(sprite)
	if prop.has("glow"):
		var glow: Sprite2D = Sprite2D.new()
		glow.texture = _tex(glow, String(prop.glow))
		glow.hframes = frames
		glow.frame = sprite.frame
		glow.offset = sprite.offset ## the glow sheet lies exactly on the picture (it is a child, which does not take the offset along)
		glow.material = Unlit.material()
		sprite.add_child(glow)
		_glows[String(prop.id)] = glow
	if prop.has("light"):
		var spec_light: Dictionary = prop.light as Dictionary
		_prop_lights[String(prop.id)] = _light(self, at + Vector2(0, -6), Color(String(spec_light.color)), int(spec_light.radius), 0.8, float(spec_light.energy), 0.12, false)
		if String(prop.id).begins_with("mushrooms"):
			_mushrooms.append(at + Vector2(0, -8))
	for i: int in (prop.get("seats", []) as Array).size(): ## places to sit (the benches of the hallway)
		var entry: Array = (prop.seats as Array)[i] as Array
		var seat: HallSeat = HallSeat.new()
		seat.name = "Seat_%s_%d" % [String(prop.id), i]
		seat.setup(at + Vector2(float(entry[0]), float(entry[1])), int(entry[2]), Vector2(float(entry[3]), float(entry[4])))
		add_child(seat)
	if prop.has("solid"):
		var s: Array = prop.solid as Array
		_box(body, Rect2(at.x + float(s[2]), at.y + float(s[3]), float(s[0]), float(s[1])))
	if prop.has("crown"):
		var c: Dictionary = prop.crown as Dictionary
		var crown: Sprite2D = _standing(String(c.tex), 1, 0, feet, at)
		crown.name = String(prop.id) + "_crown"
		if c.has("glow"):
			var cg: Sprite2D = Sprite2D.new()
			cg.texture = _tex(cg, String(c.glow))
			cg.material = Unlit.material()
			crown.add_child(cg)
		_crowns.append({"trunk": sprite, "crown": crown, "sway": float(c.get("sway", 0.03)), "phase": at.x * 0.07})


## The young tree growing out of the floor can be chopped down (`HutTree`): it takes the trunk and crown sprites of the prop.
func _make_tree(prop: Dictionary) -> void:
	var trunk: Sprite2D = props[String(prop.id)] as Sprite2D
	var crown: Sprite2D = null
	for entry: Dictionary in _crowns:
		if entry.trunk == trunk:
			crown = entry.crown as Sprite2D
	var fellable: HutTree = HutTree.new()
	fellable.name = "FellableTree"
	fellable.position = _vec(prop.pos)
	add_child(fellable)
	fellable.setup(self, trunk, crown, prop.fell as Dictionary, float(prop.get("feet", 0)))
	tree = fellable


## The hut is mended (story: the renewal): every picture that has a fresh counterpart is swapped (floor without holes, clean walls, mended furniture, a whole rug), the cobwebs are gone,
## the roof stops dripping and the stump of the felled tree is cleared away (only the hut has the fresh set).
func set_renewed(on: bool) -> void:
	if id != "hut" or not on or _fresh:
		return
	_fresh = true
	_reskin(self)
	_drips.clear()
	if tree != null:
		tree.call("clear_stump")


func _reskin(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Sprite2D and child.has_meta("file"):
			var sprite: Sprite2D = child as Sprite2D
			var file: String = String(sprite.get_meta("file"))
			sprite.texture = _texture(file)
			if file == "web.png":
				sprite.visible = false
			elif file.ends_with("_glow.png") and not file.begins_with("res://"): ## an old glow whose picture was redrawn without one is dropped
				sprite.visible = ResourceLoader.exists(_dir + "fresh/" + file) or not ResourceLoader.exists(_dir + "fresh/" + file.replace("_glow", ""))
		_reskin(child)


## A prop is gone for good (picked up): sprite, glow, light and the moths' interest.
func hide_prop(id: String) -> void:
	var sprite: Sprite2D = props.get(id) as Sprite2D
	if sprite != null:
		_mushrooms.erase(sprite.position + Vector2(0, -8))
		sprite.visible = false
	var light: InteriorLight = _prop_lights.get(id) as InteriorLight
	if light != null:
		light.visible = false
		light.enabled = false


## Things that hang from a cord or chain and swing (a Node2D at the point they hang from, rotated; the picture hangs under it).
func _hang(item: Dictionary) -> void:
	var pivot: Node2D = Node2D.new()
	pivot.position = _vec(item.pos)
	pivot.z_index = 2
	add_child(pivot)
	var sprite: Sprite2D = Sprite2D.new()
	var texture: Texture2D = _tex(sprite, String(item.tex))
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(-texture.get_width() / 2.0, 0.0)
	pivot.add_child(sprite)
	if item.has("glow"):
		var glow: Sprite2D = Sprite2D.new()
		glow.texture = _tex(glow, String(item.glow))
		glow.centered = false
		glow.position = sprite.position
		glow.material = Unlit.material()
		pivot.add_child(glow)
	if item.has("light"):
		var l: Dictionary = item.light as Dictionary
		_light(pivot, Vector2(0, float(l.get("drop", 30))), Color(String(l.color)), int(l.radius), 0.8, float(l.energy), 0.1, false)
	_hanging.append({"node": pivot, "sway": float(item.get("sway", 0.05)), "speed": float(item.get("speed", 1.0)), "phase": randf() * TAU, "skew": 0.0})


func _anim(item: Dictionary) -> void:
	var frames: int = int(item.frames)
	var sprite: Sprite2D = _standing(String(item.tex), frames, 0, float(item.feet), _vec(item.pos))
	if bool(item.get("unlit", false)):
		sprite.material = Unlit.material()
	sprite.z_index = 1
	_anims.append({"sprite": sprite, "frames": frames, "fps": float(item.fps), "time": randf()})


func _light(parent: Node, at: Vector2, color: Color, radius: int, squash: float, energy: float, flicker: float, day_only: bool) -> InteriorLight:
	var light: InteriorLight = InteriorLight.new()
	light.position = at
	light.glow_color = color
	light.radius = radius
	light.squash = squash
	light.base_energy = energy
	light.flicker = flicker
	light.day_only = day_only
	parent.add_child(light)
	return light


## A sunbeam from a window: additive, flickers between three frames, fades with the evening.
func _ray(at: Vector2, scale_k: float, index: int) -> void:
	var ray: Sprite2D = Sprite2D.new()
	ray.texture = _texture("rays.png")
	ray.hframes = RAY_FRAMES
	ray.centered = false
	ray.position = at
	ray.scale = Vector2(scale_k, scale_k)
	ray.z_index = 1
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	ray.material = mat
	ray.set_meta("seed", index * 0.7)
	add_child(ray)
	_rays.append(ray)


## The front lip of the south wall with the doorway, and the door (E): the way out (a room without a lip has none: only `doors`).
func _front() -> void:
	if not spec.has("front_y"):
		return
	var exit_spec: Dictionary = spec.exit_door as Dictionary
	var opens: bool = bool(exit_spec.get("opens", false))
	if opens: ## a room lies behind this wall: it sorts by its foot with the people (she is in front of it in the hallway, behind it in the room)
		_sprite_sorted("front.png", Vector2(0, float(spec.front_y)))
	else:
		_sprite("front.png", Vector2(0, float(spec.front_y)), 2)
	if ResourceLoader.exists(_dir + "front_glow.png"):
		_sprite("front_glow.png", Vector2(0, float(spec.front_y)), 3, true)
	_door(exit_spec, "ÖFFNEN" if opens else "VERLASSEN", not opens)


## A door of this room: its leaf (hinged on its left edge), what it needs (`needs`: a quest flag of the local player) and, with `opens`, that E only opens it (it stays open: the room next door is right behind it,
## `solid` is the door's blocker that goes away when it opens) instead of leading out into the world.
func _door(item: Dictionary, label: String, leaving: bool, main: bool = true) -> void:
	var leaf: Sprite2D = _sprite_sorted(String(item.get("tex", "door.png")), _vec(item.leaf)) if bool(item.get("opens", false)) or bool(item.get("sorted", false)) else _sprite(String(item.get("tex", "door.png")), _vec(item.leaf), 3)
	var way: Doorway = Doorway.new()
	way.interior_id = id
	way.leaving = leaving
	way.opens = bool(item.get("opens", false))
	way.needs = String(item.get("needs", ""))
	way.locked_text = String(item.get("locked_text", ""))
	way.label = label
	way.leaf = leaf
	way.reach_radius = 12.0
	way.prompt_height = 34.0
	way.position = _vec(item.pos)
	if item.has("solid"):
		var block: StaticBody2D = StaticBody2D.new()
		block.name = "DoorBlock"
		var box: Array = item.solid as Array
		_box(block, Rect2(float(box[0]), float(box[1]), float(box[2]), float(box[3])))
		add_child(block)
		way.blocker = block.get_child(0) as CollisionShape2D
	add_child(way)
	if main:
		door = way


## A veiled room lies under shadow smoke (the same smoke as the dark round the rooms and the map's unexplored land) that fills it completely, with a few pairs of eyes in it, until somebody steps in:
## `lift_veil` then pushes it back from where she stands, in a ragged front of burning dither (shader room_veil), and the eyes snap shut as the front reaches them.
func _make_veil() -> void:
	veiled = bool(spec.get("veiled", false))
	revealed = not veiled
	if not veiled:
		return
	_veil = ColorRect.new()
	var soft: Array = spec.get("veil_soft", [0, 0, 0, 0]) as Array ## left, top, right, bottom: on a side where the smoke meets the normal, visible room (a wall, the hallway's floor) the smoke thins out this many px in a ragged, glowing, dithered edge instead of ending in a straight line
	_veil_top = float(spec.get("veil_top", 0.0)) ## the smoke reaches this far above the room (the hallway: over the front walls of the rooms next to it)
	_veil_off = Vector2(0.0, _veil_top)
	var core: Vector2 = Vector2(size.x, float(spec.get("veil_height", size.y))) ## a room with its front wall at the bottom (`fake`): the smoke stops above the wall
	var veil_size: Vector2 = core + _veil_off
	_veil.size = veil_size
	_veil.position = -_veil_off
	_veil.z_index = int(spec.get("veil_z", 40)) ## over everything; a room next door lies under the lip of the wall between (z 2)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = VEIL
	material.set_shader_parameter("rect_size", veil_size)
	var eyes: PackedVector2Array = PackedVector2Array()
	for eye: Variant in spec.get("veil_eyes", []) as Array:
		eyes.append(_vec(eye) + _veil_off)
	material.set_shader_parameter("eye_count", eyes.size())
	while eyes.size() < 4:
		eyes.append(Vector2(-100, -100))
	material.set_shader_parameter("eyes", eyes)
	material.set_shader_parameter("reveal", 0.0)
	material.set_shader_parameter("origin", veil_size / 2.0)
	material.set_shader_parameter("soft", Vector4(float(soft[0]), float(soft[1]), float(soft[2]), float(soft[3])))
	if spec.has("veil_hole"): ## a piece of wall that belongs to the room next door (the corridor's arch) lies in this room's smoke: it stays free, with a ragged edge
		var hole: Array = spec.veil_hole as Array
		material.set_shader_parameter("hole", Vector4(float(hole[0]) + _veil_off.x, float(hole[1]) + _veil_off.y, float(hole[2]) + _veil_off.x, float(hole[3]) + _veil_off.y))
		material.set_shader_parameter("hole_soft", float(spec.get("veil_hole_soft", 0.0)))
	if spec.has("veil_cut"): ## the wall of the room next door lies over the first rows of this one: no smoke there (but in the doorway, once its door is open)
		var cut: Dictionary = spec.veil_cut as Dictionary
		material.set_shader_parameter("cut_y", float(cut.y) + _veil_off.y)
		material.set_shader_parameter("cut_soft", float(cut.get("soft", 0.0))) ## the smoke thins out ragged round the free wall too
		if cut.has("x"): ## the wall that stays free is only this wide (Ellie's room): the walls of the other rooms lie under the smoke too
			material.set_shader_parameter("cut_x", _vec(cut.x) + Vector2(_veil_off.x, _veil_off.x))
		material.set_shader_parameter("gap", _vec(cut.gap) + Vector2(_veil_off.x, _veil_off.x))
	_veil.material = material
	add_child(_veil)
	material.set_shader_parameter("world", (_veil.global_position).round())


## Somebody stepped in at `from` (global): the smoke lifts out of the room.
func lift_veil(from: Vector2) -> void:
	if revealed or lifting or _veil == null:
		return
	lifting = true
	_veil_t = 0.0
	_veil_origin = (from - global_position).clamp(Vector2.ZERO, size)
	var far: float = maxf(_veil_origin.distance_to(Vector2.ZERO), maxf(_veil_origin.distance_to(Vector2(size.x, 0.0)), maxf(_veil_origin.distance_to(Vector2(0.0, size.y)), _veil_origin.distance_to(size))))
	var material: ShaderMaterial = _veil.material as ShaderMaterial
	material.set_shader_parameter("origin", _veil_origin + _veil_off)
	material.set_shader_parameter("reach", far * 1.25 + 30.0)
	_veil_sound = AudioStreamPlayer2D.new()
	_veil_sound.stream = VEIL_SOUND
	_veil_sound.volume_db = -4.0
	_veil_sound.max_distance = 700.0
	_veil_sound.position = _veil_origin
	_veil_sound.finished.connect(_veil_sound.queue_free)
	add_child(_veil_sound)
	_veil_sound.play()


## The room is open at once (a saved game that already saw it).
func reveal_now() -> void:
	revealed = true
	lifting = false
	if _veil != null:
		_veil.visible = false


func _dust() -> void:
	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.position = size / 2.0 + Vector2(0, 10)
	motes.amount = 44
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(190, 100)
	motes.direction = Vector2(0.3, -1.0)
	motes.spread = 40.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 1.0
	motes.initial_velocity_max = 4.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 1.0
	motes.color = Color(1.0, 0.92, 0.75, 0.35)
	motes.z_index = 1
	motes.material = Unlit.material()
	add_child(motes)


## Two moths per glowing mushroom, drifting round it (unlit pixels).
func _make_moths() -> void:
	_moths = Node2D.new()
	_moths.z_index = 3
	_moths.material = Unlit.material()
	_moths.draw.connect(_draw_moths)
	add_child(_moths)


func _draw_moths() -> void:
	var night: float = TimeManager.night_amount()
	for i: int in _mushrooms.size():
		for k: int in 2:
			var t: float = _time * (0.7 + 0.25 * k) + i * 2.3 + k * 3.1
			var at: Vector2 = _mushrooms[i] + Vector2(cos(t) * 12.0 + sin(t * 2.3) * 4.0, sin(t * 1.3) * 7.0 - 6.0 + sin(t * 3.1) * 2.0)
			var flap: bool = int(_time * 14.0 + k) % 2 == 0
			var tone: Color = Color(0.82, 1.0, 0.95, 0.55 + 0.35 * night)
			_moths.draw_rect(Rect2(at.round(), Vector2(1, 1)), tone)
			_moths.draw_rect(Rect2((at + Vector2(-1.0 if flap else 1.0, -1.0 if flap else 0.0)).round(), Vector2(1, 1)), Color(tone, tone.a * 0.7))
			_moths.draw_rect(Rect2((at + Vector2(1.0 if flap else -1.0, -1.0 if flap else 0.0)).round(), Vector2(1, 1)), Color(tone, tone.a * 0.7))


const ANIMATE_RANGE: float = 900.0 ## px; rooms are up to ~260 px across

func _near_player(radius: float) -> bool:
	var near: Rect2 = Rect2(global_position, size).grow(radius) ## the room's rect, not its corner: the hallway is a thousand px wide
	for player: Player in Player.all:
		if is_instance_valid(player) and near.has_point(player.global_position): return true
	return false

## Rooms far from every player are not animated. `_time` keeps running, so anything read from it is right
## again on the first frame back; delta-driven states simply pause. No players at all: animate as before.
func _process(delta: float) -> void:
	_time += delta
	if _back != null and not _smoke_back: ## the dark behind the hut or the cabin only lies there while somebody is in it (it would cover the smoke of the rooms next to its slot)
		var manager: Interiors = get_parent() as Interiors
		if manager != null and manager.local_player() != null:
			_back.visible = manager.interior_at(manager.local_position()) == self
	if not Player.all.is_empty() and not _near_player(ANIMATE_RANGE): return
	if _veil != null and _veil.visible:
		var veil_material: ShaderMaterial = _veil.material as ShaderMaterial
		veil_material.set_shader_parameter("time", _time)
		var gap_open: bool = false ## a door of a room next door stands open (the shut doors of the `fake` rooms never do)
		for other: Interior in neighbors:
			if other.door != null and other.door.is_open:
				gap_open = true
		veil_material.set_shader_parameter("gap_open", 1.0 if gap_open else 0.0)
		if lifting:
			_veil_t += delta
			var k: float = clampf(_veil_t / VEIL_TIME, 0.0, 1.0)
			veil_material.set_shader_parameter("reveal", k * k * (3.0 - 2.0 * k) * 0.35 + k * 0.65) ## starts gently, then the smoke is driven out at a steady speed
			if _veil_t >= VEIL_TIME:
				reveal_now()
	for pillar: Sprite2D in _fading: ## a tall thing hides whoever stands behind it (north of its foot, within its width): it fades away, and comes back when she has stepped out from behind it
		var hides: bool = false
		for player: Player in Player.all:
			if is_instance_valid(player) and player.global_position.y < pillar.global_position.y and absf(player.global_position.x - pillar.global_position.x) < float(pillar.texture.get_width()) * 0.5 + 8.0 and pillar.global_position.y - player.global_position.y < 420.0:
				hides = true
		pillar.modulate.a = move_toward(pillar.modulate.a, 0.18 if hides else 1.0, delta * 4.0)
	for piece: Sprite2D in _over_player:
		var over: bool = false
		var foot: float = piece.global_position.y
		var left: float = piece.global_position.x
		for player: Player in Player.all:
			if is_instance_valid(player) and player.global_position.y < foot and player.global_position.x >= left and player.global_position.x < left + float(piece.texture.get_width()):
				over = true
		piece.z_index = 1 if over else 0
	var day: float = 1.0 - TimeManager.night_amount()
	for ray: Sprite2D in _rays:
		var seed_value: float = float(ray.get_meta("seed"))
		ray.frame = int(_time * 1.4 + seed_value * 3.0) % RAY_FRAMES
		ray.modulate.a = day * (0.7 + 0.3 * sin(_time * 0.7 + seed_value))
	for hang: Dictionary in _hanging:
		var node: Node2D = hang.node as Node2D
		if float(hang.sway) > 0.0:
			node.rotation = sin(_time * float(hang.speed) + float(hang.phase)) * float(hang.sway) + sin(_time * float(hang.speed) * 2.3 + float(hang.phase)) * float(hang.sway) * 0.3
		elif float(hang.skew) > 0.0:
			node.skew = sin(_time * 0.8 + node.position.x * 0.1) * float(hang.skew)
	for anim: Dictionary in _anims:
		anim.time = float(anim.time) + delta * float(anim.fps) * (0.85 + 0.3 * randf())
		(anim.sprite as Sprite2D).frame = int(anim.time) % int(anim.frames)
	for crown: Dictionary in _crowns: ## the young tree sways in the draught from the hole in the wall
		var s: float = sin(_time * 0.9 + float(crown.phase)) + 0.4 * sin(_time * 2.1 + float(crown.phase) * 2.0)
		(crown.crown as Sprite2D).skew = s * float(crown.sway)
		(crown.trunk as Sprite2D).skew = s * float(crown.sway) * 0.18
	for drip: Dictionary in _drips:
		drip.left = float(drip.left) - delta
		if float(drip.left) <= 0.0:
			drip.left = float(drip.every) * randf_range(0.8, 1.3)
			_fall(drip.pos as Vector2, drip.land as Vector2)
	for key: String in _glows.keys():
		var value: Variant = _glows[key]
		if not is_instance_valid(value): ## a felled tree frees its glow with its pivot
			_glows.erase(key)
			continue
		var glow: Sprite2D = value as Sprite2D
		glow.modulate.a = 0.85 + 0.15 * sin(_time * 1.7 + glow.get_instance_id() * 0.001)
	if _moths != null:
		_moths.queue_redraw()
	if _back != null:
		(_back.material as ShaderMaterial).set_shader_parameter("time", _time)
		(_back.material as ShaderMaterial).set_shader_parameter("night", TimeManager.night_amount())
		(_edge.material as ShaderMaterial).set_shader_parameter("time", _time)


## A drop of water forms on the roof, lets go, falls, splashes on the floor.
func _fall(from: Vector2, to: Vector2) -> void:
	var drop: Sprite2D = Sprite2D.new()
	drop.texture = DRIP
	drop.hframes = 4
	drop.position = from
	drop.z_index = 2
	drop.material = Unlit.material()
	add_child(drop)
	var tween: Tween = create_tween()
	tween.tween_callback(func() -> void: drop.frame = 0)
	tween.tween_interval(0.5)
	tween.tween_callback(func() -> void: drop.frame = 1)
	tween.tween_interval(0.4)
	tween.tween_callback(func() -> void: drop.frame = 2)
	tween.tween_property(drop, "position", to - Vector2(0, 6), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		drop.queue_free()
		_splash(to))


func _splash(at: Vector2) -> void:
	var splash: Sprite2D = Sprite2D.new()
	splash.texture = SPLASH
	splash.hframes = 5
	splash.position = at
	splash.z_index = -3
	splash.material = Unlit.material()
	add_child(splash)
	var tween: Tween = create_tween()
	tween.tween_method(func(f: float) -> void: splash.frame = clampi(int(f), 0, 4), 0.0, 4.99, 0.4)
	tween.tween_callback(splash.queue_free)
	var interiors: Interiors = get_parent() as Interiors
	if interiors != null and interiors.interior_at(interiors.local_position()) == self:
		var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sound.stream = DRIP_SOUND
		sound.volume_db = -10.0
		sound.max_distance = 400.0
		sound.position = at
		sound.finished.connect(sound.queue_free)
		add_child(sound)
		sound.play()


## The room as the camera shows it: at least a screen big, centred on the room, so a small room sits in the middle with dark around it.
func view_rect(view: Vector2) -> Rect2:
	var rect: Rect2 = union_rect()
	var rect_size: Vector2 = Vector2(maxf(rect.size.x, view.x), maxf(rect.size.y, view.y))
	return Rect2(rect.get_center() - rect_size / 2.0, rect_size)


## The tint of the world while you are in here (alpha 1 always): warm and dim by day, cold by night.
func ambient() -> Color:
	var a: Dictionary = spec.ambient as Dictionary
	return Color(String(a.day)).lerp(Color(String(a.night)), TimeManager.night_amount())


func entry_position() -> Vector2:
	return global_position + _vec(spec.entry)


func room_to_global(point: Vector2) -> Vector2:
	return global_position + point


func set_bed_frame(frame: int) -> void:
	var bed: Sprite2D = props.get("bed") as Sprite2D
	if bed != null:
		bed.frame = frame
	var glow: Sprite2D = _glows.get("bed") as Sprite2D
	if glow != null:
		glow.frame = frame
