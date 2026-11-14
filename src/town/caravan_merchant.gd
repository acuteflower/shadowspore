class_name CaravanMerchant
extends Interactable
## Jorun, the travelling merchant (docs/haendler_konzept.md 2.1, 6.1). Like `InteriorResident` no network object: where he is and what he does follows the
## caravan's phase. He walks beside the ox while the caravan drives, steps to the counter while the stall unfolds, stands at its inner end while it is open
## and sleeps in the wagon at night (E KLOPFEN: a line through the canvas). E while open: ANSPRECHEN (the first talk of a day builds trust through
## `TownManager.request_talk`, his `chat` line; the very first one tells her his name: flag `knows_jorun`), then HANDELN opens `ShopWindow` "caravan".
## Art: assets/characters/jorun.png (+ _glow) and data/jorun_rig.json in the settlers' format; until they exist a placeholder figure is drawn.

const WALK_SPEED: float = 30.0

var caravan: CaravanManager
var sid: String = "jorun"
var spec: Dictionary = {}
var _rig: Dictionary = {}
var _sprite: Sprite2D
var _glow: Sprite2D
var _clip: String = "idle"
var _clip_time: float = 0.0
var _sector: int = 2
var _time: float = 0.0
var _talking: bool = false
var _turned: float = 0.0
var _last_line: String = ""
var _last_pos: Vector2 = Vector2.ZERO
var _registered: bool = false
var _cycle: int = 0 ## which of the stall's idle clips plays (CYCLE)
var _cycle_t: float = 0.0
var _call_cool: float = 6.0 ## seconds until he may call out again
var _greeted: Dictionary = {} ## day -> true: he waved at the local player today
var _once: String = "" ## a one-shot clip (call, wave) playing over the cycle
var _once_t: float = 0.0
var _bubble: SettlerBubble
const CYCLE: Array[String] = ["counter", "arrange", "counter", "count", "counter", "smoke"]


func setup(owner_caravan: CaravanManager) -> void:
	caravan = owner_caravan
	sid = caravan.merchant_id()
	spec = DataRegistry.get_entry("settlers", sid)
	add_to_group("quest_actors")
	visible = false
	var art: String = String(spec.get("art", sid))
	var rig_path: String = "res://data/%s_rig.json" % art
	if FileAccess.file_exists(rig_path) and ResourceLoader.exists("res://assets/characters/%s.png" % art):
		_rig = JSON.parse_string(FileAccess.get_file_as_string(rig_path)) as Dictionary
		_sprite = _sheet("res://assets/characters/%s.png" % art)
		if ResourceLoader.exists("res://assets/characters/%s_glow.png" % art):
			_glow = _sheet("res://assets/characters/%s_glow.png" % art)
			_glow.material = Unlit.material()


func _sheet(path: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path) as Texture2D
	sprite.hframes = int(_rig.get("frames", 1))
	sprite.vframes = int(_rig.get("rows", 8))
	sprite.centered = false
	var feet: Array = _rig.get("feet", [0, 0]) as Array
	sprite.position = Vector2(-float(feet[0]), -float(feet[1]))
	add_child(sprite)
	return sprite


func display_name() -> String:
	return String(spec.get("name", "JORUN")) if caravan.town.has_met(sid) else String(spec.get("stranger", "FREMDER HÄNDLER"))


## Called by the caravan every frame: place and clip from the phase.
func follow() -> void:
	var delta: float = get_process_delta_time()
	_time += delta
	_turned = maxf(_turned - delta, 0.0)
	if not _registered and caravan.town != null:
		caravan.town.register_person(sid, self)
		_registered = true
	var s: String = caravan.state()
	var k: float = float(caravan.phase.get("k", 0.0))
	var pose: Dictionary = caravan.wagon_pose()
	var wagon: Vector2 = pose.pos as Vector2
	var dir: Vector2 = pose.dir as Vector2
	var ahead: float = float((DataRegistry.table("caravan_art").get("wagon", {}) as Dictionary).get("ox_ahead", 44.0)) * 0.72
	var beside_ox: Vector2 = wagon + Vector2(dir.x, dir.y * CaravanView.SINP) * ahead + Vector2(-dir.y, dir.x) * 14.0
	var counter: Vector2 = caravan.merchant_point()
	var shown: bool = true
	var target: Vector2 = counter
	match s:
		"away":
			shown = false
		"coming", "going":
			target = beside_ox
		"setup":
			target = beside_ox.lerp(counter, smoothstep(0.0, 0.35, k))
		"teardown":
			target = counter.lerp(beside_ox, smoothstep(0.55, 1.0, k))
		"night", "storm":
			shown = false ## asleep (or sheltering) in the wagon
			target = caravan.stall() + Vector2(0.0, 4.0)
	visible = shown
	global_position = target
	var step: Vector2 = global_position - _last_pos
	var moving: bool = step.length() > 0.05 and step.length() < 40.0
	_last_pos = global_position
	if moving:
		_sector = Adventurer.sector_of(step)
	elif _turned <= 0.0 and s == "open":
		_sector = 2 ## facing the customers (south)
	var wanted: String = "walk" if moving else ("idle" if s != "open" else _stall_clip(delta))
	if wanted != _clip:
		_clip = wanted
		_clip_time = 0.0
	_clip_time += delta
	_show()
	queue_redraw()


