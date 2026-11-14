class_name SalonSeat
extends BenchSeat
## The chair of the open-air salon (`docs/salon_konzept.md`, piece `salon` with `"salon": true`): the same host-confirmed sitting as a bench (`RestComponent`),
## opening `SalonWindow` on the sitting player's peer while hiding the HUD and framing Ellie + the glowing mirror on the left.
## On every peer the mirror wakes while somebody sits (`TownStructure.set_glow_boost`, rising sparks from the glass).

const SALON_WINDOW_SCRIPT: GDScript = preload("res://src/ui/salon_window.gd")

var _local_sitting: bool = false
var _occupied_shown: bool = false
var _window: BoardWindow
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


## SalonWindow shows its own controls at the bottom of the board.
func show_stand_prompt() -> bool:
	return false


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


func _process(_delta: float) -> void:
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


## Somebody (any player) sits on this chair right now (not walking up, not getting up).
func _seated_by_anyone() -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var rest: RestComponent = node.get_node_or_null("RestComponent") as RestComponent
		if rest != null and rest.seat == self and rest.state != RestComponent.State.FREE and rest.state != RestComponent.State.APPROACH and rest.state != RestComponent.State.UP:
			return true
	return false


## The local player sat down or got up: hide the HUD and open/close `SalonWindow`.
func _apply_local(player: Player, active: bool) -> void:
	if player == null or not is_instance_valid(player):
		if not active and _window != null and is_instance_valid(_window):
			_window.call("close_from_seat")
			_window = null
		return
	var hud: Node = player.get("_hud") as Node
	if hud == null:
		hud = player.get_node_or_null("Hud")
	if hud != null:
		hud.set("vista_hide", active)
	if active:
		if _window == null or not is_instance_valid(_window) or _window._closing:
			_window = SALON_WINDOW_SCRIPT.call("open", get_tree(), player, manager, self) as BoardWindow
	elif _window != null and is_instance_valid(_window):
		_window.call("close_from_seat")
		_window = null


## Celebratory prism burst from the mirror when a new look is applied.
func sparkle_burst() -> void:
	var burst: CPUParticles2D = CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 16
	burst.lifetime = 0.85
	burst.spread = 180.0
	burst.gravity = Vector2(0.0, -14.0)
	burst.initial_velocity_min = 14.0
	burst.initial_velocity_max = 36.0
	burst.color = Color(0.84, 1.0, 0.96, 0.95)
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([Color(0.47, 0.96, 0.90, 1.0), Color(0.91, 0.86, 1.0, 0.9), Color(1.0, 1.0, 1.0, 0.0)])
	burst.color_ramp = ramp
	burst.material = Unlit.material()
	burst.z_index = 8
	burst.top_level = true
	burst.global_position = mirror_point()
	burst.emitting = true
	add_child(burst)
	burst.finished.connect(burst.queue_free)


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
	if _window != null and is_instance_valid(_window):
		_window.call("close_from_seat")
		_window = null
