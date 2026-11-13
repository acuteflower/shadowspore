extends CanvasLayer
## The game's own mouse cursor. The OS cursor is hidden and a pixel-art one is drawn on top of everything (layer 128), in the
## 640x360 picture, so it scales and snaps like the rest of the game and keeps animating while the Escape menu pauses the world.
##
## One `Look` at a time, picked every frame from what the heroine is doing and what the mouse is over:
##   menus and windows   ARROW (a little leaf sprouts from its tail), ARROW_HOT over something clickable, GRAB / GRABBING (items,
##                       dragging, the map and the skill graph), DEAD (the glitching arrow of the death screen)
##   in the world        AIM (a breathing bloom that folds while the blade swings), SNEAK (a closed bud), BUSY (spores orbit while she
##                       picks or eats), ENEMY (fangs close in over a hurtbox), HARVEST (a teal bloom over a plant the held tool can take, or one E can pick)
##   building            BUILD / BUILD_BAD (teal / red brackets), DEMOLISH (a red cross, bright over a piece)
##   fishing             FISH_AIM / FISH_BAD (cast ring), FISH_CAST (ring draws in), FISH_DRIFT (ripples), FISH_NIBBLE (twitching),
##                       FISH_BITE (golden flash), FISH_DRILL (a ring that trembles and turns petrol -> gold -> red with the line's tension)
## By day the accents are gold, by night they turn void violet and a tendril creeps from the tip (`VineStyle.void_amount`). Clicks send
## out a ring and sparks, moving fast sheds motes. A gamepad hides it, so does leaving the window. Options -> EIGENER CURSOR turns it off.
##
## Custom-drawn UI that knows what is clickable calls `GameCursor.set_hint(self, &"click")` (or &"grab"), and `&""` when the mouse leaves:
## hints of hidden nodes are ignored, so a closing window needs no clean-up.
##
## This script talks to the player, the build mode and plants only through duck typing: the player scene preloads the HUD, whose scripts
## call this autoload, so a typed `Player` here would be a cyclic dependency (same reason `Hud.bind` takes an untyped player).

const LAYER_INDEX: int = 128
const PROBE_RADIUS: float = 6.0 ## px around the mouse in which a hurtbox counts as "under" it
const HURTBOX_MASK: int = 1 << 4 ## physics layer 5, the one weapons hit
const PICK_REACH: float = 7.0 ## px from the edge of a pickable plant in which the mouse counts as on it
const PICK_NEAR: float = 120.0 ## px: plants further from the mouse than this are not even asked (tall blossom trees reach up here)
const FAUNA_NEAR: float = 40.0 ## px: animals further from the mouse than this are not even asked
const FAUNA_REACH: float = 8.0 ## px from an animal's body where it counts even off its painted pixels
const PICK_EVERY: float = 0.05 ## seconds between two scans of the pickable plants
const POP_LIFE: float = 0.30
const MAX_MOTES: int = 48
const HOVER_NONE: int = 0
const HOVER_ENEMY: int = 1
const HOVER_HARVEST: int = 2
const HOVER_FAUNA: int = 3 ## an animal: it cannot be hurt, the cursor only shrinks to a dot
const FISH_CASTING: int = 1 ## FishingComponent.S, mirrored (a typed reference would be cyclic)
const FISH_DRIFTING: int = 2
const FISH_NIBBLE: int = 3
const FISH_BITE: int = 4
const FISH_DRILL: int = 5
const TEAL: Color = Color("3cc0c6")
const TEAL_LIGHT: Color = Color("78f4e6")
const DANGER: Color = Color("ff4a63")
const MAGENTA: Color = Color("ff4fd8")
const GOLD: Color = Color("e6c468")

enum Look {
	HIDDEN, ARROW, ARROW_HOT, GRAB, GRABBING, DEAD,
	AIM, SNEAK, BUSY, ENEMY, HARVEST, CHARGE,
	BUILD, BUILD_BAD, DEMOLISH,
	FISH_AIM, FISH_BAD, FISH_CAST, FISH_DRIFT, FISH_NIBBLE, FISH_BITE, FISH_DRILL,
	TINY,
}

var look: Look = Look.HIDDEN ## what is shown now
var look_age: float = 10.0 ## seconds since `look` changed

