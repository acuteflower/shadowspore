class_name CabinSpiderScene
extends Node
## Day 2, in the lumberjack's cabin (quest `lumberjack`, step "defeat the shadow spider", event `cabin:fight`, started when she has stepped through the cabin's door): one shadow spider
## tears out of the floor of the small room (`WorldLevel.spawn_story_spider`, the normal `shadow_spider`: a real fight, nothing rigged; `WorldLevel.navigation_floor` counts the room as
## floor), after a moment Ellie reacts in a short dialogue (`cabin_spider`), then she has to beat it. Its death sets the flag `spider_dead`. If the spider is lost (she died and came
## back) a new one rises when she is inside again; a saved game that stopped in the fight starts here again (`resume_story`). A child of the player; solo / host only for now.

const SPAWN_AT: Vector2 = Vector2(112.0, 132.0) ## in the room, a free spot of the floor between the cot and the table

var _player: Player
var _world: WorldLevel
var _cabin: Hut
var _interior: Interior
var _spider: ShadowSpider
var _talked: bool = false
var _dead: bool = false


func start(player: Player, world: WorldLevel, hut: Hut, talked: bool) -> void:
	_player = player
	_world = world
	_cabin = hut
	_interior = (world.get_node("Interiors") as Interiors).interior("cabin")
	_talked = talked
	_run()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _inside() -> bool:
	return is_instance_valid(_player) and (_world.get_node("Interiors") as Interiors).interior_at(_player.global_position) == _interior


func _run() -> void:
	while not _dead and is_instance_valid(_player):
		if _spider == null or not is_instance_valid(_spider) or _spider.is_queued_for_deletion():
			if _inside():
				await _rise()
		await _wait(0.5)
	if is_instance_valid(_player) and _player.quests != null:
		_player.quests.set_flag("spider_dead")
	queue_free()


## The spider emerges, Ellie reacts (the first time), and the fight is on.
func _rise() -> void:
	var at: Vector2 = _interior.room_to_global(SPAWN_AT)
	_spider = _world.spawn_story_spider("shadow_spider", at, (_player.global_position - at).angle())
	if _spider == null:
		await _wait(1.0)
		return
	var health: HealthComponent = _spider.get_node("HealthComponent") as HealthComponent
	health.died.connect(func() -> void: _dead = true)
	if not _talked:
		_talked = true
		await _wait(1.3) ## the rift opens, the claws come through
		var runner: BubbleRunner = BubbleRunner.find(_player)
		if runner != null:
			await runner.play("cabin_spider", _player)
