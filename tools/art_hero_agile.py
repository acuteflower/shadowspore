#!/usr/bin/env python3
from __future__ import annotations
"""Movement 2.0 agile & transition sprite sheets for Ellie (`assets/characters/player_agile.png`).

Generates 8 genuine directions (E, SE, S, SW, W, NW, N, NE) x 43 columns of 48x56 frames:
  - cols  0.. 2 ( 3f): `start`          — Crisp forward-leaning push-off from Idle into stride (V2)
  - cols  3.. 6 ( 4f): `brake`          — Cushioned front-boot plant, knee sink & coat/hair forward whip (V2)
  - cols  7..10 ( 4f): `pivot`          — 180-degree Sprint-Pivot: outer boot braced, head/shoulders lead, hair arc (V2)
  - cols 11..16 ( 6f): `strafe_r`       — Combat lateral cross-step right, eyes locked on target (T9)
  - cols 17..22 ( 6f): `strafe_l`       — Combat lateral cross-step left, eyes locked on target (T9)
  - cols 23..24 ( 2f): `crouch_bridge`  — Smooth weight-drop bridge between standing and sneaking prowl (V9)
  - cols 25..32 ( 8f): `vault`          — One-handed palm vault over fallen logs & fences (T6, V8)
  - cols 33..42 (10f): `hop`            — Nimble 1-level cliff Ledge Hop with airborne tuck & knee-flex landing (T6, V8)

Outputs:
  - `assets/characters/player_agile.png`                      (Base Body mannequin; airborne frames omit baked ground shadow)
  - `assets/characters/player_agile_blood.png`                (Blood / bandage / 3D ArmPainter depth map)
  - `assets/characters/outfits/<style>/player_agile.png`      (All outfit styles in `art_hero_outfit.OUTFIT_IDS`)
  - `assets/characters/hair/<style>/player_agile.png`         (All hairstyles front layer)
  - `assets/characters/hair/<style>/player_agile_back.png`    (All hairstyles back layer)
  - Updates `data/hero_rig.json["agile"]`, `data/hero_arm3d.json`, and `data/hero_jewelry.json`

Usage:
  python3 tools/art_hero_agile.py [--contact /abs/path.png]
"""
import json
import math
import multiprocessing as mp
import os
import struct
import sys
import zlib
from pathlib import Path

os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")

import numpy as np

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import art_hero3d as hero  # noqa: E402
import hut_lib  # noqa: F401, E402  (keeps deterministic RAMPS indices)
import art_hero_carry_stone as _carry_stone  # noqa: F401, E402  (keeps deterministic RAMPS indices)
import art_hero_hair as hair_mod  # noqa: E402
import art_hero_outfit as outfit_mod  # noqa: E402
import art_hero_jewelry as jewelry_mod  # noqa: E402

outfit_mod.ensure_ramps(hero)
hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
FW, FH, GROUND_ROW = 48, 56, 51.0
ROOT = hero.ROOT


def _pose(
    twist: float,
    lean: float,
    pz: float,
    feet,
    hand_r,
    hand_l,
    hair,
    flare: float = 0.0,
    roll: float = 0.0,
    head_yaw: float = 0.0,
    ankles=None,
    dy: float = 0.0,
    airborne: bool = False,
) -> dict:
    p = hero.P(twist, lean, pz, feet, hand_r, hand_l, hair, flare)
    if abs(roll) > 1e-5:
        p["roll"] = roll
    if abs(head_yaw) > 1e-5:
        p["head_yaw"] = head_yaw
    if ankles is not None:
        p["ankles"] = ankles
        p["dy"] = dy
    p["airborne"] = airborne
    return p


