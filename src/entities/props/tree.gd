class_name FirTree
extends WorldProp
## Every tree of the meadow: the fir, the willow (a curtain of hanging strands) and the blossom tree (see
## plants.json: `crown_shape`, `rain_colors`, `light_color`, `sway`, `pickup`, `petals`). A fir with glowing bits (lanterns, moss tips, shelf fungi, violet veins). The sheet's rows 2 and 3
## hold only those, drawn unshaded in two child sprites that follow the trunk and the crown (so they
## fade with the crown): dim by day, bright at night, with a soft teal light pool on the ground under
## the bigger trees. The crown sways gently in the wind all the time. The trunk is solid; the crown is a second sprite on top, high above the ground on the big
## trees. You can walk right in under a giant: the whole tree (trunk, crown and glow) only fades away
## while it really hides someone, that is while a player stands behind the tree and the trunk or the
## crown is drawn over him (checked on the screen, so you never lose a friend or yourself behind it).
## Chopped with the axe (hits drop wood, the last one fells it) it leaves a stump, and over the days
## a sapling and a young tree grow back (state "f" = felled, "h" counts the regrowth back from the
## full slots; see `WorldLevel._grow_things`).

const NEEDLES: Array[Color] = [Color("3a8564"), Color("5ea97d"), Color("2a6650")] ## what falls from a hit tree (plants.json `rain_colors` for other kinds)
const FADE_ALPHA: float = 0.28
const WATCH_DISTANCE: float = 260.0 ## px: only players this close are checked
const BODY_HEIGHTS: Array[float] = [4.0, 26.0, 50.0] ## where her body is tested against the crown (px above her feet)
const BODY_WIDTHS: Array[float] = [-6.0, 0.0, 6.0]
const SWAY_RATE: float = 22.0 ## rad/s of the shake after a hit
const FALL_ANGLE: float = 1.42 ## rad: a felled tree lies almost flat
const FEET_ROW: float = 196.0 ## the sheet's frame row of the tree's base (art_tree.py)
const BARK: Array[Color] = [Color("8a6f78"), Color("5a4556"), Color("3a2c40")]
const DUST: Array[Color] = [Color("a89c96"), Color("7a6f70"), Color("5a4f50")]
const REGROW_BURST: Array[Color] = [Color("d9c8ff"), Color("78f4e6")]
const IDLE_SWAY: float = 0.009 ## skew of the crown in the wind
const LIGHT_COLOR: Color = Color("6fe6d6")
const PETAL_PICKED_ROW: int = 4 ## blossom sheet: the crown with the blossoms picked (glow: row 5)

var _covering: bool = false ## the tree currently hides a player
var _cover_wait: float = 0.0 ## seconds until the next covering test
var _fade: Tween
var _wobble: float = 0.0 ## sway amplitude, dies out
var _wobble_dir: float = 1.0
var _wobble_time: float = 0.0
var _falling: bool = false
var _fall: Node2D ## the part that falls: trunk above the cut and the crown, hinged at the stump
var _fall_crown: Sprite2D
var _idle_phase: float = 0.0
var _night: float = 0.0
var _light: NightLight
var _petals: CPUParticles2D ## blossom trees: petals drift down all the time
var _tree_top: float = 0.0
var _tree_clear: float = 0.0
var _tree_half: float = 0.0
var _tree_trunk_half: float = 0.0
var _tree_sway: float = 0.0
var _feet_row: float = FEET_ROW
var _frame_w: float = 112.0
var _ground_fruit: Sprite2D
var _crown_shape_name: String = "cone"
var _crown_dome_height: float = 0.0
var _fades_crown: bool = true
var _on_screen: bool = true
var _notifier: VisibleOnScreenNotifier2D
var _vines: Sprite2D ## plants.json `vines`: ropes hanging from the crown that breathe (vine_breathe.gdshader), with their buds' light as a child
var _vine_glow: Sprite2D
var _twitches: bool = false ## plants.json `twitch`
var _twitch_wait: float = 0.0 ## seconds until the dead tree next jerks and creaks
var _creak: AudioStreamPlayer2D
static var _vine_material: ShaderMaterial
static var _vine_glow_material: ShaderMaterial

