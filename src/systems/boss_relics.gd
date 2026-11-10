class_name BossRelics
extends Node
## What a boss leaves behind that belongs to one player (docs/rissfeder.md): a piece of jewellery that is certain the first time this player is there when the boss
## falls and a small chance every time after. A node of the world level (group `boss_relics`), host-authoritative.
## The enemy's loot block (data/enemies.json) lists them under `relics`: [{id, first, chance}] (`first` = chance at the first kill, usually 1.0; `chance` after).
## Every living winner rolls for themselves, and the drop is theirs alone (`ItemDrop.story_owner`, never expires, never merges), so in a group nobody loses
## a first kill to a faster hand. The kills are counted per player (the peer id; in a single-player game that is always 1), and what was dropped but not picked
## up yet is saved with its place, so quitting before picking it up loses nothing.

const ITEM_DROP_PATH: String = "res://src/entities/drops/item_drop.tscn" ## loaded when needed (see DropComponent)
const PREFIX: String = "relic:" ## ItemDrop.story_id of a relic drop: "relic:<item id>"

static var _serial: int = 0

var _kills: Dictionary = {} ## "<peer id>" -> {enemy id: kills this player was there for}
var _owed: Dictionary = {} ## drop name -> {owner, item, at: [x, y]}: relics lying on the ground, not taken yet


static func of(tree: SceneTree) -> BossRelics:
	return tree.get_first_node_in_group("boss_relics") as BossRelics


func _ready() -> void:
	add_to_group("boss_relics")


## How often `owner` (peer id) was present when `enemy_id` died.
func kills_of(owner: int, enemy_id: String) -> int:
	return int((_kills.get(str(owner), {}) as Dictionary).get(enemy_id, 0))


## Relics lying on the ground that `owner` has not taken yet.
func owed_count(owner: int) -> int:
	var count: int = 0
	for entry: Variant in _owed.values():
		if int((entry as Dictionary)["owner"]) == owner:
			count += 1
	return count


## Host: `enemy_id` died at `origin` with `winners` (living players) present. Rolls the `relics` of its loot block for each of them and counts the kill.
## Returns the peer ids that got a relic dropped (the tests read it).
func roll(enemy_id: String, relics: Array, winners: Array, origin: Vector2) -> Array[int]:
	var given: Array[int] = []
	if not multiplayer.is_server():
		return given
	for node: Variant in winners:
		var player: Node = node as Node
		if player == null:
			continue
		var owner: int = player.name.to_int()
		var first: bool = kills_of(owner, enemy_id) == 0
		for entry: Variant in relics:
			var relic: Dictionary = entry as Dictionary
			var chance: float = float(relic.get("first", 1.0)) if first else float(relic.get("chance", 0.0))
			if chance >= 1.0 or randf() < chance:
				if _spawn(owner, String(relic["id"]), origin, Vector2.from_angle(randf() * TAU) * 36.0) != null:
					given.append(owner)
		var table: Dictionary = _kills.get(str(owner), {}) as Dictionary
		table[enemy_id] = int(table.get(enemy_id, 0)) + 1
		_kills[str(owner)] = table
	return given


## Host: the owner took the relic in (called by `ItemDrop`): it no longer has to be kept for the next session.
func collected(drop_name: String) -> void:
	_owed.erase(drop_name)


## Host: forget the kills of `enemy_id` (dev menu, tests): the next kill counts as the first again.
func forget(enemy_id: String) -> void:
	for key: String in _kills:
		(_kills[key] as Dictionary).erase(enemy_id)


func _spawn(owner: int, item: String, at: Vector2, launch: Vector2) -> ItemDrop:
	var container: Node = get_tree().get_first_node_in_group("drops")
	if container == null or Items.definition({"id": item}).is_empty():
		return null
	_serial += 1
	var drop: ItemDrop = (load(ITEM_DROP_PATH) as PackedScene).instantiate() as ItemDrop
	drop.name = "Relic_%d_%d" % [owner, _serial]
	drop.item_id = item
	drop.story_owner = owner
	drop.story_id = PREFIX + item
	drop.position = at
	drop.launch = launch
	container.add_child(drop)
	_owed[String(drop.name)] = {"owner": owner, "item": item, "at": [at.x, at.y]}
	return drop


# ---------------------------------------------------------------- save

func export_state() -> Dictionary:
	return {"kills": _kills.duplicate(true), "owed": _owed.values().duplicate(true)}


func import_state(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for child: Node in get_tree().get_nodes_in_group("drops"):
		for drop: Node in child.get_children():
			if drop is ItemDrop and (drop as ItemDrop).story_id.begins_with(PREFIX):
				drop.queue_free() ## the saved game is the truth
	_kills = (data.get("kills", {}) as Dictionary).duplicate(true)
	_owed.clear()
	for entry: Variant in data.get("owed", []) as Array:
		var owed: Dictionary = entry as Dictionary
		var at: Array = owed.get("at", [0.0, 0.0]) as Array
		_spawn(int(owed["owner"]), String(owed["item"]), Vector2(float(at[0]), float(at[1])), Vector2.ZERO)
