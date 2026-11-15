class_name StarHallRoom
extends Node2D
## The Star Hall ("Der Sternensaal", docs/sternensaal_konzept.md): 560x820 floating moon-marble sanctuary in deep cosmos.
## Built inside its pocket Interior slot: renders starhall_cosmos.gdshader behind floating outer crystal islands,
## dual starhall_mirror.gdshader reflection basins, progressive crystal pylons linked to awakened waystones,
## Y-sorted balustrades & relic plinths, the monumental throne with Caelia (StarHallGoddess), and StarHallReturnSeal.

const COSMOS_SHADER: Shader = preload("res://assets/shaders/starhall_cosmos.gdshader")
const MIRROR_SHADER: Shader = preload("res://assets/shaders/starhall_mirror.gdshader")

const FLOOR_BASE_TEX: Texture2D = preload("res://assets/interior/starhall/floor_base.png")
const FLOOR_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/floor_glow.png")
const THRONE_TEX: Texture2D = preload("res://assets/interior/starhall/throne.png")
const THRONE_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/throne_glow.png")
const PYLON_TEX: Texture2D = preload("res://assets/interior/starhall/pylon.png")
const PYLON_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/pylon_glow.png")
const BALUSTRADE_TEX: Texture2D = preload("res://assets/interior/starhall/balustrade.png")
const BALUSTRADE_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/balustrade_glow.png")
const RELIC_PLINTH_TEX: Texture2D = preload("res://assets/interior/starhall/relic_plinth.png")
const RELIC_PLINTH_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/relic_plinth_glow.png")
const ISLAND0_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_0.png")
const ISLAND0_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_0_glow.png")
const ISLAND1_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_1.png")
const ISLAND1_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_1_glow.png")
const ISLAND2_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_2.png")
const ISLAND2_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_2_glow.png")
const STAR_MOTE_TEX: Texture2D = preload("res://assets/interior/starhall/star_mote.png")

const HALL_SIZE: Vector2 = Vector2(560.0, 820.0)
const COSMOS_POS: Vector2 = Vector2(-620.0, -230.0)
const COSMOS_SIZE: Vector2 = Vector2(1800.0, 1280.0)
const THRONE_POS: Vector2 = Vector2(280.0, 162.0)
const GODDESS_POS: Vector2 = Vector2(280.0, 163.0)
const RETURN_POS: Vector2 = Vector2(280.0, 715.0)

var goddess: StarHallGoddess
var return_seal: StarHallReturnSeal

var _cosmos_mat: ShaderMaterial
var _mirror_mats: Array[ShaderMaterial] = []
var _anims: Array[Dictionary] = []
var _pylons: Array[Dictionary] = []
var _islands: Array[Dictionary] = []
var _motes: Array[Dictionary] = []
var _time: float = 0.0
var _waystones_bound: bool = false


func _ready() -> void:
	name = "StarHallRoom"
	y_sort_enabled = true
	_build()


