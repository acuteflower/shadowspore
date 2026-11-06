class_name SkillTreeWindow
extends Control
## F: a living, explorable veil. Only the three existing abilities are real skills.
## Holding on a placeholder explores the graph for free; it never buys an upgrade.
const VEIL: Shader = preload("res://assets/shaders/skill_veil.gdshader")
const OPEN_SECONDS: float = 0.85
const CLOSE_SECONDS: float = 0.3
const HOLD_SECONDS: float = 0.7
const REVEAL_SECONDS: float = 1.1
const ZOOM_MIN: float = 0.55
const ZOOM_MAX: float = 1.8
const ZOOM_STEP: float = 1.28
const HOME: Vector2 = Vector2(-46, -4) ## keeps every node clear of the corner vines
const TEXT: Color = Color("e8e4f4")
const DIM: Color = Color("a79abf")
const INK: Color = Color("08050f")
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const HALO_LEVELS: float = 4.0

var _player: Node
var _skills: SkillTreeComponent
var _opening: bool = false
var _open_t: float = 0.0
var _time: float = 0.0
var _selected: String = "sword_combo"
var _hover: String = ""
var _center: Vector2 = HOME
var _fly_target: Vector2 = Vector2.ZERO
var _flying: bool = false
var _zoom: float = 1.0
var _zoom_target: float = 1.0
var _dragging: bool = false
var _slider_drag: bool = false
var _velocity: Vector2 = Vector2.ZERO
var _since_motion: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _held: bool = false
var _hold: float = 0.0
var _hold_mouse: bool = false
var _hold_on_orb: bool = false
var _pending: String = ""
var _pending_time: float = 0.0
var _paused_here: bool = false
var _paused_before: bool = false
var _blocking_before: bool = false
var _owns_input: bool = false
var _reveal: Dictionary = {} ## id -> seconds since host-confirmed exploration
var _interest: Dictionary = {} ## eased hover / selection strength
var _stage: Control
var _web: Control
var _orbs: Control
var _chrome: Control
var _veil: ColorRect
var _material: ShaderMaterial = ShaderMaterial.new()
var _last_size: Vector2 = Vector2.ZERO
var _voice: AudioStreamPlayer
var _halos: Dictionary = {} ## radius -> dithered halo texture (kept referenced, or it turns white)


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 30 ## above the HUD vines; death has its own higher CanvasLayer
	_stage = Control.new()
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_web = Control.new()
	_web.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_web.draw.connect(_draw_web)
	_stage.add_child(_web)
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = VEIL
	_veil.material = _material
	_stage.add_child(_veil)
	_stage.move_child(_veil, 0)
	_orbs = Control.new()
	_orbs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orbs.draw.connect(_draw_orbs)
	_stage.add_child(_orbs)
	_chrome = Control.new()
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.draw.connect(_draw_chrome)
	add_child(_chrome)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -23.0
	add_child(_voice)
	resized.connect(_layout)
	_layout()


## Node avoids the player -> HUD -> player preload cycle.
func bind(player: Node) -> void:
	_player = player
	_skills = player.get_node("SkillTreeComponent") as SkillTreeComponent
	_skills.explored.connect(_on_explored)
	var health: HealthComponent = player.get_node("HealthComponent") as HealthComponent
	health.changed.connect(func(current: float, _maximum: float) -> void:
		if current <= 0.0 and _owns_input:
			_finish_close())


func _can_open() -> bool:
	if not is_instance_valid(_player) or _skills == null or InputManager.ui_blocking or get_tree().paused:
		return false
	if _player.get("intro") != null or bool(_player.get("story_lock")) or bool(_player.get("stumbling")):
		return false
	if (_player.get_node("HealthComponent") as HealthComponent).current <= 0.0:
		return false
	var hud: CanvasLayer = get_parent() as CanvasLayer
	if hud != null and not hud.visible:
		return false
	var quests: QuestComponent = _player.get("quests") as QuestComponent
	return not get_tree().get_first_node_in_group("world") is WorldLevel or (quests != null and quests.has_flag("hud_unlocked"))


func _set_open(open: bool) -> void:
	if open == _opening:
		return
	if open:
		if _owns_input or not _can_open():
			return
		_blocking_before = InputManager.ui_blocking
		_paused_before = get_tree().paused
		_owns_input = true
		InputManager.skills_open = true
		InputManager.ui_blocking = true
		_paused_here = multiplayer.is_server() and multiplayer.get_peers().is_empty()
		if _paused_here:
			get_tree().paused = true
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_center = HOME
		_flying = false
		_anchor = size * 0.5
		_velocity = Vector2.ZERO
		_zoom_target = _fit_zoom()
		_zoom = _zoom_target * 0.9
		_play("open")
	_opening = open
	_cancel_hold()
	_dragging = false
	_slider_drag = false
	_hover = ""


func _finish_close() -> void:
	_opening = false
	_open_t = 0.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cancel_hold()
	_dragging = false
	_slider_drag = false
	_velocity = Vector2.ZERO
	_pending = ""
	if not _owns_input:
		return
	_owns_input = false
	InputManager.skills_open = false
	var health: HealthComponent = _player.get_node_or_null("HealthComponent") as HealthComponent if is_instance_valid(_player) else null
	var dead: bool = health != null and health.current <= 0.0
	InputManager.ui_blocking = _blocking_before or dead or InputManager.menu_open or InputManager.map_open
	if _paused_here:
		get_tree().paused = _paused_before
	_paused_here = false


