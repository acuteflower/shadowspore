class_name ItemTooltip
extends Control
## Hover card in the vine style: a leaf of dark bark paper with a ragged, wavy edge that unfurls
## from the top, row by row. A bloom beside the type shows the rarity (more petals, higher
## rarity), stats show as a row of pearls, and vines with a glowing bud grow over its corners.
## It sways a little; epic and legendary cards shed motes, legendary ones have a light running
## along the top edge, and at night the void creeps over the corners.

const STATS: Array = [["damage", "Schaden", 20.0], ["speed", "Tempo", 2.0], ["reach", "Reichweite", 40.0], ["knockback", "Rückstoß", 100.0]]
const TIERS: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
const WRAP_WIDTH: int = 118
const PAD: int = 7
const PEARLS: int = 5
const PEARL_STRIDE: int = 4
const UNFURL_SECONDS: float = 0.24
const PAPER: Color = Color("120d22")
const PAPER_VOID: Color = Color("07030f")

var _rows: Array[Dictionary] = [] ## {type, text, ...}: title, sub, rule, stat, desc, hint
var _heights: Array[int] = []
var _label_width: int = 0
var _rarity: Color = Color.WHITE
var _tier: int = 0
var _age: float = 0.0
var _time: float = 0.0
var _salt: int = 0


## Fills the card for `stack`; `equip_hint` adds the right-click hint. `replaces`: the piece of jewellery of the same kind that is worn (a talisman card then
## compares with it line by line and says that it would be replaced).
func show_stack(stack: Dictionary, equip_hint: bool, replaces: Dictionary = {}) -> void:
	var def: Dictionary = Items.definition(stack)
	var rarity: Dictionary = DataRegistry.get_entry("rarities", String(def.get("rarity", "common")))
	var weapon_class: Dictionary = DataRegistry.get_entry("weapon_classes", String(def.get("weapon_class", "")))
	var type_name: String = String(weapon_class.get("name", String(def.get("kind", "")).capitalize()))
	_rarity = Items.rarity_color(stack)
	_tier = maxi(TIERS.find(String(def.get("rarity", "common"))), 0)
	_salt = hash(String(stack.get("id", ""))) % 997
	_age = 0.0
	_rows.clear()
	var level: int = Items.refine(stack)
	_rows.append({"type": "title", "text": String(def.get("name", "?")), "refine": level})
	if TalismanRules.is_talisman(stack):
		_talisman_rows(stack, def, rarity, equip_hint, replaces)
		_measure()
		queue_redraw()
		return
	_rows.append({"type": "sub", "text": "%s %s" % [rarity.get("name", ""), type_name]})
	var stats: Dictionary = def.get("stats", {})
	var refinable: bool = RefineRules.is_refinable(stack)
	if refinable: ## the fifteen pearls: how far this weapon is refined and how far it can go
		_rows.append({"type": "refine", "level": level, "cap": RefineRules.cap(stack), "text": "%d/%d" % [level, RefineRules.cap(stack)]})
	var stat_rows: Array[Dictionary] = []
	for entry: Array in STATS:
		if stats.has(entry[0]):
			var base: float = float(stats[entry[0]])
			var value: float = Items.stat(stack, String(entry[0])) ## with the refinement
			var bonus: String = "+" + _number(value - base) if level > 0 and not is_equal_approx(value, base) else ""
			stat_rows.append({"type": "stat", "text": String(entry[1]), "value": _number(value), "bonus": bonus, "level": level, "fill": clampf(value / float(entry[2]), 0.0, 1.0)})
	var description: Array[String] = _wrap(String(def.get("description", "")))
	if not stat_rows.is_empty():
		_rows.append({"type": "rule"})
		_rows.append_array(stat_rows)
	if refinable:
		_add_milestones(stack, level)
	if not description.is_empty():
		_rows.append({"type": "rule"})
		for line: String in description:
			_rows.append({"type": "desc", "text": line})
	if equip_hint:
		_rows.append({"type": "hint", "text": "Rechtsklick: ausrüsten"})
	_measure()
	queue_redraw()


