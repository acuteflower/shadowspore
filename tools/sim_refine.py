#!/usr/bin/env python3
"""Balance sheet of the refinement system (docs/refinement_konzept.md): reads data/refine.json and rolls weapons of every rarity from +0 to their cap
(mirror of src/systems/refine_rules.gd; tools/test_refine.tscn checks that both agree), then sets the material against what the world really drops:
the loot tables of data/enemies.json and the mix of night.json give the expected splinters, cores and slag per kill, so every row says how many NIGHTS of hunting
(KILLS_PER_NIGHT kills for one player) its scarcest material needs.
Usage: python3 tools/sim_refine.py [runs]"""
import json, math, random, sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"
CFG = json.loads((DATA / "refine.json").read_text(encoding="utf-8"))
ENEMIES = json.loads((DATA / "enemies.json").read_text(encoding="utf-8"))
NIGHT = json.loads((DATA / "night.json").read_text(encoding="utf-8"))
RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
SECONDS_PER_DAY = 295.0  # Torben's work seconds in one game day (schedule 0.29-0.54 and 0.62-0.78 of a 720 s day)
KILLS_PER_NIGHT = 16.0   # one player, a night of the middle game (budget 6 x level and day factors, half of it refunded on kills)
ORE_PER_ROCK = 4.3       # iron ore from one iron rock: 3-5 hits at 70 % plus the last hit's 1-2 (data/plants.json); an ingot is 2 ore, a plate 3 ore (3 ingots make 2 plates)


def rnd(x): return int(math.floor(x + 0.5))  # like GDScript roundi


def tier(target): return CFG["tiers"][min((target - 1) // 5, len(CFG["tiers"]) - 1)]


def chance(rarity, target, pity):
    base = CFG["base_chance"][target - 1]
    if base >= 1.0: return 1.0
    t = tier(target)
    bonus = min(pity * t["pity"], t["pity_cap"])
    return max(0.0, min(base * CFG["rarity"][rarity]["chance"] + bonus, CFG["chance_cap"]))


def materials(rarity, target):
    t = tier(target); k = (target - 1) % 5
    main, side = CFG["ladder"][rarity][(target - 1) // 5]
    scale = CFG["item_amount"]
    out = {main: max(rnd(t["primary"][k] * CFG["rarity"][rarity]["amount"] * scale.get(main, 1.0)), 1)}
    n = rnd(t["secondary"][k] * scale.get(side, 1.0)) if side else 0
    if n > 0: out[side] = n
    return out


def copper(rarity, target):
    return max(rnd(CFG["copper"]["base"] * target ** CFG["copper"]["exp"] * CFG["rarity"][rarity]["cost"]), 1)


def work(rarity, target): return rnd(CFG["work"][target - 1] * CFG["rarity"][rarity]["work"])


def supply():
    """Expected drops and copper per kill of a late-game night: species mixed by their weight."""
    species = NIGHT["species"]
    total = sum(s["weight"] for s in species)
    per = {"copper": 0.0}
    for s in species:
        share = s["weight"] / total
        loot = ENEMIES[s["id"]]["loot"]
        per["copper"] += share * (loot["copper"]["min"] + loot["copper"]["max"]) / 2.0
        for it in loot.get("items", []):
            per[it["id"]] = per.get(it["id"], 0.0) + share * it["chance"] * (it.get("min", 1) + it.get("max", 1)) / 2.0
    return per


def run(rarity, cap):
    level, pity, attempts, secs, cop, mats = 0, 0, 0, 0, 0, {}
    while level < cap:
        target = level + 1
        attempts += 1; secs += work(rarity, target); cop += copper(rarity, target)
        for k, v in materials(rarity, target).items(): mats[k] = mats.get(k, 0) + v
        if random.random() < chance(rarity, target, pity): level, pity = target, 0
        else: pity += 1
    return attempts, secs, cop, mats


ORDER = ["iron_ingot", "iron_plate", "void_splinter", "shadow_core", "void_slag"]
per_kill = supply()
print("per kill: " + ", ".join("%s %.3f" % (k, v) for k, v in per_kill.items()) + " | %d kills a night" % KILLS_PER_NIGHT)
for rarity in CFG["rarity"]:
    res = [run(rarity, min(CFG["max"], CFG["rarity"][rarity]["cap"])) for _ in range(RUNS)]
    n = len(res)
    att = sorted(r[0] for r in res)
    mats = {}
    for r in res:
        for k, v in r[3].items(): mats[k] = mats.get(k, 0) + v / n
    copper_total = sum(r[2] for r in res) / n
    nights = {k: v / per_kill[k] / KILLS_PER_NIGHT for k, v in mats.items() if k in per_kill}
    nights["copper"] = copper_total / per_kill["copper"] / KILLS_PER_NIGHT
    ore = mats.get("iron_ingot", 0.0) * 2.0 + mats.get("iron_plate", 0.0) * 3.0
    worst = max(nights, key=nights.get)
    print("%-9s attempts %4.1f (median %d, p90 %d) | Torben %5.1f min = %4.1f days | copper %5d | %s | iron %3.0f ore = %2.0f rocks | hunting: %.0f nights (%s)" % (
        rarity, sum(att) / n, att[n // 2], att[int(n * 0.9)], sum(r[1] for r in res) / n / 60.0, sum(r[1] for r in res) / n / SECONDS_PER_DAY, copper_total,
        ", ".join("%s %.0f" % (k, v) for k, v in sorted(mats.items(), key=lambda kv: ORDER.index(kv[0]))), ore, ore / ORE_PER_ROCK, nights[worst], worst))
