#!/usr/bin/env python3
"""Procedural pixel-art generator for Caelia's Veil Thread collectibles in WINDKAP.

Outputs:
  assets/props/veil_thread.png       144x64 (6 cols x 2 rows of 24x32), pivot (12, 28)
  assets/props/veil_thread_glow.png  144x64 unlit emissive glow mask
  docs/img/veil_thread_atlas_4x.png  768x496 (4x nearest) Day / Night / Pickup & Glow-only QA sheet

Note: Does NOT generate a data/veil_thread_art.json file (excluded by M2 file ownership).
Runtime constants for M6 (`src/systems/veil_threads.gd`):
  FRAME_W = 24, FRAME_H = 32, COLS = 6, ROWS = 2, GROUND_ROW = 28, PIVOT = (12, 28)
  Row 0 (0..5): Seamless 6-frame idle double-helix float & pulse
  Row 1 (6..9): Pickup absorption/untwist keyframes; (10..11): Spent anchor shimmer
"""
from __future__ import annotations

from collections import deque
from collections.abc import Callable
import math
import pathlib
import sys

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402
from art_ancient_stones import blend_over, make_grid  # noqa: E402

# ---------------------------------------------------------------------------
# Exported Constants (for M6 runtime reference)
# ---------------------------------------------------------------------------
FRAME_W = 24
FRAME_H = 32
COLS = 6
ROWS = 2
SHEET_W = FRAME_W * COLS
SHEET_H = FRAME_H * ROWS
GROUND_ROW = 28
PIVOT = (12, 28)

# ---------------------------------------------------------------------------
# Palettes (Zero #000000)
# ---------------------------------------------------------------------------
INK = hexc("1b1a2e")
SHADOW_RGB = (16, 16, 34)

VIO_EDGE = hexc("21123b")
VIO_DARK = hexc("34185e")
VIO_MID = hexc("6636ad")
VIO_LIT = hexc("9468ee")
VIO_HI = hexc("cbaaff")

TEAL_EDGE = hexc("143640")
TEAL_DARK = hexc("2a8c94")
TEAL_MID = hexc("3cc0c6")
TEAL_LIT = hexc("78f4e6")
TEAL_CORE = hexc("d0fff8")

GOLD_MID = hexc("b48a38")
GOLD_HI = hexc("e6c468")


def verify_no_black(name: str, px: list[list[tuple[int, int, int, int]]]) -> None:
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} contains forbidden #000000 pixel at ({x}, {y})")


def verify_no_orphan_idle_pixels(
    idle_frames: list[tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]],
) -> None:
    """Assert zero non-glowing 4-connected orphan pixels (size <= 2) in Row 0 idle frames."""
    for f_idx, (base, gl) in enumerate(idle_frames):
        visited: set[tuple[int, int]] = set()
        for sy in range(FRAME_H):
            for sx in range(FRAME_W):
                if base[sy][sx][3] < 200 or (sx, sy) in visited:
                    continue
                comp: list[tuple[int, int]] = []
                q: deque[tuple[int, int]] = deque([(sx, sy)])
                visited.add((sx, sy))
                while q:
                    cx, cy = q.popleft()
                    comp.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < FRAME_W and 0 <= ny < FRAME_H and (nx, ny) not in visited and base[ny][nx][3] >= 200:
                            visited.add((nx, ny))
                            q.append((nx, ny))
                if len(comp) <= 2 and all(gl[py][px_][3] < 200 for px_, py in comp):
                    raise AssertionError(f"Idle frame {f_idx} has non-glowing orphan component: {comp}")


def _contiguous_runs(
    pts: list[tuple[int, int, float]],
    pred: Callable[[tuple[int, int, float]], bool],
) -> list[list[tuple[int, int, float]]]:
    runs: list[list[tuple[int, int, float]]] = []
    cur: list[tuple[int, int, float]] = []
    for p in pts:
        if pred(p):
            if cur and p[1] != cur[-1][1] + 1:
                runs.append(cur)
                cur = [p]
            else:
                cur.append(p)
        else:
            if cur:
                runs.append(cur)
                cur = []
    if cur:
        runs.append(cur)
    return runs


