class_name CrowHoard
extends WorldTrial
## The crow's hoard, common (Krähenschatz, docs/raetsel_konzept.md section 4): a single crow with a silver ring on its leg sits on a dead snag, bits of
## glitter in the grass round it. Hold food it likes in the hand (the selected hotbar slot, `data/pets.json` foods: loves/likes), come close quietly
## and stand still: it grows curious, flies down in front of you and offers itself ("E FÜTTERN", Ellie's crouch of the pet system, `Player.begin_feed`).
## Sprinting, swinging or rushing at it sends it back to its snag. Fed, it eats, caws twice and flies in a curve to a mound of fresh earth 20-40 tiles
## away, where it scratches until somebody comes; then it flies home. E at the mound ("AUSGRABEN") and she digs it out by hand (the picking clip),
## or three blows of a hoe (`HarvestHurtbox`); a Wurzelkiste breaks up out of the earth (`LootChests.appear` with `rise`).
## Host-authoritative like the wisp: the host decides, `_rpc_state` tells every peer the state with its flight (from, to, heights, length, bend), and
## every peer animates the crow (the wildlife's own sheet, `assets/wildlife/corvid.png`) from that. Saved: whether the hoard was shown (`revealed`).
## RAVEN TRADE (kind `raven_trade`, rare, `raven` true): an old raven with a ravensteel ring on a bleached snag. It comes down to anyone standing
## still near it, but takes only shiny things (`data/puzzles.json` `raven.likes`): "E ANBIETEN" opens a one-slot offer box (`BoxWindow`, `ItemBox`
## "raven:<id>"); whatever she lays in is judged by the host at once (`_host_judge`): junk goes back into her bag and it turns away
## (three times in a day and it ignores her until the next). Paid, it keeps the pawn and leads over its `stations`: at each it drops a black
## feather with a silver tip that she picks up (E) before it flies on; left waiting `feather_wait` s it flies home and resumes from that station
## when she comes back. At the end it sits on its mound: E digs out a Mondsiegeltruhe with the pawn inside (`reward_extra`).

enum State { PERCH, HOP, GROUND, EAT, CALL, LEAD, DIG, HOME, DONE, WAIT, REFUSE }

const ART: String = "res://assets/props/puzzles/"
const CROW_SHEET: String = "res://assets/wildlife/corvid.png"
const RING_SHEET: String = "res://assets/wildlife/pet_marks.png"
const HARVEST_LAYER: int = 1 << 4
const LIFT: float = 24.0 ## weapons swing from her chest: a ground target's hurtbox sits that much higher
const SILVER: Color = Color("d8dde8")
const EARTH: Array[Color] = [Color("45323a"), Color("66494a"), Color("2e2228"), Color("8a6a5c")]
const GLINT: Color = Color("fff2cc")
const RAVENSTEEL: Color = Color("8f9ac0")
const FEATHER: Color = Color("14121c")
const FEATHER_EDGE: Color = Color("3a3650")
const FEATHER_TIP: Color = Color("dfe8f8")

var cfg: Dictionary = {}
var state: int = State.PERCH
var revealed: bool = false
var digs: int = 0
var target_peer: int = 0
var interest: float = 0.0
var raven: bool = false ## the rare raven trade instead of the crow's food
var feathers: int = 0 ## raven: feathers she picked up
var dropped: int = 0 ## raven: feathers it dropped so far
var pawn: String = "" ## raven (host): the item it took, it goes into the chest
var manual: bool = false ## look studies drive the states by hand: the host logic sleeps

var _snag_pos: Vector2 = Vector2.ZERO
var _mound_pos: Vector2 = Vector2.ZERO
var _perch: Vector2 = Vector2(0.6, -10.5) ## px above the snag's feet where the crow sits
var _solved: bool = false
var _build: int = 0
var variant: int = 0 ## which hoard perch (tools/art_hoard.py: 0 lightning stump, 1 ring stump, 2 crooked stump, 3 rock)

# flight / pose (every peer, from `_rpc_state`)
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _h0: float = 0.0
var _h1: float = 0.0
var _dur: float = 1.0
var _bend: float = 0.0
var _face: float = PI * 0.5
var _state_t: float = 0.0
var _time: float = 0.0
var _height: float = 0.0
var _caws: int = 0

# host
var _cool: float = 0.0
var _ground_t: float = 0.0
var _last: Dictionary = {} ## peer -> last position (speed towards the crow)
var _junk: Dictionary = {} ## raven, host: peer -> [day, offers it refused]
var _stations: Array[Vector2] = []
var _drop_age: Array[float] = [] ## every peer: seconds since each feather fell
var _offer: ItemBox ## raven: the one slot she lays her offer in
var _offer_window: BoxWindow ## the local player's open offer window

var _snag: Node2D
var _crow: Node2D
var _sprite: Sprite2D
var _ring: Sprite2D
var _mound: Node2D
var _mound_sprite: Sprite2D
var _hurtbox: HarvestHurtbox
var _ground: Node2D
var _crow_spot: HoardSpot
var _mound_spot: HoardSpot
var _glints: Array[Vector2] = []
var _clods: Array = [] ## [pos, vel, age, life, colour]
var _night: float = 0.0


