class_name TorbenCamp
extends Node2D
## Torben's overworld iron outcrop (quest `torben_smithy`): NO mine — open sky, iron boulders,
## warm brazier light, and StoryTorben hammering iron until Ellie helps fend off 3 shadows.

enum State { IDLE, FIGHT, MEET_READY, DONE }

const TRIGGER_RADIUS: float = 175.0
const RETRY_RADIUS: float = 260.0
const LOST_RADIUS: float = 520.0
const WALK_SPEED: float = 52.0
const BARK_LINES: Array[String] = ["Weg.", "Ruhe.", "Blech.", "Runter."]

var world: WorldLevel = null
var torben: StoryTorben = null

var _state: State = State.IDLE
var _enemies: Array[ShadowSpider] = []
var _kills_left: int = 0
var _check_cd: float = 0.25
var _combat_cd: float = 0.0
var _meeting: bool = false
var _home_offset: Vector2 = Vector2(14.0, 6.0)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("torben_camp")
	z_index = 0
	y_sort_enabled = true
	_rng.randomize()
	_build_props()
	torben = StoryTorben.new()
	torben.name = "StoryTorben"
	torben.camp = self
	torben.position = _home_offset
	add_child(torben)
	torben.play("sledge", Vector2(-1.0, -0.3))


func _build_props() -> void:
	var tex: Texture2D = load("res://assets/world/iron_rock.png") as Texture2D
	var placements: Array[Dictionary] = [
		{"pos": Vector2(-28.0, -6.0), "frame": 0, "radius": 11.0},
		{"pos": Vector2(36.0, -16.0), "frame": 4, "radius": 11.0}
	]
	for p: Dictionary in placements:
		var rock_pos: Vector2 = p.pos as Vector2
		var body: StaticBody2D = StaticBody2D.new()
		body.position = rock_pos
		body.collision_layer = 1
		body.collision_mask = 0
		var shape: CollisionShape2D = CollisionShape2D.new()
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = float(p.radius)
		shape.shape = circle
		body.add_child(shape)
		if tex != null:
			var sp: Sprite2D = Sprite2D.new()
			sp.texture = tex
			sp.hframes = 6
			sp.vframes = 4
			sp.frame = int(p.frame)
			sp.offset = Vector2(0.0, -10.0)
			body.add_child(sp)
		add_child(body)
	var light: PointLight2D = PointLight2D.new()
	light.position = Vector2(0.0, -4.0)
	light.color = Color("ffae52")
	light.energy = 0.85
	light.blend_mode = Light2D.BLEND_MODE_ADD
	LightTexture.apply(light, 140, 0.72, 0)
	add_child(light)


func _draw() -> void:
	# Subtle trampled earth and iron ember hearth between boulders
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 21:
		pts.append(Vector2.from_angle(TAU * i / 20.0) * Vector2(54.0, 26.0))
	draw_colored_polygon(pts, Color(0.18, 0.14, 0.11, 0.25))
	draw_circle(Vector2(-2.0, 0.0), 6.0, Color(0.15, 0.11, 0.09, 0.85))
	draw_circle(Vector2(-2.0, 0.0), 3.0, Color("e87828", 0.75))


func take_torben() -> Vector2:
	var at: Vector2 = torben.global_position if is_instance_valid(torben) else global_position + _home_offset
	if is_instance_valid(torben):
		torben.visible = false
		torben.can_talk = false
	_state = State.DONE
	return at


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or world == null or _state == State.DONE:
		return
	if world.torben_taken or (world._town_node != null and world._town_node.residents.has("torben")):
		if is_instance_valid(torben):
			torben.visible = false
			torben.can_talk = false
		_state = State.DONE
		return
	var player: Player = _active_player()
	if player == null or player.quests == null:
		return
	if player.quests.is_finished("torben_smithy") or player.quests.has_flag("tb_met"):
		_state = State.DONE
		return
	if _state == State.FIGHT:
		_tick_fight(delta, player)
		return
	_check_cd -= delta
	if _check_cd > 0.0:
		return
	_check_cd = 0.25
	var step: String = player.quests.active_step_id("torben_smithy")
	if step == "tb_find" and player.global_position.distance_to(global_position) <= TRIGGER_RADIUS:
		_start_ambush(player)
	elif step == "tb_fight" and _enemies.is_empty() and player.global_position.distance_to(global_position) <= RETRY_RADIUS:
		_state = State.FIGHT
		_kills_left = maxi(_kills_left, 3)
		_spawn_ambush(_kills_left)
	elif step == "tb_meet":
		_state = State.MEET_READY
		if is_instance_valid(torben):
			torben.can_talk = true
			torben.play("idle", player.global_position - torben.global_position)


