#!/usr/bin/env python3
"""The great crow of the room's opening (src/entities/player/room_intro.gd): the crow of the window, seen so close that it flies past the whole screen. Drawn at the game's own pixel size,
with the world crow's plumage and the same ellipsoid renderer (art_hero3d, as art_corvid.py), but modelled for this size: flat feather blades (primaries fanned from the wrist, secondaries along the
forearm, covert rows on top), a fan tail, head with bill, eye and nape feathers. Flying to the right, seen from above and a little from the side, so the wings reach up and down the screen.
  python3 tools/art_intro_crow.py [preview.png]     writes assets/fx/intro_crow.png (8 flap frames in a row) and data/intro_crow.json (frame size, anchor)
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_corvid as ac  # noqa: E402  the world crow's palette and ink
import art_hero3d as art  # noqa: E402
from gen_art import CLEAR  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FRAMES = 20
FW, FH = 560, 640
CENTER = (FW // 2, FH // 2)  # where the bird's middle (the body) lies in a frame
PITCH, YAW = 62.0, 1.50  # flying to the right (yaw pi/2 would be the pure side view), seen from above
PLUMAGE, ALT, BILL, EYE, GLINT, RACHIS = 0, 1, 2, 3, 4, 5


def V(*a):
    return np.array(a, float)


def blade(m, a, b, width, thick, mat, up=(0, 1, 0)):
    """A flat feather from a to b: a leaf-shaped ellipsoid, wide in the plane that faces `up`."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = b - a
    length = float(np.linalg.norm(axis))
    R = art.frame_from(axis, V(*up))
    m.ell((a + b) / 2, (width, length / 2 * 1.04, thick), mat, R=R)
    if length > 40:  # the shaft: a thin lighter line along the middle, lifted a little out of the vane, so every long feather has its own spine
        m.ell((a + b) / 2 + R[:, 2] * thick * 0.9, (1.5, length / 2 * 0.97, thick * 0.8), RACHIS, R=R)


def plates(m, c, rx, ry, rz, z0, z1, step, w, L, thick, rng, a0=-30.0, a1=210.0, lift=0.32, alt_every=5):
    """Plumage: rows of small overlapping feathers laid on an ellipsoid (centre c, radii rx, ry, rz), from z0 down to z1 along the body, every feather pointing back (-z), its tip lifted a little so
    it lies over the next row like a shingle. The big smooth ellipsoids under them are only the dark ground."""
    z, row = z0, 0
    c = np.asarray(c, float)
    while z > z1:
        frac = z / rz
        if abs(frac) < 0.985:
            sc = math.sqrt(1.0 - frac * frac)
            ex, ey = rx * sc, ry * sc
            span = math.radians(a1 - a0)
            n = max(3, int(span * (ex + ey) / 2.0 / (w * 1.5)))
            for i in range(n):
                a = math.radians(a0) + span * (i + 0.5 * (row % 2)) / n
                p = V(ex * math.cos(a), ey * math.sin(a), z)
                nrm = V(p[0] / rx ** 2, p[1] / ry ** 2, p[2] / rz ** 2)
                nrm = nrm / np.linalg.norm(nrm)
                t = V(0, 0, -1) - nrm * float(nrm @ V(0, 0, -1))
                if np.linalg.norm(t) < 0.2:
                    t = V(0, -1, 0) - nrm * float(nrm @ V(0, -1, 0))
                t = t / np.linalg.norm(t)
                axis = t + nrm * lift
                axis = axis / np.linalg.norm(axis)
                R = art.frame_from(axis, nrm)
                ll = L * (0.9 + 0.25 * rng.random())
                m.ell(c + p + axis * ll * 0.42 - nrm * thick * 0.3, (w * (0.85 + 0.3 * rng.random()), ll / 2, thick), ALT if (i + row) % alt_every == 0 else PLUMAGE, R=R)
        z -= step
        row += 1


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.0]])


