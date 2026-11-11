class_name LootChest
extends Interactable
## A loot chest of the wild (docs/beutetruhen_konzept.md): Wurzelkiste (common), Mondsiegeltruhe (rare), Glutreliquiar (legendary).
## Art `py -3 tools/art_loot_chests.py`: a sheet of COLS frames (0 locked, 1 unlocked and shut, 2..8 the lid opening) + a glow sheet, anchors in
## data/loot_chest_art.json. The state belongs to `LootChests` (host); this node shows it: E (a hold for rare and legendary: SIEGEL BRECHEN /
## FESSELN LÖSEN) -> Ellie stoops (`Player.begin_pick`) -> `LootChests.request_open`; `play_open` runs the tier's opening on every peer from one
## clock, so everyone sees the same: rattle, seal / chains, the lid with a damped swing, rays, a pillar of light, shards, links, coins, motes.
## All effects are drawn as pixels on two unlit layers (`_fx` above, `_ground` under the chest). `arrive` = it falls out of a pillar of light first
## (a boss's chest, later the reward of a solved puzzle).

const DIR: String = "res://assets/props/chests/"
const SOUND_DIR: String = "res://assets/audio/chest/"
const COLORS: Dictionary = { ## tier -> [main, light, deep]
	"common": [Color("c9d4e8"), Color("ffffff"), Color("78f4e6")],
	"rare": [Color("5aa8ff"), Color("eaf8ff"), Color("4a5cff")],
	"legendary": [Color("ffb347"), Color("fff2cc"), Color("d2721c")],
}
const VOID: Color = Color("9468ee")
## Seconds after the opening began: the lock gives (frame 1), the lid starts, the lid's swing lasts.
const TIMES: Dictionary = {
	"common": {"lock": 0.12, "lid": 0.22, "swing": 0.55},
	"rare": {"lock": 0.6, "lid": 0.74, "swing": 0.6},
	"legendary": {"lock": 1.05, "lid": 1.5, "swing": 0.55},
}
const ARRIVE_TIME: float = 1.25 ## a chest that falls out of the light: seconds until it can be used
const LAND_AT: float = 0.62
const MAX_PARTS: int = 260
const BAYER: Array = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

var id: String = ""
var tier: String = "common"
var flip: bool = false
var arrive: bool = false ## set before it enters the tree: it comes down in a pillar of light
var opened: bool = false

var _art: Dictionary = {}
var _spec: Dictionary = {}
var _body: Sprite2D
var _glow: Sprite2D
var _fx: Node2D
var _ground: Node2D
var _light: NightLight
var _cols: int = 9
var _lid: Array = []
var _night: float = 0.0
var _time: float = 0.0
var _open_t: float = -1.0 ## seconds since the opening began (-1 = not opening)
var _arrive_t: float = 99.0
var _vanish_t: float = -1.0
var _hold: float = 0.0 ## 0..1 of the local player's hold
var _holding: bool = false
var _strain: float = 0.0 ## shown tension (hold or opening)
var _parts: Array[Dictionary] = []
var _rings: Array[Dictionary] = [] ## {age, life, r, c}: shock rings on the ground
var _flashes: Array[Dictionary] = [] ## {p, age, life, r, c}
var _emit: float = 0.0
var _glint: float = 0.0
var _events: Dictionary = {} ## names of the opening's moments already played
var _main: Color
var _light_col: Color
var _deep: Color


