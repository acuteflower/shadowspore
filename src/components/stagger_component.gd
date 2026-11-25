class_name StaggerComponent
extends Node2D
## Lost-Ark-style Golden Stagger Check ("Taumel-Prüfung") for dungeon bosses & major elites
## (docs/dungeon_konzept.md Section 3.2).
## Host starts a timed stagger check scaled to 1-4 active players; heavy attacks, late combo
## hits, pickaxe strikes, and spells deal stagger damage. Depleting the bar breaks the cast
## and leaves the boss EXPOSED (`+30%` vulnerability) for `exposed_seconds` (`4.0 s`).

signal check_started(max_stagger: float, duration: float)
signal stagger_changed(current: float, maximum: float, time_left: float, duration: float)
signal stagger_broken(source_peer: int)
signal stagger_failed()
signal exposed_ended()

const GOLD_MAIN: Color = Color("ffd98a")
const GOLD_DEEP: Color = Color("b48a38")
const GOLD_CORE: Color = Color("fff7d6")

@export var exposed_seconds: float = 4.0
@export var vuln_multiplier: float = 1.30
@export var ring_radius: float = 34.0

var active: bool = false
var current_stagger: float = 0.0
var max_stagger: float = 100.0
var time_left: float = 0.0
var duration: float = 3.8
var exposed_left: float = 0.0

var _break_age: float = -1.0
var _time: float = 0.0


func _ready() -> void:
	name = "StaggerComponent"
	material = Unlit.material()
	z_index = 24


## Static helper called by `AttackComponent._hit_scan` & spells (host-only).
static func try_hit_stagger(enemy_node: Node, stagger_power: float, source_peer: int) -> bool:
	if enemy_node == null or stagger_power <= 0.0:
		return false
	var comp: StaggerComponent = enemy_node.get_node_or_null("StaggerComponent") as StaggerComponent
	if comp == null:
		return false
	return comp.apply_stagger(stagger_power, source_peer)


## Static helper read by `HealthComponent.take_damage` (host-only).
static func vulnerability_of(enemy_node: Node) -> float:
	if enemy_node == null:
		return 1.0
	var comp: StaggerComponent = enemy_node.get_node_or_null("StaggerComponent") as StaggerComponent
	if comp != null and comp.is_exposed():
		return comp.vuln_multiplier
	return 1.0


func is_exposed() -> bool:
	return exposed_left > 0.0


func fraction() -> float:
	return clampf(current_stagger / maxf(max_stagger, 0.001), 0.0, 1.0)


func time_fraction() -> float:
	return clampf(time_left / maxf(duration, 0.001), 0.0, 1.0)


## Host-only: opens a timed Stagger Check scaled by `player_count`.
func begin_check(base_stagger: float, check_duration: float = 3.8, player_count: int = 1) -> void:
	if not multiplayer.is_server():
		return
	var scaled: float = maxf(base_stagger * DungeonRules.stagger_scale(player_count), 10.0)
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_begin.rpc(scaled, check_duration)
	else:
		_rpc_begin(scaled, check_duration)


## Host-only: cancels an active stagger check without triggering fail/break (e.g. boss died/reset).
func cancel_check() -> void:
	if not multiplayer.is_server() or not active:
		return
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_end.rpc(false, 0, false)
	else:
		_rpc_end(false, 0, false)


## Host-only: deals stagger damage to the active bar; returns true if this hit broke the bar.
func apply_stagger(amount: float, source_peer: int) -> bool:
	if not multiplayer.is_server() or not active or amount <= 0.0:
		return false
	current_stagger = maxf(current_stagger - amount, 0.0)
	if current_stagger <= 0.0:
		if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
			_rpc_end.rpc(true, source_peer, true)
		else:
			_rpc_end(true, source_peer, true)
		if is_inside_tree():
			get_tree().call_group("dungeons", "note_player_stagger", source_peer)
		return true
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_progress.rpc(current_stagger, time_left)
	else:
		_rpc_progress(current_stagger, time_left)
	return false


