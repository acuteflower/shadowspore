class_name LootChests
extends Node2D
## The loot chests of the wild (docs/beutetruhen_konzept.md), host-authoritative and shared by everybody. A chest is placed with
## `place(id, tier, pos, flip)` (from `data/loot_chests.json` `placed`, still empty: no chest lies in the world yet; later puzzles and places
## call it too). E at a chest -> `LootChest.interact` (a hold for rare and legendary ones) -> `request_open` -> the host checks reach, life and
## state, tells every peer to play the opening (`_rpc_opened`) and pays in time with it: copper and XP to every living player within
## `share_radius`, the items (`LootRules.roll`) spring out of the chest's mouth one after the other, the best last.
## A joining peer gets the dev chests and the opened ones (`_rpc_snapshot`); the save file keeps the opened ids (`"chests"`, dev chests never).
## Bosses: an enemy whose loot block has `chest` leaves no scattered loot but a Glutreliquiar holding exactly its spoils (`boss_chest`, called by
## `DropComponent._roll`): it comes down in a pillar of light a moment after the kill, the copper, XP and relics go to the same winners when it is
## opened. Such a chest is kept in the save until it is opened; opened boss and test chests fade away after `fade_after` seconds.
## Dev: `request_dev(tier, pos)` puts a test chest down (pause menu ENTWICKLER).

const DEV_PREFIX: String = "dev_"
const DROP_SCENE: String = "res://src/entities/drops/item_drop.tscn" ## loaded when needed (the load cycle World -> Drops -> Player -> World)

var _settings: Dictionary = {}
var _tiers: Dictionary = {}
var _pools: Dictionary = {}
var _chests: Dictionary = {} ## id -> LootChest
var _opened: Dictionary = {} ## id -> true
var _spawned: Dictionary = {} ## id -> [tier, pos, flip]: chests placed while playing (test chests, boss chests): every peer has them
var _payload: Dictionary = {} ## host: id -> what a boss chest holds {enemy, copper, xp, winners: [peer ids], items: [{id, count}], relics: [...]}
var _dev_count: int = 0
var _serial: int = 0
var _drop_count: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new() ## host: the loot dice (tests may seed it)


static func of(tree: SceneTree) -> LootChests:
	return tree.get_first_node_in_group("loot_chests") as LootChests


func _ready() -> void:
	add_to_group("loot_chests")
	y_sort_enabled = true
	rng.randomize()
	var table: Dictionary = DataRegistry.table("loot_chests")
	_settings = table.get("settings", {}) as Dictionary
	_tiers = table.get("tiers", {}) as Dictionary
	_pools = table.get("pools", {}) as Dictionary
	for spec: Dictionary in table.get("placed", []) as Array: ## {id, tier, tile [x, y], flip}
		var tile: Array = spec.tile as Array
		place(String(spec.id), String(spec.tier), Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8), bool(spec.get("flip", false)))
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void: _rpc_snapshot.rpc_id(peer, _spawned_list(), PackedStringArray(_opened.keys())))


func tier(name: String) -> Dictionary:
	return _tiers.get(name, {}) as Dictionary


func setting(key: String, fallback: float) -> float:
	return float(_settings.get(key, fallback))


func is_open(id: String) -> bool:
	return _opened.has(id)


func chest(id: String) -> LootChest:
	return _chests.get(id) as LootChest


func count() -> int:
	return _chests.size()


## Every peer: a chest of `tier` stands at `pos` (world px of its feet) from now on. Ids must be unique and the same on every peer.
func place(id: String, tier_name: String, pos: Vector2, flip: bool = false) -> LootChest:
	if _chests.has(id) or not _tiers.has(tier_name):
		return _chests.get(id) as LootChest
	var node: LootChest = LootChest.new()
	node.name = "Chest_" + id
	node.id = id
	node.tier = tier_name
	node.flip = flip
	node.position = pos
	add_child(node)
	_chests[id] = node
	if _opened.has(id):
		node.set_open_instant()
	return node


# ---------------------------------------------------------------- opening