## What he does at the open stall: holds a bundle out while somebody trades with him, waves at the local player the first time a day, calls out to people
## passing at a distance, otherwise cycles counter / arrange / count / smoke.
func _stall_clip(delta: float) -> String:
	_call_cool = maxf(_call_cool - delta, 0.0)
	if get_tree().get_first_node_in_group("shop_window") is ShopWindow and (get_tree().get_first_node_in_group("shop_window") as ShopWindow).shop_id == caravan.shop_id():
		return "present" if _has_clip("present") else "idle"
	if _once != "":
		_once_t -= delta
		if _once_t > 0.0:
			return _once
		_once = ""
	var player: Player = caravan.town.local_player()
	if player != null and not _talking:
		var d: float = player.global_position.distance_to(global_position)
		if d < 90.0 and not _greeted.has(TimeManager.day) and _has_clip("wave"):
			_greeted[TimeManager.day] = true
			_play_once("wave")
			_sector = Adventurer.sector_of(player.global_position - global_position)
			_turned = 2.0
			return _once
		if d > 90.0 and d < 190.0 and _call_cool <= 0.0 and _has_clip("call"):
			_call_cool = randf_range(14.0, 24.0)
			_play_once("call")
			say(_pick((spec.get("chat", {}) as Dictionary).get("call", []) as Array), 2.6)
			return _once
	_cycle_t += delta
	var current: String = CYCLE[_cycle % CYCLE.size()]
	if _cycle_t > (7.0 if current == "counter" else _clip_seconds(current) * 2.0):
		_cycle_t = 0.0
		_cycle += 1
		current = CYCLE[_cycle % CYCLE.size()]
	return current if _has_clip(current) else "idle"


func _clip_seconds(name_id: String) -> float:
	var clip: Dictionary = (_rig.get("clips", {}) as Dictionary).get(name_id, {}) as Dictionary
	return float(clip.get("count", 4)) / maxf(float(clip.get("fps", 4)), 1.0)


func _play_once(name_id: String) -> void:
	_once = name_id
	_once_t = _clip_seconds(name_id) * 1.6


## A short line in the bubble over his head (`SettlerBubble`, like the settlers' chatter).
func say(text: String, seconds: float) -> void:
	if text == "":
		return
	if _bubble == null:
		_bubble = SettlerBubble.new()
		_bubble.position = Vector2(0.0, -float(_rig.get("height", 40)) - 10.0)
		add_child(_bubble)
	_bubble.show_text(text, seconds)


func _has_clip(name_id: String) -> bool:
	return (_rig.get("clips", {}) as Dictionary).has(name_id)


func _show() -> void:
	if _sprite == null:
		return
	var clips: Dictionary = _rig.get("clips", {}) as Dictionary
	var clip: Dictionary = clips.get(_clip, clips.get("idle", {})) as Dictionary
	var count: int = maxi(int(clip.get("count", 1)), 1)
	var index: int = _sector * int(_rig.get("frames", 1)) + int(clip.get("start", 0)) + int(_clip_time * float(clip.get("fps", 8))) % count
	_sprite.frame = index
	if _glow != null:
		_glow.frame = index


