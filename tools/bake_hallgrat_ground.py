#!/usr/bin/env python3
"""The paved ground of Hallgrat (docs/stadt_westen_konzept.md stage 3a): squares and streets from data/hallgrat.json `paving`, laid only on the
real terraces (floor tiles of their own level, a few px back from every contour, never on a stair or ramp: the relief draws those).

Styles:
  ring   the forum: elliptic courses of cut setts round the Wächterin, her own flagstone bed stays free (`hole`), a darker band of kerb
         stones at the rim; the 3/4 view squashes the circles like the statue's bed
  setts  streets and lanes: rows of small cut stones in running bond, lit from the upper left, a kerb of larger stones along the edges
  flags  the old squares of the Fuß: irregular flagstones (the world's stone fields), more grass and moss with `wear`
`wear` 0..1 takes stones away, lets grass and moss in and frays the edge (the Stille is kept up, the Fuß is half abandoned).

Writes assets/world/ground/hallgrat_<id>.png + _mask.png (surface stone), puts them into data/ground_baked.json `decals` (replacing older
hallgrat_ ones) and the paved tiles into `hallgrat_clear` (row runs [y, x0, x1]), which the world keeps free of generated props.
    py -3 tools/bake_hallgrat_ground.py [preview.png]      then      Godot --headless --path . --import
Needs numpy and PIL."""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_ground as bg
from world_data import load_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# the town's own cut stone: the same ramp as its masonry walls and stairs (relief.gdshader MASON), so street, stair and wall are one stone
STONE = np.array([[0.0980, 0.0902, 0.1765], [0.1608, 0.1490, 0.2706], [0.2431, 0.2275, 0.3686], [0.3451, 0.3255, 0.4824],
                  [0.4706, 0.4471, 0.6078], [0.6353, 0.6118, 0.7569]], dtype=np.float32) * 255.0
MORTAR = np.array(bg.MORTAR[:3], dtype=np.float32)
MOSS = np.array([c[:3] for c in bg.MOSS], dtype=np.float32)
GRASS = np.array([c[:3] for c in bg.MEADOW_HI], dtype=np.float32)
BAYER = bg.BAYER


