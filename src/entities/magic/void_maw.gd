class_name VoidMaw
extends SpellZone
## Leerenschlund (docs/magie_konzept.md, school LEERE): the void always takes its price (SpellComponent already took `price` of the caster's
## health). At the aimed point the ground tears open into the void (magic_void_maw.gdshader): a black hole with a ragged lip, the ground round
## it darkening, spiral arms of violet light wound inwards. For `seconds` it pulls every shadow creature within the circle towards its middle
## (host: `pull` px/s, harder near the hole, through move_and_collide so walls hold; creatures of 300 health and more are too heavy to move),
## thin strands of void reach out to each of them. Then it snaps shut: everything inside takes `damage` (less at the rim), the hole closes to a
## white seam and a ring breaks out, and for every creature it bit `refund` of the caster's maximum health flows back to her as a stream of
## violet light (up to her full health, never beyond). Tier III (SATTER SCHLUND): `fed` or more bitten = the crystal charges the rest of its time twice as fast. Tier V (LEERER
## STERN): a creature below `devour` of its health is swallowed whole and gives back twice. Gem Hunger V (ZWEITER BISS): half a second
## later it snaps once more with `bite2` of the bite and the life back.

const RIM: Color = Color("d27bff")
const HOT: Color = Color("ff4fd8")
const WHITE: Color = Color("f6e8ff")
const FLESH: Color = Color("261a4a")
const HEAVY: float = 300.0 ## creatures with this much health or more do not move in the pull
const PULL_REACH: float = 1.15 ## the pull reaches a little beyond the drawn circle

var _tear: Node2D
var _strands: Node2D
var _light: NightLight
var _snapped: bool = false
var _feed: float = 0.0
var _caught: Array[Vector2] = [] ## where the pulled creatures are (own frame), refreshed every peer for the strands
var _catch_clock: float = 0.0
var _hum: float = 0.0
var _second: bool = false ## Hunger V: the second bite has come


func _build() -> void:
	var reach: float = radius * 1.35 + 8.0
	_tear = shader_quad("Tear", "res://assets/shaders/magic_void_maw.gdshader", Rect2(-reach, -reach * SQUASH - 4.0, reach * 2.0, reach * SQUASH * 2.0 + 8.0), -4)
	set_shader(_tear, "radius", radius)
	set_shader(_tear, "squash", SQUASH)
	set_shader(_tear, "seed", _rng.randf() * 100.0)
	_strands = Node2D.new()
	_strands.name = "Strands"
	_strands.z_index = 2
	_strands.material = add_material()
	_strands.draw.connect(_draw_strands)
	add_child(_strands)
	_light = NightLight.new()
	_light.radius = roundi(radius * 1.2)
	_light.squash = SQUASH
	_light.glow_color = Color("b45cff")
	_light.base_energy = 0.8
	_light.pulse = 0.2
	add_child(_light)
	SpellZone.sound(self, "maw_open", global_position, 0.0)
	_shake(2.0)


func _ending() -> float:
	return 0.9 + (0.5 if float(params.get("bite2", 0.0)) > 0.0 else 0.0)


func _update(delta: float) -> void:
	var grow: float = 1.0 - pow(1.0 - clampf(_age / 0.4, 0.0, 1.0), 3.0)
	var snap: float = clampf((_age - seconds) / 0.55, 0.0, 1.0)
	if _age >= seconds and not _snapped:
		_snapped = true
		_snap(1.0)
	if _age >= seconds + 0.5 and _snapped and not _second and float(params["bite2"]) > 0.0: ## Hunger V: it snaps a second time
		_second = true
		_snap(float(params["bite2"]))
	_feed = move_toward(_feed, 0.0, delta * 2.0)
	var fade: float = clampf((_age - seconds - 0.5) / 0.4, 0.0, 1.0)
	set_shader(_tear, "age", _age)
	set_shader(_tear, "grow", grow)
	set_shader(_tear, "snap", snap)
	set_shader(_tear, "feed", _feed)
	set_shader(_tear, "fade", fade)
	if _light != null:
		_light.base_energy = (0.8 + 0.6 * _feed) * (1.0 - fade) * grow
	_catch_clock -= delta
	if _catch_clock <= 0.0 and not _snapped:
		_catch_clock = 0.1
		_caught.clear()
		for box: HurtboxComponent in _in_reach():
			_caught.append(box.global_position - global_position)
	if _snapped:
		_caught.clear()
	if not _snapped and _rng.randf() < delta * 30.0 * grow: ## flecks of the world sucked in along the spiral
		var a: float = _rng.randf() * TAU
		var from: Vector2 = Vector2(cos(a), sin(a) * SQUASH) * radius * _rng.randf_range(0.7, 1.05)
		var inward: Vector2 = -from.normalized() * _rng.randf_range(30.0, 50.0) + Vector2(-sin(a), cos(a) * SQUASH) * 30.0
		mote(from, inward, _rng.randf_range(0.5, 0.9), [RIM, FLESH.lightened(0.3), HOT][_rng.randi() % 3], 1, 0.0, 0.2)
	_hum -= delta
	if not _snapped and _hum <= 0.0 and not _caught.is_empty():
		_hum = 0.6
		SpellZone.sound(self, "maw_pull", global_position, -10.0)
	_strands.queue_redraw()


## Every living shadow creature within the pull (hurtboxes, one per creature).
func _in_reach() -> Array[HurtboxComponent]:
	var found: Array[HurtboxComponent] = []
	for box: HurtboxComponent in SpellComponent.volley_targets(self, global_position, global_position, radius * 1.4):
		var rel: Vector2 = SpellZone.feet_of(box) - global_position
		if Vector2(rel.x, rel.y / SQUASH).length() <= radius * PULL_REACH:
			found.append(box)
	return found