class GlowMap:
    def __init__(self, w: int, h: int) -> None:
        self.w = w
        self.h = h
        self.px = make_grid(w, h)
        self.pts: list[tuple[int, int, tuple[int, int, int, int], int]] = []

    def emit(
        self,
        base: list[list[tuple[int, int, int, int]]] | None,
        x: int,
        y: int,
        dim_col: tuple[int, int, int, int] | None,
        bright_col: tuple[int, int, int, int],
        halo: int = 1,
    ) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            if dim_col is not None and base is not None:
                base[y][x] = dim_col
            self.px[y][x] = bright_col
            if halo > 0:
                self.pts.append((x, y, bright_col, halo))

    def finish(self) -> list[list[tuple[int, int, int, int]]]:
        out = [row[:] for row in self.px]
        for cx, cy, col, rad in self.pts:
            for dy in range(-rad - 1, rad + 2):
                for dx in range(-rad - 1, rad + 2):
                    if dx == 0 and dy == 0:
                        continue
                    xx, yy = cx + dx, cy + dy
                    if not (0 <= xx < self.w and 0 <= yy < self.h):
                        continue
                    d = math.hypot(dx, dy)
                    if d <= rad + 0.45 and out[yy][xx][3] < 255:
                        a = 96 if d <= 1.25 else 36
                        if a > out[yy][xx][3]:
                            out[yy][xx] = (col[0], col[1], col[2], a)
        return out


def _draw_shadow_ellipse(px: list[list[tuple[int, int, int, int]]], cx: float, cy: float, rx: float, ry: float, strong: bool = True) -> None:
    for y in range(FRAME_H):
        for x in range(FRAME_W):
            d = math.hypot((x - cx) / rx, (y - cy) / ry)
            if d <= 1.0:
                a = (68 if d < 0.55 else 42) if strong else (44 if d < 0.6 else 24)
                px[y][x] = blend_over((SHADOW_RGB[0], SHADOW_RGB[1], SHADOW_RGB[2], a), px[y][x])


def _draw_strand_segment(
    px: list[list[tuple[int, int, int, int]]],
    glow: GlowMap,
    pts: list[tuple[int, int, float]],
    palette: tuple[tuple[int, int, int, int], ...],
    glow_pal: tuple[tuple[int, int, int, int], ...],
) -> None:
    """Draws a strictly 4-connected filament strand with dark edge & NW->SE lit core."""
    edge_c, dark_c, mid_c, lit_c, hi_c = palette
    prev_x, prev_y = pts[0][0], pts[0][1]
    for idx, (x, y, depth) in enumerate(pts):
        # Maintain strict 4-connectivity across steps
        if x != prev_x and y != prev_y:
            if 1 <= prev_y < FRAME_H - 1 and 1 <= x < FRAME_W - 1:
                if px[prev_y][x][3] == 0:
                    px[prev_y][x] = dark_c
        if 1 <= y < FRAME_H - 1 and 1 <= x < FRAME_W - 1:
            # Core color from depth & NW bias
            if depth > 0.35:
                c = hi_c
                gc = glow_pal[1]
                halo = 1
            elif depth > -0.15:
                c = lit_c
                gc = glow_pal[0]
                halo = 1
            else:
                c = mid_c
                gc = None
                halo = 0
            px[y][x] = c
            if gc is not None:
                glow.emit(px, x, y, c, gc, halo=halo)
            # Subtle 1px dark tinted side shading on opposite side of light (SE)
            if x + 1 < FRAME_W - 1 and px[y][x + 1][3] == 0:
                px[y][x + 1] = edge_c if depth <= 0.1 else dark_c
            if x - 1 >= 1 and px[y][x - 1][3] == 0 and depth > 0.25:
                px[y][x - 1] = dark_c
        prev_x, prev_y = x, y


