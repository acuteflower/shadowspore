class_name BuildMode
extends Node2D
## The local player's build mode (B): a see-through copy of the chosen piece follows the cursor (a pad: 40 px in front of her), snapped to the grid, tinted teal where
## it may stand and red where it may not (with the reason under the card), inside a ring of dots that marks the edge of the town's light. LMB sets it (hold it
## to lay a row of fences or plates), R mirrors, X switches to the demolish tool, T to the move tool (LMB lifts a piece, LMB sets it down again, R mirrors it,
## RMB puts it back; free of cost), V changes the category, the number keys and the wheel choose the piece, Escape / RMB / B leave (on a pad the demolish button
## goes round build -> demolish -> move). The host checks everything again (`TownManager.request_place` / `request_move`). The card is `BuildMenu`; this node
## draws the world part.

const GOOD: Color = Color("78f4e6")
const BAD: Color = Color("e0556e")
const RING: Color = Color("9af4e0")
const GOLD_HAND: Color = Color("d9b25f") ## the move tool's marks
const REPEAT_DELAY: float = 0.28
const REPEAT_EVERY: float = 0.09

var town: TownManager
var active: bool = false
var demolish: bool = false
var moving: bool = false ## the move tool
var carry_id: int = -1 ## move tool: the piece that has been lifted and follows the cursor (-1: none, pick one)
var piece: String = ""
var flip: bool = false
var category: int = 0
var reason: String = ""
var pos: Vector2 = Vector2.ZERO
var target_id: int = -1 ## demolish / move: the piece under the cursor
var menu: BuildMenu

var _build_flip: bool = false ## the build tool's mirroring while a lifted piece uses its own
var _ghost: Sprite2D
var _textures: Dictionary = {}
var _time: float = 0.0
var _held: float = 0.0
var _last_placed: Vector2 = Vector2(INF, INF)
var _player: Player
var _plan: ShaderMaterial ## the ghost is drawn as a projected plan (blueprint.gdshader)
var _sweep: Array[Vector2] = [] ## where the props stand that the new piece's pressure wave would tear out
var _sweep_cells: Array = []
var _sweep_for: Vector3 = Vector3.INF ## (x, y, piece hash) the sweep was found for
var _sweep_clock: float = 0.0
var _rustle_clock: float = 0.0
var _last_snap: Vector2 = Vector2.INF


func setup(owner_town: TownManager) -> void:
	town = owner_town
	name = "BuildMode"
	add_to_group("build_mode") ## the cursor (GameCursor) asks it what to show
	z_index = 90
	material = Unlit.material()
	_ghost = Sprite2D.new()
	_ghost.centered = false
	_plan = ShaderMaterial.new()
	_plan.shader = preload("res://assets/shaders/blueprint.gdshader")
	_ghost.material = _plan
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
	if on:
		menu.deal()
	InputManager.build_open = on
	_ghost.visible = false
	_end_carry()
	demolish = false
	moving = false
	menu.visible = on
	_held = 0.0
	queue_redraw() ## the footprint and the ring of dots must go with the menu


func _exit_tree() -> void:
	InputManager.build_open = false


## The build tool is in hand (not the demolish or the move tool).
func building() -> bool:
	return not demolish and not moving


func carrying() -> bool:
	return moving and carry_id >= 0


## The piece the ghost shows: the chosen one, or the one that has been lifted.
func ghost_piece() -> String:
	if carrying():
		return String((town.structures[carry_id] as Dictionary).p) if town.structures.has(carry_id) else ""
	return piece if building() else ""


func select(id: String) -> void:
	piece = id
	_end_carry()
	demolish = false
	moving = false
	_last_placed = Vector2(INF, INF)


func set_demolish(on: bool) -> void:
	_end_carry()
	demolish = on
	if on:
		moving = false
	_last_placed = Vector2(INF, INF)


