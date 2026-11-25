class_name GoddessSystem
extends Node
## Host-authoritative coordinator for Caelia ("Die Wächterin"), the Star Hall sanctuary,
## the once-per-player first-death rescue after awakening at least one Waystone,
## statue <-> Star Hall travel, and purifying Shadow Step into Light Step ("LICHTSCHRITT").

signal state_changed(peer_id: int)
signal notice(text: String, good: bool)

const STARHALL_ID: String = "starhall"
const STARHALL_DEFAULT_ORIGIN: Vector2 = Vector2(840.0, 649.0)
const GODDESS_WINDOW_SCRIPT: GDScript = preload("res://src/ui/goddess_window.gd")
const OFFERS: Array[Dictionary] = [
	{"id": "stardust_elixir", "item": "stardust_elixir", "count": 1, "cost": 1},
	{"id": "astral_star_fruit", "item": "astral_star_fruit", "count": 1, "cost": 2},
	{"id": "morningstar_pendant", "item": "morningstar_pendant", "count": 1, "cost": 4},
	{"id": "crescent_earrings", "item": "crescent_earrings", "count": 1, "cost": 5},
	{"id": "blade_starlight", "item": "blade_starlight", "count": 1, "cost": 30},
]
const MILESTONES: Array[Dictionary] = [
	{"id": "m1", "threshold": 3, "title": "STERNENWACHT I", "summary": "+10 LEBEN, +15 AUSDAUER & 2X ELIXIER", "reward": "stardust_elixir", "reward_count": 2, "health": 10, "stamina": 15, "starfall": 0, "step_rank": 0},
	{"id": "m2", "threshold": 6, "title": "STERNENWACHT II", "summary": "+1 STERNSCHNUPPE PRO NACHT & STERNFRUCHT", "reward": "astral_star_fruit", "reward_count": 1, "health": 0, "stamina": 0, "starfall": 1, "step_rank": 0},
	{"id": "m3", "threshold": 12, "title": "STERNENWACHT III", "summary": "STÄRKERER LICHTSCHRITT & 2X STERNFRUCHT", "reward": "astral_star_fruit", "reward_count": 2, "health": 0, "stamina": 0, "starfall": 0, "step_rank": 1},
	{"id": "m4", "threshold": 20, "title": "STERNENWACHT IV", "summary": "SIEGEL DER ERSTEN WÄCHTERIN +15 HP/AUSDAUER", "reward": "caelia_sigil", "reward_count": 1, "health": 15, "stamina": 15, "starfall": 0, "step_rank": 0},
]

var _introduced: Dictionary = {} ## str(peer_id) -> bool
var _light_step: Dictionary = {} ## str(peer_id) -> bool
var _return_statue: Dictionary = {} ## str(peer_id) -> waystone id
var _shards_collected: Dictionary = {} ## str(peer_id) -> int
var _milestones_claimed: Dictionary = {} ## str(peer_id) -> Array of milestone ids
var _altar_greeted: Dictionary = {} ## str(peer_id) -> bool
var _busy: bool = false
var _rescue_overlay: ColorRect
var _rescue_layer: CanvasLayer


static func of(tree: SceneTree) -> GoddessSystem:
	return tree.get_first_node_in_group("goddess") as GoddessSystem


static func starhall_world_anchor(tree: SceneTree, _pos: Vector2) -> Vector2:
	var sys: GoddessSystem = of(tree)
	if sys != null:
		var anchor: Vector2 = sys._anchor_world_pos()
		if anchor != Vector2.ZERO:
			return anchor
	return STARHALL_DEFAULT_ORIGIN


func _ready() -> void:
	name = "GoddessSystem"
	add_to_group("goddess")
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			_rpc_snapshot.rpc_id(peer, _snapshot_dict()))
	_setup_rescue_overlay()
	_sync_and_hook_players()


func _setup_rescue_overlay() -> void:
	_rescue_layer = CanvasLayer.new()
	_rescue_layer.layer = 85
	_rescue_layer.visible = false
	_rescue_overlay = ColorRect.new()
	_rescue_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rescue_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rescue_overlay.color = Color(0.88, 0.98, 0.96, 0.0)
	_rescue_layer.add_child(_rescue_overlay)
	add_child(_rescue_layer)


