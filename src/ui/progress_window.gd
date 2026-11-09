class_name ProgressWindow
extends Control
## P (or the level badge on the hotbar): the road of levels. A vine runs from left to right, one globe per level, the rewards hang below it as small bark-paper cards.
## Everything up to the reached level is lit; the levels ahead lie in the veil (the milestones peek through). Rewards are not automatic: hold on a glowing level
## (or on the bud at the bottom right) to collect them, only then do health, stamina, armor, overheal and talisman slots change (`ProgressComponent.claimed`).
## Same family as the map and the skill graph: shared veil code, pan / zoom with inertia, cursor-anchored wheel zoom, zoom vine.
const VEIL: Shader = preload("res://assets/shaders/progress_veil.gdshader")
const OPEN_SECONDS: float = 1.0
const CLOSE_SECONDS: float = 0.3
const HOLD_SECONDS: float = 0.75
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 1.7
const ZOOM_STEP: float = 1.28
const SPACING: float = 84.0 ## world px between two levels
const LIGHT_Y: float = 44.0 ## the lit corridor lies round this line (vine at 0, cards below)
const COMPACT_ZOOM: float = 0.9 ## below this the cards shrink to pips (only the selected one stays open)
const TEXT: Color = Color("e8e4f4")
const DIM: Color = Color("a79abf")
const INK: Color = Color("08050f")
const GOLD: Color = Color("ffd98a")
const TEAL: Color = Color("6fe0c4")
const VIOLET: Color = Color("9b6cf0")
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const HALO_LEVELS: float = 4.0
const KIND_COLORS: Dictionary = {
	"health": Color("e0647c"), "stamina": Color("72d6e6"), "armor": Color("a9b8de"), "overheal": Color("f1e6ff"), "talisman": Color("ffd98a"), "seed": Color("6fe0c4"),
}
const ICONS: Dictionary = {
	"health": ["##.##", "#####", "#####", ".###.", "..#.."],
	"stamina": ["..###", ".####", "####.", "###..", "#...."],
	"armor": ["#####", "#####", "#####", ".###.", "..#.."],
	"overheal": ["#...#", ".#.#.", "..#..", "..#..", "..#.."],
	"talisman": ["..#..", ".###.", "#####", ".###.", "..#.."],
	"seed": [".....", "..#..", ".###.", "..#..", "....."],
}

var _player: Node
var _progress: ProgressComponent
var _opening: bool = false
var _open_t: float = 0.0
var _time: float = 0.0
var _level: int = 1 ## cached once a frame (Levels.level_for loops)
var _claimed: int = 1
var _fraction: float = 0.0
var _selected: int = 1
var _hover: int = 0
var _center: Vector2 = Vector2.ZERO
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
var _hold_on_node: bool = false
var _pending: int = 0
var _pending_time: float = 0.0
var _paused_here: bool = false
var _paused_before: bool = false
var _blocking_before: bool = false
var _owns_input: bool = false
var _burst: Dictionary = {} ## level -> seconds since it was collected
var _born: Dictionary = {} ## level -> seconds since it was reached while the window was open
var _interest: Dictionary = {} ## level -> eased hover / selection strength
var _shown: Dictionary = {} ## stat -> value on display (counts up when rewards are collected)
var _xr_shown: float = 0.0 ## the sap bud's world x (eased)
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
	add_to_group("progress_window")
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
	_voice.volume_db = -21.0
	add_child(_voice)
	resized.connect(_layout)
	_layout()


## `player` is untyped: the player scene preloads the HUD (no preload cycle).
func bind(player: Node) -> void:
	_player = player
	_progress = player.get("progress") as ProgressComponent
	_progress.claimed_changed.connect(_on_claimed)
	_progress.leveled.connect(_on_leveled)
	var health: HealthComponent = player.get_node("HealthComponent") as HealthComponent
	health.changed.connect(func(current: float, _maximum: float) -> void:
		if current <= 0.0 and _owns_input:
			_finish_close())
	_refresh_state()


## The hotbar's level badge calls this (group `progress_window`).
func open_window() -> void:
	_set_open(true)


func _can_open() -> bool:
	if not is_instance_valid(_player) or _progress == null or InputManager.ui_blocking or get_tree().paused:
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
		InputManager.progress_open = true
		InputManager.ui_blocking = true
		_paused_here = multiplayer.is_server() and multiplayer.get_peers().is_empty()
		if _paused_here:
			get_tree().paused = true
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_refresh_state()
		_selected = _first_claimable() if _claimed < _level else _level
		var focus: Vector2 = _focus()
		_center = Vector2(focus.x, 38.0)
		_flying = false
		_anchor = size * 0.5
		_velocity = Vector2.ZERO
		_zoom_target = focus.y
		_zoom = _zoom_target * 0.88
		_xr_shown = _level_x(_level) + _fraction * SPACING - 60.0
		for kind: String in LevelRewards.KINDS:
			_shown[kind] = _stat(kind, _claimed)
		_play("open")
	_opening = open
	_cancel_hold()
	_dragging = false
	_slider_drag = false
	_hover = 0


func _finish_close() -> void:
	_opening = false
	_open_t = 0.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cancel_hold()
	_dragging = false
	_slider_drag = false
	_velocity = Vector2.ZERO
	_pending = 0
	if not _owns_input:
		return
	_owns_input = false
	InputManager.progress_open = false
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


# ------------------------------------------------------------------------------------------------ state

func _refresh_state() -> void:
	if _progress == null:
		return
	_level = _progress.level
	_claimed = _progress.claimed
	_fraction = Levels.fraction(_progress.xp)


func _first_claimable() -> int:
	return clampi(_claimed + 1, 1, _level)


func _max_level() -> int:
	return Levels.max_level()


func _level_x(n: int) -> float:
	return float(n - 1) * SPACING


## The vine's height at a world x (the same for the vine, the globes and the light).
func _course(x: float) -> float:
	return sin(x * 0.021) * 5.0 + sin(x * 0.0073 + 1.0) * 3.0


## Where the road should be looked at when the window opens: (world x, zoom). Uncollected levels are brought into view.
func _focus() -> Vector2:
	var first: int = _first_claimable() if _claimed < _level else _level
	var span: float = float(maxi(_level - first, 0)) + 3.0
	var zoom: float = clampf(size.x * 0.78 / (SPACING * span), 0.62, minf(_fit_zoom(), 1.0))
	var left: float = _level_x(first)
	var right: float = _level_x(_level) + _fraction * SPACING
	return Vector2((left + right) * 0.5 + 6.0, zoom)


func _state(n: int) -> int: ## 0 ahead, 1 waiting to be collected, 2 collected
	if n > _level:
		return 0
	return 1 if n > _claimed else 2


