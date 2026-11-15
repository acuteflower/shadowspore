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
from hut_lib import BARK_D, FIRE, glow_of  # noqa: E402
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
ASHLAR = len(h.RAMPS)           # the town wall's and towers' faces: drawn smooth, coursed afterwards by ashlar_pass (5 px courses)
h.RAMPS.append([(c[0], c[1], min(255, c[2] + 1), 255) for c in hh.MASON[1:5]])
PLINTH = len(h.RAMPS)           # the battered foot: bigger blocks (8 px courses)
h.RAMPS.append([(c[0], min(255, c[1] + 1), c[2], 255) for c in hh.MASON[1:5]])
COURSED = ((ASHLAR, 5, 8, 14), (PLINTH, 8, 13, 21))
BLOOMS = (hh.WINE, hh.OCHRE, hh.PLUM, hh.FRUIT)
TOP = 52.0                     # model units: the town wall's walkway (a house's eaves stand at about 30: the wall towers over them)
TOWER_R = 15.0
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
    if style == "koppel":
        return lay_fence(run, rng, total), at, total, arc
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


def lay_fence(run, rng, total):
    """The paddock's wooden fence: split posts about 11 px apart (a little crooked), two rails between each pair (now and then one sagging
    or a third, newer one nailed on), grass at the posts; strong gate posts with a cap where the run ends at the gate."""
    things = []
    posts = run.get("posts", [False, False])
    n = max(1, int(round(total / 11.0)))
    ss = [total * k / n for k in range(n + 1)]
    for k, s in enumerate(ss):
        gate = (k == 0 and posts[0]) or (k == n and posts[1])
        things.append((s, "gpost" if gate else "fpost", (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), rng.random())))
        if rng.random() < 0.55:
            things.append((s + 0.01, "tuft_out", (rng.random(),)))
    for k in range(n):
        q = rng.random()
        things.append(((ss[k] + ss[k + 1]) / 2, "rails", (ss[k], ss[k + 1], q)))
    return things


def lay_rampart(run, rng, total):
    """The town wall: a battered plinth of big blocks, coursed ashlar, a string course, a corbelled parapet (machicolation brackets under it)
    with capped merlons on the outer side and a paved wall walk, cross-shaped arrow slits with dressed surrounds, buttresses, torches on
    the town side, streaks of damp, moss and ivy; round towers at `towers` (arc px)."""
    seed = run["seed"]
    towers = run.get("towers", [])
    tower_px = TOWER_R * K

    def free(s, pad=0.0):
        return all(abs(s - t) > tower_px + pad for t in towers)

    def top_at(s):
        return TOP + 1.6 * noise1(s, seed, 80)
    things = []
    s = 0.0
    while s < total - 0.5:
        w = min(8.0, total - s)
        mid = s + w / 2
        if free(mid, -4.0):
            top = top_at(mid)
            hw = w / K / 2.0                                   # half the segment in model units
            things.append((mid, "body", (hw * 2.6, top)))      # long, flat-faced: neighbours overlap, so the face stays even
            things.append((mid, "plinth_cap", (hw * 1.6, 14.2)))
            things.append((mid, "cordon", (hw * 1.6, top - 13.0)))
            things.append((mid, "walk", (hw * 1.6, top + 0.5)))
            things.append((mid, "parapet", (hw * 2.6, top)))
            if rng.random() < 0.3:
                things.append((mid, "streak", (top - 14.0, rng.random())))
            if rng.random() < 0.1:
                things.append((mid, "ivy", (top - 2.0,)))
            if rng.random() < 0.35:
                things.append((mid + rng.uniform(-3, 3), "tuft_out", (rng.random(),)))
            if rng.random() < 0.25:
                things.append((mid, "tuft_in", (rng.random(),)))
            if rng.random() < 0.18:
                things.append((mid, "moss_foot", (rng.random(),)))
        s += w
    s = 3.0
    while s < total - 2.0:  # machicolation: a bracket every 6 px under the overhanging breastwork
        if free(s, 1.0):
            things.append((s, "corbel", (top_at(s),)))
        s += 6.0
    s = 6.0
    while s < total - 5.0:  # merlons 9 px wide with 5 px embrasures between them
        if free(s, 6.0):
            things.append((s, "merlon", (top_at(s), rng.random())))
            if rng.random() < 0.1:
                things.append((s, "moss_top", (rng.uniform(1.4, 2.4), top_at(s) + 11.6)))
        s += 14.0
    s = rng.uniform(12, 26)
    while s < total - 10:  # arrow slits
        if free(s, 8.0):
            things.append((s, "slit", (top_at(s) - 21.0,)))
        s += rng.uniform(30, 44)
    s = rng.uniform(34, 56)
    while s < total - 24:  # buttresses on the outside
        if free(s, 18.0):
            things.append((s, "buttress", (top_at(s), rng.random())))
        s += rng.uniform(60, 90)
    s = rng.uniform(40, 80)
    while s < total - 20:  # a torch on the town side
        if free(s, 16.0):
            things.append((s, "torch", (top_at(s) - 20.0,)))
        s += rng.uniform(90, 140)
    for t in towers:
        things.append((t, "tower", (rng.random(), top_at(t))))
    return things


