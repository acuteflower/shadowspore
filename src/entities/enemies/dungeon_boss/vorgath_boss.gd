class_name VorgathBoss
extends CharacterBody2D
## Endboss of Dungeon #1: Vorgath, Brut der Mole (docs/dungeon_konzept.md Section 6.3).
## Beginner-friendly Lost-Ark showcase with x5 BossBar layers:
## - Kettenfeger (135 deg frontal anchor sweep)
## - Brackwasser-Spucke (spore blobs -> 6s puddles unless Hafenlaterne is broken!)
## - Rammflut (0.50 s ice-blue Counter flash + first-time hint; hitting bollard stuns 1.2 s)
## - 60% Sog des Tiefendocks (gentle center pull + 3.8 s golden Stagger Check -> EXPOSED)
## - 30% Springflut (2.2 s telegraph with safe shadow cones behind 3 Steinsetzer bollards; washes away puddles!)
## - Optional rear weakpoint Hafenlaterne (160 HP -> breaks for bonus_part_broken + disables puddles)

signal boss_defeated()
signal lantern_broken(source_peer: int)
signal spring_tide_triggered()

const BASE_HP: float = 900.0
const BASE_STAGGER: float = 110.0
const BASE_LANTERN_HP: float = 160.0
const MOVE_SPEED: float = 64.0
const CHARGE_SPEED: float = 245.0
const BOLLARD_SAFE_WIDTH: float = 28.0
const BOLLARD_SAFE_DEPTH: float = 76.0

enum State { IDLE, CHASE, SWEEP_WINDUP, SWEEP_STRIKE, SPIT, RAM_COUNTER, RAM_CHARGE, STAGGER_CAST, TIDE_TELEGRAPH, TIDE_WAVE, STUNNED, EXPOSED, DEAD }

@export var arena_center: Vector2 = Vector2.ZERO
@export var arena_radius: Vector2 = Vector2(158.0, 112.0)

var bollard_positions: Array[Vector2] = []
var dungeon_scene: DungeonScene = null
var player_count_scale: int = 1

var health: HealthComponent = null
var hurtbox: HurtboxComponent = null
var counter: CounterComponent = null
var stagger: StaggerComponent = null
var rig: VorgathRig = null

var state: State = State.IDLE
var state_t: float = 0.0
var facing: Vector2 = Vector2.DOWN
var lantern_hp: float = BASE_LANTERN_HP
var lantern_intact: bool = true

var _active: bool = false
var _attack_cd: float = 1.4
var _did_stagger_60: bool = false
var _did_tide_30: bool = false
var _next_tide_cd: float = 24.0
var _did_counter_hint: bool = false
var _sweep_dir: Vector2 = Vector2.DOWN
var _ram_dir: Vector2 = Vector2.DOWN
var _ram_hit_peers: Dictionary = {}
var _puddles: Array[Dictionary] = [] ## {pos: Vector2, life: float, radius: float, tick: float}
var _blobs: Array[Dictionary] = [] ## {pos: Vector2, start: Vector2, target: Vector2, t: float, dur: float}
var _wave_y: float = 0.0
var _wave_hit_peers: Dictionary = {}
var _fx_layer: _VorgathArenaFx = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


class _VorgathArenaFx extends Node2D:
	## Draws unlit floor telegraphs (Kettenfeger sector, Rammflut lane, Springflut safe cones & wave, puddles, blobs).
	var boss: VorgathBoss = null

	func _ready() -> void:
		material = Unlit.material()
		z_index = -1

	func _draw() -> void:
		if boss == null:
			return
		boss._draw_arena_fx(self)


