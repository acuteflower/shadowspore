class_name SwimRules
extends RefCounted
## docs/schwimmen_konzept.md: the pure rules of swimming on the surface (no nodes, tested by tools/test_swim.tscn). Numbers: data/swim.json.

const NONE: int = 0
const TREAD: int = 1 ## in deep water without input
const BREAST: int = 2
const CRAWL: int = 3 ## sprint

static func cfg() -> Dictionary:
	return DataRegistry.table("swim")


## Hysteresis: a swimmer starts above `enter_amount` of the depth and stops below `exit_amount`.
static func wants_swim(swimming: bool, amount: float) -> bool:
	var c: Dictionary = cfg()
	if swimming:
		return amount >= float(c["exit_amount"])
	return amount >= float(c["enter_amount"])


## The technique for the input. `tired` (stamina was empty and has not recovered) allows only the slow breaststroke; a wounded swimmer cannot crawl.
static func technique(moving: bool, sprint: bool, stamina: float, tired: bool, wounded: bool) -> int:
	if not moving:
		return TREAD
	if sprint and not tired and not wounded and stamina > 0.0:
		return CRAWL
	return BREAST


## Top speed in px/s for a technique.
static func speed(state: int, tired: bool, wounded: bool) -> float:
	var speeds: Dictionary = cfg()["speeds"]
	var value: float = 0.0
	match state:
		BREAST:
			value = float(speeds["tired"] if tired else speeds["breast"])
		CRAWL:
			value = float(speeds["crawl"])
	if wounded:
		value *= float(cfg()["wounded_speed"])
	return value


## Stamina per second a technique costs.
static func cost(state: int) -> float:
	var stamina: Dictionary = cfg()["stamina"]
	match state:
		BREAST:
			return float(stamina["breast"])
		CRAWL:
			return float(stamina["crawl"])
	return 0.0


## Tired starts at empty stamina and ends once this share of the maximum is back.
static func next_tired(tired: bool, stamina: float, maximum: float) -> bool:
	if stamina <= 0.0:
		return true
	if tired and stamina >= maximum * float(cfg()["stamina"]["tired_resume"]):
		return false
	return tired


const OFFSHORE_START_TILES: float = 14.0
const OFFSHORE_MAX_TILES: float = 24.0
const OFFSHORE_MAX_DRIFT: float = 64.0 ## px/s gentle return current toward shore deep offshore
const OFFSHORE_MAX_STAMINA: float = 22.0 ## extra stamina/s drained deep offshore


## Smooth 0..1 offshore intensity starting beyond `start_tiles` from the coastline.
static func offshore_factor(offshore_tiles: float, start_tiles: float = OFFSHORE_START_TILES, max_tiles: float = OFFSHORE_MAX_TILES) -> float:
	if offshore_tiles <= start_tiles:
		return 0.0
	var span: float = maxf(max_tiles - start_tiles, 1.0)
	var t: float = clampf((offshore_tiles - start_tiles) / span, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Progressive gentle shoreward return current (px/s) when swimming beyond `start_tiles` offshore.
static func offshore_drift(offshore_tiles: float, return_dir: Vector2, start_tiles: float = OFFSHORE_START_TILES, max_tiles: float = OFFSHORE_MAX_TILES) -> Vector2:
	var f: float = offshore_factor(offshore_tiles, start_tiles, max_tiles)
	if f <= 0.0 or return_dir == Vector2.ZERO:
		return Vector2.ZERO
	return return_dir.normalized() * (f * OFFSHORE_MAX_DRIFT)


## Progressive extra stamina drain per second when swimming beyond `start_tiles` offshore.
static func offshore_stamina_extra(offshore_tiles: float, start_tiles: float = OFFSHORE_START_TILES, max_tiles: float = OFFSHORE_MAX_TILES) -> float:
	var f: float = offshore_factor(offshore_tiles, start_tiles, max_tiles)
	return f * f * OFFSHORE_MAX_STAMINA
