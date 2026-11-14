extends Node
## Only place that reads input devices. Entities ask this, never Input directly.
## PC for now; touch (virtual twin-stick) plugs in here later.

## Set by open full-screen UI (inventory) so clicks and keys don't reach the game world.
var ui_blocking: bool = false
var inventory_open: bool = false ## the inventory window is open: its slots take clicks and number keys
var item_keys_claimed: bool = false ## the inventory uses the number keys this frame (an item under the mouse or on the cursor): the hotbar must not select

## True while the Escape menu is open (the inventory stays shut then).
var menu_open: bool = false
var mod_menu_open: bool = false ## the item drop menu holds the hero's movement and aim

## True while the free camera (L) flies: she stands still and nothing in the world reacts to the keys.
var freecam_open: bool = false

## True while the town's build mode (B) is on: LMB places instead of swinging, the number keys and the wheel choose a piece instead of a hotbar slot.
var build_open: bool = false

## True while the map (M) is open: the heroine stands still and the move keys pan the map.
var map_open: bool = false
var journal_open: bool = false

## Full-screen skill graph; kept true through its closing animation.
var skills_open: bool = false

## Full-screen progress window (levels and their rewards, P); kept true through its closing animation.
var progress_open: bool = false

## True while the mouse was the last aiming device used; false once a gamepad takes over.
var using_mouse: bool = true


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		using_mouse = true
	elif event is InputEventJoypadButton:
		using_mouse = false
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		using_mouse = false


func move_vector() -> Vector2:
	return Vector2.ZERO if map_open or journal_open or skills_open or progress_open or freecam_open or mod_menu_open else map_pan_vector()


func skills_pressed() -> bool:
	return Input.is_action_just_pressed("skills")


func progress_pressed() -> bool:
	return Input.is_action_just_pressed("progress")


func skills_center_pressed() -> bool:
	return Input.is_action_just_pressed("skills_center")


## The move keys / left stick as they are, for menus that pan (the map).
func map_pan_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## L: fly the free camera / land where it is. Works with menus shut only.
func freecam_pressed() -> bool:
	return not ui_blocking and not menu_open and Input.is_action_just_pressed("freecam")


func map_pressed() -> bool:
	return Input.is_action_just_pressed("map")


## Zoom keys: +1 in, -1 out, 0 none.
func map_zoom_step() -> int:
	return int(Input.is_action_just_pressed("map_zoom_in")) - int(Input.is_action_just_pressed("map_zoom_out"))


func map_center_pressed() -> bool:
	return Input.is_action_just_pressed("map_center")


func sprint_pressed() -> bool:
	return not (skills_open or progress_open) and Input.is_action_just_pressed("sprint")


func sprint_held() -> bool:
	return not (skills_open or progress_open) and Input.is_action_pressed("sprint")


func attack_pressed() -> bool:
	return not ui_blocking and not build_open and not freecam_open and Input.is_action_pressed("action_primary")


## Right mouse button / pad button: the weapon's secondary attack (the sword's heavy blow: hold to charge, let go to strike).
func secondary_pressed() -> bool:
	return not ui_blocking and not build_open and not map_open and not freecam_open and Input.is_action_just_pressed("action_secondary")


func secondary_held() -> bool:
	return not ui_blocking and not build_open and not map_open and not freecam_open and Input.is_action_pressed("action_secondary")


## The raw button, also while a menu owns the input (the charge of a heavy blow is dropped then, not released).
func secondary_down() -> bool:
	return Input.is_action_pressed("action_secondary")


## Dev key: spawn an enemy at the cursor.
func debug_spawn_pressed() -> bool:
	return not ui_blocking and Input.is_action_just_pressed("debug_spawn")


func debug_listener_pressed() -> bool:
	return not ui_blocking and Input.is_action_just_pressed("debug_spawn_listener")


## Dev key F3: spawn a void crusher at the cursor.
func debug_crusher_pressed() -> bool:
	return not ui_blocking and Input.is_action_just_pressed("debug_spawn_crusher")


