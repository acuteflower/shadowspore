class_name Moisture
extends RefCounted
## Wet and dry (docs/plant_life.md). Two layers, both pure functions so every peer agrees:
##  - the ground: `PropGenerator.damp(at)` (north slopes, cliff feet and the water's edge are damp, sunny slopes and high ground dry);
##  - the weather: a damp DAY (about a third of them, from the world seed) or a fog night just before it soaks the land: `wetness()` is
##    1 at dawn and dries out toward evening. Wet days make mushrooms and moss come back faster, bring out the undergrowth animals,
##    help seeds to take and tint the world cool and dark.
const WET_DAY_CHANCE: float = 0.32
const DRY_OUT: float = 0.65 ## share of the wetness lost between sunrise and dusk

static var world_seed: int = 0


static func is_wet_day(day: int) -> bool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, 6203])
	return rng.randf() < WET_DAY_CHANCE or fog_night(day - 1)


static func fog_night(night_id: int) -> bool:
	return night_id >= 1 and NightRules.special_for(world_seed, night_id) == "fog"


## 0 dry .. 1 soaked, now. During a fog night the air itself is wet.
static func wetness() -> float:
	var t: float = TimeManager.time_of_day
	var day: int = TimeManager.day
	var value: float = 0.0
	if t >= TimeManager.DAY_START:
		if is_wet_day(day):
			value = 1.0 - DRY_OUT * clampf((t - TimeManager.DAY_START) / (TimeManager.NIGHT_START - TimeManager.DAY_START), 0.0, 1.0)
		if fog_night(day):
			value = maxf(value, 0.8 * TimeManager.night_amount())
	else: ## the small hours still belong to the night of `day`
		value = 0.35 if is_wet_day(day) else 0.0
		if fog_night(day):
			value = maxf(value, 0.8)
	return value
