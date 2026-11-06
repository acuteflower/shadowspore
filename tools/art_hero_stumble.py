"""Ellie stumbles on the footpath while she is badly hurt: her foot drags, the knee gives, she pitches onto her hands and knees, stays there
a moment breathing, pushes up, sways, and walks on. 8 views (sectors E SE S SW W NW N NE like the other sheets), 24 fps.
  python3 tools/art_hero_stumble.py [sheet out.png]   writes assets/characters/player_stumble.png + player_stumble_blood.png and data/hero_rig.json "stumble"."""
import json
import sys
from pathlib import Path

import art_hero_emerge as em
import art_hero3d as hero
from gen_art import CLEAR, ROOT, write_png

Q = em.Q
FPS = 24
DURATION = 2.1
EVENTS = {"gasp": 0.12, "thud": 0.45, "hold": 0.7, "cough": 0.95, "rise": 1.15}  # hold..rise = the loop she stays in until she gets up (E)
WALK_A = Q(lean=0.12, dy=-1.0, legs=((0.4, 0.2), (-0.35, 0.45)), hand_l=(4.5, 25.0, 3.0), hand_r=(-5.0, 25.0, -1.5))
WALK_B = Q(lean=0.1, dy=-1.0, legs=((-0.3, 0.4), (0.4, 0.25)), hand_l=(4.5, 25.0, -1.5), hand_r=(-5.0, 25.0, 3.0))
KEYS = [
    (0.0, WALK_A, "io"),
    (0.12, Q(lean=0.3, pz=2.5, dy=-3.0, legs=((0.75, 0.5), (-0.4, 0.9)), hand_l=(4.0, 30.0, 9.0), hand_r=(-4.0, 29.0, 9.0), droop=1.5), "in"),  # the foot catches
    (0.28, Q(pitch=0.45, shift=(0.0, 0.0, 3.0), legs=((0.5, 1.0), (-0.1, 1.1)), hand_l=(3.5, 36.0, 8.0), hand_r=(-3.5, 36.0, 8.0), droop=5.0), "in"),  # the knee gives
    (0.45, Q(pitch=1.0, shift=(0.0, 0.0, 4.0), legs=((0.7, 1.4), (0.7, 1.4)), hand_l=(3.5, 37.0, 9.0), hand_r=(-3.5, 37.0, 9.0), droop=9.0, lean=-0.1), "in"),  # hands and knees
    (0.55, Q(pitch=1.1, shift=(0.0, -1.0, 4.0), legs=((0.7, 1.4), (0.7, 1.4)), hand_l=(3.5, 37.0, 9.0), hand_r=(-3.5, 37.0, 9.0), droop=9.0, lean=-0.1), "out"),  # the arms give a little
    (0.7, Q(pitch=1.0, shift=(0.0, 0.0, 4.0), legs=((0.7, 1.4), (0.7, 1.4)), hand_l=(3.5, 37.0, 9.0), hand_r=(-3.5, 37.0, 9.0), droop=9.0, lean=-0.1), "io"),
    (0.95, Q(pitch=1.06, shift=(0.0, -0.5, 4.0), legs=((0.7, 1.4), (0.7, 1.4)), hand_l=(3.5, 37.0, 9.0), hand_r=(-3.5, 37.0, 9.0), droop=9.0, lean=-0.1), "io"),  # breathing, a cough
    (1.15, Q(pitch=1.0, shift=(0.0, 0.0, 4.0), legs=((0.7, 1.4), (0.7, 1.4)), hand_l=(3.5, 37.0, 9.0), hand_r=(-3.5, 37.0, 9.0), droop=9.0, lean=-0.1), "io"),
    (1.4, Q(lean=0.3, pz=2.0, legs=((0.55, 1.0), (0.2, 0.5)), hand_l=(3.5, 24.0, 9.0), hand_r=(-3.5, 24.0, 9.0), droop=2.0), "io"),  # one knee, pushing up
    (1.7, Q(lean=0.22, pz=1.0, dy=-2.0, legs=((0.3, 0.5), (0.1, 0.3)), hand_l=(3.5, 26.0, 5.0), hand_r=(-3.5, 27.0, 5.0), droop=1.0), "io"),  # up, a hand on the wound
    (2.1, WALK_A, "io"),
]


def timeline(keys, t):
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, a, _), (t1, b, ease) in zip(keys, keys[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            k = {"lin": k, "in": k * k, "out": 1 - (1 - k) ** 2, "io": k * k * (3 - 2 * k)}[ease]
            return em.mix(a, b, k)
    return keys[-1][1]


def frames(sector, blood=False):
    em.SECTOR = sector
    return [em.render_frame(timeline(KEYS, (i + 0.5) / FPS), blood) for i in range(int(round(DURATION * FPS)))]


def main():
    W, H = hero.FW, hero.FH
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        sectors = (2, 0)
        k = 3
        cols = 13
        count = int(round(DURATION * FPS))
        rows_n = len(sectors) * ((count + cols - 1) // cols)
        out = [[(62, 125, 86, 255)] * (cols * W * k) for _ in range(rows_n * H * k)]
        per = (count + cols - 1) // cols
        for si, sec in enumerate(sectors):
            for i, fr in enumerate(frames(sec)):
                r, c = divmod(i, cols)
                for y in range(H):
                    for x in range(W):
                        px = fr[y][x]
                        if px[3]:
                            for dy in range(k):
                                for dx in range(k):
                                    out[((si * per + r) * H + y) * k + dy][(c * W + x) * k + dx] = px
        write_png(Path(sys.argv[2]), cols * W * k, rows_n * H * k, out)
        return
    count = int(round(DURATION * FPS))
    for blood, name in ((False, "player_stumble"), (True, "player_stumble_blood")):
        sheet = [[CLEAR] * (count * W) for _ in range(8 * H)]
        for sec in range(8):
            for i, fr in enumerate(frames(sec, blood)):
                for y in range(H):
                    sheet[sec * H + y][i * W:(i + 1) * W] = fr[y]
        write_png(ROOT / "characters" / f"{name}.png", count * W, 8 * H, sheet)
        print(name, "written", flush=True)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["stumble"] = {"fps": FPS, "frames": count, "events": EVENTS, "duration": DURATION}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
