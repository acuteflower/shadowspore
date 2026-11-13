class_name QuestComponent
extends Node
## The local player's quests (data/quests.json: id -> {title, steps[{id, text, type "reach" | "flag", tile [x, y] of the goal, radius (tiles) for
## "reach", flag name for "flag"}]}). A quest runs its steps in order: a "reach" step is done when she comes within `radius` tiles of the
## goal (a step with `search` radius in tiles is a search area: the goal is its centre, the map draws the circle), a "flag" step when `set_flag(name)` is called, a "tasks" step when all of its `tasks` are done (see `task_states`); a quest may have `next`: the quest that starts when it finishes (the story calls it: a sign was read, a sword taken). The state (active steps, finished
## quests, flags) is saved (`export_data`). The HUD shows the current step (`QuestVine`) and the map its goal (`MapWindow`). Only the owner of a
## player has one (`Player.quests`).

signal changed ## anything: a quest started, a step done, a quest finished
signal step_started(quest_id: String, step: int)
signal step_done(quest_id: String, step: int)
signal quest_finished(quest_id: String)
signal story_event(event_name: String) ## a step that has an "event" started ("dialogue:<id>" shows a dialogue)

var tutorial_combo: int = 0
var _active: Dictionary = {} ## quest id -> index of the current step
var _done: Array[String] = []
var _flags: Dictionary = {} ## flag name -> true
var _player: Node2D
var _quests: Dictionary = {}


func _ready() -> void:
	_player = get_parent() as Node2D
	_quests = DataRegistry.table("quests")


func start(quest_id: String) -> void:
	if not _quests.has(quest_id) or _active.has(quest_id) or _done.has(quest_id):
		return
	_active[quest_id] = 0
	step_started.emit(quest_id, 0)
	_fire_event(quest_id)
	changed.emit()
	_check_flag(quest_id)


## Dev: starts a quest again from its first step (also one that is running or finished): its step flags are forgotten.
func restart(quest_id: String) -> void:
	if not _quests.has(quest_id):
		return
	_active.erase(quest_id)
	_done.erase(quest_id)
	for raw: Variant in (_quests[quest_id] as Dictionary).steps as Array:
		var flag: String = String((raw as Dictionary).get("flag", ""))
		if flag != "":
			_flags.erase(flag)
	for flag_name: String in _flags.keys(): ## and whatever the story keeps for it under its name (`<quest>_...`)
		if flag_name.begins_with(quest_id + "_"):
			_flags.erase(flag_name)
	start(quest_id)


func is_active(quest_id: String) -> bool:
	return _active.has(quest_id)


## The id of the step a running quest is at ("" when it is not running).
func active_step_id(quest_id: String) -> String:
	return String(_step(quest_id).get("id", "")) if _active.has(quest_id) else ""


func has_active_step(step_id: String) -> bool:
	if step_id == "":
		return false
	for quest_id: String in _active:
		if active_step_id(quest_id) == step_id:
			return true
	return false


func completed_step_ids(quest_id: String) -> Array[String]:
	var ids: Array[String] = []
	var definition: Dictionary = _quests.get(quest_id, {})
	var steps: Array = definition.get("steps", [])
	var completed: int = steps.size() if is_finished(quest_id) else int(_active.get(quest_id, 0))
	for i: int in completed:
		ids.append(String((steps[i] as Dictionary).get("id", "")))
	return ids


func is_finished(quest_id: String) -> bool:
	return _done.has(quest_id)


func has_flag(flag: String) -> bool:
	return bool(_flags.get(flag, false))


func set_flag(flag: String) -> void:
	_flags[flag] = true
	for quest_id: String in _active.keys():
		_check_flag(quest_id)
	changed.emit()


## The first running quest for the existing story and tutorial scripts.
func current() -> Dictionary:
	for quest_id: String in _active:
		return active_entry(quest_id)
	return {}


func active_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_active.keys())
	return ids


func finished_ids() -> Array[String]:
	return _done.duplicate()


func next_quest(quest_id: String) -> String:
	return String((_quests.get(quest_id, {}) as Dictionary).get("next", ""))


func quest_title(quest_id: String) -> String:
	return String((_quests.get(quest_id, {}) as Dictionary).get("title", quest_id))


func active_entry(quest_id: String) -> Dictionary:
	if not is_active(quest_id):
		return {}
	var step: Dictionary = _step(quest_id)
	var steps: Array = (_quests[quest_id] as Dictionary).steps
	return {"id": quest_id, "step_id": String(step.get("id", "")), "title": quest_title(quest_id), "text": String(step.text), "step": int(_active[quest_id]), "steps": steps.size(), "target": _target(step), "hint": String(step.get("hint", "")), "search": float(step.get("search", 0.0)), "tasks": task_states(step)}


