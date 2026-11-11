class_name VeilStream
extends SpellZone
## Nebelschleier's cast (docs/magie_konzept.md, school NEBEL): a ribbon of pale mist unrolls from the crystal in the staff's crown to every
## veiled player (`extra` = their peer ids), curls round them twice and closes like a cloth. The veil itself (transparency, glitch, wisps,
## IRRSPUR) is the status effect `veil` (VeilFx), which the host has already put on them; this node is only the look of the cast. Every peer.

const MIST: Color = Color("b9aaff")
const PALE: Color = Color("f2eeff")
const DEEP: Color = Color("5a4ea0")
const TRAVEL: float = 0.3

var _crown: Vector2 = Vector2(0.0, -34.0)
var _targets: Array[Player] = []
var _cloud: Node2D ## NEBELWAND
var _cloud_tick: float = 0.0
var _puffs: Array[Vector4] = [] ## x, y, r, phase of the cloud's puffs (own frame)


func _build() -> void:
	var who: Player = caster_node()
	if who != null and who.attack != null and who.attack.holds_staff():
		var hand: Node2D = who.attack.get_node_or_null("Hand") as Node2D
		if hand != null:
			_crown = hand.to_global(who.attack.blade_point(StaffCrystals.CROWN_PX)) - global_position
	elif who != null:
		_crown = who.global_position + Vector2(0.0, -34.0) - global_position
	for id: Variant in extra:
		for player: Player in Player.all:
			if int(player.name) == int(id):
				_targets.append(player)
	SpellZone.sound(self, "veil_on", global_position, -2.0)
	if float(params.get("cloud", 0.0)) > 0.0:
		radius = float(params["cloud_radius"])
		for i: int in 11:
			var at: Vector2 = random_inside(_rng, 0.8)
			_puffs.append(Vector4(at.x, at.y, _rng.randf_range(8.0, 13.0), _rng.randf() * TAU))
		_cloud = Node2D.new()
		_cloud.name = "Cloud"
		_cloud.z_index = 1
		_cloud.material = add_material()
		_cloud.draw.connect(_draw_cloud)
		add_child(_cloud)


func _ending() -> float:
	return 1.0 + float(params.get("cloud", 0.0))


## 0..1 how thick the NEBELWAND stands (it swells in, and thins out in its last second).
func _cloud_amount() -> float:
	if _cloud == null:
		return 0.0
	var until: float = seconds + float(params["cloud"])
	return clampf(_age / 0.6, 0.0, 1.0) * clampf((until - _age) / 1.0, 0.0, 1.0)


func _update(delta: float) -> void:
	if _cloud != null:
		_cloud.queue_redraw()
		if multiplayer.is_server() and _cloud_amount() > 0.3:
			_cloud_tick -= delta
			if _cloud_tick <= 0.0:
				_cloud_tick = 0.5
				for player: Player in players_inside():
					if player.effects != null and player.effects.left("veil") < 1.0:
						player.effects.apply("veil", 1.0, float(params["tier"]), caster)
		if _rng.randf() < delta * 8.0 * _cloud_amount():
			mote(random_inside(_rng, 0.9) + Vector2(0.0, -2.0), Vector2(_rng.randf_range(-6.0, 6.0), -_rng.randf_range(6.0, 14.0)), _rng.randf_range(0.8, 1.4), MIST, 1, 0.0, 0.5)
	for player: Player in _targets:
		if not is_instance_valid(player):
			continue
		var body: Vector2 = player.global_position + Vector2(0.0, -16.0) - global_position
		var k: float = clampf(_age / TRAVEL, 0.0, 1.0)
		if k < 1.0 and _rng.randf() < 0.9: ## the ribbon's head sheds mist on its way
			var head: Vector2 = _curve(_crown, body, k)
			mote(head, Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-12.0, 2.0)), _rng.randf_range(0.3, 0.6), MIST if _rng.randf() < 0.7 else PALE, 1, 6.0, 2.5)
		elif _age < TRAVEL + 0.45 and _rng.randf() < 0.8: ## it wraps round them
			var a: float = (_age - TRAVEL) * 18.0 + _rng.randf() * 0.6
			var r: float = 11.0 - (_age - TRAVEL) * 8.0
			mote(body + Vector2(cos(a) * r, sin(a) * r * 1.6), Vector2(-sin(a), cos(a)) * 20.0, 0.4, PALE if _rng.randf() < 0.4 else MIST, 1, 4.0, 3.0)