var _time: float = 0.0
var _last_usec: int = 0
const SMOOTH_POSITION: bool = true ## false: snap the cursor to whole art pixels again
var _raw: Vector2 = Vector2(-1.0, -1.0)
var _pos: Vector2 = Vector2.ZERO ## the mouse in the 640x360 picture, whole pixels
var _speed: float = 0.0 ## px/s, smoothed
var _alpha: float = 0.0
var _idle: float = 0.0 ## seconds the mouse has not moved
var _click_age: float = 10.0
var _night: float = 0.0
var _enabled: bool = true
var _canvas: Node2D
var _probe: PhysicsShapeQueryParameters2D
var _probe_wanted: bool = false
var _hover: int = HOVER_NONE
var _hover_id: int = 0 ## instance id of the plant the mouse is on (0 = none)
var _hover_seen: int = 0 ## the one the painter has already announced
var _pick_wait: float = 0.0
var _pick_id: int = 0 ## last scan: the pickable plant under the mouse
var _fauna_seen: bool = false ## last scan: an animal lies under the mouse
var _interactables_cache: Array[Node] = []
var _interactables_cache_time: float = -999.0
var _fauna_cache: Array[Node] = []
var _fauna_cache_time: float = -999.0
var _last_scan_aim: Vector2 = Vector2.INF
var _player: Node
var _hints: Dictionary = {} ## instance id of the asking node -> &"click" / &"grab"
var _pops: Array[Dictionary] = [] ## rings: {pos, age, life, color, r0, r1}
var _motes: Array[Dictionary] = [] ## specks: {pos, vel, age, life, color}
var _mote_carry: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# what `_resolve` found out this frame, for the painter
var _hot: bool = false
var _swinging: bool = false
var _wounded: bool = false
var _locked: bool = false ## a demolish target is under the mouse
var _tension: float = 0.0


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_physics_process(false)
		return
	_rng.randomize()
	_last_usec = Time.get_ticks_usec()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = PROBE_RADIUS
	_probe = PhysicsShapeQueryParameters2D.new()
	_probe.shape = shape
	_probe.collision_mask = HURTBOX_MASK
	_probe.collide_with_areas = true
	_probe.collide_with_bodies = false
	_canvas = Node2D.new()
	_canvas.name = "Canvas"
	_canvas.draw.connect(_paint)
	add_child(_canvas)
	get_window().mouse_entered.connect(func() -> void: _in_window = true)
	get_window().mouse_exited.connect(func() -> void: _in_window = false)
	Input.use_accumulated_input = true ## accumulation prevents 1000Hz gaming mice from flooding input pipeline


var _in_window: bool = true ## the pointer is over the game window (mouse_entered / mouse_exited)


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Custom UI: the mouse is over something clickable (&"click") or draggable (&"grab"); pass &"" when it is not.
func set_hint(source: Object, kind: StringName) -> void:
	if source == null:
		return
	if kind == &"":
		_hints.erase(source.get_instance_id())
	else:
		_hints[source.get_instance_id()] = kind


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var dt: float = clampf(float(now - _last_usec) / 1000000.0, 0.0, 0.1) ## real time: slow motion and the pause must not slow the cursor
	_last_usec = now
	_enabled = bool(GameSettings.get_value("cursor"))
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if _enabled and _in_window else Input.MOUSE_MODE_VISIBLE ## outside the window the system pointer must show
	_canvas.visible = _enabled
	if not _enabled:
		return
	_time += dt
	_night = VineStyle.void_amount()
	var view: Viewport = get_viewport()
	var mouse: Vector2 = view.get_mouse_position()
	var inside: bool = view.get_visible_rect().has_point(mouse)
	var moved: float = mouse.distance_to(_raw)
	if moved > 0.5:
		_speed = lerpf(_speed, moved / maxf(dt, 0.001), 0.35)
		_idle = 0.0
	else:
		_speed = lerpf(_speed, 0.0, 0.35)
		_idle += dt
	_raw = mouse
	_pos = mouse if SMOOTH_POSITION else mouse.round() ## sub-pixel: whole art pixels were 3-4 screen pixels, so the cursor stepped
	var next: Look = _resolve()
	if next != look:
		_on_look_changed(look, next)
		look = next
		look_age = 0.0
	else:
		look_age += dt
	if _hover_id != _hover_seen:
		_hover_seen = _hover_id
		if _hover_id != 0 and look == Look.HARVEST and look_age > 0.0: ## slid from one plant onto the next: the bloom opens again
			look_age = 0.0
			_pop(TEAL_LIGHT, 3.0, 9.0)
	if Input.is_action_just_pressed("action_primary") or Input.is_action_just_pressed("action_secondary"):
		_click_age = 0.0
		_spawn_click()
	else:
		_click_age += dt
	var goal: float = 0.0 if look == Look.HIDDEN or not inside else 1.0
	_alpha = move_toward(_alpha, goal, dt * (7.0 if goal > _alpha else 5.0))
	_update_particles(dt)
	_canvas.queue_redraw()


