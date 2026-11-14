class_name DesertHeat
extends RefCounted
## Pure rules for Sonnenquarz-Öde midday heat (`sun_heat` / `ERHITZT`), natural cooling (`refreshed` / `ERFRISCHT`),
## real world shade (palms, saguaro cacti, ruin arches, NW cliff shadows), and arcane quartz spell-recharge resonance.

const HEAT_THRESHOLD: float = 0.25 ## `sun_heat` HUD tag & sweat gesture engage above this intensity (0..1)
const HEAT_CLEAR_AT: float = 0.08
const BUILD_RATE: float = 0.105 ## ~9.5 s in blazing midday sand to reach 1.0 (19 s on cool white ground quartz)
const COOL_SHADE_RATE: float = 0.42 ## cools 1.0 -> 0.0 in ~2.4 s under real shade or at night
const COOL_REFRESHED_RATE: float = 0.65
const STAMINA_REGEN_PENALTY: float = 0.30 ## up to -30 % stamina regen at full heat
const STAMINA_COST_PENALTY: float = 0.15 ## up to +15 % sprint & shadow-step stamina cost at full heat
const REFRESHED_REGEN_BONUS: float = 0.15 ## +15 % stamina regen while ERFRISCHT
const OASIS_REFRESH_SECONDS: float = 45.0

const NW_SHADOW_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-2, 0), Vector2i(0, -2), Vector2i(-2, -1), Vector2i(-1, -2), Vector2i(-2, -2),
]


## True when `pos` lies inside a room/mine, under a real canopy (`sun_palm`, `crown_cactus`, `quartz_arch`),
## or in the cast shadow of a higher NW cliff/mesa wall (top-left sunlight).
static func is_in_shade(tree: SceneTree, pos: Vector2) -> bool:
	if Interiors.slot_at(pos) >= 0 or MineManager.in_mine(pos):
		return true
	if WeatherManager.current != null and WeatherManager.current.canopy_at(pos) > 0.18:
		return true
	if tree != null:
		for node: Node in tree.get_nodes_in_group("day_canopies"):
			var item: Node2D = node as Node2D
			if item == null or not item.is_inside_tree():
				continue
			if item.global_position.distance_squared_to(pos) > 19600.0:
				continue
			var shape: Vector4 = item.call("day_canopy") as Vector4
			if shape.z <= 0.0 or shape.w <= 0.0:
				continue
			var rel: Vector2 = (pos - Vector2(shape.x, shape.y)) / Vector2(shape.z, shape.w)
			if rel.length_squared() <= 0.88:
				return true
		var obs: Node = tree.get_first_node_in_group("desert_observatory")
		if obs != null and obs.has_method("is_cooling_near") and bool(obs.call("is_cooling_near", pos)):
			return true
	if Terrain.relief != null:
		var tx: int = floori(pos.x / 16.0)
		var ty: int = floori(pos.y / 16.0)
		var base_lvl: int = Terrain.relief.level(tx, ty)
		for off: Vector2i in NW_SHADOW_OFFSETS:
			if Terrain.relief.is_land(tx + off.x, ty + off.y) and Terrain.relief.level(tx + off.x, ty + off.y) > base_lvl:
				return true
	return false


## Signed change per second for `player.heat_amount` (0..1). Negative cools rapidly; positive warms by day.
static func heat_drive(tree: SceneTree, pos: Vector2) -> float:
	var sun: float = TimeManager.sun_amount()
	if sun <= 0.06:
		return -COOL_SHADE_RATE ## desert nights are crisp and cool (0 heat)
	var arid: float = BiomeBlend.arid_at(pos)
	if arid < 0.32:
		return -COOL_SHADE_RATE
	if is_in_shade(tree, pos):
		return -COOL_SHADE_RATE
	var arid_k: float = smoothstep(0.30, 0.72, arid)
	var quartz_mul: float = 0.5 if BiomeBlend.is_quartz_surface(pos) else 1.0 ## cool white ground quartz halves heat buildup
	var weather_mul: float = 1.0
	if WeatherManager.current != null:
		weather_mul *= clampf(1.0 - 0.22 * WeatherManager.current.desert_resonance - 0.30 * WeatherManager.current.desert_arcane_storm - 0.12 * clampf(WeatherManager.current.wind - 0.45, 0.0, 1.0), 0.45, 1.0)
	return BUILD_RATE * sun * arid_k * quartz_mul * weather_mul


## True when standing/wading/swimming in cooling water (oasis, river, shore).
static func is_in_cooling_water(player: Player) -> bool:
	if player == null:
		return false
	if player.swim > 0 or player._is_submerged():
		return true
	var surf: Dictionary = Terrain.surface_data(Terrain.surface_at(player.global_position))
	return float(surf.get("submerge", 0.0)) > 0.0 or bool(surf.get("water", false))


## Multiplier (>= 1.0) on `SpellComponent` crystal recharge speed from magical desert weather and nearby `resonance_obelisk`s.
static func spell_recharge_rate(tree: SceneTree, pos: Vector2) -> float:
	var bonus: float = 0.0
	var w: WeatherManager = WeatherManager.current
	if w != null:
		if w.desert_resonance > 0.12 and BiomeBlend.is_quartz_surface(pos):
			bonus += 0.22 * w.desert_resonance ## Singender Resonanzwind on white quartz
		if w.desert_arcane_storm > 0.12:
			bonus += 0.35 * w.desert_arcane_storm ## Arkanes Quarzgewitter
	if tree != null:
		var best_obelisk: float = 0.0
		for node: Node in tree.get_nodes_in_group("resonance_obelisks"):
			if node != null and node.has_method("recharge_bonus_at"):
				best_obelisk = maxf(best_obelisk, float(node.call("recharge_bonus_at", pos)))
		bonus += best_obelisk
	return clampf(1.0 + bonus, 1.0, 2.15)
