extends Node2D
## Animation workbench: Godot --path . tools/preview_void_predator.tscn
## Optional -- --capture=/absolute/path.png writes a still and exits.

const LABELS: Array[String] = ["BEOBACHTEN", "VERANKERN / ZIEHEN", "SICHEL AUFZIEHEN", "SICHELSCHLAG", "ZUG VORBEREITEN", "VERANKERUNGSZUG"]
var _actors: Array[ShadowSpider] = []
var _time: float = 0.0
var _capture: String = ""
var _phases: Array[int] = [-1, -1, -1, -1, -1, -1]


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("120e1f"))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture = arg.trim_prefix("--capture=")
	if OS.get_cmdline_user_args().has("--night"):
		TimeManager.time_of_day = 0.97
		var darkness: CanvasModulate = CanvasModulate.new()
		darkness.color = TimeManager.ambient_color()
		add_child(darkness)
	for i: int in 6:
		var actor: ShadowSpider = load("res://src/entities/enemies/shadow_spider.tscn").instantiate() as ShadowSpider
		actor.position = Vector2(75 + (i % 3) * 210, 116 + (i / 3) * 142)
		add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.get_node("HealthBar").hide()
		actor.heading = 0.0
		actor.attack_side = -1.0
		actor.attack_dir = Vector2.RIGHT
		actor._rig.attack_side = -1.0
		actor._rig.set_aim(Vector2.RIGHT)
		actor.anchor = actor.position + Vector2(105, 0)
		actor._rig.set_anchor(actor.anchor)
		actor._rig.update_rig(0.01, Vector2.ZERO, 0.0)
		_actors.append(actor)
	if not _capture.is_empty():
		set_process(false)
		for i: int in 6:
			_sample(i, 0.72)
		queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(_capture)
		print("Predator capture: ", error_string(error))
		get_tree().quit(error)


func _sample(i: int, t: float) -> void:
	var actor: ShadowSpider = _actors[i]
	var rig: SpiderRig = actor._rig
	rig.set_aim(Vector2.RIGHT)
	rig.start_pose(SpiderRig.Pose.LOCOMOTION, 1.0)
	rig.update_rig(0.01, Vector2.ZERO, 0.0)
	match i:
		0:
			rig.start_pose(SpiderRig.Pose.OBSERVE, 1.0)
			rig.update_rig(t, Vector2.ZERO, 0.0)
		1:
			actor.position.x = 285 + sin(t * TAU) * 9.0
			rig.update_rig(0.06, Vector2.RIGHT * 70.0, 0.0)
		2, 3:
			rig.start_pose(SpiderRig.Pose.WINDUP, 0.58)
			rig.update_rig(0.58 * (t if i == 2 else 1.0), Vector2.ZERO, 0.0)
			if i == 3:
				rig.start_pose(SpiderRig.Pose.STRIKE, 0.24)
				rig.update_rig(t * 0.14, Vector2.ZERO, 0.0)
		4, 5:
			rig.start_pose(SpiderRig.Pose.COIL, 0.7)
			rig.update_rig(0.7 * (t if i == 4 else 1.0), Vector2.ZERO, 0.0)
			if i == 5:
				rig.start_pose(SpiderRig.Pose.THROW, 0.2)
				rig.update_rig(0.2 * t, Vector2.ZERO, 0.0)


func _process(delta: float) -> void:
	_time += delta
	for i: int in _actors.size():
		var actor: ShadowSpider = _actors[i]
		var rig: SpiderRig = actor._rig
		var poses: Array[int] = [SpiderRig.Pose.WINDUP, SpiderRig.Pose.RECOVER]
		var durations: Array[float] = [0.58, 0.72]
		match i:
			0:
				poses = [SpiderRig.Pose.OBSERVE, SpiderRig.Pose.LOCOMOTION]
				durations = [0.8, 1.2]
			1:
				poses = [SpiderRig.Pose.LOCOMOTION]
				durations = [2.0]
			3:
				poses = [SpiderRig.Pose.WINDUP, SpiderRig.Pose.STRIKE, SpiderRig.Pose.RECOVER]
				durations = [0.58, 0.24, 0.72]
			4:
				poses = [SpiderRig.Pose.COIL, SpiderRig.Pose.RECOVER]
				durations = [0.7, 0.82]
			5:
				poses = [SpiderRig.Pose.COIL, SpiderRig.Pose.THROW, SpiderRig.Pose.PULL, SpiderRig.Pose.RECOVER]
				durations = [0.7, 0.2, 0.36, 0.82]
		var total: float = 0.0
		for duration: float in durations:
			total += duration
		var elapsed: float = fposmod(_time, total)
		var phase: int = 0
		while phase < durations.size() - 1 and elapsed >= durations[phase]:
			elapsed -= durations[phase]
			phase += 1
		if phase != _phases[i]:
			_phases[i] = phase
			rig.start_pose(poses[phase] as SpiderRig.Pose, durations[phase])
		var velocity: Vector2 = Vector2.ZERO
		if i == 1:
			var old: float = actor.position.x
			actor.position.x = 285 + sin(_time * 2.0) * 22.0
			velocity.x = (actor.position.x - old) / maxf(delta, 0.001)
		rig.update_rig(delta, velocity, 0.0)
	queue_redraw()


func _draw() -> void:
	PixelText.draw(self, "VOIDBLOOM / VOID-PREDATOR", Vector2i(20, 18), Color("cbaaff"))
	for i: int in 6:
		var cell: Vector2i = Vector2i(12 + (i % 3) * 210, 46 + (i / 3) * 142)
		draw_rect(Rect2(cell, Vector2i(196, 128)), Color("223a35"))
		for y: int in range(cell.y + 12, cell.y + 128, 16):
			draw_line(Vector2(cell.x, y), Vector2(cell.x + 196, y), Color("29443c"))
		PixelText.draw(self, LABELS[i], cell + Vector2i(8, 10), Color("bdb3e4"))
	PixelText.draw(self, "48 HP   /   SICHEL 14   /   ZUG 17   /   SCHWERE TREFFER BRECHEN AUF", Vector2i(20, 342), Color("7fe3da"))
