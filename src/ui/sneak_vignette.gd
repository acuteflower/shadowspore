extends ColorRect
## Fades the sneak look (gray tint + vignette) in and out.

const FADE_SPEED: float = 4.0 ## full fade in 0.25 s

var _stealth: StealthComponent
var _amount: float = 0.0


func bind(stealth: StealthComponent) -> void:
	_stealth = stealth


func _process(delta: float) -> void:
	var target: float = 1.0 if _stealth != null and _stealth.sneaking else 0.0
	if _amount != target:
		_amount = move_toward(_amount, target, FADE_SPEED * delta)
		(material as ShaderMaterial).set_shader_parameter("amount", _amount)
		visible = _amount > 0.0
