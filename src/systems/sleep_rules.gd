class_name SleepRules
extends RefCounted
## Pure rules for the day-night sleep threshold (10%-70% of night), rolling fatigue debt,
## dynamic wake-up time, skipped night hours, and rested/tired effect tiers.

const DEFAULT_NIGHT_START: float = 0.875
const DEFAULT_NIGHT_END: float = 0.175

const DEFAULT_FATIGUE: float = 0.5
const MIN_THRESHOLD: float = 0.10
const MAX_THRESHOLD: float = 0.70
const RECOVERY_CUTOFF: float = 0.72
const RECOVERY_MIN: float = 0.20
const RECOVERY_MAX: float = 0.55
const LATE_DEBT_MAX: float = 0.35
const ALL_NIGHTER_DEBT: float = 0.55

const DEFAULT_WAKE_EARLY: float = 0.25208333 ## 06:03
const DEFAULT_WAKE_LATE: float = 0.375 ## 09:00

const WELL_RESTED_MAX_PROGRESS: float = 0.72
const DEFAULT_WELL_RESTED_BONUS: float = 0.12
const DEFAULT_TIRED_PENALTY_PER_TIER: float = 0.10
const DEFAULT_TIRED_MAX_TIER: int = 2


static func _table() -> Dictionary:
	return DataRegistry.table("sleep")


static func _thresh_cfg() -> Dictionary:
	return _table().get("threshold", {}) as Dictionary


static func _wake_cfg() -> Dictionary:
	return _table().get("wake", {}) as Dictionary


static func _fx_cfg() -> Dictionary:
	return _table().get("effects", {}) as Dictionary


static func text_cfg() -> Dictionary:
	return _table().get("text", {}) as Dictionary


static func night_span(night_start: float = DEFAULT_NIGHT_START, night_end: float = DEFAULT_NIGHT_END) -> float:
	return fposmod(night_end - night_start, 1.0)


static func is_in_night(t: float, night_start: float = DEFAULT_NIGHT_START, night_end: float = DEFAULT_NIGHT_END) -> bool:
	var n: float = fposmod(t, 1.0)
	if night_start > night_end:
		return n >= night_start or n < night_end
	return n >= night_start and n < night_end


## 0..1 progress within the sleep/dark night window; -1.0 outside night.
static func night_progress(t: float, night_start: float = DEFAULT_NIGHT_START, night_end: float = DEFAULT_NIGHT_END) -> float:
	if not is_in_night(t, night_start, night_end):
		return -1.0
	var span: float = maxf(night_span(night_start, night_end), 0.0001)
	return clampf(fposmod(t - night_start, 1.0) / span, 0.0, 1.0)


## Normalized 0.10..0.70 sleep unlock progress based on rolling fatigue (0 = rested -> 70%, 1 = exhausted -> 10%).
static func unlock_progress(fatigue: float) -> float:
	var cfg: Dictionary = _thresh_cfg()
	var min_p: float = float(cfg.get("min_progress", MIN_THRESHOLD))
	var max_p: float = float(cfg.get("max_progress", MAX_THRESHOLD))
	return lerpf(max_p, min_p, clampf(fatigue, 0.0, 1.0))


## Normalized 0..1 time_of_day at which today's sleep window opens.
static func unlock_time_of_day(
	fatigue: float,
	night_start: float = DEFAULT_NIGHT_START,
	night_end: float = DEFAULT_NIGHT_END
) -> float:
	return fposmod(night_start + unlock_progress(fatigue) * night_span(night_start, night_end), 1.0)


static func can_sleep(
	t: float,
	fatigue: float,
	night_start: float = DEFAULT_NIGHT_START,
	night_end: float = DEFAULT_NIGHT_END
) -> bool:
	var p: float = night_progress(t, night_start, night_end)
	if p < 0.0:
		return false
	return p + 0.0001 >= unlock_progress(fatigue)


## Updated fatigue after sleeping at normalized night progress p (0..1).
static func fatigue_after_sleep(fatigue: float, p: float) -> float:
	var cfg: Dictionary = _thresh_cfg()
	var cutoff: float = clampf(float(cfg.get("recovery_cutoff", RECOVERY_CUTOFF)), 0.1, 0.95)
	var rec_min: float = float(cfg.get("recovery_min", RECOVERY_MIN))
	var rec_max: float = float(cfg.get("recovery_max", RECOVERY_MAX))
	var debt_max: float = float(cfg.get("late_debt_max", LATE_DEBT_MAX))
	var clamped_p: float = clampf(p, 0.0, 1.0)
	var delta: float = 0.0
	if clamped_p <= cutoff:
		var earliness: float = 1.0 - clamped_p / cutoff
		delta = -lerpf(rec_min, rec_max, earliness)
	else:
		var lateness: float = (clamped_p - cutoff) / maxf(1.0 - cutoff, 0.001)
		delta = lerpf(0.0, debt_max, lateness)
	return clampf(clampf(fatigue, 0.0, 1.0) + delta, 0.0, 1.0)


## Updated fatigue after crossing a sunrise without sleeping in a bed.
static func fatigue_after_all_nighter(fatigue: float) -> float:
	var cfg: Dictionary = _thresh_cfg()
	var debt: float = float(cfg.get("all_nighter_debt", ALL_NIGHTER_DEBT))
	return clampf(clampf(fatigue, 0.0, 1.0) + debt, 0.0, 1.0)


## Dynamic morning time_of_day (06:03..09:00) based on when the player went to sleep.
static func wake_time(sleep_progress: float) -> float:
	var cfg: Dictionary = _wake_cfg()
	var early: float = float(cfg.get("early_time", DEFAULT_WAKE_EARLY))
	var late: float = float(cfg.get("late_time", DEFAULT_WAKE_LATE))
	return clampf(lerpf(early, late, clampf(sleep_progress, 0.0, 1.0)), early, late)


static func should_grant_well_rested(sleep_progress: float) -> bool:
	var max_p: float = float(_fx_cfg().get("well_rested_max_progress", WELL_RESTED_MAX_PROGRESS))
	return clampf(sleep_progress, 0.0, 1.0) <= max_p


static func well_rested_duration() -> float:
	return float(_fx_cfg().get("well_rested_duration", 600.0))


static func well_rested_regen_bonus() -> float:
	return float(_fx_cfg().get("well_rested_regen_bonus", DEFAULT_WELL_RESTED_BONUS))


static func tired_duration() -> float:
	return float(_fx_cfg().get("tired_duration", 1440.0))


static func tired_tier_for_awake_nights(nights_awake: int) -> int:
	if nights_awake <= 0:
		return 0
	var max_tier: int = int(_fx_cfg().get("tired_max_tier", DEFAULT_TIRED_MAX_TIER))
	return mini(nights_awake, maxi(max_tier, 1))


static func tired_regen_penalty(tier: int) -> float:
	var per_tier: float = float(_fx_cfg().get("tired_regen_penalty_per_tier", DEFAULT_TIRED_PENALTY_PER_TIER))
	return maxf(float(maxi(tier, 0)) * per_tier, 0.0)


## In-game hours remaining in dark night when sleeping at time t.
static func skipped_night_hours(t: float, night_start: float = DEFAULT_NIGHT_START, night_end: float = DEFAULT_NIGHT_END) -> float:
	if not is_in_night(t, night_start, night_end):
		return 0.0
	var rem_frac: float = clampf(fposmod(night_end - t, 1.0), 0.0, night_span(night_start, night_end))
	return rem_frac * 24.0
