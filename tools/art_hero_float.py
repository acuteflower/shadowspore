#!/usr/bin/env python3
"""Zero-gravity floating animation sheet generator for Ellie in Caelia's interstellar sanctuary
(docs/caelia_interstellar_konzept.md). Uses the exact 3D ellipsoid model & palette of `tools/art_hero3d.py`.

Generates:
  - assets/characters/player_float.png       (56 cols x 8 rows of 64x64 frames, 8 real facings E..NE)
  - assets/characters/player_float_blood.png (matching blood/bandage threshold sheet)
  - data/hero_rig.json["float"]              (clip layout, anchor, rig points)

Usage:
  py -3 tools/art_hero_float.py                         writes sheets + rig JSON
  py -3 tools/art_hero_float.py contact out.png [sec]   writes 3x zoomed contact sheet over deep space
"""
from __future__ import annotations

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

FW, FH = 64, 64
CENTER_ROW = 34.0
hero.FW, hero.FH = FW, FH
hero.GROUND_ROW = CENTER_ROW

CLIPS: list[tuple[str, int, int]] = [
    ("float_idle", 8, 6),
    ("drift", 8, 8),
    ("glide", 8, 10),
    ("brake", 6, 10),
    ("arrive", 10, 9),
    ("standby", 16, 8),
]
STARTS: dict[str, int] = {}
_cursor = 0
for _cname, _ccnt, _cfps in CLIPS:
    STARTS[_cname] = _cursor
    _cursor += _ccnt
TOTAL = _cursor


def _pose(
    pitch: float = 0.06,
    lift: float = 0.0,
    lean: float = 0.0,
    twist: float = 0.0,
    roll: float = 0.0,
    legs: tuple[tuple[float, float], tuple[float, float]] = ((0.34, 0.68), (-0.12, 0.24)),
    hl: tuple[float, float, float] = (8.8, 25.0, 2.2),
    hr: tuple[float, float, float] = (-8.4, 24.0, 1.4),
    hair: tuple[float, float, float] = (0.0, 4.4, -1.6),
    droop: float = -0.8,
    spread: float = 1.75,
    curl: float = 1.25,
    flare: float = 0.95,
    head_yaw: float = 0.0,
    nod: float = 0.0,
    pole_l: tuple[float, float, float] = (0.85, -0.45, -0.35),
    pole_r: tuple[float, float, float] = (-0.85, -0.45, -0.35),
    eyes_closed: float = 0.0,
) -> dict:
    """Zero-G key pose: pelvis sits at model y = 0 (mapped to CENTER_ROW in 64x64)."""
    # Slight non-zero pitch triggers art_hero3d's level-shift branch cleanly
    eff_pitch = pitch if abs(pitch) > 1e-3 else 0.002
    d = em.Q(
        twist=twist,
        lean=lean,
        pz=0.0,
        dy=0.0,
        pitch=eff_pitch,
        shift=(0.0, -24.0 + lift, 0.0),
        legs=legs,
        hand_l=hl,
        hand_r=hr,
        hair=hair,
        droop=droop,
        flare=flare,
        pole_l=pole_l,
        pole_r=pole_r,
        eyes_closed=eyes_closed,
    )
    d["level"] = True
    d["head_yaw"] = head_yaw
    d["spread"] = spread
    d["curl"] = curl
    if abs(nod) > 1e-4:
        d["nod"] = nod
    if abs(roll) > 1e-4:
        d["roll"] = roll
    return d


def _wave_hair(u: float, lift_y: float, stream_z: float, sway_x: float = 1.1) -> tuple[float, float, float]:
    s = TAU * u
    return (
        sway_x * math.sin(s),
        lift_y + 1.0 * math.sin(s + 0.8),
        stream_z + 0.85 * math.cos(s - 0.5),
    )


TAU = 2.0 * math.pi


