class_name WitchArena
extends Node
## The Schieferkessel am Rabenbaum as a place of the fight (docs/enemies/boss_mora.md, step 1/2): a child of `WorldLevel` (group `witch_arena`), on
## every peer; only the host decides, everybody builds the same gates.
##   CALM     nothing happens, and nothing at all until the hollow is OPENED: the quest `spiegelhexe` reaches its step "SUCHE MORA AM RABENBAUM"
##            (Esma has asked; `request_open`, saved). Then, when a living player comes within `wake_range` of the tree:
##   PRELUDE  three shadow spiders (her rot) tear out of the roots and the ways out are sealed: thorn hedges grow in every gate (`gates` of the baked
##            hollow; solid while sealed) and a climb over the slate is refused (`blocks_climb`, asked by `WallClimb`). The last spider dies: Ellie's
##            bark (`morwenna_threshold`), then
##   BOSS     Morwenna falls out of the crown (`MirrorWitch`, spawned through the level's enemy spawner).
##   FREE     she is released (`on_released`): the gates wither, the tree stays liberated (saved: `export_state`), and her hologram stands in front
##            of the tree (`MorwennaHologram`, also on the map): E calls her back for another fight (`request_rematch`, no spiders), the tree darkens
##            while she fights and is freed again when she falls.
## Nobody left alive within `leash` for `reset_seconds` (prelude or fight): the spiders / she go, the gates open, all is CALM again.
## Data: data/witch_arena.json + data/witch_arena_baked.json (`py -3 tools/bake_witch_arena.py`).

enum Stage { CALM, PRELUDE, BOSS, FREE }

const SCENE_PATH: String = "res://src/entities/enemies/witch_boss/mirror_witch.tscn"
const THORNS: String = "res://assets/props/thorn_hedge.png"
const THORNS_GLOW: String = "res://assets/props/thorn_hedge_glow.png"
const THORN_FRAME: Vector2 = Vector2(40, 34)
const TICK: float = 0.25
const THRESHOLD_PAUSE: float = 3.6 ## seconds from the last spider's death to her fall (Ellie's two lines)
const HOLOGRAM_AT: Vector2 = Vector2(0, 112) ## from the tree: on the open floor in front of it
const THORN_GLOW_ALPHA: float = 0.55

var world: WorldLevel
var boss: MirrorWitch
var stage: Stage = Stage.CALM
var released: bool = false ## she was freed (saved): the tree stays liberated, she never comes back
var sealed: bool = false
var _spec: Dictionary = {}
var _baked: Dictionary = {}
var _tree_at: Vector2 = Vector2.ZERO
var _spiders: Array[Node] = []
var _clock: float = 0.0
var _away: float = 0.0
var _summon_in: float = -1.0
var _gate_root: Node2D
var _bodies: Array[StaticBody2D] = []
var _thorns: Array[Sprite2D] = []
var _grow: float = 0.0 ## 0 withered .. 1 grown (every peer eases towards `sealed`)
var _zone: Rect2 = Rect2()
var _hologram: MorwennaHologram
var _rematch_in: float = -1.0
var opened: bool = false ## Esma has sent somebody (the quest): only then does the tree wake (saved)
var _quest_clock: float = 0.0
var _asked_open: bool = false
var _said: Dictionary = {} ## local: the quest's one-off remarks already made (hallucination, phantom)


func setup(p_world: WorldLevel) -> void:
	world = p_world
	name = "WitchArena"
	add_to_group("witch_arena")
	add_to_group("climb_block")
	_spec = DataRegistry.table("witch_arena")
	_baked = DataRegistry.table("witch_arena_baked")
	var tile: Array = _spec.get("tile", [0, 0]) as Array
	_tree_at = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
	var zone: Dictionary = _baked.get("zone", {}) as Dictionary
	_zone = Rect2(float(zone.get("x", 0.0)), float(zone.get("y", 0.0)), float(zone.get("w", 0.0)), float(zone.get("h", 0.0)))
	_build_gates()
	_hologram = MorwennaHologram.new()
	_hologram.name = "MorwennaHologram"
	_hologram.arena = self
	_hologram.position = _tree_at + HOLOGRAM_AT
	world.add_child.call_deferred(_hologram)
	if not multiplayer.is_server():
		_ask_host.call_deferred()


func tree_position() -> Vector2:
	return _tree_at


func boss_present() -> bool:
	for node: Node in get_tree().get_nodes_in_group("bosses"):
		if node is MirrorWitch and not node.is_queued_for_deletion():
			return true
	return false


# --- the gates (every peer) ----------------------------------------------------------------------------------------


