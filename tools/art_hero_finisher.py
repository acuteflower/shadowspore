#!/usr/bin/env python3
from __future__ import annotations
"""Combat V2 Finisher sprite sheets for Ellie (`assets/characters/player_finisher.png`).

Generates 8 genuine directions (E, SE, S, SW, W, NW, N, NE) x 24 columns of 48x56 frames for Move #1 ("Abgrund-Pfähler",
docs/finisher_v2_konzept.md). Airborne frames (2..5) omit the baked ground shadow; the game lifts the sprite itself.
  - clip `impale_down` (cols 0..19):
      *  0..2:  crouch / anticipation, take-off (2 = feet leave the ground, arms rising)
      *  3..4:  apex hang: both hands on the hilt high above the head, reverse grip, blade straight down (3 ~ 4, a held drift)
      *  5..6:  plunge; 6 = impact, feet planted, hilt driven down at waist height in front of her
      *  7..10: grinding second press on the pommel (10 = deepest)
      * 11..12: brace / coil before the rip (weight back, knees bent)
      * 13..15: explosive rip-out in a rising diagonal arc (15 = sword hand high above / behind the right shoulder)
      * 16..19: settle back into the combat guard
  - clip `impale_flick` (cols 20..23): alternative ending after 15 (story flag): wrist snap that flicks the blade down and
    out to her side (chiburi), 23 = relaxed low ready stance, sword hand low at her side

Outputs:
  - `assets/characters/player_finisher.png`                 (Base Body mannequin; airborne frames omit baked ground shadow)
  - `assets/characters/player_finisher_blood.png`           (Blood / bandage / 3D ArmPainter depth map)
  - `assets/characters/outfits/<style>/player_finisher.png` (All outfit styles in `art_hero_outfit.OUTFIT_IDS`)
  - `assets/characters/hair/<style>/player_finisher.png`    (All hairstyles front layer)
  - `assets/characters/hair/<style>/player_finisher_back.png` (All hairstyles back layer)
  - Updates `data/hero_rig.json["finisher"]`, `data/hero_arm3d.json`, and `data/hero_jewelry.json`

Usage:
  python3 tools/art_hero_finisher.py [--contact /abs/path.png]
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
    **extra: float,
) -> dict:
    p = hero.P(twist, lean, pz, feet, hand_r, hand_l, hair, flare)
    p.update(extra)  # optional hair shaping: spread / curl / droop / pitch
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

    # Hand targets are model space (x: + = her left, y: height, z: + = forward / strike direction). The sword is drawn by the
    # game at `hand_r` (the grip); in the apex / impact / press frames `hand_l` sits on the same hilt just below or beside it.
    # Every target stays inside the 12.6 arm reach so the painted arm (hero_arm3d) really ends at the hilt.
    GROUND = 2.5
    add_clip(
        "impale_down",
        16.0,
        [
            # --- 0..2: crouch / anticipation and take-off ---
            _pose(  # 0: settle into the crouch, hilt held low at her right hip
                -0.18, 0.14, 0.6, (),
                (-4.4, 30.5, 3.2), (-0.8, 29.5, 3.6),
                (0.3, 0.1, -0.8), 0.08, head_yaw=0.12,
                ankles=((2.9, GROUND, 2.8), (-2.9, GROUND, -2.4)), dy=-1.4,
            ),
            _pose(  # 1: deepest load, knees bent, both hands start to lift the hilt
                -0.12, 0.24, 1.0, (),
                (-3.2, 32.2, 6.4), (-0.2, 31.6, 6.6),
                (0.3, 0.6, -1.4), 0.12, head_yaw=0.08,
                ankles=((3.0, GROUND, 3.0), (-3.0, GROUND, -2.6)), dy=-2.6,
            ),
            _pose(  # 2: take-off, toes leave the ground, arms rising past the face
                -0.06, -0.02, 1.4, (),
                (-2.2, 42.6, 3.4), (0.4, 41.6, 3.8),
                (0.2, 1.8, -1.8), 0.24, head_yaw=0.04,
                ankles=((2.8, 4.2, 1.6), (-2.9, 3.4, -1.8)), dy=0.4,
                airborne=True,
            ),
            # --- 3..4: apex hang (reverse grip, blade straight down in front of her) ---
            _pose(  # 3: both hands stacked on the hilt high above the head, knees tucked, hair floating up
                0.0, -0.02, 1.8, (),
                (-1.0, 49.6, 3.0), (0.3, 48.0, 3.3),
                (0.2, 6.0, -0.8), 0.30,
                ankles=((2.9, 7.2, 3.6), (-2.9, 6.4, 1.0)), dy=0.4,
                airborne=True, spread=0.35,
            ),
            _pose(  # 4: the same hold with a tiny drift (the game holds here ~0.14 s)
                0.0, -0.02, 1.85, (),
                (-1.0, 49.7, 3.1), (0.3, 48.1, 3.4),
                (0.3, 6.6, -0.6), 0.32,
                ankles=((2.9, 7.5, 3.7), (-2.9, 6.7, 1.1)), dy=0.4,
                airborne=True, spread=0.40,
            ),
            # --- 5..6: plunge and impact ---
            _pose(  # 5: driving down, legs reaching for the ground, hair whipped up by the fall
                0.06, 0.24, 2.4, (),
                (-0.6, 38.4, 9.4), (0.6, 37.0, 9.6),
                (-0.1, 7.0, 0.6), 0.36, head_yaw=-0.02,
                ankles=((3.1, 4.4, 4.4), (-3.0, 3.6, -2.4)), dy=-0.4,
                airborne=True, spread=0.30,
            ),
            _pose(  # 6: impact, feet planted wide, both hands drive the hilt down at waist height in front of her
                0.10, 0.30, 3.3, (),
                (-0.4, 27.2, 12.0), (0.6, 25.8, 12.2),
                (-0.3, -0.2, 2.4), 0.26, roll=-0.04, head_yaw=-0.06,
                ankles=((3.2, GROUND, 6.2), (-3.1, GROUND, -4.2)), dy=-1.8,
            ),
            # --- 7..10: grinding second press, her weight on the pommel ---
            _pose(  # 7
                0.14, 0.34, 3.5, (),
                (-0.4, 26.4, 12.2), (0.9, 26.8, 12.0),
                (-0.3, 0.0, 1.8), 0.18, roll=-0.06, head_yaw=-0.08,
                ankles=((3.2, GROUND, 6.3), (-3.1, GROUND, -4.3)), dy=-2.0,
            ),
            _pose(  # 8
                0.20, 0.38, 3.8, (),
                (-0.3, 25.2, 12.3), (1.0, 25.6, 12.1),
                (-0.5, -0.3, 2.2), 0.20, roll=-0.08, head_yaw=-0.12,
                ankles=((3.3, GROUND, 6.6), (-3.1, GROUND, -4.4)), dy=-2.3,
            ),
            _pose(  # 9
                0.24, 0.41, 4.0, (),
                (-0.3, 24.0, 12.3), (1.0, 24.4, 12.1),
                (-0.7, -0.4, 2.4), 0.18, roll=-0.10, head_yaw=-0.15,
                ankles=((3.4, GROUND, 6.8), (-3.2, GROUND, -4.5)), dy=-2.6,
            ),
            _pose(  # 10: deepest press, shoulders hunched over the hilt
                0.27, 0.44, 4.2, (),
                (-0.3, 23.0, 12.2), (1.0, 23.4, 12.0),
                (-0.8, -0.5, 2.6), 0.16, roll=-0.11, head_yaw=-0.18,
                ankles=((3.4, GROUND, 6.9), (-3.2, GROUND, -4.6)), dy=-2.8,
            ),
            # --- 11..12: brace / coil before the rip (weight back, knees bent, the hilt stays in the wound) ---
            _pose(  # 11
                0.18, 0.24, 2.6, (),
                (-0.5, 24.0, 10.6), (1.0, 24.6, 10.4),
                (-0.2, 0.2, 0.8), 0.12, roll=-0.04, head_yaw=-0.10,
                ankles=((3.4, GROUND, 5.6), (-3.2, GROUND, -4.6)), dy=-2.9,
            ),
            _pose(  # 12: fully coiled, right shoulder wound forward, weight on the back leg
                0.24, 0.16, 1.8, (),
                (-0.6, 24.6, 9.6), (0.9, 25.2, 9.4),
                (0.2, 0.4, -0.4), 0.10, roll=0.02, head_yaw=-0.14,
                ankles=((3.4, GROUND, 5.0), (-3.2, GROUND, -4.8)), dy=-3.2,
            ),
            # --- 13..15: explosive rip-out, rising diagonal arc up and back over her right shoulder ---
            _pose(  # 13: tearing free, the left hand lets go
                -0.10, 0.10, 1.8, ((3.3, 4.8, 0.0), (-3.2, -4.6, 0.0)),
                (-2.4, 28.0, 9.4), (4.6, 28.6, 5.0),
                (0.9, 0.6, -1.0), 0.24, roll=0.04, head_yaw=0.06,
            ),
            _pose(  # 14: the blade rises past her chest, body uncoiling
                -0.44, -0.06, 1.2, ((3.2, 4.4, 0.2), (-3.2, -4.4, 0.0)),
                (-5.4, 38.4, 5.2), (6.4, 30.0, 1.8),
                (2.0, 1.2, -1.6), 0.32, roll=0.08, head_yaw=0.26,
            ),
            _pose(  # 15: sword hand high above and behind her right shoulder, left arm thrown out for balance
                -0.70, -0.16, 0.4, ((3.1, 4.2, 0.4), (-3.2, -4.2, 0.0)),
                (-6.2, 47.6, -2.6), (7.6, 32.4, -2.8),
                (3.2, 1.6, -2.2), 0.36, roll=0.12, head_yaw=0.46,
            ),
            # --- 16..19: settle back into the combat guard ---
            _pose(  # 16
                -0.54, -0.10, 0.4, ((3.0, 3.8, 0.0), (-3.0, -3.6, 0.0)),
                (-7.4, 40.2, -1.6), (7.0, 30.0, -2.0),
                (2.6, 1.0, -1.6), 0.24, roll=0.08, head_yaw=0.36,
            ),
            _pose(  # 17
                -0.36, -0.04, 0.4, ((3.0, 3.2, 0.0), (-3.0, -2.8, 0.0)),
                (-7.4, 32.6, -0.6), (6.6, 28.6, -1.2),
                (1.8, 0.6, -1.0), 0.16, roll=0.05, head_yaw=0.26,
            ),
            _pose(  # 18
                -0.18, 0.02, 0.4, ((2.9, 2.4, 0.0), (-2.9, -1.9, 0.0)),
                (-6.0, 27.4, 0.8), (5.6, 26.4, -0.4),
                (0.9, 0.3, -0.4), 0.08, head_yaw=0.12,
            ),
            _pose(  # 19: combat guard
                -0.04, 0.02, 0.2, ((2.8, 1.4, 0.0), (-2.8, -1.2, 0.0)),
                (-5.2, 25.0, 1.2), (5.2, 25.0, 0.6),
                (0.2, 0.0, 0.0), 0.02,
            ),
        ],
    )
    # Alternative ending (story flag `rescued`): played instead of 16..19, straight from the high rip pose (15).
    add_clip(
        "impale_flick",
        16.0,
        [
            _pose(  # 20: wrist cocks, the hand comes forward over the shoulder (blade raised, ready to snap)
                -0.46, -0.06, 0.6, ((3.1, 4.0, 0.2), (-3.1, -3.8, 0.0)),
                (-5.4, 43.4, 2.6), (6.8, 30.6, -1.8),
                (2.4, 1.2, -1.4), 0.28, roll=0.08, head_yaw=0.30,
            ),
            _pose(  # 21: the snap, arm whips down and out to her right side
                -0.12, 0.06, 0.6, ((3.1, 3.6, 0.0), (-3.2, -3.6, 0.0)),
                (-8.6, 31.0, 3.6), (5.8, 28.4, -0.8),
                (-0.6, 0.8, 0.6), 0.30, roll=-0.04, head_yaw=0.06,
            ),
            _pose(  # 22: hard stop, arm extended low and out (ichor flies off the tip)
                0.04, 0.10, 0.5, ((3.0, 3.2, 0.0), (-3.2, -3.2, 0.0)),
                (-9.0, 27.4, 2.0), (5.2, 27.2, 0.2),
                (-1.2, 0.2, 1.0), 0.18, roll=-0.05, head_yaw=-0.04,
            ),
            _pose(  # 23: relaxed low ready, sword hand low at her side, the blade pointing out and down
                -0.02, 0.06, 0.3, ((2.9, 2.6, 0.0), (-3.1, -2.6, 0.0)),
                (-7.6, 25.8, 1.4), (4.8, 26.6, 0.6),
                (-0.3, 0.0, 0.3), 0.06, head_yaw=0.02,
            ),
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
    print(f"Rendering player_finisher ({COLS}x{ROWS} = {len(jobs)} frames + all outfits/hairs) with {workers} workers...", flush=True)

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
    write_array(chars_dir / "player_finisher.png", body_sheet)
    write_array(chars_dir / "player_finisher_blood.png", blood_sheet)
    for st, arr in outfit_sheets.items():
        write_array(chars_dir / "outfits" / st / "player_finisher.png", arr)
    for st in hair_f_sheets:
        write_array(chars_dir / "hair" / st / "player_finisher.png", hair_f_sheets[st])
        write_array(chars_dir / "hair" / st / "player_finisher_back.png", hair_b_sheets[st])

    # Update hero_rig.json
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig_data = json.loads(rig_path.read_text())
    rig_data["finisher"] = {
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
        arm3_data.setdefault("sheets", {})["player_finisher.png"] = {
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
        jewel_data.setdefault("sheets", {})["finisher"] = {
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
        pick_rows = list(range(ROWS))
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
        # Debug twin (`<name>_rig.png`): the game-drawn sword arm as a gold shoulder->hand line, the grip (rig hand) as a cyan dot.
        dbg = strip.copy()
        for ri, sec in enumerate(pick_rows):
            for c in range(COLS):
                sx, sy = shoulders[sec * COLS + c]
                hx, hy = hands[sec * COLS + c]
                ox, oy = c * FW + FW // 2, ri * FH + int(GROUND_ROW)  # rig points are feet-relative
                n = int(max(abs(hx - sx), abs(hy - sy))) + 1
                for k in range(n + 1):
                    t = k / max(n, 1)
                    px, py = int(round(ox + sx + (hx - sx) * t)), int(round(oy + sy + (hy - sy) * t))
                    if 0 <= px < dbg.shape[1] and 0 <= py < dbg.shape[0]:
                        dbg[py, px, :3] = (230, 196, 104)
                px, py = int(round(ox + hx)), int(round(oy + hy))
                if 0 < px < dbg.shape[1] and 0 < py < dbg.shape[0]:
                    dbg[py - 1 : py + 1, px - 1 : px + 1, :3] = (120, 244, 230)
        dzoom = np.repeat(np.repeat(dbg, 2, axis=0), 2, axis=1)
        write_array(contact_out.with_name(contact_out.stem + "_rig.png"), dzoom)

    print("player_finisher sheets, cosmetics, blood/depth, arm3d, jewelry and rig updated.", flush=True)


if __name__ == "__main__":
    main()
