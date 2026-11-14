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
signal refine_done(before: Dictionary, after: Dictionary, success: bool, refund: Dictionary) ## the local player collected a refined weapon: the reveal card plays
signal brew_done(type: String, tier: int, count: int, moon: bool) ## the local player got potions from a brew (Esma): the brew card plays
signal refresh_done(raw: String, stones: Array) ## for the asking player only: Ilva showed what the raw stones hid (LÄUTERN)
signal notice(text: String, good: bool) ## a short message for the local builder ("NICHT GENUG HOLZ")
signal event(kind: String, data: Dictionary) ## what happened to the town, on every peer: "lamp_out", "level_up", "alert" (docs/town_ausbau.md; the settlers' chatter and the map listen)

const SETTLERS_TABLE: String = "settlers"
const PROGRESS_FULL: int = 1000
const STATE_VERSION: int = 1
const STOCK_SLOTS: int = 48 ## the stockpile: 8 x 6 slots

var world: WorldLevel
var founded: bool = false
var name_index: int = 0
var center: Vector2 = Vector2.ZERO ## the hut's feet: the heart of the town
var founded_day: int = 0
var critters: TownCritters
var structures: Dictionary = {} ## int id -> {p, x, y, f, g}; id 0 is the house
var box: ItemBox = ItemBox.new("town_stock", STOCK_SLOTS) ## the stock as slots (`StockWindow`, same stacks and clicks as the inventory); the host holds the truth and syncs it
var stock: Dictionary = {} ## item id -> count: the totals of `box`, refreshed with every change (what costs, recipes and quests read; never write to it, use `_add_stock`)
var cleared: Dictionary = {} ## Vector2i prop cell -> true: soft props the foundations removed for good
var residents: Dictionary = {} ## settler id -> {trust, talked}
var next_id: int = 1
var unlocks: Dictionary = {} ## name -> true: what the town has learned to do (docs/farming.md: "farming" opens the fields once Gustav has made the first hoe or can)
var board: BoardManager ## the quest board's notices (docs/questtafel_konzept.md); a child created on every peer
var farm: FarmManager ## the state of the fields (cells, crops); a child created on every peer
var caravan: CaravanManager ## the travelling merchant who visits the fountain square (docs/haendler_konzept.md); a child created on every peer

var _build: BuildMode ## the local builder (made once a local player exists)
var _banner: TownBanner
var paths: Array = [] ## trampled ways {s: structure id, p: [[x, y], ...] from a building's door to the network, d: 1 once the building stands, e: 1 when the end is a door (not a join)}: they stay when the building goes
var _path_root: Node2D
const MAX_ORDERS: int = 3

var debug_refine_seed: int = -1 ## tests: >= 0 fixes the dice of the next refinements
var _outposts: Dictionary = {} ## role -> Vector2 (global): places away from the town where a trade is valid (`register_outpost`)
var _persons: Dictionary = {} ## id -> Node2D: people who live elsewhere (`register_person`)
var orders: Array = [] ## what a settler is making on commission: {r recipe id, left work seconds, total, done}; they work only while at their bench, anyone collects. A refinement is one too: {r "refine", k "refine", m maker, w the weapon as it was handed in, to the level it is meant to reach, ok the result (rolled when it was handed in), left, total, done}
var _order_sync: float = 0.0
var brewed: Dictionary = {} ## alchemy (docs/alchemie_konzept.md): "type:tier" -> how often it was brewed (shared: Esma learns, not one player); a tier needs the one below brewed once
var alchemy_gift: bool = false ## Esma's first lesson gave her vials (once per world)
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
var _lit: Array[Vector3] = [] ## the circles of what really burns (a lamp post without flame carries none)
var _lit_dirty: bool = true
var _seat_root: Node2D
var _seats: Dictionary = {} ## "id_index" -> BenchSeat (always there, whether or not the bench's picture is loaded)
var _last_level: int = -1
var _wave_gains: Dictionary = {} ## id -> [[Vector2, item]]: what the pressure wave of a piece just finished brought in (`_rpc_wave`, shown by `_consecrate`)
var chatter: SettlerChatter
var alert_on: bool = false ## the dark gathers at the edge of the light (a raid is warned): Valdric keeps the watch, the edge of the light glows brighter
var alert_angle: float = 0.0 ## from the middle of the town towards where it gathers
var fear_on: bool = false ## the dark is near: the people run indoors and hide until it is quiet again (`Settler._fear_step`; Valdric keeps the watch instead)
var _touch_msec: int = 0
var _inside: bool = false ## the local player stands in the town
var _entered_day: int = -1
var _left_msec: int = -1 ## when the local player last left the town's light
var _hands: Dictionary = {} ## host: peer -> [site id, msec of the last grab]: who lends a hand where (counts x3 at that site)
var _help_site: int = -1 ## the site the local player lends a hand at (-1: none)
var _quiet: bool = false ## the developer checkpoint builds a whole town at once: no foundation stones, no consecrations
const HAND_WEIGHT: float = 3.0
const HAND_MSEC: int = 1600
var look_color: int = 0 ## the town's banner colour (`TownEmblems.COLORS`), chosen in the STADT tab
var look_emblem: int = 0 ## the town's emblem (`TownEmblems.GLYPHS`)
var wear: Dictionary = {} ## Vector2i cell (8 px) -> 0..1 how trodden the ground is (`TownWear`, computed on every peer from the state)
var _wear_dirty: bool = true
var _wear_clock: float = 0.0
var _wear_tex: ImageTexture
var light_scale: float = 1.0 ## 1, or less on a fog night: the light reaches that share as far
var _scaled: Array[Vector3] = []
var _scaled_version: int = -1
var _scaled_for: float = 1.0
static var magic_lights: Dictionary = {} ## instance id of a cast light -> Vector3(x, y, radius) (`add_magic_light`)
static var magic_version: int = 0
var _with_magic: Array[Vector3] = []
var _magic_built: Vector3i = Vector3i(-1, -1, -1)
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


func _init() -> void:
	box.reach_ok = func(who: Node2D) -> bool: return who is Player and _near_role(who as Player, "stock", 90.0)
	box.changed.connect(func() -> void:
		_refresh_stock()
		if is_inside_tree() and multiplayer.is_server():
			_sync_stock())


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
	chatter = SettlerChatter.new()
	chatter.name = "Chatter"
	chatter.town = self
	add_child(chatter)
	farm = FarmManager.new()
	farm.name = "Farm"
	add_child(farm)
	farm.setup(self)
	board = BoardManager.new()
	board.name = "Board"
	add_child(board)
	board.setup(self)
	caravan = CaravanManager.new()
	add_child(caravan)
	caravan.setup(self)
	_seat_root = Node2D.new()
	_seat_root.name = "Seats"
	_seat_root.y_sort_enabled = true
	add_child(_seat_root)
	_settler_root = Node2D.new()
	_settler_root.name = "Settlers"
	_settler_root.y_sort_enabled = true
	add_child(_settler_root)
	Terrain.patches.append(self)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_snapshot.rpc_id(id, export_state(true)))
	built.connect(_on_built)
	changed.connect(func() -> void: _wear_dirty = true)
	town_founded.connect(func() -> void:
		_entered_day = TimeManager.day) ## the ground is claimed; the town itself is founded by its fountain square (`_found_heart`)
	built.connect(func(piece: String, _id: int) -> void:
		if piece == "plaza" and not _quiet:
			get_tree().create_timer(2.6, false).timeout.connect(_found_heart))
	resident_joined.connect(func(sid: String) -> void:
		_circles_dirty = true ## residents add worth: the level (and with it the light) may grow
		town_banner({"header": "NEU IN %s" % town_name(), "title": "%s ZIEHT EIN" % String(settler_spec(sid).get("name", sid)), "sub": String(settler_spec(sid).get("title", ""))}))
	event.connect(_on_town_event)
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
	if piece == "quest_board" and board != null and multiplayer.is_server():
		board.check_story_now()
	if player != null and TownRules.piece(piece).has("fuel"):
		notice.emit("E AM PFOSTEN: ANZÜNDEN", true) ## a new lamp post is cold until somebody lights it


func _announce(title: String, sub: String) -> void:
	if local_player() == null:
		return
	_banner_node().show_text(title, sub)


func _banner_node() -> TownBanner:
	if _banner == null:
		_banner = TownBanner.new()
		add_child(_banner)
	return _banner


## The fountain square is finished: now the town is founded for real (docs/brunnenplatz.md).
func _found_heart() -> void:
	_entered_day = TimeManager.day
	town_banner({"header": "STADT GEGRÜNDET", "title": town_name(), "sub": "DER BRUNNEN IST IHR HERZ", "big": true, "sound": "level_bells"})


## The heart of the town: the fountain square once it is built (where the ways lead), else the house.
func heart() -> Vector2:
	var ids: Array[int] = built_ids("plaza")
	return position_of(ids[0]) + Vector2(0.0, -8.0) if not ids.is_empty() else center


## Has the town its heart yet? Until then it is only claimed ground round the hut.
func has_heart() -> bool:
	return has_built("plaza")


## The town's own banner (its colour and emblem): `info` as `TownBanner.show_banner`.
func town_banner(info: Dictionary) -> void:
	if local_player() == null:
		return
	var full: Dictionary = info.duplicate()
	full["color"] = TownEmblems.color(look_color)
	full["emblem"] = look_emblem
	_banner_node().show_banner(full)


## What happens to the town, on every peer: a new level is a ceremony (docs/stadtbau_konzept.md 5.2).
func _on_town_event(kind: String, data: Dictionary) -> void:
	if kind == "level_up":
		_circles_dirty = true
		get_tree().create_timer(2.4, false).timeout.connect(func() -> void: _level_ceremony(int(data.get("level", level()))))


