class_name WindkapProps
extends RefCounted
## Custom landmarks, interactive camp props, Stone-Setter map tablet (the Sternenauge statue lives in `Sternenauge`), physical threshold blockers,
## and zone-aware coastal water ambience for WINDKAP (and any v2 coastal zone).
## All interactive state changes are host-authoritative via `@rpc`; strictly statically typed.

const CAMP_SHEET: String = "res://assets/props/coastal_camp.png"
const CAMP_GLOW: String = "res://assets/props/coastal_camp_glow.png"
const TABLET_SHEET: String = "res://assets/props/map_tablet.png"
const TABLET_GLOW: String = "res://assets/props/map_tablet_glow.png"
const BLOCKER_SHEET: String = "res://assets/props/threshold_blockers.png"
const BLOCKER_GLOW: String = "res://assets/props/threshold_blockers_glow.png"
const DAY_SPRITE_SHADER: Shader = preload("res://assets/shaders/day_sprite.gdshader")

static var _shared_day_mat: ShaderMaterial = null


static func day_material() -> ShaderMaterial:
	if _shared_day_mat == null:
		_shared_day_mat = ShaderMaterial.new()
		_shared_day_mat.shader = DAY_SPRITE_SHADER
	return _shared_day_mat


static func _rect_from(arr: Variant) -> Rect2:
	if arr is Array and (arr as Array).size() >= 4:
		var a: Array = arr as Array
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2()