## A talisman: its kind and field, one line per effect (coloured against the worn piece of the same kind), the story, the hint.
func _talisman_rows(stack: Dictionary, def: Dictionary, rarity: Dictionary, equip_hint: bool, replaces: Dictionary) -> void:
	var info: Dictionary = TalismanRules.type_info(TalismanRules.type_of(stack))
	_rows.append({"type": "sub", "text": "%s %s - %s" % [rarity.get("name", ""), info.get("name", ""), String(info.get("domain", "")).capitalize()]})
	_rows.append({"type": "rule"})
	var bonus: Dictionary = TalismanRules.bonus_of(stack)
	var other: Dictionary = TalismanRules.bonus_of(replaces)
	for key: String in (TalismanRules.catalog().get("stats", {}) as Dictionary):
		if bonus.has(key):
			var tone: int = TalismanRules.better(key, float(bonus[key]), float(other.get(key, 0.0))) if not replaces.is_empty() else 0
			_rows.append({"type": "bonus", "text": TalismanRules.line(key, float(bonus[key])), "tone": tone})
	if not replaces.is_empty():
		for key: String in other:
			if not bonus.has(key):
				var label: String = String(((TalismanRules.catalog().get("stats", {}) as Dictionary).get(key, {}) as Dictionary).get("label", key))
				_rows.append({"type": "bonus", "text": "OHNE %s" % label, "tone": -1})
	var description: Array[String] = _wrap(String(def.get("description", "")))
	if not description.is_empty():
		_rows.append({"type": "rule"})
		for line: String in description:
			_rows.append({"type": "desc", "text": line})
	if not replaces.is_empty():
		_rows.append({"type": "hint", "text": "Rechtsklick: ersetzt %s" % String(Items.definition(replaces).get("name", ""))})
	elif equip_hint:
		_rows.append({"type": "hint", "text": "Rechtsklick: anlegen"})


func _measure() -> void:
	_label_width = 0
	for row: Dictionary in _rows:
		if String(row["type"]) == "stat":
			_label_width = maxi(_label_width, PixelText.width(String(row["text"])))
	var widest: int = 0
	var total: int = 0
	_heights.clear()
	for row: Dictionary in _rows:
		var width: int = PixelText.width(String(row.get("text", "")))
		var height: int = 9
		match String(row["type"]):
			"title":
				height = 11
				if int(row.get("refine", 0)) > 0:
					width += 4 + PixelText.width("+%d" % int(row["refine"]))
			"refine":
				width = RefineStyle.pearls_width() + 6 + PixelText.width(String(row["text"]))
				height = 10
			"mile":
				height = 9
			"sub":
				width += 10
				height = 10
			"rule":
				height = 6
			"stat":
				width = _label_width + 8 + PEARLS * PEARL_STRIDE + 6 + PixelText.width(String(row["value"]))
				if String(row.get("bonus", "")) != "":
					width += 4 + PixelText.width(String(row["bonus"]))
				height = 10
			"bonus":
				width += 8
				height = 10
			"hint":
				width += 8
				height = 12
		widest = maxi(widest, width)
		_heights.append(height)
		total += height
	size = Vector2(widest + PAD * 2, total + PAD * 2 - 1)


func _process(delta: float) -> void:
	if visible:
		_age += delta
		_time += delta
		modulate.a = clampf(_age / 0.08, 0.0, 1.0)
		queue_redraw()


# ---------- drawing ----------

## How far the paper's edge is pulled in at column `x`: ragged, with round corners.
func _inset(x: int, bottom: bool) -> int:
	var edge: int = mini(x, int(size.x) - 1 - x)
	return int(VineStyle.rand(x / 2 + _salt + (97 if bottom else 0)) * 2.4) + maxi(3 - edge, 0)


