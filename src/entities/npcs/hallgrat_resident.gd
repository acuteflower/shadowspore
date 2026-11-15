class_name HallgratResident
extends Interactable
## One of Hallgrat's people (docs/hallgrat_bewohner_konzept.md). `HallgratPeople` moves it every frame from the pure plan state (walking
## along the town's net, standing at its spot with the spot's clip, gone while it is inside). The picture is the resident's sheet in the
## settlers' format (`py -3 tools/art_hallgrat_people.py` -> assets/characters/hallgrat_<id>.png + _glow, data/hallgrat_<id>_rig.json).
## E is the same as with Gustav or the witches: the first talk of a day builds trust (`TownManager.request_talk`, settlers.json entry with
## `away` true), a `chat` line in a bubble, then the shop (`shop`) or the hand-in of a board notice. The town knows the figure as a person
## (`register_person`) and its shop's role as valid next to it (`register_outpost`, updated while it walks).
## Reactions to the players (step 4, local and cosmetic, never the place): standing people look at someone who comes near, greet them once
## (a wave and a word when they know her, a look and a murmur when she is a stranger), step aside a few pixels when she walks into them,
## start at a sprint or a swung blade close by, and say something when she is badly hurt or when the rain begins.
## Sounds (data/hallgrat_people.json `sounds`, `py -3 tools/audio_hallgrat_people.py`): work clips sound on their frames (chisel, grinding wheel,
## broom, lantern, cloth, mug), voices now and then (Hedda hums, market vendors call by day); only near a local player, at most `max` at once.

const REACH: float = 26.0
const LOOK_RANGE: float = 64.0
const GREET_RANGE: float = 46.0
const STARTLE_RANGE: float = 80.0
const LOOKS_AT: Array[String] = ["idle", "talk", "sit", "serve", "guard"] ## clips during which someone turns to look

var id: String = ""
var reflect_moving: bool = true ## WaterReflections: checked every rebuild, residents walk
var spec: Dictionary = {} ## the plan's entry (data/hallgrat_people.json)
var settler: Dictionary = {} ## the person's entry (data/settlers.json)
var moving: bool = false
var inside: bool = false
var spot: String = ""
var _rig: Dictionary = {}
var _sprite: Sprite2D
var _glow: Sprite2D
var _clip: String = "idle"
var _clip_time: float = 0.0
var _sector: int = 2
var _time: float = 0.0
var _talking: bool = false
var _turned: float = 0.0 ## seconds it keeps facing whoever spoke to it
var _town: TownManager
var _role: String = ""
var _last_line: String = ""
var walk_clip: String = "walk" ## townsfolk with a load walk with it ("carry")
var _feet: Vector2 = Vector2.ZERO ## the sprite's own offset; dodging and starting move it a little
var _greeted: float = 0.0 ## seconds until it greets again
var _startle: float = 0.0 ## the little jump
var _startle_cd: float = 0.0
var _hurt_cd: float = 0.0
var _wave: float = 0.0
var _dodge: Vector2 = Vector2.ZERO
var _was_raining: bool = false
var _bubble: SettlerBubble
var _last_frame: int = -1 ## the clip frame that last sounded
var _voice_cd: float = -1.0
static var sounds_played: int = 0 ## tests
static var _playing: int = 0
static var _streams: Dictionary = {}


func setup(resident_id: String, data: Dictionary) -> void:
	id = resident_id
	spec = data
	name = "Resident_" + id
	settler = DataRegistry.get_entry("settlers", id)
	add_to_group("quest_actors")
	var art: String = "hallgrat_" + id
	var rig_path: String = "res://data/%s_rig.json" % art
	if FileAccess.file_exists(rig_path):
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
	_feet = sprite.position
	add_child(sprite)
	return sprite


## Takes a state of `HallgratPeople.state_at`.
func apply(state: Dictionary, delta: float = 0.0) -> void:
	_time += delta
	_turned = maxf(_turned - delta, 0.0)
	var pos: Vector2 = state.get("pos", Vector2.INF) as Vector2
	inside = bool(state.get("inside", false)) or not pos.is_finite()
	visible = not inside
	if inside:
		return
	moving = bool(state.get("moving", false))
	spot = String(state.get("spot", ""))
	position = pos.round()
	var clips: Dictionary = _rig.get("clips", {}) as Dictionary
	var clip: String = walk_clip if moving else String(state.get("clip", "idle"))
	if moving and bool(state.get("fast", false)) and clips.has("run") and walk_clip == "walk":
		clip = "run"
	if _turned > 0.0 and not moving:
		clip = "talk" if _talking else "idle"
	elif moving:
		_sector = Adventurer.sector_of(state.get("dir", Vector2.DOWN) as Vector2)
	else:
		_sector = Adventurer.sector_of(state.get("face", Vector2.DOWN) as Vector2)
	clip = _react(clip, state, delta)
	if not (_rig.get("clips", {}) as Dictionary).has(clip):
		clip = "idle"
	if clip != _clip:
		_clip = clip
		_clip_time = 0.0
		_last_frame = -1
	_clip_time += delta
	_show()
	_sounds(delta)
	_meet_town()


