#!/usr/bin/env python3
"""Ellie swims on the water surface (docs/schwimmen_konzept.md, step 2). Needs numpy; uses the heroine renderer of art_hero3d.py.

The body is rendered twice from the same pose, cut by the water plane (model y = 0): everything ABOVE the water, sharp, and everything BELOW it
as a silhouette the game tints and refracts. 8 facings (rows E SE S SW W NW N NE like every sheet), frames of 64x72, the pelvis on the sprite's x
centre, the water plane on row 46 (so the sprite offset is (0, -10): the water plane lies on the player's origin).

  py -3 tools/art_hero_swim.py                 writes assets/characters/player_swim.png, player_swim_under.png and the "swim" entry of data/hero_rig.json
  py -3 tools/art_hero_swim.py contact out.png [sector] [clip]   contact sheet of one sector (default 2 = south), all clips or one, composed over water
  py -3 tools/art_hero_swim.py frame out.png clip i0 i1 ...      zoomed single frames of one clip, all eight facings stacked

Clips (name, frames, fps): tread, breast, crawl (loops); enter (wade -> swim, played backwards it is the stand-up); t2b (tread -> breast, backwards:
breast -> tread); b2c (breast -> crawl, backwards: crawl -> breast); dive (a header into the water, ends treading); shake (wringing out after
the stand-up, on land); float (dead on her back). Pose conventions: the pelvis sits `sink` model units below the water; "forward" of the swimmer
is the model's +y before the pitch turns the body (the `fsd` helper takes forward / side / depth from the pelvis)."""
import json
import math
import sys
from multiprocessing import Pool
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero_emerge as em  # noqa: E402
import art_hero3d as hero  # noqa: E402
from gen_art import CLEAR, ROOT, write_png  # noqa: E402

hero.FW, hero.FH = 64, 72
FW, FH = 64, 72
WATER_ROW = 46
hero.GROUND_ROW = float(WATER_ROW)  # the renderer's ground row is the water plane here

CLIPS = [  # name, frames, fps
    ("tread", 12, 8), ("breast", 14, 9), ("crawl", 16, 14), ("enter", 7, 12), ("t2b", 5, 12), ("b2c", 4, 12),
    ("dive", 12, 12), ("shake", 10, 14), ("float", 6, 4),
]
STARTS = {}
_n = 0
for _name, _count, _fps in CLIPS:
    STARTS[_name] = _n
    _n += _count
TOTAL = _n


# ---------------------------------------------------------------- pose helpers
def fsd(f, s, d):
    """Forward / side / depth from the pelvis (the swimmer's own frame) as a model-space target before the pitch: forward = +y, down = +z."""
    return (s, 24.0 + f, d)


def cyc(keys, u):
    """Closed loop through (u, values) keys, cosine-eased; values are tuples of numbers."""
    u = u % 1.0
    ks = keys + [(keys[0][0] + 1.0, keys[0][1])]
    for (u0, a), (u1, b) in zip(ks, ks[1:]):
        if u0 <= u <= u1:
            k = (u - u0) / max(u1 - u0, 1e-9)
            k = 0.5 - 0.5 * math.cos(math.pi * k)
            return tuple(x * (1 - k) + y * k for x, y in zip(a, b))
    return ks[0][1]


def pose(pitch, sink, lean=0.0, twist=0.0, legs=((0.0, 0.05), (0.0, 0.05)), hl=(3.0, 26.0, 1.0), hr=(-3.0, 26.0, 1.0),
         hair=(0.0, 0.0, 0.0), droop=1.5, head_yaw=0.0, pole_l=(0.8, -0.4, -0.5), pole_r=(-0.8, -0.4, -0.5), spread=0.8, curl=0.5, lift=0.0, nod=0.0):
    """One swimming key pose. `pitch` turns the body about the pelvis (0 upright, 1.5 flat face down, negative on the back), `sink` is how far the
    pelvis lies under the water plane, `lift` raises everything (leaps)."""
    d = em.Q(twist=twist, lean=lean, pz=0.0, dy=0.0, pitch=pitch if abs(pitch) > 1e-3 else 0.001, shift=(0.0, -24.0 - sink + lift, 0.0), legs=legs,
             hand_l=hl, hand_r=hr, hair=hair, droop=droop, pole_l=pole_l, pole_r=pole_r)
    d["level"] = True
    d["head_yaw"] = head_yaw
    d["spread"] = spread
    d["curl"] = curl
    if nod:
        d["nod"] = nod
    return d


