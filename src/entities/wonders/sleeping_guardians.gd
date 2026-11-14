class_name SleepingGuardians
extends Node2D
## Unique Meadow World Wonder 2 (`docs/wiesenbiom_ausbau_konzept.md` Stufe 5.2): **Der Kreis der Schlafenden Wächter**.
## Seven house-tall mossy stone monolith guardians (`sleeping_guardian.png`, `3x1` of `80x128`, anchor `(40, 116)`) stand in an
## oval ring on the misty Glasklippen Level-3 plateau (`[256, 205]`). Six rest peacefully (Cols `0..1`); the seventh is broken
## and headless (Col `2`), its fallen headstone (`guardian_brazier.png` Col `2`) resting in the grass nearby.
##
## Two full, host-authoritative ways to awaken the ancient blessing echo:
##  - **Path A (Carry the Fallen Headstone):** Lift the fallen headstone (`E -> "KOPFSTEIN AUFHEBEN"`, using Ellie's two-handed
##    carry sheet) and carry it to the 7th broken guardian (`E -> "WÄCHTERHAUPT EINSETZEN"`). The 7th monolith restores to Col `0`!
##  - **Path B (Light the 7 Offering Bowls in Order `I..VII`):** Each guardian has an ancient stone brazier (`guardian_brazier.png`,
##    Cols `0..1`) marked with `1..7` glowing rune notches. Lighting them in ascending order `1 -> 7` (`E -> "OPFERSCHALE ENTZÜNDEN"`)
##    awakens the circle; a wrong bowl gently resets the unawakened bowls with a puff of mist.
##
## Once awakened, `guardian_chord.wav` resonates across the plateau, a permanent luminous rune circle blesses any player inside
## (`+1.5 HP/s` & `+4.0 Stamina/s`), a `legendary` `LootChest` rises at the center, and the state persists in `SaveGame`.

const GUARDIAN_TEX: String = "res://assets/props/sleeping_guardian.png"
const GUARDIAN_GLOW: String = "res://assets/props/sleeping_guardian_glow.png"
const BRAZIER_TEX: String = "res://assets/props/guardian_brazier.png"
const BRAZIER_GLOW: String = "res://assets/props/guardian_brazier_glow.png"
const CHORD_WAV: String = "res://assets/audio/meadow_wonders/guardian_chord.wav"

const GUARDIAN_COUNT: int = 7
const BROKEN_INDEX: int = 6 ## 7th guardian (southern/south-east arch) is the broken headless sentinel

var wonders: MeadowWonders
var wonder_id: String = "wonder_sleeping_guardians"
var chest_tier: String = "legendary"
var ring_rx: float = 76.0
var ring_ry: float = 52.0
var headstone_start: Vector2 = Vector2(88.0, 56.0)

var awakened: bool = false
var head_restored: bool = false
var lit_step: int = 0 ## 0..7 bowls lit in sequence
var carrier_peer: int = 0 ## peer_id currently carrying the fallen headstone (0 = lying on ground)

var _statues: Array[Sprite2D] = []
var _statue_glows: Array[Sprite2D] = []
var _braziers: Array[GuardianBrazier] = []
var _broken_plinth: BrokenGuardianSocket
var _headstone: FallenHeadstone
var _ground_fx: Node2D
var _center_light: NightLight

var _time: float = 0.0
var _awaken_age: float = 99.0
var _regen_accum: float = 0.0
var _mist_wisps: Array[Dictionary] = []


func setup(owner_wonders: MeadowWonders, spec: Dictionary) -> void:
	wonders = owner_wonders
	wonder_id = String(spec.get("id", "wonder_sleeping_guardians"))
	chest_tier = String(spec.get("chest_tier", "legendary"))
	ring_rx = float(spec.get("ring_rx", 76.0))
	ring_ry = float(spec.get("ring_ry", 52.0))
	var hs: Array = spec.get("headstone_offset", [88.0, 56.0]) as Array
	headstone_start = Vector2(float(hs[0]), float(hs[1]))
	var t: Array = spec.get("tile", [256, 205]) as Array
	position = Vector2(float(t[0]), float(t[1])) * 16.0 + Vector2(8.0, 8.0)