static func _vec2_from(arr: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if arr is Array and (arr as Array).size() >= 2:
		var a: Array = arr as Array
		return Vector2(float(a[0]), float(a[1]))
	return fallback


static func _add_box_colliders(parent: Node2D, body_name: String, rects: Array) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	for r_v: Variant in rects:
		var r: Rect2 = _rect_from(r_v)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		var cs: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = r.size
		cs.shape = box
		cs.position = r.get_center()
		body.add_child(cs)
	parent.add_child(body)
	return body


static func _camp_art() -> Dictionary:
	return DataRegistry.table("coastal_camp_art")


static func _blocker_art() -> Dictionary:
	return DataRegistry.table("threshold_blockers_art")


# ==============================================================================
# 1. Coastal Camp — Lit Campfire (NightLight + animated flame + smoke particles)
# ==============================================================================
class Campfire:
	extends Node2D

	var _flame: Sprite2D = null
	var _glow: Sprite2D = null
	var _light: NightLight = null
	var _flame_rect: Rect2 = Rect2(0, 48, 32, 32)
	var _flame_cols: int = 8
	var _flame_fps: float = 11.0
	var _time: float = 0.0

	func _ready() -> void:
		add_to_group("campfires")
		add_to_group("night_lights")
		add_to_group("flora_glow")
		WaterReflections.watch(self, false)
		tree_exiting.connect(func() -> void: WaterReflections.unwatch(self))
		var art: Dictionary = WindkapProps._camp_art()
		var spec: Dictionary = art.get("campfire_lit", {}) as Dictionary
		var flame_spec: Dictionary = art.get("campfire_flame", {}) as Dictionary
		var sheet: Texture2D = load(WindkapProps.CAMP_SHEET) as Texture2D
		var glow_tex: Texture2D = load(WindkapProps.CAMP_GLOW) as Texture2D

		var base: Sprite2D = Sprite2D.new()
		base.name = "Base"
		base.texture = sheet
		base.region_enabled = true
		base.region_rect = WindkapProps._rect_from(spec.get("rect", [64, 0, 64, 48]))
		base.centered = false
		base.offset = WindkapProps._vec2_from(spec.get("offset", [-32, -36]))
		base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		base.material = WindkapProps.day_material()
		add_child(base)

		if glow_tex != null:
			_glow = Sprite2D.new()
			_glow.name = "EmberGlow"
			_glow.texture = glow_tex
			_glow.region_enabled = true
			_glow.region_rect = base.region_rect
			_glow.centered = false
			_glow.offset = base.offset
			_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_glow.material = Unlit.material()
			add_child(_glow)

		var fire_at: Vector2 = WindkapProps._vec2_from(spec.get("fire_at", [0, -6]))
		var f_full: Rect2 = WindkapProps._rect_from(flame_spec.get("rect", [0, 48, 256, 32]))
		var f_frame: Vector2 = WindkapProps._vec2_from(flame_spec.get("frame", [32, 32]))
		_flame_cols = maxi(1, int(flame_spec.get("cols", 8)))
		_flame_fps = maxf(1.0, float(flame_spec.get("fps", 11.0)))
		_flame_rect = Rect2(f_full.position, f_frame)

		_flame = Sprite2D.new()
		_flame.name = "Flame"
		_flame.texture = sheet
		_flame.region_enabled = true
		_flame.region_rect = _flame_rect
		_flame.centered = false
		_flame.position = fire_at
		_flame.offset = WindkapProps._vec2_from(flame_spec.get("offset", [-16, -26]))
		_flame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_flame.material = Unlit.material()
		add_child(_flame)

		var light_cfg: Dictionary = spec.get("light", {}) as Dictionary
		_light = NightLight.new()
		_light.name = "FireLight"
		_light.position = WindkapProps._vec2_from(light_cfg.get("at", [0, -6]))
		_light.radius = int(light_cfg.get("radius", 96))
		_light.squash = float(light_cfg.get("squash", 0.7))
		_light.base_energy = float(light_cfg.get("energy", 1.35))
		_light.pulse = float(light_cfg.get("flicker", 0.35))
		_light.glow_color = Color(String(light_cfg.get("color", "ff9448")))
		add_child(_light)

		var smoke: CPUParticles2D = CPUParticles2D.new()
		smoke.name = "Smoke"
		smoke.position = fire_at + Vector2(0.0, -16.0)
		smoke.z_index = 2
		smoke.amount = 10
		smoke.lifetime = 2.6
		smoke.direction = Vector2(0.15, -1.0)
		smoke.spread = 24.0
		smoke.gravity = Vector2(4.0, -4.0)
		smoke.initial_velocity_min = 6.0
		smoke.initial_velocity_max = 14.0
		smoke.scale_amount_min = 2.0
		smoke.scale_amount_max = 3.5
		var grad: Gradient = Gradient.new()
		grad.colors = PackedColorArray([Color("b4b0c6", 0.0), Color("b4b0c6", 0.36), Color("8a88a0", 0.16), Color("8a88a0", 0.0)])
		grad.offsets = PackedFloat32Array([0.0, 0.18, 0.65, 1.0])
		smoke.color_ramp = grad
		add_child(smoke)

		WindkapProps._add_box_colliders(self, "Body", spec.get("colliders", [[-19, -11, 38, 16]]) as Array)

	func _process(delta: float) -> void:
		_time += delta
		if _flame != null:
			var idx: int = int(floorf(_time * _flame_fps)) % _flame_cols
			_flame.region_rect = Rect2(_flame_rect.position.x + float(idx) * _flame_rect.size.x, _flame_rect.position.y, _flame_rect.size.x, _flame_rect.size.y)
		if _glow != null:
			var night: float = TimeManager.night_amount()
			var flick: float = 0.84 + 0.16 * sin(_time * 9.5) * cos(_time * 4.3)
			_glow.modulate.a = lerpf(0.55, 1.0, night) * flick


# ==============================================================================
# 2. Coastal Camp — Sittable Driftwood Bench / Stump Seat (`SeatSpot`)
# ==============================================================================
class CampSeat:
	extends SeatSpot

	var part_key: String = "driftwood_bench_h"
	var facing_sector: int = 4
	var _seat_offset: Vector2 = Vector2(0.0, -4.0)

	func _ready() -> void:
		var art: Dictionary = WindkapProps._camp_art()
		var spec: Dictionary = art.get(part_key, art.get("driftwood_bench_h", {})) as Dictionary
		var sheet: Texture2D = load(WindkapProps.CAMP_SHEET) as Texture2D
		_seat_offset = WindkapProps._vec2_from(spec.get("seat_pos", [0, -4]))
		var sp: Sprite2D = Sprite2D.new()
		sp.name = "Sprite"
		sp.texture = sheet
		sp.region_enabled = true
		sp.region_rect = WindkapProps._rect_from(spec.get("rect", [128, 0, 48, 32]))
		sp.centered = false
		sp.offset = WindkapProps._vec2_from(spec.get("offset", [-24, -24]))
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.material = WindkapProps.day_material()
		add_child(sp)
		WindkapProps._add_box_colliders(self, "Body", spec.get("colliders", [[-18, -8, 36, 10]]) as Array)

	func sit_sector() -> int:
		return clampi(facing_sector, 0, 7)

	func seat_position() -> Vector2:
		return global_position + _seat_offset + Vector2(0.0, 2.0)

	func approach_position() -> Vector2:
		return seat_position() + Vector2(0.0, 12.0)

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 14.0

	func prompt_position() -> Vector2:
		return Vector2(0.0, -24.0)

	func usable_by(player: Player) -> bool:
		return player != null and player.health.current > 0.0 and player.intro == null and not player.story_lock and not player.fainting

	func regen_rate() -> float:
		return 0.65

	func prompt() -> String:
		var player: Player = _local_player()
		if player == null or not usable_by(player) or InputManager.ui_blocking:
			return ""
		return "HINSETZEN" if not occupied() else ""

	func interact(player: Player) -> void:
		if not player.is_multiplayer_authority() or prompt() == "":
			return
		var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent
		if rest != null:
			rest.request_sit(self)


# ==============================================================================
# 3. Coastal Camp — Decorative Prop (backpack, rope coil, kindling, pebbles)
# ==============================================================================
class CampDecor:
	extends Node2D

	var part_key: String = "beach_pack_prop"

	func _ready() -> void:
		var art: Dictionary = WindkapProps._camp_art()
		var spec: Dictionary = art.get(part_key, {}) as Dictionary
		if spec.is_empty():
			return
		var sp: Sprite2D = Sprite2D.new()
		sp.name = "Sprite"
		sp.texture = load(WindkapProps.CAMP_SHEET) as Texture2D
		sp.region_enabled = true
		sp.region_rect = WindkapProps._rect_from(spec.get("rect", [0, 0, 24, 16]))
		sp.centered = false
		sp.offset = WindkapProps._vec2_from(spec.get("offset", [-12, -13]))
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.material = WindkapProps.day_material()
		add_child(sp)
		var cols: Array = spec.get("colliders", []) as Array
		if not cols.is_empty():
			WindkapProps._add_box_colliders(self, "Body", cols)
		WaterReflections.watch(self, false)
		tree_exiting.connect(func() -> void: WaterReflections.unwatch(self))


# ==============================================================================
# 4. Coastal Camp — Host-Authoritative Supply Chest (`ItemBox` + `BoxWindow`)
# ==============================================================================
class SupplyChest:
	extends Interactable

	const SLOTS: int = 16
	const REACH_PX: float = 48.0

	var box_id: String = "windkap_camp_chest"
	var box: ItemBox = null
	var _sprite: Sprite2D = null
	var _glow: Sprite2D = null
	var _base_rect: Rect2 = Rect2(0, 80, 56, 48)
	var _window: BoxWindow = null
	var _seeded: bool = false

	func _ready() -> void:
		var art: Dictionary = WindkapProps._camp_art()
		var spec: Dictionary = art.get("supply_chest", {}) as Dictionary
		var full: Rect2 = WindkapProps._rect_from(spec.get("rect", [0, 80, 168, 48]))
		var frame_sz: Vector2 = WindkapProps._vec2_from(spec.get("frame", [56, 48]))
		_base_rect = Rect2(full.position, frame_sz)

		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture = load(WindkapProps.CAMP_SHEET) as Texture2D
		_sprite.region_enabled = true
		_sprite.region_rect = _base_rect
		_sprite.centered = false
		_sprite.offset = WindkapProps._vec2_from(spec.get("offset", [-28, -39]))
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.material = WindkapProps.day_material()
		add_child(_sprite)

		var gtex: Texture2D = load(WindkapProps.CAMP_GLOW) as Texture2D
		if gtex != null:
			_glow = Sprite2D.new()
			_glow.name = "Glow"
			_glow.texture = gtex
			_glow.region_enabled = true
			_glow.region_rect = _base_rect
			_glow.centered = false
			_glow.offset = _sprite.offset
			_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_glow.material = Unlit.material()
			add_child(_glow)

		WindkapProps._add_box_colliders(self, "Body", spec.get("colliders", [[-13, -7, 26, 9]]) as Array)

		box = ItemBox.new(box_id, SLOTS)
		box.reach_ok = func(p: Node2D) -> bool:
			return is_instance_valid(self) and p != null and p.global_position.distance_to(global_position) <= REACH_PX + 24.0
		box.changed.connect(_on_box_changed)
		if multiplayer.is_server():
			if not _seeded:
				_seed_defaults()
			multiplayer.peer_connected.connect(_on_peer_connected)
		tree_exiting.connect(_on_exiting)

	func _on_exiting() -> void:
		if box != null and ItemBox.registry.get(box_id) == box:
			ItemBox.registry.erase(box_id)

	func _seed_defaults() -> void:
		_seeded = true
		box.add_item("dusk_berry", 6)
		box.add_item("wood", 8)
		box.add_item("stick", 6)
		box.add_item("plant_fiber", 6)
		box.add_item("stone", 6)
		box.add_item("sickle_basic", 1)
		box.add_item("pickaxe_basic", 1)

	func export_slots() -> Array:
		return box.slots.duplicate(true) if box != null else []

	func import_slots(data: Array) -> void:
		_seeded = true
		if box != null:
			box.import_slots(data)
			box.touch()

	func _on_peer_connected(peer_id: int) -> void:
		if multiplayer.is_server() and box != null and NetworkManager.rpc_ready(self):
			_rpc_sync_slots.rpc_id(peer_id, box.slots)

	func _on_box_changed() -> void:
		if multiplayer.is_server() and NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
			_rpc_sync_slots.rpc(box.slots)

	@rpc("authority", "call_remote", "reliable")
	func _rpc_sync_slots(slots_data: Array) -> void:
		if box != null:
			box.import_slots(slots_data)
			box.touch()

	func _set_frame(idx: int) -> void:
		var col: int = clampi(idx, 0, 2)
		var r: Rect2 = Rect2(_base_rect.position.x + float(col) * _base_rect.size.x, _base_rect.position.y, _base_rect.size.x, _base_rect.size.y)
		if _sprite != null:
			_sprite.region_rect = r
		if _glow != null:
			_glow.region_rect = r

	func _process(_delta: float) -> void:
		var is_open: bool = _window != null and is_instance_valid(_window)
		_set_frame(2 if is_open else 0)
		if _glow != null:
			_glow.modulate.a = lerpf(0.18, 0.72, TimeManager.night_amount())

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 16.0

	func prompt_position() -> Vector2:
		return Vector2(0.0, -34.0)

	func prompt() -> String:
		return "" if InputManager.ui_blocking else "VORRATSKISTE ÖFFNEN"

	func interact(player: Player) -> void:
		if not player.is_multiplayer_authority() or box == null or InputManager.ui_blocking:
			return
		_window = BoxWindow.open_box(get_tree(), player, box, "VORRATSKISTE")


# ==============================================================================
# 5. Coastal Camp — Weapon Rack / Chopping Stump with Claimable Starter Gear
# ==============================================================================
class StarterWeapon:
	extends Interactable

	var item_id: String = "sword_basic"
	var claimed_peers: Dictionary = {} ## int peer_id -> true (host-authoritative)
	var _weapon_sprite: Sprite2D = null
	var _weapon_glow: Sprite2D = null
	var _prompt_off: Vector2 = Vector2(0.0, -30.0)

	func _ready() -> void:
		var art: Dictionary = WindkapProps._camp_art()
		var sheet: Texture2D = load(WindkapProps.CAMP_SHEET) as Texture2D
		var glow_tex: Texture2D = load(WindkapProps.CAMP_GLOW) as Texture2D
		var is_axe: bool = item_id == "axe_basic"
		var base_key: String = "chopping_stump" if is_axe else "weapon_rack"
		var item_key: String = "starter_axe_planted" if is_axe else "starter_sword_planted"
		var base_spec: Dictionary = art.get(base_key, {}) as Dictionary
		var item_spec: Dictionary = art.get(item_key, {}) as Dictionary

		var base: Sprite2D = Sprite2D.new()
		base.name = "Stand"
		base.texture = sheet
		base.region_enabled = true
		base.region_rect = WindkapProps._rect_from(base_spec.get("rect", [168, 80, 48, 48]))
		base.centered = false
		base.offset = WindkapProps._vec2_from(base_spec.get("offset", [-24, -40]))
		base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		base.material = WindkapProps.day_material()
		add_child(base)

		WindkapProps._add_box_colliders(self, "Body", base_spec.get("colliders", [[-14, -8, 28, 10]]) as Array)

		var slot_at: Vector2 = WindkapProps._vec2_from(base_spec.get("axe_slot" if is_axe else "sword_slot", [0, -10]))
		_weapon_sprite = Sprite2D.new()
		_weapon_sprite.name = "Weapon"
		_weapon_sprite.texture = sheet
		_weapon_sprite.region_enabled = true
		_weapon_sprite.region_rect = WindkapProps._rect_from(item_spec.get("rect", [64, 128, 24, 32]))
		_weapon_sprite.centered = false
		_weapon_sprite.position = slot_at
		_weapon_sprite.offset = WindkapProps._vec2_from(item_spec.get("offset", [-12, -27]))
		_weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_weapon_sprite.material = WindkapProps.day_material()
		add_child(_weapon_sprite)

		if glow_tex != null:
			_weapon_glow = Sprite2D.new()
			_weapon_glow.name = "WeaponGlow"
			_weapon_glow.texture = glow_tex
			_weapon_glow.region_enabled = true
			_weapon_glow.region_rect = _weapon_sprite.region_rect
			_weapon_glow.centered = false
			_weapon_glow.position = slot_at
			_weapon_glow.offset = _weapon_sprite.offset
			_weapon_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_weapon_glow.material = Unlit.material()
			add_child(_weapon_glow)

		_prompt_off = WindkapProps._vec2_from(item_spec.get("prompt_anchor", [0, -32])) + slot_at
		if multiplayer.is_server():
			multiplayer.peer_connected.connect(_on_peer_connected)
		_refresh_visible()

	func _on_peer_connected(peer_id: int) -> void:
		if multiplayer.is_server() and NetworkManager.rpc_ready(self):
			_rpc_sync_claimed.rpc_id(peer_id, export_claimed())

	func export_claimed() -> Array[int]:
		var out: Array[int] = []
		for k: Variant in claimed_peers:
			if bool(claimed_peers[k]):
				out.append(int(k))
		return out

	func import_claimed(ids: Variant) -> void:
		claimed_peers.clear()
		if ids is Array:
			for v: Variant in ids as Array:
				claimed_peers[int(v)] = true
		_refresh_visible()

	func _local_available() -> bool:
		var uid: int = multiplayer.get_unique_id()
		if claimed_peers.has(uid):
			return false
		var p: Player = SaveGame._local_player(get_tree())
		if p != null and p.inventory != null and _player_has_item(p, item_id):
			return false
		return true

	static func _player_has_item(p: Player, id: String) -> bool:
		if p == null or p.inventory == null:
			return false
		if p.inventory.count_item(id) > 0:
			return true
		for slot_key: Variant in p.inventory.equipment:
			var stack: Variant = p.inventory.equipment[slot_key]
			if stack is Dictionary and String((stack as Dictionary).get("id", "")) == id:
				return true
		return false

	func _refresh_visible() -> void:
		var show_item: bool = _local_available()
		if _weapon_sprite != null:
			_weapon_sprite.visible = show_item
		if _weapon_glow != null:
			_weapon_glow.visible = show_item

	func _process(_delta: float) -> void:
		_refresh_visible()
		if _weapon_glow != null and _weapon_glow.visible:
			var pulse: float = 0.45 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.004)
			_weapon_glow.modulate.a = lerpf(0.25, 0.95, TimeManager.night_amount()) * pulse

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 16.0

	func prompt_position() -> Vector2:
		return _prompt_off

	func prompt() -> String:
		if InputManager.ui_blocking or not _local_available():
			return ""
		return "AXT NEHMEN" if item_id == "axe_basic" else "SCHWERT NEHMEN"

	func interact(player: Player) -> void:
		if not player.is_multiplayer_authority() or not _local_available():
			return
		if multiplayer.is_server():
			_host_claim(player.name.to_int())
		else:
			_rpc_request_claim.rpc_id(1)

	@rpc("any_peer", "call_remote", "reliable")
	func _rpc_request_claim() -> void:
		if multiplayer.is_server():
			_host_claim(multiplayer.get_remote_sender_id())

	func _host_claim(peer_id: int) -> void:
		if claimed_peers.has(peer_id):
			return
		var target: Player = null
		for p: Player in Player.all:
			if p.name == str(peer_id):
				target = p
				break
		if target == null or target.health.current <= 0.0 or target.global_position.distance_to(global_position) > 64.0:
			return
		if _player_has_item(target, item_id):
			claimed_peers[peer_id] = true
			_rpc_sync_claimed.rpc(export_claimed())
			return
		var leftover: int = target.inventory.add_item(item_id, 1)
		if leftover > 0:
			return
		claimed_peers[peer_id] = true
		if NetworkManager.rpc_ready(self):
			_rpc_sync_claimed.rpc(export_claimed())
		else:
			_refresh_visible()

	@rpc("authority", "call_local", "reliable")
	func _rpc_sync_claimed(ids: Array[int]) -> void:
		import_claimed(ids)
		Sfx.at(self, "pickup", global_position, -4.0)


