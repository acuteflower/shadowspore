class_name Settler
extends Interactable
## A resident of the town (data/settlers.json). Not a network object: where they stand is a pure function of the clock, their plan and the position of their home
## building, so every peer computes the same place and nothing needs syncing (docs/town.md). They walk in from the edge of the light when they arrive (a local
## walk, shown on the peers that were there), work at their place by day, stand at the hut's fire in the evening and sleep at night (hidden). **They walk like people:**
## a change of place is a route (`TownManager.walk_route`: round the pieces, fences, trunks and rocks, along the trampled ways), walked at a steady pace from the moment
## the plan changes; a spot inside a piece (the bed) is entered through its door.
## E talks (the first talk of a day builds trust) and, at the bench, opens the craft window. The art is made apart: assets/characters/<art>.png + data/<art>_rig.json
## (docs/town.md "Art contract"); until it exists a plain placeholder figure stands in, so the whole town works without it.
## A spot may say more than where to stand (data `spots`): `clip` (what the figure plays there: stand, sit, hammer ...), `enter` (a clip played once on arrival: sit_down), `clips` + `pause`
## (a cycle: each clip once, a pause between, round again: sword practice), `face`, `sound` "hammer" with `strike` (the frame where the mallet hits). A settler with `chat` (Valdric) answers E
## with a line instead of a dialogue or a shop: from the pool of the current quest step, of the place he stands at, of the night, of anything; `takes_over` "knight" makes him the story's knight
## from then on (the actor is put away, he walks on from where the knight stood), `founder` makes him a resident from the day the town is founded, `counts` false keeps him out of the town's worth.

const TRAVEL: float = 0.02 ## of a day: the time a change of place may take at most (a walk that is long gets quicker)
const WALK_SPEED: float = 34.0 ## px/s while she walks in
const SECTORS: int = 8

var town: TownManager
var sid: String = ""
var spec: Dictionary = {}
var _rig: Dictionary = {}
var _sprite: Sprite2D
var _glow: Sprite2D
var _clip: String = "idle"
var _clip_time: float = 0.0
var _sector: int = 2
var _arrive_t: float = -1.0
var _arrive_route: PackedVector2Array = PackedVector2Array()
var _arrive_total: float = 1.0
var _last_pos: Vector2 = Vector2.ZERO
var _moving: bool = false
var _spot: String = "rest"
var _talking: bool = false
var _time: float = 0.0
var _strike_clock: float = 0.0
var _hammers: Array[AudioStream] = []
var _cycle_i: int = 0
var _cycle_t: float = 0.0
var _cycle_pause: bool = false
var _enter_t: float = 99.0 ## seconds since they stopped walking (the `enter` clip plays for its first moments)
var _last_line: String = ""
var _bubble: SettlerBubble
var _alert_mode: int = 0 ## 0 the plan, 1 walking out to the edge of the light, 2 holding it, 3 walking back (`alert_watch`, docs/town_ausbau.md C20)
var _alert_route: PackedVector2Array = PackedVector2Array()
var _alert_d: float = 0.0
var _alert_sector: int = 2
const ALERT_SPEED: float = 52.0


