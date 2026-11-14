class_name MeadowWonders
extends Node2D
## Chunk-streamed, host-authoritative manager for the three one-of-a-kind World Wonders of the
## standard meadow biome (`docs/wiesenbiom_ausbau_konzept.md` Stufe 5):
##  1. `BellPond` (*Der Glockenteich*, `[795, 525]` -> `[801, 525]`): underwater midnight bell & dry stepping-stone causeway.
##  2. `SleepingGuardians` (*Der Kreis der Schlafenden Wächter*, `[256, 205]`): 7 monolith sentinels, headstone carry OR 1..7 braziers.
##  3. `FlowerAmphitheater` (*Das Blumen-Amphitheater*, `[421, 667]`): moonflower stage & 42 dancing night wisps.
## Registers in `Terrain.patches` so `BellPond`'s risen stepping stones provide a dry `"stone"` water deck (`has_water_deck_at`).
## Saved under `"meadow_wonders"` in `SaveGame`.

var world: WorldLevel
var _sites_by_chunk: Dictionary = {} ## Vector2i(chunk) -> Array[Dictionary]
var _live_chunks: Dictionary = {} ## Vector2i(chunk) -> Array[Node]

var _bell_node: BellPond
var _guardians_node: SleepingGuardians
var _amphitheater_node: FlowerAmphitheater

var _bell_awake: bool = false
var _guardians_awake: bool = false
var _guardians_head_restored: bool = false
var _guardians_lit_step: int = 0
var _guardians_carrier: int = 0
var _guardians_head_local: Vector2 = Vector2(88.0, 56.0)
var _amphitheater_awake: bool = false

var _banner: TownBanner


static func of(tree: SceneTree) -> MeadowWonders:
	return tree.get_first_node_in_group("meadow_wonders") as MeadowWonders


func _ready() -> void:
	add_to_group("meadow_wonders")
	Terrain.patches.append(self)
	tree_exiting.connect(func() -> void: Terrain.patches.erase(self))
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			_rpc_snapshot.rpc_id(
				peer,
				_bell_awake,
				_guardians_awake,
				_guardians_head_restored,
				_guardians_lit_step,
				_guardians_carrier,
				_guardians_head_local,
				_amphitheater_awake
			))


func has_progress() -> bool:
	return _bell_awake or _guardians_awake or _guardians_head_restored or _amphitheater_awake


func is_bell_awakened() -> bool:
	return _bell_awake


func is_guardians_awakened() -> bool:
	return _guardians_awake


func is_amphitheater_awakened() -> bool:
	return _amphitheater_awake


func bell_shore_tile() -> Vector2i:
	var st: Array = (DataRegistry.table("meadow_wonders").get("bell_pond", {}) as Dictionary).get("shore_tile", [795, 525]) as Array
	return Vector2i(int(st[0]), int(st[1]))


func guardians_tile() -> Vector2i:
	var gt: Array = (DataRegistry.table("meadow_wonders").get("sleeping_guardians", {}) as Dictionary).get("tile", [256, 205]) as Array
	return Vector2i(int(gt[0]), int(gt[1]))


func amphitheater_tile() -> Vector2i:
	var at: Array = (DataRegistry.table("meadow_wonders").get("flower_amphitheater", {}) as Dictionary).get("tile", [421, 667]) as Array
	return Vector2i(int(at[0]), int(at[1]))


func setup(level: WorldLevel) -> Dictionary:
	world = level
	_sites_by_chunk.clear()
	var blocked: Dictionary = {}
	var table: Dictionary = DataRegistry.table("meadow_wonders")

	var bp: Dictionary = table.get("bell_pond", {}) as Dictionary
	if not bp.is_empty():
		var st: Array = bp.get("shore_tile", [795, 525]) as Array
		var sp: Array = bp.get("spire_tile", [801, 525]) as Array
		var shore_t: Vector2i = Vector2i(int(st[0]), int(st[1]))
		var spire_t: Vector2i = Vector2i(int(sp[0]), int(sp[1]))
		_add_site(shore_t, {"kind": "bell_pond", "spec": bp})
		_mark_square(blocked, shore_t, 4)
		_mark_square(blocked, spire_t, 4)

	var sg: Dictionary = table.get("sleeping_guardians", {}) as Dictionary
	if not sg.is_empty():
		var gt: Array = sg.get("tile", [256, 205]) as Array
		var g_tile: Vector2i = Vector2i(int(gt[0]), int(gt[1]))
		var hs: Array = sg.get("headstone_offset", [88.0, 56.0]) as Array
		_guardians_head_local = Vector2(float(hs[0]), float(hs[1]))
		_add_site(g_tile, {"kind": "sleeping_guardians", "spec": sg})
		_mark_square(blocked, g_tile, 8)

	var fa: Dictionary = table.get("flower_amphitheater", {}) as Dictionary
	if not fa.is_empty():
		var at: Array = fa.get("tile", [421, 667]) as Array
		var a_tile: Vector2i = Vector2i(int(at[0]), int(at[1]))
		_add_site(a_tile, {"kind": "flower_amphitheater", "spec": fa})
		_mark_square(blocked, a_tile, 9)

	return blocked


