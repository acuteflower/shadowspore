class_name PetBehavior
extends RefCounted
## The part of a wild crow or raven that can come to trust somebody (docs/pet_konzept.md, host only). It lives inside `WildCorvid`.
##
## Lure: while Ellie stands still, sneaking, with food the bird wants in her hand and inside its lure range, a hidden trust grows (`interest`).
## Normal fear is suspended for her while it is above `keep_at`. At 1.0 the bird hops towards her in short, careful steps (head up between
## the hops); close enough it makes an offer (`offered_peer`: she gets "E FÜTTERN"). If she moves, sprints or swings, the trust drains and the
## bird flees as always. The Rissfeder (`corvid_calm`) widens the range and speeds the trust up, so the talisman is what makes the first
## contact possible at all. Taking the food (`take`) is validated here and counted by `PetRegistry`.

var bird: WildCorvid
var interest: Dictionary = {} ## peer id -> 0..1.2 hidden trust
var target_peer: int = 0 ## the player it is walking up to (0 = none)
var offered_peer: int = 0
var _traits: Array[String]
var _last_pos: Dictionary = {}
var _speed: Dictionary = {}
var _pause_left: float = 0.0
var _offer_left: float = 0.0


func _init(owner_bird: WildCorvid) -> void:
	bird = owner_bird
	_traits = PetRules.traits_of(owner_bird.pet_key)


func _lure() -> Dictionary:
	return PetRules.table()["lure"] as Dictionary


## Called by the bird's sense for every living player (every `sense_interval`). True = the bird is not afraid of this player right now.
func tolerates(player: Player, distance: float, dt: float) -> bool:
	var peer: int = player.name.to_int()
	var speed: float = 0.0
	if _last_pos.has(peer):
		speed = (player.global_position - (_last_pos[peer] as Vector2)).length() / maxf(dt, 0.001)
	_last_pos[peer] = player.global_position
	_speed[peer] = lerpf(float(_speed.get(peer, speed)), speed, 0.6)
	var current: float = float(interest.get(peer, 0.0))
	var lure: Dictionary = _lure()
	var registry: PetRegistry = PetRegistry.of(bird.get_tree())
	var stack: Dictionary = player.inventory.slots[player.inventory.selected] as Dictionary
	var kind: String = PetRules.reaction(bird.species, String(stack.get("id", "")), bird.pet_key) if not stack.is_empty() else ""
	var calm: float = player.talismans.corvid_calm()
	var holds: bool = kind != "" and kind != "dislikes" and registry != null
	if holds:
		var stage: int = registry.stage_of(bird.pet_key, peer)
		holds = distance <= PetRules.lure_range(bird.species, stage, calm, _traits) and distance > 5.0
		holds = holds and float(_speed[peer]) < float(lure["still_speed"])
		holds = holds and (player.stealth.sneaking or not bool(lure["sneak_required"]))
		holds = holds and not player.sprinting and not player.attack.is_swinging()
		holds = holds and registry.cooldown_left(bird.pet_key, peer) <= 0.0
		holds = holds and registry.fed_today(bird.pet_key, peer) < int((PetRules.table()["feed"] as Dictionary)["full_after"])
	if bird.offered_peer == peer and kind != "" and kind != "dislikes" and distance <= float((PetRules.table()["feed"] as Dictionary)["reach"]) + 12.0:
		holds = true ## she is crouching with the food out (a busy action, so no longer "sneaking"): the offer stands
	if bird.state == WildCorvid.State.FLY or bird._rest_time() or player.sprinting or player.attack.is_swinging():
		current = 0.0
	else:
		current = PetRules.step_interest(current, holds, PetRules.lure_rate(kind, calm, _traits), dt)
	interest[peer] = current
	return current >= float(lure["keep_at"])


