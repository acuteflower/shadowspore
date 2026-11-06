class_name TownManager
extends Node2D
## The player's town (docs/town.md): one shared state for the whole world, decided by the host and mirrored on every peer. It owns the pieces the group has
## placed (`structures`: id -> {p piece, x, y, f flipped, g progress 0..1000}), the town's stock, the props the foundations have cleared, and the settlers who
## moved in. The views (`TownStructure`, `Settler`) are only pictures of this state and are loaded near each peer's own player.
## Rules that need no nodes live in `TownRules`; what the world answers (ground, water, colliders, soft props) is asked of the `WorldLevel`.

signal changed ## anything: pieces, progress, stock, residents, name
signal town_founded
signal built(piece: String, id: int)
signal resident_joined(settler: String)
signal notice(text: String, good: bool) ## a short message for the local builder ("NICHT GENUG HOLZ")

const SETTLERS_TABLE: String = "settlers"
const PROGRESS_FULL: int = 1000
const STATE_VERSION: int = 1

var world: WorldLevel
var founded: bool = false
var name_index: int = 0
var center: Vector2 = Vector2.ZERO ## the hut's feet: the heart of the town
var founded_day: int = 0
var critters: TownCritters
var structures: Dictionary = {} ## int id -> {p, x, y, f, g}; id 0 is the house
var stock: Dictionary = {} ## item id -> count
var cleared: Dictionary = {} ## Vector2i prop cell -> true: soft props the foundations removed for good
var residents: Dictionary = {} ## settler id -> {trust, talked}
var next_id: int = 1

var _build: BuildMode ## the local builder (made once a local player exists)
var _banner: TownBanner
var paths: Array = [] ## trampled ways {s: structure id, p: [[x, y], ...] from a building's door to the network, d: 1 once the building stands, e: 1 when the end is a door (not a join)}: they stay when the building goes
var _path_root: Node2D
const MAX_ORDERS: int = 3

var orders: Array = [] ## what a settler is making on commission: {r recipe id, left work seconds, total, done}; they work only while at their bench, anyone collects
var _order_sync: float = 0.0
var _walks: Dictionary = {} ## settlers' walks: "ax,ay>bx,by" -> PackedVector2Array (see `walk_route`)
var _stands: Dictionary = {}
var _walk_key: int = -1
var _walk_time: int = 0
var _path_views: Dictionary = {} ## index in `paths` -> Sprite2D
var _views: Dictionary = {} ## id -> TownStructure
var _settlers: Dictionary = {} ## settler id -> Settler
var _root: Node2D
var _settler_root: Node2D
var _circles: Array[Vector3] = []
var _circles_dirty: bool = true
var _circles_version: int = 0
var light_scale: float = 1.0 ## 1, or less on a fog night: the light reaches that share as far
var _scaled: Array[Vector3] = []
var _scaled_version: int = -1
var _scaled_for: float = 1.0
var _surfaces: Dictionary = {} ## Vector2i (16 px cell) -> surface name
var _progress: Dictionary = {} ## host: id -> float progress
var _progress_clock: float = 0.0
var _progress_dirty: Dictionary = {}
var _stream_clock: float = 0.0
var _found_clock: float = 0.0
var _arrival_clock: float = 0.0
var _last_hour: int = -1
var _arrivals: Dictionary = {} ## host: settler id -> seconds the condition has held
var _built_at: Dictionary = {} ## host: piece -> seconds since the first one was finished


func _ready() -> void:
	add_to_group("town")
	name = "Town"
	if multiplayer.is_server(): ## animals that visit the town (birds on the roofs, a fox at the stockpile)
		critters = TownCritters.new()
		critters.name = "Critters"
		critters.town = self
		add_child(critters)
	y_sort_enabled = true
	_root = Node2D.new()
	_root.name = "Structures"
	_root.y_sort_enabled = true
	add_child(_root)
	_path_root = Node2D.new()
	_path_root.name = "Ways"
	_path_root.z_index = -9
	add_child(_path_root)
	_settler_root = Node2D.new()
	_settler_root.name = "Settlers"
	_settler_root.y_sort_enabled = true
	add_child(_settler_root)
	Terrain.patches.append(self)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_snapshot.rpc_id(id, export_state()))
	built.connect(_on_built)
	town_founded.connect(func() -> void: _announce("STADT GEGRÜNDET", town_name()))
	resident_joined.connect(func(sid: String) -> void: _announce("%s ZIEHT EIN" % String(settler_spec(sid).get("name", sid)), String(settler_spec(sid).get("title", ""))))
	TimeManager.day_started.connect(_on_day_started)


func _exit_tree() -> void:
	Terrain.patches.erase(self)
	if TimeManager.day_started.is_connected(_on_day_started):
		TimeManager.day_started.disconnect(_on_day_started)


## The story listens: a finished piece sets `built_<piece>` for the local player's quests; the morning after the renewal opens the town quest.
func _on_built(piece: String, _id: int) -> void:
	var player: Player = local_player()
	if player != null and player.quests != null:
		player.quests.set_flag("built_" + piece)


func _announce(title: String, sub: String) -> void:
	if local_player() == null:
		return
	if _banner == null:
		_banner = TownBanner.new()
		add_child(_banner)
	_banner.show_text(title, sub)


func _on_day_started(_day: int) -> void:
	var player: Player = local_player()
	if founded and player != null and player.quests != null and player.quests.has_flag("rebuild_done"):
		player.quests.set_flag("town_morning")


func setup(level: WorldLevel) -> void:
	world = level


## `Terrain.patches`: stepping plates are stone underfoot.
func surface_at(pos: Vector2) -> String:
	return String(_surfaces.get(Vector2i(floori(pos.x / 16.0), floori(pos.y / 16.0)), ""))


# ---------- questions ----------

func is_founded() -> bool:
	return founded


func town_name() -> String:
	var names: Array = TownRules.town_names()
	return String(names[clampi(name_index, 0, names.size() - 1)]) if not names.is_empty() else "STADT"


func is_built(id: int) -> bool:
	return structures.has(id) and int((structures[id] as Dictionary).g) >= PROGRESS_FULL


func rect_of(id: int) -> Rect2:
	var data: Dictionary = structures[id] as Dictionary
	return TownRules.foot_rect(String(data.p), float(data.x), float(data.y))


## Wildlife near the town's light is used to people: how much of their usual fear of a player they keep (1 outside the light).
static func calm_at(tree: SceneTree, point: Vector2) -> float:
	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	return 0.7 if town != null and town.founded and town.in_territory(point) else 1.0


## The free ground in front of a piece's door (empty for a piece without one).
func front_of(id: int) -> Rect2:
	var data: Dictionary = structures[id] as Dictionary
	return TownRules.front_rect(String(data.p), float(data.x), float(data.y))


func position_of(id: int) -> Vector2:
	var data: Dictionary = structures[id] as Dictionary
	return Vector2(float(data.x), float(data.y))


