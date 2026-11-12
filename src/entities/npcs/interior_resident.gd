class_name InteriorResident
extends Interactable
## Somebody who lives in an interior instead of the town (the witch in her tower room): data/settlers.json entry with `away` true, placed by `Interior` from
## the room's `resident` key. Like a `Settler` they are no network object: where they stand and what they do is a pure function of the clock and their plan
## (`schedule` [[from, to, spot]], `spots` {at (room px), face, clip}; a change of place is a short walk at the start of the slot, by way of `hub` when the spot
## says `via_hub`). E talks to them (the first talk of a day builds trust through `TownManager.request_talk`, they say a `chat` line) and opens their shop
## (`shop`: `ShopWindow`, data/shops.json). The town knows them as a person (`TownManager.register_person`) and their room as a place where their trade is
## valid (`register_outpost`, the shop's `role`). Art: assets/characters/<art>.png (+ _glow) and data/<art>_rig.json, the settlers' format.

const WALK_SPEED: float = 26.0 ## px/s
const REACH: float = 72.0 ## she is spoken to across her counter (it is solid over its whole depth: her feet and the customer's are ~60 px apart)

var sid: String = ""
var spec: Dictionary = {}
var room: Node2D ## the Interior she lives in
var _rig: Dictionary = {}
var _sprite: Sprite2D
var _glow: Sprite2D
var _clip: String = "idle"
var _clip_time: float = 0.0
var _sector: int = 2
var _time: float = 0.0
var _talking: bool = false
var _turned: float = 0.0 ## seconds she keeps facing whoever spoke to her
var _town: TownManager
var _last_line: String = ""
var _spot: String = ""


func setup(inside: Node2D, settler_id: String) -> void:
	room = inside
	sid = settler_id
	add_to_group("quest_actors") ## quest steps with `actor` = her id find her (the Spiegelhexe quest: "SPRICH MIT DER HEXE")
	name = settler_id.capitalize()
	spec = DataRegistry.get_entry("settlers", sid)
	var art: String = String(spec.get("art", sid))
	var rig_path: String = "res://data/%s_rig.json" % art
	if FileAccess.file_exists(rig_path):
		_rig = JSON.parse_string(FileAccess.get_file_as_string(rig_path)) as Dictionary
		_sprite = _sheet("res://assets/characters/%s.png" % art)
		if ResourceLoader.exists("res://assets/characters/%s_glow.png" % art):
			_glow = _sheet("res://assets/characters/%s_glow.png" % art)
			_glow.material = Unlit.material()
	_apply(TimeManager.time_of_day, 0.0)


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


func _vec(raw: Variant) -> Vector2:
	var a: Array = raw as Array
	return Vector2(float(a[0]), float(a[1]))


func _spot_at(id: String) -> Vector2:
	return _vec(((spec.get("spots", {}) as Dictionary).get(id, {}) as Dictionary).get("at", [0, 0]))


## The slot of the plan the time `t` (0..1 of the day) lies in: {spot, since (of a day, how long it has run), prev (the spot before)}.
func plan_at(t: float) -> Dictionary:
	var plan: Array = spec.get("schedule", []) as Array
	for i: int in plan.size():
		var slot: Array = plan[i] as Array
		var from: float = float(slot[0])
		var to: float = float(slot[1])
		var inside: bool = (t >= from and t < to) if from <= to else (t >= from or t < to)
		if inside:
			var prev: Array = plan[posmod(i - 1, plan.size())] as Array
			return {"spot": String(slot[2]), "since": fposmod(t - from, 1.0), "prev": String(prev[2])}
	return {"spot": String((plan[0] as Array)[2]) if not plan.is_empty() else "", "since": 1.0, "prev": ""}


## The way from one spot to the next (room px).
func _route(from_id: String, to_id: String) -> PackedVector2Array:
	var spots: Dictionary = spec.get("spots", {}) as Dictionary
	var route: PackedVector2Array = PackedVector2Array([_spot_at(from_id)])
	if spec.has("hub") and (bool((spots.get(from_id, {}) as Dictionary).get("via_hub", false)) or bool((spots.get(to_id, {}) as Dictionary).get("via_hub", false))):
		route.append(_vec(spec.hub))
	route.append(_spot_at(to_id))
	return route


## Where she is and what she plays at time `t`: walking in from the spot before during the slot's first moments, then at her spot with its clip.
func _apply(t: float, delta: float) -> void:
	var plan: Dictionary = plan_at(t)
	var spot: String = String(plan.spot)
	if spot == "":
		return
	_spot = spot
	var cfg: Dictionary = (spec.get("spots", {}) as Dictionary).get(spot, {}) as Dictionary
	var walked: float = float(plan.since) * TimeManager.DAY_LENGTH_SEC * WALK_SPEED
	var moving: bool = false
	if String(plan.prev) != "" and String(plan.prev) != spot:
		var route: PackedVector2Array = _route(String(plan.prev), spot)
		var left: float = walked
		for i: int in route.size() - 1:
			var leg: float = route[i].distance_to(route[i + 1])
			if left < leg:
				position = route[i].lerp(route[i + 1], left / maxf(leg, 0.01)).round()
				_sector = Adventurer.sector_of(route[i + 1] - route[i])
				moving = true
				break
			left -= leg
	var clip: String = "walk"
	if not moving:
		position = _spot_at(spot)
		clip = String(cfg.get("clip", "idle"))
		if _turned <= 0.0:
			_sector = Adventurer.sector_of(_vec(cfg.get("face", [0, 1])))
		elif _talking or _turned > 0.0:
			clip = "idle" if clip != "counter" else clip
	if clip != _clip:
		_clip = clip
		_clip_time = 0.0
	_clip_time += delta
	_show()


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
		_glow.modulate.a = 0.8 + 0.2 * sin(_time * 5.0)


