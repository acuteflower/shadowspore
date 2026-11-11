class_name EmberBurn
extends Node2D
## Glutschwarm's fire on a shadow creature (docs/magie_konzept.md, school GLUT): a child of the creature's body, made on every peer by the
## shard that hits it (EmberVolley) or by the fire that jumps to it (FUNKENSPRUNG). Every peer counts its time down and draws the flames;
## only the host's copy burns: a tick of `dps * TICK` every TICK seconds through `take_tick`, credited to the caster. A new hit while it burns
## refreshes the time and adds `extend` seconds. When the creature dies while burning and the burn may jump (`jump` px, tier III), the host
## finds the nearest other creature and tells everybody (SpellComponent._rpc_burn_jump), which lights it with what was left.
## Pixel flames in whole art pixels: tongues of stepped columns (deep red foot, orange belly, yellow tip, a white-hot heart while it is
## fresh), embers rising, a warm glow on the ground. Unshaded and additive, so it burns bright at night.

const TICK: float = 0.5
const DEEP: Color = Color("8a2a10")
const RED: Color = Color("d8461a")
const ORANGE: Color = Color("ff8a3c")
const YELLOW: Color = Color("ffd36a")
const WHITE: Color = Color("fff4d0")
const DRAW_STEP: float = 1.0 / 18.0

var dps: float = 0.0
var left: float = 0.0
var total: float = 0.0
var caster: int = 0
var jump: float = 0.0
var _box: HurtboxComponent
var _t: float = 0.0
var _tick: float = 0.0
var _draw_acc: float = 0.0
var _fresh: float = 1.0 ## 1 when it was just lit or refreshed: the flames flare white-hot
var _leap_from: Vector2 = Vector2.INF ## FUNKENSPRUNG: where the fire came from (world px), drawn as an arc for a moment
var _sparks: Array[Vector4] = [] ## x, y (own frame), life, speed
var _ended: bool = false
var _seed: float = 0.0
var _foot: Vector2 = Vector2(0.0, 2.0) ## where the fire stands on the body (own frame): the bottom of the hurtbox's shape
var _size: Vector2 = Vector2(12.0, 14.0) ## how wide and tall the body the fire climbs is


## Lights (or feeds) the fire on `body`. Every peer.
static func ignite(body: Node2D, burn_dps: float, seconds: float, from_caster: int, jump_px: float, extend: float = 0.0) -> EmberBurn:
	if body == null or not is_instance_valid(body) or seconds <= 0.0:
		return null
	var burn: EmberBurn = body.get_node_or_null("EmberBurn") as EmberBurn
	if burn != null and not burn._ended:
		burn.left = maxf(burn.left, seconds) + extend
		burn.total = maxf(burn.total, burn.left)
		burn.dps = maxf(burn.dps, burn_dps)
		burn.jump = maxf(burn.jump, jump_px)
		burn._fresh = 1.0
		return burn
	burn = EmberBurn.new()
	burn.name = "EmberBurn"
	burn.dps = burn_dps
	burn.left = seconds
	burn.total = seconds
	burn.caster = from_caster
	burn.jump = jump_px
	body.add_child(burn)
	return burn


## FUNKENSPRUNG on every peer: the fire arrives from `from` (the creature that died).
static func leap(body: Node2D, from: Vector2, burn_dps: float, seconds: float, from_caster: int, jump_px: float) -> void:
	var burn: EmberBurn = ignite(body, burn_dps, seconds, from_caster, jump_px)
	if burn != null:
		burn._leap_from = from
		SpellZone.sound(body, "ember_jump", body.global_position, -4.0)


func _ready() -> void:
	z_index = 2
	material = SpellZone.add_material()
	_seed = float(get_instance_id() % 997) * 0.37
	for child: Node in get_parent().get_children():
		if child is HurtboxComponent and not (child is HarvestHurtbox):
			_box = child as HurtboxComponent
			break
	_measure.call_deferred()


## The body the fire climbs: the hurtbox's collision shape, seen from here.
func _measure() -> void:
	if _box == null or not is_instance_valid(_box):
		return
	for child: Node in _box.get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var r: Rect2 = shape_node.shape.get_rect()
		var top_left: Vector2 = to_local(shape_node.to_global(r.position))
		var bottom_right: Vector2 = to_local(shape_node.to_global(r.end))
		_size = Vector2(clampf(absf(bottom_right.x - top_left.x), 8.0, 28.0), clampf(absf(bottom_right.y - top_left.y), 10.0, 30.0))
		_foot = Vector2((top_left.x + bottom_right.x) * 0.5, maxf(top_left.y, bottom_right.y) + 2.0).round()
		return


func _process(delta: float) -> void:
	_t += delta
	_fresh = move_toward(_fresh, 0.0, delta * 2.2)
	if not _ended:
		left -= delta
		if multiplayer.is_server() and _box != null and _box.health != null:
			if _box.health.current <= 0.0:
				_host_died()
			else:
				_tick += delta
				while _tick >= TICK and left > -TICK * 0.5:
					_tick -= TICK
					_box.health.take_tick(dps * TICK, caster)
		if left <= 0.0 or (_box != null and _box.health != null and _box.health.current <= 0.0):
			_ended = true
			left = 0.0
	_tick_sparks(delta)
	_draw_acc += delta
	if _draw_acc >= DRAW_STEP:
		_draw_acc = 0.0
		queue_redraw()
	if _ended and _sparks.is_empty() and _t > 0.3:
		queue_free()


## How strongly it burns (0 out .. 1), it dies down in the last 0.6 s.
func strength() -> float:
	if _ended:
		return 0.0
	return clampf(left / 0.6, 0.0, 1.0) * clampf(_t / 0.12, 0.0, 1.0)


