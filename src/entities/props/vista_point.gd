class_name VistaPoint
extends SeatSpot
## A panoramic cliff-edge resting place (`docs/wiesenbiom_ausbau_konzept.md` Stufe 1, `data/vistas.json`).
## Sitting down (`E -> "AUSSICHT GENIESSEN"`) uses the replicated `RestComponent`; on the sitting player's own peer only:
## - `WorldLevel.set_vista_focus` expands chunk streaming (`LOAD_RADIUS = 2`) into the valley ahead so zoomed-out terrain & props have zero seam pop-in;
## - `Camera2D` smoothly zooms out to `0.56` and pans slightly toward the cliff view (`Player.view_shift`);
## - the HUD gently fades away (`hud.vista_hide`) and `MusicDirector.vista_mode` blends in calm high-altitude wind;
## - after `reveal_delay` seconds, the host unveils a wide valley disc in `MapDiscovery` and awards first-time discovery XP (`Vistas`).

const TEX_PATH: String = "res://assets/props/vista_spot.png"
const GLOW_PATH: String = "res://assets/props/vista_spot_glow.png"
const FRAME_W: int = 64
const FRAME_H: int = 48
const GROUND_Y: float = 40.0 ## feet row inside the 64x48 frame

var vista_id: String = ""
var vista_name: String = ""
var vista_sub: String = ""
var sector: int = 2 ## facing sector 0..7 (E, SE, S, SW, W, NW, N, NE)
var variant: int = 0 ## 0 stone_ledge, 1 moss_log, 2 carved_bench
var discovered_flag: bool = false

var _body: Sprite2D
var _glow: Sprite2D
var _light: NightLight
var _local_sitting: bool = false
var _cam_tween: Tween
var _discover_sent: bool = false


func _ready() -> void:
	label = "AUSSICHT GENIESSEN"
	radius = 18.0
	height = 28.0
	_build_visuals()
	_build_collider()
	var manager: Vistas = Vistas.of(get_tree())
	if manager != null:
		manager.register(self)


func _build_visuals() -> void:
	var offset_v: Vector2 = Vector2(0.0, -(GROUND_Y - float(FRAME_H) * 0.5))
	if ResourceLoader.exists(TEX_PATH):
		_body = Sprite2D.new()
		_body.texture = load(TEX_PATH) as Texture2D
		_body.hframes = 3
		_body.vframes = 1
		_body.frame = clampi(variant, 0, 2)
		_body.offset = offset_v
		add_child(_body)
	if ResourceLoader.exists(GLOW_PATH):
		_glow = Sprite2D.new()
		_glow.texture = load(GLOW_PATH) as Texture2D
		_glow.hframes = 3
		_glow.vframes = 1
		_glow.frame = clampi(variant, 0, 2)
		_glow.offset = offset_v
		_glow.material = Unlit.material()
		_glow.modulate = Color(1.0, 1.0, 1.0, 0.45)
		add_child(_glow)
	_light = NightLight.new()
	_light.position = Vector2(-12.0, -6.0)
	_light.radius = 38
	_light.base_energy = 0.25
	_light.glow_color = Color("78f4e6")
	add_child(_light)
	set_discovered_visual(discovered_flag)


func _build_collider() -> void:
	## Small low-profile stone/log collider at the cairn shoulder so walking around feels physical without blocking the seat approach.
	var static_body: StaticBody2D = StaticBody2D.new()
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(10.0, 6.0)
	shape_node.shape = rect
	shape_node.position = Vector2(-15.0, -2.0)
	static_body.add_child(shape_node)
	add_child(static_body)


func set_discovered_visual(on: bool) -> void:
	discovered_flag = on
	if _glow != null:
		_glow.modulate = Color(1.0, 1.0, 1.0, 0.95 if on else 0.42)
	if _light != null:
		_light.base_energy = 0.52 if on else 0.22
		_light.glow_color = Color("ffd98a") if on else Color("78f4e6")


func play_discovery_fx() -> void:
	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.one_shot = true
	motes.emitting = true
	motes.amount = 22
	motes.lifetime = 2.1
	motes.explosiveness = 0.55
	motes.direction = sit_direction() + Vector2(0.0, -0.6)
	motes.spread = 55.0
	motes.gravity = Vector2(0.0, -10.0)
	motes.initial_velocity_min = 12.0
	motes.initial_velocity_max = 32.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.0
	motes.color = Color("ffd98a")
	motes.material = Unlit.material()
	motes.position = Vector2(0.0, -12.0)
	motes.z_index = 6
	add_child(motes)
	get_tree().create_timer(2.6).timeout.connect(motes.queue_free)