# ==============================================================================
# 7. Das Windkap — Interactive Stone-Setter Map Tablet (`map_tablet.png`)
# ==============================================================================
class MapTablet:
	extends Interactable

	var tablet_id: String = "windkap_map_tablet"
	var awakened: bool = false
	var _body: Sprite2D = null
	var _glow: Sprite2D = null
	var _light: NightLight = null
	var _banner: TownBanner = null
	var _time: float = 0.0
	var _busy: bool = false

	func _ready() -> void:
		add_to_group("night_lights")
		add_to_group("flora_glow")
		var tex: Texture2D = load(WindkapProps.TABLET_SHEET) as Texture2D
		var gtex: Texture2D = load(WindkapProps.TABLET_GLOW) as Texture2D

		_body = Sprite2D.new()
		_body.name = "Tablet"
		_body.texture = tex
		_body.region_enabled = true
		_body.region_rect = Rect2(0, 0, 64, 64)
		_body.centered = false
		_body.offset = Vector2(-32.0, -54.0)
		_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_body.material = WindkapProps.day_material()
		add_child(_body)

		if gtex != null:
			_glow = Sprite2D.new()
			_glow.name = "TabletGlow"
			_glow.texture = gtex
			_glow.region_enabled = true
			_glow.region_rect = Rect2(0, 0, 64, 64)
			_glow.centered = false
			_glow.offset = Vector2(-32.0, -54.0)
			_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_glow.material = Unlit.material()
			add_child(_glow)

		_light = NightLight.new()
		_light.name = "TabletLight"
		_light.position = Vector2(0.0, -24.0)
		_light.radius = 48
		_light.squash = 0.72
		_light.base_energy = 0.30
		_light.pulse = 0.15
		_light.glow_color = Color("78f4e6")
		add_child(_light)

		WindkapProps._add_box_colliders(self, "Body", [[-17, -8, 34, 9]])
		_sync_initial_state()
		_apply_visual()

	func _sync_initial_state() -> void:
		var disc: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
		if disc != null and disc.has_method("is_continent_unlocked") and bool(disc.call("is_continent_unlocked")):
			awakened = true
			return
		var p: Player = SaveGame._local_player(get_tree())
		if p != null and p.quests != null and p.quests.has_flag("atlas_continent_unlocked"):
			awakened = true

	func _apply_visual() -> void:
		var x_off: float = 64.0 if awakened else 0.0
		var r: Rect2 = Rect2(x_off, 0.0, 64.0, 64.0)
		if _body != null:
			_body.region_rect = r
		if _glow != null:
			_glow.region_rect = r
		if _light != null:
			_light.base_energy = 0.85 if awakened else 0.32

	func _process(delta: float) -> void:
		_time += delta
		if _glow != null:
			var night: float = TimeManager.night_amount()
			var pulse: float = 0.82 + 0.18 * sin(_time * 2.6)
			var base_a: float = lerpf(0.75, 1.0, night) if awakened else lerpf(0.30, 0.78, night)
			_glow.modulate.a = base_a * pulse

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 18.0

	func prompt_position() -> Vector2:
		return Vector2(0.0, -48.0)

	func prompt() -> String:
		if InputManager.ui_blocking or _busy:
			return ""
		return "KARTENTAFEL BETRACHTEN" if awakened else "STEINSETZER-TAFEL LESEN"

	func interact(player: Player) -> void:
		if not player.is_multiplayer_authority() or _busy or InputManager.ui_blocking:
			return
		_busy = true
		var toward: Vector2 = (global_position + Vector2(0.0, -8.0) - player.global_position).normalized()
		if player.has_method("begin_touch"):
			get_tree().create_timer(1.6).timeout.connect(func() -> void: _busy = false)
			player.begin_touch(toward, func() -> void:
				_busy = false
				_trigger_read(player))
		else:
			_busy = false
			_trigger_read(player)

	func _trigger_read(player: Player) -> void:
		var first_time: bool = not awakened
		if multiplayer.is_server():
			_host_unlock(player.name.to_int())
		else:
			_rpc_request_unlock.rpc_id(1)
		if player.quests != null:
			player.quests.set_flag("atlas_continent_unlocked")
		var map_win: Node = _find_map_window(player)
		if map_win != null and map_win.has_method("unlock_continent_solemn"):
			map_win.call("unlock_continent_solemn")
		elif first_time:
			_show_fallback_banner()
		else:
			var speech: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
			if speech != null:
				speech.speak("STEINSETZER-TAFEL", "Die Gravur zeigt ganz ALTMARK — von den Klippen im Westen bis zum Großen Riss.", 3.6)

	@rpc("any_peer", "call_remote", "reliable")
	func _rpc_request_unlock() -> void:
		if multiplayer.is_server():
			_host_unlock(multiplayer.get_remote_sender_id())

	func _host_unlock(peer_id: int) -> void:
		var disc: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
		if disc != null and disc.has_method("set_continent_unlocked"):
			disc.call("set_continent_unlocked", true)
		for p: Player in Player.all:
			if p.quests != null:
				p.quests.set_flag("atlas_continent_unlocked")
		if NetworkManager.rpc_ready(self):
			_rpc_awakened.rpc(peer_id)
		else:
			_rpc_awakened(peer_id)

	@rpc("authority", "call_local", "reliable")
	func _rpc_awakened(_peer_id: int) -> void:
		var was: bool = awakened
		awakened = true
		_apply_visual()
		for node: Node in get_tree().get_nodes_in_group("windkap_lighthouse"):
			if node.has_method("set_awakened"):
				node.call("set_awakened", true)
		if not was:
			_play_awaken_fx()

	func _play_awaken_fx() -> void:
		var motes: CPUParticles2D = CPUParticles2D.new()
		motes.one_shot = true
		motes.emitting = true
		motes.amount = 24
		motes.lifetime = 1.9
		motes.explosiveness = 0.65
		motes.direction = Vector2(0.0, -1.0)
		motes.spread = 65.0
		motes.gravity = Vector2(0.0, -8.0)
		motes.initial_velocity_min = 12.0
		motes.initial_velocity_max = 30.0
		motes.scale_amount_min = 1.0
		motes.scale_amount_max = 2.0
		motes.color = Color("78f4e6")
		motes.material = Unlit.material()
		motes.position = Vector2(0.0, -24.0)
		motes.z_index = 4
		add_child(motes)
		get_tree().create_timer(2.4).timeout.connect(motes.queue_free)
		if ResourceLoader.exists("res://assets/audio/vistas/chime.wav"):
			var audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			audio.stream = load("res://assets/audio/vistas/chime.wav") as AudioStream
			audio.volume_db = -5.0
			add_child(audio)
			audio.finished.connect(audio.queue_free)
			audio.play()

	func _find_map_window(player: Player) -> Node:
		var grouped: Node = get_tree().get_first_node_in_group("map_window")
		if grouped != null:
			return grouped
		if player != null and player._hud != null:
			return player._hud.get_node_or_null("MapWindow")
		return null

	func _show_fallback_banner() -> void:
		if _banner == null:
			_banner = TownBanner.new()
			add_child(_banner)
		_banner.show_banner({
			"header": "STEINSETZER-KARTE ERWACHT",
			"title": "ALTMARK ENTHÜLLT",
			"sub": "DER KONTINENT ÖFFNET SICH IM ATLAS [M]",
			"color": Color("1e3a48"),
			"emblem": -1,
		})