func _build_gates() -> void:
	_gate_root = Node2D.new()
	_gate_root.name = "WitchGates"
	_gate_root.y_sort_enabled = true
	world.add_child.call_deferred(_gate_root)
	var tex: Texture2D = load(THORNS) as Texture2D if ResourceLoader.exists(THORNS) else null
	var glow: Texture2D = load(THORNS_GLOW) as Texture2D if ResourceLoader.exists(THORNS_GLOW) else null
	for gate: Dictionary in _baked.get("gates", []) as Array:
		var r: Array = gate["rect"] as Array
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 0
		body.collision_mask = 0
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(float(r[2]), float(r[3]))
		shape.shape = rect
		shape.position = Vector2(float(r[0]), float(r[1])) + rect.size * 0.5
		body.add_child(shape)
		_gate_root.add_child(body)
		_bodies.append(body)
		if tex == null:
			continue
		for thorn: Array in gate.get("thorns", []) as Array:
			var sprite: Sprite2D = Sprite2D.new()
			sprite.texture = tex
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(Vector2(float(int(thorn[2]) % 3) * THORN_FRAME.x, 0.0), THORN_FRAME)
			sprite.offset = Vector2(-THORN_FRAME.x * 0.5, -THORN_FRAME.y + 3.0)
			sprite.flip_h = bool(thorn[3])
			sprite.position = Vector2(float(thorn[0]), float(thorn[1]))
			sprite.visible = false
			if glow != null and (thorn.size() < 5 or bool(thorn[4])): ## only some hedges carry glowing buds
				var lit: Sprite2D = Sprite2D.new()
				lit.texture = glow
				lit.centered = false
				lit.region_enabled = true
				lit.region_rect = sprite.region_rect
				lit.offset = sprite.offset
				lit.flip_h = sprite.flip_h
				lit.material = Unlit.material()
				lit.modulate.a = THORN_GLOW_ALPHA
				sprite.add_child(lit)
			_gate_root.add_child(sprite)
			_thorns.append(sprite)


func _set_sealed(on: bool) -> void:
	sealed = on
	for body: StaticBody2D in _bodies:
		body.set_deferred("collision_layer", 1 if on else 0)


func _process(delta: float) -> void:
	_quest_clock += delta
	if _quest_clock >= 0.5:
		_quest_clock = 0.0
		_watch_quest()
	if _hologram != null and _hologram.is_inside_tree():
		_hologram.set_active(released and stage == Stage.FREE and not boss_present())
	var want: float = 1.0 if sealed else 0.0
	if is_equal_approx(_grow, want):
		return
	_grow = move_toward(_grow, want, delta * (1.4 if sealed else 0.6))
	for i: int in _thorns.size(): ## they grow in a ripple along the gate, wither all together
		var sprite: Sprite2D = _thorns[i]
		var k: float = clampf(_grow * 1.6 - float(i % 7) * 0.09, 0.0, 1.0) if sealed else _grow
		sprite.visible = k > 0.02
		sprite.scale = Vector2(1.0, k)
		sprite.modulate.a = 1.0 if sealed else k


## Asked by `WallClimb` before a climb: while the hollow is sealed nobody climbs into it or out of it.
func blocks_climb(from: Vector2, to: Vector2) -> bool:
	if not sealed:
		return false
	var grown: Rect2 = _zone.grow(48.0)
	return grown.has_point(from) or grown.has_point(to)


# --- the host's watch ----------------------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_clock += delta
	if _rematch_in >= 0.0:
		_rematch_in -= delta
		if _rematch_in < 0.0:
			summon_boss()
	if _summon_in >= 0.0:
		_summon_in -= delta
		if _summon_in < 0.0 and stage == Stage.PRELUDE:
			_summon_in = -1.0
			summon_boss()
	if _clock < TICK:
		return
	_clock = 0.0
	match stage:
		Stage.CALM:
			if opened and not released and _someone_near(float(_spec.get("wake_range", 300.0))):
				_start_prelude()
		Stage.PRELUDE:
			_spiders = _spiders.filter(func(n: Node) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion() and float((n.get_node("HealthComponent") as HealthComponent).current) > 0.0)
			if _spiders.is_empty() and _summon_in < 0.0:
				_summon_in = THRESHOLD_PAUSE
				_rpc_bark.rpc("morwenna_threshold")
			_watch_empty(TICK)
		Stage.BOSS:
			if not boss_present() and not released:
				_rpc_stage.rpc(Stage.CALM, false)


func _someone_near(radius: float) -> bool:
	for player: Player in Player.all:
		if player.health.current > 0.0 and not player.story_lock and player.global_position.distance_to(_tree_at) < radius:
			return true
	return false


