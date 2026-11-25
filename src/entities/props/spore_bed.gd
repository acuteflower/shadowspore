class_name SporeBed
extends Interactable
## Living Schattenfrucht moss bed at the camp & town (`docs/schattenfruechte_und_menue_konzept.md` §1.4).
## Every collected Schattenfrucht moves into this mossy stone-rimmed patch with its exact procedural
## `ShadowFruitArt` appearance. Up to 24 active residents peek from the moss, glance toward passing
## players, bounce in a pentatonic xylophone wave when greeted (`E`), glow warmly at night, and produce
## a daily morning Sporen-Tau gift once 5+ fruits have been gathered.

const CHIME_WAV: AudioStream = preload("res://assets/audio/waystone/chime_b.wav")
const PICKUP_WAV: AudioStream = preload("res://assets/audio/sfx/item_pickup.wav")
const RUSTLE_WAV: AudioStream = preload("res://assets/audio/hut/rustle.wav")

const BED_W: int = 64
const BED_H: int = 38
const MAX_VISIBLE: int = 24

# Deterministic cozy nest slots inside the 64x38 mossy oval (relative to bed center)
const NEST_SLOTS: Array[Vector2] = [
	Vector2(-18.0, -6.0), Vector2(18.0, -6.0), Vector2(0.0, -9.0), Vector2(-10.0, 2.0),
	Vector2(10.0, 2.0), Vector2(-22.0, 1.0), Vector2(22.0, 1.0), Vector2(0.0, 6.0),
	Vector2(-14.0, -10.0), Vector2(14.0, -10.0), Vector2(-6.0, -3.0), Vector2(6.0, -3.0),
	Vector2(-15.0, 7.0), Vector2(15.0, 7.0), Vector2(-24.0, -4.0), Vector2(24.0, -4.0),
	Vector2(-7.0, 8.0), Vector2(7.0, 8.0), Vector2(0.0, -1.0), Vector2(-19.0, 5.0),
	Vector2(19.0, 5.0), Vector2(-11.0, -7.0), Vector2(11.0, -7.0), Vector2(0.0, -13.0),
]

static var _bed_base_tex: ImageTexture = null
static var _bed_glow_tex: ImageTexture = null
static var _dew_tex: ImageTexture = null

var _base_sprite: Sprite2D
var _base_glow: Sprite2D
var _dew_sprite: Sprite2D
var _light: NightLight
var _motes: CPUParticles2D
var _residents_root: Node2D
var _residents: Array[Dictionary] = [] ## {id, root, body, glow, art, slot, pitch, hop_t, hop_delay}

var _vt: VeilThreads = null
var _time: float = 0.0
var _wave_active: bool = false
var _wave_t: float = 0.0
var _greet_cooldown: float = 0.0


func _ready() -> void:
	add_to_group("spore_beds")
	y_sort_enabled = true
	_ensure_bed_textures()

	_base_sprite = Sprite2D.new()
	_base_sprite.texture = _bed_base_tex
	_base_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_base_sprite.z_index = -2
	add_child(_base_sprite)

	_base_glow = Sprite2D.new()
	_base_glow.texture = _bed_glow_tex
	_base_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_base_glow.material = Unlit.material()
	_base_glow.z_index = -1
	add_child(_base_glow)

	_residents_root = Node2D.new()
	_residents_root.y_sort_enabled = true
	add_child(_residents_root)

	_dew_sprite = Sprite2D.new()
	_dew_sprite.texture = _dew_tex
	_dew_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dew_sprite.material = Unlit.material()
	_dew_sprite.position = Vector2(0.0, -14.0)
	_dew_sprite.z_index = 10
	_dew_sprite.visible = false
	add_child(_dew_sprite)

	_light = NightLight.new()
	_light.position = Vector2(0.0, -4.0)
	_light.radius = 48
	_light.base_energy = 0.25
	_light.glow_color = Color("78f4e6")
	add_child(_light)

	_motes = CPUParticles2D.new()
	_motes.material = Unlit.material()
	_motes.z_index = 6
	_motes.position = Vector2(0.0, -4.0)
	_motes.amount = 10
	_motes.lifetime = 2.6
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(24.0, 10.0)
	_motes.direction = Vector2(0.0, -1.0)
	_motes.spread = 22.0
	_motes.initial_velocity_min = 3.0
	_motes.initial_velocity_max = 9.0
	_motes.gravity = Vector2.ZERO
	_motes.scale_amount_min = 1.0
	_motes.scale_amount_max = 1.5
	var ramp: Gradient = Gradient.new()
	ramp.colors = PackedColorArray([
		Color("d0fff8", 0.0),
		Color("78f4e6", 0.85),
		Color("b98cff", 0.70),
		Color("b98cff", 0.0),
	])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.72, 1.0])
	_motes.color_ramp = ramp
	_motes.emitting = false
	add_child(_motes)

	_bind_veil_threads()


