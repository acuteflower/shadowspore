"""The walls of Ellie's room (tools/art_servant_room.py), made like its floor (tools/servant_floor.py): the same world stone ramp, the same construction of a stone (dark joint, light rim where
its upper left edge rises, ordered-dither shading across it, its own tone and tilt), the same wear (hairline cracks, pocks, grime, moss only in the damp). Courses of hewn blocks, every course
and block of its own random size, the courses wobbling a hair, the joints a little tilted; lighter top surfaces, a darker vertical face."""
import math

import numpy as np

from servant_floor import BAYER, STONE6, _fbm, _hash
from stone_wear import MOSS, Wear, auto_spots, moss_pass

PAL = np.array(STONE6, np.uint8)


def _courses(W, H, rng, heights, widths, seed, wobble=1.1):
    """Block ids (H, W): rows of random heights, each cut into blocks of random widths, a random offset per row, joints tilted a little, the lines wobbling by hand."""
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    qx = xx + (_fbm(xx * 0.07, yy * 0.07, seed + 1) - 0.5) * 2 * wobble
    qy = yy + (_fbm(xx * 0.07 + 31, yy * 0.07, seed + 2) - 0.5) * 2 * wobble
    ids = np.zeros((H, W), np.int32)
    y, count, rows = 0.0, 0, []
    while y < H - 0.5:
        h = rng.uniform(*heights)
        if H - (y + h) < heights[0] * 0.8:
            h = H - y
        rows.append((y, y + h))
        y += h
    for (y0, y1) in rows:
        band = (qy >= y0) & (qy < y1) if y1 < H else (qy >= y0)
        if y0 == 0:
            band = qy < y1
        x = -rng.uniform(0, widths[1])
        cuts = []
        while x < W + widths[1]:
            x += rng.uniform(*widths)
            cuts.append((x, rng.normal(0, 0.1)))
        idx = np.zeros((H, W), np.int32)
        for cx, tilt in cuts:
            idx += (qx > cx + tilt * (qy - (y0 + y1) / 2)).astype(np.int32)
        ids = np.where(band, count + idx, ids)
        count += len(cuts) + 1
    _, ids = np.unique(ids, return_inverse=True)
    return ids.reshape(H, W).astype(np.int32)


