#!/usr/bin/env python3
"""Pixel-art generator for Shadowspore Dungeon #1: Die Gezeitenkammern von Sturmhafen.
Follows docs/design_guide.md & shadowspore-pixel-art skill:
- Never pure #000000 (dark tinted slate/violet ink #110d1e / #141726)
- Top-left directional lighting, cool-violet ambient shadows
- 1px crisp silhouette outlines, unlit *_glow.png companion sheets
- Bottom-center pivots for world props, 16x16 icons for items, 392x74 banner for DungeonWindow
"""
from __future__ import annotations

import math
import pathlib
import sys
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1] / "assets"


def hex_rgba(s: str, a: int = 255) -> tuple[int, int, int, int]:
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def lerp_c(c1, c2, t: float):
    t = max(0.0, min(1.0, t))
    return (
        int(round(c1[0] + (c2[0] - c1[0]) * t)),
        int(round(c1[1] + (c2[1] - c1[1]) * t)),
        int(round(c1[2] + (c2[2] - c1[2]) * t)),
        int(round(c1[3] + (c2[3] - c1[3]) * t)),
    )


def save_img(rel: str, img: Image.Image) -> None:
    out = ROOT / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"[art_dungeon_sturmhafen] wrote {rel} ({img.width}x{img.height})")


# Curated Sturmhafen coastal slate, bronze, timber, turquoise rune & amber palettes (ZERO #000000)
INK = hex_rgba("120e20")
INK_DARK = hex_rgba("141726")
SLATE = [hex_rgba("1b2234"), hex_rgba("28344a"), hex_rgba("3b4c66"), hex_rgba("586f8c"), hex_rgba("829db8")]
MOSS = [hex_rgba("1d3a36"), hex_rgba("2c5c50"), hex_rgba("4a886e"), hex_rgba("78b890")]
BRONZE = [hex_rgba("38291e"), hex_rgba("5e452c"), hex_rgba("8f6e40"), hex_rgba("c9a25e"), hex_rgba("f0d492")]
VERDIGRIS = [hex_rgba("1d4548"), hex_rgba("2c6f70"), hex_rgba("4aa09a"), hex_rgba("7ed2c4")]
TIMBER = [hex_rgba("281a24"), hex_rgba("452d30"), hex_rgba("694842"), hex_rgba("946c5a"), hex_rgba("bd957a")]
IRON = [hex_rgba("1d2030"), hex_rgba("32394f"), hex_rgba("515b75"), hex_rgba("7e8ba6")]
TURQ = [hex_rgba("185868"), hex_rgba("28a2ad"), hex_rgba("4df2e0"), hex_rgba("c4fff8")]
AMBER = [hex_rgba("8a3c1c"), hex_rgba("d46e26"), hex_rgba("ffae3d"), hex_rgba("ffe898")]
PORTAL = [hex_rgba("0c1324"), hex_rgba("142742"), hex_rgba("1e516b"), hex_rgba("38a6b0")]
VOID_MIST = hex_rgba("100c1e")


def hash2(x: int, y: int, seed: int = 13) -> float:
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def add_outline(im: Image.Image, color=INK) -> Image.Image:
    w, h = im.size
    src = im.load()
    out = im.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] >= 180:
                    dst[x, y] = color
                    break
    return out


def shade_stone_block(px, x0: int, y0: int, x1: int, y1: int, seed: int = 1, moss_top: bool = True) -> None:
    w = max(1, x1 - x0)
    h = max(1, y1 - y0)
    for y in range(y0, y1):
        for x in range(x0, x1):
            u = (x - x0) / w
            v = (y - y0) / h
            # Top-left directional bevel
            lit = (1.0 - u) * 0.5 + (1.0 - v) * 0.5
            n = (hash2(x, y, seed) - 0.5) * 0.22
            val = lit + n
            if y == y0 or x == x0:
                idx = 3 if (x + y) % 3 else 4
            elif y == y1 - 1 or x == x1 - 1:
                idx = 0
            elif val > 0.68:
                idx = 3
            elif val > 0.42:
                idx = 2
            elif val > 0.22:
                idx = 1
            else:
                idx = 0
            c = SLATE[idx]
            if moss_top and y - y0 <= 2 and hash2(x, y, seed + 77) > 0.55:
                c = MOSS[2 if y == y0 else 1]
            px[x, y] = c


