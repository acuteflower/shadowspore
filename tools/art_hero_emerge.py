#!/usr/bin/env python3
"""The intro animation: Ellie pushes the manhole lid aside from below and crawls out of the sewer (needs numpy; uses the
heroine renderer of art_hero3d.py). One direction only (she faces east, seen from the side: the clearest silhouette of a body
that climbs and crawls), 10 frames a second:
  assets/characters/player_emerge.png   frames of 72x76 side by side, feet anchor (36, 51) = the hole's middle
  data/hero_rig.json                    gets "emerge": {fps, frames, offset (px of the player node from the cover, per frame),
                                        events (seconds: what the lid, dust, sound and camera do)}
While she is still in the shaft everything below the ground line (row GROUND_CUT) is cut off. Frames are FRAME_W (72) wide, FRAME_H (76) high, feet anchor (36, 51).
Usage:  python3 tools/art_hero_emerge.py sheet out.png   contact sheet for looking at the poses
        python3 tools/art_hero_emerge.py                 writes the sheet and the rig data"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as hero  # noqa: E402
from gen_art import CLEAR, ROOT, write_png  # noqa: E402

FPS = 12
FRAME_W = 72  # wider than the walk frames (48): a body lying on the ground is long, nothing may touch the border
TIME_SCALE = 0.65  # the key times below are written for a 10 s scene; the real one is faster (this scales keys, events and duration)
FRAME_H = 76  # 20 rows below the feet: what is still in the shaft fades into the dark there instead of being cut off
SHAFT_FADE = 16
hero.FW = FRAME_W
hero.FH = FRAME_H
SECTOR = 0  # east
GROUND_CUT = 52  # frame row of the ground at the hole's middle: below it nothing of her shows while she is in the shaft
REST_L, REST_R = (4.5, 26.0, 1.0), (-5.0, 25.5, 2.0)
UP = (0.0, 1.0, 0.0)

# Seconds into the scene (the player node's time); the game reads these from data/hero_rig.json.
EVENTS = {
    "knock1": 0.55, "knock2": 1.05, "jolt": 1.45,  # the lid is struck from below, dust sifts out of the joint
    "lid_start": 1.7, "lid_end": 2.5,  # it grinds aside
    "hand": 2.0,  # the first fingers show
    "gasp": 4.0,  # she gets her head up and gulps air
    "over_rim": 4.9,  # her weight comes over the collar
    "thud": 5.6,  # chest on the stones
    "cough": 7.0,
    "stand": 8.6,  # she is up
}
DURATION = 10.0


def Q(twist=0.0, lean=0.0, pz=0.0, dy=0.0, pitch=0.0, shift=(0.0, 0.0, 0.0), legs=((0.0, 0.04), (0.0, 0.04)), hand_r=REST_R, hand_l=REST_L,
      hair=(0.0, 0.0, 0.0), droop=0.0, flare=0.0, pole_l=(0.8, -0.6, -0.3), pole_r=(-0.8, -0.6, -0.3), cut=False, anchor=(0.0, 0.0), eyes_closed=0.0):
    """One key pose of the intro. Model units (about px / 0.92), she faces +z (east on screen). dy/pz move the upper body, pitch turns the
    whole body about the pelvis (prone), shift moves everything afterwards, hands are targets in the model's space before pitch."""
    d = hero.P(twist, lean, pz, ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0)), hand_r, hand_l, hair, flare)
    d.update({"leg_angles": legs, "dy": dy, "pitch": pitch, "shift": shift, "both_arms": True, "droop": droop, "pole_l": pole_l, "pole_r": pole_r,
              "cut": 1.0 if cut else 0.0, "anchor": anchor, "eyes_closed": float(eyes_closed)})
    return d


