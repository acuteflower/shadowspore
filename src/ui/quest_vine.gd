class_name QuestVine
extends Control
## The current quest, top right under the money: a thin branch grows out of the right edge, a glowing bud hangs at its tip, under it the title (gold)
## with the distance to the goal (teal) and the task in light text, typed out letter by letter. When a step is done the bud flares, sparks fly and
## the old text withers away before the next one is written; with no quest the branch withdraws. At night the void creeps in from the tip.
## The branch follows the journal focus.

const LENGTH: float = 150.0
const BRANCH_Y: float = 8.0
const LINE_CHARS: int = 34
const TYPE_RATE: float = 38.0 ## letters per second

var _tracked: TrackedQuests
var _player: Node2D
var _time: float = 0.0
var _grow: float = 0.0 ## 0..1, the branch's length
var _title: String = ""
var _text: String = ""
var _typed: float = 0.0
var _wither: float = 0.0 ## 1 -> 0 while the old text fades before the next is written
var _pending_title: String = ""
var _pending_text: String = ""
var _flare: float = 0.0
var _sparks: float = 0.0
var _target: Vector2 = Vector2.INF
var _target_actor: Node2D
var _search: float = 0.0 ## radius in tiles of a search area (the map shows it): the goal is no exact place
var _has_quest: bool = false
var _tasks: Array = [] ## the jobs of a "tasks" step: {text, done, have, need, counter}
var _main_id: String = ""
var _deadline: String = ""
var _has_area: bool = false
var _journal_focus_bloom: bool = false
var _board_notice: Dictionary = {}
var _has_notice: bool = false
var _notice_grow: float = 0.0
var _notice_flare: float = 0.0
var _notice_sparks: float = 0.0
var _notice_y: float = 16.0
var _known_notice_ids: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(LENGTH + 24, 172)
	size = Vector2(LENGTH + 24, 172)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(player: Node, quests: QuestComponent, tracked: TrackedQuests = null) -> void:
	_player = player as Node2D
	_tracked = tracked
	if _tracked == null: ## without the list (a test): a plain one over the story quest alone
		_tracked = TrackedQuests.new()
		_tracked.quests = quests
		if player is Player:
			_tracked._player = player as Player
		add_child(_tracked)
	_tracked.changed.connect(_refresh.bind(false))
	if tracked == null:
		quests.changed.connect(_refresh.bind(false))
	quests.step_done.connect(func(id: String, _step: int) -> void:
		_flare_for("story:%s" % id))
	_tracked.finished.connect(_flare_for)
	_refresh(true)


func _flare_for(id: String) -> void:
	if id == _main_id:
		_flare = 1.0
		_sparks = 1.0


func _refresh(instant: bool) -> void:
	_board_notice = _tracked.story_board_notice() if _tracked != null else {}
	_has_notice = not _board_notice.is_empty()
	var current_notice_ids: Dictionary = {}
	var has_new_notice: bool = false
	for raw_oid: Variant in _board_notice.get("ids", []) as Array:
		var oid: int = int(raw_oid)
		current_notice_ids[oid] = true
		if not _known_notice_ids.has(oid):
			has_new_notice = true
	_known_notice_ids = current_notice_ids
	if instant:
		_notice_grow = 1.0 if _has_notice else 0.0
	elif has_new_notice:
		_notice_flare = 1.0
		_notice_sparks = 1.0
	var now: Dictionary = _tracked.focused()
	var previous: String = _main_id
	_main_id = String(now.get("id", ""))
	if InputManager.journal_open and _main_id != previous:
		_journal_focus_bloom = _main_id != "" and not bool(GameSettings.get_value("journal_still"))
	_deadline = TrackedQuests.deadline_text(now)
	_has_area = (now.get("area", Vector3.INF) as Vector3) != Vector3.INF
	_has_quest = not now.is_empty()
	if not _has_quest and has_new_notice and not instant:
		_flare = 1.0
		_sparks = 1.0
	_target = now.get("target", Vector2.INF) as Vector2
	_target_actor = now.get("target_actor") as Node2D
	_search = float(now.get("search", 0.0))
	_tasks = now.get("tasks", []) as Array
	if not _has_quest:
		_pending_title = ""
		_pending_text = ""
		return
	var text: String = String(now.text)
	var title: String = String(now.title)
	if instant or _main_id != previous:
		_pending_title = ""
		_pending_text = ""
		_wither = 0.0
		_title = title
		_text = text
		_typed = float(_text.length())
		return
	if (text != _text or title != _title) and (text != _pending_text or title != _pending_title):
		_pending_title = title
		_pending_text = text
		_wither = 1.0 if _text != "" else 0.0


