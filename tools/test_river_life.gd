extends Node
var failures: int = 0
var checks: int = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var rivers: WorldRivers = WorldRivers.new()
	add_child(rivers)
	var data: Dictionary = DataRegistry.table("rivers_baked")
	var seen: Dictionary = {}
	var jellies_total: int = 0
	for key: String in data["chunks"]:
		var cell: Vector2i = Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
		var details: RiverDetails = RiverDetails.new()
		add_child(details)
		details.setup(rivers, cell)
		var bank_count: int = 0
		for kind_row: int in range(10, 19): bank_count += details._rows.count(kind_row)
		var water_count: int = details._rows.count(20) + details._rows.count(21) + details._rows.count(22)
		check(water_count <= 18, "Water-plant cap exceeded")
		jellies_total += details._jellies.size()
		check(details._jellies.size() <= 7, "Too many jellies")
		for jelly: Dictionary in details._jellies: check(details._jelly_ok(jelly["pos"]), "Jelly outside the deep water")
		check(details._sprites.size() - bank_count - water_count <= 18, "Details exceeded density cap")
		check(bank_count <= 52, "Bank props exceeded density cap")
		for i: int in details._sprites.size():
			var row: int = details._rows[i]
			var at: Vector2 = details._sprites[i].position
			seen[row] = true
			if row >= 20: check(rivers.field_at(at).x < -3.0, "Water plant on the bank or on land")
			elif row in [17, 18]: check(rivers.field_at(at).x < 0.0, "Water plant on dry land")
			elif row >= 10: check(rivers.field_at(at).x >= 1.0, "Bank prop in or at the water")
			elif row in [2, 3]:
				check(rivers.is_deep(at), "Rock obstructs walkable shallow water")
				for ford: Array in data["fords"]:
					check(at.distance_to(Vector2(float(ford[0]), float(ford[1]))) >= 42.0, "Rock closes a ford")
			elif row == 1: check(rivers.field_at(at).x > 0.0, "Reed rooted in deep river")
			else: check(rivers.field_at(at).x < 0.0, "Aquatic plant on dry land")
		var copy: RiverDetails = RiverDetails.new()
		add_child(copy)
		copy.setup(rivers, cell)
		check(copy._rows == details._rows, "Details vary with load order")
		copy.queue_free()
		details.queue_free()
	check(seen.has(0) and seen.has(1) and seen.has(2) and seen.has(4) and seen.has(5), "Missing main detail types")
	for kind: int in [20, 21, 22]: check(seen.has(kind), "Missing water plant kind %d" % kind)
	for kind: int in range(10, 19): check(seen.has(kind), "Missing bank prop kind %d" % kind)
	check(jellies_total > 0, "No jellies anywhere")
	var dry: Dictionary = {"speed": 1.0}
	check(rivers.wade_data(Vector2.ZERO, dry) == dry, "Dry land speed changed")
	var ford: Array = data["fords"][0]
	var at: Vector2 = Vector2(float(ford[0]), float(ford[1]))
	var water: Dictionary = rivers.wade_data(at, {"speed": 0.8, "ripples": true})
	check(float(water["submerge"]) > 1.0 and float(water["submerge"]) <= 6.0, "Wading depth invalid")
	check(float(water["speed"]) >= 0.66 and float(water["speed"]) <= 0.94, "Wading speed invalid")
	var ripples: WaterRipples = WaterRipples.new()
	add_child(ripples)
	for i: int in 40: ripples.add(at, 1.0)
	check(ripples._ages.size() == 24 and ripples._strengths.size() == 24, "Ripple cap failed")
	ripples._process(1.0)
	check(ripples._positions.is_empty() and ripples._strengths.is_empty(), "Ripples did not expire")
	var overlay: WaterOverlay = WaterOverlay.new()
	add_child(overlay)
	overlay.submerge = 5.0
	overlay._process(1.0)
	overlay.submerge = 0.0
	overlay._process(1.0)
	check(overlay._current == 0.0, "Water overlay lingers on shore")
	print("River life: %d checks, %d failures; types %s" % [checks, failures, seen.keys()])
	get_tree().quit(0 if failures == 0 else 1)