func _bind_veil_threads() -> void:
	_vt = VeilThreads.of(get_tree())
	if _vt != null and not _vt.changed.is_connected(_rebuild_residents):
		_vt.changed.connect(_rebuild_residents)
	_rebuild_residents()


func _rebuild_residents() -> void:
	for r: Dictionary in _residents:
		var rn: Node2D = r["root"] as Node2D
		if rn != null and is_instance_valid(rn):
			rn.queue_free()
	_residents.clear()
	if _vt == null:
		return
	var ids: Array[String] = _vt.collected_ids()
	var shown: int = mini(ids.size(), mini(MAX_VISIBLE, NEST_SLOTS.size()))
	# Show newest/most-recent first if > MAX_VISIBLE
	var start_idx: int = maxi(0, ids.size() - shown)
	var avg_col: Color = Color(0.0, 0.0, 0.0, 1.0)
	for i: int in shown:
		var fid: String = ids[start_idx + i]
		var art: Dictionary = ShadowFruitArt.build(fid)
		var slot: Vector2 = NEST_SLOTS[i]
		var root: Node2D = Node2D.new()
		root.position = slot.round()
		_residents_root.add_child(root)

		var bodies: Array = art["fruit_bodies"] as Array
		var glows: Array = art["fruit_glows"] as Array
		var b_spr: Sprite2D = Sprite2D.new()
		b_spr.texture = bodies[0] as ImageTexture
		b_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b_spr.offset = Vector2(0.0, -7.0)
		root.add_child(b_spr)

		var g_spr: Sprite2D = Sprite2D.new()
		g_spr.texture = glows[0] as ImageTexture
		g_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		g_spr.offset = Vector2(0.0, -7.0)
		g_spr.material = Unlit.material()
		root.add_child(g_spr)

		var ac: Color = art["accent"] as Color
		avg_col += Color(ac.r, ac.g, ac.b, 0.0)
		_residents.append({
			"id": fid,
			"root": root,
			"body": b_spr,
			"glow": g_spr,
			"bodies": bodies,
			"glows": glows,
			"slot": slot,
			"pitch": float(art["pitch"]),
			"phase": fposmod(float(absi(fid.hash())) * 0.21, TAU),
			"hop_t": -1.0,
			"hop_delay": 0.0,
			"chimed": false,
		})

	if shown > 0:
		avg_col = Color(avg_col.r / float(shown), avg_col.g / float(shown), avg_col.b / float(shown), 1.0)
		_light.glow_color = avg_col
		_light.radius = 48 + mini(shown * 2, 44)
		_motes.amount = clampi(4 + shown, 6, 22)
		_motes.emitting = true
	else:
		_light.glow_color = Color("78f4e6")
		_light.radius = 34
		_motes.emitting = false
	_dew_sprite.visible = _vt.bed_gift_ready()


func prompt() -> String:
	if _vt == null:
		return "MOOSBEET"
	if _vt.bed_gift_ready():
		return "SPOREN-TAU ERNTEN"
	if _residents.is_empty():
		return "LEERES SPORENBEET"
	return "SPORENBEET BEGRÜSSEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 34.0


func prompt_position() -> Vector2:
	return Vector2(0.0, -28.0)


func interact(_player: Player) -> void:
	if _vt == null:
		_bind_veil_threads()
	if _vt != null and _vt.bed_gift_ready():
		_vt.request_harvest_bed_gift()
		_play_sound(PICKUP_WAV, -3.0, 1.06)
		_trigger_wave()
		return
	if _residents.is_empty():
		_play_sound(RUSTLE_WAV, -10.0, 0.9)
		return
	if _greet_cooldown <= 0.0:
		_greet_cooldown = 1.1
		_trigger_wave()