func _process(delta: float) -> void:
	_time += delta
	if _journal_focus_bloom and not InputManager.journal_open and not InputManager.map_open:
		_journal_focus_bloom = false
		if _has_quest:
			_grow = minf(_grow, 0.75)
			_flare = 0.85
			_sparks = 0.55
	var want_branch: bool = _has_quest or _has_notice
	_grow = move_toward(_grow, 1.0 if want_branch else 0.0, delta / (1.3 if want_branch else 0.9))
	_notice_grow = move_toward(_notice_grow, 1.0 if _has_notice else 0.0, delta / (0.75 if _has_notice else 0.5))
	_flare = move_toward(_flare, 0.0, delta * 1.3)
	_sparks = move_toward(_sparks, 0.0, delta * 1.1)
	_notice_flare = move_toward(_notice_flare, 0.0, delta * 1.3)
	_notice_sparks = move_toward(_notice_sparks, 0.0, delta * 1.1)
	if _pending_text != "":
		_wither = move_toward(_wither, 0.0, delta * 3.5)
		if _wither <= 0.0:
			_title = _pending_title
			_text = _pending_text
			_pending_title = ""
			_pending_text = ""
			_typed = 0.0
	elif _grow > 0.6 and _has_quest:
		_typed = minf(_typed + TYPE_RATE * delta, float(_text.length()))
	visible = _grow > 0.0
	queue_redraw()


