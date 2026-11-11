class_name QuestJournalPage
extends VBoxContainer
## Reading area on the right-hand leaf. The original notice scrolls with the rest of the entry.

const INK: Color = QuestJournalArt.INK
const FAINT: Color = QuestJournalArt.FAINT
const TEAL: Color = QuestJournalArt.TEAL
const RED: Color = QuestJournalArt.RED
const SKETCHES: Dictionary = {
	"roof": [".....#.......", "....###......", "...#...##....", "..#......##..", ".###########.", "...#.....#...", "...#..##.#...", "...#..##.#...", "...#######..."],
	"wheel": ["....###.....", "..##...##...", ".#...#...#..", ".#...#...#..", "#.#######.#.", "#...##....#.", ".#...#...#..", "..##..#.#...", "....##.#...."],
}

var _kicker: Label
var _stamp: TextureRect
var _title: Label
var _scroll: ScrollContainer
var _goal: Label
var _tasks: Label
var _details: Label
var _memory: Label
var _history: Label
var _sketch: Control
var _sketch_id: String = ""
var _note: PanelContainer
var _notice: Label
var _note_color: Color = BoardNotes.FETCH_PAPER
var _note_mark: String = "fetch"
var _note_wax: Color = BoardNotes.RED
var _page_id: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	var origin: HBoxContainer = HBoxContainer.new()
	add_child(origin)
	_stamp = TextureRect.new()
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	origin.add_child(_stamp)
	_kicker = _label(origin, FAINT)
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = _label(self, INK, 2)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_scroll.add_child(body)
	_goal = _label(body, INK)
	_tasks = _label(body, INK)
	_details = _label(body, FAINT)
	_memory = _label(body, TEAL)
	var margin: HBoxContainer = HBoxContainer.new()
	body.add_child(margin)
	_history = _label(margin, TEAL)
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sketch = Control.new()
	_sketch.custom_minimum_size = Vector2(17, 12)
	_sketch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sketch.draw.connect(_draw_sketch)
	margin.add_child(_sketch)

	_note = PanelContainer.new()
	_note.add_theme_stylebox_override("panel", QuestJournalSkin.paper_inset())
	_note.draw.connect(_draw_notice)
	body.add_child(_note)
	_notice = _label(_note, INK)


func _label(parent: Control, tone: Color, scale_px: int = 1) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", PixelText.HEIGHT * scale_px)
	label.add_theme_constant_override("line_spacing", 4)
	label.add_theme_color_override("font_color", tone)
	parent.add_child(label)
	return label


func show_entry(row: Dictionary, archived: bool, status: String) -> void:
	var id: String = String(row.get("id", ""))
	if id != _page_id:
		_scroll.scroll_vertical = 0
	_page_id = id
	var board: bool = String(row.get("source", "")) == "board"
	var ready: bool = bool(row.get("ready", false))
	var closed: String = String(row.get("status", ""))
	var giver: String = String(row.get("giver_name", row.get("giver", "")))
	var hunt: bool = String(row.get("kind", "")) == BoardRules.KILL
	_note_mark = "kill" if hunt else "fetch"
	_stamp.texture = QuestJournalSkin.icon(_note_mark if board else "story", TEAL if ready else FAINT)
	(_kicker.get_parent() as Control).visible = not row.is_empty()
	var source: String = giver.to_upper() if board else "HAUPTGESCHICHTE"
	if row.is_empty():
		source = ""
	elif archived or ready:
		source += "   /   " + status.to_upper()
	_kicker.add_theme_color_override("font_color", TEAL if ready or closed == "finished" else FAINT)
	_set_line(_kicker, source)
	_set_line(_title, String(row.get("title", "")))

	var goal: String = String(row.get("text", "")) if not archived else ""
	if row.is_empty():
		goal = "Das Archiv ist noch leer." if archived else "Keine offenen Einträge in dieser Ansicht."
	elif board and not archived and not ready:
		match String(row.kind):
			BoardRules.FETCH: goal = "Sammle die Lieferung für %s." % giver
			BoardRules.KILL: goal = "Erfülle den Jagdauftrag von %s." % giver
	_set_line(_goal, goal)

	var tasks: PackedStringArray = []
	for task: Dictionary in row.get("tasks", []) as Array:
		var counter: String = "   %d/%d" % [int(task.have), int(task.need)] if bool(task.counter) else ""
		tasks.append(("%s  " % ("+" if bool(task.done) else "-")) + String(task.text) + counter)
	_set_line(_tasks, "\n".join(tasks))

	var details: PackedStringArray = []
	var deadline: String = TrackedQuests.deadline_text(row) if not archived else ""
	if deadline != "":
		details.append(deadline)
	_details.add_theme_color_override("font_color", RED if bool(row.get("urgent", false)) or int(row.get("days_left", -1)) == 1 else FAINT)
	if String(row.get("window", "")) == "night":
		details.append("Fortschritt zählt nur nachts.")
	if not board and not archived and int(row.get("steps", 0)) > 1:
		details.append("Etappe %d von %d" % [int(row.step) + 1, int(row.steps)])
	if board and archived:
		var day: String = "Tag %d  ·  " % (int(row.day) + 1) if int(row.day) >= 0 else ""
		details.append("%sFortschritt %d/%d" % [day, int(row.have), int(row.need)])
	elif board:
		details.append("%d Kupfer  ·  %d EP  ·  %d Vertrauen" % (row.reward as Array))
		if String(row.get("reward_item", "")) != "":
			details.append("+ " + String(row.reward_item))
	_set_line(_details, "\n".join(details))

	var notes: Dictionary = DataRegistry.get_entry("quest_journal", id.trim_prefix("story:")) if not board else {}
	var observation: String = String(notes.get("finished", "")) if archived else String((notes.get("steps", {}) as Dictionary).get(String(row.get("step_id", "")), ""))
	_set_line(_memory, "„%s“" % observation if observation != "" else "")
	var history: PackedStringArray = []
	for memory: String in row.get("memories", []) as Array:
		history.append("„%s“" % memory)
	_set_line(_history, "ZULETZT NOTIERT\n" + "\n\n".join(history) if not history.is_empty() else "")
	_sketch_id = String(row.get("sketch", ""))
	_sketch.visible = SKETCHES.has(_sketch_id)
	(_history.get_parent() as Control).visible = _history.visible or _sketch.visible
	_sketch.queue_redraw()

	var notice: String = String(row.get("notice", row.get("text", ""))) if board else ""
	_note_color = BoardNotes.KILL_PAPER if hunt else BoardNotes.FETCH_PAPER
	_note_wax = BoardNotes.WAX.darkened(0.18) if hunt else Color("4e7161")
	_set_line(_notice, notice)
	_note.visible = notice != ""
	_note.queue_redraw()


func _set_line(label: Label, contents: String) -> void:
	var line: String = contents.replace("ß", "SS").replace("…", "...").replace("–", "-").to_upper()
	if label.text != line:
		label.text = line
	label.visible = contents != ""


func _draw_sketch() -> void:
	var rows: Array = SKETCHES.get(_sketch_id, [])
	for y: int in rows.size():
		var line: String = rows[y]
		for x: int in line.length():
			if line[x] == "#":
				_sketch.draw_rect(Rect2(x + 1, y + 2, 1, 1), TEAL)


func _draw_notice() -> void:
	QuestJournalSkin.draw_pinned_paper(_note, _note_color, _note_wax, _note_mark)
