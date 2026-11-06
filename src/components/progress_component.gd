class_name ProgressComponent
extends Node
## A player's money (in copper, see Currency) and XP. The host holds the truth and pushes it to
## the owning client after every change.

signal changed
signal gained(xp_amount: int) ## XP came in (not on the first sync), for the HUD

var copper: int = 0
var xp: int = 0
var level: int:
	get:
		return Levels.level_for(xp)

var _synced: bool = false


func _ready() -> void:
	if not multiplayer.is_server() and is_multiplayer_authority():
		_rpc_request_state.rpc_id(1) ## the host may spawn us before our node existed, so ask


## Host only.
func award(copper_amount: int, xp_amount: int) -> void:
	copper += copper_amount
	xp += xp_amount
	changed.emit()
	if xp_amount > 0:
		gained.emit(xp_amount)
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
	xp = int(state["xp"])
	changed.emit()
	if _synced and xp > before:
		gained.emit(xp - before)
	_synced = true
