"""Clean pixel eyes for Ellie's sheets (and no painted mouth).

The ellipsoid renderer paints her eyes as decals on the 3D head. At 48 x 56 px they came out as smeared, uneven violet blobs that
changed shape from frame to frame (a dark bar on the head's edge in the three-quarter views, one eye bigger than the other, a
crooked lid, the eyes drifting apart and together). This pass removes the blobs and the painted mouth (skin where they were; the
decal's violet outline becomes skin outline) and draws one fixed, slim pixel eye per visible eye (approved look "A", 2026-11-12):

    D    D = lash/lid (darkest eye colour)
    I    I = iris

WHERE comes from the model (`stamp`): art_hero3d puts both eye centres and their looking directions on the head (`Model.eyes`,
`face_eyes`). An eye is drawn when it looks at the camera (facing > FACING_MIN): front and three-quarter views show two, profiles
one, back views none. Both share the row of the nearer eye (a turned head's far eye may sit one row higher, as the perspective puts it) and stand a
fixed distance apart: 2 skin pixels between them from the
front, 1 when the head is turned (SEP_FRONT decides). In a profile the eye is moved off the head's edge. The iris is drawn only on
face (the fringe still covers it); its lash may lie under the fringe's tip (it reads as the fringe's shadow). The silhouette never
changes (the blood and jewellery maps stay valid).

art_hero3d.frame() runs it on every frame it renders (only while the eye ramp is Ellie's). For finished sheets:
    py -3 tools/hero_face.py            (all assets/characters/player*.png colour sheets, in place: the sheets of
                                         art_hero_jewelry.sheets(), combo, cast, drink and feed by the model, the others by `tidy`, a guess from the image)
    py -3 tools/hero_face.py a.png ...  (just these)
Run it on freshly rendered (or the original) sheets.
"""
import sys
from collections import Counter
from pathlib import Path

import numpy as np

EYE = [(0x2a, 0x1c, 0x52), (0x5f, 0x3b, 0xc9), (0xa7, 0x7b, 0xff), (0xef, 0xe6, 0xff)]  # = art_hero3d RAMPS[EYE]
SKIN = [(0xd2, 0xa2, 0x9c), (0xef, 0xc3, 0xb6), (0xfa, 0xdf, 0xd2), (0xff, 0xf2, 0xe8),  # current porcelain-rose skin
        (0xd7, 0x9a, 0x88), (0xef, 0xc0, 0xa8), (0xf9, 0xdc, 0xc6), (0xff, 0xf1, 0xe4),  # legacy skin (for standalone re-runs)
        (0xd5, 0x8a, 0x86), (0xe5, 0xa3, 0x9b), (0xf2, 0xba, 0xb0), (0xf8, 0xcf, 0xc6)]  # blush
HAIR = [(0x8f, 0x84, 0xc2), (0xbd, 0xb3, 0xe4), (0xe9, 0xe3, 0xf7), (0xff, 0xfa, 0xf0)]  # = art_hero3d RAMPS[HAIR]
MOUTH = [(0x84, 0x40, 0x5a), (0xb2, 0x58, 0x73), (0xd9, 0x8a, 0xa0), (0xf0, 0xb2, 0xc2)]  # = art_hero3d RAMPS[MOUTH]
LASH, IRIS = EYE[0], EYE[1]
STAMP = [LASH, IRIS]  # one column, top to bottom
GAP = 2  # skin pixels between the two eyes of a face seen from the front
GAP_TURNED = 1  # ... of a face turned three-quarters (the far eye near the head's edge): foreshortened
FACING_MIN = 0.12  # an eye is drawn when it looks at the camera at least this much (profile far eye about -0.4, three-quarter far eye 0.28)
SEP_FRONT = 2.45  # projected distance (px) between the eye centres from which the face counts as seen from the front


def _ink(c, k=0.55):  # = art_hero3d.ink_color
    return (int(c[0] * k), int(c[1] * k * 0.95), int(c[2] * k))


SKIN_INK = (0x52, 0x36, 0x44)
FACE_INK = [_ink(EYE[0]), _ink(MOUTH[0]), _ink(SKIN[4], 0.5), _ink(SKIN[8])]  # outline pixels of eye, mouth and blush decals -> skin outline


