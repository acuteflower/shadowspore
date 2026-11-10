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
var held: Dictionary = {} ## the stack on the cursor while the inventory window is open (the host holds the truth, the owner sees it)
var box: ItemBox ## the container this player has open (the town's stock, a chest): slot kind "box"; the host sets it with the "box_open" op after checking the reach
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
	if kind == "box":
		return box.slots[int(ref)] if _exists("box", ref) else {}
	return equipment.get(String(ref), {})


## Opens a container for this player (the owner calls it on its own mirror, the host checks the reach and attaches it for real).
func open_box(opened: ItemBox) -> void:
	box = opened
	request("box_open", [opened.id])


func close_box() -> void:
	if box != null:
		box = null
		request("box_close", [0])


## Asks for a change. ops (kind = "inv" with an index, or "equip" with a slot name):
##   "move" [from, to], "equip" [from, slot or ""], "unequip" [slot, to or -1], "use" [slot, 0] (eat/drink one item), "select" [slot, 0];
##   the cursor stack: "click" [kind, ref] (take the stack / put it down, top up or swap), "rclick" [kind, ref] (empty hand: take half,
##   a single piece of gear: equip; full hand: put down ONE), "quick" [kind, ref] (shift-click: gear to its slot, else hotbar <-> rucksack),
##   "hotkey" [kind or "held", ref, n] (number key: swap with hotbar slot n), "throw" [all] (throw the cursor stack or one piece into the world),
##   "dropslot" [kind, ref, all] (throw from a slot: one piece or all), "sort" [0] (stack and sort the rucksack), "stow" [0] (cursor stack back into the bag), "sort_box" [0] / "take_all" [0] (open container: sort it / move everything into the bag),
##   "box_open" [box id] / "box_close" [0] (the container slots, kind "box" with an index, work in "click" / "rclick" / "quick" while a box is open and within reach).
func request(op: String, args: Array) -> void:
	if multiplayer.is_server():
		_apply(op, args)
	else:
		_rpc_request.rpc_id(1, op, args)


## Host only. Returns how many items did not fit. `extra` is what a stack carries besides id and count (the refinement of a weapon, `Items.extras`):
## such a stack is never merged into another one.
func add_item(id: String, count: int = 1, extra: Dictionary = {}) -> int:
	var probe: Dictionary = {"id": id, "count": 1}
	var limit: int = Items.max_stack(probe)
	for i: int in SIZE: ## top up existing stacks first
		var existing: Dictionary = slots[i]
		if extra.is_empty() and count > 0 and not existing.is_empty() and existing["id"] == id and Items.extras(existing).is_empty() and int(existing["count"]) < limit:
			var added: int = mini(limit - int(existing["count"]), count)
			existing["count"] = int(existing["count"]) + added
			count -= added
	for i: int in SIZE:
		if count > 0 and slots[i].is_empty() and _fits(i, probe):
			var placed: int = mini(limit, count)
			var fresh: Dictionary = {"id": id, "count": placed}
			fresh.merge(extra)
			slots[i] = fresh
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
func give(id: String, count: int = 1, extra: Dictionary = {}) -> int:
	var left: int = add_item(id, count, extra)
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


## How many of `id` the bag holds that are not refined: a refined weapon is never sold by accident.
func count_plain(id: String) -> int:
	var total: int = 0
	for stack: Dictionary in slots:
		if not stack.is_empty() and String(stack["id"]) == id and Items.refine(stack) == 0:
			total += int(stack["count"])
	return total


## Host only: takes `count` of `id` out of the bag (false, and nothing taken, if there are fewer).
func remove_item(id: String, count: int) -> bool:
	if count_item(id) < count:
		return false
	var order: Array[int] = [] ## plain pieces go first: a refined weapon is only given up when nothing else is left
	for i: int in SIZE:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return Items.refine(slots[a] as Dictionary) < Items.refine(slots[b] as Dictionary) or (Items.refine(slots[a] as Dictionary) == Items.refine(slots[b] as Dictionary) and a < b))
	for i: int in order:
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


