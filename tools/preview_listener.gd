extends Node2D
## Offline morph/telegraph workbench. Optional -- --capture=/absolute/path.png.
const ACTOR: PackedScene = preload("res://src/entities/enemies/void_listener.tscn")
const LABELS: Array[String] = ["LAUSCHEN", "TASTEN / GEHEN", "RESONANZ AUFLADEN", "KOPFSPALT OEFFNEN", "DRUCKWELLE", "ABWEHRSCHREI"]
var _actors: Array[VoidListener] = []
var _time: float = 0.0
var _wave: ResonanceWave


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("120e1f"))
	for i: int in 6:
		var actor: VoidListener = ACTOR.instantiate() as VoidListener
		actor.position = Vector2(46 + (i % 3) * 210, 128 + (i / 3) * 145)
		actor.name = "ListenerPreview%d" % i
		add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.get_node("HealthBar").hide()
		_actors.append(actor)
	_wave = load("res://src/entities/enemies/resonance_wave.tscn").instantiate() as ResonanceWave
	add_child(_wave)
	_wave.set_physics_process(false)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			set_process(false)
			_sample(0.72)
			queue_redraw()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var result: Error = get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			print("Listener capture: ", error_string(result))
			get_tree().quit(result)


func _sample(t: float) -> void:
	for i: int in 6:
		var actor: VoidListener = _actors[i]
		var rig: ListenerRig = actor._rig
		var heading: float = PI / 2.0 if i < 2 else 0.0
		actor.heading = heading
		rig.update_rig(0.01, Vector2.ZERO, heading)
		var poses: Array[int] = [ListenerRig.Pose.LISTEN, ListenerRig.Pose.MOVE, ListenerRig.Pose.CHARGE, ListenerRig.Pose.CHARGE, ListenerRig.Pose.RELEASE, ListenerRig.Pose.SCREAM]
		rig.start_pose(poses[i] as ListenerRig.Pose, 1.0)
		rig.update_rig(t if i != 3 else 0.98, Vector2.RIGHT * 35.0 if i == 1 else Vector2.ZERO, heading)
		actor.attack_dir = Vector2.RIGHT
		actor.attack_origin = actor.position
		actor.warning_length = 125.0
		actor.state = VoidListener.State.WAVE_WINDUP if i in [2, 3] else (VoidListener.State.SCREAM if i == 5 else VoidListener.State.LISTEN)
		actor._state_time = 0.7 if i == 3 else (0.16 if i == 5 else 0.35)
		actor._zone.queue_redraw()
		actor._process(0.0)
	_wave.origin = _actors[4].position
	_wave.direction = Vector2.RIGHT
	_wave.emission_point = _actors[4]._rig.mouth_position()
	_wave.travelled = 65.0
	_wave.position = _wave.origin + _wave.direction * _wave.travelled
	_wave._age = _wave.travelled / 210.0
	_wave.queue_redraw()
	_wave._glow.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_sample(fposmod(_time * 0.55, 1.0))
	queue_redraw()


func _draw() -> void:
	PixelText.draw(self, "SHADOWSPORE / LEERENHORCHER", Vector2i(18, 17), Color("cbaaff"))
	for i: int in 6:
		var cell: Vector2i = Vector2i(10 + (i % 3) * 210, 42 + (i / 3) * 145)
		draw_rect(Rect2(cell, Vector2i(198, 135)), Color("223a35"))
		for y: int in range(cell.y + 20, cell.y + 135, 16):
			draw_line(Vector2(cell.x, y), Vector2(cell.x + 198, y), Color("29443c"))
		PixelText.draw(self, LABELS[i], cell + Vector2i(7, 9), Color("bdb3e4"))
	PixelText.draw(self, "F1 SPINNE  /  F2 HORCHER  /  F4 ZEIT   /   38 HP  /  WELLE 14  /  SCHREI 9", Vector2i(18, 345), Color("7fe3da"))
