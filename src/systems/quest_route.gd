class_name QuestRoute
extends RefCounted
## Pure: how a goal in another zone is reached (docs/hud_v2_konzept.md 3.B/3.C, step 4). The quest vine, the way vine and
## tests ask it; nothing here touches the tree. Distances are in tiles (= metres), along the straight line to the next
## threshold's middle (the vine says "120 M", not a path length).
##
## `plan(atlas, continent, from_px, target_px, flags)` ->
##   {"same": true, "zone": id}  when start and goal lie in one zone (or outside the zone world), or
##   {"same": false, "zone": from, "goal_zone": to, "next": {id, kind, pos (tile), to_zone, to_name, open, closed_reason,
##    seamless}, "then": id or &"", "then_name": "", "meters": int, "blocked": bool, "reachable": bool}
## `blocked` = no open way; then `next` is the first CLOSED threshold of the way that would lead there once the story
## opens it (closed_reason says why). `reachable` false = not even that (the zones are not linked).

static func plan(atlas: Atlas, continent: StringName, from_px: Vector2, target_px: Vector2, flags: Dictionary) -> Dictionary:
	if atlas == null or not from_px.is_finite() or not target_px.is_finite():
		return {"same": true, "zone": &""}
	var from_zone: StringName = atlas.zone_at(continent, from_px)
	var to_zone: StringName = atlas.zone_at(continent, target_px)
	if from_zone == &"" or to_zone == &"" or from_zone == to_zone:
		return {"same": true, "zone": from_zone}
	var from_tile: Vector2 = Atlas.tile_of(from_px)
	var chain: Array[Atlas.Threshold] = atlas.route(from_zone, to_zone, flags, from_tile)
	var blocked: bool = chain.is_empty()
	if blocked:
		chain = atlas.route(from_zone, to_zone, all_open(atlas), from_tile)
	var out: Dictionary = {"same": false, "zone": from_zone, "goal_zone": to_zone, "blocked": blocked, "reachable": not chain.is_empty(),
		"next": {}, "then": &"", "then_name": "", "meters": 0}
	if chain.is_empty():
		return out
	var first: Atlas.Threshold = chain[0]
	var at: StringName = from_zone
	var lead: Atlas.Threshold = first
	if blocked: ## the first threshold that is still shut: that is where the way ends today
		for t: Atlas.Threshold in chain:
			if not Atlas.is_threshold_open(t, flags) or not atlas.is_zone_open(t.other(at), flags):
				lead = t
				break
			at = t.other(at)
	var across: StringName = lead.other(at)
	var across_zone: Atlas.Zone = atlas.zone(across)
	var target: Vector2 = first.midpoint() if not blocked else lead.midpoint()
	out.next = {
		"id": lead.id, "kind": lead.kind, "pos": lead.midpoint(), "to_zone": across,
		"to_name": across_zone.name if across_zone != null else String(across).to_upper(),
		"open": Atlas.is_threshold_open(lead, flags) and atlas.is_zone_open(across, flags),
		"closed_reason": lead.closed_reason, "seamless": lead.seamless(),
	}
	out.meters = roundi(from_tile.distance_to(target))
	var index: int = chain.find(lead)
	if index >= 0 and index + 1 < chain.size():
		var then: StringName = chain[index + 1].other(across)
		var then_zone: Atlas.Zone = atlas.zone(then)
		out.then = then
		out.then_name = then_zone.name if then_zone != null else String(then).to_upper()
	elif across != to_zone:
		pass
	return out


## Every story flag a threshold or zone waits for, set (the way as it will be once everything is open).
static func all_open(atlas: Atlas) -> Dictionary:
	var flags: Dictionary = {}
	for id: StringName in atlas.thresholds:
		var t: Atlas.Threshold = atlas.thresholds[id] as Atlas.Threshold
		if t.open_flag != &"":
			flags[String(t.open_flag)] = true
	for id: StringName in atlas.zones:
		var z: Atlas.Zone = atlas.zones[id] as Atlas.Zone
		if z.unlock_flag != &"":
			flags[String(z.unlock_flag)] = true
	return flags


## The line the quest vine writes for a plan: "→ WINDKAP · 120 M", "→ ALTER PASS (VERSPERRT)".
static func headline(route: Dictionary) -> String:
	if bool(route.get("same", true)) or (route.get("next", {}) as Dictionary).is_empty():
		return ""
	var next: Dictionary = route.next as Dictionary
	if not bool(next.get("open", true)):
		return "→ %s (VERSPERRT)" % String(next.to_name)
	return "→ %s · %d M" % [String(next.to_name), int(route.get("meters", 0))]


## The small line under it: "DANN WALDZONE", or the reason a threshold is shut.
static func subline(route: Dictionary) -> String:
	if bool(route.get("same", true)) or (route.get("next", {}) as Dictionary).is_empty():
		return ""
	var next: Dictionary = route.next as Dictionary
	if not bool(next.get("open", true)):
		return String(next.get("closed_reason", "")).to_upper()
	if String(route.get("then_name", "")) != "":
		return "DANN " + String(route.then_name)
	return ""
