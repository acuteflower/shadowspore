class_name StockWindow
extends BoardWindow
## The town's stock at a stockpile, in the board look of every town window (`BoardWindow`): the camera draws close and frames the stockpile on the left, the board hangs on
## the right. Two tabs: LAGER (what the town holds; E takes ten, Shift takes all) and RUCKSACK (what you carry that may be stowed: materials and food; E stows ten,
## Shift all). The rows scroll, so the stock can hold as many kinds as the game has. The host decides every move (`TownManager.request_stock`).

const STOWABLE: Array[String] = ["material", "consumable"]


static func open(tree: SceneTree, for_player: Player, for_town: TownManager, at: Vector2 = Vector2.INF) -> StockWindow:
	if tree.get_first_node_in_group("stock_window") != null:
		return null
	var window: StockWindow = StockWindow.new()
	tree.root.add_child(window)
	window.focus_world = at if at != Vector2.INF else for_player.global_position
	window.setup_board(for_player, for_town)
	return window


func _setup_board() -> void:
	add_to_group("stock_window")
	title = "STADTLAGER"
	tabs = [{"id": "stock", "name": "LAGER"}, {"id": "bag", "name": "RUCKSACK"}]
	tab = 0 if not town.stock.is_empty() else 1
	player.inventory.changed.connect(_on_town_changed)


func _subtitle() -> String:
	var total: int = 0
	for item: String in town.stock:
		total += int(town.stock[item])
	return "%d ARTEN  %d TEILE GEMEINSAMER VORRAT" % [town.stock.size(), total]


func _empty_text() -> String:
	return "NOCH NICHTS IM LAGER" if tab == 0 else "NICHTS IM RUCKSACK, DAS INS LAGER DARF"


func _hint() -> String:
	return "W S WÄHLEN   A D REITER   E 10   SHIFT ALLES   ESC ZURÜCK"


func _name_of(item: String) -> String:
	return String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()


func _rebuild() -> void:
	rows.clear()
	if tab == 0:
		var ids: Array = town.stock.keys()
		ids.sort_custom(func(a: Variant, b: Variant) -> bool: return _name_of(String(a)) < _name_of(String(b)))
		for item: Variant in ids:
			rows.append({"kind": "take", "item": String(item), "count": int(town.stock[item]), "name": _name_of(String(item)), "sub": "IM RUCKSACK: %d" % player.inventory.count_item(String(item)) if player.inventory.count_item(String(item)) > 0 else "", "state": OK})
	else:
		var counts: Dictionary = {}
		for stack: Dictionary in player.inventory.slots:
			if not stack.is_empty() and String(Items.definition(stack).get("kind", "")) in STOWABLE:
				counts[String(stack.id)] = int(counts.get(String(stack.id), 0)) + int(stack.count)
		var ids: Array = counts.keys()
		ids.sort_custom(func(a: Variant, b: Variant) -> bool: return _name_of(String(a)) < _name_of(String(b)))
		for item: Variant in ids:
			rows.append({"kind": "put", "item": String(item), "count": int(counts[item]), "name": _name_of(String(item)), "sub": "IM LAGER: %d" % int(town.stock.get(item, 0)) if town.stock.has(item) else "", "state": OK})


func _detail(area: Rect2, row: Dictionary) -> void:
	var item: String = String(row.item)
	draw_cell(area.position + Vector2(0, 2), item, 1, true)
	var x: float = area.position.x + 46.0
	_text(Vector2(x, area.position.y + 4.0), String(row.name), GOLD)
	var y: float = area.position.y + 16.0
	for line: String in _wrap(String(DataRegistry.get_entry("items", item).get("description", "")), int(area.size.x) - 52).slice(0, 2):
		_text(Vector2(x, y), line, DIM)
		y += 9.0
	_text(Vector2(area.position.x, area.position.y + 46.0), "IM LAGER %d" % int(town.stock.get(item, 0)), LIT)
	_text(Vector2(area.position.x + 90.0, area.position.y + 46.0), "IM RUCKSACK %d" % player.inventory.count_item(item), TEXT)


func _buttons() -> Array[Dictionary]:
	var have_rows: bool = not rows.is_empty()
	if tab == 0:
		return [{"id": "take", "label": "NEHMEN", "ready": have_rows}, {"id": "take_all", "label": "ALLES", "ready": have_rows}]
	var any: bool = false
	for stack: Dictionary in player.inventory.slots:
		if not stack.is_empty() and String(Items.definition(stack).get("kind", "")) == "material":
			any = true
	return [{"id": "put", "label": "EINLAGERN", "ready": have_rows}, {"id": "put_all", "label": "ALLES MATERIAL", "ready": any}]


func _press(id: String, bulk: bool) -> void:
	var row: Dictionary = _focused()
	match id:
		"take", "take_all":
			if not row.is_empty():
				town.request_stock("take", String(row.item), 999 if (id == "take_all" or bulk) else 10)
		"put", "put_all":
			if id == "put_all":
				town.request_stock("deposit_all", "", 0)
			elif not row.is_empty():
				town.request_stock("deposit", String(row.item), 999 if bulk else 10)
	_sound("tick")
