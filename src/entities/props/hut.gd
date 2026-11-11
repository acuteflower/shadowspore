class_name Hut
extends Node2D
## The old hut seen from outside (art: tools/art_hut.py -> assets/interior/hut/hut.png, hut_glow.png, hut_door.png): a sagging mossy roof, a crooked chimney,
## ivy and roots, a window with a broken shutter, glowing mushrooms at its foot. It is solid; its door (`Doorway`, E) leads into the interior of the same name
## (`Interiors`, data/interiors.json), which is much bigger than the hut looks from outside. Placed from data/ground.json "huts": {id, tile, interior}.

const LOOKS: Dictionary = {
	"hut": {"dir": "res://assets/interior/hut/", "picture": "hut.png", "glow": "hut_glow.png", "door": "hut_door.png", "frame": Vector2i(208, 200), "feet": 174, "door_at": Vector2(83, 126),
			"exit": 28.0, "colliders": [Rect2(-58, -24, 116, 22), Rect2(-70, -12, 12, 12), Rect2(58, -12, 12, 12)], "chimney": Vector2(-33, -98), "lights": true},
	## the lumberjack's cabin (art: tools/art_cabin.py): small, overgrown, no chimney, no light of its own
	"cabin": {"dir": "res://assets/interior/cabin/", "picture": "cabin.png", "glow": "cabin_glow.png", "door": "cabin_door.png", "frame": Vector2i(160, 156), "feet": 132, "door_at": Vector2(65, 88),
			"exit": 24.0, "colliders": [Rect2(-42, -22, 84, 20), Rect2(-52, -10, 10, 10), Rect2(42, -10, 10, 10)], "chimney": Vector2.INF, "lights": false},
	## the lake witch's stilt house at the south shore of the Hexenwald lake (art: tools/art_lake_hut.py, docs/seehexe_konzept.md): bone wood, reed roof, a lens
	## window that throws teal light on the yard, crystal wind chimes under the eave; its own night lights (`lamps`), a teal-tinged smoke thread and the spill
	"lake": {"dir": "res://assets/interior/lake_hut/", "picture": "lake_hut.png", "glow": "lake_hut_glow.png", "door": "lake_hut_door.png", "frame": Vector2i(248, 160), "feet": 124,
			"door_at": Vector2(110, 80), "exit": 28.0, "colliders": [Rect2(-48, -24, 48, 20), Rect2(0, -26, 58, 28)], "chimney": Vector2.INF, "lights": false,
			"smoke": Vector2(31, -100), "smoke_tint": Color(0.56, 0.66, 0.68), "spill": "lake_hut_window_light.png",
			"lamps": [[Vector2(26, 14), 50, 0.66, Color("78f4e6")], [Vector2(-30, 0), 22, 0.4, Color("ff9a50")], [Vector2(0, 8), 34, 0.5, Color("78f4e6")],
					[Vector2(-30, -60), 40, 0.55, Color("78f4e6")]],
			"hangs": [["chimes.png", Vector2(-62, -46), 3.0, 2.5], ["chimes.png", Vector2(26, -40), 3.0, 2.5]], "perches": [-20.0, 22.0], "perch_height": 90.0,
			"sounds": [["res://assets/audio/lake_hut/chimes.wav", Vector2(0, -50), -14.0, 220.0]]},
}

var art: String = "hut" ## which of LOOKS
var interior_id: String = "hut"
var yard_props: Array = [] ## the props of its yard (data/ground.json huts[].yard.props, built by `HutYard`)
var doorway: Doorway
var board: CabinBoard ## the cabin's board (null elsewhere)
var _picture: Sprite2D
var _leaf: Sprite2D
var _mushroom_light: NightLight ## the glow of the mushrooms at the foot of the wall (gone once the hut is renewed)
var _look: Dictionary = {}
var exit_position: Vector2 ## where you stand after leaving (world px)
var _glow: Sprite2D
var _spill: Sprite2D ## the lamp light that leaves the window: a bloom on the wall and a patch on the ground with the bars cast into it (a dimmer one for the old hut)
var _window_light: NightLight
var _vane: Sprite2D ## the weathervane on the renewed roof ridge: turns with the wind
var _vane_dir: float = 1.0
var _banner_mat: ShaderMaterial ## the town banner at the renewed roof's right end: its rows sway in the wind
var _sway_mats: Array[ShaderMaterial] = [] ## every swaying picture of the renewed hut (the banners, the flags)
var _banner_left: Sprite2D ## the second banner (village and up), at the roof's left end
var _flags: Array[Sprite2D] = [] ## flags on the ridge (borough: one, town: two)
var _ivy: Array[Sprite2D] = [] ## the ivy that climbs the right corner with the days
var _town: TownManager
var _town_look: float = 0.0
var _town_ready: bool = false ## the first look at the town is not animated


