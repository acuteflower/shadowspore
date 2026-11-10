class_name MornathFight
extends Node
## The fight against Mornath (docs/boss_sky_cleaver.md), phase 1 and the end of every phase. A child of the boss (`SkyCleaver`), on every peer.
##
## Host authority, deterministic replay: the host decides what happens next and tells everybody with a reliable RPC (`_rpc_act` ...); every peer then plays the same
## timeline from it (a list of events on this node's clock, `_t`): the feathers and warnings (`FeatherField`), the boss's body (`SkyCleaver.puppet_*`, the raise of the
## wings, the charge) and the sounds. Only the host hurts (the field's zones) and decides. Nothing about the boss's position is synchronised, except while it chases.
##
## The acts: BARRIER (the opening: feathers into the ways down), RAIN (waves of feathers over the floor), SHOT (one feather at one player, or a line across the arena),
## CHASE (he follows a player's footsteps, then a burst round him and he lands tired), BLAST (a shock round his pillar against people who cling to it).
## The end of a phase: when the health reaches the next third it holds (`HealthComponent.floor_value`), he breaks off, flies to a pillar and rests; weapons wear that
## pillar down (`ArenaPillar`); when it bursts he falls; the first blow on the fallen one is the finisher, the health falls past the third, the next phase begins.
##
## Phase 2 (from the first finisher on, `phase >= 1`): a short transition (TRANSITION: the bars close, tendrils lift him, two blades shatter and grow back as light, the look
## turns (`SkyCleaver.set_corruption`), he screams and pushes everybody away, the sky rift `RiftWall` tears open between the two pillars that still stand, the card
## "DER HIMMEL REISST", `BossPhaseScreen`), then the acts of data `fight.p2`: PINCER (two wings: an aimed shot and a line, then swapped), the rain from both sides of the rift
## that leaves puddles of void, HANDS (a blade turns like the hand of a clock from every pillar), CAGE (a ring of stakes closes in with a gap to get out through), the chase with
## an echo, the blast in two stages. The rift breathes (a gap opens now and then and he attacks). It ends with the JUDGEMENT: the rift collapses, he stands up on the northern
## pillar and begins to split the sky (a ring on the floor fills like a clock, the sky darkens, a pillar of light grows); weapons must break the pillar before the time is up,
## else everybody dies and the fight starts again at the beginning of phase 2 (`SkyCleaver.checkpoint_reached`).

enum Act { NONE, BARRIER, RAIN, SHOT, LINE, CHASE, BLAST, PINCER, HANDS, CAGE, DIVE, GLUT, SPLITTER, MARK }
enum Mode { WAIT, IDLE, ACTING, MOVING, BREAKING, REST, FALLING, DOWNED, FINISHING, RISING, TRANSITION, JUDGEMENT }

const SOUNDS: int = 4

var boss: SkyCleaver
var field: FeatherField
var mode: Mode = Mode.WAIT
var act: Act = Act.NONE
var phase: int = 0 ## 0 = the first phase
var barrier_done: bool = false
var _spec: Dictionary = {}
var _t: float = 0.0
var _events: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new() ## cosmetics of the act in progress (seeded by the host's number)
var _pick: RandomNumberGenerator = RandomNumberGenerator.new() ## the host's decisions
var _base_pos: Vector2 = Vector2.ZERO
var _base_h: float = 0.0
var _gap: float = 2.0
var _rot: int = 0
var _blast_cd: float = 3.0
var _near_t: float = 0.0
var _last_target: int = 0
var _wing: int = 0 ## the wing that is raised (0 = the bird's right)
var _lift: float = 0.0
var _raise: float = 0.0
var _charge: float = 0.0
var _fatigue: float = 0.0
var _rain_end: float = 0.0
var _droop_from: float = 0.0
var _chase: Dictionary = {}
var _stuck: Array[StuckFeather] = []
var _break_pillar: int = -1
var _fall_from: Vector2 = Vector2.ZERO
var _fall_to: Vector2 = Vector2.ZERO
var _sounds: Array[AudioStreamPlayer2D] = []
var _sound_i: int = 0
var _stream_cache: Dictionary = {}
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash: float = 0.0
var _watch: float = 0.0
var _away: float = 0.0
var _started: bool = false
var stat_us: int = 0 ## profiling: microseconds spent in the fight's own frame
var _living_cache: Array[Player] = []
var _living_frame: int = -1
var _watch_acc: float = 0.0
var _kick_t: PackedFloat32Array = PackedFloat32Array([9.0, 9.0]) ## seconds since a wing beat (a feather leaves it), per wing
var _kick_amp: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
var _opening_left: float = -1.0 ## host: seconds until the opening act (it waits for the entrance screen to end)
var haste: float = 1.0 ## the speed of the act in progress (1.1 below 45 % health in phase 2): this node's clock and the field's clock run this much faster
var rift: RiftWall ## the sky rift of phase 2
var judge_failed: bool = false
var _combo: bool = false ## the act just chosen is the first half of a combination: the next one follows at once
var _hurry: bool = false ## host: the rift's gap is open, attack now
var _rift_left: float = -1.0 ## host: seconds until the rift breathes again
var _hurry_in: float = -1.0
var _finish_to: float = 0.64
var _trans_pos: Vector2 = Vector2.ZERO
var _trans_h: float = 0.0
var _left_wing: int = 0
var _jfx: JudgementFx
var _meter: JudgementMeter
var _judge_total: float = 28.0
var _judge_hp: float = 240.0
var _kill_at: float = -1.0
var _aura: BossAura
var _final: bool = false ## the transition in progress is the third phase's (`fight.transition3`)
var _t3_scream: float = 0.0
var _t3_end: float = 0.0
var _dive: Dictionary = {} ## the dive of phase 3 (host decides the path, everybody replays the rest)
var blaze: FireArena ## the fire and the light of the third phase (fields, splinters, the brand mark, the burning floor)
var _glut_end: float = 99.0
var _mark: Dictionary = {}
var _mark_end: float = 99.0
var _split_first: int = 0
var _trail: Dictionary = {} ## host: player id -> where she stood (every 0.1 s), for the sky splinters
var _trail_acc: float = 0.0
var _edge_lit: bool = false ## the rim of the arena burns
var _last_stand: bool = false ## the last judgement is won: he lies there and can die


func setup(p_boss: SkyCleaver, p_field: FeatherField) -> void:
	boss = p_boss
	field = p_field
	_spec = boss.def_value("fight") as Dictionary
	_pick.seed = hash(boss.arena) + 91
	var phases: Array = _spec["phases"] as Array
	if boss.start_phase > 0: ## the fight starts at a later phase (everybody fell in the judgement): the earlier pillars lie broken, the look has turned
		phase = mini(boss.start_phase, phases.size())
		for i: int in phase:
			var broken: ArenaPillar = boss.pillar(int((phases[i] as Dictionary)["pillar"]))
			if broken != null:
				broken.break_silently()
		boss.set_corruption(1.0) ## (a checkpoint in the third phase replays its transition: the fire starts with it)
	boss.set_floor(_floor_for(phase))
	_aura = BossAura.begin(self)
	blaze = FireArena.new()
	blaze.name = "Fire"
	boss.add_child(blaze)
	blaze.setup(boss, field, _floor_spec())
	field.blaze = blaze
	_preload_sounds()
	for i: int in SOUNDS:
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.max_distance = 700.0
		player.attenuation = 1.4
		add_child(player)
		_sounds.append(player)


# --- small helpers -------------------------------------------------------------------------------------------------


func _num(group: String, key: String) -> float:
	return float(_sp(group)[key])


## The numbers of an act: phase 2 has its own for some (`fight.p2`), everything else is the same as in phase 1.
func _sp(group: String) -> Dictionary:
	if phase >= 2:
		var p3: Dictionary = _spec.get("p3", {}) as Dictionary
		if p3.has(group):
			return p3[group] as Dictionary
	if phase >= 1:
		var p2: Dictionary = _spec.get("p2", {}) as Dictionary
		if p2.has(group):
			return p2[group] as Dictionary
	return _spec[group] as Dictionary


func _gap_range() -> Array:
	if phase >= 2 and (_spec.get("p3", {}) as Dictionary).has("gap"):
		return (_spec["p3"] as Dictionary)["gap"] as Array
	if phase >= 1:
		var p2: Dictionary = _spec.get("p2", {}) as Dictionary
		if p2.has("gap"):
			return p2["gap"] as Array
	return _spec["gap"] as Array


func _pick_gap() -> float:
	var range_s: Array = _gap_range()
	return _pick.randf_range(float(range_s[0]), float(range_s[1])) / haste


func _rotation() -> Array:
	if phase >= 2 and (_spec.get("p3", {}) as Dictionary).has("rotation"):
		return (_spec["p3"] as Dictionary)["rotation"] as Array
	if phase >= 1:
		var p2: Dictionary = _spec.get("p2", {}) as Dictionary
		if p2.has("rotation"):
			return p2["rotation"] as Array
	return _spec["rotation"] as Array


## 1.0, or the p2 haste when his health is low (decided by the host and sent with the act, so every peer plays the same speed).
func _haste_now() -> float:
	if phase < 1:
		return 1.0
	var p2: Dictionary = _spec.get("p2", {}) as Dictionary
	if phase >= 2 and (_spec.get("p3", {}) as Dictionary).has("haste_below"):
		p2 = _spec["p3"] as Dictionary
	if boss.health_now() < float(p2.get("haste_below", 0.0)) * boss.max_health():
		return float(p2.get("haste", 1.0))
	return 1.0


func _rift_up() -> bool:
	return rift != null and is_instance_valid(rift)


func _rift_blocks(a: Vector2, b: Vector2) -> bool:
	if not _rift_up():
		return false
	# Quick rejection: if both endpoints are comfortably on the same side of the rift line (>14 px margin), they cannot intersect
	var sda: float = rift.signed_distance(a)
	var sdb: float = rift.signed_distance(b)
	if (sda > 14.0 and sdb > 14.0) or (sda < -14.0 and sdb < -14.0):
		return false
	return rift.blocks(a, b)


func _set_world_directors_active(active: bool) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var night: NightDirector = tree.get_first_node_in_group("night_director") as NightDirector
	if night != null:
		night.story_hold = not active
	var wildlife: WildlifeEvents = tree.get_first_node_in_group("wildlife_events") as WildlifeEvents
	if wildlife != null:
		wildlife.set_process(active if multiplayer.is_server() else false)


func _exit_tree() -> void:
	_set_world_directors_active(true)


func _extra() -> int:
	return maxi(_living().size() - 1, 0)


## Players who are alive and near the arena.
func _living() -> Array[Player]:
	var tick: int = Engine.get_physics_frames()
	if tick - _living_frame < 6 and _living_frame >= 0:
		return _living_cache
	_living_frame = tick
	var found: Array[Player] = []
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(boss.centre()) < 420.0:
			found.append(player)
	_living_cache = found
	return found


func _by_id(id: int) -> Player:
	for player: Player in Player.all:
		if player.name == str(id):
			return player
	return null


func _at(t: float, fn: Callable) -> void:
	_events.append({"t": t, "fn": fn})


func _fire_events() -> void:
	if _events.is_empty():
		return
	var due: Array[Dictionary] = []
	var later: Array[Dictionary] = []
	for e: Dictionary in _events:
		if float(e["t"]) <= _t:
			due.append(e)
		else:
			later.append(e)
	_events = later
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	for e: Dictionary in due:
		(e["fn"] as Callable).call()


func _clear_body() -> void:
	_lift = 0.0
	_raise = 0.0
	_charge = 0.0
	_fatigue = 0.0
	boss.rig.raise_r = 0.0
	boss.rig.raise_l = 0.0
	boss.rig.charge = 0.0
	boss.rig.fatigue = 0.0
	boss.look_point = Vector2.INF


func _floor_for(p: int) -> float:
	var phases: Array = _spec["phases"] as Array
	if p >= phases.size():
		return 0.0
	return float((phases[p] as Dictionary)["break_at"]) * boss.max_health() + 0.5


## How heavy the mood of the fight is (BossAura): nothing before it starts, faint in the first phase, heavy in the second, the heaviest in the judgement.
func aura_level() -> float:
	if boss == null or boss.state == SkyCleaver.State.DEAD or boss.state == SkyCleaver.State.CRASHED or mode == Mode.WAIT:
		return 0.0
	if mode == Mode.JUDGEMENT:
		return 1.3 if judge_failed else 1.1 + 0.2 * clampf(judge_elapsed() / maxf(judge_total(), 0.01), 0.0, 1.0)
	return 0.58 if phase < 1 else (0.85 if phase < 2 else 1.0)


func _kick(amount: float) -> void:
	if _aura != null:
		_aura.kick(amount)


## Loads every cue in the background now, so the first use in an attack is a cache hit and not a disk read on the main thread.
func _preload_sounds() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for cue: Variant in (boss.def_value("audio") as Dictionary).values():
		if cue is String and String(cue).begins_with("res://"):
			ResourceLoader.load_threaded_request(String(cue))