## UI helper: would the stack on the cursor be accepted by this slot? (The host re-checks everything.)
func can_place(to_kind: String, to_ref: Variant) -> bool:
	return not held.is_empty() and _exists(to_kind, to_ref) and _accepts(to_kind, to_ref, held)


## Is there such a slot ("inv" with an index, "equip" with a slot name)?
func slot_exists(kind: String, ref: Variant) -> bool:
	return _exists(kind, ref)


## Host only: takes the stack out of a slot (`kind` "inv" with an index or "equip" with a slot name) and hands it over, with everything it carries. {} if there is none.
func take_stack(kind: String, ref: Variant) -> Dictionary:
	if not _exists(kind, ref) or stack_at(kind, ref).is_empty():
		return {}
	var taken: Dictionary = stack_at(kind, ref)
	_set_stack(kind, ref, {})
	_commit()
	return taken


## Developer cheat (host): sets the refinement of the weapon in her hand (0 = plain, up to the weapon's cap, Glut cleared). False when she holds nothing refinable.
func debug_set_refine(level: int) -> bool:
	var stack: Dictionary = active_stack()
	if not RefineRules.is_refinable(stack):
		return false
	var level_now: int = clampi(level, 0, RefineRules.cap(stack))
	if level_now > 0:
		stack[RefineRules.KEY_LEVEL] = level_now
	else:
		stack.erase(RefineRules.KEY_LEVEL)
	stack.erase(RefineRules.KEY_PITY)
	_commit()
	return true


## Empties the bag, the hotbar and the worn equipment (the wake-up in the hut: the story starts again with nothing). Host only.
func clear_all() -> void:
	for i: int in slots.size():
		slots[i] = {}
	for slot_name: String in equipment:
		equipment[slot_name] = {}
	held = {}
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
	if box != null and multiplayer.is_server():
		box.touch() ## the box's owner syncs it to every peer
	var owner_id: int = get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_rpc_state.rpc_id(owner_id, {"slots": slots, "equipment": equipment, "held": held})


func _apply(op: String, args: Array) -> void:
	if args.is_empty():
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
		"click":
			ok = _click(String(args[0]), args[1])
		"rclick":
			ok = _rclick(String(args[0]), args[1])
		"quick":
			ok = _quick(String(args[0]), args[1])
		"hotkey":
			ok = _hotkey(String(args[0]), args[1], int(args[2]))
		"throw":
			ok = _throw_held(bool(args[0]))
		"dropslot":
			ok = _drop_slot(String(args[0]), args[1], bool(args[2]))
		"sort":
			ok = _sort()
		"sort_box":
			ok = _sort_box()
		"take_all":
			ok = _take_all()
		"stow":
			ok = _stow()
		"select":
			selected = clampi(int(args[0]), 0, HOTBAR_SIZE - 1)
			ok = true
		"box_open":
			var wanted: ItemBox = ItemBox.find(String(args[0]))
			box = wanted if wanted != null and wanted.may_use(get_parent() as Node2D) else null
			ok = box != null
		"box_close":
			box = null
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
	if stack.is_empty() or player == null:
		return false
	if not usable(player, def):
		return false
	var kind: String = String(def.get("kind", ""))
	if kind == "consumable":
		var stats: Dictionary = def.get("stats", {})
		if float(stats.get("heal", 0)) > 0.0:
			player.health.heal(float(stats.heal))
		if stats.has("regen"):
			player.health.regen(float(stats.regen), float(stats.get("regen_seconds", 5)))
	elif kind == "potion":
		_drink(player, AlchemyRules.of(stack))
	else:
		return false
	var pause: String = AlchemyRules.pause_effect(def)
	if pause != "" and player.effects != null:
		player.effects.apply(pause, AlchemyRules.pause("heal" if pause == "wound_pause" else ("special" if pause == "special_pause" else "food")))
	stack["count"] = int(stack["count"]) - 1
	if int(stack["count"]) <= 0:
		slots[index] = {}
	return true


