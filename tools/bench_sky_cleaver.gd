extends Node2D
## Frame-time benchmark of the Sky Cleaver rig: update (geometry) vs draw (rasterising) per pose. Run windowed (draw needs a renderer):
##   Godot --rendering-driver opengl3 --path . tools/bench_sky_cleaver.tscn

const POSES: Array = [["PERCHED", 0, Vector2.ZERO], ["FLYING", 2, Vector2(130, 0)], ["HOVER", 3, Vector2.ZERO]]


func _ready() -> void:
	var holder: Node2D = Node2D.new()
	holder.position = Vector2(320, 220)
	add_child(holder)
	var rig: SkyCleaverRig = SkyCleaverRig.new()
	var body: Node2D = Node2D.new()
	body.name = "Body"
	rig.add_child(body)
	var glow: Node2D = Node2D.new()
	glow.name = "Glow"
	rig.add_child(glow)
	holder.add_child(rig)
	var lights: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="):
			rig.tick_hz = float(arg.trim_prefix("--hz="))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lights="):
			lights = int(arg.trim_prefix("--lights="))
	for i: int in lights:
		var light: NightLight = NightLight.new()
		light.radius = 140
		light.position = Vector2(-60 + i * 40, -30)
		holder.add_child(light)
		light.set_night(1.0)
	print("lights: ", lights)
	for spec: Array in POSES:
		rig.start_pose(int(spec[1]) as SkyCleaverRig.Pose, 600.0)
		for i: int in 120:
			rig.update_rig(1.0 / 60.0, spec[2] as Vector2, 0.4, 0.0)
			await get_tree().process_frame
		rig.stat_update_us = 0
		rig.stat_draw_us = 0
		var frames: int = 240
		var t0: int = Time.get_ticks_usec()
		for i: int in frames:
			rig.update_rig(1.0 / 60.0, spec[2] as Vector2, 0.4, 0.0)
			await get_tree().process_frame
		var total: float = float(Time.get_ticks_usec() - t0) / 1000.0 / frames
		print("%-8s frame %.2f ms | update %.2f ms | draw(body+glow) %.2f ms | parts %d" % [spec[0], total, rig.stat_update_us / 1000.0 / frames, rig.stat_draw_us / 1000.0 / frames, rig._sorted.size()])
	get_tree().quit()
