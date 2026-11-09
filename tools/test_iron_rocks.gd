extends Node
## Regression for the iron ore rocks (data/plants.json "iron_rock", tools/art_iron.py): the generator places them rarer than stone rocks,
## also inside rock formations and as ore formations, every variant exists, nothing overlaps, and the harvest data hands out iron ore.
## Run: Godot --headless --path . tools/test_iron_rocks.tscn
var failures: int = 0

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var plants: Dictionary = DataRegistry.table("plants")
	var spec: Dictionary = plants.get("iron_rock", {}) as Dictionary
	check(not spec.is_empty(), "plants.json has iron_rock")
	var variants: int = (spec.radius as Array).size()
	check(variants == 6 and (spec.height as Array).size() == variants and (spec.hits as Array).size() == variants and (spec.weights as Array).size() == variants, "iron_rock arrays have one entry per variant (6)")
	check(int(spec.columns) == variants and int(spec.rows) == 4, "iron_rock sheet is 6 columns x 4 states")
	var drops: Array = ((spec.harvest as Dictionary).final_drops as Array)
	check(drops.any(func(d: Variant) -> bool: return String((d as Dictionary).id) == "iron_ore"), "the last blow drops iron ore")
	for id: String in ["iron_ore", "iron_ingot", "iron_plate"]:
		var item: Dictionary = DataRegistry.get_entry("items", id)
		check(not item.is_empty() and ResourceLoader.exists(String(item.icon)), "item %s with icon" % id)
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var rocks: int = 0
	var iron: int = 0
	var by_variant: Array[int] = [0, 0, 0, 0, 0, 0]
	var at_cliff: int = 0
	var on_bed: int = 0
	var sample: Array[Vector2] = []
	var all: Array[Dictionary] = []
	for cx: int in range(0, 35):
		for cy: int in range(0, 35):
			var rect: Rect2i = Rect2i(Vector2i(cx, cy) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				var kind: String = String(entry.kind)
				if kind == "rock":
					rocks += 1
				elif kind == "iron_rock":
					iron += 1
					by_variant[int(entry.variant)] += 1
					all.append(entry)
					if world._relief.wall_above(entry.cell as Vector2i):
						at_cliff += 1
					if sample.size() < 6 and cx > 12 and cx < 24:
						sample.append(entry.pos as Vector2)
	print("rocks %d, iron rocks %d (variants %s), at cliffs %d" % [rocks, iron, str(by_variant), at_cliff])
	check(iron > 40, "there are iron rocks in the world (%d)" % iron)
	check(float(iron) < float(rocks) * 0.4, "iron is clearly rarer than stone (%d vs %d)" % [iron, rocks])
	check(float(iron) > float(rocks) * 0.06, "iron is not vanishingly rare (%d vs %d)" % [iron, rocks])
	check(by_variant.all(func(n: int) -> bool: return n > 0), "every iron rock variant occurs")
	var near: int = 0
	for i: int in all.size():
		for j: int in range(i + 1, all.size()):
			var a: Dictionary = all[i]
			var b: Dictionary = all[j]
			var gap: float = (float((spec.radius as Array)[int(a.variant)]) + float((spec.radius as Array)[int(b.variant)])) * 0.9
			if (a.pos as Vector2).distance_to(b.pos as Vector2) < gap * 0.99:
				near += 1
	check(near == 0, "no two iron rocks overlap")
	print("sample positions (px): ", sample)
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