func _tone(n: int) -> Color:
	match _state(n):
		0:
			return VIOLET
		1:
			return GOLD
	return TEAL


## 2 = reached, 1 = the next level / milestone (shown, but dim), 0 = far ahead (digits and names are covered).
func _knowledge(n: int) -> int:
	if n <= _level:
		return 2
	if n == _level + 1 or n == LevelRewards.next_milestone(_level):
		return 1
	return 0


## How much of a card shows through the veil.
func _veil_alpha(n: int) -> float:
	if n <= _level:
		return 1.0
	var d: float = float(n - _level)
	if LevelRewards.is_milestone(n):
		return lerpf(0.7, 0.34, clampf((d - 1.0) / 14.0, 0.0, 1.0))
	return lerpf(0.52, 0.12, clampf((d - 1.0) / 6.0, 0.0, 1.0))


func _stat(kind: String, level: int) -> float:
	var stats: Dictionary = LevelRewards.stats_at(level)
	match kind:
		"talisman":
			return float(stats.get("talismans", 0))
		"overheal":
			return float(stats.get("overheal", 0.0)) * 100.0
	return float(stats.get(kind, 0.0))


func _cover(text: String, knowledge: int) -> String:
	if knowledge >= 1:
		return text
	var out: String = ""
	for i: int in text.length():
		var c: String = text[i]
		out += "?" if c >= "0" and c <= "9" else c
	return out


func _cover_name(text: String, knowledge: int) -> String:
	if knowledge >= 1:
		return text
	var out: String = ""
	for i: int in text.length():
		out += "?" if i % 2 == 1 and text[i] != " " else text[i]
	return out


