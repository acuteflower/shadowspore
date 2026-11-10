class_name BuildMode
extends Node2D
## The local player's build mode (B): a see-through copy of the chosen piece follows the cursor (a pad: 40 px in front of her), snapped to the grid, tinted teal where
## it may stand and red where it may not (with the reason under the card), inside a ring of dots that marks the edge of the town's light. LMB sets it (hold it
## to lay a row of fences or plates), R mirrors, X switches to the demolish tool, V changes the category, the number keys and the wheel choose the piece, Escape / RMB
## / B leave. The host checks everything again (`TownManager.request_place`). The card is `BuildMenu`; this node draws the world part.

const GOOD: Color = Color("78f4e6")
const BAD: Color = Color("e0556e")
const RING: Color = Color("9af4e0")
const REPEAT_DELAY: float = 0.28
const REPEAT_EVERY: float = 0.09

var town: TownManager
var active: bool = false
var demolish: bool = false
var piece: String = ""
var flip: bool = false
var category: int = 0
var reason: String = ""
var pos: Vector2 = Vector2.ZERO
var target_id: int = -1 ## demolish: the piece under the cursor
var menu: BuildMenu

var _ghost: Sprite2D
var _textures: Dictionary = {}
var _time: float = 0.0
var _held: float = 0.0
var _last_placed: Vector2 = Vector2(INF, INF)
var _player: Player


func setup(owner_town: TownManager) -> void:
	town = owner_town
	name = "BuildMode"
	add_to_group("build_mode") ## the cursor (GameCursor) asks it what to show
	z_index = 90
	material = Unlit.material()
	_ghost = Sprite2D.new()
	_ghost.centered = false
	_ghost.material = Unlit.material()
	_ghost.visible = false
	add_child(_ghost)
	menu = BuildMenu.new()
	menu.name = "BuildMenu"
	add_child(menu)
	menu.setup(self)
	town.notice.connect(func(text: String, good: bool) -> void: menu.toast(text, good))


func categories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in TownRules.categories():
		if not TownRules.in_category(String((entry as Dictionary).id)).is_empty():
			out.append(entry as Dictionary)
	return out


func pieces_here() -> Array[String]:
	var cats: Array[Dictionary] = categories()
	return TownRules.in_category(String(cats[clampi(category, 0, cats.size() - 1)].id)) if not cats.is_empty() else ([] as Array[String])


func texture_of(id: String) -> Texture2D:
	if not _textures.has(id):
		var spec: Dictionary = TownRules.piece(id)
		_textures[id] = load("%s%s.png" % [TownStructure.DIR, String(spec.get("preview", spec.get("texture", id)))]) as Texture2D
	return _textures[id] as Texture2D


# ---------- switching ----------

func set_active(on: bool) -> void:
	if on == active:
		return
	if on:
		_player = town.local_player()
		if _player == null or _player.health.current <= 0.0 or _player.story_lock:
			return
		if not town.founded:
			menu.toast("NOCH KEINE STADT", false)
			return
		if piece == "" or not (piece in pieces_here()):
			var list: Array[String] = pieces_here()
			piece = list[0] if not list.is_empty() else ""
	active = on
	InputManager.build_open = on
	_ghost.visible = false
	demolish = false
	menu.visible = on
	_held = 0.0
	queue_redraw() ## the footprint and the ring of dots must go with the menu


func _exit_tree() -> void:
	InputManager.build_open = false


func select(id: String) -> void:
	piece = id
	demolish = false
	_last_placed = Vector2(INF, INF)


func set_demolish(on: bool) -> void:
	demolish = on
	_last_placed = Vector2(INF, INF)


func _choose_step(step: int) -> void:
	var list: Array[String] = pieces_here()
	if list.is_empty():
		return
	var at: int = list.find(piece)
	select(list[posmod(at + step, list.size())])


