class_name StaffCrystals
extends Node2D
## The stones in a held magic staff (docs/magie_konzept.md; the places per staff are in data/spells.json `staffs`: `crowns`/`knots` as
## [along, across] px in the held picture, the forked Bleichgabel has two of each, section 17), drawn on every peer over the staff's sprite (a child of AttackComponent's `Hand`,
## after the weapon). The spell crystal stands in the crown's three twigs, the gem lies in the knot further down. The spell crystal shows its
## recharge: empty it is dark and dull, light fills it from the bottom, and when it is full it blinks once and breathes. While she casts it
## flares. Unlit, so the stones glow at night. The little pictures are `assets/magic/staff_stones.png` (tools/art_crystals.py: one column per
## stone kind, `mini` in data/spells.json; row 0 lit, row 1 the dark empty stone).

const CROWN_PX: float = 22.5 ## grip to the middle of the head's cradle in the staff's held picture (tools/art_weapons.py `staff`)
const KNOT_PX: float = 8.0 ## grip to the silver bezel of the gem
const ICON_CROWN: Vector2 = Vector2(11.5, 4.5) ## the same two places in the 16x16 inventory icon
const ICON_KNOT: Vector2 = Vector2(6.8, 9.2)
const SILVER: Color = Color("a3adc8")
const SILVER_LIT: Color = Color("d6dcef")
const SILVER_DARK: Color = Color("3a4260")
const WOOD: Color = Color("73508a")
const WOOD_DARK: Color = Color("2b1a38")
const INK: Color = Color("1b1a2e")
const CELL: Vector2i = Vector2i(7, 10)
const SHEET_PATH: String = "res://assets/magic/staff_stones.png"
const SMALL_PATH: String = "res://assets/magic/staff_stones_small.png" ## the Bleichgabel's small claws: 5x7 crystals, 3x3 gem pearls (`small_stones`)
const SMALL_CELL: Vector2i = Vector2i(5, 7)

var attack: AttackComponent
var _sheet: Texture2D
var _small: Texture2D
var _cell: Vector2i = CELL ## the cell of the sheet in use this frame
var _use: Texture2D
var _spells: SpellComponent
var _bolt: float = 0.0 ## 1 = a GABELSCHLAG just jumped between the prongs


func _ready() -> void:
	material = Unlit.material()
	## no own z_index: the stones sort with the Hand node, so they go behind her when the staff is behind her
	if ResourceLoader.exists(SHEET_PATH):
		_sheet = load(SHEET_PATH) as Texture2D
	if ResourceLoader.exists(SMALL_PATH):
		_small = load(SMALL_PATH) as Texture2D


func _process(delta: float) -> void:
	_bolt = move_toward(_bolt, 0.0, delta / 0.4)
	visible = attack != null and attack.holds_staff()
	if visible:
		queue_redraw()


