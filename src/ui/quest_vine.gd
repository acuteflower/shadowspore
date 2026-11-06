class_name QuestVine
extends Control
## The current quest, top right under the money: a thin branch grows out of the right edge, a glowing bud hangs at its tip, under it the title (gold)
## with the distance to the goal (teal) and the task in light text, typed out letter by letter. When a step is done the bud flares, sparks fly and
## the old text withers away before the next one is written; with no quest the branch withdraws. At night the void creeps in from the tip.

const LENGTH: float = 150.0
const BRANCH_Y: float = 8.0
const LINE_CHARS: int = 34
const TYPE_RATE: float = 38.0 ## letters per second

var _quests: QuestComponent
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
var _search: float = 0.0 ## radius in tiles of a search area (the map shows it): the goal is no exact place
var _has_quest: bool = false
var _tasks: Array = [] ## the jobs of a "tasks" step: {text, done, have, need, counter}


func _ready() -> void:
	custom_minimum_size = Vector2(LENGTH + 24, 130)
	size = Vector2(LENGTH + 24, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(player: Node, quests: QuestComponent) -> void:
	_player = player as Node2D
	_quests = quests
	quests.changed.connect(_refresh.bind(false))
	quests.step_done.connect(func(_q: String, _s: int) -> void:
		_flare = 1.0
		_sparks = 1.0)
	_refresh(true)


func _refresh(instant: bool) -> void:
	var now: Dictionary = _quests.current()
	_has_quest = not now.is_empty()
	_target = now.get("target", Vector2.INF) as Vector2
	_search = float(now.get("search", 0.0))
	_tasks = now.get("tasks", []) as Array
	if not _has_quest:
		_pending_title = ""
		_pending_text = ""
		return
	var text: String = String(now.text)
	var title: String = String(now.title)
	if instant:
		_title = title
		_text = text
		_typed = 0.0
		return
	if text != _text or title != _title:
		_pending_title = title
		_pending_text = text
		_wither = 1.0 if _text != "" else 0.0


func _process(delta: float) -> void:
	_time += delta
	_grow = move_toward(_grow, 1.0 if _has_quest else 0.0, delta / (1.3 if _has_quest else 0.9))
	_flare = move_toward(_flare, 0.0, delta * 1.3)
	_sparks = move_toward(_sparks, 0.0, delta * 1.1)
	if _pending_text != "":
		_wither = move_toward(_wither, 0.0, delta * 3.5)
		if _wither <= 0.0:
			_title = _pending_title
			_text = _pending_text
			_pending_title = ""
			_pending_text = ""
			_typed = 0.0
	elif _grow > 0.6:
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
	var text_alpha: float = clampf((_grow - 0.85) / 0.15, 0.0, 1.0) * (1.0 - (1.0 - _wither) * 0.0) * _wither_alpha()
	var right: int = int(size.x) - 12 ## text is right aligned under the branch, so it hangs from the edge
	var title_color: Color = Color(VineStyle.WARM_GLOW, text_alpha)
	PixelText.draw(self, _title, Vector2i(right - PixelText.width(_title), 16), title_color, Color(VineStyle.OUTLINE, text_alpha))
	if _target != Vector2.INF and _player != null:
		var meters: String = "%d M" % roundi(_player.global_position.distance_to(_target) / 16.0)
		if _search > 0.0:
			meters = "SUCHKREIS %d M" % roundi(_search)
		PixelText.draw(self, meters, Vector2i(right - PixelText.width(meters), 26), Color(UiStyle.ACCENT, text_alpha * 0.9), Color(VineStyle.OUTLINE, text_alpha))
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
