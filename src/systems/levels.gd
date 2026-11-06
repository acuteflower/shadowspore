class_name Levels
extends RefCounted
## The one main level, derived from total XP (nothing but the XP is stored). XP needed to go from
## level n to n + 1 is `base * n ^ exponent`, rounded to `step` (data/levels.json). No rewards yet.


static func max_level() -> int:
	return int(DataRegistry.table("levels").get("max_level", 30))


## XP from the start of `level` to the start of the next one.
static func xp_to_next(level: int) -> int:
	var data: Dictionary = DataRegistry.table("levels")
	var step: int = maxi(int(data.get("step", 5)), 1)
	return maxi(roundi(float(data.get("base", 30)) * pow(level, float(data.get("exponent", 1.7))) / step) * step, step)


## Total XP at which `level` begins (level 1 = 0).
static func xp_at(level: int) -> int:
	var total: int = 0
	for n: int in range(1, level):
		total += xp_to_next(n)
	return total


static func level_for(xp: int) -> int:
	var level: int = 1
	var left: int = xp
	while level < max_level() and left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	return level


## XP earned inside the current level.
static func xp_into(xp: int) -> int:
	return xp - xp_at(level_for(xp))


## 0..1 through the current level (always 1 at the top).
static func fraction(xp: int) -> float:
	var level: int = level_for(xp)
	if level >= max_level():
		return 1.0
	return float(xp_into(xp)) / xp_to_next(level)