func _watch_empty(step: float) -> void:
	if _someone_near(float(_spec.get("leash", 520.0))):
		_away = 0.0
		return
	_away += step
	if _away >= float(_spec.get("reset_seconds", 8.0)):
		_reset()


func _start_prelude() -> void:
	_away = 0.0
	_summon_in = -1.0
	_spiders.clear()
	var near: Vector2 = _tree_at + Vector2(0, 150)
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(_tree_at) < float(_spec.get("wake_range", 300.0)):
			near = player.global_position
			break
	for offset: Array in _spec.get("spiders", []) as Array:
		var at: Vector2 = _tree_at + Vector2(float(offset[0]), float(offset[1]))
		var spider: ShadowSpider = world.spawn_story_spider("shadow_spider", at, (near - at).angle())
		if spider != null:
			_spiders.append(spider)
	_rpc_stage.rpc(Stage.PRELUDE, true)


## Host: Morwenna falls out of the crown (the fight's entrance).
func summon_boss() -> void:
	if not multiplayer.is_server() or boss_present():
		return
	var players: int = 0
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(_tree_at) < float(_spec.get("leash", 520.0)):
			players += 1
	var node: MirrorWitch = (load(SCENE_PATH) as PackedScene).instantiate() as MirrorWitch
	world._enemy_count += 1
	node.name = "Morwenna%d" % world._enemy_count
	node.enemy_id = String(_spec.get("species", "boss_morwenna"))
	node.health_scale = 1.0 + 0.5 * float(maxi(players - 1, 0)) ## more players: more health (everything else the fight shares out itself)
	node.position = _tree_at + Vector2(0, 46)
	world._enemies.add_child(node, true)
	boss = node
	node.reset_requested.connect(_reset)
	_rpc_stage.rpc(Stage.BOSS, true)


## Host: nobody is left in the hollow: the spiders and she go, the gates open, the tree calms down.
func _reset() -> void:
	for spider: Node in _spiders:
		if is_instance_valid(spider):
			spider.queue_free()
	_spiders.clear()
	if is_instance_valid(boss):
		boss.queue_free()
	boss = null
	_summon_in = -1.0
	_away = 0.0
	_rpc_stage.rpc(Stage.CALM, false)


## Every peer (`MirrorWitch.tree_free`, when the golden dust begins): the tree is free, the gates wither.
func on_released() -> void:
	_flag_local("morwenna_released")
	var first: bool = not released
	released = true
	stage = Stage.FREE
	_set_sealed(false)
	if multiplayer.is_server() and first:
		_after_release.call_deferred()


## Any peer (E at the hologram): she is called back for another fight.
func request_rematch() -> void:
	if multiplayer.is_server():
		_host_rematch()
	else:
		_rpc_ask_rematch.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask_rematch() -> void:
	if multiplayer.is_server():
		_host_rematch()


func _host_rematch() -> void:
	if not released or stage != Stage.FREE or boss_present() or _rematch_in >= 0.0:
		return
	_rematch_in = 1.4 ## the hologram tears first
	_rpc_rematch.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_rematch() -> void:
	if _hologram != null:
		_hologram.touched()
	var tree: CrowTree = get_tree().get_first_node_in_group("crow_tree") as CrowTree
	if tree != null:
		tree.set_liberated(false) ## she drinks again: the tree darkens while she fights


func _after_release() -> void:
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree():
		_rpc_bark.rpc("morwenna_released")


@rpc("authority", "call_local", "reliable")
func _rpc_stage(next: int, seal: bool) -> void:
	var was: Stage = stage
	stage = next as Stage
	_set_sealed(seal)
	if stage == Stage.PRELUDE and was != Stage.PRELUDE: ## the spiders: Ellie's shock, and she has found Mora's tree
		_bark_local("sh_spiders")
		_flag_local("mora_found")
	if stage == Stage.BOSS:
		_flag_local("mora_found") ## (also when she is called without the spiders)
	if stage == Stage.CALM:
		var tree: CrowTree = get_tree().get_first_node_in_group("crow_tree") as CrowTree
		if tree != null:
			tree.drain = 0.0
			tree.set_hour(0.0)
			if released: ## a rematch nobody finished: the tree is free again, the hologram comes back
				tree.set_liberated(true)
		if released:
			stage = Stage.FREE


## Ellie's lines in the speech box, for the local players in the hollow.
@rpc("authority", "call_local", "reliable")
func _rpc_bark(id: String) -> void:
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.global_position.distance_to(_tree_at) < 700.0:
			var box: Node = get_tree().get_first_node_in_group("speech_box")
			if box != null:
				box.call("play", id)
			return


