class_name BossPhaseScreen
extends Control
## The card between two phases of a boss fight, local to every player who is near the arena (started by the fight: `BossPhaseScreen.play`). About 4.5 s, a brother of
## `BossIntro` (same shader, same shadow face): two bars of shadow smoke slam shut from the top and the bottom, the world drains into cold violet, shadow lightning flickers
## through the picture, the camera closes in on the boss; when he screams (`scream_at`) a flash and a ring of pressure bend the picture; then the name of the phase condenses
## out of the smoke in the shadow face (`VoidTitle`), crumbles, and the bars open (`leave_at`).
## The player is held still (`story_lock`) and the HUD hidden meanwhile; both are given back in `_restore`, also when the node is removed early. Game time, own CanvasLayer (55).
## Times (`cfg`, data `fight.transition`): scream_at, title_at, leave_at, end. Preview: tools/preview_boss_fight.tscn (`--acts=transition`).

signal finished

const SHADER: Shader = preload("res://assets/shaders/boss_intro.gdshader")
const BAR_PX: float = 40.0
const SLAM: float = 0.26
const ZOOM: float = 1.35
const MAX_TIME: float = 9.0
const LEAVE_LEN: float = 0.5
const REVEAL: float = 0.8
const DISSOLVE_LEN: float = 0.6

var _boss: Node2D
var _player: Player
var _text: String = ""
var _cfg: Dictionary = {}
var _layer: CanvasLayer
var _rect: ColorRect
var _title: VoidTitle
var _material: ShaderMaterial = ShaderMaterial.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _t: float = 0.0
var _done: bool = false
var _restored: bool = false
var _hud: CanvasLayer
var _hud_was_visible: bool = true
var _blocking_was: bool = false
var _zoom0: Vector2 = Vector2.ONE
var _ret_cam: Camera2D
var _ret_shift: Vector2 = Vector2.ZERO
var _ret_zoom: Vector2 = Vector2.ONE
var _flash_next: float = 0.35
var _flash_left: float = 0.0
var _flash_len: float = 0.08
var _flash_amp: float = 0.0
var _flash_seed: float = 0.0
var _screamed: bool = false
var _slammed: bool = false
var _played: Dictionary = {}
var _bars: float = 0.0
var _dusk: float = 0.0
var _leave: float = 0.0


## Starts the card for `player` (the local one) and `boss` (a Node2D with `eye_position()`).
static func play(boss: Node2D, player: Player, text: String, cfg: Dictionary) -> BossPhaseScreen:
	var screen: BossPhaseScreen = BossPhaseScreen.new()
	screen._boss = boss
	screen._player = player
	screen._text = text
	screen._cfg = cfg
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "BossPhaseLayer"
	layer.layer = 55
	screen._layer = layer
	layer.add_child(screen)
	boss.get_tree().root.add_child.call_deferred(layer)
	return screen


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7711
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_title = VoidTitle.new()
	_title.setup(_text, "big", 3.0)
	_title.set_ink(1.0)
	_title.visible = false
	add_child(_title)
	_hud = _player.get("_hud") as CanvasLayer
	if _hud != null:
		_hud_was_visible = _hud.visible
		_hud.visible = false
	_blocking_was = InputManager.ui_blocking
	InputManager.ui_blocking = true
	_player.story_lock = true
	_zoom0 = _player.view_camera().zoom
	_fit()
	_play("slam", -2.0)


func _exit_tree() -> void:
	_restore()


func _fit() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if size != view:
		size = view
		_rect.size = view
		var cap: float = float(((VoidTitle.metrics()["faces"] as Dictionary)["big"] as Dictionary)["cap"])
		_title.place(Vector2(roundf(size.x * 0.5 - _title.ink_size.x * 0.5), roundf(size.y * 0.5 - cap * 0.5)))


func _process(delta: float) -> void:
	if _done:
		return
	_fit()
	_t += delta
	if not is_instance_valid(_boss) or not is_instance_valid(_player) or _player.health.current <= 0.0 or _t > MAX_TIME or _t >= float(_cfg["end"]):
		_finish()
		return
	_step_bars()
	_step_flashes(delta)
	_step_camera(delta)
	_step_title()
	_push_shader()


func _step_bars() -> void:
	var u: float = clampf(_t / SLAM, 0.0, 1.0)
	var closing: float = 1.12 * (1.0 - pow(1.0 - u, 3.0))
	if _t > SLAM:
		closing = 1.0 + 0.12 * (1.0 - clampf((_t - SLAM) / 0.18, 0.0, 1.0))
	_leave = clampf((_t - float(_cfg["leave_at"])) / LEAVE_LEN, 0.0, 1.0)
	var eased: float = _leave * _leave * (3.0 - 2.0 * _leave)
	_bars = closing * (1.0 - eased)
	_dusk = clampf(_t / 0.6, 0.0, 1.0) * (1.0 - eased)
	if not _slammed and _t >= SLAM:
		_slammed = true
		_player.add_shake(1.2)


func _start_flash(amp: float, length: float, big: bool) -> void:
	_flash_left = length
	_flash_len = length
	_flash_amp = amp
	_flash_seed = _rng.randf() * 100.0
	if big:
		_play("crackle", -5.0)
		_player.add_shake(0.5)


