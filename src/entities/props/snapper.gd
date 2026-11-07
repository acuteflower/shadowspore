class_name Snapper
extends Flora
## Fangblume (docs/plant_life.md): a small night flower with two toothed jaws and a glowing lure. By day it is a closed bud and
## harmless. At night it opens, dangles its lure and now and then snaps at a moth that flutters in (a harmless local show). Anyone who
## comes too close gets a small sting (the host decides: `plants.json` `snapper` damage / range / cooldown); sneaking halves the range,
## and a short flare of the lure warns first. Inside the town's light it sleeps, so it is only a threat out at the dark edge. The sickle
## cuts it (2 hits, fibers and leaves), it grows back like a bush. Rows of its sheet: 0 open, 1 half shut, 2 closed.
const SNAP_TIME: float = 0.9
const LURE_FLARE: float = 0.35 ## seconds of warning before the jaws fall shut on someone

var _open: bool = false
var _snap_t: float = -1.0 ## 0..1 while the jaws are shutting and opening again
var _light_check: float = 0.0
var _in_light: bool = false
var _tell: Dictionary = {} ## host: player id -> seconds he has stood in range
var _cooldown: Dictionary = {} ## host: player id -> seconds until the next sting
var _bug: Node2D
var _bug_t: float = -1.0
var _bug_wait: float = 3.0
var _alert: float = 0.0 ## 0..1 the lure flares (someone is close), on every peer for its own player


func _setup_prop() -> void:
	super()
	_bug_wait = randf_range(2.0, 7.0)
	_bug = Node2D.new()
	_bug.z_index = 2
	_bug.material = Unlit.material()
	_bug.visible = false
	_bug.draw.connect(_draw_bug)
	add_child(_bug)


func apply_state(new_state: Dictionary, fx: String) -> void:
	super(new_state, fx)
	_pose_snap()


func _process(delta: float) -> void:
	super(delta)
	if not _on_screen and not multiplayer.is_server():
		return
	_light_check -= delta
	if _light_check <= 0.0:
		_light_check = 1.0
		var town: TownManager = level._town_node if level != null else null
		_in_light = town != null and town.founded and town.light_depth(global_position) > -4.0
	var snapper: Dictionary = _spec.get("snapper", {}) as Dictionary
	var was_open: bool = _open
	_open = not is_depleted() and not _in_light and TimeManager.night_amount() >= float(snapper.get("open_from", 0.45)) and MineManager.night_at(self, 1.0) > 0.0
	if _snap_t >= 0.0:
		_snap_t += delta / SNAP_TIME
		if _snap_t >= 1.0:
			_snap_t = -1.0
		_pose_snap()
	elif was_open != _open:
		_pose_snap()
	_update_alert(delta)
	_update_bug(delta)
	if multiplayer.is_server():
		_sting(delta, snapper)


## Every peer: how close is the local player (the lure flares so a careful walker sees the danger).
func _update_alert(delta: float) -> void:
	var near: bool = false
	if _open and _snap_t < 0.0:
		for player: Player in Player.all:
			if is_instance_valid(player) and player.is_multiplayer_authority() and player.global_position.distance_to(_head()) < float((_spec.snapper as Dictionary).range) * 2.0:
				near = true
	_alert = move_toward(_alert, 1.0 if near else 0.0, delta * 4.0)
	if _glow != null:
		_glow.self_modulate = Color(1.0 + 0.8 * _alert, 1.0 + 0.2 * _alert, 1.0 + 0.4 * _alert, 1.0)


func _head() -> Vector2:
	return global_position + Vector2(0.0, -float((_spec.height as Array)[variant]) * 0.6)


## Host: the sting. Someone who stays inside the range through the warning flare is bitten once per cooldown.
func _sting(delta: float, snapper: Dictionary) -> void:
	for id: Variant in _cooldown.keys():
		_cooldown[id] = float(_cooldown[id]) - delta
		if float(_cooldown[id]) <= 0.0:
			_cooldown.erase(id)
	if not _open or _snap_t >= 0.0:
		return
	var range_px: float = float(snapper.get("range", 15.0))
	var seen: Dictionary = {}
	for player: Player in Player.all:
		if not is_instance_valid(player) or player.health.current <= 0.0 or not player.is_inside_tree():
			continue
		var id: int = player.get_instance_id()
		var reach: float = range_px * (0.5 if player.stealth.sneaking else 1.0)
		if player.global_position.distance_to(_head()) > reach or _cooldown.has(id):
			continue
		seen[id] = true
		_tell[id] = float(_tell.get(id, 0.0)) + delta
		if float(_tell[id]) >= LURE_FLARE:
			_tell.erase(id)
			_cooldown[id] = float(snapper.get("cooldown", 3.0))
			player.health.take_damage(float(snapper.get("damage", 4.0)), global_position, 30.0, 0)
			level._rpc_thing_fx.rpc(cell, "snap", player.global_position)
			return
	for id: Variant in _tell.keys():
		if not seen.has(id):
			_tell.erase(id)


## Everyone (via the level): the jaws shut on something at `at`.
func play_fx(fx: String, at: Vector2) -> void:
	if fx != "snap":
		return
	_snap_t = 0.0
	_bug_t = -1.0
	_bug.visible = false
	if _on_screen:
		_burst(6, [Color("ff4ad0"), Color("f4ecd8")], 34.0, _head() - global_position + Vector2(0, -2) + (at - global_position).limit_length(4.0))
	_pose_snap()


func _pose_snap() -> void:
	if _sprite == null or is_depleted():
		return
	var row: int = 0 if _open else 2
	if _snap_t >= 0.0:
		row = 1 if (_snap_t < 0.14 or _snap_t > 0.74) else 2
		if _snap_t > 0.9:
			row = 0 if _open else 2
	var columns: int = int(_spec.columns)
	_sprite.frame = variant + columns * row
	_sync_glow(true)
	if _glow != null:
		_glow.visible = row != 2 or _snap_t >= 0.0 or _open


## A moth flutters toward the lure and is eaten: only a show (every peer has its own), the real snapping at players is the host's.
func _update_bug(delta: float) -> void:
	if not _open or not _on_screen or _snap_t >= 0.0:
		_bug.visible = false
		_bug_t = -1.0
		return
	if _bug_t < 0.0:
		_bug_wait -= delta
		if _bug_wait <= 0.0:
			_bug_wait = randf_range(5.0, 12.0)
			_bug_t = 0.0
		return
	_bug_t += delta / 1.6
	_bug.visible = true
	var lure: Vector2 = Vector2(5.0, -float((_spec.height as Array)[variant]) - 6.0)
	var angle: float = float(cell.x * 7 + cell.y * 3) + _bug_t * 5.0
	var spiral: float = 26.0 * (1.0 - _bug_t)
	_bug.position = lure + Vector2(cos(angle), sin(angle) * 0.6) * spiral
	_bug.queue_redraw()
	if _bug_t >= 1.0:
		_bug_t = -1.0
		_bug.visible = false
		play_fx("snap", global_position + lure)


func _draw_bug() -> void:
	var flap: int = int(Time.get_ticks_msec() / 70) % 2
	_bug.draw_rect(Rect2(-1, -1 - flap, 2, 1), Color(0.95, 0.92, 1.0, 0.9))
	_bug.draw_rect(Rect2(1, -1 + flap - 1, 2, 1), Color(0.95, 0.92, 1.0, 0.9))
	_bug.draw_rect(Rect2(0, 0, 1, 1), Color("b8a0d8"))