func _ready() -> void:
	name = "VorgathBoss"
	add_to_group("enemies")
	add_to_group("predators")
	add_to_group("dungeon_boss")
	y_sort_enabled = true
	collision_layer = 4 ## enemy layer (3)
	collision_mask = 1 ## world walls
	_rng.seed = 4729

	var col: CollisionShape2D = CollisionShape2D.new()
	var circ: CircleShape2D = CircleShape2D.new()
	circ.radius = 20.0
	col.shape = circ
	col.position = Vector2(0.0, -6.0)
	add_child(col)

	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = BASE_HP
	health.current = BASE_HP
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	hurtbox = HurtboxComponent.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.health = health
	hurtbox.collision_layer = 16 ## layer 5 enemy hurtbox
	hurtbox.collision_mask = 0
	var hcs: CollisionShape2D = CollisionShape2D.new()
	var hcirc: CircleShape2D = CircleShape2D.new()
	hcirc.radius = 28.0
	hcs.shape = hcirc
	hcs.position = Vector2(0.0, -14.0)
	hurtbox.add_child(hcs)
	add_child(hurtbox)

	counter = CounterComponent.new()
	counter.cooldown_seconds = 14.0
	counter.stun_seconds = 2.8
	counter.vuln_multiplier = 1.25
	counter.visual_offset = Vector2(0.0, -24.0)
	add_child(counter)
	counter.countered.connect(_on_countered)
	counter.stun_ended.connect(_on_stun_ended)

	stagger = StaggerComponent.new()
	stagger.exposed_seconds = 4.0
	stagger.vuln_multiplier = 1.30
	stagger.ring_radius = 44.0
	add_child(stagger)
	stagger.stagger_broken.connect(_on_stagger_broken)
	stagger.stagger_failed.connect(_on_stagger_failed)
	stagger.exposed_ended.connect(_on_exposed_ended)

	rig = VorgathRig.new()
	add_child(rig)

	_fx_layer = _VorgathArenaFx.new()
	_fx_layer.boss = self
	add_child(_fx_layer)


func setup_encounter(center: Vector2, bollards: Array[Vector2], scene_ref: DungeonScene, party_size: int) -> void:
	arena_center = center
	bollard_positions = bollards.duplicate()
	dungeon_scene = scene_ref
	player_count_scale = clampi(party_size, 1, 4)
	var hp_scaled: float = roundf(BASE_HP * DungeonRules.hp_scale(player_count_scale))
	health.max_health = hp_scaled
	health.current = hp_scaled
	lantern_hp = BASE_LANTERN_HP * lerpf(1.0, 1.45, float(player_count_scale - 1) / 3.0)
	lantern_intact = true
	if rig != null:
		rig.lantern_intact = true


func activate_fight() -> void:
	if _active or state == State.DEAD:
		return
	_active = true
	state = State.CHASE
	state_t = 0.0
	_attack_cd = 1.5
	if is_inside_tree():
		get_tree().call_group("boss_bar", "track", "VORGATH, BRUT DER MOLE", health, 5, stagger)


func reset_encounter() -> void:
	_active = false
	state = State.IDLE
	state_t = 0.0
	_did_stagger_60 = false
	_did_tide_30 = false
	_next_tide_cd = 24.0
	_puddles.clear()
	_blobs.clear()
	lantern_intact = true
	lantern_hp = BASE_LANTERN_HP * lerpf(1.0, 1.45, float(player_count_scale - 1) / 3.0)
	if rig != null:
		rig.lantern_intact = true
		rig.anim_state = "idle"
	if counter != null:
		counter.close_window()
		counter.stun_left = 0.0
		counter.cooldown_left = 0.0
	if stagger != null:
		stagger.cancel_check()
		stagger.exposed_left = 0.0
	if health != null:
		health.current = health.max_health
		health.changed.emit(health.current, health.max_health)
	global_position = arena_center + Vector2(0.0, -48.0)


