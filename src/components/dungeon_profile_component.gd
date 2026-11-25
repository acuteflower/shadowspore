class_name DungeonProfileComponent
extends Node
## Per-player portable dungeon progress: Veil Resonance (4 charges, 06:00/18:00 UTC +2 refresh,
## Rest Bonus overflow), discovered gates, clear counts, best-time & combat records, and
## Echo Shard balance + weekly Echo Exchange limits (docs/dungeon_konzept.md).
## Host holds truth and replicates updates to the owning peer.

signal changed()
signal exchange_result(ok: bool, message: String, item_id: String, count: int)

var resonance: Dictionary = {} ## ResonanceRules state
var discovered: Dictionary = {} ## dungeon_id -> true
var cleared: Dictionary = {} ## dungeon_id -> int (clear count)
var records: Dictionary = {} ## dungeon_id -> {best_sec, clears, best_counters, best_staggers, best_damage, min_hits}
var prefer_resonance: bool = true ## player's toggle in DungeonWindow / ReadyBanner

var _synced: bool = false


func _ready() -> void:
	var now_u: int = _now_unix()
	if resonance.is_empty():
		resonance = ResonanceRules.fresh_state(now_u)
	if not multiplayer.is_server() and is_multiplayer_authority() and NetworkManager.rpc_ready(self):
		_rpc_request_state.rpc_id(1)


static func _now_unix() -> int:
	if CloudSession != null and CloudSession.has_method("server_unix_time"):
		return int(CloudSession.call("server_unix_time"))
	return int(Time.get_unix_time_from_system())


## Refreshes resonance charges & weekly echo state against current time.
func refresh_clock(now_override: int = -1) -> Dictionary:
	var now_u: int = now_override if now_override > 0 else _now_unix()
	resonance = ResonanceRules.sync_state(resonance, now_u)
	return resonance


func charges() -> int:
	refresh_clock()
	return int(resonance.get("charges", 0))


func rest_units() -> int:
	refresh_clock()
	return int(resonance.get("rest_units", 0))


func echo_shards() -> int:
	refresh_clock()
	return int(resonance.get("echo_shards", 0))


func echo_week_earned() -> int:
	refresh_clock()
	return int(resonance.get("echo_week_earned", 0))


func is_discovered(dungeon_id: String) -> bool:
	return bool(discovered.get(dungeon_id, false))


func clear_count(dungeon_id: String) -> int:
	return int(cleared.get(dungeon_id, 0))


func record_for(dungeon_id: String) -> Dictionary:
	var raw: Variant = records.get(dungeon_id, {})
	return raw as Dictionary if raw is Dictionary else {}


## Host-only: marks a physical dungeon gate as discovered by this player.
func mark_discovered(dungeon_id: String) -> void:
	if not multiplayer.is_server() or dungeon_id.is_empty():
		return
	if bool(discovered.get(dungeon_id, false)):
		return
	discovered[dungeon_id] = true
	_push_state()


## Client or host: asks the host to mark a dungeon gate discovered (e.g. approaching its entrance).
func request_discover(dungeon_id: String) -> void:
	if dungeon_id.is_empty():
		return
	if multiplayer.is_server():
		mark_discovered(dungeon_id)
	elif is_multiplayer_authority() and NetworkManager.rpc_ready(self):
		_rpc_discover.rpc_id(1, dungeon_id)


## Host-only: finalizes a dungeon victory for this player (consumes resonance only on victory,
## grants echo shards under weekly cap, records clear & best time, pushes state to owner).
func apply_victory(dungeon_id: String, use_resonance: bool, clear_sec: float, counters: int, staggers: int, damage: float, hits_taken: int, echo_amount: int, now_override: int = -1) -> Dictionary:
	if not multiplayer.is_server():
		return {}
	var now_u: int = now_override if now_override > 0 else _now_unix()
	var was_first: bool = int(cleared.get(dungeon_id, 0)) <= 0
	var cons: Dictionary = ResonanceRules.consume_for_victory(resonance, now_u, use_resonance)
	resonance = cons["state"] as Dictionary
	var echo_res: Dictionary = ResonanceRules.grant_echo_shards(resonance, now_u, echo_amount)
	resonance = echo_res["state"] as Dictionary
	discovered[dungeon_id] = true
	cleared[dungeon_id] = int(cleared.get(dungeon_id, 0)) + 1
	var rec_res: Dictionary = DungeonRules.record_victory(records, dungeon_id, clear_sec, counters, staggers, damage, hits_taken)
	records = rec_res["records"] as Dictionary
	_push_state()
	return {
		"first_clear": was_first,
		"consumed_resonance": bool(cons["consumed_resonance"]),
		"consumed_rest_double": bool(cons["consumed_rest_double"]),
		"echo_granted": int(echo_res["granted"]),
		"echo_capped": bool(echo_res["capped"]),
		"new_best_time": bool(rec_res["new_best_time"]),
	}


## Host or client: buys an Echo Exchange offer directly from the Steinsetzer-Prüfungstafel.
func request_exchange(offer_id: String) -> void:
	if offer_id.is_empty():
		return
	if multiplayer.is_server():
		_host_exchange(offer_id)
	elif is_multiplayer_authority() and NetworkManager.rpc_ready(self):
		_rpc_exchange.rpc_id(1, offer_id)


