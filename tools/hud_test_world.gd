extends RefCounted
## Loads the v2 main world (`ZoneWorld`) for HUD tests and look studies (docs/hud_v2_konzept.md, step 1) and returns the
## local player once the HUD has grown in. Loads in steps across frames like `GameLauncher`: the plain `_ready` path of
## `ZoneWorld` spins in `while not loading_step()` without a frame, but a zone build finishes in `Jobs` callbacks that
## need frames, so it can hang.
## Use: `var player: Player = await HudTestWorld.open(self)` with `const HudTestWorld := preload("res://tools/hud_test_world.gd")`.

const WORLD_PATH: String = "res://src/world/v2/zone_world.tscn"


## Hosts a local session when none runs, adds the world under `host`, loads it and waits for the local player.
## Returns null when nothing came within `timeout_ms`. The HUD is unlocked and fully grown in.
static func open(host: Node, timeout_ms: int = 90000) -> Player:
	var tree: SceneTree = host.get_tree()
	host.add_to_group("sandbox") ## SaveGame and CloudSession never save while a sandbox node exists
	if host.multiplayer.multiplayer_peer == null or host.multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		NetworkManager.host_singleplayer()
	var world: Node = (load(WORLD_PATH) as PackedScene).instantiate()
	world.set("loading_in_steps", true)
	host.add_child(world)
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not bool(world.call("loading_init_step")):
		await tree.process_frame
		if Time.get_ticks_msec() > deadline:
			return null
	while not bool(world.call("loading_step")):
		await tree.process_frame
		if Time.get_ticks_msec() > deadline:
			return null
	await tree.physics_frame
	while not bool(world.call("loading_warmup_step")):
		await tree.process_frame
		if Time.get_ticks_msec() > deadline:
			return null
	world.set("loading_in_steps", false)
	var player: Player = null
	while player == null:
		player = SaveGame._local_player(tree)
		if player == null or player.get("_hud") == null:
			player = null
			await tree.process_frame
			if Time.get_ticks_msec() > deadline:
				return null
	if player.quests != null:
		player.quests.set_flag("hud_unlocked")
	var hud: Node = player.get("_hud") as Node
	if hud.has_method("open"):
		hud.call("open")
	for i: int in 200: ## the grow-in takes about 2.5 s
		await tree.process_frame
	return player


## The world node `open` added (the first child of `host` that is a world).
static func world_of(host: Node) -> Node:
	for child: Node in host.get_children():
		if child.is_in_group("world"):
			return child
	return null