def build_clips() -> tuple[dict, list[dict]]:
    clips_meta = {}
    all_poses: list[dict] = []

    def add_clip(name: str, fps: float, frames: list[dict]) -> None:
        clips_meta[name] = {"start": len(all_poses), "count": len(frames), "fps": fps}
        all_poses.extend(frames)

    # 1. `start` (3 frames): forward lean & crisp push-off from Idle into stride
    add_clip(
        "start",
        18.0,
        [
            _pose(0.04, 0.14, 0.6, ((2.8, 1.4, 0.0), (-2.8, -1.8, 0.6)), (-5.3, 25.0, 1.4), (5.3, 25.0, -0.6), (0.0, 0.1, -0.9), 0.06),
            _pose(-0.08, 0.23, 1.8, ((2.8, -3.0, 0.4), (-2.8, 4.4, 1.2)), (-5.2, 26.2, 2.8), (5.6, 25.8, -2.6), (0.0, 0.4, -1.8), 0.14),
            _pose(-0.04, 0.17, 1.2, ((2.8, 0.6, 0.8), (-2.8, 5.2, 0.1)), (-5.3, 25.6, 2.0), (5.4, 25.4, -1.4), (0.0, 0.3, -1.4), 0.10),
        ],
    )

    # 2. `brake` (4 frames): front boot plant, soft knee cushion, forward hair/coat whip -> calm settle
    add_clip(
        "brake",
        16.0,
        [
            _pose(0.06, -0.05, 1.5, ((3.0, 5.6, 0.0), (-3.0, -3.8, 0.3)), (-6.0, 26.4, 1.8), (6.1, 26.6, 2.2), (0.0, 0.5, -1.1), 0.18),
            _pose(
                0.04,
                0.11,
                1.0,
                (),
                (-5.8, 25.2, 2.2),
                (5.8, 25.4, 2.8),
                (0.0, 0.3, 2.1),
                0.22,
                ankles=((3.0, 2.5, 4.2), (-2.9, 2.5, -2.0)),
                dy=-1.3,
            ),
            _pose(0.02, 0.06, 0.4, ((2.9, 2.2, 0.0), (-2.8, -0.8, 0.3)), (-5.4, 24.9, 1.2), (5.4, 25.0, 1.4), (0.0, 0.1, 0.9), 0.09),
            _pose(0.0, 0.02, 0.1, ((2.7, 0.8, 0.0), (-2.7, -0.6, 0.0)), (-5.2, 24.7, 0.7), (5.2, 24.7, 0.7), (0.0, 0.0, 0.2), 0.02),
        ],
    )

    # 3. `pivot` (4 frames): 180-degree Sprint-Pivot (rendered in new heading; torso coiled back at f0, head leads!)
    add_clip(
        "pivot",
        18.0,
        [
            _pose(
                -0.82,
                -0.06,
                -0.8,
                (),
                (-6.4, 26.6, -2.2),
                (6.6, 27.4, 3.0),
                (-3.0, 0.8, 1.5),
                0.25,
                roll=0.08,
                head_yaw=0.52,
                ankles=((3.3, 2.5, -3.4), (-3.4, 2.5, 4.6)),
                dy=-1.2,
            ),
            _pose(
                -0.30,
                0.14,
                0.4,
                (),
                (-6.0, 26.4, 0.6),
                (6.2, 26.8, 0.8),
                (-2.5, 1.0, -0.8),
                0.28,
                roll=0.05,
                head_yaw=0.22,
                ankles=((3.1, 3.0, -1.0), (-3.2, 2.5, 4.0)),
                dy=-0.9,
            ),
            _pose(0.12, 0.24, 1.8, ((3.0, 4.6, 0.8), (-3.0, -3.4, 0.2)), (-5.6, 26.6, 2.4), (5.8, 26.0, -2.6), (1.1, 0.6, -2.1), 0.18),
            _pose(0.04, 0.17, 1.1, ((2.9, 5.2, 0.0), (-2.9, -2.6, 0.5)), (-5.3, 25.8, 1.6), (5.4, 25.4, -1.4), (0.4, 0.3, -1.3), 0.10),
        ],
    )

    # 4. `strafe_r` (6 frames): Combat lateral cross-step to her right (-x), eyes forward (+z)
    strafe_r = []
    sr_ankles = [
        ((2.2, 2.5, 0.6), (-4.6, 2.5, -0.4)),   # 0: right foot strike wide (-x)
        ((1.4, 3.3, 1.4), (-3.6, 2.5, -0.2)),   # 1: weight on right, left peels
        ((-0.4, 4.1, 2.2), (-2.4, 2.5, -0.4)),  # 2: left crosses in front
        ((0.4, 2.5, 1.8), (-2.8, 3.1, -0.8)),   # 3: left plants, right peels
        ((1.8, 2.5, 1.0), (-4.2, 3.9, -0.4)),   # 4: right swings out wide
        ((2.4, 2.5, 0.6), (-4.8, 2.9, -0.2)),   # 5: right prepares strike
    ]
    sr_dy = [-0.6, -0.9, -0.4, -0.7, -0.9, -0.5]
    for i in range(6):
        ph = 2.0 * math.pi * i / 6.0
        strafe_r.append(
            _pose(
                -0.22 + 0.05 * math.sin(ph),
                0.10,
                0.2,
                (),
                (-5.6, 25.6 + 0.4 * math.cos(ph), 1.4),
                (5.4, 26.0 - 0.4 * math.cos(ph), 1.8),
                (1.5, 0.3 + 0.2 * math.sin(2 * ph), -0.4),
                0.11,
                roll=-0.04,
                head_yaw=0.22,
                ankles=sr_ankles[i],
                dy=sr_dy[i],
            )
        )
    add_clip("strafe_r", 12.5, strafe_r)

    # 5. `strafe_l` (6 frames): Combat lateral cross-step to her left (+x), eyes forward (+z)
    strafe_l = []
    sl_ankles = [
        ((4.6, 2.5, -0.4), (-2.2, 2.5, 0.6)),   # 0: left foot strike wide (+x)
        ((3.6, 2.5, -0.2), (-1.4, 3.3, 1.4)),   # 1: weight on left, right peels
        ((2.4, 2.5, -0.4), (0.4, 4.1, 2.0)),    # 2: right crosses cleanly
        ((2.8, 3.1, -0.8), (-0.4, 2.5, 1.6)),   # 3: right plants, left peels
        ((4.2, 3.9, -0.4), (-1.8, 2.5, 1.0)),   # 4: left swings out wide
        ((4.8, 2.9, -0.2), (-2.4, 2.5, 0.6)),   # 5: left prepares strike
    ]
    for i in range(6):
        ph = 2.0 * math.pi * i / 6.0
        strafe_l.append(
            _pose(
                0.22 - 0.05 * math.sin(ph),
                0.10,
                0.2,
                (),
                (-5.4, 25.6 - 0.4 * math.cos(ph), 1.6),
                (5.6, 26.0 + 0.4 * math.cos(ph), 1.4),
                (-1.5, 0.3 + 0.2 * math.sin(2 * ph), -0.4),
                0.11,
                roll=0.04,
                head_yaw=-0.22,
                ankles=sl_ankles[i],
                dy=sr_dy[i],
            )
        )
    add_clip("strafe_l", 12.5, strafe_l)

    # 6. `crouch_bridge` (2 frames): Smooth standing <-> sneaking prowl bridge
    add_clip(
        "crouch_bridge",
        18.0,
        [
            _pose(
                0.02,
                0.15,
                0.4,
                (),
                (-5.2, 24.2, 1.4),
                (5.2, 24.2, 1.8),
                (0.0, 0.1, -0.4),
                0.04,
                ankles=((2.9, 2.5, 3.0), (-2.9, 2.5, -2.6)),
                dy=-1.5,
            ),
            _pose(
                0.04,
                0.26,
                0.8,
                (),
                (-5.2, 22.8, 2.2),
                (5.4, 22.8, 3.0),
                (0.0, 0.2, -0.8),
                0.07,
                ankles=((3.0, 2.5, 5.6), (-3.0, 2.5, -5.0)),
                dy=-2.9,
            ),
        ],
    )

    # 7. `vault` (8 frames): One-handed left-palm vault over fallen logs & fences
    add_clip(
        "vault",
        22.0,
        [
            _pose(0.04, 0.20, 1.0, ((2.9, 3.6, 0.0), (-2.9, -3.2, 0.5)), (-5.6, 25.6, -1.2), (4.4, 28.6, 5.6), (0.0, 0.3, -1.4), 0.12),
            _pose(-0.14, 0.30, 1.8, ((2.9, -2.2, 0.8), (-2.9, -4.8, 1.6)), (-6.0, 26.8, -2.6), (3.6, 25.8, 7.4), (0.4, 0.7, -2.2), 0.20),
            _pose(
                -0.26,
                0.32,
                1.4,
                (),
                (-6.2, 27.6, -3.0),
                (3.2, 23.4, 4.6),
                (0.8, 1.1, -2.8),
                0.30,
                roll=-0.10,
                head_yaw=0.18,
                ankles=((2.2, 7.4, -1.6), (-3.5, 8.0, -0.4)),
                dy=-0.4,
                airborne=True,
            ),
            _pose(
                -0.30,
                0.28,
                1.2,
                (),
                (-6.2, 28.0, -3.2),
                (4.4, 24.2, -1.0),
                (1.1, 1.4, -3.1),
                0.34,
                roll=-0.12,
                head_yaw=0.22,
                ankles=((1.8, 8.4, 1.8), (-3.4, 8.6, 3.2)),
                dy=-0.2,
                airborne=True,
            ),
            _pose(
                -0.12,
                0.22,
                1.4,
                (),
                (-5.8, 27.0, -1.8),
                (5.8, 27.2, -3.4),
                (0.6, 1.0, -2.4),
                0.26,
                ankles=((2.6, 5.4, -1.8), (-3.0, 4.2, 5.0)),
                dy=-0.3,
                airborne=True,
            ),
            _pose(
                -0.04,
                0.18,
                1.2,
                (),
                (-5.5, 26.0, -0.6),
                (5.6, 26.4, -1.8),
                (0.2, 0.6, -1.6),
                0.18,
                ankles=((2.8, 3.6, -3.0), (-2.9, 2.8, 5.6)),
                dy=-0.5,
                airborne=True,
            ),
            _pose(
                0.04,
                0.20,
                1.0,
                (),
                (-5.6, 25.0, 1.2),
                (5.6, 25.4, 1.8),
                (0.0, 0.2, 1.1),
                0.16,
                ankles=((2.9, 2.9, -2.4), (-2.9, 2.5, 4.6)),
                dy=-1.2,
            ),
            _pose(0.0, 0.16, 0.8, ((2.9, 2.2, 0.5), (-2.9, -1.8, 0.0)), (-5.3, 25.4, 1.4), (5.4, 25.2, -1.0), (0.0, 0.2, -1.0), 0.08),
        ],
    )

    # 8. `hop` (10 frames): Nimble 1-level cliff Ledge Hop
    add_clip(
        "hop",
        23.0,
        [
            _pose(
                0.0,
                0.18,
                0.6,
                (),
                (-5.4, 24.6, 0.4),
                (5.4, 24.6, 0.8),
                (0.0, 0.0, -0.5),
                0.06,
                ankles=((2.9, 2.5, 2.4), (-2.9, 2.5, -2.0)),
                dy=-1.0,
            ),
            _pose(0.04, 0.26, 1.6, ((2.9, 4.4, 0.8), (-2.9, -3.8, 0.6)), (-6.0, 27.2, 1.2), (6.0, 27.4, 1.6), (0.0, 0.5, -1.6), 0.16),
            _pose(
                0.04,
                0.20,
                1.2,
                (),
                (-6.4, 28.4, 1.0),
                (6.4, 28.6, 1.4),
                (0.0, 1.4, -2.2),
                0.28,
                ankles=((2.8, 6.2, 2.4), (-2.8, 5.0, -2.0)),
                dy=0.0,
                airborne=True,
            ),
            _pose(
                0.0,
                0.16,
                1.0,
                (),
                (-6.5, 28.8, 0.8),
                (6.5, 29.0, 1.2),
                (0.0, 1.8, -2.4),
                0.32,
                ankles=((2.8, 6.8, 1.8), (-2.8, 5.8, -1.4)),
                dy=0.2,
                airborne=True,
            ),
            _pose(
                -0.03,
                0.14,
                0.8,
                (),
                (-6.3, 28.2, 1.2),
                (6.3, 28.4, 1.6),
                (0.0, 1.6, -1.8),
                0.30,
                ankles=((2.9, 5.2, 2.6), (-2.9, 4.4, -1.8)),
                dy=0.0,
                airborne=True,
            ),
            _pose(
                -0.02,
                0.16,
                0.8,
                (),
                (-6.0, 27.0, 1.6),
                (6.0, 27.2, 2.0),
                (0.0, 1.1, -1.0),
                0.24,
                ankles=((3.0, 3.6, 3.2), (-3.0, 3.2, -2.0)),
                dy=-0.4,
                airborne=True,
            ),
            _pose(
                0.0,
                0.24,
                1.0,
                (),
                (-5.8, 24.4, 2.4),
                (5.8, 24.6, 2.8),
                (0.0, -0.3, 1.6),
                0.20,
                ankles=((3.2, 2.5, 3.6), (-3.2, 2.5, -2.2)),
                dy=-1.6,
            ),
            _pose(
                0.0,
                0.26,
                1.0,
                (),
                (-5.6, 23.6, 2.8),
                (5.8, 23.8, 3.2),
                (0.0, -0.5, 2.1),
                0.14,
                ankles=((3.2, 2.5, 3.4), (-3.1, 2.5, -2.0)),
                dy=-2.1,
            ),
            _pose(
                0.0,
                0.14,
                0.5,
                (),
                (-5.4, 24.4, 1.6),
                (5.4, 24.5, 1.8),
                (0.0, 0.0, 0.8),
                0.06,
                ankles=((2.9, 2.5, 2.0), (-2.9, 2.5, -1.4)),
                dy=-0.9,
            ),
            _pose(0.0, 0.04, 0.1, ((2.7, 1.0, 0.0), (-2.7, -0.8, 0.0)), (-5.2, 24.7, 0.8), (5.2, 24.7, 0.8), (0.0, 0.0, 0.2), 0.02),
        ],
    )

    return clips_meta, all_poses


