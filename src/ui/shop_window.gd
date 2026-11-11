class_name ShopWindow
extends BoardWindow
## The reusable shop of the town (data/shops.json, one entry per person-and-place; Gustav's workbench is the first, the forge, the kitchen and the market use the same).
## A shop's tabs say what it offers; each one is a `kind`:
##   craft - things you make yourself at the bench (recipes with `by: "self"`): a short bar fills, then the host swaps material for the result;
##   order - things only the person can make (recipes with `by: "npc"`, `work` seconds): the material is handed over, the person works on it *while they are at their bench*
##           (so it stops at night and when they take a break), the finished piece waits on the bench until anybody collects it; the queue is the town's, not yours;
##   buy   - the person sells (`buy` list: item, price in copper, `trust`);
##   sell  - the person buys from your bag (`sell` list);
##   brew  - the person brews potions from what you bring (data/alchemy.json, AlchemyRules; Esma): instant, the brew card plays (`BrewReveal`);
##   grind - the lake witch's SCHLIFF: three equal crystals or gems become one a tier higher (`CrystalRules`, the shop's `grind` block);
##   refresh - the lake witch's LÄUTERN (free, no money shown): a raw stone shows the stone it has hidden since it was found and becomes it (`CrystalRules`, the shop's `refresh` block, `StoneReveal`);
##   dev   - a developer tab that hands out every staff, crystal and gem (and the `dev.items` extras) for free (to be removed later).
## A craft tab may name a `group`: then it lists only recipes of that group (the lake witch's STÄBE and STEINE share her bench).
## The look and the staging are `BoardWindow`'s. `ShopWindow.open(tree, player, town, shop_id)`; the person answers from a bubble (lines in the data, placeholders for the
## dialogue writer). Everything with consequences is asked of the host (`TownManager.request_craft / request_order / request_collect / request_trade`).

var shop_id: String = ""
var def: Dictionary = {}
var npc: String = ""
var station: String = "workshop"
var _craft_left: float = 0.0
var _craft_total: float = 1.0
var _craft_id: String = ""
var _brew_tiers: Dictionary = {}


static func open(tree: SceneTree, for_player: Player, for_town: TownManager, id: String = "gustav_bench") -> ShopWindow:
	if tree.get_first_node_in_group("shop_window") != null:
		return null
	var window: ShopWindow = ShopWindow.new()
	window.shop_id = id
	tree.root.add_child(window)
	window.setup_board(for_player, for_town)
	return window


func _setup_board() -> void:
	add_to_group("shop_window")
	def = town.shop(shop_id)
	npc = String(def.get("npc", ""))
	station = String(def.get("station", "workshop"))
	title = String(def.get("title", "HANDEL"))
	for entry: Variant in def.get("tabs", []) as Array:
		tabs.append(entry as Dictionary)
	var person: Node2D = town.person_node(npc)
	speaker = person
	focus_world = person.global_position if person != null else player.global_position
	town.refine_done.connect(_on_refine_done)
	town.brew_done.connect(_on_brew_done)
	town.refresh_done.connect(_on_refresh_done)
	player.inventory.changed.connect(_on_town_changed) ## the bag and the purse change what can be bought and sold
	player.progress.changed.connect(_on_town_changed)
	_say_line("open")


## The weapon came back: the card of the answer plays over the window.
func _on_refine_done(before: Dictionary, after: Dictionary, success: bool, refund: Dictionary) -> void:
	RefineReveal.present(get_tree(), before, after, success, refund)


## The potions came out of the cauldron: the brew card plays over the window.
func _on_brew_done(type: String, level: int, count: int, moon: bool) -> void:
	BrewReveal.present(get_tree(), type, level, count, moon)
	_say_line("brew_moon" if moon else "brew_done")


## Ilva cleaned the raw stones: the card shows what they hid.
func _on_refresh_done(raw: String, stones: Array) -> void:
	StoneReveal.present(get_tree(), raw, stones)
	_say_line("refresh_done")


func _exit_tree() -> void:
	if town != null and town.refresh_done.is_connected(_on_refresh_done):
		town.refresh_done.disconnect(_on_refresh_done)
	if town != null and town.brew_done.is_connected(_on_brew_done):
		town.brew_done.disconnect(_on_brew_done)
	if town != null and town.refine_done.is_connected(_on_refine_done):
		town.refine_done.disconnect(_on_refine_done)
	super()