func _exit_tree() -> void:
	if _owns_input:
		_finish_close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_hold()
		_dragging = false
		_slider_drag = false
		_velocity = Vector2.ZERO


func _process(delta: float) -> void:
	if InputManager.skills_pressed():
		_set_open(not _opening)
	if not _owns_input:
		return
	if _paused_here and not multiplayer.get_peers().is_empty():
		get_tree().paused = _paused_before
		_paused_here = false
	if is_instance_valid(_player) and (_player.get("intro") != null or bool(_player.get("story_lock"))):
		_finish_close()
		return
	_open_t = move_toward(_open_t, 1.0 if _opening else 0.0, delta / (OPEN_SECONDS if _opening else CLOSE_SECONDS))
	if _open_t <= 0.0:
		_finish_close()
		return
	modulate.a = smoothstep(0.0, 1.0, _open_t)
	_time += delta
	_navigate_view(delta)
	if InputManager.using_mouse:
		_hover = _pick(get_local_mouse_position() - _stage.position)
	if _held and _hold_mouse:
		var inside: bool = _hover == _selected if _hold_on_orb else _action_rect().has_point(get_local_mouse_position())
		if not inside:
			_cancel_hold()
	if _held and _opening and _skills.can_explore(_selected) and _pending.is_empty():
		_hold = minf(_hold + delta / HOLD_SECONDS, 1.0)
		if _hold >= 1.0:
			_pending = _selected
			_pending_time = 0.0
			_cancel_hold()
			_skills.request_explore(_selected)
	if not _pending.is_empty():
		_pending_time += delta
		if _pending_time >= 3.0:
			_pending = ""
	for id: String in _reveal.keys():
		_reveal[id] = float(_reveal[id]) + delta
		if float(_reveal[id]) > 2.4:
			_reveal.erase(id)
	for id: String in _skills.definitions():
		var target: float = 1.0 if id == _selected else (0.55 if id == _hover else 0.0)
		_interest[id] = lerpf(float(_interest.get(id, 0.0)), target, 1.0 - exp(-9.0 * delta))
	_push_veil()
	queue_redraw()
	_web.queue_redraw()
	_orbs.queue_redraw()
	_chrome.modulate.a = smoothstep(0.2, 0.9, _open_t)
	_chrome.queue_redraw()


func _navigate_view(delta: float) -> void:
	if _opening:
		var pan: Vector2 = InputManager.map_pan_vector()
		if pan != Vector2.ZERO:
			_center += pan * delta * 240.0 / _zoom
			_flying = false
			_velocity = Vector2.ZERO
		if InputManager.skills_center_pressed():
			_recenter()
		var step: int = InputManager.map_zoom_step()
		if step != 0:
			_zoom_by(step, size * 0.5)
	if _flying:
		_center = _center.lerp(_fly_target, 1.0 - exp(-5.0 * delta))
	elif not _dragging and _velocity.length() > 0.01:
		_center += _velocity * delta
		_velocity *= exp(-5.0 * delta)
	_since_motion += delta
	var before: float = _zoom
	_zoom *= pow(_zoom_target / _zoom, 1.0 - exp(-12.0 * delta))
	if absf(_zoom - _zoom_target) < 0.0005 * _zoom:
		_zoom = _zoom_target
	_center += (_anchor - size * 0.5) * (1.0 / before - 1.0 / _zoom)
	_center = _center.clamp(Vector2(-440, -300), Vector2(440, 300))


func _zoom_by(steps: float, at: Vector2) -> void:
	_zoom_target = clampf(_zoom_target * pow(ZOOM_STEP, steps), ZOOM_MIN, ZOOM_MAX)
	_anchor = at
	_flying = false
	_velocity = Vector2.ZERO


func _recenter() -> void:
	_fly_target = HOME
	_flying = true
	_velocity = Vector2.ZERO
	_zoom_target = _fit_zoom()
	_anchor = size * 0.5


func _layout() -> void:
	if _stage == null:
		return
	_stage.position = Vector2.ZERO
	_stage.size = size
	_veil.size = _stage.size
	if _last_size != Vector2.ZERO:
		_zoom_target = clampf(_zoom_target * size.x / _last_size.x, ZOOM_MIN, ZOOM_MAX)
	_anchor = size * 0.5
	_last_size = size


func _fit_zoom() -> float:
	return clampf(minf(size.x / 640.0, size.y / 360.0) * 0.85, ZOOM_MIN, 1.15)


func _pos(id: String) -> Vector2:
	var values: Array = (_skills.definitions()[id] as Dictionary).get("pos", [0, 0])
	return Vector2(float(values[0]), float(values[1]))


func _screen(id: String) -> Vector2:
	return ((_orb_world(id) - _center) * _zoom + _stage.size * 0.5).round()


func _phase(id: String) -> float:
	var point: Vector2 = _pos(id)
	return VineStyle.rand(int(point.x) * 7 + int(point.y) * 13) * TAU


