class_name CounterComponent
extends Node2D
## Lost-Ark-style "Klangkonter" (Blue Flash Counter) for dungeon bosses and large elites
## (docs/dungeon_konzept.md Section 3.1).
## Host opens a brief counter window (`0.45-0.50 s`) before a charge/lunge; any frontal hit
## inside the 110-degree cone interrupts the attack, triggers ice-blue shockring + hit-stop,
## stuns the enemy for `stun_seconds` (`2.8 s`), and increases damage taken by +25%.

signal window_changed(open: bool)
signal countered(source_peer: int)
signal stun_ended()

const COUNTER_COLOR: Color = Color("4df2ff")
const COUNTER_CORE: Color = Color("e8ffff")
const FRONT_CONE_COS: float = 0.573576 ## cos(55 deg) => 110 degree frontal cone

@export var cooldown_seconds: float = 18.0
@export var stun_seconds: float = 2.8
@export var vuln_multiplier: float = 1.25
@export var visual_offset: Vector2 = Vector2(0.0, -18.0)

var window_open: bool = false
var window_left: float = 0.0
var window_total: float = 0.45
var facing_dir: Vector2 = Vector2.DOWN
var stun_left: float = 0.0
var cooldown_left: float = 0.0

var _ring_age: float = -1.0
var _ring_origin: Vector2 = Vector2.ZERO
var _time: float = 0.0


func _ready() -> void:
	name = "CounterComponent"
	material = Unlit.material()
	z_index = 25


## Static helper called by `AttackComponent._hit_scan` (host-only).
static func try_hit_counter(enemy_node: Node, attacker_pos: Vector2, source_peer: int) -> bool:
	if enemy_node == null:
		return false
	var comp: CounterComponent = enemy_node.get_node_or_null("CounterComponent") as CounterComponent
	if comp == null:
		return false
	return comp.try_counter(attacker_pos, source_peer)


## Static helper read by `HealthComponent.take_damage` (host-only).
static func vulnerability_of(enemy_node: Node) -> float:
	if enemy_node == null:
		return 1.0
	var comp: CounterComponent = enemy_node.get_node_or_null("CounterComponent") as CounterComponent
	if comp != null and comp.is_stunned():
		return comp.vuln_multiplier
	return 1.0


func is_stunned() -> bool:
	return stun_left > 0.0


func can_open_window() -> bool:
	return cooldown_left <= 0.0 and not window_open and stun_left <= 0.0


## Host-only: opens the blue-flash counter window for `duration` seconds facing `dir`.
func open_window(dir: Vector2, duration: float = 0.48) -> bool:
	if not multiplayer.is_server() or not can_open_window():
		return false
	var norm: Vector2 = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.DOWN
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_set_window.rpc(true, norm, duration)
	else:
		_rpc_set_window(true, norm, duration)
	return true


## Host-only: closes an active counter window without triggering a counter.
func close_window() -> void:
	if not multiplayer.is_server() or not window_open:
		return
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_set_window.rpc(false, facing_dir, 0.0)
	else:
		_rpc_set_window(false, facing_dir, 0.0)


## Host-only: evaluates a frontal player hit against the open counter window.
func try_counter(attacker_pos: Vector2, source_peer: int) -> bool:
	if not multiplayer.is_server() or not window_open:
		return false
	var owner_2d: Node2D = get_parent() as Node2D
	if owner_2d == null:
		return false
	var to_attacker: Vector2 = attacker_pos - owner_2d.global_position
	if to_attacker.length_squared() > 1.0:
		var dot_val: float = to_attacker.normalized().dot(facing_dir)
		if dot_val < FRONT_CONE_COS:
			return false
	cooldown_left = cooldown_seconds
	var hit_pos: Vector2 = owner_2d.global_position + visual_offset
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_counter_triggered.rpc(source_peer, hit_pos, stun_seconds)
	else:
		_rpc_counter_triggered(source_peer, hit_pos, stun_seconds)
	if is_inside_tree():
		get_tree().call_group("dungeons", "note_player_counter", source_peer)
	return true


func _process(delta: float) -> void:
	_time += delta
	var redraw: bool = false
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
	if window_open:
		window_left -= delta
		redraw = true
		if multiplayer.is_server() and window_left <= 0.0:
			close_window()
	if stun_left > 0.0:
		stun_left = maxf(stun_left - delta, 0.0)
		redraw = true
		if stun_left <= 0.0:
			stun_ended.emit()
	if _ring_age >= 0.0:
		_ring_age += delta
		redraw = true
		if _ring_age >= 0.55:
			_ring_age = -1.0
	if redraw:
		queue_redraw()