func _sound(cue: String, at: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var audio: Dictionary = boss.def_value("audio") as Dictionary
	var path: String = String(audio.get(cue, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	if not _stream_cache.has(path):
		var loaded: bool = ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED
		_stream_cache[path] = (ResourceLoader.load_threaded_get(path) if loaded else load(path)) as AudioStream
	var player: AudioStreamPlayer2D = _sounds[_sound_i % SOUNDS]
	_sound_i += 1
	player.stream = _stream_cache[path] as AudioStream
	player.global_position = at
	player.volume_db = float(audio["volume_db"]) + volume_db
	player.pitch_scale = pitch
	player.play()


## A flash of light over the screen of every local player near the arena (the finisher).
func _screen_flash(strength: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.global_position.distance_to(boss.centre()) < 600.0:
			_flash = maxf(_flash, strength)
			return


# --- the loop ------------------------------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_step(delta)
	stat_us += Time.get_ticks_usec() - t0


func _step(delta: float) -> void:
	_kick_t[0] += delta
	_kick_t[1] += delta
	if boss == null or boss.state == SkyCleaver.State.DEAD or boss.state == SkyCleaver.State.CRASHED:
		return
	if mode in [Mode.ACTING, Mode.FALLING, Mode.FINISHING, Mode.RISING, Mode.BREAKING, Mode.DOWNED, Mode.TRANSITION, Mode.JUDGEMENT]:
		var dt: float = delta * haste
		_t += dt
		_fire_events()
		_drive(dt)
	_flash_step(delta)
	if multiplayer.is_server():
		_host_step(delta)


func _flash_step(delta: float) -> void:
	if _flash <= 0.0 and _flash_layer == null:
		return
	if _flash > 0.0 and _flash_layer == null:
		_flash_layer = CanvasLayer.new()
		_flash_layer.layer = 54
		_flash_rect = ColorRect.new()
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_layer.add_child(_flash_rect)
		add_child(_flash_layer)
	_flash = maxf(_flash - delta * 2.6, 0.0)
	if _flash_rect != null:
		_flash_rect.color = Color(0.93, 0.85, 1.0, _flash * 0.85)
		if _flash <= 0.0:
			_flash_layer.queue_free()
			_flash_layer = null
			_flash_rect = null


## The body and the field while an act is on: positions, wings, charge.
func _drive(delta: float) -> void:
	match mode:
		Mode.ACTING:
			_drive_act(delta)
		Mode.FALLING:
			var fall: float = _num("rest", "fall_time")
			var s: float = clampf(_t / fall, 0.0, 1.0)
			boss.puppet_pos = _fall_from.lerp(_fall_to, 1.0 - pow(1.0 - s, 2.0))
			boss.puppet_height = _base_h * (1.0 - s * s)
		Mode.RISING:
			var rise: float = _num("finisher", "rise")
			var s2: float = smoothstep(0.0, 1.0, clampf(_t / rise, 0.0, 1.0))
			boss.puppet_height = lerpf(0.0, _num("finisher", "rise_height"), s2)
			boss.puppet_pos = _fall_to
		Mode.TRANSITION:
			_drive_transition()
		Mode.JUDGEMENT:
			_drive_judgement()
	boss.rig.raise_r = _raise_of(0)
	boss.rig.raise_l = _raise_of(1)
	boss.rig.charge = _charge
	boss.rig.fatigue = _fatigue


## The raise of a wing: the act's own raise, snapped down for a moment by every beat (the wing beats when a feather leaves it).
func _raise_of(si: int) -> float:
	if not (_wing == si or _wing == 2):
		return 0.0
	var t: float = _kick_t[si]
	var k: float = t / 0.06 if t < 0.06 else maxf(0.0, 1.0 - (t - 0.06) / 0.3)
	return _raise * (1.0 - 0.8 * k * _kick_amp[si])


## Does the body move fast enough to be rebuilt 60 times a second? (the rig costs about 9 ms a rebuild: 30 a second is enough for a charge, a rest, a lying body)
func wants_fast() -> bool:
	match mode:
		Mode.ACTING:
			return act in [Act.CHASE, Act.BARRIER, Act.PINCER, Act.DIVE] or _kick_t[0] < 0.45 or _kick_t[1] < 0.45
		Mode.FALLING, Mode.RISING, Mode.BREAKING, Mode.MOVING, Mode.TRANSITION:
			return true
		Mode.FINISHING:
			return _t < 0.8
	return false


func _kick_wing(si: int, amp: float) -> void:
	_kick_t[si] = 0.0
	_kick_amp[si] = amp
	boss.play_wing()


## Where a feather leaves a wing: the tip of blade `idx` of wing `si`, as a point of the picture and as ground + height for the field.
func _wing_origin(si: int, idx: int) -> Dictionary:
	var tips: PackedVector2Array = boss.rig.blade_tips(si)
	var root: Vector2 = boss.global_position
	var screen: Vector2 = boss.rig.global_position + (tips[clampi(idx, 0, tips.size() - 1)] if not tips.is_empty() else Vector2(0.0, -20.0))
	return {"screen": screen, "ground": Vector2(screen.x, root.y), "h": root.y - screen.y}


func _drive_act(delta: float) -> void:
	match act:
		Act.BARRIER:
			var b: Dictionary = _sp("barrier")
			var up: float = smoothstep(0.0, 0.5, _t)
			var down: float = smoothstep(float(b["end"]) - 0.7, float(b["end"]), _t)
			_lift = float(b["lift"]) * up * (1.0 - down)
			_raise = smoothstep(0.05, 0.55, _t) * (1.0 - smoothstep(float(b["end"]) - 1.0, float(b["end"]) - 0.5, _t))
			_charge = smoothstep(0.05, 0.6, _t) * (1.0 - smoothstep(float(b["end"]) - 0.9, float(b["end"]) - 0.4, _t))
		Act.RAIN:
			var r: Dictionary = _sp("rain")
			var rise: float = float(r["rise"])
			var fall_at: float = _rain_end
			var lift_up: float = smoothstep(0.0, rise, _t)
			var lift_down: float = smoothstep(fall_at, fall_at + 0.6, _t)
			_lift = float(r["lift"]) * lift_up * (1.0 - lift_down)
			var ready_at: float = float(r["first_warn"]) + 0.2
			_raise = smoothstep(0.05, ready_at, _t) * (1.0 - smoothstep(fall_at - 0.3, fall_at + 0.3, _t))
			_charge = smoothstep(0.05, ready_at + 0.1, _t) * (1.0 - smoothstep(fall_at - 0.5, fall_at + 0.3, _t))
			_fatigue = smoothstep(fall_at, fall_at + 0.7, _t) * (1.0 - smoothstep(_droop_from + float(r["droop"]) - 0.6, _droop_from + float(r["droop"]), _t))
			var droop: bool = _t > fall_at + 0.5 and _t < _droop_from + float(r["droop"])
			boss.set_combat(droop, float(_sp("armour")["droop"]) if droop else 1.0)
		Act.SHOT, Act.LINE:
			var s: Dictionary = _sp("shot" if act == Act.SHOT else "line")
			var fire_at: float = float(s["charge"])
			var up2: float = smoothstep(0.0, fire_at * 0.85, _t)
			var down2: float = smoothstep(fire_at + 0.05, fire_at + 0.5, _t)
			_raise = up2 * (1.0 - down2)
			_charge = smoothstep(0.0, fire_at, _t) * (1.0 - smoothstep(fire_at, fire_at + 0.4, _t))
			boss.set_combat(true, float(_sp("armour")["shot"]) if _t < fire_at else 1.0)
		Act.PINCER:
			var pc: Dictionary = _sp("pincer")
			var pfire: float = float(pc["charge"])
			var pup: float = smoothstep(0.0, pfire * 0.85, _t)
			var pdown: float = smoothstep(pfire + float(pc["swap"]) + 0.05, pfire + float(pc["swap"]) + 0.5, _t)
			_raise = pup * (1.0 - pdown)
			_charge = smoothstep(0.0, pfire, _t) * (1.0 - smoothstep(pfire + float(pc["swap"]), pfire + float(pc["swap"]) + 0.4, _t))
			boss.set_combat(true, float(_sp("armour")["shot"]) if _t < pfire else 1.0)
		Act.HANDS:
			var hd: Dictionary = _sp("hands")
			var hend: float = float(hd["warn"]) + float(hd["sweep"])
			_raise = smoothstep(0.0, float(hd["charge"]), _t) * (1.0 - smoothstep(hend - 0.1, hend + 0.35, _t))
			_charge = smoothstep(0.0, float(hd["warn"]), _t) * (1.0 - smoothstep(hend - 0.2, hend + 0.3, _t))
			boss.set_combat(true, float(_sp("armour")["shot"]))
		Act.CAGE:
			var cg: Dictionary = _sp("cage")
			var cfire: float = float(cg["charge"])
			var cend: float = cfire + float(cg["close_after"]) + float(cg["close_time"])
			_raise = smoothstep(0.0, cfire * 0.85, _t) * (1.0 - smoothstep(cend - 0.5, cend, _t))
			_charge = smoothstep(0.0, cfire, _t) * (1.0 - smoothstep(cend - 0.4, cend + 0.2, _t))
			boss.set_combat(true, float(_sp("armour")["shot"]) if _t < cend - 0.6 else 1.0)
		Act.BLAST:
			var bl: Dictionary = _sp("blast")
			var hit_at: float = float(bl["warn"])
			_raise = smoothstep(0.0, hit_at - 0.05, _t) * (1.0 - smoothstep(hit_at, hit_at + 0.14, _t))
			_charge = smoothstep(0.0, hit_at, _t) * (1.0 - smoothstep(hit_at, hit_at + 0.3, _t))
			boss.set_combat(true, 1.0)
		Act.CHASE:
			_drive_chase(delta)
		Act.DIVE:
			_drive_dive(delta)
		Act.GLUT:
			var gl: Dictionary = _sp("glut")
			var gfire: float = float(gl["charge"])
			_raise = smoothstep(0.0, gfire * 0.85, _t) * (1.0 - smoothstep(_glut_end, _glut_end + 0.4, _t))
			_charge = smoothstep(0.0, gfire, _t) * (1.0 - smoothstep(_glut_end, _glut_end + 0.4, _t))
			boss.set_combat(true, float(_sp("armour")["shot"]) if _t < gfire else 1.0)
		Act.SPLITTER:
			var sp: Dictionary = _sp("splitter")
			var sp_up: float = smoothstep(0.0, float(sp["rise"]), _t)
			var sp_down: float = smoothstep(_rain_end, _rain_end + 0.6, _t)
			_lift = float(sp["lift"]) * sp_up * (1.0 - sp_down)
			_raise = smoothstep(0.05, 0.5, _t) * (1.0 - smoothstep(_rain_end - 0.3, _rain_end + 0.3, _t))
			_charge = smoothstep(0.05, 0.6, _t) * (1.0 - smoothstep(_rain_end - 0.5, _rain_end + 0.3, _t))
			_fatigue = smoothstep(_rain_end, _rain_end + 0.7, _t) * (1.0 - smoothstep(_droop_from + float(sp["droop"]) - 0.6, _droop_from + float(sp["droop"]), _t))
			var sp_droop: bool = _t > _rain_end + 0.5 and _t < _droop_from + float(sp["droop"])
			boss.set_combat(sp_droop, float(_sp("armour")["droop"]) if sp_droop else 1.0)
		Act.MARK:
			var mk: Dictionary = _sp("mark")
			var mk_cast: float = float(mk["charge"])
			_raise = smoothstep(0.0, mk_cast * 0.85, _t) * (1.0 - smoothstep(_mark_end - 0.6, _mark_end - 0.1, _t))
			_charge = smoothstep(0.0, mk_cast, _t) * (1.0 - smoothstep(_mark_end - 0.5, _mark_end, _t))
			boss.set_combat(true, float(_sp("armour")["shot"]) if _t < mk_cast else 1.0)
	if act != Act.CHASE and act != Act.DIVE:
		boss.puppet_pos = _base_pos
		boss.puppet_height = _base_h + _lift


# --- the host: what next -------------------------------------------------------------------------------------------


func _host_step(delta: float) -> void:
	_blast_cd -= delta
	if phase >= 2:
		_record_trails(delta)
		_host_edge_check()
	if _opening_left >= 0.0:
		if boss.intro_running() or boss.state != SkyCleaver.State.PERCHED:
			_opening_left = _num("barrier", "delay")
		else:
			_opening_left -= delta
			if _opening_left < 0.0:
				_opening_left = -1.0
				_rpc_act.rpc(Act.BARRIER, _pick.randi(), Vector2.ZERO, Vector2.ZERO, 0, 1.0)
	if mode == Mode.IDLE:
		_gap -= delta
		if boss.state == SkyCleaver.State.PERCHED:
			var close: bool = false
			for player: Player in _living():
				if player.global_position.distance_to(boss.global_position) < _num("blast", "trigger_range"):
					close = true
			_near_t = _near_t + delta if close else maxf(_near_t - delta * 2.0, 0.0)
			if _gap <= 0.0:
				_choose()
	if _rift_up() and mode in [Mode.IDLE, Mode.ACTING, Mode.MOVING]:
		_host_rift(delta)
	if _kill_at >= 0.0 and _t >= _kill_at and mode == Mode.JUDGEMENT:
		_kill_at = -1.0
		_judge_kill()
	if mode in [Mode.IDLE, Mode.ACTING, Mode.MOVING, Mode.REST, Mode.DOWNED, Mode.TRANSITION, Mode.JUDGEMENT]:
		_watch_players(delta)


## Everybody left or died: after a while the fight resets (the boss goes, the feathers go, the pillars stand again, the arena waits for the next one).
func _watch_players(delta: float) -> void:
	_watch_acc += delta
	if _watch_acc < 0.25:
		return
	delta = _watch_acc
	_watch_acc = 0.0
	var any: bool = false
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(boss.centre()) < _num("reset", "radius"):
			any = true
			break
	_away = 0.0 if any else _away + delta
	if _away >= _num("reset", "after"):
		boss.request_reset()


func _choose() -> void:
	if mode != Mode.IDLE:
		return
	var floor_value: float = boss.health_floor()
	if phase < (_spec["phases"] as Array).size() and boss.health_now() <= floor_value + 0.01:
		_begin_break_host()
		return
	if _blast_cd <= 0.0 and _near_t >= _num("blast", "trigger_time"):
		_near_t = 0.0
		_blast_cd = _num("blast", "cooldown")
		_rpc_act.rpc(Act.BLAST, _pick.randi(), Vector2.ZERO, Vector2.ZERO, 0, _haste_now())
		return
	var order: Array = _rotation()
	var name: String = String(order[_rot % order.size()])
	_rot += 1
	_combo = name.ends_with("+")
	name = name.trim_suffix("+")
	var hs: float = _haste_now()
	match name:
		"shot":
			var target: Player = _pick_target()
			if target == null:
				_gap = 1.0
				return
			var kind: Act = Act.LINE if _pick.randf() < float(_spec["line_chance"]) else Act.SHOT
			_rpc_act.rpc(kind, _pick.randi(), target.global_position, Vector2.ZERO, int(target.name), hs)
		"rain":
			_rpc_act.rpc(Act.RAIN, _pick.randi(), Vector2.ZERO, Vector2.ZERO, _pick.randi() % 4, hs)
		"chase":
			var chased: Player = _pick_target()
			if chased == null:
				_gap = 1.0
				return
			_rpc_act.rpc(Act.CHASE, _pick.randi(), boss.global_position, chased.global_position, int(chased.name), hs)
		"pincer":
			var twin: Player = _pick_target()
			if twin == null:
				_gap = 1.0
				return
			_rpc_act.rpc(Act.PINCER, _pick.randi(), twin.global_position, Vector2.ZERO, int(twin.name), hs)
		"hands":
			_rpc_act.rpc(Act.HANDS, _pick.randi(), Vector2.ZERO, Vector2.ZERO, 0, hs)
		"dive":
			var diver: Player = _pick_target()
			if diver == null:
				_gap = 1.0
				return
			_rpc_act.rpc(Act.DIVE, _pick.randi(), diver.global_position, Vector2.ZERO, int(diver.name), hs)
		"glut":
			var thrown: Player = _pick_target()
			if thrown == null:
				_gap = 1.0
				return
			_rpc_act.rpc(Act.GLUT, _pick.randi(), thrown.global_position, Vector2.ZERO, int(thrown.name), hs)
		"splitter":
			if _living().is_empty():
				_gap = 1.0
				return
			_rpc_act.rpc(Act.SPLITTER, _pick.randi(), Vector2.ZERO, Vector2.ZERO, 0, hs)
		"mark":
			var branded: Player = _pick_target()
			if branded == null:
				_gap = 1.0
				return
			_rpc_act.rpc(Act.MARK, _pick.randi(), branded.global_position, Vector2.ZERO, int(branded.name), hs)
		"cage":
			var caged: Player = _pick_target()
			if caged == null:
				_gap = 1.0
				return
			_rpc_act.rpc(Act.CAGE, _pick.randi(), caged.global_position, Vector2.ZERO, int(caged.name), hs)
		"move":
			_move_host()


func _pick_target() -> Player:
	var living: Array[Player] = _living()
	if living.is_empty():
		return null
	var choices: Array[Player] = []
	for player: Player in living:
		if int(player.name) != _last_target or living.size() == 1:
			choices.append(player)
	if choices.is_empty():
		choices = living
	var target: Player = choices[_pick.randi() % choices.size()]
	if _pick.randf() < 0.5: ## half of the time the nearest one
		var best: float = 1e9
		for player: Player in choices:
			var d: float = player.global_position.distance_to(boss.global_position)
			if d < best:
				best = d
				target = player
	_last_target = int(target.name)
	return target


func _move_host() -> void:
	var options: Array[int] = []
	for i: int in boss.pillar_count():
		if i != boss.perched_on() and not boss.pillar_broken(i):
			options.append(i)
	if options.is_empty():
		_gap = 1.0
		return
	_rpc_move.rpc()
	boss.host_fly_to(options[_pick.randi() % options.size()], false)


@rpc("authority", "call_local", "reliable")
func _rpc_move() -> void:
	mode = Mode.MOVING


## The boss touched down on its pillar for the first time: after a moment the opening act starts.
func on_touched_down() -> void:
	if not multiplayer.is_server() or _started:
		return
	_started = true
	_opening_left = _num("barrier", "delay")
	_set_world_directors_active(false)
	_rpc_started.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_started() -> void:
	_started = true
	_set_world_directors_active(false)
	if mode == Mode.WAIT:
		mode = Mode.IDLE
		_gap = 99.0 ## nothing before the opening


## The boss perched (a flight ended). Every peer.
func on_perched() -> void:
	match mode:
		Mode.MOVING:
			mode = Mode.IDLE
			_gap = _pick_gap()
		Mode.BREAKING:
			if boss.perched_on() == _break_pillar:
				_begin_rest()
		Mode.RISING:
			mode = Mode.IDLE
			_gap = 2.5


# --- acts (every peer) ---------------------------------------------------------------------------------------------


@rpc("authority", "call_local", "reliable")
func _rpc_act(kind: int, seed_v: int, a: Vector2, b: Vector2, n: int, speed: float) -> void:
	if mode not in [Mode.IDLE, Mode.WAIT]:
		return
	haste = clampf(speed, 1.0, 1.5)
	field.time_scale = haste
	act = kind as Act
	mode = Mode.ACTING
	_t = 0.0
	_events.clear()
	_rng.seed = seed_v
	field.clear_marks()
	_base_pos = boss._perch_pos(boss.perched_on())
	_base_h = boss._perch_height(boss.perched_on())
	_clear_body()
	_wing = 2
	boss.enter_act(_base_pos, _base_h)
	boss.set_combat(false, 1.0)
	match act:
		Act.BARRIER:
			_start_barrier()
		Act.RAIN:
			_start_rain(n)
		Act.SHOT, Act.LINE:
			_start_shot(a, n)
		Act.CHASE:
			_start_chase(n)
		Act.BLAST:
			_start_blast()
		Act.PINCER:
			_start_pincer(a, n)
		Act.HANDS:
			_start_hands()
		Act.CAGE:
			_start_cage(a, n)
		Act.DIVE:
			_start_dive(a, n)
		Act.GLUT:
			_start_glut(a, n)
		Act.SPLITTER:
			_start_splitter()
		Act.MARK:
			_start_mark(a, n)


func _end_act() -> void:
	act = Act.NONE
	mode = Mode.IDLE
	haste = 1.0
	field.time_scale = 1.0
	_clear_body()
	boss.settle_on_perch()
	if multiplayer.is_server() and (_combo or _hurry):
		_gap = 0.8 if _combo else 0.6 ## (was 0.06 / 0.12: area attacks came back to back) the second half of a combination follows at once; the rift's gap is open: attack now
		_combo = false
		_hurry = false
		return
	_gap = _pick_gap() if multiplayer.is_server() else 99.0


# -- BARRIER --------------------------------------------------------------------------------------------------------


func _start_barrier() -> void:
	var b: Dictionary = _sp("barrier")
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 0.0, 0.8)
	var volley: int = 0
	for entry: Dictionary in boss.barrier_spec():
		_at(float(b["first"]) + float(volley) * float(b["between"]), _throw_volley.bind(entry))
		volley += 1
	_at(float(b["end"]), _finish_barrier)


func _throw_volley(entry: Dictionary) -> void:
	var b: Dictionary = _sp("barrier")
	var feathers: Array = entry["feathers"] as Array
	var solid: Array = entry["solid"] as Array
	_sound("feather_launch", _base_pos, 0.0, 0.9)
	for i: int in feathers.size():
		var spot: Array = feathers[i] as Array
		var dst: Vector2 = boss.arena_origin + Vector2(float(spot[0]), float(spot[1]))
		_at(_t + 0.05 + float(i) * float(b["stagger"]), _launch_barrier_feather.bind(i, dst, Vector2(float(solid[0]), float(solid[1])), int(_rng.randi() % 6), int(_rng.randi() % 4), (_rng.randf() - 0.5) * 0.4))


## One feather leaves a wing (the wing beats), flies out fast and plants itself in the way.
func _launch_barrier_feather(i: int, dst: Vector2, solid: Vector2, extra: int, variant: int, lean: float) -> void:
	var b: Dictionary = _sp("barrier")
	var wing: int = i % 2
	_kick_wing(wing, 1.0)
	var origin: Dictionary = _wing_origin(wing, 1 + (i / 2) % 4)
	var now: float = field.now()
	var land: float = now + float(b["fly"])
	field.add_flight(origin["ground"] as Vector2, float(origin["h"]), dst, 0.0, now, land, VoidFeather.THROWN, variant, 0.0, 0.0, 0.0, 9.0, Vector2i.ZERO, true)
	field.add_sparks(origin["screen"] as Vector2, 7)
	field.add_ring(dst, float(b["radius"]), 0.0, now, land, float(b["damage"]), 140.0)
	get_tree().create_timer(float(b["fly"])).timeout.connect(_plant.bind(dst, VoidFeather.BARRIER_LENGTHS[extra % 3], VoidFeather.BARRIER_WIDTH, variant, lean, solid))
	if i % 2 == 0:
		_sound("feather_launch", origin["screen"] as Vector2, -4.0, randf_range(1.0, 1.25))


func _plant(dst: Vector2, length: int, width: int, variant: int, lean: float, solid: Vector2) -> void:
	if not is_instance_valid(boss) or not is_inside_tree():
		return
	var feather: StuckFeather = StuckFeather.plant(boss.get_parent(), dst, length, width, variant, lean, solid, true, _stuck.size())
	_stuck.append(feather)
	if _stuck.size() % 3 == 0:
		boss.shake_near(dst, 0.7)
		_sound("feather_stick", dst, -2.0, randf_range(0.95, 1.2))


func _finish_barrier() -> void:
	barrier_done = true
	_end_act()
	if multiplayer.is_server():
		_gap = 1.6
		if phase >= 2:
			_rpc_start_phase_three.rpc() ## the fight began at the third phase: the transition (the push, the scream, the fire) plays again
		elif phase >= 1 and not _rift_up():
			_rpc_start_phase_two.rpc() ## the fight began at the second phase (after a wipe): the look turns and the rift tears open


# -- RAIN -----------------------------------------------------------------------------------------------------------

const RAIN_SCRIPTS: Array = [
	[["cols", 1, 0.0], ["cols", -1, 0.5], ["rings", 1, 0.0]],
	[["rows", 1, 0.0], ["rows", -1, 0.5], ["rings", -1, 0.3]],
	[["diag", 1, 0.0], ["diag", -1, 0.5], ["cols", 1, 0.25]],
	[["rings", 1, 0.0], ["cols", -1, 0.0], ["rows", 1, 0.5]],
]


## Phase 2: the waves mirror over the rift (strips parallel to it, equally far from it on both sides, so both halves are hit at once).
const RAIN_SCRIPTS_RIFT: Array = [
	[["mirror", 1, 0.0], ["mirror", -1, 0.5], ["mirror", 1, 0.25]],
	[["mirror", -1, 0.0], ["mirror", 1, 0.4], ["rings", 1, 0.0]],
	[["mirror", 1, 0.5], ["rings", -1, 0.0], ["mirror", -1, 0.0]],
]


func _start_rain(script: int) -> void:
	var r: Dictionary = _sp("rain")
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 0.0, 1.0)
	_wing = 2
	_charge = 0.0
	boss.rig.charge_kind = 0
	var scripts: Array = RAIN_SCRIPTS_RIFT if phase >= 1 and _rift_up() else RAIN_SCRIPTS
	var waves: Array = scripts[script % scripts.size()] as Array
	if phase >= 2:
		waves = _rain_waves_final()
	var wave_count: int = mini(int(r["waves"]), waves.size())
	var last_hit: float = 0.0
	for w: int in wave_count:
		var wave: Array = waves[w] as Array
		var warn_at: float = float(r["first_warn"]) + float(w) * float(r["wave_gap"])
		var hit_at: float = warn_at + float(r["warn"])
		_at(warn_at, _announce_wave.bind(String(wave[0]), int(wave[1]), float(wave[2]), hit_at - warn_at, wave[3] as Vector2 if wave.size() > 3 else Vector2.INF))
		last_hit = hit_at + 0.7
		_at(hit_at - 0.35, _sound.bind("rain", _base_pos, -3.0, 1.0 + 0.08 * float(w)))
		_at(hit_at - 0.42, _rain_beat)
	_rain_end = last_hit
	_droop_from = _rain_end + 0.6
	_at(_rain_end + 0.3, _rain_lands)
	_at(_droop_from + float(r["droop"]), _end_act)


## The long rain of phase 3: seven waves one after the other: vertical strips, rings from the middle, diagonal strips leaning left (sweeping to the left), rings from a second
## point, diagonal strips leaning right (sweeping to the right), rings from a third point, horizontal strips. The points are in `fight.p3.rain.origins` (relative to the
## sun sigil); the offsets of the strips are drawn from the act's seed.
func _rain_waves_final() -> Array:
	var origins: Array = _sp("rain")["origins"] as Array
	var middle: Vector2 = boss.arena_middle()
	var o0: Vector2 = middle + Vector2(float((origins[0] as Array)[0]), float((origins[0] as Array)[1]))
	var o1: Vector2 = middle + Vector2(float((origins[1] as Array)[0]), float((origins[1] as Array)[1]))
	var o2: Vector2 = middle + Vector2(float((origins[2] as Array)[0]), float((origins[2] as Array)[1]))
	return [
		["cols", 1, _rng.randf(), Vector2.INF],
		["rings", 1, 0.0, o0],
		["diag_l", -1, _rng.randf(), Vector2.INF],
		["rings", -1, 0.0, o1],
		["diag_r", 1, _rng.randf(), Vector2.INF],
		["rings", 1, 0.0, o2],
		["rows", -1, _rng.randf(), Vector2.INF],
	]


func _rain_beat() -> void:
	_kick_wing(0, 0.55)
	_kick_wing(1, 0.55)
	field.add_sparks(_wing_origin(0, 3)["screen"] as Vector2, 4)
	field.add_sparks(_wing_origin(1, 3)["screen"] as Vector2, 4)


func _rain_lands() -> void:
	boss.set_pose(SkyCleaverRig.Pose.SPENT, 60.0)


func _lane_has_floor(a: Vector2, b: Vector2) -> bool:
	var steps: int = maxi(2, int(a.distance_to(b) / 14.0))
	for i: int in steps + 1:
		if field.on_floor(a.lerp(b, float(i) / float(steps))):
			return true
	return false


## All the shapes of one wave of the rain, in the order they hit (the sweep). Pure function of the arena and the parameters.
func rain_shapes(kind: String, dir: int, phase_k: float, origin: Vector2 = Vector2.INF) -> Array[Dictionary]:
	var rect: Rect2 = boss.arena_rect()
	var strip: float = _num("rain", "strip") + minf(3.0 * float(_extra()), 9.0)
	var shapes: Array[Dictionary] = []
	match kind:
		"cols", "rows":
			var cols: bool = kind == "cols"
			var period: float = 84.0 if cols else 82.0
			var lo: float = rect.position.x if cols else rect.position.y
			var hi: float = rect.end.x if cols else rect.end.y
			var o: float = lo + phase_k * period
			var j: int = 0
			while o + float(j) * period < hi + strip:
				for s: int in 2:
					var centre: float = o + float(j) * period + strip * (float(s) + 0.5)
					if centre > hi + strip or centre < lo - strip:
						continue
					if cols:
						shapes.append({"type": 0, "a": Vector2(centre, rect.position.y - 20.0), "b": Vector2(centre, rect.end.y + 20.0), "w": strip * 0.5, "inner": 0.0, "key": centre})
					else:
						shapes.append({"type": 0, "a": Vector2(rect.position.x - 20.0, centre), "b": Vector2(rect.end.x + 20.0, centre), "w": strip * 0.5, "inner": 0.0, "key": centre})
				j += 1
		"diag", "diag_l", "diag_r":
			var period2: float = 92.0
			var leaning_left: bool = kind == "diag_l" ## "\\" lanes; "diag" and "diag_r" are "/" lanes
			var u: Vector2 = Vector2(1.0, -1.0).normalized() if leaning_left else Vector2(1.0, 1.0).normalized()
			var v: Vector2 = Vector2(1.0, 1.0).normalized() if leaning_left else Vector2(-1.0, 1.0).normalized()
			var kmin: float = 1e9
			var kmax: float = -1e9
			for corner: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
				kmin = minf(kmin, corner.dot(u))
				kmax = maxf(kmax, corner.dot(u))
			var j2: int = 0
			while kmin + phase_k * period2 + float(j2) * period2 < kmax + strip:
				for s2: int in 2:
					var kc: float = kmin + phase_k * period2 + float(j2) * period2 + strip * (float(s2) + 0.5)
					var mid: Vector2 = u * kc + v * rect.get_center().dot(v) ## the lane runs along v through the arena, not through the world's origin
					shapes.append({"type": 0, "a": mid - v * 420.0, "b": mid + v * 420.0, "w": strip * 0.5, "inner": 0.0, "key": kc})
				j2 += 1
		"mirror":
			var period4: float = float(_sp("rain").get("period", 84.0))
			var along: Vector2 = rift.direction()
			var across: Vector2 = rift.normal()
			var mid4: Vector2 = rift.middle()
			var d0: float = 12.0 + phase_k * period4
			var j4: int = 0
			while d0 + float(j4) * period4 < 330.0:
				for s4: int in 2:
					var dist: float = d0 + float(j4) * period4 + strip * (float(s4) + 0.5)
					for side: float in [-1.0, 1.0]:
						var a4: Vector2 = mid4 + across * side * dist - along * 380.0
						var b4: Vector2 = mid4 + across * side * dist + along * 380.0
						if _lane_has_floor(a4, b4):
							shapes.append({"type": 0, "a": a4, "b": b4, "w": strip * 0.5, "inner": 0.0, "key": dist})
				j4 += 1
		"rings":
			var period3: float = 74.0
			var width3: float = strip + 20.0
			var centre3: Vector2 = origin if origin.is_finite() else rect.get_center()
			var reach: float = rect.size.length() * (1.0 if origin.is_finite() else 0.5)
			var k: int = 0
			while phase_k * period3 + float(k) * period3 < reach:
				var r_in: float = phase_k * period3 + float(k) * period3
				shapes.append({"type": 1, "a": centre3, "b": Vector2.ZERO, "w": r_in + width3, "inner": r_in, "key": r_in})
				k += 1
	shapes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["key"]) < float(b["key"]) if dir > 0 else float(a["key"]) > float(b["key"]))
	return shapes


