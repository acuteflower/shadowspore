class_name SalonSeat
extends BenchSeat
## The chair of the open-air salon (`docs/salon_konzept.md`, piece `salon` with `"salon": true`): the same host-confirmed sitting as a bench (`RestComponent`),
## but on the sitting player's own peer the camera moves close to her (zoom, a little towards the mirror), the HUD steps aside and a line says what the place
## will be for. On every peer the mirror wakes while somebody sits (`TownStructure.set_glow_boost`, a few sparks rising from the glass).
## Stage 2 opens the look window from here (`_apply_local`).

const ZOOM: float = 2.2
const ZOOM_IN_SECONDS: float = 1.4
const ZOOM_OUT_SECONDS: float = 0.8
const HEAD: float = 24.0 ## how far above her seat the camera looks (her face, seated)
const TOWARDS_MIRROR: float = 10.0
const HINT: String = "HIER KANNST DU BALD DEIN AUSSEHEN ÄNDERN"

var _local_sitting: bool = false
var _occupied_shown: bool = false
var _cam_tween: Tween
var _hint: CanvasLayer
var _hint_canvas: Control
var _hint_alpha: float = 0.0
var _hint_goal: float = 0.0
var _sparks: CPUParticles2D


func setup(owner_manager: TownManager, id: int, seat_index: int) -> void:
	super.setup(owner_manager, id, seat_index)
	label = "PLATZ NEHMEN"
	radius = 12.0
	height = 26.0


func prompt() -> String:
	return "PLATZ NEHMEN" if super.prompt() != "" else ""


func approach_position() -> Vector2:
	return seat_position() + Vector2(0.0, 12.0)


## Health while seated: a salon chair is for looks, not for rest.
func regen_rate() -> float:
	return 0.0


## Which way the mirror stands from the chair: right, or left on a mirrored piece.
func _mirror_side() -> float:
	if manager == null or not manager.structures.has(structure_id):
		return 1.0
	return -1.0 if int((manager.structures[structure_id] as Dictionary).get("f", 0)) == 1 else 1.0


## The middle of the mirror's glass (global), from the piece's data `mirror` [x, y] relative to its feet.
func mirror_point() -> Vector2:
	if manager == null or not manager.structures.has(structure_id):
		return global_position
	var data: Dictionary = manager.structures[structure_id] as Dictionary
	var at: Array = TownRules.piece(String(data.p)).get("mirror", [20, -42]) as Array
	return Vector2(float(data.x) + float(at[0]) * _mirror_side(), float(data.y) + float(at[1]))


func _process(delta: float) -> void:
	var player: Player = _local_player()
	var sitting_now: bool = false
	if player != null:
		var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent
		sitting_now = rest != null and rest.seat == self and rest.state != RestComponent.State.FREE and rest.state != RestComponent.State.APPROACH and rest.state != RestComponent.State.UP
	if sitting_now != _local_sitting:
		_local_sitting = sitting_now
		_apply_local(player, sitting_now)
	var someone: bool = _seated_by_anyone()
	if someone != _occupied_shown:
		_occupied_shown = someone
		_wake(someone)
	if _hint_canvas != null:
		_hint_alpha = move_toward(_hint_alpha, _hint_goal, delta * 1.6)
		_hint_canvas.queue_redraw()
		if _hint_alpha <= 0.0 and _hint_goal <= 0.0:
			_hint.queue_free()
			_hint = null
			_hint_canvas = null


## Somebody (any player) sits on this chair right now (not walking up, not getting up).
func _seated_by_anyone() -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var rest: RestComponent = node.get_node_or_null("RestComponent") as RestComponent
		if rest != null and rest.seat == self and rest.state != RestComponent.State.FREE and rest.state != RestComponent.State.APPROACH and rest.state != RestComponent.State.UP:
			return true
	return false


