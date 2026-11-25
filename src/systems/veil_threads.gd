class_name VeilThreads
extends Node
## Global coop-shared Schattenfrucht registry, stage spawner, Sporen-Schwellen milestone rewards,
## zone blessings, and SporeBed daily gift manager (`docs/schattenfruechte_und_menue_konzept.md` §1).
## Keeps class/group/save key `veil_threads` for 100% save & Atlas compatibility.

signal thread_collected(id: String, zone_id: StringName, peer_id: int)
signal milestone_claimed(milestone_id: String)
signal bed_gift_harvested(day: int, peer_id: int)
signal changed

const REACH_MAX_PX: float = 82.0
const REVEAL_TILES: float = 12.0
const BASE_XP_REWARD: int = 15

var _atlas: Atlas = null
var _director: ZoneDirector = null
var _specs: Dictionary = {} ## String id -> Dictionary {id, zone, tile, local_tile, place, trait, hint}
var _by_zone: Dictionary = {} ## StringName zone_id -> Array[String]
var _collected: Dictionary = {} ## String id -> true
var _claimed_milestones: Dictionary = {} ## String milestone_id -> true
var _endless_claimed: int = 0
var _bed_gift_day: int = -1
var _pickups: Dictionary = {} ## String id -> VeilThreadPickup


static func of(tree: SceneTree) -> VeilThreads:
	if tree == null:
		return null
	return tree.get_first_node_in_group("veil_threads") as VeilThreads


static func _cfg() -> Dictionary:
	return DataRegistry.table("shadow_fruits")


func _ready() -> void:
	add_to_group("veil_threads")
	_load_specs_from_atlas(Atlas.shared())
	_try_attach_director()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)


func _process(_delta: float) -> void:
	if _director == null or not is_instance_valid(_director):
		_try_attach_director()
	else:
		set_process(false)


func _on_peer_connected(peer: int) -> void:
	if not NetworkManager.rpc_ready(self):
		return
	_rpc_snapshot_v2.rpc_id(peer, _pack_snapshot())


func _load_specs_from_atlas(atlas: Atlas) -> void:
	_atlas = atlas
	_specs.clear()
	_by_zone.clear()
	if _atlas == null:
		return
	for z_val: Variant in _atlas.zones.values():
		var z: Atlas.Zone = z_val as Atlas.Zone
		if z == null:
			continue
		var raw_threads: Variant = z.raw.get("veil_threads", [])
		if not (raw_threads is Array):
			continue
		var z_ids: Array[String] = []
		for item: Variant in raw_threads as Array:
			if not (item is Dictionary):
				continue
			var d: Dictionary = item as Dictionary
			var tid: String = String(d.get("id", "")).strip_edges()
			var t_arr: Variant = d.get("tile")
			if tid.is_empty() or not (t_arr is Array) or (t_arr as Array).size() < 2:
				continue
			var pair: Array = t_arr as Array
			var local_tile: Vector2 = Vector2(float(pair[0]), float(pair[1]))
			var world_tile: Vector2 = local_tile
			if not z.bbox.grow(2.0).has_point(world_tile):
				world_tile = Vector2(z.origin) + local_tile
			var tr: String = String(d.get("trait", "calm")).strip_edges()
			if tr.is_empty():
				tr = "calm"
			var spec: Dictionary = {
				"id": tid,
				"zone": z.id,
				"tile": world_tile,
				"local_tile": local_tile,
				"place": StringName(String(d.get("place", ""))),
				"trait": tr,
				"hint": String(d.get("hint", "")),
			}
			_specs[tid] = spec
			z_ids.append(tid)
		if not z_ids.is_empty():
			_by_zone[z.id] = z_ids


func _try_attach_director() -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	var dir: ZoneDirector = tree.get_first_node_in_group("zone_director") as ZoneDirector
	if dir == null and get_parent() != null:
		for child: Node in get_parent().get_children():
			if child is ZoneDirector:
				dir = child as ZoneDirector
				break
	if dir == null:
		var world: Node = tree.get_first_node_in_group("world")
		if world != null and world.has_method("director"):
			var cand: Variant = world.call("director")
			if cand is ZoneDirector:
				dir = cand as ZoneDirector
	if dir == null:
		return
	_director = dir
	if _director.atlas != null and _director.atlas != _atlas:
		_load_specs_from_atlas(_director.atlas)
	if not _director.stage_attached.is_connected(_on_stage_attached):
		_director.stage_attached.connect(_on_stage_attached)
	if not _director.stage_detached.is_connected(_on_stage_detached):
		_director.stage_detached.connect(_on_stage_detached)
	for zid_v: Variant in _director.stages.keys():
		var zid: StringName = zid_v as StringName
		if zid != &"":
			_populate_stage(zid)
	set_process(false)


