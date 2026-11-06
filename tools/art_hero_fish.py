"""Ellie fishing: the body animations of the rod (docs/fishing.md). Eight views, one sheet of clips.

OPENBLAS_NUM_THREADS=1 python3 tools/art_hero_fish.py [workers]        writes player_fish.png, player_fish_blood.png, hero_rig.json "fish"
python3 tools/art_hero_fish.py sheet out.png [sector]                  contact sheet of one view (all clips), quick check

Like the sword, the rod and her right arm are NOT in the sheet: the game draws the arm from `shoulder` to `hand` and
holds the rod there. Per frame the rig also carries `rod` = [forward, side, lift] (how the rod points relative to where she
faces; side > 0 = her right, lift = how high), so the rod's whip in the cast, its strain in a fight and its droop after a
lost fish come from the same keys as her body. Her left hand is baked: it balances in the cast and cranks the reel.

Clips (frames, fps, loop): ready, cast, strike, flee, brace, reel, land, snap, sag. `cast` releases at RELEASE (the game waits
that long before the float flies, settings.cast.windup)."""
import json
import math
import multiprocessing as mp
import os
import sys

import numpy as np

import art_hero3d as h
from art_hero_rebuild import write_array

R0, L0 = (-4.2, 28.5, 7.5), (-0.8, 27.0, 6.0)  # right hand on the grip, left hand at the reel
READY_ROD = (0.8, 0.25, 0.5)
WIDE = ((3.0, 4.0, 0), (-3.0, -3.0, 0))
STAND = h.STAND


def K(t, twist=0.05, lean=0.04, pz=0.0, feet=STAND, right=R0, left=L0, hair=(0.0, 0.0, 0.0), flare=0.0, rod=READY_ROD):
    return (t, h.P(twist, lean, pz, feet, right, left, hair, flare), rod)


def reel_loop(n=8):
    keys = []
    for i in range(n + 1):
        ph = 2 * math.pi * i / n
        left = (-1.0, 27.0 + 2.3 * math.sin(ph), 6.2 + 2.3 * math.cos(ph))
        keys.append(K(i / n, twist=0.05 + 0.02 * math.sin(ph), lean=-0.12 + 0.015 * math.sin(ph), pz=-0.3 + 0.2 * math.sin(ph + 1.0), feet=WIDE,
                      right=(-4.3, 30.5 + 0.3 * math.sin(ph), 7.0), left=left, hair=(0.2 * math.sin(ph), 0.1, -0.2), rod=(0.55, 0.25, 0.95 + 0.04 * math.sin(ph))))
    return keys


def flee_loop():
    sway = [(-0.16, -0.6), (-0.24, -1.2), (-0.10, 0.1), (-0.21, -0.9), (-0.16, -0.6)]
    keys = []
    for i, (lean, pz) in enumerate(sway):
        keys.append(K(i / 4, twist=0.05, lean=lean, pz=pz, feet=WIDE, right=(-4.5, 33.0 - 0.8 * (i % 2), 6.0), left=(-0.5 + 3.0 * (i % 2), 30.5, 5.0),
                      hair=(1.0 * (i % 2) - 0.5, 0.2, -0.9 + 0.8 * (i % 2)), flare=0.1, rod=(0.45, 0.25 + 0.05 * (i % 2), 1.0)))
    return keys