## A new level: every finished building lights up one after the other from the house outwards, a ring of light runs from the house to the edge of the
## town's light, the bells ring and the banner names the level and what it brings.
func _level_ceremony(index: int) -> void:
	var player: Player = local_player()
	if player == null or not founded:
		return
	var far: float = 0.0
	var middle: Vector2 = heart()
	for c: Vector3 in circles():
		far = maxf(far, Vector2(c.x, c.y).distance_to(middle) + c.z)
	if player.global_position.distance_to(middle) < far + 200.0:
		for id: int in _views:
			var view: TownStructure = _views[id] as TownStructure
			if is_instance_valid(view) and view.is_done():
				view.flare(view.position.distance_to(middle) / 260.0)
		TownConsecration.play(_root, middle, {"radius": 0.0, "reach": far, "light_color": Color("ffd27a")})
	var levels: Array = TownRules.config().get("levels", []) as Array
	var spec: Dictionary = levels[clampi(index, 0, levels.size() - 1)] as Dictionary if not levels.is_empty() else {}
	var gift: String = String(spec.get("gift", ""))
	town_banner({"header": "%s WÄCHST" % town_name(), "title": TownRules.level_name(index), "sub": gift, "big": true, "sound": "level_bells"})


func _on_day_started(_day: int) -> void:
	_wear_dirty = true ## the ground wears in with the days
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


## How much further every light of the town reaches at its level (`levels[].light` in town.json): a bigger town holds the dark further off.
func light_grow() -> float:
	var levels: Array = TownRules.config().get("levels", []) as Array
	return float((levels[clampi(level(), 0, levels.size() - 1)] as Dictionary).get("light", 1.0)) if not levels.is_empty() else 1.0


## Circles of light {x, y, reach} of the finished pieces: the ground the group may build on.
func circles() -> Array[Vector3]:
	if _circles_dirty:
		_circles.clear()
		var grow: float = light_grow()
		for id: int in structures:
			var data: Dictionary = structures[id] as Dictionary
			var reach: float = float(TownRules.piece(String(data.p)).get("reach", 0.0)) * grow
			if reach > 0.0 and int(data.g) >= PROGRESS_FULL:
				_circles.append(Vector3(float(data.x), float(data.y) - 8.0, reach))
		_circles_dirty = false
		_lit_dirty = true
		_circles_version += 1
	return _circles


func in_territory(pos: Vector2) -> bool:
	return TownRules.covers(circles(), pos)


# ---------- lamp posts: cold, lit, empty (docs/town_ausbau.md B9) ----------

## The fuel data of a lamp post ({} for every other piece).
func lamp_spec(id: int) -> Dictionary:
	if not structures.has(id):
		return {}
	return TownRules.piece(String((structures[id] as Dictionary).p)).get("fuel", {}) as Dictionary


## {f fuel 0..1000, l 1 once lit}. A lamp from an older save has no state: it burns, full.
func lamp_u(id: int) -> Dictionary:
	var u: Variant = (structures[id] as Dictionary).get("u", null) if structures.has(id) else null
	if u is Dictionary:
		return {"f": int((u as Dictionary).get("f", 0)), "l": int((u as Dictionary).get("l", 0))}
	return {"f": 1000, "l": 1}


## "" (not a lamp), "cold" (never lit), "lit", "empty" (burnt down).
func lamp_state(id: int) -> String:
	if lamp_spec(id).is_empty():
		return ""
	var u: Dictionary = lamp_u(id)
	if int(u.l) == 0:
		return "cold"
	return "lit" if int(u.f) > 0 else "empty"


func is_lamp_burning(id: int) -> bool:
	return lamp_state(id) == "lit"


## What E does at a lamp post ("" = nothing).
func lamp_prompt(id: int) -> String:
	match lamp_state(id):
		"cold":
			return "ANZÜNDEN"
		"empty":
			return "NACHFÜLLEN"
		"lit":
			return "NACHFÜLLEN" if int(lamp_u(id).f) <= 600 else ""
	return ""


func request_lamp(id: int) -> void:
	if multiplayer.is_server():
		_host_lamp(id, multiplayer.get_unique_id())
	else:
		_rpc_lamp_request.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lamp_request(id: int) -> void:
	if multiplayer.is_server():
		_host_lamp(id, multiplayer.get_remote_sender_id())


func _host_lamp(id: int, peer: int) -> void:
	var spec: Dictionary = lamp_spec(id)
	var player: Player = player_of(peer)
	if spec.is_empty() or player == null or not is_built(id) or lamp_prompt(id) == "":
		return
	if player.global_position.distance_to(rect_of(id).get_center()) > 90.0:
		return
	var cost: Dictionary = {String(spec.item): 1}
	if not can_afford(cost, player):
		_tell(peer, missing_text(cost, player), false)
		return
	_pay(cost, player)
	_sync_stock()
	_rpc_lamp.rpc(id, mini(1000, int(lamp_u(id).f) + int(spec.get("per_item", 500))), 1, true)


@rpc("authority", "call_local", "reliable")
func _rpc_lamp(id: int, fuel: int, lit: int, spark: bool) -> void:
	if not structures.has(id):
		return
	(structures[id] as Dictionary).u = {"f": fuel, "l": lit}
	_circles_dirty = true ## the night's circles follow the flames
	if _views.has(id):
		(_views[id] as TownStructure).refresh_lamp(spark)
	changed.emit()


## Host, every game hour: lit lamps burn down while it is night; a lamp that goes out says so.
func _burn_lamps() -> void:
	if not TimeManager.is_night():
		return
	var out: int = 0
	for id: int in structures.keys():
		var spec: Dictionary = lamp_spec(id)
		if spec.is_empty() or not is_built(id) or not is_lamp_burning(id):
			continue
		var per_hour: int = int(round(1000.0 / (float(spec.get("nights", 3.0)) * 8.0)))
		var fuel: int = maxi(int(lamp_u(id).f) - per_hour, 0)
		_rpc_lamp.rpc(id, fuel, 1, false)
		if fuel == 0:
			out += 1
	if out > 0:
		banner("EIN LICHT ERLISCHT" if out == 1 else "%d LICHTER ERLISCHEN" % out, "")
		emit_event("lamp_out", {"count": out})


## Host: the dark gathers (or the alarm is over). Everyone's settlers and the glow of the light's edge follow.
func set_alert(on: bool, angle: float) -> void:
	if multiplayer.is_server() and (on != alert_on or (on and not is_equal_approx(angle, alert_angle))):
		_rpc_alert.rpc(on, angle)


@rpc("authority", "call_local", "reliable")
func _rpc_alert(on: bool, angle: float) -> void:
	alert_on = on
	alert_angle = angle


## Host: the people of the town are afraid (creatures at the edge of the light, a call, a raid) or calm again. Every peer's settlers follow.
func set_fear(on: bool) -> void:
	if multiplayer.is_server() and on != fear_on:
		_rpc_fear.rpc(on)


@rpc("authority", "call_local", "reliable")
func _rpc_fear(on: bool) -> void:
	fear_on = on
	if on:
		event.emit("fear", {})
	else:
		event.emit("fear_over", {})


## Host: a creature is turned back at the edge of the light at `pos`: sparks on every peer (at most four a second).
func light_touch(pos: Vector2) -> void:
	if not multiplayer.is_server() or not founded:
		return
	var now: int = Time.get_ticks_msec()
	if now - _touch_msec < 250:
		return
	_touch_msec = now
	_rpc_light_touch.rpc(pos)


@rpc("authority", "call_local", "unreliable")
func _rpc_light_touch(pos: Vector2) -> void:
	var near: bool = false
	for center: Vector2 in _view_centers():
		near = near or center.distance_to(pos) < 420.0
	if not near:
		return
	var sparks: CPUParticles2D = CPUParticles2D.new()
	sparks.one_shot = true
	sparks.emitting = true
	sparks.amount = 14
	sparks.lifetime = 0.6
	sparks.explosiveness = 0.9
	sparks.direction = Vector2.UP
	sparks.spread = 180.0
	sparks.gravity = Vector2(0.0, 30.0)
	sparks.initial_velocity_min = 18.0
	sparks.initial_velocity_max = 54.0
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 1.5
	sparks.color = Color("9ff7ea")
	sparks.material = Unlit.material()
	sparks.global_position = pos
	sparks.z_index = 8
	add_child(sparks)
	get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)
	if ResourceLoader.exists("res://assets/audio/town/light_touch.wav"):
		var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sound.stream = load("res://assets/audio/town/light_touch.wav") as AudioStream
		sound.volume_db = -12.0
		sound.max_distance = 300.0
		sound.global_position = pos
		add_child(sound)
		sound.finished.connect(sound.queue_free)
		sound.play()


## Host: tells every peer what happened to the town.
func emit_event(kind: String, data: Dictionary = {}) -> void:
	if multiplayer.is_server():
		_rpc_event.rpc(kind, data)


@rpc("authority", "call_local", "reliable")
func _rpc_event(kind: String, data: Dictionary) -> void:
	event.emit(kind, data)


## Host: a rise in the town's level is an event.
func _check_level() -> void:
	var now: int = level()
	if _last_level >= 0 and now > _last_level:
		emit_event("level_up", {"level": now, "name": TownRules.level_name(now)})
	_last_level = now


# ---------- the night (docs/nacht_monster_konzept.md): light is land ----------

## How deep `pos` lies in the light of the town: positive inside a circle, negative = distance to the nearest one (-9999 when nothing is lit or the town is not founded).
func light_depth(pos: Vector2) -> float:
	return TownRules.light_depth(lit_circles(), pos) if founded else -9999.0


