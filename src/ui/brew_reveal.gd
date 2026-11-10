class_name BrewReveal
extends CanvasLayer
## The card when Esma has brewed (docs/alchemie_konzept.md): the room dims, a cauldron bubbles in the potion's colour while the ingredients drop in, then the potions rise
## out of the steam with a glassy chord: the vials, how many, the name and the tier (a full moon adds a silver shimmer and its line). Local, cosmetic, a few seconds;
## E / click / Esc closes it. Sounds: tools/audio_alchemy.py.

const BUILD: float = 1.0 ## seconds of bubbling before the potions rise
const STAY: float = 0.8
const FADE: float = 0.3
const AUTO_CLOSE: float = 6.0
const CARD: Vector2 = Vector2(210.0, 150.0)

var _type: String = "heal"
var _tier: int = 1
var _count: int = 1
var _moon: bool = false
var _view: Control
var _age: float = 0.0
var _closing: float = -1.0
var _revealed: bool = false
var _motes: Array[Dictionary] = [] ## {pos, vel, age, life, color}
var _voices: Dictionary = {}
var _plops: int = 0


static func present(tree: SceneTree, type: String, tier: int, count: int, moon: bool) -> BrewReveal:
	if tree.get_first_node_in_group("brew_reveal") != null:
		return null
	var reveal: BrewReveal = BrewReveal.new()
	reveal._type = type
	reveal._tier = tier
	reveal._count = count
	reveal._moon = moon
	tree.root.add_child(reveal)
	return reveal


func _ready() -> void:
	add_to_group("brew_reveal")
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	for sound: String in ["plop", "bubble", "brewed", "moon"]:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.stream = load("res://assets/audio/alchemy/%s.wav" % sound) as AudioStream
		voice.volume_db = -8.0
		add_child(voice)
		_voices[sound] = voice
	(_voices["bubble"] as AudioStreamPlayer).play()


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if not _revealed:
		_age = BUILD ## skip the bubbling
	elif _age >= BUILD + STAY and _closing < 0.0:
		_closing = 0.0


func _process(delta: float) -> void:
	_age += delta
	var drops: int = mini(int(_age / (BUILD / 4.0)), 3)
	while _plops < drops and not _revealed:
		_plops += 1
		(_voices["plop"] as AudioStreamPlayer).play()
	if not _revealed and _age >= BUILD:
		_revealed = true
		(_voices["bubble"] as AudioStreamPlayer).stop()
		(_voices["brewed"] as AudioStreamPlayer).play()
		if _moon:
			(_voices["moon"] as AudioStreamPlayer).play()
		for i: int in 30:
			var heading: float = -PI / 2.0 + randf_range(-1.1, 1.1)
			_motes.append({"pos": _centre() + Vector2(0, -6), "vel": Vector2.from_angle(heading) * randf_range(30.0, 90.0), "age": 0.0, "life": randf_range(0.5, 1.1),
				"color": AlchemyRules.color(_type).lerp(Color.WHITE, randf() * 0.5) if not (_moon and i % 3 == 0) else Color("dfe8ff")})
	if randf() < delta * (24.0 if not _revealed else 8.0): ## steam and glints keep rising
		_motes.append({"pos": _centre() + Vector2(randf_range(-14.0, 14.0), 14.0), "vel": Vector2(randf_range(-6.0, 6.0), randf_range(-30.0, -12.0)), "age": 0.0, "life": randf_range(0.6, 1.2),
			"color": Color(AlchemyRules.light(_type), 0.6)})
	for i: int in range(_motes.size() - 1, -1, -1):
		var m: Dictionary = _motes[i]
		m.age = float(m.age) + delta
		if float(m.age) >= float(m.life):
			_motes.remove_at(i)
			continue
		m.vel = (m.vel as Vector2) * exp(-2.0 * delta) + Vector2(0.0, -10.0 * delta)
		m.pos = (m.pos as Vector2) + (m.vel as Vector2) * delta
	if _age >= BUILD + AUTO_CLOSE and _closing < 0.0:
		_closing = 0.0
	if _closing >= 0.0:
		_closing += delta
		if _closing >= FADE:
			queue_free()
			return
	_view.queue_redraw()


func _centre() -> Vector2:
	return (get_viewport().get_visible_rect().size / 2.0).round()


func _t(at: Vector2, text: String, color: Color, scale: float = 1.0) -> void:
	var width: float = float(PixelText.width(text)) * scale
	var origin: Vector2 = (at - Vector2(width / 2.0, 0.0)).round()
	_view.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	PixelText.draw(_view, text, Vector2i.ZERO, color, UiStyle.OUTLINE)
	_view.draw_set_transform(Vector2.ZERO)


