class_name WardRing
extends Node2D
## A ring of ward stones (Bannsteine) round a house at the edge of the world (the lake witch's, docs/seehexe_konzept.md 3.3): half-sunk steles of the
## waystones' violet stone with grown crystal heads. Awake, the ring is a real circle of light the night respects like a lamp of the town
## (`TownManager.add_magic_light`: nothing is born inside, calm creatures keep out) and the Hexenwald's mist tells no lies inside it (`shelters`, asked by
## `StatusEffects._breathe_mist`). At night a band of light runs from stone to stone along the ground and breathes.
## Placed by `WorldLevel` from data/ground.json huts[].ring {center [x, y], radius, stones [[x, y, variant]], start_awake} (px from the hut's feet).
## Shared world state, host-authoritative: `set_awake` (host) -> `_rpc_state` on every peer, a joining peer gets a snapshot, the save keeps it
## (`SaveGame` key "ward_rings": {id: awake}). Art: tools/art_lake_hut.py -> ward.png (3 variants x dormant/awake) + ward_glow.png.
## The lake witch's quest (docs/seehexe_konzept.md 8): while the ring sleeps, the stones of `feed` can be fed one Seeglimmer each (`WardFeedSpot` E ->
## `request_feed`, host). After the second the void tears open at the coast and the `ambush` creatures climb out (shadow spiders and a listener, real fights);
## the last stone takes its glimmer only when they are gone; the third lights the whole ring. `fed`/`ambush` travel to every peer and to joiners; they are not
## saved (`LakeWitchStory` restores them from the host player's quest flags).

signal changed(awake: bool)
signal quest_changed ## `fed` or `ambush` changed (the lake witch's quest)

const AMBUSH_NONE: int = 0
const AMBUSH_RUNNING: int = 1
const AMBUSH_DONE: int = 2

const SHEET: String = "res://assets/interior/lake_hut/ward.png"
const GLOW: String = "res://assets/interior/lake_hut/ward_glow.png"
const FEET: float = 100.0 ## the sheet's ground row (frames 64 x 112)
const FRAME_H: float = 112.0
const TEAL: Color = Color("78f4e6")
const ANIMATE_RANGE: float = 640.0

static var _rings: Array[WardRing] = [] ## every ring in the tree (`shelters` asks them)

var id: String = ""
var radius: float = 150.0
var stones: Array = [] ## [Vector2 (local px), variant]
var awake: bool = true
var _sprites: Array[Sprite2D] = []
var _glows: Array[Sprite2D] = []
var _lights: Array[NightLight] = []
var _band: Node2D
var _time: float = 0.0
var _wake: float = 1.0 ## 0..1: how far the light has come back (the band grows from stone to stone)
var feed: Array[int] = [] ## indices of the weak stones the quest feeds
var fed: Array[int] = [] ## of those, the ones that took their glimmer (host decides, every peer knows)
var ambush: int = AMBUSH_NONE
var ambush_spec: Dictionary = {} ## {"spiders": [[x, y]], "listeners": [[x, y]]} px from the ring's middle
var _ambushers: Array[Node2D] = [] ## host: the creatures still standing


## Is `pos` inside an awake ring? (the Hexenwald's mist lies nowhere in here)
static func shelters(pos: Vector2) -> bool:
	for ring: WardRing in _rings:
		if is_instance_valid(ring) and ring.awake and ring.global_position.distance_to(pos) <= ring.radius:
			return true
	return false


static func by_id(tree: SceneTree, ring_id: String) -> WardRing:
	for node: Node in tree.get_nodes_in_group("ward_rings"):
		if (node as WardRing).id == ring_id:
			return node as WardRing
	return null


## Set up from the ring block of a hut (`center` is where this node stands; stone positions are made relative to it).
func setup(ring_id: String, spec: Dictionary, hut_feet: Vector2) -> void:
	id = ring_id
	var c: Array = spec.get("center", [0, 0]) as Array
	position = hut_feet + Vector2(float(c[0]), float(c[1]))
	radius = float(spec.get("radius", 150.0))
	awake = bool(spec.get("start_awake", true))
	_wake = 1.0 if awake else 0.0
	for raw: Variant in spec.get("stones", []) as Array:
		var s: Array = raw as Array
		stones.append([hut_feet + Vector2(float(s[0]), float(s[1])) - position, int(s[2])])
	for raw: Variant in spec.get("feed", []) as Array:
		feed.append(int(raw))
	ambush_spec = spec.get("ambush", {}) as Dictionary