## The players nearby (local and cosmetic): look, greet, step aside, start, worry. Returns the clip to show.
func _react(clip: String, state: Dictionary, delta: float) -> String:
	_greeted = maxf(_greeted - delta, 0.0)
	_startle = maxf(_startle - delta, 0.0)
	_startle_cd = maxf(_startle_cd - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	_wave = maxf(_wave - delta, 0.0)
	var me: Player = _nearest_player()
	var push: Vector2 = Vector2.ZERO
	var raining: bool = bool(state.get("sheltered", false)) or (moving and bool(state.get("fast", false)) and WeatherManager.sky_wet())
	if raining and not _was_raining and randf() < 0.25:
		_say("rain", 2.4)
	_was_raining = raining
	if me != null and _talking == false:
		var d: Vector2 = me.global_position - global_position
		var dist: float = d.length()
		if dist < STARTLE_RANGE and _startle_cd <= 0.0 and (me.sprinting and dist < 34.0 or me.attack != null and me.attack.is_swinging()):
			_startle = 0.32
			_startle_cd = 7.0
			_sector = Adventurer.sector_of(d)
			if randf() < 0.5:
				_say("startle", 2.0)
		if moving and dist < 22.0: ## step aside: a sideways shift, the plan keeps its place
			var dir: Vector2 = state.get("dir", Vector2.DOWN) as Vector2
			var side: Vector2 = dir.orthogonal()
			push = side * (8.0 if side.dot(-d) > 0.0 else -8.0)
		if not moving and dist < LOOK_RANGE and clip in LOOKS_AT:
			_sector = Adventurer.sector_of(d)
		if dist < GREET_RANGE and _greeted <= 0.0:
			_greeted = 45.0
			_greet()
		if dist < 70.0 and _hurt_cd <= 0.0 and me.health != null and me.health.current > 0.0 and me.health.current < me.health.max_health * 0.3:
			_hurt_cd = 70.0
			_say("hurt", 2.6)
	_dodge = _dodge.move_toward(push, 30.0 * delta)
	if _sprite != null:
		var hop: float = -sin(_startle / 0.32 * PI) * 4.0 if _startle > 0.0 else 0.0
		_sprite.position = _feet + _dodge.round() + Vector2(0, round(hop))
		if _glow != null:
			_glow.position = _sprite.position
	if _wave > 0.0 and not moving:
		return "wave"
	return clip


func _nearest_player() -> Player:
	var best: Player = null
	var best_d: float = STARTLE_RANGE
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < best_d:
			best = p
			best_d = p.global_position.distance_to(global_position)
	return best


## A greeting: a wave and a friendly word from someone who knows her, a look and a murmur from a stranger now and then.
func _greet() -> void:
	if knows_her():
		if not moving:
			_wave = 1.3
		if randf() < 0.5:
			_say("greet_known", 2.2)
	elif randf() < 0.35:
		_say("greet_stranger", 2.0)


## Whether this figure knows the local player: a core figure she has talked to.
func knows_her() -> bool:
	return _town != null and _town.has_met(id)


func _say(pool: String, seconds: float) -> void:
	var lines: Array = (DataRegistry.table("hallgrat_people").get("reactions", {}) as Dictionary).get(pool, []) as Array
	if lines.is_empty() or _talking:
		return
	if _bubble == null:
		_bubble = SettlerBubble.new()
		_bubble.position = Vector2(0.0, -float(_rig.get("height", 56)) - 10.0)
		add_child(_bubble)
	_bubble.show_text(String(lines[randi() % lines.size()]), seconds)


## The sounds of what it does: a work clip sounds on its frames, a voice now and then. Only when a local player can hear it.
func _sounds(delta: float) -> void:
	var cfg: Dictionary = DataRegistry.table("hallgrat_people").get("sounds", {}) as Dictionary
	if cfg.is_empty() or _talking:
		return
	var hear: float = _hearing()
	var clip_cfg: Dictionary = (cfg.get("clips", {}) as Dictionary).get(_clip, {}) as Dictionary
	if not clip_cfg.is_empty() and not moving:
		var clip: Dictionary = (_rig.get("clips", {}) as Dictionary).get(_clip, {}) as Dictionary
		var count: int = maxi(int(clip.get("count", 1)), 1)
		var step: int = int(_clip_time * float(clip.get("fps", 8)))
		var frame: int = step % count
		if frame != _last_frame:
			_last_frame = frame
			var once_done: bool = bool(clip_cfg.get("once", false)) and step >= count
			if float(frame) in (clip_cfg.get("frames", []) as Array) and not once_done and randf() <= float(clip_cfg.get("chance", 1.0)):
				_play(cfg, clip_cfg, hear)
	for voice: Dictionary in cfg.get("voices", []) as Array:
		if String(voice.get("who", id)) != id or String(voice.get("role", sound_role())) != sound_role():
			continue
		if not (_clip in (voice.get("clips", []) as Array)) or moving or (bool(voice.get("day", false)) and TimeManager.night_amount() > 0.5):
			continue
		var every: Array = voice.get("every", [30.0, 60.0]) as Array
		if _voice_cd < 0.0:
			_voice_cd = randf_range(0.2, 1.0) * float(every[1])
		_voice_cd -= delta
		if _voice_cd <= 0.0:
			_voice_cd = randf_range(float(every[0]), float(every[1]))
			_play(cfg, voice, hear)


## The role whose voices it uses (townsfolk: their role; core figures match voices by `who`).
func sound_role() -> String:
	return ""


## The distance to the nearest local player, INF without one.
func _hearing() -> float:
	var best: float = INF
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority():
			best = minf(best, p.global_position.distance_to(global_position))
	return best


func _play(cfg: Dictionary, entry: Dictionary, hear: float) -> void:
	var reach: float = float(entry.get("range", 240.0))
	var files: Array = entry.get("files", []) as Array
	if files.is_empty() or hear > reach or _playing >= int(cfg.get("max", 8)):
		return
	var path: String = String(cfg.get("folder", "")) + String(files[randi() % files.size()]) + ".wav"
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream
	var stream: AudioStream = _streams[path] as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = float(entry.get("db", -12.0))
	player.max_distance = reach
	player.pitch_scale = randf_range(0.95, 1.05)
	add_child(player)
	_playing += 1
	sounds_played += 1
	player.tree_exiting.connect(_sound_gone.bind(player))
	player.play()
	get_tree().create_timer(stream.get_length() + 0.1).timeout.connect(player.queue_free) ## by its length: `finished` never comes without an audio device


func _sound_gone(player: AudioStreamPlayer2D) -> void:
	if player.has_meta("counted"):
		return
	player.set_meta("counted", true)
	_playing = maxi(_playing - 1, 0)


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
		_glow.modulate.a = 0.85 + 0.15 * sin(_time * 7.0)


## The town learns of the figure and of where its trade is valid; the place follows it while it walks.
func _meet_town() -> void:
	if _town == null:
		_town = get_tree().get_first_node_in_group("town") as TownManager if is_inside_tree() else null
		if _town == null:
			return
		_town.register_person(id, self)
		_role = String(_town.shop(String(settler.get("shop", ""))).get("role", ""))
	if _role != "":
		_town.register_outpost(_role, global_position)


func _exit_tree() -> void:
	if _town != null and is_instance_valid(_town) and _role != "":
		_town.clear_outpost(_role)


func _draw() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * Vector2(8.0, 2.8))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.26))


