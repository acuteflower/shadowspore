class_name LivingFloraField
extends Node2D
## LivingFloraField — Batched Shader Coordinator, Whole-Pixel Botanical Mote Layer & Ecosystem Composer:
##   - Shares pooled `living_flora.gdshader` / `living_flora_glow.gdshader` materials across 100+ plants
##     and updates `actors[8]`, `slash_wave`, and `flora_rain` ONCE per frame!
##   - Renders crisp whole-pixel botanical life (`FloraMoteLayer` via `Node2D._draw()`):
##       * Wind-drifting silver dandelion seed parachutes (`meadow_clock`)
##       * Tumbling & stone-resting wild-rose, elderflower & meadowsweet petals
##       * Sparkling turquoise Star-Dew splash droplets (`star_mantle`)
##       * Ballistic leaf & blossom bursts on `[E]` plucking & `sickle_basic` harvesting
##       * Daytime `2x1 px` wild honeybees & hoverflies orbiting sunny nectar blooms!

const LIT_SHADER: Shader = preload("res://assets/shaders/living_flora.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/living_flora_glow.gdshader")

class FloraMote:
	var kind: int = 0 ## 0=dandelion parachute, 1=drifting petal, 2=dew droplet, 3=cut leaf/petal chip
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 8.0
	var z_vel: float = 0.0
	var age: float = 0.0
	var life: float = 2.0
	var phase: float = 0.0
	var col_a: Color = Color.WHITE
	var col_b: Color = Color("cbcde0")


class PollinatorBee:
	var home: Vector2 = Vector2.ZERO
	var phase: float = 0.0
	var speed: float = 2.2
	var rx: float = 7.0
	var ry: float = 4.0
	var is_hoverfly: bool = false


class FloraMoteLayer:
	extends Node2D
	var motes: Array[FloraMote] = []
	var bees: Array[PollinatorBee] = []
	var show_bees: bool = true
	var bee_alpha: float = 1.0
	var clock: float = 0.0

	func _draw() -> void:
		for m: FloraMote in motes:
			var rem: float = clampf((m.life - m.age) / maxf(m.life * 0.25, 0.08), 0.0, 1.0)
			if rem <= 0.02:
				continue
			var p: Vector2 = Vector2(roundf(m.pos.x), roundf(m.pos.y - m.z_h))
			if m.kind == 0:
				# Delicate 2-tone silver dandelion parachute (white umbrella pixel + warm seed speck below!)
				var c_top: Color = m.col_a
				var c_seed: Color = m.col_b
				c_top.a = rem * 0.95
				c_seed.a = rem * 0.85
				draw_rect(Rect2(p + Vector2(-1.0, 0.0), Vector2(3.0, 1.0)), c_top)
				draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2(1.0, 2.0)), c_seed)
			elif m.kind == 1:
				# Tumbling blossom petal (flips 2x1 <-> 1x2 while airborne, rests flat on stone/earth when z_h <= 0.2!)
				var cp: Color = m.col_a
				cp.a = rem * 0.92
				var flat: bool = m.z_h <= 0.25 or (int(m.age * 7.0 + m.phase) % 2 == 0)
				draw_rect(Rect2(p, Vector2(2.0, 1.0) if flat else Vector2(1.0, 2.0)), cp)
			elif m.kind == 2:
				# Luminous turquoise-white Star-Dew droplet!
				var cd: Color = m.col_a if m.age < m.life * 0.5 else m.col_b
				cd.a = rem
				draw_rect(Rect2(p, Vector2(1.0, 1.0)), cd)
			else:
				# Crisp cut leaf / blossom burst fragment
				var cl: Color = m.col_a if (int(m.age * 14.0) % 2 == 0) else m.col_b
				cl.a = rem
				draw_rect(Rect2(p, Vector2(2.0, 1.0)), cl)

		if show_bees and bee_alpha > 0.04:
			for b: PollinatorBee in bees:
				var t: float = clock * b.speed + b.phase
				var bx: float = b.home.x + sin(t) * b.rx + cos(t * 2.1) * 2.2
				var by: float = b.home.y + cos(t * 1.3) * b.ry + sin(t * 3.4) * 1.1
				var bp: Vector2 = Vector2(roundf(bx), roundf(by))
				var body_c: Color = Color(0.95, 0.78, 0.34, bee_alpha) if not b.is_hoverfly else Color(0.88, 0.86, 0.52, bee_alpha)
				var wing_c: Color = Color(0.94, 0.97, 1.0, bee_alpha * 0.80)
				var dir_sign: float = 1.0 if cos(t) >= 0.0 else -1.0
				draw_rect(Rect2(bp, Vector2(2.0, 1.0)), body_c)
				if (int(clock * 24.0 + b.phase * 5.0) % 2) == 0:
					draw_rect(Rect2(bp + Vector2(0.0 if dir_sign > 0.0 else 1.0, -1.0), Vector2(1.0, 1.0)), wing_c)


