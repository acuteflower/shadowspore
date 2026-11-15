class_name StarHallReturnSeal
extends Interactable
## Floating turquoise-gold arrival & return seal at the southern circle of the Star Hall (280, 715).
## Pressing E sends the local player back to her origin waystone statue.

const SEAL_TEX: Texture2D = preload("res://assets/interior/starhall/return_seal.png")
const SEAL_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/return_seal_glow.png")
const FRAMES: int = 8
const FPS: float = 7.0
const REACH: float = 28.0

var _body: Sprite2D
var _glow: Sprite2D
var _light: PointLight2D
var _t: float = 0.0


func _ready() -> void:
	name = "StarHallReturnSeal"
	var off: Vector2 = Vector2(-32.0, -26.0)
	_body = Sprite2D.new()
	_body.texture = SEAL_TEX
	_body.hframes = FRAMES
	_body.centered = false
	_body.offset = off
	_body.z_index = -5
	add_child(_body)

	_glow = Sprite2D.new()
	_glow.texture = SEAL_GLOW_TEX
	_glow.hframes = FRAMES
	_glow.centered = false
	_glow.offset = off
	_glow.z_index = -4
	_glow.material = Unlit.material()
	add_child(_glow)

	_light = PointLight2D.new()
	_light.position = Vector2(0.0, -4.0)
	_light.color = Color("7af5ee")
	_light.energy = 0.62
	LightTexture.apply(_light, 132, 0.65, 1)
	add_child(_light)


func prompt() -> String:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null and sys.is_busy():
		return ""
	return "ZURÜCKKEHREN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - REACH


func prompt_position() -> Vector2:
	return Vector2(0.0, -34.0)


func interact(player: Player) -> void:
	var sys: GoddessSystem = GoddessSystem.of(get_tree())
	if sys != null:
		sys.return_from_starhall(player)


func _process(delta: float) -> void:
	_t += delta
	var frame_idx: int = int(_t * FPS) % FRAMES
	if _body != null:
		_body.frame = frame_idx
	if _glow != null:
		_glow.frame = frame_idx
	if _light != null:
		_light.energy = 0.56 + 0.14 * sin(_t * 2.1)
