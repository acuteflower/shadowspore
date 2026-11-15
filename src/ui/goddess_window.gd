class_name GoddessWindow
extends BoardWindow
## Caelia's celestial exchange & star-shard collection altar in the Star Hall.
## Tab 0 (`STERNENGABEN`): trade `star_shard` ("Sternerz") for unique starlight consumables, talismans, and `blade_starlight`.
## Tab 1 (`SAMMLUNG`): donate shards directly and claim permanent celestial milestones as total offered/traded shards grow.

var goddess: StarHallGoddess
var sys: GoddessSystem


static func open(tree: SceneTree, for_player: Player, for_town: TownManager, for_goddess: StarHallGoddess) -> BoardWindow:
	if tree == null or tree.get_first_node_in_group("board_window") != null or for_player == null:
		return null
	var script_res: GDScript = load("res://src/ui/goddess_window.gd") as GDScript
	var window: BoardWindow = script_res.new() as BoardWindow
	window.set("goddess", for_goddess)
	window.set("sys", GoddessSystem.of(tree))
	tree.root.add_child(window)
	window.setup_board(for_player, for_town)
	return window


func _setup_board() -> void:
	add_to_group("goddess_window")
	title = "STERNENALTAR"
	tabs.append({"id": "gifts", "name": "STERNENGABEN"})
	tabs.append({"id": "collection", "name": "SAMMLUNG"})
	if is_instance_valid(goddess):
		focus_world = goddess.global_position + Vector2(0.0, -24.0)
	else:
		focus_world = player.global_position + Vector2(0.0, -24.0)
	if sys != null:
		if not sys.state_changed.is_connected(_on_sys_changed):
			sys.state_changed.connect(_on_sys_changed)
		if not sys.notice.is_connected(_on_notice):
			sys.notice.connect(_on_notice)
	if player != null and player.inventory != null:
		if not player.inventory.changed.is_connected(_on_town_changed):
			player.inventory.changed.connect(_on_town_changed)


func _close() -> void:
	_disconnect_altar_signals()
	super._close()


func _exit_tree() -> void:
	_disconnect_altar_signals()
	super._exit_tree()


func _disconnect_altar_signals() -> void:
	if sys != null:
		if sys.state_changed.is_connected(_on_sys_changed):
			sys.state_changed.disconnect(_on_sys_changed)
		if sys.notice.is_connected(_on_notice):
			sys.notice.disconnect(_on_notice)
	if is_instance_valid(player) and player.inventory != null:
		if player.inventory.changed.is_connected(_on_town_changed):
			player.inventory.changed.disconnect(_on_town_changed)


func _on_sys_changed(_peer_id: int) -> void:
	_on_town_changed()


func _persona() -> PackedStringArray:
	return PackedStringArray(["CAELIA", "HÜTERIN DES ERSTEN LICHTS"])


func _shard_count() -> int:
	if player == null or player.inventory == null:
		return 0
	return player.inventory.count_item("star_shard")


func _collected_count() -> int:
	return sys.shards_collected(player) if sys != null else 0


func _subtitle() -> String:
	if tab == 1:
		return "DARGEBRACHTE SPLITTER: %d" % _collected_count()
	return "STERNSPLITTER GEGEN CAELIAS GABEN TAUSCHEN"


func _header_right(right: float, y: float) -> void:
	var have: int = _shard_count()
	var label: String = "STERNERZ: %d" % have
	var w: int = PixelText.width(label)
	var icon: Texture2D = Items.icon({"id": "star_shard"})
	if icon != null:
		_canvas.draw_texture_rect(icon, Rect2(right - float(w) - 18.0, y - 5.0, 14.0, 14.0), false)
	_text(Vector2(right - float(w), y), label, GOLD if have > 0 else DIM)