## Finished pieces of one kind.
func built_ids(piece: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		if String(data.p) == piece and int(data.g) >= PROGRESS_FULL:
			out.append(id)
	out.sort()
	return out


func count_of(piece: String) -> int:
	var total: int = 0
	for id: int in structures:
		if String((structures[id] as Dictionary).p) == piece:
			total += 1
	return total


func has_built(piece: String) -> bool:
	return not built_ids(piece).is_empty()


func population() -> int:
	return _counted_residents()


## Residents that count for the town's size (a settler with `counts` false, Valdric, lives here but does not make the hamlet a village).
func _counted_residents() -> int:
	var n: int = 0
	for sid: String in residents:
		if bool(settler_spec(sid).get("counts", true)):
			n += 1
	return n


func worth() -> float:
	var total: float = float(_counted_residents()) * float(TownRules.config().get("resident_worth", 8))
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		if int(data.g) >= PROGRESS_FULL:
			total += float(TownRules.piece(String(data.p)).get("worth", 0))
	return total


func level() -> int:
	return TownRules.level_for(worth())


func level_label() -> String:
	return TownRules.level_name(level())


## Circles of light {x, y, reach} of the finished pieces: the ground the group may build on.
func circles() -> Array[Vector3]:
	if _circles_dirty:
		_circles.clear()
		for id: int in structures:
			var data: Dictionary = structures[id] as Dictionary
			var reach: float = float(TownRules.piece(String(data.p)).get("reach", 0.0))
			if reach > 0.0 and int(data.g) >= PROGRESS_FULL:
				_circles.append(Vector3(float(data.x), float(data.y) - 8.0, reach))
		_circles_dirty = false
		_circles_version += 1
	return _circles


func in_territory(pos: Vector2) -> bool:
	return TownRules.covers(circles(), pos)


# ---------- the night (docs/nacht_monster_konzept.md): light is land ----------

## How deep `pos` lies in the light of the town: positive inside a circle, negative = distance to the nearest one (-9999 when nothing is lit or the town is not founded).
func light_depth(pos: Vector2) -> float:
	return TownRules.light_depth(lit_circles(), pos) if founded else -9999.0


## The circles as the night sees them: shrunk on a fog night (`light_scale`, set by `NightAtmosphere` on every peer). Building rules still use `circles()`.
func lit_circles() -> Array[Vector3]:
	var base: Array[Vector3] = circles()
	if is_equal_approx(light_scale, 1.0):
		return base
	if _scaled_version != _circles_version or not is_equal_approx(_scaled_for, light_scale):
		_scaled.clear()
		for c: Vector3 in base:
			_scaled.append(Vector3(c.x, c.y, c.z * light_scale))
		_scaled_version = _circles_version
		_scaled_for = light_scale
	return _scaled


## Away from the light at `pos` (a unit vector).
func light_outward(pos: Vector2) -> Vector2:
	return TownRules.light_outward(lit_circles(), pos)


## Which share of the line a..b is lit.
func lit_fraction(a: Vector2, b: Vector2) -> float:
	return TownRules.lit_fraction(lit_circles(), a, b) if founded else 0.0


## Nothing is born here: inside the light (plus a margin) or close to a building or a site of one (pieces with a role or a reach: houses, stores, lamps; not fences or plates).
func spawn_blocked(pos: Vector2) -> bool:
	if not founded:
		return false
	var protection: Dictionary = NightRules.config().protection as Dictionary
	if light_depth(pos) > -float(protection.light_margin):
		return true
	var margin: float = float(protection.building_tiles) * TownRules.TILE
	for id: int in structures:
		var spec: Dictionary = TownRules.piece(String((structures[id] as Dictionary).p))
		if (spec.has("role") or float(spec.get("reach", 0.0)) > 0.0) and rect_of(id).grow(margin).has_point(pos):
			return true
	return false


## A point just outside the light on the line from `from` to `to`: where a creature stands and watches (the edge of the dusk band). Walks from `to` towards `from`.
func dark_edge(from: Vector2, to: Vector2, margin: float) -> Vector2:
	var steps: int = 24
	for i: int in steps + 1:
		var point: Vector2 = to.lerp(from, float(i) / float(steps))
		if light_depth(point) < -margin:
			return point
	return from


## Is anything being built (a site not finished yet)? Hammering draws them.
func is_building() -> bool:
	for id: int in structures:
		if int((structures[id] as Dictionary).g) < PROGRESS_FULL:
			return true
	return false


## Where somebody who fell comes back: at the door of the house.
func respawn_point() -> Vector2:
	return door_of(0)


## A banner on every peer (the night: "something stirs in the dark", "night survived").
func banner(title: String, sub: String) -> void:
	if multiplayer.is_server():
		_announce(title, sub)
		_rpc_banner.rpc(title, sub)


@rpc("authority", "call_remote", "reliable")
func _rpc_banner(title: String, sub: String) -> void:
	_announce(title, sub)


func is_unlocked(piece: String) -> bool:
	var spec: Dictionary = TownRules.piece(piece)
	if spec.is_empty() or bool(spec.get("builtin", false)):
		return false
	if level() < int(spec.get("level", 0)):
		return false
	var needs: String = String(spec.get("needs", ""))
	return needs == "" or has_built(needs)


func lock_reason(piece: String) -> String:
	var spec: Dictionary = TownRules.piece(piece)
	if level() < int(spec.get("level", 0)):
		return "STUFE %s NÖTIG" % TownRules.level_name(int(spec.get("level", 0)))
	var needs: String = String(spec.get("needs", ""))
	if needs != "" and not has_built(needs):
		return "BRAUCHT %s" % String(TownRules.piece(needs).get("name", needs))
	return ""


func available(item: String, player: Player) -> int:
	return int(stock.get(item, 0)) + (player.inventory.count_item(item) if player != null else 0)


func can_afford(cost: Dictionary, player: Player) -> bool:
	for item: String in cost:
		if available(item, player) < int(cost[item]):
			return false
	return true


func missing_text(cost: Dictionary, player: Player) -> String:
	for item: String in cost:
		if available(item, player) < int(cost[item]):
			return "ES FEHLT %s" % String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()
	return ""


## Everything that can be said against a piece standing with its feet at `pos` (a snapped position), independent of who builds and what they carry:
## "" when the site is fine, otherwise a short reason.
func check_site(piece: String, pos: Vector2, check_world: bool = true) -> String:
	var spec: Dictionary = TownRules.piece(piece)
	if spec.is_empty():
		return "UNBEKANNT"
	if not in_territory(pos):
		return "AUSSERHALB DES LICHTS"
	var rect: Rect2 = TownRules.foot_rect(piece, pos.x, pos.y)
	var front: Rect2 = TownRules.front_rect(piece, pos.x, pos.y)
	var walks: bool = bool(spec.get("walk", false))
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		var other: Dictionary = TownRules.piece(String(data.p))
		if not bool(other.get("builtin", false)) and TownRules.overlaps(rect, rect_of(id)):
			return "IM WEG"
		if walks or bool(other.get("walk", false)):
			continue ## plates are ground: people walk over them
		if front.has_area() and TownRules.overlaps(front, rect_of(id)):
			return "TÜR ZUGESTELLT" ## something stands right in front of this piece's door
		var their_front: Rect2 = front_of(id)
		if their_front.has_area() and TownRules.overlaps(rect, their_front):
			return "VERSPERRT EINE TÜR"
	if check_world and world != null:
		var reason: String = world.town_probe(rect)
		if reason != "":
			return reason
		if front.has_area():
			reason = world.town_probe(front) ## a fallen log, a trunk or a rock in front of the door: nobody could get in
			if reason != "":
				return "TÜR ZUGESTELLT" if reason == "IM WEG" else reason
		for node: Node in get_tree().get_nodes_in_group("players"):
			if rect.grow(5.0).has_point((node as Node2D).global_position):
				return "JEMAND STEHT DARIN"
		for node: Node in get_tree().get_nodes_in_group("settlers"):
			if rect.grow(5.0).has_point((node as Node2D).global_position):
				return "JEMAND STEHT DARIN"
	return ""


## The full check for a builder: the site plus unlocks, the limit, the builder's reach and the material.
func check_place(piece: String, pos: Vector2, builder: Player, check_world: bool = true) -> String:
	if not founded:
		return "KEINE STADT"
	var spec: Dictionary = TownRules.piece(piece)
	if spec.is_empty() or bool(spec.get("builtin", false)):
		return "UNBEKANNT"
	if not is_unlocked(piece):
		return lock_reason(piece)
	if structures.size() >= int((TownRules.config().get("limits", {}) as Dictionary).get("max_pieces", 400)):
		return "ZU VIELE TEILE"
	if builder != null and builder.global_position.distance_to(pos) > float((TownRules.config().get("limits", {}) as Dictionary).get("build_reach", 240.0)):
		return "ZU WEIT WEG"
	var reason: String = check_site(piece, pos, check_world)
	if reason != "":
		return reason
	return missing_text(spec.get("cost", {}) as Dictionary, builder)


# ---------- founding ----------

## The town begins when the hut is renewed. Anyone may ask; the host decides.
func request_found() -> void:
	if founded:
		return
	if multiplayer.is_server():
		_host_found()
	else:
		_rpc_found.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_found() -> void:
	if multiplayer.is_server():
		_host_found()


func _host_found() -> void:
	if founded or world == null:
		return
	var hut: Hut = world.hut_node()
	if hut == null:
		return
	founded = true
	center = hut.position
	founded_day = TimeManager.day
	name_index = int((TownRules.config().get("name", {}) as Dictionary).get("default", 0))
	structures[0] = {"p": "house", "x": center.x, "y": center.y, "f": 0, "g": PROGRESS_FULL, "b": TimeManager.day}
	_circles_dirty = true
	_apply_all()
	_rpc_snapshot.rpc(export_state())
	town_founded.emit()


# ---------- placing ----------

## Local builder asks to place `piece` with its feet at `pos` (already snapped).
func request_place(piece: String, pos: Vector2, flip: bool) -> void:
	if multiplayer.is_server():
		_host_place(piece, pos, 1 if flip else 0, multiplayer.get_unique_id())
	else:
		_rpc_place.rpc_id(1, piece, pos.x, pos.y, 1 if flip else 0)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_place(piece: String, x: float, y: float, flip: int) -> void:
	if multiplayer.is_server():
		_host_place(piece, Vector2(x, y), flip, multiplayer.get_remote_sender_id())


func _host_place(piece: String, pos: Vector2, flip: int, peer: int) -> void:
	var builder: Player = player_of(peer)
	pos = TownRules.snapped_position(piece, pos)
	var reason: String = check_place(piece, pos, builder)
	if reason != "":
		_tell(peer, reason, false)
		return
	var spec: Dictionary = TownRules.piece(piece)
	_pay(spec.get("cost", {}) as Dictionary, builder)
	var rect: Rect2 = TownRules.foot_rect(piece, pos.x, pos.y)
	var front: Rect2 = TownRules.front_rect(piece, pos.x, pos.y)
	var cells: Array = world.town_soft_cells(rect.merge(front) if front.has_area() else rect) if world != null else []
	var id: int = next_id
	next_id += 1
	var data: Dictionary = {"p": piece, "x": pos.x, "y": pos.y, "f": flip, "g": 0}
	_progress[id] = 0.0
	_rpc_added.rpc(id, data, cells)
	if bool(spec.get("paths", false)):
		_host_make_way(id)
	_sync_stock()
	_tell(peer, "%s ANGELEGT" % String(spec.name), true)


@rpc("authority", "call_local", "reliable")
func _rpc_added(id: int, data: Dictionary, cells: Array) -> void:
	structures[id] = data
	for cell: Variant in cells:
		cleared[cell as Vector2i] = true
	if world != null:
		world.town_clear_cells(cells)
	next_id = maxi(next_id, id + 1)
	_circles_dirty = true
	_register(id)
	changed.emit()


## Host: props the light has swept away after they were used up (`WorldLevel._sweep_spent`): gone for good, saved with the town.
func clear_spent(cells: Array) -> void:
	if multiplayer.is_server():
		_rpc_cleared.rpc(cells)


@rpc("authority", "call_local", "reliable")
func _rpc_cleared(cells: Array) -> void:
	for cell: Variant in cells:
		cleared[cell as Vector2i] = true
	if world != null:
		world.town_clear_cells(cells)


## Developer checkpoint (Escape menu -> ENTWICKLER -> FERTIGE STADT): the town is founded, every piece of the catalogue stands finished round the hut (what is there already is kept) and
## every settler whose building stands is at home. Nothing is paid, nothing is asked. Solo / host only.
func debug_build_all() -> void:
	if not multiplayer.is_server() or world == null:
		return
	request_found()
	if not founded:
		return
	var plan: Array = [["lamp_post", Vector2(-80, 120)], ["lamp_post", Vector2(150, 140)], ["workshop", Vector2(40, 175)], ["stockpile", Vector2(-110, 190)], ["bench", Vector2(80, 100)]]
	for k: int in 4:
		plan.append(["fence", Vector2(-170 + k * 24, 215)])
	for k: int in 6:
		plan.append(["path_stone", Vector2(20 + k * 16, 118)])
	for piece: String in TownRules.buildable():
		var known: bool = false
		for entry: Array in plan:
			known = known or String(entry[0]) == piece
		if not known:
			plan.append([piece, Vector2(0, 150)])
	var have: Dictionary = {}
	for id: int in structures:
		var kind: String = String((structures[id] as Dictionary).p)
		have[kind] = int(have.get(kind, 0)) + 1
	for entry: Array in plan:
		var piece: String = String(entry[0])
		if int(have.get(piece, 0)) > 0:
			have[piece] = int(have[piece]) - 1
			continue
		var pos: Vector2 = _debug_site(piece, center + (entry[1] as Vector2))
		if pos == Vector2.INF:
			continue
		var spec: Dictionary = TownRules.piece(piece)
		var rect: Rect2 = TownRules.foot_rect(piece, pos.x, pos.y)
		var front: Rect2 = TownRules.front_rect(piece, pos.x, pos.y)
		var cells: Array = world.town_soft_cells(rect.merge(front) if front.has_area() else rect)
		var id: int = next_id
		next_id += 1
		_progress[id] = 0.0
		_rpc_added.rpc(id, {"p": piece, "x": pos.x, "y": pos.y, "f": 0, "g": 0}, cells)
		if bool(spec.get("paths", false)):
			_host_make_way(id)
		_rpc_done.rpc(id)
		(structures[id] as Dictionary).b = TimeManager.day - 6 ## the checkpoint town has stood a while: its wear is already there
	for sid: String in settler_ids():
		var settler: Dictionary = settler_spec(sid)
		if not bool(settler.get("enabled", true)):
			continue
		var arrive: Dictionary = settler.get("arrive", {}) as Dictionary
		if not residents.has(sid) and has_built(String(arrive.get("needs", ""))):
			_rpc_resident.rpc(sid, {"trust": 0, "talked": -1}, false) ## not freshly arrived: they are simply at home
	_sync_stock()


## The nearest free spot for `piece` round `around` (rings of 8 px, 24 directions).
func _debug_site(piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 30):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 8.0)
			if check_site(piece, p) == "":
				return p
	return Vector2.INF