func set_moving(on: bool) -> void:
	_end_carry()
	moving = on
	if on:
		demolish = false
	_last_placed = Vector2(INF, INF)


## A pad has no mouse for the tags: its demolish button goes round build -> demolish -> move -> build.
func _cycle_tool() -> void:
	if demolish:
		set_moving(true)
	elif moving:
		set_moving(false)
	else:
		set_demolish(true)


## Lifts the piece `id` (move tool): it follows the cursor as a ghost with its own mirroring, the real one fades back where it stands.
func _lift(id: int) -> void:
	if not town.structures.has(id):
		return
	_build_flip = flip
	carry_id = id
	flip = int((town.structures[id] as Dictionary).get("f", 0)) == 1
	_last_snap = Vector2.INF
	_fade_view(id, 0.35)
	Sfx.ui(self, "ui_click", -6.0)


func _end_carry() -> void:
	if carry_id < 0:
		return
	_fade_view(carry_id, 1.0)
	carry_id = -1
	flip = _build_flip
	_ghost.visible = false


func _fade_view(id: int, alpha: float) -> void:
	var view: TownStructure = town.view_of(id)
	if view != null and is_instance_valid(view):
		view.modulate.a = alpha


func _set_down() -> void:
	if reason != "":
		menu.toast(reason, false)
		return
	var id: int = carry_id
	var at: Vector2 = pos
	var mirrored: bool = flip
	_end_carry()
	town.request_move(id, at, mirrored)
	Sfx.at(self, "build_place", at, -3.0, 0.04, 480.0)


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
	menu.deal()
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
		if InputManager.using_mouse:
			set_demolish(not demolish)
		else:
			_cycle_tool()
	if Input.is_action_just_pressed("build_move"):
		set_moving(not moving)
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
	if carry_id >= 0 and not town.structures.has(carry_id):
		_end_carry() ## somebody else took it down meanwhile
	var cursor: Vector2 = InputManager.aim_world_position() if InputManager.using_mouse else _player.global_position + _player.facing.normalized() * 40.0
	if carrying():
		target_id = -1
		_update_ghost(cursor)
	elif demolish or moving:
		target_id = _structure_at(cursor)
		reason = ""
		_ghost.visible = false
		_sweep.clear()
	else:
		target_id = -1
		_update_ghost(cursor)
	if Input.is_action_pressed("action_primary") and not menu.over_card():
		_held += delta
		if _held > REPEAT_DELAY and building() and _repeatable() and pos != _last_placed and reason == "":
			_place()
			_held = REPEAT_DELAY - REPEAT_EVERY
	else:
		_held = 0.0
	queue_redraw()


func _repeatable() -> bool:
	var spec: Dictionary = TownRules.piece(piece)
	return bool(spec.get("walk", false)) or piece == "fence"


func _update_ghost(cursor: Vector2) -> void:
	var shown: String = ghost_piece()
	if shown == "":
		_ghost.visible = false
		return
	pos = TownRules.snapped_position(shown, cursor)
	reason = town.check_move(carry_id, pos, _player) if carrying() else town.check_place(shown, pos, _player)
	var spec: Dictionary = TownRules.piece(shown)
	var tex: Texture2D = texture_of(shown)
	var frame: Array = spec.get("frame", [16, 16]) as Array
	_ghost.texture = tex
	_ghost.flip_h = flip
	_ghost.position = pos + Vector2(-float(frame[0]) / 2.0, -float(spec.get("feet", frame[1])))
	_plan.set_shader_parameter("tint", Color(0.47, 0.96, 0.9, 0.95) if reason == "" else Color(1.0, 0.35, 0.42, 0.9))
	_plan.set_shader_parameter("shake", 0.0 if reason == "" else 0.6)
	_ghost.visible = true
	if pos != _last_snap:
		if _last_snap != Vector2.INF and InputManager.using_mouse:
			_tick()
		_last_snap = pos
	if carrying():
		_sweep.clear() ## a piece that is carried sweeps nothing (a site sweeps when it is finished, wherever it stands then)
		_sweep_cells.clear()
		_sweep_for = Vector3.INF
	else:
		_update_sweep()