func _ready() -> void:
	add_to_group("night_lights")
	add_to_group("loot_chest_nodes")
	_art = DataRegistry.table("loot_chest_art").get(tier, {}) as Dictionary
	var chests: LootChests = LootChests.of(get_tree())
	_spec = chests.tier(tier) if chests != null else (DataRegistry.table("loot_chests").tiers as Dictionary).get(tier, {}) as Dictionary
	var pal: Array = COLORS.get(tier, COLORS.common) as Array
	_main = pal[0]
	_light_col = pal[1]
	_deep = pal[2]
	_cols = int(_art.get("cols", 9))
	_lid = _art.get("lid", []) as Array
	var frame: Array = _art.get("frame", [56, 50]) as Array
	var ground_row: float = float(_art.get("ground", 41))
	_ground = Node2D.new()
	_ground.z_index = -1
	_ground.material = Unlit.material()
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_body = Sprite2D.new()
	_body.texture = load(DIR + "chest_%s.png" % tier) as Texture2D
	_body.hframes = _cols
	_body.offset = Vector2(0, -(ground_row - float(frame[1]) / 2.0))
	_body.flip_h = flip
	add_child(_body)
	_glow = Sprite2D.new()
	_glow.texture = load(DIR + "chest_%s_glow.png" % tier) as Texture2D
	_glow.hframes = _cols
	_glow.offset = _body.offset
	_glow.flip_h = flip
	_glow.material = Unlit.material()
	_body.add_child(_glow)
	_fx = Node2D.new()
	_fx.z_index = 3
	_fx.material = Unlit.material()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_light = NightLight.new()
	_light.radius = {"common": 22, "rare": 32, "legendary": 46}.get(tier, 24) as int
	_light.base_energy = {"common": 0.45, "rare": 0.75, "legendary": 0.95}.get(tier, 0.5) as float
	_light.glow_color = _main
	_light.position = Vector2(0, -4)
	add_child(_light)
	var foot: Array = _art.get("foot", [26, 9]) as Array
	var solid: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(float(foot[0]) - 4.0, float(foot[1]))
	shape.shape = box
	shape.position = Vector2(0, -float(foot[1]) * 0.5 + 1.0)
	solid.add_child(shape)
	add_child(solid)
	_set_col(0)
	if arrive:
		_arrive_t = 0.0
		_body.position.y = -96.0
		_body.modulate.a = 0.0


# ---------------------------------------------------------------- anchors

## Px from the feet of an anchor of the art data (mirrored with the chest).
func anchor(key: String) -> Vector2:
	var v: Array = _art.get(key, [0, 0]) as Array
	if v.is_empty():
		return Vector2.ZERO
	return Vector2(-float(v[0]) if flip else float(v[0]), float(v[1]))


