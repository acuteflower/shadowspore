#!/usr/bin/env python3
"""The town's scarecrow (`scarecrow`), built with `hut_lib` / `art_hero3d` to match `fence`, `bench`, and `lamp_post`.
Writes:
  assets/town/scarecrow.png          36x48, feet row 42, footprint [12, 8]
  assets/town/scarecrow_glow.png     36x48, emissive pixels for the hanging teal jar-charm & tiny eye-slits
  assets/town/scarecrow_preview.png  36x48, base + soft glow composite for build menu / ghost preview
Run:
  py -3 tools/art_scarecrow.py [preview_contact.png]
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
from gen_art import hexc  # noqa: E402
from hut_lib import (  # noqa: E402
    BARK, BARK_D, CLAY, IRON, LINEN, MOSS, MOSS_L, PLANK, PLANK_W,
    ROOT, STONE, STONE_L, STRAW, WAX, V, bayer, grain, log, rng_for, save, slab, soft_shadow, to_array,
)
import hut_lib  # noqa: E402

OUT = ROOT / "town"
FW, FH, GROUND = 36, 48, 42
UNITS_PER_PX = 1.0 / (math.sin(math.radians(26.0)) * h.SCALE)
WOODISH = (BARK, BARK_D, PLANK, PLANK_W, MOSS, MOSS_L, STONE, STONE_L, IRON, STRAW, LINEN, CLAY, WAX)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def proj(x, y, z):
    cosp = math.cos(math.radians(26.0))
    sinp = math.sin(math.radians(26.0))
    return FW / 2.0 + x * h.SCALE, GROUND - (y * cosp - z * sinp) * h.SCALE


def scarecrow_model():
    rng = rng_for(93)
    m = h.Model()
    # Footprint is [12, 8]: front edge is z = 0 (row 42 = feet), back edge is z ~ -19.8; centre post at zc = -4.8
    zc = -4.8

    # 1. Small cairn of mossy field stones & fallen straw wisps right on the feet row (42)
    for k in range(6):
        ang = k / 6.0 * math.tau + 0.35
        rx, rz = 4.6, 3.6
        sx = math.cos(ang) * rx
        sz = zc + math.sin(ang) * rz
        m.ell(
            V(sx, 1.0, sz),
            (rng.uniform(1.6, 2.3), rng.uniform(1.0, 1.4), rng.uniform(1.3, 1.8)),
            STONE_L if k % 2 == 0 else STONE,
            R=h.rot_y(ang),
        )
    for dx, dz, mat in ((-3.0, 2.2, MOSS_L), (2.8, 1.8, MOSS), (-1.2, -2.2, MOSS)):
        m.ell(V(dx, 1.7, zc + dz), (1.4, 0.55, 1.1), mat)
    for dx in (-3.8, 3.4, 0.8):  # fallen straw wisps at base
        m.limb(V(dx * 0.4, 1.3, zc + 1.6), V(dx, 0.5, zc + 3.4), 0.42, 0.22, STRAW)

    # 2. Crooked plum-bark wooden crosspost
    # Vertical post leans left to the waist, then kinks right up into the neck
    log(m, V(0.0, 0.4, zc), V(-0.9, 13.5, zc), 1.85, BARK, step=0.9, taper=0.92)
    log(m, V(-0.9, 13.5, zc), V(0.4, 29.0, zc + 0.4), 1.65, BARK, step=0.9, taper=0.85)
    m.ell(V(-1.6, 6.8, zc + 1.1), (0.9, 0.7, 0.7), BARK_D)  # bark knot on lower post

    # Crooked horizontal crossbar (left side dips lower, right side tilts higher to hold the hanging charm lantern)
    arm_l = V(-14.2, 21.2, zc + 0.8)
    arm_r = V(13.8, 24.4, zc + 0.8)
    log(m, arm_l, arm_r, 1.25, BARK, step=0.9, taper=0.88)
    m.ell(arm_l + V(-0.4, -0.1, 0.0), (1.1, 0.9, 1.1), BARK_D)
    m.ell(arm_r + V(0.4, 0.1, 0.0), (1.0, 0.85, 1.0), BARK_D)

    # 3. Straw-stuffed linen tunic + straw tufts bursting at cuffs, hem & collar
    # Stuffed torso sack & cinched waist
    m.ell(V(-0.3, 19.2, zc + 1.4), (5.0, 5.2, 3.6), LINEN, R=rot_z(-0.06))
    m.ell(V(-0.5, 13.0, zc + 1.3), (5.4, 3.0, 3.7), LINEN, R=rot_z(0.05))  # flared ragged tunic skirt
    for ox in (-3.6, -1.2, 1.4, 3.6):  # tattered tunic hem tabs + straw poking underneath
        m.ell(V(ox - 0.4, 10.4 + (ox % 2) * 0.4, zc + 1.6), (1.3, 1.5, 1.1), LINEN)
    for ox, dy in ((-3.2, 8.9), (-0.5, 8.6), (2.4, 9.0)):
        m.limb(V(ox, 11.2, zc + 1.8), V(ox * 1.22, dy, zc + 2.4), 0.72, 0.35, STRAW)
    # Rope belt & stitched warm patch on belly
    m.ell(V(-0.4, 15.0, zc + 1.5), (4.8, 0.85, 3.8), STRAW)
    m.ell(V(1.6, 14.4, zc + 4.8), (0.9, 1.3, 0.6), STRAW)  # belt knot
    m.ell(V(2.2, 17.6, zc + 4.2), (1.8, 1.7, 0.7), CLAY, R=rot_z(0.15))  # sewn patch

    # Tunic sleeves along the crooked crossbar + straw bursting from both cuffs
    log(m, V(-4.2, 21.8, zc + 1.4), V(-9.8, 21.3, zc + 1.2), 2.25, LINEN, step=0.9, taper=0.92)
    log(m, V(3.8, 22.8, zc + 1.4), V(9.2, 23.8, zc + 1.2), 2.15, LINEN, step=0.9, taper=0.90)
    for sy, dy, dz in ((-0.9, 1.3, 0.8), (0.5, -1.2, 1.0), (0.0, 0.2, 0.6)):
        m.limb(V(-9.6, 21.3 + sy * 0.5, zc + 1.5), V(-13.0, 20.4 + dy, zc + 1.6 + dz), 0.78, 0.35, STRAW)
        m.limb(V(9.0, 23.8 + sy * 0.5, zc + 1.5), V(12.0, 24.5 + dy, zc + 1.6 + dz), 0.72, 0.32, STRAW)

    # 4. Tattered purple-indigo scarf & fluttering ragged cape
    # Back/side cape drape behind shoulders
    slab(m, V(-5.2, 23.5, zc - 0.6), V(-7.6, 12.2, zc - 0.2), 3.4, 0.9, h.LEGGING, (0, 0, 1), step=1.1)
    slab(m, V(3.2, 23.8, zc - 0.6), V(5.4, 13.8, zc - 0.2), 2.8, 0.85, h.COAT, (0, 0, 1), step=1.1)
    # Coiled purple-indigo neck scarf & fluttering front tattered tails
    m.ell(V(0.1, 24.8, zc + 1.8), (4.8, 1.8, 4.0), h.COAT, R=rot_z(-0.08))
    m.ell(V(-0.6, 25.4, zc + 2.5), (3.8, 1.1, 3.2), h.VIOLET, R=rot_z(-0.1))
    # Two ragged scarf tails sweeping left across the tunic chest
    slab(m, V(-2.2, 24.0, zc + 4.0), V(-5.6, 15.6, zc + 3.6), 1.65, 0.65, h.COAT, (0, 0, 1), step=1.0)
    m.ell(V(-6.2, 14.6, zc + 3.5), (1.1, 1.4, 0.5), h.LEGGING)
    slab(m, V(0.6, 23.8, zc + 4.3), V(-1.4, 18.2, zc + 4.4), 1.25, 0.55, h.VIOLET, (0, 0, 1), step=0.9)

    # Straw wisps peeking under the chin
    for dx in (-2.4, 0.5, 2.8):
        m.limb(V(dx * 0.6, 26.2, zc + 2.4), V(dx * 1.25, 25.5, zc + 4.2), 0.48, 0.2, STRAW)

    # 5. Painted gourd / burlap head (cocked at a charming tilt)
    head_c = V(0.5, 29.5, zc + 1.8)
    head_R = rot_z(-0.15)
    m.ell(head_c, (4.6, 4.2, 4.2), WAX, R=head_R)
    m.ell(head_c + V(0.8, -0.6, 0.4), (3.6, 3.2, 3.5), STRAW, R=head_R)  # warm gourd-tan lower cheek

    # 6. Crooked peaked straw/felt hat (dark plum-felt cone + frayed golden straw brim edge & violet band)
    brim_c = V(0.6, 33.0, zc + 1.7)
    hat_R = rot_z(-0.18)
    m.ell(brim_c + V(0.0, -0.3, 0.0), (9.4, 0.95, 6.8), STRAW, R=hat_R)  # frayed golden straw under-brim / rim
    m.ell(brim_c + V(0.0, 0.35, 0.0), (8.6, 1.05, 6.2), BARK_D, R=hat_R)  # weathered dark plum-felt upper brim
    m.ell(brim_c + V(0.2, 1.6, 0.0), (4.9, 1.3, 4.5), h.VIOLET, R=hat_R)  # purple-indigo hatband
    # Crooked peaked cone bending gracefully to the right at the tip
    cone_pts = [
        (V(0.4, 34.4, zc + 1.6), 4.4),
        (V(0.9, 36.8, zc + 1.4), 3.3),
        (V(1.8, 39.2, zc + 1.2), 2.2),
        (V(3.2, 41.2, zc + 1.0), 1.35),
        (V(4.8, 40.4, zc + 1.0), 0.85),  # floppy crooked tip!
    ]
    for (p0, r0), (p1, r1) in zip(cone_pts, cone_pts[1:]):
        m.limb(p0, p1, r0, r1, BARK_D, step=0.6)

    # 7. Small hanging teal-glowing charm / jar lantern suspended from the right crossbar end
    hook = V(12.2, 23.8, zc + 1.2)
    m.ell(hook, (0.75, 0.75, 0.75), IRON)  # iron ring on the arm
    m.limb(hook, hook + V(0.0, -2.8, 0.0), 0.32, 0.32, IRON)  # short chain
    jar_c = hook + V(0.0, -5.4, 0.0)
    m.ell(jar_c + V(0.0, 2.2, 0.0), (1.9, 0.8, 1.9), IRON)  # jar lid
    m.ell(jar_c, (1.85, 2.3, 1.85), h.TEAL, kind="emit")  # glowing teal charm-jar glass
    m.ell(jar_c + V(0.0, -2.2, 0.0), (1.7, 0.7, 1.7), IRON)  # bottom iron cradle
    return m, head_c, jar_c


def make(preview=None):
    hut_lib.set_fresh()
    OUT.mkdir(parents=True, exist_ok=True)
    m, head_c, jar_c = scarecrow_model()
    arr = to_array(hut_lib.render(m, FW, FH, GROUND))
    arr = grain(arr, 94, amount=0.45, mats=WOODISH)
    arr = soft_shadow(arr, FW / 2.0, GROUND + 1, 7.5, 2.1)

    # Build clean glow sheet (36x48) + crisp 2D pixel face details (tiny glowing eye-slits & stitched gourd mouth)
    glow = np.zeros((FH, FW, 4), np.uint8)
    teal_ramp = h.RAMPS[h.TEAL]
    teal_rgb = {tuple(int(v) for v in c[:3]): b for b, c in enumerate(teal_ramp)}

    # Soft dithered night glow halo around the hanging charm-jar lantern
    jx, jy = proj(*jar_c)
    for y in range(FH):
        for x in range(FW):
            d = math.hypot((x + 0.5 - jx) / 5.2, (y + 0.5 - jy) / 5.8)
            if 0.35 < d < 1.0 and bayer(x, y) < (1.0 - d) * 0.85:
                glow[y, x] = (*teal_ramp[1][:3], 95)

    # Extract jar lantern emissive pixels: bright core in _glow, rich translucent teal glass in base
    for y in range(FH):
        for x in range(FW):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in teal_rgb:
                d_core = math.hypot(x + 0.5 - jx, y + 0.5 - jy)
                tone = 3 if d_core < 1.15 else 2 if d_core < 2.1 else 1
                glow[y, x] = (*teal_ramp[tone][:3], 255)
                # Keep base lantern glass slightly deeper teal so day & night contrast nicely
                base_tone = max(0, tone - 1)
                arr[y, x] = (*teal_ramp[base_tone][:3], 255)

    # Paint crisp burlap/gourd face details around projected head center:
    # two tiny glowing teal eye-slits (tilted with head) + dark stitched grin
    hx, hy = proj(*(head_c + V(0.0, 0.0, 3.6)))
    ihx, ihy = int(round(hx)), int(round(hy))
    stitch_dark = hexc("22162b")
    eye_dim = teal_ramp[1]
    eye_bright = teal_ramp[3]
    eye_mid = teal_ramp[2]

    # Left & right 2px eye-slits (tilted slightly down to the right with the cocked head)
    eye_slits = [
        (ihx - 2, ihy - 1, True), (ihx - 1, ihy - 1, False),
        (ihx + 1, ihy, False), (ihx + 2, ihy, True),
    ]
    for ex, ey, hot in eye_slits:
        if 0 <= ex < FW and 0 <= ey < FH:
            # dark socket pixel directly above for unmistakable readability against pale gourd/burlap
            if ey - 1 >= 0 and arr[ey - 1, ex, 3]:
                arr[ey - 1, ex] = stitch_dark
            arr[ey, ex] = (*eye_dim[:3], 255)
            glow[ey, ex] = (*(eye_bright if hot else eye_mid)[:3], 255)

    # Crooked stitched smile underneath the eyes
    for sx, sy in ((ihx - 2, ihy + 1), (ihx - 1, ihy + 2), (ihx, ihy + 2), (ihx + 1, ihy + 2), (ihx + 2, ihy + 1)):
        if 0 <= sx < FW and 0 <= sy < FH and arr[sy, sx, 3]:
            arr[sy, sx] = stitch_dark

    save(OUT / "scarecrow.png", arr)
    save(OUT / "scarecrow_glow.png", glow)

    # Build-menu / ghost preview (`scarecrow_preview.png`, matching `lamp_post_preview.png` convention)
    comp = Image.fromarray(arr, "RGBA")
    glow_im = Image.fromarray(glow, "RGBA")
    glow_im.putalpha(glow_im.getchannel("A").point(lambda v: int(v * 0.85)))
    comp.alpha_composite(glow_im, (0, 0))
    comp.save(OUT / "scarecrow_preview.png")

    if preview:
        scale = 6
        day_bg = (58, 102, 66, 255)
        night_bg = (16, 20, 36, 255)
        pad = 6
        tile_w, tile_h = FW + pad * 2, FH + pad * 2
        sheet = Image.new("RGBA", (tile_w * 3 * scale, tile_h * scale), day_bg)
        # Panel 1: Day (base + 0.3 day glow, matching TownStructure.GLOW_BY_DAY)
        p1 = Image.new("RGBA", (tile_w, tile_h), day_bg)
        p1.alpha_composite(Image.fromarray(arr, "RGBA"), (pad, pad))
        g_day = Image.fromarray(glow, "RGBA")
        g_day.putalpha(g_day.getchannel("A").point(lambda v: int(v * 0.3)))
        p1.alpha_composite(g_day, (pad, pad))
        # Panel 2: Preview sprite
        p2 = Image.new("RGBA", (tile_w, tile_h), day_bg)
        p2.alpha_composite(comp, (pad, pad))
        # Panel 3: Night (dimmed base + full unlit glow)
        p3 = Image.new("RGBA", (tile_w, tile_h), night_bg)
        dark = (arr.astype(np.float32) * np.array([0.36, 0.38, 0.56, 1.0])).clip(0, 255).astype(np.uint8)
        p3.alpha_composite(Image.fromarray(dark, "RGBA"), (pad, pad))
        p3.alpha_composite(Image.fromarray(glow, "RGBA"), (pad, pad))
        for idx, panel in enumerate((p1, p2, p3)):
            sheet.paste(panel.resize((tile_w * scale, tile_h * scale), Image.NEAREST), (idx * tile_w * scale, 0))
        sheet.save(preview)
    return arr


if __name__ == "__main__":
    make(sys.argv[1] if len(sys.argv) > 1 else None)
