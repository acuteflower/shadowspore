class_name NightBehavior
extends RefCounted
## What makes a shadow creature a creature of the night (docs/nacht_monster_konzept.md section 6). Host only; the `NightDirector` attaches one to every
## creature it spawns (`enemy.night`), and the creature asks it twice: where to walk while it has nothing to hunt (`walk_dir`), and what the light lets it do
## (`limit`). Light is land: a creature does not enter the town's light on its own, it stops at the edge; one in a raid ("excited") may, slowed and in pain.

var goal: Vector2 = Vector2.INF ## the patrol goal; infinite = the director picks a new one
var queue: Array[Vector2] = [] ## goals that follow (a raid: the gap, then the player)
var excited: bool = false ## in a raid: the light is no wall
var hunter: bool = false ## a "silent night" hunter: always knows where the nearest player is
var remnant: bool = false ## a leftover of the day: slower, weak, burns in the sun
var retreat: bool = false ## the morning: back to the dark
var key: String = "" ## the group it belongs to
var cost: float = 1.0
var top_speed: float = 100.0 ## the creature's fastest walk (from its data): the light slows it to a share of this
var speed_cap: float = 0.0 ## a leftover of the day is held to this speed (0 = no cap)
var home: Vector2 = Vector2.INF ## where it was born (a patrol sometimes leads back)
var town: TownManager

## The light is a gradient, not a wall (docs/nacht_monster_konzept.md): the outer `dim_px` of the town's light is a dim band that a courageous creature may enter, slowed,
## to probe; the core stays painful for everyone. Courage = this creature's own temper + its pack + the night (`courage_extra`, set by the director each tick).
var courage: float = 0.4 ## its own temper (rolled at birth) plus the bonus of its pack
var courage_extra: float = 0.0 ## the night's share: moon, dark gaps, many lamps (negative)
var scout: bool = false ## sent ahead to look at the base: its report opens the raids of the night
var caller: bool = false ## a listener that can call the dark together (killing it ends the call)
var calling: bool = false ## it stands still and calls
var ram: bool = false ## a crusher in a raid: it goes for the weakest point of the base
var pack: int = 0 ## the number of the pack it was born in (0 = none)
var observed: float = 0.0 ## seconds a scout has watched the base
var probing: bool = false ## its goal lies in the dim band: it walks right up to it

var _stuck_at: Vector2 = Vector2.INF
var _stuck_time: float = 0.0
var _dim_time: float = 0.0 ## seconds spent in the dim band
var _probe_cool: float = 0.0 ## after a probe it keeps out of the dim band for a while


## Speed factor over the creature's wander speed while it walks to `goal`.
func speed_factor() -> float:
	var behavior: Dictionary = NightRules.config().behavior as Dictionary
	var factor: float = float(behavior.raid_speed) if excited or hunter else float(behavior.patrol_speed)
	return factor * (float((NightRules.config().remnants as Dictionary).speed) if remnant else 1.0)


## The direction to walk to `goal` (zero on arrival or when stuck; the goal is then cleared or advanced). `nav` is the creature's own `EnemyNavigation`.
func walk_dir(enemy: Node2D, nav: EnemyNavigation, delta: float) -> Vector2:
	var behavior: Dictionary = NightRules.config().behavior as Dictionary
	var here: Vector2 = enemy.global_position
	if here.distance_to(goal) <= (6.0 if probing else float(behavior.arrive_px)):
		_next_goal()
		return Vector2.ZERO
	if _stuck_at.is_finite() and here.distance_to(_stuck_at) < 6.0:
		_stuck_time += delta
		if _stuck_time >= float(behavior.stuck_seconds):
			_stuck_time = 0.0
			_stuck_at = Vector2.INF
			goal = Vector2.INF
			queue.clear()
			return Vector2.ZERO
	else:
		_stuck_at = here
		_stuck_time = 0.0
	if nav.segment_clear(here, goal):
		return (goal - here).normalized()
	return nav.direction_to(goal, delta)


func _next_goal() -> void:
	probing = false
	goal = queue.pop_front() if not queue.is_empty() else Vector2.INF
	_stuck_at = Vector2.INF
	_stuck_time = 0.0


## The creature's velocity after the light has had its say: outside the light nothing changes; at the edge the way in is closed (a raid member pushes in, slowed);
## inside the light it is slowed and pushed out. A leftover of the day is slow everywhere.
func limit(enemy: Node2D, velocity: Vector2, delta: float) -> Vector2:
	var out: Vector2 = velocity
	if calling:
		return Vector2.ZERO ## a caller stands and calls
	if speed_cap > 0.0:
		out = out.limit_length(speed_cap)
	_probe_cool = maxf(0.0, _probe_cool - delta)
	if town == null or not town.founded:
		return out
	var behavior: Dictionary = NightRules.config().behavior as Dictionary
	var cfg: Dictionary = NightRules.config().courage as Dictionary
	var here: Vector2 = enemy.global_position
	var depth: float = town.light_depth(here)
	if depth > 0.0:
		if not excited and depth <= float(cfg.dim_px) and brave():
			_dim_time += delta ## a probe: slowed, in the dim band, it feels how far the light holds
			town.light_touch(here)
			if _dim_time < float(cfg.dim_seconds):
				return out.limit_length(top_speed * float(cfg.dim_slow))
			_dim_time = 0.0 ## enough: it darts back and keeps away for a while
			_probe_cool = float(cfg.probe_cooldown)
			goal = Vector2.INF
			probing = false
			queue.clear()
		out = out.limit_length(top_speed * float(behavior.light_slow)) ## in pain
		town.light_touch(here)
		return out if excited else out + town.light_outward(here) * float(behavior.light_push)
	_dim_time = maxf(0.0, _dim_time - delta)
	if excited or out == Vector2.ZERO:
		return out
	var ahead: Vector2 = here + out.normalized() * 14.0
	var ahead_depth: float = town.light_depth(ahead)
	if ahead_depth > 0.0:
		if ahead_depth <= float(cfg.dim_px) and brave():
			return out.limit_length(top_speed * float(cfg.dim_slow)) ## it steps into the dim band
		var outward: Vector2 = town.light_outward(ahead)
		var inward: float = -out.dot(outward) ## how much of the move leads in
		if inward > 0.0:
			out += outward * inward ## slide along the edge, never in
			town.light_touch(here + out.normalized() * 10.0)
	return out


## Does it dare the dim band now? Its own temper and the night's mood decide; right after a probe it does not.
func brave() -> bool:
	return _probe_cool <= 0.0 and courage + courage_extra >= float((NightRules.config().courage as Dictionary).enter)
