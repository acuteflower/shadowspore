class_name SkyCleaver
extends CharacterBody2D
## Mornath, der Himmelsspalter (`boss_sky_cleaver`): the first boss, a sun eagle of the order of the High Spire eaten by the Void. For now it has no attacks:
## it sits on one of the arena's pillars and now and then flies to another one (PERCHED -> TAKEOFF -> FLYING -> HOVER -> LANDING -> PERCHED).
## Design: docs/boss_sky_cleaver.md. The root node always stays on the ground (collision, shadow, y-sort); the picture (`Rig`) is lifted by `_height`.
##
## Host authority, deterministic replay: the host decides when and where to fly and tells everybody with reliable RPCs (`_rpc_fly_to_pillar`, `_rpc_phase`,
## `_rpc_perch_land`, `_rpc_ground_crash`); every peer then plays the same timeline (a quadratic Bezier between two pillars, heights from the pillars' perches),
## so nothing about its position is synchronised. A joining peer asks the host for a snapshot. It can be hit on and next to its pillar (perched, taking off, landing);
## a heavy hit (knockback >= `heavy_knockback`) breaks the take-off.

signal touched_down ## the first touchdown on its pillar after the entrance flight (the boss entrance screen waits for it)
signal perched ## every time it has settled on a pillar (every peer)
signal reset_requested ## host: nobody is left in the fight; the level removes the boss and arms the arena again
signal defeated ## host and clients: the boss died (the level forgets the checkpoint: the next summoning begins at phase 1)
signal checkpoint_reached(phase: int)## host: the fight reached a phase it restarts from after a wipe (the level remembers it for the next summoning)

enum State { PERCHED, TAKEOFF, FLYING, HOVER, LANDING, STAGGER, CRASHED, DEAD, ACT } ## ACT: the fight (src/entities/enemies/mornath_fight.gd) puts it where it wants (`puppet_*`)
const TITLE: String = "MORNATH" ## the name over the boss bar (the full title is the entrance screen's: data `intro`)
const HURTBOX_LAYER: int = 1 << 4
const HOVER_BOB: float = 2.5
const BEAD_OFFSET: Vector2 = Vector2(0, 5)

var enemy_id: String = "boss_sky_cleaver"
var health_scale: float = 1.0
var damage_scale: float = 1.0
var emerge_on_spawn: bool = false ## unused (the boss does not come from the night's cracks), kept for the shared spawn contract
var arena: String = "" ## id of its arena (data/ground.json "arenas"): its pillars are the nodes of the group "arena_pillars" with this arena
var pillar_index: int = 0 ## the pillar it starts on (and, when arriving, the one it lands on)
var arrive_height: float = 0.0 ## > 0: it is not on its pillar yet; it spawns off-screen at `position` (this high above the ground) and flies in
var start_phase: int = 0 ## the fight begins at this phase (after everybody fell in the judgement the next summoning starts at phase 2): health, broken pillars and look follow
var heading: float = PI / 2.0
var state: State = State.PERCHED
var _def: Dictionary
var _pillars: Array[ArenaPillar] = []
var _centre: Vector2 = Vector2.ZERO
var _from: int = 0
var _to: int = 0
var _side: float = 1.0
var _arrival: bool = false ## the flight in from off-screen (until it has touched down on its pillar for the first time)
var _origin: Vector2 = Vector2.ZERO ## where the current flight starts (a pillar's foot, or the off-screen entry point)
var _origin_height: float = 0.0
var _arc: float = 0.0
var _curve: float = 0.0
var _fly_time: float = 2.0
var _hover_time: float = 1.0
var _state_time: float = 0.0
var _height: float = 0.0
var _rise: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _last_height: float = 0.0
var _dwell: float = 3.0
var _crash_pos: Vector2 = Vector2.ZERO
var _crash_height: float = 0.0
var _crash_drift: Vector2 = Vector2.ZERO
var _hittable: bool = true
var _bar_shown: bool = false
var _intro: BossIntro ## the entrance screen of the local player (while it runs the boss bar waits)
var _breath_left: float = 4.0
var _stream_cache: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# --- the fight (docs/boss_sky_cleaver.md): set by MornathFight
var puppet_pos: Vector2 = Vector2.ZERO ## State.ACT: where on the ground it is, set every frame by the fight ...
var puppet_height: float = 0.0 ## ... and how high
var act_hittable: bool = false ## State.ACT: can it be struck?
var armour: float = 1.0 ## the factor every blow is multiplied with (SkyCleaverHurtbox): tired he is soft, braced he is hard
var invulnerable: bool = false ## resting at the end of a phase: no blow lands on him, the pillar takes them
var look_point: Vector2 = Vector2.INF ## where it looks instead of at the nearest player
var arena_origin: Vector2 = Vector2.ZERO ## the arena's middle tile (world): arena data is relative to it
var arena_poly: PackedVector2Array = PackedVector2Array()
var fight: MornathFight
var field: FeatherField
var rig: SkyCleaverRig:
	get:
		return _rig