func _target(step: Dictionary) -> Vector2:
	if step.has("anchor"): ## a named place (an interior's door): Interiors knows where it is
		var manager: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
		return manager.anchor_position(String(step.anchor)) if manager != null else Vector2.INF
	if step.has("actor"): ## someone who walks about (the knight): the node says where he is now
		for node: Node in get_tree().get_nodes_in_group("quest_actors"):
			var at: Vector2 = node.call("actor_position", String(step.actor)) as Vector2
			if at != Vector2.INF:
				return at
		return Vector2.INF
	if not step.has("tile"):
		return Vector2.INF
	var tile: Array = step.tile as Array
	return Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8.0, 8.0)


var _task_clock: float = 0.0
var _closest: Dictionary = {} ## "quest/step" -> her closest approach to a reach goal so far (px)
var _task_signature: String = ""


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var doors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	var in_transit: bool = doors != null and doors.is_busy() ## under a door's dark nothing may start: a talk would pause the game with the screen still black
	for quest_id: String in _active.keys():
		var step: Dictionary = _step(quest_id)
		if in_transit:
			break
		if String(step.get("type", "")) == "reach":
			var goal: Vector2 = _target(step)
			var dist: float = _player.global_position.distance_to(goal)
			var reach: float = float(step.get("radius", 4)) * 16.0
			var key: String = "%s/%s" % [quest_id, String(step.get("id", ""))]
			if dist <= reach:
				_closest.erase(key)
				_advance(quest_id)
				continue
			# Walking past a little beside the goal counts too: once she came within twice the radius and now moves away again, the step is done.
			if goal != Vector2.INF and not step.has("search") and not step.has("actor"):
				var best: float = float(_closest.get(key, INF))
				if dist < best:
					_closest[key] = dist
				elif best <= reach * 2.0 and dist > best + 40.0:
					_closest.erase(key)
					_advance(quest_id)
	_task_clock -= delta
	if _task_clock <= 0.0:
		_task_clock = 0.25
		_check_tasks()