## Host: costs come first from the stock, then from the builder's bag.
func _pay(cost: Dictionary, player: Player) -> void:
	for item: String in cost:
		var need: int = int(cost[item])
		var from_stock: int = mini(int(stock.get(item, 0)), need)
		if from_stock > 0:
			_add_stock(item, -from_stock)
			need -= from_stock
		if need > 0 and player != null:
			player.inventory.remove_item(item, need)


func _add_stock(item: String, amount: int) -> void:
	var now: int = int(stock.get(item, 0)) + amount
	if now <= 0:
		stock.erase(item)
	else:
		stock[item] = now


func _sync_stock() -> void:
	_rpc_stock_state.rpc(stock)


@rpc("authority", "call_local", "reliable")
func _rpc_stock_state(new_stock: Dictionary) -> void:
	stock = new_stock.duplicate()
	for item: Variant in stock.keys():
		stock[item] = int(stock[item])
	changed.emit()


# ---------- trampled ways ----------

## Host: a building gets a way from its door towards the town (the hut's door, another building's door); on the way it joins an older way when it meets one
## (`TownWays`). The front is tried first; when something stands in front of it (a fallen log) the sides and the back are.
func _host_make_way(id: int) -> void:
	if world == null:
		return
	var hut: Hut = world.hut_node()
	var rect: Rect2 = rect_of(id)
	var doors: Array[Vector2] = [position_of(id) + Vector2(0.0, 9.0), rect.get_center() + Vector2(rect.size.x / 2.0 + 8.0, 0.0), rect.get_center() - Vector2(rect.size.x / 2.0 + 8.0, 0.0), rect.get_center() - Vector2(0.0, rect.size.y / 2.0 + 8.0)]
	var targets: Array[Vector2] = []
	if hut != null:
		targets.append(hut.exit_position)
	for other: int in structures:
		if other != id and bool(TownRules.piece(String((structures[other] as Dictionary).p)).get("paths", false)):
			targets.append(position_of(other) + Vector2(0.0, 9.0))
	if targets.is_empty():
		return
	var ctx: Dictionary = _walk_context(position_of(id))
	var solids: Array[Rect2] = ctx.solids as Array[Rect2]
	var trails: Array[PackedVector2Array] = ctx.trails as Array[PackedVector2Array]
	var walkable: Callable = ctx.walkable as Callable
	for door: Vector2 in doors:
		var best: Vector2 = Vector2.INF
		var best_distance: float = INF
		for t: Vector2 in targets:
			var distance: float = door.distance_to(t)
			if distance < best_distance and distance > 14.0:
				best = t
				best_distance = distance
		if best == Vector2.INF:
			return
		var made: Dictionary = TownWays.route(door, best, solids, walkable, trails, id * 7919 + paths.size())
		var route: PackedVector2Array = made.p as PackedVector2Array
		if route.size() < 2:
			continue
		var pts_out: Array = []
		for p: Vector2 in route:
			pts_out.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		_rpc_way_added.rpc({"s": id, "p": pts_out, "d": 0, "e": 0 if bool(made.joined) else 1})
		return