func sit_sector() -> int:
	return clampi(sector, 0, 7)


func sit_direction() -> Vector2:
	return Vector2.RIGHT.rotated(float(sit_sector()) * PI / 4.0)


func seat_position() -> Vector2:
	## Sitting north-facing (`5..7`) places feet behind the slab (`y - 3`) so y-sort draws the rock/log lip in front of Ellie's legs;
	## sitting front/south-facing (`0..4`) places Ellie's sort-y at `y + 1` so her seated figure and forward-hanging legs draw in front of the seat!
	var dy: float = -3.0 if sit_sector() >= 5 else 1.0
	return global_position + Vector2(0.0, dy)


func approach_position() -> Vector2:
	## Approach from behind the cliff edge (opposite the valley look direction), safely on the plateau floor.
	return (seat_position() - sit_direction() * 14.0).round()


func usable_by(player: Player) -> bool:
	return player != null and player.health.current > 0.0 and player.intro == null and not player.story_lock and not player.fainting


func regen_rate() -> float:
	var manager: Vistas = Vistas.of(get_tree())
	var cfg: Dictionary = manager.settings() if manager != null else {}
	return float(cfg.get("regen_rate", 0.55))


## Host: called every second while `player` sits on this VistaPoint.
func rest_tick(player: Player, seated: float) -> void:
	var manager: Vistas = Vistas.of(get_tree())
	if manager == null:
		return
	var delay: float = float(manager.settings().get("reveal_delay", 1.9))
	if seated >= delay and not manager.is_discovered(vista_id):
		manager.host_discover(vista_id, player)


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or not usable_by(player) or InputManager.ui_blocking:
		return ""
	return "AUSSICHT GENIESSEN" if not occupied() else ""


func interact(player: Player) -> void:
	if not player.is_multiplayer_authority() or prompt() == "":
		return
	(player.get_node("RestComponent") as RestComponent).request_sit(self)


func _process(_delta: float) -> void:
	var player: Player = _local_player()
	var sitting_now: bool = false
	if player != null:
		var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent
		if rest != null and rest.seat == self and rest.state != RestComponent.State.FREE and rest.state != RestComponent.State.APPROACH and rest.state != RestComponent.State.UP:
			sitting_now = true
	if sitting_now != _local_sitting:
		_local_sitting = sitting_now
		_apply_local_vista_mode(player, sitting_now)


func _apply_local_vista_mode(player: Player, active: bool) -> void:
	var manager: Vistas = Vistas.of(get_tree())
	var cfg: Dictionary = manager.settings() if manager != null else {}
	var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
	if world != null:
		if active:
			var look_world: Vector2 = global_position + sit_direction() * 220.0
			world.set_vista_focus(look_world, 2)
		else:
			world.clear_vista_focus()
	var music: MusicDirector = get_tree().get_first_node_in_group("music_director") as MusicDirector
	if music != null:
		music.vista_mode = active
	if player != null and is_instance_valid(player):
		var hud: Node = player.get("_hud") as Node
		if hud == null:
			hud = player.get_node_or_null("Hud")
		if hud != null:
			hud.set("vista_hide", active)
		var camera: Camera2D = player.view_camera()
		if camera != null:
			if _cam_tween != null:
				_cam_tween.kill()
			_cam_tween = player.create_tween().set_parallel(true)
			_cam_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			if active:
				var z: float = float(cfg.get("zoom", 0.56))
				var pan: float = float(cfg.get("pan_px", 108.0))
				var dur_in: float = float(cfg.get("zoom_in_seconds", 1.85))
				_cam_tween.tween_property(camera, "zoom", Vector2(z, z), dur_in)
				_cam_tween.tween_property(player, "view_shift", (sit_direction() * pan).round(), dur_in)
				if ResourceLoader.exists("res://assets/audio/vistas/sit_stone.wav"):
					var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
					snd.stream = load("res://assets/audio/vistas/sit_stone.wav") as AudioStream
					snd.volume_db = -8.0
					add_child(snd)
					snd.finished.connect(snd.queue_free)
					snd.play()
			else:
				var dur_out: float = float(cfg.get("zoom_out_seconds", 0.85))
				_cam_tween.tween_property(camera, "zoom", Vector2.ONE, dur_out)
				_cam_tween.tween_property(player, "view_shift", Vector2.ZERO, dur_out)


func _exit_tree() -> void:
	if _local_sitting:
		_local_sitting = false
		var player: Player = _local_player()
		_apply_local_vista_mode(player, false)