func _process(_delta: float) -> void:
	_sync_and_hook_players()


func _sync_and_hook_players() -> void:
	for player: Player in Player.all:
		if not is_instance_valid(player):
			continue
		if multiplayer.is_server() and player.health != null:
			if not player.health.story_ward.is_valid():
				player.health.story_ward = Callable(self, "_on_story_ward").bind(player)
		var want_light: bool = has_light_step_player(player)
		if player.light_step != want_light:
			player.light_step = want_light
		if player.is_multiplayer_authority():
			_sync_local_quest(player)


func _sync_local_quest(player: Player) -> void:
	if player == null or player.quests == null:
		return
	if has_light_step_player(player) and not player.quests.is_active("caelia_stars") and not player.quests.is_finished("caelia_stars"):
		player.quests.start("caelia_stars")
	if player.quests.is_active("caelia_stars"):
		var collected: int = shards_collected(player)
		var held: int = player.inventory.count_item("star_shard") if player.inventory != null else 0
		if not player.quests.has_flag("caelia_has_shard") and (held > 0 or collected > 0):
			player.quests.set_flag("caelia_has_shard")
		if not player.quests.has_flag("caelia_first_gift") and collected > 0:
			player.quests.set_flag("caelia_first_gift")


func is_busy() -> bool:
	return _busy


func _key_for(player: Player) -> String:
	return str(player.name.to_int())


func is_introduced_player(player: Player) -> bool:
	return player != null and bool(_introduced.get(_key_for(player), false))


func is_local_introduced() -> bool:
	for player: Player in Player.all:
		if is_instance_valid(player) and player.is_multiplayer_authority():
			return is_introduced_player(player)
	return false


func has_light_step_player(player: Player) -> bool:
	return player != null and bool(_light_step.get(_key_for(player), false))


func shards_collected(player: Player) -> int:
	if player == null:
		return 0
	return int(_shards_collected.get(_key_for(player), 0))


func has_milestone(player: Player, milestone_id: String) -> bool:
	if player == null:
		return false
	var list: Array = _milestones_claimed.get(_key_for(player), []) as Array
	return list.has(milestone_id)


static func offer_spec(offer_id: String) -> Dictionary:
	for entry: Dictionary in OFFERS:
		if String(entry["id"]) == offer_id:
			return entry
	return {}


static func milestone_spec(milestone_id: String) -> Dictionary:
	for entry: Dictionary in MILESTONES:
		if String(entry["id"]) == milestone_id:
			return entry
	return {}


static func star_health_bonus(player_node: Node) -> float:
	var player: Player = player_node as Player
	if player == null or not player.is_inside_tree():
		return 0.0
	var sys: GoddessSystem = of(player.get_tree())
	if sys == null:
		return 0.0
	var total: float = 0.0
	for m: Dictionary in MILESTONES:
		if sys.has_milestone(player, String(m["id"])):
			total += float(m["health"])
	return total


static func star_stamina_bonus(player_node: Node) -> float:
	var player: Player = player_node as Player
	if player == null or not player.is_inside_tree():
		return 0.0
	var sys: GoddessSystem = of(player.get_tree())
	if sys == null:
		return 0.0
	var total: float = 0.0
	for m: Dictionary in MILESTONES:
		if sys.has_milestone(player, String(m["id"])):
			total += float(m["stamina"])
	return total


static func star_step_rank(player_node: Node) -> int:
	var player: Player = player_node as Player
	if player == null or not player.is_inside_tree():
		return 0
	var sys: GoddessSystem = of(player.get_tree())
	if sys == null:
		return 0
	var rank: int = 0
	for m: Dictionary in MILESTONES:
		if sys.has_milestone(player, String(m["id"])):
			rank += int(m["step_rank"])
	return rank