func _ready() -> void:
	add_to_group("ward_rings")
	add_to_group("night_lights")
	_rings.append(self)
	y_sort_enabled = true
	var sheet: Texture2D = load(SHEET) as Texture2D
	var glow_sheet: Texture2D = load(GLOW) as Texture2D if ResourceLoader.exists(GLOW) else null
	_band = Node2D.new() ## the band of light on the ground (drawn below everything that stands)
	_band.name = "Band"
	_band.z_index = -3
	_band.material = Unlit.material()
	_band.draw.connect(_draw_band)
	add_child(_band)
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Stones"
	add_child(body)
	for i: int in stones.size():
		var at: Vector2 = stones[i][0] as Vector2
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = "Stone%d" % i
		sprite.texture = sheet
		sprite.hframes = 3
		sprite.vframes = 2
		sprite.offset = Vector2(0.0, FRAME_H / 2.0 - FEET)
		sprite.position = at
		add_child(sprite)
		_sprites.append(sprite)
		if glow_sheet != null:
			var glow: Sprite2D = Sprite2D.new()
			glow.texture = glow_sheet
			glow.hframes = 3
			glow.vframes = 2
			glow.offset = sprite.offset
			glow.material = Unlit.material()
			sprite.add_child(glow)
			_glows.append(glow)
		var light: NightLight = NightLight.new()
		light.position = at + Vector2(0, -6)
		light.radius = 46
		light.squash = 0.6
		light.base_energy = 0.5
		light.glow_color = TEAL
		light.pulse = 0.3
		add_child(light)
		_lights.append(light)
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = Vector2(20, 8)
		shape.shape = box
		shape.position = at + Vector2(0, -4)
		body.add_child(shape)
		if feed.has(i):
			var spot: WardFeedSpot = WardFeedSpot.new()
			spot.name = "Feed%d" % i
			spot.ring = self
			spot.index = i
			spot.position = at + Vector2(0, 6)
			add_child(spot)
	_show_state()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			_rpc_state.rpc_id(peer, awake, false)
			_rpc_quest.rpc_id(peer, PackedInt32Array(fed), ambush))


func _exit_tree() -> void:
	_rings.erase(self)
	TownManager.remove_magic_light(get_instance_id())


## Host: wake the ring (or let it go out). Everyone sees it; `animate` lets the light run from stone to stone.
func set_awake(on: bool, animate: bool = true) -> void:
	if not multiplayer.is_server():
		return
	_rpc_state.rpc(on, animate)


@rpc("authority", "call_local", "reliable")
func _rpc_state(on: bool, animate: bool) -> void:
	var was: bool = awake
	awake = on
	if not animate or not on:
		_wake = 1.0 if on else 0.0
	elif not was:
		_wake = 0.0 ## the light comes back stone by stone (`_process`), each one rings as it wakes
	_show_state()
	if was != on:
		changed.emit(on)


## Host: one weak stone takes the glimmer of the player `peer` (checked: the quest stone, in reach, a glimmer in her bag, the shadows gone before the last).
func request_feed(i: int) -> void:
	if multiplayer.is_server():
		_host_feed(i, multiplayer.get_unique_id())
	else:
		_rpc_request_feed.rpc_id(1, i)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_feed(i: int) -> void:
	if multiplayer.is_server():
		_host_feed(i, multiplayer.get_remote_sender_id())


func _host_feed(i: int, peer: int) -> void:
	if awake or not feed.has(i) or fed.has(i):
		return
	if fed.size() >= feed.size() - 1 and ambush != AMBUSH_DONE:
		return ## the last stone waits until the shadows are gone
	var player: Player = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and (node as Player).get_multiplayer_authority() == peer:
			player = node as Player
	if player == null or player.global_position.distance_to(to_global(stones[i][0] as Vector2)) > 70.0 or not player.inventory.has_item("lake_glimmer"):
		return
	player.inventory.remove_item("lake_glimmer", 1)
	fed.append(i)
	var start_ambush: bool = fed.size() == feed.size() - 1 and ambush == AMBUSH_NONE
	_rpc_quest.rpc(PackedInt32Array(fed), AMBUSH_RUNNING if start_ambush else ambush)
	if start_ambush:
		_spawn_ambush()
	if fed.size() >= feed.size():
		set_awake(true, true)