var plants: Array[LivingFloraProp] = []
var ruins: Array[SanctuaryRuin] = []
var species_placed: Dictionary = {}

var _materials: Dictionary = {} ## key String -> ShaderMaterial
var _actor_slots: Array[Vector4] = []
var _slash_wave: Vector4 = Vector4.ZERO
var _slash_age: float = 99.0
var _ambient_drift_timer: float = 1.2
var _mote_layer: FloraMoteLayer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	y_sort_enabled = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 202611
	_actor_slots.resize(8)
	for i: int in 8:
		_actor_slots[i] = Vector4.ZERO

	_mote_layer = FloraMoteLayer.new()
	_mote_layer.name = "FloraMotes"
	_mote_layer.z_as_relative = false
	_mote_layer.z_index = 2
	add_child(_mote_layer)


func get_shared_material(is_large: bool, sway_val: float, is_glow: bool) -> ShaderMaterial:
	var bucket: int = clampi(roundi(sway_val * 2.0), 1, 4)
	var key: String = "%s_%d_%s" % ["L" if is_large else "S", bucket, "G" if is_glow else "M"]
	if _materials.has(key):
		return _materials[key] as ShaderMaterial

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = GLOW_SHADER if is_glow else LIT_SHADER
	mat.set_shader_parameter("frame_size", Vector2(56.0, 52.0) if is_large else Vector2(32.0, 36.0))
	mat.set_shader_parameter("pivot_row", 45.0 if is_large else 31.0)
	mat.set_shader_parameter("amount", float(bucket) * 0.55 * (1.15 if is_large else 1.0))
	mat.set_shader_parameter("flutter", 0.28 + float(bucket) * 0.05)
	mat.set_shader_parameter("cell_w", 7.0 if is_large else 4.5)
	mat.set_shader_parameter("use_model_origin", true)
	mat.set_shader_parameter("actors", _actor_slots)
	_materials[key] = mat
	return mat


