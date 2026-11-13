class_name WorldProp
extends Interactable
## Base of what stands in the world and shares a state with every peer (data/plants.json): bushes,
## little stones and big rocks. The state is a small dictionary ({} = untouched): "h" harvest slots
## used, "p" the day it was picked + 1, "k" the kind (set by the host, so growing back works for
## props that are not loaded). It lives on the host and reaches every peer through `WorldLevel`,
## which also placed this prop. Subclasses show it (`apply_state`) and add what is special.

static var _day_shared: ShaderMaterial

static func _day_material() -> ShaderMaterial:
	if _day_shared == null:
		_day_shared = ShaderMaterial.new()
		_day_shared.shader = preload("res://assets/shaders/day_sprite.gdshader")
	return _day_shared

const SPARKS: Texture2D = preload("res://assets/fx/dust.png")
const GLOW_BY_DAY: float = 0.22 ## how visible the glowing parts are in daylight

var level: WorldLevel
var cell: Vector2i = Vector2i.ZERO
var kind: String = ""
var variant: int = 0
var state: Dictionary = {}

var _spec: Dictionary = {}
var _radius: float = 12.0
var _height: float = 22.0
var _wind_exposure: float = 1.0
var wind_boost: float = 1.0 ## set by the world level for Krummholz (stunted trees on high ground sway harder)
var _tween: Tween
var _glow: Sprite2D ## the emissive parts of the sprite's frame (plants.json "glow", same sheet layout), drawn unshaded
var _night_light: NightLight
var blight: float = 0.0 ## 0..1: how far the Void has got into this plant (near the world's edge), see `_setup_blight`
var _blight_glow: Sprite2D ## violet shimmer of a blighted plant in moonlit nights (plants without a glow sheet of their own)

const BLIGHT_REACH: float = 14.0 ## tiles from the coast where small plants begin to wither (the baked coast field only knows about 16)
const BLIGHT_TINT: Color = Color(0.62, 0.55, 0.72)
const BLIGHT_GLOW: Color = Color(0.72, 0.38, 1.0)

@onready var _sprite: Sprite2D = $Sprite
@onready var _hurtbox: HarvestHurtbox = get_node_or_null("Hurtbox") as HarvestHurtbox


func setup(world: WorldLevel, at: Vector2i, prop_kind: String, prop_variant: int) -> void:
	level = world
	cell = at
	kind = prop_kind
	variant = prop_variant
	name = "%s_%d_%d" % [kind, at.x, at.y]


func _ready() -> void:
	if is_instance_valid(WorldWind.current):
		_wind_exposure = WorldWind.current.exposure(global_position)
	_wind_exposure *= wind_boost
	_spec = DataRegistry.get_entry("plants", kind)
	_radius = float((_spec.radius as Array)[variant])
	_height = float((_spec.height as Array)[variant])
	if _hurtbox != null:
		_hurtbox.owner_prop = self
		_shape($Hurtbox/Shape, _radius * 0.85, Vector2(0, -_radius * 0.5))
	_setup_glow()
	if _spec.has("group"):
		add_to_group(StringName(_spec.group)) ## plants.json `group`: e.g. the toadstools the Hexenwald's toads live by (TinyPopulation)
	_setup_prop()
	if _sprite.material == null: _sprite.material = _day_material()
	_setup_blight()
	_setup_gloom()
	var saved: Dictionary = level.thing_state(cell) if level != null else {}
	apply_state(saved if String(saved.get("k", kind)) == kind else {}, "") ## a state of another kind (an old save) is ignored


## The glow sprite lies exactly over `_sprite` (so it rustles and sways with it): dim by day, bright at night.
func _setup_glow() -> void:
	if not _spec.has("glow"):
		return
	_glow = Sprite2D.new()
	_glow.centered = false
	_glow.offset = _sprite.offset
	_glow.texture = load(String(_spec.glow)) as Texture2D
	_glow.material = Unlit.material()
	_sprite.add_child(_glow)
	add_to_group("night_lights") ## DayNight tells every night light and prop how dark it is
	if bool(_spec.get("fireflies", false)):
		add_to_group("flora_glow") ## the fireflies gather here (see Fireflies)
	set_night(TimeManager.night_amount())


## Near the world's edge the Void eats the plants (docs/plant_life.md): small plants fade toward grey-violet and sag the closer they
## stand to the coast, and in moonlit nights they glimmer violet. Only a look (trees and rocks are left alone).
const GLOOM_TINT: Color = Color(0.5, 0.64, 0.7) ## meadow bushes in the Hexenwald: darker and colder with the biome's gloom (BiomeBlend)
const ARID_TINT: Color = Color(1.06, 0.88, 0.64) ## surviving meadow bushes and steppe grasses in the desert border warm and dry with BiomeBlend


## The plain bushes the Hexenwald shares with the meadow take on its dark, cool light instead of glowing lime against it.
func _setup_gloom() -> void:
	if _sprite == null:
		return
	if kind == "bush":
		var gloom: float = BiomeBlend.amount_at(global_position)
		if gloom > 0.02:
			_sprite.self_modulate *= Color.WHITE.lerp(GLOOM_TINT, gloom)
	if kind == "bush" or kind == "grass":
		var arid: float = BiomeBlend.arid_at(global_position) * (1.0 - 0.92 * BiomeBlend.oasis_at(global_position))
		if arid > 0.03:
			_sprite.self_modulate *= Color.WHITE.lerp(ARID_TINT, minf(arid * 1.4, 1.0))


