class_name BoardRules
extends RefCounted
## The pure rules of the quest board (docs/questtafel_konzept.md): which notices may hang, how one is rolled, what it says and pays, when it runs out.
## No nodes, so the host (`BoardManager`), the window and the tests all ask the same functions. Data: data/board.json.
## A notice is a plain Dictionary: {id, k "fetch" | "kill" | "story", g giver, tx template id, t item or species, n count, c copper, x xp, tr trust,
## b bonus {id, n} or {}, d day posted, e day it runs out (-1 = never), txt text, ti title (story), q quest id (story)}.

const FETCH: String = "fetch"
const KILL: String = "kill"
const STORY: String = "story"


static func config() -> Dictionary:
	return DataRegistry.table("board")


static func piece() -> String:
	return String(config().get("piece", "quest_board"))


static func reach() -> float:
	return float(config().get("reach", 150.0))


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


static func is_expired(offer: Dictionary, day: int) -> bool:
	return int(offer.e) >= 0 and day >= int(offer.e)


static func days_left(offer: Dictionary, day: int) -> int:
	return -1 if int(offer.e) < 0 else maxi(0, int(offer.e) - day)


## The goal as one line: "12 TANNENHOLZ" / "3 SCHATTENSPINNEN"; story notices have none.
static func goal_text(offer: Dictionary) -> String:
	match String(offer.k):
		FETCH:
			return "%d %s" % [int(offer.n), item_name(String(offer.t))]
		KILL:
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


## Is the entry of `story` due (its quest exists, the condition holds)? `finished` asks whether a quest id is finished, `flag` whether a player flag is set.
static func story_due(entry: Dictionary, quests: Dictionary, finished: Callable, flag: Callable) -> bool:
	if not quests.has(String(entry.quest)):
		return false
	var after: String = String(entry.get("after", ""))
	if after != "" and not bool(finished.call(after)):
		return false
	var needed: String = String(entry.get("flag", ""))
	return needed == "" or bool(flag.call(needed))
