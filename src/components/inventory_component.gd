class_name InventoryComponent
extends Node
## Backpack (hotbar + rucksack) and equipment of one player. The host holds the truth and
## validates every change; the owning client keeps a mirror that the host pushes after each change.

signal changed

const HOTBAR_SIZE: int = 8
const BACKPACK_SIZE: int = 24
const SIZE: int = HOTBAR_SIZE + BACKPACK_SIZE
const LOADOUT: String = "default"

var slots: Array = [] ## Dictionary stacks, index < HOTBAR_SIZE is the hotbar
var equipment: Dictionary = {} ## slot name -> stack
var selected: int = 0 ## the hotbar slot in use (the owner's choice, told to the host with the "select" op)


func _ready() -> void:
	for i: int in SIZE:
		slots.append({})
	for slot_name: String in DataRegistry.table("equipment_slots"):
		equipment[slot_name] = {}
	if multiplayer.is_server():
		_give_loadout() ## no push yet: the owner's node may not exist; it asks for the state itself
		changed.emit()
	elif is_multiplayer_authority():
		_rpc_request_state.rpc_id(1) ## the host may spawn us before our node existed, so ask


## What is in her hand: a tool in the selected hotbar slot overrides the equipped main-hand weapon.
func active_stack() -> Dictionary:
	var held: Dictionary = slots[selected]
	if not held.is_empty() and String(Items.definition(held).get("kind", "")) == "tool":
		return held
	return equipment.get("main_hand", {})


## Owner: picks a hotbar slot. Applied at once on the owner's machine, the host is told.
func select(index: int) -> void:
	if index == selected or index < 0 or index >= HOTBAR_SIZE:
		return
	selected = index
	if multiplayer.is_server():
		_commit()
	else:
		_rpc_request.rpc_id(1, "select", [index, 0])
		changed.emit()


func stack_at(kind: String, ref: Variant) -> Dictionary:
	if kind == "inv":
		return slots[int(ref)]
	return equipment.get(String(ref), {})


## Asks for a change. ops: "move" [from, to], "equip" [from, slot or ""], "unequip" [slot, to or -1],
## "use" [slot, 0] (eat/drink one item of a consumable).
func request(op: String, args: Array) -> void:
	if multiplayer.is_server():
		_apply(op, args)
	else:
		_rpc_request.rpc_id(1, op, args)


## Host only. Returns how many items did not fit.
func add_item(id: String, count: int = 1) -> int:
	var probe: Dictionary = {"id": id, "count": 1}
	var limit: int = Items.max_stack(probe)
	for i: int in SIZE: ## top up existing stacks first
		var existing: Dictionary = slots[i]
		if count > 0 and not existing.is_empty() and existing["id"] == id and int(existing["count"]) < limit:
			var added: int = mini(limit - int(existing["count"]), count)
			existing["count"] = int(existing["count"]) + added
			count -= added
	for i: int in SIZE:
		if count > 0 and slots[i].is_empty() and _fits(i, probe):
			var placed: int = mini(limit, count)
			slots[i] = {"id": id, "count": placed}
			count -= placed
	return count


## True if at least one of `id` would fit (a stack to top up or a free slot).
func has_room(id: String) -> bool:
	var probe: Dictionary = {"id": id, "count": 1}
	var limit: int = Items.max_stack(probe)
	for i: int in SIZE:
		var existing: Dictionary = slots[i]
		if existing.is_empty():
			if _fits(i, probe):
				return true
		elif existing["id"] == id and int(existing["count"]) < limit:
			return true
	return false


## Host only: adds items and syncs the owner. Returns how many did not fit.
func give(id: String, count: int = 1) -> int:
	var left: int = add_item(id, count)
	if left < count:
		_commit()
	return left


## How many of `id` the bag holds (worn gear is not counted).
func count_item(id: String) -> int:
	var total: int = 0
	for stack: Dictionary in slots:
		if not stack.is_empty() and String(stack["id"]) == id:
			total += int(stack["count"])
	return total


## Host only: takes `count` of `id` out of the bag (false, and nothing taken, if there are fewer).
func remove_item(id: String, count: int) -> bool:
	if count_item(id) < count:
		return false
	for i: int in SIZE:
		var stack: Dictionary = slots[i]
		if count > 0 and not stack.is_empty() and String(stack["id"]) == id:
			var taken: int = mini(int(stack["count"]), count)
			stack["count"] = int(stack["count"]) - taken
			count -= taken
			if int(stack["count"]) <= 0:
				slots[i] = {}
	_commit()
	return true


## True if one of `id` is in the bag or worn.
func has_item(id: String) -> bool:
	for stack: Dictionary in slots:
		if not stack.is_empty() and String(stack["id"]) == id:
			return true
	for stack: Variant in equipment.values():
		if not (stack as Dictionary).is_empty() and String((stack as Dictionary)["id"]) == id:
			return true
	return false


## UI helper: would dragging this onto that be accepted? (The host re-checks everything.)
func can_drop(from_kind: String, from_ref: Variant, to_kind: String, to_ref: Variant) -> bool:
	var source: Dictionary = stack_at(from_kind, from_ref)
	if source.is_empty():
		return false
	var target: Dictionary = stack_at(to_kind, to_ref)
	match [from_kind, to_kind]:
		["inv", "inv"]:
			return from_ref != to_ref and _fits(int(to_ref), source) and _fits(int(from_ref), target)
		["inv", "equip"]:
			return Items.fits_slot(String(to_ref), source) and _fits(int(from_ref), target)
		["equip", "inv"]:
			return _fits(int(to_ref), source) and (target.is_empty() or Items.fits_slot(String(from_ref), target))
	return false


