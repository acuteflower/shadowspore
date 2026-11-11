class_name EmberVolley
extends SpellZone
## Glutschwarm (docs/magie_konzept.md, school GLUT): burning shards break out of the crystal in the staff's crown, hang for a heartbeat in a
## fan round it, glowing hotter, then each shoots off in its own curve to its target and homes in on it as it moves. Which creature each
## shard takes and how hard it hits the host decided (`extra` = [[body path, damage factor]], SpellRules.volley_plan); every peer flies the
## same shards. On impact: a burst of sparks and a flash, the host deals `damage * factor` (take_hit, credited to the caster) and every
## peer lights the creature (EmberBurn; a second shard on a burning creature adds `extend` seconds). Tier V (GLUTHERZ): the last shard bursts
## into a ring of embers that hits and lights everything within `ring` px for `damage * ring_share`. Gem Zunder V (AUFLODERN): a shard on a
## creature that already burns hits `rekindle` times as hard.
## Positions are in this node's frame (it stands on the caster's feet and never moves); drawn on the additive air layer above everybody.

const FAN_TIME: float = 0.16 ## the shards hang round the crown this long
const STAGGER: float = 0.07 ## one leaves after the other
const SPEED: float = 300.0 ## px/s along the curve
const HOT: Color = Color("fff4d0")
const YELLOW: Color = Color("ffd36a")
const ORANGE: Color = Color("ff8a3c")
const RED: Color = Color("d8461a")
const DEEP: Color = Color("8a2a10")

var _shards: Array[Dictionary] = [] ## {body, box, factor, start, fan, ctrl, t, dur, done, trail, last}
var _crown: Vector2 = Vector2(0.0, -34.0)
var _flashes: Array[Vector3] = [] ## x, y, age of the impact flashes (own frame)
var _life: float = 1.0


func _build() -> void:
	var who: Player = caster_node()
	if who != null and who.attack != null and who.attack.holds_staff():
		var hand: Node2D = who.attack.get_node_or_null("Hand") as Node2D
		if hand != null:
			_crown = hand.to_global(who.attack.blade_point(StaffCrystals.CROWN_PX)) - global_position
	var count: int = extra.size()
	var longest: float = 0.0
	for k: int in count:
		var step: Array = extra[k] as Array
		var body: Node2D = get_tree().root.get_node_or_null(NodePath(String(step[0]))) as Node2D
		var spread: float = (float(k) - float(count - 1) * 0.5) * 0.62
		var fan: Vector2 = _crown + Vector2(sin(spread) * 12.0, -cos(spread) * 9.0 - 3.0)
		var shard: Dictionary = {"body": body, "box": _box_of(body), "factor": float(step[1]), "fan": fan, "t": -FAN_TIME - STAGGER * float(k),
			"dur": 0.4, "done": false, "trail": [] as Array[Vector2], "last": fan, "ctrl": Vector2.ZERO, "start": fan, "index": k}
		_aim(shard)
		longest = maxf(longest, FAN_TIME + STAGGER * float(k) + float(shard["dur"]))
		_shards.append(shard)
	_life = longest + 0.9
	SpellZone.sound(self, "ember_launch", global_position + _crown, -2.0)
	for i: int in 14: ## the crystal sheds sparks as the shards break out
		var a: float = _rng.randf() * TAU
		mote(_crown, Vector2(cos(a), sin(a)) * _rng.randf_range(20.0, 55.0), _rng.randf_range(0.25, 0.5), [YELLOW, ORANGE, HOT][i % 3], 2 if i % 5 == 0 else 1, -20.0, 3.0)


func _ending() -> float:
	return _life


static func _box_of(body: Node2D) -> HurtboxComponent:
	if body == null:
		return null
	for child: Node in body.get_children():
		if child is HurtboxComponent and not (child is HarvestHurtbox):
			return child as HurtboxComponent
	return null


## Where a shard is going (own frame): the middle of its creature, or where it was last seen if it is gone.
func _target_of(shard: Dictionary) -> Vector2:
	var box: HurtboxComponent = shard["box"] as HurtboxComponent
	if box != null and is_instance_valid(box):
		shard["last"] = box.global_position - global_position
	return shard["last"] as Vector2


## The curve of a shard: from its place in the fan, bowed outwards and up, to the target.
func _aim(shard: Dictionary) -> void:
	var from: Vector2 = shard["fan"] as Vector2
	var to: Vector2 = _target_of(shard)
	var dir: Vector2 = (to - from)
	var side: float = -1.0 if int(shard["index"]) % 2 == 0 else 1.0
	shard["ctrl"] = from.lerp(to, 0.35) + dir.orthogonal().normalized() * side * clampf(dir.length() * 0.35, 14.0, 46.0) + Vector2(0.0, -22.0)
	shard["dur"] = clampf((dir.length() * 1.25) / SPEED, 0.22, 0.75)