func _physics_process(delta: float) -> void:
	_update_blobs_and_puddles(delta)
	if _fx_layer != null:
		_fx_layer.queue_redraw()
	if not _active or state == State.DEAD:
		_sync_rig()
		return
	if not multiplayer.is_server():
		_sync_rig()
		return

	state_t += delta
	var target: Player = _nearest_alive_player()
	if target == null:
		velocity = Vector2.ZERO
		_sync_rig()
		return

	## Phase threshold checks when in CHASE
	var hp_ratio: float = health.current / maxf(health.max_health, 1.0)
	if state == State.CHASE:
		if not _did_stagger_60 and hp_ratio <= 0.60:
			_did_stagger_60 = true
			_enter_state(State.STAGGER_CAST)
			return
		if hp_ratio <= 0.30:
			if not _did_tide_30:
				_did_tide_30 = true
				_next_tide_cd = 24.0
				_enter_state(State.TIDE_TELEGRAPH)
				return
			_next_tide_cd -= delta
			if _next_tide_cd <= 0.0:
				_next_tide_cd = 24.0
				_enter_state(State.TIDE_TELEGRAPH)
				return

	match state:
		State.CHASE:
			var to_p: Vector2 = target.global_position - global_position
			var dist: float = to_p.length()
			if dist > 4.0:
				facing = to_p / dist
			velocity = facing * MOVE_SPEED if dist > 48.0 else Vector2.ZERO
			move_and_slide()
			_clamp_in_arena()
			_attack_cd -= delta
			if _attack_cd <= 0.0:
				_choose_next_attack(dist)
		State.SWEEP_WINDUP:
			velocity = Vector2.ZERO
			if state_t >= 0.72:
				_execute_sweep_hit()
				_enter_state(State.SWEEP_STRIKE)
		State.SWEEP_STRIKE:
			velocity = Vector2.ZERO
			if state_t >= 0.42:
				_attack_cd = 1.75
				_enter_state(State.CHASE)
		State.SPIT:
			velocity = Vector2.ZERO
			if state_t >= 0.55:
				_fire_spore_blobs()
				_attack_cd = 2.0
				_enter_state(State.CHASE)
		State.RAM_COUNTER:
			velocity = Vector2.ZERO
			## Counter window lasts 0.50 s — if player hits frontally, _on_countered fires!
			if state_t >= 0.52:
				counter.close_window()
				_ram_hit_peers.clear()
				_enter_state(State.RAM_CHARGE)
		State.RAM_CHARGE:
			velocity = _ram_dir * CHARGE_SPEED
			move_and_slide()
			_check_ram_hits()
			## Check collision with any indestructible Steinsetzer bollard -> 1.2 s stun!
			for bp: Vector2 in bollard_positions:
				if global_position.distance_to(bp) <= 30.0:
					_play_boss_sfx("vorgath_slam", 1.0)
					_announce("VORGATH PRALLT AN DEN POLTER!")
					velocity = Vector2.ZERO
					_enter_state(State.STUNNED)
					state_t = -1.2 ## 1.2s self-stun
					return
			if state_t >= 0.62 or _at_arena_wall():
				_clamp_in_arena()
				velocity = Vector2.ZERO
				_attack_cd = 2.1
				_enter_state(State.CHASE)
		State.STAGGER_CAST:
			## Drift toward center and gently pull players inward during golden Stagger Check
			var to_c: Vector2 = arena_center - global_position
			velocity = to_c.normalized() * 70.0 if to_c.length() > 14.0 else Vector2.ZERO
			move_and_slide()
			for p: Player in _alive_dungeon_players():
				var pull: Vector2 = global_position - p.global_position
				if pull.length() > 36.0 and pull.length() < 260.0:
					p.global_position += pull.normalized() * 44.0 * delta
		State.TIDE_TELEGRAPH:
			## Retreats near north gate while wave builds (2.2 s telegraph with safe shadow cones behind bollards!)
			var north_spot: Vector2 = arena_center + Vector2(0.0, -arena_radius.y + 26.0)
			var to_n: Vector2 = north_spot - global_position
			velocity = to_n.normalized() * 90.0 if to_n.length() > 12.0 else Vector2.ZERO
			move_and_slide()
			if state_t >= 2.2:
				_wave_y = arena_center.y - arena_radius.y - 16.0
				_wave_hit_peers.clear()
				_play_boss_sfx("spring_tide", 2.0)
				spring_tide_triggered.emit()
				_enter_state(State.TIDE_WAVE)
		State.TIDE_WAVE:
			velocity = Vector2.ZERO
			_wave_y += 280.0 * delta
			## Tidal wave washes away all Brackwasser puddles it passes!
			for i: int in range(_puddles.size() - 1, -1, -1):
				var pd: Dictionary = _puddles[i]
				if (pd["pos"] as Vector2).y <= _wave_y:
					_puddles.remove_at(i)
			_check_wave_hits()
			if _wave_y >= arena_center.y + arena_radius.y + 32.0:
				_attack_cd = 2.4
				_enter_state(State.CHASE)
		State.STUNNED:
			velocity = Vector2.ZERO
			if not counter.is_stunned() and state_t >= 0.0:
				_attack_cd = 1.4
				_enter_state(State.CHASE)
		State.EXPOSED:
			velocity = Vector2.ZERO
			if not stagger.is_exposed():
				_attack_cd = 1.5
				_enter_state(State.CHASE)

	_sync_rig()