def clip_float_idle(i: int, n: int = 8) -> dict:
    """Serene weightless hovering: one knee softly tucked, arms loosely balanced, hair fanned gracefully."""
    u = i / n
    s = TAU * u
    c = math.cos(s)
    sn = math.sin(s)
    legs = (
        (0.52 + 0.12 * sn, 0.96 + 0.16 * c),
        (-0.18 + 0.10 * math.sin(s + 1.4), 0.30 + 0.12 * math.cos(s + 1.4)),
    )
    hl = (10.4 + 1.0 * sn, 27.5 + 1.6 * c, 3.0 + 0.9 * sn)
    hr = (-10.0 - 0.9 * math.sin(s + 0.9), 26.2 + 1.5 * math.cos(s + 0.9), 2.4 + 0.8 * c)
    return _pose(
        pitch=0.09 + 0.04 * sn,
        lift=1.4 * sn,
        lean=0.04 + 0.03 * c,
        twist=0.07 * sn,
        roll=0.05 * c,
        legs=legs,
        hl=hl,
        hr=hr,
        hair=_wave_hair(u, lift_y=1.9, stream_z=-2.2, sway_x=1.45),
        droop=-0.6,
        spread=1.95,
        curl=1.35,
        flare=1.20 + 0.24 * sn,
        head_yaw=0.09 * math.sin(s),
        nod=-0.04 * c,
    )


def clip_drift(i: int, n: int = 8) -> dict:
    """Relaxed weightless cruising forward (~28 deg tilt), trailing legs & streaming silk hair."""
    u = i / n
    s = TAU * u
    sn = math.sin(s)
    c = math.cos(s)
    legs = (
        (-0.24 + 0.13 * sn, 0.36 + 0.15 * c),
        (0.02 + 0.13 * math.sin(s + math.pi), 0.72 + 0.16 * math.cos(s + math.pi)),
    )
    hl = (10.2 + 0.9 * sn, 24.5 + 1.2 * c, -1.6 + 0.8 * sn)
    hr = (-9.8 - 0.9 * sn, 23.8 + 1.2 * math.cos(s + 0.7), -2.2 + 0.8 * c)
    return _pose(
        pitch=0.46 + 0.04 * sn,
        lift=0.9 * sn,
        lean=0.05,
        twist=0.06 * c,
        legs=legs,
        hl=hl,
        hr=hr,
        hair=_wave_hair(u, lift_y=0.4, stream_z=-3.8, sway_x=1.05),
        droop=-0.2,
        spread=1.55,
        curl=1.20,
        flare=1.45 + 0.24 * sn,
        nod=-0.30 - 0.04 * sn,
    )


def clip_glide(i: int, n: int = 8) -> dict:
    """Sleek fast Shift Boost-Glide (~49 deg star-flight, readable in all 8 directions!), hair streaming behind."""
    u = i / n
    s = TAU * u
    sn = math.sin(s)
    c = math.cos(s)
    legs = (
        (-0.22 + 0.08 * sn, 0.18 + 0.09 * c),
        (-0.04 + 0.08 * math.sin(s + math.pi), 0.42 + 0.11 * math.cos(s + math.pi)),
    )
    # Sleek aerodynamic arms swept smoothly outward-back along her sides
    hl = (9.4 + 0.6 * c, 19.2 + 0.9 * sn, -4.4 + 0.6 * c)
    hr = (-9.4 - 0.6 * c, 19.2 - 0.9 * sn, -4.4 - 0.6 * c)
    return _pose(
        pitch=0.84 + 0.04 * sn,
        lift=0.5 * sn,
        lean=-0.08,
        twist=0.04 * sn,
        legs=legs,
        hl=hl,
        hr=hr,
        hair=_wave_hair(u, lift_y=-1.6, stream_z=-5.4, sway_x=0.85),
        droop=0.1,
        spread=1.35,
        curl=1.25,
        flare=1.75 + 0.25 * sn,
        nod=-0.56 - 0.03 * sn,
        pole_l=(0.9, -0.25, -0.65),
        pole_r=(-0.9, -0.25, -0.65),
    )


def clip_brake(i: int, n: int = 6) -> dict:
    """Expressive zero-G deceleration / counter-thrust: lean back, legs forward, hair sweeping softly ahead."""
    u = i / n
    s = TAU * u
    sn = math.sin(s)
    c = math.cos(s)
    legs = (
        (0.66 + 0.08 * sn, 0.78 + 0.10 * c),
        (0.46 + 0.08 * c, 0.48 + 0.09 * sn),
    )
    hl = (12.0 + 0.8 * sn, 30.2 + 1.0 * c, 4.6 + 0.6 * sn)
    hr = (-11.8 - 0.8 * c, 29.4 + 1.0 * sn, 4.4 + 0.6 * c)
    return _pose(
        pitch=-0.28 + 0.04 * sn,
        lift=0.6 * c,
        lean=-0.10,
        twist=0.06 * sn,
        legs=legs,
        hl=hl,
        hr=hr,
        hair=_wave_hair(u, lift_y=2.2, stream_z=2.8, sway_x=1.45),
        droop=-0.9,
        spread=2.05,
        curl=1.30,
        flare=1.35,
        nod=0.14,
    )