func _orb_world(id: String) -> Vector2:
	var phase: float = _phase(id)
	var amount: float = 1.0 if _skills.is_explored(id) else 0.55
	return _pos(id) + Vector2(sin(_time * 0.72 + phase) * 1.7, sin(_time * 0.58 + phase * 1.3) * 2.2) * amount


func _depth(id: String) -> int:
	var depth: int = 0
	var current: String = id
	for _step: int in _skills.definitions().size():
		var parent_id: String = String((_skills.definitions().get(current, {}) as Dictionary).get("parent", ""))
		if parent_id.is_empty():
			break
		depth += 1
		current = parent_id
	return depth


## One shared heartbeat propagates through each branch, reaching successive nodes later.
func _cycle(id: String) -> float:
	var branch: String = String((_skills.definitions()[id] as Dictionary).branch)
	var offset: float = float(["combat", "movement", "shadow"].find(branch)) * 0.31
	return fposmod(_time * 0.22 + offset - _depth(id) * 0.18, 1.0)


func _color(id: String) -> Color:
	var node: Dictionary = _skills.definitions()[id]
	return Color(String(DataRegistry.get_entry("skills", "branches")[node.branch].color))


func _appearance(id: String) -> float:
	if _skills.is_awake(id):
		return smoothstep(0.08, 0.8, _open_t)
	var parent_id: String = String((_skills.definitions()[id] as Dictionary).get("parent", ""))
	var reveal: float = float(_reveal.get(parent_id, REVEAL_SECONDS)) / REVEAL_SECONDS
	return smoothstep(0.24, 0.95, reveal) * smoothstep(0.2, 0.9, _open_t)


func _push_veil() -> void:
	var lights: PackedVector4Array = PackedVector4Array()
	for id: String in _skills.definitions():
		if not _skills.is_explored(id):
			continue
		var t: float = clampf(float(_reveal.get(id, REVEAL_SECONDS)) / REVEAL_SECONDS, 0.0, 1.0)
		var point: Vector2 = _pos(id)
		lights.append(Vector4(point.x, point.y, lerpf(14.0, 106.0, 1.0 - pow(1.0 - t, 3.0)), 0.0))
	var count: int = lights.size()
	lights.resize(32)
	_material.set_shader_parameter("view_size", _stage.size)
	_material.set_shader_parameter("center", _center)
	_material.set_shader_parameter("zoom", _zoom)
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_material.set_shader_parameter("opening", smoothstep(0.0, 1.0, _open_t))
	_material.set_shader_parameter("lights", lights)
	_material.set_shader_parameter("light_count", count)


func _on_explored(id: String) -> void:
	_reveal[id] = 0.0
	_pending = ""
	for child_id: String in _skills.definitions():
		if String((_skills.definitions()[child_id] as Dictionary).get("parent", "")) == id:
			_fly_target = _pos(id).lerp(_pos(child_id), 0.35)
			_flying = true
			_velocity = Vector2.ZERO
			_anchor = size * 0.5
			break
	_play("reveal")


func _play(kind: String) -> void:
	var path: String = "res://assets/audio/skills/" + kind + ".wav"
	if ResourceLoader.exists(path):
		_voice.stream = load(path) as AudioStream
		_voice.play()


func _cancel_hold() -> void:
	_held = false
	_hold = 0.0


func _pick(at: Vector2) -> String:
	if not Rect2(Vector2.ZERO, _stage.size).has_point(at) or _ui_visibility(at) < 0.5:
		return ""
	for id: String in _skills.definitions():
		if _skills.is_visible(id) and _appearance(id) > 0.6 and _screen(id).distance_to(at) <= maxf(15.0, _orb_radius(id) + 5.0):
			return id
	return ""


## Let the graph pass behind floating labels without competing with their text.
## This attenuates only graph marks; there is no panel or opaque surface.
func _ui_visibility(at: Vector2) -> float:
	var zones: Array[Rect2] = [
		Rect2(0, size.y - 108, 250, 81),
		_action_rect(),
		Rect2(size.x - 132, 48, 132, 17),
	]
	var visibility: float = 1.0
	for zone: Rect2 in zones:
		var nearest: Vector2 = at.clamp(zone.position, zone.end)
		visibility = minf(visibility, lerpf(0.12, 1.0, smoothstep(0.0, 18.0, at.distance_to(nearest))))
	return visibility


func _action_rect() -> Rect2:
	return Rect2(size.x - 218, size.y - 112, 176, 50)


func _zoom_rect() -> Rect2:
	return Rect2(size.x - 34, 83, 25, maxf(size.y - 109, 40.0))


