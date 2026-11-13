class_name TrialLevel
extends "res://src/world/test_level.gd" ## by path: naming TestLevel here resolves too early in the Player -> HUD -> pause menu load chain
## The trials' test world (`--trials`, or Pause menu -> ENTWICKLER -> RÄTSELWELT): a flat, empty meadow with every trial of the Wächterin in it
## (data/puzzles.json `trial_world`: the wisp trail, the crow's hoard, the raven trade and the three root weaves). Nothing grows here, nothing is saved
## (group `sandbox`: `SaveGame` refuses), the loot chests and the trials run as in the world. The host's player gets what the trials ask for: berries and
## seeds for the crow, a shiny pawn for the raven, a hoe for digging.

const WORLD_RECT: Rect2i = Rect2i(-66, -46, 132, 92) ## in tiles
const KIT: Array = [["dusk_berry", 12], ["seed_fluff", 6], ["silver_chain", 1], ["iron_ingot", 2], ["hoe_basic", 1]]

var puzzles: Puzzles


func _ready() -> void:
	add_to_group("sandbox")
	var chests: LootChests = LootChests.new()
	chests.name = "LootChests"
	add_child(chests)
	puzzles = Puzzles.new()
	puzzles.name = "Puzzles"
	puzzles.source = "trial_world"
	add_child(puzzles)
	_add_walls()
	super._ready()


## Plain grass and now and then a tuft: nothing to distract from the trials.
func _fill_ground() -> void:
	var tiles: Dictionary = DataRegistry.table("grass_tiles")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var plain: Array = tiles.get("plain", []) as Array
	var tuft: Array = tiles.get("tuft", plain) as Array
	for y: int in range(WORLD_RECT.position.y - 12, WORLD_RECT.end.y + 12):
		for x: int in range(WORLD_RECT.position.x - 20, WORLD_RECT.end.x + 20):
			var options: Array = tuft if rng.randf() < 0.04 else plain
			var atlas: Array = options[rng.randi() % options.size()] as Array
			_ground.set_cell(Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))


func _add_walls() -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Edge"
	var r: Rect2 = Rect2(Vector2(WORLD_RECT.position) * 16.0, Vector2(WORLD_RECT.size) * 16.0)
	for side: Rect2 in [Rect2(r.position.x - 16, r.position.y - 16, r.size.x + 32, 16), Rect2(r.position.x - 16, r.end.y, r.size.x + 32, 16),
			Rect2(r.position.x - 16, r.position.y, 16, r.size.y), Rect2(r.end.x, r.position.y, 16, r.size.y)]:
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = side.size
		shape.shape = rect
		shape.position = side.get_center()
		body.add_child(shape)
		var look: ColorRect = ColorRect.new()
		look.position = side.position
		look.size = side.size
		look.color = Color(0.15, 0.12, 0.18, 1)
		look.z_index = -9
		add_child(look)
	add_child(body)


func _clamp_spawn(pos: Vector2) -> Vector2:
	var r: Rect2 = Rect2(Vector2(WORLD_RECT.position) * 16.0, Vector2(WORLD_RECT.size) * 16.0).grow(-24.0)
	return pos.clamp(r.position, r.end)


func _spawn_player(id: int) -> void:
	super._spawn_player(id)
	var player: Player = _players.get_node_or_null(str(id)) as Player
	if player != null:
		_give_kit.call_deferred(player)


func _give_kit(player: Player) -> void:
	if not is_instance_valid(player) or player.inventory == null:
		return
	for k: Array in KIT:
		player.inventory.give(String(k[0]), int(k[1]))
