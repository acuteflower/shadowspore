class_name FreeCam
extends Node
## Dev tool: L lifts the camera off the heroine and lets it fly; L again lands her exactly where the camera looks
## (the ring on the screen marks her feet), or on the nearest free spot beside it. She stands still while it flies and
## the world keeps running. WASD fly, Shift is fast, the wheel and +/- zoom. The world streams round the camera.
## A child of the local player (created in `Player._ready`); the player is untyped here on purpose.

const SPEED: float = 230.0
const FAST: float = 3.2
const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 3.0
const FEET_BELOW_CAMERA: float = 22.0 ## the player's camera sits this far above her feet
const SEARCH_STEP: float = 8.0
const SEARCH_RADIUS: float = 64.0

var _player: Node2D
var _cam: Camera2D
var _player_cam: Camera2D
var _pos: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _active: bool = false
var _layer: CanvasLayer
var _hint: FreeCamHint
var _world: Node


func _ready() -> void:
	_player = get_parent() as Node2D


func active() -> bool:
	return _active


func _process(delta: float) -> void:
	if InputManager.freecam_pressed():
		if _active:
			_leave()
		elif _can_enter():
			_enter()
		return
	if not _active:
		return
	var health: HealthComponent = _player.get("health") as HealthComponent
	if health != null and health.current <= 0.0:
		_cancel() ## she fell while the camera flew: back to her
		return
	if InputManager.ui_blocking or InputManager.menu_open:
		return
	var dir: Vector2 = InputManager.map_pan_vector()
	var speed: float = SPEED * (FAST if InputManager.sprint_held() else 1.0) / _zoom
	_pos += dir * speed * delta
	var step: int = InputManager.map_zoom_step()
	if step != 0:
		_set_zoom(_zoom * (1.2 if step > 0 else 1.0 / 1.2))
	_cam.global_position = _pos.round()
	_cam.zoom = Vector2(_zoom, _zoom)
	_hint.feet = _pos + Vector2(0.0, FEET_BELOW_CAMERA)
	_hint.zoom = _zoom


func _unhandled_input(event: InputEvent) -> void:
	if not _active or InputManager.ui_blocking:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_set_zoom(_zoom * (1.2 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2))
		get_viewport().set_input_as_handled()


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)


func _can_enter() -> bool:
	if _player == null or not _player.is_multiplayer_authority():
		return false
	if InputManager.map_open or (InputManager.skills_open or InputManager.progress_open) or InputManager.build_open:
		return false
	var health: HealthComponent = _player.get("health") as HealthComponent
	if health == null or health.current <= 0.0:
		return false
	if _player.get("intro") != null or bool(_player.get("story_lock")) or bool(_player.get("stumbling")) or bool(_player.get("fainting")):
		return false
	var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
	if world != null: ## rooms, shafts and the mine lie far outside the map: the camera would only show the void
		var limit: float = float(RegionMap.WORLD_TILES) * 16.0
		if _player.global_position.x < 0.0 or _player.global_position.y < 0.0 or _player.global_position.x > limit or _player.global_position.y > limit:
			return false
	return true


func _enter() -> void:
	_player_cam = _player.call("view_camera") as Camera2D
	_world = get_tree().get_first_node_in_group("world")
	_pos = _player_cam.get_screen_center_position()
	_zoom = _player_cam.zoom.x
	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = false
	_cam.global_position = _pos
	_cam.zoom = Vector2(_zoom, _zoom)
	(_world if _world != null else _player.get_parent()).add_child(_cam)
	_cam.make_current()
	if _world is WorldLevel:
		(_world as WorldLevel).editor_camera = _cam ## the same hook the map editor uses: the world streams round the camera
	_layer = CanvasLayer.new()
	_layer.layer = 30
	_hint = FreeCamHint.new()
	_layer.add_child(_hint)
	add_child(_layer)
	_hint.feet = _pos + Vector2(0.0, FEET_BELOW_CAMERA)
	_hint.zoom = _zoom
	InputManager.freecam_open = true
	_active = true


func _leave() -> void:
	var spot: Vector2 = _free_spot(_pos + Vector2(0.0, FEET_BELOW_CAMERA))
	if spot == Vector2.INF:
		_hint.complain("KEIN PLATZ HIER")
		return
	if not _loaded_at(spot):
		_hint.complain("DIE WELT LÄDT NOCH")
		return
	_player.call("request_teleport", spot)
	_cancel()


## Back to the heroine where she stands.
func _cancel() -> void:
	_active = false
	InputManager.freecam_open = false
	if _world is WorldLevel and (_world as WorldLevel).editor_camera == _cam:
		(_world as WorldLevel).editor_camera = null
	if is_instance_valid(_player_cam):
		_player_cam.make_current()
		_player_cam.reset_smoothing()
	if is_instance_valid(_cam):
		_cam.queue_free()
	if is_instance_valid(_layer):
		_layer.queue_free()
	_cam = null
	_hint = null
	_layer = null


## The camera's spot if she fits there, else the nearest free one round it (rings of 8 px), else INF.
func _free_spot(feet: Vector2) -> Vector2:
	var body: CharacterBody2D = _player as CharacterBody2D
	if body == null:
		return feet
	var radius: float = 0.0
	while radius <= SEARCH_RADIUS:
		var count: int = 1 if radius == 0.0 else int(radius / SEARCH_STEP) * 6
		for i: int in count:
			var angle: float = TAU * float(i) / float(count)
			var spot: Vector2 = (feet + Vector2.from_angle(angle) * radius).round()
			if not body.test_move(Transform2D(0.0, spot), Vector2.ZERO) and _on_land(spot):
				return spot
		radius += SEARCH_STEP
	return Vector2.INF


func _on_land(spot: Vector2) -> bool:
	var world: WorldLevel = _world as WorldLevel
	if world == null:
		return true
	return world.call("_land_at", int(floorf(spot.x / 16.0)), int(floorf(spot.y / 16.0)))


## The chunk is there (its collision exists), so she does not drop into an unloaded gap.
func _loaded_at(spot: Vector2) -> bool:
	var world: WorldLevel = _world as WorldLevel
	if world == null:
		return true
	var chunks: Variant = world.get("_chunks")
	if chunks is Dictionary:
		var cell: Vector2i = Vector2i(int(floorf(spot.x / 16.0)), int(floorf(spot.y / 16.0))) / WorldLevel.CHUNK
		return (chunks as Dictionary).has(cell)
	return true
