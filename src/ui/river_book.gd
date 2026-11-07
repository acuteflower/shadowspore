class_name RiverBook
extends Control
## The river book (N): two bark-paper pages. Left the species (a silhouette until caught), right the one chosen:
## picture, best length, count, first day and what is known about it. Local to the player, see FishBook.

const SIDE: Texture2D = preload("res://assets/fishing/fish_side.png")
const ORDER: Array[String] = ["silverling", "copper_loach", "moon_trout", "gold_carp", "glimmer_loach", "veil_eel", "abyss_pike"]
const RARITY: Dictionary = {"common": "b8b8c8", "uncommon": "6fd08c", "rare": "5aa8ff", "epic": "b47aff", "legendary": "ffb347"}
const RARITY_NAME: Dictionary = {"common": "GEWÖHNLICH", "uncommon": "UNGEWÖHNLICH", "rare": "SELTEN", "epic": "EPISCH", "legendary": "LEGENDÄR"}
const GOLD: Color = Color("e6c468")
const TEXT: Color = Color("e8e4f4")
const DIM: Color = Color("8a84ad")
const TEAL: Color = Color("7fe3da")
const INK: Color = Color("1b1a2e")
const ROW: int = 24

var open: bool = false
var selected: int = 0
var _p: Player
var _t: float = 0.0
var _was_blocking: bool = false


func bind(player: Node) -> void:
	_p = player as Player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func toggle() -> void:
	if open:
		close()
	else:
		open_book()


func open_book() -> void:
	if open or _p == null or _p.fishing == null or _p.fishing.book == null:
		return
	open = true
	visible = true
	_t = 0.0
	selected = clampi(selected, 0, ORDER.size() - 1)
	_was_blocking = InputManager.ui_blocking
	InputManager.ui_blocking = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func close() -> void:
	if not open:
		return
	open = false
	visible = false
	InputManager.ui_blocking = _was_blocking
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	if open:
		InputManager.ui_blocking = _was_blocking


func _process(delta: float) -> void:
	if open:
		_t = minf(_t + delta * 4.0, 1.0)
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key: Key = (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE or key == KEY_N:
			close()
		elif key == KEY_S or key == KEY_DOWN:
			selected = mini(selected + 1, ORDER.size() - 1)
		elif key == KEY_W or key == KEY_UP:
			selected = maxi(selected - 1, 0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var row: int = int(((event as InputEventMouseButton).position.y - (_left_rect().position.y + 34.0)) / ROW)
		var in_x: bool = _left_rect().has_point((event as InputEventMouseButton).position)
		if in_x and row >= 0 and row < ORDER.size():
			selected = row
		get_viewport().set_input_as_handled()


func _left_rect() -> Rect2:
	return Rect2(roundf(size.x * 0.5) - 212.0, roundf(size.y * 0.5) - 128.0, 206, 256)


func _right_rect() -> Rect2:
	return Rect2(roundf(size.x * 0.5) + 6.0, roundf(size.y * 0.5) - 128.0, 206, 256)


func _wrap(text: String, columns: int) -> Array[String]:
	var lines: Array[String] = []
	var line: String = ""
	for word: String in text.split(" "):
		if line != "" and (line.length() + 1 + word.length()) * 4 > columns * 4:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		lines.append(line)
	return lines


func habitat_text(id: String) -> String:
	var spec: Dictionary = FishingRules.species_table()[id] as Dictionary
	var hy: Array = (spec["habitat"] as Dictionary)["y"] as Array
	var depth: String = "FLACHES WASSER" if float(hy[1]) <= 0.45 else ("TIEFES WASSER" if float(hy[0]) >= 0.6 else "MITTLERE TIEFE")
	var window: Array = spec["night"] as Array
	var when: String = "NUR NACHTS" if float(window[0]) >= 0.3 else ("TAGS" if float(window[1]) <= 0.6 else "TAG UND NACHT")
	var line: String = "%s, %s" % [depth, when]
	if spec.has("flow"):
		var flow: Array = spec["flow"] as Array
		line += ", STARKE STRÖMUNG" if float(flow[0]) >= 0.4 else (", STILLES WASSER" if float(flow[1]) <= 0.45 else "")
	if float(spec.get("shy", 0.0)) > 0.0:
		line += ", MEIDET LICHT"
	return line


func _draw() -> void:
	if not open:
		return
	var book: FishBook = _p.fishing.book
	var a: float = _t
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.05, 0.62 * a))
	var left: Rect2 = _left_rect()
	var right: Rect2 = _right_rect()
	VineStyle.paper(self, left, a, 0.0, 3)
	VineStyle.paper(self, right, a, 0.0, 29)
	PixelText.draw(self, "FLUSSBUCH", Vector2i(int(left.position.x) + 12, int(left.position.y) + 12), Color(GOLD, a), Color(INK, a))
	var found: int = book.species.size()
	var count_text: String = "%d/%d" % [found, ORDER.size()]
	PixelText.draw(self, count_text, Vector2i(int(left.end.x) - 12 - PixelText.width(count_text), int(left.position.y) + 12), Color(TEAL, a))
	var table: Dictionary = FishingRules.species_table()
	for i: int in ORDER.size():
		var id: String = ORDER[i]
		var spec: Dictionary = table[id] as Dictionary
		var known: bool = book.known(id)
		var y: int = int(left.position.y) + 34 + i * ROW
		if i == selected:
			draw_rect(Rect2(left.position.x + 8, y, left.size.x - 16, ROW - 2), Color("2a2548", 0.8 * a))
			draw_rect(Rect2(left.position.x + 8, y, 2, ROW - 2), Color(TEAL, a))
		var icon: Texture2D = Items.icon({"id": String(spec["item"]), "count": 1})
		if icon != null:
			draw_texture_rect(icon, Rect2(left.position.x + 14, y + 2, 16, 16), false, Color(1, 1, 1, a) if known else Color(0.03, 0.02, 0.07, a))
		PixelText.draw(self, String(spec["name"]) if known else "????????", Vector2i(int(left.position.x) + 36, y + 7), Color(TEXT if known else DIM, a))
		if known:
			var n: String = "X%d" % int((book.species[id] as Dictionary)["caught"])
			PixelText.draw(self, n, Vector2i(int(left.end.x) - 14 - PixelText.width(n), y + 7), Color(GOLD, a))
	_draw_page(right, ORDER[selected], book, a)
	PixelText.draw(self, "W S: WÄHLEN    N: SCHLIESSEN", Vector2i(int(size.x * 0.5) - 54, int(left.end.y) + 6), Color(DIM, a))