func _draw() -> void:
	var alpha: float = attack.weapon_alpha()
	if alpha <= 0.02:
		return
	if _spells == null:
		var owner_player: Player = attack.get_parent() as Player
		_spells = owner_player.spells if owner_player != null else null
		if _spells == null:
			return
		_spells.fork_struck.connect(func(_prong: int, power: float) -> void: _bolt = clampf(power - 0.6, 0.6, 1.0))
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var who: Player = attack.get_parent() as Player
	var layout: Dictionary = SpellRules.staff_def(_spells.staff_id)
	var crowns: Array = layout.get("crowns", [[CROWN_PX, 0.0]]) as Array
	var knots: Array = layout.get("knots", [[KNOT_PX, 0.0]]) as Array
	var count: int = mini(_spells.prongs, mini(crowns.size(), knots.size()))
	var small: bool = bool(layout.get("small_stones", false)) and _small != null
	_use = _small if small else _sheet
	_cell = SMALL_CELL if small else CELL
	var gem_size: Vector2i = Vector2i(3, 3) if small else Vector2i(5, 5)
	var lift: float = 1.0 if small else 2.0
	var shrink: float = 0.6 if small else 1.0
	var crown_at: Array[Vector2] = []
	for p: int in count:
		crown_at.append(_point(crowns[p] as Array))
	if count >= 2:
		_bond(crown_at, t, alpha)
	for p: int in count:
		var cast: float = who.cast_glow(p)
		var gem_id: String = _spells.gem_of(p)
		if gem_id != "":
			var knot: Vector2 = _point(knots[p] as Array)
			var gem_index: int = int(SpellRules.gem_def(String(SpellRules.gem_info(gem_id).get("mod", ""))).get("mini", 2))
			_halo(knot + Vector2(0.0, 4.0 * shrink), SpellRules.stone_color(gem_id), 0.18 + 0.08 * sin(t * 2.0 + float(p)) + 0.3 * cast, alpha, shrink)
			_stone(gem_index, knot + Vector2(0.0, 1.0), 1.0, alpha, gem_size)
			_bezel(knot, alpha, small)
		var spell_id: String = _spells.spell_of(p)
		if spell_id == "":
			continue
		var crown: Vector2 = crown_at[p]
		var index: int = int(SpellRules.spell_def(String(SpellRules.spell_info(spell_id).get("spell", ""))).get("mini", 0))
		var colour: Color = SpellRules.stone_color(spell_id)
		var fill: float = _spells.charge_fraction(p)
		var light: float = _charge_light(fill, t + float(p) * 1.3)
		var ready: bool = fill >= 0.999
		var flash: float = _spells.ready_flash(p)
		var glow: float = (0.28 + 0.1 * sin(t * 2.6 + float(p)) if ready else 0.22 * light) + 0.6 * flash + 0.7 * cast
		_halo(crown + Vector2(0.0, 1.0), colour, glow, alpha, shrink)
		_stone(index, crown + Vector2(0.0, lift), light, alpha, _cell)
		if count == 1:
			_clasp(crown, alpha) ## the Hexenulme closes its twigs over the crystal; the Bleichgabel has its claws in its picture
		if flash > 0.0: ## just full: a cross of light on the crystal
			var arm: float = 2.0 if small else 3.0
			draw_rect(Rect2(crown + Vector2(-arm, -arm - 2.0), Vector2(arm * 2.0 + 1.0, 1)), Color(1, 1, 1, flash * 0.8 * alpha))
			draw_rect(Rect2(crown + Vector2(0.0, -arm * 2.0 - 2.0), Vector2(1, arm * 2.0 + 1.0)), Color(1, 1, 1, flash * 0.8 * alpha))
	if _bolt > 0.0 and count >= 2:
		_lightning(crown_at[0] + Vector2(0.0, -3.0), crown_at[1] + Vector2(0.0, -3.0), _bolt, alpha, t)


## A place on the held staff from the layout ([along, across] px in its picture), whole pixels.
func _point(at: Array) -> Vector2:
	return attack.item_point(float(at[0]), float(at[1])).round()


## The bond of the two crystals of the Bleichgabel: GLEICHKLANG a slow thread of light swinging between them in their colour, ZWIESPALT short
## crackling sparks that jump across and die.
func _bond(crown_at: Array[Vector2], t: float, alpha: float) -> void:
	var a: Vector2 = crown_at[0] + Vector2(0.0, -3.0)
	var b: Vector2 = crown_at[1] + Vector2(0.0, -3.0)
	match _spells.bond:
		"harmony":
			var colour: Color = SpellRules.stone_color(_spells.spell_of(0)).lightened(0.3)
			var steps: int = maxi(int(a.distance_to(b)), 2)
			for i: int in steps + 1:
				var f: float = float(i) / float(steps)
				var sag: float = sin(f * PI) * (1.5 + sin(t * 1.7))
				var pulse: float = 0.5 + 0.5 * sin(t * 3.0 - f * 6.0)
				draw_rect(Rect2((a.lerp(b, f) + Vector2(0.0, sag)).round(), Vector2.ONE), Color(colour, alpha * (0.18 + 0.3 * pulse)))
		"tension":
			if fmod(t * 1.9, 1.0) < 0.12: ## now and then a crackle jumps across
				_lightning(a, b, 0.45, alpha, t)


