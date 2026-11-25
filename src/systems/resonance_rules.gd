class_name ResonanceRules
extends RefCounted
## Pure rules for Dungeon Veil Resonance (4 max charges, 2 daily refreshes at 06:00 & 18:00 UTC
## granting +2 each, Lost-Ark Rest Bonus overflow, and weekly Echo Shard cap + exchange).
## Deterministic and 100% headless testable (docs/dungeon_konzept.md Section 4).

const DEFAULT_MAX_CHARGES: int = 4
const DEFAULT_PER_REFRESH: int = 2
const DEFAULT_REFRESH_OFFSET_UTC: int = 21600 ## 06:00 UTC
const DEFAULT_REFRESH_INTERVAL: int = 43200 ## 12 hours (06:00 & 18:00 UTC)
const DEFAULT_REST_MAX: int = 8 ## 8 half-units = 4 doubled rewards
const DEFAULT_REST_PER_DOUBLE: int = 2
const DEFAULT_MAX_CATCHUP_EPOCHS: int = 60
const DEFAULT_WEEKLY_ECHO_CAP: int = 120
const DEFAULT_WEEKLY_OFFSET_UTC: int = 367200 ## Monday 06:00 UTC (1970-01-01 was Thursday -> +4d 6h)
const DEFAULT_WEEKLY_INTERVAL: int = 604800 ## 7 days


static func config() -> Dictionary:
	return DataRegistry.table("dungeon_resonance")


static func max_charges() -> int:
	return int(config().get("max_charges", DEFAULT_MAX_CHARGES))


static func charges_per_refresh() -> int:
	return int(config().get("charges_per_refresh", DEFAULT_PER_REFRESH))


static func refresh_offset_utc() -> int:
	return int(config().get("refresh_offset_sec_utc", DEFAULT_REFRESH_OFFSET_UTC))


static func refresh_interval_sec() -> int:
	return maxi(int(config().get("refresh_interval_sec", DEFAULT_REFRESH_INTERVAL)), 60)


static func rest_max_units() -> int:
	return int(config().get("rest_max_units", DEFAULT_REST_MAX))


static func rest_units_per_double() -> int:
	return maxi(int(config().get("rest_units_per_double", DEFAULT_REST_PER_DOUBLE)), 1)


static func weekly_echo_cap() -> int:
	return int(config().get("weekly_echo_cap", DEFAULT_WEEKLY_ECHO_CAP))


static func group_sparks() -> int:
	return maxi(int(config().get("group_sparks", 3)), 1)


## Returns the 12-hour UTC epoch index aligned to 06:00 UTC and 18:00 UTC.
static func epoch_for(unix_sec: int) -> int:
	var offset: int = refresh_offset_utc()
	var step: int = refresh_interval_sec()
	return int(floor(float(unix_sec - offset) / float(step)))


## Seconds remaining until the next 06:00 or 18:00 UTC refresh.
static func seconds_until_next_refresh(unix_sec: int) -> int:
	var offset: int = refresh_offset_utc()
	var step: int = refresh_interval_sec()
	var next_epoch: int = epoch_for(unix_sec) + 1
	var next_unix: int = offset + next_epoch * step
	return maxi(next_unix - unix_sec, 0)


## Weekly reset bucket aligned to Monday 06:00 UTC.
static func week_id_for(unix_sec: int) -> int:
	var offset: int = int(config().get("weekly_reset_offset_sec_utc", DEFAULT_WEEKLY_OFFSET_UTC))
	var step: int = maxi(int(config().get("weekly_interval_sec", DEFAULT_WEEKLY_INTERVAL)), 3600)
	return int(floor(float(unix_sec - offset) / float(step)))


static func fresh_state(now_unix: int) -> Dictionary:
	return {
		"charges": max_charges(),
		"rest_units": 0,
		"last_epoch": epoch_for(now_unix),
		"last_seen_unix": now_unix,
		"echo_shards": 0,
		"echo_week_id": week_id_for(now_unix),
		"echo_week_earned": 0,
		"exchange_bought": {},
	}