## The circles as the night sees them: shrunk on a fog night (`light_scale`, set by `NightAtmosphere` on every peer). Building rules still use `circles()`.
func lit_circles() -> Array[Vector3]:
	circles() ## (rebuilds the building circles first, which also marks the lit ones as old)
	if _lit_dirty:
		_lit.clear()
		for id: int in structures:
			var data: Dictionary = structures[id] as Dictionary
			var reach: float = float(TownRules.piece(String(data.p)).get("reach", 0.0)) * light_grow()
			if reach > 0.0 and int(data.g) >= PROGRESS_FULL and (lamp_spec(id).is_empty() or is_lamp_burning(id)):
				_lit.append(Vector3(float(data.x), float(data.y) - 8.0, reach))
		_lit_dirty = false
		_circles_version += 1
	var base: Array[Vector3] = _lit
	if not is_equal_approx(light_scale, 1.0):
		if _scaled_version != _circles_version or not is_equal_approx(_scaled_for, light_scale):
			_scaled.clear()
			for c: Vector3 in _lit:
				_scaled.append(Vector3(c.x, c.y, c.z * light_scale))
			_scaled_version = _circles_version
			_scaled_for = light_scale
		base = _scaled
	if magic_lights.is_empty():
		return base
	if _magic_built != Vector3i(magic_version, _circles_version, roundi(light_scale * 1000.0)):
		_with_magic = base.duplicate()
		for circle: Variant in magic_lights.values():
			_with_magic.append(circle as Vector3)
		_magic_built = Vector3i(magic_version, _circles_version, roundi(light_scale * 1000.0))
	return _with_magic


## Magic (docs/magie_konzept.md): a cast light the night respects like a lamp (Bannlicht from tier III, BANNKREIS) while it stands. Every peer keeps its own copy.
static func add_magic_light(key: int, circle: Vector3) -> void:
	magic_lights[key] = circle
	magic_version += 1


static func remove_magic_light(key: int) -> void:
	if magic_lights.erase(key):
		magic_version += 1


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
			var lit: Vector2 = to.lerp(from, float(maxi(i - 1, 0)) / float(steps))
			for k: int in 6: ## narrow the step down to about a pixel: the edge, not somewhere up to a step past it
				var middle: Vector2 = lit.lerp(point, 0.5)
				if light_depth(middle) < -margin:
					point = middle
				else:
					lit = middle
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
	var needs_who: String = String(spec.get("needs_resident", ""))
	if needs_who != "" and not residents.has(needs_who):
		return false ## the workshop waits for Gustav (story: he is rescued first)
	var needs_unlock: String = String(spec.get("needs_unlock", ""))
	if needs_unlock != "" and not unlocks.has(needs_unlock):
		return false ## the fields wait for Gustav's first hoe or watering can
	var needs: String = String(spec.get("needs", ""))
	return needs == "" or has_built(needs)


func lock_reason(piece: String) -> String:
	var spec: Dictionary = TownRules.piece(piece)
	if level() < int(spec.get("level", 0)):
		return "STUFE %s NÖTIG" % TownRules.level_name(int(spec.get("level", 0)))
	var needs_who: String = String(spec.get("needs_resident", ""))
	if needs_who != "" and not residents.has(needs_who):
		return "BRAUCHT %s" % String(settler_spec(needs_who).get("name", needs_who))
	var needs_unlock: String = String(spec.get("needs_unlock", ""))
	if needs_unlock != "" and not unlocks.has(needs_unlock):
		return "GUSTAV MUSS HACKE ODER KANNE FERTIGEN"
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
## "" when the site is fine, otherwise a short reason. `ignore`: a piece that is being moved (it does not stand in its own way).
func check_site(piece: String, pos: Vector2, check_world: bool = true, ignore: int = -1) -> String:
	var spec: Dictionary = TownRules.piece(piece)
	if spec.is_empty():
		return "UNBEKANNT"
	if not in_territory(pos):
		return "AUSSERHALB DES LICHTS"
	var rect: Rect2 = TownRules.foot_rect(piece, pos.x, pos.y)
	var front: Rect2 = TownRules.front_rect(piece, pos.x, pos.y)
	var walks: bool = bool(spec.get("walk", false))
	if caravan != null and piece != "plaza":
		var parked: String = caravan.blocks(rect)
		if parked != "":
			return parked
	for id: int in structures:
		if id == ignore:
			continue
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
		var own: Array[RID] = (_views[ignore] as TownStructure).solid_rids() if _views.has(ignore) and is_instance_valid(_views[ignore]) else ([] as Array[RID])
		var reason: String = world.town_probe(rect, own)
		if reason != "":
			return reason
		if front.has_area():
			reason = world.town_probe(front, own) ## a fallen log, a trunk or a rock in front of the door: nobody could get in
			if reason != "":
				return "TÜR ZUGESTELLT" if reason == "IM WEG" else reason
		var body: Rect2 = rect ## where nobody may stand: the footprint, or on a walkable floor only what stands on it (the fountain)
		if bool(spec.get("walk", false)):
			var solid: Array = (spec.get("stand", {}) as Dictionary).get("solid", []) as Array
			body = Rect2(pos.x - float(solid[0]) / 2.0, pos.y - float(solid[1]), float(solid[0]), float(solid[1])) if solid.size() == 2 else Rect2()
		if body.has_area():
			for node: Node in get_tree().get_nodes_in_group("players"):
				if body.grow(5.0).has_point((node as Node2D).global_position):
					return "JEMAND STEHT DARIN"
			for node: Node in get_tree().get_nodes_in_group("settlers"):
				if body.grow(5.0).has_point((node as Node2D).global_position):
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
	if spec.has("limit") and count_of(piece) >= int(spec.limit):
		return "STEHT SCHON" if int(spec.limit) == 1 else "NUR %d MAL" % int(spec.limit)
	if structures.size() >= int((TownRules.config().get("limits", {}) as Dictionary).get("max_pieces", 400)):
		return "ZU VIELE TEILE"
	if builder != null and builder.global_position.distance_to(pos) > float((TownRules.config().get("limits", {}) as Dictionary).get("build_reach", 240.0)):
		return "ZU WEIT WEG"
	var reason: String = check_site(piece, pos, check_world)
	if reason != "":
		return reason
	return missing_text(spec.get("cost", {}) as Dictionary, builder)


## Can the piece `id` be carried to `pos` (snapped)? The same site rules as a new piece (it does not stand in its own way), the builder must reach both the old
## and the new place; it costs nothing. The house stays, and the fountain square stays while the caravan stands on it.
func check_move(id: int, pos: Vector2, builder: Player, check_world: bool = true) -> String:
	if not founded:
		return "KEINE STADT"
	if not structures.has(id):
		return "UNBEKANNT"
	var data: Dictionary = structures[id] as Dictionary
	var piece: String = String(data.p)
	if bool(TownRules.piece(piece).get("builtin", false)):
		return "DAS HAUS BLEIBT"
	if piece == "plaza" and caravan != null and CaravanRules.parked(caravan.state()):
		return "DIE KARAWANE STEHT DARAUF"
	var reach: float = float((TownRules.config().get("limits", {}) as Dictionary).get("build_reach", 240.0))
	if builder != null and (builder.global_position.distance_to(pos) > reach or builder.global_position.distance_to(position_of(id)) > reach):
		return "ZU WEIT WEG"
	return check_site(piece, pos, check_world, id)


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
	_rpc_snapshot.rpc(export_state(true))
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
		var rect: Rect2 = TownRules.foot_rect(String(data.p), float(data.x), float(data.y))
		for cell: Variant in world.town_clear_clover(rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5):
			cleared[cell as Vector2i] = true
	next_id = maxi(next_id, id + 1)
	_circles_dirty = true
	_register(id)
	if not _quiet and _views.has(id) and int(data.get("g", 0)) == 0:
		(_views[id] as TownStructure).lay_foundation()
	changed.emit()


## Developer checkpoint (Escape menu -> ENTWICKLER -> FERTIGE STADT): the town is founded, every piece of the catalogue stands finished round the hut (what is there already is kept) and
## every settler whose building stands is at home. Nothing is paid, nothing is asked. Solo / host only.
func debug_build_all(with_torben: bool = false) -> void:
	if not multiplayer.is_server() or world == null:
		return
	request_found()
	if not founded:
		return
	_quiet = true ## the whole town at once: no stones, no consecrations
	if not unlocks.has("farming"):
		_rpc_unlock.rpc("farming", false) ## the checkpoint town has its hoe and can: fields are open
	var plan: Array = [["plaza", Vector2(0, 150)], ["lamp_post", Vector2(-80, 120)], ["lamp_post", Vector2(150, 140)], ["workshop", Vector2(40, 175)], ["stockpile", Vector2(-110, 190)], ["bench", Vector2(80, 100)]]
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
		if spec.has("fuel"):
			_rpc_lamp.rpc(id, 1000, 1, false) ## the checkpoint town burns
		(structures[id] as Dictionary).b = TimeManager.day - 6 ## the checkpoint town has stood a while: its wear is already there
	for sid: String in settler_ids():
		var settler: Dictionary = settler_spec(sid)
		if (not bool(settler.get("enabled", true)) or sid == "torben") and not (with_torben and sid == "torben"):
			continue
		var arrive: Dictionary = settler.get("arrive", {}) as Dictionary
		if not residents.has(sid) and has_built(String(arrive.get("needs", ""))):
			_rpc_resident.rpc(sid, {"trust": 30 if with_torben else 0, "talked": -1}, false) ## not freshly arrived: they are simply at home (the full checkpoint also knows their trust)
	_sync_stock()
	_quiet = false


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
	if amount < 0:
		box.remove_item(item, -amount)
	elif box.add_item(item, amount) > 0:
		push_warning("town stock is full: %s lost" % item) ## ponytail: STOCK_SLOTS is the ceiling, a bigger box (or a second stockpile) when it bites
	_refresh_stock()


func _refresh_stock() -> void:
	stock = box.totals()


func _sync_stock() -> void:
	_rpc_stock_state.rpc(box.slots)


@rpc("authority", "call_local", "reliable")
func _rpc_stock_state(new_slots: Array) -> void:
	box.import_slots(new_slots)
	_refresh_stock()
	changed.emit()