var _fight_on: bool = false
var _arena_spec: Dictionary = {}
var _arena_bounds: Rect2 = Rect2()
var _rig_frozen: float = 0.0
var _reset_asked: bool = false
var _corruption: float = 0.0
var _fury: float = 0.0

@onready var _rig: SkyCleaverRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _shadow: Node2D = $Shadow
@onready var _trail: ShadowTrailComponent = $ShadowTrail
@onready var _dust: CPUParticles2D = $Rig/Dust
@onready var _hit_fx: CPUParticles2D = $Rig/HitFx
@onready var _voice: AudioStreamPlayer2D = $Voice
@onready var _wings: AudioStreamPlayer2D = $Wings
@onready var _impact: AudioStreamPlayer2D = $Impact


func _ready() -> void:
	add_to_group("predators")
	add_to_group("bosses")
	_def = EnemyScaling.scaled(DataRegistry.get_entry("enemies", enemy_id), health_scale, damage_scale)
	_health.max_health = float(_def["max_health"])
	_health.current = _health.max_health
	if start_phase > 0:
		var fight_spec: Dictionary = _def.get("fight", {}) as Dictionary
		var phases: Array = fight_spec.get("phases", []) as Array
		if not phases.is_empty():
			_health.current = _health.max_health * float((phases[mini(start_phase, phases.size()) - 1] as Dictionary)["to"])
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_rng.seed = hash(arena) + 17
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		var pillar: ArenaPillar = node as ArenaPillar
		if pillar != null and pillar.arena == arena:
			_pillars.append(pillar)
	_pillars.sort_custom(func(a: ArenaPillar, b: ArenaPillar) -> bool: return a.index < b.index)
	if start_phase == 0: ## a fresh fight (also one called back by the hologram after a victory): every pillar stands whole and cold again, on every peer
		for pillar: ArenaPillar in _pillars:
			if pillar.broken:
				pillar.restore()
			else:
				pillar.set_armed(false)
				pillar.extinguish(0.0)
	if _pillars.is_empty():
		set_physics_process(false)
		return
	for pillar: ArenaPillar in _pillars:
		_centre += pillar.global_position
	_centre /= float(_pillars.size())
	_from = clampi(pillar_index, 0, _pillars.size() - 1)
	_to = _from
	_dwell = float((_def["perch"] as Dictionary)["first_dwell"])
	_load_arena()
	if arrive_height > 0.0:
		_begin_arrival()
	else:
		_place_on_perch()
	_last_pos = global_position
	_last_height = _height
	heading = (_centre - global_position).angle()
	_rig.tick_hz = 24.0 ## physics runs at 120 Hz; the rig (about 9 ms a rebuild) needs no more than the screen shows
	_shadow.draw.connect(_draw_shadow)
	_rig.wing_beat.connect(_on_wing_beat)
	_rig.bead_dropped.connect(_on_bead_dropped)
	_enter(State.FLYING if _arrival else State.PERCHED, 0.0)
	var decal: Dictionary = _arena_decal()
	if _def.has("fight") and not decal.is_empty():
		field = FeatherField.new()
		field.name = "Feathers"
		add_child(field)
		field.setup(decal, multiplayer.is_server())
		field.damage_scale = damage_scale
		fight = MornathFight.new()
		fight.name = "Fight"
		add_child(fight)
		fight.setup(self, field)
		_fight_on = true
		touched_down.connect(fight.on_touched_down)
		perched.connect(fight.on_perched)
		_health.died.connect(func() -> void: fight.release_feathers(false))
	if multiplayer.is_server():
		if _arrival:
			_start_intro(0.0)
	else:
		_request_state.rpc_id(1)
		if fight != null:
			fight.request_sync()


func _process(_delta: float) -> void:
	if _rig.on_screen:
		_shadow.queue_redraw()
	_update_bar()


