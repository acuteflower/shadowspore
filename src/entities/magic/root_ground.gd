class_name RootGround
extends SpellZone
## Wurzelgrund (docs/magie_konzept.md, school WURZEL): a seed of green light flies from the staff's crown to the aimed spot, the earth tears open
## (magic_root_soil.gdshader, world-lit) and wild roots break out of it (each one a `MagicRoot`, y-sorted with everybody), moss and small
## flowers spread, a witch-green ring breathes along the edge (magic_root_glow.gdshader). Every second the ground beats: a green ring runs out
## and the host heals every player standing in it by `heal` x their maximum health (only up to full; tier V LEBENSBLÜTE: on into overheal and
## burning is put out). Tier III (DORNEN): roots lash at shadow creatures inside (`thorns` per second). Wildwuchs V (BLÜTENSCHLUSS): when it
## ends the roots blossom and heal everyone inside once more by `bloom`. At the end the roots wither, sink and crumble, the earth closes.

const SEED_FLIGHT: float = 0.32 ## s the seed of light needs from the crown to the ground
const GREEN: Color = Color("a8f070")
const GREEN_DEEP: Color = Color("3f8a2a")
const LEAF: Array[Color] = [Color("c6f59a"), Color("8fdc5a"), Color("eaffd0")]
const EARTH: Array[Color] = [Color("5a3d33"), Color("3d2a2c"), Color("7a5a44")]
const PETALS: Array[Color] = [Color("f3e2ff"), Color("ffc6e8"), Color("eaffd0")]

var _soil: Node2D
var _glow: Node2D
var _roots: Array[MagicRoot] = []
var _light: NightLight
var _from: Vector2 = Vector2.ZERO ## the staff's crown when it was cast (zone frame)
var _landed: bool = false
var _beat: float = 0.0
var _bloom: float = 0.0
var _bloomed: bool = false
var _withering: bool = false


func _build() -> void:
	var caster_player: Player = caster_node()
	_from = (caster_player.global_position + Vector2(0.0, -34.0) - global_position) if caster_player != null else Vector2(0.0, -60.0)
	var reach: float = radius * 1.25 + 6.0
	var box: Rect2 = Rect2(-reach, -reach * SQUASH - 2.0, reach * 2.0, reach * SQUASH * 2.0 + 4.0)
	_soil = shader_quad("Soil", "res://assets/shaders/magic_root_soil.gdshader", box, -5)
	_glow = shader_quad("Glow", "res://assets/shaders/magic_root_glow.gdshader", box, -4)
	var look_seed: float = _rng.randf() * 100.0
	for node: Node2D in [_soil, _glow]:
		set_shader(node, "radius", radius)
		set_shader(node, "squash", SQUASH)
		set_shader(node, "seed", look_seed)
		set_shader(node, "grow", 0.0)
	_soil.visible = false
	_glow.visible = false
	var count: int = 4 + roundi(radius / 9.0) ## 7 at tier I, about 10 at the widest
	for i: int in count: ## more roots towards the rim, a few in the middle; never two on the same spot
		var a: float = TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / float(count)
		var r: float = radius * (_rng.randf_range(0.55, 0.88) if i % 3 != 0 else _rng.randf_range(0.12, 0.4))
		var root: MagicRoot = MagicRoot.new()
		root.position = Vector2(cos(a) * r, sin(a) * r * SQUASH).round()
		root.lean = Vector2(cos(a), sin(a) * 0.4) * _rng.randf_range(0.25, 0.7)
		root.height = _rng.randf_range(12.0, 22.0) * (1.15 if r > radius * 0.5 else 0.85) + float(params.get("tier", 1)) * 1.2
		root.thick = 4.0 if root.height > 18.0 else 3.0
		root.curl = _rng.randf_range(-1.0, 1.0) * 1.6
		root.phase = _rng.randf() * TAU
		root.delay = 0.05 + _rng.randf() * 0.35
		root.thorny = bool(params.get("perk3", false))
		root.leaves = _rng.randi_range(1, 3)
		root.salt = _rng.randi() % 100000
		add_child(root)
		_roots.append(root)
	SpellZone.sound(self, "root_seed", global_position + _from, -2.0)
	_light = NightLight.new()
	_light.radius = roundi(radius * 1.25)
	_light.squash = SQUASH
	_light.glow_color = Color("9cf06a")
	_light.base_energy = 0.0
	_light.pulse = 0.12
	add_child(_light)


