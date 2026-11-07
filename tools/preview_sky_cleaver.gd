extends Node2D
## Offline workbench for Mornath, the Sky Cleaver (SkyCleaverRig): contact sheets of every pose at several moments and facings, frame strips and a headless check.
## No saves, no game port. Needs a renderer for captures (`--rendering-driver opengl3`).
##   -- --capture=/abs/sheet.png [--scale=2] [--only=PERCHED,FLYING] [--facings] [--poses] [--heading=0.62]
##   -- --anim=/abs/folder [--scale=2] [--heading=0.62]     (frame strips of FLYING, HOVER, TAKEOFF, LANDING, STAGGER, CRASHED, DEAD)
##   -- --check [--corruption=1]                             (headless: every pose, several headings, random velocity and rise)
##   -- --corruption=0..1 [--lift=0..1]                      (phase 2 look on every cell; 0 = phase one, the default)
## Cells: the poses by name (PERCHED .. DEAD, JUDGE, SPENT, DOWNED) plus BURST (JUDGE with burst_blades() at its start: the light blades shatter and regrow).
const CELL: Vector2i = Vector2i(104, 112)
const ORIGIN_Y: float = 90.0
const NAMES: Array[String] = ["PERCHED", "TAKEOFF", "FLYING", "HOVER", "LANDING", "STAGGER", "CRASHED", "DEAD", "JUDGE", "SPENT", "DOWNED", "BURST"]
const DURATION: Array[float] = [60.0, 0.6, 60.0, 60.0, 0.5, 0.5, 0.7, 1.8, 60.0, 60.0, 60.0, 60.0]
## cell index -> SkyCleaverRig.Pose (the first eight are the enum values, the new cells map on)
const POSE_OF: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 10, 8, 9, 10]
const PERCH_TIMES: Array[float] = [0.3, 1.5, 3.0, 4.5, 5.5, 6.5, 7.5, 9.0]
const STEP: float = 1.0 / 60.0

var _glow_material: CanvasItemMaterial = CanvasItemMaterial.new()
var _no_glow: bool = false
var _no_body: bool = false
var _corruption: float = 0.0
var _lift: float = 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("120e1f"))
	_glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var capture: String = ""
	var anim: String = ""
	var scale_i: int = 2
	var only: Array[String] = []
	var want_facings: bool = false
	var want_poses: bool = false
	var heading: float = 0.62
	var check: bool = false
	var cols: int = 8
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--anim="):
			anim = arg.trim_prefix("--anim=")
		elif arg.begins_with("--scale="):
			scale_i = int(arg.trim_prefix("--scale="))
		elif arg.begins_with("--only="):
			for n: String in arg.trim_prefix("--only=").split(","):
				only.append(n.to_upper())
		elif arg.begins_with("--heading="):
			heading = float(arg.trim_prefix("--heading="))
		elif arg.begins_with("--cols="):
			cols = maxi(1, int(arg.trim_prefix("--cols=")))
		elif arg.begins_with("--corruption="):
			_corruption = clampf(float(arg.trim_prefix("--corruption=")), 0.0, 1.0)
		elif arg.begins_with("--lift="):
			_lift = clampf(float(arg.trim_prefix("--lift=")), 0.0, 1.0)
		elif arg == "--noglow":
			_no_glow = true
		elif arg == "--nobody":
			_no_body = true
		elif arg == "--facings":
			want_facings = true
		elif arg == "--poses":
			want_poses = true
		elif arg == "--check":
			check = true
	if check:
		var code: int = await _run_check()
		get_tree().quit(code)
		return
	if anim != "":
		DirAccess.make_dir_recursive_absolute(anim)
		await _run_anim(anim, scale_i, heading)
		get_tree().quit(0)
		return
	if capture != "":
		if not want_facings and not want_poses:
			want_poses = true
			want_facings = only.is_empty()
		var cells: Array[Dictionary] = _sheet_cells(only, want_poses, want_facings, heading)
		await _render(cells, cols, scale_i, capture)
		get_tree().quit(0)
		return
	# interactive: the full sheet at 2x in the window
	var cells2: Array[Dictionary] = _sheet_cells([], true, false, heading)
	await _render(cells2, 8, 1, "")


# --- cells ---------------------------------------------------------------------------------------------------------


func _cell(pose: int, label: String, heading: float, moment: float) -> Dictionary:
	return {"pose": pose, "label": label, "heading": heading, "moment": moment}


