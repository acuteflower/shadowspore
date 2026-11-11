class_name QuestJournal
extends Control

const ART = preload("res://src/ui/quest_journal_art.gd")
const PAGE = preload("res://src/ui/quest_journal_page.gd")
const CREAK: AudioStream = preload("res://assets/audio/fishing/creak.wav")
const RUSTLE: AudioStream = preload("res://assets/audio/board/rustle_a.wav")
const CLOSE_PAPER: AudioStream = preload("res://assets/audio/board/rustle_b.wav")
const TURN_PAPER: AudioStream = preload("res://assets/audio/board/flip.wav")
const PIN: AudioStream = preload("res://assets/audio/board/tack.wav")
const OPEN_SECONDS: float = 0.26
const CLOSE_SECONDS: float = 0.18
const TURN_SECONDS: float = 0.24

var _player: Node
var _tracked: TrackedQuests
var _health: HealthComponent
var _owns_input: bool = false
var _paused_here: bool = false
var _archive: bool = false
var _selected_id: String = ""
var _rows: Array[Dictionary] = []
var _pending: Dictionary = {}
var _filter: int = 0
var _closing: bool = false
var _still: bool = false
var _ribbon_goal: float = 0.0
var _read_key: String = ""
var _map: MapWindow
var _layer: CanvasLayer

var _veil: ColorRect
var _art: QuestJournalArt
var _paper: Control
var _tabs: Array[Button] = []
var _filters: HBoxContainer
var _filter_buttons: Array[Button] = []
var _list: ItemList
var _page: QuestJournalPage
var _actions: HBoxContainer
var _focus_button: Button
var _map_button: Button
var _abandon_button: Button
var _confirm: PanelContainer
var _confirm_text: Label
var _cancel_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layer = CanvasLayer.new()
	_layer.layer = 24 ## above ambient town titles, below scripted scenes and death
	_layer.hide()
	add_child(_layer)
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vignette: TextureRect = TextureRect.new()
	vignette.texture = VineStyle.make_vignette()
	vignette.modulate = Color("140e21", 0.65)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_art = ART.new()
	_place(_layer, _art, Rect2(Vector2.ZERO, ART.EXTENT))
	_paper = Control.new()
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var lettering: Theme = Theme.new()
	lettering.default_font = PixelText.bitmap_font()
	lettering.default_font_size = PixelText.HEIGHT
	lettering.set_stylebox("scroll", "VScrollBar", QuestJournalSkin.scroll_track(false))
	for style: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		lettering.set_stylebox(style, "VScrollBar", QuestJournalSkin.scroll_track(true))
	_paper.theme = lettering
	_place(_layer, _paper, Rect2(Vector2.ZERO, ART.EXTENT))
	resized.connect(_center_spread)
	_center_spread()

	for i: int in 2:
		var tab: Button = _button(_paper, ["Offen", "Archiv"][i], _switch_tab.bind(i), "register", ["story", "archive"][i])
		tab.toggle_mode = true
		_place(_paper, tab, Rect2(68 + i * 68, 29, 65, 21))
		_tabs.append(tab)
	var back: Button = _button(_paper, "J  Schließen", _request_close, "close", "close")
	_place(_paper, back, Rect2(493, 28, 81, 19))

	_filters = HBoxContainer.new()
	_filters.add_theme_constant_override("separation", 4)
	_place(_paper, _filters, Rect2(68, 94, 222, 17))
	for i: int in 3:
		var filter: Button = _button(_filters, ["Alle", "Geschichte", "Aufträge"][i], _set_filter.bind(i), "filter", ["", "story", "fetch"][i])
		filter.toggle_mode = true
		_filter_buttons.append(filter)
	_list = ItemList.new()
	_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for style: String in ["selected", "selected_focus", "hovered"]:
		_list.add_theme_stylebox_override(style, QuestJournalSkin.list_item(style))
	_list.add_theme_constant_override("icon_margin", 6)
	_list.add_theme_constant_override("line_separation", 4)
	_list.add_theme_constant_override("v_separation", 9)
	_list.add_theme_color_override("font_color", ART.INK)
	_list.add_theme_color_override("font_selected_color", ART.INK)
	_list.add_theme_color_override("font_hovered_color", ART.INK)
	_list.item_selected.connect(_select)
	_place(_paper, _list, Rect2(68, 119, 222, 162))
	_page = PAGE.new()
	_place(_paper, _page, Rect2(348, 65, 225, 198))
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	_place(_paper, _actions, Rect2(348, 274, 225, 18))
	_focus_button = _button(_actions, "Fokussieren", _toggle_focus, "focus", "focus")
	_map_button = _button(_actions, "Karte", _show_on_map, "map", "map")
	_map_button.tooltip_text = "Auf der Karte zeigen"
	_abandon_button = _button(_actions, "Aufgeben", _ask_abandon, "abandon", "abandoned")
	_abandon_button.tooltip_text = "Auftrag aufgeben"
	_confirm = PanelContainer.new()
	_confirm.hide()
	_confirm.add_theme_stylebox_override("panel", QuestJournalSkin.paper_inset())
	_confirm.draw.connect(_draw_confirmation)
	_place(_paper, _confirm, Rect2(345, 113, 231, 86))
	var letter: VBoxContainer = VBoxContainer.new()
	letter.add_theme_constant_override("separation", 9)
	_confirm.add_child(letter)
	_confirm_text = Label.new()
	_confirm_text.add_theme_color_override("font_color", ART.INK)
	_confirm_text.add_theme_constant_override("line_spacing", 4)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	letter.add_child(_confirm_text)
	var choice: HBoxContainer = HBoxContainer.new()
	letter.add_child(choice)
	_cancel_button = _button(choice, "Behalten", _cancel_abandon, "focus", "ready")
	_button(choice, "Aufgeben", _abandon, "abandon", "abandoned")


