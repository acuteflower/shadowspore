class_name PetSchedule
extends RefCounted
## Where a registered bird is at a given time of day (docs/pet_konzept.md 7.2). Like the settlers' plan it is a PURE function (record, clock): an unloaded
## bird is never simulated, the registry just asks this where to put it when its place comes into view. Every bird has a home and three favourite spots
## round it (offsets rolled from its key); by day it goes from spot to spot, at night it roosts at home.


## The three favourite spots in world pixels (the same every time).
static func spots(record: Dictionary, key: String) -> Array[Vector2]:
	var terr: Dictionary = PetRules.table()["territory"] as Dictionary
	var radius: Array = terr["radius"] as Array
	var home: Array = record.get("home", [0.0, 0.0]) as Array
	var origin: Vector2 = Vector2(float(home[0]), float(home[1]))
	var list: Array[Vector2] = []
	for i: int in int(terr["spots"]):
		var angle: float = float(absi(hash("%s:a%d" % [key, i])) % 6283) / 1000.0
		var far: float = lerpf(float(radius[0]), float(radius[1]), float(absi(hash("%s:r%d" % [key, i])) % 1000) / 1000.0)
		list.append(origin + Vector2.from_angle(angle) * far)
	return list


## Index of the plan slot at `time_of_day` (0..1): -1 = night (home), else 0..spots-1 by day.
static func slot_at(time_of_day: float) -> int:
	var terr: Dictionary = PetRules.table()["territory"] as Dictionary
	var night_start: float = float(terr["night_start"])
	var night_end: float = float(terr["night_end"])
	var t: float = fposmod(time_of_day, 1.0)
	if t >= night_start or t < night_end:
		return -1
	var count: int = int(terr["spots"])
	return clampi(int((t - night_end) / (night_start - night_end) * count), 0, count - 1)


## The place of the bird: home at night, otherwise its spot of the hour with a little scatter that changes from slot to slot.
static func place(record: Dictionary, key: String, time_of_day: float) -> Vector2:
	var home: Array = record.get("home", [0.0, 0.0]) as Array
	var origin: Vector2 = Vector2(float(home[0]), float(home[1]))
	var slot: int = slot_at(time_of_day)
	if slot < 0:
		return origin
	var terr: Dictionary = PetRules.table()["territory"] as Dictionary
	var jitter: float = float(terr["jitter"])
	var scatter: Vector2 = Vector2(float(absi(hash("%s:jx%d" % [key, slot])) % 2001) / 1000.0 - 1.0, float(absi(hash("%s:jy%d" % [key, slot])) % 2001) / 1000.0 - 1.0) * jitter
	return spots(record, key)[slot] + scatter