def wing(m, side, flap, hand_flap, rng_seed=3):
    """One wing. `side` -1 / +1; flap and hand_flap: angles (rad, positive = up) of the arm and the hand about the body's long axis."""
    rng = np.random.default_rng(rng_seed + (0 if side < 0 else 50))
    Ra, Rh = rot_z(-side * flap), rot_z(-side * hand_flap)
    shoulder = V(side * 34, 16, 34)
    elbow = shoulder + Ra @ V(side * 70, 0, -4)
    wrist = elbow + Ra @ V(side * 62, 0, 16) + (Rh @ V(side * 0, 0, 0))
    hand_dir = Rh @ V(side * 1.0, 0.0, -0.05)
    # the arm: leading edge, thick at the shoulder
    for a, b, ra, rb in ((shoulder, elbow, 20, 15), (elbow, wrist, 15, 11)):
        for i in range(7):
            t = i / 6.0
            m.ell(a + (b - a) * t, (ra + (rb - ra) * t,) * 3, PLUMAGE)
    # secondaries: along the forearm and upper arm, hanging back, a little longer towards the body
    for j in range(11):
        t = j / 10.0
        base = shoulder + (wrist - shoulder) * t + V(0, -3, -10)
        L = 128 - 40 * t + rng.uniform(-3, 3)
        d = Ra @ V(side * 0.12, -0.05, -1.0)
        blade(m, base, base + d / np.linalg.norm(d) * L, 17, 3.2, ALT if j % 3 == 1 else PLUMAGE, up=(0, 1, 0))
    # primaries: ten long blades fanned from the wrist, the outer ones longest and pointing out, the inner ones turning back; each flexes upward a little at the tip
    for i in range(10):
        f = i / 9.0
        base = wrist + hand_dir * (i * 4.5) + V(0, -2, -6 - i * 2.2)
        ang = -0.08 - f * 1.05  # outward .. back
        d = Rh @ V(side * math.cos(ang), 0.05 + 0.13 * (1 - f), math.sin(ang))
        L = 168 - f * 52 + (6 if i == 1 else 0) + rng.uniform(-2, 2)
        tip = base + d / np.linalg.norm(d) * L
        blade(m, base, tip, 14.5 - f * 2.2, 3.0, PLUMAGE if i % 3 else ALT, up=(0, 1, 0))
    # coverts: two rows of short feathers over the bases of the long ones, lighter plumage
    for row, (n, L, w, back) in enumerate(((12, 58, 15, 30), (14, 40, 12, 12))):
        for k in range(n):
            t = k / (n - 1.0)
            base = shoulder + (wrist - shoulder) * t + V(0, 4 + row * 2, 8 - back * 0.1)
            if t > 0.8:
                base = wrist + hand_dir * ((t - 0.8) * 140 + 4) + V(0, 4 + row * 2, -6)
            d = (Ra if t < 0.8 else Rh) @ V(side * 0.08, -0.02, -1.0)
            blade(m, base, base + d / np.linalg.norm(d) * L, w, 3.4, PLUMAGE if (k + row) % 4 else ALT, up=(0, 1, 0))