func _setup_blight() -> void:
	if level == null or _sprite == null or PropGenerator.TREE_KINDS.has(kind) or kind in ["rock", "iron_rock", "curse_rock", "sun_quartz_rock", "mine_rock", "mine_collapse"]:
		return
	blight = 1.0 - smoothstep(2.0, BLIGHT_REACH, level.coast_tiles(global_position))
	if blight <= 0.02:
		blight = 0.0
		return
	_sprite.self_modulate = Color.WHITE.lerp(BLIGHT_TINT, blight * 0.85)
	_sprite.scale.y = 1.0 - 0.14 * blight ## the stalks sag
	if _glow == null:
		_blight_glow = Sprite2D.new()
		_blight_glow.centered = false
		_blight_glow.offset = _sprite.offset
		_blight_glow.material = Unlit.material()
		_blight_glow.modulate = Color(BLIGHT_GLOW, 0.0)
		_sprite.add_child(_blight_glow)
		add_to_group("night_lights")
	set_night(TimeManager.night_amount())


## Subclasses call this after changing `_sprite`'s texture or frame: the glow takes the same frame (or hides).
func _sync_glow(lit: bool) -> void:
	if _blight_glow != null:
		_blight_glow.texture = _sprite.texture
		_blight_glow.hframes = _sprite.hframes
		_blight_glow.vframes = _sprite.vframes
		_blight_glow.frame = _sprite.frame
	if _glow != null:
		_glow.visible = lit
		_glow.hframes = _sprite.hframes
		_glow.vframes = _sprite.vframes
		_glow.frame = _sprite.frame


## DayNight: how dark it is (0..1).
func set_night(amount: float) -> void:
	amount = MineManager.night_at(self, amount)
	if _glow != null:
		_glow.modulate.a = lerpf(GLOW_BY_DAY, 1.0, amount)
		if blight > 0.0: ## the glow of a blighted plant turns violet
			_glow.self_modulate = Color.WHITE.lerp(BLIGHT_GLOW, blight * 0.7)
	if _blight_glow != null:
		_blight_glow.modulate.a = blight * amount * (0.12 + 0.3 * TimeManager.moon_light())


## A soft pool of light on the ground that shines at night (made once, shown or hidden with `on`).
func _set_light(on: bool, color: Color, radius: int, energy: float) -> void:
	if on and _night_light == null:
		_night_light = NightLight.new()
		_night_light.radius = radius
		_night_light.squash = 0.55
		_night_light.base_energy = energy
		_night_light.glow_color = color
		_night_light.pulse = 0.2
		_night_light.position = Vector2(0, -3)
		add_child(_night_light)
	if _night_light != null:
		_night_light.visible = on


## For subclasses: runs once the spec is known.
func _setup_prop() -> void:
	pass


## Everyone: shows `new_state` with an effect (hit, strip, pick, regrow, rustle).
func apply_state(new_state: Dictionary, _fx: String) -> void:
	state = new_state


func spec() -> Dictionary:
	return _spec


## Harvest slots a whole prop has (bushes: harvest.hits, rocks: hits per variant).
func slots() -> int:
	var hits: Variant = _spec.get("hits", (_spec.get("harvest", {}) as Dictionary).get("hits", 3))
	return int((hits as Array)[variant]) if hits is Array else int(hits)


## All slots used: stripped bush, depleted rock.
func is_depleted() -> bool:
	return _spec.has("harvest") and int(state.get("h", 0)) >= slots()


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + Vector2(0, -_radius * 0.45)) - _radius


func prompt_position() -> Vector2:
	return Vector2(0, -_height - 8.0)


## True while the opening runs (crawling out of the sewer until she wakes in Valdric's hut): nothing out there can be
## picked, so she cannot heal herself on the way. The host asks its own `opening_over`; a client has no opening of its
## own and reads the host's locked clock instead (the opening holds it at midnight, the wake-up unlocks it).
func opening_locked() -> bool:
	if level == null:
		return false
	if multiplayer.is_server():
		return not level.opening_over
	return TimeManager.locked


## Host: a weapon's hit scan found this prop.
func harvest_hit(source: int) -> void:
	level.harvest_hit(self, source)


func _shape(node: CollisionShape2D, radius: float, at: Vector2) -> void:
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	node.shape = circle
	node.position = at


func _rustle(direction: float, amount: float = 0.16) -> void:
	if _tween != null:
		_tween.kill()
	_sprite.skew = amount * (1.0 if direction >= 0.0 else -1.0)
	_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_sprite, "skew", 0.0, 0.55)


## A one-shot puff of little pieces (leaves, chips, sparks).
func _burst(count: int, colors: Array, speed: float = 38.0, at: Vector2 = Vector2.ZERO) -> void:
	if colors.is_empty():
		return
	var puff: CPUParticles2D = CPUParticles2D.new()
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([colors[0], colors[colors.size() - 1], Color(colors[0], 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	puff.texture = SPARKS
	puff.color_ramp = gradient
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.amount = count
	puff.lifetime = 0.7
	puff.direction = Vector2.UP
	puff.spread = 75.0
	puff.initial_velocity_min = speed * 0.5
	puff.initial_velocity_max = speed
	puff.gravity = Vector2(0, 120.0 if speed > 0.0 else -20.0)
	puff.scale_amount_min = 0.35
	puff.scale_amount_max = 0.6
	puff.position = at if at != Vector2.ZERO else Vector2(0, -_height * 0.55)
	puff.emitting = true
	add_child(puff)
	puff.finished.connect(puff.queue_free)