# --- joining, saving, the dev menu ---------------------------------------------------------------------------------


func _ask_host() -> void:
	_ask_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ask_state() -> void:
	if multiplayer.is_server():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), stage, sealed, released, opened)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(p_stage: int, p_sealed: bool, p_released: bool, p_opened: bool) -> void:
	opened = p_opened
	stage = p_stage as Stage
	_set_sealed(p_sealed)
	if p_released:
		_set_released_now()


func export_state() -> Dictionary:
	return {"released": released, "opened": opened}


func import_state(data: Dictionary) -> void:
	opened = bool(data.get("opened", false)) or bool(data.get("released", false))
	if bool(data.get("released", false)):
		_set_released_now()


func _set_released_now() -> void:
	released = true
	stage = Stage.FREE
	var tree: CrowTree = get_tree().get_first_node_in_group("crow_tree") as CrowTree
	if tree != null:
		tree.set_liberated(true, true)


## Developer: the fight at once (any peer asks the host; a released witch is called back, the tree turns dark again). Opens the hollow too.
func debug_fight() -> void:
	if not multiplayer.is_server():
		_rpc_debug_fight.rpc_id(1)
		return
	_rpc_opened.rpc()
	if released and not boss_present():
		_rpc_rematch.rpc()
	for spider: Node in _spiders:
		if is_instance_valid(spider):
			spider.queue_free()
	_spiders.clear()
	summon_boss()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_debug_fight() -> void:
	if multiplayer.is_server():
		debug_fight()



# --- the quest "DIE SPIEGELHEXE" (data/quests.json `spiegelhexe`, docs/enemies/boss_mora.md section 8) ----------------------------------------------


const QUEST: String = "spiegelhexe"
const QUEST_LEVEL: int = 5 ## Valdric only asks once she is strong enough (and the first talisman slot is hers)
const OPEN_STEPS: PackedStringArray = ["sh_tree", "sh_fight", "sh_shard", "sh_back", "sh_forge"]


## Every peer, for its own player, twice a second: Valdric's request starts the quest; Esma's request opens the hollow; the first
## hallucination and the first phantom spider on the way get a remark.
func _watch_quest() -> void:
	for player: Player in Player.all:
		if not player.is_multiplayer_authority() or player.quests == null:
			continue
		var quests: QuestComponent = player.quests
		if not quests.is_active(QUEST) and not quests.is_finished(QUEST) and quests.is_finished("town_workshop") and player.progress.level >= QUEST_LEVEL:
			quests.start(QUEST)
		var step: String = quests.active_step_id(QUEST) if quests.is_active(QUEST) else ""
		if not _asked_open and not opened and (quests.is_finished(QUEST) or step in OPEN_STEPS):
			_asked_open = true
			request_open()
		if step == "" or step in OPEN_STEPS or step in ["sh_valdric", "sh_valdric_talk"]:
			continue
		if not _said.has("hallu") and player.effects != null and player.effects.has("hallucinated"):
			_said["hallu"] = true
			_bark_local("sh_hallu")
		if not _said.has("phantom"):
			for node: Node in get_tree().get_nodes_in_group("phantom_spiders"):
				var phantom: PhantomSpider = node as PhantomSpider
				if phantom != null and phantom.global_position.distance_to(player.global_position) < 220.0:
					_said["phantom"] = true
					_bark_local("sh_phantom")
					phantom.vanished.connect(func() -> void: _bark_local("sh_phantom_gone"), CONNECT_ONE_SHOT)
					break


## Any peer: the hollow may wake from now on (saved).
func request_open() -> void:
	if multiplayer.is_server():
		_rpc_opened.rpc()
	else:
		_rpc_ask_open.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask_open() -> void:
	if multiplayer.is_server():
		_rpc_opened.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_opened() -> void:
	opened = true


## A line in the speech box for this machine's player (when one is in the world).
func _bark_local(id: String) -> void:
	var box: Node = get_tree().get_first_node_in_group("speech_box")
	if box != null and not DataRegistry.get_entry("dialogue", id).is_empty():
		box.call("play", id)


## A quest flag for this machine's players near the tree.
func _flag_local(flag: String) -> void:
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.quests != null and player.global_position.distance_to(_tree_at) < 800.0:
			player.quests.set_flag(flag)


## Developer: the quest from its first step (no level needed).
func debug_quest(player: Player) -> void:
	if player != null and player.quests != null and player.is_multiplayer_authority():
		player.quests.restart(QUEST)