## Local player: the chest's hold is done and her hand is on the lid.
func request_open(id: String) -> void:
	if multiplayer.is_server():
		_host_open(id, multiplayer.get_unique_id())
	else:
		_rpc_request.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(id: String) -> void:
	if multiplayer.is_server():
		_host_open(id, multiplayer.get_remote_sender_id())


func _host_open(id: String, peer: int) -> void:
	var node: LootChest = _chests.get(id) as LootChest
	if node == null or _opened.has(id):
		return
	var who: Player = _player(peer)
	if who == null or who.health.current <= 0.0:
		return
	if node.reach_distance(who.global_position) > setting("reach", 34.0):
		return
	var spec: Dictionary = tier(node.tier)
	_rpc_opened.rpc(id, peer)
	var near: Array[Player] = []
	var items: Array[Dictionary] = []
	var burst: float = float(spec.get("burst", 0.5))
	if _payload.has(id): ## a boss's chest: its own spoils for the ones who fought it
		var held: Dictionary = _payload[id] as Dictionary
		_payload.erase(id)
		for pid: Variant in held.get("winners", []) as Array:
			var p: Player = _player(int(pid))
			if p != null:
				near.append(p)
		for entry: Variant in held.get("items", []) as Array:
			items.append(entry as Dictionary)
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return LootRules.rarity_rank(String(a.id)) < LootRules.rarity_rank(String(b.id)))
		var paid: Dictionary = spec.duplicate()
		paid["copper"] = [int(held.get("copper", 0)), int(held.get("copper", 0))]
		paid["xp"] = int(held.get("xp", 0))
		get_tree().create_timer(burst).timeout.connect(func() -> void: _host_pay(id, paid, near, true))
		var relics: Array = held.get("relics", []) as Array
		var enemy: String = String(held.get("enemy", ""))
		if not relics.is_empty():
			get_tree().create_timer(burst + 0.2 + float(spec.get("stagger", 0.2)) * (items.size() + 1)).timeout.connect(func() -> void: _host_relics(id, enemy, relics, near))
	else:
		for player: Player in Player.all:
			if player.health.current > 0.0 and player.global_position.distance_to(node.global_position) <= setting("share_radius", 200.0):
				near.append(player)
		items = LootRules.roll(spec, _pools, rng, near.size())
		get_tree().create_timer(burst).timeout.connect(func() -> void: _host_pay(id, spec, near))
	if _spawned.has(id):
		get_tree().create_timer(setting("fade_after", 45.0)).timeout.connect(func() -> void: _rpc_remove.rpc(id))
	var stagger: float = float(spec.get("stagger", 0.15))
	for i: int in items.size():
		var stack: Dictionary = items[i]
		var last: bool = i == items.size() - 1
		get_tree().create_timer(burst + 0.06 + stagger * i).timeout.connect(func() -> void: _spring(id, stack, i, items.size(), last, spec))


## Host: copper and XP for everyone who was near when it opened (and is still alive), shown as coins and orbs.
func _host_pay(id: String, spec: Dictionary, near: Array[Player], dead_too: bool = false) -> void:
	var node: LootChest = _chests.get(id) as LootChest
	if node == null:
		return
	var span: Array = spec.get("copper", [0, 0]) as Array
	var copper: int = rng.randi_range(int(span[0]), int(span[1]))
	var xp: int = int(spec.get("xp", 0))
	var ids: PackedInt32Array = []
	for player: Player in near:
		if is_instance_valid(player) and (dead_too or player.health.current > 0.0):
			player.progress.award(copper, xp)
			ids.append(player.name.to_int())
	if not ids.is_empty():
		_rpc_reward.rpc(node.global_position + node.mouth(), ids, copper, xp)


