class_name HintCard
extends Control
## The first tutorial card of the game, left under the clock: shown while the current quest step has a "hint" (data/quests.json), now "sneak". A branch
## grows out of the left edge, a leaf of bark paper hangs from it with the key cap (the bound key, lit teal while she is really sneaking) and
## a few lines. When the step is done the card blooms, sparks fly and it withers away. Not shown while a dialogue is open.

const WIDTH: float = 176.0
const HEIGHT: float = 92.0
const SHOW_SECONDS: float = 14.0 ## a lesson stays this long, then it withers (the quest vine keeps the task)
const PAPER: Color = Color("140e24")

var _quests: QuestComponent
var _dialogue: DialogueBox
var _tracked: TrackedQuests
var _journal_hint_started: bool = false
var _hint: String = ""
var _grow: float = 0.0
var _time: float = 0.0
var _bloom: float = 0.0
var _step_key: String = ""
var _age: float = 0.0 ## seconds this step's card has been wanted
var _event_left: float = 0.0 ## a card that is not a quest lesson (swimming): seconds still to show
var _live: float = 0.0 ## 0..1, eased: she is sneaking right now


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 0.0
	offset_top = 96.0
	offset_right = WIDTH
	offset_bottom = 96.0 + HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hint_card")


func bind(quests: QuestComponent, dialogue: DialogueBox, tracked: TrackedQuests) -> void:
	_quests = quests
	_dialogue = dialogue
	_tracked = tracked
	quests.changed.connect(_refresh)
	quests.step_done.connect(func(_q: String, _s: int) -> void: _bloom = 1.0 if _hint != "" else 0.0)
	_refresh()


func _refresh() -> void:
	var now: Dictionary = _quests.current()
	var hint: String = String(now.get("hint", ""))
	if hint != "" and _event_left <= 0.0:
		_hint = hint


## First time in deep water: a short card about swimming and the crawl (flag swim_hint_seen, once per save).
func notify_swim() -> void:
	if _quests == null or _quests.has_flag("swim_hint_seen"):
		return
	_quests.set_flag("swim_hint_seen")
	_hint = "swim"
	_event_left = 12.0


## First time a notice hangs on the quest board and she is near it (flag board_hint_seen, once per save).
func notify_board() -> void:
	if _quests == null or _quests.has_flag("board_hint_seen"):
		return
	_quests.set_flag("board_hint_seen")
	_hint = "board"
	_event_left = 14.0


## First breath of the Hexenwald's mist (flag mist_hint_seen, once per save).
func notify_mist() -> void:
	if _quests == null or _quests.has_flag("mist_hint_seen"):
		return
	_quests.set_flag("mist_hint_seen")
	_hint = "mist"
	_event_left = 12.0


func _wanted() -> bool:
	var now: Dictionary = _quests.current()
	var hint: String = String(now.get("hint", ""))
	if hint == "map" and _quests.has_flag("map_opened"):
		return false ## she has opened the map: the lesson is over
	return hint != "" and not _dialogue.is_active()


func _process(delta: float) -> void:
	_time += delta
	var now: Dictionary = _quests.current()
	var step_key: String = "%s/%s" % [now.get("id", ""), now.get("step_id", "")]
	if step_key != _step_key:
		_step_key = step_key
		_age = 0.0
	var wanted: bool = _wanted()
	if wanted:
		_age += delta
	wanted = wanted and _age < SHOW_SECONDS
	if not wanted and _event_left <= 0.0 and not _journal_hint_started and _tracked != null and not _tracked.journal_opened and _quests.has_flag("hud_unlocked") and not _dialogue.is_active():
		_journal_hint_started = true
		_hint = "journal"
		_event_left = 10.0
	if _event_left > 0.0:
		_event_left -= delta
		wanted = not _dialogue.is_active()
		if _event_left <= 0.0:
			_hint = ""
			wanted = false
	_grow = move_toward(_grow, 1.0 if wanted else 0.0, delta / (1.1 if wanted else 0.8))
	_bloom = move_toward(_bloom, 0.0, delta * 0.8)
	var using_key: bool = InputManager.map_open if _hint == "map" else InputManager.sneak_held()
	if _hint == "journal":
		using_key = InputManager.journal_open
		if using_key:
			_event_left = 0.0
			_bloom = 1.0
	_live = move_toward(_live, 1.0 if using_key else 0.0, delta * 6.0)
	if _hint == "map" and InputManager.map_open and _wanted():
		_bloom = 1.0 ## the map is open: the card blooms and withers
		_quests.set_flag("map_opened")
	visible = _grow > 0.0 or _bloom > 0.0
	queue_redraw()