func _choose_category(step: int) -> void:
	var cats: Array[Dictionary] = categories()
	if cats.is_empty():
		return
	category = posmod(category + step, cats.size())
	var list: Array[String] = pieces_here()
	select(list[0] if not list.is_empty() else "")


# ---------- every frame ----------

func _process(delta: float) -> void:
	_time += delta
	if InputManager.build_toggle_pressed() or (active and Input.is_action_just_pressed("build")):
		set_active(not active)
	if not active:
		return
	if InputManager.ui_blocking or InputManager.menu_open or InputManager.map_open or _player == null or not is_instance_valid(_player) or _player.health.current <= 0.0 or _player.story_lock:
		set_active(false)
		return
	if Input.is_action_just_pressed("build_demolish"):
		set_demolish(not demolish)
	if Input.is_action_just_pressed("build_flip"):
		flip = not flip
	if Input.is_action_just_pressed("build_category"):
		_choose_category(1)
	var pick: int = InputManager.build_pick()
	var list: Array[String] = pieces_here()
	if pick >= 0 and pick < list.size():
		select(list[pick])
	elif InputManager.build_step() != 0:
		_choose_step(InputManager.build_step())
	var cursor: Vector2 = InputManager.aim_world_position() if InputManager.using_mouse else _player.global_position + _player.facing.normalized() * 40.0
	if demolish:
		target_id = _structure_at(cursor)
		reason = ""
		_ghost.visible = false
	else:
		target_id = -1
		_update_ghost(cursor)
	if Input.is_action_pressed("action_primary") and not menu.over_card():
		_held += delta
		if _held > REPEAT_DELAY and not demolish and _repeatable() and pos != _last_placed and reason == "":
			_place()
			_held = REPEAT_DELAY - REPEAT_EVERY
	else:
		_held = 0.0
	queue_redraw()


func _repeatable() -> bool:
	var spec: Dictionary = TownRules.piece(piece)
	return bool(spec.get("walk", false)) or piece == "fence"


func _update_ghost(cursor: Vector2) -> void:
	if piece == "":
		_ghost.visible = false
		return
	pos = TownRules.snapped_position(piece, cursor)
	reason = town.check_place(piece, pos, _player)
	var spec: Dictionary = TownRules.piece(piece)
	var tex: Texture2D = texture_of(piece)
	var frame: Array = spec.get("frame", [16, 16]) as Array
	_ghost.texture = tex
	_ghost.flip_h = flip
	_ghost.position = pos + Vector2(-float(frame[0]) / 2.0, -float(spec.get("feet", frame[1])))
	_ghost.modulate = Color(0.55, 1.0, 0.9, 0.62) if reason == "" else Color(1.0, 0.4, 0.45, 0.55)
	_ghost.visible = true


func _structure_at(cursor: Vector2) -> int:
	var best: int = -1
	var best_distance: float = 22.0
	for id: int in town.structures:
		var data: Dictionary = town.structures[id] as Dictionary
		if bool(TownRules.piece(String(data.p)).get("builtin", false)):
			continue
		var rect: Rect2 = town.rect_of(id)
		var distance: float = 0.0 if rect.grow(4.0).has_point(cursor) else cursor.distance_to(Vector2(clampf(cursor.x, rect.position.x, rect.end.x), clampf(cursor.y, rect.position.y, rect.end.y)))
		if distance < best_distance:
			best = id
			best_distance = distance
	return best


