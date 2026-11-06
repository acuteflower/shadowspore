class_name FishingComponent
extends Node
## Angeln (docs/fishing.md). A child of every Player. The HOST decides everything (target, drift, bite, the
## fight, the catch); the owner only sends intentions (cast, strike, twitch, give line, reel in) and every peer
## replays the state packets, so all of them see the same line, the same shadow, the same fight.

enum S { IDLE, CASTING, DRIFTING, NIBBLE, BITE, DRILL }

signal state_changed(state: int)
signal fx(kind: String, pos: Vector2, data: Dictionary) ## every peer: "splash", "tap", "bite", "approach", "lost", "landed" ...
signal caught(species: String, length: int, is_record: bool, prime: bool) ## the owner only: show the card (prime = landed with a helper's net)

const SWERVES: Array[float] = [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.7, -1.7, PI]
const PULL_CELL: float = 6.0
const PULL_N: int = 81 ## 486 px square around her
const MAX_TURN: float = 3.0 ## rad/s: the most a fish turns
const SPEED_UP: float = 140.0 ## px/s per s
const SLOW_DOWN: float = 110.0
const ROD_TIP: float = 43.0 ## px from the grip to the tip in rod_basic_held.png

var state: int = S.IDLE
var rod_id: String = ""
var bobber: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var cast_pose: String = "cork"
var species: String = "" ## known to everybody from the first approach on (the shadow shows it)
var approach_from: Vector2 = Vector2.ZERO
var approach_time: float = 0.0 ## seconds left of the shadow's swim to the float
var approach_total: float = 1.0
var tension: float = 0.0
var dist: float = 0.0
var phase: String = "flee"
var tell: bool = false
var heading: Vector2 = Vector2.RIGHT
var casting_time: float = 0.0 ## 0..1 of the throw (after the wind-up, when the float leaves the rod)
var _cast_clock: float = 0.0
var anim: String = "" ## which body clip of player_fish.png plays ("" = none, she uses the normal sheets)
var anim_time: float = 0.0
var _oneshot: String = ""
var _oneshot_t: float = 0.0
static var _fish_rig: Dictionary = {}
static var _fish_hand: PackedVector2Array = PackedVector2Array()
static var _fish_shoulder: PackedVector2Array = PackedVector2Array()
static var _fish_rod: PackedVector3Array = PackedVector3Array()
var netted: bool = false ## a friend holds the landing net under the fish: no more breaking, a prime catch
var bait: String = "" ## the owner's choice
var pose: String = "cork"
var aim_point: Vector2 = Vector2.ZERO ## owner: where the cast would land
var aim_valid: bool = false
var aim_reason: String = ""
var book: FishBook ## the owner's river book

var _player: Player
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _t: float = 0.0
var _bite_t: float = -1.0
var _bite_species: String = ""
var _approaching: bool = false
var _scared: Array = []
var _twitches: Array[float] = []
var _taps_left: int = 0
var _tap_t: float = 0.0
var _window: float = 0.0
var _drill: Dictionary = {}
var _fled_seen: int = 1
var _give: float = 0.0
var _reel: bool = false
var _sync_t: float = 0.0
var _drift_check: float = 0.0
var _idle_time: float = 0.0
var _splash_t: float = 0.0
var _fvel: Vector2 = Vector2.ZERO ## the fish's swim velocity: it speeds up and turns smoothly, it never teleports
var _shore: Vector2 = Vector2.ZERO ## the water point nearest to her feet: where a fish is landed
var _shore_gap: float = 0.0
var _shore_from: Vector2 = Vector2(-9999, -9999)
var _pull: PackedFloat32Array = PackedFloat32Array() ## swim distance to the landing point over open water (PULL_N x PULL_N cells)
var _pull_origin: Vector2 = Vector2.ZERO
var _run_sign: float = 1.0 ## up or down the river
var _wander: float = 0.0
var _leaps_done: int = 0
var _scare_n: int = 0
var _cooldown: float = 0.0
var _hold_t: float = -1.0 ## owner: how long the button has been down while the float drifts
var _giving: bool = false
var _input_t: float = 0.0
var _last_sent: Vector2 = Vector2(-9, -9)
var _bait_i: int = 0
var _pose_i: int = 0
var _view: FishingView
var _creak: AudioStreamPlayer2D


func _ready() -> void:
	_player = get_parent() as Player
	_rng.randomize()
	_load_fish_rig()
	if is_multiplayer_authority():
		book = FishBook.new()
		var card: FishCard = FishCard.new()
		card.name = "FishCard"
		_player.add_child(card)
		card.bind(self)
	var spot: FishNetSpot = FishNetSpot.new()
	spot.name = "NetSpot"
	add_child(spot)
	spot.bind(self, _player)
	_view = FishingView.new()
	_view.name = "FishingView"
	add_child(_view)
	_view.bind(self, _player)
	_creak = AudioStreamPlayer2D.new()
	_creak.name = "Creak"
	_creak.stream = _wav("creak", true)
	_creak.max_distance = 260.0
	_creak.volume_db = -80.0
	add_child(_creak)
	_player.health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void:
		if multiplayer.is_server() and state != S.IDLE:
			_host_end("", ""))


# ---------------------------------------------------------------------------------------------- queries

static func rod_def(item_id: String) -> Dictionary:
	return DataRegistry.get_entry("items", item_id)


## The rod in her hand on this machine (the replicated held item, so remote peers know too).
func rod_item() -> String:
	var held: String = _player.attack.held_weapon
	return held if held != "" and String(rod_def(held).get("tool", "")) == "rod" else ""


func rod_active() -> bool:
	return rod_item() != ""


func locks_movement() -> bool:
	return state == S.DRILL or state == S.CASTING or animating()


func tip() -> Vector2:
	return _player.attack.tip_position(ROD_TIP)