## A one-off sound of the refinement set (assets/audio/refine/).
func _play_refine(name: String) -> void:
	var voice: AudioStreamPlayer = AudioStreamPlayer.new()
	voice.stream = load("res://assets/audio/refine/%s.wav" % name) as AudioStream
	voice.volume_db = -8.0
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func _say_line(kind: String) -> void:
	var list: Array = (def.get("lines", {}) as Dictionary).get(kind, []) as Array
	if not list.is_empty():
		say(String(list[randi() % list.size()]))


func _kind() -> String:
	return String(tabs[tab].kind) if not tabs.is_empty() else ""


func _subtitle() -> String:
	return ""


func _persona() -> PackedStringArray:
	var spec: Dictionary = town.settler_spec(npc)
	return PackedStringArray([String(spec.get("name", "")), String(spec.get("title", ""))])


func _header_right(right: float, y: float) -> void:
	if _kind() in ["buy", "sell", "grind"]:
		draw_purse(right, y, player.progress.copper)
	else:
		draw_trust(right, y, npc)


func _empty_text() -> String:
	if _kind() == "refine":
		return "DU TRÄGST KEINE WAFFE, DIE %s VERFEINERN KANN" % String(town.settler_spec(npc).get("name", npc))
	return "HIER GIBT ES NICHTS" if _kind() != "sell" else "DU TRÄGST NICHTS, DAS %s WILL" % String(town.settler_spec(npc).get("name", npc))


# ---------- rows ----------

func _item_name(item: String) -> String:
	return String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()


func _needs_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	var inputs: Dictionary = recipe.get("in", {}) as Dictionary
	for item: String in inputs:
		parts.append("%d %s" % [int(inputs[item]), _item_name(item)])
	return "  ".join(parts)


static func duration_text(seconds: float) -> String:
	var whole: int = ceili(seconds)
	return "%d M %02d S" % [whole / 60, whole % 60] if whole >= 60 else "%d S" % whole


func _recipe_row(id: String) -> Dictionary:
	var recipe: Dictionary = town.recipes()[id] as Dictionary
	var out: Dictionary = recipe.get("out", {}) as Dictionary
	var item: String = String(out.keys()[0])
	var by_npc: bool = String(recipe.get("by", "self")) == "npc"
	var why: String = town.order_block(id, player) if by_npc else town.recipe_block(id, player)
	var state: int = OK if why == "" else (LOCKED if "TRAUT" in why else MISSING)
	return {"kind": "order" if by_npc else "craft", "recipe": id, "item": item, "count": int(out[item]), "name": String(recipe.name), "sub": _needs_text(recipe),
		"tag": duration_text(float(recipe.get("work", 0.0))) if by_npc else "", "tag_color": DIM, "state": state, "why": why}