func setup(owner_town: TownManager, settler_id: String, fresh: bool) -> void:
	town = owner_town
	sid = settler_id
	spec = town.settler_spec(sid)
	_rig = DataRegistry.table(String(spec.art) + "_rig")
	add_to_group("settlers")
	add_to_group("quest_actors")
	var sheet: String = "res://assets/characters/%s.png" % String(spec.art)
	if not _rig.is_empty() and ResourceLoader.exists(sheet):
		_sprite = _make_sprite(sheet)
		var glow_path: String = "res://assets/characters/%s_glow.png" % String(spec.art)
		if ResourceLoader.exists(glow_path):
			_glow = _make_sprite(glow_path)
			_glow.material = Unlit.material()
	for path: String in ["res://assets/audio/hut/hammer_a.wav", "res://assets/audio/hut/hammer_b.wav", "res://assets/audio/hut/hammer_c.wav"]:
		_hammers.append(load(path) as AudioStream)
	var taken_at: Vector2 = Vector2.INF
	if String(spec.get("takes_over", "")) == "knight" and town.world != null:
		taken_at = town.world.take_knight() ## the story's actor is put away: he is this settler now
	elif String(spec.get("takes_over", "")) == "story_gustav": ## Gustav's escort figure is put away: he is this settler now
		for node: Node in get_tree().get_nodes_in_group("story_gustav"):
			if node is Node2D:
				taken_at = (node as Node2D).global_position
				node.queue_free()
	var plan: Dictionary = plan_at(TimeManager.time_of_day)
	var target: Vector2 = _plan_position(plan).pos as Vector2
	global_position = target
	_last_pos = target
	if fresh:
		var arrive: Dictionary = spec.get("arrive", {}) as Dictionary
		var angle: float = deg_to_rad(float(arrive.get("angle", 180.0)))
		var goal: Vector2 = town.stand_point(spot_position(String(plan.spot)))
		var from: Vector2 = taken_at if taken_at != Vector2.INF else goal + Vector2.from_angle(angle) * float(arrive.get("distance", 190.0))
		_arrive_route = town.walk_route(from, goal)
		if _arrive_route.size() >= 2: ## no way in (walled in): they are simply there, nobody floats through trees
			_arrive_total = maxf(_length(_arrive_route) / WALK_SPEED, 1.0)
			_arrive_t = 0.0
			global_position = _arrive_route[0]


func _make_sprite(path: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path) as Texture2D
	sprite.hframes = int(_rig.get("frames", 1))
	sprite.vframes = SECTORS
	var frame: Array = _rig.get("frame", [64, 72]) as Array
	var feet: Array = _rig.get("feet", [32, 58]) as Array
	sprite.offset = Vector2(0.0, float(frame[1]) * 0.5 - float(feet[1]))
	add_child(sprite)
	return sprite


# ---------- where she is ----------

func home_position() -> Vector2:
	var ids: Array[int] = town.built_ids(String(spec.get("home", "")))
	return town.position_of(ids[0]) if not ids.is_empty() else town.center + Vector2(0.0, 24.0)


func spot_position(spot: String) -> Vector2:
	var spots: Dictionary = spec.get("spots", {}) as Dictionary
	var cfg: Dictionary = spots.get(spot, spots.get("rest", {})) as Dictionary
	var at: Array = cfg.get("at", [0, 0]) as Array
	var of: String = String(cfg.get("of", "home"))
	var anchor: Vector2
	if of == "home":
		anchor = home_position()
	elif of == "center":
		anchor = town.center
	else: ## the first finished piece of that kind (the bench, the stockpile); without one the spot is the fallback's
		var ids: Array[int] = town.built_ids(of)
		if ids.is_empty():
			return spot_position(String(cfg.get("fallback", "work")))
		anchor = town.position_of(ids[0])
	return anchor + Vector2(float(at[0]), float(at[1]))


## The spot actually used: one that hangs on a piece that does not stand (data `of`) is its `fallback` (work, unless it says otherwise).
func resolve_spot(spot: String) -> String:
	var cfg: Dictionary = (spec.get("spots", {}) as Dictionary).get(spot, {}) as Dictionary
	var of: String = String(cfg.get("of", "home"))
	if of != "home" and of != "center" and town.built_ids(of).is_empty():
		return String(cfg.get("fallback", "work"))
	return spot


## The plan at time `t` (0..1 of the day): {spot, prev, k, seconds}: k 0..1 how far the change window from `prev` to `spot` has run, seconds since it opened.
func plan_at(t: float) -> Dictionary:
	var schedule: Array = spec.get("schedule", []) as Array
	if spec.has("schedule_camp") and town.built_ids(String(spec.get("home", ""))).is_empty():
		schedule = spec.schedule_camp as Array ## without their house they live at the fire (Gustav before the workshop stands)
	for i: int in schedule.size():
		var window: Array = schedule[i] as Array
		var a: float = float(window[0])
		var b: float = float(window[1])
		var inside: bool = (t >= a and t < b) if a < b else (t >= a or t < b)
		if inside:
			var previous: Array = schedule[(i + schedule.size() - 1) % schedule.size()] as Array
			return {"spot": String(window[2]), "prev": String(previous[2]), "k": clampf(fposmod(t - a, 1.0) / TRAVEL, 0.0, 1.0), "seconds": fposmod(t - a, 1.0) * TimeManager.DAY_LENGTH_SEC}
	return {"spot": "rest", "prev": "rest", "k": 1.0, "seconds": 0.0}