func _announce_wave(kind: String, dir: int, phase_k: float, warn: float, origin: Vector2 = Vector2.INF) -> void:
	var r: Dictionary = _sp("rain")
	var shapes: Array[Dictionary] = rain_shapes(kind, dir, phase_k, origin)
	var base: float = field.now()
	var hit: float = base + warn
	var rank: int = 0
	var last_key: float = -1e9
	for i: int in shapes.size():
		var shape: Dictionary = shapes[i]
		if i > 0 and absf(float(shape["key"]) - last_key) > 0.5: ## strips with the same key (both sides of the rift) hit together
			rank += 1
		last_key = float(shape["key"])
		var t_hit: float = hit + float(rank) * float(r["strip_step"])
		if int(shape["type"]) == 0:
			field.add_lane(shape["a"] as Vector2, shape["b"] as Vector2, float(shape["w"]), base, t_hit, float(r["damage"]), float(r["knock"]))
			_rain_feathers_lane(shape, t_hit)
			if kind == "mirror" and rank % 2 == 0:
				_puddle(shape, t_hit, r)
		else:
			field.add_ring(shape["a"] as Vector2, float(shape["w"]), float(shape["inner"]), base, t_hit, float(r["damage"]), float(r["knock"]))
			_rain_feathers_ring(shape, t_hit)


## Where a strip came down the void stays for a while: a puddle that hurts every half second and narrows the floor.
func _puddle(shape: Dictionary, t_hit: float, r: Dictionary) -> void:
	var ticks: PackedFloat32Array = PackedFloat32Array()
	for n: int in range(1, int(r["puddle_ticks"])):
		ticks.append(t_hit + 0.05 + 0.5 * float(n))
	field.add_lane(shape["a"] as Vector2, shape["b"] as Vector2, float(r["puddle_half"]), t_hit, t_hit + 0.05, float(r["puddle_damage"]), 40.0, 1, ticks)


func _rain_feathers_lane(shape: Dictionary, t_hit: float) -> void:
	var a: Vector2 = shape["a"] as Vector2
	var b: Vector2 = shape["b"] as Vector2
	var half: float = float(shape["w"])
	var across: Vector2 = (b - a).orthogonal().normalized()
	var length: float = a.distance_to(b)
	var placed: int = 0
	for attempt: int in 70:
		if placed >= 14:
			break
		var p: Vector2 = a.lerp(b, _rng.randf()) + across * (_rng.randf() - 0.5) * half * 1.5
		if not field.on_floor(p):
			continue
		placed += 1
		field.add_fall(p, t_hit + _rng.randf_range(-0.05, 0.05), _rng.randi() % 4, int(_rng.randi() % 3) - 1)
	if length <= 0.0:
		return


func _rain_feathers_ring(shape: Dictionary, t_hit: float) -> void:
	var centre: Vector2 = shape["a"] as Vector2
	var outer: float = float(shape["w"])
	var inner: float = float(shape["inner"])
	var mid: float = (outer + inner) * 0.5
	var count: int = clampi(int(TAU * mid / 16.0), 8, 60)
	var offset: float = _rng.randf() * TAU
	for i: int in count:
		var angle: float = offset + TAU * float(i) / float(count)
		var p: Vector2 = centre + Vector2.from_angle(angle) * (mid + (_rng.randf() - 0.5) * (outer - inner) * 0.6)
		if not field.on_floor(p):
			continue
		field.add_fall(p, t_hit + _rng.randf_range(-0.05, 0.05), _rng.randi() % 4, int(_rng.randi() % 3) - 1)


## How much of the floor a wave covers: sampled on a grid (for the tests and for tuning).
func wave_coverage(kind: String, dir: int, phase_k: float, origin: Vector2 = Vector2.INF) -> float:
	var shapes: Array[Dictionary] = rain_shapes(kind, dir, phase_k, origin)
	var rect: Rect2 = boss.arena_rect()
	var floor_n: int = 0
	var hit_n: int = 0
	var y: float = rect.position.y
	while y < rect.end.y:
		var x: float = rect.position.x
		while x < rect.end.x:
			var p: Vector2 = Vector2(x, y)
			if field.on_floor(p):
				floor_n += 1
				for shape: Dictionary in shapes:
					if _shape_has(shape, p):
						hit_n += 1
						break
			x += 4.0
		y += 4.0
	return float(hit_n) / maxf(float(floor_n), 1.0)


func _shape_has(shape: Dictionary, p: Vector2) -> bool:
	if int(shape["type"]) == 0:
		return FeatherField._closest(p, shape["a"] as Vector2, shape["b"] as Vector2).distance_to(p) <= float(shape["w"])
	var r: float = p.distance_to(shape["a"] as Vector2)
	return r <= float(shape["w"]) and r >= float(shape["inner"])


# -- SHOT and LINE --------------------------------------------------------------------------------------------------