func _physics_process(delta: float) -> void:
	_hover = HOVER_NONE
	_hover_id = 0
	if not _probe_wanted or _probe == null:
		_pick_id = 0
		_fauna_seen = false
		return
	var aim: Vector2 = InputManager.aim_world_position()
	_probe.transform = Transform2D(0.0, aim)
	var hits: Array[Dictionary] = get_viewport().world_2d.direct_space_state.intersect_shape(_probe, 8)
	var plant: Object = null
	for hit: Dictionary in hits:
		var collider: Object = hit["collider"]
		if collider == null:
			continue
		if collider.has_method("harvest_owner"): ## a plant's, rock's, fallen log's or clover field's hurtbox
			if plant == null:
				plant = collider.call("harvest_owner")
		elif "health" in collider: ## anything with a health bar that weapons can hurt
			var health: Object = collider.get("health")
			if health != null and float(health.get("current")) > 0.0:
				_hover = HOVER_ENEMY
				return
	if plant != null and _can_harvest(plant):
		_hover = HOVER_HARVEST
		_hover_id = plant.get_instance_id()
		return
	_pick_wait -= delta
	if _pick_wait <= 0.0:
		_pick_wait = PICK_EVERY
		var aim_moved: bool = aim.distance_squared_to(_last_scan_aim) > 2.0
		if aim_moved or _pick_id == 0 or not is_instance_valid(instance_from_id(_pick_id)):
			_last_scan_aim = aim
			var found: Object = _pickable_at(aim)
			_pick_id = found.get_instance_id() if found != null else 0
			_fauna_seen = _pick_id == 0 and _fauna_at(aim)
	if _pick_id != 0 and is_instance_valid(instance_from_id(_pick_id)):
		var plant_node: Object = instance_from_id(_pick_id)
		if plant_node != null and plant_node.has_method("is_depleted") and not bool(plant_node.call("is_depleted")):
			_hover = HOVER_HARVEST
			_hover_id = _pick_id
		else:
			_pick_id = 0
	elif _fauna_seen:
		_hover = HOVER_FAUNA


func _get_cached_interactables() -> Array[Node]:
	if _interactables_cache.is_empty() or _time - _interactables_cache_time > 0.5:
		_interactables_cache = get_tree().get_nodes_in_group("interactables")
		_interactables_cache_time = _time
	return _interactables_cache


func _get_cached_fauna() -> Array[Node]:
	if _fauna_cache.is_empty() or _time - _fauna_cache_time > 0.5:
		_fauna_cache = get_tree().get_nodes_in_group("wild_animals")
		_fauna_cache_time = _time
	return _fauna_cache


## Plants that E picks (data/plants.json `pickup`: berries, glow caps, flowers, blossom trees, roots, pebbles) need no tool, and the small ones
## (pebbles, glow caps) have no hurtbox for the probe to find. So the interactables are asked by their own reach: the nearest one that still
## offers its prompt (not picked yet, not a flower that is shut for the day) and whose edge is within `PICK_REACH` of the mouse, or whose painted
## pixels lie under the mouse (a blossom crown is far from its trunk). Duck typed, like the rest.
func _pickable_at(at: Vector2) -> Object:
	var best: Object = null
	var best_reach: float = PICK_REACH
	var at_x: float = at.x
	var at_y: float = at.y
	for node: Node in _get_cached_interactables():
		if not is_instance_valid(node):
			continue
		var item: Node2D = node as Node2D
		if item == null:
			continue
		var gpos: Vector2 = item.global_position
		# Fast spatial AABB pre-filter: eliminates >95% of candidates without expensive method calls
		if absf(gpos.x - at_x) > PICK_NEAR or absf(gpos.y - at_y) > PICK_NEAR:
			continue
		if not item.is_visible_in_tree() or not item.has_method("is_depleted"):
			continue
		if gpos.distance_squared_to(at) > PICK_NEAR * PICK_NEAR:
			continue
		if String(item.call("prompt")) == "" or not (item.call("spec") as Dictionary).has("pickup"):
			continue
		var reach: float = float(item.call("reach_distance", at))
		if reach > PICK_REACH:
			if not PixelPick.hit(item, at):
				continue
			reach = PICK_REACH
		if reach <= best_reach:
			best_reach = reach
			best = item
	return best


