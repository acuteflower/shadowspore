class_name StarHallRoom
extends Node2D
## Caelia's Interstellar Sanctuary (docs/caelia_interstellar_konzept.md):
## Open, floorless, wall-less deep-space clearing where Ellie and Caelia float completely weightlessly.
##   - Fullscreen camera-locked `interstellar_cosmos.gdshader` (Layers 0..5: Milky Way + dark dust lanes,
##     distant galaxies, vacuum spectral starfield, shadowed ringed world, dual volumetric nebulae,
##     near binary/diffraction stars, outer Void-rift horizon scars).
##   - `InterstellarDepthDust` (Layers 6, 7 & 8: wrapping near ice/stardust speed cues, reactive local
##     wake stardust, sparse foreground dust gliding OVER Ellie & Caelia, and Soft Veil Horizon wisps).
##   - Center (1100, 1100): Redesigned floating Goddess Caelia (`StarHallGoddess`) with 360-degree presence.
##   - Arrival (1100, 1390): Free-floating vertical Return Rift (`StarHallReturnSeal`).
##   - Zero-G floating prop anchor registry (`register_floating_prop`) ready for future floating props & seals.

const COSMOS_SHADER: Shader = preload("res://assets/shaders/interstellar_cosmos.gdshader")
const VIEW_SIZE: Vector2 = Vector2(640.0, 360.0)
const HORIZON_BARK_LINE: String = "JENSEITS DES SCHLEIERS WARTET NUR DAS VERGESSEN... BLEIB IM LICHT."

var goddess: StarHallGoddess
var return_seal: StarHallReturnSeal
var dust: InterstellarDepthDust

var _cosmos_layer: CanvasLayer
var _cosmos_rect: ColorRect
var _cosmos_mat: ShaderMaterial
var _floating_props: Array[Dictionary] = []
var _time: float = 0.0
var _bark_shown: bool = false
var _was_local_inside: bool = false
var _center: Vector2 = ZeroGRules.DEFAULT_CENTER
var _arrival: Vector2 = ZeroGRules.DEFAULT_ARRIVAL


func _ready() -> void:
	name = "StarHallRoom"
	y_sort_enabled = true
	_center = ZeroGRules.room_center()
	_arrival = ZeroGRules.arrival_point()
	_build()


func _build() -> void:
	# 1. Infinite Camera-Anchored Interstellar Deep-Space Parallax Backdrop (Layers 0..5)
	_cosmos_layer = CanvasLayer.new()
	_cosmos_layer.name = "InterstellarCosmosLayer"
	_cosmos_layer.layer = -20
	_cosmos_layer.visible = false
	add_child(_cosmos_layer)

	_cosmos_rect = ColorRect.new()
	_cosmos_rect.name = "InterstellarCosmosRect"
	_cosmos_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cosmos_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cosmos_mat = ShaderMaterial.new()
	_cosmos_mat.shader = COSMOS_SHADER
	_cosmos_mat.set_shader_parameter("view_size", VIEW_SIZE)
	_cosmos_mat.set_shader_parameter("cam_pos", Vector2.ZERO)
	_cosmos_mat.set_shader_parameter("time", 0.0)
	_cosmos_mat.set_shader_parameter("horizon_amt", 0.0)
	_cosmos_mat.set_shader_parameter("caelia_prox", 0.0)
	_cosmos_mat.set_shader_parameter("caelia_screen", VIEW_SIZE * 0.5)
	_cosmos_rect.material = _cosmos_mat
	_cosmos_layer.add_child(_cosmos_rect)

	# 2. Layers 6, 7 & 8 Depth Dust, Reactive Wake & Foreground Parallax
	dust = InterstellarDepthDust.new()
	add_child(dust)

	# 3. Caelia's Celestial Clearing Lights (balanced so her moon-ivory gown keeps crisp shading without blowout)
	_add_star_light(_center + Vector2(0.0, -10.0), Color(0.76, 0.94, 1.00), 340, 0.86, 0.34)
	_add_star_light(_center + Vector2(0.0, 14.0), Color(1.00, 0.90, 0.68), 230, 0.84, 0.18)

	# 4. Freely Floating Goddess Caelia in the Center
	goddess = StarHallGoddess.new()
	goddess.position = _center
	add_child(goddess)

	# 5. Free-Floating Return Rift just south of Ellie's arrival spot so both Ellie and the rift read clearly
	return_seal = StarHallReturnSeal.new()
	return_seal.position = _arrival + Vector2(0.0, 44.0)
	add_child(return_seal)


## Registers any future zero-G floating prop/relic/seal so it gently bobs and yields softly to player wake.
func register_floating_prop(node: Node2D, anchor: Vector2, amp: Vector2 = Vector2(1.5, 3.0), speed: float = 0.85, phase: float = 0.0, wake_factor: float = 1.0) -> void:
	if node == null:
		return
	node.position = anchor
	_floating_props.append({
		"node": node,
		"anchor": anchor,
		"offset": Vector2.ZERO,
		"vel": Vector2.ZERO,
		"amp": amp,
		"speed": speed,
		"phase": phase,
		"wake": wake_factor,
	})