func _start_shot(target_pos: Vector2, target_id: int) -> void:
	var s: Dictionary = _sp("shot" if act == Act.SHOT else "line")
	var heading: float = (target_pos - _base_pos).angle()
	boss.look_point = target_pos
	# the aimed shot raises the wing that is on the left of the screen, the line the one on the right
	var right_is_left: bool = sin(heading) >= 0.0
	var left_wing: int = 0 if right_is_left else 1
	_left_wing = left_wing
	_wing = left_wing if act == Act.SHOT else 1 - left_wing
	boss.set_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
	boss.rig.charge_kind = 1 if act == Act.SHOT else 3
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, -2.0, 1.25 if act == Act.SHOT else 1.0)
	var player: Player = _by_id(target_id)
	if player != null:
		field.add_mark(player, field.now() + float(s["charge"]) + 0.2)
	if multiplayer.is_server():
		_at(float(s["charge"]) - float(s["lock_before"]), _host_lock)
	_at(float(s["charge"]) + 1.6, _end_shot_if_idle) ## the fire event (set by the lock) ends it; this is the safety net if the lock never arrived
	_shot_fired = false


var _shot_fired: bool = false


func _end_shot_if_idle() -> void:
	if mode == Mode.ACTING and act in [Act.SHOT, Act.LINE, Act.GLUT] and not _shot_fired:
		_end_act()


## Host: the aim locks shortly before the release: everybody learns where.
func _host_lock() -> void:
	var living: Array[Player] = _living()
	if living.is_empty():
		_rpc_lock.rpc(PackedVector2Array([boss.look_point if boss.look_point.is_finite() else boss.centre()]))
		return
	var points: PackedVector2Array = PackedVector2Array()
	var primary: Player = _by_id(_last_target)
	if primary == null or primary.health.current <= 0.0:
		primary = living[0]
	points.append(primary.global_position)
	if act == Act.SHOT or act == Act.GLUT:
		for player: Player in living:
			if points.size() >= mini(1 + _extra(), 5 if act == Act.GLUT else 3):
				break
			if player != primary:
				points.append(player.global_position)
	elif act == Act.PINCER: ## the second wing takes the other player (alone: the same one, a little off)
		for player: Player in living:
			if player != primary:
				points.append(player.global_position)
				break
	_rpc_lock.rpc(points)


@rpc("authority", "call_local", "reliable")
func _rpc_lock(points: PackedVector2Array) -> void:
	if mode != Mode.ACTING or act not in [Act.SHOT, Act.LINE, Act.PINCER, Act.CAGE, Act.GLUT] or _shot_fired:
		return
	_shot_fired = true
	boss.look_point = points[0]
	var now: float = field.now()
	match act:
		Act.PINCER:
			var pc: Dictionary = _sp("pincer")
			var plock: float = float(pc["lock_before"])
			_lock_pincer(points, now, plock, pc)
			_at(_t + plock + float(pc["swap"]) + float(pc["recover"]) + 0.55, _end_act)
		Act.GLUT:
			_lock_glut(points, now, float(_sp("glut")["lock_before"]), _sp("glut"))
		Act.CAGE:
			var cg: Dictionary = _sp("cage")
			var clock_s: float = float(cg["lock_before"])
			_lock_cage(points[0], now, clock_s, cg)
			_at(_t + clock_s + float(cg["close_after"]) + float(cg["close_time"]) + float(cg["burst_after"]) + float(cg["recover"]) + 0.3, _end_act)
		_:
			var s: Dictionary = _sp("shot" if act == Act.SHOT else "line")
			var lock: float = float(s["lock_before"])
			if act == Act.SHOT:
				for point: Vector2 in points:
					_lock_shot(point, now, lock, s)
			else:
				_lock_line(points[0], now, lock, s)
			_at(_t + lock + float(s["recover"]) + (0.5 if act == Act.SHOT else 0.7), _end_act)
			_at(_t + lock, _sound.bind("feather_launch", _base_pos, 0.0, 1.0))


## The aimed shot: the wing beats at the release, the feather leaves it, flies to the locked spot, hits whoever it passes, stays stuck, bursts after a fuse and leaves a zone.
## `wing` -1 = the act's wing; `delay` = seconds after the lock.
func _lock_shot(point: Vector2, now: float, lock: float, s: Dictionary, wing: int = -1, delay: float = 0.0) -> void:
	var distance: float = _base_pos.distance_to(point)
	var t0: float = now + lock + delay
	var t1: float = t0 + maxf(distance / float(s["speed"]), 0.25)
	var fuse: float = float(s["fuse"])
	var patch: Vector2i = Vector2i(40, 28)
	field.add_ring(point, float(s["zone_radius"]), 0.0, now + lock * 0.5, t1 + fuse, float(s["zone_damage"]), 120.0, 0, PackedFloat32Array(), patch)
	var ticks: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(2, int(s["ticks"]) + 1):
		ticks.append(t1 + fuse + 0.5 * float(i))
	field.add_ring(point, float(s["zone_radius"]), 0.0, t1 + fuse, t1 + fuse + 0.5, float(s["tick_damage"]), 40.0, 1, ticks)
	_at(_t + lock + delay, _fire_shot.bind(point, t1, int(_rng.randi() % 4), s, wing if wing >= 0 else _wing))
	_at(_t + lock + delay + (t1 - t0), _sound.bind("feather_stick", point, 0.0, 1.0))
	_at(_t + lock + delay + (t1 - t0) + fuse, _sound.bind("feather_hit", point, 0.0, 0.8))


func _fire_shot(point: Vector2, t1: float, variant: int, s: Dictionary, wing: int) -> void:
	_kick(0.3)
	_kick_wing(wing, 1.0)
	var origin: Dictionary = _wing_origin(wing, 2)
	field.add_flight(origin["ground"] as Vector2, float(origin["h"]), point, 0.0, field.now(), t1, VoidFeather.SHOT, variant, float(s["fuse"]) + 0.15, float(s["damage"]), float(s["knock"]), float(s["radius"]), VoidFeather.SHOT_STUCK, true)
	field.add_sparks(origin["screen"] as Vector2, 10)
	boss.shake_near(_base_pos, 0.5)
	_sound("feather_launch", origin["screen"] as Vector2, 2.0, 1.0)


## The line: from the boss through the locked spot, across the arena. The wing beats, a feather per segment leaves it and plants itself, segments hit one after the other, outwards.
func _lock_line(point: Vector2, now: float, lock: float, s: Dictionary, wing: int = -1, delay: float = 0.0) -> void:
	var dir: Vector2 = (point - _base_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var w: int = wing if wing >= 0 else _wing
	var length: float = float(s["length"])
	var count: int = int(s["segments"])
	var seg: float = length / float(count)
	var fire: float = now + float(s["warn"]) + delay
	var wing_src: Dictionary = _wing_origin(w, 2)
	field.add_beam(_base_pos + dir * 14.0, _base_pos + dir * (14.0 + length), wing_src["screen"] as Vector2, now, fire, float(count) * float(s["seg_step"]), 0.45, float(s["half_width"]), 1 if act == Act.PINCER else 0)
	_at(_t + float(s["warn"]) + delay, _kick.bind(0.35))
	for i: int in count:
		var a: Vector2 = _base_pos + dir * (14.0 + seg * float(i))
		var b: Vector2 = _base_pos + dir * (14.0 + seg * float(i + 1))
		var t_hit: float = fire + float(i) * float(s["seg_step"])
		field.add_lane(a, b, float(s["half_width"]), now, t_hit, float(s["damage"]), float(s["knock"]))
		var mid: Vector2 = (a + b) * 0.5 + dir.orthogonal() * (_rng.randf() - 0.5) * float(s["half_width"]) * 0.8
		if field.on_floor(mid):
			_at(_t + float(s["warn"]) + delay - 0.32 + float(i) * 0.03, _launch_line_feather.bind(i, mid, t_hit, int(_rng.randi() % 4), w))
	_at(_t + float(s["warn"]) + delay - 0.34, _sound.bind("rain", _base_pos + dir * 120.0, -2.0, 1.1))


func _launch_line_feather(i: int, dst: Vector2, t_hit: float, variant: int, wing: int) -> void:
	_kick_wing(wing, 0.8 if i > 0 else 1.0)
	var origin: Dictionary = _wing_origin(wing, 1 + i % 5)
	field.add_flight(origin["ground"] as Vector2, float(origin["h"]), dst, 0.0, field.now(), maxf(t_hit, field.now() + 0.18), VoidFeather.LINE, variant, 0.55, 0.0, 0.0, 9.0, VoidFeather.LINE_STUCK, true)
	field.add_sparks(origin["screen"] as Vector2, 4)


# -- PINCER ---------------------------------------------------------------------------------------------------------


func _start_pincer(target_pos: Vector2, target_id: int) -> void:
	var s: Dictionary = _sp("pincer")
	var heading: float = (target_pos - _base_pos).angle()
	boss.look_point = target_pos
	_left_wing = 0 if sin(heading) >= 0.0 else 1
	_wing = 2 ## both wings go up
	boss.set_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
	boss.rig.charge_kind = 1
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, -1.0, 1.4)
	var player: Player = _by_id(target_id)
	if player != null:
		field.add_mark(player, field.now() + float(s["charge"]) + 0.3)
	if multiplayer.is_server():
		_at(float(s["charge"]) - float(s["lock_before"]), _host_lock)
	_at(float(s["charge"]) + 1.6, _end_shot_if_idle)
	_shot_fired = false


## Two wings, two volleys: the left one an aimed shot at A, the right one a line through B; a moment later they swap (shot at B from the right, line through A from the left).
## Alone, A and B are the same player: the shot goes at him, the line passes him a little to one side, and the second volley mirrors it.
func _lock_pincer(points: PackedVector2Array, now: float, lock: float, s: Dictionary) -> void:
	var shot: Dictionary = s["shot"] as Dictionary
	var line: Dictionary = s["line"] as Dictionary
	var a: Vector2 = points[0]
	var b: Vector2 = points[1] if points.size() > 1 else a
	var wl: int = _left_wing
	var wr: int = 1 - wl
	var swap: float = float(s["swap"])
	var solo: bool = points.size() < 2 or a.distance_to(b) < 8.0
	if solo:
		var d1: Vector2 = (a - _base_pos).normalized()
		var off: float = float(s["offset_angle"])
		_lock_shot(a, now, lock, shot, wl, 0.0)
		_lock_line(_base_pos + d1.rotated(off) * 150.0, now, lock, line, wr, 0.0)
		_lock_shot(a + d1.orthogonal() * 20.0, now, lock, shot, wr, swap)
		_lock_line(_base_pos + d1.rotated(-off) * 150.0, now, lock, line, wl, swap)
	else:
		_lock_shot(a, now, lock, shot, wl, 0.0)
		_lock_line(b, now, lock, line, wr, 0.0)
		_lock_shot(b, now, lock, shot, wr, swap)
		_lock_line(a, now, lock, line, wl, swap)
	_at(_t + lock, _sound.bind("feather_launch", _base_pos, 0.0, 1.0))
	_at(_t + lock + swap, _sound.bind("feather_launch", _base_pos, 0.0, 1.15))


# -- HANDS ----------------------------------------------------------------------------------------------------------


## From every pillar that still stands a blade turns over the floor like the hand of a clock (120 degrees in 1.6 s): one clockwise, the other against it. Walk with it or
## against it: the area it will sweep is announced as a fan of lanes that light up one after the other.
func _start_hands() -> void:
	var s: Dictionary = _sp("hands")
	_wing = 2
	boss.set_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
	boss.rig.charge_kind = 0
	boss.look_point = Vector2.INF
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 0.0, 0.8)
	var warn: float = float(s["warn"])
	var sweep: float = float(s["sweep"])
	var half: float = deg_to_rad(float(s["angle"])) * 0.5
	var segs: int = int(s["segments"])
	var length: float = float(s["length"])
	var now: float = field.now()
	var n: int = 0
	for i: int in boss.pillar_count():
		if boss.pillar_broken(i):
			continue
		var origin: Vector2 = boss._perch_pos(i)
		var mid: float = (boss.centre() - origin).angle()
		var dir: float = 1.0 if n % 2 == 0 else -1.0
		var a0: float = mid - dir * half
		var a1: float = mid + dir * half
		field.add_hand(origin, a0, a1, length, now + 0.05, now + warn, now + warn + sweep)
		for k: int in segs:
			var angle: float = lerpf(a0, a1, (float(k) + 0.5) / float(segs))
			var u: Vector2 = Vector2.from_angle(angle)
			var t_hit: float = now + warn + sweep * (float(k) + 0.5) / float(segs)
			field.add_lane(origin + u * 14.0, origin + u * length, float(s["half_width"]), now, t_hit, float(s["damage"]), float(s["knock"]), 0, PackedFloat32Array(), Vector2i.ZERO, 0.1)
		n += 1
	_at(warn - 0.1, _sound.bind("rain", _base_pos, 0.0, 0.7))
	_at(warn + sweep + float(s["recover"]), _end_act)


# -- CAGE -----------------------------------------------------------------------------------------------------------


func _start_cage(target_pos: Vector2, target_id: int) -> void:
	var s: Dictionary = _sp("cage")
	boss.look_point = target_pos
	_wing = 2
	boss.set_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
	boss.rig.charge_kind = 3
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, -1.0, 1.1)
	var player: Player = _by_id(target_id)
	if player != null:
		field.add_mark(player, field.now() + float(s["charge"]) + 0.2)
	if multiplayer.is_server():
		_at(float(s["charge"]) - float(s["lock_before"]), _host_lock)
	_at(float(s["charge"]) + 1.6, _end_shot_if_idle)
	_shot_fired = false


## A ring of feather stakes falls round the locked spot and closes in; one gap of 40 degrees shows the way out. Nobody inside the last ring escapes the burst in its middle.
func _lock_cage(point: Vector2, now: float, lock: float, s: Dictionary) -> void:
	var outer: float = float(s["outer"])
	var gap_w: float = deg_to_rad(float(s["gap"]))
	var toward: float = (boss.centre() - point).angle()
	var gap_a: float = toward
	for k: int in 12: ## the first direction (from the middle of the arena outwards, then turning) where the way out leads onto the floor and not through the rift
		var angle: float = toward + (float(k + 1) / 2) * 0.5 * (1.0 if k % 2 == 0 else -1.0) + _rng.randf_range(-0.12, 0.12)
		var beyond: Vector2 = point + Vector2.from_angle(angle) * (outer + 16.0)
		if field.on_floor(beyond) and not _rift_blocks(point, beyond):
			gap_a = angle
			break
	var t_start: float = now + lock + float(s["close_after"])
	var t_end: float = t_start + float(s["close_time"])
	field.add_cage(point, outer, float(s["inner"]), gap_a, gap_w, now, t_start, t_end, float(s["damage"]), float(s["knock"]), float(s["wall_half"]))
	field.add_ring(point, float(s["inner"]), 0.0, now, t_end + float(s["burst_after"]), float(s["burst_damage"]), float(s["knock"]))
	_at(_t + lock + float(s["close_after"]) - 0.3, _sound.bind("feather_launch", point, 0.0, 0.8))
	_at(_t + lock + float(s["close_after"]) + float(s["close_time"]) + float(s["burst_after"]), _cage_burst.bind(point, float(s["inner"])))


func _cage_burst(point: Vector2, radius: float) -> void:
	_kick(0.6)
	ShockRing.burst(boss.get_parent(), point, radius, 0.9)
	boss.shake_near(point, 1.4)
	_sound("feather_hit", point, 2.0, 0.7)


# -- DIVE (phase 3) -------------------------------------------------------------------------------------------------


## He leans forward on the pillar and takes aim (an eye over the target), shoots off at her, homing, low over the floor, faster than anybody can run, rears up right in
## front of her and grabs with both wings: a small zone (`dive.zone_radius`) is announced for `dive.rise` seconds only, so nothing but a blink (or a very early sidestep)
## gets her out. It hurts and sets her alight (`burn`). Afterwards he stands there tired (armour `armour_hit`); if the grab found nobody he is open for much longer
## (`whiff_recover`, `armour_whiff`).
func _start_dive(target_pos: Vector2, target_id: int) -> void:
	var d: Dictionary = _sp("dive")
	boss.set_pose(SkyCleaverRig.Pose.STOOP, float(d["aim"]))
	boss.rig.dive = 0.0
	boss.rig.charge_kind = 1
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 0.0, 0.9)
	var target: Player = _by_id(target_id)
	_dive = {
		"target": target_id, "pos": _base_pos, "dir": (target_pos - _base_pos).normalized(), "speed": 0.0, "net": _base_pos, "launched": false, "launch_t": 0.0,
		"committed": false, "commit_t": 0.0, "track_in": 0.0, "centre": Vector2.ZERO, "before": 0, "leave_at": 0.0, "whiff": false, "trail": 0.0,
	}
	if target != null:
		field.add_mark(target, field.now() + float(d["aim"]) + float(d["max_time"]))
	_at(float(d["aim"]), _dive_launch)