## True while `player` may use an item of this definition now: something to heal (healing items are kept at full health), no pause running.
## The owner asks it before the animation starts, the host again before anything is taken.
static func usable(player: Player, def: Dictionary) -> bool:
	var kind: String = String(def.get("kind", ""))
	if kind != "consumable" and kind != "potion":
		return false
	var pause: String = AlchemyRules.pause_effect(def)
	if pause != "" and player.effects != null and player.effects.has(pause):
		return false
	if kind == "consumable":
		var stats: Dictionary = def.get("stats", {})
		return not (float(stats.get("heal", 0)) + float(stats.get("regen", 0)) > 0.0 and not player.health.can_heal())
	var info: Dictionary = def.get("potion", {}) as Dictionary
	if String(info.get("type", "")) == "heal":
		var level: int = int(info.get("tier", 1))
		var burning: bool = false
		for effect: Variant in AlchemyRules.cleanses("heal", level):
			burning = burning or (player.effects != null and player.effects.has(String(effect)))
		var room: bool = player.health.can_heal() if AlchemyRules.overheals(level) else (player.health.current > 0.0 and player.health.current < player.health.max_health - 0.01)
		return room or burning
	return player.health.current > 0.0


## Host: a potion takes effect (Wundtau heals at once and may put out burning, Glutatem starts its 30 seconds).
func _drink(player: Player, info: Dictionary) -> void:
	var level: int = int(info.get("tier", 1))
	match String(info.get("type", "")):
		"heal":
			for effect: Variant in AlchemyRules.cleanses("heal", level):
				if player.effects != null:
					player.effects.clear(String(effect))
			var amount: float = AlchemyRules.heal_amount(level, player.health.max_health)
			if not AlchemyRules.overheals(level):
				amount = minf(amount, maxf(player.health.max_health - player.health.current, 0.0)) ## only Wundtau V spills over into overheal
			if amount > 0.0:
				player.health.heal(amount)
		"stamina":
			if player.effects != null:
				player.effects.apply("glutatem", AlchemyRules.stamina_spec(level).seconds, float(level))
		"ashen":
			if player.effects != null:
				player.effects.clear("burn") ## the skin takes the flames in
				player.effects.apply("ashen", AlchemyRules.ashen_spec(level).seconds, float(level))
		"clarity":
			if player.effects != null:
				player.effects.apply("clear_vision", AlchemyRules.clarity_spec(level).seconds, float(level))
				player.effects.clear("hallucinated")
		"wisp":
			if player.effects != null:
				player.effects.apply("wisp", AlchemyRules.wisp_spec(level).seconds, float(level))
		"leere":
			var spec: Dictionary = AlchemyRules.leere_spec(level)
			if player.effects != null:
				player.effects.apply("void_rift", spec.seconds, float(level))
			# Spawn the actual rift effect
			var rift_script: GDScript = load("res://src/effects/void_rift_effect.gd")
			var rift: Object = rift_script.new()
			rift.name = "VoidRift_%d" % player.get_instance_id()
			player.add_child(rift)
			rift.open(player.global_position, spec.radius, spec.dps, spec.lifesteal, spec.self_dps, spec.slow, spec.pull, spec.seconds)


# ---------------------------------------------------------------- the cursor stack
func _exists(kind: String, ref: Variant) -> bool:
	if kind == "box":
		return box != null and int(ref) >= 0 and int(ref) < box.size() and box.may_use(get_parent() as Node2D)
	return _valid(int(ref)) if kind == "inv" else (kind == "equip" and equipment.has(String(ref)))


func _set_stack(kind: String, ref: Variant, stack: Dictionary) -> void:
	if kind == "inv":
		slots[int(ref)] = stack
	elif kind == "box":
		box.slots[int(ref)] = stack
	else:
		equipment[String(ref)] = stack


## May this slot hold `stack`? The hotbar takes tools and consumables only, an equipment slot one matching piece of gear.
func _accepts(kind: String, ref: Variant, stack: Dictionary) -> bool:
	if stack.is_empty():
		return true
	if kind == "inv":
		return _fits(int(ref), stack)
	if kind == "box":
		return true
	return int(stack["count"]) == 1 and slot_open(String(ref)) and Items.fits_slot(String(ref), stack) and TalismanRules.conflict(equipment, String(ref), stack) == ""


