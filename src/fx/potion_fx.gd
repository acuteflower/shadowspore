class_name PotionFx
extends Node2D
## The look of the three special potions on her body (docs/alchemie_konzept.md section 11), a child of the player made by `StatusEffects._show`; it lives as long as
## its effect does (`end()` lets it fade). Unlit, drawn in pixels, every peer runs it from the replicated effect (only the owner sees Klarblick's glints).
##   ashen   - Aschenhaut: soot flakes and embers rise from her, a dull orange ring pulses at her feet, black glowing seams flicker on the body line; louder with the tier.
##   clear_vision - Klarblick: real things she could pick glint with a small green-white cross in the radius; tier III also shows the eyes of shadow creatures in the mist.
##   wisp    - Irrlichtsud: a teal wisp circles her with a trail and a real teal light (`NightLight`, so it only shines at night); the wisp lags behind her when she moves.

const BODY: Vector2 = Vector2(0, -24)

var _id: String = ""
var _effects: StatusEffects
var _time: float = 0.0
var _fade: float = 0.0
var _ending: bool = false
var _glints: Array[Node2D] = [] ## things that glint (refreshed a few times a second)
var _eyes: Array[Node2D] = []
var _scan: float = 0.0
var _wisp_at: Vector2 = Vector2.ZERO ## global position of the wisp (lags behind)
var _trail: Array[Vector2] = []
var _light: NightLight


func bind(id: String, effects: StatusEffects) -> void:
	_id = id
	_effects = effects
	z_index = 5
	material = Unlit.material()
	_wisp_at = (get_parent() as Node2D).global_position + BODY
	if id == "wisp":
		_light = NightLight.new()
		_light.radius = int(_spec().radius) + 24
		_light.base_energy = 0.8
		_light.glow_color = Color("4fe0d0")
		_light.pulse = 0.25
		add_child(_light)


func end() -> void:
	_ending = true


func _tier() -> int:
	return maxi(int(_effects.scale_of(_id)), 1) if _effects != null else 1


func _spec() -> Dictionary:
	match _id:
		"wisp":
			return AlchemyRules.wisp_spec(_tier())
		"clear_vision":
			return AlchemyRules.clarity_spec(_tier())
	return AlchemyRules.ashen_spec(_tier())


func _process(delta: float) -> void:
	_time += delta
	_fade = clampf(_fade + delta * (-3.0 if _ending else 2.5), 0.0, 1.0)
	var owner_node: Node2D = get_parent() as Node2D
	if owner_node == null:
		return
	if _id == "wisp":
		var orbit: Vector2 = owner_node.global_position + BODY + Vector2(cos(_time * 2.1) * 15.0, sin(_time * 2.1) * 6.0 - 6.0 + sin(_time * 3.3) * 2.0)
		_wisp_at = _wisp_at.lerp(orbit, minf(delta * 6.0, 1.0))
		_trail.push_front(_wisp_at)
		if _trail.size() > 7:
			_trail.resize(7)
		if _light != null:
			_light.global_position = _wisp_at + Vector2(0, 12)
	elif _id == "clear_vision":
		_scan -= delta
		if _scan <= 0.0:
			_scan = 0.25
			_refresh_scan(owner_node)
	queue_redraw()


## Only her own machine sees what her clear head shows.
func _refresh_scan(owner_node: Node2D) -> void:
	_glints.clear()
	_eyes.clear()
	if not owner_node.is_multiplayer_authority():
		return
	var radius: float = float(_spec().radius)
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		var thing: Node2D = node as Node2D
		if thing != null and thing != owner_node and thing.is_visible_in_tree() and thing.global_position.distance_to(owner_node.global_position) <= radius \
				and String(thing.call("prompt")) != "":
			_glints.append(thing)
	if bool(_spec().eyes):
		for node: Node in get_tree().get_nodes_in_group("predators"):
			var creature: Node2D = node as Node2D
			if creature != null and creature.is_visible_in_tree() and creature.global_position.distance_to(owner_node.global_position) <= radius * 1.3:
				_eyes.append(creature)


func _dot(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at.round(), Vector2.ONE), color)


func _draw() -> void:
	if _fade <= 0.0:
		return
	match _id:
		"ashen":
			_draw_ashen()
		"clear_vision":
			_draw_clear()
		"wisp":
			_draw_wisp()