func is_done() -> bool: ## the hut always stands (RoofPerch asks)
	return true


func _ready() -> void:
	y_sort_enabled = true ## the yard's props sort with the people by their feet, in front of and behind the hut
	var look: Dictionary = LOOKS[art] as Dictionary
	var dir: String = String(look.dir)
	var frame: Vector2i = look.frame as Vector2i
	var feet_row: int = int(look.feet)
	_look = look
	var picture: Sprite2D = Sprite2D.new()
	picture.texture = load(dir + String(look.picture)) as Texture2D
	picture.offset = Vector2(0, frame.y / 2.0 - feet_row)
	_picture = picture
	add_child(picture)
	var glow: Sprite2D = Sprite2D.new() ## the emissive pixels (the window, the hole, mushrooms, a crack): unlit, dim by day
	glow.texture = load(dir + String(look.glow)) as Texture2D
	glow.offset = picture.offset
	glow.material = Unlit.material()
	_glow = glow
	add_child(glow)
	var leaf: Sprite2D = Sprite2D.new()
	leaf.texture = load(dir + String(look.door)) as Texture2D
	leaf.centered = false
	leaf.position = (look.door_at as Vector2) - Vector2(frame.x / 2.0, feet_row)
	_leaf = leaf
	add_child(leaf)
	doorway = Doorway.new()
	doorway.interior_id = interior_id
	doorway.label = "BETRETEN"
	doorway.leaf = leaf
	doorway.reach_radius = 14.0
	doorway.prompt_height = 52.0
	doorway.position = Vector2(0, 4)
	add_child(doorway)
	for x: float in ([-62.0, 10.0, 62.0] if art == "hut" else (look.get("perches", []) as Array)): ## birds on the ridge (the renewed one has a vane, the chimney stands left of the middle)
		var perch: RoofPerch = RoofPerch.new()
		perch.host = self
		perch.perch_height = float(look.get("perch_height", 85.0))
		perch.position = Vector2(x, 3.0)
		add_child(perch)
	exit_position = global_position + Vector2(0, float(look.exit))
	var body: StaticBody2D = StaticBody2D.new() ## the walls: you walk round the hut, in through the door
	for rect: Rect2 in look.colliders as Array:
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.position + rect.size / 2.0
		body.add_child(shape)
	add_child(body)
	if bool(look.lights):
		var smoke: CPUParticles2D = CPUParticles2D.new() ## a thin thread of smoke from the chimney: someone keeps a fire going
		smoke.position = look.chimney as Vector2
		smoke.z_index = 4
		smoke.amount = 16
		smoke.lifetime = 5.0
		smoke.preprocess = 5.0
		smoke.direction = Vector2(0.35, -1.0)
		smoke.spread = 10.0
		smoke.gravity = Vector2(2.5, -1.5)
		smoke.initial_velocity_min = 7.0
		smoke.initial_velocity_max = 12.0
		smoke.scale_amount_min = 1.5
		smoke.scale_amount_max = 3.2
		var fade: Gradient = Gradient.new()
		fade.colors = PackedColorArray([Color(0.62, 0.58, 0.7, 0.0), Color(0.62, 0.58, 0.7, 0.5), Color(0.46, 0.43, 0.56, 0.0)])
		fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
		smoke.color_ramp = fade
		add_child(smoke)
		var light: NightLight = NightLight.new() ## a cold glow from the mushrooms at night
		light.position = Vector2(34, -6)
		light.radius = 26
		light.base_energy = 0.55
		light.glow_color = Color("78f4e6")
		_mushroom_light = light
		add_child(light)
		var lantern: NightLight = NightLight.new() ## the lantern by the door and the fire's glow in the window light the doorstep
		lantern.position = Vector2(-18, 6)
		lantern.radius = 40
		lantern.squash = 0.6
		lantern.base_energy = 0.5
		lantern.glow_color = Color("78f4e6")
		add_child(lantern)
		var window_light: NightLight = NightLight.new()
		window_light.position = Vector2(37, 8)
		window_light.radius = 34
		window_light.squash = 0.6
		window_light.base_energy = 0.42
		window_light.glow_color = Color("ff9a50")
		_window_light = window_light
		add_child(window_light)
		_load_spill(dir + "hut_window_light.png")
	if look.has("smoke"):
		_add_smoke(look.smoke as Vector2, look.get("smoke_tint", Color(0.62, 0.58, 0.7)) as Color)
	if look.has("spill"):
		_load_spill(dir + String(look.spill))
	for lamp: Array in look.get("lamps", []) as Array: ## [position, radius, energy, colour]
		var light: NightLight = NightLight.new()
		light.position = lamp[0] as Vector2
		light.radius = int(lamp[1])
		light.squash = 0.6
		light.base_energy = float(lamp[2])
		light.glow_color = lamp[3] as Color
		light.pulse = 0.2
		add_child(light)
	for loop: Array in look.get("sounds", []) as Array: ## [file, position, volume dB, reach px]: quiet positional loops (the wind chimes)
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.stream = load(String(loop[0])) as AudioStream
		player.position = loop[1] as Vector2
		player.volume_db = float(loop[2])
		player.max_distance = float(loop[3])
		player.autoplay = true
		player.finished.connect(func() -> void: player.play())
		add_child(player)
	for hang: Array in look.get("hangs", []) as Array: ## [file, position (px from the feet), pivot row, sway amount]: wind chimes and the like under the eave
		_hang(dir + String(hang[0]), hang[1] as Vector2, float(hang[2]), float(hang[3]))
	if not yard_props.is_empty():
		var yard: HutYard = HutYard.new()
		yard.name = "Yard"
		yard.setup(yard_props, dir)
		add_child(yard)
		for seat: Array in ([] if art != "hut" else [["east", KnightFireScene.STUMP + Vector2(0, 8)], ["south", KnightFireScene.LOG + Vector2(4, 8)]]): ## the two places at the fire (story: "sit by the fire")
			var spot: CampfireSeat = CampfireSeat.new()
			spot.name = "Seat_" + String(seat[0])
			spot.hut = self
			spot.which = String(seat[0])
			spot.label = "SITZEN"
			spot.step = "sit_fire"
			spot.radius = 16.0
			spot.height = 34.0
			spot.position = seat[1] as Vector2
			var which: String = String(seat[0])
			spot.use = func(player: Player) -> void:
				var world: Node = get_tree().get_first_node_in_group("world")
				if world is WorldLevel:
					(world as WorldLevel).start_fire_scene(player, which)
			add_child(spot)
	exit_position = global_position + Vector2(0, float(look.exit))
	if art == "cabin": ## a board lies across the doorstep: carried aside with E, only then the door can be used
		board = CabinBoard.new()
		board.name = "Board"
		board.hut = self
		board.position = Vector2(0, 16)
		add_child(board)
		doorway.locked = true


