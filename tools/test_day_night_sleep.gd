extends Node
## Verifies the 40m/12m day-night cycle, 10%-70% rolling sleep threshold, dynamic wake time,
## rested/tired stamina effects, lamp fuel skip deduction, and sleep state serialization.

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	# 1. Cycle timing: 40 min total, 12 min (30%) dark night, 28 min (70%) day+twilight
	check(is_equal_approx(TimeManager.DAY_LENGTH_SEC, 2400.0), "40 minute full cycle (2400s)")
	check(is_equal_approx(TimeManager.NIGHT_START, 0.875), "night starts at 0.875 (21:00)")
	check(is_equal_approx(TimeManager.NIGHT_END, 0.175), "night ends at 0.175 (04:12)")
	check(is_equal_approx(TimeManager.night_span(), 0.30), "night spans 30% (12 min)")
	check(is_equal_approx(TimeManager.night_hours(), 7.2), "night spans 7.2 in-game hours")
	check(is_equal_approx(TimeManager.night_at(0.5), 0.0), "noon has 0.0 night_at")
	check(is_equal_approx(TimeManager.night_at(0.9), 1.0), "21:36 has 1.0 night_at")
	check(is_equal_approx(TimeManager.night_at(0.1), 1.0), "02:24 has 1.0 night_at")

	# 2. Rolling 10%-70% threshold
	check(is_equal_approx(SleepRules.unlock_progress(0.5), 0.40), "default fatigue 0.5 -> 40% night threshold")
	check(is_equal_approx(SleepRules.unlock_progress(0.0), 0.70), "well-rested fatigue 0.0 -> 70% night threshold")
	check(is_equal_approx(SleepRules.unlock_progress(1.0), 0.10), "exhausted fatigue 1.0 -> 10% night threshold")

	var f: float = 0.5
	f = SleepRules.fatigue_after_sleep(f, 0.40)
	f = SleepRules.fatigue_after_sleep(f, 0.55)
	f = SleepRules.fatigue_after_sleep(f, 0.70)
	check(is_equal_approx(f, 0.0), "consistent timely sleep reaches 0.0 fatigue (70% threshold)")

	var late_f: float = SleepRules.fatigue_after_sleep(0.0, 0.95)
	check(late_f > 0.25, "very late sleep increases fatigue (%.2f)" % late_f)

	var all_night_once: float = SleepRules.fatigue_after_all_nighter(0.5)
	check(is_equal_approx(all_night_once, 1.0), "1 all-nighter from normal reaches 10% threshold")
	var two_all_nighters: float = SleepRules.fatigue_after_all_nighter(SleepRules.fatigue_after_all_nighter(0.0))
	check(is_equal_approx(two_all_nighters, 1.0), "2 all-nighters from rested reaches 10% threshold")

	check(not SleepRules.can_sleep(0.50, 1.0), "cannot sleep during daytime even when exhausted")
	check(not SleepRules.can_sleep(0.88, 1.0), "cannot sleep right at 21:00 (< 10% of night)")
	check(SleepRules.can_sleep(0.91, 1.0), "can sleep after 10% of night when exhausted")
	check(not SleepRules.can_sleep(0.01, 0.0), "rested player cannot sleep at 45% of night")
	check(SleepRules.can_sleep(0.09, 0.0), "rested player can sleep at ~71.7% of night")

	# 3. Dynamic wake-up time (Idea 1) & morning dew preservation
	var wake_early: float = SleepRules.wake_time(0.10)
	var wake_late: float = SleepRules.wake_time(1.0)
	check(wake_early >= TimeManager.DAY_START and wake_early < 0.27, "early sleep wakes shortly after 06:00 (%.4f)" % wake_early)
	check(is_equal_approx(wake_late, 0.375), "very late sleep wakes at 09:00 (0.375)")
	TimeManager.set_time(wake_early)
	var dew_early: float = TimeManager.dew_amount()
	TimeManager.set_time(wake_late)
	var dew_late: float = TimeManager.dew_amount()
	check(dew_early > dew_late + 0.3, "sleeping early preserves morning dew (%.2f vs %.2f)" % [dew_early, dew_late])

	# 4. Skipped night hours & data text
	check(is_equal_approx(SleepRules.skipped_night_hours(0.875), 7.2), "full night skip equals 7.2h")
	check(is_equal_approx(SleepRules.skipped_night_hours(0.025), 3.6), "half night skip equals 3.6h")
	check(SleepRules.skipped_night_hours(0.5) == 0.0, "daytime skipped_night_hours is 0")
	var texts: Dictionary = SleepRules.text_cfg()
	check(String(texts.get("not_tired_hint", "")) != "" and String(texts.get("not_tired_speech", "")) != "", "sleep text localization loaded")

	# 5. StaminaComponent + StatusEffects multipliers (Idea 2)
	check(SleepRules.should_grant_well_rested(0.45), "0.45 night progress grants well_rested")
	check(not SleepRules.should_grant_well_rested(0.90), "0.90 night progress does not grant well_rested")
	var dummy: Node2D = Node2D.new()
	add_child(dummy)
	var health: HealthComponent = HealthComponent.new()
	health.name = "HealthComponent"
	dummy.add_child(health)
	var fx: StatusEffects = StatusEffects.new()
	fx.name = "Effects"
	fx.health = health
	dummy.add_child(fx)
	var stam: StaminaComponent = StaminaComponent.new()
	stam.name = "StaminaComponent"
	dummy.add_child(stam)
	check(is_equal_approx(stam.regen_scale(), 1.0), "baseline stamina regen_scale is 1.0")
	fx.apply("well_rested", 10.0, 1.0)
	check(is_equal_approx(stam.regen_scale(), 1.12), "well_rested grants +12% stamina regen")
	fx.clear("well_rested")
	fx.apply("tired", 10.0, 1.0)
	check(is_equal_approx(stam.regen_scale(), 0.90), "tired tier I applies -10% stamina regen")
	fx.apply("tired", 10.0, 2.0)
	check(is_equal_approx(stam.regen_scale(), 0.80), "tired tier II applies -20% stamina regen")
	dummy.queue_free()

	# 6. TimeManager record_sleep, all-nighter tracking, and export/import round-trip
	TimeManager.unlock()
	TimeManager.day = 2
	TimeManager.time_of_day = 0.995 ## 40% night progress
	TimeManager.reset_sleep_state()
	check(TimeManager.can_sleep_now(), "TimeManager.can_sleep_now true at default 40% threshold")
	TimeManager.time_of_day = 0.95
	check(not TimeManager.can_sleep_now(), "TimeManager.can_sleep_now false at 25% night progress with default fatigue")
	TimeManager.set_time(0.28) ## crosses sunrise on day 2 without sleeping -> all-nighter
	check(TimeManager.day == 3 and TimeManager.nights_awake == 1, "staying up past sunrise increments nights_awake")
	check(TimeManager.sleep_fatigue > 0.95, "staying up raises sleep_fatigue toward max")

	var exported: Dictionary = TimeManager.export_sleep_state()
	TimeManager.reset_sleep_state()
	TimeManager.import_sleep_state(exported)
	check(TimeManager.nights_awake == 1 and is_equal_approx(TimeManager.sleep_fatigue, float(exported.fatigue)), "sleep state export/import round-trips cleanly")

	TimeManager.set_time(0.92)
	TimeManager.record_sleep(0.15)
	TimeManager.set_time(SleepRules.wake_time(0.15))
	check(TimeManager.nights_awake == 0 and TimeManager.day == 4, "sleeping resets nights_awake and advances day without all-nighter penalty")

	# 7. In-world BedRestSpot ("DU BIST NOCH NICHT MÜDE") & night skip integration
	await _test_world_bed()

	print("DAY_NIGHT_SLEEP failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_world_bed() -> void:
	const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")
	NetworkManager.host_singleplayer()
	var world: WorldLevel = WORLD_SCENE.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	for _i: int in 4:
		await get_tree().process_frame

	var hero: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	hero.quests.import_data({"active": {}, "done": ["find_help", "lumberjack", "rebuild_hut", "town_start"], "flags": {"rebuild_done": true, "knows_adventurer": true, "hud_unlocked": true, "day2_started": true, "left_hut": true}})
	if hut != null:
		hero.request_teleport(hut.position + Vector2(0, 120))
		for _i: int in 150:
			await get_tree().process_frame
		interiors.use_door(hero, hut.doorway)
		for _i: int in 150:
			await get_tree().process_frame
	var room: Interior = interiors.interior("hut")
	var bed_sleep: BedRestSpot = room.get_node_or_null("BedSleep") as BedRestSpot if room != null else null
	check(bed_sleep != null, "BedSleep BedRestSpot exists in hut interior")
	if bed_sleep != null:
		TimeManager.unlock()
		TimeManager.reset_sleep_state()
		TimeManager.day = 3
		TimeManager.time_of_day = 0.90 ## 8.3% of night (< 40% default)
		check(bed_sleep.prompt() == "SCHLAFEN", "BedSleep prompt is SCHLAFEN")
		check(bed_sleep.prompt_hint() == "DU BIST NOCH NICHT MÜDE", "BedSleep shows not-tired hint before threshold")
		var xp_before: int = hero.progress.xp
		hero.effects.apply("tired", 300.0, 2.0)
		TimeManager.time_of_day = 0.01 ## past 40% threshold
		check(bed_sleep.prompt() == "SCHLAFEN" and bed_sleep.prompt_hint() == "", "BedSleep unlocks after threshold with empty hint")
		# Spawn a test night enemy / burn lamps & commit sleep
		var enemy_holder: Node2D = Node2D.new()
		world.night._live.append({"node": enemy_holder, "nb": NightBehavior.new(), "key": "k", "cost": 1.0, "id": "stalker"})
		world.add_child(enemy_holder)
		var hours: float = SleepRules.skipped_night_hours(TimeManager.time_of_day)
		var sleep_p: float = TimeManager.night_progress()
		world._server_commit_rest_sleep(sleep_p, SleepRules.wake_time(sleep_p), hours)
		await get_tree().process_frame
		check(world.night.live_count() == 0, "NightDirector.skip_night clears active night creatures")
		check(hero.progress.xp == xp_before, "skipping night via sleep awards no night_survived XP")
		check(not hero.effects.has("tired") and hero.effects.has("well_rested"), "sleeping clears tired and grants well_rested")
		check(TimeManager.day == 4 and TimeManager.nights_awake == 0, "committed sleep advances day cleanly without all-nighter")
	world.queue_free()
	await get_tree().process_frame