## A step of type "tasks" has several jobs that can be done in any order: {id, text, kind "item" (the bag holds `count` of `item`) | "deliver" (like "item", but done only when the story sets `flag`: it was handed over) | "flag" (the story sets `flag`)}.
## It is done when all are; the HUD lists them with their counters (`current().tasks`). The bag is looked at four times a second.
func task_states(step: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in step.get("tasks", []) as Array:
		var task: Dictionary = raw as Dictionary
		var have: int = 0
		var need: int = 1
		var done: bool = false
		if String(task.get("kind", "flag")) == "deliver": ## collected in the bag, done when it has been handed over (the flag)
			need = int(task.get("count", 1))
			done = has_flag(String(task.get("flag", "")))
			var player_d: Player = _player as Player
			have = need if done else (mini(player_d.inventory.count_item(String(task.item)), need) if player_d != null else 0)
		elif String(task.get("kind", "flag")) == "stock": ## the town's stock plus the bag counts (what a build would draw on)
			need = int(task.get("count", 1))
			var player_s: Player = _player as Player
			var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
			var owned: int = 0
			if town != null:
				owned = int(town.stock.get(String(task.item), 0))
			if player_s != null:
				owned += player_s.inventory.count_item(String(task.item))
			have = mini(owned, need)
			done = has_flag(String(task.get("flag", ""))) if task.has("flag") else have >= need
		elif String(task.get("kind", "flag")) == "item":
			need = int(task.get("count", 1))
			var player: Player = _player as Player
			have = mini(player.inventory.count_item(String(task.item)), need) if player != null else 0
			done = have >= need
		else:
			done = has_flag(String(task.get("flag", "")))
			have = 1 if done else 0
		out.append({"text": String(task.text), "done": done, "have": have, "need": need, "counter": String(task.get("kind", "flag")) in ["item", "deliver", "stock"]})
	return out


func _check_tasks() -> void:
	var signature: String = ""
	for quest_id: String in _active.keys():
		var step: Dictionary = _step(quest_id)
		if String(step.get("type", "")) != "tasks":
			continue
		var all_done: bool = true
		for state: Dictionary in task_states(step):
			signature += "%s%d," % [state.text, state.have]
			if not bool(state.done):
				all_done = false
		if all_done:
			_advance(quest_id)
			return
	if signature != _task_signature:
		_task_signature = signature
		changed.emit()


func _step(quest_id: String) -> Dictionary:
	return ((_quests[quest_id] as Dictionary).steps as Array)[int(_active[quest_id])] as Dictionary


func _check_flag(quest_id: String) -> void:
	if _active.has(quest_id):
		var step: Dictionary = _step(quest_id)
		if String(step.get("type", "")) == "flag" and _flags.has(String(step.flag)):
			_advance(quest_id)


func _advance(quest_id: String) -> void:
	var index: int = int(_active[quest_id])
	step_done.emit(quest_id, index)
	index += 1
	if index >= ((_quests[quest_id] as Dictionary).steps as Array).size():
		_active.erase(quest_id)
		_done.append(quest_id)
		quest_finished.emit(quest_id)
		changed.emit()
		var next: String = String((_quests[quest_id] as Dictionary).get("next", "")) ## quests may lead straight into another
		if next != "":
			start(next)
		return
	_active[quest_id] = index
	step_started.emit(quest_id, index)
	_fire_event(quest_id)
	changed.emit()
	_check_flag(quest_id)


func _fire_event(quest_id: String) -> void:
	var event_name: String = String(_step(quest_id).get("event", ""))
	if event_name != "":
		story_event.emit(event_name)


func export_data() -> Dictionary:
	var names: Dictionary = {}
	for id: String in _active:
		names[id] = String(_step(id).get("id", ""))
	return {"active": _active.duplicate(), "active_steps": names, "done": _done.duplicate(), "flags": _flags.duplicate()}


func import_data(data: Dictionary) -> void:
	_closest.clear()
	_task_signature = ""
	_flags = (data.get("flags", {}) as Dictionary).duplicate()
	_active.clear()
	for quest_id: String in (data.get("active", {}) as Dictionary):
		if _quests.has(quest_id):
			var index: int = int((data.active as Dictionary)[quest_id])
			var name_saved: String = String((data.get("active_steps", {}) as Dictionary).get(quest_id, ""))
			var steps: Array = (_quests[quest_id] as Dictionary).steps
			## Older versions used find_knight on both sides of the ambush.
			if quest_id == "find_help" and name_saved == "find_knight" and not has_flag("woke_up") and not has_flag("left_hut") and index < 10:
				name_saved = "find_fallen_knight"
			if name_saved != "":
				for i: int in steps.size():
					if String((steps[i] as Dictionary).get("id", "")) == name_saved: index = i
			elif quest_id == "find_help" and index >= 3:
				index = 3 ## old crossroad/sign saves resume at the new fund section
			_active[quest_id] = clampi(index, 0, steps.size() - 1)
	_done.clear()
	for quest_id: Variant in data.get("done", []) as Array:
		_done.append(String(quest_id))
	_migrate_town_start(data)
	_migrate_plaza()
	changed.emit()


## Saves from before the fountain square (docs/brunnenplatz.md): a town quest already waiting at the lamp post goes back one step, to the square, which now
## founds the town and must stand before anything else can be built.
func _migrate_plaza() -> void:
	if not _active.has("town_start") or bool(_flags.get("built_plaza", false)):
		return
	var steps: Array = (_quests["town_start"] as Dictionary).steps as Array
	var plaza: int = -1
	for i: int in steps.size():
		if String((steps[i] as Dictionary).get("id", "")) == "build_plaza":
			plaza = i
	if plaza >= 0 and int(_active["town_start"]) > plaza:
		_active["town_start"] = plaza


## Saves from before the Gustav quest line: `town_start` used to end with "build a workshop", "a stranger comes", "talk to him". The first of those hands over to the new rescue
## quest (WorldLevel.resume_story starts the follow-up of every finished quest); the later two mean Gustav already lives in the town: the rescue counts as done and the workshop
## quest waits at the pickaxe (or is done when it was made).
func _migrate_town_start(data: Dictionary) -> void:
	var old_step: String = String((data.get("active_steps", {}) as Dictionary).get("town_start", ""))
	if not _active.has("town_start") or not old_step in ["build_workshop", "meet_stranger", "gustav_hello"]:
		return
	_active.erase("town_start")
	if not _done.has("town_start"):
		_done.append("town_start")
	_flags["built_lamp_post"] = true
	if old_step == "build_workshop":
		return
	for flag: String in ["built_workshop", "gustav_call_done", "wagon_seen", "wagon_spider_dead", "wagon_opened", "knows_gustav", "gustav_packed", "gustav_at_light", "gustav_joined", "workshop_done"]:
		_flags[flag] = true
	if not _done.has("gustav_rescue"):
		_done.append("gustav_rescue")
	if bool(_flags.get("crafted_pickaxe", false)):
		if not _done.has("town_workshop"):
			_done.append("town_workshop")
	else:
		var steps: Array = (_quests["town_workshop"] as Dictionary).steps as Array
		for i: int in steps.size():
			if String((steps[i] as Dictionary).get("id", "")) == "ws_pickaxe":
				_active["town_workshop"] = i
