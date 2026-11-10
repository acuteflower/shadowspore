extends Node2D
## Offline workbench of the Lichtfischer: six poses over night water. Optional -- --capture=/absolute/path.png [--day] [--closeup=N] (N 0..5 draws one panel at 3x).
const ACTOR: PackedScene = preload("res://src/entities/enemies/light_fisher.tscn")
const LABELS: Array[String] = ["KOEDER LOCKT", "PIRSCH", "BISS: AUFZIEHEN", "BISS: SCHNAPPEN", "BLENDLICHT", "IRRLICHTER"]
var _actors: Array[LightFisher] = []
var _time: float = 0.0
var _night: bool = true
var _panels: Node2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("0b1216"))
	var closeup: int = -1
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--day":
			_night = false
		elif arg.begins_with("--closeup="):
			closeup = int(arg.trim_prefix("--closeup="))
		elif arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	_panels = Node2D.new()
	_panels.z_index = -20
	_panels.draw.connect(_draw_panels)
	add_child(_panels)
	for i: int in 6:
		var actor: LightFisher = ACTOR.instantiate() as LightFisher
		actor.position = Vector2(52 + (i % 3) * 210, 118 + (i / 3) * 145)
		actor.name = "FisherPreview%d" % i
		add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.get_node("HealthBar").hide()
		actor.get_node("NightLight").hide()
		_actors.append(actor)
	if closeup >= 0:
		scale = Vector2(3, 3)
		position = -_actors[closeup].position * 3.0 + Vector2(320, 190)
	if capture != "":
		set_process(false)
		_sample(1.0)
		queue_redraw()
		_panels.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var result: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Fisher capture: ", error_string(result))
		get_tree().quit(result)


func _settle(actor: LightFisher, pose: FisherRig.Pose, duration: float, at: float, heading: float, lure: Vector2, velocity: Vector2, aware: float) -> void:
	var rig: FisherRig = actor._rig
	rig.start_pose(pose, duration, maxf(0.0, at - 0.9))
	for k: int in 30:
		rig.update_rig(0.03, velocity, heading, lure, 1.0 if _night else 0.4, aware, true)
	actor.heading = heading
	actor.lure_vec = lure


func _sample(_t: float) -> void:
	var states: Array[LightFisher.State] = [LightFisher.State.LURK, LightFisher.State.STALK, LightFisher.State.SNAP_WINDUP, LightFisher.State.SNAP, LightFisher.State.FLASH, LightFisher.State.ORB_CAST]
	for i: int in 6:
		var actor: LightFisher = _actors[i]
		var rig: FisherRig = actor._rig
		var lure: Vector2 = Vector2(30, 6)
		actor.state = states[i]
		actor.attack_dir = Vector2.RIGHT
		actor.attack_origin = actor.position
		actor.warning_length = 60.0
		actor._burst_done = [false, false, false]
		actor._burst_heard = [false, false, false]
		match i:
			0:
				_settle(actor, FisherRig.Pose.LURK, 1.0, 0.9, 0.3, Vector2(28, 10), Vector2.ZERO, 0.2)
			1:
				_settle(actor, FisherRig.Pose.STALK, 1.0, 0.9, 0.0, lure, Vector2(30, 0), 1.0)
			2:
				actor._state_time = 0.55
				_settle(actor, FisherRig.Pose.SNAP_WINDUP, 0.7, 0.55, 0.0, Vector2(20, 0), Vector2.ZERO, 1.0)
			3:
				actor._state_time = 0.13
				_settle(actor, FisherRig.Pose.SNAP, 0.24, 0.13, 0.0, Vector2(20, 0), Vector2.ZERO, 1.0)
			4:
				actor._state_time = 0.14
				actor.attack_origin = actor.position + Vector2(28, 0)
				_settle(actor, FisherRig.Pose.FLASH, 0.3, 0.14, 0.0, Vector2(28, 0), Vector2.ZERO, 1.0)
			5:
				actor.aim_points = PackedVector2Array([actor.position + Vector2(105, 0), actor.position + Vector2(105, 26), actor.position + Vector2(105, -26)])
				actor.attack_origin = actor.position + Vector2(28, 0)
				actor._state_time = 1.55
				_settle(actor, FisherRig.Pose.ORB_CAST, 2.4, 1.55, 0.0, Vector2(28, 0), Vector2.ZERO, 1.0)
		actor._zone.queue_redraw()
		actor._fx.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_sample(fposmod(_time * 0.5, 1.0))
	queue_redraw()
	_panels.queue_redraw()


func _draw() -> void:
	PixelText.draw(self, "SHADOWSPORE / LICHTFISCHER", Vector2i(18, 17), Color("7fe8d0"))
	PixelText.draw(self, "F5 NUR IM WASSER  /  54 HP  /  KOEDER 150 PROZENT  /  MAUL OFFEN NUR BEIM BISS", Vector2i(18, 345), Color("7fe3da"))


## The water panels lie below everything the creatures draw (their silhouettes sit at z -6 and the warnings at z -3).
func _draw_panels() -> void:
	for i: int in 6:
		var cell: Vector2i = Vector2i(10 + (i % 3) * 210, 42 + (i / 3) * 145)
		_panels.draw_rect(Rect2(cell, Vector2i(198, 135)), Color("10282b") if _night else Color("2d5a5c"))
		for y: int in range(cell.y + 14, cell.y + 135, 9):
			var shift: int = (y / 9) % 2 * 7
			for x: int in range(cell.x + shift, cell.x + 198, 22):
				_panels.draw_rect(Rect2(x, y, 7, 1), Color("17383b") if _night else Color("3b6c6d"))
		PixelText.draw(_panels, LABELS[i], cell + Vector2i(7, 9), Color("bdb3e4"))
