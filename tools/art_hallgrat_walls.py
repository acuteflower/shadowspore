#!/usr/bin/env python3
"""Hallgrat's low walls (docs/stadt_westen_konzept.md 14.7): every run of data/hallgrat.json `wall_runs` (laid by
tools/place_hallgrat_deco.py along the paving's edge) is built stone by stone along its own curve, so no two pieces of wall look alike and
they follow the ways round every bend.

Styles: `stadt` (the town wall on the terraces' brink: tall coursed ashlar with merlons, slits, buttresses and round towers; collision
`thick` 9 px plus a circle per tower), `garten` (coursed, a row of capstones, flowers peeping over), `feld` (rough field stones of every size, the top wandering, moss),
`ruine` (fallen to knee height and lower, gaps, stones lying beside it, overgrown). A run that ends at a door path ends in a gate post
(squared blocks, a cap, now and then a stone ball or a planter on it); the other ends taper or break off.

A run is cut into pieces of about 40 px (each its own picture, so every piece sorts with the world by its own front); the stones are laid
for the whole run first and every piece draws the stones whose middle lies on it, so the pieces meet without a seam.

Writes assets/town/hallgrat/walls/wand_<run>_<k>.png, the types `wand_<run>_<k>` (size, feet, foot, poly = the collision along the wall,
`exact`) and the list `wall_pieces` [{type, px}] into data/hallgrat_art.json.
    py -3 tools/art_hallgrat_walls.py [preview.png]      then      Godot --headless --path . --import"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hallgrat_houses as hh  # noqa: E402  (sets the town's stone ramps)
import art_hero3d as h  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import CLAY, MOSS, MOSS_L, SOIL, STONE, STONE_L, V, rng_for, save, to_array  # noqa: E402
from gen_art import hexc  # noqa: E402

S = h.SCALE
G = 1.6
K = S * G                      # px per model unit
OUT = hh.OUT / "walls"
FIELD = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("201d36", "332f52", "4b4670", "6c6690")])     # field stones: the street stone, a shade duller
FIELD_L = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("29264a", "403b62", "5c5781", "8781aa")])
DARK = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("0c0a14", "120f1c", "181424", "1e192c")])     # arrow slits, the dark in a tower's window
ROOF_T = len(h.RAMPS)
h.RAMPS.append(list(hh.SLATE[0]))                                                  # the towers' slate hoods
BLOOMS = (hh.WINE, hh.OCHRE, hh.PLUM, hh.FRUIT)
TOP = 30.0                     # model units: the town wall's walkway (a house's eaves stand at about 30)
TOWER_R = 7.4
PIECE = 8                      # points (3 px apart) per piece: short, so each sorts with the world close to where it stands


def noise1(s, seed, scale):
    """Smooth 1-D value noise along the arc (0..1)."""
    f = s / scale
    i = int(math.floor(f))
    u = f - i
    u = u * u * (3 - 2 * u)
    a = hut_lib.hsh(i, 3, seed)
    b = hut_lib.hsh(i + 1, 3, seed)
    return a * (1 - u) + b * u


def to_model(dx, dy):
    return V(dx / K, 0.0, dy / (h.SINP * K))


def lay(run):
    """All stones and growth of a run: [(s, kind, args)] with `s` the arc position (px) of the thing's middle."""
    pts = [tuple(p) for p in run["pts"]]
    ns = [tuple(n) for n in run["n"]]
    style, seed = run["style"], run["seed"]
    rng = rng_for(seed)
    arc = [0.0]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        arc.append(arc[-1] + math.hypot(bx - ax, by - ay))
    total = arc[-1]

    def at(s):
        s = max(0.0, min(total, s))
        j = max(0, min(len(pts) - 2, int(np.searchsorted(arc, s)) - 1))
        t = (s - arc[j]) / max(arc[j + 1] - arc[j], 1e-6)
        x = pts[j][0] + (pts[j + 1][0] - pts[j][0]) * t
        y = pts[j][1] + (pts[j + 1][1] - pts[j][1]) * t
        tm = to_model(pts[j + 1][0] - pts[j][0], pts[j + 1][1] - pts[j][1])
        tm = tm / (np.linalg.norm(tm) or 1.0)
        yaw = math.atan2(-tm[2], tm[0])
        return x, y, yaw, ns[j]

    if style == "stadt":
        return lay_rampart(run, rng, total), at, total, arc
    things = []
    T = 2.4 if style == "garten" else 2.7
    posts = run.get("posts", [False, False])
    abut = run.get("abut", [False, False])
    s0 = 7.0 if posts[0] else 0.0
    s1 = total - (7.0 if posts[1] else 0.0)

    def height(s):
        if style == "garten":
            hgt = 8.6 + 1.0 * noise1(s, seed, 40)
        elif style == "feld":
            hgt = 6.4 + 3.4 * noise1(s, seed, 26)
        else:
            hgt = 0.8 + 6.8 * noise1(s, seed, 18) ** 1.6
        for side, (end, has_post) in enumerate(((s - s0, posts[0]), (s1 - s, posts[1]))):  # free ends taper or break off; not at a house
            if not has_post and style != "garten" and end < 18 and not abut[side]:
                hgt *= 0.45 + 0.55 * end / 18
        return hgt

    s = s0
    while s < s1 - 1.0:
        w = rng.uniform(5.0, 8.0) if style == "garten" else rng.uniform(3.5, 9.0)
        w = min(w, s1 - s)
        mid = s + w / 2
        top = height(mid)
        y = 0.0
        row = 0
        if top < 1.6:
            things.append((mid, "rubble", (rng.uniform(1.2, 2.2), rng.random())))
            s += w
            continue
        while y < top - 0.8:
            hgt = rng.uniform(2.2, 3.0) if style == "garten" else rng.uniform(1.8, 3.6)
            hgt = min(hgt, top - y + 0.6)
            off = (rng.uniform(-1.2, 1.2) if row % 2 else 0.0) if style == "garten" else rng.uniform(-1.6, 1.6)
            mat = (STONE, STONE, STONE_L)[int(rng.random() * 3)] if style == "garten" else (FIELD, FIELD, FIELD_L, STONE)[int(rng.random() * 4)]
            things.append((mid + off, "stone", (w * 0.52 * rng.uniform(0.92, 1.05), hgt * 0.52, T * rng.uniform(0.9, 1.08), y + hgt / 2, mat,
                                                rng.uniform(-0.12, 0.12))))
            y += hgt * 0.9
            row += 1
        if style == "garten":
            things.append((mid, "cap", (w * 0.54, top + 0.6)))
        if style != "garten" and rng.random() < 0.35:
            things.append((mid, "moss_top", (rng.uniform(1.6, 3.2), top)))
        if rng.random() < (0.5 if style == "ruine" else 0.3):
            things.append((mid + rng.uniform(-2, 2), "tuft_out", (rng.random(),)))
        if rng.random() < 0.18:
            things.append((mid, "tuft_in", (rng.random(),)))
        if style == "garten" and rng.random() < 0.12:
            things.append((mid, "flowers", (top + 1.2,)))
        if style != "ruine" and rng.random() < 0.06:
            things.append((mid, "ivy", (top,)))
        if style == "ruine" and rng.random() < 0.3:
            things.append((mid + rng.uniform(-3, 3), "fallen", (rng.uniform(1.4, 2.6), rng.random())))
        s += w
    for k, has in enumerate(posts):
        if has:
            things.append((3.0 if k == 0 else total - 3.0, "post", (rng.random(), style)))
    return things, at, total, arc