func _ending() -> float:
	return 1.0


func _update(delta: float) -> void:
	var fly: float = clampf(_age / SEED_FLIGHT, 0.0, 1.0)
	if not _landed:
		_seed_trail(fly)
		if fly >= 1.0:
			_land()
		return
	var since: float = _age - SEED_FLIGHT
	var tear: float = 1.0 - pow(1.0 - clampf(since / 0.35, 0.0, 1.0), 3.0)
	var wither: float = ending_amount()
	if wither > 0.0 and not _bloomed and float(params.get("bloom", 0.0)) > 0.0:
		_bloomed = true
		_bloom = 1.0
		SpellZone.sound(self, "root_beat", global_position, 2.0)
		_host_bloom()
		for root: MagicRoot in _roots:
			root.blossom()
			for k: int in 4:
				mote(root.position + Vector2(0.0, -root.height), Vector2(_rng.randf_range(-25.0, 25.0), -_rng.randf_range(10.0, 35.0)), 1.2, PETALS[k % PETALS.size()], 1, -18.0, 1.2)
	_bloom = move_toward(_bloom, 0.0, delta * 1.5)
	if wither > 0.0 and not _withering:
		_withering = true
		SpellZone.sound(self, "root_wither", global_position, -4.0)
	if _beat > 0.0:
		_beat += delta / 0.7
		if _beat >= 1.0:
			_beat = 0.0
	for node: Node2D in [_soil, _glow]:
		set_shader(node, "age", _age)
		set_shader(node, "grow", tear)
		set_shader(node, "wither", wither)
	set_shader(_soil, "moss", clampf(since / 2.5, 0.0, 1.0))
	set_shader(_glow, "beat", _beat)
	set_shader(_glow, "bloom", _bloom)
	_light.base_energy = 0.75 * tear * (1.0 - wither) + 0.5 * _bloom
	var lashing: Array[Vector2] = []
	if bool(params.get("perk3", false)) and wither <= 0.0 and int(_age * 8.0) != int((_age - delta) * 8.0):
		for box: HurtboxComponent in enemies_inside():
			lashing.append(SpellZone.feet_of(box) - global_position)
	for root: MagicRoot in _roots:
		root.life = since
		root.wither = wither
		if not lashing.is_empty():
			var nearest: Vector2 = lashing[0]
			for spot: Vector2 in lashing:
				if spot.distance_to(root.position) < nearest.distance_to(root.position):
					nearest = spot
			if nearest.distance_to(root.position) < radius * 0.9:
				root.lash(nearest - root.position)
	if wither <= 0.0 and _rng.randf() < delta * 7.0: ## pollen and sap motes drift up off the roots
		var root_at: MagicRoot = _roots[_rng.randi() % _roots.size()]
		mote(root_at.position + Vector2(_rng.randf_range(-2.0, 2.0), -root_at.height * _rng.randf_range(0.3, 1.0)), Vector2(_rng.randf_range(-5.0, 5.0), -_rng.randf_range(6.0, 16.0)), _rng.randf_range(1.0, 2.0), LEAF[_rng.randi() % LEAF.size()], 1, -3.0, 0.4)
	if wither > 0.0 and wither < 0.7 and _rng.randf() < delta * 30.0: ## crumbling: earth falls off the withering roots
		var dying: MagicRoot = _roots[_rng.randi() % _roots.size()]
		mote(dying.position + Vector2(0.0, -dying.height * (1.0 - wither) * _rng.randf()), Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-6.0, 4.0)), 0.6, EARTH[_rng.randi() % EARTH.size()], 1, -70.0, 0.5)