def _mask(rgb: np.ndarray, colors) -> np.ndarray:
    m = np.zeros(rgb.shape[:2], bool)
    for c in colors:
        m |= np.all(rgb == np.array(c, np.uint8), axis=-1)
    return m


def _clusters(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """4-connected groups of eye pixels."""
    seen = np.zeros_like(mask)
    out = []
    h, w = mask.shape
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        stack, group = [(y, x)], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            group.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        out.append(group)
    return out


def _skin_fill(rgb, skin, pts, h, w):
    around = Counter()
    for y, x in pts:
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (2, 0), (-2, 0)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and skin[ny, nx]:
                around[tuple(int(v) for v in rgb[ny, nx])] += 1
    return around.most_common(1)[0][0] if around else SKIN[2]


def _near_skin(skin, pts, h, w):
    return any(0 <= y + dy < h and 0 <= x + dx < w and skin[y + dy, x + dx]
               for y, x in pts for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))


def _clean(arr: np.ndarray):
    """Removes the mouth and the eye blobs (skin where they were), turns their outlines into skin outline.
    Returns (arr, face): face = pixels that are face (skin or old eye) and may carry an eye."""
    arr = arr.copy()
    rgb = arr[..., :3].copy()
    alpha = arr[..., 3]
    h, w = alpha.shape
    solid = alpha == 255
    skin = _mask(rgb, SKIN) & solid
    eye = _mask(rgb, EYE) & solid
    face = skin | eye
    for colors, limit in ((MOUTH, 8), (EYE, 12)):
        m = _mask(rgb, colors) & solid
        for g in _clusters(m):
            if len(g) <= limit and _near_skin(skin, g, h, w):
                fill = _skin_fill(rgb, skin, g, h, w)
                for y, x in g:
                    arr[y, x, :3] = fill
    arr[_mask(rgb, FACE_INK), :3] = SKIN_INK
    return arr, face


def stamp(arr: np.ndarray, eyes) -> np.ndarray:
    """arr: one frame (H, W, 4) RGBA as rendered; eyes: [(x, y, facing[, closed, up_x, up_y]), ...] in frame pixels."""
    out, face = _clean(arr)
    h, w = face.shape
    alpha = arr[..., 3]
    hair = _mask(arr[..., :3], HAIR) & (alpha == 255)
    seen = sorted([e for e in eyes if e[2] > FACING_MIN], key=lambda e: -e[2])
    if not seen:
        return out
    near = seen[0]
    closed = bool(near[3]) if len(near) > 3 else False
    up_x = float(near[4]) if len(near) > 4 else 0.0
    up_y = float(near[5]) if len(near) > 5 else -1.0

    def edge(x, y):
        return not (0 <= x < w and 0 <= y < h) or alpha[y, x] < 255 or not (face[y, x] or hair[y, x])

    # Lying / prone pose where the head's crown points sideways on screen rather than up: orient the eye with the head.
    if abs(up_x) > abs(up_y) * 1.15:
        ux = -1 if up_x < 0 else 1  # step toward the crown / brow
        for idx, e in enumerate(seen[:2]):
            ex, ey = int(np.floor(e[0])), int(np.floor(e[1]))
            if idx == 1 and abs(ey - int(np.floor(near[1]))) < 2:
                ey = int(np.floor(near[1])) + (2 if e[1] > near[1] else -2)
            for dy in (0, -1, 1):
                ry = ey + dy
                if 0 <= ex < w and 0 <= ry < h and face[ry, ex]:
                    if closed:
                        out[ry, ex, :3] = LASH
                    else:
                        out[ry, ex, :3] = IRIS
                        if 0 <= ex + ux < w and (face[ry, ex + ux] or hair[ry, ex + ux]):
                            out[ry, ex + ux, :3] = LASH
                    break
        return out

    row = int(np.floor(near[1] + 0.15)) - 1
    # Keep the iris comfortably on skin (not clipped under low fringe and not hanging off the chin)
    xn = int(np.floor(near[0]))
    if 0 <= xn < w:
        if 0 <= row + 1 < h and not face[row + 1, xn] and 0 <= row + 2 < h and face[row + 2, xn]:
            row += 1
        elif 0 <= row + 1 < h and face[row + 1, xn] and (row + 2 >= h or not face[row + 2, xn]) and row - 1 >= 0 and face[row, xn]:
            row -= 1

    cols = [(xn, row)]
    if len(seen) > 1:
        far = seen[1]
        step = 1 if far[0] > near[0] else -1
        turned = abs(far[0] - near[0]) < SEP_FRONT or far[2] < 0.72
        span = (GAP_TURNED if turned else GAP) + 1
        if not turned:
            xm = 0.5 * (near[0] + far[0])
            x_left = int(np.floor(xm - span * 0.5 + 0.5))
            xn = x_left if step > 0 else x_left + span
        xf = xn + step * span
        # Ensure both eyes land on face skin and neither sits directly on the outer silhouette column when the face has room
        if (not (0 <= xf < w and 0 <= row + 1 < h and face[row + 1, xf]) or edge(xf + step, row + 1)) and not edge(xn - step, row + 1) and 0 <= xn - step < w and 0 <= xf - step < w and face[row + 1, xn - step] and face[row + 1, xf - step]:
            xn -= step
            xf -= step
        elif (not (0 <= xn < w and 0 <= row + 1 < h and face[row + 1, xn]) or edge(xn - step, row + 1)) and not edge(xf + step, row + 1) and 0 <= xf + step < w and 0 <= xn + step < w and face[row + 1, xf + step] and face[row + 1, xn + step]:
            xn += step
            xf += step
        # Keep both eyes level on the same row unless the head itself is strongly rolled sideways
        rf = row
        if abs(up_x) > 0.38:
            own = int(np.floor(far[1] + 0.15)) - 1
            if abs(own - row) == 1 and 0 <= own + 1 < h and 0 <= xf < w and face[own + 1, xf]:
                rf = own
        cols = [(xn, row), (xf, rf)]
    else:  # profile: sit 1 px inside the front face contour, never on the outer column
        for d in (1, -1):
            if edge(xn + d, row + 1) and not edge(xn - d, row + 1) and 0 <= xn - d < w and face[row + 1, xn - d]:
                cols[0] = (xn - d, row)
                break
    for x, r in cols:
        if not (0 <= x < w and 0 <= r + 1 < h) or not face[r + 1, x]:
            continue
        if closed:
            out[r + 1, x, :3] = LASH
            continue
        out[r + 1, x, :3] = IRIS
        if 0 <= r < h and (face[r, x] or hair[r, x]):
            out[r, x, :3] = LASH
    return out