## Is any living player close enough to see it? (the screen reaches about 370 px from its middle; the picture is lifted by `_height`)
## How often the rig is rebuilt (6-10 ms a rebuild, measured with tools/bench_sky_cleaver.tscn): 40 a second while anything moves fast, 30 while he only
## sits, rests or lies there. Both divide the 120 Hz physics tick evenly; the old 60 doubled the cost exactly when an attack started (the lag).
func _wanted_tick() -> float:
	if state in [State.FLYING, State.HOVER, State.TAKEOFF, State.LANDING, State.STAGGER, State.CRASHED, State.DEAD]:
		return 24.0
	if fight != null and fight.wants_fast():
		return 24.0
	return 12.0


func _seen_by_anyone() -> bool:
	var at: Vector2 = global_position + Vector2(0.0, -_height)
	for player: Player in Player.all:
		if player.global_position.distance_to(at) < 520.0:
			return true
	return false


func _physics_process(delta: float) -> void:
	_state_time += delta
	_step_timeline()
	_update_heading(delta)
	var moved: Vector2 = global_position - _last_pos
	_velocity = moved / maxf(delta, 0.0001)
	_rise = (_height - _last_height) / maxf(delta, 0.0001)
	_last_pos = global_position
	_last_height = _height
	_rig.position = Vector2(0.0, -roundf(_height))
	_rig.ground_drop = _height
	_rig.on_screen = _seen_by_anyone()
	_rig_frozen = maxf(_rig_frozen - delta, 0.0)
	_rig.tick_hz = _wanted_tick()
	if _rig_frozen <= 0.0:
		_rig.update_rig(delta, _velocity, heading, _rise)
	_update_hittable()
	if state == State.PERCHED:
		_breath_left -= delta
		if _breath_left <= 0.0:
			_breath_left = _rng.randf_range(7.0, 12.0)
			_play(_voice, "breath", -6.0)
	if multiplayer.is_server():
		_host_step(delta)


# --- the timeline (every peer) -------------------------------------------------------------------------------------


func _duration(s: State) -> float:
	match s:
		State.TAKEOFF:
			return float((_def["perch"] as Dictionary)["takeoff"])
		State.FLYING:
			return _fly_time
		State.HOVER:
			return _hover_time
		State.LANDING:
			return float((_def["landing"] as Dictionary)["duration"])
		State.STAGGER:
			return float((_def["perch"] as Dictionary)["stagger"])
		State.CRASHED:
			return float((_def["crash"] as Dictionary)["fall"])
		State.DEAD:
			return float((_def["crash"] as Dictionary)["dead"])
	return 1.0


func _perch_pos(i: int) -> Vector2:
	return _pillars[clampi(i, 0, _pillars.size() - 1)].global_position


func _perch_height(i: int) -> float:
	return _pillars[clampi(i, 0, _pillars.size() - 1)].perch_height()


## The entrance: it spawns off-screen and swoops in on its pillar (FLYING -> HOVER -> LANDING -> PERCHED). Everything is derived from the spawn
## properties and the data, so every peer plays the same flight; the boss bar waits for the touchdown.
func _begin_arrival() -> void:
	var arrival: Dictionary = _def["arrival"] as Dictionary
	_arrival = true
	_origin = global_position
	_origin_height = arrive_height
	_side = 1.0 if hash(arena) % 2 == 0 else -1.0
	_apply_flight_shape()
	_fly_time = maxf(float((_def["flight"] as Dictionary)["min_time"]), _origin.distance_to(_perch_pos(_to)) / float(arrival["speed"]))
	_hover_time = float(arrival["hover"])
	_set_hittable(false)


func _apply_flight_shape() -> void:
	var shape: Dictionary = (_def["arrival"] if _arrival else _def["flight"]) as Dictionary
	_arc = float(shape["arc"])
	_curve = float(shape["curve"])


func _place_on_perch() -> void:
	global_position = _perch_pos(_from)
	_height = _perch_height(_from)