static func way_points(way: Dictionary) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for raw: Variant in way.p as Array:
		pts.append(Vector2(float((raw as Array)[0]), float((raw as Array)[1])))
	return pts


## What a walker has to keep out of and may follow: {solids: the pieces (the hut too; plates are ground), trails: the finished ways, walkable: Callable(Vector2) -> bool}.
func _walk_context(at: Vector2) -> Dictionary:
	var solids: Array[Rect2] = []
	for sid: int in structures:
		if not bool(TownRules.piece(String((structures[sid] as Dictionary).p)).get("walk", false)):
			solids.append(rect_of(sid))
	var trails: Array[PackedVector2Array] = []
	for way: Variant in paths:
		if int((way as Dictionary).d) == 1:
			trails.append(way_points(way as Dictionary))
	var level: int = world.town_level_at(at)
	var walkable: Callable = func(point: Vector2) -> bool: return world.town_walkable(point, level)
	return {"solids": solids, "trails": trails, "walkable": walkable}


# ---------- walking (settlers) ----------

## A settler stands here for `spot`: inside a piece (the bed behind the workshop wall) it is the piece's door, on ground that is blocked (a log, a fence) the nearest free
## spot within about 48 px. Cached; the cache ends when the town changes and every 20 s (props load with the chunks).
func stand_point(spot: Vector2) -> Vector2:
	_check_walk_cache()
	var key: Vector2i = Vector2i(spot.round())
	if _stands.has(key):
		return _stands[key] as Vector2
	var out: Vector2 = spot
	for sid: int in structures:
		if not bool(TownRules.piece(String((structures[sid] as Dictionary).p)).get("walk", false)) and rect_of(sid).has_point(spot):
			out = door_of(sid)
			break
	if out == spot and world != null:
		var ctx: Dictionary = _walk_context(spot)
		if not _free(out, ctx):
			for ring: int in range(1, 7):
				var found: bool = false
				for k: int in 12:
					var candidate: Vector2 = spot + Vector2.from_angle(TAU * float(k) / 12.0 + float(ring)) * float(ring) * 8.0
					if _free(candidate, ctx):
						out = candidate
						found = true
						break
				if found:
					break
	_stands[key] = out
	return out


func _free(point: Vector2, ctx: Dictionary) -> bool:
	for r: Rect2 in ctx.solids as Array[Rect2]:
		if r.grow(TownWays.MARGIN).has_point(point):
			return false
	return bool((ctx.walkable as Callable).call(point))


## The point in front of a piece where people go in and out.
func door_of(id: int) -> Vector2:
	var hut: Hut = world.hut_node() if world != null else null
	if id == 0 and hut != null:
		return hut.exit_position
	return position_of(id) + Vector2(0.0, 9.0)


## The way a person walks from `from` to `to` (both are places in the plan; they are moved to `stand_point`): round the pieces and whatever the ground forbids,
## along the trampled ways where those lead the right way. First point = where they start, last = where they arrive. Empty when no way exists.
func walk_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	_check_walk_cache()
	var a: Vector2 = stand_point(from)
	var b: Vector2 = stand_point(to)
	var key: String = "%d,%d>%d,%d" % [roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y)]
	if _walks.has(key):
		return _walks[key] as PackedVector2Array
	var out: PackedVector2Array = PackedVector2Array()
	if world != null and a.distance_to(b) >= 10.0:
		var ctx: Dictionary = _walk_context(a)
		var made: Dictionary = TownWays.route(a, b, ctx.solids as Array[Rect2], ctx.walkable as Callable, ctx.trails as Array[PackedVector2Array], hash(Vector4i(roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y))), false)
		out = made.p as PackedVector2Array
	elif a.distance_to(b) < 10.0:
		out = PackedVector2Array([a, b])
	_walks[key] = out
	return out


func _check_walk_cache() -> void:
	var finished: int = 0
	for way: Variant in paths:
		finished += int((way as Dictionary).d)
	var key: int = next_id * 1000003 + structures.size() * 1009 + paths.size() * 31 + finished
	var now: int = Time.get_ticks_msec()
	if key != _walk_key or now - _walk_time > 20000:
		_walk_key = key
		_walk_time = now
		_walks.clear()
		_stands.clear()


@rpc("authority", "call_local", "reliable")
func _rpc_way_added(entry: Dictionary) -> void:
	paths.append(entry)
	_refresh_ways()


