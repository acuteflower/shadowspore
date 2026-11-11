class_name MirrorWitchFight
extends Node
## The fight against Morwenna, die Spiegelhexe (docs/enemies/boss_mora.md). A child of the boss (`MirrorWitch`), on every peer.
##
## Host authority, replay on every peer (the pattern of `MornathFight`): the host decides what happens next and tells everybody with a reliable RPC
## (`_rpc_act`, `_rpc_lock`, `_rpc_transition` ...); every peer then plays the same list of timed events (`_at`): the warnings on the floor (the
## `FeatherField`'s zones: what is drawn is what hurts), the effects (`WitchFx`), the sounds. Only the host hurts and only the host moves bodies: the
## witch and her up to two glitch clones are "bodies" (index 0 = the real one) whose place, pose and fade the host streams 20 times a second
## (`_rpc_bodies`, unreliable); peers only ease towards it. So a clone can never be told apart by the network, only by what the dossier names:
## a clone casts NO shadow, its fires are witch green and twitch, it is drawn with scanlines, and the ravens shriek above the REAL witch.
##
## Phase 1 (to 66 %): RESIN (three cuts, the last after a held stutter), PROWL (zigzag into the blind spot), LANCE (roots under the feet),
## SPRAY (a spring back, a fan of slowing sap), FEINT (she vanishes a step before you and cuts from behind).
## Phase 2 "DER SPIEGEL ZERBRICHT" (to 33 %, one clone): PINCER (two crossing sprints, the crossing bursts), SHARDS (mirror shards that bounce off the
## slate), BURROW (an earth mound hunts you while the clone binds you), CAGE (a ring of mirror splinters with burning threads), and the SWAP: struck,
## she may change places with a clone.
## Phase 3 "DIE HEXENSTUNDE" (two clones): CAROUSEL (the three circle and lunge through the middle), LEECH (she drinks from the tree and heals while
## three pulses run over the hollow; enough damage breaks it), FRENZY (five dashes that leave curse seams), SPLIT (three beams, only the real one
## burns: read the ravens, strike her to break it), SWARM (the ravens panic: feathers blind the picture, dives sweep the floor).
## More players: more health (spawn), more spears, drops, shards and cages, the dashes and beams are shared out among the players, the swap comes more often.

enum Mode { ENTRANCE, IDLE, ACT, RECOVER, TRANSITION, STAGGER, DEAD }
enum Act { NONE, RESIN, PROWL, LANCE, SPRAY, FEINT, PINCER, SHARDS, BURROW, CAGE, CAROUSEL, LEECH, FRENZY, SPLIT, SWARM, TIDE }
enum Lock { LANCE, FEINT, BURROW, LUNGE, FRENZY, SPLIT, DIVE, SWAP_CUT, CLONE }

const ACT_NAMES: Dictionary = {"resin": Act.RESIN, "prowl": Act.PROWL, "lance": Act.LANCE, "spray": Act.SPRAY, "feint": Act.FEINT, "pincer": Act.PINCER, "shards": Act.SHARDS,
	"burrow": Act.BURROW, "cage": Act.CAGE, "carousel": Act.CAROUSEL, "leech": Act.LEECH, "frenzy": Act.FRENZY, "split": Act.SPLIT, "swarm": Act.SWARM, "tide": Act.TIDE}
const BODIES: int = 3
const SOUNDS: int = 5
const STREAM: float = 0.05
const PHANTOM: int = 2 ## the FeatherField kind of a clone's warning: a cracked mirror instead of the solid red (feather_zones.gdshader)
const CLONE_ACTS: Array[int] = [Act.PINCER, Act.CAROUSEL, Act.SPLIT] ## acts that move the clones themselves: no drifting, no attacks of their own

var boss: MirrorWitch
var field: FeatherField
var fx: WitchFx
var omen: RavenOmen
var mode: Mode = Mode.ENTRANCE
var act: Act = Act.NONE
var phase: int = 0
var _spec: Dictionary = {}
var _host: bool = false
var _t: float = 0.0
var _events: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new() ## cosmetics of the act in progress (seeded by the host's number)
var _pick: RandomNumberGenerator = RandomNumberGenerator.new() ## the host's decisions
var _nodes: Array[WitchBody] = []
var _boxes: Array[WitchCloneHurtbox] = []
# --- bodies (index 0 = the real witch). The host owns these; peers receive them.
var _pos: PackedVector2Array = PackedVector2Array()
var _h: PackedFloat32Array = PackedFloat32Array()
var _face: PackedFloat32Array = PackedFloat32Array()
var _clip: PackedStringArray = PackedStringArray()
var _ct: PackedFloat32Array = PackedFloat32Array()
var _loop: PackedByteArray = PackedByteArray()
var _alpha: PackedFloat32Array = PackedFloat32Array()
var _diss: PackedFloat32Array = PackedFloat32Array()
var _on: PackedByteArray = PackedByteArray()
var _trail: PackedByteArray = PackedByteArray()
var _hold: PackedFloat32Array = PackedFloat32Array()
var _fade_to: PackedFloat32Array = PackedFloat32Array() ## where `_diss` is heading (0 formed, 1 gone)
var _seg: Array[Dictionary] = []
var _back_in: PackedFloat32Array = PackedFloat32Array() ## host: seconds until a struck clone forms again
var _goal: PackedVector2Array = PackedVector2Array() ## peers: where the stream says each body is
var _stream_left: float = 0.0
var _ct_net: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var _rate: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
var _gap: float = 2.0
var _rot: int = 0
var _end_at: float = -1.0
var _recover: float = 0.0
var _recover_armour: float = 1.0
var _orbit: float = 0.0
var _orbit_dir: float = 1.0
var _last_target: int = 0
var _swap_cd: float = 4.0
var _harass: PackedFloat32Array = PackedFloat32Array([0.0, 2.0, 2.6]) ## host: seconds until each clone attacks on its own
var _away: float = 0.0
var _watch: float = 0.0
var _burrow: Dictionary = {}
var _carousel: Dictionary = {}
var _break_damage: float = 0.0 ## host: damage taken during an act that can be broken (leech, split)
var _heal_left: float = 0.0
var _dead_t: float = -1.0
var _entrance_t: float = 0.0
var _landed: bool = false
var _sounds: Array[AudioStreamPlayer2D] = []
var _sound_i: int = 0
var _stream_cache: Dictionary = {}
var _aura: BossAura
var _living_cache: Array[Player] = []
var _living_frame: int = -1


func setup(p_boss: MirrorWitch) -> void:
	boss = p_boss
	field = boss.field
	fx = boss.fx
	_host = multiplayer.is_server()
	_spec = boss.def_value("fight") as Dictionary
	_pick.seed = int(Time.get_ticks_usec()) ^ 0x5EED
	for i: int in BODIES:
		_pos.append(boss.global_position)
		_goal.append(boss.global_position)
		_h.append(0.0)
		_face.append(PI / 2.0)
		_clip.append("idle")
		_ct.append(0.0)
		_loop.append(1)
		_alpha.append(1.0)
		_diss.append(0.0 if i == 0 else 1.0)
		_fade_to.append(0.0 if i == 0 else 1.0)
		_on.append(1 if i == 0 else 0)
		_trail.append(0)
		_hold.append(0.0)
		_back_in.append(0.0)
		_seg.append({})
	_nodes.append(boss.body)
	for i: int in range(1, BODIES):
		var clone: WitchBody = WitchBody.new()
		clone.name = "%s_Clone%d" % [boss.name, i]
		clone.phantom = true
		clone.dissolve = 1.0
		boss.get_parent().add_child.call_deferred(clone)
		var box: WitchCloneHurtbox = WitchCloneHurtbox.new()
		box.fight = self
		box.index = i
		clone.add_child(box)
		_nodes.append(clone)
		_boxes.append(box)
	omen = RavenOmen.new()
	omen.name = "Ravens"
	boss.add_child(omen)
	omen.setup(self, boss.tree_position())
	_aura = BossAura.begin(self)
	boss.set_floor(_floor_for(0))
	for i: int in SOUNDS:
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.max_distance = 760.0
		player.attenuation = 1.4
		add_child(player)
		_sounds.append(player)
	_begin_entrance(0.0)


func _exit_tree() -> void:
	for i: int in range(1, _nodes.size()):
		if is_instance_valid(_nodes[i]):
			_nodes[i].queue_free()
	_set_world_directors_active(true)
	var tree: CrowTree = boss.tree
	if is_instance_valid(tree):
		tree.drain = 0.0
		if mode != Mode.DEAD:
			tree.set_hour(0.0)


# --- small helpers -------------------------------------------------------------------------------------------------


func _d(group: String) -> Dictionary:
	return _spec.get(group, {}) as Dictionary


func _n(group: String, key: String, fallback: float) -> float:
	return float(_d(group).get(key, fallback))


## A time of this node's clock on the field's clock (zones and effects live there).
func _f(t: float) -> float:
	return field.now() + (t - _t)


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


func _extra() -> int:
	return maxi(_living().size() - 1, 0)


## Players who are alive and in the hollow.
func _living() -> Array[Player]:
	var tick: int = Engine.get_physics_frames()
	if tick - _living_frame < 6 and _living_frame >= 0:
		return _living_cache
	_living_frame = tick
	var found: Array[Player] = []
	var leash: float = boss.leash()
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(boss.tree_position()) < leash:
			found.append(player)
	_living_cache = found
	return found


func _by_id(id: int) -> Player:
	for player: Player in Player.all:
		if player.name == str(id):
			return player
	return null


## The players she can aim at: alive, near, and not veiled by Nebelschleier (docs/magie_konzept.md). Everything that picks a target or a
## spot uses this; the reset check and the player-count scaling keep `_living()`.
func _seen() -> Array[Player]:
	var out: Array[Player] = []
	for player: Player in _living():
		if not player.veiled():
			out.append(player)
	return out


