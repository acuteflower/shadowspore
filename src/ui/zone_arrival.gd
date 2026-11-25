class_name ZoneArrival
extends CanvasLayer
## Arriving in the zone world (docs/v2_zonenwelt_atlas_konzept.md 7.1, step 5). Local and cosmetic, the local player only.
## * First entry into a zone: the big inscription at the top: the zone's name in gold at double size, its subtitle under it,
##   vines growing out of both sides, and beside it a small card on which the zone's outline is traced in ink within two
##   seconds, a gold point where she came in. Then the vines draw back and everything withers.
## * Coming back: only a slim line with the name for two seconds.
## * Places: entering one writes its name small under the clock; the first time with the stamp "ENTDECKT".
## Everything waits while a dialogue, the pause menu, a story scene or a fight holds the screen. What was seen is
## `ZoneDirector.seen` (saved with the zone world).

const LAYER: int = 21
const BIG_IN: float = 0.7
const BIG_TRACE: float = 2.0
const BIG_HOLD: float = 4.6
const BIG_OUT: float = 1.0
const SMALL_IN: float = 0.35
const SMALL_HOLD: float = 2.0
const SMALL_OUT: float = 0.5
const PLACE_HOLD: float = 3.2
const PLACE_OUT: float = 0.6
const STAMP_AT: float = 0.45
const FIGHT_RANGE: float = 220.0
const PLACE_TICK: float = 0.25
const CARD: Vector2 = Vector2(58.0, 46.0)
const PLACE_POS: Vector2 = Vector2(14.0, 66.0)
const GOLD: Color = Color("ffd27a")
const GOLD_DIM: Color = Color("b08a4a")
const LILAC: Color = Color(0.86, 0.80, 0.96)
const INK: Color = Color("0a0612")
const ROUTE: Color = Color("e3d3a4") ## the outline on the dark card: pale parchment ink
const VINE: Color = Color("1f3a33")
const VINE_LIGHT: Color = Color("5f9a76")
const STAMP: Color = Color("8a2a3c")
const STAMP_LIGHT: Color = Color("ffe0c8")

var director: ZoneDirector
var _canvas: Control
var _queue: Array[Dictionary] = [] ## pending zone inscriptions
var _now: Dictionary = {} ## {zone, big, entry (tile), age}
var _place: Dictionary = {} ## {id, name, first, age}
var _place_queue: Array[Dictionary] = []
var _here_place: StringName = &""
var _place_tick: float = 0.0
var _time: float = 0.0


func setup(p_director: ZoneDirector) -> void:
	director = p_director
	director.zone_changed.connect(_on_zone_changed)


func _exit_tree() -> void:
	HudNotices.release_big(self)


func _ready() -> void:
	name = "ZoneArrival"
	add_to_group("world_banners")
	layer = int((DataRegistry.table("hud").get("layers", {}) as Dictionary).get("notices", LAYER)) ## above the HUD and the banners
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)


## What is showing or waiting (tests): {"zone": id or "", "big": bool, "place": id or "", "stamp": bool, "queued": int,
## "waiting": ["zone:big|small", ...]}.
func state() -> Dictionary:
	return {
		"zone": String(_now.get("zone", "")), "big": bool(_now.get("big", false)),
		"place": String(_place.get("id", "")), "stamp": bool(_place.get("first", false)),
		"queued": _queue.size() + _place_queue.size(),
		"waiting": _queue.map(func(e: Dictionary) -> String: return "%s:%s" % [e.zone, "big" if bool(e.big) else "small"]),
	}


func _on_zone_changed(peer: int, zone_id: StringName) -> void:
	if peer != _local_peer() or director == null:
		return
	var zone: Atlas.Zone = director.atlas.zone(zone_id)
	if zone == null:
		return
	var first: bool = not director.seen_zone(zone_id)
	director.mark_zone(zone_id)
	var player: Node2D = _local_player()
	var entry: Vector2 = Atlas.tile_of(player.global_position) if player != null else zone.center()
	for i: int in range(_queue.size() - 1, -1, -1): ## a newer arrival replaces an older one still waiting
		if not bool(_queue[i].big):
			_queue.remove_at(i)
	_queue.append({"zone": zone_id, "big": first, "entry": entry, "age": 0.0})


