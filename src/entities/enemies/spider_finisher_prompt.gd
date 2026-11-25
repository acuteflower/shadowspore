class_name SpiderFinisherPrompt
extends Interactable
## Finisher V2 (docs/finisher_v2_konzept.md): the E prompt on a `ShadowSpider` whose core is exposed (`finisher_ready_kind` > 0, set by the host).
## E asks the host to start the finisher (`FinisherComponent.request_finisher`); the host checks the same rules as for a lethal sword blow.

var spider: ShadowSpider = null


func prompt() -> String:
	if spider == null or not is_instance_valid(spider):
		return ""
	return spider.finisher_prompt_text()


func reach_distance(from: Vector2) -> float:
	var reach: float = float(FinisherRules.settings().get("exposed_trigger_reach", 34.0))
	return global_position.distance_to(from) - (reach - Interactable.INTERACT_RANGE)


func interact(player: Player) -> void:
	if player == null or player.finisher == null or spider == null or not is_instance_valid(spider):
		return
	player.finisher.request_finisher(spider)


func prompt_position() -> Vector2:
	return Vector2(0, -30)