func _dive_launch() -> void:
	if act != Act.DIVE:
		return
	_dive["launched"] = true
	_dive["launch_t"] = _t
	boss.rig.dive = 1.0
	boss.play_voice("takeoff")
	_sound("feather_launch", boss.global_position, 3.0, 0.7)
	_kick(0.5)
	field.add_sparks(boss.eye_position(), 14)


func _drive_dive(delta: float) -> void:
	var d: Dictionary = _sp("dive")
	var target: Player = _by_id(int(_dive["target"]))
	if target != null:
		boss.look_point = target.global_position
	var launched: bool = bool(_dive["launched"])
	var committed: bool = bool(_dive["committed"])
	var height: float = _base_h
	if not launched:
		_charge = smoothstep(0.0, float(d["aim"]), _t)
		boss.set_combat(true, float(_sp("armour")["shot"]))
		boss.rig.dive = 0.0
		boss.puppet_pos = _base_pos
		boss.puppet_height = _base_h
		return
	if not committed:
		_charge = 1.0
		boss.set_combat(false, 1.0)
		if multiplayer.is_server():
			_host_dive_step(delta)
		else:
			_dive["pos"] = (_dive["pos"] as Vector2).lerp(_dive["net"] as Vector2, 1.0 - exp(-12.0 * delta))
		var k: float = _t - float(_dive["launch_t"])
		height = lerpf(_base_h, float(d["grab_height"]), smoothstep(0.0, float(d["descend"]), k))
		_dive["trail"] = float(_dive["trail"]) - delta
		if float(_dive["trail"]) <= 0.0: ## fire trails behind him
			_dive["trail"] = 0.045
			field.add_sparks(boss.eye_position(), 2)
	else:
		var ct: float = _t - float(_dive["commit_t"])
		var rise: float = float(d["rise"])
		var end: float = float(_dive["leave_at"]) - float(_dive["commit_t"])
		var up: float = smoothstep(0.0, rise, ct)
		height = lerpf(float(d["grab_height"]), float(d["stand_height"]), up) * (1.0 - smoothstep(rise + 0.12, rise + 0.5, ct)) + float(d["grab_height"]) * smoothstep(rise + 0.12, rise + 0.5, ct)
		_raise = up * (1.0 - smoothstep(rise + 0.05, rise + 0.3, ct))
		_charge = up * (1.0 - smoothstep(rise, rise + 0.25, ct))
		_fatigue = smoothstep(rise + 0.1, rise + 0.5, ct) * (1.0 - smoothstep(end - 0.5, end, ct))
		var hit_win: bool = ct > rise + 0.1 and ct < end
		var factor: float = float(d["armour_whiff"]) if bool(_dive["whiff"]) else float(d["armour_hit"])
		boss.set_combat(hit_win, factor if hit_win else 1.0)
		boss.rig.dive = 0.0
	boss.puppet_pos = _dive["pos"] as Vector2
	boss.puppet_height = height


## Host: the homing flight. He speeds up, turns towards her at a limited rate (so a straight run does not shake him off, a blink does), stays over the floor, and rears up
## when he is `catch` px from her (or gives up after `max_time`).
func _host_dive_step(delta: float) -> void:
	var d: Dictionary = _sp("dive")
	var target: Player = _by_id(int(_dive["target"]))
	if target == null or target.health.current <= 0.0:
		var living: Array[Player] = _living()
		if living.is_empty():
			_commit_dive_host(_dive["pos"] as Vector2, _dive["pos"] as Vector2)
			return
		target = living[0]
		_dive["target"] = int(target.name)
	var pos: Vector2 = _dive["pos"] as Vector2
	var dir: Vector2 = _dive["dir"] as Vector2
	var speed: float = float(_dive["speed"])
	if speed <= 0.0:
		speed = float(d["speed0"])
	speed = move_toward(speed, float(d["speed"]), float(d["accel"]) * delta)
	var want: Vector2 = (target.global_position - pos).normalized()
	var turn: float = float(d["turn"]) * delta
	dir = dir.rotated(clampf(dir.angle_to(want), -turn, turn))
	var next: Vector2 = pos + dir * speed * delta
	if not field.on_floor(next):
		var slide_x: Vector2 = pos + Vector2(dir.x, 0.0) * speed * delta
		var slide_y: Vector2 = pos + Vector2(0.0, dir.y) * speed * delta
		if field.on_floor(slide_x):
			next = slide_x
		elif field.on_floor(slide_y):
			next = slide_y
		else:
			next = pos
			speed *= 0.5
	_dive["pos"] = next
	_dive["dir"] = dir
	_dive["speed"] = speed
	_dive["track_in"] = float(_dive["track_in"]) - delta
	if float(_dive["track_in"]) <= 0.0:
		_dive["track_in"] = 0.05
		_rpc_dive_track.rpc(next)
	var since: float = _t - float(_dive["launch_t"])
	if next.distance_to(target.global_position) <= float(d["catch"]):
		_commit_dive_host(next, target.global_position)
	elif since > float(d["max_time"]):
		_commit_dive_host(next, next) ## he gave up: the wings close on nothing


func _commit_dive_host(pos: Vector2, target_pos: Vector2) -> void:
	if bool(_dive["committed"]):
		return
	_dive["committed"] = true ## (every peer sets it again in the RPC: this stops a second call in the same frame)
	_rpc_dive_commit.rpc(pos, target_pos)


@rpc("authority", "call_remote", "unreliable")
func _rpc_dive_track(pos: Vector2) -> void:
	if mode == Mode.ACTING and act == Act.DIVE:
		_dive["net"] = pos


## He reached her: he rears up right in front of her, the grab is announced and closes after `rise` seconds.
@rpc("authority", "call_local", "reliable")
func _rpc_dive_commit(pos: Vector2, target_pos: Vector2) -> void:
	if mode != Mode.ACTING or act != Act.DIVE or not bool(_dive["launched"]):
		return
	var d: Dictionary = _sp("dive")
	_dive["committed"] = true
	_dive["pos"] = pos
	_dive["commit_t"] = _t
	var rise: float = float(d["rise"])
	_dive["leave_at"] = _t + rise + float(d["recover"])
	var centre: Vector2 = target_pos
	_dive["centre"] = centre
	field.clear_marks()
	var now: float = field.now()
	var radius: float = float(d["zone_radius"]) * (1.0 + 0.06 * float(mini(_extra(), 3)))
	field.add_ring(centre, radius, 0.0, now, now + rise, float(d["damage"]), float(d["knock"]), 0, PackedFloat32Array(), Vector2i.ZERO, 0.16, float(d["burn"]))
	_dive["before"] = field.hurt_total
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.rig.dive = 0.0
	boss.play_voice("takeoff")
	_sound("charge", pos, 2.0, 1.3)
	_wing = 2
	_at(_t + rise, _dive_clap.bind(centre, radius))
	if multiplayer.is_server():
		_at(_t + rise + 0.3, _dive_judge)
	_at(_t + rise + float(d["recover"]), _dive_try_leave)


## The wings close.
func _dive_clap(centre: Vector2, radius: float) -> void:
	_kick(0.8)
	ShockRing.burst(boss.get_parent(), centre, radius, 1.0)
	boss.shake_near(centre, 2.4)
	boss.rig.hit_flash()
	_kick_wing(0, 1.0)
	_kick_wing(1, 1.0)
	field.add_sparks(boss.eye_position(), 18)
	_sound("blast", centre, 3.0, 1.25)


## Host: did the grab find anybody? If not he is left standing open for longer.
func _dive_judge() -> void:
	if field.hurt_total == int(_dive.get("before", 0)):
		_rpc_dive_whiff.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_dive_whiff() -> void:
	if act != Act.DIVE or bool(_dive["whiff"]):
		return
	var d: Dictionary = _sp("dive")
	_dive["whiff"] = true
	_dive["leave_at"] = float(_dive["commit_t"]) + float(d["rise"]) + float(d["whiff_recover"])
	_sound("blast", boss.global_position, -4.0, 0.6)


func _dive_try_leave() -> void:
	if act != Act.DIVE:
		return
	if _t + 0.001 < float(_dive["leave_at"]):
		_at(float(_dive["leave_at"]), _dive_try_leave)
		return
	act = Act.NONE
	mode = Mode.MOVING
	_clear_body()
	boss.rig.dive = 0.0
	boss.keep_act_for_flight()
	if multiplayer.is_server():
		boss.host_fly_to(_flee_pillar(), true)


# -- GLUT, SPLITTER, MARK (phase 3) ---------------------------------------------------------------------------------


## Glutfeld: he throws a few fire feathers at the players. Each one sticks where it lands (a ring warns from the aim on), and after a moment the floor round it catches fire
## and burns for seconds (`FireArena.light`): no blow, but whoever stands in it is set alight. The ones beyond the number of players fall round them and close the ways.
func _start_glut(target_pos: Vector2, target_id: int) -> void:
	var g: Dictionary = _sp("glut")
	boss.look_point = target_pos
	_wing = 2
	_glut_end = 99.0
	boss.set_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
	boss.rig.charge_kind = 1
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, -1.0, 1.2)
	var player: Player = _by_id(target_id)
	if player != null:
		field.add_mark(player, field.now() + float(g["charge"]) + 0.2)
	if multiplayer.is_server():
		_at(float(g["charge"]) - float(g["lock_before"]), _host_lock)
	_at(float(g["charge"]) + 1.6, _end_shot_if_idle)
	_shot_fired = false


func _lock_glut(points: PackedVector2Array, now: float, lock: float, g: Dictionary) -> void:
	var count: int = mini(int(g["count"]) + int(g["per_extra"]) * _extra(), int(g["max"]))
	var radius: float = float(g["radius"])
	var last: float = 0.0
	for i: int in count:
		var base: Vector2 = points[i % points.size()]
		var p: Vector2 = base
		if i >= points.size(): ## the others fall round the players
			for attempt: int in 8:
				var cand: Vector2 = base + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(float(g["spread_min"]), float(g["spread_max"]))
				if field.on_floor(cand) and not _rift_blocks(base, cand):
					p = cand
					break
		var delay: float = float(i) * float(g["throw_gap"])
		var t0: float = now + lock + delay
		var t1: float = t0 + maxf(_base_pos.distance_to(p) / float(g["speed"]), 0.25)
		var ignite: float = (t1 - now) + float(g["ignite"]) ## seconds from now (on this clock) until the floor catches fire
		last = maxf(last, ignite)
		blaze.light(p, radius, ignite / haste, float(g["burn_seconds"]), float(g["scale"]), true)
		_at(_t + lock + delay, _fire_glut.bind(p, t1, int(_rng.randi() % 4), g, i % 2))
		_at(_t + lock + delay + (t1 - t0), _sound.bind("feather_stick", p, 0.0, 1.0))
		_at(_t + ignite, _glut_ignites.bind(p))
	_glut_end = _t + lock + float(count - 1) * float(g["throw_gap"]) + 0.5
	_at(_glut_end + float(g["recover"]), _end_act)


func _fire_glut(point: Vector2, t1: float, variant: int, g: Dictionary, wing: int) -> void:
	_kick(0.3)
	_kick_wing(wing, 1.0)
	var origin: Dictionary = _wing_origin(wing, 2)
	field.add_flight(origin["ground"] as Vector2, float(origin["h"]), point, 0.0, field.now(), t1, VoidFeather.SHOT, variant, float(g["ignite"]) + 0.25, 0.0, 0.0, 9.0, VoidFeather.SHOT_STUCK, true)
	field.add_sparks(origin["screen"] as Vector2, 8)
	boss.shake_near(_base_pos, 0.3)
	_sound("feather_launch", origin["screen"] as Vector2, 1.0, 1.15)


func _glut_ignites(point: Vector2) -> void:
	_sound("blast", point, -3.0, 1.6)
	boss.shake_near(point, 0.5)


## Himmelssplitter: he rises and the sky comes down on five spots one after the other, each where somebody stood a second ago (the lag): standing still is punished, running on
## is not. Every other splinter strikes from the other side of the arena's middle. Each leaves a fire for a moment.
func _start_splitter() -> void:
	var s: Dictionary = _sp("splitter")
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 1.0, 0.8)
	_wing = 2
	_charge = 0.0
	boss.rig.charge_kind = 3
	_split_first = _pick.randi()
	var count: int = mini(int(s["count"]) + int(s["per_extra"]) * _extra(), int(s["max"]))
	var last: float = 0.0
	for i: int in count:
		var at: float = float(s["first"]) + float(i) * float(s["step"])
		if multiplayer.is_server():
			_at(at, _host_splitter.bind(i))
		last = at + float(s["warn"])
		_at(last - 0.1, _splitter_beat)
	_rain_end = last + 0.5
	_droop_from = _rain_end + 0.6
	_at(_rain_end + 0.3, _rain_lands)
	_at(_droop_from + float(s["droop"]), _end_act)


func _host_splitter(i: int) -> void:
	var s: Dictionary = _sp("splitter")
	var living: Array[Player] = _living()
	if living.is_empty():
		return
	var who: Player = living[(i + _split_first) % living.size()]
	var p: Vector2 = _trail_at(int(who.name), float(s["lag"]), who.global_position)
	if i % 2 == 1: ## the sky answers from the other side
		var mirrored: Vector2 = boss.arena_middle() * 2.0 - p
		if field.on_floor(mirrored):
			p = mirrored
	if not field.on_floor(p):
		p = who.global_position
	_rpc_splitter.rpc(p, i)


@rpc("authority", "call_local", "reliable")
func _rpc_splitter(point: Vector2, index: int) -> void:
	if mode != Mode.ACTING or act != Act.SPLITTER:
		return
	var s: Dictionary = _sp("splitter")
	var now: float = field.now()
	var warn: float = float(s["warn"])
	field.add_ring(point, float(s["radius"]), 0.0, now, now + warn, float(s["damage"]), float(s["knock"]), 0, PackedFloat32Array(), Vector2i.ZERO, 0.2)
	blaze.column(point, float(s["radius"]), warn / haste, float(s["ember"]), float(s["ember_scale"]))
	_sound("charge", point, -4.0, 1.5 + 0.06 * float(index))
	_at(_t + warn, _sound.bind("blast", point, 0.0, 1.5))


func _splitter_beat() -> void:
	_kick(0.5)
	_kick_wing(0, 0.8)
	_kick_wing(1, 0.8)
	boss.shake_near(_base_pos, 0.4)


## Host: where every player stood, every 0.1 s, for the last three seconds.
func _record_trails(delta: float) -> void:
	_trail_acc += delta
	if _trail_acc < 0.1:
		return
	_trail_acc = 0.0
	for player: Player in Player.all:
		if player.health.current <= 0.0:
			continue
		var id: int = int(player.name)
		var list: Array = _trail.get(id, []) as Array
		list.append(player.global_position)
		if list.size() > 30:
			list.pop_front()
		_trail[id] = list


func _trail_at(id: int, lag: float, fallback: Vector2) -> Vector2:
	var list: Array = _trail.get(id, []) as Array
	if list.is_empty():
		return fallback
	return list[maxi(list.size() - 1 - roundi(lag / 0.1), 0)] as Vector2


## Brandmal: one player is marked. A seal turns over her head and counts down; shortly before it bursts it sinks into the floor where she stands: she has to be out of the
## ring by then, and so has everybody else (the burst hurts and sets alight whoever stands in it). He stands open the whole time.
func _start_mark(target_pos: Vector2, target_id: int) -> void:
	var m: Dictionary = _sp("mark")
	boss.look_point = target_pos
	_wing = 2
	_mark = {"target": target_id, "point": Vector2.INF}
	_mark_end = 99.0
	boss.set_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
	boss.rig.charge_kind = 3
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 1.0, 0.7)
	var player: Player = _by_id(target_id)
	if player != null:
		field.add_mark(player, field.now() + float(m["charge"]) + 0.3)
	_at(float(m["charge"]), _mark_cast)
	_at(float(m["charge"]) + 2.0, _mark_safety)


## A feather flies from his wing to her head and brands her.
func _mark_cast() -> void:
	var player: Player = _by_id(int(_mark["target"]))
	_kick(0.5)
	_kick_wing(0, 1.0)
	_kick_wing(1, 1.0)
	_sound("feather_launch", _base_pos, 2.0, 0.8)
	if player == null or player.health.current <= 0.0:
		_mark_end = _t + 0.6
		_at(_mark_end, _end_act)
		return
	var origin: Dictionary = _wing_origin(0, 2)
	var now: float = field.now()
	field.add_flight(origin["ground"] as Vector2, float(origin["h"]), player.global_position, 46.0, now, now + 0.28, VoidFeather.SHOT, 0, 0.0, 0.0, 0.0, 9.0, Vector2i.ZERO, true)
	field.add_sparks(origin["screen"] as Vector2, 14)
	_at(_t + 0.28, _mark_begin)


