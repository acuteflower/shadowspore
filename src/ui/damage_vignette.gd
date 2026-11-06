extends ColorRect
## Pulses red at the screen edges whenever the player takes damage.

const FADE_SPEED: float = 2.5

var _amount: float = 0.0


func bind(health: HealthComponent) -> void:
	health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void: _amount = 1.0)


func _process(delta: float) -> void:
	if _amount > 0.0:
		_amount = maxf(_amount - FADE_SPEED * delta, 0.0)
		(material as ShaderMaterial).set_shader_parameter("amount", _amount)
