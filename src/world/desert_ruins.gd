class_name DesertRuins
extends Node2D
## Active scattered quartz ruins across Sonnenquarz-Öde (docs/quarzwueste_konzept.md Stufe 4b):
## - QuartzArch: broken sandstone-and-quartz gates that cast real daytime canopy shade ("day_canopies") and flare at night / on spells.
## - LightConduit: half-buried stone channels that catch nearby spell casts or Arcane Quartz Storm bolts and race a turquoise-gold pulse along the sand.
## - ResonanceObelisk: Harmonic obelisks (0..1, +35%..+60% spell crystal recharge) & Overcharged obelisks (2..3, periodic expanding Prism Rings).
## - QuartzSeal: dormant ancient rune circles whose 4 cardinal rune sockets or conduit pulses awaken a buried desert LootChest.

const ARCH_TEX: Texture2D = preload("res://assets/props/quartz_arch.png")
const ARCH_GLOW: Texture2D = preload("res://assets/props/quartz_arch_glow.png")
const OBELISK_TEX: Texture2D = preload("res://assets/props/resonance_obelisk.png")
const OBELISK_GLOW: Texture2D = preload("res://assets/props/resonance_obelisk_glow.png")
const CONDUIT_TEX: Texture2D = preload("res://assets/props/light_conduit.png")
const CONDUIT_GLOW: Texture2D = preload("res://assets/props/light_conduit_glow.png")
const SEAL_TEX: Texture2D = preload("res://assets/props/quartz_seal.png")
const SEAL_GLOW: Texture2D = preload("res://assets/props/quartz_seal_glow.png")

const DESERT_CHUNK_X0: int = 19 ## tile 608
const DESERT_CHUNK_X1: int = 34 ## tile 1088
const DESERT_CHUNK_Y0: int = 1 ## tile 32
const DESERT_CHUNK_Y1: int = 11 ## tile 352

var world: WorldLevel
var _sites_by_chunk: Dictionary = {} ## Vector2i(chunk) -> Dictionary site spec
var _live_chunks: Dictionary = {} ## Vector2i(chunk) -> Array[Node]
var _awakened_seals: Dictionary = {} ## String(seal_id) -> true
var _masonry_props: Array[Dictionary] = [] ## {cell, kind: "ruin_sandstone", variant} bundled exclusively inside ruin ensembles


static func of(tree: SceneTree) -> DesertRuins:
	return tree.get_first_node_in_group("desert_ruins") as DesertRuins


func extra_masonry() -> Array[Dictionary]:
	return _masonry_props


func setup(level: WorldLevel, prior_blocked: Dictionary) -> Dictionary:
	world = level
	z_index = -8
	_sites_by_chunk.clear()
	_masonry_props.clear()
	var ruin_blocked: Dictionary = {}
	var seed_base: int = level._map.world_seed
	for cy: int in range(DESERT_CHUNK_Y0, DESERT_CHUNK_Y1 + 1):
		for cx: int in range(DESERT_CHUNK_X0, DESERT_CHUNK_X1 + 1):
			var chunk_cell: Vector2i = Vector2i(cx, cy)
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = hash(Vector4i(cx, cy, seed_base, 9417))
			var site: Dictionary = _plan_chunk_site(chunk_cell, rng, prior_blocked)
			if site.is_empty():
				continue
			_sites_by_chunk[chunk_cell] = site
			for bcell_v: Variant in site.get("blocked", []) as Array:
				ruin_blocked[bcell_v as Vector2i] = true
			for m_v: Variant in site.get("masonry", []) as Array:
				_masonry_props.append(m_v as Dictionary)
	return ruin_blocked


func _ready() -> void:
	add_to_group("desert_ruins")
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void:
			_rpc_snapshot.rpc_id(peer, PackedStringArray(_awakened_seals.keys())))


func site_count() -> int:
	return _sites_by_chunk.size()


func sites() -> Dictionary:
	return _sites_by_chunk


func is_seal_awake(seal_id: String) -> bool:
	return _awakened_seals.has(seal_id)


func export_state() -> Array:
	return _awakened_seals.keys()


func import_state(saved: Array) -> void:
	_awakened_seals.clear()
	for entry: Variant in saved:
		_awakened_seals[String(entry)] = true
	for nodes_v: Variant in _live_chunks.values():
		for n: Node in nodes_v as Array:
			if n is QuartzSeal and _awakened_seals.has((n as QuartzSeal).seal_id):
				(n as QuartzSeal).set_awake_instant()


