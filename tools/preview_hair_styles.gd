extends Node2D
## Visual showcase & verification capture for all 6 Ellie hairstyles, night bioluminescence, and SalonWindow icons.
## Usage: godot --path . res://tools/preview_hair_styles.tscn -- --dir=<abs_output_dir>

const STYLES: Array[String] = ["default", "blade_bob", "storm_tail", "moon_knot", "dusk_braids", "night_bun"]
const LABELS: Array[String] = ["Silberwellen", "Klingenbob", "Sturmschweif", "Sternenschleier*", "Dämmerflechten", "Nachtkrone"]
const DYES: Array[String] = ["default", "obsidian", "copper", "default", "blonde", "rose"]


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--base-body="):
			_capture_base_body.call_deferred(arg.trim_prefix("--base-body="))
			return
		if arg.begins_with("--dir="):
			_capture.call_deferred(arg.trim_prefix("--dir="))
			return
	_build_showcase(false)


func _clear_stage() -> void:
	for c: Node in get_children():
		c.queue_free()


func _spawn_dummy(pos: Vector2, sector: int, hair_spec: String, outfit_spec: String = "default", walk_phase: float = -1.0) -> Player:
	var p: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	p.name = str(get_child_count() + 10)
	add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	p.attack.set_process(false)
	p._camera.enabled = false
	p.scale = Vector2(2.0, 2.0)
	p.position = pos
	if p.appearance != null:
		p.appearance.set_outfit(outfit_spec)
		p.appearance.set_hair(hair_spec)
	var dir: Vector2 = Vector2.RIGHT.rotated(float(sector) * PI / 4.0)
	p.facing = dir
	p._sector = sector
	if walk_phase >= 0.0:
		p.velocity = dir * p.sprint_speed
		p.sprinting = true
		p._walk_time = walk_phase
		p._last_step = int(walk_phase)
		p._animate(0.0)
	else:
		p.velocity = Vector2.ZERO
		p.sprinting = false
		p._idle_time = 0.0
		p._animate(0.0)
	p.attack.facing = dir
	p.attack.held_weapon = ""
	p.attack._since_swing = 99.0
	p.attack._weapon_alpha = 0.0
	p.attack._hold_k = 0.0
	p.attack._process(1.0 / 60.0)
	return p


func _build_showcase(night: bool) -> void:
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("0f0b1c") if night else Color("241e34")
	add_child(bg)

	RenderingServer.global_shader_parameter_set("g_day_strength", 0.0 if night else 1.0)
	RenderingServer.global_shader_parameter_set("g_day_clock", 1.2)
	if night:
		var cm: CanvasModulate = CanvasModulate.new()
		cm.color = Color(0.32, 0.34, 0.52, 1.0)
		add_child(cm)

	for i: int in STYLES.size():
		var cx: float = 56.0 + float(i) * 105.0
		var st: String = STYLES[i]
		var dyed_id: String = st if DYES[i] == "default" else ("%s:%s" % [st, DYES[i]])
		# Top row: Front/3-quarter view (S=2 or SE=1)
		_spawn_dummy(Vector2(cx, 138.0), 2, st, "default", -1.0)
		# Bottom row: Back/Sprint motion + dye showcase (N=6 or NW=5)
		_spawn_dummy(Vector2(cx, 302.0), 6 if not night else 5, dyed_id, "midnight" if night else "default", 1.0 if night else -1.0)

		var lbl: Label = Label.new()
		lbl.text = LABELS[i]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.position = Vector2(cx - 42.0, 12.0)
		add_child(lbl)


