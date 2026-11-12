class_name BoardRules
extends RefCounted
## The pure rules of the quest board (docs/questtafel_konzept.md): which notices may hang, how one is rolled, what it says and pays, when it runs out.
## No nodes, so the host (`BoardManager`), the window and the tests all ask the same functions. Data: data/board.json.
## A notice is a plain Dictionary: {id, k "fetch" | "kill" | "story", g giver, tx template id, t item or species, n count, c copper, x xp, tr trust,
## b bonus {id, n} or {}, d day posted, e day it runs out (-1 = never), txt text, ti title (story), q quest id (story)}.
## Occasions (docs/questtafel_ausbau_konzept.md 2.5) and rush notices add optional keys: w why (the chip), oc occasion id, a area [x, y, radius] in px, win "night" (only kills at night count),
## u rush notice (true) with ut the time of day it ends (dusk).
## A wanted poster (docs/questtafel_ausbau_konzept.md 2.7) is a `kill` notice with bn (the marked creature's name), bh (nights it survived) and a = its last place; it never runs out until it falls.

const FETCH: String = "fetch"
const KILL: String = "kill"
const STORY: String = "story"


static func config() -> Dictionary:
	return DataRegistry.table("board")


static func piece() -> String:
	return String(config().get("piece", "quest_board"))


static func reach() -> float:
	return float(config().get("reach", 150.0))


## How close (px) to the giver a player must stand to report a finished notice.
static func giver_reach() -> float:
	return float(config().get("giver_reach", 110.0))


## What a settler says when a notice is handed in (placeholders for the dialogue writer).
static func thanks() -> Array:
	return config().get("thanks", []) as Array


static func limit(key: String) -> int:
	return int((config().get("limits", {}) as Dictionary).get(key, 0))


static func templates() -> Array:
	return config().get("templates", []) as Array


static func story_entries() -> Array:
	return config().get("story", []) as Array


## Can this template be posted now by `giver` (a resident with `trust`) on `day`?
static func eligible(template: Dictionary, giver: String, trust: int, day: int) -> bool:
	var givers: Array = template.get("givers", []) as Array
	if not givers.is_empty() and not givers.has(giver):
		return false
	return day >= int(template.get("min_day", 0)) and trust >= int(template.get("min_trust", 0))


## Rolls one new simple notice, or {} when nothing fits. `residents` is TownManager.residents (id -> {trust}), `open` the notices that hang now.
## A giver has at most `per_giver` open notices and no template hangs twice at once.
static func roll(rng: RandomNumberGenerator, residents: Dictionary, open: Array, day: int, id: int) -> Dictionary:
	var per_giver: int = limit("per_giver")
	var used: Dictionary = {}
	var hanging: Dictionary = {}
	for raw: Variant in open:
		var offer: Dictionary = raw as Dictionary
		used[String(offer.g)] = int(used.get(String(offer.g), 0)) + 1
		hanging[String(offer.get("tx", ""))] = true
	var choices: Array[Array] = []
	for raw: Variant in templates():
		var template: Dictionary = raw as Dictionary
		if hanging.has(String(template.id)):
			continue
		for giver: String in residents:
			if int(used.get(giver, 0)) >= per_giver:
				continue
			if eligible(template, giver, int((residents[giver] as Dictionary).get("trust", 0)), day):
				choices.append([template, giver])
	if choices.is_empty():
		return {}
	var pick: Array = choices[rng.randi_range(0, choices.size() - 1)]
	return make(rng, pick[0] as Dictionary, String(pick[1]), day, id)


## One notice from a template: count, pay and expiry are rolled once here and stay fixed.
static func make(rng: RandomNumberGenerator, template: Dictionary, giver: String, day: int, id: int) -> Dictionary:
	var span: Array = template.get("count", [1, 1]) as Array
	var count: int = rng.randi_range(int(span[0]), int(span[1]))
	var pay: Array = template.get("copper_each", [0, 0]) as Array
	var copper: int = count * rng.randi_range(int(pay[0]), int(pay[1]))
	var life: Array = config().get("lifetime", [3, 5]) as Array
	var kind: String = String(template.kind)
	var target: String = String(template.get("item", "")) if kind == FETCH else String(template.get("species", ""))
	var bonus: Dictionary = {}
	var extra: Dictionary = template.get("bonus", {}) as Dictionary
	if not extra.is_empty() and rng.randf() < float(extra.get("chance", 1.0)):
		bonus = {"id": String(extra.id), "n": int(extra.get("n", 1))}
	var offer: Dictionary = {
		"id": id, "k": kind, "g": giver, "tx": String(template.id), "t": target, "n": count, "c": copper,
		"x": count * int(template.get("xp_each", 0)), "tr": int(template.get("trust", 0)), "b": bonus,
		"d": day, "e": day + rng.randi_range(int(life[0]), int(life[1])),
	}
	offer["txt"] = text_of(offer, String(template.get("text", "")))
	return offer


