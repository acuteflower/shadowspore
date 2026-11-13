"""Root weave (Wurzelgeflecht, docs/raetsel_konzept.md 6a): the rules, a solver and a checker for every `root_weave` in data/puzzles.json.

Rules (the same as src/systems/weave_rules.gd, keep both in step):
- cubes: kind "cube" | "seed" (grows `from` children the first time it is lit) | "thorn" (cannot be touched) | "heart" | "crown" (never toggled).
- pressing a touchable present cube toggles it and every present non-heart/non-crown cube a root leads to from it (one-way roots only a -> b).
- after a press every lit present seed whose children are not there yet lets them rise (in their own start state), repeated until nothing grows.
- goal "all": every cube (heart/crown aside) is present and lit. goal "path": a chain of lit cubes along roots links the heart to the crown.

Run: python3 tools/check_root_weave.py            (checks every weave, prints shortest solution and how many there are)
     python3 tools/check_root_weave.py --search ID (tries start states for weave ID and prints the hardest found)
"""
import json, random, sys
from collections import deque
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data" / "puzzles.json"
MIN_MOVES = {"common": 3, "rare": 6, "legendary": 11}


def prepare(w):
    cubes = w["cubes"]
    ids = sorted(cubes)
    idx = {c: i for i, c in enumerate(ids)}
    out = [[] for _ in ids]
    adj = [[] for _ in ids]
    for r in w["roots"]:
        a, b = idx[r[0]], idx[r[1]]
        one = len(r) > 2 and bool(r[2])
        adj[a].append(b); adj[b].append(a)
        out[a].append(b)
        if not one:
            out[b].append(a)
    kind = [cubes[c].get("kind", "cube") for c in ids]
    born = [cubes[c].get("from", "") for c in ids]
    children = {i: [idx[c] for c in ids if born[idx[c]] == ids[i]] for i in range(len(ids))}
    return ids, idx, out, adj, kind, born, children


def start_state(w, prep):
    ids, idx, out, adj, kind, born, children = prep
    lit = 0
    pres = 0
    for c, d in w["cubes"].items():
        i = idx[c]
        if d.get("from", "") == "":
            pres |= 1 << i
            if d.get("lit", False):
                lit |= 1 << i
    return grow(lit, pres, w, prep)


def grow(lit, pres, w, prep):
    ids, idx, out, adj, kind, born, children = prep
    changed = True
    while changed:
        changed = False
        for i, k in enumerate(kind):
            if k == "seed" and pres >> i & 1 and lit >> i & 1 and children[i] and not pres >> children[i][0] & 1:
                for c in children[i]:
                    pres |= 1 << c
                    if w["cubes"][ids[c]].get("lit", False):
                        lit |= 1 << c
                changed = True
    return lit, pres


def press(lit, pres, i, w, prep):
    ids, idx, out, adj, kind, born, children = prep
    lit ^= 1 << i
    for j in out[i]:
        if pres >> j & 1 and kind[j] not in ("heart", "crown"):
            lit ^= 1 << j
    return grow(lit, pres, w, prep)


def touchable(i, prep):
    return prep[4][i] in ("cube", "seed")


def solved(lit, pres, w, prep):
    ids, idx, out, adj, kind, born, children = prep
    if w.get("goal", "all") == "all":
        for i, k in enumerate(kind):
            if k in ("heart", "crown"):
                continue
            if not (pres >> i & 1 and lit >> i & 1):
                return False
        return True
    heart = kind.index("heart"); crown = kind.index("crown")
    seen = {heart}; q = [heart]
    while q:
        a = q.pop()
        for b in adj[a]:
            if b == crown:
                return True
            if b not in seen and pres >> b & 1 and lit >> b & 1 and kind[b] not in ("heart", "crown"):
                seen.add(b); q.append(b)
    return False


def solve(w, prep=None):
    """Shortest number of touches, one shortest solution and how many shortest solutions (as move sets) exist."""
    prep = prep or prepare(w)
    start = start_state(w, prep)
    if solved(*start, w, prep):
        return 0, [], 1
    dist = {start: 0}
    ways = {start: 1}
    prev = {start: None}
    q = deque([start])
    best = None
    while q:
        s = q.popleft()
        d = dist[s]
        if best is not None and d >= best:
            break
        for i in range(len(prep[0])):
            if not (s[1] >> i & 1) or not touchable(i, prep):
                continue
            n = press(s[0], s[1], i, w, prep)
            if n not in dist:
                dist[n] = d + 1; ways[n] = ways[s]; prev[n] = (s, prep[0][i]); q.append(n)
                if solved(*n, w, prep) and best is None:
                    best = d + 1
            elif dist[n] == d + 1:
                ways[n] += ways[s]
    if best is None:
        return None, None, 0
    goals = [s for s, d in dist.items() if d == best and solved(*s, w, prep)]
    s = goals[0]; path = []
    while prev[s]:
        s, p = prev[s]; path.append(p)
    import math
    count = sum(ways[g] for g in goals) // math.factorial(best)  # orderings of one set count once (roughly: growth can make order matter)
    return best, path[::-1], max(1, count)


def weaves():
    table = json.loads(DATA.read_text(encoding="utf-8"))
    out = [e for e in table.get("placed", []) + table.get("trial_world", []) if e.get("kind") == "root_weave"]
    seen = set(); res = []
    for e in out:
        if e["id"] not in seen:
            seen.add(e["id"]); res.append(e)
    return res


def search(w, tries):
    prep = prepare(w)
    best = (-1, None)
    rng = random.Random(7)
    keys = sorted(w["cubes"])
    for t in range(tries):
        for c in keys:
            if w["cubes"][c].get("kind", "cube") not in ("heart", "crown"):
                w["cubes"][c]["lit"] = rng.random() < 0.5
        n, path, count = solve(w, prep)
        if n is None:
            continue
        score = n * 10 - count
        if score > best[0]:
            best = (score, {c: w["cubes"][c].get("lit", False) for c in keys}, n, path, count)
            print(n, count, path, flush=True)
    return best


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--search":
        w = next(e for e in weaves() if e["id"] == sys.argv[2])
        b = search(w, int(sys.argv[3]) if len(sys.argv) > 3 else 400)
        print(json.dumps(b[1]))
        return
    ok = True
    for w in weaves():
        n, path, count = solve(w)
        need = MIN_MOVES.get(w.get("tier", "common"), 1)
        good = n is not None and n >= need
        ok &= good
        print("%-24s %-9s goal=%-4s cubes=%2d shortest=%s solutions~%d %s %s" % (w["id"], w.get("tier"), w.get("goal", "all"), len(w["cubes"]), n, count, path, "OK" if good else "TOO EASY / UNSOLVABLE"))
    print("ROOT WEAVE DATA OK" if ok else "ROOT WEAVE DATA FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