def lay_rampart(run, rng, total):
    """The town wall: coursed ashlar on a jutting foot course, a walkway cap and merlons, arrow slits, buttresses on the outside now and
    then, ivy and moss; round towers at `towers` (arc px)."""
    seed = run["seed"]
    towers = run.get("towers", [])
    tower_px = TOWER_R * K

    def free(s, pad=0.0):
        return all(abs(s - t) > tower_px + pad for t in towers)

    def top_at(s):
        return TOP + 1.4 * noise1(s, seed, 70)
    things = []
    s = 0.0
    while s < total - 0.5:
        w = min(rng.uniform(5.5, 9.0), total - s)
        mid = s + w / 2
        if free(mid, -3.0):
            top = top_at(mid)
            y, row = 0.0, 0
            while y < top - 0.8:
                hgt = 3.8 if row == 0 else rng.uniform(2.6, 3.3)
                hgt = min(hgt, top - y + 0.4)
                off = (rng.uniform(-1.4, 1.4) if row % 2 else 0.0)
                mat = (STONE, STONE, STONE_L, STONE, FIELD)[int(rng.random() * 5)]
                thick = 3.5 if row == 0 else (3.0 if row == 1 else 2.6)   # a batter: the foot courses jut out
                things.append((mid + off, "stone", (w * 0.52 * rng.uniform(0.94, 1.04), hgt * 0.52, thick * rng.uniform(0.96, 1.04),
                                                    y + hgt / 2, mat, rng.uniform(-0.05, 0.05))))
                y += hgt * 0.93
                row += 1
            things.append((mid, "walk", (w * 0.55, top + 0.4)))
            if rng.random() < 0.08:
                things.append((mid, "ivy", (top - 1.0,)))
            if rng.random() < 0.22:
                things.append((mid + rng.uniform(-2, 2), "tuft_out", (rng.random(),)))
            if rng.random() < 0.15:
                things.append((mid, "tuft_in", (rng.random(),)))
        s += w
    s = 3.0
    while s < total - 3.0:  # merlons
        if free(s, 2.0):
            things.append((s, "merlon", (top_at(s) + 0.9,)))
            if rng.random() < 0.12:
                things.append((s, "moss_top", (rng.uniform(1.2, 2.0), top_at(s) + 4.6)))
        s += 8.5
    s = rng.uniform(10, 24)
    while s < total - 8:  # arrow slits
        if free(s, 6.0):
            things.append((s, "slit", (top_at(s) - 9.5,)))
        s += rng.uniform(26, 40)
    s = rng.uniform(30, 50)
    while s < total - 20:  # buttresses on the outside
        if free(s, 14.0):
            things.append((s, "buttress", (top_at(s), rng.random())))
        s += rng.uniform(55, 80)
    for t in towers:
        things.append((t, "tower", (rng.random(), top_at(t))))
    return things