def _draw_idle_frame(frame: int) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    px = make_grid(FRAME_W, FRAME_H)
    glow = GlowMap(FRAME_W, FRAME_H)
    phase = frame * math.tau / COLS
    bob = int(round(math.sin(phase)))

    # Woven double helix (y=5..24)
    teal_pts: list[tuple[int, int, float]] = []
    vio_pts: list[tuple[int, int, float]] = []
    for y in range(5, 25):
        u = (y - 5) / 19.0
        amp = 3.2 * math.sin(u * math.pi) + 0.6
        ang = u * math.tau * 1.15 - phase
        tx = int(round(12.0 + math.sin(ang) * amp))
        tz = math.cos(ang)
        vx = int(round(12.0 + math.sin(ang + math.pi) * amp))
        vz = math.cos(ang + math.pi)
        teal_pts.append((tx, y, tz))
        vio_pts.append((vx, y, vz))

    # Draw full contiguous strands first, then re-draw contiguous front runs (vz >= 0) for clean front/back helix weaving
    vio_pal = (VIO_EDGE, VIO_DARK, VIO_MID, VIO_LIT, VIO_HI)
    vio_glow = (VIO_LIT, VIO_HI)
    teal_pal = (TEAL_EDGE, TEAL_DARK, TEAL_MID, TEAL_LIT, TEAL_CORE)
    teal_glow = (TEAL_LIT, TEAL_CORE)
    _draw_strand_segment(px, glow, vio_pts, vio_pal, vio_glow)
    _draw_strand_segment(px, glow, teal_pts, teal_pal, teal_glow)
    for front_run in _contiguous_runs(vio_pts, lambda p: p[2] >= 0.0):
        _draw_strand_segment(px, glow, front_run, vio_pal, vio_glow)

    # Central Ankerlicht Knot (y=13..16 + bob, 4x4 diamond clasp with 1px #1b1a2e outline)
    ky = 14 + bob
    clasp_outline = [
        (12, ky - 2), (11, ky - 1), (13, ky - 1),
        (10, ky), (14, ky),
        (11, ky + 1), (13, ky + 1), (12, ky + 2),
    ]
    for ox, oy in clasp_outline:
        px[oy][ox] = INK
    px[ky - 1][12] = GOLD_HI
    px[ky][11] = GOLD_HI
    px[ky][13] = GOLD_MID
    px[ky + 1][12] = GOLD_MID
    glow.emit(px, 12, ky, TEAL_CORE, TEAL_CORE, halo=2)

    # Upper & lower tapered wisps & drifting ground tether specks (2px clusters / tips)
    top_y = 3 + ((frame + 1) % 2)
    glow.emit(px, 12, top_y, TEAL_LIT, TEAL_CORE, halo=1)
    glow.emit(px, 12, top_y + 1, TEAL_MID, TEAL_LIT, halo=0)
    bot_x = 11 + (frame % 3)
    glow.emit(px, bot_x, 25, VIO_LIT, VIO_HI, halo=0)
    glow.emit(px, bot_x, 26, VIO_MID, VIO_LIT, halo=0)

    _draw_shadow_ellipse(px, 12.0, float(GROUND_ROW), 4.5, 1.5, strong=True)
    return px, glow.finish()