## Host: one stack springs out of the chest's mouth in a fan towards the front; the last (best) one highest and straight ahead.
func _spring(id: String, stack: Dictionary, i: int, total: int, last: bool, spec: Dictionary) -> void:
	var node: LootChest = _chests.get(id) as LootChest
	var container: Node = get_tree().get_first_node_in_group("drops")
	if node == null or container == null:
		return
	var mouth: Vector2 = node.mouth()
	var drop: ItemDrop = (load(DROP_SCENE) as PackedScene).instantiate() as ItemDrop
	_drop_count += 1
	drop.name = "ChestDrop_%s_%d" % [id, _drop_count]
	drop.item_id = String(stack.id)
	drop.count = int(stack.count)
	drop.position = node.global_position + Vector2(mouth.x, 2.0)
	var fan: float = PI * 0.5 if last or total <= 1 else lerpf(PI * 0.12, PI * 0.88, float(i) / float(maxi(total - 2, 1)))
	fan += rng.randf_range(-0.12, 0.12)
	drop.launch = Vector2.from_angle(fan) * (rng.randf_range(28.0, 46.0) if not last else 22.0)
	drop.rise = -mouth.y
	drop.pop = float(spec.get("pop", 60.0)) * (1.35 if last else rng.randf_range(0.8, 1.1))
	drop.life = setting("drop_life", 300.0)
	container.add_child(drop)
	_rpc_sprang.rpc(id, LootRules.rarity_rank(String(stack.id)))


## Host: a boss's relics (BossRelics: certain at a player's first kill, rare after) come out last, for the winners still here.
func _host_relics(id: String, enemy: String, relics: Array, near: Array[Player]) -> void:
	var node: LootChest = _chests.get(id) as LootChest
	var ledger: BossRelics = BossRelics.of(get_tree())
	if node == null or ledger == null:
		return
	var here: Array = []
	for player: Player in near:
		if is_instance_valid(player):
			here.append(player)
	if not ledger.roll(enemy, relics, here, node.global_position + Vector2(node.mouth().x, 6.0)).is_empty():
		_rpc_sprang.rpc(id, 4)


@rpc("authority", "call_local", "reliable")
func _rpc_opened(id: String, peer: int) -> void:
	_opened[id] = true
	var node: LootChest = _chests.get(id) as LootChest
	if node != null:
		node.play_open(peer == multiplayer.get_unique_id())


@rpc("authority", "call_local", "reliable")
func _rpc_sprang(id: String, rank: int) -> void:
	var node: LootChest = _chests.get(id) as LootChest
	if node != null:
		node.spring_fx(rank)


## Cosmetic on every peer: coins and XP orbs fly from the chest to each player who shared the find.
@rpc("authority", "call_local", "reliable")
func _rpc_reward(from: Vector2, ids: PackedInt32Array, copper: int, xp: int) -> void:
	var world: Node = get_tree().current_scene
	var coins: Vector3i = Currency.split(copper)
	var groups: Array = [[RewardOrb.Kind.GOLD, coins.x], [RewardOrb.Kind.SILVER, coins.y], [RewardOrb.Kind.COPPER, coins.z], [RewardOrb.Kind.XP, ceili(xp / 8.0)]]
	for pid: int in ids:
		var target: Player = _player(pid)
		if target == null:
			continue
		var coin_said: bool = false
		var xp_said: bool = false
		for group: Array in groups:
			var xp_kind: bool = group[0] == RewardOrb.Kind.XP
			for k: int in mini(int(group[1]), 5):
				var text: String = ""
				var color: Color = Color.WHITE
				if not xp_kind and not coin_said:
					text = "+" + Currency.short_text(copper)
					color = DropComponent.COIN_COLOR
					coin_said = true
				elif xp_kind and not xp_said:
					text = "+%d XP" % xp
					color = DropComponent.XP_COLOR
					xp_said = true
				RewardOrb.spawn(world, from, target, group[0], text, color)


# ---------------------------------------------------------------- boss chests and dev chests

## Host: `enemy` died at `pos`: a chest of `tier_name` holding `held` ({copper, xp, winners, items, relics}) comes down there after `delay` seconds.
func boss_chest(enemy: String, tier_name: String, pos: Vector2, held: Dictionary, delay: float = 2.6) -> String:
	if not multiplayer.is_server() or not _tiers.has(tier_name):
		return ""
	_serial += 1
	var id: String = "boss_%s_%d_%d" % [enemy, int(Time.get_unix_time_from_system()), _serial]
	var stored: Dictionary = held.duplicate(true)
	stored["enemy"] = enemy
	_payload[id] = stored
	var spot: Vector2 = pos.round()
	if delay <= 0.0:
		_rpc_place.rpc(id, tier_name, spot, false, true)
	else:
		get_tree().create_timer(delay).timeout.connect(func() -> void: _rpc_place.rpc(id, tier_name, spot, false, true))
	return id