func _rows(n: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = LevelRewards.lines(n)
	if rows.is_empty():
		rows.append({"kind": "seed", "text": "DER KEIM"})
	return rows


# ------------------------------------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if InputManager.progress_pressed():
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
	_refresh_state()
	_navigate_view(delta)
	if InputManager.using_mouse:
		_hover = _pick(get_local_mouse_position() - _stage.position)
		GameCursor.set_hint(self, &"click" if (_hover > 0 or _action_rect().has_point(get_local_mouse_position()) and _can_claim(_hold_target(false))) else &"")
	_update_hold(delta)
	if _pending > 0:
		_pending_time += delta
		if _pending_time >= 3.0:
			_pending = 0
	for n: int in _burst.keys():
		_burst[n] = float(_burst[n]) + delta
		if float(_burst[n]) > 3.0:
			_burst.erase(n)
	for n: int in _born.keys():
		_born[n] = float(_born[n]) + delta
		if float(_born[n]) > 3.0:
			_born.erase(n)
	for n: int in range(1, _max_level() + 1):
		var target: float = 1.0 if n == _selected else (0.55 if n == _hover else 0.0)
		_interest[n] = lerpf(float(_interest.get(n, 0.0)), target, 1.0 - exp(-9.0 * delta))
	var xr: float = _level_x(_level) + _fraction * SPACING
	_xr_shown = lerpf(_xr_shown, xr, 1.0 - exp(-3.0 * delta))
	for kind: String in LevelRewards.KINDS:
		var goal: float = _stat(kind, _claimed)
		var now: float = float(_shown.get(kind, goal))
		_shown[kind] = goal if absf(goal - now) < 0.05 else lerpf(now, goal, 1.0 - exp(-6.0 * delta))
	_push_veil()
	queue_redraw()
	_web.queue_redraw()
	_orbs.queue_redraw()
	_chrome.modulate.a = smoothstep(0.2, 0.9, _open_t)
	_chrome.queue_redraw()


func _update_hold(delta: float) -> void:
	var target: int = _hold_target(_hold_on_node)
	if _held and _hold_mouse:
		var at: Vector2 = get_local_mouse_position()
		var inside: bool = _hover == _selected if _hold_on_node else _action_rect().has_point(at)
		if not inside:
			_cancel_hold()
	if _held and _opening and _can_claim(target) and _pending == 0:
		_hold = minf(_hold + delta / HOLD_SECONDS, 1.0)
		if _hold >= 1.0:
			_pending = target
			_pending_time = 0.0
			_cancel_hold()
			_progress.request_claim(target)
	elif _held and not _can_claim(target):
		_hold = 0.0


## What a hold would collect: the selected level (held on its globe or card) or everything that is reached (held on the bud).
func _hold_target(on_node: bool) -> int:
	return _selected if on_node else _level


func _can_claim(target: int) -> bool:
	return target > _claimed and target <= _level


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
	_clamp_center()


func _clamp_center() -> void:
	_center = _center.clamp(Vector2(-90.0, -70.0), Vector2(_level_x(_max_level()) + 90.0, 140.0))


func _zoom_by(steps: float, at: Vector2) -> void:
	_zoom_target = clampf(_zoom_target * pow(ZOOM_STEP, steps), ZOOM_MIN, ZOOM_MAX)
	_anchor = at
	_flying = false
	_velocity = Vector2.ZERO


func _recenter() -> void:
	var focus: Vector2 = _focus()
	_fly_target = Vector2(focus.x, 38.0)
	_flying = true
	_velocity = Vector2.ZERO
	_zoom_target = focus.y
	_anchor = size * 0.5


func _fly_to(n: int) -> void:
	_fly_target = Vector2(_level_x(n) + 8.0, 38.0)
	_flying = true
	_velocity = Vector2.ZERO
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
	return clampf(minf(size.x / 640.0, size.y / 360.0), ZOOM_MIN, 1.2)


func _screen_of(world: Vector2) -> Vector2:
	return ((world - _center) * _zoom + _stage.size * 0.5).round()


func _world_x(screen_x: float) -> float:
	return _center.x + (screen_x - _stage.size.x * 0.5) / _zoom


func _phase(n: int) -> float:
	return VineStyle.rand(n * 7 + 3) * TAU


func _node_world(n: int) -> Vector2:
	var x: float = _level_x(n)
	return Vector2(x, _course(x) + sin(_time * 0.7 + _phase(n)) * 1.4)


func _node_screen(n: int) -> Vector2:
	return _screen_of(_node_world(n))


func _node_radius(n: int) -> float:
	return roundf((14.0 if LevelRewards.is_milestone(n) else 11.0) * sqrt(_zoom))


func _compact() -> bool:
	return _zoom < COMPACT_ZOOM


func _appear(n: int) -> float:
	var d: float = absf(float(n - _level))
	return clampf((_open_t - 0.1 - d * 0.012) / 0.4, 0.0, 1.0)


func _card_size(n: int) -> Vector2:
	var rows: int = _rows(n).size()
	var milestone: bool = LevelRewards.is_milestone(n)
	return Vector2(88.0 if milestone else 66.0, 7.0 + (12.0 if milestone else 0.0) + rows * 10.0)


func _card_rect(n: int) -> Rect2:
	var at: Vector2 = _node_screen(n)
	var card: Vector2 = _card_size(n)
	return Rect2((at + Vector2(-card.x * 0.5, _node_radius(n) + 12.0)).round(), card)


func _card_shown(n: int) -> bool:
	return not _compact() or n == _selected or n == _hover


func _push_veil() -> void:
	var lights: PackedVector4Array = PackedVector4Array()
	for n: int in range(1, _level + 1):
		var t: float = _appear(n)
		var radius: float = lerpf(14.0, 104.0, 1.0 - pow(1.0 - t, 3.0))
		radius += exp(-float(_burst.get(n, 9.0)) * 1.6) * 22.0 + exp(-float(_born.get(n, 9.0)) * 1.2) * 26.0
		lights.append(Vector4(_level_x(n), LIGHT_Y, radius, 0.0))
	if _level < _max_level(): ## the next level glows up as the XP fills
		lights.append(Vector4(_level_x(_level + 1), LIGHT_Y, (24.0 + _fraction * 62.0) * _appear(_level + 1), 0.0))
	var count: int = mini(lights.size(), 40)
	lights.resize(40)
	_material.set_shader_parameter("view_size", _stage.size)
	_material.set_shader_parameter("center", _center)
	_material.set_shader_parameter("zoom", _zoom)
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_material.set_shader_parameter("opening", smoothstep(0.0, 1.0, _open_t))
	_material.set_shader_parameter("lights", lights)
	_material.set_shader_parameter("light_count", count)


func _on_claimed(claimed_level: int, collected: bool) -> void:
	_pending = 0
	var before: int = _claimed
	_refresh_state()
	if not collected or not visible:
		for kind: String in LevelRewards.KINDS:
			_shown[kind] = _stat(kind, claimed_level)
		return
	for n: int in range(before + 1, claimed_level + 1):
		_burst[n] = -float(n - before - 1) * 0.16 ## a wave from the lowest one up
	var milestone: bool = false
	for n: int in range(before + 1, claimed_level + 1):
		milestone = milestone or LevelRewards.is_milestone(n)
	_play("milestone" if milestone else "claim")
	_fly_to(claimed_level)


func _on_leveled(new_level: int) -> void:
	if not visible:
		return
	_refresh_state()
	_born[new_level] = 0.0
	_play("ready")


func _play(kind: String) -> void:
	var path: String = "res://assets/audio/progress/" + kind + ".wav"
	if ResourceLoader.exists(path):
		_voice.stream = load(path) as AudioStream
		_voice.play()


func _cancel_hold() -> void:
	_held = false
	_hold = 0.0


# ------------------------------------------------------------------------------------------------ picking and input

func _pick(at: Vector2) -> int:
	if not Rect2(Vector2.ZERO, _stage.size).has_point(at) or _ui_visibility(at) < 0.5:
		return 0
	for n: int in range(1, _max_level() + 1):
		var node: Vector2 = _node_screen(n)
		if absf(node.x - at.x) > 120.0:
			continue
		if _appear(n) > 0.6 and node.distance_to(at) <= maxf(15.0, _node_radius(n) + 5.0):
			return n
	for n: int in range(1, _max_level() + 1):
		if _card_shown(n) and _appear(n) > 0.6 and _card_rect(n).grow(2.0).has_point(at):
			return n
	return 0


## Graph marks fade behind the floating blocks (they are cards on the vine, never opaque panels).
func _ui_visibility(at: Vector2) -> float:
	var zones: Array[Rect2] = [
		Rect2(0, 44, 184, 84),
		Rect2(0, size.y - 108, 250, 81),
		_action_rect(),
		Rect2(size.x - 160, 40, 160, 44),
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
				var picked: int = _pick(local - _stage.position)
				if mouse.button_index == MOUSE_BUTTON_MIDDLE:
					_dragging = true
					_flying = false
				elif _zoom_rect().has_point(local):
					_slider_drag = true
					_set_zoom_from(local.y)
				elif _action_rect().has_point(local):
					_begin_hold(true, false)
				elif picked > 0:
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
			_center = (_center - motion.relative / _zoom)
			_clamp_center()
			_velocity = (-motion.relative / _zoom) * 30.0 + _velocity * 0.5
			_since_motion = 0.0
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_begin_hold(false, true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_accept"):
		_cancel_hold()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_select_step(-1 if event.is_action_pressed("ui_left") else 1)
		get_viewport().set_input_as_handled()


func _begin_hold(mouse: bool, on_node: bool) -> void:
	var target: int = _hold_target(on_node)
	if _can_claim(target) and _pending == 0 and _open_t > 0.8:
		_held = true
		_hold_mouse = mouse
		_hold_on_node = on_node


func _select(n: int) -> void:
	if n != _selected:
		_selected = n
		_cancel_hold()
		_play("focus")


func _select_step(direction: int) -> void:
	var n: int = clampi(_selected + direction, 1, _max_level())
	_select(n)
	var at: Vector2 = _node_screen(n)
	if not Rect2(Vector2(60, 40), _stage.size - Vector2(120, 80)).has_point(at):
		_fly_to(n)


# ------------------------------------------------------------------------------------------------ drawing helpers

func _text(canvas: CanvasItem, value: String, at: Vector2, color: Color, scale_value: float = 1.0) -> void:
	canvas.draw_set_transform(at.round(), 0.0, Vector2.ONE * scale_value)
	PixelText.draw(canvas, value, Vector2i.ZERO, color, Color(VineStyle.OUTLINE, color.a * 0.9))
	canvas.draw_set_transform(Vector2.ZERO)


func _text_centered(canvas: CanvasItem, value: String, at: Vector2, color: Color) -> void:
	_text(canvas, value, at - Vector2(PixelText.width(value) * 0.5, 0), color)


func _text_backing(rect: Rect2, opacity: float = 0.9) -> void:
	VineStyle.paper(_chrome, Rect2(rect.position.round(), rect.size.round()), opacity, VineStyle.void_amount(), int(rect.position.x) * 3 + int(rect.position.y))


## Dithered halo: a cached ordered-dither falloff, so glows share the veil's Bayer look.
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


func _icon(canvas: CanvasItem, kind: String, at: Vector2, alpha: float) -> void:
	var rows: Array = ICONS.get(kind, ICONS["seed"])
	var color: Color = KIND_COLORS.get(kind, TEAL)
	for y: int in rows.size():
		var line: String = rows[y]
		for x: int in line.length():
			if line[x] == "#":
				canvas.draw_rect(Rect2(at + Vector2(x, y), Vector2.ONE), Color(color.lightened(0.28) if y == 0 or x == 0 else color, alpha))


# ------------------------------------------------------------------------------------------------ the vine and the sap

func _draw_web() -> void:
	if _progress == null:
		return
	var void_level: float = VineStyle.void_amount()
	var xr: float = _level_x(_level) + _fraction * SPACING ## where the XP has grown to
	var xc: float = _level_x(_claimed) ## sap up to here is collected (teal), beyond it waits (gold)
	var grow: float = smoothstep(0.05, 0.8, _open_t)
	var reach: float = grow * (_level_x(_max_level()) + 400.0)
	var thick: int = clampi(roundi(3.0 * sqrt(_zoom)) + 1, 3, 6)
	var left: int = 0
	var right: int = int(_stage.size.x)
	for sx: int in range(left, right):
		var wx: float = _world_x(float(sx))
		if wx < -70.0 or wx > _level_x(_max_level()) + 120.0 or absf(wx - xr) > reach:
			continue
		var sy: int = roundi(_screen_of(Vector2(wx, _course(wx))).y)
		if wx <= xr:
			var fade: float = smoothstep(-70.0, -10.0, wx)
			var bark: Color = VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level * 0.6)
			var lit: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level * 0.6)
			var top: int = sy - int(thick * 0.5)
			_web.draw_rect(Rect2(sx, top - 1, 1, thick + 2), Color(VineStyle.OUTLINE, fade))
			_web.draw_rect(Rect2(sx, top, 1, thick), Color(bark, fade))
			if sx % 3 != 1:
				_web.draw_rect(Rect2(sx, top, 1, 1), Color(lit, fade))
			if sx % 5 == 0:
				_web.draw_rect(Rect2(sx, top + thick - 1, 1, 1), Color(bark.darkened(0.35), fade))
			# the sap: a thin bright thread through the bark
			var collected: bool = wx <= xc + 4.0
			var tone: Color = TEAL if collected else GOLD
			var surge: float = 0.0
			for wave: int in 2:
				var front: float = fposmod(_time * 52.0 - wave * 410.0, maxf(xr, 1.0) + 220.0) - 30.0
				surge = maxf(surge, exp(-pow((wx - front) / 26.0, 2.0)))
			var edge_fade: float = smoothstep(xr - 4.0, xr - 40.0, wx) ## the sap thins towards its bud
			var strength: float = (0.5 + surge * 0.5) * fade * lerpf(0.55, 1.0, edge_fade)
			_web.draw_rect(Rect2(sx, sy, 1, 1), Color(tone.lerp(Color.WHITE, surge * 0.35), strength))
			if surge > 0.35:
				_web.draw_rect(Rect2(sx, sy - 1, 1, 1), Color(tone, surge * 0.28 * fade))
		else:
			# ahead: only a thin, dotted tendril that the fog slowly swallows
			var away: float = (wx - xr) / 520.0
			var alpha: float = clampf(0.85 - away, 0.0, 1.0) * grow
			if alpha > 0.02 and (sx % 2 == 0 or away < 0.2):
				_web.draw_rect(Rect2(sx, sy, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, 0.4 + void_level * 0.3), alpha))
				if sx % 4 == 0:
					_web.draw_rect(Rect2(sx, sy + 1, 1, 1), Color(VineStyle.BARK, alpha * 0.8))
	_draw_leaves(xr, xc, grow, void_level)
	_draw_motes(xr, grow)