func setup(entry: Dictionary, tuning: Dictionary) -> void:
	super.setup(entry, tuning)
	cfg = tuning
	var t: Array = entry.get("tile", [0, 0]) as Array
	var m: Array = entry.get("mound", [0, 0]) as Array
	_snag_pos = Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8, 8)
	_mound_pos = Vector2(float(m[0]), float(m[1])) * 16.0 + Vector2(8, 8)
	raven = String(entry.get("kind", "")) == "raven_trade"
	for st: Variant in entry.get("stations", []) as Array:
		var sa: Array = st as Array
		_stations.append(Vector2(float(sa[0]), float(sa[1])) * 16.0 + Vector2(8, 8))
		_drop_age.append(99.0)
	var art: Dictionary = DataRegistry.table("puzzle_art").get(_art_key(), {}) as Dictionary
	var count: int = int(art.get("frames", 1))
	variant = clampi(int(entry.get("variant", absi(hash(id + "v")) % count)), 0, count - 1)
	var perches: Array = art.get("perches", [art.get("perch", [0.6, -10.5])]) as Array
	var perch: Array = perches[mini(variant, perches.size() - 1)] as Array
	_perch = Vector2(float(perch[0]), float(perch[1]))
	_build = absi(hash(id)) % 3 + (3 if raven else 0) ## corvid.png: builds 0-2 crow, 3-5 raven
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(id + "glint")
	for i: int in 6:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(14.0, 30.0)
		_glints.append(_snag_pos + Vector2(cos(a) * r, sin(a) * r * 0.55).round())
	_set_pose(State.PERCH)


func _art_key() -> String:
	return "hoard_raven" if raven else "hoard_crow"


func station_count() -> int:
	return _stations.size()


func station_position(i: int) -> Vector2:
	return _stations[i]


func reward_extra() -> Array:
	return [{"id": pawn, "count": 1}] if raven and pawn != "" else []


func start_position() -> Vector2:
	return _snag_pos + Vector2(0, 110)


func end_position() -> Vector2:
	return _mound_pos


func reward_rise() -> bool:
	return true


func snag_position() -> Vector2:
	return _snag_pos


func mound_position() -> Vector2:
	return _mound_pos


## Where the crow's feet are on the ground right now (with the flight's curve).
func crow_position() -> Vector2:
	if _is_flight():
		return _flight_point(_flight_t())
	return _crow.position if _crow != null else _perch_ground()


func _perch_ground() -> Vector2:
	return _snag_pos + Vector2(_perch.x, 2.0)


func _ready() -> void:
	y_sort_enabled = true
	_ground = Node2D.new()
	_ground.name = "HoardGround"
	_ground.z_index = -5
	_ground.material = Unlit.material()
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	var solids: Array = (DataRegistry.table("puzzle_art").get(_art_key(), {}) as Dictionary).get("solid", []) as Array
	var solid: Array = solids[variant] as Array if variant < solids.size() else ([14, 7] if raven else [12, 6])
	_snag = _prop(_art_key(), _snag_pos, Vector2(float(solid[0]), float(solid[1])))
	var snag_sprite: Sprite2D = _snag.get_child(0) as Sprite2D
	snag_sprite.frame = variant
	var snag_glow: Sprite2D = snag_sprite.get_node_or_null("Glow") as Sprite2D
	if snag_glow != null:
		snag_glow.frame = variant
	_mound = _prop("mound", _mound_pos, Vector2.ZERO)
	_mound_sprite = _mound.get_child(0) as Sprite2D
	_hurtbox = HarvestHurtbox.new()
	_hurtbox.name = "Harvest"
	_hurtbox.harvest_target = self
	_hurtbox.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(22.0, 16.0)
	shape.shape = box
	shape.position = Vector2(0.0, -4.0 - LIFT)
	_hurtbox.add_child(shape)
	_mound.add_child(_hurtbox)
	_mound_spot = HoardSpot.new()
	_mound_spot.trial = self
	_mound_spot.kind = "mound"
	_mound.add_child(_mound_spot)

	_crow = Node2D.new()
	_crow.name = "Crow"
	_crow.draw.connect(_draw_shadow)
	add_child(_crow)
	_sprite = Sprite2D.new()
	_sprite.texture = load(CROW_SHEET) as Texture2D
	_sprite.hframes = 62
	_sprite.vframes = 48
	_sprite.centered = false
	_sprite.offset = Vector2(-24, -35)
	_crow.add_child(_sprite)
	if ResourceLoader.exists(RING_SHEET):
		_ring = Sprite2D.new()
		_ring.texture = load(RING_SHEET) as Texture2D
		_ring.hframes = 62
		_ring.vframes = 48
		_ring.centered = false
		_ring.offset = Vector2(-24, -35)
		_ring.modulate = RAVENSTEEL if raven else SILVER
		_crow.add_child(_ring)
	_crow_spot = HoardSpot.new()
	_crow_spot.trial = self
	_crow_spot.kind = "crow"
	_crow.add_child(_crow_spot)
	for i: int in _stations.size(): ## the feathers it will drop
		var holder: Node2D = Node2D.new()
		holder.name = "Feather%d" % i
		holder.position = _stations[i] + Vector2(10, 4)
		add_child(holder)
		var fs: HoardSpot = HoardSpot.new()
		fs.trial = self
		fs.kind = "feather%d" % i
		holder.add_child(fs)
	add_to_group("night_lights")
	_apply_look()
	_animate(0.0)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void: _rpc_state.rpc_id(peer, state, _pack(), revealed, digs, target_peer))


## The feather lying at station `i` (drawn on the ground, picked with E).
func feather_position(i: int) -> Vector2:
	return _stations[i] + Vector2(10, 4)


