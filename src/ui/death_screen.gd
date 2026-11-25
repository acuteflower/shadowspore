class_name DeathScreen
extends Control
## The death screen ("der Biss"), local to the player who fell. About 3.4 s the shader (assets/shaders/death_bite.gdshader) plays:
## the colours drain and the shadow creeps in, two big magenta eyes open in the dark, look around and lunge, black jaws slam shut
## (slow motion when alone, white flash, shake), what is left of the picture is torn and eaten, a maw of teeth stays as its frame and
## the eyes keep watching from above. Then vines grow in and carry a card with two choices: ZURÜCKKEHREN (the host respawns her,
## the shadow floods the screen, then retreats from the middle as a ragged wave) and BEENDEN (quits without saving).
## The sequence always plays in full. The respawn waits for the choice (`Player.request_respawn`), nothing happens by itself.
## Everything runs in real time (also in the slow motion) on its own CanvasLayer above the HUD, so the HUD is torn with the world.

const SHADER: Shader = preload("res://assets/shaders/death_bite.gdshader")
const SOUNDS: Dictionary = {
	"stop": preload("res://assets/audio/death/stop.wav"),
	"rumble": preload("res://assets/audio/death/rumble.wav"),
	"bite": preload("res://assets/audio/death/bite.wav"),
	"drone": preload("res://assets/audio/death/drone.wav"),
	"return": preload("res://assets/audio/death/return.wav"),
}
const OPTIONS: Array[String] = ["ZURÜCKKEHREN", "BEENDEN"]
const INPUT_GUARD: float = 0.55 ## seconds after the card has grown before a key counts
const CARD_SIZE: Vector2 = Vector2(204, 108)
const EYE_Y_WATCH: float = 0.3 ## where the eyes hang after the bite (fraction of the height)
const REVIVE_TIMEOUT: float = 6.0
const SLOW_MOTION: float = 0.3
const MAGENTA_GLOW: Color = Color("ff4fd8")

enum Phase { IDLE, DYING, CHOOSING, RETURNING, QUITTING }

var _player: Node
var _health: HealthComponent
var _layer: CanvasLayer
var _rect: ColorRect
var _ui: Control
var _material: ShaderMaterial = ShaderMaterial.new()
var _phase: Phase = Phase.IDLE
var _gen: int = 0
var _clock: float = 0.0
var _focus: int = 0
var _hover: int = -1
var _guard: float = 0.0
var _drone: AudioStreamPlayer
var _slowed: bool = false
var _choices: Array[Dictionary] = []
var _map_zone: Atlas.Zone ## the zone she fell in (the card's little map), null = no map
var _map_death: Vector2 = Vector2.INF ## continent tiles
var _map_stone: Vector2 = Vector2.INF
var _map_home: Vector2 = Vector2.INF
const MAP_W: float = 78.0

var _dusk: float = 0.0
var _eyes: float = 0.0
var _eye_scale: float = 1.0
var _eye_alpha: float = 1.0
var _eye_y: float = 0.42
var _lunge: float = 0.0
var _bite: float = 0.0
var _eaten: float = 0.0
var _shock: float = 0.0
var _shake: float = 0.0
var _cover: float = 0.0
var _release: float = 0.0
var _ui_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer = CanvasLayer.new() ## above the HUD (layer 1) and the other overlays
	_layer.layer = 60
	_layer.visible = false
	get_tree().root.add_child.call_deferred(_layer) ## not under the HUD: the intro and story may hide it, the death screen must not hide
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = SHADER
	_rect.material = _material
	_layer.add_child(_rect)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	_ui.gui_input.connect(_on_ui_input)
	_layer.add_child(_ui)
	_drone = AudioStreamPlayer.new()
	_drone.stream = SOUNDS["drone"] as AudioStream
	_drone.volume_db = -11.0
	_drone.finished.connect(func() -> void: if _phase == Phase.CHOOSING: _drone.play())
	add_child(_drone)


func _exit_tree() -> void:
	_set_slow(false)
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()


## `player` is untyped on purpose (the player scene preloads the HUD).
func bind(player: Node) -> void:
	_player = player
	_health = player.health
	_health.changed.connect(_on_health)