func _rebuild() -> void:
	rows.clear()
	if tabs.is_empty():
		return
	match _kind():
		"craft":
			var group: String = String(tabs[tab].get("group", ""))
			for id: String in town.recipes():
				var made: Dictionary = town.recipes()[id] as Dictionary
				if String(made.get("by", "self")) == "self" and String(made.get("station", "workshop")) == station and (group == "" or String(made.get("group", "")) == group):
					rows.append(_recipe_row(id))
		"grind":
			_rebuild_grind()
		"refresh":
			var refresh: Dictionary = def.get("refresh", {}) as Dictionary
			for raw: String in refresh.get("fee", {}) as Dictionary:
				var have: int = player.inventory.count_item(raw)
				var fee: int = int((refresh.fee as Dictionary)[raw])
				var why: String = CrystalRules.refresh_block(refresh, raw, 1, have, player.progress.copper, town.trust_of(npc))
				rows.append({"kind": "refresh", "item": raw, "count": have, "name": _item_name(raw), "sub": "INHALT VERBORGEN" if have > 0 else "DU HAST KEINEN",
					"state": OK if why == "" else (LOCKED if "VERTRAUEN" in why else MISSING), "why": why, "price": fee})
		"dev":
			for item: String in CrystalRules.dev_items(def.get("dev", {}) as Dictionary):
				rows.append({"kind": "dev", "item": item, "count": 1, "name": _item_name(item), "sub": "DEV: GRATIS", "state": OK, "why": ""})
		"order":
			for i: int in town.orders.size():
				var order: Dictionary = town.orders[i] as Dictionary
				if town.maker_of(order) != npc or TownManager.is_refine(order):
					continue
				var recipe: Dictionary = town.recipes().get(String(order.r), {}) as Dictionary
				var item: String = String((recipe.get("out", {}) as Dictionary).keys()[0])
				var done: bool = bool(order.done)
				var working: bool = not done and town.order_wait(i) <= float(order.left) + 0.01 and i == _first_open()
				rows.append({"kind": "queue", "index": i, "recipe": String(order.r), "item": item, "count": int((recipe.out as Dictionary)[item]), "name": String(recipe.get("name", "?")),
					"sub": "FERTIG, LIEGT AUF DER BANK" if done else ("%s ARBEITET DARAN" % String(town.settler_spec(npc).get("name", npc)) if working else "WARTET"),
					"tag": "ABHOLEN" if done else duration_text(town.order_wait(i)), "tag_color": LIT if done else DIM,
					"state": OK if done else MISSING, "why": "NOCH NICHT FERTIG", "bar": 1.0 - float(order.left) / maxf(float(order.total), 1.0)})
			for id: String in town.recipes():
				var asked: Dictionary = town.recipes()[id] as Dictionary
				if String(asked.get("by", "self")) == "npc" and String(asked.get("npc", "gustav")) == npc:
					rows.append(_recipe_row(id))
		"refine":
			_rebuild_refine()
		"brew":
			_rebuild_brew()
		"buy":
			for entry: Variant in def.get("buy", []) as Array:
				var offer: Dictionary = entry as Dictionary
				var price: int = int(offer.price)
				var locked: bool = town.trust_of(npc) < int(offer.get("trust", 0))
				var poor: bool = player.progress.copper < price
				rows.append({"kind": "buy", "item": String(offer.item), "count": 1, "name": _item_name(String(offer.item)), "sub": "VERTRAUEN %d" % int(offer.trust) if locked else "",
					"coins": price, "poor": poor, "state": LOCKED if locked else (MISSING if poor else OK), "why": "VERTRAUEN %d NÖTIG" % int(offer.trust) if locked else "ZU WENIG GELD", "price": price})
		"sell":
			for entry: Variant in def.get("sell", []) as Array:
				var offer: Dictionary = entry as Dictionary
				var have: int = player.inventory.count_plain(String(offer.item))
				rows.append({"kind": "sell", "item": String(offer.item), "count": have, "name": _item_name(String(offer.item)), "sub": "IM RUCKSACK" if have > 0 else "DU HAST KEINS",
					"coins": int(offer.price),"state": OK if have > 0 else MISSING, "why": "DU HAST KEIN %s" % _item_name(String(offer.item)), "price": int(offer.price)})


## SCHLIFF: one row per crystal or gem in the bag that can still go a tier higher (tier V cannot), with what it would become and what stops it.
func _rebuild_grind() -> void:
	var grind: Dictionary = def.get("grind", {}) as Dictionary
	for item: String in CrystalRules.dev_items({"kinds": ["crystal", "gem"]}):
		if player.inventory.count_plain(item) <= 0:
			continue
		var c: Dictionary = CrystalRules.cost(grind, item)
		if c.is_empty():
			continue
		var have: Dictionary = {item: player.inventory.count_plain(item)}
		for need: String in c.in as Dictionary:
			have[need] = player.inventory.count_plain(need)
		var why: String = CrystalRules.block(grind, item, have, player.progress.copper, town.trust_of(npc))
		rows.append({"kind": "grind", "item": String(c.out), "from": item, "count": 1, "name": _item_name(String(c.out)), "sub": "AUS %d X %s" % [int(c.count), _item_name(item)],
			"state": OK if why == "" else (LOCKED if "VERTRAUEN" in why else MISSING), "why": why, "cost": c, "price": int(c.copper)})


## The alchemy tab: every potion in its five tiers. A tier is locked until the brewer trusts her enough and has brewed the tier below once.
func _rebuild_brew() -> void:
	for type: String in AlchemyRules.TYPES:
		var level: int = int(_brew_tiers.get(type, 1))
		var why: String = town.brew_block(type, level, player, npc)
		var locked: bool = "TRAUT" in why or "ERST STUFE" in why
		rows.append({"kind": "brew", "type": type, "tier": level, "item": AlchemyRules.item_id(type, level), "count": town.brew_yield(type, level),
			"name": "%s %s" % [String(AlchemyRules.potion(type).get("name", type)), AlchemyRules.roman(level)],
			"sub": AlchemyRules.tier_name(level, type),
			"tag": "", "tag_color": DIM,
			"state": OK if why == "" else (LOCKED if locked else MISSING), "why": why})