var _watch: float = 0.0


## The hut is mended and freshened (story: the renewal): the whole outside is drawn again in `fresh/` (closed roof, whole shutters and door, no moss, ivy or roots, no mushrooms).
func set_renewed(on: bool) -> void:
	if art != "hut" or not on:
		return
	var dir: String = String(_look.dir) + "fresh/"
	_picture.texture = load(dir + String(_look.picture)) as Texture2D
	_glow.texture = load(dir + String(_look.glow)) as Texture2D
	_leaf.texture = load(dir + String(_look.door)) as Texture2D
	if _mushroom_light != null:
		_mushroom_light.visible = false
	_load_spill(dir + "hut_window_light.png")
	if ResourceLoader.exists(dir + "vane.png"):
		_vane = Sprite2D.new()
		_vane.texture = load(dir + "vane.png") as Texture2D
		_vane.offset = Vector2(0.0, -15.0) ## its foot on the position: the ridge beam, right of the chimney
		_vane.position = Vector2(36.0, -81.0)
		_picture.add_child(_vane) ## a child of the picture: drawn right after the roof it stands on (as a child of the y-sorting hut it would sort behind it)
	if ResourceLoader.exists(dir + "banner.png"):
		var banner: Sprite2D = _hang(dir + "banner.png", Vector2(171.0 - 104.0, 88.0 - 174.0), 9.0, 3.0) ## frame pixel (171, 88): the bracket sits at the roof's peak, right end
		_banner_mat = banner.material as ShaderMaterial
		_banner_left = _hang(dir + "banner.png", Vector2(14.0 - 104.0, 88.0 - 174.0), 9.0, 3.0) ## its twin on the left (village and up)
		_banner_left.flip_h = true
		_banner_left.visible = false
	if ResourceLoader.exists(dir + "hut_flag.png"):
		for k: int in 2:
			var flag: Sprite2D = _hang(dir + "hut_flag.png", Vector2((98.0 + 24.0 * k) - 104.0, 65.0 - 174.0), -1.0, 0.0) ## the pole's foot on the ridge
			flag.flip_h = k == 1
			flag.visible = false
			_flags.append(flag)
	for name: String in ["hut_ivy_a", "hut_ivy_b"]:
		if ResourceLoader.exists(dir + name + ".png"):
			var ivy: Sprite2D = Sprite2D.new()
			ivy.texture = load(dir + name + ".png") as Texture2D
			ivy.centered = false
			ivy.position = Vector2(-104.0, -174.0)
			ivy.visible = false
			_picture.add_child(ivy)
			_ivy.append(ivy)
	if _window_light != null: ## the real light: bigger, warmer, flickers like the fire behind the glass
		_window_light.position = Vector2(36, 12)
		_window_light.radius = 56
		_window_light.base_energy = 0.62
		_window_light.pulse = 0.3


