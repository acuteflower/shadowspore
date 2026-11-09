class_name Interiors
extends Node2D
## The interiors of the world ("pocket spaces"). Walk through a door and you are in a world of your own that can be bigger than the building looks from outside:
## every interior of data/interiors.json is built (the same on every peer) at its own slot far outside the 1100 x 1100 tile world (`POCKET_X0`), and the door
## (`Doorway`, E) moves you there and back (the owner moves herself, the position synchronizer tells the others; `Player.request_teleport`). So multiplayer,
## physics and everything else stay as they are; what changes by where you are (decided by the position, `slot_at`):
##  - the world is streamed, discovered on the map and sensed around the door outside (`world_position`), not around the pocket;
##  - the camera stays on the room (limits, `apply_view`), the world's tint is replaced by the room's ambient colour (`ambient_color`, used by `DayNight`);
##  - the floor is wood (`surface_at`, a `Terrain.patches` entry); the fireflies stay away.
## The transition is a ragged iris of dark (`door_wipe.gdshader`) with the door swinging open and a creak.

const POCKET_X0: float = 60000.0
const POCKET_Y0: float = 60000.0
const SLOT: float = 1600.0
const SOUNDS: Dictionary = {
	"open": preload("res://assets/audio/hut/door_open.wav"),
	"close": preload("res://assets/audio/hut/door_close.wav"),
	"creak_a": preload("res://assets/audio/hut/creak_a.wav"),
	"creak_b": preload("res://assets/audio/hut/creak_b.wav"),
}
const AMBIENT: AudioStream = preload("res://assets/audio/hut/ambient.wav")
const WIPE: Shader = preload("res://assets/shaders/door_wipe.gdshader")

var _interiors: Dictionary = {} ## id -> Interior
var _order: Array[String] = []
var _entrances: Dictionary = {} ## interior id -> Hut (the building outside)
var _wipe_material: ShaderMaterial = ShaderMaterial.new()
var _wipe_layer: CanvasLayer
var _cover: float = 0.0
var _busy: bool = false
var _player: Player
var _view_key: String = "-"
var _clock: float = 0.0
var _ambient: AudioStreamPlayer
var _step_clock: float = 0.0
var _creaks: int = 0
var _here_id: String = "" ## the room she stood in last frame


func _ready() -> void:
	add_to_group("interiors")
	y_sort_enabled = true
	name = "Interiors"
	var table: Dictionary = DataRegistry.table("interiors")
	for id: String in table:
		var data: Dictionary = table[id] as Dictionary
		var interior: Interior = Interior.new()
		var next_to: Interior = null
		if data.has("adjacent"): ## a room right next to another (the hallway under Ellie's room): no slot of its own
			var adjacent: Dictionary = data.adjacent as Dictionary
			next_to = _interiors.get(String(adjacent.to)) as Interior
			var offset: Array = adjacent.offset as Array
			interior.position = next_to.position + Vector2(float(offset[0]), float(offset[1]))
		else:
			interior.position = Vector2(POCKET_X0 + _order.size() * SLOT, POCKET_Y0)
			_order.append(id)
		add_child(interior)
		interior.setup(id, data)
		_interiors[id] = interior
		if next_to != null:
			next_to.join(interior)
	for id: String in table: ## rooms that share the view with others they are not next to (the corridor leading up from the hallway)
		for other_id: Variant in (table[id] as Dictionary).get("joins", []) as Array:
			var other: Interior = _interiors.get(String(other_id)) as Interior
			if other != null:
				(_interiors[id] as Interior).join(other)
	var seen: Array[Interior] = [] ## rooms that hang together (neighbours of neighbours) share one view and one dark round them
	for start: Interior in _interiors.values():
		if seen.has(start) or start.neighbors.is_empty():
			continue
		var group: Array[Interior] = [start]
		var rect: Rect2 = Rect2(start.global_position, start.size)
		var at: int = 0
		while at < group.size():
			for other: Interior in group[at].neighbors:
				if not group.has(other):
					group.append(other)
					rect = rect.merge(Rect2(other.global_position, other.size))
			at += 1
		for member: Interior in group:
			seen.append(member)
			member.set_group_rect(rect)
	Terrain.patches.append(self)
	_wipe_layer = CanvasLayer.new()
	_wipe_layer.layer = 80
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe_material.shader = WIPE
	rect.material = _wipe_material
	_wipe_layer.add_child(rect)
	_wipe_layer.visible = false
	add_child(_wipe_layer)
	_wipe_layer.set_meta("rect", rect)
	_ambient = AudioStreamPlayer.new() ## the room's sounds: wind through the cracks, the fire, a few birds
	_ambient.stream = AMBIENT
	_ambient.volume_db = -80.0
	_ambient.finished.connect(func() -> void: _ambient.play())
	add_child(_ambient)


func _exit_tree() -> void:
	Terrain.patches.erase(self)


# ---------- where is what ----------