## An animal under the mouse (group `wild_animals`): its painted pixels, or its body centre. Animals cannot be hurt, so they only get the small cursor.
func _fauna_at(at: Vector2) -> bool:
	var at_x: float = at.x
	var at_y: float = at.y
	for node: Node in _get_cached_fauna():
		if not is_instance_valid(node):
			continue
		var animal: Node2D = node as Node2D
		if animal == null:
			continue
		var apos: Vector2 = animal.global_position
		# Fast spatial AABB pre-filter
		if absf(apos.x - at_x) > FAUNA_NEAR or absf(apos.y - at_y) > FAUNA_NEAR:
			continue
		if not animal.is_visible_in_tree():
			continue
		if apos.distance_squared_to(at) > FAUNA_NEAR * FAUNA_NEAR:
			continue
		if at.distance_to(apos + Vector2(0.0, -8.0)) <= FAUNA_REACH or PixelPick.hit(animal, at):
			return true
	return false


## The held tool is the one the plant under the mouse asks for (data/plants.json `harvest.tool`; clover and fallen logs: data/harvest.json).
func _can_harvest(plant: Object) -> bool:
	if _player == null or bool(plant.call("is_depleted")):
		return false
	var spec: Dictionary = plant.call("spec") as Dictionary
	var needs: String = String((spec.get("harvest", spec) as Dictionary).get("tool", ""))
	var held: Dictionary = _player.inventory.active_stack()
	return needs != "" and not held.is_empty() and String(Items.definition(held).get("tool", "")) == needs


# ---------------------------------------------------------------- what to show

func _resolve() -> Look:
	_probe_wanted = false
	_swinging = false
	_wounded = false
	_locked = false
	_tension = 0.0
	var kind: StringName = _hint_kind()
	_hot = kind == &"click"
	if not InputManager.using_mouse:
		return Look.HIDDEN
	var player: Node = _local_player()
	if player != null:
		if float(player.health.current) <= 0.0:
			return Look.DEAD
		_swinging = bool(player.attack.is_swinging())
		_wounded = bool(player.wounded)
	var view: Viewport = get_viewport()
	var over: Look = _control_look(view.gui_get_hovered_control(), kind)
	if InputManager.ui_blocking or InputManager.menu_open or InputManager.map_open or (InputManager.skills_open or InputManager.progress_open):
		if view.gui_is_dragging() or _holds_stack(player):
			return Look.GRABBING
		if InputManager.map_open or (InputManager.skills_open or InputManager.progress_open): ## both are dragged around
			if over == Look.ARROW_HOT:
				return over
			return Look.GRABBING if Input.is_action_pressed("action_primary") else Look.GRAB
		return over if over != Look.HIDDEN else Look.ARROW
	if player == null:
		return Look.ARROW
	if over != Look.HIDDEN: ## the hotbar and other buttons of the HUD
		return Look.GRABBING if over == Look.GRAB and view.gui_is_dragging() else over
	var build: Node = get_tree().get_first_node_in_group("build_mode") if InputManager.build_open else null
	if build != null and bool(build.active):
		var menu: Object = build.get("menu")
		if menu != null and bool(menu.call("over_card")):
			return Look.ARROW_HOT
		if bool(build.demolish):
			_locked = int(build.target_id) >= 0
			return Look.DEMOLISH
		return Look.BUILD if String(build.reason) == "" else Look.BUILD_BAD
	var fishing: Node = player.fishing
	if fishing != null and bool(fishing.rod_active()):
		_tension = clampf(float(fishing.tension), 0.0, 1.0)
		match int(fishing.state):
			FISH_CASTING:
				return Look.FISH_CAST
			FISH_DRIFTING:
				return Look.FISH_DRIFT
			FISH_NIBBLE:
				return Look.FISH_NIBBLE
			FISH_BITE:
				return Look.FISH_BITE
			FISH_DRILL:
				return Look.FISH_DRILL
		return Look.FISH_AIM if bool(fishing.aim_valid) else Look.FISH_BAD
	if bool(player.story_lock) or player.intro != null or bool(player.fainting) or bool(player.stumbling):
		return Look.HIDDEN if _idle > 1.5 else Look.AIM ## a scene plays: the cursor tucks itself away
	if bool(player.attack.is_charging()): ## the right mouse button holds a heavy blow
		return Look.CHARGE
	if bool(player.is_busy()):
		return Look.BUSY
	_probe_wanted = true
	if _hover == HOVER_ENEMY:
		return Look.ENEMY
	if bool(player.stealth.sneaking):
		return Look.SNEAK
	if _hover == HOVER_HARVEST:
		return Look.HARVEST
	if _hover == HOVER_FAUNA:
		return Look.TINY
	return Look.AIM


