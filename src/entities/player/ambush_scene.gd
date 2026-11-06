class_name AmbushScene
extends Node
## The crossroad ambush, started by the quest step "ambush" after the signpost was read (`WorldLevel.start_ambush`; solo / host for now).
## 1. She is held still, the screen darkens and closes in, a heartbeat starts and three pairs of magenta eyes open in the dark round her; she
##    gasps (dialogue `ambush_start`).  2. Control returns and the spiders (`ambush_spider`) come out of the eyes
##    one after the other. Each has real, killable 150 HP; fallen spiders are replaced by more emerging shadows.
##    She can dodge and strike, but her health never goes below 1 (`HealthComponent.floor_value`): the fight cannot be won
##    and she cannot die.  3. After a while (a few hits taken) the rescue (`_moment`): slow motion, a white streak, the adventurer (`Adventurer`)
##    cuts the three spiders down, lands backlit in front of her, speaks (dialogue `rescue`), Ellie faints (`Player.show_faint_frame`) and the
##    screen goes black. Then the flags `rescued` and `ambush_done` are set and the screen comes back (placeholder for the hut, not built yet).

const SOUNDS: Dictionary = {
	"sting": preload("res://assets/audio/ambush/sting.wav"),
	"impact": preload("res://assets/audio/ambush/impact.wav"),
	"whoosh": preload("res://assets/audio/ambush/whoosh.wav"),
	"slash": preload("res://assets/audio/ambush/slash.wav"),
	"land": preload("res://assets/audio/ambush/land.wav"),
	"beat": preload("res://assets/audio/intro/heartbeat.wav"),
	"gasp": preload("res://assets/audio/intro/gasp.wav"),
}
const VIGNETTE: Shader = preload("res://assets/shaders/ambush_vignette.gdshader")
const SLOT_ANGLES: Array[float] = [-2.6, -0.45, 1.9] ## where the eyes open round her (radians), tried in turn when blocked
const RING: float = 125.0
const FIGHT_MIN: float = 10.0 ## seconds of fighting before the end can come, if she has been hit often enough
const FIGHT_MAX: float = 21.0
const MIN_HITS: int = 3
const REINFORCEMENT_DELAY: float = 0.65

var _player: Player
var _world: WorldLevel
var _eyes: AmbushEyes
var _vignette: ColorRect
var _flash: ColorRect
var _spiders: Array[ShadowSpider] = []
var _refill_wait: Dictionary = {} ## slot -> seconds before its replacement tears through
var _resolving: bool = false ## rescue owns the scene; no further reinforcements
var _adv: Adventurer
var _zoom_base: float = 1.0
var _hits: int = 0
var _beat: AudioStreamPlayer
var _beat_gap: float = 1.0
var _beat_clock: float = 0.0
var _dread: float = 0.0 ## 0..1, drives the vignette and the heartbeat


func start(player: Player, world: WorldLevel) -> void:
	_player = player
	_world = world
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vignette_layer: CanvasLayer = CanvasLayer.new() ## below the HUD (layer 1)
	vignette_layer.layer = 0
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = ShaderMaterial.new()
	(_vignette.material as ShaderMaterial).shader = VIGNETTE
	vignette_layer.add_child(_vignette)
	add_child(vignette_layer)
	var flash_layer: CanvasLayer = CanvasLayer.new() ## above everything
	flash_layer.layer = 90
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	flash_layer.add_child(_flash)
	add_child(flash_layer)
	_eyes = AmbushEyes.new()
	world.add_child(_eyes)
	_beat = AudioStreamPlayer.new()
	_beat.stream = SOUNDS["beat"] as AudioStream
	add_child(_beat)
	_run()


func _process(delta: float) -> void:
	(_vignette.material as ShaderMaterial).set_shader_parameter("amount", _dread)
	if _dread > 0.05: ## the heartbeat speeds up and grows louder with the dread
		_beat_clock += delta / maxf(Engine.time_scale, 0.2)
		if _beat_clock >= _beat_gap:
			_beat_clock = 0.0
			_beat_gap = lerpf(1.05, 0.55, _dread)
			_beat.volume_db = lerpf(-14.0, 0.0, _dread)
			_beat.play()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout ## real time, also during the slow motion


func _play(sound: String, volume_db: float) -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = SOUNDS[sound] as AudioStream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _fade_dread(to: float, seconds: float) -> void:
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(self, "_dread", to, seconds)


