class_name HealthComponent
extends Node
## Hit points. Only the host changes them and tells every peer the new value, so `damaged`
## and `died` fire everywhere and each peer can show its own feedback.

signal changed(current: float, maximum: float)
signal damaged(amount: float, from: Vector2, knockback: float)
signal healed(amount: float) ## on every peer, for floating numbers
signal ticked(amount: float) ## on every peer: damage over time (a status effect such as burn): no flash, no knock back, nothing interrupted
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

var armor: float = 0.0 ## from the collected levels and the talismans: every blow is multiplied by LevelRewards.damage_factor(armor)
var absorb: float = 0.0 ## the share of every hit and tick that is swallowed (talismans: Schweigtropfen), after the armor
var floor_value: float = 0.0 ## the story can make a fight unkillable: damage never takes health below this
var ward: Callable = Callable() ## host: a talisman's last wing beat (Rissfeder). Asked with the health a blow or tick would leave when that is 0; returns the health she keeps (> 0) or -1
var god_mode: bool = false ## dev cheat (host): no damage, no ticks, no kill
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
	if not multiplayer.is_server() or god_mode or current <= 0.0 or now < _invulnerable_until_msec:
		return
	_invulnerable_until_msec = now + int(invulnerable_seconds * 1000.0)
	if source != 0:
		last_attacker = source
	if armor > 0.0:
		amount = maxf(roundf(amount * LevelRewards.damage_factor(armor) * 10.0) / 10.0, 0.1)
	if absorb > 0.0:
		amount = maxf(roundf(amount * (1.0 - absorb) * 10.0) / 10.0, 0.1)
	_notify.rpc(amount, from, knockback, _warded(maxf(current - amount, floor_value)))


## Host only: a blow that cannot kill (a story or boss moment): takes `amount`, but never more than all but one point, and ignores the grace period after a hit.
## Whoever is already at one point is only knocked back.
func take_survivable(amount: float, from: Vector2, knockback: float, source: int = 0) -> void:
	if not multiplayer.is_server() or god_mode or current <= 0.0:
		return
	var taken: float = clampf(minf(amount, current - 1.0), 0.0, amount)
	_invulnerable_until_msec = Time.get_ticks_msec() + int(invulnerable_seconds * 1000.0)
	if source != 0:
		last_attacker = source
	_notify.rpc(taken, from, knockback, current - taken)


## Host only: one tick of damage over time (`StatusEffects`): ignores the grace period, does not knock back, does not make her flinch (`ticked`, not `damaged`).
func take_tick(amount: float, source: int = 0) -> void:
	if not multiplayer.is_server() or god_mode or current <= 0.0 or amount <= 0.0:
		return
	if source != 0:
		last_attacker = source
	if absorb > 0.0:
		amount = maxf(amount * (1.0 - absorb), 0.05)
	_notify_tick.rpc(amount, _warded(maxf(current - amount, floor_value)))


## Host only: `left` is the health a blow would leave. A ward (talisman) may turn a lethal one into a survived one; anything else passes unchanged.
func _warded(left: float) -> float:
	if left > 0.0 or not ward.is_valid():
		return left
	var kept: float = float(ward.call(left))
	return kept if kept > 0.0 else left


## Host only: no further hit counts for `seconds` (the grace a ward gives).
func grant_grace(seconds: float) -> void:
	_invulnerable_until_msec = maxi(_invulnerable_until_msec, Time.get_ticks_msec() + int(seconds * 1000.0))


## Host only: the end, whatever the invulnerability or the floor say (a judgement that falls on everybody).
func kill(from: Vector2 = Vector2.ZERO, source: int = 0) -> void:
	if not multiplayer.is_server() or god_mode or current <= 0.0:
		return
	if source != 0:
		last_attacker = source
	_notify.rpc(current, from, 0.0, 0.0)


## Sets the maximum, armor and overheal allowance (on every peer, from the collected level and the talismans). `grow`: the added maximum is healed at once.
## `gear`: the change comes from putting jewellery on or off: nothing is healed (else taking a necklace off and on again would heal), and a smaller
## maximum cuts what stood above it.
func apply_stats(new_max: float, new_armor: float, new_overheal: float, grow: bool, gear: bool = false) -> void:
	var gained_max: float = new_max - max_health
	var was_full: bool = current >= max_health - 0.01
	max_health = new_max
	armor = new_armor
	overheal_ratio = new_overheal
	if gear:
		if current > ceiling():
			current = ceiling()
		else:
			changed.emit(current, max_health)
		return
	if current > 0.0 and gained_max > 0.0 and (grow or was_full):
		current += gained_max ## whoever was at full health stays at full health
	else:
		changed.emit(current, max_health) ## the bars read the new maximum


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
func _notify_tick(amount: float, new_value: float) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	current = new_value
	ticked.emit(amount)
	if new_value <= 0.0:
		died.emit()


@rpc("any_peer", "call_local", "reliable")
func _set_value(value: float) -> void:
	if multiplayer.get_remote_sender_id() <= 1:
		current = value
