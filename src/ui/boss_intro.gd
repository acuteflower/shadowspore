class_name BossIntro
extends Control
## The boss entrance screen, local to every player who is near the arena (started by the boss itself: `BossIntro.play`). About 7 s, in two halves:
## 1. FLIGHT: two bars of shadow smoke slam shut from the top and the bottom (assets/shaders/boss_intro.gdshader), the colours drain into cold violet,
##    "shadow lightning" flickers through the picture (the picture turns negative for a few frames, cracks of light run across it, rows slip
##    sideways), the dark closes in round the boss and the camera pans to its pillar and pushes in a little while it swoops in from beyond the screen.
## 2. CARD: it touches down: white-violet flash, a ring of pressure runs out of it, the letters of its name slam down one by one (gold blocks with a bevel
##    and an ink outline, a streak behind each, chromatic ghosts), a crack of light tears open under the name, the epithet is typed in, the tracking
##    widens slowly. Then the name crumbles upwards into shadow, the bars open and the boss bar tears open (the boss waits for `finished`).
## The player is held still (`story_lock`) and the HUD hidden meanwhile; both are given back in `_restore`, also when the node is removed early.
## It runs in game time on its own CanvasLayer (55, above the HUD, under the death screen); the Escape menu pauses it with the world.
## Preview/regression: tools/preview_boss_intro.tscn, tools/test_boss_entrance.tscn.

signal finished

const SHADER: Shader = preload("res://assets/shaders/boss_intro.gdshader")
const SOUNDS: Dictionary = {
	"slam": preload("res://assets/audio/boss_intro/slam.wav"),
	"crackle": preload("res://assets/audio/boss_intro/crackle.wav"),
	"riser": preload("res://assets/audio/boss_intro/riser.wav"),
	"boom": preload("res://assets/audio/boss_intro/boom.wav"),
	"shimmer": preload("res://assets/audio/boss_intro/shimmer.wav"),
	"exhale": preload("res://assets/audio/boss_intro/exhale.wav"),
}
const BAR_PX: float = 40.0
const SLAM: float = 0.26 ## s until the bars have met their full height
const ZOOM: float = 1.5
const MAX_TIME: float = 16.0 ## nothing may hold the player longer than this
const NAME_CAP_Y: float = 0.545 ## the top of the capitals of the name, as a fraction of the screen height
const NAME_REVEAL: float = 0.9 ## s the name needs to condense out of the smoke
const CRACK_AT: float = 0.5
const EPITHET_AT: float = 1.0
const DISSOLVE_AT: float = 3.1 ## s after the touchdown: the name crumbles
const DISSOLVE_LEN: float = 0.8
const LEAVE_AT: float = 3.4 ## the bars open
const LEAVE_LEN: float = 0.5
const CARD_END: float = LEAVE_AT + LEAVE_LEN + 0.05
const INK: Color = Color("0b0614")
const MAGENTA: Color = Color("ff4fd8")
const TEAL: Color = Color("4ee0d0")
const VIOLET: Color = Color("8a4dff")
const HOT: Color = Color("ffe9f6")

