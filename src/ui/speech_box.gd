class_name SpeechBox
extends Control
## The speech box ("Zuruf"): a card of bark paper at the bottom of the screen with a hanging name tag and the words typed out, for what someone says while the player
## is steering (or in the middle of a cutscene). No portrait, no input, nothing pauses: the line stays as long as it takes to read and withers away, the next one
## follows. It sits in the HUD (group `speech_box`) and is driven from code: `await speak(speaker, text)`, `await play(id)` (an entry of data/dialogue.json: lines with
## `speaker`, `text`, optional `hold` seconds), or a quest step event `bark:<id>`. It waits while a full dialogue is open and fades while the map or the inventory is.

signal line_done

const TYPE_RATE: float = 42.0 ## characters per second
const MAX_TEXT: int = 238 ## px, widest line of text
const PAPER_ALPHA: float = 0.82 ## the card is a little see-through
const GROW: float = 0.32
const FADE: float = 0.4
const BOTTOM_GAP: float = 64.0 ## from the bottom of the screen to the card, above the hotbar

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _lines: PackedStringArray = PackedStringArray()
var _phase: int = 0 ## 0 idle, 1 growing, 2 typing and holding, 3 fading
var _t: float = 0.0
var _typed: float = 0.0
var _alpha: float = 1.0
var _time: float = 0.0
var _next_id: int = 0
var _done_id: int = 0
var _dialogue: DialogueBox
var _quests: QuestComponent


func _ready() -> void:
	add_to_group("speech_box")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func bind(quests: QuestComponent, dialogue: DialogueBox) -> void:
	_dialogue = dialogue
	_quests = quests
	quests.story_event.connect(func(event_name: String) -> void:
		if event_name.begins_with("bark:"):
			play(event_name.trim_prefix("bark:")))


## Says one line and returns when it is gone (`await`). `hold` < 0: as long as it takes to read.
func speak(speaker: String, text: String, hold: float = -1.0) -> void:
	_next_id += 1
	var id: int = _next_id
	_queue.append({"id": id, "speaker": speaker.to_upper(), "text": text, "hold": hold})
	while _done_id < id:
		await line_done


## Plays the lines of data/dialogue.json `id` one after the other.
func play(id: String) -> void:
	for line: Dictionary in DataRegistry.get_entry("dialogue", id).get("lines", []) as Array:
		var speaker: String = String(line.get("speaker", "ELLIE"))
		if line.has("known_flag") and _quests != null and _quests.has_flag(String(line.known_flag)): ## someone who has introduced himself shows his name
			speaker = String(line.get("known_name", speaker))
		await speak(speaker, String(line.text), float(line.get("hold", -1.0)))


func is_speaking() -> bool:
	return _phase != 0 or not _queue.is_empty()


func _process(delta: float) -> void:
	var blocked: bool = get_tree().paused or (_dialogue != null and _dialogue.is_active())
	var hud: Node = get_parent()
	var covered: bool = (hud.get_node_or_null("MapWindow") as CanvasItem).visible or (hud.get_node_or_null("InventoryWindow") as CanvasItem).visible
	_alpha = move_toward(_alpha, 0.0 if (blocked or covered) else 1.0, delta * 6.0)
	if _phase == 0 and not _queue.is_empty() and not blocked:
		_begin(_queue.pop_front() as Dictionary)
	visible = _phase != 0 and _alpha > 0.0
	if _phase == 0 or blocked:
		return
	_time += delta
	_t += delta
	match _phase:
		1:
			if _t >= GROW:
				_phase = 2
				_t = 0.0
		2:
			_typed = minf(_typed + TYPE_RATE * delta, float(String(_current.text).length()))
			var read: float = float(String(_current.text).length()) / TYPE_RATE + (float(_current.hold) if float(_current.hold) >= 0.0 else maxf(1.3, String(_current.text).length() * 0.045))
			if _t >= read:
				_phase = 3
				_t = 0.0
		3:
			if _t >= FADE:
				_phase = 0
				_done_id = int(_current.id)
				line_done.emit()
	queue_redraw()


func _begin(line: Dictionary) -> void:
	_current = line
	_lines = _wrap(String(line.text))
	_phase = 1
	_t = 0.0
	_typed = 0.0