# ---------- trampled ways ----------

## Host: a building gets a way from its door towards the town (the hut's door, another building's door); on the way it joins an older way when it meets one
## (`TownWays`). The front is tried first; when something stands in front of it (a fallen log) the sides and the back are. `done`: the piece stands already (it was
## moved), the way shows at once.
func _host_make_way(id: int, done: bool = false) -> void:
	if world == null:
		return
	var hut: Hut = world.hut_node()
	var rect: Rect2 = rect_of(id)
	var doors: Array[Vector2] = [position_of(id) + Vector2(0.0, 9.0), rect.get_center() + Vector2(rect.size.x / 2.0 + 8.0, 0.0), rect.get_center() - Vector2(rect.size.x / 2.0 + 8.0, 0.0), rect.get_center() - Vector2(0.0, rect.size.y / 2.0 + 8.0)]
	var targets: Array[Vector2] = []
	var square: int = -1
	for other: int in structures:
		if String((structures[other] as Dictionary).p) == "plaza":
			square = other
	if String((structures[id] as Dictionary).p) == "plaza":
		var ring: Array[Vector2] = _square_rim(id) ## the square's own way leaves from its rim towards the house
		if hut != null:
			ring.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(hut.exit_position) < b.distance_to(hut.exit_position))
		doors = ring
	if square >= 0 and square != id:
		targets = _square_rim(square) ## every way leads to the fountain square: the heart of the town
	else:
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
		_rpc_way_added.rpc({"s": id, "p": pts_out, "d": 1 if done else 0, "e": 0 if bool(made.joined) else 1})
		return


## Points just outside the fountain square's cobbles where ways begin and end (12 round its ellipse).
func _square_rim(id: int) -> Array[Vector2]:
	var rect: Rect2 = rect_of(id)
	var out: Array[Vector2] = []
	for k: int in 12:
		var a: float = TAU * float(k) / 12.0
		out.append(rect.get_center() + Vector2(cos(a) * (rect.size.x * 0.5 + 6.0), sin(a) * (rect.size.y * 0.5 + 5.0)))
	return out


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
	if caravan != null and CaravanRules.parked(caravan.state()): ## the stall on the square: people walk round it
		solids.append(caravan.footprint())
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
	var key: int = next_id * 1000003 + structures.size() * 1009 + paths.size() * 31 + finished + (7 if caravan != null and CaravanRules.parked(caravan.state()) else 0)
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
	if farm != null:
		farm.field_removed(id)
	for i: int in range(paths.size() - 1, -1, -1):
		if int((paths[i] as Dictionary).s) == id and int((paths[i] as Dictionary).d) == 0:
			paths.remove_at(i) ## a way nobody ever walked is not kept
	_refresh_ways()
	_circles_dirty = true
	_rebuild_surfaces()
	_sync_seats()
	changed.emit()


# ---------- moving ----------

## Local builder asks to carry the piece `id` to `pos` (already snapped), mirrored or not. Free; a site keeps its progress, a field its beds.
func request_move(id: int, pos: Vector2, flip: bool) -> void:
	if multiplayer.is_server():
		_host_move(id, pos, 1 if flip else 0, multiplayer.get_unique_id())
	else:
		_rpc_move.rpc_id(1, id, pos.x, pos.y, 1 if flip else 0)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_move(id: int, x: float, y: float, flip: int) -> void:
	if multiplayer.is_server():
		_host_move(id, Vector2(x, y), flip, multiplayer.get_remote_sender_id())


func _host_move(id: int, pos: Vector2, flip: int, peer: int) -> void:
	if not structures.has(id):
		return
	var piece: String = String((structures[id] as Dictionary).p)
	pos = TownRules.snapped_position(piece, pos)
	var reason: String = check_move(id, pos, player_of(peer))
	if reason != "":
		_tell(peer, reason, false)
		return
	var spec: Dictionary = TownRules.piece(piece)
	var rect: Rect2 = TownRules.foot_rect(piece, pos.x, pos.y)
	var front: Rect2 = TownRules.front_rect(piece, pos.x, pos.y)
	var cells: Array = world.town_soft_cells(rect.merge(front) if front.has_area() else rect) if world != null else []
	_rpc_moved.rpc(id, pos.x, pos.y, flip, cells)
	if bool(spec.get("paths", false)):
		_host_make_way(id, is_built(id)) ## a way from the new door (the old one stays trodden, like the way of a piece that was taken down)
	_tell(peer, "%s VERSETZT" % String(spec.name), true)


@rpc("authority", "call_local", "reliable")
func _rpc_moved(id: int, x: float, y: float, flip: int, cells: Array) -> void:
	if not structures.has(id):
		return
	var data: Dictionary = structures[id] as Dictionary
	data.x = x
	data.y = y
	data.f = flip
	for cell: Variant in cells:
		cleared[cell as Vector2i] = true
	if world != null:
		world.town_clear_cells(cells)
		var rect: Rect2 = rect_of(id)
		for cell: Variant in world.town_clear_clover(rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5):
			cleared[cell as Vector2i] = true
	var dropped: bool = false
	for i: int in range(paths.size() - 1, -1, -1):
		if int((paths[i] as Dictionary).s) == id and int((paths[i] as Dictionary).d) == 0:
			paths.remove_at(i) ## the planned way of a site led to the old door
			dropped = true
	if dropped: ## the pictures are kept by index: lay them out again
		for sprite: Variant in _path_views.values():
			(sprite as Sprite2D).queue_free()
		_path_views.clear()
		_refresh_ways()
	if _views.has(id):
		(_views[id] as TownStructure).dismantle()
		_views.erase(id)
	_walk_key = -1 ## the settlers find their ways anew
	_circles_dirty = true
	_register(id)
	if _views.has(id):
		(_views[id] as TownStructure).arrive()
	_sync_seats()
	changed.emit() ## a field's beds go along by themselves (they are kept by index in the field)


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
		var helpers: float = 0.0
		for p: Player in players:
			if p.global_position.distance_to(middle) <= radius:
				helpers += _hand_weight(p.get_multiplayer_authority(), id)
		for sid: String in _settlers:
			if (_settlers[sid] as Settler).is_helping() and (_settlers[sid] as Settler).global_position.distance_to(middle) <= radius * 1.4:
				helpers += 1.0
		if helpers <= 0.0:
			continue
		var rate: float = float(PROGRESS_FULL) / maxf(float(spec.get("build_seconds", 5.0)), 0.5) * (1.0 + 0.5 * (helpers - 1.0))
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
			_host_wave(id)
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


## How far the pressure wave of a finished `piece` reaches from its feet: its data `wave` (px beyond the walls) plus half its footprint's width; 0 = none.
static func wave_radius(piece: String) -> float:
	var spec: Dictionary = TownRules.piece(piece)
	var wave: float = float(spec.get("wave", 0.0))
	return wave + float((spec.get("foot", [0, 0]) as Array)[0]) * 0.5 if wave > 0.0 else 0.0


## Local player, E at a site: she lends a hand there. Each round of her working clip (the picking motion: she stoops, takes, sets) is a grab; the host
## counts her as three helpers while the grabs keep coming. Any movement or a finished site ends it (`_update_help`).
func lend_hand(player: Player, id: int) -> void:
	if not structures.has(id) or is_built(id) or player.is_busy():
		return
	_help_site = id
	_grab(player)


func _grab(player: Player) -> void:
	var rect: Rect2 = rect_of(_help_site)
	var aim: Vector2 = Vector2(clampf(player.global_position.x, rect.position.x, rect.end.x), clampf(player.global_position.y, rect.position.y, rect.end.y)) - player.global_position
	var site: int = _help_site
	player.begin_pick(aim if aim.length() > 1.0 else player.facing, func() -> void:
		if multiplayer.is_server():
			_rpc_hand(site)
		else:
			_rpc_hand.rpc_id(1, site))
	if _views.has(site):
		(_views[site] as TownStructure).helping_here = true


func _update_help() -> void:
	if _help_site < 0:
		return
	var player: Player = local_player()
	var stop: bool = player == null or not structures.has(_help_site) or is_built(_help_site) or player.health.current <= 0.0 or player.story_lock
	if not stop and InputManager.move_vector().length() > 0.2:
		stop = true
	if not stop and player.global_position.distance_to(rect_of(_help_site).get_center()) > float((TownRules.config().get("limits", {}) as Dictionary).get("helper_radius", 100.0)):
		stop = true
	if stop:
		if _views.has(_help_site):
			(_views[_help_site] as TownStructure).helping_here = false
		_help_site = -1
		return
	if not player.is_busy():
		_grab(player)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand(id: int) -> void:
	if not multiplayer.is_server() or not structures.has(id) or is_built(id):
		return
	var peer: int = multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	_hands[peer] = [id, Time.get_ticks_msec()]
	var who: Player = player_by_peer(peer)
	_rpc_hand_fx.rpc(id, who.global_position + Vector2(0, -22) if who != null else rect_of(id).get_center())


@rpc("authority", "call_local", "unreliable")
func _rpc_hand_fx(id: int, from: Vector2) -> void:
	if _views.has(id):
		(_views[id] as TownStructure).hand_burst(from)