def tidy(arr: np.ndarray, sector=None) -> np.ndarray:
    """arr: (H, W, 4) uint8 RGBA (one frame or a strip of frames). Returns a tidied copy.
    sector (0 E, 1 SE, 2 S, 3 SW, 4 W, 5 NW, 6 N, 7 NE), when known, fixes how many eyes the face shows: S two (gap 2),
    SE/SW two (gap 1; the far eye is added on the far side when the render lost it), E/W one, the back views none.
    Without it the eyes are guessed from what was rendered."""
    arr = arr.copy()
    rgb, alpha = arr[..., :3], arr[..., 3]
    h, w = alpha.shape
    solid = alpha == 255
    skin = _mask(rgb, SKIN) & solid
    # the mouth goes: skin where it was
    mouth = _mask(rgb, MOUTH) & solid
    for g in _clusters(mouth):
        if len(g) <= 8 and _near_skin(skin, g, h, w):
            fill = _skin_fill(rgb, skin, g, h, w)
            for y, x in g:
                arr[y, x, :3] = fill
    skin = _mask(arr[..., :3], SKIN) & solid
    eye = _mask(rgb, EYE) & solid
    if not eye.any():
        return arr
    groups = []
    for g in _clusters(eye):
        if len(g) > 12 or not _near_skin(skin, g, h, w):
            continue
        ys = [p[0] for p in g]
        xs = [p[1] for p in g]
        cx = sum(xs) / len(xs)
        groups.append({"px": g, "top": min(ys), "cx": cx, "cy": sum(ys) / len(ys), "n": len(g), "x": int(np.floor(cx + 0.5))})
    if not groups:
        return arr
    paintable = eye | skin
    ink_face = _mask(rgb, FACE_INK)
    hair = _mask(rgb, HAIR) & solid
    # the decals' own outline (where an eye poked out of the head) becomes the skin's outline
    arr[ink_face, :3] = SKIN_INK

    def fits(x, y):
        return 0 <= x < w and 0 <= y < h and paintable[y, x]

    def edge(x, y):
        if not (0 <= x < w and 0 <= y < h) or alpha[y, x] < 255:
            return True
        return not (paintable[y, x] or hair[y, x])  # an outline, the collar ...

    def ok(x, y):  # both pixels on the face, with face (or hair) on either side, never the head's edge
        return all(fits(x, y + r) and not edge(x - 1, y + r) and not edge(x + 1, y + r) for r in (0, 1))

    # eyes of one face (close together) share one top row: the lower of their tops (above it the fringe may already cover one)
    for g in groups:
        mates = [o for o in groups if abs(o["cx"] - g["cx"]) <= 7 and abs(o["cy"] - g["cy"]) <= 3]
        g["row"] = max(o["top"] for o in mates)
    if sector in (5, 6, 7):
        for g in groups:
            g["hidden"] = True
    elif sector in (0, 4):  # profile: one eye, the biggest of each face
        for g in groups:
            mates = [o for o in groups if o["row"] == g["row"] and abs(o["cx"] - g["cx"]) <= 7]
            if max(mates, key=lambda o: (o["n"], -abs(o["cx"]))) is not g:
                g["hidden"] = True
    # off the face's edge
    for g in groups:
        if ok(g["x"], g["row"]):
            continue
        for d in (-1, 1, -2, 2):
            if ok(g["x"] + d, g["row"]):
                g["x"] += d
                break
    # three-quarter views: the far eye the render lost comes back on the far side (SE: right, SW: left)
    if sector in (1, 3):
        side = 1 if sector == 1 else -1
        for g in [o for o in groups if not o.get("hidden")]:
            if any(o is not g and not o.get("hidden") and o["row"] == g["row"] and abs(o["x"] - g["x"]) <= 7 for o in groups):
                continue
            def under_fringe(x, y):  # the iris on the face; its lash may lie under the fringe (it reads as the fringe's shadow)
                return fits(x, y + 1) and 0 <= x < w and (paintable[y, x] or hair[y, x]) and not edge(x, y + 1)
            x, row = g["x"], g["row"]
            for near, far, test in ((x, x + 2 * side, ok), (x, x + 2 * side, under_fringe), (x - side, x + side, under_fringe)):
                if test(far, row) and (near == x or under_fringe(near, row)):
                    g["x"] = near
                    g["fringe"] = near != x
                    groups.append({"px": [], "top": row, "cx": float(far), "cy": g["cy"], "n": 0, "x": far, "row": row, "fringe": True, "fixed": True})
                    g["fixed"] = True
                    break
    # the same distance between the two eyes of every face
    for a in groups:
        for b in groups:
            if a is b or a.get("hidden") or b.get("hidden") or a.get("fixed") or b.get("fixed") or a["row"] != b["row"] or not (a["x"], id(a)) < (b["x"], id(b)) or b["x"] - a["x"] > 8:
                continue
            gap = b["x"] - a["x"] - 1
            turned = sector in (1, 3) if sector is not None else any(edge(g["x"] + d, g["row"] + r) for g, d in ((a, -1), (a, -2), (b, 1), (b, 2)) for r in (0, 1))
            want = GAP_TURNED if turned else GAP
            if gap == want:
                continue
            shift = want - gap  # + = further apart
            small, big = (a, b) if a["n"] <= b["n"] else (b, a)
            moved = False
            for mover in (small, big):
                nx = mover["x"] + (shift if mover is b else -shift)
                if ok(nx, mover["row"]):
                    mover["x"] = nx
                    moved = True
                    break
            if not moved and b["x"] - a["x"] - 1 < GAP_TURNED:  # no room for two eyes: the far (smaller) one is hidden by the turn
                small["hidden"] = True
                continue
            if not moved:  # split the move between both
                for mover in (a, b):
                    step = (1 if mover is b else -1) * (1 if shift > 0 else -1)
                    if b["x"] - a["x"] - 1 != want and ok(mover["x"] + step, mover["row"]):
                        mover["x"] += step
    # clear the old blobs, then stamp
    for g in groups:
        fill = _skin_fill(rgb, skin, g["px"], h, w)
        for y, x in g["px"]:
            arr[y, x, :3] = fill
    for g in groups:
        if g.get("hidden"):
            continue
        for r, col in enumerate(STAMP):
            y, x = g["row"] + r, g["x"]
            if fits(x, y) or (r == 0 and g.get("fringe") and 0 <= x < w and 0 <= y < h and hair[y, x]):
                arr[y, x, :3] = col
                arr[y, x, 3] = 255
    return arr


