class_name HudNotices
extends Node
## The HUD's notices (docs/hud_v2_konzept.md 3.F, step 5): one queue per rank, one notice per rank at a time.
## * big: the top-centre stage. Whoever shows something there (zone card, `TownBanner`, `MineBanner`) claims it with the
##   static `claim_big(owner)` and gives it back with `release_big(owner)`; a claim waits while another owner holds the
##   stage, while the game is paused, a dialogue is open or a shadow creature is close. `notify("big", ..)` shows a
##   banner cloth through the same gate.
## * medium: a leaf of bark paper on the right rail under the quest vine (waystone awakened, veil thread x/8, chronicle
##   30/60/100 %, vista found). Node "NoticeLeaf" of the HUD.
## * small: one line above the hotbar (loot merged per item: "+3 TANNENHOLZ", a pet's gift, a new board notice, a
##   danger change). Node "NoticeLine", stacked by the director (`hud_lift`, `hud_height`).
## Local and cosmetic; a child "Notices" of the `Hud`. `HudDirector.notify(rank, id, data)` lands here; outside code
## without a HUD reference uses the static `post(tree, rank, id, data)` (returns false when there is no HUD).

const LEAF_IN: float = 0.35
const LEAF_HOLD: float = 3.6
const LEAF_OUT: float = 0.5
const LINE_IN: float = 0.2
const LINE_HOLD: float = 2.2
const LINE_OUT: float = 0.45
const LOOT_GRACE: float = 3.0 ## seconds after setup in which bag changes are not reported (the save is still loading)
const CHRONICLE_TICK: float = 3.0
const FIGHT_RANGE: float = 220.0
const GOLD: Color = Color("ffd27a")
const GOLD_DIM: Color = Color("b08a4a")
const LILAC: Color = Color(0.86, 0.80, 0.96)
const TEAL: Color = Color("7fe0c8")
const MAGENTA: Color = Color("ff5fb8")
const INK: Color = Color("1b1a2e")

static var _stage_owner: WeakRef = null
static var _stage_combat: bool = false ## set by the HUD's notices each frame (shadow creature close to the local player)

var hud: CanvasLayer
var player: Node2D
var leaf_view: LeafView
var line_view: LineView
var _leaf_queue: Array[Dictionary] = []
var _leaf: Dictionary = {} ## {id, header, text, color, age}
var _line_queue: Array[Dictionary] = []
var _line: Dictionary = {} ## {id, text, color, count, item, age}
var _banner: TownBanner
var _age: float = 0.0
var _counts: Dictionary = {} ## item id -> count in the local bag (loot lines)
var _chronicle_tick: float = 0.0
var _chronicle: Dictionary = {} ## zone id -> last completion percent seen
var _book: Node


# --- the big stage (static: banners anywhere in the tree use it) ---------------------------------------------------

## True when `owner` may show its big notice now (and holds the stage until `release_big`).
static func claim_big(owner: Object) -> bool:
	var holder: Object = _stage_owner.get_ref() if _stage_owner != null else null
	if holder != null and holder != owner:
		if holder is Node and not (holder as Node).is_inside_tree():
			_stage_owner = null
		else:
			return false
	if holder == owner:
		return true
	if _stage_combat:
		return false
	_stage_owner = weakref(owner)
	return true


static func release_big(owner: Object) -> void:
	if _stage_owner != null and _stage_owner.get_ref() == owner:
		_stage_owner = null


static func stage_busy() -> bool:
	var holder: Object = _stage_owner.get_ref() if _stage_owner != null else null
	return holder != null and (not (holder is Node) or (holder as Node).is_inside_tree())


## For code that has no HUD at hand: the local HUD's notices take it. False when there is none (arena, tests).
static func post(tree: SceneTree, rank: String, id: String, data: Dictionary) -> bool:
	var notices: HudNotices = tree.get_first_node_in_group("hud_notices") as HudNotices
	if notices == null:
		return false
	notices.notify(rank, id, data)
	return true


# --- setup ----------------------------------------------------------------------------------------------------------

