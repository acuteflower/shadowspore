class_name ProgressComponent
extends Node
## A player's money (in copper, see Currency) and XP. The host holds the truth and pushes it to
## the owning client after every change.

signal changed
signal gained(xp_amount: int) ## XP came in (not on the first sync), for the HUD
signal leveled(new_level: int) ## the level rose (not on the first sync): the reward is waiting in the Fortschritt window
signal claimed_changed(claimed_level: int, collected: bool) ## on every peer: rewards up to this level are collected (`collected` false = a load or join, no fanfare)

var copper: int = 0
var xp: int = 0
var level: int:
	get:
		return Levels.level_for(xp)
var claimed: int = 1 ## rewards up to this level are collected; the character's values (LevelRewards.stats_at) follow it. Host truth, known to every peer

var _synced: bool = false


func _ready() -> void:
	if not multiplayer.is_server():
		_rpc_request_claimed.rpc_id(1) ## health, stamina and armor of every player depend on it
		if is_multiplayer_authority():
			_rpc_request_state.rpc_id(1) ## the host may spawn us before our node existed, so ask
	apply_stats(false)


## Rewards waiting to be collected.
func claimable() -> int:
	return maxi(level - claimed, 0)


## The owner asks to collect the rewards of every level up to `up_to`; the host checks and tells everyone.
func request_claim(up_to: int) -> void:
	if multiplayer.is_server():
		_host_claim(up_to)
	elif is_multiplayer_authority():
		_rpc_claim.rpc_id(1, up_to)


## Host only: collects up to `up_to` (never above the reached level, never backwards).
func _host_claim(up_to: int) -> void:
	var target: int = mini(up_to, level)
	if target <= claimed:
		return
	_rpc_claimed.rpc(target, true)


## Host only: loading a save puts the collected level back (everything that depends on it follows).
func restore_claimed(value: int) -> void:
	if multiplayer.is_server():
		_rpc_claimed.rpc(clampi(value, 1, maxi(level, 1)), false)


## Health, stamina and overheal of the character follow the collected level. `grow`: what was gained is healed at once.
func apply_stats(grow: bool) -> void:
	var owner_node: Node = get_parent()
	if owner_node == null:
		return
	var stats: Dictionary = LevelRewards.stats_at(claimed)
	var health: HealthComponent = owner_node.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.apply_stats(float(stats["health"]), float(stats["armor"]), float(stats["overheal"]), grow)
	var stamina: StaminaComponent = owner_node.get_node_or_null("StaminaComponent") as StaminaComponent
	if stamina != null:
		stamina.set_max(float(stats["stamina"]), grow)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_claim(up_to: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_host_claim(up_to)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_claimed() -> void:
	if multiplayer.is_server():
		_rpc_claimed.rpc_id(multiplayer.get_remote_sender_id(), claimed, false)


@rpc("any_peer", "call_local", "reliable")
func _rpc_claimed(value: int, collected: bool) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	var grow: bool = collected and value > claimed
	claimed = value
	apply_stats(grow)
	changed.emit()
	claimed_changed.emit(claimed, collected)


## Host only.
func award(copper_amount: int, xp_amount: int) -> void:
	var before: int = level
	copper += copper_amount
	xp += xp_amount
	changed.emit()
	if xp_amount > 0:
		gained.emit(xp_amount)
	if level > before:
		leveled.emit(level)
	var owner_id: int = get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_rpc_state.rpc_id(owner_id, {"copper": copper, "xp": xp})


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		award(0, 0)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_state(state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	copper = int(state["copper"])
	var before: int = xp
	var level_before: int = level
	xp = int(state["xp"])
	changed.emit()
	if _synced and xp > before:
		gained.emit(xp - before)
	if _synced and level > level_before:
		leveled.emit(level)
	_synced = true