## The pictures of the finished ways (made once per way; a new one fades in).
func _refresh_ways() -> void:
	for i: int in paths.size():
		var way: Dictionary = paths[i] as Dictionary
		if int(way.d) == 1 and not _path_views.has(i):
			var made: Dictionary = TownPathArt.make(way_points(way), int(way.s) * 31 + i, int(way.get("e", 0)) == 1)
			if made.is_empty():
				continue
			var sprite: Sprite2D = Sprite2D.new()
			sprite.texture = made.texture as Texture2D
			sprite.centered = false
			sprite.position = made.origin as Vector2
			sprite.modulate.a = 0.0
			_path_root.add_child(sprite)
			create_tween().tween_property(sprite, "modulate:a", 1.0, 1.4)
			_path_views[i] = sprite
	for i: int in _path_views.keys():
		if i >= paths.size() or int((paths[i] as Dictionary).d) != 1:
			(_path_views[i] as Sprite2D).queue_free()
			_path_views.erase(i)
	_rebuild_surfaces()


# ---------- demolishing ----------

func request_demolish(id: int) -> void:
	if multiplayer.is_server():
		_host_demolish(id, multiplayer.get_unique_id())
	else:
		_rpc_demolish.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_demolish(id: int) -> void:
	if multiplayer.is_server():
		_host_demolish(id, multiplayer.get_remote_sender_id())


func _host_demolish(id: int, peer: int) -> void:
	if not structures.has(id):
		return
	var data: Dictionary = structures[id] as Dictionary
	var spec: Dictionary = TownRules.piece(String(data.p))
	if bool(spec.get("builtin", false)):
		_tell(peer, "DAS HAUS BLEIBT", false)
		return
	var builder: Player = player_of(peer)
	if builder != null and builder.global_position.distance_to(Vector2(float(data.x), float(data.y))) > float((TownRules.config().get("limits", {}) as Dictionary).get("build_reach", 240.0)):
		_tell(peer, "ZU WEIT WEG", false)
		return
	var back: Dictionary = TownRules.refund(spec.get("cost", {}) as Dictionary, int(data.g) >= PROGRESS_FULL)
	for item: String in back:
		_add_stock(item, int(back[item]))
	_progress.erase(id)
	_rpc_removed.rpc(id)
	_sync_stock()
	_tell(peer, "%s ABGERISSEN" % String(spec.name), true)


@rpc("authority", "call_local", "reliable")
func _rpc_removed(id: int) -> void:
	if _views.has(id):
		(_views[id] as TownStructure).dismantle()
		_views.erase(id)
	structures.erase(id)
	for i: int in range(paths.size() - 1, -1, -1):
		if int((paths[i] as Dictionary).s) == id and int((paths[i] as Dictionary).d) == 0:
			paths.remove_at(i) ## a way nobody ever walked is not kept
	_refresh_ways()
	_circles_dirty = true
	_rebuild_surfaces()
	changed.emit()


# ---------- building ----------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not founded:
		return
	_work_orders(delta)
	var limits: Dictionary = TownRules.config().get("limits", {}) as Dictionary
	var radius: float = float(limits.get("helper_radius", 100.0))
	var players: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		var p: Player = node as Player
		if p != null and p.health.current > 0.0 and not p.story_lock:
			players.append(p)
	for id: int in structures.keys():
		var data: Dictionary = structures[id] as Dictionary
		if int(data.g) >= PROGRESS_FULL:
			continue
		var spec: Dictionary = TownRules.piece(String(data.p))
		var middle: Vector2 = rect_of(id).get_center()
		var helpers: int = 0
		for p: Player in players:
			if p.global_position.distance_to(middle) <= radius:
				helpers += 1
		for sid: String in _settlers:
			if (_settlers[sid] as Settler).is_helping() and (_settlers[sid] as Settler).global_position.distance_to(middle) <= radius * 1.4:
				helpers += 1
		if helpers == 0:
			continue
		var rate: float = float(PROGRESS_FULL) / maxf(float(spec.get("build_seconds", 5.0)), 0.5) * (1.0 + 0.5 * float(helpers - 1))
		var now: float = float(_progress.get(id, float(data.g))) + rate * delta
		_progress[id] = now
		var value: int = mini(int(now), PROGRESS_FULL)
		if value != int(data.g):
			data.g = value
			_progress_dirty[id] = value
			if _views.has(id) and value < PROGRESS_FULL:
				(_views[id] as TownStructure).set_progress(value)
		if value >= PROGRESS_FULL:
			_progress.erase(id)
			_progress_dirty.erase(id)
			_rpc_done.rpc(id)
	_progress_clock += delta
	if _progress_clock >= 0.25 and not _progress_dirty.is_empty():
		_progress_clock = 0.0
		_rpc_progress.rpc(PackedInt32Array(_progress_dirty.keys()), PackedInt32Array(_progress_dirty.values()))
		_progress_dirty.clear()


@rpc("authority", "call_remote", "unreliable")
func _rpc_progress(ids: PackedInt32Array, values: PackedInt32Array) -> void:
	for i: int in ids.size():
		if structures.has(ids[i]):
			var data: Dictionary = structures[ids[i]] as Dictionary
			if int(data.g) < PROGRESS_FULL:
				data.g = values[i]
				if _views.has(ids[i]):
					(_views[ids[i]] as TownStructure).set_progress(values[i])


@rpc("authority", "call_local", "reliable")
func _rpc_done(id: int) -> void:
	if not structures.has(id):
		return
	var data: Dictionary = structures[id] as Dictionary
	data.g = PROGRESS_FULL
	data.b = TimeManager.day ## the day it was finished: what a piece collects with age (TownStructure `wear`)
	for way: Variant in paths:
		if int((way as Dictionary).s) == id:
			(way as Dictionary).d = 1
	_refresh_ways()
	_circles_dirty = true
	_register(id)
	if _views.has(id):
		(_views[id] as TownStructure).set_progress(PROGRESS_FULL, true)
	built.emit(String(data.p), id)
	changed.emit()


# ---------- the stock ----------

func request_stock(op: String, item: String, count: int) -> void:
	if multiplayer.is_server():
		_host_stock(op, item, count, multiplayer.get_unique_id())
	else:
		_rpc_stock_request.rpc_id(1, op, item, count)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_stock_request(op: String, item: String, count: int) -> void:
	if multiplayer.is_server():
		_host_stock(op, item, count, multiplayer.get_remote_sender_id())


func _near_role(player: Player, role: String, reach: float) -> bool:
	for id: int in built_ids_of_role(role):
		if rect_of(id).grow(reach).has_point(player.global_position):
			return true
	return false


