class_name Bush
extends WorldProp
## A walk-through bush of the meadow, plain or with dusk berries. You wade through it a little
## slower and it rustles; berries are picked with E; the sickle plucks it for fibers, leaves and
## sticks (3 hits leave bare twigs); everything grows back by the days (see `WorldLevel._grow_things`).

const IDLE_SWAY: float = 0.02 ## skew of the sprite in the wind (plants.json "sway" overrides: grass moves more)
const DEFAULT_PICK_BURST: Array[Color] = [Color("8a5cf0"), Color("d9c8ff"), Color("78f4e6")]
const DEFAULT_LEAF_COLORS: Array[Color] = [Color("55985f"), Color("7cb96d"), Color("3e7d56")]
const BERRY_BUSH_LEAF_COLORS: Array[Color] = [Color("52998f"), Color("7cc2a8"), Color("2a5c5e")]
const REGROW_BURST: Array[Color] = [Color("d9c8ff"), Color("a6f0d0")]

var _inside: Array[Player] = []
var _idle_phase: float = 0.0
var _sway_rate: float = 0.0
var _on_screen: bool = true
var _notifier: VisibleOnScreenNotifier2D

@onready var _foliage: Area2D = $Foliage

func _setup_prop() -> void:
	_idle_phase = fposmod(position.x * 0.37 + position.y * 0.11, TAU)
	_sway_rate = _wind_exposure * float(_spec.get("sway", IDLE_SWAY)) * 1.5
	_shape($Foliage/Shape, _radius * 0.8, Vector2(0, -_radius * 0.35))
	_foliage.body_entered.connect(_on_enter)
	_foliage.body_exited.connect(_on_exit)
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-_radius - 8.0, -_height - 8.0, (_radius + 8.0) * 2.0, _height + 16.0)
	_notifier.screen_entered.connect(func() -> void: _on_screen = true)
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(_notifier)


func _process(_delta: float) -> void:
	if not _on_screen:
		return
	if _tween == null or not _tween.is_running(): ## a rustle has the sprite for a moment, else it sways in the wind
		_sprite.skew = WorldWind.sample(global_position).x * _sway_rate


func _exit_tree() -> void:
	for player: Player in _inside:
		if is_instance_valid(player):
			player.clear_slow(self)


func apply_state(new_state: Dictionary, fx: String) -> void:
	state = new_state
	var stripped: bool = is_depleted()
	var columns: int = int(_spec.columns)
	if stripped:
		_sprite.texture = load(String(_spec.stripped)) as Texture2D
		_sprite.hframes = columns
		_sprite.vframes = 1
		_sprite.frame = variant
	else:
		_sprite.texture = load(String(_spec.texture)) as Texture2D
		_sprite.hframes = columns
		_sprite.vframes = int(_spec.rows)
		_sprite.frame = variant + (columns if bool(state.get("p", 0)) and int(_spec.rows) > 1 else 0)
	_sync_glow(not stripped)
	var light: Dictionary = _spec.get("light", {})
	if not light.is_empty():
		_set_light(not stripped and not bool(state.get("p", 0)), Color(String(light.color)), int(light.radius), float(light.energy)) ## ripe berries glow
	_hurtbox.set_deferred("monitorable", not stripped)
	_set_zone(not stripped)
	match fx:
		"rustle":
			_rustle(randf_range(-1.0, 1.0))
		"hit":
			_rustle(randf_range(-1.0, 1.0))
			_burst(5, _leaf_colors())
		"strip":
			_rustle(randf_range(-1.0, 1.0))
			_burst(14, _leaf_colors())
		"pick":
			_rustle(randf_range(-1.0, 1.0))
			_burst(7, _pick_colors())
		"regrow":
			_burst(6, REGROW_BURST, 0.0)
	if _prompt_node != null:
		set_focused(_prompt_node.visible)


func prompt() -> String:
	if _spec.has("pickup") and not is_depleted() and not bool(state.get("p", 0)):
		return String((_spec.pickup as Dictionary).prompt)
	return ""


## She faces the bush and picks (about a second); the berries come at the grab, not at the key press.
func interact(player: Player) -> void:
	var toward: Vector2 = global_position + Vector2(0, -_radius * 0.45) - player.global_position
	player.begin_pick(toward.normalized(), func() -> void: level.request_pick(cell))


## Walking through: slower on the walker's own machine, a rustle everywhere.
func _on_enter(body: Node2D) -> void:
	var player: Player = body as Player
	if player == null:
		return
	_inside.append(player)
	_rustle(signf(player.velocity.x) if absf(player.velocity.x) > 5.0 else randf_range(-1.0, 1.0))
	if player.is_multiplayer_authority():
		player.set_slow(self, float(_spec.slow))


func _on_exit(body: Node2D) -> void:
	var player: Player = body as Player
	if player != null:
		_inside.erase(player)
		player.clear_slow(self)


func _set_zone(on: bool) -> void:
	_foliage.set_deferred("monitoring", on)
	if not on:
		for player: Player in _inside:
			player.clear_slow(self)
		_inside.clear()


func _leaf_colors() -> Array[Color]:
	if _spec.has("leaf_colors"):
		return _colors(_spec.leaf_colors as Array)
	if kind == "berry_bush":
		return BERRY_BUSH_LEAF_COLORS
	return DEFAULT_LEAF_COLORS


func _pick_colors() -> Array[Color]:
	var burst: Array = (_spec.get("pickup", {}) as Dictionary).get("burst", [])
	return _colors(burst) if not burst.is_empty() else DEFAULT_PICK_BURST


func _colors(hexes: Array) -> Array[Color]:
	var colors: Array[Color] = []
	for hex: Variant in hexes:
		colors.append(Color(String(hex)))
	return colors
