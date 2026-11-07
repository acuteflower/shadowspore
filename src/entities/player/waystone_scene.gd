class_name WaystoneScene
extends Node
## What the one who woke a waystone sees (a child of that player, local only; the statue's own animation runs on every peer, see `WaystoneStatue`):
## she is held still facing the statue, the camera draws close and rises to the crown while the crystals light, shakes a little at the bloom, Ellie says a line,
## the map opens on its own at the statue (`MapWindow.present`: the fog lifts round it, a ring of light runs out), the title "WEGSTEIN ERWACHT" with the statue's
## name, the camera returns and she is free. Esc / M closes the map early; the rest still runs to its end.

const ZOOM: float = 1.9
const MAP_HOLD: float = 4.6
const LINE: String = "ES IST WARM. ALS WÜRDE SIE MICH ERKENNEN." ## PLACEHOLDER for the dialogue writer


func start(player: Player, statue: WaystoneStatue, spec: Dictionary) -> void:
	player.story_lock = true
	player.velocity = Vector2.ZERO
	var to: Vector2 = statue.global_position - player.global_position
	if to.length() > 1.0:
		player.facing = to.normalized()
	var camera: Camera2D = player.view_camera()
	var zoom0: Vector2 = camera.zoom
	var shift0: Vector2 = player.view_shift
	var focus: Vector2 = statue.center_point() + Vector2(0, -16) - player.global_position
	var draw_in: Tween = create_tween().set_parallel(true).set_ignore_time_scale(true)
	draw_in.tween_property(camera, "zoom", zoom0 * ZOOM, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	draw_in.tween_property(player, "view_shift", focus, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(WaystoneStatue.FLASH_AT).timeout
	player.release_touch() ## the flash throws her hands off the stone
	await get_tree().create_timer(0.15).timeout
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.speak("ELLIE", LINE, 2.6)
	await get_tree().create_timer(0.9).timeout
	var map: MapWindow = get_tree().get_first_node_in_group("map_window") as MapWindow
	if map != null and is_instance_valid(player):
		var tile: Array = spec.tile as Array
		map.present(Vector2(float(tile[0]), float(tile[1])), MAP_HOLD, float(spec.get("reveal", 15.0)) * float(RegionMap.CELL))
		await get_tree().create_timer(0.3).timeout
		var waited: float = 0.0
		while map.visible and waited < MAP_HOLD + 3.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
	if not is_instance_valid(player):
		queue_free()
		return
	var banner: TownBanner = TownBanner.new()
	add_child(banner)
	banner.show_text("WEGSTEIN ERWACHT", String(spec.get("name", "")))
	var draw_out: Tween = create_tween().set_parallel(true).set_ignore_time_scale(true)
	draw_out.tween_property(camera, "zoom", zoom0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	draw_out.tween_property(player, "view_shift", shift0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await draw_out.finished
	player.story_lock = false
	await get_tree().create_timer(6.5).timeout
	queue_free()