def ring(m, base, y, r, hgt, n, rng, mats, off=0.0, depth=2.2, flat=1.0):
    """One course of a round tower: n blocks round the circle, each turned along it."""
    for i in range(n):
        a = 2 * math.pi * (i + off) / n
        w = math.pi * r / n * 1.08
        m.ell(base + V(math.cos(a) * r, y + hgt / 2, math.sin(a) * r), (w, hgt * 0.53 * flat, depth), mats[int(rng.random() * len(mats))],
              R=h.rot_y(-a - math.pi / 2))


def drum(m, base, y0, y1, r, mat, r1=None, step=0.8):
    """A smooth round drum from y0 to y1 (radius r, or r..r1 for a batter): thin discs stacked, coursed later by ashlar_pass."""
    r1 = r if r1 is None else r1
    n = max(2, int((y1 - y0) / step))
    for i in range(n + 1):
        t = i / n
        rr = r + (r1 - r) * t
        m.ell(base + V(0, y0 + (y1 - y0) * t, 0), (rr, step * 0.75, rr), mat)


def block(m, c, y0, y1, w, t, mat, R, step=0.8):
    """An upright block of masonry (half width w, half depth t) from y0 to y1 at c: flat ellipsoids stacked, coursed later."""
    n = max(1, int((y1 - y0) / step))
    for i in range(n + 1):
        m.ell(c + V(0, y0 + (y1 - y0) * i / n, 0), (w, step * 0.75, t), mat, R=R)


def cone(m, base, y0, r0, height, rng):
    """A slate cone: rows of single slates round it, every row hanging over the one below, a dark core under them."""
    rows = int(height / 1.15)
    for j in range(rows):
        t = j / rows
        rr = r0 * (1 - t) ** 1.05 + 0.15
        y = y0 + height * t
        m.ell(base + V(0, y + 0.4, 0), (max(0.3, rr - 0.5), 0.8, max(0.3, rr - 0.5)), ROOF_T)
        n = max(5, int(2 * math.pi * rr / 1.5))
        slope = math.atan2(r0, height)
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * (j % 2) + rng.uniform(-0.12, 0.12)) / n
            ww = math.pi * rr / n * 1.12
            R = h.rot_y(-a - math.pi / 2) @ h.rot_x(-slope)
            m.ell(base + V(math.cos(a) * rr, y, math.sin(a) * rr), (ww, 0.95, 0.32), ROOF_T, R=R)


