extends Node2D
## Offline pose workbench for the Void Crusher: a contact sheet of its poses on a ground grid, looping the way the game plays them.
## Optional: -- --capture=/absolute/path.png [--facing=1.571] [--phase=0.7] [--night] ; no saves, no game port.
const ACTOR: PackedScene = preload("res://src/entities/enemies/void_crusher.tscn")
const LABELS: Array[String] = ["RUHE", "GEHEN", "SCHLAG: AUSHOLEN", "SCHLAG: EINSCHLAG", "SCHLAG: FEST", "RAMMSTOSS: ANSATZ", "RAMMSTOSS", "BETAEUBT", "FEGER: AUSHOLEN", "FEGER", "TREFFER IM RUECKEN", "TOD"]
const POSES: Array[int] = [CrusherRig.Pose.IDLE, CrusherRig.Pose.MOVE, CrusherRig.Pose.SLAM_WINDUP, CrusherRig.Pose.SLAM, CrusherRig.Pose.SLAM_RECOVER, CrusherRig.Pose.RUSH_WINDUP, CrusherRig.Pose.RUSH, CrusherRig.Pose.STUN, CrusherRig.Pose.SWEEP_WINDUP, CrusherRig.Pose.SWEEP, CrusherRig.Pose.HURT, CrusherRig.Pose.DEAD]
const PHASE: Array[float] = [0.3, 0.5, 0.9, 0.75, 0.5, 0.9, 0.5, 0.5, 0.95, 0.5, 0.35, 0.45]
const DURATION: Array[float] = [1.0, 1.0, 0.95, 0.18, 0.95, 0.7, 0.34, 1.4, 0.45, 0.16, 0.65, 1.5]
var _actors: Array[VoidCrusher] = []
var _time: float = 0.0
var _facing: float = 0.0
var _fixed_phase: float = -1.0
var _night: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("120e1f"))
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--facing="):
			_facing = float(arg.trim_prefix("--facing="))
		elif arg.begins_with("--phase="):
			_fixed_phase = float(arg.trim_prefix("--phase="))
		elif arg == "--night":
			_night = true
	for i: int in POSES.size():
		var actor: VoidCrusher = ACTOR.instantiate() as VoidCrusher
		actor.position = Vector2(55 + (i % 4) * 155, 100 + (i / 4) * 112)
		actor.name = "CrusherPreview%d" % i
		add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.get_node("HealthBar").hide()
		actor.get_node("NightLight").visible = false
		_actors.append(actor)
	if capture != "":
		set_process(false)
		for step: int in 3:
			_sample(0.0)
		queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var result: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Crusher capture: ", error_string(result))
		get_tree().quit(result)


func _sample(_dt: float) -> void:
	for i: int in POSES.size():
		var actor: VoidCrusher = _actors[i]
		var rig: CrusherRig = actor._rig
		var heading: float = _facing
		var phase: float = _fixed_phase if _fixed_phase >= 0.0 else PHASE[i]
		actor.heading = heading
		actor.attack_dir = Vector2.from_angle(heading)
		actor.attack_origin = actor.position
		if POSES[i] in [CrusherRig.Pose.SWEEP_WINDUP, CrusherRig.Pose.SWEEP]:
			actor.attack_dir = Vector2.from_angle(heading + PI * 0.9) ## the target stands behind it
		rig.update_rig(0.0, Vector2.ZERO, heading, actor.attack_dir.angle())
		rig.start_pose(POSES[i] as CrusherRig.Pose, DURATION[i])
		for n: int in 6: ## settle the planted feet and tendons, then land on the phase
			rig.update_rig(DURATION[i] * phase / 6.0, Vector2.RIGHT * 35.0 if POSES[i] == CrusherRig.Pose.MOVE else Vector2.ZERO, heading, actor.attack_dir.angle())
		actor.state = [VoidCrusher.State.IDLE, VoidCrusher.State.CHASE, VoidCrusher.State.SLAM_WINDUP, VoidCrusher.State.SLAM, VoidCrusher.State.SLAM_RECOVER, VoidCrusher.State.RUSH_WINDUP, VoidCrusher.State.RUSH, VoidCrusher.State.STUN, VoidCrusher.State.SWEEP_WINDUP, VoidCrusher.State.SWEEP, VoidCrusher.State.HURT, VoidCrusher.State.DEAD][i]
		actor._state_time = DURATION[i] * phase
		actor.warning_length = 64.0 if POSES[i] == CrusherRig.Pose.RUSH_WINDUP else 54.0
		actor._zone.queue_redraw()
		actor._fx.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_fixed_phase = -1.0
	for i: int in POSES.size():
		_actors[i]._rig.update_rig(delta, Vector2.RIGHT * 35.0 if POSES[i] == CrusherRig.Pose.MOVE else Vector2.ZERO, _facing, _actors[i].attack_dir.angle())
		_actors[i]._state_time += delta
		_actors[i]._zone.queue_redraw()
		_actors[i]._fx.queue_redraw()
	queue_redraw()


func _draw() -> void:
	PixelText.draw(self, "VOIDBLOOM / LEERENBRECHER", Vector2i(18, 12), Color("cbaaff"))
	for i: int in POSES.size():
		var cell: Vector2i = Vector2i(8 + (i % 4) * 155, 30 + (i / 4) * 112)
		draw_rect(Rect2(cell, Vector2i(147, 104)), Color("223a35"))
		for y: int in range(cell.y + 14, cell.y + 104, 16):
			draw_line(Vector2(cell.x, y), Vector2(cell.x + 147, y), Color("29443c"))
		PixelText.draw(self, LABELS[i], cell + Vector2i(5, 6), Color("bdb3e4"))
