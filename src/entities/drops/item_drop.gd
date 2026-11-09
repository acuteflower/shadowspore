class_name ItemDrop
extends Area2D
## An item lying on the ground. It pops out of the dead enemy in an arc (simulated the same on
## every peer from the spawn values), then glows in its rarity color and bobs. The host gives it
## to the first player who comes close: within a short range the item is drawn toward that player,
## gently at first, then faster, and taken in when it arrives. Only one person can take it.
## Rare items shoot a beam.

const LIFETIME: float = 60.0
const BLINK_TIME: float = 6.0
const PICKUP_DELAY: float = 0.6
const GRAVITY: float = 520.0
const NAME_RANGE: float = 56.0
const BEAM_FROM_RARITY: int = 2 ## rare and above
const MAGNET_RADIUS: float = 24.0 ## a player this close (with room in the bag) draws the item in
const MAGNET_LOSE_RADIUS: float = 64.0 ## the pull lets go when the player gets farther away than this
const PULL_ACCEL: float = 420.0 ## px/s²: starts slow, then speeds up
const PULL_MAX_SPEED: float = 240.0
const PICKUP_REACH: float = 5.0 ## it is taken in this close to the player
const PULL_LIFT: float = 18.0 ## px the item rises toward chest height on its way in
const MERGE_RADIUS: float = 44.0 ## landed drops of the same item this close become one stack
const BAYER: Array = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

@export var story_id: String = ""
@export var story_owner: int = 0
@export var item_id: String = ""
@export var count: int = 1
@export var refine: int = 0 ## a thrown refined weapon keeps its level ...
@export var refine_pity: int = 0 ## ... and its Glut
@export var launch: Vector2 = Vector2.ZERO ## horizontal speed of the pop

var _age: float = 0.0
var _height: float = 0.0
var _vz: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _bounces: int = 0
var _landed: bool = false
var _rarity_index: int = 0
var _rarity_color: Color = Color.WHITE
var _stack: Dictionary = {}
var _label: String = ""
var _merged: bool = false ## host: already folded into another drop
var _hop: float = 0.0 ## 1 right after absorbing another drop, then fades
var _puller: int = 0 ## peer id of the player it is drawn to, 0 = lying still
var _pull_speed: float = 0.0


func _ready() -> void:
	material = Unlit.material() ## loot stays easy to spot at night
	_stack = {"id": item_id, "count": count}
	if refine > 0:
		_stack[RefineRules.KEY_LEVEL] = refine
	if refine_pity > 0:
		_stack[RefineRules.KEY_PITY] = refine_pity
	var def: Dictionary = Items.definition(_stack)
	_label = Items.title(_stack)
	_rarity_color = Items.rarity_color(_stack)
	_rarity_index = DataRegistry.table("rarities").keys().find(String(def.get("rarity", "common")))
	_velocity = launch
	_vz = 130.0 + launch.length() * 0.8


func _physics_process(delta: float) -> void:
	_age += delta
	if not _landed:
		_velocity = _velocity.move_toward(Vector2.ZERO, 40.0 * delta)
		position += _velocity * delta
		_vz -= GRAVITY * delta
		_height += _vz * delta
		if _height <= 0.0:
			_height = 0.0
			if _bounces < 1:
				_bounces += 1
				_vz = absf(_vz) * 0.35
			else:
				_landed = true
	_hop = move_toward(_hop, 0.0, 4.0 * delta)
	if _puller != 0:
		_pull(delta)
	queue_redraw()
	if multiplayer.is_server():
		_host_tick()


func _host_tick() -> void:
	if _age >= LIFETIME and story_id == "":
		queue_free()
		return
	if not _landed or _age < PICKUP_DELAY:
		return
	if _try_merge():
		return
	if _puller != 0: ## being drawn in: let go if the player left, take it in on arrival
		var target: Player = _player_by_id(_puller)
		if target == null or target.health.current <= 0.0 or target.global_position.distance_to(global_position) > MAGNET_LOSE_RADIUS:
			_set_puller.rpc(0)
		elif target.global_position.distance_to(global_position) <= PICKUP_REACH:
			_collect(target)
		return
	for player: Player in Player.all:
		if (story_owner != 0 and player.name.to_int() != story_owner) or player.health.current <= 0.0 or not player.inventory.has_room(item_id):
			continue
		if player.global_position.distance_to(global_position) <= MAGNET_RADIUS:
			_set_puller.rpc(player.name.to_int())
			return


## Host: hands the stack to the player; a full bag leaves what does not fit lying there.
func _collect(player: Player) -> void:
	var left: int = player.inventory.give(item_id, count, Items.extras(_stack))
	if left < count:
		if story_id == "knight_sword":
			var world: Node = get_tree().get_first_node_in_group("world")
			if world is WorldLevel and (world as WorldLevel).fallen_knight != null:
				(world as WorldLevel).fallen_knight.sword_taken(player.name.to_int())
		_picked.rpc(player.name.to_int(), count - left, left)
		if left == 0:
			queue_free()
			return
	_set_puller.rpc(0)


