class_name ArenaStory
extends Node
## The story of a boss arena (data/ground.json `arenas[].story` {quest, knight_pillar, knight_offset, hologram}): the quest `mornath` (data/quests.json, started only from
## the developer menu for now) leads her to the plateau; while it runs a dead knight in Valdric's armour sits against the east pillar (`ArenaKnight`), who is not there
## otherwise. E at him starts the search (`MornathInspectScene`: walk up, stoop, her words, the cry from above), which ends with the boss's entrance (the boss is called
## by `WorldLevel.request_arena_boss`; its fight and entrance screen are the old ones). When the boss falls the flag `mornath_defeated` ends the quest, the knight
## dissolves and she says her last words. From then on (and after a wipe in the fight) a glitched hologram of Mornath stands in the middle (`MornathHologram`): E calls
## him again, no quest needed. Quests are local to the player, so every peer decides for its own local player what it sees; the boss itself is the host's.
## A node of the level, group `arena_story`; the knight and the hologram are children of the level (they sort with the world).

var level: WorldLevel
var arena_id: String = ""
var quest_id: String = "mornath"
var knight: ArenaKnight
var hologram: MornathHologram
var origin: Vector2 = Vector2.ZERO
var poly: PackedVector2Array = PackedVector2Array()

var _clock: float = 0.0
var _outro_running: bool = false


func setup(world: WorldLevel, spec: Dictionary, arena_origin: Vector2) -> void:
	level = world
	origin = arena_origin
	arena_id = String(spec.id)
	var story: Dictionary = spec.get("story", {}) as Dictionary
	quest_id = String(story.get("quest", "mornath"))
	for point: Array in spec.poly as Array:
		poly.append(origin + Vector2(float(point[0]), float(point[1])))
	var pillar_at: Array = ((spec.pillars as Array)[int(story.get("knight_pillar", 1))] as Dictionary).pos as Array
	var offset: Array = story.get("knight_offset", [0, 16]) as Array
	knight = ArenaKnight.new()
	knight.name = "ArenaKnight_%s" % arena_id
	knight.story = self
	knight.position = origin + Vector2(float(pillar_at[0]) + float(offset[0]), float(pillar_at[1]) + float(offset[1]))
	world.add_child(knight)
	var holo_at: Array = story.get("hologram", [0, 0]) as Array
	hologram = MornathHologram.new()
	hologram.name = "MornathHologram_%s" % arena_id
	hologram.story = self
	hologram.position = origin + Vector2(float(holo_at[0]), float(holo_at[1]))
	world.add_child(hologram)
	add_to_group("arena_story")


## Where a developer jump puts her: on the floor in front of the pillar with the knight.
func foot_point() -> Vector2:
	return knight.global_position + Vector2(-6, 56)


func _local_player() -> Player:
	for player: Player in Player.all:
		if is_instance_valid(player) and player.is_multiplayer_authority() and player.quests != null:
			return player
	return null


func _physics_process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = 0.3
	var player: Player = _local_player()
	if player == null:
		knight.set_present(false)
		hologram.set_active(false)
		return
	var quests: QuestComponent = player.quests
	var step: String = quests.active_step_id(quest_id)
	knight.set_present(quests.is_active(quest_id))
	knight.inspectable = step == "inspect"
	var boss_here: bool = level.arena_boss_present(arena_id)
	hologram.set_active((quests.is_finished(quest_id) or step == "fight") and not boss_here and not _outro_running)


## E at the knight (local player): the search and the boss's entrance.
func inspect(player: Player) -> void:
	if knight.inspectable:
		level.start_mornath_inspect(player, self)


## E at the hologram (local player): the first time she wonders about it, then the boss is called back.
func hologram_use(player: Player) -> void:
	if player.get_node_or_null("MornathCallScene") != null or level.arena_boss_present(arena_id):
		return
	var scene: MornathCallScene = MornathCallScene.new()
	scene.name = "MornathCallScene"
	player.add_child(scene)
	scene.start(player, self)


## Called on every peer when a boss of the arena dies (`SkyCleaver._on_died`).
func boss_defeated(arena: String) -> void:
	if arena != arena_id:
		return
	var player: Player = _local_player()
	if player == null or player.quests.active_step_id(quest_id) != "fight":
		return
	player.quests.set_flag("mornath_defeated") ## ends the quest: the hologram comes later, after the outro
	_outro(player)


func _outro(player: Player) -> void:
	_outro_running = true
	await get_tree().create_timer(2.2, true, false, true).timeout
	if is_instance_valid(knight):
		knight.dissolve()
	await get_tree().create_timer(3.4, true, false, true).timeout
	if is_instance_valid(player) and player.health.current > 0.0 and Geometry2D.is_point_in_polygon(player.global_position, poly):
		for child: Node in player.get_children():
			var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
			if box != null:
				box.start("mornath_end")
				await box.finished
				break
	_outro_running = false
