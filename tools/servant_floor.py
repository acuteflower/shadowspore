"""The floor of Ellie's room (tools/art_servant_room.py): irregular flagstones, really random. No tile, no grid, nothing repeats: the stones are scattered by dart throwing with
random sizes, cut apart as a power diagram (straight, slightly hand-wobbly joints), and every stone has its own tone, its own tilt (so it catches the light a little differently),
its own wear. Lit from the top left like everything else: a light rim where a stone's upper left edge rises from the joint, a dark joint, ordered-dither shading across the stone.
Then the little stories: walked-smooth paths, grime along the walls, a water stain under the washstand, hairline cracks, pocks, chipped corners, a few sprigs of moss in the damp joints."""
import math

import numpy as np

from stone_wear import Wear, auto_spots, moss_pass

STONE6 = [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in ("1c1a34", "2e2a52", "47436f", "665f94", "8a83b8", "d0cbec")]  # the world's rocks (tools/art_stone.py)
MOSS = [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in ("14281f", "1c3d36", "2b5646", "3a7550")]
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def _hash(x, y, seed):
    n = (x.astype(np.int64) * 374761393 + y.astype(np.int64) * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _vnoise(x, y, seed):
    xi, yi = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _hash(xi, yi, seed), _hash(xi + 1, yi, seed)
    c, d = _hash(xi, yi + 1, seed), _hash(xi + 1, yi + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def _fbm(x, y, seed):
    return 0.55 * _vnoise(x, y, seed) + 0.3 * _vnoise(x * 2.1, y * 2.1, seed + 7) + 0.15 * _vnoise(x * 4.3, y * 4.3, seed + 13)


def floor_img(W=272, H=160, seed=11, paths=(), damp=((256, 24, 30),), stains=((236, 44, 17, 10),), tone_bias=0.0, wear=Wear()):
    """RGBA array (H, W, 4). `paths`: polylines (floor px) that people have walked smooth; `damp`: (x, y, radius) places where moss grows; `stains`: (x, y, rx, ry) wet stains.
    `wear` (tools/stone_wear.py) turns moss, cracks, chips, pocks, stains, grime, wide joints and the polish of the paths up or down; Wear() is the look of the finished room."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    wx = (_fbm(xx * 0.11, yy * 0.11, seed + 1) - 0.5) * 1.6  # the cut is by hand: the lines are not perfectly straight
    wy = (_fbm(xx * 0.11 + 40, yy * 0.11, seed + 2) - 0.5) * 1.6
    qx, qy = xx + wx, yy + wy
    ids = np.zeros((H, W), np.int32)  # random binary space partition: tilted cuts, random places, random sizes, so the slabs are irregular quadrilaterals of every size
    stack, count = [0], 1
    while stack:
        rid = stack.pop()
        ys, xs = np.nonzero(ids == rid)
        w, hh = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
        tw, th = rng.uniform(20, 50), rng.uniform(15, 34)
        if (w < tw * 1.25 and hh < th * 1.25) or (w < 17 and hh < 17) or (w < 12 or hh < 12):
            continue
        vertical = (w / tw > hh / th) if abs(w / tw - hh / th) > 0.15 else rng.random() < 0.5
        ext = (xs.min(), xs.max() + 1) if vertical else (ys.min(), ys.max() + 1)
        frac = rng.uniform(0.34, 0.66)
        pos = ext[0] + (ext[1] - ext[0]) * frac
        tilt_a = rng.normal(0, 0.11)
        if vertical:
            nx, ny = math.cos(tilt_a), math.sin(tilt_a)
            cx, cy = pos, (ys.min() + ys.max()) / 2.0
        else:
            nx, ny = -math.sin(tilt_a), math.cos(tilt_a)
            cx, cy = (xs.min() + xs.max()) / 2.0, pos
        side = ((qx[ys, xs] - cx) * nx + (qy[ys, xs] - cy) * ny) > 0
        if side.all() or (~side).all():
            continue
        ids[ys[side], xs[side]] = count
        stack += [rid, count]
        count += 1
    n = count
    cnt = np.bincount(ids.ravel(), minlength=n).astype(float)
    P = np.stack([np.bincount(ids.ravel(), weights=xx.ravel(), minlength=n) / cnt, np.bincount(ids.ravel(), weights=yy.ravel(), minlength=n) / cnt, np.sqrt(cnt) / 2.0], axis=1)
    # per stone: tone, tilt, wear, a pocked or smooth surface
    tone = 2.2 + tone_bias + (_fbm(P[:, 0] * 0.03, P[:, 1] * 0.03, seed + 3) - 0.5) * 1.3 + np.clip(rng.normal(0, 0.42, n), -0.8, 0.8)  # broad patches plus each stone's own colour
    tilt = rng.normal(0, 0.45, (n, 2))
    rough = rng.uniform(0.0, 1.0, n)
    # joints and rims
    right = np.roll(ids, -1, axis=1)
    down = np.roll(ids, -1, axis=0)
    joint = (ids != right) | (ids != down)
    wide = rng.random(n) < 0.3 * wear.wide_joints  # some joints are two pixels wide (worn out, filled with sand)
    joint |= wide[ids] & ((ids != np.roll(ids, -2, axis=1)) | (ids != np.roll(ids, -2, axis=0)))
    joint[:, -2:] = False
    joint[-2:, :] = False
    joint_l = np.roll(joint, 1, axis=1)
    joint_u = np.roll(joint, 1, axis=0)
    joint_l[:, 0] = False
    joint_u[0, :] = False
    rim = (joint_l | joint_u) & ~joint
    # the value across the stone
    cx, cy, cr = P[ids, 0], P[ids, 1], P[ids, 2]
    lit = (-(xx - cx) * (0.72 + tilt[ids, 0]) - (yy - cy) * (0.72 + tilt[ids, 1])) / cr
    v = tone[ids] + lit * 0.42 + (_fbm(xx * 0.35, yy * 0.35, seed + 5) - 0.5) * 0.55 * (0.5 + rough[ids])  # stone grain
    speck = _hash(xx, yy, seed + 9)
    v = v - (speck < 0.04 * wear.pocks * (0.4 + rough[ids])) * 0.9 + (speck > 1.0 - 0.015 * wear.pocks) * 0.8  # pocks and glints
    # worn smooth where people walk (lighter, calmer), grime along the walls and in the corners
    walked = np.zeros((H, W))
    for line in paths:
        for (ax, ay), (bx, by) in zip(line, line[1:]):
            t = np.clip(((xx - ax) * (bx - ax) + (yy - ay) * (by - ay)) / max((bx - ax) ** 2 + (by - ay) ** 2, 1e-6), 0, 1)
            d = np.hypot(xx - (ax + (bx - ax) * t), yy - (ay + (by - ay) * t))
            walked = np.maximum(walked, np.clip(1.0 - d / 22.0, 0, 1))
    v += walked * 0.45 * wear.polish
    v -= (np.clip((11 - yy) / 11, 0, 1) * 0.95 + np.clip((9 - xx) / 9, 0, 1) * 0.7 + np.clip((xx - (W - 10)) / 10, 0, 1) * 0.7 + np.clip((yy - (H - 8)) / 8, 0, 1) * 0.35) * wear.grime
    for sx, sy, rx, ry in stains:  # wet stains
        d = np.hypot((xx - sx) / rx, (yy - sy) / ry) + (_fbm(xx * 0.2, yy * 0.2, seed + 6) - 0.5) * 0.6
        v -= np.clip(1.15 - d, 0, 1) * 1.1 * wear.stains
    bay = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    t = np.floor(v + (bay - 0.5) * 0.5 + 0.5).astype(int)
    t = np.clip(t, 1, 5)
    out = np.zeros((H, W, 4), np.uint8)
    pal = np.array(STONE6, np.uint8)
    out[..., :3] = pal[t]
    out[..., 3] = 255
    # rims and joints
    t_rim = np.clip(t + 1, 1, 5)
    out[rim, :3] = pal[t_rim[rim]]
    out[joint, :3] = pal[0]
    deep = joint & (_hash(xx, yy, seed + 15) < 0.25)  # the joints are not one flat black: some are a shade lighter (dust, sand)
    out[deep, :3] = pal[1]
    # hairline cracks, chipped corners
    for i in range(n):
        if P[i, 2] < 9 or not (0 <= P[i, 0] < W and 0 <= P[i, 1] < H):
            continue
        if rng.random() < 0.17 * wear.cracks:
            x, y = P[i, 0] + rng.uniform(-3, 3), P[i, 1] + rng.uniform(-3, 3)
            ang = rng.uniform(0, math.tau)
            for _ in range(int(rng.uniform(6, 15) * min(max(wear.cracks, 0.5), 2.5) ** 0.5)):
                xi, yi = int(x), int(y)
                if 0 <= xi < W and 0 <= yi < H and ids[yi, xi] == i and not joint[yi, xi]:
                    out[yi, xi, :3] = pal[0]
                    if yi + 1 < H and ids[yi + 1, xi] == i and not joint[yi + 1, xi] and rng.random() < 0.5:
                        out[yi + 1, xi, :3] = pal[min(5, t[yi + 1, xi] + 1)]  # the lit lip of the crack
                ang += rng.normal(0, 0.55)
                x, y = x + math.cos(ang), y + math.sin(ang)
        if rng.random() < 0.14 * wear.chips:  # a chipped corner: a few joint-coloured pixels where the stone's edge meets its corner
            ys, xs = np.nonzero((ids == i) & joint)
            if len(xs):
                k = int(rng.integers(0, len(xs)))
                for dx, dy in ((0, 0), (-1, 0), (0, -1), (-1, -1)) if rng.random() < 0.6 else ((0, 0), (-1, 0)):
                    xi, yi = int(xs[k]) + dx, int(ys[k]) + dy
                    if 0 <= xi < W and 0 <= yi < H and ids[yi, xi] == i:
                        out[yi, xi, :3] = pal[0]
    # moss: only in the damp, in the joints and on the rims beside them
    spots = list(wear.moss_spots) if wear.moss_spots is not None else auto_spots(W, H, seed, wear.moss, defaults=[(mx, my, mr, mr) for mx, my, mr in damp], edges=0.85)
    out[..., :3] = moss_pass(out[..., :3], joint, rim, wear, spots, seed, _hash, _fbm)
    return out