def _draw_collect_frame(step: int) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """Frames 6..9: Thread uncoils gracefully upward and blooms into rising violet-turquoise sparks."""
    px = make_grid(FRAME_W, FRAME_H)
    glow = GlowMap(FRAME_W, FRAME_H)
    t = step / 3.0  # 0..1
    rise = int(round(t * 7))

    # Sweeping separated arcs uncoiling into upward wisps
    arc_len = 14 - step * 3
    for k in range(arc_len):
        u = k / max(1, arc_len - 1)
        y = 22 - k - rise
        if y < 2:
            continue
        spread = (1.5 + t * 4.5) * math.sin(u * math.pi * 0.85 + 0.35)
        lx = int(round(12.0 - spread))
        rx = int(round(12.0 + spread))
        if 2 <= lx < FRAME_W - 2:
            px[y][lx] = TEAL_LIT if step > 0 else TEAL_CORE
            glow.emit(px, lx, y, TEAL_LIT, TEAL_CORE if step == 0 else TEAL_LIT, halo=1)
        if 2 <= rx < FRAME_W - 2:
            px[y][rx] = VIO_HI if step <= 1 else VIO_LIT
            glow.emit(px, rx, y, VIO_LIT, VIO_HI, halo=1)

    # Central knot flash & rising star-sparks
    ky = 15 - rise // 2
    if step == 0:
        for ox, oy in ((11, ky), (13, ky), (12, ky - 1), (12, ky + 1)):
            glow.emit(px, ox, oy, TEAL_CORE, TEAL_CORE, halo=2)
        glow.emit(px, 12, ky, TEAL_CORE, TEAL_CORE, halo=2)
    elif step == 1:
        for ox, oy in ((9, ky - 2), (15, ky - 2), (10, ky + 2), (14, ky + 2)):
            glow.emit(px, ox, oy, VIO_HI, VIO_HI, halo=1)
        glow.emit(px, 12, ky - 1, TEAL_CORE, TEAL_CORE, halo=2)
    else:
        sparks = ((7, 8 - step, TEAL_LIT), (16, 7 - step, VIO_HI), (11, 4, TEAL_CORE), (14, 12 - step, VIO_LIT), (9, 13, TEAL_MID))
        for sx, sy, col in sparks:
            if 2 <= sy < FRAME_H - 3:
                glow.emit(px, sx, sy, col, col, halo=1)

    _draw_shadow_ellipse(px, 12.0, float(GROUND_ROW), 4.0 - t * 1.2, 1.3, strong=False)
    return px, glow.finish()


def _draw_anchor_frame(pulse: int) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """Frames 10..11: Quiet post-collection woven ground anchor ring."""
    px = make_grid(FRAME_W, FRAME_H)
    glow = GlowMap(FRAME_W, FRAME_H)
    # 5x3 px ground-level woven anchor ring
    ring = [(11, 26), (12, 26), (13, 26), (10, 27), (14, 27), (11, 28), (12, 28), (13, 28)]
    for rx, ry in ring:
        px[ry][rx] = VIO_MID if ry == 26 else VIO_DARK
    if pulse == 0:
        glow.emit(px, 12, 27, TEAL_LIT, TEAL_LIT, halo=1)
        glow.emit(px, 11, 26, VIO_HI, VIO_HI, halo=0)
    else:
        glow.emit(px, 12, 27, TEAL_CORE, TEAL_CORE, halo=1)
        glow.emit(px, 13, 26, TEAL_LIT, TEAL_LIT, halo=0)
    _draw_shadow_ellipse(px, 12.0, float(GROUND_ROW), 3.5, 1.2, strong=False)
    return px, glow.finish()


def _blit(
    dst: list[list[tuple[int, int, int, int]]],
    src: list[list[tuple[int, int, int, int]]],
    ox: int,
    oy: int,
    alpha_blend: bool = True,
) -> None:
    dh, dw = len(dst), len(dst[0])
    for y, row in enumerate(src):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x, c in enumerate(row):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            dst[dy][dx] = blend_over(dst[dy][dx], c) if alpha_blend else c