func player_by_peer(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.get_multiplayer_authority() == peer:
			return node as Player
	return null


## Host: how much a player counts at site `id` (3 while lending a hand there, else 1).
func _hand_weight(peer: int, id: int) -> float:
	var hand: Array = _hands.get(peer, []) as Array
	return HAND_WEIGHT if hand.size() == 2 and int(hand[0]) == id and Time.get_ticks_msec() - int(hand[1]) < HAND_MSEC else 1.0


## Host, the moment a piece is finished: its pressure wave (data `wave` px, docs/stadtbau_konzept.md 4) tears the soft props and small plants round it out
## (only inside the light, the new piece's own circle included) and what they would give goes into the stock. Sent before `_rpc_done` on the same channel.
func _host_wave(id: int) -> void:
	var data: Dictionary = structures[id] as Dictionary
	var spec: Dictionary = TownRules.piece(String(data.p))
	var radius: float = wave_radius(String(data.p))
	if radius <= 0.0 or world == null:
		return
	var at: Vector2 = position_of(id)
	var lit: Array[Vector3] = circles().duplicate()
	if float(spec.get("reach", 0.0)) > 0.0:
		lit.append(Vector3(at.x, at.y - 8.0, float(spec.reach)))
	var cells: Array = world.town_wave_cells(at, radius, lit)
	var gains: Array = []
	for cell: Variant in cells:
		var item: String = world.town_wave_yield(cell as Vector2i)
		if item != "":
			_add_stock(item, 1)
			gains.append([world.prop_position(cell as Vector2i), item])
	if not gains.is_empty():
		_sync_stock()
	_rpc_wave.rpc(id, cells, gains)


@rpc("authority", "call_local", "reliable")
func _rpc_wave(id: int, cells: Array, gains: Array) -> void:
	for cell: Variant in cells:
		cleared[cell as Vector2i] = true
	if world != null and structures.has(id):
		world.town_uproot(cells, position_of(id), TownConsecration.WAVE_SPEED, TownConsecration.WAVE_START)
		for cell: Variant in world.town_clear_clover(position_of(id), wave_radius(String((structures[id] as Dictionary).p))):
			cleared[cell as Vector2i] = true
	_wave_gains[id] = gains


## Everyone near: the consecration of a finished piece (`TownConsecration`): impact, bell, wave, light flooding out, the gains flying to the stockpile.
func _consecrate(id: int) -> void:
	var view: TownStructure = _views.get(id) as TownStructure
	if view == null or not is_instance_valid(view):
		_wave_gains.erase(id)
		return
	var data: Dictionary = structures[id] as Dictionary
	var spec: Dictionary = TownRules.piece(String(data.p))
	var target: Vector2 = Vector2.INF
	var stocks: Array[int] = built_ids("stockpile")
	if not stocks.is_empty() and stocks[0] != id:
		target = door_of(stocks[0])
	var light: Dictionary = (spec.get("aura", spec.get("light", {})) as Dictionary)
	TownConsecration.play(view.get_parent(), view.position, {
		"radius": wave_radius(String(data.p)),
		"reach": float(spec.get("reach", 0.0)),
		"title": String(spec.get("name", "")).to_upper(),
		"worth": float(spec.get("worth", 0.0)),
		"light_color": Color(String(light.get("color", "ffd27a"))),
		"gains": _wave_gains.get(id, []),
		"gain_target": target,
		"height": float(spec.get("feet", 40.0)),
	})
	_wave_gains.erase(id)


@rpc("authority", "call_local", "reliable")
func _rpc_done(id: int) -> void:
	if not structures.has(id):
		return
	var data: Dictionary = structures[id] as Dictionary
	data.g = PROGRESS_FULL
	data.b = TimeManager.day ## the day it was finished: what a piece collects with age (TownStructure `wear`)
	if TownRules.piece(String(data.p)).has("fuel") and not data.has("u"):
		data.u = {"f": 0, "l": 0} ## a new lamp post is cold until it is lit by hand
	for way: Variant in paths:
		if int((way as Dictionary).s) == id:
			(way as Dictionary).d = 1
	_refresh_ways()
	_circles_dirty = true
	_register(id)
	if _views.has(id):
		(_views[id] as TownStructure).set_progress(PROGRESS_FULL, true)
		if not _quiet:
			_consecrate(id)
	_sync_seats()
	built.emit(String(data.p), id)
	if multiplayer.is_server():
		_check_level()
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


## A place away from the town where a trade is valid too (the witch's room: `InteriorResident`), by the role its shop names.
func register_outpost(role: String, at: Vector2) -> void:
	if role != "":
		_outposts[role] = at


## Somebody who is no `Settler` of the town but can be traded with (the witch): the shop window frames them and lets them answer.
func clear_outpost(role: String) -> void:
	_outposts.erase(role)


func register_person(id: String, node: Node2D) -> void:
	_persons[id] = node


## The figure of a person: the town's settler, or somebody who lives elsewhere.
func person_node(id: String) -> Node2D:
	var settler: Settler = settler_node(id)
	if settler != null:
		return settler
	var other: Variant = _persons.get(id)
	return other as Node2D if other != null and is_instance_valid(other) else null


func _near_role(player: Player, role: String, reach: float) -> bool:
	if _outposts.has(role) and player.global_position.distance_to(_outposts[role] as Vector2) <= reach:
		return true
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


## Has the player really met this person? A settler is known from the first talk on (`talked` >= 0); the founder
## (Valdric) and whoever the story brought in (`arrive.story`, Gustav) are known from the story. Somebody who only
## stands in `residents` (a checkpoint, an arrival nobody has spoken to yet, Esma or Ilva before the first visit)
## is still a stranger: the board takes no notice from them.
func has_met(id: String) -> bool:
	if not residents.has(id):
		return false
	var spec: Dictionary = settler_spec(id)
	if bool(spec.get("founder", false)) or String((spec.get("arrive", {}) as Dictionary).get("story", "")) != "":
		return true
	return int((residents[id] as Dictionary).get("talked", -1)) >= 0


## The residents the player knows: only they may let notices hang on the board.
func met_residents() -> Dictionary:
	var met: Dictionary = {}
	for sid: String in residents:
		if settler_spec(sid).has("visitor"):
			continue ## the merchant comes and goes: he hangs no notices
		if has_met(sid):
			met[sid] = residents[sid]
	return met


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
		if String(arrive.get("story", "")) != "": ## the story brings them (Gustav: `add_story_resident`), no waiting for a piece
			continue
		if has_built(String(arrive.get("needs", ""))):
			_arrivals[sid] = float(_arrivals.get(sid, 0.0)) + delta
			if float(_arrivals[sid]) >= float(arrive.get("delay", 8.0)):
				_rpc_resident.rpc(sid, {"trust": 0, "talked": -1}, true)
		else:
			_arrivals.erase(sid)


## Host: the story lets `sid` move in (Gustav after the escort). `fresh` plays the walk-in; without it they are simply at home.
func add_story_resident(sid: String, fresh: bool = false) -> void:
	if not multiplayer.is_server() or residents.has(sid) or not settler_ids().has(sid):
		return
	_rpc_resident.rpc(sid, {"trust": 0, "talked": -1}, fresh)


@rpc("authority", "call_local", "reliable")
func _rpc_resident(sid: String, data: Dictionary, fresh: bool) -> void:
	residents[sid] = {"trust": int(data.get("trust", 0)), "talked": int(data.get("talked", -1))}
	_ensure_settler(sid, fresh)
	if fresh:
		resident_joined.emit(sid)
	changed.emit()


func _ensure_settler(sid: String, fresh: bool) -> void:
	if _settlers.has(sid) or not residents.has(sid) or bool(settler_spec(sid).get("away", false)): ## somebody `away` lives elsewhere (the witch in her tower): known and trusted, but no figure in the town
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
	if not residents.has(sid) and not bool(settler_spec(sid).get("away", false)): ## somebody who lives elsewhere is known from the first talk on
		return
	var data: Dictionary = (residents.get(sid, {"trust": 0, "talked": -1}) as Dictionary).duplicate()
	if int(data.talked) != TimeManager.day:
		data.talked = TimeManager.day
		data.trust = mini(int(data.trust) + 10, 100)
		_rpc_resident.rpc(sid, data, false)


## Host, every game hour: residents with a trade work for the town while they are at their place.
func _hour_tick() -> void:
	_burn_lamps()
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

## The role of the building a recipe is made at (workshop: craft, smithy: smith).
func _recipe_role(recipe: Dictionary) -> String:
	if recipe.has("role"): ## a bench that is no piece of the town (the witch's jewellery bench)
		return String(recipe.role)
	return String(TownRules.piece(String(recipe.get("station", "workshop"))).get("role", "craft"))


## Who works on / makes this commission.
func maker_of(order: Dictionary) -> String:
	if order.has("m"):
		return String(order.m)
	return String((recipes().get(String(order.r), {}) as Dictionary).get("npc", "gustav"))


## A refinement is a commission of its own kind (the weapon waits on the anvil, the result is decided).
static func is_refine(order: Dictionary) -> bool:
	return String(order.get("k", "")) == "refine"


## A commission as a clean dictionary (after a network hop or a JSON file).
static func _clean_order(e: Dictionary) -> Dictionary:
	var out: Dictionary = {"r": String(e.r), "left": float(e.left), "total": float(e.total), "done": bool(e.done)}
	if is_refine(e):
		out["k"] = "refine"
		out["m"] = String(e.get("m", RefineRules.maker()))
		out["w"] = SaveGame._stack(e.get("w", {}))
		out["to"] = int(e.get("to", 1))
		out["ok"] = bool(e.get("ok", false))
	return out


func orders_of(maker: String) -> int:
	var n: int = 0
	for order: Variant in orders:
		n += 1 if maker_of(order as Dictionary) == maker else 0
	return n


## What stops this commission right now ("" = nothing).
func order_block(recipe_id: String, player: Player) -> String:
	var recipe: Dictionary = recipes().get(recipe_id, {}) as Dictionary
	if recipe.is_empty() or String(recipe.get("by", "self")) != "npc":
		return "UNBEKANNT"
	var reason: String = recipe_block(recipe_id, player)
	if reason != "":
		return reason
	if orders_of(String(recipe.get("npc", "gustav"))) >= MAX_ORDERS:
		return "DIE WARTELISTE IST VOLL"
	return ""


## Seconds of work still ahead of an order (everything before it counts too), for the "ready in" text.
func order_wait(index: int) -> float:
	var total: float = 0.0
	var maker: String = maker_of(orders[index] as Dictionary)
	for i: int in mini(index + 1, orders.size()):
		if not bool((orders[i] as Dictionary).done) and maker_of(orders[i] as Dictionary) == maker:
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
	if player == null or not _near_role(player, _recipe_role(recipes().get(recipe_id, {}) as Dictionary), 150.0):
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
	if index < 0 or index >= orders.size():
		return
	var made: Dictionary = recipes().get(String((orders[index] as Dictionary).r), {}) as Dictionary
	if is_refine(orders[index] as Dictionary):
		made = {"station": RefineRules.station()}
	if player == null or not _near_role(player, _recipe_role(made), 150.0):
		_tell(peer, "ZU WEIT VON DER WERKBANK", false)
		return
	if not bool((orders[index] as Dictionary).done):
		_tell(peer, "NOCH NICHT FERTIG", false)
		return
	var recipe: Dictionary = recipes().get(String((orders[index] as Dictionary).r), {}) as Dictionary
	if is_refine(orders[index] as Dictionary):
		_collect_refine(index, player, peer)
		return
	orders.remove_at(index)
	_give_outputs(recipe, player)
	_sync_stock()
	_rpc_orders.rpc(orders.duplicate(true))
	_tell(peer, "%s ABGEHOLT" % String(recipe.get("name", "?")), true)


# ---------- refinement (docs/refinement_konzept.md): the weapon goes onto Torben's anvil, the result is rolled at once and kept ----------

## What stops refining this weapon right now ("" = nothing).
func refine_block(stack: Dictionary, player: Player, by: String = "") -> String:
	if not RefineRules.is_refinable(stack):
		return "DAS LÄSST SICH NICHT VERFEINERN"
	if not RefineRules.can_refine(stack):
		return "HÖHER GEHT ES NICHT"
	var target: int = RefineRules.next_level(stack)
	var maker: String = by if by != "" else RefineRules.maker()
	if trust_of(maker) < RefineRules.trust_needed(target):
		return "%s TRAUT DIR NOCH NICHT" % String(settler_spec(maker).get("name", maker))
	var missing: String = missing_text(RefineRules.materials(stack, target), player)
	if missing != "":
		return missing
	if player.progress.copper < RefineRules.copper(stack, target):
		return "ZU WENIG GELD"
	return ""


## `shop_id`: whose shop it is asked at ("" = the smithy; the witch refines too).
func request_refine(kind: String, ref: Variant, shop_id: String = "") -> void:
	if multiplayer.is_server():
		_host_refine(kind, ref, multiplayer.get_unique_id(), shop_id)
	else:
		_rpc_refine.rpc_id(1, kind, ref, shop_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_refine(kind: String, ref: Variant, shop_id: String = "") -> void:
	if multiplayer.is_server():
		_host_refine(kind, ref, multiplayer.get_remote_sender_id(), shop_id)


func _host_refine(kind: String, ref: Variant, peer: int, shop_id: String = "") -> void:
	var player: Player = player_of(peer)
	var at: Dictionary = shop(shop_id) if shop_id != "" else {}
	var by: String = String(at.get("npc", ""))
	var role: String = String(at.get("role", TownRules.piece(RefineRules.station()).get("role", "smith")))
	if player == null or not _near_role(player, role, float(at.get("reach", 150.0))):
		_tell(peer, "ZU WEIT VON DER SCHMIEDE", false)
		return
	var stack: Dictionary = player.inventory.stack_at(kind, ref) if kind in ["inv", "equip"] and player.inventory.slot_exists(kind, ref) else {}
	if stack.is_empty():
		return
	var reason: String = refine_block(stack, player, by)
	if reason != "":
		_tell(peer, reason, false)
		return
	if kind == "equip" and not player.inventory.has_room(String(stack.id)):
		_tell(peer, "KEIN PLATZ IM RUCKSACK", false)
		return
	var target: int = RefineRules.next_level(stack)
	_take_inputs({"in": RefineRules.materials(stack, target)}, player)
	player.progress.award(-RefineRules.copper(stack, target), 0)
	var weapon: Dictionary = player.inventory.take_stack(kind, ref)
	## Refining is instant: the result is rolled now and the weapon goes straight back into the bag.
	_deliver_refine(weapon, target, RefineRules.roll(weapon, target, randi() if debug_refine_seed < 0 else debug_refine_seed), player, peer)
	_sync_stock()


@rpc("authority", "call_remote", "reliable")
func _rpc_refine_done(before: Dictionary, after: Dictionary, success: bool, refund: Dictionary) -> void:
	refine_done.emit(SaveGame._stack(before), SaveGame._stack(after), success, refund)


## Level (1..15) the weapon on the anvil is meant to reach, 0 when `maker` has no refinement to work on: Torben's sparks fly the stronger the higher it is.
func refine_heat(maker: String) -> int:
	for entry: Variant in orders:
		var order: Dictionary = entry as Dictionary
		if is_refine(order) and maker_of(order) == maker and not bool(order.done):
			return int(order.to)
	return 0


## Host: a refinement still lying on the anvil (older saves, from when it took work time) goes back to its owner.
func _collect_refine(index: int, player: Player, peer: int) -> void:
	var order: Dictionary = orders[index] as Dictionary
	orders.remove_at(index)
	if not _deliver_refine(order.w as Dictionary, int(order.to), bool(order.ok), player, peer):
		orders.insert(index, order) ## no room in the bag: the weapon stays on the anvil
		_tell(peer, "KEIN PLATZ IM RUCKSACK", false)
		return
	_sync_stock()
	_rpc_orders.rpc(orders.duplicate(true))


## Host: the refined piece goes into the bag, with what a failed attempt returns. The notice tells how it went.
## False (nothing changed) when the bag has no room for the weapon.
func _deliver_refine(before: Dictionary, target: int, success: bool, player: Player, peer: int) -> bool:
	var after: Dictionary = RefineRules.result(before, success)
	if player.inventory.give(String(after.id), 1, Items.extras(after)) > 0:
		return false
	var returned: Dictionary = {} if success else RefineRules.refund(before, target)
	for item: String in returned:
		var left: int = player.inventory.give(item, int(returned[item]))
		if left > 0:
			_add_stock(item, left)
	if peer == multiplayer.get_unique_id():
		refine_done.emit(before, after, success, returned)
	else:
		_rpc_refine_done.rpc_id(peer, before, after, success, returned)
	if success:
		_tell(peer, Items.title(after).to_upper(), true)
	else:
		_tell(peer, "MISSLUNGEN, DIE GLUT STEIGT (%d)" % RefineRules.pity(after), false)
	if player.quests != null:
		player.quests.set_flag("refined_%s" % ("ok" if success else "failed"))
	return true


@rpc("authority", "call_local", "reliable")
func _rpc_orders(list: Array) -> void:
	var incoming: Array = list.duplicate(true) ## call_local hands over the host's own array: copy before it is cleared
	orders.clear()
	for entry: Variant in incoming:
		var e: Dictionary = entry as Dictionary
		orders.append(_clean_order(e))
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
			if bool(order.done) or maker_of(order) != sid:
				continue
			order.left = float(order.left) - delta
			moved = true
			if float(order.left) <= 0.0:
				order.left = 0.0
				order.done = true
				finished = true
				_rpc_order_ready.rpc(Items.title(order.w as Dictionary) if is_refine(order) else String(recipe.get("name", "?")), sid)
			break
	_order_sync -= delta
	if finished or (moved and _order_sync <= 0.0):
		_order_sync = 1.0
		_rpc_orders.rpc(orders.duplicate(true))


# ---------- alchemy: Esma brews potions (docs/alchemie_konzept.md, AlchemyRules) ----------

## What stops `player` from having this potion brewed by `maker` now ("" = nothing): the brewer's trust, the tier below, the ingredients in the bag.
func brew_block(type: String, level: int, player: Player, maker: String) -> String:
	var why: String = AlchemyRules.unlock_block(type, level, trust_of(maker), brewed, String(settler_spec(maker).get("name", maker)))
	if why != "":
		return why
	var cond: String = AlchemyRules.condition_block(type, count_of("smithy") > 0, TimeManager.dew_amount(), TimeManager.night_amount())
	if cond != "":
		return cond ## the special potions have their own way: the forge's heat, the morning dew, the night
	var need: Dictionary = AlchemyRules.ingredients(type, level)
	for item: String in need:
		if player.inventory.count_item(item) < int(need[item]):
			return "ES FEHLT %s" % String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()
	return ""


## Potions one brew gives right now (the full moon at night adds some).
func brew_yield(type: String, level: int) -> int:
	return AlchemyRules.brew_yield(type, level, TimeManager.moon_phase(), TimeManager.night_amount())


func request_brew(type: String, level: int, shop_id: String) -> void:
	if multiplayer.is_server():
		_host_brew(type, level, shop_id, multiplayer.get_unique_id())
	else:
		_rpc_brew.rpc_id(1, type, level, shop_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_brew(type: String, level: int, shop_id: String) -> void:
	if multiplayer.is_server():
		_host_brew(type, level, shop_id, multiplayer.get_remote_sender_id())


## Host: brewing is instant like refining: the ingredients (from the bag only: she brings them to Esma) leave, the potions go into the bag
## (what does not fit goes to the town's stock), the count of this tier rises.
func _host_brew(type: String, level: int, shop_id: String, peer: int) -> void:
	var player: Player = player_of(peer)
	var at: Dictionary = shop(shop_id)
	var maker: String = String(at.get("npc", ""))
	if player == null or at.is_empty() or not _near_role(player, String(at.get("role", "witch")), float(at.get("reach", 150.0))):
		_tell(peer, "ZU WEIT VOM KESSEL", false)
		return
	var reason: String = brew_block(type, level, player, maker)
	if reason != "":
		_tell(peer, reason, false)
		return
	var need: Dictionary = AlchemyRules.ingredients(type, level)
	for item: String in need:
		player.inventory.remove_item(item, int(need[item]))
	var moon: bool = AlchemyRules.moon_extra(TimeManager.moon_phase(), TimeManager.night_amount()) > 0
	var count: int = brew_yield(type, level)
	var left: int = player.inventory.give(AlchemyRules.item_id(type, level), count)
	player.inventory.changed.emit()
	if left > 0:
		_add_stock(AlchemyRules.item_id(type, level), left)
		_sync_stock()
	var brew_key: String = AlchemyRules.key(type, level)
	brewed[brew_key] = int(brewed.get(brew_key, 0)) + 1
	_rpc_brewed.rpc(brewed.duplicate())
	if peer == multiplayer.get_unique_id():
		brew_done.emit(type, level, count, moon)
	else:
		_rpc_brew_done.rpc_id(peer, type, level, count, moon)
	if left > 0:
		_tell(peer, "KEIN PLATZ: %d IM LAGER DER STADT" % left, false)
	if player.quests != null:
		player.quests.set_flag("brewed_%s" % type)


@rpc("authority", "call_local", "reliable")
func _rpc_brewed(counts: Dictionary) -> void:
	brewed = counts.duplicate()
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_brew_done(type: String, level: int, count: int, moon: bool) -> void:
	brew_done.emit(type, level, count, moon)


## Esma's first lesson: the asking player gets `vials` empty vials, once per world. True on the host when it was given.
func request_alchemy_gift(vials: int = 5) -> void:
	if multiplayer.is_server():
		_host_alchemy_gift(vials, multiplayer.get_unique_id())
	else:
		_rpc_alchemy_gift.rpc_id(1, vials)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_alchemy_gift(vials: int) -> void:
	if multiplayer.is_server():
		_host_alchemy_gift(vials, multiplayer.get_remote_sender_id())


func _host_alchemy_gift(vials: int, peer: int) -> void:
	var player: Player = player_of(peer)
	if player == null or alchemy_gift:
		return
	alchemy_gift = true
	var left: int = player.inventory.give(String(AlchemyRules.data().get("vial", "vial_empty")), clampi(vials, 0, 10))
	if left > 0:
		_add_stock(String(AlchemyRules.data().get("vial", "vial_empty")), left)
		_sync_stock()
	_tell(peer, "%d LEERE PHIOLEN" % clampi(vials, 0, 10), true)


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
		var sold: int = mini(amount, player.inventory.count_plain(item)) ## a refined weapon is not sold by the piece
		if sold <= 0:
			_tell(peer, "DU HAST KEIN %s" % item_name, false)
			return
		player.inventory.remove_item(item, sold)
		player.progress.award(price * sold, 0)
		_tell(peer, "%d X %s VERKAUFT" % [sold, item_name], true)



## The lake witch's SCHLIFF (docs/seehexe_konzept.md 5, CrystalRules): three equal stones + the tier's material + copper become one stone a tier higher, at once,
## never a failure. The host checks the reach of her room, trust, the stones, the material and the purse.
func request_grind(shop_id: String, item: String) -> void:
	if multiplayer.is_server():
		_host_grind(shop_id, item, multiplayer.get_unique_id())
	else:
		_rpc_grind.rpc_id(1, shop_id, item)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_grind(shop_id: String, item: String) -> void:
	if multiplayer.is_server():
		_host_grind(shop_id, item, multiplayer.get_remote_sender_id())


func _host_grind(shop_id: String, item: String, peer: int) -> void:
	var player: Player = player_of(peer)
	var def: Dictionary = shop(shop_id)
	if player == null or def.is_empty() or not def.has("grind"):
		return
	if not _near_role(player, String(def.get("role", "")), float(def.get("reach", 150.0))):
		_tell(peer, "ZU WEIT WEG", false)
		return
	var grind: Dictionary = def.grind as Dictionary
	var c: Dictionary = CrystalRules.cost(grind, item)
	var have: Dictionary = {item: player.inventory.count_plain(item)}
	for need: String in c.get("in", {}) as Dictionary:
		have[need] = player.inventory.count_plain(need)
	var why: String = CrystalRules.block(grind, item, have, player.progress.copper, trust_of(String(def.get("npc", ""))))
	if why != "":
		_tell(peer, why, false)
		return
	player.inventory.remove_item(item, int(c.count))
	for need: String in c.in as Dictionary:
		player.inventory.remove_item(need, int((c.in as Dictionary)[need]))
	player.progress.award(-int(c.copper), 0)
	var left: int = player.inventory.give(String(c.out), 1)
	if left > 0:
		_add_stock(String(c.out), left)
	_tell(peer, "%s GESCHLIFFEN" % String(DataRegistry.get_entry("items", String(c.out)).get("name", c.out)).to_upper(), true)


## LÄUTERN (docs/seehexe_konzept.md 14): Ilva washes `amount` raw stones `raw` in the lake (free: the fee is 0); each gives the stone it hid since it was found (`InventoryComponent.take_hidden`).
func request_refresh(shop_id: String, raw: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_refresh(shop_id, raw, amount, multiplayer.get_unique_id())
	else:
		_rpc_refresh.rpc_id(1, shop_id, raw, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_refresh(shop_id: String, raw: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_refresh(shop_id, raw, amount, multiplayer.get_remote_sender_id())


func _host_refresh(shop_id: String, raw: String, amount: int, peer: int) -> void:
	var player: Player = player_of(peer)
	var def: Dictionary = shop(shop_id)
	if player == null or def.is_empty() or not def.has("refresh") or amount > 99:
		return
	if not _near_role(player, String(def.get("role", "")), float(def.get("reach", 150.0))):
		_tell(peer, "ZU WEIT WEG", false)
		return
	var refresh: Dictionary = def.refresh as Dictionary
	var why: String = CrystalRules.refresh_block(refresh, raw, amount, player.inventory.count_item(raw), player.progress.copper, trust_of(String(def.get("npc", ""))))
	if why != "":
		_tell(peer, why, false)
		return
	var stones: Array[String] = player.inventory.take_hidden(raw, amount)
	if stones.size() != amount:
		return
	player.progress.award(-int((refresh.fee as Dictionary)[raw]) * amount, 0)
	var stocked: int = 0
	for stone: String in stones:
		var left: int = player.inventory.give(stone, 1)
		if left > 0:
			_add_stock(stone, left)
			stocked += left
	if stocked > 0:
		_sync_stock()
		_tell(peer, "KEIN PLATZ: %d IM LAGER DER STADT" % stocked, false)
	if peer == multiplayer.get_unique_id():
		refresh_done.emit(raw, stones)
	else:
		_rpc_refresh_done.rpc_id(peer, raw, stones)


@rpc("authority", "call_remote", "reliable")
func _rpc_refresh_done(raw: String, stones: Array) -> void:
	refresh_done.emit(raw, stones)


## The DEV tab of a shop (its dev block: kinds + items; to be removed later): hands the item out for free, host-checked like a trade.
func request_dev_give(shop_id: String, item: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_dev_give(shop_id, item, amount, multiplayer.get_unique_id())
	else:
		_rpc_dev_give.rpc_id(1, shop_id, item, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_dev_give(shop_id: String, item: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_dev_give(shop_id, item, amount, multiplayer.get_remote_sender_id())


func _host_dev_give(shop_id: String, item: String, amount: int, peer: int) -> void:
	var player: Player = player_of(peer)
	var def: Dictionary = shop(shop_id)
	if player == null or not def.has("dev") or amount < 1 or amount > 99 or not CrystalRules.dev_allowed(def.dev as Dictionary, item):
		return
	var left: int = player.inventory.give(item, amount)
	if left >= amount:
		_tell(peer, "KEIN PLATZ IM RUCKSACK", false)
		return
	_tell(peer, "%d X %s" % [amount - left, String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()], true)


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
	if player == null or recipe.is_empty() or not _near_role(player, _recipe_role(recipe), 150.0):
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
	if recipe.has("unlocks"):
		unlock(String(recipe.unlocks)) ## the first hoe or can opens the fields for the whole town
	if player.quests != null: ## story hook: the quest steps ask for "crafted_<recipe>" (solo / host player owns the quests)
		player.quests.set_flag("crafted_" + recipe_id)
		if recipe_id == "pickaxe_basic" and not player.quests.has_flag("crafted_pickaxe"):
			player.quests.set_flag("crafted_pickaxe")
			var box: Node = get_tree().get_first_node_in_group("speech_box")
			if box != null and box.has_method("play"):
				box.call("play", "pickaxe_made") ## Gustav's remark at the first pickaxe
		if recipe_id == "iron_ingot" and not player.quests.has_flag("ingot_remarked"):
			player.quests.set_flag("ingot_remarked")
			var box2: Node = get_tree().get_first_node_in_group("speech_box")
			if box2 != null and box2.has_method("play"):
				box2.call("play", "ingot_made")


## Host: the town learns something (`unlocks`), everybody hears it once. "farming" makes the fields buildable (docs/farming.md).
func unlock(what: String) -> void:
	if not multiplayer.is_server() or unlocks.has(what):
		return
	_rpc_unlock.rpc(what, true)


@rpc("authority", "call_local", "reliable")
func _rpc_unlock(what: String, announce: bool) -> void:
	if unlocks.has(what):
		return
	unlocks[what] = true
	changed.emit()
	if announce and what == String(FarmRules.config().get("unlock", "farming")):
		_announce("FELDER FREIGESCHALTET", "BAUMENÜ · ACKER")


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


## The town's colour and emblem (anyone may change them, the host tells everyone).
func request_look(color_index: int, emblem_index: int) -> void:
	if multiplayer.is_server():
		_rpc_look_state.rpc(color_index, emblem_index)
	else:
		_rpc_look.rpc_id(1, color_index, emblem_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_look(color_index: int, emblem_index: int) -> void:
	if multiplayer.is_server():
		_rpc_look_state.rpc(color_index, emblem_index)


@rpc("authority", "call_local", "reliable")
func _rpc_look_state(color_index: int, emblem_index: int) -> void:
	look_color = posmod(color_index, TownEmblems.COLORS.size())
	look_emblem = posmod(emblem_index, TownEmblems.GLYPHS.size())
	changed.emit()


## Walking in: the edge of the light ripples round her feet and every lamp in sight flares a moment.
func _greet_light(player: Player) -> void:
	TownConsecration.play(player.get_parent(), player.global_position, {"radius": 0.0, "reach": 46.0, "light_color": Color("78f4e6")})
	for id: int in _views:
		var view: TownStructure = _views[id] as TownStructure
		if is_instance_valid(view) and view.is_done() and view.position.distance_to(player.global_position) < 360.0:
			view.flare(0.3 + view.position.distance_to(player.global_position) / 400.0)


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


# ---------- care ----------

## Is this building looked after? A resident who lives there looks after it; a piece nobody is assigned to (the stockpile) is looked after as soon as anybody lives in the town.
## A building whose settler has not come yet is not (cobwebs, moss: `wear` entries with `track: "neglect"`).
func cared(id: int) -> bool:
	if not structures.has(id):
		return false
	var kind: String = String((structures[id] as Dictionary).p)
	var assigned: bool = false
	for sid: String in settler_ids():
		var spec: Dictionary = settler_spec(sid)
		if String(spec.get("home", "")) == kind and bool(spec.get("enabled", true)):
			assigned = true
			if residents.has(sid):
				return true
	return not assigned and population() > 0


# ---------- seats ----------

## The benches' places (`seats` of the piece) as nodes that exist on every peer for every finished bench.
func _sync_seats() -> void:
	var wanted: Dictionary = {}
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		if int(data.g) < PROGRESS_FULL:
			continue
		var list: Array = TownRules.piece(String(data.p)).get("seats", []) as Array
		for i: int in list.size():
			wanted["%d_%d" % [id, i]] = [id, i]
	for key: String in _seats.keys():
		if not wanted.has(key):
			(_seats[key] as BenchSeat).queue_free()
			_seats.erase(key)
	for key: String in wanted:
		if _seats.has(key):
			(_seats[key] as BenchSeat).refresh()
			continue
		var seat_id: int = int((wanted[key] as Array)[0])
		var seat: BenchSeat = SalonSeat.new() if bool(TownRules.piece(String((structures[seat_id] as Dictionary).p)).get("salon", false)) else BenchSeat.new() ## the salon's chair frames her up close
		_seat_root.add_child(seat)
		seat.setup(self, seat_id, int((wanted[key] as Array)[1]))
		_seats[key] = seat


func seat_nodes() -> Array[BenchSeat]:
	var out: Array[BenchSeat] = []
	for seat: Variant in _seats.values():
		out.append(seat as BenchSeat)
	return out


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
			var view: TownStructure = FarmField.new() if bool(TownRules.piece(String(data.p)).get("farm", false)) else TownStructure.new()
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
	_sync_seats()
	_last_level = level() if founded else -1
	changed.emit()


func build_mode() -> BuildMode:
	return _build


func _process(delta: float) -> void:
	_update_help()
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
	_watch_territory(delta)
	_wear_clock += delta
	if _wear_dirty and _wear_clock >= 1.0:
		_wear_clock = 0.0
		_update_wear()
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


func wear_at(pos: Vector2) -> float:
	return float(wear.get(TownWear.cell_of(pos), 0.0))


## Recomputes the trodden ground (only while somebody of this peer is near the town) and hands it to the ground shader and to the small plants.
func _update_wear() -> void:
	var near: bool = false
	for center: Vector2 in _view_centers():
		near = near or center.distance_to(self.center) < 1500.0
	if not near:
		return
	_wear_dirty = false
	wear = TownWear.compute(structures, paths, TimeManager.day)
	var origin: Vector2 = TownWear.origin_for(center)
	var img: Image = TownWear.field_image(wear, origin)
	if _wear_tex == null:
		_wear_tex = ImageTexture.create_from_image(img)
		RenderingServer.global_shader_parameter_set("g_town_wear", _wear_tex)
	else:
		_wear_tex.update(img)
	RenderingServer.global_shader_parameter_set("g_town_wear_rect", Vector4(origin.x, origin.y, TownWear.SIZE * TownWear.CELL, TownWear.SIZE * TownWear.CELL))
	for node: Node in get_tree().get_nodes_in_group("meadow_details"):
		(node as MeadowDetails).apply_wear(self)


## The local player enters the town's ground (not a room): its name comes once a day, quietly (docs/town_ausbau.md C19).
func _watch_territory(_delta: float) -> void:
	var player: Player = local_player()
	if player == null or Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position):
		return
	var depth: float = TownRules.light_depth(circles(), player.global_position)
	if not _inside and depth > 10.0:
		_inside = true
		var away: bool = _left_msec >= 0 and Time.get_ticks_msec() - _left_msec > 180000 ## three minutes out in the wild: the town greets her again
		if (_entered_day != TimeManager.day or away) and has_heart() and not player.story_lock and player.intro == null:
			_entered_day = TimeManager.day
			_left_msec = -1
			var people: int = population()
			town_banner({"title": town_name(), "sub": "%s · %d %s · TAG %d" % [level_label(), people, "EINWOHNER" if people != 1 else "EINWOHNERIN", TimeManager.day + 1], "sound": "town_motif"})
			_greet_light(player)
	elif _inside and depth < -20.0:
		_inside = false
		_left_msec = Time.get_ticks_msec()


# ---------- saving and joining ----------

func export_state(snapshot: bool = false) -> Dictionary:
	var out_structures: Dictionary = {}
	for id: int in structures:
		out_structures[str(id)] = (structures[id] as Dictionary).duplicate()
	var out_cleared: Array = []
	for cell: Vector2i in cleared:
		out_cleared.append([cell.x, cell.y])
	return {
		"version": STATE_VERSION, "founded": founded, "name": name_index, "look": [look_color, look_emblem], "center": [center.x, center.y], "day": founded_day,
		"next_id": next_id, "structures": out_structures, "stock_slots": box.slots.duplicate(true), "cleared": out_cleared, "residents": residents.duplicate(true), "paths": paths.duplicate(true), "orders": orders.duplicate(true),
		"fear": fear_on, "brewed": brewed.duplicate(), "alchemy_gift": alchemy_gift,
		"unlocks": unlocks.keys(), "farm": farm.export_state() if farm != null else {},
		"board": board.export_state(snapshot) if board != null else {},
		"caravan": caravan.export_state() if caravan != null else {},
	}


func import_state(data: Dictionary) -> void:
	structures.clear()
	box.import_slots([])
	cleared.clear()
	residents.clear()
	paths.clear()
	orders.clear()
	_progress.clear()
	unlocks.clear()
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
	fear_on = bool(data.get("fear", false))
	brewed.clear()
	var counts: Dictionary = data.get("brewed", {}) as Dictionary
	for brew_key: String in counts:
		brewed[brew_key] = int(counts[brew_key])
	alchemy_gift = bool(data.get("alchemy_gift", false))
	name_index = int(data.get("name", 0))
	var look: Array = data.get("look", [0, 0]) as Array
	look_color = int(look[0]) if look.size() > 1 else 0
	look_emblem = int(look[1]) if look.size() > 1 else 0
	var middle: Array = data.get("center", [0, 0]) as Array
	center = Vector2(float(middle[0]), float(middle[1]))
	founded_day = int(data.get("day", 0))
	next_id = int(data.get("next_id", 1))
	var saved: Dictionary = data.get("structures", {}) as Dictionary
	for key: String in saved:
		var entry: Dictionary = saved[key] as Dictionary
		structures[int(key)] = {"p": String(entry.p), "x": float(entry.x), "y": float(entry.y), "f": int(entry.get("f", 0)), "g": int(entry.get("g", PROGRESS_FULL)), "b": int(entry.get("b", founded_day))}
		if entry.get("u", null) is Dictionary:
			(structures[int(key)] as Dictionary).u = {"f": int((entry.u as Dictionary).get("f", 0)), "l": int((entry.u as Dictionary).get("l", 0))}
		if int((structures[int(key)] as Dictionary).g) < PROGRESS_FULL:
			_progress[int(key)] = float((structures[int(key)] as Dictionary).g)
	if data.has("stock_slots"):
		box.import_slots(data.get("stock_slots", []) as Array)
	else: ## an older save: item -> count
		var items: Dictionary = data.get("stock", {}) as Dictionary
		for item: String in items:
			box.add_item(item, int(items[item]))
	_refresh_stock()
	for cell: Variant in data.get("cleared", []) as Array:
		cleared[Vector2i(int((cell as Array)[0]), int((cell as Array)[1]))] = true
	for way: Variant in data.get("paths", []) as Array:
		var entry: Dictionary = way as Dictionary
		paths.append({"s": int(entry.s), "p": (entry.p as Array).duplicate(true), "d": int(entry.get("d", 1)), "e": int(entry.get("e", 0))})
	for entry: Variant in data.get("orders", []) as Array:
		var e: Dictionary = entry as Dictionary
		orders.append(_clean_order(e))
	var people: Dictionary = data.get("residents", {}) as Dictionary
	for sid: String in people:
		var entry: Dictionary = people[sid] as Dictionary
		residents[sid] = {"trust": int(entry.get("trust", 0)), "talked": int(entry.get("talked", -1))}
	for what: Variant in data.get("unlocks", []) as Array:
		unlocks[String(what)] = true
	if farm != null:
		farm.import_state(data.get("farm", {}) as Dictionary)
	if board != null:
		board.import_state(data.get("board", {}) as Dictionary)
	if caravan != null:
		caravan.import_state(data.get("caravan", {}) as Dictionary)
	_apply_all()


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(data: Dictionary) -> void:
	var was: bool = founded
	import_state(data)
	if founded and not was:
		town_founded.emit()
