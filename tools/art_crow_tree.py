"""Der Rabenbaum: the great, suffering raven tree in the middle of the Schieferkessel (boss 2, docs/enemies/boss_mora.md).

    py -3 tools/art_crow_tree.py [preview.png]

Writes assets/props/crow_tree/{pad,trunk,crown,moss,charms,glow,veins}.png (320x360, feet at (160, 340)) and crow_tree.json (layers, 16 perches in
frame pixels, the hollow, the collision), plus docs/img/crow_tree.png (day / night / witch hour / freed).

Painted pixel by pixel with the Hexenwald's own tree language (tools/art_hexenwald.py: Hexenulme and Bleichbaum), three times their size:
the same six-tone ramps, light from the top left, a cool rim on the right, ink outline.
  wood    every limb is a crooked, knuckled, tapering path that kinks, forks and ends in a claw or a bleached break (`grow`); it is shaded as a
          round body and its bark is furrowed ALONG the limb, winding round it; moss lies on whatever faces up, lichen crusts on the lit side,
          burls, knots, shelf fungi. The trunk is a twisted S with gnarls on roots that arch and grip like fingers.
  crown   not balls: hunched cushions of small leaf lobes with a scalloped leaf texture, lit hems, tatters underneath and holes where the dead wood
          shows; darker masses sit BEHIND the boughs (they are part of the trunk layer), the bright ones in front (the crown layer, it sways).
  moss    long strands of witch hair from the hems and the undersides of the boughs.
What Morwenna did to the tree is on layers of its own so the game can drive it (src/entities/props/crow_tree.gd):
  veins   the ritual: cracks of violet and witch-green light (#a8ff6a) that creep in along four roots, meet in the hollow and climb the trunk into the
          boughs. They pulse; in the witch hour they blaze green; when the tree is freed they go out.
  charms  cursed mirror splinters, bones and twig charms on threads, and the fetters: sagging cords strung with splinters from bough to bough.
  trunk   also carries three root ropes wound round it, the splinters she drove in round the hollow and cobwebs between the roots."""
import json, math, random, sys
import numpy as np
from PIL import Image
from gen_art import ROOT, hexc, noise

W, H, FX, FY = 320, 360, 160, 340
OUT = ROOT / 'props' / 'crow_tree'


def ramp(*c):
    return [hexc(x) for x in c]


LEAF = ramp("0a0e20", "0f1c2c", "15303a", "1d4a48", "2d6a58", "4e9070")
RIM = ramp("1c5a6a", "3a9aa8")
BARK = ramp("0c0812", "1a1322", "2c2236", "44344c", "625064", "8c7880")
BONE = ramp("2e2a44", "56506c", "8a8698", "b8b4b8", "dedacc", "f6f2e0")
LICHEN = ramp("2e3a40", "4c6060", "7a9488", "a8c4b0")
HAIR = ramp("1e3038", "34504e", "557468", "86a08a")
WINE = ramp("2a0612", "5a0a1e", "8e1430", "c43044", "ee6a6a")
HOOD = ramp("120a26", "26124a", "40207a", "6434a6", "9458cc", "c690ec")
ROPE = ramp("1c1512", "33271e", "4e3c2e", "6e5642", "927660")
MIRROR = ramp("22303e", "3e566c", "6a8296", "a6c0cc", "ecf8fb")
RAG = ramp("5a0a1e", "9a1830", "d03a48")
HEX_DIM, HEX, HEX_HOT = hexc("4a9a3a"), hexc("a8ff6a"), hexc("eaffc4")
VIO_DIM, VIO, VIO_HOT = hexc("6434a6"), hexc("c690ec"), hexc("ecdcff")
INK = hexc("0b1620")
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
rng = random.Random(7142)


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def layer():
    return np.zeros((H, W, 4), np.uint8)


def put(g, x, y, c, over=True):
    x, y = int(x), int(y)
    if 0 <= x < W and 0 <= y < H and (over or g[y, x, 3] == 0):
        g[y, x] = c


def light_px(base, glow, x, y, dim, bright, halo=1):
    """A glowing pixel: the dim colour into the lit art, the bright one with a soft halo into the glow layer."""
    if base is not None:
        put(base, x, y, dim)
    put(glow, x, y, bright)
    for dy in range(-halo - 1, halo + 2):
        for dx in range(-halo - 1, halo + 2):
            d = math.hypot(dx, dy)
            xx, yy = int(x) + dx, int(y) + dy
            if 0 < d <= halo + 0.5 and 0 <= xx < W and 0 <= yy < H and glow[yy, xx, 3] == 0:
                glow[yy, xx] = (*bright[:3], 110 if d < 1.6 else 52)


# ================================================================== wood: paths first, then one shading pass
Z = np.full((H, W), -1e9)
S = np.zeros((H, W)); A = np.zeros((H, W)); R = np.zeros((H, W)); ANG = np.zeros((H, W))
KIND = np.full((H, W), -1, np.int8); BLEACH = np.zeros((H, W), bool); BACK = np.zeros((H, W))
pieces, tips, seats, hangs = [], [], [], []