func _wrap(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var row: String = ""
	for word: String in text.split(" ", false):
		var tryout: String = word if row == "" else row + " " + word
		if PixelText.width(tryout) > MAX_TEXT and row != "":
			out.append(row)
			row = word
		else:
			row = tryout
	if row != "":
		out.append(row)
	return out


func _draw() -> void:
	if _phase == 0:
		return
	var grow: float = clampf(_t / GROW, 0.0, 1.0) if _phase == 1 else 1.0
	grow = grow * grow * (3.0 - 2.0 * grow)
	var leave: float = clampf(_t / FADE, 0.0, 1.0) if _phase == 3 else 0.0
	var fade: float = grow * (1.0 - leave) * _alpha
	if fade <= 0.0:
		return
	var name_text: String = String(_current.speaker)
	var widest: int = PixelText.width(name_text) + 20
	for row: String in _lines:
		widest = maxi(widest, PixelText.width(row))
	var width: float = clampf(widest + 30.0, 150.0, MAX_TEXT + 34.0)
	var height: float = 22.0 + _lines.size() * 10.0
	var rise: float = (1.0 - grow) * 10.0 + leave * 6.0
	var origin: Vector2 = Vector2(roundf((size.x - width) / 2.0), roundf(size.y - BOTTOM_GAP - height + rise))
	# the vine along the top edge grows out from the middle, a leaf at either end
	var reach: float = width * 0.5 * grow
	for dir: int in [-1, 1]:
		for xi: int in int(reach) + 1:
			var x: float = origin.x + width * 0.5 + dir * xi
			var y: float = origin.y - 2.0 + sin(xi * 0.09 + (0.0 if dir > 0 else 2.0)) * 1.2
			draw_rect(Rect2(x, roundf(y) + 1.0, 1, 2), Color(VineStyle.OUTLINE, fade))
			draw_rect(Rect2(x, roundf(y), 1, 2), Color(VineStyle.BARK, fade))
		if grow > 0.6:
			VineStyle.leaf(self, Vector2(origin.x + width * 0.5 + dir * reach, origin.y - 2.0), dir, -1, 3, Color(VineStyle.LEAF, fade), Color(VineStyle.LEAF_LIGHT, fade))
	VineStyle.paper(self, Rect2(origin, Vector2(width, height)), fade * PAPER_ALPHA, VineStyle.void_amount(), 31)
	VineStyle.leaf(self, origin + Vector2(width - 3.0, 3.0), 1, -1, 3, Color(VineStyle.LEAF, fade), Color(VineStyle.LEAF_LIGHT, fade)) ## leaves on the corners
	VineStyle.leaf(self, origin + Vector2(3.0, height - 3.0), -1, 1, 3, Color(VineStyle.LEAF, fade), Color(VineStyle.LEAF_LIGHT, fade))
	# the hanging name tag: a small plank on two threads, the name in gold
	var tag_w: float = PixelText.width(name_text) + 12.0
	var tag: Vector2 = origin + Vector2(14.0, -12.0 + sin(_time * 1.3) * 0.6)
	var void_level: float = VineStyle.void_amount()
	for tx: float in [tag.x + 3.0, tag.x + tag_w - 4.0]:
		draw_rect(Rect2(tx, origin.y - 3.0, 1, 4), Color(VineStyle.BARK_LIGHT, fade))
	draw_rect(Rect2(tag, Vector2(tag_w, 11.0)), Color(VineStyle.OUTLINE, fade * PAPER_ALPHA))
	draw_rect(Rect2(tag + Vector2(1, 1), Vector2(tag_w - 2.0, 9.0)), Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level), fade * PAPER_ALPHA))
	draw_rect(Rect2(tag + Vector2(1, 1), Vector2(tag_w - 2.0, 1.0)), Color(VineStyle.BARK_LIGHT, fade * PAPER_ALPHA))
	PixelText.draw(self, name_text, Vector2i(tag + Vector2(6, 3)), Color(VineStyle.WARM_GLOW, fade), Color(VineStyle.OUTLINE, fade))
	# the words, typed out letter by letter, a bud blinking where it goes on
	var shown: int = int(_typed)
	var y_text: int = int(origin.y) + 14
	for row: String in _lines:
		var part: String = row.left(shown)
		if part != "":
			PixelText.draw(self, part, Vector2i(int(origin.x) + 14, y_text), Color(UiStyle.TEXT, fade), Color(VineStyle.OUTLINE, fade))
		shown = maxi(shown - row.length() - 1, 0)
		y_text += 10
	if _phase == 2 and int(_typed) < String(_current.text).length() and int(_time * 6.0) % 2 == 0:
		draw_rect(Rect2(origin.x + width - 12.0, origin.y + height - 9.0, 2, 2), Color(UiStyle.ACCENT, fade))
	elif _phase == 2 and int(_typed) >= String(_current.text).length():
		VineStyle.glow(self, Vector2(origin.x + width - 11.0, origin.y + height - 8.0), 5.0, UiStyle.ACCENT, 0.3 * fade * (0.6 + 0.4 * sin(_time * 3.0)))