def drift(u, k=1.0, waves=2):
    """The wet mane afloat: it streams back along the body, lifted a little off the back, waving with the strokes."""
    s = 2 * math.pi * u * waves
    return (1.1 * math.sin(s), -7.0 * k, -3.4 * k + 0.9 * math.sin(s + 1.0))


def mix(a, b, k):
    return em.mix(a, b, k)


# ---------------------------------------------------------------- the cycles
def stand():
    """Standing in hip-deep water (the wading pose the stand-up ends in)."""
    return pose(0.0, 0.0, legs=((0.0, 0.04), (0.0, 0.04)), hl=(4.5, 14.0, 1.0), hr=(-4.5, 14.0, 1.0), droop=0.5)


def tread(i, n=12):
    u = i / n
    s = 2 * math.pi * u
    legs = ((0.35 + 0.35 * math.sin(s), 1.0 + 0.4 * math.cos(s)), (0.35 + 0.35 * math.sin(s + math.pi), 1.0 + 0.4 * math.cos(s + math.pi)))
    hl = (9.0 + 1.8 * math.cos(s), 31.4 + 2.2 * math.sin(s), 2.5 + 2.0 * math.cos(s))
    hr = (-9.0 - 1.8 * math.cos(s + math.pi), 31.4 + 2.2 * math.sin(s + math.pi), 2.5 + 2.0 * math.cos(s + math.pi))
    return pose(0.0, 7.5 + 0.7 * math.sin(s), lean=0.04, legs=legs, hl=hl, hr=hr, droop=3.5, head_yaw=0.12 * math.sin(s * 0.5),
                hair=(0.0, -0.5, 0.0), pole_l=(0.8, -0.5, 0.3), pole_r=(-0.8, -0.5, 0.3), spread=1.1)


BREAST_ARM = [  # (u, (forward, side, depth)) for the left arm; the right one mirrors it
    (0.00, (25.0, 3.0, 1.0)), (0.12, (25.0, 3.0, 1.0)), (0.30, (20.0, 11.0, 3.0)), (0.50, (14.0, 4.5, 5.0)),
    (0.62, (17.0, 3.0, 3.5)), (0.78, (25.0, 3.0, 1.0)),
]
BREAST_LEG = [  # (u, (thigh, flex))
    (0.00, (0.05, 0.10)), (0.35, (0.10, 0.30)), (0.50, (0.55, 1.90)), (0.68, (0.22, 0.35)), (0.82, (0.05, 0.10)),
]


def breast(i, n=14):
    u = i / n
    a = cyc(BREAST_ARM, u)
    th, fl = cyc(BREAST_LEG, u + 0.04)
    glide = 0.5 + 0.5 * math.cos(2 * math.pi * u)  # high at the glide: the body lifts and sinks a little with the stroke
    return pose(1.36, 1.5 + 0.8 * (1.0 - glide), lean=-0.5, legs=((th, fl), (th * 0.9, fl)),
                hl=fsd(a[0], a[1], a[2]), hr=fsd(a[0], -a[1], a[2]), droop=2.4, hair=drift(u, 0.9, 1),
                pole_l=(0.7, -0.3, -0.6), pole_r=(-0.7, -0.3, -0.6), spread=1.6, curl=1.0, nod=-0.8)


CRAWL_ARM = [
    (0.00, (26.0, 4.0, -1.0)), (0.10, (24.0, 4.0, 3.0)), (0.25, (16.0, 5.0, 7.0)), (0.40, (8.0, 6.0, 4.0)), (0.50, (4.0, 7.0, -1.0)),
    (0.65, (12.0, 10.0, -8.0)), (0.85, (22.0, 7.0, -7.0)),
]


def crawl(i, n=16):
    u = i / n
    a = cyc(CRAWL_ARM, u)
    b = cyc(CRAWL_ARM, u + 0.5)
    kick = 2 * math.pi * 4 * u
    legs = ((0.32 * math.sin(kick), 0.30 + 0.22 * math.cos(kick)), (0.32 * math.sin(kick + math.pi), 0.30 + 0.22 * math.cos(kick + math.pi)))
    bump = max(0.0, math.cos(2 * math.pi * (u - 0.5))) ** 3  # once per cycle she turns her face to breathe
    return pose(1.40, 0.8, lean=-0.22, twist=0.42 * math.sin(2 * math.pi * u), legs=legs,
                hl=fsd(a[0], a[1], a[2]), hr=fsd(b[0], -b[1], b[2]), droop=1.8, head_yaw=1.25 * bump, hair=drift(u, 1.0, 2),
                pole_l=(0.6, 0.0, -0.9), pole_r=(-0.6, 0.0, -0.9), spread=1.8, curl=1.2, nod=-1.1 * (1.0 - 0.6 * bump))