func _mark_begin() -> void:
	if act != Act.MARK:
		return
	var m: Dictionary = _sp("mark")
	var total: float = float(m["total"])
	var player: Player = _by_id(int(_mark["target"]))
	field.clear_marks()
	_mark["begun"] = true
	_mark_end = _t + total + float(m["recover"])
	if player == null or player.health.current <= 0.0:
		_mark_end = _t + 0.6
		_at(_mark_end, _end_act)
		return
	blaze.seal(player, total / haste, float(m["radius"]))
	_sound("charge", player.global_position, 2.0, 1.4)
	if multiplayer.is_server():
		player.effects.apply("brandmark", total, 1.0)
		_at(_t + total - float(m["lock_before"]), _host_mark_lock)
	_at(_t + total, _mark_burst)
	_at(_mark_end, _end_act)


## Host: the seal sinks into the floor under her (or, if she fell, where she was).
func _host_mark_lock() -> void:
	var player: Player = _by_id(int(_mark["target"]))
	var p: Vector2 = boss.centre()
	if player != null and player.health.current > 0.0:
		p = player.global_position
	elif (_mark["point"] as Vector2).is_finite():
		p = _mark["point"] as Vector2
	_rpc_mark_lock.rpc(p)


@rpc("authority", "call_local", "reliable")
func _rpc_mark_lock(point: Vector2) -> void:
	if mode != Mode.ACTING or act != Act.MARK or not bool(_mark.get("begun", false)):
		return
	var m: Dictionary = _sp("mark")
	_mark["point"] = point
	var now: float = field.now()
	field.add_ring(point, float(m["radius"]), 0.0, now, now + float(m["lock_before"]), float(m["damage"]), float(m["knock"]), 0, PackedFloat32Array(), Vector2i.ZERO, 0.2, float(m["burn"]))
	blaze.lock_seal(point)
	_kick(0.4)
	_sound("charge", point, 2.0, 0.6)
	boss.shake_near(point, 0.8)


func _mark_burst() -> void:
	var point: Vector2 = _mark["point"] as Vector2
	_kick(1.0)
	_screen_flash(0.35)
	_sound("blast", point if point.is_finite() else boss.centre(), 4.0, 0.8)
	_sound("feather_hit", point if point.is_finite() else boss.centre(), 2.0, 0.6)
	_clear_brandmark()


func _mark_safety() -> void:
	if act == Act.MARK and not bool(_mark.get("begun", false)) and _mark_end > 90.0:
		_mark_end = _t + 0.3
		_at(_mark_end, _end_act)


## Host: nobody is marked any more.
func _clear_brandmark() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	for player: Player in Player.all:
		if player.effects != null:
			player.effects.clear("brandmark")


# -- the burning floor ----------------------------------------------------------------------------------------------


func _floor_spec() -> Dictionary:
	return (_spec.get("p3", {}) as Dictionary).get("floor", {}) as Dictionary


## Host: in the last fifth of his health the rim of the arena catches fire for good.
func _host_edge_check() -> void:
	if _edge_lit or phase < 2 or mode not in [Mode.IDLE, Mode.ACTING, Mode.MOVING]:
		return
	var fl: Dictionary = _floor_spec()
	if not fl.is_empty() and boss.health_now() <= float(fl["edge_below"]) * boss.max_health():
		_rpc_edge.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_edge() -> void:
	if _edge_lit:
		return
	_edge_lit = true
	var fl: Dictionary = _floor_spec()
	blaze.set_edge(true, float(fl.get("edge_seconds", 1.6)))
	_kick(1.0)
	boss.shake_near(boss.centre(), 2.4)
	boss.play_voice("crash")
	_sound("roar", boss.centre(), 4.0, 0.6)
	ShockRing.burst(boss.get_parent(), boss.centre(), 220.0, 1.4)
	_screen_flash(0.5)


## The last judgement: the whole floor burns, and three islands of the old turquoise light are cold.
func _arm_floor(j: Dictionary) -> void:
	var fl: Dictionary = j.get("cold", {}) as Dictionary
	blaze.set_floor(true, float(j.get("floor_seconds", 2.0)))
	blaze.set_edge(true, float(j.get("floor_seconds", 2.0)))
	_edge_lit = true
	if fl.is_empty():
		return
	var pillar: ArenaPillar = boss.pillar(_break_pillar)
	var at: Vector2 = pillar.global_position if pillar != null else boss.centre()
	var toward: float = (boss.arena_middle() - at).angle()
	var spots: PackedVector2Array = PackedVector2Array()
	for k: int in int(fl["count"]):
		var ang: float = toward + TAU * float(k) / float(fl["count"])
		for scale_v: float in [1.0, 0.82, 0.64, 0.46]:
			var cand: Vector2 = at + Vector2.from_angle(ang) * float(fl["distance"]) * scale_v
			if field.on_floor(cand) and field.on_floor(cand + Vector2(float(fl["radius"]) * 0.8, 0.0)) and field.on_floor(cand - Vector2(float(fl["radius"]) * 0.8, 0.0)):
				spots.append(cand)
				break
	blaze.cold_islands(spots, float(fl["radius"]), float(fl["shrink_every"]), float(fl["shrink"]), float(fl["min"]))


## The last stand: the pillar burst, the floor's fire goes out and he lies there with a clear mark; the last tenth of his health is for the swords.
func _put_out_floor() -> void:
	blaze.set_floor(false, 1.5)
	blaze.set_edge(false, 1.5)
	blaze.clear_cold()


## He has not died after `last_scream` seconds: one last scream, a ring round him, and then he lies still.
func _last_scream() -> void:
	if mode != Mode.DOWNED or not _last_stand:
		return
	var j: Dictionary = _judge_spec()
	var now: float = field.now()
	var at: Vector2 = boss.puppet_pos
	field.add_ring(at, float(j.get("scream_radius", 120.0)), 0.0, now, now + 0.9, float(j.get("scream_damage", 24.0)), 220.0, 0, PackedFloat32Array(), Vector2i.ZERO, 0.2, 4.0)
	boss.play_voice("crash")
	boss.rig.crack_flash()
	_sound("roar", at, 5.0, 0.6)
	_kick(1.0)
	_at(_t + 0.9, _last_scream_hits.bind(at, float(j.get("scream_radius", 120.0))))


func _last_scream_hits(at: Vector2, radius: float) -> void:
	ShockRing.burst(boss.get_parent(), at, radius, 1.4)
	boss.shake_near(at, 2.4)
	_sound("blast", at, 4.0, 0.6)


# -- BLAST ----------------------------------------------------------------------------------------------------------


func _start_blast() -> void:
	var bl: Dictionary = _sp("blast")
	boss.set_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
	boss.rig.charge_kind = 0
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 0.0, 0.7)
	var warn: float = float(bl["warn"])
	var now: float = field.now()
	field.add_ring(_base_pos, float(bl["radius"]), 0.0, now + 0.05, now + warn, float(bl["damage"]), float(bl["knock"]))
	_at(warn, _blast_hits)
	var done: float = warn + float(bl["recover"])
	if bl.has("outer_radius"): ## phase 2: a second ring follows the first
		var later: float = warn + float(bl["outer_after"])
		field.add_ring(_base_pos, float(bl["outer_radius"]), float(bl["outer_inner"]), now + 0.05, now + later, float(bl["outer_damage"]), float(bl["knock"]))
		_at(later, _blast_outer)
		done = later + float(bl["recover"])
	_at(done, _end_act)


func _blast_hits() -> void:
	_kick(0.55)
	var bl: Dictionary = _sp("blast")
	ShockRing.burst(boss.get_parent(), _base_pos, float(bl["radius"]), 1.0)
	boss.shake_near(_base_pos, 2.2)
	boss.rig.hit_flash()
	_sound("blast", _base_pos, 2.0, 1.0)


func _blast_outer() -> void:
	_kick(0.7)
	var bl: Dictionary = _sp("blast")
	ShockRing.burst(boss.get_parent(), _base_pos, float(bl["outer_radius"]), 1.3)
	boss.shake_near(_base_pos, 1.8)
	_sound("blast", _base_pos, 3.0, 0.75)


# -- CHASE ----------------------------------------------------------------------------------------------------------


func _start_chase(target_id: int) -> void:
	var c: Dictionary = _sp("chase")
	boss.set_pose(SkyCleaverRig.Pose.TAKEOFF, float(_sp("chase")["takeoff"]))
	boss.rig.charge_kind = 2
	boss.play_voice("takeoff")
	_sound("charge", _base_pos, 0.0, 0.6)
	var target: Player = _by_id(target_id)
	_chase = {"target": target_id, "pos": _base_pos, "vel": Vector2.ZERO, "hist": [], "started": false, "start_t": 0.0, "close": 0.0, "committed": false, "net": _base_pos, "track_in": 0.0, "grounded": false}
	if target != null:
		field.add_mark(target, field.now() + float(c["max_time"]) + 0.8)
	_at(float(_sp("chase")["takeoff"]), _chase_go)


func _chase_go() -> void:
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	_chase["started"] = true
	_chase["start_t"] = _t


func _drive_chase(delta: float) -> void:
	var c: Dictionary = _sp("chase")
	var committed: bool = bool(_chase["committed"])
	var pos: Vector2 = _chase["pos"] as Vector2
	var started: bool = bool(_chase["started"])
	var hover: float = float(c["hover"])
	if not committed:
		_raise = clampf((_t - 0.3) / (float(c["max_time"]) * 1.1), 0.0, 0.9)
		_charge = smoothstep(0.0, 0.8, _t)
		if started:
			_lift = lerpf(_base_h, hover, smoothstep(0.0, 0.6, _t - float(_chase["start_t"]))) - _base_h
		if multiplayer.is_server():
			if started:
				_host_chase_step(delta)
		else:
			var net: Vector2 = _chase["net"] as Vector2
			pos = pos.lerp(net, 1.0 - exp(-12.0 * delta))
			_chase["pos"] = pos
	boss.puppet_pos = _chase["pos"] as Vector2
	boss.puppet_height = _base_h + _lift
	if committed:
		var ct: float = _t - float(_chase["commit_t"])
		var cc: Dictionary = c
		var land_at: float = float(cc["warn"]) + 0.15
		var land_s: float = smoothstep(land_at, land_at + float(cc["land"]), ct)
		var rise_at: float = land_at + float(cc["land"]) + float(cc["grounded"])
		var rise_s: float = smoothstep(rise_at, rise_at + 0.45, ct)
		boss.puppet_height = hover * ((1.0 - land_s) + rise_s)
		_raise = 0.9 * (1.0 - smoothstep(float(cc["warn"]) - 0.1, float(cc["warn"]) + 0.2, ct))
		_charge = smoothstep(0.0, float(cc["warn"]), ct) * (1.0 - smoothstep(float(cc["warn"]), float(cc["warn"]) + 0.3, ct))
		var down: bool = ct > land_at + float(cc["land"]) * 0.8 and ct < rise_at
		_fatigue = smoothstep(land_at, land_at + float(cc["land"]), ct) * (1.0 - rise_s)
		boss.set_combat(down, float(_sp("armour")["grounded"]) if down else 1.0)


func _host_chase_step(delta: float) -> void:
	var c: Dictionary = _sp("chase")
	var target: Player = _by_id(int(_chase["target"]))
	if target == null or target.health.current <= 0.0:
		var living: Array[Player] = _living()
		if living.is_empty():
			_commit_host(_chase["pos"] as Vector2)
			return
		target = living[0]
		_chase["target"] = int(target.name)
	var hist: Array = _chase["hist"] as Array
	hist.append({"t": _t, "p": target.global_position})
	while hist.size() > 2 and float((hist[1] as Dictionary)["t"]) < _t - float(c["lag"]) - 0.2:
		hist.pop_front()
	var lagged: Vector2 = (hist[0] as Dictionary)["p"] as Vector2
	for entry: Dictionary in hist:
		if float(entry["t"]) <= _t - float(c["lag"]):
			lagged = entry["p"] as Vector2
	var pos: Vector2 = _chase["pos"] as Vector2
	var to: Vector2 = lagged - pos
	var desired: Vector2 = to.normalized() * float(c["speed"]) * smoothstep(0.0, 24.0, to.length())
	var vel: Vector2 = (_chase["vel"] as Vector2).move_toward(desired, 280.0 * delta)
	var next: Vector2 = pos + vel * delta
	var rift_active: bool = _rift_up()
	if not field.on_floor(next) or (rift_active and _rift_blocks(pos, next)):
		var slide_x: Vector2 = pos + Vector2(vel.x, 0.0) * delta
		if field.on_floor(slide_x) and (not rift_active or not _rift_blocks(pos, slide_x)):
			next = slide_x
			vel.y = 0.0
		else:
			var slide_y: Vector2 = pos + Vector2(0.0, vel.y) * delta
			if field.on_floor(slide_y) and (not rift_active or not _rift_blocks(pos, slide_y)):
				next = slide_y
				vel.x = 0.0
			else:
				next = pos
				vel = Vector2.ZERO
	_chase["vel"] = vel
	_chase["pos"] = next
	var close: bool = next.distance_to(target.global_position) < float(c["close"])
	_chase["close"] = float(_chase["close"]) + delta if close else 0.0
	_chase["track_in"] = float(_chase["track_in"]) - delta
	if float(_chase["track_in"]) <= 0.0:
		_chase["track_in"] = 0.05
		_rpc_track.rpc(next)
	if float(_chase["close"]) > 0.18 or _t - float(_chase["start_t"]) > float(c["max_time"]):
		_commit_host(next)


@rpc("authority", "call_remote", "unreliable")
func _rpc_track(pos: Vector2) -> void:
	if mode == Mode.ACTING and act == Act.CHASE:
		_chase["net"] = pos


## Host: he has reached the one he followed. In phase 2, with company, a shadow double of the ring forms round the nearest other player.
func _commit_host(pos: Vector2) -> void:
	var twin: Vector2 = Vector2.INF
	if phase >= 1 and _living().size() > 1:
		var main: Player = _by_id(int(_chase["target"]))
		var best: float = 1e9
		for player: Player in _living():
			if player == main:
				continue
			var d: float = player.global_position.distance_to(pos)
			if d < best:
				best = d
				twin = player.global_position
	_rpc_commit.rpc(pos, twin)


## He has reached the one he followed: the ring is announced, the burst comes, he lands tired.
@rpc("authority", "call_local", "reliable")
func _rpc_commit(pos: Vector2, twin: Vector2) -> void:
	if mode != Mode.ACTING or act != Act.CHASE or bool(_chase["committed"]):
		return
	var c: Dictionary = _sp("chase")
	_chase["committed"] = true
	_chase["pos"] = pos
	_chase["commit_t"] = _t
	field.clear_marks()
	var radius: float = float(c["radius"]) * (1.0 + 0.08 * float(mini(_extra(), 3)))
	var now: float = field.now()
	var warn: float = float(c["warn"])
	field.add_ring(pos, radius, 0.0, now, now + warn, float(c["damage"]), float(c["knock"]))
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.play_voice("takeoff")
	_sound("charge", pos, 2.0, 0.9)
	var fire_t: float = _t + warn
	_at(fire_t, _chase_burst.bind(pos, radius))
	if c.has("echo_after"): ## phase 2: a second ring runs out after the first
		var echo_at: float = float(c["echo_after"])
		field.add_ring(pos, float(c["echo_outer"]), float(c["echo_inner"]), now, now + warn + echo_at, float(c["echo_damage"]), float(c["knock"]))
		_at(fire_t + echo_at, _chase_echo.bind(pos, float(c["echo_outer"])))
	if twin.is_finite(): ## the shadow double: the same ring round the other player
		field.add_ring(twin, radius, 0.0, now, now + warn, float(c["double_damage"]), float(c["knock"]))
		ShadowPatch.spawn(get_tree().current_scene, twin, Vector2i(44, 32), 2.4, 1.6, 5)
		_at(fire_t, _chase_double.bind(twin, radius))
	_at(fire_t + 0.15, _chase_land)
	var rise_at: float = fire_t + 0.15 + float(c["land"]) + float(c["grounded"])
	_at(rise_at, _chase_rise)
	_at(rise_at + 0.45, _chase_leave)


func _chase_burst(pos: Vector2, radius: float) -> void:
	_kick(0.6)
	var c: Dictionary = _sp("chase")
	var count: int = int(c["feathers"]) + 4 * _extra()
	var now: float = field.now()
	_kick_wing(0, 1.0)
	_kick_wing(1, 1.0)
	for i: int in count:
		var angle: float = TAU * float(i) / float(count) + _rng.randf() * 0.2
		var dst: Vector2 = pos + Vector2.from_angle(angle) * radius * _rng.randf_range(0.82, 1.0)
		var origin: Dictionary = _wing_origin(i % 2, 1 + (i / 2) % 5)
		field.add_flight(origin["ground"] as Vector2, float(origin["h"]), dst, 2.0, now, now + 0.22, VoidFeather.SALVO, _rng.randi() % 4, 0.5, 0.0, 0.0, 9.0, VoidFeather.SALVO_STUCK, true)
		if i < 8:
			field.add_sparks(origin["screen"] as Vector2, 2)
	ShockRing.burst(boss.get_parent(), pos, radius, 0.8)
	boss.shake_near(pos, 2.0)
	boss.rig.hit_flash()
	_sound("blast", pos, 0.0, 1.15)