## Any peer: a test chest of `tier` at `pos` (asks the host, which gives it an id and tells everyone); `arrive` = it falls out of the light.
func request_dev(tier_name: String, pos: Vector2, arrive: bool = false) -> void:
	if multiplayer.is_server():
		_host_dev(tier_name, pos, arrive)
	else:
		_rpc_dev.rpc_id(1, tier_name, pos, arrive)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_dev(tier_name: String, pos: Vector2, arrive: bool) -> void:
	if multiplayer.is_server():
		_host_dev(tier_name, pos, arrive)


func _host_dev(tier_name: String, pos: Vector2, arrive: bool) -> void:
	if not _tiers.has(tier_name):
		return
	_dev_count += 1
	_rpc_place.rpc("%s%d" % [DEV_PREFIX, _dev_count], tier_name, pos.round(), _dev_count % 2 == 0, arrive)


@rpc("authority", "call_local", "reliable")
func _rpc_place(id: String, tier_name: String, pos: Vector2, flip: bool, arrive: bool) -> void:
	_spawned[id] = [tier_name, pos, flip]
	if arrive and not _chests.has(id):
		var node: LootChest = LootChest.new()
		node.name = "Chest_" + id
		node.id = id
		node.tier = tier_name
		node.flip = flip
		node.arrive = true
		node.position = pos
		add_child(node)
		_chests[id] = node
		return
	place(id, tier_name, pos, flip)


## Every peer: an opened boss or test chest fades and is gone.
@rpc("authority", "call_local", "reliable")
func _rpc_remove(id: String) -> void:
	_spawned.erase(id)
	_opened.erase(id)
	var node: LootChest = _chests.get(id) as LootChest
	_chests.erase(id)
	if node != null:
		node.vanish()


func _spawned_list() -> Array:
	var out: Array = []
	for id: String in _spawned:
		out.append([id] + (_spawned[id] as Array))
	return out


@rpc("authority", "reliable")
func _rpc_snapshot(spawned: Array, opened: PackedStringArray) -> void:
	for id: String in opened:
		_opened[id] = true
	for entry: Array in spawned:
		_spawned[String(entry[0])] = [entry[1], entry[2], entry[3]]
		place(String(entry[0]), String(entry[1]), entry[2] as Vector2, bool(entry[3]))
	for id: String in opened:
		var node: LootChest = _chests.get(id) as LootChest
		if node != null:
			node.set_open_instant()


# ---------------------------------------------------------------- save file

func export_state() -> Dictionary:
	var ids: Array = []
	for id: String in _opened:
		if not _spawned.has(id):
			ids.append(id)
	var bosses: Dictionary = {} ## boss chests not opened yet: where they stand and what they hold
	for id: String in _payload:
		if _spawned.has(id) and not _opened.has(id):
			var at: Vector2 = (_spawned[id] as Array)[1] as Vector2
			bosses[id] = {"tier": String((_spawned[id] as Array)[0]), "at": [at.x, at.y], "load": _payload[id]}
	return {"opened": ids, "boss": bosses}


func import_state(data: Dictionary) -> void:
	var ids: PackedStringArray = PackedStringArray()
	for id: Variant in data.get("opened", []) as Array:
		ids.append(String(id))
		_opened[String(id)] = true
		var node: LootChest = _chests.get(String(id)) as LootChest
		if node != null:
			node.set_open_instant()
	var bosses: Dictionary = data.get("boss", {}) as Dictionary
	for key: Variant in bosses:
		var entry: Dictionary = bosses[key] as Dictionary
		var at: Array = entry.get("at", [0, 0]) as Array
		var bid: String = String(key)
		var where: Vector2 = Vector2(float(at[0]), float(at[1]))
		_payload[bid] = entry.get("load", {}) as Dictionary
		_spawned[bid] = [String(entry.get("tier", "legendary")), where, false]
		place(bid, String(entry.get("tier", "legendary")), where)
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(_spawned_list(), ids)


func _player(peer: int) -> Player:
	for player: Player in Player.all:
		if player.name == str(peer):
			return player
	return null
