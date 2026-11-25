class_name WayVine
extends Control
## Wegranke (docs/hud_v2_konzept.md 4.4, step 4): a thin compass twig at the top centre. It spans half a turn around the
## way Ellie walks (the middle is straight ahead, the ends are left and right of her), the four quarters sit on it as
## small knots (N O S W) and marks wander along it by their bearing:
## * the quest goal (gold bud, open when near), or, when the goal lies in another zone, the next threshold on the way
##   there (teal gate; a shut one grey with a seal) and the goal dim behind it (`QuestRoute`, the same plan the quest
##   vine writes);
## * home (a little hut, only at night), the zone's awake waystone (a statuette), the player's own pins of the zone and a
##   friend's map call (a beam, 8 s).
## A mark behind her clings to the nearer end as a half arrow. No distances here: those are in the quest vine. Shows
## while she explores; the director takes it away in fights, bosses, dialogues and idle (data/hud.json).

const SPAN: float = 160.0
const TOP: float = 8.0 ## the twig's row
const HALF_TURN: float = PI * 0.5 ## from the middle to an end
const TICK: float = 0.25
const GOLD: Color = Color("ffd27a")
const TEAL: Color = Color("7fe0c8")
const GREY: Color = Color("8f8aa0")
const SEAL: Color = Color("8a2a3c")
const HOME: Color = Color("f0c890")
const STONE: Color = Color("c9b8f0")
const PIN: Color = Color("e6e0ff")
const BEAM: Color = Color("9fd8ff")
const QUARTERS: Array[String] = ["N", "O", "S", "W"]

var player: Node2D
var _heading: float = 0.0 ## bearing she walks, 0 = north (screen up), clockwise
var _last_pos: Vector2 = Vector2.INF
var _marks: Array[Dictionary] = [] ## {kind, pos (world px), open, near}
var _tick: float = 0.0
var _time: float = 0.0
var _pings: Array[Dictionary] = [] ## {pos, age}


func bind(p_player: Node2D) -> void:
	player = p_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coop: Node = get_tree().get_first_node_in_group("zone_coop")
	if coop != null and coop.has_signal("ping_received"):
		coop.connect("ping_received", _on_ping)


## The director asks: something to point at.
func hud_busy() -> bool:
	return not _marks.is_empty()


## What the twig shows (tests): kinds of the marks and the x of each.
func marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mark: Dictionary in _marks:
		out.append({"kind": String(mark.kind), "x": _x_of(mark.pos as Vector2), "open": bool(mark.get("open", true))})
	return out


func _on_ping(_peer: int, world_pos: Vector2, _zone: StringName) -> void:
	_pings.append({"pos": world_pos, "age": 0.0})


func _process(delta: float) -> void:
	_time += delta
	if player == null or not is_instance_valid(player):
		return
	var pos: Vector2 = player.global_position
	if _last_pos.is_finite():
		var step: Vector2 = pos - _last_pos
		if step.length_squared() > 0.04:
			var target: float = atan2(step.x, -step.y)
			_heading = lerp_angle(_heading, target, clampf(delta * 5.0, 0.0, 1.0))
	_last_pos = pos
	for i: int in range(_pings.size() - 1, -1, -1):
		_pings[i].age = float(_pings[i].age) + delta
		if float(_pings[i].age) > 8.0:
			_pings.remove_at(i)
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_collect()
	if modulate.a > 0.01:
		queue_redraw()


