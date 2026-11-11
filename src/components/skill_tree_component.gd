class_name SkillTreeComponent
extends Node
## Host-owned state of the skill graph (docs/skill_tree.md, docs/faehigkeiten_kampf_konzept.md).
## Roots are available from the start. Unlocks and upgrades cost points, and placeholders are free to explore.
## Skill points are `level - 1 - spent`; only the host decides what is learned, only the owner gets the answer.
signal changed
signal explored(id: String)
signal learned(id: String)

const RENAMED: Dictionary = {"shadow_blink": "shadow_step"} ## node ids of older saves -> their successor (the blink was archived for the shadow step)
var _discovered: Array[String] = []
var _learned: Array[String] = []


func _ready() -> void:
	if not multiplayer.is_server() and is_multiplayer_authority():
		_request_state.rpc_id(1)


func definitions() -> Dictionary:
	return DataRegistry.table("skills").get("nodes", {})


func node(id: String) -> Dictionary:
	return definitions().get(id, {}) as Dictionary


func is_root(id: String) -> bool:
	return bool(node(id).get("root", false))


func is_upgrade(id: String) -> bool:
	return bool(node(id).get("upgrade", false))


func is_unlock(id: String) -> bool:
	return bool(node(id).get("unlock", false))


func is_learned(id: String) -> bool:
	return id in _learned


## A real ability she has: a root or a purchase.
func is_awake(id: String) -> bool:
	return is_root(id) or is_learned(id)


## Upgrades are always shown (the player should see that they exist); placeholders only once explored.
func is_explored(id: String) -> bool:
	return is_awake(id) or id in _discovered or is_upgrade(id)


func is_visible(id: String) -> bool:
	var def: Dictionary = node(id)
	if def.is_empty():
		return false
	if is_root(id):
		return true
	var parent_id: String = String(def.get("parent", ""))
	if is_upgrade(id):
		return is_visible(parent_id)
	return is_explored(parent_id)


func can_explore(id: String) -> bool:
	return bool(node(id).get("placeholder", false)) and is_visible(id) and not is_explored(id)


# ------------------------------------------------------------------ levels, points, upgrades
## The reached level of the player this graph belongs to (1 without a progress component).
func level() -> int:
	var progress: ProgressComponent = get_parent().get_node_or_null("ProgressComponent") as ProgressComponent if get_parent() != null else null
	return progress.level if progress != null else 1


func points_total() -> int:
	return maxi(level() - 1, 0)


func points_spent() -> int:
	var spent: int = 0
	for id: String in _learned:
		spent += cost(id)
	return spent


func points_free() -> int:
	return maxi(points_total() - points_spent(), 0)


func required_level(id: String) -> int:
	return int(node(id).get("level", 1))


func cost(id: String) -> int:
	return int(node(id).get("cost", 0))


## The upgrades hanging directly on a skill (or upgrade), in the order of the data file.
func upgrades_of(id: String) -> Array[String]:
	var found: Array[String] = []
	for other: String in definitions():
		var def: Dictionary = node(other)
		if bool(def.get("upgrade", false)) and String(def.get("parent", "")) == id:
			found.append(other)
	return found


## Every upgrade of a skill, also the ones further down the chain (combo_four -> combo_five).
func upgrade_chain(id: String) -> Array[String]:
	var chain: Array[String] = []
	var pending: Array[String] = [id]
	while not pending.is_empty():
		var next: Array[String] = upgrades_of(pending.pop_front())
		chain.append_array(next)
		pending.append_array(next)
	return chain


func learned_count(id: String) -> int:
	var count: int = 0
	for upgrade_id: String in upgrade_chain(id):
		if is_learned(upgrade_id):
			count += 1
	return count


## "learned", "ready" (can be bought right now), "short" (level reached, not enough points),
## "blocked" (the parent is missing) or "locked" (level too low). "" for other nodes.
func learn_state(id: String) -> StringName:
	if not is_upgrade(id) and not is_unlock(id):
		return &""
	if is_learned(id):
		return &"learned"
	var parent_id: String = String(node(id).get("parent", ""))
	if not is_awake(parent_id):
		return &"blocked"
	if level() < required_level(id):
		return &"locked"
	return &"ready" if points_free() >= cost(id) else &"short"


func upgrade_state(id: String) -> StringName:
	return learn_state(id) if is_upgrade(id) else &""


func can_learn(id: String) -> bool:
	return learn_state(id) == &"ready"


## True when any upgrade of this skill could be bought right now (the flower shows it).
func has_ready_upgrade(id: String) -> bool:
	for upgrade_id: String in upgrade_chain(id):
		if can_learn(upgrade_id):
			return true
	return false


func request_explore(id: String) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.is_server():
		_explore(id)
	else:
		_request_explore.rpc_id(1, id)


func request_learn(id: String) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.is_server():
		_learn(id)
	else:
		_request_learn.rpc_id(1, id)


func _explore(id: String) -> void:
	if not multiplayer.is_server() or not can_explore(id):
		return
	_discovered.append(id)
	changed.emit()
	explored.emit(id)
	_sync(id)


func _learn(id: String) -> void:
	if not multiplayer.is_server() or not can_learn(id):
		return
	_learned.append(id)
	changed.emit()
	learned.emit(id)
	_sync(id)


func export_data() -> Dictionary:
	return {"discovered": _discovered.duplicate(), "learned": _learned.duplicate()}


## Old saves default to the roots. Unknown, duplicate and disconnected nodes are dropped; upgrades must also fit the level
## and the points (the experience is restored before this runs).
func import_data(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_discovered.clear()
	_learned.clear()
	var incoming: Variant = data.get("discovered", [])
	if incoming is Array:
		incoming = (incoming as Array).map(func(value: Variant) -> Variant: return RENAMED.get(value, value)) ## older saves
		for _pass: int in definitions().size():
			for value: Variant in incoming:
				if value is String and can_explore(String(value)):
					_discovered.append(String(value))
	var bought: Variant = data.get("learned", [])
	if bought is Array:
		for _pass: int in definitions().size():
			for value: Variant in bought:
				if value is String and can_learn(String(value)):
					_learned.append(String(value))
	changed.emit()
	_sync()


func _sync(new_id: String = "") -> void:
	var owner_id: int = get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_state.rpc_id(owner_id, _discovered, _learned, new_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_explore(id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_explore(id)


@rpc("any_peer", "call_remote", "reliable")
func _request_learn(id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_learn(id)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_sync()


@rpc("any_peer", "call_remote", "reliable")
func _state(ids: Array[String], bought: Array[String], new_id: String) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_discovered = ids.duplicate()
	_learned = bought.duplicate()
	changed.emit()
	if not new_id.is_empty():
		if new_id in _learned:
			learned.emit(new_id)
		else:
			explored.emit(new_id)