def build_tower(m, base, q, top, rng):
    """A round tower, much broader and taller than the curtain: a battered foot of big blocks, a smooth coursed drum (the houses' masonry),
    two string courses, slits with dressed surrounds and a lit window, a ring of machicolation corbels under an overhanging crown, then
    merlons and a banner, or a tall cone of single slates with a dormer, a knob and a pennant."""
    r0 = TOWER_R
    height = top + 22.0
    drum(m, base, 0.6, 14.0, r0 + 2.2, PLINTH, r1=r0 + 0.8)
    m.ell(base + V(0, 0.8, 0), (r0 + 2.6, 1.0, r0 + 2.6), PLINTH)
    drum(m, base, 14.0, height, r0, ASHLAR)
    ring(m, base, 13.6, r0 + 1.1, 1.8, 26, rng, (STONE_L,), depth=1.2)   # the talus cap
    ring(m, base, top - 13.8, r0 + 0.6, 1.6, 26, rng, (STONE_L,), depth=1.0)
    for yy, aa in ((top - 26.0, 0.5 * math.pi), (top - 26.0, 0.16 * math.pi), (top - 26.0, 0.84 * math.pi), (top - 6.0, 0.3 * math.pi),
                   (top - 6.0, 0.7 * math.pi), (24.0, 0.62 * math.pi)):
        R = h.rot_y(-aa - math.pi / 2)
        c = base + V(math.cos(aa) * (r0 - 0.1), yy, math.sin(aa) * (r0 - 0.1))
        m.ell(c, (1.5, 3.5, 0.75), STONE_L, R=R)                                   # dressed surround
        m.ell(c + V(math.cos(aa), 0, math.sin(aa)) * 0.15, (0.45, 2.8, 0.75), DARK, R=R)
        m.ell(c + V(math.cos(aa), 0.75, math.sin(aa)) * 0.15 + V(0, 0.6, 0), (1.2, 0.4, 0.75), DARK, R=R)
    win = base + V(0, top + 3.0, r0 - 0.2)                                          # the warden's window towards the town
    for x in (-2.4, 2.4):
        m.ell(win + V(x, 0, 0), (0.9, 3.4, 0.9), STONE_L)
    m.ell(win + V(0, 3.6, 0.1), (3.0, 1.0, 0.9), STONE_L)
    m.ell(win + V(0, -3.4, 0.4), (3.2, 0.55, 1.2), STONE_L)
    m.ell(win + V(0, 0, 0.35), (1.5, 2.9, 0.6), FIRE)
    m.ell(win + V(0, 0, 0.6), (0.18, 2.9, 0.4), hh.IRON)                          # its iron bar
    for i in range(24):  # machicolation: two steps of corbels round the drum
        a = 2 * math.pi * i / 24
        R = h.rot_y(-a - math.pi / 2)
        for dr, dy in ((0.5, -2.6), (1.3, -1.2)):
            m.ell(base + V(math.cos(a) * (r0 + dr), height + dy, math.sin(a) * (r0 + dr)), (0.85, 0.85, 1.2), STONE_L, R=R)
    drum(m, base, height, height + 3.6, r0 + 2.0, ASHLAR)
    ring(m, base, height + 3.4, r0 + 2.3, 1.2, 28, rng, (STONE_L,), depth=1.0)
    if q < 0.5:  # crenellated crown
        m.ell(base + V(0, height + 4.2, 0), (r0 + 1.4, 0.6, r0 + 1.4), STONE_L)
        for i in range(10):
            a = 2 * math.pi * (i + 0.5) / 10
            R = h.rot_y(-a - math.pi / 2)
            c = base + V(math.cos(a) * (r0 + 1.7), 0, math.sin(a) * (r0 + 1.7))
            block(m, c, height + 4.4, height + 9.6, 2.4, 1.1, ASHLAR, R)
            m.ell(c + V(0, height + 10.2, 0), (2.7, 0.6, 1.5), STONE_L, R=R)
        pole = base + V(-2.6, height + 4.0, -1.6)
        m.limb(pole, pole + V(0, 17.0, 0), 0.34, 0.26, BARK_D)
        for k2 in range(7):
            m.ell(pole + V(1.3 + k2 * 1.25, 15.8 - k2 * 0.3 - math.sin(k2 * 1.1) * 0.5, 0), (0.9, 1.9 - k2 * 0.16, 0.25), hh.WINE)
        m.ell(pole + V(3.2, 15.4, 0.3), (0.8, 0.8, 0.12), hh.OCHRE)
        if q < 0.2:
            hut_lib.tuft(m, base + V(2.5, height + 4.6, 1.5), rng, blades=5, height=2.8)
    else:  # a tall cone of slates with a dormer and a banner
        ch = 30.0
        cone(m, base, height + 4.0, r0 + 3.2, ch, rng)
        fr = (r0 + 3.2) * (1 - 0.26) ** 1.05                                        # the cone's radius at the dormer
        dorm = base + V(0, height + 4.0 + ch * 0.26, fr + 0.6)
        block(m, dorm, -2.4, 2.6, 2.4, 1.3, ASHLAR, None)
        m.ell(dorm + V(0, 0.2, 1.1), (1.2, 1.8, 0.4), FIRE)
        for sx in (-1, 1):  # its little gable roof
            m.ell(dorm + V(sx * 1.4, 4.0, 0.2), (2.0, 0.5, 2.0), ROOF_T, R=h.rot_z(-sx * 0.65) if hasattr(h, "rot_z") else None)
        tip = base + V(0, height + 4.0 + ch, 0)
        m.ell(tip, (0.8, 0.8, 0.8), hh.OCHRE)
        m.limb(tip, tip + V(0, 9.0, 0), 0.3, 0.22, hh.IRON)
        for k2 in range(7):
            m.ell(tip + V(1.3 + k2 * 1.25, 8.0 - k2 * 0.3 - math.sin(k2 * 1.1) * 0.5, 0), (0.9, 1.6 - k2 * 0.14, 0.25), hh.WINE)
    if q > 0.7:
        hut_lib.ivy(m, base + V(-r0 * 0.6, height - 2, r0 * 0.8), height * 0.7, rng, sway=0.3)
    for k3 in range(6):
        a = rng.uniform(0.1, math.pi - 0.1)
        hut_lib.tuft(m, base + V(math.cos(a) * (r0 + 3.0), 0.0, math.sin(a) * (r0 + 3.0)), rng, blades=4, height=3.0)
    for k3 in range(3):  # a few stones fallen at its foot
        a = rng.uniform(0.2, math.pi - 0.2)
        m.ell(base + V(math.cos(a) * (r0 + 4.0), 0.6, math.sin(a) * (r0 + 4.0)), (1.0, 0.6, 0.8), FIELD_L)


