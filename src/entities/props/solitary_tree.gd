class_name SolitaryTree
extends SeatSpot
## Grand gnarled hilltop oak (`docs/wiesenbiom_ausbau_konzept.md` Stufe 2.2) standing alone on the highest
## crest of an open *Windwiese & Blütenmeer*. Never choppable — an indestructible resting landmark:
##  - Variant 0: weathered wooden bench nestled against the right-front buttress roots (`E -> "UNTER DER WINDEICHE RASTEN"`).
##  - Variant 1: rope-and-plank wooden swing (`oak_swing.png`) hanging from the left bough (`E -> "AUF DER SCHAUKEL RASTEN"`),
##    swaying smoothly in `WorldWind` and gently rocking a seated player by 1–2 whole pixels!
## Casts real ground shade (`day_canopies`), attracts night fireflies (`flora_glow`), and fades softly when a player walks behind its broad crown.

const TEX_PATH: String = "res://assets/props/solitary_oak.png"
const GLOW_PATH: String = "res://assets/props/solitary_oak_glow.png"
const SWING_PATH: String = "res://assets/props/oak_swing.png"
const FRAME_W: int = 224
const FRAME_H: int = 208
const FEET_Y: float = 192.0
const FADE_ALPHA: float = 0.36

var variant: int = 0 ## 0 = root bench, 1 = rope swing
var _body: Sprite2D
var _glow: Sprite2D
var _swing: Sprite2D
var _light: NightLight
var _notifier: VisibleOnScreenNotifier2D
var _on_screen: bool = false
var _covering: bool = false
var _cover_wait: float = 0.0
var _swing_shift: float = 0.0


func setup(pos_px: Vector2, var_idx: int) -> void:
	position = pos_px.round()
	variant = clampi(var_idx, 0, 1)


func _ready() -> void:
	add_to_group("day_canopies")
	add_to_group("flora_glow")
	label = "AUF DER SCHAUKEL RASTEN" if variant == 1 else "UNTER DER WINDEICHE RASTEN"
	radius = 22.0
	height = 38.0
	y_sort_enabled = false
	_build_visuals()
	_build_collider()
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-124.0, -204.0, 248.0, 224.0)
	_notifier.screen_entered.connect(func() -> void: _on_screen = true)
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(_notifier)


func _build_visuals() -> void:
	var off: Vector2 = Vector2(0.0, -(FEET_Y - float(FRAME_H) * 0.5))
	if ResourceLoader.exists(TEX_PATH):
		_body = Sprite2D.new()
		_body.texture = load(TEX_PATH) as Texture2D
		_body.hframes = 2
		_body.vframes = 1
		_body.frame = variant
		_body.offset = off
		add_child(_body)
	if ResourceLoader.exists(GLOW_PATH):
		_glow = Sprite2D.new()
		_glow.texture = load(GLOW_PATH) as Texture2D
		_glow.hframes = 2
		_glow.vframes = 1
		_glow.frame = variant
		_glow.offset = off
		_glow.material = Unlit.material()
		add_child(_glow)
	if variant == 1 and ResourceLoader.exists(SWING_PATH):
		_swing = Sprite2D.new()
		_swing.texture = load(SWING_PATH) as Texture2D
		_swing.position = Vector2(-42.0, -58.0)
		_swing.offset = Vector2(0.0, 30.0) ## pivot at top rope knot (16, 2) inside 32x64 sprite
		add_child(_swing)
	_light = NightLight.new()
	_light.position = Vector2(28.0 if variant == 0 else -32.0, -10.0)
	_light.radius = 64
	_light.base_energy = 0.42
	_light.pulse = 0.14
	_light.glow_color = Color("ffd98a")
	add_child(_light)


func _build_collider() -> void:
	var sb: StaticBody2D = StaticBody2D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var trunk_shape: CollisionShape2D = CollisionShape2D.new()
	var cap: CapsuleShape2D = CapsuleShape2D.new()
	cap.radius = 8.0
	cap.height = 38.0
	trunk_shape.shape = cap
	trunk_shape.rotation = PI * 0.5
	trunk_shape.position = Vector2(0.0, -5.0)
	sb.add_child(trunk_shape)
	add_child(sb)


func _process(delta: float) -> void:
	if not _on_screen:
		return
	var wind_vec: Vector2 = WorldWind.sample(global_position)
	var clock: float = WorldWind.current.clock if WorldWind.current != null else float(Time.get_ticks_msec()) * 0.001
	var night: float = TimeManager.night_amount()
	if _body != null:
		_body.skew = clampf(wind_vec.x * 0.011, -0.035, 0.035)
	if _glow != null:
		_glow.skew = _body.skew if _body != null else 0.0
		_glow.modulate = Color(1.0, 1.0, 1.0, lerpf(0.24, 0.92, night))
	if _swing != null:
		var osc: float = sin(clock * 1.65 + global_position.x * 0.01) * (0.045 + absf(wind_vec.x) * 0.08) + wind_vec.x * 0.05
		_swing.skew = clampf(-osc, -0.16, 0.16)
		_swing_shift = roundf(osc * 18.0)
		for p_seat: Player in Player.all:
			var rest: RestComponent = p_seat.get_node_or_null("RestComponent") as RestComponent
			if rest != null and rest.seat == self and rest.state != RestComponent.State.FREE and rest.state != RestComponent.State.APPROACH and rest.state != RestComponent.State.UP:
				p_seat.global_position = seat_position()

	_cover_wait -= delta
	if _cover_wait <= 0.0:
		_cover_wait = 0.08
		var hides: bool = false
		for p: Player in Player.all:
			if p.health.current <= 0.0:
				continue
			var rel: Vector2 = p.global_position - global_position
			if rel.y < -2.0 and rel.y > -148.0 and absf(rel.x) < 88.0:
				hides = true
				break
		if hides != _covering:
			_covering = hides
			var target_a: float = FADE_ALPHA if _covering else 1.0
			var tw: Tween = create_tween()
			tw.tween_property(self, "modulate:a", target_a, 0.18)


func day_canopy() -> Vector4:
	var c: Vector2 = global_position + Vector2(24.0, 10.0)
	return Vector4(c.x, c.y, 96.0, 56.0)


func sit_sector() -> int:
	return 2 ## facing south out across the sun-swept flower sea


func seat_position() -> Vector2:
	if variant == 1:
		return global_position + Vector2(-42.0 + _swing_shift, 3.0)
	return global_position + Vector2(36.0, 4.0)


func approach_position() -> Vector2:
	return (global_position + Vector2(-42.0, 16.0)) if variant == 1 else (global_position + Vector2(36.0, 16.0))


func prompt_position() -> Vector2:
	return Vector2(-42.0, -34.0) if variant == 1 else Vector2(36.0, -28.0)


func reach_distance(from: Vector2) -> float:
	var anchor: Vector2 = (global_position + Vector2(-42.0, 3.0)) if variant == 1 else (global_position + Vector2(36.0, 4.0))
	return maxf(0.0, anchor.distance_to(from) - 18.0)


func regen_rate() -> float:
	return 0.65


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.health.current <= 0.0 or player.intro != null or player.story_lock or player.fainting or InputManager.ui_blocking:
		return ""
	if occupied():
		return ""
	return "AUF DER SCHAUKEL RASTEN" if variant == 1 else "UNTER DER WINDEICHE RASTEN"


func interact(player: Player) -> void:
	if player == null or not player.is_multiplayer_authority() or prompt() == "":
		return
	(player.get_node("RestComponent") as RestComponent).request_sit(self)
