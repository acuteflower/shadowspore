class_name VoidZoneStyle
extends RefCounted
## Shared visual language for Void / Shadow creature ground telegraphs (`ShadowSpider`, `VoidListener`, `VoidCrusher`, `LightFisher`).
## Contrasts with ancient construct geometry (`QuartzGolem`) by rendering organic reality-rifts:
## `#120522` abyssal chasm crust, seething `#c21f3b -> #ff3366 -> #ffd6e4` danger waves, `#ff4fd8` / `#9a5cff` Void-corruption veins,
## sinuous writhing rims, and creature-specific organic filaments — while keeping exact hurtbox footprints unmistakable.

const ABYSS: Color = Color("120522")
const DEEP_CRIMSON: Color = Color("b8163a")
const HOT_CRIMSON: Color = Color("ff3062")
const SURGE_PALE: Color = Color("ffd8e6")
const VOID_MAGENTA: Color = Color("ff4fd8")
const VOID_VIOLET: Color = Color("9a5cff")


static func hash01(i: int, salt: float = 0.0) -> float:
	return fposmod(sin(float(i) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)


static func hash2(i: int, salt: float = 0.0) -> Vector2:
	return Vector2(
		fposmod(sin(float(i) * 12.9898 + salt) * 43758.5453, 1.0),
		fposmod(sin(float(i) * 78.233 + 3.1 + salt) * 19642.349, 1.0)
	)


static func warn_color(wave: float, hot: bool, corruption: float = 0.0) -> Color:
	var base: Color = DEEP_CRIMSON.lerp(SURGE_PALE if hot else HOT_CRIMSON, wave)
	if corruption > 0.01:
		base = base.lerp(VOID_MAGENTA if wave > 0.55 else VOID_VIOLET, corruption)
	return base


## Pixel-snapped 1x1 Void pixel with a 1px dark-purple abyssal chasm crust underneath so it pops on night grass, water, and torchlit stone alike.
static func rift_px(canvas: CanvasItem, pt: Vector2, col: Color, abyss_alpha: float) -> void:
	var p: Vector2 = pt.round()
	if abyss_alpha > 0.01:
		canvas.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color(ABYSS, abyss_alpha))
	canvas.draw_rect(Rect2(p, Vector2.ONE), col)


## Organic twitching Void-fissure / corrupted nerve-vein between `a` and `b` (never ruler-straight), with optional forked side-rootlets.
static func jagged_vein(
	canvas: CanvasItem,
	a: Vector2,
	b: Vector2,
	time: float,
	wobble_amp: float,
	col_primary: Color,
	col_corrupt: Color,
	abyss_alpha: float,
	salt: float = 0.0,
	forks: bool = false
) -> void:
	var span: Vector2 = b - a
	var dist: float = span.length()
	if dist < 2.0:
		return
	var dir: Vector2 = span / dist
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var steps: int = maxi(2, roundi(dist / 1.7))
	var pts: Array[Vector2] = []
	for i: int in range(steps + 1):
		var f: float = float(i) / float(steps)
		var taper: float = sin(f * PI)
		var wob: float = (sin(f * 13.0 - time * 8.5 + salt) * 0.65 + sin(f * 27.0 + time * 5.2 + salt * 2.1) * 0.35) * wobble_amp * taper
		var p: Vector2 = (a.lerp(b, f) + perp * wob).round()
		pts.append(p)
		if abyss_alpha > 0.01:
			canvas.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color(ABYSS, abyss_alpha))
	for i: int in pts.size():
		var use_corrupt: bool = ((i + int(absf(salt) * 3.0)) % 4 == 0)
		canvas.draw_rect(Rect2(pts[i], Vector2.ONE), col_corrupt if use_corrupt else col_primary)
		if forks and i > 2 and i < pts.size() - 3 and i % 6 == 0:
			var side: float = 1.0 if ((i / 6 + int(salt)) % 2 == 0) else -1.0
			var branch_len: float = 3.2 + hash01(i, salt) * 2.5
			var tip: Vector2 = pts[i] + (dir * 0.55 + perp * side * 0.85).normalized() * branch_len
			for bi: int in 3:
				var bp: Vector2 = pts[i].lerp(tip, float(bi + 1) / 3.0).round()
				canvas.draw_rect(Rect2(bp, Vector2.ONE), Color(col_corrupt, col_corrupt.a * (0.85 - float(bi) * 0.22)))


