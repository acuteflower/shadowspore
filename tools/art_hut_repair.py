#!/usr/bin/env python3
"""The beams for the building scene (story: Valdric and Ellie mend the hut; needs numpy): yard_beams.png, a stack of fresh-cut fir beams and planks (72 x 44, ground row 36),
written to assets/interior/hut/. Fresh-cut fir (`NEWWOOD`): pale, warm, a little rosy. The renewed hut itself (outside and inside) is tools/art_hut_fresh.py.
  python3 tools/art_hut_repair.py"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import hut_outside as ho  # noqa: E402
from gen_art import hexc  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, save  # noqa: E402

OUT = ROOT / "interior" / "hut"
NEWWOOD = len(h.RAMPS)
h.RAMPS += [[hexc(c) for c in row] for row in [["5a3d34", "8c6048", "c08e66", "e8bc8c"]]]  # fresh-cut fir


def beams():
    rng = rng_for(65)
    m = h.Model()
    for k in range(6):  # a stack of beams, three below, two on top, one more
        row, col = (0, k) if k < 3 else ((1, k - 3 + 0.5) if k < 5 else (2, 1.0))
        log(m, V(-26 + rng.uniform(-1.5, 0.5), 3.2 + row * 5.6, -9 + col * 6.2), V(26 + rng.uniform(-0.5, 1.5), 3.2 + row * 5.6 + rng.uniform(-0.2, 0.4), -9 + col * 6.2), 2.9, NEWWOOD, step=1.1)
        m.ell((27.2, 3.2 + row * 5.6, -9 + col * 6.2), (0.8, 2.7, 2.7), PLANK_W)
    for k in range(3):  # planks leaning against it
        slab(m, V(-22 + k * 4.0, 1.0, 14.0), V(-20 + k * 4.0, 19.0, 6.0), 3.6, 0.9, NEWWOOD, (0, 0.4, 1), step=1.2)
    for _ in range(5):  # sawdust and shavings
        m.ell(V(rng.uniform(-22, 22), 0.8, rng.uniform(8, 16)), (rng.uniform(2, 3.4), 0.5, rng.uniform(1.2, 2)), STRAW)
    arr = to_array(render(m, 72, 44, 36))
    return soft_shadow(grain(arr, 66, amount=0.6), 36, 37, 30, 4, 70), 36


def main():
    arr, feet = beams()
    save(OUT / "yard_beams.png", arr)
    print("repair art written", feet)


if __name__ == "__main__":
    main()