func _step_timeline() -> void:
	var flight: Dictionary = _def["flight"] as Dictionary
	var hover_above: float = float(flight["hover_above"])
	match state:
		State.PERCHED, State.TAKEOFF, State.STAGGER:
			_place_on_perch()
		State.ACT:
			global_position = puppet_pos
			_height = puppet_height
		State.FLYING:
			var t: float = clampf(_state_time / _fly_time, 0.0, 1.0)
			## eased: slow start (just left the perch), slow arrival; the entrance is already at speed and only brakes
			var s: float = (1.0 - (1.0 - t) * (1.0 - t)) if _arrival else t * t * (3.0 - 2.0 * t)
			var a: Vector2 = _origin
			var b: Vector2 = _perch_pos(_to)
			var across: Vector2 = (b - a).orthogonal().normalized()
			var control: Vector2 = (a + b) * 0.5 + across * _side * a.distance_to(b) * _curve
			global_position = a.lerp(control, s).lerp(control.lerp(b, s), s)
			_height = lerpf(_origin_height, _perch_height(_to) + hover_above, s) + sin(s * PI) * _arc
		State.HOVER:
			global_position = _perch_pos(_to)
			_height = _perch_height(_to) + hover_above + sin(_state_time * 2.3) * HOVER_BOB * smoothstep(0.0, 0.5, _state_time)
		State.LANDING:
			var t: float = clampf(_state_time / _duration(State.LANDING), 0.0, 1.0)
			var s: float = t * t * (3.0 - 2.0 * t)
			global_position = _perch_pos(_to)
			_height = lerpf(_perch_height(_to) + hover_above, _perch_height(_to), s)
		State.CRASHED:
			var t: float = clampf(_state_time / _duration(State.CRASHED), 0.0, 1.0)
			global_position = _crash_pos + _crash_drift * (1.0 - pow(1.0 - t, 2.0))
			_height = _crash_height * (1.0 - t * t)
		State.DEAD:
			_height = 0.0


func _update_heading(delta: float) -> void:
	var turn: float = float((_def["perch"] as Dictionary)["turn_speed"])
	var want: float = heading
	match state:
		State.FLYING:
			if _velocity.length() > 10.0:
				want = _velocity.angle()
			turn = float((_def["flight"] as Dictionary)["turn_rate"])
		State.PERCHED, State.TAKEOFF, State.HOVER, State.LANDING, State.STAGGER, State.ACT:
			want = _look_angle()
		_:
			return
	heading = lerp_angle(heading, want, 1.0 - exp(-turn * delta))


## Perched it watches the nearest living player, else the middle of the arena.
func _look_angle() -> float:
	if look_point.is_finite():
		var aimed: Vector2 = look_point - global_position
		if aimed.length() > 4.0:
			return aimed.angle()
	var best: Player
	var best_distance: float = float((_def["perch"] as Dictionary)["look_range"])
	for player: Player in Player.all:
		if player.health.current <= 0.0:
			continue
		var distance: float = player.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	var target: Vector2 = best.global_position if best != null else _centre
	var toward: Vector2 = target - global_position
	return toward.angle() if toward.length() > 4.0 else heading


# --- host decisions ------------------------------------------------------------------------------------------------


func _host_step(_delta: float) -> void:
	if state == State.DEAD or _health.current <= 0.0:
		if state == State.DEAD and _state_time >= _duration(State.DEAD) + 0.4:
			queue_free()
		elif state == State.CRASHED and _state_time >= _duration(State.CRASHED):
			_rpc_phase.rpc(State.DEAD)
		return
	match state:
		State.PERCHED:
			if not _fight_on and _state_time >= _dwell and _pillars.size() > 1:
				_plan_flight()
		State.TAKEOFF:
			if _state_time >= _duration(State.TAKEOFF):
				_rpc_phase.rpc(State.FLYING)
		State.FLYING:
			if _state_time >= _fly_time:
				_rpc_phase.rpc(State.HOVER)
		State.HOVER:
			if _state_time >= _hover_time:
				_rpc_perch_land.rpc()
		State.LANDING:
			if _state_time >= _duration(State.LANDING):
				_rpc_phase.rpc(State.PERCHED)
		State.STAGGER:
			if _state_time >= _duration(State.STAGGER):
				_rpc_phase.rpc(State.PERCHED)


func _plan_flight() -> void:
	var choices: Array[int] = []
	for i: int in _pillars.size():
		if i != _from:
			choices.append(i)
	var target: int = choices[_rng.randi() % choices.size()]
	var flight: Dictionary = _def["flight"] as Dictionary
	var distance: float = _perch_pos(_from).distance_to(_perch_pos(target))
	var fly_time: float = maxf(float(flight["min_time"]), distance / float(flight["speed"]) + 0.45)
	var hover_time: float = _rng.randf_range(float(flight["hover_min"]), float(flight["hover_max"]))
	_rpc_fly_to_pillar.rpc(target, 1.0 if _rng.randf() < 0.5 else -1.0, fly_time, hover_time)