## A soft S-curve from the crown to the target.
static func _curve(from: Vector2, to: Vector2, k: float) -> Vector2:
	var mid: Vector2 = from.lerp(to, 0.5) + (to - from).orthogonal().normalized() * sin(k * TAU) * 8.0 + Vector2(0.0, -10.0)
	var a: Vector2 = from.lerp(mid, k)
	var b: Vector2 = mid.lerp(to, k)
	return a.lerp(b, k)


func _draw_air() -> void:
	super._draw_air()
	var k: float = clampf(_age / TRAVEL, 0.0, 1.0)
	var fade: float = 1.0 - clampf((_age - TRAVEL - 0.25) / 0.6, 0.0, 1.0)
	if fade <= 0.0:
		return
	for player: Player in _targets:
		if not is_instance_valid(player):
			continue
		var body: Vector2 = player.global_position + Vector2(0.0, -16.0) - global_position
		var steps: int = 22
		for i: int in steps: ## the ribbon: two strands that wind round each other, thinning behind its head
			var f: float = float(i) / float(steps - 1) * k
			var p: Vector2 = _curve(_crown, body, f)
			var tail: float = clampf(1.0 - (k - f) * 1.6, 0.15, 1.0) * fade
			var twist: float = sin(f * 14.0 - _age * 10.0) * 2.0
			var n: Vector2 = (body - _crown).orthogonal().normalized()
			_air.draw_rect(Rect2((p + n * twist).round(), Vector2.ONE), Color(MIST, 0.7 * tail))
			_air.draw_rect(Rect2((p - n * twist).round(), Vector2.ONE), Color(PALE if i % 4 == 0 else DEEP, 0.5 * tail))
		if k >= 1.0: ## the cloth closing round them: a ring that shrinks to the body
			var c: float = clampf((_age - TRAVEL) / 0.4, 0.0, 1.0)
			var r: float = lerpf(18.0, 6.0, c)
			for j: int in 16:
				var a: float = TAU * float(j) / 16.0 + _age * 4.0
				_air.draw_rect(Rect2((body + Vector2(cos(a) * r, sin(a) * r * 1.5)).round(), Vector2.ONE), Color(PALE if j % 4 == 0 else MIST, (1.0 - c) * 0.8 * fade))


## NEBELWAND: soft dithered puffs of mist lying on the ground, slowly breathing and drifting.
func _draw_cloud() -> void:
	var amount: float = _cloud_amount()
	if amount <= 0.01:
		return
	for i: int in _puffs.size():
		var pf: Vector4 = _puffs[i]
		var centre: Vector2 = Vector2(pf.x + sin(_age * 0.6 + pf.w) * 3.0, pf.y + cos(_age * 0.5 + pf.w) * 1.5).round()
		var r: float = pf.z * (0.85 + 0.15 * sin(_age * 1.3 + pf.w))
		for y: int in range(-roundi(r * SQUASH), roundi(r * SQUASH) + 1):
			for x: int in range(-roundi(r), roundi(r) + 1):
				var d: float = Vector2(float(x), float(y) / SQUASH).length() / r
				if d > 1.0:
					continue
				var dither: float = float((x * 7 + y * 13 + i * 5) & 3) / 4.0
				if (1.0 - d) * 1.2 < dither:
					continue
				var tone: Color = PALE if d < 0.3 and (x + y) % 3 == 0 else (MIST if d < 0.75 else DEEP)
				_cloud.draw_rect(Rect2(centre + Vector2(float(x), float(y)), Vector2.ONE), Color(tone, 0.34 * amount * (1.25 - d)))