func _draw() -> void:
	var void_level: float = VineStyle.void_amount()
	var unfurl: float = 1.0 - pow(1.0 - clampf(_age / UNFURL_SECONDS, 0.0, 1.0), 3.0)
	var width: int = int(size.x)
	var height: int = roundi(size.y * unfurl)
	draw_set_transform(Vector2(roundf(sin(_time * 1.3) * 0.8), 0.0)) ## it sways a little
	_draw_paper(width, height, void_level)
	_draw_rows(height, void_level)
	_draw_vines(width, height, void_level)
	if _tier >= 3 and unfurl >= 1.0: ## epic and legendary: motes drift up inside the card
		for k: int in 3 + (_tier - 3) * 2:
			var phase: float = fposmod(_time * 0.5 + k * 0.31, 1.0)
			draw_rect(Rect2(roundf(5.0 + VineStyle.rand(k + 70 + _salt) * (size.x - 10.0)), roundf(size.y - 5.0 - phase * (size.y - 10.0)), 1, 1), Color(_rarity, 1.0 - phase))
	draw_set_transform(Vector2.ZERO)


func _draw_paper(width: int, height: int, void_level: float) -> void:
	var fill: Color = PAPER.lerp(PAPER_VOID, void_level)
	var edge: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level)
	var lit: Color = Color(_rarity, 0.75)
	var shimmer: float = fposmod(_time * 70.0, width + 40.0) - 20.0
	var last_top: int = 0
	var last_bottom: int = 0
	for x: int in width:
		var top: int = _inset(x, false)
		var bottom: int = height - _inset(x, true)
		if bottom <= top:
			continue
		draw_rect(Rect2(x, top, 1, bottom - top), Color(fill, 0.95))
		for row: int in 4: ## the rarity colour seeps in from the top edge
			draw_rect(Rect2(x, top + 1 + row, 1, 1), Color(_rarity, 0.16 * (1.0 - row / 4.0)))
		var top_edge: Color = edge.lerp(_rarity, 0.45)
		if _tier == 4 and absf(x - shimmer) < 9.0: ## legendary: a light runs along the top edge
			top_edge = top_edge.lerp(VineStyle.PETAL, 1.0 - absf(x - shimmer) / 9.0)
		draw_rect(Rect2(x, mini(top, last_top) if x > 0 else top, 1, (absi(top - last_top) + 1) if x > 0 else 1), top_edge)
		draw_rect(Rect2(x, top + 1, 1, 1), lit)
		draw_rect(Rect2(x, mini(bottom - 1, last_bottom - 1) if x > 0 else bottom - 1, 1, (absi(bottom - last_bottom) + 1) if x > 0 else 1), edge.darkened(0.25))
		if x == 0 or x == width - 1: ## the sides
			draw_rect(Rect2(x, top, 1, bottom - top), edge)
		last_top = top
		last_bottom = bottom


func _draw_rows(paper_height: int, void_level: float) -> void:
	var y: int = PAD
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		var height: int = _heights[i]
		var p: float = clampf((_age - 0.03 - i * 0.03) / 0.1, 0.0, 1.0)
		if p > 0.0 and y + height - 2 <= paper_height:
			_draw_row(row, y, height, p, void_level)
		y += height


