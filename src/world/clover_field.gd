class_name CloverField
extends Node2D
## A small field of clover you stand IN, not on. It is a crowd of little standing clumps (trefoil leaves on thin stems, blossoms on taller
## ones), batched per 6 px band of the field: every band is its own y-sorted node, so a band in front of Ellie hides her lower legs and a
## band behind her does not. The clumps bend away from whoever stands or walks in the field (`actors`) and sway in WorldWind's wind
## (clover_clumps.gdshader); a second layer glows at night (dew on the leaves, blossom hearts, void-violet tips).
## Nothing is shared between two fields: `plan` draws everything from the field's seed, and `_make_atlas` paints the clump pictures of
## THIS field (leaf shape, size, count, height, chevrons, dew, palette, blossom colours), so no two fields look alike.
const LIT: Shader = preload("res://assets/shaders/clover_clumps.gdshader")
const GLOW: Shader = preload("res://assets/shaders/clover_clumps_glow.gdshader")
const CELL: Vector2i = Vector2i(16, 20) ## one clump picture, the foot at (8, 18)
const BAND: float = 6.0
const LEAF_CELLS: int = 14
const FLOWER_CELLS: int = 6
const CELLS: int = LEAF_CELLS + FLOWER_CELLS + 1 ## + the four-leaf clover
const RAMPS: Array = [ ## the world's own foliage ramps (art_bush.py), so the field belongs to the meadow
	["1f3a2a", "2a5a38", "3a7a44", "50984e", "6cb460", "92d078"], ## sunlit meadow
	["1d2748", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d"], ## meadow
	["1a3040", "24544c", "30745a", "44946a", "62b084", "8cd0a4"], ## cool
]
const FLOWERS: Array = [ ## light, main, shade, heart
	["fff1e4", "e6dcc8", "b4a8a0", "ffe08a"], ## white
	["f4b4d8", "e8a9d0", "a8648c", "ffd0a0"], ## rose
	["d4c8f4", "bdb3e4", "7a6cae", "fff0a8"], ## lilac
	["ffe48a", "ecc050", "a88430", "fff8c8"], ## golden
	["c8e4ff", "9cc4ec", "5c88b4", "fff4c0"], ## pale blue
	["ffd4b4", "f0a888", "a86048", "fff0b0"], ## peach
]
const VIOLET: Color = Color("7048d0")
const DEW: Color = Color("c8fff4")
const ACTOR_SLOTS: int = 4

var radius: Vector2 = Vector2(40, 28) ## px, the plan's ellipse (the world level checks the ground under it)
var atlas_image: Image
var _materials: Array[ShaderMaterial] = []
var _energy: Dictionary = {} ## per player: how hard he is moving through the field (the clumps lean away more, then settle slowly)
var _notifier: VisibleOnScreenNotifier2D
var _on_screen: bool = false


## Everything a field is, drawn from `rng` (the caller seeds it from the chunk, so every peer gets the same field).
static func plan(rng: RandomNumberGenerator) -> Dictionary:
	var rx: float = rng.randf_range(26.0, 54.0)
	var colors: Array[int] = []
	for _i: int in rng.randi_range(1, 3):
		var pick: int = rng.randi_range(0, FLOWERS.size() - 1)
		if not colors.has(pick):
			colors.append(pick)
	return {
		"seed": rng.randi(), "rx": rx, "ry": rx * rng.randf_range(0.55, 0.8), "ramp": rng.randi_range(0, RAMPS.size() - 1), "warm": rng.randf_range(0.0, 0.3),
		"wobble": [rng.randf_range(0.08, 0.2), rng.randf_range(0.06, 0.16), rng.randf_range(0.02, 0.08), rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU],
		"step": rng.randf_range(5.0, 8.0), "patchy": rng.randf_range(0.1, 0.45), "lobe": rng.randf_range(2.0, 3.0), "shape": rng.randi_range(0, 2),
		"leaves": rng.randi_range(1, 3), "height": rng.randf_range(0.7, 1.3), "chevron": rng.randf_range(0.3, 0.95), "void": rng.randf_range(0.0, 0.3),
		"dew": rng.randf_range(0.1, 0.5), "flower_colors": colors, "flower_share": rng.randf_range(0.02, 0.13), "lucky": rng.randf() < 0.3,
	}


func setup(field: Dictionary, center: Vector2) -> void:
	position = center
	name = "CloverField"
	y_sort_enabled = true ## the bands sort with Ellie, trees and bushes in the level's Props chain
	radius = Vector2(float(field.rx), float(field.ry))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(field.seed)
	var images: Array[Image] = _make_atlas(field, rng)
	atlas_image = images[0]
	var textures: Array[ImageTexture] = [ImageTexture.create_from_image(images[0]), ImageTexture.create_from_image(images[1])]
	# the clumps, in a jittered grid thinned by the field's patchy density, sorted into bands from back to front
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = int(field.seed)
	noise.frequency = 0.09
	var bands: Dictionary = {} ## band index -> Array[Dictionary]
	var step: float = float(field.step)
	var y: float = -radius.y * 1.2
	while y < radius.y * 1.2:
		var x: float = -radius.x * 1.2
		while x < radius.x * 1.2:
			var at: Vector2 = Vector2(x + rng.randf_range(-0.45, 0.45) * step, y + rng.randf_range(-0.45, 0.45) * step * 0.8)
			var core: float = _core(field, noise, at)
			if core > 0.04 and rng.randf() < pow(core, 0.7) * 1.15:
				var cell: int = rng.randi_range(0, LEAF_CELLS - 1)
				if core < 0.3: ## the ragged edge is low
					cell = rng.randi_range(0, 4)
				elif rng.randf() < float(field.flower_share) * (0.4 + core):
					cell = LEAF_CELLS + rng.randi_range(0, FLOWER_CELLS - 1)
				elif bool(field.lucky) and core > 0.5 and rng.randf() < 0.01:
					cell = CELLS - 1
				var band: int = floori(at.y / BAND)
				(bands.get_or_add(band, []) as Array).append({"at": at, "cell": cell, "flip": rng.randf() < 0.5, "tint": rng.randf_range(0.9, 1.08), "phase": rng.randf(), "sway": rng.randf_range(0.8, 1.5)})
			x += step
		y += step * 0.8
	var keys: Array = bands.keys()
	keys.sort()
	for key: int in keys:
		_add_band(key, bands[key] as Array, textures)
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-radius * 1.3 - Vector2(10, 40), radius * 2.6 + Vector2(20, 60))
	_notifier.screen_entered.connect(func() -> void: _on_screen = true)
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(_notifier)


