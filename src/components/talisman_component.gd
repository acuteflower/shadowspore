class_name TalismanComponent
extends Node
## The worn jewellery of one player and what it adds up to (docs/talisman_konzept.md). The host's inventory is the truth for every number that matters in
## combat; every peer knows the worn pieces through the synced `worn` list (three item ids, like `held_weapon`) and recomputes the same bonus from it with the
## pure `TalismanRules`, so health bars, charge speed and the look of the jewellery need no extra packets. Consumers: `ProgressComponent.apply_stats` (health,
## armor), `HealthComponent.absorb`, `AttackComponent` (damage, charge speed), `StealthComponent.alarm_scale` (shadow creatures).

signal changed
signal absorbed ## on every peer: a blow was partly swallowed (the earrings flash)
signal warded(at: Vector2) ## on every peer: the Rissfeder caught a lethal blow (feathers burst from her)
signal ward_changed ## on every peer: the Rissfeder is spent or whole again
signal dive_changed ## on every peer: the dive window opened or closed

const SOUNDS: String = "res://assets/audio/talisman/"

var worn: PackedStringArray = PackedStringArray(): ## item ids of the worn talismans, synced by the owner
	set(value):
		if value == worn:
			return
		var before: PackedStringArray = worn
		worn = value
		if _ready_done:
			_refresh()
			_chime(before, value)
var bonus: Dictionary = {} ## what they add up to (TalismanRules.combine)
var perks: Dictionary = {} ## the special abilities of the worn pieces (TalismanRules.perks): id -> its entry of the catalogue
var ward_ready: bool = true ## the last wing beat can still be used (every peer; the host decides)
var dive_left: float = 0.0 ## seconds the dive after a blink still counts (every peer counts it down)
var starlight_left: float = 0.0 ## seconds the starlight perk after a blink remains armed

var _ward_left: float = 0.0 ## host: seconds until the feather is whole again (runs on while it is not worn: taking it off is no reset)

var _inventory: InventoryComponent
var _ready_done: bool = false
var _armed_msec: int = 0 ## jewellery put on or off after this moment makes a sound (not the load at the start)
var _sounds: Dictionary = {}


func _ready() -> void:
	_inventory = get_node_or_null("../InventoryComponent") as InventoryComponent
	if _inventory != null:
		_inventory.changed.connect(_on_inventory_changed)
		if is_multiplayer_authority():
			worn = TalismanRules.worn_ids(_inventory.equipment)
	_ready_done = true
	_refresh()
	_armed_msec = Time.get_ticks_msec() + 2500
	var health: HealthComponent = get_node_or_null("../HealthComponent") as HealthComponent
	if health != null:
		health.damaged.connect(func(_amount: float, _from: Vector2, _knock: float) -> void:
			if health.absorb > 0.0:
				absorbed.emit()
				_play("absorb", -7.0))


func _process(delta: float) -> void:
	if dive_left > 0.0:
		dive_left = maxf(dive_left - delta, 0.0)
		if dive_left <= 0.0:
			dive_changed.emit()
	if starlight_left > 0.0:
		starlight_left = maxf(starlight_left - delta, 0.0)
		if starlight_left <= 0.0:
			dive_changed.emit()
	if _ward_left > 0.0 and multiplayer.is_server():
		_ward_left = maxf(_ward_left - delta, 0.0)
		if _ward_left <= 0.0:
			_ward_state.rpc(true, Vector2.ZERO)


## Host: the pause of the Letzter Flügelschlag gets shorter (the Himmelsriss's Federbund). It is ready again at once when it runs out.
func shorten_ward(seconds: float) -> void:
	if multiplayer.is_server() and _ward_left > 0.0 and perks.has("ward"):
		_ward_left = maxf(_ward_left - seconds, 0.0)


func _on_inventory_changed() -> void:
	if _inventory == null:
		return
	if is_multiplayer_authority():
		worn = TalismanRules.worn_ids(_inventory.equipment) ## the setter refreshes when it changed
	if multiplayer.is_server() and not is_multiplayer_authority():
		_refresh() ## the host trusts its own copy of somebody else's bag, not the list they sync