## The refine tab: the weapons on the anvil first (they wait, work or can be collected), then every refinable weapon she carries or wears.
func _rebuild_refine() -> void:
	for i: int in town.orders.size():
		var order: Dictionary = town.orders[i] as Dictionary
		if town.maker_of(order) != npc or not TownManager.is_refine(order):
			continue
		var weapon: Dictionary = order.w as Dictionary
		var done: bool = bool(order.done)
		var working: bool = not done and town.order_wait(i) <= float(order.left) + 0.01 and i == _first_open()
		rows.append({"kind": "queue", "index": i, "recipe": "refine", "item": String(weapon.id), "count": 1, "level": Items.refine(weapon), "stack": weapon, "name": Items.title(weapon),
			"sub": "FERTIG, LIEGT AUF DER BANK" if done else ("AUF +%d, %s ARBEITET DARAN" % [int(order.to), String(town.settler_spec(npc).get("name", npc))] if working else "AUF +%d, WARTET" % int(order.to)),
			"tag": "ABHOLEN" if done else duration_text(town.order_wait(i)), "tag_color": LIT if done else DIM, "state": OK if done else MISSING, "why": "NOCH NICHT FERTIG",
			"bar": 1.0 - float(order.left) / maxf(float(order.total), 1.0)})
	var worn: Dictionary = player.inventory.equipment.get("main_hand", {}) as Dictionary
	if RefineRules.is_refinable(worn):
		rows.append(_weapon_row("equip", "main_hand", worn))
	for i: int in InventoryComponent.SIZE:
		var stack: Dictionary = player.inventory.slots[i] as Dictionary
		if RefineRules.is_refinable(stack):
			rows.append(_weapon_row("inv", i, stack))


func _weapon_row(slot_kind: String, slot_ref: Variant, stack: Dictionary) -> Dictionary:
	var level: int = Items.refine(stack)
	var can: bool = RefineRules.can_refine(stack)
	var why: String = town.refine_block(stack, player, npc)
	var state: int = OK if why == "" else (LOCKED if ("TRAUT" in why or "HÖHER" in why) else MISSING)
	var odds: float = RefineRules.chance(stack)
	var sub: String = "+%d > +%d" % [level, level + 1] if can else "HÖHER GEHT ES NICHT"
	if slot_kind == "equip":
		sub = "ANGELEGT  " + sub
	return {"kind": "refine", "item": String(stack.id), "count": 1, "level": level, "stack": stack, "name": Items.title(stack), "sub": sub,
		"tag": "%d %%" % roundi(odds * 100.0) if can else "", "tag_color": _odds_color(odds), "state": state, "why": why, "slot_kind": slot_kind, "slot_ref": slot_ref}


## Colour of a chance: good (> 70 %), risky (30 .. 70 %), bad.
func _odds_color(odds: float) -> Color:
	return [LIT, GOLD, BAD][RefineRules.verdict(odds)] as Color


func _first_open() -> int:
	for i: int in town.orders.size():
		if not bool((town.orders[i] as Dictionary).done) and town.maker_of(town.orders[i] as Dictionary) == npc:
			return i
	return -1


func _tab_changed() -> void:
	if _kind() in ["order", "refine"]:
		_say_line("order")
	if _kind() == "brew":
		_first_lesson()


## The first time she opens the alchemy tab Esma explains it and gives her a few empty vials (once per world, the host decides).
func _first_lesson() -> void:
	var lesson: Array = (def.get("lines", {}) as Dictionary).get("brew_intro", []) as Array
	if player.quests != null and not player.quests.has_flag("alchemy_learned"):
		player.quests.set_flag("alchemy_learned")
		if not lesson.is_empty():
			say(String(lesson[0]))
		if not town.alchemy_gift:
			town.request_alchemy_gift(5)
		return
	_say_line("brew")


# ---------- detail ----------

