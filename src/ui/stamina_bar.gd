extends SapVine
## Stamina as a teal sap vine growing out to the right (the scarf color). Dims while
## regeneration is paused, turns orange and pulses when nearly empty.

const FILL: Array[Color] = [Color("7fe3da"), Color("4eb5b0"), Color("2f8a8c")]
const FILL_LOW: Array[Color] = [Color("f2a58b"), Color("e0755f"), Color("a8453b")]
const LOW_RATIO: float = 0.2
const WAITING_DIM: float = 0.7

var _stamina: StaminaComponent


func _init() -> void:
	dir = 1
	length = STAMINA_LEN
	base_thick = 3
	fork_at = 0.62


## It stays level and ripples like a snake, then dips a little at the end.
func _offset(t: float) -> float:
	return sin(t * TAU * 1.4) * 3.0 * minf(t * 3.0, 1.0) + 5.0 * t * t


func bind(stamina: StaminaComponent) -> void:
	_stamina = stamina


func _update_state(_delta: float) -> void:
	if _stamina == null:
		return
	ratio = _stamina.current / _stamina.max_stamina
	var low: bool = ratio < LOW_RATIO
	palette = FILL_LOW if low else FILL
	dim = WAITING_DIM if _stamina.is_waiting() else 1.0
	label = str(ceili(_stamina.current))
	alert = Color("f2a58b") if low else Color(0, 0, 0, 0)
