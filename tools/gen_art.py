#!/usr/bin/env python3
"""Draws the game's pixel art from code (stdlib only). Re-run to regenerate:
  (the grass atlas, tileset and tile table come from tools/art_grass.py)
  assets/items/*.png            sword icons (16x16) and in-hand sprites (30x9 / 32x9, pivot at grip (4, 4))
  assets/enemies/shadow_spider_body.png  8 facing frames of 32x26 (legs are drawn in code)
  assets/props/training_dummy.png  24x32
  assets/fx/puff.png            4x4 white puff, tinted per surface
  assets/fx/footprint.png       5x3 white footprint, tinted per surface
  assets/fx/dust.png            4x4 dust puff for particles
  assets/fx/blink_rift.png      6 frames of 40x20, void rift (open, full, collapse)
  assets/fx/void_shard.png      3x3 white shard, tinted by particle gradient
  (the player sheet, assets/characters/player.png, comes from tools/art_hero3d.py)
"""
import math
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "assets"
CLEAR = (0, 0, 0, 0)


def hexc(h: str, a: int = 255):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def write_png(path: pathlib.Path, w: int, h: int, px) -> None:
    rows = b"".join(
        b"\x00" + bytes(c for x in range(w) for c in px[y][x]) for y in range(h)
    )

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


# ---------------------------------------------------------------- shared helpers
def noise(x: int, y: int, seed: int) -> int:
    n = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
    n = (n ^ (n >> 13)) * 1274126177
    return (n ^ (n >> 16)) & 0xFF


DUST = [
    ".XX.",
    "XLXX",
    "XXXX",
    ".XX.",
]


def dust_puff():
    pal = {".": CLEAR, "X": hexc("cfc2a4"), "L": hexc("efe6cf")}
    return [[pal[c] for c in row] for row in DUST]


# ------------------------------------------------------------ terrain fx
def puff():
    w = (255, 255, 255, 255)
    return [[CLEAR, w, w, CLEAR], [w, w, w, w], [w, w, w, w], [CLEAR, w, w, CLEAR]]


def footprint():
    w = (255, 255, 255, 255)
    return [[CLEAR, w, w, w, CLEAR], [w, w, w, w, w], [CLEAR, w, w, w, CLEAR]]



# ------------------------------------------------------- weapons, slash, dummy
OUT_C = hexc("1b1a2e")


def sword_palette(light, mid, dark, guard, grip, pommel, gem):
    fuller = (int(dark[0] * 0.78), int(dark[1] * 0.78), int(dark[2] * 0.82), 255)
    guard_hi = (min(255, guard[0] + 40), min(255, guard[1] + 40), min(255, guard[2] + 40), 255)
    return {".": CLEAR, "o": OUT_C, "L": light, "M": mid, "B": dark, "F": fuller, "c": guard, "C": guard_hi,
            "G": grip, "w": (min(255, grip[0] + 34), min(255, grip[1] + 30), min(255, grip[2] + 30), 255), "y": pommel, "g": gem}


SWORD_BASIC = sword_palette(hexc("eef2fb"), hexc("b8c1d6"), hexc("77839f"), hexc("b8934a"), hexc("3d2a3f"), hexc("b8934a"), hexc("b99bff"))
SWORD_IRON = sword_palette(hexc("e6f7f0"), hexc("a4d4c4"), hexc("5f9a8c"), hexc("8fb7a5"), hexc("3a2f2a"), hexc("8fb7a5"), hexc("78f4e6"))


def outline_pass(px, color):
    h, w = len(px), len(px[0])
    out = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if px[y][x][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] == 255:
                        out[y][x] = color
                        break
    return out


