class_name FlowerAmphitheater
extends Interactable
## Unique Meadow World Wonder 3 (`docs/wiesenbiom_ausbau_konzept.md` Stufe 5.3): **Das Blumen-Amphitheater (Die Stille Bühne)**.
## A natural meadow hollow (`[421, 667]` in *Die Lichtung*) carpeted in concentric rings of glowing moonflowers (`moonbell` & `mist_lily`)
## surrounding a circular ancient mossy stone podium (`amphitheater_podium.png`, `128x96`, center anchor `(64, 52)`).
##  - Interacting (`E -> "AUF DER STILLEN BÜHNE LAUSCHEN"`) OR stepping onto the central stone stage at night awakens the amphitheater
##    (`amphitheater_hum.wav`), summoning **42 harmonic turquoise-violet-gold wisps** to dance in three counter-rotating rings around
##    the hollow and raising a `rare` `LootChest`!
##  - Every night thereafter, the wisp dance continues peacefully across the moonflower stage.

const PODIUM_TEX: String = "res://assets/props/amphitheater_podium.png"
const PODIUM_GLOW: String = "res://assets/props/amphitheater_podium_glow.png"
const MOONBELL_TEX: String = "res://assets/props/moonbell.png"
const MOONBELL_GLOW: String = "res://assets/props/moonbell_glow.png"
const LILY_TEX: String = "res://assets/props/mist_lily.png"
const LILY_GLOW: String = "res://assets/props/mist_lily_glow.png"
const HUM_WAV: String = "res://assets/audio/meadow_wonders/amphitheater_hum.wav"

const WISP_PALETTE: Array[Color] = [
	Color("6cf5e8"),
	Color("c8a8ff"),
	Color("ffe28a"),
	Color("9ff8ee"),
]

var wonders: MeadowWonders
var wonder_id: String = "wonder_flower_amphitheater"
var chest_tier: String = "rare"
var awakened: bool = false

var _podium_body: Sprite2D
var _podium_glow: Sprite2D
var _stage_light: NightLight
var _flower_glows: Array[Sprite2D] = []
var _wisp_canvas: Node2D
var _wisps: Array[Dictionary] = []

var _time: float = 0.0
var _dance_boost: float = 0.0 ## surges to 1.0 on interaction / awakening even at dusk or day


func setup(owner_wonders: MeadowWonders, spec: Dictionary) -> void:
	wonders = owner_wonders
	wonder_id = String(spec.get("id", "wonder_flower_amphitheater"))
	chest_tier = String(spec.get("chest_tier", "rare"))
	var t: Array = spec.get("tile", [421, 667]) as Array
	position = Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8.0, 8.0)


func _ready() -> void:
	add_to_group("flora_glow")

	# Circular ancient stone podium (anchor 64, 52 in 128x96 -> offset (0, -4))
	var pod_off: Vector2 = Vector2(0.0, -(52.0 - 48.0))
	if ResourceLoader.exists(PODIUM_TEX):
		_podium_body = Sprite2D.new()
		_podium_body.texture = load(PODIUM_TEX) as Texture2D
		_podium_body.offset = pod_off
		_podium_body.z_index = -5
		add_child(_podium_body)
	if ResourceLoader.exists(PODIUM_GLOW):
		_podium_glow = Sprite2D.new()
		_podium_glow.texture = load(PODIUM_GLOW) as Texture2D
		_podium_glow.offset = pod_off
		_podium_glow.z_index = -5
		_podium_glow.material = Unlit.material()
		add_child(_podium_glow)

	_build_moonflower_rings()

	_stage_light = NightLight.new()
	_stage_light.radius = 104
	_stage_light.base_energy = 0.46
	_stage_light.pulse = 0.16
	_stage_light.glow_color = Color("9ceee8")
	add_child(_stage_light)

	_wisp_canvas = Node2D.new()
	_wisp_canvas.z_index = 4
	_wisp_canvas.material = Unlit.material()
	_wisp_canvas.draw.connect(_draw_wisps)
	add_child(_wisp_canvas)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(wonder_id)
	for i: int in 42:
		var tier: int = i % 3
		var base_rx: float = [46.0, 74.0, 102.0][tier] + rng.randf_range(-6.0, 6.0)
		var base_ry: float = base_rx * 0.64
		var dir_sign: float = 1.0 if tier != 1 else -1.0
		_wisps.append({
			"rx": base_rx,
			"ry": base_ry,
			"angle": float(i) / 42.0 * TAU + rng.randf_range(-0.2, 0.2),
			"speed": rng.randf_range(0.42, 0.78) * dir_sign,
			"bob_phase": rng.randf() * TAU,
			"height": rng.randf_range(8.0, 26.0),
			"col": WISP_PALETTE[i % WISP_PALETTE.size()],
			"size": 2.0 if i % 3 == 0 else 1.0,
		})

	_refresh_visuals()