def crow(t):
    m = art.Model()
    ph = 2 * math.pi * t
    flap = 0.42 * math.sin(ph)
    hand = 0.55 * math.sin(ph - 0.8)  # the hand lags and flexes more
    bob = 5.0 * math.sin(ph + 0.6)
    body = V(0, bob, 0)
    rng = np.random.default_rng(5)
    m.ell(body + V(0, 0, 0), (44, 40, 98), PLUMAGE)  # the dark ground of the body, under the feathers
    m.ell(body + V(0, -2, -52), (34, 32, 62), PLUMAGE)
    m.ell(body + V(0, 6, 62), (38, 36, 46), PLUMAGE)
    m.ell(body + V(0, 20, 96), (27, 27, 30), PLUMAGE)
    plates(m, body, 44.5, 40.5, 98.5, 86, -92, 11, 13, 30, 3.2, rng)  # back, flanks, belly
    plates(m, body + V(0, 6, 62), 38.5, 36.5, 46.5, 44, 4, 10, 11, 24, 3.0, rng)  # the chest
    plates(m, body + V(0, 20, 96), 27.5, 27.5, 30.5, 28, -22, 9, 10, 20, 2.8, rng)  # the neck
    # head and bill
    m.ell(body + V(0, 26, 122), (31, 30, 34), PLUMAGE)
    m.ell(body + V(0, 20, 132), (22, 20, 20), PLUMAGE)
    plates(m, body + V(0, 26, 122), 31.5, 30.5, 34.5, 26, -26, 8, 8, 15, 2.6, rng, lift=0.22)  # the head: small close feathers
    for i in range(4):  # the bill: a stout wedge, a little hooked
        f = i / 3.0
        m.ell(body + V(0, 16 - f * 5 - f * f * 3, 144 + f * 46), (16 - f * 11, 14 - f * 10.0, 20), BILL)
    m.ell(body + V(0, 8, 150), (13, 5.5, 30), BILL, R=art.rot_x(0.1))  # the lower bill
    for s in (-1, 1):
        m.ell(body + V(s * 21, 32, 127), (5.4, 6.2, 5.0), EYE)  # the eye, with a glint
        m.ell(body + V(s * 24.5, 34, 130), (1.9, 2.1, 1.6), GLINT)
        for k in range(3):  # nape and cheek feathers, lit edges
            m.ell(body + V(s * (18 + k * 3), 10 + k * 5, 108 - k * 12), (7, 9, 15), ALT if k == 1 else PLUMAGE, R=art.rot_x(-0.5))
    # tail: a fan of seven blades, tilted a little with the wing beat
    for i in range(-3, 4):
        ang = i * 0.17
        base = body + V(0, -3, -108)
        d = V(math.sin(ang), -0.05 - 0.04 * math.sin(ph + 1.1), -math.cos(ang))
        blade(m, base, base + d * (122 - abs(i) * 4), 17, 3.5, ALT if i % 3 == 0 else PLUMAGE)
    # the legs tucked: two dark toes sticking out behind the belly
    for s in (-1, 1):
        for toe in (-1, 0, 1):
            m.limb(body + V(s * 16, -30, -70), body + V(s * 16 + toe * 9, -34, -96), 4.5, 2.4, BILL, step=4.0)
    # the wings, drawn after the body so the near wing covers it
    wing(m, -1, flap, hand)
    wing(m, 1, flap, hand, rng_seed=9)
    return m


def setup():
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = FW, FH, float(CENTER[1]), 3, 1.0
    art.PITCH = math.radians(PITCH)
    art.COSP, art.SINP = math.cos(art.PITCH), math.sin(art.PITCH)
    art.UHAT = np.array([0.0, art.COSP, -art.SINP])
    art.WHAT = np.array([0.0, art.SINP, art.COSP])
    art.DECAL_WEIGHT = {GLINT: 4.0, EYE: 3.0}
    art.LIGHT = np.array([-0.72, 0.42, 0.3])  # from the left and low: the back of the bird is in the middle shades, only its left edges catch the light, a black bird with a rim of light
    art.LIGHT = art.LIGHT / np.linalg.norm(art.LIGHT)
    ac.material(0)
    art.RAMPS.append([art.hexc(c) for c in ('2b3445', '3c4858', '626e7a', '8a98a2')])  # the shafts: a lighter line