func _add_band(key: int, clumps: Array, textures: Array[ImageTexture]) -> void:
	var band: Node2D = Node2D.new()
	band.position = Vector2(0.0, (float(key) + 1.0) * BAND) ## sorts by its bottom edge
	add_child(band)
	for layer: int in 2:
		var instance: MultiMeshInstance2D = MultiMeshInstance2D.new()
		instance.texture = textures[layer]
		instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = LIT if layer == 0 else GLOW
		shader_material.set_shader_parameter("count", float(CELLS))
		shader_material.set_shader_parameter("actors", _no_actors())
		shader_material.set_shader_parameter("band_origin", global_position + band.position)
		_materials.append(shader_material)
		instance.material = shader_material
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(CELL)
		instance.multimesh = MultiMesh.new()
		instance.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		instance.multimesh.use_colors = true
		instance.multimesh.use_custom_data = true
		instance.multimesh.mesh = quad
		instance.multimesh.instance_count = clumps.size()
		for i: int in clumps.size():
			var c: Dictionary = clumps[i]
			var at: Vector2 = (c.at as Vector2).round() - Vector2(0.0, band.position.y)
			instance.multimesh.set_instance_transform_2d(i, Transform2D(Vector2(-1.0 if bool(c.flip) else 1.0, 0.0), Vector2(0.0, 1.0), at + Vector2(0.0, -9.0)))
			instance.multimesh.set_instance_color(i, Color(c.tint, c.tint, c.tint, 1.0))
			instance.multimesh.set_instance_custom_data(i, Color(float(c.cell) / float(CELLS), float(c.phase), float(c.sway), at.x / 256.0 + 0.5))
		band.add_child(instance)


## Local player: the clumps near anyone in or at the field lean away; harder while he moves, settling slowly afterwards.
func _process(delta: float) -> void:
	if not _on_screen:
		return
	var actors: PackedVector4Array = _no_actors()
	var used: int = 0
	for player: Player in Player.all:
		if not is_instance_valid(player) or used >= ACTOR_SLOTS:
			continue
		var rel: Vector2 = player.global_position - global_position
		if absf(rel.x) > radius.x * 1.3 + 24.0 or absf(rel.y) > radius.y * 1.3 + 24.0:
			continue
		var id: int = player.get_instance_id()
		var energy: float = float(_energy.get(id, 0.0))
		var moving: float = clampf(player.velocity.length() / 70.0, 0.0, 1.0)
		energy = move_toward(energy, moving, delta * (7.0 if moving > energy else 0.7))
		_energy[id] = energy
		actors[used] = Vector4(player.global_position.x, player.global_position.y, 0.4 + 0.6 * energy, 0.0)
		used += 1
	for shader_material: ShaderMaterial in _materials:
		shader_material.set_shader_parameter("actors", actors)