func _rebuild() -> void:
	rows.clear()
	var have: int = _shard_count()
	var collected: int = _collected_count()
	if tab == 0:
		for offer: Dictionary in GoddessSystem.OFFERS:
			var item_id: String = String(offer["item"])
			var count: int = int(offer["count"])
			var cost: int = int(offer["cost"])
			var def: Dictionary = DataRegistry.get_entry("items", item_id)
			var ok: bool = have >= cost
			var kind_label: String = _kind_label(def)
			rows.append({
				"kind": "offer",
				"offer": offer,
				"item": item_id,
				"count": count,
				"cost": cost,
				"name": String(def.get("name", item_id)).to_upper(),
				"sub": "%d STERNERZ - %s" % [cost, kind_label],
				"tag": "%d STERNERZ" % cost,
				"tag_color": LIT if ok else BAD,
				"state": OK if ok else MISSING,
				"why": "" if ok else "DIR FEHLEN %d STERNERZ" % (cost - have),
			})
		return

	# Tab 1: SAMMLUNG — direct shard donation + 4 milestones
	rows.append({
		"kind": "donate",
		"item": "star_shard",
		"count": 1,
		"name": "STERNERZ DARBRINGEN",
		"sub": "STÄRKT DEN SAAL & ERWECKT MEILENSTEINE",
		"tag": "VORRAT: %d" % have,
		"tag_color": LIT if have >= 1 else DIM,
		"state": OK if have >= 1 else MISSING,
		"why": "" if have >= 1 else "KEIN STERNERZ IM BEUTEL",
	})
	for m: Dictionary in GoddessSystem.MILESTONES:
		var mid: String = String(m["id"])
		var threshold: int = int(m["threshold"])
		var claimed: bool = sys != null and sys.has_milestone(player, mid)
		var reached: bool = collected >= threshold
		var tag_text: String = "ERHALTEN" if claimed else ("BEREIT!" if reached else "%d / %d" % [mini(collected, threshold), threshold])
		var tag_col: Color = LIT if claimed else (GOLD if reached else DIM)
		var st: int = OK if (claimed or reached) else LOCKED
		rows.append({
			"kind": "milestone",
			"milestone": m,
			"id": mid,
			"item": String(m["reward"]),
			"count": int(m["reward_count"]),
			"threshold": threshold,
			"claimed": claimed,
			"reached": reached,
			"name": String(m["title"]),
			"sub": String(m["summary"]),
			"tag": tag_text,
			"tag_color": tag_col,
			"state": st,
			"why": "" if (reached and not claimed) else ("BEREITS EMPFANGEN" if claimed else "NOCH %d STERNERZ DARBRINGEN" % (threshold - collected)),
		})


func _kind_label(def: Dictionary) -> String:
	match String(def.get("kind", "")):
		"weapon":
			return "WAFFE"
		"talisman":
			return "TALISMAN"
		"consumable":
			return "ELIXIER" if String(def.get("id", "")) == "stardust_elixir" else "VERBRAUCH"
	return "GABE"


func _detail(area: Rect2, row: Dictionary) -> void:
	var kind: String = String(row.get("kind", ""))
	if kind == "offer":
		_detail_offer(area, row)
	elif kind == "donate":
		_detail_donate(area)
	elif kind == "milestone":
		_detail_milestone(area, row)


func _detail_offer(area: Rect2, row: Dictionary) -> void:
	var item_id: String = String(row.get("item", ""))
	var count: int = int(row.get("count", 1))
	var cost: int = int(row.get("cost", 1))
	var have: int = _shard_count()
	var def: Dictionary = DataRegistry.get_entry("items", item_id)
	draw_cell(area.position + Vector2(0, 2), item_id, count, true, have < cost)
	var x: float = area.position.x + 44.0
	_text(Vector2(x, area.position.y + 2.0), String(row.get("name", "")), Items.rarity_color({"id": item_id}))
	var y: float = area.position.y + 13.0
	for line: String in _wrap(String(def.get("description", "")), int(area.size.x) - 50).slice(0, 2):
		_text(Vector2(x, y), line, DIM)
		y += 9.0
	var summary: String = _item_stats_summary(def)
	if summary != "":
		_text(Vector2(x, area.position.y + 33.0), summary, LIT)
	draw_chip(Vector2(area.position.x, area.position.y + 48.0), "star_shard", have, cost)
	if String(row.get("why", "")) != "":
		_text(Vector2(area.position.x + 68.0, area.position.y + 54.0), String(row.get("why", "")), BAD)


func _detail_donate(area: Rect2) -> void:
	var have: int = _shard_count()
	var collected: int = _collected_count()
	draw_cell(area.position + Vector2(0, 2), "star_shard", 1, true, have < 1)
	var x: float = area.position.x + 44.0
	_text(Vector2(x, area.position.y + 2.0), "STERNERZ AM ALTAR WEIHEN", GOLD)
	var line1: String = "JEDER EINGETAUSCHTE ODER DARGEBRACHTE SPLITTER STÄRKT CAELIAS SEGEN."
	var y: float = area.position.y + 13.0
	for line: String in _wrap(line1, int(area.size.x) - 50).slice(0, 2):
		_text(Vector2(x, y), line, DIM)
		y += 9.0
	_text(Vector2(x, area.position.y + 33.0), "AKTUELL GESAMMELT: %d SPLITTER  -  HEILT +15 LEBEN" % collected, LIT)
	draw_chip(Vector2(area.position.x, area.position.y + 48.0), "star_shard", have, 1)


