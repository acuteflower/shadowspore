class_name DropComponent
extends Node
## Rolls an enemy's loot when it dies (host only), from the "loot" block in data/enemies.json.
## Money and XP are paid out straight to the killer (or to every player for "award": "all",
## e.g. bosses); coins and orbs fly to them as a cosmetic. Items drop on the ground for the
## first player to walk over them.

const ITEM_DROP_PATH: String = "res://src/entities/drops/item_drop.tscn" ## loaded when needed: a preload here came out empty in the load cycle World -> Drops -> Player -> World
const MAX_ORBS: int = 4 ## per kind and player
const XP_PER_ORB: float = 6.0
const COIN_COLOR: Color = Color("ffcf9a")
const XP_COLOR: Color = Color("7fe3da")

static var _drop_count: int = 0

@onready var _health: HealthComponent = get_node("../HealthComponent") as HealthComponent


func _ready() -> void:
	if multiplayer.is_server():
		_health.died.connect(_roll)


func _roll() -> void:
	var enemy: Node2D = get_parent() as Node2D
	if enemy.has_meta("burned") and _health.last_attacker == 0: ## the sun took it, nobody killed it: no spoils
		return
	_note_for_board(String(enemy.get("enemy_id")))
	var loot: Dictionary = DataRegistry.get_entry("enemies", String(enemy.get("enemy_id"))).get("loot", {})
	if loot.is_empty():
		return
	var span: Dictionary = loot.get("copper", {})
	var reward: Variant = enemy.get("health_scale") ## deeper (tougher) enemies pay more
	var factor: float = float(reward) if reward != null else 1.0
	var copper: int = roundi(randi_range(int(span.get("min", 0)), int(span.get("max", 0))) * factor)
	var xp: int = roundi(int(loot.get("xp", 0)) * factor)
	var ids: PackedInt32Array = []
	var winners: Array[Player] = _winners(String(loot.get("award", "killer")))
	var chest: Dictionary = loot.get("chest", {}) as Dictionary
	var chests: LootChests = LootChests.of(get_tree())
	if not chest.is_empty() and chests != null: ## a boss: its spoils wait in a chest that comes down out of the light (docs/beutetruhen_konzept.md)
		_to_chest(chests, chest, loot, enemy, winners, copper, xp)
		return
	for player: Player in winners:
		player.progress.award(copper, xp)
		ids.append(player.name.to_int())
	if not ids.is_empty() and copper + xp > 0:
		_reward_fx.rpc(enemy.global_position + Vector2(0, -8), ids, copper, xp)
	_drop_items(loot.get("items", []), enemy.global_position)
	var relics: Array = loot.get("relics", []) as Array ## a boss's own piece: certain the first time, rare after (BossRelics)
	var ledger: BossRelics = BossRelics.of(get_tree())
	if not relics.is_empty() and ledger != null:
		ledger.roll(String(enemy.get("enemy_id")), relics, winners, enemy.global_position)


## The quest board counts the kill for whoever landed the last hit (duck typed: no cycle with the town).
func _note_for_board(species: String) -> void:
	var town_node: Node = get_tree().get_first_node_in_group("town")
	var board: Object = town_node.get("board") as Object if town_node != null else null
	if board == null:
		return
	for player: Player in _winners("killer"):
		board.call("note_kill", player, species)


## "killer": whoever landed the last hit. "all": every living player.
func _winners(award: String) -> Array[Player]:
	var found: Array[Player] = []
	for player: Player in Player.all:
		if award == "all" and player.health.current > 0.0:
			found.append(player)
		elif award != "all" and player.name.to_int() == _health.last_attacker:
			return [player]
	return found


## Host: everything this enemy leaves goes into a chest of `chest.tier` (plus `chest.bonus` draws from data/loot_chests.json's pools).
func _to_chest(chests: LootChests, chest: Dictionary, loot: Dictionary, enemy: Node2D, winners: Array[Player], copper: int, xp: int) -> void:
	var found: Dictionary = {}
	for stack: Dictionary in roll_entries(loot.get("items", []) as Array):
		found[String(stack.id)] = int(found.get(String(stack.id), 0)) + int(stack.count)
	var bonus: Dictionary = {"draws": chest.get("bonus", []) as Array}
	for stack: Dictionary in LootRules.roll(bonus, DataRegistry.table("loot_chests").get("pools", {}) as Dictionary, chests.rng):
		found[String(stack.id)] = int(found.get(String(stack.id), 0)) + int(stack.count)
	var items: Array = []
	for id: String in found:
		items.append({"id": id, "count": int(found[id])})
	var who: Array = []
	for player: Player in winners:
		who.append(player.name.to_int())
	var spot: Vector2 = enemy.global_position
	if enemy.has_method("chest_spot"):
		spot = enemy.call("chest_spot") as Vector2
	var held: Dictionary = {"copper": copper, "xp": xp, "winners": who, "items": items, "relics": loot.get("relics", []) as Array}
	chests.boss_chest(String(enemy.get("enemy_id")), String(chest.get("tier", "legendary")), spot, held, float(chest.get("delay", 2.6)))


