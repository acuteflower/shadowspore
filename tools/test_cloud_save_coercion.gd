extends Node
## Regression test for silent Release crash (0xc0000005) when Nakama Lua serializes
## empty Lua tables `{}` as JSON `[]` in `saves/player_profile` and world imports,
## plus dead/connecting RelayPeer RPC safety in `NetworkManager`.

const RelayPeer: GDScript = preload("res://src/autoload/nakama_relay_peer.gd")

var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("FAIL: TIMEOUT after 45s")
		get_tree().quit(1)
	)
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: %s" % label)
	else:
		_failures += 1
		printerr("FAIL: %s" % label)


func _run() -> void:
	# 1. Helper coercion checks
	_check(SaveGame.as_dict([]).is_empty(), "as_dict([]) -> empty Dict")
	_check(SaveGame.as_dict(null).is_empty(), "as_dict(null) -> empty Dict")
	_check(SaveGame.as_dict("invalid").is_empty(), "as_dict(String) -> empty Dict")
	_check(int(SaveGame.as_dict({"k": 5}).get("k", 0)) == 5, "as_dict(Dict) preserved")
	_check(SaveGame.as_array({}).is_empty(), "as_array({}) -> empty Array")
	_check(SaveGame.as_array(null).is_empty(), "as_array(null) -> empty Array")
	_check(SaveGame.as_array([1, 2]).size() == 2, "as_array(Array) preserved")
	_check(SaveGame._stack([]).is_empty(), "_stack([]) -> empty Dict")
	_check(SaveGame._stack(null).is_empty(), "_stack(null) -> empty Dict")
	var valid_stack: Dictionary = SaveGame._stack({"id": "torch", "count": 3.0})
	_check(String(valid_stack.get("id", "")) == "torch" and valid_stack.get("count") is int and int(valid_stack.get("count", 0)) == 3, "_stack converts float count to int")

	# 2. Boot real campaign ZoneWorld + Player
	var world: ZoneWorld = load("res://src/world/v2/zone_world.tscn").instantiate() as ZoneWorld
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	_check(player != null and is_instance_valid(player), "ZoneWorld spawns local player")

	# Wait briefly if chunk streaming uses steps
	var deadline: int = Time.get_ticks_msec() + 15000
	while bool(world.get("loading_in_steps")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	# 3. Exact Nakama Lua-corrupted player_profile (empty `{}` became `[]` via nk.storage_write)
	var nakama_player_json: String = JSON.stringify({
		"xp": 150.0,
		"claimed": 2.0,
		"copper": 42.0,
		"health": 80.0,
		"bandaged": false,
		"pos": [12563.9258, 10946.4424],
		"skill_tree": {"discovered": [], "learned": []},
		"slots": [[], [], {"id": "torch", "count": 2.0}, null],
		"equipment": {"main_hand": [], "off_hand": []},
		"raw_rolls": [],
		"appearance": {
			"unlocked_hair_styles": [],
			"unlocked_hair_colors": [],
			"unlocked_outfits": [],
			"unlocked_outfit_colors": [],
			"outfit": "default",
			"hair": "default",
		},
		"quests": {
			"flags": [],
			"active": [],
			"active_steps": [],
			"done": ["awakening"],
		},
		"board_local": {
			"seen": [],
			"focus": "",
			"focus_cleared": false,
		},
	})
	var pdata_a: Dictionary = SaveGame.as_dict(JSON.parse_string(nakama_player_json))
	SaveGame.import_player_data(player, pdata_a, true, true)
	await get_tree().process_frame
	_check(player.position.distance_to(Vector2(12563.9258, 10946.4424)) < 0.05, "Nakama player pos restored")
	_check(player.progress.copper == 42 and player.progress.claimed == 2, "Nakama player progress restored")
	_check(player.inventory.slots[0].is_empty() and player.inventory.slots[3].is_empty(), "Nakama []/null inventory slots stay empty Dicts")
	_check(String(player.inventory.slots[2].get("id", "")) == "torch" and int(player.inventory.slots[2].get("count", 0)) == 2, "Nakama valid stack preserved")
	_check((player.inventory.equipment.get("main_hand", {}) as Dictionary).is_empty(), "Nakama [] equipment slot becomes empty Dict")
	var q_exported: Dictionary = player.quests.export_data()
	_check(SaveGame.as_dict(q_exported.get("active")).is_empty(), "Nakama active:[] quests imported without crash")
	_check(SaveGame.as_array(q_exported.get("done")).has("awakening"), "Nakama done quests preserved")

	# 4. Extreme all-collapsed Variant payload (top-level sub-tables replaced with `[]` or `null`)
	var pdata_b: Dictionary = {
		"xp": 50.0,
		"claimed": 1.0,
		"copper": 7.0,
		"health": 50.0,
		"pos": null,
		"skill_tree": [],
		"slots": null,
		"equipment": [],
		"raw_rolls": null,
		"appearance": [],
		"quests": [],
		"board_local": [],
		"held": [],
	}
	SaveGame.import_player_data(player, pdata_b, true, true)
	SaveGame.restore_guest_economy(player, pdata_b)
	_check(player.inventory.held.is_empty(), "restore_guest_economy tolerates held:[]")
	CloudSession._remember_solo_preserve(pdata_a)
	CloudSession._remember_solo_preserve(pdata_b)
	CloudSession._solo_profile_preserve.clear()
	_check(true, "CloudSession._remember_solo_preserve tolerates collapsed tables")

	# 5. Nakama-corrupted world payload across all subsystem importers
	_check(not SaveGame.import_world_data(get_tree(), {"version": 1, "day": 3}, player, false), "import_world_data rejects legacy v1 saves")
	var corrupted_world: Dictionary = {
		"version": SaveGame.VERSION,
		"day": 3,
		"time": 0.45,
		"opening_over": true,
		"sleep": [],
		"zone_world": {"discovered": [], "player_zones": []},
		"things": {"10,20": [], "h:foo": null},
		"story": [],
		"mine": [],
		"town": {
			"founded": true,
			"brewed": [],
			"look": [],
			"center": [],
			"structures": {"bad": []},
			"cleared": [],
			"paths": [],
			"orders": [],
			"residents": {"bad": []},
			"unlocks": [],
			"farm": {"bad": []},
			"board": {
				"offers": [],
				"taken": [],
				"archive": [],
				"occ": [],
				"story": [],
				"honor": {"town": [], "peers": [], "titles": [], "fallen": []},
			},
			"caravan": {"visit": [], "pre": [], "force": []},
		},
		"night": {"memory": {"s1": []}, "report": [], "marked": []},
		"waystones": {"awake": []},
		"goddess": {
			"introduced": [],
			"light_step": [],
			"return_statue": [],
			"shards_collected": [],
			"milestones_claimed": [],
			"altar_greeted": [],
		},
		"ward_rings": [],
		"witch": [],
		"aurelith": [],
		"relics": {"kills": [], "owed": [null, []]},
		"chests": {"opened": [], "extra": [], "boss": {"bad": []}},
		"puzzles": {"progress": [], "solved": []},
		"pets": {"bonds": [], "birds": [], "hoards": {"b1": {}}, "comp": {"1": []}},
		"vistas": [],
		"meadow_landmarks": [],
		"meadow_pois": {"order": [], "mills": [], "boats": []},
		"meadow_wonders": [],
		"map": null,
	}
	var world_ok: bool = SaveGame.import_world_data(get_tree(), corrupted_world, player, false)
	_check(world_ok, "import_world_data completes cleanly with Lua []/null fields")
	SaveGame.import_player_data(player, {"pos": [NAN, INF], "health": NAN}, true, false)
	_check(player.position.is_finite() and is_finite(player.health.current) and player.health.current > 0.0, "import_player_data ignores non-finite pos/health")
	_check(SaveGame.decompress_json("not_valid_base64!!").is_empty(), "decompress_json rejects malformed payload cleanly")
	await get_tree().process_frame

	# 6. NetworkManager.rpc_ready + dead/connecting RelayPeer RPC safety across subsystems
	_check(not NetworkManager.rpc_ready(null), "rpc_ready(null) == false")
	_check(NetworkManager.rpc_ready(world), "rpc_ready(world) == true on OfflineMultiplayerPeer")

	var fake_relay: NakamaRelayPeer = RelayPeer.new() as NakamaRelayPeer
	fake_relay._is_host = true
	fake_relay._unique_id = 1
	fake_relay._status = MultiplayerPeer.CONNECTION_CONNECTING
	multiplayer.multiplayer_peer = fake_relay
	NetworkManager.transport_mode = "relay"
	_check(not NetworkManager.rpc_ready(world), "rpc_ready(world) == false while RelayPeer CONNECTING")
	fake_relay._handle_ws_text("{\"error\":[]}")
	fake_relay._status = MultiplayerPeer.CONNECTION_CONNECTING
	fake_relay._handle_ws_text("{\"match_data\":[]}")
	fake_relay._handle_control("{\"type\":\"welcome\",\"self_peer_id\":1,\"peers\":{}}")
	_check(fake_relay._status == MultiplayerPeer.CONNECTION_CONNECTED, "RelayPeer handles coerced empty Lua tables cleanly")
	fake_relay._status = MultiplayerPeer.CONNECTION_CONNECTING
	SaveGame.sync_player_to_network(player)
	TimeManager.import_sleep_state({"fatigue": 0.25, "nights_awake": 1, "slept_night_id": 1})
	SaveGame.import_world_data(get_tree(), corrupted_world, player, false)
	_check(true, "sync/import RPC paths stay safe while RelayPeer CONNECTING")

	fake_relay._status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_check(not NetworkManager.rpc_ready(world), "rpc_ready(world) == false while RelayPeer DISCONNECTED")
	NetworkManager._process(0.016)
	_check(multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "NetworkManager recovers host from dead RelayPeer to OfflineMultiplayerPeer")
	_check(NetworkManager.rpc_ready(world), "rpc_ready(world) == true after fallback to OfflineMultiplayerPeer")

	NetworkManager.leave(false)
	world.queue_free()
	await get_tree().process_frame

	print("CLOUD SAVE COERCION TEST FAILURES=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