func _enter_state(next: State) -> void:
	state = next
	state_t = 0.0
	if next == State.RAM_COUNTER:
		var target: Player = _nearest_alive_player()
		_ram_dir = (target.global_position - global_position).normalized() if target != null else Vector2.DOWN
		facing = _ram_dir
		counter.open_window(_ram_dir, 0.50)
		if not _did_counter_hint:
			_did_counter_hint = true
			_announce("BLAUER BLITZ! SCHLAG VORGATH VON VORN FÜR EINEN KLANGKONTER!")
	elif next == State.STAGGER_CAST:
		_announce("TAUMEL-PRÜFUNG! SCHWERE SCHLÄGE BRECHEN DEN SOG!")
		stagger.begin_check(BASE_STAGGER, 3.8, player_count_scale)
	elif next == State.TIDE_TELEGRAPH:
		_announce("SPRINGFLUT! SUCH DECKUNG HINTER DEN STEINSETZER-POLTERN!")
	_sync_rig()


func _choose_next_attack(dist: float) -> void:
	if counter.can_open_window() and dist >= 68.0 and _rng.randf() < 0.42:
		_enter_state(State.RAM_COUNTER)
		return
	if dist <= 78.0:
		_sweep_dir = facing
		_enter_state(State.SWEEP_WINDUP)
	else:
		_enter_state(State.SPIT)


func _execute_sweep_hit() -> void:
	_play_boss_sfx("vorgath_slam", 0.5)
	var dmg: float = 16.0 * DungeonRules.damage_scale(player_count_scale)
	for p: Player in _alive_dungeon_players():
		var rel: Vector2 = p.global_position - global_position
		if rel.length() <= 76.0 and rel.normalized().dot(_sweep_dir) >= 0.36: ## ~135 deg cone
			p.health.take_damage(dmg, global_position, 180.0, 0)


func _fire_spore_blobs() -> void:
	var targets: Array[Player] = _alive_dungeon_players()
	if targets.is_empty():
		return
	var count: int = mini(targets.size() + 1, 3)
	for i: int in count:
		var p: Player = targets[i % targets.size()]
		var jitter: Vector2 = Vector2(_rng.randf_range(-24.0, 24.0), _rng.randf_range(-18.0, 18.0)) if i > 0 else Vector2.ZERO
		_blobs.append({
			"start": global_position + Vector2(0.0, -24.0),
			"pos": global_position + Vector2(0.0, -24.0),
			"target": p.global_position + jitter,
			"t": 0.0,
			"dur": 0.85,
		})


func _check_ram_hits() -> void:
	var dmg: float = 20.0 * DungeonRules.damage_scale(player_count_scale)
	for p: Player in _alive_dungeon_players():
		var pid: int = p.get_multiplayer_authority()
		if _ram_hit_peers.has(pid):
			continue
		if p.global_position.distance_to(global_position) <= 34.0:
			_ram_hit_peers[pid] = true
			p.health.take_damage(dmg, global_position, 220.0, 0)


## True if `pt` stands sheltered in the southern lee behind any of the 3 indestructible Steinsetzer bollards.
func is_sheltered_by_bollard(pt: Vector2) -> bool:
	for bp: Vector2 in bollard_positions:
		var dy: float = pt.y - bp.y
		var dx: float = absf(pt.x - bp.x)
		if dy >= -4.0 and dy <= BOLLARD_SAFE_DEPTH and dx <= BOLLARD_SAFE_WIDTH:
			return true
	return false