func _build() -> void:
	# 1. Deep Cosmos Shader Backdrop (anchored to hall room space, no dark vignette edge)
	var cosmos: ColorRect = ColorRect.new()
	cosmos.name = "StarHallCosmos"
	cosmos.position = COSMOS_POS
	cosmos.size = COSMOS_SIZE
	cosmos.z_index = -30
	cosmos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cosmos_mat = ShaderMaterial.new()
	_cosmos_mat.shader = COSMOS_SHADER
	_cosmos_mat.set_shader_parameter("rect_size", COSMOS_SIZE)
	_cosmos_mat.set_shader_parameter("hall_origin", -COSMOS_POS)
	_cosmos_mat.set_shader_parameter("hall_size", HALL_SIZE)
	_cosmos_mat.set_shader_parameter("cam_offset", Vector2.ZERO)
	_cosmos_mat.set_shader_parameter("time", 0.0)
	cosmos.material = _cosmos_mat
	add_child(cosmos)

	# 2. Outer Floating Moon-Marble & Crystal Islands
	var island_texs: Array[Texture2D] = [ISLAND0_TEX, ISLAND1_TEX, ISLAND2_TEX]
	var island_glows: Array[Texture2D] = [ISLAND0_GLOW_TEX, ISLAND1_GLOW_TEX, ISLAND2_GLOW_TEX]
	var island_specs: Array[Dictionary] = [
		{"v": 0, "pos": Vector2(44.0, 128.0), "amp": 4.0, "spd": 0.9, "ph": 0.2},
		{"v": 1, "pos": Vector2(512.0, 146.0), "amp": 3.0, "spd": 1.1, "ph": 1.7},
		{"v": 1, "pos": Vector2(58.0, 470.0), "amp": 4.0, "spd": 0.8, "ph": 2.9},
		{"v": 0, "pos": Vector2(506.0, 488.0), "amp": 3.5, "spd": 0.95, "ph": 4.1},
		{"v": 2, "pos": Vector2(88.0, 720.0), "amp": 3.0, "spd": 1.25, "ph": 0.9},
		{"v": 2, "pos": Vector2(476.0, 732.0), "amp": 3.0, "spd": 1.15, "ph": 3.5},
	]
	for spec: Dictionary in island_specs:
		var v_idx: int = int(spec["v"])
		var base_pos: Vector2 = spec["pos"] as Vector2
		var holder: Node2D = Node2D.new()
		holder.position = base_pos
		holder.z_index = -20
		add_child(holder)

		var ib: Sprite2D = Sprite2D.new()
		ib.texture = island_texs[v_idx]
		holder.add_child(ib)

		var ig: Sprite2D = Sprite2D.new()
		ig.texture = island_glows[v_idx]
		ig.material = Unlit.material()
		holder.add_child(ig)

		_islands.append({
			"node": holder,
			"base": base_pos,
			"amp": float(spec["amp"]),
			"spd": float(spec["spd"]),
			"ph": float(spec["ph"]),
		})

	# 3. Moon-Marble Platform Base & Unlit Leyline Glow
	var floor_base: Sprite2D = Sprite2D.new()
	floor_base.name = "FloorBase"
	floor_base.texture = FLOOR_BASE_TEX
	floor_base.centered = false
	floor_base.position = Vector2.ZERO
	floor_base.z_index = -10
	add_child(floor_base)

	var floor_glow: Sprite2D = Sprite2D.new()
	floor_glow.name = "FloorGlow"
	floor_glow.texture = FLOOR_GLOW_TEX
	floor_glow.centered = false
	floor_glow.position = Vector2.ZERO
	floor_glow.z_index = -8
	floor_glow.material = Unlit.material()
	add_child(floor_glow)

	# 4. Dual Recessed Sapphire Mirror Basins on the Star Bridge
	var basin_positions: Array[Vector2] = [Vector2(170.0, 399.0), Vector2(346.0, 399.0)]
	var basin_sz: Vector2 = Vector2(44.0, 162.0)
	for b_idx: int in basin_positions.size():
		var m_rect: ColorRect = ColorRect.new()
		m_rect.name = "MirrorBasin_%d" % b_idx
		m_rect.position = basin_positions[b_idx]
		m_rect.size = basin_sz
		m_rect.z_index = -9
		m_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m_mat: ShaderMaterial = ShaderMaterial.new()
		m_mat.shader = MIRROR_SHADER
		m_mat.set_shader_parameter("basin_size", basin_sz)
		m_mat.set_shader_parameter("cam_offset", Vector2.ZERO)
		m_mat.set_shader_parameter("time", 0.0)
		m_mat.set_shader_parameter("mirror_seed", float(b_idx) * 17.0)
		m_rect.material = m_mat
		add_child(m_rect)
		_mirror_mats.append(m_mat)

	# 5. Props (Y-sorted as direct children alongside players so feet depth-sort natively)
	_add_anim_prop("DivineThrone", THRONE_TEX, THRONE_GLOW_TEX, THRONE_POS, Vector2(-80.0, -148.0), 8, 6.5, 0.0)
	_add_star_light(Vector2(280.0, 126.0), Color(0.68, 0.94, 1.00), 215, 0.72, 0.46)
	_add_star_light(Vector2(280.0, 174.0), Color(1.00, 0.88, 0.60), 175, 0.68, 0.46)

	# Seated Goddess Caelia on the Throne
	goddess = StarHallGoddess.new()
	goddess.position = GODDESS_POS
	add_child(goddess)

	# Return Seal at Southern Arrival Circle + cosmic beacon pool
	return_seal = StarHallReturnSeal.new()
	return_seal.position = RETURN_POS
	add_child(return_seal)
	_add_star_light(RETURN_POS, Color(0.38, 0.90, 1.00), 152, 0.72, 0.50)

	# 3 Relic Plinths on the Northern Dais (the nearest eastern/front plinth holds the future Gaben shrine hook)
	var relic_spots: Array[Vector2] = [
		Vector2(174.0, 180.0),
		Vector2(386.0, 180.0),
		Vector2(204.0, 224.0),
	]
	for r_idx: int in relic_spots.size():
		_add_anim_prop("RelicPlinth_%d" % r_idx, RELIC_PLINTH_TEX, RELIC_PLINTH_GLOW_TEX, relic_spots[r_idx], Vector2(-18.0, -44.0), 8, 6.0, float(r_idx) * 0.35)
		_add_star_light(relic_spots[r_idx] + Vector2(0.0, -16.0), Color(0.46, 0.94, 1.00), 72, 0.72, 0.32)
	var gift_spot: _StarHallGiftSpot = _StarHallGiftSpot.new()
	gift_spot.position = relic_spots[2]
	add_child(gift_spot)

	# 6 Crystal Pylons (paired South -> Middle -> North, lighting progressively with awakened Waystones)
	# Order matches southern pair active first (>=1 statue), middle pair (>=3), northern pair (>=5).
	var pylon_specs: Array[Dictionary] = [
		{"pos": Vector2(204.0, 344.0), "req": 5},
		{"pos": Vector2(356.0, 344.0), "req": 5},
		{"pos": Vector2(228.0, 480.0), "req": 3},
		{"pos": Vector2(332.0, 480.0), "req": 3},
		{"pos": Vector2(204.0, 612.0), "req": 1},
		{"pos": Vector2(356.0, 612.0), "req": 1},
	]
	for p_idx: int in pylon_specs.size():
		var p_cfg: Dictionary = pylon_specs[p_idx]
		var p_pos: Vector2 = p_cfg["pos"] as Vector2
		var entry: Dictionary = _add_anim_prop("CrystalPylon_%d" % p_idx, PYLON_TEX, PYLON_GLOW_TEX, p_pos, Vector2(-24.0, -84.0), 8, 6.5, float(p_idx) * 0.22)
		var p_light: PointLight2D = _add_star_light(p_pos + Vector2(0.0, -28.0), Color(0.58, 0.94, 1.00), 124, 0.72, 0.52)
		entry["light"] = p_light
		entry["req"] = int(p_cfg["req"])
		_pylons.append(entry)

	# Soft central bridge astral pool between reflection basins
	_add_star_light(Vector2(280.0, 480.0), Color(0.34, 0.74, 0.98), 132, 0.80, 0.24)

	# 4 Openwork Moon-Marble Balustrades along Balcony Rims
	var bal_spots: Array[Vector2] = [
		Vector2(174.0, 381.0),
		Vector2(386.0, 381.0),
		Vector2(174.0, 581.0),
		Vector2(386.0, 581.0),
	]
	for b_i: int in bal_spots.size():
		_add_static_prop("Balustrade_%d" % b_i, BALUSTRADE_TEX, BALUSTRADE_GLOW_TEX, bal_spots[b_i], Vector2(-24.0, -32.0))

	# 6. Drifting Star Motes
	var motes_root: Node2D = Node2D.new()
	motes_root.name = "StarMotes"
	motes_root.z_index = 15
	add_child(motes_root)
	for m_i: int in 26:
		var seed_f: float = float(m_i) * 1.6180339
		var mx: float = 155.0 + fmod(seed_f * 97.3, 250.0)
		var my: float = 85.0 + fmod(seed_f * 173.7, 665.0)
		var ms: Sprite2D = Sprite2D.new()
		ms.texture = STAR_MOTE_TEX
		ms.hframes = 4
		ms.frame = m_i % 4
		ms.material = Unlit.material()
		ms.position = Vector2(roundf(mx), roundf(my))
		motes_root.add_child(ms)
		_motes.append({"sprite": ms, "bx": mx, "by": my, "ph": seed_f * 3.1, "spd": 3.5 + fmod(seed_f * 5.0, 3.0)})

	# 7. Island Perimeter & Obstacle Colliders
	_build_colliders(basin_positions, basin_sz, relic_spots, pylon_specs, bal_spots)
	_refresh_pylons()