func _draw_confirmation() -> void:
	QuestJournalSkin.draw_pinned_paper(_confirm, BoardNotes.KILL_PAPER, BoardNotes.RED, "abandoned")


func _center_spread() -> void:
	_art.position = ((size - ART.EXTENT) / 2.0).floor()
	_paper.position = _art.position


func _place(parent: Node, child: Control, bounds: Rect2) -> void:
	if child.get_parent() == null:
		parent.add_child(child)
	child.position = bounds.position
	child.size = bounds.size


func _button(parent: Control, title: String, action: Callable, role: String, glyph: String = "") -> Button:
	var button: Button = Button.new()
	button.text = title.to_upper()
	QuestJournalSkin.action(button, role, glyph)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Node avoids the player scene's dependency on the HUD.
func bind(player: Node) -> void:
	_player = player
	_tracked = player.get("tracked") as TrackedQuests
	_health = player.get("health") as HealthComponent
	if _tracked != null:
		_tracked.changed.connect(_refresh)
	_health.changed.connect(_on_health)
	_map = get_parent().get_node_or_null("MapWindow") as MapWindow
	if _map != null:
		_map.quest_preview_closed.connect(_return_from_map)


func open() -> void:
	if _owns_input or _tracked == null or not _can_open():
		return
	_owns_input = true
	_closing = false
	_still = bool(GameSettings.get_value("journal_still"))
	_tracked.journal_opened = true
	InputManager.journal_open = true
	InputManager.ui_blocking = true
	_paused_here = multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	if _paused_here:
		get_tree().paused = true
	_archive = _tracked.journal_archive
	_selected_id = _tracked.journal_page
	_art.opening = 1.0 if _still else 0.0
	_art.turn = 1.0
	_art.ink = 1.0
	_art.seal_flash = 0.0
	show()
	_layer.show()
	_refresh()
	_art.ribbon = _ribbon_goal
	_render_motion()
	Sfx.ui_stream(self, CREAK, -27.0, 0.04)
	Sfx.ui_stream(self, RUSTLE, -21.0)
	if _list.item_count > 0:
		_list.ensure_current_is_visible()
		_list.grab_focus()
	else:
		_tabs[int(_archive)].grab_focus()


func _can_open() -> bool:
	if not is_instance_valid(_player) or _health.current <= 0.0 or InputManager.ui_blocking or InputManager.menu_open or InputManager.build_open or InputManager.freecam_open or get_tree().paused:
		return false
	var hud: CanvasLayer = get_parent() as CanvasLayer
	if hud == null or not hud.visible or _story_busy():
		return false
	return not get_tree().get_first_node_in_group("world") is WorldLevel or (_tracked.quests != null and _tracked.quests.has_flag("hud_unlocked"))


func _story_busy() -> bool:
	return _player.get("intro") != null or bool(_player.get("story_lock")) or bool(_player.get("stumbling"))


func close() -> void:
	if not _owns_input:
		return
	_owns_input = false
	_closing = false
	_pending.clear()
	_confirm.hide()
	hide()
	_layer.hide()
	InputManager.journal_open = false
	InputManager.ui_blocking = InputManager.menu_open or InputManager.map_open or (is_instance_valid(_health) and _health.current <= 0.0)
	if _paused_here:
		get_tree().paused = false
	_paused_here = false