func _add_site(tile: Vector2i, entry: Dictionary) -> void:
	var chunk_cell: Vector2i = tile / WorldLevel.CHUNK
	(_sites_by_chunk.get_or_add(chunk_cell, []) as Array).append(entry)


static func _mark_square(blocked: Dictionary, center: Vector2i, rad: int) -> void:
	for dy: int in range(-rad, rad + 1):
		for dx: int in range(-rad, rad + 1):
			blocked[center + Vector2i(dx, dy)] = true


func surface_at(world_pos: Vector2) -> String:
	if _bell_node != null and is_instance_valid(_bell_node) and _bell_node.contains_deck_point(world_pos):
		return "stone"
	return ""


func has_water_deck_at(world_pos: Vector2) -> bool:
	return surface_at(world_pos) != ""


func populate_chunk(chunk_cell: Vector2i) -> void:
	if _live_chunks.has(chunk_cell) or not _sites_by_chunk.has(chunk_cell):
		return
	var spawned: Array[Node] = []
	var props_parent: Node2D = world._props if world != null and world._props != null else self

	for entry_v: Variant in _sites_by_chunk[chunk_cell] as Array:
		var entry: Dictionary = entry_v as Dictionary
		var kind: String = String(entry.kind)
		var spec: Dictionary = entry.spec as Dictionary
		match kind:
			"bell_pond":
				var pond: BellPond = BellPond.new()
				pond.name = "Wonder_BellPond"
				pond.setup(self, spec)
				add_child(pond)
				if _bell_awake:
					pond.set_awakened_instant(true)
				_bell_node = pond
				spawned.append(pond)
			"sleeping_guardians":
				var ring: SleepingGuardians = SleepingGuardians.new()
				ring.name = "Wonder_SleepingGuardians"
				ring.setup(self, spec)
				props_parent.add_child(ring)
				ring.lit_step = _guardians_lit_step
				ring.set_state_instant(_guardians_awake, _guardians_head_restored)
				if not _guardians_awake:
					ring.apply_headstone_carrier(_guardians_carrier, _guardians_head_local)
				_guardians_node = ring
				spawned.append(ring)
			"flower_amphitheater":
				var amp: FlowerAmphitheater = FlowerAmphitheater.new()
				amp.name = "Wonder_FlowerAmphitheater"
				amp.setup(self, spec)
				props_parent.add_child(amp)
				if _amphitheater_awake:
					amp.set_awakened_instant(true)
				_amphitheater_node = amp
				spawned.append(amp)

	_live_chunks[chunk_cell] = spawned


func free_chunk(chunk_cell: Vector2i) -> void:
	if not _live_chunks.has(chunk_cell):
		return
	var list: Array = _live_chunks[chunk_cell] as Array
	_live_chunks.erase(chunk_cell)
	for n_v: Variant in list:
		var n: Node = n_v as Node
		if is_instance_valid(n):
			if n == _bell_node:
				_bell_node = null
			elif n == _guardians_node:
				_guardians_node = null
			elif n == _amphitheater_node:
				_amphitheater_node = null
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()


# ---------------------------------------------------------------- 1. Bell Pond

func request_awaken_bell_pond() -> void:
	if multiplayer.is_server():
		_host_awaken_bell(multiplayer.get_unique_id())
	else:
		_rpc_req_bell.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_bell() -> void:
	if multiplayer.is_server():
		_host_awaken_bell(multiplayer.get_remote_sender_id())


