class_name FireCircle
extends RefCounted
## The evening circle at the hut's fire (docs/town_ausbau.md C15): somebody who sits at the fire while a resident of the town is near it gets warm after a few quiet seconds
## (a little healing over a few seconds, then a pause). The circle breaks up while the town's light is in alarm. Host-side rules only; the look is `RestComponent.warm_fx`.

const RADIUS: float = 96.0 ## px: how close a resident has to be to make company
const SIT_SECONDS: float = 8.0 ## quiet seconds before the warmth comes
const COOLDOWN: float = 90.0
const HEAL: float = 6.0
const HEAL_SECONDS: float = 6.0

static var _next: Dictionary = {} ## peer id -> msec before which no new warmth comes


## Residents who are up and near `at` (they sit or stand at the fire).
static func company(town: TownManager, at: Vector2) -> int:
	var n: int = 0
	for sid: String in town.settler_ids():
		var settler: Settler = town.settler_node(sid)
		if settler != null and settler.visible and settler.global_position.distance_to(at) <= RADIUS:
			n += 1
	return n


static func ready(player: Player) -> bool:
	return Time.get_ticks_msec() >= int(_next.get(player.get_multiplayer_authority(), 0))


## Host: the warmth for one sitter (if the circle is whole and the pause is over).
static func tick(town: TownManager, player: Player, seat_at: Vector2, seated: float) -> bool:
	if seated < SIT_SECONDS or town == null or not town.founded or town.alert_on or not ready(player) or company(town, seat_at) == 0:
		return false
	_next[player.get_multiplayer_authority()] = Time.get_ticks_msec() + int(COOLDOWN * 1000.0)
	player.health.regen(HEAL, HEAL_SECONDS)
	var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent
	if rest != null:
		rest.warm_fx.rpc()
	return true