## A stack of items on the cursor (the inventory window): duck-typed, the cursor never names Player.
func _holds_stack(player: Object) -> bool:
	return player != null and not (player.inventory.held as Dictionary).is_empty()


## What a hovered control or a hint asks for; HIDDEN = nothing special.
func _control_look(hovered: Control, kind: StringName) -> Look:
	if kind == &"click":
		return Look.ARROW_HOT
	if kind == &"grab":
		return Look.GRAB
	if hovered == null:
		return Look.HIDDEN
	var script: Script = hovered.get_script() as Script
	if script != null and script.get_global_name() == &"ItemSlot":
		var filled: bool = hovered.get("inventory") != null and not (hovered.call("stack") as Dictionary).is_empty()
		return Look.GRAB if filled else Look.ARROW
	var button: BaseButton = hovered as BaseButton
	if button != null and not button.disabled:
		return Look.ARROW_HOT
	return Look.HIDDEN


func _hint_kind() -> StringName:
	var found: StringName = &""
	for id: int in _hints.keys():
		var source: Object = instance_from_id(id)
		if source == null:
			_hints.erase(id)
			continue
		if not _shown(source):
			continue
		var kind: StringName = _hints[id]
		if kind == &"click":
			return kind
		found = kind
	return found


## False for a hint of a hidden control, or of one under a hidden canvas layer (windows that close without clearing their hint).
func _shown(source: Object) -> bool:
	var node: Node = source as Node
	if node == null:
		return true
	if not node.is_inside_tree():
		return false
	var item: CanvasItem = node as CanvasItem
	if item != null and not item.is_visible_in_tree():
		return false
	var up: Node = node
	while up != null:
		var canvas_layer: CanvasLayer = up as CanvasLayer
		if canvas_layer != null and not canvas_layer.visible:
			return false
		up = up.get_parent()
	return true


## The player this machine controls (found by group, re-checked a few times a second while there is none).
func _local_player() -> Node:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = null
	if Engine.get_process_frames() % 12 != 0:
		return null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.is_multiplayer_authority():
			_player = node
			break
	return _player


func _on_look_changed(from: Look, to: Look) -> void:
	if from == Look.HIDDEN or to in [Look.HIDDEN, Look.ARROW, Look.ARROW_HOT, Look.AIM, Look.SNEAK]:
		return
	_pop(_look_tone(to), 3.0, 9.0) ## a new state announces itself with a ring


func _look_tone(which: Look) -> Color:
	match which:
		Look.ENEMY, Look.BUILD_BAD, Look.DEMOLISH, Look.FISH_BAD:
			return DANGER
		Look.HARVEST, Look.BUILD, Look.FISH_AIM, Look.FISH_CAST, Look.FISH_DRIFT, Look.FISH_NIBBLE, Look.FISH_DRILL:
			return TEAL_LIGHT
		Look.FISH_BITE:
			return GOLD
		Look.DEAD:
			return MAGENTA
	return _tone()


## Gold by day, void violet by night: the colour of the cursor's glow.
func _tone() -> Color:
	return VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, _night)


# ---------------------------------------------------------------- particles

func _spawn_click() -> void:
	var tone: Color = _look_tone(look)
	_pop(tone, 3.0, 11.0 if look >= Look.AIM else 8.0)
	for k: int in 5:
		_add_mote(_pos, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(24.0, 58.0), _rng.randf_range(0.2, 0.38), tone.lightened(0.3))


func _pop(color: Color, from_radius: float, to_radius: float) -> void:
	_pops.append({"pos": _pos, "age": 0.0, "life": POP_LIFE, "color": color, "r0": from_radius, "r1": to_radius})


func _add_mote(at: Vector2, velocity: Vector2, life: float, color: Color) -> void:
	if _motes.size() < MAX_MOTES:
		_motes.append({"pos": at, "vel": velocity, "age": 0.0, "life": life, "color": color})


func _update_particles(dt: float) -> void:
	for i: int in range(_pops.size() - 1, -1, -1):
		var pop: Dictionary = _pops[i]
		pop["age"] = float(pop["age"]) + dt
		if float(pop["age"]) >= float(pop["life"]):
			_pops.remove_at(i)
	for i: int in range(_motes.size() - 1, -1, -1):
		var mote: Dictionary = _motes[i]
		var age: float = float(mote["age"]) + dt
		if age >= float(mote["life"]):
			_motes.remove_at(i)
			continue
		mote["age"] = age
		mote["pos"] = (mote["pos"] as Vector2) + (mote["vel"] as Vector2) * dt
	if _speed > 140.0 and _alpha > 0.3: ## fast mouse: it sheds motes that rise and twinkle out
		_mote_carry += dt * minf(_speed / 40.0, 16.0)
		while _mote_carry >= 1.0:
			_mote_carry -= 1.0
			var tint: Color = [VineStyle.PETAL, _look_tone(look), _look_tone(look).lightened(0.35)][_rng.randi() % 3]
			_add_mote(_pos + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0)), Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-20.0, -6.0)), _rng.randf_range(0.3, 0.6), tint)
	else:
		_mote_carry = 0.0