def clip_arrive(i: int, n: int = 10) -> dict:
    """One-shot lift-off when arriving in space: feet leave gravity, hair blooms out, glances at hands -> idle 0."""
    u = i / max(n - 1, 1)
    idle0 = clip_float_idle(0)
    if i == n - 1:
        return idle0
    k = 0.5 - 0.5 * math.cos(math.pi * min(1.0, u * 1.15))
    wonder = math.sin(math.pi * min(1.0, max(0.0, (u - 0.25) / 0.60)))
    legs = (
        (0.04 + 0.48 * k, 0.06 + 0.90 * k),
        (0.02 - 0.20 * k, 0.06 + 0.24 * k),
    )
    hl = (5.2 + 5.2 * k - 1.4 * wonder, 16.5 + 11.0 * k + 5.2 * wonder, 1.5 + 1.5 * k + 5.5 * wonder)
    hr = (-5.2 - 4.8 * k + 1.8 * wonder, 16.5 + 9.7 * k + 4.8 * wonder, 1.5 + 0.9 * k + 6.0 * wonder)
    return _pose(
        pitch=0.02 + 0.07 * k - 0.06 * wonder,
        lift=-3.5 * (1.0 - k) + 1.8 * wonder,
        lean=0.04 * k + 0.08 * wonder,
        twist=0.10 * wonder,
        legs=legs,
        hl=hl,
        hr=hr,
        hair=(0.4 * wonder, 0.2 + 1.7 * k + 1.0 * wonder, -0.4 - 1.8 * k),
        droop=0.4 - 1.0 * k,
        spread=0.35 + 1.60 * k + 0.30 * wonder,
        curl=0.35 + 1.00 * k,
        flare=0.25 + 0.95 * k,
        head_yaw=-0.22 * wonder,
        nod=0.20 * wonder,
    )


def clip_standby(i: int, n: int = 16) -> dict:
    """Gentle zero-G curiosity gesture: reaches softly toward a passing star mote, looks around, returns to idle 0."""
    u = i / n
    s = TAU * u
    env = math.sin(math.pi * u) ** 1.35
    reach = math.sin(math.pi * max(0.0, min(1.0, (u - 0.14) / 0.66))) ** 1.2
    legs = (
        (0.52 + 0.14 * env, 0.96 + 0.16 * env),
        (-0.18 - 0.12 * env, 0.30 + 0.16 * math.sin(s)),
    )
    hl = (10.4 + 1.2 * env, 27.5 + 2.0 * env, 3.0 + 1.2 * env)
    hr = (
        -10.0 - 2.4 * reach,
        26.2 + 9.8 * reach,
        2.4 + 8.6 * reach,
    )
    return _pose(
        pitch=0.09 - 0.10 * env,
        lift=1.8 * env + 0.8 * math.sin(s),
        lean=0.04 + 0.06 * reach,
        twist=-0.24 * reach,
        roll=-0.08 * env,
        legs=legs,
        hl=hl,
        hr=hr,
        hair=(1.4 * math.sin(s), 1.9 + 1.2 * env, -2.2 - 0.8 * reach),
        droop=-0.7,
        spread=1.95 + 0.30 * env,
        curl=1.35,
        flare=1.20 + 0.25 * env,
        head_yaw=-0.34 * reach + 0.14 * math.sin(s),
        nod=-0.16 * reach,
    )


FUNCS = {
    "float_idle": clip_float_idle,
    "drift": clip_drift,
    "glide": clip_glide,
    "brake": clip_brake,
    "arrive": clip_arrive,
    "standby": clip_standby,
}


