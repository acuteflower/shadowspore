extends Node
## Godot --headless --path . tools/test_pets.tscn (offline, no save access): rules of the bond with wild birds, the lure (how hard it is to come close),
## the registry (points, daily curve, cooldown, save) and a bird that is lured by a quiet player with food in her hand.

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	TimeManager.time_of_day = 0.5
	# --- rules
	_check(PetRules.stage_of(0.0) == 0, "a stranger starts at stage 0")
	_check(PetRules.stage_of(1000.0) == 5, "a lot of points is the last stage")
	_check(PetRules.reaction("crow", "glow_cap") == "dislikes", "glow caps are not for crows")
	_check(PetRules.reaction("crow", "stone") == PetRules.NO_REACTION, "stone is no food")
	var none: Array[String] = []
	var plain: float = PetRules.lure_range("crow", 0, 0.0, none)
	var calm: float = PetRules.lure_range("crow", 0, 0.7, none)
	_check(calm > plain * 1.5, "the Rissfeder should widen the lure range a lot (%s vs %s)" % [plain, calm])
	_check(PetRules.lure_range("crow", 4, 0.0, none) > plain * 1.5, "a familiar bird lets one come closer")
	_check(PetRules.gain("loves", 0, none) > PetRules.gain("likes", 0, none), "loved food counts more")
	_check(PetRules.gain("likes", 5, none) < PetRules.gain("likes", 0, none), "the daily curve lowers the points")
	_check(PetRules.step_interest(0.0, true, 0.3, 1.0) > 0.0 and PetRules.step_interest(0.5, false, 0.3, 1.0) < 0.5, "interest grows when held and decays when not")
	# --- registry
	var registry: PetRegistry = PetRegistry.new()
	add_child(registry)
	var r: Dictionary = registry.feed("test#0", "crow", 1, "stone")
	_check(not bool(r["ok"]) and registry.bp_of("test#0", 1) == 0.0, "no bond from a stone")
	r = registry.feed("test#0", "crow", 1, "dusk_berry")
	_check(bool(r["ok"]) and registry.bp_of("test#0", 1) > 0.0, "a berry builds the bond")
	var first: float = registry.bp_of("test#0", 1)
	r = registry.feed("test#0", "crow", 1, "dusk_berry")
	_check(not bool(r["ok"]) and registry.bp_of("test#0", 1) == first, "the cooldown stops a second feeding at once")
	_check(registry.fed_today("test#0", 1) == 1, "one feeding counted today")
	var saved: Dictionary = registry.export_state()
	var other: PetRegistry = PetRegistry.new()
	add_child(other)
	other.import_state(saved)
	_check(is_equal_approx(other.bp_of("test#0", 1), first), "the bond survives a save")
	_check(other.bp_of("test#0", 2) == 0.0, "another player has no bond with this bird")
	# --- a lured bird
	var population: CorvidPopulation = load("res://src/world/corvid_population.tscn").instantiate() as CorvidPopulation
	add_child(population)
	population.setup(4, func(_at: Vector2, _species: String) -> bool: return true)
	population.set_process(false)
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			population._active[Vector2i(x, y)] = true
	var bird: WildCorvid = load("res://src/entities/wildlife/wild_corvid.tscn").instantiate() as WildCorvid
	bird.name = "Lure"
	bird.species = "crow"
	bird.home = Vector2.ZERO
	bird.position = Vector2.ZERO
	bird.flock_id = "test_flock"
	bird.pet_key = "test_flock#0"
	population._birds.add_child(bird)
	bird.set_physics_process(false)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = Vector2(plain - 6.0, 0.0)
	add_child(player)
	player.set_physics_process(false)
	await get_tree().physics_frame
	_check(bird._pet != null, "a pet species gets its lure behaviour on the host")
	_check(bird.get_node_or_null("PetFeedSpot") != null, "a pet species has the feed spot")
	player.stealth.sneaking = true
	for i: int in 12:
		bird._pet.tolerates(player, player.position.length(), 0.5)
	_check(float(bird._pet.interest.get(1, 0.0)) == 0.0, "without food in hand the bird does not warm to her")
	var slot: int = player.inventory.selected
	player.inventory.slots[slot] = {"id": "dusk_berry", "count": 3}
	for i: int in 12:
		bird._pet.tolerates(player, player.position.length(), 0.5)
	var warm: float = float(bird._pet.interest.get(1, 0.0))
	_check(warm > 0.5, "with food, quiet and close enough the bird warms to her (%s)" % warm)
	bird._pet.interest[1] = 0.0
	player.stealth.sneaking = false
	for i: int in 12:
		bird._pet.tolerates(player, player.position.length(), 0.5)
	_check(float(bird._pet.interest.get(1, 0.0)) == 0.0, "walking upright does not win a bird's trust")
	bird._pet.interest[1] = 0.0
	player.stealth.sneaking = true
	player.position = Vector2(plain * 2.0, 0.0)
	for i: int in 12:
		bird._pet.tolerates(player, player.position.length(), 0.5)
	_check(float(bird._pet.interest.get(1, 0.0)) == 0.0, "too far away the bird does not care")
	# --- step 2: registered birds
	var record_base: Dictionary = {"home": [600.0, 600.0]}
	_check(PetSchedule.slot_at(0.0) == -1 and PetSchedule.slot_at(0.9) == -1, "night has no slot: the bird roosts at home")
	_check(PetSchedule.slot_at(0.25) == 0 and PetSchedule.slot_at(0.75) == 2, "the day goes through the three spots")
	_check(PetSchedule.place(record_base, "k", 0.0).is_equal_approx(Vector2(600, 600)), "at night the bird is at home")
	_check(PetSchedule.place(record_base, "k", 0.5).is_equal_approx(PetSchedule.place(record_base, "k", 0.5)), "the place is a pure function")
	_check(PetSchedule.place(record_base, "k", 0.5).distance_to(Vector2(600, 600)) <= 104.0 + 21.0, "the spots stay inside the territory")
	_check(PetSchedule.place(record_base, "k", 0.25) != PetSchedule.place(record_base, "k", 0.75), "the spots differ through the day")
	_check(PetRegistry.clean_name("a/b<c>!") == "ABC" and PetRegistry.clean_name("   ") == "", "names are cleaned to capitals and letters")
	_check(PetRegistry.clean_name("abcdefghijklmnop").length() == 12, "names have a length limit")
	for i: int in 14:
		registry._cooldown.clear()
		registry.feed(bird.pet_key, "crow", 1, "seed_fluff")
	_check(registry.stage_of(bird.pet_key, 1) >= 2, "a few loved seeds reach the registering stage")
	_check(not registry.has_record(bird.pet_key), "no record before the bird was asked")
	_check(registry.ensure_record(bird, 1) and registry.has_record(bird.pet_key), "reaching stage 2 registers the bird")
	_check(not registry.ensure_record(bird, 1), "a bird is registered only once")
	_check(registry.name_of(bird.pet_key) != "", "a registered bird has a name")
	_check(population._wild_count() == 0, "a registered bird no longer counts for the ambient budget")
	registry.request_rename(bird.pet_key, "  mondschein 7 ")
	_check(registry.name_of(bird.pet_key) == "MONDSCHEIN 7", "renaming works for a player who knows the bird (%s)" % registry.name_of(bird.pet_key))
	registry._do_rename(bird.pet_key, "FREMDER", 2)
	_check(registry.name_of(bird.pet_key) == "MONDSCHEIN 7", "a stranger cannot rename it")
	var other_two: PetRegistry = PetRegistry.new()
	add_child(other_two)
	other_two.import_state(registry.export_state())
	_check(other_two.name_of(bird.pet_key) == "MONDSCHEIN 7" and other_two.has_record(bird.pet_key), "records survive a save")
	registry._pets["x#0"] = {"n": "TESTER", "sp": "raven", "ap": 1, "ring": 2, "home": [600.0, 600.0], "seen": [600.0, 600.0], "sd": 0, "rd": 0, "by": 1}
	TimeManager.time_of_day = 0.0
	registry._maintain_pets(PetRules.table()["territory"] as Dictionary)
	var spawned: WildCorvid = null
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		if (node as WildCorvid).pet_key == "x#0":
			spawned = node as WildCorvid
	_check(spawned != null and spawned.species == "raven" and spawned.appearance == 1, "a registered bird is put into its loaded territory")
	if spawned != null:
		spawned.set_physics_process(false)
		_check(spawned.flock_id == "pet:x#0" and spawned.territory.is_finite(), "it has a flock of its own and a territory")
		_check(spawned.get_node_or_null("PetTag") != null and spawned.get_node_or_null("Ring") != null, "it carries the tag and the ring")
		registry._maintain_pets(PetRules.table()["territory"] as Dictionary)
		var copies: int = 0
		for node: Node in get_tree().get_nodes_in_group("corvids"):
			if (node as WildCorvid).pet_key == "x#0":
				copies += 1
		_check(copies == 1, "the same bird is never spawned twice")
		spawned.global_position = Vector2(600.0 + 400.0, 600.0)
		registry._maintain_pets(PetRules.table()["territory"] as Dictionary)
		_check(spawned.global_position.distance_to(Vector2(600, 600)) < 5.0, "out of sight, a bird that strayed is back in its territory")
		for cell: Vector2i in population._active.keys():
			population._active.erase(cell)
		registry._maintain_pets(PetRules.table()["territory"] as Dictionary)
		_check(spawned.is_queued_for_deletion(), "a bird whose territory is unloaded is taken away")
		_check(registry.seen_of("x#0").z >= 0.0 and registry.seen_of("x#0").x > 0.0, "its last place is kept")
	registry._bonds["decay#0"] = {"1": {"bp": 120.0, "day": 0, "fed": 0, "total": 4}}
	registry._on_day(2)
	_check(is_equal_approx(registry.bp_of("decay#0", 1), 120.0), "within the grace days nothing is lost")
	registry._on_day(10)
	_check(is_equal_approx(registry.bp_of("decay#0", 1), 117.0), "a long absence cools the bond a little")
	registry._bonds["decay#0"] = {"1": {"bp": 41.0, "day": 0, "fed": 0, "total": 4}}
	registry._pets["decay#0"] = registry._pets["x#0"]
	for d: int in range(10, 20):
		registry._on_day(d)
	_check(registry.bp_of("decay#0", 1) >= PetRules.stage_start(2), "a registered bird never falls below the registering stage")
	# --- step 3: the companion
	var cfg: Dictionary = PetRules.table()["companion"] as Dictionary
	TimeManager.time_of_day = 0.5
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		population._active[cell] = true
	player.position = Vector2(100.0, 100.0)
	registry._pets["c#0"] = {"n": "GEFÄHRTE", "sp": "crow", "ap": 0, "ring": 1, "home": [100.0, 100.0], "seen": [100.0, 100.0], "sd": 0, "rd": 0, "by": 1}
	registry._bonds["c#0"] = {"1": {"bp": 120.0, "day": 0, "fed": 0, "total": 9}}
	_check(not registry._take_companion("c#0", 1), "a bird below the companion stage cannot be taken")
	registry._bonds["c#0"] = {"1": {"bp": 320.0, "day": 0, "fed": 0, "total": 9}}
	_check(registry._take_companion("c#0", 1) and registry.companion_of(1) == "c#0", "a bird at the last stage becomes the companion")
	_check(not registry._take_companion("x#0", 1) or registry.companion_of(1) == "x#0", "taking another bird replaces the first (one companion)")
	registry._take_companion("c#0", 1)
	_check(registry.peer_of_companion("c#0") == 1 and registry.mode_of(1) == 0 and registry.mode_name(1) == "FOLGEN", "it starts in follow mode")
	registry._maintain_pets(PetRules.table()["territory"] as Dictionary)
	var comp: WildCorvid = registry._bird_of("c#0")
	_check(comp != null, "the companion is spawned next to its person")
	if comp != null:
		comp.set_physics_process(false)
		registry._tick_companions(0.4)
		_check(comp.companion_peer == 1, "the bird knows whose companion it is")
		comp.global_position = player.global_position + Vector2(300.0, 0.0)
		registry._tick_companions(0.4)
		_check(comp.state == WildCorvid.State.FLY, "a companion that is left behind flies after her")
		comp.state = WildCorvid.State.WATCH
		comp._moving = false
		comp.global_position = player.global_position + Vector2(10.0, 0.0)
		registry._still[1] = float(cfg["shoulder_after"]) + 1.0
		registry._tick_companions(0.4)
		_check(comp.rider == 1, "after she stood still it sits on her shoulder")
		comp._physics_process(0.016)
		_check(comp.global_position.distance_to(player.global_position) < 12.0 and comp._height > 10.0, "on the shoulder it is pinned to her, raised")
		player.velocity = Vector2(90.0, 0.0)
		registry._tick_companions(0.4)
		_check(comp.rider == 0, "running shakes it off the shoulder")
		player.velocity = Vector2.ZERO
		registry._cycle_mode(1)
		_check(registry.mode_of(1) == 1, "holding the whistle changes the mode to stay")
		registry._cycle_mode(1)
		_check(registry.mode_name(1) == "HEIM", "...then to home")
		registry._cycle_mode(1)
		_check(registry.mode_of(1) == 0, "...then back to follow")
		var saved_comp: Dictionary = registry.export_state()
		var again: PetRegistry = PetRegistry.new()
		add_child(again)
		again.import_state(saved_comp)
		_check(again.companion_of(1) == "c#0", "the companion survives a save")
		# hoard and finds
		var hb: ItemBox = registry.hoard("c#0")
		_check(hb.size() == int(cfg["hoard_slots"]), "the hoard has its slots")
		comp.state = WildCorvid.State.WATCH
		registry._gift_left[1] = 0.0
		registry._tick_finds(1, registry._comp[1] as Dictionary, comp, 0.4)
		var found: int = 0
		for stack: Dictionary in hb.slots:
			if not stack.is_empty():
				found += int(stack["count"])
		_check(found == 1, "a find lands in the hoard (%d)" % found)
		var saved_h: Dictionary = registry.export_state()
		var h2: PetRegistry = PetRegistry.new()
		add_child(h2)
		h2.import_state(saved_h)
		_check(h2.hoard("c#0").slots == hb.slots, "the hoard survives a save")
		for i: int in 12:
			registry._finds_day[1] = {"d": TimeManager.day, "n": 0}
			registry._gift_left[1] = 0.0
			registry._tick_finds(1, registry._comp[1] as Dictionary, comp, 0.4)
		_check(registry._finds_day[1]["n"] >= 0, "finds are counted per day")
		# E on the bird
		_check(registry.can_take("c#0", 1) == false, "its own companion cannot be taken again")
		# scout (raven)
		registry._pets["r#0"] = {"n": "SPÄHER", "sp": "raven", "ap": 0, "ring": 2, "home": [100.0, 100.0], "seen": [100.0, 100.0], "sd": 0, "rd": 0, "by": 1}
		registry._bonds["r#0"] = {"1": {"bp": 320.0, "day": 0, "fed": 0, "total": 9}}
		_check(registry.can_take("r#0", 1), "a second bird of the last stage can be taken")
		registry._take_companion("r#0", 1)
		registry._maintain_pets(PetRules.table()["territory"] as Dictionary)
		var raven: WildCorvid = registry._bird_of("r#0")
		_check(raven != null, "the raven companion is there")
		if raven != null:
			raven.set_physics_process(false)
			raven.global_position = player.global_position + Vector2(8.0, 0.0)
			registry._come(1)
			_check(registry._scouts.has(1) and raven.state == WildCorvid.State.FLY, "tap on a raven that is at hand sends it scouting")
			var sd: Dictionary = registry._scouts[1] as Dictionary
			raven.state = WildCorvid.State.WATCH
			raven.global_position = sd["goal"] as Vector2
			registry._tick_scout(1, raven, player, 0.4)
			_check(int((registry._scouts[1] as Dictionary)["ph"]) == 1, "at the turning point it reports and comes back")
			raven.state = WildCorvid.State.WATCH
			raven.global_position = player.global_position
			registry._tick_scout(1, raven, player, 0.4)
			_check(not registry._scouts.has(1), "the scout flight ends at her")
		registry._release_companion(1)
		_check(registry.companion_of(1) == "" and comp.companion_peer == 0, "releasing frees the bird")
	print("Pets: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