func _build_moonflower_rings() -> void:
	var mb_tex: Texture2D = load(MOONBELL_TEX) as Texture2D if ResourceLoader.exists(MOONBELL_TEX) else null
	var mb_glw: Texture2D = load(MOONBELL_GLOW) as Texture2D if ResourceLoader.exists(MOONBELL_GLOW) else null
	var ml_tex: Texture2D = load(LILY_TEX) as Texture2D if ResourceLoader.exists(LILY_TEX) else null
	var ml_glw: Texture2D = load(LILY_GLOW) as Texture2D if ResourceLoader.exists(LILY_GLOW) else null

	var ring_holder: Node2D = Node2D.new()
	ring_holder.name = "MoonflowerRings"
	ring_holder.y_sort_enabled = true
	add_child(ring_holder)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(wonder_id) ^ 0x517cc1b7
	var ring_specs: Array[Dictionary] = [
		{"count": 16, "rx": 74.0, "ry": 48.0},
		{"count": 22, "rx": 96.0, "ry": 62.0},
		{"count": 26, "rx": 118.0, "ry": 76.0},
	]
	for r_idx: int in ring_specs.size():
		var r_spec: Dictionary = ring_specs[r_idx]
		var cnt: int = int(r_spec.count)
		var rx: float = float(r_spec.rx)
		var ry: float = float(r_spec.ry)
		for k: int in cnt:
			var a: float = (float(k) + rng.randf_range(-0.25, 0.25)) / float(cnt) * TAU
			# Leave a gentle southern entrance gap on the inner ring for the rising chest & approach
			if r_idx == 0 and absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.34:
				continue
			var pt: Vector2 = Vector2(cos(a) * rx + rng.randf_range(-3.0, 3.0), sin(a) * ry + rng.randf_range(-2.5, 2.5)).round()
			var use_lily: bool = (k + r_idx) % 3 == 0 and ml_tex != null
			var tex: Texture2D = ml_tex if use_lily else mb_tex
			var glw: Texture2D = ml_glw if use_lily else mb_glw
			if tex == null:
				continue
			var rows: int = 3 if use_lily else 2
			var col_idx: int = rng.randi() % 5
			var sp: Sprite2D = Sprite2D.new()
			sp.texture = tex
			sp.hframes = 5
			sp.vframes = rows
			sp.frame = col_idx
			sp.centered = false
			sp.offset = Vector2(-20.0, -31.0)
			sp.position = pt
			ring_holder.add_child(sp)
			if glw != null:
				var gs: Sprite2D = Sprite2D.new()
				gs.texture = glw
				gs.hframes = 5
				gs.vframes = rows
				gs.frame = col_idx
				gs.centered = false
				gs.offset = Vector2(-20.0, -31.0)
				gs.position = pt
				gs.material = Unlit.material()
				ring_holder.add_child(gs)
				_flower_glows.append(gs)


func set_awakened_instant(val: bool) -> void:
	awakened = val
	if val:
		var chests: LootChests = LootChests.of(get_tree())
		if chests != null:
			chests.place(wonder_id + "_chest", chest_tier, global_position + Vector2(0.0, 54.0), false)
	_refresh_visuals()


func play_awaken_fx() -> void:
	awakened = true
	_dance_boost = 1.0
	_play_hum()
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		chests.appear(wonder_id + "_chest", chest_tier, global_position + Vector2(0.0, 54.0), false, true, true)
	_refresh_visuals()