func _draw_leaves(xr: float, xc: float, grow: float, void_level: float) -> void:
	var first: int = maxi(int((_world_x(-12.0) - 20.0) / 24.0), 0)
	var last: int = int((_world_x(_stage.size.x + 12.0) + 20.0) / 24.0)
	for k: int in range(first, last + 1):
		var wx: float = float(k) * 24.0 + VineStyle.rand(k * 3 + 1) * 12.0
		if wx > xr + 6.0 or wx > grow * (xr + 400.0) or VineStyle.rand(k + 91) < 0.18:
			continue
		var up: int = -1 if k % 2 == 0 else 1
		var base: Vector2 = _screen_of(Vector2(wx, _course(wx)))
		var size_px: int = 3 if VineStyle.rand(k + 5) > 0.45 else 2
		var collected: bool = wx <= xc + 4.0
		var tone: Color = VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level * 0.7)
		var light: Color = VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level * 0.7)
		if not collected: ## the leaves of the waiting stretch carry a little gold
			tone = tone.lerp(GOLD.darkened(0.45), 0.4)
			light = light.lerp(GOLD, 0.45)
		var sway: int = roundi(sin(_time * 1.1 + float(k) * 1.7) * 0.6)
		VineStyle.leaf(_web, base + Vector2(sway, up * 2), 1 if k % 3 != 0 else -1, up, size_px, tone, light)


## Drifting seeds of light over the lit road (stateless: a pure function of the clock).
func _draw_motes(xr: float, grow: float) -> void:
	for i: int in 26:
		var seed_value: int = i * 11 + 4
		var along: float = VineStyle.rand(seed_value) * xr
		var rise: float = fposmod(_time * (5.0 + VineStyle.rand(seed_value + 1) * 5.0) + VineStyle.rand(seed_value + 2) * 60.0, 54.0)
		var wx: float = along + sin(_time * 0.6 + float(i)) * 6.0
		var at: Vector2 = _screen_of(Vector2(wx, _course(along) - 4.0 - rise * 0.8))
		if at.x < -4.0 or at.x > _stage.size.x + 4.0:
			continue
		var alpha: float = sin(rise / 54.0 * PI) * 0.55 * grow
		var tone: Color = TEAL if along <= _level_x(_claimed) else GOLD
		_web.draw_rect(Rect2(at, Vector2.ONE), Color(tone.lightened(0.3), alpha))
		if i % 4 == 0:
			_web.draw_rect(Rect2(at + Vector2(1, 0), Vector2.ONE), Color(tone, alpha * 0.4))


# ------------------------------------------------------------------------------------------------ globes and cards

func _draw_orbs() -> void:
	if _progress == null:
		return
	var order: Array[int] = []
	for n: int in range(1, _max_level() + 1):
		var node: Vector2 = _node_screen(n)
		if node.x > -100.0 and node.x < _stage.size.x + 100.0:
			order.append(n)
	order.sort_custom(func(a: int, b: int) -> bool: return absi(a - _selected) > absi(b - _selected)) ## the selected one on top
	for n: int in order:
		_draw_vine_stem(n)
	_draw_xp_bud()
	for n: int in order:
		_draw_node(n)
	for n: int in order:
		if _card_shown(n):
			_draw_card(n)
		else:
			_draw_pips(n)
	for n: int in order:
		_draw_burst(n)