# ---------------------------------------------------------------- painting

func _paint() -> void:
	if _alpha <= 0.01 or look == Look.HIDDEN:
		return
	for pop: Dictionary in _pops:
		var p: float = float(pop["age"]) / float(pop["life"])
		var radius: int = int(lerpf(float(pop["r0"]), float(pop["r1"]), 1.0 - pow(1.0 - p, 2.0)))
		VineStyle.ring(_canvas, pop["pos"] as Vector2, radius, _a(pop["color"] as Color, (1.0 - p) * 0.85), 0.75)
	var tone: Color = _tone()
	var pulse: float = 0.8 + 0.2 * sin(_time * 3.0)
	match look:
		Look.ARROW, Look.ARROW_HOT:
			_glow(_pos + Vector2(2, 3), 10.0, tone, (0.85 if look == Look.ARROW_HOT else 0.45) * pulse)
			_blit(&"arrow", &"", _pos)
			if look == Look.ARROW_HOT:
				for k: int in 3: ## sparks circle the tip: this is clickable
					var a: float = _time * 3.2 + float(k) * TAU / 3.0
					_dot(_pos + Vector2(2, 2) + Vector2(cos(a), sin(a)) * (7.0 + sin(_time * 5.0 + float(k))), _a(VineStyle.PETAL, 0.9))
			_tendril(_pos + Vector2(7, 15), Vector2(0.35, 0.94))
		Look.GRAB:
			_glow(_pos, 11.0, tone, 0.4 * pulse)
			_blit(&"hand", &"", _pos)
		Look.GRABBING:
			_glow(_pos, 11.0, tone, 0.6)
			_blit(&"fist", &"", _pos + Vector2(0, 1))
		Look.DEAD:
			_paint_dead()
		Look.AIM:
			var folded: bool = _swinging or _click_age < 0.09 ## the petals close while the blade is out
			var glyph: StringName = &"bloom_3" if folded else (&"bloom_5" if sin(_time * 2.6) > 0.2 else &"bloom_4")
			_glow(_pos, 10.0, tone, (0.3 if folded else 0.6) * pulse)
			_blit(glyph, &"", _pos, 0.8 if _swinging else 1.0)
			_tendril(_pos + Vector2(0, 6), Vector2(0.1, 1.0))
		Look.SNEAK:
			_glow(_pos, 8.0, tone, 0.25)
			_blit(&"bud", &"", _pos, 0.8)
		Look.TINY: ## over an animal: a single dot, you cannot strike it
			for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				_dot(_pos + offset, _a(VineStyle.OUTLINE, 0.7))
			_dot(_pos, _a(tone, 0.95))
		Look.BUSY:
			_glow(_pos, 10.0, tone, 0.5)
			_blit(&"bloom_3", &"", _pos)
			for k: int in 3:
				var a: float = _time * 5.0 + float(k) * TAU / 3.0
				_dot(_pos + Vector2(cos(a), sin(a)) * 8.0, _a(VineStyle.PETAL))
				_dot(_pos + Vector2(cos(a - 0.4), sin(a - 0.4)) * 8.0, _a(tone, 0.6))
		Look.CHARGE: ## the bloom folds as the blade is drawn, a ring closes in, gold when the blow is worth letting go
			var player_node: Node = _local_player()
			var amount: float = 0.0
			var draw: float = 0.0
			var armed: bool = false
			if player_node != null:
				amount = float(player_node.attack.charge_amount())
				draw = float(player_node.attack.charge_draw())
				armed = bool(player_node.attack.charge_ready())
			var ring_tone: Color = GOLD if armed else tone
			var full: bool = amount >= 0.98
			var throb: float = 0.5 + 0.5 * sin(_time * 22.0) if full else 1.0
			_glow(_pos, 10.0 + 4.0 * amount, ring_tone, (0.3 + 0.5 * amount) * throb)
			_blit(&"bloom_3" if draw > 0.4 else &"bloom_4", &"", _pos, 0.8 + 0.2 * throb)
			VineStyle.ring(_canvas, _pos, int(lerpf(15.0, 8.0, draw)), _a(ring_tone, 0.35 + 0.5 * draw), 0.75)
			if armed:
				for k: int in 4: ## four sparks sit on the ring: it is ready
					var a: float = float(k) * TAU / 4.0 + _time * (1.5 + 4.0 * amount)
					_dot(_pos + Vector2(cos(a), sin(a)) * lerpf(9.0, 7.0, amount), _a(GOLD, 0.6 + 0.4 * throb))
		Look.ENEMY:
			var shut: bool = _swinging or _click_age < 0.12
			_glow(_pos, 10.0, DANGER, 0.5 + 0.3 * sin(_time * 9.0))
			_blit(&"fang_shut" if shut else &"fang_open", &"red", _pos)
		Look.HARVEST:
			var ripe: float = clampf(look_age / 0.24, 0.0, 1.0) ## the bud opens when the mouse lands on something ripe
			var beat: float = sin(_time * 4.4)
			var glyph_name: StringName = &"bud" if ripe < 0.4 else (&"bloom_3" if ripe < 1.0 else (&"seed_4" if beat > 0.0 else &"seed_3"))
			_glow(_pos, 10.0, TEAL_LIGHT, (0.3 + 0.4 * ripe) * (0.8 + 0.2 * beat))
			_blit(glyph_name, &"teal", _pos)
			var reach: float = fposmod(_time * 1.3, 1.0) ## a ring draws in again and again: take it
			VineStyle.ring(_canvas, _pos, int(lerpf(12.0, 7.0, reach)), _a(TEAL_LIGHT, (1.0 - reach) * 0.55 * ripe), 0.75)
			for k: int in 3: ## spores rise: it is ripe for the tool in her hand
				var phase: float = fposmod(_time * 0.9 + float(k) / 3.0, 1.0)
				_dot(_pos + Vector2(sin(_time * 2.0 + float(k) * 2.1) * 5.0, -2.0 - phase * 12.0), _a(TEAL_LIGHT, (1.0 - phase) * minf(phase * 6.0, 1.0) * ripe))
		Look.BUILD, Look.BUILD_BAD:
			var good: bool = look == Look.BUILD
			var shake: Vector2 = Vector2(signf(sin(_time * 90.0)), 0.0) if not good and _click_age < 0.18 else Vector2.ZERO
			_glow(_pos, 10.0, TEAL_LIGHT if good else DANGER, 0.35 * pulse)
			_blit(&"bracket_4" if sin(_time * 4.0) > 0.3 else &"bracket_5", &"teal" if good else &"red", _pos + shake)
		Look.DEMOLISH:
			_glow(_pos, 10.0, DANGER, 0.6 if _locked else 0.2)
			_blit(&"cross", &"red", _pos, 1.0 if _locked else 0.6)
		Look.FISH_AIM, Look.FISH_BAD:
			_glow(_pos, 10.0, TEAL_LIGHT if look == Look.FISH_AIM else DANGER, 0.3 * pulse)
			_blit(&"fish_bad" if look == Look.FISH_BAD else (&"fish_5" if sin(_time * 2.0) > 0.4 else &"fish_6"), &"red" if look == Look.FISH_BAD else &"teal", _pos)
		Look.FISH_CAST:
			var frames: Array[StringName] = [&"fish_6", &"fish_5", &"fish_4"] ## the ring draws in around the float's landing
			_glow(_pos, 10.0, TEAL_LIGHT, 0.5)
			_blit(frames[clampi(int(look_age * 9.0), 0, 2)], &"teal", _pos)
		Look.FISH_DRIFT:
			_ripples(TEAL, 0.55)
			_blit(&"fish_5", &"teal", _pos)
		Look.FISH_NIBBLE:
			var seed_step: int = int(_time * 14.0) ## the float twitches: so does the cursor
			var twitch: Vector2 = Vector2(roundf((VineStyle.rand(seed_step) - 0.5) * 2.0), roundf((VineStyle.rand(seed_step + 3) - 0.5) * 2.0))
			_ripples(GOLD, 1.5)
			_blit(&"fish_4", &"teal", _pos + twitch)
		Look.FISH_BITE:
			var flash: bool = int(_time * 12.0) % 2 == 0
			_glow(_pos, 12.0, GOLD, 0.9)
			_ripples(GOLD, 2.4)
			_blit(&"bite_long" if flash else &"bite_short", &"gold", _pos + (Vector2(signf(sin(_time * 80.0)), 0.0)))
		Look.FISH_DRILL:
			_paint_drill()
	for mote: Dictionary in _motes:
		var p: float = float(mote["age"]) / float(mote["life"])
		_dot(mote["pos"] as Vector2, _a(mote["color"] as Color, (1.0 - p) * (0.6 + 0.4 * sin(float(mote["age"]) * 40.0))))
	if _wounded and look >= Look.AIM: ## at 10 % health her blood beats in the cursor too
		_glow(_pos, 12.0, DANGER, 0.45 * maxf(0.0, sin(_time * 7.0)))


