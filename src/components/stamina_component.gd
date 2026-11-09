class_name StaminaComponent
extends Node
## Stamina pool. After any use, regeneration pauses for `regen_delay` seconds, then runs continuously.

signal changed(current: float, maximum: float)

@export var max_stamina: float = 100.0
@export var regen_per_sec: float = 25.0
@export var regen_delay: float = 1.25 ## seconds

var current: float = 0.0

var _delay_left: float = 0.0


func _ready() -> void:
	current = max_stamina
	changed.emit(current, max_stamina)


func _process(delta: float) -> void:
	if _delay_left > 0.0:
		_delay_left -= delta
	elif current < max_stamina:
		_set_current(current + regen_per_sec * delta)


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


## A new maximum (from the collected level); `grow` gives what was added right away.
func set_max(value: float, grow: bool = false) -> void:
	var added: float = value - max_stamina
	max_stamina = value
	_set_current(current + added if grow and added > 0.0 else current)


func refill() -> void:
	_set_current(max_stamina)


func _use(amount: float) -> void:
	_delay_left = regen_delay
	_set_current(current - amount)


func _set_current(value: float) -> void:
	current = clampf(value, 0.0, max_stamina)
	changed.emit(current, max_stamina)