func _collect() -> void:
	_marks.clear()
	var tree: SceneTree = get_tree()
	var world: Node = tree.get_first_node_in_group("world")
	var director: ZoneDirector = world.call("director") as ZoneDirector if world != null and world.has_method("director") else null
	var here: Vector2 = Interiors.outer(tree, player.global_position)
	var hud: Node = get_parent()
	var quest: Node = hud.get_node_or_null("QuestVine") if hud != null else null
	if quest != null:
		var actor: Node2D = quest.get("_target_actor") as Node2D
		var target: Vector2 = actor.global_position if actor != null and is_instance_valid(actor) and actor.is_inside_tree() else quest.get("_target") as Vector2
		if target.is_finite():
			var route: Dictionary = quest.call("route") as Dictionary
			var next: Dictionary = route.get("next", {}) as Dictionary
			if not bool(route.get("same", true)) and not next.is_empty():
				_marks.append({"kind": "gate", "pos": Atlas.px_of(next.pos as Vector2), "open": bool(next.get("open", true))})
				_marks.append({"kind": "quest", "pos": Interiors.outer(tree, target), "near": false, "dim": true})
			else:
				var outer: Vector2 = Interiors.outer(tree, target)
				_marks.append({"kind": "quest", "pos": outer, "near": outer.distance_to(here) < 320.0})
	if TimeManager.night_amount() > 0.3:
		var town: TownManager = tree.get_first_node_in_group("town") as TownManager
		if town != null and town.founded:
			_marks.append({"kind": "home", "pos": town.respawn_point()})
	if director != null and director.atlas != null:
		var zone_id: StringName = director.atlas.zone_at(director.continent_id, here)
		var stones: Waystones = Waystones.of(tree)
		if stones != null and zone_id != &"":
			var spec: Dictionary = stones.awake_waystone_in_zone(zone_id)
			if not spec.is_empty():
				var at: Vector2 = stones.arrival_position(String(spec.get("id", "")))
				if at.is_finite() and at != Vector2.ZERO:
					_marks.append({"kind": "stone", "pos": at})
		var map: Node = hud.get_node_or_null("MapWindow") if hud != null else null
		var markers: MapMarkers = map.get("_v2_markers") as MapMarkers if map != null else null
		if markers != null and zone_id != &"":
			for pin: Dictionary in markers.pins_for_zone(zone_id):
				var p: Variant = pin.get("pos")
				if p is Vector2:
					_marks.append({"kind": "pin", "pos": Atlas.px_of(p as Vector2)})
	for ping: Dictionary in _pings:
		_marks.append({"kind": "ping", "pos": ping.pos, "age": ping.age})


## Bearing of a world point from her, 0 = north, clockwise.
func _bearing(pos: Vector2) -> float:
	var v: Vector2 = pos - Interiors.outer(get_tree(), player.global_position)
	return atan2(v.x, -v.y)


## x on the twig (0..SPAN) of a world point; a point behind her lies beyond the ends.
func _x_of(pos: Vector2) -> float:
	var rel: float = wrapf(_bearing(pos) - _heading, -PI, PI)
	return SPAN * 0.5 + rel / HALF_TURN * SPAN * 0.5


func _draw() -> void:
	if player == null:
		return
	var left: float = roundf((size.x - SPAN) / 2.0)
	var night: float = TimeManager.night_amount()
	for xi: int in int(SPAN) + 1: ## the twig: thin, thicker in the middle, fading at the ends
		var u: float = float(xi) / SPAN
		var edge: float = clampf(minf(u, 1.0 - u) * 6.0, 0.0, 1.0)
		var y: float = TOP + roundf(sin(float(xi) * 0.08 + 0.6) * 0.8)
		draw_rect(Rect2(left + xi, y - 1.0, 1, 3), Color(VineStyle.OUTLINE, 0.85 * edge))
		draw_rect(Rect2(left + xi, y, 1, 1), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, night), edge))
	draw_rect(Rect2(left + SPAN * 0.5, TOP - 3.0, 1, 2), Color(VineStyle.PETAL, 0.7)) ## straight ahead
	for k: int in 4: ## the quarters as knots
		var bearing: float = float(k) * PI * 0.5
		var rel: float = wrapf(bearing - _heading, -PI, PI)
		if absf(rel) > HALF_TURN:
			continue
		var x: float = left + roundf(SPAN * 0.5 + rel / HALF_TURN * SPAN * 0.5)
		var y: float = TOP + roundf(sin((x - left) * 0.08 + 0.6) * 0.8)
		var fade: float = 1.0 - clampf((absf(rel) - HALF_TURN * 0.8) / (HALF_TURN * 0.2), 0.0, 1.0)
		draw_rect(Rect2(x - 1.0, y - 1.0, 3, 3), Color(VineStyle.OUTLINE, fade))
		draw_rect(Rect2(x, y, 1, 1), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, night), fade))
		HudText.draw(self, QUARTERS[k], Vector2(x - 1.0, y + 3.0), Color(UiStyle.TEXT_DIM, 0.8 * fade), fade)
	for mark: Dictionary in _marks:
		_draw_mark(mark, left)