func _tick() -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = load("res://assets/audio/town/snap_tick.wav") as AudioStream
	player.volume_db = -18.0
	player.pitch_scale = randf_range(0.95, 1.08)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Which props the piece's pressure wave would tear out where it stands now (asked again when it moves, at most 8 times a second), and they shiver.
func _update_sweep() -> void:
	_sweep_clock -= get_process_delta_time()
	var key: Vector3 = Vector3(pos.x, pos.y, float(piece.hash()))
	var radius: float = TownManager.wave_radius(piece)
	if radius <= 0.0 or town.world == null:
		_sweep.clear()
		_sweep_cells.clear()
		_sweep_for = key
		return
	if key != _sweep_for and _sweep_clock <= 0.0:
		_sweep_clock = 0.12
		_sweep_for = key
		_sweep.clear()
		var lit: Array[Vector3] = town.circles().duplicate()
		var spec: Dictionary = TownRules.piece(piece)
		if float(spec.get("reach", 0.0)) > 0.0:
			lit.append(Vector3(pos.x, pos.y - 8.0, float(spec.reach) * town.light_grow()))
		_sweep_cells = town.world.town_wave_cells(pos, radius, lit)
		for cell: Variant in _sweep_cells:
			_sweep.append(town.world.prop_position(cell as Vector2i))
	_rustle_clock -= get_process_delta_time()
	if _rustle_clock <= 0.0 and reason == "":
		_rustle_clock = 0.7
		for cell: Variant in _sweep_cells:
			var thing: WorldProp = town.world.prop_node(cell as Vector2i)
			if thing != null:
				thing.call("_rustle", 1.0 if (cell as Vector2i).x % 2 == 0 else -1.0, 0.07)


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
		if carrying():
			_end_carry() ## the lifted piece goes back where it stands, the build mode stays
			Sfx.ui(self, "ui_click", -10.0)
		else:
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
		elif moving:
			if carrying():
				_set_down()
			elif target_id >= 0:
				_lift(target_id)
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
	if moving and not carrying():
		if target_id >= 0: ## the piece the hand would lift: corner brackets that breathe
			_draw_brackets(town.rect_of(target_id), Color(GOLD_HAND, 0.9), 1.0 + roundf(sin(_time * 5.0)))
		return
	var shown: String = ghost_piece()
	if shown == "":
		return
	var cursor: Vector2 = pos
	for id: int in town.structures:
		if id == carry_id:
			continue
		var door_zone: Rect2 = town.front_of(id)
		if door_zone.has_area() and view.intersects(door_zone):
			draw_rect(door_zone, Color(RING, 0.06)) ## doors of the town: nothing may be put in front of them
	_draw_grid(cursor)
	var rect: Rect2 = TownRules.foot_rect(shown, pos.x, pos.y)
	var color: Color = GOOD if reason == "" else BAD
	if carrying(): ## where it stands now: a dashed outline, a dotted thread to where it would go
		var home: Rect2 = town.rect_of(carry_id)
		_draw_dashed_rect(home, Color(GOLD_HAND, 0.7))
		var from: Vector2 = home.get_center()
		var to: Vector2 = rect.get_center()
		var steps: int = int(from.distance_to(to) / 4.0)
		for s: int in range(1, steps):
			if (s + int(_time * 8.0)) % 3 == 0:
				draw_rect(Rect2(from.lerp(to, float(s) / float(steps)).round(), Vector2.ONE), Color(GOLD_HAND, 0.6))
	draw_rect(rect, Color(color, 0.16 + 0.05 * sin(_time * 5.0)))
	draw_rect(rect, Color(color, 0.85), false, 1.0)
	var spec: Dictionary = TownRules.piece(shown)
	var reach: float = float(spec.get("reach", 0.0)) * town.light_grow()
	if reach > 0.0 and reason == "": ## the light it would bring: a dashed gold ring, the new ground faintly lit
		var center: Vector2 = Vector2(pos.x, pos.y - 8.0)
		var count: int = maxi(int(reach * TAU / 3.0), 24)
		for k: int in count:
			var angle: float = TAU * float(k) / float(count) + _time * 0.15
			if k % 4 < 2:
				var point: Vector2 = (center + Vector2.from_angle(angle) * reach).round()
				draw_rect(Rect2(point, Vector2.ONE), Color(1.0, 0.82, 0.48, 0.75))
		draw_circle(center, reach, Color(1.0, 0.82, 0.48, 0.05))
	for spot: Vector2 in _sweep: ## what the wave will tear out
		var r: float = 5.0 + sin(_time * 6.0 + spot.x) * 0.6
		for k2: int in 10:
			var a: float = TAU * float(k2) / 10.0
			draw_rect(Rect2((spot + Vector2(0, -3) + Vector2.from_angle(a) * r).round(), Vector2.ONE), Color(1.0, 1.0, 1.0, 0.55))
	var front: Rect2 = TownRules.front_rect(shown, pos.x, pos.y) ## the ground in front of the door, which has to stay free
	if front.has_area():
		draw_rect(front, Color(color, 0.07))
		for k: int in int(front.size.x / 6.0) + 1:
			draw_rect(Rect2(front.position.x + float(k) * 6.0, front.end.y - 1.0, 3.0, 1.0), Color(color, 0.55))


