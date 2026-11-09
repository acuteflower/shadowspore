extends Node
## Godot --headless --path . res://tools/test_torben_art.tscn
## Torben's atlas (tools/art_torben.py): eight true directions, every clip inside the sheet, a glow sheet of the same size that only holds forging heat, and the settler loads him.
var failures: int = 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		failures += 1
		push_error(what)

func _ready() -> void:
	var rig: Dictionary = DataRegistry.table("torben_rig")
	check(not rig.is_empty() and int(rig.get("rows", 0)) == 8, "Torben has eight true directions")
	var frame: Array = rig.frame as Array
	var sheet: Texture2D = load("res://assets/characters/torben.png") as Texture2D
	var glow: Texture2D = load("res://assets/characters/torben_glow.png") as Texture2D
	check(sheet != null and sheet.get_size() == Vector2(int(frame[0]) * int(rig.frames), int(frame[1]) * 8), "sprite atlas matches its rig")
	check(glow != null and glow.get_size() == sheet.get_size(), "glow sheet has the same layout as the atlas")
	var clips: Dictionary = rig.clips as Dictionary
	var next: int = 0
	var inside: bool = true
	for name: String in clips:
		var clip: Dictionary = clips[name] as Dictionary
		if int(clip.start) != next:
			inside = false
		next = int(clip.start) + int(clip.count)
	check(inside and next == int(rig.frames), "the clips tile the sheet without gaps (%d frames)" % next)
	for name: String in ["idle", "walk", "run", "work", "stand", "sit", "sit_down", "bellows", "quench", "sledge", "lift", "carry", "set_down", "shove", "grab_armor", "nod", "snort", "swat"]:
		check(clips.has(name), "clip %s exists" % name)
	check(int((clips.work as Dictionary).strike) == 4 and int((clips.sledge as Dictionary).strike) == 4, "the blows land on frame 4")
	var image: Image = glow.get_image()
	var lit: int = 0
	var odd: int = 0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var c: Color = image.get_pixel(x, y)
			if c.a > 0.9:
				lit += 1
				if c.r < 0.35 or c.b > 0.7:
					odd += 1 ## the heat ramp is red-orange-yellow, never dark or blue
	check(lit > 20 and odd == 0, "the glow sheet holds only forging heat (%d sampled pixels)" % lit)
	var town: TownManager = TownManager.new()
	add_child(town)
	var settler: Settler = Settler.new()
	add_child(settler)
	settler.setup(town, "torben", false)
	check(settler._sprite != null and settler._rig == rig, "the settler loads Torben instead of the placeholder")
	check(settler._glow != null, "the settler draws his glow sheet")
	for sector: int in 8:
		for clip_name: String in ["idle", "walk", "work", "sit"]:
			settler._sector = sector
			settler._clip = clip_name
			settler._clip_time = 0.0
			settler._show()
			var clip: Dictionary = clips[clip_name] as Dictionary
			check(settler._sprite.frame == sector * int(rig.frames) + int(clip.start) and not settler._sprite.flip_h, "%s uses independent direction %d" % [clip_name, sector])
	settler.queue_free()
	print("TORBEN ART: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