## Purely advances resonance charges, rest bonus overflow, and weekly Echo reset to `now_unix`.
## Protects against backwards system clock adjustments via monotonic `last_seen_unix`.
static func sync_state(raw: Dictionary, now_unix: int) -> Dictionary:
	if raw.is_empty():
		return fresh_state(now_unix)
	var cap: int = max_charges()
	var per_ref: int = charges_per_refresh()
	var rest_cap: int = rest_max_units()
	var max_epochs: int = int(config().get("max_catchup_epochs", DEFAULT_MAX_CATCHUP_EPOCHS))

	var last_seen: int = int(raw.get("last_seen_unix", 0))
	var eff_now: int = maxi(now_unix, last_seen)
	var charges: int = clampi(int(raw.get("charges", cap)), 0, cap)
	var rest_units: int = clampi(int(raw.get("rest_units", 0)), 0, rest_cap)
	var last_epoch: int = int(raw.get("last_epoch", epoch_for(eff_now)))
	var cur_epoch: int = epoch_for(eff_now)

	if cur_epoch > last_epoch:
		var elapsed: int = mini(cur_epoch - last_epoch, max_epochs)
		for _i: int in elapsed:
			var sum_charges: int = charges + per_ref
			var overflow: int = maxi(sum_charges - cap, 0)
			charges = mini(sum_charges, cap)
			if overflow > 0:
				rest_units = mini(rest_units + overflow, rest_cap)
		last_epoch = cur_epoch

	var cur_week: int = week_id_for(eff_now)
	var stored_week: int = int(raw.get("echo_week_id", cur_week))
	var week_earned: int = maxi(int(raw.get("echo_week_earned", 0)), 0)
	var bought_raw: Variant = raw.get("exchange_bought", {})
	var bought: Dictionary = (bought_raw as Dictionary).duplicate(true) if bought_raw is Dictionary else {}
	if cur_week > stored_week:
		stored_week = cur_week
		week_earned = 0
		bought.clear()

	return {
		"charges": charges,
		"rest_units": rest_units,
		"last_epoch": last_epoch,
		"last_seen_unix": eff_now,
		"echo_shards": maxi(int(raw.get("echo_shards", 0)), 0),
		"echo_week_id": stored_week,
		"echo_week_earned": week_earned,
		"exchange_bought": bought,
	}


## Consumes 1 Resonance charge on victory (never on entry/wipe) if requested and available.
## Automatically spends 1 full Rest Bonus step (`rest_units_per_double` units) to double the reliquary.
static func consume_for_victory(raw: Dictionary, now_unix: int, use_resonance: bool) -> Dictionary:
	var st: Dictionary = sync_state(raw, now_unix)
	var consumed_res: bool = false
	var consumed_double: bool = false
	var charges: int = int(st.get("charges", 0))
	var rest_units: int = int(st.get("rest_units", 0))
	var per_double: int = rest_units_per_double()

	if use_resonance and charges >= 1:
		charges -= 1
		consumed_res = true
		if rest_units >= per_double:
			rest_units -= per_double
			consumed_double = true

	st["charges"] = charges
	st["rest_units"] = rest_units
	return {
		"state": st,
		"consumed_resonance": consumed_res,
		"consumed_rest_double": consumed_double,
	}


## Grants Echo Shards respecting the weekly soft cap (120/week).
static func grant_echo_shards(raw: Dictionary, now_unix: int, amount: int) -> Dictionary:
	var st: Dictionary = sync_state(raw, now_unix)
	var cap: int = weekly_echo_cap()
	var earned: int = int(st.get("echo_week_earned", 0))
	var room: int = maxi(cap - earned, 0)
	var granted: int = clampi(amount, 0, room)
	st["echo_shards"] = int(st.get("echo_shards", 0)) + granted
	st["echo_week_earned"] = earned + granted
	return {
		"state": st,
		"granted": granted,
		"capped": granted < maxi(amount, 0),
	}


## Validates and applies an Echo Exchange purchase from the Steinsetzer-Prüfungstafel.
static func purchase_exchange(raw: Dictionary, now_unix: int, offer: Dictionary, cleared_dungeons: Dictionary) -> Dictionary:
	var st: Dictionary = sync_state(raw, now_unix)
	var offer_id: String = String(offer.get("id", ""))
	if offer_id.is_empty():
		return {"ok": false, "reason": "UNGÜLTIGES ANGEBOT", "state": st}
	var req_clear: String = String(offer.get("requires_clear", ""))
	if not req_clear.is_empty() and int(cleared_dungeons.get(req_clear, 0)) <= 0:
		return {"ok": false, "reason": "ERST NACH ERSTLÄUTERUNG VERFÜGBAR", "state": st}
	var limit: int = int(offer.get("weekly_limit", 0))
	var bought: Dictionary = st.get("exchange_bought", {}) as Dictionary
	var done: int = int(bought.get(offer_id, 0))
	if limit > 0 and done >= limit:
		return {"ok": false, "reason": "WOCHENLIMIT ERREICHT", "state": st}
	var cost: int = maxi(int(offer.get("cost", 0)), 0)
	var shards: int = int(st.get("echo_shards", 0))
	if shards < cost:
		return {"ok": false, "reason": "ZU WENIG ECHOSPLITTER", "state": st}

	st["echo_shards"] = shards - cost
	bought[offer_id] = done + 1
	st["exchange_bought"] = bought
	return {
		"ok": true,
		"reason": "",
		"state": st,
		"item_id": String(offer.get("item_id", "")),
		"count": maxi(int(offer.get("count", 1)), 1),
	}


static func rest_doubles_ready(raw: Dictionary) -> int:
	return int(floor(float(int(raw.get("rest_units", 0))) / float(rest_units_per_double())))


static func format_countdown(sec: int) -> String:
	var clamped: int = maxi(sec, 0)
	var hrs: int = clamped / 3600
	var mins: int = (clamped % 3600) / 60
	return "%02d:%02d STD." % [hrs, mins]
