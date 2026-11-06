class_name ElliePortrait
extends Control
## Generated four-state portrait. Real blink frames, pixel-quantized breath/hair motion.
const SHEET: Texture2D = preload("res://assets/ui/ellie_dialogue_v3.png")
const SHADER: Shader = preload("res://assets/shaders/dialogue_portrait.gdshader")
var _ink: ShaderMaterial
var _clock: float = 0.0
var _next_blink: float = 2.8
var _blink_left: float = 0.0
var reflective: bool = false
var hurt: bool = false
var speaking: bool = false
var talk_char: String = "" ## the letter being typed: it picks the mouth shape
var _viseme: int = 0
var _viseme_hold: float = 0.0
var opacity: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ink = ShaderMaterial.new()
	_ink.shader = SHADER
	material = _ink

## Vowels open the mouth (a wide, e i smiling, o u round), m b p and pauses close it, other letters narrow it; a shape is held a moment.
func _update_mouth(delta: float) -> void:
	_viseme_hold -= delta
	if not speaking:
		_viseme = 0
		return
	if _viseme_hold > 0.0:
		return
	var c: String = talk_char.to_lower()
	var v: int = 1
	if c in ["a", "ä"]:
		v = 3
	elif c in ["e", "i", "y"]:
		v = 2
	elif c in ["o", "u", "ö", "ü"]:
		v = 4
	elif c in ["m", "b", "p", " ", ".", ",", "!", "?", "…", "-", ""]:
		v = 0
	if v != _viseme:
		_viseme = v
		_viseme_hold = 0.07


func advance(delta: float) -> void:
	_update_mouth(delta)
	_clock += delta
	_next_blink -= delta
	_blink_left = maxf(0.0, _blink_left - delta)
	if _next_blink <= 0.0:
		_blink_left = 0.13
		_next_blink = 3.4 + sin(_clock * 0.7) * 0.7
	if _ink == null:
		return
	# Two-by-two generated sheet. Draw the upper body, on a 103x153 art grid,
	# each art pixel occupying exactly 2x2 game pixels (4x4 at 1280x720).
	var cell_size: Vector2 = Vector2(SHEET.get_size()) / 2.0
	_ink.set_shader_parameter("frame_region", Vector4(0, cell_size.y if hurt else 0.0, cell_size.x, cell_size.x * 1.58))
	_ink.set_shader_parameter("blink_offset", cell_size.x)
	_ink.set_shader_parameter("sheet_size", Vector2(SHEET.get_size()))
	_ink.set_shader_parameter("logical_size", Vector2(DialogueArt.LOGICAL_SIZE))
	_ink.set_shader_parameter("clock", _clock)
	_ink.set_shader_parameter("speaking", speaking)
	_ink.set_shader_parameter("viseme", _viseme)
	_ink.set_shader_parameter("blinking", _blink_left > 0.0)
	_ink.set_shader_parameter("injured", hurt)
	_ink.set_shader_parameter("reflective", reflective)
	_ink.set_shader_parameter("fade", opacity)
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(SHEET, Rect2(Vector2.ZERO, size), false)