func _prop(name: String, at: Vector2, solid: Vector2) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = name.capitalize().replace(" ", "")
	node.position = at
	add_child(node)
	var art: Dictionary = DataRegistry.table("puzzle_art").get(name, {}) as Dictionary
	var frame: Array = art.get("frame", [32, 32]) as Array
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(ART + name + ".png") as Texture2D
	sprite.hframes = int(art.get("frames", 1))
	sprite.centered = false
	sprite.offset = -Vector2(float(frame[0]) * 0.5, float(art.get("ground", frame[1])))
	node.add_child(sprite)
	if ResourceLoader.exists(ART + name + "_glow.png"):
		var glow: Sprite2D = Sprite2D.new()
		glow.name = "Glow"
		glow.texture = load(ART + name + "_glow.png") as Texture2D
		glow.hframes = sprite.hframes
		glow.centered = false
		glow.offset = sprite.offset
		glow.material = Unlit.material()
		sprite.add_child(glow)
	if solid != Vector2.ZERO:
		var body: StaticBody2D = StaticBody2D.new()
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = solid
		cs.shape = rect
		cs.position = Vector2(0, -solid.y * 0.5 + 1.0)
		body.add_child(cs)
		node.add_child(body)
	return node


func set_night(amount: float) -> void:
	_night = amount
	for node: Node2D in [_snag, _mound]:
		var glow: Node = node.get_child(0).get_node_or_null("Glow") if node != null else null
		if glow is Sprite2D:
			(glow as Sprite2D).modulate.a = 0.3 + 0.7 * amount


# ------------------------------------------------------------------ host

func _process(delta: float) -> void:
	_time += delta
	_state_t += delta
	if multiplayer.is_server() and not manual:
		_host_step(delta)
	_animate(delta)