## `_by_id`, but a veiled player is not found (she lost the trail).
func _by_seen(id: int) -> Player:
	var player: Player = _by_id(id)
	return player if player != null and not player.veiled() else null


func _pick_target() -> Player:
	var living: Array[Player] = _seen()
	if living.is_empty():
		return null
	if living.size() > 1: ## never the same one twice in a row
		var others: Array[Player] = []
		for player: Player in living:
			if player.name.to_int() != _last_target:
				others.append(player)
		living = others
	var chosen: Player = living[_pick.randi() % living.size()]
	_last_target = chosen.name.to_int()
	return chosen


func _floor_for(p: int) -> float:
	var phases: Array = _spec.get("phases", [0.66, 0.33]) as Array
	if p >= phases.size():
		return 0.0
	return float(phases[p]) * boss.max_health() + 0.5


## The point of the hollow's floor nearest to `p` on the way to the tree.
func _on_floor(p: Vector2) -> Vector2:
	if field.on_floor(p):
		return p
	var home: Vector2 = boss.tree_position() + Vector2(0, 40)
	for k: int in 40:
		var q: Vector2 = p.lerp(home, float(k + 1) / 40.0)
		if field.on_floor(q):
			return q
	return home


## How far a straight way from `a` towards `dir` stays on the floor (at most `limit`).
func _reach(a: Vector2, dir: Vector2, limit: float) -> float:
	var gone: float = 0.0
	while gone < limit and field.on_floor(a + dir * (gone + 6.0)):
		gone += 6.0
	return gone


## Seconds on this fight's clock (the entrance screen of a peer that joins while she falls).
func elapsed() -> float:
	return _t


func real_position() -> Vector2:
	return _nodes[0].global_position if is_instance_valid(_nodes[0]) else boss.global_position


func clones_on() -> int:
	var count: int = 0
	for i: int in range(1, BODIES):
		if _on[i] == 1 and _fade_to[i] < 0.5:
			count += 1
	return count


func aura_level() -> float:
	if mode == Mode.ENTRANCE or mode == Mode.DEAD:
		return 0.0
	return [0.5, 0.82, 1.18][clampi(phase, 0, 2)]


func _kick(amount: float) -> void:
	if _aura != null:
		_aura.kick(amount)


func _set_world_directors_active(active: bool) -> void:
	if not is_inside_tree():
		return
	var night: NightDirector = get_tree().get_first_node_in_group("night_director") as NightDirector
	if night != null:
		night.story_hold = not active


