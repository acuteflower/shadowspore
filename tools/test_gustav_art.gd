extends Node
## Godot --headless --path . res://tools/test_gustav_art.tscn
var failures: int = 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		failures += 1
		push_error(what)

func _ready() -> void:
	var rig: Dictionary = DataRegistry.table("gustav_rig")
	check(not rig.is_empty() and int(rig.get("rows", 0)) == 8, "Gustav has eight true directions")
	var sheet: Texture2D = load("res://assets/characters/gustav.png") as Texture2D
	var portrait: Texture2D = load("res://assets/ui/portrait_gustav.png") as Texture2D
	check(sheet != null and sheet.get_size() == Vector2(72 * int(rig.frames), 76 * 8), "sprite atlas matches its rig")
	check(DialogueArt.valid_portrait(portrait), "dialogue portrait matches the existing art contract")
	var town: TownManager = TownManager.new()
	add_child(town)
	var settler: Settler = Settler.new()
	add_child(settler)
	settler.setup(town, "gustav", false)
	check(settler._sprite != null and settler._rig == rig, "the existing settler loads Gustav instead of the placeholder")
	for sector: int in 8:
		for clip_name: String in ["idle", "walk", "run", "work"]:
			settler._sector = sector
			settler._clip = clip_name
			settler._clip_time = 0.0
			settler._show()
			var clip: Dictionary = (rig.clips as Dictionary)[clip_name]
			check(settler._sprite.frame == sector * int(rig.frames) + int(clip.start) and not settler._sprite.flip_h, "%s uses independent direction %d" % [clip_name, sector])
	check(int((rig.clips as Dictionary).work.strike) == 3, "hammer strike matches the work sound")
	settler.queue_free()
	print("GUSTAV ART: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