func _process(delta: float) -> void:
	_time += delta
	if director == null:
		return
	_watch_place(delta)
	var blocked: bool = _blocked()
	if _now.is_empty() and not _queue.is_empty() and not blocked and HudNotices.claim_big(self): ## the top-centre stage is shared
		_now = _queue.pop_front()
		if bool(_now.big):
			_play("res://assets/audio/town/banner_unroll.wav", -10.0)
	if not _now.is_empty():
		var hold_end: float = (BIG_IN + BIG_HOLD) if bool(_now.big) else (SMALL_IN + SMALL_HOLD)
		var age: float = float(_now.age)
		if not (blocked and age > 0.2 and age < hold_end - 0.1): ## hold while something covers the screen
			_now.age = age + delta
		if float(_now.age) >= hold_end + (BIG_OUT if bool(_now.big) else SMALL_OUT):
			_now = {}
			HudNotices.release_big(self)
	if _place.is_empty() and not _place_queue.is_empty() and not blocked and (_now.is_empty() or not bool(_now.big)):
		_place = _place_queue.pop_front()
		var vine: Node = get_tree().get_first_node_in_group("place_vine") ## the clock's Ortsranke shows it (docs/hud_v2_konzept.md 3.A)
		_place.on_vine = vine != null and vine.is_visible_in_tree()
		if bool(_place.on_vine):
			vine.call("show_place", _place.id, String(_place.name), bool(_place.first))
	if not _place.is_empty():
		var p_age: float = float(_place.age)
		if not (blocked and p_age < PLACE_HOLD - 0.1):
			var before: float = p_age
			_place.age = p_age + delta
			if bool(_place.first) and before < STAMP_AT and float(_place.age) >= STAMP_AT and not bool(_place.get("on_vine", false)):
				_play("res://assets/audio/skills/reveal.wav", -12.0)
		if float(_place.age) >= PLACE_HOLD + PLACE_OUT:
			_place = {}
	_canvas.queue_redraw()


func _watch_place(delta: float) -> void:
	_place_tick -= delta
	if _place_tick > 0.0:
		return
	_place_tick = PLACE_TICK
	var player: Node2D = _local_player()
	if player == null:
		return
	var here: StringName = director.atlas.place_at(director.continent_id, player.global_position)
	if here == _here_place:
		return
	_here_place = here
	if here == &"":
		return
	var zone: Atlas.Zone = director.atlas.zone(director.atlas.zone_at(director.continent_id, player.global_position))
	if zone == null:
		return
	for place: Atlas.Place in zone.places:
		if place.id != here:
			continue
		var first: bool = not director.seen_place(here)
		director.mark_place(here)
		if String(_place.get("id", "")) == String(here):
			return
		_place_queue.clear()
		_place_queue.append({"id": here, "name": place.name, "first": first, "age": 0.0})
		return


func _blocked() -> bool:
	var tree: SceneTree = get_tree()
	if tree.paused or InputManager.ui_blocking:
		return true
	var box: Node = tree.get_first_node_in_group("dialogue")
	if box != null and box.has_method("is_active") and bool(box.call("is_active")):
		return true
	var player: Node2D = _local_player()
	if player == null:
		return false
	if bool(player.get("story_lock")):
		return true
	for node: Node in tree.get_nodes_in_group("predators"): ## a fight: shadow creatures close by (not wildlife)
		if node.get("enemy_id") == null or not (node is Node2D):
			continue
		if (node as Node2D).global_position.distance_to(player.global_position) > FIGHT_RANGE:
			continue
		var health: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current > 0.0:
			return true
	return false


func _local_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


func _local_player() -> Node2D:
	if director == null or director.players_root == null:
		return null
	return director.players_root.get_node_or_null(str(_local_peer())) as Node2D


