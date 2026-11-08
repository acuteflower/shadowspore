"""How worn a stone surface is: one set of knobs shared by the floor (tools/servant_floor.py) and the walls (tools/servant_wall.py) of Ellie's room, so the same texture can be reused
cleaner, more worn or overgrown. Every knob is a multiplier: 1.0 is the look of the finished room, 0 switches it off, 2-4 is heavy.

    moss          greenery in the joints (0 none, 1 a few patches, 2.4 the walls of the room, 4 overgrown). It also grows the patches and thickens them.
    moss_reach    how far it creeps out of the joints onto the edges of the stones (>1 reaches further)
    moss_hang     walls only: tufts hanging down from the joints over the stone below
    cracks        hairline cracks (how many stones have one, how long)
    chips         chipped corners (a few joint-coloured pixels where a stone's corner broke off)
    pocks         pits and glints in the stone's surface
    stains        wet stains and damp streaks
    wash          walls only: remains of old lime wash
    grime         darkening at the foot of the wall, along the walls and in the corners
    wide_joints   how many stones sit in a wide, sand-filled joint
    polish        floor only: the paths people have walked smooth
    moss_spots    explicit places for the moss, [(x, y, rx, ry)]; None = the surface's own defaults plus automatic ones that grow with `moss`
"""
from dataclasses import dataclass, replace
from typing import Optional, Tuple

import numpy as np

MOSS = [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in ("14281f", "1c3d36", "2b5646", "3a7550", "74b268")]  # the world's moss, dark to lit


@dataclass(frozen=True)
class Wear:
    moss: float = 1.0
    moss_reach: float = 1.0
    moss_hang: float = 1.0
    cracks: float = 1.0
    chips: float = 1.0
    pocks: float = 1.0
    stains: float = 1.0
    wash: float = 1.0
    grime: float = 1.0
    wide_joints: float = 1.0
    polish: float = 1.0
    moss_spots: Optional[Tuple[Tuple[float, float, float, float], ...]] = None

    def but(self, **kw) -> "Wear":
        return replace(self, **kw)


PRESETS = {
    "clean": Wear(moss=0.0, moss_reach=1.0, moss_hang=0.0, cracks=0.15, chips=0.0, pocks=0.3, stains=0.0, wash=0.0, grime=0.4, wide_joints=0.2, polish=1.2),
    "tended": Wear(moss=0.35, moss_hang=0.3, cracks=0.45, chips=0.25, pocks=0.6, stains=0.4, wash=0.4, grime=0.7, wide_joints=0.6),
    "worn": Wear(),
    "neglected": Wear(moss=2.4, moss_reach=1.3, moss_hang=1.2, cracks=1.6, chips=1.5, pocks=1.3, stains=1.5, wash=1.4, grime=1.3, wide_joints=1.4, polish=0.8),
    "ruined": Wear(moss=2.8, moss_reach=1.5, moss_hang=1.4, cracks=2.6, chips=3.0, pocks=2.0, stains=2.0, wash=2.0, grime=1.7, wide_joints=2.0, polish=0.4),
    "overgrown": Wear(moss=4.5, moss_reach=1.9, moss_hang=2.0, cracks=1.2, chips=1.0, pocks=1.0, stains=1.8, wash=0.8, grime=1.2, wide_joints=1.2, polish=0.6),
}


def parse(args, base: Wear = Wear()) -> Wear:
    """'preset=neglected moss=3 cracks=0.5' (as the command line of art_servant_room.py gives them) -> a Wear."""
    wear = base
    for a in args:
        k, _, v = a.partition("=")
        if k == "preset":
            wear = PRESETS[v]
        elif k in Wear.__dataclass_fields__ and k != "moss_spots":
            wear = wear.but(**{k: float(v)})
    return wear


def auto_spots(W, H, seed, moss, defaults=(), bottom=0.0, edges=0.0, count_k=4.0):
    """The moss places: the surface's own `defaults` (grown with `moss`), plus automatic ones (more of them the more moss). `bottom` (0..1) pulls them towards the bottom edge (a wall's foot),
    `edges` (0..1) towards the borders (a floor is damp along its walls)."""
    k = max(moss, 0.0) ** 0.35
    spots = [(x, y, rx * k, ry * k) for x, y, rx, ry in defaults]
    rng = np.random.default_rng(seed + 991)
    for _ in range(int(round(count_k * max(moss - 1.0, 0.0)))):
        rx = rng.uniform(14, 34) * k
        ry = rx * rng.uniform(0.45, 0.8)
        if rng.random() < bottom:
            x, y = rng.uniform(4, W - 4), H - rng.beta(1.2, 3.0) * H * 0.8 - 2
        elif rng.random() < edges:
            side = rng.integers(0, 4)
            x = rng.uniform(4, W - 4) if side < 2 else (rng.uniform(0, 14) if side == 2 else W - rng.uniform(0, 14))
            y = rng.uniform(0, 14) if side == 0 else (H - rng.uniform(0, 14) if side == 1 else rng.uniform(4, H - 4))
        else:
            x, y = rng.uniform(4, W - 4), rng.uniform(2, H - 2)
        spots.append((x, y, rx, ry))
    return spots


def moss_pass(rgb, joint, rim, wear: Wear, spots, seed, hash_fn, fbm_fn, down_hang=False):
    """Greenery in the joints and on the rims beside them. Identical to the floor's original moss at moss = 1; denser, wider and with hanging tufts above that."""
    if wear.moss <= 0.0 or not spots:
        return rgb
    H, W = joint.shape
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    mp = np.array(MOSS, np.uint8)
    edge = joint | rim
    if wear.moss_reach > 1.0:  # a second row of stone beside the joints
        near = np.roll(rim, 1, axis=0) | np.roll(rim, 1, axis=1) | np.roll(rim, -1, axis=0) | np.roll(rim, -1, axis=1)
        edge = edge | (near & (hash_fn(xx, yy, seed + 16) < min(1.0, wear.moss_reach - 1.0) * 0.55))
    dens = 0.55 + 0.45 * wear.moss
    painted = np.zeros((H, W), bool)
    for mx, my, rx, ry in spots:
        d = np.hypot((xx - mx) / rx, (yy - my) / ry) + (fbm_fn(xx * 0.18, yy * 0.18, seed + 8) - 0.5) * 0.8
        grow = edge & (d < 1.0) & (hash_fn(xx, yy, seed + 10) < (1.0 - d) * 0.9 * dens)
        painted |= grow
        pick = np.where(hash_fn(xx, yy, seed + 11)[grow] < 0.35, 3, np.where(hash_fn(xx, yy, seed + 12)[grow] < 0.5, 2, 1))
        rgb[grow] = mp[pick]
    if down_hang and wear.moss_hang > 0.0:  # tufts hanging from a joint over the stone below, the tips lit
        below = np.roll(painted, 1, axis=0)
        below[0, :] = False
        tuft = below & ~joint & (hash_fn(xx, yy, seed + 17) < 0.42 * wear.moss_hang)
        rgb[tuft] = mp[np.where(hash_fn(xx, yy, seed + 18)[tuft] < 0.5, 2, 3)]
        below2 = np.roll(tuft, 1, axis=0)
        below2[0, :] = False
        tip = below2 & ~joint & ~tuft & (hash_fn(xx, yy, seed + 19) < 0.5 * min(wear.moss_hang, 1.5))
        rgb[tip] = mp[np.where(hash_fn(xx, yy, seed + 20)[tip] < 0.4, 4, 3)]
    return rgb