def stamp(x, y, r, ang, along, kind, z0, bleach):
    nx, ny = -math.sin(ang), math.cos(ang)
    tx, ty = math.cos(ang), math.sin(ang)
    rr = int(math.ceil(r)) + 1
    cx, cy = int(round(x)), int(round(y))
    for dy in range(-rr, rr + 1):
        yy = cy + dy
        if yy < 0 or yy >= H:
            continue
        for dx in range(-rr, rr + 1):
            xx = cx + dx
            if xx < 0 or xx >= W:
                continue
            ox, oy = xx - x, yy - y
            across = ox * nx + oy * ny
            lon = ox * tx + oy * ty
            if abs(across) > r + 0.15 or abs(lon) > 1.1 + (0.5 if r < 1.2 else 0.0):
                continue
            s = clamp(across / max(r, 0.6), -1.0, 1.0)
            z = z0 + math.sqrt(max(0.0, 1.0 - s * s)) * r * 0.8
            if z > Z[yy, xx]:
                Z[yy, xx] = z; S[yy, xx] = s; A[yy, xx] = along; R[yy, xx] = r; ANG[yy, xx] = ang
                KIND[yy, xx] = kind; BLEACH[yy, xx] = bleach; BACK[yy, xx] = z0


def lay(pts, kind, z0, broken=False):
    n = len(pts)
    for i, (x, y, r, ang) in enumerate(pts):
        stamp(x, y, r, ang, i, kind, z0, broken and i > n - 6)
    pieces.append((pts, kind, z0))


def grow(x, y, ang, length, width, depth, z, level=None, kind=1):
    """A crooked, tapering limb: it kinks at knuckles, may run out level (the ravens' seats), sheds spurs of dry twig, forks into thinner limbs and
    ends in a claw or a bleached break. Returns its own path."""
    bend = rng.uniform(-0.03, 0.03)
    steps = max(3, int(length))
    pts = []
    knuckle = rng.randrange(5, 9)
    for i in range(steps):
        t = i / steps
        w = max(0.55, width * (1.0 - 0.5 * t))
        pts.append((x, y, w, ang))
        if i % knuckle == knuckle - 1:
            ang += rng.uniform(-0.36, 0.36)
            knuckle = rng.randrange(5, 9)
        ang += bend
        if level is not None and 0.22 < t < 0.9:
            ang += clamp(math.atan2(math.sin(level - ang), math.cos(level - ang)), -0.02, 0.02) + 0.035 * math.sin(i * 0.19 + length)
        elif depth >= 1 and level is None:
            ang -= 0.012 * math.cos(ang)
        if x < 12 or x > W - 13 or y < 12:                                              # the frame: turn back in
            toward = math.atan2(120 - y, FX - x)
            ang += clamp(math.atan2(math.sin(toward - ang), math.cos(toward - ang)), -0.14, 0.14)
        x += math.cos(ang); y += math.sin(ang)
        if abs(math.sin(ang)) < 0.42 and w >= 1.9 and 0.15 < t < 0.97 and i % 3 == 0:
            seats.append((x, y - w, w))
        if w >= 1.3 and i % 6 == 3:
            hangs.append((x, y + w, z))
        if 0.9 <= w < 4.6 and i % 8 == 5 and rng.random() < 0.72 and depth >= 0:        # dry spurs
            side = rng.choice((-1, 1))
            grow(x, y, ang + side * rng.uniform(0.6, 1.25), rng.uniform(5, 13) + w * 1.5, min(0.95, w * 0.42), -1, z - 0.5)
    broken = depth >= 0 and width >= 1.4 and rng.random() < (0.38 if depth <= 1 else 0.14)
    lay(pts, kind, z, broken)
    if depth <= 0 or width < 0.9 or broken:
        if not broken:                                                                 # the claw
            hook = 1 if math.cos(ang) > 0 else -1
            lay([(x + (hook if k > 1 else 0) * 0.9, y + k - 1, 0.55, math.pi / 2) for k in range(1, 4)], kind, z)
        tips.append((x, y, depth, z))
        return pts
    spread = rng.uniform(0.5, 0.9)
    side = rng.choice((-1, 1))
    grow(x, y, ang - side * spread * 0.55, length * rng.uniform(0.6, 0.78), width * 0.64, depth - 1, z + rng.uniform(-2, 2))
    grow(x, y, ang + side * spread, length * rng.uniform(0.45, 0.62), width * 0.5, depth - 1, z + rng.uniform(-2, 2))
    if depth >= 3 and rng.random() < 0.7:
        grow(x, y, ang + rng.uniform(-0.25, 0.25), length * 0.5, width * 0.45, depth - 2, z + rng.uniform(-2, 2))
    return pts


def side_limbs(x, y, ang, length, width, depth, z, level):
    """A heavy bough with further limbs leaving its back along the way."""
    pts = grow(x, y, ang, length, width, depth, z, level)
    for f in (0.3, 0.52, 0.72):
        px, py, pw, pa = pts[int(len(pts) * f)]
        grow(px, py - pw * 0.5, -math.pi / 2 + rng.uniform(-0.7, 0.7) + 0.5 * math.cos(pa), length * rng.uniform(0.42, 0.6), pw * 0.56, max(depth - 2, 1), z + rng.uniform(-3, 3))


TRUNK = {}


def trunk_path():
    top, base = 196, 336
    phase = 1.3
    pts = []
    for y in range(base, top - 1, -1):
        t = (base - y) / (base - top)
        cx = FX + 7.0 * (math.sin(t * 3.4 + phase) - math.sin(phase)) * (0.4 + 0.6 * t)
        bulge = 1.0 + 0.13 * math.sin(t * 9.0 + 2.1) + 0.06 * math.sin(t * 23.0)
        hw = 21.5 * (1.0 - 0.34 * t) * bulge + max(0.0, (y - 318) * 0.7)
        TRUNK[y] = (cx, hw)
        pts.append((cx, y, hw))
    out = []
    for i, (cx, y, hw) in enumerate(pts):
        nxt = pts[min(i + 1, len(pts) - 1)]; prv = pts[max(i - 1, 0)]
        out.append((cx, y, hw, math.atan2(nxt[1] - prv[1], nxt[0] - prv[0])))
    return out