func _plan_chunk_site(chunk_cell: Vector2i, rng: RandomNumberGenerator, prior_blocked: Dictionary) -> Dictionary:
	var base_tile: Vector2i = chunk_cell * WorldLevel.CHUNK
	for _attempt: int in 8:
		var tx: int = base_tile.x + rng.randi_range(7, WorldLevel.CHUNK - 8)
		var ty: int = base_tile.y + rng.randi_range(7, WorldLevel.CHUNK - 8)
		var center_tile: Vector2i = Vector2i(tx, ty)
		if not world._generator.is_desert_bare(center_tile):
			continue
		var pos: Vector2 = Vector2(tx, ty) * 16.0 + Vector2(8.0, 8.0)
		var arid: float = BiomeBlend.arid_at(pos)
		var oasis: float = BiomeBlend.oasis_at(pos)
		if arid < 0.54 or oasis >= 0.14 or BiomeBlend.is_quartz_surface(pos):
			continue
		# Every ruin is a full architectural ensemble: frequent in Region 34 (Ruinenfeld), moderate in Region 33, rare border shrines in Region 32
		var chance: float = 0.54 if tx >= 835 else (0.30 if arid >= 0.72 else 0.14)
		if rng.randf() >= chance:
			return {}
		if not world._relief.flat_around(pos, 74.0):
			continue
		if world._rivers != null and not world._rivers.clear_for_prop(pos, 82.0):
			continue
		var clash: bool = false
		for dy: int in range(-5, 6):
			for dx: int in range(-5, 6):
				var c: Vector2i = center_tile + Vector2i(dx, dy)
				if prior_blocked.has(c) or world._stone_cells.has(c):
					clash = true
					break
			if clash:
				break
		if clash:
			continue

		var kind: String = "gate_courtyard"
		if tx >= 835:
			var roll_r34: float = rng.randf()
			kind = "sanctum_seal" if roll_r34 < 0.34 else ("shrine_ensemble" if roll_r34 < 0.68 else "gate_courtyard")
		elif arid >= 0.72:
			var roll_r33: float = rng.randf()
			kind = "sanctum_seal" if roll_r33 < 0.22 else ("shrine_ensemble" if roll_r33 < 0.58 else "gate_courtyard")

		var arch_var: int = rng.randi() % 3
		var obelisk_var: int = (2 + rng.randi() % 2) if (tx >= 835 and rng.randf() < 0.52) or (arid >= 0.75 and rng.randf() < 0.36) else (rng.randi() % 2)
		var obelisk_var_b: int = rng.randi() % 2 if obelisk_var >= 2 else (2 + rng.randi() % 2 if tx >= 850 and rng.randf() < 0.4 else rng.randi() % 2)
		var seal_var: int = rng.randi() % 2

		# Clear the entire 11x11-tile courtyard of random cacti/rocks so the ensemble reads cleanly
		var blocked: Array[Vector2i] = []
		for dy2: int in range(-5, 6):
			for dx2: int in range(-5, 6):
				blocked.append(center_tile + Vector2i(dx2, dy2))

		# Bundled architectural `ruin_sandstone` corner piers & colonnade blocks around this ruin courtyard ONLY
		var corner_offsets: Array[Vector2i] = [
			Vector2i(-3, -2),
			Vector2i(3, -2),
			Vector2i(-3, 2),
			Vector2i(3, 2),
		]
		if kind == "shrine_ensemble":
			corner_offsets = [
				Vector2i(-4, -2),
				Vector2i(4, -2),
				Vector2i(-4, 2),
				Vector2i(4, 2),
			]
		elif kind == "sanctum_seal":
			corner_offsets = [
				Vector2i(-4, -3),
				Vector2i(4, -3),
				Vector2i(-4, 3),
				Vector2i(4, 3),
			]
		var skip_idx: int = rng.randi() % 5 ## 0..3 leaves 1 weathered corner missing; 4 keeps all 4 corners intact
		var masonry: Array[Dictionary] = []
		for ci: int in corner_offsets.size():
			if ci == skip_idx:
				continue
			var m_cell: Vector2i = center_tile + corner_offsets[ci]
			var m_pos: Vector2 = Vector2(m_cell) * 16.0 + Vector2(8.0, 8.0)
			if world._relief.flat_around(m_pos, 18.0) and not BiomeBlend.is_quartz_surface(m_pos):
				masonry.append({
					"cell": m_cell,
					"kind": "ruin_sandstone",
					"variant": (ci + arch_var) % 4,
				})

		return {
			"chunk": chunk_cell,
			"tile": center_tile,
			"pos": pos,
			"kind": kind,
			"arch_var": arch_var,
			"obelisk_var": obelisk_var,
			"obelisk_var_b": obelisk_var_b,
			"seal_var": seal_var,
			"tier": "rare" if tx >= 850 and rng.randf() < 0.45 else "common",
			"blocked": blocked,
			"masonry": masonry,
		}
	return {}


func populate_chunk(chunk_cell: Vector2i) -> void:
	if _live_chunks.has(chunk_cell) or not _sites_by_chunk.has(chunk_cell):
		return
	var spec: Dictionary = _sites_by_chunk[chunk_cell] as Dictionary
	var spawned: Array[Node] = _spawn_site(spec)
	_live_chunks[chunk_cell] = spawned


func free_chunk(chunk_cell: Vector2i) -> void:
	if not _live_chunks.has(chunk_cell):
		return
	var list: Array = _live_chunks[chunk_cell] as Array
	_live_chunks.erase(chunk_cell)
	for node_v: Variant in list:
		var n: Node = node_v as Node
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()