func _play(path: String, db: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = load(path) as AudioStream
	player.volume_db = db
	player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# --- drawing --------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if InputManager.menu_open:
		return
	if not _now.is_empty():
		var zone: Atlas.Zone = director.atlas.zone(_now.zone as StringName)
		if zone != null:
			if bool(_now.big):
				_draw_big(zone, float(_now.age), _now.entry as Vector2)
			else:
				_draw_small(zone, float(_now.age))
	if not _place.is_empty() and not bool(_place.get("on_vine", false)):
		_draw_place(String(_place.name), bool(_place.first), float(_place.age))


## 0..1: in, held, out.
func _shown(age: float, t_in: float, hold: float, t_out: float) -> float:
	if age < t_in:
		var k: float = age / t_in
		return 1.0 - pow(1.0 - k, 3.0)
	var back: float = age - t_in - hold
	if back > 0.0:
		return 1.0 - clampf(back / t_out, 0.0, 1.0)
	return 1.0


func _draw_big(zone: Atlas.Zone, age: float, entry: Vector2) -> void:
	var shown: float = _shown(age, BIG_IN, BIG_HOLD, BIG_OUT)
	var mid: float = roundf(_canvas.size.x / 2.0)
	var title: String = zone.name
	var title_w: float = float(PixelText.width(title)) * 2.0
	var sub_w: float = float(PixelText.width(zone.subtitle))
	var block_w: float = maxf(title_w, sub_w)
	var gap: float = 14.0
	var total: float = block_w + gap + CARD.x
	var left: float = roundf(mid - total / 2.0)
	var text_mid: float = left + roundf(block_w / 2.0)
	var top: float = 20.0
	var typed: int = int(ceilf(float(title.length()) * clampf(age / (BIG_IN * 0.9), 0.0, 1.0)))
	var fade: float = clampf(shown * 1.6, 0.0, 1.0)
	_text(title.substr(0, typed), text_mid - roundf(title_w / 2.0), top, 2.0, Color(GOLD, fade))
	if zone.subtitle != "":
		var sub_fade: float = clampf((age - BIG_IN * 0.6) / 0.5, 0.0, 1.0) * fade
		_text(zone.subtitle, text_mid - roundf(sub_w / 2.0), top + 16.0, 1.0, Color(LILAC, sub_fade))
	var reach: float = (block_w / 2.0 + 30.0) * shown
	_vine(Vector2(text_mid, top + 26.0), -1.0, reach, fade, 3)
	_vine(Vector2(text_mid, top + 26.0), 1.0, reach, fade, 7)
	var card: Rect2 = Rect2(Vector2(left + block_w + gap, top - 6.0), CARD)
	var card_fade: float = clampf((age - 0.25) / 0.4, 0.0, 1.0) * shown
	if card_fade > 0.0:
		VineStyle.paper(_canvas, card, card_fade, 0.0, 41)
		var trace: float = clampf((age - 0.4) / BIG_TRACE, 0.0, 1.0)
		_trace_outline(zone, card.grow(-6.0), trace, card_fade, entry, age)


func _draw_small(zone: Atlas.Zone, age: float) -> void:
	var shown: float = _shown(age, SMALL_IN, SMALL_HOLD, SMALL_OUT)
	var w: float = float(PixelText.width(zone.name))
	var mid: float = roundf(_canvas.size.x / 2.0)
	var top: float = 22.0 - roundf((1.0 - shown) * 4.0)
	_text(zone.name, mid - roundf(w / 2.0), top, 1.0, Color(GOLD, shown))
	var reach: float = (w / 2.0 + 14.0) * shown
	_vine(Vector2(mid, top + 8.0), -1.0, reach, shown, 11)
	_vine(Vector2(mid, top + 8.0), 1.0, reach, shown, 13)


func _draw_place(place_name: String, first: bool, age: float) -> void:
	var shown: float = _shown(age, 0.3, PLACE_HOLD - 0.3, PLACE_OUT)
	var at: Vector2 = PLACE_POS + Vector2(roundf((1.0 - shown) * -8.0), 0.0)
	VineStyle.leaf(_canvas, at + Vector2(0.0, 3.0), 1, 1, 3, Color(VINE, shown), Color(VINE_LIGHT, shown))
	_text(place_name, at.x + 7.0, at.y, 1.0, Color(GOLD.lerp(Color.WHITE, 0.25), shown))
	if not first or age < STAMP_AT:
		return
	var stamp_age: float = age - STAMP_AT
	var size: float = 2.0 if stamp_age < 0.07 else 1.0 ## lands with a thump: one frame big, then its size
	var word: String = "ENTDECKT"
	var w: float = float(PixelText.width(word)) * size
	var box_pos: Vector2 = Vector2(at.x + 7.0 + float(PixelText.width(place_name)) + 6.0, at.y - 3.0 - (size - 1.0) * 3.0).round()
	var box: Rect2 = Rect2(box_pos, Vector2(w + 6.0 * size, 7.0 * size + 4.0))
	_canvas.draw_rect(box.grow(1.0), Color(INK, shown * 0.9))
	_canvas.draw_rect(box, Color(STAMP, shown))
	_canvas.draw_rect(Rect2(box.position, Vector2(box.size.x, 1.0)), Color(STAMP.lightened(0.25), shown))
	_text(word, box.position.x + 3.0 * size, box.position.y + 2.0, size, Color(STAMP_LIGHT, shown))


func _text(text: String, x: float, y: float, scale: float, color: Color) -> void:
	if text == "" or color.a <= 0.01:
		return
	_canvas.draw_set_transform(Vector2(roundf(x), roundf(y)), 0.0, Vector2(scale, scale))
	PixelText.draw(_canvas, text, Vector2i.ZERO, color, Color(INK, color.a))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A thin vine growing sideways from `root` with a gentle wave and leaves every few pixels; `reach` = its length now.
func _vine(root: Vector2, side: float, reach: float, fade: float, salt: int) -> void:
	if reach < 1.0:
		return
	var steps: int = int(reach)
	var last: Vector2 = root
	for i: int in steps:
		var x: float = float(i)
		var p: Vector2 = (root + Vector2(side * x, roundf(sin(x * 0.18 + float(salt)) * 1.4))).round()
		var tip: float = clampf((reach - x) / 6.0, 0.0, 1.0)
		_canvas.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color(INK, fade * 0.7)) ## a hair of shadow under it
		_canvas.draw_rect(Rect2(p, Vector2.ONE), Color(VINE.lerp(VINE_LIGHT, 0.35 + 0.5 * tip), fade))
		if i % 2 == 0:
			_canvas.draw_rect(Rect2(p - Vector2(0.0, 1.0), Vector2.ONE), Color(VINE_LIGHT, fade * 0.55))
		if i % 9 == 4 and reach - x > 3.0:
			var up: int = 1 if VineStyle.rand(salt * 31 + i) > 0.5 else -1
			VineStyle.leaf(_canvas, p, int(side), up, 3, Color(VINE, fade), Color(VINE_LIGHT, fade))
		last = p
	VineStyle.glow(_canvas, last + Vector2(0.5, 0.5), 3.0, Color(GOLD, 0.6), 0.5 * fade)