func _set_zoom_from(y: float) -> void:
	var u: float = clampf((size.y - 34.0 - y) / maxf(size.y - 124.0, 1.0), 0.0, 1.0)
	_zoom_target = exp(lerpf(log(ZOOM_MIN), log(ZOOM_MAX), u))
	_anchor = size * 0.5
	_flying = false
	_velocity = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if not _owns_input:
		return
	if event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()
		return
	if not _opening:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if mouse != null:
		if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mouse.pressed:
			_zoom_by(1.0 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0, mouse.position)
		elif mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if not mouse.pressed:
				_cancel_hold()
				_dragging = false
				_slider_drag = false
				if _since_motion > 0.08:
					_velocity = Vector2.ZERO
			else:
				var local: Vector2 = mouse.position
				var picked: String = _pick(local - _stage.position)
				if mouse.button_index == MOUSE_BUTTON_MIDDLE:
					_dragging = true
					_flying = false
				elif _zoom_rect().has_point(local):
					_slider_drag = true
					_set_zoom_from(local.y)
				elif _action_rect().has_point(local):
					_begin_hold(true, false)
				elif not picked.is_empty():
					_select(picked)
					_begin_hold(true, true)
				elif mouse.double_click:
					_zoom_by(2.0, local)
				else:
					_dragging = true
					_flying = false
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			_cancel_hold()
		get_viewport().set_input_as_handled()
	elif motion != null:
		_hover = _pick(motion.position - _stage.position)
		if _slider_drag:
			_set_zoom_from(motion.position.y)
		elif _dragging:
			_center = (_center - motion.relative / _zoom).clamp(Vector2(-440, -300), Vector2(440, 300))
			_velocity = (-motion.relative / _zoom) * 30.0 + _velocity * 0.5
			_since_motion = 0.0
		if _held and _hold_mouse:
			var inside: bool = _hover == _selected if _hold_on_orb else _action_rect().has_point(motion.position)
			if not inside:
				_cancel_hold()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_begin_hold(false, false)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_accept"):
		_cancel_hold()
		get_viewport().set_input_as_handled()
	else:
		for action: String in ["ui_left", "ui_right", "ui_up", "ui_down"]:
			if event.is_action_pressed(action):
				var direction: Vector2 = {"ui_left": Vector2.LEFT, "ui_right": Vector2.RIGHT, "ui_up": Vector2.UP, "ui_down": Vector2.DOWN}[action]
				_navigate(direction)
				get_viewport().set_input_as_handled()
				break


func _begin_hold(mouse: bool, on_orb: bool) -> void:
	if _skills.can_explore(_selected) and _pending.is_empty() and _open_t > 0.8:
		_held = true
		_hold_mouse = mouse
		_hold_on_orb = on_orb


func _select(id: String) -> void:
	if id != _selected:
		_selected = id
		_cancel_hold()
		_play("focus")


func _navigate(direction: Vector2) -> void:
	var best: String = ""
	var score: float = INF
	for id: String in _skills.definitions():
		if id == _selected or not _skills.is_visible(id) or _appearance(id) < 0.6:
			continue
		var offset: Vector2 = _pos(id) - _pos(_selected)
		var alignment: float = offset.normalized().dot(direction)
		if alignment > 0.3 and offset.length() / alignment < score:
			score = offset.length() / alignment
			best = id
	if not best.is_empty():
		_select(best)
		var at: Vector2 = _screen(best)
		if not Rect2(Vector2(24, 24), _stage.size - Vector2(48, 48)).has_point(at) or _ui_visibility(at) < 0.5:
			_fly_target = _pos(best)
			_flying = true
			_velocity = Vector2.ZERO
			_anchor = size * 0.5


func _draw_chrome() -> void:
	if not visible or _skills == null:
		return
	var void_level: float = VineStyle.void_amount()
	var plate: float = clampf((_open_t - 0.35) / 0.5, 0.0, 1.0)
	VineStyle.tag(_chrome, "FÄHIGKEITEN", Vector2(size.x * 0.5, 0), plate, void_level, _time)
	_text_centered("DAS SCHLEIERGEFLECHT", Vector2(size.x * 0.5, 29), DIM)
	_draw_points_vine(void_level)
	_draw_details()
	_draw_action_vine(void_level)
	_draw_zoom_vine(void_level)
	var controls: String = "ZIEHEN / WASD: SCHIEBEN   RAD / Q E: ZOOM   R: MITTE   F / ESC: ZURÜCK" if InputManager.using_mouse else "STICK: SCHIEBEN   STEUERKREUZ: AUSWAHL   A: HALTEN   START: ZURÜCK"
	var hint_width: float = PixelText.width(controls) + 16.0
	_text_backing(Rect2(size.x * 0.5 - hint_width * 0.5, size.y - 19, hint_width, 15), VineStyle.BARK_LIGHT, 0.68)
	_text_centered(controls, Vector2(size.x * 0.5, size.y - 15), Color(DIM, 0.75))


func _text_centered(value: String, at: Vector2, color: Color) -> void:
	_text(_chrome, value, at - Vector2(PixelText.width(value) * 0.5, 0), color)


## Small hanging text blocks: the same ragged bark paper as dialogue, tooltips and hint cards.
func _text_backing(rect: Rect2, _tint: Color, opacity: float = 0.9) -> void:
	VineStyle.paper(_chrome, Rect2(rect.position.round(), rect.size.round()), opacity, VineStyle.void_amount(), int(rect.position.x) * 3 + int(rect.position.y))


