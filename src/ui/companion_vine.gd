class_name CompanionVine
extends Control
## Gefährtenranke (docs/hud_v2_konzept.md 4.7, step 7): the other players of a co-op session as a short list on the
## left rail below the hint card. Per mate one row on a thin stem out of the screen edge: a spore in the player's colour
## (`MultiplayerHud.PLAYER_TONES`), the name, then either a sap line of their health (same zone) or the zone they are
## in, "✝" and the seconds since they fell while down, a status mark (swimming, in a room, in the mine) and a soft
## magenta blink while a shadow creature is at them or a boss fight runs. Local and cosmetic; nothing is sent.
## `MultiplayerHud` keeps only the room badge.

const ROW_H: float = 14.0
const MAX_ROWS: int = 3
const TOP: float = 196.0
const SAP_W: float = 40.0
const FIGHT_RANGE: float = 220.0
const TICK: float = 0.25
const MAGENTA: Color = Color("ff4fa8")

var player: Node2D
var _rows: Array[Dictionary] = [] ## {peer, name, tone, ratio, zone, same, dead, since, mark, fight}
var _down_since: Dictionary = {} ## peer -> seconds since they fell
var _tick: float = 0.0
var _time: float = 0.0
var _redraw_wait: float = 0.0


func bind(p_player: Node2D) -> void:
	player = p_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hud_busy() -> bool:
	return not _rows.is_empty()


## The rows as they are now (tests).
func rows() -> Array[Dictionary]:
	return _rows.duplicate(true)


func _process(delta: float) -> void:
	_time += delta
	for peer: Variant in _down_since.keys():
		_down_since[peer] = float(_down_since[peer]) + delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_collect()
	_redraw_wait -= delta
	var fighting: bool = _rows.any(func(r: Dictionary) -> bool: return bool(r.fight))
	if not _rows.is_empty() and _redraw_wait <= 0.0 and modulate.a > 0.01:
		_redraw_wait = 0.05 if fighting else 0.25
		queue_redraw()
	elif _rows.is_empty() and _redraw_wait <= 0.0:
		_redraw_wait = 1.0
		queue_redraw()


func _collect() -> void:
	_rows.clear()
	if player == null or not is_instance_valid(player):
		return
	var tree: SceneTree = get_tree()
	var world: Node = tree.get_first_node_in_group("world")
	var director: ZoneDirector = world.call("director") as ZoneDirector if world != null and world.has_method("director") else null
	var me: int = player.name.to_int()
	var my_zone: StringName = _zone_of(director, me, player.global_position)
	var boss: bool = false
	var bar: Node = tree.get_first_node_in_group("boss_bar")
	if bar != null and bar.has_method("is_fighting"):
		boss = bool(bar.call("is_fighting"))
	var seen: Dictionary = {}
	for mate: Player in Player.all:
		if not is_instance_valid(mate) or mate == player or not mate.is_inside_tree():
			continue
		var peer: int = mate.name.to_int()
		seen[peer] = true
		var health: HealthComponent = mate.health
		var dead: bool = health != null and health.current <= 0.0
		if dead and not _down_since.has(peer):
			_down_since[peer] = 0.0
		elif not dead:
			_down_since.erase(peer)
		var zone: StringName = _zone_of(director, peer, mate.global_position)
		var zone_name: String = ""
		if director != null and director.atlas != null and zone != &"":
			var z: Atlas.Zone = director.atlas.zone(zone)
			zone_name = z.name if z != null else String(zone).to_upper()
		var mark: String = ""
		if MineManager.in_mine(mate.global_position):
			mark = "mine"
		elif Interiors.slot_at(mate.global_position) >= 0 or PocketSpace.is_pocket(mate.global_position):
			mark = "room"
		elif int(mate.swim) > 0:
			mark = "swim"
		_rows.append({
			"peer": peer,
			"name": NetworkManager.player_name_for(peer).to_upper(),
			"tone": MultiplayerHud.PLAYER_TONES[clampi(NetworkManager.player_slot_for(peer), 0, MultiplayerHud.PLAYER_TONES.size() - 1)],
			"ratio": clampf(health.current / maxf(health.max_health, 1.0), 0.0, 1.0) if health != null else 1.0,
			"zone": zone_name, "same": zone == my_zone or zone == &"", "dead": dead,
			"since": float(_down_since.get(peer, 0.0)), "mark": mark,
			"fight": not dead and (boss or _near_creature(mate)),
		})
		if _rows.size() >= MAX_ROWS:
			break
	for peer: Variant in _down_since.keys():
		if not seen.has(peer):
			_down_since.erase(peer)