func _trigger_wave() -> void:
	_wave_active = true
	_wave_t = 0.0
	# Sort delay left-to-right by slot.x so they hop like a musical xylophone!
	for r: Dictionary in _residents:
		var sx: float = (r["slot"] as Vector2).x
		var norm: float = clampf((sx + 26.0) / 52.0, 0.0, 1.0)
		r["hop_delay"] = norm * 0.55
		r["hop_t"] = -1.0
		r["chimed"] = false


func _process(delta: float) -> void:
	_time += delta
	if _vt == null:
		_bind_veil_threads()
	if _greet_cooldown > 0.0:
		_greet_cooldown = maxf(_greet_cooldown - delta, 0.0)

	var night: float = TimeManager.night_amount()
	var cnt: int = _residents.size()
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.0)
	_base_glow.modulate.a = (0.18 if cnt == 0 else lerpf(0.45, 0.92, night)) * (0.85 + 0.15 * pulse)
	_light.base_energy = (0.12 if cnt == 0 else lerpf(0.26, 0.72, night)) * (0.90 + 0.10 * pulse)

	if _vt != null:
		var gift_now: bool = _vt.bed_gift_ready()
		_dew_sprite.visible = gift_now
		if gift_now:
			_dew_sprite.position = Vector2(0.0, roundf(-15.0 + sin(_time * 3.1) * 2.2))

	if _wave_active:
		_wave_t += delta
		var any_left: bool = false
		for r: Dictionary in _residents:
			var delay: float = float(r["hop_delay"])
			if _wave_t < delay:
				any_left = true
				continue
			var ht: float = _wave_t - delay
			r["hop_t"] = ht
			if ht < 0.42:
				any_left = true
				if not bool(r["chimed"]):
					r["chimed"] = true
					_play_sound(CHIME_WAV, -9.0, float(r["pitch"]))
		if not any_left:
			_wave_active = false

	# Nearest player glance + cozy breathing animation for each resident
	var near_player: Player = null
	var best_d: float = 120.0
	for p: Player in Player.all:
		if is_instance_valid(p) and p.health != null and p.health.current > 0.0:
			var d: float = p.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				near_player = p

	for r: Dictionary in _residents:
		var root: Node2D = r["root"] as Node2D
		var b_spr: Sprite2D = r["body"] as Sprite2D
		var g_spr: Sprite2D = r["glow"] as Sprite2D
		var bodies: Array = r["bodies"] as Array
		var glows: Array = r["glows"] as Array
		var slot: Vector2 = r["slot"] as Vector2
		var ph: float = float(r["phase"])
		var ht: float = float(r["hop_t"])

		var frame_i: int = 0
		var hop_y: float = 0.0
		var sx: float = 1.0
		var sy: float = 1.0
		if ht >= 0.0 and ht < 0.42:
			var u: float = ht / 0.42
			hop_y = -sin(u * PI) * 8.5
			frame_i = 2 if (u > 0.18 and u < 0.78) else (1 if u <= 0.18 else 3)
			sx = lerpf(0.86, 1.12, absf(u - 0.5) * 2.0)
			sy = lerpf(1.18, 0.88, absf(u - 0.5) * 2.0)
		else:
			# Subtle idle breathing + occasional cute blink + look toward passing Ellie
			var breath: float = sin(_time * 2.4 + ph) * 0.05
			sx = 1.0 - breath * 0.6
			sy = 1.0 + breath
			var blink_cycle: float = fposmod(_time * 0.35 + ph, 1.0)
			if blink_cycle > 0.92:
				frame_i = 2
			elif near_player != null:
				var dx: float = near_player.global_position.x - (global_position.x + slot.x)
				if absf(dx) > 10.0 and sin(_time * 3.5 + ph) > 0.25:
					frame_i = 3 if dx > 0.0 else 1

		b_spr.texture = bodies[frame_i] as ImageTexture
		g_spr.texture = glows[frame_i] as ImageTexture
		root.position = Vector2(roundf(slot.x), roundf(slot.y + hop_y))
		root.scale = Vector2(sx, sy)
		g_spr.modulate.a = lerpf(0.68, 1.0, night)