func _spawn_site(spec: Dictionary) -> Array[Node]:
	var out: Array[Node] = []
	var pos: Vector2 = spec.pos as Vector2
	var kind: String = String(spec.kind)
	var props_parent: Node2D = world._props if world != null and world._props != null else self
	var tile: Vector2i = spec.tile as Vector2i

	match kind:
		"gate_courtyard":
			# Cohesive Sun-Gate Courtyard: northern QuartzArch + continuous N-S LightConduit + central-south ResonanceObelisk (+ flanking corner masonry via extra_props)
			var arch: QuartzArch = QuartzArch.new()
			arch.setup(pos + Vector2(0.0, -26.0), int(spec.arch_var))
			props_parent.add_child(arch)
			out.append(arch)

			var ob: ResonanceObelisk = ResonanceObelisk.new()
			ob.setup(pos + Vector2(0.0, 28.0), int(spec.obelisk_var))
			props_parent.add_child(ob)
			out.append(ob)

			var cond: LightConduit = LightConduit.new()
			cond.setup(pos + Vector2(0.0, -22.0), pos + Vector2(0.0, 24.0), true)
			cond.target_node = ob
			arch.linked_conduit = cond
			add_child(cond)
			out.append(cond)

		"shrine_ensemble":
			# Cohesive Twin-Obelisk Resonance Shrine: northern QuartzArch + T-junction LightConduits feeding left & right ResonanceObelisks
			var arch2: QuartzArch = QuartzArch.new()
			arch2.setup(pos + Vector2(0.0, -24.0), int(spec.arch_var))
			props_parent.add_child(arch2)
			out.append(arch2)

			var ob_l: ResonanceObelisk = ResonanceObelisk.new()
			ob_l.setup(pos + Vector2(-44.0, 18.0), int(spec.obelisk_var))
			props_parent.add_child(ob_l)
			out.append(ob_l)

			var ob_r: ResonanceObelisk = ResonanceObelisk.new()
			ob_r.setup(pos + Vector2(44.0, 18.0), int(spec.obelisk_var_b))
			props_parent.add_child(ob_r)
			out.append(ob_r)

			var cond_stem: LightConduit = LightConduit.new()
			cond_stem.setup(pos + Vector2(0.0, -20.0), pos + Vector2(0.0, 16.0), false)
			add_child(cond_stem)
			out.append(cond_stem)

			var cond_l: LightConduit = LightConduit.new()
			cond_l.setup(pos + Vector2(0.0, 16.0), pos + Vector2(-40.0, 16.0), true)
			cond_l.target_node = ob_l
			add_child(cond_l)
			out.append(cond_l)

			var cond_r: LightConduit = LightConduit.new()
			cond_r.setup(pos + Vector2(0.0, 16.0), pos + Vector2(40.0, 16.0), true)
			cond_r.target_node = ob_r
			add_child(cond_r)
			out.append(cond_r)

			cond_stem.chained_conduits = [cond_l, cond_r]
			arch2.linked_conduit = cond_stem

		"sanctum_seal":
			# Cohesive Sunken Seal Sanctum: northern QuartzArch + central QuartzSeal + twin W & E ResonanceObelisks linked inward by straight LightConduits
			var arch3: QuartzArch = QuartzArch.new()
			arch3.setup(pos + Vector2(0.0, -40.0), int(spec.arch_var))
			props_parent.add_child(arch3)
			out.append(arch3)

			var seal_id: String = "desert_seal_%d_%d" % [tile.x, tile.y]
			var seal: QuartzSeal = QuartzSeal.new()
			seal.setup(self, seal_id, pos, int(spec.seal_var), String(spec.tier))
			if _awakened_seals.has(seal_id):
				seal.set_awake_instant()
			add_child(seal)
			out.append(seal)

			var ob_w: ResonanceObelisk = ResonanceObelisk.new()
			ob_w.setup(pos + Vector2(-54.0, 2.0), int(spec.obelisk_var))
			props_parent.add_child(ob_w)
			out.append(ob_w)

			var ob_e: ResonanceObelisk = ResonanceObelisk.new()
			ob_e.setup(pos + Vector2(54.0, 2.0), int(spec.obelisk_var_b))
			props_parent.add_child(ob_e)
			out.append(ob_e)

			var cond_w: LightConduit = LightConduit.new()
			cond_w.setup(pos + Vector2(-50.0, 0.0), pos + Vector2(-24.0, 0.0), true)
			cond_w.target_node = seal
			ob_w.linked_conduit = cond_w
			add_child(cond_w)
			out.append(cond_w)

			var cond_e: LightConduit = LightConduit.new()
			cond_e.setup(pos + Vector2(50.0, 0.0), pos + Vector2(24.0, 0.0), true)
			cond_e.target_node = seal
			ob_e.linked_conduit = cond_e
			add_child(cond_e)
			out.append(cond_e)

			var cond_n: LightConduit = LightConduit.new()
			cond_n.setup(pos + Vector2(0.0, -38.0), pos + Vector2(0.0, -22.0), true)
			cond_n.target_node = seal
			arch3.linked_conduit = cond_n
			add_child(cond_n)
			out.append(cond_n)
	return out


