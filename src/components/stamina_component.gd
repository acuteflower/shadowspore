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
		_set_current(current + regen_per_sec * regen_scale() * delta)


## Multiplier on continuous stamina regeneration: desert midday heat slows regen by up to -30 %, ERFRISCHT boosts it by +15 %.
func regen_scale() -> float:
	var heat: float = heat_amount()
	var effects: StatusEffects = get_node_or_null("../Effects") as StatusEffects
	var cool_bonus: float = DesertHeat.REFRESHED_REGEN_BONUS if (effects != null and effects.has("refreshed")) else 0.0
	return clampf(1.0 - DesertHeat.STAMINA_REGEN_PENALTY * heat + cool_bonus, 0.35, 1.5)


## 0..1 continuous desert sun-heat intensity on the owning player.
func heat_amount() -> float:
	var owner_node: Node = get_parent()
	if owner_node is Player:
		return clampf((owner_node as Player).heat_amount, 0.0, 1.0)
	var effects: StatusEffects = get_node_or_null("../Effects") as StatusEffects
	return clampf(effects.scale_of("sun_heat"), 0.0, 1.0) if (effects != null and effects.has("sun_heat")) else 0.0


## True while the owning player has ERFRISCHT (`refreshed`).
func is_refreshed() -> bool:
	var effects: StatusEffects = get_node_or_null("../Effects") as StatusEffects
	return effects != null and effects.has("refreshed")


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


## The active Glutatem tier can reduce the cost of sprinting; desert sun-heat (`sun_heat`) increases it by up to +15 %.
func sprint_scale() -> float:
	var effects: StatusEffects = get_node_or_null("../Effects") as StatusEffects
	var tier: int = int(effects.scale_of("glutatem")) if effects != null else 0
	var base: float = float(AlchemyRules.stamina_spec(tier)["sprint_scale"]) if tier > 0 else 1.0
	return base * (1.0 + DesertHeat.STAMINA_COST_PENALTY * heat_amount())


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