## Where the plan puts them: {pos, done}. A change of place is a walk along `TownManager.walk_route` at a steady pace from the moment the window opens (a long one is
## quickened to fit); `done` once they have arrived (or when there was nothing to walk).
func _plan_position(plan: Dictionary) -> Dictionary:
	var to: Vector2 = spot_position(String(plan.spot))
	if String(plan.spot) == String(plan.prev) or float(plan.k) >= 1.0:
		return {"pos": town.stand_point(to), "done": true}
	var route: PackedVector2Array = town.walk_route(spot_position(String(plan.prev)), to)
	if route.size() < 2: ## no way found: they are there, not floating through whatever is in between
		return {"pos": town.stand_point(to), "done": true}
	var length: float = _length(route)
	var speed: float = maxf(WALK_SPEED, length / (TRAVEL * TimeManager.DAY_LENGTH_SEC * 0.9))
	var walked: float = float(plan.seconds) * speed
	return {"pos": _along(route, walked), "done": walked >= length}


static func _length(route: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, route.size()):
		total += route[i - 1].distance_to(route[i])
	return total


## The point `distance` px along the line (the end when it is longer).
static func _along(route: PackedVector2Array, distance: float) -> Vector2:
	var left: float = maxf(distance, 0.0)
	for i: int in range(1, route.size()):
		var segment: float = route[i - 1].distance_to(route[i])
		if left <= segment:
			return route[i - 1].lerp(route[i], left / maxf(segment, 0.001))
		left -= segment
	return route[route.size() - 1]


func is_working() -> bool:
	return _spot == "work" and not _moving and _arrive_t < 0.0 and visible


func is_helping() -> bool:
	return is_working()


func actor_position(who: String) -> Vector2:
	return global_position if (who == sid or who == String(spec.get("actor", ""))) and visible else Vector2.INF


## Sleeping residents remain at their home on the map, with a quiet resting marker.
func map_marker() -> Dictionary:
	if town == null or not town.residents.has(sid):
		return {}
	return {"id": sid, "name": String(spec.get("name", sid)), "title": String(spec.get("title", "BEWOHNER")),
		"position": global_position if visible else home_position(), "resting": not visible}


# ---------- every frame ----------

func _process(delta: float) -> void:
	_time += delta
	var plan: Dictionary = plan_at(TimeManager.time_of_day)
	_spot = resolve_spot(String(plan.spot))
	var placed: Dictionary = _plan_position(plan)
	if _arrive_t >= 0.0:
		_arrive_t += delta
		var k: float = clampf(_arrive_t / _arrive_total, 0.0, 1.0)
		global_position = _along(_arrive_route, k * _length(_arrive_route))
		if k >= 1.0:
			_arrive_t = -1.0
	elif not _talking:
		global_position = placed.pos as Vector2
	_alert_step(delta, placed.pos as Vector2)
	visible = _arrive_t >= 0.0 or not (_spot == "rest" and (bool(placed.done) or String(plan.prev) == "rest")) ## asleep inside once they have walked in
	var step: Vector2 = global_position - _last_pos
	_moving = step.length() > 0.02
	var cfg: Dictionary = _spot_cfg()
	if _moving:
		_sector = Adventurer.sector_of(step)
		_enter_t = 0.0
		_cycle_pause = false
		_cycle_t = 0.0
	else:
		_enter_t += delta
		if cfg.has("face"):
			_sector = Adventurer.sector_of(_vec(cfg.face))
		elif _spot == "work":
			_sector = Adventurer.sector_of(_vec(spec.get("face_work", [0, -1])))
		elif _spot == "fire":
			_sector = Adventurer.sector_of(_vec(spec.get("face_fire", [1, 0])))
	_last_pos = global_position
	var wanted: String = "walk" if _moving else _spot_clip(cfg, delta)
	if _alert_mode == 2 and not _moving: ## on watch at the edge of the light: standing, sword at his side, looking out
		wanted = "idle" if _has_clip("idle") else wanted
		_sector = _alert_sector
	if _talking and not _moving:
		wanted = "idle" if _has_clip("idle") else wanted
	if wanted != _clip:
		_clip = wanted
		_clip_time = 0.0
	_clip_time += delta
	_show()
	_work_sound(delta, cfg)
	queue_redraw()