## Writhing Void-membrane rim along an arc (`arc_rad <= TAU`), with optional inward fangs or outward shadow-cilia.
## Wobble stays within `<= 0.9 px` so the hurtbox boundary remains 100% faithful.
static func sinuous_rim_arc(
	canvas: CanvasItem,
	origin: Vector2,
	aim_dir: Vector2,
	radius: float,
	arc_rad: float,
	squash: float,
	time: float,
	strength: float,
	hot: bool,
	thorn_dir: float = 0.0,
	thorn_count: int = 0
) -> void:
	var base_ang: float = aim_dir.angle()
	var arc_len: float = radius * arc_rad
	var steps: int = maxi(16, roundi(arc_len / 1.8))
	var abyss_a: float = 0.62 * strength
	var rim_hot: Color = Color(SURGE_PALE if hot else HOT_CRIMSON, 0.94 * strength)
	var rim_void: Color = Color(VOID_MAGENTA, 0.86 * strength)
	for i: int in range(steps + 1):
		var frac: float = float(i) / float(steps) - 0.5
		var ang: float = base_ang + frac * arc_rad
		var wriggle: float = sin(ang * 9.0 + time * 11.0) * 0.75
		var r_now: float = radius + wriggle
		var p: Vector2 = origin + Vector2(cos(ang) * r_now, sin(ang) * r_now * squash)
		var sub_p: Vector2 = origin + Vector2(cos(ang) * (r_now - 2.0), sin(ang) * (r_now - 2.0) * squash)
		canvas.draw_rect(Rect2(sub_p.round(), Vector2.ONE), Color(VOID_VIOLET if i % 2 == 0 else DEEP_CRIMSON, 0.48 * strength))
		rift_px(canvas, p, rim_void if i % 5 == 0 else rim_hot, abyss_a)

	if thorn_count > 0 and absf(thorn_dir) > 0.01:
		for ti: int in thorn_count:
			var t_frac: float = (float(ti) + 0.5) / float(thorn_count) - 0.5
			var t_ang: float = base_ang + t_frac * arc_rad + sin(time * 6.0 + float(ti) * 1.7) * 0.03
			var radial: Vector2 = Vector2(cos(t_ang), sin(t_ang) * squash)
			var r_base: float = radius + sin(t_ang * 9.0 + time * 11.0) * 0.6
			var thorn_len: float = (3.4 + 1.2 * sin(time * 9.0 + float(ti) * 2.3)) * absf(thorn_dir)
			var sgn: float = signf(thorn_dir)
			for s: int in range(1, roundi(thorn_len) + 1):
				var r_s: float = r_base + sgn * float(s)
				var tp: Vector2 = origin + radial * r_s
				var tc: Color = Color(SURGE_PALE if s == 1 and hot else (HOT_CRIMSON if s <= 2 else VOID_MAGENTA), (1.0 - float(s - 1) / (thorn_len + 1.0)) * 0.90 * strength)
				rift_px(canvas, tp, tc, abyss_a * 0.7)


## Seething Void floor fill for a cone/fan (`squash = 1.0` for world-space top-down, `LightFisher.SQUASH` for water perspective).
static func fill_void_fan(
	canvas: CanvasItem,
	origin: Vector2,
	aim_dir: Vector2,
	reach: float,
	arc_rad: float,
	squash: float,
	time: float,
	strength: float,
	locked: bool,
	hot: bool,
	samples: int = 480
) -> void:
	var speed: float = 19.0 if (locked or hot) else 9.5
	for i: int in samples:
		var rnd: Vector2 = hash2(i, 0.0)
		var dist: float = sqrt(rnd.x) * maxf(4.0, reach - 1.5)
		if dist < 5.0:
			continue
		var ang_off: float = (rnd.y - 0.5) * arc_rad
		var raw: Vector2 = aim_dir.rotated(ang_off) * dist
		var pt: Vector2 = Vector2(raw.x, raw.y * squash)
		var wave: float = 0.5 + 0.5 * sin(dist * 0.27 - time * speed + rnd.y * TAU)
		if wave < 0.45:
			continue
		var p: Vector2 = (origin + pt).round()
		if i % 7 == 0:
			canvas.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color(ABYSS, strength * 0.42))
		var corrupt_mix: float = 0.38 if (i % 6 == 0) else 0.0
		var col: Color = warn_color(wave, hot, corrupt_mix)
		canvas.draw_rect(Rect2(p, Vector2.ONE), Color(col, strength * (0.36 + wave * 0.44)))


## Seething Void floor fill for a linear corridor / rush / resonance lane.
static func fill_void_lane(
	canvas: CanvasItem,
	origin: Vector2,
	aim_dir: Vector2,
	length: float,
	half_width: float,
	time: float,
	strength: float,
	locked: bool,
	hot: bool,
	samples: int = 440
) -> void:
	var across: Vector2 = aim_dir.orthogonal()
	var speed: float = 20.0 if (locked or hot) else 10.0
	for i: int in samples:
		var rnd: Vector2 = hash2(i, 4.7)
		var dist: float = 5.0 + rnd.x * maxf(2.0, length - 6.0)
		var pt: Vector2 = aim_dir * dist + across * (rnd.y - 0.5) * (half_width * 1.9)
		var wave: float = 0.5 + 0.5 * sin(dist * 0.26 - time * speed + rnd.y * TAU)
		if wave < 0.46:
			continue
		var p: Vector2 = (origin + pt).round()
		if i % 7 == 0:
			canvas.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color(ABYSS, strength * 0.42))
		var corrupt_mix: float = 0.40 if (i % 6 == 0) else 0.0
		var col: Color = warn_color(wave, hot, corrupt_mix)
		canvas.draw_rect(Rect2(p, Vector2.ONE), Color(col, strength * (0.36 + wave * 0.44)))