func _detail(area: Rect2, row: Dictionary) -> void:
	var kind: String = String(row.kind)
	var item: String = String(row.item)
	if kind == "refine":
		_detail_refine(area, row)
		return
	if kind == "brew":
		_detail_brew(area, row)
		return
	draw_cell(area.position + Vector2(0, 2), item, 1, true, false, int(row.get("level", 0)))
	var x: float = area.position.x + 46.0
	_text(Vector2(x, area.position.y + 4.0), String(row.name), GOLD)
	var definition: Dictionary = DataRegistry.get_entry("items", item)
	var info: String = String(town.recipes().get(String(row.get("recipe", "")), {}).get("info", "")) if row.has("recipe") else String(definition.get("description", ""))
	var y: float = area.position.y + 16.0
	for line: String in _wrap(info, int(area.size.x) - 52).slice(0, 2):
		_text(Vector2(x, y), line, DIM)
		y += 9.0
	match kind:
		"craft", "order":
			var recipe: Dictionary = town.recipes()[String(row.recipe)] as Dictionary
			var cx: float = area.position.x
			var cy: float = area.position.y + 42.0
			var inputs: Dictionary = recipe.get("in", {}) as Dictionary
			for need_item: String in inputs:
				var width: float = draw_chip(Vector2(cx, cy), need_item, town.available(need_item, player), int(inputs[need_item]))
				cx += width
			if kind == "order":
				var wait: String = "%s BRAUCHT %s" % [String(town.settler_spec(npc).get("name", npc)), duration_text(float(recipe.get("work", 0.0)))]
				if town.orders_of(npc) > 0:
					wait += "  NACH %d AUFTRAG" % town.orders_of(npc)
				_text(Vector2(area.position.x, area.position.y + 64.0), wait, DIM)
		"queue":
			_text(Vector2(area.position.x, area.position.y + 46.0), String(row.sub), LIT if bool((town.orders[int(row.index)] as Dictionary).done) else DIM)
			if not bool((town.orders[int(row.index)] as Dictionary).done):
				var speaker_node: Settler = town.settler_node(npc)
				if speaker_node != null and not speaker_node.is_working():
					_text(Vector2(area.position.x, area.position.y + 58.0), "ER ARBEITET NUR AN DER BANK, NICHT NACHTS UND NICHT IN DER PAUSE", Color(DIM, 0.8))
		"grind":
			var c: Dictionary = row.cost as Dictionary
			var gx: float = area.position.x
			var gy: float = area.position.y + 42.0
			gx += draw_chip(Vector2(gx, gy), String(row.from), player.inventory.count_plain(String(row.from)), int(c.count))
			for need_item: String in c.in as Dictionary:
				gx += draw_chip(Vector2(gx, gy), need_item, player.inventory.count_plain(need_item), int((c.in as Dictionary)[need_item]))
			draw_purse_left(gx, gy + 6.0, int(c.copper), GOLD if player.progress.copper >= int(c.copper) else BAD)
			var made_by: String = "%s SCHLEIFT SOFORT, NICHTS GEHT VERLOREN" % String(town.settler_spec(npc).get("name", npc))
			_text(Vector2(area.position.x, area.position.y + 64.0), made_by if String(row.why) == "" else String(row.why), DIM if String(row.why) == "" else BAD)
		"refresh":
			_text(Vector2(area.position.x, area.position.y + 46.0), "%s WÄSCHT DEN STEIN IM SEE" % String(town.settler_spec(npc).get("name", npc)), GOLD)
			var says: String = "WAS DRIN STECKT, STEHT SEIT DEM FUND FEST. SHIFT: ALLE"
			_text(Vector2(area.position.x, area.position.y + 58.0), says if String(row.why) == "" else String(row.why), DIM if String(row.why) == "" else BAD)
		"dev":
			_text(Vector2(area.position.x, area.position.y + 46.0), "ENTWICKLER: GRATIS IN DEN RUCKSACK. E 1 X, SHIFT 10 X.", DIM)
		"buy", "sell":
			var verb: String = "KOSTET" if kind == "buy" else "ZAHLT"
			var head: String = verb + " "
			_text(Vector2(area.position.x, area.position.y + 46.0), head, GOLD)
			var hx: float = area.position.x + float(PixelText.width(head))
			draw_purse_left(hx, area.position.y + 46.0, int(row.price))
			_text(Vector2(hx + purse_width(int(row.price)) + 2.0, area.position.y + 46.0), "DAS STÜCK", GOLD)
			if kind == "sell":
				var all_head: String = "SHIFT: ALLES  "
				_text(Vector2(area.position.x, area.position.y + 58.0), all_head, DIM)
				draw_purse_left(area.position.x + float(PixelText.width(all_head)), area.position.y + 58.0, int(row.price) * int(row.count))