def _stone(ids, rng, seed, tone, spread=0.42, lit_k=0.42, grime=None, damp=(), cracks=0.18, wide=0.3, tone_wave=1.2, wear=Wear()):
    """Shade a block partition the way servant_floor shades its slabs. Returns (rgb (H, W, 3) uint8, joint mask, ids)."""
    H, W = ids.shape
    n = int(ids.max()) + 1
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    cnt = np.bincount(ids.ravel(), minlength=n).astype(float)
    cx = np.bincount(ids.ravel(), weights=xx.ravel(), minlength=n) / cnt
    cy = np.bincount(ids.ravel(), weights=yy.ravel(), minlength=n) / cnt
    hw = np.full(n, 1.0)
    hh = np.full(n, 1.0)
    np.maximum.at(hw, ids.ravel(), np.abs(xx.ravel() - cx[ids.ravel()]))
    np.maximum.at(hh, ids.ravel(), np.abs(yy.ravel() - cy[ids.ravel()]))
    tn = tone + (_fbm(cx * 0.03, cy * 0.03, seed + 3) - 0.5) * tone_wave + np.clip(rng.normal(0, spread, n), -0.8, 0.8)
    tilt = rng.normal(0, 0.4, (n, 2))
    rough = rng.uniform(0, 1, n)
    right, down = np.roll(ids, -1, axis=1), np.roll(ids, -1, axis=0)
    joint = (ids != right) | (ids != down)
    widej = rng.random(n) < wide * wear.wide_joints
    joint |= widej[ids] & ((ids != np.roll(ids, -2, axis=1)) | (ids != np.roll(ids, -2, axis=0)))
    joint[:, -2:] = False
    joint[-2:, :] = False
    jl, ju = np.roll(joint, 1, axis=1), np.roll(joint, 1, axis=0)
    jl[:, 0] = False
    ju[0, :] = False
    rim = (jl | ju) & ~joint
    lit = (-(xx - cx[ids]) / hw[ids] * (0.55 + tilt[ids, 0]) - (yy - cy[ids]) / hh[ids] * (0.55 + tilt[ids, 1])) * 0.5
    v = tn[ids] + lit * lit_k * 2.0 + (_fbm(xx * 0.35, yy * 0.35, seed + 5) - 0.5) * 0.55 * (0.5 + rough[ids])
    sp = _hash(xx, yy, seed + 9)
    v = v - (sp < 0.04 * wear.pocks * (0.4 + rough[ids])) * 0.9 + (sp > 1.0 - 0.015 * wear.pocks) * 0.8
    if grime is not None:
        v = v + grime(xx, yy)
    for sx, sy, rx, ry in damp:
        d = np.hypot((xx - sx) / rx, (yy - sy) / ry) + (_fbm(xx * 0.2, yy * 0.2, seed + 6) - 0.5) * 0.6
        v -= np.clip(1.15 - d, 0, 1) * 1.0 * wear.stains
    bay = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    t = np.clip(np.floor(v + (bay - 0.5) * 0.5 + 0.5).astype(int), 1, 5)
    rgb = PAL[t].copy()
    rgb[rim] = PAL[np.clip(t + 1, 1, 5)][rim]
    rgb[joint] = PAL[0]
    rgb[joint & (_hash(xx, yy, seed + 15) < 0.25)] = PAL[1]
    for i in range(n):  # hairline cracks with a lit lip, like the floor's
        if cnt[i] < 150 or rng.random() > cracks * wear.cracks:
            continue
        x, y = cx[i] + rng.uniform(-hw[i] * 0.5, hw[i] * 0.5), cy[i] + rng.uniform(-hh[i] * 0.4, hh[i] * 0.4)
        ang = rng.uniform(0, math.tau)
        for _ in range(int(rng.uniform(6, 15) * min(max(wear.cracks, 0.5), 2.5) ** 0.5)):
            xi, yi = int(x), int(y)
            if 0 <= xi < W and 0 <= yi < H and ids[yi, xi] == i and not joint[yi, xi]:
                rgb[yi, xi] = PAL[0]
                if yi + 1 < H and ids[yi + 1, xi] == i and not joint[yi + 1, xi] and rng.random() < 0.5:
                    rgb[yi + 1, xi] = PAL[min(5, t[yi + 1, xi] + 1)]
            ang += rng.normal(0, 0.55)
            x, y = x + math.cos(ang), y + math.sin(ang)
    if wear.chips > 0.0:  # chipped corners (a separate random stream, so the other marks stay where they are)
        crng = np.random.default_rng(seed + 77)
        for i in range(n):
            if cnt[i] < 150 or crng.random() > 0.14 * wear.chips:
                continue
            ys, xs = np.nonzero((ids == i) & joint)
            if len(xs):
                k = int(crng.integers(0, len(xs)))
                for dx, dy in ((0, 0), (-1, 0), (0, -1), (-1, -1)) if crng.random() < 0.6 else ((0, 0), (-1, 0)):
                    xi, yi = int(xs[k]) + dx, int(ys[k]) + dy
                    if 0 <= xi < W and 0 <= yi < H and ids[yi, xi] == i:
                        rgb[yi, xi] = PAL[0]
    return rgb, joint, rim, t