## F5: a Lichtfischer, only in water.
func debug_fisher_pressed() -> bool:
	return not ui_blocking and Input.is_action_just_pressed("debug_spawn_fisher")


## Dev key F4 (host): the clock jumps one hour.
func debug_time_pressed() -> bool:
	return Input.is_action_just_pressed("debug_time")


## The map's travel mode: E held (the hold on a waystone's marker) and A / D or the arrow keys to step through the destinations.
func interact_held() -> bool:
	return Input.is_action_pressed("interact")


func map_select_step() -> int:
	return int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))


## E (gamepad Y): talk to / use whatever the prompt above an object offers.
func interact_pressed() -> bool:
	return not ui_blocking and not freecam_open and Input.is_action_just_pressed("interact")


func inventory_pressed() -> bool:
	return Input.is_action_just_pressed("inventory")


const HOTBAR_ACTIONS: Array[StringName] = [
	&"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4",
	&"hotbar_5", &"hotbar_6", &"hotbar_7", &"hotbar_8"
]


## Number key 1-8 pressed this frame -> 0-7, else -1.
func hotbar_pick() -> int:
	if (skills_open or progress_open) or build_open or freecam_open or item_keys_claimed or mod_menu_open:
		return -1
	for i: int in 8:
		if Input.is_action_just_pressed(HOTBAR_ACTIONS[i]):
			return i
	return -1


## Mouse wheel: +1 next, -1 previous, 0 none.
func hotbar_step() -> int:
	if ui_blocking or build_open or freecam_open: ## the wheel zooms the map / chooses the piece to build
		return 0
	if Input.is_action_just_pressed("hotbar_next"):
		return 1
	if Input.is_action_just_pressed("hotbar_prev"):
		return -1
	return 0


func sneak_held() -> bool:
	return not (skills_open or progress_open) and not freecam_open and Input.is_action_pressed("sneak")


func blink_pressed() -> bool:
	return not (skills_open or progress_open) and not freecam_open and not mod_menu_open and Input.is_action_just_pressed("blink")


## Alt (gamepad B): the shadow step, a short evasive step through the void.
func shadow_step_pressed() -> bool:
	return not (skills_open or progress_open) and not freecam_open and not ui_blocking and not build_open and Input.is_action_just_pressed("shadow_step")


func aim_world_position() -> Vector2:
	var vp: Viewport = get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_mouse_position()


func aim_vector(origin: Vector2) -> Vector2:
	return (aim_world_position() - origin).normalized()


# ---------- the town's build mode (docs/town.md) ----------

func build_toggle_pressed() -> bool:
	return not ui_blocking and Input.is_action_just_pressed("build")


## 0..7 when a number key chose a piece this frame, else -1.
func build_pick() -> int:
	for i: int in 8:
		if Input.is_action_just_pressed(HOTBAR_ACTIONS[i]):
			return i
	return -1


## Wheel or pad left/right: +1 next piece, -1 previous, 0 none.
func build_step() -> int:
	return int(Input.is_action_just_pressed("hotbar_next") or Input.is_action_just_pressed("build_next")) - int(Input.is_action_just_pressed("hotbar_prev") or Input.is_action_just_pressed("build_prev"))


# ---------- fishing (docs/fishing.md) ----------

func fish_press() -> bool:
	return not ui_blocking and not build_open and not map_open and not freecam_open and Input.is_action_just_pressed("action_primary")


func fish_held() -> bool:
	return not ui_blocking and not build_open and not map_open and not freecam_open and Input.is_action_pressed("action_primary")


func fish_reel_in_pressed() -> bool:
	return not ui_blocking and not build_open and not map_open and not freecam_open and Input.is_action_just_pressed("action_secondary")


func fish_bait_pressed() -> bool:
	return not ui_blocking and Input.is_action_just_pressed("fish_bait")


func fish_pose_pressed() -> bool:
	return not ui_blocking and Input.is_action_just_pressed("fish_pose")


func fish_book_pressed() -> bool:
	return Input.is_action_just_pressed("fish_book")