## The zone's outline fitted into `box`, traced in ink up to `trace` (0..1) of its length, with a gold point at the
## entry tile once the line has passed it.
func _trace_outline(zone: Atlas.Zone, box: Rect2, trace: float, fade: float, entry: Vector2, age: float) -> void:
	var poly: PackedVector2Array = zone.footprint
	if poly.size() < 3:
		return
	var k: float = minf(box.size.x / zone.bbox.size.x, box.size.y / zone.bbox.size.y)
	var size: Vector2 = zone.bbox.size * k
	var shift: Vector2 = box.position + (box.size - size) / 2.0
	var total: float = 0.0
	for i: int in poly.size():
		total += poly[i].distance_to(poly[(i + 1) % poly.size()])
	var budget: float = total * trace
	var last_px: Vector2 = Vector2.INF
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var seg: float = a.distance_to(b)
		if budget <= 0.0:
			break
		var t_end: float = minf(1.0, budget / maxf(seg, 0.001))
		budget -= seg
		var pa: Vector2 = shift + (a - zone.bbox.position) * k
		var pb: Vector2 = shift + (a.lerp(b, t_end) - zone.bbox.position) * k
		var n: int = maxi(1, int(ceilf(pa.distance_to(pb))))
		for s: int in n + 1:
			var p: Vector2 = pa.lerp(pb, float(s) / float(n)).floor()
			if p != last_px:
				_canvas.draw_rect(Rect2(p, Vector2.ONE), Color(ROUTE, fade))
				last_px = p
	if trace >= 1.0 or trace > 0.6:
		var dot: Vector2 = (shift + (entry - zone.bbox.position) * k).floor()
		var pulse: float = 0.6 + 0.4 * sin(age * 6.0)
		VineStyle.glow(_canvas, dot + Vector2(0.5, 0.5), 4.0, Color(GOLD, 0.7), pulse * fade)
		_canvas.draw_rect(Rect2(dot - Vector2.ONE, Vector2(3.0, 3.0)), Color(INK, fade))
		_canvas.draw_rect(Rect2(dot, Vector2.ONE), Color(GOLD, fade))