## Host: the void tears open at the coast and the shadows climb out (a real fight; each one is counted out when it dies or leaves the tree).
func _spawn_ambush() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("spawn_species"):
		_rpc_quest.rpc(PackedInt32Array(fed), AMBUSH_DONE)
		return
	_ambushers.clear()
	var kinds: Array = []
	for at: Variant in ambush_spec.get("spiders", []) as Array:
		kinds.append(["shadow_spider", at])
	for at: Variant in ambush_spec.get("listeners", []) as Array:
		kinds.append(["void_listener", at])
	for k: int in kinds.size():
		var spec: Array = kinds[k] as Array
		var a: Array = spec[1] as Array
		var pos: Vector2 = to_global(Vector2(float(a[0]), float(a[1])))
		var body: Node2D = world.call("spawn_species", String(spec[0]), pos, -PI / 2.0, 1.0, 1.0, true) as Node2D
		if body != null:
			_ambushers.append(body)
			body.tree_exiting.connect(_on_ambusher_gone.bind(body))
			var health: HealthComponent = _health_of(body)
			if health != null:
				health.died.connect(_on_ambusher_gone.bind(body))
	if _ambushers.is_empty():
		_rpc_quest.rpc(PackedInt32Array(fed), AMBUSH_DONE)


func _on_ambusher_gone(body: Node2D) -> void:
	if not multiplayer.is_server() or ambush != AMBUSH_RUNNING:
		return
	_ambushers.erase(body)
	var standing: int = 0
	for other: Node2D in _ambushers:
		if is_instance_valid(other) and not other.is_queued_for_deletion():
			var health: HealthComponent = _health_of(other)
			if health == null or health.current > 0.0:
				standing += 1
	if standing == 0:
		_rpc_quest.rpc(PackedInt32Array(fed), AMBUSH_DONE)


func _health_of(body: Node) -> HealthComponent:
	for child: Node in body.get_children():
		if child is HealthComponent:
			return child as HealthComponent
	return null


## Host: the quest state as it was (a loaded game, the developer jumps). `animate` false: no fights, no sounds.
func restore_quest(fed_now: Array[int], ambush_now: int) -> void:
	if multiplayer.is_server():
		_rpc_quest.rpc(PackedInt32Array(fed_now), ambush_now)


@rpc("authority", "call_local", "reliable")
func _rpc_quest(fed_now: PackedInt32Array, ambush_now: int) -> void:
	var before: int = fed.size()
	fed.clear()
	for i: int in fed_now:
		fed.append(i)
	var ambush_before: int = ambush
	ambush = ambush_now
	_show_state()
	if fed.size() > before and not fed.is_empty():
		_sound("ward_wake.wav", to_global(stones[fed[fed.size() - 1]][0] as Vector2))
	if fed.size() != before or ambush != ambush_before:
		quest_changed.emit()


func _show_state() -> void:
	for i: int in _sprites.size():
		var variant: int = int(stones[i][1])
		var lit: bool = (awake and _stone_lit(i)) or (not awake and fed.has(i))
		_sprites[i].frame = variant + (3 if lit else 0)
		if i < _glows.size():
			_glows[i].frame = _sprites[i].frame
		_lights[i].visible = lit
	if awake:
		TownManager.add_magic_light(get_instance_id(), Vector3(global_position.x, global_position.y, radius))
	else:
		TownManager.remove_magic_light(get_instance_id())
	_band.queue_redraw()


## While the light comes back, the stones wake one after another (in ring order).
func _stone_lit(i: int) -> bool:
	return _wake >= float(i + 1) / float(maxi(stones.size(), 1)) - 0.001


func _lit_count() -> int:
	var n: int = 0
	for i: int in stones.size():
		if _stone_lit(i):
			n += 1
	return n


func _sound(file: String, at: Vector2) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load("res://assets/audio/lake_hut/" + file) as AudioStream
	player.max_distance = 420.0
	player.volume_db = -6.0
	player.finished.connect(player.queue_free)
	get_parent().add_child(player)
	player.global_position = at
	player.play()


func set_night(_on: bool) -> void: ## (group night_lights: the glow follows `night_amount` every frame)
	pass


func export_state() -> bool:
	return awake


func import_state(on: bool) -> void:
	if multiplayer.is_server():
		_rpc_state.rpc(on, false)
	else:
		_rpc_state(on, false)


