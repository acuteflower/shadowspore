class_name QuestVine
extends Control
## The current quest, top right under the money: a thin branch grows out of the right edge, a glowing bud hangs at its tip, under it the title (gold)
## with the distance to the goal (teal) and the task in light text, typed out letter by letter. When a step is done the bud flares, sparks fly and
## the old text withers away before the next one is written; with no quest the branch withdraws. At night the void creeps in from the tip.
## It shows `TrackedQuests.entries()`: the story quest, or (without one) the first quest-board notice the player took, as the main branch; the other notices hang under it as
## small twigs (a bud, the goal with its count, a stub of bark at the edge), up to three, then "+N". A twig grows out when a notice is taken, flares when it is handed in and fades when it runs out.

const LENGTH: float = 150.0
const BRANCH_Y: float = 8.0
const LINE_CHARS: int = 34
const TYPE_RATE: float = 38.0 ## letters per second
const MAX_SHOWN: int = 4 ## the main entry and up to three twigs

var _quests: QuestComponent
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
var _search: float = 0.0 ## radius in tiles of a search area (the map shows it): the goal is no exact place
var _has_quest: bool = false
var _tasks: Array = [] ## the jobs of a "tasks" step: {text, done, have, need, counter}
var _main_id: String = ""
var _last_twigs: Array[Dictionary] = []
var _twigs: Array[Dictionary] = [] ## entries hanging under the main one (at most MAX_SHOWN - 1)
var _extra: int = 0 ## entries beyond what is shown
var _twig_grow: Dictionary = {} ## entry id -> 0..1, how far a twig has grown out
var _dying: Array[Dictionary] = [] ## {entry, t, done}: twigs that left the list, fading
var _done_ids: Dictionary = {} ## entry id -> true for entries that were handed in (their twig flares instead of just fading)