func trigger_slash_gust(world_pos: Vector2, radius: float = 34.0, strength: float = 1.0) -> void:
	_slash_wave = Vector4(world_pos.x, world_pos.y, radius, strength)
	_slash_age = 0.0
	# Dislodge petals or dandelion seeds from plants caught inside the slash arc!
	for fp: LivingFloraProp in plants:
		if not is_instance_valid(fp) or fp.is_cut() or fp.is_picked():
			continue
		if fp.global_position.distance_to(world_pos) <= radius:
			var sp: Dictionary = fp.spec()
			if String(sp.get("behavior", "")) == "dandelion_puff" and fp.variant >= 2 and multiplayer.is_server():
				fp.state["p"] = maxi(1, TimeManager.day)
				fp._rpc_sync_flora_state.rpc(fp.state, "puff", 1.0)
			elif bool(sp.get("petal_drift", false)):
				var bcols: Array = sp.get("burst_colors", ["#f4f2fa"]) as Array
				spawn_petals(fp.global_position + Vector2(0.0, -16.0), 3, Color(String(bcols[0])))


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_mote_layer.clock += dt

	# 1. Gather up to 8 live actor positions (players + wild creatures) for radial shader parting!
	var slot_i: int = 0
	for p: Player in Player.all:
		if slot_i >= 8:
			break
		if is_instance_valid(p) and p.is_visible_in_tree():
			var spd_boost: float = clampf(p.velocity.length() / 95.0, 0.0, 0.45)
			_actor_slots[slot_i] = Vector4(p.global_position.x, p.global_position.y, 16.0, 0.85 + spd_boost)
			slot_i += 1
	for k: int in range(slot_i, 8):
		_actor_slots[k] = Vector4.ZERO

	if _slash_age < 0.32:
		_slash_age += dt
		_slash_wave.w = maxf(0.0, 1.0 - _slash_age / 0.32)
	else:
		_slash_wave = Vector4.ZERO

	var rain_now: float = WeatherManager.current.rain if WeatherManager.current != null else 0.0
	for mat_v: Variant in _materials.values():
		var mat: ShaderMaterial = mat_v as ShaderMaterial
		mat.set_shader_parameter("actors", _actor_slots)
		mat.set_shader_parameter("slash_wave", _slash_wave)
		mat.set_shader_parameter("flora_rain", rain_now)

	# 2. Gentle ambient wind-borne blossom petals & dandelion seeds during breezes!
	_ambient_drift_timer -= dt
	var wind_g: float = WorldWind.current.gust if WorldWind.current != null else 0.25
	if _ambient_drift_timer <= 0.0:
		_ambient_drift_timer = lerpf(2.2, 0.65, clampf(wind_g, 0.0, 1.0))
		if _mote_layer.motes.size() < 56 and not plants.is_empty():
			var pick_fp: LivingFloraProp = plants[_rng.randi() % plants.size()]
			if is_instance_valid(pick_fp) and not pick_fp.is_cut() and not pick_fp.is_picked():
				var pspec: Dictionary = pick_fp.spec()
				if bool(pspec.get("petal_drift", false)):
					var bcols: Array = pspec.get("burst_colors", ["#f4f2fa"]) as Array
					spawn_petals(pick_fp.global_position + Vector2(_rng.randf_range(-8.0, 8.0), -18.0), 1, Color(String(bcols[0])))
				elif String(pspec.get("behavior", "")) == "dandelion_puff" and pick_fp.variant >= 2 and wind_g > 0.45:
					spawn_dandelion_seeds(pick_fp.global_position + Vector2(0.0, -16.0), 1)

	# 3. Pollinator visibility (active in warm daylight without rain!)
	var night: float = TimeManager.night_amount()
	var bee_vis: float = (1.0 - smoothstep(0.15, 0.55, night)) * (1.0 - smoothstep(0.05, 0.30, rain_now))
	_mote_layer.bee_alpha = bee_vis
	_mote_layer.show_bees = bee_vis > 0.04

	# 4. Step active botanical motes
	var wind_vec: Vector2 = WorldWind.current.direction * (14.0 + 26.0 * wind_g) if WorldWind.current != null else Vector2(14.0, 2.0)
	var mi: int = _mote_layer.motes.size() - 1
	while mi >= 0:
		var m: FloraMote = _mote_layer.motes[mi]
		m.age += dt
		if m.age >= m.life:
			_mote_layer.motes.remove_at(mi)
		else:
			if m.kind == 0:
				# Dandelion parachute rides WorldWind with buoyant sine bobbing!
				m.vel = m.vel.lerp(wind_vec + Vector2(0.0, sin(m.age * 3.2 + m.phase) * 5.5), dt * 2.4)
				m.pos += m.vel * dt
				m.z_h = maxf(2.0, m.z_h + (3.2 * sin(m.age * 2.5 + m.phase) - 1.6) * dt)
			elif m.kind == 1:
				# Blossom petal flutters down, then rests still on stone/earth for its final second!
				if m.z_h > 0.2:
					var sway_x: float = sin(m.age * 6.5 + m.phase) * 14.0
					m.pos += (wind_vec * 0.55 + Vector2(sway_x, 3.0)) * dt
					m.z_h = maxf(0.0, m.z_h - 11.5 * dt)
			else:
				# Dew droplet or cut leaf fragment ballistic arc
				m.pos += m.vel * dt
				m.z_h = maxf(0.0, m.z_h + m.z_vel * dt)
				m.z_vel -= 115.0 * dt
				if m.z_h <= 0.05:
					m.vel *= 0.65
		mi -= 1

	if not _mote_layer.motes.is_empty() or _mote_layer.show_bees:
		_mote_layer.queue_redraw()