# ==============================================================================
# 8. Physical Threshold Blockers (`threshold_blockers.png` + `closed_reason`)
# ==============================================================================
class ThresholdBlocker:
	extends Interactable

	const KIND_MAP: Dictionary = {
		"rockfall": "mossy_rockfall",
		"mossy_rockfall": "mossy_rockfall",
		"collapsed_gate": "collapsed_arch",
		"collapsed_arch": "collapsed_arch",
		"bramble_wall": "bramble_wall",
	}

	var threshold_id: StringName = &""
	var blocker_kind: String = "rockfall"
	var fallback_hint: String = ""
	var closed: bool = true

	var _spec: Dictionary = {}
	var _sprite: Sprite2D = null
	var _glow: Sprite2D = null
	var _light: NightLight = null
	var _closed_body: StaticBody2D = null
	var _open_body: StaticBody2D = null
	var _prompt_off: Vector2 = Vector2(0.0, -46.0)
	var _time: float = 0.0

	func _ready() -> void:
		add_to_group("night_lights")
		var art: Dictionary = WindkapProps._blocker_art()
		var art_key: String = String(KIND_MAP.get(blocker_kind, "mossy_rockfall"))
		_spec = art.get(art_key, {}) as Dictionary
		var sheet: Texture2D = load(WindkapProps.BLOCKER_SHEET) as Texture2D
		var gtex: Texture2D = load(WindkapProps.BLOCKER_GLOW) as Texture2D

		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture = sheet
		_sprite.region_enabled = true
		_sprite.centered = false
		_sprite.offset = WindkapProps._vec2_from(_spec.get("offset", [-48, -54]))
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.material = WindkapProps.day_material()
		add_child(_sprite)

		if gtex != null:
			_glow = Sprite2D.new()
			_glow.name = "Glow"
			_glow.texture = gtex
			_glow.region_enabled = true
			_glow.centered = false
			_glow.offset = _sprite.offset
			_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_glow.material = Unlit.material()
			add_child(_glow)

		_light = NightLight.new()
		_light.name = "BlockerLight"
		_light.position = WindkapProps._vec2_from(_spec.get("light_pos", [0, -12]))
		_light.radius = 44
		_light.squash = 0.7
		_light.base_energy = 0.34
		_light.pulse = 0.14
		_light.glow_color = Color(String(_spec.get("light_color", "78f4e6")))
		add_child(_light)

		_closed_body = WindkapProps._add_box_colliders(self, "ClosedBody", _spec.get("colliders", [[-40, -16, 80, 18]]) as Array)
		_open_body = WindkapProps._add_box_colliders(self, "OpenBody", _spec.get("open_colliders", []) as Array)
		_prompt_off = WindkapProps._vec2_from(_spec.get("prompt_anchor", [0, -46]))
		_apply_closed(closed)

	func set_closed(is_closed: bool) -> void:
		closed = is_closed
		_apply_closed(closed)

	func _apply_closed(is_closed: bool) -> void:
		var r: Rect2 = WindkapProps._rect_from(_spec.get("rect" if is_closed else "open_rect", [0, 0, 96, 64]))
		if _sprite != null:
			_sprite.region_rect = r
		if _glow != null:
			_glow.region_rect = r
		_set_body_enabled(_closed_body, is_closed)
		_set_body_enabled(_open_body, not is_closed)

	static func _set_body_enabled(body: StaticBody2D, enabled: bool) -> void:
		if body == null:
			return
		for child: Node in body.get_children():
			if child is CollisionShape2D:
				var cs: CollisionShape2D = child as CollisionShape2D
				if cs.is_inside_tree():
					cs.set_deferred("disabled", not enabled)
				else:
					cs.disabled = not enabled

	func _process(delta: float) -> void:
		_time += delta
		if _glow != null:
			var night: float = TimeManager.night_amount()
			var pulse: float = 0.80 + 0.20 * sin(_time * 2.1 + position.x * 0.05)
			_glow.modulate.a = lerpf(0.06, 0.88, night) * pulse

	func reach_distance(from: Vector2) -> float:
		return from.distance_to(global_position) - 36.0

	func prompt_position() -> Vector2:
		return _prompt_off

	func prompt() -> String:
		if not closed or InputManager.ui_blocking:
			return ""
		return "UNTERSUCHEN"

	func _reason_text() -> String:
		var atlas: Atlas = Atlas.shared()
		if atlas != null and threshold_id != &"":
			var t: Atlas.Threshold = atlas.thresholds.get(threshold_id) as Atlas.Threshold
			if t != null and not t.closed_reason.is_empty():
				return t.closed_reason
		return fallback_hint if not fallback_hint.is_empty() else "Der Durchgang ist noch versperrt."

	func interact(player: Player) -> void:
		if not player.is_multiplayer_authority() or not closed:
			return
		var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
		if box != null:
			var title: String = "NORDPASS"
			if blocker_kind == "collapsed_gate" or blocker_kind == "collapsed_arch":
				title = "EINGESTÜRZTES TOR"
			elif blocker_kind == "bramble_wall":
				title = "DORNENWALL"
			else:
				title = "FELSSTURZ"
			box.speak(title, _reason_text(), 3.6)


