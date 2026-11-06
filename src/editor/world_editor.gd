class_name WorldEditor
extends CanvasLayer
## Paused authoring workspace. Enter only through Settings > Entwickler.
const TOOLS: Array[String] = ["Auswählen / verschieben", "Objekt platzieren", "Objekt löschen", "Boden malen", "Höhe formen", "Rampe einbauen", "Treppe einbauen", "Terrain zurücksetzen"]
const ACCENT: Color = Color("7fe3da")
var world: WorldLevel
var camera: Camera2D
var _previous_camera: Camera2D
var _root: Control
var _overlay: Control
var _panel: PanelContainer
var _status: Label
var _title: Label
var _selection: Label
var _tool: OptionButton
var _catalog: OptionButton
var _variant: SpinBox
var _size: SpinBox
var _scale: SpinBox
var _flip: CheckBox
var _ground_kind: OptionButton
var _biome: OptionButton
var _height: SpinBox
var _style: OptionButton
var _grid: CheckBox
var _dialog: ConfirmationDialog
var _selected: Vector2i = Vector2i(-1, -1)
var _drag: WorldProp
var _drag_offset: Vector2
var _drag_origin: Vector2
var _panning: bool = false
var _stroke: bool = false
var _pending: Dictionary = {}
var _last_cell: Vector2i = Vector2i(-1, -1)
var _history: Array[Dictionary] = []
var _future: Array[Dictionary] = []
var _saved: Dictionary = {}
var _kinds: Array[String] = []
var _grounds: Array[String] = []
var _biomes: Array[String] = []
var _was_paused: bool = false
var _hidden_huds: Array[CanvasLayer] = []

func start(level: WorldLevel) -> void:
	world = level
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_was_paused = get_tree().paused
	_saved = world.edits.data()
	_previous_camera = get_viewport().get_camera_2d()
	for player: Node in get_tree().get_nodes_in_group("players"):
		for child: Node in player.get_children():
			if child is CanvasLayer and (child as CanvasLayer).visible:
				_hidden_huds.append(child as CanvasLayer)
				(child as CanvasLayer).hide()
	camera = Camera2D.new()
	camera.position = _previous_camera.get_screen_center_position() if _previous_camera != null else Vector2(world._start) * 16.0
	camera.zoom = _previous_camera.zoom if _previous_camera != null else Vector2.ONE
	camera.position_smoothing_enabled = false
	world.add_child(camera)
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	camera.make_current()
	world.editor_camera = camera
	world._cliffs.process_mode = Node.PROCESS_MODE_ALWAYS
	for child: Node in world.get_children():
		if child is VoidEdge:
			child.process_mode = Node.PROCESS_MODE_ALWAYS
	InputManager.ui_blocking = true
	InputManager.menu_open = true
	get_tree().paused = true
	_build_ui()
	_note("Bereit. Wähle ein Werkzeug – deine Welt wartet.")
	world.multiplayer.peer_connected.connect(_peer_joined)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var theme: Theme = Theme.new()
	theme.default_font_size = 10
	theme.set_color("font_color", "Label", Color("e8e4f4"))
	for type_name: String in ["PanelContainer", "Button", "OptionButton"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color("201c34")
		box.border_color = Color("51456f")
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.content_margin_left = 5
		box.content_margin_right = 5
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		theme.set_stylebox("panel" if type_name == "PanelContainer" else "normal", type_name, box)
	_root.theme = theme
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	var top: PanelContainer = PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 28
	_root.add_child(top)
	var bar: HBoxContainer = HBoxContainer.new()
	top.add_child(bar)
	_title = Label.new()
	_title.text = "✦ WELTWERKSTATT"
	_title.modulate = ACCENT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	_button(bar, "↶", undo).tooltip_text = "Rückgängig · Strg/Cmd+Z"
	_button(bar, "↷", redo).tooltip_text = "Wiederholen · Strg/Cmd+Shift+Z"
	_button(bar, "Zum Spieler", _home)
	_button(bar, "Speichern", _save)
	_button(bar, "Spielen  ›", _request_close)
	_panel = PanelContainer.new()
	_panel.position = Vector2(6, 34)
	_panel.size = Vector2(156, 270)
	_root.add_child(_panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(146, 262)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)
	_label(column, "WERKZEUGE", ACCENT)
	_tool = _options(column, TOOLS)
	_tool.item_selected.connect(func(_i: int) -> void: _cancel_gesture(); _overlay.queue_redraw())
	_label(column, "OBJEKTE", ACCENT)
	_catalog = OptionButton.new()
	column.add_child(_catalog)
	for id: String in DataRegistry.table("plants"):
		var spec: Dictionary = DataRegistry.get_entry("plants", id)
		if not spec.has("scene"):
			continue
		_kinds.append(id)
		_catalog.add_item(String(spec.get("name", id)))
	_catalog.item_selected.connect(func(_i: int) -> void: _variant.max_value = _variant_count() - 1; _variant.value = 0)
	_variant = _spin(column, "Variante", 0, 0, _variant_count() - 1)
	_scale = _spin(column, "Größe", 1, 0.5, 2, 0.1)
	_flip = CheckBox.new()
	_flip.text = "Horizontal spiegeln"
	column.add_child(_flip)
	_selection = _label(column, "Kein Objekt ausgewählt", Color("a69abc"))
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "Übernehmen", _edit_selected)
	_button(actions, "Löschen", _delete_selected)
	_button(column, "Duplizieren → platzieren", _duplicate_selected)
	_label(column, "TERRAIN", ACCENT)
	_size = _spin(column, "Pinselradius", 2, 0, 8)
	_grounds.assign(DataRegistry.table("grass_tiles").keys())
	_ground_kind = _options(column, _grounds)
	for id: String in DataRegistry.table("biomes"):
		var active: String = RegionMap.active_biome(id)
		if not _biomes.has(active):
			_biomes.append(active)
	_biome = _options(column, _biomes)
	_height = _spin(column, "Zielhöhe", 1, 0, 3)
	var styles: Array[String] = ["Gras / Erde", "Fels", "Mauerwerk", "Kristall", "Void"]
	if String(DataRegistry.table("world_map").get("biome", "")) == "meadow":
		styles = ["Gras / Erde", "Fels"]
	_style = _options(column, styles)
	_label(column, "Rampen / Treppen laufen nach Norden.\nUnten Höhe H, oben H+1.", Color("a69abc"))
	_grid = CheckBox.new()
	_grid.text = "Raster anzeigen"
	_grid.button_pressed = true
	column.add_child(_grid)
	_label(column, "WASD: Kamera\nMittel-/Rechtsklick: schieben\nMausrad: Zoom · F: Spieler\nEntf: löschen · Esc: zurück\nStrg/Cmd+S: speichern", Color("a69abc"))
	var bottom: PanelContainer = PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -32
	_root.add_child(bottom)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Weltwerkstatt schließen"
	_dialog.dialog_text = "Deine Karte enthält ungespeicherte Änderungen."
	_dialog.ok_button_text = "Speichern & spielen"
	_dialog.cancel_button_text = "Weiter bearbeiten"
	_dialog.add_button("Verwerfen & spielen", false, "discard")
	_dialog.confirmed.connect(func() -> void: if _save(): _close())
	_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			world.editor_apply(_saved)
			_close())
	_root.add_child(_dialog)

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.modulate = color
	parent.add_child(label)
	return label

