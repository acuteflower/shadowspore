class_name FieldCell
extends Interactable
## One bed of a field (docs/farming.md): 16 x 16 px of ground that the hoe breaks up and the can waters, and the crop that stands in it. It is the node that
##  - shows the crop (`assets/props/crops/<frames>.png`, 4 stages of 24 x 32, feet at row 29; swaying in the wind; ripe night crops glow),
##  - is hit by tools (`HarvestHurtbox` on physics layer 5, lifted 24 px like every ground target because the weapons' fan starts at her chest: `harvest_hit`),
##  - answers E (sow with a seed in the hand, pick when ripe).
## The state lives in `FarmManager` (host decides); the soil under it is painted by the field (`FieldSoil`).

const CROP_DIR: String = "res://assets/props/crops/"
const HARVEST_LAYER: int = 1 << 4 ## physics layer 5, the one weapons hit
const FEET: Vector2 = Vector2(12.0, 29.0) ## the crop's feet in its 24 x 32 frame
const LIFT: float = 24.0 ## weapons swing from her chest: the hurtbox of something on the ground sits that far higher
const BURST_SOIL: Array[Color] = [Color("66494a"), Color("45323a"), Color("8a6a5c")]
const BURST_WATER: Array[Color] = [Color("bfe9ff"), Color("8ab8e0"), Color("e8f8ff")]

var field: FarmField
var index: int = 0
var state: Dictionary = {}

var _sprite: Sprite2D
var _glow: Sprite2D
var _hurtbox: HarvestHurtbox
var _crop: String = ""
var _stage: int = -1
var _night: float = 0.0
var _pop: Tween
var _sway: ShaderMaterial
var _active: bool = true


func setup(owner_field: FarmField, cell_index: int, center: Vector2, sway: ShaderMaterial) -> void:
	field = owner_field
	index = cell_index
	position = center + Vector2(0.0, 6.0) ## the origin is the crop's foot; the bed's middle is 6 px above
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.hframes = FarmRules.STAGES
	_sprite.position = -FEET
	_sway = sway
	_sprite.material = sway
	_sprite.visible = false
	add_child(_sprite)
	_glow = Sprite2D.new()
	_glow.centered = false
	_glow.hframes = FarmRules.STAGES
	_glow.material = Unlit.material()
	_glow.visible = false
	_sprite.add_child(_glow)
	_hurtbox = HarvestHurtbox.new()
	_hurtbox.name = "Harvest"
	_hurtbox.harvest_target = self
	_hurtbox.collision_layer = HARVEST_LAYER
	_hurtbox.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(14.0, 14.0)
	shape.shape = box
	shape.position = Vector2(0.0, -6.0 - LIFT)
	_hurtbox.add_child(shape)
	add_child(_hurtbox)
	add_to_group("night_lights")
	refresh("")


## Cells of a field that is still a building site neither show nor answer.
func set_active(on: bool) -> void:
	_active = on
	visible = on
	if _hurtbox != null:
		_hurtbox.collision_layer = HARVEST_LAYER if on else 0


## Takes the state of the cell from the manager and shows it. `fx` plays the effect that belongs to the change (till, water, plant, harvest, grow).
func refresh(fx: String) -> void:
	state = field.farm.cell_state(field.id, index)
	var crop_id: String = String(state.get("c", ""))
	var stage: int = clampi(int(state.get("a", 0)), 0, FarmRules.STAGES - 1)
	if crop_id != _crop:
		_crop = crop_id
		_stage = -1
		if crop_id == "":
			_sprite.visible = false
		else:
			var spec: Dictionary = FarmRules.crop(crop_id)
			var path: String = CROP_DIR + String(spec.get("frames", "crop_" + crop_id)) + ".png"
			_sprite.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
			_sprite.visible = _sprite.texture != null
			var glow_path: String = path.replace(".png", "_glow.png")
			_glow.texture = load(glow_path) as Texture2D if bool(spec.get("glow", false)) and ResourceLoader.exists(glow_path) else null
			_sprite.material = null if _glow.texture != null else _sway ## a crop with a glowing sheet stands still (the glow would slide off the leaves)
	if crop_id != "" and stage != _stage:
		var grew: bool = _stage >= 0 and stage > _stage
		_stage = stage
		_sprite.frame = stage
		_glow.frame = stage
		if grew and fx == "grow":
			_pop_in()
	_glow.visible = _glow.texture != null and _stage >= FarmRules.STAGES - 1
	_apply_night()
	match fx:
		"till":
			_dust(8, BURST_SOIL, 26.0)
			_sound("hoe_till", -4.0)
		"scrape":
			_dust(4, BURST_SOIL, 16.0)
			_sound("hoe_scrape", -8.0)
		"water":
			_dust(9, BURST_WATER, 22.0, 0.55)
			_sound("can_pour", -5.0)
		"plant":
			_dust(5, BURST_SOIL, 16.0)
			_sound("plant", -3.0)
			_pop_in()
		"harvest":
			_dust(10, BURST_SOIL, 34.0)
			_sound("harvest", -3.0)
	if _prompt_node != null:
		set_focused(_prompt_node.visible)