func _spot_cfg() -> Dictionary:
	return (spec.get("spots", {}) as Dictionary).get(_spot, {}) as Dictionary


func _has_clip(name: String) -> bool:
	return (_rig.get("clips", {}) as Dictionary).has(name)


func _clip_seconds(name: String) -> float:
	var clip: Dictionary = (_rig.get("clips", {}) as Dictionary).get(name, {}) as Dictionary
	return float(clip.get("count", 1)) / maxf(float(clip.get("fps", 8)), 1.0)


## What the figure plays at this spot: the legacy `work` / `idle`, the spot's own `clip` (after its `enter` clip), or a cycle of `clips` with a pause between.
func _spot_clip(cfg: Dictionary, delta: float) -> String:
	var list: Array = cfg.get("clips", []) as Array
	if list.is_empty():
		var main: String = String(cfg.get("clip", "work" if _spot == "work" else "idle"))
		var enter: String = String(cfg.get("enter", ""))
		if enter != "" and _enter_t < _clip_seconds(enter):
			return enter
		return main
	var name: String = String(list[_cycle_i % list.size()])
	_cycle_t += delta
	if not _cycle_pause:
		if _cycle_t >= _clip_seconds(name):
			_cycle_pause = true
			_cycle_t = 0.0
			return String(cfg.get("rest", "idle"))
		return name
	if _cycle_t >= float(cfg.get("pause", 1.2)):
		_cycle_pause = false
		_cycle_t = 0.0
		_cycle_i += 1
		return String(list[_cycle_i % list.size()])
	return String(cfg.get("rest", "idle"))


func _vec(raw: Variant) -> Vector2:
	var a: Array = raw as Array
	return Vector2(float(a[0]), float(a[1]))


## The mallet rings once per round of the work clip (or of the spot's own `hammer` clip), whether or not the picture exists.
func _work_sound(delta: float, cfg: Dictionary) -> void:
	var sound: String = String(cfg.get("sound", "hammer" if _clip == "work" else ""))
	var hammering: bool = sound == "hammer" and (_clip == "work" or _clip == String(cfg.get("clip", "")))
	if not hammering or not visible or _talking:
		_strike_clock = 0.0
		return
	var clip: Dictionary = ((_rig.get("clips", {}) as Dictionary).get(_clip, {})) as Dictionary
	var fps: float = maxf(float(clip.get("fps", 9)), 1.0)
	var round_time: float = float(clip.get("count", 6)) / fps
	var strike_at: float = float(cfg.get("strike", clip.get("strike", 3))) / fps
	var before: float = floorf((_strike_clock - strike_at) / round_time)
	_strike_clock += delta
	if floorf((_strike_clock - strike_at) / round_time) > before:
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.stream = _hammers[randi() % _hammers.size()]
		player.volume_db = -12.0
		player.max_distance = 260.0
		player.pitch_scale = randf_range(0.94, 1.06)
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()


## A few pale chips fly from the log on the splitting block when the mallet drives the wedge in (spot `chips`; the block is a step `reach` px in front of them).
func _chips(cfg: Dictionary) -> void:
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.one_shot = true
	puff.amount = 6
	puff.lifetime = 0.55
	puff.explosiveness = 1.0
	puff.direction = Vector2.UP
	puff.spread = 70.0
	puff.gravity = Vector2(0.0, 90.0)
	puff.initial_velocity_min = 14.0
	puff.initial_velocity_max = 34.0
	puff.scale_amount_min = 0.8
	puff.scale_amount_max = 1.3
	puff.color = Color("c9a878")
	puff.position = _vec(cfg.get("face", [1, 0])) * float(cfg.get("reach", 9.0)) + Vector2(0.0, -6.0)
	puff.z_index = 2
	add_child(puff)
	puff.emitting = true
	get_tree().create_timer(1.0).timeout.connect(puff.queue_free)