func guardian_local_pos(idx: int) -> Vector2:
	# Start at top-north (-PI/2) and step clockwise so idx 6 sits accessibly on the lower-west / north-west arc
	var angle: float = -PI * 0.5 + float(idx) / float(GUARDIAN_COUNT) * TAU
	return Vector2(cos(angle) * ring_rx, sin(angle) * ring_ry).round()


func brazier_local_pos(idx: int) -> Vector2:
	var g_pos: Vector2 = guardian_local_pos(idx)
	return (g_pos * 0.68 + Vector2(0.0, 6.0)).round()


func _ready() -> void:
	add_to_group("flora_glow")
	y_sort_enabled = true

	_ground_fx = Node2D.new()
	_ground_fx.z_index = -5
	_ground_fx.material = Unlit.material()
	_ground_fx.draw.connect(_draw_ground_fx)
	add_child(_ground_fx)

	var g_tex: Texture2D = load(GUARDIAN_TEX) as Texture2D if ResourceLoader.exists(GUARDIAN_TEX) else null
	var g_glw: Texture2D = load(GUARDIAN_GLOW) as Texture2D if ResourceLoader.exists(GUARDIAN_GLOW) else null
	var g_off: Vector2 = Vector2(0.0, -(116.0 - 64.0)) ## anchor (40, 116) inside 80x128 cell

	for i: int in GUARDIAN_COUNT:
		var g_pos: Vector2 = guardian_local_pos(i)
		var holder: Node2D = Node2D.new()
		holder.name = "Guardian_%d" % i
		holder.position = g_pos
		add_child(holder)

		var sp: Sprite2D = Sprite2D.new()
		if g_tex != null:
			sp.texture = g_tex
			sp.hframes = 3
		sp.offset = g_off
		sp.flip_h = g_pos.x > 8.0
		holder.add_child(sp)
		_statues.append(sp)

		var gl: Sprite2D = Sprite2D.new()
		if g_glw != null:
			gl.texture = g_glw
			gl.hframes = 3
		gl.offset = g_off
		gl.flip_h = sp.flip_h
		gl.material = Unlit.material()
		holder.add_child(gl)
		_statue_glows.append(gl)

		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(36.0, 16.0)
		cs.shape = rect
		cs.position = Vector2(0.0, -4.0)
		body.add_child(cs)
		holder.add_child(body)

		var brz: GuardianBrazier = GuardianBrazier.new()
		brz.name = "Brazier_%d" % i
		brz.setup(self, i, brazier_local_pos(i))
		add_child(brz)
		_braziers.append(brz)

	_broken_plinth = BrokenGuardianSocket.new()
	_broken_plinth.name = "BrokenSocket"
	_broken_plinth.setup(self, guardian_local_pos(BROKEN_INDEX) + Vector2(0.0, 12.0))
	add_child(_broken_plinth)

	_headstone = FallenHeadstone.new()
	_headstone.name = "FallenHeadstone"
	_headstone.setup(self, headstone_start)
	add_child(_headstone)

	_center_light = NightLight.new()
	_center_light.radius = 84
	_center_light.base_energy = 0.35
	_center_light.pulse = 0.14
	_center_light.glow_color = Color("7cf6e8")
	add_child(_center_light)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(wonder_id)
	for m: int in 18:
		_mist_wisps.append({
			"angle": rng.randf() * TAU,
			"dist": rng.randf_range(0.25, 1.12),
			"speed": rng.randf_range(0.08, 0.22) * (1.0 if m % 2 == 0 else -1.0),
			"phase": rng.randf() * TAU,
		})

	_refresh_visuals()