func _draw_row(row: Dictionary, y: int, height: int, p: float, void_level: float) -> void:
	var text: String = String(row.get("text", ""))
	var shade: Color = Color(VineStyle.OUTLINE, p)
	match String(row["type"]):
		"title":
			VineStyle.glow(self, Vector2(PAD + PixelText.width(text) / 2.0, y + 5.0), 18.0, _rarity, 0.12 * p)
			PixelText.draw(self, text, Vector2i(PAD, y), Color(_rarity, p), shade)
			var level: int = int(row.get("refine", 0))
			if level > 0: ## the "+7" after the name, in the colour of its tier
				var tag: String = "+%d" % level
				var tone: Color = RefineStyle.color(level)
				if level >= RefineRules.max_level():
					tone = tone.lightened(0.2 + 0.2 * sin(_time * 3.0))
				PixelText.draw(self, tag, Vector2i(PAD + PixelText.width(text) + 4, y), Color(tone, p), shade)
		"refine":
			RefineStyle.draw_pearls(self, Vector2(PAD, y + 3), int(row["level"]), int(row["cap"]), p, _time)
			var count: String = String(row["text"])
			PixelText.draw(self, count, Vector2i(int(size.x) - PAD - PixelText.width(count), y), Color(RefineStyle.color(int(row["level"])), p), shade)
		"mile":
			var reached: bool = bool(row["on"])
			var mark: Color = RefineStyle.color(int(row["at"])) if reached else UiStyle.TEXT_DIM
			PixelText.draw(self, text, Vector2i(PAD, y), Color(mark, p * (1.0 if reached else 0.55)), shade)
		"sub":
			_draw_bloom(Vector2(PAD + 3.0, y + 5.0), p)
			PixelText.draw(self, text, Vector2i(PAD + 10, y), Color(UiStyle.TEXT_DIM.lerp(_rarity, 0.3), p), shade)
		"rule": ## a thread with a bud, fading out to the right
			var span: int = int(size.x) - PAD * 2
			for x: int in span:
				draw_rect(Rect2(PAD + x, y + 2, 1, 1), Color(_rarity.lerp(VineStyle.VOID_GLOW, void_level * 0.5), 0.55 * p * (1.0 - float(x) / span)))
			draw_rect(Rect2(PAD, y + 1, 1, 3), Color(_rarity, p))
			draw_rect(Rect2(PAD - 1, y + 2, 3, 1), Color(_rarity, p))
		"stat":
			PixelText.draw(self, text, Vector2i(PAD, y), Color(UiStyle.TEXT_DIM, p), shade)
			var lit: int = clampi(ceili(float(row["fill"]) * PEARLS), 1, PEARLS)
			for k: int in PEARLS: ## the value as pearls
				var at: Vector2 = Vector2(PAD + _label_width + 8 + k * PEARL_STRIDE, y + 3)
				var on: bool = k < lit
				draw_rect(Rect2(at, Vector2(3, 3)), Color(_rarity if on else VineStyle.BARK_VOID_LIGHT, p * (1.0 if on else 0.7)))
				if on:
					draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, p * 0.8))
			var value: String = String(row["value"])
			var value_x: int = int(size.x) - PAD - PixelText.width(value)
			PixelText.draw(self, value, Vector2i(value_x, y), Color(UiStyle.TEXT, p), shade)
			var bonus: String = String(row.get("bonus", ""))
			if bonus != "": ## what the refinement adds, in the colour of the level
				PixelText.draw(self, bonus, Vector2i(value_x - 4 - PixelText.width(bonus), y), Color(RefineStyle.color(int(row["level"])), p), shade)
		"bonus": ## an effect of jewellery: a bud and the line, green when it beats the worn piece, red when it falls short
			var tone: int = int(row.get("tone", 0))
			var colour: Color = _rarity if tone == 0 else (Color("6fd08c") if tone > 0 else Color("ff5a6a"))
			var bud: Vector2 = Vector2(PAD + 2.0, y + 4.0)
			VineStyle.glow(self, bud, 4.0, colour, 0.4 * p)
			draw_rect(Rect2(bud, Vector2.ONE), Color(VineStyle.PETAL, p))
			PixelText.draw(self, text, Vector2i(PAD + 8, y), Color(colour.lerp(Color.WHITE, 0.25), p), shade)
		"desc":
			PixelText.draw(self, text, Vector2i(PAD, y), Color(UiStyle.TEXT_DIM.lerp(VineStyle.LEAF_VOID_LIGHT, void_level * 0.4), p), shade)
		"hint":
			var bud: Vector2 = Vector2(PAD + 2.0, y + 6.0)
			VineStyle.glow(self, bud, 5.0, UiStyle.ACCENT, 0.5 * p)
			draw_rect(Rect2(bud, Vector2.ONE), Color(VineStyle.PETAL, p))
			PixelText.draw(self, text, Vector2i(PAD + 8, y + 1), Color(UiStyle.ACCENT, p), shade)