## The slot (index of the interior) a position lies in, -1 for the open world.
static func slot_at(pos: Vector2) -> int:
	if pos.x < POCKET_X0 - 1400.0 or pos.y < POCKET_Y0 - 400.0 or pos.y > POCKET_Y0 + SLOT: ## the mine (MineManager) lies in a row below the rooms
		return -1
	return clampi(int((pos.x - POCKET_X0 + 1400.0) / SLOT), 0, 64)


## Where something stands as far as the open world is concerned: its own position, or the door of the building it is in.
static func outer(tree: SceneTree, pos: Vector2) -> Vector2:
	if MineManager.in_mine(pos):
		var mines: MineManager = tree.get_first_node_in_group("mines") as MineManager
		return mines.world_position(pos) if mines != null else pos
	if slot_at(pos) < 0:
		return pos
	var manager: Interiors = tree.get_first_node_in_group("interiors") as Interiors
	return manager.world_position(pos) if manager != null else pos


func interior_at(pos: Vector2) -> Interior:
	var found: Interior = null
	for room: Interior in _interiors.values():
		if Rect2(room.global_position, room.size).has_point(pos) and (found == null or room.spec.has("adjacent")): ## a room next door wins where it overlaps the wall
			found = room
	if found != null:
		return found
	var slot: int = slot_at(pos)
	return _interiors[_order[slot]] as Interior if slot >= 0 and slot < _order.size() else null


func interior(id: String) -> Interior:
	return _interiors.get(id) as Interior


func world_position(pos: Vector2) -> Vector2:
	var inside: Interior = interior_at(pos)
	if inside == null:
		return pos
	var hut: Hut = _entrances.get(String(inside.spec.adjacent.to) if inside.spec.has("adjacent") else inside.id) as Hut
	return hut.exit_position if hut != null else Vector2.ZERO


func register_entrance(id: String, hut: Hut) -> void:
	_entrances[id] = hut


## A named place for the quest marker: "<interior id>_exit" is the door inside.
func anchor_position(anchor: String) -> Vector2:
	if anchor.ends_with("_exit"):
		var inside: Interior = interior(anchor.trim_suffix("_exit"))
		if inside != null:
			return inside.door.global_position
	return Vector2.INF


## `Terrain.patches`: the floors inside are wood.
func surface_at(pos: Vector2) -> String:
	return "wood" if slot_at(pos) >= 0 else ""


## The tint while the local player is in a room (alpha 0 = she is outside).
func ambient_color() -> Color:
	if _player == null or not is_instance_valid(_player):
		return Color(0, 0, 0, 0)
	var inside: Interior = interior_at(_player.global_position)
	return inside.ambient() if inside != null else Color(0, 0, 0, 0)


func local_player() -> Player:
	return _player if _player != null and is_instance_valid(_player) else null


func local_position() -> Vector2:
	return _player.global_position if _player != null and is_instance_valid(_player) else Vector2.ZERO


func local_inside() -> bool:
	return _player != null and is_instance_valid(_player) and slot_at(_player.global_position) >= 0


# ---------- camera ----------

func _process(delta: float) -> void:
	_clock += delta
	if _player == null or not is_instance_valid(_player):
		_player = null
		for player: Player in Player.all:
			if player.is_multiplayer_authority():
				_player = player
	if _player == null:
		return
	var slot: int = slot_at(_player.global_position)
	if _view_key_at(_player.global_position) != _view_key:
		apply_view(_player)
	if slot >= 0 and not _busy:
		var here: Interior = interior_at(_player.global_position)
		var here_id: String = here.id if here != null else ""
		if here_id != _here_id: ## from a room into the one next door (no door to wipe): the story notes where she has been
			var before: Interior = interior(_here_id)
			_here_id = here_id
			if before != null and here != null and before.neighbors.has(here) and _player.quests != null:
				_player.quests.set_flag("left_" + before.id)
				_player.quests.set_flag("entered_" + here.id)
		if _player.quests != null:
			for room: Interior in _interiors.values(): ## a saved game: the door she opened stays open
				if room.door != null and room.door.opens and not room.door.is_open and _player.quests.has_flag("door_open_" + room.id):
					room.door.open_now(false)
		if here != null and here.veiled and not here.revealed and not here.lifting: ## a veiled room lies under shadow smoke until somebody stands in it: the smoke lifts from where she stands
			var flag: String = "revealed_" + here.id
			if _player.quests != null and _player.quests.has_flag(flag):
				here.reveal_now()
			else:
				if _player.quests != null:
					_player.quests.set_flag(flag)
				here.lift_veil(_player.global_position)
	elif slot < 0:
		_here_id = ""
	# the room's ambience fades in and out with the door; the boards creak now and then under her feet
	var want: float = -9.0 if slot >= 0 else -80.0
	_ambient.volume_db = move_toward(_ambient.volume_db, want, 60.0 * delta)
	if slot >= 0 and not _ambient.playing:
		_ambient.play()
	elif slot < 0 and _ambient.playing and _ambient.volume_db <= -79.0:
		_ambient.stop()
	if slot >= 0 and _player.velocity.length() > 20.0:
		_step_clock += delta
		if _step_clock > 0.42:
			_step_clock = 0.0
			if randf() < 0.2:
				_creaks += 1
				_sound("creak_a" if _creaks % 2 == 0 else "creak_b", -15.0)


