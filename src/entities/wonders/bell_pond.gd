class_name BellPond
extends Node2D
## Unique Meadow World Wonder 1 (`docs/wiesenbiom_ausbau_konzept.md` Stufe 5.1): **Der Glockenteich**.
## Out of the middle of a quiet forest lake rises the weathered stone-and-verdigris spire of a sunken bell tower (`bell_spire.png` `96x160`).
##  - **By day:** two turquoise kingfishers perch peacefully on the spire roof and dart low across the water when approached.
##  - **On clear nights around midnight (`22:20 – 01:55`):** the submerged bronze bell tolls once with a deep underwater resonance
##    (`bell_underwater.wav`), expanding luminous turquoise ripples across the lake, and **6 mossy stepping stones** (`bell_stepping_stone.png`)
##    rise between shore `[795, 525]` and spire `[801, 525]`, forming a dry `"stone"` causeway (`deck_rects`) straight to the belfry!
##  - Stepping onto the spire platform or ringing/touching the belfry altar awakens the wonder permanently (keeping the causeway walkable
##    once discovered so nobody is ever stranded!) and raises a legendary `LootChest` carrying the `bell_chime_talisman` (*Glockenteich-Gehänge*)!

const SPIRE_TEX: String = "res://assets/props/bell_spire.png"
const SPIRE_GLOW: String = "res://assets/props/bell_spire_glow.png"
const STONE_TEX: String = "res://assets/props/bell_stepping_stone.png"
const STONE_GLOW: String = "res://assets/props/bell_stepping_stone_glow.png"
const BELL_WAV: String = "res://assets/audio/meadow_wonders/bell_underwater.wav"

var wonders: MeadowWonders
var wonder_id: String = "wonder_bell_pond"
var shore_pos: Vector2 = Vector2.ZERO
var spire_pos: Vector2 = Vector2.ZERO
var chest_tier: String = "legendary"
var awakened: bool = false ## permanently awakened by player reaching the spire
var stones_risen: bool = false ## true during clear midnight window OR once awakened

var _spire_body: Sprite2D
var _spire_glow: Sprite2D
var _spire_light: NightLight
var _stones: Array[Sprite2D] = []
var _stone_glows: Array[Sprite2D] = []
var _stone_positions: Array[Vector2] = []
var _deck_rects: Array[Rect2] = []
var _fx_canvas: Node2D
var _altar: BelfryAltar

var _time: float = 0.0
var _toll_age: float = 99.0
var _tolled_this_night: bool = false
var _bird_flight: float = 0.0 ## 0 perched on spire roof, >0 darting gracefully across water


func setup(owner_wonders: MeadowWonders, spec: Dictionary) -> void:
	wonders = owner_wonders
	wonder_id = String(spec.get("id", "wonder_bell_pond"))
	chest_tier = String(spec.get("chest_tier", "legendary"))
	var st: Array = spec.get("shore_tile", [795, 525]) as Array
	var sp: Array = spec.get("spire_tile", [801, 525]) as Array
	shore_pos = Vector2(float(st[0]), float(st[1])) * 16.0 + Vector2(8.0, 8.0)
	spire_pos = Vector2(float(sp[0]), float(sp[1])) * 16.0 + Vector2(8.0, 8.0)
	position = shore_pos
	_build_causeway_geometry()


func _build_causeway_geometry() -> void:
	_stone_positions.clear()
	_deck_rects.clear()
	var span: Vector2 = spire_pos - shore_pos
	var steps: int = 6
	for i: int in steps:
		var t: float = float(i + 1) / float(steps + 1)
		var pt: Vector2 = (shore_pos + span * t).round()
		_stone_positions.append(pt)
	# Continuous overlapping stone deck from shore to spire platform when risen!
	var min_x: float = minf(shore_pos.x, spire_pos.x) - 14.0
	var max_x: float = maxf(shore_pos.x, spire_pos.x) + 28.0
	var mid_y: float = (shore_pos.y + spire_pos.y) * 0.5
	_deck_rects.append(Rect2(min_x, mid_y - 13.0, max_x - min_x, 26.0))
	# Spire belfry platform itself (48x30 around spire_pos)
	_deck_rects.append(Rect2(spire_pos.x - 24.0, spire_pos.y - 14.0, 52.0, 30.0))


func contains_deck_point(world_pt: Vector2) -> bool:
	if not stones_risen and not awakened:
		return false
	for r: Rect2 in _deck_rects:
		if r.has_point(world_pt):
			return true
	return false


func is_midnight_clear() -> bool:
	var tod: float = TimeManager.time_of_day
	var in_window: bool = tod >= 0.93 or tod <= 0.08
	if not in_window:
		return false
	if WeatherManager.current != null and WeatherManager.current.rain > 0.25:
		return false
	return true