def root(side, reach, lift, w0, front, start_hw):
    """A root like a finger: it leaves the foot, arches, and digs its tip into the slate."""
    pts = []
    n = int(reach)
    x0 = FX + side * start_hw
    y0 = 326 + front * 0.5
    wob = rng.uniform(0, 6)
    for k in range(n):
        u = k / n
        x = x0 + side * k + math.sin(u * 5.0 + wob) * 2.0 * u
        y = y0 + front * u ** 0.8 * 0.5 + 7.0 * u - lift * math.sin(min(1.0, u * 1.25) * math.pi) ** 0.9 + (3.0 * (u - 0.88) / 0.12 if u > 0.88 else 0.0)
        pts.append((x, y, max(0.9, w0 * (1.0 - 0.82 * u))))
    out = []
    for i, (x, y, w) in enumerate(pts):
        nxt = pts[min(i + 1, n - 1)]; prv = pts[max(i - 1, 0)]
        out.append((x, y, w, math.atan2(nxt[1] - prv[1], nxt[0] - prv[0])))
    lay(out, 2, 6.0 + front * 0.6)
    if reach > 50:                                                                      # a rootlet forks off
        bx, by, bw, ba = out[int(n * rng.uniform(0.4, 0.6))]
        fork = []
        m = int(reach * 0.3)
        for k in range(m):
            u = k / m
            fork.append((bx + side * k * 0.8, by + k * 0.36 * (1 if front >= 6 else -0.6) + 1.5 * u, max(0.7, bw * 0.6 * (1 - u)), ba + 0.5 * side))
        lay(fork, 2, 5.0 + front * 0.6)
    return out