func _detail_milestone(area: Rect2, row: Dictionary) -> void:
	var m: Dictionary = row.get("milestone", {}) as Dictionary
	var reward_id: String = String(m.get("reward", ""))
	var threshold: int = int(m.get("threshold", 1))
	var collected: int = _collected_count()
	var claimed: bool = bool(row.get("claimed", false))
	var reached: bool = bool(row.get("reached", false))
	draw_cell(area.position + Vector2(0, 2), reward_id, int(m.get("reward_count", 1)), true, not claimed and not reached)
	var x: float = area.position.x + 44.0
	_text(Vector2(x, area.position.y + 2.0), String(m.get("title", "")), GOLD)
	_text(Vector2(x, area.position.y + 13.0), "SCHWELLE: %d STERNERZ  (GESAMMELT: %d)" % [threshold, collected], LIT if reached else DIM)
	_text(Vector2(x, area.position.y + 24.0), String(m.get("summary", "")), TEXT)
	var bar_y: float = area.position.y + 39.0
	var bar_w: float = area.size.x - 4.0
	_canvas.draw_rect(Rect2(area.position.x, bar_y, bar_w, 5.0), UiStyle.OUTLINE)
	_canvas.draw_rect(Rect2(area.position.x + 1.0, bar_y + 1.0, bar_w - 2.0, 3.0), Color(0, 0, 0, 0.55))
	_canvas.draw_rect(Rect2(area.position.x + 1.0, bar_y + 1.0, (bar_w - 2.0) * clampf(float(collected) / maxf(float(threshold), 1.0), 0.0, 1.0), 3.0), GOLD if reached else LIT)
	var status: String = "BEREITS EMPFANGEN" if claimed else ("SEGEN LIEGT BEREIT!" if reached else "NOCH %d SPLITTER BIS ZUR FREISCHALTUNG" % (threshold - collected))
	_text(Vector2(area.position.x, area.position.y + 52.0), status, LIT if claimed else (GOLD if reached else DIM))


func _item_stats_summary(def: Dictionary) -> String:
	var parts: PackedStringArray = []
	var stats: Dictionary = def.get("stats", {}) as Dictionary
	if int(stats.get("damage", 0)) > 0:
		parts.append("SCHADEN %d" % int(stats["damage"]))
	if int(stats.get("heal", 0)) > 0:
		parts.append("+%d LEBEN" % int(stats["heal"]))
	if int(stats.get("stamina", 0)) > 0:
		parts.append("+%d AUSDAUER" % int(stats["stamina"]))
	if int(stats.get("xp", 0)) > 0:
		parts.append("+%d EP" % int(stats["xp"]))
	var bonus: Dictionary = def.get("bonus", {}) as Dictionary
	for key: Variant in bonus.keys():
		parts.append(TalismanRules.line(String(key), float(bonus[key])))
	var perks: Array = def.get("perks", []) as Array
	if not perks.is_empty():
		var p_entry: Dictionary = (TalismanRules.catalog().get("perks", {}) as Dictionary).get(String(perks[0]), {}) as Dictionary
		var p_name: String = String(p_entry.get("name", ""))
		if p_name != "":
			parts.append("PERK: %s" % p_name)
	return " - ".join(parts)


func _buttons() -> Array[Dictionary]:
	var row: Dictionary = _focused()
	if row.is_empty():
		return []
	var kind: String = String(row.get("kind", ""))
	if kind == "offer":
		return [{"id": "exchange", "label": "EINTAUSCHEN", "ready": int(row.get("state", MISSING)) == OK}]
	if kind == "donate":
		var have: int = _shard_count()
		return [
			{"id": "donate", "label": "DARBRINGEN", "ready": have >= 1},
			{"id": "donate5", "label": "5 X", "ready": have >= 5},
		]
	if kind == "milestone":
		var claimed: bool = bool(row.get("claimed", false))
		var reached: bool = bool(row.get("reached", false))
		return [{"id": "claim", "label": "ERHALTEN" if claimed else "EMPFANGEN", "ready": not claimed and reached}]
	return []


func _press(id: String, bulk: bool) -> void:
	if sys == null:
		return
	var row: Dictionary = _focused()
	match id:
		"exchange":
			var offer: Dictionary = row.get("offer", {}) as Dictionary
			if not offer.is_empty():
				sys.request_exchange(String(offer["id"]))
				say("MÖGE DAS STERNENLICHT DICH BEGLEITEN.")
		"donate", "donate5":
			var amt: int = 5 if (id == "donate5" or bulk) else 1
			sys.request_donate(amt)
			say("DEIN STERNERZ ERHELLT DIESEN SAAL.")
		"claim":
			var m: Dictionary = row.get("milestone", {}) as Dictionary
			if not m.is_empty():
				sys.request_claim_milestone(String(m["id"]))
				say("EMPFANGE DEN SEGEN DER STERNE, ELLIE.")
