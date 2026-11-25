class_name HudDirector
extends Node
## The HUD's direction (docs/hud_v2_konzept.md 4.2): one place that knows where every part lives and when it shows.
## Local and cosmetic, a child "Director" of the `Hud`. Everything comes from data/hud.json:
## * Contexts (idle, vista, boss, menu, dialogue, cutscene, combat, build, fish, swim, notice, town) are worked out every
##   frame. Each has a strength 0..1 that eases in and out with its own speed; a part's alpha is the product of
##   `1 - strength * (1 - factor)` over all contexts (factor 0 = `hide`, `dim` gives a factor). This replaced the old
##   idle / boss / menu-cover fades of `Hud`, with the same numbers.
## * Slots: parts of a stacking slot (`above_bar`) are lifted so a growing part pushes the ones above it up instead of
##   drawing over them (status tags, fishing leaf, small notices, speech box). Parts that draw relative to something
##   else read `hud_lift` (a property they own), the others are moved by their offsets.
## * The folded hotbar (`fold` in the data) carries the parts hanging on it.
## * Story locks: `unlock` flags hold parts back in a story world (the old ground.json `hidden_hud`).
## Tests force contexts with `force(ctx, on)` and read `rect_of(part)` / `alpha_of(part)`.

const DATA: String = "hud"
const COMBAT_RANGE: float = 220.0
const COMBAT_TICK: float = 0.25
const LIFT_SPEED: float = 140.0 ## px per second a stacked part moves when the one below grows or withers

var hud: CanvasLayer
var player: Node2D
var data: Dictionary = {}
var parts: Dictionary = {} ## name -> spec (from the data)
var strength: Dictionary = {} ## context -> 0..1 (eased)
var active: Dictionary = {} ## context -> bool (this frame)
var covered: bool = false ## a full-screen window is open (inventory, map, journal, skills, progress, pause)

var _forced: Dictionary = {} ## context -> bool, tests
var _idle_time: float = 0.0
var _last_pos: Vector2 = Vector2.INF
var _combat: bool = false
var _combat_tick: float = 0.0
var _lift: Dictionary = {} ## part -> current lift (px, up)
var _base: Dictionary = {} ## part -> Rect2(left, top, right, bottom) offsets as laid out
var _shift: Dictionary = {} ## part -> Vector2 applied now
var _alpha: Dictionary = {} ## part -> alpha applied now
var _cache: Dictionary = {} ## part -> node
var _tint_wait: float = 0.0


func setup(p_hud: CanvasLayer, p_player: Node2D) -> void:
	hud = p_hud
	player = p_player
	data = DataRegistry.table(DATA)
	parts = data.get("parts", {}) as Dictionary
	for ctx: String in (data.get("contexts", {}) as Dictionary):
		strength[ctx] = 0.0
		active[ctx] = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10 ## after the parts have updated their sizes this frame


## Real input or cursor movement keeps the HUD awake.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative != Vector2.ZERO:
			_idle_time = 0.0
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_idle_time = 0.0
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.25:
		_idle_time = 0.0


func wake() -> void:
	_idle_time = 0.0


## Tests: hold a context on (true), off (false) or give it back to the game (remove with `release`).
func force(ctx: String, on: bool) -> void:
	_forced[ctx] = on


func release(ctx: String = "") -> void:
	if ctx == "":
		_forced.clear()
	else:
		_forced.erase(ctx)


## Settle every fade at once (tests, after forcing).
func snap() -> void:
	for ctx: String in strength:
		strength[ctx] = 1.0 if bool(active.get(ctx, false)) else 0.0
	for name: String in parts:
		_lift[name] = _lift_target(name)


func layer_of(key: String, fallback: int) -> int:
	return int((data.get("layers", {}) as Dictionary).get(key, fallback))


func node_of(part: String) -> CanvasItem:
	var cached: Variant = _cache.get(part)
	if cached != null and is_instance_valid(cached):
		return cached as CanvasItem
	var found: CanvasItem = hud.get_node_or_null(part) as CanvasItem if hud != null else null
	_cache[part] = found
	return found


## Parts a story world holds back until their flag is set (`hud.gd` grows them in when it is).
func locked_parts() -> Array[String]:
	var out: Array[String] = []
	for name: String in parts:
		if String((parts[name] as Dictionary).get("unlock", "")) != "":
			out.append(name)
	return out


func unlock_flag(part: String) -> String:
	return String((parts.get(part, {}) as Dictionary).get("unlock", ""))


## Where the part draws now, in screen px (its box moved by fold and stack). A stacking part that reports its height
## takes only that much room above its (lifted) bottom.
func rect_of(part: String) -> Rect2:
	var spec: Dictionary = parts.get(part, {}) as Dictionary
	var box: Array = spec.get("box", [0, 0, 0, 0]) as Array
	var shift: Vector2 = _shift.get(part, Vector2.ZERO) as Vector2
	var rect: Rect2 = Rect2(float(box[0]) + shift.x, float(box[1]) + shift.y, float(box[2]), float(box[3]))
	if _stacks(part):
		var h: float = _height_of(part)
		if h > 0.0 and h < rect.size.y:
			rect = Rect2(rect.position.x, rect.end.y - h, rect.size.x, h)
	return rect