func _sheet_cells(only: Array[String], poses: bool, facings: bool, heading: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if poses:
		for p: int in NAMES.size():
			if not only.is_empty() and not (NAMES[p] in only):
				continue
			for i: int in 8:
				var m: float = PERCH_TIMES[i] if p == 0 else float(i) / 7.0
				if p == 2 or p == 3:
					m = float(i) / 8.0
				out.append(_cell(p, "%s %d" % [NAMES[p], i], heading, m))
	if facings:
		for p: int in [0, 2, 3, 1]:
			if not only.is_empty() and not (NAMES[p] in only):
				continue
			var m2: float = {0: 3.0, 2: 0.375, 3: 0.25, 1: 0.7}[p]
			for k: int in 8:
				out.append(_cell(p, "%s F%d" % [NAMES[p], k], float(k) * PI / 4.0, m2))
	return out


func _spawn(parent: Node2D, id: String) -> SkyCleaverRig:
	var holder: Node2D = Node2D.new()
	holder.name = id
	parent.add_child(holder)
	var rig: SkyCleaverRig = SkyCleaverRig.new()
	rig.name = "Rig"
	var body: Node2D = Node2D.new()
	body.name = "Body"
	rig.add_child(body)
	var glow: Node2D = Node2D.new()
	glow.name = "Glow"
	glow.material = _glow_material
	rig.add_child(glow)
	holder.add_child(rig)
	glow.visible = not _no_glow
	body.visible = not _no_body
	return rig


func _velocity_for(pose: int, heading: float) -> Vector2:
	if pose == 2:
		return Vector2.from_angle(heading) * 130.0
	return Vector2.ZERO


func _step(rig: SkyCleaverRig, seconds: float, pose: int, heading: float, rise: float = 0.0) -> void:
	var left: float = seconds
	while left > 0.0:
		var dt: float = minf(STEP, left)
		rig.update_rig(dt, _velocity_for(pose, heading), heading, rise)
		left -= dt


## Plays the pose the way the game would (with the pose before it as a prelude) up to the moment of the cell.
func _simulate(rig: SkyCleaverRig, cell: Dictionary) -> void:
	var pose: int = cell.pose
	var heading: float = cell.heading
	var moment: float = cell.moment
	rig.corruption = _corruption
	rig.lift = _lift
	rig.update_rig(0.0, Vector2.ZERO, heading, 0.0)
	rig.ground_drop = 100.0
	match pose:
		0:
			rig.start_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
			_step(rig, moment, pose, heading)
		1:
			rig.start_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
			_step(rig, 0.6, 0, heading)
			rig.start_pose(SkyCleaverRig.Pose.TAKEOFF, 0.6)
			_step(rig, moment * 0.6, pose, heading)
		2:
			rig.start_pose(SkyCleaverRig.Pose.FLYING, 60.0)
			_step(rig, 1.2 + moment / SkyCleaverRig.FLY_RATE, pose, heading, 0.0)
		3:
			rig.start_pose(SkyCleaverRig.Pose.HOVER, 60.0)
			_step(rig, 1.2 + moment / SkyCleaverRig.HOVER_RATE, pose, heading)
		4:
			rig.start_pose(SkyCleaverRig.Pose.FLYING, 60.0)
			_step(rig, 0.8, 2, heading)
			rig.start_pose(SkyCleaverRig.Pose.LANDING, 0.5)
			_step(rig, moment * 0.5, pose, heading)
		5:
			rig.start_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
			_step(rig, 0.5, 0, heading)
			rig.start_pose(SkyCleaverRig.Pose.TAKEOFF, 0.6)
			_step(rig, 0.3, 1, heading)
			rig.start_pose(SkyCleaverRig.Pose.STAGGER, 0.5)
			_step(rig, moment * 0.5, pose, heading)
		6:
			rig.start_pose(SkyCleaverRig.Pose.FLYING, 60.0)
			_step(rig, 0.8, 2, heading)
			rig.start_pose(SkyCleaverRig.Pose.CRASHED, 0.7)
			_step(rig, moment * 0.7, pose, heading)
		7:
			rig.start_pose(SkyCleaverRig.Pose.FLYING, 60.0)
			_step(rig, 0.8, 2, heading)
			rig.start_pose(SkyCleaverRig.Pose.CRASHED, 0.7)
			_step(rig, 0.7, 6, heading)
			rig.start_pose(SkyCleaverRig.Pose.DEAD, 1.8)
			_step(rig, moment * 1.8, pose, heading)
		8:
			rig.start_pose(SkyCleaverRig.Pose.PERCHED, 60.0)
			_step(rig, 0.4, 0, heading)
			rig.start_pose(SkyCleaverRig.Pose.JUDGE, 60.0)
			_step(rig, 0.6 + moment * 1.6, pose, heading)
		9:
			rig.start_pose(SkyCleaverRig.Pose.SPENT, 60.0)
			_step(rig, 0.8 + moment * 1.6, pose, heading)
		10:
			rig.start_pose(SkyCleaverRig.Pose.FLYING, 60.0)
			_step(rig, 0.8, 2, heading)
			rig.start_pose(SkyCleaverRig.Pose.CRASHED, 0.7)
			_step(rig, 0.7, 6, heading)
			rig.start_pose(SkyCleaverRig.Pose.DOWNED, 60.0)
			_step(rig, 0.3 + moment * 1.6, pose, heading)
		11:
			rig.start_pose(SkyCleaverRig.Pose.JUDGE, 60.0)
			_step(rig, 1.2, 8, heading)
			rig.burst_blades()
			_step(rig, moment * 2.4, 8, heading)
	rig.update_rig(0.0, _velocity_for(pose, heading), heading, 0.0)


# --- rendering -----------------------------------------------------------------------------------------------------


func _render(cells: Array[Dictionary], cols: int, scale_i: int, path: String) -> void:
	var rows: int = ceili(float(cells.size()) / float(cols))
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(cols * CELL.x * scale_i, rows * CELL.y * scale_i)
	viewport.transparent_bg = false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world: Node2D = Node2D.new()
	world.scale = Vector2(scale_i, scale_i)
	viewport.add_child(world)
	var backdrop: Node2D = Node2D.new()
	backdrop.draw.connect(_draw_backdrop.bind(backdrop, cells, cols))
	world.add_child(backdrop)
	for i: int in cells.size():
		var cell: Dictionary = cells[i]
		var rig: SkyCleaverRig = _spawn(world, "SkyPrev%d" % i)
		rig.get_parent().position = _origin(i, cols)
		_simulate(rig, cell)
	if path == "":
		return
	for n: int in 4:
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var result: Error = image.save_png(path)
	print("Sky Cleaver capture: ", error_string(result), " ", path, " ", image.get_size())
	viewport.queue_free()


func _origin(i: int, cols: int) -> Vector2:
	return Vector2(float(i % cols) * CELL.x + CELL.x * 0.5, float(i / cols) * CELL.y + ORIGIN_Y)


func _draw_backdrop(canvas: Node2D, cells: Array[Dictionary], cols: int) -> void:
	var rows: int = ceili(float(cells.size()) / float(cols))
	canvas.draw_rect(Rect2(0, 0, cols * CELL.x, rows * CELL.y), Color("120e1f"))
	for i: int in cells.size():
		var o: Vector2 = _origin(i, cols)
		var top_left: Vector2 = Vector2(float(i % cols) * CELL.x, float(i / cols) * CELL.y)
		canvas.draw_rect(Rect2(top_left + Vector2(1, 1), Vector2(CELL.x - 2, CELL.y - 2)), Color("1a1630"))
		canvas.draw_rect(Rect2(top_left + Vector2(1, ORIGIN_Y + 1), Vector2(CELL.x - 2, CELL.y - ORIGIN_Y - 2)), Color("223a35"))
		if cells[i].pose in [0, 5, 8, 9, 11]:
			canvas.draw_rect(Rect2(o + Vector2(-17, 0), Vector2(34, 20)), Color("585670"))
			canvas.draw_rect(Rect2(o + Vector2(-17, 0), Vector2(34, 3)), Color("7a7896"))
			canvas.draw_rect(Rect2(o + Vector2(-17, 3), Vector2(3, 17)), Color("6a688a"))
		else:
			canvas.draw_rect(Rect2(o + Vector2(-14, 0), Vector2(28, 3)), Color(0, 0, 0, 0.25))
		canvas.draw_rect(Rect2(o + Vector2(-1, -1), Vector2(3, 1)), Color("ff4fd8"))
		PixelText.draw(canvas, String(cells[i].label), Vector2i(top_left) + Vector2i(4, 4), Color("bdb3e4"))


func _run_anim(folder: String, scale_i: int, heading: float) -> void:
	var specs: Array[Array] = [["flying", 2, 8, 8.0], ["hover", 3, 8, 8.0], ["takeoff", 1, 8, 7.0], ["landing", 4, 8, 7.0], ["stagger", 5, 8, 7.0], ["crashed", 6, 8, 7.0], ["dead", 7, 8, 7.0], ["perched", 0, 8, 1.0]]
	for spec: Array in specs:
		var cells: Array[Dictionary] = []
		for i: int in int(spec[2]):
			var m: float = float(i) / float(spec[3])
			if int(spec[1]) == 0:
				m = PERCH_TIMES[i]
			cells.append(_cell(int(spec[1]), "%s %d" % [String(spec[0]).to_upper(), i], heading, m))
		await _render(cells, 8, scale_i, "%s/%s_strip.png" % [folder, spec[0]])


# --- headless check ------------------------------------------------------------------------------------------------


func _finite(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


func _run_check() -> int:
	var failures: int = 0
	print("Sky Cleaver check at corruption %.2f" % _corruption)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var world: Node2D = Node2D.new()
	add_child(world)
	var beats: Array[int] = [0, 0]
	var beads: Array[int] = [0]
	var rig: SkyCleaverRig = _spawn(world, "SkyCheck")
	rig.corruption = _corruption
	rig.wing_beat.connect(func(strong: bool) -> void: beats[0 if strong else 1] += 1)
	rig.bead_dropped.connect(func(point: Vector2) -> void:
		beads[0] += 1
		if not _finite(point):
			push_error("bead point not finite"))
	var frames: int = 0
	for pose_i: int in NAMES.size():
		for heading_i: int in 8:
			var heading: float = float(heading_i) * PI / 4.0 + rng.randf_range(-0.3, 0.3)
			rig.start_pose(POSE_OF[pose_i] as SkyCleaverRig.Pose, 0.7 if pose_i != 0 else 20.0, rng.randf_range(0.0, 0.3) if heading_i % 3 == 0 else 0.0)
			for f: int in 320:
				if _corruption > 0.0:
					if f == 40:
						rig.burst_blades()
					if f == 90:
						rig.crack_flash()
					rig.lift = 1.0 if (f / 60) % 2 == 1 else 0.0
					rig.charge = 0.6 if f > 200 else 0.0
				var vel: Vector2 = Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-180.0, 180.0))
				var rise: float = rng.randf_range(-160.0, 160.0)
				heading += rng.randf_range(-0.05, 0.05)
				rig.ground_drop = rng.randf_range(30.0, 120.0)
				rig.update_rig(1.0 / 60.0 if f % 7 != 0 else rng.randf_range(0.0, 0.05), vel, heading, rise)
				frames += 1
				var b: Rect2 = rig.bounds()
				var ok: bool = _finite(rig.head_point()) and _finite(rig.core_point()) and is_finite(b.position.x) and is_finite(b.size.x) and is_finite(b.position.y) and is_finite(b.size.y)
				if not ok:
					failures += 1
					push_error("non finite geometry: pose %s heading %.2f frame %d" % [NAMES[pose_i], heading, f])
					break
				if f % 97 == 0:
					await get_tree().process_frame
	# transitions in a row, as the fight would play them
	rig.charge = 0.0
	rig.lift = 0.0
	for chain: Array in [[0, 1, 2, 3, 4, 0], [0, 1, 5, 0], [2, 6, 7], [3, 4, 0, 1, 2, 6, 7], [0, 8, 9, 3, 8, 5, 10, 6, 10]]:
		for pose_i: int in chain:
			rig.start_pose(POSE_OF[pose_i] as SkyCleaverRig.Pose, 0.5)
			for f: int in 40:
				rig.update_rig(1.0 / 60.0, Vector2(90, 20), 0.5, 20.0)
	for pose_i: int in [0, 2]:
		for heading_i: int in [0, 2, 4]:
			var h2: float = float(heading_i) * PI / 4.0
			rig.start_pose(POSE_OF[pose_i] as SkyCleaverRig.Pose, 60.0)
			var widest: float = 0.0
			var tallest: float = 0.0
			var lowest: float = 0.0
			for f: int in 240:
				rig.update_rig(1.0 / 60.0, Vector2.from_angle(h2) * 130.0 if pose_i == 2 else Vector2.ZERO, h2, 0.0)
				if f > 60:
					var bb: Rect2 = rig.bounds()
					widest = maxf(widest, bb.size.x)
					tallest = maxf(tallest, -bb.position.y)
					lowest = maxf(lowest, bb.end.y)
			print("  %s heading %.2f: max width %.0f, max height above origin %.0f, lowest %.0f" % [NAMES[pose_i], h2, widest, tallest, lowest])
	await get_tree().process_frame
	print("Sky Cleaver check: %d frames, %d failures, %d strong beats, %d soft beats, %d beads" % [frames, failures, beats[0], beats[1], beads[0]])
	return 1 if failures > 0 else 0