func _ready() -> void:
	custom_minimum_size = Vector2(LENGTH + 24, 130)
	size = Vector2(LENGTH + 24, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(player: Node, quests: QuestComponent, tracked: TrackedQuests = null) -> void:
	_player = player as Node2D
	_quests = quests
	_tracked = tracked
	if _tracked == null: ## without the list (a test): a plain one over the story quest alone
		_tracked = TrackedQuests.new()
		_tracked.quests = quests
		add_child(_tracked)
	_tracked.changed.connect(_refresh.bind(false))
	quests.changed.connect(_refresh.bind(false))
	quests.step_done.connect(func(_q: String, _s: int) -> void:
		_flare = 1.0
		_sparks = 1.0)
	_tracked.finished.connect(func(id: String) -> void:
		_done_ids[id] = true
		if id == _main_id:
			_flare = 1.0
			_sparks = 1.0)
	_refresh(true)


func _refresh(instant: bool) -> void:
	var list: Array[Dictionary] = _tracked.entries()
	var now: Dictionary = list[0] if not list.is_empty() else {}
	_main_id = String(now.get("id", ""))
	_twigs = []
	for i: int in range(1, mini(list.size(), MAX_SHOWN)):
		_twigs.append(list[i])
	_extra = maxi(list.size() - MAX_SHOWN, 0)
	var live: Dictionary = {}
	for twig: Dictionary in _twigs:
		live[String(twig.id)] = true
		if not _twig_grow.has(String(twig.id)):
			_twig_grow[String(twig.id)] = 1.0 if instant else 0.0
	for key: String in _twig_grow.keys():
		if not live.has(key):
			_twig_grow.erase(key)
			for old: Dictionary in _last_twigs:
				if String(old.id) == key:
					_dying.append({"entry": old, "t": 0.0, "done": _done_ids.has(key)})
	_last_twigs = _twigs.duplicate()
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
	for key: String in _twig_grow.keys():
		_twig_grow[key] = move_toward(float(_twig_grow[key]), 1.0, delta * 2.4)
	for i: int in range(_dying.size() - 1, -1, -1):
		_dying[i]["t"] = float(_dying[i].t) + delta
		if float(_dying[i].t) > 1.0:
			_dying.remove_at(i)
	visible = _grow > 0.0 or not _dying.is_empty()
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
	_draw_twigs(task_y + 6, maxf(text_alpha, 0.0), right)


## The other quests: one line each under the main entry. A bark stub at the edge, a bud (cream for a fetch, red for a hunt, teal when it can be handed in), the goal and its count.
func _draw_twigs(top: int, alpha: float, right: int) -> void:
	var y: int = top
	for twig: Dictionary in _twigs:
		var grown: float = float(_twig_grow.get(String(twig.id), 1.0))
		_draw_twig(twig, y, alpha * grown, right, (1.0 - grown) * 26.0, 0.0, false)
		y += 11
	for gone: Dictionary in _dying:
		var t: float = float(gone.t)
		_draw_twig(gone.entry as Dictionary, y, alpha * (1.0 - t), right, t * 8.0, t, bool(gone.done))
		y += 11
	if _extra > 0:
		var more: String = "+%d" % _extra
		PixelText.draw(self, more, Vector2i(right - PixelText.width(more), y + 1), Color(UiStyle.TEXT_DIM, alpha * 0.8), Color(VineStyle.OUTLINE, alpha))


func _draw_twig(twig: Dictionary, y: int, alpha: float, right: int, slide: float, burst: float, handed_in: bool) -> void:
	if alpha <= 0.01:
		return
	var ready: bool = bool(twig.ready)
	var label: String
	if ready:
		label = "%s > %s" % [String(twig.label), String(twig.giver_name)]
	else:
		label = "%s %d/%d" % [String(twig.label), int(twig.have), int(twig.need)]
	var kind: Color = Color("d0566a") if String(twig.kind) == BoardRules.KILL else Color("e8dcc0")
	var urgent: bool = not ready and int(twig.days_left) >= 0 and int(twig.days_left) <= 1
	var tone: Color = UiStyle.ACCENT if ready else (Color("e0788a") if urgent else UiStyle.TEXT_DIM)
	var width: int = PixelText.width(label)
	var x: int = right - width + int(slide)
	draw_rect(Rect2(int(size.x) - 9 + slide, y + 2, 9, 4), Color(VineStyle.OUTLINE, alpha)) ## the stub of bark at the edge
	draw_rect(Rect2(int(size.x) - 9 + slide, y + 3, 9, 2), Color(VineStyle.BARK, alpha))
	draw_rect(Rect2(int(size.x) - 9 + slide, y + 3, 9, 1), Color(VineStyle.BARK_LIGHT, alpha * 0.8))
	PixelText.draw(self, label, Vector2i(x, y), Color(tone, alpha * (1.0 if ready else 0.95)), Color(VineStyle.OUTLINE, alpha))
	var bud: Vector2 = Vector2(x - 6, y + 1)
	if bool(twig.get("urgent", false)) and not ready: ## the clock of a rush notice: a ring round the bud that eats itself up and flickers red in the last fifth
		var left: float = float(twig.get("urgent_left", 1.0))
		var flicker: float = 1.0 if left > 0.2 else (0.55 + 0.45 * sin(_time * 14.0))
		var steps: int = 16
		for s: int in steps:
			if float(s) / float(steps) > left:
				break
			var angle: float = -PI / 2.0 + float(s) * TAU / float(steps)
			draw_rect(Rect2(roundf(bud.x + 1.0 + cos(angle) * 5.0), roundf(bud.y + 1.0 + sin(angle) * 5.0), 1, 1), Color("e0788a", alpha * flicker))
	draw_rect(Rect2(bud - Vector2.ONE, Vector2(5, 5)), Color(VineStyle.OUTLINE, alpha * 0.9))
	draw_rect(Rect2(bud, Vector2(3, 3)), Color(UiStyle.ACCENT if ready else kind, alpha))
	if ready:
		VineStyle.glow(self, bud + Vector2(1, 1), 5.0 + 1.5 * sin(_time * 4.0), UiStyle.ACCENT, 0.45 * alpha)
	if handed_in and burst > 0.0: ## handed in: a ring of sparks leaves the bud
		for k: int in 6:
			var angle: float = float(k) * TAU / 6.0 + burst * 2.0
			draw_rect(Rect2(roundf(bud.x + 1.0 + cos(angle) * burst * 12.0), roundf(bud.y + 1.0 + sin(angle) * burst * 12.0), 1, 1), Color(UiStyle.ACCENT, (1.0 - burst) * alpha))


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