CLIPS = {
    # name: (frames, fps, loop, keys)
    "ready": (6, 5, True, [K(0.0), K(0.5, lean=0.07, hair=(0.3, 0.2, -0.2), right=(-4.2, 28.2, 7.8), rod=(0.8, 0.25, 0.55)), K(1.0)]),
    "cast": (14, 20, False, [
        K(0.00),
        K(0.18, twist=-0.2, lean=-0.08, pz=-0.2, right=(-6.0, 33.0, 1.0), left=(1.5, 29.0, 5.0), hair=(-0.4, 0.2, 0.3), rod=(0.2, 0.35, 0.9)),
        K(0.38, twist=-0.55, lean=-0.2, pz=-0.8, feet=((3.0, 3.0, 0), (-3.0, -3.5, 0)), right=(-6.5, 42.0, -5.5), left=(3.5, 33.0, 7.0), hair=(-1.6, 0.3, 1.2), flare=0.1, rod=(-0.7, 0.3, 1.15)),
        K(0.45, twist=0.0, lean=0.1, pz=0.6, feet=((3.0, 4.2, 0), (-3.0, -2.5, 0.3)), right=(-4.5, 39.0, 4.0), left=(2.0, 31.0, 4.0), hair=(-0.6, 0.4, 0.4), rod=(0.3, 0.2, 1.1)),
        K(0.52, twist=0.25, lean=0.3, pz=1.8, feet=((3.0, 5.5, 0), (-3.0, -1.5, 0.6)), right=(-3.0, 33.0, 12.5), left=(1.5, 29.0, 5.0), hair=(1.8, 0.8, -1.4), flare=0.18, rod=(1.0, 0.1, 0.45)),
        K(0.68, twist=0.12, lean=0.24, pz=1.5, feet=((3.0, 5.5, 0), (-3.0, -1.2, 0)), right=(-3.2, 29.5, 11.5), left=(-0.5, 27.5, 7.0), hair=(1.0, 0.4, -0.6), flare=0.1, rod=(0.95, 0.1, 0.05)),
        K(1.00, lean=0.06, pz=0.2, feet=((3.0, 4.0, 0), (-3.0, -1.0, 0))),
    ]),
    "strike": (6, 24, False, [
        K(0.00),
        K(0.35, twist=-0.12, lean=-0.22, pz=-0.4, right=(-4.5, 38.0, 4.0), left=(2.0, 31.0, 3.0), hair=(-0.9, 0.3, 0.7), flare=0.1, rod=(0.35, 0.25, 1.15)),
        K(0.70, lean=-0.1, right=(-4.5, 34.0, 6.0), hair=(0.4, 0.1, -0.3), rod=(0.45, 0.25, 1.05)),
        K(1.00, lean=-0.14, pz=-0.5, feet=WIDE, right=(-4.5, 33.0, 6.0), left=(-0.5, 30.5, 5.0), rod=(0.45, 0.25, 1.0)),
    ]),
    "flee": (8, 14, True, flee_loop()),
    "brace": (4, 10, True, [
        K(0.0, lean=-0.25, pz=-0.9, feet=((3.2, 4.0, 0), (-3.2, -3.4, 0)), right=(-4.5, 31.0, 5.5), left=(-0.8, 29.0, 5.0), flare=0.06, rod=(0.4, 0.25, 1.05)),
        K(0.5, lean=-0.27, pz=-1.0, feet=((3.2, 4.0, 0), (-3.2, -3.4, 0)), right=(-4.6, 31.2, 5.4), left=(-0.8, 29.2, 5.0), hair=(0.3, 0.2, -0.3), flare=0.07, rod=(0.4, 0.27, 1.07)),
        K(1.0, lean=-0.25, pz=-0.9, feet=((3.2, 4.0, 0), (-3.2, -3.4, 0)), right=(-4.5, 31.0, 5.5), left=(-0.8, 29.0, 5.0), flare=0.06, rod=(0.4, 0.25, 1.05)),
    ]),
    "reel": (8, 12, True, reel_loop()),
    "land": (12, 16, False, [
        K(0.00, lean=-0.12, pz=-0.3, feet=WIDE, right=(-4.3, 30.5, 7.0), left=(-1.0, 27.0, 8.5), rod=(0.55, 0.25, 0.95)),
        K(0.25, twist=-0.1, lean=-0.3, pz=-0.9, feet=WIDE, right=(-4.5, 42.0, 3.0), left=(-1.0, 36.0, 4.0), hair=(-1.0, 0.3, 0.8), flare=0.14, rod=(0.2, 0.3, 1.2)),
        K(0.50, twist=0.0, lean=-0.18, pz=-0.4, feet=WIDE, right=(-4.0, 40.0, 5.0), left=(2.0, 37.0, 6.0), hair=(0.8, 0.5, -0.4), flare=0.1, rod=(0.35, 0.3, 1.15)),
        K(0.80, lean=0.0, right=(-3.5, 33.0, 8.0), left=(-0.8, 29.0, 6.5), rod=(0.7, 0.2, 0.8)),
        K(1.00),
    ]),
    "snap": (10, 16, False, [
        K(0.00, lean=-0.16, pz=-0.6, feet=WIDE, right=(-4.5, 33.0, 6.0), left=(-0.5, 30.5, 5.0), rod=(0.45, 0.25, 1.0)),
        K(0.15, twist=-0.2, lean=-0.38, pz=-1.8, feet=((3.0, 2.0, 0.4), (-3.0, -5.5, 0)), right=(-6.0, 41.0, -1.0), left=(5.0, 36.0, 2.0), hair=(-1.6, 0.5, 1.4), flare=0.2, rod=(-0.3, 0.4, 1.2)),
        K(0.40, twist=0.0, lean=-0.12, pz=-0.8, feet=((3.0, 3.0, 0), (-3.0, -4.0, 0)), right=(-5.0, 33.0, 3.0), left=(3.0, 31.0, 4.0), hair=(0.6, 0.3, -0.5), flare=0.1, rod=(0.2, 0.3, 0.9)),
        K(0.70, lean=0.12, pz=0.0, right=(-4.5, 27.5, 6.5), left=(-0.8, 26.5, 5.5), hair=(0.9, 0.1, -0.4), rod=(0.7, 0.25, 0.45)),
        K(1.00, lean=0.06, right=(-4.3, 28.0, 7.0), rod=(0.75, 0.25, 0.4)),
    ]),
    "sag": (8, 10, False, [
        K(0.00),
        K(0.30, twist=0.1, lean=0.18, pz=0.2, right=(-4.5, 25.5, 6.5), left=(-1.0, 24.5, 5.5), hair=(0.8, 0.1, -0.5), rod=(0.65, 0.25, 0.25)),
        K(0.65, twist=0.08, lean=0.15, right=(-4.5, 25.8, 6.5), left=(-1.0, 24.8, 5.5), hair=(0.3, 0.1, -0.2), rod=(0.65, 0.25, 0.3)),
        K(1.00),
    ]),
}
RELEASE = 7  # the cast clip's frame in which the float leaves the rod