func _host_step(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	var people: Array = WorldTrial.living_players()
	match state:
		State.PERCH:
			if raven and pawn != "": ## it owes her the way: when somebody comes back to its snag it flies on
				for e: Variant in people:
					if ((e as Dictionary).pos as Vector2).distance_to(_snag_pos) < float(cfg.get("resume_range", 70.0)):
						_lead_on()
						return
			_host_lure(people, delta)
		State.HOP:
			if _state_t >= _dur:
				_ground_t = 0.0
				_go(State.GROUND)
		State.GROUND:
			_ground_t += delta
			var who: Dictionary = _person(people, target_peer)
			if who.is_empty() or _ground_t > float(cfg.get("offer_time", 30.0)):
				_fly_home(false)
				return
			var d: float = (who.pos as Vector2).distance_to(crow_position())
			var rush: float = _approach_speed(who, delta)
			if bool(who.loud) or d < float(cfg.get("too_close", 9.0)) or d > float(cfg.get("leave_range", 130.0)) or rush > float(cfg.get("rush_speed", 46.0)):
				_fly_home(true)
				return
			var face: float = ((who.pos as Vector2) - crow_position()).angle()
			if absf(angle_difference(face, _face)) > 0.6:
				_face = face
				_send()
		State.EAT:
			if _state_t >= 1.1:
				_go(State.CALL)
		State.CALL:
			if _state_t >= 1.5:
				_lead_on()
		State.LEAD:
			if _state_t >= _dur:
				if raven and feathers < _stations.size(): ## at the next station: the feather falls (again, if it went home before)
					dropped = maxi(dropped, feathers + 1)
					_go(State.WAIT)
				else:
					revealed = true
					_go(State.DIG)
		State.WAIT:
			if _state_t >= float(cfg.get("feather_wait", 60.0)):
				_fly_home(false)
		State.REFUSE:
			if _state_t >= 1.4:
				_ground_t = 0.0
				_go(State.GROUND)
		State.DIG:
			if raven:
				return ## the raven sits on its hoard until it is dug out
			for e: Variant in people:
				if ((e as Dictionary).pos as Vector2).distance_to(_mound_pos) < float(cfg.get("show_range", 52.0)):
					_fly_home(false)
					return
		State.HOME:
			if _state_t >= _dur:
				_go(State.DONE if revealed or _solved else State.PERCH)


## Where it flies next: the next feather station, else the mound (it lands on the raven's mound, beside the crow's).
func _lead_on() -> void:
	var bend: float = 0.55 if (hash(id + str(feathers)) & 1) == 0 else -0.55
	var speed: float = float(cfg.get("lead_speed", 64.0))
	if raven and feathers < _stations.size():
		_start_flight(State.LEAD, crow_position(), _stations[feathers], _height, 0.0, speed, bend)
	elif raven:
		_start_flight(State.LEAD, crow_position(), _mound_pos + Vector2(0, 1), _height, 3.0, speed, bend)
	else:
		_start_flight(State.LEAD, crow_position(), _mound_pos + Vector2(-12, 3), 0.0, 0.0, speed, bend)


## On its snag: who holds food it likes, close and calm? Interest grows, a fright wipes it.
func _host_lure(people: Array, delta: float) -> void:
	if revealed or _solved or (raven and pawn != ""):
		return
	var best: Dictionary = {}
	var best_rate: float = 0.0
	for e: Variant in people:
		var who: Dictionary = e as Dictionary
		var d: float = (who.pos as Vector2).distance_to(_snag_pos)
		var rush: float = _approach_speed(who, delta)
		if bool(who.loud) and d < float(cfg.get("spook_range", 140.0)) or d < float(cfg.get("too_close", 9.0)) + 14.0:
			if interest > 0.05 or _cool <= 0.0:
				interest = 0.0
				_cool = float(cfg.get("spook_cool", 5.0))
				_caw_rpc()
			continue
		if _cool > 0.0:
			continue
		var food: String = "offer" if raven else food_in_hand(who.player as Player)
		if food == "" or d > float(cfg.get("lure_range", 115.0)) or (raven and _ignores(int(who.peer))):
			continue
		var still: bool = float(who.speed) < float(cfg.get("still_speed", 6.0)) or (bool(who.sneak) and rush < 20.0)
		if not still:
			continue
		var rate: float = float(cfg.get("rate", 0.35)) if raven else (float(cfg.get("rate_loves", 0.5)) if PetRules.reaction("crow", food) == "loves" else float(cfg.get("rate_likes", 0.3)))
		var p: Player = who.player as Player
		if p != null and p.talismans != null:
			rate *= 1.0 + p.talismans.corvid_calm()
		if rate > best_rate:
			best_rate = rate
			best = who
	if best.is_empty():
		interest = maxf(0.0, interest - delta * float(cfg.get("decay", 0.3)))
		return
	interest += best_rate * delta
	var face: float = ((best.pos as Vector2) - _snag_pos).angle()
	if absf(angle_difference(face, _face)) > 0.7:
		_face = face
		_send()
	if interest >= 1.0:
		interest = 0.0
		target_peer = int(best.peer)
		var her: Vector2 = best.pos as Vector2
		var land: Vector2 = her + (_snag_pos - her).normalized() * float(cfg.get("offer_distance", 22.0))
		_start_flight(State.HOP, crow_position(), land, -_perch.y, 0.0, 56.0, 0.3)


func _approach_speed(who: Dictionary, delta: float) -> float:
	var peer: int = int(who.get("peer", 0))
	var pos: Vector2 = who.pos as Vector2
	var speed: float = 0.0
	if _last.has(peer) and delta > 0.0:
		var before: float = (_last[peer] as Vector2).distance_to(crow_position())
		speed = (before - pos.distance_to(crow_position())) / delta
	_last[peer] = pos
	return speed


func _person(people: Array, peer: int) -> Dictionary:
	for e: Variant in people:
		if int((e as Dictionary).get("peer", 0)) == peer:
			return e as Dictionary
	return {}


## Anything a player holds in the selected hotbar slot ("" = an empty hand): what she may offer the raven.
static func held_item(player: Player) -> String:
	if player == null or player.inventory == null:
		return ""
	var stack: Dictionary = player.inventory.slots[player.inventory.selected] as Dictionary
	return "" if stack.is_empty() else String(stack["id"])


## True: the raven likes this item (data/puzzles.json `raven.likes`).
func raven_likes(item: String) -> bool:
	return (cfg.get("likes", []) as Array).has(item)


func _ignores(peer: int) -> bool:
	var j: Array = _junk.get(peer, [-1, 0]) as Array
	return int(j[0]) == TimeManager.day and int(j[1]) >= int(cfg.get("junk_limit", 3))


## The food a player holds in the selected hotbar slot that a crow likes or loves ("" = none).
static func food_in_hand(player: Player) -> String:
	if player == null or player.inventory == null:
		return ""
	var stack: Dictionary = player.inventory.slots[player.inventory.selected] as Dictionary
	if stack.is_empty():
		return ""
	var kind: String = PetRules.reaction("crow", String(stack["id"]))
	return String(stack["id"]) if kind == "loves" or kind == "likes" else ""


func _fly_home(spooked: bool) -> void:
	if spooked:
		_cool = float(cfg.get("spook_cool", 5.0))
		_caw_rpc()
	interest = 0.0
	target_peer = 0
	if state == State.WAIT:
		_height = 0.0
	_start_flight(State.HOME, crow_position(), _perch_ground(), _height, -_perch.y, 72.0 if spooked else 58.0, -0.4)


func _start_flight(next: int, from: Vector2, to: Vector2, h0: float, h1: float, speed: float, bend: float) -> void:
	_from = from
	_to = to
	_h0 = h0
	_h1 = h1
	_bend = bend
	_dur = maxf(0.8, from.distance_to(to) / maxf(speed, 1.0))
	_go(next)


func _go(next: int) -> void:
	_send(next) ## the state itself changes in `_rpc_state`, on every peer alike (its clock starts there)


func _pack() -> Array:
	return [_from, _to, _h0, _h1, _dur, _bend, _face, feathers, dropped]


func _send(next: int = -1) -> void:
	var to: int = state if next < 0 else next
	if multiplayer.get_peers().is_empty():
		_rpc_state(to, _pack(), revealed, digs, target_peer)
	else:
		_rpc_state.rpc(to, _pack(), revealed, digs, target_peer)


@rpc("authority", "call_local", "reliable")
func _rpc_state(next: int, pose: Array, shown: bool, dug: int, peer: int) -> void:
	var old: int = state
	state = next
	_from = pose[0] as Vector2
	_to = pose[1] as Vector2
	_h0 = float(pose[2])
	_h1 = float(pose[3])
	_dur = float(pose[4])
	_bend = float(pose[5])
	_face = float(pose[6])
	if pose.size() > 8:
		feathers = int(pose[7])
		var was: int = dropped
		dropped = int(pose[8])
		for i: int in range(was, mini(dropped, _drop_age.size())):
			_drop_age[i] = 0.0
	var newly: bool = shown and not revealed
	revealed = shown
	digs = dug
	target_peer = peer
	if old != next:
		_state_t = 0.0
		_caws = 0
		_enter_fx(next)
		if _offer_window != null and is_instance_valid(_offer_window) and next != State.GROUND and next != State.REFUSE:
			_offer_window.call("_close") ## it took the pawn (or flew off): the offer window goes
			_offer_window = null
	if newly:
		_reveal_fx()
	_apply_look()


func _enter_fx(next: int) -> void:
	match next:
		State.HOP, State.LEAD, State.HOME:
			_flap_sound()
		State.EAT:
			_sound_file("res://assets/audio/pets/take.wav", -4.0, crow_position())
		State.DIG:
			_greet("ER SITZT AUF SEINEM HORT. HIER MUSS ICH GRABEN." if raven else "SIE HAT MIR IHR VERSTECK GEZEIGT.") ## placeholder lines for the dialogue writer
		State.REFUSE:
			_sound_file("res://assets/audio/pets/refuse.wav", -4.0, crow_position())
		State.WAIT:
			_caw()


func _reveal_fx() -> void:
	for i: int in 16:
		_clod(_mound_pos + Vector2(randf_range(-8, 8), randf_range(-3, 3)), 0.8)


func _caw_rpc() -> void:
	if multiplayer.get_peers().is_empty():
		_rpc_caw()
	else:
		_rpc_caw.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_caw() -> void:
	_caw()


# ------------------------------------------------------------------ feeding and digging

func spot_prompt(kind: String) -> String:
	var me: Player = _local()
	if me == null or _solved:
		return ""
	if kind == "crow":
		if state == State.GROUND and target_peer == me.name.to_int() and not me.is_busy():
			if raven:
				return "ANBIETEN"
			if not raven and food_in_hand(me) != "":
				return "FÜTTERN"
		return ""
	if kind.begins_with("feather"):
		var i: int = kind.to_int()
		return "FEDER AUFHEBEN" if i == feathers and i < dropped and not me.is_busy() and _drop_age[i] > 1.2 else ""
	if revealed and not me.is_busy():
		return "AUSGRABEN"
	return ""


func spot_hint(_kind: String) -> String:
	return ""


func spot_used(kind: String, player: Player) -> void:
	if kind == "mound": ## she kneels and digs it out with her hands (the picking clip); at the grab the host decides
		var down: Vector2 = (_mound_pos - player.global_position).normalized()
		player.begin_pick(down, func() -> void:
			if multiplayer.is_server():
				_host_hand_dig(multiplayer.get_unique_id())
			else:
				_rpc_hand_dig.rpc_id(1))
		return
	if kind.begins_with("feather"):
		var fi: int = kind.to_int()
		var towards: Vector2 = (feather_position(fi) - player.global_position).normalized()
		player.begin_pick(towards, func() -> void:
			if multiplayer.is_server():
				_host_feather(multiplayer.get_unique_id(), fi)
			else:
				_rpc_feather.rpc_id(1, fi))
		return
	if raven:
		_offer_window = BoxWindow.open_box(get_tree(), player, offer_box(), "DEM RABEN ANBIETEN")
		return
	var item: String = food_in_hand(player)
	if item == "":
		return
	var toward: Vector2 = (crow_position() - player.global_position).normalized()
	player.begin_feed(toward, item, func() -> void:
		if multiplayer.is_server():
			_host_feed(multiplayer.get_unique_id())
		else:
			_rpc_feed.rpc_id(1))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_feed() -> void:
	if multiplayer.is_server():
		_host_feed(multiplayer.get_remote_sender_id())


## The raven's one-slot offer box: only the player it stands in front of may use it, only while it waits for her.
func offer_box() -> ItemBox:
	if _offer == null:
		_offer = ItemBox.new("raven:" + id, 1)
		_offer.reach_ok = func(who: Node2D) -> bool:
			return who is Player and (state == State.GROUND or state == State.REFUSE) and (who as Player).name.to_int() == target_peer and who.global_position.distance_to(crow_position()) < 70.0
		_offer.changed.connect(func() -> void:
			if multiplayer.is_server():
				_host_judge.call_deferred())
	return _offer


## Host: something lies in the offer box: the raven takes one piece if it likes it (the rest and anything else goes back into her bag).
func _host_judge() -> void:
	if _offer == null or (_offer.slots[0] as Dictionary).is_empty():
		return
	var stack: Dictionary = (_offer.slots[0] as Dictionary).duplicate()
	_offer.slots[0] = {}
	_offer.touch()
	var who: Player = _player(target_peer)
	var item: String = String(stack["id"])
	var count: int = int(stack.get("count", 1))
	var liked: bool = raven_likes(item) and state == State.GROUND and Items.extras(stack).is_empty()
	if who == null:
		return
	if liked:
		pawn = item
		count -= 1
	if count > 0:
		var left: int = who.inventory.give(item, count, Items.extras(stack))
		if left > 0:
			DropComponent.spawn_thrown(get_tree(), item, left, who.global_position, Vector2.DOWN, Items.extras(stack)) ## a full bag: it lands at her feet
	if liked:
		_face = (who.global_position - crow_position()).angle()
		_go(State.EAT)
		return
	var j: Array = _junk.get(target_peer, [-1, 0]) as Array
	_junk[target_peer] = [TimeManager.day, (int(j[1]) if int(j[0]) == TimeManager.day else 0) + 1]
	_face = (crow_position() - who.global_position).angle() ## it turns its head away
	if _ignores(target_peer):
		_fly_home(true)
	else:
		_go(State.REFUSE)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_feather(i: int) -> void:
	if multiplayer.is_server():
		_host_feather(multiplayer.get_remote_sender_id(), i)


## E on a feather (host): the next one in the chain; the raven flies on.
func _host_feather(peer: int, i: int) -> void:
	var who: Player = _player(peer)
	if who == null or i != feathers or i >= dropped or who.global_position.distance_to(feather_position(i)) > 44.0:
		return
	feathers += 1
	if state == State.WAIT:
		_lead_on()
	else:
		_send()


func _host_feed(peer: int) -> void:
	var ok: bool = false
	var who: Player = _player(peer)
	var refused: bool = false
	if who != null and state == State.GROUND and target_peer == peer and who.global_position.distance_to(crow_position()) < 60.0:
		var item: String = held_item(who) if raven else food_in_hand(who)
		if raven and item != "" and not raven_likes(item):
			refused = true
		elif item != "" and who.inventory.remove_item(item, 1):
			ok = true
			if raven:
				pawn = item
	if refused:
		var j: Array = _junk.get(peer, [-1, 0]) as Array
		_junk[peer] = [TimeManager.day, (int(j[1]) if int(j[0]) == TimeManager.day else 0) + 1]
	if multiplayer.get_peers().is_empty():
		_rpc_fed(peer, ok)
	else:
		_rpc_fed.rpc(peer, ok)
	if refused:
		_face = (crow_position() - who.global_position).angle() ## it turns its head away
		if _ignores(peer):
			_fly_home(true)
		else:
			_go(State.REFUSE)
	elif ok:
		_face = (who.global_position - crow_position()).angle()
		_go(State.EAT)


@rpc("authority", "call_local", "reliable")
func _rpc_fed(peer: int, _ok: bool) -> void:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority() and p.name.to_int() == peer:
			p.release_feed()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_dig() -> void:
	if multiplayer.is_server():
		_host_hand_dig(multiplayer.get_remote_sender_id())


## E at the mound (host): she digs it out by hand at once.
func _host_hand_dig(peer: int) -> void:
	if not revealed or _solved:
		return
	var who: Player = _player(peer)
	if who == null or who.global_position.distance_to(_mound_pos) > float(cfg.get("dig_reach", 48.0)):
		return
	_dig_to(int(cfg.get("digs", 3)))


## A weapon blow found the mound (host): a hoe digs too (one of three blows).
func harvest_hit(source: int) -> void:
	if not multiplayer.is_server() or not revealed or _solved:
		return
	var who: Player = _player(source)
	if who == null or who.global_position.distance_to(_mound_pos) > float(cfg.get("dig_reach", 48.0)):
		return
	if not _held_hoe(who):
		return
	_dig_to(digs + 1)


func _dig_to(count: int) -> void:
	digs = mini(count, int(cfg.get("digs", 3)))
	if state == State.DIG:
		_fly_home(false)
	if multiplayer.get_peers().is_empty():
		_rpc_dig(digs)
	else:
		_rpc_dig.rpc(digs)
	if digs >= int(cfg.get("digs", 3)):
		_solved = true
		solved.emit(id, _mound_pos)


@rpc("authority", "call_local", "reliable")
func _rpc_dig(count: int) -> void:
	digs = count
	_sound_file("res://assets/audio/farming/hoe_till.wav", -1.0, _mound_pos)
	for i: int in 10 + count * 4:
		_clod(_mound_pos + Vector2(randf_range(-6, 6), randf_range(-3, 2)), 1.0)
	if count >= int(cfg.get("digs", 3)):
		_solved = true
	_apply_look()


## What the cursor asks of a hurtbox owner (`GameCursor._can_harvest`).
func spec() -> Dictionary:
	return {"tool": "hoe"}


func is_depleted() -> bool:
	return not revealed or _solved


func set_solved_instant() -> void:
	_solved = true
	revealed = true
	digs = int(cfg.get("digs", 3))
	state = State.DONE
	_set_pose(State.DONE)
	_apply_look()


func reset_trial() -> void:
	feathers = 0
	dropped = 0
	pawn = ""
	_junk.clear()
	_solved = false
	revealed = false
	digs = 0
	target_peer = 0
	interest = 0.0
	state = State.PERCH
	_set_pose(State.PERCH)
	_apply_look()


func export_progress() -> Dictionary:
	if _solved:
		return {}
	var out: Dictionary = {}
	if revealed:
		out["revealed"] = true
	if raven and pawn != "":
		out["pawn"] = pawn
		out["feathers"] = feathers
		out["dropped"] = feathers ## a feather lying uncollected is dropped again on the next lead
	return out


func import_progress(data: Dictionary) -> void:
	pawn = String(data.get("pawn", ""))
	feathers = int(data.get("feathers", 0))
	dropped = int(data.get("dropped", feathers))
	if bool(data.get("revealed", false)):
		revealed = true
		state = State.DONE
		_set_pose(State.DONE)
		_apply_look()


func _set_pose(next: int) -> void:
	_from = _perch_ground()
	_to = _perch_ground()
	_h0 = -_perch.y
	_h1 = -_perch.y
	_dur = 1.0
	_state_t = 99.0
	if next == State.DONE or next == State.PERCH:
		_height = -_perch.y


func _apply_look() -> void:
	if _mound != null:
		_mound.visible = revealed and not _solved
	if _hurtbox != null:
		_hurtbox.collision_layer = HARVEST_LAYER if revealed and not _solved else 0
	if _mound_sprite != null:
		_mound_sprite.scale.y = 1.0 - 0.18 * float(digs)


func _held_hoe(player: Player) -> bool:
	if player == null or player.inventory == null:
		return false
	return String(Items.definition(player.inventory.active_stack()).get("tool", "")) == "hoe"


func _player(peer: int) -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer:
			return p
	return null


func _local() -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority():
			return p
	return null


func _greet(line: String, always: bool = false) -> void:
	var me: Player = _local()
	if me == null or (not always and me.global_position.distance_to(_mound_pos) > 260.0 and me.global_position.distance_to(crow_position()) > 260.0):
		return
	var box: Node = get_tree().get_first_node_in_group("speech_box")
	if box != null and box.has_method("speak"):
		box.call("speak", "ELLIE", line)


# ------------------------------------------------------------------ animation (every peer)

func _is_flight() -> bool:
	return state == State.HOP or state == State.LEAD or state == State.HOME


func _flight_t() -> float:
	return clampf(_state_t / maxf(_dur, 0.01), 0.0, 1.0)


func _flight_point(t: float) -> Vector2:
	var mid: Vector2 = (_from + _to) * 0.5
	var d: Vector2 = _to - _from
	var ctrl: Vector2 = mid + Vector2(-d.y, d.x) * _bend * 0.5
	var u: float = 1.0 - t
	return u * u * _from + 2.0 * u * t * ctrl + t * t * _to


func _animate(delta: float) -> void:
	if _crow == null:
		return
	var col: int = 0
	var pos: Vector2 = _perch_ground()
	var h: float = -_perch.y
	match state:
		State.HOP, State.LEAD, State.HOME:
			var t: float = _flight_t()
			var e: float = t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65 ## a little slower at both ends
			pos = _flight_point(e)
			var arc: float = minf(44.0, _from.distance_to(_to) * 0.22) + 8.0
			h = lerpf(_h0, _h1, e) + sin(PI * e) * arc
			var ahead: Vector2 = _flight_point(minf(e + 0.02, 1.0)) - _flight_point(maxf(e - 0.02, 0.0))
			if ahead.length() > 0.01:
				_face = ahead.angle()
			if t < 0.16:
				col = 44 + mini(5, int(t / 0.16 * 6.0))
			elif t > 0.84:
				col = 38 + mini(5, int((t - 0.84) / 0.16 * 6.0))
			elif t > (0.34 if raven else 0.45) and t < (0.68 if raven else 0.58):
				col = 50 + int(_time * 4.0) % 4
			else:
				col = 30 + int(_time * 14.0) % 8
			if int(_time * 14.0) % 8 == 0 and int((_time - delta) * 14.0) % 8 != 0 and t > 0.16 and t < 0.84 and randf() < 0.3:
				_flap_sound()
		State.WAIT:
			pos = _to
			h = 0.0
			col = 22 + int(_time * 3.0) % 4 if fmod(_time, 4.0) < 2.4 else int(_time * 2.5) % 4
		State.REFUSE:
			pos = _to
			h = 0.0
			col = 16 + mini(5, int(_state_t / 1.4 * 6.0)) ## it preens, its head turned away
		State.GROUND:
			pos = _to
			h = 0.0
			col = 22 + int(_time * 3.0) % 4 if fmod(_time, 3.0) < 1.6 else int(_time * 2.5) % 4
		State.EAT:
			pos = _to
			h = 0.0
			col = 4 + int(_state_t * 12.0) % 6
		State.CALL:
			pos = _to
			h = 0.0
			col = int(_time * 2.5) % 4
			for k: int in 2:
				var at: float = 0.15 + k * 0.7
				if _state_t >= at and _caws <= k:
					_caws = k + 1
					_caw()
				if _state_t >= at and _state_t < at + 0.4:
					col = 26 + int((_state_t - at) * 10.0) % 4
		State.DIG when raven:
			pos = _to
			h = 3.0 ## on top of its mound
			col = 22 + int(_time * 3.0) % 4 if fmod(_time, 5.0) < 2.0 else int(_time * 2.5) % 4
		State.DIG:
			pos = _to
			h = 0.0
			_face = (_mound_pos - pos).angle()
			var beat: float = fmod(_time, 2.4)
			col = 4 + int(beat * 10.0) % 6 if beat < 1.6 else 22 + int(beat * 3.0) % 4
			if beat < 1.6 and int(_time * 10.0) % 6 == 2 and int((_time - delta) * 10.0) % 6 != 2:
				_clod(_mound_pos + Vector2(randf_range(-5, 1), randf_range(-1, 2)), 0.5)
		_:
			var cycle: float = fmod(_time + float(_build) * 2.3, 9.0)
			if interest > 0.15 and state == State.PERCH:
				col = 22 + int(_time * 3.0) % 4
			elif cycle > 6.4:
				col = 16 + mini(5, int((cycle - 6.4) / 2.6 * 6.0))
			else:
				col = int(_time * 2.5) % 4
	_height = h
	_crow.position = pos.round()
	var sector: int = posmod(roundi(_face / (PI / 4.0)), 8)
	_sprite.frame = (_build * 8 + sector) * 62 + col
	_sprite.position.y = -roundf(h)
	_sprite.z_index = 5 if _is_flight() and h > 16.0 else 0
	if _ring != null:
		_ring.frame = _sprite.frame
		_ring.position = _sprite.position
		_ring.z_index = _sprite.z_index
		_ring.visible = not _is_flight()
	if _crow_spot != null:
		_crow_spot.position = Vector2(0, -roundf(h))
	for k: int in _drop_age.size():
		_drop_age[k] += delta
	# clods of earth
	for i: int in range(_clods.size() - 1, -1, -1):
		var c: Array = _clods[i]
		c[2] = float(c[2]) + delta
		var v: Vector2 = c[1] as Vector2
		v.y += 220.0 * delta
		c[1] = v
		c[0] = (c[0] as Vector2) + v * delta
		if float(c[2]) > float(c[3]):
			_clods.remove_at(i)
	_crow.queue_redraw()
	_ground.queue_redraw()


## A black feather with a silver tip on the ground at station `i` (it flutters down first, then lies there and its tip glints).
func _draw_feather(i: int) -> void:
	var rest: Vector2 = feather_position(i)
	var age: float = _drop_age[i]
	var at: Vector2 = rest
	var ang: float = 0.4 + float(i) * 1.3
	if age < 1.2: ## fluttering down from where the raven stood
		var k: float = age / 1.2
		at = rest + Vector2(sin(age * 7.0) * 5.0 * (1.0 - k), -22.0 * (1.0 - k))
		ang += sin(age * 6.0) * 0.8
	var dir: Vector2 = Vector2(cos(ang), sin(ang) * 0.55).normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	for j: int in 8:
		var p: Vector2 = (at + dir * (j - 3.5)).round()
		var tip: bool = j >= 6
		_ground.draw_rect(Rect2(p, Vector2.ONE), FEATHER_TIP if tip else FEATHER)
		if j > 0 and j < 6: ## the vane on one side, the edge a little lighter
			_ground.draw_rect(Rect2((p + side).round(), Vector2.ONE), FEATHER_EDGE if j % 2 == 0 else FEATHER)
			if j > 1 and j < 5:
				_ground.draw_rect(Rect2((p + side * 2.0).round(), Vector2.ONE), Color(FEATHER_EDGE, 0.8))
		if j == 7 or j == 6:
			_ground.draw_rect(Rect2((p + side).round(), Vector2.ONE), Color(FEATHER_TIP, 0.7))
	var g: float = fmod(_time * 0.8 + float(i) * 0.9, 2.6)
	if g < 0.2: ## the silver tip glints
		var tp: Vector2 = (at + dir * 3.5).round()
		var a: float = 1.0 - g / 0.2
		for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			_ground.draw_rect(Rect2(tp + d, Vector2.ONE), Color(GLINT, a))
		_ground.draw_rect(Rect2(tp, Vector2.ONE), Color(1, 1, 1, a))


func _clod(at: Vector2, strength: float) -> void:
	var a: float = randf_range(-PI, 0.0)
	var sp: float = randf_range(30.0, 70.0) * strength
	_clods.append([at, Vector2(cos(a) * sp * 0.8, sin(a) * sp - 20.0 * strength), 0.0, randf_range(0.35, 0.6), EARTH[randi() % EARTH.size()], at.y + randf_range(-1.0, 3.0)])


func _draw_shadow() -> void:
	var h: float = _height
	var w: float = clampf(5.0 - h * 0.05, 2.5, 5.0)
	var a: float = clampf(0.32 - h * 0.004, 0.1, 0.32)
	if state == State.PERCH or state == State.DONE:
		return
	_crow.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.45))
	_crow.draw_circle(Vector2.ZERO, w, Color(0.04, 0.03, 0.08, a))
	_crow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ground() -> void:
	# the glitter of its finds round the snag (a sun glint by day, a faint shimmer at night)
	for i: int in _glints.size():
		var p: Vector2 = _glints[i]
		var phase: float = fmod(_time * 0.7 + float(i) * 1.37, 3.2)
		var a: float = 0.35 + 0.25 * (1.0 - _night)
		_ground.draw_rect(Rect2(p, Vector2.ONE), Color(0.82, 0.86, 0.92, a))
		if phase < 0.18:
			var k: float = 1.0 - phase / 0.18
			for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				_ground.draw_rect(Rect2(p + d, Vector2.ONE), Color(GLINT, 0.8 * k))
			_ground.draw_rect(Rect2(p, Vector2.ONE), Color(1, 1, 1, k))
	# the dug pit once the chest is out
	if _solved:
		var e: Vector2 = _mound_pos.round()
		for dy: int in range(-4, 5):
			for dx: int in range(-11, 12):
				var r: float = Vector2(dx / 11.0, dy / 4.0).length()
				if r <= 1.0:
					var c: Color = EARTH[2] if r < 0.6 else (EARTH[0] if dy < 0 else EARTH[1])
					_ground.draw_rect(Rect2(e + Vector2(dx, dy), Vector2.ONE), Color(c, 0.9 if r < 0.85 else 0.5))
	for i: int in range(feathers, mini(dropped, _stations.size())):
		_draw_feather(i)
	for c: Array in _clods:
		var p: Vector2 = c[0] as Vector2
		if p.y > float(c[5]):
			p.y = float(c[5])
		var k: float = 1.0 - float(c[2]) / float(c[3])
		_ground.draw_rect(Rect2(p.round(), Vector2.ONE), Color(c[4] as Color, clampf(k * 1.5, 0.0, 1.0)))


# ------------------------------------------------------------------ sound

func _caw() -> void:
	Sfx.at(self, Sfx.pick(["crow_caw_a", "crow_caw_b"]), crow_position() + Vector2(0, -_height), -3.0)


func _flap_sound() -> void:
	Sfx.at(self, "crow_soft", crow_position() + Vector2(0, -_height), -14.0, 0.2)


func _sound_file(path: String, db: float, at: Vector2) -> void:
	if not ResourceLoader.exists(path) or not is_inside_tree():
		return
	var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	p.stream = load(path) as AudioStream
	p.volume_db = db
	p.max_distance = 380.0
	p.position = at
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