## The small thread that carries the card below the globe.
func _draw_vine_stem(n: int) -> void:
	if not _card_shown(n):
		return
	var appear: float = _appear(n)
	if appear <= 0.05:
		return
	var node: Vector2 = _node_screen(n)
	var rect: Rect2 = _card_rect(n)
	var alpha: float = appear * _veil_alpha(n) * _ui_visibility(rect.get_center())
	var start: int = int(node.y + _node_radius(n))
	var end: int = int(rect.position.y + 1.0)
	for y: int in range(start, end):
		_orbs.draw_rect(Rect2(node.x + roundf(sin((y - start) * 0.5 + _phase(n)) * 0.6), y, 1, 1), Color(VineStyle.BARK_LIGHT if y % 2 == 0 else VineStyle.BARK, alpha))


func _draw_node(n: int) -> void:
	var appear: float = _appear(n)
	if appear <= 0.01:
		return
	var at: Vector2 = _node_screen(n)
	var state: int = _state(n)
	var milestone: bool = LevelRewards.is_milestone(n)
	var tone: Color = _tone(n)
	var alpha: float = appear * _ui_visibility(at) * lerpf(0.55, 1.0, _veil_alpha(n)) if state == 0 else appear * _ui_visibility(at)
	var phase: float = _phase(n)
	var interest: float = float(_interest.get(n, 0.0))
	var radius: float = _node_radius(n) * lerpf(0.5, 1.0, VineStyle.back_out(clampf(appear, 0.0, 1.0)))
	var breath: float = sin(_time * 1.15 + phase) * 0.5 + 0.5
	var waiting: float = (0.6 + 0.4 * sin(_time * 3.2 + phase)) if state == 1 else 0.0
	var born: float = exp(-float(_born.get(n, 9.0)) * 1.4)
	var life: float = 0.38 if state == 0 else 1.0
	var burst: float = exp(-maxf(float(_burst.get(n, 9.0)), 0.0) * 1.8) if float(_burst.get(n, 9.0)) >= 0.0 else 0.0
	_halo(_orbs, at, radius + (26.0 if milestone else 20.0), tone, alpha * (0.55 + breath * 0.3 + waiting * 1.1 + interest * 0.5 + burst * 1.4 + born * 1.2) * life)
	# the flower: a bud while the level lies ahead, half open while it waits, in full bloom once collected; holding on it opens the petals
	var charging: bool = (_held or _pending > 0) and _hold_on_node and n == (_pending if _pending > 0 else _hold_target(_hold_on_node))
	var charge: float = (1.0 if _pending > 0 else _hold) if charging else 0.0
	var open: float = 0.12 + interest * 0.2
	if state == 1:
		open = lerpf(0.55 + waiting * 0.06, 0.12, born) + charge * 0.45 + interest * 0.12
	elif state == 2:
		open = 1.0 - 0.45 * burst
	BloomOrb.draw(_orbs, at, radius * 1.18, tone, alpha, open, life, breath, _time, n, interest + waiting * 0.6 + charge, 12 if milestone else 6 + n % 3)
	# the number in the heart (small zoom: only milestones carry it below)
	var label: String = str(n)
	if radius >= 8.0:
		var label_at: Vector2 = at + Vector2(-PixelText.width(label) * 0.5 + 0.5, -2.0)
		if open < 0.8:
			_orbs.draw_circle(at, 4.5, Color(INK, alpha * 0.82))
		_text(_orbs, label, label_at, Color(tone.lightened(0.55) if state != 0 else DIM, alpha * (1.0 if state != 0 else 0.75)))
	elif milestone or n == _level or n == _selected:
		_text(_orbs, label, at + Vector2(-PixelText.width(label) * 0.5, radius + 4.0), Color(tone.lightened(0.4), alpha))
	if state != 0: ## pollen drifts off a living flower; a waiting one sheds gold sparks
		for spark: int in 3:
			var rise: float = fposmod(_time * (0.9 if state == 1 else 0.45) + phase + spark * 0.33, 1.0)
			var spark_tone: Color = GOLD if state == 1 else TEAL
			_orbs.draw_rect(Rect2((at + Vector2(sin(phase + spark * 2.0 + rise * 2.0) * radius * 0.8, -radius - rise * 14.0)).round(), Vector2.ONE), Color(spark_tone.lightened(0.3), alpha * sin(rise * PI) * (0.8 if state == 1 else 0.5)))
	if interest > 0.01:
		for part: int in 2:
			var angle: float = -_time * 0.22 + phase + part * PI
			_orbs.draw_arc(at, radius + 7.0, angle, angle + 0.85, 14, Color(TEXT, alpha * interest * 0.65), 1.0)
	var target: int = _hold_target(_hold_on_node)
	if (_held or _pending > 0) and n == (_pending if _pending > 0 else target) and _hold_on_node:
		_draw_charge(at, radius + 9.0, alpha, tone)


func _draw_charge(at: Vector2, radius: float, alpha: float, tone: Color) -> void:
	var charge: float = 1.0 if _pending > 0 else _hold
	if charge <= 0.0:
		return
	var pulse: float = 0.6 + 0.4 * sin(_time * 14.0) if _pending > 0 else 1.0
	_orbs.draw_arc(at, radius, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, Color(tone, alpha * pulse), 2.0)
	for gather: int in 8: ## the light gathers into the globe as the hold completes
		var angle: float = gather * TAU / 8.0 + _time * 0.9
		var pull: float = fposmod(charge * 1.4 + gather * 0.125, 1.0)
		var spot: Vector2 = at + Vector2.from_angle(angle) * lerpf(radius + 16.0, radius - 6.0, pull)
		_orbs.draw_rect(Rect2(spot.round(), Vector2.ONE), Color(tone.lightened(0.4), alpha * charge * pull))