func _on_health(current: float, _maximum: float) -> void:
	if current <= 0.0 and _phase == Phase.IDLE:
		_die()
	elif current > 0.0 and (_phase == Phase.DYING or _phase == Phase.CHOOSING):
		_come_back(false) ## healed from outside (a cheat): no need to ask the host


# ---------- the sequence ----------

func _wait(seconds: float, gen: int) -> bool:
	await get_tree().create_timer(seconds, true, false, true).timeout ## real time, also in the slow motion
	return gen == _gen


func _tween(property: String, to: float, seconds: float, ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	create_tween().set_ignore_time_scale(true).tween_property(self, property, to, seconds).set_trans(Tween.TRANS_SINE).set_ease(ease_type)


func _sound(id: String, volume_db: float = 0.0) -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = SOUNDS[id] as AudioStream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _set_slow(on: bool) -> void:
	if on and multiplayer.get_peers().is_empty(): ## alone only: others keep their time
		Engine.time_scale = SLOW_MOTION
		_slowed = true
	elif _slowed:
		Engine.time_scale = 1.0
		_slowed = false


func _reset() -> void:
	_dusk = 0.0
	_eyes = 0.0
	_eye_scale = 1.0
	_eye_alpha = 1.0
	_eye_y = 0.42
	_lunge = 0.0
	_bite = 0.0
	_eaten = 0.0
	_shock = 0.0
	_shake = 0.0
	_cover = 0.0
	_release = 0.0
	_ui_t = 0.0
	_focus = 0
	_hover = -1
	_rebuild_choices()


func _rebuild_choices() -> void:
	_choices.clear()
	_map_zone = null
	_map_death = Vector2.INF
	_map_stone = Vector2.INF
	_map_home = Vector2.INF
	if not is_inside_tree():
		_choices.append({"id": "home", "label": "ZURÜCKKEHREN", "sub": "", "waystone_id": "", "tone": VineStyle.WARM_GLOW})
		_choices.append({"id": "quit", "label": "BEENDEN", "sub": "", "waystone_id": "", "tone": Color(VineStyle.LEAF_VOID_LIGHT)})
		return
	var world: Node = get_tree().get_first_node_in_group("world")
	var director: ZoneDirector = null
	if world != null and world.has_method("director"):
		director = world.call("director") as ZoneDirector
	if director == null:
		director = get_tree().get_first_node_in_group("zone_director") as ZoneDirector
	if director == null:
		_choices.append({"id": "home", "label": "ZURÜCKKEHREN", "sub": "", "waystone_id": "", "tone": VineStyle.WARM_GLOW})
		_choices.append({"id": "quit", "label": "BEENDEN", "sub": "", "waystone_id": "", "tone": Color(VineStyle.LEAF_VOID_LIGHT)})
		return

	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
	var home_lbl: String = "ZUHAUSE" if (town != null and town.founded) else "KÜSTENLAGER"
	var zone_id: StringName = &""
	if _player != null:
		var peer_id: int = _player.name.to_int()
		if director.player_zone.has(peer_id):
			zone_id = director.player_zone[peer_id] as StringName
		if zone_id == &"" and _player is Node2D:
			var raw_px: Vector2 = (_player as Node2D).global_position
			if PocketSpace.is_pocket(raw_px):
				zone_id = PocketSpace.parent_zone_at(raw_px)
			elif director.atlas != null:
				zone_id = director.atlas.zone_at(director.continent_id, raw_px)

	var wm: Waystones = Waystones.of(get_tree())
	var ws_spec: Dictionary = wm.awake_waystone_in_zone(zone_id) if (wm != null and zone_id != &"") else {}
	if not ws_spec.is_empty():
		var ws_id: String = String(ws_spec.get("id", ""))
		var ws_name: String = String(ws_spec.get("name", "WÄCHTERIN DER BUCHT")).to_upper()
		_choices.append({"id": "waystone", "label": "WEGSTEIN", "sub": ws_name, "waystone_id": ws_id, "tone": Color("78f4e6")})
	_choices.append({"id": "home", "label": home_lbl, "sub": "", "waystone_id": "", "tone": VineStyle.WARM_GLOW})
	_choices.append({"id": "quit", "label": "BEENDEN", "sub": "", "waystone_id": "", "tone": Color(VineStyle.LEAF_VOID_LIGHT)})
	_focus = clampi(_focus, 0, maxi(_choices.size() - 1, 0))
	if director.atlas != null and zone_id != &"": ## the little map: where she fell, the waystone, home
		_map_zone = director.atlas.zone(zone_id)
		if _player is Node2D:
			_map_death = Atlas.tile_of(Interiors.outer(get_tree(), (_player as Node2D).global_position))
		if not ws_spec.is_empty() and wm != null:
			var stone_px: Vector2 = wm.arrival_position(String(ws_spec.get("id", "")))
			if stone_px.is_finite() and stone_px != Vector2.ZERO:
				_map_stone = Atlas.tile_of(stone_px)
		var home_px: Vector2 = world.call("respawn_point_for", _player.name.to_int() if _player != null else 1, &"home") as Vector2 if world != null and world.has_method("respawn_point_for") else Vector2.INF
		if home_px.is_finite():
			_map_home = Atlas.tile_of(home_px)


func _die() -> void:
	_gen += 1
	var gen: int = _gen
	_phase = Phase.DYING
	_reset()
	_clock = 0.0
	_layer.visible = true
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	InputManager.ui_blocking = true
	_sound("stop")
	_tween("_dusk", 1.0, 1.0)
	if not await _wait(0.55, gen):
		return
	_sound("rumble", -3.0) ## the eyes open
	_tween("_eyes", 1.0, 1.15, Tween.EASE_OUT)
	if not await _wait(1.15, gen):
		return
	_tween("_lunge", 1.0, 0.5, Tween.EASE_IN) ## they come closer
	_tween("_bite", 0.1, 0.5, Tween.EASE_IN)
	if not await _wait(0.5, gen):
		return
	_set_slow(true) ## the bite
	_sound("bite", 1.0)
	_tween("_bite", 1.0, 0.13, Tween.EASE_IN)
	if not await _wait(0.13, gen):
		return
	_shock = 1.0
	_shake = 1.0
	_eyes = 0.0
	_lunge = 0.0
	_tween("_shock", 0.0, 0.5, Tween.EASE_OUT)
	_tween("_shake", 0.0, 0.9, Tween.EASE_OUT)
	if _player != null and _player.has_method("add_shake"):
		_player.call("add_shake", 8.0)
	if not await _wait(0.28, gen): ## black
		return
	_set_slow(false)
	_eye_y = EYE_Y_WATCH
	_eye_scale = 0.5
	_eye_alpha = 0.75
	_tween("_bite", 0.3, 0.7, Tween.EASE_OUT) ## the jaws part: the maw stays as a frame
	_tween("_eaten", 1.0, 0.9)
	_tween("_eyes", 0.85, 1.0, Tween.EASE_OUT)
	if not await _wait(1.0, gen):
		return
	_rebuild_choices()
	_focus = 0
	_phase = Phase.CHOOSING
	_guard = INPUT_GUARD + 0.4
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	_drone.play()
	_tween("_ui_t", 1.0, 0.9, Tween.EASE_OUT)


func _choose(index: int) -> void:
	if _phase != Phase.CHOOSING or _guard > 0.0:
		return
	if index < 0 or index >= _choices.size():
		return
	var choice: Dictionary = _choices[index]
	var cid: String = String(choice.get("id", "home"))
	if cid == "quit":
		_quit()
	elif cid == "waystone":
		_come_back(true, String(choice.get("waystone_id", "")))
	else:
		_come_back(true, "", &"home")


## Respawn under black cover (`_cover == 1.0`), optionally at the awakened zone waystone, then retreat the shadow wave.
func _come_back(ask_host: bool, waystone_id: String = "", target: StringName = &"") -> void:
	_gen += 1
	var gen: int = _gen
	_phase = Phase.RETURNING
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_slow(false)
	_tween("_ui_t", 0.0, 0.3)
	_tween("_eyes", 0.0, 0.35)
	_tween("_cover", 1.0, 0.7)
	_drone.stop()
	if not await _wait(0.8, gen):
		return
	_eaten = 0.0
	_bite = 0.0
	_eyes = 0.0
	_dusk = 0.0
	var wm_resp: Waystones = Waystones.of(get_tree()) if is_inside_tree() else null
	if ask_host and not waystone_id.is_empty() and wm_resp != null:
		wm_resp.request_prepare_zone(waystone_id)
	if ask_host and _player != null and _player.has_method("request_respawn"): ## the host checks the waystone (awake, this zone)
		_player.call("request_respawn", StringName(waystone_id) if not waystone_id.is_empty() else target)
	var waited: float = 0.0
	while _health != null and _health.current <= 0.0 and waited < REVIVE_TIMEOUT:
		if not await _wait(0.1, gen):
			return
		waited += 0.1
	if ask_host and not waystone_id.is_empty() and _player != null and is_instance_valid(_player):
		if wm_resp != null:
			var st_node: WaystoneStatue = wm_resp.statue_node(waystone_id)
			if st_node != null and st_node.has_method("flare"):
				st_node.call("flare")
	if not await _wait(0.6, gen): ## black, the camera settles at the respawn point
		return
	_sound("return", -2.0)
	_tween("_release", 1.0, 1.3)
	if not await _wait(1.4, gen):
		return
	_finish()


func _quit() -> void:
	_gen += 1
	_phase = Phase.QUITTING
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tween("_ui_t", 0.0, 0.3)
	_tween("_cover", 1.0, 0.9)
	_drone.stop()
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit()


func _finish() -> void:
	_phase = Phase.IDLE
	_layer.visible = false
	_reset()
	InputManager.ui_blocking = false


# ---------- input ----------

func _input(event: InputEvent) -> void:
	if _phase != Phase.CHOOSING:
		return
	var opt_count: int = maxi(_choices.size(), 1)
	if event.is_action_pressed("ui_down"):
		_focus = posmod(_focus + 1, opt_count)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_focus = posmod(_focus - 1, opt_count)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_choose(_focus)
		get_viewport().set_input_as_handled()


func _on_ui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	var click: InputEventMouseButton = event as InputEventMouseButton
	if motion != null:
		_hover = _option_at(motion.position)
		if _hover >= 0:
			_focus = _hover
		GameCursor.set_hint(_ui, &"click" if _hover >= 0 else &"") ## the cursor sparkles over an option
	elif click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _option_at(click.position)
		if index >= 0:
			_choose(index)


func _card_size() -> Vector2:
	var extra: float = MAP_W + 10.0 if _map_zone != null else 0.0
	if _choices.size() >= 3:
		return Vector2(226.0 + extra, 144.0)
	return CARD_SIZE + Vector2(extra, 0.0)


func _card() -> Rect2:
	var csz: Vector2 = _card_size()
	return Rect2((size - csz) / 2.0 + Vector2(0, 14), csz).abs()


func _option_rect(index: int) -> Rect2:
	var card: Rect2 = _card()
	var csz: Vector2 = card.size
	var cur_y: float = card.position.y + (52.0 if _choices.size() >= 3 else 56.0)
	for i: int in index:
		var prev_sub: String = String(_choices[i].get("sub", "")) if i < _choices.size() else ""
		cur_y += 30.0 if not prev_sub.is_empty() else 22.0
	var my_sub: String = String(_choices[index].get("sub", "")) if index < _choices.size() else ""
	var row_h: float = 28.0 if not my_sub.is_empty() else 20.0
	var map_room: float = MAP_W + 10.0 if _map_zone != null else 0.0
	return Rect2(card.position.x + 14.0, cur_y, csz.x - 28.0 - map_room, row_h)


func _option_at(at: Vector2) -> int:
	for i: int in _choices.size():
		if _option_rect(i).has_point(at):
			return i
	return -1


# ---------- frame ----------

func _process(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	var real: float = delta / maxf(Engine.time_scale, 0.05)
	_clock = fmod(_clock + real, 20000.0)
	_guard = maxf(_guard - real, 0.0)
	var wander: float = 1.0 - _lunge
	var look: Vector2 = Vector2(sin(_clock * 1.3) * 0.9, sin(_clock * 0.7) * 0.5) * wander
	var size_px: Vector2 = _rect.size
	_material.set_shader_parameter("view_size", size_px)
	_material.set_shader_parameter("time", _clock)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_material.set_shader_parameter("dusk", _dusk)
	_material.set_shader_parameter("eyes", _eyes)
	_material.set_shader_parameter("eye_scale", _eye_scale * (1.0 + _lunge * 0.55))
	_material.set_shader_parameter("eye_alpha", _eye_alpha)
	_material.set_shader_parameter("eye_at", Vector2(0.5, _eye_y))
	_material.set_shader_parameter("look", look)
	_material.set_shader_parameter("bite", _bite)
	_material.set_shader_parameter("eaten", _eaten)
	_material.set_shader_parameter("shock", _shock)
	_material.set_shader_parameter("shake", _shake)
	_material.set_shader_parameter("cover", _cover)
	_material.set_shader_parameter("release", _release)
	_ui.queue_redraw()


func _text(text: String, centre_x: float, y: float, scale_px: int, color: Color) -> void:
	_ui.draw_set_transform(Vector2(roundf(centre_x - PixelText.width(text) * scale_px / 2.0), roundf(y)), 0.0, Vector2(scale_px, scale_px))
	PixelText.draw(_ui, text, Vector2i.ZERO, color, Color(VineStyle.OUTLINE, color.a))
	_ui.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ui() -> void:
	var p: float = _ui_t
	if p <= 0.0:
		return
	var void_level: float = maxf(VineStyle.void_amount(), 0.35)
	var card: Rect2 = _card()
	var mid_y: float = card.position.y + card.size.y / 2.0
	var length: float = card.position.x - 4.0
	for side: int in 2: ## a branch from each edge holds the card
		var from_x: float = 0.0 if side == 0 else size.x
		var to_x: float = length if side == 0 else size.x - length
		var course: Callable = func(x: float) -> float: return mid_y - 8.0 + 6.0 * sin(x * 0.03 + side * 2.0) + sin(x * 0.09 + side) * 1.2
		VineStyle.branch(_ui, from_x, to_x, course, 6, void_level, 60.0, _clock, p)
		VineStyle.foliage(_ui, from_x, to_x, course, 10, 600 + side * 40, void_level, 60.0, _clock, p)
	var rise: float = (1.0 - VineStyle.back_out(p)) * 14.0 ## the card unfurls into place
	var shown: Rect2 = Rect2(card.position + Vector2(0, rise), card.size)
	VineStyle.paper(_ui, shown, p, void_level, 71)
	VineStyle.glow(_ui, shown.get_center(), 90.0, MAGENTA_GLOW, 0.1 * p)
	_text("BESIEGT", shown.get_center().x, shown.position.y + 10.0, 3, Color(UiStyle.TEXT, p))
	_text("DER SCHATTEN HAT DICH GEHOLT", shown.get_center().x, shown.position.y + (35.0 if _choices.size() >= 3 else 38.0), 1, Color(UiStyle.TEXT_DIM, 0.9 * p))
	for i: int in _choices.size():
		var ch: Dictionary = _choices[i]
		var opt_r: Rect2 = _option_rect(i)
		var rect: Rect2 = Rect2(opt_r.position + Vector2(0, rise), opt_r.size)
		var focused: bool = i == _focus and _phase == Phase.CHOOSING
		var tone: Color = ch.get("tone", VineStyle.WARM_GLOW) as Color
		var sub: String = String(ch.get("sub", ""))
		if focused:
			var pulse: float = 0.75 + 0.25 * sin(_clock * 5.0)
			VineStyle.glow(_ui, rect.get_center(), 38.0, tone, 0.32 * p * pulse)
			_ui.draw_rect(Rect2(rect.position + Vector2(2, rect.size.y / 2.0 - 2.0), Vector2(4, 4)), Color(VineStyle.OUTLINE, p)) ## the bud
			_ui.draw_rect(Rect2(rect.position + Vector2(3, rect.size.y / 2.0 - 1.0), Vector2(2, 2)), Color(tone, p))
			_ui.draw_rect(Rect2(rect.end - Vector2(6, rect.size.y / 2.0 + 2.0), Vector2(4, 4)), Color(VineStyle.OUTLINE, p))
			_ui.draw_rect(Rect2(rect.end - Vector2(5, rect.size.y / 2.0 + 1.0), Vector2(2, 2)), Color(tone, p))
		_text(String(ch.get("label", "")), rect.get_center().x, rect.position.y + (2.0 if not sub.is_empty() else 3.0), 2, Color(tone if focused else UiStyle.TEXT_DIM, p))
		if not sub.is_empty():
			_text(sub, rect.get_center().x, rect.position.y + 18.0, 1, Color(tone.lightened(0.22) if focused else UiStyle.TEXT_DIM, 0.88 * p))
	_draw_zone_map(shown, p)
	_text("PFEILE: WÄHLEN   E / KLICK: BESTÄTIGEN", size.x / 2.0, shown.end.y + 8.0, 1, Color(UiStyle.TEXT_DIM, 0.5 * p))


## The zone she fell in as a little ink map on the card's right: its outline, a magenta cross where she fell, the awake
## waystone (teal) and home (warm), each only when it lies in this zone.
func _draw_zone_map(card: Rect2, p: float) -> void:
	if _map_zone == null or _map_zone.footprint.size() < 3:
		return
	var box: Rect2 = Rect2(card.end.x - 14.0 - MAP_W, card.position.y + 48.0, MAP_W, card.size.y - 62.0)
	var bounds: Rect2 = _map_zone.bbox if _map_zone.bbox.size.x > 0.0 else Rect2(_map_zone.footprint[0], Vector2.ONE)
	var scale: float = minf(box.size.x / maxf(bounds.size.x, 1.0), box.size.y / maxf(bounds.size.y, 1.0))
	var offset: Vector2 = box.position + (box.size - bounds.size * scale) * 0.5
	var to_box: Callable = func(tile: Vector2) -> Vector2: return (offset + (tile - bounds.position) * scale).round()
	var poly: PackedVector2Array = PackedVector2Array()
	var step: int = maxi(1, _map_zone.footprint.size() / 96)
	for i: int in range(0, _map_zone.footprint.size(), step):
		poly.append(to_box.call(_map_zone.footprint[i]) as Vector2)
	if poly.size() >= 3:
		var fill: PackedColorArray = PackedColorArray([Color(0.10, 0.08, 0.16, 0.85 * p)])
		if not Geometry2D.triangulate_polygon(poly).is_empty():
			_ui.draw_polygon(poly, fill)
		poly.append(poly[0])
		_ui.draw_polyline(poly, Color(Color("e3d3a4"), 0.8 * p), 1.0)
	_text(_map_zone.name, box.get_center().x, box.end.y + 2.0, 1, Color(UiStyle.TEXT_DIM, 0.8 * p))
	if _map_home.is_finite() and bounds.grow(1.0).has_point(_map_home):
		var h: Vector2 = to_box.call(_map_home) as Vector2
		_ui.draw_rect(Rect2(h - Vector2(1, 1), Vector2(3, 3)), Color(VineStyle.WARM_GLOW, p))
	if _map_stone.is_finite() and bounds.grow(1.0).has_point(_map_stone):
		var s: Vector2 = to_box.call(_map_stone) as Vector2
		VineStyle.glow(_ui, s, 5.0, Color("78f4e6"), 0.5 * p)
		_ui.draw_rect(Rect2(s + Vector2(0, -2), Vector2(1, 1)), Color(Color("78f4e6"), p))
		_ui.draw_rect(Rect2(s + Vector2(-1, -1), Vector2(3, 3)), Color(Color("78f4e6"), p))
	if _map_death.is_finite() and bounds.grow(1.0).has_point(_map_death):
		var d: Vector2 = to_box.call(_map_death) as Vector2
		var pulse: float = 0.7 + 0.3 * sin(_clock * 4.0)
		for k: int in range(-2, 3):
			_ui.draw_rect(Rect2(d + Vector2(k, k), Vector2(1, 1)), Color(MAGENTA_GLOW, p * pulse))
			_ui.draw_rect(Rect2(d + Vector2(k, -k), Vector2(1, 1)), Color(MAGENTA_GLOW, p * pulse))