# ---------------- MOTE SPAWN HELPERS ----------------

func spawn_dandelion_seeds(world_pos: Vector2, count: int = 10) -> void:
	for i: int in count:
		if _mote_layer.motes.size() >= 96:
			break
		var m: FloraMote = FloraMote.new()
		m.kind = 0
		m.pos = world_pos + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-2.0, 2.0))
		m.vel = Vector2(_rng.randf_range(8.0, 28.0), _rng.randf_range(-10.0, 8.0))
		m.z_h = _rng.randf_range(8.0, 16.0)
		m.life = _rng.randf_range(2.8, 4.6)
		m.phase = _rng.randf() * TAU
		m.col_a = Color("f4f2fa")
		m.col_b = Color("cfa44e")
		_mote_layer.motes.append(m)


func spawn_petals(world_pos: Vector2, count: int = 3, petal_col: Color = Color("f7d2e0")) -> void:
	for _i: int in count:
		if _mote_layer.motes.size() >= 96:
			break
		var m: FloraMote = FloraMote.new()
		m.kind = 1
		m.pos = world_pos + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-2.0, 2.0))
		m.z_h = _rng.randf_range(12.0, 24.0)
		m.life = _rng.randf_range(2.2, 3.6)
		m.phase = _rng.randf() * TAU
		m.col_a = petal_col
		_mote_layer.motes.append(m)


func spawn_dew_splash(world_pos: Vector2, count: int = 6) -> void:
	for i: int in count:
		if _mote_layer.motes.size() >= 96:
			break
		var m: FloraMote = FloraMote.new()
		m.kind = 2
		var ang: float = _rng.randf() * TAU
		m.pos = world_pos
		m.vel = Vector2(cos(ang), sin(ang) * 0.6) * _rng.randf_range(14.0, 34.0)
		m.z_h = 4.0
		m.z_vel = _rng.randf_range(28.0, 54.0)
		m.life = _rng.randf_range(0.32, 0.56)
		m.col_a = Color("d6fff8")
		m.col_b = Color("5cd4ce")
		_mote_layer.motes.append(m)


func spawn_cut_burst(world_pos: Vector2, count: int, c1: Color, c2: Color, dir_x: float) -> void:
	for _i: int in count:
		if _mote_layer.motes.size() >= 96:
			break
		var m: FloraMote = FloraMote.new()
		m.kind = 3
		m.pos = world_pos + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-2.0, 2.0))
		m.vel = Vector2(dir_x * _rng.randf_range(14.0, 46.0) + _rng.randf_range(-16.0, 16.0), _rng.randf_range(-18.0, 18.0))
		m.z_h = _rng.randf_range(4.0, 14.0)
		m.z_vel = _rng.randf_range(26.0, 58.0)
		m.life = _rng.randf_range(0.42, 0.78)
		m.col_a = c1
		m.col_b = c2
		_mote_layer.motes.append(m)


# ==============================================================================
# Ecological Sanctuary, Meadow, Roadside & Woodland-Edge Composer (Squares 1..3)
# ==============================================================================

func add_ruin(kind: String, pos: Vector2, var_idx: int = 0, flipped: bool = false) -> SanctuaryRuin:
	var r: SanctuaryRuin = SanctuaryRuin.new()
	r.setup_ruin(kind, pos, var_idx, flipped)
	add_child(r)
	ruins.append(r)
	return r