@onready var _crown: Sprite2D = $Crown
@onready var _trunk_glow: Sprite2D = $Sprite/Glow
@onready var _crown_glow: Sprite2D = $Crown/Glow
@onready var _body_shape: CollisionShape2D = $Body/Shape


func _setup_prop() -> void:
	add_to_group("bird_perches")
	add_to_group("day_canopies")
	_feet_row = float(_spec.get("feet_row", FEET_ROW))
	var base_tex: Texture2D = load(String(_spec.texture)) as Texture2D
	if base_tex != null:
		_frame_w = float(base_tex.get_width()) / float(maxi(int(_spec.columns), 1))
	var dyn_offset: Vector2 = Vector2(-_frame_w * 0.5, -_feet_row)
	_sprite.offset = dyn_offset
	_trunk_glow.offset = dyn_offset
	_crown.offset = dyn_offset
	_crown_glow.offset = dyn_offset
	if _spec.has("ground_fruit"):
		var gtex: Texture2D = load(String(_spec.ground_fruit)) as Texture2D
		if gtex != null:
			_ground_fruit = Sprite2D.new()
			_ground_fruit.texture = gtex
			_ground_fruit.hframes = int(_spec.get("ground_fruit_columns", 6))
			_ground_fruit.vframes = 1
			_ground_fruit.frame = int(_spec.get("ground_fruit_offset", 0)) + (variant % maxi(int(_spec.columns), 1))
			_ground_fruit.centered = false
			var fw_g: float = float(gtex.get_width()) / float(maxi(_ground_fruit.hframes, 1))
			_ground_fruit.offset = Vector2(-fw_g * 0.5, -float(_spec.get("ground_fruit_feet", 18.0)))
			_ground_fruit.material = _day_material()
			add_child(_ground_fruit)
			move_child(_ground_fruit, 0)
	_crown.material = _day_material()
	_tree_top = float((_spec.height as Array)[variant])
	_tree_clear = float((_spec.clear as Array)[variant])
	_tree_half = float((_spec.crown_half_width as Array)[variant])
	_tree_trunk_half = float((_spec.trunk_half_width as Array)[variant])
	_tree_sway = _wind_exposure * float(_spec.get("sway", IDLE_SWAY))
	_crown_shape_name = String(_spec.get("crown_shape", "cone"))
	_crown_dome_height = float((_spec.dome_height as Array)[variant]) if _spec.has("dome_height") else 0.0
	_fades_crown = bool((_spec.crown_fade as Array)[variant])
	var trunk: RectangleShape2D = RectangleShape2D.new()
	trunk.size = Vector2(_tree_trunk_half * 2.0 + 3.0, 6.0)
	_body_shape.shape = trunk
	_body_shape.position = Vector2(0, -3)
	_idle_phase = fposmod(position.x * 0.37 + position.y * 0.11, TAU)
	_trunk_glow.material = Unlit.material()
	_crown_glow.material = Unlit.material()
	_notifier = VisibleOnScreenNotifier2D.new()
	var rect_w: float = (_tree_half + 16.0) * 2.0
	var rect_h: float = _tree_top + 24.0
	_notifier.rect = Rect2(-rect_w * 0.5, -_tree_top - 16.0, rect_w, rect_h)
	_notifier.screen_entered.connect(func() -> void: _on_screen = true)
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(_notifier)
	if variant >= int(_spec.get("light_from", 2)): ## a soft pool of light on the ground under the bigger trees (only those: woods have many trees)
		_light = NightLight.new()
		_light.radius = int(_tree_half * 0.85)
		_light.squash = 0.55
		_light.base_energy = float(_spec.get("light_energy", 0.28)) + 0.05 * variant
		_light.glow_color = Color(String(_spec.get("light_color", "#6fe6d6")))
		_light.pulse = 0.2
		_light.position = Vector2(0, -3)
		add_child(_light)
	if bool(_spec.get("fireflies", false)):
		add_to_group("flora_glow") ## the fireflies gather here (see Fireflies)
	if _spec.has("vines"):
		_make_vines()
	_twitches = _spec.has("twitch")
	if _twitches:
		_twitch_wait = _twitch_delay() * randf_range(0.3, 1.0)
	if _spec.has("petals"):
		_make_petals()
	add_to_group("night_lights") ## DayNight tells every night light and this tree how dark it is
	set_night(TimeManager.night_amount())


