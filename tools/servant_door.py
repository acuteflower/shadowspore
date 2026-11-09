"""The door of Ellie's room (tools/art_servant_room.py): a servants' plank door seen from the front, made like the room's furniture (the tended plum-violet fir of tools/servant_furniture.py, iron, the
renderer of the hut). Vertical boards of slightly different wood, a Z-brace (top, bottom and the diagonal), an iron ring pull on a back plate, rivets, a worn threshold board; the top rows lie in the
shade of the wall's cap. It fills the doorway of the front wall exactly (48 x 36 px, DOOR_GAP of art_servant_room.py), so it takes the place of the gap when it is shut and swings away when it opens
(Doorway.set_open squeezes it towards its left hinge).
    python3 tools/servant_door.py [preview.png]"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import servant_furniture  # noqa: E402,F401  (sets hut_lib's tended state before any colour is read)
import art_hero3d as h  # noqa: E402
from hut_lib import BARK, BARK_D, IRON, PLANK, PLANK_W, U, V, grain, render, rng_for, slab, to_array  # noqa: E402

W, H = 48, 36
PAD = 4  # canvas margin the renderer needs round the model


def door_arr(seed=33):
    rng = rng_for(seed)
    m = h.Model()
    mw, mh = W * U, H * U
    n = 6
    bw = mw / n
    for i in range(n):  # the boards: flush at the top (the frame), each a little different
        x = -mw / 2 + bw * (i + 0.5)
        mat = (PLANK, PLANK_W)[i % 2] if i % 3 != 2 else BARK
        slab(m, V(x, 0.5 * U, 0), V(x, mh + 1.0 * U, 0), bw / 2 - 0.55, 1.8, mat, (0, 0, 1), step=1.3)
        slab(m, V(x + bw / 2 - 0.25, 0.5 * U, 0.4), V(x + bw / 2 - 0.25, mh + 1.0 * U, 0.4), 0.3, 1.4, BARK_D, (0, 0, 1), step=1.5)  # the joint between two boards
    for y in (mh * 0.24, mh * 0.74):  # two iron straps across, with rivets
        slab(m, V(-mw / 2, y, 2.1), V(mw / 2, y, 2.1), 1.9, 0.6, IRON, (0, 0, 1), step=1.3)
        for k in range(n + 1):
            m.ell((-mw / 2 + k * bw, y, 2.8), (0.55, 0.55, 0.4), IRON)
    ring = V(mw * 0.30, mh * 0.5, 0)  # the ring pull on a back plate, between the straps
    m.ell(ring + V(0, 0, 2.6), (2.6, 1.8, 0.5), IRON)
    for k in range(16):
        a = k / 16 * math.tau
        m.ell(ring + V(2.4 * math.cos(a), -1.2 + 2.4 * math.sin(a), 3.4), (0.8, 0.8, 0.7), h.GOLD if k % 8 == 0 else IRON)
    arr = to_array(render(m, W + 2 * PAD, H + 2 * PAD, H + PAD))
    arr = grain(arr, 5, along=(0.0, 1.0), amount=0.6)
    out = arr[PAD:PAD + H, PAD:PAD + W].copy()
    # the top rows lie in the shade of the wall's cap, the foot is the worn threshold board
    out[0] = out[1]
    for y, k in enumerate((0.55, 0.38, 0.22, 0.1)):
        solid = out[y, :, 3] > 0
        out[y, solid, :3] = (out[y, solid, :3] * (1.0 - k) + np.array([16, 12, 28]) * k).astype(np.uint8)
    out[H - 2:, :, :3] = np.where(out[H - 2:, :, 3:4] > 0, (out[H - 2:, :, :3] * 0.82).astype(np.uint8), out[H - 2:, :, :3])
    return out


if __name__ == "__main__":
    from PIL import Image
    arr = door_arr()
    print(arr.shape, "opaque:", int((arr[..., 3] > 0).sum()), "of", W * H)
    if len(sys.argv) > 1:
        Image.fromarray(arr).resize((W * 8, H * 8), Image.NEAREST).save(sys.argv[1])