func _chase_echo(pos: Vector2, radius: float) -> void:
	ShockRing.burst(boss.get_parent(), pos, radius, 1.2)
	boss.shake_near(pos, 1.6)
	_sound("blast", pos, 1.0, 0.8)


func _chase_double(pos: Vector2, radius: float) -> void:
	ShockRing.burst(boss.get_parent(), pos, radius, 0.8)
	boss.shake_near(pos, 1.0)
	_sound("blast", pos, -2.0, 1.3)


func _chase_land() -> void:
	boss.set_pose(SkyCleaverRig.Pose.LANDING, 0.5)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if mode == Mode.ACTING and act == Act.CHASE and is_instance_valid(boss):
			boss.set_pose(SkyCleaverRig.Pose.SPENT, 60.0)
			boss.touch_down_fx())


func _chase_rise() -> void:
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.play_voice("takeoff")


func _chase_leave() -> void:
	## the act is over; he leaves the spot in flight (the host decides where to)
	act = Act.NONE
	mode = Mode.MOVING
	_clear_body()
	boss.keep_act_for_flight()
	if multiplayer.is_server():
		boss.host_fly_to(_flee_pillar(), true)


func _flee_pillar() -> int:
	var best: int = -1
	var best_d: float = -1.0
	var living: Array[Player] = _living()
	for i: int in boss.pillar_count():
		if boss.pillar_broken(i):
			continue
		var p: Vector2 = boss._perch_pos(i)
		var d: float = 1e9
		for player: Player in living:
			d = minf(d, player.global_position.distance_to(p))
		d = d if not living.is_empty() else 0.0
		if d > best_d:
			best_d = d
			best = i
	return best if best >= 0 else boss.perched_on()


# --- the end of a phase --------------------------------------------------------------------------------------------


## The boss is told it was hit (host only): is this the blow that takes it to the third?
func on_damaged(from: Vector2) -> void:
	if mode == Mode.DOWNED:
		if not _last_stand:
			_rpc_finish.rpc(from)
		return
	if mode in [Mode.IDLE, Mode.ACTING, Mode.MOVING] and phase < (_spec["phases"] as Array).size() and boss.health_now() <= boss.health_floor() + 0.01:
		_begin_break_host()


func _begin_break_host() -> void:
	var phases: Array = _spec["phases"] as Array
	var wanted: int = int((phases[phase] as Dictionary)["pillar"])
	if wanted < 0 or boss.pillar_broken(wanted):
		var options: Array[int] = []
		for i: int in boss.pillar_count():
			if not boss.pillar_broken(i):
				options.append(i)
		wanted = options[0] if not options.is_empty() else boss.perched_on()
	_rpc_break.rpc(wanted)


## He breaks off: everything announced is dropped, he roars and flies to the pillar where he rests.
@rpc("authority", "call_local", "reliable")
func _rpc_break(pillar: int) -> void:
	if mode not in [Mode.IDLE, Mode.ACTING, Mode.MOVING, Mode.WAIT]:
		return
	haste = 1.0
	field.time_scale = 1.0
	_combo = false
	_hurry = false
	if _rift_up():
		rift.collapse() ## the rift falls in on itself
	_break_pillar = pillar
	field.clear()
	_clear_brandmark()
	field.clear_marks()
	_events.clear()
	act = Act.NONE
	mode = Mode.BREAKING
	_t = 0.0
	_clear_body()
	boss.look_point = Vector2.INF
	boss.set_invulnerable(true)
	boss.set_combat(false, 1.0)
	if boss.state != SkyCleaver.State.ACT:
		boss.enter_act(boss.global_position, boss.current_height())
	boss.set_pose(SkyCleaverRig.Pose.STAGGER, 0.6)
	boss.play_voice("crash")
	_sound("roar", boss.global_position, 3.0, 1.0)
	ShockRing.burst(boss.get_parent(), boss.global_position, 56.0, 0.9)
	boss.shake_near(boss.global_position, 1.6)
	boss.rig.hit_flash()
	_at(0.75, _break_fly)


func _break_fly() -> void:
	if multiplayer.is_server():
		boss.host_fly_to(_break_pillar, true)


## He sits on the pillar and rests; weapons wear it down.
func _begin_rest() -> void:
	if _is_judgement():
		_begin_judgement()
		return
	mode = Mode.REST
	_t = 0.0
	_events.clear()
	boss.set_pose(SkyCleaverRig.Pose.SPENT, 60.0)
	boss.set_invulnerable(true)
	var pillar: ArenaPillar = boss.pillar(_break_pillar)
	if pillar != null:
		pillar.set_armed(true, _num("rest", "pillar_hp"))
		if not pillar.shattered.is_connected(_on_pillar_shattered):
			pillar.shattered.connect(_on_pillar_shattered, CONNECT_ONE_SHOT)
		if not pillar.worn.is_connected(_on_pillar_worn):
			pillar.worn.connect(_on_pillar_worn)
	_sound("charge", boss.global_position, -4.0, 0.5)


func _on_pillar_worn(_left: float, _maximum: float) -> void:
	var pillar: ArenaPillar = boss.pillar(_break_pillar)
	if pillar != null:
		_sound("pillar_crack", pillar.global_position, 0.0, randf_range(0.9, 1.2))
		boss.rig.hit_flash()


## The pillar bursts: he falls with it.
func _on_pillar_shattered() -> void:
	if mode == Mode.JUDGEMENT:
		if judge_failed:
			return
		_judge_success()
	elif mode != Mode.REST:
		return
	mode = Mode.FALLING
	_t = 0.0
	_events.clear()
	_base_pos = boss._perch_pos(_break_pillar)
	_base_h = boss._perch_height(_break_pillar)
	var toward: Vector2 = (boss.centre() - _base_pos).normalized()
	_fall_from = _base_pos
	_fall_to = _base_pos + toward * 30.0
	boss.enter_act(_base_pos, _base_h)
	boss.set_invulnerable(false)
	boss.set_combat(false, 1.0)
	boss.set_pose(SkyCleaverRig.Pose.CRASHED, _num("rest", "fall_time"))
	boss.play_voice("crash")
	_sound("pillar_break", _base_pos, 3.0, 1.0)
	_at(_num("rest", "fall_time"), _begin_downed)


func _begin_downed() -> void:
	mode = Mode.DOWNED
	_t = 0.0
	_events.clear()
	boss.puppet_height = 0.0
	boss.puppet_pos = _fall_to
	boss.set_pose(SkyCleaverRig.Pose.DOWNED, 60.0)
	boss.impact_ground()
	boss.set_combat(true, float(_judge_spec().get("downed_armour", 2.0)) if _last_stand else 1.0)
	boss.shake_near(_fall_to, 2.6)
	if _last_stand:
		boss.set_floor(0.0) ## nothing holds the last tenth: he can die now
		_at(float(_judge_spec().get("scream_after", 14.0)), _last_scream)


## The first blow on the fallen one: the finisher.
@rpc("authority", "call_local", "reliable")
func _rpc_finish(from: Vector2) -> void:
	if mode != Mode.DOWNED:
		return
	mode = Mode.FINISHING
	_t = 0.0
	_events.clear()
	var f: Dictionary = _sp("finisher")
	_finish_to = float((((_spec["phases"] as Array)[mini(phase, (_spec["phases"] as Array).size() - 1)]) as Dictionary).get("to", f["to"]))
	boss.set_combat(false, 1.0)
	boss.freeze_rig(0.14)
	boss.look_point = from
	_screen_flash(1.0)
	ShockRing.burst(boss.get_parent(), boss.global_position, 76.0, 1.0)
	boss.shake_near(boss.global_position, 3.6)
	boss.rig.hit_flash()
	boss.hit_burst()
	_sound("finisher", boss.global_position, 4.0, 1.0)
	_at(0.14, _finish_react)
	if multiplayer.is_server() and not _has_transition(phase + 1):
		_at(0.16, _finish_cut) ## with a transition the health is cut when the card ends (the bar's fork shatters with it)
	_at(float(f["react"]), _begin_rise)


func _finish_react() -> void:
	boss.set_pose(SkyCleaverRig.Pose.STAGGER, 0.9)
	boss.play_voice("crash")
	boss.look_point = Vector2.INF


func _finish_cut() -> void:
	boss.host_set_health_fraction(_finish_to)


## The next phase begins: he gets up heavily and flies to a pillar.
func _begin_rise() -> void:
	phase += 1
	boss.set_floor(_floor_for(phase))
	if phase == 1 and _spec.has("transition"):
		_begin_transition(false)
		return
	if phase == 2 and _spec.has("transition3"):
		_begin_final_transition(false)
		return
	mode = Mode.RISING
	_t = 0.0
	_events.clear()
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.play_voice("takeoff")
	_sound("charge", boss.global_position, 0.0, 0.7)
	_at(_num("finisher", "rise"), _rise_fly)


func _rise_fly() -> void:
	act = Act.NONE
	mode = Mode.RISING
	boss.keep_act_for_flight()
	if multiplayer.is_server():
		boss.host_fly_to(_flee_pillar(), true)


# --- joining and cleaning up ---------------------------------------------------------------------------------------


func request_sync() -> void:
	if not multiplayer.is_server():
		_request_sync.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_sync() -> void:
	if multiplayer.is_server():
		var broken: PackedInt32Array = PackedInt32Array()
		for i: int in boss.pillar_count():
			if boss.pillar_broken(i):
				broken.append(i)
		_sync.rpc_id(multiplayer.get_remote_sender_id(), phase, barrier_done, broken, int(mode), _break_pillar, _rift_up())


@rpc("authority", "call_remote", "reliable")
func _sync(p_phase: int, built: bool, broken: PackedInt32Array, p_mode: int, break_pillar: int, rift_on: bool) -> void:
	phase = p_phase
	if phase >= 1:
		boss.set_corruption(1.0)
	if phase >= 2 and p_mode != int(Mode.TRANSITION): ## the third phase is on: the fire burns already
		boss.set_fury_now(1.0)
		ArenaFury.ignite(boss, 0.0)
	if rift_on and not _rift_up():
		_make_rift()
		rift.open_now()
	_break_pillar = break_pillar
	_started = true
	_set_world_directors_active(false)
	if built and not barrier_done:
		barrier_done = true
		for entry: Dictionary in boss.barrier_spec():
			for spot: Array in entry["feathers"] as Array:
				var dst: Vector2 = boss.arena_origin + Vector2(float(spot[0]), float(spot[1]))
				var solid: Array = entry["solid"] as Array
				var feather: StuckFeather = StuckFeather.plant(boss.get_parent(), dst, VoidFeather.BARRIER_LENGTHS[_stuck.size() % 3], VoidFeather.BARRIER_WIDTH, _stuck.size() % 4, 0.0, Vector2(float(solid[0]), float(solid[1])), false, _stuck.size())
				_stuck.append(feather)
	for i: int in broken:
		var pillar: ArenaPillar = boss.pillar(i)
		if pillar != null:
			pillar.break_silently()
	if mode == Mode.WAIT and p_mode != int(Mode.WAIT):
		mode = Mode.IDLE
		_gap = 2.0
	boss.set_floor(_floor_for(phase))
	var fl: Dictionary = _floor_spec()
	if phase >= 2 and not fl.is_empty() and boss.health_now() <= float(fl["edge_below"]) * boss.max_health():
		_edge_lit = true
		blaze.set_edge(true, 0.0)


## The boss died or was reset: the feathers crumble, the rift closes, the judgement's light goes out.
func release_feathers(instant: bool) -> void:
	_set_world_directors_active(true)
	_release_phase_two(instant)
	for feather: StuckFeather in _stuck:
		if is_instance_valid(feather):
			if instant:
				feather.queue_free()
			else:
				feather.dissolve()
	_stuck.clear()
	field.clear()
	_clear_brandmark()
	if blaze != null:
		blaze.clear_all()


# --- the second phase: the transition and the rift -----------------------------------------------------------------


func _has_transition(next_phase: int) -> bool:
	return (next_phase == 1 and _spec.has("transition")) or (next_phase == 2 and _spec.has("transition3"))


## Host: the fight began at the second phase (after a wipe in the judgement): once the opening is done the look turns and the rift tears open.
@rpc("authority", "call_local", "reliable")
func _rpc_start_phase_two() -> void:
	if mode in [Mode.IDLE, Mode.WAIT] and not _rift_up():
		_begin_transition(true)


## Every peer plays the same short scene (about 4.5 s): he is pulled up by his tendrils, two blades shatter and grow back as light, the look turns, he screams and
## pushes everybody away, the rift tears open between the pillars that still stand, the card names the phase, and the health falls past the third.
func _begin_transition(from_checkpoint: bool) -> void:
	var tr: Dictionary = _spec["transition"] as Dictionary
	mode = Mode.TRANSITION
	act = Act.NONE
	_t = 0.0
	haste = 1.0
	field.time_scale = 1.0
	_events.clear()
	field.clear()
	field.clear_marks()
	_clear_body()
	if boss.state == SkyCleaver.State.ACT:
		_trans_pos = boss.puppet_pos
		_trans_h = boss.puppet_height
	else:
		_trans_pos = boss._perch_pos(boss.perched_on())
		_trans_h = boss._perch_height(boss.perched_on())
		boss.enter_act(_trans_pos, _trans_h)
	boss.set_invulnerable(true)
	boss.set_combat(false, 1.0)
	boss.look_point = Vector2.INF
	boss.set_pose(SkyCleaverRig.Pose.SPENT, 0.6)
	boss.play_voice("takeoff")
	_sound("charge", _trans_pos, 2.0, 0.5)
	_wing = 2
	if multiplayer.is_server():
		boss.checkpoint_reached.emit(1)
		if not from_checkpoint:
			_at(float(tr["cut_at"]), _finish_cut)
	_start_phase_screen(tr)
	_at(float(tr["burst_at"]), _tr_burst)
	_at(float(tr["corrupt_at"]), _tr_corrupt)
	_at(float(tr["scream_at"]), _tr_scream)
	_at(float(tr["rift_at"]), _tr_rift)
	_at(float(tr["end"]), _end_transition)


func _drive_transition() -> void:
	if _final:
		_drive_final_transition()
		return
	var tr: Dictionary = _spec["transition"] as Dictionary
	var up: float = smoothstep(0.0, 1.1, _t)
	var scream: float = float(tr["scream_at"])
	boss.puppet_pos = _trans_pos + Vector2(sin(_t * 2.3) * 1.2, 0.0)
	boss.puppet_height = _trans_h + float(tr["lift"]) * up + 2.0 * sin(_t * 3.1) * up
	boss.rig.lift = up * (1.0 - smoothstep(scream - 0.1, scream + 0.35, _t))
	_charge = smoothstep(float(tr["corrupt_at"]) - 0.3, scream, _t) * (1.0 - smoothstep(scream, scream + 0.5, _t))
	boss.rig.charge_kind = 3


func _tr_burst() -> void:
	_kick(0.8)
	boss.rig.burst_blades()
	boss.rig.hit_flash()
	ShockRing.burst(boss.get_parent(), boss.global_position, 70.0, 0.8)
	boss.shake_near(boss.global_position, 1.4)
	_sound("pillar_break", boss.global_position, 2.0, 1.5)
	field.add_sparks(boss.eye_position(), 14)


func _tr_corrupt() -> void:
	boss.set_corruption(1.0)
	boss.rig.hit_flash()
	boss.shake_near(boss.global_position, 1.8)
	_sound("roar", boss.global_position, 2.0, 0.6)
	field.add_sparks(boss.eye_position(), 18)


func _tr_scream() -> void:
	_kick(1.0)
	var tr: Dictionary = _spec["transition"] as Dictionary
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.rig.crack_flash()
	boss.rig.hit_flash()
	boss.play_voice("crash")
	_sound("roar", boss.global_position, 5.0, 0.7)
	ShockRing.burst(boss.get_parent(), boss.global_position, float(tr["push_radius"]) * 0.8, 1.4)
	boss.shake_near(boss.global_position, 3.4)
	_screen_flash(1.0)
	if multiplayer.is_server(): ## the pressure wave throws everybody away from him
		for player: Player in _living():
			if player.global_position.distance_to(boss.global_position) < float(tr["push_radius"]):
				var box: HurtboxComponent = player.get_node_or_null("Hurtbox") as HurtboxComponent
				if box != null:
					box.take_hit(float(tr["push_damage"]), boss.global_position, float(tr["push_knock"]))


