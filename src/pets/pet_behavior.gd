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
	var trusted: bool = current >= float(lure["keep_at"])
	var holds: bool = kind != "" and kind != "dislikes" and registry != null
	if holds:
		var stage: int = registry.stage_of(bird.pet_key, peer)
		var reach: float = PetRules.lure_range(bird.species, stage, calm, _traits) * (float(lure["trusted_range"]) if trusted else 1.0)
		holds = distance <= reach and distance > 5.0
		holds = holds and (float(_speed[peer]) < float(lure["still_speed"]) or player.is_busy())
		## sneaking earns the first trust; once the bird trusts her, standing still with the food is enough (crouching to hold it out is no sneak)
		holds = holds and (trusted or player.stealth.sneaking or not bool(lure["sneak_required"]))
		holds = holds and not player.sprinting and not player.attack.is_swinging()
	if player.sprinting or player.attack.is_swinging():
		current = 0.0
	elif bird.state == WildCorvid.State.FLY:
		pass ## flying down to her (or away): the trust neither grows nor fades in the air
	elif bird._rest_time() and target_peer != peer and offered_peer != peer:
		current = PetRules.step_interest(current, false, 0.0, dt) ## asleep on its roost
	elif holds and not hungry(peer):
		pass ## it just ate (cooldown) or is full for today: it stays as calm as it is, it does not grow fonder, and it does not take fright
	else:
		current = PetRules.step_interest(current, holds, PetRules.lure_rate(kind, calm, _traits), dt)
	interest[peer] = current
	return current >= float(lure["keep_at"])


## True while this player may feed the bird (no cooldown after the last bite, not full for today).
func hungry(peer: int) -> bool:
	return PetRules.feed_block(bird.get_tree(), bird.pet_key, peer) == ""


## Any player the bird trusts right now: its own caution must not keep it from walking up to her.
func trusting() -> bool:
	var keep: float = float(_lure()["keep_at"])
	for peer: int in interest:
		if float(interest[peer]) >= keep:
			return true
	return false


## Called from the bird's think while nothing else is going on. True = the bird is busy with somebody (no wandering, no preening).
func drive(delta: float) -> bool:
	_pause_left -= delta
	if bird.state == WildCorvid.State.FEED and bird._elapsed < bird._duration:
		return true ## eating from her hand
	var lure: Dictionary = _lure()
	if offered_peer != 0:
		var asked: Player = _player(offered_peer)
		if asked == null or float(interest.get(offered_peer, 0.0)) < float(lure["keep_at"]):
			_withdraw(0.3)
		elif bird.global_position.distance_to(asked.global_position) > float(lure["stand_off"]) + 22.0:
			var peer: int = offered_peer
			_withdraw(1.0) ## she stepped back a little: no fright, it follows her again
			target_peer = peer
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
				offered_peer = target_peer ## (also while it may not eat yet: she sees the prompt greyed out, with the reason)
				bird._offer.rpc(offered_peer)
			_look(goal)
			return true
		if bird.state == WildCorvid.State.FLY:
			return true
		if (not bird._perch_path.is_empty() or bird._height > 1.0 or distance > float(lure["fly_over"])) and _fly_near(goal):
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
		interest[peer] = maxf(float(interest.get(peer, 0.0)), float(_lure()["take_min"]) + 0.1) ## it stays: after the cooldown it asks for more
		target_peer = peer
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


## A bird on a branch or far off flutters down to a spot a few hops in front of her instead of walking all the way.
func _fly_near(player: Player) -> bool:
	var land: float = float(_lure()["stand_off"]) + 16.0
	var away: Vector2 = (bird.global_position - player.global_position).normalized()
	var space: PhysicsDirectSpaceState2D = bird.get_world_2d().direct_space_state
	for angle: float in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var point: Vector2 = player.global_position + away.rotated(angle) * land
		if not _ground_ok(point) or point.distance_to(bird.global_position) < 8.0:
			continue
		var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
		query.position = point
		query.collision_mask = 1
		if not space.intersect_point(query, 1).is_empty():
			continue
		_pause_left = 0.4
		return bird._fly_to_spot({"position": point, "height": 0.0, "path": ""})
	return false


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
			bird._act.rpc(WildCorvid.State.HOP, clampf(length / (float(bird._spec["walk_speed"]) * 1.35), 0.26, 0.44), step.angle(), bird.global_position, bird.global_position + step, Vector2.ZERO, 0.0, 0.0, 0.0, "", 0.0)
			return
	target_peer = 0


## The population refuses landings next to a player (right for fleeing birds); a bird walking up to her only needs flat, free ground.
func _ground_ok(point: Vector2) -> bool:
	return Terrain.relief == null or Terrain.relief.flat_around(point, 4.0)
