class_name DialogueBox
extends Control
## Dialogue with a generated, animated Ellie illustration beside the text.
## Text is paginated to fit the viewport. Solo play pauses and restores prior state.

signal finished

const TICK: AudioStream = preload("res://assets/audio/intro/tick.wav")
const TYPE_RATE: float = 38.0
const OPEN_SECONDS: float = 0.5
const CLOSE_SECONDS: float = 0.3
const TEXT_SCALE: int = 2
const PAD: int = 16
const MAX_ROWS: int = 3

var _vignette: GradientTexture2D
const NPC_PORTRAITS: Dictionary = { ## speakers other than Ellie: name plate text -> portrait
	"???": preload("res://assets/ui/portrait_adventurer_v2.png"),
	"RITTER": preload("res://assets/ui/portrait_adventurer_v2.png"),
}
## Speakers whose portrait is made apart (docs/town.md, docs/characters/): the picture is picked up as soon as the file exists (103 x 153, docs/dialogue_art.md); until then
## nobody is shown beside their lines. "FREMDER" is the stranger who becomes Gustav: a silhouette until the story names him (`known_flag`).
const LATE_PORTRAITS: Dictionary = {
	"GUSTAV": "res://assets/ui/portrait_gustav.png",
	"FREMDER": "res://assets/ui/portrait_gustav.png",
	"MAREN": "res://assets/ui/portrait_maren.png",
}
const UNKNOWN_SHADER: Shader = preload("res://assets/shaders/unknown_portrait.gdshader")
var _npc: TextureRect
var _npc_ink: ShaderMaterial
var _quests: QuestComponent
var _portrait: ElliePortrait
var _hidden_parts: Array[Dictionary] = []
var _menu_before: bool = false
var _continue_key: String = "E"
var _lines: Array = []
var _page: int = 0
var _typed: float = 0.0
var _open: float = 0.0
var _closing: bool = false
var _active: bool = false
var _time: float = 0.0
var _armed_at: float = 0.0
var _was_paused: bool = false
var _blocking_before: bool = false
var _tick: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vignette = VineStyle.make_vignette()
	for texture: Texture2D in NPC_PORTRAITS.values():
		assert(DialogueArt.valid_portrait(texture), "Dialogue portraits must use the shared 103x153 art grid")
	_portrait = ElliePortrait.new()
	add_child(_portrait)
	_npc = TextureRect.new()
	_npc_ink = ShaderMaterial.new()
	_npc_ink.shader = UNKNOWN_SHADER
	_npc.material = _npc_ink
	_npc.stretch_mode = TextureRect.STRETCH_SCALE
	_npc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_npc.visible = false
	add_child(_npc)
	add_to_group("dialogue")
	_tick = AudioStreamPlayer.new()
	_tick.stream = TICK
	_tick.volume_db = -16.0
	add_child(_tick)


## The dialogue box of a player's HUD (the HUD is a child of the player).
static func find(player: Node) -> DialogueBox:
	for child: Node in player.get_children():
		var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
		if box != null:
			return box
	return null


func bind(quests: QuestComponent) -> void:
	_quests = quests
	quests.story_event.connect(func(event_name: String) -> void:
		if event_name.begins_with("dialogue:"):
			start(event_name.trim_prefix("dialogue:")))


func is_active() -> bool:
	return _active


## Dialogue metadata can conceal any new speaker. A persisted quest identity flag
## reveals both portrait and name, including when a conversation is replayed later.
func _speaker_unknown(line: Dictionary) -> bool:
	var known_flag: String = String(line.get("known_flag", ""))
	if not known_flag.is_empty():
		return _quests == null or not _quests.has_flag(known_flag)
	return bool(line.get("unknown", String(line.get("speaker", "ELLIE")) == "???"))


func start(id: String) -> void:
	var entry: Dictionary = DataRegistry.get_entry("dialogue", id)
	if entry.is_empty() or _active:
		return
	_lines = _paginate(entry.get("lines", []) as Array)
	if _lines.is_empty():
		return
	_time = 0.0
	_menu_before = InputManager.menu_open
	InputManager.menu_open = true
	_continue_key = VineStyle.key_name("interact", "E")
	# Quiet the surrounding HUD while this conversation has focus.
	_hidden_parts.clear()
	if get_parent() is CanvasLayer:
		for child: Node in get_parent().get_children():
			if child != self and child is Control and not child is PauseMenu and not child is WoundBorder: ## the low-health border stays
				_hidden_parts.append({"node": child, "visible": (child as Control).visible, "processing": child.is_processing()})
				child.set_process(false)
				(child as CanvasItem).hide()
	_page = 0
	_typed = 0.0
	_open = 0.0
	_closing = false
	_active = true
	_armed_at = 0.6
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_blocking_before = InputManager.ui_blocking
	InputManager.ui_blocking = true
	_was_paused = get_tree().paused
	if multiplayer.get_peers().is_empty():
		get_tree().paused = true ## alone: the world waits while she speaks