func add_plant(id: String, pos: Vector2, var_idx: int = 0, flipped: bool = false) -> LivingFloraProp:
	var fp: LivingFloraProp = LivingFloraProp.new()
	fp.setup_flora(id, pos, var_idx, flipped, self)
	add_child(fp)
	plants.append(fp)
	species_placed[id] = int(species_placed.get(id, 0)) + 1

	var sp: Dictionary = DataRegistry.get_entry("sanctuary_flora", id)
	if bool(sp.get("bees", false)) and _mote_layer.bees.size() < 18 and _rng.randf() < 0.42:
		var bee: PollinatorBee = PollinatorBee.new()
		bee.home = pos + Vector2(0.0, -float(sp.get("height", 16.0)) * 0.72)
		bee.phase = _rng.randf() * TAU
		bee.speed = _rng.randf_range(1.7, 2.7)
		bee.rx = _rng.randf_range(5.5, 10.0)
		bee.ry = _rng.randf_range(3.0, 5.5)
		bee.is_hoverfly = (_rng.randf() < 0.35)
		_mote_layer.bees.append(bee)
	return fp


## Populates the 8 standing `SanctuaryRuin` companions and all 28 `LivingFlora 2.0` species
## across their authentic micro-habitats in Square 1 (Meadow), Square 2 (Crossroads & Ruins), and Square 3 (Woodland Edge)!
func populate_sanctuary_ecosystem(_surfaces: GroundSurfaces) -> void:
	# ---------------- A. 8 STANDING 3/4 SANCTUARY RUIN COMPANIONS (SQUARE 2) ----------------
	add_ruin("sanctuary_parapet", Vector2(218.0, -114.0), 0, false)   ## North-West Shrine north retaining parapet!
	add_ruin("ancient_dew_basin", Vector2(182.0, -94.0), 0, false)    ## Interactive Star-Dew Basin beside NW Shrine!
	add_ruin("sanctuary_waymarker", Vector2(304.0, -14.0), 0, false)  ## Tilted runic milestone greeting travellers at West Gateway!
	add_ruin("sanctuary_waymarker", Vector2(496.0, -16.0), 1, false)  ## Tilted runic milestone flanking the East Cart Track!
	add_ruin("sanctuary_parapet", Vector2(496.0, -88.0), 1, false)    ## Broken ashlar parapet along NE ruined cobble spur!
	add_ruin("fallen_column_drum", Vector2(546.0, -72.0), 0, false)   ## Half-sunken fluted column drum at NE ruin tail-off!
	add_ruin("fallen_column_drum", Vector2(264.0, 110.0), 1, true)    ## Overgrown fluted column drum beside SW stepping stones!
	add_ruin("ancient_dew_basin", Vector2(424.0, 48.0), 0, true)      ## Second interactive Star-Dew Basin at SE Sanctuary Steps!

	# ---------------- B. CURATED HERO CLUSTERS FOR ALL 28 BOTANICAL SPECIES ----------------
	var placements: Array[Array] = [
		# --- Category 1: Crevice, Cobble & Path-Edge Weeds (hugging stone joints & road shoulders!) ---
		["waybread", Vector2(212.0, 22.0), 0, false],
		["waybread", Vector2(278.0, -4.0), 1, true],
		["waybread", Vector2(514.0, 14.0), 2, false],
		["waybread", Vector2(548.0, -14.0), 0, true],
		["gold_stonecrop", Vector2(334.0, -12.0), 0, false],
		["gold_stonecrop", Vector2(436.0, -11.0), 1, true],
		["gold_stonecrop", Vector2(246.0, -108.0), 2, false],
		["gold_stonecrop", Vector2(506.0, -84.0), 0, true],
		["cymbal_weed", Vector2(354.0, -28.0), 0, false],
		["cymbal_weed", Vector2(414.0, 38.0), 1, true],
		["cymbal_weed", Vector2(222.0, -80.0), 2, false],
		["cymbal_weed", Vector2(464.0, 14.0), 0, true],
		["wall_rue", Vector2(356.0, -38.0), 0, false],
		["wall_rue", Vector2(198.0, -112.0), 1, true],
		["wall_rue", Vector2(286.0, -76.0), 2, false],
		["wall_rue", Vector2(482.0, -90.0), 0, true],
		["silverweed", Vector2(262.0, -76.0), 0, false],
		["silverweed", Vector2(322.0, -78.0), 1, true],
		["silverweed", Vector2(448.0, -68.0), 2, false],
		["silverweed", Vector2(168.0, 26.0), 0, true],

		# --- Category 2: Meadow & Wayside Wildflowers (Square 1 Meadow fringes + Square 2 sunny verges!) ---
		["silver_yarrow", Vector2(146.0, -12.0), 0, false],
		["silver_yarrow", Vector2(236.0, -16.0), 1, true],
		["silver_yarrow", Vector2(292.0, 28.0), 2, false],
		["silver_yarrow", Vector2(-88.0, -56.0), 1, false],
		["silver_yarrow", Vector2(76.0, -64.0), 0, true],
		["way_chicory", Vector2(182.0, -6.0), 0, false],
		["way_chicory", Vector2(248.0, 25.0), 1, true],
		["way_chicory", Vector2(504.0, 18.0), 2, false],
		["way_chicory", Vector2(118.0, 30.0), 0, true],
		["wild_thyme", Vector2(326.0, 26.0), 0, false],
		["wild_thyme", Vector2(442.0, 26.0), 1, true],
		["wild_thyme", Vector2(334.0, -74.0), 2, false],
		["wild_thyme", Vector2(256.0, -106.0), 1, true],
		["dew_campion", Vector2(158.0, -48.0), 0, false],
		["dew_campion", Vector2(224.0, 52.0), 1, true],
		["dew_campion", Vector2(-118.0, 66.0), 2, false],
		["dew_campion", Vector2(88.0, 74.0), 0, true],
		["meadow_clock", Vector2(134.0, -34.0), 0, false], ## Golden salsify bloom
		["meadow_clock", Vector2(204.0, 36.0), 2, true],   ## Ripe silver dandelion puff-clock right near path!
		["meadow_clock", Vector2(284.0, -36.0), 2, false], ## Ripe silver dandelion puff-clock!
		["meadow_clock", Vector2(-64.0, -76.0), 0, true],
		["meadow_clock", Vector2(54.0, 62.0), 2, false],

		# --- Category 3: Mystic Sanctuary & Dusk Flora (anchoring thresholds, milestones & shrines!) ---
		["rune_saxifrage", Vector2(312.0, -10.0), 0, false],
		["rune_saxifrage", Vector2(414.0, -28.0), 1, true],
		["rune_saxifrage", Vector2(196.0, -90.0), 2, false],
		["rune_saxifrage", Vector2(284.0, 102.0), 0, true],
		["sentinel_mullein", Vector2(294.0, -18.0), 1, false], ## Tall amber torch flanking West Gateway waymarker!
		["sentinel_mullein", Vector2(506.0, -20.0), 2, true],  ## Tall amber torch flanking East Gateway waymarker!
		["sentinel_mullein", Vector2(174.0, -106.0), 0, false],## Tall guardian mullein at NW Shrine!
		["star_mantle", Vector2(192.0, -84.0), 0, false],      ## Dew-pearl Lady's Mantle beside NW Dew Basin!
		["star_mantle", Vector2(436.0, 52.0), 1, true],        ## Dew-pearl Lady's Mantle beside SE Dew Basin!
		["star_mantle", Vector2(362.0, 58.0), 2, false],
		["star_mantle", Vector2(564.0, 58.0), 0, true],
		["dusk_columbine", Vector2(436.0, -42.0), 0, false],
		["dusk_columbine", Vector2(542.0, -48.0), 1, true],
		["dusk_columbine", Vector2(486.0, 96.0), 2, false],

		# --- Category 4: Tall Herbs, Umbels & Ruderal Borders (lush mid-height framing!) ---
		["shadow_angelica", Vector2(166.0, -82.0), 0, false],
		["shadow_angelica", Vector2(552.0, -34.0), 1, true],
		["shadow_angelica", Vector2(534.0, 108.0), 2, false],
		["shadow_angelica", Vector2(-136.0, -88.0), 0, true],
		["wild_teasel", Vector2(276.0, -112.0), 0, false],
		["wild_teasel", Vector2(526.0, -98.0), 2, true],
		["wild_teasel", Vector2(154.0, 98.0), 0, false],
		["nettle_clump", Vector2(238.0, -118.0), 0, false],
		["nettle_clump", Vector2(512.0, -96.0), 2, true],
		["nettle_clump", Vector2(248.0, 114.0), 1, false],
		["meadowsweet", Vector2(422.0, 88.0), 0, false],
		["meadowsweet", Vector2(474.0, 98.0), 1, true],
		["meadowsweet", Vector2(558.0, 88.0), 2, false],
		["meadowsweet", Vector2(632.0, 74.0), 0, true],

		# --- Category 5: Flowering & Berry Shrubs (anchoring corners, ruins & woodland threshold!) ---
		["wild_rose_briar", Vector2(162.0, -112.0), 0, false], ## Blooming wild rose briar framing NW Shrine!
		["wild_rose_briar", Vector2(332.0, 108.0), 2, true],   ## Ruby-rosehip briar beside SW stepping trail!
		["wild_rose_briar", Vector2(-148.0, 96.0), 0, false],  ## Blooming wild rose in Square 1 SW corner!
		["elderberry_shrub", Vector2(458.0, -108.0), 0, false],## Creamy blooming Elderberry shrub north of East Spur!
		["elderberry_shrub", Vector2(574.0, -98.0), 2, true],  ## Ripe dark-berry Elderberry at Square 2->3 north border!
		["hawthorn_bush", Vector2(342.0, -114.0), 0, false],   ## Blooming May-hawthorn above North Cobble curve!
		["hawthorn_bush", Vector2(124.0, 108.0), 2, true],     ## Sloe-fruiting hawthorn at SW meadow edge!
		["bramble_thicket", Vector2(558.0, -60.0), 2, false],  ## Blackberry bramble sprawling beside fallen column!
		["bramble_thicket", Vector2(578.0, 108.0), 0, true],   ## Blooming bramble at SE woodland entry!

		# --- Category 6: Creepers, Vines & Stone Overgrowth (weaving stone & earth together!) ---
		["sanctuary_ivy", Vector2(204.0, -112.0), 0, false],
		["sanctuary_ivy", Vector2(328.0, 22.0), 1, true],
		["sanctuary_ivy", Vector2(440.0, -18.0), 2, false],
		["sanctuary_ivy", Vector2(538.0, -68.0), 0, true],
		["silver_clematis", Vector2(252.0, -114.0), 0, false],
		["silver_clematis", Vector2(484.0, -92.0), 1, true],
		["silver_clematis", Vector2(278.0, 112.0), 2, false],
		["periwinkle_mat", Vector2(186.0, -76.0), 0, false],
		["periwinkle_mat", Vector2(228.0, -76.0), 1, true],
		["periwinkle_mat", Vector2(352.0, 44.0), 2, false],
		["periwinkle_mat", Vector2(416.0, -38.0), 0, true],

		# --- Category 7: Woodland-Edge, Moss & Damp Hollow Flora (Square 2 SE -> Square 3 Forest!) ---
		["wood_sorrel", Vector2(452.0, 82.0), 0, false],
		["wood_sorrel", Vector2(588.0, 52.0), 1, true],
		["wood_sorrel", Vector2(638.0, -62.0), 2, false],
		["wood_sorrel", Vector2(704.0, 82.0), 0, true],
		["wood_sorrel", Vector2(878.0, -32.0), 1, false],
		["shadow_arum", Vector2(612.0, 44.0), 0, false],
		["shadow_arum", Vector2(754.0, -34.0), 1, true],
		["shadow_arum", Vector2(836.0, 54.0), 2, false],
		["ostrich_fern", Vector2(582.0, 28.0), 0, false],
		["ostrich_fern", Vector2(604.0, -48.0), 1, true],
		["ostrich_fern", Vector2(676.0, -78.0), 2, false],
		["ostrich_fern", Vector2(728.0, 92.0), 0, true],
		["ostrich_fern", Vector2(896.0, -46.0), 1, false],
	]

	for entry: Array in placements:
		add_plant(String(entry[0]), entry[1] as Vector2, int(entry[2]), bool(entry[3]))