func anchors(key: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v: Variant in _art.get(key, []) as Array:
		var a: Array = v as Array
		out.append(Vector2(-float(a[0]) if flip else float(a[0]), float(a[1])))
	return out


## Where the loot springs from (px from the feet).
func mouth() -> Vector2:
	if _art.is_empty():
		_art = DataRegistry.table("loot_chest_art").get(tier, {}) as Dictionary
	return anchor("mouth")


# ---------------------------------------------------------------- interaction

func prompt() -> String:
	if opened or _open_t >= 0.0 or _arrive_t < ARRIVE_TIME or _vanish_t >= 0.0:
		return ""
	return String(_spec.get("prompt", "ÖFFNEN"))


func reach_distance(from: Vector2) -> float:
	var foot: Array = _art.get("foot", [26, 9]) as Array
	return from.distance_to(global_position + Vector2(0, -3)) - float(foot[0]) * 0.42


func prompt_position() -> Vector2:
	return Vector2(0, anchor("lid_top").y - 16.0)


func interact(player: Player) -> void:
	if prompt() == "" or player.is_busy() or player.health.current <= 0.0:
		return
	if float(_spec.get("hold", 0.0)) <= 0.0:
		_begin(player)
	else:
		_holding = true
		_sound("hold_" + tier, -6.0)


## The hold is full (or not needed): she stoops and lays her hand on the lid; the host decides when it closes.
func _begin(player: Player) -> void:
	_holding = false
	var dir: Vector2 = (global_position - player.global_position).normalized()
	var chest_id: String = id
	player.begin_pick(dir, func() -> void:
		var chests: LootChests = LootChests.of(get_tree())
		if chests != null:
			chests.request_open(chest_id))


func _update_hold(delta: float) -> void:
	var hold_time: float = float(_spec.get("hold", 0.0))
	if not _holding or hold_time <= 0.0:
		_hold = maxf(_hold - delta * 2.0, 0.0)
		return
	var me: Player = _local_player()
	var ok: bool = me != null and me.health.current > 0.0 and not me.is_busy() and InputManager.interact_held() and not InputManager.ui_blocking \
		and reach_distance(me.global_position) <= Interactable.INTERACT_RANGE + 8.0 and prompt() != ""
	if not ok:
		_holding = false
		return
	_hold = minf(_hold + delta / hold_time, 1.0)
	if _hold >= 1.0:
		_begin(me)


func _local_player() -> Player:
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			return player
	return null


# ---------------------------------------------------------------- state from LootChests

## Every peer: the host opened it; `mine` = the local player did.
func play_open(_mine: bool) -> void:
	if opened:
		return
	opened = true
	_holding = false
	_open_t = 0.0
	_events.clear()


## A save or a late join: it stands open, no show.
func set_open_instant() -> void:
	opened = true
	_open_t = 99.0
	_holding = false
	_hold = 0.0
	_set_col(_cols - 1)
	_arrive_t = 99.0
	_body.position = Vector2.ZERO
	_body.modulate.a = 1.0


## Every peer: a piece of the loot just sprang out (rank 0 common .. 4 legendary).
func spring_fx(rank: int) -> void:
	var m: Vector2 = mouth()
	var col: Color = _rarity_color(rank)
	for i: int in 6 + rank * 2:
		var a: float = -PI * 0.5 + randf_range(-1.1, 1.1)
		_part(m, Vector2.from_angle(a) * randf_range(20.0, 55.0), col.lightened(randf() * 0.4), randf_range(0.4, 0.8), 1, 80.0)
	_flashes.append({"p": m, "age": 0.0, "life": 0.22, "r": 5.0 + rank * 1.5, "c": col})
	_sound("pop", -4.0, 0.9 + rank * 0.08)
	if rank >= 3:
		_sound("sparkle", -6.0)


## Every peer: fades away (an opened boss or test chest after a while).
func vanish() -> void:
	if _vanish_t < 0.0:
		_vanish_t = 0.0


func _rarity_color(rank: int) -> Color:
	var keys: Array = DataRegistry.table("rarities").keys()
	var key: String = String(keys[clampi(rank, 0, keys.size() - 1)])
	return Color(String((DataRegistry.table("rarities")[key] as Dictionary).get("color", "#ffffff")))


# ---------------------------------------------------------------- the clock

func _process(delta: float) -> void:
	_time += delta
	_update_hold(delta)
	if _arrive_t < ARRIVE_TIME:
		_update_arrive(delta)
	if _open_t >= 0.0 and _open_t < 6.0:
		_open_t += delta
		_update_open()
	else:
		var target: float = _hold
		_strain = move_toward(_strain, target, delta * 4.0)
		var amp: float = _strain * (1.5 if tier == "legendary" else 1.0)
		_body.position.x = roundf(sin(_time * 55.0) * amp) if _strain > 0.15 else 0.0
	if _vanish_t >= 0.0:
		_vanish_t += delta
		modulate.a = clampf(1.0 - _vanish_t / 1.4, 0.0, 1.0)
		if _vanish_t > 0.2 and randf() < 0.5:
			_part(Vector2(randf_range(-16, 16), randf_range(-14, 0)), Vector2(0, -randf_range(10, 26)), _main, 1.2, 0, 0.0)
		if _vanish_t >= 1.6:
			queue_free()
	_ambient(delta)
	_step_parts(delta)
	_update_glow()
	_fx.queue_redraw()
	_ground.queue_redraw()


func _update_glow() -> void:
	var base: float = lerpf(0.4, 1.0, _night)
	var breath: float = 0.86 + 0.14 * sin(_time * (1.6 if tier == "legendary" else 1.1))
	var a: float = base * breath
	if opened and _open_t > 3.0:
		a *= 0.6
	_glow.modulate.a = clampf(a + _strain * 0.6, 0.0, 1.0)
	if tier == "legendary" and not opened:
		_glow.self_modulate = Color.WHITE.lerp(Color(1.7, 1.25, 0.55), _strain) ## the chains' violet veins turn to gold under her hands
	elif tier == "rare" and not opened:
		_glow.self_modulate = Color(1.0 + _strain * 0.7, 1.0 + _strain * 0.7, 1.0 + _strain * 0.5)
	else:
		_glow.self_modulate = Color.WHITE


func set_night(amount: float) -> void:
	_night = amount


func _set_col(col: int) -> void:
	_body.frame = clampi(col, 0, _cols - 1)
	_glow.frame = _body.frame


# ---------------------------------------------------------------- the opening

func _once(name: String, at: float) -> bool:
	if _open_t >= at and not _events.has(name):
		_events[name] = true
		return true
	return false


func _update_open() -> void:
	var times: Dictionary = TIMES.get(tier, TIMES.common) as Dictionary
	var t: float = _open_t
	var lock_at: float = float(times.lock)
	var lid_at: float = float(times.lid)
	# the frame: locked, unlocked, then a lid with a damped swing round its full angle
	if t < lock_at:
		_set_col(0)
	elif t < lid_at:
		_set_col(1)
	else:
		var u: float = (t - lid_at) / float(times.swing)
		var full: float = float(_lid[_cols - 1]) if _lid.size() >= _cols else 110.0
		var angle: float = full * (1.0 - exp(-4.2 * u) * cos(7.5 * u)) if u < 2.2 else full
		_set_col(_col_for(minf(angle, full)))
	# tension before the lock gives
	if t < lock_at:
		_strain = clampf(t / maxf(lock_at, 0.01), 0.0, 1.0) * (1.0 if tier != "common" else 0.4)
		_body.position.x = roundf(sin(t * 62.0) * (0.5 + _strain * 1.6)) if tier != "common" or t > 0.04 else 0.0
	else:
		_strain = move_toward(_strain, 0.0, 0.05)
		_body.position.x = 0.0
	match tier:
		"common":
			_open_common(t)
		"rare":
			_open_rare(t)
		_:
			_open_legendary(t)
	# inside light breathing out of the open chest for a while
	if t > lid_at + 0.2 and randf() < 0.18:
		var m: Vector2 = mouth()
		_part(m + Vector2(randf_range(-10, 10), randf_range(-2, 2)), Vector2(randf_range(-4, 4), -randf_range(12, 26)), _main.lerp(_light_col, randf() * 0.5), randf_range(0.8, 1.5), 0, -6.0)


func _col_for(angle: float) -> int:
	if angle < 2.5:
		return 1
	var best: int = 2
	for c: int in range(2, _cols):
		if absf(float(_lid[c]) - angle) < absf(float(_lid[best]) - angle):
			best = c
	return best


func _open_common(t: float) -> void:
	var m: Vector2 = mouth()
	if _once("latch", 0.0):
		_sound("latch", -3.0)
	if _once("lock", 0.12):
		var lock: Vector2 = anchor("lock")
		for i: int in 5:
			_part(lock, Vector2(randf_range(-30, 30), randf_range(-40, -10)), Color("a05c3a"), 0.6, 2, 140.0, 4.0)
	if _once("creak", 0.2):
		_sound("creak", -2.0)
	if _once("burst", 0.5):
		_sound("thud_small", -4.0)
		for i: int in 12: ## dust from the seam
			var a: float = randf() * TAU
			_part(m + Vector2(cos(a) * 12.0, 0), Vector2(cos(a) * randf_range(10, 26), -randf_range(4, 16)), Color(0.82, 0.76, 0.66, 0.8), randf_range(0.5, 0.9), 0, -10.0)
		for i: int in 10: ## seed fluff and silver motes
			_part(m + Vector2(randf_range(-8, 8), 0), Vector2(randf_range(-14, 14), -randf_range(22, 44)), _main if i % 2 else _deep, randf_range(0.9, 1.6), 0, -4.0)
		_flashes.append({"p": m, "age": 0.0, "life": 0.3, "r": 8.0, "c": _light_col})
		_shake(1.2, 260.0)


func _open_rare(t: float) -> void:
	var lock: Vector2 = anchor("lock")
	var m: Vector2 = mouth()
	if _once("hum", 0.0):
		_sound("seal_hum", -2.0)
	if t < 0.6 and randf() < 0.6: ## light gathers into the seal
		var a: float = randf() * TAU
		var from: Vector2 = lock + Vector2(cos(a), sin(a) * 0.6) * randf_range(14, 24)
		_part(from, (lock - from) * 2.6, _light_col, 0.38, 0, 0.0)
	if _once("crack", 0.6):
		_sound("seal_crack", 0.0)
		_flashes.append({"p": lock, "age": 0.0, "life": 0.35, "r": 12.0, "c": Color.WHITE})
		for i: int in 18:
			var a2: float = randf() * TAU
			_part(lock, Vector2(cos(a2), sin(a2) * 0.8 - 0.4) * randf_range(40, 95), _main.lerp(_light_col, randf()), randf_range(0.5, 0.9), 2, 160.0, 6.0)
		_shake(1.6, 280.0)
	if _once("lid", 0.74):
		_sound("lid_rare", -2.0)
	if _once("burst", 1.0):
		_sound("burst_rare", 0.0)
		_flashes.append({"p": m, "age": 0.0, "life": 0.45, "r": 16.0, "c": _light_col})
		_rings.append({"age": 0.0, "life": 0.7, "r": 34.0, "c": _main})
		for i: int in 26: ## moon motes spiralling up
			var a3: float = TAU * i / 26.0
			_part(m + Vector2(cos(a3) * 6.0, 0), Vector2(cos(a3) * 18.0, -randf_range(40, 70)), _main.lerp(_light_col, randf()), randf_range(1.0, 1.8), 3, -8.0, 0.0, a3)
		_banner()
		_shake(2.4, 300.0)


func _open_legendary(t: float) -> void:
	var m: Vector2 = mouth()
	var chain: Array[Vector2] = _chain_points()
	if _once("strain", 0.0):
		_sound("chain_strain", 0.0)
	if t < 1.05 and randf() < 0.75 and not chain.is_empty(): ## sparks along the chains, violet turning gold
		var p: Vector2 = chain[randi() % chain.size()]
		_part(p, Vector2(randf_range(-20, 20), -randf_range(10, 40)), VOID.lerp(_main, clampf(t / 1.05, 0.0, 1.0)), 0.45, 0, 60.0)
		if randf() < 0.1:
			_shake(0.6 + t, 240.0)
	if _once("snap", 1.05):
		_sound("chain_snap", 1.0)
		for p2: Vector2 in chain: ## the links fly
			for k: int in 2:
				var away: Vector2 = (p2 - Vector2(0, -12)).normalized()
				_part(p2, (away + Vector2(randf_range(-0.5, 0.5), -0.6)) * randf_range(50, 110), Color("4e4a66") if k == 0 else _main, randf_range(0.6, 1.1), 2, 210.0, 8.0)
		_flashes.append({"p": anchor("chain_cross"), "age": 0.0, "life": 0.3, "r": 16.0, "c": _light_col})
		_shake(3.5, 360.0)
	if _once("silence", 1.15):
		_sound("gem_swell", -3.0)
	if _once("blast", 1.5):
		_sound("boom", 2.0)
		_sound("choir", -2.0)
		_rings.append({"age": 0.0, "life": 0.9, "r": 60.0, "c": _main})
		_rings.append({"age": -0.12, "life": 0.9, "r": 44.0, "c": _light_col})
		_flashes.append({"p": m, "age": 0.0, "life": 0.6, "r": 26.0, "c": Color.WHITE})
		_shake(6.0, 420.0)
	if _once("coins", 1.58):
		_sound("coins", -2.0)
		for i: int in 34: ## a fountain of coins
			_part(m + Vector2(randf_range(-6, 6), 0), Vector2(randf_range(-55, 55), -randf_range(70, 150)), Color("ffe08a") if i % 3 else Color("fff2cc"), randf_range(1.0, 1.6), 1, 260.0, randf_range(4.0, 14.0))
		_banner()


## Points along the legendary chains (for sparks and flying links): from the plinth up to the lid and down to the padlock.
func _chain_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var ends: Array[Vector2] = anchors("chain_ends")
	var top: Vector2 = anchor("lid_top")
	var cross: Vector2 = anchor("chain_cross")
	for e: Vector2 in ends:
		for k: int in 6:
			out.append(e.lerp(top + Vector2(e.x * 0.3, 0), k / 5.0))
		for k: int in 3:
			out.append(e.lerp(cross, 0.5 + k * 0.25))
	return out


func _banner() -> void:
	var text: String = String(_spec.get("banner", ""))
	if text != "":
		DamageNumber.spawn_text(get_tree().current_scene, global_position + Vector2(0, anchor("lid_top").y - 26.0), text, _main)


# ---------------------------------------------------------------- arriving out of the light

func _update_arrive(delta: float) -> void:
	_arrive_t += delta
	var t: float = _arrive_t
	var fall: float = clampf((t - 0.18) / (LAND_AT - 0.18), 0.0, 1.0)
	_body.position.y = roundf(-96.0 * (1.0 - fall * fall))
	_body.modulate.a = clampf((t - 0.12) / 0.25, 0.0, 1.0)
	if _arrive_t - delta < 0.01:
		_sound("descend", -2.0)
	if t >= LAND_AT and t - delta < LAND_AT:
		_sound("boom", 0.0)
		_rings.append({"age": 0.0, "life": 0.8, "r": 52.0, "c": _main})
		_flashes.append({"p": Vector2(0, -6), "age": 0.0, "life": 0.4, "r": 18.0, "c": _light_col})
		for i: int in 22:
			var a: float = randf() * TAU
			_part(Vector2(cos(a) * 14.0, sin(a) * 5.0), Vector2(cos(a) * randf_range(30, 70), sin(a) * randf_range(8, 20) - 10.0), Color(0.78, 0.74, 0.7, 0.85), randf_range(0.5, 0.9), 0, -14.0)
		_shake(4.5, 400.0)
	if t >= ARRIVE_TIME:
		_body.position = Vector2.ZERO
		_body.modulate.a = 1.0


# ---------------------------------------------------------------- ambient life

func _ambient(delta: float) -> void:
	if _vanish_t >= 0.0 or _arrive_t < ARRIVE_TIME:
		return
	_emit += delta
	_glint += delta
	var lid_top: Vector2 = anchor("lid_top")
	var foot: Array = _art.get("foot", [26, 9]) as Array
	var half: float = float(foot[0]) * 0.32
	var every: float = {"common": 0.9, "rare": 0.32, "legendary": 0.2}.get(tier, 0.9) as float
	if opened and _open_t > 4.0:
		every *= 3.0
	if _emit >= every:
		_emit = 0.0
		if opened:
			var m: Vector2 = mouth()
			_part(m + Vector2(randf_range(-half, half), 0), Vector2(randf_range(-3, 3), -randf_range(8, 18)), _main.lerp(_light_col, randf() * 0.5), randf_range(1.0, 1.8), 0, -6.0)
		elif tier == "common":
			_part(Vector2(randf_range(-half, half), lid_top.y + 4.0), Vector2(randf_range(-2, 2), -randf_range(5, 10)), Color(_main, 0.8), 1.8, 0, -3.0)
		elif tier == "rare":
			var from: Vector2 = anchor("crystals") if randf() < 0.5 else Vector2(randf_range(-half, half), lid_top.y + 3.0)
			_part(from + Vector2(randf_range(-3, 3), 0), Vector2(randf_range(-3, 3), -randf_range(8, 16)), _main.lerp(_light_col, randf() * 0.6), randf_range(1.2, 2.0), 3, -2.0, 0.0, randf() * TAU)
		else:
			for c: Vector2 in anchors("candles"): ## embers off the candle flames
				if randf() < 0.6:
					_part(c + Vector2(randf_range(-1, 1), 0), Vector2(randf_range(-4, 4), -randf_range(10, 22)), _main.lerp(Color("fff2cc"), randf() * 0.5), randf_range(0.7, 1.3), 0, -4.0)
			if randf() < 0.35: ## the void breathing at the chains' feet
				var ends: Array[Vector2] = anchors("chain_ends")
				if not ends.is_empty():
					_part(ends[randi() % ends.size()] + Vector2(randf_range(-2, 2), 0), Vector2(randf_range(-3, 3), -randf_range(4, 9)), VOID, 1.6, 0, -1.0)
	if _glint >= {"common": 99.0, "rare": 2.6, "legendary": 1.4}.get(tier, 99.0) as float and not opened:
		_glint = 0.0
		_flashes.append({"p": Vector2(randf_range(-half, half), lid_top.y + randf_range(0, 8)), "age": 0.0, "life": 0.5, "r": 3.0, "c": _light_col, "star": true})


# ---------------------------------------------------------------- particles

## kind: 0 mote, 1 coin, 2 shard (falls, lands), 3 swirling mote. `floor_drop` = px below the start where a falling piece lands.
func _part(p: Vector2, v: Vector2, c: Color, life: float, kind: int = 0, g: float = 0.0, floor_drop: float = 999.0, phase: float = 0.0) -> void:
	if _parts.size() >= MAX_PARTS:
		_parts.remove_at(0)
	_parts.append({"p": p, "v": v, "c": c, "life": life, "age": 0.0, "k": kind, "g": g, "floor": p.y + floor_drop, "ph": phase})


func _step_parts(delta: float) -> void:
	var i: int = 0
	while i < _parts.size():
		var q: Dictionary = _parts[i]
		var age: float = float(q.age) + delta
		if age >= float(q.life):
			_parts.remove_at(i)
			continue
		q.age = age
		var v: Vector2 = q.v as Vector2
		var p: Vector2 = q.p as Vector2
		v.y += float(q.g) * delta
		if int(q.k) == 3: ## swirl round the rising column
			v.x = cos(float(q.ph) + age * 5.0) * 16.0
		if int(q.k) == 0:
			v *= 1.0 - 1.4 * delta
		p += v * delta
		if (int(q.k) == 1 or int(q.k) == 2) and p.y > float(q.floor) and v.y > 0.0:
			p.y = float(q.floor)
			v = Vector2(v.x * 0.4, -v.y * 0.25) if absf(v.y) > 40.0 else Vector2.ZERO
		q.v = v
		q.p = p
		i += 1
	var j: int = 0
	while j < _rings.size():
		var r: Dictionary = _rings[j]
		r.age = float(r.age) + delta
		if float(r.age) >= float(r.life):
			_rings.remove_at(j)
		else:
			j += 1
	var k: int = 0
	while k < _flashes.size():
		var f: Dictionary = _flashes[k]
		f.age = float(f.age) + delta
		if float(f.age) >= float(f.life):
			_flashes.remove_at(k)
		else:
			k += 1


# ---------------------------------------------------------------- drawing

func _draw_fx() -> void:
	var m: Vector2 = mouth()
	# the arriving pillar of light from the sky
	if _arrive_t < ARRIVE_TIME:
		var a: float = clampf(_arrive_t / 0.15, 0.0, 1.0) * clampf((ARRIVE_TIME - _arrive_t) / 0.6, 0.0, 1.0)
		_column(Vector2(0, -4), 220.0, 3.0 + 6.0 * a, a, _main, _light_col)
	# rare: a fan of moon rays out of the open chest
	if tier == "rare" and _open_t >= 1.0 and _open_t < 2.6:
		var u: float = (_open_t - 1.0) / 1.6
		var fade: float = (1.0 - u) * minf(u * 8.0, 1.0)
		for r: int in 9:
			var ang: float = -PI * 0.5 + (r - 4) * 0.2 + sin(_time * 2.0 + r) * 0.03
			var length: float = (34.0 + 22.0 * float((r * 7) % 3)) * minf(u * 4.0, 1.0)
			_ray(m, ang, length, Color(_main if r % 2 else _light_col, 0.55 * fade))
	# legendary: the sun heart flares, then a pillar of gold light stands over the chest
	if tier == "legendary" and _open_t >= 1.05 and _open_t < 1.55:
		var g: Vector2 = anchor("gem")
		var s: float = (_open_t - 1.05) / 0.45
		_star(g, 2.0 + s * 9.0, Color(_light_col, 0.4 + 0.6 * s))
	if tier == "legendary" and _open_t >= 1.5 and _open_t < 4.2:
		var u2: float = (_open_t - 1.5) / 2.7
		var w: float = lerpf(14.0, 2.0, u2)
		_column(m, 200.0, w, (1.0 - u2) * minf(u2 * 12.0, 1.0), _main, _light_col)
	for f: Dictionary in _flashes:
		var age: float = float(f.age)
		if age < 0.0:
			continue
		var u3: float = age / float(f.life)
		if f.has("star"):
			_star(f.p as Vector2, float(f.r) * sin(u3 * PI), Color(f.c as Color, 1.0 - u3 * 0.5))
		else:
			_disc(f.p as Vector2, float(f.r) * (0.4 + 0.6 * u3), float(f.r) * (0.4 + 0.6 * u3) * 0.75, Color(f.c as Color, 1.0 - u3), 1.0 - u3)
	for q: Dictionary in _parts:
		var p: Vector2 = (q.p as Vector2).round()
		var u4: float = float(q.age) / float(q.life)
		var c: Color = q.c as Color
		var alpha: float = c.a * (1.0 - u4 * u4)
		match int(q.k):
			1: ## a coin: flips between a bar and a dot
				var flipc: bool = int((float(q.age) + float(q.ph)) * 14.0) % 2 == 0
				_fx.draw_rect(Rect2(p, Vector2(2, 1) if flipc else Vector2(1, 1)), Color(c, alpha))
			2:
				_fx.draw_rect(Rect2(p, Vector2(2, 2) if u4 < 0.5 else Vector2(1, 1)), Color(c, alpha))
			_:
				_fx.draw_rect(Rect2(p, Vector2.ONE), Color(c, alpha))
				if u4 < 0.3 and (q.v as Vector2).length() > 30.0:
					_fx.draw_rect(Rect2(p - (q.v as Vector2).normalized().round(), Vector2.ONE), Color(c, alpha * 0.5))


func _draw_ground() -> void:
	var foot: Array = _art.get("foot", [26, 9]) as Array
	var rx: float = float(foot[0]) * 0.5 + 8.0
	var ry: float = rx * 0.4
	var lit: float = lerpf(0.35, 1.0, _night) * (0.4 if opened and _open_t > 3.0 else 1.0) * modulate.a
	# the rune ring under rare and legendary chests (it tightens and fills while she holds)
	if tier != "common" and _arrive_t >= ARRIVE_TIME:
		var shrink: float = 1.0 - _strain * 0.18
		var n: int = 40 if tier == "legendary" else 30
		var spin: float = _time * (0.12 if tier == "legendary" else -0.08)
		for i: int in n:
			var a: float = TAU * i / n + spin
			var p: Vector2 = Vector2(cos(a) * rx * shrink, sin(a) * ry * shrink + 1.0).round()
			var on: bool = (float(i) / n) < _hold or (opened and _open_t < 1.5)
			var mark: bool = i % (5 if tier == "legendary" else 6) == 0
			if not mark and i % 2 == 1:
				continue
			var c: Color = _light_col if on else _main
			var a2: float = (0.95 if on else 0.32 + 0.12 * sin(_time * 2.0 + i)) * lit
			_ground.draw_rect(Rect2(p, Vector2(2, 1) if mark else Vector2.ONE), Color(c, a2))
		if tier == "legendary": ## an inner ring of glyph ticks
			for i: int in 8:
				var a3: float = TAU * i / 8.0 - spin * 2.0
				var p2: Vector2 = Vector2(cos(a3) * rx * 0.72 * shrink, sin(a3) * ry * 0.72 * shrink + 1.0).round()
				_ground.draw_rect(Rect2(p2, Vector2(1, 2)), Color(_main, 0.5 * lit))
	# shock rings
	for r: Dictionary in _rings:
		var age: float = float(r.age)
		if age < 0.0:
			continue
		var u: float = age / float(r.life)
		var rad: float = float(r.r) * (0.25 + 0.75 * sqrt(u))
		var steps: int = int(rad * 1.6) + 12
		for i: int in steps:
			if i % 3 == 2:
				continue
			var a4: float = TAU * i / steps
			_ground.draw_rect(Rect2(Vector2(cos(a4) * rad, sin(a4) * rad * 0.42).round(), Vector2.ONE), Color(r.c as Color, (1.0 - u) * 0.9))


## A column of light standing on `base`: dithered edges, a white core, sparks rising in it.
func _column(base: Vector2, height: float, width: float, strength: float, col: Color, core: Color) -> void:
	if strength <= 0.01:
		return
	var half: int = maxi(int(width * 0.5), 1)
	for y: int in int(height):
		var fall: float = 1.0 - float(y) / height
		for x: int in range(-half, half + 1):
			var edge: float = 1.0 - absf(float(x)) / float(half + 1)
			var dens: float = strength * fall * edge
			if BAYER[posmod(y, 4)][posmod(x, 4)] < dens * 18.0:
				var c: Color = core if absf(float(x)) <= half * 0.3 else col
				_fx.draw_rect(Rect2(base + Vector2(x, -y), Vector2.ONE), Color(c, minf(dens * 1.3, 0.9)))
	for k: int in 5:
		var ph: float = fposmod(_time * 0.9 + k * 0.21, 1.0)
		_fx.draw_rect(Rect2(base + Vector2(roundf(sin(k * 3.1 + _time) * half), -roundf(ph * height * 0.8)), Vector2.ONE), Color(core, strength * (1.0 - ph)))


func _ray(from: Vector2, ang: float, length: float, c: Color) -> void:
	var dir: Vector2 = Vector2.from_angle(ang)
	for i: int in int(length):
		if i % 4 == 3 and i > length * 0.5:
			continue
		_fx.draw_rect(Rect2((from + dir * i).round(), Vector2.ONE), Color(c, c.a * (1.0 - float(i) / length)))


func _star(p: Vector2, size: float, c: Color) -> void:
	var s: int = int(size)
	for i: int in range(-s, s + 1):
		var a: float = c.a * (1.0 - absf(float(i)) / float(s + 1))
		_fx.draw_rect(Rect2(p.round() + Vector2(i, 0), Vector2.ONE), Color(c, a))
		_fx.draw_rect(Rect2(p.round() + Vector2(0, i), Vector2.ONE), Color(c, a))
	_fx.draw_rect(Rect2(p.round() - Vector2.ONE, Vector2(3, 3)), Color(Color.WHITE, c.a))


func _disc(p: Vector2, rx: float, ry: float, c: Color, strength: float) -> void:
	for y: int in range(-ceili(ry), ceili(ry) + 1):
		var half: float = rx * sqrt(maxf(1.0 - pow(y / maxf(ry, 0.1), 2.0), 0.0))
		for x: int in range(-floori(half), floori(half) + 1):
			if BAYER[posmod(y, 4)][posmod(x, 4)] < strength * 16.0:
				_fx.draw_rect(Rect2(p.round() + Vector2(x, y), Vector2.ONE), c)


# ---------------------------------------------------------------- sound and shake

func _sound(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
	var path: String = SOUND_DIR + name + ".wav"
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load(path) as AudioStream
	player.volume_db = db
	player.pitch_scale = pitch * randf_range(0.97, 1.03)
	player.max_distance = 520.0
	player.attenuation = 1.4
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _shake(amount: float, range_px: float) -> void:
	var me: Player = _local_player()
	if me != null and me.global_position.distance_to(global_position) < range_px:
		me.add_shake(amount)