def hash2(a, b, seed):
    v = (a.astype(np.int64) * 374761393 + b.astype(np.int64) * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0


def floor_mask(X, Y, relief):
    """Pixels on plain floor of a single level, at least 4 px from any change of level (the smooth contour the game draws)."""
    tx, ty = (X // 16).astype(int), (Y // 16).astype(int)
    kind = relief[..., 1][ty, tx] & 15
    land = relief[..., 3][ty, tx] > 0
    lvl = sum((bg.relief_field(c, X, Y) > 0.5).astype(int) for c in range(3))
    ok = land & (kind == 0) & (lvl == relief[..., 0][ty, tx])
    for dx, dy in ((4, 0), (-4, 0), (0, 4), (0, -6)):
        lv2 = sum((bg.relief_field(c, X + dx, Y + dy) > 0.5).astype(int) for c in range(3))
        ok &= lv2 == lvl
    near = near_stairs(X, Y, relief)
    return ok | (near & land & (kind != 1)), near


def near_stairs(X, Y, relief):
    """Pixels on or right beside a stair or ramp (one tile round it): the street runs up to the stair's first and last step (the relief draws
    the stair itself over the paving), so no strip of grass is left between them."""
    tx, ty = (X // 16).astype(int), (Y // 16).astype(int)
    conn = np.zeros(tx.shape, dtype=bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            k = relief[..., 1][np.clip(ty + dy, 0, 1099), np.clip(tx + dx, 0, 1099)] & 15
            conn |= (k >= 2) & (k <= 4)
    return conn


def shade(tone):
    return STONE[np.clip(np.rint(tone).astype(int), 0, 5)]


EARTH = np.array([c[:3] for c in bg.PATH], dtype=np.float32)


def finish(sid, joint, X, Y, seed, worn=None, crack=None):
    """Colours a field of cut stones: `sid` (0..1 per stone), `joint` (the gaps). Every stone gets its own tone, a lit rim where a joint lies
    above or left of it and a dark one below or right (world light from the upper left, whatever way the stones run), a grain of 2 px
    speckles, now and then a sunken dark stone or a crack; the joints are mortar, earth or a blade of grass. `worn`: 0..1 lighter, smoother."""
    grain = hash2(np.floor(X / 2.0), np.floor(Y / 2.0), seed + 11)
    tone = 1.85 + sid * 1.55 + (grain - 0.5) * 0.55 + (BAYER[Y.astype(int) % 4, X.astype(int) % 4] - 0.5) * 0.35
    if worn is not None:
        tone = tone + worn * 0.6
    tone = np.where(sid < 0.07, tone - 0.9, tone)  # a sunken stone
    up = np.zeros_like(joint)
    up[1:] = joint[:-1]
    left = np.zeros_like(joint)
    left[:, 1:] = joint[:, :-1]
    down = np.zeros_like(joint)
    down[:-1] = joint[1:]
    right = np.zeros_like(joint)
    right[:, :-1] = joint[:, 1:]
    tone = np.where(up | left, tone + 0.95, tone)
    tone = np.where((down | right) & ~(up | left), tone - 0.75, tone)
    col = shade(tone)
    if crack is not None:
        col[crack & ~joint] = STONE[0]
    jn = hash2(np.floor(X / 3.0), np.floor(Y / 3.0), seed + 12)
    jc = np.where((jn > 0.62)[..., None], EARTH[0], MORTAR)
    jc = np.where((jn > 0.9)[..., None], GRASS[2], jc)
    return np.where(joint[..., None], jc, col)


def setts_field(u, v, seed, length=7.0, base=8.0):
    """Setts in running bond in a street's own frame: rows across the street (u = along, v = across), stones of 8-12 px, now and then two
    stones as one long one; the rows wobble a little."""
    wob = (hash2(np.floor(v / 5.0), v * 0 + 4, seed) - 0.5) * 1.4
    uu = u + wob
    course = np.floor(uu / length)
    cu = uu - course * length
    width = base + np.floor(hash2(course, course * 0 + 2, seed) * 5.0)
    off = hash2(course, course * 0 + 3, seed) * width
    sv = np.floor((v + off) / width)
    cv = (v + off) - sv * width
    merged = (hash2(np.floor(sv / 2.0), course, seed + 7) > 0.8) & (np.mod(sv, 2) > 0.5)
    stone = np.where(merged, sv - 1, sv)
    sid = hash2(stone, course, seed + 1)
    joint = (cu < 1.0) | ((cv < 1.0) & ~merged)
    a = hash2(stone, course, seed + 9) * math.pi
    crack = (sid > 0.93) & (np.abs((cu - length / 2) * np.cos(a) + (cv - width / 2) * np.sin(a)) < 0.5)
    return sid, joint, crack


def ring_field(r, ang, r0, seed, step=7.0, size=11.0):
    course = np.floor((r - r0) / step)
    within = np.mod(r - r0, step)
    rad = r0 + (course + 0.5) * step
    n = np.maximum(5, np.round(2 * math.pi * np.maximum(rad, 1.0) / size))
    u = (ang / (2 * math.pi) + 0.5) * n + hash2(course, course * 0 + 1, seed) * 3.0
    stone = np.floor(u)
    along = np.mod(u, 1.0) * (2 * math.pi * np.maximum(r, 1.0) / n)
    sid = hash2(stone, course, seed + 5)
    joint = (within < 1.0) | (along < 1.0)
    crack = (sid > 0.94) & (np.abs(within - step / 2 - (along - 5.0) * 0.4) < 0.5)
    return sid, joint, crack, course


def paint_setts(X, Y, u, v, edge, half, seed):
    """A street: setts across it, worn smooth along its middle, a kerb of long stones along both edges."""
    sid, joint, crack = setts_field(u, v, seed)
    worn = np.clip(1.0 - np.abs(v) / max(half * 0.55, 1.0), 0.0, 1.0)
    kerb = (edge < 4.5) & (half > 9.0)
    side = (v > 0).astype(float)
    ku = np.floor((u + side * 7.0) / 15.0)
    ksid = hash2(ku, side, seed + 21)
    kj = np.mod(u + side * 7.0, 15.0) < 1.0
    sid = np.where(kerb, ksid * 0.6, sid)
    joint = np.where(kerb, kj | ((edge > 3.8) & (edge < 4.5)), joint)
    col = finish(sid, joint, X, Y, seed, worn=np.where(kerb, 0.0, worn), crack=crack & ~kerb)
    return col, np.where(kerb, ksid, sid)


def paint_ring(X, Y, cx, cy, sq, seed, dais):
    """The forum: a dais of large wedge slabs under the statue, framed by a kerb of long dark stones (one low step), and round it the
    courses of setts; every fourth course is set in a darker stone."""
    dx, dy = X - cx, (Y - cy) / sq
    r = np.hypot(dx, dy)
    ang = np.arctan2(dy, dx)
    sid, joint, crack, course = ring_field(r, ang, dais + 6.0, seed)
    sid = np.where(np.mod(course, 4) == 3, sid * 0.45, sid)
    if dais > 0:
        dsid, djoint, dcrack, _ = ring_field(r, ang + 0.4, 14.0, seed + 30, step=16.0, size=26.0)
        inside = r < dais
        centre = r < 14.0
        sid = np.where(inside, 0.35 + dsid * 0.55, sid)
        joint = np.where(inside, djoint, joint)
        crack = np.where(inside, dcrack, crack)
        sid = np.where(centre, 0.95, sid)
        joint = np.where(centre, np.abs(r - 13.5) < 0.8, joint)
        k = (r >= dais) & (r < dais + 6.0)
        kn = max(8.0, round(2 * math.pi * (dais + 3.0) / 22.0))
        ku = (ang / (2 * math.pi) + 0.5) * kn
        sid = np.where(k, 0.12 + hash2(np.floor(ku), ku * 0 + 5, seed) * 0.25, sid)
        joint = np.where(k, (np.mod(ku, 1.0) * 2 * math.pi * (dais + 3.0) / kn < 1.0) | (r >= dais + 5.2), joint)
        crack = np.where(k, False, crack)
        worn = np.where(inside, 0.5, np.clip(1.0 - (r - dais) / 40.0, 0.0, 1.0) * 0.4)
    else:
        k = np.zeros(r.shape, dtype=bool)
        worn = None
    col = finish(sid, joint, X, Y, seed, worn=worn, crack=crack)
    col[k & (r < dais + 1.2)] = STONE[4]  # the lit top edge of the dais's step
    return col, sid


def paint_flags(X, Y, seed):
    col = np.zeros(X.shape + (3,), dtype=np.float32)
    ids = np.zeros(X.shape, dtype=np.float32)
    for j in range(X.shape[0]):
        for i in range(X.shape[1]):
            c = bg.flagstone(int(X[j, i]), int(Y[j, i]), seed)
            col[j, i] = c[:3]
            ids[j, i] = (bg.cell_of(int(X[j, i]) + seed * 5, int(Y[j, i]) + seed * 3)[0] % 997) / 997.0
    return col, ids


def simplify(pts, eps):
    """Douglas-Peucker: the routed ways go in tile steps, a street should not."""
    if len(pts) < 3:
        return pts
    (ax, ay), (bx, by) = pts[0], pts[-1]
    L = math.hypot(bx - ax, by - ay) or 1.0
    d = [abs((by - ay) * px - (bx - ax) * py + bx * ay - by * ax) / L for px, py in pts[1:-1]]
    i = int(np.argmax(d)) + 1
    if d[i - 1] <= eps:
        return [pts[0], pts[-1]]
    return simplify(pts[:i + 1], eps)[:-1] + simplify(pts[i:], eps)


def smooth_line(pts):
    """The street's centre line: the route without its tile steps, rounded through its corners (it is clipped to the floor anyway)."""
    keep = simplify(pts, 20.0)
    return [tuple(p) for p in bg.catmull(keep, step=4.0)] if len(keep) > 2 else keep


def bake(spec, town, relief, seed):
    style = spec["style"]
    wear = float(spec.get("wear", 0.2))
    pad = 12
    if style == "ring":
        cx, cy = spec["centre"][0] * 16 + 8.0, spec["centre"][1] * 16 + 8.0
        rx, ry = spec["radius"]
        x0, y0, x1, y1 = cx - rx - pad, cy - ry - pad, cx + rx + pad, cy + ry + pad
    elif "line" in spec or "way" in spec or "line_px" in spec:
        if "line_px" in spec:
            pts = [tuple(p_) for p_ in spec["line_px"]]
            pts = [tuple(p_) for p_ in bg.catmull(pts, step=3.0)] if len(pts) > 2 else pts
        else:
            line = spec.get("line") or next(w["line"] for w in town["ways"] if w["id"] == spec["way"])
            pts = smooth_line([(x * 16 + 8.0, y * 16 + 8.0) for x, y in line])
        half = spec.get("width", 36) / 2.0
        x0, y0 = min(p[0] for p in pts) - half - pad, min(p[1] for p in pts) - half - pad
        x1, y1 = max(p[0] for p in pts) + half + pad, max(p[1] for p in pts) + half + pad
    else:
        poly = [(x * 16.0, y * 16.0) for x, y in spec["poly"]]
        x0, y0 = min(p[0] for p in poly) - pad, min(p[1] for p in poly) - pad
        x1, y1 = max(p[0] for p in poly) + pad, max(p[1] for p in poly) + pad
    x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
    w, h = x1 - x0, y1 - y0
    X = np.arange(w)[None, :].repeat(h, 0).astype(np.float64) + x0 + 0.5
    Y = np.arange(h)[:, None].repeat(w, 1).astype(np.float64) + y0 + 0.5
    rag = (bg.vnoise_at(x0, y0, w, h, 7, seed + 1) - 0.5) * 7 + (bg.vnoise_at(x0, y0, w, h, 3, seed + 2) - 0.5) * 3 * (0.5 + wear)
    if style == "ring":
        sq = ry / rx
        r = np.hypot(X - cx, (Y - cy) / sq)
        edge = rx - r + rag
        shape = edge > 0
        col, ids = paint_ring(X, Y, cx, cy, sq, seed, float(spec.get("dais", 0.0)))
    elif "line" in spec or "way" in spec or "line_px" in spec:
        d = np.full(X.shape, 1e9)
        U = np.zeros(X.shape)
        V = np.zeros(X.shape)
        run = 0.0
        for (ax, ay), (bx2, by2) in zip(pts[:-1], pts[1:]):
            vx, vy = bx2 - ax, by2 - ay
            L = max(math.hypot(vx, vy), 1e-6)
            tt = np.clip(((X - ax) * vx + (Y - ay) * vy) / (L * L), 0, 1)
            dd = np.hypot(X - ax - tt * vx, Y - ay - tt * vy)
            closer = dd < d
            d = np.where(closer, dd, d)
            U = np.where(closer, run + tt * L, U)
            V = np.where(closer, ((X - ax) * vy - (Y - ay) * vx) / L, V)
            run += L
        edge = half - d + rag * 0.6
        shape = edge > 0
        if style == "flags":
            col, ids = paint_flags(X, Y, seed)
        else:
            col, ids = paint_setts(X, Y, U, V, edge, half, seed)
    else:
        img_poly = Image.new("L", (w, h), 0)
        ImageDraw.Draw(img_poly).polygon([(p[0] - x0, p[1] - y0) for p in poly], fill=255)
        inside = np.array(img_poly) > 0
        sd = bg._signed_distance(inside, 24)
        edge = -sd + rag
        shape = edge > 0
        if style == "flags":
            col, ids = paint_flags(X, Y, seed)
        else:
            col, ids = paint_setts(X, Y, edge, seed, w, h)
    floor_ok, near = floor_mask(X, Y, relief)
    ok = shape & floor_ok
    if style == "setts":  # landings: a row of broad slabs where the street meets a stair, laid parallel to its steps
        lsid, ljoint, _ = setts_field(U, V, seed + 40, length=8.0, base=14.0)
        land = near & shape & (edge >= 4.5)
        col = np.where(land[..., None], finish(0.4 + lsid * 0.5, ljoint, X, Y, seed + 40, worn=np.full(X.shape, 0.3)), col)
    # wear: missing stones (bare earth with grass), grass in the joints, moss, a frayed rim
    holes = bg.vnoise_at(x0, y0, w, h, 23, seed + 3) * 0.7 + bg.vnoise_at(x0, y0, w, h, 8, seed + 4) * 0.3
    bayer = BAYER[(Y.astype(int)) % 4, (X.astype(int)) % 4]
    ok &= ~(holes > 1.0 - wear * 0.42 + (bayer - 0.5) * 0.08)
    ok &= ~((edge < 3.0 + wear * 6.0) & (bayer > 0.35 + edge / (8.0 + wear * 10.0)))
    gone = ids > 1.0 - wear * 0.18  # a few whole stones gone: earth with a tuft
    joint = np.all(col == MORTAR, axis=-1) | np.all(col == EARTH[0], axis=-1)
    grow = bg.vnoise_at(x0, y0, w, h, 5, seed + 6)
    col = np.where((joint & (grow > 0.75 - wear * 0.35))[..., None], GRASS[np.clip((grow * 6).astype(int), 1, 4)], col)
    col = np.where((~joint & (grow > 0.93 - wear * 0.25) & (bayer < 0.6))[..., None], MOSS[np.clip((grow * 3).astype(int), 0, 2)], col)
    col = np.where(gone[..., None], np.array(bg.PATH[2][:3], dtype=np.float32), col)
    img = np.zeros((h, w, 4), dtype=np.uint8)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    img[ok, :3] = col[ok].astype(np.uint8)
    img[ok, 3] = 255
    mask[ok] = (bg.STONE_CODE, 0, 0, 255)
    rng = __import__("random").Random(seed)
    for _ in range(int(w * h * wear / 220)):  # tufts on the frayed rim and in the gaps
        x, y = rng.randrange(4, w - 4), rng.randrange(6, h - 2)
        if ok[y, x] and (edge[y, x] < 5 or gone[y, x]):
            bg.tuft(img, x, y, rng.randrange(2, 5), rng, bg.MEADOW_HI[:6])
    ys, xs = np.nonzero(img[..., 3] > 0)
    if not len(ys):
        return None
    ya, yb, xa, xb = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return img[ya:yb, xa:xb], mask[ya:yb, xa:xb], (int(x0 + xa), int(y0 + ya)), ok


def runs_of(paved):
    runs = []
    for y in sorted(paved):
        xs = sorted(paved[y])
        a = b = xs[0]
        for x in xs[1:]:
            if x == b + 1:
                b = x
            else:
                runs.append([y, a, b])
                a = b = x
        runs.append([y, a, b])
    return runs


def main():
    town = json.load(open(os.path.join(ROOT, "data/hallgrat.json"), encoding="utf-8"))
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    baked_path = os.path.join(ROOT, "data/ground_baked.json")
    baked = json.load(open(baked_path, encoding="utf-8"))
    decals = [d for d in baked["decals"] if not d["id"].startswith("hallgrat_")]
    paved = {}
    shown = []
    jobs = [(spec, 7100 + i * 37) for i, spec in enumerate(town.get("paving", []))]
    for k, dp in enumerate(town.get("door_paths", [])):  # the lanes from the doors (tools/place_hallgrat_buildings.py)
        jobs.append(({"id": "zugang_%d" % k, "style": "setts", "line_px": dp["px"], "width": 13, "wear": 0.35, "kerb": False}, 9100 + k * 11))
    street_runs = None
    for spec, sd in jobs:
        if spec["id"].startswith("zugang_") and street_runs is None:
            street_runs = runs_of(paved)
        out = bake(spec, town, relief, sd)
        if out is None:
            print("nothing to pave for", spec["id"])
            continue
        img, mask, (ox, oy), ok = out
        name = "hallgrat_" + spec["id"]
        bg.save(bg.ROOT / "assets" / "world" / "ground" / (name + ".png"), img)
        bg.save(bg.ROOT / "assets" / "world" / "ground" / (name + "_mask.png"), mask)
        decals.append({"id": name, "texture": "res://assets/world/ground/%s.png" % name, "mask": "res://assets/world/ground/%s_mask.png" % name, "x": ox, "y": oy})
        shown.append((img, ox, oy))
        stone = mask[..., 0] == bg.STONE_CODE
        hh, ww = stone.shape
        for ty in range(oy // 16, (oy + hh) // 16 + 1):
            for tx in range(ox // 16, (ox + ww) // 16 + 1):
                sub = stone[max(0, ty * 16 - oy):max(0, ty * 16 + 16 - oy), max(0, tx * 16 - ox):max(0, tx * 16 + 16 - ox)]
                if sub.size and sub.mean() > 0.3:
                    paved.setdefault(ty, set()).add(tx)
        print("baked %s %d x %d" % (name, img.shape[1], img.shape[0]))
    runs = runs_of(paved)
    for y in []:
        xs = sorted(paved[y])
        a = b = xs[0]
        for x in xs[1:]:
            if x == b + 1:
                b = x
            else:
                runs.append([y, a, b])
                a = b = x
        runs.append([y, a, b])
    baked["decals"] = decals
    baked["hallgrat_clear"] = runs
    baked["hallgrat_streets"] = street_runs if street_runs is not None else runs
    tmp = baked_path + ".tmp"
    open(tmp, "w", encoding="utf-8").write(json.dumps(baked, separators=(",", ":")))
    os.replace(tmp, baked_path)
    print("%d paved tiles in %d runs" % (sum(b - a + 1 for _, a, b in runs), len(runs)))
    if len(sys.argv) > 1:
        bx0, by0, bx1, by1 = [v * 16 for v in town["bounds"]]
        can = np.zeros((by1 - by0, bx1 - bx0, 4), dtype=np.uint8)
        can[...] = (58, 98, 70, 255)
        for img, ox, oy in shown:
            hh, ww = img.shape[:2]
            sl = can[oy - by0:oy - by0 + hh, ox - bx0:ox - bx0 + ww]
            a = img[..., 3:4] / 255.0
            sl[..., :3] = (img[..., :3] * a + sl[..., :3] * (1 - a)).astype(np.uint8)
        Image.fromarray(can).save(sys.argv[1])


if __name__ == "__main__":
    main()