func _host_exchange(offer_id: String, now_override: int = -1) -> void:
	var offer: Dictionary = DungeonRules.exchange_by_id(offer_id)
	var now_u: int = now_override if now_override > 0 else _now_unix()
	var res: Dictionary = ResonanceRules.purchase_exchange(resonance, now_u, offer, cleared)
	if not bool(res.get("ok", false)):
		_send_exchange_result(false, String(res.get("reason", "FEHLGESCHLAGEN")), "", 0)
		return
	var owner_node: Node = get_parent()
	var item_id: String = String(res.get("item_id", ""))
	var cnt: int = int(res.get("count", 1))
	if owner_node != null:
		var inv: InventoryComponent = owner_node.get_node_or_null("InventoryComponent") as InventoryComponent
		if inv != null:
			if not inv.has_room(item_id):
				_send_exchange_result(false, "INVENTAR VOLL", "", 0)
				return
			var leftover: int = inv.give(item_id, cnt)
			if leftover > 0:
				## Bag could not fit full stack: roll back added part cleanly
				if leftover < cnt:
					inv.remove_item(item_id, cnt - leftover)
				_send_exchange_result(false, "INVENTAR VOLL", "", 0)
				return
	resonance = res["state"] as Dictionary
	_push_state()
	_send_exchange_result(true, "GETAUSCHT!", item_id, cnt)


func _send_exchange_result(ok: bool, msg: String, item_id: String, count: int) -> void:
	var owner_id: int = get_multiplayer_authority()
	if owner_id == multiplayer.get_unique_id():
		exchange_result.emit(ok, msg, item_id, count)
	elif NetworkManager.rpc_ready(self):
		_rpc_exchange_result.rpc_id(owner_id, ok, msg, item_id, count)


## Host-only dev helper: grants charges or echo shards for testing.
func debug_refill(add_charges: int = 4, add_rest: int = 0, add_echo: int = 0) -> void:
	if not multiplayer.is_server():
		return
	refresh_clock()
	resonance["charges"] = clampi(int(resonance.get("charges", 0)) + add_charges, 0, ResonanceRules.max_charges())
	resonance["rest_units"] = clampi(int(resonance.get("rest_units", 0)) + add_rest, 0, ResonanceRules.rest_max_units())
	resonance["echo_shards"] = maxi(int(resonance.get("echo_shards", 0)) + add_echo, 0)
	_push_state()


func export_data() -> Dictionary:
	refresh_clock()
	return {
		"resonance": resonance.duplicate(true),
		"discovered": discovered.duplicate(true),
		"cleared": cleared.duplicate(true),
		"records": records.duplicate(true),
		"prefer_resonance": prefer_resonance,
	}


func import_data(raw: Dictionary) -> void:
	var now_u: int = _now_unix()
	if raw.is_empty():
		resonance = ResonanceRules.fresh_state(now_u)
		discovered = {}
		cleared = {}
		records = {}
		prefer_resonance = true
	else:
		var r_raw: Variant = raw.get("resonance", {})
		resonance = ResonanceRules.sync_state(r_raw as Dictionary if r_raw is Dictionary else {}, now_u)
		var d_raw: Variant = raw.get("discovered", {})
		discovered = (d_raw as Dictionary).duplicate(true) if d_raw is Dictionary else {}
		var c_raw: Variant = raw.get("cleared", {})
		cleared = {}
		if c_raw is Dictionary:
			for k: Variant in (c_raw as Dictionary):
				cleared[String(k)] = int((c_raw as Dictionary)[k])
		var rec_raw: Variant = raw.get("records", {})
		records = (rec_raw as Dictionary).duplicate(true) if rec_raw is Dictionary else {}
		prefer_resonance = bool(raw.get("prefer_resonance", true))
	changed.emit()
	if multiplayer.is_server():
		_push_state()


func _push_state() -> void:
	changed.emit()
	var owner_id: int = get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id() and NetworkManager.rpc_ready(self):
		_rpc_state.rpc_id(owner_id, export_data())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_push_state()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_discover(dungeon_id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		mark_discovered(dungeon_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_exchange(offer_id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_host_exchange(offer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_state(data: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var now_u: int = _now_unix()
	var r_raw: Variant = data.get("resonance", {})
	resonance = ResonanceRules.sync_state(r_raw as Dictionary if r_raw is Dictionary else {}, now_u)
	var d_raw: Variant = data.get("discovered", {})
	discovered = (d_raw as Dictionary).duplicate(true) if d_raw is Dictionary else {}
	var c_raw: Variant = data.get("cleared", {})
	cleared = (c_raw as Dictionary).duplicate(true) if c_raw is Dictionary else {}
	var rec_raw: Variant = data.get("records", {})
	records = (rec_raw as Dictionary).duplicate(true) if rec_raw is Dictionary else {}
	prefer_resonance = bool(data.get("prefer_resonance", true))
	_synced = true
	changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_exchange_result(ok: bool, msg: String, item_id: String, count: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	exchange_result.emit(ok, msg, item_id, count)
