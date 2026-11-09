class_name LevelRewards
extends RefCounted
## What the levels give (data/level_rewards.json). Pure functions of the level, the same on every peer.
## Every level gives a little health and stamina; every fifth level is a milestone (armor, overheal, a talisman slot).
## The values only count up to the CLAIMED level (`ProgressComponent.claimed`): rewards are collected in the Fortschritt window.

const KINDS: Array[String] = ["health", "stamina", "armor", "overheal", "talisman"]


static func _data() -> Dictionary:
	return DataRegistry.table("level_rewards")


static func step() -> int:
	return maxi(int(_data().get("milestone_step", 5)), 1)


static func is_milestone(level: int) -> bool:
	return _data().get("milestones", {}).has(str(level))


static func milestone(level: int) -> Dictionary:
	return (_data().get("milestones", {}) as Dictionary).get(str(level), {})


## What reaching `level` adds on top of the one before: {health, stamina, armor, overheal, talisman}.
static func gain(level: int) -> Dictionary:
	if level <= 1:
		return {}
	var out: Dictionary = {}
	var per: Dictionary = _data().get("per_level", {})
	for key: String in per:
		out[key] = float(per[key])
	for key: String in milestone(level):
		if key in KINDS:
			out[key] = float(out.get(key, 0.0)) + float(milestone(level)[key])
	return out


## The values of a character whose rewards up to `level` are collected.
static func stats_at(level: int) -> Dictionary:
	var base: Dictionary = _data().get("base", {})
	var out: Dictionary = {
		"health": float(base.get("health", 100)), "stamina": float(base.get("stamina", 100)),
		"armor": float(base.get("armor", 0)), "overheal": float(base.get("overheal", 0.1)), "talismans": int(base.get("talismans", 0)),
	}
	for n: int in range(2, level + 1):
		var g: Dictionary = gain(n)
		out["health"] = float(out["health"]) + float(g.get("health", 0.0))
		out["stamina"] = float(out["stamina"]) + float(g.get("stamina", 0.0))
		out["armor"] = float(out["armor"]) + float(g.get("armor", 0.0))
		out["overheal"] = float(out["overheal"]) + float(g.get("overheal", 0.0))
		out["talismans"] = int(out["talismans"]) + int(g.get("talisman", 0.0))
	return out


## The next milestone level above `level` (0 when there is none).
static func next_milestone(level: int) -> int:
	for n: int in range(level + 1, Levels.max_level() + 1):
		if is_milestone(n):
			return n
	return 0


## The level that opens the `n`th talisman slot (0 when no level does).
static func talisman_level(n: int) -> int:
	var count: int = int((_data().get("base", {}) as Dictionary).get("talismans", 0))
	for level: int in range(2, Levels.max_level() + 1):
		count += int(gain(level).get("talisman", 0.0))
		if count >= n:
			return level
	return 0


## Reduction of incoming damage: 80 / (80 + armor), so armor never reaches immunity.
static func damage_factor(armor: float) -> float:
	return 80.0 / (80.0 + maxf(armor, 0.0))


## Rows for a card: [{kind, text}] (German, upper case: PixelText).
static func lines(level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g: Dictionary = gain(level)
	if g.has("health"):
		out.append({"kind": "health", "text": "+%d LEBEN" % roundi(float(g["health"]))})
	if g.has("stamina"):
		out.append({"kind": "stamina", "text": "+%d AUSDAUER" % roundi(float(g["stamina"]))})
	if g.has("armor"):
		out.append({"kind": "armor", "text": "+%d RÜSTUNG" % roundi(float(g["armor"]))})
	if g.has("overheal"):
		out.append({"kind": "overheal", "text": "ÜBERHEILUNG +%d %%" % roundi(float(g["overheal"]) * 100.0)})
	if g.has("talisman"):
		out.append({"kind": "talisman", "text": "TALISMANPLATZ"})
	return out
