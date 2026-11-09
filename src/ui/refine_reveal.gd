class_name RefineReveal
extends CanvasLayer
## The moment of truth when Torben hands a refined weapon back (docs/refinement_konzept.md): the room dims, the weapon glows and shakes on the anvil's heat while an ember sound swells,
## then the answer: a success is a white flash, a ring of light in the colour of the level, a shower of sparks, the new level and what it gives (a milestone rings a longer chord); a failure
## is a dull flash, cracks across the iron, grey puffs, "MISSLUNGEN", the Glut it leaves and the iron that comes back. Local, cosmetic, a few seconds; E / click / Esc closes it.

const BUILD: float = 0.95 ## seconds of heating before the answer
const STAY: float = 1.5 ## the card cannot be closed before the answer has sunk in
const FADE: float = 0.3
const AUTO_CLOSE: float = 9.0
const CARD: Vector2 = Vector2(220.0, 176.0)
const SOUNDS: Array[String] = ["ember", "success", "perfect", "fail"]

var _before: Dictionary = {}
var _after: Dictionary = {}
var _success: bool = false
var _refund: Dictionary = {}
var _view: Control
var _age: float = 0.0
var _closing: float = -1.0
var _revealed: bool = false
var _sparks: Array[Dictionary] = [] ## {pos, vel, age, life, color, size}
var _voices: Dictionary = {}
var _milestone: Dictionary = {}


## Shows the reveal over everything (the shop window included). `before` is the weapon as it was handed in, `after` as it comes back.
static func present(tree: SceneTree, before: Dictionary, after: Dictionary, success: bool, refund: Dictionary) -> RefineReveal:
	if tree.get_first_node_in_group("refine_reveal") != null:
		return null
	var reveal: RefineReveal = RefineReveal.new()
	reveal._before = before
	reveal._after = after
	reveal._success = success
	reveal._refund = refund
	tree.root.add_child(reveal)
	return reveal


func _ready() -> void:
	add_to_group("refine_reveal")
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	for sound: String in SOUNDS:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.stream = load("res://assets/audio/refine/%s.wav" % sound) as AudioStream
		voice.volume_db = -7.0
		add_child(voice)
		_voices[sound] = voice
	for m: Dictionary in RefineRules.milestones(Items.refine(_after)):
		if _success and int(m.level) == Items.refine(_after):
			_milestone = m
	(_voices["ember"] as AudioStreamPlayer).play()


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled() ## nothing under the card hears a key while it stands
	if _age >= BUILD + STAY and _closing < 0.0:
		_closing = 0.0


func _process(delta: float) -> void:
	_age += delta
	if not _revealed and _age >= BUILD:
		_revealed = true
		_burst()
	if _revealed:
		_emit_trickle(delta)
	_update_sparks(delta)
	if _age >= AUTO_CLOSE and _closing < 0.0:
		_closing = 0.0
	if _closing >= 0.0:
		_closing += delta
		if _closing >= FADE:
			queue_free()
			return
	_view.queue_redraw()


func _centre() -> Vector2:
	return (get_viewport().get_visible_rect().size / 2.0).round()


func _tone() -> Color:
	return RefineStyle.color(Items.refine(_after)) if _success else Color("e0556e")


## The answer: sound, flash, a ring and a shower of sparks (or cracks and smoke).
func _burst() -> void:
	(_voices["ember"] as AudioStreamPlayer).stop()
	var level: int = Items.refine(_after)
	var big: bool = _success and (not _milestone.is_empty() or level >= RefineRules.max_level())
	(_voices["perfect" if big else ("success" if _success else "fail")] as AudioStreamPlayer).play()
	var middle: Vector2 = _centre() + Vector2(0, -34)
	var count: int = (46 if big else 28) if _success else 16
	for i: int in count:
		var heading: float = randf() * TAU
		var speed: float = randf_range(30.0, 120.0 if _success else 50.0)
		var color: Color = _tone().lerp(Color.WHITE, randf() * 0.6) if _success else Color("3a3446").lerp(Color("8a84ad"), randf())
		_sparks.append({"pos": middle, "vel": Vector2.from_angle(heading) * speed, "age": 0.0, "life": randf_range(0.5, 1.2), "color": color, "size": randf_range(1.0, 2.0), "smoke": not _success})


func _emit_trickle(delta: float) -> void:
	if not _success or _closing >= 0.0:
		return
	if randf() < delta * 14.0: ## sparks keep rising off the weapon while the card stands
		var at: Vector2 = _centre() + Vector2(randf_range(-18.0, 18.0), -34.0 + randf_range(-4.0, 20.0))
		_sparks.append({"pos": at, "vel": Vector2(randf_range(-8.0, 8.0), randf_range(-34.0, -14.0)), "age": 0.0, "life": randf_range(0.6, 1.1), "color": _tone().lerp(Color.WHITE, 0.4), "size": 1.0, "smoke": false})