func _play_hum() -> void:
	if ResourceLoader.exists(HUM_WAV):
		var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		snd.stream = load(HUM_WAV) as AudioStream
		snd.bus = "SFX"
		snd.volume_db = -3.0
		snd.max_distance = 620.0
		snd.finished.connect(snd.queue_free)
		add_child(snd)
		snd.play()


func _refresh_visuals() -> void:
	if _stage_light != null:
		_stage_light.base_energy = 0.86 if awakened else 0.48
		_stage_light.radius = 128 if awakened else 96


func is_interactable() -> bool:
	return true


func prompt() -> String:
	return "STILLE MELODIE SUMMEN" if awakened else "AUF DER STILLEN BÜHNE LAUSCHEN"


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, from.distance_to(global_position) - 34.0)


func prompt_position() -> Vector2:
	return Vector2(0.0, -30.0)


func interact(player: Player) -> void:
	if player == null or player.is_busy():
		return
	if not awakened and wonders != null:
		wonders.request_awaken_amphitheater()
	else:
		_dance_boost = 1.0
		_play_hum()


func _process(delta: float) -> void:
	_time += delta
	_dance_boost = maxf(0.0, _dance_boost - delta * 0.08)

	# Stepping onto the central stone stage at night automatically awakens the amphitheater!
	if multiplayer.is_server() and not awakened and TimeManager.is_night() and wonders != null:
		for p: Player in Player.all:
			if is_instance_valid(p) and p.health.current > 0.0 and p.global_position.distance_to(global_position) <= 44.0:
				wonders.request_awaken_amphitheater()
				break

	var night_amt: float = TimeManager.night_amount()
	var glow_vis: float = clampf(maxf(night_amt, _dance_boost * 0.85) + (0.22 if awakened else 0.0), 0.15, 1.0)
	if _podium_glow != null:
		_podium_glow.modulate.a = glow_vis * (0.84 + 0.16 * sin(_time * 2.3))
	for i: int in _flower_glows.size():
		var fg: Sprite2D = _flower_glows[i]
		fg.modulate.a = glow_vis * (0.76 + 0.24 * sin(_time * 2.0 + float(i) * 0.45))

	_wisp_canvas.queue_redraw()


func wisp_intensity() -> float:
	if awakened and TimeManager.is_night():
		return 1.0
	if TimeManager.is_night():
		return 0.65
	return _dance_boost


func _draw_wisps() -> void:
	var intensity: float = wisp_intensity()
	if intensity <= 0.02:
		return
	for i: int in _wisps.size():
		var w: Dictionary = _wisps[i]
		var ang: float = float(w.angle) + _time * float(w.speed)
		var rx: float = float(w.rx) * (1.0 + 0.06 * sin(_time * 1.3 + float(i)))
		var ry: float = float(w.ry) * (1.0 + 0.06 * cos(_time * 1.1 + float(i)))
		var lift: float = float(w.height) + sin(_time * 2.8 + float(w.bob_phase)) * 5.5
		var pt: Vector2 = Vector2(cos(ang) * rx, sin(ang) * ry - lift).round()
		var base_col: Color = w.col as Color
		var twinkle: float = 0.72 + 0.28 * sin(_time * 5.2 + float(i) * 1.7)
		var alpha: float = clampf(intensity * twinkle, 0.0, 1.0)

		# Soft trailing mote one quarter-beat behind
		var trail_ang: float = ang - float(w.speed) * 0.14
		var trail_pt: Vector2 = Vector2(cos(trail_ang) * rx, sin(trail_ang) * ry - lift + 1.0).round()
		_wisp_canvas.draw_rect(Rect2(trail_pt, Vector2.ONE), Color(base_col.r, base_col.g, base_col.b, alpha * 0.38))

		# Outer halo + crisp unlit wisp core
		var sz: float = float(w.size)
		_wisp_canvas.draw_rect(Rect2(pt - Vector2.ONE, Vector2(sz + 2.0, sz + 2.0)), Color(base_col.r, base_col.g, base_col.b, alpha * 0.30))
		_wisp_canvas.draw_rect(Rect2(pt, Vector2(sz, sz)), Color(1.0, 0.98, 0.92, alpha * 0.95).lerp(base_col, 0.35))
