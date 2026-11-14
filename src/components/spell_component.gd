class_name SpellComponent
extends Node
## Magic of one player (docs/magie_konzept.md): the staff in her hand, the crystals in it and each spell crystal's recharge.
## Host-authoritative: the host reads the staff from its copy of the bag, keeps the recharge clocks and tells every peer (`_rpc_state`).
## The owner starts the cast motion at once (Player.begin_cast, replicated like picking); at the release moment it asks the host, which
## checks everything again, starts the recharge and opens the spell's zone on every peer (`_rpc_zone`). The zone's host copy deals the
## burning and the healing; all copies draw it.
## A staff has one or two PRONGS (docs/magie_konzept.md 17): prong 0 = "sp"/"gm" (left mouse button), prong 1 = "sp2"/"gm2" (right mouse
## button, the Bleichgabel only). Each prong's crystal charges on its own. The forked staff adds GABELSCHLAG (the other prong cast within
## `window` seconds after the first comes out `echo` times as strong) and the bond of its two crystals (GLEICHKLANG / ZWIESPALT changes
## every recharge), SpellRules.fork_rules.

signal state_changed
signal cast_done(spell_item: String) ## every peer: a spell of this player opened (the lake witch's quest counts the first one)
signal fork_struck(prong: int, power: float) ## every peer: a GABELSCHLAG left prong `prong` (StaffCrystals draws the lightning)

const SENDER_HOST: int = 1

var staff_held: bool = false
var staff_id: String = "" ## the staff in her hand ("" = none)
var prongs: int = 1 ## how many prongs it has (1 or 2)
var bond: String = "" ## "harmony" / "tension" / "" (SpellRules.fork_bond)
var _sp: PackedStringArray = PackedStringArray(["", ""]) ## spell crystal item ids per prong
var _gm: PackedStringArray = PackedStringArray(["", ""]) ## gem item ids per prong
var _left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0]) ## seconds until each crystal is full again (every peer counts down)
var _total: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _flashes: PackedFloat32Array = PackedFloat32Array([0.0, 0.0]) ## 1 when a crystal has just become full (its crown blinks)
var _player: Player
var _pending_until_msec: PackedInt64Array = PackedInt64Array([0, 0]) ## owner: a cast was sent, no second one until the host answered
var _aim: SpellAim ## owner: the aim marks (SpellAim)
var _last_prong: int = -1 ## host: the prong cast last (GABELSCHLAG)
var _last_msec: int = -100000

## Prong 0, the names everything used before the fork came.
var spell: String:
	get:
		return _sp[0]
	set(value):
		_sp[0] = value
var gem: String:
	get:
		return _gm[0]
	set(value):
		_gm[0] = value
var charge_left: float:
	get:
		return _left[0]
	set(value):
		_left[0] = value
var charge_total: float:
	get:
		return _total[0]
	set(value):
		_total[0] = value


func setup(player: Player) -> void:
	_player = player


func _ready() -> void:
	if _player == null:
		_player = get_parent() as Player
	if multiplayer.is_server():
		_player.inventory.changed.connect(_host_refresh)
		_player.inventory.socketed.connect(_on_socketed)
		_host_refresh.call_deferred()
	else:
		_rpc_request_state.rpc_id(SENDER_HOST)


func _process(delta: float) -> void:
	if _aim == null and staff_held and _player != null and _player.is_multiplayer_authority() and _player.is_inside_tree():
		_aim = SpellAim.new() ## her own screen: what the crystal would do now
		_aim.name = "SpellAim"
		_aim.spells = self
		_player.add_child(_aim)
	var rate: float = recharge_rate()
	for p: int in 2:
		if _left[p] > 0.0:
			_left[p] = maxf(_left[p] - delta * rate, 0.0)
			if _left[p] <= 0.0 and _sp[p] != "":
				_flashes[p] = 1.0
				if is_multiplayer_authority() and _player != null:
					SpellZone.sound(_player, "ready", _player.global_position, -6.0 + 1.5 * float(p)) ## only she hears her crystal is full again
		_flashes[p] = move_toward(_flashes[p], 0.0, delta * 2.5)


## Multiplier (>= 1.0) on crystal recharge speed from Singender Resonanzwind (on white quartz), Arkanes Quarzgewitter, and Resonanz-Obelisken.
func recharge_rate() -> float:
	if _player == null or not _player.is_inside_tree():
		return 1.0
	return DesertHeat.spell_recharge_rate(_player.get_tree(), _player.global_position)