func _capture(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	NetworkManager.host_singleplayer()
	await get_tree().process_frame

	# 1. Daylight showcase (all 6 styles front + back/dyed)
	_build_showcase(false)
	for _f: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("01_all_styles_day.png"))

	# 2. Night bioluminescence showcase (Sternenschleier & Nachtkrone glowing teal crystals!)
	_clear_stage()
	await get_tree().process_frame
	_build_showcase(true)
	for _f: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("02_night_prism_glow.png"))

	# 3. SalonWindow UI with all 6 bespoke 16x16 hairstyle icons & Sternenschleier focused
	_clear_stage()
	await get_tree().process_frame
	RenderingServer.global_shader_parameter_set("g_day_strength", 1.0)
	var bg_ui: ColorRect = ColorRect.new()
	bg_ui.size = Vector2(640, 360)
	bg_ui.color = Color("1f1930")
	add_child(bg_ui)
	var p_salon: Player = _spawn_dummy(Vector2(150.0, 240.0), 1, "default", "default", -1.0)
	p_salon.scale = Vector2(2.0, 2.0)
	var tm: TownManager = TownManager.new()
	add_child(tm)
	var seat: SalonSeat = SalonSeat.new()
	seat.position = Vector2(150.0, 240.0)
	add_child(seat)
	var win: SalonWindow = SalonWindow.new()
	win.seat = seat
	add_child(win)
	win.setup_board(p_salon, tm)
	for _f: int in 45:
		win._process(0.04)
		await get_tree().process_frame
	for idx: int in win.rows.size():
		if String(win.rows[idx].get("style_id", "")) == "moon_knot":
			win.focus = idx
			break
	for _f: int in 15:
		win._process(0.04)
		await get_tree().process_frame
	win._canvas.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("03_salon_ui_frisuren.png"))

	# 4. Perlenblüte Legendary Qipao Daylight Showcase (8 directions + Sprint BlossomBreeze petals + Dyes!)
	_clear_stage()
	await get_tree().process_frame
	_build_perlenbluete_showcase(false)
	for _f: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("04_perlenbluete_day_petals.png"))

	# 5. Perlenblüte Night Moonlit Silk & Ice-Blossom Lume + Glowing Spring Petals!
	_clear_stage()
	await get_tree().process_frame
	_build_perlenbluete_showcase(true)
	for _f: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("05_perlenbluete_night_lume.png"))

	# 6. SalonWindow OUTFIT Tab showing Perlenblüte (LEGENDÄR · FRÜHJAHR 2027) & live mirror preview!
	_clear_stage()
	await get_tree().process_frame
	RenderingServer.global_shader_parameter_set("g_day_strength", 1.0)
	var bg_ui2: ColorRect = ColorRect.new()
	bg_ui2.size = Vector2(640, 360)
	bg_ui2.color = Color("1f1930")
	add_child(bg_ui2)
	var p_salon2: Player = _spawn_dummy(Vector2(150.0, 240.0), 1, "night_bun:obsidian", "default", -1.0)
	p_salon2.scale = Vector2(2.0, 2.0)
	var tm2: TownManager = TownManager.new()
	add_child(tm2)
	var seat2: SalonSeat = SalonSeat.new()
	seat2.position = Vector2(150.0, 240.0)
	add_child(seat2)
	var win2: SalonWindow = SalonWindow.new()
	win2.seat = seat2
	add_child(win2)
	win2.setup_board(p_salon2, tm2)
	win2._set_tab(1)
	win2.focus = 1
	for _f: int in 45:
		win2._process(0.04)
		p_salon2._animate(0.0)
		p_salon2.attack._process(1.0 / 60.0)
		var bb: BlossomBreeze = p_salon2.get_node_or_null("BlossomBreeze") as BlossomBreeze
		if bb != null:
			bb._process(0.08)
		await get_tree().process_frame
	win2._canvas.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("06_salon_ui_perlenbluete.png"))

	print("Saved in-engine hairstyle & Perlenbluete showcase captures to: ", out_dir)
	get_tree().quit(0)