func alpha_of(part: String) -> float:
	return float(_alpha.get(part, 1.0))


## The part is on screen (visible, not faded away, something to show).
func shows(part: String) -> bool:
	var node: CanvasItem = node_of(part)
	if node == null or not node.is_visible_in_tree():
		return false
	if alpha_of(part) < 0.05:
		return false
	if node.has_method("hud_height") and _stacks(part):
		return float(node.call("hud_height")) > 0.0
	if node.has_method("hud_busy"):
		return bool(node.call("hud_busy"))
	return true


func attach_group(part: String) -> String:
	return String((parts.get(part, {}) as Dictionary).get("attach", ""))


func is_on(ctx: String) -> bool:
	return bool(active.get(ctx, false))


func _process(delta: float) -> void:
	if hud == null:
		return
	_contexts(delta)
	_tint_wait -= delta
	if _tint_wait <= 0.0: ## the zone tint of the bark (ZoneMood eases on its own; four looks a second are enough)
		_tint_wait = 0.25
		VineStyle.follow_mood(bool(GameSettings.get_value("hud_tint")))
	var specs: Dictionary = data.get("contexts", {}) as Dictionary
	for ctx: String in strength:
		var spec: Dictionary = specs.get(ctx, {}) as Dictionary
		var on: bool = bool(active[ctx])
		var seconds: float = float(spec.get("fade_out" if on else "fade_in", 0.3))
		strength[ctx] = move_toward(float(strength[ctx]), 1.0 if on else 0.0, delta / maxf(seconds, 0.01))
	var boss: Node = node_of("BossBar")
	if boss != null and boss.has_method("set_covered"):
		boss.call("set_covered", covered)
	for name: String in parts:
		_apply_alpha(name)
	_apply_layout(delta)


# --- contexts -------------------------------------------------------------------------------------------------------

func _contexts(delta: float) -> void:
	covered = _menu_open()
	var boss: bool = _boss_fight()
	var fishing: bool = _fishing()
	var moving: bool = false
	if player != null and is_instance_valid(player):
		moving = _last_pos != Vector2.INF and player.global_position.distance_squared_to(_last_pos) > 0.0001
		_last_pos = player.global_position
	var intro: bool = bool(hud.get("_intro_active"))
	var holds: bool = covered or intro or InputManager.ui_blocking or InputManager.menu_open or boss or moving or fishing
	_idle_time = 0.0 if holds else _idle_time + delta
	_combat_tick -= delta
	if _combat_tick <= 0.0:
		_combat_tick = COMBAT_TICK
		_combat = _in_combat()
	var idle_after: float = float((data.get("idle", {}) as Dictionary).get("seconds", 10.0))
	var live: Dictionary = {
		"idle": _idle_time >= idle_after,
		"vista": bool(hud.get("vista_hide")) and not covered and not InputManager.menu_open,
		"boss": boss,
		"menu": covered,
		"dialogue": _dialogue(),
		"cutscene": intro or _story_locked(),
		"combat": _combat,
		"build": InputManager.build_open,
		"fish": fishing,
		"swim": player != null and int(player.get("swim")) > 0,
		"notice": _big_notice(),
		"town": _in_town_light(),
	}
	for ctx: String in active:
		active[ctx] = bool(_forced[ctx]) if _forced.has(ctx) else bool(live.get(ctx, false))


func _menu_open() -> bool:
	for name: String in ["GameMenu", "InventoryWindow", "MapWindow", "QuestJournal", "SkillTreeWindow", "ProgressWindow", "DungeonWindow", "DungeonResultWindow", "PauseMenu"]:
		var node: CanvasItem = node_of(name)
		if node != null and node.visible:
			return true
	return false


func _boss_fight() -> bool:
	var boss: BossBar = node_of("BossBar") as BossBar
	if boss != null and boss.is_fighting():
		return true
	return get_tree().root.get_node_or_null("BossIntroLayer") != null


func _fishing() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var fishing: FishingComponent = player.get("fishing") as FishingComponent
	return fishing != null and fishing.state != FishingComponent.S.IDLE


func _dialogue() -> bool:
	var box: Node = node_of("DialogueBox")
	return box != null and box.has_method("is_active") and bool(box.call("is_active"))


func _story_locked() -> bool:
	return player != null and is_instance_valid(player) and (bool(player.get("story_lock")) or player.get("intro") != null)


func _big_notice() -> bool:
	var notices: Node = hud.get_node_or_null("Notices")
	return notices != null and notices.has_method("big_showing") and bool(notices.call("big_showing"))