def build_piece(run, things, at, lo, hi, feet):
    """The model of the things whose middle lies in [lo, hi) of the run, relative to `feet` (px)."""
    m = h.Model()
    for s, kind, a in things:
        if not (lo <= s < hi):
            continue
        rng = rng_for(run["seed"] * 7 + int(s * 13) + 17)   # per thing: a piece rendered with its neighbours draws them the same
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
        elif kind == "body":  # the curtain: a battered foot of big blocks, then the coursed face up to the walk
            w, top = a
            block(m, base + out_ * 0.6, 0.6, 7.0, w, 6.0, PLINTH, R)
            block(m, base + out_ * 0.3, 7.0, 14.0, w, 5.2, PLINTH, R)
            block(m, base, 14.0, top, w, 4.4, ASHLAR, R)
        elif kind == "parapet":  # the breastwork on the corbels, overhanging the outer face
            w, top = a
            block(m, base + out_ * 4.9, top - 1.4, top + 4.2, w, 1.1, ASHLAR, R)
        elif kind == "walk":  # the wall walk: flagstones seen from above, a low kerb on the town side
            w, top = a
            m.ell(base + V(0, top, 0), (w, 1.0, 4.6), STONE_L, R=R)
            m.ell(base - out_ * 3.9 + V(0, top + 1.2, 0), (w, 0.8, 0.8), STONE, R=R)
        elif kind == "plinth_cap":
            w, y = a
            m.ell(base + out_ * 0.4 + V(0, y, 0), (w, 0.8, 5.4), STONE_L, R=R)
        elif kind == "cordon":
            w, y = a
            m.ell(base + out_ * 0.5 + V(0, y, 0), (w, 0.75, 4.9), STONE_L, R=R)
        elif kind == "corbel":
            top = a[0]
            m.ell(base + out_ * 4.6 + V(0, top - 3.6, 0), (0.8, 0.9, 1.0), STONE_L, R=R)
            m.ell(base + out_ * 5.2 + V(0, top - 2.2, 0), (0.9, 0.8, 1.2), STONE_L, R=R)
        elif kind == "merlon":
            top, q = a
            c = base + out_ * 4.9
            block(m, c, top + 4.2, top + 10.6, 2.9, 1.1, ASHLAR, R)
            m.ell(c + V(0, top + 11.1, 0), (3.3, 0.6, 1.5), STONE_L, R=R)                 # the coping
            m.ell(c + V(0, top + 7.2, 0), (0.4, 1.9, 1.5), DARK, R=R)                     # a loop in the merlon
            if q < 0.15:
                m.ell(c + V(1.6, top + 11.6, 0), (1.0, 0.5, 1.0), MOSS, R=R)
        elif kind == "slit":  # a cross loop in a dressed surround
            y = a[0]
            m.ell(base + V(0, y, 0), (1.6, 3.6, 4.75), STONE_L, R=R)
            m.ell(base + V(0, y, 0), (0.45, 2.9, 5.0), DARK, R=R)
            m.ell(base + V(0, y + 0.6, 0), (1.3, 0.4, 5.0), DARK, R=R)
        elif kind == "buttress":
            top, q = a
            for k, (y0, y1, d) in enumerate(((0.6, top * 0.36, 4.2), (top * 0.36, top * 0.64, 3.0), (top * 0.64, top * 0.84, 1.9))):
                c = base + out_ * (4.4 + d)
                block(m, c, y0, y1, 3.1, d + 0.4, PLINTH if k == 0 else ASHLAR, R)
                m.ell(c + out_ * 0.2 + V(0, y1 + 0.2, 0), (3.4, 0.7, d + 0.7), STONE_L, R=R)   # the weathering on each step
            if q < 0.4:
                hut_lib.tuft(m, base + out_ * 8.0, rng, blades=5, height=3.0)
        elif kind == "streak":  # damp running down from the cordon: darker field stone
            y, q = a
            for k in range(4):
                m.ell(base + out_ * 4.5 + V(rng.uniform(-1.5, 1.5), y - k * 3.2, 0), (0.9 - k * 0.15, 1.8, 0.3), MOSS, R=R)
        elif kind == "moss_foot":
            m.ell(base + out_ * 6.8 + V(0, 1.2, 0), (4.0, 1.4, 1.4), MOSS, R=R)
            m.ell(base - out_ * 6.8 + V(1.0, 1.0, 0), (3.0, 1.1, 1.2), MOSS_L, R=R)
        elif kind == "torch":
            y = a[0]
            c = base - out_ * 4.6
            m.limb(c + V(0, y - 2.0, 0), c - out_ * 1.6 + V(0, y + 1.5, 0), 0.3, 0.3, hut_lib.IRON)
            m.ell(c - out_ * 1.7 + V(0, y + 1.6, 0), (0.7, 0.5, 0.7), hut_lib.IRON)
            m.ell(c - out_ * 1.7 + V(0, y + 3.0, 0), (0.7, 1.4, 0.7), FIRE)
        elif kind in ("fpost", "gpost"):
            lx, lz, q = a
            top = 12.5 if kind == "fpost" else 17.0
            r = 0.75 if kind == "fpost" else 1.25
            hut_lib.log(m, base + V(0, 0.0, 0), base + V(lx, top, lz), r, hut_lib.BARK, step=0.8)
            m.ell(base + V(lx, top + 0.2, lz), (r * 0.9, 0.35, r * 0.9), hut_lib.PLANK_W)
            if kind == "gpost":
                m.ell(base + V(lx, top + 1.0, lz), (2.0, 0.7, 1.8), hut_lib.PLANK)
                m.ell(base + V(0, 0.6, 0), (2.4, 0.8, 2.0), STONE)
                if q < 0.5:  # a lantern on the gate post
                    hut_lib.log(m, base + V(lx, top - 1.0, lz), base + V(lx + 2.6, top - 1.0, lz), 0.2, hut_lib.IRON, step=0.4)
                    m.ell(base + V(lx + 2.6, top - 3.2, lz), (0.9, 1.4, 0.9), FIRE)
                    m.ell(base + V(lx + 2.6, top - 1.6, lz), (1.1, 0.35, 1.0), hut_lib.IRON)
        elif kind == "rails":
            s0, s1, q = a
            pa, pb = at(s0), at(s1)
            A = to_model(pa[0] - feet[0], pa[1] - feet[1])
            B = to_model(pb[0] - feet[0], pb[1] - feet[1])
            for y0, y1, mat in ((9.6, 9.6 - (2.4 if q < 0.1 else 0.0), hut_lib.PLANK_W), (5.2, 5.2, hut_lib.PLANK)):
                mid = (A + B) / 2 + V(0, (y0 + y1) / 2 - 0.5, 0)
                hut_lib.log(m, A + V(0, y0, 0), mid, 0.42, mat, step=0.7)
                hut_lib.log(m, mid, B + V(0, y1, 0), 0.42, mat, step=0.7)
            if q > 0.9:  # a newer board nailed on low
                hut_lib.log(m, A + V(0, 2.4, 0), B + V(0, 2.6, 0), 0.38, hut_lib.PLANK_W, step=0.7)
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