def tidy_rows(rows, eyes=None):
    """For art_hero3d.to_pixels: a list of rows of RGBA tuples in, the same out (eyes from art_hero3d.face_eyes, else a guess)."""
    arr = np.asarray(rows, dtype=np.uint8)
    out = stamp(arr, eyes) if eyes is not None else tidy(arr)
    return [[tuple(int(v) for v in out[y, x]) for x in range(out.shape[1])] for y in range(out.shape[0])]


# sheets whose rows are the eight facings (E SE S SW W NW N NE), repeated (the main sheet has 16 rows: standing, crouched)
SECTOR_ROWS = {"player": 16, "player_attack": 8, "player_cast": 8, "player_climb": 8, "player_combo": 8, "player_drink": 8,
               "player_eat": 8, "player_feed": 8, "player_fish": 8, "player_heavy": 8, "player_pick": 8, "player_pull": 8,
               "player_rest": 8, "player_sit": 8, "player_standby": 8, "player_step": 8, "player_stumble": 8, "player_swim": 8,
               "player_swim_under": 8, "player_touch": 8}


FRAME_W = {"player_swim": 64, "player_swim_under": 64, "player_climb": None, "player_rest": None, "player_sit": None, "player_stumble": None}


def _borrow(strip: np.ndarray, fw: int, sector: int) -> None:
    """A facing that shows eyes, but a frame the render gave none (the fringe swung over a narrow face): copy the eyes of the
    next frame at the same place when that is bare skin here too, so an idle or walk loop never blinks its eyes away."""
    want = {0: 1, 4: 1, 1: 2, 3: 2, 2: 2}.get(sector, 0)
    if not want:
        return
    h = strip.shape[0]
    n = strip.shape[1] // fw
    lash = np.all(strip[..., :3] == np.array(LASH, np.uint8), axis=-1)
    skin = _mask(strip[..., :3], SKIN) & (strip[..., 3] == 255)
    count = [len(set(np.nonzero(lash[:, c * fw:(c + 1) * fw])[1].tolist())) for c in range(n)]
    for c in range(n):
        if count[c] >= want:
            continue
        for d in (-1, 1, -2, 2):
            o = c + d
            if not (0 <= o < n) or count[o] < want:
                continue
            ys, xs = np.nonzero(lash[:, o * fw:(o + 1) * fw])
            spots = [(y, x) for y, x in zip(ys, xs)]
            if all(y + 1 < h and skin[y, c * fw + x] and skin[y + 1, c * fw + x] for y, x in spots if not lash[y, c * fw + x]):
                for y, x in spots:
                    strip[y, c * fw + x, :3] = LASH
                    strip[y + 1, c * fw + x, :3] = IRIS
                count[c] = want
                break