## The bud where the sap has grown to: the XP of the current level.
func _draw_xp_bud() -> void:
	if _level >= _max_level() and _fraction >= 1.0:
		return
	var appear: float = smoothstep(0.35, 0.85, _open_t)
	var x: float = _xr_shown
	var at: Vector2 = _screen_of(Vector2(x, _course(x)))
	if at.x < -30.0 or at.x > _stage.size.x + 30.0:
		return
	var beat: float = 0.5 + 0.5 * sin(_time * 2.4)
	VineStyle.glow(_orbs, at, 12.0 + beat * 3.0, GOLD, 0.8 * appear)
	_orbs.draw_rect(Rect2(at - Vector2(2, 2), Vector2(5, 5)), Color(VineStyle.OUTLINE, appear))
	_orbs.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 3)), Color(GOLD.darkened(0.15), appear))
	_orbs.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, appear))
	for k: int in 4: ## four tiny petals open and close
		var open: float = 2.0 + beat * 1.5
		var offset: Vector2 = [Vector2(-open, 0), Vector2(open, 0), Vector2(0, -open), Vector2(0, open)][k]
		_orbs.draw_rect(Rect2((at + offset).round(), Vector2.ONE), Color(VineStyle.PETAL, appear * 0.85))
	var label: String = "%d / %d XP" % [Levels.xp_into(_progress.xp), Levels.xp_to_next(_level)]
	var label_at: Vector2 = at + Vector2(-PixelText.width(label) * 0.5, -34.0)
	_text(_orbs, label, label_at, Color(GOLD, appear * _ui_visibility(label_at)))


func _draw_pips(n: int) -> void:
	var appear: float = _appear(n)
	if appear <= 0.05:
		return
	var node: Vector2 = _node_screen(n)
	var rows: Array[Dictionary] = _rows(n)
	var alpha: float = appear * _veil_alpha(n) * _ui_visibility(node)
	var start: Vector2 = node + Vector2(-float(rows.size()) * 2.0 + 0.5, _node_radius(n) + 7.0)
	for i: int in rows.size():
		var color: Color = KIND_COLORS.get(String(rows[i].kind), TEAL)
		_orbs.draw_rect(Rect2((start + Vector2(i * 4, 0)).round(), Vector2(3, 3)), Color(INK, alpha))
		_orbs.draw_rect(Rect2((start + Vector2(i * 4, 0)).round() + Vector2.ONE, Vector2.ONE), Color(color, alpha))


func _draw_card(n: int) -> void:
	var appear: float = _appear(n)
	if appear <= 0.05:
		return
	var knowledge: int = _knowledge(n)
	var state: int = _state(n)
	var milestone: bool = LevelRewards.is_milestone(n)
	var rect: Rect2 = _card_rect(n)
	rect.position.y += roundf((1.0 - VineStyle.back_out(appear)) * -10.0)
	var alpha: float = appear * _veil_alpha(n) * _ui_visibility(rect.get_center())
	if n == _selected or n == _hover:
		alpha = maxf(alpha, appear * 0.8 * float(_interest.get(n, 0.0)))
	var interest: float = float(_interest.get(n, 0.0))
	var void_level: float = VineStyle.void_amount()
	var waiting: float = (0.6 + 0.4 * sin(_time * 3.2 + _phase(n))) if state == 1 else 0.0
	var burst_age: float = float(_burst.get(n, 9.0))
	var flash: float = exp(-maxf(burst_age, 0.0) * 2.2) if burst_age >= 0.0 else 0.0
	if state == 1:
		_halo(_orbs, rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.8, GOLD, alpha * (0.35 + waiting * 0.45))
	if flash > 0.02:
		_halo(_orbs, rect.get_center(), maxf(rect.size.x, rect.size.y) * 1.0, TEAL.lerp(Color.WHITE, 0.3), alpha * flash * 1.6)
	VineStyle.paper(_orbs, rect, alpha, void_level, n * 7)
	if state == 1: ## a golden lit edge on the top
		_orbs.draw_rect(Rect2(rect.position + Vector2(3, 1), Vector2(rect.size.x - 6.0, 1)), Color(GOLD, alpha * (0.35 + waiting * 0.4)))
	var y: float = rect.position.y + 5.0
	if milestone:
		var title: String = _cover_name(String(LevelRewards.milestone(n).get("name", "")), knowledge)
		_text_centered(_orbs, title, Vector2(rect.get_center().x, y), Color(GOLD if state != 0 else Color(VIOLET.lightened(0.3)), alpha))
		_orbs.draw_rect(Rect2(rect.position + Vector2(8, 11), Vector2(rect.size.x - 16.0, 1)), Color(VineStyle.BARK_LIGHT, alpha * 0.8))
		y += 12.0
	for row: Dictionary in _rows(n):
		var kind: String = String(row.kind)
		var color: Color = KIND_COLORS.get(kind, TEAL)
		_icon(_orbs, kind, Vector2(rect.position.x + 6.0, y - 0.0), alpha * (1.0 if state != 0 else 0.8))
		var text_color: Color = Color(TEXT if state != 2 else DIM.lerp(TEXT, 0.35), alpha)
		_text(_orbs, _cover(String(row.text), knowledge), Vector2(rect.position.x + 14.0, y), text_color if state != 0 else Color(color.lerp(DIM, 0.4), alpha))
		y += 10.0
	if state == 2 and n > 1: ## collected: a small teal check in the corner
		var corner: Vector2 = rect.position + Vector2(rect.size.x - 9.0, 3.0)
		for p: Vector2 in [Vector2(0, 2), Vector2(1, 3), Vector2(2, 2), Vector2(3, 1), Vector2(4, 0)]:
			_orbs.draw_rect(Rect2(corner + p, Vector2.ONE), Color(TEAL, alpha * 0.9))
	elif state == 1: ## waiting: a pulsing gold bud
		var bud: Vector2 = rect.position + Vector2(rect.size.x - 6.0, 5.0)
		VineStyle.glow(_orbs, bud, 6.0, GOLD, alpha * (0.5 + waiting * 0.4))
		_orbs.draw_rect(Rect2(bud - Vector2.ONE, Vector2(2, 2)), Color(GOLD.lightened(0.3), alpha))
	if interest > 0.01: ## the selection: four gold corners
		var frame: Rect2 = rect.grow(2.0)
		var corner_color: Color = Color(GOLD, alpha * interest)
		for c: Vector2 in [frame.position, Vector2(frame.end.x - 3.0, frame.position.y), Vector2(frame.position.x, frame.end.y - 1.0), Vector2(frame.end.x - 3.0, frame.end.y - 1.0)]:
			_orbs.draw_rect(Rect2(c, Vector2(3, 1)), corner_color)
		for c: Vector2 in [frame.position, Vector2(frame.end.x - 1.0, frame.position.y), Vector2(frame.position.x, frame.end.y - 3.0), Vector2(frame.end.x - 1.0, frame.end.y - 3.0)]:
			_orbs.draw_rect(Rect2(c, Vector2(1, 3)), corner_color)