func host_awaken_seal(seal_id: String, tier_name: String, at: Vector2) -> void:
	if not multiplayer.is_server() or _awakened_seals.has(seal_id):
		return
	if multiplayer.get_peers().is_empty():
		_rpc_awaken_seal(seal_id, tier_name, at)
	else:
		_rpc_awaken_seal.rpc(seal_id, tier_name, at)


@rpc("authority", "call_local", "reliable")
func _rpc_awaken_seal(seal_id: String, tier_name: String, at: Vector2) -> void:
	_awakened_seals[seal_id] = true
	for nodes_v: Variant in _live_chunks.values():
		for n: Node in nodes_v as Array:
			if n is QuartzSeal and (n as QuartzSeal).seal_id == seal_id:
				(n as QuartzSeal).play_awaken_fx()
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		chests.appear(seal_id, tier_name, at, true, false, true)


@rpc("authority", "reliable")
func _rpc_snapshot(awake_ids: PackedStringArray) -> void:
	for sid: String in awake_ids:
		_awakened_seals[sid] = true
	for nodes_v: Variant in _live_chunks.values():
		for n: Node in nodes_v as Array:
			if n is QuartzSeal and _awakened_seals.has((n as QuartzSeal).seal_id):
				(n as QuartzSeal).set_awake_instant()


# =============================================================================
# 1. Gebrochener Quarz-Torbogen (`QuartzArch`)
# =============================================================================
class QuartzArch extends Node2D:
	var variant: int = 0
	var _sprite: Sprite2D
	var _glow: Sprite2D
	var _flare: float = 0.0
	var _night: float = 0.0
	var linked_conduit: LightConduit

	func setup(world_pos: Vector2, arch_variant: int) -> void:
		position = world_pos
		variant = clampi(arch_variant, 0, 2)
		name = "QuartzArch_%d_%d" % [int(world_pos.x), int(world_pos.y)]

	func _ready() -> void:
		add_to_group("day_canopies")
		add_to_group("night_lights")
		add_to_group("desert_spell_listeners")
		add_to_group("desert_arcane_listeners")

		_sprite = Sprite2D.new()
		_sprite.texture = ARCH_TEX
		_sprite.hframes = 3
		_sprite.frame = variant
		_sprite.centered = false
		_sprite.offset = Vector2(-48.0, -82.0)
		_sprite.material = WorldProp._day_material()
		add_child(_sprite)

		_glow = Sprite2D.new()
		_glow.texture = ARCH_GLOW
		_glow.hframes = 3
		_glow.frame = variant
		_glow.centered = false
		_glow.offset = _sprite.offset
		_glow.material = Unlit.material()
		_sprite.add_child(_glow)

		# Two pier colliders so Ellie & wildlife can walk cleanly under the arch span
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for px_x: float in [-28.0, 28.0]:
			var cs: CollisionShape2D = CollisionShape2D.new()
			var rect: RectangleShape2D = RectangleShape2D.new()
			rect.size = Vector2(14.0, 8.0)
			cs.shape = rect
			cs.position = Vector2(px_x, -4.0)
			body.add_child(cs)
		add_child(body)
		set_night(TimeManager.night_amount())

	## Casts real SE daytime ground shadow in `DaylightField` & cools Ellie (`DesertHeat.is_in_shade`).
	func day_canopy() -> Vector4:
		var rx: float = 34.0 if variant != 1 else 26.0
		var ry: float = 19.0
		return Vector4(global_position.x + 12.0, global_position.y - 8.0, rx, ry)

	func set_night(amount: float) -> void:
		_night = amount
		_update_glow()

	func _update_glow() -> void:
		if _glow != null:
			_glow.modulate.a = clampf(lerpf(0.24, 0.96, _night) + _flare * 0.75, 0.0, 1.0)

	func _process(delta: float) -> void:
		if _flare > 0.0:
			_flare = maxf(0.0, _flare - delta * 1.4)
			_update_glow()

	func on_spell_cast(caster_pos: Vector2, target_pos: Vector2, _spell_id: String) -> void:
		if global_position.distance_to(caster_pos) <= 96.0 or global_position.distance_to(target_pos) <= 96.0:
			_flare = 1.0
			_update_glow()
			if is_instance_valid(linked_conduit):
				linked_conduit.trigger_pulse()

	func on_arcane_lightning(strike_pos: Vector2, _info: Dictionary = {}) -> void:
		if global_position.distance_to(strike_pos) <= 130.0:
			_flare = 1.0
			_update_glow()
			if is_instance_valid(linked_conduit):
				linked_conduit.trigger_pulse()