## The death screen's arrow: magenta, torn into bands that slip sideways like the shadow creatures.
func _paint_dead() -> void:
	var glyph: CursorArt.Glyph = CursorArt.glyph(&"arrow", _night, &"magenta")
	var origin: Vector2 = _pos - Vector2(glyph.hot)
	var bands: int = 4
	var step: int = int(_time * 12.0)
	_glow(_pos + Vector2(2, 3), 10.0, MAGENTA, 0.4 + 0.3 * sin(_time * 6.0) + (0.3 if _hot else 0.0))
	for b: int in bands:
		var y0: int = int(float(glyph.size.y * b) / float(bands))
		var y1: int = int(float(glyph.size.y * (b + 1)) / float(bands))
		var shift: float = 0.0
		if VineStyle.rand(step * 7 + b) > 0.72:
			shift = roundf((VineStyle.rand(step + b * 13) - 0.5) * 8.0)
		_canvas.draw_texture_rect_region(glyph.texture, Rect2(origin + Vector2(shift, float(y0)), Vector2(float(glyph.size.x), float(y1 - y0))), Rect2(0.0, float(y0), float(glyph.size.x), float(y1 - y0)), Color(1, 1, 1, _alpha))
	if _hot:
		for k: int in 3:
			var a: float = _time * 3.2 + float(k) * TAU / 3.0
			_dot(_pos + Vector2(2, 2) + Vector2(cos(a), sin(a)) * 7.0, _a(MAGENTA.lightened(0.5), 0.9))