## Why a piece of jewellery cannot go into this equipment slot ("SCHON EIN ARMBAND ANGELEGT"), "" when it can: for the window's hint. Only one piece of each kind is worn.
func refusal(slot_name: String, stack: Dictionary) -> String:
	return TalismanRules.refusal(equipment, slot_name, stack)


## Talisman slots wake up with the milestones (LevelRewards): talisman_1 .. talisman_N are open once N slots are collected. Every other slot is always open.
func slot_open(slot_name: String) -> bool:
	if not slot_name.begins_with("talisman_"):
		return true
	var progress: ProgressComponent = get_parent().get_node_or_null("ProgressComponent") as ProgressComponent
	if progress == null:
		return true
	return slot_name.trim_prefix("talisman_").to_int() <= int(LevelRewards.stats_at(progress.claimed)["talismans"])


## Left click: take the whole stack; with a full hand put it down (an empty slot), top up a stack of the same item (the rest stays in the
## hand) or swap with what lies there.
func _click(kind: String, ref: Variant) -> bool:
	if not _exists(kind, ref):
		return false
	var current: Dictionary = stack_at(kind, ref)
	if held.is_empty():
		if current.is_empty():
			return false
		held = current
		_set_stack(kind, ref, {})
		return true
	if current.is_empty():
		if not _accepts(kind, ref, held):
			return false
		_set_stack(kind, ref, held)
		held = {}
		return true
	if kind != "equip" and String(current["id"]) == String(held["id"]) and Items.extras(current) == Items.extras(held) and Items.max_stack(held) > 1:
		var room: int = Items.max_stack(held) - int(current["count"])
		if room <= 0:
			return false
		var moved: int = mini(room, int(held["count"]))
		current["count"] = int(current["count"]) + moved
		held["count"] = int(held["count"]) - moved
		if int(held["count"]) <= 0:
			held = {}
		return true
	if not _accepts(kind, ref, held):
		return false
	_set_stack(kind, ref, held)
	held = current
	return true


## Right click: with an empty hand take half of a stack (rounded up); a single piece of gear is equipped, worn gear taken off.
## With a full hand put down exactly one piece.
func _rclick(kind: String, ref: Variant) -> bool:
	if not _exists(kind, ref):
		return false
	var current: Dictionary = stack_at(kind, ref)
	if held.is_empty():
		if current.is_empty():
			return false
		if kind == "equip":
			return _unequip(String(ref), -1)
		if Items.max_stack(current) <= 1:
			if kind == "inv" and Items.definition(current).has("slot") and _slot_for(current) != "":
				return _equip(int(ref), "")
			held = current
			_set_stack(kind, ref, {})
			return true
		var take: int = ceili(float(current["count"]) / 2.0)
		held = {"id": String(current["id"]), "count": take}
		current["count"] = int(current["count"]) - take
		if int(current["count"]) <= 0:
			_set_stack(kind, ref, {})
		return true
	if kind == "equip" or not _accepts(kind, ref, {"id": held["id"], "count": 1}):
		return false
	if current.is_empty():
		var one: Dictionary = (held as Dictionary).duplicate() ## keeps the refinement of a single weapon
		one["count"] = 1
		_set_stack(kind, ref, one)
	elif String(current["id"]) == String(held["id"]) and Items.extras(current) == Items.extras(held) and int(current["count"]) < Items.max_stack(current):
		current["count"] = int(current["count"]) + 1
	else:
		return false
	held["count"] = int(held["count"]) - 1
	if int(held["count"]) <= 0:
		held = {}
	return true


