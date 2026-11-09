extends Node
## Godot --headless --path . res://tools/test_smithy.tscn
## The smithy (tools/art_smithy.py, data/town.json "smithy"): picture, animated glow strip, parts, wear overlays and spill exist and match their data; the piece waits for Torben;
## its cost items exist; Torben's spots point at things that are on the picture.
var failures: int = 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		failures += 1
		push_error(what)

func tex(name: String) -> Texture2D:
	return load("res://assets/town/%s.png" % name) as Texture2D

func _ready() -> void:
	var spec: Dictionary = TownRules.piece("smithy")
	check(not spec.is_empty(), "town.json has the smithy")
	check(String(spec.get("needs_resident", "")) == "torben", "it waits for Torben")
	check(String(spec.get("category", "")) == "craft", "it is in the craft category")
	var frame: Array = spec.frame as Array
	var base: Texture2D = tex("smithy")
	check(base != null and base.get_size() == Vector2(float(frame[0]), float(frame[1])), "the picture matches its frame")
	var anim: Dictionary = spec.anim as Dictionary
	var glow: Texture2D = tex("smithy_glow")
	check(glow != null and glow.get_size() == Vector2(float(frame[0]) * float(anim.frames), float(frame[1])), "the glow is a strip of %d frames" % int(anim.frames))
	check(tex("smithy_pad") != null and tex("smithy_spill") != null, "pad and spill pictures exist")
	check(tex("smithy_spill").get_size() == base.get_size(), "the spill has the picture's size")
	for part: Variant in spec.parts as Array:
		var p: Dictionary = part as Dictionary
		var t: Texture2D = tex(String(p.texture))
		check(t != null and t.get_size() == Vector2(float((p.frame as Array)[0]), float((p.frame as Array)[1])), "part %s matches its frame" % String(p.texture))
		var at: Array = p.at as Array
		check(float(at[0]) >= 0.0 and float(at[1]) >= 0.0 and float(at[0]) + t.get_size().x <= float(frame[0]) and float(at[1]) + t.get_size().y <= float(frame[1]), "part %s lies inside the frame" % String(p.texture))
		if p.has("glow"):
			check(tex("%s_glow" % String(p.texture)) != null, "part %s has its glow sheet" % String(p.texture))
	for w: Variant in spec.wear as Array:
		var t2: Texture2D = tex(String((w as Dictionary).texture))
		check(t2 != null and t2.get_size() == base.get_size(), "wear %s has the picture's size" % String((w as Dictionary).texture))
	for item: String in (spec.cost as Dictionary):
		check(not DataRegistry.get_entry("items", item).is_empty(), "cost item %s exists" % item)
	check(float((spec.foot as Array)[0]) > float((TownRules.piece("workshop").foot as Array)[0]), "the smithy is broader than the workshop")
	var settlers: Dictionary = DataRegistry.table("settlers")
	var torben: Dictionary = settlers.get("torben", {}) as Dictionary
	check(String(torben.get("home", "")) == "smithy" and not bool(torben.get("enabled", true)), "Torben lives in the smithy and is not enabled yet")
	for name: String in ["work", "bellows", "quench", "watch", "rest"]:
		var at2: Array = ((torben.spots as Dictionary)[name] as Dictionary).at as Array
		var in_x: bool = absf(float(at2[0])) <= float(frame[0]) * 0.5
		check(in_x, "spot %s is within the smithy's width" % name)
	var rig: Dictionary = DataRegistry.table("torben_rig")
	var clips: Dictionary = rig.clips as Dictionary
	for name: String in ["work", "bellows", "quench", "stand"]:
		check(clips.has(name), "Torben has the clip %s for his spot" % name)
	print("SMITHY: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