func _update(delta: float) -> void:
	for shard: Dictionary in _shards:
		if bool(shard["done"]):
			continue
		shard["t"] = float(shard["t"]) + delta
		var t: float = float(shard["t"])
		var pos: Vector2
		if t < 0.0: ## hanging in the fan, trembling and glowing up
			var grow: float = clampf(1.0 + t / (FAN_TIME + STAGGER * float(shard["index"])), 0.0, 1.0)
			pos = _crown.lerp(shard["fan"] as Vector2, 1.0 - pow(1.0 - grow, 3.0)) + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
		else:
			var k: float = clampf(t / float(shard["dur"]), 0.0, 1.0)
			var e: float = k * k * (1.6 - 0.6 * k) ## a lazy start, then it shoots
			var to: Vector2 = _target_of(shard) ## homing: the end follows the creature
			var a: Vector2 = (shard["fan"] as Vector2).lerp(shard["ctrl"] as Vector2, e)
			var b: Vector2 = (shard["ctrl"] as Vector2).lerp(to, e)
			pos = a.lerp(b, e)
			if k >= 1.0:
				_impact(shard, to)
		var trail: Array = shard["trail"] as Array
		trail.push_front(pos)
		if trail.size() > 10:
			trail.pop_back()
		shard["pos"] = pos
		if t >= 0.0 and _rng.randf() < delta * 40.0:
			mote(pos, Vector2(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-10.0, 4.0)), _rng.randf_range(0.2, 0.45), ORANGE if _rng.randf() < 0.6 else YELLOW, 1, 14.0, 2.0)
	for i: int in range(_flashes.size() - 1, -1, -1):
		var f: Vector3 = _flashes[i]
		f.z += delta
		if f.z > 0.35:
			_flashes.remove_at(i)
		else:
			_flashes[i] = f


func _impact(shard: Dictionary, at: Vector2) -> void:
	shard["done"] = true
	_flashes.append(Vector3(at.x, at.y, 0.0))
	for i: int in 12:
		var a: float = _rng.randf() * TAU
		mote(at, Vector2(cos(a), sin(a) * 0.8) * _rng.randf_range(25.0, 70.0) + Vector2(0.0, -15.0), _rng.randf_range(0.2, 0.5), [HOT, YELLOW, ORANGE, RED][i % 4], 2 if i % 4 == 0 else 1, -30.0, 3.5)
	SpellZone.sound(self, "ember_hit", global_position + at, -3.0)
	var body: Node2D = shard["body"] as Node2D
	var box: HurtboxComponent = shard["box"] as HurtboxComponent
	var last: bool = int(shard["index"]) == _shards.size() - 1
	if body != null and is_instance_valid(body) and box != null and is_instance_valid(box) and box.health != null and box.health.current > 0.0:
		var already: bool = body.get_node_or_null("EmberBurn") != null
		var factor: float = float(shard["factor"])
		if already and float(params["rekindle"]) > 0.0: ## Zunder V AUFLODERN: a burning creature flares up
			factor *= float(params["rekindle"])
			_flashes.append(Vector3(at.x, at.y - 6.0, -0.04))
			for j: int in 16:
				mote(at + Vector2(_rng.randf_range(-5.0, 5.0), 0.0), Vector2(_rng.randf_range(-14.0, 14.0), -_rng.randf_range(50.0, 110.0)), _rng.randf_range(0.3, 0.6), [HOT, YELLOW, ORANGE][j % 3], 2 if j % 3 == 0 else 1, -20.0, 2.5)
			SpellZone.sound(self, "ember_burst", global_position + at, -4.0)
		EmberBurn.ignite(body, float(params["burn_dps"]), float(params["burn_seconds"]), caster, float(params["jump"]), float(params["extend"]) if already else 0.0)
		if multiplayer.is_server():
			box.take_hit(float(params["damage"]) * factor, global_position + _crown, 30.0, caster)
	if last and float(params["ring"]) > 0.0: ## GLUTHERZ: the last shard bursts into a ring of embers
		_glutherz(at)