func _draw_mark(mark: Dictionary, left: float) -> void:
	var raw: float = _x_of(mark.pos as Vector2)
	var behind: bool = raw < 0.0 or raw > SPAN
	var x: float = left + roundf(clampf(raw, 2.0, SPAN - 2.0))
	var y: float = TOP - 4.0
	var alpha: float = 0.55 if behind else 1.0
	match String(mark.kind):
		"quest":
			var dim: bool = bool(mark.get("dim", false))
			var color: Color = Color(GOLD, alpha * (0.45 if dim else 1.0))
			VineStyle.glow(self, Vector2(x, y + 1.0), 6.0, GOLD, (0.25 if dim else 0.6) * alpha * (0.8 + 0.2 * sin(_time * 3.0)))
			if bool(mark.get("near", false)): ## open bud: four petals round a light heart
				for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					draw_rect(Rect2(x + d.x, y + 1.0 + d.y, 1, 1), color)
				draw_rect(Rect2(x, y + 1.0, 1, 1), Color(Color.WHITE, alpha))
			else:
				draw_rect(Rect2(x - 1.0, y, 3, 3), Color(VineStyle.OUTLINE, alpha))
				draw_rect(Rect2(x, y, 1, 2), color)
		"gate":
			var open: bool = bool(mark.get("open", true))
			var color: Color = Color(TEAL if open else GREY, alpha)
			if open:
				VineStyle.glow(self, Vector2(x, y + 1.0), 6.0, TEAL, 0.5 * alpha)
			draw_rect(Rect2(x - 2.0, y - 1.0, 1, 5), color) ## two posts and a lintel
			draw_rect(Rect2(x + 2.0, y - 1.0, 1, 5), color)
			draw_rect(Rect2(x - 2.0, y - 2.0, 5, 1), color)
			if open:
				draw_rect(Rect2(x, y + 1.0, 1, 1), Color(Color.WHITE, alpha))
			else:
				draw_rect(Rect2(x - 1.0, y + 1.0, 3, 2), Color(SEAL, alpha))
		"home":
			var c: Color = Color(HOME, alpha)
			draw_rect(Rect2(x - 2.0, y + 1.0, 5, 3), c)
			draw_rect(Rect2(x - 1.0, y, 3, 1), c)
			draw_rect(Rect2(x, y - 1.0, 1, 1), c)
			draw_rect(Rect2(x, y + 2.0, 1, 2), Color(Color("ffd98a"), alpha))
		"stone":
			var s: Color = Color(STONE, alpha)
			draw_rect(Rect2(x, y - 1.0, 1, 1), s)
			draw_rect(Rect2(x - 1.0, y, 3, 3), s)
			draw_rect(Rect2(x - 2.0, y + 3.0, 5, 1), s)
			draw_rect(Rect2(x, y + 1.0, 1, 1), Color(TEAL, alpha))
		"pin":
			draw_rect(Rect2(x - 1.0, y, 3, 2), Color(PIN, alpha * 0.9))
			draw_rect(Rect2(x, y + 2.0, 1, 2), Color(PIN, alpha * 0.9))
		"ping":
			var fade: float = 1.0 - clampf((float(mark.get("age", 0.0)) - 6.0) / 2.0, 0.0, 1.0)
			for k: int in 6: ## a beam of light standing on the twig
				draw_rect(Rect2(x, y + 2.0 - float(k), 1, 1), Color(BEAM, alpha * fade * (1.0 - float(k) / 7.0)))
			VineStyle.glow(self, Vector2(x, y), 5.0, BEAM, 0.5 * fade)
	if behind: ## a half arrow at the end: turn round
		var dir: float = -1.0 if raw < 0.0 else 1.0
		draw_rect(Rect2(x + dir * 3.0, TOP - 1.0, 1, 3), Color(UiStyle.TEXT_DIM, 0.6))
		draw_rect(Rect2(x + dir * 4.0, TOP, 1, 1), Color(UiStyle.TEXT_DIM, 0.6))