## The camera stays on the room while she is in one; outside it is free again.
## What the camera frames at a position: "" outside, else the rooms that share the view (the camera is set again when she comes in or goes out, not by slot: the long hallway runs through several).
func _view_key_at(pos: Vector2) -> String:
	if slot_at(pos) < 0:
		return ""
	var seen: Interior = interior_at(pos)
	return str(seen.union_rect()) if seen != null else str(slot_at(pos))


func apply_view(player: Player) -> void:
	var camera: Camera2D = player.get("_camera") as Camera2D
	if camera == null:
		return
	var inside: Interior = interior_at(player.global_position)
	if inside != null:
		var rect: Rect2 = inside.view_rect(get_viewport().get_visible_rect().size)
		camera.limit_left = int(rect.position.x)
		camera.limit_top = int(rect.position.y)
		camera.limit_right = int(rect.end.x)
		camera.limit_bottom = int(rect.end.y)
	else:
		camera.limit_left = -10000000
		camera.limit_top = -10000000
		camera.limit_right = 10000000
		camera.limit_bottom = 10000000
	camera.reset_smoothing()
	_view_key = _view_key_at(player.global_position)


# ---------- doors ----------

func _cover_to(amount: float, seconds: float) -> void:
	_wipe_layer.visible = true
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_method(func(v: float) -> void: _set_cover(v), _cover, amount, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if amount <= 0.0:
		_wipe_layer.visible = false


func _set_cover(v: float) -> void:
	_cover = v
	_wipe_material.set_shader_parameter("cover", v)
	_wipe_material.set_shader_parameter("time", _clock)
	_wipe_material.set_shader_parameter("view_size", (_wipe_layer.get_meta("rect") as ColorRect).size)


func door_sound(id: String, volume_db: float) -> void:
	_sound(id, volume_db)


func _sound(id: String, volume_db: float) -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = SOUNDS[id] as AudioStream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## E at a door (local player): the door swings, the dark closes in, she is moved, the dark opens in the other place.
func use_door(player: Player, door: Doorway) -> void:
	if _busy or player.story_lock:
		return
	_busy = true
	player.story_lock = true
	InputManager.ui_blocking = true
	var open_tween: Tween = create_tween()
	open_tween.tween_method(func(v: float) -> void: door.set_open(v), 0.0, 1.0, 0.32)
	_sound("open", -4.0)
	await _cover_to(1.0, 0.5)
	var spot: Vector2
	var facing: Vector2
	if door.leaving:
		var hut: Hut = _entrances.get(door.interior_id) as Hut
		spot = hut.exit_position if hut != null else player.global_position
		facing = Vector2.DOWN
	else:
		spot = interior(door.interior_id).entry_position()
		facing = Vector2.UP
	player.request_teleport(spot)
	player.facing = facing
	apply_view(player)
	door.set_open(0.0)
	var other: Doorway = null
	if door.leaving:
		var outside: Hut = _entrances.get(door.interior_id) as Hut
		other = outside.doorway if outside != null else null
	else:
		other = interior(door.interior_id).door
	if other != null:
		other.set_open(0.7)
	_sound("close", -8.0)
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _cover_to(0.0, 0.6)
	if other != null:
		var close_tween: Tween = create_tween()
		close_tween.tween_method(func(v: float) -> void: other.set_open(v), 0.7, 0.0, 0.4)
	player.story_lock = false
	InputManager.ui_blocking = false
	_busy = false
	if not door.leaving and player.quests != null: ## inside: the next step of the story may start here (the cabin: the spider)
		player.quests.set_flag("entered_" + door.interior_id)
	if door.leaving and player.quests != null: ## outside again: the next step of the story (a thought, a new goal) starts now, not under the closing dark
		player.quests.set_flag("hud_unlocked") ## hotbar, clock and purse return the first time she is out
		player.quests.set_flag("left_" + door.interior_id)
		if player.quests.has_flag("day2_started"): ## the second morning: the knight greets her and sends her to the lumberjack's hut
			player.quests.start("lumberjack")


## A change of place without a door (the mine's stairs and lift): the dark closes in as an iris, `move` runs (it moves the player), the dark opens.
func transit(player: Player, move: Callable) -> void:
	if _busy or player.story_lock:
		return
	_busy = true
	player.story_lock = true
	InputManager.ui_blocking = true
	await _cover_to(1.0, 0.5)
	await move.call()
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _cover_to(0.0, 0.6)
	player.story_lock = false
	InputManager.ui_blocking = false
	_busy = false


## Puts the player into the room at `spot` (room pixels) without the door (the wake-up scene).
func place_player(player: Player, id: String, spot: Vector2) -> void:
	var inside: Interior = interior(id)
	player.global_position = inside.room_to_global(spot)
	player.velocity = Vector2.ZERO
	apply_view(player)
