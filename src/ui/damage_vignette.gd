extends ColorRect
## Pulses red at the screen edges whenever the player takes damage.

const FADE_SPEED: float = 2.5

var _amount: float = 0.0


func _ready() -> void:
	visible = false
	set_process(false)


func bind(health: HealthComponent) -> void:
	health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void:
		_amount = 1.0
		visible = true
		set_process(true)
		(material as ShaderMaterial).set_shader_parameter("amount", _amount))


func _process(delta: float) -> void:
	_amount = maxf(_amount - FADE_SPEED * delta, 0.0)
	(material as ShaderMaterial).set_shader_parameter("amount", _amount)
	if _amount <= 0.0:
		visible = false
		set_process(false)
