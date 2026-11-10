class_name StaminaComponent
extends Node
## Stamina pool. After any use, regeneration pauses for `regen_delay` seconds, then runs continuously.
## Glutatem (a potion, status effect `glutatem` on the sibling `Effects`, its scale = the tier) adds a pulse of stamina every second
## that also comes during the pause, and from tier IV shortens the pause (AlchemyRules.stamina_spec). Every peer counts it itself, like the rest of the pool.

signal changed(current: float, maximum: float)

@export var max_stamina: float = 100.0
@export var regen_per_sec: float = 25.0
@export var regen_delay: float = 1.25 ## seconds

var current: float = 0.0

var _delay_left: float = 0.0
var _pulse_left: float = 1.0


func _ready() -> void:
	current = max_stamina
	changed.emit(current, max_stamina)


func _process(delta: float) -> void:
	var tier: int = _glutatem_tier()
	if tier > 0:
		_pulse_left -= delta
		if _pulse_left <= 0.0:
			_pulse_left += 1.0
			_set_current(current + float(AlchemyRules.stamina_spec(tier)["per_second"])) ## the potion's pulse, also during the pause
	else:
		_pulse_left = 1.0
	if _delay_left > 0.0:
		_delay_left -= delta
	elif current < max_stamina:
		_set_current(current + regen_per_sec * delta)


func _glutatem_tier() -> int:
	var effects: StatusEffects = get_node_or_null("../Effects") as StatusEffects
	return int(effects.scale_of("glutatem")) if effects != null else 0


## True while regeneration is paused after use.
func is_waiting() -> bool:
	return _delay_left > 0.0


## Pays `amount` at once. Returns false (and pays nothing) if there is not enough.
func spend(amount: float) -> bool:
	if current < amount:
		return false
	_use(amount)
	return true


## Pays `rate * delta` for continuous use. Returns false once the pool is empty.
func drain(rate: float, delta: float) -> bool:
	if current <= 0.0:
		return false
	_use(rate * delta)
	return current > 0.0


## The active Glutatem tier can reduce the cost of sprinting.
func sprint_scale() -> float:
	var effects: StatusEffects = get_node_or_null("../Effects") as StatusEffects
	var tier: int = int(effects.scale_of("glutatem")) if effects != null else 0
	return float(AlchemyRules.stamina_spec(tier)["sprint_scale"]) if tier > 0 else 1.0


## A new maximum (from the collected level); `grow` gives what was added right away.
func set_max(value: float, grow: bool = false) -> void:
	var added: float = value - max_stamina
	max_stamina = value
	_set_current(current + added if grow and added > 0.0 else current)


func refill() -> void:
	_set_current(max_stamina)


func _use(amount: float) -> void:
	var tier: int = _glutatem_tier()
	_delay_left = regen_delay * (float(AlchemyRules.stamina_spec(tier)["delay_scale"]) if tier > 0 else 1.0)
	_set_current(current - amount)


func _set_current(value: float) -> void:
	current = clampf(value, 0.0, max_stamina)
	changed.emit(current, max_stamina)