func _check_wave_hits() -> void:
	var dmg: float = 28.0 * DungeonRules.damage_scale(player_count_scale)
	for p: Player in _alive_dungeon_players():
		var pid: int = p.get_multiplayer_authority()
		if _wave_hit_peers.has(pid):
			continue
		if absf(p.global_position.y - _wave_y) <= 20.0:
			_wave_hit_peers[pid] = true
			if not is_sheltered_by_bollard(p.global_position):
				p.health.take_damage(dmg, Vector2(p.global_position.x, _wave_y - 30.0), 240.0, 0)


func _update_blobs_and_puddles(delta: float) -> void:
	var blob_dmg: float = 12.0 * DungeonRules.damage_scale(player_count_scale)
	for i: int in range(_blobs.size() - 1, -1, -1):
		var b: Dictionary = _blobs[i]
		b["t"] = float(b["t"]) + delta
		var u: float = clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
		var st: Vector2 = b["start"] as Vector2
		var tg: Vector2 = b["target"] as Vector2
		b["pos"] = st.lerp(tg, u) + Vector2(0.0, -sin(u * PI) * 44.0)
		if u >= 1.0:
			if multiplayer.is_server():
				for p: Player in _alive_dungeon_players():
					if p.global_position.distance_to(tg) <= 24.0:
						p.health.take_damage(blob_dmg, tg, 80.0, 0)
				if lantern_intact:
					_puddles.append({"pos": tg, "life": 6.0, "radius": 24.0, "tick": 0.4})
			_blobs.remove_at(i)

	for i: int in range(_puddles.size() - 1, -1, -1):
		var pd: Dictionary = _puddles[i]
		pd["life"] = float(pd["life"]) - delta
		pd["tick"] = float(pd["tick"]) - delta
		if multiplayer.is_server() and float(pd["tick"]) <= 0.0:
			pd["tick"] = 0.75
			for p: Player in _alive_dungeon_players():
				if p.global_position.distance_to(pd["pos"] as Vector2) <= float(pd["radius"]):
					p.health.take_damage(4.0, pd["pos"] as Vector2, 0.0, 0)
		if float(pd["life"]) <= 0.0:
			_puddles.remove_at(i)


## Optional rear weakpoint check: hits from behind Vorgath (or heavy strikes) crack his Hafenlaterne!
func _on_damaged(amount: float, from: Vector2, source: int) -> void:
	if rig != null:
		rig.hit_flash = 1.0
	if not multiplayer.is_server() or not lantern_intact or state == State.DEAD:
		return
	var from_dir: Vector2 = (from - global_position).normalized() if from.distance_squared_to(global_position) > 1.0 else -facing
	var is_back_hit: bool = from_dir.dot(facing) < -0.15
	var lantern_dmg: float = amount * (1.0 if is_back_hit else 0.25)
	damage_lantern(lantern_dmg, source)


## Public helper (also callable directly by tests): damages the Hafenlaterne weakpoint.
func damage_lantern(amount: float, source_peer: int = 1) -> bool:
	if not lantern_intact or amount <= 0.0:
		return false
	lantern_hp = maxf(lantern_hp - amount, 0.0)
	if lantern_hp <= 0.0:
		lantern_intact = false
		if rig != null:
			rig.lantern_intact = false
		if dungeon_scene != null:
			dungeon_scene.bonus_part_broken = true
		_announce("HAFENLATERNE ZERBROCHEN! KEINE BRACKWASSER-PFÜTZEN MEHR (+1 BONUS)!")
		_play_boss_sfx("stagger_break", -1.0)
		lantern_broken.emit(source_peer)
		return true
	return false


func _on_countered(_source_peer: int) -> void:
	velocity = Vector2.ZERO
	_enter_state(State.STUNNED)


func _on_stun_ended() -> void:
	if state == State.STUNNED:
		_attack_cd = 1.3
		_enter_state(State.CHASE)