## The item id of the worn piece of this kind of jewellery ("bracelet" ...), "" when none.
func worn_id(type: String) -> String:
	for id: String in worn:
		if String(Items.definition({"id": id}).get("jewelry", "")) == type:
			return id
	return ""


## A little sound for every piece put on (by its metal) or taken off; only on the machine of the one who wears it.
func _chime(before: PackedStringArray, after: PackedStringArray) -> void:
	if Time.get_ticks_msec() < _armed_msec or not is_multiplayer_authority():
		return
	for id: String in after:
		if not before.has(id):
			_play("equip_" + String(TalismanArt.look_of(id).get("metal", "silver")), -8.0)
	for id: String in before:
		if not after.has(id):
			_play("off", -12.0)


func _play(id: String, volume_db: float) -> void:
	var stream: AudioStream = _sounds.get(id) as AudioStream
	if stream == null:
		if not ResourceLoader.exists(SOUNDS + id + ".wav"):
			return
		stream = load(SOUNDS + id + ".wav") as AudioStream
		_sounds[id] = stream
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.max_distance = 300.0
	get_parent().add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func alarm_scale() -> float:
	return TalismanRules.alarm_scale(bonus)


func damage_factor(heavy: bool) -> float:
	return TalismanRules.damage_factor(bonus, heavy)


func charge_rate() -> float:
	return TalismanRules.charge_rate(bonus)


## Multiplier on the blink cooldown (Rissfeder: shorter).
func blink_scale() -> float:
	return TalismanRules.blink_scale(bonus)


## The share by which wild crows and ravens are calmer around her (0 without Rissfeder).
func corvid_calm() -> float:
	return TalismanRules.corvid_calm(bonus)


# ---------------------------------------------------------------- special abilities (docs/rissfeder.md)

## Every peer, when a blink was played: opens the dive / starlight window (the next blow hits harder).
func note_blink() -> void:
	if perks.has("dive"):
		dive_left = float((perks["dive"] as Dictionary)["window"])
		dive_changed.emit()
	if perks.has("starlight"):
		starlight_left = float((perks["starlight"] as Dictionary)["window"])
		dive_changed.emit()


## Host: the factor on the next weapon hit while the dive window is open.
func dive_factor() -> float:
	if dive_left > 0.0 and perks.has("dive"):
		return 1.0 + float((perks["dive"] as Dictionary)["damage"])
	return 1.0


## Host: a blow has landed, the dive is used up (on every peer).
func spend_dive() -> void:
	if dive_left > 0.0 and multiplayer.is_server():
		_dive_end.rpc()


@rpc("any_peer", "call_local", "reliable")
func _dive_end() -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	dive_left = 0.0
	dive_changed.emit()


## Host: if the Starlight perk is armed after a blink, unleash a celestial wave around `at`.
func trigger_starlight(at: Vector2, base_damage: float, attacker: int) -> void:
	if starlight_left <= 0.0 or not perks.has("starlight") or not multiplayer.is_server():
		return
	var cfg: Dictionary = perks["starlight"] as Dictionary
	var radius: float = float(cfg.get("radius", 38.0))
	var bonus_dmg: float = base_damage * float(cfg.get("damage", 0.35))
	var knock: float = float(cfg.get("knockback", 90.0))
	starlight_left = 0.0
	var player_node: Node2D = get_parent() as Node2D
	if player_node != null:
		for target: HurtboxComponent in HitScan.circle(player_node, at, radius, AttackComponent.HURTBOX_MASK):
			target.take_hit(bonus_dmg, at, knock, attacker)
	_starlight_hit.rpc(at, radius)


@rpc("authority", "call_local", "reliable")
func _starlight_hit(at: Vector2, radius: float) -> void:
	starlight_left = 0.0
	dive_changed.emit()
	var burst: _StarlightBurst = _StarlightBurst.new(radius)
	burst.global_position = at
	if get_tree() != null and get_tree().current_scene != null:
		get_tree().current_scene.add_child(burst)