func feet() -> Vector2:
	return _player.global_position


func _rivers() -> WorldRivers:
	for patch: Node in Terrain.patches:
		if patch is WorldRivers:
			return patch as WorldRivers
	return null


func _field(point: Vector2) -> Vector2:
	var rivers: WorldRivers = _rivers()
	return rivers.field_at(point) if rivers != null else Vector2(INF, 0.0)


func _flow(point: Vector2) -> Vector2:
	var rivers: WorldRivers = _rivers()
	return rivers.fauna.flow_at(point) if rivers != null and rivers.fauna != null else Vector2.ZERO


func stand_ok() -> bool:
	var s: Dictionary = FishingRules.settings()["stand"] as Dictionary
	var x: float = _field(feet()).x
	return x >= float(s["x_min"]) and x <= float(s["x_max"])


func _cfg() -> Dictionary:
	return FishingRules.settings()


func bait_choices() -> Array[String]:
	var out: Array[String] = [""]
	var baits: Dictionary = DataRegistry.table("fishing")["baits"] as Dictionary
	for id: String in baits:
		if _player.inventory.count_item(id) > 0:
			out.append(id)
	return out


func pose_choices() -> Array[String]:
	var out: Array[String] = []
	var poses: Dictionary = FishingRules.poses()
	for id: String in poses:
		var needs: String = String((poses[id] as Dictionary)["needs"])
		if needs == "" or _player.inventory.count_item(needs) > 0:
			out.append(id)
	return out


## Dev: the bank spot nearest to `from` with open water in front of it (the baked ford banks), or `Vector2.INF`.
static func nearest_bank(tree: SceneTree, from: Vector2) -> Vector2:
	var rivers: WorldRivers
	for patch: Node in Terrain.patches:
		if patch is WorldRivers:
			rivers = patch as WorldRivers
	if rivers == null:
		return Vector2.INF
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for ford: Array in DataRegistry.table("rivers_baked")["fords"]:
		var centre: Vector2 = Vector2(float(ford[0]), float(ford[1]))
		if centre.distance_to(from) > best_d + 200.0:
			continue
		for a: int in 16:
			var dir: Vector2 = Vector2.from_angle(float(a) / 16.0 * TAU)
			for r: int in range(20, 160, 2):
				var stand: Vector2 = centre + dir * float(r)
				var x: float = rivers.field_at(stand).x
				if x < 3.0 or x > 9.0:
					continue
				for reach: int in range(36, 120, 6):
					var target: Vector2 = stand - dir * float(reach)
					if rivers.field_at(target).x <= -12.0 and rivers.field_at(target + Vector2(10, 0)).x <= -8.0 and stand.distance_to(from) < best_d:
						best = stand
						best_d = stand.distance_to(from)
						break
				break
	return best


# ---------------------------------------------------------------------------------------------- body animation

static func _load_fish_rig() -> void:
	if not _fish_rig.is_empty():
		return
	_fish_rig = DataRegistry.table("hero_rig").get("fish", {}) as Dictionary
	for point: Array in _fish_rig.get("hand", []):
		_fish_hand.append(Vector2(float(point[0]), float(point[1])))
	for point: Array in _fish_rig.get("shoulder", []):
		_fish_shoulder.append(Vector2(float(point[0]), float(point[1])))
	for value: Array in _fish_rig.get("rod", []):
		_fish_rod.append(Vector3(float(value[0]), float(value[1]), float(value[2])))


func _clip(name: String) -> Dictionary:
	return (_fish_rig.get("clips", {}) as Dictionary).get(name, {}) as Dictionary


func _oneshot_for(kind: String, data: Dictionary) -> String:
	match kind:
		"hook": return "strike"
		"landed": return "land"
		"lost": return "snap" if String(data.get("reason", "")) == "snapped" else "sag"
	return ""


func _anim_tick(delta: float) -> void:
	if _fish_rig.is_empty():
		return
	anim_time += delta
	var want: String = ""
	if not rod_active() or _player.health.current <= 0.0:
		_oneshot = ""
	elif _oneshot != "":
		_oneshot_t += delta
		var clip: Dictionary = _clip(_oneshot)
		if _oneshot_t >= float(clip["count"]) / float(clip["fps"]):
			_oneshot = ""
		else:
			want = _oneshot
	if want == "" and rod_active():
		match state:
			S.CASTING: want = "cast"
			S.DRIFTING, S.NIBBLE, S.BITE: want = "ready"
			S.DRILL: want = "brace" if tell else ("flee" if phase == "flee" else "reel")
	if want != anim:
		anim = want
		anim_time = 0.0
	if anim == "cast":
		anim_time = _cast_clock ## the throw follows the host's clock exactly


## True while a clip locks her in place (the owner cannot walk off in the middle of a throw or a fight).
func animating() -> bool:
	return anim != "" and anim != "ready"


## The sprite frame, rig points and rod pose of the current clip for her view `sector`, or {} (use the normal sheets).
func body_frame(sector: int, moving: bool) -> Dictionary:
	if anim == "" or _fish_rig.is_empty() or (anim == "ready" and moving):
		return {}
	var clip: Dictionary = _clip(anim)
	var count: int = int(clip["count"])
	var position_in_clip: float = anim_time * float(clip["fps"])
	var loop: bool = bool(clip["loop"])
	position_in_clip = fposmod(position_in_clip, float(count)) if loop else clampf(position_in_clip, 0.0, float(count - 1))
	var i: int = int(position_in_clip)
	var next: int = (i + 1) % count if loop else mini(i + 1, count - 1)
	var k: float = position_in_clip - float(i)
	var cols: int = int(_fish_rig["cols"])
	var a: int = int(clip["start"]) + i
	var b: int = int(clip["start"]) + next
	return {
		"frame": sector * cols + a,
		"cols": cols,
		"hand": _fish_hand[sector * cols + a].lerp(_fish_hand[sector * cols + b], k),
		"shoulder": _fish_shoulder[sector * cols + a].lerp(_fish_shoulder[sector * cols + b], k),
		"rod": _fish_rod[a].lerp(_fish_rod[b], k),
	}


