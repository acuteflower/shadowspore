class_name ItemBox
extends RefCounted
## A container of item slots (the town's stock; later every chest in the world). Same stack format as the inventory: a plain Dictionary `{"id", "count", ...extras}`, an empty
## slot is `{}`. The host holds the truth; `InventoryComponent` moves stacks between a player and the box it has opened (slot kind "box"), and whoever owns the box
## (TownManager, a chest) syncs `slots` to the peers on `changed`.
## Mutators here never emit: the owner emits `touch()` once after a batch.

signal changed

static var registry: Dictionary = {} ## id -> ItemBox, so the host can find the box a player asks to open

var id: String = ""
var slots: Array = []
var reach_ok: Callable = Callable() ## (player: Node2D) -> bool, whether that player may use the box now (empty = anyone)


func _init(box_id: String, size: int) -> void:
	id = box_id
	for i: int in size:
		slots.append({})
	registry[id] = self


static func find(box_id: String) -> ItemBox:
	return registry.get(box_id) as ItemBox


func size() -> int:
	return slots.size()


func touch() -> void:
	changed.emit()


func may_use(player: Node2D) -> bool:
	return not reach_ok.is_valid() or bool(reach_ok.call(player))


## Adds `count` of `id`; returns how many did not fit. A stack with extras (a refined weapon) is never merged.
func add_item(item: String, count: int, extra: Dictionary = {}) -> int:
	var limit: int = Items.max_stack({"id": item, "count": 1})
	if extra.is_empty():
		for stack: Dictionary in slots:
			if count > 0 and not stack.is_empty() and String(stack["id"]) == item and Items.extras(stack).is_empty() and int(stack["count"]) < limit:
				var added: int = mini(limit - int(stack["count"]), count)
				stack["count"] = int(stack["count"]) + added
				count -= added
	for i: int in slots.size():
		if count > 0 and (slots[i] as Dictionary).is_empty():
			var placed: int = mini(limit, count)
			var fresh: Dictionary = {"id": item, "count": placed}
			fresh.merge(extra)
			slots[i] = fresh
			count -= placed
	return count


func count_item(item: String) -> int:
	var total: int = 0
	for stack: Dictionary in slots:
		if not stack.is_empty() and String(stack["id"]) == item:
			total += int(stack["count"])
	return total


## Takes up to `count` of `id` (plain pieces before refined ones); returns how many were taken.
func remove_item(item: String, count: int) -> int:
	var order: Array[int] = []
	for i: int in slots.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = Items.refine(slots[a] as Dictionary)
		var rb: int = Items.refine(slots[b] as Dictionary)
		return ra < rb or (ra == rb and a < b))
	var taken: int = 0
	for i: int in order:
		var stack: Dictionary = slots[i]
		if taken < count and not stack.is_empty() and String(stack["id"]) == item:
			var part: int = mini(int(stack["count"]), count - taken)
			stack["count"] = int(stack["count"]) - part
			taken += part
			if int(stack["count"]) <= 0:
				slots[i] = {}
	return taken


## item id -> total count (what the town's recipes and costs read).
func totals() -> Dictionary:
	var out: Dictionary = {}
	for stack: Dictionary in slots:
		if not stack.is_empty():
			out[String(stack["id"])] = int(out.get(String(stack["id"]), 0)) + int(stack["count"])
	return out


## Replaces the slots (a snapshot from the host, a save), padded or cut to this box's size.
func import_slots(data: Array) -> void:
	for i: int in slots.size():
		var entry: Dictionary = (data[i] as Dictionary).duplicate() if i < data.size() and data[i] is Dictionary else {}
		if not entry.is_empty():
			entry["count"] = int(entry.get("count", 1))
		slots[i] = entry