func _draw_view() -> void:
	var fade: float = clampf(_age / 0.25, 0.0, 1.0) * (1.0 - clampf(_closing / FADE, 0.0, 1.0) if _closing >= 0.0 else 1.0)
	var full: Vector2 = get_viewport().get_visible_rect().size
	_view.draw_rect(Rect2(Vector2.ZERO, full), Color(0.02, 0.01, 0.05, 0.55 * fade))
	var middle: Vector2 = _centre()
	var card: Rect2 = Rect2(middle - CARD / 2.0, CARD)
	VineStyle.paper(_view, card, fade, VineStyle.void_amount(), 7)
	var tone: Color = AlchemyRules.color(_type)
	var cauldron: Vector2 = middle + Vector2(0, -8)
	VineStyle.glow(_view, cauldron + Vector2(0, -6), 30.0, tone, 0.45 * fade)
	# the cauldron: a dark round pot with a lit rim and the brew bubbling in it
	for row: int in 14:
		var half: float = 16.0 * sqrt(maxf(1.0 - pow(float(row - 2) / 12.0, 2.0), 0.0))
		_view.draw_rect(Rect2(Vector2(cauldron.x - half, cauldron.y + float(row)).round(), Vector2(roundf(half * 2.0), 1)), Color(Color("1d1530").lerp(Color("3a2c58"), 1.0 - float(row) / 14.0), fade))
	_view.draw_rect(Rect2(cauldron + Vector2(-17, -1), Vector2(34, 2)), Color("5c4a86", fade))
	_view.draw_rect(Rect2(cauldron + Vector2(-15, -2), Vector2(30, 2)), Color(tone.darkened(0.2), fade))
	for k: int in 5: ## bubbles on the brew
		var phase: float = fposmod(_age * (1.6 + 0.3 * float(k)) + float(k) * 0.37, 1.0)
		var at: Vector2 = cauldron + Vector2(-12.0 + float(k) * 6.0, -2.0 - phase * 3.0)
		_view.draw_rect(Rect2(at.round(), Vector2(2, 2)), Color(AlchemyRules.light(_type), (1.0 - phase) * fade))
	if not _revealed: ## ingredients drop in
		for k: int in 3:
			var at_time: float = float(k) * BUILD / 4.0
			var u: float = clampf((_age - at_time) / 0.25, 0.0, 1.0)
			if u > 0.0 and u < 1.0:
				_view.draw_rect(Rect2((cauldron + Vector2(-6.0 + float(k) * 6.0, -30.0 + 28.0 * u * u)).round(), Vector2(3, 3)), Color("8ad48a", fade))
		_t(middle + Vector2(0, 30), ".".repeat(1 + int(_age * 4.0) % 3), Color(UiStyle.TEXT_DIM, fade), 2.0)
		_draw_motes(fade)
		return
	var since: float = _age - BUILD
	var rise: float = 1.0 - exp(-since * 6.0)
	var icon: Texture2D = Items.icon({"id": AlchemyRules.item_id(_type, _tier)})
	var shown: int = mini(_count, 4)
	for k: int in shown: ## the vials float up out of the steam
		var x: float = float(k) - float(shown - 1) / 2.0
		var at: Vector2 = cauldron + Vector2(x * 20.0, -34.0 * rise + sin(_age * 3.0 + float(k)) * 1.5)
		if icon != null:
			_view.draw_texture_rect(icon, Rect2((at - Vector2(12, 12)).round(), Vector2(24, 24)), false, Color(1, 1, 1, fade * rise))
	if since < 0.3:
		_view.draw_rect(Rect2(Vector2.ZERO, full), Color(Color.WHITE, (1.0 - since / 0.3) * 0.35))
	_draw_motes(fade)
	var pop: float = 1.0 + 0.5 * exp(-since * 9.0)
	_t(middle + Vector2(0, 16), "%d X" % _count, Color(tone, fade), 2.0 * pop)
	_t(middle + Vector2(0, 34), String(DataRegistry.get_entry("items", AlchemyRules.item_id(_type, _tier)).get("name", "")).to_upper(), Color(Color("d9b25f"), fade))
	_t(middle + Vector2(0, 44), "STUFE %s  %s" % [AlchemyRules.roman(_tier), AlchemyRules.tier_name(_tier, _type)], Color(tone.lightened(0.2), fade))
	if _moon:
		_t(middle + Vector2(0, 54), "DER VOLLMOND HAT MITGERÜHRT", Color(Color("dfe8ff"), fade * (0.7 + 0.3 * sin(_age * 3.0))))
	if _age >= BUILD + STAY and _closing < 0.0:
		_t(Vector2(middle.x, card.end.y - 11.0), "E WEITER", Color(UiStyle.TEXT_DIM, fade * (0.6 + 0.4 * sin(_age * 4.0))))


func _draw_motes(fade: float) -> void:
	for m: Dictionary in _motes:
		var k: float = float(m.age) / float(m.life)
		_view.draw_rect(Rect2((m.pos as Vector2).round(), Vector2.ONE), Color(m.color as Color, (m.color as Color).a * (1.0 - k) * fade))
