extends Node2D
## Real Player scenes and right-arm rig; Godot --path . res://tools/preview_ellie_standby.tscn
const NAMES: PackedStringArray = ["STRECKEN", "HAAR RICHTEN", "UMSCHAUEN"]
var players: Array[Player] = []
var elapsed: float = 0.0

func _ready() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("262232")
	add_child(bg)
	for row: int in 2:
		for clip: int in Player.STANDBY_CLIPS:
			var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
			player.name = str(2 + row * Player.STANDBY_CLIPS + clip)
			add_child(player)
			player.set_physics_process(false)
			player.set_process(false)
			player.attack.set_process(false)
			player._camera.enabled = false
			player.scale = Vector2(2.4, 2.4)
			player.position = Vector2(110 + 205 * clip, 151 + 170 * row)
			player.facing = Vector2.DOWN if row == 0 else Vector2.LEFT
			player._sector = 2 if row == 0 else 4
			player._start_standby(clip)
			players.append(player)
			var label: Label = Label.new()
			label.text = NAMES[clip]
			label.position = Vector2(36 + 205 * clip, 12 + 170 * row)
			add_child(label)
	_update_players(0.0)

func _process(delta: float) -> void:
	elapsed = fposmod(elapsed + delta, float(Player.STANDBY_FRAMES) / Player.STANDBY_FPS)
	_update_players(elapsed)

func _update_players(time: float) -> void:
	for i: int in players.size():
		var player: Player = players[i]
		player._standby_clip = i % Player.STANDBY_CLIPS
		player._standby_time = time
		player._animate(0.0)
		player.attack.facing = player.facing
		player.attack._process(1.0 / Player.STANDBY_FPS)