## The seed of light on its way: an arc from the crown to the ground, a green trail behind it.
func _seed_trail(fly: float) -> void:
	var arc: Vector2 = _from.lerp(Vector2.ZERO, fly) + Vector2(0.0, -sin(fly * PI) * (24.0 + _from.length() * 0.18))
	mote(arc, Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0)), 0.35, LEAF[2], 2, 0.0, 3.0)
	mote(arc + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0)), Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(0.0, 12.0)), 0.5, LEAF[_rng.randi() % 2], 1, -20.0, 2.0)


## The seed strikes: the earth tears, clods and crumbs fly, a ring of green light runs out.
func _land() -> void:
	_landed = true
	SpellZone.sound(self, "root_burst", global_position)
	_soil.visible = true
	_glow.visible = true
	_beat = 0.001
	for i: int in 28:
		var a: float = _rng.randf() * TAU
		var speed: float = _rng.randf_range(25.0, 70.0)
		mote(Vector2(cos(a), sin(a) * SQUASH) * _rng.randf_range(2.0, 8.0), Vector2(cos(a), sin(a) * SQUASH) * speed + Vector2(0.0, -_rng.randf_range(30.0, 70.0)), _rng.randf_range(0.4, 0.8), EARTH[i % EARTH.size()], 2 if i % 5 == 0 else 1, -160.0, 1.0)
	for i: int in 14:
		var b: float = TAU * i / 14.0
		mote(Vector2(cos(b), sin(b) * SQUASH) * 4.0, Vector2(cos(b), sin(b) * SQUASH) * 70.0, 0.45, LEAF[i % LEAF.size()], 1, 0.0, 3.5)
	var me: Player = caster_node()
	if me != null and me.is_multiplayer_authority():
		me.add_shake(1.6)


## Host: the healing beat. Every second also on every peer: the ring runs out and leaves rise off whoever is healed.
func _host_tick(_tick: float) -> void:
	if _age < SEED_FLIGHT + 0.2:
		return
	var share: float = float(params.get("heal", 0.0))
	var lush: bool = bool(params.get("perk5", false))
	for player: Player in players_inside():
		var amount: float = player.health.max_health * share
		if not lush:
			amount = minf(amount, maxf(player.health.max_health - player.health.current, 0.0))
		elif player.effects != null:
			player.effects.clear("burn")
		if amount > 0.0:
			player.health.heal(amount)
	var thorns: float = float(params.get("thorns", 0.0)) if bool(params.get("perk3", false)) else 0.0
	if thorns > 0.0:
		for box: HurtboxComponent in enemies_inside():
			box.health.take_tick(thorns * float(params.get("tick", 1.0)), caster)
	_beat_fx()


## The beat as every peer sees it (each peer runs its own clock: the host's beat is only the first; the others follow their own tick).
func _beat_fx() -> void:
	_beat = 0.001
	SpellZone.sound(self, "root_beat", global_position, -8.0)
	for player: Player in players_inside():
		var at: Vector2 = player.global_position - global_position
		for k: int in 5:
			mote(at + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-24.0, -2.0)), Vector2(_rng.randf_range(-8.0, 8.0), -_rng.randf_range(14.0, 28.0)), _rng.randf_range(0.7, 1.1), LEAF[k % LEAF.size()], 2 if k == 0 else 1, -6.0, 1.0)


func _process(delta: float) -> void:
	super._process(delta)
	if not multiplayer.is_server() and _landed and ending_amount() <= 0.0: ## clients: the same beat on their own clock
		_tick_clock += delta
		if _tick_clock >= float(params.get("tick", 1.0)) and _age >= SEED_FLIGHT + 0.2:
			_tick_clock = 0.0
			_beat_fx()


## Host: BLÜTENSCHLUSS, a last heal when the roots blossom.
func _host_bloom() -> void:
	if not multiplayer.is_server():
		return
	for player: Player in players_inside():
		player.health.heal(player.health.max_health * float(params.get("bloom", 0.0)))
