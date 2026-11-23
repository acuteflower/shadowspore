class_name MyceliumTether
extends Node2D
## Ecological Void-mycelium trip-thread (`T4`, `V5`) spun by an ambushing `ShadowSpider` between nearby rocks/trunks.
## - Nearly invisible dark-violet ankle filament (`#1a1030` / `#5c2fb8`) with 2 tiny glistening spore-dew droplets.
## - Walking through upright triggers `webbed` (`0.55 s`) and sends an instant biotremor alert to the owner spider!
## - Sneaking carefully (`sneak`), `ShadowStep`, or any weapon/sickle swing severs the thread cleanly with zero penalty!

signal tripped(world_pos: Vector2, player: Player)
signal severed(world_pos: Vector2)

const COL_OUTLINE: Color = Color("040208")
const COL_SILK: Color = Color("1a1030")
const COL_VEIN: Color = Color("5c2fb8")
const COL_DEW: Color = Color("cbaaff")

var anchor_a: Vector2 = Vector2.ZERO
var anchor_b: Vector2 = Vector2.ZERO
var owner_spider: Node2D = null

var _time: float = 0.0
var _broken: bool = false
var _snap_age: float = 0.0


func setup(from_world: Vector2, to_world: Vector2, spider: Node2D) -> void:
	anchor_a = from_world
	anchor_b = to_world
	owner_spider = spider
	global_position = (from_world + to_world) * 0.5
	z_index = -4
	material = Unlit.material()


func _process(delta: float) -> void:
	_time += delta
	if _broken:
		_snap_age += delta
		queue_redraw()
		if _snap_age >= 0.24:
			queue_free()
		return

	if owner_spider != null and not is_instance_valid(owner_spider):
		sever()
		return

	if multiplayer.is_server():
		_check_actors()
	queue_redraw()


func _check_actors() -> void:
	for player: Player in Player.all:
		if not is_instance_valid(player) or player.health.current <= 0.0:
			continue
		var ppos: Vector2 = player.global_position
		# Active weapon swing near the thread cuts it cleanly!
		if player.attack != null and player.attack.is_swinging():
			var tip_est: Vector2 = ppos + player.attack.aim_dir * 22.0
			if _seg_dist(tip_est, anchor_a, anchor_b) <= 14.0 or _seg_dist(ppos, anchor_a, anchor_b) <= 14.0:
				_rpc_sever.rpc(false, Vector2.ZERO, 0)
				return
		# ShadowStep passing across the thread snaps it harmlessly!
		if player._step_t >= 0.0 and _seg_dist(ppos, anchor_a, anchor_b) <= 12.0:
			_rpc_sever.rpc(false, Vector2.ZERO, 0)
			return
		# Airborne (`Vault` / `Ledge Hop`) clears the ankle-height thread!
		if player.air_height > 4.0:
			continue
		if _seg_dist(ppos, anchor_a, anchor_b) <= 6.5:
			if player.stealth != null and player.stealth.sneaking and player.velocity.length() < 48.0:
				continue ## Careful sneaking steps cleanly over the ankle filament!
			if player.effects != null:
				player.effects.apply("webbed", 0.65)
			tripped.emit(ppos, player)
			_rpc_sever.rpc(true, ppos, player.get_multiplayer_authority())
			return


@rpc("authority", "call_local", "reliable")
func _rpc_sever(was_tripped: bool, at_pos: Vector2, _peer_id: int) -> void:
	if _broken:
		return
	_broken = true
	_snap_age = 0.0
	Sfx.at(self, "spider_backstep", at_pos if was_tripped else global_position, -7.0)
	severed.emit(global_position)


func sever() -> void:
	if _broken:
		return
	if multiplayer.is_server() and is_inside_tree() and NetworkManager.rpc_ready(self):
		_rpc_sever.rpc(false, global_position, 0)
	else:
		_broken = true
		_snap_age = 0.0


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 <= 0.001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _draw() -> void:
	var la: Vector2 = anchor_a - global_position
	var lb: Vector2 = anchor_b - global_position
	var span: Vector2 = lb - la
	var length: float = span.length()
	if length < 4.0:
		return
	if _broken:
		var fade: float = clampf(1.0 - _snap_age / 0.24, 0.0, 1.0)
		var recoil: float = _snap_age * 42.0
		var dir: Vector2 = span / length
		for k: int in 5:
			var f: float = float(k) / 4.0
			var pa: Vector2 = (la + dir * (f * length * 0.35 - recoil * (1.0 - f))).round()
			var pb: Vector2 = (lb - dir * (f * length * 0.35 - recoil * (1.0 - f))).round()
			draw_rect(Rect2(pa, Vector2.ONE), Color(COL_DEW if k == 4 else COL_VEIN, fade * 0.85))
			draw_rect(Rect2(pb, Vector2.ONE), Color(COL_DEW if k == 4 else COL_VEIN, fade * 0.85))
		return

	var steps: int = maxi(6, roundi(length / 2.2))
	var pulse: float = 0.42 + 0.28 * sin(_time * 2.8)
	for i: int in range(steps + 1):
		var u: float = float(i) / float(steps)
		var sag: float = sin(u * PI) * (1.6 + 0.35 * sin(_time * 1.9))
		var p: Vector2 = (la.lerp(lb, u) + Vector2(0.0, sag - 3.0)).round()
		draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color(COL_OUTLINE, 0.38))
		var is_dew: bool = (i == steps / 3 or i == (steps * 2) / 3)
		var col: Color = COL_DEW if is_dew else (COL_VEIN if i % 4 == 0 else COL_SILK)
		var alpha: float = (0.72 * pulse) if is_dew else 0.56
		draw_rect(Rect2(p, Vector2.ONE), Color(col, alpha))
