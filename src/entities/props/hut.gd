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
	for x: float in ([-62.0, 10.0, 62.0] if art == "hut" else []): ## birds on the ridge (the renewed one has a vane, the chimney stands left of the middle)
		var perch: RoofPerch = RoofPerch.new()
		perch.host = self
		perch.perch_height = 86.0
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
		_vane.position = Vector2(36.0, -82.0)
		_picture.add_child(_vane) ## a child of the picture: drawn right after the roof it stands on (as a child of the y-sorting hut it would sort behind it)
	if _window_light != null: ## the real light: bigger, warmer, flickers like the fire behind the glass
		_window_light.position = Vector2(36, 12)
		_window_light.radius = 56
		_window_light.base_energy = 0.62
		_window_light.pulse = 0.3


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


func _process(delta: float) -> void:
	if _vane != null: ## the arrow swings round when the wind turns (it squashes through the middle), and trembles a little in a strong one
		var wind: float = WorldWind.sample(global_position).x
		if absf(wind) > 0.08:
			_vane_dir = signf(wind)
		_vane.scale.x = move_toward(_vane.scale.x, _vane_dir, delta * 2.5)
		_vane.rotation = sin(Time.get_ticks_msec() * 0.004) * 0.05 * clampf(absf(wind) * 2.0, 0.0, 1.0)
	_glow.modulate.a = lerpf(0.55, 1.0, TimeManager.night_amount())
	if _spill != null: ## the fire flickers: two slow waves and a quick one, a little brighter at night
		var t: float = Time.get_ticks_msec() * 0.001
		var flicker: float = 0.86 + 0.07 * sin(t * 2.3) + 0.05 * sin(t * 5.1 + 1.3) + 0.03 * sin(t * 11.7)
		_spill.modulate.a = lerpf(0.18, 1.0, TimeManager.night_amount()) * flicker
	if art == "cabin":
		_watch -= delta
		if _watch <= 0.0:
			_watch = 0.5
			_watch_for_player()


## The lumberjack's cabin notices her coming (quest step "find the cabin"): the step is done, the marker now points at the cabin itself.
func _watch_for_player() -> void:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		if player == null or not player.is_multiplayer_authority() or player.quests == null:
			continue
		if String(player.quests.current().get("step_id", "")) == "find_lumberjack" and player.global_position.distance_to(global_position) < 340.0:
			player.quests.set_flag("cabin_near")
