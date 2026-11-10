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
