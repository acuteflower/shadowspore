class_name LiftMenu
extends CanvasLayer
## Where the lift goes: a card of bark paper with a row for the gate and every mended lift. Arrow keys and E, or the mouse; Escape closes it. Opened by the
## `MineWinch` of a level (`level` > 0) and by the mine's gate on the surface (`level` 0 = the world outside, the first row is level 1's entry hall).

const CARD_WIDTH: float = 168.0
const ROW: float = 17.0
const TEXT: Color = Color("e9dcff")
const DIM: Color = Color("8f7fb0")
const LIT: Color = Color("78f4e6")

var _player: Player
var _level: int = 0
var _rows: Array[Dictionary] = [] ## {text, level, spot}
var _focus: int = 0
var _canvas: Control
var _time: float = 0.0


## Local player: opens the menu for `level` (0 = at the gate outside).
static func open(tree: SceneTree, player: Player, level: int) -> void:
	if tree.get_first_node_in_group("lift_menu") != null:
		return
	var menu: LiftMenu = LiftMenu.new()
	tree.root.add_child(menu)
	menu.setup(player, level)


func setup(player: Player, level: int) -> void:
	add_to_group("lift_menu")
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = player
	_level = level
	var mines: MineManager = get_tree().get_first_node_in_group("mines") as MineManager
	if level > 0:
		_rows.append({"text": "ZUM TOR", "level": 0, "spot": "entry"})
	else:
		_rows.append({"text": "EBENE 1  EINGANG", "level": 1, "spot": "entry"})
	if mines != null:
		for station: int in mines.unlocked_stations():
			if station != level:
				_rows.append({"text": "EBENE %d  AUFZUG" % station, "level": station, "spot": "station"})
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)
	player.story_lock = true ## she stands still while she chooses
	InputManager.ui_blocking = true


func _process(delta: float) -> void:
	_time += delta
	_canvas.queue_redraw()


func _card() -> Rect2:
	var height: float = 30.0 + ROW * _rows.size() + 12.0
	return Rect2((_canvas.size - Vector2(CARD_WIDTH, height)) / 2.0, Vector2(CARD_WIDTH, height)).abs()


func _row_rect(index: int) -> Rect2:
	var card: Rect2 = _card()
	return Rect2(card.position.x + 12.0, card.position.y + 26.0 + ROW * index, CARD_WIDTH - 24.0, ROW - 1.0)


func _draw() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.02, 0.01, 0.05, 0.5))
	var card: Rect2 = _card()
	VineStyle.paper(_canvas, card, 1.0, 0.1, 31)
	PixelText.draw(_canvas, "AUFZUG", Vector2i(int(card.position.x) + 12, int(card.position.y) + 9), Color("d9b25f"), Color("0a0612"))
	for i: int in _rows.size():
		var rect: Rect2 = _row_rect(i)
		var on: bool = i == _focus
		if on:
			_canvas.draw_rect(rect, Color(LIT, 0.14 + 0.05 * sin(_time * 4.0)))
			_canvas.draw_rect(Rect2(rect.position, Vector2(2, rect.size.y)), LIT)
		PixelText.draw(_canvas, String(_rows[i].text), Vector2i(int(rect.position.x) + 8, int(rect.position.y) + 5), TEXT if on else DIM, Color("0a0612"))


func _input(event: InputEvent) -> void:
	if _rows.is_empty():
		return
	if event.is_action_pressed("ui_down"):
		_focus = (_focus + 1) % _rows.size()
	elif event.is_action_pressed("ui_up"):
		_focus = (_focus + _rows.size() - 1) % _rows.size()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_choose(_focus)
	elif event.is_action_pressed("ui_cancel"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_gui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	var click: InputEventMouseButton = event as InputEventMouseButton
	if motion != null:
		for i: int in _rows.size():
			if _row_rect(i).has_point(motion.position):
				_focus = i
	elif click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		for i: int in _rows.size():
			if _row_rect(i).has_point(click.position):
				_choose(i)
				return
		if not _card().has_point(click.position):
			_close()


func _close() -> void:
	if is_instance_valid(_player):
		_player.story_lock = false
	InputManager.ui_blocking = false
	queue_free()


func _choose(index: int) -> void:
	var row: Dictionary = _rows[index]
	var player: Player = _player
	_close()
	var mines: MineManager = player.get_tree().get_first_node_in_group("mines") as MineManager
	if mines != null:
		mines.travel(player, int(row.level), String(row.spot))