def draw_rect_px(px, w: int, h: int, x0: int, y0: int, x1: int, y1: int, c) -> None:
    for y in range(max(0, y0), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            px[x, y] = c


def build_sturmhafen_gate() -> None:
    W, H = 112, 88
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    gpx = glow.load()

    # Ground shadow ellipse at feet
    cx, cy = W // 2, H - 7
    for y in range(H - 14, H - 1):
        for x in range(8, W - 8):
            d = math.hypot((x - cx) / 46.0, (y - cy) / 5.5)
            if d <= 1.0:
                px[x, y] = (18, 14, 34, int(110 * (1.0 - d * 0.5)))

    # Deep recessed ocean-abyss portal behind arch (x: 32..80, y: 28..79)
    for y in range(28, 80):
        for x in range(32, 80):
            dx = (x - 56) / 24.0
            dy = (y - 54) / 26.0
            # Arch top spandrels filled with carved dark basalt arch stones
            if y < 44 and math.hypot(dx, (y - 44) / 16.0) > 1.0:
                sp_lit = 1 if (x + y) % 5 == 0 else 0
                px[x, y] = SLATE[1 + sp_lit]
                continue
            r = math.hypot(dx * 0.85, dy)
            wave = math.sin(x * 0.28 + y * 0.22) * 0.14
            t = max(0.0, min(1.0, 1.0 - r * 0.85 + wave))
            c = lerp_c(PORTAL[0], PORTAL[3], t * 0.65)
            px[x, y] = c
            if t > 0.52 and (x + y) % 2 == 0:
                gpx[x, y] = (77, 242, 224, int(130 * (t - 0.45)))

    # Iron portcullis teeth hanging from top of arch
    for tx in range(38, 76, 6):
        tooth_len = 8 if (tx // 6) % 2 == 0 else 11
        for y in range(29, 29 + tooth_len):
            px[tx, y] = IRON[2]
            px[tx + 1, y] = IRON[0]

    # Left & Right monumental basalt pillars (blocks stacked with mortar lines)
    for px0 in (12, 78):
        # Footing plinth
        shade_stone_block(px, px0 - 3, 70, px0 + 25, 81, seed=px0 + 1, moss_top=False)
        # Pillar courses
        for row, y0 in enumerate((56, 42, 28)):
            shade_stone_block(px, px0, y0, px0 + 22, y0 + 13, seed=px0 + row * 11, moss_top=(row == 2))
            # Mortar crack
            draw_rect_px(px, W, H, px0, y0 + 13, px0 + 22, y0 + 14, INK_DARK)
        # Carved vertical turquoise conduit down pillar center
        rcx = px0 + 10
        for y in range(32, 69):
            if y % 6 != 0:
                px[rcx, y] = TURQ[1]
                px[rcx + 1, y] = TURQ[2]
                gpx[rcx, y] = (77, 242, 224, 175)
                gpx[rcx + 1, y] = (196, 255, 248, 210)
        # Encrusted sea-barnacles near base
        for bx, by in ((px0 + 2, 74), (px0 + 17, 72), (px0 + 5, 65)):
            draw_rect_px(px, W, H, bx, by, bx + 4, by + 3, VERDIGRIS[2])
            px[bx + 1, by + 1] = TURQ[2]

    # Monumental carved Steinsetzer lintel + stepped pediment crown
    shade_stone_block(px, 8, 12, W - 8, 28, seed=99, moss_top=True)
    shade_stone_block(px, 18, 5, W - 18, 12, seed=107, moss_top=True)
    # Central keystone crest
    shade_stone_block(px, 49, 2, 63, 14, seed=113, moss_top=False)

    # 4 Glowing Resonance Seal Runes inset into lintel!
    rune_xs = (26, 44, 62, 80)
    for rx in rune_xs:
        draw_rect_px(px, W, H, rx - 1, 16, rx + 7, 24, INK_DARK)
        # Diamond glyph inside stone socket
        for dy in range(6):
            for dx in range(6):
                dist = abs(dx - 2.5) + abs(dy - 2.5)
                if dist <= 2.6:
                    c = TURQ[3] if dist <= 1.2 else TURQ[2]
                    px[rx + dx, 17 + dy] = c
                    gpx[rx + dx, 17 + dy] = (c[0], c[1], c[2], 245)

    # Flanking bronze harbor braziers perched on top corners
    for bx in (15, W - 21):
        draw_rect_px(px, W, H, bx, 6, bx + 6, 12, BRONZE[2])
        draw_rect_px(px, W, H, bx + 1, 3, bx + 5, 7, AMBER[2])
        px[bx + 2, 2] = AMBER[3]
        px[bx + 3, 2] = AMBER[3]
        for yy in range(1, 8):
            for xx in range(bx - 1, bx + 7):
                d = math.hypot(xx - (bx + 2.5), yy - 4.5)
                if d <= 3.5:
                    gpx[xx, yy] = (255, 198, 92, int(230 * (1.0 - d / 3.8)))

    im = add_outline(im, INK)
    save_img("props/sturmhafen_gate.png", im)
    save_img("props/sturmhafen_gate_glow.png", glow)


def build_dungeon_banner() -> None:
    """392x74 lush pixel-art diorama banner for Steinsetzer-Prüfungstafel."""
    W, H = 392, 74
    im = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    px = im.load()

    # 1. Deep vaulted sea-cavern gradient sky/ceiling
    for y in range(H):
        t = y / max(1, H - 1)
        base = lerp_c(hex_rgba("0c1222"), hex_rgba("15283d"), t)
        for x in range(W):
            n = (hash2(x // 2, y // 2, 41) - 0.5) * 0.08
            px[x, y] = lerp_c(base, hex_rgba("1e3c54"), max(0.0, min(1.0, t * 0.6 + n)))

    # 2. Distant vaulted Steinsetzer aqueduct arches in background
    for arch_cx in range(36, W, 72):
        for y in range(4, 52):
            for x in range(max(0, arch_cx - 36), min(W, arch_cx + 36)):
                dx = (x - arch_cx) / 24.0
                in_hole = (y >= 24 and abs(x - arch_cx) < 22) or (y >= 10 and math.hypot(dx, (y - 24) / 14.0) < 0.92)
                if not in_hole:
                    dist_edge = abs(x - arch_cx)
                    c = SLATE[1] if dist_edge > 24 else SLATE[2]
                    if (x + y) % 11 == 0:
                        c = SLATE[0]
                    px[x, y] = c

    # 3. Moonlit storm-sea breach framed cleanly inside the center arch (arch_cx = 180)
    for y in range(12, 48):
        for x in range(158, 202):
            dx = (x - 180) / 21.0
            if (y >= 24 and abs(x - 180) < 20) or (y >= 12 and math.hypot(dx, (y - 24) / 12.0) < 0.90):
                t = 1.0 - min(1.0, abs(x - 180) / 22.0)
                c = lerp_c(hex_rgba("14364a"), hex_rgba("4ec8cf"), t * 0.78)
                if y < 22 and hash2(x, y, 61) > 0.88:
                    c = hex_rgba("c6fff8")
                px[x, y] = c

    # 4. Towering silhouette of Vorgath, Brut der Mole rising from the sluice water!
    vx, vy = 264, 42
    for y in range(12, 54):
        for x in range(vx - 34, vx + 36):
            # Massive hunched void carapace
            d_body = math.hypot((x - vx) / 24.0, (y - (vy - 8)) / 18.0)
            d_shld = math.hypot((x - (vx - 14)) / 14.0, (y - (vy - 14)) / 13.0)
            d_arm = math.hypot((x - (vx + 22)) / 12.0, (y - (vy - 4)) / 16.0)
            if min(d_body, d_shld, d_arm) <= 1.0:
                c = hex_rgba("090614") if min(d_body, d_shld, d_arm) < 0.85 else hex_rgba("1d1436")
                px[x, y] = c
    # Vorgath's 3 glowing magenta eyes + turquoise glowing barnacles + brass harbor lantern on back
    for ex, ey in ((vx - 10, vy - 12), (vx - 5, vy - 13), (vx - 7, vy - 9)):
        draw_rect_px(px, W, H, ex, ey, ex + 2, ey + 2, hex_rgba("ff4fd8"))
    for bx, by in ((vx + 2, vy - 16), (vx + 8, vy - 12), (vx - 16, vy - 6), (vx + 18, vy - 4)):
        draw_rect_px(px, W, H, bx, by, bx + 3, by + 2, TURQ[2])
    # Glowing amber harbor lantern dangling from Vorgath's back
    draw_rect_px(px, W, H, vx + 6, vy - 28, vx + 13, vy - 20, AMBER[2])
    draw_rect_px(px, W, H, vx + 8, vy - 26, vx + 11, vy - 22, AMBER[3])
    # Heavy anchor silhouette beside Vorgath
    draw_rect_px(px, W, H, vx + 26, vy - 14, vx + 30, vy + 10, IRON[1])
    draw_rect_px(px, W, H, vx + 20, vy + 4, vx + 36, vy + 8, IRON[2])

    # 5. Foreground weathered wooden dock beams & broken ship ribs on left (x: 0..138)
    for rib_x in (24, 52, 82, 110):
        for k in range(36):
            rx = int(rib_x + math.sin(k * 0.08) * 8)
            ry = 52 - k
            if 0 <= rx < W and 0 <= ry < H:
                draw_rect_px(px, W, H, rx, ry, rx + 4, ry + 2, TIMBER[2] if k % 3 else TIMBER[3])
                px[rx, ry] = TIMBER[0]

    # 6. Three Steinsetzer wave-bollards jutting out of the flooded basin
    for bx in (138, 194, 336):
        shade_stone_block(px, bx - 7, 36, bx + 7, 56, seed=bx, moss_top=False)
        draw_rect_px(px, W, H, bx - 4, 39, bx + 4, 41, TURQ[2])

    # 7. Shimmering horizontal tidal water across bottom (y: 48..74) with crisp pixel ripples & reflections
    for y in range(48, H):
        wt = (y - 48) / float(H - 48)
        row_phase = hash2(0, y, 91) * 6.28
        for x in range(W):
            rip = math.sin(x * 0.15 + row_phase) * 0.5 + 0.5
            c = lerp_c(hex_rgba("123247"), hex_rgba("091729"), wt)
            if y == 48 and (x // 2) % 3 != 0:
                c = lerp_c(c, TURQ[2], 0.55)
            elif (y % 3 == 0) and rip > 0.74:
                c = lerp_c(c, TURQ[2], 0.42 * (1.0 - wt * 0.5))
            # Moonbeam & lantern horizontal reflection bands in water
            if abs(x - 180) < 20 - int(wt * 6) and (y % 2 == 0) and rip > 0.35:
                c = lerp_c(c, TURQ[2], 0.48)
            if abs(x - (vx + 9)) < 11 and (y % 2 == 1) and rip > 0.42:
                c = lerp_c(c, AMBER[2], 0.52)
            px[x, y] = c

    # 8. Crisp hanging brass lantern on left foreground + subtle vignette
    draw_rect_px(px, W, H, 42, 0, 44, 18, IRON[1])
    draw_rect_px(px, W, H, 39, 18, 47, 28, BRONZE[2])
    draw_rect_px(px, W, H, 41, 20, 45, 26, AMBER[3])
    for y in range(H):
        for x in range(W):
            dl = math.hypot(x - 43, y - 23)
            if dl < 22.0:
                px[x, y] = lerp_c(px[x, y], AMBER[2], (1.0 - dl / 22.0) * 0.28)
            edge = min(x / 18.0, (W - 1 - x) / 18.0, y / 10.0, (H - 1 - y) / 10.0, 1.0)
            if edge < 1.0:
                px[x, y] = lerp_c(INK, px[x, y], 0.45 + 0.55 * edge)

    save_img("ui/dungeon_banner_sturmhafen.png", im)


def build_bollard() -> None:
    W, H = 32, 40
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px, gpx = im.load(), glow.load()
    # Ground shadow
    for y in range(32, 39):
        for x in range(4, 28):
            if math.hypot((x - 16) / 11.0, (y - 35) / 3.5) <= 1.0:
                px[x, y] = (16, 12, 30, 120)
    # Massive stepped bollard shaft
    shade_stone_block(px, 6, 26, 26, 36, seed=31, moss_top=False)
    shade_stone_block(px, 8, 10, 24, 27, seed=33, moss_top=False)
    shade_stone_block(px, 6, 5, 26, 11, seed=37, moss_top=True)
    # Carved glowing turquoise storm-breaker chevron rune on front
    for dx, dy in ((0, 0), (-1, 1), (1, 1), (-2, 2), (2, 2), (0, 3), (0, 4), (0, 5)):
        px[16 + dx, 15 + dy] = TURQ[2]
        gpx[16 + dx, 15 + dy] = (77, 242, 224, 235)
    # Iron mooring ring
    for ang in range(0, 360, 25):
        rx = int(round(16 + math.cos(math.radians(ang)) * 3.2))
        ry = int(round(29 + math.sin(math.radians(ang)) * 2.4))
        px[rx, ry] = IRON[2]
    im = add_outline(im, INK)
    save_img("dungeons/sturmhafen/bollard.png", im)
    save_img("dungeons/sturmhafen/bollard_glow.png", glow)


def build_tide_bell() -> None:
    W, H = 48, 56
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px, gpx = im.load(), glow.load()
    # Slate belfry posts & crossbeam
    shade_stone_block(px, 6, 12, 13, 51, seed=51, moss_top=True)
    shade_stone_block(px, 35, 12, 42, 51, seed=53, moss_top=True)
    shade_stone_block(px, 4, 6, 44, 14, seed=57, moss_top=True)
    # Verdigris bronze dome bell hanging from center
    for y in range(16, 40):
        t = (y - 16) / 24.0
        half_w = int(round(4 + 9 * (t ** 1.35)))
        for x in range(24 - half_w, 24 + half_w + 1):
            u = (x - (24 - half_w)) / max(1, half_w * 2)
            idx = 3 if u < 0.28 else (2 if u < 0.62 else (1 if u < 0.85 else 0))
            c = VERDIGRIS[idx] if (x + y) % 5 == 0 else BRONZE[min(4, idx + 1)]
            px[x, y] = c
    # Glowing turquoise resonance band & clapper
    draw_rect_px(px, W, H, 15, 34, 33, 36, TURQ[2])
    draw_rect_px(gpx, W, H, 15, 34, 33, 36, (77, 242, 224, 220))
    draw_rect_px(px, W, H, 22, 39, 26, 44, TURQ[3])
    draw_rect_px(gpx, W, H, 22, 39, 26, 44, (196, 255, 248, 250))
    im = add_outline(im, INK)
    save_img("dungeons/sturmhafen/tide_bell.png", im)
    save_img("dungeons/sturmhafen/tide_bell_glow.png", glow)


def build_weight_stone() -> None:
    W, H = 24, 24
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px, gpx = im.load(), glow.load()
    for y in range(3, 21):
        for x in range(3, 21):
            if abs(x - 11.5) + abs(y - 11.5) <= 12.2:
                lit = (1.0 - (x - 3) / 18.0) * 0.5 + (1.0 - (y - 3) / 18.0) * 0.5
                px[x, y] = SLATE[3 if lit > 0.65 else (2 if lit > 0.38 else 1)]
    # Glowing turquoise resonance diamond core
    for y in range(8, 16):
        for x in range(8, 16):
            d = abs(x - 11.5) + abs(y - 11.5)
            if d <= 3.2:
                c = TURQ[3] if d <= 1.4 else TURQ[2]
                px[x, y] = c
                gpx[x, y] = (c[0], c[1], c[2], 245)
    im = add_outline(im, INK)
    save_img("dungeons/sturmhafen/weight_stone.png", im)
    save_img("dungeons/sturmhafen/weight_stone_glow.png", glow)


def build_winch() -> None:
    W, H = 48, 48
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px, gpx = im.load(), glow.load()
    # Basalt pedestal & counterweight socket
    shade_stone_block(px, 6, 26, 42, 43, seed=71, moss_top=False)
    shade_stone_block(px, 10, 10, 17, 30, seed=73, moss_top=False)
    shade_stone_block(px, 31, 10, 38, 30, seed=75, moss_top=False)
    # Bronze chain drum + handwheel
    draw_rect_px(px, W, H, 16, 13, 32, 23, BRONZE[2])
    draw_rect_px(px, W, H, 16, 13, 32, 16, BRONZE[3])
    for cx in range(18, 31, 3):
        draw_rect_px(px, W, H, cx, 13, cx + 1, 23, IRON[1])
    # Glowing socket indicator on front pedestal
    draw_rect_px(px, W, H, 19, 31, 29, 39, INK_DARK)
    draw_rect_px(px, W, H, 21, 33, 27, 37, TURQ[2])
    draw_rect_px(gpx, W, H, 21, 33, 27, 37, (77, 242, 224, 230))
    im = add_outline(im, INK)
    save_img("dungeons/sturmhafen/winch.png", im)
    save_img("dungeons/sturmhafen/winch_glow.png", glow)


def build_brazier() -> None:
    W, H = 32, 36
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px, gpx = im.load(), glow.load()
    shade_stone_block(px, 8, 22, 24, 33, seed=81, moss_top=False)
    draw_rect_px(px, W, H, 6, 16, 26, 23, BRONZE[2])
    draw_rect_px(px, W, H, 6, 16, 26, 18, BRONZE[3])
    # Warm flame cluster
    for y in range(6, 17):
        for x in range(10, 22):
            d = math.hypot((x - 16) / 5.5, (y - 13) / 6.0)
            if d <= 1.0:
                c = AMBER[3] if d < 0.4 else (AMBER[2] if d < 0.72 else AMBER[1])
                px[x, y] = c
                gpx[x, y] = (c[0], c[1], c[2], 240)
    im = add_outline(im, INK)
    save_img("dungeons/sturmhafen/brazier.png", im)
    save_img("dungeons/sturmhafen/brazier_glow.png", glow)


def build_planks() -> None:
    W, H = 48, 36
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    for y0 in (6, 15, 24):
        for y in range(y0, y0 + 7):
            for x in range(4, 44):
                grain = 1 if (x + y * 3) % 7 == 0 else 0
                c = TIMBER[3] if y == y0 else (TIMBER[1] if y == y0 + 6 else TIMBER[2 - grain])
                px[x, y] = c
    # Diagonal brace & iron nails
    for k in range(28):
        bx = 10 + k
        by = 6 + int(k * 0.8)
        draw_rect_px(px, W, H, bx, by, bx + 4, by + 3, TIMBER[1])
    for nx, ny in ((8, 9), (38, 9), (8, 18), (38, 18), (8, 27), (38, 27)):
        px[nx, ny] = IRON[3]
    im = add_outline(im, INK)
    save_img("dungeons/sturmhafen/planks.png", im)


def build_item_icons() -> None:
    # 1. anchor_pendant.png (16x16)
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = im.load()
    # Gold chain loop at top
    for x, y in ((6, 2), (7, 1), (8, 1), (9, 2), (6, 3), (9, 3)):
        px[x, y] = BRONZE[3]
    # Anchor shaft + crossbar
    draw_rect_px(px, 16, 16, 7, 4, 9, 13, IRON[2])
    draw_rect_px(px, 16, 16, 5, 6, 11, 8, BRONZE[3])
    # Anchor curved flukes
    for x, y in ((3, 10), (4, 11), (5, 12), (6, 13), (7, 13), (8, 13), (9, 13), (10, 12), (11, 11), (12, 10)):
        px[x, y] = IRON[3] if x < 8 else IRON[1]
    # Glowing turquoise Steinsetzer gem at heart
    px[7, 6] = TURQ[3]
    px[8, 7] = TURQ[2]
    im = add_outline(im, INK)
    save_img("items/anchor_pendant.png", im)

    # 2. tide_bracelet.png (16x16)
    im2 = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px2 = im2.load()
    for y in range(2, 14):
        for x in range(2, 14):
            d = math.hypot((x - 7.5) / 5.2, (y - 7.8) / 4.8)
            if 0.62 <= d <= 1.05:
                top_left = (x < 8 and y < 8)
                if (x + y) % 3 == 0:
                    px2[x, y] = TURQ[3 if top_left else 2]
                else:
                    px2[x, y] = BRONZE[4 if top_left else (3 if y < 9 else 2)]
    # Center sea-quartz clasp on top rim
    draw_rect_px(px2, 16, 16, 6, 2, 10, 5, TURQ[2])
    px2[7, 3] = TURQ[3]
    im2 = add_outline(im2, INK)
    save_img("items/tide_bracelet.png", im2)


def main() -> None:
    build_sturmhafen_gate()
    build_dungeon_banner()
    build_bollard()
    build_tide_bell()
    build_weight_stone()
    build_winch()
    build_brazier()
    build_planks()
    build_item_icons()


if __name__ == "__main__":
    main()
