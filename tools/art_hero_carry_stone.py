"""Ellie carries a moonstone of the star mirror (Sternenspiegel, docs/raetsel_konzept.md 6b): she stoops and lifts it, walks with it held before her
chest in both hands, and sets it down again (the lift played backwards). All eight facings, the stone baked into the frames (optional pose keys
`rock`, `rock_r`, `rock_mat` of art_hero3d.py), the same poses as the board of tools/art_hero_carry.py.
  python3 tools/art_hero_carry_stone.py      writes assets/characters/player_carry_stone.png (8 rows E SE S SW W NW N NE, LIFT + WALK columns,
                                             frames of the emerge format, feet as player_carry.png) and data/hero_rig.json "carry_stone"."""
import json
import math
from pathlib import Path

import art_hero_emerge as em
import art_hero3d as hero
from gen_art import CLEAR, ROOT, hexc, write_png

Q = em.Q
LIFT, WALK = 8, 8
FPS_LIFT, FPS_WALK = 12, 10
MOON = len(hero.RAMPS)
hero.RAMPS.append([hexc(c) for c in ["3a3858", "6a6890", "a6a4c8", "e2e0f4"]])  # the moonstone: the pale violet stone, a little lighter


def pose(lean, dy, legs, hand_y, hand_z, droop=0.0):
    return dict(Q(lean=lean, pz=1.0, dy=dy, legs=legs, hand_l=(4.0, hand_y, hand_z), hand_r=(-4.0, hand_y, hand_z), droop=droop),
                rock=(0.0, hand_y + 0.6, hand_z + 2.4), rock_r=4.2, rock_mat=MOON)


LIFT_KEYS = [
    pose(0.62, -4.5, ((0.9, 1.5), (0.7, 1.3)), 6.5, 12.5, 2.0),
    pose(0.58, -4.0, ((0.85, 1.45), (0.65, 1.25)), 7.5, 12.5, 2.0),
    pose(0.52, -3.2, ((0.75, 1.35), (0.55, 1.15)), 10.0, 12.0, 2.0),
    pose(0.44, -2.4, ((0.6, 1.2), (0.45, 1.0)), 13.0, 11.0, 1.5),
    pose(0.34, -1.6, ((0.45, 0.95), (0.35, 0.8)), 16.0, 10.2, 1.2),
    pose(0.24, -0.9, ((0.3, 0.7), (0.25, 0.6)), 18.5, 9.6, 1.0),
    pose(0.14, -0.3, ((0.18, 0.45), (0.14, 0.4)), 20.0, 9.2, 0.8),
    pose(0.1, 0.0, ((0.08, 0.2), (0.06, 0.2)), 21.0, 9.0, 0.6),
]


def walk_pose(i):
    ph = 2 * math.pi * i / WALK
    t_r = 0.5 * math.sin(ph)
    t_l = 0.5 * math.sin(ph + math.pi)
    f_r = 0.12 + 0.7 * max(0.0, math.cos(ph))
    f_l = 0.12 + 0.7 * max(0.0, math.cos(ph + math.pi))
    bob = 0.35 * abs(math.sin(ph))
    return pose(0.12, bob - 0.3, ((t_r, f_r), (t_l, f_l)), 21.0 + bob, 9.0, 0.6)


WALK_KEYS = [walk_pose(i) for i in range(WALK)]


def main():
    W, H = hero.FW, hero.FH
    rows = []
    for sector in range(8):
        em.SECTOR = sector
        rows.append([em.render_frame(p, False) for p in LIFT_KEYS + WALK_KEYS])
        print("sector", sector, "done", flush=True)
    n = LIFT + WALK
    sheet = [[CLEAR] * (n * W) for _ in range(8 * H)]
    for r, frames in enumerate(rows):
        for i, fr in enumerate(frames):
            for y in range(H):
                sheet[r * H + y][i * W:(i + 1) * W] = fr[y]
    write_png(ROOT / "characters" / "player_carry_stone.png", n * W, 8 * H, sheet)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["carry_stone"] = {"lift": LIFT, "walk": WALK, "lift_fps": FPS_LIFT, "walk_fps": FPS_WALK, "frame": [W, H]}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("carry stone sheet written", W, H)


if __name__ == "__main__":
    main()
