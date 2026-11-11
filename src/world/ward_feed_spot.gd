class_name WardFeedSpot
extends Interactable
## E at one of the weak ward stones while the lake witch's quest asks for it (docs/seehexe_konzept.md 8, step "NÄHRE DIE BANNSTEINE"): Ellie stoops, lays a
## Seeglimmer into the stone's crystal head and the host lights it (`WardRing.request_feed`). Says nothing at any other time.

const QUEST_STEP: String = "lw_feed"

var ring: WardRing
var index: int = 0


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


func prompt() -> String:
	var player: Player = _local_player()
	if ring == null or player == null or player.quests == null or player.story_lock or InputManager.ui_blocking:
		return ""
	if ring.awake or ring.fed.has(index) or not player.quests.has_active_step(QUEST_STEP):
		return ""
	if not player.inventory.has_item("lake_glimmer"):
		return "SEEGLIMMER FEHLT"
	if ring.fed.size() >= 2 and ring.ambush != WardRing.AMBUSH_DONE:
		return "ERST DIE SCHATTEN"
	return "NÄHREN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 14.0


func prompt_position() -> Vector2:
	return Vector2(0, -74)


func interact(player: Player) -> void:
	if prompt() != "NÄHREN":
		return
	var toward: Vector2 = global_position - player.global_position
	var at: int = index
	var r: WardRing = ring
	player.begin_pick(toward.normalized() if toward.length() > 1.0 else player.facing, func() -> void: r.request_feed(at))