func drop(from_kind: String, from_ref: Variant, to_kind: String, to_ref: Variant) -> void:
	match [from_kind, to_kind]:
		["inv", "inv"]:
			request("move", [from_ref, to_ref])
		["inv", "equip"]:
			request("equip", [from_ref, to_ref])
		["equip", "inv"]:
			request("unequip", [from_ref, to_ref])


## Empties the bag, the hotbar and the worn equipment (the wake-up in the hut: the story starts again with nothing). Host only.
func clear_all() -> void:
	for i: int in slots.size():
		slots[i] = {}
	for slot_name: String in equipment:
		equipment[slot_name] = {}
	_commit()


func _give_loadout() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	var id: String = "story_start" if world != null and world.has_method("starting_health_ratio") else LOADOUT
	var loadout: Dictionary = DataRegistry.get_entry("loadout", id)
	var worn: Dictionary = loadout.get("equipment", {})
	for slot_name: String in worn:
		if equipment.has(slot_name):
			equipment[slot_name] = {"id": String(worn[slot_name]), "count": 1}
	for entry: Dictionary in loadout.get("items", []):
		var at: int = int(entry.get("slot", -1)) ## an optional fixed slot (the tools sit in the hotbar)
		if at >= 0 and at < SIZE and (slots[at] as Dictionary).is_empty():
			slots[at] = {"id": String(entry["id"]), "count": int(entry.get("count", 1))}
		else:
			add_item(String(entry["id"]), int(entry.get("count", 1)))


func _fits(index: int, stack: Dictionary) -> bool:
	return index >= HOTBAR_SIZE or Items.hotbar_ok(stack)


func _valid(index: int) -> bool:
	return index >= 0 and index < SIZE


func _commit() -> void:
	changed.emit()
	var owner_id: int = get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_rpc_state.rpc_id(owner_id, {"slots": slots, "equipment": equipment})


func _apply(op: String, args: Array) -> void:
	if args.size() != 2:
		return
	var ok: bool = false
	match op:
		"move":
			ok = _move(int(args[0]), int(args[1]))
		"equip":
			ok = _equip(int(args[0]), String(args[1]))
		"unequip":
			ok = _unequip(String(args[0]), int(args[1]))
		"use":
			ok = _use(int(args[0]))
		"select":
			selected = clampi(int(args[0]), 0, HOTBAR_SIZE - 1)
			ok = true
	if ok:
		_commit()


## Eats one item: the stats of a consumable ("heal" now, "regen" more over "regen_seconds") go to its
## owner. Healing items are not used up when nothing can be healed (full health and full overheal).
func _use(index: int) -> bool:
	if not _valid(index):
		return false
	var stack: Dictionary = slots[index]
	var def: Dictionary = Items.definition(stack)
	var player: Player = get_parent() as Player
	if stack.is_empty() or String(def.get("kind", "")) != "consumable" or player == null:
		return false
	var stats: Dictionary = def.get("stats", {})
	var heals: bool = float(stats.get("heal", 0)) + float(stats.get("regen", 0)) > 0.0
	if heals and not player.health.can_heal():
		return false
	if float(stats.get("heal", 0)) > 0.0:
		player.health.heal(float(stats.heal))
	if stats.has("regen"):
		player.health.regen(float(stats.regen), float(stats.get("regen_seconds", 5)))
	stack["count"] = int(stack["count"]) - 1
	if int(stack["count"]) <= 0:
		slots[index] = {}
	return true


func _move(from: int, to: int) -> bool:
	if from == to or not _valid(from) or not _valid(to):
		return false
	var a: Dictionary = slots[from]
	var b: Dictionary = slots[to]
	if a.is_empty() or not _fits(to, a) or not _fits(from, b):
		return false
	if not b.is_empty() and a["id"] == b["id"] and Items.max_stack(a) > 1: ## merge stacks
		var room: int = Items.max_stack(a) - int(b["count"])
		var moved: int = mini(room, int(a["count"]))
		if moved > 0:
			b["count"] = int(b["count"]) + moved
			a["count"] = int(a["count"]) - moved
			if int(a["count"]) <= 0:
				slots[from] = {}
			return true
	slots[from] = b
	slots[to] = a
	return true


func _equip(from: int, slot_name: String) -> bool:
	if not _valid(from) or slots[from].is_empty():
		return false
	var stack: Dictionary = slots[from]
	if slot_name == "":
		slot_name = _slot_for(stack)
	if not equipment.has(slot_name) or not Items.fits_slot(slot_name, stack):
		return false
	var worn: Dictionary = equipment[slot_name]
	if not _fits(from, worn):
		return false
	equipment[slot_name] = stack
	slots[from] = worn
	return true


func _unequip(slot_name: String, to: int) -> bool:
	if not equipment.has(slot_name) or equipment[slot_name].is_empty():
		return false
	var stack: Dictionary = equipment[slot_name]
	if to < 0:
		for i: int in SIZE:
			if slots[i].is_empty() and _fits(i, stack):
				to = i
				break
	if not _valid(to) or not _fits(to, stack):
		return false
	var other: Dictionary = slots[to]
	if not other.is_empty() and not Items.fits_slot(slot_name, other):
		return false
	equipment[slot_name] = other
	slots[to] = stack
	return true


## First free matching equipment slot, else the first matching one (which gets swapped).
func _slot_for(stack: Dictionary) -> String:
	var fallback: String = ""
	for slot_name: String in equipment:
		if Items.fits_slot(slot_name, stack):
			if equipment[slot_name].is_empty():
				return slot_name
			if fallback == "":
				fallback = slot_name
	return fallback


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(op: String, args: Array) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_apply(op, args)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_commit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_state(state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	slots = state["slots"]
	equipment = state["equipment"]
	changed.emit()
