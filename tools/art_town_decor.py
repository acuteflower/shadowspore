#!/usr/bin/env python3
"""Town additions of docs/town_ausbau.md (run AFTER tools/art_town.py, which writes the base pictures; this adds to them and to data/town.json):

  * the banner post (piece `banner_post`) with its swaying banner,
  * night lanterns on the fronts of the stockpile and the workshop (parts with unlit glow sheets, more light on the ground: it merges into `*_spill.png`),
  * the market-stall shutters (5 frames each, closed .. open) of stockpile and workshop (data `shutters`),
  * the overlays of ageing and care (data `wear` with `track`: age / care / neglect): ivy, a flower box, moss and cobwebs,
  * the same ivy for the renewed hut (assets/interior/hut/fresh/hut_ivy_*.png) and the hut's second banner and flag (`hut_flag.png`).
    python3 tools/art_town_decor.py [preview.png]
It needs numpy and PIL; the second run changes nothing (spills are merged with `maximum`, JSON entries replaced by texture name)."""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import art_town as T  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, grain, log, rng_for, save, slab, to_array, V  # noqa: E402

OUT = T.OUT
JSON = Path(__file__).resolve().parent.parent / "data" / "town.json"
UP = T.UNITS_PER_PX
hut_lib.set_fresh()


def depth_units(px):
    return px * UP


# ------------------------------------------------------------------ geometry of the two roofed stalls (copied from art_town.py)
def stock_geo():
    W = 35.0
    back, front = -depth_units(28) + 3.0, -2.0
    return {"W": W, "back": back, "front": front, "rf": back + 0.62 * (front - back), "fw": 120, "fh": 80, "ground": 68, "eave": 32.5, "hinge_y": 31.8}


def shop_geo():
    W = 52.0
    back, front = -depth_units(40) + 3.0, -3.0
    return {"W": W, "back": back, "front": front, "rf": back + 0.58 * (front - back), "fw": 144, "fh": 112, "ground": 98, "eave": 43.0, "hinge_y": 42.3}


# ------------------------------------------------------------------ json
def merge(piece, key, entry, match="texture"):
    """Put `entry` into the list `key` of a piece, replacing the one with the same `match` value (so a second run changes nothing)."""
    data = json.loads(JSON.read_text(encoding="utf-8"))
    lst = data["pieces"][piece].setdefault(key, [])
    for i, old in enumerate(lst):
        if old.get(match) == entry.get(match):
            lst[i] = entry
            break
    else:
        lst.append(entry)
    JSON.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\r\n")


def put_piece(piece, entry):
    data = json.loads(JSON.read_text(encoding="utf-8"))
    data["pieces"][piece] = entry
    JSON.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\r\n")


# ------------------------------------------------------------------ the banner post
def hang_banner(m, x, y_top, z, length, half):
    """The town's banner as a hanging cloth (teal, gold stripe, swallow tail) on a crossbar."""
    log(m, V(x - half - 0.8, y_top - 0.4, z + 0.5), V(x + half + 0.8, y_top - 0.4, z + 0.5), 0.45, IRON, step=0.8)
    slab(m, V(x, y_top - 0.8, z + 0.9), V(x, y_top - length, z + 0.9), half, 0.5, BANNER, (0, 0, 1), step=1.0)
    slab(m, V(x, y_top - length * 0.4, z + 1.2), V(x, y_top - length * 0.4 - 1.6, z + 1.2), half + 0.05, 0.4, STRAW, (0, 0, 1), step=0.9)
    m.ell(V(x - half * 0.5, y_top - length - 0.8, z + 0.9), (half * 0.55, 1.6, 0.35), BANNER)
    m.ell(V(x + half * 0.5, y_top - length - 0.8, z + 0.9), (half * 0.55, 1.6, 0.35), BANNER)


