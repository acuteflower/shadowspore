#!/usr/bin/env python3
"""The quest board of the town (docs/questtafel_konzept.md): two leaning posts, a plank panel under a small shingled roof, an empty panel for the live notes, moss and a
glowing bud. Made like the other town pieces (ellipsoids through art_town / hut_lib). Needs numpy.
    py -3 tools/art_quest_board.py [preview.png]     writes assets/town/quest_board.png (+ _glow)
Frame 56x56, feet row 50, footprint 40x10 (data/town.json `quest_board`)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_town as t  # noqa: E402
from art_town import *  # noqa: E402,F401,F403
import hut_lib  # noqa: E402
import art_hero3d as h  # noqa: E402
from hut_lib import rng_for, slab, V, to_array  # noqa: E402


def quest_board():
    rng = rng_for(61)
    m = h.Model()
    z = -t.depth_units(10) / 2.0
    for sx in (-1, 1):
        x = sx * 19.5
        lean = rng.uniform(-0.05, 0.05)
        t.log(m, V(x, 0, z), V(x + lean * 46, 46.0, z), 2.1, t.BARK, step=1.0, taper=0.9)
        for k in range(3):  # roots and stones at the foot
            a = k / 3 * 6.283 + 0.5 + sx
            m.limb(V(x + 1.5 * (1 if k % 2 else -1), 3.0, z + 1.0), V(x + 4.4 * (1 if k % 2 else -1), 0.4, z + 2.6 * (1 if k < 2 else -1)), 1.2, 0.5, t.BARK)
        m.ell(V(x + 3.5, 1.2, z + 3.0), (3.2, 1.6, 2.4), t.STONE)
        m.ell(V(x - 2.8, 1.0, z + 2.6), (2.2, 1.2, 1.8), t.STONE_L)
    # the panel: planks, slightly uneven, a frame of two rails
    for i, yy in enumerate([13.0 + 3.5 * k for k in range(7)]):
        slab(m, V(-18.0, yy, z + 1.4), V(18.0, yy + rng.uniform(-0.25, 0.25), z + 1.4), 1.75, 0.8, t.PLANK_W if i % 2 else t.PLANK, (0, 0, 1), step=1.3)
    for yy in (12.0, 35.0):
        slab(m, V(-21.5, yy, z + 2.4), V(21.5, yy, z + 2.4), 1.0, 1.0, t.BARK_D, (0, 0, 1), step=1.3)
    # the little roof
    slab(m, V(-25.0, 38.5, z + 1.0), V(25.0, 38.5, z + 1.0), 3.2, 0.9, t.PLANK_W, (0, 1, 0.55), step=1.3)
    slab(m, V(-24.0, 39.7, z - 1.4), V(24.0, 39.7, z - 1.4), 2.6, 0.8, t.PLANK, (0, 1, -0.3), step=1.3)
    # no notes here: BoardNotes (src/town/board_notes.gd) pins the real notices on the empty panel, six places
    for k in range(6):  # only the pin holes and a nail head per place
        x = -10.0 + 10.0 * (k % 3)
        y = 28.5 - 8.0 * (k // 3)
        m.ell(V(x, y + 3.0, z + 2.5), (0.5, 0.5, 0.4), t.IRON)
    m.ell(V(22.5, 36.0, z + 2.9), (0.9, 0.9, 0.9), t.BARK_D)  # the knob where the live bud hangs (BoardNotes draws the glow, it breathes and pulses)
    for _ in range(6):
        m.ell(V(rng.uniform(-23, 23), 39.6, z + rng.uniform(-2, 2.5)), (rng.uniform(1.4, 3.0), 0.45, 1.1), t.MOSS_L if rng.random() < 0.6 else t.MOSS)
    arr = to_array(hut_lib.render(m, 56, 56, 50))
    return t.put("quest_board", t.finish(arr, 62, 50, 20, 2.4))


if __name__ == "__main__":
    t.OUT.mkdir(parents=True, exist_ok=True)
    hut_lib.set_fresh()
    arr = quest_board()
    print("written quest_board", arr.shape)
    out_png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if out_png:
        t.contact({"quest_board": arr}, out_png[0])