@rpc("authority", "call_local", "reliable")
func _set_puller(player_id: int) -> void:
	_puller = player_id
	_pull_speed = 0.0


## Every peer: glide toward the player the host picked, slowly at first, rising to chest height.
func _pull(delta: float) -> void:
	var target: Player = _player_by_id(_puller)
	if target == null:
		return
	var to: Vector2 = target.global_position - global_position
	_pull_speed = minf(_pull_speed + PULL_ACCEL * delta, PULL_MAX_SPEED)
	position += to.normalized() * minf(_pull_speed * delta, to.length())
	var near: float = 1.0 - clampf(to.length() / MAGNET_RADIUS, 0.0, 1.0)
	_height = move_toward(_height, PULL_LIFT * near, 70.0 * delta)


func _player_by_id(player_id: int) -> Player:
	for player: Player in Player.all:
		if player.name.to_int() == player_id:
			return player
	return null


## Host: folds this drop into a landed drop of the same item nearby, if the stack limit allows.
func _try_merge() -> bool:
	if story_id != "" or refine > 0 or refine_pity > 0:
		return false
	if _merged:
		return true
	var limit: int = Items.max_stack(_stack)
	for node: Node in get_parent().get_children():
		var other: ItemDrop = node as ItemDrop
		if other == null or other.story_id != "" or other == self or other._merged or not other._landed or other.item_id != item_id:
			continue
		if other.refine != refine or other.refine_pity != refine_pity:
			continue ## a refined weapon is its own piece
		if other.position.distance_to(position) > MERGE_RADIUS or other.count + count > limit:
			continue
		_merged = true
		other._absorb(count)
		queue_free()
		return true
	return false


func _absorb(extra: int) -> void:
	count += extra
	_set_count.rpc(count)


@rpc("authority", "call_local", "reliable")
func _set_count(new_count: int) -> void:
	count = new_count
	_hop = 1.0


@rpc("authority", "call_local", "reliable")
func _picked(player_id: int, taken: int, remaining: int) -> void:
	for player: Player in Player.all:
		if player.name.to_int() == player_id:
			DamageNumber.spawn_text(get_tree().current_scene, player.global_position + Vector2(0, -58),
				"+%d %s" % [taken, _label], _rarity_color)
	count = remaining


func _near_local_player() -> bool:
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.global_position.distance_to(global_position) < NAME_RANGE:
			return true
	return false


func _draw() -> void:
	if _age > LIFETIME - BLINK_TIME and int(_age * 8.0) % 2 == 0:
		return
	var lift: float = _height + 7.0 + (sin(_age * 3.0) * 1.5 if _landed else 0.0) + sin(_hop * PI) * 6.0
	_ellipse(6.0, 2.5, Color(0, 0, 0, 0.3), 1.0)
	_ellipse(9.0, 4.5, Color(_rarity_color, 0.4), 0.3 + 0.12 * sin(_age * 3.0)) ## pulsing aura on the ground
	if _rarity_index >= BEAM_FROM_RARITY:
		var width: int = 4 if _rarity_index >= 4 else 2
		for y: int in 28:
			draw_rect(Rect2(-width / 2.0, -y - 1, width, 1), Color(_rarity_color, (1.0 - y / 28.0) * 0.55 * (0.8 + 0.2 * sin(_age * 4.0))))
		for k: int in 3: ## sparks rising along the beam
			var phase: float = fposmod(_age * 0.8 + k / 3.0, 1.0)
			draw_rect(Rect2(roundf(sin(k * 7.0 + 1.0) * 5.0), roundf(-phase * 24.0), 1, 1), Color(_rarity_color.lightened(0.5), 1.0 - phase))
	var icon: Texture2D = Items.icon(_stack)
	if icon:
		draw_texture(icon, Vector2(-8, -lift - 14))
	if _rarity_index >= BEAM_FROM_RARITY or _near_local_player():
		var text: String = _label if count <= 1 else "%s x%d" % [_label, count]
		PixelText.draw(self, text, Vector2i(-PixelText.width(text) / 2, int(-lift) - 26), _rarity_color, UiStyle.OUTLINE)


## Dithered pixel ellipse on the ground; `strength` 0..1 sets how many pixels are filled.
func _ellipse(rx: float, ry: float, color: Color, strength: float) -> void:
	if strength >= 1.0:
		for y: int in range(-ceili(ry), ceili(ry) + 1):
			var half: float = rx * sqrt(maxf(1.0 - pow(y / ry, 2.0), 0.0))
			var w: int = floori(half) * 2 + 1
			if w > 0:
				draw_rect(Rect2(-floori(half), y, w, 1), color)
		return
	for y: int in range(-ceili(ry), ceili(ry) + 1):
		var half: float = rx * sqrt(maxf(1.0 - pow(y / ry, 2.0), 0.0))
		for x: int in range(-floori(half), floori(half) + 1):
			if BAYER[posmod(y, 4)][posmod(x, 4)] < strength * 16.0:
				draw_rect(Rect2(x, y, 1, 1), color)
