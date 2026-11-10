class_name StatusEffects
extends Node
## The status effects of a player (child `Effects` of every `Player`, made in `Player._ready`). Definitions are data (`data/status_effects.json`: `name`, `seconds`,
## `tick`, `damage_ratio`, `min_damage`, `extinguish`). The first effect is **burn** (Mornath's third phase, the burning floor of the last judgement): every `tick` seconds it
## costs `damage_ratio` of the maximum health (at least `min_damage`, times the `scale` of whoever set it) without interrupting anything (`HealthComponent.take_tick`:
## no knock back, no grace period, no flinch). It lasts `seconds`; burning again refreshes the time (it never stacks); water puts it out, and being in water protects.
##
## Host authority: only the host applies, ticks and extinguishes (`apply`), and tells everybody with reliable RPCs; every peer then counts the time down by itself, so the flames
## on the body (`BurnFx`) and the tag in the HUD (`StatusTags`) need no further traffic. A death clears everything. New effect: an entry in the JSON, a case in `_fx` for its look.

signal changed
signal started(id: String)

var health: HealthComponent
var _effects: Dictionary = {} ## id -> {left, total, scale, acc, source}
var _fx: Dictionary = {} ## id -> the node that shows it on the body
var _wet_check: float = 0.0
var _wood_check: float = 0.0


func _ready() -> void:
	health = get_node_or_null("../HealthComponent") as HealthComponent
	if health != null:
		health.died.connect(clear_all)


## Host: `id` starts or is refreshed for `seconds` (0 = the definition's time). `scale` multiplies the damage (the boss's damage scale), `source` is the peer to credit.
func apply(id: String, seconds: float = 0.0, scale: float = 1.0, source: int = 0) -> void:
	if not multiplayer.is_server() or health == null or health.current <= 0.0 or definition(id).is_empty():
		return
	if _wet() and String(definition(id).get("extinguish", "")) == "water":
		return
	_rpc_apply.rpc(id, seconds if seconds > 0.0 else float(definition(id)["seconds"]), scale, source)


## Host: puts `id` out (or everything).
func clear(id: String) -> void:
	if multiplayer.is_server() and _effects.has(id):
		_rpc_clear.rpc(id)


func clear_all() -> void:
	for id: String in _effects.keys():
		_remove(id)
	changed.emit()


static func definition(id: String) -> Dictionary:
	return DataRegistry.get_entry("status_effects", id)


func has(id: String) -> bool:
	return _effects.has(id)


func left(id: String) -> float:
	return float((_effects[id] as Dictionary)["left"]) if _effects.has(id) else 0.0


func total(id: String) -> float:
	return float((_effects[id] as Dictionary)["total"]) if _effects.has(id) else 0.0


## The `scale` it was set with (for a potion: its tier), 0 when it is not on.
func scale_of(id: String) -> float:
	return float((_effects[id] as Dictionary)["scale"]) if _effects.has(id) else 0.0


func active() -> Array[String]:
	var out: Array[String] = []
	for id: String in _effects.keys():
		out.append(id)
	return out


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply(id: String, seconds: float, scale: float, source: int) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	var fresh: bool = not _effects.has(id)
	var entry: Dictionary = _effects.get(id, {"left": 0.0, "total": seconds, "scale": scale, "acc": 0.0, "source": source}) as Dictionary
	entry["left"] = maxf(float(entry["left"]), seconds)
	entry["total"] = maxf(float(entry["total"]), seconds)
	entry["scale"] = maxf(float(entry["scale"]), scale)
	entry["source"] = source if source != 0 else int(entry["source"])
	_effects[id] = entry
	if fresh:
		_show(id)
		started.emit(id)
	changed.emit()


@rpc("any_peer", "call_local", "reliable")
func _rpc_clear(id: String) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_remove(id)
	changed.emit()


## Host, once a second: the Hexenwald's mist keeps HALLUZINIERT on everybody in it who does not wear a piece with the perk `clear_sight`
## (docs/hexenwald_nebel_konzept.md). It is refreshed, never stacked, so it fades by itself a few seconds after she has left the wood.
func _breathe_mist() -> void:
	var player: Node2D = get_parent() as Node2D
	var def: Dictionary = definition("hallucinated")
	if player == null or def.is_empty():
		return
	var worn: Variant = player.get("talismans")
	if worn != null and (worn.get("perks") as Dictionary).has("clear_sight"):
		clear("hallucinated") ## put on: her head clears at once
	elif Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position):
		clear("hallucinated") ## under a roof (the witch's tower) there is no mist: nothing false follows her inside
	elif BiomeBlend.amount_at(player.global_position) > float(def.get("min_gloom", 0.35)):
		apply("hallucinated")


func _physics_process(delta: float) -> void:
	_wood_check -= delta
	if _wood_check <= 0.0 and multiplayer.is_server():
		_wood_check = 1.0
		_breathe_mist()
	if _effects.is_empty():
		return
	var is_host: bool = multiplayer.is_server()
	_wet_check -= delta
	var check_water: bool = is_host and _wet_check <= 0.0
	if check_water:
		_wet_check = 0.25
	for id: String in _effects.keys():
		var entry: Dictionary = _effects[id] as Dictionary
		var def: Dictionary = definition(id)
		entry["left"] = float(entry["left"]) - delta
		if is_host and health != null and health.current > 0.0:
			entry["acc"] = float(entry["acc"]) + delta
			var tick: float = float(def.get("tick", 0.5))
			if float(def.get("damage_ratio", 0.02)) <= 0.0 and float(def.get("min_damage", 1.0)) <= 0.0:
				tick = INF ## a harmless effect (a pause, a potion) never ticks damage
			while float(entry["acc"]) >= tick:
				entry["acc"] = float(entry["acc"]) - tick
				var least: float = float(def.get("min_damage", 1.0))
				if least > 0.0:
					least = maxf(roundf(least * float(entry["scale"])), 1.0) ## a weaker source (floor fire, scale 0.5) weakens the smallest tick too
				var amount: float = maxf(roundf(health.max_health * float(def.get("damage_ratio", 0.02)) * float(entry["scale"])), least)
				health.take_tick(amount, int(entry["source"]))
			if check_water and String(def.get("extinguish", "")) == "water" and _wet():
				_rpc_clear.rpc(id)
				continue
		if float(entry["left"]) <= 0.0:
			_remove(id)
			changed.emit()


## Standing in water (any surface the terrain gives a `submerge` to).
func _wet() -> bool:
	var player: Node2D = get_parent() as Node2D
	if player == null:
		return false
	return float(Terrain.surface_data(Terrain.surface_at(player.global_position)).get("submerge", 0.0)) > 0.0


func _show(id: String) -> void:
	if id == "hallucinated" and not _fx.has(id) and get_parent().is_multiplayer_authority(): ## what she sees is hers alone: only on her own machine
		var seen: Hallucinations = Hallucinations.new()
		seen.name = "Hallucinations"
		get_parent().add_child(seen)
		_fx[id] = seen
	if id == "burn" and not _fx.has(id) and DisplayServer.get_name() != "headless":
		var fx: BurnFx = BurnFx.new()
		fx.name = "BurnFx"
		(get_parent() as Node2D).add_child(fx)
		fx.bind(self)
		_fx[id] = fx


func _remove(id: String) -> void:
	_effects.erase(id)
	if _fx.has(id):
		var node: Node = _fx[id] as Node
		if is_instance_valid(node):
			if node.has_method("end"):
				node.call("end")
			node.queue_free()
		_fx.erase(id)
