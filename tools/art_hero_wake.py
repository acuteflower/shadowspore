#!/usr/bin/env python3
"""Ellie wakes up in the hut's bed and gets up (needs numpy; same renderer as art_hero3d.py / art_hero_emerge.py). Side view, facing east: the bed lies
east-west, her head on the pillow in the west, the foot end in the east, an old wool blanket over her legs. Frames of FRAME_W x FRAME_H, 12 a second:
  frames 0..SLEEP-1                  a breathing loop, asleep (head turned away)
  frames SLEEP..SLEEP+AWAKE-1        a breathing loop, awake: the head turned to the room, her hand on the bandage
  the rest                           getting up (GETUP_SECONDS): head up, onto the elbows, sitting, the blanket slides off, she scoots to the foot end,
                                     the legs swing over the edge, she sits there gasping, pushes up, stands, swaying
  assets/characters/player_wake.png         the frames side by side, the player node's feet anchor (40, 51) = the floor
  assets/characters/player_wake_blood.png   no blood in these frames, but the bandage mask (alpha 254, see art_hero3d.bandage_mask)
  data/hero_rig.json                        "wake": {fps, frames, sleep, awake, getup, offset (px of the player node from the bed's anchor, per frame), events}
The blanket is part of the sheet (ellipsoids over her, then a heap on the bed); when the sheet ends the bed prop (assets/props/hut/bed.png, frame 1) shows
the same heap. Usage:  python3 tools/art_hero_wake.py sheet out.png     contact sheet (green backdrop, 2x)
                       python3 tools/art_hero_wake.py                   writes the sheet, the blood map and the rig data"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero_emerge as em  # noqa: E402  (sets the frame size: overridden below)
import art_hero3d as hero  # noqa: E402
from gen_art import CLEAR, ROOT, write_png  # noqa: E402

FPS = 12
FRAME_W, FRAME_H = 80, 64
hero.FW, hero.FH = FRAME_W, FRAME_H
SECTOR = 0  # east
BED_H = 13.0  # the mattress top above the floor (model units; the bed prop is drawn for it)
SLEEP, AWAKE = 8, 8
GETUP_SECONDS = 5.6
HEAP_AT = -10.0  # px west of the bed's centre where the blanket ends up (the bed prop's frame 1)
BANDAGE_ON = True

REST_L, REST_R = em.REST_L, em.REST_R
EVENTS = {"groan": 0.35, "creak_a": 0.9, "sit": 2.0, "slide": 2.3, "legs": 3.0, "creak_b": 3.1, "breath": 3.9, "push": 4.6, "stand": 5.2}


def knees(t_l, t_r, lift=2.6):
    """Hand targets (model space before the body's pitch) on the knees of legs with the given thigh angles: the hands rest on them."""
    out = []
    for side, t in ((1, t_l), (-1, t_r)):
        hip = np.array([side * 2.5, 24.0, 0.2])
        knee = hip + 11.5 * np.array([0.0, -math.cos(t), math.sin(t)])
        out.append(tuple(knee + np.array([side * 2.2, lift, 0.4])))
    return out


def W(cover=1.0, bed=1.0, floor=None, anchor=(0.0, 0.0), spread=1.5, curl=2.1, **kw):
    """One key pose: `cover` 1 = the blanket lies over her, 0 = a heap on the bed; `bed` 1 = lying on the mattress (no ground shadow)."""
    d = em.Q(anchor=anchor, **kw)
    d["spread"] = spread
    d["curl"] = curl
    d["cover"] = cover
    d["bed"] = bed
    d["floor"] = BED_H if floor is None else floor  # height of her lowest point (not counting the hair): the mattress, or the floor
    return d


LYING = dict(pitch=-1.5, legs=((0.02, 0.06), (0.0, 0.05)), droop=2.5)
SIT_LEGS = ((0.0, 1.5), (0.0, 1.55))  # thighs flat on the mattress, the lower legs hang down over the foot end


# ---------------------------------------------------------------- the keys
def sleep_pose(k):
    """k 0..1 round the breathing loop."""
    b = 0.5 - 0.5 * math.cos(2 * math.pi * k)
    return W(**LYING, pz=0.55 * b, lean=0.02 + 0.035 * b, twist=-0.22, hand_l=(3.6, 25.5, 5.0), hand_r=(-3.8, 24.5, 4.5), hair=(0.0, 0.0, 0.3 * b), eyes_closed=1.0)


def awake_pose(k):
    b = 0.5 - 0.5 * math.cos(2 * math.pi * k)
    return W(**LYING, pz=0.7 * b, lean=0.03 + 0.04 * b, twist=0.28, hand_l=(2.4, 29.0, 4.2), hand_r=(-3.8, 24.5, 4.5), hair=(0.0, 0.0, 0.3 * b))


AWAKE0 = awake_pose(0.0)
GETUP = [
    (0.0, AWAKE0),
    (0.45, W(**LYING, pz=0.2, lean=0.05, twist=0.2, hand_l=(2.4, 29.0, 4.2), hand_r=(-3.8, 24.5, 4.5))),
    (0.95, W(**dict(LYING, droop=5.0), lean=0.42, twist=0.1, pz=-0.5, hand_l=(5.0, 24.0, -5.0), hand_r=(-5.0, 24.0, -5.0))),  # head and shoulders lift, hands find the mattress
    (1.7, W(**dict(LYING, droop=6.0), lean=0.95, twist=0.05, pz=-0.8, hand_l=(6.0, 20.0, -9.0), hand_r=(-6.0, 20.0, -9.0), cover=0.85)),  # up on the elbows, wincing
    (2.4, W(**dict(LYING, droop=6.0), lean=1.42, twist=0.0, pz=-0.4, hand_l=(5.0, 22.0, -7.0), hand_r=(-5.0, 22.0, -7.0), cover=0.35)),  # sitting up, the blanket slides
    (3.0, W(**dict(LYING, droop=5.0), lean=1.3, twist=0.0, hand_l=(4.0, 20.0, -5.0), hand_r=(-4.0, 20.0, -5.0), cover=0.05, anchor=(10.0, 0.0))),  # hands behind her, scooting east
    (3.7, W(**dict(LYING, legs=SIT_LEGS, droop=3.0), floor=5.0, lean=1.28, hand_l=(5.5, 20.0, -3.0), hand_r=(-5.5, 20.0, -3.0), cover=0.0, anchor=(22.0, 0.0), bed=0.6)),  # the legs swing over the foot end
    (4.4, W(**dict(LYING, legs=SIT_LEGS, droop=3.0), floor=0.0, lean=1.85, hand_l=knees(0.0, 0.0)[0], hand_r=knees(0.0, 0.0)[1], cover=0.0, anchor=(23.0, 0.0), bed=0.3)),  # head down, hands on the knees, breathing hard
    (4.9, W(floor=0.0, pitch=-0.9, lean=1.45, legs=((0.0, 0.9), (0.0, 0.9)), hand_l=knees(0.0, 0.0)[0], hand_r=knees(0.0, 0.0)[1], droop=3.0, cover=0.0, anchor=(29.0, 1.0), bed=0.0)),  # leaning forward, pushing up
    (5.3, W(floor=0.0, pitch=-0.35, lean=0.7, legs=((0.15, 0.5), (0.12, 0.45)), hand_l=knees(0.15, 0.12)[0], hand_r=knees(0.15, 0.12)[1], droop=2.0, cover=0.0, anchor=(33.0, 2.0), bed=0.0)),
    (GETUP_SECONDS, W(floor=0.0, lean=0.1, hand_l=REST_L, hand_r=REST_R, cover=0.0, anchor=(36.0, 3.0), bed=0.0, spread=0.5, curl=0.7)),  # standing, swaying a little
]


def blanket_prims(cover, anchor_px):
    """The old wool blanket: ellipsoids in model space (y up from the floor, z east). cover 1 over her legs from the hips down, 0 a heap on the bed."""
    heap_z = (HEAP_AT - anchor_px[0]) / hero.SCALE
    top = BED_H
    cover = max(0.0, min(1.0, cover))
    def lerp(a, b):
        return tuple(a[i] * cover + b[i] * (1.0 - cover) for i in range(3))
    specs = [  # (centre covering, centre heap, radii covering, radii heap)
        ((0.0, top + 3.6, 12.0), (0.0, top + 2.0, heap_z), (5.4, 3.5, 13.5), (4.8, 2.6, 6.5)),
        ((0.0, top + 4.2, 2.0), (0.0, top + 3.0, heap_z - 5.5), (5.2, 3.6, 4.0), (4.4, 3.0, 4.6)),
        ((1.5, top + 5.6, 8.0), (1.6, top + 4.6, heap_z + 1.0), (3.0, 1.6, 4.5), (3.0, 1.9, 3.2)),
        ((-1.2, top + 5.4, 16.0), (-1.4, top + 3.9, heap_z - 2.0), (3.2, 1.5, 4.0), (2.6, 1.6, 3.0)),
        ((-1.0, top + 5.0, 19.5), (-1.2, top + 3.2, heap_z + 3.0), (2.8, 1.3, 3.2), (3.2, 1.5, 2.6)),
        ((1.4, top + 4.6, 20.5), (1.6, top + 2.6, heap_z + 5.0), (2.6, 1.2, 3.0), (2.4, 1.3, 2.4)),
    ]
    out = []
    for c0, c1, r0, r1 in specs:
        out.append(hero.Prim(np.array(lerp(c0, c1), float), np.array(lerp(r0, r1), float), np.eye(3), hero.BLANKET, "blanket"))
    return out


def blanket_slide(t):
    """How far the blanket is pulled off her legs (0 spread over them .. 1 a heap) at time t of the get-up."""
    pts = [(0.0, 0.0), (0.9, 0.0), (1.7, 0.3), (2.4, 0.8), (3.1, 1.0)]
    for (t0, a), (t1, b) in zip(pts, pts[1:]):
        if t <= t1:
            k = max(0.0, (t - t0) / (t1 - t0))
            return a + (b - a) * k * k * (3 - 2 * k)
    return 1.0


def blanket_sheet():
    """The blanket as its own sheet over the bed (88 x 76 frames, bed space, the same frame count as the wake sheet): the game draws it over her, fixed to the bed."""
    from hut_cloth import cloth
    from hut_lib import render as render_model, to_array, grain, WOOL, CLAY
    import art_hero3d as hh
    frames_ = []
    total = SLEEP + AWAKE + int(round(GETUP_SECONDS * FPS))
    for i in range(total):
        t = (i - SLEEP - AWAKE + 0.5) / FPS
        s = 0.0 if i < SLEEP + AWAKE else blanket_slide(t)
        m = hh.Model()
        cloth(m, s)
        arr = to_array(render_model(m, 88, 76, 66))
        frames_.append(grain(arr, 5, amount=0.5, mats=(WOOL, CLAY)))
    return np.concatenate(frames_, axis=1)


def render_frame(pose, blood=False):
    model = hero.build(0.0, "attack", False, pose)
    body = [p for p in model.prims if p.kind != "hair"]  # set her lowest point (not the hair) at the mattress / floor height
    lowest = min(float(p.c[1] - np.sqrt(((p.R[1, :] * p.r) ** 2).sum())) for p in body)
    lift = float(pose["floor"]) - lowest
    for p in model.prims:
        p.c = p.c + np.array([0.0, lift, 0.0])
    yaw = math.pi / 2 - SECTOR * math.pi / 4
    if blood:
        blood_transform = None
        if pose.get("pitch"):
            rest = hero.build(0.0, "attack", False, dict(pose, pitch=0.0))
            pivot = np.array([0.0, 24.0, 0.0])
            rotation = hero.rot_x(float(pose["pitch"]))
            low = min(float((pivot + rotation @ (p.c - pivot))[1] - np.sqrt((((rotation @ p.R)[1, :] * p.r) ** 2).sum())) for p in rest.prims)
            translation = np.array(pose.get("shift", (0, 0, 0)), float) + np.array([0.0, -low + lift, 0.0])
            blood_transform = lambda pts: (pts - pivot - translation) @ rotation + pivot
        depth, code, thresholds = hero.render(model.transform(yaw, 0.0), yaw, 0.0, blood_transform)
        rows = hero.to_blood(thresholds, code, hero.LAST_BAND if BANDAGE_ON else None)
        for y in range(hero.FH):  # no blood in these frames: threshold "never"
            rows[y] = [(255, 255, 255, c[3]) if c[3] else c for c in rows[y]]
        return rows
    depth, code = hero.render(model.transform(yaw, 0.0))
    rows = hero.to_pixels(depth, code)
    if float(pose["bed"]) > 0.35:  # on the bed: the ground shadow (a dark ellipse at the floor row) would show on the mattress
        rows = [[CLEAR if tuple(c) == (0, 0, 0, 70) else c for c in row] for row in rows]
    return rows


def frame_poses():
    poses = []
    for i in range(SLEEP):
        poses.append(sleep_pose(i / SLEEP))
    for i in range(AWAKE):
        poses.append(awake_pose(i / AWAKE))
    count = int(round(GETUP_SECONDS * FPS))
    for i in range(count):
        poses.append(em.timeline(GETUP, (i + 0.5) / FPS))
    return poses


def frames(blood=False):
    return [(render_frame(p, blood), tuple(p["anchor"])) for p in frame_poses()]


def sheet_pixels(frame_rows, columns):
    rows_n = (len(frame_rows) + columns - 1) // columns
    sheet = [[CLEAR] * (columns * hero.FW) for _ in range(rows_n * hero.FH)]
    for i, fr in enumerate(frame_rows):
        r, c = divmod(i, columns)
        for y in range(hero.FH):
            sheet[r * hero.FH + y][c * hero.FW:(c + 1) * hero.FW] = fr[y]
    return sheet, rows_n


def contact(path, indices=None):
    frs = frames()
    if indices:
        frs = [frs[i] for i in indices]
    import os
    cols = int(os.environ.get('COLS', 8))
    sheet, rows_n = sheet_pixels([f[0] for f in frs], cols)
    bg = [[(112, 82, 60, 255)] * (cols * hero.FW) for _ in range(rows_n * hero.FH)]
    for y in range(rows_n * hero.FH):
        for x in range(cols * hero.FW):
            c = sheet[y][x]
            if c[3]:
                bg[y][x] = c
    k = int(os.environ.get('K', 2))
    big = [[bg[y // k][x // k] for x in range(cols * hero.FW * k)] for y in range(rows_n * hero.FH * k)]
    write_png(Path(path), cols * hero.FW * k, rows_n * hero.FH * k, big)


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "compose":
        save_blanket() if "--blanket" in sys.argv else None
        compose(sys.argv[2], [int(a) for a in sys.argv[3:] if not a.startswith("--")])
        return
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        pick = [int(a) for a in sys.argv[3:]] if len(sys.argv) > 3 else None
        contact(sys.argv[2], pick)
        print("contact sheet written")
        return
    frs = frames()
    sheet, _ = sheet_pixels([f[0] for f in frs], len(frs))
    write_png(ROOT / "characters" / "player_wake.png", len(frs) * hero.FW, hero.FH, sheet)
    blood = frames(True)
    bsheet, _ = sheet_pixels([f[0] for f in blood], len(blood))
    write_png(ROOT / "characters" / "player_wake_blood.png", len(blood) * hero.FW, hero.FH, bsheet)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    save_blanket()
    rig = json.loads(rig_path.read_text())
    rig["wake"] = {"fps": FPS, "frames": len(frs), "sleep": [0, SLEEP], "awake": [SLEEP, AWAKE], "getup": [SLEEP + AWAKE, len(frs) - SLEEP - AWAKE],
                   "offset": [[round(a[0], 2), round(a[1], 2)] for _, a in frs], "events": EVENTS, "duration": GETUP_SECONDS, "frame_w": FRAME_W, "frame_h": FRAME_H}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("wake sheet, blood map and rig data written")



def save_blanket():
    from hut_lib import save as save_arr
    save_arr(ROOT / "interior" / "hut" / "blanket.png", blanket_sheet())


def compose(path, indices, k=3):
    """The wake sheet in place: the bed (assets/interior/hut/bed.png frame 0), Ellie at her anchor offsets, and the blanket sheet over her, on the hut's floor colour."""
    from hut_lib import load_png_arr
    bed = load_png_arr(ROOT / "interior" / "hut" / "bed.png")
    wake = load_png_arr(ROOT / "characters" / "player_wake.png")
    blanket_path = ROOT / "interior" / "hut" / "blanket.png"
    blanket = load_png_arr(blanket_path) if blanket_path.exists() else None
    rig = json.loads((ROOT.parent / "data" / "hero_rig.json").read_text())["wake"]
    cw, ch = 150, 96
    cols = 5
    rows_n = (len(indices) + cols - 1) // cols
    canvas = np.zeros((rows_n * ch, cols * cw, 4), np.uint8)
    canvas[:] = (62, 44, 54, 255)

    def paste(dst_x, dst_y, arr):
        ah, aw = arr.shape[:2]
        for yy in range(ah):
            for xx in range(aw):
                x, y = dst_x + xx, dst_y + yy
                if arr[yy, xx, 3] and 0 <= x < canvas.shape[1] and 0 <= y < canvas.shape[0]:
                    a = arr[yy, xx, 3] / 255.0
                    canvas[y, x, :3] = arr[yy, xx, :3] * a + canvas[y, x, :3] * (1 - a)

    for n, idx in enumerate(indices):
        cx, cy = (n % cols) * cw, (n // cols) * ch
        bx, by = cx + 20, cy + 14  # bed picture top-left (88 x 76, feet row 66 at bed centre x 44)
        paste(bx, by, bed[:, 0:88])
        ox, oy = rig["offset"][idx]
        node = (bx + 44 + ox, by + 66 + oy)  # the player node: Ellie's frame has its feet anchor at (40, 51)
        paste(int(node[0] - 40), int(node[1] - 51), wake[:, idx * FRAME_W:(idx + 1) * FRAME_W])
        if blanket is not None:
            paste(bx, by, blanket[:, idx * 88:(idx + 1) * 88])
    big = np.repeat(np.repeat(canvas, k, axis=0), k, axis=1)
    save_png_arr(path, big)


def save_png_arr(path, arr):
    from hut_lib import save
    save(path, arr)


if __name__ == "__main__":
    main()
