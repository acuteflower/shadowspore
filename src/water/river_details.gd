class_name RiverDetails
extends Node2D
## Cosmetic residents are deterministic on every peer. Rocks occupy already
## blocked deep water only; no new obstacle may close a ford.
var _sprites: Array[Sprite2D] = []
var _rows: PackedInt32Array = []
var _phases: PackedFloat32Array = []
var _flows: PackedVector2Array = []
var _rivers: WorldRivers
var _spec: Dictionary
var _time: float = 0.0
var disturbances: Array = []
var _glows: Array[Sprite2D] = []
var glow_materials: Array[ShaderMaterial] = []
var _night: float = 0.0
var _flow_image: Image
var _origin: Vector2
var _jellies: Array[Dictionary] = []
var _water_glows: Dictionary = {} ## water-plant sprite -> its glow sprite (same frame)
var _water_homes: Dictionary = {} ## water-plant sprite -> where it floats
var _bank_glow_sheet: Texture2D
var _flora_shader: Shader ## river_flora.gdshader; the materials stay per plant (bend and current are per-plant uniforms)

func setup(rivers: WorldRivers, cell: Vector2i, flow_image: Image = null) -> void:
	_rivers = rivers
	_flow_image = flow_image
	_origin = Vector2(cell) * 512.0
	_night = TimeManager.night_amount()
	_spec = DataRegistry.table("river_life")
	add_to_group("night_lights")
	var data: Dictionary = rivers._data
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, int(_spec["seed"])))
	var spacing: int = int(_spec["spacing"])
	var sheet: Texture2D = load("res://assets/water/river_details.png") as Texture2D
	for y: int in range(16, 512, spacing):
		for x: int in range(16, 512, spacing):
			if _sprites.size() >= int(_spec["max_chunk"]): break
			var at: Vector2 = Vector2(cell) * 512.0 + Vector2(x + rng.randf_range(-8, 8), y + rng.randf_range(-8, 8)).round()
			var field: Vector2 = rivers.field_at(at)
			var row: int = -1
			if field.x > 1.0 and field.x < 9.0: row = 1
			elif field.x < -2.0 and field.y > 0.15 and field.y < 0.55: row = 0 if rng.randf() < 0.8 else 4
			elif field.x < -10.0 and field.y > 0.78 and rng.randf() < 0.3:
				var ford_free: bool = true
				for ford: Array in data["fords"]:
					if at.distance_to(Vector2(float(ford[0]), float(ford[1]))) < float(_spec["rock_clear_ford"]): ford_free = false
				if ford_free: row = 2 if rng.randf() < 0.7 else 3
			if row < 0: continue
			# Pads only in collecting pools, never strewn over fast narrow channels.
			for basin: Dictionary in data["basins"]:
				var outlet: Array = basin["outlet"]
				if row == 0 and at.distance_to(Vector2(float(outlet[0]), float(outlet[1]))) < float(basin["radius"]): row = 5
			if row == 0 and rivers.lake_at(at) and field.y < 0.48 and rng.randf() < 0.3:
				row = 5
			var sprite: Sprite2D = Sprite2D.new()
			sprite.texture = sheet
			sprite.hframes = 8
			sprite.vframes = 6
			sprite.centered = false
			sprite.offset = Vector2(-16, -34)
			sprite.position = at
			sprite.z_index = -6 if row in [0, 4, 5] else 0
			if row in [0, 4]: sprite.modulate = Color(0.65, 0.85, 0.8, 0.65)
			if row in [0, 1]:
				sprite.material = _flora_material()
			add_child(sprite)
			if row in [0, 1, 4, 5]: _make_cuttable(sprite)
			if row == 1: sprite.add_to_group("river_perches")
			if row in [2, 3]: sprite.add_to_group("river_cover")
			_sprites.append(sprite)
			_rows.append(row)
			_phases.append(rng.randf() * TAU)
			var flow: Vector2 = Vector2.RIGHT
			if flow_image != null:
				var local: Vector2i = Vector2i(at - Vector2(cell) * 512.0)
				var pixel: Color = flow_image.get_pixel(clampi(local.x, 0, 511), clampi(local.y, 0, 511))
				flow = Vector2(pixel.b * 2.0 - 1.0, pixel.a * 2.0 - 1.0).limit_length()
			_flows.append(flow)
			if row in [2, 3] and disturbances.size() < 8: disturbances.append([at.x, at.y, float(_spec["rock_radius"]), 0.75])

	for basin: Dictionary in data["basins"]:
		var outlet: Array = basin["outlet"]
		var at: Vector2 = Vector2(float(outlet[0]), float(outlet[1])) + Vector2(5, -2)
		if Vector2i((at / 512.0).floor()) != cell or _sprites.size() >= int(_spec["max_chunk"]): continue
		var pad: Sprite2D = Sprite2D.new()
		pad.texture = sheet
		pad.hframes = 8
		pad.vframes = 6
		pad.centered = false
		pad.offset = Vector2(-16, -34)
		pad.position = at
		pad.z_index = -6
		add_child(pad)
		_sprites.append(pad)
		_rows.append(5)
		_phases.append(rng.randf() * TAU)
		_flows.append(Vector2.ZERO)
	_bank_props(rivers, cell)
	_water_glow(rivers, cell)
	_water_flora(rivers, cell)
	_spawn_jellies(rivers, cell)