func _tr_rift() -> void:
	var tr: Dictionary = _spec["transition"] as Dictionary
	_make_rift()
	rift.open(float(tr["rift_time"]))
	_sound("blast", rift.middle(), 3.0, 0.6)
	boss.shake_near(rift.middle(), 2.2)


func _end_transition() -> void:
	boss.rig.lift = 0.0
	boss.set_invulnerable(false)
	if multiplayer.is_server():
		_rift_left = float((_spec["rift"] as Dictionary)["breath_first"])
	_rise_fly()


## The local player's card (bars of shadow, "DER HIMMEL REISST").
func _start_phase_screen(tr: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(boss.centre()) < 700.0:
			BossPhaseScreen.play(boss, player, String(tr["text"]), tr)
			return


# --- the third phase: the push, the scream, the fire --------------------------------------------------------------------


@rpc("authority", "call_local", "reliable")
func _rpc_start_phase_three() -> void:
	if phase >= 2 and mode in [Mode.IDLE, Mode.WAIT]:
		_begin_final_transition(true)


## He breaks off and flies to the middle of the arena (the push), spreads his wings, the card of the phase closes in, he screams: the look turns to its last form, the
## light of the floor and of the last pillar catches fire. About 8 s; the health is cut when the card ends. Every peer plays it, the host hurts.
func _begin_final_transition(from_checkpoint: bool) -> void:
	var tr: Dictionary = _spec["transition3"] as Dictionary
	var screen: Dictionary = tr["screen"] as Dictionary
	_final = true
	mode = Mode.TRANSITION
	act = Act.NONE
	_t = 0.0
	haste = 1.0
	field.time_scale = 1.0
	_events.clear()
	field.clear()
	field.clear_marks()
	_clear_body()
	if boss.state == SkyCleaver.State.ACT:
		_trans_pos = boss.puppet_pos
		_trans_h = boss.puppet_height
	else:
		_trans_pos = boss._perch_pos(boss.perched_on())
		_trans_h = boss._perch_height(boss.perched_on())
		boss.enter_act(_trans_pos, _trans_h)
	boss.set_invulnerable(true)
	boss.set_combat(false, 1.0)
	boss.look_point = Vector2.INF
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.play_voice("takeoff")
	_sound("charge", _trans_pos, 2.0, 0.5)
	_wing = 2
	var screen_at: float = float(tr["screen_at"])
	_t3_scream = screen_at + float(screen["scream_at"])
	_t3_end = screen_at + float(screen["end"]) + 0.1
	if multiplayer.is_server():
		boss.checkpoint_reached.emit(2)
		if not from_checkpoint:
			_at(screen_at + float(screen["leave_at"]) - 0.3, _finish_cut)
	_at(float(tr["push_at"]), _tr3_push)
	_at(float(tr["spread_at"]), _tr3_spread)
	_at(screen_at, _tr3_screen)
	_at(_t3_scream, _tr3_scream)
	_at(_t3_end, _end_final_transition)


func _drive_final_transition() -> void:
	var tr: Dictionary = _spec["transition3"] as Dictionary
	var s: float = smoothstep(0.0, 1.0, clampf(_t / float(tr["fly_time"]), 0.0, 1.0))
	boss.puppet_pos = _trans_pos.lerp(boss.arena_middle(), s)
	boss.puppet_height = lerpf(_trans_h, float(tr["hover_height"]), s) + 2.0 * sin(_t * 2.3) * s
	var spread: float = float(tr["spread_at"])
	_raise = smoothstep(spread, spread + 0.9, _t) * (1.0 - smoothstep(_t3_end - 0.8, _t3_end - 0.2, _t))
	_charge = smoothstep(spread, _t3_scream, _t) * (1.0 - smoothstep(_t3_scream, _t3_scream + 0.6, _t))
	boss.rig.lift = smoothstep(spread - 0.3, spread + 0.5, _t) * (1.0 - smoothstep(_t3_scream - 0.1, _t3_scream + 0.4, _t))
	boss.rig.charge_kind = 3


## He lands in the middle with a wave of pressure that throws everybody to the end of the arena.
func _tr3_push() -> void:
	var tr: Dictionary = _spec["transition3"] as Dictionary
	var centre: Vector2 = boss.arena_middle()
	_kick(1.0)
	ShockRing.burst(boss.get_parent(), centre, float(tr["push_radius"]) * 0.4, 1.8)
	boss.shake_near(centre, 3.8)
	boss.rig.hit_flash()
	boss.rig.crack_flash()
	boss.play_voice("crash")
	_sound("blast", centre, 6.0, 0.55)
	_screen_flash(0.8)
	if multiplayer.is_server():
		_push_players(tr)


## Host: every living player near the arena loses a quarter of her health (never the last point) and slides to the end of the floor, away from the middle.
func _push_players(tr: Dictionary) -> void:
	var centre: Vector2 = boss.arena_middle()
	var spare: int = 0
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.global_position.distance_to(centre) > float(tr["push_radius"]):
			continue
		var from: Vector2 = player.global_position
		var dir: Vector2 = from - centre
		if dir.length() < 6.0: ## standing right under him: any direction, a different one for each
			dir = Vector2.from_angle(float(spare) * 2.4 + 0.7)
			spare += 1
		dir = dir.normalized()
		player.health.take_survivable(roundf(player.health.max_health * float(tr["push_fraction"])), centre, 0.0)
		player.launch(_end_of_floor(from, dir, float(tr["push_margin"])), float(tr["push_seconds"]))


## The last point of the arena's floor on the ray from `from` along `dir`, `margin` px short of the edge.
func _end_of_floor(from: Vector2, dir: Vector2, margin: float) -> Vector2:
	var last: Vector2 = from
	for n: int in 160:
		var p: Vector2 = from + dir * 4.0 * float(n + 1)
		if not field.on_floor(p):
			break
		last = p
	var back: float = minf(margin, last.distance_to(from))
	return last - dir * back


func _tr3_spread() -> void:
	_kick(0.6)
	boss.play_voice("takeoff")
	_sound("charge", boss.global_position, 3.0, 0.5)
	boss.shake_near(boss.global_position, 1.4)


## The glitching card of the phase (bars of shadow, the screen turning pink-violet, "DER HIMMEL BRENNT").
func _tr3_screen() -> void:
	var tr: Dictionary = _spec["transition3"] as Dictionary
	var cfg: Dictionary = (tr["screen"] as Dictionary).duplicate()
	cfg["text"] = tr["text"]
	_start_phase_screen(cfg)


## The scream: the last form (fire, bigger wings of light, more fragments), the floor and the last pillar burn.
func _tr3_scream() -> void:
	var tr: Dictionary = _spec["transition3"] as Dictionary
	_kick(1.6)
	boss.set_fury(1.0)
	boss.set_corruption(1.0)
	boss.set_pose(SkyCleaverRig.Pose.HOVER, 60.0)
	boss.rig.burst_blades()
	boss.rig.crack_flash()
	boss.rig.hit_flash()
	boss.play_voice("crash")
	_sound("roar", boss.global_position, 6.0, 0.5)
	ShockRing.burst(boss.get_parent(), boss.global_position, 140.0, 1.6)
	boss.shake_near(boss.global_position, 4.0)
	_screen_flash(1.0)
	field.add_sparks(boss.eye_position(), 30)
	ArenaFury.ignite(boss, float(tr["ignite_seconds"]))


func _end_final_transition() -> void:
	_final = false
	boss.rig.lift = 0.0
	boss.set_invulnerable(false)
	_rise_fly()


## The two pillars that still stand are the ends of the rift; it runs on to the edge of the floor on either side.
func _make_rift() -> void:
	if _rift_up():
		return
	var ends: Array[Vector2] = []
	for i: int in boss.pillar_count():
		if not boss.pillar_broken(i):
			ends.append(boss._perch_pos(i))
	if ends.size() < 2:
		return
	var r: Dictionary = _spec["rift"] as Dictionary
	rift = RiftWall.new()
	rift.name = "Rift"
	rift.half_width = float(r["half_width"])
	rift.hurt_range = float(r["hurt_range"])
	rift.damage = float(r["damage"])
	rift.knock = float(r["knock"])
	rift.tick = float(r["tick"])
	rift.damage_scale = field.damage_scale
	boss.get_parent().add_child(rift)
	rift.setup(ends[0], ends[1], field.on_floor, multiplayer.is_server(), hash(boss.arena) + 5)


## Host: the rift breathes. A gap opens in it for a few seconds (flickering first) and he attacks at once, so nobody is shut in one half for ever.
func _host_rift(delta: float) -> void:
	var r: Dictionary = _spec["rift"] as Dictionary
	if _hurry_in >= 0.0:
		_hurry_in -= delta
		if _hurry_in < 0.0:
			_hurry_in = -1.0
			if mode == Mode.IDLE:
				_gap = minf(_gap, 0.6)
			else:
				_hurry = true
	if _rift_left < 0.0:
		return
	_rift_left -= delta
	if _rift_left <= 0.0:
		_rift_left = _pick.randf_range(float(r["breath_min"]), float(r["breath_max"]))
		_rpc_rift_gap.rpc(_pick.randf_range(0.3, 0.7))
		_hurry_in = float(r["gap_warn"])


@rpc("authority", "call_local", "reliable")
func _rpc_rift_gap(where: float) -> void:
	if _rift_up():
		var r: Dictionary = _spec["rift"] as Dictionary
		rift.gap(where, float(r["gap_warn"]), float(r["gap_open"]), float(r["gap_len"]))
		_sound("charge", rift.middle(), -2.0, 0.6)


# --- the judgement -------------------------------------------------------------------------------------------------


## The numbers of the judgement in progress (the last one has its own).
func _judge_spec() -> Dictionary:
	if phase >= 2 and _spec.has("judgement2"):
		return _spec["judgement2"] as Dictionary
	return _spec["judgement"] as Dictionary


func _is_judgement() -> bool:
	var phases: Array = _spec["phases"] as Array
	return phase < phases.size() and bool((phases[phase] as Dictionary).get("judgement", false))


## Seconds of the judgement that have run (0 .. total).
func judge_elapsed() -> float:
	return clampf(_t, 0.0, _judge_total) if mode == Mode.JUDGEMENT else 0.0


func judge_total() -> float:
	return _judge_total


func judge_pillar() -> ArenaPillar:
	return boss.pillar(_break_pillar)


## He stands up on the pillar, unhurt, and begins to split the sky. A ring on the floor fills like a clock, the sky darkens, a pillar of light builds above him;
## weapons must break the pillar before the ring is full, and the pillar fights back with a shock wave and a wreath of feathers every few seconds.
func _begin_judgement() -> void:
	var j: Dictionary = _judge_spec()
	mode = Mode.JUDGEMENT
	judge_failed = false
	_t = 0.0
	_events.clear()
	_kill_at = -1.0
	_judge_total = float(j["time"])
	boss.set_pose(SkyCleaverRig.Pose.JUDGE, 0.6)
	boss.set_invulnerable(true)
	boss.set_combat(false, 1.0)
	boss.look_point = Vector2.INF
	boss.play_voice("takeoff")
	_sound("roar", boss.global_position, 4.0, 0.7)
	ShockRing.burst(boss.get_parent(), boss.global_position, 110.0, 1.3)
	boss.shake_near(boss.global_position, 2.4)
	var pillar: ArenaPillar = boss.pillar(_break_pillar)
	_judge_hp = float(j["pillar_hp"]) * (1.0 + float(j["hp_per_extra"]) * float(_extra()))
	if pillar != null:
		pillar.set_armed(true, _judge_hp)
		if not pillar.shattered.is_connected(_on_pillar_shattered):
			pillar.shattered.connect(_on_pillar_shattered, CONNECT_ONE_SHOT)
		if not pillar.worn.is_connected(_on_pillar_worn):
			pillar.worn.connect(_on_pillar_worn)
	_jfx = JudgementFx.begin(boss, self, float(j["ring_radius"]), float(j["dark"]))
	_meter = JudgementMeter.show_for(self)
	if phase >= 2:
		_arm_floor(j)
	var at: float = float(j["pulse_first"])
	while at < _judge_total - 1.2:
		_at(at, _judge_pulse)
		at += float(j["pulse_every"])
	_at(_judge_total, _judge_fail)


func _drive_judgement() -> void:
	var p: float = judge_elapsed() / _judge_total
	boss.rig.charge_kind = 3
	_charge = 1.0 if judge_failed else smoothstep(0.0, 3.0, _t) * (0.55 + 0.45 * p)
	_raise = 0.0
	var marked: ArenaPillar = boss.pillar(_break_pillar)
	if marked != null:
		marked.set_marker_urgency(1.0 if judge_failed else 1.0 - smoothstep(4.0, 12.0, _judge_total - judge_elapsed())) ## same clock as the meter


## The pillar fights back: a shock wave round its foot and, a moment after, a wreath of feathers a little farther out. Step out of the first, through the gap, before the second.
func _judge_pulse() -> void:
	var j: Dictionary = _judge_spec()
	var pillar: ArenaPillar = boss.pillar(_break_pillar)
	if pillar == null:
		return
	var at: Vector2 = pillar.global_position
	var now: float = field.now()
	var warn: float = float(j["pulse_warn"])
	field.add_ring(at, float(j["pulse_radius"]), 0.0, now, now + warn, float(j["pulse_damage"]), float(j["pulse_knock"]), 0, PackedFloat32Array(), Vector2i.ZERO, 0.16, float(j.get("burn", 0.0)))
	var later: float = warn + float(j["wreath_after"])
	field.add_ring(at, float(j["wreath_outer"]), float(j["wreath_inner"]), now, now + later, float(j["wreath_damage"]), float(j["pulse_knock"]) * 0.7, 0, PackedFloat32Array(), Vector2i.ZERO, 0.16, float(j.get("burn", 0.0)))
	_rain_feathers_ring({"a": at, "w": float(j["wreath_outer"]), "inner": float(j["wreath_inner"])}, now + later)
	_sound("charge", at, 0.0, 0.9)
	_at(_t + warn, _judge_pulse_hits.bind(at, float(j["pulse_radius"])))
	_at(_t + later, _judge_wreath_hits.bind(at, float(j["wreath_outer"])))


func _judge_pulse_hits(at: Vector2, radius: float) -> void:
	_kick(0.8)
	ShockRing.burst(boss.get_parent(), at, radius, 1.1)
	boss.shake_near(at, 1.6)
	_sound("blast", at, 2.0, 0.9)


func _judge_wreath_hits(at: Vector2, radius: float) -> void:
	ShockRing.burst(boss.get_parent(), at, radius, 0.8)
	_sound("feather_hit", at, 1.0, 0.8)


## The time ran out: the pillar of light comes down on everything.
func _judge_fail() -> void:
	_kick(1.0)
	if judge_failed or mode != Mode.JUDGEMENT:
		return
	var j: Dictionary = _judge_spec()
	judge_failed = true
	field.clear()
	var pillar: ArenaPillar = boss.pillar(_break_pillar)
	if pillar != null:
		pillar.set_armed(false)
	if _jfx != null:
		_jfx.fail()
	_sound("roar", boss.global_position, 6.0, 0.5)
	boss.shake_near(boss.global_position, 3.0)
	boss.rig.crack_flash()
	_at(_t + float(j["fail_after"]) - 0.35, _screen_flash.bind(1.0))
	if multiplayer.is_server():
		_kill_at = _t + float(j["fail_after"])


func _judge_kill() -> void:
	if not multiplayer.is_server():
		return
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(boss.centre()) < 520.0:
			player.health.kill(boss.global_position)


## The pillar burst in time: the charge flows out of him, he falls with it.
func _judge_success() -> void:
	var j: Dictionary = _judge_spec()
	if _jfx != null:
		_jfx.discharge()
	_screen_flash(float(j["success_flash"]))
	ShockRing.burst(boss.get_parent(), boss.global_position, 140.0, 1.5)
	boss.shake_near(boss.global_position, 3.4)
	boss.rig.hit_flash()
	boss.rig.crack_flash()
	_charge = 0.0
	_sound("finisher", boss.global_position, 4.0, 0.7)
	_free_meter()
	if phase >= 2:
		_last_stand = true
		_put_out_floor()


func _free_meter() -> void:
	if _meter != null and is_instance_valid(_meter):
		_meter.leave()
	_meter = null


func _release_phase_two(instant: bool) -> void:
	_free_meter()
	if phase >= 2 or _final:
		ArenaFury.extinguish(boss, 0.0 if instant else 4.0) ## the fire of the last phase goes out
	if _jfx != null and is_instance_valid(_jfx):
		if instant:
			_jfx.queue_free()
		else:
			_jfx.discharge()
	_jfx = null
	if _rift_up():
		if instant:
			rift.queue_free()
		else:
			rift.collapse()