## Shift-click: gear goes to its slot (worn gear back into the bag); anything else jumps between hotbar and rucksack.
func _quick(kind: String, ref: Variant) -> bool:
	if not _exists(kind, ref) or not held.is_empty():
		return false
	var current: Dictionary = stack_at(kind, ref)
	if current.is_empty():
		return false
	if kind == "equip":
		return _unequip(String(ref), -1)
	if kind == "box": ## out of the container into the bag
		var left: int = add_item(String(current["id"]), int(current["count"]), Items.extras(current))
		var taken: bool = left < int(current["count"])
		current["count"] = left
		if left <= 0:
			_set_stack(kind, ref, {})
		return taken
	if _exists("box", 0): ## a container is open: the stack goes into it
		var left_over: int = box.add_item(String(current["id"]), int(current["count"]), Items.extras(current))
		var stowed: bool = left_over < int(current["count"])
		current["count"] = left_over
		if left_over <= 0:
			slots[int(ref)] = {}
		return stowed
	if Items.definition(current).has("slot") and _slot_for(current) != "":
		return _equip(int(ref), "")
	var from: int = int(ref)
	var first: int = 0 if from >= HOTBAR_SIZE else HOTBAR_SIZE
	var last: int = HOTBAR_SIZE if from >= HOTBAR_SIZE else SIZE
	var moved: bool = false
	for pass_index: int in 2: ## first top up stacks of the same item, then use free slots
		for i: int in range(first, last):
			if int(current["count"]) <= 0 or not _fits(i, current):
				continue
			var target: Dictionary = slots[i]
			if pass_index == 0 and not target.is_empty() and String(target["id"]) == String(current["id"]) and Items.extras(target) == Items.extras(current) and int(target["count"]) < Items.max_stack(target):
				var room: int = mini(Items.max_stack(target) - int(target["count"]), int(current["count"]))
				target["count"] = int(target["count"]) + room
				current["count"] = int(current["count"]) - room
				moved = true
			elif pass_index == 1 and target.is_empty():
				slots[i] = current.duplicate()
				current["count"] = 0
				moved = true
	if int(current["count"]) <= 0:
		slots[from] = {}
	return moved


## A number key over a slot: it swaps with hotbar slot `n` (an item goes in, whatever stood there comes out); with a full hand and no
## slot under the cursor the cursor stack goes into hotbar slot `n`.
func _hotkey(kind: String, ref: Variant, n: int) -> bool:
	if n < 0 or n >= HOTBAR_SIZE:
		return false
	if kind == "held":
		return _click("inv", n)
	if kind == "box" or not _exists(kind, ref):
		return false
	if kind == "equip":
		if stack_at("equip", ref).is_empty():
			return _equip(n, String(ref))
		return _unequip(String(ref), n)
	var from: int = int(ref)
	if from == n:
		return false
	return _move(n, from) if (slots[from] as Dictionary).is_empty() else _move(from, n)


## Q with the cursor stack: one piece (or, with `all`, everything) is thrown into the world.
func _throw_held(all: bool) -> bool:
	if held.is_empty():
		return false
	var count: int = int(held["count"]) if all else 1
	if not _throw(held, count):
		return false
	held["count"] = int(held["count"]) - count
	if int(held["count"]) <= 0:
		held = {}
	return true


## Q over a slot: one piece of the stack (or the whole stack) is thrown into the world.
func _drop_slot(kind: String, ref: Variant, all: bool) -> bool:
	if kind == "box" or not _exists(kind, ref):
		return false
	var current: Dictionary = stack_at(kind, ref)
	if current.is_empty():
		return false
	var count: int = int(current["count"]) if (all or kind == "equip") else 1
	if not _throw(current, count):
		return false
	current["count"] = int(current["count"]) - count
	if int(current["count"]) <= 0:
		_set_stack(kind, ref, {})
	return true


func _throw(stack: Dictionary, count: int) -> bool:
	var player: Player = get_parent() as Player
	if player == null or player.health.current <= 0.0 or count <= 0:
		return false
	DropComponent.spawn_thrown(get_tree(), String(stack["id"]), count, player.global_position + Vector2(0, -8), player.facing, Items.extras(stack))
	return true


## Merges equal stacks in the rucksack (not the hotbar) and sorts it: tools, gear, food, materials; rarer first, then by name.
func _sort() -> bool:
	return _sort_slots(slots, HOTBAR_SIZE, SIZE)


## The same for the open container (R / "Sortieren" in a box window).
func _sort_box() -> bool:
	return box != null and _sort_slots(box.slots, 0, box.size())