def held_sword(pal, blade: int = 21):
    """Sword pointing right, grip pivot at (4, 4), sized for the 42 px heroine: gem pommel, wrapped
    grip, slim curved crossguard, then a tapering 3 px blade with a fuller. Width = 9 + blade."""
    w = 8 + blade + 1
    px = [[CLEAR] * w for _ in range(9)]
    px[3][0], px[4][0], px[5][0] = pal["y"], pal["g"], pal["y"]  # pommel with a gem
    px[3][1], px[4][1], px[5][1] = pal["C"], pal["y"], pal["y"]
    for x in range(2, 6):  # leather-wrapped grip
        px[3][x] = px[5][x] = pal["G"]
        px[4][x] = pal["w"] if x % 2 else pal["G"]
    for y in range(1, 8):  # crossguard: a slim bar whose tips curve toward the blade
        px[y][6] = pal["c"]
    px[1][7] = px[7][7] = pal["c"]
    px[2][6] = px[3][6] = pal["C"]
    for y in (3, 4, 5):  # collar where the blade enters
        px[y][7] = pal["c"]
    end = 8 + blade
    for x in range(8, end - 3):  # upper edge, bright
        px[3][x] = pal["L"]
    for x in range(8, end - 1):  # lower edge, shaded
        px[5][x] = pal["B"]
    for x in range(8, end):  # spine with a darker fuller groove
        px[4][x] = pal["F"] if 9 <= x <= 8 + int(blade * 0.62) and x % 7 != 0 else pal["M"]
    px[4][end] = pal["L"]  # tip
    return outline_pass(px, OUT_C)


def sword_icon(pal):
    px = [[CLEAR] * 16 for _ in range(16)]
    for i in range(9):  # tapering blade up-right
        x, y = 6 + i, 9 - i
        px[y][x] = pal["L"]
        if i < 8:
            px[y][x + 1] = pal["F"] if i in (1, 2, 3, 4) else pal["B"]
    px[1][15] = CLEAR
    for k in range(-2, 3):  # slim crossguard
        px[10 + k][5 + k] = pal["c"]
    px[10][5] = pal["C"]
    px[11][4] = pal["G"]
    px[12][3] = pal["w"]
    px[13][2] = pal["y"]
    px[14][1] = pal["g"]
    return outline_pass(px, OUT_C)


def training_dummy():
    px = [[CLEAR] * 24 for _ in range(32)]
    wood, wood_d = hexc("8c643e"), hexc("684830")
    straw, straw_d, straw_l = hexc("d6b86a"), hexc("b0924e"), hexc("ecd48c")
    red, white = hexc("c8453f"), hexc("f0e6d2")

    def put(x, y, c):
        if 0 <= x < 24 and 0 <= y < 32:
            px[y][x] = c

    for x in range(6, 18):  # base plate
        for y in (28, 29):
            put(x, y, wood if y == 28 else wood_d)
    for y in range(14, 28):  # post
        put(11, y, wood)
        put(12, y, wood_d)
    for x in range(4, 20):  # arms
        put(x, 15, wood)
        put(x, 16, wood_d)
    for x in (3, 20):  # straw wisps
        put(x, 14, straw)
        put(x, 16, straw_d)
    for y in range(7, 22):  # torso sack
        for x in range(5, 19):
            dx, dy = (x + 0.5 - 12) / 6.5, (y + 0.5 - 14.5) / 7.5
            d = dx * dx + dy * dy
            if d <= 1:
                c = straw_l if dx < -0.3 and dy < 0 else (straw_d if d > 0.7 else straw)
                put(x, y, c)
    for y in range(0, 8):  # head sack
        for x in range(8, 17):
            dx, dy = (x + 0.5 - 12) / 4.5, (y + 0.5 - 4) / 4.0
            if dx * dx + dy * dy <= 1:
                put(x, y, straw_l if dx < -0.2 and dy < 0 else straw)
    for x in range(10, 15):  # neck rope
        put(x, 8, wood_d)
    for y in range(9, 20):  # target
        for x in range(7, 17):
            r = math.hypot(x + 0.5 - 12, y + 0.5 - 14.5)
            if r <= 1.6:
                put(x, y, red)
            elif r <= 3.1:
                put(x, y, white)
            elif r <= 4.6:
                put(x, y, red)
    px = outline_pass(px, OUT_C)
    for x in range(4, 20):  # soft ground shadow
        if px[31][x][3] == 0:
            px[31][x] = (0, 0, 0, 60)
    return px