## Start of a flight: the wind-up on the perch (TAKEOFF), the target, the bend of the curve and the times of the whole flight travel together.
@rpc("authority", "call_local", "reliable")
func _rpc_fly_to_pillar(to: int, side: float, fly_time: float, hover_time: float) -> void:
	_to = to
	_side = side
	_fly_time = fly_time
	_hover_time = hover_time
	_arrival = false
	_origin = _perch_pos(_from)
	_origin_height = _perch_height(_from)
	_apply_flight_shape()
	_enter(State.TAKEOFF, 0.0)


## A flight that starts where it is (after a chase, after a fall) instead of on a pillar: the same flight, hover and landing follow.
@rpc("authority", "call_local", "reliable")
func _rpc_fly_from(origin: Vector2, origin_h: float, to: int, side: float, fly_time: float, hover_time: float) -> void:
	_to = to
	_side = side
	_fly_time = fly_time
	_hover_time = hover_time
	_arrival = false
	_origin = origin
	_origin_height = origin_h
	_apply_flight_shape()
	_enter(State.FLYING, 0.0)


@rpc("authority", "call_local", "reliable")
func _rpc_phase(next: int) -> void:
	_enter(next as State, 0.0)


## Arrival: the braking flare and the touchdown on the target pillar.
@rpc("authority", "call_local", "reliable")
func _rpc_perch_land() -> void:
	_enter(State.LANDING, 0.0)


## Death: it drops out of the sky (or off its pillar) and crashes on the ground.
@rpc("authority", "call_local", "reliable")
func _rpc_ground_crash(from_pos: Vector2, from_height: float, drift: Vector2) -> void:
	_crash_pos = from_pos
	_crash_height = from_height
	_crash_drift = drift
	_enter(State.CRASHED, 0.0)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_rpc_snapshot.rpc_id(multiplayer.get_remote_sender_id(), state, _from, _to, _side, _fly_time, _hover_time, _state_time, _crash_pos, _crash_height, _crash_drift, _arrival, _origin, _origin_height, puppet_pos, puppet_height)


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(current: int, from: int, to: int, side: float, fly_time: float, hover_time: float, elapsed: float, crash_pos: Vector2, crash_height: float, drift: Vector2, arrival: bool, origin: Vector2, origin_height: float, p_puppet_pos: Vector2, p_puppet_height: float) -> void:
	_arrival = arrival
	_origin = origin
	_origin_height = origin_height
	_apply_flight_shape()
	var entering: bool = arrival and _intro == null
	_from = from
	_to = to
	_side = side
	_fly_time = fly_time
	_hover_time = hover_time
	_crash_pos = crash_pos
	_crash_height = crash_height
	_crash_drift = drift
	puppet_pos = p_puppet_pos
	puppet_height = p_puppet_height
	_enter(current as State, elapsed)
	if entering:
		_start_intro(elapsed)


## Every peer enters a state the same way; effects that belong to the beginning of a state only play when it is entered at its beginning.
func _enter(next: State, elapsed: float) -> void:
	var previous: State = state
	state = next
	_state_time = elapsed
	if next == State.PERCHED and previous in [State.LANDING]:
		_from = _to
	var first_touchdown: bool = next == State.PERCHED and _arrival
	if first_touchdown:
		_arrival = false ## first touchdown: the fight proper begins (the boss bar appears)
	if next == State.PERCHED and multiplayer.is_server():
		var perch: Dictionary = _def["perch"] as Dictionary
		_dwell = float(perch["first_dwell"]) if first_touchdown else _rng.randf_range(float(perch["dwell_min"]), float(perch["dwell_max"])) + (float(perch["stagger_dwell"]) if previous == State.STAGGER else 0.0)
	var fresh: bool = elapsed < 0.2
	var pose: SkyCleaverRig.Pose = SkyCleaverRig.Pose.PERCHED
	match next:
		State.TAKEOFF:
			pose = SkyCleaverRig.Pose.TAKEOFF
			if fresh:
				_play(_voice, "takeoff")
		State.FLYING:
			pose = SkyCleaverRig.Pose.FLYING
			if _arrival and fresh:
				_play(_voice, "takeoff") ## heard from afar before it is seen
		State.HOVER:
			pose = SkyCleaverRig.Pose.HOVER
		State.LANDING:
			pose = SkyCleaverRig.Pose.LANDING
		State.STAGGER:
			pose = SkyCleaverRig.Pose.STAGGER
		State.CRASHED:
			pose = SkyCleaverRig.Pose.CRASHED
			_set_hittable(false)
			if fresh:
				_play(_voice, "crash")
		State.DEAD:
			pose = SkyCleaverRig.Pose.DEAD
			if fresh:
				_impact_ground()
		State.PERCHED:
			if previous == State.LANDING and fresh:
				_touch_down()
			if first_touchdown:
				touched_down.emit()
	_rig.start_pose(pose, _duration(next), elapsed)
	if next == State.PERCHED:
		perched.emit()