func _build_colliders(basins: Array[Vector2], basin_sz: Vector2, relics: Array[Vector2], pylons: Array[Dictionary], bals: Array[Vector2]) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "StarHallColliders"
	add_child(body)

	# Perimeter segment loop tracing inside the cliff edge of the 560x820 marble platform
	var loop: PackedVector2Array = PackedVector2Array([
		Vector2(236.0, 88.0),
		Vector2(324.0, 88.0),
		Vector2(382.0, 114.0),
		Vector2(414.0, 158.0),
		Vector2(414.0, 198.0),
		Vector2(376.0, 244.0),
		Vector2(354.0, 270.0),
		Vector2(354.0, 376.0),
		Vector2(410.0, 390.0),
		Vector2(412.0, 568.0),
		Vector2(354.0, 584.0),
		Vector2(354.0, 646.0),
		Vector2(374.0, 682.0),
		Vector2(370.0, 736.0),
		Vector2(322.0, 760.0),
		Vector2(238.0, 760.0),
		Vector2(190.0, 736.0),
		Vector2(186.0, 682.0),
		Vector2(206.0, 646.0),
		Vector2(206.0, 584.0),
		Vector2(148.0, 568.0),
		Vector2(150.0, 390.0),
		Vector2(206.0, 376.0),
		Vector2(206.0, 270.0),
		Vector2(184.0, 244.0),
		Vector2(146.0, 198.0),
		Vector2(146.0, 158.0),
		Vector2(178.0, 114.0),
	])
	for i: int in loop.size():
		var seg: SegmentShape2D = SegmentShape2D.new()
		seg.a = loop[i]
		seg.b = loop[(i + 1) % loop.size()]
		var shape: CollisionShape2D = CollisionShape2D.new()
		shape.shape = seg
		body.add_child(shape)

	# Monumental Throne Dais block (keeps Ellie in front of Caelia's feet at y ~ 166+)
	_add_box(body, Rect2(226.0, 96.0, 108.0, 62.0))

	# Dual Reflection Basins (walk around them cleanly via the central bridge or outer marble promenade)
	for b_pos: Vector2 in basins:
		_add_box(body, Rect2(b_pos + Vector2(2.0, 4.0), basin_sz - Vector2(4.0, 6.0)))

	# 3 Relic Plinth bases
	for r_pos: Vector2 in relics:
		_add_box(body, Rect2(r_pos + Vector2(-11.0, -10.0), Vector2(22.0, 12.0)))

	# 6 Crystal Pylon bases
	for p_cfg: Dictionary in pylons:
		var p_pos: Vector2 = p_cfg["pos"] as Vector2
		_add_box(body, Rect2(p_pos + Vector2(-10.0, -10.0), Vector2(20.0, 12.0)))

	# 4 Balustrade rails
	for bal_pos: Vector2 in bals:
		_add_box(body, Rect2(bal_pos + Vector2(-20.0, -7.0), Vector2(40.0, 8.0)))


