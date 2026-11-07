class_name HealthComponent
extends Node
## Hit points. Only the host changes them and tells every peer the new value, so `damaged`
## and `died` fire everywhere and each peer can show its own feedback.

signal changed(current: float, maximum: float)
signal damaged(amount: float, from: Vector2, knockback: float)
signal healed(amount: float) ## on every peer, for floating numbers
signal died

const OVERHEAL_SECONDS: float = 60.0 ## overheal stays this long after it was last topped up ...
const OVERHEAL_DECAY: float = 2.0 ## ... then drains by this many points a second

@export var max_health: float = 100.0
@export var overheal_ratio: float = 0.1 ## healing may carry health this far above the maximum (gear may raise it)
@export var invulnerable_seconds: float = 0.0 ## after a hit, further hits are ignored for this long

var current: float = 0.0:
	set(value):
		current = value
		changed.emit(current, max_health)

var floor_value: float = 0.0 ## the story can make a fight unkillable: damage never takes health below this
var overheal_left: float = 0.0 ## seconds until overheal starts to drain (counted on every peer, set by heals)
var last_attacker: int = 0 ## peer id of the player who hit last (host only), for credit on a kill
var _invulnerable_until_msec: int = 0
var _regens: Array[Dictionary] = [] ## host: {per, left} (heal `per` every second for `left` more seconds)
var _regen_clock: float = 0.0
var _decay_clock: float = 0.0


func _ready() -> void:
	current = max_health


## Host only.
func take_damage(amount: float, from: Vector2, knockback: float, source: int = 0) -> void:
	var now: int = Time.get_ticks_msec()
	if not multiplayer.is_server() or current <= 0.0 or now < _invulnerable_until_msec:
		return
	_invulnerable_until_msec = now + int(invulnerable_seconds * 1000.0)
	if source != 0:
		last_attacker = source
	_notify.rpc(amount, from, knockback, maxf(current - amount, floor_value))


## Host only: the end, whatever the invulnerability or the floor say (a judgement that falls on everybody).
func kill(from: Vector2 = Vector2.ZERO, source: int = 0) -> void:
	if not multiplayer.is_server() or current <= 0.0:
		return
	if source != 0:
		last_attacker = source
	_notify.rpc(current, from, 0.0, 0.0)


## The most health can be raised to: the maximum plus the overheal allowance.
func ceiling() -> float:
	return max_health * (1.0 + overheal_ratio)


## True while healing would still do something (alive and below the overheal ceiling).
func can_heal() -> bool:
	return current > 0.0 and current < ceiling() - 0.01


## Host only: heals now. Past the maximum it becomes overheal (up to `overheal_ratio`), which
## absorbs hits first and drains after `OVERHEAL_SECONDS`. Not for the dead.
func heal(amount: float) -> void:
	if not multiplayer.is_server() or not can_heal():
		return
	var new_value: float = minf(current + amount, ceiling())
	_heal_notify.rpc(new_value, new_value - current, OVERHEAL_SECONDS if new_value > max_health else 0.0)


## Host only: heals `total` over `seconds`, one tick a second; several regens stack.
func regen(total: float, seconds: float) -> void:
	if multiplayer.is_server() and seconds >= 1.0:
		_regens.append({"per": total / floorf(seconds), "left": floori(seconds)})


func _process(delta: float) -> void:
	if current > max_health:
		overheal_left = maxf(overheal_left - delta, 0.0)
	if not multiplayer.is_server():
		return
	if current > max_health and overheal_left <= 0.0: ## the overheal fades away
		_decay_clock += delta
		if _decay_clock >= 0.5:
			_decay_clock -= 0.5
			_set_value.rpc(maxf(current - OVERHEAL_DECAY * 0.5, max_health))
	if _regens.is_empty():
		return
	_regen_clock += delta
	if _regen_clock < 1.0:
		return
	_regen_clock -= 1.0
	if current <= 0.0:
		_regens.clear()
		return
	for entry: Dictionary in _regens:
		heal(float(entry.per))
		entry.left = int(entry.left) - 1
	_regens = _regens.filter(func(entry: Dictionary) -> bool: return int(entry.left) > 0)


@rpc("any_peer", "call_local", "reliable")
func _heal_notify(new_value: float, gained: float, overheal_seconds: float) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	current = new_value
	if overheal_seconds > 0.0:
		overheal_left = overheal_seconds
	healed.emit(gained)


## Host only: sets the health to `value` (cheat menu), at least 1 and at most the maximum.
func set_health(value: float) -> void:
	if multiplayer.is_server():
		_set_value.rpc(clampf(value, 1.0, max_health))


## Host only: back to full health (respawn).
func heal_full() -> void:
	if multiplayer.is_server():
		_set_value.rpc(max_health)


@rpc("any_peer", "call_local", "reliable")
func _notify(amount: float, from: Vector2, knockback: float, new_value: float) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	current = new_value
	damaged.emit(amount, from, knockback)
	if new_value <= 0.0:
		died.emit()


@rpc("any_peer", "call_local", "reliable")
func _set_value(value: float) -> void:
	if multiplayer.get_remote_sender_id() <= 1:
		current = value