# ----------------------------------------------------------- shadow spider
import random

SQUASH = 0.78  # 3/4 view: ground distances are shortened vertically
SP_OUT = hexc("040208")
SP_D0 = hexc("07040d")
SP_D1 = hexc("0e0919")
SP_D2 = hexc("171029")
SP_D3 = hexc("221740")
SP_RIM = hexc("5a36b8")
SP_SPEC = hexc("a07cff")
SP_VEIN = hexc("8a4dff")
SP_VEIN_DIM = hexc("5c2fb8")
SP_CORE = hexc("ecd2ff")
SP_EYE = hexc("ff4fd8")
SP_EYE_CORE = hexc("ffe3fb")

# body-local shapes: u = forward, v = right (ground units). The rig reuses EYES and CORES for its glow.
LOBES = [(0.0, 0.0, 6.4, 4.7), (-5.0, 1.9, 3.4, 3.0), (-4.3, -2.7, 3.0, 2.8), (3.9, -0.4, 3.8, 3.4),
         (1.3, 3.5, 2.5, 2.3), (-0.8, -3.8, 2.4, 2.2), (-8.0, -0.4, 2.3, 1.8)]
EYES = [(5.8, -1.7, 0.9), (6.1, 1.2, 0.65), (4.3, -3.1, 0.5), (4.5, 2.5, 0.5), (6.9, -0.1, 0.4), (3.3, 0.2, 0.35)]
CORES = [(-1.5, 0.3, 1.4), (-4.6, 2.0, 0.9), (2.7, -1.6, 0.8)]
SPIKES = [(-8.6, 1.6, -0.3), (-7.0, -4.2, -1.9), (-2.4, 5.2, 1.5), (-1.4, -5.2, -1.6), (5.9, 2.8, 0.6), (-5.5, 4.0, 0.9)]


def _vein_points():
    rng = random.Random(7)
    pts = []
    for k in range(5):
        u, v = CORES[0][0], CORES[0][1]
        ang = rng.uniform(0, math.tau)
        for _ in range(7):
            ang += rng.uniform(-0.5, 0.5)
            for _ in range(3):
                u += math.cos(ang) * 0.4
                v += math.sin(ang) * 0.4
                pts.append((u, v))
    return pts


VEINS = _vein_points()