# ==============================================================================
# 9. Zone-Aware Water Ambience (brook, surf wash, ocean swell at ALTMARK coords)
# ==============================================================================
class ZoneWaterAmbience:
	extends WaterAmbience

	func _update_mix(dt: float) -> void:
		var wf: WaterField = _find_water_field() as WaterField
		if wf == null or not is_instance_valid(wf):
			super._update_mix(dt)
			return
		var listener: Vector2 = _listener_position()
		var wtime: float = _water_time(wf, dt)

		var ww: WorldWind = WorldWind.current
		var wind_dir: Vector2 = ww.direction if ww != null and is_instance_valid(ww) else Vector2.RIGHT
		var wind_gust: float = ww.gust if ww != null and is_instance_valid(ww) else 0.15
		var wm: WeatherManager = WeatherManager.current
		var storm: float = wm.storm if wm != null and is_instance_valid(wm) else 0.0

		var b: Rect2 = wf.bounds
		var dx_b: float = maxf(maxf(b.position.x - listener.x, listener.x - b.end.x), 0.0)
		var dy_b: float = maxf(maxf(b.position.y - listener.y, listener.y - b.end.y), 0.0)
		var bounds_fade: float = 1.0 - smoothstep(40.0, 320.0, sqrt(dx_b * dx_b + dy_b * dy_b))

		# 1. Brook proximity via WaterField.nearest_brook_px
		var brook_nearest: Vector2 = wf.nearest_brook_px(listener)
		var brook_prox: float = 0.0
		if brook_nearest != Vector2.INF:
			brook_prox = (1.0 - smoothstep(28.0, 280.0, listener.distance_to(brook_nearest))) * bounds_fade
		var brook_rip: float = 0.88 + 0.12 * sin(wtime * 0.75)
		var brook_lin: float = clampf(brook_prox * brook_rip * 0.42, 0.0, 1.0)
		if _brook_2d != null and is_instance_valid(_brook_2d):
			if brook_nearest != Vector2.INF and is_inside_tree():
				_brook_2d.global_position = brook_nearest
			var b2d_db: float = clampf(-12.0 + linear_to_db(maxf(brook_prox * 0.65, 0.0001)), -80.0, 0.0) if brook_prox > 0.01 else -80.0
			_sync_player_2d(_brook_2d, b2d_db, dt)
		if _brook_bed != null and is_instance_valid(_brook_bed):
			var bbed_db: float = clampf(-9.0 + linear_to_db(maxf(brook_lin, 0.0001)), -80.0, 0.0) if brook_prox > 0.01 else -80.0
			_sync_player_1d(_brook_bed, bbed_db, dt, 6.0)

		# 2. Coastal surf wash via WaterField.nearest_coast_px
		var coast_nearest: Vector2 = wf.nearest_coast_px(listener)
		var coast_prox: float = 0.0
		if coast_nearest != Vector2.INF:
			coast_prox = (1.0 - smoothstep(32.0, 300.0, listener.distance_to(coast_nearest))) * bounds_fade
		var p01: float = WaterRules.swash_phase(listener.y, wtime, wind_dir, wind_gust, storm)
		var swash_env: float = 0.22
		if p01 < WaterRules.SWASH_SURGE_END:
			swash_env = 0.22 + 0.78 * sin((p01 / WaterRules.SWASH_SURGE_END) * PI * 0.5)
		else:
			var back_t: float = (p01 - WaterRules.SWASH_SURGE_END) / (1.0 - WaterRules.SWASH_SURGE_END)
			swash_env = 0.22 + 0.78 * pow(clampf(1.0 - back_t, 0.0, 1.0), 1.35)
		var surf_weather: float = 1.0 + clampf(storm, 0.0, 1.0) * 0.35 + clampf(wind_gust, 0.0, 2.0) * 0.08
		var surf_lin: float = clampf(coast_prox * swash_env * surf_weather * 0.72, 0.0, 1.0)
		if _surf_player != null and is_instance_valid(_surf_player):
			var surf_db: float = clampf(-10.0 + linear_to_db(maxf(surf_lin, 0.0001)), -80.0, 0.0) if coast_prox > 0.01 else -80.0
			_sync_player_1d(_surf_player, surf_db, dt, 0.0)

		# 3. Open ocean swell proximity (strongest in/near REGIME_OCEAN and along outer shore)
		var wf_here: Dictionary = wf.water_field_at(listener)
		var in_ocean: bool = int(wf_here.get("regime", 0)) == WaterRules.REGIME_OCEAN
		var ocean_prox: float = bounds_fade if in_ocean else (coast_prox * 0.75)
		var swell_h: float = WaterRules.swell_height(listener, wtime, wind_dir, wind_gust, storm)
		var swell_mod: float = 0.70 + 0.30 * clampf(absf(swell_h), 0.0, 1.2)
		var ocean_weather: float = 0.80 + 0.45 * clampf(storm, 0.0, 1.0) + 0.12 * clampf(wind_gust, 0.0, 2.0)
		var ocean_lin: float = clampf(ocean_prox * swell_mod * ocean_weather * 0.68, 0.0, 1.0)
		if _ocean_player != null and is_instance_valid(_ocean_player):
			var ocean_db: float = clampf(-11.0 + linear_to_db(maxf(ocean_lin, 0.0001)), -80.0, 0.0) if ocean_prox > 0.01 else -80.0
			_sync_player_1d(_ocean_player, ocean_db, dt, 0.0)