func _show() -> void:
	if _sprite == null:
		return
	var clips: Dictionary = _rig.get("clips", {}) as Dictionary
	var clip: Dictionary = clips.get(_clip, clips.get("idle", {})) as Dictionary
	var count: int = maxi(int(clip.get("count", 1)), 1)
	var raw: int = int(_clip_time * float(clip.get("fps", 8)))
	var frame: int = raw % count if bool(clip.get("loop", true)) else mini(raw, count - 1)
	var index: int = _sector * int(_rig.get("frames", 1)) + int(clip.get("start", 0)) + frame
	_sprite.frame = index
	if _glow != null:
		_glow.frame = index
		_glow.modulate.a = 0.8 + 0.2 * sin(_time * 5.0)


func _draw() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * Vector2(10.0, 3.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.26))
	if _sprite == null: ## no art yet: a plain stand-in (a leather apron over a violet shirt) so the town can be tried
		draw_rect(Rect2(-5, -24, 10, 16), Color("5a4a6e"))
		draw_rect(Rect2(-4, -17, 8, 10), Color("6b4a32"))
		draw_rect(Rect2(-5, -8, 4, 8), Color("2a2438"))
		draw_rect(Rect2(1, -8, 4, 8), Color("2a2438"))
		draw_circle(Vector2(0, -29), 5.0, Color("c8946a"))
		draw_rect(Rect2(-5, -35, 10, 3), Color("8c8a96"))


# ---------- chatter and the watch ----------

func spot_name() -> String:
	return _spot


## Says something to the town (the small bubble over the head, `SettlerChatter`).
func say(text: String, seconds: float) -> void:
	if _bubble == null:
		_bubble = SettlerBubble.new()
		_bubble.position = Vector2(0.0, -float(_rig.get("height", 54)) - 10.0)
		add_child(_bubble)
	_bubble.show_text(text, seconds)


## The point on the inside of the light's edge, in the direction the creatures gather (`TownManager.alert_angle`).
func _alert_target() -> Vector2:
	var dir: Vector2 = Vector2.from_angle(town.alert_angle)
	var edge: Vector2 = town.dark_edge(town.center + dir * 900.0, town.center, 0.0)
	if edge.distance_to(town.center) > 800.0:
		edge = town.center + dir * 200.0
	return edge - dir * 22.0


func _alert_start(mode: int, target: Vector2) -> void:
	_alert_route = town.walk_route(global_position, target)
	if _alert_route.size() < 2:
		_alert_route = PackedVector2Array([global_position, target])
	_alert_d = 0.0
	_alert_mode = mode
	_alert_sector = Adventurer.sector_of(Vector2.from_angle(town.alert_angle))


## A resident with `alert_watch` (Valdric) leaves his plan while the town's light is in alarm, walks to the edge where the dark gathers, stands there and goes back afterwards.
func _alert_step(delta: float, plan_pos: Vector2) -> void:
	var watching: bool = town != null and town.alert_on and bool(spec.get("alert_watch", false)) and _arrive_t < 0.0 and not _talking
	match _alert_mode:
		0, 3:
			if watching:
				_alert_start(1, _alert_target())
		1, 2:
			if not watching:
				_alert_start(3, plan_pos)
	if _alert_mode == 0:
		return
	if _alert_mode == 2:
		global_position = _alert_route[_alert_route.size() - 1]
		return
	_alert_d += ALERT_SPEED * delta
	if _alert_d >= _length(_alert_route):
		if _alert_mode == 1:
			_alert_mode = 2
			global_position = _alert_route[_alert_route.size() - 1]
		else:
			_alert_mode = 0
		return
	global_position = _along(_alert_route, _alert_d)


# ---------- talking ----------

