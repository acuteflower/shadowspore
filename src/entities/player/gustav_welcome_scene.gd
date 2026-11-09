class_name GustavWelcomeScene
extends Node
## Quest `gustav_rescue`, step `welcome` (event `welcome:gustav`, started when Gustav has reached the light; a save that stopped there starts it again): Gustav walks up to Valdric
## (the way a settler would, `TownManager.walk_route`), and once she is near the two the dialogue `gustav_welcome` plays: Valdric greets him, Gustav hands over his sickle (the dialogue's
## `give`, so it can only happen once) and the flag `gustav_joined` ends the step. Then `TownManager.add_story_resident("gustav", true)`: the `Settler` takes over from the figure
## (`takes_over` "story_gustav") and walks to the camp by the fire. A child of the player; solo / host only.

const SPEED: float = 70.0
const NEAR_HER: float = 220.0

var _player: Player
var _world: WorldLevel
var _town: TownManager
var _gustav: StoryGustav
var _route: PackedVector2Array = PackedVector2Array()
var _index: int = 0
var _talking: bool = false
var _spot: Vector2 = Vector2.INF


func start(player: Player, world: WorldLevel, town: TownManager) -> void:
	_player = player
	_world = world
	_town = town
	for node: Node in get_tree().get_nodes_in_group("story_gustav"):
		_gustav = node as StoryGustav
	if _gustav == null: ## a loaded game: he is simply at the light
		_gustav = StoryGustav.new()
		_gustav.name = "StoryGustav"
		world.add_child(_gustav)
		_gustav.global_position = town.door_of(0) + Vector2(30.0, 40.0)
	_spot = _valdric_spot()
	_route = town.walk_route(_gustav.global_position, _spot)
	_index = 1


func _valdric_spot() -> Vector2:
	for node: Node in get_tree().get_nodes_in_group("quest_actors"):
		if node == _gustav or not node.has_method("actor_position"):
			continue
		var at: Vector2 = node.call("actor_position", "knight") as Vector2
		if at != Vector2.INF:
			return at + Vector2(-26.0, 12.0)
	return _town.door_of(0) + Vector2(-26.0, 30.0)


func _physics_process(delta: float) -> void:
	if _talking or not is_instance_valid(_player) or not is_instance_valid(_gustav):
		return
	var here: Vector2 = _gustav.global_position
	var step: Vector2 = _spot - here
	if _index < _route.size():
		step = _route[_index] - here
		if step.length() < 3.0:
			_index += 1
			return
	elif step.length() < 6.0:
		_arrived()
		return
	var move: float = minf(SPEED * delta, step.length())
	_gustav.global_position = here + step.normalized() * move
	_gustav.play("walk", step)


func _arrived() -> void:
	_gustav.play("idle", Vector2(1.0, 0.3))
	if _player.global_position.distance_to(_gustav.global_position) > NEAR_HER or _player.story_lock or InputManager.ui_blocking:
		return ## he waits for her
	_talking = true
	_talk()


func _talk() -> void:
	await _world.play_story_dialogue(_player, "gustav_welcome")
	_town.add_story_resident("gustav", true)
	queue_free()