def window_cut(out, rect, seed=61):
    """A small window through the face of the back wall: `rect` (x, y, w, h) is the opening (alpha 0; the sky sprite lies behind it), framed by dressed stones (a lighter ring with its own joints,
    a heavy lintel), the reveal (left dark, right lit, like the doorway) and a projecting sill whose top is where something can sit."""
    x0, y0, w, h = rect
    x1, y1 = x0 + w, y0 + h
    rng = np.random.default_rng(seed)
    W = out.shape[1]
    rgb = out[..., :3]
    ring = np.zeros(out.shape[:2], bool)  # dressed stones round the opening: 3 px at the sides, 4 above
    ring[y0 - 4:y1 + 1, x0 - 3:x1 + 3] = True
    ring[y0:y1, x0:x1] = False
    for yy_ in range(y0 - 4, y1 + 1):  # lift the stone one step: cut stone is paler than the rubble wall
        for xx_ in range(x0 - 3, x1 + 3):
            if ring[yy_, xx_]:
                c = tuple(int(v) for v in rgb[yy_, xx_])
                k = min(range(6), key=lambda i: sum((int(PAL[i][j]) - c[j]) ** 2 for j in range(3)))
                bay = BAYER[yy_ % 4, xx_ % 4]
                rgb[yy_, xx_] = PAL[min(5, k + (1 if bay > 0.35 else 0))]
    for xx_ in range(x0 - 3, x1 + 3):  # the dark outline round the dressed stones
        rgb[y0 - 5, xx_] = PAL[0]
    for yy_ in range(y0 - 5, y1 + 1):
        rgb[yy_, x0 - 4] = PAL[0]
        rgb[yy_, x1 + 3] = PAL[0]
    # joints between the dressed stones: the lintel is one long block with a joint at each end, the jambs are courses of 7..11 px
    for xx_ in (x0 - 3, x1 + 2):
        rgb[y0 - 4:y0 - 0, xx_] = PAL[0]
    y = y1 - int(rng.integers(5, 8))
    while y > y0 + 1:
        for xx_ in range(x0 - 3, x0):
            rgb[y, xx_] = PAL[0]
        y2 = y - int(rng.integers(5, 8)) + 1
        for xx_ in range(x1, x1 + 3):
            rgb[max(y2, y0 + 1), xx_] = PAL[0]
        y -= int(rng.integers(7, 11))
    rgb[y0 - 1, x0 - 3:x1 + 3] = PAL[1]  # the underside of the lintel throws a shadow into the opening
    out[y0:y1, x0:x1, 3] = 0
    for k in range(3):  # shadow of the lintel falls on the sky edge too: stays part of the wall picture (alpha) so the sky behind is darkened
        out[y0 + k, x0:x1, :3] = PAL[0]
        out[y0 + k, x0:x1, 3] = (200, 110, 50)[k]
    out[y0:y1, x0:x0 + 2, :3] = PAL[0]  # the left reveal faces away from the light
    out[y0:y1, x0:x0 + 1, 3] = 255
    out[y0:y1, x0 + 1:x0 + 2, 3] = 150
    out[y0:y1, x1 - 2:x1 - 1, :3] = PAL[4]  # the right reveal catches the light
    out[y0:y1, x1 - 2:x1 - 1, 3] = 210
    out[y0:y1, x1 - 1:x1, :3] = PAL[5]
    out[y0:y1, x1 - 1:x1, 3] = 255
    # the sill: a slab that sticks out of the wall, lit top (4 rows), dark front (3 rows), its shadow on the wall
    sx0, sx1 = x0 - 5, x1 + 5
    for k in range(4):
        out[y1 + k, sx0:sx1, :3] = PAL[4] if k < 2 else PAL[3]
        out[y1 + k, sx0:sx1, 3] = 255
    out[y1, sx0:sx1, :3] = PAL[5]
    for k in range(3):
        out[y1 + 4 + k, sx0:sx1, :3] = PAL[2] if k == 0 else PAL[1]
        out[y1 + 4 + k, sx0:sx1, 3] = 255
    out[y1 + 6, sx0:sx1, :3] = PAL[0]
    for xx_ in (sx0, sx1 - 1):
        out[y1:y1 + 7, xx_, :3] = PAL[0]
    for xx_ in (int((sx0 + x0) / 2 + rng.integers(-1, 2)), int((x1 + sx1) / 2 + rng.integers(-1, 2))):  # joints in the slab
        out[y1 + 4:y1 + 6, xx_, :3] = PAL[0]
    for k, a in enumerate((90, 52, 24)):  # the sill's shadow on the wall below
        sel = out[y1 + 7 + k, sx0 + 1:sx1 - 1]
        sel[:, :3] = (sel[:, :3].astype(int) * (255 - a) // 255).astype(np.uint8)
    return out


def sky_img(w, h, seed=71):
    """What is seen through the window: a dithered dusk-violet sky (deeper at the top, pale at the horizon), two thin clouds, a ridge of far firs at the bottom. Lit by the room's tint like the wall."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    v = 2.6 + (yy / h) * 2.1 + (_fbm(xx * 0.12, yy * 0.3, seed) - 0.5) * 0.9
    bay = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    t = np.clip(np.floor(v + (bay - 0.5) * 0.9 + 0.5).astype(int), 2, 5)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = PAL[t]
    out[..., 3] = 255
    for cy, cx, cl in ((int(h * 0.34), int(rng.integers(3, 8)), 11), (int(h * 0.52), int(rng.integers(12, 15)), 9)):  # thin clouds: a pale streak with a darker belly
        for i in range(cl):
            x = cx + i
            if 0 <= x < w:
                out[cy, x, :3] = PAL[5]
                if 2 <= i < cl - 2:
                    out[cy + 1, x, :3] = PAL[4]
    ridge = (h * 0.90 + 1.6 * np.sin(np.arange(w) * 0.9 + 1.0) + np.where(np.arange(w) % 5 == 2, -2.0, 0.0) + np.where(np.arange(w) % 7 == 4, -1.0, 0.0)).astype(int)
    for x in range(w):  # far firs: pointed tops on a dark ridge
        out[ridge[x]:, x, :3] = PAL[1]
        out[ridge[x]:ridge[x] + 1, x, :3] = PAL[2]
    return out


def back_wall_img(W=304, cap=14, face=58, below=4, seed=21, wear=Wear(), window=None):
    """The back wall: rows 0..cap the lit top, then the face; `below` rows are the contact shadow on the floor. RGBA (cap + face + below, W, 4).
    `window` (x, y, w, h) in wall pixels cuts a small window through the face (see window_cut)."""
    rng = np.random.default_rng(seed)
    H = cap + face
    out = np.zeros((H + below, W, 4), np.uint8)
    # the top: one row of long slabs, the lightest tone of the wall
    ids_c = _courses(W, cap, rng, (cap, cap), (24, 46), seed + 100, wobble=0.6)
    rgb_c, j_c, r_c, t_c = _stone(ids_c, rng, seed + 100, 3.0, spread=0.3, lit_k=0.3, cracks=0.1, wear=wear)
    rgb_c[cap - 1, :] = PAL[5]  # the lit front lip of the wall's top
    rgb_c[cap - 2, :] = np.where((np.arange(W) % 7 == 0)[:, None], PAL[4], PAL[5])
    out[:cap, :, :3] = rgb_c
    out[:cap, :, 3] = 255
    # the face
    ids_f = _courses(W, face, rng, (13, 20), (24, 54), seed)

    def grime(xx, yy):
        g = -np.clip((yy - (face - 12)) / 12.0, 0, 1) * 0.75 * wear.grime  # the foot of the wall sinks into shade
        g -= np.clip((5 - yy) / 5.0, 0, 1) * 0.7 * wear.grime  # just under the overhang of the top
        g -= (np.clip((10 - xx) / 10.0, 0, 1) * 0.5 + np.clip((xx - (W - 10)) / 10.0, 0, 1) * 0.5) * wear.grime  # the corners
        for sx in (37, 96, 148, 205, 253):  # damp streaks running down from a joint
            run = np.clip(1.0 - np.abs(xx - (sx + 2.0 * np.sin(yy * 0.2 + sx))) / 1.6, 0, 1) * np.clip((yy - 4) / 7.0, 0, 1) * np.clip(1.0 - (yy - 4) / 36.0, 0, 1)
            g -= run * 1.1 * wear.stains * (_fbm(sx, yy * 0.2, 3) > 0.35)
        return g

    rgb_f, j_f, r_f, t_f = _stone(ids_f, rng, seed, 2.25, spread=0.4, lit_k=0.42, grime=grime, damp=((266, face - 4, 36, 12),), wear=wear)
    spots = list(wear.moss_spots) if wear.moss_spots is not None else auto_spots(W, face, seed, wear.moss, defaults=((268, face - 3, 30, 9), (22, face - 2, 14, 6)), bottom=0.7)
    rgb_f = moss_pass(rgb_f, j_f, r_f, wear, spots, seed, _hash, _fbm, down_hang=True)
    # patches of old lime wash that hold on in the lee: lighter, speckled, torn at the edge
    yy, xx = np.mgrid[0:face, 0:W].astype(float)
    wash_k = wear.wash ** 0.5
    patches = [(118, 22, 20, 12), (226, 30, 15, 9)] if wear.wash > 0 else []
    wrng = np.random.default_rng(seed + 55)
    for _ in range(int(round(max(wear.wash - 1.0, 0.0) * 3))):
        patches.append((wrng.uniform(10, W - 10), wrng.uniform(8, face - 12), wrng.uniform(10, 22), wrng.uniform(6, 12)))
    for px, py, rx, ry in patches:
        rx, ry = rx * wash_k, ry * wash_k
        d = np.hypot((xx - px) / rx, (yy - py) / ry) + (_fbm(xx * 0.2, yy * 0.2, seed + 40) - 0.5) * 0.7
        wash = (d < 1.0) & (_hash(xx, yy, seed + 41) < (1.0 - d) * 1.1) & ~j_f
        rgb_f[wash] = PAL[np.clip(t_f + 1, 1, 5)][wash]
    out[cap:H, :, :3] = rgb_f
    out[cap:H, :, 3] = 255
    out[cap, :, :3] = PAL[0]  # the shadow line under the top's lip
    for k, a in enumerate((96, 62, 34, 14)[:below]):  # the contact shadow on the floor
        out[H + k, :, :3] = (10, 6, 22)
        out[H + k, :, 3] = a
    if window is not None:
        window_cut(out, window)
    return out


def side_img(left, H=238, W=16, seed=33, wear=Wear()):
    """The top of a side wall seen from above: blocks end to end, the edge towards the room dark on the left wall and lit on the right one (light from the top left)."""
    rng = np.random.default_rng(seed + (0 if left else 7))
    ids = _courses(H, W, rng, (W, W), (22, 42), seed + 50, wobble=0.5)  # built along x then turned
    ids = ids.T.copy()  # (H, W)
    rgb, joint, rim, t = _stone(ids, rng, seed, 2.8, spread=0.3, lit_k=0.3, cracks=0.1, wear=wear)
    out = np.zeros((H, W, 4), np.uint8)
    out[..., :3] = rgb
    out[..., 3] = 255
    if left:
        out[:, W - 1, :3] = PAL[0]  # the room side of the left wall is in its own shadow
        out[:, 0, :3] = PAL[5]
    else:
        out[:, 0, :3] = PAL[5]
        out[:, W - 1, :3] = PAL[1]
    return out


def front_img(W=304, cap=14, face=22, gap=(208, 256), seed=45, wear=Wear()):
    """The south wall: its lit top and its outer face (two courses), the doorway cut out (alpha 0)."""
    rng = np.random.default_rng(seed)
    H = cap + face
    out = np.zeros((H, W, 4), np.uint8)
    ids_c = _courses(W, cap, rng, (cap, cap), (24, 46), seed + 100, wobble=0.5)
    rgb_c, *_ = _stone(ids_c, rng, seed + 100, 3.0, spread=0.3, lit_k=0.3, cracks=0.1, wear=wear)
    rgb_c[cap - 1, :] = PAL[5]
    out[:cap, :, :3] = rgb_c
    ids_f = _courses(W, face, rng, (10, 12), (24, 54), seed)
    rgb_f, j, r, t = _stone(ids_f, rng, seed, 2.4, spread=0.4, lit_k=0.4, cracks=0.1,
                            grime=lambda xx, yy: -np.clip((yy - (face - 7)) / 7.0, 0, 1) * 0.6 * wear.grime, wear=wear)
    out[cap:, :, :3] = rgb_f
    out[cap, :, :3] = PAL[0]
    out[..., 3] = 255
    out[:, gap[0]:gap[1], 3] = 0
    out[:, gap[0] - 1, :3] = PAL[0]  # left jamb faces east, away from the light: dark
    out[:, gap[1], :3] = PAL[5]  # right jamb faces the light: a bright edge
    out[:, gap[1] + 1, :3] = PAL[4]
    return out