## Dithered halo: a cached ordered-dither falloff, so glows share the veil's Bayer look instead of stacked flat discs.
func _halo(canvas: CanvasItem, at: Vector2, radius: float, tone: Color, strength: float) -> void:
	if strength <= 0.01:
		return
	var r: int = maxi(roundi(radius / 2.0) * 2, 4)
	if not _halos.has(r):
		if _halos.size() > 48:
			_halos.clear()
		var side: int = r * 2 + 1
		var image: Image = Image.create(side, side, false, Image.FORMAT_RGBA8)
		for y: int in side:
			for x: int in side:
				var q: float = pow(maxf(1.0 - Vector2(x - r, y - r).length() / r, 0.0), 1.7) * HALO_LEVELS
				var step: float = floorf(q) + (1.0 if q - floorf(q) > BAYER[(y % 4) * 4 + x % 4] / 16.0 else 0.0)
				image.set_pixel(x, y, Color(1, 1, 1, step / HALO_LEVELS))
		_halos[r] = ImageTexture.create_from_image(image)
	canvas.draw_texture(_halos[r] as Texture2D, (at - Vector2(r, r)).round(), Color(tone, minf(strength * 0.5, 0.9)))


## One dark translucent globe with layered depth, light from the upper left. Used by orbs, pendants and the action bud.
func _globe(canvas: CanvasItem, at: Vector2, radius: float, tone: Color, alpha: float, life: float, breath: float, rim: float = 0.0) -> void:
	canvas.draw_circle(at + Vector2(0, 2), radius + 2.0, Color(INK, alpha * 0.65))
	canvas.draw_circle(at, radius, Color(tone.darkened(0.93), alpha))
	canvas.draw_circle(at + Vector2(-1, -1), radius * 0.74, Color(tone.darkened(0.79), alpha * (0.48 + breath * 0.14)))
	canvas.draw_circle(at + Vector2(-2, -3), radius * 0.4, Color(tone, alpha * 0.055 * life))
	VineStyle.ring(canvas, at, int(radius), Color(tone, alpha * (0.22 + breath * 0.1 + rim * 0.16)), 0.8)


## 0..1: how far the selected placeholder's exploration has charged (a pending host answer counts as full).
func _charge(id: String) -> float:
	if id == _pending:
		return 1.0
	return _hold if id == _selected else 0.0


func _draw_points_vine(void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.4) / 0.5, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return 42.0 + 3.0 * sin((size.x - x) * 0.045)
	VineStyle.branch(_chrome, size.x, size.x - 132.0, course, 4, void_level, 45.0, _time, reach)
	VineStyle.foliage(_chrome, size.x, size.x - 132.0, course, 7, 470, void_level, 45.0, _time, reach)
	var progress: ProgressComponent = _player.get_node("ProgressComponent") as ProgressComponent
	_text(_chrome, "%d PUNKTE / FÜR SPÄTER" % maxi(progress.level - 1, 0), Vector2(size.x - 124, 54), Color("e6c468"))