def _tint_night(src: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    out = make_grid(len(src[0]), len(src))
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                out[y][x] = (max(6, int(c[0] * 0.44)), max(7, int(c[1] * 0.48)), max(14, int(c[2] * 0.68)), c[3])
    return out


def _add_glow(
    dst: list[list[tuple[int, int, int, int]]],
    glow: list[list[tuple[int, int, int, int]]],
    ox: int,
    oy: int,
) -> None:
    dh, dw = len(dst), len(dst[0])
    for y, row in enumerate(glow):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x, gc in enumerate(row):
            dx = ox + x
            if not (0 <= dx < dw) or gc[3] == 0:
                continue
            dc = dst[dy][dx]
            f = gc[3] / 255.0
            dst[dy][dx] = (
                min(255, int(dc[0] * (1.0 - 0.40 * f) + gc[0] * f * 1.35)),
                min(255, int(dc[1] * (1.0 - 0.40 * f) + gc[1] * f * 1.35)),
                min(255, int(dc[2] * (1.0 - 0.40 * f) + gc[2] * f * 1.35)),
                255,
            )


def build_4x_atlas(frames: list[tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]]) -> list[list[tuple[int, int, int, int]]]:
    """192 x 124 1x -> 768 x 496 4x nearest (Row 1 Day Idle 0..5, Row 2 Night Idle 0..5, Row 3 Pickup/Anchor 6..11 + Glow preview)."""
    lw, lh = 192, 124
    img = [[INK] * lw for _ in range(lh)]
    swatches = [hexc("3e7d56"), hexc("c49e72"), hexc("4d6272"), hexc("3e7d56"), hexc("c49e72"), hexc("4d6272")]
    night_bg = hexc("14192c")

    # Row 1: Day Idle 0..5 (y=4..35)
    for col in range(6):
        ox = 4 + col * 31
        bg = swatches[col]
        for y in range(FRAME_H):
            for x in range(FRAME_W):
                img[4 + y][ox + x] = bg
        base, _ = frames[col]
        _blit(img, base, ox, 4, alpha_blend=True)

    # Row 2: Night Idle 0..5 + Glow (y=42..73)
    for col in range(6):
        ox = 4 + col * 31
        for y in range(FRAME_H):
            for x in range(FRAME_W):
                img[42 + y][ox + x] = night_bg
        base, gl = frames[col]
        _blit(img, _tint_night(base), ox, 42, alpha_blend=True)
        _add_glow(img, gl, ox, 42)

    # Row 3: Pickup & Anchor 6..11 on Night (y=82..113)
    for idx in range(6):
        ox = 4 + idx * 31
        for y in range(FRAME_H):
            for x in range(FRAME_W):
                img[82 + y][ox + x] = night_bg
        base, gl = frames[6 + idx]
        _blit(img, _tint_night(base), ox, 82, alpha_blend=True)
        _add_glow(img, gl, ox, 82)

    scale = 4
    out = [[CLEAR] * (lw * scale) for _ in range(lh * scale)]
    for y in range(lh):
        for sy in range(scale):
            dst_row = out[y * scale + sy]
            for x in range(lw):
                c = img[y][x]
                bx = x * scale
                for sx in range(scale):
                    dst_row[bx + sx] = c
    return out


def main() -> None:
    frames = (
        [_draw_idle_frame(f) for f in range(6)]
        + [_draw_collect_frame(s) for s in range(4)]
        + [_draw_anchor_frame(p) for p in range(2)]
    )

    sheet = make_grid(SHEET_W, SHEET_H)
    glow_sheet = make_grid(SHEET_W, SHEET_H)
    for i, (base, gl) in enumerate(frames):
        col = i % COLS
        row = i // COLS
        assert len(base) == FRAME_H and len(base[0]) == FRAME_W
        assert len(gl) == FRAME_H and len(gl[0]) == FRAME_W
        _blit(sheet, base, col * FRAME_W, row * FRAME_H, alpha_blend=False)
        _blit(glow_sheet, gl, col * FRAME_W, row * FRAME_H, alpha_blend=False)

    atlas = build_4x_atlas(frames)

    verify_no_black("veil_thread.png", sheet)
    verify_no_black("veil_thread_glow.png", glow_sheet)
    verify_no_black("veil_thread_atlas_4x.png", atlas)
    verify_no_orphan_idle_pixels(frames[:6])

    props_dir = ROOT / "props"
    atlas_path = ROOT.parent / "docs" / "img" / "veil_thread_atlas_4x.png"
    write_png(props_dir / "veil_thread.png", SHEET_W, SHEET_H, sheet)
    write_png(props_dir / "veil_thread_glow.png", SHEET_W, SHEET_H, glow_sheet)
    write_png(atlas_path, len(atlas[0]), len(atlas), atlas)
    print(f"Wrote {props_dir / 'veil_thread.png'} ({SHEET_W}x{SHEET_H}), _glow.png, and {atlas_path} ({len(atlas[0])}x{len(atlas)})")


if __name__ == "__main__":
    main()