func _glutherz(at: Vector2) -> void:
	var ring: float = float(params["ring"])
	_flashes.append(Vector3(at.x, at.y, -0.05))
	for i: int in 28:
		var a: float = TAU * float(i) / 28.0
		mote(at, Vector2(cos(a), sin(a) * SQUASH) * ring * 3.2, 0.35, [HOT, YELLOW, ORANGE][i % 3], 2 if i % 4 == 0 else 1, 0.0, 4.0)
	SpellZone.sound(self, "ember_burst", global_position + at, 0.0)
	var world_at: Vector2 = global_position + at
	for box: HurtboxComponent in SpellComponent.volley_targets(self, world_at, world_at, ring):
		var body: Node2D = box.get_parent() as Node2D
		EmberBurn.ignite(body, float(params["burn_dps"]), float(params["burn_seconds"]), caster, float(params["jump"]))
		if multiplayer.is_server():
			box.take_hit(float(params["damage"]) * float(params["ring_share"]), world_at, 45.0, caster)


func _draw_air() -> void:
	super._draw_air()
	for f: Vector3 in _flashes: ## impacts: a white-hot spark that opens into a cross and a broken ring
		if f.z < 0.0:
			continue
		var k: float = f.z / 0.35
		var at: Vector2 = Vector2(f.x, f.y).round()
		var arm: float = roundf(2.0 + k * 6.0)
		var col: Color = Color(HOT.lerp(ORANGE, k), 1.0 - k)
		_air.draw_rect(Rect2(at + Vector2(-arm, 0.0), Vector2(arm * 2.0 + 1.0, 1.0)), col)
		_air.draw_rect(Rect2(at + Vector2(0.0, -arm), Vector2(1.0, arm * 2.0 + 1.0)), col)
		var r: float = 3.0 + k * 11.0
		for j: int in 12:
			if j % 3 == 1:
				continue
			var a: float = TAU * float(j) / 12.0
			_air.draw_rect(Rect2((at + Vector2(cos(a) * r, sin(a) * r * 0.7)).round(), Vector2.ONE), Color(YELLOW.lerp(RED, k), (1.0 - k) * 0.8))
	for shard: Dictionary in _shards:
		if bool(shard["done"]) or not shard.has("pos"):
			continue
		var trail: Array = shard["trail"] as Array
		for i: int in range(trail.size() - 1, 0, -1): ## the tail: hot behind the shard, red and thin further back
			var k2: float = float(i) / float(trail.size())
			var p: Vector2 = (trail[i] as Vector2).round()
			_air.draw_rect(Rect2(p, Vector2.ONE), Color(ORANGE.lerp(DEEP, k2), (1.0 - k2) * 0.85))
			if i < 5:
				_air.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color(RED, (1.0 - k2) * 0.6))
			if i < 3:
				var mid: Vector2 = ((trail[i] as Vector2) + (trail[i - 1] as Vector2)) * 0.5
				_air.draw_rect(Rect2(mid.round(), Vector2.ONE), Color(YELLOW, 0.6))
		_shard(shard["pos"] as Vector2, trail)


## One burning shard: a splinter of glowing crystal along its flight (white-hot heart, yellow core, orange flanks, a red tail end), in a
## pulsing halo of red light.
func _shard(pos: Vector2, trail: Array) -> void:
	var dir: Vector2 = Vector2.UP
	if trail.size() > 2:
		var d: Vector2 = (trail[0] as Vector2) - (trail[2] as Vector2)
		if d.length() > 0.5:
			dir = d.normalized()
	var at: Vector2 = pos.round()
	var side: Vector2 = dir.orthogonal()
	var pulse: float = 0.75 + 0.25 * sin(_age * 30.0)
	for g: int in 12: ## halo
		var a: float = TAU * float(g) / 12.0 + _age * 5.0
		_air.draw_rect(Rect2((at + Vector2(cos(a), sin(a)) * 4.0).round(), Vector2.ONE), Color(RED, 0.3 * pulse))
		if g % 2 == 0:
			_air.draw_rect(Rect2((at + Vector2(cos(a), sin(a)) * 6.0).round(), Vector2.ONE), Color(DEEP, 0.25 * pulse))
	for s: int in range(-4, 4): ## the body: pointed at the front, widest behind the tip
		var w: float = 0.0 if s == 3 or s == -4 else (1.0 if s >= -2 else 0.5)
		var p: Vector2 = at + dir * float(s)
		var core: Color = HOT if s >= 1 else (YELLOW if s >= -1 else ORANGE)
		_air.draw_rect(Rect2(p.round(), Vector2.ONE), core)
		if w > 0.0:
			var flank: Color = ORANGE if s >= -1 else RED
			_air.draw_rect(Rect2((p + side * w).round(), Vector2.ONE), flank)
			_air.draw_rect(Rect2((p - side * w).round(), Vector2.ONE), flank)