func _zoom(to: float, seconds: float) -> void:
	_zoom_base = to
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(_player._camera, "zoom", Vector2(to, to), seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A white flash that fades quickly (a hit).
func _blink(alpha: float) -> void:
	_flash.color = Color(1, 1, 1, alpha)
	create_tween().set_ignore_time_scale(true).tween_property(_flash, "color:a", 0.0, 0.22)


## The camera jumps in a little and settles back (a hit lands).
func _punch(amount: float) -> void:
	_player._camera.zoom = Vector2.ONE * _zoom_base * (1.0 + amount)
	create_tween().set_ignore_time_scale(true).tween_property(_player._camera, "zoom", Vector2.ONE * _zoom_base, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hold(on: bool) -> void:
	_player.story_lock = on
	InputManager.ui_blocking = on


func _run() -> void:
	await _wait(1.0)
	_hold(true)
	_player.health.floor_value = 1.0
	_play("sting", -4.0)
	_fade_dread(0.45, 2.5)
	_zoom(1.3, 3.0)
	var spots: Array[Vector2] = _eye_spots()
	for i: int in spots.size():
		_eyes.open(i, spots[i])
		await _wait(0.7)
	await _wait(0.8)
	_play("gasp", -6.0)
	_player.add_shake(1.5)
	await _wait(0.6)
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	if box != null:
		box.start("ambush_start")
		await box.finished
	_hold(false)
	_player.health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void: _hits += 1)
	_fade_dread(0.6, 2.0)
	for i: int in spots.size():
		var spider: ShadowSpider = _world.spawn_story_spider("ambush_spider", spots[i], (_player.global_position - spots[i]).angle())
		if spider != null:
			_spiders.append(spider)
		# The warning eyes hand over to the creature as its first claws break through.
		_close_birth_eyes(i)
		if i < spots.size() - 1:
			await _wait(1.45)
	# The last creature also finishes forming before the fight timer begins.
	await _wait(ShadowBirth.DURATION)
	var fight: float = 0.0
	while is_inside_tree():
		await _wait(0.25)
		fight += 0.25
		if _player.health.current <= 0.0 or fight >= FIGHT_MAX or (fight >= FIGHT_MIN and _hits >= MIN_HITS):
			break
		_maintain_pressure(0.25)
	await _moment()


## Individual kills count, but never clear the scripted ambush. Three occupied slots
## bound the enemy count; replacements telegraph with the normal full emergence.
func _maintain_pressure(delta: float) -> void:
	if _resolving:
		return
	for i: int in _spiders.size():
		var spider: ShadowSpider = _spiders[i]
		if is_instance_valid(spider) and spider._health.current > 0.0:
			continue
		if not _refill_wait.has(i):
			_refill_wait[i] = REINFORCEMENT_DELAY
		_refill_wait[i] = float(_refill_wait[i]) - delta
		if float(_refill_wait[i]) > 0.0:
			continue
		var spots: Array[Vector2] = _eye_spots()
		for spot: Vector2 in spots:
			var clear: bool = true
			for other: ShadowSpider in _spiders:
				if is_instance_valid(other) and other._health.current > 0.0 and other.global_position.distance_to(spot) < 48.0:
					clear = false
			if not clear:
				continue
			var replacement: ShadowSpider = _world.spawn_story_spider("ambush_spider",spot,(_player.global_position-spot).angle())
			if replacement != null:
				_spiders[i] = replacement
				_refill_wait.erase(i)
			break


func _close_birth_eyes(slot: int) -> void:
	await get_tree().create_timer(0.75).timeout
	if is_instance_valid(_eyes):
		_eyes.close(slot)


## Three places round her where a spider can stand: spread round the ring, on loaded land and clear of anything solid.
func _eye_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	for base: float in SLOT_ANGLES:
		for turn: int in 12:
			var angle: float = base + turn * 0.35 * (1.0 if turn % 2 == 0 else -1.0)
			var spot: Vector2 = _player.global_position + Vector2.from_angle(angle) * RING
			var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
			query.position = spot
			query.collision_mask = 1
			if _world.navigation_floor(spot) and space.intersect_point(query, 1).is_empty():
				out.append(spot)
				break
	return out


## The rescue. Slow motion, a spider rears over her; then a white streak: the adventurer plunges out of the dark onto the nearest spider
## (shock ring, dust), dashes to the next and the next, and every cut is a frozen moment (a line through the spider, a crescent, a hit stop,
## a flash, a camera punch) before the spider bursts; the last one is a finisher (crossed cuts, a big ring). He shakes the blade clean, stands
## in front of her backlit, speaks, and Ellie faints; he runs to her and kneels (`_faint`).
func _moment() -> void:
	_resolving = true
	_hold(true)
	Engine.time_scale = 0.25
	_fade_dread(1.0, 1.2)
	_zoom(1.85, 1.4)
	_player.add_shake(3.0)
	await _wait(1.6)
	_beat_gap = 99.0 ## silence: the heartbeat stops
	_play("whoosh", -2.0)
	_blink(0.45)
	var centre: Vector2 = _player.global_position
	var live: Array[ShadowSpider] = []
	for spider: ShadowSpider in _spiders:
		if is_instance_valid(spider) and spider._health.current > 0.0:
			live.append(spider)
	live.sort_custom(func(a: ShadowSpider, b: ShadowSpider) -> bool: return a.global_position.distance_to(centre) < b.global_position.distance_to(centre))
	var toward: Vector2 = Vector2.ZERO
	for spider: ShadowSpider in live:
		toward += (spider.global_position - centre).normalized()
	var away: Vector2 = -toward.normalized() if toward.length() > 0.2 else Vector2.LEFT
	_adv = Adventurer.new()
	_world.add_child(_adv)
	Engine.time_scale = 0.4
	# 1. the plunge onto the nearest spider
	var first: ShadowSpider = live[0] if not live.is_empty() else null
	var land: Vector2 = centre + away * 40.0
	if first != null:
		land = first.global_position + (centre - first.global_position).normalized() * 34.0
	var start: Vector2 = land + away * 170.0
	_adv.global_position = start
	_adv.lift = 280.0
	_adv.trail = true
	_play("whoosh", -3.0)
	var dive: Tween = create_tween().set_ignore_time_scale(true)
	dive.tween_method(func(k: float) -> void:
		_adv.global_position = start.lerp(land, k)
		_adv.lift = 280.0 * (1.0 - k * k)
		_adv.pose("dive", 0 if k < 0.5 else 1, land - start), 0.0, 1.0, 0.55)
	await dive.finished
	_adv.trail = false
	_adv.lift = 0.0
	_adv.pose("dive", 2, (first.global_position - land) if first != null else Vector2.DOWN)
	_play("land", -2.0)
	ShockRing.burst(_world, land, 80.0, 1.0)
	_player.add_shake(6.0)
	if first != null:
		await _cut(first, land, 0)
	await _wait(0.4)
	# 2. the others: dash, slash, frozen cut
	var kills: Array[String] = ["dive", "slash_b", "slash_c"]
	for i: int in range(1, live.size()):
		var spider: ShadowSpider = live[i]
		if not is_instance_valid(spider):
			continue
		var target: Vector2 = spider.global_position
		var from: Vector2 = _adv.global_position
		var heading: Vector2 = (target - from).normalized()
		var stop: Vector2 = target - heading * 34.0
		_adv.trail = true
		_adv.play("run", heading)
		_play("whoosh", -6.0)
		var dash: Tween = create_tween().set_ignore_time_scale(true)
		dash.tween_property(_adv, "global_position", stop, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		await dash.finished
		_adv.trail = false
		_adv.play(kills[i % kills.size()], (target - stop).normalized())
		await _adv.strike
		await _cut(spider, stop, i)
		await _wait(0.4)
	# 3. the blade shaken clean, a step in front of her, the light behind him
	_adv.play("flick", (centre - _adv.global_position).normalized())
	await _wait(0.5)
	var stand: Vector2 = centre + Vector2(0.7 if away.x >= 0.0 else -0.7, -0.7) * 54.0 ## north-east/west of her: the camera sees his front
	_adv.play("run", (stand - _adv.global_position).normalized())
	var step: Tween = create_tween().set_ignore_time_scale(true)
	step.tween_property(_adv, "global_position", stand, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await step.finished
	_adv.play("idle", centre - stand)
	_play("land", -8.0)
	var settle: Tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	settle.tween_property(_adv, "lit", 1.0, 1.2)
	settle.tween_method(func(v: float) -> void: Engine.time_scale = v, Engine.time_scale, 1.0, 1.0)
	_fade_dread(0.25, 1.6)
	_zoom(1.6, 1.8)
	await _wait(1.6)
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	if box != null:
		box.start("rescue")
		await box.finished
	await _faint(stand, centre)
	# The hut: the screen is black, the wake-up scene takes over under it (the quest step "wake", started by the flag below).
	_player.quests.set_flag("rescued")
	_player.end_faint()
	_player.health.floor_value = 0.0
	_player._camera.zoom = Vector2.ONE
	_dread = 0.0
	if is_instance_valid(_adv):
		_adv.queue_free()
	_hold(false)
	_player.quests.set_flag("ambush_done")
	await get_tree().process_frame
	await get_tree().process_frame
	_eyes.queue_free()
	queue_free()


## One cut, a frozen moment: a line through the spider (two crossed ones for the finisher), a crescent, a flash, a hit stop with the spider
## held in the air, a camera punch; then it bursts and a ring of dust runs out.
func _cut(spider: ShadowSpider, from: Vector2, index: int) -> void:
	var at: Vector2 = spider.global_position
	var direction: Vector2 = (at - from).normalized()
	var big: bool = index >= 2
	var chest: Vector2 = at + Vector2(0, -12)
	SlashArc.line(_world, chest, direction.rotated(-0.55 if index % 2 == 0 else 0.55), 100.0)
	if big:
		SlashArc.line(_world, chest, direction.rotated(0.55), 100.0)
	SlashArc.cut(_world, chest - direction * 6.0, direction, 30.0 + index * 5.0, (-0.5 if index % 2 == 0 else 0.5))
	_play("slash", -2.0)
	_blink(0.65 if big else 0.4)
	_punch(0.12 if big else 0.06)
	_player.add_shake(6.0 if big else 3.5)
	spider.process_mode = Node.PROCESS_MODE_DISABLED ## frozen in the cut
	var scale_before: float = Engine.time_scale
	Engine.time_scale = 0.03
	await _wait(0.2 if big else 0.11)
	Engine.time_scale = scale_before
	if is_instance_valid(spider):
		spider.process_mode = Node.PROCESS_MODE_INHERIT
		spider.cut_down(from)
	ShockRing.burst(_world, at, 76.0 if big else 46.0, 1.0 if big else 0.6)


## Ellie faints: the faint sheet runs in real time (she clutches the wound, her knees give and hit the ground, she sways back and topples with
## weight, bounces once and lies still). He sees it coming, runs to her and kneels beside her; the screen goes black.
func _faint(stand: Vector2, centre: Vector2) -> void:
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("faint", {}) as Dictionary)
	var fps: float = float(rig.get("fps", 24))
	var frames: int = int(rig.get("frames", 1))
	var events: Dictionary = rig.get("events", {}) as Dictionary
	var flip: bool = stand.x < centre.x ## she turns her face to him
	var buckle_at: int = int(float(events.get("buckle", 0.75)) * fps)
	var kneel_at: int = int(float(events.get("kneel", 0.98)) * fps)
	var thud_at: int = int(float(events.get("thud", 1.74)) * fps)
	var beside: Vector2 = centre + (stand - centre).normalized() * 24.0
	_zoom(2.1, 2.2)
	for f: int in frames:
		_player.show_faint_frame(f, flip)
		if f == buckle_at and is_instance_valid(_adv):
			_adv.trail = true
			_adv.play("run", (beside - _adv.global_position).normalized())
			var rush: Tween = create_tween().set_ignore_time_scale(true)
			rush.tween_property(_adv, "global_position", beside, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			rush.tween_callback(func() -> void: _adv.trail = false)
		if f == kneel_at:
			_player.add_shake(2.0)
			ShockRing.burst(_world, centre, 22.0, 0.3)
		if f == thud_at:
			_play("impact", -10.0)
			_player.add_shake(4.5)
			ShockRing.burst(_world, centre, 40.0, 0.5)
			if is_instance_valid(_adv):
				_adv.play("kneel", centre - beside)
		await _wait(1.0 / fps)
	await _wait(1.3)
	var black: Tween = create_tween().set_ignore_time_scale(true)
	black.tween_property(_flash, "color", Color(0, 0, 0, 1), 1.0)
	await _wait(2.4)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