func _near_player() -> bool:
	for player: Player in Player.all:
		if is_instance_valid(player) and player.global_position.distance_squared_to(global_position) <= ANIMATE_RANGE * ANIMATE_RANGE:
			return true
	return Player.all.is_empty()


func _process(delta: float) -> void:
	_time += delta
	if awake and _wake < 1.0:
		var lit_before: int = _lit_count()
		_wake = minf(1.0, _wake + delta * 0.6)
		var lit_now: int = _lit_count()
		if lit_now != lit_before:
			_show_state()
			_sound("ward_ring.wav" if lit_now == stones.size() else "ward_wake.wav", global_position if lit_now == stones.size() else to_global(stones[maxi(lit_now - 1, 0)][0] as Vector2))
	if not _near_player():
		return
	var night: float = TimeManager.night_amount()
	for k: int in _glows.size():
		var beat: float = VoidGlow.beat(_time + float(k) * 0.37) if awake else 0.0
		_glows[k].modulate.a = lerpf(0.4, 1.0, night) * (0.85 + 0.15 * beat)
	_band.queue_redraw()


## The band: a bowed line of teal light on the ground from stone to stone (bulging outward, so the stones stand on one oval), two pixels wide with a
## dark seam, little runes set into it every few steps, the heartbeat running round the ring; faint by day, alive at night, only between awake stones.
var _runes: Array[PackedVector2Array] = [ ## (a var: packed arrays are not constant expressions)
	PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(0, 2), Vector2(1, 1), Vector2(2, 0), Vector2(2, 2)]),
	PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(1, 1), Vector2(1, 2)]),
	PackedVector2Array([Vector2(0, 2), Vector2(1, 1), Vector2(2, 0), Vector2(0, 0), Vector2(2, 2)]),
	PackedVector2Array([Vector2(1, 0), Vector2(0, 1), Vector2(2, 1), Vector2(1, 2), Vector2(1, 1)]),
]


func _draw_band() -> void:
	if stones.size() < 2 or not awake:
		return
	var night: float = TimeManager.night_amount()
	var base: float = lerpf(0.18, 0.85, night)
	var n: int = stones.size()
	var all_lit: bool = _lit_count() == n
	var mark: int = 0
	for i: int in n:
		var j: int = (i + 1) % n
		if not (_stone_lit(i) and _stone_lit(j)) and not all_lit:
			continue
		var a: Vector2 = stones[i][0] as Vector2
		var b: Vector2 = stones[j][0] as Vector2
		var mid: Vector2 = (a + b) * 0.5
		var bow: Vector2 = mid.normalized() * 16.0 * Vector2(1.0, 0.7) ## outward, flatter up and down (the ground is seen at a slant)
		var length: float = a.distance_to(b)
		var steps: int = int(length / 2.0)
		for s: int in range(2, steps - 1): ## leave the stones' feet free
			var t: float = float(s) / float(maxi(steps, 1))
			var p: Vector2 = a.lerp(b, t) + bow * (4.0 * t * (1.0 - t))
			var run: float = float(i) + t
			var pulse: float = 0.5 + 0.5 * sin(_time * 2.2 - run * 2.4)
			var alpha: float = base * (0.3 + 0.7 * pulse)
			var px: Vector2 = Vector2(roundf(p.x), roundf(p.y))
			if s % 12 == 6: ## a rune
				var rune: PackedVector2Array = _runes[(mark + i) % _runes.size()]
				mark += 1
				for q: Vector2 in rune:
					_band.draw_rect(Rect2(px + q - Vector2(1, 2), Vector2.ONE), Color(TEAL.lightened(0.35), minf(1.0, alpha * 1.4)))
				continue
			if (s + int(_time * 5.0)) % 7 == 0:
				alpha *= 0.35
			_band.draw_rect(Rect2(px, Vector2.ONE), Color(TEAL, alpha))
			_band.draw_rect(Rect2(px + Vector2(0, 1), Vector2.ONE), Color(TEAL.darkened(0.35), alpha * 0.55))
			if pulse > 0.85 and s % 3 == 0: ## sparks lifting off the band where the heartbeat passes
				_band.draw_rect(Rect2(px + Vector2(0, -2 - int(_time * 9.0 + s) % 4), Vector2.ONE), Color(TEAL.lightened(0.5), alpha * 0.7))