## A jagged bolt of light from `a` to `b`: white core, the colours of the two crystals at its ends, jagged anew every 1/20 s.
func _lightning(a: Vector2, b: Vector2, strength: float, alpha: float, t: float) -> void:
	var ca: Color = SpellRules.stone_color(_spells.spell_of(0))
	var cb: Color = SpellRules.stone_color(_spells.spell_of(1))
	var steps: int = maxi(int(a.distance_to(b) / 2.0), 3)
	var seed_step: float = floorf(t * 20.0)
	var prev: Vector2 = a
	var side: Vector2 = (b - a).orthogonal().normalized()
	for i: int in range(1, steps + 1):
		var f: float = float(i) / float(steps)
		var raw: float = sin((seed_step + float(i)) * 12.9898) * 43758.5453
		var jag: float = 0.0 if i == steps else ((raw - floorf(raw)) - 0.5) * 5.0
		var point: Vector2 = (a.lerp(b, f) + side * jag).round()
		var colour: Color = ca.lerp(cb, f).lerp(Color.WHITE, 0.55)
		var span: float = maxf(prev.distance_to(point), 1.0)
		for k: int in int(span):
			draw_rect(Rect2(prev.lerp(point, float(k) / span).round(), Vector2.ONE), Color(colour, alpha * strength))
		prev = point
	draw_rect(Rect2(a + Vector2(-1.0, -1.0), Vector2(3.0, 3.0)), Color(ca.lightened(0.5), alpha * strength * 0.5))
	draw_rect(Rect2(b + Vector2(-1.0, -1.0), Vector2(3.0, 3.0)), Color(cb.lightened(0.5), alpha * strength * 0.5))


## How much a recharging crystal shines (0 = out, 1 = full light): out after the cast, from about half the time on it glimmers faintly and
## grows brighter, and in the last third it blinks now and then, faster towards the end. Full: 1 (the flash on top comes from `ready_flash`).
static func _charge_light(fill: float, t: float) -> float:
	if fill >= 0.999:
		return 1.0
	var glimmer: float = smoothstep(0.5, 1.0, fill) * 0.55
	var late: float = clampf((fill - 0.66) / 0.34, 0.0, 1.0)
	if late > 0.0: ## short blinks, more often the closer it is
		var beat: float = sin(t * (5.0 + 13.0 * late) + sin(t * 1.7) * 2.0)
		glimmer += pow(maxf(beat, 0.0), 14.0) * (0.35 + 0.45 * late)
	return clampf(glimmer, 0.0, 1.0)


## One stone standing on `at` (its bottom middle): the dark, dull stone with its lit picture over it at `light` strength.
func _stone(index: int, at: Vector2, light: float, alpha: float, size: Vector2i) -> void:
	var origin: Vector2 = at + Vector2(-floorf(size.x / 2.0), -size.y + 2.0)
	if _use == null: ## before the art exists: a plain little stone
		draw_rect(Rect2(origin, Vector2(size)), Color(0.1, 0.1, 0.18, alpha))
		draw_rect(Rect2(origin + Vector2.ONE, Vector2(size) - Vector2(2, 2)), Color(0.6, 1.0, 0.9, alpha * light))
		return
	var cell: Vector2 = Vector2(index * _cell.x, 0.0)
	var offset: Vector2 = Vector2(roundf((_cell.x - size.x) / 2.0), _cell.y - size.y) ## a gem uses the lower middle of its cell
	draw_texture_rect_region(_use, Rect2(origin, Vector2(size)), Rect2(cell + Vector2(0.0, _cell.y) + offset, Vector2(size)), Color(1, 1, 1, alpha)) ## the dark, empty stone
	if light > 0.01:
		draw_texture_rect_region(_use, Rect2(origin, Vector2(size)), Rect2(cell + offset, Vector2(size)), Color(1, 1, 1, alpha * light))