## A thin thread of smoke rising from a chimney (`at`, px from the feet), tinted.
func _add_smoke(at: Vector2, tint: Color) -> void:
	var smoke: CPUParticles2D = CPUParticles2D.new()
	smoke.position = at
	smoke.z_index = 4
	smoke.amount = 14
	smoke.lifetime = 5.0
	smoke.preprocess = 5.0
	smoke.direction = Vector2(0.3, -1.0)
	smoke.spread = 10.0
	smoke.gravity = Vector2(2.5, -1.5)
	smoke.initial_velocity_min = 6.0
	smoke.initial_velocity_max = 11.0
	smoke.scale_amount_min = 1.4
	smoke.scale_amount_max = 3.0
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(tint, 0.0), Color(tint, 0.45), Color(tint.darkened(0.25), 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	smoke.color_ramp = fade
	add_child(smoke)


## A picture that hangs from a bracket and sways with the wind (rows below `pivot` slide in whole pixels, `sway_rows.gdshader`).
func _hang(path: String, at: Vector2, pivot: float, amount: float) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path) as Texture2D
	sprite.centered = false
	sprite.position = at
	if pivot >= 0.0: ## (a negative pivot: it does not sway)
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/sway_rows.gdshader") as Shader
		mat.set_shader_parameter("pivot_row", pivot) ## the bracket and the crossbar stay put
		mat.set_shader_parameter("amount", amount)
		mat.set_shader_parameter("flutter", 0.8)
		mat.set_shader_parameter("cell_w", 30.0)
		sprite.material = mat
		_sway_mats.append(mat)
	_picture.add_child(sprite)
	return sprite