## Where the camera looks while it swoops in: the boss as it will sit on its pillar (the middle of the picture at the end).
func landing_spot() -> Vector2:
	return _perch_pos(_to) + Vector2(0.0, -_perch_height(_to) - 22.0)


## Its middle on screen (the root stays on the ground, the picture is lifted by `_height`).
func eye_position() -> Vector2:
	return global_position + Vector2(0.0, -_height - 14.0)


## The entrance screen (src/ui/boss_intro.gd) for the local player when he is near the arena; `skip` = seconds of the flight that have passed already.
func _start_intro(skip: float) -> void:
	if _intro != null or _health.current <= 0.0 or DisplayServer.get_name() == "headless":
		return
	var shown: Dictionary = _def.get("intro", {}) as Dictionary
	if shown.is_empty():
		return
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(_centre) < float(shown.get("range", 700.0)):
			_intro = BossIntro.play(self, player, String(shown["name"]), String(shown["epithet"]), skip)
			_intro.finished.connect(func() -> void: _intro = null)
			return


func _touch_down() -> void:
	_play(_impact, "land")
	_dust.restart()
	_shake_near(global_position, float((_def["landing"] as Dictionary)["shake"]))


## The crash: dust, shards, a tremor and a dark mark on the ground.
func _impact_ground() -> void:
	_play(_impact, "crash")
	_dust.restart()
	_shake_near(global_position, 2.2)
	_trail.infest(global_position)


# --- hits and death ------------------------------------------------------------------------------------------------


func _update_hittable() -> void:
	var open: bool = state in [State.PERCHED, State.TAKEOFF, State.LANDING, State.STAGGER] or (state == State.ACT and act_hittable)
	_set_hittable(open and not invulnerable and _health.current > 0.0)


func _set_hittable(on: bool) -> void:
	if on == _hittable:
		return
	_hittable = on
	_hurtbox.set_deferred("collision_layer", HURTBOX_LAYER if on else 0)


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	var away: Vector2 = (global_position - from).normalized()
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -_height - 30.0), amount, away)
	_rig.hit_flash()
	_hit_fx.direction = -away if away != Vector2.ZERO else Vector2.UP
	_hit_fx.restart()
	_play(_impact, "hit", 0.0, randf_range(0.92, 1.1))
	if not multiplayer.is_server() or _health.current <= 0.0:
		return
	if fight != null:
		fight.on_damaged(from)
	if not _fight_on and state == State.TAKEOFF and knockback >= float(_def["heavy_knockback"]):
		_rpc_phase.rpc(State.STAGGER) ## a heavy hit breaks the take-off


func _on_died() -> void:
	_set_hittable(false)
	defeated.emit()
	get_tree().call_group("arena_story", "boss_defeated", arena) ## the arena's story (quest, knight, hologram) on every peer
	if multiplayer.is_server():
		_rpc_ground_crash.rpc(global_position, _height, _velocity * 0.35 if state == State.FLYING else Vector2.ZERO)


func _on_wing_beat(strong: bool) -> void:
	_play(_wings, "wing_strong" if strong else "wing_soft", 0.0, randf_range(0.94, 1.06))


## A void bead fell from the perched boss and hit the floor: a small creeping shadow where it lands.
func _on_bead_dropped(ground_point: Vector2) -> void:
	var at: Vector2 = ground_point + BEAD_OFFSET
	_trail.leave(at, false)
	_impact.global_position = at
	_play(_impact, "bead", 0.0, randf_range(0.9, 1.15))


# --- the boss bar (every peer, only for its own local players) -----------------------------------------------------


func _update_bar() -> void:
	if _pillars.is_empty():
		return
	var near: bool = false
	var range_px: float = float(_def["bar_range"]) * (1.25 if _bar_shown else 1.0)
	if _health.current > 0.0 and not _arrival and _intro == null:
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(_centre) < range_px:
				near = true
				break
	if near and not _bar_shown:
		_bar_shown = true
		get_tree().call_group("boss_bar", "track", TITLE, _health)
	elif not near and _bar_shown:
		_bar_shown = false
		if _health.current > 0.0:
			get_tree().call_group("boss_bar", "release")


