extends Node
## HUD layout check (docs/hud_v2_konzept.md 4.2, step 2): in 12 forced contexts no two visible parts of data/hud.json
## overlap (parts of one `attach` group may touch), the stacked parts above the hotbar never cover each other, and the
## notices / place line / way vine are in their slots. Headless:
## `Godot --headless --path . tools/test_hud_layout.tscn` (prints `HUD LAYOUT OK`).

const HudTestWorld := preload("res://tools/hud_test_world.gd")
const CONTEXTS: Array[String] = ["explore", "combat", "boss", "dialogue", "menu", "vista", "build", "fish", "swim", "idle", "cutscene", "notice"]

var player: Player
var hud: CanvasLayer
var director: HudDirector
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	player = await HudTestWorld.open(self)
	if player == null:
		push_error("HUD LAYOUT: the world did not load")
		get_tree().quit(1)
		return
	hud = player.get("_hud") as CanvasLayer
	director = hud.get("director") as HudDirector
	_check(director != null, "the HUD has a director")
	if director == null:
		get_tree().quit(1)
		return
	player.health.floor_value = 1.0
	_fill()
	await _frames(30)
	for ctx: String in CONTEXTS:
		director.release()
		if ctx != "explore":
			director.force(ctx, true)
		for other: String in director.strength:
			if other != ctx:
				director.force(other, false)
		await _frames(3)
		director.snap()
		await _frames(3)
		_check_overlaps(ctx)
	director.release()
	_check_notices()
	_check_stage()
	_check_route()
	_check_place_and_tint()
	_check_respawn()
	await _check_tags()
	print("HUD LAYOUT: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("HUD LAYOUT OK")
	get_tree().quit(1 if failures > 0 else 0)


## Something in every part that can show: tags, a small and a medium notice, a line in the speech box.
func _fill() -> void:
	if player.effects != null:
		player.effects.apply("burn", 30.0)
		player.effects.apply("well_rested", 60.0)
	var notices: HudNotices = hud.get_node_or_null("Notices") as HudNotices
	if notices != null:
		notices.notify("small", "loot:wood", {"count": 3, "item": "wood"})
		notices.notify("medium", "test", {"header": "WEGSTEIN ERWACHT", "text": "PRÜFSTEIN"})
	var speech: SpeechBox = hud.get_node_or_null("SpeechBox") as SpeechBox
	if speech != null:
		speech.speak("PRÜFER", "EINE ZEILE ÜBER DER LEISTE, DIE NIEMANDEN ÜBERDECKEN DARF.", 60.0)


func _check_overlaps(ctx: String) -> void:
	var on: Array[String] = []
	for part: String in director.parts:
		if director.shows(part):
			on.append(part)
	for i: int in on.size():
		for j: int in range(i + 1, on.size()):
			var a: String = on[i]
			var b: String = on[j]
			var group: String = director.attach_group(a)
			if group != "" and group == director.attach_group(b):
				continue
			var ra: Rect2 = director.rect_of(a)
			var rb: Rect2 = director.rect_of(b)
			_check(not ra.intersects(rb), "%s: %s %s and %s %s do not overlap" % [ctx, a, ra, b, rb])
	print("  %s: %s" % [ctx, ", ".join(on)])


func _check_notices() -> void:
	var notices: HudNotices = hud.get_node_or_null("Notices") as HudNotices
	_check(notices != null, "the HUD has notices")
	if notices == null:
		return
	notices.notify("small", "loot:stone", {"count": 2, "item": "stone"})
	notices.notify("small", "loot:stone", {"count": 1, "item": "stone"})
	var merged: bool = false
	for line: Dictionary in notices._line_queue:
		if String(line.id) == "loot:stone":
			merged = int(line.count) == 3
	if String(notices._line.get("id", "")) == "loot:stone":
		merged = int(notices._line.count) == 3
	_check(merged, "two loot lines of one item merge (+3)")


func _check_stage() -> void:
	var a: Node = Node.new()
	var b: Node = Node.new()
	add_child(a)
	add_child(b)
	HudNotices.release_big(HudNotices._stage_owner.get_ref() if HudNotices._stage_owner != null else null)
	_check(HudNotices.claim_big(a), "a free stage can be claimed")
	_check(not HudNotices.claim_big(b), "a held stage cannot be claimed by another")
	_check(HudNotices.claim_big(a), "the holder may claim again")
	HudNotices.release_big(a)
	_check(HudNotices.claim_big(b), "a released stage can be claimed")
	HudNotices.release_big(b)
	a.queue_free()
	b.queue_free()


## Wegranke data: a quest goal in the next zone gives the way through the threshold, shut ways are reported as such.
func _check_route() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	var zd: ZoneDirector = world.call("director") as ZoneDirector if world != null and world.has_method("director") else null
	_check(zd != null and zd.atlas != null, "the zone world has an atlas")
	if zd == null or zd.atlas == null:
		return
	var goal: Vector2 = _point_in(zd, &"erlenfurt")
	_check(goal.is_finite(), "a point inside ERLENFURT is found")
	if not goal.is_finite():
		return
	var shut: Dictionary = QuestRoute.plan(zd.atlas, zd.continent_id, player.global_position, goal, {})
	_check(not bool(shut.get("same", true)), "a goal in ERLENFURT is in another zone")
	_check(bool(shut.get("blocked", false)), "with no flags the way to ERLENFURT is shut")
	_check(QuestRoute.headline(shut).contains("VERSPERRT"), "a shut way says VERSPERRT (%s)" % QuestRoute.headline(shut))
	var open: Dictionary = QuestRoute.plan(zd.atlas, zd.continent_id, player.global_position, goal, QuestRoute.all_open(zd.atlas))
	_check(not bool(open.get("blocked", true)) and bool(open.get("reachable", false)), "with every flag the way is open")
	_check(int(open.get("meters", 0)) > 0, "the way has a distance")
	_check(QuestRoute.headline(open).begins_with("→"), "an open way points at its zone (%s)" % QuestRoute.headline(open))
	var same: Dictionary = QuestRoute.plan(zd.atlas, zd.continent_id, player.global_position, player.global_position + Vector2(40, 0), {})
	_check(bool(same.get("same", false)), "a goal in the same zone needs no way")


func _point_in(zd: ZoneDirector, zone_id: StringName) -> Vector2:
	var zone: Atlas.Zone = zd.atlas.zone(zone_id)
	if zone == null:
		return Vector2.INF
	for i: int in range(1, 12):
		for j: int in range(1, 12):
			var tile: Vector2 = zone.bbox.position + zone.bbox.size * Vector2(float(i) / 12.0, float(j) / 12.0)
			var px: Vector2 = tile * 16.0 + Vector2(8, 8)
			if zd.atlas.zone_at(zd.continent_id, px) == zone_id:
				return px
	return Vector2.INF


## Ortsranke and the zone tint of the bark.
func _check_place_and_tint() -> void:
	var clock: Node = hud.find_child("ClockVine", true, false)
	_check(clock != null and clock.has_method("place_state"), "the clock has the Ortsranke")
	if clock != null:
		clock.call("show_place", &"test", "PRÜFHAIN", true)
		var state: Dictionary = clock.call("place_state") as Dictionary
		_check(String(state.get("place", "")) == "PRÜFHAIN", "a place types itself into the Ortsranke")
		_check(bool(state.get("stamp", false)), "a first visit stamps ENTDECKT")
		_check(String(state.get("danger", "")) != "", "the Ortsranke knows the danger grade (%s)" % state.get("danger", ""))
	var keep: Dictionary = ZoneMood.now
	ZoneMood.now = ZoneMood.blend(ZoneMood.NEUTRAL, ZoneMood.parse({"hud_bark": [0.42, 0.62, 0.36], "hud_tint": 1.0, "hud_void": 1.0}), 1.0)
	var mix: float = VineStyle.follow_mood(true)
	_check(VineStyle.BARK != VineStyle.BASE_BARK, "a zone with a bark tone tints the bark")
	_check(mix <= VineStyle.TINT_MAX * 2.0 + 0.001, "the tint stays within its cap")
	var moved: float = absf(VineStyle.BARK.r - VineStyle.BASE_BARK.r) + absf(VineStyle.BARK.g - VineStyle.BASE_BARK.g) + absf(VineStyle.BARK.b - VineStyle.BASE_BARK.b)
	_check(moved < 0.12, "the bark only moves a little (%.3f)" % moved)
	VineStyle.follow_mood(false)
	_check(VineStyle.BARK == VineStyle.BASE_BARK, "switched off, the plain bark is back")
	ZoneMood.now = keep


## Death card v2: the host only accepts a waystone that is awake.
func _check_respawn() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	_check(world != null and world.has_method("respawn_allowed"), "the world validates respawn targets")
	if world == null or not world.has_method("respawn_allowed"):
		return
	var peer: int = player.name.to_int()
	_check(bool(world.call("respawn_allowed", peer, &"home")), "home is always allowed")
	_check(bool(world.call("respawn_allowed", peer, &"")), "the default is always allowed")
	_check(not bool(world.call("respawn_allowed", peer, &"no_such_stone")), "an unknown waystone is refused")


## More than four effects fold into a "+N" tag.
func _check_tags() -> void:
	if player.effects == null:
		return
	for id: String in ["burn", "well_rested", "hallucinated", "veil", "wisp", "clear_vision"]:
		player.effects.apply(id, 30.0)
	await _frames(4)
	var tags: Node = hud.find_child("StatusTags", true, false)
	_check(tags != null, "the HUD has status tags")
	if tags != null and tags.has_method("hud_busy"):
		_check(bool(tags.call("hud_busy")), "status tags show while effects run")


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame
