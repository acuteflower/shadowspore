class_name NightWatchers
extends Node2D
## Eyes in the bushes at night: now and then a pair of dim eyes opens in a bush at the edge of what she can see, watches her (the pupils lean towards her),
## blinks, and is gone as soon as she comes close, a light is near or the day breaks. Nothing is there: they are cosmetic and local on every peer (no node
## in the network, no collision, no damage, no sound), only a feeling that the dark is not empty. Magenta like the shadow creatures, but smaller, dimmer and
## never moving; in the Hexenwald they are witch green. Unlit, so they shine against the tint. Tuning: the constants below.

const MAX_PAIRS: int = 4 ## at once on one screen
const SPAWN_EVERY: Vector2 = Vector2(2.5, 6.0) ## seconds between two tries (random in this range)
const MIN_DISTANCE: float = 120.0 ## px from the middle of the screen: they sit at the edge of her view, never right beside her
const MAX_DISTANCE: float = 330.0
const STARTLE_DISTANCE: float = 62.0 ## she comes this close: the pair closes and is gone
const LIFE: Vector2 = Vector2(4.0, 9.0)
const FADE_IN: float = 1.4
const FADE_OUT: float = 0.45
const NIGHT_MIN: float = 0.85 ## how dark it has to be (night_amount) before the first pair opens
const LIGHT_MARGIN: float = 28.0 ## px outside the town's light they keep away
const HOSTS: Array[String] = ["bush", "ember_bush", "berry_bush", "hex_shrub", "witch_broom", "thorn_hedge"] ## what they hide in
const MAGENTA: Color = Color(0.88, 0.30, 0.92)
const WITCH_GREEN: Color = Color(0.66, 1.0, 0.42)


class Pair:
	var host: Node2D
	var age: float = 0.0
	var life: float = 6.0
	var out: float = 0.0 ## > 0 while closing: seconds since it began
	var gap: float = 3.5 ## half distance between the eyes
	var color: Color = MAGENTA
	var phase: float = 0.0 ## blink and pulse offset
	var single: bool = false ## the odd one with only one eye


var _pairs: Array[Pair] = []
var _time: float = 0.0
var _next: float = 3.0
var _town: TownManager


func _ready() -> void:
	name = "NightWatchers"
	z_index = 3
	material = Unlit.material()
	add_to_group("night_watchers")


func _process(delta: float) -> void:
	var interiors: Interiors = get_parent().get_node_or_null("Interiors") as Interiors
	var mines: MineManager = get_parent().get_node_or_null("Mines") as MineManager
	var outside: bool = (interiors == null or not interiors.local_inside()) and (mines == null or not mines.local_inside())
	var camera: Camera2D = get_viewport().get_camera_2d()
	var night: float = _night_here(camera)
	if not outside or camera == null:
		_pairs.clear()
		visible = false
		return
	visible = true
	_time += delta
	var middle: Vector2 = camera.get_screen_center_position()
	_step_pairs(delta, middle, night)
	_next -= delta
	if _next <= 0.0:
		_next = randf_range(SPAWN_EVERY.x, SPAWN_EVERY.y)
		if night >= NIGHT_MIN and _pairs.size() < MAX_PAIRS:
			_try_open(middle)
	queue_redraw()


## Opens as many pairs as fit right now (previews and tests; ordinary play lets them come one by one).
func fill_now() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	for _i: int in MAX_PAIRS * 12:
		if _pairs.size() >= MAX_PAIRS:
			break
		_try_open(camera.get_screen_center_position())


## 0 by day .. 1 at night (the Hexenwald is always night).
func _night_here(camera: Camera2D) -> float:
	if camera == null:
		return 0.0
	return maxf(TimeManager.night_amount(), BiomeBlend.amount_at(camera.get_screen_center_position()))