func _draw_page(rect: Rect2, id: String, book: FishBook, a: float) -> void:
	var spec: Dictionary = FishingRules.species_table()[id] as Dictionary
	var known: bool = book.known(id)
	var entry: Dictionary = book.species.get(id, {}) as Dictionary
	var cx: int = int(rect.position.x + rect.size.x * 0.5)
	var tint: Color = Color(1, 1, 1, a) if known else Color(0.03, 0.02, 0.07, a)
	draw_texture_rect_region(SIDE, Rect2(cx - 48, rect.position.y + 20, 96, 48), Rect2(0, ORDER.find(id) * 24, 48, 24), tint)
	var name_text: String = String(spec["name"]) if known else "UNBEKANNT"
	PixelText.draw(self, name_text, Vector2i(cx - PixelText.width(name_text) / 2, int(rect.position.y) + 78), Color(GOLD, a), Color(INK, a))
	var rarity: String = String(spec["rarity"])
	var rarity_text: String = String(RARITY_NAME.get(rarity, "")) if known else "???"
	PixelText.draw(self, rarity_text, Vector2i(cx - PixelText.width(rarity_text) / 2, int(rect.position.y) + 90), Color(Color(String(RARITY.get(rarity, "b8b8c8"))), a))
	var y: int = int(rect.position.y) + 112
	var x: int = int(rect.position.x) + 16
	if known:
		PixelText.draw(self, "LÄNGSTER: %d CM" % int(entry["best"]), Vector2i(x, y), Color(TEXT, a))
		PixelText.draw(self, "GEFANGEN: %d" % int(entry["caught"]), Vector2i(x, y + 12), Color(TEXT, a))
		PixelText.draw(self, "ERSTER FANG: TAG %d" % int(entry["first_day"]), Vector2i(x, y + 24), Color(TEXT, a))
		var yy: int = y + 44
		for line: String in _wrap(String(spec["info"]), 44):
			PixelText.draw(self, line, Vector2i(x, yy), Color(DIM.lightened(0.25), a))
			yy += 9
		yy += 4
		for line: String in _wrap("FINDET MAN: " + habitat_text(id), 44):
			PixelText.draw(self, line, Vector2i(x, yy), Color(TEAL, a))
			yy += 9
	else:
		for line: String in _wrap("NOCH NICHT GEFANGEN. BEOBACHTE DAS WASSER UND PROBIERE ANDERE KÖDER.", 44):
			PixelText.draw(self, line, Vector2i(x, y), Color(DIM, a))
			y += 9