func _draw_details() -> void:
	var node: Dictionary = _skills.definitions()[_selected]
	var branch: Dictionary = DataRegistry.get_entry("skills", "branches")[node.branch]
	var color: Color = _color(_selected)
	var y: float = size.y - 119
	var void_level: float = VineStyle.void_amount()
	var reach: float = clampf((_open_t - 0.42) / 0.5, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return y + 3.0 * sin(x / 244.0 * PI) + sin(x * 0.07 + 2.0) * 1.1
	var block: Rect2 = Rect2(6, y + 7, 244, 66 if _skills.is_awake(_selected) else 78)
	_text_backing(block, color, 0.94)
	for x: float in [18.0, 232.0]:
		_chrome.draw_line(Vector2(x, float(course.call(x)) + 2), Vector2(x, block.position.y), VineStyle.BARK_LIGHT, 1.0)
	VineStyle.branch(_chrome, 0.0, 244.0, course, 4, void_level, 50.0, _time, reach)
	VineStyle.foliage(_chrome, 0.0, 244.0, course, 9, 570, void_level, 50.0, _time, reach)
	_text(_chrome, String(branch.name) + (" / ERLERNT" if _skills.is_awake(_selected) else " / PLATZHALTER"), Vector2(12, y + 12), color)
	_text(_chrome, String(node.name), Vector2(12, y + 25), TEXT, 2.0)
	if _skills.is_awake(_selected):
		_text(_chrome, String(node.description), Vector2(12, y + 46), DIM)
		var detail: String = String(node.detail)
		if _selected == "shadow_blink":
			var blink: BlinkComponent = _player.get_node("BlinkComponent") as BlinkComponent
			detail = "REICHWEITE %d / ABKLINGZEIT %d S" % [roundi(blink.blink_range), roundi(blink.cooldown)]
		_text(_chrome, detail, Vector2(12, y + 59), color)
	else:
		_text(_chrome, "NOCH KEINE FÄHIGKEIT. KEINE SPIELWIRKUNG.", Vector2(12, y + 46), DIM)
		_text(_chrome, "ERKUNDEN IST KOSTENLOS.", Vector2(12, y + 59), color)
		_text(_chrome, "PUNKTE BLEIBEN ERHALTEN.", Vector2(12, y + 70), DIM)


func _draw_action_vine(void_level: float) -> void:
	var y: float = size.y - 119
	var reach: float = clampf((_open_t - 0.45) / 0.5, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return y + 3.0 * sin((size.x - x) / 216.0 * PI) + sin(x * 0.07 + 2.0) * 1.1
	var block: Rect2 = _action_rect()
	_text_backing(block, _color(_selected), 0.94)
	for x: float in [size.x - 206.0, size.x - 54.0]:
		_chrome.draw_line(Vector2(x, float(course.call(x)) + 2), Vector2(x, block.position.y), VineStyle.BARK_LIGHT, 1.0)
	VineStyle.branch(_chrome, size.x, size.x - 216.0, course, 4, void_level, 50.0, _time, reach)
	VineStyle.foliage(_chrome, size.x, size.x - 216.0, course, 8, 610, void_level, 50.0, _time, reach)
	var color: Color = _color(_selected)
	var active: bool = _skills.can_explore(_selected)
	var charge: float = _charge(_selected)
	var slot: Vector2 = Vector2(size.x - 80, block.position.y + 25 + sin(_time * 1.3) * 1.0)
	var breath: float = sin(_time * 1.15) * 0.5 + 0.5
	for row: int in range(int(float(course.call(slot.x))) + 1, int(slot.y) - 10):
		_chrome.draw_rect(Rect2(slot.x, row, 1, 1), VineStyle.BARK_LIGHT if row % 2 == 0 else VineStyle.BARK)
	_halo(_chrome, slot, 20.0, color, (0.55 + charge * 0.9) if active else 0.25)
	_globe(_chrome, slot, 10.0, color, 1.0 if active else 0.55, 1.0 if active else 0.4, breath, charge)
	_chrome.draw_circle(slot + Vector2(sin(_time * 0.9), cos(_time * 0.7)).round(), 2.0 + charge, Color(color, (0.5 + charge * 0.5) if active else 0.3))
	if charge > 0.0:
		var pulse: float = 0.6 + 0.4 * sin(_time * 14.0) if _pending == _selected else 1.0
		_chrome.draw_arc(slot, 13.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, Color(color, pulse), 2.0)
	var label: String = "HALTEN ZUM ERKUNDEN" if active else ("BEREITS ERLERNT" if _skills.is_awake(_selected) else "BEREITS ERKUNDET")
	var status: String = "KOSTENLOS / PLATZHALTER" if active else ("BESTEHENDE FÄHIGKEIT" if _skills.is_awake(_selected) else "PLATZHALTER / OHNE WIRKUNG")
	if not _pending.is_empty():
		label = "SCHLEIER ANTWORTET ..."
	_text(_chrome, label, Vector2(size.x - 208, block.position.y + 12), color if active else DIM)
	_text(_chrome, status, Vector2(size.x - 208, block.position.y + 25), DIM)


func _draw_zoom_vine(void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.45) / 0.45, 0.0, 1.0)
	var bottom: float = size.y - 34.0
	var top: float = bottom - (bottom - 90.0) * reach
	var x: float = size.x - 22.0
	for row: int in range(int(top), int(bottom) + 1):
		var t: float = (bottom - row) / maxf(bottom - 90.0, 1.0)
		var px: float = x + sin(row * 0.06) * 1.5
		var thick: int = maxi(roundi(lerpf(3.0, 1.0, t)), 1)
		var taken: float = VineStyle.infection((bottom - row) * 0.5 + 40.0, void_level, row / 3)
		_chrome.draw_rect(Rect2(px - 1, row, thick + 2, 1), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		_chrome.draw_rect(Rect2(px, row, thick, 1), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if row % 3 != 1:
			_chrome.draw_rect(Rect2(px, row, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
	for i: int in 5:
		var at_y: float = lerpf(bottom, 90.0, float(i) / 4.0)
		if at_y >= top:
			VineStyle.leaf(_chrome, Vector2(x - 2, at_y), -1, -1 if i % 2 == 0 else 1, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level))
	var u: float = clampf((log(_zoom_target) - log(ZOOM_MIN)) / (log(ZOOM_MAX) - log(ZOOM_MIN)), 0.0, 1.0)
	var bead: Vector2 = Vector2(x + sin(lerpf(bottom, 90.0, u) * 0.06) * 1.5 + 1, lerpf(bottom, 90.0, u))
	VineStyle.glow(_chrome, bead, 11.0, VineStyle.VOID_GLOW, 0.6 * reach)
	_chrome.draw_rect(Rect2(bead - Vector2(2, 2), Vector2(5, 5)), VineStyle.OUTLINE)
	_chrome.draw_rect(Rect2(bead - Vector2(1, 1), Vector2(3, 3)), VineStyle.VOID_GLOW)
	_chrome.draw_rect(Rect2(bead, Vector2.ONE), VineStyle.PETAL)
	_text(_chrome, "+", Vector2(x - 1, 74), DIM)
	_text(_chrome, "-", Vector2(x - 1, bottom + 6), DIM)


func _connection_points(id: String) -> PackedVector2Array:
	var parent_id: String = String((_skills.definitions()[id] as Dictionary).parent)
	var start: Vector2 = _orb_world(parent_id)
	var end: Vector2 = _orb_world(id)
	var side: Vector2 = (end - start).orthogonal().normalized()
	var phase: float = _phase(id)
	var count: int = clampi(roundi(start.distance_to(end) * _zoom / 3.0), 28, 52)
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		var t: float = float(i) / (count - 1)
		var bow: float = sin(t * PI) * (sin(t * 3.8 + phase) * 7.0 + sin(_time * 0.85 + t * 5.0 + phase) * 2.4)
		var world: Vector2 = start.lerp(end, t) + side * bow
		points.append(((world - _center) * _zoom + _stage.size * 0.5).round())
	return points


func _path_point(points: PackedVector2Array, progress: float) -> Vector2:
	var index: float = clampf(progress, 0.0, 1.0) * (points.size() - 1)
	var first: int = mini(floori(index), points.size() - 2)
	return points[first].lerp(points[first + 1], index - first).round()


func _draw_web() -> void:
	if _skills == null:
		return
	for id: String in _skills.definitions():
		var node: Dictionary = _skills.definitions()[id]
		if not _skills.is_visible(id) or not node.has("parent"):
			continue
		var parent_id: String = String(node.parent)
		var points: PackedVector2Array = _connection_points(id)
		var tone: Color = _color(id)
		var phase: float = _phase(id)
		var alpha: float = _appearance(parent_id) * smoothstep(0.1, 0.8, _open_t)
		var grow: float = smoothstep(0.04, 0.8, float(_reveal.get(parent_id, REVEAL_SECONDS)) / REVEAL_SECONDS)
		var front: float = _cycle(parent_id) / 0.18
		var surge: float = maxf(0.0, 1.0 - float(_reveal.get(id, 10.0)) / 1.3)
		var last: int = mini(ceili(grow * (points.size() - 1)), points.size() - 1)
		for i: int in range(1, last + 1):
			var t: float = float(i) / (points.size() - 1)
			var at: Vector2 = points[i]
			var visibility: float = alpha * _ui_visibility(at)
			var light: float = exp(-pow((t - front) / 0.075, 2.0)) if front <= 1.1 else 0.0
			light = maxf(light, maxf(surge * 0.75, _charge(id) * 0.85))
			var root: Color = Color("291936").lerp(tone.darkened(0.82), 0.4)
			_web.draw_line(points[i - 1], at, Color(root, visibility * 0.75), 3.0)
			var energy: Color = tone.darkened(0.53).lerp(tone.lightened(0.22), light * 0.85)
			_web.draw_line(points[i - 1], at, Color(energy, visibility * (0.55 + light * 0.45)), 1.0)
			# A second fine fibre twists around the anchored main tendril.
			var side: Vector2 = (at - points[i - 1]).orthogonal().normalized()
			var twist: Vector2 = side * sin(t * 13.0 - _time * 1.5 + phase) * sin(t * PI) * 1.4
			_web.draw_rect(Rect2((at + twist).round(), Vector2.ONE), Color(tone, visibility * (0.12 + light * 0.22)))
		if front >= 0.0 and front <= grow:
			var at: Vector2 = _path_point(points, front)
			var strength: float = sin(front * PI) * alpha * _ui_visibility(at)
			_web.draw_circle(at, 3.0, Color(tone, strength * 0.14))
			_web.draw_rect(Rect2(at, Vector2.ONE), Color(tone.lightened(0.55), strength))


func _orb_radius(id: String) -> float:
	return roundf((13.0 if _skills.is_awake(id) else 9.0) * sqrt(_zoom))


func _draw_orbs() -> void:
	if _skills == null:
		return
	for id: String in _skills.definitions():
		if not _skills.is_visible(id):
			continue
		var appear: float = _appearance(id)
		if appear <= 0.01:
			continue
		var at: Vector2 = _screen(id)
		var alpha: float = appear * _ui_visibility(at)
		var tone: Color = _color(id)
		var phase: float = _phase(id)
		var awake: bool = _skills.is_awake(id)
		var explored: bool = _skills.is_explored(id)
		var interest: float = float(_interest.get(id, 0.0))
		var radius: float = _orb_radius(id) * lerpf(0.55, 1.0, VineStyle.back_out(clampf(appear, 0.0, 1.0)))
		var charge: float = _charge(id)
		var breath: float = sin(_time * 1.15 + phase) * 0.5 + 0.5
		var heartbeat: float = exp(-pow((_cycle(id) - 0.025) / 0.035, 2.0))
		var awakening: float = maxf(0.0, 1.0 - float(_reveal.get(id, 10.0)) / 1.1)
		heartbeat = maxf(heartbeat, awakening)
		var life: float = 1.0 if explored else 0.38
		_halo(_orbs, at, radius + 20.0, tone, alpha * (0.7 + breath * 0.35 + heartbeat * 0.9 + interest * 0.5 + charge * 0.9) * life)
		_globe(_orbs, at, radius, tone, alpha, life, breath, interest)
		# Broken shell highlights drift independently of the inner currents.
		for part: int in 3:
			var angle: float = phase + _time * (0.17 if part % 2 == 0 else -0.12) + part * TAU / 3.0
			_orbs.draw_arc(at, radius + 1.0, angle, angle + 0.45 + part * 0.08, 10, Color(tone.lightened(0.15), alpha * life * (0.28 + breath * 0.2)), 1.0)
		for current: int in 2:
			var angle: float = _time * (0.6 if current == 0 else -0.43) + phase + current * PI
			_orbs.draw_arc(at + Vector2(sin(angle), cos(angle)).round(), radius * (0.42 + current * 0.16), angle, angle + 1.45, 14, Color(tone, alpha * life * (0.16 + heartbeat * 0.2 + charge * 0.3)), 1.0)
		var core: Vector2 = at + Vector2(sin(_time * 0.9 + phase), cos(_time * 0.7 + phase)).round()
		_orbs.draw_circle(core, 2.0 + heartbeat * 1.0 + charge * 1.5, Color(tone, alpha * life * (0.42 + heartbeat * 0.3 + charge * 0.3)))
		if awake:
			_draw_glyph(at, String((_skills.definitions()[id] as Dictionary).icon), Color(tone.lightened(0.45), alpha * 0.95))
		else:
			_orbs.draw_rect(Rect2(core, Vector2.ONE), Color(tone.lightened(0.6), alpha * (0.85 if explored else 0.35)))
		# Tiny orbiting seeds bind the globe to the drifting veil, rather than a flat button.
		for mote: int in (4 if awake else 2):
			var orbit: float = phase + _time * (0.35 + mote * 0.07) + mote * 2.4
			var orbit_radius: float = radius + 4.0 + mote * 1.6
			var pos: Vector2 = at + Vector2(cos(orbit), sin(orbit) * 0.7) * orbit_radius
			_orbs.draw_rect(Rect2(pos.round(), Vector2.ONE), Color(tone.lightened(0.25), alpha * life * (0.2 + heartbeat * 0.35)))
		if interest > 0.01:
			for part: int in 2:
				var angle: float = -_time * 0.22 + phase + part * PI
				_orbs.draw_arc(at, radius + 6.0, angle, angle + 0.85, 14, Color(TEXT, alpha * interest * 0.65), 1.0)
		if charge > 0.0:
			var pulse: float = 0.6 + 0.4 * sin(_time * 14.0) if id == _pending else 1.0
			_orbs.draw_arc(at, radius + 8.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, Color(tone, alpha * pulse), 2.0)
			# The veil gathers into the orb as the hold completes.
			for gather: int in 7:
				var angle: float = gather * TAU / 7.0 + _time * 0.9
				var pull: float = fposmod(charge * 1.4 + gather * 0.137, 1.0)
				var spot: Vector2 = at + Vector2.from_angle(angle) * lerpf(radius + 20.0, radius + 2.0, pull)
				_orbs.draw_rect(Rect2(spot.round(), Vector2.ONE), Color(tone.lightened(0.4), alpha * charge * pull))
		if _reveal.has(id):
			var age: float = float(_reveal[id])
			_orbs.draw_arc(at, radius + age * 45.0 * _zoom, 0.0, TAU, 64, Color(tone, maxf(0.0, 0.65 - age * 0.5) * alpha), 1.0)
			for spark: int in 12:
				var angle: float = float(spark) / 12.0 * TAU + VineStyle.rand(spark) * 0.3
				var pos: Vector2 = at + Vector2.from_angle(angle) * age * (25 + VineStyle.rand(spark + 3) * 25)
				_orbs.draw_rect(Rect2(pos.round(), Vector2.ONE), Color(tone, maxf(0.0, 1.0 - age) * alpha))
		if awake:
			var label: String = String((_skills.definitions()[id] as Dictionary).name)
			var label_at: Vector2 = at + Vector2(-PixelText.width(label) * 0.5, radius + 11)
			_text(_orbs, label, label_at, Color(tone, alpha * _ui_visibility(label_at)))
		elif id == _selected or id == _hover:
			_text(_orbs, "PLATZHALTER", at + Vector2(-21, radius + 9), Color(DIM, alpha))


func _draw_glyph(at: Vector2, icon: String, color: Color, target: CanvasItem = null) -> void:
	var canvas: CanvasItem = _orbs if target == null else target
	match icon:
		"sword":
			canvas.draw_line(at + Vector2(-4, 5), at + Vector2(5, -5), color)
			canvas.draw_line(at + Vector2(-4, 0), at + Vector2(0, 4), color)
			canvas.draw_rect(Rect2(at + Vector2(3, -5), Vector2(2, 2)), Color(TEXT, color.a))
		"stride":
			for i: int in 2:
				var p: Vector2 = at + Vector2(-4 + i * 5, -3)
				canvas.draw_polyline(PackedVector2Array([p, p + Vector2(3, 3), p + Vector2(0, 3)]), color)
		"rift":
			canvas.draw_polyline(PackedVector2Array([at + Vector2(2, -6), at + Vector2(-3, 0), at + Vector2(2, 0), at + Vector2(-2, 6)]), color)


func _text(canvas: CanvasItem, value: String, at: Vector2, color: Color, scale_value: float = 1.0) -> void:
	canvas.draw_set_transform(at.round(), 0.0, Vector2.ONE * scale_value)
	PixelText.draw(canvas, value, Vector2i.ZERO, color, Color(VineStyle.OUTLINE, color.a * 0.9))
	canvas.draw_set_transform(Vector2.ZERO)
