class_name StoneReveal
extends CanvasLayer
## The card when Ilva refreshes raw stones (LÄUTERN, docs/seehexe_konzept.md 14): the room dims, the raw stone trembles in her hands while its crust flakes off,
## then a flash and what it hid since it was found: the stones (up to eight shown), the best one named with its tier in its rarity colour (tier III and up rings a
## longer chord). Local, cosmetic, a few seconds; E / click / Esc closes it. Sounds: the refine card's (assets/audio/refine).

const BUILD: float = 1.1 ## seconds of flaking before the answer
const STAY: float = 0.8
const FADE: float = 0.3
const AUTO_CLOSE: float = 7.0
const CARD: Vector2 = Vector2(220.0, 150.0)
const SHOWN: int = 8

var _raw: String = ""
var _stones: Array[String] = []
var _best: String = ""
var _view: Control
var _age: float = 0.0
var _closing: float = -1.0
var _revealed: bool = false
var _motes: Array[Dictionary] = [] ## {pos, vel, age, life, color}
var _voices: Dictionary = {}


static func present(tree: SceneTree, raw: String, stones: Array) -> StoneReveal:
	if tree.get_first_node_in_group("stone_reveal") != null or stones.is_empty():
		return null
	var reveal: StoneReveal = StoneReveal.new()
	reveal._raw = raw
	for s: Variant in stones:
		reveal._stones.append(String(s))
	reveal._best = best_of(reveal._stones)
	tree.root.add_child(reveal)
	return reveal


## The highest tier among `stones` (the first of them on a tie).
static func best_of(stones: Array[String]) -> String:
	var best: String = ""
	for s: String in stones:
		if best == "" or CrystalRules.tier_of(s) > CrystalRules.tier_of(best):
			best = s
	return best


func _ready() -> void:
	add_to_group("stone_reveal")
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	for sound: String in ["ember", "success", "perfect"]:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.stream = load("res://assets/audio/refine/%s.wav" % sound) as AudioStream
		voice.volume_db = -8.0
		add_child(voice)
		_voices[sound] = voice
	(_voices["ember"] as AudioStreamPlayer).play()


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if not _revealed:
		_age = BUILD ## skip the flaking
	elif _age >= BUILD + STAY and _closing < 0.0:
		_closing = 0.0


func _tone() -> Color:
	return Items.rarity_color({"id": _best})


func _process(delta: float) -> void:
	_age += delta
	var middle: Vector2 = _centre() + Vector2(0, -12)
	if not _revealed and _age >= BUILD:
		_revealed = true
		(_voices["ember"] as AudioStreamPlayer).stop()
		(_voices["perfect" if CrystalRules.tier_of(_best) >= 3 else "success"] as AudioStreamPlayer).play()
		for i: int in 34:
			_motes.append({"pos": middle, "vel": Vector2.from_angle(randf() * TAU) * randf_range(30.0, 95.0), "age": 0.0, "life": randf_range(0.5, 1.1),
				"color": _tone().lerp(Color.WHITE, randf() * 0.5)})
	if not _revealed and randf() < delta * 26.0: ## flakes of crust
		_motes.append({"pos": middle + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 6.0)), "vel": Vector2(randf_range(-30.0, 30.0), randf_range(-40.0, -5.0)), "age": 0.0,
			"life": randf_range(0.4, 0.8), "color": Color("8d86a8") if randf() < 0.7 else Color("cfe9ff")})
	for i: int in range(_motes.size() - 1, -1, -1):
		var m: Dictionary = _motes[i]
		m.age = float(m.age) + delta
		if float(m.age) >= float(m.life):
			_motes.remove_at(i)
			continue
		m.vel = (m.vel as Vector2) * exp(-2.2 * delta) + Vector2(0.0, 40.0 * delta)
		m.pos = (m.pos as Vector2) + (m.vel as Vector2) * delta
	if _age >= BUILD + AUTO_CLOSE and _closing < 0.0:
		_closing = 0.0
	if _closing >= 0.0:
		_closing += delta
		if _closing >= FADE:
			queue_free()
			return
	_view.queue_redraw()


