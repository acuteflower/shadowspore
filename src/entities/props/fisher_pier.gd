class_name FisherPier
extends SeatSpot
## Weathered wooden lakeside fishing pier (`docs/wiesenbiom_ausbau_konzept.md` Stufe 4.3) with a warm hook-lantern,
## dry `"wood"` deck override over shallow lake water, peaceful pier-head resting spot (`E -> "AM FISCHERSTEG RASTEN"`),
## and an abandoned mossy `ReedRowboat` nestled in the nearby reeds (`E -> "ALTES RUDERBOOT DURCHSUCHEN"`).

const PIER_TEX: String = "res://assets/props/fisher_pier.png"
const PIER_GLOW: String = "res://assets/props/fisher_pier_glow.png"
const BOAT_TEX: String = "res://assets/props/reed_rowboat.png"

var pois: MeadowPois
var pier_id: String = ""
var dir_idx: int = 0 ## 0 East, 1 West, 2 South, 3 North
var boat_world_pos: Vector2 = Vector2.ZERO
var boat_searched: bool = false
var deck_rect: Rect2 = Rect2()

var _body: Sprite2D
var _glow: Sprite2D
var _light: NightLight
var _boat_node: ReedRowboatSpot


func setup(owner_pois: MeadowPois, spec: Dictionary) -> void:
	pois = owner_pois
	pier_id = String(spec.get("id", ""))
	dir_idx = clampi(int(spec.get("dir", 0)), 0, 3)
	var t: Array = spec.get("tile", [0, 0]) as Array
	var shore_px: Vector2 = Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8.0, 8.0)
	var fwd: Vector2 = _dir_vec(dir_idx)
	# Shift pier center 28 px out from shore so landward end overlaps bank and tip extends out into lake water!
	position = (shore_px + fwd * 28.0).round()
	var bt: Array = spec.get("boat_tile", t) as Array
	boat_world_pos = (Vector2(float(bt[0]), float(bt[1])) * 16.0 + Vector2(8.0, 8.0)).round()
	if dir_idx in [0, 1]:
		deck_rect = Rect2(position.x - 42.0, position.y - 14.0, 84.0, 26.0)
	else:
		deck_rect = Rect2(position.x - 15.0, position.y - 42.0, 30.0, 84.0)


static func _dir_vec(d: int) -> Vector2:
	match d:
		0: return Vector2.RIGHT
		1: return Vector2.LEFT
		2: return Vector2.DOWN
		_: return Vector2.UP


func contains_deck_point(world_pt: Vector2) -> bool:
	return deck_rect.has_point(world_pt)


func _ready() -> void:
	add_to_group("flora_glow")
	label = "AM FISCHERSTEG RASTEN"
	radius = 20.0
	height = 34.0
	z_index = -3
	var off: Vector2 = Vector2(0.0, -(52.0 - 48.0))
	if ResourceLoader.exists(PIER_TEX):
		_body = Sprite2D.new()
		_body.texture = load(PIER_TEX) as Texture2D
		_body.hframes = 4
		_body.frame = dir_idx
		_body.offset = off
		add_child(_body)
	if ResourceLoader.exists(PIER_GLOW):
		_glow = Sprite2D.new()
		_glow.texture = load(PIER_GLOW) as Texture2D
		_glow.hframes = 4
		_glow.frame = dir_idx
		_glow.offset = off
		_glow.material = Unlit.material()
		add_child(_glow)

	var tip_off: Vector2 = _dir_vec(dir_idx) * 32.0
	_light = NightLight.new()
	_light.position = tip_off + Vector2(0.0, -14.0)
	_light.radius = 58
	_light.base_energy = 0.46
	_light.pulse = 0.14
	_light.glow_color = Color("ffc868")
	add_child(_light)

	_boat_node = ReedRowboatSpot.new()
	_boat_node.setup(self, boat_world_pos - position)
	add_child(_boat_node)
	_boat_node.set_searched(boat_searched)


func _process(_delta: float) -> void:
	if _glow != null:
		_glow.modulate.a = lerpf(0.26, 0.94, TimeManager.night_amount())


func set_boat_searched(val: bool) -> void:
	boat_searched = val
	if _boat_node != null:
		_boat_node.set_searched(val)


func sit_sector() -> int:
	match dir_idx:
		0: return 0 # East
		1: return 4 # West
		2: return 2 # South
		_: return 6 # North


func seat_position() -> Vector2:
	return (global_position + _dir_vec(dir_idx) * 28.0).round()


func approach_position() -> Vector2:
	return (global_position - _dir_vec(dir_idx) * 14.0).round()


func regen_rate() -> float:
	return 0.45


func reach_distance(from: Vector2) -> float:
	var anchor: Vector2 = seat_position()
	var d_seat: float = anchor.distance_to(from) - 22.0
	var d_mid: float = global_position.distance_to(from) - 22.0
	return maxf(0.0, minf(d_seat, d_mid))


func prompt_position() -> Vector2:
	return (seat_position() - global_position) + Vector2(0.0, -28.0)


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.health.current <= 0.0 or player.intro != null or player.story_lock or player.fainting or InputManager.ui_blocking:
		return ""
	if occupied():
		return ""
	return label


func interact(player: Player) -> void:
	if player == null or not player.is_multiplayer_authority() or prompt() == "":
		return
	(player.get_node("RestComponent") as RestComponent).request_sit(self)


class ReedRowboatSpot extends Interactable:
	var pier: FisherPier
	var searched: bool = false
	var _sprite: Sprite2D

	func setup(owner_pier: FisherPier, local_pos: Vector2) -> void:
		pier = owner_pier
		position = local_pos

	func _ready() -> void:
		z_index = 1 ## slightly above pier (-3) so it sorts cleanly in reeds
		if ResourceLoader.exists(FisherPier.BOAT_TEX):
			_sprite = Sprite2D.new()
			_sprite.texture = load(FisherPier.BOAT_TEX) as Texture2D
			_sprite.hframes = 2
			_sprite.offset = Vector2(0.0, -(28.0 - 24.0))
			_sprite.frame = 1 if searched else 0
			add_child(_sprite)

	func set_searched(val: bool) -> void:
		searched = val
		if _sprite != null:
			_sprite.frame = 1 if searched else 0

	func is_interactable() -> bool:
		return not searched

	func prompt() -> String:
		return "" if searched else "ALTES RUDERBOOT DURCHSUCHEN"

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, from.distance_to(global_position) - 34.0)

	func prompt_position() -> Vector2:
		return Vector2(0.0, -24.0)

	func interact(player: Player) -> void:
		if searched or player == null or player.is_busy() or pier == null or pier.pois == null:
			return
		var aim: Vector2 = global_position - player.global_position
		var dir: Vector2 = aim.normalized() if aim.length_squared() > 1.0 else Vector2.DOWN
		player.begin_pick(dir, func() -> void:
			if is_instance_valid(pier) and pier.pois != null:
				pier.pois.request_search_rowboat(pier.pier_id))