func _on_stage_attached(zone_id: StringName) -> void:
	_populate_stage(zone_id)


func _on_stage_detached(zone_id: StringName) -> void:
	if not _by_zone.has(zone_id):
		return
	for tid: String in _by_zone[zone_id] as Array[String]:
		_pickups.erase(tid)


func _populate_stage(zone_id: StringName) -> void:
	if _director == null or not _by_zone.has(zone_id):
		return
	var stage: ZoneStage = _director.stage(zone_id)
	if stage == null or not is_instance_valid(stage):
		return
	for tid: String in _by_zone[zone_id] as Array[String]:
		if _collected.has(tid):
			continue
		var existing: VeilThreadPickup = _pickups.get(tid) as VeilThreadPickup
		if existing != null and is_instance_valid(existing):
			continue
		var spec: Dictionary = _specs[tid] as Dictionary
		var pickup: VeilThreadPickup = VeilThreadPickup.new()
		pickup.name = "VeilThread_" + tid
		pickup.thread_id = tid
		pickup.zone_id = zone_id
		pickup.place_id = spec["place"] as StringName
		pickup.trait_kind = String(spec.get("trait", "calm"))
		pickup.hint_text = String(spec["hint"])
		var world_tile: Vector2 = spec["tile"] as Vector2
		pickup.position = Atlas.px_of(world_tile) + Vector2(8.0, 8.0)
		stage.add_child(pickup)
		_pickups[tid] = pickup


# --- queries & progress ----------------------------------------------------------------------------------------------

func is_collected(id: String) -> bool:
	return _collected.has(id)


func collected_ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in _collected.keys():
		out.append(String(k))
	out.sort()
	return out


func collected_count() -> int:
	return _collected.size()


func total_count() -> int:
	return _specs.size()


func zones_with_fruits() -> Array[StringName]:
	var out: Array[StringName] = []
	for zid_v: Variant in _by_zone.keys():
		out.append(zid_v as StringName)
	return out


func collected_in_zone(zone_id: StringName) -> int:
	if not _by_zone.has(zone_id):
		return 0
	var n: int = 0
	for tid: String in _by_zone[zone_id] as Array[String]:
		if _collected.has(tid):
			n += 1
	return n


func total_in_zone(zone_id: StringName) -> int:
	if not _by_zone.has(zone_id):
		return 0
	return (_by_zone[zone_id] as Array[String]).size()