## The story notice for an entry of `story` (never runs out; the quest starts when somebody takes it).
static func make_story(entry: Dictionary, day: int, id: int) -> Dictionary:
	return {
		"id": id, "k": STORY, "g": String(entry.get("giver", "")), "tx": String(entry.id), "q": String(entry.quest), "ti": String(entry.get("title", "")),
		"txt": String(entry.get("text", "")), "n": 0, "c": 0, "x": 0, "tr": 0, "b": {}, "t": "", "d": day, "e": -1,
	}


static func template_of(id: String) -> Dictionary:
	for raw: Variant in templates():
		if String((raw as Dictionary).id) == id:
			return raw as Dictionary
	return {}


## `{count}` and `{item}` in the template's text (placeholders for the dialogue writer).
static func text_of(offer: Dictionary, pattern: String) -> String:
	return pattern.replace("{count}", str(int(offer.n))).replace("{item}", item_name(String(offer.t))).replace("{species}", species_name(String(offer.t)))


static func species_name(id: String) -> String:
	return String(DataRegistry.get_entry("enemies", id).get("name", id.replace("_", " "))).to_upper()


static func item_name(id: String) -> String:
	return Items.title({"id": id, "count": 1}).to_upper()


# ---------- wanted posters (the marked ones) ----------

static func bounty_cfg() -> Dictionary:
	return config().get("bounty", {}) as Dictionary


static func is_bounty(offer: Dictionary) -> bool:
	return offer.has("bn")


## The poster for a marked creature `mark` {name, species, nights, pos [x, y]}: pay grows with every night it survived.
static func make_bounty(mark: Dictionary, giver: String, day: int, id: int) -> Dictionary:
	var cfg: Dictionary = bounty_cfg()
	var nights: int = maxi(1, int(mark.get("nights", 1)))
	var pos: Array = mark.get("pos", [0.0, 0.0]) as Array
	var bonus: Dictionary = (cfg.get("loot", {}) as Dictionary).duplicate()
	var offer: Dictionary = {
		"id": id, "k": KILL, "g": giver, "tx": "bounty", "t": String(mark.species), "n": 1,
		"c": roundi(float(cfg.get("copper", 400)) * (1.0 + float(cfg.get("copper_per_night", 0.2)) * float(nights - 1))),
		"x": int(cfg.get("xp", 80)), "tr": int(cfg.get("trust", 10)), "b": bonus,
		"d": day, "e": -1, "bn": String(mark.name), "bh": nights, "w": String(cfg.get("why", "GEZEICHNET")),
		"a": [float(pos[0]), float(pos[1]), float(cfg.get("search_px", 640.0))],
	}
	offer["txt"] = String(cfg.get("text", "")).replace("{name}", String(mark.name)).replace("{nights}", str(nights))
	return offer


static func is_expired(offer: Dictionary, day: int) -> bool:
	return int(offer.e) >= 0 and day >= int(offer.e)


static func days_left(offer: Dictionary, day: int) -> int:
	return -1 if int(offer.e) < 0 else maxi(0, int(offer.e) - day)


## The last day (exclusive, like `e`) a player may still hand in a notice they took: a notice they carry does not vanish with the board's, it keeps its own deadline
## (`personal.min_days` after taking it, at least until the notice itself would run out). -1 = never (story).
static func due_for(offer: Dictionary, day: int) -> int:
	if int(offer.e) < 0:
		return -1
	return maxi(int(offer.e), day + int((config().get("personal", {}) as Dictionary).get("min_days", 2)))


## The deadline of a taken entry (old saves have none: the notice's own).
static func entry_due(offer: Dictionary, entry: Dictionary) -> int:
	return int(entry.get("due", offer.e))


static func entry_days_left(offer: Dictionary, entry: Dictionary, day: int) -> int:
	var due: int = entry_due(offer, entry)
	return -1 if due < 0 else maxi(0, due - day)


static func entry_expired(offer: Dictionary, entry: Dictionary, day: int, tod: float) -> bool:
	var due: int = entry_due(offer, entry)
	return (due >= 0 and day >= due) or urgent_over(offer, day, tod)