def enter(i, n=7):
    """Wading -> swimming: lean in, push off, the body comes up flat."""
    keys = [
        stand(),
        pose(0.15, 0.0, lean=0.35, legs=((0.45, 0.9), (0.35, 0.7)), hl=(5.0, 16.0, 6.0), hr=(-5.0, 16.0, 6.0), droop=0.8),
        pose(0.5, 1.5, lean=0.2, legs=((0.9, 1.5), (-0.3, 0.2)), hl=fsd(22.0, 3.0, 2.0), hr=fsd(22.0, -3.0, 2.0), droop=1.0),
        breast(0),
    ]
    t = i / (n - 1) * (len(keys) - 1)
    k = min(int(t), len(keys) - 2)
    f = t - k
    return mix(keys[k], keys[k + 1], 0.5 - 0.5 * math.cos(math.pi * f))


def t2b(i, n=5):
    return mix(tread(0), breast(0), 0.5 - 0.5 * math.cos(math.pi * i / (n - 1)))


def b2c(i, n=4):
    return mix(breast(7), crawl(0), 0.5 - 0.5 * math.cos(math.pi * i / (n - 1)))


def dive(i, n=12):
    keys = [  # coil, leap, apex, falling, hands in, plunging, legs follow, turn, climb, break the surface, gasp, settle
        pose(0.0, -19.0, lean=0.55, legs=((0.9, 1.7), (0.8, 1.5)), hl=(5.0, 21.0, 6.0), hr=(-5.0, 21.0, 6.0), droop=0.5),
        pose(0.7, -26.0, lean=0.1, legs=((0.1, 0.2), (0.0, 0.2)), hl=fsd(25.0, 3.0, 0.0), hr=fsd(25.0, -3.0, 0.0), droop=2.5),
        pose(1.25, -30.0, lean=0.0, legs=((0.0, 0.1), (0.0, 0.1)), hl=fsd(26.0, 3.0, 0.0), hr=fsd(26.0, -3.0, 0.0), droop=3.0),
        pose(1.55, -20.0, lean=0.0, legs=((-0.1, 0.1), (-0.1, 0.1)), hl=fsd(26.0, 3.0, 0.0), hr=fsd(26.0, -3.0, 0.0), droop=4.0),
        pose(1.9, -6.0, lean=0.0, legs=((-0.1, 0.1), (-0.1, 0.1)), hl=fsd(26.0, 3.0, 0.0), hr=fsd(26.0, -3.0, 0.0), droop=6.0),
        pose(2.2, 8.0, lean=0.0, legs=((-0.1, 0.1), (-0.15, 0.2)), hl=fsd(26.0, 3.0, 1.0), hr=fsd(26.0, -3.0, 1.0), droop=6.0),
        pose(2.2, 22.0, lean=0.0, legs=((-0.2, 0.3), (-0.1, 0.1)), hl=fsd(24.0, 5.0, 2.0), hr=fsd(24.0, -5.0, 2.0), droop=5.0),
        pose(1.7, 24.0, lean=-0.1, legs=((0.2, 0.5), (0.1, 0.3)), hl=fsd(18.0, 9.0, 4.0), hr=fsd(18.0, -9.0, 4.0), droop=4.0),
        pose(1.0, 14.0, lean=-0.3, legs=((0.3, 0.8), (0.2, 0.6)), hl=fsd(12.0, 8.0, 5.0), hr=fsd(12.0, -8.0, 5.0), droop=3.0),
        pose(0.4, 8.0, lean=-0.3, legs=((0.4, 1.0), (0.3, 0.9)), hl=(7.0, 31.0, 4.0), hr=(-7.0, 31.0, 4.0), droop=2.0, head_yaw=0.1),
        pose(0.0, 8.5, lean=-0.1, legs=((0.4, 1.0), (0.3, 1.1)), hl=(9.0, 32.0, 3.0), hr=(-9.0, 32.0, 3.0), droop=1.5),
        tread(0),
    ]
    t = i / (n - 1) * (len(keys) - 1)
    k = min(int(t), len(keys) - 2)
    f = t - k
    return mix(keys[k], keys[k + 1], 0.5 - 0.5 * math.cos(math.pi * f))