func _ready() -> void:
	add_to_group("flora_glow")
	z_index = -3

	# Stepping stones along water surface
	var st_tex: Texture2D = load(STONE_TEX) as Texture2D if ResourceLoader.exists(STONE_TEX) else null
	var st_glw: Texture2D = load(STONE_GLOW) as Texture2D if ResourceLoader.exists(STONE_GLOW) else null
	for i: int in _stone_positions.size():
		var local_pt: Vector2 = _stone_positions[i] - position
		var sp: Sprite2D = Sprite2D.new()
		if st_tex != null:
			sp.texture = st_tex
			sp.hframes = 3
		sp.position = local_pt
		sp.offset = Vector2(0.0, -2.0)
		add_child(sp)
		_stones.append(sp)

		var gl: Sprite2D = Sprite2D.new()
		if st_glw != null:
			gl.texture = st_glw
			gl.hframes = 3
		gl.position = local_pt
		gl.offset = Vector2(0.0, -2.0)
		gl.material = Unlit.material()
		add_child(gl)
		_stone_glows.append(gl)

	# Sunken Bell Spire (anchor 48, 136 inside 96x160)
	var spire_local: Vector2 = spire_pos - position
	var spire_off: Vector2 = Vector2(0.0, -(136.0 - 80.0))
	if ResourceLoader.exists(SPIRE_TEX):
		_spire_body = Sprite2D.new()
		_spire_body.texture = load(SPIRE_TEX) as Texture2D
		_spire_body.hframes = 2
		_spire_body.position = spire_local
		_spire_body.offset = spire_off
		_spire_body.z_index = 3 ## sorts cleanly as a tall spire
		add_child(_spire_body)
	if ResourceLoader.exists(SPIRE_GLOW):
		_spire_glow = Sprite2D.new()
		_spire_glow.texture = load(SPIRE_GLOW) as Texture2D
		_spire_glow.hframes = 2
		_spire_glow.position = spire_local
		_spire_glow.offset = spire_off
		_spire_glow.z_index = 3
		_spire_glow.material = Unlit.material()
		add_child(_spire_glow)

	_spire_light = NightLight.new()
	_spire_light.position = spire_local + Vector2(0.0, -48.0)
	_spire_light.radius = 92
	_spire_light.base_energy = 0.48
	_spire_light.pulse = 0.16
	_spire_light.glow_color = Color("6cf5e8")
	add_child(_spire_light)

	_fx_canvas = Node2D.new()
	_fx_canvas.z_index = 4
	_fx_canvas.material = Unlit.material()
	_fx_canvas.draw.connect(_draw_fx)
	add_child(_fx_canvas)

	_altar = BelfryAltar.new()
	_altar.setup(self, spire_local + Vector2(-10.0, 2.0))
	add_child(_altar)

	_refresh_visuals()


func set_awakened_instant(val: bool) -> void:
	awakened = val
	if val:
		stones_risen = true
		var chests: LootChests = LootChests.of(get_tree())
		if chests != null:
			var cid: String = wonder_id + "_chest"
			chests.place(cid, chest_tier, spire_pos + Vector2(14.0, 6.0), true)
			if multiplayer.is_server() and not chests.is_open(cid) and DataRegistry.table("items").has("bell_chime_talisman"):
				chests.add_extra(cid, [{"id": "bell_chime_talisman", "count": 1}])
	_refresh_visuals()


func play_awaken_fx() -> void:
	awakened = true
	stones_risen = true
	_toll_bell()
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		var cid: String = wonder_id + "_chest"
		if multiplayer.is_server() and DataRegistry.table("items").has("bell_chime_talisman"):
			chests.add_extra(cid, [{"id": "bell_chime_talisman", "count": 1}])
		chests.appear(cid, chest_tier, spire_pos + Vector2(14.0, 6.0), true, true, true)
	_refresh_visuals()


func _toll_bell() -> void:
	_toll_age = 0.0
	if ResourceLoader.exists(BELL_WAV):
		var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		snd.stream = load(BELL_WAV) as AudioStream
		snd.bus = "SFX"
		snd.volume_db = -2.0
		snd.max_distance = 680.0
		snd.finished.connect(snd.queue_free)
		snd.position = spire_pos - position
		add_child(snd)
		snd.play()


func _refresh_visuals() -> void:
	var active: bool = stones_risen or awakened
	if _spire_body != null:
		_spire_body.frame = 1 if active else 0
	if _spire_glow != null:
		_spire_glow.frame = 1 if active else 0
	for i: int in _stones.size():
		var col: int = (1 + (i % 2)) if active else 0
		_stones[i].frame = col
		_stone_glows[i].frame = col
		_stone_glows[i].visible = active
	if _spire_light != null:
		_spire_light.base_energy = 0.85 if active else 0.36
		_spire_light.radius = 112 if active else 72