## The weapon big on the left with its fifteen pearls, what the next level gives, what it costs (material chips and copper), how long Torben needs and the chance as a bar
## (the gold piece is the Glut of earlier failures), with Torben's verdict beside it.
func _detail_refine(area: Rect2, row: Dictionary) -> void:
	var stack: Dictionary = row.stack as Dictionary
	var level: int = Items.refine(stack)
	var cap: int = RefineRules.cap(stack)
	draw_cell(area.position + Vector2(0, 2), String(row.item), 1, true, false, level)
	var x: float = area.position.x + 46.0
	_text(Vector2(x, area.position.y + 2.0), String(row.name), GOLD)
	RefineStyle.draw_pearls(_canvas, Vector2(x, area.position.y + 14.0), level, cap, 1.0, _time)
	_text(Vector2(x + float(RefineStyle.pearls_width()) + 6.0, area.position.y + 12.0), "%d/%d" % [level, cap], RefineStyle.color(level))
	if not RefineRules.can_refine(stack):
		_text(Vector2(x, area.position.y + 28.0), "HÖHER GEHT ES NICHT.", DIM)
		return
	var target: int = RefineRules.next_level(stack)
	var after: Dictionary = RefineRules.result(stack, true)
	var damage_now: float = Items.stat(stack, "damage")
	var gains: String = "SCHADEN %s > %s" % [_num(damage_now), _num(Items.stat(after, "damage"))]
	for m: Dictionary in RefineRules.milestones(target):
		if int(m.level) == target:
			gains += "   +%d %s" % [target, String(m.get("name", ""))]
	_text(Vector2(x, area.position.y + 24.0), gains, LIT)
	var cx: float = area.position.x
	var cy: float = area.position.y + 36.0
	var mats: Dictionary = RefineRules.materials(stack, target)
	for need_item: String in mats:
		cx += draw_chip(Vector2(cx, cy), need_item, town.available(need_item, player), int(mats[need_item]))
	var price: int = RefineRules.copper(stack, target)
	draw_purse_left(cx, cy + 6.0, price, GOLD if player.progress.copper >= price else BAD)
	var right: float = area.end.x - 4.0
	var wait: String = "%s SCHMIEDET SOFORT" % String(town.settler_spec(npc).get("name", npc))
	_text(Vector2(right - float(PixelText.width(wait)), area.position.y + 4.0), wait, DIM)
	var odds: float = RefineRules.chance(stack)
	var glut: float = RefineRules.pity_bonus(stack)
	var tone: Color = _odds_color(odds)
	var bar_y: float = area.position.y + 60.0
	_canvas.draw_rect(Rect2(area.position.x, bar_y, 150.0, 6.0), UiStyle.OUTLINE)
	_canvas.draw_rect(Rect2(area.position.x + 1.0, bar_y + 1.0, 148.0, 4.0), Color(0, 0, 0, 0.55))
	_canvas.draw_rect(Rect2(area.position.x + 1.0, bar_y + 1.0, 148.0 * clampf(odds - glut, 0.0, 1.0), 4.0), tone)
	if glut > 0.0:
		_canvas.draw_rect(Rect2(area.position.x + 1.0 + 148.0 * (odds - glut), bar_y + 1.0, 148.0 * glut, 4.0), Color("fff0b0"))
	var odds_text: String = "CHANCE %d %%" % roundi(odds * 100.0)
	if glut > 0.0:
		odds_text += "  GLUT +%d %%" % roundi(glut * 100.0)
	_text(Vector2(area.position.x + 158.0, bar_y), odds_text, tone)
	var lines: Dictionary = def.get("lines", {}) as Dictionary
	var key: String = "verdict_last" if target >= RefineRules.max_level() else ["verdict_good", "verdict_risky", "verdict_bad"][RefineRules.verdict(odds)]
	var verdicts: Array = lines.get(key, []) as Array
	if not verdicts.is_empty():
		var quote: String = String(verdicts[0])
		_text(Vector2(right - float(PixelText.width(quote)), bar_y), quote, TEXT)
	if String(row.slot_kind) == "equip":
		_text(Vector2(right - float(PixelText.width("ANGELEGT, DANN HAST DU KEINE WAFFE")), area.position.y + 24.0), "ANGELEGT, DANN HAST DU KEINE WAFFE", Color(BAD, 0.8))


