class_name SkillTreeComponent
extends Node
## Host-owned discovery of cosmetic placeholders. Never changes abilities, stats or XP.
signal changed
signal explored(id: String)

var _discovered: Array[String] = []


func _ready() -> void:
	if not multiplayer.is_server() and is_multiplayer_authority():
		_request_state.rpc_id(1)


func definitions() -> Dictionary:
	return DataRegistry.table("skills").get("nodes", {})


func is_awake(id: String) -> bool:
	return bool((definitions().get(id, {}) as Dictionary).get("root", false))


func is_explored(id: String) -> bool:
	return is_awake(id) or id in _discovered


func is_visible(id: String) -> bool:
	var node: Dictionary = definitions().get(id, {})
	return not node.is_empty() and (is_awake(id) or is_explored(String(node.get("parent", ""))))


func can_explore(id: String) -> bool:
	var node: Dictionary = definitions().get(id, {})
	return bool(node.get("placeholder", false)) and is_visible(id) and not is_explored(id)


func request_explore(id: String) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.is_server():
		_explore(id)
	else:
		_request_explore.rpc_id(1, id)


func _explore(id: String) -> void:
	if not multiplayer.is_server() or not can_explore(id):
		return
	_discovered.append(id)
	changed.emit()
	explored.emit(id)
	_sync(id)


func export_data() -> Dictionary:
	return {"discovered": _discovered.duplicate()}


## Old saves default to the three roots. Reject unknown, real and disconnected nodes.
func import_data(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_discovered.clear()
	var incoming: Variant = data.get("discovered", [])
	if incoming is Array:
		for _pass: int in definitions().size():
			for value: Variant in incoming:
				if value is String and can_explore(String(value)):
					_discovered.append(String(value))
	changed.emit()
	_sync()


func _sync(new_id: String = "") -> void:
	var owner_id: int = get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_state.rpc_id(owner_id, _discovered, new_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_explore(id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_explore(id)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_sync()


@rpc("any_peer", "call_remote", "reliable")
func _state(ids: Array[String], new_id: String) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_discovered = ids.duplicate()
	changed.emit()
	if not new_id.is_empty():
		explored.emit(new_id)