## The rarity: a little flower, more petals the rarer the item.
func _draw_bloom(at: Vector2, p: float) -> void:
	var petals: Array[Vector2] = [Vector2(0, -2), Vector2(2, 0), Vector2(0, 2), Vector2(-2, 0), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	VineStyle.glow(self, at, 6.0, _rarity, (0.35 + 0.1 * _tier + 0.1 * sin(_time * 3.0)) * p)
	for k: int in 4 + _tier:
		draw_rect(Rect2(at + petals[k], Vector2.ONE), Color(_rarity, p))
	draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, p))


## Leaves and a glowing bud grow over two corners; at night void tendrils creep out.
func _draw_vines(width: int, height: int, void_level: float) -> void:
	var p: float = clampf((_age - 0.12) / 0.15, 0.0, 1.0)
	if p <= 0.0 or height < 8:
		return
	var leaf: Color = VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level)
	var light: Color = VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level)
	VineStyle.leaf(self, Vector2(2, 5), -1, -1, 3, Color(leaf, p), Color(light, p))
	VineStyle.leaf(self, Vector2(5, 1), 1, -1, 2, Color(leaf, p), Color(light, p))
	VineStyle.glow(self, Vector2(-1, 1), 6.0, _rarity, 0.8 * p)
	draw_rect(Rect2(-2, 0, 1, 1), Color(VineStyle.PETAL, p))
	VineStyle.leaf(self, Vector2(width - 3, height - 6), 1, 1, 3, Color(leaf, p), Color(light, p))
	for k: int in 2: ## a few leaves droop from the lower edge
		var x: int = 14 + int(VineStyle.rand(k + 40 + _salt) * (width - 28))
		VineStyle.leaf(self, Vector2(x, height - _inset(x, true)), -1 if k == 0 else 1, 1, 2, Color(leaf, p), Color(light, p))
	if void_level > 0.2:
		VineStyle.tendril(self, Vector2(width - 1, height - 3), Vector2(0.8, 0.6).normalized(), int(3 + 6 * void_level), _time, _salt)
		VineStyle.tendril(self, Vector2(1, 2), Vector2(-0.8, -0.6).normalized(), int(3 + 5 * void_level), _time, _salt + 3)


func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % value
	return "%.1f" % value if absf(value * 10.0 - roundf(value * 10.0)) < 0.001 else "%.2f" % value


## The milestones of the refinement up to the weapon's cap: reached ones in the colour of their level, the rest dim.
func _add_milestones(stack: Dictionary, level: int) -> void:
	var all: Dictionary = RefineRules.config().get("milestones", {}) as Dictionary
	var keys: Array = all.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var first: bool = true
	for key: Variant in keys:
		var at: int = int(key)
		if at > RefineRules.cap(stack):
			continue
		var entry: Dictionary = all[key] as Dictionary
		var effects: Array[String] = []
		if entry.has("reach"):
			effects.append("REICHWEITE +%d" % int(entry["reach"]))
		if entry.has("speed"):
			effects.append("TEMPO +%d%%" % roundi(float(entry["speed"]) * 100.0))
		if first:
			_rows.append({"type": "rule"})
			first = false
		for line: String in _wrap("+%d %s: %s" % [at, String(entry.get("name", "")), " ".join(effects)]):
			_rows.append({"type": "mile", "text": line, "on": level >= at, "at": at})


func _wrap(text: String) -> Array[String]:
	var lines: Array[String] = []
	var current: String = ""
	for word: String in text.split(" "):
		var candidate: String = word if current == "" else current + " " + word
		if PixelText.width(candidate) > WRAP_WIDTH and current != "":
			lines.append(current)
			current = word
		else:
			current = candidate
	if current != "":
		lines.append(current)
	return lines
