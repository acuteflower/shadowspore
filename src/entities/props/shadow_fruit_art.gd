class_name ShadowFruitArt
extends RefCounted
## Deterministic procedural pixel-art generator for buried & uprooted living Schattenfrüchte.
## Every fruit belongs unmistakably to the same botanical species (plump obsidian-violet subterranean
## shadow-fruit with bioluminescent veins, tiny sleepy spore-eyes, curled dark-emerald leaf crown,
## and twitching root tendrils) while varying subtly per `fruit_id` across shape, glow accent,
## leaf crown, vein pattern, and musical chime pitch.
## Strict pixel-art rules (`docs/design_guide.md`): nearest filtering, 1px tinted outline (`#040208` /
## `#120b24`, never pure `#000000`), top-left lighting, separate unlit `*_glow` textures.

const OUTLINE: Color = Color("080512")
const BODY_SHADOW: Color = Color("110a22")
const BODY_DARK: Color = Color("1d1138")
const BODY_MID: Color = Color("311b5c")
const BODY_LIGHT: Color = Color("4f2d8c")
const BODY_RIM: Color = Color("764fc2")

const SOIL_DARK: Color = Color("1b1526")
const SOIL_MID: Color = Color("30233a")
const SOIL_LIGHT: Color = Color("4b384f")
const SOIL_WARM: Color = Color("644c58")
const HOLE_DEEP: Color = Color("0c0816")

const ROOT_DARK: Color = Color("1c1230")
const ROOT_MID: Color = Color("372459")
const ROOT_TIP: Color = Color("644696")

const LEAF_OUTLINE: Color = Color("0b181c")
const LEAF_DARK: Color = Color("183834")
const LEAF_MID: Color = Color("295a4c")
const LEAF_LIGHT: Color = Color("438262")
const LEAF_TIP: Color = Color("6db37d")

## Five cohesive Shadowspore bioluminescent families: [deep, mid, bright, core]
const ACCENTS: Array[Array] = [
	[Color("1e6e78"), Color("3cc0c6"), Color("78f4e6"), Color("d8fff8")], ## Schleier-Türkis
	[Color("4c248f"), Color("8652e0"), Color("b98cff"), Color("ebd8ff")], ## Dämmer-Violett
	[Color("7e226c"), Color("cb48b8"), Color("ff80e4"), Color("ffd8f6")], ## Sporen-Magenta
	[Color("1f7058"), Color("3eb88a"), Color("82f0be"), Color("dcfff0")], ## Mond-Mint
	[Color("313d9e"), Color("5f7ae8"), Color("9ec0ff"), Color("e2eeff")], ## Stern-Indigo
]

const FAMILY_IDS: Array[String] = ["teal", "violet", "magenta", "mint", "indigo"]
const FAMILY_NAMES: Array[String] = [
	"SCHLEIER-TÜRKIS",
	"DÄMMER-VIOLETT",
	"SPOREN-MAGENTA",
	"MOND-MINT",
	"STERN-INDIGO",
]

const TRAIT_LABELS: Dictionary = {
	"calm": "RUHIG",
	"shy": "SCHEU · ANSCHLEICHEN",
	"nocturnal": "NACHTBLÜHER · NACHT ODER LICHT",
	"stubborn": "TIEFWURZLER · 2× ZIEHEN",
}

## Pentatonic-flavored musical ratios so every fruit chimes distinctly when pulled
const CHIME_PITCHES: Array[float] = [0.92, 1.00, 1.06, 1.12, 1.19, 1.26, 0.96, 1.09]

static var _cache: Dictionary = {} ## String seed_str -> Dictionary bundle


static func family_id(accent_idx: int) -> String:
	return FAMILY_IDS[clampi(accent_idx, 0, FAMILY_IDS.size() - 1)]


static func family_name(accent_idx: int) -> String:
	return FAMILY_NAMES[clampi(accent_idx, 0, FAMILY_NAMES.size() - 1)]


static func trait_label(trait_id: String) -> String:
	return String(TRAIT_LABELS.get(trait_id, "RUHIG"))