def shake(i, n=10):
    """Standing on the bank: she shakes the water out of her hair and wrings the coat (no water plane: it lies far below her feet)."""
    u = i / n
    s = 2 * math.pi * u
    burst = math.sin(math.pi * min(u * 1.25, 1.0))
    p = pose(0.0, -21.5, lean=0.12 * burst, twist=0.16 * math.sin(3 * s) * burst, legs=((0.1, 0.25), (0.05, 0.2)),
             hl=(7.0 + 3.0 * math.sin(2 * s), 28.0 + 3.0 * math.cos(2 * s), 5.0), hr=(-7.0 - 3.0 * math.sin(2 * s), 28.0 + 3.0 * math.cos(2 * s + 1.0), 5.0),
             droop=1.0, head_yaw=0.7 * math.sin(3 * s) * burst, hair=(2.4 * math.sin(3 * s) * burst, 0.0, 0.0), spread=1.6, curl=0.8)
    p["dry"] = True
    return p


def floating(i, n=6):
    u = i / n
    s = 2 * math.pi * u
    p = pose(-1.45, 3.0 + 0.5 * math.sin(s), lean=0.0, twist=0.05 * math.sin(s), legs=((-0.05, 0.15), (0.05, 0.2)),
             hl=fsd(6.0 + math.sin(s), 9.0, 3.0), hr=fsd(5.0 - math.sin(s), -9.0, 3.0), droop=0.2, head_yaw=0.15 * math.sin(s),
             hair=(0.0, 1.0, 0.0), spread=2.0, curl=1.0, pole_l=(0.8, 0.0, -0.3), pole_r=(-0.8, 0.0, -0.3))
    p["eyes_closed"] = 1.0
    return p


FUNCS = {"tread": tread, "breast": breast, "crawl": crawl, "enter": enter, "t2b": t2b, "b2c": b2c, "dive": dive, "shake": shake, "float": floating}


# ---------------------------------------------------------------- rendering
def _cut(prims, above):
    """The water plane model y = 0 is world y = bob * SCALE = 0 here (no bob): keep one side of every primitive."""
    for p in prims:
        old = p.clip
        def clip(q, p=p, old=old):
            y = p.c[1] + ((q * p.r) @ p.R.T)[..., 1]
            ok = (y >= 0.0) if above else (y < 0.0)
            return ok & old(q) if old is not None else ok
        p.clip = clip


def _strip(rows):
    """to_pixels draws a ground shadow under the feet: not here (the water is the ground)."""
    return [[CLEAR if c[3] == 70 and c[0] == 0 and c[1] == 0 and c[2] == 0 else c for c in row] for row in rows]


def render_pose(pose_dict, sector):
    yaw = math.pi / 2 - sector * math.pi / 4
    model = hero.build(0.0, "attack", False, pose_dict)
    layers = []
    for above in (True, False):
        prims = model.transform(yaw, 0.0)
        if not pose_dict.get("dry"):
            _cut(prims, above)
        elif not above:
            layers.append([[CLEAR] * FW for _ in range(FH)])
            continue
        depth, code = hero.render(prims)
        layers.append(_strip(hero.to_pixels(depth, code)))
    points = {}
    for key in ("mouth", "ear_a", "ear_b", "hand_l", "hand_r", "neck_a", "neck_b"):
        if key in model.rig:
            points[key] = hero.project(model, yaw, model.rig[key])
    heights = [round(float(model.rig[k][1]), 2) if k in model.rig else 0.0 for k in ("hand_l", "hand_r", "mouth")]
    return layers[0], layers[1], points, heights


def _job(args):
    clip, i, sector = args
    return (clip, i, sector) + render_pose(FUNCS[clip](i), sector)


def all_jobs(clips=None):
    return [(name, i, s) for name, count, _ in CLIPS if clips is None or name in clips for i in range(count) for s in range(8)]


def run(jobs):
    with Pool() as pool:
        return pool.map(_job, jobs, chunksize=4)


# ---------------------------------------------------------------- previews
WATER = (67, 135, 128, 255)
WATER_DEEP = (45, 100, 100, 255)