func setup(p_hud: CanvasLayer, p_player: Node2D) -> void:
	hud = p_hud
	player = p_player
	name = "Notices"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud_notices")
	leaf_view = LeafView.new()
	leaf_view.name = "NoticeLeaf"
	leaf_view.notices = self
	line_view = LineView.new()
	line_view.name = "NoticeLine"
	line_view.notices = self
	for view: Control in [leaf_view, line_view]:
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(view)
	_hook_sources()


func _exit_tree() -> void:
	for view: Control in [leaf_view, line_view]:
		if view != null and is_instance_valid(view):
			view.queue_free()


## rank "big" | "medium" | "small"; data: header, text (or title/sub for big), color, count + item (loot merging).
func notify(rank: String, id: String, data: Dictionary) -> void:
	match rank:
		"big":
			if _banner == null:
				_banner = TownBanner.new()
				add_child(_banner)
			_banner.show_banner({"header": String(data.get("header", "")), "title": String(data.get("title", data.get("text", ""))),
				"sub": String(data.get("sub", "")), "color": data.get("color", TownBanner.NIGHT_CLOTH), "emblem": -1})
		"medium":
			for i: int in range(_leaf_queue.size() - 1, -1, -1):
				if String(_leaf_queue[i].id) == id:
					_leaf_queue.remove_at(i)
			var entry: Dictionary = {"id": id, "header": String(data.get("header", "")), "text": String(data.get("text", "")),
				"color": data.get("color", GOLD), "age": 0.0}
			if String(_leaf.get("id", "")) == id:
				entry.age = minf(float(_leaf.age), LEAF_IN)
				_leaf = entry
			else:
				_leaf_queue.append(entry)
		"small":
			var count: int = int(data.get("count", 0))
			if String(_line.get("id", "")) == id and count != 0 and float(_line.age) < LINE_IN + LINE_HOLD:
				_line.count = int(_line.count) + count
				_line.text = _line_text(_line)
				_line.age = minf(float(_line.age), LINE_IN)
				return
			for queued: Dictionary in _line_queue:
				if String(queued.id) == id and count != 0:
					queued.count = int(queued.count) + count
					queued.text = _line_text(queued)
					return
			var line: Dictionary = {"id": id, "text": String(data.get("text", "")), "color": data.get("color", TEAL),
				"count": count, "item": String(data.get("item", "")), "age": 0.0}
			if count != 0:
				line.text = _line_text(line)
			_line_queue.append(line)


## What is showing or waiting (tests).
func state() -> Dictionary:
	return {"leaf": String(_leaf.get("id", "")), "leaf_text": String(_leaf.get("text", "")), "line": String(_line.get("id", "")),
		"line_text": String(_line.get("text", "")), "queued": _leaf_queue.size() + _line_queue.size(), "stage": stage_busy()}


func big_showing() -> bool:
	return stage_busy()


static func _line_text(line: Dictionary) -> String:
	var item: String = String(line.get("item", ""))
	if item == "":
		return String(line.get("text", ""))
	return "+%d %s" % [int(line.count), Items.title({"id": item}).to_upper()]


# --- sources --------------------------------------------------------------------------------------------------------

func _hook_sources() -> void:
	var inventory: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inventory != null:
		_counts = _bag_counts(inventory)
		inventory.changed.connect(_on_bag_changed.bind(inventory))
	_hook_world.call_deferred()


func _hook_world() -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	var stones: Waystones = Waystones.of(tree)
	if stones != null and not stones.awakened.is_connected(_on_waystone):
		stones.awakened.connect(_on_waystone)
	var threads: VeilThreads = VeilThreads.of(tree)
	if threads != null and not threads.thread_collected.is_connected(_on_thread):
		threads.thread_collected.connect(_on_thread.bind(threads))
	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	var board: BoardManager = town.board if town != null else null
	if board != null and not board.changed.is_connected(_on_board):
		_board_count = _open_notices(board)
		board.changed.connect(_on_board.bind(board))


var _board_count: int = 0


