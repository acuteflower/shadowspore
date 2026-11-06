"""Ellie carries the old board away from the cabin's door (story: day 2, the lumberjack's cabin): she stoops and lifts the plank, walks with it held in both hands, and sets it down again.
Side views in separate east and west rows. The plank is baked into the frames (optional pose keys `plank`, `plank_tilt`, `plank_len`, `plank_mat`
of art_hero3d.py), in the cabin's weathered boards.
  python3 tools/art_hero_carry.py [sheet out.png]   writes assets/characters/player_carry.png and data/hero_rig.json "carry"
Frames: LIFT (stoop .. standing with the plank), WALK (a loop of carrying steps), the way back down is LIFT played backwards."""
import json
import math
import sys
from pathlib import Path

import art_hero_emerge as em
import art_hero3d as hero
import hut_lib  # noqa: F401  adds the wood ramps (PLANK_W) to the palette
from gen_art import CLEAR, ROOT, write_png

Q = em.Q
LIFT, WALK = 8, 8
FPS_LIFT, FPS_WALK = 12, 10
PLANK = dict(plank_len=30, plank_mat=hut_lib.PLANK_W)


def pose(lean, dy, legs, lh, rh, plank, tilt, droop=0.0):
    return dict(Q(lean=lean, pz=1.0, dy=dy, legs=legs, hand_l=lh, hand_r=rh, droop=droop), plank=plank, plank_tilt=tilt, **PLANK)


# stooped at the board's end, hands low, the plank on the ground in front ... upright, the plank held at the hip
LIFT_KEYS = [
    pose(0.62, -4.5, ((0.9, 1.5), (0.7, 1.3)), (2.8, 9.0, 13.0), (-2.8, 9.0, 13.0), (0.0, 7.5, 20.0), -0.02, 2.0),
    pose(0.58, -4.0, ((0.85, 1.45), (0.65, 1.25)), (2.8, 10.0, 13.0), (-2.8, 10.0, 13.0), (0.0, 8.5, 20.0), -0.05, 2.0),
    pose(0.52, -3.2, ((0.75, 1.35), (0.55, 1.15)), (2.8, 12.0, 12.5), (-2.8, 12.0, 12.5), (0.0, 11.0, 19.5), -0.1, 2.0),
    pose(0.44, -2.4, ((0.6, 1.2), (0.45, 1.0)), (2.8, 15.0, 11.5), (-2.8, 15.0, 11.5), (0.0, 14.0, 19.0), -0.15, 1.5),
    pose(0.34, -1.6, ((0.45, 0.95), (0.35, 0.8)), (2.8, 18.0, 10.5), (-2.8, 18.0, 10.5), (0.0, 17.5, 18.0), -0.18, 1.2),
    pose(0.24, -0.9, ((0.3, 0.7), (0.25, 0.6)), (2.8, 20.5, 10.0), (-2.8, 20.5, 10.0), (0.0, 20.5, 17.0), -0.15, 1.0),
    pose(0.14, -0.3, ((0.18, 0.45), (0.14, 0.4)), (2.8, 22.0, 9.5), (-2.8, 22.0, 9.5), (0.0, 22.5, 16.0), -0.1, 0.8),
    pose(0.1, 0.0, ((0.08, 0.2), (0.06, 0.2)), (2.8, 23.0, 9.2), (-2.8, 23.0, 9.2), (0.0, 23.5, 15.5), -0.08, 0.6),
]


def walk_pose(i):
    ph = 2 * math.pi * i / WALK
    t_r = 0.5 * math.sin(ph)
    t_l = 0.5 * math.sin(ph + math.pi)
    f_r = 0.12 + 0.7 * max(0.0, math.cos(ph))
    f_l = 0.12 + 0.7 * max(0.0, math.cos(ph + math.pi))
    bob = 0.35 * abs(math.sin(ph))
    return pose(0.1, bob - 0.3, ((t_r, f_r), (t_l, f_l)), (2.8, 23.0 + bob, 9.2), (-2.8, 23.0 + bob, 9.2), (0.0, 23.5 + bob, 15.5), -0.08 + 0.02 * math.sin(ph), 0.6)


WALK_KEYS = [walk_pose(i) for i in range(WALK)]


def frames():
    return [em.render_frame(p, False) for p in LIFT_KEYS + WALK_KEYS]


def main():
    frs = frames()
    W, H = hero.FW, hero.FH
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        sheet, rows_n = em.sheet_pixels(frs, 8)
        k = 3
        out = [[(62, 125, 86, 255)] * (8 * W * k) for _ in range(rows_n * H * k)]
        for y, row in enumerate(sheet):
            for x, px in enumerate(row):
                if px[3]:
                    for dy in range(k):
                        for dx in range(k):
                            out[y * k + dy][x * k + dx] = px
        write_png(Path(sys.argv[2]), 8 * W * k, rows_n * H * k, out)
        return
    em.SECTOR = 4
    west = frames()
    sheet = [[CLEAR] * (len(frs) * W) for _ in range(2 * H)]
    for row, facing in enumerate((frs, west)):
        for i, fr in enumerate(facing):
            for y in range(H):
                sheet[row * H + y][i * W:(i + 1) * W] = fr[y]
    write_png(ROOT / "characters" / "player_carry.png", len(frs) * W, 2 * H, sheet)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["carry"] = {"lift": LIFT, "walk": WALK, "lift_fps": FPS_LIFT, "walk_fps": FPS_WALK}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("carry sheet written")


if __name__ == "__main__":
    main()