func spell_of(prong: int) -> String:
	return _sp[clampi(prong, 0, 1)]


func gem_of(prong: int) -> String:
	return _gm[clampi(prong, 0, 1)]


## 0..1: how full a crystal is (1 = ready).
func charge_fraction(prong: int = 0) -> float:
	var p: int = clampi(prong, 0, 1)
	if _total[p] <= 0.0:
		return 1.0
	return clampf(1.0 - _left[p] / _total[p], 0.0, 1.0)


func left_of(prong: int) -> float:
	return _left[clampi(prong, 0, 1)]


## 0..1: the blink of a crystal that has just become ready.
func ready_flash(prong: int = 0) -> float:
	return _flashes[clampi(prong, 0, 1)]


func is_ready(prong: int = 0) -> bool:
	return staff_held and prong >= 0 and prong < prongs and _sp[prong] != "" and _left[prong] <= 0.05


## Everything the next cast of a prong does (crystal + its gem), {} without a crystal.
func cast_params(prong: int = 0) -> Dictionary:
	var p: int = clampi(prong, 0, 1)
	return SpellRules.params(_sp[p], _gm[p]) if _sp[p] != "" and p < prongs else {}


# ---------------------------------------------------------------- owner: casting

## Owner: LMB (prong 0) or RMB (prong 1) with the staff. Starts the cast motion toward `aim` (world px) when that crystal is full. True
## when it started. Each kind checks first what only makes sense with a target: Glutschwarm needs a shadow creature in reach (else nothing
## happens and the crystal stays full), Nebelschleier picks the player under the pointer (else herself), Leerenschlund needs the health it costs.
func try_cast(aim: Vector2, prong: int = 0) -> bool:
	if not is_multiplayer_authority() or not is_ready(prong) or Time.get_ticks_msec() < _pending_until_msec[prong]:
		return false
	var p: Dictionary = cast_params(prong)
	if p.is_empty():
		return false
	var origin: Vector2 = _player.global_position
	var kind: String = String(p["kind"])
	var target: Vector2 = origin if kind == "aura" else SpellRules.target_point(origin, aim, float(p["range"]))
	var toward: Vector2 = (aim - origin).normalized() if aim.distance_to(origin) > 2.0 else _player.facing
	var chosen: int = 0
	match kind:
		"volley":
			var targets: Array[HurtboxComponent] = volley_targets(_player, origin, aim, float(p["range"]))
			if targets.is_empty():
				_say("KEIN ZIEL", SpellRules.school_color("ember"))
				return false ## Glutschwarm: without a shadow creature in reach nothing happens
			target = aim
			toward = (SpellZone.feet_of(targets[0]) - origin).normalized()
		"veil":
			var mate: Player = veil_target(origin, aim, float(p["range"]))
			chosen = int(mate.name) if mate != null else get_multiplayer_authority()
			target = mate.global_position if mate != null else origin
			if mate != null and mate != _player:
				toward = (mate.global_position - origin).normalized()
		"maw":
			if not SpellRules.can_pay(_player.health.current, _player.health.max_health, float(p["price"])):
				_say("ZU WENIG LEBEN", SpellRules.school_color("void"))
				return false ## the void always takes its price, and never the last of her
	if bool(p.get("no_water", false)) and wet(target, float(p["radius"])):
		_say("NICHT IM WASSER", Color("9fe6ff"))
		return false ## Wurzelgrund: roots do not grow out of water
	var timing: Vector2 = SpellRules.cast_timing(String(p["cast"]))
	var motion: String = String(p["cast"]) + ("@1" if prong == 1 else "") ## the prong rides along in the action's name (Player.cast_prong)
	if not _player.begin_cast(motion, toward, target, func() -> void: _release(target, chosen, prong), timing.y):
		return false
	_pending_until_msec[prong] = Time.get_ticks_msec() + int((timing.x + 0.6) * 1000.0)
	return true


func _say(text: String, colour: Color) -> void:
	DamageNumber.spawn_text(_player.get_parent(), _player.global_position + Vector2(0.0, -50.0), text, colour)