var _boss: Node2D
var _player: Player
var _title: String = ""
var _epithet: String = ""
var _skip: float = 0.0
var _layer: CanvasLayer
var _rect: ColorRect
var _glow: Control
var _ui: Control
var _material: ShaderMaterial = ShaderMaterial.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _t: float = 0.0 ## seconds since the bars started to close
var _land: float = -1.0 ## seconds since the touchdown, -1 before
var _clock: float = 0.0
var _done: bool = false
var _restored: bool = false
var _hud: CanvasLayer
var _hud_was_visible: bool = true
var _blocking_was: bool = false
var _zoom0: Vector2 = Vector2.ONE
var _ret_cam: Camera2D
var _ret_shift: Vector2 = Vector2.ZERO
var _ret_zoom: Vector2 = Vector2.ONE
var _slammed: bool = false
var _flash_next: float = 0.1
var _flash_left: float = 0.0
var _flash_len: float = 0.08
var _flash_amp: float = 0.0
var _flash_seed: float = 0.0
var _flash_big: bool = false
var _bars: float = 0.0
var _dusk: float = 0.0
var _leave: float = 0.0
var _band_next: float = 1.0
var _band_left: float = 0.0
var _band_y: float = 0.0
var _band_h: float = 0.0
var _band_dx: float = 0.0
var _name_node: VoidTitle ## the name and the epithet in the shadow face (docs/void_face.md)
var _epithet_node: VoidTitle
var _crack_y: float = 0.0
var _spark_next: float = 0.0
var _played: Dictionary = {}
var _riser: AudioStreamPlayer
var _sparks: Array[Dictionary] = [] ## {pos, vel, life, max, hot}
var _fill_rects: Array[Rect2] = []
var _fill_cols: PackedColorArray = PackedColorArray()
var _glow_rects: Array[Rect2] = []
var _glow_cols: PackedColorArray = PackedColorArray()


## Starts the screen for `player` (the local one) and `boss` (a Node2D with `eye_position()`, `landing_spot()` and the signal `touched_down`).
## `skip` = seconds of the flight that have already passed (a peer that joined late).
static func play(boss: Node2D, player: Player, title: String, epithet: String, skip: float = 0.0) -> BossIntro:
	var intro: BossIntro = BossIntro.new()
	intro._boss = boss
	intro._player = player
	intro._title = title
	intro._epithet = epithet
	intro._skip = skip
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "BossIntroLayer"
	layer.layer = 55
	intro._layer = layer
	layer.add_child(intro)
	boss.get_tree().root.add_child.call_deferred(layer) ## the boss may be in the middle of being spawned
	return intro


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 5309
	_t = _skip
	_clock = _skip
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_name_node = VoidTitle.new()
	_name_node.setup(_title, "big", 1.0)
	_name_node.set_ink(1.0) ## the black gooey face
	_name_node.visible = false
	add_child(_name_node)
	_epithet_node = VoidTitle.new()
	_epithet_node.setup(_epithet, "small", 2.0)
	_epithet_node.set_ink(1.0)
	_epithet_node.visible = false
	add_child(_epithet_node)
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)
	_riser = AudioStreamPlayer.new()
	_riser.stream = SOUNDS["riser"] as AudioStream
	_riser.volume_db = -6.0
	add_child(_riser)
	_boss.connect(&"touched_down", _on_touched_down)
	_boss.tree_exiting.connect(_finish)
	_hud = _player.get("_hud") as CanvasLayer
	if _hud != null:
		_hud_was_visible = _hud.visible
		_hud.visible = false
	_blocking_was = InputManager.ui_blocking
	InputManager.ui_blocking = true
	_player.story_lock = true
	_zoom0 = _player.view_camera().zoom
	_fit()
	_riser.play(maxf(0.0, _skip))


func _exit_tree() -> void:
	_restore()


## The layer is not a Control, so nothing sizes the quads: they follow the viewport (640 x 360 art pixels, more when the window is wider).
func _fit() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if size != view:
		size = view
		_rect.size = view
		_glow.size = view
		_ui.size = view
		_layout_titles()


func _on_touched_down() -> void:
	if _land >= 0.0:
		return
	_land = 0.0
	_flash_left = 0.0
	_start_flash(1.0, 0.16, true)
	_player.add_shake(1.6)
	_play("boom", -2.0)
	_riser.stop()


# --- the clock -----------------------------------------------------------------------------------------------------


func _process(delta: float) -> void:
	if _done:
		return
	_fit()
	_t += delta
	_clock += delta
	if _land >= 0.0:
		_land += delta
	if not is_instance_valid(_boss) or not is_instance_valid(_player) or _player.health.current <= 0.0 or _t > MAX_TIME:
		_finish()
		return
	if _land >= CARD_END:
		_finish()
		return
	_step_bars()
	_step_flashes(delta)
	_step_camera(delta)
	_step_sounds()
	_step_text(delta)
	_push_shader()
	_ui.queue_redraw()
	_glow.queue_redraw()