def timeline(keys, t):
    for (t0, a, ra), (t1, b, rb) in zip(keys, keys[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            k = k * k * (3 - 2 * k)
            return h.lerp_pose(a, b, k), tuple(float(x) * (1 - k) + float(y) * k for x, y in zip(ra, rb))
    return keys[-1][1], keys[-1][2]


def layout():
    """[(clip, frame index)] in sheet order, and each clip's first column."""
    order, starts, col = [], {}, 0
    for name, (n, _fps, _loop, _keys) in CLIPS.items():
        starts[name] = col
        order += [(name, i) for i in range(n)]
        col += n
    return order, starts


def sample(name, i):
    n, _fps, loop, keys = CLIPS[name]
    t = i / n if loop else i / (n - 1)
    return timeline(keys, t)


def render_job(job):
    sector, col, name, i = job
    h.WANT_BLOOD = True
    pose, rod = sample(name, i)
    pixels, rig = h.frame(sector, 0.0, "attack", False, pose)
    return sector, col, np.asarray(pixels, dtype=np.uint8).tobytes(), np.asarray(h.LAST_BLOOD, dtype=np.uint8).tobytes(), rig, rod


def sheet_preview(path, sector):
    from PIL import Image
    order, _ = layout()
    cols = len(order)
    img = Image.new("RGBA", (cols * h.FW, h.FH), (62, 125, 86, 255))
    h.WANT_BLOOD = False
    for col, (name, i) in enumerate(order):
        pose, _rod = sample(name, i)
        pixels, _rig = h.frame(sector, 0.0, "attack", False, pose)
        im = Image.new("RGBA", (h.FW, h.FH))
        for y, row in enumerate(pixels):
            for x, px in enumerate(row):
                im.putpixel((x, y), tuple(px))
        img.alpha_composite(im, (col * h.FW, 0))
    per_row = 12
    rows = (cols + per_row - 1) // per_row
    out = Image.new("RGBA", (per_row * h.FW * 2, rows * h.FH * 2), (62, 125, 86, 255))
    for r in range(rows):
        part = img.crop((r * per_row * h.FW, 0, min((r + 1) * per_row, cols) * h.FW, h.FH)).resize((min(per_row, cols - r * per_row) * h.FW * 2, h.FH * 2), Image.NEAREST)
        out.paste(part, (0, r * h.FH * 2))
    out.save(path)


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        sheet_preview(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0)
        return
    order, starts = layout()
    cols = len(order)
    shape = (8 * h.FH, cols * h.FW, 4)
    color, blood = np.zeros(shape, np.uint8), np.zeros(shape, np.uint8)
    hands, shoulders, rods = [None] * (8 * cols), [None] * (8 * cols), [None] * cols
    workers = int(sys.argv[1]) if len(sys.argv) > 1 else min(6, os.cpu_count() or 1)
    jobs = [(s, c, name, i) for s in range(8) for c, (name, i) in enumerate(order)]
    print(f"Rendering {len(jobs)} fishing frames with {workers} workers", flush=True)
    with mp.Pool(workers) as pool:
        for done, (s, col, px, bl, rig, rod) in enumerate(pool.imap_unordered(render_job, jobs, chunksize=2), 1):
            for dest, data in ((color, px), (blood, bl)):
                dest[s * h.FH:(s + 1) * h.FH, col * h.FW:(col + 1) * h.FW] = np.frombuffer(data, dtype=np.uint8).reshape(h.FH, h.FW, 4)
            hands[s * cols + col], shoulders[s * cols + col] = rig["hand"], rig["shoulder"]
            rods[col] = [round(v, 3) for v in rod]
            if done % 100 == 0:
                print(f"{done}/{len(jobs)}", flush=True)
    assert all(p is not None for p in hands + shoulders + rods)
    write_array(h.ROOT / "characters" / "player_fish.png", color)
    write_array(h.ROOT / "characters" / "player_fish_blood.png", blood)
    path = h.ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(path.read_text())
    rig["fish"] = {"cols": cols, "release": RELEASE, "hand": hands, "shoulder": shoulders, "rod": rods,
                   "clips": {name: {"start": starts[name], "count": CLIPS[name][0], "fps": CLIPS[name][1], "loop": CLIPS[name][2]} for name in CLIPS}}
    path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("Fishing sheets, masks and rig written", flush=True)


if __name__ == "__main__":
    main()