func _local_player() -> Player:
	return town.local_player() if town != null else null


func prompt() -> String:
	if not visible or _arrive_t >= 0.0 or _talking or InputManager.ui_blocking or town == null or not town.residents.has(sid):
		return ""
	return "HANDWERK" if is_working() and int((town.residents[sid] as Dictionary).get("talked", -1)) == TimeManager.day else "ANSPRECHEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 8.0


func prompt_position() -> Vector2:
	return Vector2(0.0, -float(_rig.get("height", 54)) - 8.0) ## the rig may name the figure's height in px


func trust_tier() -> int:
	var tiers: Array = spec.get("talk", []) as Array
	var trust: int = town.trust_of(sid)
	var tier: int = 0
	for i: int in tiers.size():
		if trust >= int((tiers[i] as Dictionary).get("trust", 0)):
			tier = i
	return tier


func interact(player: Player) -> void:
	if _talking or not town.residents.has(sid):
		return
	if spec.has("chat"):
		_chat(player)
		return
	_talking = true
	_sector = Adventurer.sector_of(player.global_position - global_position)
	var fresh_day: bool = int((town.residents[sid] as Dictionary).get("talked", -1)) != TimeManager.day
	if fresh_day:
		town.request_talk(sid)
		var tiers: Array = spec.get("talk", []) as Array
		if not tiers.is_empty():
			var box: DialogueBox = DialogueBox.find(player)
			if box != null:
				box.start(String((tiers[trust_tier()] as Dictionary).dialogue))
				await box.finished
	elif not is_working():
		var barks: Array = spec.get("barks", []) as Array
		var speech: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
		if speech != null and not barks.is_empty():
			speech.speak(String(spec.name), String(barks[randi() % barks.size()]))
	var ready_order: bool = false
	for order: Variant in town.orders:
		ready_order = ready_order or bool((order as Dictionary).done)
	if (is_working() or (ready_order and visible)) and spec.has("shop"): ## at the bench, or on a break when a finished piece waits for you
		ShopWindow.open(get_tree(), player, town, String(spec.shop))
	_talking = false


## E at a settler with `chat`: they turn to you and say one line, always (the first talk of a day still builds trust). Which one: with the current quest step's own lines
## it is often one of those, otherwise (or besides) one of the place they stand at, of the night, of anything; never the same twice in a row.
func _chat(player: Player) -> void:
	_talking = true
	_sector = Adventurer.sector_of(player.global_position - global_position)
	if int((town.residents[sid] as Dictionary).get("talked", -1)) != TimeManager.day:
		town.request_talk(sid)
	var line: String = _chat_line(player)
	var speech: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if speech != null and line != "":
		await speech.speak(String(spec.name), line)
	_talking = false


func _chat_line(player: Player) -> String:
	var chat: Dictionary = spec.chat as Dictionary
	var pools: Array = []
	var step: String = String(player.quests.current().get("step_id", "")) if player.quests != null else ""
	var for_step: Array = (chat.get("quest", {}) as Dictionary).get(step, []) as Array
	if not for_step.is_empty():
		pools.append([for_step, 4])
	var for_spot: Array = (chat.get("spot", {}) as Dictionary).get(_spot, []) as Array
	if not for_spot.is_empty():
		pools.append([for_spot, 2])
	var for_night: Array = chat.get("night", []) as Array
	if TimeManager.is_night() and not for_night.is_empty():
		pools.append([for_night, 3])
	pools.append([chat.get("any", []) as Array, 2])
	var total: int = 0
	for pool: Array in pools:
		total += int(pool[1]) if not (pool[0] as Array).is_empty() else 0
	if total <= 0:
		return ""
	var roll: int = randi() % total
	var picked: Array = []
	for pool: Array in pools:
		if (pool[0] as Array).is_empty():
			continue
		roll -= int(pool[1])
		if roll < 0:
			picked = pool[0] as Array
			break
	var line: String = String(picked[randi() % picked.size()])
	if picked.size() > 1 and line == _last_line:
		line = String(picked[(picked.find(line) + 1) % picked.size()])
	_last_line = line
	return line