def spider_body(direction: int):
    """Organic void creature seen from above at 3/4: a ragged black mass with thorns, a net of
    glowing veins, asymmetric eyes and a glowing slit for a mouth. Heading = direction*45deg."""
    ang = direction * math.pi / 4
    fx, fy = math.cos(ang), math.sin(ang) / SQUASH
    n = math.hypot(fx, fy)
    fx, fy = fx / n, fy / n
    rx, ry = -fy, fx
    w, h, cx, cy = 32, 26, 16, 13
    px = [[CLEAR] * w for _ in range(h)]

    def local(x, y):
        gx, gy = x + 0.5 - cx, (y + 0.5 - cy) / SQUASH
        return gx * fx + gy * fy, gx * rx + gy * ry

    inside = {}
    for y in range(h):
        for x in range(w):
            u, v = local(x, y)
            field = min(((u - lu) / rx_) ** 2 + ((v - lv) / ry_) ** 2 for lu, lv, rx_, ry_ in LOBES)
            ragged = (noise(int(round(u * 1.7)) + 40, int(round(v * 1.7)) + 40, 5) / 255 - 0.5) * 0.45
            if field + ragged <= 1:
                inside[(x, y)] = (u, v)
    for su, sv, sang in SPIKES:  # thorns: short spikes sticking out of the mass
        for k in range(1, 4):
            u, v = su + math.cos(sang) * k * 0.8, sv + math.sin(sang) * k * 0.9
            # back to pixels: invert local()
            gx, gy = u * fx + v * rx, u * fy + v * ry
            x, y = int(round(cx + gx - 0.5)), int(round(cy + gy * SQUASH - 0.5))
            if 0 <= x < w and 0 <= y < h:
                inside[(x, y)] = (u, v)
    for (x, y) in list(inside):  # the shadow side crumbles away (dithered)
        if ((x + 1, y) not in inside or (x, y + 1) not in inside) and BAYER[y % 4][x % 4] < 5:
            del inside[(x, y)]
    for (x, y), (u, v) in inside.items():
        light = (-(x + 0.5 - cx) * 0.45 - (y + 0.5 - cy) * 0.9) / 9 * 0.5 + 0.5
        light += (BAYER[y % 4][x % 4] / 16 - 0.47) * 0.25
        c = SP_D0 if light < 0.56 else SP_D1 if light < 0.78 else SP_D2 if light < 0.93 else SP_D3
        if light > 0.97 and BAYER[y % 4][x % 4] < 3:
            c = SP_SPEC  # wet highlights
        px[y][x] = c
    for (x, y) in inside:  # violet rim light on the upper-left edge
        if (x - 1, y) not in inside or (x, y - 1) not in inside:
            if px[y][x] in (SP_D0, SP_D1, SP_D2, SP_D3):
                px[y][x] = SP_RIM

    def dot(uu, vv, col, r):
        for (x, y), (u, v) in inside.items():
            if (u - uu) ** 2 + (v - vv) ** 2 <= r * r:
                px[y][x] = col

    for (x, y), (u, v) in inside.items():  # vein network
        if any((u - pu) ** 2 + (v - pv) ** 2 < 0.16 for pu, pv in VEINS):
            px[y][x] = SP_VEIN if BAYER[y % 4][x % 4] < 7 else SP_VEIN_DIM
    for (x, y), (u, v) in inside.items():  # mouth: a curved glowing slit at the front
        if abs(v) < 2.0 and abs(u - (7.7 - 0.22 * v * v)) < 0.5:
            px[y][x] = SP_VEIN
    for cu, cv, r in CORES:
        dot(cu, cv, SP_VEIN_DIM, r + 0.6)
        dot(cu, cv, SP_VEIN, r)
        dot(cu, cv, SP_CORE, r * 0.5)
    for eu, ev, r in EYES:
        dot(eu, ev, SP_EYE, r)
        dot(eu, ev, SP_EYE_CORE, r * 0.45)
    return outline_pass(px, SP_OUT)


def spider_sheet():
    sheet = [[CLEAR] * (32 * 8) for _ in range(26)]
    for d in range(8):
        body = spider_body(d)
        for y in range(26):
            for x in range(32):
                sheet[y][d * 32 + x] = body[y][x]
    return sheet



# --------------------------------------------------------------- loot items
def splinter_icon():
    """A cluster of black crystal splinters with violet edges and a glowing seam."""
    px = [[CLEAR] * 16 for _ in range(16)]
    shards = [
        [(8, 1), (11, 6), (9.6, 13.6), (6.4, 13.6), (5, 6)],
        [(2.6, 6.2), (5.6, 8.2), (5, 13.4), (2.2, 12)],
        [(13.4, 7), (14.8, 10.2), (13.2, 13.4), (10.4, 12.2)],
    ]

    def inside(poly, x, y):
        hit = False
        for i in range(len(poly)):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                hit = not hit
        return hit

    for poly in shards:
        xs = [p[0] for p in poly]
        left, right = min(xs), max(xs)
        for y in range(16):
            for x in range(16):
                if inside(poly, x + 0.5, y + 0.5):
                    t = (x + 0.5 - left) / max(right - left, 1)
                    px[y][x] = hexc("3a2370") if t < 0.22 else hexc("221740") if t < 0.5 else hexc("120b22") if t < 0.8 else hexc("07040d")
    for y in range(3, 12):  # glowing seam through the big shard
        px[y][8] = hexc("8a4dff")
    px[6][8] = hexc("ecd2ff")
    px[7][8] = hexc("c6a2ff")
    px[10][3] = hexc("8a4dff")
    px[11][12] = hexc("8a4dff")
    return outline_pass(px, hexc("040208"))