func _add_star_light(pos: Vector2, col: Color, width: int, squash: float, energy: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.position = pos
	light.color = col
	light.energy = energy
	LightTexture.apply(light, width, squash, int(absf(pos.x + pos.y)) % 3)
	add_child(light)
	return light


func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)


func _add_static_prop(node_name: String, base_tex: Texture2D, glow_tex: Texture2D, foot: Vector2, off: Vector2) -> void:
	var holder: Node2D = Node2D.new()
	holder.name = node_name
	holder.position = foot
	add_child(holder)

	var sb: Sprite2D = Sprite2D.new()
	sb.texture = base_tex
	sb.centered = false
	sb.offset = off
	holder.add_child(sb)

	var sg: Sprite2D = Sprite2D.new()
	sg.texture = glow_tex
	sg.centered = false
	sg.offset = off
	sg.material = Unlit.material()
	holder.add_child(sg)


func _add_anim_prop(node_name: String, base_tex: Texture2D, glow_tex: Texture2D, foot: Vector2, off: Vector2, frames: int, fps: float, phase: float) -> Dictionary:
	var holder: Node2D = Node2D.new()
	holder.name = node_name
	holder.position = foot
	add_child(holder)

	var sb: Sprite2D = Sprite2D.new()
	sb.texture = base_tex
	sb.hframes = frames
	sb.centered = false
	sb.offset = off
	holder.add_child(sb)

	var sg: Sprite2D = Sprite2D.new()
	sg.texture = glow_tex
	sg.hframes = frames
	sg.centered = false
	sg.offset = off
	sg.material = Unlit.material()
	holder.add_child(sg)

	var entry: Dictionary = {
		"base": sb,
		"glow": sg,
		"frames": frames,
		"fps": fps,
		"phase": phase,
		"active": true,
	}
	_anims.append(entry)
	return entry


