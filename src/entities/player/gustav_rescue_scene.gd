class_name GustavRescueScene
extends Node
## Quest `gustav_rescue` at the wagon, two modes (a child of the player, solo / host only like the other story scenes):
## "fight" (step `kill_wagon_spider`, event `wagon:fight`): one normal `shadow_spider` (nothing rigged) tears at the wagon; the stranger inside shouts encouragement every 4-6 s
##   (barks `wagon_cheer_a..c`, `wagon_hurt` when it hits her). A lost spider (she died and came back, or it wandered off) is replaced. Its death sets `wagon_spider_dead`.
## "meet" (step `gustav_meet`, event `wagon:meet`): she walks up to him, the dialogues `gustav_rescue_a` (flag `knows_gustav`) and `gustav_rescue_b` (flag `gustav_packed`).

const CHEERS: Array[String] = ["wagon_cheer_a", "wagon_cheer_b", "wagon_cheer_c"]
const SPIDER_AT: Vector2 = Vector2(78.0, 38.0) ## from the wagon's feet
const LOST_DISTANCE: float = 520.0

var _player: Player
var _world: WorldLevel
var _wagon: GustavWagon
var _spider: ShadowSpider
var _dead: bool = false
var _cheer_clock: float = 3.0
var _cheers: int = 0
var _last_health: float = -1.0


func start(player: Player, world: WorldLevel, wagon: GustavWagon, mode: String) -> void:
	_player = player
	_world = world
	_wagon = wagon
	if mode == "meet":
		_meet()
	else:
		_fight()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# ---------- the fight ----------

func _fight() -> void:
	_last_health = _player.health.current
	_player.health.changed.connect(_on_health)
	while not _dead and is_instance_valid(_player) and is_instance_valid(_wagon):
		if _spider == null or not is_instance_valid(_spider) or _spider.is_queued_for_deletion():
			await _rise()
		elif _spider.global_position.distance_to(_wagon.global_position) > LOST_DISTANCE:
			_spider.queue_free() ## it ran off: a new one comes out at the wagon
			_spider = null
		_cheer(0.5)
		await _wait(0.5)
	if is_instance_valid(_player) and _player.quests != null:
		_player.quests.set_flag("wagon_spider_dead")
	queue_free()


func _rise() -> void:
	var at: Vector2 = _wagon.global_position + SPIDER_AT
	_spider = _world.spawn_story_spider("shadow_spider", at, (_wagon.global_position - at).angle())
	if _spider == null:
		await _wait(1.0)
		return
	var health: HealthComponent = _spider.get_node("HealthComponent") as HealthComponent
	health.died.connect(func() -> void: _dead = true)
	_cheer_clock = 2.5


func _cheer(delta: float) -> void:
	_cheer_clock -= delta
	if _cheer_clock > 0.0 or _spider == null or not is_instance_valid(_spider):
		return
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box == null or box.is_speaking():
		return
	_cheer_clock = randf_range(4.0, 6.0)
	box.play(CHEERS[_cheers % CHEERS.size()])
	_cheers += 1


func _on_health(current: float, _maximum: float) -> void:
	if current < _last_health - 0.5 and _spider != null and is_instance_valid(_spider):
		var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
		if box != null and not box.is_speaking():
			box.play("wagon_hurt")
	_last_health = current


# ---------- the first talk ----------

func _meet() -> void:
	var gustav: StoryGustav = _wagon.gustav
	if gustav == null:
		_wagon.set_open(true) ## a loaded game: he already stands beside the wagon
		gustav = _wagon.gustav
	_player.story_lock = true
	InputManager.ui_blocking = true
	var stand: Vector2 = gustav.global_position + Vector2(-30.0, 8.0)
	_player.auto_walk = stand
	_player.auto_walk_factor = 0.55
	var waited: float = 0.0
	while waited < 5.0 and _player.global_position.distance_to(stand) > 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if _player.global_position.distance_to(stand) > 14.0:
		_player.global_position = stand
	_player.auto_walk = Vector2.INF
	_player.auto_walk_factor = -1.0
	_player.facing = (gustav.global_position - _player.global_position).normalized()
	gustav.play("idle", _player.global_position - gustav.global_position)
	InputManager.ui_blocking = false
	await _wait(0.4)
	await _talk("gustav_rescue_a")
	_player.quests.set_flag("knows_gustav")
	gustav.play("work", Vector2(1.0, 0.5)) ## he gathers his tools
	await _wait(0.3)
	await _talk("gustav_rescue_b")
	gustav.play("idle", _player.global_position - gustav.global_position)
	_player.story_lock = false
	_player.quests.set_flag("gustav_packed")
	queue_free()


func _talk(id: String) -> void:
	for child: Node in _player.get_children():
		var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
		if box != null:
			box.start(id)
			await box.finished
			return