func _on_stagger_broken(_source_peer: int) -> void:
	velocity = Vector2.ZERO
	_enter_state(State.EXPOSED)


func _on_stagger_failed() -> void:
	if multiplayer.is_server():
		_play_boss_sfx("vorgath_slam", 1.5)
		var dmg: float = 20.0 * DungeonRules.damage_scale(player_count_scale)
		for p: Player in _alive_dungeon_players():
			if p.global_position.distance_to(global_position) <= 185.0:
				p.health.take_damage(dmg, global_position, 220.0, 0)
	_attack_cd = 1.8
	_enter_state(State.CHASE)


func _on_exposed_ended() -> void:
	if state == State.EXPOSED:
		_attack_cd = 1.4
		_enter_state(State.CHASE)


func _on_died() -> void:
	state = State.DEAD
	state_t = 0.0
	_active = false
	velocity = Vector2.ZERO
	if counter != null:
		counter.close_window()
	if stagger != null:
		stagger.cancel_check()
	_puddles.clear()
	_blobs.clear()
	_play_boss_sfx("victory_fanfare", 0.5)
	_sync_rig()
	boss_defeated.emit()


func _clamp_in_arena() -> void:
	global_position.x = clampf(global_position.x, arena_center.x - arena_radius.x + 22.0, arena_center.x + arena_radius.x - 22.0)
	global_position.y = clampf(global_position.y, arena_center.y - arena_radius.y + 22.0, arena_center.y + arena_radius.y - 22.0)


func _at_arena_wall() -> bool:
	return absf(global_position.x - arena_center.x) >= arena_radius.x - 24.0 or absf(global_position.y - arena_center.y) >= arena_radius.y - 24.0


func _alive_dungeon_players() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in Player.all:
		if is_instance_valid(p) and p.health != null and p.health.current > 0.0:
			if p.global_position.distance_to(arena_center) <= 460.0:
				out.append(p)
	return out


func _nearest_alive_player() -> Player:
	var best: Player = null
	var best_d: float = INF
	for p: Player in _alive_dungeon_players():
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _sync_rig() -> void:
	if rig == null:
		return
	rig.facing = facing
	rig.counter_open = counter != null and counter.window_open
	rig.stagger_active = stagger != null and stagger.active
	rig.exposed = stagger != null and stagger.is_exposed()
	var mapped: String = "idle"
	match state:
		State.CHASE:
			mapped = "walk" if velocity.length_squared() > 4.0 else "idle"
		State.SWEEP_WINDUP:
			mapped = "sweep_windup"
		State.SWEEP_STRIKE:
			mapped = "sweep"
		State.SPIT:
			mapped = "spit"
		State.RAM_COUNTER:
			mapped = "counter"
		State.RAM_CHARGE:
			mapped = "charge"
		State.STAGGER_CAST:
			mapped = "stagger"
		State.TIDE_TELEGRAPH, State.TIDE_WAVE:
			mapped = "tide"
		State.STUNNED, State.EXPOSED:
			mapped = "stunned"
		State.DEAD:
			mapped = "dead"
	if rig.anim_state != mapped:
		rig.anim_state = mapped
		rig.anim_t = 0.0


func _announce(msg: String) -> void:
	if not is_inside_tree():
		return
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.speak("VORGATH", msg, 3.2)


func _play_boss_sfx(id: String, db: float) -> void:
	var path: String = "res://assets/audio/dungeon/%s.wav" % id
	if ResourceLoader.exists(path) and is_inside_tree():
		var stream: AudioStream = load(path) as AudioStream
		if stream != null:
			var asp: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			asp.stream = stream
			asp.volume_db = db
			asp.max_distance = 620.0
			add_child(asp)
			asp.finished.connect(asp.queue_free)
			asp.play()