CLIPS_META, ALL_POSES = build_clips()
COLS = len(ALL_POSES)
ROWS = 8


def write_array(path: Path, pixels: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    hh, ww, _ = pixels.shape
    raw = b"".join(b"\0" + pixels[y].tobytes() for y in range(hh))

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", ww, hh, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def _head_center(model: hero.Model) -> np.ndarray:
    for p in model.prims:
        if p.kind == "head":
            return p.c.copy()
    return np.zeros(3)


def _render_cell(job: tuple) -> tuple:
    sector, col, pose = job
    hero.FW, hero.FH, hero.GROUND_ROW = FW, FH, GROUND_ROW
    yaw = math.pi / 2.0 - sector * math.pi / 4.0
    shadow_on = not bool(pose.get("airborne", False))

    ref_model = hero.build(0.0, "attack", False, pose, outfit_id="default", hair_id="default")
    ref_hc = _head_center(ref_model)
    tprims = ref_model.transform(yaw, ref_model.bob)
    hero.FACE_EYES = hero.face_eyes(ref_model, yaw)
    try:
        layers = hero.render_layers(tprims, shadow=shadow_on)
    finally:
        hero.FACE_EYES = None

    # Blood + bandage + 3D ArmPainter depth map
    hero.WANT_BLOOD = True
    depth, code, bl = hero.render(tprims, yaw, ref_model.bob)
    bh_prims = [p for p in tprims if p.layer in ("body", "body_under", "prop")]
    arm_d, arm_c, _ = hero._raster_subset(bh_prims)
    blood_rows = hero.to_blood(bl, code, hero.LAST_BAND, depth, arm_d, arm_c)
    hero.WANT_BLOOD = False

    rig = {k: hero.project(ref_model, yaw, v) for k, v in ref_model.rig.items()}
    rig["jf"] = [round(float((hero.rot_y(yaw) @ v) @ hero.WHAT), 3) for v in getattr(ref_model, "facing", [])]
    arm3 = [int(round(c * 20.0)) for pt in ref_model.arm3 for c in hero.project_3d(ref_model, yaw, pt)]
    jewel = jewelry_mod.ints(rig)

    # Extra outfit styles (e.g. perlenbluete)
    outfits_bytes = {"default": np.asarray(layers["outfit"], dtype=np.uint8).tobytes()}
    b_prims = [p for p in tprims if p.layer in ("body", "body_under", "prop")]
    b_occ_prims = [p for p in tprims if p.layer in ("body", "prop")]
    b_depth, b_code, _ = hero._raster_subset(b_prims)
    b_csub = b_code.reshape(FH, hero.SS, FW, hero.SS).transpose(0, 2, 1, 3).reshape(FH, FW, hero.SS * hero.SS)
    occ_depth, _, _ = hero._raster_subset(b_occ_prims)
    k_ramps = len(hero.RAMPS) * 4

    for o_style in outfit_mod.OUTFIT_IDS:
        if o_style == "default":
            continue
        om = hero.build(0.0, "attack", False, pose, outfit_id=o_style, hair_id="default")
        delta = ref_hc - _head_center(om)
        o_only = hero.Model()
        o_only.prims = []
        for p in om.prims:
            if p.layer == "outfit":
                p.c = p.c + delta
                o_only.prims.append(p)
        ot = o_only.transform(yaw, ref_model.bob)
        if ot:
            bo_depth_occ, o_code, _ = hero._raster_subset(ot, occ_depth)
            bo_depth = np.where(o_code >= 0, bo_depth_occ, b_depth)
            bo_code = np.where(o_code >= 0, o_code, b_code)
            bo_csub = bo_code.reshape(FH, hero.SS, FW, hero.SS).transpose(0, 2, 1, 3).reshape(FH, FW, hero.SS * hero.SS)
            bo_dsub = bo_depth.reshape(FH, hero.SS, FW, hero.SS).transpose(0, 2, 1, 3).reshape(FH, FW, hero.SS * hero.SS)
            o_csub = o_code.reshape(FH, hero.SS, FW, hero.SS).transpose(0, 2, 1, 3).reshape(FH, FW, hero.SS * hero.SS)
            b_rem_csub = np.where(o_csub >= 0, -1, b_csub)
            bo_opaque = (bo_csub >= 0).sum(-1)
            bo_solid = bo_opaque >= 6
            bo_dmean = np.where(bo_csub >= 0, bo_dsub, 0.0).sum(-1) / np.maximum(bo_opaque, 1)
            best_o, w_o = hero._best_codes(o_csub, k_ramps)
            _, w_b = hero._best_codes(b_rem_csub, k_ramps)
            o_solid = bo_solid & ((o_csub >= 0).sum(-1) > 0) & (w_o >= w_b)
            best_o = np.where(o_solid, best_o, -1)
            bo_ink = hero._crease_ink(bo_dmean, bo_solid)
            o_rows = hero._rows_from_best(best_o, bo_ink, ~bo_solid)
            outfits_bytes[o_style] = np.asarray(o_rows, dtype=np.uint8).tobytes()
        else:
            outfits_bytes[o_style] = np.zeros((FH, FW, 4), dtype=np.uint8).tobytes()

    # Hairstyles (default + custom)
    hairs_bytes = {
        "default": (
            np.asarray(layers["hair_front"], dtype=np.uint8).tobytes(),
            np.asarray(layers["hair_back"], dtype=np.uint8).tobytes(),
        )
    }
    shared_hair = hero.prepare_hair_shield(tprims)
    for h_style in hair_mod.STYLE_IDS:
        if h_style == "default":
            continue
        hm = hero.build(0.0, "attack", False, pose, outfit_id="default", hair_id=h_style)
        delta_h = ref_hc - _head_center(hm)
        h_only = hero.Model()
        h_only.prims = []
        for p in hm.prims:
            if p.layer == "hair":
                p.c = p.c + delta_h
                h_only.prims.append(p)
        ht = h_only.transform(yaw, ref_model.bob)
        if ht:
            hf_r, hb_r = hero.raster_hair_pair(ht, shared_hair)
            hairs_bytes[h_style] = (
                np.asarray(hf_r, dtype=np.uint8).tobytes(),
                np.asarray(hb_r, dtype=np.uint8).tobytes(),
            )
        else:
            z = np.zeros((FH, FW, 4), dtype=np.uint8).tobytes()
            hairs_bytes[h_style] = (z, z)

    return (
        sector,
        col,
        np.asarray(layers["body"], dtype=np.uint8).tobytes(),
        np.asarray(blood_rows, dtype=np.uint8).tobytes(),
        outfits_bytes,
        hairs_bytes,
        rig["shoulder"],
        rig["hand"],
        arm3,
        jewel,
    )


def _composite_preview(body: np.ndarray, outfit: np.ndarray, hf: np.ndarray, hb: np.ndarray) -> np.ndarray:
    out = hb.copy()
    b_mask = body[..., 3] > 0
    out[b_mask] = body[b_mask]
    o_mask = outfit[..., 3] > 0
    out[o_mask] = outfit[o_mask]
    hf_mask = hf[..., 3] > 0
    out[hf_mask] = hf[hf_mask]
    return out


def main() -> None:
    contact_out: Path | None = None
    if "--contact" in sys.argv:
        idx = sys.argv.index("--contact")
        if idx + 1 < len(sys.argv):
            contact_out = Path(sys.argv[idx + 1])

    jobs = [(s, c, ALL_POSES[c]) for s in range(ROWS) for c in range(COLS)]
    workers = min(8, os.cpu_count() or 1)
    print(f"Rendering player_agile ({COLS}x{ROWS} = {len(jobs)} frames + all outfits/hairs) with {workers} workers...", flush=True)

    body_sheet = np.zeros((ROWS * FH, COLS * FW, 4), dtype=np.uint8)
    blood_sheet = np.zeros((ROWS * FH, COLS * FW, 4), dtype=np.uint8)
    outfit_sheets = {st: np.zeros((ROWS * FH, COLS * FW, 4), dtype=np.uint8) for st in ("default",) + tuple(outfit_mod.OUTFIT_IDS)}
    hair_f_sheets = {st: np.zeros((ROWS * FH, COLS * FW, 4), dtype=np.uint8) for st in ("default",) + tuple(hair_mod.STYLE_IDS)}
    hair_b_sheets = {st: np.zeros((ROWS * FH, COLS * FW, 4), dtype=np.uint8) for st in ("default",) + tuple(hair_mod.STYLE_IDS)}

    shoulders = [None] * (ROWS * COLS)
    hands = [None] * (ROWS * COLS)
    arm3_cells = [None] * (ROWS * COLS)
    jewel_cells = [None] * (ROWS * COLS)

    with mp.Pool(workers) as pool:
        for s, c, b_bytes, bl_bytes, o_dict, h_dict, sh, ha, a3, jw in pool.imap_unordered(_render_cell, jobs, chunksize=4):
            y0, x0 = s * FH, c * FW
            body_sheet[y0 : y0 + FH, x0 : x0 + FW] = np.frombuffer(b_bytes, dtype=np.uint8).reshape(FH, FW, 4)
            blood_sheet[y0 : y0 + FH, x0 : x0 + FW] = np.frombuffer(bl_bytes, dtype=np.uint8).reshape(FH, FW, 4)
            for st, ob in o_dict.items():
                outfit_sheets[st][y0 : y0 + FH, x0 : x0 + FW] = np.frombuffer(ob, dtype=np.uint8).reshape(FH, FW, 4)
            for st, (hfb, hbb) in h_dict.items():
                hair_f_sheets[st][y0 : y0 + FH, x0 : x0 + FW] = np.frombuffer(hfb, dtype=np.uint8).reshape(FH, FW, 4)
                hair_b_sheets[st][y0 : y0 + FH, x0 : x0 + FW] = np.frombuffer(hbb, dtype=np.uint8).reshape(FH, FW, 4)
            flat_i = s * COLS + c
            shoulders[flat_i] = sh
            hands[flat_i] = ha
            arm3_cells[flat_i] = a3
            jewel_cells[flat_i] = jw

    chars_dir = ROOT / "characters"
    write_array(chars_dir / "player_agile.png", body_sheet)
    write_array(chars_dir / "player_agile_blood.png", blood_sheet)
    for st, arr in outfit_sheets.items():
        write_array(chars_dir / "outfits" / st / "player_agile.png", arr)
    for st in hair_f_sheets:
        write_array(chars_dir / "hair" / st / "player_agile.png", hair_f_sheets[st])
        write_array(chars_dir / "hair" / st / "player_agile_back.png", hair_b_sheets[st])

    # Update hero_rig.json
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig_data = json.loads(rig_path.read_text())
    rig_data["agile"] = {
        "cols": COLS,
        "rows": ROWS,
        "clips": CLIPS_META,
        "shoulder": shoulders,
        "hand": hands,
    }
    rig_path.write_text(json.dumps(rig_data, separators=(",", ":")) + "\n")

    # Update hero_arm3d.json
    arm3_path = ROOT.parent / "data" / "hero_arm3d.json"
    if arm3_path.exists():
        arm3_data = json.loads(arm3_path.read_text())
        flat_arm3 = [val for cell in arm3_cells for val in cell]
        arm3_data.setdefault("sheets", {})["player_agile.png"] = {
            "cols": COLS,
            "rows": ROWS,
            "data": flat_arm3,
        }
        arm3_path.write_text(json.dumps(arm3_data, separators=(",", ":")) + "\n")

    # Update hero_jewelry.json
    jewel_path = ROOT.parent / "data" / "hero_jewelry.json"
    if jewel_path.exists():
        jewel_data = json.loads(jewel_path.read_text())
        flat_jewel = [val for cell in jewel_cells for val in cell]
        jewel_data.setdefault("sheets", {})["agile"] = {
            "cols": COLS,
            "rows": ROWS,
            "data": flat_jewel,
        }
        jewel_path.write_text(json.dumps(jewel_data, separators=(",", ":")) + "\n")

    if contact_out is not None:
        comp = _composite_preview(
            body_sheet,
            outfit_sheets["default"],
            hair_f_sheets["default"],
            hair_b_sheets["default"],
        )
        # Render a 2x scaled dark-backdrop contact sheet of key sectors (E=0, SE=1, S=2, W=4, N=6) for crisp inspection
        pick_rows = [0, 1, 2, 4, 6]
        strip = np.zeros((len(pick_rows) * FH, COLS * FW, 4), dtype=np.uint8)
        strip[..., :3] = (20, 16, 32)
        strip[..., 3] = 255
        for ri, sec in enumerate(pick_rows):
            cell_slice = comp[sec * FH : (sec + 1) * FH, :, :]
            alpha = cell_slice[..., 3:4].astype(np.float32) / 255.0
            bg = strip[ri * FH : (ri + 1) * FH, :, :3].astype(np.float32)
            blended = cell_slice[..., :3].astype(np.float32) * alpha + bg * (1.0 - alpha)
            strip[ri * FH : (ri + 1) * FH, :, :3] = np.clip(blended, 0, 255).astype(np.uint8)
        zoom = np.repeat(np.repeat(strip, 2, axis=0), 2, axis=1)
        write_array(contact_out, zoom)

    print("player_agile sheets, cosmetics, blood/depth, arm3d, jewelry and rig updated.", flush=True)


if __name__ == "__main__":
    main()