func _input(event: InputEvent) -> void:
	if not _active or _closing:
		return
	var pressed: bool = event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if event.is_echo() or _armed_at > 0.0:
		return
	var full: int = String((_lines[_page] as Dictionary).text).length()
	if _typed < float(full):
		_typed = float(full)
	elif _page + 1 < _lines.size():
		_page += 1
		_typed = 0.0
		_armed_at = 0.12
	else:
		_closing = true


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	_armed_at = maxf(_armed_at - delta, 0.0)
	if _closing:
		_open = maxf(_open - delta / CLOSE_SECONDS, 0.0)
		if _open <= 0.0:
			_end()
			return
	else:
		_open = minf(_open + delta / OPEN_SECONDS, 1.0)
		if _open >= 0.9:
			var before: int = int(_typed)
			_typed = minf(_typed + TYPE_RATE * delta, float(String((_lines[_page] as Dictionary).text).length()))
			if int(_typed) / 2 != before / 2 and int(_typed) > before:
				_tick.pitch_scale = randf_range(0.9, 1.15)
				_tick.play()
	_portrait.hurt = String((_lines[_page] as Dictionary).get("mood", "")) in ["hurt", "reflective_hurt"]
	_portrait.speaking = _open >= 0.9 and _typed < float(String((_lines[_page] as Dictionary).text).length()) and not _closing
	_portrait.reflective = String((_lines[_page] as Dictionary).get("mood", "")) == "reflective_hurt"
	var spoken: String = String((_lines[_page] as Dictionary).text)
	_portrait.talk_char = spoken.substr(int(_typed) - 1, 1) if int(_typed) >= 1 and int(_typed) <= spoken.length() else ""
	_portrait.opacity = _ease(_open)
	_portrait.position = Vector2(roundf(4.0 - (1.0 - _ease(_open)) * 160.0), roundf(size.y - DialogueArt.DISPLAY_SIZE.y + DialogueArt.BOTTOM_OVERHANG))
	_portrait.size = DialogueArt.DISPLAY_SIZE
	_portrait.advance(delta)
	var speaker: String = String((_lines[_page] as Dictionary).get("speaker", "ELLIE")).to_upper()
	var art: Texture2D = _portrait_for(speaker)
	_npc.visible = art != null
	_portrait.visible = not _npc.visible and not LATE_PORTRAITS.has(speaker)
	if _npc.visible:
		_npc.texture = art
		_npc_ink.set_shader_parameter("unknown", _speaker_unknown(_lines[_page] as Dictionary))
		_npc.modulate.a = _ease(_open)
		_npc.size = DialogueArt.DISPLAY_SIZE
		_npc.position = _portrait.position + Vector2(0, roundf(sin(_time * 1.6) * 0.6) * DialogueArt.PIXEL_SCALE)
	queue_redraw()


func _portrait_for(speaker: String) -> Texture2D:
	if NPC_PORTRAITS.has(speaker):
		return NPC_PORTRAITS[speaker] as Texture2D
	if LATE_PORTRAITS.has(speaker) and ResourceLoader.exists(String(LATE_PORTRAITS[speaker])):
		var texture: Texture2D = load(String(LATE_PORTRAITS[speaker])) as Texture2D
		return texture if DialogueArt.valid_portrait(texture) else null
	return null


func _end() -> void:
	_active = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InputManager.ui_blocking = _blocking_before
	InputManager.menu_open = _menu_before
	for state: Dictionary in _hidden_parts:
		if is_instance_valid(state.node):
			(state.node as CanvasItem).visible = bool(state.visible)
			(state.node as Node).set_process(bool(state.processing))
	_hidden_parts.clear()
	get_tree().paused = _was_paused
	finished.emit()


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _panel_rect() -> Rect2:
	return Rect2(198, size.y - 122, maxf(240.0, size.x - 214.0), 106)

func _draw() -> void:
	if not _active:
		return
	var e: float = _ease(_open)
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, e * 0.65))
	_draw_panel(_lines[_page] as Dictionary, e)