func _draw_arena_fx(canvas: CanvasItem) -> void:
	## 1. Brackwasser puddles
	for pd: Dictionary in _puddles:
		var lp: Vector2 = to_local(pd["pos"] as Vector2)
		var r: float = float(pd["radius"])
		var a: float = clampf(float(pd["life"]) / 1.5, 0.0, 1.0)
		canvas.draw_set_transform(lp, 0.0, Vector2(1.0, 0.62))
		canvas.draw_circle(Vector2.ZERO, r, Color(Color("3c1c5a"), 0.58 * a))
		canvas.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(Color("9d5cff"), 0.72 * a), 1.5)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## 2. Airborne spore blobs
	for b: Dictionary in _blobs:
		var tg_l: Vector2 = to_local(b["target"] as Vector2)
		var bp_l: Vector2 = to_local(b["pos"] as Vector2)
		canvas.draw_arc(tg_l, 18.0, 0.0, TAU, 16, Color(Color("c678ff"), 0.55), 1.5)
		canvas.draw_circle(bp_l, 6.0, Color("5a2682"))
		canvas.draw_circle(bp_l + Vector2(-1, -1), 3.0, Color("ff7ae8"))

	## 3. Kettenfeger 135-deg frontal sweep telegraph
	if state == State.SWEEP_WINDUP:
		var fill: float = clampf(state_t / 0.72, 0.0, 1.0)
		var base_a: float = _sweep_dir.angle()
		var half: float = deg_to_rad(67.5)
		var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
		for k: int in 13:
			var ang: float = base_a - half + (2.0 * half * float(k) / 12.0)
			pts.append(Vector2.from_angle(ang) * 76.0)
		canvas.draw_colored_polygon(pts, Color(Color("ffae3d"), 0.16 + 0.24 * fill))
		canvas.draw_arc(Vector2.ZERO, 76.0, base_a - half, base_a + half, 18, Color(Color("ffd98a"), 0.85), 2.0)

	## 4. Rammflut charge lane telegraph (ice-blue!)
	if state == State.RAM_COUNTER:
		var end_l: Vector2 = _ram_dir * 160.0
		var perp: Vector2 = Vector2(-_ram_dir.y, _ram_dir.x) * 24.0
		var lane: PackedVector2Array = PackedVector2Array([perp, end_l + perp, end_l - perp, -perp])
		canvas.draw_colored_polygon(lane, Color(Color("4df2ff"), 0.18))
		canvas.draw_line(Vector2.ZERO, end_l, Color(Color("4df2ff"), 0.75), 2.0)

	## 5. Springflut telegraph: north-to-south danger arrows + safe shadow cones behind bollards!
	if state == State.TIDE_TELEGRAPH or state == State.TIDE_WAVE:
		var ac_l: Vector2 = to_local(arena_center)
		var arena_r: Rect2 = Rect2(ac_l - arena_radius, arena_radius * 2.0)
		if state == State.TIDE_TELEGRAPH:
			var p_t: float = clampf(state_t / 2.2, 0.0, 1.0)
			canvas.draw_rect(arena_r, Color(Color("2498a8"), 0.12 + 0.16 * p_t))
		## Safe shadow zones behind each Steinsetzer bollard (crisp emerald-turquoise shield!)
		for bp: Vector2 in bollard_positions:
			var b_l: Vector2 = to_local(bp)
			var safe_r: Rect2 = Rect2(b_l.x - BOLLARD_SAFE_WIDTH, b_l.y, BOLLARD_SAFE_WIDTH * 2.0, BOLLARD_SAFE_DEPTH)
			canvas.draw_rect(safe_r, Color(Color("4df2a6"), 0.26))
			canvas.draw_rect(safe_r, Color(Color("a0ffd6"), 0.85), false, 1.5)
		## Sweeping ocean wave wall during TIDE_WAVE
		if state == State.TIDE_WAVE:
			var wy_l: float = to_local(Vector2(arena_center.x, _wave_y)).y
			canvas.draw_rect(Rect2(arena_r.position.x, wy_l - 14.0, arena_r.size.x, 22.0), Color(Color("228ea6"), 0.78))
			canvas.draw_rect(Rect2(arena_r.position.x, wy_l + 4.0, arena_r.size.x, 5.0), Color(Color("c4fff8"), 0.92))