func _exit_tree() -> void:
	if carrier_peer != 0:
		var p: Player = player_of(carrier_peer)
		if p != null and p.carry_stone != 0:
			p.end_carry()


func player_of(peer: int) -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name.to_int() == peer:
			return p
	return null


func set_state_instant(is_awake: bool, restored_head: bool) -> void:
	awakened = is_awake
	head_restored = restored_head
	if is_awake:
		lit_step = GUARDIAN_COUNT
		carrier_peer = 0
		var chests: LootChests = LootChests.of(get_tree())
		if chests != null:
			chests.place(wonder_id + "_chest", chest_tier, global_position + Vector2(0.0, 4.0), false)
	_refresh_visuals()


func play_awaken_fx(restored_head: bool) -> void:
	awakened = true
	head_restored = head_restored or restored_head
	lit_step = GUARDIAN_COUNT
	if carrier_peer != 0:
		var p: Player = player_of(carrier_peer)
		carrier_peer = 0
		if p != null and p.carry_stone != 0:
			p.end_carry()
	_awaken_age = 0.0
	if ResourceLoader.exists(CHORD_WAV):
		var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		snd.stream = load(CHORD_WAV) as AudioStream
		snd.bus = "SFX"
		snd.volume_db = -1.5
		snd.max_distance = 680.0
		snd.finished.connect(snd.queue_free)
		add_child(snd)
		snd.play()
	for pl: Player in Player.all:
		if is_instance_valid(pl) and pl.is_multiplayer_authority() and pl.global_position.distance_to(global_position) < 260.0:
			pl.add_shake(1.3)
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		chests.appear(wonder_id + "_chest", chest_tier, global_position + Vector2(0.0, 4.0), false, true, true)
	_refresh_visuals()


func apply_brazier_step(new_step: int, reset_puff: bool) -> void:
	lit_step = clampi(new_step, 0, GUARDIAN_COUNT)
	if reset_puff:
		Sfx.at(self, "bush_rustle", global_position, -5.0, 0.1)
	else:
		Sfx.at(self, "waystone_wake", global_position, -7.0, 0.14)
	_refresh_visuals()


func apply_headstone_carrier(peer_id: int, drop_local: Vector2) -> void:
	var prev_peer: int = carrier_peer
	carrier_peer = peer_id
	if prev_peer != 0 and prev_peer != peer_id:
		var old_p: Player = player_of(prev_peer)
		if old_p != null and old_p.carry_stone != 0:
			old_p.end_carry()
	if peer_id != 0:
		var new_p: Player = player_of(peer_id)
		if new_p != null and new_p.carry_stone == 0:
			new_p.start_carry()
	elif _headstone != null:
		_headstone.position = drop_local
	_refresh_visuals()


func _refresh_visuals() -> void:
	for i: int in _statues.size():
		var col: int = i % 2
		if i == BROKEN_INDEX and not head_restored:
			col = 2
		_statues[i].frame = col
		_statue_glows[i].frame = col
		var is_lit: bool = awakened or i < lit_step
		_statue_glows[i].visible = is_lit or TimeManager.night_amount() > 0.15
		if i < _braziers.size():
			_braziers[i].set_lit(is_lit)
	if _headstone != null:
		_headstone.refresh_visibility()
	if _center_light != null:
		_center_light.base_energy = 0.92 if awakened else 0.34
		_center_light.radius = 124 if awakened else 78
		_center_light.glow_color = Color("ffd97d") if awakened else Color("7cf6e8")


