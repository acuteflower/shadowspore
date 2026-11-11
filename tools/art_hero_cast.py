"""Ellie casts with a magic staff (docs/magie_konzept.md). Same ellipsoid renderer as every other sheet of the heroine.
Her staff hand (right) is NOT in the sheet: the game draws the arm and the staff from the rig points (AttackComponent) and turns the staff
along Player.STAFF_KEYS; the left hand is baked in.

Five clips of 12 frames each (light, root, ember, veil, maw), legs planted (she stands still while she casts), played in 0.8 s (data/spells.json `cast`):
  light  BANNLICHT  she draws the staff in to her chest, the left hand cupping the crown, rears up and lifts it high over her head
                    (arched back, the free hand thrown open to the sky), then drops onto one knee and strikes the butt on the ground
                    in front of her (the light opens at 0.525 of the clip), the free hand flung out flat over the ground; she holds, rises.
  root   WURZELGRUND she turns away and draws the staff back over her right shoulder, the left palm out towards the target, then sweeps
                    it forward and low in a long lunge (the seed of light leaves the crown at 0.5), the left hand pressed down towards the
                    earth calling the roots; she holds, settles.

  py -3 tools/art_hero_cast.py                    writes assets/characters/player_cast.png, player_cast_blood.png and data/hero_rig.json "cast_*"
  py -3 tools/art_hero_cast.py contact out.png light|root|ember|veil|maw <sector>   one clip as a contact sheet
"""
import json
import sys
from pathlib import Path

import art_hero3d as hero
from art_hero3d import P, FW, FH, ROOT, PICK_FRAMES, paste, write_png, CLEAR, timeline_pose

STAND = ((2.8, 3.0, 0), (-2.8, -0.5, 0))
HOLD_R = (-5.0, 26.5, 3.0)  # the staff hand at rest: beside the hip, a little forward
REST_L = (4.5, 26.0, 1.0)
KNEEL = ((3.2, 7.0, 0), (-3.0, -5.5, 0))  # left foot far forward, right knee down
LUNGE = ((3.3, 6.8, 0), (-3.2, -4.6, 0))