class _StarlightBurst:
	extends Node2D
	var _r: float = 38.0
	var _t: float = 0.0

	func _init(r: float = 38.0) -> void:
		_r = r
		material = Unlit.material()
		z_index = 6

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 0.34:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / 0.34, 0.0, 1.0)
		var alpha: float = 1.0 - k
		var rad: float = lerpf(8.0, _r, 1.0 - pow(1.0 - k, 2.0))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 24, Color("78f4e6", alpha * 0.85), 2.0)
		draw_arc(Vector2.ZERO, rad * 0.72, 0.0, TAU, 18, Color("fff0b0", alpha * 0.9), 1.0)
		for i: int in 8:
			var a: float = float(i) * TAU / 8.0 + k * 0.8
			var pt: Vector2 = Vector2.from_angle(a) * rad
			draw_rect(Rect2(pt.round() - Vector2.ONE, Vector2(2.0, 2.0)), Color("fff0b0" if i % 2 == 0 else "d8fff9", alpha))


## Host, called by `HealthComponent` when a blow or tick would take her last point: the feather catches it once, then needs `cooldown` seconds.
## Returns the health she keeps, or -1 when there is no ward (not worn, or spent).
func _ward_check(_left: float) -> float:
	if not multiplayer.is_server() or not perks.has("ward") or _ward_left > 0.0:
		return -1.0
	var cfg: Dictionary = perks["ward"] as Dictionary
	var player: Node2D = get_parent() as Node2D
	var health: HealthComponent = player.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return -1.0
	_ward_left = float(cfg["cooldown"])
	health.grant_grace(float(cfg["invulnerable"]))
	var at: Vector2 = player.global_position
	for target: HurtboxComponent in HitScan.circle(player, at + Vector2(0.0, -12.0), float(cfg["radius"]), AttackComponent.HURTBOX_MASK):
		target.take_hit(float(cfg["damage"]), at, float(cfg["knockback"]), get_multiplayer_authority()) ## the burst of feathers pushes them away
	_ward_state.rpc(false, at)
	return maxf(health.max_health * float(cfg["health"]), 1.0)


@rpc("any_peer", "call_local", "reliable")
func _ward_state(ready: bool, at: Vector2) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	ward_ready = ready
	if not ready:
		warded.emit(at)
		var radius: float = float((perks.get("ward", {}) as Dictionary).get("radius", 72.0))
		FeatherBurst.burst(get_tree().current_scene, at, radius)
		var player: Node = get_parent()
		if is_multiplayer_authority() and player.has_method("add_shake"):
			player.call("add_shake", 7.0)
		_play("ward", -3.0)
	else:
		_play("ward_ready", -9.0)
	ward_changed.emit()


func _refresh() -> void:
	var ids: PackedStringArray = worn
	if multiplayer.is_server() and _inventory != null:
		ids = TalismanRules.worn_ids(_inventory.equipment)
	var stacks: Array[Dictionary] = TalismanRules.stacks_of(ids)
	var next: Dictionary = TalismanRules.combine(stacks)
	var stats_changed: bool = next != bonus
	bonus = next
	perks = TalismanRules.perks(stacks)
	if stats_changed:
		_apply()
	_hook_ward()
	changed.emit()


## The host asks the feather before a lethal blow goes through (only while a piece with the ward is worn).
func _hook_ward() -> void:
	var player: Node = get_parent()
	var health: HealthComponent = player.get_node_or_null("HealthComponent") as HealthComponent if player != null else null
	if health != null and multiplayer.is_server():
		health.ward = Callable(self, "_ward_check") if perks.has("ward") else Callable()


## Health, armor and the swallowed share follow the jewellery. Never heals (a necklace put on and taken off is no medicine).
func _apply() -> void:
	var player: Node = get_parent()
	if player == null:
		return
	var health: HealthComponent = player.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.absorb = TalismanRules.absorb(bonus)
	var progress: ProgressComponent = player.get_node_or_null("ProgressComponent") as ProgressComponent
	if progress != null:
		progress.apply_stats(false, true)
