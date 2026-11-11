class_name SpeechPortrait
extends RefCounted
## A baked speaking portrait (Gustav): the sheet of `tools/art_gustav_portrait.py` holds 5 mouth shapes x eyes open / closed, 103 x 153 px each.
## It follows the rules of `ElliePortrait`: the letter being typed picks the shape (a = 3, e i y = 2, o u = 4, m b p, space and punctuation = 0,
## other letters = 1), a shape is held 0.07 s, the eyes close for 0.13 s every ~3.4 s. `frame()` is an `AtlasTexture` of exactly one frame, so
## `DialogueArt.valid_portrait` and the silhouette shader of unknown speakers work on it as on any other portrait.

const PATH: String = "res://data/gustav_portrait.json"

var talk_char: String = ""
var speaking: bool = false
var hurt: bool = false ## sheets with four rows (Ellie): rows 2-3 are the wounded pair
var eyes_shut: bool = false ## holds the eyes closed (reflective lines)
var _sheet: Texture2D
var _frame: AtlasTexture = AtlasTexture.new()
var _cell: Vector2i = DialogueArt.LOGICAL_SIZE
var _hold_time: float = 0.07
var _blink_every: float = 3.4
var _blink_length: float = 0.13
var _clock: float = 0.0
var _viseme: int = 0
var _viseme_hold: float = 0.0
var _next_blink: float = 2.8
var _blink_left: float = 0.0


static func create(spec_path: String = PATH) -> SpeechPortrait:
	var spec: Dictionary = _read(spec_path)
	if spec.is_empty() or not ResourceLoader.exists(String(spec.get("sheet", ""))):
		return null
	var portrait: SpeechPortrait = SpeechPortrait.new()
	portrait._sheet = load(String(spec.sheet)) as Texture2D
	var cell: Array = spec.get("frame", [103, 153]) as Array
	portrait._cell = Vector2i(int(cell[0]), int(cell[1]))
	portrait._hold_time = float(spec.get("viseme_hold", 0.07))
	var blink: Dictionary = spec.get("blink", {}) as Dictionary
	portrait._blink_every = float(blink.get("interval", 3.4))
	portrait._blink_length = float(blink.get("length", 0.13))
	portrait._frame.atlas = portrait._sheet
	portrait._apply(0, false)
	return portrait if DialogueArt.valid_portrait(portrait._frame) else null


static func _read(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func frame() -> Texture2D:
	return _frame


func advance(delta: float) -> void:
	_clock += delta
	_viseme_hold -= delta
	if not speaking:
		_viseme = 0
	elif _viseme_hold <= 0.0:
		var v: int = _viseme_for(talk_char)
		if v != _viseme:
			_viseme = v
			_viseme_hold = _hold_time
	_next_blink -= delta
	_blink_left = maxf(0.0, _blink_left - delta)
	if _next_blink <= 0.0:
		_blink_left = _blink_length
		_next_blink = _blink_every + sin(_clock * 0.7) * 0.7
	_apply(_viseme, _blink_left > 0.0 or eyes_shut)


static func _viseme_for(character: String) -> int:
	var c: String = character.to_lower()
	if c in ["a", "ä"]:
		return 3
	if c in ["e", "i", "y"]:
		return 2
	if c in ["o", "u", "ö", "ü"]:
		return 4
	if c in ["m", "b", "p", " ", ".", ",", "!", "?", "…", "-", ""]:
		return 0
	return 1


func _apply(viseme: int, closed: bool) -> void:
	var row: int = (2 if hurt else 0) + (1 if closed else 0)
	_frame.region = Rect2(viseme * _cell.x, row * _cell.y, _cell.x, _cell.y)