## Hexenulme: ropes of ivy hang from the hem of the crown and sway slowly with a breath of their own (children of the crown, so they
## fade and fall with it); the buds at some of their tips glow on an unlit child, dim by day like the other glow.
func _make_vines() -> void:
	if _vine_material == null:
		_vine_material = ShaderMaterial.new()
		_vine_material.shader = load("res://assets/shaders/vine_breathe.gdshader") as Shader
		_vine_glow_material = ShaderMaterial.new()
		_vine_glow_material.shader = load("res://assets/shaders/vine_breathe_glow.gdshader") as Shader
		_vine_glow_material.set_shader_parameter("mask_rows", -1.0 / 3.0)
	var sheet: Texture2D = load(String(_spec.vines)) as Texture2D
	_vines = Sprite2D.new()
	_vines.centered = false
	_vines.offset = _crown.offset
	_vines.texture = sheet
	_vines.hframes = int(_spec.columns)
	_vines.vframes = 3
	_vines.frame = variant
	_vines.material = _vine_material
	_crown.add_child(_vines)
	_vine_glow = Sprite2D.new()
	_vine_glow.centered = false
	_vine_glow.offset = _crown.offset
	_vine_glow.texture = sheet
	_vine_glow.hframes = int(_spec.columns)
	_vine_glow.vframes = 3
	_vine_glow.frame = variant + 2 * int(_spec.columns)
	_vine_glow.material = _vine_glow_material
	_vines.add_child(_vine_glow)


func _twitch_delay() -> float:
	var every: Array = (_spec.twitch as Dictionary).get("every", [8.0, 22.0])
	return randf_range(float(every[0]), float(every[1]))


## Bleichbaum: now and then the dead tree jerks as if something moved inside it, and creaks (only heard close by; purely local, every peer
## on its own clock: nothing depends on it).
func _twitch(delta: float) -> void:
	_twitch_wait -= delta
	if _twitch_wait > 0.0:
		return
	_twitch_wait = _twitch_delay()
	if is_depleted() or not _on_screen:
		return
	var twitch: Dictionary = _spec.twitch
	_wobble = maxf(_wobble, float(twitch.get("amount", 0.3)))
	_wobble_time = 0.0
	_wobble_dir = 1.0 if randf() < 0.5 else -1.0
	var sounds: Array = twitch.get("sounds", [])
	if sounds.is_empty():
		return
	if _creak == null:
		_creak = AudioStreamPlayer2D.new()
		_creak.max_distance = 320.0
		_creak.position = Vector2(0, -_tree_clear)
		add_child(_creak)
	_creak.stream = load(String(sounds[randi() % sounds.size()])) as AudioStream
	var volume: float = float(GameSettings.get_value("sfx")) / 100.0 ## the effects volume, like the birds' calls
	if volume <= 0.001:
		return
	_creak.volume_db = float(twitch.get("volume_db", -16.0)) + linear_to_db(volume)
	_creak.pitch_scale = randf_range(0.85, 1.12)
	_creak.play()