LIGHT_KEYS = [
    (0.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
    (0.16, P(-0.16, 0.08, 0.3, STAND, (-3.6, 33.5, 5.0), (-0.6, 32.5, 6.5), (0.3, 0.1, 0.1))),
    (0.32, P(-0.06, -0.14, -0.4, ((2.9, 2.5, 0), (-2.9, -1.5, 0)), (-3.2, 46.0, 3.4), (6.8, 42.5, 3.0), (-0.8, -0.3, -0.6), 0.06)),
    (0.42, P(-0.04, -0.18, -0.5, ((2.9, 2.5, 0), (-2.9, -1.5, 0)), (-3.0, 47.2, 3.0), (7.2, 43.8, 2.4), (-1.0, -0.4, -0.8), 0.08)),
    (0.52, P(0.06, 0.42, 3.0, KNEEL, (-2.2, 17.0, 9.4), (8.8, 22.0, 4.0), (1.6, 0.9, 1.1), 0.16)),
    (0.66, P(0.05, 0.40, 2.9, KNEEL, (-2.2, 17.4, 9.2), (8.6, 21.6, 4.2), (1.1, 0.7, 0.7), 0.12)),
    (0.84, P(0.02, 0.14, 0.9, ((3.0, 4.0, 0), (-3.0, -2.5, 0)), (-4.0, 25.5, 5.0), (5.0, 26.5, 2.0), (0.3, 0.2, 0.1), 0.04)),
    (1.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
]

ROOT_KEYS = [
    (0.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
    (0.18, P(-0.34, -0.04, -0.4, ((2.9, 2.0, 0), (-2.9, -2.5, 0)), (-6.2, 37.5, -2.6), (5.0, 33.0, 7.0), (0.6, 0.3, 0.3), 0.03)),
    (0.34, P(-0.46, -0.08, -0.6, ((2.9, 2.0, 0), (-2.9, -3.0, 0)), (-6.6, 40.0, -3.8), (5.6, 31.5, 8.6), (0.9, 0.4, 0.5), 0.05)),
    (0.48, P(0.34, 0.34, 2.5, LUNGE, (-0.6, 24.0, 12.0), (6.2, 19.5, 6.5), (-1.3, 0.4, -0.9), 0.13)),
    (0.66, P(0.30, 0.31, 2.3, LUNGE, (-0.8, 24.4, 11.6), (6.0, 19.0, 6.8), (-0.8, 0.3, -0.5), 0.1)),
    (0.84, P(0.10, 0.12, 0.8, ((3.0, 4.0, 0), (-3.0, -2.5, 0)), (-3.6, 27.0, 5.0), (4.8, 26.5, 2.0), (-0.2, 0.1, -0.1), 0.03)),
    (1.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
]

# GLUTSCHWARM: she coils, the staff drawn back over her right shoulder and the left hand reaching out at the target like a bow's grip,
# then snaps the staff forward at chest height in a short step (the shards break out of the crown at 0.43), the left hand flung back.
EMBER_KEYS = [
    (0.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
    (0.16, P(-0.42, -0.06, -0.4, ((2.9, 2.0, 0), (-2.9, -3.0, 0)), (-6.4, 38.0, -3.0), (4.0, 34.0, 7.5), (0.5, 0.2, 0.3), 0.02)),
    (0.30, P(-0.52, -0.08, -0.6, ((2.9, 2.0, 0), (-2.9, -3.4, 0)), (-6.8, 39.5, -4.2), (3.6, 35.0, 8.8), (0.8, 0.3, 0.4), 0.03)),
    (0.42, P(0.40, 0.22, 1.8, ((3.1, 5.6, 0), (-3.0, -3.8, 0)), (-1.0, 34.0, 12.6), (7.6, 30.0, -3.6), (-1.3, 0.3, -0.9), 0.1)),
    (0.62, P(0.34, 0.19, 1.6, ((3.1, 5.6, 0), (-3.0, -3.8, 0)), (-1.2, 33.6, 12.2), (7.2, 30.4, -3.0), (-0.8, 0.2, -0.5), 0.07)),
    (0.84, P(0.10, 0.08, 0.6, ((3.0, 4.0, 0), (-3.0, -2.5, 0)), (-3.8, 27.5, 6.0), (5.0, 27.0, 2.0), (-0.2, 0.1, -0.1), 0.02)),
    (1.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
]

# NEBELSCHLEIER: she lifts the staff upright before her and draws the left hand slowly across her face like a veil, then opens it, palm
# out towards whom she veils, with a soft step (the mist leaves the crown at 0.49); a long, calm hold.
VEIL_KEYS = [
    (0.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
    (0.20, P(0.24, -0.05, 0.2, STAND, (-2.4, 38.5, 6.4), (1.2, 44.5, 6.6), (0.2, 0.1, 0.1), 0.0)),
    (0.38, P(0.34, -0.04, 0.2, STAND, (-2.2, 39.0, 6.6), (-4.2, 43.8, 7.2), (0.3, 0.1, 0.2), 0.02)),
    (0.50, P(-0.18, 0.12, 1.0, ((3.0, 4.2, 0), (-2.9, -2.6, 0)), (-4.2, 33.0, 7.4), (8.4, 36.0, 9.0), (-0.5, 0.2, -0.4), 0.08)),
    (0.72, P(-0.14, 0.10, 0.9, ((3.0, 4.2, 0), (-2.9, -2.6, 0)), (-4.4, 32.6, 7.0), (8.0, 35.4, 8.6), (-0.3, 0.1, -0.2), 0.06)),
    (0.88, P(-0.04, 0.05, 0.4, ((3.0, 3.6, 0), (-3.0, -1.8, 0)), (-4.6, 28.0, 4.6), (5.4, 28.5, 2.6), (0.0, 0.0, 0.0), 0.02)),
    (1.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
]

# LEERENSCHLUND: she rears up, the staff raised and the left hand clawed high as if she grasped the dark, then crouches deep and drives the
# crown down into the ground before her, the left hand a fist pressed to the earth (the ground tears at 0.52); she holds, rises heavily.
MAW_KEYS = [
    (0.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
    (0.20, P(0.10, -0.12, -0.2, ((2.9, 2.5, 0), (-2.9, -1.5, 0)), (-4.6, 38.0, 4.0), (5.4, 46.0, 4.0), (-0.6, -0.2, -0.4), 0.04)),
    (0.36, P(0.14, -0.16, -0.3, ((2.9, 2.5, 0), (-2.9, -1.5, 0)), (-4.4, 40.0, 3.6), (5.8, 47.4, 3.0), (-0.9, -0.3, -0.6), 0.06)),
    (0.52, P(0.04, 0.50, 2.6, ((3.7, 4.6, 0), (-3.6, -4.2, 0)), (-2.0, 17.0, 10.4), (6.2, 15.5, 7.4), (1.6, 0.9, 1.2), 0.18)),
    (0.74, P(0.04, 0.47, 2.5, ((3.7, 4.6, 0), (-3.6, -4.2, 0)), (-2.0, 17.4, 10.2), (6.0, 15.8, 7.2), (1.0, 0.6, 0.7), 0.14)),
    (0.88, P(0.02, 0.16, 0.9, ((3.0, 4.0, 0), (-3.0, -2.5, 0)), (-4.0, 25.5, 5.0), (5.0, 26.5, 2.0), (0.3, 0.2, 0.1), 0.04)),
    (1.00, P(0.0, 0.03, 0.0, STAND, HOLD_R, REST_L, (0.0, 0.0, 0.0))),
]

CLIPS = (("light", LIGHT_KEYS), ("root", ROOT_KEYS), ("ember", EMBER_KEYS), ("veil", VEIL_KEYS), ("maw", MAW_KEYS))


def render(want_blood: bool):
    """Per sector: [(pixels, blood, shoulder, hand)] for the light clip then the root clip."""
    hero.WANT_BLOOD = want_blood
    rows = []
    for sector in range(8):
        row = []
        for _name, keys in CLIPS:
            for i in range(PICK_FRAMES):
                pose = timeline_pose(keys, (i + 0.5) / PICK_FRAMES)
                pixels, rig = hero.frame(sector, 0.0, "attack", False, pose)
                row.append((pixels, hero.LAST_BLOOD if want_blood else None, rig["shoulder"], rig["hand"]))
        rows.append(row)
    hero.WANT_BLOOD = False
    return rows


def contact(out: Path, clip: str, sector: int) -> None:
    keys = dict(CLIPS)[clip]
    cells = [hero.frame(sector, 0.0, "attack", False, timeline_pose(keys, (i + 0.5) / PICK_FRAMES))[0] for i in range(PICK_FRAMES)]
    sheet = [[CLEAR] * (6 * FW) for _ in range(2 * FH)]
    for i, fr in enumerate(cells):
        r, c = divmod(i, 6)
        for y in range(FH):
            sheet[r * FH + y][c * FW:(c + 1) * FW] = fr[y]
    write_png(out, 6 * FW, 2 * FH, sheet)


def main() -> None:
    rows = render(True)
    cols = PICK_FRAMES * len(CLIPS)
    write_png(ROOT / "characters" / "player_cast.png", cols * FW, 8 * FH, paste([[c[0] for c in row] for row in rows], cols, 8))
    write_png(ROOT / "characters" / "player_cast_blood.png", cols * FW, 8 * FH, paste([[c[1] for c in row] for row in rows], cols, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"cast_cols": PICK_FRAMES, "cast_clips": [name for name, _k in CLIPS],
                "cast_shoulder": [c[2] for row in rows for c in row], "cast_hand": [c[3] for row in rows for c in row]})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("cast sheet written", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) > 4 and sys.argv[1] == "contact":
        contact(Path(sys.argv[2]), sys.argv[3], int(sys.argv[4]))
    else:
        main()