func _bag_counts(inventory: InventoryComponent) -> Dictionary:
	var out: Dictionary = {}
	var stacks: Array = inventory.slots.duplicate()
	stacks.append(inventory.held)
	for key: Variant in inventory.equipment:
		stacks.append(inventory.equipment[key])
	for stack: Variant in stacks:
		if not (stack is Dictionary) or (stack as Dictionary).is_empty():
			continue
		var id: String = String((stack as Dictionary).get("id", ""))
		if id != "":
			out[id] = int(out.get(id, 0)) + int((stack as Dictionary).get("count", 1))
	return out


func _on_bag_changed(inventory: InventoryComponent) -> void:
	var now: Dictionary = _bag_counts(inventory)
	if _age >= LOOT_GRACE:
		for id: String in now:
			var gain: int = int(now[id]) - int(_counts.get(id, 0))
			if gain > 0:
				notify("small", "loot:" + id, {"count": gain, "item": id, "color": TEAL})
	_counts = now


func _on_waystone(id: String) -> void:
	var stones: Waystones = Waystones.of(get_tree())
	var spec: Dictionary = stones.spec_for(id) if stones != null else {}
	notify("medium", "waystone:" + id, {"header": "WEGSTEIN ERWACHT", "text": String(spec.get("name", id)).to_upper(), "color": TEAL})


func _on_thread(id: String, zone_id: StringName, _peer: int, threads: VeilThreads) -> void:
	var traits: Dictionary = ShadowFruitArt.traits_for(id)
	var col: Color = traits.get("accent_bright", LILAC) as Color
	var z_done: int = threads.collected_in_zone(zone_id) if zone_id != &"" else threads.collected_count()
	var z_tot: int = threads.total_in_zone(zone_id) if zone_id != &"" else maxi(threads.total_count(), 8)
	var z_name: String = ""
	if zone_id != &"":
		var z: Atlas.Zone = Atlas.shared().zone(zone_id)
		if z != null and not z.name.is_empty():
			z_name = z.name.to_upper()
	var line: String = ("%s · %d / %d" % [z_name, z_done, z_tot]) if not z_name.is_empty() else ("%d / %d GEPFLÜCKT" % [z_done, z_tot])
	notify("medium", "veil_thread", {"header": "SCHATTENFRUCHT", "text": line, "color": col})


func _open_notices(board: BoardManager) -> int:
	return board.offers.size()


func _on_board(board: BoardManager) -> void:
	var count: int = _open_notices(board)
	if count > _board_count and _age >= LOOT_GRACE:
		notify("small", "board", {"text": "NEUER AUSHANG AN DER TAFEL", "color": GOLD})
	_board_count = count


func _watch_chronicle(delta: float) -> void:
	_chronicle_tick -= delta
	if _chronicle_tick > 0.0:
		return
	_chronicle_tick = CHRONICLE_TICK
	if _book == null or not is_instance_valid(_book):
		_book = hud.find_child("AtlasBook", true, false) if hud != null else null
		if _book == null:
			return
	var director: ZoneDirector = _director()
	if director == null or player == null:
		return
	var zone_id: StringName = director.player_zone.get(_local_peer(), &"") as StringName
	if zone_id == &"":
		return
	var stats: Dictionary = _book.call("compute_zone_progress", zone_id) as Dictionary
	var pct: int = int(stats.get("completion_pct", 0))
	var key: String = String(zone_id)
	if not _chronicle.has(key):
		_chronicle[key] = pct
		return
	var before: int = int(_chronicle[key])
	_chronicle[key] = pct
	for tier: int in [30, 60, 100]:
		if before < tier and pct >= tier:
			notify("medium", "chronicle:" + key, {"header": "CHRONIK " + String(stats.get("name", key)), "text": "%d %% ERKUNDET" % tier, "color": GOLD})


func _director() -> ZoneDirector:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("director"):
		return null
	return world.call("director") as ZoneDirector


func _local_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