def build_tower(m, base, q, top, rng):
    """A round tower: rings of ashlar, a corbelled crown, then merlons or a slate hood with a pennant."""
    r0 = TOWER_R
    height = top + 11.0
    m.ell(base + V(0, height / 2, 0), (r0 - 1.0, height / 2, r0 - 1.0), STONE)      # the core, so no gap shows between the stones
    y, k = 0.0, 0
    while y < height - 0.6:
        hgt = 3.8 if k == 0 else rng.uniform(2.7, 3.2)
        rr = r0 + (0.6 if k == 0 else 0.0)
        n = 11
        for i in range(n):
            a = 2 * math.pi * (i + (0.5 if k % 2 else 0.0)) / n
            mat = (STONE, STONE, STONE_L, FIELD)[int(rng.random() * 4)]
            m.ell(base + V(math.cos(a) * rr, y + hgt / 2, math.sin(a) * rr), (2.25, hgt * 0.53, 1.5), mat, R=h.rot_y(-a - math.pi / 2))
        y += hgt * 0.94
        k += 1
    for i in range(14):  # the corbel ring
        a = 2 * math.pi * i / 14
        m.ell(base + V(math.cos(a) * (r0 + 0.9), height + 0.6, math.sin(a) * (r0 + 0.9)), (1.9, 1.1, 1.3), STONE_L, R=h.rot_y(-a - math.pi / 2))
    for yy in (top - 8.0, top - 19.0):  # slits
        if yy > 3:
            m.ell(base + V(0, yy, r0 + 0.3), (0.5, 1.9, 0.9), DARK)
    if q < 0.55:  # crenellated
        m.ell(base + V(0, height + 1.4, 0), (r0 + 0.4, 0.8, r0 + 0.4), STONE_L)
        for i in range(8):
            a = 2 * math.pi * (i + 0.5) / 8
            m.ell(base + V(math.cos(a) * (r0 + 0.3), height + 3.6, math.sin(a) * (r0 + 0.3)), (1.9, 2.3, 1.3), STONE_L, R=h.rot_y(-a - math.pi / 2))
        if q < 0.2:
            hut_lib.tuft(m, base + V(1.5, height + 2.2, 0.5), rng, blades=4, height=2.4)
    else:  # a slate hood with a pennant of the town
        for j in range(12):
            t = j / 12
            rr = (r0 + 1.9) * (1 - t) ** 1.15 + 0.3
            m.ell(base + V(0, height + 1.2 + j * 1.25, 0), (rr, 0.95, rr), ROOF_T)
        tip = base + V(0, height + 16.5, 0)
        m.limb(tip, tip + V(0, 6.0, 0), 0.32, 0.25, hh.IRON)
        for k2 in range(4):
            m.ell(tip + V(1.0 + k2 * 1.1, 5.2 - k2 * 0.25, 0), (0.75, 0.95 - k2 * 0.12, 0.25), hh.WINE)
    if q > 0.75:
        hut_lib.ivy(m, base + V(-r0 * 0.6, height - 2, r0 * 0.75), height * 0.6, rng, sway=0.3)


