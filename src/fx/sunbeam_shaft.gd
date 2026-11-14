class_name SunbeamShaft
extends Node2D
## Narrow cathedral shaft of golden sunlight (and soft silver moonbeam on clear nights) breaking through
## the high `ancient_fir` canopy of *Der Tiefe Urforst* (`docs/wiesenbiom_ausbau_konzept.md` Stufe 2.1).
## Purely atmospheric & unlit (`Unlit.material()`), with gentle wind-drifting pollen/dust motes inside the beam.

static var _beam_tex: ImageTexture
static var _pool_tex: ImageTexture

var beam_scale: float = 1.0
var phase: float = 0.0
var _beam: Sprite2D
var _pool: Sprite2D
var _motes: Node2D
var _notifier: VisibleOnScreenNotifier2D
var _on_screen: bool = false
var _mote_data: Array[Vector4] = [] ## (local_x, local_y, phase, size)


static func _ensure_textures() -> void:
	if _beam_tex != null and _pool_tex != null:
		return
	# Slanted cathedral beam from top-left (-38, -148) down to ground pool (0, 0), crisp pixel-art clusters
	var bw: int = 88
	var bh: int = 160
	var b_img: Image = Image.create(bw, bh, false, Image.FORMAT_RGBA8)
	for y: int in bh:
		var t: float = float(y) / float(bh - 1) ## 0 at canopy top, 1 at forest floor
		var cx: float = lerpf(18.0, 56.0, t)
		var half_w: float = lerpf(8.5, 19.5, t)
		var v_fade: float = smoothstep(0.0, 0.16, t) * (1.0 - smoothstep(0.84, 1.0, t))
		for x: int in bw:
			var d: float = absf(float(x) - cx) / maxf(half_w, 1.0)
			if d >= 1.0:
				continue
			# Crisp 2-ray split inside the shaft so it reads like real light through fir branches
			var ray_split: float = 0.72 + 0.28 * sin((float(x) - cx) * 0.42 + 0.6)
			var core: float = pow(1.0 - d, 1.45) * v_fade * ray_split
			# Quantize into 4 clean pixel-art alpha bands (no muddy continuous gradient)
			var q: float = 0.0
			if core > 0.62:
				q = 0.34
			elif core > 0.36:
				q = 0.21
			elif core > 0.16:
				q = 0.11
			if q > 0.0:
				b_img.set_pixel(x, y, Color(1.0, 1.0, 1.0, q))
	_beam_tex = ImageTexture.create_from_image(b_img)

	var pw: int = 56
	var ph: int = 28
	var p_img: Image = Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	for py: int in ph:
		for px: int in pw:
			var dx: float = (float(px) - 27.5) / 25.0
			var dy: float = (float(py) - 13.5) / 11.5
			var r2: float = dx * dx + dy * dy
			if r2 >= 1.0:
				continue
			var strength: float = 1.0 - r2
			var pa: float = 0.28 if strength > 0.58 else (0.16 if strength > 0.25 else 0.0)
			if pa > 0.0:
				p_img.set_pixel(px, py, Color(1.0, 1.0, 1.0, pa))
	_pool_tex = ImageTexture.create_from_image(p_img)


func setup(at: Vector2, scale_factor: float = 1.0, seed_val: int = 0) -> void:
	position = at.round()
	beam_scale = clampf(scale_factor, 0.75, 1.35)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else hash(Vector2i(int(at.x), int(at.y)))
	phase = rng.randf() * TAU
	_mote_data.clear()
	for _i: int in 9:
		var t: float = rng.randf_range(0.14, 0.92)
		var lx: float = lerpf(-34.0, 2.0, t) + rng.randf_range(-9.0, 9.0)
		var ly: float = lerpf(-136.0, -6.0, t)
		_mote_data.append(Vector4(lx, ly, rng.randf() * TAU, 2.0 if rng.randf() < 0.28 else 1.0))


func _ready() -> void:
	_ensure_textures()
	y_sort_enabled = false
	_pool = Sprite2D.new()
	_pool.texture = _pool_tex
	_pool.material = Unlit.material()
	_pool.z_index = -7
	add_child(_pool)

	_beam = Sprite2D.new()
	_beam.texture = _beam_tex
	_beam.offset = Vector2(-12.0, -76.0)
	_beam.material = Unlit.material()
	_beam.z_index = 5
	add_child(_beam)

	_motes = Node2D.new()
	_motes.material = Unlit.material()
	_motes.z_index = 6
	_motes.draw.connect(_draw_motes)
	add_child(_motes)

	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-72.0, -172.0, 128.0, 196.0)
	_notifier.screen_entered.connect(func() -> void:
		_on_screen = true
		set_process(true)
		_refresh_light())
	_notifier.screen_exited.connect(func() -> void:
		_on_screen = false
		set_process(false))
	add_child(_notifier)
	set_process(false)
	_refresh_light()


func _process(_delta: float) -> void:
	if not _on_screen:
		return
	_refresh_light()
	if _motes != null and _motes.visible:
		_motes.queue_redraw()


func _refresh_light() -> void:
	var night: float = TimeManager.night_amount()
	var weather_dim: float = 1.0
	if WeatherManager.current != null:
		weather_dim = clampf(1.0 - WeatherManager.current.rain * 0.92 - WeatherManager.current.storm * 0.95 - maxf(WeatherManager.current.cloud - 0.55, 0.0) * 1.1, 0.0, 1.0)
	var clock: float = WorldWind.current.clock if WorldWind.current != null else float(Time.get_ticks_msec()) * 0.001
	var breathe: float = 0.88 + 0.12 * sin(clock * 0.65 + phase)
	var day_amt: float = (1.0 - night) * weather_dim * breathe
	var moon_amt: float = night * weather_dim * 0.42 * breathe
	var strength: float = maxf(day_amt, moon_amt) * beam_scale
	visible = strength > 0.03
	if not visible:
		return
	var col: Color = Color("fff0b0").lerp(Color("c8fff4"), clampf(night * 1.15, 0.0, 1.0))
	if _beam != null:
		_beam.modulate = Color(col.r, col.g, col.b, clampf(strength, 0.0, 1.0))
	if _pool != null:
		_pool.modulate = Color(col.r, col.g, col.b, clampf(strength * 0.85, 0.0, 1.0))
	if _motes != null:
		_motes.visible = strength > 0.15
		_motes.modulate = Color(col.r, col.g, col.b, clampf(strength * 1.1, 0.0, 1.0))


func _draw_motes() -> void:
	var clock: float = WorldWind.current.clock if WorldWind.current != null else float(Time.get_ticks_msec()) * 0.001
	for m: Vector4 in _mote_data:
		var drift_x: float = sin(clock * 0.75 + m.z) * 4.5
		var drift_y: float = cos(clock * 0.52 + m.z * 1.3) * 3.5
		var twinkle: float = 0.45 + 0.55 * sin(clock * 1.9 + m.z * 2.1)
		if twinkle < 0.25:
			continue
		var p: Vector2 = Vector2(m.x + drift_x, m.y + drift_y).round()
		_motes.draw_rect(Rect2(p, Vector2(m.w, m.w)), Color(1.0, 1.0, 1.0, twinkle * 0.75))