## The two prong tips of the head curling in over the crystal's flanks, so it sits IN the head and does not hover in front of it.
func _clasp(at: Vector2, alpha: float) -> void:
	for side: float in [-1.0, 1.0]: ## the prongs curl in over the crystal's flanks
		var tip: Vector2 = at + Vector2(-4.0 if side < 0.0 else 4.0, -2.0)
		draw_rect(Rect2(tip, Vector2(1, 3)), Color(WOOD if side < 0.0 else WOOD_DARK, alpha))
		draw_rect(Rect2(tip + Vector2(side * -1.0, -1.0), Vector2(1, 1)), Color(WOOD, alpha))


## The silver ring of the gem's bezel, over the stone's rim.
func _bezel(at: Vector2, alpha: float, small: bool = false) -> void:
	var ring: Array[Vector2] = [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3), Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]
	if small: ## the small bezel of the Bleichgabel: four claws of silver round the pearl
		ring = [Vector2(-2, -1), Vector2(2, -1), Vector2(-2, 1), Vector2(2, 1)]
	for d: Vector2 in ring:
		var lit: bool = d.x + d.y < 0.0
		draw_rect(Rect2(at + d, Vector2.ONE), Color(SILVER_LIT if lit else SILVER_DARK, alpha))


## The stones of a staff over its 16x16 inventory icon drawn at `origin` (ItemSlot): a little crystal in each crown, a speck of each gem in
## its bezel, at the places the layout names (data/spells.json `staffs`: `icon_crowns`, `icon_knots`).
static func draw_icon_stones(canvas: CanvasItem, stack: Dictionary, origin: Vector2) -> void:
	var layout: Dictionary = SpellRules.staff_def(String(stack.get("id", "")))
	var crowns: Array = layout.get("icon_crowns", [[ICON_CROWN.x, ICON_CROWN.y]]) as Array
	var knots: Array = layout.get("icon_knots", [[ICON_KNOT.x, ICON_KNOT.y]]) as Array
	for p: int in mini(SpellRules.prongs_of(String(stack.get("id", ""))), mini(crowns.size(), knots.size())):
		var gem: String = SpellRules.gem_in(stack, p)
		if gem != "":
			var g: Color = SpellRules.stone_color(gem)
			var k: Vector2 = (origin + Vector2(float((knots[p] as Array)[0]), float((knots[p] as Array)[1]))).floor()
			canvas.draw_rect(Rect2(k, Vector2(2, 2)), g)
			canvas.draw_rect(Rect2(k, Vector2.ONE), g.lightened(0.6))
		var spell: String = SpellRules.spell_in(stack, p)
		if spell != "":
			var c: Color = SpellRules.stone_color(spell)
			var at: Vector2 = (origin + Vector2(float((crowns[p] as Array)[0]), float((crowns[p] as Array)[1]))).floor()
			canvas.draw_rect(Rect2(at + Vector2(-1.0, -1.0), Vector2(3, 4)), INK)
			canvas.draw_rect(Rect2(at + Vector2(0.0, -2.0), Vector2(1, 1)), INK)
			canvas.draw_rect(Rect2(at + Vector2(0.0, -1.0), Vector2(1, 3)), c)
			canvas.draw_rect(Rect2(at + Vector2(-1.0, 0.0), Vector2(1, 2)), c.lightened(0.35))
			canvas.draw_rect(Rect2(at + Vector2(1.0, 0.0), Vector2(1, 2)), c.darkened(0.35))
			canvas.draw_rect(Rect2(at, Vector2.ONE), Color(1, 1, 1, 0.9))


## A soft, dithered pool of the stone's light round it.
func _halo(at: Vector2, colour: Color, strength: float, alpha: float, shrink: float = 1.0) -> void:
	if strength <= 0.01:
		return
	for ring: int in 3:
		var r: float = (3.0 + ring * 2.0) * shrink
		var a: float = strength * alpha * (0.45 - ring * 0.13)
		for k: int in 12:
			var ang: float = TAU * float(k) / 12.0 + ring * 0.4
			draw_rect(Rect2((at + Vector2(cos(ang) * r, sin(ang) * r * 0.8 - 4.0 * shrink)).round(), Vector2.ONE), Color(colour, a))