func _place() -> void:
	if reason != "":
		return
	_last_placed = pos
	town.request_place(piece, pos, flip)
	Sfx.at(self, "build_place", pos, -1.0, 0.04, 480.0)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("action_secondary"):
		set_active(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("action_primary"):
		if menu.over_card():
			menu.click()
		elif demolish:
			if target_id >= 0:
				town.request_demolish(target_id)
				Sfx.ui(self, "build_demolish", -3.0)
		elif piece != "":
			if reason == "":
				_place()
			else:
				menu.toast(reason, false)
		get_viewport().set_input_as_handled()


# ---------- the world part of the picture ----------

func _draw() -> void:
	if not active:
		return
	var view: Rect2 = _view_rect()
	_draw_territory(view)
	if demolish:
		if target_id >= 0:
			var rect: Rect2 = town.rect_of(target_id)
			draw_rect(rect, Color(BAD, 0.22))
			draw_rect(rect, Color(BAD, 0.9), false, 1.0)
			for k: int in 4:
				var corner: Vector2 = rect.position + Vector2(rect.size.x * float(k % 2), rect.size.y * float(k / 2))
				draw_line(corner + Vector2(-2, -2), corner + Vector2(2, 2), BAD, 1.0)
		return
	if piece == "":
		return
	var cursor: Vector2 = pos
	for id: int in town.structures:
		var door_zone: Rect2 = town.front_of(id)
		if door_zone.has_area() and view.intersects(door_zone):
			draw_rect(door_zone, Color(RING, 0.06)) ## doors of the town: nothing may be put in front of them
	_draw_grid(cursor)
	var rect: Rect2 = TownRules.foot_rect(piece, pos.x, pos.y)
	var color: Color = GOOD if reason == "" else BAD
	draw_rect(rect, Color(color, 0.16 + 0.05 * sin(_time * 5.0)))
	draw_rect(rect, Color(color, 0.85), false, 1.0)
	var front: Rect2 = TownRules.front_rect(piece, pos.x, pos.y) ## the ground in front of the door, which has to stay free
	if front.has_area():
		draw_rect(front, Color(color, 0.07))
		for k: int in int(front.size.x / 6.0) + 1:
			draw_rect(Rect2(front.position.x + float(k) * 6.0, front.end.y - 1.0, 3.0, 1.0), Color(color, 0.55))


func _view_rect() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	return Rect2(inverse * Vector2.ZERO, Vector2.ZERO).expand(inverse * get_viewport_rect().size).grow(24.0)


## The edge of the light as marching dots: where the group may not build any further.
func _draw_territory(view: Rect2) -> void:
	var circles: Array[Vector3] = town.circles()
	for i: int in circles.size():
		var c: Vector3 = circles[i]
		var center: Vector2 = Vector2(c.x, c.y)
		if not view.grow(c.z).has_point(center):
			continue
		var count: int = maxi(int(c.z * TAU / 5.0), 12)
		for k: int in count:
			var angle: float = TAU * float(k) / float(count)
			var point: Vector2 = center + Vector2.from_angle(angle) * c.z
			if not view.has_point(point):
				continue
			var inside_other: bool = false
			for j: int in circles.size():
				if j != i and point.distance_squared_to(Vector2(circles[j].x, circles[j].y)) < (circles[j].z - 1.0) * (circles[j].z - 1.0):
					inside_other = true
					break
			if inside_other:
				continue
			var phase: float = fposmod(angle * c.z / 5.0 - _time * 6.0, 4.0)
			if phase < 2.5:
				var pulse: float = 0.8 + 0.2 * sin(_time * 3.0 + angle * 3.0)
				draw_rect(Rect2(point.round() - Vector2(1.5, 1.5), Vector2(4, 4)), Color(0.04, 0.02, 0.1, 0.35)) ## a dark rim so the dots read on light grass
				draw_rect(Rect2(point.round() - Vector2(0.5, 0.5), Vector2(2, 2)), Color(RING, pulse))


## A faint dot grid round the cursor, only where it is lit: it shows where the snap cells are.
func _draw_grid(center: Vector2) -> void:
	var grid: float = TownRules.snap_of(piece)
	var base: Vector2 = (center / grid).round() * grid
	for y: int in range(-4, 5):
		for x: int in range(-6, 7):
			var p: Vector2 = base + Vector2(x, y) * grid
			if not town.in_territory(p):
				continue
			var fade: float = 1.0 - clampf(p.distance_to(center) / 80.0, 0.0, 1.0)
			if fade > 0.0:
				draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Color(RING, 0.35 * fade))