func _active_player() -> Player:
	for p: Player in Player.all:
		if p.is_multiplayer_authority() and p.health.current > 0.0:
			return p
	return null


func _start_ambush(player: Player) -> void:
	player.quests.set_flag("tb_camp_reached")
	_state = State.FIGHT
	_kills_left = 3
	_spawn_ambush(3)
	if is_instance_valid(torben):
		torben.can_talk = false
		world.play_story_dialogue(player, "tb_ambush_start", torben)


func _spawn_ambush(count: int) -> void:
	var angles: Array[float] = [-0.6, 1.9, 3.7]
	for i: int in count:
		var ang: float = angles[i % angles.size()] + _rng.randf_range(-0.25, 0.25)
		var pos: Vector2 = global_position + Vector2.from_angle(ang) * _rng.randf_range(95.0, 125.0)
		var spider: ShadowSpider = world.spawn_story_spider("shadow_spider", pos, (global_position - pos).angle())
		if spider != null:
			_enemies.append(spider)
			var health: HealthComponent = spider.get_node_or_null("HealthComponent") as HealthComponent
			if health != null:
				health.died.connect(_on_ambusher_died, CONNECT_ONE_SHOT)


func _on_ambusher_died() -> void:
	_kills_left = maxi(0, _kills_left - 1)


func _tick_fight(delta: float, player: Player) -> void:
	_combat_cd = maxf(0.0, _combat_cd - delta)
	var alive: Array[ShadowSpider] = []
	var lost: int = 0
	for s: ShadowSpider in _enemies:
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var h: HealthComponent = s.get_node_or_null("HealthComponent") as HealthComponent
		if h != null and h.current <= 0.0:
			continue
		if s.global_position.distance_to(global_position) > LOST_RADIUS:
			s.queue_free()
			lost += 1
			continue
		alive.append(s)
	_enemies = alive
	if lost > 0:
		_spawn_ambush(lost)
	if _enemies.is_empty() and _kills_left <= 0:
		player.quests.set_flag("tb_ambush_done")
		_state = State.MEET_READY
		if is_instance_valid(torben):
			torben.global_position = global_position + _home_offset
			torben.can_talk = true
			torben.play("idle", player.global_position - torben.global_position)
			world.play_story_dialogue(player, "tb_ambush_clear", torben)
		return
	if not is_instance_valid(torben) or _enemies.is_empty():
		return
	var target: ShadowSpider = null
	var best_d: float = INF
	for s: ShadowSpider in _enemies:
		var d: float = torben.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			target = s
	if target == null:
		return
	var toward: Vector2 = target.global_position - torben.global_position
	if best_d <= 54.0:
		if _combat_cd <= 0.0:
			_combat_cd = 1.9
			torben.play("sledge" if _rng.randi() % 2 == 0 else "swat", toward)
			var h: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
			if h != null and h.current > 0.0:
				h.take_damage(18.0, torben.global_position, 140.0)
			if _rng.randf() < 0.55:
				torben.say(BARK_LINES[_rng.randi() % BARK_LINES.size()], 1.6)
	elif torben.global_position.distance_to(global_position) < 92.0 and best_d < 150.0:
		torben.play("walk", toward)
		torben.global_position += toward.normalized() * WALK_SPEED * delta
	else:
		torben.play("idle", toward)


## Interactive cutscene after ambushers fall: inspects Ellie's sword, agrees to come if smithy stands.
func meet_torben(player: Player) -> void:
	if _meeting or player == null or not is_instance_valid(torben):
		return
	_meeting = true
	torben.busy = true
	torben.can_talk = false
	player.story_lock = true
	player.facing = (torben.global_position - player.global_position).normalized()
	torben.play("idle", player.global_position - torben.global_position)
	await world.play_story_dialogue(player, "tb_meet", torben)
	if is_instance_valid(torben):
		torben.play("shove", Vector2.DOWN)
		await get_tree().create_timer(0.45, true, false, true).timeout
	if is_instance_valid(torben):
		torben.play("nod", player.global_position - torben.global_position)
		await get_tree().create_timer(0.45, true, false, true).timeout
	if is_instance_valid(torben):
		torben.play("lift", Vector2.DOWN)
		await get_tree().create_timer(0.45, true, false, true).timeout
	if is_instance_valid(torben):
		torben.play("carry", Vector2.DOWN)
	if world != null and world._town_node != null:
		world._town_node.add_story_resident("torben", true)
	take_torben()
	if is_instance_valid(player):
		player.story_lock = false
	_meeting = false