func _draw() -> void:
	if _grow <= 0.0:
		return
	var void_level: float = VineStyle.void_amount()
	var length: float = LENGTH * (_grow * _grow * (3.0 - 2.0 * _grow))
	draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1, 1)) ## drawn growing right, mirrored so it grows from the right edge
	for xi: int in int(length) + 1: ## the branch, thick at the screen edge, thin at the tip
		var u: float = xi / LENGTH
		var thick: int = 4 if u < 0.12 else (3 if u < 0.4 else (2 if u < 0.85 else 1))
		var y: float = roundf(BRANCH_Y + sin(xi * 0.07) * 1.5) - thick / 2
		var taken: float = VineStyle.infection(LENGTH - xi, void_level, xi / 2)
		draw_rect(Rect2(xi, y - 1, 1, thick + 2), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		draw_rect(Rect2(xi, y, 1, thick), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if xi % 3 != 1:
			draw_rect(Rect2(xi, y, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
	for k: int in 5: ## leaves
		var x: float = 16.0 + k * 26.0 + VineStyle.rand(k + 960) * 8.0
		if x > length - 4.0:
			continue
		var taken: float = VineStyle.infection(LENGTH - x, void_level, k)
		var up: int = -1 if k % 2 == 0 else 1
		VineStyle.leaf(self, Vector2(x, roundf(BRANCH_Y + sin(x * 0.07) * 1.5)) + Vector2(0, up * 2), 1, up, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken))
	var tip: Vector2 = Vector2(length, roundf(BRANCH_Y + sin(length * 0.07) * 1.5))
	var bud_taken: float = VineStyle.infection(0.0, void_level, 5)
	var pulse: float = 0.7 + 0.3 * sin(_time * 2.2)
	VineStyle.glow(self, tip, 6.0 + _flare * 8.0, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, bud_taken), (0.6 + _flare) * pulse * _grow)
	draw_rect(Rect2(tip, Vector2.ONE), VineStyle.PETAL)
	for offset: Vector2 in [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]:
		draw_rect(Rect2(tip + offset, Vector2.ONE), Color(VineStyle.WARM_GLOW, 0.8 * _grow))
	if _sparks > 0.0:
		for k: int in 7:
			var angle: float = k * TAU / 7.0 + _time * 2.0
			var r: float = (1.0 - _sparks) * 14.0 + 3.0
			draw_rect(Rect2(roundf(tip.x + cos(angle) * r), roundf(tip.y + sin(angle) * r), 1, 1), Color(VineStyle.WARM_GLOW, _sparks))
	if void_level > 0.05:
		VineStyle.tendril(self, Vector2(length * 0.6, BRANCH_Y), Vector2(0.4, 0.9).normalized(), int(3 + 5 * void_level), _time, 1)
	draw_set_transform(Vector2.ZERO)

	if _grow < 0.85:
		return
	var branch_alpha: float = clampf((_grow - 0.85) / 0.15, 0.0, 1.0)
	var right: int = int(size.x) - 12 ## text is right aligned under the branch, so it hangs from the edge
	var target_notice_top: float = 15.0
	if _has_quest:
		var text_alpha: float = branch_alpha * _wither_alpha()
		var title_color: Color = Color(VineStyle.WARM_GLOW, text_alpha)
		PixelText.draw(self, _title, Vector2i(right - PixelText.width(_title), 16), title_color, Color(VineStyle.OUTLINE, text_alpha))
		var target: Vector2 = _target_actor.global_position if is_instance_valid(_target_actor) and _target_actor.is_inside_tree() else _target
		if target != Vector2.INF and _player != null:
			var meters: String = "%d M" % roundi(_player.global_position.distance_to(target) / 16.0)
			if _search > 0.0:
				meters = "SUCHKREIS %d M" % roundi(_search)
			PixelText.draw(self, meters, Vector2i(right - PixelText.width(meters), 26), Color(UiStyle.ACCENT, text_alpha * 0.9), Color(VineStyle.OUTLINE, text_alpha))
		elif _has_area:
			PixelText.draw(self, "SUCHGEBIET", Vector2i(right - PixelText.width("SUCHGEBIET"), 26), Color(UiStyle.ACCENT, text_alpha), Color(VineStyle.OUTLINE, text_alpha))
		var lines: PackedStringArray = _wrap(_text.left(int(_typed)))
		for i: int in lines.size():
			PixelText.draw(self, lines[i], Vector2i(right - PixelText.width(lines[i]), 38 + i * 9), Color(UiStyle.TEXT, text_alpha), Color(VineStyle.OUTLINE, text_alpha))
		var task_y: int = 38 + lines.size() * 9 + 5
		for task: Dictionary in _tasks: ## the jobs of the step: a bud (lit when done), the words, a counter
			var done: bool = bool(task.done)
			var label: String = String(task.text)
			if bool(task.counter):
				label += "  %d/%d" % [int(task.have), int(task.need)]
			var tint: Color = Color(UiStyle.ACCENT if done else UiStyle.TEXT_DIM, text_alpha * (1.0 if done else 0.9))
			var width: int = PixelText.width(label)
			PixelText.draw(self, label, Vector2i(right - width, task_y), tint, Color(VineStyle.OUTLINE, text_alpha))
			var bud_at: Vector2 = Vector2(right - width - 7, task_y + 2)
			draw_rect(Rect2(bud_at, Vector2(3, 3)), Color(UiStyle.ACCENT if done else VineStyle.BARK_LIGHT, text_alpha))
			if done:
				VineStyle.glow(self, bud_at + Vector2(1, 1), 4.0, UiStyle.ACCENT, 0.4 * text_alpha)
			task_y += 10
		if int(_typed) < _text.length() and int(_time * 6.0) % 2 == 0 and not lines.is_empty(): ## a blinking bud where the writing goes on
			var last: int = lines.size() - 1
			draw_rect(Rect2(right - PixelText.width(lines[last]) - 4, 40 + last * 9, 2, 2), Color(UiStyle.ACCENT, text_alpha))
		if _deadline != "":
			var deadline: String = _deadline.to_upper()
			PixelText.draw(self, deadline, Vector2i(right - PixelText.width(deadline), task_y + 2), Color(UiStyle.TEXT_DIM, text_alpha), Color(VineStyle.OUTLINE, text_alpha))
		var full_lines: int = maxi(_wrap(_text).size(), lines.size())
		var stable_task_y: int = 38 + full_lines * 9 + 5 + _tasks.size() * 10
		var quest_bottom: int = stable_task_y + (11 if _deadline != "" else 0)
		target_notice_top = float(quest_bottom + 10)
	if _notice_grow <= 0.05 or absf(_notice_y - target_notice_top) > 48.0:
		_notice_y = target_notice_top
	else:
		_notice_y = move_toward(_notice_y, target_notice_top, 90.0 * get_process_delta_time())
	if _notice_grow > 0.01 and not _board_notice.is_empty():
		_draw_board_notice(roundf(_notice_y), right, branch_alpha, void_level)


func _draw_board_notice(top_y: float, right: int, branch_alpha: float, void_level: float) -> void:
	var ease_n: float = _notice_grow * _notice_grow * (3.0 - 2.0 * _notice_grow)
	var count: int = int(_board_notice.get("count", 1))
	var line1: String = "NEUE HAUPTQUEST" if count <= 1 else "%d NEUE HAUPTQUESTS" % count
	var board_pos: Vector2 = _board_notice.get("target", Vector2.INF) as Vector2
	var dist_txt: String = ("%d M" % roundi(_player.global_position.distance_to(board_pos) / 16.0)) if (board_pos != Vector2.INF and _player != null) else ""
	var row_texts: Array[Dictionary] = [{"text": line1, "color": VineStyle.WARM_GLOW}]
	var card_h: int = 26
	if not _has_quest:
		card_h = 35
		row_texts.append({"text": String(_board_notice.get("title", "SIEH AN DIE QUESTTAFEL")), "color": UiStyle.TEXT})
		row_texts.append({"text": "AN DER QUESTTAFEL", "color": UiStyle.TEXT_DIM, "dist": dist_txt})
	else:
		row_texts.append({"text": "AN DER QUESTTAFEL", "color": UiStyle.TEXT, "dist": dist_txt})
	var max_text_w: int = 0
	for row: Dictionary in row_texts:
		var w: int = PixelText.width(String(row.text))
		var dt: String = String(row.get("dist", ""))
		if dt != "":
			w += PixelText.width("  " + dt)
		max_text_w = maxi(max_text_w, w)
	var card_w: int = clampi(max_text_w + 35, 114, int(size.x) - 16)
	var card_top: float = top_y
	var thread_top: float = BRANCH_Y + 1.0
	if _has_quest:
		var twig_y: float = top_y
		var twig_span: float = float(card_w + 8)
		var twig_len: float = twig_span * ease_n
		draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1, 1))
		for xi: int in int(twig_len) + 1:
			var u: float = float(xi) / maxf(twig_span, 1.0)
			var thick: int = 2 if u < 0.45 else 1
			var y: float = roundf(twig_y + sin(xi * 0.09 + 1.1) * 1.0) - thick / 2
			var taken: float = VineStyle.infection(twig_span - xi, void_level, xi / 2 + 400)
			draw_rect(Rect2(xi, y - 1, 1, thick + 2), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
			draw_rect(Rect2(xi, y, 1, thick), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		for k: int in 2:
			var lx: float = 22.0 + float(k) * 42.0
			if lx <= twig_len - 4.0:
				var taken_l: float = VineStyle.infection(twig_span - lx, void_level, k + 710)
				var up: int = -1 if k % 2 == 0 else 1
				VineStyle.leaf(self, Vector2(lx, roundf(twig_y + sin(lx * 0.09 + 1.1) * 1.0)) + Vector2(0, up), 1, up, 2, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken_l), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken_l))
		var n_tip: Vector2 = Vector2(twig_len, roundf(twig_y + sin(twig_len * 0.09 + 1.1) * 1.0))
		var n_taken: float = VineStyle.infection(0.0, void_level, 715)
		var n_pulse: float = 0.7 + 0.3 * sin(_time * 2.8)
		VineStyle.glow(self, n_tip, 5.0 + _notice_flare * 7.0, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, n_taken), (0.65 + _notice_flare) * n_pulse * ease_n)
		draw_rect(Rect2(n_tip, Vector2.ONE), VineStyle.PETAL)
		for offset: Vector2 in [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]:
			draw_rect(Rect2(n_tip + offset, Vector2.ONE), Color(VineStyle.WARM_GLOW, 0.8 * ease_n))
		if _notice_sparks > 0.0:
			for k: int in 6:
				var angle: float = k * TAU / 6.0 + _time * 2.4
				var r: float = (1.0 - _notice_sparks) * 11.0 + 2.0
				draw_rect(Rect2(roundf(n_tip.x + cos(angle) * r), roundf(n_tip.y + sin(angle) * r), 1, 1), Color(VineStyle.WARM_GLOW, _notice_sparks))
		draw_set_transform(Vector2.ZERO)
		card_top = top_y + 5.0
		thread_top = top_y + 1.0
	if _notice_grow <= 0.3:
		return
	var card_alpha: float = branch_alpha * clampf((_notice_grow - 0.3) / 0.7, 0.0, 1.0)
	var card_rect: Rect2 = Rect2(float(right - card_w + 2), roundf(card_top - (1.0 - ease_n) * 3.0), float(card_w), float(card_h))
	var thread_color: Color = Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level), card_alpha)
	for tx: float in [card_rect.position.x + 14.0, card_rect.end.x - 14.0]:
		var th: float = maxf(card_rect.position.y + 2.0 - thread_top, 1.0)
		draw_rect(Rect2(roundf(tx), roundf(thread_top), 1.0, roundf(th)), thread_color)
	VineStyle.paper(self, card_rect, card_alpha, void_level, 43)
	draw_rect(Rect2(card_rect.end.x - 8.0, card_rect.position.y + 3.0, 3.0, 3.0), Color(Color("9e3550"), card_alpha))
	draw_rect(Rect2(card_rect.end.x - 7.0, card_rect.position.y + 4.0, 1.0, 1.0), Color(VineStyle.WARM_GLOW, card_alpha))
	var icon_at: Vector2 = Vector2(card_rect.position.x + 6.0, roundf(card_rect.position.y + (card_rect.size.y - 16.0) * 0.5))
	var glow_strength: float = (0.55 + _notice_flare * 0.65) * card_alpha * (0.75 + 0.25 * sin(_time * 2.6))
	VineStyle.glow(self, icon_at + Vector2(8, 8), 8.0 + _notice_flare * 5.0, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, void_level), glow_strength)
	var tex: Texture2D = BoardRules.story_icon_by_path(String(_board_notice.get("icon", "")))
	if tex != null:
		draw_texture_rect(tex, Rect2(icon_at, Vector2(16, 16)), false, Color(1, 1, 1, card_alpha))
	var text_x: int = int(card_rect.position.x) + 26
	var line_y: int = int(card_rect.position.y) + (5 if _has_quest else 5)
	for i: int in row_texts.size():
		var row: Dictionary = row_texts[i]
		var words: String = String(row.text)
		var col: Color = Color(row.color as Color, card_alpha)
		PixelText.draw(self, words, Vector2i(text_x, line_y + i * 9), col, Color(VineStyle.OUTLINE, card_alpha))
		var dt: String = String(row.get("dist", ""))
		if dt != "":
			var dx: int = text_x + PixelText.width(words + "  ")
			PixelText.draw(self, dt, Vector2i(dx, line_y + i * 9), Color(UiStyle.ACCENT, card_alpha), Color(VineStyle.OUTLINE, card_alpha))


func _wither_alpha() -> float:
	return 1.0 if _pending_text == "" else _wither


func _wrap(text: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var line: String = ""
	for word: String in text.split(" "):
		if line != "" and line.length() + 1 + word.length() > LINE_CHARS:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		lines.append(line)
	return lines
