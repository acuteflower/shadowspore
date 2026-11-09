class_name StockWindow
extends BoxWindow
## The town's stock at a stockpile: the shared `ItemBox` of `TownManager` as slots, next to the player's own bag (see `BoxWindow`: click, half, one, shift-click, cursor stack).
## The host decides every move (`InventoryComponent` kind "box"; the stockpile's reach is checked by `TownManager.box`).

var town: TownManager


static func open(tree: SceneTree, for_player: Player, for_town: TownManager, _at: Vector2 = Vector2.INF) -> StockWindow:
	if tree.get_first_node_in_group("board_window") != null:
		return null
	var window: StockWindow = StockWindow.new()
	window.town = for_town
	tree.root.add_child(window)
	window.setup(for_player, for_town.box, "STADTLAGER")
	return window


func _subtitle() -> String:
	var total: int = 0
	for item: String in town.stock:
		total += int(town.stock[item])
	return "%d ARTEN  %d TEILE GEMEINSAMER VORRAT" % [town.stock.size(), total]