## "Alles nehmen": every stack of the open container goes into the bag as far as it fits.
func _take_all() -> bool:
	if box == null:
		return false
	var moved: bool = false
	for i: int in box.size():
		var current: Dictionary = box.slots[i]
		if current.is_empty():
			continue
		var left: int = add_item(String(current["id"]), int(current["count"]), Items.extras(current))
		if left < int(current["count"]):
			moved = true
		if left <= 0:
			box.slots[i] = {}
		else:
			current["count"] = left
	return moved


func _sort_slots(target: Array, from: int, to: int) -> bool:
	var stacks: Array[Dictionary] = []
	for i: int in range(from, to):
		var stack: Dictionary = (target[i] as Dictionary).duplicate()
		for other: Dictionary in stacks:
			if not stack.is_empty() and String(other["id"]) == String(stack["id"]) and Items.extras(other) == Items.extras(stack) and int(other["count"]) < Items.max_stack(other):
				var room: int = mini(Items.max_stack(other) - int(other["count"]), int(stack["count"]))
				other["count"] = int(other["count"]) + room
				stack["count"] = int(stack["count"]) - room
		if not stack.is_empty() and int(stack["count"]) > 0:
			stacks.append(stack)
	var rarities: Array = DataRegistry.table("rarities").keys()
	var order: Array[String] = ["tool", "weapon", "armor", "consumable", "material"]
	stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: Dictionary = Items.definition(a)
		var db: Dictionary = Items.definition(b)
		var ka: int = order.find(String(da.get("kind", "")))
		var kb: int = order.find(String(db.get("kind", "")))
		ka = ka if ka >= 0 else order.size()
		kb = kb if kb >= 0 else order.size()
		if ka != kb:
			return ka < kb
		var ra: int = rarities.find(String(da.get("rarity", "common")))
		var rb: int = rarities.find(String(db.get("rarity", "common")))
		if ra != rb:
			return ra > rb
		return String(da.get("name", a["id"])) < String(db.get("name", b["id"])))
	for i: int in range(from, to):
		target[i] = stacks[i - from] if i - from < stacks.size() else {}
	return true


## The cursor stack goes back into the bag (what does not fit is thrown out). Host.
func _stow() -> bool:
	if held.is_empty():
		return false
	var left: int = add_item(String(held["id"]), int(held["count"]), Items.extras(held))
	if left > 0:
		_throw(held, left)
	held = {}
	return true


## Host: puts the cursor stack away and tells the owner (the window closing, a save).
func stow_held() -> void:
	if multiplayer.is_server() and _stow():
		_commit()


func _move(from: int, to: int) -> bool:
	if from == to or not _valid(from) or not _valid(to):
		return false
	var a: Dictionary = slots[from]
	var b: Dictionary = slots[to]
	if a.is_empty() or not _fits(to, a) or not _fits(from, b):
		return false
	if not b.is_empty() and a["id"] == b["id"] and Items.extras(a) == Items.extras(b) and Items.max_stack(a) > 1: ## merge stacks
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
	if not equipment.has(slot_name) or not slot_open(slot_name) or not Items.fits_slot(slot_name, stack) or TalismanRules.conflict(equipment, slot_name, stack) != "":
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
	if not other.is_empty() and (not Items.fits_slot(slot_name, other) or TalismanRules.conflict(equipment, slot_name, other) != ""):
		return false
	equipment[slot_name] = other
	slots[to] = stack
	return true


## First free matching equipment slot, else the first matching one (which gets swapped). A piece of jewellery goes where the same kind is worn already
## (it replaces it), whether or not another talisman slot is free.
func _slot_for(stack: Dictionary) -> String:
	var same: String = TalismanRules.conflict(equipment, "", stack)
	if same != "" and slot_open(same) and Items.fits_slot(same, stack):
		return same
	var fallback: String = ""
	for slot_name: String in equipment:
		if slot_open(slot_name) and Items.fits_slot(slot_name, stack):
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
	held = state.get("held", {})
	changed.emit()
