class_name FishNetSpot
extends Interactable
## The place under a hooked fish where a FRIEND can press E and hold the landing net (docs/fishing.md). It follows the
## fish, shows "KESCHERN" only to other players, only while the fish is near the bank.

var _c: FishingComponent
var _p: Player


func bind(component: FishingComponent, player: Player) -> void:
	_c = component
	_p = player
	top_level = true


func _process(_delta: float) -> void:
	global_position = _c.bobber


func prompt() -> String:
	if _c.state != FishingComponent.S.DRILL or _c.netted or _p.is_multiplayer_authority():
		return ""
	if _c.dist > float((FishingRules.settings()["net"] as Dictionary)["range"]):
		return ""
	return "KESCHERN"


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, from.distance_to(global_position) - 22.0)


func interact(_player: Player) -> void:
	_c.request_net()