static func entry_active(offer: Dictionary, entry: Dictionary, day: int, tod: float) -> bool:
	return not offer.is_empty() and String(offer.k) != STORY and not entry.is_empty() and not bool(entry.get("done", false)) and not entry_expired(offer, entry, day, tod)


## Does the notice still hang on the board (a notice only held by those who took it has run out)?
static func is_hanging(offer: Dictionary, day: int, tod: float = -1.0) -> bool:
	return not is_expired(offer, day) and not urgent_over(offer, day, TimeManager.time_of_day if tod < 0.0 else tod)


# ---------- rush notices ----------

static func urgent_cfg() -> Dictionary:
	return config().get("urgent", {}) as Dictionary


static func is_urgent(offer: Dictionary) -> bool:
	return bool(offer.get("u", false))


## A rush notice is only good until dusk of the day it was posted (the clock, not the days).
static func urgent_over(offer: Dictionary, day: int, tod: float) -> bool:
	if not is_urgent(offer):
		return false
	if day > int(offer.d):
		return true
	return tod >= float(offer.get("ut", 0.8)) or tod < TimeManager.DAY_START


## 1 just posted at sunrise .. 0 dusk (the ring in the quest branch); 1 for notices without a clock.
static func urgent_left(offer: Dictionary, tod: float) -> float:
	if not is_urgent(offer):
		return 1.0
	var until: float = float(offer.get("ut", 0.8))
	return clampf((until - tod) / maxf(until - TimeManager.DAY_START, 0.01), 0.0, 1.0)


## Game hours until dusk (rounded up), for the window.
static func urgent_hours(offer: Dictionary, tod: float) -> int:
	return ceili(maxf(float(offer.get("ut", 0.8)) - tod, 0.0) * 24.0)


## Makes a notice a rush notice: double pay, double trust, the extra item for sure, good until dusk.
static func urgentize(offer: Dictionary, template: Dictionary) -> void:
	var u: Dictionary = urgent_cfg()
	offer["c"] = roundi(float(offer.c) * float(u.get("copper", 2.0)))
	offer["x"] = roundi(float(offer.x) * float(u.get("xp", 2.0)))
	offer["tr"] = roundi(float(offer.tr) * float(u.get("trust", 2.0)))
	var extra: Dictionary = template.get("bonus", {}) as Dictionary
	if not extra.is_empty():
		offer["b"] = {"id": String(extra.id), "n": int(extra.get("n", 1))}
	offer["u"] = true
	offer["ut"] = float(u.get("until", 0.8))
	offer["e"] = int(offer.d) + 1


# ---------- occasions ----------

static func occasions() -> Array:
	return config().get("occasions", []) as Array


static func occasion_of(id: String) -> Dictionary:
	for raw: Variant in occasions():
		if String((raw as Dictionary).id) == id:
			return raw as Dictionary
	return {}


## The eight points of the compass for an angle (0 = east, clockwise on the map: +y is south).
const COMPASS: Array[String] = ["OSTEN", "SÜDOSTEN", "SÜDEN", "SÜDWESTEN", "WESTEN", "NORDWESTEN", "NORDEN", "NORDOSTEN"]


static func compass(angle: float) -> String:
	return COMPASS[posmod(roundi(fposmod(angle, TAU) / (TAU / 8.0)), 8)]