func _process(delta: float) -> void:
	_time += delta
	_awaken_age += delta

	# Glow modulation on statues
	for i: int in _statue_glows.size():
		var gl: Sprite2D = _statue_glows[i]
		if not gl.visible:
			continue
		var is_lit: bool = awakened or i < lit_step
		var pulse: float = 0.82 + 0.18 * sin(_time * 2.1 + float(i) * 0.9)
		gl.modulate.a = (0.95 * pulse) if is_lit else (0.28 * TimeManager.night_amount() * pulse)

	# Host safety: if carrier disconnects or faints, set the headstone gently back on the plateau
	if multiplayer.is_server() and carrier_peer != 0 and not awakened and wonders != null:
		var cp: Player = player_of(carrier_peer)
		if cp == null or cp.health == null or cp.health.current <= 0.0:
			wonders.host_force_drop_headstone(headstone_start)

	# Blessing Echo regeneration for players standing inside the awakened ring!
	if awakened:
		_regen_accum += delta
		for p: Player in Player.all:
			if not is_instance_valid(p) or p.health == null or p.health.current <= 0.0:
				continue
			var q: Vector2 = p.global_position - global_position
			var inside: bool = pow(q.x / (ring_rx + 18.0), 2.0) + pow(q.y / (ring_ry + 18.0), 2.0) <= 1.0
			if inside and p.stamina != null and p.stamina.current < p.stamina.max_stamina:
				p.stamina._set_current(p.stamina.current + 4.0 * delta)
		if _regen_accum >= 1.0:
			_regen_accum -= 1.0
			if multiplayer.is_server():
				for p2: Player in Player.all:
					if not is_instance_valid(p2) or p2.health == null or p2.health.current <= 0.0:
						continue
					var q2: Vector2 = p2.global_position - global_position
					if pow(q2.x / (ring_rx + 18.0), 2.0) + pow(q2.y / (ring_ry + 18.0), 2.0) <= 1.0:
						if p2.health.current < p2.health.max_health:
							p2.health.heal(1.5)

	_ground_fx.queue_redraw()


func _draw_ground_fx() -> void:
	# Drifting highland mist wisps
	for w: Dictionary in _mist_wisps:
		var ang: float = float(w.angle) + _time * float(w.speed)
		var d: float = float(w.dist)
		var pt: Vector2 = Vector2(cos(ang) * ring_rx * d, sin(ang) * ring_ry * d).round()
		var a_mist: float = (0.14 + 0.08 * sin(_time * 1.4 + float(w.phase))) * (1.3 if awakened else 1.0)
		_ground_fx.draw_rect(Rect2(pt + Vector2(-4.0, -1.0), Vector2(8.0, 2.0)), Color(0.75, 0.96, 0.94, a_mist))

	# Carved order notch dots beside each brazier (1..7) so observant explorers can deduce the sequence
	for i: int in GUARDIAN_COUNT:
		var b_pt: Vector2 = brazier_local_pos(i) + Vector2(0.0, 6.0)
		var lit_col: Color = Color("ffd97d") if (awakened or i < lit_step) else Color(0.55, 0.88, 0.86, 0.58)
		var count: int = i + 1
		var start_x: float = -float(count - 1) * 1.5
		for n: int in count:
			_ground_fx.draw_rect(Rect2((b_pt + Vector2(start_x + float(n) * 3.0, 0.0)).round(), Vector2(2.0, 2.0)), lit_col)

	# Awakened luminous blessing circle on the mossy plateau floor
	if awakened or lit_step > 0:
		var ring_alpha: float = 0.65 + 0.2 * sin(_time * 2.2) if awakened else (0.22 * float(lit_step) / float(GUARDIAN_COUNT))
		var ring_col: Color = Color(0.52, 0.98, 0.90, ring_alpha).lerp(Color(1.0, 0.86, 0.48, ring_alpha), 0.45 if awakened else 0.0)
		var pts: PackedVector2Array = PackedVector2Array()
		var inner_rx: float = ring_rx * 0.54
		var inner_ry: float = ring_ry * 0.54
		for s: int in 49:
			var a: float = float(s) / 48.0 * TAU
			pts.append(Vector2(cos(a) * inner_rx, sin(a) * inner_ry))
		_ground_fx.draw_polyline(pts, ring_col, 1.5)
		if awakened:
			for r: int in 14:
				var ra: float = float(r) / 14.0 * TAU + _time * 0.35
				var rp: Vector2 = Vector2(cos(ra) * (inner_rx - 6.0), sin(ra) * (inner_ry - 4.0)).round()
				_ground_fx.draw_rect(Rect2(rp, Vector2(2.0, 2.0)), Color(1.0, 0.93, 0.68, 0.78))

	if _awaken_age < 3.0:
		var f: float = _awaken_age / 3.0
		var wave_rx: float = lerpf(12.0, ring_rx * 1.25, f)
		var wave_ry: float = lerpf(8.0, ring_ry * 1.25, f)
		var w_pts: PackedVector2Array = PackedVector2Array()
		for s2: int in 41:
			var a2: float = float(s2) / 40.0 * TAU
			w_pts.append(Vector2(cos(a2) * wave_rx, sin(a2) * wave_ry))
		_ground_fx.draw_polyline(w_pts, Color(1.0, 0.92, 0.62, (1.0 - f) * 0.85), 2.0)


