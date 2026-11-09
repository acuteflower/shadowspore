"""Ellie's heavy blow (right mouse button with the sword: "Wuchtschlag"). Same ellipsoid renderer as every other sheet of the heroine.
Her sword hand is NOT in the sheet (the game draws the arm and the blade from the rig points); the left hand is baked in and follows the grip.

Keys (one pose each, the game blends between them by `AttackComponent.heavy_key()`):
  0 guard         the stance she starts the draw from            \\
  1 draw          the blade comes up over the right shoulder      |  charging: key = draw * 2 + power
  2 drawn         hands overhead, weight back                     |
  3 strain        fully charged: leaning back, the hair flies up /
  4 apex          the instant before the blow: arched back, hands highest
  5 chop          the blade falls through the middle, the body drops into the step
  6 impact        deep lunge, hands low on her left, the whole body behind the blow
  7 rebound       the blow bites, a small rebound
  8 recover       she draws the blade back up out of the ground
  9 settle        back to the guard
Every key exists once per leg variant (0 planted, 1-6 the walk cycle's phases) like the attack sheet, so she can walk (slowly) while she charges.

  python3 tools/art_hero_heavy.py [contact out.png <sector>]   writes assets/characters/player_heavy.png, player_heavy_blood.png and data/hero_rig.json "heavy_*"
"""
import json
import sys
from pathlib import Path

import art_hero3d as hero
from art_hero3d import P, FW, FH, ATTACK_LEGS, WALK_FRAMES, ROOT, paste, write_png, CLEAR

KEYS = 10
GUARD_FEET = ((3.0, 3.0, 0), (-3.0, -3.0, 0))
BACK_FEET = ((3.2, 2.0, 0), (-3.2, -4.5, 0))  # weight on the rear (right) foot
LUNGE_FEET = ((3.4, 8.5, 0), (-3.2, -4.0, 0))  # left foot far forward, the right pushes

# (twist, lean, pz, feet, hand_r, hand_l, hair, flare); hand_l follows the grip: a little toward the pommel
HEAVY_POSES = [
    P(-0.10, 0.03, 0.0, GUARD_FEET, (-4.5, 28.0, 4.0), (-1.2, 27.0, 4.2), (0.0, 0.0, 0.0)),
    P(-0.30, -0.08, -0.5, ((3.1, 2.4, 0), (-3.1, -3.8, 0)), (-5.2, 36.0, 1.5), (-2.0, 34.0, 2.4), (0.8, 0.3, 0.2), 0.04),
    P(-0.50, -0.20, -1.4, BACK_FEET, (-4.8, 45.5, -1.8), (-2.2, 43.5, -0.4), (1.2, 0.8, 0.6), 0.08),
    P(-0.55, -0.30, -1.8, BACK_FEET, (-5.2, 47.2, -2.8), (-2.5, 45.0, -1.2), (1.6, 1.1, 0.9), 0.12),
    P(-0.60, -0.36, -2.2, BACK_FEET, (-5.6, 48.0, -3.6), (-2.8, 45.8, -2.0), (1.9, 1.3, 1.1), 0.14),
    P(0.00, 0.22, 1.6, ((3.3, 6.0, 0), (-3.2, -4.4, 0)), (-0.2, 38.5, 5.5), (2.4, 37.0, 5.0), (-1.4, 0.3, -1.0), 0.18),
    P(0.45, 0.36, 3.2, LUNGE_FEET, (4.2, 27.0, 9.5), (6.6, 26.0, 9.0), (-0.9, 0.5, -0.5), 0.14),
    P(0.42, 0.32, 3.0, LUNGE_FEET, (4.4, 28.0, 9.0), (6.8, 27.0, 8.5), (-0.6, 0.4, -0.3), 0.12),
    P(0.28, 0.24, 2.0, ((3.2, 6.0, 0), (-3.2, -4.0, 0)), (1.6, 29.0, 6.4), (4.2, 28.0, 6.0), (-0.4, 0.3, -0.2), 0.10),
    P(0.10, 0.10, 0.7, ((3.0, 4.0, 0), (-3.0, -2.5, 0)), (-3.0, 26.5, 3.6), (0.4, 25.8, 3.6), (0.3, 0.1, 0.0), 0.03),
]


def render_frames(want_blood: bool, sectors):
    """[(colour pixels, blood thresholds, shoulder, hand)] for every sector row in order: variant-major, key-minor."""
    hero.WANT_BLOOD = want_blood
    rows = []
    for sector in sectors:
        row = []
        for variant in range(ATTACK_LEGS):
            for pose in HEAVY_POSES:
                if variant == 0:
                    pixels, rig = hero.frame(sector, 0.0, "attack", False, pose)
                else:  # walking while she charges: the pelvis stays over the walking feet
                    pixels, rig = hero.frame(sector, (variant - 1) / WALK_FRAMES, "walk", False, dict(pose, pz=0.0))
                row.append((pixels, hero.LAST_BLOOD if want_blood else None, rig["shoulder"], rig["hand"]))
        rows.append(row)
    hero.WANT_BLOOD = False
    return rows


def contact(out: Path, sector: int) -> None:
    cells = [c[0] for c in render_frames(False, [sector])[0][:KEYS]]
    sheet = [[CLEAR] * (5 * FW) for _ in range(2 * FH)]
    for i, fr in enumerate(cells):
        r, c = divmod(i, 5)
        for y in range(FH):
            sheet[r * FH + y][c * FW:(c + 1) * FW] = fr[y]
    write_png(out, 5 * FW, 2 * FH, sheet)


def main() -> None:
    rows = render_frames(True, range(8))
    cols = KEYS * ATTACK_LEGS
    write_png(ROOT / "characters" / "player_heavy.png", cols * FW, 8 * FH, paste([[c[0] for c in row] for row in rows], cols, 8))
    write_png(ROOT / "characters" / "player_heavy_blood.png", cols * FW, 8 * FH, paste([[c[1] for c in row] for row in rows], cols, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"heavy_keys": KEYS, "heavy_variants": ATTACK_LEGS,
                "heavy_shoulder": [c[2] for row in rows for c in row], "heavy_hand": [c[3] for row in rows for c in row]})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("heavy sheet written", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[1] == "contact":
        contact(Path(sys.argv[2]), int(sys.argv[3]))
    else:
        main()