## The sickle can cut this plant (see WaterPlantCut).
func _make_cuttable(sprite: Sprite2D) -> void:
	var cutter: WaterPlantCut = WaterPlantCut.new()
	cutter.setup(sprite)
	add_child(cutter)


## Shore dressing (rows 10-15 of `_rows` = rows 0-5 of bank_details.png): reeds, stones, driftwood,
## wet-grass tufts with blooms, ferns and foam-lapped stones, placed in random clumps along the bank.
func _bank_props(rivers: WorldRivers, cell: Vector2i) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, int(_spec["seed"]) + 77))
	var clumps: FastNoiseLite = FastNoiseLite.new()
	clumps.seed = int(_spec["seed"])
	clumps.frequency = 0.012
	var sheet: Texture2D = load("res://assets/water/bank_details.png") as Texture2D
	var spacing: int = int(_spec["bank_spacing"])
	var placed: int = 0
	for y: int in range(0, 512, spacing):
		for x: int in range(0, 512, spacing):
			if placed >= int(_spec["bank_max_chunk"]): return
			var at: Vector2 = Vector2(cell) * 512.0 + Vector2(x + rng.randf() * spacing, y + rng.randf() * spacing).round()
			var gap: float = rivers.field_at(at).x
			if gap < 1.5 or gap > 16.0: continue
			# Patchy: most of the shore stays bare, some stretches are crowded.
			var density: float = clampf(0.30 + clumps.get_noise_2dv(at) * 0.9, 0.04, 0.8)
			if rng.randf() > density: continue
			var kind: int = _bank_kind(gap, rng.randf())
			for i: int in 1 + (rng.randi() % 3 if rng.randf() < 0.5 else 0):
				var spot: Vector2 = (at + Vector2(rng.randf_range(-11, 11), rng.randf_range(-6, 6)) * (1.0 if i > 0 else 0.0)).round()
				var spot_gap: float = rivers.field_at(spot).x
				if spot_gap < 1.5 or spot_gap > 17.0: continue
				_add_bank_sprite(sheet, spot, kind, rng.randi() % 6, rng)
				placed += 1

## 0 reeds, 1 stones, 2 driftwood, 3 blooms, 4 ferns, 5 foam stones, 6 glow reeds (7 lilies, 8 kelp: see _water_glow); chosen by distance to the water.
func _bank_kind(gap: float, roll: float) -> int:
	if gap < 4.0: return 5 if roll < 0.25 else (0 if roll < 0.45 else (6 if roll < 0.7 else (2 if roll < 0.85 else 1)))
	if gap < 9.0: return 0 if roll < 0.15 else (6 if roll < 0.35 else (1 if roll < 0.5 else (4 if roll < 0.7 else 3)))
	return 3 if roll < 0.4 else (6 if roll < 0.55 else (4 if roll < 0.8 else (1 if roll < 0.92 else 2)))