# =============================================================================
# 2. Lichtleit-Rinne (`LightConduit`)
# =============================================================================
class LightConduit extends Node2D:
	var start_pos: Vector2 = Vector2.ZERO
	var end_pos: Vector2 = Vector2.ZERO
	var has_hub: bool = false
	var target_node: Node2D
	var chained_conduits: Array[LightConduit] = []
	var _segments: Array[Sprite2D] = []
	var _glows: Array[Sprite2D] = []
	var _seg_points: PackedVector2Array = PackedVector2Array()
	var _pulse_t: float = -1.0 ## -1 = idle, 0..1 = travelling from start_pos to end_pos
	var _cooldown: float = 0.0
	var _night: float = 0.0
	var _spark_overlay: Node2D

	func setup(from_world: Vector2, to_world: Vector2, start_hub: bool = false) -> void:
		position = from_world
		start_pos = from_world
		end_pos = to_world
		has_hub = start_hub
		name = "LightConduit_%d_%d" % [int(from_world.x), int(from_world.y)]

	func _ready() -> void:
		add_to_group("night_lights")
		add_to_group("desert_spell_listeners")
		add_to_group("desert_arcane_listeners")
		var delta_v: Vector2 = end_pos - start_pos
		var dist: float = maxf(delta_v.length(), 18.0)
		var dir: Vector2 = delta_v / dist
		var frame_idx: int = 0
		if absf(dir.x) > 0.38 and absf(dir.y) > 0.38:
			frame_idx = 2
		elif absf(dir.y) > absf(dir.x):
			frame_idx = 1
		# Tight edge-to-edge masonry step so stone gutters butt seamlessly into one carved channel
		var tile_step: float = 15.0 if frame_idx == 1 else (19.0 if frame_idx == 0 else 17.0)
		var count: int = clampi(ceili(dist / tile_step), 2, 7)
		for i: int in count:
			var f: float = float(i) / float(maxi(count - 1, 1)) if count > 1 else 0.5
			var local_p: Vector2 = delta_v * f
			_seg_points.append(local_p)
			var sp: Sprite2D = Sprite2D.new()
			sp.texture = CONDUIT_TEX
			sp.hframes = 4
			sp.frame = 3 if (i == 0 and has_hub) else frame_idx
			if frame_idx == 2 and dir.x * dir.y < 0.0:
				sp.flip_h = true
			sp.position = local_p
			add_child(sp)
			_segments.append(sp)

			var gl: Sprite2D = Sprite2D.new()
			gl.texture = CONDUIT_GLOW
			gl.hframes = 4
			gl.frame = sp.frame
			gl.flip_h = sp.flip_h
			gl.material = Unlit.material()
			sp.add_child(gl)
			_glows.append(gl)

		_spark_overlay = ConduitSparkDraw.new()
		(_spark_overlay as ConduitSparkDraw).owner_conduit = self
		_spark_overlay.material = Unlit.material()
		_spark_overlay.z_index = 2
		add_child(_spark_overlay)
		set_night(TimeManager.night_amount())

	func set_night(amount: float) -> void:
		_night = amount
		_refresh_glows()

	func is_pulsing() -> bool:
		return _pulse_t >= 0.0

	func trigger_pulse() -> void:
		if _cooldown > 0.0 or _pulse_t >= 0.0:
			return
		_pulse_t = 0.0
		_cooldown = 0.9
		Sfx.at(self, "conduit_pulse", global_position, -4.0, 0.07)

	func on_spell_cast(caster_pos: Vector2, target_pos: Vector2, _spell_id: String) -> void:
		for p: Vector2 in [start_pos, start_pos.lerp(end_pos, 0.5), end_pos]:
			if p.distance_to(caster_pos) <= 92.0 or p.distance_to(target_pos) <= 92.0:
				trigger_pulse()
				return

	func on_arcane_lightning(strike_pos: Vector2, _info: Dictionary = {}) -> void:
		if start_pos.distance_to(strike_pos) <= 135.0 or end_pos.distance_to(strike_pos) <= 135.0:
			trigger_pulse()

	func _process(delta: float) -> void:
		if _cooldown > 0.0:
			_cooldown = maxf(0.0, _cooldown - delta)
		if _pulse_t >= 0.0:
			var speed: float = 148.0 / maxf(start_pos.distance_to(end_pos), 32.0)
			_pulse_t += delta * speed
			if _pulse_t >= 1.0:
				_pulse_t = -1.0
				if is_instance_valid(target_node) and target_node.has_method("energize"):
					target_node.call("energize", 12.0)
				for next_c: LightConduit in chained_conduits:
					if is_instance_valid(next_c):
						next_c.trigger_pulse()
			_refresh_glows()
			_spark_overlay.queue_redraw()

	func _refresh_glows() -> void:
		var base_a: float = lerpf(0.22, 0.85, _night)
		var count: int = _glows.size()
		for i: int in count:
			var g: Sprite2D = _glows[i]
			if g == null:
				continue
			var boost: float = 0.0
			if _pulse_t >= 0.0 and count > 0:
				var seg_f: float = (float(i) + 0.5) / float(count)
				boost = clampf(1.0 - absf(_pulse_t - seg_f) * 3.4, 0.0, 1.0)
			g.modulate = Color(1.0 + 0.35 * boost, 1.0 + 0.25 * boost, 1.0, clampf(base_a + boost * 0.85, 0.0, 1.0))