func _update_sparks(delta: float) -> void:
	for i: int in range(_sparks.size() - 1, -1, -1):
		var s: Dictionary = _sparks[i]
		s.age = float(s.age) + delta
		if float(s.age) >= float(s.life):
			_sparks.remove_at(i)
			continue
		var vel: Vector2 = (s.vel as Vector2) * exp(-2.2 * delta) + Vector2(0.0, (-12.0 if bool(s.smoke) else 60.0) * delta)
		s.vel = vel
		s.pos = (s.pos as Vector2) + vel * delta


# ---------- drawing ----------

func _t(at: Vector2, text: String, color: Color, scale: float = 1.0, centred: bool = false) -> void:
	var width: float = float(PixelText.width(text)) * scale
	var origin: Vector2 = at - Vector2(width / 2.0 if centred else 0.0, 0.0)
	if scale == 1.0:
		PixelText.draw(_view, text, Vector2i(roundi(origin.x), roundi(origin.y)), color, UiStyle.OUTLINE)
		return
	_view.draw_set_transform(origin.round(), 0.0, Vector2(scale, scale))
	PixelText.draw(_view, text, Vector2i.ZERO, color, UiStyle.OUTLINE)
	_view.draw_set_transform(Vector2.ZERO)


func _draw_view() -> void:
	var fade: float = clampf(_age / 0.25, 0.0, 1.0) * (1.0 - clampf(_closing / FADE, 0.0, 1.0)) if _closing >= 0.0 else clampf(_age / 0.25, 0.0, 1.0)
	var full: Vector2 = get_viewport().get_visible_rect().size
	_view.draw_rect(Rect2(Vector2.ZERO, full), Color(0.02, 0.01, 0.05, 0.62 * fade))
	var middle: Vector2 = _centre()
	var card: Rect2 = Rect2(middle - CARD / 2.0, CARD)
	VineStyle.paper(_view, card, fade, VineStyle.void_amount(), 5)
	var icon_at: Vector2 = middle + Vector2(0, -34)
	var heat: float = clampf(_age / BUILD, 0.0, 1.0)
	var since: float = _age - BUILD
	var tone: Color = _tone()
	var glow_color: Color = Color("ff9a4a").lerp(Color("fff0b0"), heat) if not _revealed else tone
	# the weapon: shakes harder as it heats, then rests
	var shake: Vector2 = Vector2.ZERO
	if not _revealed:
		shake = Vector2(sin(_age * 61.0), cos(_age * 53.0)) * (0.4 + 1.6 * heat * heat)
	VineStyle.glow(_view, icon_at, 26.0 + 14.0 * heat + (10.0 * exp(-since * 3.0) if _revealed else 0.0), glow_color, (0.25 + 0.5 * heat) * fade if not _revealed or _success else 0.2 * fade)
	var icon: Texture2D = Items.icon(_after)
	if icon != null:
		var tint: Color = Color(1.0, 1.0 - 0.35 * (1.0 - heat), 1.0 - 0.45 * (1.0 - heat), fade)
		_view.draw_texture_rect(icon, Rect2((icon_at + shake - Vector2(24, 24)).round(), Vector2(48, 48)), false, tint)
	if not _revealed:
		for k: int in 12: ## sparks of heat drawn inwards
			var phase: float = fposmod(_age * 1.3 + float(k) / 12.0, 1.0)
			var heading: float = float(k) * 2.399 + _age * 0.8
			var spot: Vector2 = icon_at + Vector2.from_angle(heading) * (34.0 * (1.0 - phase) + 6.0)
			_view.draw_rect(Rect2(spot.round(), Vector2.ONE), Color(glow_color, phase * heat * fade))
		_t(middle + Vector2(0, 8), "." .repeat(1 + int(_age * 4.0) % 3), Color(UiStyle.TEXT_DIM, fade), 2.0, true)
		_draw_sparks(fade)
		return
	# the answer
	if since < 0.35: ## the flash
		_view.draw_rect(Rect2(Vector2.ZERO, full), Color(Color.WHITE if _success else Color("c9a0a0"), (1.0 - since / 0.35) * (0.7 if _success else 0.35)))
	if _success and since < 0.7: ## a ring of light
		var k: float = since / 0.7
		_view.draw_arc(icon_at, 12.0 + 90.0 * (1.0 - pow(1.0 - k, 2.0)), 0.0, TAU, 48, Color(tone, (1.0 - k) * fade), 2.0)
	if not _success: ## cracks across the iron
		var crack: Color = Color("e0556e", clampf(since * 4.0, 0.0, 1.0) * fade)
		for line: int in 5:
			var cursor: Vector2 = icon_at + Vector2(float(line - 2) * 9.0, -22.0)
			for step: int in 6:
				var next: Vector2 = cursor + Vector2(VineStyle.rand(line * 31 + step * 7) * 8.0 - 4.0, 8.0)
				_view.draw_line(cursor.round(), next.round(), crack, 1.0)
				cursor = next
	_draw_sparks(fade)
	var level: int = Items.refine(_after)
	var title: String = "+%d" % level if _success else "MISSLUNGEN"
	var pop: float = 1.0 + 0.6 * exp(-since * 9.0) ## the number lands with a thump
	_t(middle + Vector2(0, 2), title, Color(tone, fade), 3.0 * pop if _success else 2.0, true)
	_t(middle + Vector2(0, 28), Items.title(_after).to_upper() if _success else Items.title(_before).to_upper(), Color(RefineStyle.GOLD if _success else UiStyle.TEXT, fade), 1.0, true)
	var cap: int = RefineRules.cap(_after)
	var pearls_at: Vector2 = Vector2(middle.x - float(RefineStyle.pearls_width()) / 2.0, middle.y + 40.0)
	RefineStyle.draw_pearls(_view, pearls_at, level, cap, fade, _age)
	if _success and level > 0:
		var pearl: float = pearls_at.x + float((level - 1) * RefineStyle.PEARL_STRIDE + ((level - 1) / RefineRules.TIER_SIZE) * RefineStyle.GAP)
		_view.draw_rect(Rect2(pearl - 1.0, pearls_at.y - 1.0, 5, 5), Color(Color.WHITE, clampf(1.0 - since * 2.0, 0.0, 1.0) * fade)) ## the new pearl flashes
	if _success:
		var gain: String = "SCHADEN %s > %s" % [_num(Items.stat(_before, "damage")), _num(Items.stat(_after, "damage"))]
		_t(middle + Vector2(0, 52), gain, Color(RefineStyle.TEAL, fade), 1.0, true)
		if not _milestone.is_empty():
			var effects: Array[String] = []
			if _milestone.has("reach"):
				effects.append("REICHWEITE +%d" % int(_milestone.reach))
			if _milestone.has("speed"):
				effects.append("TEMPO +%d%%" % roundi(float(_milestone.speed) * 100.0))
			_t(middle + Vector2(0, 62), "%s: %s" % [String(_milestone.get("name", "")), " ".join(effects)], Color(tone.lightened(0.15 * sin(_age * 4.0) + 0.1), fade), 1.0, true)
	else:
		_t(middle + Vector2(0, 52), "GLUT +%d %%  (JETZT %d %%)" % [roundi(RefineRules.pity_bonus(_after) * 100.0), roundi(RefineRules.chance(_after) * 100.0)], Color(RefineStyle.GOLD, fade), 1.0, true)
		var x: float = middle.x - 20.0 * float(_refund.size())
		for item: String in _refund:
			var picture: Texture2D = Items.icon({"id": item})
			if picture != null:
				_view.draw_texture_rect(picture, Rect2(Vector2(x, middle.y + 63.0), Vector2(12, 12)), false, Color(1, 1, 1, fade))
			_t(Vector2(x + 14.0, middle.y + 66.0), "+%d" % int(_refund[item]), Color(RefineStyle.TEAL, fade))
			x += 40.0
	if _age >= BUILD + STAY and _closing < 0.0:
		_t(Vector2(middle.x, card.end.y - 11.0), "E WEITER", Color(UiStyle.TEXT_DIM, fade * (0.6 + 0.4 * sin(_age * 4.0))), 1.0, true)


func _draw_sparks(fade: float) -> void:
	for s: Dictionary in _sparks:
		var k: float = float(s.age) / float(s.life)
		var color: Color = Color(s.color as Color, (1.0 - k) * fade)
		var size: float = float(s.size) * (1.0 + (k * 2.0 if bool(s.smoke) else 0.0))
		_view.draw_rect(Rect2((s.pos as Vector2).round(), Vector2(size, size)), color)


func _num(value: float) -> String:
	return "%d" % value if is_equal_approx(value, roundf(value)) else ("%.1f" % value if absf(value * 10.0 - roundf(value * 10.0)) < 0.001 else "%.2f" % value)
