class_name ZonePortal
extends Interactable
## Context-dependent zone transition marker: unlocked paths trigger on walk-in, while gates/locked exits require E interaction.

var portal_id: String = ""
var source_zone_id: String = ""
var target_zone_id: String = ""
var target_spawn: String = "default"
var trigger_mode: String = "walk" ## "walk" or "interact"
var label: String = ""
var locked: bool = false
var locked_hint: String = ""
var dir: String = "east"
var portal_size: Vector2 = Vector2(64.0, 64.0)

var _world: Variant
var _area: Area2D
var _bob: float = 0.0
var _glow_light: NightLight


func setup(owner_world: Variant, zone_id: String, spec: Dictionary) -> void:
	_world = owner_world
	source_zone_id = zone_id
	portal_id = String(spec.get("id", "portal"))
	target_zone_id = String(spec.get("target_zone", ""))
	target_spawn = String(spec.get("target_spawn", "default"))
	trigger_mode = String(spec.get("trigger", "walk"))
	label = String(spec.get("label", target_zone_id.to_upper()))
	locked = bool(spec.get("locked", false))
	locked_hint = String(spec.get("locked_hint", "Noch verschlossen."))
	dir = String(spec.get("dir", "east"))
	var sz: Array = spec.get("size", [64, 64]) as Array
	if sz.size() >= 2:
		portal_size = Vector2(float(sz[0]), float(sz[1]))
	name = "ZonePortal_%s" % portal_id


func _ready() -> void:
	z_index = -3
	if not locked and trigger_mode == "walk":
		_area = Area2D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2 ## Player physics layer
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = portal_size
		shape.shape = rect
		_area.add_child(shape)
		add_child(_area)
		_area.body_entered.connect(_on_body_entered)
	elif locked:
		## Small solid timber/rock barricade collider so player feels a physical frontier before pressing E
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(36.0, 14.0) if dir in ["north", "south"] else Vector2(14.0, 36.0)
		shape.shape = rect
		body.add_child(shape)
		add_child(body)
	_glow_light = NightLight.new()
	_glow_light.radius = 44
	_glow_light.base_energy = 0.45 if not locked else 0.25
	_glow_light.glow_color = Color("7cf4de") if not locked else Color("d96b6b")
	add_child(_glow_light)
	queue_redraw()


func _process(delta: float) -> void:
	_bob += delta * 2.2
	if not locked:
		queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if locked or trigger_mode != "walk":
		return
	if body is Player and (body as Player).is_multiplayer_authority():
		if _world != null and _world.has_method("request_portal_travel"):
			_world.call("request_portal_travel", source_zone_id, portal_id, body)


func prompt() -> String:
	if trigger_mode == "interact" or locked:
		return "NACH %s" % label if not locked else label
	return ""


func prompt_hint() -> String:
	if locked:
		return locked_hint
	return ""


func reach_distance(from: Vector2) -> float:
	if trigger_mode != "interact" and not locked:
		return INF
	return maxf(0.0, from.distance_to(global_position) - 34.0)


func prompt_position() -> Vector2:
	return Vector2(0.0, -30.0)


func interact(player: Player) -> void:
	if locked:
		return
	if _world != null and _world.has_method("request_portal_travel"):
		_world.call("request_portal_travel", source_zone_id, portal_id, player)


func _draw() -> void:
	var dir_vec: Vector2 = Vector2.RIGHT
	match dir:
		"west":
			dir_vec = Vector2.LEFT
		"north":
			dir_vec = Vector2.UP
		"south":
			dir_vec = Vector2.DOWN
	if locked:
		## Crisp pixel barricade / chain posts across the closed passage
		var perp: Vector2 = Vector2(-dir_vec.y, dir_vec.x)
		var bar_half: float = 20.0
		var p0: Vector2 = -perp * bar_half
		var p1: Vector2 = perp * bar_half
		draw_line(p0 + Vector2(0, -3), p1 + Vector2(0, -3), Color("3c2b24"), 5.0)
		draw_line(p0 + Vector2(0, -3), p1 + Vector2(0, -3), Color("684c3c"), 3.0)
		draw_rect(Rect2(p0 - Vector2(4, 10), Vector2(8, 16)), Color("4d382c"))
		draw_rect(Rect2(p1 - Vector2(4, 10), Vector2(8, 16)), Color("4d382c"))
		draw_circle(Vector2(0, -5), 5.0, Color("201624"))
		draw_circle(Vector2(0, -5), 3.0, Color("d96b6b"))
		return
	## Open path marker: soft glowing cobblestones + animated directional chevron
	var pulse: float = 0.65 + 0.35 * sin(_bob)
	var step_col: Color = Color(0.45, 0.92, 0.84, 0.24 * pulse)
	var chevron_col: Color = Color(0.68, 0.98, 0.90, 0.72 * pulse)
	draw_circle(Vector2.ZERO, 18.0, Color(0.42, 0.92, 0.84, 0.08 * pulse))
	for i: int in range(3):
		var offset: float = float(i - 1) * 11.0 + sin(_bob - float(i) * 0.6) * 2.5
		var center: Vector2 = dir_vec * offset
		var perp: Vector2 = Vector2(-dir_vec.y, dir_vec.x)
		var tip: Vector2 = center + dir_vec * 6.0
		var wing_a: Vector2 = center - dir_vec * 3.0 + perp * 7.0
		var wing_b: Vector2 = center - dir_vec * 3.0 - perp * 7.0
		draw_line(wing_a, tip, step_col, 4.0)
		draw_line(wing_b, tip, step_col, 4.0)
		draw_line(wing_a, tip, chevron_col, 2.0)
		draw_line(wing_b, tip, chevron_col, 2.0)