func _sound(cue: String, at: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless" or _sounds.is_empty():
		return
	var audio: Dictionary = boss.def_value("audio") as Dictionary
	var path: String = String(audio.get(cue, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	if not _stream_cache.has(path):
		_stream_cache[path] = load(path) as AudioStream
	var player: AudioStreamPlayer2D = _sounds[_sound_i % SOUNDS]
	_sound_i += 1
	player.stream = _stream_cache[path] as AudioStream
	player.global_position = at
	player.volume_db = float(audio.get("volume_db", -6.0)) + volume_db
	player.pitch_scale = pitch
	player.play()


# --- bodies: host --------------------------------------------------------------------------------------------------


func _move(i: int, to: Vector2, seconds: float, clip: String = "run", trail: bool = false, arc: float = 0.0, ease_out: bool = false) -> void:
	if not _host:
		return
	_seg[i] = {"a": _pos[i], "b": to, "t0": _t, "dur": maxf(seconds, 0.01), "arc": arc, "ease": ease_out}
	_trail[i] = 1 if trail else 0
	if (to - _pos[i]).length() > 3.0:
		_face[i] = (to - _pos[i]).angle()
	if clip != "":
		_play(i, clip, clip == "run")


func _play(i: int, clip: String, loop: bool = false) -> void:
	if not _host:
		return
	_clip[i] = clip
	_ct[i] = 0.0
	_loop[i] = 1 if loop else 0
	_hold[i] = 0.0


func _look(i: int, at: Vector2) -> void:
	if _host and (at - _pos[i]).length() > 2.0:
		_face[i] = (at - _pos[i]).angle()


func _step_bodies(delta: float) -> void:
	for i: int in BODIES:
		var seg: Dictionary = _seg[i]
		if not seg.is_empty():
			var k: float = clampf((_t - float(seg["t0"])) / float(seg["dur"]), 0.0, 1.0)
			var s: float = (1.0 - (1.0 - k) * (1.0 - k)) if bool(seg["ease"]) else k * k * (3.0 - 2.0 * k)
			_pos[i] = (seg["a"] as Vector2).lerp(seg["b"] as Vector2, s)
			_h[i] = sin(k * PI) * float(seg["arc"])
			if k >= 1.0:
				_seg[i] = {}
				_trail[i] = 0
				_h[i] = 0.0
				if _clip[i] == "run":
					_play(i, "idle", true)
		if i == 0 and _rise_from >= 0.0:
			_ct[0] = maxf(WitchBody.clip_length("down") - 0.13 - (_t - _rise_from) * 0.72, 0.0)
		elif _hold[i] > 0.0:
			_hold[i] -= delta
		else:
			_ct[i] += delta
		_diss[i] = move_toward(_diss[i], _fade_to[i], delta * 3.4)
		if i > 0 and _back_in[i] > 0.0:
			_back_in[i] -= delta
			if _back_in[i] <= 0.0 and mode != Mode.DEAD and i <= phase:
				_pos[i] = _on_floor(_pos[0] + Vector2.from_angle(_pick.randf() * TAU) * 46.0)
				_fade_to[i] = 0.0
				_play(i, "idle", true)
	fx.mound = _pos[0] if not _burrow.is_empty() else Vector2.INF
	_stream_left -= delta
	if _stream_left <= 0.0:
		_stream_left = STREAM
		var data: PackedFloat32Array = PackedFloat32Array()
		for i: int in BODIES:
			var flags: int = int(_loop[i]) | (int(_trail[i]) << 1) | (int(_on[i]) << 2) | ((1 if (i == 0 and not _burrow.is_empty()) else 0) << 3)
			data.append_array([_pos[i].x, _pos[i].y, _h[i], _face[i], float(WitchBody.CLIP_NAMES.find(_clip[i])), _ct[i], _alpha[i], _fade_to[i], float(flags)])
		_rpc_bodies.rpc(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_bodies(data: PackedFloat32Array) -> void:
	for i: int in mini(BODIES, int(data.size() / 9.0)):
		var o: int = i * 9
		_goal[i] = Vector2(data[o], data[o + 1])
		if _goal[i].distance_to(_pos[i]) > 70.0:
			_pos[i] = _goal[i]
		_h[i] = data[o + 2]
		_face[i] = data[o + 3]
		_clip[i] = WitchBody.CLIP_NAMES[clampi(int(data[o + 4]), 0, WitchBody.CLIP_NAMES.size() - 1)]
		var step: float = data[o + 5] - _ct_net[i]
		_rate[i] = 1.0 if step < 0.0 else clampf(step / STREAM, 0.0, 1.2)
		_ct_net[i] = data[o + 5]
		_ct[i] = data[o + 5]
		_alpha[i] = data[o + 6]
		_fade_to[i] = data[o + 7]
		var flags: int = int(data[o + 8])
		_loop[i] = flags & 1
		_trail[i] = (flags >> 1) & 1
		_on[i] = (flags >> 2) & 1
		if i == 0:
			fx.mound = _goal[0] if (flags >> 3) & 1 == 1 else Vector2.INF


## Every peer: the pictures follow the bodies.
func _show_bodies(delta: float) -> void:
	for i: int in BODIES:
		var node: WitchBody = _nodes[i]
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		if not _host:
			_pos[i] = _pos[i].lerp(_goal[i], 1.0 - exp(-22.0 * delta))
			_ct[i] += delta * _rate[i]
			_diss[i] = move_toward(_diss[i], _fade_to[i], delta * 3.4)
		if i == 0:
			boss.global_position = _pos[0]
		else:
			node.global_position = _pos[i]
		node.height = _h[i]
		node.alpha = _alpha[i]
		node.dissolve = _diss[i]
		node.trail = _trail[i] == 1
		node.show_pose(_clip[i], _ct[i], _face[i], _loop[i] == 1)
	boss.set_real_visible(_alpha[0] > 0.5 and _diss[0] < 0.5)
	for i: int in _boxes.size():
		_boxes[i].set_open(_on[i + 1] == 1 and _diss[i + 1] < 0.4 and _alpha[i + 1] > 0.5)


# --- the loop ------------------------------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_t += delta
	_fire_events()
	if _host:
		_host_step(delta)
		_step_bodies(delta)
	_show_bodies(delta)
	if mode == Mode.DEAD:
		_step_death(delta)


func _host_step(delta: float) -> void:
	if mode == Mode.DEAD:
		return
	_watch_players(delta)
	_swap_cd = maxf(_swap_cd - delta, 0.0)
	if mode in [Mode.ACT, Mode.RECOVER, Mode.STAGGER] and not (mode == Mode.ACT and int(act) in CLONE_ACTS):
		_idle_step(delta, true) ## her clones never stand about while she is busy
	if mode in [Mode.IDLE, Mode.ACT, Mode.RECOVER, Mode.STAGGER] and not (mode == Mode.ACT and int(act) in CLONE_ACTS):
		_clone_attacks(delta)
	match mode:
		Mode.ENTRANCE:
			if _landed and _t >= _entrance_t:
				_rpc_mode.rpc(Mode.IDLE, 1.2)
		Mode.IDLE:
			if _check_phase():
				return
			_idle_step(delta)
			_gap -= delta
			if _gap <= 0.0:
				_choose()
		Mode.ACT:
			_act_step(delta)
			if _end_at >= 0.0 and _t >= _end_at:
				_end_at = -1.0
				_rpc_mode.rpc(Mode.RECOVER, _recover)
		Mode.RECOVER, Mode.STAGGER:
			_recover -= delta
			if _recover <= 0.0:
				if not _check_phase():
					_rpc_mode.rpc(Mode.IDLE, 0.0)


func _watch_players(delta: float) -> void:
	_watch += delta
	if _watch < 0.5:
		return
	_watch = 0.0
	if _living().is_empty():
		_away += 0.5
		if _away >= boss.reset_seconds():
			boss.request_reset()
	else:
		_away = 0.0


## Every peer enters a mode the same way.
@rpc("authority", "call_local", "reliable")
func _rpc_mode(next: int, seconds: float) -> void:
	mode = next as Mode
	match mode:
		Mode.IDLE:
			act = Act.NONE
			boss.set_combat(true, 1.0)
			if _host:
				var gaps: Array = _spec.get("gap", [[1.5, 2.3]]) as Array
				var range_s: Array = gaps[mini(phase, gaps.size() - 1)] as Array
				_gap = seconds if seconds > 0.0 else _pick.randf_range(float(range_s[0]), float(range_s[1])) / (1.0 + 0.08 * float(_extra()))
		Mode.RECOVER:
			act = Act.NONE
			boss.set_combat(true, _recover_armour)
			if _host:
				_recover = seconds
				if _clip[0] in ["run", "leech"]:
					_play(0, "idle", true)
		Mode.STAGGER:
			act = Act.NONE
			boss.set_combat(true, _n("stagger", "armour", 1.7))
			_events.clear()
			field.clear()
			fx.cancel_beams()
			fx.mound = Vector2.INF
			boss.tree_drain(0.0)
			_nodes[0].glitch(2.0, 0.3)
			_sound("stagger", real_position())
			_kick(0.7)
			if _host:
				_recover = seconds
				_end_at = -1.0
				_burrow = {}
				_carousel = {}
				_alpha[0] = 1.0
				_fade_to[0] = 0.0
				_seg[0] = {}
				_play(0, "down")
				_hold[0] = 0.0
				_at(_t + 0.26, func() -> void: _hold[0] = maxf(seconds - 0.5, 0.1))


## The health has reached the next third: the phase turns.
func _check_phase() -> bool:
	var phases: Array = _spec.get("phases", [0.66, 0.33]) as Array
	if phase >= phases.size() or boss.health_now() > boss.health_floor() + 0.05:
		return false
	_rpc_transition.rpc(phase + 1, _pos[0])
	return true


func _idle_step(delta: float, only_clones: bool = false) -> void:
	var living: Array[Player] = _seen()
	if living.is_empty():
		return
	var target: Player = _by_seen(_last_target)
	if target == null or target.health.current <= 0.0:
		target = living[0]
	_orbit += delta * 0.55 * _orbit_dir
	if _pick.randf() < delta * 0.25:
		_orbit_dir = -_orbit_dir
	var speed: float = float(boss.def_value("prowl_speed")) * (1.0 + 0.12 * float(phase))
	var count: int = 1 + phase
	for i: int in BODIES:
		if (only_clones and i == 0) or _on[i] == 0 or _fade_to[i] > 0.5 or not _seg[i].is_empty() or _hold[i] > 0.0:
			continue
		if not (_clip[i] in ["run", "idle"]) and _ct[i] < WitchBody.clip_length(_clip[i]): ## a blow still being played: no sliding
			continue
		var want: Vector2 = target.global_position + Vector2.from_angle(_orbit + TAU * float(i) / float(count)) * Vector2(92.0 + 14.0 * float(i), 70.0 + 10.0 * float(i))
		var step: Vector2 = want - _pos[i]
		var moving: bool = step.length() > 6.0
		if moving:
			var next: Vector2 = _pos[i] + step.normalized() * minf(speed * delta, step.length())
			if field.on_floor(next):
				_pos[i] = next
			else:
				moving = false
		_face[i] = (target.global_position - _pos[i]).angle() if not moving else lerp_angle(_face[i], step.angle(), 0.3)
		var want_clip: String = "run" if moving else "idle"
		if _clip[i] != want_clip and (_clip[i] in ["run", "idle"] or _ct[i] > WitchBody.clip_length(_clip[i])):
			_play(i, want_clip, true)
		if i == 0 and moving and _pick.randf() < delta * 0.5: ## a spasm: her body jerks aside
			_rpc_spasm.rpc()


## Host: a formed clone that is not busy goes for a player on its own: a dash and its own cut (its warning is the cracked one).
func _clone_attacks(delta: float) -> void:
	if not _carousel.is_empty() or not _burrow.is_empty():
		return
	var h: Dictionary = _d("harass")
	for i: int in range(1, BODIES):
		if _on[i] == 0 or _fade_to[i] > 0.5 or not _seg[i].is_empty() or _hold[i] > 0.0 or not (_clip[i] in ["run", "idle"]):
			continue
		_harass[i] -= delta
		if _harass[i] > 0.0:
			continue
		var living: Array[Player] = _seen()
		if living.is_empty():
			return
		var target: Player = living[(i + _pick.randi()) % living.size()]
		if target.global_position.distance_to(_pos[i]) > float(h.get("reach", 230.0)):
			_harass[i] = 0.4 ## too far: it closes in first (the drift)
			continue
		_harass[i] = _pick.randf_range(float(h.get("min", 1.9)), float(h.get("max", 3.0))) / (1.0 + 0.25 * float(phase) + 0.12 * float(_extra()))
		_rpc_lock.rpc(Lock.CLONE, PackedVector2Array([_pos[i], target.global_position]), PackedInt32Array([i, _pick.randi() % 3]))


@rpc("authority", "call_local", "unreliable")
func _rpc_spasm() -> void:
	_nodes[0].glitch(1.3, 0.16)
	_sound("stutter", real_position(), -10.0, randf_range(0.9, 1.2))


# --- choosing ------------------------------------------------------------------------------------------------------


func _choose() -> void:
	var target: Player = _pick_target()
	if target == null:
		_gap = 1.0
		return
	var rotations: Array = _spec.get("rotation", [["resin"]]) as Array
	var rotation: Array = rotations[mini(phase, rotations.size() - 1)] as Array
	var kind: Act = Act.NONE
	for attempt: int in rotation.size():
		kind = ACT_NAMES.get(String(rotation[_rot % rotation.size()]), Act.RESIN) as Act
		_rot += 1
		if kind in [Act.PINCER, Act.CAROUSEL, Act.SPLIT] and clones_on() == 0:
			continue ## nothing to do it with right now
		break
	var me: Vector2 = _pos[0]
	var at: Vector2 = target.global_position
	var toward: Vector2 = (at - me).normalized() if at.distance_to(me) > 2.0 else Vector2.RIGHT
	var pts: PackedVector2Array = PackedVector2Array()
	var ids: PackedInt32Array = PackedInt32Array([target.name.to_int()])
	match kind:
		Act.RESIN:
			pts = [me, at]
			for i: int in range(1, BODIES): ## her clones mirror the combo from other sides
				if _on[i] == 1 and _fade_to[i] < 0.5:
					pts.append(_pos[i])
		Act.PROWL:
			var side: float = 1.0 if _pick.randf() < 0.5 else -1.0
			var across: Vector2 = toward.orthogonal() * side
			pts = [me, _on_floor(me.lerp(at, 0.4) + across * 54.0), _on_floor(at + across * 40.0 - toward * 8.0), _on_floor(at + toward * 34.0 + across * 10.0), at]
		Act.LANCE, Act.TIDE:
			pts = [me]
		Act.SPRAY:
			pts = [me, _on_floor(me - toward * 52.0), at]
		Act.FEINT:
			pts = [me, at]
		Act.PINCER:
			var u: Vector2 = Vector2.from_angle(_pick.randf() * TAU)
			pts = [at, _on_floor(at + u * 118.0), _on_floor(at + u.orthogonal() * 118.0), _on_floor(at - (u + u.orthogonal()).normalized() * 118.0)]
		Act.SHARDS:
			pts = [me, at]
		Act.BURROW:
			pts = [me, at]
		Act.CAGE:
			pts = [me, at]
			for player: Player in _seen():
				if player != target and pts.size() < 4:
					pts.append(player.global_position)
		Act.CAROUSEL:
			pts = [at]
		Act.LEECH:
			pts = [boss.tap_point()]
		Act.FRENZY:
			pts = [me]
		Act.SPLIT:
			var base: float = _pick.randf() * TAU
			var middle: Vector2 = boss.tree_position() + Vector2(0, 70)
			for k: int in BODIES:
				pts.append(_on_floor(middle + Vector2.from_angle(base + TAU * float(k) / 3.0) * Vector2(150.0, 100.0)))
			var first: int = _pick.randi() % 3 ## where the real one stands is anybody's guess
			var swapped: Vector2 = pts[0]
			pts[0] = pts[first]
			pts[first] = swapped
		Act.SWARM:
			pts = [at]
	_rpc_act.rpc(kind, _pick.randi(), pts, ids, _extra())


@rpc("authority", "call_local", "reliable")
func _rpc_act(kind: int, seed_v: int, pts: PackedVector2Array, ids: PackedInt32Array, extra: int) -> void:
	if mode == Mode.DEAD or mode == Mode.TRANSITION:
		return
	mode = Mode.ACT
	act = kind as Act
	_rng.seed = seed_v
	_recover_armour = 1.0
	_break_damage = 0.0
	boss.set_combat(true, 1.0)
	match act:
		Act.RESIN:
			_start_resin(pts)
		Act.PROWL:
			_start_prowl(pts)
		Act.LANCE:
			_start_lance(pts, int(_n("lance", "rounds", 4.0)) + phase, 0.0)
		Act.SPRAY:
			_start_spray(pts, extra)
		Act.FEINT:
			_start_feint(pts)
		Act.PINCER:
			_start_pincer(pts)
		Act.SHARDS:
			_start_shards(pts, extra)
		Act.BURROW:
			_start_burrow(pts, ids)
		Act.CAGE:
			_start_cage(pts)
		Act.CAROUSEL:
			_start_carousel(pts)
		Act.LEECH:
			_start_leech(pts)
		Act.FRENZY:
			_start_frenzy()
		Act.SPLIT:
			_start_split(pts)
		Act.SWARM:
			_start_swarm()
		Act.TIDE:
			_start_tide(pts)


func _finish(at: float, recover: float, armour: float = 1.0) -> void:
	_recover_armour = armour
	if _host:
		_end_at = at
		_recover = recover


# --- phase 1 -------------------------------------------------------------------------------------------------------


## One cut of body `i`: the warning lane from `from` towards `dir`, the clip timed so that its strike frame is the hit.
func _cut(i: int, t_hit: float, warn: float, from: Vector2, dir: Vector2, reach: float, half: float, damage: float, clip: String, knock: float = 110.0) -> void:
	field.add_lane(from + dir * 6.0, from + dir * reach, half, _f(t_hit - warn), _f(t_hit), damage, knock, 0 if i == 0 else PHANTOM)
	_at(t_hit - WitchBody.strike_time(clip), func() -> void:
		_play(i, clip)
		_look(i, from + dir * 20.0))
	_at(t_hit, func() -> void:
		_sound("slash", from, -2.0 if i == 0 else -7.0, randf_range(0.92, 1.12))
		fx.sparks(from + dir * reach * 0.7 + Vector2(0, -12), WitchFx.MIRROR_HOT if i == 0 else WitchFx.GREEN, 5))


## The resin combo of body `i` from `start` at `target`: a sprint in, two cuts, the stutter, the scissor.
func _combo(i: int, start: Vector2, target: Vector2, t0: float, scale: float) -> float:
	var r: Dictionary = _d("resin")
	var dir: Vector2 = (target - start).normalized() if target.distance_to(start) > 2.0 else Vector2.RIGHT
	var p1: Vector2 = _on_floor(target - dir * 32.0)
	if start.distance_to(target) < 32.0:
		p1 = start
	var damage: float = float(r.get("damage", 14.0)) * scale
	var warn: float = float(r.get("warn", 0.34))
	_at(t0, func() -> void: _move(i, p1, 0.3, "run", true, 0.0, true))
	var t1: float = t0 + 0.3 + warn
	_cut(i, t1, warn, p1, dir, 46.0, 15.0, damage, "slash_a")
	var p2: Vector2 = p1 + dir * 12.0
	var t2: float = t1 + float(r.get("beat", 0.46))
	_at(t1 + 0.1, func() -> void: _move(i, p2, 0.16, "", false))
	_cut(i, t2, warn, p2, dir, 48.0, 15.0, damage, "slash_b")
	## the micro-stutter: she freezes on the wind-up of the scissor cut, crackling, then it snaps shut
	var hold: float = float(r.get("stutter", 0.26))
	var t3: float = t2 + float(r.get("beat", 0.46)) + hold + 0.1
	var p3: Vector2 = p2 + dir * 10.0
	var lead: float = WitchBody.strike_time("slash_c")
	_at(t3 - lead - hold, func() -> void:
		_play(i, "slash_c")
		_look(i, p3 + dir * 20.0))
	_at(t3 - lead - hold + 0.085, func() -> void:
		if _host:
			_hold[i] = hold
		_nodes[i].glitch(1.6, hold)
		if i == 0:
			_sound("stutter", p3, -3.0))
	field.add_lane(p3 + dir * 4.0, p3 + dir * 58.0, 25.0, _f(t3 - 0.5), _f(t3), damage * float(r.get("final", 1.6)), 170.0, 0 if i == 0 else PHANTOM)
	_at(t3, func() -> void:
		_sound("scissor", p3, 0.0 if i == 0 else -6.0)
		fx.sparks(p3 + dir * 30.0 + Vector2(0, -12), WitchFx.VIOLET if i == 0 else WitchFx.GREEN, 12)
		if i == 0:
			boss.shake_near(p3, 1.0))
	return t3


func _start_resin(pts: PackedVector2Array) -> void:
	var last: float = _combo(0, pts[0], pts[1], _t, 1.0)
	var k: int = 1
	for j: int in range(2, pts.size()): ## a clone comes from its own side, a breath later, and hits softer
		while k < BODIES and (_on[k] == 0 or _fade_to[k] > 0.5):
			k += 1
		if k >= BODIES:
			break
		last = maxf(last, _combo(k, pts[j], pts[1], _t + 0.3 * float(j - 1), _n("clone", "damage_scale", 0.6)))
		k += 1
	_finish(last + 0.35, _n("resin", "recover", 1.1), 1.4)


func _start_prowl(pts: PackedVector2Array) -> void:
	var step: float = _n("prowl", "step", 0.21)
	for k: int in 3:
		var to: Vector2 = pts[k + 1]
		_at(_t + step * float(k), func() -> void:
			_move(0, to, step, "run", true)
			_sound("dash", to, -6.0, 1.1 + 0.1 * float(k)))
	var dir: Vector2 = (pts[4] - pts[3]).normalized() if pts[4].distance_to(pts[3]) > 2.0 else Vector2.LEFT
	var t_hit: float = _t + step * 3.0 + _n("prowl", "warn", 0.3)
	_cut(0, t_hit, _n("prowl", "warn", 0.3) + step, pts[3], dir, 50.0, 17.0, _n("prowl", "damage", 18.0), "slash_b", 150.0)
	_finish(t_hit + 0.3, _n("prowl", "recover", 0.9), 1.3)


## Roots under the feet: `rounds` locks, each at where every player stands then. `delay`: seconds before the first.
func _start_lance(pts: PackedVector2Array, rounds: int, delay: float) -> void:
	_at(_t + delay, func() -> void:
		_play(0, "cast")
		_sound("cast", real_position()))
	_at(_t + delay + WitchBody.strike_time("cast"), func() -> void:
		boss.shake_near(real_position(), 0.8)
		fx.sparks(real_position() + Vector2(0, -4), WitchFx.GREEN, 8))
	var beat: float = _n("lance", "beat", 0.42)
	for k: int in rounds:
		_at(_t + delay + 0.42 + beat * float(k), func() -> void:
			if not _host:
				return
			var spots: PackedVector2Array = PackedVector2Array()
			for player: Player in _seen():
				if spots.size() < 4:
					spots.append(player.global_position + player.velocity * (0.12 * float(k % 3)))
			if not spots.is_empty():
				_rpc_lock.rpc(Lock.LANCE, spots, PackedInt32Array()))
	if act == Act.LANCE:
		_finish(_t + delay + 0.42 + beat * float(rounds) + 0.5, _n("lance", "recover", 0.9), 1.2)


func _start_spray(pts: PackedVector2Array, extra: int) -> void:
	var s: Dictionary = _d("spray")
	_at(_t, func() -> void:
		_move(0, pts[1], 0.48, "leap", true, 24.0)
		_look(0, pts[2]))
	var t_throw: float = _t + 0.26
	var flight: float = float(s.get("flight", 0.62))
	var count: int = int(s.get("drops", 5)) + extra
	var aim: Vector2 = pts[2] - pts[1]
	var base: float = aim.angle()
	var far: float = clampf(aim.length(), 60.0, 190.0)
	var stay: float = float(s.get("stay", 3.2))
	var radius: float = float(s.get("radius", 15.0))
	for k: int in count:
		var a: float = base + (float(k) - float(count - 1) * 0.5) * float(s.get("spread", 0.26))
		var dst: Vector2 = pts[1] + Vector2.from_angle(a) * far * _rng.randf_range(0.82, 1.14)
		if not field.on_floor(dst):
			continue
		fx.add_drop(pts[1], 30.0, dst, _f(t_throw), _f(t_throw + flight), radius, stay)
		field.add_ring(dst, radius, 0.0, _f(t_throw), _f(t_throw + flight), float(s.get("damage", 8.0)), 50.0, 0, PackedFloat32Array([_f(t_throw + flight + 1.0), _f(t_throw + flight + 2.0), _f(t_throw + flight + 3.0)]))
	_at(t_throw, func() -> void: _sound("sap", pts[1]))
	_finish(_t + 0.26 + flight + 0.1, _n("spray", "recover", 0.7))


func _start_feint(pts: PackedVector2Array) -> void:
	var dir: Vector2 = (pts[1] - pts[0]).normalized() if pts[1].distance_to(pts[0]) > 2.0 else Vector2.RIGHT
	var stop: Vector2 = _on_floor(pts[1] - dir * 10.0)
	var run: float = clampf(pts[0].distance_to(stop) / float(boss.def_value("run_speed")), 0.22, 0.5)
	_at(_t, func() -> void:
		_move(0, stop, run, "run", true, 0.0, true)
		_sound("dash", pts[0], -4.0))
	_at(_t + run, func() -> void:
		fx.puff(stop, false, 18)
		_sound("vanish", stop)
		boss.set_combat(false, 1.0)
		if _host:
			_alpha[0] = 0.0)
	_at(_t + run + _n("feint", "gone", 0.24), func() -> void:
		if not _host:
			return
		var target: Player = _by_seen(_last_target)
		var at: Vector2 = target.global_position if target != null else pts[1]
		_rpc_lock.rpc(Lock.FEINT, PackedVector2Array([_on_floor(at + dir * 20.0), at]), PackedInt32Array()))
	_finish(_t + run + _n("feint", "gone", 0.24) + _n("feint", "warn", 0.32) + 0.3, _n("feint", "recover", 1.0), 1.5)


## WURZELSCHACH: rings of roots over the whole hollow, centred on her, in two (three) alternating waves: the bands of the first wave burst, then the
## bands between them. Step from a lit band into one that has just gone off.
func _start_tide(pts: PackedVector2Array) -> void:
	var w: Dictionary = _d("tide")
	var centre: Vector2 = pts[0]
	var band: float = float(w.get("band", 56.0))
	var reach: float = float(w.get("reach", 470.0))
	var warn: float = float(w.get("warn", 0.8))
	var beat: float = float(w.get("beat", 0.7))
	var waves: int = int(w.get("waves", 2)) + (1 if phase >= 2 else 0)
	var damage: float = float(w.get("damage", 16.0))
	_at(_t, func() -> void:
		_play(0, "cast")
		_sound("cast", centre, 0.0, 0.9))
	var t_first: float = _t + 0.3 + warn
	for k: int in waves:
		var t_hit: float = t_first + beat * float(k)
		var r: float = band * float(k % 2)
		while r < reach:
			field.add_ring(centre, r + band, r, _f(t_hit - warn), _f(t_hit), damage, 110.0)
			for s: int in 5: ## the roots that break out of the band
				var p: Vector2 = centre + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(r + 6.0, r + band - 6.0)
				if field.on_floor(p):
					fx.add_spear(p, _f(t_hit), _rng.randf_range(20.0, 30.0))
			r += band * 2.0
		_at(t_hit, func() -> void:
			_sound("root", centre, 0.0, 0.85 + 0.1 * float(k))
			boss.shake_near(centre, 1.1)
			_kick(0.4))
	_finish(t_first + beat * float(waves - 1) + 0.3, _n("tide", "recover", 0.7), 1.3)


# --- phase 2 -------------------------------------------------------------------------------------------------------


func _start_pincer(pts: PackedVector2Array) -> void:
	var p: Dictionary = _d("pincer")
	var centre: Vector2 = pts[0]
	var set_up: float = float(p.get("setup", 0.5))
	var warn: float = float(p.get("warn", 0.62))
	var t_run: float = _t + set_up + warn - 0.16
	var t_cross: float = _t + set_up + warn
	var slot: int = 1
	omen.shriek(set_up + warn)
	for i: int in BODIES:
		if _on[i] == 0 or _fade_to[i] > 0.5:
			continue
		var from: Vector2 = pts[slot]
		slot += 1
		var dir: Vector2 = (centre - from).normalized() if centre.distance_to(from) > 2.0 else Vector2.RIGHT
		var far: Vector2 = from + dir * minf(236.0, _reach(from, dir, 236.0) + 6.0)
		_at(_t, func() -> void: _move(i, from, set_up, "run", true))
		field.add_lane(from, far, 13.0, _f(_t + set_up), _f(t_cross - 0.04), float(p.get("damage", 16.0)) * (1.0 if i == 0 else _n("clone", "damage_scale", 0.6)), 140.0, 0 if i == 0 else PHANTOM)
		fx.add_seam(from, far, _f(_t + set_up), _f(t_cross))
		_at(t_run, func() -> void:
			_move(i, far, 0.3, "run", true)
			if i == 0:
				_sound("dash", from, 0.0, 0.85))
		_at(t_run + 0.3, func() -> void:
			_play(i, "slash_b")
			_look(i, centre))
	field.add_ring(centre, float(p.get("burst", 44.0)), 0.0, _f(_t + set_up), _f(t_cross + 0.1), float(p.get("damage", 16.0)) * 1.5, 210.0)
	_at(t_cross + 0.1, func() -> void:
		ShockRing.burst(get_tree().current_scene, centre, float(p.get("burst", 44.0)), 1.2)
		_sound("burst", centre)
		boss.shake_near(centre, 1.5)
		_kick(0.6))
	_finish(t_cross + 0.5, float(p.get("recover", 1.0)), 1.3)


## The way of a mirror shard: straight until the slate, then it glances off (twice).
func _bounce_path(from: Vector2, dir: Vector2, bounces: int, limit: float) -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array([from])
	var p: Vector2 = from
	var d: Vector2 = dir
	var gone: float = 0.0
	var left: int = bounces
	while gone < limit:
		var next: Vector2 = p + d * 3.0
		if field.on_floor(next):
			p = next
			gone += 3.0
			continue
		if left <= 0:
			break
		left -= 1
		path.append(p)
		if field.on_floor(p + Vector2(-d.x, d.y) * 5.0):
			d = Vector2(-d.x, d.y)
		elif field.on_floor(p + Vector2(d.x, -d.y) * 5.0):
			d = Vector2(d.x, -d.y)
		else:
			d = -d
	path.append(p)
	return path


func _start_shards(pts: PackedVector2Array, extra: int) -> void:
	var s: Dictionary = _d("shards")
	_at(_t, func() -> void:
		_play(0, "scream")
		_look(0, pts[1])
		_sound("mirror", pts[0]))
	var count: int = mini(int(s.get("count", 3)) + extra, 5)
	var aim: float = (pts[1] - pts[0]).angle()
	var charge: float = float(s.get("charge", 0.55))
	for k: int in count:
		var a: float = aim + (float(k) - float(count - 1) * 0.5) * float(s.get("spread", 0.34))
		var path: PackedVector2Array = _bounce_path(pts[0] + Vector2.from_angle(a) * 12.0, Vector2.from_angle(a), int(s.get("bounces", 2)), float(s.get("range", 520.0)))
		var t0: float = _t + charge + 0.12 * float(k)
		fx.add_shot(path, _f(t0), float(s.get("speed", 215.0)), float(s.get("damage", 15.0)), 120.0, charge)
		_at(t0, func() -> void: _sound("shard", pts[0], -3.0, 1.0 + 0.08 * float(k)))
	_finish(_t + charge + 0.9, float(s.get("recover", 0.6)))


func _start_burrow(pts: PackedVector2Array, ids: PackedInt32Array) -> void:
	var b: Dictionary = _d("burrow")
	_at(_t, func() -> void:
		_play(0, "cast")
		_sound("cast", pts[0], 0.0, 0.8))
	_at(_t + 0.34, func() -> void:
		fx.puff(pts[0], false, 12)
		_sound("burrow", pts[0])
		boss.set_combat(false, 1.0)
		if _host:
			_alpha[0] = 0.0
			_burrow = {"id": ids[0], "until": _t + float(b.get("hunt", 2.3)), "under": true})
	var slot: int = 0
	for i: int in range(1, BODIES): ## meanwhile the clones bind her
		if _on[i] == 1 and _fade_to[i] < 0.5:
			_combo(i, _pos[i], pts[1], _t + 0.4 + 0.5 * float(slot), _n("clone", "damage_scale", 0.6))
			slot += 1
	_finish(_t + 60.0, float(b.get("recover", 1.3)), 1.5) ## (the eruption ends it: `_on_lock`)


func _act_step(delta: float) -> void:
	if not _burrow.is_empty() and bool(_burrow.get("under", false)):
		var target: Player = _by_seen(int(_burrow["id"]))
		if target == null or target.health.current <= 0.0:
			target = _pick_target()
		var at: Vector2 = target.global_position if target != null else _pos[0]
		var step: Vector2 = at - _pos[0]
		var next: Vector2 = _pos[0] + step.normalized() * minf(_n("burrow", "speed", 132.0) * delta, step.length())
		if field.on_floor(next):
			_pos[0] = next
		if step.length() < 16.0 or _t >= float(_burrow["until"]):
			_burrow["under"] = false
			_rpc_lock.rpc(Lock.BURROW, PackedVector2Array([_pos[0]]), PackedInt32Array())
	if not _carousel.is_empty():
		var target2: Player = _by_seen(_last_target)
		var centre: Vector2 = _carousel["c"] as Vector2
		if target2 != null:
			centre = centre.lerp(target2.global_position, 1.0 - exp(-1.6 * delta)) ## the wheel drifts after her
			_carousel["c"] = centre
		_carousel["a"] = float(_carousel["a"]) + _n("carousel", "spin", 2.3) * delta
		var offs: PackedFloat32Array = _carousel["off"] as PackedFloat32Array
		var busy: PackedByteArray = _carousel["busy"] as PackedByteArray
		for i: int in BODIES:
			if _on[i] == 0 or _fade_to[i] > 0.5 or busy[i] == 1 or not _seg[i].is_empty():
				continue
			var a: float = float(_carousel["a"]) + offs[i]
			var want: Vector2 = _on_floor(centre + Vector2.from_angle(a) * Vector2(104.0, 78.0))
			_pos[i] = _pos[i].lerp(want, 1.0 - exp(-9.0 * delta))
			_face[i] = a + PI * 0.5
			_trail[i] = 1
			if _clip[i] != "run":
				_play(i, "run", true)
	if act == Act.LEECH and _heal_left > 0.0:
		_heal_left -= delta
		boss.host_heal(_n("leech", "heal", 0.012) * boss.max_health() * delta)


func _start_cage(pts: PackedVector2Array) -> void:
	var c: Dictionary = _d("cage")
	_at(_t, func() -> void:
		_play(0, "cast")
		_look(0, pts[1])
		_sound("cast", pts[0]))
	var plant: float = _t + 0.34
	var on: float = plant + float(c.get("arm", 0.75))
	var off: float = on + float(c.get("burn", 2.6))
	for j: int in range(1, pts.size()):
		var posts: PackedVector2Array = PackedVector2Array()
		var turn: float = _rng.randf() * TAU
		var count: int = int(c.get("posts", 5))
		for k: int in count:
			posts.append(pts[j] + Vector2.from_angle(turn + TAU * float(k) / float(count)) * Vector2(float(c.get("radius", 62.0)), float(c.get("radius", 62.0)) * 0.78))
		fx.add_cage(posts, _f(plant), _f(on), _f(off), float(c.get("damage", 9.0)), 90.0)
		_at(plant, func() -> void: _sound("cage", pts[j]))
		_at(on, func() -> void: _sound("threads", pts[j], -3.0))
	_start_lance(PackedVector2Array([pts[0]]), int(c.get("roots", 4)), float(c.get("arm", 0.75)) + 0.5)
	_finish(off + 0.1, float(c.get("recover", 0.7)))


# --- phase 3 -------------------------------------------------------------------------------------------------------


func _start_carousel(pts: PackedVector2Array) -> void:
	var c: Dictionary = _d("carousel")
	omen.shriek(1.4)
	_sound("whirl", pts[0])
	var count: int = 0
	var offs: PackedFloat32Array = PackedFloat32Array()
	for i: int in BODIES:
		offs.append(TAU * float(count) / float(1 + clones_on()))
		if _on[i] == 1 and _fade_to[i] < 0.5:
			count += 1
	if _host:
		var busy: PackedByteArray = PackedByteArray()
		busy.resize(BODIES)
		_carousel = {"c": pts[0], "a": _pick.randf() * TAU, "off": offs, "busy": busy}
	var first: float = float(c.get("first", 1.0))
	var beat: float = float(c.get("beat", 0.66))
	var lunges: int = int(c.get("lunges", 6))
	for k: int in lunges:
		_at(_t + first + beat * float(k), func() -> void:
			if not _host or _carousel.is_empty():
				return
			var who: int = -1
			for step: int in BODIES: ## the next body that is there
				var i: int = (k + step) % BODIES
				if _on[i] == 1 and _fade_to[i] < 0.5:
					who = i
					break
			if who < 0:
				return
			var target: Player = _by_seen(_last_target)
			var at: Vector2 = target.global_position if target != null else (_carousel["c"] as Vector2)
			_rpc_lock.rpc(Lock.LUNGE, PackedVector2Array([_pos[who], at]), PackedInt32Array([who])))
	_at(_t + first + beat * float(lunges) + 0.5, func() -> void:
		if _host:
			_carousel = {}
			for i: int in BODIES:
				_trail[i] = 0)
	_finish(_t + first + beat * float(lunges) + 0.6, float(c.get("recover", 1.1)), 1.3)


func _start_leech(pts: PackedVector2Array) -> void:
	var l: Dictionary = _d("leech")
	var tree_at: Vector2 = boss.tree_position()
	_at(_t, func() -> void:
		_move(0, pts[0], 0.55, "run", true)
		_sound("dash", real_position(), -3.0))
	_at(_t + 0.55, func() -> void:
		_play(0, "leech", true)
		if _host:
			_face[0] = -PI / 2.0
			_heal_left = float(l.get("seconds", 3.4))
		boss.tree_drain(1.0)
		_sound("leech", pts[0]))
	## three pulses: near, far, middle (or another order): step out of the band that is lit, into one that has just gone off
	var bands: Array = l.get("bands", [[0, 122], [122, 240], [240, 430]]) as Array
	var order: Array = [[0, 2, 1], [1, 0, 2], [2, 0, 1], [0, 1, 2]][_rng.randi() % 4] as Array
	var first: float = _t + 0.55 + float(l.get("first", 1.15))
	var beat: float = float(l.get("beat", 0.95))
	var warn: float = float(l.get("warn", 1.05))
	for k: int in 3:
		var band: Array = bands[int(order[k])] as Array
		var t_hit: float = first + beat * float(k)
		field.add_ring(tree_at + Vector2(0, 10), float(band[1]), float(band[0]), _f(t_hit - warn), _f(t_hit), float(l.get("damage", 20.0)), 150.0)
		fx.add_pulse(tree_at + Vector2(0, 10), float(band[0]), float(band[1]), _f(t_hit))
		_at(t_hit, func() -> void:
			_sound("pulse", tree_at, 0.0, 1.0 - 0.08 * float(k))
			boss.shake_near(tree_at, 1.2)
			_kick(0.5))
	_at(first + beat * 2.0 + 0.4, func() -> void: boss.tree_drain(0.0))
	_finish(first + beat * 2.0 + 0.5, float(l.get("recover", 0.9)), 1.2)


func _start_frenzy() -> void:
	var f: Dictionary = _d("frenzy")
	var beat: float = float(f.get("beat", 0.8))
	var dashes: int = int(f.get("dashes", 5))
	_at(_t, func() -> void:
		_play(0, "scream")
		_sound("scream", real_position(), -2.0, 1.15))
	for k: int in dashes:
		_at(_t + 0.5 + beat * float(k), func() -> void:
			if not _host:
				return
			var living: Array[Player] = _seen()
			if living.is_empty():
				return
			var at: Vector2 = living[k % living.size()].global_position ## shared out among the players
			var from: Vector2 = _pos[0]
			var dir: Vector2 = (at - from).normalized() if at.distance_to(from) > 4.0 else Vector2.from_angle(_pick.randf() * TAU)
			var far: float = minf(float(f.get("length", 300.0)), _reach(from, dir, float(f.get("length", 300.0))))
			_rpc_lock.rpc(Lock.FRENZY, PackedVector2Array([from, from + dir * maxf(far, 40.0)]), PackedInt32Array()))
	var done: float = _t + 0.5 + beat * float(dashes) + 0.75
	_at(done - 0.2, func() -> void:
		_play(0, "down")
		if _host:
			_at(_t + 0.24, func() -> void: _hold[0] = float(f.get("tired", 2.3))))
	_finish(done, float(f.get("tired", 2.3)), float(f.get("tired_armour", 1.8)))


func _start_split(pts: PackedVector2Array) -> void:
	var s: Dictionary = _d("split")
	_sound("vanish", real_position())
	for i: int in BODIES:
		if _on[i] == 0 or (_fade_to[i] > 0.5 and i > 0):
			continue
		fx.puff(_pos[i], i > 0, 12)
	boss.set_combat(false, 1.0)
	if _host:
		for i: int in BODIES:
			if _on[i] == 1:
				_fade_to[i] = 1.0
	_at(_t + 0.42, func() -> void:
		if _host:
			for i: int in BODIES:
				if _on[i] == 1:
					_pos[i] = pts[i]
					_seg[i] = {}
					_fade_to[i] = 0.0
					_back_in[i] = 0.0
					_play(i, "scream")
					_hold[i] = 9.0
		_sound("stutter", pts[0]))
	_at(_t + 0.72, func() -> void:
		boss.set_combat(true, 1.0)
		if not _host:
			return
		var living: Array[Player] = _seen()
		if living.is_empty():
			return
		var lines: PackedVector2Array = PackedVector2Array()
		var who: PackedInt32Array = PackedInt32Array()
		for i: int in BODIES:
			if _on[i] == 0:
				continue
			var at: Vector2 = living[i % living.size()].global_position
			var dir: Vector2 = (at - _pos[i]).normalized() if at.distance_to(_pos[i]) > 4.0 else Vector2.DOWN
			_face[i] = dir.angle()
			lines.append(_pos[i])
			lines.append(_pos[i] + dir * maxf(60.0, _reach(_pos[i], dir, float(s.get("length", 330.0)))))
			who.append(i)
		_rpc_lock.rpc(Lock.SPLIT, lines, who))
	var t_fire: float = _t + 0.72 + float(s.get("charge", 1.2))
	_at(t_fire, func() -> void:
		if _host:
			for i: int in BODIES:
				_hold[i] = 0.0)
	_finish(t_fire + 0.45, float(s.get("recover", 1.0)), 1.3)


func _start_swarm() -> void:
	var s: Dictionary = _d("swarm")
	var dives: int = int(s.get("dives", 6))
	var beat: float = float(s.get("beat", 0.72))
	_at(_t, func() -> void:
		_play(0, "scream")
		_sound("scream", real_position(), 2.0, 0.9)
		_kick(1.0)
		omen.panic(0.9 + beat * float(dives) + 0.8)
		fx.feather_storm(boss.tree_position(), 0.9 + beat * float(dives) + 0.6))
	for k: int in dives:
		_at(_t + 0.8 + beat * float(k), func() -> void:
			if not _host:
				return
			var living: Array[Player] = _seen()
			if living.is_empty():
				return
			var at: Vector2 = living[k % living.size()].global_position
			var dir: Vector2 = Vector2.from_angle(_pick.randf() * TAU)
			var back: float = _reach(at, -dir, 230.0)
			var fore: float = _reach(at, dir, 230.0)
			_rpc_lock.rpc(Lock.DIVE, PackedVector2Array([at - dir * back, at + dir * fore]), PackedInt32Array()))
	_finish(_t + 0.8 + beat * float(dives) + 0.7, float(s.get("recover", 0.8)), 1.2)


# --- locks: the host fixes a point late, every peer builds the same from it -----------------------------------------


@rpc("authority", "call_local", "reliable")
func _rpc_lock(tag: int, pts: PackedVector2Array, who: PackedInt32Array) -> void:
	if mode == Mode.DEAD or mode == Mode.TRANSITION:
		return
	match tag as Lock:
		Lock.LANCE:
			var l: Dictionary = _d("lance")
			var warn: float = float(l.get("warn", 0.56))
			for p: Vector2 in pts:
				if not field.on_floor(p):
					continue
				field.add_ring(p, float(l.get("radius", 15.0)), 0.0, _f(_t), _f(_t + warn), float(l.get("damage", 15.0)), 100.0)
				fx.add_spear(p, _f(_t + warn))
			_at(_t + float(l.get("warn", 0.56)), func() -> void: _sound("root", pts[0], -2.0, randf_range(0.9, 1.15)))
		Lock.FEINT:
			var warn: float = _n("feint", "warn", 0.32)
			var dir: Vector2 = (pts[1] - pts[0]).normalized() if pts[1].distance_to(pts[0]) > 2.0 else Vector2.LEFT
			fx.puff(pts[0], false, 14)
			_nodes[0].glitch(1.4, 0.14)
			boss.set_combat(true, 1.0)
			if _host:
				_pos[0] = pts[0]
				_seg[0] = {}
				_alpha[0] = 1.0
			_cut(0, _t + warn, warn, pts[0], dir, 44.0, 16.0, _n("feint", "damage", 20.0), "slash_a", 150.0)
		Lock.BURROW:
			var b: Dictionary = _d("burrow")
			var warn: float = float(b.get("warn", 0.44))
			field.add_ring(pts[0], float(b.get("radius", 32.0)), 0.0, _f(_t), _f(_t + warn), float(b.get("damage", 24.0)), 220.0)
			_at(_t + warn, func() -> void:
				ShockRing.burst(get_tree().current_scene, pts[0], float(b.get("radius", 32.0)), 1.1)
				fx.add_spear(pts[0] + Vector2(-9, 2), field.now(), 22.0)
				fx.add_spear(pts[0] + Vector2(10, -1), field.now(), 26.0)
				_sound("erupt", pts[0])
				boss.shake_near(pts[0], 1.6)
				boss.set_combat(true, 1.5)
				if _host:
					_burrow = {}
					_alpha[0] = 1.0
					_seg[0] = {"a": pts[0], "b": pts[0], "t0": _t, "dur": 0.4, "arc": 26.0, "ease": false}
					_play(0, "leap")
					_end_at = _t + 0.55)
		Lock.LUNGE:
			var c: Dictionary = _d("carousel")
			var i: int = who[0]
			var dir: Vector2 = (pts[1] - pts[0]).normalized() if pts[1].distance_to(pts[0]) > 2.0 else Vector2.RIGHT
			var far: Vector2 = pts[0] + dir * minf(208.0, _reach(pts[0], dir, 208.0) + 6.0)
			var warn: float = float(c.get("warn", 0.42))
			field.add_lane(pts[0], far, 13.0, _f(_t), _f(_t + warn), float(c.get("damage", 17.0)) * (1.0 if i == 0 else _n("clone", "damage_scale", 0.6)), 140.0, 0 if i == 0 else PHANTOM)
			if _host and not _carousel.is_empty():
				(_carousel["busy"] as PackedByteArray)[i] = 1
				_play(i, "slash_c")
				_face[i] = dir.angle()
			_at(_t + warn - 0.14, func() -> void:
				_move(i, far, 0.2, "", true)
				_sound("dash", pts[0], -3.0 if i == 0 else -8.0, 1.2))
			_at(_t + warn + 0.12, func() -> void:
				if _host and not _carousel.is_empty():
					(_carousel["busy"] as PackedByteArray)[i] = 0
					var centre: Vector2 = _carousel["c"] as Vector2
					(_carousel["off"] as PackedFloat32Array)[i] = (far - centre).angle() - float(_carousel["a"]))
		Lock.FRENZY:
			var f: Dictionary = _d("frenzy")
			var warn: float = float(f.get("warn", 0.4))
			var seam: float = float(f.get("seam", 0.85))
			field.add_lane(pts[0], pts[1], 12.0, _f(_t), _f(_t + warn), float(f.get("damage", 18.0)), 150.0)
			field.add_lane(pts[0], pts[1], 19.0, _f(_t + warn + 0.1), _f(_t + warn + seam), float(f.get("damage", 18.0)) * 0.8, 120.0)
			fx.add_seam(pts[0], pts[1], _f(_t + warn), _f(_t + warn + seam))
			_at(_t + warn - 0.12, func() -> void:
				_move(0, pts[1], 0.17, "slash_b", true)
				_sound("dash", pts[0], 1.0, randf_range(1.0, 1.3)))
			_at(_t + warn + seam, func() -> void:
				_sound("seam", pts[0].lerp(pts[1], 0.5), -2.0)
				_kick(0.4))
		Lock.SPLIT:
			var s: Dictionary = _d("split")
			var charge: float = float(s.get("charge", 1.2))
			omen.shriek(charge)
			for k: int in who.size():
				var i: int = who[k]
				var a: Vector2 = pts[k * 2]
				var b: Vector2 = pts[k * 2 + 1]
				field.add_lane(a, b, float(s.get("half", 14.0)), _f(_t), _f(_t + charge), float(s.get("damage", 28.0)) if i == 0 else 0.0, 200.0)
				fx.add_beam(a, a, b, _f(_t), _f(_t + charge), i == 0)
			_sound("charge", pts[0])
			_at(_t + charge, func() -> void:
				_sound("beam", pts[0])
				boss.shake_near(pts[0], 1.8)
				_kick(0.9))
		Lock.DIVE:
			var s: Dictionary = _d("swarm")
			var warn: float = float(s.get("warn", 0.78))
			field.add_lane(pts[0], pts[1], float(s.get("half", 16.0)), _f(_t), _f(_t + warn), float(s.get("damage", 14.0)), 130.0)
			omen.dive(pts[0], pts[1], warn)
			_at(_t + warn, func() -> void: _sound("dive", pts[0].lerp(pts[1], 0.5), -2.0, randf_range(0.9, 1.2)))
		Lock.CLONE: ## a clone's own attack: 0 the resin combo, 1 a dash cut, 2 roots under the target
			var i: int = who[0]
			var scale: float = _n("clone", "damage_scale", 0.6)
			var dir: Vector2 = (pts[1] - pts[0]).normalized() if pts[1].distance_to(pts[0]) > 2.0 else Vector2.RIGHT
			match who[1]:
				0:
					_combo(i, pts[0], pts[1], _t, scale)
				1:
					var stop: Vector2 = _on_floor(pts[1] - dir * 30.0)
					_at(_t, func() -> void:
						_move(i, stop, 0.26, "run", true, 0.0, true)
						_sound("dash", pts[0], -8.0, 1.2))
					_cut(i, _t + 0.56, 0.56, stop, dir, 50.0, 16.0, _n("prowl", "damage", 18.0) * scale, "slash_b", 140.0)
				_:
					var l: Dictionary = _d("lance")
					var warn: float = float(l.get("warn", 0.56)) + 0.1
					_at(_t, func() -> void:
						_play(i, "cast")
						_look(i, pts[1]))
					for k: int in 3:
						var p: Vector2 = pts[1] + Vector2.from_angle(_rng.randf() * TAU) * (0.0 if k == 0 else 26.0)
						if field.on_floor(p):
							field.add_ring(p, float(l.get("radius", 15.0)), 0.0, _f(_t + 0.12 * float(k)), _f(_t + warn + 0.12 * float(k)), float(l.get("damage", 15.0)) * scale, 90.0, PHANTOM)
							fx.add_spear(p, _f(_t + warn + 0.12 * float(k)), 22.0)
					_at(_t + warn, func() -> void: _sound("root", pts[1], -7.0, 1.2))
		Lock.SWAP_CUT:
			var i: int = who[0]
			var dir: Vector2 = (pts[1] - pts[0]).normalized() if pts[1].distance_to(pts[0]) > 2.0 else Vector2.RIGHT
			_cut(i, _t + 0.36, 0.36, pts[0], dir, 46.0, 15.0, _n("resin", "damage", 14.0) * _n("clone", "damage_scale", 0.6), "slash_a")


# --- struck --------------------------------------------------------------------------------------------------------


## Host: a blow landed on the real witch.
func on_damaged(amount: float, knockback: float) -> void:
	if not _host or mode == Mode.DEAD or mode == Mode.TRANSITION or mode == Mode.ENTRANCE:
		return
	if mode == Mode.ACT and act in [Act.LEECH, Act.SPLIT]: ## these can be broken: enough damage, or one heavy blow
		_break_damage += amount
		var need: float = _n("leech" if act == Act.LEECH else "split", "break", 0.05) * boss.max_health() * (1.0 + 0.5 * float(_extra()))
		if _break_damage >= need or knockback >= float(boss.def_value("heavy_knockback")):
			_heal_left = 0.0
			_rpc_mode.rpc(Mode.STAGGER, _n("stagger", "seconds", 1.9))
		return
	if phase >= 1 and mode in [Mode.IDLE, Mode.RECOVER] and _swap_cd <= 0.0 and clones_on() > 0 and _pick.randf() < _n("swap", "chance", 0.6):
		var options: Array[int] = []
		for i: int in range(1, BODIES):
			if _on[i] == 1 and _fade_to[i] < 0.5:
				options.append(i)
		var k: int = options[_pick.randi() % options.size()]
		_swap_cd = _n("swap", "cooldown", 7.0) / (1.0 + 0.25 * float(_extra()))
		var a: Vector2 = _pos[0]
		_pos[0] = _pos[k]
		_pos[k] = a
		_seg[0] = {}
		_seg[k] = {}
		_rpc_swap.rpc(k, a, _pos[0])
		var target: Player = _by_seen(_last_target)
		if target != null: ## the phantom she left in her place cuts at once
			_rpc_lock.rpc(Lock.SWAP_CUT, PackedVector2Array([a, target.global_position]), PackedInt32Array([k]))


@rpc("authority", "call_local", "reliable")
func _rpc_swap(k: int, a: Vector2, b: Vector2) -> void:
	fx.puff(a, true, 14)
	fx.puff(b, false, 14)
	_nodes[0].glitch(2.0, 0.22)
	_nodes[k].glitch(2.0, 0.22)
	_sound("swap", a)
	_kick(0.5)
	omen.shriek(1.7) ## the ravens know where she went


## Host: a blade went through clone `i`.
func clone_struck(i: int, from: Vector2) -> void:
	if not _host or _on[i] == 0 or _fade_to[i] > 0.5 or mode == Mode.DEAD:
		return
	_fade_to[i] = 1.0
	_seg[i] = {}
	_back_in[i] = _n("clone", "return", 4.5) - 0.8 * float(phase - 1)
	_rpc_poof.rpc(i, _pos[i], from)


@rpc("authority", "call_local", "reliable")
func _rpc_poof(i: int, at: Vector2, _from: Vector2) -> void:
	fx.puff(at, true, 22)
	_nodes[i].glitch(2.0, 0.2)
	_sound("poof", at, -2.0, randf_range(0.9, 1.15))


# --- the entrance: she falls out of the crown ----------------------------------------------------------------------


func _begin_entrance(elapsed: float) -> void:
	var e: Dictionary = _d("entrance")
	var wait: float = float(e.get("wait", 1.5))
	var fall: float = float(e.get("fall", 0.5))
	var high: float = boss.crown_height()
	mode = Mode.ENTRANCE
	boss.set_combat(false, 1.0)
	_set_world_directors_active(false)
	_alpha[0] = 0.0
	_h[0] = high
	_clip[0] = "down"
	_ct[0] = 0.6
	_loop[0] = 0
	_hold[0] = 99.0
	_t = elapsed
	_at(0.2, func() -> void:
		_sound("scream", boss.tree_position() + Vector2(0, -120), 0.0, 1.1)
		omen.panic(wait + 1.0)
		boss.shake_near(boss.tree_position(), 0.7))
	_at(wait - 0.2, func() -> void: _sound("crack", boss.tree_position() + Vector2(0, -120)))
	_at(wait, func() -> void: ## she drops head first
		_alpha[0] = 1.0
		if _host:
			_seg[0] = {})
	var steps: int = 12
	for k: int in steps + 1:
		_at(wait + fall * float(k) / float(steps), func() -> void:
			var q: float = float(k) / float(steps)
			if _host:
				_h[0] = high * (1.0 - q * q))
	_at(wait + fall, func() -> void:
		_landed = true
		_entrance_t = wait + fall + float(e.get("card", 4.6))
		if _host:
			_h[0] = 0.0
		ShockRing.burst(get_tree().current_scene, real_position(), 46.0, 1.3)
		ShadowPatch.spawn(get_tree().current_scene, real_position(), Vector2i(86, 58), 6.0, 4.0, 7)
		_sound("land", real_position())
		boss.shake_near(real_position(), 2.2)
		boss.touched_down.emit())
	for k: int in 3: ## she glitches in three ghost images before her body holds
		_at(wait + fall + 0.12 + 0.2 * float(k), func() -> void:
			_nodes[0].glitch(2.2, 0.16)
			_nodes[0]._leave_image()
			_sound("stutter", real_position(), -4.0, 0.8 + 0.2 * float(k)))
	_at(wait + fall + 1.5, func() -> void: ## she jerks upright: the collapse played backwards
		if _host:
			_hold[0] = 0.0
		_rise_from = _t)
	_at(wait + fall + 2.6, func() -> void: ## and whets the sickles
		_rise_from = -1.0
		_play(0, "slash_c")
		if _host:
			_at(_t + 0.09, func() -> void: _hold[0] = 0.7)
		_sound("whet", real_position()))
	_at(wait + fall + 3.5, func() -> void: _play(0, "idle", true))


var _rise_from: float = -1.0


# --- the phases turn -----------------------------------------------------------------------------------------------


@rpc("authority", "call_local", "reliable")
func _rpc_transition(next_phase: int, at: Vector2) -> void:
	mode = Mode.TRANSITION
	act = Act.NONE
	_events.clear()
	field.clear()
	fx.clear()
	boss.set_combat(false, 1.0)
	boss.tree_drain(0.0)
	var tr: Dictionary = _d("transition%d" % next_phase)
	var scream: float = float(tr.get("scream_at", 1.1))
	var to_tree: bool = next_phase >= 2
	if _host:
		_burrow = {}
		_carousel = {}
		_end_at = -1.0
		_alpha[0] = 1.0
		_fade_to[0] = 0.0
		_seg[0] = {}
		_pos[0] = at
		if to_tree: ## "NÄHRE MICH!": she throws herself at the trunk
			_move(0, boss.tap_point(), 0.7, "run", true)
			_at(_t + 0.7, func() -> void:
				_play(0, "leech", true)
				_face[0] = -PI / 2.0)
		else:
			_play(0, "scream")
			_at(_t + 0.16, func() -> void: _hold[0] = scream - 0.3)
	_nodes[0].glitch(2.0, 0.3)
	_sound("crack" if not to_tree else "scream", at)
	boss.say(String(tr.get("line", "")))
	for k: int in 5:
		_at(_t + 0.15 + (scream - 0.2) * float(k) / 5.0, func() -> void: _nodes[0].glitch(1.2 + 0.3 * float(k), 0.12))
	if DisplayServer.get_name() != "headless":
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(boss.tree_position()) < 620.0:
				BossPhaseScreen.play(boss, player, String(tr.get("text", "")), tr)
				break
	if to_tree:
		_at(_t + 0.8, func() -> void:
			boss.tree_drain(1.0)
			boss.tree_hour(1.0)
			_sound("leech", boss.tap_point()))
	_at(_t + scream, func() -> void:
		phase = next_phase
		for node: WitchBody in _nodes:
			if is_instance_valid(node):
				node.set_look(phase)
		var here: Vector2 = real_position()
		ShockRing.burst(get_tree().current_scene, here, 150.0, 1.6)
		fx.sparks(here + Vector2(0, -34), WitchFx.MIRROR_HOT, 26)
		fx.puff(here, false, 20)
		_sound("shatter", here, 2.0)
		boss.shake_near(here, 2.4)
		boss.tree_drain(0.0)
		_kick(1.0)
		omen.set_mood(phase)
		if not _host:
			return
		for player: Player in Player.all: ## the pressure throws everybody back
			if player.health.current > 0.0 and player.global_position.distance_to(here) < float(tr.get("push_radius", 190.0)):
				var box: HurtboxComponent = player.get_node_or_null("Hurtbox") as HurtboxComponent
				if box != null:
					box.take_hit(float(tr.get("push_damage", 2.0)), here, float(tr.get("push_knock", 270.0)))
		_play(0, "scream")
		_ct[0] = 0.3
		_on[phase] = 1 ## a clone tears itself off her
		_pos[phase] = here
		_fade_to[phase] = 0.0
		_diss[phase] = 1.0
		_back_in[phase] = 0.0
		_play(phase, "scream")
		_ct[phase] = 0.3
		_at(_t + 0.3, func() -> void: _move(phase, _on_floor(here + Vector2(54.0 if phase == 1 else -54.0, 22.0)), 0.45, "run", true)))
	_at(_t + float(tr.get("end", 3.7)), func() -> void:
		if not _host:
			return
		boss.set_floor(_floor_for(phase))
		boss.host_set_health_fraction(float((_spec.get("phases", [0.66, 0.33]) as Array)[phase - 1]) - 0.015)
		_rpc_mode.rpc(Mode.IDLE, 1.0))


# --- the end: she is released --------------------------------------------------------------------------------------


## Every peer (the health's `died`).
func on_died() -> void:
	mode = Mode.DEAD
	act = Act.NONE
	_events.clear()
	field.clear()
	fx.clear()
	boss.set_combat(false, 1.0)
	boss.tree_drain(0.0)
	_dead_t = 0.0
	omen.set_mood(-1)
	_sound("death", real_position())
	if _host:
		_burrow = {}
		_carousel = {}
		_seg[0] = {}
		_alpha[0] = 1.0
		_fade_to[0] = 0.0
		_h[0] = 0.0
		_play(0, "down")
		for i: int in range(1, BODIES):
			_fade_to[i] = 1.0
			_back_in[i] = 0.0
	for i: int in range(1, BODIES):
		if _on[i] == 1:
			fx.puff(_pos[i], true, 18)
	var r: Dictionary = _d("release")
	var clear_at: float = float(r.get("clear_at", 1.6))
	_at(_t + clear_at, func() -> void: ## for two seconds her eyes are her own
		for node: WitchBody in _nodes:
			if is_instance_valid(node):
				node.set_look(0)
		boss.say(String(r.get("line", ""))))
	_at(_t + float(r.get("dust_at", 3.4)), func() -> void:
		_sound("release", real_position())
		boss.tree_hour(0.0)
		boss.tree_free())


func _step_death(delta: float) -> void:
	_dead_t += delta
	var r: Dictionary = _d("release")
	var dust_at: float = float(r.get("dust_at", 3.4))
	var gone_at: float = float(r.get("gone_at", 5.6))
	if _dead_t > dust_at and _dead_t < gone_at and Engine.get_physics_frames() % 3 == 0:
		fx.gold_dust(real_position(), 3)
	if _dead_t > dust_at:
		_nodes[0].alpha = 1.0 - smoothstep(dust_at, gone_at, _dead_t)
		if _host:
			_alpha[0] = _nodes[0].alpha
	if _host and _dead_t > gone_at + 1.2:
		boss.queue_free()


# --- a joining peer ------------------------------------------------------------------------------------------------


func request_sync() -> void:
	_request_sync.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_sync() -> void:
	if multiplayer.is_server():
		_sync.rpc_id(multiplayer.get_remote_sender_id(), phase, mode, _t)


@rpc("authority", "call_remote", "reliable")
func _sync(p_phase: int, p_mode: int, elapsed: float) -> void:
	phase = p_phase
	for node: WitchBody in _nodes:
		if is_instance_valid(node):
			node.set_look(phase)
	omen.set_mood(phase)
	if phase >= 2:
		boss.tree_hour(1.0)
	if p_mode != Mode.ENTRANCE:
		_events.clear()
		_landed = true
		mode = p_mode as Mode
		_t = elapsed
		boss.set_combat(mode in [Mode.IDLE, Mode.ACT, Mode.RECOVER, Mode.STAGGER], 1.0)
