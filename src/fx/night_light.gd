class_name NightLight
extends PointLight2D
## A light that only shines at night. The DayNight node tells every NightLight how dark it is
## (`set_night`), so flowers and eyes glow up as the evening comes and fade at dawn. The light is a
## flat, slightly irregular pool on the ground that breathes slowly, each one out of step.

@export var radius: int = 26 ## px, horizontal radius
@export var squash: float = 0.6 ## flat in the 3/4 view
@export var base_energy: float = 0.9
@export var glow_color: Color = Color("b99bff")
@export var pulse: float = 0.14 ## how much the light breathes (0 = steady)

var _night: float = 0.0
var budgeted: bool = true: ## false: one of the many small lights that are not among the nearest ones (see `budget`)
	set(value):
		budgeted = value
		_update_active()
var _phase: float = 0.0
var _notifier: VisibleOnScreenNotifier2D
var _on_screen: bool = true


func _ready() -> void:
	var variant: int = absi(int(position.x * 7.0 + position.y * 13.0)) % 3
	texture = LightTexture.get_texture(radius * 2, squash, variant)
	color = glow_color
	_phase = fposmod(position.x * 0.37 + position.y * 0.71, TAU)
	add_to_group("night_lights")
	_notifier = VisibleOnScreenNotifier2D.new()
	var reach: float = float(radius) + 16.0
	_notifier.rect = Rect2(-reach, -reach * squash, reach * 2.0, reach * 2.0 * squash)
	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_notifier)
	set_night(TimeManager.night_amount())


func _on_screen_entered() -> void:
	_on_screen = true
	_update_active()


func _on_screen_exited() -> void:
	_on_screen = false
	_update_active()


func _update_active() -> void:
	var active: bool = _night > 0.01 and _on_screen and budgeted
	enabled = active
	set_process(active)
	if not active:
		energy = 0.0


func set_night(amount: float) -> void:
	amount = MineManager.night_at(self, amount)
	_night = amount
	_update_active()


func _process(_delta: float) -> void:
	var breath: float = 1.0 - pulse * 0.5 + pulse * 0.5 * sin(Time.get_ticks_msec() * 0.0013 + _phase)
	energy = base_energy * _night * breath


const SMALL_RADIUS: int = 34 ## lights this small (glowing plants, moonbells, shrooms) share a budget
const LIGHT_LIMIT: int = 16 ## the renderer's limit per picture
const SMALL_MIN: int = 4 ## small lights that always shine, even in a crowd of big ones


## The renderer lights one picture with at most 16 lights, and a ground tile layer is one picture: with 20 small plant lights about, the big ones (a lamp post, the forge)
## went missing there, with a hard edge where the next layer begins. So the big ones always shine and the small ones nearest to `center` fill up what is left of the limit (`LIGHT_LIMIT` minus the big lights in view, at least `SMALL_MIN`).
static func budget(tree: SceneTree, center: Vector2) -> void:
	var small: Array[NightLight] = []
	var big: int = 0
	for node: Node in tree.get_nodes_in_group("night_lights"):
		var light: NightLight = node as NightLight
		if light != null and light._on_screen and light._night > 0.01:
			if light.radius <= SMALL_RADIUS:
				small.append(light)
			else:
				big += 1
	small.sort_custom(func(a: NightLight, b: NightLight) -> bool: return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	var room: int = maxi(SMALL_MIN, LIGHT_LIMIT - big)
	for i: int in small.size():
		var allowed: bool = i < room
		if small[i].budgeted != allowed:
			small[i].budgeted = allowed