func _process(delta: float) -> void:
	_time += delta
	var redraw: bool = false
	if active:
		time_left = maxf(time_left - delta, 0.0)
		stagger_changed.emit(current_stagger, max_stagger, time_left, duration)
		redraw = true
		if multiplayer.is_server() and time_left <= 0.0:
			if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
				_rpc_end.rpc(false, 0, true)
			else:
				_rpc_end(false, 0, true)
	if exposed_left > 0.0:
		exposed_left = maxf(exposed_left - delta, 0.0)
		redraw = true
		if exposed_left <= 0.0:
			exposed_ended.emit()
	if _break_age >= 0.0:
		_break_age += delta
		redraw = true
		if _break_age >= 0.75:
			_break_age = -1.0
	if redraw:
		queue_redraw()


@rpc("authority", "call_local", "reliable")
func _rpc_begin(scaled_max: float, check_duration: float) -> void:
	active = true
	max_stagger = scaled_max
	current_stagger = scaled_max
	duration = maxf(check_duration, 0.1)
	time_left = duration
	check_started.emit(max_stagger, duration)
	stagger_changed.emit(current_stagger, max_stagger, time_left, duration)
	queue_redraw()


@rpc("authority", "call_local", "reliable")
func _rpc_progress(cur: float, t_left: float) -> void:
	current_stagger = cur
	time_left = t_left
	stagger_changed.emit(current_stagger, max_stagger, time_left, duration)
	queue_redraw()


@rpc("authority", "call_local", "reliable")
func _rpc_end(broken: bool, source_peer: int, emit_outcome: bool) -> void:
	active = false
	time_left = 0.0
	if broken:
		current_stagger = 0.0
		exposed_left = exposed_seconds
		_break_age = 0.0
		_play_break_sound()
		for p: Player in Player.all:
			if p.is_multiplayer_authority():
				p.add_shake(6.5)
		if emit_outcome:
			stagger_broken.emit(source_peer)
	elif emit_outcome:
		stagger_failed.emit()
	stagger_changed.emit(current_stagger, max_stagger, 0.0, duration)
	queue_redraw()


func _play_break_sound() -> void:
	var path: String = "res://assets/audio/dungeon/stagger_break.wav"
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path) as AudioStream
		if stream != null and is_inside_tree():
			var asp: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			asp.stream = stream
			asp.volume_db = 1.0
			asp.max_distance = 560.0
			add_child(asp)
			asp.finished.connect(asp.queue_free)
			asp.play()
			return
	if is_inside_tree():
		Sfx.ui(self, "skills/learn", 0.0)


func _draw() -> void:
	if active:
		var pulse: float = 0.7 + 0.3 * sin(_time * 18.0)
		var tf: float = time_fraction()
		var r_outer: float = ring_radius
		var r_inner: float = lerpf(8.0, ring_radius, tf)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.58))
		draw_arc(Vector2.ZERO, r_outer, 0.0, TAU, 36, Color(GOLD_DEEP, 0.65 * pulse), 2.0)
		draw_arc(Vector2.ZERO, r_inner, 0.0, TAU, 32, Color(GOLD_MAIN, 0.9 * pulse), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _break_age >= 0.0:
		var k: float = clampf(_break_age / 0.75, 0.0, 1.0)
		var a: float = pow(1.0 - k, 1.3)
		var rr: float = lerpf(12.0, 74.0, pow(k, 0.5))
		draw_arc(Vector2(0.0, -14.0), rr, 0.0, TAU, 32, Color(GOLD_MAIN, a), 3.0 * (1.0 - k * 0.5))
		var lp: Vector2 = Vector2(-38.0, -34.0 - k * 18.0).round()
		PixelText.draw(self, "TAUMELBRUCH!", Vector2i(int(lp.x), int(lp.y)), Color(GOLD_CORE, a), Color(Color("040208"), a))