## The potion big on the left with its five tier pips, what it does, the ingredients (have / need), how many come out and what stops it.
func _detail_brew(area: Rect2, row: Dictionary) -> void:
	var type: String = String(row.type)
	var level: int = int(row.tier)
	var tone: Color = AlchemyRules.color(type)
	draw_cell(area.position + Vector2(0, 2), String(row.item), int(row.count), true, int(row.state) == LOCKED)
	var x: float = area.position.x + 46.0
	_text(Vector2(x, area.position.y + 2.0), String(row.name), GOLD)
	for k: int in AlchemyRules.tier_count(type): ## the tiers (five, special potions three) as drops: filled up to this one
		var pip: Vector2 = Vector2(x + float(k) * 7.0, area.position.y + 13.0)
		var lit: bool = k < level
		_canvas.draw_rect(Rect2(pip, Vector2(5, 5)), UiStyle.OUTLINE)
		_canvas.draw_rect(Rect2(pip + Vector2.ONE, Vector2(3, 3)), tone if lit else Color(0.1, 0.06, 0.16))
		if lit:
			_canvas.draw_rect(Rect2(pip + Vector2.ONE, Vector2.ONE), AlchemyRules.light(type))
	_text(Vector2(x + 40.0, area.position.y + 12.0), AlchemyRules.tier_name(level, type), tone)
	var definition: Dictionary = DataRegistry.get_entry("items", String(row.item))
	var y: float = area.position.y + 22.0
	for line: String in _wrap(String(definition.get("description", "")), int(area.size.x) - 52).slice(0, 2):
		_text(Vector2(x, y), line, DIM)
		y += 9.0
	var cx: float = area.position.x
	var cy: float = area.position.y + 42.0
	var need: Dictionary = AlchemyRules.ingredients(type, level)
	for item: String in need:
		if cx > area.end.x - 40.0:
			cx = area.position.x
			cy += 14.0
		cx += draw_chip(Vector2(cx, cy), item, player.inventory.count_item(item), int(need[item]))
	var maker: String = String(town.settler_spec(npc).get("name", npc))
	var out: String = "%s BRAUT %d %s SOFORT" % [maker, int(row.count), "TRANK" if int(row.count) == 1 else "TRÄNKE"]
	if town.brew_yield(type, level) > AlchemyRules.base_yield(type, level):
		out += "  VOLLMOND +%d" % (town.brew_yield(type, level) - AlchemyRules.base_yield(type, level))
	_text(Vector2(area.position.x, cy + 18.0), out, LIT if int(row.state) == OK else DIM)
	if String(row.why) != "":
		_text(Vector2(area.position.x, cy + 28.0), String(row.why), BAD if int(row.state) == MISSING else DIM)


func _num(value: float) -> String:
	return "%d" % value if is_equal_approx(value, roundf(value)) else ("%.1f" % value if absf(value * 10.0 - roundf(value * 10.0)) < 0.001 else "%.2f" % value)


# ---------- buttons and actions ----------

func _process(delta: float) -> void:
	super(delta)
	if _craft_left > 0.0:
		_craft_left -= delta
		if _craft_left <= 0.0:
			town.request_craft(_craft_id)
			_craft_id = ""
			_say_line("craft")


func _buttons() -> Array[Dictionary]:
	var row: Dictionary = _focused()
	if row.is_empty():
		return []
	var ready: bool = int(row.state) == OK
	match String(row.kind):
		"craft":
			return [{"id": "craft", "label": "FERTIGEN", "ready": ready and _craft_left <= 0.0, "progress": 1.0 - _craft_left / _craft_total if _craft_left > 0.0 else -1.0}]
		"order":
			return [{"id": "order", "label": "BESTELLEN", "ready": ready}]
		"queue":
			return [{"id": "collect", "label": "ABHOLEN", "ready": ready}]
		"refine":
			return [{"id": "refine", "label": "VERFEINERN", "ready": ready}]
		"brew":
			return [{"id": "brew", "label": "BRAUEN LASSEN", "ready": ready}]
		"buy":
			return [{"id": "buy", "label": "KAUFEN", "ready": ready}, {"id": "buy10", "label": "10 X", "ready": ready and player.progress.copper >= int(row.price) * 2}]
		"sell":
			return [{"id": "sell", "label": "VERKAUFEN", "ready": ready}, {"id": "sell_all", "label": "ALLES", "ready": ready}]
		"grind":
			return [{"id": "grind", "label": "SCHLEIFEN", "ready": ready}]
		"refresh":
			return [{"id": "refresh", "label": "LÄUTERN", "ready": ready}, {"id": "refresh_all", "label": "ALLE", "ready": ready and int(row.count) > 1}]
		"dev":
			return [{"id": "dev", "label": "GEBEN", "ready": true}, {"id": "dev10", "label": "10 X", "ready": true}]
	return []