func _add_bank_sprite(sheet: Texture2D, at: Vector2, kind: int, variant: int, rng: RandomNumberGenerator) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = sheet
	sprite.hframes = 6
	sprite.vframes = 9
	sprite.frame = kind * 6 + variant
	sprite.centered = false
	sprite.offset = Vector2(-16, -28)
	sprite.position = at
	sprite.flip_h = kind in [0, 3, 4, 6, 8] and rng.randf() < 0.5
	if kind in [0, 3, 4, 6, 8]:
		sprite.material = _flora_material()
	if kind >= 7: sprite.z_index = -6  # in the water, under the y-sorted shore props
	add_child(sprite)
	if kind in [0, 3, 4, 6, 7, 8]: _make_cuttable(sprite)
	_sprites.append(sprite)
	_rows.append(10 + kind)
	_phases.append(rng.randf() * TAU)
	_flows.append(Vector2.ZERO)
	if kind in [3, 6, 7, 8]:  # luminous plants: only the glowing pixels, drawn unlit and brighter at night
		var glow: Sprite2D = Sprite2D.new()
		if _bank_glow_sheet == null: _bank_glow_sheet = load("res://assets/water/bank_details_glow.png") as Texture2D
		glow.texture = _bank_glow_sheet
		glow.hframes = 6
		glow.vframes = 9
		glow.frame = sprite.frame
		glow.centered = false
		glow.offset = sprite.offset
		glow.flip_h = sprite.flip_h
		glow.material = Unlit.material()
		glow.modulate.a = lerpf(0.25, 1.0, _night)
		sprite.add_child(glow)
		_glows.append(glow)

## Three more water plants (rows 20-22 of `_rows`; sheet assets/water/water_flora.png, tools/art_water_plants.py): Linsenteppich (a mat of
## tiny leaves on calm shallows and pools, drifting a little), Goldmummel (floating heart leaves with golden cup blooms: open by day,
## closed and glowing at night, in shallows and lakes) and Federkraut (feathery hornwort under the surface of deeper water, swaying).
## They come in clumps of two to four, only inside the water (4 px from the bank), and are cosmetic and deterministic per chunk.
func _water_flora(rivers: WorldRivers, cell: Vector2i) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, int(_spec["seed"]) + 4141))
	var sheet: Texture2D = load("res://assets/water/water_flora.png") as Texture2D
	var glow_sheet: Texture2D = load("res://assets/water/water_flora_glow.png") as Texture2D
	var spacing: int = int(_spec["water_flora_spacing"])
	var placed: int = 0
	for kind: int in [22, 20, 21]: ## the plants under the surface first, so the floating ones lie over them
		var budget: int = int(_spec["water_flora_max"]) * ([22, 20, 21].find(kind) + 1) / 3 ## each kind may use its third
		for y: int in range(0, 512, spacing):
			for x: int in range(0, 512, spacing):
				if placed >= budget: break
				var centre: Vector2 = Vector2(cell) * 512.0 + Vector2(x + rng.randf() * spacing, y + rng.randf() * spacing).round()
				var field: Vector2 = rivers.field_at(centre)
				var lake: bool = rivers.lake_at(centre)
				if field.x > -6.0 or rng.randf() > (0.5 if lake else 0.3): continue
				if kind == 20 and field.y > 0.4: continue
				if kind == 21 and (field.y < 0.06 or field.y > 0.5): continue
				if kind == 22 and (field.y < 0.28 or field.y > 0.85): continue
				var variant: int = rng.randi() % 6
				for i: int in rng.randi_range(2, 4):
					if placed >= budget: break
					var at: Vector2 = (centre + Vector2(rng.randf_range(-16, 16), rng.randf_range(-8, 8)) * (1.0 if i > 0 else 0.0)).round()
					var spot: Vector2 = rivers.field_at(at)
					if spot.x > -4.0 or spot.y < 0.04: continue
					_add_water_sprite(sheet, glow_sheet, at, kind, variant if i == 0 or rng.randf() < 0.6 else rng.randi() % 6, rng)
					placed += 1

func _add_water_sprite(sheet: Texture2D, glow_sheet: Texture2D, at: Vector2, kind: int, variant: int, rng: RandomNumberGenerator) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = sheet
	sprite.hframes = 6
	sprite.vframes = 6
	sprite.frame = (kind - 20) * 12 + variant
	sprite.centered = false
	sprite.offset = Vector2(-16, -28)
	sprite.position = at
	sprite.z_index = -6
	sprite.flip_h = rng.randf() < 0.5
	sprite.set_meta("variant", variant)
	if kind == 22:
		sprite.material = _flora_material()
	add_child(sprite)
	_make_cuttable(sprite)
	_sprites.append(sprite)
	_rows.append(kind)
	_phases.append(rng.randf() * TAU)
	_flows.append(_flow_at(at))
	_water_homes[sprite] = at
	var glow: Sprite2D = Sprite2D.new()
	glow.texture = glow_sheet
	glow.hframes = 6
	glow.vframes = 6
	glow.frame = sprite.frame
	glow.centered = false
	glow.offset = sprite.offset
	glow.flip_h = sprite.flip_h
	glow.material = Unlit.material()
	glow.modulate.a = lerpf(0.25, 1.0, _night)
	sprite.add_child(glow)
	_glows.append(glow)
	_water_glows[sprite] = glow