def _strip_shadow(rows: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    """Removes the baked dark ground shadow ellipse — zero-G space has no floor."""
    return [
        [CLEAR if (c[3] == 70 and c[0] == 0 and c[1] == 0 and c[2] == 0) else c for c in row]
        for row in rows
    ]


def _render_one(args: tuple[str, int, int]):
    clip, idx, sector = args
    pose_dict = FUNCS[clip](idx)
    yaw = math.pi / 2.0 - sector * math.pi / 4.0
    model = hero.build(0.0, "attack", False, pose_dict)
    prims = model.transform(yaw, 0.0)
    # Render color + exact blood threshold map in one pass
    depth, code, blood = hero.render(prims, yaw=yaw, dy=0.0)
    hero.FACE_EYES = hero.face_eyes(model, yaw)
    pix = _strip_shadow(hero.to_pixels(depth, code))
    hero.FACE_EYES = None
    bl_rows = hero.to_blood(blood, code, hero.LAST_BAND)
    pts: dict[str, list[float] | None] = {}
    for key in ("mouth", "ear_a", "ear_b", "neck_a", "neck_b", "hand_l", "hand_r"):
        if key in model.rig:
            px, py = hero.project(model, yaw, model.rig[key])
            pts[key] = [round(float(px), 1), round(float(py), 1)]
        else:
            pts[key] = None
    return clip, idx, sector, pix, bl_rows, pts


def _all_jobs(only_clips: list[str] | None = None) -> list[tuple[str, int, int]]:
    return [
        (name, i, s)
        for name, count, _ in CLIPS
        if only_clips is None or name in only_clips
        for i in range(count)
        for s in range(8)
    ]


def write_sheets() -> None:
    jobs = _all_jobs()
    with Pool() as pool:
        results = pool.map(_render_one, jobs, chunksize=4)

    color_sheet = [[CLEAR] * (TOTAL * FW) for _ in range(8 * FH)]
    blood_sheet = [[(255, 255, 255, 0)] * (TOTAL * FW) for _ in range(8 * FH)]
    points: dict[str, list[list[list[float] | None]]] = {
        k: [[None] * TOTAL for _ in range(8)]
        for k in ("mouth", "ear_a", "ear_b", "neck_a", "neck_b", "hand_l", "hand_r")
    }

    for clip, idx, sec, pix, bl_rows, pts in results:
        col = STARTS[clip] + idx
        for y in range(FH):
            color_sheet[sec * FH + y][col * FW : (col + 1) * FW] = pix[y]
            blood_sheet[sec * FH + y][col * FW : (col + 1) * FW] = bl_rows[y]
        for k in points:
            points[k][sec][col] = pts.get(k)

    out_color = ROOT / "characters" / "player_float.png"
    out_blood = ROOT / "characters" / "player_float_blood.png"
    write_png(out_color, TOTAL * FW, 8 * FH, color_sheet)
    write_png(out_blood, TOTAL * FW, 8 * FH, blood_sheet)

    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text(encoding="utf-8"))
    rig["float"] = {
        "frame": [FW, FH],
        "center_row": CENTER_ROW,
        "total": TOTAL,
        "clips": {name: {"start": STARTS[name], "count": count, "fps": fps} for name, count, fps in CLIPS},
        "points": points,
    }
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {out_color}, {out_blood}, and hero_rig.json['float'] ({TOTAL} cols x 8 rows)")


def write_contact(out_path: str, sector: int = 1) -> None:
    """Renders a 3x zoomed contact sheet of all clips in one sector + an 8-direction turnaround strip."""
    jobs = [(name, i, sector) for name, count, _ in CLIPS for i in range(count)]
    jobs += [("float_idle", 0, s) for s in range(8)]
    jobs += [("glide", 2, s) for s in range(8)]
    with Pool() as pool:
        results = pool.map(_render_one, jobs, chunksize=4)

    by = {(r[0], r[1], r[2]): r[3] for r in results}
    k = 3
    cols = max(max(c for _, c, _ in CLIPS), 8)
    rows_n = len(CLIPS) + 2
    W, H = cols * FW * k, rows_n * FH * k
    bg0, bg1 = (10, 8, 24, 255), (16, 13, 34, 255)
    canvas = [[bg0 if ((x // 12 + y // 12) % 2 == 0) else bg1 for x in range(W)] for y in range(H)]

    def blit(pix, r_idx: int, c_idx: int) -> None:
        for y in range(FH):
            for x in range(FW):
                px = pix[y][x]
                if px[3]:
                    for dy in range(k):
                        for dx in range(k):
                            canvas[r_idx * FH * k + y * k + dy][c_idx * FW * k + x * k + dx] = px

    for r_i, (name, count, _) in enumerate(CLIPS):
        for i in range(count):
            blit(by[(name, i, sector)], r_i, i)
    for s in range(8):
        blit(by[("float_idle", 0, s)], len(CLIPS), s)
        blit(by[("glide", 2, s)], len(CLIPS) + 1, s)

    p = Path(out_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    write_png(p, W, H, canvas)
    print("Contact sheet written:", p)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "contact":
        sec = int(sys.argv[3]) if len(sys.argv) >= 4 else 1
        write_contact(sys.argv[2], sec)
    else:
        write_sheets()