func _view_rect() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	return Rect2(inverse * Vector2.ZERO, Vector2.ZERO).expand(inverse * get_viewport_rect().size).grow(24.0)


## Four corner brackets round `rect`, `out` px outside it (the move tool's mark on the piece it would lift).
func _draw_brackets(rect: Rect2, color: Color, out: float) -> void:
	var r: Rect2 = rect.grow(out)
	var arm: float = minf(5.0, minf(r.size.x, r.size.y) * 0.4)
	for k: int in 4:
		var sx: float = 1.0 if k % 2 == 0 else -1.0
		var sy: float = 1.0 if k < 2 else -1.0
		var corner: Vector2 = Vector2(r.position.x if sx > 0.0 else r.end.x, r.position.y if sy > 0.0 else r.end.y).round()
		draw_rect(Rect2(corner + Vector2(0.0 if sx > 0.0 else -arm, 0.0 if sy > 0.0 else -1.0), Vector2(arm, 1.0)), color)
		draw_rect(Rect2(corner + Vector2(0.0 if sx > 0.0 else -1.0, 0.0 if sy > 0.0 else -arm), Vector2(1.0, arm)), color)


func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var r: Rect2 = Rect2(rect.position.round(), rect.size.round())
	for x: int in range(0, int(r.size.x), 4):
		draw_rect(Rect2(r.position.x + float(x), r.position.y, 2.0, 1.0), color)
		draw_rect(Rect2(r.position.x + float(x), r.end.y - 1.0, 2.0, 1.0), color)
	for y: int in range(0, int(r.size.y), 4):
		draw_rect(Rect2(r.position.x, r.position.y + float(y), 1.0, 2.0), color)
		draw_rect(Rect2(r.end.x - 1.0, r.position.y + float(y), 1.0, 2.0), color)


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
	var grid: float = TownRules.snap_of(ghost_piece())
	var base: Vector2 = (center / grid).round() * grid
	for y: int in range(-4, 5):
		for x: int in range(-6, 7):
			var p: Vector2 = base + Vector2(x, y) * grid
			if not town.in_territory(p):
				continue
			var fade: float = 1.0 - clampf(p.distance_to(center) / 80.0, 0.0, 1.0)
			if fade > 0.0:
				draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Color(RING, 0.35 * fade))
