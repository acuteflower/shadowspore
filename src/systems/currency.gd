class_name Currency
extends RefCounted
## One currency, counted in copper: 100 copper = 1 silver, 100 silver = 1 gold.

const SILVER: int = 100
const GOLD: int = 10000


## Gold, silver and copper of a copper amount, as (gold, silver, copper).
@warning_ignore("integer_division")
static func split(copper: int) -> Vector3i:
	return Vector3i(copper / GOLD, (copper % GOLD) / SILVER, copper % SILVER)


## Short text such as "1G 20S 5K"; zero parts are left out.
static func short_text(copper: int) -> String:
	var parts: Vector3i = split(copper)
	var text: String = ""
	if parts.x > 0:
		text += "%dG " % parts.x
	if parts.y > 0:
		text += "%dS " % parts.y
	if parts.z > 0 or text == "":
		text += "%dK" % parts.z
	return text.strip_edges()