## The frame and drift of a water plant (see `_water_flora`).
func _animate_water_plant(sprite: Sprite2D, row: int, phase: float, flow: Vector2) -> void:
	var variant: int = int(sprite.get_meta("variant"))
	var state: int = 0
	match row:
		20: ## the mat breathes: two shimmer frames, and it drifts a pixel or two with the current
			state = posmod(int(_time * 0.8 + phase), 2)
			var home: Vector2 = _water_homes[sprite]
			sprite.position = home + (Vector2(sin(_time * 0.27 + phase), cos(_time * 0.21 + phase * 2.0)) * 1.6 + flow * 1.2).round()
		21: ## open by day, shut and glowing at night
			state = 1 if _night > 0.45 else 0
		22: ## sways in the current
			state = posmod(int(_time * 1.3 + phase), 2)
	var frame: int = ((row - 20) * 2 + state) * 6 + variant
	sprite.frame = frame
	(_water_glows[sprite] as Sprite2D).frame = frame

## Luminous lilies and kelp rooted in the shallows (kinds 7 and 8), drawn under the shore props.
func _water_glow(rivers: WorldRivers, cell: Vector2i) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, int(_spec["seed"]) + 303))
	var sheet: Texture2D = load("res://assets/water/bank_details.png") as Texture2D
	var placed: int = 0
	for y: int in range(0, 512, 30):
		for x: int in range(0, 512, 30):
			if placed >= int(_spec["water_glow_max"]): return
			var at: Vector2 = Vector2(cell) * 512.0 + Vector2(x + rng.randf() * 30.0, y + rng.randf() * 30.0).round()
			var field: Vector2 = rivers.field_at(at)
			if field.x > -3.0 or field.y < 0.08 or field.y > 0.6 or rng.randf() > 0.32: continue
			var kind: int = 7 if field.y < 0.3 and rng.randf() < 0.6 else 8
			_add_bank_sprite(sheet, at, kind, rng.randi() % 6, rng)
			_flows[_flows.size() - 1] = _flow_at(at)
			placed += 1

func _flow_at(point: Vector2) -> Vector2:
	if _flow_image == null: return Vector2.ZERO
	var local: Vector2i = Vector2i(point - _origin)
	if local.x < 0 or local.y < 0 or local.x > 511 or local.y > 511: return Vector2.ZERO
	var pixel: Color = _flow_image.get_pixel(local.x, local.y)
	return Vector2(pixel.b * 2.0 - 1.0, pixel.a * 2.0 - 1.0).limit_length()

## Luminous jellies drift with the current in deeper water, only seen at night.
func _spawn_jellies(rivers: WorldRivers, cell: Vector2i) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, int(_spec["seed"]) + 909))
	var texture: Texture2D = load("res://assets/water/river_jelly.png") as Texture2D
	var submerged: ShaderMaterial = ShaderMaterial.new()
	submerged.shader = load("res://assets/shaders/river_jelly.gdshader") as Shader
	for attempt: int in 60:
		if _jellies.size() >= int(_spec["jelly_max"]): return
		var at: Vector2 = Vector2(cell) * 512.0 + Vector2(rng.randf() * 512.0, rng.randf() * 512.0).round()
		if not _jelly_ok(at): continue
		var color: int = rng.randi() % 3
		var big: int = 1 if rng.randf() < 0.4 else 0
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = 8
		sprite.vframes = 6
		sprite.centered = false
		sprite.offset = Vector2(-12, -5)  # sits low: the bell is under the surface, not above it
		sprite.material = submerged
		sprite.z_index = -6
		sprite.visible = false
		sprite.position = at
		add_child(sprite)
		var light: NightLight = NightLight.new()
		light.radius = 26 + big * 8
		light.base_energy = 0.55
		light.pulse = 0.3
		light.glow_color = [Color("4fd0c0"), Color("a98af0"), Color("e8a9d0")][color]
		sprite.add_child(light)
		_jellies.append({"sprite": sprite, "pos": at, "heading": rng.randf() * TAU, "phase": rng.randf(), "row": color * 2 + big, "speed": float(_spec["jelly_speed"]) * rng.randf_range(0.7, 1.3)})