func _options(parent: Node, names: Array[String]) -> OptionButton:
	var options: OptionButton = OptionButton.new()
	options.fit_to_longest_item = false
	for text: String in names:
		options.add_item(text)
	parent.add_child(options)
	return options

func _spin(parent: Node, title: String, value: float, low: float, high: float, step: float = 1) -> SpinBox:
	_label(parent, title, Color("a69abc"))
	var spin: SpinBox = SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	parent.add_child(spin)
	return spin

func _variant_count() -> int:
	if _kinds.is_empty():
		return 1
	return (DataRegistry.get_entry("plants", _kinds[_catalog.selected]).radius as Array).size()

func _mouse_world() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()

func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / 16.0), floori(pos.y / 16.0))

func _over_map() -> bool:
	var pos: Vector2 = get_viewport().get_mouse_position()
	return pos.y > 29 and pos.y < _root.size.y - 33 and not _panel.get_global_rect().has_point(pos) and not _dialog.visible

func _process(delta: float) -> void:
	if not is_instance_valid(world):
		_close()
		return
	if not _dialog.visible and not get_viewport().gui_get_focus_owner() is LineEdit:
		camera.position += InputManager.move_vector() * 340.0 * delta / camera.zoom.x
	camera.position = camera.position.clamp(Vector2.ZERO, Vector2.ONE * RegionMap.WORLD_TILES * 16.0)
	world.editor_refresh()
	_overlay.queue_redraw()

func _input(event: InputEvent) -> void:
	# Finish a gesture even when the pointer is released over the sidebar.
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if not button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			if _stroke:
				_finish_stroke()
			if is_instance_valid(_drag):
				_finish_drag()
		if not button.pressed and button.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = false

