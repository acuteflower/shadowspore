extends Node2D
## Weapons and tools in her hand at rest, 4 facings x 5 items. `Godot --path . tools/preview_weapons.tscn -- --capture=/abs.png [--sprint]`
const ITEMS: PackedStringArray = ["sword_basic", "sword_iron", "axe_basic", "pickaxe_basic", "sickle_basic"]
const SECTORS: Array[int] = [0, 2, 4, 6] ## E S W N
const DIRS: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
var players: Array[Player] = []

func _ready() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("3c5a3c")
	add_child(bg)
	var sprint: bool = OS.get_cmdline_user_args().has("--sprint")
	for row: int in 4:
		for col: int in ITEMS.size():
			var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
			player.name = str(2 + row * 5 + col)
			add_child(player)
			player.set_physics_process(false)
			player.set_process(false)
			player.attack.set_process(false)
			player._camera.enabled = false
			player.scale = Vector2(2.0, 2.0)
			player.position = Vector2(70 + 125 * col, 80 + 85 * row)
			player.facing = DIRS[row]
			player._sector = SECTORS[row]
			player.attack.held_weapon = ITEMS[col]
			player.attack._since_swing = 0.0
			player.attack.carrying = sprint
			players.append(player)
	var swing: bool = OS.get_cmdline_user_args().has("--swing")
	if swing: ## freeze every item halfway through its first strike
		for i: int in players.size():
			players[i].attack._swing(DIRS[i / ITEMS.size()], ITEMS[i % ITEMS.size()], 0)
			players[i].attack._phase = AttackComponent.Phase.ACTIVE
			players[i].attack._time = float(players[i].attack._step["active"]) * 0.5
	for i: int in 30:
		for p: Player in players:
			p._animate(0.0)
			p.attack.facing = p.facing
			if not swing:
				p.attack._since_swing = 0.0
				p.attack._process(1.0 / 60.0)
			else:
				p.attack._update_pose(0.0)
		await get_tree().process_frame
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			get_tree().quit()