func _drop_items(entries: Array, origin: Vector2) -> void:
	spawn_drops(get_tree(), entries, origin)


## Rolls `entries` ([{id, chance, min, max}]) into stacks [{id, count}] without dropping them (a boss's chest holds them).
static func roll_entries(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if randf() <= float(entry.get("chance", 1.0)):
			out.append({"id": String(entry.id), "count": randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))})
	return out


## Host only: rolls `entries` ([{id, chance, min, max}]) and lets the items pop out around `origin`.
## Also used for plants (bushes drop fibers and sticks the same way enemies drop loot).
static func spawn_drops(tree: SceneTree, entries: Array, origin: Vector2) -> void:
	var container: Node = tree.get_first_node_in_group("drops")
	if container == null:
		return
	var rolled: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if randf() <= float(entry.get("chance", 1.0)):
			rolled.append(entry)
	var scene: PackedScene = load(ITEM_DROP_PATH) as PackedScene
	var start: float = randf() * TAU
	for i: int in rolled.size(): ## spread evenly so drops never land on top of each other
		var drop: ItemDrop = scene.instantiate() as ItemDrop
		_drop_count += 1
		drop.name = "Drop%d" % _drop_count
		drop.item_id = String(rolled[i]["id"])
		drop.count = randi_range(int(rolled[i].get("min", 1)), int(rolled[i].get("max", 1)))
		drop.position = origin
		drop.launch = Vector2.from_angle(start + TAU * i / rolled.size()) * randf_range(32.0, 52.0)
		container.add_child(drop)


## Host: a stack the player threw out of the inventory: it flies a good way in `direction` (further than the magnet reaches).
static func spawn_thrown(tree: SceneTree, id: String, count: int, origin: Vector2, direction: Vector2, extra: Dictionary = {}) -> void:
	var container: Node = tree.get_first_node_in_group("drops")
	if container == null:
		return
	var drop: ItemDrop = (load(ITEM_DROP_PATH) as PackedScene).instantiate() as ItemDrop
	_drop_count += 1
	drop.name = "Drop%d" % _drop_count
	drop.item_id = id
	drop.count = count
	drop.refine = int(extra.get(RefineRules.KEY_LEVEL, 0))
	drop.refine_pity = int(extra.get(RefineRules.KEY_PITY, 0))
	for key: String in SpellRules.SOCKET_KEYS:
		if extra.has(key):
			drop.sockets[key] = String(extra[key])
	drop.position = origin
	var way: Vector2 = direction.normalized() if direction.length() > 0.1 else Vector2.DOWN
	drop.launch = way * 70.0
	container.add_child(drop)


## Cosmetic on every peer: coins and XP orbs fly to each winner and show what they got on arrival.
@rpc("authority", "call_local", "reliable")
func _reward_fx(from: Vector2, ids: PackedInt32Array, copper: int, xp: int) -> void:
	var world: Node = get_tree().current_scene
	var coins: Vector3i = Currency.split(copper)
	var groups: Array = [
		[RewardOrb.Kind.GOLD, coins.x, true], [RewardOrb.Kind.SILVER, coins.y, true], [RewardOrb.Kind.COPPER, coins.z, true],
		[RewardOrb.Kind.XP, ceili(xp / XP_PER_ORB), false],
	]
	for id: int in ids:
		var target: Player = _player(id)
		if target == null:
			continue
		var coin_text_sent: bool = false
		var xp_text_sent: bool = false
		for group: Array in groups:
			for i: int in mini(int(group[1]), MAX_ORBS):
				var text: String = ""
				var color: Color = Color.WHITE
				if bool(group[2]) and not coin_text_sent:
					text = "+" + Currency.short_text(copper)
					color = COIN_COLOR
					coin_text_sent = true
				elif not bool(group[2]) and not xp_text_sent:
					text = "+%d XP" % xp
					color = XP_COLOR
					xp_text_sent = true
				RewardOrb.spawn(world, from, target, group[0], text, color)


func _player(id: int) -> Player:
	for player: Player in Player.all:
		if player.name.to_int() == id:
			return player
	return null