class ConduitSparkDraw extends Node2D:
	var owner_conduit: LightConduit

	func _draw() -> void:
		if owner_conduit == null or owner_conduit._pulse_t < 0.0:
			return
		var local_end: Vector2 = owner_conduit.end_pos - owner_conduit.start_pos
		var head: Vector2 = local_end * clampf(owner_conduit._pulse_t, 0.0, 1.0)
		var tail: Vector2 = local_end * clampf(owner_conduit._pulse_t - 0.18, 0.0, 1.0)
		draw_line(tail, head, Color(0.47, 0.96, 0.90, 0.85), 3.0)
		draw_line(tail.lerp(head, 0.4), head, Color(1.0, 0.92, 0.62, 0.95), 1.5)
		draw_circle(head, 4.2, Color(0.47, 0.96, 0.90, 0.45))
		draw_circle(head, 2.2, Color(1.0, 0.97, 0.82, 0.98))


# =============================================================================
# 3. Resonanz-Obelisk (`ResonanceObelisk`)
# =============================================================================
class ResonanceObelisk extends Node2D:
	const HARMONIC_RADIUS: float = 84.0
	const RING_MAX_RADIUS: float = 78.0

	var variant: int = 0 ## 0..1 Harmonic (staff recharge aura), 2..3 Overcharged (periodic Prism Rings)
	var energized_timer: float = 0.0
	var linked_conduit: LightConduit
	var _sprite: Sprite2D
	var _glow: Sprite2D
	var _light: NightLight
	var _ring_draw: Node2D
	var _night: float = 0.0
	var _pulse_clock: float = 0.0
	var _ring_t: float = -1.0 ## -1 idle, 0..1 expanding prism ring
	var _telegraph: float = 0.0

	func setup(world_pos: Vector2, obelisk_variant: int) -> void:
		position = world_pos
		variant = clampi(obelisk_variant, 0, 3)
		_pulse_clock = fposmod(world_pos.x * 0.037 + world_pos.y * 0.053, 4.2)
		name = "ResonanceObelisk_%d_%d" % [int(world_pos.x), int(world_pos.y)]

	func is_overcharged() -> bool:
		return variant >= 2

	func is_energized() -> bool:
		return energized_timer > 0.0

	func _ready() -> void:
		add_to_group("resonance_obelisks")
		add_to_group("night_lights")
		add_to_group("desert_spell_listeners")
		add_to_group("desert_arcane_listeners")

		_ring_draw = ObeliskRingDraw.new()
		(_ring_draw as ObeliskRingDraw).obelisk = self
		_ring_draw.material = Unlit.material()
		_ring_draw.z_index = -1
		add_child(_ring_draw)

		_sprite = Sprite2D.new()
		_sprite.texture = OBELISK_TEX
		_sprite.hframes = 4
		_sprite.frame = variant
		_sprite.centered = false
		_sprite.offset = Vector2(-24.0, -66.0)
		_sprite.material = WorldProp._day_material()
		add_child(_sprite)

		_glow = Sprite2D.new()
		_glow.texture = OBELISK_GLOW
		_glow.hframes = 4
		_glow.frame = variant
		_glow.centered = false
		_glow.offset = _sprite.offset
		_glow.material = Unlit.material()
		_sprite.add_child(_glow)

		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(18.0, 9.0)
		cs.shape = rect
		cs.position = Vector2(0.0, -4.5)
		body.add_child(cs)
		add_child(body)

		_light = NightLight.new()
		_light.radius = 44 if is_overcharged() else 38
		_light.squash = 0.58
		_light.base_energy = 0.42 if is_overcharged() else 0.34
		_light.glow_color = Color("cbaaff") if is_overcharged() else Color("78f4e6")
		_light.pulse = 0.25
		_light.position = Vector2(0.0, -10.0)
		add_child(_light)
		set_night(TimeManager.night_amount())

	## Read by `DesertHeat.spell_recharge_rate`: Harmonic obelisks speed up spell crystal recharge (+35%, or +60% energized);
	## Overcharged obelisks grant +20% (+40% energized).
	func recharge_bonus_at(world_pos: Vector2) -> float:
		var d: float = global_position.distance_to(world_pos)
		if d > HARMONIC_RADIUS:
			return 0.0
		var falloff: float = 1.0 - smoothstep(HARMONIC_RADIUS * 0.55, HARMONIC_RADIUS, d)
		if is_overcharged():
			return (0.40 if energized_timer > 0.0 else 0.20) * falloff
		return (0.60 if energized_timer > 0.0 else 0.35) * falloff

	func energize(seconds: float = 12.0) -> void:
		var was_cold: bool = energized_timer <= 0.05
		energized_timer = maxf(energized_timer, seconds)
		if is_overcharged() and _ring_t < 0.0:
			emit_prism_ring()
		elif was_cold:
			Sfx.at(self, "prism_ring", global_position, -6.0, 0.08)
		if is_instance_valid(linked_conduit):
			linked_conduit.trigger_pulse()
		_ring_draw.queue_redraw()

	func emit_prism_ring() -> void:
		_ring_t = 0.0
		_telegraph = 0.0
		Sfx.at(self, "prism_ring", global_position, -4.5, 0.06)
		if is_instance_valid(linked_conduit):
			linked_conduit.trigger_pulse()

	func is_emitting_ring() -> bool:
		return _ring_t >= 0.0

	func set_night(amount: float) -> void:
		_night = amount
		if _light != null:
			_light.set_night(amount)

	func on_spell_cast(caster_pos: Vector2, target_pos: Vector2, _spell_id: String) -> void:
		if global_position.distance_to(caster_pos) <= 78.0 or global_position.distance_to(target_pos) <= 78.0:
			energize(10.0)

	func on_arcane_lightning(strike_pos: Vector2, _info: Dictionary = {}) -> void:
		if global_position.distance_to(strike_pos) <= 140.0:
			energize(14.0)

	func _process(delta: float) -> void:
		var dirty: bool = false
		if energized_timer > 0.0:
			energized_timer = maxf(0.0, energized_timer - delta)
			dirty = true
		if is_overcharged():
			var storm_fast: bool = WeatherManager.current != null and WeatherManager.current.desert_arcane_storm > 0.25
			var period: float = 3.0 if (storm_fast or energized_timer > 0.0) else 5.6
			_pulse_clock += delta
			var rem: float = period - _pulse_clock
			var new_tel: float = clampf(1.0 - rem / 0.85, 0.0, 1.0) if rem <= 0.85 else 0.0
			if absf(new_tel - _telegraph) > 0.02:
				_telegraph = new_tel
				dirty = true
			if _pulse_clock >= period:
				_pulse_clock = 0.0
				emit_prism_ring()
				dirty = true
		if _ring_t >= 0.0:
			_ring_t += delta * 1.45
			if _ring_t >= 1.0:
				_ring_t = -1.0
			dirty = true
		if _glow != null:
			var pulse_a: float = 0.08 * sin(Time.get_ticks_msec() * 0.004 + position.x * 0.05)
			var boost_a: float = (0.45 if energized_timer > 0.0 else 0.0) + _telegraph * 0.35
			_glow.modulate.a = clampf(lerpf(0.32, 0.98, _night) + pulse_a + boost_a, 0.0, 1.0)
		if dirty or energized_timer > 0.0:
			_ring_draw.queue_redraw()