func _draw_view() -> void:
	var fade: float = clampf(_age / 0.25, 0.0, 1.0) * (1.0 - clampf(_closing / FADE, 0.0, 1.0) if _closing >= 0.0 else 1.0)
	var full: Vector2 = get_viewport().get_visible_rect().size
	_view.draw_rect(Rect2(Vector2.ZERO, full), Color(0.02, 0.01, 0.05, 0.55 * fade))
	var middle: Vector2 = _centre()
	var card: Rect2 = Rect2(middle - CARD / 2.0, CARD)
	VineStyle.paper(_view, card, fade, VineStyle.void_amount(), 11)
	var stage: Vector2 = middle + Vector2(0, -12)
	if not _revealed: ## the raw stone trembles harder and harder
		var shake: float = 1.0 + 2.0 * (_age / BUILD)
		var at: Vector2 = stage + Vector2(sin(_age * 47.0) * shake, cos(_age * 39.0) * shake * 0.5)
		VineStyle.glow(_view, stage, 18.0 + 8.0 * _age / BUILD, Color("cfe9ff"), 0.35 * fade * _age / BUILD)
		var raw_icon: Texture2D = Items.icon({"id": _raw})
		if raw_icon != null:
			_view.draw_texture_rect(raw_icon, Rect2((at - Vector2(16, 16)).round(), Vector2(32, 32)), false, Color(1, 1, 1, fade))
		_t(middle + Vector2(0, 26), "ILVA FRISCHT AUF" + ".".repeat(1 + int(_age * 4.0) % 3), Color(UiStyle.TEXT_DIM, fade))
		_draw_motes(fade)
		return
	var since: float = _age - BUILD
	var rise: float = 1.0 - exp(-since * 6.0)
	VineStyle.glow(_view, stage, 30.0, _tone(), 0.4 * fade)
	var shown: int = mini(_stones.size(), SHOWN)
	var size: float = 24.0 if shown <= 4 else 18.0
	for k: int in shown:
		var x: float = float(k) - float(shown - 1) / 2.0
		var at: Vector2 = stage + Vector2(x * (size + 2.0), -6.0 * rise + sin(_age * 3.0 + float(k)) * 1.2)
		var icon: Texture2D = Items.icon({"id": _stones[k]})
		if icon != null:
			_view.draw_texture_rect(icon, Rect2((at - Vector2(size, size) / 2.0).round(), Vector2(size, size)), false, Color(1, 1, 1, fade * rise))
	if since < 0.3:
		_view.draw_rect(Rect2(Vector2.ZERO, full), Color(Color.WHITE, (1.0 - since / 0.3) * 0.35))
	_draw_motes(fade)
	if _stones.size() > SHOWN:
		_t(stage + Vector2(0, 16), "+%d" % (_stones.size() - SHOWN), Color(UiStyle.TEXT_DIM, fade))
	var pop: float = 1.0 + 0.5 * exp(-since * 9.0)
	var tier: int = CrystalRules.tier_of(_best)
	_t(middle + Vector2(0, 16), "STUFE %s" % AlchemyRules.roman(tier), Color(_tone(), fade), 2.0 * pop)
	_t(middle + Vector2(0, 34), String(DataRegistry.get_entry("items", _best).get("name", _best)).to_upper(), Color(Color("d9b25f"), fade))
	var line: String = "DAS HAT DEIN STEIN VERBORGEN" if _stones.size() == 1 else "%d STEINE, DER BESTE OBEN" % _stones.size()
	_t(middle + Vector2(0, 44), line, Color(_tone().lightened(0.2), fade))
	if _age >= BUILD + STAY and _closing < 0.0:
		_t(Vector2(middle.x, card.end.y - 11.0), "E WEITER", Color(UiStyle.TEXT_DIM, fade * (0.6 + 0.4 * sin(_age * 4.0))))


func _draw_motes(fade: float) -> void:
	for m: Dictionary in _motes:
		var k: float = float(m.age) / float(m.life)
		_view.draw_rect(Rect2((m.pos as Vector2).round(), Vector2.ONE), Color(m.color as Color, (m.color as Color).a * (1.0 - k) * fade))


func _centre() -> Vector2:
	return (get_viewport().get_visible_rect().size / 2.0).round()


func _t(at: Vector2, text: String, color: Color, scale: float = 1.0) -> void:
	var width: float = float(PixelText.width(text)) * scale
	var origin: Vector2 = (at - Vector2(width / 2.0, 0.0)).round()
	_view.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	PixelText.draw(_view, text, Vector2i.ZERO, color, UiStyle.OUTLINE)
	_view.draw_set_transform(Vector2.ZERO)
