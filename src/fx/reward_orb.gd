class_name RewardOrb
extends Node2D
## A glowing coin or XP orb that bursts out of a dead enemy and homes in on the player who
## earned it. Purely cosmetic: the reward itself was already paid out by the host.

enum Kind { GOLD, SILVER, COPPER, XP }

const COLORS: Dictionary = {
	Kind.GOLD: [Color("fff3b0"), Color("f2c14e")],
	Kind.SILVER: [Color("f4f8ff"), Color("b8c4d8")],
	Kind.COPPER: [Color("ffcf9a"), Color("d6874a")],
	Kind.XP: [Color("d8fffa"), Color("7fe3da")],
}
const BURST_TIME: float = 0.28
const TRAIL: int = 4

var _kind: Kind = Kind.COPPER
var _target: Node2D
var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0


func _ready() -> void:
	material = Unlit.material() ## coins and XP keep glowing at night
var _history: Array[Vector2] = []
var _message: String = "" ## shown above the player when this orb arrives
var _message_color: Color = Color.WHITE


static func spawn(world: Node, from: Vector2, target: Node2D, kind: Kind, message: String = "", message_color: Color = Color.WHITE) -> void:
	var orb: RewardOrb = RewardOrb.new()
	orb._kind = kind
	orb._target = target
	orb._message = message
	orb._message_color = message_color
	orb._velocity = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 120.0)
	orb.z_index = 15
	world.add_child(orb)
	orb.global_position = from


func _process(delta: float) -> void:
	_age += delta
	if not is_instance_valid(_target):
		queue_free()
		return
	_history.append(global_position)
	if _history.size() > TRAIL:
		_history.pop_front()
	if _age < BURST_TIME:
		_velocity = _velocity.move_toward(Vector2.ZERO, 260.0 * delta)
	else:
		var aim: Vector2 = _target.global_position + Vector2(0, -10) - global_position
		if aim.length() < 6.0:
			if _message != "":
				DamageNumber.spawn_text(get_tree().current_scene, _target.global_position + Vector2(0, -58), _message, _message_color)
			queue_free()
			return
		_velocity = _velocity.lerp(aim.normalized() * (150.0 + (_age - BURST_TIME) * 420.0), minf(10.0 * delta, 1.0))
	global_position += _velocity * delta
	queue_redraw()


func _draw() -> void:
	var colors: Array = COLORS[_kind]
	for i: int in _history.size():
		var trail: Vector2 = (_history[i] - global_position).round()
		draw_rect(Rect2(trail, Vector2.ONE), Color(colors[1], 0.5 * float(i + 1) / TRAIL))
	draw_rect(Rect2(-2, -2, 4, 4), Color(colors[1], 0.35))
	draw_rect(Rect2(-1, -1, 2, 2), colors[1])
	draw_rect(Rect2(-1, -1, 1, 1), colors[0])