func built_ids_of_role(role: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		if int(data.g) >= PROGRESS_FULL and String(TownRules.piece(String(data.p)).get("role", "")) == role:
			out.append(id)
	out.sort()
	return out


func _host_stock(op: String, item: String, count: int, peer: int) -> void:
	var player: Player = player_of(peer)
	if player == null or not _near_role(player, "stock", 90.0):
		_tell(peer, "ZU WEIT VOM LAGER", false)
		return
	match op:
		"deposit_all":
			var moved: int = 0
			var counts: Dictionary = {}
			for stack: Dictionary in player.inventory.slots:
				if not stack.is_empty() and String(Items.definition(stack).get("kind", "")) == "material":
					counts[String(stack.id)] = int(counts.get(String(stack.id), 0)) + int(stack.count)
			for id: String in counts:
				if player.inventory.remove_item(id, int(counts[id])):
					_add_stock(id, int(counts[id]))
					moved += int(counts[id])
			_tell(peer, "%d EINGELAGERT" % moved if moved > 0 else "NICHTS ZUM EINLAGERN", moved > 0)
		"deposit":
			var held: int = mini(count, player.inventory.count_item(item))
			if held <= 0 or String(DataRegistry.get_entry("items", item).get("kind", "")) not in ["material", "consumable"]:
				return
			player.inventory.remove_item(item, held)
			_add_stock(item, held)
			_tell(peer, "%d EINGELAGERT" % held, true)
		"take":
			var have: int = int(stock.get(item, 0))
			var amount: int = mini(count, have)
			if amount <= 0:
				return
			var left: int = player.inventory.give(item, amount)
			_add_stock(item, -(amount - left))
			_tell(peer, "%d GENOMMEN" % (amount - left), amount - left > 0)
	_sync_stock()


# ---------- settlers ----------

func settler_spec(id: String) -> Dictionary:
	return DataRegistry.get_entry(SETTLERS_TABLE, id)


func settler_ids() -> Array:
	return DataRegistry.table(SETTLERS_TABLE).keys()


func trust_of(id: String) -> int:
	return int((residents.get(id, {}) as Dictionary).get("trust", 0))


func settler_node(id: String) -> Settler:
	return _settlers.get(id) as Settler


## Host, once a second: a settler comes when the piece they were waiting for has stood for `delay` seconds.
func _check_arrivals(delta: float) -> void:
	for sid: String in settler_ids():
		if residents.has(sid):
			continue
		var spec: Dictionary = settler_spec(sid)
		if not bool(spec.get("enabled", true)):
			_arrivals.erase(sid)
			continue
		if bool(spec.get("founder", false)): ## lives here from the day the town is founded (Valdric)
			_rpc_resident.rpc(sid, {"trust": 0, "talked": -1}, true)
			continue
		var arrive: Dictionary = spec.get("arrive", {}) as Dictionary
		if has_built(String(arrive.get("needs", ""))):
			_arrivals[sid] = float(_arrivals.get(sid, 0.0)) + delta
			if float(_arrivals[sid]) >= float(arrive.get("delay", 8.0)):
				_rpc_resident.rpc(sid, {"trust": 0, "talked": -1}, true)
		else:
			_arrivals.erase(sid)


@rpc("authority", "call_local", "reliable")
func _rpc_resident(sid: String, data: Dictionary, fresh: bool) -> void:
	residents[sid] = {"trust": int(data.get("trust", 0)), "talked": int(data.get("talked", -1))}
	_ensure_settler(sid, fresh)
	if fresh:
		resident_joined.emit(sid)
	changed.emit()


func _ensure_settler(sid: String, fresh: bool) -> void:
	if _settlers.has(sid) or not residents.has(sid):
		return
	var settler: Settler = Settler.new()
	settler.name = sid.capitalize()
	_settler_root.add_child(settler)
	settler.setup(self, sid, fresh)
	_settlers[sid] = settler


## Local player talked to a settler: the first talk of a day makes them trust a little more. Returns the trust tier the dialogue should use.
func request_talk(sid: String) -> void:
	if multiplayer.is_server():
		_host_talk(sid)
	else:
		_rpc_talk.rpc_id(1, sid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_talk(sid: String) -> void:
	if multiplayer.is_server():
		_host_talk(sid)


func _host_talk(sid: String) -> void:
	if not residents.has(sid):
		return
	var data: Dictionary = (residents[sid] as Dictionary).duplicate()
	if int(data.talked) != TimeManager.day:
		data.talked = TimeManager.day
		data.trust = mini(int(data.trust) + 10, 100)
		_rpc_resident.rpc(sid, data, false)


## Host, every game hour: residents with a trade work for the town while they are at their place.
func _hour_tick() -> void:
	for sid: String in residents:
		var spec: Dictionary = settler_spec(sid)
		var made: Dictionary = spec.get("produces", {}) as Dictionary
		var node: Settler = _settlers.get(sid) as Settler
		if made.is_empty() or node == null or not node.is_working():
			continue
		var inputs: Dictionary = made.get("in", {}) as Dictionary
		var ok: bool = true
		for item: String in inputs:
			if int(stock.get(item, 0)) < int(inputs[item]):
				ok = false
		if not ok:
			continue
		for item: String in inputs:
			_add_stock(item, -int(inputs[item]))
		var outputs: Dictionary = made.get("out", {}) as Dictionary
		for item: String in outputs:
			_add_stock(item, int(outputs[item]))
		_sync_stock()


# ---------- crafting ----------

func recipes() -> Dictionary:
	return DataRegistry.table("recipes")


## What is stopping this recipe for `player` right now ("" = nothing).
func recipe_block(recipe_id: String, player: Player) -> String:
	var recipe: Dictionary = recipes().get(recipe_id, {}) as Dictionary
	if recipe.is_empty():
		return "UNBEKANNT"
	var maker: String = String(recipe.get("npc", "gustav"))
	if trust_of(maker) < int(recipe.get("trust", 0)):
		return "%s TRAUT DIR NOCH NICHT" % String(settler_spec(maker).get("name", maker))
	if bool(recipe.get("once", false)):
		for item: String in recipe.get("out", {}) as Dictionary:
			if player.inventory.has_item(item):
				return "DU HAST SCHON EINE"
	return missing_text(recipe.get("in", {}) as Dictionary, player)


## The material of a recipe leaves the bag first, then the stock.
func _take_inputs(recipe: Dictionary, player: Player) -> void:
	var inputs: Dictionary = recipe.get("in", {}) as Dictionary
	for item: String in inputs:
		var need: int = int(inputs[item])
		var from_bag: int = mini(player.inventory.count_item(item), need)
		if from_bag > 0:
			player.inventory.remove_item(item, from_bag)
		if need - from_bag > 0:
			_add_stock(item, -(need - from_bag))


func _give_outputs(recipe: Dictionary, player: Player) -> void:
	var outputs: Dictionary = recipe.get("out", {}) as Dictionary
	for item: String in outputs:
		var left: int = player.inventory.give(item, int(outputs[item]))
		if left > 0:
			_add_stock(item, left) ## a full bag: the rest goes to the stock


# ---------- commissions (what only a settler can make: it takes a while) ----------

## What stops this commission right now ("" = nothing).
func order_block(recipe_id: String, player: Player) -> String:
	var recipe: Dictionary = recipes().get(recipe_id, {}) as Dictionary
	if recipe.is_empty() or String(recipe.get("by", "self")) != "npc":
		return "UNBEKANNT"
	var reason: String = recipe_block(recipe_id, player)
	if reason != "":
		return reason
	if orders.size() >= MAX_ORDERS:
		return "DIE WARTELISTE IST VOLL"
	return ""


## Seconds of work still ahead of an order (everything before it counts too), for the "ready in" text.
func order_wait(index: int) -> float:
	var total: float = 0.0
	for i: int in mini(index + 1, orders.size()):
		if not bool((orders[i] as Dictionary).done):
			total += float((orders[i] as Dictionary).left)
	return total


func request_order(recipe_id: String) -> void:
	if multiplayer.is_server():
		_host_order(recipe_id, multiplayer.get_unique_id())
	else:
		_rpc_order.rpc_id(1, recipe_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_order(recipe_id: String) -> void:
	if multiplayer.is_server():
		_host_order(recipe_id, multiplayer.get_remote_sender_id())


func _host_order(recipe_id: String, peer: int) -> void:
	var player: Player = player_of(peer)
	if player == null or not _near_role(player, "craft", 140.0):
		_tell(peer, "ZU WEIT VON DER WERKBANK", false)
		return
	var reason: String = order_block(recipe_id, player)
	if reason != "":
		_tell(peer, reason, false)
		return
	var recipe: Dictionary = recipes().get(recipe_id, {}) as Dictionary
	_take_inputs(recipe, player)
	var work: float = maxf(float(recipe.get("work", 60.0)), 1.0)
	orders.append({"r": recipe_id, "left": work, "total": work, "done": false})
	_sync_stock()
	_rpc_orders.rpc(orders.duplicate(true))
	_tell(peer, "%s IN AUFTRAG" % String(recipe.name), true)


func request_collect(index: int) -> void:
	if multiplayer.is_server():
		_host_collect(index, multiplayer.get_unique_id())
	else:
		_rpc_collect.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_collect(index: int) -> void:
	if multiplayer.is_server():
		_host_collect(index, multiplayer.get_remote_sender_id())


func _host_collect(index: int, peer: int) -> void:
	var player: Player = player_of(peer)
	if player == null or not _near_role(player, "craft", 140.0):
		_tell(peer, "ZU WEIT VON DER WERKBANK", false)
		return
	if index < 0 or index >= orders.size() or not bool((orders[index] as Dictionary).done):
		_tell(peer, "NOCH NICHT FERTIG", false)
		return
	var recipe: Dictionary = recipes().get(String((orders[index] as Dictionary).r), {}) as Dictionary
	orders.remove_at(index)
	_give_outputs(recipe, player)
	_sync_stock()
	_rpc_orders.rpc(orders.duplicate(true))
	_tell(peer, "%s ABGEHOLT" % String(recipe.get("name", "?")), true)


@rpc("authority", "call_local", "reliable")
func _rpc_orders(list: Array) -> void:
	var incoming: Array = list.duplicate(true) ## call_local hands over the host's own array: copy before it is cleared
	orders.clear()
	for entry: Variant in incoming:
		var e: Dictionary = entry as Dictionary
		orders.append({"r": String(e.r), "left": float(e.left), "total": float(e.total), "done": bool(e.done)})
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_order_ready(recipe_name: String, maker: String) -> void:
	_announce("%s IST FERTIG" % recipe_name, "%s HAT ES AUF DER BANK" % String(settler_spec(maker).get("name", maker)))


## Host: the first open commission of each settler advances while that settler stands at their bench.
func _work_orders(delta: float) -> void:
	var moved: bool = false
	var finished: bool = false
	for sid: String in settler_ids():
		var node: Settler = _settlers.get(sid) as Settler
		if node == null or not node.is_working():
			continue
		for entry: Variant in orders:
			var order: Dictionary = entry as Dictionary
			var recipe: Dictionary = recipes().get(String(order.r), {}) as Dictionary
			if bool(order.done) or String(recipe.get("npc", "gustav")) != sid:
				continue
			order.left = float(order.left) - delta
			moved = true
			if float(order.left) <= 0.0:
				order.left = 0.0
				order.done = true
				finished = true
				_rpc_order_ready.rpc(String(recipe.get("name", "?")), sid)
			break
	_order_sync -= delta
	if finished or (moved and _order_sync <= 0.0):
		_order_sync = 1.0
		_rpc_orders.rpc(orders.duplicate(true))


# ---------- trade (a shop's buy and sell lists, data/shops.json) ----------

func shop(id: String) -> Dictionary:
	return DataRegistry.get_entry("shops", id)


func request_trade(shop_id: String, mode: String, item: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_trade(shop_id, mode, item, amount, multiplayer.get_unique_id())
	else:
		_rpc_trade.rpc_id(1, shop_id, mode, item, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade(shop_id: String, mode: String, item: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_trade(shop_id, mode, item, amount, multiplayer.get_remote_sender_id())


func _host_trade(shop_id: String, mode: String, item: String, amount: int, peer: int) -> void:
	var player: Player = player_of(peer)
	var def: Dictionary = shop(shop_id)
	if player == null or def.is_empty() or mode not in ["buy", "sell"] or amount < 1 or amount > 99:
		return
	if not _near_role(player, String(def.get("role", "craft")), float(def.get("reach", 140.0))):
		_tell(peer, "ZU WEIT WEG", false)
		return
	var offer: Dictionary = {}
	for entry: Variant in def.get(mode, []) as Array:
		if String((entry as Dictionary).item) == item:
			offer = entry as Dictionary
	if offer.is_empty():
		return
	var npc: String = String(def.get("npc", ""))
	if trust_of(npc) < int(offer.get("trust", 0)):
		_tell(peer, "%s TRAUT DIR NOCH NICHT" % String(settler_spec(npc).get("name", npc)), false)
		return
	var price: int = int(offer.price)
	var item_name: String = String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()
	if mode == "buy":
		if player.progress.copper < price:
			_tell(peer, "ZU WENIG GELD", false)
			return
		var wanted: int = mini(amount, player.progress.copper / price)
		var left: int = player.inventory.give(item, wanted)
		if wanted - left <= 0:
			_tell(peer, "KEIN PLATZ IM RUCKSACK", false)
			return
		player.progress.award(-price * (wanted - left), 0)
		_tell(peer, "%d X %s GEKAUFT" % [wanted - left, item_name], true)
	else:
		var sold: int = mini(amount, player.inventory.count_item(item))
		if sold <= 0:
			_tell(peer, "DU HAST KEIN %s" % item_name, false)
			return
		player.inventory.remove_item(item, sold)
		player.progress.award(price * sold, 0)
		_tell(peer, "%d X %s VERKAUFT" % [sold, item_name], true)



func request_craft(recipe_id: String) -> void:
	if multiplayer.is_server():
		_host_craft(recipe_id, multiplayer.get_unique_id())
	else:
		_rpc_craft.rpc_id(1, recipe_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_craft(recipe_id: String) -> void:
	if multiplayer.is_server():
		_host_craft(recipe_id, multiplayer.get_remote_sender_id())


func _host_craft(recipe_id: String, peer: int) -> void:
	var player: Player = player_of(peer)
	var recipe: Dictionary = recipes().get(recipe_id, {}) as Dictionary
	if player == null or recipe.is_empty() or not _near_role(player, "craft", 140.0):
		_tell(peer, "ZU WEIT VON DER WERKBANK", false)
		return
	var reason: String = recipe_block(recipe_id, player)
	if reason != "":
		_tell(peer, reason, false)
		return
	_take_inputs(recipe, player)
	var outputs: Dictionary = recipe.get("out", {}) as Dictionary
	for item: String in outputs:
		var left: int = player.inventory.give(item, int(outputs[item]))
		if left > 0:
			_add_stock(item, left) ## a full bag: the rest goes to the stock
	_sync_stock()
	_tell(peer, "%s GEFERTIGT" % String(recipe.name), true)


# ---------- the name ----------

func request_name(index: int) -> void:
	if multiplayer.is_server():
		_rpc_name_state.rpc(index)
	else:
		_rpc_name.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_name(index: int) -> void:
	if multiplayer.is_server():
		_rpc_name_state.rpc(index)


@rpc("authority", "call_local", "reliable")
func _rpc_name_state(index: int) -> void:
	name_index = clampi(index, 0, maxi(TownRules.town_names().size() - 1, 0))
	changed.emit()


# ---------- messages ----------

func _tell(peer: int, text: String, good: bool) -> void:
	if peer == multiplayer.get_unique_id():
		notice.emit(text, good)
	else:
		_rpc_notice.rpc_id(peer, text, good)


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(text: String, good: bool) -> void:
	notice.emit(text, good)


func player_of(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.get_multiplayer_authority() == peer:
			return node as Player
	return null


func local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


# ---------- views ----------

func _register(id: int) -> void:
	_rebuild_surfaces()
	_stream_views(true)


func _rebuild_surfaces() -> void:
	_surfaces.clear()
	for way: Variant in paths:
		if int((way as Dictionary).d) == 1:
			var pts: Array = (way as Dictionary).p as Array
			for k: int in pts.size() - 1:
				var a: Vector2 = Vector2(float((pts[k] as Array)[0]), float((pts[k] as Array)[1]))
				var b: Vector2 = Vector2(float((pts[k + 1] as Array)[0]), float((pts[k + 1] as Array)[1]))
				for step: int in range(int(a.distance_to(b) / 6.0) + 1):
					var at: Vector2 = a.lerp(b, float(step) * 6.0 / maxf(a.distance_to(b), 1.0))
					_surfaces[Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))] = "path"
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		var spec: Dictionary = TownRules.piece(String(data.p))
		var surface: String = String(spec.get("surface", ""))
		if surface == "":
			continue
		var rect: Rect2 = TownRules.foot_rect(String(data.p), float(data.x), float(data.y))
		for y: int in range(floori(rect.position.y / 16.0), ceili(rect.end.y / 16.0)):
			for x: int in range(floori(rect.position.x / 16.0), ceili(rect.end.x / 16.0)):
				_surfaces[Vector2i(x, y)] = surface


func _view_centers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if multiplayer.is_server() or (node as Node).is_multiplayer_authority():
			out.append((node as Node2D).global_position)
	return out


## Loads the pictures of the pieces near a player of this peer, drops the far ones.
func _stream_views(force: bool = false) -> void:
	var limits: Dictionary = TownRules.config().get("limits", {}) as Dictionary
	var near: float = float(limits.get("view_radius", 700.0))
	var far: float = float(limits.get("unview_radius", 900.0))
	var centers: Array[Vector2] = _view_centers()
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		if bool(TownRules.piece(String(data.p)).get("builtin", false)):
			continue
		var at: Vector2 = Vector2(float(data.x), float(data.y))
		var distance: float = INF
		for c: Vector2 in centers:
			distance = minf(distance, c.distance_to(at))
		if _views.has(id):
			if distance > far and not force:
				(_views[id] as TownStructure).queue_free()
				_views.erase(id)
		elif distance <= near or (force and centers.is_empty()):
			var view: TownStructure = TownStructure.new()
			view.name = "S%d" % id
			_root.add_child(view)
			view.setup(self, id)
			_views[id] = view


func view_of(id: int) -> TownStructure:
	return _views.get(id) as TownStructure


func _apply_all() -> void:
	_circles_dirty = true
	_rebuild_surfaces()
	if world != null:
		world.town_clear_cells(cleared.keys())
	for sid: String in residents:
		_ensure_settler(sid, false)
	_refresh_ways()
	_stream_views(true)
	changed.emit()


func build_mode() -> BuildMode:
	return _build


func _process(delta: float) -> void:
	if _build == null and local_player() != null:
		_build = BuildMode.new()
		add_child(_build)
		_build.setup(self)
	_stream_clock += delta
	if _stream_clock >= 0.5:
		_stream_clock = 0.0
		if founded:
			_stream_views()
	if not founded:
		_found_clock += delta
		if _found_clock >= 1.0:
			_found_clock = 0.0
			var player: Player = local_player()
			if player != null and player.quests != null and player.quests.has_flag("rebuild_done"):
				request_found()
		return
	if multiplayer.is_server():
		_arrival_clock += delta
		if _arrival_clock >= 1.0:
			_check_arrivals(_arrival_clock)
			_arrival_clock = 0.0
		var hour: int = int(TimeManager.time_of_day * 24.0)
		if hour != _last_hour:
			if _last_hour >= 0:
				_hour_tick()
			_last_hour = hour


# ---------- saving and joining ----------

func export_state() -> Dictionary:
	var out_structures: Dictionary = {}
	for id: int in structures:
		out_structures[str(id)] = (structures[id] as Dictionary).duplicate()
	var out_cleared: Array = []
	for cell: Vector2i in cleared:
		out_cleared.append([cell.x, cell.y])
	return {
		"version": STATE_VERSION, "founded": founded, "name": name_index, "center": [center.x, center.y], "day": founded_day,
		"next_id": next_id, "structures": out_structures, "stock": stock.duplicate(), "cleared": out_cleared, "residents": residents.duplicate(true), "paths": paths.duplicate(true), "orders": orders.duplicate(true),
	}


func import_state(data: Dictionary) -> void:
	structures.clear()
	stock.clear()
	cleared.clear()
	residents.clear()
	paths.clear()
	orders.clear()
	_progress.clear()
	for view: Variant in _views.values():
		(view as TownStructure).queue_free()
	_views.clear()
	for settler: Variant in _settlers.values():
		(settler as Settler).queue_free()
	_settlers.clear()
	for sprite: Variant in _path_views.values():
		(sprite as Sprite2D).queue_free()
	_path_views.clear()
	founded = bool(data.get("founded", false))
	name_index = int(data.get("name", 0))
	var middle: Array = data.get("center", [0, 0]) as Array
	center = Vector2(float(middle[0]), float(middle[1]))
	founded_day = int(data.get("day", 0))
	next_id = int(data.get("next_id", 1))
	var saved: Dictionary = data.get("structures", {}) as Dictionary
	for key: String in saved:
		var entry: Dictionary = saved[key] as Dictionary
		structures[int(key)] = {"p": String(entry.p), "x": float(entry.x), "y": float(entry.y), "f": int(entry.get("f", 0)), "g": int(entry.get("g", PROGRESS_FULL)), "b": int(entry.get("b", founded_day))}
		if int((structures[int(key)] as Dictionary).g) < PROGRESS_FULL:
			_progress[int(key)] = float((structures[int(key)] as Dictionary).g)
	var items: Dictionary = data.get("stock", {}) as Dictionary
	for item: String in items:
		stock[item] = int(items[item])
	for cell: Variant in data.get("cleared", []) as Array:
		cleared[Vector2i(int((cell as Array)[0]), int((cell as Array)[1]))] = true
	for way: Variant in data.get("paths", []) as Array:
		var entry: Dictionary = way as Dictionary
		paths.append({"s": int(entry.s), "p": (entry.p as Array).duplicate(true), "d": int(entry.get("d", 1)), "e": int(entry.get("e", 0))})
	for entry: Variant in data.get("orders", []) as Array:
		var e: Dictionary = entry as Dictionary
		orders.append({"r": String(e.r), "left": float(e.left), "total": float(e.total), "done": bool(e.done)})
	var people: Dictionary = data.get("residents", {}) as Dictionary
	for sid: String in people:
		var entry: Dictionary = people[sid] as Dictionary
		residents[sid] = {"trust": int(entry.get("trust", 0)), "talked": int(entry.get("talked", -1))}
	_apply_all()


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(data: Dictionary) -> void:
	var was: bool = founded
	import_state(data)
	if founded and not was:
		town_founded.emit()
