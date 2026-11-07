class_name BossAura
extends ColorRect
## The mood of the boss fight against Mornath (docs/boss_sky_cleaver.md), local to every player near the arena: a quad over the world and under the HUD
## (CanvasLayer 0, like the ambush vignette) with assets/shaders/boss_aura.gdshader. While the fight goes on the night gets heavier and colder (the colours drain
## into violet), a ragged dark closes in from the edges and breathes with the heartbeat of the shadow creatures, and now and then, and at the big moments, the picture glitches:
## rows slip sideways, the colours split, blocks jump, for a frame or two it turns negative. It grows with the phase (`MornathFight.aura_level`): faint in the first phase,
## heavy in the second, as heavy as it gets in the judgement (then the picture also breathes). Purely cosmetic and local; frees itself when the fight ends.
## `kick(amount)` = a glitch at once (the fight calls it at a blast, a scream, a pulse of the judgement).

const SHADER: Shader = preload("res://assets/shaders/boss_aura.gdshader")
const RANGE: float = 480.0 ## a local player this close to the arena's middle feels it

var _fight: MornathFight
var _layer: CanvasLayer
var _material: ShaderMaterial = ShaderMaterial.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _level: float = 0.0 ## the smoothed level (0 .. 1.3)
var _near: float = 0.0
var _t: float = 0.0
var _next: float = 4.0
var _left: float = 0.0
var _len: float = 0.1
var _amp: float = 0.0
var _neg_left: float = 0.0
var _seed: float = 0.0


static func begin(fight: MornathFight) -> BossAura:
	if DisplayServer.get_name() == "headless":
		return null
	var aura: BossAura = BossAura.new()
	aura._fight = fight
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "BossAuraLayer"
	layer.layer = 0 ## under the HUD (layer 1)
	aura._layer = layer
	layer.add_child(aura)
	fight.add_child(layer)
	return aura


func _ready() -> void:
	_rng.seed = 424242
	color = Color.WHITE
	_material.shader = SHADER
	material = _material
	_next = _rng.randf_range(3.0, 6.0)
	_fit()


func _fit() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if size != view:
		size = view
	_material.set_shader_parameter("view_size", view)


func kick(amount: float) -> void:
	_start(clampf(amount, 0.2, 1.0), 0.09 + 0.12 * amount, amount > 0.7 and _rng.randf() < 0.6)


func _start(amp: float, length: float, negative: bool) -> void:
	_left = length
	_len = length
	_amp = amp
	_seed = _rng.randf() * 100.0
	if negative:
		_neg_left = 0.05 + 0.04 * _rng.randf()


## Seconds between the glitches of the level: rare at first, often at the end.
func _interval() -> float:
	if _level > 1.05:
		return _rng.randf_range(1.2, 3.0)
	if _level > 0.7:
		return _rng.randf_range(3.0, 6.5)
	return _rng.randf_range(4.5, 9.0)


func _process(delta: float) -> void:
	if not is_instance_valid(_fight) or not is_instance_valid(_fight.boss):
		_layer.queue_free()
		return
	_fit()
	_t += delta
	var want: float = _fight.aura_level()
	var near: bool = false
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.global_position.distance_to(_fight.boss.centre()) < RANGE:
			near = true
			break
	_near = move_toward(_near, 1.0 if near else 0.0, delta * 0.5)
	_level = move_toward(_level, want, delta * 0.45)
	var k: float = _level * _near
	if _left > 0.0:
		_left -= delta
	if _neg_left > 0.0:
		_neg_left -= delta
	if k > 0.05 and _left <= 0.0:
		_next -= delta
		if _next <= 0.0:
			_next = _interval()
			_start(_rng.randf_range(0.4, 0.9) * minf(k + 0.2, 1.0), _rng.randf_range(0.07, 0.2), k > 0.9 and _rng.randf() < 0.35)
	var beat: float = VoidGlow.beat(_t, 0.0, 0.8 + 0.3 * k)
	var heat: float = clampf((_level - 0.6) / 0.6, 0.0, 1.0)
	_material.set_shader_parameter("time", _t)
	_material.set_shader_parameter("dusk", k * 0.42)
	_material.set_shader_parameter("vignette", k * 0.95)
	_material.set_shader_parameter("pulse", beat)
	_material.set_shader_parameter("heat", heat)
	_material.set_shader_parameter("warp", maxf(_level - 1.0, 0.0) * _near * 1.6)
	var live: float = 0.0 if _left <= 0.0 else _amp * (1.0 if _left > _len * 0.4 else 0.4)
	_material.set_shader_parameter("glitch", live)
	_material.set_shader_parameter("glitch_seed", _seed)
	_material.set_shader_parameter("neg", 0.5 if _neg_left > 0.0 else 0.0)
	visible = k > 0.01 or _left > 0.0