static func _no_actors() -> PackedVector4Array:
	var empty: PackedVector4Array = PackedVector4Array()
	empty.resize(ACTOR_SLOTS)
	return empty


## The outline factor at angle `a`: 1.0 is the plan's radius; the three harmonics make every field its own shape.
static func _shape(field: Dictionary, a: float) -> float:
	var w: Array = field.wobble
	return 1.0 + float(w[0]) * sin(2.0 * a + float(w[3])) + float(w[1]) * sin(3.0 * a + float(w[4])) + float(w[2]) * sin(5.0 * a + float(w[5]))


## 1 in the heart of the field, 0 at and beyond its wobbling rim, with noise so the density is patchy.
static func _core(field: Dictionary, noise: FastNoiseLite, p: Vector2) -> float:
	var u: Vector2 = Vector2(p.x / float(field.rx), p.y / float(field.ry))
	var q: float = u.length() / _shape(field, u.angle())
	return clampf(1.0 - pow(q, 2.2) + noise.get_noise_2d(p.x, p.y) * float(field.patchy), 0.0, 1.0)


# ------------------------------------------------------------------------------ this field's own clump pictures
func _make_atlas(field: Dictionary, rng: RandomNumberGenerator) -> Array[Image]:
	var lit: Image = Image.create(CELL.x * CELLS, CELL.y, false, Image.FORMAT_RGBA8)
	var glow: Image = Image.create(CELL.x * CELLS, CELL.y, false, Image.FORMAT_RGBA8)
	var pal: Array[Color] = []
	for hex: String in RAMPS[int(field.ramp)]:
		pal.append(Color(hex).lerp(Color("8aa84a"), float(field.warm) * 0.6)) ## some fields lean toward olive
	for cell: int in LEAF_CELLS:
		var tall: int = 0 if cell < 5 else (1 if cell < 10 else 2) ## low, middle, tall
		var count: int = clampi(int(field.leaves) + rng.randi_range(-1, 1) + (1 if tall == 2 else 0), 1, 4)
		var parts: Array[Dictionary] = []
		for _i: int in count:
			var reach: float = (2.0 + 3.5 * float(tall + 1) * float(field.height)) * rng.randf_range(0.7, 1.15)
			var a: float = rng.randf_range(-0.9, 0.9)
			parts.append({"a": a, "c": Vector2(8.0 + sin(a) * reach, 18.0 - cos(a) * reach), "s": float(field.lobe) / 2.0 * rng.randf_range(0.8, 1.2)})
		parts.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return (p.c as Vector2).y < (q.c as Vector2).y)
		for part: Dictionary in parts:
			var c: Vector2 = part.c
			c.y = maxf(c.y, 5.0 + 2.4 * float(part.s))
			_stem(lit, cell, Vector2(8.0 + rng.randf_range(-1.0, 1.0), 18.0), c, pal)
			_trefoil(lit, glow, cell, c, float(part.s), float(part.a), pal, field, rng)
	for cell: int in FLOWER_CELLS:
		var colors: Array = field.flower_colors
		_flower(lit, glow, LEAF_CELLS + cell, FLOWERS[int(colors[cell % colors.size()])], pal, field, rng)
	_lucky(lit, glow, CELLS - 1, pal)
	return [lit, glow]