## Host, every `tick`: the pull.
func _host_tick(tick: float) -> void:
	if _snapped or _age < 0.25:
		return
	for box: HurtboxComponent in _in_reach():
		if box.health.max_health >= HEAVY:
			continue
		var body: CharacterBody2D = box.get_parent() as CharacterBody2D
		if body == null:
			continue
		var rel: Vector2 = body.global_position - global_position
		var dist: float = Vector2(rel.x, rel.y / SQUASH).length()
		if dist < 3.0:
			continue
		var near: float = 1.0 - clampf(dist / radius, 0.0, 1.0)
		var step: Vector2 = -rel.normalized() * float(params["pull"]) * (0.55 + 0.9 * near) * tick
		step += rel.orthogonal().normalized() * float(params["pull"]) * 0.25 * tick ## a little round, like water down a drain
		body.move_and_collide(step.limit_length(dist - 2.0))


## Every peer: the bite (`share` of the full bite: 1, or Hunger's second bite). The host deals it and pays back.
func _snap(share: float) -> void:
	SpellZone.sound(self, "maw_snap", global_position, 2.0 if share >= 1.0 else -2.0)
	_shake(5.0 * share)
	for i: int in roundi(34.0 * share): ## the jaws slam: shards of void and light thrown out
		var a: float = _rng.randf() * TAU
		mote(Vector2(cos(a), sin(a) * SQUASH) * radius * 0.2, Vector2(cos(a), sin(a) * SQUASH) * _rng.randf_range(60.0, 140.0) + Vector2(0.0, -30.0), _rng.randf_range(0.3, 0.7), [WHITE, RIM, HOT, FLESH][i % 4], 2 if i % 5 == 0 else 1, -40.0, 3.0)
	if share < 1.0: ## Hunger's second bite: the closed seam tears open once more, a ring of white and magenta
		_feed = 1.0
		for i: int in 36:
			var a: float = TAU * float(i) / 36.0
			mote(Vector2(cos(a), sin(a) * SQUASH) * radius * 0.25, Vector2(cos(a), sin(a) * SQUASH) * radius * 2.6, 0.4, WHITE if i % 3 == 0 else HOT, 2 if i % 6 == 0 else 1, 0.0, 2.0)
	var bitten: Array[HurtboxComponent] = []
	for box: HurtboxComponent in _in_reach():
		bitten.append(box)
	var who: Player = caster_node()
	if not bitten.is_empty():
		_feed = 1.0
		SpellZone.sound(self, "maw_feed", global_position, -2.0)
		if who != null: ## the stream of life back to her
			var to: Vector2 = who.global_position + Vector2(0.0, -16.0) - global_position
			for j: int in 8 * bitten.size():
				var from: Vector2 = Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-4.0, 4.0))
				var life: float = _rng.randf_range(0.45, 0.7)
				mote(from, (to - from) / life + Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(-30.0, 0.0)), life, HOT if j % 3 == 0 else RIM, 2 if j % 4 == 0 else 1, 0.0, 0.0)
	if not multiplayer.is_server():
		return
	var portions: float = 0.0
	for box: HurtboxComponent in bitten:
		if box.health == null or box.health.current <= 0.0:
			continue
		var rel: Vector2 = SpellZone.feet_of(box) - global_position
		var near: float = 1.0 - clampf(Vector2(rel.x, rel.y / SQUASH).length() / (radius * PULL_REACH), 0.0, 1.0)
		var bite: float = float(params["damage"]) * (0.6 + 0.4 * near) * share
		if float(params["devour"]) > 0.0 and box.health.current <= box.health.max_health * float(params["devour"]): ## LEERER STERN: swallowed whole
			bite = box.health.current + 1.0
			portions += 1.0
		box.take_hit(bite, global_position, 20.0, caster)
		portions += 1.0
	if who == null or portions <= 0.0:
		return
	var back: float = minf(who.health.max_health * float(params["refund"]) * portions * share, who.health.max_health - who.health.current)
	if back > 0.0: ## the void gives back what it took, never more than she can hold
		who.health.heal(back)
	if share >= 1.0 and int(params["fed"]) > 0 and bitten.size() >= int(params["fed"]) and who.spells != null:
		who.spells.fed_well(int(params.get("prong", 0)))


func _shake(amount: float) -> void:
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.global_position.distance_to(global_position) < 260.0:
			player.add_shake(amount * (1.0 - player.global_position.distance_to(global_position) / 260.0))


## Thin strands of the void from the hole to every creature it pulls, wavering, a magenta bead running inwards along each.
func _draw_strands() -> void:
	var grow: float = clampf(_age / 0.4, 0.0, 1.0)
	for target: Vector2 in _caught:
		var length: float = target.length()
		if length < 4.0:
			continue
		var steps: int = clampi(int(length / 3.0), 4, 40)
		var n: Vector2 = target.orthogonal() / length
		var bead: float = fposmod(_age * 1.6 + target.x * 0.013, 1.0)
		for i: int in steps:
			var f: float = float(i) / float(steps)
			var p: Vector2 = target * f + n * sin(f * 9.0 - _age * 12.0) * 2.0 * (1.0 - f) * f * 4.0
			var col: Color = Color(RIM, 0.45 * grow * (0.4 + 0.6 * f))
			if absf(f - (1.0 - bead)) < 0.06:
				col = Color(HOT, 0.9 * grow)
			_strands.draw_rect(Rect2(p.round(), Vector2.ONE), col)