# --- running --------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_age += delta
	var director: HudDirector = hud.get("director") as HudDirector if hud != null else null
	_stage_combat = director != null and director.is_on("combat")
	_watch_chronicle(delta)
	var paused: bool = get_tree().paused
	if _leaf.is_empty() and not _leaf_queue.is_empty() and not paused:
		_leaf = _leaf_queue.pop_front()
	if not _leaf.is_empty():
		if not paused:
			_leaf.age = float(_leaf.age) + delta
		if float(_leaf.age) >= LEAF_IN + LEAF_HOLD + LEAF_OUT:
			_leaf = {}
		leaf_view.queue_redraw()
	if _line.is_empty() and not _line_queue.is_empty() and not paused:
		_line = _line_queue.pop_front()
	if not _line.is_empty():
		if not paused:
			_line.age = float(_line.age) + delta
		if float(_line.age) >= LINE_IN + LINE_HOLD + LINE_OUT:
			_line = {}
		line_view.queue_redraw()


static func _shown(age: float, t_in: float, hold: float, t_out: float) -> float:
	if age < t_in:
		return 1.0 - pow(1.0 - age / t_in, 3.0)
	return 1.0 - clampf((age - t_in - hold) / t_out, 0.0, 1.0)


## The leaf on the right rail: slides in from the screen edge on a thread.
class LeafView extends Control:
	const BOX: Rect2 = Rect2(484.0, 258.0, 152.0, 30.0)
	var notices: HudNotices

	func hud_busy() -> bool:
		return notices != null and not notices._leaf.is_empty()

	func _draw() -> void:
		if notices == null or notices._leaf.is_empty():
			return
		var leaf: Dictionary = notices._leaf
		var age: float = float(leaf.age)
		var shown: float = HudNotices._shown(age, LEAF_IN, LEAF_HOLD, LEAF_OUT)
		var color: Color = leaf.color as Color
		var rect: Rect2 = Rect2(BOX.position + Vector2(roundf((1.0 - shown) * 40.0), 0.0), BOX.size)
		var thread_x: float = rect.position.x + rect.size.x - 20.0
		draw_rect(Rect2(thread_x, rect.position.y - 6.0, 1.0, 6.0), Color(VineStyle.BARK_LIGHT, shown))
		VineStyle.paper(self, rect, shown, 0.0, 57)
		VineStyle.glow(self, rect.position + Vector2(9.0, 15.0), 4.0, color, 0.5 * shown)
		draw_rect(Rect2(rect.position + Vector2(8.0, 14.0), Vector2(2.0, 2.0)), Color(color, shown))
		var header: String = String(leaf.header)
		var text: String = String(leaf.text)
		HudText.draw(self, header, Vector2(rect.position.x + 16.0, rect.position.y + 6.0), Color(GOLD_DIM.lerp(color, 0.35), shown), shown)
		var typed: int = int(ceilf(float(text.length()) * clampf((age - LEAF_IN * 0.5) / 0.6, 0.0, 1.0)))
		HudText.draw(self, text.substr(0, typed), Vector2(rect.position.x + 16.0, rect.position.y + 16.0), Color(Color.WHITE.lerp(color, 0.3), shown), shown)


## The small line above the hotbar, lifted by the director when tags, the fishing leaf or the speech box sit below it.
class LineView extends Control:
	const BOTTOM: float = 300.0
	var notices: HudNotices
	var hud_lift: float = 0.0

	func hud_height() -> float:
		return 10.0 if notices != null and not notices._line.is_empty() else 0.0

	func _draw() -> void:
		if notices == null or notices._line.is_empty():
			return
		var line: Dictionary = notices._line
		var shown: float = HudNotices._shown(float(line.age), LINE_IN, LINE_HOLD, LINE_OUT)
		var text: String = String(line.text)
		var w: float = float(PixelText.width(text))
		var y: float = BOTTOM - hud_lift - 7.0 + roundf((1.0 - shown) * 3.0)
		HudText.draw(self, text, Vector2(roundf(320.0 - w / 2.0), y), Color(line.color as Color, shown), shown)
