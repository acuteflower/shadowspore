"""Ellie's 4th and 5th sword strikes (skill upgrades AUFWAERTSHIEB and WIRBELKLINGE, data/skills.json). Same ellipsoid
renderer as every other sheet of the heroine; the existing sheets stay untouched. Her sword hand is NOT in the sheet (the game
draws the arm and the blade from the rig points); the left hand is baked in.

Block 0  Aufwaertshieb  a backhand rising cut: she starts low on her left, the blade climbs steeply across her
                        front and ends high over her right shoulder, the body leaning back into it
Block 1  Wirbelklinge   a full turn: she coils to her right, then the upper body spins through a whole circle with the blade
                        at arm's length, the coat flaring, and settles back to guard

Keys per block (like the attack sheet): 0 wind-up pose, 1-2 strike, 3 follow-through, 4-5 recovery. Every key exists once per leg
variant (0 planted, 1-6 the walk cycle's phases) so she can swing while walking.

  python3 tools/art_hero_combo.py [contact out.png <sector> [<block>]]   writes assets/characters/player_combo.png,
                                                                         player_combo_blood.png and data/hero_rig.json "combo_*"
"""
import json
import math
import sys
from pathlib import Path

import numpy as np

import art_hero3d as hero
from art_hero3d import P, FW, FH, ATTACK_LEGS, WALK_FRAMES, ATTACK_FRAMES, ROOT, paste, write_png, CLEAR, rot_y

BLOCKS = 2


def spin_hand(twist: float, y: float, side: float = -7.0, reach: float = 3.0):
    """A hand that stays at the same spot relative to the torso while the torso turns by `twist`."""
    v = rot_y(twist) @ np.array([side, y, reach])
    return (float(v[0]), float(v[1]), float(v[2]))


def spin_pose(twist, lean, pz, feet, y_r, y_l, hair, flare=0.0):
    return P(twist, lean, pz, feet, spin_hand(twist, y_r), spin_hand(twist, y_l, 5.0, -1.0), hair, flare)


STANCE = ((3.3, 3.2, 0), (-3.1, -3.8, 0))
SPIN_FEET = ((3.4, 3.6, 0), (-3.3, -3.2, 0))

COMBO_POSES = [
    # --- Aufwaertshieb: low on the left, up across the front, high over the right shoulder
    [
        P(0.70, 0.12, -0.6, STANCE, (3.0, 27.0, 7.0), (6.0, 28.5, 4.0), (-1.2, 0.4, 0.5)),
        P(0.25, 0.08, 0.4, ((3.3, 3.8, 0), (-3.1, -3.0, 0)), (-0.5, 31.0, 9.0), (5.5, 30.5, 6.5), (0.5, 0.5, -0.3)),
        P(-0.20, -0.02, 1.2, ((3.0, 4.6, 0), (-3.0, -2.4, 0.5)), (-4.5, 40.5, 7.0), (4.5, 34.0, 4.0), (1.8, 0.9, -0.6), 0.1),
        P(-0.60, -0.20, 1.5, ((3.0, 5.0, 0), (-3.0, -1.8, 1.0)), (-6.0, 47.0, 2.5), (3.5, 37.5, 2.0), (2.6, 1.2, -0.9), 0.28),
        P(-0.40, -0.10, 1.0, ((3.0, 4.2, 0), (-3.0, -1.4, 0.4)), (-6.0, 44.0, 1.5), (3.5, 36.0, 1.5), (1.0, 0.5, -0.4), 0.14),
        P(-0.05, 0.03, 0.5, ((2.8, 2.0, 0), (-2.8, 0.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (-0.4, 0.0, 0.0)),
    ],
    # --- Wirbelklinge: coil to the right, then a full turn of the upper body
    [
        spin_pose(-0.95, 0.10, -0.9, ((3.4, 3.8, 0), (-3.4, -3.6, 0)), 32.0, 33.0, (1.4, 0.4, 0.8)),
        spin_pose(0.50, 0.12, 0.0, SPIN_FEET, 33.0, 34.0, (-1.4, 0.6, -0.4), 0.15),
        spin_pose(1.90, 0.14, 0.2, SPIN_FEET, 34.0, 34.0, (-2.4, 0.8, -1.4), 0.35),
        spin_pose(3.60, 0.14, 0.2, ((3.4, 3.4, 0), (-3.3, -2.6, 1.0)), 34.0, 34.0, (-2.6, 0.9, 1.2), 0.38),
        spin_pose(5.30, 0.10, 0.0, SPIN_FEET, 33.0, 33.0, (-1.2, 0.5, 1.0), 0.2),
        P(6.38, 0.04, 0.3, ((2.8, 3.0, 0), (-2.8, -0.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.3, 0.0, 0.0)),
    ],
]


def render_frames(want_blood: bool, sectors, blocks=None):
    """[(colour pixels, blood thresholds, shoulder, hand)] for every sector row in order: block, leg variant, key."""
    hero.WANT_BLOOD = want_blood
    rows = []
    for sector in sectors:
        row = []
        for block in (range(BLOCKS) if blocks is None else blocks):
            for variant in range(ATTACK_LEGS):
                for pose in COMBO_POSES[block]:
                    if variant == 0:
                        pixels, rig = hero.frame(sector, 0.0, "attack", False, pose)
                    else:  # walking swing: the pelvis stays over the walking feet
                        pixels, rig = hero.frame(sector, (variant - 1) / WALK_FRAMES, "walk", False, dict(pose, pz=0.0))
                    row.append((pixels, hero.LAST_BLOOD if want_blood else None, rig["shoulder"], rig["hand"]))
        rows.append(row)
    hero.WANT_BLOOD = False
    return rows


def contact(out: Path, sector: int, block: int) -> None:
    cells = [c[0] for c in render_frames(False, [sector], [block])[0][:ATTACK_FRAMES]]
    sheet = [[CLEAR] * (ATTACK_FRAMES * FW) for _ in range(FH)]
    for i, fr in enumerate(cells):
        for y in range(FH):
            sheet[y][i * FW:(i + 1) * FW] = fr[y]
    write_png(out, ATTACK_FRAMES * FW, FH, sheet)


def main() -> None:
    rows = render_frames(True, range(8))
    cols = BLOCKS * ATTACK_LEGS * ATTACK_FRAMES
    write_png(ROOT / "characters" / "player_combo.png", cols * FW, 8 * FH, paste([[c[0] for c in row] for row in rows], cols, 8))
    write_png(ROOT / "characters" / "player_combo_blood.png", cols * FW, 8 * FH, paste([[c[1] for c in row] for row in rows], cols, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"combo_cols": cols, "combo_shoulder": [c[2] for row in rows for c in row], "combo_hand": [c[3] for row in rows for c in row]})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("combo sheet written", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[1] == "contact":
        contact(Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]) if len(sys.argv) > 4 else 0)
    else:
        main()