class GuardianBrazier extends Interactable:
	var circle: SleepingGuardians
	var index: int = 0
	var lit: bool = false
	var _body: Sprite2D
	var _glow: Sprite2D
	var _light: NightLight

	func setup(owner_circle: SleepingGuardians, idx: int, local_pos: Vector2) -> void:
		circle = owner_circle
		index = idx
		position = local_pos

	func _ready() -> void:
		var off: Vector2 = Vector2(0.0, -(40.0 - 24.0)) ## anchor (20, 40) in 40x48 cell
		if ResourceLoader.exists(SleepingGuardians.BRAZIER_TEX):
			_body = Sprite2D.new()
			_body.texture = load(SleepingGuardians.BRAZIER_TEX) as Texture2D
			_body.hframes = 3
			_body.offset = off
			add_child(_body)
		if ResourceLoader.exists(SleepingGuardians.BRAZIER_GLOW):
			_glow = Sprite2D.new()
			_glow.texture = load(SleepingGuardians.BRAZIER_GLOW) as Texture2D
			_glow.hframes = 3
			_glow.offset = off
			_glow.material = Unlit.material()
			add_child(_glow)
		_light = NightLight.new()
		_light.position = Vector2(0.0, -18.0)
		_light.radius = 42
		_light.base_energy = 0.0
		_light.pulse = 0.14
		_light.glow_color = Color("7cf6e8")
		add_child(_light)
		set_lit(lit)

	func set_lit(on: bool) -> void:
		lit = on
		if _body != null:
			_body.frame = 1 if on else 0
		if _glow != null:
			_glow.frame = 1 if on else 0
			_glow.visible = on
		if _light != null:
			_light.base_energy = 0.55 if on else 0.0

	func is_interactable() -> bool:
		return circle != null and not circle.awakened and not lit and circle.carrier_peer != multiplayer.get_unique_id()

	func prompt() -> String:
		if not is_interactable():
			return ""
		return "OPFERSCHALE ENTZÜNDEN"

	func reach_distance(from: Vector2) -> float:
		return maxf(0.0, from.distance_to(global_position) - 18.0)

	func prompt_position() -> Vector2:
		return Vector2(0.0, -34.0)

	func interact(player: Player) -> void:
		if not is_interactable() or player == null or player.is_busy() or player.carry_stone != 0 or circle.wonders == null:
			return
		var dir: Vector2 = global_position - player.global_position
		var idx_capture: int = index
		var w_ref: MeadowWonders = circle.wonders
		player.begin_pick(dir, func() -> void:
			if w_ref != null:
				w_ref.request_light_guardian_brazier(idx_capture)
		)