func _jelly_ok(at: Vector2) -> bool:
	# The bell and its trailing tentacles (about 12 px south) must stay clear of the banks.
	var field: Vector2 = _rivers.field_at(at)
	return field.x < -7.0 and field.y > 0.2 and _rivers.field_at(at + Vector2(0, 12)).x < -5.0 and _rivers.field_at(at + Vector2(0, -6)).x < -5.0

func _drift_jellies(delta: float) -> void:
	for jelly: Dictionary in _jellies:
		var sprite: Sprite2D = jelly["sprite"]
		sprite.visible = _night > 0.04
		if not sprite.visible: continue
		sprite.modulate.a = clampf(_night * 1.4, 0.0, 1.0)
		var pulse: float = fposmod(_time * 0.8 + float(jelly["phase"]), 1.0)
		sprite.frame = int(jelly["row"]) * 8 + int(pulse * 8.0)
		var thrust: float = maxf(0.0, sin(pulse * TAU))
		var at: Vector2 = jelly["pos"]
		var heading: float = float(jelly["heading"]) + sin(_time * 0.3 + float(jelly["phase"]) * 9.0) * delta * 0.6
		var dir: Vector2 = (_flow_at(at) * 0.8 + Vector2.from_angle(heading) * 0.5).normalized()
		var next: Vector2 = at + dir * float(jelly["speed"]) * (0.2 + 0.8 * thrust) * delta
		if _jelly_ok(next): jelly["pos"] = next
		else: heading += PI * 0.7
		jelly["heading"] = heading
		sprite.position = (jelly["pos"] as Vector2).round() + Vector2(0.0, roundf(sin(_time * 0.7 + float(jelly["phase"]) * 6.0) * 2.0))

func _flora_material() -> ShaderMaterial:
	if _flora_shader == null: _flora_shader = load("res://assets/shaders/river_flora.gdshader") as Shader
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _flora_shader
	return mat

## Called by DayNight through the group `night_lights`.
func set_night(amount: float) -> void:
	_night = amount
	for glow: Sprite2D in _glows:
		glow.modulate.a = lerpf(0.25, 1.0, amount)
	for mat: ShaderMaterial in glow_materials:
		mat.set_shader_parameter("night", amount)

## Plants farther than this from every player are not updated. Their frame and bend come from the
## absolute clock (`_time`), so they are correct again on the first frame they come back into range.
const ANIMATE_RADIUS: float = 420.0

func _near_any(at: Vector2, players: PackedVector2Array, radius: float) -> bool:
	for spot: Vector2 in players:
		if at.distance_squared_to(spot) <= radius * radius: return true
	return false

func _process(delta: float) -> void:
	_time += delta
	_drift_jellies(delta)
	# Players are collected once per frame. With no player at all (workbenches) everything animates as before.
	var players: PackedVector2Array = PackedVector2Array()
	for player: Player in Player.all: players.append(player.global_position)
	for i: int in _sprites.size():
		var sprite: Sprite2D = _sprites[i]
		var row: int = _rows[i]
		if not players.is_empty() and not _near_any(sprite.global_position, players, ANIMATE_RADIUS): continue
		if row >= 20:
			_animate_water_plant(sprite, row, _phases[i], _flows[i])
			if row == 22:
				(sprite.material as ShaderMaterial).set_shader_parameter("current_push", _flows[i] * (0.6 + 0.4 * sin(_time * 1.2 + _phases[i])))
			continue
		if row < 10: sprite.frame = row * 8 + posmod(int(_time * float(_spec["plant_fps"] if row in [0, 1, 5] else _spec["rock_fps"]) + _phases[i]), 8)
		if sprite.material is ShaderMaterial:
			var bend: float = sin(_time * 1.4 + _phases[i]) * 0.7
			for spot: Vector2 in players:
				var gap: Vector2 = sprite.global_position - spot
				if gap.length() < float(_spec["bend_radius"]): bend += signf(gap.x) * 2.0 * (1.0 - gap.length() / float(_spec["bend_radius"]))
			(sprite.material as ShaderMaterial).set_shader_parameter("bend", clampf(bend, -2.0, 2.0))
			if row == 0 or row == 18: (sprite.material as ShaderMaterial).set_shader_parameter("current_push", _flows[i] * (0.8 + 0.4 * sin(_time * 1.5 + _phases[i])))