def banner_post():
    import hut_yard as y  # noqa: F401
    fw, fh, ground = 32, 64, 56
    z = -depth_units(6) / 2.0
    m = h.Model()
    for k in range(5):  # a heap of stones at the foot
        a = k / 5 * math.tau
        m.ell(V(math.cos(a) * 2.6, 1.4, z + math.sin(a) * 1.8), (1.9, 1.5, 1.6), STONE if k % 2 else STONE_L)
    T.upright(m, 0.0, z, 1.0, 47.0, 1.15, BARK, 0.85)
    for k in range(3):  # the grain of the pole: a few ring knots
        m.ell(V(0.9, 12.0 + k * 11, z + 0.7), (0.5, 0.8, 0.4), BARK_D)
    log(m, V(-6.4, 45.2, z + 0.5), V(6.4, 45.2, z + 0.5), 0.6, IRON, step=0.8)  # the crossbar
    m.ell(V(0.0, 49.0, z), (1.4, 1.4, 1.4), IRON)
    m.ell(V(0.0, 49.0, z), (0.8, 0.8, 0.8), h.TEAL, kind="emit")
    base = to_array(hut_lib.render(m, fw, fh, ground))
    base = T.finish(base, 81, ground, 9, 2.4)
    T.put("banner_post", base)
    pm = h.Model()
    hang_banner(pm, 0.0, 45.6, z, 21.0, 3.6)
    cloth, (cx, cy) = T.part("banner_post_cloth", pm, fw, fh, ground, seed=82)
    from PIL import Image
    prev = base.copy()
    sheet = Image.fromarray(prev)
    sheet.alpha_composite(Image.fromarray(cloth), (cx, cy))
    save(OUT / "banner_post_preview.png", np.array(sheet))
    put_piece("banner_post", {
        "name": "STANDARTE", "category": "living", "texture": "banner_post", "frame": [fw, fh], "feet": ground, "foot": [8, 6], "snap": 8,
        "cost": {"wood": 2, "plant_fiber": 1}, "build_seconds": 2.5, "worth": 1, "info": "DAS BANNER DER STADT", "glow": False,
        "preview": "banner_post_preview", "fireflies": True, "perches": [[0, 3, 48]],
        "parts": [{"texture": "banner_post_cloth", "frame": T.INFO["banner_post_cloth"]["frame"], "at": T.INFO["banner_post_cloth"]["at"], "window": [0.5, 1.0],
                   "sway": {"pivot": 0, "amount": 3.0, "flutter": 0.9}}],
    })
    # the piece goes after the bench in the catalogue (living): put it right behind it
    data = json.loads(JSON.read_text(encoding="utf-8"))
    pieces = data["pieces"]
    order = [k for k in pieces if k != "banner_post"]
    idx = order.index("bench") + 1
    order.insert(idx, "banner_post")
    data["pieces"] = {k: pieces[k] for k in order}
    JSON.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\r\n")
    return base


# ------------------------------------------------------------------ night lanterns
def lantern_parts():
    from hut_lib import pool_spill
    from PIL import Image
    for piece, geo, specs in (("stockpile", stock_geo(), [("l", -geo_x(stock_geo(), 5.0)), ("r", geo_x(stock_geo(), 5.0))]),
                              ("workshop", shop_geo(), [("l", -geo_x(shop_geo(), 8.0))])):
        fw, fh, ground, rf, W = geo["fw"], geo["fh"], geo["ground"], geo["rf"], geo["W"]
        spill_path = OUT / f"{piece}_spill.png"
        spill = np.array(Image.open(spill_path).convert("RGBA"))
        for side, x in specs:
            lm = h.Model()
            T.lantern(lm, (x, geo["hinge_y"] - 0.6, rf + 6.0), hang=2.0)
            name = f"{piece}_lantern_{side}"
            arr, (lx, ly) = T.part(name, lm, fw, fh, ground, glow=True, seed=90 + (1 if side == "r" else 0))
            fb = T.fire_box(arr)
            box = (fb[0] + lx, fb[1] + lx, fb[2] + ly, fb[3] + ly)
            floor_y = ground + (rf + 6.0) / UP + 3.0
            extra = pool_spill(fw, fh, box, [((box[0] + box[1]) / 2, floor_y, 17, 6, 0.75)], reach=6, seed=93, bloom=0.4)
            spill = np.maximum(spill, extra)
            info = T.INFO[name]
            merge(piece, "parts", {"texture": name, "frame": info["frame"], "at": info["at"], "window": [0.75, 1.0],
                                   "sway": {"pivot": 0, "amount": 1.4, "flutter": 0.3}, "glow": {"frames": 1, "fps": 1}})
        save(spill_path, spill)


def geo_x(geo, inset):
    return geo["W"] - inset


# ------------------------------------------------------------------ shutters
ANGLES = (0.0, 26.0, 50.0, 72.0, 88.0)