# ---------------------------------------------------------------------------------------------- owner: input

static func _wav(name: String, loop: bool = false) -> AudioStreamWAV:
	var path: String = "res://assets/audio/fishing/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStreamWAV = load(path) as AudioStreamWAV
	if loop and stream != null:
		stream = stream.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


func _play(name: String, pos: Vector2, pitch: float = 1.0) -> void:
	var stream: AudioStreamWAV = _wav(name)
	if stream == null or not is_inside_tree():
		return
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = stream
	voice.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	voice.max_distance = 300.0
	voice.volume_db = -6.0
	voice.global_position = pos
	voice.finished.connect(voice.queue_free)
	_player.get_parent().add_child(voice)
	voice.play()


## The line sings under load: louder and higher with the tension (a second cue next to its colour).
func _update_creak() -> void:
	if _creak == null or _creak.stream == null:
		return
	if state == S.DRILL and tension > 0.3:
		if not _creak.playing:
			_creak.play()
		_creak.global_position = bobber
		_creak.pitch_scale = lerpf(0.7, 1.9, clampf((tension - 0.3) / 0.7, 0.0, 1.0))
		_creak.volume_db = lerpf(-24.0, -4.0, clampf((tension - 0.3) / 0.7, 0.0, 1.0))
	elif _creak.playing:
		_creak.stop()


func _physics_process(delta: float) -> void:
	_update_creak()
	_cooldown = maxf(0.0, _cooldown - delta)
	_cast_clock = _cast_clock + delta if state == S.CASTING else 0.0
	var cast_cfg: Dictionary = _cfg()["cast"] as Dictionary
	casting_time = clampf((_cast_clock - float(cast_cfg["windup"])) / float(cast_cfg["flight"]), 0.0, 1.0)
	_anim_tick(delta)
	if multiplayer.is_server():
		_host_tick(delta)
	if is_multiplayer_authority():
		_owner_tick(delta)


func _owner_tick(delta: float) -> void:
	var alive: bool = _player.health.current > 0.0
	if InputManager.fish_book_pressed() and not InputManager.ui_blocking:
		var hud: Node = _player.get("_hud") as Node
		if hud != null and hud.has_node("RiverBook"):
			(hud.get_node("RiverBook") as RiverBook).toggle()
	var active: bool = rod_active() and alive
	aim_valid = false
	if not active:
		if state != S.IDLE:
			_send("reel", [])
		_hold_t = -1.0
		return
	# keep the choices valid
	var baits: Array[String] = bait_choices()
	var poses: Array[String] = pose_choices()
	_bait_i = clampi(_bait_i, 0, baits.size() - 1)
	_pose_i = clampi(_pose_i, 0, poses.size() - 1)
	if state == S.IDLE:
		if InputManager.fish_bait_pressed():
			_bait_i = (_bait_i + 1) % baits.size()
		if InputManager.fish_pose_pressed():
			_pose_i = (_pose_i + 1) % poses.size()
	bait = baits[_bait_i]
	pose = poses[_pose_i]
	if state != S.IDLE:
		var to: Vector2 = bobber - feet()
		if to.length() > 4.0:
			_player.facing = to.normalized()
	match state:
		S.IDLE:
			_update_aim()
			if InputManager.fish_press() and aim_valid and _cooldown <= 0.0:
				_send("cast", [aim_point, bait, pose])
				_cooldown = float((_cfg()["cast"] as Dictionary)["cooldown"])
		S.CASTING:
			pass
		S.DRIFTING:
			_drift_input(delta)
		S.NIBBLE, S.BITE:
			if InputManager.fish_press():
				_send("strike", [])
			elif InputManager.fish_reel_in_pressed():
				_send("reel", [])
		S.DRILL:
			_drill_input(delta)
	if state == S.DRIFTING and InputManager.fish_reel_in_pressed():
		_send("reel", [])


func _update_aim() -> void:
	var cast_cfg: Dictionary = _cfg()["cast"] as Dictionary
	var from: Vector2 = feet()
	var want: Vector2 = InputManager.aim_world_position()
	var offset: Vector2 = want - from
	var reach: float = minf(float(cast_cfg["max"]), float(FishingRules.rods().get(rod_item(), {"cast": 130.0})["cast"]))
	if offset.length() > reach:
		offset = offset.normalized() * reach
	aim_point = from + offset
	aim_reason = ""
	if _player.is_busy():
		aim_reason = "busy"
	elif not stand_ok():
		aim_reason = "stand"
	elif offset.length() < float(cast_cfg["min"]):
		aim_reason = "near"
	elif _field(aim_point).x > float(cast_cfg["target_x_max"]):
		aim_reason = "land"
	aim_valid = aim_reason == ""


func _drift_input(_delta: float) -> void:
	var drift: Dictionary = _cfg()["drift"] as Dictionary
	if InputManager.fish_press():
		_hold_t = 0.0
	elif _hold_t >= 0.0 and InputManager.fish_held():
		_hold_t += _delta
		if _hold_t >= float(drift["give_hold"]) and not _giving:
			_giving = true
			_send("give", [true])
	elif _hold_t >= 0.0:
		if _giving:
			_giving = false
			_send("give", [false])
		else:
			_send("twitch", [])
		_hold_t = -1.0