func _host_awaken_bell(peer_id: int) -> void:
	if not multiplayer.is_server() or _bell_awake or _bell_node == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	if who.global_position.distance_to(_bell_node.spire_pos) > 78.0:
		return
	_bell_awake = true
	var spec: Dictionary = DataRegistry.table("meadow_wonders").get("bell_pond", {}) as Dictionary
	var xp_amt: int = int(spec.get("xp", 28))
	var rev: float = float(spec.get("reveal_cells", 16.0))
	_award_wonder_xp(_bell_node.spire_pos, xp_amt, rev)
	if multiplayer.get_peers().is_empty():
		_rpc_bell_awakened(peer_id)
	else:
		_rpc_bell_awakened.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_bell_awakened(peer_id: int) -> void:
	_bell_awake = true
	if _bell_node != null and is_instance_valid(_bell_node):
		_bell_node.play_awaken_fx()
	if multiplayer.get_unique_id() == peer_id:
		var spec: Dictionary = DataRegistry.table("meadow_wonders").get("bell_pond", {}) as Dictionary
		_show_banner("WELTWUNDER ERWACHT", String(spec.get("name", "DER GLOCKENTEICH")), String(spec.get("sub", "")), Color("1d4a58"))


# ---------------------------------------------------------------- 2. Sleeping Guardians

func request_pick_headstone() -> void:
	if multiplayer.is_server():
		_host_pick_headstone(multiplayer.get_unique_id())
	else:
		_rpc_req_pick_head.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_pick_head() -> void:
	if multiplayer.is_server():
		_host_pick_headstone(multiplayer.get_remote_sender_id())


func _host_pick_headstone(peer_id: int) -> void:
	if not multiplayer.is_server() or _guardians_awake or _guardians_head_restored or _guardians_carrier != 0 or _guardians_node == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0 or who.carry_stone != 0:
		return
	var hs_world: Vector2 = _guardians_node.global_position + _guardians_head_local
	if who.global_position.distance_to(hs_world) > 56.0:
		return
	_guardians_carrier = peer_id
	if multiplayer.get_peers().is_empty():
		_rpc_headstone_carrier(peer_id, _guardians_head_local)
	else:
		_rpc_headstone_carrier.rpc(peer_id, _guardians_head_local)