func _in_town_light() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
	return town != null and town.founded and town.light_depth(player.global_position) > 0.0


## A shadow creature close by and alive (wildlife does not count).
func _in_combat() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	for node: Node in get_tree().get_nodes_in_group("predators"):
		if node.get("enemy_id") == null or not (node is Node2D):
			continue
		if (node as Node2D).global_position.distance_to(player.global_position) > COMBAT_RANGE:
			continue
		var health: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current > 0.0:
			return true
	return false


# --- alpha ----------------------------------------------------------------------------------------------------------

func _apply_alpha(name: String) -> void:
	var node: CanvasItem = node_of(name)
	if node == null:
		return
	var spec: Dictionary = parts[name] as Dictionary
	var target: float = 1.0
	for ctx: Variant in spec.get("hide", []) as Array:
		target *= 1.0 - float(strength.get(String(ctx), 0.0))
	var dims: Dictionary = spec.get("dim", {}) as Dictionary
	for ctx: String in dims:
		target *= 1.0 - float(strength.get(ctx, 0.0)) * (1.0 - float(dims[ctx]))
	if absf(float(_alpha.get(name, -1.0)) - target) > 0.0005:
		_alpha[name] = target
		node.modulate.a = target


# --- layout ---------------------------------------------------------------------------------------------------------

func _stacks(name: String) -> bool:
	return bool((parts.get(name, {}) as Dictionary).get("stack", false))


func _height_of(name: String) -> float:
	var node: CanvasItem = node_of(name)
	if node == null or not node.is_visible_in_tree() or not node.has_method("hud_height"):
		return 0.0
	return float(node.call("hud_height"))


## How far a stacked part must rise so it clears every active part below it in its slot.
func _lift_target(name: String) -> float:
	var spec: Dictionary = parts.get(name, {}) as Dictionary
	if not bool(spec.get("stack", false)):
		return 0.0
	var slot: String = String(spec.get("slot", ""))
	var slot_spec: Dictionary = (data.get("slots", {}) as Dictionary).get(slot, {}) as Dictionary
	var gap: float = float(slot_spec.get("gap", 2.0))
	var cursor: float = float(slot_spec.get("floor", 360.0)) + gap
	var members: Array[String] = []
	for other: String in parts:
		var o: Dictionary = parts[other] as Dictionary
		if String(o.get("slot", "")) == slot and bool(o.get("stack", false)):
			members.append(other)
	members.sort_custom(func(a: String, b: String) -> bool: return int((parts[a] as Dictionary).get("order", 0)) < int((parts[b] as Dictionary).get("order", 0)))
	for other: String in members:
		var box: Array = (parts[other] as Dictionary).get("box", [0, 0, 0, 0]) as Array
		var natural_bottom: float = float(box[1]) + float(box[3])
		var bottom: float = minf(natural_bottom, cursor - gap)
		if other == name:
			return natural_bottom - bottom
		var h: float = _height_of(other)
		if h > 0.0:
			cursor = bottom - h
	return 0.0


func _fold_shift(name: String) -> Vector2:
	var bar: Hotbar = node_of("Hotbar") as Hotbar
	if bar == null:
		return Vector2.ZERO
	match String((parts[name] as Dictionary).get("fold", "")):
		"self", "drop":
			return Vector2(0.0, bar.drop)
		"in":
			return Vector2(bar.inset, bar.drop)
		"out":
			return Vector2(-bar.inset, bar.drop)
		"crystal":
			return Vector2(-bar.inset, bar.drop + bar.sink)
	return Vector2.ZERO


func _apply_layout(delta: float) -> void:
	var bar: Hotbar = node_of("Hotbar") as Hotbar
	for name: String in parts:
		var spec: Dictionary = parts[name] as Dictionary
		var lift: float = float(_lift.get(name, 0.0))
		if bool(spec.get("stack", false)):
			lift = move_toward(lift, _lift_target(name), LIFT_SPEED * delta)
			_lift[name] = lift
		var shift: Vector2 = _fold_shift(name) + Vector2(0.0, -lift)
		if shift == (_shift.get(name, Vector2.INF) as Vector2):
			continue
		_shift[name] = shift
		var node: Control = node_of(name) as Control
		if node == null:
			continue
		if "hud_lift" in node: ## it draws relative to something else: it lifts itself
			node.set("hud_lift", lift)
			shift.y += lift
		if shift == Vector2.ZERO and not _base.has(name):
			continue
		if not _base.has(name):
			_base[name] = Rect2(node.offset_left, node.offset_top, node.offset_right, node.offset_bottom)
		var base: Rect2 = _base[name]
		node.offset_left = base.position.x + shift.x
		node.offset_right = base.size.x + shift.x
		node.offset_top = base.position.y + shift.y
		node.offset_bottom = base.size.y + shift.y
	if bar != null:
		var crystal: CanvasItem = node_of("BlinkIcon")
		if crystal != null:
			crystal.self_modulate.a = bar.shown