func _key_label(action: String = "sneak") -> String:
	return VineStyle.key_name(action, "STRG" if action == "sneak" else "M")


func _draw() -> void:
	if _hint in ["take_sword", "equip_sword", "combo"]:
		_draw_sword_hint()
		return
	if _hint == "chop":
		_draw_chop_hint()
		return
	if _hint == "build":
		_draw_build_hint()
		return
	if _hint == "swim":
		_draw_swim_hint()
		return
	if _hint == "mist":
		_draw_mist_hint()
		return
	if _hint in ["board", "journal"]:
		_draw_notice_hint(_hint == "journal")
		return
	if _hint == "craft":
		_draw_craft_hint()
		return
	if _hint in ["socket", "cast"]:
		_draw_staff_hint(_hint == "cast")
		return
	if _hint != "sneak" and _hint != "map":
		return
	var is_map: bool = _hint == "map"
	var g: float = _grow * _grow * (3.0 - 2.0 * _grow)
	var void_level: float = VineStyle.void_amount()
	var length: float = (WIDTH - 12.0) * g
	for xi: int in int(length) + 1: ## the branch out of the left edge
		var thick: int = 4 if xi < 14 else (3 if xi < 60 else (2 if xi < 130 else 1))
		var y: float = roundf(6.0 + sin(xi * 0.06) * 1.5) - thick / 2
		draw_rect(Rect2(xi, y - 1, 1, thick + 2), VineStyle.OUTLINE)
		draw_rect(Rect2(xi, y, 1, thick), VineStyle.BARK)
		if xi % 3 != 1:
			draw_rect(Rect2(xi, y, 1, 1), VineStyle.BARK_LIGHT)
	for k: int in 4:
		var lx: float = 18.0 + k * 38.0
		if lx < length - 4.0:
			VineStyle.leaf(self, Vector2(lx, 6.0 + (-3 if k % 2 == 0 else 3)), 1, -1 if k % 2 == 0 else 1, 3, VineStyle.LEAF, VineStyle.LEAF_LIGHT)
	var tip: Vector2 = Vector2(length, 6.0)
	VineStyle.glow(self, tip, 5.0, VineStyle.WARM_GLOW, 0.7 * g)
	if g < 0.6 and _bloom <= 0.0:
		return
	# the card hangs from two threads, swinging a little
	var sway: float = sin(_time * 1.4) * 1.0
	var card: Rect2 = Rect2(10.0 + sway, 22.0, WIDTH - 22.0, HEIGHT - 26.0)
	var drop: float = (1.0 - clampf((g - 0.6) / 0.4, 0.0, 1.0)) * -20.0
	var fade: float = clampf((g - 0.6) / 0.4, 0.0, 1.0) * (1.0 - _bloom * 0.0)
	for tx: float in [card.position.x + 14.0, card.end.x - 14.0]:
		for ty: int in range(7, int(card.position.y + drop)):
			draw_rect(Rect2(tx, ty, 1, 1), VineStyle.BARK if ty % 2 == 0 else VineStyle.BARK_LIGHT)
	var origin: Vector2 = card.position + Vector2(0, drop)
	_paper(origin, card.size, fade, void_level)
	var live_glow: float = _live
	# the key cap: a bud with the key in it, bright while she sneaks
	var bud: Vector2 = origin + Vector2(20, 24)
	var key: String = _key_label("map" if is_map else "sneak")
	var cap_w: int = VineStyle.key_cap(self, bud + Vector2(-8, -6), key, fade, live_glow, void_level)
	var text_x: int = int(origin.x) + 20 + cap_w + 2
	PixelText.draw(self, "KARTE" if is_map else "SCHLEICHEN", Vector2i(text_x, int(origin.y) + 8), Color(VineStyle.WARM_GLOW, fade), Color(VineStyle.OUTLINE, fade))
	var lines: Array[String] = ["HALTE %s GEDRUECKT." % key, "SO ENTDECKEN DICH", "SCHATTENWESEN SPAET."]
	if is_map:
		lines = ["ÖFFNE DIE KARTE MIT %s." % key, "IM GOLDENEN KREIS", "LIEGT DEIN ZIEL."]
	for i: int in lines.size():
		PixelText.draw(self, lines[i].replace("UE", "Ü").replace("AE", "Ä"), Vector2i(int(origin.x) + 10, int(origin.y) + 36 + i * 9), Color(UiStyle.TEXT, fade), Color(VineStyle.OUTLINE, fade))
	var state: String = ("OFFEN" if _live > 0.5 else "ZU") if is_map else ("LEISE" if _live > 0.5 else "LAUT")
	PixelText.draw(self, state, Vector2i(text_x, int(origin.y) + 18), Color(UiStyle.ACCENT if _live > 0.5 else UiStyle.TEXT_DIM, fade * (0.6 + 0.4 * _live)), Color(VineStyle.OUTLINE, fade))
	if _bloom > 0.0: ## done: a burst of petals over the card
		for k: int in 16:
			var angle: float = k * TAU / 16.0 + _time
			var r: float = (1.0 - _bloom) * 40.0 + 6.0
			draw_rect(Rect2(origin.x + card.size.x / 2.0 + cos(angle) * r * 1.4, origin.y + card.size.y / 2.0 + sin(angle) * r, 1, 1), Color(VineStyle.WARM_GLOW if k % 2 == 0 else UiStyle.ACCENT, _bloom))