def _hash(a, b, seed):
    n = (a * 374761393 + b * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def ashlar_pass(arr, ox, oy, seed):
    """The houses' masonry (art_hallgrat_houses.wall_pass) on the smooth ASHLAR and PLINTH faces, anchored to the world (ox, oy = world px
    of the picture's top left), so the courses run on unbroken from one piece of the wall to the next: courses 5 px (the foot: 8 px),
    blocks 8-14 (13-21) px, every course offset, dark joints, a lit top and left edge, a darker bottom, each block its own tone."""
    H, W = arr.shape[:2]
    out = arr.copy()
    key = (arr[..., 0].astype(np.int64) << 16) | (arr[..., 1].astype(np.int64) << 8) | arr[..., 2].astype(np.int64)
    Y, X = np.mgrid[0:H, 0:W]
    wy, wx = (Y + oy).astype(np.int64), (X + ox).astype(np.int64)
    M = np.array([c[:3] for c in hh.MASON], dtype=np.uint8)
    for mat, ch, w0, w1 in COURSED:
        band = np.full((H, W), -1)
        for b, c in enumerate(h.RAMPS[mat]):
            band[(key == ((c[0] << 16) | (c[1] << 8) | c[2])) & (arr[..., 3] > 0)] = b
        sel = band >= 0
        if not sel.any():
            continue
        for gap in (1, 2):  # thin upright ink lines where two overlapping body slabs meet: the face is one surface, close them
            left = np.full_like(band, -1)
            left[:, gap:] = band[:, :-gap]
            right = np.full_like(band, -1)
            right[:, :-1] = band[:, 1:]
            fill = (band == 0) & (left >= 1) & (right >= 1) if gap == 1 else \
                (band == 0) & (left >= 1) & (np.roll(band, -1, 1) == 0) & (np.roll(band, -2, 1) >= 1)
            band = np.where(fill, left, band)
            if gap == 2:
                nxt = np.roll(fill, 1, 1)
                band = np.where(nxt & (band == 0), np.roll(band, 1, 1), band)
        course = wy // ch
        cy = wy % ch
        width = w0 + (_hash(course, 1 + mat, seed) * (w1 - w0 + 1)).astype(np.int64)
        off = (_hash(course, 2 + mat, seed) * width).astype(np.int64)
        bx = (wx + off) // width
        cx = (wx + off) % width
        joint = (cy == 0) | (cx == 0)
        tone = band + 1 + (_hash(bx, course, seed + 7) - 0.5) * 1.1
        tone = tone + np.where((cy == 1) | (cx == 1), 0.9, np.where((cy == ch - 1) | (cx == width - 1), -0.6, 0.0))
        tone = tone - 1.4 * ((_hash(bx, course, seed + 9) > 0.93) & (cy == 2))
        col = M[np.clip(np.rint(tone), 0, 5).astype(int)]
        jcol = np.where((band < 3)[..., None], M[0], M[1])
        pick = np.where(joint[..., None], jcol, col)
        out[sel, :3] = pick[sel]
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
    import hashlib
    src_hash = hashlib.md5(Path(__file__).read_bytes()).hexdigest()
    old_cache = data.get("wall_cache", {}) if "--all" not in sys.argv else {}
    old_types = dict(data["types"])
    old_pieces = data.get("wall_pieces", [])
    data["types"] = {k: v for k, v in data["types"].items() if not k.startswith("wand_")}
    OUT.mkdir(parents=True, exist_ok=True)
    cache = {}
    keep = set()
    for run in town.get("wall_runs", []):  # a run that is exactly as it was (and this script too) keeps its pictures
        key_ = hashlib.md5((json.dumps(run, sort_keys=True) + src_hash).encode()).hexdigest()
        cache[str(run["id"])] = key_
        if old_cache.get(str(run["id"])) == key_:
            keep.add(run["id"])
    for old in OUT.glob("wand_*.png"):
        if int(old.stem.split("_")[1]) not in keep:
            old.unlink()
    pieces = []
    shown = []
    for run in town.get("wall_runs", []):
        if run["id"] in keep:
            mine = [pc for pc in old_pieces if pc["type"].startswith("wand_%d_" % run["id"])]
            for pc in mine:
                data["types"][pc["type"]] = old_types[pc["type"]]
            pieces += mine
            continue
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
            tall = run["style"] == "stadt"
            m = build_piece(run, things, at, lo, hi, feet)
            if not m.prims:
                continue
            own = m
            if tall:  # rendered with a little of its neighbours, then cut to its own silhouette: no seam where two pieces meet
                m = build_piece(run, things, at, lo - 16.0, hi + 16.0, feet)
            for mm in ({id(m): m, id(own): own}).values():
                for p in mm.prims:
                    p.c = p.c * G
                    p.r = p.r * G
            span_x = max(abs(p[0] - feet[0]) for p in sub) + (60 if tall else 16)
            span_y = max(feet[1] - p[1] for p in sub)
            cw, ground = int(2 * span_x + 40), int(span_y + (250 if tall else 48))
            raw, ids = render_ids(m, cw, ground + 14, ground)
            if own is not m:
                cut = to_array(hut_lib.render(own, cw, ground + 14, ground))[..., 3] == 0
            raw = stone_pass(raw, ids, run["seed"] + k)
            if tall:  # world px of the picture's top left: the courses run on from piece to piece
                raw = ashlar_pass(raw, feet[0] - cw // 2, feet[1] - ground, 911)
                raw[cut] = 0
            shadow(raw, sub, feet, cw // 2, ground)
            ys, xs = np.nonzero(raw[..., 3] > 0)
            x0, x1, y0, y1 = int(xs.min()), int(xs.max()) + 1, int(ys.min()), int(ys.max()) + 1
            arr = raw[y0:y1, x0:x1]
            key = "wand_%d_%d" % (run["id"], k)
            save(OUT / f"{key}.png", arr)
            glow = glow_of(arr, (FIRE,))  # torches and lit tower windows: their unlit sheet and a warm light
            lit = []
            if glow[..., 3].any():
                save(OUT / f"{key}_glow.png", glow)
                gy, gx = np.nonzero(glow[..., 3] > 0)
                lit = [[int(gx.mean()), int(gy.max())]]
            chain = [[round(p[0] - feet[0], 1), round(p[1] - feet[1], 1)] for p in sub]  # the wall's line: the collision is a row of boxes on it
            if k < n_pieces - 1:  # reach on to the next piece's first point, so no gap is left between two pieces
                nxt = pts[min(len(pts) - 1, i1 + 1)]
                chain.append([round(nxt[0] - feet[0], 1), round(nxt[1] - feet[1], 1)])
            xs_ = [p[0] - feet[0] for p in sub]
            data["types"][key] = {"size": [arr.shape[1], arr.shape[0]], "feet": [cw // 2 - x0, ground - y0],
                                  "foot": [int(max(xs_) - min(xs_)) + 6, int(span_y) + 6], "lights": lit, "chain": chain,
                                  "dir": "walls/"}
            if run["style"] == "koppel":
                data["types"][key]["thick"] = 5.0
            if tall:
                data["types"][key]["thick"] = 16.0
                data["types"][key]["towers"] = [[round(at(t)[0] - feet[0], 1), round(at(t)[1] - feet[1] - 1.0, 1), round(TOWER_R * K, 1)]
                                                for t in run["towers"] if lo <= t < hi]
            pieces.append({"type": key, "px": list(feet)})
            shown.append(arr)
    data["wall_pieces"] = pieces
    data["wall_cache"] = cache
    print("kept %d runs as they were" % len(keep))
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