## Emits a subtle stardust trail speck at `world_pos` when Ellie boost-glides or dashes in space.
func emit_trail_mote(world_pos: Vector2, drift_vel: Vector2, golden: bool = false) -> void:
	if dust != null:
		dust.spawn_trail_mote(world_pos - global_position, drift_vel, golden)


func center_global() -> Vector2:
	return global_position + _center


func _add_star_light(pos: Vector2, col: Color, width: int, squash: float, energy: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.position = pos
	light.color = col
	light.energy = energy
	LightTexture.apply(light, width, squash, int(absf(pos.x + pos.y)) % 3)
	add_child(light)
	return light


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _cosmos_layer != null and not is_visible_in_tree():
		_cosmos_layer.visible = false


func _process(delta: float) -> void:
	_time += delta
	var cam: Camera2D = get_viewport().get_camera_2d()
	var cam_global: Vector2 = cam.get_screen_center_position() if cam != null else center_global()
	var cam_local: Vector2 = cam_global - global_position

	# Show fullscreen cosmic CanvasLayer ONLY while the active camera is viewing this interstellar sanctuary
	var active_view: bool = is_visible_in_tree() and (Interiors.in_cosmos_band(cam_global) or cam_local.distance_to(_center) < 1800.0)
	if _cosmos_layer != null:
		_cosmos_layer.visible = active_view
	if not active_view:
		_was_local_inside = false
		return

	var local_player: Player = null
	var players_local: Array[Dictionary] = []
	for p: Player in Player.all:
		if not is_instance_valid(p):
			continue
		var pl: Vector2 = p.global_position - global_position
		if pl.distance_to(_center) < 1600.0:
			players_local.append({"pos": pl, "vel": p.velocity})
			if p.is_multiplayer_authority():
				local_player = p

	if local_player != null and not _was_local_inside:
		_was_local_inside = true
		_bark_shown = false

	var focus_local: Vector2 = (local_player.global_position - global_position) if local_player != null else cam_local
	var rel_focus: Vector2 = focus_local - _center
	var horizon_amt: float = ZeroGRules.horizon_ratio(rel_focus)
	var horizon_inward: Vector2 = -rel_focus.normalized() if rel_focus.length_squared() > 1.0 else Vector2.UP

	# One-time gentle whisper from Caelia if Ellie floats deep into the outer Veil Horizon
	if local_player != null and not _bark_shown:
		var bark_r: float = float(ZeroGRules.section("horizon").get("bark_radius", 835.0))
		if rel_focus.length() >= bark_r and not local_player.story_lock:
			_bark_shown = true
			var speech: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
			if speech != null:
				speech.speak("CAELIA", HORIZON_BARK_LINE, 3.4)

	var caelia_local: Vector2 = goddess.position if is_instance_valid(goddess) else _center
	var caelia_dist: float = focus_local.distance_to(caelia_local)
	var caelia_prox: float = clampf(1.0 - caelia_dist / 420.0, 0.0, 1.0)
	var caelia_screen: Vector2 = VIEW_SIZE * 0.5 + (caelia_local - cam_local)

	if _cosmos_mat != null:
		_cosmos_mat.set_shader_parameter("view_size", VIEW_SIZE)
		_cosmos_mat.set_shader_parameter("cam_pos", cam_local - _center)
		_cosmos_mat.set_shader_parameter("time", _time)
		_cosmos_mat.set_shader_parameter("horizon_amt", horizon_amt)
		_cosmos_mat.set_shader_parameter("caelia_prox", caelia_prox)
		_cosmos_mat.set_shader_parameter("caelia_screen", caelia_screen)

	if dust != null:
		dust.step_dust(delta, cam_local, players_local, horizon_amt, horizon_inward)

	_step_floating_props(delta, players_local)


func _step_floating_props(delta: float, players_local: Array[Dictionary]) -> void:
	for i: int in range(_floating_props.size() - 1, -1, -1):
		var fp: Dictionary = _floating_props[i]
		var node: Node2D = fp["node"] as Node2D
		if not is_instance_valid(node):
			_floating_props.remove_at(i)
			continue
		var anchor: Vector2 = fp["anchor"] as Vector2
		var off: Vector2 = fp["offset"] as Vector2
		var vel: Vector2 = fp["vel"] as Vector2
		var amp: Vector2 = fp["amp"] as Vector2
		var spd: float = float(fp["speed"])
		var ph: float = float(fp["phase"])
		var wake: float = float(fp["wake"])

		if wake > 0.0:
			var cur_p: Vector2 = anchor + off
			for pd: Dictionary in players_local:
				var pv: Vector2 = pd["vel"] as Vector2
				if pv.length_squared() < 144.0:
					continue
				var d: Vector2 = cur_p - (pd["pos"] as Vector2)
				var d2: float = d.length_squared()
				if d2 < 56.0 * 56.0 and d2 > 4.0:
					var dist: float = sqrt(d2)
					vel += (d / dist) * (1.0 - dist / 56.0) * minf(pv.length(), 150.0) * 0.55 * wake * delta

		# Elastic spring back to zero-G equilibrium
		vel += (-off * 3.2 - vel * 2.4) * delta
		off += vel * delta
		fp["offset"] = off
		fp["vel"] = vel

		var bob: Vector2 = Vector2(sin(_time * spd * 0.65 + ph) * amp.x, sin(_time * spd + ph) * amp.y)
		node.position = (anchor + off + bob).round()