## Host: the creature died in the fire. With FUNKENSPRUNG the fire leaps to the nearest other creature with what was left.
func _host_died() -> void:
	if _ended:
		return
	_ended = true
	if jump <= 0.0 or left < 0.4:
		return
	var here: Vector2 = SpellZone.feet_of(_box) if _box != null else global_position
	var nearest: HurtboxComponent = null
	for box: HurtboxComponent in SpellComponent.volley_targets(get_parent() as Node2D, here, here, jump):
		if box.get_parent() != get_parent():
			nearest = box
			break
	if nearest == null:
		return
	for player: Player in Player.all:
		if int(player.name) == caster and player.spells != null:
			player.spells._rpc_burn_jump.rpc(_body_point(), String(nearest.get_parent().get_path()), dps, left + 1.0, jump)
			return


## The middle of the creature's body (world px): where the hurtbox sits.
func _body_point() -> Vector2:
	return _box.global_position if _box != null else global_position + Vector2(0.0, -8.0)


func _tick_sparks(delta: float) -> void:
	var s: float = strength()
	if s > 0.0 and randf() < delta * 16.0 * s:
		var heart: Vector2 = _body_point() - global_position
		_sparks.append(Vector4(heart.x + randf_range(-6.0, 6.0), heart.y + randf_range(-2.0, 6.0), randf_range(0.4, 0.9), randf_range(18.0, 34.0)))
	for i: int in range(_sparks.size() - 1, -1, -1):
		var sp: Vector4 = _sparks[i]
		sp.z -= delta
		sp.y -= sp.w * delta
		sp.x += sin(_t * 9.0 + float(i)) * delta * 8.0
		if sp.z <= 0.0:
			_sparks.remove_at(i)
		else:
			_sparks[i] = sp


func _draw() -> void:
	var heart: Vector2 = (_body_point() - global_position).round()
	var s: float = strength()
	if s > 0.01:
		## a warm pool of light on the ground under it
		for k: int in 10:
			var a: float = TAU * float(k) / 10.0 + _t * 0.4
			draw_rect(Rect2(_foot + Vector2(roundf(cos(a) * (_size.x * 0.5 + 4.0)), roundf(sin(a) * 4.0)), Vector2.ONE), Color(ORANGE, 0.22 * s))
		## the tongues climb the body: a big one in the middle, others at the flanks and higher up, all licking upwards
		var half: float = _size.x * 0.5
		var tall: float = _size.y
		var tongues: Array[Vector3] = [Vector3(0.0, 0.0, 1.0), Vector3(-half * 0.7, -1.0, 0.7), Vector3(half * 0.7, 0.0, 0.75),
			Vector3(-half * 0.3, -tall * 0.45, 0.55), Vector3(half * 0.35, -tall * 0.4, 0.5), Vector3(0.0, -tall * 0.75, 0.45)]
		for i: int in tongues.size():
			var tg: Vector3 = tongues[i]
			var salt: float = _seed + float(i) * 3.7
			var beat: float = 0.6 + 0.4 * sin(_t * (7.0 + float(i)) + salt)
			_tongue(_foot + Vector2(roundf(tg.x), roundf(tg.y)), 3 if i == 0 else 2, roundi((tall * 0.75 + 4.0) * tg.z * beat * (0.55 + 0.45 * s)), salt, s)
	for sp: Vector4 in _sparks:
		var k: float = clampf(sp.z / 0.5, 0.0, 1.0)
		draw_rect(Rect2(Vector2(roundf(sp.x), roundf(sp.y)), Vector2.ONE), Color(YELLOW if k > 0.5 else ORANGE, k))
	if _leap_from.is_finite() and _t < 0.35: ## FUNKENSPRUNG: an arc of sparks from the creature that died
		var from: Vector2 = _leap_from - global_position
		var k2: float = _t / 0.35
		for j: int in 14:
			var f: float = float(j) / 13.0
			if f > k2:
				break
			var p: Vector2 = from.lerp(heart, f) + Vector2(0.0, -sin(f * PI) * 18.0)
			draw_rect(Rect2(p.round(), Vector2.ONE), Color(YELLOW if j % 3 == 0 else ORANGE, (1.0 - k2) * 0.9))


## One tongue of fire standing on `foot`: columns of whole pixels, each a little taller towards the middle, swaying at the top.
func _tongue(foot: Vector2, half: int, height: int, salt: float, s: float) -> void:
	if height < 2:
		return
	var flick: float = floorf(_t * 14.0)
	for col: int in range(-half, half + 1):
		var edge: float = 1.0 - absf(float(col)) / float(half + 1)
		var tall: int = maxi(roundi(float(height) * (0.45 + 0.55 * edge) * (0.8 + 0.4 * _hash(salt + float(col) * 1.3 + flick))), 1)
		for row: int in tall:
			var up: float = float(row) / float(tall)
			var sway: float = roundf(sin(_t * 9.0 + salt + float(row) * 0.5) * up * 1.6)
			var colour: Color = DEEP.lerp(RED, clampf(up * 3.0, 0.0, 1.0))
			if up > 0.3:
				colour = RED.lerp(ORANGE, clampf((up - 0.3) * 3.0, 0.0, 1.0))
			if up > 0.68:
				colour = ORANGE.lerp(YELLOW, clampf((up - 0.68) * 3.0, 0.0, 1.0))
			if absi(col) == 0 and up < 0.5 and _fresh > 0.2:
				colour = colour.lerp(WHITE, _fresh)
			var alpha: float = s * (0.95 - up * 0.45)
			draw_rect(Rect2(foot + Vector2(float(col) + sway, -float(row)), Vector2.ONE), Color(colour, alpha))


static func _hash(x: float) -> float:
	var v: float = sin(x * 127.1) * 43758.5453
	return v - floorf(v)
