extends Node
## Headless unit tests for M2 Lost-Ark combat upgrades:
## CounterComponent (frontal cone check, rear rejection, stun, cooldown, +25% vuln),
## StaggerComponent (1-4P scaling, stagger break, EXPOSED +30% vuln, timeout failure),
## and BossBar v2 (multi-layer x5 HP tracking & integrated golden stagger bar).
## Run: Godot --headless --path . res://tools/test_dungeon_combat.tscn  (prints DUNGEON COMBAT OK)

var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	NetworkManager.host_singleplayer()
	_test_counter_component()
	_test_stagger_component()
	_test_boss_bar_multilayer()
	if _failed == 0:
		print("DUNGEON COMBAT OK (%d checks)" % _checks)
	else:
		push_error("DUNGEON COMBAT FAILED (%d/%d failed)" % [_failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		push_error("FAIL: %s" % label)


func _test_counter_component() -> void:
	var dummy: Node2D = Node2D.new()
	dummy.position = Vector2(200.0, 200.0)
	add_child(dummy)
	var hp: HealthComponent = HealthComponent.new()
	hp.name = "HealthComponent"
	hp.max_health = 200.0
	dummy.add_child(hp)
	var cnt: CounterComponent = CounterComponent.new()
	cnt.cooldown_seconds = 15.0
	cnt.stun_seconds = 2.8
	dummy.add_child(cnt)

	var fired_peer: Array[int] = [0]
	cnt.countered.connect(func(peer_id: int) -> void: fired_peer[0] = peer_id)

	_check(cnt.can_open_window(), "counter ready initially")
	_check(cnt.open_window(Vector2.RIGHT, 0.5), "counter window opens facing east")
	_check(cnt.window_open, "window_open is true")
	## Rear hit (west of dummy) MUST NOT counter
	_check(not CounterComponent.try_hit_counter(dummy, Vector2(150.0, 200.0), 1), "rear hit rejected")
	_check(cnt.window_open, "window stays open after rear hit")
	## Frontal hit (east of dummy) MUST counter
	_check(CounterComponent.try_hit_counter(dummy, Vector2(240.0, 200.0), 1), "frontal hit triggers counter")
	_check(not cnt.window_open and cnt.is_stunned(), "counter closes window and stuns enemy")
	_check(fired_peer[0] == 1, "countered signal emitted with peer 1")
	_check(is_equal_approx(CounterComponent.vulnerability_of(dummy), 1.25), "countered enemy has 1.25x vuln")
	_check(not cnt.can_open_window(), "internal cooldown prevents immediate re-open")

	## Verify HealthComponent applies +25% vulnerability while countered
	hp.take_damage(20.0, Vector2(240.0, 200.0), 0.0, 1)
	_check(is_equal_approx(hp.current, 175.0), "20 dmg * 1.25 counter vuln = 25 dmg (175 HP left)")
	dummy.queue_free()


func _test_stagger_component() -> void:
	var boss: Node2D = Node2D.new()
	add_child(boss)
	var hp: HealthComponent = HealthComponent.new()
	hp.name = "HealthComponent"
	hp.max_health = 300.0
	boss.add_child(hp)
	var stg: StaggerComponent = StaggerComponent.new()
	boss.add_child(stg)

	var outcome: Array[String] = [""]
	stg.stagger_broken.connect(func(_p: int) -> void: outcome[0] = "broken")
	stg.stagger_failed.connect(func() -> void: outcome[0] = "failed")

	## 2-player scaling: 100 base * 1.75 = 175 stagger
	stg.begin_check(100.0, 3.8, 2)
	_check(stg.active and is_equal_approx(stg.max_stagger, 175.0), "2P stagger scales to 175")
	_check(not StaggerComponent.try_hit_stagger(boss, 55.0, 1), "first heavy (55) leaves 120")
	_check(is_equal_approx(stg.current_stagger, 120.0), "stagger reduced to 120")
	_check(StaggerComponent.try_hit_stagger(boss, 130.0, 1), "depleting stagger breaks bar")
	_check(not stg.active and stg.is_exposed() and outcome[0] == "broken", "boss enters EXPOSED on stagger break")
	_check(is_equal_approx(StaggerComponent.vulnerability_of(boss), 1.30), "EXPOSED enemy has 1.30x vuln")

	hp.take_damage(10.0, Vector2.ZERO, 0.0, 1)
	_check(is_equal_approx(hp.current, 287.0), "10 dmg * 1.30 EXPOSED vuln = 13 dmg (287 HP left)")

	## Verify timeout failure
	outcome[0] = ""
	stg.exposed_left = 0.0
	stg.begin_check(100.0, 0.2, 1)
	stg._process(0.25)
	_check(not stg.active and outcome[0] == "failed", "stagger timeout emits stagger_failed")
	boss.queue_free()


func _test_boss_bar_multilayer() -> void:
	var boss: Node2D = Node2D.new()
	add_child(boss)
	var hp: HealthComponent = HealthComponent.new()
	hp.name = "HealthComponent"
	hp.max_health = 500.0
	boss.add_child(hp)
	var stg: StaggerComponent = StaggerComponent.new()
	boss.add_child(stg)

	var bar: BossBar = BossBar.new()
	add_child(bar)
	bar.track("VORGATH, BRUT DER MOLE", hp, 5, stg)
	_check(bar.is_fighting(), "BossBar fighting active")
	_check(bar.current_bar_number() == 5, "full 500/500 HP = bar x5")

	hp.current = 400.0
	_check(bar.current_bar_number() == 4, "400/500 HP = bar x4")
	hp.current = 301.0
	_check(bar.current_bar_number() == 4, "301/500 HP still bar x4")
	hp.current = 250.0
	_check(bar.current_bar_number() == 3, "250/500 HP = bar x3")
	hp.current = 100.0
	_check(bar.current_bar_number() == 1, "100/500 HP = final bar x1")
	hp.current = 1.0
	_check(bar.current_bar_number() == 1, "1/500 HP = final bar x1")

	stg.begin_check(90.0, 3.8, 1)
	bar._process(0.3)
	_check(bar._stagger_open > 0.5, "stagger bar expands smoothly when check active")

	bar.release()
	bar.queue_free()
	boss.queue_free()