## Rings and sparks where a reward was just collected.
func _draw_burst(n: int) -> void:
	if not _burst.has(n):
		return
	var age: float = float(_burst[n])
	if age < 0.0:
		return
	var at: Vector2 = _node_screen(n)
	var tone: Color = TEAL.lerp(GOLD, 0.35)
	var radius: float = _node_radius(n)
	_orbs.draw_arc(at, radius + age * 52.0 * _zoom, 0.0, TAU, 64, Color(tone, maxf(0.0, 0.7 - age * 0.5)), 1.0)
	if age < 0.9:
		_orbs.draw_arc(at, radius + age * 30.0 * _zoom, 0.0, TAU, 48, Color(VineStyle.PETAL, maxf(0.0, 0.55 - age * 0.7)), 1.0)
	for spark: int in 16:
		var angle: float = float(spark) / 16.0 * TAU + VineStyle.rand(spark + n) * 0.3
		var distance: float = age * (24.0 + VineStyle.rand(spark + 3) * 34.0)
		var spot: Vector2 = at + Vector2.from_angle(angle) * distance + Vector2(0, age * age * 10.0)
		_orbs.draw_rect(Rect2(spot.round(), Vector2.ONE), Color(tone.lightened(0.35), maxf(0.0, 1.0 - age * 0.8)))
	# the card throws a shower of motes upwards
	var rect: Rect2 = _card_rect(n)
	for k: int in 10:
		var along: float = VineStyle.rand(k * 5 + n)
		var rise: float = age * (12.0 + VineStyle.rand(k + 2) * 22.0)
		_orbs.draw_rect(Rect2((Vector2(rect.position.x + along * rect.size.x, rect.position.y + 3.0 - rise)).round(), Vector2.ONE), Color(GOLD.lightened(0.25), maxf(0.0, 1.0 - age * 0.7)))


# ------------------------------------------------------------------------------------------------ the frame around it

func _draw_chrome() -> void:
	if not visible or _progress == null:
		return
	var void_level: float = VineStyle.void_amount()
	var plate: float = clampf((_open_t - 0.35) / 0.5, 0.0, 1.0)
	VineStyle.tag(_chrome, "FORTSCHRITT", Vector2(size.x * 0.5, 0), plate, void_level, _time)
	_text_centered(_chrome, "DER WACHSENDE WEG", Vector2(size.x * 0.5, 29), DIM)
	_draw_level_vine(void_level)
	_draw_stats(void_level)
	_draw_details(void_level)
	_draw_action(void_level)
	_draw_zoom_vine(void_level)
	var controls: String = "ZIEHEN / WASD: SCHIEBEN   RAD / Q E: ZOOM   R: MITTE   HALTEN: EINSAMMELN   P / ESC: ZURÜCK" if InputManager.using_mouse else "STICK: SCHIEBEN   LINKS RECHTS: STUFE   A: HALTEN   START: ZURÜCK"
	var hint_width: float = PixelText.width(controls) + 16.0
	_text_backing(Rect2(size.x * 0.5 - hint_width * 0.5, size.y - 19, hint_width, 15), 0.68)
	_text_centered(_chrome, controls, Vector2(size.x * 0.5, size.y - 15), Color(DIM, 0.75))


## Top right: the level, the XP, and what the level does to the night.
func _draw_level_vine(void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.4) / 0.5, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return 42.0 + 3.0 * sin((size.x - x) * 0.045)
	VineStyle.branch(_chrome, size.x, size.x - 150.0, course, 4, void_level, 45.0, _time, reach)
	VineStyle.foliage(_chrome, size.x, size.x - 150.0, course, 7, 470, void_level, 45.0, _time, reach)
	_text(_chrome, "STUFE %d / %d" % [_level, _max_level()], Vector2(size.x - 142, 52), GOLD)
	var more: int = roundi((NightRules.budget(_level, 1, 1) / NightRules.budget(1, 1, 1) - 1.0) * 100.0)
	var tougher: int = roundi((NightRules.strength(_level, 0.0) - 1.0) * 100.0)
	_text(_chrome, "NÄCHTE +%d %% / ZÄHER +%d %%" % [more, tougher], Vector2(size.x - 142, 63), Color(DIM, 0.85))