# ---------- E ----------

func prompt() -> String:
	if inside or _talking or InputManager.ui_blocking or _town == null or settler.is_empty():
		return ""
	if _town.board != null and not _town.board.finishable(id, _town.local_player()).is_empty():
		return "AUFTRAG ABGEBEN"
	var talked: bool = int((_town.residents.get(id, {}) as Dictionary).get("talked", -1)) == TimeManager.day
	return "HANDELN" if talked and settler.has("shop") else "ANSPRECHEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - REACH


func prompt_position() -> Vector2:
	return Vector2(0.0, -float(_rig.get("height", 56)) - 8.0)


func interact(player: Player) -> void:
	if _talking or _town == null:
		return
	_talking = true
	_turned = 5.0
	_sector = Adventurer.sector_of(player.global_position - global_position)
	var runner: BubbleRunner = BubbleRunner.find(player)
	var who: String = String(settler.get("name", id))
	if _town.board != null and not _town.board.finishable(id, player).is_empty(): ## the end of a board notice: report to the one who gave it
		var thanks: String = _town.board.report(id, player)
		if runner != null and thanks != "":
			await runner.say_line(who, thanks, self)
		_talking = false
		return
	var fresh_day: bool = int((_town.residents.get(id, {}) as Dictionary).get("talked", -1)) != TimeManager.day
	if fresh_day:
		_town.request_talk(id)
		var line: String = chat_line()
		if runner != null and line != "":
			await runner.say_line(who, line, self)
	if settler.has("shop") and is_inside_tree() and not inside:
		_town.register_outpost(_role, global_position)
		ShopWindow.open(get_tree(), player, _town, String(settler.shop))
	_talking = false


## `quest_actors`: where the figure stands, for a quest step whose `actor` is its id.
func actor_position(who: String) -> Vector2:
	return global_position if who == id and is_inside_tree() and not inside else Vector2.INF


## One line of its `chat` (placeholders for the dialogue writer): of the spot it is at, of the night, of anything; never the same twice in a row.
func chat_line() -> String:
	var chat: Dictionary = settler.get("chat", {}) as Dictionary
	var pool: Array = []
	pool.append_array((chat.get("spot", {}) as Dictionary).get(spot, []) as Array)
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