def shutter(piece, geo, length, half_w, seed):
    """A hinged market-stall flap under the roof's front edge: shut (hanging flat) .. propped up as an awning (88 degrees). One frame strip (5 frames, same cell)."""
    fw, fh, ground, rf, W = geo["fw"], geo["fh"], geo["ground"], geo["rf"], geo["W"]
    zh = rf + 6.4
    yh = geo["hinge_y"]
    frames = []
    for a in ANGLES:
        r = math.radians(a)
        d = V(0, -math.cos(r), math.sin(r))
        n = V(0, math.sin(r), math.cos(r))
        m = h.Model()
        x = -half_w + 2.2
        i = 0
        while x < half_w:
            top = V(x, yh, zh)
            m.ell(tuple(top), (0.5, 0.5, 0.5), IRON) if i % 3 == 0 else None
            slab(m, top, top + d * length, 2.2, 0.9, PLANK_W if i % 3 == 0 else PLANK, tuple(n), step=1.3)
            x += 4.3
            i += 1
        for t in (0.28, 0.74):  # two battens across
            p = V(0, yh, zh) + d * (length * t) + n * 0.7
            slab(m, p + V(-half_w + 0.6, 0, 0), p + V(half_w - 0.6, 0, 0), 1.0, 0.7, BARK_D, tuple(n), step=1.2)
        for sx in (-1, 1):  # hinges
            m.ell((sx * (half_w - 1.2), yh + 0.2, zh + 0.8), (1.6, 0.7, 0.5), IRON)
        frames.append(to_array(hut_lib.render(m, fw, fh, ground)))
    union = np.zeros((fh, fw), bool)
    for f in frames:
        union |= f[..., 3] > 0
    ys, xs = np.nonzero(union)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()) + 1, int(ys.min()), int(ys.max()) + 1
    cells = [grain(f[y0:y1, x0:x1], seed + k, amount=0.4, mats=T.WOODISH) for k, f in enumerate(frames)]
    strip = np.concatenate(cells, axis=1)
    name = f"{piece}_shutter"
    save(OUT / f"{name}.png", strip)
    merge(piece, "shutters", {"texture": name, "frame": [x1 - x0, y1 - y0], "at": [x0, y0], "frames": len(ANGLES)})
    return strip


# ------------------------------------------------------------------ ageing and care
def _overlay(path, m, fw, fh, ground, seed):
    arr = to_array(hut_lib.render(m, fw, fh, ground))
    save(path, grain(arr, seed, amount=0.5, mats=T.WOODISH))


def ivy_cluster(m, rng, x, z, y0, y1, spread=1.6, density=0.7, lean=0.0):
    """A climbing plant along a vertical line: leaf blobs, a few lit ones, little flowers."""
    y = y0
    while y < y1:
        for _ in range(2):
            m.ell(V(x + rng.uniform(-spread, spread) + lean * (y - y0), y, z + rng.uniform(-0.6, 1.2)), (rng.uniform(1.1, 2.1), rng.uniform(0.9, 1.7), 0.9), MOSS_L if rng.random() < 0.45 else MOSS)
        if rng.random() < 0.18:
            m.ell(V(x + rng.uniform(-spread, spread), y, z + 1.5), (0.55, 0.55, 0.5), LINEN)
        y += 1.8 / max(density, 0.2)


def cobweb(m, cx, cy, cz, size, sign=1):
    for k in range(5):
        ang = math.radians(-8 + k * 24)
        end = V(cx + sign * math.cos(ang) * size, cy - math.sin(ang) * size * 1.1, cz)
        m.limb(V(cx, cy, cz), end, 0.12, 0.12, LINEN)
    for rr in (0.45, 0.8):
        for k in range(4):
            a0, a1 = math.radians(-8 + k * 24), math.radians(16 + k * 24)
            p0 = V(cx + sign * math.cos(a0) * size * rr, cy - math.sin(a0) * size * rr * 1.1, cz)
            p1 = V(cx + sign * math.cos(a1) * size * rr, cy - math.sin(a1) * size * rr * 1.1, cz)
            m.limb(p0, p1, 0.1, 0.1, LINEN)


def flower_box(m, rng, x, y, z, width=8.0):
    slab(m, V(x - width, y + 1.6, z), V(x + width, y + 1.6, z), 1.9, 2.0, BARK_D, (0, 0, 1))
    k = 0
    xx = x - width + 1.2
    while xx < x + width - 0.5:
        m.ell(V(xx, y + 4.2, z + 0.4), (1.2, 1.7, 1.1), MOSS if k % 2 else MOSS_L)
        mat = (LINEN, STRAW, CLAY)[k % 3]
        m.ell(V(xx + 0.3, y + 6.4 + (k % 2), z + 0.6), (0.85, 0.85, 0.85), mat)
        xx += 2.6
        k += 1


