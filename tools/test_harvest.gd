extends Node
## Regression for the sickle on clover fields, the axe on fallen logs (data/harvest.json) and the pixel test the cursor uses
## to find pickable things and animals (PixelPick). The world's host decisions (drops, replication) are covered by the network tests.
## Run: Godot --headless --path . tools/test_harvest.tscn
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		failures += 1


func _run() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7

	# ---- clover: cut with the sickle, hidden until it grows back
	var field: CloverField = CloverField.new()
	add_child(field)
	field.setup(CloverField.plan(rng), Vector2(160, 240))
	check(field.key == "c:160,240", "a clover field is keyed by its centre")
	check(String(field.spec().get("tool", "")) == "sickle", "clover is harvested with the sickle")
	check(not field.is_depleted() and field.visible, "a fresh clover field stands")
	var field_box: HarvestHurtbox = field.get_node("Harvest") as HarvestHurtbox
	check(field_box.collision_layer == CloverField.HARVEST_LAYER, "a clover field is found by weapons (layer 5)")
	check(field_box.harvest_owner() == field, "the clover hurtbox hands its hits to the field")
	field.apply_harvest({"h": 2}, "hit", Vector2(160, 240))
	check(field.visible and not field.is_depleted(), "a touched clover field stays standing")
	field.apply_harvest({"h": 3, "f": 1}, "strip", Vector2(160, 240))
	check(not field.visible and field.is_depleted(), "a cut clover field is hidden and depleted")
	check(field_box.collision_layer == 0, "a cut clover field cannot be hit any more")
	field.apply_harvest({}, "regrow", Vector2.ZERO)
	check(field.visible and not field.is_depleted(), "a clover field grows back whole")
	check(field_box.collision_layer == CloverField.HARVEST_LAYER, "a regrown clover field can be hit again")

	# ---- clover is cut piece by piece: each blow takes the clumps round one spot
	var piece_field: CloverField = CloverField.new()
	add_child(piece_field)
	piece_field.setup(CloverField.plan(rng), Vector2(400, 240))
	var spot: Vector2 = piece_field.to_local(piece_field.next_cut(piece_field.global_position))
	check(not piece_field.all_cut([spot]) or piece_field.get_child_count() > 0, "one blow does not clear a whole clover field")
	piece_field.apply_harvest({"h": 1, "pts": [spot]}, "hit", Vector2.ZERO)
	check(piece_field.visible and not piece_field.is_depleted(), "a partly cut clover field still stands")
	var next_spot: Vector2 = piece_field.to_local(piece_field.next_cut(piece_field.global_position))
	check(next_spot.distance_to(spot) > CloverField.CUT_RADIUS, "the next blow goes to clumps that are still standing")

	# ---- water plants: the sickle cuts one reed at a time
	var reed: Sprite2D = Sprite2D.new()
	reed.position = Vector2(50, 60)
	add_child(reed)
	var water_cut: WaterPlantCut = WaterPlantCut.new()
	water_cut.setup(reed)
	add_child(water_cut)
	check(water_cut.key == "w:50,60" and String(water_cut.spec().get("tool", "")) == "sickle", "a water plant is keyed by its place and cut with the sickle")
	water_cut.apply_harvest({"h": 2, "f": 1}, "strip", Vector2.ZERO)
	check(not reed.visible and water_cut.is_depleted(), "a cut water plant is gone")
	water_cut.apply_harvest({}, "regrow", Vector2.ZERO)
	check(reed.visible and not water_cut.is_depleted(), "a water plant grows back")

	# ---- fallen log: chopped with the axe, gone for good
	var log_node: FallenLog = FallenLog.new()
	log_node.setup(Vector2(300, 300), 0) ## before it enters the tree, as the world does
	add_child(log_node)
	check(log_node.key == "l:300,300", "a fallen log is keyed by its anchor")
	check(String(log_node.spec().get("tool", "")) == "axe", "fallen logs are chopped with the axe")
	check(not log_node.is_depleted(), "a standing log is not depleted")
	var log_box: HarvestHurtbox = log_node.get_node("Harvest") as HarvestHurtbox
	check(log_box.harvest_owner() == log_node, "the log hurtbox hands its hits to the log")
	log_node.apply_harvest({"h": 1}, "hit", Vector2.ZERO)
	check(not log_node.is_depleted(), "a hit log is still standing")
	log_node.apply_harvest({"h": 3, "f": 1}, "strip", Vector2.ZERO)
	check(log_node.is_depleted(), "a chopped log is depleted")
	check(log_box.collision_layer == 0, "a chopped log cannot be hit any more")

	# ---- PixelPick: a point counts only on a painted pixel of the drawn frame
	var holder: Node2D = Node2D.new()
	add_child(holder)
	holder.position = Vector2(100, 100)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load("res://assets/props/pebbles.png") as Texture2D
	sprite.hframes = 5
	sprite.centered = true
	holder.add_child(sprite)
	var image: Image = sprite.texture.get_image()
	var cell: Vector2 = Vector2(float(image.get_width()) / 5.0, float(image.get_height()))
	var painted: Vector2i = Vector2i(-1, -1)
	for y: int in image.get_height():
		for x: int in int(cell.x):
			if painted.x < 0 and image.get_pixel(x, y).a >= 0.9:
				painted = Vector2i(x, y)
	check(painted.x >= 0, "the pebble picture has painted pixels")
	if painted.x >= 0:
		var at: Vector2 = holder.position + Vector2(painted) - cell * 0.5
		check(PixelPick.hit(holder, at), "a painted pixel of the picture is hit")
		check(not PixelPick.hit(holder, holder.position + Vector2(400, 400)), "far away nothing is hit")
	check(not PixelPick.hit(holder, Vector2(-500, -500)), "points outside the picture are never hit")
	sprite.visible = false
	check(not PixelPick.hit(holder, holder.position), "a hidden picture is not hit")

	print("DONE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