func _paper(at: Vector2, size_px: Vector2, fade: float, void_level: float) -> void:
	var fill: Color = PAPER.lerp(Color("07030f"), void_level)
	var edge: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level)
	var last_top: int = 0
	var last_bottom: int = 0
	for x: int in int(size_px.x):
		var d: int = mini(x, int(size_px.x) - 1 - x)
		var upper: int = int(VineStyle.rand(x + 5) * 2.0) + maxi(2 - d, 0)
		var lower: int = int(size_px.y) - int(VineStyle.rand(x + 55) * 2.0) - maxi(2 - d, 0)
		draw_rect(Rect2(at.x + x, at.y + upper, 1, lower - upper), Color(fill, 0.95 * fade))
		draw_rect(Rect2(at.x + x, at.y + minf(upper, last_top if x > 0 else upper), 1, (absf(upper - last_top) + 1) if x > 0 else 1.0), Color(edge, fade))
		draw_rect(Rect2(at.x + x, at.y + upper + 1, 1, 1), Color(UiStyle.ACCENT, 0.5 * fade))
		draw_rect(Rect2(at.x + x, at.y + minf(lower - 1, last_bottom - 1 if x > 0 else lower - 1.0), 1, (absf(lower - last_bottom) + 1) if x > 0 else 1.0), Color(edge.darkened(0.3), fade))
		last_top = upper
		last_bottom = lower
	VineStyle.leaf(self, at + Vector2(size_px.x - 3, 3), 1, -1, 3, Color(VineStyle.LEAF, fade), Color(VineStyle.LEAF_LIGHT, fade))