func interrupt() -> void:
	close()
	if is_instance_valid(_map):
		_map.cancel_quest_preview()


func _request_close() -> void:
	if _closing:
		return
	Sfx.ui_stream(self, CLOSE_PAPER, -23.0)
	if _still:
		close()
	else:
		_closing = true


func _exit_tree() -> void:
	close()


func _on_health(current: float, _maximum: float) -> void:
	if current <= 0.0:
		interrupt()


func _process(delta: float) -> void:
	if not _owns_input:
		return
	if not is_instance_valid(_player) or _story_busy() or not is_visible_in_tree():
		close()
		return
	if _art.opening == 1.0 and _art.turn == 1.0 and _art.ink == 1.0 and _art.ribbon == _ribbon_goal and _art.seal_flash <= 0.0 and not _closing:
		return
	_art.opening = move_toward(_art.opening, 0.0 if _closing else 1.0, delta / (CLOSE_SECONDS if _closing else OPEN_SECONDS))
	_art.turn = move_toward(_art.turn, 1.0, delta / TURN_SECONDS)
	_art.ink = move_toward(_art.ink, 1.0, delta / 0.17)
	_art.ribbon = move_toward(_art.ribbon, _ribbon_goal, delta / 0.25)
	_art.seal_flash = move_toward(_art.seal_flash, 0.0, delta / 0.46)
	if _closing and _art.opening <= 0.0:
		close()
	else:
		_render_motion()


func _render_motion() -> void:
	var shown: float = smoothstep(0.0, 0.83, _art.opening)
	_art.night = VineStyle.void_amount()
	_veil.color = Color(Color("1b1325").lerp(Color("10091b"), _art.night), 0.64 * shown)
	_paper.modulate.a = smoothstep(0.63, 0.98, _art.opening)
	_page.modulate.a = lerpf(0.72, 1.0, smoothstep(0.0, 1.0, _art.ink))
	_art.refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_journal"):
		if _owns_input:
			if _closing:
				_closing = false
			else:
				_request_close()
		else:
			open()
		if _owns_input or not InputManager.ui_blocking:
			get_viewport().set_input_as_handled()
	elif _owns_input and event.is_action_pressed("ui_cancel"):
		if _pending.is_empty():
			_request_close()
		else:
			_cancel_abandon()
		get_viewport().set_input_as_handled()
	elif _owns_input:
		var key: InputEventKey = event as InputEventKey
		var pad: InputEventJoypadButton = event as InputEventJoypadButton
		if key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_Q, KEY_E]:
			_switch_tab(int(key.physical_keycode == KEY_E))
			get_viewport().set_input_as_handled()
		elif pad != null and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			_switch_tab(int(pad.button_index == JOY_BUTTON_RIGHT_SHOULDER))
			get_viewport().set_input_as_handled()


func _switch_tab(tab: int) -> void:
	if _archive == (tab == 1):
		_tabs[tab].set_pressed_no_signal(true)
		return
	_archive = tab == 1
	_selected_id = ""
	_pending.clear()
	_art.turn = 1.0 if _still else 0.0
	_art.toward_archive = _archive
	Sfx.ui_stream(self, TURN_PAPER, -19.0)
	_refresh()


func _set_filter(index: int) -> void:
	_filter = index
	_refresh()


func _refresh() -> void:
	if not _owns_input:
		return
	var focus_id: String = String(_tracked.focused().get("id", ""))
	_tabs[0].set_pressed_no_signal(not _archive)
	_tabs[1].set_pressed_no_signal(_archive)
	_filters.visible = not _archive
	_list.position.y = 98.0 if _archive else 119.0
	for i: int in _filter_buttons.size():
		_filter_buttons[i].set_pressed_no_signal(i == _filter)
	_rows = _tracked.archive_entries() if _archive else _tracked.entries()
	if not _archive:
		if _filter != 0:
			var source: String = "story" if _filter == 1 else "board"
			_rows = _rows.filter(func(entry: Dictionary) -> bool: return String(entry.source) == source)
		_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _order(a, focus_id) < _order(b, focus_id))
	_art.show_fern = not _archive and _rows.size() <= 5
	_list.size.y = 183.0 if _archive else (100.0 if _art.show_fern else 162.0)
	var index: int = -1
	var focused_row: int = -1
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		if String(row.id) == _selected_id:
			index = i
		if String(row.id) == focus_id:
			focused_row = i
		var title: String = String(row.title)
		if _archive:
			title = "%s · %s" % [title, _status(row)]
		title = title.replace("ß", "SS").to_upper()
		if i < _list.item_count:
			_list.set_item_text(i, title)
		else:
			_list.add_item(title)
		_list.set_item_icon(i, _entry_mark(row, i == focused_row))
		_list.set_item_custom_fg_color(i, ART.TEAL if bool(row.get("ready", false)) else ART.INK)
	while _list.item_count > _rows.size():
		_list.remove_item(_list.item_count - 1)
	if index < 0 and not _rows.is_empty():
		index = focused_row if focused_row >= 0 else 0
	if index >= 0:
		_list.select(index)
		_select(index)
	else:
		_selected_id = ""
		_show_entry({})
	_tracked.journal_page = _selected_id
	_tracked.journal_archive = _archive
	_art.refresh()


