class_name TalismanComponent
extends Node
## The worn jewellery of one player and what it adds up to (docs/talisman_konzept.md). The host's inventory is the truth for every number that matters in
## combat; every peer knows the worn pieces through the synced `worn` list (three item ids, like `held_weapon`) and recomputes the same bonus from it with the
## pure `TalismanRules`, so health bars, charge speed and the look of the jewellery need no extra packets. Consumers: `ProgressComponent.apply_stats` (health,
## armor), `HealthComponent.absorb`, `AttackComponent` (damage, charge speed), `StealthComponent.alarm_scale` (shadow creatures).

signal changed
signal absorbed ## on every peer: a blow was partly swallowed (the earrings flash)

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


func _refresh() -> void:
	var ids: PackedStringArray = worn
	if multiplayer.is_server() and _inventory != null:
		ids = TalismanRules.worn_ids(_inventory.equipment)
	var next: Dictionary = TalismanRules.combine(TalismanRules.stacks_of(ids))
	var stats_changed: bool = next != bonus
	bonus = next
	if stats_changed:
		_apply()
	changed.emit()


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