def core_icon():
    """A black orb with a violet rim, glowing cracks and a bright core."""
    px = [[CLEAR] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            d = math.hypot(x + 0.5 - 8, y + 0.5 - 8)
            if d <= 5.4:
                shade = (-(x - 8) * 0.5 - (y - 8) * 0.9) / 6
                px[y][x] = hexc("07040d") if shade < 0.1 else hexc("0e0919") if shade < 0.45 else hexc("221740")
                if d > 4.4 and shade > 0.2:
                    px[y][x] = hexc("5a36b8")
    for x, y in ((5, 6), (6, 7), (10, 6), (9, 7), (8, 10), (8, 11), (6, 10)):  # cracks
        px[y][x] = hexc("8a4dff")
    for x, y in ((7, 8), (8, 8), (7, 7), (8, 7)):  # core
        px[y][x] = hexc("ecd2ff")
    px[8][8] = hexc("ffffff")
    for x, y in ((8, 2), (13, 8), (2, 8), (8, 13)):  # tiny sparks around the orb
        px[y][x] = hexc("8a4dff")
    return outline_pass(px, hexc("040208"))


# ---------------------------------------------------- blink (void ability)
VOID = hexc("07040f")
DEEP_V = hexc("1a0b33")
RIM_V = hexc("5b2a9e")
RIM_HI = hexc("9b5cff")
STAR = hexc("c9a0ff")
GLOW_V = (90, 40, 170, 110)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
RIFT_RX = [2.0, 8.0, 13.0, 16.0, 11.0, 4.0]  # open, full, collapse


def rift_frame(k: int):
    """Flattened (3/4 view) black rift with a violet rim and tendril spikes."""
    rx = RIFT_RX[k]
    ry = rx * 0.5
    fr = [[CLEAR] * 40 for _ in range(20)]
    for y in range(20):
        for x in range(40):
            dx, dy = (x + 0.5 - 20) / rx, (y + 0.5 - 10) / ry
            spike = max(0.0, math.cos(5 * math.atan2(dy, dx) + k * 0.7)) ** 5
            d = math.hypot(dx, dy) / (1 + spike * 0.4)
            b = BAYER[y % 4][x % 4] / 16
            if d < 0.45:
                c = VOID
            elif d < 0.78:
                c = VOID if b < (0.78 - d) / 0.33 else DEEP_V
            elif d <= 1.0:
                c = RIM_HI if (dy < 0 and d > 0.88) else RIM_V
            elif d <= 1.25 and b < (1.25 - d) / 0.25 * 0.6:
                c = GLOW_V
            else:
                c = CLEAR
            if c in (VOID, DEEP_V) and noise(x, y, k + 3) > 244:
                c = STAR
            fr[y][x] = c
    return fr


def rift_sheet():
    sheet = [[CLEAR] * 240 for _ in range(20)]
    for k in range(6):
        fr = rift_frame(k)
        for y in range(20):
            for x in range(40):
                sheet[y][k * 40 + x] = fr[y][x]
    return sheet


def shard():
    w = (255, 255, 255, 255)
    return [[CLEAR, w, CLEAR], [w, w, w], [CLEAR, w, CLEAR]]


if __name__ == "__main__":  # swords, axe, pickaxe and sickle live in tools/art_weapons.py
    write_png(ROOT / "props" / "training_dummy.png", 24, 32, training_dummy())
    write_png(ROOT / "enemies" / "shadow_spider_body.png", 256, 26, spider_sheet())
    write_png(ROOT / "items" / "void_splinter.png", 16, 16, splinter_icon())
    write_png(ROOT / "items" / "shadow_core.png", 16, 16, core_icon())
    write_png(ROOT / "fx" / "puff.png", 4, 4, puff())
    write_png(ROOT / "fx" / "footprint.png", 5, 3, footprint())
    write_png(ROOT / "fx" / "blink_rift.png", 240, 20, rift_sheet())
    write_png(ROOT / "fx" / "void_shard.png", 3, 3, shard())
    write_png(ROOT / "fx" / "dust.png", 4, 4, dust_puff())