func _step_flashes(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
	var scream: float = float(_cfg["scream_at"])
	if not _screamed and _t >= scream:
		_screamed = true
		_flash_left = 0.0
		_start_flash(1.0, 0.16, true)
		_player.add_shake(2.0)
		_play("boom", 0.0)
	if _t >= _flash_next and _flash_left <= 0.0 and _t < float(_cfg["leave_at"]) - 0.2:
		var big: bool = _rng.randf() < 0.45
		_start_flash(_rng.randf_range(0.7, 1.0) if big else _rng.randf_range(0.35, 0.6), _rng.randf_range(0.05, 0.1), big)
		_flash_next = _t + _flash_len + _rng.randf_range(0.25, 0.55)


func _step_camera(delta: float) -> void:
	var cam: Camera2D = _player.view_camera()
	var goal_zoom: float = lerpf(1.0, ZOOM, smoothstep(0.0, 1.2, _t))
	goal_zoom = lerpf(goal_zoom, 1.0, _leave)
	cam.zoom = Vector2.ONE * goal_zoom
	var eye: Vector2 = _boss.call("eye_position") as Vector2
	var base: Vector2 = _player.global_position + cam.position
	var goal: Vector2 = eye + Vector2(0.0, size.y * 0.05 / goal_zoom) - base
	goal = goal.lerp(Vector2.ZERO, _leave)
	_player.view_shift = _player.view_shift.lerp(goal, 1.0 - exp(-3.2 * delta))
	if _t < float(_cfg["scream_at"]) and _player.global_position.distance_to(eye) < 40.0:
		pass ## (keeps the tweak point for a boss that is on top of the player)


func _step_title() -> void:
	var title_at: float = float(_cfg["title_at"])
	if _t < title_at:
		return
	var age: float = _t - title_at
	var leave_at: float = float(_cfg["leave_at"])
	var dissolve: float = clampf((_t - (leave_at - 0.25)) / DISSOLVE_LEN, 0.0, 1.0)
	var impact: float = clampf(1.0 - age / 0.35, 0.0, 1.0)
	var glitch: float = maxf(impact, 0.55 if fmod(_t * 7.3, 1.0) < 0.1 else 0.0)
	_title.visible = true
	_title.set_look(clampf(age / REVEAL, 0.0, 1.0) * 1.4, dissolve, glitch, smoothstep(0.0, 0.9, age), 0.35 + 0.65 * smoothstep(0.2, 2.0, age))
	if not _played.has("shimmer") and age >= 0.1:
		_played["shimmer"] = true
		_play("shimmer", -6.0)


func _push_shader() -> void:
	var flash: float = 0.0
	if _flash_left > 0.0:
		flash = _flash_amp * (1.0 if _flash_left > _flash_len * 0.4 else 0.35)
	var since: float = _t - float(_cfg["scream_at"])
	var shock: float = maxf(0.0, 1.0 - since * 4.5) if since >= 0.0 else 0.0
	var ring: float = clampf(since / 0.9, 0.0, 1.0) if since >= 0.0 else 0.0
	var eye: Vector2 = _boss.call("eye_position") as Vector2
	var screen: Vector2 = get_viewport().get_canvas_transform() * eye
	var heat: float = clampf(maxf(flash, shock) + (1.0 - clampf(_t - SLAM, 0.0, 0.5) * 2.0) * 0.6, 0.0, 1.0)
	_material.set_shader_parameter("view_size", size)
	_material.set_shader_parameter("time", _t)
	_material.set_shader_parameter("bars", _bars)
	_material.set_shader_parameter("bar_px", BAR_PX)
	_material.set_shader_parameter("dusk", _dusk)
	_material.set_shader_parameter("flash", flash)
	_material.set_shader_parameter("flash_seed", _flash_seed)
	_material.set_shader_parameter("glitch", maxf(flash * 0.9, 0.0))
	_material.set_shader_parameter("focus", Vector2(screen.x / size.x, screen.y / size.y))
	_material.set_shader_parameter("focus_amt", smoothstep(0.0, 1.0, _t) * 0.85 * (1.0 - _leave))
	_material.set_shader_parameter("shock", shock)
	_material.set_shader_parameter("ring", ring)
	_material.set_shader_parameter("ring_on", 1.0 if since >= 0.0 and ring < 1.0 else 0.0)
	_material.set_shader_parameter("edge_heat", heat)


func _play(cue: String, volume_db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = BossIntro.SOUNDS[cue] as AudioStream
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# --- the end ---------------------------------------------------------------------------------------------------------


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
	_title.hide()
	var tween: Tween = create_tween()
	tween.tween_method(_return_camera, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_free_layer)


func _return_camera(k: float) -> void:
	if is_instance_valid(_player) and _ret_cam != null:
		_player.view_shift = _ret_shift * (1.0 - k)
		_ret_cam.zoom = _ret_zoom.lerp(_zoom0, k)


func _free_layer() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()


func _restore() -> void:
	if _restored:
		return
	_restored = true
	if is_instance_valid(_player):
		_player.story_lock = false
	InputManager.ui_blocking = _blocking_was
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = _hud_was_visible
