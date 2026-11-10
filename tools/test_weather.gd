extends Node
## Weather checks (docs/wetter_konzept.md): the pure rules (determinism, continuity over midnight, distribution, calm start), the cloud field (coverage and
## shape of the CPU twin), lightning, the storm night, the manager's questions (exposure, alarm, sunlight) and the wind hand-over. Headless; prints WEATHER OK.
var failures: int = 0
func _ready() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func _run() -> void:
	var seed_a: int = 4242
	WeatherRules.reset()
	# determinism: the same seed and time always give the same sky, a rebuilt chain too
	var s1: WeatherRules.State = WeatherRules.state_at(seed_a, 7.31)
	WeatherRules.reset()
	var s2: WeatherRules.State = WeatherRules.state_at(seed_a, 7.31)
	check(is_equal_approx(s1.cloud, s2.cloud) and is_equal_approx(s1.rain, s2.rain) and is_equal_approx(s1.wind, s2.wind), "state_at is a pure function of seed and time")
	var other: WeatherRules.State = WeatherRules.state_at(seed_a + 1, 7.31)
	var any_diff: bool = false
	for e: float in [3.5, 6.2, 9.9, 14.4, 20.1]:
		if absf(WeatherRules.state_at(seed_a, e).cloud - WeatherRules.state_at(seed_a + 1, e).cloud) > 0.01: any_diff = true
	check(any_diff, "another world seed has another sky (%s)" % other.cloud)
	# the calm start: no rain, no storm before calm_until
	var calm_ok: bool = true
	var calm_until: float = float(WeatherRules.cfg().get("calm_until", 3.0))
	for k: int in 300:
		var e: float = float(k) / 300.0 * calm_until
		var st: WeatherRules.State = WeatherRules.state_at(seed_a, e)
		if st.rain > 0.02 or st.storm > 0.02: calm_ok = false
	check(calm_ok, "the first %.1f days are calm" % calm_until)
	# continuity: no jumps, also over day boundaries
	var worst: float = 0.0
	var prev: WeatherRules.State = WeatherRules.state_at(seed_a, 0.0)
	for k: int in range(1, 20000):
		var st: WeatherRules.State = WeatherRules.state_at(seed_a, float(k) * 0.002)
		worst = maxf(worst, maxf(absf(st.cloud - prev.cloud), maxf(absf(st.rain - prev.rain), absf(st.wind - prev.wind))))
		prev = st
	check(worst < 0.12, "no jumps: worst step %.3f per 2 minutes" % worst)
	# distribution over many seeds and days
	var sunny: int = 0
	var rainy: int = 0
	var stormy: int = 0
	var total: int = 0
	for sd: int in 12:
		for k: int in range(0, 90 * 24):
			var st: WeatherRules.State = WeatherRules.state_at(1000 + sd, 3.5 + float(k) / 24.0)
			total += 1
			if st.cloud < 0.35 and st.rain < 0.05: sunny += 1
			if st.rain > 0.15: rainy += 1
			if st.storm > 0.5: stormy += 1
	var f_sun: float = float(sunny) / float(total)
	var f_rain: float = float(rainy) / float(total)
	var f_storm: float = float(stormy) / float(total)
	check(f_sun > 0.25 and f_sun < 0.75, "sunny share %.0f %%" % (f_sun * 100.0))
	check(f_rain > 0.07 and f_rain < 0.35, "rain share %.0f %%" % (f_rain * 100.0))
	check(f_storm > 0.002 and f_storm < 0.08, "storm share %.1f %%" % (f_storm * 100.0))
	# the ground: wet after rain, dry again after days
	var wet_seen: bool = false
	var dry_seen: bool = false
	for k: int in range(0, 60 * 8):
		var w: float = WeatherRules.ground_wet(1003, 3.5 + float(k) / 8.0)
		if w > 0.5: wet_seen = true
		if w < 0.05: dry_seen = true
		if w < 0.0 or w > 1.0: failures += 1
	check(wet_seen and dry_seen, "the ground gets wet and dries again")
	# the cloud field
	var field: WeatherField = WeatherField.new()
	field._finish(field._generate(seed_a), Callable())
	check(field.ready_now and field.image.get_width() == WeatherField.SIZE, "cloud field built (%dx%d)" % [field.image.get_width(), field.image.get_height()])
	for want: float in [0.2, 0.5, 0.8]:
		field.thresh = field.threshold(want)
		var covered: int = 0
		var n: int = 3000
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 9
		for i: int in n:
			if field.density(Vector2(rng.randf() * 6000.0, rng.randf() * 6000.0), Vector2.ZERO) > field.thresh: covered += 1
		var share: float = float(covered) / float(n)
		check(absf(share - want) < 0.09, "coverage %.1f gives %.0f %% cloud" % [want, share * 100.0])
	field.thresh = field.threshold(0.0)
	check(field.thresh > 1.5 and field.thick(Vector2(100, 100)) == 0.0, "no cloud at coverage 0")
	field.thresh = field.threshold(0.5)
	field.rain_regime = 0.0
	check(field.rain_at(Vector2(300, 200)) == 0.0, "no rain without a rain regime")
	field.rain_regime = 0.8
	var rainy_px: int = 0
	var dry_px: int = 0
	for i: int in 400:
		var r: float = field.rain_at(Vector2(float(i) * 13.0, float(i) * 7.0))
		if r > 0.05: rainy_px += 1
		else: dry_px += 1
	check(rainy_px > 40 and dry_px > 40, "a rain cell: rain here, dry there (%d / %d)" % [rainy_px, dry_px])
	var wrapped: bool = absf(field.density(Vector2(100, 100), Vector2.ZERO) - field.density(Vector2(100.0 + WeatherField.TILE_A, 100.0), Vector2.ZERO)) < 0.001
	check(wrapped, "the cloud field tiles seamlessly")
	# lightning is a pure function; none in weak weather
	var seen: int = 0
	var same: bool = true
	for slice: int in 4000:
		var a: Dictionary = WeatherRules.lightning(seed_a, slice, 1.0)
		var b: Dictionary = WeatherRules.lightning(seed_a, slice, 1.0)
		if a != b: same = false
		if not a.is_empty(): seen += 1
	check(same and seen > 100 and seen < 1200, "lightning: pure, %d strikes in 4000 s of storm" % seen)
	check(WeatherRules.lightning(seed_a, 12, 0.1).is_empty(), "no lightning below the storm threshold")
	# the storm night
	var night_id: int = -1
	for d: int in range(4, 400):
		if NightRules.special_for(seed_a, d) == "storm":
			night_id = d
			break
	check(night_id > 0, "the special night kind 'storm' exists (night %d)" % night_id)
	if night_id > 0:
		var mid: float = float(night_id) + 0.75
		check(WeatherRules.storm_night(seed_a, mid) > 0.99, "storm night holds the weather at midnight")
		check(WeatherRules.state_at(seed_a, mid).storm > 0.9, "the sky is a storm in that night")
		check(WeatherRules.storm_night(seed_a, float(night_id) + 0.2) < 0.01, "the evening before is free")
	# the manager's questions
	var weather: WeatherManager = WeatherManager.new()
	add_child(weather)
	check(weather.sunlight() > 0.5, "full sun under a young sky")
	weather.cloud = 1.0
	weather.rain = 1.0
	weather.storm = 1.0
	check(weather.sunlight() < 0.2 and weather.ambient_dim() < 0.75, "a storm takes the sun and dims the light")
	check(weather.alarm_factor() >= 0.6 and weather.alarm_factor() < 1.0 or weather.local_rain == 0.0, "alarm factor in range")
	check(weather.exposure_at(Vector2.ZERO) >= 0.0, "exposure answers without a field")
	weather.queue_free()
	# the wind hand-over
	var wind: WorldWind = WorldWind.new()
	add_child(wind)
	wind.set_weather(0.9, 0.5, 1.0, 1.0)
	check(wind.strength > 0.85 and wind.storm > 0.9, "WorldWind takes the weather's strength")
	wind.queue_free()
	# moisture follows the weather
	var w_days: int = 0
	for d: int in range(1, 120):
		Moisture.world_seed = seed_a
		if Moisture.is_wet_day(d): w_days += 1
	check(w_days > 3 and w_days < 90, "wet days from the weather: %d of 119" % w_days)
	print("WEATHER OK" if failures == 0 else "WEATHER FAILED %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