func _draw_panel(line: Dictionary, e: float) -> void:
	var rect: Rect2 = _panel_rect()
	rect.position.y += roundf((1.0 - e) * 28.0)
	var left: float = rect.position.x
	var right: float = rect.end.x
	var top: float = rect.position.y
	var void_level: float = VineStyle.void_amount()
	var reach: float = clampf(_open / 0.72, 0, 1)
	var branch_y: Callable = func(x: float) -> float: return top - 24 + sin((x - left) * 0.021) * 3
	VineStyle.branch(self, size.x, left + 12, branch_y, 5, void_level, 30, _time, reach)
	VineStyle.foliage(self, size.x, left + 12, branch_y, 17, 270, void_level, 30, _time, reach)
	VineStyle.paper(self, rect, e, void_level, 41)
	var foot_y: Callable = func(x: float) -> float: return rect.end.y + 1 + sin(x * 0.06) * 2
	VineStyle.branch(self, size.x, right - 98, foot_y, 4, void_level, 8, _time, reach)
	VineStyle.foliage(self, size.x, right - 98, foot_y, 6, 342, void_level, 8, _time, reach)
	for side: int in [-1, 1]:
		var x: float = left + 3 if side < 0 else right - 3
		var leaf: Color = VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level)
		var light: Color = VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level)
		VineStyle.leaf(self, Vector2(x, top + 5), side, -1, 3, leaf, light)
		VineStyle.leaf(self, Vector2(x, rect.end.y - 5), side, 1, 3, leaf, light)
	if e < 0.95:
		return
	var name_text: String = String(line.get("speaker", "ELLIE")).to_upper()
	if _speaker_unknown(line):
		name_text = "???"
	else:
		name_text = String(line.get("known_name",name_text)).to_upper()
	var title_text: String = String(line.get("title", "")).to_upper()
	var name_width: float = maxf(72, PixelText.width(name_text) * 2 + 24)
	var name_rect: Rect2 = Rect2(left + 20, top - 18, name_width, 25)
	for offset: int in [8, int(name_width) - 8]:
		var x: float = name_rect.position.x + offset
		for y: int in range(int(branch_y.call(x)), int(name_rect.position.y)):
			draw_rect(Rect2(x, y, 1, 1), VineStyle.BARK_LIGHT if y % 2 == 0 else VineStyle.BARK)
	_wood_plate(name_rect, VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level))
	_text(name_text, name_rect.position + Vector2(12, 4), VineStyle.WARM_GLOW, 2)
	if title_text != "":
		_text(title_text, Vector2(name_rect.end.x + 10, top - 12), UiStyle.ACCENT)
	var rows: PackedStringArray = String(line.text).split("\n")
	var shown: int = int(_typed)
	var drawn: int = 0
	for i: int in rows.size():
		var part: String = rows[i].left(maxi(shown - drawn, 0))
		drawn += rows[i].length() + 1
		_text(part, Vector2(left + PAD + 4, top + 18 + i * 20), UiStyle.TEXT, TEXT_SCALE)
	# Page pips stay separate from the reading area and progression prompt.
	for i: int in _lines.size():
		if i >= 12:
			break
		draw_rect(Rect2(left + 22 + i * 7, rect.end.y - 13, 3, 2), UiStyle.ACCENT if i == _page else Color("514561"))
	if shown >= String(line.text).length() and not _closing:
		var key_width: int = VineStyle.cap_width(_continue_key)
		var key_rect: Rect2 = Rect2(right - key_width - 15, rect.end.y - 22, key_width, VineStyle.CAP_HEIGHT)
		VineStyle.key_cap(self, key_rect.position, _continue_key, 1.0, 0.35 + 0.25 * sin(_time * 3.0), void_level)
		var label: String = "WEITER" if _page + 1 < _lines.size() else "ZURÜCK"
		_text(label, Vector2(key_rect.position.x - PixelText.width(label) - 10, key_rect.position.y + 2), Color(UiStyle.TEXT, 0.75 + sin(_time * 3) * 0.2))

func _wood_plate(rect: Rect2, color: Color) -> void:
	draw_rect(rect, VineStyle.OUTLINE)
	draw_rect(rect.grow(-1), color)
	draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2, 1)), VineStyle.BARK_LIGHT)

func _text(text: String, at: Vector2, color: Color, scale_factor: int = 1) -> void:
	draw_set_transform(at.round(), 0, Vector2.ONE * scale_factor)
	PixelText.draw(self, text, Vector2i.ZERO, color, VineStyle.OUTLINE)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _wrap(text: String, limit: int) -> PackedStringArray:
	var rows: PackedStringArray = []
	for paragraph: String in text.split("\n"):
		var row: String = ""
		for word: String in paragraph.split(" ", false):
			if row != "" and row.length() + 1 + word.length() > limit:
				rows.append(row)
				row = ""
			while word.length() > limit:
				rows.append(word.left(limit))
				word = word.substr(limit)
			row = word if row == "" else row + " " + word
		if row != "":
			rows.append(row)
	return rows

func _paginate(lines: Array) -> Array:
	var pages: Array = []
	var limit: int = maxi(8, int((_panel_rect().size.x - PAD * 2 - 8) / (PixelText.ADVANCE * TEXT_SCALE)))
	for raw: Variant in lines:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw as Dictionary
		var text: String = String(entry.get("text", "")).to_upper().replace("ß", "SS")
		var rows: PackedStringArray = _wrap(text, limit)
		for first: int in range(0, rows.size(), MAX_ROWS):
			var page: Dictionary = entry.duplicate(true)
			page["text"] = "\n".join(rows.slice(first, mini(first + MAX_ROWS, rows.size())))
			pages.append(page)
	return pages