class FallenHeadstone extends Interactable:
	var circle: SleepingGuardians
	var _body: Sprite2D
	var _glow: Sprite2D
	var _shown_prompt: String = ""

	func setup(owner_circle: SleepingGuardians, local_pos: Vector2) -> void:
		circle = owner_circle
		position = local_pos

	func _ready() -> void:
		var off: Vector2 = Vector2(0.0, -(40.0 - 24.0))
		if ResourceLoader.exists(SleepingGuardians.BRAZIER_TEX):
			_body = Sprite2D.new()
			_body.texture = load(SleepingGuardians.BRAZIER_TEX) as Texture2D
			_body.hframes = 3
			_body.frame = 2
			_body.offset = off
			add_child(_body)
		if ResourceLoader.exists(SleepingGuardians.BRAZIER_GLOW):
			_glow = Sprite2D.new()
			_glow.texture = load(SleepingGuardians.BRAZIER_GLOW) as Texture2D
			_glow.hframes = 3
			_glow.frame = 2
			_glow.offset = off
			_glow.material = Unlit.material()
			add_child(_glow)
		refresh_visibility()

	func refresh_visibility() -> void:
		var vis: bool = circle != null and not circle.head_restored and circle.carrier_peer == 0
		if _body != null:
			_body.visible = vis
		if _glow != null:
			_glow.visible = vis

	func _process(_delta: float) -> void:
		if circle != null and circle.carrier_peer != 0:
			var cp: Player = circle.player_of(circle.carrier_peer)
			if cp != null:
				global_position = (cp.global_position + cp.facing.normalized() * 14.0).round()
		if _prompt_node != null and _prompt_node.visible:
			var now: String = prompt()
			if now != _shown_prompt:
				_shown_prompt = now
				_prompt_node.show_text(now, "")

	func is_interactable() -> bool:
		if circle == null or circle.head_restored or circle.awakened:
			return false
		var me: int = multiplayer.get_unique_id()
		if circle.carrier_peer == me:
			# Yield focus to the broken guardian socket when standing right in front of it!
			if circle._broken_plinth != null and circle._broken_plinth.global_position.distance_to(global_position) < 38.0:
				return false
			return true
		return circle.carrier_peer == 0

	func prompt() -> String:
		if not is_interactable():
			return ""
		if circle.carrier_peer == multiplayer.get_unique_id():
			return "KOPFSTEIN ABLEGEN"
		return "KOPFSTEIN AUFHEBEN"

	func reach_distance(from: Vector2) -> float:
		if circle != null and circle.carrier_peer == multiplayer.get_unique_id():
			return 6.0
		return maxf(0.0, from.distance_to(global_position) - 18.0)

	func prompt_position() -> Vector2:
		return Vector2(0.0, -28.0)

	func interact(player: Player) -> void:
		if circle == null or circle.wonders == null or player == null or circle.awakened or circle.head_restored:
			return
		var me: int = player.name.to_int()
		if circle.carrier_peer == me:
			if player._carry_anim >= 0.0:
				return
			circle.wonders.request_drop_headstone(global_position - circle.global_position)
		elif circle.carrier_peer == 0 and player.carry_stone == 0 and not player.is_busy():
			circle.wonders.request_pick_headstone()


class BrokenGuardianSocket extends Interactable:
	var circle: SleepingGuardians

	func setup(owner_circle: SleepingGuardians, local_pos: Vector2) -> void:
		circle = owner_circle
		position = local_pos

	func is_interactable() -> bool:
		return circle != null and not circle.awakened and not circle.head_restored and circle.carrier_peer == multiplayer.get_unique_id()

	func prompt() -> String:
		if not is_interactable():
			return ""
		return "WÄCHTERHAUPT EINSETZEN"

	func reach_distance(from: Vector2) -> float:
		if is_interactable() and from.distance_to(global_position) <= 44.0:
			return 0.0
		return maxf(0.0, from.distance_to(global_position) - 28.0)

	func prompt_position() -> Vector2:
		return Vector2(0.0, -64.0)

	func interact(player: Player) -> void:
		if not is_interactable() or player == null or circle.wonders == null:
			return
		circle.wonders.request_restore_guardian_head()
