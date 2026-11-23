extends Node2D
## Visual showcase & capture of Movement 2.0 real Player rigs (including 3D ArmPainter right arm,
## held blade, spore-pivot flecks, Sun-Quartz choker glint, airborne shadow separation & cosmetics):
## Run: Godot --path . res://tools/preview_movement_2_0.tscn -- --capture=/abs/path.png

const CARDS: Array[Dictionary] = [
	{"title": "ANTRITT (START)", "col": 1, "sec": 0, "air": 0.0, "glint": false, "spores": false, "hair": "default", "outfit": "default"},
	{"title": "SPRINT-PIVOT 180", "col": 8, "sec": 2, "air": 0.0, "glint": false, "spores": true, "hair": "default", "outfit": "default"},
	{"title": "BREMS-SETTLE", "col": 4, "sec": 4, "air": 0.0, "glint": true, "spores": false, "hair": "storm_tail", "outfit": "default"},
	{"title": "KAMPF-STRAFE", "col": 13, "sec": 2, "air": 0.0, "glint": false, "spores": false, "hair": "blade_bob", "outfit": "crimson"},
	{"title": "VAULT (SPRUNG)", "col": 28, "sec": 0, "air": 8.0, "glint": false, "spores": true, "hair": "default", "outfit": "default"},
	{"title": "LEDGE HOP", "col": 36, "sec": 1, "air": 6.5, "glint": true, "spores": true, "hair": "dusk_braids", "outfit": "perlenbluete"},
]

var _capture_path: String = ""
var _frames_waited: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")

	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(640.0, 360.0)
	bg.color = Color("181426")
	add_child(bg)

	for i: int in CARDS.size():
		var card: Dictionary = CARDS[i]
		var gx: int = i % 3
		var gy: int = i / 3
		var cell_origin: Vector2 = Vector2(22.0 + float(gx) * 204.0, 18.0 + float(gy) * 166.0)

		var panel: ColorRect = ColorRect.new()
		panel.position = cell_origin
		panel.size = Vector2(188.0, 150.0)
		panel.color = Color("221d36")
		add_child(panel)

		var turf: ColorRect = ColorRect.new()
		turf.position = cell_origin + Vector2(14.0, 112.0)
		turf.size = Vector2(160.0, 22.0)
		turf.color = Color("2f624e")
		add_child(turf)

		var p: Player = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
		p.name = str(10 + i)
		add_child(p)
		p.set_physics_process(false)
		p.set_process(false)
		p._camera.enabled = false
		p.scale = Vector2(2.0, 2.0)
		p.position = cell_origin + Vector2(94.0, 122.0)

		var sec: int = int(card["sec"])
		var col: int = int(card["col"])
		p.facing = Vector2.RIGHT.rotated(float(sec) * PI / 4.0)
		p._sector = sec
		p.air_height = float(card["air"])
		p.appearance.set_hair(String(card["hair"]))
		p.appearance.set_outfit(String(card["outfit"]))
		p.attack.held_weapon = "sword_iron"
		p.attack._since_swing = 0.2
		p.attack._ready_k = 1.0

		# Pose on player_agile sheet
		p._use_sheet(Player.AGILE_SHEET_ID)
		var af: int = sec * p._agile_cols + col
		p._sprite.frame = af
		var vert_dy: float = roundf(-p.air_height)
		p._sprite.position = Vector2(0.0, vert_dy)
		var sh: Vector2 = p._rig_agile_shoulder[af]
		var ha: Vector2 = p._rig_agile_hand[af]
		p.attack.facing = p.facing
		p.attack.body_dir = p.facing
		p.attack.rig_shoulder = sh + Vector2(0.0, vert_dy)
		p.attack.rig_hand = ha + Vector2(0.0, vert_dy)
		p.attack.rig_arm3 = GripRig.shift_arm3(GripRig.frame_arm3("player_agile.png", af), 0.0, vert_dy)
		p.attack.free_hand = false
		p.attack.sheathed = false
		p.attack.mirror_material(p._sprite.material)
		p.attack._process(1.0 / 60.0)

		if bool(card["spores"]):
			p.move_fx.spawn_spore_flecks(p.global_position, p.facing, 3)
		if bool(card["glint"]):
			p.move_fx.trigger_choker_glint(0.20)
		p.move_fx._process(0.01)

		var title_node: Node2D = Node2D.new()
		title_node.position = cell_origin + Vector2(8.0, 8.0)
		var txt: String = String(card["title"])
		title_node.draw.connect(func() -> void:
			PixelText.draw(title_node, txt, Vector2i.ZERO, Color("e8e4f4"), Color("1b1a2e")))
		add_child(title_node)
		title_node.queue_redraw()


func _process(_delta: float) -> void:
	if _capture_path.is_empty():
		return
	_frames_waited += 1
	if _frames_waited == 4:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_capture_path)
		print("PREVIEW CAPTURED: ", _capture_path)
		get_tree().quit(0)