func _drill_input(delta: float) -> void:
	var to: Vector2 = (bobber - feet())
	var dir: Vector2 = InputManager.move_vector()
	var give: float = 0.0
	if to.length() > 1.0 and dir != Vector2.ZERO:
		give = clampf(dir.normalized().dot(to.normalized()), 0.0, 1.0)
	var reel: bool = InputManager.fish_held()
	if multiplayer.is_server():
		_give = give
		_reel = reel
		return
	_input_t -= delta
	if Vector2(give, 1.0 if reel else 0.0) != _last_sent or _input_t <= 0.0:
		_last_sent = Vector2(give, 1.0 if reel else 0.0)
		_input_t = 0.15
		_rpc_input.rpc_id(1, give, reel)


func _send(kind: String, args: Array) -> void:
	if multiplayer.is_server():
		_host_request(kind, args)
	else:
		_rpc_request.rpc_id(1, kind, args)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(kind: String, args: Array) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_host_request(kind, args)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_input(give: float, reel: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_give = clampf(give, 0.0, 1.0)
		_reel = reel


## Someone else holds the net under the fish: the friend's E (FishNetSpot) asks the host.
func request_net() -> void:
	if multiplayer.is_server():
		_host_net(_local_helper())
	else:
		_rpc_net.rpc_id(1)


func _local_helper() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var other: Player = node as Player
		if other != null and other.is_multiplayer_authority():
			return other
	return null


@rpc("any_peer", "call_remote", "reliable")
func _rpc_net() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	for node: Node in get_tree().get_nodes_in_group("players"):
		var other: Player = node as Player
		if other != null and other.get_multiplayer_authority() == sender:
			_host_net(other)
			return


## Host: the helper must be another living player close to the fish while it is near the bank.
func _host_net(helper: Player) -> bool:
	var net: Dictionary = _cfg()["net"] as Dictionary
	if state != S.DRILL or netted or helper == null or helper == _player or helper.health.current <= 0.0:
		return false
	if dist > float(net["range"]) or helper.global_position.distance_to(bobber) > float(net["reach"]):
		return false
	netted = true
	_fx_all("net", bobber, {})
	_broadcast()
	return true


# ---------------------------------------------------------------------------------------------- host

func _host_rod() -> String:
	var stack: Dictionary = _player.inventory.active_stack()
	if stack.is_empty():
		return ""
	return String(stack["id"]) if String(rod_def(String(stack["id"])).get("tool", "")) == "rod" else ""


func _host_request(kind: String, args: Array) -> void:
	if _player.health.current <= 0.0:
		return
	match kind:
		"cast":
			if args.size() == 3 and args[0] is Vector2 and args[1] is String and args[2] is String: ## the owner's packet is not trusted
				_host_cast(args[0] as Vector2, String(args[1]), String(args[2]))
		"strike":
			if state == S.BITE:
				_host_hook()
			elif state == S.NIBBLE:
				_host_end("early", "")
		"twitch":
			if state == S.DRIFTING or state == S.NIBBLE:
				_host_twitch()
		"give":
			_give = 1.0 if args.size() == 1 and args[0] is bool and bool(args[0]) else 0.0
		"reel":
			if state != S.IDLE and state != S.DRILL:
				_host_end("", "")


func _host_cast(at: Vector2, bait_id: String, pose_id: String) -> void:
	var rod: String = _host_rod()
	if state != S.IDLE or rod == "" or _player.is_busy():
		return
	var cast_cfg: Dictionary = _cfg()["cast"] as Dictionary
	var offset: Vector2 = at - feet()
	var reach: float = float((FishingRules.rods()[rod] as Dictionary)["cast"])
	if offset.length() > reach + 4.0 or offset.length() < float(cast_cfg["min"]) - 4.0:
		return
	if not stand_ok() or _field(at).x > float(cast_cfg["target_x_max"]):
		return
	var baits: Dictionary = DataRegistry.table("fishing")["baits"] as Dictionary
	var used: String = bait_id if baits.has(bait_id) and _player.inventory.count_item(bait_id) > 0 else ""
	var poses: Dictionary = FishingRules.poses()
	var used_pose: String = pose_id if poses.has(pose_id) else "cork"
	var needs: String = String((poses[used_pose] as Dictionary)["needs"])
	if needs != "" and _player.inventory.count_item(needs) <= 0:
		used_pose = "cork"
	if used != "":
		_player.inventory.remove_item(used, 1)
	rod_id = rod
	target = at
	bobber = at
	cast_pose = used_pose
	_bait_used = used
	species = ""
	_scared = []
	_twitches = []
	_bite_t = -1.0
	_bite_species = ""
	_approaching = false
	netted = false
	_t = 0.0
	_idle_time = 0.0
	_give = 0.0
	_set_state(S.CASTING)
	_broadcast()
	_fx_all("cast", feet(), {"to": at})


var _bait_used: String = ""


func _host_tick(delta: float) -> void:
	if state == S.IDLE:
		return
	if _host_rod() != rod_id or _player.health.current <= 0.0:
		_host_end("", "")
		return
	var max_line: float = float((_cfg()["drift"] as Dictionary)["max_line"])
	if feet().distance_to(bobber) > max_line and state != S.DRILL:
		_host_end("snapped", "")
		return
	match state:
		S.CASTING:
			_t += delta
			var cast_times: Dictionary = _cfg()["cast"] as Dictionary
			if _t >= float(cast_times["windup"]) + float(cast_times["flight"]):
				_host_land_cast()
		S.DRIFTING:
			_host_drift(delta)
		S.NIBBLE:
			_host_nibble(delta)
		S.BITE:
			_t += delta
			if _t >= _window:
				_host_end("late", "")
		S.DRILL:
			_host_drill(delta)
	_sync_t -= delta
	if _sync_t <= 0.0 and state in [S.DRIFTING, S.NIBBLE, S.BITE, S.DRILL]:
		_sync_t = float((_cfg()["drill"] as Dictionary)["sync"]) if state == S.DRILL else float((_cfg()["drift"] as Dictionary)["sync"])
		_rpc_sync.rpc(bobber, tension, dist, heading, phase, tell)


func _host_land_cast() -> void:
	_set_state(S.DRIFTING)
	_fx_all("splash", bobber, {"strength": 0.45})
	_scare_near(bobber, 18.0)
	_broadcast()
	_idle_time = 0.0
	_drift_check = 0.0
	_pick_bite(true)


func _ctx() -> Dictionary:
	var field: Vector2 = _field(bobber)
	var town: Node = get_tree().get_first_node_in_group("town")
	var light: float = (town as TownManager).light_depth(bobber) if town is TownManager else -9999.0
	return {"x": field.x, "y": field.y, "flow": _flow(bobber).length(), "night": TimeManager.night_amount(),
		"light_depth": light, "bait": _bait_used, "pose": cast_pose, "scared": _scared}


func _pick_bite(fresh: bool) -> void:
	var weights: Dictionary = FishingRules.weights(_ctx())
	if not fresh and _bite_species != "" and weights.has(_bite_species):
		return ## still interested
	if _approaching: ## the shadow that was swimming in loses interest
		_approaching = false
		species = ""
		_broadcast()
	if weights.is_empty():
		_bite_species = ""
		_bite_t = -1.0
		return
	_bite_species = FishingRules.pick(weights, _rng)
	_bite_t = FishingRules.bite_delay(FishingRules.total(weights), _rng)


func _host_drift(delta: float) -> void:
	var drift: Dictionary = _cfg()["drift"] as Dictionary
	var field: Vector2 = _field(bobber)
	var speed: float = float(drift["give_speed"]) if _give > 0.5 else float(drift["speed"])
	var flow: Vector2 = _flow(bobber)
	var next: Vector2 = bobber + flow * speed * delta
	if _field(next).x <= float(drift["stop_x"]) and field.x <= float(drift["stop_x"]):
		bobber = next
	_idle_time += delta
	_drift_check += delta
	if _drift_check >= 1.5:
		_drift_check = 0.0
		_pick_bite(false)
	if _bite_species == "":
		if _idle_time >= float((_cfg()["nibble"] as Dictionary)["idle_giveup"]):
			_host_end("", "")
		return
	_bite_t -= delta
	var approach: float = 2.4
	if not _approaching and _bite_t <= approach:
		_approaching = true
		species = _bite_species
		approach_from = _deep_offset(bobber)
		approach_total = maxf(_bite_t, 0.8)
		approach_time = approach_total
		_broadcast()
		_fx_all("approach", bobber, {})
	if _approaching:
		approach_time = maxf(0.0, _bite_t)
	if _bite_t <= 0.0:
		_set_state(S.NIBBLE)
		var taps: Array = (_cfg()["nibble"] as Dictionary)["taps"] as Array
		_taps_left = _rng.randi_range(int(taps[0]), int(taps[1]))
		_tap_t = 0.0
		_broadcast()


func _host_nibble(delta: float) -> void:
	_tap_t -= delta
	if _tap_t > 0.0:
		return
	if _taps_left > 0:
		_taps_left -= 1
		_tap_t = float((_cfg()["nibble"] as Dictionary)["tap_gap"]) * _rng.randf_range(0.8, 1.3)
		_fx_all("tap", bobber, {"side": _rng.randi_range(0, 1)})
		return
	_window = FishingRules.strike_window(species, _rng)
	_t = 0.0
	_set_state(S.BITE)
	_broadcast()
	_fx_all("bite", bobber, {})


func _host_twitch() -> void:
	var tw: Dictionary = _cfg()["twitch"] as Dictionary
	var now: float = Time.get_ticks_msec() / 1000.0
	_twitches.append(now)
	while not _twitches.is_empty() and now - _twitches[0] > float(tw["window"]):
		_twitches.pop_front()
	if state == S.NIBBLE:
		_host_end("early", "")
		return
	var flow: Vector2 = _flow(bobber)
	var shift: Vector2 = -flow.normalized() * float(tw["shift"]) if flow != Vector2.ZERO else Vector2.ZERO
	if _field(bobber + shift).x <= float((_cfg()["drift"] as Dictionary)["stop_x"]):
		bobber += shift
	_fx_all("splash", bobber, {"strength": 0.3})
	if _bite_species != "":
		var spec: Dictionary = FishingRules.species_table()[_bite_species] as Dictionary
		if bool(spec.get("timid", false)) and _twitches.size() >= int(tw["scare_count"]):
			_scared.append(_bite_species)
			_bite_species = ""
			if _approaching:
				_approaching = false
				species = ""
				_broadcast()
				_fx_all("scared", bobber, {})
			_pick_bite(true)
		elif not bool(spec.get("timid", false)):
			_bite_t -= float(tw["lure_bonus"])


func _host_hook() -> void:
	var item: String = String((FishingRules.species_table()[species] as Dictionary)["item"])
	if not _player.inventory.has_room(item):
		_host_end("full", "")
		return
	var rod: Dictionary = FishingRules.rods()[rod_id] as Dictionary
	_find_shore()
	var to: Vector2 = bobber - feet()
	heading = to.normalized() if to.length() > 1.0 else Vector2.RIGHT
	dist = maxf(0.0, to.length() - _shore_gap)
	_drill = FishingRules.new_drill(species, rod, dist, _rng)
	_fled_seen = 1
	_fvel = Vector2.ZERO
	_leaps_done = 0
	tension = 0.25
	phase = "flee"
	tell = false
	_give = 0.0
	_reel = false
	_splash_t = 0.0
	_set_state(S.DRILL)
	_turn_fish()
	_broadcast()
	_fx_all("hook", bobber, {})
	_start_run()


func _host_drill(delta: float) -> void:
	var rod: Dictionary = FishingRules.rods()[rod_id] as Dictionary
	var net: Dictionary = _cfg()["net"] as Dictionary
	var dcfg: Dictionary = _cfg()["drill"] as Dictionary
	var spec: Dictionary = FishingRules.species_table()[species] as Dictionary
	_find_shore()
	_drill["dist"] = _line_dist()
	if netted: ## the friend's net: the fish is drawn in gently and the line cannot break any more
		_reel = true
		_give = 0.0
	var result: String = FishingRules.drill_step(_drill, _give, _reel, delta, rod, _rng, false)
	if netted:
		_drill["tension"] = minf(float(_drill["tension"]), float(net["cap"]))
		_drill["snap"] = 0.0
		if result == "snapped" or result == "escaped":
			result = ""
	tension = float(_drill["tension"])
	phase = String(_drill["phase"])
	tell = bool(_drill["tell"])
	if int(_drill["fled"]) != _fled_seen:
		_fled_seen = int(_drill["fled"])
		_turn_fish()
		_start_run()
	_swim(delta, spec, net)
	dist = _line_dist()
	_drill["dist"] = dist
	if result == "" and dist <= float(dcfg["land_distance"]) and float(_drill["time"]) > 0.8:
		result = "landed"
	elif result == "" and dist > float(rod["line"]) * float(dcfg["escape_factor"]) and not netted:
		result = "escaped"
	_splash_t -= delta
	if _splash_t <= 0.0 and phase == "flee" and _fvel.length() > 8.0:
		_splash_t = float(dcfg["splash_gap"])
		_fx_all("splash", bobber, {"strength": 0.5 + float(_drill.get("surge", 1.0)) * 0.4})
		_scare_n += 1
		if _scare_n % 3 == 0:
			_scare_near(bobber, 34.0)
	var turmoil: Dictionary = _cfg()["turmoil"] as Dictionary
	if float(_drill["time"]) > float(turmoil["after"]):
		var world: Node = get_tree().get_first_node_in_group("world")
		if world != null and world.get("night") != null:
			(world.get("night") as NightDirector).stir(float(spec.get("turmoil", 0.0)) * float(turmoil["lure"]) * delta)
	match result:
		"landed":
			_host_landed()
		"snapped":
			_host_end("snapped", species)
		"escaped":
			_host_end("escaped", species)


## The line that is out: from her feet to the fish, minus the stretch of bank before the water starts.
func _line_dist() -> float:
	return maxf(0.0, bobber.distance_to(feet()) - _shore_gap)


func _water_at(point: Vector2, margin: float) -> bool:
	return _field(point).x <= -margin


## Which way is the bank? (points towards land; zero where the field is unknown)
func _bank_dir(point: Vector2) -> Vector2:
	var gx: float = _field(point + Vector2(6, 0)).x - _field(point - Vector2(6, 0)).x
	var gy: float = _field(point + Vector2(0, 6)).x - _field(point - Vector2(0, 6)).x
	if not is_finite(gx) or not is_finite(gy):
		return Vector2.ZERO
	return Vector2(gx, gy).normalized()


## The water point closest to her feet (where the fish is brought in). Looked up again only when she has moved.
func _find_shore() -> void:
	var here: Vector2 = feet()
	if here.distance_to(_shore_from) < 6.0:
		return
	_shore_from = here
	var best: Vector2 = bobber
	var best_r: float = INF
	for i: int in 24:
		var dir: Vector2 = Vector2.from_angle(TAU * float(i) / 24.0)
		var r: float = 0.0
		while r <= 60.0 and r < best_r:
			if _water_at(here + dir * r, 5.0):
				best_r = r
				best = here + dir * r
				break
			r += 3.0
	_shore = best
	_shore_gap = minf(here.distance_to(best), 30.0)
	_build_pull_map()


func _cell_of(point: Vector2) -> Vector2i:
	return Vector2i(((point - _pull_origin) / PULL_CELL).floor())


## A fish is not pulled through the bank: a flood fill over the water gives every cell its swim distance to the landing
## point, and the crank follows it downhill (round bends and out of pockets).
func _build_pull_map() -> void:
	_pull_origin = _shore - Vector2.ONE * PULL_CELL * float(PULL_N) * 0.5
	var total: int = PULL_N * PULL_N
	var water: PackedByteArray = PackedByteArray()
	water.resize(total)
	for i: int in total:
		var centre: Vector2 = _pull_origin + Vector2(float(i % PULL_N) + 0.5, float(i / PULL_N) + 0.5) * PULL_CELL
		water[i] = 1 if _water_at(centre, 2.0) else 0
	_pull = PackedFloat32Array()
	_pull.resize(total)
	_pull.fill(INF)
	var start: Vector2i = _cell_of(_shore)
	var queue: Array[int] = []
	var first: int = start.y * PULL_N + start.x
	if start.x < 0 or start.y < 0 or start.x >= PULL_N or start.y >= PULL_N:
		return
	_pull[first] = 0.0
	queue.append(first)
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		var ax: int = at % PULL_N
		var ay: int = at / PULL_N
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var nx: int = ax + dx
				var ny: int = ay + dy
				if (dx == 0 and dy == 0) or nx < 0 or ny < 0 or nx >= PULL_N or ny >= PULL_N:
					continue
				var n: int = ny * PULL_N + nx
				if water[n] == 0:
					continue
				var cost: float = _pull[at] + (1.0 if dx == 0 or dy == 0 else 1.414)
				if cost < _pull[n] - 0.001:
					_pull[n] = cost
					queue.append(n)


## The way to the landing point from here (unit vector), following the flood fill; zero when the fish is off the map.
func _pull_dir(point: Vector2) -> Vector2:
	var c: Vector2i = _cell_of(point)
	if _pull.is_empty() or c.x < 1 or c.y < 1 or c.x >= PULL_N - 1 or c.y >= PULL_N - 1:
		return Vector2.ZERO
	var here: float = _pull[c.y * PULL_N + c.x]
	if is_inf(here): ## on a cell the flood did not reach (the edge): head for the best cell next to it
		var best: Vector2 = Vector2.ZERO
		var best_v: float = INF
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var v: float = _pull[(c.y + dy) * PULL_N + c.x + dx]
				if v < best_v:
					best_v = v
					best = Vector2(dx, dy)
		return best.normalized()
	var sum: Vector2 = Vector2.ZERO
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var there: float = _pull[(c.y + dy) * PULL_N + c.x + dx]
			if not is_inf(there) and there < here:
				sum += Vector2(dx, dy).normalized() * (here - there)
	return sum.normalized()


## The first direction near `want` (turning aside a little more each time) that has open water ahead: a fish never swims at a bank.
func _swim_dir(point: Vector2, want: Vector2, margin: float) -> Vector2:
	var base: float = want.angle()
	for offset: float in SWERVES:
		var dir: Vector2 = Vector2.from_angle(base + offset)
		if _water_at(point + dir * 8.0, margin) and _water_at(point + dir * 18.0, margin):
			return dir
	var away: Vector2 = -_bank_dir(point)
	return away if away != Vector2.ZERO else -want


## One tick of the fish's swimming: it speeds up and slows down, turns at a limited rate and keeps to the water.
func _swim(delta: float, spec: Dictionary, net: Dictionary) -> void:
	var wish: Vector2 = Vector2.ZERO
	var speed: float = 0.0
	var margin: float = 8.0
	if netted:
		wish = _pull_dir(bobber)
		if wish == Vector2.ZERO:
			wish = _shore - bobber
		speed = float(net["pull"])
		margin = 4.0
	elif phase == "flee":
		wish = _flee_dir(bobber)
		speed = float(_drill["run"])
	elif _reel:
		wish = _pull_dir(bobber)
		if wish == Vector2.ZERO:
			wish = _shore - bobber
		speed = float(_drill["pull_in"])
		margin = 4.0
	else: ## exhausted: it hangs in the water and drifts a little
		wish = heading.rotated(0.6 * sin(float(_drill["time"]) * 1.7 + _wander))
		speed = float(spec["speed"]) * 0.1
	var aim: Vector2 = wish.normalized() if wish != Vector2.ZERO else heading
	var hauled: bool = netted or (_reel and phase != "flee")
	var dir: Vector2 = aim if hauled else _swim_dir(bobber, aim, margin) ## being hauled in, it follows the flood fill, not the feelers
	var current: float = _fvel.angle() if _fvel.length() > 2.0 else dir.angle()
	var turn: float = clampf(angle_difference(current, dir.angle()), -MAX_TURN * delta, MAX_TURN * delta)
	var now: float = _fvel.length()
	now = move_toward(now, speed, (SPEED_UP if speed > now else SLOW_DOWN) * delta)
	_fvel = Vector2.from_angle(current + turn) * now
	var step: Vector2 = _fvel * delta
	var hold: float = 1.0 ## the fish stays at least this far inside the water
	if _water_at(bobber + step, hold):
		bobber += step
	else: ## it brushes the bank: it slides along it, never onto it
		var bank: Vector2 = _bank_dir(bobber)
		var slid: Vector2 = step - bank * maxf(0.0, step.dot(bank)) if bank != Vector2.ZERO else Vector2.ZERO
		if slid != Vector2.ZERO and _water_at(bobber + slid, hold):
			bobber += slid
		elif bank != Vector2.ZERO and _water_at(bobber - bank * delta * 14.0, hold): ## wedged against it: it backs off into deeper water
			bobber -= bank * delta * 14.0
		_fvel *= 0.6
	if _fvel.length() > 4.0:
		heading = heading.slerp(_fvel.normalized(), minf(1.0, 10.0 * delta)).normalized()


## Where a run goes: along the river (up or down), a little away from her, back to the middle when the bank gets close, in lazy arcs.
func _flee_dir(point: Vector2) -> Vector2:
	var away: Vector2 = (point - feet()).normalized()
	var dir: Vector2 = away * 0.35
	var bank: Vector2 = _bank_dir(point)
	if bank != Vector2.ZERO:
		dir += bank.orthogonal() * _run_sign * 0.8
		var x: float = _field(point).x
		if x > -18.0: ## the bank is near: back to the middle
			dir -= bank * clampf((x + 18.0) / 12.0, 0.0, 1.0) * 1.2
	if dir.length() < 0.01:
		dir = away
	return dir.normalized().rotated(0.45 * sin(float(_drill["t"]) * 2.2 + _wander))


## The shoals and brook fish of RiverFauna scatter from a landing float and from a fight (host).
func _scare_near(at: Vector2, radius: float) -> void:
	var rivers: WorldRivers = _rivers()
	if rivers != null and rivers.fauna != null and is_instance_valid(rivers.fauna.animals):
		rivers.fauna.scare_fish(at, radius)


## Where a fish rises from: of eight directions the one over the deepest water, so shadows come up out of the depth.
func _deep_offset(centre: Vector2) -> Vector2:
	var best: Vector2 = centre + Vector2.from_angle(_rng.randf() * TAU) * 30.0
	var best_depth: float = -1.0
	var start: float = _rng.randf() * TAU
	for i: int in 8:
		var candidate: Vector2 = centre + Vector2.from_angle(start + float(i) * TAU / 8.0) * 32.0
		var field: Vector2 = _field(candidate)
		if field.x <= -4.0 and field.y > best_depth:
			best_depth = field.y
			best = candidate
	return best


## A run begins: a surge of spray, a shake of the camera for strong fish, sometimes a leap out of the water.
func _start_run() -> void:
	var spec: Dictionary = FishingRules.species_table()[species] as Dictionary
	_fx_all("run", bobber, {"strength": float(spec["pull"]) * 1.6})
	## a leap is rare: at most twice a fight, only over deep water
	if bool(spec.get("leap", false)) and _leaps_done < 2 and _field(bobber).x <= -14.0 and _rng.randf() < 0.4:
		_leaps_done += 1
		_fx_all("leap", bobber, {"species": species})
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if state == S.DRILL:
				_fx_all("splash", bobber, {"strength": 1.2}))


