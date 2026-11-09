"""Three more things for the other servants' rooms (tools/art_servant_rooms2.py), made like Ellie's furniture (tools/servant_furniture.py): a small table with a jug and a bowl, a three-legged stool and a
plain wall shelf (no picture, no feather: it is not hers). Every function returns (RGBA array, feet row)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import servant_furniture as furn  # noqa: E402
from servant_furniture import BARK, BARK_D, CLAY, GAP, IRON, LINEN, PLANK_W, V, grain, log, render, slab, to_array  # noqa: E402


def table_arr():
    """A small square table of the plum fir with a clay jug, a bowl with a heel of bread and a tin cup on it."""
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 10.0, 0, sz * 7.0), V(sx * 9.8, 16.0, sz * 6.8), 1.6, BARK_D, step=1.1)
    slab(m, V(-12.5, 16.6, 0), V(12.5, 16.6, 0), 1.5, 9.0, BARK, (0, 1, 0))  # the top
    slab(m, V(-11.5, 15.8, 9.4), V(11.5, 15.8, 9.4), 1.3, 0.9, PLANK_W, (0, 0, 1))  # its apron
    m.ell((-6.0, 21.0, -1.0), (3.4, 4.0, 3.2), CLAY)  # the jug
    m.ell((-6.0, 25.4, -1.0), (2.0, 1.4, 1.9), CLAY)
    m.ell((-6.0, 26.6, -1.0), (1.8, 0.3, 1.7), GAP)
    m.limb(V(-9.0, 22.0, -1.0), V(-9.6, 19.6, -1.0), 0.5, 0.5, CLAY)
    m.ell((5.0, 18.0, 1.0), (4.6, 1.3, 3.8), CLAY)  # the bowl
    m.ell((5.0, 18.9, 1.0), (4.0, 0.4, 3.2), GAP)
    m.ell((5.0, 19.2, 1.0), (2.6, 1.0, 1.8), h.BLANKET)  # a heel of bread
    log(m, V(9.0, 17.4, -4.0), V(9.0, 20.6, -4.0), 1.5, IRON, step=0.9)  # a tin cup
    m.ell((9.0, 20.7, -4.0), (1.3, 0.3, 1.3), GAP)
    arr = to_array(render(m, 36, 42, 34))
    return furn._ground(grain(arr, 41, amount=0.5), 34, 15, 3), 34


def stool_arr():
    """A three-legged stool with a round seat, worn pale in the middle."""
    m = h.Model()
    for k, (dx, dz) in enumerate(((-4.5, -2.5), (4.5, -2.5), (0.0, 5.0))):
        log(m, V(dx * 1.1, 0, dz * 1.1), V(dx, 10.0, dz), 1.3, BARK_D, step=1.0)
    m.ell((0, 10.8, 0), (6.0, 1.3, 5.4), BARK)
    m.ell((0, 11.6, 0), (4.4, 0.4, 3.9), PLANK_W)
    arr = to_array(render(m, 20, 22, 17))
    return furn._ground(grain(arr, 42, amount=0.4), 17, 7, 2), 17


def shelf2_arr():
    """A plain wall shelf on two brackets: two clay cups, a folded cloth and a book."""
    m = h.Model()
    slab(m, V(-23, 8.0, 3.0), V(23, 8.0, 3.0), 1.5, 4.8, PLANK_W, (0, 1, 0), step=1.3)
    slab(m, V(-23, 6.4, 7.2), V(23, 6.4, 7.2), 1.0, 0.9, BARK, (0, 0, 1), step=1.3)
    for bx in (-16.0, 16.0):
        slab(m, V(bx, 0.0, 0.6), V(bx, 7.0, 0.6), 1.0, 1.2, BARK_D, (0, 0, 1), step=1.0)
        m.limb(V(bx, 0.4, 0.6), V(bx, 7.0, 5.6), 1.0, 1.0, BARK_D)
    for cx in (-14.0, -8.0):  # two cups
        log(m, V(cx, 9.4, 3.5), V(cx, 14.0, 3.5), 2.0, CLAY, step=0.9)
        m.ell((cx, 14.2, 3.5), (1.7, 0.3, 1.7), GAP)
    for k in range(3):  # a folded cloth
        m.ell((4.0, 10.4 + k * 1.4, 3.8), (6.0, 1.0, 3.8), LINEN)
    m.ell((17.0, 11.0, 3.8), (5.6, 2.0, 4.0), PLANK_W)  # a book
    m.ell((17.0, 12.9, 3.8), (5.1, 0.5, 3.5), LINEN)
    arr = grain(to_array(render(m, 56, 40, 32)), 75, amount=0.4, mats=(PLANK_W, BARK, BARK_D))
    return arr, 32