## Glutschwarm's targets: every living shadow creature within `reach` of `origin`, one hurtbox per creature, the one nearest to the
## pointer first.
static func volley_targets(from: Node2D, origin: Vector2, aim: Vector2, reach: float) -> Array[HurtboxComponent]:
	var found: Array[HurtboxComponent] = []
	var seen: Dictionary = {}
	for box: HurtboxComponent in HitScan.circle(from, origin, reach, SpellZone.HURTBOX_MASK):
		if box is HarvestHurtbox or box.health == null or box.health.current <= 0.0:
			continue
		var body: Node = box.get_parent()
		if body == null or seen.has(body.get_instance_id()) or SpellZone.feet_of(box).distance_to(origin) > reach:
			continue
		seen[body.get_instance_id()] = true
		found.append(box)
	found.sort_custom(func(a: HurtboxComponent, b: HurtboxComponent) -> bool: return SpellZone.feet_of(a).distance_squared_to(aim) < SpellZone.feet_of(b).distance_squared_to(aim))
	return found


## Nebelschleier's target: the living player whose body is under the pointer (a person is tall: anywhere from the feet to the head counts)
## and within `reach` of `origin`; null = she veils herself.
static func veil_target(origin: Vector2, aim: Vector2, reach: float) -> Player:
	var best: Player = null
	var best_distance: float = 16.0
	for player: Player in Player.all:
		if player.health.current <= 0.0 or not player.is_inside_tree() or player.global_position.distance_to(origin) > reach + 8.0:
			continue
		var off: Vector2 = aim - (player.global_position + Vector2(0.0, -18.0))
		var distance: float = Vector2(off.x, off.y * 0.55).length()
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _release(target: Vector2, chosen: int, prong: int) -> void:
	if multiplayer.is_server():
		_host_cast(target, chosen, prong)
	else:
		_rpc_cast.rpc_id(SENDER_HOST, target, chosen, prong)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cast(target: Vector2, chosen: int, prong: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_host_cast(target, chosen, clampi(prong, 0, 1))


## Host: one cast, checked again: she lives, holds the staff with this crystal, it is full, she is not in the water, and what the kind
## needs is there. A refused cast keeps the crystal full.
func _host_cast(target: Vector2, chosen: int = 0, prong: int = 0) -> void:
	_host_refresh()
	if _player.health.current <= 0.0 or not is_ready(prong) or _player.swim > 0:
		_send_state() ## the owner's mirror learns why nothing happened
		return
	var p: Dictionary = cast_params(prong)
	var origin: Vector2 = _player.global_position
	var kind: String = String(p["kind"])
	var at: Vector2 = origin if kind == "aura" else SpellRules.target_point(origin, target, float(p["range"]) + 12.0)
	var extra: Array = []
	var fork: Dictionary = SpellRules.fork_rules(_player.inventory.active_staff())
	var power: float = 1.0
	if prongs >= 2 and _last_prong == 1 - prong and float(Time.get_ticks_msec() - _last_msec) / 1000.0 <= float(fork["window"]):
		power = float(fork["echo"]) ## GABELSCHLAG: the other prong answered in time
	match kind:
		"volley":
			var targets: Array[HurtboxComponent] = volley_targets(_player, origin, target, float(p["range"]) + 12.0)
			for step: Array in SpellRules.volley_plan(targets.size(), int(p["shards"]), float(p["focus"])):
				extra.append([String(targets[int(step[0])].get_parent().get_path()), float(step[1])])
			if extra.is_empty():
				_send_state()
				return
			at = origin
		"veil":
			var mate: Player = _player_by_id(chosen)
			if mate == null or mate.health.current <= 0.0 or mate.global_position.distance_to(origin) > float(p["range"]) + 24.0:
				mate = _player
			at = mate.global_position
			extra.append(int(mate.name))
			if float(p["group"]) > 0.0: ## SCHLEIERKREIS: everybody close beside the target too
				for other: Player in Player.all:
					if other != mate and other.health.current > 0.0 and other.global_position.distance_to(mate.global_position) <= float(p["group"]):
						extra.append(int(other.name))
			var veil_seconds: float = float(SpellRules.empower(p, power)["seconds"])
			for id: Variant in extra:
				var veiled: Player = _player_by_id(int(id))
				if veiled != null and veiled.effects != null:
					veiled.effects.apply("veil", veil_seconds, float(p["tier"]), get_multiplayer_authority())
		"maw":
			if not SpellRules.can_pay(_player.health.current, _player.health.max_health, float(p["price"])):
				_send_state()
				return
			var price: float = SpellRules.maw_price(_player.health.max_health, float(p["price"]))
			_player.health.set_health(_player.health.current - price) ## the price, before anything else happens
			extra.append(price)
	if bool(p.get("no_water", false)) and wet(at, float(p["radius"])):
		_send_state() ## refused, the crystal keeps its charge
		return
	_last_prong = -1 if power > 1.0 else prong ## a fork strike is spent: the next one needs a fresh pair
	_last_msec = Time.get_ticks_msec()
	_total[prong] = float(p["cooldown"]) * float(fork["charge"])
	_left[prong] = _total[prong]
	_send_state()
	_rpc_zone.rpc(_sp[prong], _gm[prong], at, get_multiplayer_authority(), extra, power, prong)


func _player_by_id(id: int) -> Player:
	for player: Player in Player.all:
		if int(player.name) == id:
			return player
	return null


## Host, Leerenschlund's SATTER SCHLUND: it fed well, the crystal of `prong` charges the rest of its time twice as fast.
func fed_well(prong: int = 0) -> void:
	var p: int = clampi(prong, 0, 1)
	if multiplayer.is_server() and _left[p] > 0.0:
		_left[p] *= 0.5
		_total[p] *= 0.5 ## the crown keeps its fill, it only runs faster now
		_send_state()


## True when the circle of `radius` round `at` lies in water (its middle or a good part of its rim): a river, a lake, a pond.
func wet(at: Vector2, radius: float) -> bool:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("water_depth"):
		return false
	var points: Array[Vector2] = [at]
	for k: int in 8:
		var a: float = TAU * float(k) / 8.0
		points.append(at + Vector2(cos(a), sin(a) * SpellZone.SQUASH) * radius * 0.7)
	var wet_points: int = 0
	for point: Vector2 in points:
		if float(world.call("water_depth", point)) > 0.05:
			wet_points += 1
	return wet_points >= 3 or float(world.call("water_depth", at)) > 0.05


## Every peer: the spell opens at `at`. `extra`: Glutschwarm [[target body path, damage factor] per shard], Nebelschleier [veiled peer ids],
## Leerenschlund [the price paid]. `power` > 1 = a GABELSCHLAG (SpellRules.empower), `prong` = which prong it left.
@rpc("any_peer", "call_local", "reliable")
func _rpc_zone(spell_item: String, gem_item: String, at: Vector2, caster: int, extra: Array, power: float, prong: int) -> void:
	if not _from_host():
		return
	cast_done.emit(spell_item)
	if is_inside_tree():
		get_tree().call_group("desert_spell_listeners", "on_spell_cast", _player.global_position if _player != null else at, at, spell_item)
	var p: Dictionary = SpellRules.empower(SpellRules.params(spell_item, gem_item), power)
	p["prong"] = prong
	var level: Node = get_tree().get_first_node_in_group("world") ## inside the y-sorted world, so roots and walls sort with everybody
	if level == null:
		level = get_tree().current_scene
	if p.is_empty() or level == null:
		return
	var zone: Node2D
	match String(p["kind"]):
		"aura":
			zone = BanishLight.new()
		"volley":
			zone = EmberVolley.new()
		"veil":
			zone = VeilStream.new()
		"maw":
			zone = VoidMaw.new()
		_:
			zone = RootGround.new()
	zone.position = at
	zone.set("params", p)
	zone.set("caster", caster)
	zone.set("extra", extra)
	level.add_child(zone)
	if String(p["kind"]) == "maw" and extra.size() > 0 and _player != null: ## the price, shown where she stands
		DamageNumber.spawn_text(_player.get_parent(), _player.global_position + Vector2(0.0, -46.0), "-%d" % roundi(float(extra[0])), SpellRules.school_color("void"))
	if power > 1.0 and _player != null:
		fork_struck.emit(prong, power)
		SpellZone.sound(_player, "fork_strike", _player.global_position, 0.0)
		DamageNumber.spawn_text(_player.get_parent(), _player.global_position + Vector2(0.0, -58.0), "GABELSCHLAG", Color("f6f2e0"))


## Every peer: Glutschwarm's FUNKENSPRUNG, the fire of a creature that died jumps from `from` to `to` (a body path) with what it had left.
@rpc("any_peer", "call_local", "reliable")
func _rpc_burn_jump(from: Vector2, to: String, dps: float, seconds: float, jump: float) -> void:
	if not _from_host():
		return
	var body: Node2D = get_tree().root.get_node_or_null(NodePath(to)) as Node2D
	if body != null:
		EmberBurn.leap(body, from, dps, seconds, get_multiplayer_authority(), jump)


# ---------------------------------------------------------------- host: what she holds

func _host_refresh() -> void:
	if not multiplayer.is_server() or _player == null or _player.inventory == null:
		return
	var staff: Dictionary = _player.inventory.active_staff()
	var held_now: bool = not staff.is_empty()
	var id_now: String = String(staff.get("id", ""))
	var count: int = SpellRules.prongs_of(id_now) if held_now else 1
	var sp_now: PackedStringArray = PackedStringArray([SpellRules.spell_in(staff, 0), SpellRules.spell_in(staff, 1) if count > 1 else ""])
	var gm_now: PackedStringArray = PackedStringArray([SpellRules.gem_in(staff, 0), SpellRules.gem_in(staff, 1) if count > 1 else ""])
	var bond_now: String = SpellRules.fork_bond(staff)
	if held_now == staff_held and id_now == staff_id and sp_now == _sp and gm_now == _gm and bond_now == bond:
		return
	staff_held = held_now
	staff_id = id_now
	prongs = count
	bond = bond_now
	_sp = sp_now
	_gm = gm_now
	_send_state()


## Host: a crystal went into or out of a staff: a new spell crystal starts empty and charges (taking one out and back gives nothing).
func _on_socketed(socket: String) -> void:
	_socket_sound()
	if not socket.begins_with(SpellRules.KEY_SPELL):
		return
	var prong: int = SpellRules.prong_of_key(socket)
	var staff: Dictionary = _player.inventory.active_staff()
	var crystal: String = SpellRules.spell_in(staff, prong)
	if crystal == "":
		for stack: Dictionary in _player.inventory.slots: ## the staff that changed may lie in the bag
			if SpellRules.is_staff(stack) and SpellRules.spell_in(stack, prong) != "":
				crystal = SpellRules.spell_in(stack, prong)
				staff = stack
				break
	if crystal == "":
		return
	_host_refresh()
	_total[prong] = float(SpellRules.params(crystal).get("cooldown", 0.0)) * float(SpellRules.fork_rules(staff)["charge"])
	_left[prong] = _total[prong]
	_send_state()


func _socket_sound() -> void:
	if get_multiplayer_authority() == multiplayer.get_unique_id():
		_rpc_socket_sound()
	else:
		_rpc_socket_sound.rpc_id(get_multiplayer_authority())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_socket_sound() -> void:
	if _from_host() and _player != null:
		SpellZone.sound(_player, "socket", _player.global_position, -4.0)


## Developer cheat (host): every crystal is full at once.
func debug_recharge() -> void:
	if multiplayer.is_server():
		_left = PackedFloat32Array([0.0, 0.0])
		_send_state()


func _send_state() -> void:
	_rpc_state.rpc(staff_held, staff_id, prongs, bond, _sp, _gm, _left, _total)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if multiplayer.is_server():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), staff_held, staff_id, prongs, bond, _sp, _gm, _left, _total)


@rpc("any_peer", "call_local", "reliable")
func _rpc_state(held: bool, id: String, count: int, bond_now: String, sp: PackedStringArray, gm: PackedStringArray, left: PackedFloat32Array, total: PackedFloat32Array) -> void:
	if not _from_host() or sp.size() < 2 or gm.size() < 2 or left.size() < 2 or total.size() < 2:
		return
	var was_ready: Array[bool] = [is_ready(0), is_ready(1)]
	staff_held = held
	staff_id = id
	prongs = clampi(count, 1, 2)
	bond = bond_now
	_sp = sp
	_gm = gm
	_left = left
	_total = total
	_pending_until_msec = PackedInt64Array([0, 0])
	for p: int in 2:
		if not was_ready[p] and is_ready(p) and left[p] <= 0.0 and total[p] > 0.0:
			_flashes[p] = 1.0
	state_changed.emit()


func _from_host() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	return sender == SENDER_HOST or sender == 0 or (multiplayer.is_server() and sender == multiplayer.get_unique_id())