## Top left: the character as it is now (collected rewards only), with what is still waiting in gold.
func _draw_stats(void_level: float) -> void:
	var y: float = 40.0
	var reach: float = clampf((_open_t - 0.42) / 0.5, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return y + 3.0 * sin(x / 170.0 * PI) + sin(x * 0.07 + 2.0) * 1.1
	var block: Rect2 = Rect2(6, y + 7, 170, 74)
	_text_backing(block, 0.94)
	for x: float in [18.0, 158.0]:
		_chrome.draw_line(Vector2(x, float(course.call(x)) + 2), Vector2(x, block.position.y), VineStyle.BARK_LIGHT, 1.0)
	VineStyle.branch(_chrome, 0.0, 170.0, course, 4, void_level, 50.0, _time, reach)
	VineStyle.foliage(_chrome, 0.0, 170.0, course, 6, 530, void_level, 50.0, _time, reach)
	_text(_chrome, "DEIN STAND", Vector2(12, y + 12), GOLD)
	var rows: Array[Array] = [["health", "LEBEN"], ["stamina", "AUSDAUER"], ["armor", "RÜSTUNG"], ["overheal", "ÜBERHEILUNG"], ["talisman", "TALISMANE"]]
	var after: Dictionary = LevelRewards.stats_at(_level)
	for i: int in rows.size():
		var kind: String = rows[i][0]
		var row_y: float = y + 23.0 + i * 10.0
		_icon(_chrome, kind, Vector2(12, row_y), 1.0)
		_text(_chrome, String(rows[i][1]), Vector2(20, row_y), DIM)
		var now: float = float(_shown.get(kind, _stat(kind, _claimed)))
		var value: String = ("%d %%" % roundi(now)) if kind == "overheal" else str(roundi(now))
		_text(_chrome, value, Vector2(132.0 - PixelText.width(value), row_y), TEXT)
		var goal: float = _stat(kind, _level)
		var pending: float = goal - _stat(kind, _claimed)
		if pending > 0.01 and not after.is_empty():
			var plus: String = ("+%d %%" % roundi(pending)) if kind == "overheal" else "+%d" % roundi(pending)
			var pulse: float = 0.65 + 0.35 * sin(_time * 3.2)
			_text(_chrome, plus, Vector2(138, row_y), Color(GOLD, pulse))


## Bottom left: the selected level, its name and what it gives.
func _draw_details(void_level: float) -> void:
	var n: int = clampi(_selected, 1, _max_level())
	var knowledge: int = _knowledge(n)
	var state: int = _state(n)
	var milestone: bool = LevelRewards.is_milestone(n)
	var tone: Color = _tone(n)
	var y: float = size.y - 119.0
	var reach: float = clampf((_open_t - 0.42) / 0.5, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return y + 3.0 * sin(x / 244.0 * PI) + sin(x * 0.07 + 2.0) * 1.1
	var block: Rect2 = Rect2(6, y + 7, 244, 78)
	_text_backing(block, 0.94)
	for post: float in [18.0, 232.0]:
		_chrome.draw_line(Vector2(post, float(course.call(post)) + 2), Vector2(post, block.position.y), VineStyle.BARK_LIGHT, 1.0)
	VineStyle.branch(_chrome, 0.0, 244.0, course, 4, void_level, 50.0, _time, reach)
	VineStyle.foliage(_chrome, 0.0, 244.0, course, 9, 570, void_level, 50.0, _time, reach)
	var status: String = "NOCH IM NEBEL"
	match state:
		1:
			status = "BEREIT ZUM EINSAMMELN"
		2:
			status = "EINGESAMMELT" if n > 1 else "DER ANFANG"
	_text(_chrome, "STUFE %d / %s" % [n, status], Vector2(12, y + 12), tone)
	var title: String = _cover_name(String(LevelRewards.milestone(n).get("name", "")), knowledge) if milestone else "STUFE %d" % n
	_text(_chrome, title, Vector2(12, y + 25), TEXT if knowledge >= 1 else DIM, 2.0)
	var note: String = String(LevelRewards.milestone(n).get("note", "")) if milestone else "EIN WENIG MEHR LEBEN UND AUSDAUER."
	if n == 1:
		note = "HIER BEGINNT DER WEG."
	_text(_chrome, note if knowledge >= 1 else "DAS SCHICKSAL LIEGT NOCH IM SCHLEIER.", Vector2(12, y + 46), DIM)
	var x: float = 12.0
	for row: Dictionary in _rows(n):
		var kind: String = String(row.kind)
		var text: String = _cover(String(row.text), knowledge)
		_icon(_chrome, kind, Vector2(x, y + 60), 1.0 if knowledge >= 1 else 0.6)
		_text(_chrome, text, Vector2(x + 8, y + 60), Color(KIND_COLORS.get(kind, TEAL), 1.0 if knowledge >= 1 else 0.6))
		x += 12.0 + PixelText.width(text)
		if x > 200.0:
			break
	if n == _level and _level < _max_level():
		_text(_chrome, "NÄCHSTE STUFE: NOCH %d XP" % (Levels.xp_to_next(_level) - Levels.xp_into(_progress.xp)), Vector2(12, y + 72), Color(GOLD, 0.8))


## Bottom right: the bud you hold to collect.
func _draw_action(void_level: float) -> void:
	var y: float = size.y - 119.0
	var reach: float = clampf((_open_t - 0.45) / 0.5, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return y + 3.0 * sin((size.x - x) / 216.0 * PI) + sin(x * 0.07 + 2.0) * 1.1
	var block: Rect2 = _action_rect()
	_text_backing(block, 0.94)
	for x: float in [size.x - 206.0, size.x - 54.0]:
		_chrome.draw_line(Vector2(x, float(course.call(x)) + 2), Vector2(x, block.position.y), VineStyle.BARK_LIGHT, 1.0)
	VineStyle.branch(_chrome, size.x, size.x - 216.0, course, 4, void_level, 50.0, _time, reach)
	VineStyle.foliage(_chrome, size.x, size.x - 216.0, course, 8, 610, void_level, 50.0, _time, reach)
	var waiting: int = maxi(_level - _claimed, 0)
	var active: bool = waiting > 0
	var tone: Color = GOLD if active else TEAL
	var charge: float = 1.0 if _pending > 0 else (_hold if not _hold_on_node else 0.0)
	var slot: Vector2 = Vector2(size.x - 80, block.position.y + 25 + sin(_time * 1.3) * 1.0)
	var breath: float = sin(_time * 1.15) * 0.5 + 0.5
	for row: int in range(int(float(course.call(slot.x))) + 1, int(slot.y) - 10):
		_chrome.draw_rect(Rect2(slot.x, row, 1, 1), VineStyle.BARK_LIGHT if row % 2 == 0 else VineStyle.BARK)
	_halo(_chrome, slot, 20.0, tone, ((0.65 + sin(_time * 3.2) * 0.2) + charge * 0.9) if active else 0.25)
	BloomOrb.draw(_chrome, slot, 13.0, tone, 1.0 if active else 0.6, (0.5 + charge * 0.5) if active else 0.3, 1.0 if active else 0.5, breath, _time, 77, charge, 8)
	if active:
		_chrome.draw_circle(slot, 4.5, Color(INK, 0.82))
		_text_centered(_chrome, str(waiting), slot + Vector2(0, -2.0), Color(VineStyle.PETAL, 1.0))
	if charge > 0.0:
		var pulse: float = 0.6 + 0.4 * sin(_time * 14.0) if _pending > 0 else 1.0
		_chrome.draw_arc(slot, 13.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, Color(tone, pulse), 2.0)
	var label: String = "HALTEN: ALLES EINSAMMELN" if waiting > 1 else ("HALTEN: EINSAMMELN" if waiting == 1 else "ALLES EINGESAMMELT")
	var detail: String = "BIS STUFE %d" % _level if active else "NÄCHSTE BELOHNUNG: STUFE %d" % _level_after()
	if _pending > 0:
		label = "DIE WURZELN ANTWORTEN ..."
	_text(_chrome, label, Vector2(size.x - 208, block.position.y + 12), tone if active else DIM)
	_text(_chrome, detail if _level < _max_level() or active else "DER WEG IST VOLLENDET", Vector2(size.x - 208, block.position.y + 25), DIM)
	if _held and _hold_on_node and _can_claim(_selected):
		_text(_chrome, "GEHALTEN: STUFE %d" % _selected, Vector2(size.x - 208, block.position.y + 38), Color(GOLD, 0.9))


func _level_after() -> int:
	return mini(_level + 1, _max_level())


func _draw_zoom_vine(void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.45) / 0.45, 0.0, 1.0)
	var bottom: float = size.y - 34.0
	var top: float = bottom - (bottom - 90.0) * reach
	var x: float = size.x - 22.0
	for row: int in range(int(top), int(bottom) + 1):
		var t: float = (bottom - row) / maxf(bottom - 90.0, 1.0)
		var px: float = x + sin(row * 0.06) * 1.5
		var thick: int = maxi(roundi(lerpf(3.0, 1.0, t)), 1)
		var taken: float = VineStyle.infection((bottom - row) * 0.5 + 40.0, void_level, int(row / 3.0))
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