@rpc("authority", "call_local", "reliable")
func _rpc_set_window(open: bool, dir: Vector2, duration: float) -> void:
	window_open = open
	facing_dir = dir
	window_left = duration if open else 0.0
	window_total = maxf(duration, 0.01)
	if open:
		_play_sound("counter_flash", -3.0)
	window_changed.emit(open)
	queue_redraw()


@rpc("authority", "call_local", "reliable")
func _rpc_counter_triggered(source_peer: int, hit_pos: Vector2, stun_dur: float) -> void:
	window_open = false
	window_left = 0.0
	stun_left = stun_dur
	_ring_age = 0.0
	_ring_origin = to_local(hit_pos)
	_play_sound("counter_hit", 1.5)
	for p: Player in Player.all:
		if p.is_multiplayer_authority():
			if p.global_position.distance_to(hit_pos) <= 420.0:
				p.add_shake(5.5)
			if p.get_multiplayer_authority() == source_peer:
				p.set_meta(&"_counter_boost_until_msec", Time.get_ticks_msec() + 4000)
	if multiplayer.get_peers().is_empty() and is_inside_tree():
		_solo_hitstop()
	countered.emit(source_peer)
	window_changed.emit(false)
	queue_redraw()


func _solo_hitstop() -> void:
	Engine.time_scale = 0.12
	var timer: SceneTreeTimer = get_tree().create_timer(0.095, true, false, true)
	await timer.timeout
	if is_inside_tree():
		Engine.time_scale = 1.0


func _play_sound(id: String, db: float) -> void:
	var path: String = "res://assets/audio/dungeon/%s.wav" % id
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path) as AudioStream
		if stream != null and is_inside_tree():
			var asp: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			asp.stream = stream
			asp.volume_db = db
			asp.max_distance = 520.0
			add_child(asp)
			asp.finished.connect(asp.queue_free)
			asp.play()
			return
	if is_inside_tree():
		Sfx.ui(self, "skills/reveal", db)


func _draw() -> void:
	if window_open:
		var t: float = 1.0 - clampf(window_left / window_total, 0.0, 1.0)
		var pulse: float = 0.72 + 0.28 * sin(_time * 42.0)
		var r: float = lerpf(28.0, 14.0, t)
		var c: Vector2 = visual_offset.round()
		draw_arc(c, r, 0.0, TAU, 24, Color(COUNTER_COLOR, 0.85 * pulse), 2.0)
		draw_arc(c, r - 3.0, 0.0, TAU, 20, Color(COUNTER_CORE, 0.65 * pulse), 1.0)
		## 4-point Steinsetzer counter glint star + frontal directional chevron
		var arm: float = lerpf(16.0, 24.0, pulse)
		draw_line(c - Vector2(arm, 0), c + Vector2(arm, 0), Color(COUNTER_CORE, 0.9), 2.0)
		draw_line(c - Vector2(0, arm * 0.75), c + Vector2(0, arm * 0.75), Color(COUNTER_CORE, 0.9), 2.0)
		var front_pt: Vector2 = (facing_dir * 20.0).round()
		draw_circle(c + front_pt, 3.0, COUNTER_CORE)
		draw_arc(c + front_pt, 5.0, 0.0, TAU, 12, COUNTER_COLOR, 1.0)

	if stun_left > 0.0:
		var sc: Vector2 = visual_offset + Vector2(0.0, -14.0)
		for i: int in 3:
			var ang: float = _time * 4.5 + float(i) * (TAU / 3.0)
			var pt: Vector2 = sc + Vector2(cos(ang) * 11.0, sin(ang) * 4.5)
			draw_rect(Rect2(pt.round() - Vector2.ONE, Vector2(3, 3)), COUNTER_COLOR)
			draw_rect(Rect2(pt.round(), Vector2(1, 1)), COUNTER_CORE)

	if _ring_age >= 0.0:
		var k: float = clampf(_ring_age / 0.55, 0.0, 1.0)
		var rr: float = lerpf(10.0, 68.0, pow(k, 0.55))
		var alpha: float = pow(1.0 - k, 1.4)
		draw_arc(_ring_origin, rr, 0.0, TAU, 32, Color(COUNTER_COLOR, alpha * 0.95), 3.0 * (1.0 - k * 0.6))
		draw_arc(_ring_origin, rr * 0.72, 0.0, TAU, 24, Color(COUNTER_CORE, alpha * 0.8), 1.5)
		var label_pos: Vector2 = (_ring_origin + Vector2(-24.0, -24.0 - k * 16.0)).round()
		PixelText.draw(self, "KONTER!", Vector2i(int(label_pos.x), int(label_pos.y)), Color(COUNTER_CORE, alpha), Color(Color("040208"), alpha))