func _zone_of(director: ZoneDirector, peer: int, pos: Vector2) -> StringName:
	if director == null:
		return &""
	var zone: StringName = director.player_zone.get(peer, &"") as StringName
	if zone == &"" and director.atlas != null:
		zone = director.atlas.zone_at(director.continent_id, Interiors.outer(get_tree(), pos))
	return zone


func _near_creature(mate: Node2D) -> bool:
	for node: Node in get_tree().get_nodes_in_group("predators"):
		if node.get("enemy_id") == null or not (node is Node2D):
			continue
		if (node as Node2D).global_position.distance_to(mate.global_position) <= FIGHT_RANGE:
			return true
	return false


func _draw() -> void:
	if _rows.is_empty():
		return
	var night: float = TimeManager.night_amount()
	var bark: Color = VineStyle.BARK.lerp(VineStyle.BARK_VOID, night)
	var bark_light: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, night)
	var bottom: float = TOP + float(_rows.size() - 1) * ROW_H + 4.0
	for y: int in range(int(TOP) - 4, int(bottom) + 1): ## the stem down the screen edge
		draw_rect(Rect2(1.0, float(y), 2, 1), VineStyle.OUTLINE)
		draw_rect(Rect2(2.0, float(y), 1, 1), bark_light if y % 3 == 0 else bark)
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		var y: float = TOP + float(i) * ROW_H
		var tone: Color = row.tone as Color
		var dead: bool = bool(row.dead)
		for x: int in range(3, 9): ## a twig to the spore
			draw_rect(Rect2(float(x), y + 2.0, 1, 1), bark_light if x % 2 == 0 else bark)
		if bool(row.fight): ## the soft magenta blink of a fight
			var blink: float = 0.5 + 0.5 * sin(_time * 6.0 + float(i))
			VineStyle.glow(self, Vector2(11.0, y + 2.0), 7.0, MAGENTA, 0.45 * blink)
		var spore: Color = tone.darkened(0.55) if dead else tone
		draw_rect(Rect2(9.0, y, 5, 5), VineStyle.OUTLINE)
		draw_rect(Rect2(10.0, y + 1.0, 3, 3), spore)
		draw_rect(Rect2(10.0, y + 1.0, 1, 1), spore.lightened(0.4))
		var name: String = String(row.name).left(12)
		var name_color: Color = Color(UiStyle.TEXT_DIM, 0.8) if dead else Color(tone.lerp(Color.WHITE, 0.35), 0.95)
		HudText.draw(self, name, Vector2(17.0, y), name_color)
		var x: float = 17.0 + HudText.width(name) + 4.0
		if dead:
			HudText.draw(self, "✝ %d" % int(row.since), Vector2(x, y), Color(MAGENTA.lerp(UiStyle.TEXT_DIM, 0.4), 0.9))
		elif bool(row.same):
			var ratio: float = float(row.ratio)
			var sap: Color = Color("e0485a").lerp(Color("9af0a8"), clampf((ratio - 0.25) / 0.5, 0.0, 1.0))
			draw_rect(Rect2(x - 1.0, y + 1.0, SAP_W + 2.0, 4), VineStyle.OUTLINE)
			draw_rect(Rect2(x, y + 2.0, SAP_W, 2), bark)
			draw_rect(Rect2(x, y + 2.0, roundf(SAP_W * ratio), 2), sap)
			draw_rect(Rect2(x, y + 2.0, roundf(SAP_W * ratio), 1), sap.lightened(0.3))
			x += SAP_W + 4.0
		else:
			var zone: String = "→ " + String(row.zone)
			HudText.draw(self, zone.left(18), Vector2(x, y), Color(UiStyle.TEXT_DIM, 0.85))
			x += HudText.width(zone.left(18)) + 4.0
		_draw_mark(String(row.mark), Vector2(x, y), tone)


func _draw_mark(mark: String, at: Vector2, tone: Color) -> void:
	var c: Color = Color(tone.lerp(UiStyle.TEXT_DIM, 0.4), 0.9)
	match mark:
		"swim": ## a wave
			for k: int in 5:
				draw_rect(Rect2(at.x + k, at.y + 2.0 + (1.0 if k % 2 == 0 else 0.0), 1, 1), Color("7fc8ff"))
		"room": ## a door
			draw_rect(Rect2(at.x, at.y, 4, 5), c)
			draw_rect(Rect2(at.x + 1.0, at.y + 1.0, 2, 4), VineStyle.OUTLINE)
		"mine": ## a pick
			draw_rect(Rect2(at.x, at.y, 5, 1), c)
			draw_rect(Rect2(at.x + 2.0, at.y + 1.0, 1, 4), c)