func _process(delta: float) -> void:
	_time += delta
	_toll_age += delta
	var tod: float = TimeManager.time_of_day
	if tod > 0.25 and tod < 0.85:
		_tolled_this_night = false

	# Keep stones risen if any player is currently standing out on the causeway so nobody is ever dropped mid-crossing!
	var player_on_stones: bool = false
	for p: Player in Player.all:
		if is_instance_valid(p) and p.global_position.distance_to((shore_pos + spire_pos) * 0.5) < 92.0:
			player_on_stones = true
			break

	var want_risen: bool = awakened or is_midnight_clear() or (stones_risen and player_on_stones)
	if want_risen != stones_risen:
		stones_risen = want_risen
		if stones_risen and not _tolled_this_night:
			_tolled_this_night = true
			_toll_bell()
		_refresh_visuals()

	if _spire_glow != null:
		var pulse: float = 0.85 + 0.15 * sin(_time * 2.4)
		_spire_glow.modulate.a = clampf(lerpf(0.28, 0.96, TimeManager.night_amount()) * pulse + clampf(1.0 - _toll_age / 3.2, 0.0, 1.0) * 0.6, 0.0, 1.0)

	# Kingfishers by day: dart off if a player comes close
	if not TimeManager.is_night():
		var near_spire: bool = false
		for p2: Player in Player.all:
			if is_instance_valid(p2) and p2.global_position.distance_to(spire_pos) < 120.0:
				near_spire = true
				break
		if near_spire and _bird_flight <= 0.0:
			_bird_flight = 0.01
		elif _bird_flight > 0.0:
			_bird_flight += delta * 0.55
			if _bird_flight >= 1.0 and not near_spire:
				_bird_flight = 0.0
	else:
		_bird_flight = 0.0

	_fx_canvas.queue_redraw()


func _draw_fx() -> void:
	var sp_loc: Vector2 = spire_pos - position
	# Expanding underwater bell resonance rings
	if _toll_age < 4.2:
		for k: int in 3:
			var age_k: float = _toll_age - float(k) * 0.45
			if age_k <= 0.0 or age_k > 3.2:
				continue
			var frac: float = age_k / 3.2
			var rx: float = lerpf(18.0, 118.0, frac)
			var ry: float = rx * 0.52
			var alpha: float = (1.0 - frac) * 0.72
			var pts: PackedVector2Array = PackedVector2Array()
			for s: int in 33:
				var a: float = float(s) / 32.0 * TAU
				pts.append(sp_loc + Vector2(cos(a) * rx, sin(a) * ry))
			_fx_canvas.draw_polyline(pts, Color(0.45, 0.98, 0.92, alpha), 1.5)

	# Daytime turquoise kingfishers perched on spire roof / skimming across lake
	if not TimeManager.is_night():
		for b: int in 2:
			var roof_perch: Vector2 = sp_loc + (Vector2(-11.0, -88.0) if b == 0 else Vector2(12.0, -82.0))
			var bird_pt: Vector2 = roof_perch
			var flapping: bool = _bird_flight > 0.0 and _bird_flight < 1.0
			if flapping:
				var f: float = clampf(_bird_flight, 0.0, 1.0)
				var target_skim: Vector2 = sp_loc + Vector2(76.0 if b == 0 else -68.0, -18.0 - sin(f * PI) * 26.0)
				bird_pt = roof_perch.lerp(target_skim, f)
			elif _bird_flight >= 1.0:
				continue
			var bob: float = sin(_time * 4.5 + float(b) * 1.9) * 0.6
			var p: Vector2 = (bird_pt + Vector2(0.0, bob)).round()
			# Crisp pixel kingfisher silhouette (teal back + warm orange breast + long beak)
			_fx_canvas.draw_rect(Rect2(p + Vector2(-2.0, -2.0), Vector2(4.0, 3.0)), Color("26b5c8"))
			_fx_canvas.draw_rect(Rect2(p + Vector2(-1.0, 0.0), Vector2(3.0, 2.0)), Color("f28d4b"))
			_fx_canvas.draw_rect(Rect2(p + Vector2(2.0 if b == 0 else -4.0, -2.0), Vector2(2.0, 1.0)), Color("1d1c32"))
			if flapping and int(_time * 18.0) % 2 == 0:
				_fx_canvas.draw_rect(Rect2(p + Vector2(-1.0, -5.0), Vector2(3.0, 3.0)), Color("6cf5e8"))


class BelfryAltar extends Interactable:
	var pond: BellPond

	func setup(owner_pond: BellPond, local_pos: Vector2) -> void:
		pond = owner_pond
		position = local_pos

	func is_interactable() -> bool:
		return pond != null and not pond.awakened and pond.stones_risen

	func prompt() -> String:
		if pond == null or pond.awakened or not pond.stones_risen:
			return ""
		return "VERSUNKENE GLOCKE LÄUTEN"

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, from.distance_to(global_position) - 30.0)

	func prompt_position() -> Vector2:
		return Vector2(10.0, -52.0)

	func interact(player: Player) -> void:
		if pond == null or pond.awakened or not pond.stones_risen or player == null or player.is_busy() or pond.wonders == null:
			return
		pond.wonders.request_awaken_bell_pond()
