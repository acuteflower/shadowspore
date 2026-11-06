extends Node
## Godot --headless --path . res://tools/test_maren_art.tscn
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func _ready() -> void:
	var rig: Dictionary = DataRegistry.table("maren_rig")
	check(int(rig.get("rows", 0)) == 8, "eight real directions")
	var sheet: Texture2D = load("res://assets/characters/maren.png") as Texture2D
	var portrait: Texture2D = load("res://assets/ui/portrait_maren.png") as Texture2D
	check(sheet != null and sheet.get_size() == Vector2(72 * int(rig.frames), 76 * 8), "atlas dimensions match rig")
	check(DialogueArt.valid_portrait(portrait), "portrait matches NPC dialogue contract")
	var town: TownManager = TownManager.new()
	add_child(town)
	var spec: Dictionary = town.settler_spec("maren")
	check(not bool(spec.get("enabled", true)) and String(spec.art) == "maren", "future river settler is registered but disabled")
	var figure: Settler = Settler.new()
	add_child(figure)
	figure.setup(town, "maren", false)
	figure.set_process(false)
	check(figure._sprite != null and figure._rig == rig, "actual Settler loads Maren's atlas and rig")
	for sector: int in 8:
		for clip_name: String in ["idle", "walk", "run", "work"]:
			figure._sector = sector
			figure._clip = clip_name
			figure._clip_time = 0.0
			figure._show()
			var clip: Dictionary = (rig.clips as Dictionary)[clip_name]
			check(figure._sprite.frame == sector * int(rig.frames) + int(clip.start) and not figure._sprite.flip_h, "%s direction %d" % [clip_name, sector])
	figure._clip = "work"
	var children_before: int = figure.get_child_count()
	figure._work_sound(5.0, (spec.spots as Dictionary).work as Dictionary)
	check(figure.get_child_count() == children_before, "net mending never plays a hammer sound")
	figure._work_sound(1.0, {})
	check(figure.get_child_count() == children_before + 1, "legacy work still defaults to hammering")
	for child: Node in figure.get_children():
		if child is AudioStreamPlayer2D:
			child.free()
	town.residents["gustav"] = {"trust": 0, "talked": -1}
	town.residents["valdric"] = {"trust": 0, "talked": -1}
	town.structures[99] = {"p": "pier_wood", "x": 0.0, "y": 0.0, "f": 0, "g": 1000}
	town._check_arrivals(100.0)
	check(not town.residents.has("maren"), "disabled arrival cannot trigger even with a pier")
	check(DialogueBox.LATE_PORTRAITS.get("MAREN", "") == "res://assets/ui/portrait_maren.png", "dialogue can look up her portrait")
	figure.queue_free()
	town.queue_free()
	print("MAREN ART: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