## The renewed hut grows with the town (docs/town_ausbau.md A2): a second banner in a village, flags on the ridge in a borough and a town, ivy with the days.
func _refresh_town_look() -> void:
	if _town == null or not is_instance_valid(_town):
		_town = get_tree().get_first_node_in_group("town") as TownManager
	if _town == null or not _town.founded or _banner_mat == null:
		return
	var level: int = _town.level()
	var age: int = TimeManager.day - int((_town.structures.get(0, {}) as Dictionary).get("b", TimeManager.day))
	var wanted: Array[bool] = [level >= 2]
	for k: int in _flags.size():
		wanted.append(level >= 3 + k)
	var shown: Array[Sprite2D] = [_banner_left]
	shown.append_array(_flags)
	for k: int in shown.size():
		var sprite: Sprite2D = shown[k]
		if sprite != null and wanted[k] and not sprite.visible:
			sprite.visible = true
			if _town_ready: ## it unrolls from its bar
				sprite.scale = Vector2(1.0, 0.05)
				create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(sprite, "scale:y", 1.0, 0.9)
		elif sprite != null and not wanted[k]:
			sprite.visible = false
	for k: int in _ivy.size():
		_ivy[k].visible = (age >= 9) if k == 1 else (age >= 4 and age < 9)
	_town_ready = true


## The lamp light that leaves the window (an additive picture of the building's size, see hut_lib.window_spill).
func _load_spill(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	if _spill == null:
		_spill = Sprite2D.new()
		_spill.offset = _picture.offset
		var add: CanvasItemMaterial = CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_spill.material = add
		add_child(_spill)
	_spill.texture = load(path) as Texture2D


const ANIMATE_RANGE: float = 600.0 ## px: the vane, the fire and the lamp are not updated while every player is farther away

func _near_player(radius: float) -> bool:
	for player: Player in Player.all:
		if is_instance_valid(player) and player.global_position.distance_squared_to(global_position) <= radius * radius: return true
	return false

func _process(delta: float) -> void:
	if art == "cabin": ## the quest watch keeps running everywhere (it is cheap: twice a second)
		_watch -= delta
		if _watch <= 0.0:
			_watch = 0.5
			_watch_for_player()
	if not Player.all.is_empty() and not _near_player(ANIMATE_RANGE): return
	if _vane != null: ## the arrow swings round when the wind turns (it squashes through the middle), and trembles a little in a strong one
		var wind: float = WorldWind.sample(global_position).x
		if absf(wind) > 0.08:
			_vane_dir = signf(wind)
		_vane.scale.x = move_toward(_vane.scale.x, _vane_dir, delta * 2.5)
		_vane.rotation = sin(Time.get_ticks_msec() * 0.004) * 0.05 * clampf(absf(wind) * 2.0, 0.0, 1.0)
	if not _sway_mats.is_empty():
		var wind_x: float = WorldWind.sample(global_position).x
		var clock: float = Time.get_ticks_msec() * 0.001
		for mat: ShaderMaterial in _sway_mats:
			mat.set_shader_parameter("wind", wind_x)
			mat.set_shader_parameter("time", clock)
		_town_look -= delta
		if _town_look <= 0.0:
			_town_look = 1.0
			_refresh_town_look()
	_glow.modulate.a = lerpf(0.55, 1.0, TimeManager.night_amount())
	if _spill != null: ## the fire flickers: two slow waves and a quick one, a little brighter at night
		var t: float = Time.get_ticks_msec() * 0.001
		var flicker: float = 0.86 + 0.07 * sin(t * 2.3) + 0.05 * sin(t * 5.1 + 1.3) + 0.03 * sin(t * 11.7)
		_spill.modulate.a = lerpf(0.18, 1.0, TimeManager.night_amount()) * flicker


## The lumberjack's cabin notices her coming (quest step "find the cabin"): the step is done, the marker now points at the cabin itself.
func _watch_for_player() -> void:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		if player == null or not player.is_multiplayer_authority() or player.quests == null:
			continue
		if player.quests.active_step_id("lumberjack") == "find_lumberjack" and player.global_position.distance_to(global_position) < 340.0:
			player.quests.set_flag("cabin_near")