func request_drop_headstone(local_pt: Vector2) -> void:
	if multiplayer.is_server():
		_host_drop_headstone(multiplayer.get_unique_id(), local_pt)
	else:
		_rpc_req_drop_head.rpc_id(1, local_pt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_drop_head(local_pt: Vector2) -> void:
	if multiplayer.is_server():
		_host_drop_headstone(multiplayer.get_remote_sender_id(), local_pt)


func _host_drop_headstone(peer_id: int, local_pt: Vector2) -> void:
	if not multiplayer.is_server() or _guardians_carrier != peer_id:
		return
	host_force_drop_headstone(local_pt.round())


func host_force_drop_headstone(local_pt: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_guardians_carrier = 0
	_guardians_head_local = local_pt
	if multiplayer.get_peers().is_empty():
		_rpc_headstone_carrier(0, _guardians_head_local)
	else:
		_rpc_headstone_carrier.rpc(0, _guardians_head_local)


@rpc("authority", "call_local", "reliable")
func _rpc_headstone_carrier(peer_id: int, local_pt: Vector2) -> void:
	_guardians_carrier = peer_id
	_guardians_head_local = local_pt
	if _guardians_node != null and is_instance_valid(_guardians_node):
		_guardians_node.apply_headstone_carrier(peer_id, local_pt)


func request_restore_guardian_head() -> void:
	if multiplayer.is_server():
		_host_restore_guardian_head(multiplayer.get_unique_id())
	else:
		_rpc_req_restore_head.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_restore_head() -> void:
	if multiplayer.is_server():
		_host_restore_guardian_head(multiplayer.get_remote_sender_id())


func _host_restore_guardian_head(peer_id: int) -> void:
	if not multiplayer.is_server() or _guardians_awake or _guardians_carrier != peer_id or _guardians_node == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	var socket_world: Vector2 = _guardians_node.global_position + _guardians_node.guardian_local_pos(SleepingGuardians.BROKEN_INDEX) + Vector2(0.0, 12.0)
	if who.global_position.distance_to(socket_world) > 64.0:
		return
	_finish_guardians_awakening(peer_id, true)


func request_light_guardian_brazier(idx: int) -> void:
	if multiplayer.is_server():
		_host_light_brazier(multiplayer.get_unique_id(), idx)
	else:
		_rpc_req_brazier.rpc_id(1, idx)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_brazier(idx: int) -> void:
	if multiplayer.is_server():
		_host_light_brazier(multiplayer.get_remote_sender_id(), idx)


func _host_light_brazier(peer_id: int, idx: int) -> void:
	if not multiplayer.is_server() or _guardians_awake or _guardians_node == null:
		return
	if idx < 0 or idx >= SleepingGuardians.GUARDIAN_COUNT:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	var brz_world: Vector2 = _guardians_node.global_position + _guardians_node.brazier_local_pos(idx)
	if who.global_position.distance_to(brz_world) > 54.0:
		return
	if idx == _guardians_lit_step:
		_guardians_lit_step += 1
		if _guardians_lit_step >= SleepingGuardians.GUARDIAN_COUNT:
			_finish_guardians_awakening(peer_id, false)
		else:
			if multiplayer.get_peers().is_empty():
				_rpc_brazier_step(_guardians_lit_step, false)
			else:
				_rpc_brazier_step.rpc(_guardians_lit_step, false)
	else:
		_guardians_lit_step = 0
		if multiplayer.get_peers().is_empty():
			_rpc_brazier_step(0, true)
		else:
			_rpc_brazier_step.rpc(0, true)


@rpc("authority", "call_local", "reliable")
func _rpc_brazier_step(step_val: int, reset_puff: bool) -> void:
	_guardians_lit_step = step_val
	if _guardians_node != null and is_instance_valid(_guardians_node):
		_guardians_node.apply_brazier_step(step_val, reset_puff)


func _finish_guardians_awakening(peer_id: int, restored_head: bool) -> void:
	_guardians_awake = true
	_guardians_head_restored = _guardians_head_restored or restored_head
	_guardians_lit_step = SleepingGuardians.GUARDIAN_COUNT
	_guardians_carrier = 0
	var spec: Dictionary = DataRegistry.table("meadow_wonders").get("sleeping_guardians", {}) as Dictionary
	var xp_amt: int = int(spec.get("xp", 32))
	var rev: float = float(spec.get("reveal_cells", 18.0))
	if _guardians_node != null:
		_award_wonder_xp(_guardians_node.global_position, xp_amt, rev)
	if multiplayer.get_peers().is_empty():
		_rpc_guardians_awakened(peer_id, _guardians_head_restored)
	else:
		_rpc_guardians_awakened.rpc(peer_id, _guardians_head_restored)


@rpc("authority", "call_local", "reliable")
func _rpc_guardians_awakened(peer_id: int, restored_head: bool) -> void:
	_guardians_awake = true
	_guardians_head_restored = restored_head
	_guardians_lit_step = SleepingGuardians.GUARDIAN_COUNT
	_guardians_carrier = 0
	if _guardians_node != null and is_instance_valid(_guardians_node):
		_guardians_node.play_awaken_fx(restored_head)
	if multiplayer.get_unique_id() == peer_id:
		var spec: Dictionary = DataRegistry.table("meadow_wonders").get("sleeping_guardians", {}) as Dictionary
		_show_banner("WELTWUNDER ERWACHT", String(spec.get("name", "KREIS DER SCHLAFENDEN WÄCHTER")), String(spec.get("sub", "")), Color("284c4a"))


# ---------------------------------------------------------------- 3. Flower Amphitheater

func request_awaken_amphitheater() -> void:
	if multiplayer.is_server():
		_host_awaken_amphitheater(multiplayer.get_unique_id())
	else:
		_rpc_req_amphitheater.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_amphitheater() -> void:
	if multiplayer.is_server():
		_host_awaken_amphitheater(multiplayer.get_remote_sender_id())


func _host_awaken_amphitheater(peer_id: int) -> void:
	if not multiplayer.is_server() or _amphitheater_awake or _amphitheater_node == null:
		return
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health.current <= 0.0:
		return
	if who.global_position.distance_to(_amphitheater_node.global_position) > 82.0:
		return
	_amphitheater_awake = true
	var spec: Dictionary = DataRegistry.table("meadow_wonders").get("flower_amphitheater", {}) as Dictionary
	var xp_amt: int = int(spec.get("xp", 24))
	var rev: float = float(spec.get("reveal_cells", 15.0))
	_award_wonder_xp(_amphitheater_node.global_position, xp_amt, rev)
	if multiplayer.get_peers().is_empty():
		_rpc_amphitheater_awakened(peer_id)
	else:
		_rpc_amphitheater_awakened.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_amphitheater_awakened(peer_id: int) -> void:
	_amphitheater_awake = true
	if _amphitheater_node != null and is_instance_valid(_amphitheater_node):
		_amphitheater_node.play_awaken_fx()
	if multiplayer.get_unique_id() == peer_id:
		var spec: Dictionary = DataRegistry.table("meadow_wonders").get("flower_amphitheater", {}) as Dictionary
		_show_banner("WELTWUNDER ERWACHT", String(spec.get("name", "DAS BLUMEN-AMPHITHEATER")), String(spec.get("sub", "")), Color("3a2b5c"))


# ---------------------------------------------------------------- Rewards, Sync & Save

func _award_wonder_xp(origin: Vector2, xp_amt: int, reveal_cells: float) -> void:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.health.current > 0.0 and p.global_position.distance_to(origin) <= 280.0 and p.progress != null:
			p.progress.award(0, xp_amt)
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(origin / 16.0, reveal_cells)


@rpc("authority", "reliable")
func _rpc_snapshot(
	bell: bool,
	guard_awake: bool,
	guard_head: bool,
	guard_step: int,
	guard_carrier: int,
	guard_head_loc: Vector2,
	amp_awake: bool
) -> void:
	_bell_awake = bell
	_guardians_awake = guard_awake
	_guardians_head_restored = guard_head
	_guardians_lit_step = guard_step
	_guardians_carrier = guard_carrier
	_guardians_head_local = guard_head_loc
	_amphitheater_awake = amp_awake
	_refresh_live_nodes()


func export_state() -> Dictionary:
	return {
		"bell": _bell_awake,
		"guardians": _guardians_awake,
		"guardians_head": _guardians_head_restored,
		"amphitheater": _amphitheater_awake,
	}


func import_state(saved: Variant) -> void:
	_bell_awake = false
	_guardians_awake = false
	_guardians_head_restored = false
	_guardians_lit_step = 0
	_guardians_carrier = 0
	_amphitheater_awake = false
	if saved is Dictionary:
		var d: Dictionary = saved as Dictionary
		_bell_awake = bool(d.get("bell", false))
		_guardians_awake = bool(d.get("guardians", false))
		_guardians_head_restored = bool(d.get("guardians_head", false))
		_amphitheater_awake = bool(d.get("amphitheater", false))
		if _guardians_awake:
			_guardians_lit_step = SleepingGuardians.GUARDIAN_COUNT
	_refresh_live_nodes()
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(
			_bell_awake,
			_guardians_awake,
			_guardians_head_restored,
			_guardians_lit_step,
			_guardians_carrier,
			_guardians_head_local,
			_amphitheater_awake
		)


func _refresh_live_nodes() -> void:
	if _bell_node != null and is_instance_valid(_bell_node):
		_bell_node.set_awakened_instant(_bell_awake)
	if _guardians_node != null and is_instance_valid(_guardians_node):
		_guardians_node.lit_step = _guardians_lit_step
		_guardians_node.set_state_instant(_guardians_awake, _guardians_head_restored)
		if not _guardians_awake:
			_guardians_node.apply_headstone_carrier(_guardians_carrier, _guardians_head_local)
	if _amphitheater_node != null and is_instance_valid(_amphitheater_node):
		_amphitheater_node.set_awakened_instant(_amphitheater_awake)


func _show_banner(hdr: String, title_str: String, sub_str: String, col: Color) -> void:
	if _banner == null:
		_banner = TownBanner.new()
		add_child(_banner)
	_banner.show_banner({
		"header": hdr,
		"title": title_str,
		"sub": sub_str,
		"color": col,
		"emblem": -1,
	})


func _player_by_peer(peer_id: int) -> Player:
	for p: Player in Player.all:
		if p.name.to_int() == peer_id:
			return p
	return null