func _entry_mark(row: Dictionary, in_focus: bool) -> Texture2D:
	var kind: String = String(row.get("kind", "story"))
	var ready: bool = bool(row.get("ready", false))
	var closed: String = String(row.get("status", ""))
	if in_focus:
		return QuestJournalSkin.icon("focus", Color("a67c41"))
	if ready or closed == "finished":
		return QuestJournalSkin.icon("ready", ART.TEAL)
	if closed == "expired" or closed == "abandoned":
		return QuestJournalSkin.icon(closed, ART.RED)
	return QuestJournalSkin.icon(kind, ART.RED if kind == "kill" else ART.FAINT)


func _order(row: Dictionary, focus_id: String) -> int:
	if String(row.id) == focus_id:
		return -2
	if bool(row.get("ready", false)):
		return -1
	if bool(row.get("urgent", false)):
		return 0
	return int(row.get("due", 1000000))


func _select(index: int) -> void:
	var row: Dictionary = _rows[index]
	if _selected_id != String(row.id):
		_pending.clear()
	_selected_id = String(row.id)
	_tracked.journal_page = _selected_id
	_show_entry(row)


func _status(row: Dictionary) -> String:
	match String(row.get("status", "")):
		"finished": return "Abgeschlossen"
		"expired": return "Abgelaufen"
		"abandoned": return "Aufgegeben"
	return "Bereit zur Abgabe" if bool(row.get("ready", false)) else "Offen"


func _show_entry(row: Dictionary) -> void:
	_confirm.visible = not _pending.is_empty()
	_actions.visible = not _archive and not row.is_empty() and not _confirm.visible
	_abandon_button.visible = String(row.get("source", "")) == "board"
	_map_button.visible = _map != null and MapWindow.quest_location(row) != Vector2.INF
	var on_focus: bool = not _archive and _selected_id != "" and _selected_id == String(_tracked.focused().get("id", ""))
	_focus_button.text = "FOKUS LÖSEN" if on_focus else "FOKUSSIEREN"
	_ribbon_goal = 1.0 if on_focus else 0.0
	var key: String = "%s/%s" % [String(row.get("id", "")), String(row.get("step_id", ""))]
	if key != _read_key:
		_read_key = key
		_art.ink = 1.0 if _still else 0.0
	_page.visible = not _confirm.visible
	_page.show_entry(row, _archive, _status(row))
	if _still:
		_art.ribbon = _ribbon_goal
		_render_motion()


func _toggle_focus() -> void:
	var id: String = String(_tracked.focused().get("id", ""))
	_tracked.focus("" if id == _selected_id else _selected_id)
	if not _still and id != _selected_id:
		_art.seal_flash = 1.0
	Sfx.ui_stream(self, PIN, -25.0)


func _show_on_map() -> void:
	if _map == null or _archive:
		return
	var row: Dictionary = _tracked.active_entry(_selected_id)
	_map.open_quest_preview(row)


func _return_from_map() -> void:
	open.call_deferred()


func _ask_abandon() -> void:
	for row: Dictionary in _rows:
		if String(row.id) == _selected_id and not _archive and String(row.source) == "board":
			_pending = {"id": int(row.oid), "attempt": int(row.attempt)}
			_confirm_text.text = "AUFTRAG AUFGEBEN? GESAMMELTE GEGENSTÄNDE BLEIBEN BEI DIR. DER BISHERIGE AUFTRAGSFORTSCHRITT ENDET."
			_show_entry(row)
			_cancel_button.grab_focus()
			return


func _cancel_abandon() -> void:
	_pending.clear()
	_refresh()
	if _abandon_button.is_visible_in_tree():
		_abandon_button.grab_focus()


func _abandon() -> void:
	var board: BoardManager = _tracked.board()
	if board != null and not _pending.is_empty():
		var id: int = int(_pending.id)
		var attempt: int = int(_pending.attempt)
		_pending.clear()
		board.request_abandon(id, attempt)
	_refresh()
	_list.grab_focus()