def shade_wood(g):
    n = len(BARK)
    for y in range(H):
        for x in range(W):
            kind = KIND[y, x]
            if kind < 0:
                continue
            s, r, ang, a = S[y, x], R[y, x], ANG[y, x], A[y, x]
            nx, ny = -math.sin(ang) * s, math.cos(ang) * s
            nz = math.sqrt(max(0.0, 1.0 - s * s))
            light = (nx * -0.55 + ny * -0.75 + nz * 0.6 + 1.0) / 2.0
            v = light * (n - 1.5) + (noise(x, y, 12) / 255.0 - 0.5) * 1.0
            if r >= 2.0:                                                                # the bark winds round the limb
                band = (s * r * 1.3 + a * (0.55 if kind == 0 else 0.42) + noise(x // 3, y // 5, 7) / 60.0) % 4.2
                if band < 1.15:
                    v -= 1.25
                elif band > 3.3 and light > 0.42:
                    v += 0.55
                if r >= 9 and (s * r * 0.5 + a * 0.19 + noise(x // 4, y // 7, 9) / 40.0) % 9.0 < 0.9:   # deep old furrows on the trunk
                    v -= 1.1
            elif r >= 1.2 and int(a) % 7 == 0 and noise(x, y, 5) > 120:
                v -= 0.9
            v -= clamp(-BACK[y, x] / 26.0, 0.0, 1.0) * 1.15                             # limbs behind the trunk sink into the shade
            c = BARK[int(clamp(v, 0, n - 2))]
            if BLEACH[y, x]:
                c = BONE[int(clamp(1.0 + light * 4.2 + (noise(x, y, 3) / 255.0 - 0.5), 1, 5))]
            elif -ny > 0.42 and r >= 1.6 and noise(x // 2, y // 2, 31) > (118 if kind != 0 else 190) and noise(x, y, 32) > 60:   # moss on what faces up
                c = HAIR[int(clamp(1.0 + light * 2.4 + (noise(x, y, 33) / 255.0 - 0.5), 0, 3))]
            g[y, x] = c


def trunk_details(g, glow):
    # burls and knots: a dark ring, a lit bump inside
    for y, off, rad in ((300, -0.55, 5), (268, 0.5, 4), (240, -0.35, 4), (216, 0.42, 3), (282, 0.72, 3)):
        cx, hw = TRUNK[y]
        kx = int(cx + off * hw)
        for dy in range(-rad - 1, rad + 2):
            for dx in range(-rad - 1, rad + 2):
                d = math.hypot(dx, dy * 1.15)
                if d <= rad + 0.5 and KIND[y + dy, kx + dx] == 0:
                    tone = 1 if d > rad - 0.9 else (4 if (dx < 0 and dy < 0 and d > rad - 2.2) else (0 if d < 1.2 else 2 + int(d % 2)))
                    g[y + dy, kx + dx] = BARK[tone]
    # broken stubs on the trunk: a short peg with a bleached end
    for y, side, length in ((252, -1, 9), (228, 1, 11), (276, 1, 7)):
        cx, hw = TRUNK[y]
        for k in range(length):
            x = int(cx + side * (hw - 1 + k)); yy = y - k // 3
            for j, tone in ((-1, 4 if side < 0 else 3), (0, 3), (1, 1)):
                put(g, x, yy + j, BARK[tone] if k < length - 2 else BONE[3 - j])
    # lichen crusts on the lit side
    for _ in range(11):
        y = rng.randrange(206, 322)
        cx, hw = TRUNK[y]
        x0 = int(cx - hw * rng.uniform(0.1, 0.8))
        for _k in range(rng.randrange(5, 11)):
            xx, yy = x0 + rng.randrange(-3, 4), y + rng.randrange(-2, 3)
            if 0 <= yy < H and KIND[yy, xx] == 0:
                put(g, xx, yy, LICHEN[rng.randrange(1, 4)])
        if rng.random() < 0.6:
            light_px(g, glow, x0, y, LICHEN[3], HEX if rng.random() < 0.6 else VIO, 1)
    # shelf fungi: pale caps, wine red gills that breathe light
    for i, (y, side, size) in enumerate(((246, -1, 7), (262, 1, 6), (286, -1, 8), (224, 1, 5), (308, 1, 7), (296, -1, 5))):
        cx, hw = TRUNK[y]
        for k in range(size):
            x = int(cx + side * (hw - 2 + k))
            drop = 1 if k > size - 3 else 0
            put(g, x, y - 1 + drop, BONE[5 if k < size - 2 else 4])
            put(g, x, y + drop, BONE[4 if k < size - 2 else 3])
            put(g, x, y + 1 + drop, WINE[2 if k < size // 2 else 1])
            if k % 2 == 1:
                put(g, x, y + 2 + drop, WINE[0])
                light_px(None, glow, x, y + 2 + drop, WINE[1], VIO if i % 2 else HEX, 0)
        light_px(g, glow, int(cx + side * hw), y - 2, BONE[5], HEX_HOT if i % 2 else VIO_HOT, 1)


def ropes(g):
    """Three ropes of root wound round the trunk: twisted strands, a shadow under them, a knot and a frayed end."""
    for y0, slope in ((284, 0.22), (262, -0.16), (236, 0.14)):
        cx, hw = TRUNK[y0]
        for dx in range(-int(hw) - 1, int(hw) + 2):
            x = int(cx) + dx
            y = int(round(y0 + dx * slope + 1.6 * (1 - (dx / max(hw, 1)) ** 2)))
            if KIND[y, x] != 0 and KIND[y + 1, x] != 0:
                continue
            lit = 0.5 - 0.5 * dx / max(hw, 1)
            twist = (dx + y0) % 3
            put(g, x, y - 1, ROPE[int(clamp(1 + lit * 3 + (1 if twist == 0 else 0), 1, 4))])
            put(g, x, y, ROPE[int(clamp(0.5 + lit * 3 - (1 if twist == 1 else 0), 0, 4))])
            put(g, x, y + 1, ROPE[int(clamp(lit * 2, 0, 2))])
            put(g, x, y + 2, BARK[0])
        kx = int(cx + hw * 0.25); ky = int(y0 + hw * 0.25 * slope + 1)
        for dx, dy, tone in ((0, 0, 4), (1, 0, 3), (0, 1, 3), (1, 1, 2), (-1, 0, 3), (2, 1, 1), (0, 2, 1)):
            put(g, kx + dx, ky + dy, ROPE[tone])
        for k in range(rng.randrange(6, 11)):
            put(g, kx + 1 + (k // 4), ky + 3 + k, ROPE[3 if k < 3 else 2 if k < 7 else 1])
        put(g, kx, ky + 12, ROPE[2]); put(g, kx + 3, ky + 12, ROPE[1])


def splinter(g, x, y, ang, length, glow=None):
    """A mirror splinter: a kite of cold glass with one hard glint."""
    fx, fy = math.cos(ang), math.sin(ang)
    for k in range(length):
        t = k / max(length - 1, 1)
        half = 0.4 + 1.9 * math.sin(min(1.0, t * 1.5) * math.pi * 0.62)
        for j in range(-2, 3):
            if abs(j) > half:
                continue
            tone = 3 if j < 0 else 2
            if abs(j) >= half - 0.9:
                tone = 1 if j > 0 else 4
            put(g, round(x + fx * k - fy * j), round(y + fy * k + fx * j), MIRROR[tone])
    gx, gy = round(x + fx * length * 0.35 + fy), round(y + fy * length * 0.35 - fx)
    put(g, gx, gy, MIRROR[4])
    if glow is not None:
        light_px(None, glow, gx, gy, MIRROR[4], hexc("ffffff"), 1)


def hollow(g, glow):
    """The hollow she crawled into: a ragged black mouth, a lit lip, the violet heart that will not stop, and the splinters she drove in round it."""
    cy = 300
    cx, hw = TRUNK[cy]
    cx = int(cx + 1)
    for dy in range(-17, 18):
        for dx in range(-9, 10):
            edge = (dx / 7.6) ** 2 + (dy / 15.0) ** 2 + (noise(dx + 20, dy + 20, 44) / 255.0 - 0.5) * 0.22
            x, y = cx + dx, cy + dy
            if edge < 1.0:
                put(g, x, y, hexc("05030a") if edge < 0.62 else BARK[0])
            elif edge < 1.42 and KIND[y, x] == 0:
                put(g, x, y, BARK[4 if (dx > 0 and dy > -4) or dy > 9 else 1])
    for k in range(7):                                                                  # teeth of torn wood in its upper lip
        put(g, cx - 6 + k * 2, cy - 12 + abs(k - 3) // 2 + (k % 2) * 2, BARK[2])
    light_px(g, glow, cx, cy + 3, VIO_DIM, VIO_HOT, 3)
    light_px(g, glow, cx - 1, cy + 4, VIO_DIM, VIO, 2)
    light_px(g, glow, cx + 1, cy + 2, VIO_DIM, VIO, 2)
    for k in range(6):
        light_px(g, glow, cx + (-3, 2, -2, 3, 0, -1)[k], cy + (-5, -7, 8, 6, -9, 11)[k], hexc("26124a"), VIO_DIM, 0)
    for ang, dist in ((-2.5, 12), (-1.9, 17), (-1.1, 16), (-0.5, 12), (0.5, 12), (2.7, 13)):
        splinter(g, cx + math.cos(ang) * dist * 0.72, cy + math.sin(ang) * dist, ang, 8, glow)
    return cx, cy


def cobwebs(g):
    for (x0, y0), fan in (((132, 330), (-2.6, -1.3)), ((190, 331), (-1.9, -0.5)), ((118, 337), (-2.9, -1.9))):
        for k5 in range(5):
            ang = fan[0] + (fan[1] - fan[0]) * k5 / 4
            for k in range(2, 16):
                put(g, x0 + math.cos(ang) * k, y0 + math.sin(ang) * k, (206, 204, 226, 120), over=False)
        for ring in (6, 10, 14):
            for k in range(40):
                ang = fan[0] + (fan[1] - fan[0]) * k / 39
                sag = 1.0 - 0.12 * math.sin((k % 10) / 10 * math.pi)
                put(g, x0 + math.cos(ang) * ring * sag, y0 + math.sin(ang) * ring * sag, (190, 190, 214, 84), over=False)


# ================================================================== leaves
def lobes_shade(g, lobes, seed, bias):
    """The union of the lobes shaded like cushions (top left light, ordered dither), as tools/art_willow.py does for every crown of the world."""
    depth = np.full((H, W), -1e9); normal = {}
    for cx, cy, rx, ry, cz in lobes:
        for y in range(max(0, int(cy - ry) - 1), min(H, int(cy + ry) + 2)):
            for x in range(max(0, int(cx - rx) - 1), min(W, int(cx + rx) + 2)):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                d = dx * dx + dy * dy
                if d >= 1.0:
                    continue
                z = math.sqrt(1.0 - d)
                zw = cz * 2.0 + z * max(rx, ry) * 0.8
                if zw > depth[y, x]:
                    depth[y, x] = zw; normal[(x, y)] = (dx, dy, z)
    for (x, y), nrm in normal.items():
        light = (nrm[0] * -0.55 + nrm[1] * -0.75 + nrm[2] * 0.6 + 1.0) / 2.0 + bias
        light += (noise(x, y, seed) / 255.0 - 0.5) * 0.3
        v = light * (len(LEAF) - 0.2) + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.8
        g[y, x] = LEAF[int(clamp(v, 0, len(LEAF) - 1))]


def leaf_pass(g, seed, front):
    """Leaf texture: scalloped rows, violet in the deepest shade, a rare dead leaf; then the lit contour (top, left) and the cool rim (right)."""
    index = {c[:3]: i for i, c in enumerate(LEAF)}
    k_of = np.full((H, W), -1)
    for y in range(H):
        for x in range(W):
            if g[y, x, 3]:
                k_of[y, x] = index.get(tuple(int(v) for v in g[y, x, :3]), -1)
    plain = np.zeros((H, W), bool)
    for y in range(H):
        for x in range(W):
            k = int(k_of[y, x])
            if k < 0:
                continue
            row = (x + (y // 3) * 2) % 5
            if row == 0 and y % 3 == 0 and 1 <= k <= 4:
                k -= 1
            elif row == 1 and y % 3 == 1 and 1 <= k <= 3:
                k += 1
            elif row == 3 and y % 3 == 2 and 2 <= k <= 4 and noise(x, y, seed + 3) > 150:   # a leaf's lit edge
                k += 1
            g[y, x] = LEAF[k]
            plain[y, x] = True
            if k == 0 and noise(x, y, seed + 6) > 170:
                g[y, x] = HOOD[1]; plain[y, x] = False
            elif k == 3 and noise(x, y, seed + 7) > 254 and noise(x // 2, y, seed + 17) > 128:
                g[y, x] = WINE[2]; plain[y, x] = False
            elif k == 2 and noise(x, y, seed + 8) > 254:
                g[y, x] = hexc("5a4a32"); plain[y, x] = False
            k_of[y, x] = k
    if not front:
        return
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            k = int(k_of[y, x])
            if k < 0 or not plain[y, x]:
                continue
            if k_of[y - 1, x] < 0:
                g[y, x] = LEAF[min(k + 2, 5)]
            elif k_of[y, x - 1] < 0 and k < 5:
                g[y, x] = LEAF[k + 1]
            elif k_of[y, x + 1] < 0 and noise(x, y, seed + 9) > 110 and 1 <= k <= 3:
                g[y, x] = RIM[int(noise(x, y, seed + 10) > 170)]


def masses_for(picks, scale, r):
    lobes = []
    for mx, my, depth, z in picks:
        rad = r.uniform(12.0, 20.0) * scale
        for _ in range(8 + int(rad * 1.0)):                                             # cushions of leaves, flatter than round, heavier below
            a, d = r.uniform(0, math.tau), math.sqrt(r.random())
            lr = clamp(rad * r.uniform(0.26, 0.46), 3.4, 8.6)
            lobes.append((mx + math.cos(a) * d * rad * 1.05, my - rad * 0.2 + math.sin(a) * d * rad * 0.6, lr, lr * 0.8, my * 0.03 + r.uniform(0, 2)))
        for _ in range(int(rad / 2.0)):                                                 # tatters under the hem
            lobes.append((mx + r.uniform(-1, 1) * rad, my - rad * 0.2 + rad * r.uniform(0.45, 0.8), r.uniform(1.8, 3.2), r.uniform(2.4, 4.8), 6.0))
    return [(clamp(x, rx + 3, W - rx - 4), max(ry + 4, y), rx, ry, z) for x, y, rx, ry, z in lobes]


def outline(g, color=INK):
    solid = g[..., 3] == 255
    near = np.zeros_like(solid)
    near[1:, :] |= solid[:-1, :]; near[:-1, :] |= solid[1:, :]; near[:, 1:] |= solid[:, :-1]; near[:, :-1] |= solid[:, 1:]
    g[near & (g[..., 3] == 0)] = color


# ================================================================== what hangs in it
def witch_hair(g, crown):
    r = random.Random(41)
    hems = [(x, y) for y in range(20, 250) for x in range(4, W - 4) if crown[y, x, 3] and not crown[y + 1, x, 3]]
    spots = [(int(x), int(y)) for x, y, z in hangs if y < 250]
    for i in range(88):
        x, y = r.choice(hems) if (i % 3 and hems) else r.choice(spots)
        length = r.randrange(6, 30)
        for k in range(length):
            xx = x + int(round(math.sin(k * 0.33 + x) * min(k / 8.0, 1.0) * 1.3))
            put(g, xx, y + 1 + k, HAIR[1 if k < length * 0.4 else (2 if k < length - 2 else 3)], over=False)
            if k > 3 and k % 5 == 2 and r.random() < 0.5:
                put(g, xx + r.choice((-1, 1)), y + 1 + k, HAIR[1], over=False)


def charms(g, glow):
    r = random.Random(17)
    spots = [(int(x), int(y)) for x, y, z in hangs if 70 < y < 236 and abs(x - FX) > 22 and 12 < x < W - 12]
    r.shuffle(spots)
    used = []
    for x, y in spots:
        if len(used) >= 17 or any(abs(x - a) < 13 for a, _ in used):
            continue
        used.append((x, y))
        kind = ("mirror", "mirror", "bone", "mirror", "twig", "rag", "mirror", "wisp")[len(used) % 8]
        thread = r.randrange(6, 20)
        for k in range(1, thread + 1):
            put(g, x, y + k, HAIR[0])
        cy = y + thread + 1
        if kind == "mirror":
            put(g, x, cy, ROPE[3]); put(g, x, cy - 1, ROPE[2])
            splinter(g, x, cy + 1, math.pi / 2 + r.uniform(-0.25, 0.25), r.randrange(8, 12), glow)
        elif kind == "bone":
            for k in range(6):
                put(g, x, cy + k, BONE[5 if k < 3 else 4])
            put(g, x - 1, cy, BONE[4]); put(g, x + 1, cy, BONE[3]); put(g, x - 1, cy + 5, BONE[3]); put(g, x + 1, cy + 5, BONE[4])
        elif kind == "twig":
            for k in range(5):
                put(g, x - k, cy + k, BARK[4]); put(g, x + k, cy + k, BARK[3])
            for k in range(-4, 5):
                put(g, x + k, cy + 5, BARK[4 if k < 0 else 2])
            light_px(g, glow, x, cy + 3, HEX_DIM, HEX, 2)
        elif kind == "rag":
            for k in range(r.randrange(6, 11)):
                put(g, x + (1 if (k // 2) % 2 else 0), cy + k - 1, RAG[2 if k < 2 else (1 if k < 6 else 0)])
                put(g, x + (1 if (k // 2) % 2 else 0) + 1, cy + k - 1, RAG[1 if k < 4 else 0])
        else:
            for dx, dy in ((-1, 0), (1, 0), (-2, 1), (2, 1), (-2, 2), (2, 2), (-2, 3), (2, 3), (-1, 4), (1, 4), (0, 5), (0, -1)):
                put(g, x + dx, cy + dy, BARK[3 if dx < 0 else 2])
            light_px(g, glow, x, cy + 2, HEX, HEX_HOT, 3)
    # the fetters: cords that sag from bough to bough, strung with splinters and knots
    anchors = sorted((s for s in spots if s[1] < 190), key=lambda s: s[0])
    n = len(anchors)
    pairs = [(anchors[1], anchors[n // 2 - 1]), (anchors[n // 2 + 1], anchors[n - 2]), (anchors[n // 3], anchors[2 * n // 3])] if n > 8 else []
    for (ax, ay), (bx, by) in pairs:
        span = max(abs(bx - ax), 1)
        sag = span * 0.3
        for k in range(span + 1):
            t = k / span
            x = ax + (bx - ax) * t
            y = ay + (by - ay) * t + sag * math.sin(t * math.pi)
            put(g, x, y, ROPE[2 if k % 3 else 3]); put(g, x, y + 1, ROPE[0], over=False)
            if k % 17 == 9:
                splinter(g, x, y + 2, math.pi / 2 + r.uniform(-0.2, 0.2), r.randrange(5, 8), glow)
            elif k % 17 == 2:
                put(g, x, y + 2, ROPE[3]); put(g, x, y + 3, BONE[4]); put(g, x, y + 4, BONE[3])


def veins(trunk, vein, roots, hx, hy):
    """The ritual: cracks of light that creep in along the roots, meet in the hollow and climb the wood. Dim in the lit art, bright on their own layer."""
    r = random.Random(23)

    def crack(x, y, green):
        if 0 <= int(y) < H and 0 <= int(x) < W and KIND[int(y), int(x)] >= 0:
            light_px(trunk, vein, x, y, hexc("2e5a2c") if green else hexc("3a1e66"), HEX if green else hexc("b46aff"), 1 if green else 0)

    for pts in roots:
        drift = 0.0
        n = len(pts)
        for i in range(n - 4, 2, -1):
            x, y, w, ang = pts[i]
            drift = clamp(drift + r.choice((-1, 0, 0, 0, 0, 1)) * 0.5, -w * 0.4, w * 0.4)
            drift = clamp(drift, -1.5, 1.5)
            if i % 9 != 4:
                crack(x, y - w * 0.3 + round(drift), i % 11 == 0)
        x, y = pts[3][0], pts[3][1]
        steps = int(math.hypot(hx - x, hy + 12 - y))
        for k in range(steps):                                                          # across the foot into the hollow
            t = k / max(steps, 1)
            crack(x + (hx - x) * t + math.sin(k * 0.3) * 1.0, y + (hy + 12 - y) * t - 5.0 * math.sin(t * math.pi), k % 11 == 3)
    for off0, length, green_every in ((-0.3, 108, 11), (0.3, 92, 9), (0.02, 60, 13)):   # up the trunk, following its twist
        off = off0; y = hy - 16
        for k in range(length):
            yy = y - k
            if yy not in TRUNK:
                break
            cx, hw = TRUNK[yy]
            off = clamp(off + r.choice((-1, 0, 0, 0, 1)) * 0.03 + 0.006 * math.sin(k * 0.13 + off0 * 9), -0.82, 0.82)
            if k % 14 != 9:
                crack(cx + off * hw, yy, k % green_every == 2)
            if k % 23 == 11:
                side = r.choice((-1, 1))
                for j in range(1, r.randrange(4, 9)):
                    crack(cx + off * hw + side * j, yy - j * 0.6, j % 3 == 0)


def pad_layer(roots):
    """Bare, trodden earth under the tree, dark between the roots, with gall blisters and the feathers of birds that did not get away."""
    r = random.Random(3)
    out = layer()
    for y in range(312, 358):
        for x in range(10, 310):
            d = math.hypot((x - 160) / 142.0, (y - 337) / 20.0)
            n = noise(x, y, 5) / 255.0
            if d < 1.0 - n * 0.18 or (d < 1.0 and (x + y) % 2 == 0 and n > 0.35):
                out[y, x] = hexc("0e121c" if d > 0.84 else "121924" if d > 0.6 or n > 0.8 else "17212a")
    for pts in roots:                                                                   # the shade under each arching root
        for x, y, w, ang in pts[4:-3]:
            for k in range(1, 4):
                yy, xx = int(y + w + k), int(x + 2)
                if 0 <= yy < H and 0 <= xx < W and out[yy, xx, 3] and (xx + yy) % 2 == 0:
                    out[yy, xx] = hexc("090b14")
    for _ in range(70):                                                                 # stubble
        x, y = r.randint(24, 296), r.randint(322, 354)
        if out[y, x, 3]:
            for k in range(r.randint(2, 5)):
                put(out, x + k, y, hexc(r.choice(['20302c', '1b2824', '2a3c34'])))
            put(out, x, y - 1, hexc('2a3c34'))
    for _ in range(11):                                                                 # gall blisters
        x, y = r.randint(40, 280), r.randint(326, 352)
        if out[y, x, 3] and abs(x - 160) > 36:
            for dx, dy, c in ((0, 0, '2a3a1e'), (1, 0, '2a3a1e'), (2, 0, '1c2814'), (0, -1, '5c7a34'), (1, -1, '42602a'), (0, 1, '141c10'), (1, 1, '141c10'), (2, 1, '141c10')):
                put(out, x + dx, y + dy, hexc(c))
            put(out, x, y - 1, hexc('9ab85a'))
    for _ in range(16):                                                                 # feathers: a dark vane with a pale shaft
        x, y = r.randint(30, 290), r.randint(324, 353)
        if out[y, x, 3] and abs(x - 160) > 28:
            dx = r.choice([-1, 1])
            for j in range(8):
                put(out, x + dx * j, y - j // 3, hexc('07050c'))
                if 1 <= j <= 6:
                    put(out, x + dx * j, y - j // 3 - 1, hexc('1c1630' if j % 2 else '100c1e'))
                    put(out, x + dx * j, y - j // 3 + 1, hexc('0c0a16'))
            put(out, x + dx * 8, y - 2, hexc('5a5670')); put(out, x + dx * 3, y - 1, hexc('3a3458'))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    trunk, crown, moss, charm_l, glow, vein = layer(), layer(), layer(), layer(), layer(), layer()
    # ---- the skeleton: boughs behind the trunk first (deep z), the trunk, the boughs in front, the roots
    tp = trunk_path()
    back = [(-8, 214, math.radians(214), 70, 9.0, 3, math.radians(188)), (9, 208, math.radians(-36), 72, 9.2, 3, math.radians(-10)),
            (-3, 200, math.radians(240), 64, 8.6, 3, None), (5, 200, math.radians(-56), 64, 8.6, 3, None), (0, 198, math.radians(-98), 66, 8.0, 3, None)]
    for dx, y, ang, length, width, depth, level in back:
        side_limbs(TRUNK[y][0] + dx, y, ang, length, width, depth, -24.0 + rng.uniform(-3, 3), level)
    lay(tp, 0, 0.0)
    front = [(-12, 246, math.radians(206), 62, 7.4, 3, math.radians(172)), (13, 236, math.radians(-28), 66, 7.6, 3, math.radians(10)),
             (-6, 206, math.radians(-122), 52, 6.4, 3, None), (8, 204, math.radians(-72), 50, 6.2, 3, None)]
    for dx, y, ang, length, width, depth, level in front:
        side_limbs(TRUNK[y][0] + dx, y, ang, length, width, depth, 22.0 + rng.uniform(-2, 2), level)
    roots = []
    for side, reach, lift, w0, fr in ((-1, 104, 9, 9.0, 4), (1, 112, 10, 9.4, 3), (-1, 74, 6, 7.4, 12), (1, 82, 7, 7.8, 11), (-1, 50, 4, 6.2, 17), (1, 56, 4, 6.6, 16),
                                      (-1, 88, 5, 6.0, -3), (1, 78, 5, 6.2, -4), (1, 30, 2, 5.0, 19), (-1, 26, 2, 4.6, 20)):
        roots.append(root(side, reach, lift, w0, fr, 12 + rng.uniform(-2, 4)))
    print('raven tree: %d limbs, %d tips, %d seat candidates' % (len(pieces), len(tips), len(seats)), flush=True)
    # ---- leaves behind the wood (dark), then the wood, then everything that sits on it
    r = random.Random(99)
    cand = [t for t in tips if t[1] < 214 and t[2] <= 1 and 26 < t[0] < W - 26 and t[1] > 30]
    r.shuffle(cand)
    high = []
    for t in cand:                                                                      # far enough apart that the dead wood shows between them
        if all(math.hypot(t[0] - q[0], (t[1] - q[1]) * 1.3) > 30 for q in high):
            high.append(t)
    print('crown masses:', len(high), flush=True)
    behind = layer()
    lobes_shade(behind, masses_for(high[: int(len(high) * 0.4)], 1.1, r), 61, -0.42)
    leaf_pass(behind, 61, False)
    wood = layer()
    shade_wood(wood)
    trunk_details(wood, glow)
    ropes(wood)
    hx, hy = hollow(wood, glow)
    veins(wood, vein, [roots[0], roots[1], roots[3]], hx, hy)
    outline(wood)
    cobwebs(wood)
    trunk[...] = behind
    outline(trunk, hexc("070a14"))
    solid = wood[..., 3] > 0
    trunk[solid] = wood[solid]
    # ---- the bright cushions in front, with holes: only some of the tips carry one
    lobes_shade(crown, masses_for(high[int(len(high) * 0.4):], 1.0, r), 62, -0.3)
    leaf_pass(crown, 62, True)
    witch_hair(moss, crown)
    dark = {c[:3] for c in LEAF[:3]}
    for _ in range(40):                                                                 # eyes of light deep in the leaves
        x, y = r.randrange(20, 300), r.randrange(30, 200)
        if crown[y, x, 3] and tuple(int(v) for v in crown[y, x, :3]) in dark:
            light_px(crown, glow, x, y, HEX_DIM, HEX, 1)
    outline(crown)
    charms(charm_l, glow)
    outline(charm_l)
    layers = {'pad': pad_layer(roots), 'trunk': trunk, 'crown': crown, 'moss': moss, 'charms': charm_l, 'glow': glow, 'veins': vein}
    for name, arr in layers.items():
        Image.fromarray(arr).save(OUT / (name + '.png'))
    # ---- sixteen seats on the level boughs, spread out, none buried in the front leaves
    pool = [s for s in seats if 12 < s[0] < W - 12 and 14 < s[1] < 262 and not crown[int(s[1]) - 3, int(s[0]), 3]]
    picked = []
    pool.sort(key=lambda s: -s[2])
    while pool and len(picked) < 16:
        i = max(range(len(pool)), key=lambda k: min([math.hypot(pool[k][0] - p[0], pool[k][1] - p[1]) for p in picked] or [999.0]) + pool[k][2] * 4)
        best = pool.pop(i)
        if all(math.hypot(best[0] - p[0], best[1] - p[1]) > 13 for p in picked):
            picked.append(best)
    meta = {'frame': [W, H], 'feet': [FX, FY], 'layers': ['pad', 'trunk', 'crown', 'moss', 'charms', 'glow', 'veins'],
            'collision': {'shape': 'ellipse', 'center': [160, 328], 'radii': [30, 12]}, 'perches': [[int(round(s[0])), int(round(s[1]))] for s in picked],
            'hollow': [int(hx), int(hy)], 'perch_coordinates': 'frame pixels, feet at y=340; offsets = perch - feet'}
    (OUT / 'crow_tree.json').write_text(json.dumps(meta, indent=2) + '\n', encoding='utf8')
    # ---- the contact sheet: day, night, the witch hour, freed
    sheet = Image.new('RGBA', (W * 4, H), '#1b2c2d')
    for k, (ground, dim, mode) in enumerate((('#1b2c2d', 1.0, 'day'), ('#0a0f18', .46, 'night'), ('#06080e', .34, 'hour'), ('#22302a', 1.0, 'free'))):
        bg = Image.new('RGBA', (W, H), ground)
        for name in ('pad', 'trunk', 'crown', 'moss', 'charms'):
            q = layers[name].astype(float)
            q[..., :3] *= dim
            if mode == 'free' and name in ('crown', 'moss'):
                q[..., 0] *= 1.3; q[..., 1] *= 1.28
            bg.alpha_composite(Image.fromarray(np.clip(q, 0, 255).astype(np.uint8)))
        if mode != 'day':
            bg.alpha_composite(Image.fromarray(glow))
        if mode != 'free':
            q = vein.astype(float)
            if mode == 'hour':
                q[..., :3] = np.where(q[..., 3:4] > 0, np.array([168, 255, 106.0]), 0)
            if mode == 'day':
                q[..., 3] *= 0.5
            bg.alpha_composite(Image.fromarray(np.clip(q, 0, 255).astype(np.uint8)))
        sheet.alpha_composite(bg, (k * W, 0))
    sheet.convert('RGB').save(ROOT.parent / 'docs' / 'img' / 'crow_tree.png')
    if len(sys.argv) > 1:
        sheet.convert('RGB').save(sys.argv[1])
    print('raven tree written: 7 layers, %d seats' % len(picked), flush=True)


if __name__ == '__main__':
    main()