func _draw_ashen() -> void:
	var tier: int = _tier()
	var amount: int = 8 + 4 * tier
	for i: int in amount: ## soot flakes and embers climbing off her
		var phase: float = fposmod(_time * (0.5 + 0.08 * float(i % 3)) + float(i) * 0.37, 1.0)
		var x: float = cos(float(i) * 2.399) * (5.0 + float(i % 4) * 2.0) + sin(_time * 3.0 + float(i)) * 1.5
		var y: float = -2.0 - phase * 44.0
		var ember: bool = i % 3 == 0
		var color: Color = Color("ffb060") if ember else Color("2a1620")
		_dot(Vector2(x, y), Color(color, (1.0 - phase) * _fade * (0.9 if ember else 0.7)))
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.0)
	for k: int in 26: ## a dull ring on the ground
		var angle: float = float(k) * TAU / 26.0
		_dot(Vector2(cos(angle) * 11.0, sin(angle) * 4.5 - 1.0), Color("ff7a2a", (0.25 + 0.3 * pulse) * _fade))
	for s: int in 3 + tier: ## glowing seams that flicker along the body line
		if fposmod(_time * 6.0 + float(s) * 0.41, 1.0) < 0.6:
			var seam: Vector2 = Vector2(-4.0 + float(s * 3 % 9), -8.0 - float(s * 7 % 28))
			_dot(seam, Color("ff7a2a", 0.85 * _fade))
			_dot(seam + Vector2(0, 1), Color("ffd9a0", 0.55 * _fade))


func _glint(at: Vector2, color: Color, strength: float) -> void:
	_dot(at, Color(color, strength))
	var arm: float = strength
	if arm > 0.45:
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_dot(at + d, Color(color, strength * 0.6))
	if arm > 0.8:
		for d2: Vector2 in [Vector2.LEFT * 2.0, Vector2.RIGHT * 2.0, Vector2.UP * 2.0, Vector2.DOWN * 2.0]:
			_dot(at + d2, Color(color, strength * 0.35))


func _draw_clear() -> void:
	var owner_node: Node2D = get_parent() as Node2D
	if owner_node == null or not owner_node.is_multiplayer_authority():
		return
	for i: int in _glints.size():
		var thing: Node2D = _glints[i]
		if not is_instance_valid(thing):
			continue
		var twinkle: float = 0.5 + 0.5 * sin(_time * 4.0 + float(i) * 1.7)
		var near: float = clampf(1.0 - thing.global_position.distance_to(owner_node.global_position) / float(_spec().radius) * 0.6, 0.3, 1.0)
		_glint(to_local(thing.global_position + Vector2(0, -10)), Color("d8ffb0"), twinkle * near * _fade)
	for j: int in _eyes.size():
		var creature: Node2D = _eyes[j]
		if not is_instance_valid(creature):
			continue
		var blink: float = 1.0 if fposmod(_time * 0.7 + float(j) * 0.37, 3.0) > 0.12 else 0.0
		var at: Vector2 = to_local(creature.global_position + Vector2(0, -14))
		_dot(at + Vector2(-2, 0), Color("ff4fd8", 0.9 * blink * _fade))
		_dot(at + Vector2(2, 0), Color("ff4fd8", 0.9 * blink * _fade))
		_dot(at + Vector2(-2, -1), Color("ff4fd8", 0.3 * blink * _fade))
		_dot(at + Vector2(2, -1), Color("ff4fd8", 0.3 * blink * _fade))
	for k: int in 6: ## her own head clears: a few green motes rise from her brow
		var phase: float = fposmod(_time * 0.7 + float(k) * 0.17, 1.0)
		_dot(Vector2(sin(_time * 2.0 + float(k) * 2.0) * 4.0, -40.0 - phase * 10.0), Color("eaffc4", (1.0 - phase) * 0.8 * _fade))


func _draw_wisp() -> void:
	for i: int in _trail.size(): ## the trail fades behind it
		var k: float = 1.0 - float(i) / float(_trail.size())
		_dot(to_local(_trail[i]), Color("4fe0d0", k * 0.7 * _fade))
	var head: Vector2 = to_local(_wisp_at)
	var flare: float = 0.7 + 0.3 * sin(_time * 9.0)
	_dot(head, Color("ffffff", _fade))
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_dot(head + d, Color("d6fff6", 0.85 * flare * _fade))
	for d2: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.LEFT * 2.0, Vector2.RIGHT * 2.0, Vector2.UP * 2.0, Vector2.DOWN * 2.0]:
		_dot(head + d2, Color("4fe0d0", 0.45 * flare * _fade))
	if _ending and _light != null:
		_light.visible = _fade > 0.1