## Called from the bird's think while nothing else is going on. True = the bird is busy with somebody (no wandering, no preening).
func drive(delta: float) -> bool:
	_pause_left -= delta
	if bird.state == WildCorvid.State.FEED and bird._elapsed < bird._duration:
		return true ## eating from her hand
	var lure: Dictionary = _lure()
	if offered_peer != 0:
		_offer_left -= delta
		var asked: Player = _player(offered_peer)
		if asked == null or _offer_left <= 0.0 or float(interest.get(offered_peer, 0.0)) < float(lure["keep_at"]):
			_withdraw(0.3)
		else:
			_look(asked)
			return true
	if target_peer != 0:
		var goal: Player = _player(target_peer)
		if goal == null or float(interest.get(target_peer, 0.0)) < float(lure["keep_at"]):
			target_peer = 0
			return false
		var distance: float = bird.global_position.distance_to(goal.global_position)
		if distance <= float(lure["stand_off"]) + 4.0:
			if float(interest.get(target_peer, 0.0)) >= float(lure["take_min"]):
				offered_peer = target_peer
				_offer_left = float(lure["scare_after_offer"])
				bird._offer.rpc(offered_peer)
			_look(goal)
			return true
		if _pause_left <= 0.0:
			_hop(goal, distance)
		else:
			_look(goal)
		return true
	var best_peer: int = 0
	var best: float = 0.0
	for peer: int in interest:
		if float(interest[peer]) > best:
			best = float(interest[peer])
			best_peer = peer
	if best >= float(lure["approach_at"]):
		target_peer = best_peer
		_pause_left = 0.0
		return true
	if best > 0.25:
		var watched: Player = _player(best_peer)
		if watched != null:
			_look(watched) ## it has noticed the food: head up, eyes on her
			return true
	return false


## Host: the player holding out food presses E. Returns {ok, reaction, gain, bp, stage, up, item}; on success the item is gone from her bag
## and the bird eats from her hand.
func take(player: Player) -> Dictionary:
	var peer: int = player.name.to_int()
	var result: Dictionary = {"ok": false, "reaction": "", "gain": 0.0, "bp": 0.0, "stage": 0, "up": false, "item": ""}
	var registry: PetRegistry = PetRegistry.of(bird.get_tree())
	if registry == null or offered_peer != peer:
		return result
	var feed: Dictionary = PetRules.table()["feed"] as Dictionary
	if bird.global_position.distance_to(player.global_position) > float(feed["reach"]):
		return result
	var stack: Dictionary = player.inventory.slots[player.inventory.selected] as Dictionary
	if stack.is_empty():
		return result
	var item: String = String(stack["id"])
	result["item"] = item
	result = registry.feed(bird.pet_key, bird.species, peer, item).merged({"item": item}, true)
	if bool(result["ok"]):
		result["registered"] = registry.ensure_record(bird, peer)
		player.inventory.remove_item(item, 1)
		offered_peer = 0
		bird._offer.rpc(0)
		interest[peer] = 0.55
		target_peer = 0
		_look(player)
		bird._eat.rpc(float(feed["take_seconds"]), (player.global_position - bird.global_position).angle())
	else:
		_withdraw(0.0) ## it does not want that: it turns away and the trust is gone
	return result


## Anything that frightens the bird for real (an alarm, a flight): all trust is gone.
func reset() -> void:
	interest.clear()
	_withdraw(0.0)


func _withdraw(keep: float) -> void:
	if offered_peer != 0:
		var peer: int = offered_peer
		offered_peer = 0
		bird._offer.rpc(0)
		interest[peer] = minf(float(interest.get(peer, 0.0)), keep)
	target_peer = 0


func _player(peer: int) -> Player:
	for player: Player in Player.all:
		if player.name.to_int() == peer and player.health.current > 0.0:
			return player
	return null


func _look(player: Player) -> void:
	var angle: float = (player.global_position - bird.global_position).angle()
	if bird.state != WildCorvid.State.WATCH or bird._elapsed > bird._duration - 0.25 or absf(angle_difference(angle, bird.facing)) > 0.5:
		bird.facing = angle
		bird._set_mood(WildCorvid.State.WATCH, 1.2)


func _hop(player: Player, distance: float) -> void:
	var lure: Dictionary = _lure()
	var hop: Array = lure["hop"] as Array
	var stand_off: float = float(lure["stand_off"])
	var length: float = minf(randf_range(float(hop[0]), float(hop[1])), distance - stand_off)
	var pause: Array = lure["pause"] as Array
	_pause_left = randf_range(float(pause[0]), float(pause[1]))
	if length < 3.0:
		return
	var direction: Vector2 = (player.global_position - bird.global_position).normalized()
	for angle: float in [0.0, 0.5, -0.5]:
		var step: Vector2 = direction.rotated(angle) * length
		if not bird.test_move(bird.global_transform, step) and _ground_ok(bird.global_position + step):
			bird._act.rpc(WildCorvid.State.WALK, maxf(0.4, length / float(bird._spec["walk_speed"]) * 1.25), step.angle(), bird.global_position, bird.global_position + step, Vector2.ZERO, 0.0, 0.0, 0.0, "", 0.0)
			return
	target_peer = 0


## The population refuses landings next to a player (right for fleeing birds); a bird walking up to her only needs flat, free ground.
func _ground_ok(point: Vector2) -> bool:
	return Terrain.relief == null or Terrain.relief.flat_around(point, 4.0)