## Which occasions are due on `ctx.day`, in the order of the table: {occ, hit}. `ctx` {day, moon_day, stock, storm_yesterday, wet_days, report}; `last` occasion id -> day it was posted.
static func due_occasions(ctx: Dictionary, last: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var day: int = int(ctx.get("day", 0))
	for raw: Variant in occasions():
		var occ: Dictionary = raw as Dictionary
		if day < int(occ.get("min_day", 0)):
			continue
		if day - int(last.get(String(occ.id), -9999)) < int(occ.get("cooldown", 1)):
			continue
		var hit: Dictionary = _when(occ.get("when", {}) as Dictionary, ctx)
		if not hit.is_empty():
			out.append({"occ": occ, "hit": hit})
	return out


## All conditions of an occasion; {} = does not hold, otherwise {ok: true} plus what the conditions found (item + gap of the emptiest store, the night's report).
static func _when(when: Dictionary, ctx: Dictionary) -> Dictionary:
	var hit: Dictionary = {"ok": true}
	for key: String in when:
		match key:
			"stock_below":
				var stock: Dictionary = ctx.get("stock", {}) as Dictionary
				var worst: String = ""
				var worst_rel: float = 0.0
				var limits: Dictionary = when[key] as Dictionary
				for item: String in limits:
					var need: int = int(limits[item])
					var have: int = int(stock.get(item, 0))
					if have < need and float(need - have) / float(need) > worst_rel:
						worst = item
						worst_rel = float(need - have) / float(need)
						hit["gap"] = need - have
				if worst == "":
					return {}
				hit["item"] = worst
			"storm_yesterday":
				if bool(when[key]) != bool(ctx.get("storm_yesterday", false)):
					return {}
			"wet_days":
				if int(ctx.get("wet_days", 0)) < int(when[key]):
					return {}
			"moon":
				if int(ctx.get("moon_day", -1)) != int(when[key]):
					return {}
			"intruders":
				var report: Dictionary = ctx.get("report", {}) as Dictionary
				if int(report.get("intruders", 0)) < int(when[key]) or String(report.get("species", "")) == "":
					return {}
				hit["report"] = report
			_:
				return {}
	return hit


## The notice of one due occasion (see `due_occasions`), or {} when its template is missing.
static func make_occasion(rng: RandomNumberGenerator, occ: Dictionary, hit: Dictionary, giver: String, day: int, id: int, make_urgent: bool) -> Dictionary:
	var template: Dictionary = {}
	if hit.has("item") and occ.has("templates"):
		template = template_of(String((occ.templates as Dictionary).get(String(hit.item), "")))
	elif occ.has("template"):
		template = template_of(String(occ.template))
	if template.is_empty():
		return {}
	var offer: Dictionary = make(rng, template, giver, day, id)
	var base: int = maxi(int(offer.n), 1)
	var per_copper: float = float(offer.c) / float(base)
	var per_xp: float = float(offer.x) / float(base)
	var span: Array = template.get("count", [1, 1]) as Array
	var count: int = int(offer.n)
	var side: String = ""
	if hit.has("gap"):
		count = clampi(int(hit.gap), int(span[0]), int(span[1]) + int(occ.get("count_extra", 0)))
	if hit.has("report"):
		var report: Dictionary = hit.report as Dictionary
		offer["t"] = String(report.species)
		count = clampi(int(report.intruders), int(span[0]), int(span[1]) + int(occ.get("count_extra", 2)))
		side = String(report.get("compass", ""))
		var at: Array = report.get("pos", [0.0, 0.0]) as Array
		offer["a"] = [float(at[0]), float(at[1]), 170.0]
	elif occ.has("count"):
		var own: Array = occ.count as Array
		count = rng.randi_range(int(own[0]), int(own[1]))
	var pay: float = float(occ.get("pay", 1.0))
	offer["n"] = count
	offer["c"] = roundi(per_copper * float(count) * pay)
	offer["x"] = roundi(per_xp * float(count) * pay)
	offer["w"] = String(occ.get("why", ""))
	offer["oc"] = String(occ.id)
	if String(occ.get("window", "")) != "":
		offer["win"] = String(occ.window)
		offer["e"] = day + 1
	offer["txt"] = text_of(offer, String(occ.get("text", template.get("text", "")))).replace("{side}", side)
	if make_urgent and bool(occ.get("urgent", false)):
		urgentize(offer, template)
	return offer


## Where a plant grows, for the map: {name, area [x, y, radius] in tiles}, or {}.
static func hint_of(item: String) -> Dictionary:
	return (config().get("hints", {}) as Dictionary).get(item, {}) as Dictionary


## How far along its life a notice is, 0 (just hung at sunrise) .. 1 (the sunrise it runs out). `tod` is the time of day (0..1); before sunrise the day counter has not moved on yet.
## Story notices never age (0).
static func age(offer: Dictionary, day: int, tod: float) -> float:
	if int(offer.e) < 0:
		return 0.0
	var now: float = float(day) + tod + (1.0 if tod < TimeManager.DAY_START else 0.0)
	var start: float = float(int(offer.d)) + TimeManager.DAY_START
	return clampf((now - start) / maxf(float(int(offer.e) - int(offer.d)), 1.0), 0.0, 1.0)


## The look of a notice by age: 0 fresh, 1 hanging, 2 old (yellow, dog-eared), 3 last day.
static func age_stage(f: float) -> int:
	var stages: Array = (config().get("age", {}) as Dictionary).get("stages", [0.35, 0.7, 0.9]) as Array
	var stage: int = 0
	for i: int in stages.size():
		if f >= float(stages[i]):
			stage = i + 1
	return stage


## The goal as one line: "12 TANNENHOLZ" / "3 SCHATTENSPINNEN"; story notices have none.
static func goal_text(offer: Dictionary) -> String:
	match String(offer.k):
		FETCH:
			return "%d %s" % [int(offer.n), item_name(String(offer.t))]
		KILL:
			if is_bounty(offer):
				return "%s" % String(offer.bn)
			return "%d %s" % [int(offer.n), species_name(String(offer.t))]
	return ""


## The state of the taker's entry: {n: progress, done}. `have` is what the bag holds for a fetch notice.
static func progress(offer: Dictionary, entry: Dictionary, have: int) -> int:
	if bool(entry.get("done", false)):
		return int(offer.n)
	match String(offer.k):
		FETCH:
			return mini(have, int(offer.n))
		KILL:
			return mini(int(entry.get("n", 0)), int(offer.n))
	return 0


static func can_finish(offer: Dictionary, entry: Dictionary, have: int) -> bool:
	return String(offer.k) != STORY and not entry.is_empty() and not bool(entry.get("done", false)) and progress(offer, entry, have) >= int(offer.n)


## Is the entry of `story` due (its quest exists, the condition holds)? `finished` asks whether a quest id is finished, `flag` whether a player flag is set,
## `level` is the player's level (an entry's `min_level`: the lake witch's notice hangs from level 10).
static func story_due(entry: Dictionary, quests: Dictionary, finished: Callable, flag: Callable, level: int = 999) -> bool:
	if not quests.has(String(entry.quest)):
		return false
	if level < int(entry.get("min_level", 0)):
		return false
	var after: Variant = entry.get("after", "")
	if after is Array:
		for req: Variant in after as Array:
			var qid: String = String(req)
			if qid != "" and not bool(finished.call(qid)):
				return false
	elif String(after) != "" and not bool(finished.call(String(after))):
		return false
	var needed: String = String(entry.get("flag", ""))
	return needed == "" or bool(flag.call(needed))


# ---------- the honour board: counters, titles, the board that grows ----------

static func honor_cfg() -> Dictionary:
	return config().get("honor", {}) as Dictionary


static func titles() -> Array:
	return honor_cfg().get("titles", []) as Array


static func title_of(id: String) -> Dictionary:
	for raw: Variant in titles():
		if String((raw as Dictionary).id) == id:
			return raw as Dictionary
	return {}


## An empty set of counters (the town's, or one player's).
static func blank_stats() -> Dictionary:
	return {"done": 0, "fetch": 0, "kills": 0, "rush": 0, "bounty": 0, "givers": {}}


## Counts one finished notice into `stats` (a town's or a player's counters).
static func count_done(stats: Dictionary, offer: Dictionary) -> void:
	stats["done"] = int(stats.get("done", 0)) + 1
	if is_bounty(offer):
		stats["bounty"] = int(stats.get("bounty", 0)) + 1
	elif String(offer.k) == KILL:
		stats["kills"] = int(stats.get("kills", 0)) + int(offer.n)
	elif String(offer.k) == FETCH:
		stats["fetch"] = int(stats.get("fetch", 0)) + 1
	if is_urgent(offer):
		stats["rush"] = int(stats.get("rush", 0)) + 1
	var givers: Dictionary = stats.get("givers", {}) as Dictionary
	givers[String(offer.g)] = int(givers.get(String(offer.g), 0)) + 1
	stats["givers"] = givers


## What a counter reads for the key a title asks for ("givers" = how many different residents have been helped).
static func stat_value(stats: Dictionary, key: String) -> int:
	if key == "givers":
		return (stats.get("givers", {}) as Dictionary).size()
	return int(stats.get(key, 0))


## {have, need} of a title's first (only) requirement.
static func title_progress(stats: Dictionary, title: Dictionary) -> Vector2i:
	var need: Dictionary = title.get("need", {}) as Dictionary
	for key: String in need:
		return Vector2i(stat_value(stats, key), int(need[key]))
	return Vector2i(0, 1)


static func title_earned(stats: Dictionary, title: Dictionary) -> bool:
	var progress_pair: Vector2i = title_progress(stats, title)
	return progress_pair.x >= progress_pair.y


## How many of the town's milestones (25 / 50 / 100 finished notices) are reached: the board grows by one place per milestone.
static func milestones_reached(done: int) -> int:
	var count: int = 0
	for step: Variant in honor_cfg().get("milestones", []) as Array:
		count += 1 if done >= int(step) else 0
	return count