func _step_pairs(delta: float, middle: Vector2, night: float) -> void:
	for i: int in range(_pairs.size() - 1, -1, -1):
		var pair: Pair = _pairs[i]
		if not is_instance_valid(pair.host) or night < 0.5:
			_pairs.remove_at(i) ## felled, unloaded or the sun is coming: gone
			continue
		pair.age += delta
		if pair.out > 0.0:
			pair.out += delta
			if pair.out >= FADE_OUT:
				_pairs.remove_at(i)
			continue
		var at: Vector2 = pair.host.global_position
		if pair.age >= pair.life or at.distance_to(_nearest_player(middle, at)) < STARTLE_DISTANCE or _lit(at):
			pair.out = 0.001
		elif absf(at.x - middle.x) > 480.0 or absf(at.y - middle.y) > 300.0: ## far off screen: nobody sees it
			_pairs.remove_at(i)


func _try_open(middle: Vector2) -> void:
	var candidates: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("night_lights"):
		var prop: WorldProp = node as WorldProp
		if prop == null or not HOSTS.has(prop.kind):
			continue
		var distance: float = prop.global_position.distance_to(middle)
		if distance < MIN_DISTANCE or distance > MAX_DISTANCE or _lit(prop.global_position) or _taken(prop):
			continue
		candidates.append(prop)
	if candidates.is_empty():
		return
	var host: Node2D = candidates[randi() % candidates.size()]
	for pair: Pair in _pairs: ## not two pairs next to each other
		if is_instance_valid(pair.host) and pair.host.global_position.distance_to(host.global_position) < 70.0:
			return
	var pair: Pair = Pair.new()
	pair.host = host
	pair.life = randf_range(LIFE.x, LIFE.y)
	pair.gap = randf_range(2.5, 4.5)
	pair.phase = randf() * 10.0
	pair.single = randf() < 0.08
	pair.color = WITCH_GREEN if BiomeBlend.amount_at(host.global_position) > 0.5 else MAGENTA
	_pairs.append(pair)


func _taken(prop: Node2D) -> bool:
	for pair: Pair in _pairs:
		if pair.host == prop:
			return true
	return false


## True inside (or just outside) the town's light: nothing watches from there.
func _lit(at: Vector2) -> bool:
	if not is_instance_valid(_town):
		_town = get_tree().get_first_node_in_group("town") as TownManager
	return _town != null and _town.light_depth(at) > -LIGHT_MARGIN


func _nearest_player(middle: Vector2, from: Vector2) -> Vector2:
	var best: Vector2 = middle
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Node2D = node as Node2D
		if player != null and player.global_position.distance_to(from) < best_distance:
			best_distance = player.global_position.distance_to(from)
			best = player.global_position
	return best


func _draw() -> void:
	var middle: Vector2 = get_viewport().get_camera_2d().get_screen_center_position() if get_viewport().get_camera_2d() != null else Vector2.ZERO
	for pair: Pair in _pairs:
		if not is_instance_valid(pair.host):
			continue
		var fade: float = clampf(pair.age / FADE_IN, 0.0, 1.0)
		if pair.out > 0.0:
			fade *= 1.0 - clampf(pair.out / FADE_OUT, 0.0, 1.0)
		if fade <= 0.01:
			continue
		var anchor: Vector2 = (pair.host.global_position + Vector2(0.0, -9.0)).round()
		var look: Vector2 = (middle - anchor).normalized() ## the pupils lean towards her
		var blink: bool = fmod(_time * 0.7 + pair.phase, 3.4) > 3.2 or pair.out > 0.0 ## closing eyes squint shut first
		var pulse: float = 0.72 + 0.28 * sin(_time * 2.6 + pair.phase)
		var sides: Array[float] = [-1.0, 1.0]
		if pair.single:
			sides = [1.0]
		for side: float in sides:
			var eye: Vector2 = anchor + Vector2(side * pair.gap, 0.0)
			draw_circle(eye, 7.0, Color(pair.color, 0.06 * fade * pulse))
			draw_circle(eye, 4.0, Color(pair.color, 0.13 * fade * pulse)) ## a faint wash on the leaves round it
			var height: float = 1.0 if blink else 2.0
			draw_rect(Rect2(eye + Vector2(-1.0, -height * 0.5).round(), Vector2(3.0, height)), Color(pair.color, fade * (0.8 + 0.2 * pulse)))
			if not blink:
				var pupil: Vector2 = eye + Vector2(round(look.x), 0.0)
				draw_rect(Rect2(pupil + Vector2(0.0, -1.0), Vector2.ONE), Color(1.0, 0.92, 1.0, fade)) ## the bright speck that follows her
