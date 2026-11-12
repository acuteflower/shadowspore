"""Ellie faints at the end of the crossroad ambush: she sways, clutches the wound, her knees give, she kneels, tips over backwards and lies there.
Side views in separate east and west rows; same frame size and the same renderer.
  python3 tools/art_hero_faint.py [sheet out.png]   writes assets/characters/player_faint.png + player_faint_blood.png and data/hero_rig.json "faint"."""
import json
import sys
from pathlib import Path

import art_hero_emerge as em
import art_hero3d as hero
from gen_art import CLEAR, ROOT, write_png

Q = em.Q
FPS = 24
DURATION = 2.2
EVENTS = {"buckle": 0.75, "kneel": 0.98, "fall": 1.3, "thud": 1.74}
REST_L, REST_R = em.REST_L, em.REST_R
KNEEL = ((0.12, 1.5), (0.15, 1.45))
# (time, pose, easing of the segment that ends here): she clutches the wound, sags, her knees hit the ground (gravity: ease-in), she rebounds
# upright for a moment, sways back, topples with real weight (accelerating), hits the ground, bounces once and settles.
KEYS = [
    (0.0, Q(lean=0.06, hand_l=REST_L, hand_r=REST_R), "io"),
    (0.4, Q(lean=0.16, pz=1.0, dy=-1.5, legs=((0.2, 0.35), (0.08, 0.25)), hand_l=(3.5, 26.0, 5.0), hand_r=(-3.5, 27.0, 5.0), droop=1.0), "io"),
    (0.75, Q(lean=0.28, pz=2.0, dy=-4.5, legs=((0.5, 1.0), (0.2, 0.6)), hand_l=(4.5, 23.0, 6.0), hand_r=(-4.5, 23.0, 5.0), droop=2.0), "io"),
    (0.98, Q(lean=0.22, pz=1.5, dy=-10.2, legs=KNEEL, hand_l=(5.0, 17.0, 8.0), hand_r=(-5.0, 18.0, 7.0), droop=3.0, hair=(0.0, 0.0, 2.0)), "in"),
    (1.12, Q(lean=0.0, pz=0.5, dy=-10.2, legs=KNEEL, hand_l=(5.0, 15.0, 6.0), hand_r=(-5.0, 16.0, 5.0), droop=2.0), "out"),
    (1.3, Q(lean=-0.28, pz=-1.0, dy=-10.2, legs=KNEEL, hand_l=(7.0, 22.0, -1.0), hand_r=(-7.0, 23.0, 0.0), droop=2.0), "io"),
    (1.5, Q(pitch=-0.65, shift=(0.0, -3.0, 2.0), legs=((0.3, 1.1), (0.4, 1.0)), hand_l=(8.0, 27.0, -3.0), hand_r=(-8.0, 26.0, -2.0), droop=4.0, eyes_closed=1.0), "in"),
    (1.66, Q(pitch=-1.35, shift=(0.0, -7.5, 4.0), legs=((0.35, 0.8), (0.5, 0.9)), hand_l=(9.0, 24.0, 2.0), hand_r=(-8.0, 24.0, 3.0), droop=5.0, eyes_closed=1.0), "in"),
    (1.74, Q(pitch=-1.52, shift=(0.0, -8.8, 4.0), legs=((0.25, 0.5), (0.4, 0.7)), hand_l=(9.5, 21.0, 3.0), hand_r=(-7.0, 22.0, 3.0), droop=3.0, eyes_closed=1.0), "lin"),
    (1.84, Q(pitch=-1.4, shift=(0.0, -6.0, 4.0), legs=((0.3, 0.6), (0.45, 0.75)), hand_l=(9.0, 22.0, 3.0), hand_r=(-6.0, 23.0, 3.0), droop=4.0, eyes_closed=1.0), "out"),
    (1.96, Q(pitch=-1.5, shift=(0.0, -8.8, 4.0), legs=((0.15, 0.45), (0.32, 0.65)), hand_l=(8.0, 20.0, 3.0), hand_r=(-3.0, 25.0, 1.0), droop=3.0, eyes_closed=1.0), "in"),
    (2.2, Q(pitch=-1.5, shift=(0.0, -8.8, 4.0), legs=((0.12, 0.4), (0.28, 0.6)), hand_l=(8.4, 19.0, 3.4), hand_r=(-3.0, 25.0, 1.0), droop=3.0, eyes_closed=1.0), "io"),
]


def timeline(keys, t):
    """Pose at time t; each segment has its own easing (the third item of the key that ends it)."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, a, _), (t1, b, ease) in zip(keys, keys[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            k = {"lin": k, "in": k * k, "out": 1 - (1 - k) ** 2, "io": k * k * (3 - 2 * k)}[ease]
            return em.mix(a, b, k)
    return keys[-1][1]


def frames(blood=False):
    return [em.render_frame(timeline(KEYS, (i + 0.5) / FPS), blood) for i in range(int(round(DURATION * FPS)))]


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        frs = frames()
        cols = 8
        rows_n = (len(frs) + cols - 1) // cols
        k = 3
        W, H = hero.FW, hero.FH
        out = [[(62, 125, 86, 255)] * (cols * W * k) for _ in range(rows_n * H * k)]
        for i, fr in enumerate(frs):
            r, c = divmod(i, cols)
            for y in range(H):
                for x in range(W):
                    px = fr[y][x]
                    if px[3]:
                        for dy in range(k):
                            for dx in range(k):
                                out[(r * H + y) * k + dy][(c * W + x) * k + dx] = px
        write_png(Path(sys.argv[2]), cols * W * k, rows_n * H * k, out)
        return
    for blood, name in ((False, "player_faint"), (True, "player_faint_blood")):
        em.SECTOR = 0
        frs = frames(blood)
        em.SECTOR = 4
        west = frames(blood)
        W, H = hero.FW, hero.FH
        sheet = [[CLEAR] * (len(frs) * W) for _ in range(2 * H)]
        for row, facing in enumerate((frs, west)):
            for i, fr in enumerate(facing):
                for y in range(H):
                    sheet[row * H + y][i * W:(i + 1) * W] = fr[y]
        write_png(ROOT / "characters" / f"{name}.png", len(frs) * W, 2 * H, sheet)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["faint"] = {"fps": FPS, "frames": len(frs), "events": EVENTS, "duration": DURATION}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("faint sheet written")


if __name__ == "__main__":
    main()