func _pop_in() -> void:
	if _pop != null:
		_pop.kill()
	_sprite.scale = Vector2(1.0, 0.7)
	_pop = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_sprite, "scale", Vector2.ONE, 0.3)


## Called by `DayNight` for everything in the group `night_lights`.
func set_night(amount: float) -> void:
	_night = MineManager.night_at(self, amount)
	_apply_night()


func _apply_night() -> void:
	if _glow != null:
		_glow.modulate.a = lerpf(0.3, 1.0, _night)


# ---------- tools ----------

## The harvest hurtbox hands every blow to its target (host only): the hoe breaks the ground, the can waters, anything else does nothing.
func harvest_hit(source: int) -> void:
	field.farm.host_hit(field.id, index, source)


## What the cursor asks (`GameCursor._can_harvest`): the tool that does something here right now.
func spec() -> Dictionary:
	return {"tool": FarmRules.tool_wanted(state, TimeManager.day)}


func is_depleted() -> bool:
	return FarmRules.tool_wanted(state, TimeManager.day) == "" and prompt() == ""


# ---------- E ----------

func prompt() -> String:
	if not _active or InputManager.ui_blocking:
		return ""
	if FarmRules.is_ripe(state):
		return "ERNTEN"
	if bool(state.get("t", 0)) and String(state.get("c", "")) == "" and _seed_in_hand() != "":
		return "SÄEN"
	return ""


func _seed_in_hand() -> String:
	var player: Player = field.manager.local_player()
	if player == null:
		return ""
	var held: String = String((player.inventory.slots[player.inventory.selected] as Dictionary).get("id", ""))
	return held if FarmRules.crop_for_seed(held) != "" else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + Vector2(0.0, -6.0)) - 6.0


func prompt_position() -> Vector2:
	return Vector2(0.0, -30.0 if _stage >= 2 else -22.0)


func interact(player: Player) -> void:
	if not player.is_multiplayer_authority():
		return
	var toward: Vector2 = global_position - player.global_position
	var dir: Vector2 = toward.normalized() if toward.length() > 1.0 else player.facing
	var farm: FarmManager = field.farm
	var field_id: int = field.id
	var cell: int = index
	if FarmRules.is_ripe(state):
		player.begin_pick(dir, func() -> void: farm.request_harvest(field_id, cell))
	elif prompt() == "SÄEN":
		player.begin_pick(dir, func() -> void: farm.request_plant(field_id, cell))


# ---------- effects ----------

func _dust(amount: int, colors: Array[Color], speed: float, up: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.one_shot = true
	puff.emitting = true
	puff.amount = amount
	puff.lifetime = 0.55
	puff.explosiveness = 0.95
	puff.direction = Vector2.UP
	puff.spread = 70.0
	puff.gravity = Vector2(0.0, 90.0 * up)
	puff.initial_velocity_min = speed * 0.4
	puff.initial_velocity_max = speed
	puff.scale_amount_min = 1.0
	puff.scale_amount_max = 1.6
	puff.color = colors[randi() % colors.size()]
	puff.position = Vector2(0.0, -6.0)
	puff.z_index = 3
	add_child(puff)
	get_tree().create_timer(1.0).timeout.connect(puff.queue_free)


func _sound(id: String, db: float) -> void:
	var path: String = "res://assets/audio/farming/%s.wav" % id
	if not is_inside_tree() or not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load(path) as AudioStream
	player.volume_db = db
	player.pitch_scale = randf_range(0.94, 1.06)
	player.max_distance = 300.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