class ObeliskRingDraw extends Node2D:
	var obelisk: ResonanceObelisk

	func _draw() -> void:
		if obelisk == null:
			return
		var center: Vector2 = Vector2(0.0, -3.0)
		# Harmonic energized aura floor circle (compact base rune rings)
		if not obelisk.is_overcharged() and obelisk.energized_timer > 0.0:
			var a: float = clampf(obelisk.energized_timer / 2.0, 0.0, 1.0) * 0.55
			_draw_ellipse_ring(center, 25.0, 14.5, Color(0.47, 0.96, 0.90, a * 0.72), 1.4)
			_draw_ellipse_ring(center, 18.0, 10.5, Color(1.0, 0.86, 0.48, a), 1.5)
		# Overcharged telegraph glow at foot
		if obelisk._telegraph > 0.01:
			var ta: float = obelisk._telegraph * 0.65
			_draw_ellipse_ring(center, lerpf(10.0, 20.0, obelisk._telegraph), lerpf(6.0, 12.0, obelisk._telegraph), Color(0.80, 0.67, 1.0, ta), 2.0)
		# Expanding unshaded Prism Ring (turquoise + violet + sun-gold)
		if obelisk._ring_t >= 0.0:
			var t: float = clampf(obelisk._ring_t, 0.0, 1.0)
			var rx: float = lerpf(8.0, ResonanceObelisk.RING_MAX_RADIUS, t)
			var ry: float = rx * 0.58
			var fade: float = (1.0 - t) * (1.0 - t * 0.35)
			_draw_ellipse_ring(center, rx, ry, Color(0.47, 0.96, 0.90, 0.88 * fade), 2.2)
			_draw_ellipse_ring(center, maxf(rx - 4.0, 2.0), maxf(ry - 2.4, 1.5), Color(0.80, 0.67, 1.0, 0.72 * fade), 1.6)
			_draw_ellipse_ring(center, maxf(rx - 7.5, 1.0), maxf(ry - 4.4, 1.0), Color(1.0, 0.85, 0.42, 0.68 * fade), 1.3)

	func _draw_ellipse_ring(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		var steps: int = 28
		for i: int in range(steps + 1):
			var ang: float = TAU * float(i) / float(steps)
			pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
		draw_polyline(pts, col, width)


# =============================================================================
# 4. Alter Siegelkreis im Quarz (`QuartzSeal`)
# =============================================================================
class QuartzSeal extends Node2D:
	const SOCKET_OFFSETS: Array[Vector2] = [
		Vector2(0.0, -20.0),
		Vector2(21.0, 0.0),
		Vector2(0.0, 20.0),
		Vector2(-21.0, 0.0),
	]

	var ruins: DesertRuins
	var seal_id: String = ""
	var tier_name: String = "uncommon"
	var variant: int = 0
	var awake: bool = false
	var _sockets: Array[float] = [0.0, 0.0, 0.0, 0.0] ## remaining lit seconds per cardinal socket
	var _sprite: Sprite2D
	var _glow: Sprite2D
	var _overlay: Node2D
	var _night: float = 0.0
	var _burst_t: float = -1.0

	func setup(owner_ruins: DesertRuins, id_str: String, world_pos: Vector2, seal_variant: int, reward_tier: String) -> void:
		ruins = owner_ruins
		seal_id = id_str
		position = world_pos
		variant = clampi(seal_variant, 0, 1)
		tier_name = reward_tier
		name = "QuartzSeal_" + id_str

	func _ready() -> void:
		add_to_group("night_lights")
		add_to_group("desert_spell_listeners")
		_sprite = Sprite2D.new()
		_sprite.texture = SEAL_TEX
		_sprite.hframes = 2
		_sprite.frame = variant
		add_child(_sprite)

		_glow = Sprite2D.new()
		_glow.texture = SEAL_GLOW
		_glow.hframes = 2
		_glow.frame = variant
		_glow.material = Unlit.material()
		_sprite.add_child(_glow)

		_overlay = SealSocketDraw.new()
		(_overlay as SealSocketDraw).seal = self
		_overlay.material = Unlit.material()
		_overlay.z_index = 1
		add_child(_overlay)
		set_night(TimeManager.night_amount())

	func set_night(amount: float) -> void:
		_night = amount
		_refresh_glow()

	func set_awake_instant() -> void:
		awake = true
		_sockets = [99.0, 99.0, 99.0, 99.0]
		_refresh_glow()
		if _overlay != null:
			_overlay.queue_redraw()

	func play_awaken_fx() -> void:
		awake = true
		_burst_t = 0.0
		Sfx.at(self, "seal_awake", global_position, -2.5, 0.04)
		_refresh_glow()
		if _overlay != null:
			_overlay.queue_redraw()

	## Direct conduit pulse or spell cast lights all sockets and awakens the seal on the host!
	func energize(_seconds: float = 12.0) -> void:
		if awake:
			return
		for i: int in 4:
			_sockets[i] = 10.0
		_overlay.queue_redraw()
		_refresh_glow()
		if multiplayer.is_server() and ruins != null:
			ruins.host_awaken_seal(seal_id, tier_name, global_position)

	func on_spell_cast(caster_pos: Vector2, target_pos: Vector2, _spell_id: String) -> void:
		if awake:
			return
		if global_position.distance_to(caster_pos) <= 52.0 or global_position.distance_to(target_pos) <= 52.0:
			energize(12.0)

	func _process(delta: float) -> void:
		if _burst_t >= 0.0:
			_burst_t += delta * 1.4
			if _burst_t >= 1.0:
				_burst_t = -1.0
			_overlay.queue_redraw()
		if awake:
			return
		var changed: bool = false
		for i: int in 4:
			if _sockets[i] > 0.0:
				_sockets[i] = maxf(0.0, _sockets[i] - delta)
				changed = true
		for p: Player in Player.all:
			if not is_instance_valid(p) or p.health == null or p.health.current <= 0.0:
				continue
			for i: int in 4:
				if p.global_position.distance_to(global_position + SOCKET_OFFSETS[i]) <= 13.5:
					if _sockets[i] <= 0.1:
						Sfx.at(self, "conduit_pulse", global_position + SOCKET_OFFSETS[i], -7.0, 0.10)
					_sockets[i] = 9.0
					changed = true
		if changed:
			_refresh_glow()
			_overlay.queue_redraw()
			if multiplayer.is_server() and _sockets[0] > 0.0 and _sockets[1] > 0.0 and _sockets[2] > 0.0 and _sockets[3] > 0.0:
				if ruins != null:
					ruins.host_awaken_seal(seal_id, tier_name, global_position)

	func _refresh_glow() -> void:
		if _glow == null:
			return
		var lit_cnt: int = 0
		for s: float in _sockets:
			if s > 0.0:
				lit_cnt += 1
		var frac: float = 1.0 if awake else float(lit_cnt) / 4.0
		_glow.modulate.a = clampf(lerpf(0.18, 0.55, _night) + frac * 0.65, 0.0, 1.0)


class SealSocketDraw extends Node2D:
	var seal: QuartzSeal

	func _draw() -> void:
		if seal == null:
			return
		for i: int in 4:
			if seal.awake or seal._sockets[i] > 0.0:
				var p: Vector2 = QuartzSeal.SOCKET_OFFSETS[i]
				var a: float = 0.85 if seal.awake else clampf(seal._sockets[i] / 1.5, 0.25, 0.9)
				draw_circle(p, 4.0, Color(0.47, 0.96, 0.90, a * 0.45))
				draw_circle(p, 2.0, Color(1.0, 0.92, 0.58, a))
		if seal._burst_t >= 0.0:
			var t: float = clampf(seal._burst_t, 0.0, 1.0)
			var r: float = lerpf(8.0, 52.0, t)
			var pts: PackedVector2Array = PackedVector2Array()
			for k: int in 25:
				var ang: float = TAU * float(k) / 24.0
				pts.append(Vector2(cos(ang) * r, sin(ang) * r * 0.68))
			draw_polyline(pts, Color(0.47, 0.96, 0.90, (1.0 - t) * 0.9), 2.2)