static func any_starfall_bonus(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var sys: GoddessSystem = of(tree)
	if sys == null:
		return 0
	var best: int = 0
	for list: Variant in sys._milestones_claimed.values():
		var arr: Array = list as Array
		var bonus: int = 0
		for m: Dictionary in MILESTONES:
			if arr.has(String(m["id"])):
				bonus += int(m["starfall"])
		best = maxi(best, bonus)
	return best


func can_travel_to_starhall(player: Player) -> bool:
	if player == null:
		return false
	var waystones: Waystones = Waystones.of(get_tree())
	return waystones != null and waystones.awake_count() > 0


func can_rescue(player: Player) -> bool:
	if player == null or _busy:
		return false
	if is_introduced_player(player):
		return false
	if player.intro != null or (player.health != null and player.health.floor_value > 0.0):
		return false
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return false
	var is_coop: bool = NetworkManager.is_coop_session() and not multiplayer.get_peers().is_empty()
	if not is_coop and world.is_in_group("story_world") and not bool(world.get("opening_over")):
		return false
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors != null and interiors.in_starhall(player.global_position):
		return false
	return true


## Host hook on `HealthComponent.story_ward`: intercepts a player's first lethal hit once opening is over & a statue is awake.
func _on_story_ward(_left: float, player: Player) -> float:
	if not multiplayer.is_server() or not can_rescue(player):
		return -1.0
	var key: String = _key_for(player)
	var statue_id: String = _nearest_awake_waystone_id(player.global_position)
	_introduced[key] = true
	if statue_id != "":
		_return_statue[key] = statue_id
	player.health.grant_grace(6.0)
	_rpc_begin_rescue.rpc(player.name.to_int(), statue_id)
	return player.health.max_health


func _nearest_awake_waystone_id(from: Vector2) -> String:
	var waystones: Waystones = Waystones.of(get_tree())
	if waystones == null:
		return ""
	var best_id: String = ""
	var best_dist: float = INF
	for entry: Dictionary in waystones.entries():
		if not bool(entry.get("awake", false)):
			continue
		var sid: String = String(entry["id"])
		var node: WaystoneStatue = waystones.statue_node(sid)
		var d: float = from.distance_to(node.global_position) if node != null else INF
		if d < best_dist or best_id == "":
			best_dist = d
			best_id = sid
	return best_id


func _anchor_world_pos() -> Vector2:
	var waystones: Waystones = Waystones.of(get_tree())
	if waystones == null:
		return STARHALL_DEFAULT_ORIGIN
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority():
			var sid: String = String(_return_statue.get(_key_for(p), ""))
			if sid != "":
				var s: WaystoneStatue = waystones.statue_node(sid)
				if s != null:
					return s.global_position
	var fallback: String = _nearest_awake_waystone_id(STARHALL_DEFAULT_ORIGIN)
	if fallback != "":
		var node: WaystoneStatue = waystones.statue_node(fallback)
		if node != null:
			return node.global_position
	return STARHALL_DEFAULT_ORIGIN


@rpc("authority", "call_local", "reliable")
func _rpc_begin_rescue(peer_id: int, statue_id: String) -> void:
	var key: String = str(peer_id)
	_introduced[key] = true
	if statue_id != "":
		_return_statue[key] = statue_id
	state_changed.emit(peer_id)
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer_id and p.is_multiplayer_authority():
			_run_rescue_sequence(p)
			break


func _run_rescue_sequence(player: Player) -> void:
	if _busy:
		return
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors == null or interiors.interior(STARHALL_ID) == null:
		return
	_busy = true
	player.story_lock = true
	InputManager.ui_blocking = true
	player.velocity = Vector2.ZERO
	LightStepFx.spawn_rescue_pillar(get_tree().current_scene, player.global_position)
	Sfx.at(player, "step_in", player.global_position, -2.0)

	# White-gold celestial flash rises as the beam pulls Ellie out of the Void
	await _flash_cover_to(1.0, 0.72)
	player.request_teleport(interiors.starhall_position())
	player.facing = Vector2.UP
	if player.zero_g != null:
		player.zero_g.trigger_arrive()
	player.sync_wound_visuals()
	interiors.apply_view(player)
	await get_tree().create_timer(0.28, true, false, true).timeout
	await _flash_cover_to(0.0, 0.8)

	player.story_lock = false
	InputManager.ui_blocking = false
	_busy = false

	var box: DialogueBox = DialogueBox.find(player)
	if box != null and not box.is_active():
		box.start("goddess_rescue_wake")


func _flash_cover_to(alpha: float, duration: float) -> void:
	if _rescue_layer == null or _rescue_overlay == null:
		return
	_rescue_layer.visible = true
	var start_a: float = _rescue_overlay.color.a
	var tween: Tween = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(v: float) -> void:
		_rescue_overlay.color = Color(0.90, 0.98, 0.95, v), start_a, alpha, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if alpha <= 0.01:
		_rescue_layer.visible = false


# ---------------------------------------------------------------- statue travel

func travel_to_starhall(player: Player, from_statue_id: String) -> void:
	if player == null or _busy:
		return
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors == null or interiors.interior(STARHALL_ID) == null:
		return
	if multiplayer.is_server():
		_mark_entered_server(player.name.to_int(), from_statue_id)
	else:
		_rpc_mark_entered.rpc_id(1, from_statue_id)
	await interiors.transit(player, func() -> void:
		player.request_teleport(interiors.starhall_position())
		player.facing = Vector2.UP
		if player.zero_g != null:
			player.zero_g.trigger_arrive()
		interiors.apply_view(player), true)


func return_from_starhall(player: Player) -> void:
	if player == null or _busy:
		return
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	var waystones: Waystones = Waystones.of(get_tree())
	if interiors == null:
		return
	var dest: Vector2 = Vector2.INF
	var facing_dir: Vector2 = Vector2.DOWN
	if waystones != null:
		var sid: String = String(_return_statue.get(_key_for(player), ""))
		if sid == "" or waystones.statue_node(sid) == null:
			sid = _nearest_awake_waystone_id(STARHALL_DEFAULT_ORIGIN)
		if sid != "":
			var statue: WaystoneStatue = waystones.statue_node(sid)
			if statue != null:
				dest = statue.global_position + Vector2(0.0, 22.0)
	if not dest.is_finite():
		var world: Node = get_tree().get_first_node_in_group("world")
		if world != null and world.has_method("respawn_point_for"):
			dest = world.call("respawn_point_for", player.name.to_int()) as Vector2
		elif waystones != null:
			for k: Variant in waystones.specs().keys():
				var fallback_statue: WaystoneStatue = waystones.statue_node(String(k))
				if fallback_statue != null:
					dest = fallback_statue.global_position + Vector2(0.0, 22.0)
					break
	if not dest.is_finite():
		return
	await interiors.transit(player, func() -> void:
		player.request_teleport(dest)
		player.facing = facing_dir
		interiors.apply_view(player), true)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_mark_entered(statue_id: String) -> void:
	if multiplayer.is_server():
		_mark_entered_server(multiplayer.get_remote_sender_id(), statue_id)


func _mark_entered_server(peer_id: int, statue_id: String) -> void:
	var key: String = str(peer_id)
	_introduced[key] = true
	if statue_id != "":
		_return_statue[key] = statue_id
	_rpc_entered.rpc(peer_id, statue_id)


@rpc("authority", "call_local", "reliable")
func _rpc_entered(peer_id: int, statue_id: String) -> void:
	var key: String = str(peer_id)
	_introduced[key] = true
	if statue_id != "":
		_return_statue[key] = statue_id
	state_changed.emit(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_return_statue(statue_id: String) -> void:
	if multiplayer.is_server():
		_set_return_statue_server(multiplayer.get_remote_sender_id(), statue_id)


func _set_return_statue_server(peer_id: int, statue_id: String) -> void:
	var key: String = str(peer_id)
	_return_statue[key] = statue_id
	_rpc_return_statue.rpc(peer_id, statue_id)


@rpc("authority", "call_local", "reliable")
func _rpc_return_statue(peer_id: int, statue_id: String) -> void:
	_return_statue[str(peer_id)] = statue_id


# ---------------------------------------------------------------- talking & blessing

func talk_to_goddess(player: Player, actor: StarHallGoddess) -> void:
	if player == null or actor == null or _busy:
		return
	var box: DialogueBox = DialogueBox.find(player)
	if box != null and box.is_active():
		return
	var first_blessing: bool = not has_light_step_player(player)
	if first_blessing:
		if box == null:
			return
		actor.set_talking(true)
		box.start("goddess_intro")
		await box.finished
		actor.set_talking(false)
		_busy = true
		player.story_lock = true
		actor.play_bless()
		LightStepFx.spawn_blessing(player)
		Sfx.at(player, "step_in", player.global_position, -1.0)
		if multiplayer.is_server():
			_host_grant_light_step(player.name.to_int(), true)
		else:
			_rpc_request_bless.rpc_id(1)
		await get_tree().create_timer(1.1, true, false, true).timeout
		player.story_lock = false
		_busy = false
		return

	var key: String = _key_for(player)
	if not bool(_altar_greeted.get(key, false)) and box != null:
		actor.set_talking(true)
		box.start("goddess_return")
		await box.finished
		actor.set_talking(false)
		if multiplayer.is_server():
			_host_mark_altar_greeted(player.name.to_int())
		else:
			_rpc_mark_altar_greeted.rpc_id(1)
	open_altar(player, actor)


func open_altar(player: Player, actor: StarHallGoddess = null) -> BoardWindow:
	if player == null or not player.is_multiplayer_authority():
		return null
	var town_node: TownManager = get_tree().get_first_node_in_group("town") as TownManager
	return GODDESS_WINDOW_SCRIPT.call("open", get_tree(), player, town_node, actor) as BoardWindow


@rpc("any_peer", "call_remote", "reliable")
func _rpc_mark_altar_greeted() -> void:
	if multiplayer.is_server():
		_host_mark_altar_greeted(multiplayer.get_remote_sender_id())


func _host_mark_altar_greeted(peer_id: int) -> void:
	_altar_greeted[str(peer_id)] = true
	_rpc_altar_state.rpc(_altar_state_dict(peer_id), peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_bless() -> void:
	if multiplayer.is_server():
		_host_grant_light_step(multiplayer.get_remote_sender_id(), true)


func _host_grant_light_step(peer_id: int, grant: bool) -> void:
	var key: String = str(peer_id)
	_introduced[key] = true
	_light_step[key] = grant
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer_id:
			p.set_light_step(grant)
			if grant and p.health != null and p.health.current < p.health.max_health:
				p.health.heal(p.health.max_health)
			if grant and p.is_multiplayer_authority():
				_sync_local_quest(p)
	_rpc_light_step_state.rpc(peer_id, grant, true)


@rpc("authority", "call_local", "reliable")
func _rpc_light_step_state(peer_id: int, light: bool, intro: bool) -> void:
	var key: String = str(peer_id)
	_light_step[key] = light
	if intro:
		_introduced[key] = true
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer_id:
			p.light_step = light
			if p.is_multiplayer_authority():
				_sync_local_quest(p)
	state_changed.emit(peer_id)


# ---------------------------------------------------------------- star shard altar & milestones

func request_exchange(offer_id: String) -> void:
	if multiplayer.is_server():
		_host_exchange(1, offer_id)
	else:
		_rpc_exchange.rpc_id(1, offer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_exchange(offer_id: String) -> void:
	if multiplayer.is_server():
		_host_exchange(multiplayer.get_remote_sender_id(), offer_id)


func _host_exchange(peer_id: int, offer_id: String) -> void:
	var player: Player = _player_by_peer(peer_id)
	var offer: Dictionary = offer_spec(offer_id)
	if player == null or player.inventory == null or offer.is_empty():
		return
	var cost: int = int(offer["cost"])
	var item_id: String = String(offer["item"])
	var count: int = int(offer["count"])
	if player.inventory.count_item("star_shard") < cost:
		_send_notice(peer_id, "NICHT GENUG STERNERZ.", false)
		return
	if not player.inventory.exchange_items("star_shard", cost, item_id, count):
		_send_notice(peer_id, "BEUTEL IST VOLL.", false)
		return
	var key: String = str(peer_id)
	_shards_collected[key] = int(_shards_collected.get(key, 0)) + cost
	_play_altar_fx(player)
	_rpc_altar_state.rpc(_altar_state_dict(peer_id), peer_id)
	var def: Dictionary = DataRegistry.get_entry("items", item_id)
	_send_notice(peer_id, "%s ERHALTEN!" % String(def.get("name", item_id)).to_upper(), true)


func request_donate(amount: int = 1) -> void:
	if multiplayer.is_server():
		_host_donate(1, amount)
	else:
		_rpc_donate.rpc_id(1, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_donate(amount: int) -> void:
	if multiplayer.is_server():
		_host_donate(multiplayer.get_remote_sender_id(), amount)


func _host_donate(peer_id: int, amount: int) -> void:
	var player: Player = _player_by_peer(peer_id)
	var amt: int = maxi(amount, 1)
	if player == null or player.inventory == null:
		return
	if not player.inventory.remove_item("star_shard", amt):
		_send_notice(peer_id, "NICHT GENUG STERNERZ.", false)
		return
	var key: String = str(peer_id)
	_shards_collected[key] = int(_shards_collected.get(key, 0)) + amt
	if player.health != null:
		player.health.heal(15.0 * float(amt))
	_play_altar_fx(player)
	_rpc_altar_state.rpc(_altar_state_dict(peer_id), peer_id)
	_send_notice(peer_id, "%dX STERNERZ GEWEIHT!" % amt, true)


func request_claim_milestone(milestone_id: String) -> void:
	if multiplayer.is_server():
		_host_claim_milestone(1, milestone_id)
	else:
		_rpc_claim_milestone.rpc_id(1, milestone_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_claim_milestone(milestone_id: String) -> void:
	if multiplayer.is_server():
		_host_claim_milestone(multiplayer.get_remote_sender_id(), milestone_id)


func _host_claim_milestone(peer_id: int, milestone_id: String) -> void:
	var player: Player = _player_by_peer(peer_id)
	var spec: Dictionary = milestone_spec(milestone_id)
	if player == null or player.inventory == null or spec.is_empty():
		return
	var key: String = str(peer_id)
	var list: Array = (_milestones_claimed.get(key, []) as Array).duplicate()
	if list.has(milestone_id):
		_send_notice(peer_id, "BEREITS ERHALTEN.", false)
		return
	if int(_shards_collected.get(key, 0)) < int(spec["threshold"]):
		_send_notice(peer_id, "NOCH ZU WENIG STERNERZ DARGEBRACHT.", false)
		return
	var reward_id: String = String(spec["reward"])
	var reward_count: int = int(spec["reward_count"])
	if reward_id != "" and not player.inventory.exchange_items("star_shard", 0, reward_id, reward_count):
		_send_notice(peer_id, "BEUTEL IST VOLL.", false)
		return
	list.append(milestone_id)
	_milestones_claimed[key] = list
	if player.progress != null:
		player.progress.apply_stats(true, true)
	_play_altar_fx(player)
	_rpc_altar_state.rpc(_altar_state_dict(peer_id), peer_id)
	_send_notice(peer_id, "%s EMPFANGEN!" % String(spec["title"]), true)


func _player_by_peer(peer_id: int) -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer_id:
			return p
	return null


func _play_altar_fx(player: Player) -> void:
	var goddess_actor: StarHallGoddess = get_tree().get_first_node_in_group("quest_actors") as StarHallGoddess
	if goddess_actor != null:
		goddess_actor.play_bless()
	if player != null and player.is_inside_tree():
		LightStepFx.spawn_blessing(player)
		Sfx.at(player, "step_in", player.global_position, -4.0)


func _send_notice(peer_id: int, text: String, good: bool) -> void:
	if peer_id == 1 or multiplayer.get_unique_id() == peer_id:
		notice.emit(text, good)
	else:
		_rpc_notice.rpc_id(peer_id, text, good)


@rpc("authority", "reliable")
func _rpc_notice(text: String, good: bool) -> void:
	notice.emit(text, good)


func _altar_state_dict(peer_id: int) -> Dictionary:
	var key: String = str(peer_id)
	return {
		"shards": int(_shards_collected.get(key, 0)),
		"milestones": (_milestones_claimed.get(key, []) as Array).duplicate(),
		"greeted": bool(_altar_greeted.get(key, false)),
	}


@rpc("authority", "call_local", "reliable")
func _rpc_altar_state(entry: Dictionary, peer_id: int) -> void:
	var key: String = str(peer_id)
	_shards_collected[key] = int(entry.get("shards", 0))
	_milestones_claimed[key] = (entry.get("milestones", []) as Array).duplicate()
	_altar_greeted[key] = bool(entry.get("greeted", false))
	var p: Player = _player_by_peer(peer_id)
	if p != null:
		if p.progress != null:
			p.progress.apply_stats(false, true)
		if p.is_multiplayer_authority():
			_sync_local_quest(p)
	state_changed.emit(peer_id)


func _snapshot_dict() -> Dictionary:
	return {
		"introduced": _introduced.duplicate(),
		"light_step": _light_step.duplicate(),
		"return_statue": _return_statue.duplicate(),
		"shards_collected": _shards_collected.duplicate(),
		"milestones_claimed": _milestones_claimed.duplicate(true),
		"altar_greeted": _altar_greeted.duplicate(),
	}


@rpc("authority", "reliable")
func _rpc_snapshot(snapshot: Dictionary) -> void:
	_introduced = SaveGame.as_dict(snapshot.get("introduced")).duplicate()
	_light_step = SaveGame.as_dict(snapshot.get("light_step")).duplicate()
	_return_statue = SaveGame.as_dict(snapshot.get("return_statue")).duplicate()
	_shards_collected = SaveGame.as_dict(snapshot.get("shards_collected")).duplicate()
	_milestones_claimed = SaveGame.as_dict(snapshot.get("milestones_claimed")).duplicate(true)
	_altar_greeted = SaveGame.as_dict(snapshot.get("altar_greeted")).duplicate()
	_sync_and_hook_players()


# ---------------------------------------------------------------- save / load

func export_state() -> Dictionary:
	return _snapshot_dict()


func import_state(data: Dictionary) -> void:
	_introduced = SaveGame.as_dict(data.get("introduced")).duplicate()
	_light_step = SaveGame.as_dict(data.get("light_step")).duplicate()
	_return_statue = SaveGame.as_dict(data.get("return_statue")).duplicate()
	_shards_collected = SaveGame.as_dict(data.get("shards_collected")).duplicate()
	_milestones_claimed = SaveGame.as_dict(data.get("milestones_claimed")).duplicate(true)
	_altar_greeted = SaveGame.as_dict(data.get("altar_greeted")).duplicate()
	_sync_and_hook_players()
	if multiplayer.is_server() and NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(_snapshot_dict())
	for p: Player in Player.all:
		if is_instance_valid(p) and p.progress != null:
			p.progress.apply_stats(false, true)


# ---------------------------------------------------------------- dev tools

func debug_enter_starhall(player: Player) -> void:
	if player == null or not multiplayer.is_server():
		return
	var sid: String = _nearest_awake_waystone_id(player.global_position)
	if sid != "":
		_set_return_statue_server(player.name.to_int(), sid)
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors != null and interiors.interior(STARHALL_ID) != null:
		player.request_teleport(interiors.starhall_position())
		player.facing = Vector2.UP
		interiors.apply_view(player)


func debug_trigger_rescue(player: Player) -> void:
	if player == null or not multiplayer.is_server():
		return
	var key: String = _key_for(player)
	var sid: String = _nearest_awake_waystone_id(player.global_position)
	if sid == "":
		var waystones: Waystones = Waystones.of(get_tree())
		if waystones != null:
			for k: Variant in waystones.specs().keys():
				sid = String(k)
				break
	_introduced[key] = true
	if sid != "":
		_return_statue[key] = sid
	player.health.heal(player.health.max_health)
	_rpc_begin_rescue.rpc(player.name.to_int(), sid)


func debug_grant_light_step(player: Player, on: bool) -> void:
	if player == null or not multiplayer.is_server():
		return
	_host_grant_light_step(player.name.to_int(), on)


func debug_unlock_statues(player: Player) -> void:
	if player == null or not multiplayer.is_server():
		return
	var key: String = _key_for(player)
	_introduced[key] = true
	var waystones: Waystones = Waystones.of(get_tree())
	if waystones != null and waystones.awake_count() == 0:
		for id: Variant in waystones.specs().keys():
			waystones.request_activate(String(id))
			break
	if not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(_snapshot_dict())
	state_changed.emit(player.name.to_int())


func debug_reset(player: Player) -> void:
	if player == null or not multiplayer.is_server():
		return
	var key: String = _key_for(player)
	_introduced.erase(key)
	_light_step.erase(key)
	_return_statue.erase(key)
	_shards_collected.erase(key)
	_milestones_claimed.erase(key)
	_altar_greeted.erase(key)
	player.set_light_step(false)
	if player.progress != null:
		player.progress.apply_stats(false, true)
	if not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(_snapshot_dict())
	state_changed.emit(player.name.to_int())
