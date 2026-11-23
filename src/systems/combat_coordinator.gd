class_name CombatCoordinator
extends RefCounted
## Lightweight host-authoritative pack flanking & melee attack-token director for Shadowspore 2.0 (`T6`).
## Prevents multiple predators from clumping onto the exact same pixel or swinging on the exact same frame:
## - Assigns evenly spaced angular flanking slots around each targeted Player (`0°` binder, `±110°` flankers).
## - Grants staggered melee strike tokens per target (`MAX_SIMULTANEOUS_MELEE = 1`, short cadence gap) so fights read cleanly.
## - Broadcasts ally death shockwaves (`notify_ally_death`) so nearby packmates flinch back (`PACK_RECOIL`) for 0.35s.

const TOKEN_HOLD_MAX_MSEC: int = 1350
const POST_STRIKE_GAP_MSEC: int = 280
const PACK_RECOIL_RADIUS: float = 48.0

## target_instance_id -> Array[int] (ordered enemy_instance_ids hunting this target)
static var _hunters_by_target: Dictionary = {}
## target_instance_id -> {"holder": int, "expires": int, "cooldown_until": int}
static var _tokens_by_target: Dictionary = {}
static var _last_prune_msec: int = 0


static func _prune_if_needed(now_msec: int) -> void:
	if now_msec - _last_prune_msec < 600:
		return
	_last_prune_msec = now_msec
	var empty_targets: Array[int] = []
	for t_key: Variant in _hunters_by_target.keys():
		var tid: int = int(t_key)
		var tobj: Object = instance_from_id(tid)
		if tobj == null or not (tobj is Node2D) or not (tobj as Node2D).is_inside_tree():
			empty_targets.append(tid)
			continue
		var list: Array = _hunters_by_target[tid] as Array
		for i: int in range(list.size() - 1, -1, -1):
			var eid: int = int(list[i])
			var eobj: Object = instance_from_id(eid)
			if eobj == null or not (eobj is Node2D) or not (eobj as Node2D).is_inside_tree():
				list.remove_at(i)
		if list.is_empty():
			empty_targets.append(tid)
	for tid: int in empty_targets:
		_hunters_by_target.erase(tid)
		_tokens_by_target.erase(tid)


## Registers `enemy` as hunting `target` and returns its tactical angular offset (radians) around the approach vector:
## Slot 0 = direct binder (`0.0`), Slot 1 = right flank (`+1.65 rad`), Slot 2 = left flank (`-1.65 rad`), Slot 3+ = rear pincer!
static func claim_flank_angle(enemy: Node2D, target: Node2D) -> float:
	if enemy == null or target == null:
		return 0.0
	var now: int = Time.get_ticks_msec()
	_prune_if_needed(now)
	var eid: int = enemy.get_instance_id()
	var tid: int = target.get_instance_id()

	# Remove from any previous target's hunter ring
	for other_key: Variant in _hunters_by_target.keys():
		var otid: int = int(other_key)
		if otid != tid:
			var olist: Array = _hunters_by_target[otid] as Array
			olist.erase(eid)

	if not _hunters_by_target.has(tid):
		_hunters_by_target[tid] = []
	var ring: Array = _hunters_by_target[tid] as Array
	var slot_idx: int = ring.find(eid)
	if slot_idx < 0:
		slot_idx = ring.size()
		ring.append(eid)

	if ring.size() <= 1 or slot_idx == 0:
		return 0.0
	const FLANK_ANGLES: Array[float] = [0.0, 1.58, -1.58, 2.55, -2.55]
	return FLANK_ANGLES[slot_idx % FLANK_ANGLES.size()]


static func unregister(enemy: Node2D) -> void:
	if enemy == null:
		return
	var eid: int = enemy.get_instance_id()
	for t_key: Variant in _hunters_by_target.keys():
		var list: Array = _hunters_by_target[t_key] as Array
		list.erase(eid)
	for tok_key: Variant in _tokens_by_target.keys():
		var rec: Dictionary = _tokens_by_target[tok_key] as Dictionary
		if int(rec.get("holder", 0)) == eid:
			rec["holder"] = 0
			rec["expires"] = 0


## Host-only melee cadence gate: if only 1 predator hunts `target`, always returns true immediately!
## When a pack (2+) surrounds `target`, ensures strikes stagger cleanly instead of overlapping on one frame.
static func request_melee_token(enemy: Node2D, target: Node2D, hold_sec: float = 0.95) -> bool:
	if enemy == null or target == null:
		return true
	var now: int = Time.get_ticks_msec()
	var eid: int = enemy.get_instance_id()
	var tid: int = target.get_instance_id()
	var ring: Array = _hunters_by_target.get(tid, []) as Array
	if ring.size() <= 1:
		return true

	var rec: Dictionary = _tokens_by_target.get(tid, {"holder": 0, "expires": 0, "cooldown_until": 0}) as Dictionary
	var holder: int = int(rec.get("holder", 0))
	var expires: int = int(rec.get("expires", 0))
	var cd_until: int = int(rec.get("cooldown_until", 0))

	if holder != 0 and holder != eid and now < expires:
		var holder_obj: Object = instance_from_id(holder)
		if holder_obj != null and (holder_obj is Node2D) and (holder_obj as Node2D).is_inside_tree():
			return false

	if holder != eid and now < cd_until:
		return false

	rec["holder"] = eid
	rec["expires"] = now + maxi(250, roundi(hold_sec * 1000.0))
	_tokens_by_target[tid] = rec
	return true


static func release_melee_token(enemy: Node2D, target: Node2D) -> void:
	if enemy == null or target == null:
		return
	var eid: int = enemy.get_instance_id()
	var tid: int = target.get_instance_id()
	if not _tokens_by_target.has(tid):
		return
	var rec: Dictionary = _tokens_by_target[tid] as Dictionary
	if int(rec.get("holder", 0)) == eid:
		rec["holder"] = 0
		rec["expires"] = 0
		rec["cooldown_until"] = Time.get_ticks_msec() + POST_STRIKE_GAP_MSEC
		_tokens_by_target[tid] = rec


## When a predator is slain, nearby packmates recoil briefly (`on_pack_ally_slain(fallen_pos)`).
static func notify_ally_death(fallen: Node2D, tree: SceneTree) -> void:
	unregister(fallen)
	if fallen == null or tree == null:
		return
	var pos: Vector2 = fallen.global_position
	var r2: float = PACK_RECOIL_RADIUS * PACK_RECOIL_RADIUS
	for node: Node in tree.get_nodes_in_group("predators"):
		if node == fallen or not (node is Node2D):
			continue
		var ally: Node2D = node as Node2D
		if ally.is_inside_tree() and ally.global_position.distance_squared_to(pos) <= r2:
			if ally.has_method("on_pack_ally_slain"):
				ally.call("on_pack_ally_slain", pos)