## Blossom trees: a few petals drift down from the crown all the time (unshaded, so they stay bright at night).
func _make_petals() -> void:
	var half: float = float((_spec.crown_half_width as Array)[variant])
	var clear: float = float((_spec.clear as Array)[variant])
	var colors: Array[Color] = _colors(_spec.petals as Array)
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([colors[0], colors[colors.size() - 1], Color(colors[colors.size() - 1], 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	_petals = CPUParticles2D.new()
	_petals.texture = SPARKS
	_petals.color_ramp = gradient
	_petals.material = Unlit.material()
	_petals.amount = 3 + variant * 2
	_petals.lifetime = 6.0
	_petals.preprocess = 3.0
	_petals.local_coords = false
	_petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_petals.emission_rect_extents = Vector2(half * 0.7, 3.0)
	_petals.position = Vector2(0, -(clear + (_height - clear) * 0.3))
	_petals.direction = Vector2.DOWN
	_petals.spread = 50.0
	_petals.initial_velocity_min = 1.0
	_petals.initial_velocity_max = 5.0
	_petals.gravity = Vector2(randf_range(2.0, 7.0), 9.0)
	_petals.scale_amount_min = 0.5
	_petals.scale_amount_max = 0.9
	_petals.z_index = 1
	add_child(_petals)


func _colors(hexes: Array) -> Array[Color]:
	var colors: Array[Color] = []
	for hex: Variant in hexes:
		colors.append(Color(String(hex)))
	return colors


## DayNight: how dark it is (0..1). The glowing parts brighten with it (NightLight does the same on its own).
func set_night(amount: float) -> void:
	_night = amount
	var alpha: float = lerpf(GLOW_BY_DAY, 1.0, amount)
	_trunk_glow.modulate.a = alpha
	_crown_glow.modulate.a = alpha
	if _vine_glow != null:
		_vine_glow.modulate.a = alpha


## A felled tree and its regrowth cannot be chopped again until it is whole.
func is_depleted() -> bool:
	return state.has("f")


## Blossom trees: E picks the blossoms (the crown shows green with a few left, back after a few days).
func prompt() -> String:
	if not opening_locked() and _spec.has("pickup") and not is_depleted() and not _picked():
		return String((_spec.pickup as Dictionary).prompt)
	return ""


func _picked() -> bool:
	return bool(state.get("p", 0))


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + Vector2(0, -3)) - _radius * 0.5


func prompt_position() -> Vector2:
	return Vector2(0, -float((_spec.clear as Array)[variant]) - 10.0)


func interact(player: Player) -> void:
	var toward: Vector2 = global_position - player.global_position
	player.begin_pick(toward.normalized() if toward.length() > 1.0 else player.facing, func() -> void: level.request_pick(cell))


func apply_state(new_state: Dictionary, fx: String) -> void:
	state = new_state
	if _falling: ## a fall in progress is not interrupted; its end shows the stump
		return
	if fx == "strip":
		_fell()
		return
	_show()
	match fx:
		"rustle":
			_shake(0.3)
		"hit":
			_shake(1.0)
			_needle_rain(9)
			_burst(6, BARK, 34.0, Vector2(0, -16))
			Sfx.at(self, "axe_chop", global_position, -2.0, 0.06)
		"regrow":
			_burst(6, REGROW_BURST, 0.0, Vector2(0, -12))
		"pick":
			_shake(0.6)
			_needle_rain(16)
			Sfx.at(self, "pluck", global_position, -3.0)
	if _prompt_node != null:
		set_focused(_prompt_node.visible)


func _process(delta: float) -> void:
	if _falling:
		return
	if _twitches:
		_twitch(delta)
	if not _on_screen and _wobble <= 0.002 and not _covering:
		return
	_sway(delta)
	if not _crown.visible or not _fades():
		return
	# The covering test runs at about 10 Hz; the result (and the fade tween) is kept between checks.
	_cover_wait -= delta
	if _cover_wait > 0.0: return
	_cover_wait = 0.1
	var covering: bool = false
	for player: Player in Player.all:
		if player.global_position.distance_to(global_position) < WATCH_DISTANCE and _covers((player.global_position - global_position) / scale.x):
			covering = true
			break
	if covering != _covering:
		_covering = covering
		if _fade != null:
			_fade.kill()
		_fade = create_tween().set_parallel(true)
		_fade.tween_property(_crown, "modulate:a", FADE_ALPHA if _covering else 1.0, 0.18)
		_fade.tween_property(_sprite, "modulate:a", FADE_ALPHA if _covering else 1.0, 0.18)


## A hit shakes the tree: the crown sways far, the trunk hardly, first away from whoever hit it.
func _shake(amount: float) -> void:
	_wobble = maxf(_wobble, amount)
	_wobble_time = 0.0
	_wobble_dir = _away_from_player()


func _sway(delta: float) -> void:
	var idle: float = WorldWind.sample(global_position).x * _tree_sway
	if _wobble <= 0.002:
		_crown.skew = idle
		return
	_wobble_time += delta
	var swing: float = sin(_wobble_time * SWAY_RATE) * _wobble * _wobble_dir
	_crown.rotation = swing * 0.05
	_crown.skew = swing * 0.03 + idle
	_sprite.rotation = swing * 0.012
	_wobble *= exp(-4.2 * delta)
	if _wobble <= 0.002:
		_wobble = 0.0
		_crown.rotation = 0.0
		_crown.skew = idle
		_sprite.rotation = 0.0


## +1 / -1: the side away from the nearest player (where a hit pushes the tree, and where it falls).
func _away_from_player() -> float:
	var nearest: Player = null
	var nearest_d2: float = INF
	for player: Player in Player.all:
		var d2: float = player.global_position.distance_squared_to(global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = player
	if nearest == null or absf(nearest.global_position.x - global_position.x) < 2.0:
		return 1.0 if randf() < 0.5 else -1.0
	return signf(global_position.x - nearest.global_position.x)


## Needles come loose from the crown and drift down.
func _needle_rain(count: int) -> void:
	var half: float = float((_spec.crown_half_width as Array)[variant])
	var clear: float = float((_spec.clear as Array)[variant])
	var crown_h: float = _height - clear
	var rain: CPUParticles2D = CPUParticles2D.new()
	var gradient: Gradient = Gradient.new()
	var colors: Array[Color] = _colors(_spec.rain_colors as Array) if _spec.has("rain_colors") else NEEDLES
	gradient.colors = PackedColorArray([colors[1], colors[0], Color(colors[2], 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	rain.texture = SPARKS
	rain.color_ramp = gradient
	rain.one_shot = true
	rain.explosiveness = 0.5
	rain.amount = count
	rain.lifetime = 1.7
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(half * 0.75, crown_h * 0.3)
	rain.position = Vector2(0, -(clear + crown_h * 0.42))
	rain.direction = Vector2.DOWN
	rain.spread = 28.0
	rain.initial_velocity_min = 4.0
	rain.initial_velocity_max = 18.0
	rain.gravity = Vector2(randf_range(-8.0, 8.0), 42.0)
	rain.scale_amount_min = 0.35
	rain.scale_amount_max = 0.6
	rain.emitting = true
	add_child(rain)
	rain.finished.connect(rain.queue_free)


## Is a player at `feet` (relative to the tree's base) hidden by the tree? Only when he is behind it
## (the tree is drawn over him) and a point of his body lies inside the trunk or the crown. The crown is
## a cone (firs: widest at the bottom of the crown), a dome (blossom trees: an ellipse) or a curtain
## (willows: a dome with strands hanging straight down to the ground), see plants.json `crown_shape`.
func _covers(feet: Vector2) -> bool:
	if feet.y >= 0.0:
		return false
	var top: float = _tree_top
	var clear: float = _tree_clear
	var half: float = _tree_half
	var trunk_half: float = _tree_trunk_half
	for up: float in BODY_HEIGHTS:
		var y: float = feet.y - up ## negative: above the base on the screen
		if y > 0.0 or y < -top:
			continue
		for side: float in BODY_WIDTHS:
			var x: float = absf(feet.x + side)
			if y >= -(clear + 10.0) and x <= trunk_half + 2.0:
				return true
			if y <= -clear and x <= _crown_reach(y, top, clear, half):
				return true
	return false


## How far the crown reaches to the side at height `y` (negative, above the base).
func _crown_reach(y: float, top: float, clear: float, half: float) -> float:
	match _crown_shape_name:
		"dome":
			var middle: float = -(top + clear) / 2.0
			var radius: float = (top - clear) / 2.0
			return half * sqrt(maxf(1.0 - pow((y - middle) / radius, 2.0), 0.0)) + 2.0
		"curtain":
			var dome: float = _crown_dome_height
			if y > -(top - dome): ## the strands hang from the dome's rim down to the ground
				return half * 0.92
			var middle: float = -(top - dome * 0.55)
			return half * sqrt(maxf(1.0 - pow((y - middle) / (dome * 0.6), 2.0), 0.0)) + 2.0
	return half * (top + y) / (top - clear) + 2.0 ## the cone is widest at the bottom of the crown


func _show() -> void:
	var felled: bool = is_depleted()
	_sprite.rotation = 0.0
	_crown.rotation = 0.0
	_sprite.modulate.a = FADE_ALPHA if _covering and not felled else 1.0
	_sprite.hframes = int(_spec.columns)
	if felled:
		var progress: float = float(slots() - int(state.get("h", 0))) / float(slots())
		_sprite.texture = load(String(_spec.growth)) as Texture2D
		_sprite.vframes = 1
		_sprite.frame = (0 if variant < 2 else 1) if progress <= 0.0 else (2 if progress < 0.5 else 3)
		_crown.visible = false
		_trunk_glow.visible = false
		if _light != null:
			_light.visible = false
		if _petals != null:
			_petals.emitting = false
		if _ground_fruit != null:
			_ground_fruit.visible = false
	else:
		_sprite.texture = load(String(_spec.texture)) as Texture2D
		_sprite.vframes = int(_spec.rows)
		_sprite.frame = variant
		_crown.texture = _sprite.texture
		_crown.hframes = _sprite.hframes
		_crown.vframes = _sprite.vframes
		var picked: bool = _picked() and _spec.has("pickup")
		if _ground_fruit != null:
			_ground_fruit.visible = not picked
		_crown.frame = variant + int(_spec.columns) * (PETAL_PICKED_ROW if picked else 1)
		_crown.visible = true
		_crown.modulate.a = FADE_ALPHA if _covering else 1.0
		for glow: Sprite2D in [_trunk_glow, _crown_glow]:
			glow.texture = _sprite.texture
			glow.hframes = _sprite.hframes
			glow.vframes = _sprite.vframes
			glow.visible = true
		_trunk_glow.frame = variant + 3 * int(_spec.columns)
		_crown_glow.frame = variant + int(_spec.columns) * (PETAL_PICKED_ROW + 1 if picked else 2)
		if _light != null:
			_light.visible = true
			if _spec.has("pickup"):
				_light.base_energy = (float(_spec.get("light_energy", 0.28)) + 0.05 * variant) * (0.25 if picked else 1.0)
				_light.set_night(TimeManager.night_amount())
		if _petals != null:
			_petals.emitting = not picked
	_body_shape.set_deferred("disabled", felled)
	_hurtbox.set_deferred("monitorable", not felled)


func _fades() -> bool:
	return _fades_crown


## The fall: the trunk is chopped through at the stump, which stays with its shadow. Only the part
## above the cut falls: it cracks (a shudder, bark and needles fly), topples away from the hitter
## around the cut and speeds up, hits the ground (dust, a bounce, the screen shakes), lies there a
## moment and fades; the stump is all that is left.
func _fell() -> void:
	_falling = true
	Sfx.at(self, "tree_fall", global_position, 0.0, 0.03, 480.0)
	_wobble = 0.0
	_covering = false
	if _fade != null:
		_fade.kill()
	_sprite.modulate.a = 1.0
	var dir: float = _away_from_player()
	var cut: float = 8.0 if variant < 2 else 13.0 ## the stump's height in px
	var seconds: float = 0.9 + _height / 230.0
	_body_shape.set_deferred("disabled", true)
	_hurtbox.set_deferred("monitorable", false)
	_sprite.rotation = 0.0
	_crown.rotation = 0.0
	_crown.skew = 0.0
	_crown.visible = false
	_trunk_glow.visible = false
	if _light != null:
		_light.visible = false
	if _petals != null:
		_petals.emitting = false
	if _ground_fruit != null:
		_ground_fruit.visible = false
	var sheet: Texture2D = load(String(_spec.texture)) as Texture2D
	var frame_w: float = sheet.get_width() / float(_spec.columns)
	var frame_h: float = sheet.get_height() / float(_spec.rows)
	_fall = Node2D.new()
	_fall.position = Vector2(0, -cut)
	add_child(_fall)
	var trunk_piece: Sprite2D = _piece(sheet, Rect2(variant * frame_w, 0.0, frame_w, _feet_row - cut + 1.0), frame_w, cut) ## trunk above the cut
	_fall.add_child(trunk_piece)
	trunk_piece.add_child(_glow_piece(sheet, Rect2(variant * frame_w, 3.0 * frame_h, frame_w, _feet_row - cut + 1.0), frame_w, cut))
	_fall_crown = _piece(sheet, Rect2(variant * frame_w, frame_h, frame_w, frame_h), frame_w, cut)
	_fall.add_child(_fall_crown)
	_fall_crown.add_child(_glow_piece(sheet, Rect2(variant * frame_w, 2.0 * frame_h, frame_w, frame_h), frame_w, cut))
	_needle_rain(28)
	_burst(14, BARK, 46.0, Vector2(0, -cut))
	var tween: Tween = create_tween()
	tween.tween_method(_shudder.bind(dir), 0.0, 1.0, 0.32)
	tween.tween_callback(_cut_through)
	tween.tween_method(_topple.bind(dir), 0.0, 1.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_impact.bind(dir))
	tween.tween_method(_bounce.bind(dir), 0.0, 1.0, 0.4)
	tween.tween_interval(0.7)
	tween.tween_callback(_fade_out)


## The trunk gives way: from here the stump stands where the trunk was.
func _cut_through() -> void:
	_sprite.texture = load(String(_spec.growth)) as Texture2D
	_sprite.hframes = int(_spec.columns)
	_sprite.vframes = 1
	_sprite.frame = 0 if variant < 2 else 1


## A piece of the tree sheet as its own sprite, standing where it stood before (its parent sits at the cut).
func _piece(sheet: Texture2D, region: Rect2, frame_w: float, cut: float) -> Sprite2D:
	var piece: Sprite2D = Sprite2D.new()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	piece.texture = atlas
	piece.centered = false
	piece.offset = Vector2(-frame_w / 2.0, -_feet_row + cut)
	return piece


## The glowing part of a falling piece: lies exactly over it and falls with it.
func _glow_piece(sheet: Texture2D, region: Rect2, frame_w: float, cut: float) -> Sprite2D:
	var glow: Sprite2D = _piece(sheet, region, frame_w, cut)
	glow.material = Unlit.material()
	glow.modulate.a = lerpf(GLOW_BY_DAY, 1.0, _night)
	return glow


func _shudder(t: float, dir: float) -> void:
	var swing: float = sin(t * 48.0) * (1.0 - t) * 0.02
	_fall.rotation = swing * 1.5 + dir * 0.02 * t
	_fall_crown.rotation = swing + dir * 0.01 * t


func _topple(t: float, dir: float) -> void:
	_fall.rotation = dir * (0.02 + (FALL_ANGLE - 0.02) * t)
	_fall_crown.rotation = _fall.rotation * 0.02
	_fall_crown.skew = dir * 0.05 * t * (1.0 - t) ## the crown flexes a little as it goes


func _impact(dir: float) -> void:
	var landing: Vector2 = Vector2(dir * _height * 0.62, -3)
	_burst(18, DUST, 56.0, landing)
	_needle_rain(30)
	for player: Player in Player.all:
		if player.global_position.distance_to(global_position) < 360.0:
			player.add_shake(clampf(_height / 36.0, 2.0, 5.0))


func _bounce(t: float, dir: float) -> void:
	_fall.rotation = dir * (FALL_ANGLE - 0.15 * sin(t * PI) * (1.0 - t))
	_fall_crown.skew = 0.0


func _fade_out() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fall, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_finish_fall)


func _finish_fall() -> void:
	_fall.queue_free()
	_fall = null
	_falling = false
	_show()


## World-ground canopy projection; independent of the visibility fade for actors behind a crown.
func day_canopy() -> Vector4:
	if is_depleted() or _falling: return Vector4.ZERO
	var half: float = _tree_half * absf(global_scale.x)
	var height: float = _tree_top * absf(global_scale.y)
	var center: Vector2 = global_position + Vector2(height * 0.22, height * 0.10)
	return Vector4(center.x, center.y, maxf(8.0, half * 1.05), maxf(6.0, half * 0.62))
