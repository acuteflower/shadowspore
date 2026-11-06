class_name ShopWindow
extends BoardWindow
## The reusable shop of the town (data/shops.json, one entry per person-and-place; Gustav's workbench is the first, the forge, the kitchen and the market use the same).
## A shop's tabs say what it offers; each one is a `kind`:
##   craft - things you make yourself at the bench (recipes with `by: "self"`): a short bar fills, then the host swaps material for the result;
##   order - things only the person can make (recipes with `by: "npc"`, `work` seconds): the material is handed over, the person works on it *while they are at their bench*
##           (so it stops at night and when they take a break), the finished piece waits on the bench until anybody collects it; the queue is the town's, not yours;
##   buy   - the person sells (`buy` list: item, price in copper, `trust`);
##   sell  - the person buys from your bag (`sell` list).
## The look and the staging are `BoardWindow`'s. `ShopWindow.open(tree, player, town, shop_id)`; the person answers from a bubble (lines in the data, placeholders for the
## dialogue writer). Everything with consequences is asked of the host (`TownManager.request_craft / request_order / request_collect / request_trade`).

var shop_id: String = ""
var def: Dictionary = {}
var npc: String = ""
var _craft_left: float = 0.0
var _craft_total: float = 1.0
var _craft_id: String = ""


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
	title = String(def.get("title", "HANDEL"))
	for entry: Variant in def.get("tabs", []) as Array:
		tabs.append(entry as Dictionary)
	var person: Settler = town.settler_node(npc)
	speaker = person
	focus_world = person.global_position if person != null else player.global_position
	player.inventory.changed.connect(_on_town_changed) ## the bag and the purse change what can be bought and sold
	player.progress.changed.connect(_on_town_changed)
	_say_line("open")


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
	if _kind() in ["buy", "sell"]:
		draw_purse(right, y, player.progress.copper)
	else:
		draw_trust(right, y, npc)


func _empty_text() -> String:
	return "HIER GIBT ES NICHTS" if _kind() != "sell" else "DU TRÄGST NICHTS, DAS GUSTAV WILL"


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
			for id: String in town.recipes():
				if String((town.recipes()[id] as Dictionary).get("by", "self")) == "self":
					rows.append(_recipe_row(id))
		"order":
			for i: int in town.orders.size():
				var order: Dictionary = town.orders[i] as Dictionary
				var recipe: Dictionary = town.recipes().get(String(order.r), {}) as Dictionary
				var item: String = String((recipe.get("out", {}) as Dictionary).keys()[0])
				var done: bool = bool(order.done)
				var working: bool = not done and town.order_wait(i) <= float(order.left) + 0.01 and i == _first_open()
				rows.append({"kind": "queue", "index": i, "recipe": String(order.r), "item": item, "count": int((recipe.out as Dictionary)[item]), "name": String(recipe.get("name", "?")),
					"sub": "FERTIG, LIEGT AUF DER BANK" if done else ("%s ARBEITET DARAN" % String(town.settler_spec(npc).get("name", npc)) if working else "WARTET"),
					"tag": "ABHOLEN" if done else duration_text(town.order_wait(i)), "tag_color": LIT if done else DIM,
					"state": OK if done else MISSING, "why": "NOCH NICHT FERTIG", "bar": 1.0 - float(order.left) / maxf(float(order.total), 1.0)})
			for id: String in town.recipes():
				if String((town.recipes()[id] as Dictionary).get("by", "self")) == "npc":
					rows.append(_recipe_row(id))
		"buy":
			for entry: Variant in def.get("buy", []) as Array:
				var offer: Dictionary = entry as Dictionary
				var price: int = int(offer.price)
				var locked: bool = town.trust_of(npc) < int(offer.get("trust", 0))
				var poor: bool = player.progress.copper < price
				rows.append({"kind": "buy", "item": String(offer.item), "count": 1, "name": _item_name(String(offer.item)), "sub": "VERTRAUEN %d" % int(offer.trust) if locked else "",
					"tag": Currency.short_text(price), "tag_color": GOLD, "state": LOCKED if locked else (MISSING if poor else OK), "why": "VERTRAUEN %d NÖTIG" % int(offer.trust) if locked else "ZU WENIG GELD", "price": price})
		"sell":
			for entry: Variant in def.get("sell", []) as Array:
				var offer: Dictionary = entry as Dictionary
				var have: int = player.inventory.count_item(String(offer.item))
				rows.append({"kind": "sell", "item": String(offer.item), "count": have, "name": _item_name(String(offer.item)), "sub": "IM RUCKSACK" if have > 0 else "DU HAST KEINS",
					"tag": Currency.short_text(int(offer.price)), "tag_color": GOLD, "state": OK if have > 0 else MISSING, "why": "DU HAST KEIN %s" % _item_name(String(offer.item)), "price": int(offer.price)})


func _first_open() -> int:
	for i: int in town.orders.size():
		if not bool((town.orders[i] as Dictionary).done):
			return i
	return -1


func _tab_changed() -> void:
	if _kind() == "order":
		_say_line("order")


# ---------- detail ----------

func _detail(area: Rect2, row: Dictionary) -> void:
	var kind: String = String(row.kind)
	var item: String = String(row.item)
	draw_cell(area.position + Vector2(0, 2), item, 1, true)
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
				if town.orders.size() > 0:
					wait += "  NACH %d AUFTRAG" % town.orders.size()
				_text(Vector2(area.position.x, area.position.y + 64.0), wait, DIM)
		"queue":
			_text(Vector2(area.position.x, area.position.y + 46.0), String(row.sub), LIT if bool((town.orders[int(row.index)] as Dictionary).done) else DIM)
			if not bool((town.orders[int(row.index)] as Dictionary).done):
				var speaker_node: Settler = town.settler_node(npc)
				if speaker_node != null and not speaker_node.is_working():
					_text(Vector2(area.position.x, area.position.y + 58.0), "ER ARBEITET NUR AN DER BANK, NICHT NACHTS UND NICHT IN DER PAUSE", Color(DIM, 0.8))
		"buy", "sell":
			var verb: String = "KOSTET" if kind == "buy" else "ZAHLT"
			_text(Vector2(area.position.x, area.position.y + 46.0), "%s %s DAS STÜCK" % [verb, Currency.short_text(int(row.price))], GOLD)
			if kind == "sell":
				_text(Vector2(area.position.x, area.position.y + 58.0), "SHIFT: ALLES  (%s)" % Currency.short_text(int(row.price) * int(row.count)), DIM)


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
		"buy":
			return [{"id": "buy", "label": "KAUFEN", "ready": ready}, {"id": "buy10", "label": "10 X", "ready": ready and player.progress.copper >= int(row.price) * 2}]
		"sell":
			return [{"id": "sell", "label": "VERKAUFEN", "ready": ready}, {"id": "sell_all", "label": "ALLES", "ready": ready}]
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
		"buy", "buy10":
			town.request_trade(shop_id, "buy", String(row.item), 10 if (id == "buy10" or bulk) else 1)
			_sound("coin")
			_say_line("buy")
		"sell", "sell_all":
			town.request_trade(shop_id, "sell", String(row.item), int(row.count) if (id == "sell_all" or bulk) else 1)
			_sound("coin")
			_say_line("sell")