func _draw() -> void:
	if not visible:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * Vector2(9.0, 3.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.26))
	if _sprite == null: ## placeholder: layered earth-brown coats with a stripe of caravan blue, a wide hat, a lantern staff
		var walk: float = float(int(_time * 8.0) % 2) if _clip == "walk" else 0.0
		draw_rect(Rect2(-4, -8, 3, 8 - walk), Color("2a2438"))
		draw_rect(Rect2(1, -8, 3, 8 - (1.0 - walk) * float(_clip == "walk")), Color("2a2438"))
		draw_rect(Rect2(-6, -24, 12, 17), Color("6b5440"))
		draw_rect(Rect2(-6, -16, 12, 2), Color("3d5a8a"))
		draw_rect(Rect2(-5, -24, 10, 5), Color("8a6e50"))
		draw_circle(Vector2(0, -28), 4.5, Color("c8946a"))
		draw_rect(Rect2(-9, -33, 18, 2), Color("3b2a22"))
		draw_rect(Rect2(-5, -37, 10, 4), Color("3b2a22"))
		draw_line(Vector2(-11, -33), Vector2(-11, -29), Color("d8c8a8"), 1.0) ## a charm on the hat's string
		draw_line(Vector2(9, -2), Vector2(9, -30), Color("5e3f52"), 1.0) ## the lantern staff
		draw_rect(Rect2(7, -34, 4, 4), Color(Color("ffd27a"), clampf(TimeManager.night_amount() * 1.4, 0.3, 1.0)))


# ---------- E ----------

func prompt() -> String:
	if _talking or InputManager.ui_blocking or caravan == null:
		return ""
	match caravan.state():
		"open":
			var talked: bool = int((caravan.town.residents.get(sid, {}) as Dictionary).get("talked", -1)) == TimeManager.day
			return "HANDELN" if talked else "ANSPRECHEN"
		"night", "storm":
			return "KLOPFEN"
	return ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - float(caravan.cfg().get("reach", 72.0)) if caravan != null else INF


func prompt_position() -> Vector2:
	return Vector2(0.0, -float(_rig.get("height", 40)) - 8.0)


func interact(player: Player) -> void:
	if _talking or caravan == null:
		return
	var s: String = caravan.state()
	var runner: BubbleRunner = BubbleRunner.find(player)
	if s == "night" or s == "storm": ## through the canvas
		_talking = true
		caravan.view._sound("knock", -8.0, global_position - caravan.view.global_position, 260.0)
		var line: String = _pick(((spec.get("chat", {}) as Dictionary).get("knock_storm" if s == "storm" else "knock", []) as Array))
		if runner != null and line != "":
			await runner.say_line(display_name(), line, self)
		_talking = false
		return
	if s != "open":
		return
	_talking = true
	_turned = 4.0
	_sector = Adventurer.sector_of(player.global_position - global_position)
	var fresh_day: bool = int((caravan.town.residents.get(sid, {}) as Dictionary).get("talked", -1)) != TimeManager.day
	if fresh_day:
		var first: bool = not caravan.town.has_met(sid)
		caravan.town.request_talk(sid)
		if player.quests != null:
			player.quests.set_flag("knows_jorun")
		var chat: Dictionary = spec.get("chat", {}) as Dictionary
		var line: String = _pick(chat.get("first", []) as Array) if first else _chat_line()
		if runner != null and line != "":
			await runner.say_line(String(spec.get("name", "JORUN")) if not first else display_name(), line, self)
	if is_inside_tree() and caravan.is_open():
		ShopWindow.open(get_tree(), player, caravan.town, caravan.shop_id())
	_talking = false


func _chat_line() -> String:
	var chat: Dictionary = spec.get("chat", {}) as Dictionary
	var pool: Array = []
	if TimeManager.night_amount() > 0.3:
		pool.append_array(chat.get("evening", []) as Array)
	if caravan.offer().get("sell", []).size() > 0:
		pool.append_array(chat.get("wanted", []) as Array)
	pool.append_array(chat.get("any", []) as Array)
	return _pick(pool)


func _pick(pool: Array) -> String:
	if pool.is_empty():
		return ""
	var line: String = String(pool[randi() % pool.size()])
	if pool.size() > 1 and line == _last_line:
		line = String(pool[(pool.find(line) + 1) % pool.size()])
	_last_line = line
	return line


## The map (M): the caravan where it is, also on the road (`MapWindow._live_markers`, style `jorun` in data/map_markers.json).
func map_marker() -> Dictionary:
	if caravan == null or not CaravanRules.present(caravan.state()):
		return {}
	return {"id": sid, "name": display_name(), "title": "KARAWANE" if CaravanRules.parked(caravan.state()) else "KARAWANE UNTERWEGS",
		"position": caravan.wagon_pose().pos as Vector2}


## `quest_actors`: where he stands while the caravan is in town.
func actor_position(who: String) -> Vector2:
	return global_position if who == sid and visible else Vector2.INF
