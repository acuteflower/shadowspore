"""Ellie's shadow step (Alt): a short, straight evasive step that dissolves her into the void and puts her back a little further on.
Same ellipsoid renderer as every other sheet of the heroine. BOTH arms are baked into these frames (the game hides its own sword arm
during the step), so the whole body dissolves together in `hit_flash.gdshader` (`step_*` uniforms).

Frames per sector row (the body faces the step direction):
  0 set      a quick dip: weight onto the back foot, knees give, arms drop a little
  1 load     half way into the push
  2 push     the straight push-off: the back leg drives, the body low and long, arms trailing, the hair lagging behind
  3 glide    the body flies on, the back foot comes off the ground (here she is already dissolving)
  4 arrive   she comes out of the rift still flying: the front foot reaches for the ground, the left hand forward, the hair still streaming on
  5 land     the foot bites, the hips sink, the weight catches
  6 absorb   half way up
  7 rise     back towards her ready stance (the game hands over to the idle loop)

  py -3 tools/art_hero_step.py [contact out.png <sector>]   writes assets/characters/player_step.png, player_step_blood.png and data/hero_rig.json "step_*"
"""
import json
import sys
from pathlib import Path

import art_hero3d as hero
from art_hero3d import P, FW, FH, ROOT, paste, write_png, CLEAR

# (twist, lean, pz, feet ((x, z, lift) left, right), hand_r, hand_l, hair lag (x, y, z: - = behind), flare)
SET = P(0.04, 0.12, -0.6, ((3.0, 2.2, 0), (-3.0, -3.6, 0)), (-5.6, 24.6, 0.4), (5.6, 24.8, 0.8), (0.0, -0.2, 0.3), 0.04)
PUSH = P(0.0, 0.36, 3.4, ((3.1, 9.0, 0), (-3.0, -6.4, 0.9)), (-6.6, 26.6, -5.6), (6.6, 26.8, -5.4), (0.0, 0.9, -2.6), 0.18)
GLIDE = P(0.0, 0.40, 5.0, ((3.1, 9.6, 0.8), (-3.0, -3.2, 3.2)), (-7.0, 27.8, -6.4), (7.0, 28.0, -6.2), (0.0, 1.3, -3.4), 0.26)
ARRIVE = P(-0.10, 0.30, 3.4, ((3.1, 7.6, 0.6), (-3.0, -4.6, 1.6)), (-6.4, 25.4, -3.6), (4.2, 32.0, 9.0), (0.0, 0.9, 2.4), 0.22)
LAND = P(-0.08, 0.28, 2.4, ((3.1, 7.0, 0), (-3.0, -5.0, 0)), (-5.8, 25.0, -2.2), (4.4, 29.6, 7.4), (0.0, 0.4, 1.6), 0.14)
RISE = P(0.0, 0.08, 0.7, ((3.0, 3.4, 0), (-3.0, -2.6, 0)), (-5.3, 24.8, 0.4), (5.0, 25.4, 1.4), (0.0, 0.0, 0.4), 0.03)


def mix(a, b, k: float):
    """A keyframe between two keyframes (every number blended)."""
    def m(x, y):
        if isinstance(x, (tuple, list)):
            return tuple(m(p, q) for p, q in zip(x, y))
        if isinstance(x, (int, float)) and not isinstance(x, bool):
            return x + (y - x) * k
        return x
    return {key: m(a[key], b[key]) for key in a}


STAND = P(0.0, 0.0, 0.0, ((3.0, 0.6, 0), (-3.0, -0.6, 0)), (-5.2, 24.6, 0.6), (5.2, 24.6, 0.6), (0.0, 0.0, 0.0), 0.0)
POSES = [SET, mix(SET, PUSH, 0.5), PUSH, GLIDE, ARRIVE, LAND, mix(LAND, RISE, 0.5), RISE]
for pose in POSES:
    pose["both_arms"] = True  # the sword arm is part of the frame, it dissolves with her
FRAMES = len(POSES)


def render_frames(want_blood: bool, sectors):
    hero.WANT_BLOOD = want_blood
    rows = []
    for sector in sectors:
        row = []
        for pose in POSES:
            pixels, rig = hero.frame(sector, 0.0, "attack", False, pose)
            row.append((pixels, hero.LAST_BLOOD if want_blood else None, rig["shoulder"], rig["hand"]))
        rows.append(row)
    hero.WANT_BLOOD = False
    return rows


def contact(out: Path, sector: int) -> None:
    cells = [c[0] for c in render_frames(False, [sector])[0]]
    sheet = [[CLEAR] * (FRAMES * FW) for _ in range(FH)]
    for i, fr in enumerate(cells):
        for y in range(FH):
            sheet[y][i * FW:(i + 1) * FW] = fr[y]
    write_png(out, FRAMES * FW, FH, sheet)


def main() -> None:
    rows = render_frames(True, range(8))
    write_png(ROOT / "characters" / "player_step.png", FRAMES * FW, 8 * FH, paste([[c[0] for c in row] for row in rows], FRAMES, 8))
    write_png(ROOT / "characters" / "player_step_blood.png", FRAMES * FW, 8 * FH, paste([[c[1] for c in row] for row in rows], FRAMES, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"step_frames": FRAMES, "step_shoulder": [c[2] for row in rows for c in row], "step_hand": [c[3] for row in rows for c in row]})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("step sheet written", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[1] == "contact":
        contact(Path(sys.argv[2]), int(sys.argv[3]))
    else:
        main()