func _build_perlenbluete_showcase(night: bool) -> void:
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("0e0a1a") if night else Color("241e34")
	add_child(bg)

	TimeManager.time_of_day = 0.0 if night else 0.5
	RenderingServer.global_shader_parameter_set("g_day_strength", 0.0 if night else 1.0)
	RenderingServer.global_shader_parameter_set("g_day_clock", 1.8)
	if night:
		var cm: CanvasModulate = CanvasModulate.new()
		cm.color = Color(0.32, 0.34, 0.52, 1.0)
		add_child(cm)

	# Top row: 6 key turnaround angles (E, SE, S, SW, NW, N) wearing Perlenblüte + Nachtkrone/Sternenschleier + procedural right arm!
	var sectors: Array[int] = [0, 1, 2, 3, 5, 6]
	var top_hairs: Array[String] = ["night_bun:obsidian", "night_bun:obsidian", "default", "moon_knot", "blade_bob:obsidian", "night_bun:obsidian"]
	for i: int in sectors.size():
		var cx: float = 56.0 + float(i) * 105.0
		var d: Player = _spawn_dummy(Vector2(cx, 138.0), sectors[i], top_hairs[i], "perlenbluete", -1.0)
		var bb: BlossomBreeze = d.get_node_or_null("BlossomBreeze") as BlossomBreeze
		if bb != null:
			bb._idle_wait = 0.02
			for _s: int in 8:
				bb._process(0.08)

	# Bottom row: Dynamic motion (Walk SE, Sprint E with trailing BlossomBreeze petals, Seated SE) + 3 Salon Dyes (Rose, Forest/Jade, Violet)!
	var bot_sectors: Array[int] = [1, 0, 1, 2, 1, 2]
	var bot_outfits: Array[String] = ["perlenbluete", "perlenbluete", "perlenbluete", "perlenbluete:rosewood", "perlenbluete:glacier", "perlenbluete:midnight"]
	var bot_hairs: Array[String] = ["storm_tail:obsidian", "moon_knot", "night_bun:obsidian", "dusk_braids", "blade_bob", "default:blonde"]
	var bot_phases: Array[float] = [1.0, 2.0, -1.0, -1.0, -1.0, -1.0]
	for i: int in 6:
		var cx: float = 56.0 + float(i) * 105.0
		var d2: Player = _spawn_dummy(Vector2(cx, 304.0), bot_sectors[i], bot_hairs[i], bot_outfits[i], bot_phases[i])
		if i == 2:
			d2.show_sit_frame(10, 1)
			d2.attack.visible = false
		var bb2: BlossomBreeze = d2.get_node_or_null("BlossomBreeze") as BlossomBreeze
		if bb2 != null:
			if bot_phases[i] >= 0.0:
				for step_i: int in 14:
					d2.position.x -= 2.2
					bb2._process(0.05)
				d2.position.x = cx
			else:
				bb2._idle_wait = 0.01
				for _s2: int in 6:
					bb2._process(0.09)


func _capture_base_body(out_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	NetworkManager.host_singleplayer()
	await get_tree().process_frame

	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("241e34")
	add_child(bg)

	TimeManager.time_of_day = 0.5
	RenderingServer.global_shader_parameter_set("g_day_strength", 1.0)
	RenderingServer.global_shader_parameter_set("g_day_clock", 1.5)

	# Row 1: Full 8-direction turnaround (E, SE, S, SW, W, NW, N, NE) with Night Bun updo so shoulders, neck & both arms are 100% visible!
	var dir_names: Array[String] = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	for s: int in 8:
		var cx: float = 44.0 + float(s) * 79.0
		_spawn_dummy(Vector2(cx, 134.0), s, "night_bun", "none", -1.0)
		var lbl: Label = Label.new()
		lbl.text = dir_names[s]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.position = Vector2(cx - 8.0, 14.0)
		add_child(lbl)

	# Row 2: Different hairstyles + Walk + Sprint + Live GripRig/ArmPainter holding Sword (`sword_void`)!
	var r2_hairs: Array[String] = ["default", "blade_bob:obsidian", "moon_knot", "storm_tail:obsidian", "dusk_braids", "night_bun:obsidian"]
	var r2_sectors: Array[int] = [1, 2, 3, 0, 5, 1]
	var r2_walk: Array[float] = [-1.0, -1.0, -1.0, 1.4, 2.1, -1.0]
	var r2_labels: Array[String] = ["Idle SE", "Idle S", "Idle SW", "Sprint E", "Sprint NW", "Schwertgriff"]
	for i: int in 6:
		var cx2: float = 58.0 + float(i) * 104.0
		var d: Player = _spawn_dummy(Vector2(cx2, 306.0), r2_sectors[i], r2_hairs[i], "none", r2_walk[i])
		if i == 5:
			d.attack.held_weapon = "sword_void"
			d.attack._since_swing = 0.0
			d.attack._weapon_alpha = 1.0
			d.attack._hold_k = 1.0
			d.attack._free_k = 1.0
			for _st: int in 35:
				d.attack._process(0.04)
		var lbl2: Label = Label.new()
		lbl2.text = r2_labels[i]
		lbl2.add_theme_font_size_override("font_size", 10)
		lbl2.position = Vector2(cx2 - 30.0, 186.0)
		add_child(lbl2)

	for _f: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("Saved live Godot base-body capture to: ", out_path)
	get_tree().quit(0)