static func _px(image: Image, cell: int, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < CELL.x and y < CELL.y:
		image.set_pixel(cell * CELL.x + x, y, color)


static func _stem(image: Image, cell: int, from: Vector2, to: Vector2, pal: Array[Color]) -> void:
	var steps: int = maxi(1, int(from.distance_to(to)))
	for i: int in steps:
		var p: Vector2 = from.lerp(to, float(i) / float(steps))
		_px(image, cell, int(p.x), int(p.y), pal[1] if i % 3 else pal[2])


## One trefoil seen from above and in front: three lobes (round, broad or pointed, by the field's `shape`), lit from the top left, a
## pale chevron on most, now and then a void-violet tip and a drop of dew (the glow layer carries both).
func _trefoil(lit: Image, glow: Image, cell: int, c: Vector2, s: float, tilt: float, pal: Array[Color], field: Dictionary, rng: RandomNumberGenerator) -> void:
	var turn: float = tilt * 0.6 + rng.randf() * TAU
	var base: int = clampi(int(2.0 + rng.randf_range(0.0, 1.6)), 1, 4)
	for k: int in 3:
		var a: float = turn + TAU * float(k) / 3.0
		var axis: Vector2 = Vector2(cos(a), sin(a) * 0.75)
		var lc: Vector2 = c + axis * 2.2 * s
		var ru: float = 1.7 * s
		var rv: float = 1.7 * s
		match int(field.shape):
			1:
				ru = 1.4 * s
				rv = 2.1 * s
			2:
				ru = 2.5 * s
				rv = 1.4 * s
		var dir: Vector2 = axis.normalized()
		for y: int in range(int(lc.y - 3.0 * s) - 1, int(lc.y + 3.0 * s) + 2):
			for x: int in range(int(lc.x - 3.0 * s) - 1, int(lc.x + 3.0 * s) + 2):
				var d: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5) - lc
				var u: float = d.dot(dir) / ru
				var v: float = (d.x * -dir.y + d.y * dir.x) / rv
				if int(field.shape) == 2:
					v /= maxf(1.0 - 0.3 * u, 0.4) ## tapers to a point
				if u * u + v * v > 1.0:
					continue
				var light: float = -d.x * 0.06 - d.y * 0.09
				_px(lit, cell, x, y, pal[clampi(base + (1 if light > 0.12 else (-1 if light < -0.14 else 0)), 0, 5)])
		var cx: int = int(lc.x)
		var cy: int = int(lc.y)
		if rng.randf() < float(field.chevron): ## the pale V across the lobe
			_px(lit, cell, cx, cy, pal[mini(base + 2, 5)])
			_px(lit, cell, cx - 1, cy - 1, pal[mini(base + 2, 5)])
			_px(lit, cell, cx + 1, cy - 1, pal[mini(base + 2, 5)])
		if rng.randf() < float(field.void):
			_px(lit, cell, cx + int(dir.x * ru), cy + int(dir.y * ru), VIOLET)
			_px(glow, cell, cx + int(dir.x * ru), cy + int(dir.y * ru), Color(VIOLET, 1.0).lightened(0.35))
		if rng.randf() < float(field.dew) * 0.1:
			_px(glow, cell, cx - 1, cy - 1, DEW)
			_px(glow, cell, cx - 2, cy - 1, Color(DEW, 0.4))
			_px(glow, cell, cx - 1, cy - 2, Color(DEW, 0.4))


## A tall stalk with a round blossom head in one of this field's colours, a few leaves at its foot.
func _flower(lit: Image, glow: Image, cell: int, tones: Array, pal: Array[Color], field: Dictionary, rng: RandomNumberGenerator) -> void:
	var height: float = rng.randf_range(9.0, 14.0) * float(field.height)
	var head: Vector2 = Vector2(8.0 + rng.randf_range(-2.0, 2.0), maxf(18.0 - height, 4.5))
	var r: float = rng.randf_range(2.2, 3.2)
	_trefoil(lit, glow, cell, Vector2(8.0 + rng.randf_range(-3.0, 3.0), 15.0), 0.7, 0.0, pal, field, rng)
	_stem(lit, cell, Vector2(8.0, 18.0), head + Vector2(0, r), pal)
	var light: Color = Color(tones[0])
	var main: Color = Color(tones[1])
	var shade: Color = Color(tones[2])
	for y: int in range(int(head.y - r) - 1, int(head.y + r) + 2):
		for x: int in range(int(head.x - r) - 1, int(head.x + r) + 2):
			var d: Vector2 = (Vector2(float(x) + 0.5, float(y) + 0.5) - head) / r
			if d.length_squared() > 1.0:
				continue
			var shade_amount: float = d.x * 0.5 + d.y * 0.7
			_px(lit, cell, x, y, light if shade_amount < -0.35 else (shade if shade_amount > 0.45 else main))
	for k: int in 3: ## a few petals sticking out of the round head
		var a: float = rng.randf() * TAU
		_px(lit, cell, int(head.x + cos(a) * (r + 1.0)), int(head.y + sin(a) * (r + 1.0)), main)
	_px(glow, cell, int(head.x), int(head.y), Color(tones[3]))
	_px(glow, cell, int(head.x) - 1, int(head.y) - 1, Color(light, 0.7))


## The four-leaf clover: a gold-green leaf in the middle of the clump; the shader makes it glint.
static func _lucky(lit: Image, glow: Image, cell: int, pal: Array[Color]) -> void:
	var gold: Color = Color("c8d85a")
	_stem(lit, cell, Vector2(8.0, 18.0), Vector2(8.0, 11.0), pal)
	for d: Vector2i in [Vector2i(-2, -1), Vector2i(2, -1), Vector2i(-1, -3), Vector2i(1, -3)]:
		for e: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_px(lit, cell, 8 + d.x + e.x, 8 + d.y + e.y, gold if e == Vector2i.ZERO else pal[4])
	_px(glow, cell, 8, 8, Color("f4ffb0"))
	_px(glow, cell, 7, 7, Color(Color("f4ffb0"), 0.5))
	_px(glow, cell, 9, 7, Color(Color("f4ffb0"), 0.5))