## The axe lesson (quest step "report back"): three pages that turn every few seconds: how to fell a tree, and what each kind of tree gives.
func _draw_chop_hint() -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6:
		return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	var page: int = int(_time / 5.0) % 3
	var titles: Array[String] = ["BÄUME FÄLLEN", "TANNEN UND WEIDEN", "DÄMMERBLÜTEN"]
	var pages: Array = [
		["AXT WÄHLEN: TASTE 4.", "MIT " + _action_label("action_primary") + " AUF EINEN BAUM", "SCHLAGEN, BIS ER FÄLLT."],
		["TANNE: HOLZ UND HARZ.", "WEIDE: WEIDENHOLZ UND", "SCHLEIERFÄDEN."],
		["BLÜTENHOLZ UND BLÜTEN.", "JEDE BAUMART GIBT", "ANDERES MATERIAL."],
	]
	PixelText.draw(self, titles[page], Vector2i(at + Vector2(9, 8)), Color(VineStyle.WARM_GLOW, fade), VineStyle.OUTLINE)
	var lines: Array = pages[page] as Array
	for i: int in lines.size():
		PixelText.draw(self, String(lines[i]), Vector2i(at + Vector2(9, 22 + i * 9)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	for i: int in 3:
		draw_rect(Rect2(at + Vector2(11 + i * 12, 55), Vector2(8, 3)), Color(UiStyle.ACCENT if i == page else UiStyle.TEXT_DIM, fade))
	if _bloom > 0:
		for i: int in 12:
			var angle: float = TAU * i / 12
			var p: Vector2 = at + Vector2(77, 33) + Vector2(cos(angle), sin(angle)) * (1 - _bloom) * 42
			draw_rect(Rect2(p.round(), Vector2.ONE), Color(VineStyle.WARM_GLOW, _bloom))


## The town lesson (quest steps "build a lamp post / a workshop"): three pages that turn every few seconds: the build mode, how to place and what stops it, building together.
func _draw_swim_hint() -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6:
		return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	PixelText.draw(self, "SCHWIMMEN", Vector2i(at + Vector2(9, 8)), Color(VineStyle.WARM_GLOW, fade), VineStyle.OUTLINE)
	var cap_w: int = VineStyle.key_cap(self, at + Vector2(9, 20), _action_label("sprint"), fade, 1.0 if InputManager.sprint_held() else 0.0, void_level)
	PixelText.draw(self, "KRAULEN: SCHNELL", Vector2i(at + Vector2(9 + cap_w + 6, 24)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	PixelText.draw(self, "DAS KOSTET AUSDAUER.", Vector2i(at + Vector2(9, 42)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	PixelText.draw(self, "KEIN BLINK IM WASSER.", Vector2i(at + Vector2(9, 51)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)


func _draw_notice_hint(journal: bool) -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6:
		return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	PixelText.draw(self, "ELLIES TAGEBUCH" if journal else "QUESTTAFEL", Vector2i(at + Vector2(9, 8)), Color(VineStyle.WARM_GLOW, fade), VineStyle.OUTLINE)
	var key: String = "J" if journal else _action_label("interact")
	var cap_w: int = VineStyle.key_cap(self, at + Vector2(9, 20), key, fade, _live if journal else 0.0, void_level)
	PixelText.draw(self, "ÖFFNET DAS BUCH." if journal else "LIEST DIE ZETTEL.", Vector2i(at + Vector2(9 + cap_w + 6, 24)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	var lines: PackedStringArray = PackedStringArray(["WÄHLE EINEN EINTRAG.", "DEIN FOKUS ERSCHEINT", "AM QUEST-AST."] if journal else ["ANGENOMMENE AUFTRÄGE", "STEHEN IM TAGEBUCH.", "ABGABE BEIM AUFTRAGGEBER."])
	for i: int in lines.size():
		PixelText.draw(self, lines[i], Vector2i(at + Vector2(9, 40 + i * 9)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)


func _draw_mist_hint() -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6:
		return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	PixelText.draw(self, "HEXENNEBEL", Vector2i(at + Vector2(9, 8)), Color(Color("a8ff6a"), fade), VineStyle.OUTLINE)
	PixelText.draw(self, "DER NEBEL ZEIGT DIR DINGE.", Vector2i(at + Vector2(9, 24)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	PixelText.draw(self, "NICHT ALLES IST WAHR.", Vector2i(at + Vector2(9, 33)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	PixelText.draw(self, "TRUG TUT DIR NICHTS.", Vector2i(at + Vector2(9, 47)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)


func _draw_build_hint() -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6:
		return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	var page: int = int(_time / 5.0) % 3
	var titles: Array[String] = ["BAUMODUS", "SETZEN", "GEMEINSAM"]
	var key: String = _action_label("build")
	var pages: Array = [
		["%s ÖFFNET DIE BAUKARTE." % key, "ZAHLEN ODER MAUSRAD", "WÄHLEN DAS TEIL."],
		["LINKSKLICK SETZT, R", "SPIEGELT. NUR IM LICHT", "KREIS DARF GEBAUT WERDEN."],
		["EINE BAUSTELLE WÄCHST,", "SOLANGE DU DANEBEN", "STEHST. ZU ZWEIT SCHNELLER."],
	]
	PixelText.draw(self, titles[page], Vector2i(at + Vector2(9, 8)), Color(VineStyle.WARM_GLOW, fade), VineStyle.OUTLINE)
	var lines: Array = pages[page] as Array
	for i: int in lines.size():
		PixelText.draw(self, String(lines[i]), Vector2i(at + Vector2(9, 22 + i * 9)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	for i: int in 3:
		draw_rect(Rect2(at + Vector2(11 + i * 12, 55), Vector2(8, 3)), Color(UiStyle.ACCENT if (i == page or (InputManager.build_open and i == 0)) else UiStyle.TEXT_DIM, fade))
	if _bloom > 0:
		for i: int in 12:
			var angle: float = TAU * i / 12
			var p: Vector2 = at + Vector2(77, 33) + Vector2(cos(angle), sin(angle)) * (1 - _bloom) * 42
			draw_rect(Rect2(p.round(), Vector2.ONE), Color(VineStyle.WARM_GLOW, _bloom))


## The workbench lesson (quest step "make a pickaxe"): go to Gustav's bench, pick the recipe, wait for the work to be done.
func _draw_craft_hint() -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6:
		return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	var page: int = int(_time / 5.0) % 3
	var titles: Array[String] = ["WERKBANK", "HERSTELLEN", "SPITZHACKE"]
	var pages: Array = [
		["GEH ZUR WERKBANK UND", "DRÜCKE " + _action_label("interact") + ", UM", "SIE ZU BENUTZEN."],
		["WÄHLE IM REITER FERTIGEN", "EIN REZEPT. ES BRAUCHT", "ROHSTOFFE AUS BEUTEL/LAGER."],
		["2 HOLZ UND 3 STEIN", "BRECHEN FELSEN UND", "ÖFFNEN DEN WEG IN DEN BERG."],
	]
	PixelText.draw(self, titles[page], Vector2i(at + Vector2(9, 8)), Color(VineStyle.WARM_GLOW, fade), VineStyle.OUTLINE)
	var lines: Array = pages[page] as Array
	for i: int in lines.size():
		PixelText.draw(self, String(lines[i]), Vector2i(at + Vector2(9, 22 + i * 9)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	for i: int in 3:
		draw_rect(Rect2(at + Vector2(11 + i * 12, 55), Vector2(8, 3)), Color(UiStyle.ACCENT if i == page else UiStyle.TEXT_DIM, fade))
	if _bloom > 0:
		for i: int in 12:
			var angle: float = TAU * i / 12
			var p: Vector2 = at + Vector2(77, 33) + Vector2(cos(angle), sin(angle)) * (1 - _bloom) * 42
			draw_rect(Rect2(p.round(), Vector2.ONE), Color(VineStyle.WARM_GLOW, _bloom))


func _draw_sword_hint() -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6: return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	var mode: String = _hint
	var player: Player = _quests.get_parent() as Player
	if mode == "combo" and player.attack.held_weapon != "sword_basic": mode = "equip_sword"
	var title: String = "DAS SCHWERT"
	var lines: Array[String] = ["GEHE ZUM SCHWERT.", "ES WIRD AUFGEHOBEN.", "VOLL? PLATZ IM RUCKSACK."]
	if mode == "equip_sword":
		title = "SCHWERT AUSRÜSTEN"
		lines = ["INVENTAR ÖFFNEN: " + _action_label("inventory"), "RECHTSKLICK AUF SCHWERT.", "DANN INVENTAR SCHLIESSEN."]
	elif mode == "combo":
		title = "ANGRIFFSKETTE: " + _action_label("action_primary")
		lines = ["DREIMAL IM RHYTHMUS.", "HIEB - GEGENHIEB - STICH", "PAUSE BEGINNT VON VORN."]
	PixelText.draw(self, title, Vector2i(at + Vector2(9,8)), Color(VineStyle.WARM_GLOW, fade), VineStyle.OUTLINE)
	for i: int in lines.size():
		PixelText.draw(self, lines[i], Vector2i(at + Vector2(9,22 + i*9)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	if mode == "combo":
		for i: int in 3:
			draw_rect(Rect2(at + Vector2(11 + i*41,55), Vector2(32,3)), Color(UiStyle.ACCENT if _quests.tutorial_combo > i else UiStyle.TEXT_DIM, fade))
	if _bloom > 0:
		for i: int in 12:
			var angle: float = TAU * i / 12
			var p: Vector2 = at + Vector2(77,33) + Vector2(cos(angle),sin(angle)) * (1 - _bloom) * 42
			draw_rect(Rect2(p.round(),Vector2.ONE), Color(VineStyle.WARM_GLOW, _bloom))

func _action_label(action: String) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			return "LMT" if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT else "RMT"
		if event is InputEventKey:
			var key: InputEventKey = event as InputEventKey
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != 0 else key.keycode).to_upper()
	return "?"

## The lake witch's lesson (quest "Der Ring am See", docs/seehexe_konzept.md 8): putting the stones into the staff, then the first spell.
func _draw_staff_hint(cast: bool) -> void:
	var g: float = _grow * _grow * (3 - 2 * _grow)
	var void_level: float = VineStyle.void_amount()
	var curve: Callable = func(x: float) -> float: return 6 + sin(x * 0.06) * 1.5
	VineStyle.branch(self, 0, WIDTH - 12, curve, 4, void_level, 12, _time, g)
	VineStyle.foliage(self, 0, WIDTH - 12, curve, 5, 130, void_level, 12, _time, g)
	if g < 0.6:
		return
	var at: Vector2 = Vector2(10, roundf(22 - (1 - g) * 20))
	var fade: float = clampf((g - 0.6) / 0.4, 0, 1)
	VineStyle.paper(self, Rect2(at, Vector2(WIDTH - 22, HEIGHT - 26)), fade, void_level)
	PixelText.draw(self, "ZAUBERN" if cast else "STEINE EINSETZEN", Vector2i(at + Vector2(9, 8)), Color(VineStyle.WARM_GLOW, fade), VineStyle.OUTLINE)
	var key: String = _action_label("action_primary") if cast else "LMT"
	var cap_w: int = VineStyle.key_cap(self, at + Vector2(9, 20), key, fade, 0.0, void_level)
	PixelText.draw(self, "MIT DEM STAB IN DER HAND" if cast else "STEIN AUF DEN STAB", Vector2i(at + Vector2(9 + cap_w + 6, 24)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
	var lines: PackedStringArray = PackedStringArray(["DEN STAB IN DER HOTBAR", "WÄHLEN. LEUCHTET DER", "KRISTALL, IST ER BEREIT."] if cast else ["IM RUCKSACK: STEIN NEHMEN,", "AUF DEN STAB KLICKEN.", "RMT AUF DEN STAB: HERAUS."])
	for i: int in lines.size():
		PixelText.draw(self, lines[i], Vector2i(at + Vector2(9, 40 + i * 9)), Color(UiStyle.TEXT, fade), VineStyle.OUTLINE)
