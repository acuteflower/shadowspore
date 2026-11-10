class_name FarmRules
extends RefCounted
## The pure rules of farming (docs/farming.md): crops, the growth of a bed overnight, what a tool does to a cell. No nodes, so the host, the views and the tests ask the
## same functions. Data: data/farming.json (crops, seeds the wild gives), the cell grid is the town's 16 px ground tile.
##
## A cell of a field is a Dictionary (absent = rough ground):
##   t 1        hoed (a bed)                      w day+1  watered on that day (dark soil; the sun dries it at the next sunrise)
##   c crop id  planted                           a stage  0 sprout .. `ripe_stage` (ripe)       p watered days spent in this stage
##   m missed   nights the crop was not watered   u day    last day somebody worked it (an empty bed goes back to rough ground after `fallow_days`)

const CELL: int = 16
const STAGES: int = 4 ## pictures per crop: sprout, young, grown, ripe


static func config() -> Dictionary:
	return DataRegistry.table("farming")


static func crops() -> Dictionary:
	return config().get("crops", {}) as Dictionary


static func crop(id: String) -> Dictionary:
	return crops().get(id, {}) as Dictionary


## The crop a seed item plants ("" when the item is no seed).
static func crop_for_seed(item: String) -> String:
	if item == "":
		return ""
	var all: Dictionary = crops()
	for id: String in all:
		if String((all[id] as Dictionary).get("seed", "")) == item:
			return id
	return ""


## The stage at which a crop can be harvested (3 for a crop with three growth steps).
static func ripe_stage(crop_id: String) -> int:
	return (crop(crop_id).get("grow", []) as Array).size()


static func fallow_days() -> int:
	return int(config().get("fallow_days", 3))


## The tool a cell wants next: "hoe" (rough ground), "can" (a crop that has not drunk today) or "" (nothing a tool could do now: the cursor stays a cursor).
static func tool_wanted(cell: Dictionary, day: int) -> String:
	if not bool(cell.get("t", 0)):
		return "hoe"
	if String(cell.get("c", "")) == "" or is_ripe(cell):
		return ""
	return "can" if int(cell.get("w", 0)) != day + 1 else ""


static func is_ripe(cell: Dictionary) -> bool:
	var id: String = String(cell.get("c", ""))
	return id != "" and int(cell.get("a", 0)) >= ripe_stage(id)


static func is_wet(cell: Dictionary, day: int) -> bool:
	return bool(cell.get("t", 0)) and int(cell.get("w", 0)) == day + 1


## What a tool does to a cell on `day`: the next cell (the same when nothing changes) and the effect for sound and dust ("till", "water", "scrape", "").
static func apply_tool(cell: Dictionary, tool: String, day: int) -> Dictionary:
	var next: Dictionary = cell.duplicate()
	var fx: String = ""
	if tool == "hoe":
		if not bool(cell.get("t", 0)):
			next["t"] = 1
			next["u"] = day
			fx = "till"
		elif String(cell.get("c", "")) == "":
			next["u"] = day ## raked over again: stays a bed a little longer
			fx = "scrape"
	elif tool == "can":
		if bool(cell.get("t", 0)) and int(cell.get("w", 0)) != day + 1:
			next["w"] = day + 1
			next["u"] = day
			fx = "water"
	return {"cell": next, "fx": fx}


## Can this seed go into this cell? "" = yes, otherwise a short reason.
static func plant_block(cell: Dictionary, seed_item: String) -> String:
	if crop_for_seed(seed_item) == "":
		return "KEIN SAMEN"
	if not bool(cell.get("t", 0)):
		return "ERST HACKEN"
	if String(cell.get("c", "")) != "":
		return "SCHON BEPFLANZT"
	return ""


static func plant(cell: Dictionary, seed_item: String, day: int) -> Dictionary:
	var next: Dictionary = cell.duplicate()
	next["c"] = crop_for_seed(seed_item)
	next["a"] = 0
	next["p"] = 0
	next["m"] = 0
	next["u"] = day
	return next


## The morning of `day`: one night of growth for the cell. `rained` = it was a wet day yesterday (the rain watered everything). Returns the new cell (empty = rough ground again).
static func sunrise(cell: Dictionary, day: int, rained: bool) -> Dictionary:
	var next: Dictionary = cell.duplicate()
	var watered: bool = rained or int(cell.get("w", 0)) == day ## `w` holds the day it was watered + 1: watered yesterday means w == today
	next.erase("w")
	var id: String = String(next.get("c", ""))
	if id == "":
		if bool(next.get("t", 0)) and day - int(next.get("u", day)) >= fallow_days():
			return {} ## unused beds grow over again
		return next
	var grow: Array = crop(id).get("grow", []) as Array
	var stage: int = int(next.get("a", 0))
	if stage >= grow.size():
		return next ## ripe crops wait to be picked
	if watered:
		next["p"] = int(next.get("p", 0)) + 1
		if int(next.p) >= int(grow[stage]):
			next["a"] = stage + 1
			next["p"] = 0
	else:
		next["m"] = int(next.get("m", 0)) + 1
	return next


## The harvest of a ripe cell: {"cell": what is left (empty bed, or a crop that grows back), "drops": [{id, chance, min, max}], "fx"}. `roll` is a random number 0..1.
static func harvest(cell: Dictionary, roll: float, day: int) -> Dictionary:
	var id: String = String(cell.get("c", ""))
	if not is_ripe(cell):
		return {"cell": cell, "drops": [], "fx": ""}
	var spec: Dictionary = crop(id)
	var yield_spec: Dictionary = spec.get("yield", {}) as Dictionary
	var drops: Array = []
	var bonus: int = int(config().get("ripe_bonus", 1)) if int(cell.get("m", 0)) == 0 else 0 ## looked after every single night: one more
	drops.append({"id": String(yield_spec.get("item", "")), "chance": 1.0, "min": int(yield_spec.get("min", 1)) + bonus, "max": int(yield_spec.get("max", 1)) + bonus})
	var back: Dictionary = spec.get("seed_back", {}) as Dictionary
	if not back.is_empty() and roll < float(back.get("chance", 0.0)):
		drops.append({"id": String(spec.get("seed", "")), "chance": 1.0, "min": int(back.get("min", 1)), "max": int(back.get("max", 1))})
	var next: Dictionary = cell.duplicate()
	if spec.has("regrow"):
		next["a"] = int(spec.regrow) ## picks again in a few days
		next["p"] = 0
		next["m"] = 0
	else:
		next.erase("c")
		next.erase("a")
		next.erase("p")
		next.erase("m")
	next["u"] = day
	return {"cell": next, "drops": drops, "fx": "harvest"}


## A seed the wild plant of `kind` may give when it is picked (`wild_seeds` in the data): {id, chance} or empty.
static func wild_seed(kind: String) -> Dictionary:
	var entry: Dictionary = (config().get("wild_seeds", {}) as Dictionary).get(kind, {}) as Dictionary
	if entry.is_empty():
		return {}
	return {"id": String(entry.seed), "chance": float(entry.get("chance", 0.0))}


## Cell index in a field of `cols` x `rows` cells -> (cx, cy), and back.
static func cell_index(cx: int, cy: int, cols: int) -> int:
	return cy * cols + cx


static func cell_coords(index: int, cols: int) -> Vector2i:
	return Vector2i(index % cols, floori(float(index) / float(cols)))
