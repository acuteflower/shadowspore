class_name SettlerChatter
extends Node
## The people of the town talk among themselves (docs/town_ausbau.md C16), data/chatter.json. Two kinds:
##  * topics (`meet`, `fire_story`): two residents are at the same place (the fire) in the evening; one topic of each kind a day, at a moment that is a fixed function of the
##    day and the topic, so every peer shows the same words at the same time without anything being sent;
##  * reactions: a line to something that happened to the town (`TownManager.event`, a piece built, a settler moved in).
## It runs on every peer and only shows (small bubbles over the heads, `Settler.say`). All words are placeholders for the dialogue writer.

var town: TownManager
var _cfg: Dictionary = {}
var _played: Dictionary = {} ## "day:topic" -> true
var _clock: float = 0.0
var _busy: bool = false
var _react_msec: int = 0


func _ready() -> void:
	_cfg = DataRegistry.table("chatter")
	town.event.connect(func(kind: String, _data: Dictionary) -> void: _react(kind))
	town.built.connect(func(piece: String, _id: int) -> void: _react("built:" + piece))
	town.resident_joined.connect(func(sid: String) -> void: _react("joined:" + sid))


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 1.0:
		_clock = 0.0
		_tick()


## A fixed number 0..1 for (day, key): the same on every peer.
static func unit(day: int, key: String) -> float:
	return float(("%d|%s" % [day, key]).hash() % 1000) / 1000.0


func _topics(kind: String) -> Array:
	var out: Array = []
	for raw: Variant in _cfg.get("topics", []) as Array:
		if String((raw as Dictionary).kind) == kind:
			out.append(raw)
	return out


func _tick() -> void:
	if _busy or town == null or not town.founded or town.local_player() == null or town.alert_on:
		return
	var day: int = TimeManager.day
	if _played.size() > 40:
		_played.clear()
	var tod: float = TimeManager.time_of_day
	for kind: String in ["meet", "fire_story"]:
		var list: Array = _topics(kind)
		if list.is_empty():
			continue
		var topic: Dictionary = list[int(unit(day, kind) * 1000.0) % list.size()] as Dictionary ## one a day of each kind
		var key: String = "%d:%s" % [day, String(topic.id)]
		if _played.has(key):
			continue
		var window: Array = topic.window as Array
		var start: float = float(window[0]) + unit(day, String(topic.id)) * (float(window[1]) - float(window[0])) * 0.5
		if tod < start or tod > float(window[1]):
			continue
		var who: Array = topic.who as Array
		var a: Settler = town.settler_node(String(who[0]))
		var b: Settler = town.settler_node(String(who[1]))
		if a == null or b == null or not a.visible or not b.visible:
			continue
		if a.spot_name() != String(topic.spot) or b.spot_name() != String(topic.spot) or a.global_position.distance_to(b.global_position) > 100.0:
			continue
		_played[key] = true
		_say(topic.lines as Array, 0.0)
		return


## Somebody in earshot reacts to what happened (one reaction every `reaction_cooldown` seconds).
func _react(key: String) -> void:
	if _busy or town == null or not town.founded or town.local_player() == null:
		return
	if Time.get_ticks_msec() < _react_msec:
		return
	var options: Array = []
	for raw: Variant in _cfg.get("reactions", []) as Array:
		if String((raw as Dictionary).event) == key:
			options.append(raw)
	if options.is_empty():
		return
	var pick: Dictionary = options[int(unit(TimeManager.day, key) * 1000.0) % options.size()] as Dictionary
	_react_msec = Time.get_ticks_msec() + int(float(_cfg.get("reaction_cooldown", 25.0)) * 1000.0)
	_say(pick.lines as Array, 1.4)


func _speaker(who: String) -> Settler:
	if who != "any":
		var named: Settler = town.settler_node(who)
		return named if named != null and named.visible else null
	var player: Player = town.local_player()
	var best: Settler = null
	var best_distance: float = INF
	for sid: String in town.settler_ids():
		var settler: Settler = town.settler_node(sid)
		if settler != null and settler.visible and player != null:
			var d: float = settler.global_position.distance_to(player.global_position)
			if d < best_distance:
				best = settler
				best_distance = d
	return best


func _say(lines: Array, delay: float) -> void:
	_busy = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var reach: float = float(_cfg.get("range", 190.0))
	var hold: float = float(_cfg.get("hold", 3.2))
	var gap: float = float(_cfg.get("gap", 3.0))
	for raw: Variant in lines:
		var line: Array = raw as Array
		var settler: Settler = _speaker(String(line[0]))
		var player: Player = town.local_player() if town != null else null
		if settler != null and player != null and settler.global_position.distance_to(player.global_position) <= reach:
			settler.say(String(line[1]), hold)
		await get_tree().create_timer(gap).timeout
	_busy = false