# animation cycles (column ranges) of a sheet: one facing shows the same number of eyes through a whole cycle
CYCLES = {"player": [(0, 6), (6, 12), (12, 16), (16, 22)]}


def _even_cycles(strip: np.ndarray, fw: int, sector: int, cycles) -> None:
    """Within a cycle of a three-quarter row, frames that show two eyes while most show one lose the far eye."""
    if sector not in (1, 3):
        return
    lash = np.all(strip[..., :3] == np.array(LASH, np.uint8), axis=-1)
    skin = _mask(strip[..., :3], SKIN) & (strip[..., 3] == 255)
    far = 1 if sector == 1 else -1
    for a, b in cycles:
        cols = {c: sorted(set(np.nonzero(lash[:, c * fw:(c + 1) * fw])[1].tolist())) for c in range(a, b)}
        ones = sum(1 for xs in cols.values() if len(xs) == 1)
        if ones * 2 <= (b - a):
            continue
        for c, xs in cols.items():
            if len(xs) < 2:
                continue
            x = c * fw + (xs[-1] if far > 0 else xs[0])
            for y in np.nonzero(lash[:, x])[0]:
                for yy in (y, y + 1):
                    around = [tuple(int(v) for v in strip[yy, x + d, :3]) for d in (-far, -2 * far) if skin[yy, x + d]]
                    strip[yy, x, :3] = around[0] if around else SKIN[2]