# ==============================================================================
# 10. WaterField -> WorldRivers Adapter & ZoneRiverFauna (RiverAnimals in v2!)
# ==============================================================================
class WaterFieldRiversAdapter:
	extends WorldRivers

	var field: WaterField = null

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func bind_field(wf: WaterField) -> void:
		field = wf
		var chunks: Dictionary = {}
		if wf != null:
			var c0: Vector2i = Vector2i((wf.bounds.position / 512.0).floor())
			var c1: Vector2i = Vector2i((wf.bounds.end / 512.0).floor())
			for cy: int in range(c0.y, c1.y + 1):
				for cx: int in range(c0.x, c1.x + 1):
					chunks["%d,%d" % [cx, cy]] = {"water_field": true}
		_data = {"chunks": chunks}

	func field_at(point: Vector2) -> Vector2:
		if field == null or not is_instance_valid(field):
			return Vector2(INF, 0.0)
		return field.field_at(point)


class ZoneRiverFauna:
	extends RiverFauna

	var water_field: WaterField = null
	var _adapter: WaterFieldRiversAdapter = null

	func setup_for_field(wf: WaterField) -> void:
		water_field = wf
		enabled_kinds = ["frog", "dragonfly", "strider", "heron", "otter", "kingfisher", "duck", "shoal"]
		_adapter = WaterFieldRiversAdapter.new()
		_adapter.name = "WaterFieldRiversAdapter"
		_adapter.bind_field(wf)
		add_child(_adapter)
		rivers = _adapter
		if get_node_or_null("Animals") == null:
			var a: Node2D = Node2D.new()
			a.name = "Animals"
			a.y_sort_enabled = true
			add_child(a)
			animals = a
		if get_node_or_null("Spawner") == null:
			var sp: MultiplayerSpawner = MultiplayerSpawner.new()
			sp.name = "Spawner"
			sp.add_spawnable_scene("res://src/water/river_animal.tscn")
			sp.spawn_path = NodePath("../Animals")
			add_child(sp)

	func _ready() -> void:
		y_sort_enabled = true
		if animals == null:
			animals = get_node_or_null("Animals") as Node2D
		if _adapter != null:
			rivers = _adapter
		set_process(multiplayer.is_server())

	func populate_zone_chunks() -> void:
		if water_field == null or not is_instance_valid(water_field):
			return
		var c0: Vector2i = Vector2i((water_field.bounds.position / 512.0).floor())
		var c1: Vector2i = Vector2i((water_field.bounds.end / 512.0).floor())
		for cy: int in range(c0.y, c1.y + 1):
			for cx: int in range(c0.x, c1.x + 1):
				chunk_loaded(Vector2i(cx, cy))

	func flow_at(point: Vector2) -> Vector2:
		if water_field == null or not is_instance_valid(water_field):
			return Vector2.RIGHT
		var fl: Vector2 = water_field.water_flow_at(point)
		return fl.normalized() if fl.length_squared() > 0.01 else Vector2.DOWN

	func _populate_kind(cell: Vector2i, kind: String, settings: Dictionary, rng: RandomNumberGenerator, perch_state: Dictionary) -> bool:
		if water_field == null or not is_instance_valid(water_field):
			return false
		# Keep river animals on the brook & shallow bay (not far out in deep ocean!)
		var center: Vector2 = Vector2(cell) * 512.0 + Vector2(256.0, 256.0)
		var wf_c: Dictionary = water_field.water_field_at(center)
		if int(wf_c.get("regime", 0)) == WaterRules.REGIME_OCEAN and float(wf_c.get("depth", 0.0)) > 0.85:
			return false
		return super._populate_kind(cell, kind, settings, rng, perch_state)