func _refresh_pylons() -> void:
	var manager: Waystones = Waystones.of(get_tree())
	var awake: int = manager.awake_count() if manager != null else 1
	for p: Dictionary in _pylons:
		var lit: bool = awake >= int(p["req"])
		p["active"] = lit
		var g: Sprite2D = p["glow"] as Sprite2D
		var b: Sprite2D = p["base"] as Sprite2D
		var l: PointLight2D = p["light"] as PointLight2D
		if g != null:
			g.visible = lit
		if b != null and not lit:
			b.frame = 0
		if l != null:
			l.visible = lit


func _process(delta: float) -> void:
	_time += delta
	if not _waystones_bound:
		var manager: Waystones = Waystones.of(get_tree())
		if manager != null:
			_waystones_bound = true
			if not manager.awakened.is_connected(_on_waystone_awakened):
				manager.awakened.connect(_on_waystone_awakened)
			_refresh_pylons()

	var cam: Camera2D = get_viewport().get_camera_2d()
	var cam_rel: Vector2 = cam.get_screen_center_position() - global_position - HALL_SIZE * 0.5 if cam != null else Vector2.ZERO

	if _cosmos_mat != null:
		_cosmos_mat.set_shader_parameter("time", _time)
		_cosmos_mat.set_shader_parameter("cam_offset", cam_rel)
	for m_mat: ShaderMaterial in _mirror_mats:
		m_mat.set_shader_parameter("time", _time)
		m_mat.set_shader_parameter("cam_offset", cam_rel)

	for anim: Dictionary in _anims:
		if not bool(anim.get("active", true)):
			continue
		var frames: int = int(anim["frames"])
		var fps: float = float(anim["fps"])
		var phase: float = float(anim["phase"])
		var idx: int = int((_time + phase) * fps) % frames
		(anim["base"] as Sprite2D).frame = idx
		var glow: Sprite2D = anim["glow"] as Sprite2D
		if glow != null:
			glow.frame = idx
			glow.modulate.a = 0.88 + 0.12 * sin(_time * 2.2 + phase * 3.0)

	for isl: Dictionary in _islands:
		var base_p: Vector2 = isl["base"] as Vector2
		var dy: float = sin(_time * float(isl["spd"]) + float(isl["ph"])) * float(isl["amp"])
		(isl["node"] as Node2D).position = Vector2(base_p.x, roundf(base_p.y + dy))

	for m: Dictionary in _motes:
		var ph: float = float(m["ph"])
		var ms: Sprite2D = m["sprite"] as Sprite2D
		var mx: float = float(m["bx"]) + sin(_time * 0.45 + ph) * 8.0
		var my: float = 750.0 - fposmod(_time * float(m["spd"]) + (750.0 - float(m["by"])), 665.0)
		ms.position = Vector2(roundf(mx), roundf(my))
		ms.modulate.a = 0.42 + 0.50 * (0.5 + 0.5 * sin(_time * 2.1 + ph * 2.0))


func _on_waystone_awakened(_id: String) -> void:
	_refresh_pylons()


class _StarHallGiftSpot:
	extends Interactable
	## Future Blessings ("Gaben") altar hook beside the Throne; lets players inspect upcoming divine boons.

	func prompt() -> String:
		var sys: GoddessSystem = GoddessSystem.of(get_tree())
		if sys == null or sys.is_busy() or not sys.is_local_introduced():
			return ""
		return "GABEN"

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 26.0

	func prompt_position() -> Vector2:
		return Vector2(0.0, -46.0)

	func interact(player: Player) -> void:
		var box: DialogueBox = DialogueBox.find(player)
		if box != null and not box.is_active():
			box.start("goddess_gifts_placeholder")