## The local player sat down or got up: the camera, the HUD and the hint (stage 2: the look window opens and closes here).
func _apply_local(player: Player, active: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var hud: Node = player.get("_hud") as Node
	if hud == null:
		hud = player.get_node_or_null("Hud")
	if hud != null:
		hud.set("vista_hide", active)
	var camera: Camera2D = player.view_camera()
	if camera != null:
		if _cam_tween != null:
			_cam_tween.kill()
		_cam_tween = player.create_tween().set_parallel(true)
		_cam_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if active:
			_cam_tween.tween_property(camera, "zoom", Vector2(ZOOM, ZOOM), ZOOM_IN_SECONDS)
			_cam_tween.tween_property(player, "view_shift", Vector2(TOWARDS_MIRROR * _mirror_side(), -HEAD).round(), ZOOM_IN_SECONDS)
		else:
			_cam_tween.tween_property(camera, "zoom", Vector2.ONE, ZOOM_OUT_SECONDS)
			_cam_tween.tween_property(player, "view_shift", Vector2.ZERO, ZOOM_OUT_SECONDS)
	_show_hint(active)


func _show_hint(on: bool) -> void:
	_hint_goal = 1.0 if on else 0.0
	if on and _hint == null:
		_hint = CanvasLayer.new()
		_hint.layer = 24
		_hint_canvas = Control.new()
		_hint_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_hint_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint_canvas.draw.connect(_draw_hint)
		_hint.add_child(_hint_canvas)
		add_child(_hint)


func _draw_hint() -> void:
	var fade: float = clampf(_hint_alpha * 1.4 - 0.4, 0.0, 1.0) ## it comes once the camera has nearly arrived
	if fade <= 0.0:
		return
	var size: Vector2 = _hint_canvas.size
	var width: int = PixelText.width(HINT)
	var at: Vector2i = Vector2i(int(size.x / 2.0) - width / 2, int(size.y) - 34)
	_hint_canvas.draw_rect(Rect2(Vector2(at) - Vector2(8, 5), Vector2(width + 16, 16)), Color(0.04, 0.02, 0.08, 0.55 * fade))
	PixelText.draw(_hint_canvas, HINT, at, Color(Color("e9dcff"), fade), Color(Color("0a0612"), fade))
	var sub: String = "E ODER BEWEGEN: AUFSTEHEN"
	PixelText.draw(_hint_canvas, sub, Vector2i(int(size.x / 2.0) - PixelText.width(sub) / 2, at.y + 14), Color(Color("8f7fb0"), fade), Color(Color("0a0612"), fade))


## The mirror wakes while somebody sits (every peer): the glow brightens and sparks rise from the glass.
func _wake(on: bool) -> void:
	var view: TownStructure = manager.view_of(structure_id) if manager != null else null
	if view != null and is_instance_valid(view):
		view.set_glow_boost(0.8 if on else 0.0)
	if on:
		if _sparks == null:
			_sparks = CPUParticles2D.new()
			_sparks.amount = 10
			_sparks.lifetime = 1.6
			_sparks.direction = Vector2.UP
			_sparks.spread = 30.0
			_sparks.gravity = Vector2(0.0, -6.0)
			_sparks.initial_velocity_min = 4.0
			_sparks.initial_velocity_max = 10.0
			_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			_sparks.emission_rect_extents = Vector2(6.0, 12.0)
			_sparks.color = Color(0.82, 1.0, 0.97, 0.9)
			var ramp: Gradient = Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
			ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
			_sparks.color_ramp = ramp
			_sparks.material = Unlit.material()
			_sparks.z_index = 6
			_sparks.top_level = true
			add_child(_sparks)
		_sparks.global_position = mirror_point()
		_sparks.emitting = true
		if ResourceLoader.exists("res://assets/audio/town/warmth.wav"):
			var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			sound.stream = load("res://assets/audio/town/warmth.wav") as AudioStream
			sound.volume_db = -14.0
			sound.pitch_scale = 1.25
			sound.max_distance = 240.0
			add_child(sound)
			sound.finished.connect(sound.queue_free)
			sound.play()
	elif _sparks != null:
		_sparks.emitting = false


func _exit_tree() -> void:
	if _local_sitting:
		_local_sitting = false
		_apply_local(_local_player(), false)