def tidy_sheet(arr: np.ndarray, name: str) -> np.ndarray:
    rows = SECTOR_ROWS.get(name)
    if not rows:
        return tidy(arr)
    fh = arr.shape[0] // rows
    fw = FRAME_W.get(name, 48)
    out = arr.copy()
    for r in range(rows):
        strip = tidy(arr[r * fh:(r + 1) * fh], r % 8)
        if fw:
            _borrow(strip, fw, r % 8)
            if name in CYCLES:
                _even_cycles(strip, fw, r % 8, CYCLES[name])
        out[r * fh:(r + 1) * fh] = strip
    return out


MODELS = {}


def model_sheets():
    """{sheet stem: (frame w, frame h, cols, [frame() args in sprite order])} of the sheets whose frames we can rebuild as models."""
    import art_hero3d as hero
    import art_hero_jewelry as jewel
    import art_hero_cast as cast
    import art_hero_combo as combo
    names = {"main": "player"}
    out = {names.get(name, "player_" + name): (hero.FW, hero.FH, cols, frames) for name, (cols, rows, frames) in jewel.sheets().items()}

    def legs(sector, pose, v):  # leg variant 0 planted, 1-6 the walk cycle's phases (as the attack sheets)
        return (sector, 0.0, "attack", False, pose) if v == 0 else (sector, (v - 1) / hero.WALK_FRAMES, "walk", False, dict(pose, pz=0.0))

    # same frame order as the generators (art_hero_combo.render_frames, art_hero_cast.render, art_hero3d.pick_sheet)
    frames = [legs(sector, pose, v) for sector in range(8) for block in range(combo.BLOCKS) for v in range(hero.ATTACK_LEGS) for pose in combo.COMBO_POSES[block]]
    out["player_combo"] = (hero.FW, hero.FH, len(frames) // 8, frames)
    frames = [(sector, 0.0, "attack", False, hero.timeline_pose(keys, (i + 0.5) / hero.PICK_FRAMES)) for sector in range(8) for _n, keys in cast.CLIPS for i in range(hero.PICK_FRAMES)]
    out["player_cast"] = (hero.FW, hero.FH, len(frames) // 8, frames)
    for name, keys, variants in (("player_drink", hero.DRINK_KEYS, hero.ATTACK_LEGS), ("player_feed", hero.FEED_KEYS, 1)):
        frames = [legs(sector, hero.timeline_pose(keys, (i + 0.5) / hero.PICK_FRAMES), v) for sector in range(8) for v in range(variants) for i in range(hero.PICK_FRAMES)]
        out[name] = (hero.FW, hero.FH, len(frames) // 8, frames)
    return out


def eyes_of(args):
    import math
    import art_hero3d as hero
    sector, t, mode, crouch, pose = args
    yaw = math.pi / 2 - sector * math.pi / 4
    return hero.face_eyes(hero.build(t, mode, crouch, pose), yaw)


def stamp_sheet(arr: np.ndarray, fw: int, fh: int, cols: int, frames) -> np.ndarray:
    out = arr.copy()
    for i, args in enumerate(frames):
        r, c = divmod(i, cols)
        tile = arr[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
        out[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = stamp(tile, eyes_of(args))
    return out


def main(paths):
    from PIL import Image
    root = Path(__file__).resolve().parent.parent / "assets" / "characters"
    if not paths:
        paths = [p for p in sorted(root.glob("player*.png")) if not p.stem.endswith("_blood")]
    if not MODELS:
        MODELS.update(model_sheets())
    for p in paths:
        p = Path(p)
        im = np.array(Image.open(p).convert("RGBA"))
        if p.stem in MODELS:
            fw, fh, cols, frames = MODELS[p.stem]
            out = stamp_sheet(im, fw, fh, cols, frames)
        else:
            out = tidy_sheet(im, p.stem)
        changed = int((out != im).any(-1).sum())
        Image.fromarray(out, "RGBA").save(p)
        print(f"{p.name}: {changed} px")


if __name__ == "__main__":
    main(sys.argv[1:])