# --- the fight's handles -------------------------------------------------------------------------------------------


func _load_arena() -> void:
	for spec: Dictionary in DataRegistry.table("ground").get("arenas", []) as Array:
		if String(spec.get("id", "")) != arena:
			continue
		_arena_spec = spec
		var tile: Array = spec["tile"] as Array
		arena_origin = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
		arena_poly = PackedVector2Array()
		for point: Array in spec["poly"] as Array:
			arena_poly.append(arena_origin + Vector2(float(point[0]), float(point[1])))
		var lo: Vector2 = arena_poly[0]
		var hi: Vector2 = arena_poly[0]
		for q: Vector2 in arena_poly:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		_arena_bounds = Rect2(lo, hi - lo)
		return


func _arena_decal() -> Dictionary:
	for decal: Dictionary in DataRegistry.table("ground_baked").get("decals", []) as Array:
		if String(decal.get("id", "")) == arena + "_arena":
			return decal
	return {}


## The entrance screen of a local player is still on.
func intro_running() -> bool:
	return _intro != null


func def_value(key: String) -> Variant:
	return _def.get(key)


func centre() -> Vector2:
	return _centre


func arena_rect() -> Rect2:
	return _arena_bounds


## The middle of the arena's floor: the sun sigil (data/ground.json arenas[].sigil, relative to the middle tile; the same default as tools/arena_design.py).
func arena_middle() -> Vector2:
	var at: Array = _arena_spec.get("sigil", [26, -48]) as Array
	return arena_origin + Vector2(float(at[0]), float(at[1]))


## The feather barriers of the arena's ways down (data/ground.json arenas[].boss.barriers): [{id, solid [w, h], feathers [[x, y] relative to the middle tile]}].
func barrier_spec() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in (_arena_spec.get("boss", {}) as Dictionary).get("barriers", []) as Array:
		out.append(entry)
	return out


func max_health() -> float:
	return _health.max_health


func health_now() -> float:
	return _health.current


func health_floor() -> float:
	return _health.floor_value


## The health holds at this value (the next third): the blow that would take it lower leaves it there.
func set_floor(value: float) -> void:
	_health.floor_value = value


## Host: the finisher took the health past the third.
func host_set_health_fraction(fraction: float) -> void:
	if multiplayer.is_server():
		_health.set_health(_health.max_health * fraction)


func set_invulnerable(on: bool) -> void:
	invulnerable = on


## Whether it can be struck while the fight has it (State.ACT) and by what factor a blow counts.
func set_combat(hittable: bool, factor: float) -> void:
	act_hittable = hittable
	armour = factor


func perched_on() -> int:
	return _from


func pillar(i: int) -> ArenaPillar:
	return _pillars[i] if i >= 0 and i < _pillars.size() else null


func pillar_count() -> int:
	return _pillars.size()


func pillar_broken(i: int) -> bool:
	var p: ArenaPillar = pillar(i)
	return p == null or p.broken


func current_height() -> float:
	return _height


func set_pose(pose: SkyCleaverRig.Pose, duration: float) -> void:
	_rig.start_pose(pose, duration, 0.0)


## 0..1: how far the look has turned to the second phase (8 eyes, 10 tendrils, light blades, a broken halo ...); the rig eases towards it, the voice gets deeper.
func set_corruption(value: float) -> void:
	_corruption = value
	_rig.corruption = value


func corruption() -> float:
	return _corruption


## 0..1: how far the look has turned to the third and last phase (pink-violet fire, bigger wings of light, many more floating fragments); the rig eases towards it.
func set_fury(value: float) -> void:
	_fury = value
	_rig.fury = value


func fury() -> float:
	return _fury


## A joining peer or a checkpoint: the last look at once.
func set_fury_now(value: float) -> void:
	_fury = value
	_rig.set_fury_now(value)


## The fight takes over: from now on it is put at `pos` / `height` every frame.
func enter_act(pos: Vector2, height: float) -> void:
	state = State.ACT
	_state_time = 0.0
	puppet_pos = pos
	puppet_height = height
	global_position = pos
	_height = height


## The fight gives it back: it sits on the pillar it was last on.
func settle_on_perch() -> void:
	state = State.PERCHED
	_state_time = 0.0
	act_hittable = false
	armour = 1.0
	_place_on_perch()
	_rig.start_pose(SkyCleaverRig.Pose.PERCHED, 1.0, 0.0)