def pixel_pass(img, seed=1):
    """Makes the flat bands pixel art: along every border between two shades of the same material the pixels alternate in a checkerboard (ordered dither, as the game's floors and walls do), and a few
    pixels step one shade up (plumage speckle). Ink lines (band 0 and the outline) stay."""
    lut = {}
    for m_, ramp in enumerate(art.RAMPS):
        for b_, c_ in enumerate(ramp):
            lut[tuple(int(v) for v in c_[:3])] = (m_, b_)
    H, W = img.shape[:2]
    M = np.full((H, W), -1, np.int16)
    B = np.full((H, W), -1, np.int16)
    for y in range(H):
        for x in np.nonzero(img[y, :, 3])[0]:
            hit = lut.get(tuple(int(v) for v in img[y, x, :3]))
            if hit:
                M[y, x], B[y, x] = hit
    up = np.zeros((H, W), bool)
    down = np.zeros((H, W), bool)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        Mn, Bn = np.roll(np.roll(M, dy, 0), dx, 1), np.roll(np.roll(B, dy, 0), dx, 1)
        up |= (Mn == M) & (Bn == B + 1) & (M >= 0)
        down |= (Mn == M) & (Bn == B - 1) & (M >= 0)
    yy, xx = np.mgrid[0:H, 0:W]
    chk = (xx + yy) % 2 == 0
    B2 = B + (up & chk & (B >= 1)).astype(np.int16) - (down & ~chk & (B >= 2)).astype(np.int16)
    n = ((xx * 374761393 + yy * 668265263 + seed * 2147483647) & 0xFFFFFFFF) / 4294967295.0
    B2 = B2 + ((n < 0.045) & (B2 >= 1) & (B2 <= 2)).astype(np.int16)
    out = img.copy()
    for m_, b_ in {(int(a), int(b)) for a, b in zip(M[M >= 0], B2[M >= 0])}:
        sel = (M == m_) & (B2 == b_)
        out[sel, :3] = np.array(art.RAMPS[m_][int(np.clip(b_, 0, 3))][:3], np.uint8)
    return out


def render_frame(t):
    prims = crow(t).transform(YAW, 0.0)
    depth, code = art.render(prims)
    rows = art.to_pixels(depth, code)
    img = np.array([[CLEAR if c[3] < 255 else c for c in row] for row in rows], dtype=np.uint8)
    return pixel_pass(img)


def wipe_edge(frame):
    """For every row of the frame the x (frame px) where the picture of the world ends and the white begins while this frame is on screen: a column inside the bird (its middle, smoothed over the
    rows), so the bird itself hides the edge. -1 where the bird does not cover the row."""
    solid = frame[..., 3] > 0
    mid = np.full(FH, np.nan)
    for y in range(FH):
        xs = np.nonzero(solid[y])[0]
        if len(xs) >= 12:
            mid[y] = (xs.min() + xs.max()) / 2.0
    ok = ~np.isnan(mid)
    idx = np.arange(FH)
    filled = np.interp(idx, idx[ok], mid[ok])
    k = 9
    smooth = np.convolve(np.pad(filled, k, mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
    out = []
    for y in range(FH):
        xs = np.nonzero(solid[y])[0]
        if len(xs) < 12:
            out.append(-1)
            continue
        out.append(int(round(min(max(smooth[y], xs.min() + 5), xs.max() - 5))))
    return out


def main():
    setup()
    frames = []
    for i in range(FRAMES):
        frames.append(render_frame(i / FRAMES))
        print("frame", i + 1, "/", FRAMES, flush=True)
    sheet = np.concatenate(frames, axis=1)
    out = ROOT / "assets" / "fx"
    out.mkdir(parents=True, exist_ok=True)
    Image.fromarray(sheet).save(out / "intro_crow.png")
    edges = [wipe_edge(f) for f in frames]
    print("rows of the screen window without cover:", [int((np.array(e) < 0).sum()) for e in edges])
    (ROOT / "data" / "intro_crow.json").write_text(json.dumps({"frames": FRAMES, "size": [FW, FH], "center": list(CENTER), "edge": edges}, separators=(",", ":")) + "\n")
    if len(sys.argv) > 1:
        prev = Image.new("RGBA", (FW * 4, FH), (244, 244, 244, 255))
        for i in range(4):
            prev.alpha_composite(Image.fromarray(frames[i * FRAMES // 4]), (i * FW, 0))
        prev.save(sys.argv[1])


if __name__ == "__main__":
    main()