static func build(seed_str: String) -> Dictionary:
	if _cache.has(seed_str):
		return _cache[seed_str] as Dictionary
	var traits: Dictionary = traits_for(seed_str)
	var planted: Dictionary = _render_planted(traits)
	var hiding: ImageTexture = _render_hiding(traits)
	var closed: Dictionary = _render_closed(traits)
	var half_pulled: Dictionary = _render_stubborn_half(traits)
	var hole: ImageTexture = _render_hole(traits)
	var fruit_bodies: Array[ImageTexture] = []
	var fruit_glows: Array[ImageTexture] = []
	for f: int in 4:
		var fr: Dictionary = _render_uprooted_frame(traits, f)
		fruit_bodies.append(fr["body"] as ImageTexture)
		fruit_glows.append(fr["glow"] as ImageTexture)
	var out: Dictionary = {
		"traits": traits,
		"planted_body": planted["body"] as ImageTexture,
		"planted_glow": planted["glow"] as ImageTexture,
		"hiding_body": hiding,
		"closed_body": closed["body"] as ImageTexture,
		"closed_glow": closed["glow"] as ImageTexture,
		"half_body": half_pulled["body"] as ImageTexture,
		"half_glow": half_pulled["glow"] as ImageTexture,
		"hole_body": hole,
		"fruit_bodies": fruit_bodies,
		"fruit_glows": fruit_glows,
		"accent": traits["accent_bright"] as Color,
		"accent_mid": traits["accent_mid"] as Color,
		"family_id": family_id(int(traits["accent_idx"])),
		"family_name": family_name(int(traits["accent_idx"])),
		"pitch": float(traits["pitch"]),
	}
	_cache[seed_str] = out
	return out


static func traits_for(seed_str: String) -> Dictionary:
	var h: int = _fnv1a(seed_str)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = h
	var shape: int = rng.randi() % 4 ## 0=pear/drop, 1=ribbed lantern, 2=heart/turnip, 3=twin-bud
	var accent_idx: int = rng.randi() % ACCENTS.size()
	var pal: Array = ACCENTS[accent_idx]
	var crown_leaves: int = 3 + (rng.randi() % 3) ## 3..5 leaves
	var pattern: int = rng.randi() % 3 ## 0=vertical ribs/veins, 1=speckled constellation, 2=luminous collar/heart
	var lean: int = -1 if (rng.randi() % 2) == 0 else 1
	var tendril_count: int = 2 + (rng.randi() % 3) ## 2..4 rootlets
	var has_dew_bud: bool = (rng.randi() % 3) != 0
	var pitch: float = CHIME_PITCHES[absi(h >> 7) % CHIME_PITCHES.size()]
	return {
		"seed": h,
		"shape": shape,
		"accent_idx": accent_idx,
		"accent_deep": pal[0] as Color,
		"accent_mid": pal[1] as Color,
		"accent_bright": pal[2] as Color,
		"accent_core": pal[3] as Color,
		"crown_leaves": crown_leaves,
		"pattern": pattern,
		"lean": lean,
		"tendril_count": tendril_count,
		"has_dew_bud": has_dew_bud,
		"pitch": pitch,
	}


static func _fnv1a(s: String) -> int:
	var h: int = 2166136261
	for i: int in s.length():
		h = int(((h ^ s.unicode_at(i)) * 16777619) & 0x7FFFFFFF)
	return h


static func _new_img(w: int, h: int) -> Image:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return img