func keep_act_for_flight() -> void:
	act_hittable = false
	armour = 1.0


## Host: a flight to pillar `target`, from the pillar it sits on or (`from_here`) from wherever it is.
func host_fly_to(target: int, from_here: bool) -> void:
	if not multiplayer.is_server():
		return
	var flight: Dictionary = _def["flight"] as Dictionary
	var from_pos: Vector2 = global_position if from_here else _perch_pos(_from)
	var distance: float = from_pos.distance_to(_perch_pos(target))
	var speed: float = float(flight["speed"]) * (1.5 if from_here else 1.0)
	var fly_time: float = maxf(float(flight["min_time"]), distance / speed + 0.45)
	var hover_time: float = _rng.randf_range(float(flight["hover_min"]), float(flight["hover_max"])) * (0.4 if from_here else 1.0)
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	if from_here:
		_rpc_fly_from.rpc(global_position, _height, target, side, fly_time, hover_time)
	else:
		_rpc_fly_to_pillar.rpc(target, side, fly_time, hover_time)


func request_reset() -> void:
	if multiplayer.is_server() and not _reset_asked:
		_reset_asked = true
		reset_requested.emit()


func freeze_rig(seconds: float) -> void:
	_rig_frozen = seconds


func shake_near(point: Vector2, amount: float) -> void:
	_shake_near(point, amount)


func play_wing() -> void:
	_play(_wings, "wing_strong", 0.0, randf_range(0.94, 1.06))


func play_voice(cue: String) -> void:
	_play(_voice, cue)


func touch_down_fx() -> void:
	_touch_down()


func impact_ground() -> void:
	_impact_ground()


func hit_burst() -> void:
	_hit_fx.direction = Vector2.UP
	_hit_fx.restart()
	_dust.restart()


# --- sound and shake -----------------------------------------------------------------------------------------------


## Headless peers have no listener; skip playback there.
func _play(player: AudioStreamPlayer2D, cue: String, volume_offset: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path: String = String((_def["audio"] as Dictionary).get(cue, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	if not _stream_cache.has(path):
		_stream_cache[path] = load(path) as AudioStream
	player.stream = _stream_cache[path] as AudioStream
	player.volume_db = float((_def["audio"] as Dictionary)["volume_db"]) + volume_offset
	player.pitch_scale = pitch * (lerpf(1.0, 0.8, _corruption) * lerpf(1.0, 0.86, _fury) if player == _voice else 1.0) ## the voice of the second phase is deeper, the third deeper still
	player.play()


func _shake_near(point: Vector2, amount: float) -> void:
	var radius: float = float(_def["shake_radius"])
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			player.add_shake(amount * (1.0 - smoothstep(30.0, radius, player.global_position.distance_to(point))))


func _exit_tree() -> void:
	if fight != null:
		fight.release_feathers(true)
	if _health != null and _health.current > 0.0 and is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group("arena_pillars"): ## the fight was reset: the pillars stand again
			var pillar: ArenaPillar = node as ArenaPillar
			if pillar != null and pillar.arena == arena:
				pillar.restore()
	if _bar_shown and is_inside_tree():
		get_tree().call_group("boss_bar", "release")
	for player: AudioStreamPlayer2D in [_voice, _wings, _impact]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


## The flat ground shadow (36 x 14 px, smaller and fainter the higher it flies); it follows the root, which stays on the ground.
func _draw_shadow() -> void:
	var k: float = clampf(_height / 170.0, 0.0, 1.0)
	var rx: float = lerpf(18.0, 11.0, k)
	var ry: float = lerpf(7.0, 4.0, k)
	var alpha: float = lerpf(0.34, 0.17, k)
	if state in [State.PERCHED, State.TAKEOFF, State.STAGGER, State.LANDING]:
		alpha *= 0.4 ## on the pillar the base already carries its own shadow
	if state == State.DEAD:
		alpha *= 1.0 - smoothstep(0.55, 1.0, _state_time / _duration(State.DEAD))
	for y: int in range(-ceili(ry), ceili(ry) + 1):
		var q: float = float(y) / ry
		if absf(q) > 1.0:
			continue
		var w: float = floorf(sqrt(1.0 - q * q) * rx)
		_shadow.draw_rect(Rect2(-w, float(y), w * 2.0 + 1.0, 1.0), Color(0.0, 0.0, 0.0, alpha))
