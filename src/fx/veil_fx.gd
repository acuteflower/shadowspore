class_name VeilFx
extends Node2D
## A veiled player (status effect `veil`, Nebelschleier, docs/magie_konzept.md, school NEBEL). Made by StatusEffects._show on every peer, a
## child of the player (origin = her feet). While it lasts her own sprite (hit_flash.gdshader `veil`) dissolves into drifting mist holes,
## whole pixel rows slip sideways and her colours wash into a cold lilac; to everyone else she is only a flicker (VEIL_KEEP_OTHERS), on her own
## screen she stays readable (VEIL_KEEP_OWN). The staff/sword arm fades along. Around her: slow wisps, glitch bars across her body, a faint
## dithered ring of mist on the ground. It forms in 0.35 s and tears open in the last 0.6 s. Tier III (IRRSPUR): where the veil fell, a
## mist double of her stays standing for `ghost` seconds (VeilGhost); the creatures that hunted her run to that spot, because it is where
## they last saw her. The rule itself (enemies cannot pick a veiled player) lives in the enemies' senses through `Player.veiled()`.

const MIST: Color = Color("b9aaff")
const PALE: Color = Color("f2eeff")
const DEEP: Color = Color("5a4ea0")
const VEIL_KEEP_OWN: float = 0.5
const VEIL_KEEP_OTHERS: float = 0.16
const STEP: float = 1.0 / 20.0

var _effects: StatusEffects
var _player: Player
var _t: float = 0.0
var _acc: float = 0.0
var _amount: float = 0.0
var _seed_clock: float = 0.0
var _wisps: Array[Vector4] = [] ## x, y, life, phase
var _bars: Array[Vector3] = [] ## y, width, life


func _ready() -> void:
	z_index = 3
	material = SpellZone.add_material()
	_player = get_parent() as Player


func bind(effects: StatusEffects) -> void:
	_effects = effects
	if _effects != null and _effects.scale_of("veil") >= 3.0 and _player != null: ## IRRSPUR
		var perk: Dictionary = SpellRules.spell_def("veil").get("perk3", {}) as Dictionary
		VeilGhost.leave(_player, float(perk.get("ghost", 3.0)))


func _process(delta: float) -> void:
	_t += delta
	var left: float = _effects.left("veil") if _effects != null and is_instance_valid(_effects) else 0.0
	_amount = clampf(_t / 0.35, 0.0, 1.0) * clampf(left / 0.6, 0.0, 1.0)
	_apply(_amount)
	_seed_clock += delta
	if randf() < delta * 10.0 * _amount:
		_wisps.append(Vector4(randf_range(-9.0, 9.0), randf_range(-36.0, -2.0), randf_range(0.6, 1.2), randf() * TAU))
	if randf() < delta * 6.0 * _amount:
		_bars.append(Vector3(randf_range(-36.0, -4.0), randf_range(5.0, 14.0), randf_range(0.05, 0.14)))
	for i: int in range(_wisps.size() - 1, -1, -1):
		var w: Vector4 = _wisps[i]
		w.z -= delta
		w.y -= delta * 9.0
		w.x += sin(_t * 2.0 + w.w) * delta * 7.0
		if w.z <= 0.0:
			_wisps.remove_at(i)
		else:
			_wisps[i] = w
	for i: int in range(_bars.size() - 1, -1, -1):
		var b: Vector3 = _bars[i]
		b.z -= delta
		if b.z <= 0.0:
			_bars.remove_at(i)
		else:
			_bars[i] = b
	_acc += delta
	if _acc >= STEP:
		_acc = 0.0
		queue_redraw()


## Her sprite and her arm, `amount` 0..1 veiled.
func _apply(amount: float) -> void:
	if _player == null:
		return
	var own: bool = _player.is_multiplayer_authority()
	var keep: float = VEIL_KEEP_OWN if own else VEIL_KEEP_OTHERS
	var sprite: Sprite2D = _player.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and sprite.material is ShaderMaterial:
		var mat: ShaderMaterial = sprite.material as ShaderMaterial
		mat.set_shader_parameter("veil", amount)
		mat.set_shader_parameter("veil_keep", keep)
		mat.set_shader_parameter("veil_seed", floorf(_seed_clock * 12.0))
	if _player.attack != null:
		_player.attack.modulate.a = lerpf(1.0, keep + 0.12, amount)


func end() -> void:
	_apply(0.0)
	if _player != null and is_instance_valid(_player):
		SpellZone.sound(_player, "veil_off", _player.global_position, -6.0)


func _exit_tree() -> void:
	_apply(0.0)


func _draw() -> void:
	if _amount <= 0.01:
		return
	## the mist on the ground: a dithered, breathing ring
	for k: int in 20:
		var a: float = TAU * float(k) / 20.0 + _t * 0.5
		var r: float = 11.0 + sin(_t * 2.0 + float(k)) * 1.5
		if (k + int(_t * 6.0)) % 3 == 0:
			continue
		draw_rect(Rect2(Vector2(roundf(cos(a) * r), roundf(sin(a) * r * 0.45)), Vector2.ONE), Color(MIST, 0.3 * _amount))
	for w: Vector4 in _wisps: ## wisps: two-pixel threads of mist drifting up
		var k2: float = clampf(w.z / 0.6, 0.0, 1.0)
		var at: Vector2 = Vector2(roundf(w.x), roundf(w.y))
		draw_rect(Rect2(at, Vector2(2.0, 1.0)), Color(MIST, 0.45 * k2 * _amount))
		draw_rect(Rect2(at + Vector2(1.0, -1.0), Vector2.ONE), Color(PALE, 0.3 * k2 * _amount))
	for b: Vector3 in _bars: ## glitch bars across her body
		draw_rect(Rect2(Vector2(-roundf(b.y * 0.5) + (randi() % 3) - 1.0, roundf(b.x)), Vector2(roundf(b.y), 1.0)), Color(PALE if randf() < 0.3 else MIST, 0.5 * _amount))
		draw_rect(Rect2(Vector2(-roundf(b.y * 0.5) + 3.0, roundf(b.x) + 1.0), Vector2(roundf(b.y * 0.6), 1.0)), Color(DEEP, 0.4 * _amount))