def build_piece(run, things, at, lo, hi, feet):
    """The model of the things whose middle lies in [lo, hi) of the run, relative to `feet` (px)."""
    m = h.Model()
    rng = rng_for(run["seed"] * 7 + int(max(0.0, lo)))
    for s, kind, a in things:
        if not (lo <= s < hi):
            continue
        x, y, yaw, (nx, ny) = at(s)
        base = to_model(x - feet[0], y - feet[1])
        R = h.rot_y(yaw)
        out_ = to_model(-nx, -ny)
        out_ = out_ / (np.linalg.norm(out_) or 1.0)       # the side away from the street (model units)
        if kind == "stone":
            rx, ry, rz, cy, mat, tilt = a
            m.ell(base + V(0, cy, 0), (rx, ry, rz), mat, R=R @ h.rot_x(tilt * 0.3))
        elif kind == "cap":
            w, top = a
            m.ell(base + V(0, top, 0), (w, 1.0, 3.1), STONE_L, R=R)
        elif kind == "moss_top":
            r_, top = a
            m.ell(base + V(0, top + 0.2, 0), (r_, 0.7, 2.2), MOSS, R=R)
        elif kind == "tuft_out":
            hut_lib.tuft(m, base + out_ * 3.4, rng, blades=5, height=2.8 + a[0] * 1.6)
        elif kind == "tuft_in":
            hut_lib.tuft(m, base - out_ * 3.2, rng, blades=4, height=2.2)
        elif kind == "flowers":
            top = a[0]
            for k in range(4):
                p = base + out_ * rng.uniform(-0.5, 1.5) + V(rng.uniform(-2, 2), top, 0)
                m.limb(p, p + V(0, 1.6, 0), 0.3, 0.2, MOSS_L)
                m.ell(p + V(0, 1.8, 0), (0.8, 0.7, 0.8), BLOOMS[int(rng.random() * 4)])
        elif kind == "ivy":
            hut_lib.ivy(m, base + out_ * 2.6 + V(0, a[0], 0), a[0] * 0.8, rng, sway=0.4)
        elif kind == "rubble":
            r_, q = a
            m.ell(base + V(0, r_ * 0.6, 0), (r_ * 1.3, r_ * 0.7, r_), (FIELD, FIELD_L)[int(q * 2)], R=R)
        elif kind == "fallen":
            r_, q = a
            m.ell(base + out_ * (4.5 + q * 3) + V(0, r_ * 0.6, 0), (r_ * 1.2, r_ * 0.7, r_), FIELD, R=h.rot_y(q * 3))
            if q < 0.5:
                hut_lib.tuft(m, base + out_ * (5.5 + q * 3), rng, blades=3, height=2.0)
        elif kind == "walk":
            w, top = a
            m.ell(base + V(0, top, 0), (w, 0.9, 2.9), STONE_L, R=R)
        elif kind == "merlon":
            top = a[0]
            m.ell(base + out_ * 1.2 + V(0, top + 2.2, 0), (2.4, 2.5, 1.5), STONE_L, R=R)
            m.ell(base + out_ * 1.2 + V(0, top + 4.7, 0), (2.6, 0.6, 1.7), STONE_L, R=R)
        elif kind == "slit":
            m.ell(base + V(0, a[0], 0), (0.5, 1.9, 3.2), DARK, R=R)
        elif kind == "buttress":
            top, q = a
            for k in range(5):
                hgt = top * (0.78 - k * 0.14)
                m.ell(base + out_ * (3.2 + 0.42 * (4 - k)) + V(0, hgt / 2 + k * 0.4, 0), (2.4, hgt / 2, 1.6 + 0.35 * (4 - k)),
                      (STONE, STONE_L)[k % 2], R=R)
            if q < 0.4:
                hut_lib.tuft(m, base + out_ * 5.5, rng, blades=4, height=2.6)
        elif kind == "tower":
            q, top = a
            build_tower(m, base, q, top, rng)
        elif kind == "post":
            q, style = a
            for k in range(5):
                mat = STONE_L if k % 2 else STONE
                if style != "garten":
                    mat = FIELD_L if k % 2 else FIELD
                m.ell(base + V(0, 1.6 + k * 2.7, 0), (3.6 - k * 0.1, 1.5, 3.4 - k * 0.1), mat, R=R)
            m.ell(base + V(0, 15.0, 0), (4.2, 1.1, 4.0), STONE_L, R=R)
            if q < 0.35:
                m.ell(base + V(0, 17.8, 0), (2.2, 2.2, 2.0), STONE_L)      # a stone ball
            elif q < 0.6:
                m.ell(base + V(0, 17.0, 0), (2.8, 1.6, 2.6), CLAY)          # a little planter
                m.ell(base + V(0, 18.4, 0), (2.4, 1.2, 2.2), MOSS_L)
                for k in range(3):
                    m.ell(base + V(rng.uniform(-1.5, 1.5), 19.4, rng.uniform(-1, 1)), (0.8, 0.7, 0.8), BLOOMS[int(rng.random() * 4)])
            hut_lib.tuft(m, base + out_ * 4.0, rng, blades=4, height=2.6)
    return m