func _unhandled_input(event: InputEvent) -> void:
	if _dialog.visible:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key: InputEventKey = event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		if code == KEY_ESCAPE:
			_request_close()
		elif (key.ctrl_pressed or key.meta_pressed) and code == KEY_S:
			_save()
		elif (key.ctrl_pressed or key.meta_pressed) and code == KEY_Z:
			if key.shift_pressed: redo()
			else: undo()
		elif code in [KEY_DELETE, KEY_BACKSPACE]:
			_delete_selected()
		elif code == KEY_F:
			_home()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and _over_map():
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed:
			if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var before: Vector2 = _mouse_world()
				camera.zoom = Vector2.ONE * clampf(camera.zoom.x * (1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.35, 3.0)
				camera.force_update_scroll()
				camera.position += before - _mouse_world()
			elif button.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
				_panning = true
			elif button.button_index == MOUSE_BUTTON_LEFT:
				_begin_gesture()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _panning:
			camera.position -= motion.relative / camera.zoom
		elif is_instance_valid(_drag):
			_drag.position = (_mouse_world() + _drag_offset).snapped(Vector2.ONE)
		elif _stroke and _over_map():
			_paint_line(_cell_at(_mouse_world()))
		if _over_map():
			get_viewport().set_input_as_handled()

func _begin_gesture() -> void:
	var at: Vector2 = _mouse_world()
	if _tool.selected == 0:
		var thing: WorldProp = world.editor_pick(at)
		_selected = thing.cell if thing != null else Vector2i(-1, -1)
		_sync_selection()
		if thing != null:
			_drag = thing
			_drag_origin = thing.position
			_drag_offset = thing.position - at
	elif _tool.selected == 1:
		var cell: Vector2i = _cell_at(at)
		if not world.editor_land(cell):
			_note("Objekte können auf der bestehenden Landfläche platziert werden.")
			return
		if world._things.has(cell):
			_note("Hier steht schon ein Objekt. Verschiebe oder lösche es zuerst.")
			return
		var next: Dictionary = world.edits.data()
		(next.props as Dictionary)[WorldEdits.key(cell)] = _catalog_spec(Vector2(cell) * 16.0 + Vector2(8, 13))
		_selected = cell
		_commit(next)
	elif _tool.selected == 2:
		var thing: WorldProp = world.editor_pick(at)
		if thing != null:
			_selected = thing.cell
			_delete_selected()
	else:
		_stroke = true
		_pending = world.edits.data()
		_last_cell = _cell_at(at)
		_paint_line(_last_cell)

func _catalog_spec(pos: Vector2) -> Dictionary:
	return {"kind": _kinds[_catalog.selected], "variant": int(_variant.value), "pos": [pos.x, pos.y], "scale": _scale.value, "flip": _flip.button_pressed}

func _paint_line(to: Vector2i) -> void:
	var steps: int = maxi(absi(to.x - _last_cell.x), absi(to.y - _last_cell.y))
	for i: int in steps + 1:
		var center: Vector2i = Vector2i(Vector2(_last_cell).lerp(Vector2(to), float(i) / maxi(1, steps)).round())
		_stamp(center)
	_last_cell = to

func _stamp(center: Vector2i) -> void:
	var radius: int = int(_size.value)
	if _tool.selected in [5, 6]:
		var depth: int = 3 if _tool.selected == 5 else 2
		if _height.value >= 3:
			_note("Verbinder benötigen eine untere Höhe von 0 bis 2.")
			return
		# Complete three-wide connectors, with explicit upper/lower landings.
		for row: int in range(-1, depth + 1):
			for col: int in 3:
				var cell: Vector2i = center + Vector2i(col - 1, row)
				if not world.editor_land(cell):
					return
		for row: int in range(-1, depth + 1):
			for col: int in 3:
				var cell: Vector2i = center + Vector2i(col - 1, row)
				var spec: Dictionary = (_pending.terrain as Dictionary).get(WorldEdits.key(cell), {}).duplicate(true)
				spec.merge({"height": int(_height.value) + (1 if row == -1 else 0), "kind": (Relief.RAMP if depth == 3 else Relief.STAIRS) if row >= 0 and row < depth else 0, "style": _style.selected, "geom": (row | ((depth - 1) << 2) | (col << 4)) if row >= 0 and row < depth else 0}, true)
				(_pending.terrain as Dictionary)[WorldEdits.key(cell)] = spec
		return
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y > radius * radius:
				continue
			var cell: Vector2i = center + Vector2i(x, y)
			if not world.editor_land(cell):
				continue
			var key_string: String = WorldEdits.key(cell)
			if _tool.selected == 7:
				(_pending.terrain as Dictionary).erase(key_string)
				continue
			var spec: Dictionary = (_pending.terrain as Dictionary).get(key_string, {}).duplicate(true)
			if _tool.selected == 3:
				spec["ground"] = _grounds[_ground_kind.selected]
				spec["biome"] = _biomes[_biome.selected]
			else:
				spec.merge({"height": int(_height.value), "style": _style.selected, "kind": 0, "geom": 0}, true)
			(_pending.terrain as Dictionary)[key_string] = spec

func _finish_stroke() -> void:
	_stroke = false
	_commit(_pending)
	_pending = {}

func _finish_drag() -> void:
	var from: Vector2i = _drag.cell
	var dest: Vector2i = _cell_at(_drag.position)
	var pos: Vector2 = _drag.position
	var spec: Dictionary = world.editor_prop(from)
	_drag.position = _drag_origin
	_drag = null
	if pos.distance_to(_drag_origin) < 1.0:
		return
	if not world.editor_land(dest) or (dest != from and world._things.has(dest)):
		_note("Ziel belegt oder außerhalb der Landfläche.")
		return
	var next: Dictionary = world.edits.data()
	(next.props as Dictionary)[WorldEdits.key(from)] = {"removed": true}
	spec.pos = [pos.x, pos.y]
	(next.props as Dictionary)[WorldEdits.key(dest)] = spec
	_selected = dest
	_commit(next)

func _cancel_gesture() -> void:
	_stroke = false
	_pending = {}
	_panning = false
	if is_instance_valid(_drag):
		_drag.position = _drag_origin
	_drag = null

func _sync_selection() -> void:
	var spec: Dictionary = world.editor_prop(_selected)
	_selection.text = "Kein Objekt ausgewählt"
	if spec.is_empty():
		return
	_selection.text = "Auswahl: %s\nZelle %d · %d" % [String(DataRegistry.get_entry("plants", spec.kind).get("name", spec.kind)), _selected.x, _selected.y]
	_catalog.select(_kinds.find(String(spec.kind)))
	_variant.max_value = _variant_count() - 1
	_variant.value = int(spec.variant)
	_scale.value = float(spec.scale)
	_flip.button_pressed = bool(spec.flip)

func _edit_selected() -> void:
	_cancel_gesture()
	var spec: Dictionary = world.editor_prop(_selected)
	if spec.is_empty():
		_note("Wähle zuerst ein Objekt in der Welt aus.")
		return
	var next: Dictionary = world.edits.data()
	(next.props as Dictionary)[WorldEdits.key(_selected)] = _catalog_spec(Vector2(float(spec.pos[0]), float(spec.pos[1])))
	_commit(next)

func _delete_selected() -> void:
	if world.editor_prop(_selected).is_empty():
		return
	var next: Dictionary = world.edits.data()
	(next.props as Dictionary)[WorldEdits.key(_selected)] = {"removed": true}
	_commit(next)

func _duplicate_selected() -> void:
	if world.editor_prop(_selected).is_empty():
		return
	_sync_selection()
	_tool.select(1)
	_note("Kopie bereit. Klicke auf eine freie Stelle.")

func _commit(next: Dictionary) -> void:
	var before: Dictionary = world.edits.data()
	if next == before:
		return
	_history.append(before)
	if _history.size() > 80:
		_history.pop_front()
	_future.clear()
	world.editor_apply(next)
	_sync_selection()
	_update_title()
	_note("Änderung angewendet · %d Schritte rückgängig verfügbar." % _history.size())

func undo() -> void:
	_cancel_gesture()
	if _history.is_empty():
		return
	_future.append(world.edits.data())
	world.editor_apply(_history.pop_back())
	_sync_selection()
	_update_title()
	_note("Rückgängig.")

func redo() -> void:
	_cancel_gesture()
	if _future.is_empty():
		return
	_history.append(world.edits.data())
	world.editor_apply(_future.pop_back())
	_sync_selection()
	_update_title()
	_note("Wiederhergestellt.")

func _save() -> bool:
	if _stroke:
		_finish_stroke()
	if is_instance_valid(_drag):
		_finish_drag()
	if not world.edits.save():
		_note("Speichern fehlgeschlagen. Deine Änderungen bleiben im Editor erhalten.")
		return false
	_saved = world.edits.data()
	_update_title()
	_note("Karte gespeichert. Sie wird beim nächsten Weltstart automatisch geladen.")
	return true

func _update_title() -> void:
	_title.text = "✦ WELTWERKSTATT" + ("  • ungespeichert" if world.edits.data() != _saved else "")

func _note(text: String) -> void:
	_status.text = text

func _home() -> void:
	if _previous_camera != null:
		camera.position = _previous_camera.global_position

func _request_close() -> void:
	_cancel_gesture()
	if world.edits.data() != _saved:
		_dialog.popup_centered(Vector2i(360, 130))
	else:
		_close()

func _peer_joined(_id: int) -> void:
	# Stop the paused solo workspace before live multiplayer resumes.
	_cancel_gesture()
	world.editor_apply(_saved)
	_close()

func _close() -> void:
	for hud: CanvasLayer in _hidden_huds:
		if is_instance_valid(hud):
			hud.show()
	InputManager.ui_blocking = false
	InputManager.menu_open = false
	if is_instance_valid(world):
		world.editor_camera = null
		world._cliffs.process_mode = Node.PROCESS_MODE_INHERIT
		for child: Node in world.get_children():
			if child is VoidEdge:
				child.process_mode = Node.PROCESS_MODE_INHERIT
		if world.multiplayer.peer_connected.is_connected(_peer_joined):
			world.multiplayer.peer_connected.disconnect(_peer_joined)
	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	if is_instance_valid(camera):
		camera.queue_free()
	get_tree().paused = _was_paused
	queue_free()

func _draw_overlay() -> void:
	var transform: Transform2D = get_viewport().get_canvas_transform()
	var mouse: Vector2 = _mouse_world()
	var cell: Vector2i = _cell_at(mouse)
	if _grid.button_pressed and camera.zoom.x >= 0.55:
		var inverse: Transform2D = transform.affine_inverse()
		var start: Vector2i = _cell_at(inverse * Vector2.ZERO)
		var end: Vector2i = _cell_at(inverse * _root.size) + Vector2i.ONE
		for x: int in range(start.x, end.x + 1):
			_overlay.draw_line(transform * Vector2(x * 16, start.y * 16), transform * Vector2(x * 16, end.y * 16), Color(0.6, 0.9, 0.85, 0.10))
		for y: int in range(start.y, end.y + 1):
			_overlay.draw_line(transform * Vector2(start.x * 16, y * 16), transform * Vector2(end.x * 16, y * 16), Color(0.6, 0.9, 0.85, 0.10))
	if world._things.has(_selected):
		var thing: WorldProp = world._things[_selected]
		var pos: Vector2 = transform * thing.position
		_overlay.draw_arc(pos, 14 * camera.zoom.x, 0, TAU, 32, ACCENT, 1.5)
		_overlay.draw_line(pos - Vector2(6, 0), pos + Vector2(6, 0), ACCENT)
	if _stroke:
		for key_string: String in _pending.get("terrain", {}):
			if (_pending.terrain as Dictionary).get(key_string) != world.edits.terrain.get(key_string):
				var at: Vector2i = WorldEdits.cell(key_string)
				_overlay.draw_rect(Rect2(transform * (Vector2(at) * 16.0), Vector2.ONE * 16.0 * camera.zoom.x), Color(0.5, 0.9, 0.8, 0.25))
	if not _over_map():
		return
	var valid: bool = world.editor_land(cell)
	var color: Color = ACCENT if valid else Color("ec7b94")
	var screen: Vector2 = transform * (Vector2(cell) * 16.0)
	if _tool.selected >= 3:
		_overlay.draw_arc(transform * (Vector2(cell) * 16.0 + Vector2(8, 8)), (float(_size.value) + 0.5) * 16.0 * camera.zoom.x, 0, TAU, 48, color, 1.0)
	else:
		_overlay.draw_rect(Rect2(screen, Vector2.ONE * 16.0 * camera.zoom.x), color, false, 1.0)
	if _tool.selected == 1:
		var spec: Dictionary = DataRegistry.get_entry("plants", _kinds[_catalog.selected])
		var texture: Texture2D = load(String(spec.texture)) as Texture2D
		var frame: Vector2 = Vector2(texture.get_size()) / Vector2(int(spec.get("columns", 1)), int(spec.get("rows", 1)))
		var dest_size: Vector2 = frame * camera.zoom.x * float(_scale.value)
		var dest: Rect2 = Rect2(screen + Vector2(8, 13) * camera.zoom.x - Vector2(dest_size.x / 2, dest_size.y), dest_size)
		_overlay.draw_texture_rect_region(texture, dest, Rect2(Vector2(int(_variant.value) * frame.x, 0), frame), Color(1, 1, 1, 0.5))
