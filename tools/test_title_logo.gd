extends Node
## Title logo: layers, layout, the pure functions of its clock (eye, lamp, glint, glitch, wind), pause and time-scale independence.
## `Godot --headless --path . tools/test_title_logo.tscn`
var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var layout: Dictionary = DataRegistry.table("title_logo_layout")
	var cfg: Dictionary = DataRegistry.table("title")
	check(not layout.is_empty() and not cfg.is_empty(), "layout and tuning tables are loaded")
	var size_a: Array = layout["size"] as Array
	var frames: int = int(layout["frames"])
	var orb_frame: int = int(layout["orb_frame"])

	var logo: TitleLogo = TitleLogo.new()
	add_child(logo)
	await get_tree().process_frame
	check(logo.size == Vector2(float(size_a[0]), float(size_a[1])), "logo is 440 x 240")
	check(logo.process_mode == Node.PROCESS_MODE_ALWAYS, "logo keeps running while the game is paused")

	for file: String in ["title_base", "title_plants", "title_plants_sway", "title_glow", "title_glow_map", "title_halo_void", "title_halo_life", "title_halo_lamp"]:
		var tex: Texture2D = load("res://assets/ui/logo/%s.png" % file) as Texture2D
		check(tex != null and tex.get_width() == int(size_a[0]) and tex.get_height() == int(size_a[1]), "%s.png is a full layer" % file)
	for file: String in ["title_orb_void", "title_orb_life"]:
		var tex: Texture2D = load("res://assets/ui/logo/%s.png" % file) as Texture2D
		check(tex != null and tex.get_width() == frames * orb_frame and tex.get_height() == orb_frame, "%s.png holds %d frames" % [file, frames])
	for shader: String in ["title_base", "title_plants", "title_glow", "title_halo"]:
		check(load("res://assets/shaders/%s.gdshader" % shader) is Shader, "%s shader loads" % shader)

	var orbs: Dictionary = layout["orbs"] as Dictionary
	for key: String in ["void", "life"]:
		var o: Dictionary = orbs[key] as Dictionary
		var c: Array = o["center"] as Array
		var r: Array = o["radius"] as Array
		check(float(c[0]) - float(r[0]) > 0.0 and float(c[0]) + float(r[0]) < float(size_a[0]) and float(c[1]) - float(r[1]) > 0.0 and float(c[1]) + float(r[1]) < float(size_a[1]), "%s orb lies inside the logo" % key)
		check(float(r[0]) <= float(orb_frame) / 2.0 and float(r[1]) <= float(orb_frame) / 2.0, "%s orb fits its frame" % key)
	check((layout["drip_columns"] as Array).size() > 0 and (layout["spore_sources"] as Array).size() > 0 and (layout["void_sources"] as Array).size() > 0, "particle sources exist")

	# the sway map: rooted and moving pixels both exist
	var sway: Image = (load("res://assets/ui/logo/title_plants_sway.png") as Texture2D).get_image()
	var plants_img: Image = (load("res://assets/ui/logo/title_plants.png") as Texture2D).get_image()
	var moving: int = 0
	var rooted: int = 0
	for y: int in sway.get_height():
		for x: int in sway.get_width():
			if sway.get_pixel(x, y).r > 0.0:
				moving += 1
			elif plants_img.get_pixel(x, y).a > 0.0:
				rooted += 1
	check(moving > 500, "plants have swaying pixels (%d)" % moving)
	check(rooted > 20 and rooted < moving, "plants have a rooted collar and roots (%d)" % rooted)

	# the clock is frozen by set_time and the functions are deterministic
	logo.set_time(12.345)
	check(is_equal_approx(logo.clock(), 12.345), "set_time freezes the clock")
	check(logo.eye_frame_at(7.7) == logo.eye_frame_at(7.7) and logo.glitch_at(21.0) == logo.glitch_at(21.0), "pure functions are deterministic")

	# eye: calm sequence frames, glitch frames now and then, never an invalid frame
	var seq: Array[int] = []
	var gfr: Array[int] = []
	for v: Variant in (cfg["eye"] as Dictionary)["sequence"] as Array:
		seq.append(int(v))
	for v: Variant in (cfg["eye"] as Dictionary)["glitch_frames"] as Array:
		gfr.append(int(v))
	var seen_glitch: int = 0
	var seen_calm: Dictionary = {}
	var bad_eye: int = 0
	var t: float = 0.0
	while t < 120.0:
		var f: int = logo.eye_frame_at(t)
		if f < 0 or f >= frames:
			bad_eye += 1
		if gfr.has(f) and not seq.has(f):
			seen_glitch += 1
		if seq.has(f):
			seen_calm[f] = true
		t += 0.02
	check(bad_eye == 0, "eye frame always valid")
	check(seen_glitch > 0 and seen_glitch < 400, "the eye glitches now and then but mostly stays calm (%d samples)" % seen_glitch)
	check(seen_calm.size() >= 4, "the calm eye sequence visits several frames")

	# lamp: every frame is used, about 7 per second
	var lamp_seen: Dictionary = {}
	var lamp_bad: int = 0
	t = 0.0
	while t < 3.0:
		var f: int = logo.lamp_frame_at(t)
		if f < 0 or f >= frames:
			lamp_bad += 1
		lamp_seen[f] = true
		t += 0.01
	check(lamp_bad == 0 and lamp_seen.size() == frames, "the lamp cycles through all %d frames" % frames)

	# glint and glitch happen, are short and stay on the picture
	var glint_on: int = 0
	var glitch_on: int = 0
	var glitch_ok: bool = true
	var seam: float = float((layout["seam_y"] as Array)[0])
	var top: float = float((layout["origin_of_word"] as Array)[1])
	t = 0.0
	while t < 120.0:
		if logo.glint_at(t) > -500.0:
			glint_on += 1
		var g: Vector3 = logo.glitch_at(t)
		if g.y > 0.0:
			glitch_on += 1
			glitch_ok = glitch_ok and g.x >= top and g.x + g.y <= seam and absf(g.z) >= 1.0 and absf(g.z) <= 3.0
		t += 0.01
	check(glint_on > 100 and glint_on < 4000, "a glint passes now and then (%d steps)" % glint_on)
	check(glitch_on > 20 and glitch_on < 1500, "SHADOW glitches now and then (%d steps)" % glitch_on)
	check(glitch_ok, "glitch rows stay inside the SHADOW word")

	# wind and heartbeat stay in range, the beat has a quiet part
	var wmin: float = 99.0
	var wmax: float = -99.0
	var bmin: float = 99.0
	var bmax: float = -99.0
	t = 0.0
	while t < 60.0:
		wmin = minf(wmin, logo.wind_at(t))
		wmax = maxf(wmax, logo.wind_at(t))
		bmin = minf(bmin, TitleLogo.beat(t))
		bmax = maxf(bmax, TitleLogo.beat(t))
		t += 0.01
	check(wmin > -1.5 and wmax < 1.5 and wmax - wmin > 0.5, "wind breathes within bounds (%.2f .. %.2f)" % [wmin, wmax])
	check(bmax > 0.95 and bmin < 0.05, "heartbeat has beats and rests")

	# the time-driven parts change the node: eye frame and lamp frame follow set_time
	logo.set_time(0.0)
	var eye0: int = (logo.get_child(0) as Sprite2D).frame
	var life0: int = (logo.get_child(1) as Sprite2D).frame
	logo.set_time(0.6 * 3.0 + 0.01)
	var eye1: int = (logo.get_child(0) as Sprite2D).frame
	logo.set_time(0.5)
	var life1: int = (logo.get_child(1) as Sprite2D).frame
	check(eye0 != eye1 and life0 != life1, "eye and lamp frames follow the clock")

	# real time: runs while the game is paused and with a slowed time scale
	logo.release_time()
	var c0: float = logo.clock()
	get_tree().paused = true
	Engine.time_scale = 0.1
	var start_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < 400:
		await get_tree().process_frame
	var c1: float = logo.clock()
	get_tree().paused = false
	Engine.time_scale = 1.0
	check(c1 - c0 > 0.3 and c1 - c0 < 0.9, "clock runs in real time while paused and slowed (%.2f s)" % (c1 - c0))

	# ---- the build-up
	var order: Image = (load("res://assets/ui/logo/title_order.png") as Texture2D).get_image()
	var base_img: Image = (load("res://assets/ui/logo/title_base.png") as Texture2D).get_image()
	var seam_y: int = int((layout["seam_y"] as Array)[0])
	var sum_top: float = 0.0
	var n_top: int = 0
	var sum_bottom: float = 0.0
	var n_bottom: int = 0
	var r_min: float = 1.0
	var r_max: float = 0.0
	for y: int in base_img.get_height():
		for x: int in base_img.get_width():
			if base_img.get_pixel(x, y).a > 0.0:
				var r: float = order.get_pixel(x, y).r
				r_min = minf(r_min, r)
				r_max = maxf(r_max, r)
				if y < seam_y - 6:
					sum_top += r
					n_top += 1
				elif y > seam_y + 12:
					sum_bottom += r
					n_bottom += 1
	check(r_min < 0.02 and r_max > 0.98, "every letter pixel has an arrival time spanning 0..1")
	check(sum_bottom / float(n_bottom) < sum_top / float(n_top), "SPORE lands before SHADOW")
	check(order.get_pixel(0, 0).a == 1.0, "order map is fully opaque (the importer never touches its values)")

	var total: float = logo.build_total()
	var p0: Dictionary = logo.build_params(0.3)
	check(p0["build_on"] == 1.0 and float(p0["build_t"]) < 0.0 and float(p0["crack_reach"]) < 0.0 and float(p0["spore"]) > 0.0 and not bool(p0["void_on"]), "at the start only the spore beats")
	var prev_reach: float = -2.0
	var prev_t: float = -2.0
	var prev_grow: float = -2.0
	var prev_front: float = -20.0
	var mono: bool = true
	var in_range: bool = true
	t = 0.0
	while t < total + 0.5:
		var bp: Dictionary = logo.build_params(t)
		if t < total:
			mono = mono and float(bp["crack_reach"]) >= prev_reach and float(bp["build_t"]) >= prev_t and float(bp["grow"]) >= prev_grow and float(bp["front"]) >= prev_front
			prev_reach = float(bp["crack_reach"])
			prev_t = float(bp["build_t"])
			prev_grow = float(bp["grow"])
			prev_front = float(bp["front"])
		in_range = in_range and float(bp["blueprint"]) <= 0.91 and float(bp["flash"]) <= 1.0 and float(bp["idle"]) >= 0.0 and float(bp["idle"]) <= 1.0 and float(bp["void_halo"]) <= 1.0 and float(bp["life_halo"]) <= 1.0
		t += 0.01
	check(mono, "crack, letters, plants and the light front only move forward")
	check(in_range, "build values stay in range")
	var end: Dictionary = logo.build_params(total + 0.01)
	check(bool(end["done"]) and end["build_on"] == 0.0 and end["grow"] == 2.0 and bool(end["void_on"]) and bool(end["life_on"]) and end["idle"] == 1.0, "after the build everything is the finished logo")
	check(float(logo.build_params(5.0)["build_t"]) > 1.0 and not bool(logo.build_params(4.0)["life_on"]) and bool(logo.build_params(5.5)["life_on"]), "letters are all down before the O's ignite")

	var hits: Array[int] = [0, 0]
	logo.impact.connect(func() -> void: hits[0] += 1)
	logo.built.connect(func() -> void: hits[1] += 1)
	logo.set_time(10.0)
	logo.play_build()
	check(logo.is_building() and is_equal_approx(logo.build_time(), 0.0), "play_build starts at zero")
	logo.set_time(10.0 + 4.6)
	check(hits[0] == 1 and hits[1] == 0 and logo.is_building(), "the blow fires once during the build")
	logo.set_time(10.0 + 5.0)
	check(hits[0] == 1, "the blow does not fire twice")
	logo.set_time(10.0 + total + 0.1)
	check(hits[1] == 1 and not logo.is_building(), "built fires at the end")
	logo.play_build()
	logo.set_time(10.0 + total + 1.0)
	logo.skip_build()
	check(hits[1] == 2 and not logo.is_building(), "skip_build ends the build-up at once")
	logo.set_time(10.0 + total + 5.0)
	check(hits[1] == 2, "skip_build only fires once")

	logo.queue_free()
	print("RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