func _press(id: String, bulk: bool) -> void:
	var row: Dictionary = _focused()
	match id:
		"craft":
			if _craft_left > 0.0:
				return
			_craft_id = String(row.recipe)
			_craft_total = maxf(float((town.recipes()[_craft_id] as Dictionary).get("seconds", 1.0)), 0.3)
			_craft_left = _craft_total
			_sound("tick")
		"order":
			town.request_order(String(row.recipe))
			_say_line("order")
		"collect":
			town.request_collect(int(row.index))
			_say_line("collect")
		"brew":
			town.request_brew(String(row.type), int(row.tier), shop_id)
			_say_line("brew")
		"refine":
			town.request_refine(String(row.slot_kind), row.slot_ref, shop_id)
			_say_line("refine")
			_play_refine("hand_in")
		"buy", "buy10":
			town.request_trade(shop_id, "buy", String(row.item), 10 if (id == "buy10" or bulk) else 1)
			_sound("coin")
			_say_line("buy")
		"sell", "sell_all":
			town.request_trade(shop_id, "sell", String(row.item), int(row.count) if (id == "sell_all" or bulk) else 1)
			_sound("coin")
			_say_line("sell")
		"grind":
			town.request_grind(shop_id, String(row.from))
			_sound("coin")
			_say_line("grind")
		"refresh", "refresh_all":
			var all: int = int(row.count) if int(row.price) <= 0 else mini(int(row.count), player.progress.copper / int(row.price))
			town.request_refresh(shop_id, String(row.item), all if (id == "refresh_all" or bulk) else 1)
			_sound("tick")
		"dev", "dev10":
			town.request_dev_give(shop_id, String(row.item), 10 if (id == "dev10" or bulk) else 1)
			_sound("tick")


# Compact brew families: one persistent selection per potion, including locked tiers.
func _brew_tier_rect(rect: Rect2, level: int) -> Rect2:
	return Rect2(rect.end.x - 126.0 + float(level - 1) * 24.0, rect.position.y + 1.0, 22.0, 19.0)


func _draw_list(card: Rect2) -> void:
	super(card)
	if _kind() != "brew":
		return
	for v: int in VISIBLE_ROWS:
		if scroll + v >= rows.size():
			break
		var row: Dictionary = rows[scroll + v]
		for level: int in range(1, AlchemyRules.tier_count(String(row.type)) + 1):
			var rect: Rect2 = _brew_tier_rect(_row_rect(v), level)
			var item: String = AlchemyRules.item_id(String(row.type), level)
			var why: String = town.brew_block(String(row.type), level, player, npc)
			var locked: bool = "TRAUT" in why or "ERST STUFE" in why
			var selected: bool = int(row.tier) == level
			var tone: Color = Items.rarity_color({"id": item})
			_canvas.draw_rect(rect, tone if selected else Color(tone, 0.4))
			_canvas.draw_rect(rect.grow(-1), UiStyle.SLOT_BG)
			if selected:
				_canvas.draw_rect(rect.grow(-2), Color(tone, 0.25))
			var label: String = AlchemyRules.roman(level)
			_text(rect.position + Vector2((22.0 - PixelText.width(label)) / 2.0, 5), label, DIM if locked else TEXT)
			_canvas.draw_rect(Rect2(rect.position + Vector2(5, 15), Vector2(12, 1)), DIM if locked else (LIT if why == "" else GOLD))


func _choose_brew_tier(index: int, level: int) -> void:
	focus = index
	_brew_tiers[String(rows[index].type)] = clampi(level, 1, AlchemyRules.tier_count(String(rows[index].type)))
	_rebuild()
	_sound("tick")
	_canvas.queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if not _closing and _kind() == "brew" and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		for v: int in VISIBLE_ROWS:
			if scroll + v >= rows.size():
				break
			for level: int in range(1, AlchemyRules.tier_count(String(rows[scroll + v].type)) + 1):
				if _brew_tier_rect(_row_rect(v), level).has_point(click.position):
					_choose_brew_tier(scroll + v, level)
					_canvas.accept_event()
					return
	super(event)


func _input(event: InputEvent) -> void:
	if not _closing and _kind() == "brew" and not rows.is_empty():
		var left: bool = event.is_action_pressed("ui_left") or event.is_action_pressed("move_left")
		var right: bool = event.is_action_pressed("ui_right") or event.is_action_pressed("move_right")
		if left or right:
			_choose_brew_tier(focus, posmod(int(rows[focus].tier) - 1 + (-1 if left else 1), AlchemyRules.tier_count(String(rows[focus].type))) + 1)
			get_viewport().set_input_as_handled()
			return
	super(event)


func _hint() -> String:
	return "W S TRANK   A D STUFE   E BRAUEN   ESC ZURÜCK" if _kind() == "brew" else super()
