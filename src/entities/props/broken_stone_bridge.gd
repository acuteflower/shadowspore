class_name BrokenStoneBridge
extends Node2D
## Ancient mossy stone arch bridge spanning a deep meadow river (`docs/wiesenbiom_ausbau_konzept.md` Stufe 4.2).
## Both stone abutments extend out over the river (`deck_rects` override `WorldRivers` with dry `"stone"` surface!),
## leaving a crisp ~`48–56 px` collapsed gap right over the deep current that can be crossed with **Schattenschritt (`Alt`)**!

const BRIDGE_TEX: String = "res://assets/props/broken_stone_bridge.png"
const BRIDGE_GLOW: String = "res://assets/props/broken_stone_bridge_glow.png"

var bridge_id: String = ""
var axis: String = "ew" ## "ew" or "ns"
var neg_pos: Vector2 = Vector2.ZERO
var pos_pos: Vector2 = Vector2.ZERO
var chest_tier: String = ""
var chest_bank: String = "pos"
var deck_rects: Array[Rect2] = [] ## world-space walkable stone deck rectangles

var _glow_a: Sprite2D
var _glow_b: Sprite2D


func setup(spec: Dictionary) -> void:
	bridge_id = String(spec.get("id", ""))
	axis = String(spec.get("axis", "ew"))
	var t: Array = spec.get("tile", [0, 0]) as Array
	position = Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8.0, 8.0)
	var nb: Array = spec.get("neg_bank", [t[0] - 3, t[1]]) as Array
	var pb: Array = spec.get("pos_bank", [t[0] + 3, t[1]]) as Array
	neg_pos = Vector2(float(nb[0]), float(nb[1])) * 16.0 + Vector2(8.0, 8.0)
	pos_pos = Vector2(float(pb[0]), float(pb[1])) * 16.0 + Vector2(8.0, 8.0)
	chest_tier = String(spec.get("chest_tier", ""))
	chest_bank = String(spec.get("chest_bank", "pos"))
	_compute_decks()


func _compute_decks() -> void:
	deck_rects.clear()
	var mid: Vector2 = (neg_pos + pos_pos) * 0.5
	if axis == "ew":
		# Place West abutment so its jagged tip stops at mid.x - 21 px, East abutment starting at mid.x + 21 px (42 px gap -> crisp Shadow-Step within 54 px range!)
		var west_anchor: Vector2 = Vector2(mid.x - 21.0 - 36.0, mid.y)
		var east_anchor: Vector2 = Vector2(mid.x + 21.0 + 36.0, mid.y)
		neg_pos = west_anchor
		pos_pos = east_anchor
		deck_rects.append(Rect2(west_anchor.x - 48.0, west_anchor.y - 14.0, 84.0, 26.0))
		deck_rects.append(Rect2(east_anchor.x - 36.0, east_anchor.y - 14.0, 84.0, 26.0))
	else:
		var north_anchor: Vector2 = Vector2(mid.x, mid.y - 21.0 - 30.0)
		var south_anchor: Vector2 = Vector2(mid.x, mid.y + 21.0 + 30.0)
		neg_pos = north_anchor
		pos_pos = south_anchor
		deck_rects.append(Rect2(north_anchor.x - 18.0, north_anchor.y - 48.0, 36.0, 78.0))
		deck_rects.append(Rect2(south_anchor.x - 18.0, south_anchor.y - 30.0, 36.0, 78.0))


func contains_deck_point(world_pt: Vector2) -> bool:
	for r: Rect2 in deck_rects:
		if r.has_point(world_pt):
			return true
	return false


func _ready() -> void:
	add_to_group("flora_glow")
	z_index = -3 ## above river water (-7) & glow (-6), below walking characters (0)
	var frame_neg: int = 0 if axis == "ew" else 2
	var frame_pos: int = 1 if axis == "ew" else 3
	_glow_a = _spawn_abutment(neg_pos - position, frame_neg)
	_glow_b = _spawn_abutment(pos_pos - position, frame_pos)
	_build_parapet_colliders()

	if chest_tier != "":
		var chests: LootChests = LootChests.of(get_tree())
		if chests != null:
			var bank_pt: Vector2 = pos_pos if chest_bank == "pos" else neg_pos
			var off: Vector2 = Vector2(36.0 if chest_bank == "pos" else -36.0, -18.0) if axis == "ew" else Vector2(28.0, 34.0 if chest_bank == "pos" else -34.0)
			chests.place(bridge_id + "_chest", chest_tier, bank_pt + off, chest_bank == "pos")


func _spawn_abutment(local_pt: Vector2, frame_idx: int) -> Sprite2D:
	var off: Vector2 = Vector2(0.0, -(56.0 - 48.0)) ## anchor (48, 56) inside 96x96
	if ResourceLoader.exists(BRIDGE_TEX):
		var sp: Sprite2D = Sprite2D.new()
		sp.texture = load(BRIDGE_TEX) as Texture2D
		sp.hframes = 4
		sp.frame = frame_idx
		sp.position = local_pt.round()
		sp.offset = off
		add_child(sp)
	var gl: Sprite2D = null
	if ResourceLoader.exists(BRIDGE_GLOW):
		gl = Sprite2D.new()
		gl.texture = load(BRIDGE_GLOW) as Texture2D
		gl.hframes = 4
		gl.frame = frame_idx
		gl.position = local_pt.round()
		gl.offset = off
		gl.material = Unlit.material()
		add_child(gl)
	var nl: NightLight = NightLight.new()
	nl.position = local_pt + (Vector2(0.0, -16.0) if axis == "ew" else Vector2(-16.0, 0.0))
	nl.radius = 44
	nl.base_energy = 0.34
	nl.pulse = 0.10
	nl.glow_color = Color("78f4e6")
	add_child(nl)
	return gl


func _build_parapet_colliders() -> void:
	# Low stone side-parapet rails keep players from accidentally slipping off the sides while leaving the broken gap open for Shadow-Step!
	var sb: StaticBody2D = StaticBody2D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	for r: Rect2 in deck_rects:
		var local_r: Rect2 = Rect2(r.position - global_position, r.size)
		if axis == "ew":
			for y_rail: float in [local_r.position.y - 3.0, local_r.end.y + 3.0]:
				var cs: CollisionShape2D = CollisionShape2D.new()
				var box: RectangleShape2D = RectangleShape2D.new()
				box.size = Vector2(local_r.size.x - 8.0, 5.0)
				cs.shape = box
				cs.position = Vector2(local_r.get_center().x, y_rail)
				sb.add_child(cs)
		else:
			for x_rail: float in [local_r.position.x - 3.0, local_r.end.x + 3.0]:
				var cs2: CollisionShape2D = CollisionShape2D.new()
				var box2: RectangleShape2D = RectangleShape2D.new()
				box2.size = Vector2(5.0, local_r.size.y - 8.0)
				cs2.shape = box2
				cs2.position = Vector2(x_rail, local_r.get_center().y)
				sb.add_child(cs2)
	add_child(sb)


func _process(_delta: float) -> void:
	var night: float = TimeManager.night_amount()
	var a: float = lerpf(0.24, 0.90, night)
	if _glow_a != null:
		_glow_a.modulate.a = a
	if _glow_b != null:
		_glow_b.modulate.a = a