## A new run: up or down the river, the way that leads away from her.
func _turn_fish() -> void:
	var bank: Vector2 = _bank_dir(bobber)
	var away: Vector2 = (bobber - feet()).normalized()
	var tangent: Vector2 = bank.orthogonal() if bank != Vector2.ZERO else away.orthogonal()
	var up: float = tangent.dot(away) + _rng.randf_range(-0.35, 0.35)
	_run_sign = 1.0 if up >= 0.0 else -1.0
	_wander = _rng.randf() * TAU


func _host_landed() -> void:
	var spec: Dictionary = FishingRules.species_table()[species] as Dictionary
	var length: int = int(FishingRules.roll_length(species, _rng))
	var prime: bool = netted
	var count: int = int((_cfg()["net"] as Dictionary)["prime_count"]) if prime else 1
	var left: int = _player.inventory.give(String(spec["item"]), count)
	var landed_species: String = species
	_fx_all("landed", bobber, {"species": landed_species})
	if left < count:
		_notify_owner("caught", {"species": landed_species, "length": length, "day": TimeManager.day, "prime": prime})
	_host_end("", "")


func _notify_owner(kind: String, data: Dictionary) -> void:
	var owner_id: int = get_multiplayer_authority()
	if owner_id == multiplayer.get_unique_id():
		_on_owner(kind, data)
	else:
		_rpc_owner.rpc_id(owner_id, kind, data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_owner(kind: String, data: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_on_owner(kind, data)


func _on_owner(kind: String, data: Dictionary) -> void:
	if kind == "caught" and book != null:
		var length: int = int(data["length"])
		var is_record: bool = book.record(String(data["species"]), length, int(data.get("day", 1)))
		caught.emit(String(data["species"]), length, is_record, bool(data.get("prime", false)))


## Ends the line. `reason` shows a word at the float ("early", "late", "escaped", "snapped", "full"); "" = quietly.
func _host_end(reason: String, lost_species: String) -> void:
	if state == S.IDLE:
		return
	var where: Vector2 = bobber
	if reason != "":
		_fx_all("lost", where, {"reason": reason, "species": lost_species})
	_drill = {}
	species = ""
	netted = false
	_approaching = false
	_giving = false
	_give = 0.0
	_reel = false
	_set_state(S.IDLE)
	_broadcast()


# ---------------------------------------------------------------------------------------------- replication

func _set_state(next: int) -> void:
	if next == state:
		return
	state = next
	if next != S.DRIFTING:
		_giving = false ## a held button of the last cast must not swallow the first tap of the next one
		_hold_t = -1.0
	state_changed.emit(state)


func _packet() -> Dictionary:
	return {"s": state, "rod": rod_id, "b": bobber, "t": target, "p": cast_pose, "sp": species,
		"af": approach_from, "at": approach_time, "an": approach_total, "h": heading, "tn": tension, "d": dist, "ph": phase, "nt": netted}


func _broadcast() -> void:
	_rpc_state.rpc(_packet())


@rpc("any_peer", "call_local", "reliable")
func _rpc_state(packet: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and sender != 0:
		return
	rod_id = String(packet["rod"])
	bobber = packet["b"] as Vector2
	target = packet["t"] as Vector2
	cast_pose = String(packet["p"])
	species = String(packet["sp"])
	approach_from = packet["af"] as Vector2
	approach_time = float(packet["at"])
	approach_total = float(packet["an"])
	heading = packet["h"] as Vector2
	tension = float(packet["tn"])
	dist = float(packet["d"])
	phase = String(packet["ph"])
	netted = bool(packet["nt"])
	if multiplayer.is_server():
		return ## the host already holds the truth
	_set_state(int(packet["s"]))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync(b: Vector2, tn: float, d: float, h: Vector2, ph: String, tl: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	bobber = b
	tension = tn
	dist = d
	heading = h
	phase = ph
	tell = tl


func _fx_all(kind: String, pos: Vector2, data: Dictionary) -> void:
	_rpc_fx.rpc(kind, pos, data)


@rpc("any_peer", "call_local", "reliable")
func _rpc_fx(kind: String, pos: Vector2, data: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and sender != 0:
		return
	var ripples: WaterRipples = _player.get_node_or_null("WaterRipples") as WaterRipples
	match kind:
		"splash", "hook":
			if ripples != null:
				ripples.add(pos, float(data.get("strength", 0.8)))
		"tap":
			if ripples != null:
				ripples.add(pos, 0.3)
		"bite":
			if ripples != null:
				ripples.add(pos, 1.1)
		"landed":
			if ripples != null:
				ripples.add(pos, 1.2)
	var shot: String = _oneshot_for(kind, data)
	if shot != "" and rod_active():
		_oneshot = shot
		_oneshot_t = 0.0
		anim_time = 0.0
	if kind == "run" and is_multiplayer_authority():
		_player.add_shake(clampf(float(data.get("strength", 0.0)) - 0.5, 0.0, 1.2))
	match kind:
		"run": _play("splash", pos, 0.7)
		"cast": get_tree().create_timer(float((_cfg()["cast"] as Dictionary)["windup"]) * 0.95).timeout.connect(func() -> void: _play("cast", feet()))
		"splash", "hook": _play("splash", pos, 0.9 + float(data.get("strength", 0.5)) * 0.3)
		"tap": _play("tap", pos)
		"bite": _play("bite", pos)
		"landed": _play("landed", pos)
		"lost":
			if String(data.get("reason", "")) == "snapped":
				_play("snap", pos)
	fx.emit(kind, pos, data)