static func _put(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


static func _has_px(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false
	return img.get_pixel(x, y).a > 0.05


static func _add_outline(img: Image, outline_col: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var copy: Image = img.duplicate() as Image
	for y: int in h:
		for x: int in w:
			if copy.get_pixel(x, y).a > 0.05:
				continue
			var adj: bool = _has_px(copy, x - 1, y) or _has_px(copy, x + 1, y) \
				or _has_px(copy, x, y - 1) or _has_px(copy, x, y + 1)
			if adj:
				img.set_pixel(x, y, outline_col)


static func _draw_bulb(body: Image, glow: Image, traits: Dictionary, cx: float, cy: float, sx: float, sy: float, frame_i: int, clip_y_max: int) -> void:
	var shape: int = int(traits["shape"])
	var pattern: int = int(traits["pattern"])
	var lean: int = int(traits["lean"])
	var a_deep: Color = traits["accent_deep"] as Color
	var a_mid: Color = traits["accent_mid"] as Color
	var a_bright: Color = traits["accent_bright"] as Color
	var a_core: Color = traits["accent_core"] as Color

	var rx_base: float = (4.6 if shape == 1 else (4.2 if shape == 0 else (4.0 if shape == 2 else 4.1))) * sx
	var ry_base: float = (4.8 if shape == 2 else (4.3 if shape == 1 else 4.6)) * sy
	var w: int = body.get_width()
	var h: int = body.get_height()
	var y_end: int = mini(h - 1, clip_y_max)

	# Optional side-bud for shape == 3 (Doppel-Beere)
	var bud_cx: float = cx + float(lean) * 3.2 * sx
	var bud_cy: float = cy + 1.5 * sy

	for y: int in range(1, y_end):
		for x: int in range(1, w - 1):
			var dx: float = (float(x) - cx) / maxf(rx_base, 1.0)
			var dy: float = (float(y) - cy) / maxf(ry_base, 1.0)
			# Shape silhouette modulation
			var rx_mod: float = 1.0
			if shape == 0:
				# Pear / fig: slightly narrower crown, plump lower belly
				rx_mod = 0.78 + 0.34 * clampf((dy + 1.0) * 0.5, 0.0, 1.0)
			elif shape == 1:
				# Ribbed lantern melon: wider middle
				rx_mod = 1.08 - 0.16 * dy * dy
			elif shape == 2:
				# Heart / turnip: wide shoulders, tapered pointed tip
				rx_mod = 1.08 - 0.42 * clampf(dy, 0.0, 1.0)
			else:
				rx_mod = 0.96 + 0.12 * clampf(dy, -0.5, 0.8)

			var nx: float = dx / maxf(rx_mod, 0.35)
			var d2: float = nx * nx + dy * dy
			var in_main: bool = d2 <= 1.0
			var in_bud: bool = false
			if shape == 3:
				var bdx: float = (float(x) - bud_cx) / maxf(2.4 * sx, 1.0)
				var bdy: float = (float(y) - bud_cy) / maxf(2.5 * sy, 1.0)
				in_bud = (bdx * bdx + bdy * bdy) <= 1.0

			if not in_main and not in_bud:
				continue

			# Top-left directional lighting
			var lx: float = nx if in_main else ((float(x) - bud_cx) / maxf(2.4 * sx, 1.0))
			var ly: float = dy if in_main else ((float(y) - bud_cy) / maxf(2.5 * sy, 1.0))
			var ndotl: float = clampf(-lx * 0.58 - ly * 0.72 + 0.25, -1.0, 1.0)

			# Rib shading for lantern shape
			if shape == 1 and in_main:
				ndotl += 0.18 * cos(nx * PI * 2.2)

			var c: Color = BODY_SHADOW
			if ndotl > 0.62:
				c = BODY_RIM
			elif ndotl > 0.24:
				c = BODY_LIGHT
			elif ndotl > -0.18:
				c = BODY_MID
			elif ndotl > -0.52:
				c = BODY_DARK

			# Subtle ambient glow bleed on lower belly
			if ly > 0.35 and absf(lx) < 0.55 and c == BODY_DARK:
				c = BODY_MID

			_put(body, x, y, c)

			# Bioluminescent pattern on the fruit skin
			var is_vein: bool = false
			var is_hot: bool = false
			if in_main:
				if pattern == 0:
					# Curved bioluminescent ribs/veins
					var rib_v: float = absf(sin((nx * 2.3 + ly * 0.35 * float(lean)) * PI))
					is_vein = rib_v < 0.22 and ly > -0.65 and ly < 0.72
					is_hot = is_vein and absf(ly - 0.1) < 0.38
				elif pattern == 1:
					# Speckled spore constellation
					var gx: int = int(roundf(float(x) - cx))
					var gy: int = int(roundf(float(y) - cy))
					var s_hash: int = absi((gx * 37 + gy * 91 + int(traits["seed"])) % 17)
					is_vein = (s_hash == 2 or s_hash == 9) and d2 < 0.74
					is_hot = s_hash == 2 and d2 < 0.55
				else:
					# Glowing crescent belt on lower belly (leaves upper face clear for blinking spore-eyes!)
					var ring_d: float = absf(sqrt(nx * nx * 0.85 + (ly - 0.18) * (ly - 0.18)) - 0.48)
					is_vein = ring_d < 0.10 and ly > 0.02
					is_hot = ring_d < 0.055 and ly > 0.12 and ly < 0.50
			elif in_bud:
				var bd2: float = lx * lx + ly * ly
				is_vein = bd2 < 0.28
				is_hot = bd2 < 0.12

			if is_vein:
				var pulse_hi: bool = (frame_i == 2)
				_put(body, x, y, a_mid if not is_hot else a_bright)
				_put(glow, x, y, a_bright if (is_hot or pulse_hi) else a_deep)

	# Tiny top-left specular gleam (makes the fruit feel plump and juicy!)
	var spec_x: int = int(roundf(cx - rx_base * 0.38))
	var spec_y: int = int(roundf(cy - ry_base * 0.44))
	if spec_y < y_end and _has_px(body, spec_x, spec_y):
		_put(body, spec_x, spec_y, BODY_RIM)
		if _has_px(body, spec_x + 1, spec_y):
			_put(body, spec_x + 1, spec_y, a_core.lerp(BODY_RIM, 0.45))


static func _draw_crown(body: Image, glow: Image, traits: Dictionary, cx: int, stem_y: int, sway_x: int) -> void:
	var n_leaves: int = int(traits["crown_leaves"])
	var lean: int = int(traits["lean"])
	var a_bright: Color = traits["accent_bright"] as Color
	var a_core: Color = traits["accent_core"] as Color
	var has_bud: bool = bool(traits["has_dew_bud"])

	# Calyx base (tiny dark collar where leaves sprout from the fruit top)
	for dx: int in range(-2, 3):
		_put(body, cx + dx, stem_y, LEAF_DARK if absi(dx) == 2 else LEAF_MID)

	# 3..5 curled leaves fanning outward with luminous spore-tips
	var fan_angles: Array[float] = []
	if n_leaves == 3:
		fan_angles = [-0.95, 0.08 * float(lean), 0.95]
	elif n_leaves == 4:
		fan_angles = [-1.12, -0.38, 0.38, 1.12]
	else:
		fan_angles = [-1.20, -0.58, 0.0, 0.58, 1.20]

	for i: int in fan_angles.size():
		var ang: float = fan_angles[i]
		var length: int = 5 if absi(i - fan_angles.size() / 2) == 0 else (4 if i > 0 and i < fan_angles.size() - 1 else 4)
		for step: int in range(1, length + 1):
			var t: float = float(step) / float(length)
			var curl: float = sin(t * PI) * 0.65 * signf(ang if absf(ang) > 0.05 else float(lean))
			var px: int = cx + int(roundf(sin(ang) * float(step) * 1.18 + curl + float(sway_x) * t))
			var py: int = stem_y - int(roundf(cos(ang * 0.72) * float(step) * 1.05))
			var lc: Color = LEAF_DARK if step == 1 else (LEAF_MID if step == 2 else (LEAF_LIGHT if step < length else LEAF_TIP))
			_put(body, px, py, lc)
			if step == 2 and absf(ang) > 0.45:
				_put(body, px, py + 1, LEAF_DARK)
			if step == length:
				# Tiny glowing tip on alternating leaves so buried fruits shimmer softly in grass
				if (i % 2 == 0) or n_leaves == 3:
					_put(body, px, py, a_bright.lerp(LEAF_TIP, 0.35))
					_put(glow, px, py, a_bright)

	# Optional tiny arched bioluminescent spore-stamen bud peeking above the crown
	if has_bud:
		var bx: int = cx + lean + sway_x
		var by: int = stem_y - 5
		_put(body, bx, by + 1, LEAF_LIGHT)
		_put(body, bx + lean, by, a_core)
		_put(glow, bx + lean, by, a_core)
		_put(glow, bx, by, a_bright)


static func _draw_eyes(body: Image, glow: Image, traits: Dictionary, cx: int, cy: int, frame_i: int) -> void:
	## Cute subtle living spore-eyes that wake up & blink when pulled out of the soil!
	var a_bright: Color = traits["accent_bright"] as Color
	var a_core: Color = traits["accent_core"] as Color
	var lean: int = int(traits["lean"])
	var ex_l: int = cx - 2 + (1 if frame_i == 3 else (0 if frame_i != 1 else -1))
	var ex_r: int = cx + 2 + (1 if frame_i == 3 else (0 if frame_i != 1 else -1))
	var ey: int = cy - 1 + (0 if frame_i != 2 else -1)
	if frame_i == 2:
		# Happy blink / squint arcs (`^ ^` style 2px glint)
		_put(body, ex_l, ey, a_core)
		_put(body, ex_l - 1, ey + 1, a_bright)
		_put(glow, ex_l, ey, a_core)
		_put(body, ex_r, ey, a_core)
		_put(body, ex_r + 1, ey + 1, a_bright)
		_put(glow, ex_r, ey, a_core)
	else:
		# Expressive 1x2 bright spore eyes with dark socket pixel for crisp readability
		_put(body, ex_l, ey - 1, OUTLINE)
		_put(body, ex_l, ey, a_core)
		_put(glow, ex_l, ey, a_core)
		_put(body, ex_r, ey - 1, OUTLINE)
		_put(body, ex_r, ey, a_core)
		_put(glow, ex_r, ey, a_core)
		# Tiny cheek glow pixel on wiggle frames
		if frame_i == 1 or frame_i == 3:
			_put(glow, ex_l - 1, ey + 1, a_bright)
			_put(glow, ex_r + 1, ey + 1, a_bright)
	# Subtle tiny smile/dimple on frame 2 if lean > 0
	if frame_i == 2 and lean > 0:
		_put(body, cx, ey + 2, a_bright)


static func _draw_tendrils(body: Image, glow: Image, traits: Dictionary, cx: int, base_y: int, frame_i: int) -> void:
	var n: int = int(traits["tendril_count"])
	var a_mid: Color = traits["accent_mid"] as Color
	var kick: float = 0.0 if frame_i == 0 else (1.4 if frame_i == 1 else (-0.4 if frame_i == 2 else -1.4))
	var curl_up: float = 0.8 if frame_i == 2 else 0.0
	for i: int in n:
		var frac: float = 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5) * 2.0
		var sx: float = float(cx) + frac * 3.0
		var len_px: int = 4 if (i % 2 == 0) else 5
		for s: int in range(0, len_px):
			var t: float = float(s) / maxf(float(len_px - 1), 1.0)
			var wag: float = sin(t * PI * 1.1 + float(i) * 1.4) * (1.2 + absf(kick) * 0.5) + kick * t * 1.5
			var px: int = int(roundf(sx + frac * t * 1.4 + wag))
			var py: int = base_y + s - int(roundf(curl_up * t))
			var rc: Color = ROOT_DARK if s == 0 else (ROOT_MID if s < len_px - 1 else ROOT_TIP)
			_put(body, px, py, rc)
			if s == len_px - 1:
				_put(glow, px, py, a_mid)


static func _render_planted(traits: Dictionary) -> Dictionary:
	var w: int = 24
	var h: int = 24
	var body: Image = _new_img(w, h)
	var glow: Image = _new_img(w, h)
	var cx: int = 12
	var ground_y: int = 18

	# Upper shoulder of the buried fruit peeking out of the soil mound
	_draw_bulb(body, glow, traits, float(cx), float(ground_y + 1), 0.92, 0.88, 0, ground_y + 1)
	_draw_crown(body, glow, traits, cx, ground_y - 3, 0)
	_add_outline(body, OUTLINE)

	# Dark upturned soil mound cradling the buried fruit (bottom-center pivot at (12, 19))
	for y: int in range(ground_y - 1, ground_y + 4):
		for x: int in range(4, 20):
			var dx: float = (float(x) - float(cx)) / 6.8
			var dy: float = (float(y) - float(ground_y + 1)) / 2.6
			var mound: float = dx * dx + dy * dy
			if mound > 1.0:
				continue
			# Leave a clean notch in the middle top so the glowing fruit shoulder pokes through
			if y == ground_y - 1 and absi(x - cx) <= 2:
				continue
			var sc: Color = SOIL_DARK
			if dy < -0.15 and dx < 0.25:
				sc = SOIL_WARM if ((x + y) % 3 == 0) else SOIL_LIGHT
			elif dy < 0.35:
				sc = SOIL_MID
			_put(body, x, y, sc)
			# Mask out glow pixels buried beneath the front soil lip
			if y >= ground_y:
				_put(glow, x, y, Color(0.0, 0.0, 0.0, 0.0))

	# Small scattered pebbles & root nubs around the soil lip
	var h_seed: int = int(traits["seed"])
	_put(body, cx - 6 + (h_seed % 2), ground_y + 2, SOIL_LIGHT)
	_put(body, cx + 6 - ((h_seed >> 2) % 2), ground_y + 1, SOIL_MID)
	_put(body, cx - 3, ground_y + 2, SOIL_WARM)
	_put(body, cx + 2, ground_y + 2, SOIL_LIGHT)
	# Soft dark ground-shadow rim along bottom edge of mound
	for x: int in range(6, 19):
		if not _has_px(body, x, ground_y + 3):
			_put(body, x, ground_y + 3, Color(0.04, 0.02, 0.08, 0.45))

	return {
		"body": ImageTexture.create_from_image(body),
		"glow": ImageTexture.create_from_image(glow),
	}


static func _draw_soil_mound(body: Image, glow: Image, traits: Dictionary, cx: int, ground_y: int, notch_half: int) -> void:
	for y: int in range(ground_y - 1, ground_y + 4):
		for x: int in range(4, 20):
			var dx: float = (float(x) - float(cx)) / 6.8
			var dy: float = (float(y) - float(ground_y + 1)) / 2.6
			if dx * dx + dy * dy > 1.0:
				continue
			if notch_half > 0 and y == ground_y - 1 and absi(x - cx) <= notch_half:
				continue
			var sc: Color = SOIL_DARK
			if dy < -0.15 and dx < 0.25:
				sc = SOIL_WARM if ((x + y) % 3 == 0) else SOIL_LIGHT
			elif dy < 0.35:
				sc = SOIL_MID
			_put(body, x, y, sc)
			if glow != null and y >= ground_y:
				_put(glow, x, y, Color(0.0, 0.0, 0.0, 0.0))
	var h_seed: int = int(traits["seed"])
	_put(body, cx - 6 + (h_seed % 2), ground_y + 2, SOIL_LIGHT)
	_put(body, cx + 6 - ((h_seed >> 2) % 2), ground_y + 1, SOIL_MID)
	_put(body, cx - 3, ground_y + 2, SOIL_WARM)
	_put(body, cx + 2, ground_y + 2, SOIL_LIGHT)
	for x: int in range(6, 19):
		if not _has_px(body, x, ground_y + 3):
			_put(body, x, ground_y + 3, Color(0.04, 0.02, 0.08, 0.45))


static func _render_hiding(traits: Dictionary) -> ImageTexture:
	## Shy fruit ducked underground: soil mound with just a tiny curled leaf-tip peeking out
	var body: Image = _new_img(24, 24)
	var cx: int = 12
	var ground_y: int = 18
	var lean: int = int(traits["lean"])
	_put(body, cx, ground_y - 2, LEAF_DARK)
	_put(body, cx + lean, ground_y - 3, LEAF_MID)
	_put(body, cx + lean, ground_y - 4, LEAF_TIP)
	_put(body, cx - lean, ground_y - 2, LEAF_MID)
	_add_outline(body, OUTLINE)
	_draw_soil_mound(body, null, traits, cx, ground_y, 1)
	return ImageTexture.create_from_image(body)


static func _render_closed(traits: Dictionary) -> Dictionary:
	## Nocturnal fruit sleeping by day: tightly furled dark-violet bud with minimal glimmer
	var body: Image = _new_img(24, 24)
	var glow: Image = _new_img(24, 24)
	var cx: int = 12
	var ground_y: int = 18
	var a_deep: Color = traits["accent_deep"] as Color
	var a_mid: Color = traits["accent_mid"] as Color
	# Furled teardrop bud (leaves wrapped tightly over the fruit)
	for y: int in range(ground_y - 6, ground_y + 1):
		for x: int in range(cx - 3, cx + 4):
			var dx: float = (float(x) - float(cx)) / 3.1
			var dy: float = (float(y) - float(ground_y - 2)) / 3.8
			var taper: float = 1.0 - 0.52 * clampf(-dy, 0.0, 1.0)
			if (dx / maxf(taper, 0.35)) * (dx / maxf(taper, 0.35)) + dy * dy <= 1.0:
				var c: Color = LEAF_DARK if x >= cx else LEAF_MID
				if y >= ground_y - 3 and absi(x - cx) <= 1:
					c = BODY_MID
				_put(body, x, y, c)
	_put(body, cx, ground_y - 5, LEAF_LIGHT)
	_put(body, cx, ground_y - 2, a_deep)
	_put(glow, cx, ground_y - 2, a_mid)
	_add_outline(body, OUTLINE)
	_draw_soil_mound(body, glow, traits, cx, ground_y, 2)
	return {
		"body": ImageTexture.create_from_image(body),
		"glow": ImageTexture.create_from_image(glow),
	}


static func _render_stubborn_half(traits: Dictionary) -> Dictionary:
	## Stubborn fruit after pull 1/2: heaved halfway out with straining surface roots & wide eyes!
	var body: Image = _new_img(24, 24)
	var glow: Image = _new_img(24, 24)
	var cx: int = 12
	var ground_y: int = 19
	# Clinging surface roots stretched taut down into the soil
	for sx: int in [-4, -2, 2, 4]:
		for s: int in range(0, 4):
			_put(body, cx + sx + (signi(sx) if s >= 2 else 0), ground_y - 3 + s, ROOT_MID if s < 2 else ROOT_DARK)
	_draw_bulb(body, glow, traits, float(cx), float(ground_y - 5), 0.96, 1.04, 1, ground_y)
	_draw_eyes(body, glow, traits, cx, ground_y - 5, 1)
	_draw_crown(body, glow, traits, cx, ground_y - 10, 0)
	_add_outline(body, OUTLINE)
	_draw_soil_mound(body, glow, traits, cx, ground_y, 3)
	return {
		"body": ImageTexture.create_from_image(body),
		"glow": ImageTexture.create_from_image(glow),
	}


static func _render_hole(traits: Dictionary) -> ImageTexture:
	var w: int = 24
	var h: int = 16
	var img: Image = _new_img(w, h)
	var cx: int = 12
	var cy: int = 10
	var a_deep: Color = traits["accent_deep"] as Color
	# Upturned rim of earth around the freshly dug crater
	for y: int in range(cy - 3, cy + 4):
		for x: int in range(4, 20):
			var dx: float = (float(x) - float(cx)) / 6.4
			var dy: float = (float(y) - float(cy)) / 2.8
			var d2: float = dx * dx + dy * dy
			if d2 > 1.0:
				continue
			if d2 < 0.48:
				_put(img, x, y, HOLE_DEEP)
			elif d2 < 0.72:
				_put(img, x, y, SOIL_DARK)
			else:
				_put(img, x, y, SOIL_LIGHT if (y < cy) else SOIL_MID)
	# Faint lingering spore dust + tiny snapped root stub inside crater
	_put(img, cx - 1, cy, a_deep)
	_put(img, cx + 2, cy - 1, ROOT_MID)
	_put(img, cx - 3, cy + 2, SOIL_WARM)
	_put(img, cx + 4, cy + 2, SOIL_LIGHT)
	return ImageTexture.create_from_image(img)


static func _render_uprooted_frame(traits: Dictionary, frame_i: int) -> Dictionary:
	var w: int = 20
	var h: int = 24
	var body: Image = _new_img(w, h)
	var glow: Image = _new_img(w, h)
	var cx: float = 10.0
	var cy: float = 12.0
	var sx: float = 1.0
	var sy: float = 1.0
	var sway_x: int = 0
	if frame_i == 1:
		sx = 1.12
		sy = 0.88
		cy = 12.6
		sway_x = -1
	elif frame_i == 2:
		sx = 0.90
		sy = 1.14
		cy = 11.2
		sway_x = 0
	elif frame_i == 3:
		sx = 1.12
		sy = 0.88
		cy = 12.6
		sway_x = 1

	_draw_tendrils(body, glow, traits, int(cx), int(roundf(cy + 4.0 * sy)), frame_i)
	_draw_bulb(body, glow, traits, cx, cy, sx, sy, frame_i, h - 2)
	_draw_eyes(body, glow, traits, int(cx), int(roundf(cy)), frame_i)
	_draw_crown(body, glow, traits, int(cx), int(roundf(cy - 4.3 * sy)), sway_x)
	_add_outline(body, OUTLINE)

	return {
		"body": ImageTexture.create_from_image(body),
		"glow": ImageTexture.create_from_image(glow),
	}