func entries_for_zone(zone_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _by_zone.has(zone_id):
		return out
	for tid: String in _by_zone[zone_id] as Array[String]:
		var spec: Dictionary = (_specs[tid] as Dictionary).duplicate()
		spec["collected"] = _collected.has(tid)
		out.append(spec)
	return out


func family_counts() -> Dictionary:
	var counts: Dictionary = {"teal": 0, "violet": 0, "magenta": 0, "mint": 0, "indigo": 0}
	for tid_v: Variant in _collected.keys():
		var traits: Dictionary = ShadowFruitArt.traits_for(String(tid_v))
		var fid: String = ShadowFruitArt.family_id(int(traits["accent_idx"]))
		counts[fid] = int(counts.get(fid, 0)) + 1
	return counts


## Combined Atlas veil density (0..1) from collected Schattenfrüchte + awakened Waystones.
func veil_progress_ratio() -> float:
	var t_total: int = maxi(_specs.size(), 1)
	var t_done: int = _collected.size()
	var ws_bonus: float = 0.0
	if is_inside_tree():
		var ws: Waystones = Waystones.of(get_tree())
		if ws != null and ws.awake_count() > 0:
			ws_bonus = minf(float(ws.awake_count()) * 0.22, 0.28)
	var thread_part: float = (float(t_done) / float(t_total)) * 0.78
	var base: float = 0.06 if (t_done > 0 or ws_bonus > 0.0) else 0.0
	return clampf(base + thread_part + ws_bonus, 0.0, 1.0)


# --- milestones, gameplay bonuses & zone blessings -------------------------------------------------------------------

func milestones_status() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cfg: Dictionary = _cfg()
	var raw_list: Variant = cfg.get("milestones", [])
	var done_n: int = _collected.size()
	if raw_list is Array:
		for item: Variant in raw_list as Array:
			if not (item is Dictionary):
				continue
			var m: Dictionary = (item as Dictionary).duplicate()
			var mid: String = String(m.get("id", ""))
			var req: int = int(m.get("count", 0))
			m["reached"] = done_n >= req
			m["claimed"] = _claimed_milestones.has(mid)
			out.append(m)
	return out


func next_endless_threshold() -> int:
	var step: int = maxi(int(_cfg().get("endless_step", 25)), 5)
	return 100 + (_endless_claimed + 1) * step


func endless_claim_ready() -> bool:
	return _claimed_milestones.has("spore_keeper") and _collected.size() >= next_endless_threshold()


func has_unclaimed_milestone() -> bool:
	for m: Dictionary in milestones_status():
		if bool(m.get("reached", false)) and not bool(m.get("claimed", false)):
			return true
	return endless_claim_ready()


func bag_bonus_slots() -> int:
	var total: int = 0
	for m: Dictionary in milestones_status():
		if bool(m.get("claimed", false)) and String(m.get("effect", "")) == "bag_slots":
			total += int(m.get("value", 0))
	return mini(total, 16)


func stamina_max_bonus() -> float:
	var total: float = 0.0
	for m: Dictionary in milestones_status():
		if not bool(m.get("claimed", false)):
			continue
		var eff: String = String(m.get("effect", ""))
		if eff == "stamina" or eff == "stamina_reveal":
			total += float(m.get("value", 0.0))
	return total


func stamina_regen_bonus() -> float:
	var bonus: float = 0.0
	if _claimed_milestones.has("stamina_1"):
		bonus += 0.08
	if _claimed_milestones.has("stamina_2"):
		bonus += 0.06
	return bonus


func night_light_bonus() -> float:
	return 0.22 if _claimed_milestones.has("lantern_1") else 0.0


func stealth_spook_scale() -> float:
	return 0.70 if _claimed_milestones.has("moss_step") else 1.0


func harvest_double_chance() -> float:
	return 0.15 if _claimed_milestones.has("harvest_1") else 0.0


func step_cooldown_scale() -> float:
	return 0.88 if _claimed_milestones.has("step_echo") else 1.0


func reveal_radius_scale() -> float:
	return 1.15 if _claimed_milestones.has("stamina_2") else 1.0


func has_spore_keeper() -> bool:
	return _claimed_milestones.has("spore_keeper")


func zone_blessing_status(zone_id: StringName) -> Dictionary:
	var cfg: Dictionary = _cfg()
	var table: Dictionary = cfg.get("zone_blessings", {}) as Dictionary if cfg.get("zone_blessings") is Dictionary else {}
	var zkey: String = String(zone_id)
	var b: Dictionary = table.get(zkey, table.get("default", {})) as Dictionary
	var done: int = collected_in_zone(zone_id)
	var tot: int = total_in_zone(zone_id)
	var ratio: float = float(done) / float(maxi(tot, 1)) if tot > 0 else 0.0
	return {
		"done": done,
		"total": tot,
		"half_unlocked": tot > 0 and ratio >= 0.5,
		"full_unlocked": tot > 0 and done >= tot,
		"half_name": String(b.get("half_name", "ERWACHTER BODEN")),
		"half_desc": String(b.get("half_desc", "Reichere Wildflora & ruhigere Nächte")),
		"full_name": String(b.get("full_name", "GEHEILTER BODEN")),
		"full_desc": String(b.get("full_desc", "+6 % Lauftempo & reiche Ausbeute")),
		"speed_bonus": float(b.get("speed_bonus", 0.06)) if (tot > 0 and done >= tot) else 0.0,
	}


func bed_gift_ready() -> bool:
	var bed_cfg: Dictionary = _cfg().get("spore_bed", {}) as Dictionary if _cfg().get("spore_bed") is Dictionary else {}
	var min_n: int = int(bed_cfg.get("daily_gift_min_fruits", 5))
	return _collected.size() >= min_n and TimeManager.day > _bed_gift_day


func apply_bonuses_to_player(player: Player) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.inventory != null and player.inventory.has_method("set_bonus_slots"):
		player.inventory.set_bonus_slots(bag_bonus_slots())
	if player.stamina != null and player.stamina.has_method("set_spore_bonus"):
		player.stamina.set_spore_bonus(stamina_max_bonus(), stamina_regen_bonus())
	if player.has_method("set_spore_lantern"):
		player.call("set_spore_lantern", night_light_bonus())


func _apply_bonuses_to_all_players() -> void:
	for p: Player in Player.all:
		apply_bonuses_to_player(p)


# --- collection & milestone claims (host-authoritative) --------------------------------------------------------------

func request_collect(id: String) -> void:
	if id.is_empty():
		return
	if multiplayer.is_server():
		_host_collect(id, multiplayer.get_unique_id())
	elif NetworkManager.rpc_ready(self):
		_rpc_request_collect.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_collect(id: String) -> void:
	if multiplayer.is_server():
		_host_collect(id, multiplayer.get_remote_sender_id())


func _host_collect(id: String, peer: int) -> void:
	if not _specs.has(id) or _collected.has(id):
		return
	var spec: Dictionary = _specs[id] as Dictionary
	var world_pos: Vector2 = Atlas.px_of(spec["tile"] as Vector2) + Vector2(8.0, 8.0)
	var collector: Player = null
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer:
			collector = p
			break
	if collector == null or collector.health == null or collector.health.current <= 0.0:
		return
	if collector.global_position.distance_to(world_pos) > REACH_MAX_PX:
		return

	_collected[id] = true
	var trait_k: String = String(spec.get("trait", "calm"))
	var beh: Dictionary = _cfg().get("behaviors", {}) as Dictionary if _cfg().get("behaviors") is Dictionary else {}
	var xp_map: Dictionary = beh.get("xp_by_trait", {}) as Dictionary if beh.get("xp_by_trait") is Dictionary else {}
	var xp: int = int(xp_map.get(trait_k, BASE_XP_REWARD))
	if xp > 0:
		for p: Player in Player.all:
			if is_instance_valid(p) and p.health != null and p.health.current > 0.0 and p.progress != null:
				p.progress.award(0, xp)
	# Stubborn deep-rooters also yield a luminous glimmer shard from the earth pit
	if trait_k == "stubborn" and collector.inventory != null:
		collector.inventory.give("glimmer", 1)
	if is_inside_tree():
		var disc: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
		if disc != null:
			disc.reveal_continent_disc(spec["tile"] as Vector2, REVEAL_TILES * reveal_radius_scale())
	if NetworkManager.rpc_ready(self):
		_rpc_collected.rpc(id, peer)
	else:
		_apply_collected_local(id, peer)
	CloudSession.mark_save_dirty()


@rpc("authority", "call_local", "reliable")
func _rpc_collected(id: String, peer: int) -> void:
	_apply_collected_local(id, peer)


func _apply_collected_local(id: String, peer: int) -> void:
	_collected[id] = true
	var pickup: VeilThreadPickup = _pickups.get(id) as VeilThreadPickup
	_pickups.erase(id)
	var collector: Player = null
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer:
			collector = p
			break
	if pickup != null and is_instance_valid(pickup):
		pickup.play_collect(collector)
	var zid: StringName = &""
	if _specs.has(id):
		zid = (_specs[id] as Dictionary)["zone"] as StringName
	thread_collected.emit(id, zid, peer)
	changed.emit()


func request_claim_milestone(milestone_id: String) -> void:
	if milestone_id.is_empty():
		return
	if multiplayer.is_server():
		_host_claim_milestone(milestone_id)
	elif NetworkManager.rpc_ready(self):
		_rpc_request_claim_milestone.rpc_id(1, milestone_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_claim_milestone(milestone_id: String) -> void:
	if multiplayer.is_server():
		_host_claim_milestone(milestone_id)


func _host_claim_milestone(milestone_id: String) -> void:
	if _claimed_milestones.has(milestone_id):
		return
	var found: Dictionary = {}
	for m: Dictionary in milestones_status():
		if String(m.get("id", "")) == milestone_id:
			found = m
			break
	if found.is_empty() or not bool(found.get("reached", false)):
		return
	_claimed_milestones[milestone_id] = true
	if NetworkManager.rpc_ready(self):
		_rpc_milestone_claimed.rpc(milestone_id)
	else:
		_apply_milestone_local(milestone_id)
	CloudSession.mark_save_dirty()


@rpc("authority", "call_local", "reliable")
func _rpc_milestone_claimed(milestone_id: String) -> void:
	_apply_milestone_local(milestone_id)


func _apply_milestone_local(milestone_id: String) -> void:
	_claimed_milestones[milestone_id] = true
	_apply_bonuses_to_all_players()
	milestone_claimed.emit(milestone_id)
	changed.emit()


func request_claim_endless() -> void:
	if multiplayer.is_server():
		_host_claim_endless()
	elif NetworkManager.rpc_ready(self):
		_rpc_request_claim_endless.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_claim_endless() -> void:
	if multiplayer.is_server():
		_host_claim_endless()


func _host_claim_endless() -> void:
	if not endless_claim_ready():
		return
	_endless_claimed += 1
	for p: Player in Player.all:
		if is_instance_valid(p) and p.inventory != null:
			p.inventory.give("glimmer", 4)
			p.inventory.give("moon_berry", 5)
	if NetworkManager.rpc_ready(self):
		_rpc_endless_synced.rpc(_endless_claimed)
	else:
		milestone_claimed.emit("endless_%d" % _endless_claimed)
		changed.emit()
	CloudSession.mark_save_dirty()


@rpc("authority", "call_local", "reliable")
func _rpc_endless_synced(n: int) -> void:
	_endless_claimed = n
	milestone_claimed.emit("endless_%d" % n)
	changed.emit()


func request_harvest_bed_gift() -> void:
	if multiplayer.is_server():
		_host_harvest_bed_gift(multiplayer.get_unique_id())
	elif NetworkManager.rpc_ready(self):
		_rpc_request_harvest_bed_gift.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_harvest_bed_gift() -> void:
	if multiplayer.is_server():
		_host_harvest_bed_gift(multiplayer.get_remote_sender_id())


func _host_harvest_bed_gift(peer: int) -> void:
	if not bed_gift_ready():
		return
	var day: int = TimeManager.day
	_bed_gift_day = day
	var bed_cfg: Dictionary = _cfg().get("spore_bed", {}) as Dictionary if _cfg().get("spore_bed") is Dictionary else {}
	var gifts: Array = bed_cfg.get("daily_gifts", []) as Array if bed_cfg.get("daily_gifts") is Array else []
	var mult: int = 2 if has_spore_keeper() else 1
	if not gifts.is_empty():
		var pick: Dictionary = gifts[absi(day) % gifts.size()] as Dictionary
		var item_id: String = String(pick.get("item", "glimmer"))
		var cnt: int = maxi(1, int(pick.get("count", 2))) * mult
		for p: Player in Player.all:
			if is_instance_valid(p) and p.inventory != null:
				p.inventory.give(item_id, cnt)
	if NetworkManager.rpc_ready(self):
		_rpc_bed_gift_harvested.rpc(day, peer)
	else:
		bed_gift_harvested.emit(day, peer)
		changed.emit()
	CloudSession.mark_save_dirty()


@rpc("authority", "call_local", "reliable")
func _rpc_bed_gift_harvested(day: int, peer: int) -> void:
	_bed_gift_day = day
	bed_gift_harvested.emit(day, peer)
	changed.emit()


# --- snapshot sync & save / load (v1 + v2 compatible) ----------------------------------------------------------------

func _pack_snapshot() -> Dictionary:
	return export_state()


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot_v2(data: Dictionary) -> void:
	_apply_snapshot_dict(data)


func _apply_snapshot_dict(data: Dictionary) -> void:
	_collected.clear()
	for item: Variant in SaveGame.as_array(data.get("collected")):
		var s: String = String(item).strip_edges()
		if not s.is_empty():
			_collected[s] = true
	_claimed_milestones.clear()
	for m: Variant in SaveGame.as_array(data.get("claimed_milestones")):
		var ms: String = String(m).strip_edges()
		if not ms.is_empty():
			_claimed_milestones[ms] = true
	_endless_claimed = maxi(0, int(data.get("endless_claimed", 0)))
	_bed_gift_day = int(data.get("bed_gift_day", -1))

	for tid: String in _collected:
		var pickup: VeilThreadPickup = _pickups.get(tid) as VeilThreadPickup
		if pickup != null and is_instance_valid(pickup):
			pickup.queue_free()
		_pickups.erase(tid)
	if _director != null:
		for zid_v: Variant in _director.stages.keys():
			_populate_stage(zid_v as StringName)
	_apply_bonuses_to_all_players()
	changed.emit()


func export_state() -> Dictionary:
	var arr: Array[String] = collected_ids()
	var m_arr: Array[String] = []
	for k: Variant in _claimed_milestones.keys():
		m_arr.append(String(k))
	m_arr.sort()
	return {
		"version": 2,
		"collected": arr,
		"claimed_milestones": m_arr,
		"endless_claimed": _endless_claimed,
		"bed_gift_day": _bed_gift_day,
	}


func import_state(data: Dictionary) -> void:
	_apply_snapshot_dict(data)
	if multiplayer.is_server() and NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_snapshot_v2.rpc(_pack_snapshot())
