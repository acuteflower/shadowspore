extends Node2D
## Animation bench using the actual Player scene, including its separately drawn arm.
## Godot --path . res://tools/preview_ellie_hair.tscn [-- --record=/tmp/ellie-hair]
const DIRECTIONS: PackedStringArray = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
var players: Array[Player] = []
var elapsed: float = 0.0
var recording: bool = false

func _ready() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("262232")
	add_child(bg)
	for sector: int in 8:
		var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
		player.name = str(sector + 2)
		add_child(player)
		player.set_physics_process(false)
		player.set_process(false)
		player.attack.set_process(false)
		player._camera.enabled = false
		player.scale = Vector2(2.0, 2.0)
		player.position = Vector2(80 + 155 * (sector % 4), 144 + 160 * (sector / 4))
		players.append(player)
		var label: Label = Label.new()
		label.text = DIRECTIONS[sector]
		label.position = Vector2(18 + 155 * (sector % 4), 30 + 160 * (sector / 4))
		add_child(label)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--record="):
			recording = true
			_record.call_deferred(arg.trim_prefix("--record="))
	_update_players(0.0)

func _process(delta: float) -> void:
	if not recording:
		elapsed += delta
		_update_players(elapsed * 15.0)

func _update_players(phase: float) -> void:
	for sector: int in players.size():
		var player: Player = players[sector]
		var direction: Vector2 = Vector2.RIGHT.rotated(float(sector) * PI / 4.0)
		player.facing = direction
		player.velocity = direction * player.sprint_speed
		player.sprinting = true
		player._sector = sector
		player._walk_time = fposmod(phase, 6.0)
		player._last_step = int(player._walk_time)
		player._animate(0.0)
		player.attack.facing = direction
		player.attack._process(1.0 / 15.0)

func _record(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for phase: int in 6:
		_update_players(float(phase))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var result: Error = get_viewport().get_texture().get_image().save_png(folder.path_join("%02d.png" % phase))
		if result != OK:
			push_error("Could not save animation preview")
			get_tree().quit(1)
			return
	print("Captured six real Player frames: ", folder)
	get_tree().quit()