func _play_sound(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if stream == null or not is_inside_tree():
		return
	var a: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	a.stream = stream
	a.volume_db = vol_db
	a.pitch_scale = pitch
	a.max_distance = 320.0
	a.finished.connect(a.queue_free)
	add_child(a)
	a.play()


static func _ensure_bed_textures() -> void:
	if _bed_base_tex != null:
		return
	var img: Image = Image.create(BED_W, BED_H, false, Image.FORMAT_RGBA8)
	var gimg: Image = Image.create(BED_W, BED_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	gimg.fill(Color(0, 0, 0, 0))

	var cx: float = float(BED_W) * 0.5
	var cy: float = float(BED_H) * 0.5 + 1.0
	var rx: float = 29.0
	var ry: float = 16.0

	var rim_dark: Color = Color("1f1b2e")
	var rim_stone: Color = Color("46435e")
	var rim_hi: Color = Color("6b688a")
	var moss_dark: Color = Color("19362e")
	var moss_mid: Color = Color("295443")
	var moss_hi: Color = Color("437d5c")
	var soil_dark: Color = Color("1e1629")
	var soil_mid: Color = Color("2e223a")
	var rune_teal: Color = Color("3cc0c6")
	var rune_hi: Color = Color("78f4e6")

	for y: int in BED_H:
		for x: int in BED_W:
			var dx: float = (float(x) - cx) / rx
			var dy: float = (float(y) - cy) / ry
			var d: float = sqrt(dx * dx + dy * dy)
			if d > 1.04:
				continue
			if d > 0.96:
				img.set_pixel(x, y, Color(0.04, 0.02, 0.08, 0.5))
			elif d > 0.80:
				# Mossy stone & woven root border
				var ang: float = atan2(dy, dx)
				var stone_seg: int = int(floorf((ang + PI) * 2.5))
				var is_moss: bool = (stone_seg % 3) == 1
				var top_lit: bool = dy < 0.05 and dx < 0.35
				if is_moss:
					img.set_pixel(x, y, moss_hi if top_lit else moss_mid)
				else:
					img.set_pixel(x, y, rim_hi if top_lit else (rim_stone if dy < 0.4 else rim_dark))
				if d > 0.91 and ((x + y) % 5 == 0):
					img.set_pixel(x, y, rim_dark)
			else:
				# Rich mossy forest floor bed inside
				var patch: float = sin(float(x) * 0.42 + float(y) * 0.25) * cos(float(y) * 0.38 - float(x) * 0.18)
				if patch > 0.15:
					img.set_pixel(x, y, moss_hi if (patch > 0.55 and dy < 0.2) else moss_mid)
				elif patch > -0.25:
					img.set_pixel(x, y, moss_dark)
				else:
					img.set_pixel(x, y, soil_mid if ((x + y) % 2 == 0) else soil_dark)
				# Subtle glowing mycelial veins beneath the moss
				var vein: float = absf(sin(float(x) * 0.28 + sin(float(y) * 0.35)))
				if vein < 0.08 and d < 0.72:
					gimg.set_pixel(x, y, rune_hi if d < 0.4 else rune_teal)

	_bed_base_tex = ImageTexture.create_from_image(img)
	_bed_glow_tex = ImageTexture.create_from_image(gimg)

	# Glowing morning Sporen-Tau droplet sprite (12x14)
	var dimg: Image = Image.create(12, 14, false, Image.FORMAT_RGBA8)
	dimg.fill(Color(0, 0, 0, 0))
	for y: int in range(2, 12):
		for x: int in range(2, 10):
			var ddx: float = (float(x) - 5.5) / 3.2
			var ddy: float = (float(y) - 7.5) / 4.2
			var taper: float = 1.0 - 0.55 * clampf(-ddy, 0.0, 1.0)
			if (ddx / maxf(taper, 0.3)) * (ddx / maxf(taper, 0.3)) + ddy * ddy <= 1.0:
				var c: Color = Color("d8fff8") if (ddx < 0.0 and ddy < 0.1) else (Color("78f4e6") if ddy < 0.4 else Color("3cc0c6"))
				dimg.set_pixel(x, y, c)
	dimg.set_pixel(5, 5, Color("ffffff"))
	_dew_tex = ImageTexture.create_from_image(dimg)