func _step_bars() -> void:
	var u: float = clampf(_t / SLAM, 0.0, 1.0)
	var closing: float = 1.12 * (1.0 - pow(1.0 - u, 3.0))
	if _t > SLAM:
		closing = 1.0 + 0.12 * (1.0 - clampf((_t - SLAM) / 0.18, 0.0, 1.0))
	_leave = 0.0 if _land < 0.0 else clampf((_land - LEAVE_AT) / LEAVE_LEN, 0.0, 1.0)
	var eased: float = _leave * _leave * (3.0 - 2.0 * _leave)
	_bars = closing * (1.0 - eased)
	_dusk = clampf(_t / 0.7, 0.0, 1.0) * (1.0 - eased)
	if not _slammed and _t >= SLAM:
		_slammed = true
		_player.add_shake(1.2)
		if _skip < SLAM:
			_start_flash(1.0, 0.1, true)


func _start_flash(amp: float, length: float, big: bool) -> void:
	_flash_left = length
	_flash_len = length
	_flash_amp = amp
	_flash_big = big
	_flash_seed = _rng.randf() * 100.0
	if big:
		_play("crackle", -5.0)
		_player.add_shake(0.5)


## Shadow lightning: short bursts of the negative picture, never more than about three a second, quicker as the boss comes in.
func _step_flashes(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
	if _t >= _flash_next and _flash_left <= 0.0 and (_land < 0.0 or _land < DISSOLVE_AT - 0.3):
		var big: bool = _rng.randf() < 0.4
		_start_flash(_rng.randf_range(0.7, 1.0) if big else _rng.randf_range(0.4, 0.65), _rng.randf_range(0.05, 0.11), big)
		var progress: float = clampf(_t / 3.0, 0.0, 1.0) if _land < 0.0 else 1.0
		var gap: float = lerpf(0.55, 0.3, progress) if _land < 0.0 else _rng.randf_range(1.0, 1.7)
		_flash_next = _t + _flash_len + gap + _rng.randf() * 0.15


func _step_camera(delta: float) -> void:
	var cam: Camera2D = _player.view_camera()
	var zoom_goal: float = lerpf(1.0, ZOOM, smoothstep(0.0, 1.6, _t))
	if _land >= 0.0:
		zoom_goal += 0.06 * smoothstep(0.0, 3.0, _land)
	if _leave > 0.0:
		zoom_goal = lerpf(zoom_goal, 1.0, _leave)
	cam.zoom = Vector2.ONE * zoom_goal
	var spot: Vector2 = _boss.call("landing_spot") as Vector2
	var eye: Vector2 = _boss.call("eye_position") as Vector2
	## Anticipation first (a little towards the pillar), then a chase camera that rides with the boss and settles on the pillar as it arrives.
	var chase: float = smoothstep(0.3, 0.7, _t) * clampf((eye.distance_to(spot) - 70.0) / 200.0, 0.0, 1.0) * 0.85
	var look: Vector2 = spot.lerp(eye, chase)
	var base: Vector2 = _player.global_position + cam.position
	var goal: Vector2 = look + Vector2(0.0, size.y * 0.05 / zoom_goal) - base
	if _leave > 0.0:
		goal = goal.lerp(Vector2.ZERO, _leave)
	_player.view_shift = _player.view_shift.lerp(goal, 1.0 - exp(-3.4 * delta))
	## The boss must be seen coming in: after the first beat the camera never lets it leave the frame (a margin of 25 % of the half view).
	if _leave <= 0.0 and _land < 0.0:
		var ramp: float = smoothstep(0.15, 0.5, _t)
		var half: Vector2 = size * 0.5 / zoom_goal
		var room: Vector2 = half * 0.7 + Vector2.ONE * 700.0 * (1.0 - ramp)
		var centre: Vector2 = base + _player.view_shift
		var off: Vector2 = eye - centre
		var fix: Vector2 = Vector2(off.x - clampf(off.x, -room.x, room.x), off.y - clampf(off.y, -room.y, room.y))
		_player.view_shift += fix


func _step_sounds() -> void:
	if _land < 0.0:
		if not _played.has("slam") and _t >= 0.05:
			_played["slam"] = true
			if _skip < 0.1:
				_play("slam", 0.0)
		return
	if not _played.has("shimmer") and _land >= 0.95:
		_played["shimmer"] = true
		_play("shimmer", -6.0)
	if not _played.has("exhale") and _land >= DISSOLVE_AT:
		_played["exhale"] = true
		_play("exhale", -4.0)


func _play(cue: String, volume_db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = SOUNDS[cue] as AudioStream
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _push_shader() -> void:
	var flash: float = 0.0
	if _flash_left > 0.0:
		flash = _flash_amp * (1.0 if _flash_left > _flash_len * 0.4 else 0.35)
	var shock: float = 0.0 if _land < 0.0 else maxf(0.0, 1.0 - _land * 4.5)
	var ring: float = 0.0 if _land < 0.0 else clampf(_land / 0.9, 0.0, 1.0)
	var screen: Vector2 = _boss_screen()
	var heat: float = clampf(maxf(flash, shock) + (1.0 - clampf(_t - SLAM, 0.0, 0.5) * 2.0) * 0.6, 0.0, 1.0)
	_material.set_shader_parameter("view_size", size)
	_material.set_shader_parameter("time", _clock)
	_material.set_shader_parameter("bars", _bars)
	_material.set_shader_parameter("bar_px", BAR_PX)
	_material.set_shader_parameter("dusk", _dusk)
	_material.set_shader_parameter("flash", flash)
	_material.set_shader_parameter("flash_seed", _flash_seed)
	_material.set_shader_parameter("glitch", maxf(flash * 0.9, 0.9 if _band_left > 0.0 else 0.0))
	_material.set_shader_parameter("focus", Vector2(screen.x / size.x, screen.y / size.y))
	_material.set_shader_parameter("focus_amt", smoothstep(0.0, 1.2, _t) * 0.9 * (1.0 - _leave))
	_material.set_shader_parameter("shock", shock)
	_material.set_shader_parameter("ring", ring)
	_material.set_shader_parameter("ring_on", 1.0 if _land >= 0.0 and ring < 1.0 else 0.0)
	_material.set_shader_parameter("edge_heat", heat)


## Where the boss is on the screen (canvas pixels).
func _boss_screen() -> Vector2:
	var world: Vector2 = _boss.call("eye_position") as Vector2
	return get_viewport().get_canvas_transform() * world


# --- the card --------------------------------------------------------------------------------------------------------


func _step_text(delta: float) -> void:
	_fill_rects.clear()
	_fill_cols.clear()
	_glow_rects.clear()
	_glow_cols.clear()
	_step_sparks(delta)
	if _land < 0.0:
		return
	if _band_left > 0.0:
		_band_left -= delta
	elif _land >= _band_next and _land < DISSOLVE_AT:
		_band_next = _land + _rng.randf_range(0.7, 1.5)
		_start_band(_rng.randf_range(6.0, 14.0))
	var dissolve: float = clampf((_land - DISSOLVE_AT) / DISSOLVE_LEN, 0.0, 1.0)
	_sync_titles(dissolve)
	_build_crack(dissolve, VoidGlow.beat(_clock, 0.0, 0.8))


## The name condenses out of the smoke left to right, the epithet follows; every glitch band of the card makes the letters stutter; at the end both
## crumble upwards. Sparks run along the baseline with the front of the condensing name.
func _sync_titles(dissolve: float) -> void:
	var impact: float = clampf(1.0 - _land / 0.4, 0.0, 1.0)
	var glitch: float = maxf(impact, 0.7 if _band_left > 0.0 else 0.0)
	var born: float = clampf((_land - 0.08) / NAME_REVEAL, 0.0, 1.0)
	var power: float = smoothstep(0.0, 1.0, _land / 0.9)
	var drip: float = 0.35 + 0.65 * smoothstep(0.4, 2.6, _land)
	_name_node.visible = true
	_name_node.set_look(born * 1.4, dissolve, glitch, power, drip)
	var epithet_born: float = clampf((_land - EPITHET_AT) / 0.9, 0.0, 1.0)
	_epithet_node.visible = _land >= EPITHET_AT - 0.05
	_epithet_node.set_look(epithet_born * 1.4, dissolve, glitch * 0.5, 0.6 * power, 0.3 * drip)
	if _land >= 0.1 and _land < 1.2 and _land >= _spark_next:
		_spark_next = _land + 0.09
		var left: float = _name_node.position.x + float(_name_node.lead)
		var at: Vector2 = Vector2(left + float(_name_node.ink_size.x) * born, _name_node.position.y + float(_name_node.baseline))
		_spawn_sparks(at, 4)
		_player.add_shake(0.25)


## Both words are centred, the crack of light runs between them.
func _layout_titles() -> void:
	if _name_node == null:
		return
	var caps: float = float(((VoidTitle.metrics()["faces"] as Dictionary)["big"] as Dictionary)["cap"])
	var top: float = roundf(size.y * NAME_CAP_Y)
	_name_node.place(Vector2(roundf(size.x * 0.5 - _name_node.ink_size.x * 0.5), top))
	_crack_y = top + caps + 26.0
	_epithet_node.place(Vector2(roundf(size.x * 0.5 - _epithet_node.ink_size.x * 0.5), _crack_y + 12.0))


func _start_band(amount: float) -> void:
	_band_left = 0.08
	_band_h = _rng.randf_range(10.0, 24.0)
	_band_y = size.y * 0.62 + _rng.randf_range(-6.0, 70.0)
	_band_dx = amount * (1.0 if _rng.randf() < 0.5 else -1.0)


func _slip(y: float) -> float:
	return _band_dx if _band_left > 0.0 and y >= _band_y and y <= _band_y + _band_h else 0.0


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


## A crack of light tears open under the name, from the middle outwards, with forks near its ends; it beats with the shadow creatures' pulse.
func _build_crack(dissolve: float, beat: float) -> void:
	var grow: float = _ease_out((_land - CRACK_AT) / 0.7)
	if grow <= 0.0:
		return
	var half: float = (float(_name_node.ink_size.x) * 0.5 + 34.0) * grow * (1.0 - dissolve)
	if half < 2.0:
		return
	var cx: float = roundf(size.x * 0.5)
	var y: float = _crack_y ## under the tendrils of the name
	for dx: int in range(-int(half), int(half) + 1):
		var x: float = float(dx)
		var edge: float = pow(absf(x) / half, 3.0)
		var a: float = 1.0 - edge
		var jag: float = roundf((_vnoise(x * 0.11 + 3.0) - 0.5) * 5.0)
		var color: Color = HOT.lerp(VIOLET, clampf(absf(x) / half * 1.2, 0.0, 1.0))
		var pos: Vector2 = Vector2(cx + x + _slip(y), y + jag)
		_fill_rects.append(Rect2(pos, Vector2(1.0, 1.0)))
		_fill_cols.append(Color(color, a))
		_glow_rects.append(Rect2(pos - Vector2(0.0, 1.0), Vector2(1.0, 3.0)))
		_glow_cols.append(Color(VIOLET, (0.16 + 0.14 * beat) * a))
	for side: float in [-1.0, 1.0]: ## forks
		for fork: int in 2:
			var fx: float = side * half * (0.5 + 0.28 * float(fork))
			var dir: float = 1.0 if fork == 0 else -1.0
			var fy: float = y + roundf((_vnoise(fx * 0.11 + 3.0) - 0.5) * 5.0)
			for step: int in 6:
				var q: Vector2 = Vector2(cx + fx + side * float(step) * 1.0, fy + dir * float(step))
				var qa: float = (1.0 - float(step) / 6.0) * (1.0 - pow(absf(fx) / half, 3.0))
				_fill_rects.append(Rect2(q, Vector2(1.0, 1.0)))
				_fill_cols.append(Color(VIOLET.lightened(0.3), qa))
				_glow_rects.append(Rect2(q - Vector2(1.0, 1.0), Vector2(3.0, 3.0)))
				_glow_cols.append(Color(VIOLET, 0.12 * qa))


func _spawn_sparks(at: Vector2, amount: int) -> void:
	for n: int in amount:
		if _sparks.size() >= 90:
			return
		var angle: float = _rng.randf_range(-PI, 0.0)
		var speed: float = _rng.randf_range(40.0, 150.0)
		_sparks.append({"pos": at, "vel": Vector2(cos(angle), sin(angle)) * speed, "life": 0.0, "max": _rng.randf_range(0.3, 0.7), "hot": _rng.randf() < 0.4})


func _step_sparks(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for spark: Dictionary in _sparks:
		spark["life"] = float(spark["life"]) + delta
		if float(spark["life"]) >= float(spark["max"]):
			continue
		var vel: Vector2 = spark["vel"] as Vector2
		vel.y += 160.0 * delta
		spark["vel"] = vel
		spark["pos"] = (spark["pos"] as Vector2) + vel * delta
		keep.append(spark)
		var fade: float = 1.0 - float(spark["life"]) / float(spark["max"])
		var pos: Vector2 = (spark["pos"] as Vector2).round()
		_fill_rects.append(Rect2(pos, Vector2(1.0, 1.0)))
		_fill_cols.append(Color(HOT if bool(spark["hot"]) else MAGENTA, fade))
		_glow_rects.append(Rect2(pos - Vector2(1.0, 1.0), Vector2(3.0, 3.0)))
		_glow_cols.append(Color(VIOLET, 0.25 * fade))
	_sparks = keep


func _hash(n: int) -> float:
	return float(hash(n * 7919 + 13) % 1000) / 1000.0


func _vnoise(x: float) -> float:
	var i: float = floorf(x)
	var f: float = x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash(int(i)), _hash(int(i) + 1), f)


func _draw_ui() -> void:
	for i: int in _fill_rects.size():
		_ui.draw_rect(_fill_rects[i], _fill_cols[i])


func _draw_glow() -> void:
	for i: int in _glow_rects.size():
		_glow.draw_rect(_glow_rects[i], _glow_cols[i])


# --- the end -------------------------------------------------------------------------------------------------------------


func _finish() -> void:
	if _done:
		return
	_done = true
	_restore()
	finished.emit()
	if not is_inside_tree():
		return
	if is_instance_valid(_player):
		_ret_cam = _player.view_camera()
		_ret_shift = _player.view_shift
		_ret_zoom = _ret_cam.zoom
	_rect.hide()
	_ui.hide()
	_glow.hide()
	_name_node.hide()
	_epithet_node.hide()
	var tween: Tween = create_tween()
	tween.tween_method(_return_camera, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_free_layer)


## The camera glides back to the player.
func _return_camera(k: float) -> void:
	if is_instance_valid(_player) and _ret_cam != null:
		_player.view_shift = _ret_shift * (1.0 - k)
		_ret_cam.zoom = _ret_zoom.lerp(_zoom0, k)


func _free_layer() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()


## Gives the player, the HUD and the input back (also when the node is removed early).
func _restore() -> void:
	if _restored:
		return
	_restored = true
	if is_instance_valid(_player):
		_player.story_lock = false
	InputManager.ui_blocking = _blocking_was
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = _hud_was_visible