func _draw() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * Vector2(9.0, 3.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.26))


func _process(delta: float) -> void:
	_time += delta
	_turned = maxf(_turned - delta, 0.0)
	if _town == null: ## the town is made after the rooms: it learns of her and of her room as soon as it is there
		_town = get_tree().get_first_node_in_group("town") as TownManager
		if _town != null:
			_town.register_person(sid, self)
			var shop: Dictionary = _town.shop(String(spec.get("shop", "")))
			if not shop.is_empty():
				_town.register_outpost(String(shop.get("role", "")), room.global_position + (room.get("size") as Vector2) / 2.0)
	_apply(TimeManager.time_of_day, delta)


## The settlers' question (the shop's "works only at the bench" note, production): she is at work whenever she is at one of her working spots.
func is_working() -> bool:
	return _clip in ["stir", "craft", "counter", "grind", "carve", "basin"]


# ---------- E ----------

func prompt() -> String:
	if _talking or InputManager.ui_blocking or _town == null or _clip == "walk":
		return ""
	if _quest_talk(_town.local_player()) != "":
		return "SPRECHEN"
	if _town.board != null and not _town.board.finishable(sid, _town.local_player()).is_empty():
		return "AUFTRAG ABGEBEN"
	var talked: bool = int((_town.residents.get(sid, {}) as Dictionary).get("talked", -1)) == TimeManager.day
	return "HANDELN" if talked and spec.has("shop") else "ANSPRECHEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - REACH


func prompt_position() -> Vector2:
	return Vector2(0.0, -float(_rig.get("height", 64)) - 8.0)


func interact(player: Player) -> void:
	if _talking or _town == null:
		return
	_talking = true
	_turned = 4.0
	_sector = Adventurer.sector_of(player.global_position - global_position)
	var talk: String = _quest_talk(player)
	if talk != "": ## a quest step wants this talk (the lake witch's meeting): the dialogue instead of the shop
		var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
		if world != null:
			await world.play_story_dialogue(player, talk, self)
		_talking = false
		return
	if _town.board != null and not _town.board.finishable(sid, player).is_empty(): ## the end of a board notice: report to the one who gave it
		var thanks: String = _town.board.report(sid, player)
		var runner: BubbleRunner = BubbleRunner.find(player)
		if runner != null and thanks != "":
			await runner.say_line(String(spec.get("name", sid)), thanks, self)
		_talking = false
		return
	var fresh_day: bool = int((_town.residents.get(sid, {}) as Dictionary).get("talked", -1)) != TimeManager.day
	if fresh_day:
		_town.request_talk(sid)
		var line: String = _chat_line()
		var runner: BubbleRunner = BubbleRunner.find(player)
		if runner != null and line != "":
			await runner.say_line(String(spec.get("name", sid)), line, self)
	if spec.has("shop") and is_inside_tree():
		ShopWindow.open(get_tree(), player, _town, String(spec.shop))
	_talking = false


## The dialogue a running quest step of `player` wants with her (the step's `talk_to` is her id, `talk` the dialogue), or "".
func _quest_talk(player: Player) -> String:
	if player == null or player.quests == null:
		return ""
	var table: Dictionary = DataRegistry.table("quests")
	for quest_id: String in player.quests.active_ids():
		var step_id: String = player.quests.active_step_id(quest_id)
		for raw: Variant in (table.get(quest_id, {}) as Dictionary).get("steps", []) as Array:
			var step: Dictionary = raw as Dictionary
			if String(step.get("id", "")) == step_id and String(step.get("talk_to", "")) == sid:
				return String(step.get("talk", ""))
	return ""


## `quest_actors`: where she stands, for a quest step whose `actor` is her id.
func actor_position(who: String) -> Vector2:
	return global_position if who == sid and is_inside_tree() else Vector2.INF


## One line of her `chat` (placeholders for the dialogue writer): of the spot she is at, of the night, of anything; never the same twice in a row.
func _chat_line() -> String:
	var chat: Dictionary = spec.get("chat", {}) as Dictionary
	var pool: Array = []
	pool.append_array((chat.get("spot", {}) as Dictionary).get(_spot, []) as Array)
	if TimeManager.is_night():
		pool.append_array(chat.get("night", []) as Array)
	pool.append_array(chat.get("any", []) as Array)
	if pool.is_empty():
		return ""
	var line: String = String(pool[randi() % pool.size()])
	if pool.size() > 1 and line == _last_line:
		line = String(pool[(pool.find(line) + 1) % pool.size()])
	_last_line = line
	return line