## The fight: the ring shows the line's tension the way the line's colour does (petrol -> gold -> red) and trembles with it.
func _paint_drill() -> void:
	var t: float = _tension
	var color: Color = TEAL.lerp(GOLD, t * 2.0) if t < 0.5 else GOLD.lerp(DANGER, (t - 0.5) * 2.0)
	var amp: float = t * 2.2
	var shake_step: int = int(_time * 30.0)
	var shake: Vector2 = Vector2(roundf((VineStyle.rand(shake_step) - 0.5) * amp), roundf((VineStyle.rand(shake_step + 5) - 0.5) * amp))
	_glow(_pos + shake, 12.0, color, 0.3 + 0.5 * t)
	VineStyle.ring(_canvas, _pos + shake, 9, _a(color, 0.9), 1.0 - 0.4 * t)
	_blit(&"fish_5", &"teal" if t < 0.45 else (&"gold" if t < 0.75 else &"red"), _pos + shake)


## Rings that spread from the cursor like ripples from a float.
func _ripples(color: Color, speed: float) -> void:
	for k: int in 2:
		var p: float = fposmod(_time * speed + float(k) * 0.5, 1.0)
		VineStyle.ring(_canvas, _pos, 4 + int(p * 9.0), _a(color, (1.0 - p) * 0.8), 0.6)


## At night a void tendril creeps from the cursor, like the ones on the HUD's vines.
func _tendril(origin: Vector2, heading: Vector2) -> void:
	if _night > 0.4 and _alpha > 0.95:
		VineStyle.tendril(_canvas, origin, heading.normalized(), 2 + int(5.0 * _night), _time, 5)


func _blit(glyph_name: StringName, accent: StringName, at: Vector2, alpha: float = 1.0) -> void:
	var glyph: CursorArt.Glyph = CursorArt.glyph(glyph_name, _night, accent)
	var origin: Vector2 = at - Vector2(glyph.hot)
	_canvas.draw_texture(glyph.texture, origin if SMOOTH_POSITION else origin.round(), Color(1, 1, 1, alpha * _alpha))


func _dot(at: Vector2, color: Color) -> void:
	_canvas.draw_rect(Rect2(at if SMOOTH_POSITION else at.round(), Vector2.ONE), color)


func _glow(at: Vector2, radius: float, color: Color, strength: float) -> void:
	VineStyle.glow(_canvas, at, radius, color, strength * _alpha) ## fixed radii only: the glow spans are cached per radius


func _a(color: Color, alpha: float = 1.0) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha * _alpha)