def aging_set(piece, geo, ivy_x, box_x, web_sign, seeds):
    fw, fh, ground, rf, W = geo["fw"], geo["fh"], geo["ground"], geo["rf"], geo["W"]
    rng = rng_for(seeds)
    top = geo["eave"] - 2.0
    m = h.Model()  # age 4: ivy on the front post, low
    ivy_cluster(m, rng, ivy_x, rf + 0.8, 1.0, top * 0.42, lean=0.01 * web_sign)
    _overlay(OUT / f"{piece}_ivy_a.png", m, fw, fh, ground, seeds + 1)
    m = h.Model()  # age 9: all the way up, a drape along the eave
    ivy_cluster(m, rng_for(seeds), ivy_x, rf + 0.8, 1.0, top, lean=0.01 * web_sign)
    for k in range(9):
        m.ell(V(ivy_x + web_sign * (k * 2.6), geo["eave"] - 0.6 - (k % 3) * 0.9, rf + 6.8), (rng.uniform(1.4, 2.2), 1.3, 0.8), MOSS_L if k % 2 else MOSS)
    _overlay(OUT / f"{piece}_ivy_b.png", m, fw, fh, ground, seeds + 2)
    m = h.Model()  # care: a flower box at the front
    flower_box(m, rng, box_x, 0.8, geo["front"] - 4.0)
    _overlay(OUT / f"{piece}_flowers.png", m, fw, fh, ground, seeds + 3)
    m = h.Model()  # neglect: cobwebs under the eave and moss on its edge
    cobweb(m, -W + 3.0 if web_sign > 0 else W - 3.0, geo["eave"] - 4.0, rf + 2.0, 9.0, sign=web_sign)
    cobweb(m, 0.0, geo["eave"] - 3.0, rf + 2.0, 6.0, sign=1)
    for k in range(16):
        m.ell(V(rng.uniform(-W + 2, W - 2), geo["eave"] - 0.3, rf + 6.9), (rng.uniform(1.6, 3.0), 0.9, 0.8), MOSS if k % 2 else MOSS_L)
    _overlay(OUT / f"{piece}_neglect.png", m, fw, fh, ground, seeds + 4)
    for name, days, track in ((f"{piece}_ivy_a", 4, "age"), (f"{piece}_ivy_b", 9, "age"), (f"{piece}_flowers", 1, "care"), (f"{piece}_neglect", 2, "neglect")):
        merge(piece, "wear", {"texture": name, "days": days, "track": track})


# ------------------------------------------------------------------ the renewed hut: ivy, a second banner and a flag
def hut_extras():
    fw, fh, ground = 208, 200, 174
    outdir = ROOT / "interior" / "hut" / "fresh"
    rng = rng_for(7)
    m = h.Model()
    ivy_cluster(m, rng, 63.0, 6.5, 2.0, 24.0, spread=1.4, lean=-0.012)
    _overlay(outdir / "hut_ivy_a.png", m, fw, fh, ground, 5)
    m = h.Model()
    ivy_cluster(m, rng_for(7), 63.0, 6.5, 2.0, 50.0, spread=1.6, lean=-0.012)
    for k in range(8):
        m.ell(V(55.0 - k * 2.4, 57.0 - (k % 3) * 1.2, 11.0), (rng.uniform(1.4, 2.4), 1.4, 0.9), MOSS_L if k % 2 else MOSS)
    _overlay(outdir / "hut_ivy_b.png", m, fw, fh, ground, 6)
    # the flag on the ridge: an iron pole and a teal swallow-tailed pennant with a gold stripe (hand-placed pixels like the banner)
    teal = [tuple(c[:3]) for c in h.RAMPS[BANNER]]
    iron = [tuple(c[:3]) for c in h.RAMPS[IRON]]
    gold = [(160, 130, 66), (212, 188, 120)]
    ink = (20, 14, 30)
    arr = np.zeros((26, 18, 4), np.uint8)

    def px(x, y, c):
        if 0 <= x < 18 and 0 <= y < 26:
            arr[y, x] = (*c, 255)

    for y in range(2, 26):  # the pole
        px(3, y, iron[3] if y % 5 else iron[2])
        px(4, y, iron[1])
        px(2, y, ink)
        px(5, y, ink)
    px(3, 1, gold[1])
    px(4, 1, gold[0])
    for y in range(3, 13):  # the pennant, a little tapering
        length = 12 - (y - 3) // 3
        for x in range(5, 5 + length):
            tone = 3 if y < 5 else 2 if x < 9 else 1
            px(x, y, teal[tone])
        px(5 + length, y, ink)
    for x in range(5, 12):
        px(x, 2, ink)
    for x in range(5, 11):
        px(x, 6, gold[1] if x < 8 else gold[0])
    save(outdir / "hut_flag.png", arr)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    banner_post()
    print("banner post")
    lantern_parts()
    print("lanterns")
    shutter("stockpile", stock_geo(), 27.0, 33.0, 400)
    shutter("workshop", shop_geo(), 38.0, 48.0, 410)
    print("shutters")
    sg, wg = stock_geo(), shop_geo()
    aging_set("stockpile", sg, sg["W"] - 2.0, -sg["W"] + 6.0, -1, 500)
    aging_set("workshop", wg, -wg["W"] + 2.0, -wg["W"] + 12.0, 1, 520)
    print("ageing")
    hut_extras()
    print("hut extras")
    print("INFO", json.dumps({k: v for k, v in T.INFO.items() if "lantern_" in k or "banner_post" in k}))


if __name__ == "__main__":
    import hut_yard as y  # noqa: E402,F401  (art_town's helpers use it as a global)
    T.y = y
    main()