def mix(a, b, k):
    if isinstance(a, dict):
        return {key: mix(a[key], b[key], k) for key in a}
    if isinstance(a, (tuple, list)):
        return tuple(mix(x, y, k) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and not isinstance(a, bool):
        return a * (1.0 - k) + b * k
    return a


def timeline(keys, t):
    """Pose at time t (seconds) on a list of (time, pose); eased between keys, held before the first and after the last."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            return mix(a, b, k * k * (3 - 2 * k))
    return keys[-1][1]


# ---------------------------------------------------------------- the keys
# Phase 1 (1.9-2.6 s): fingers, then gloves and forearms grip the collar to the east. She is deep in the shaft, only her arms show.
# Phase 2 (2.6-4.9 s): she hauls herself up on her arms: head, shoulders; she hangs there, head down, then gets her head up and gasps.
# Phase 3 (4.9-6.0 s): she throws her weight over the rim, chest down on the stones, legs still in the shaft.
# Phase 4 (6.0-8.0 s): she drags the legs out, lies breathing, coughs; Phase 5 (8.0-9.8 s): pushes up onto her hands, her knees, stands.
HANDS_ON_RIM = dict(hand_l=(3.0, 3.0, 25.0), hand_r=(-3.0, 3.0, 25.5))
KEYS = [
    (1.9, Q(dy=-60.0, pz=13.0, lean=0.1, hand_l=(3.0, 1.5, 25.0), hand_r=(-3.0, 1.0, 25.5), pole_l=(0.8, -0.2, -0.6), pole_r=(-0.8, -0.2, -0.6), cut=True)),
    (2.5, Q(dy=-47.0, pz=13.0, lean=0.15, **HANDS_ON_RIM, pole_l=(0.8, -0.2, -0.6), pole_r=(-0.8, -0.2, -0.6), cut=True)),
    (3.1, Q(dy=-32.0, pz=12.0, lean=0.32, **HANDS_ON_RIM, hair=(0.0, 0.0, 0.0), droop=3.0, pole_l=(0.9, 0.0, -0.8), pole_r=(-0.9, 0.0, -0.8), cut=True)),
    (3.7, Q(dy=-22.0, pz=11.0, lean=0.5, **HANDS_ON_RIM, droop=4.5, pole_l=(0.9, 0.0, -0.8), pole_r=(-0.9, 0.0, -0.8), cut=True)),
    (4.2, Q(dy=-20.0, pz=11.0, lean=-0.1, **HANDS_ON_RIM, droop=2.0, pole_l=(0.9, 0.0, -0.8), pole_r=(-0.9, 0.0, -0.8), cut=True)),  # head up, gasping
    (4.7, Q(dy=-19.0, pz=11.5, lean=0.0, **HANDS_ON_RIM, droop=2.0, pole_l=(0.9, 0.0, -0.8), pole_r=(-0.9, 0.0, -0.8), cut=True)),
    (5.1, Q(dy=-8.0, pz=13.0, lean=0.55, hand_l=(3.0, 3.0, 29.0), hand_r=(-3.0, 3.0, 29.5), droop=4.0, pole_l=(0.9, 0.0, -0.8), pole_r=(-0.9, 0.0, -0.8), cut=True)),
    (5.7, Q(pitch=1.25, shift=(0.0, -9.0, 8.0), hand_l=(3.5, 47.0, 4.5), hand_r=(-3.5, 47.0, 4.0), legs=((-0.1, 0.1), (-0.1, 0.1)), droop=12.0,
            pole_l=(0.9, -0.2, -0.4), pole_r=(-0.9, -0.2, -0.4), cut=True, anchor=(4.0, 0.0))),
    (6.4, Q(pitch=1.5, shift=(0.0, -4.0, 8.0), hand_l=(3.5, 53.0, 4.5), hand_r=(-3.5, 51.0, 4.0), legs=((-0.2, 0.15), (-0.25, 0.1)), droop=12.0,
            pole_l=(0.9, -0.2, -0.4), pole_r=(-0.9, -0.2, -0.4), cut=True, anchor=(10.0, 0.0))),
    (7.0, Q(pitch=1.5, shift=(0.0, 0.0, 6.0), hand_l=(3.5, 57.0, 4.5), hand_r=(-3.5, 52.0, 4.0), legs=((-0.1, 0.5), (-0.5, 0.1)), droop=12.0,
            pole_l=(0.9, -0.2, -0.4), pole_r=(-0.9, -0.2, -0.4), anchor=(18.0, 1.0))),  # dragging herself, the legs come out
    (7.5, Q(pitch=1.5, shift=(0.0, 0.0, 4.0), hand_l=(3.5, 56.0, 4.5), hand_r=(-3.5, 57.0, 4.0), legs=((-0.05, 0.1), (-0.1, 0.4)), droop=12.0,
            pole_l=(0.9, -0.2, -0.4), pole_r=(-0.9, -0.2, -0.4), anchor=(24.0, 2.0))),
    (8.1, Q(pitch=1.5, shift=(0.0, 0.0, 4.0), hand_l=(3.5, 54.0, 4.5), hand_r=(-3.5, 54.0, 4.0), legs=((0.0, 0.05), (0.0, 0.05)), droop=12.0,
            pole_l=(0.9, -0.2, -0.4), pole_r=(-0.9, -0.2, -0.4), anchor=(27.0, 3.0))),  # lying, breathing
    (8.9, Q(pitch=1.0, shift=(0.0, 0.0, 4.0), hand_l=(3.5, 37.0, 9.0), hand_r=(-3.5, 37.0, 9.0), legs=((0.7, 1.4), (0.7, 1.4)), droop=9.0,
            lean=-0.1, pole_l=(0.9, -0.2, -0.4), pole_r=(-0.9, -0.2, -0.4), anchor=(29.0, 4.0))),  # up onto hands and knees
    (9.5, Q(lean=0.3, pz=2.0, legs=((0.55, 1.0), (0.2, 0.5)), hand_l=(3.5, 24.0, 9.0), hand_r=(-3.5, 24.0, 9.0), droop=2.0, anchor=(33.0, 8.0))),  # on one knee
    (10.0, Q(lean=0.08, anchor=(36.0, 12.0), hand_l=REST_L, hand_r=REST_R)),  # standing, swaying a little (the player's spawn: WorldLevel.INTRO_SPAWN)
]


KEYS = [(t * TIME_SCALE, pose) for t, pose in KEYS]
EVENTS = {name: round(t * TIME_SCALE, 3) for name, t in EVENTS.items()}
DURATION = DURATION * TIME_SCALE


def render_frame(pose, blood=False):
    model = hero.build(0.0, "attack", False, pose)
    yaw = math.pi / 2 - SECTOR * math.pi / 4
    if blood:
        # Undo the whole-body pitch/ground placement for wound coordinates, so
        # crawling does not move the waist stain onto her head or hair.
        blood_transform = None
        if pose.get("pitch"):
            rest_pose = dict(pose, pitch=0.0)
            rest = hero.build(0.0, "attack", False, rest_pose)
            pivot = np.array([0.0, 24.0, 0.0])
            rotation = hero.rot_x(float(pose["pitch"]))
            low = min(float((pivot + rotation @ (p.c - pivot))[1] - np.sqrt((((rotation @ p.R)[1, :] * p.r) ** 2).sum())) for p in rest.prims)
            translation = np.array(pose.get("shift", (0, 0, 0)), float) + np.array([0.0, -low, 0.0])
            blood_transform = lambda pts: (pts - pivot - translation) @ rotation + pivot
        depth, code, thresholds = hero.render(model.transform(yaw, 0.0), yaw, 0.0, blood_transform)
        rows = hero.to_blood(thresholds, code)
    else:
        depth, code = hero.render(model.transform(yaw, 0.0))
        rows = hero.to_pixels(depth, code)
    if pose["cut"] > 0.5:  # below the ground line she is in the shaft: darker and fainter with depth, gone after SHAFT_FADE rows
        for y in range(GROUND_CUT, hero.FH):
            k = (y - GROUND_CUT) / SHAFT_FADE
            if blood:
                if k >= 1.0:
                    rows[y] = [CLEAR] * hero.FW
                continue
            rows[y] = [CLEAR if (k >= 1.0 or c[3] == 0) else (int(c[0] * (1 - 0.85 * k)), int(c[1] * (1 - 0.85 * k)), int(c[2] * (1 - 0.8 * k)), int(c[3] * (1 - k))) for c in rows[y]]
    return rows


def frames(blood=False):
    count = int(round(DURATION * FPS))
    out = []
    for i in range(count):
        t = (i + 0.5) / FPS
        if t < KEYS[0][0] - 0.1:
            out.append(([[CLEAR] * hero.FW for _ in range(hero.FH)], (0.0, 0.0)))  # still in the dark: nothing to see
            continue
        pose = timeline(KEYS, t)
        out.append((render_frame(pose, blood), tuple(pose["anchor"])))
    return out


def sheet_pixels(frame_rows, columns):
    rows_n = (len(frame_rows) + columns - 1) // columns
    sheet = [[CLEAR] * (columns * hero.FW) for _ in range(rows_n * hero.FH)]
    for i, fr in enumerate(frame_rows):
        r, c = divmod(i, columns)
        for y in range(hero.FH):
            sheet[r * hero.FH + y][c * hero.FW:(c + 1) * hero.FW] = fr[y]
    return sheet, rows_n


def zoom(times, path):
    """Some frames side by side at 6x on a green backdrop: python3 tools/art_hero_emerge.py frame out.png 2.5 3.1 ..."""
    cells = []
    for t in times:
        pose = timeline(KEYS, t)
        cells.append(render_frame(pose))
    k = 6
    w, h = hero.FW * k, hero.FH * k
    out = [[(62, 125, 86, 255)] * (w * len(cells)) for _ in range(h)]
    for n, rows in enumerate(cells):
        for y in range(hero.FH):
            for x in range(hero.FW):
                c = rows[y][x]
                if c[3]:
                    for dy in range(k):
                        for dx in range(k):
                            out[y * k + dy][n * w + x * k + dx] = c
        gy = GROUND_CUT * k
        for x in range(w):
            out[gy][n * w + x] = (200, 60, 60, 255)
    write_png(Path(path), w * len(cells), h, out)


def write_blood():
    frs = frames(blood=True)
    sheet, _ = sheet_pixels([f[0] for f in frs], len(frs))
    write_png(ROOT / "characters" / "player_emerge_blood.png", len(frs) * hero.FW, hero.FH, sheet)
    print("emerge blood thresholds written")


def main():
    if "--blood" in sys.argv:
        write_blood()
        return
    if len(sys.argv) > 3 and sys.argv[1] == "frame":
        zoom([float(a) for a in sys.argv[3:]], sys.argv[2])
        return
    frs = frames()
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        cols = 10
        sheet, rows_n = sheet_pixels([f[0] for f in frs], cols)
        # a green backdrop so the silhouettes can be judged, 2x
        bg = [[(62, 125, 86, 255)] * (cols * hero.FW) for _ in range(rows_n * hero.FH)]
        for y in range(rows_n * hero.FH):
            for x in range(cols * hero.FW):
                c = sheet[y][x]
                if c[3]:
                    bg[y][x] = c
        big = [[bg[y // 2][x // 2] for x in range(cols * hero.FW * 2)] for y in range(rows_n * hero.FH * 2)]
        write_png(Path(sys.argv[2]), cols * hero.FW * 2, rows_n * hero.FH * 2, big)
        print("contact sheet written")
        return
    sheet, _ = sheet_pixels([f[0] for f in frs], len(frs))
    write_png(ROOT / "characters" / "player_emerge.png", len(frs) * hero.FW, hero.FH, sheet)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["emerge"] = {"fps": FPS, "frames": len(frs), "offset": [[round(a[0], 2), round(a[1], 2)] for _, a in frs], "events": EVENTS, "duration": DURATION}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    write_blood()
    print("emerge sheet and rig data written")


if __name__ == "__main__":
    main()