def compose(above, below):
    out = [[(WATER if (x // 4 + y // 4) % 2 else (56, 120, 114, 255)) for x in range(FW)] for y in range(FH)]
    for y in range(FH):
        for x in range(FW):
            c = below[y][x]
            if c[3]:
                out[y][x] = (int(c[0] * 0.35 + WATER_DEEP[0] * 0.65), int(c[1] * 0.35 + WATER_DEEP[1] * 0.65), int(c[2] * 0.35 + WATER_DEEP[2] * 0.65), 255)
    for y in range(FH):
        for x in range(FW):
            c = above[y][x]
            if c[3]:
                out[y][x] = c
    for x in range(FW):  # the water plane, for judging
        if x % 3 == 0:
            out[WATER_ROW][x] = (255, 255, 255, 255)
    return out


def contact(path, sector=2, clip=None):
    names = [c for c in CLIPS if clip is None or c[0] == clip]
    jobs = [(name, i, sector) for name, count, _ in names for i in range(count)]
    results = run(jobs)
    k = 3
    cols = max(count for _, count, _ in names)
    W, H = cols * FW * k, len(names) * FH * k
    out = [[(30, 30, 40, 255)] * W for _ in range(H)]
    by = {(r[0], r[1]): r for r in results}
    for row, (name, count, _) in enumerate(names):
        for i in range(count):
            comp = compose(by[(name, i)][3], by[(name, i)][4])
            for y in range(FH):
                for x in range(FW):
                    c = comp[y][x]
                    for dy in range(k):
                        for dx in range(k):
                            out[row * FH * k + y * k + dy][i * FW * k + x * k + dx] = c
    write_png(Path(path), W, H, out)
    print("contact sheet written:", path)


def frames(path, clip, indices):
    jobs = [(clip, i, s) for i in indices for s in range(8)]
    by = {(r[1], r[2]): r for r in run(jobs)}
    k = 3
    W, H = len(indices) * FW * k, 8 * FH * k
    out = [[(30, 30, 40, 255)] * W for _ in range(H)]
    for col, i in enumerate(indices):
        for s in range(8):
            comp = compose(by[(i, s)][3], by[(i, s)][4])
            for y in range(FH):
                for x in range(FW):
                    c = comp[y][x]
                    for dy in range(k):
                        for dx in range(k):
                            out[s * FH * k + y * k + dy][col * FW * k + x * k + dx] = c
    write_png(Path(path), W, H, out)
    print("frames written:", path)


# ---------------------------------------------------------------- the sheets
def write_sheets():
    results = run(all_jobs())
    above = [[CLEAR] * (TOTAL * FW) for _ in range(8 * FH)]
    below = [[CLEAR] * (TOTAL * FW) for _ in range(8 * FH)]
    points = {k: [[None] * TOTAL for _ in range(8)] for k in ("mouth", "ear_a", "ear_b", "hand_l", "hand_r")}
    heights = [None] * TOTAL
    for clip, i, s, a, b, pts, h in results:
        col = STARTS[clip] + i
        for y in range(FH):
            above[s * FH + y][col * FW:(col + 1) * FW] = a[y]
            below[s * FH + y][col * FW:(col + 1) * FW] = b[y]
        for key in points:
            points[key][s][col] = pts.get(key)
        heights[col] = h
    write_png(ROOT / "characters" / "player_swim.png", TOTAL * FW, 8 * FH, above)
    write_png(ROOT / "characters" / "player_swim_under.png", TOTAL * FW, 8 * FH, below)
    # events: the frame at which a hand goes below the water (a splash) or comes out of it, per loop clip; the mouth rises above the water (a breath)
    events = {}
    for name, count, _ in CLIPS:
        start = STARTS[name]
        ev = {"enter_l": [], "enter_r": [], "exit_l": [], "exit_r": []}
        for i in range(count):
            prev = heights[start + (i - 1) % count]
            cur = heights[start + i]
            for idx, side in ((0, "l"), (1, "r")):
                if prev[idx] >= 0.0 > cur[idx]:
                    ev["enter_" + side].append(i)
                if prev[idx] < 0.0 <= cur[idx]:
                    ev["exit_" + side].append(i)
        events[name] = ev
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["swim"] = {
        "frame": [FW, FH], "water_row": WATER_ROW, "total": TOTAL,
        "clips": {name: {"start": STARTS[name], "count": count, "fps": fps} for name, count, fps in CLIPS},
        "events": events,
        "height": heights,  # per frame: left hand, right hand, mouth above (+) or below (-) the water, model units
        "points": {k: [[None if p is None else [round(p[0], 1), round(p[1], 1)] for p in row] for row in rows] for k, rows in points.items()},
    }
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("swim sheets and rig written,", TOTAL, "frames")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "contact":
        contact(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 2, sys.argv[4] if len(sys.argv) > 4 else None)
    elif len(sys.argv) > 4 and sys.argv[1] == "frame":
        frames(sys.argv[2], sys.argv[3], [int(a) for a in sys.argv[4:]])
    else:
        write_sheets()