def render_ids(m, fw, fh, ground):
    """The picture plus, per pixel, which stone it shows (-1 = no stone): the model is rasterised a second time with every stone's
    material set to its own number, so the joints can follow the real outline of every stone."""
    stones = {STONE, STONE_L, FIELD, FIELD_L}
    cap = {}
    orig = h.render

    def twice(prims, *a, **k):
        res = orig(prims, *a, **k)
        tagged = [h.Prim(p.c, p.r, p.R, 2000 + i if p.mat in stones else p.mat, p.kind, p.tag, p.clip, p.rot, p.layer)
                  for i, p in enumerate(prims)]
        cap["code"] = orig(tagged)[1]
        return res
    h.render = twice
    try:
        rows = hut_lib.render(m, fw, fh, ground)
    finally:
        h.render = orig
    ss = h.SS
    mid = cap["code"][ss // 2::ss, ss // 2::ss] // 4
    return to_array(rows), np.where(mid >= 2000, mid - 2000, -1)


def stone_pass(arr, ids, seed):
    """Gives the wall the houses' masonry (art_hallgrat_houses.wall_pass): every stone in the street stone's ramp MASON, each its own
    tone, a dark joint along its upper and left outline, a lit row under that and a darker one along its lower and right outline. The
    renderer's band stays the light, so the round of the stones and the shaded side keep their depth."""
    M = hh.MASON
    base = {}
    for i, c in enumerate(M):
        base[tuple(c[:3])] = float(i)
    for b, c in enumerate(h.RAMPS[FIELD]):
        base.setdefault(tuple(c[:3]), b + 0.55)
    for b, c in enumerate(h.RAMPS[FIELD_L]):
        base.setdefault(tuple(c[:3]), b + 1.1)
    H, W = arr.shape[:2]
    out = arr.copy()
    rnd = lambda a, s_: ((a * 374761393 + s_ * 2246822519) & 0xFFFFFFFF) / 4294967295.0  # noqa: E731

    def at(y, x):
        return ids[y, x] if 0 <= y < H and 0 <= x < W and arr[y, x, 3] else -2
    for y, x in zip(*np.nonzero(ids >= 0)):
        if not arr[y, x, 3]:
            continue
        t0 = base.get(tuple(int(v) for v in arr[y, x, :3]))
        if t0 is None:
            continue
        i = int(ids[y, x])
        up, left, dn, rt = at(y - 1, x), at(y, x - 1), at(y + 1, x), at(y, x + 1)
        if (up >= 0 and up != i) or (left >= 0 and left != i):
            out[y, x, :3] = M[0][:3] if t0 < 3.5 else M[1][:3]
            continue
        tone = t0 + (rnd(i, seed) - 0.5) * 1.1
        up2, left2 = at(y - 2, x), at(y, x - 2)
        if up != i or left != i or (up2 >= 0 and up2 != i) or (left2 >= 0 and left2 != i):
            tone += 0.9
        elif (dn >= 0 and dn != i) or (rt >= 0 and rt != i):
            tone -= 0.6
        out[y, x, :3] = M[max(0, min(5, int(round(tone))))][:3]
    return out


def shadow(arr, pts, feet, ox, oy):
    """A soft shadow along the wall's foot, on the ground in front of it (computed in world px, so neighbouring pieces agree)."""
    H, W = arr.shape[:2]
    for x, y in pts:
        cx, cy = x - feet[0] + ox, y - feet[1] + oy + 2.0
        for yy in range(int(cy - 3), int(cy + 4)):
            for xx in range(int(cx - 5), int(cx + 6)):
                if 0 <= yy < H and 0 <= xx < W and arr[yy, xx, 3] == 0 and ((xx + 0.5 - cx) / 5.0) ** 2 + ((yy + 0.5 - cy) / 3.0) ** 2 <= 1.0:
                    arr[yy, xx] = (0, 0, 0, 55)


def main():
    town = json.loads((hh.DATA.parent / "hallgrat.json").read_text(encoding="utf-8"))
    data = json.loads(hh.DATA.read_text(encoding="utf-8"))
    data["types"] = {k: v for k, v in data["types"].items() if not k.startswith("wand_")}
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("wand_*.png"):
        old.unlink()
    pieces = []
    shown = []
    for run in town.get("wall_runs", []):
        things, at, total, arc = lay(run)
        pts = [tuple(p) for p in run["pts"]]
        n_pieces = max(1, int(round((len(pts) - 1) / PIECE)))
        bounds = [len(pts) * k // n_pieces for k in range(n_pieces + 1)]
        for k in range(n_pieces):
            i0, i1 = bounds[k], min(len(pts) - 1, bounds[k + 1])
            lo = arc[i0] if k > 0 else -1e9
            hi = arc[i1] if k < n_pieces - 1 else 1e9
            sub = pts[i0:i1 + 1]
            fy = max(p[1] for p in sub)
            fx = sub[max(range(len(sub)), key=lambda q: sub[q][1])][0]
            feet = (int(round(fx)), int(round(fy)))
            m = build_piece(run, things, at, lo, hi, feet)
            if not m.prims:
                continue
            for p in m.prims:
                p.c = p.c * G
                p.r = p.r * G
            tall = run["style"] == "stadt"
            span_x = max(abs(p[0] - feet[0]) for p in sub) + (36 if tall else 16)
            span_y = max(feet[1] - p[1] for p in sub)
            cw, ground = int(2 * span_x + 40), int(span_y + (120 if tall else 48))
            raw, ids = render_ids(m, cw, ground + 14, ground)
            raw = stone_pass(raw, ids, run["seed"] + k)
            shadow(raw, sub, feet, cw // 2, ground)
            ys, xs = np.nonzero(raw[..., 3] > 0)
            x0, x1, y0, y1 = int(xs.min()), int(xs.max()) + 1, int(ys.min()), int(ys.max()) + 1
            arr = raw[y0:y1, x0:x1]
            key = "wand_%d_%d" % (run["id"], k)
            save(OUT / f"{key}.png", arr)
            chain = [[round(p[0] - feet[0], 1), round(p[1] - feet[1], 1)] for p in sub]  # the wall's line: the collision is a row of boxes on it
            if k < n_pieces - 1:  # reach on to the next piece's first point, so no gap is left between two pieces
                nxt = pts[min(len(pts) - 1, i1 + 1)]
                chain.append([round(nxt[0] - feet[0], 1), round(nxt[1] - feet[1], 1)])
            xs_ = [p[0] - feet[0] for p in sub]
            data["types"][key] = {"size": [arr.shape[1], arr.shape[0]], "feet": [cw // 2 - x0, ground - y0],
                                  "foot": [int(max(xs_) - min(xs_)) + 6, int(span_y) + 6], "lights": [], "chain": chain,
                                  "dir": "walls/"}
            if tall:
                data["types"][key]["thick"] = 9.0
                data["types"][key]["towers"] = [[round(at(t)[0] - feet[0], 1), round(at(t)[1] - feet[1] - 1.0, 1), round(TOWER_R * K, 1)]
                                                for t in run["towers"] if lo <= t < hi]
            pieces.append({"type": key, "px": list(feet)})
            shown.append(arr)
    data["wall_pieces"] = pieces
    hh.DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    print("%d wall runs in %d pieces" % (len(town.get("wall_runs", [])), len(pieces)))
    png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if png:
        from PIL import Image
        bx0, by0, bx1, by1 = [v * 16 for v in town["bounds"]]
        can = Image.open(png[0]) if Path(png[0]).exists() and "--over" in sys.argv else Image.new("RGBA", (bx1 - bx0, by1 - by0), (58, 98, 70, 255))
        for pc in sorted(pieces, key=lambda q: q["px"][1]):
            info = data["types"][pc["type"]]
            im = Image.open(OUT / (pc["type"] + ".png"))
            can.alpha_composite(im, (pc["px"][0] - info["feet"][0] - bx0, pc["px"][1] - info["feet"][1] - by0))
        can.save(png[0])


if __name__ == "__main__":
    main()
