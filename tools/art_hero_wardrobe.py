"""Ellie shuts her wardrobe (the opening of her room, src/entities/player/room_intro.gd): she stands in front of it, facing north, the right door open to the side; she reaches out for its edge, pushes it
round and shut, leans on both doors for a moment, breathes out and steps back. One direction (north), baked with the wardrobe's door angles of tools/servant_furniture.py, so the hands really are on the door.
  python3 tools/art_hero_wardrobe.py [sheet out.png]   writes assets/characters/player_wardrobe.png and the "wardrobe" entry of data/hero_rig.json (fps, frames, the door's angle per frame, the thud)
Her place: STAND_X right of the wardrobe's middle, STAND_G in front of its front plane (model units, as in servant_furniture.py: wardrobe half width 22, door depth 9, free edge of the door 21.5 from its hinge)."""
import json
import math
import sys
from pathlib import Path

import art_hero3d as hero
import art_hero_emerge as em
from gen_art import CLEAR, ROOT, write_png

Q = em.Q
FPS = 12
DURATION = 3.6
THUD = 2.50  # the door meets its frame
STAND_X, STAND_G = 5.0, 17.0
W2, D2, EDGE_U = 22.0, 9.0, 21.5
OPEN_MAX = math.radians(90.0)


def ease(k):
    k = max(0.0, min(1.0, k))
    return k * k * (3 - 2 * k)


def door_angle(t):
    """Radians: wide open, a hold, the push (slow at first, then faster), the knock into the frame and a small rebound, shut."""
    if t < 0.95:
        return OPEN_MAX
    if t < THUD:
        k = (t - 0.95) / (THUD - 0.95)
        return OPEN_MAX * (1.0 - (k ** 1.7 * 0.55 + ease(k) * 0.45))
    if t < THUD + 0.10:
        return math.radians(7.0) * math.sin((t - THUD) / 0.10 * math.pi)  # it bounces off the frame
    return 0.0


def hand_on_door(theta, y=34.0, off=0.0):
    """Her right hand on the door's free edge at the angle theta, in her model space (x: left of her +, z: forward)."""
    x_edge = W2 - EDGE_U * math.cos(theta)
    z_edge = D2 + EDGE_U * math.sin(theta)
    return (-(x_edge - STAND_X), y, (D2 + STAND_G) - z_edge + off)


def pose(t):
    th = door_angle(t)
    breath = 0.25 * math.sin(t * 2.0 * math.pi * 0.55)
    # phases: 0-0.95 standing at the open wardrobe (a hand on the door's edge), 0.95-2.5 pushing, 2.5-3.0 leaning on the shut doors, 3.0-3.6 breathing out, a step back
    push = ease((t - 0.55) / 0.4) * (1.0 - ease((t - THUD - 0.05) / 0.5))
    lean = 0.04 + 0.2 * push + (0.12 * ease((t - THUD) / 0.25) * (1.0 - ease((t - 3.0) / 0.5)))
    twist = 0.55 * (1.0 - ease((t - 0.95) / 1.5)) if t < 2.6 else 0.0
    hr = hand_on_door(th, 34.0, -1.2 if t < THUD + 0.1 else 0.0)
    if t >= THUD + 0.1:  # the doors are shut: right palm flat on the right door, the left palm on the left door
        rest = ease((t - 3.0) / 0.5)
        hr = tuple(a * (1 - rest) + b * rest for a, b in zip(hand_on_door(0.0, 34.0, 0.6), (-4.0, 22.0, 4.0)))
    lh_push = ease((t - 2.1) / 0.4) * (1.0 - ease((t - 3.0) / 0.5))
    hl = tuple(a * (1 - lh_push) + b * lh_push for a, b in zip((3.0, 21.0, 4.5), (3.0, 34.0, STAND_G + 0.6)))
    if t >= 3.0:
        hl = tuple(a * (1 - ease((t - 3.0) / 0.5)) + b * ease((t - 3.0) / 0.5) for a, b in zip((3.0, 34.0, STAND_G + 0.6), (3.0, 21.0, 4.5)))
    step = ease((t - 3.05) / 0.4)
    legs = ((-0.14 * step, 0.04 + 0.2 * step), (0.06 * step, 0.04 + 0.06 * step))
    return Q(twist=twist, lean=lean, pz=1.0 + 3.0 * push, dy=breath * 0.3 - 0.8 * push, legs=legs, hand_l=hl, hand_r=hr, droop=0.0, shift=(0.0, 0.0, -2.0 * step))


def frames():
    em.SECTOR = 6  # north
    count = int(round(DURATION * FPS))
    return [em.render_frame(pose((i + 0.5) / FPS)) for i in range(count)], count


def main():
    frs, count = frames()
    W, H = hero.FW, hero.FH
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        cols = 10
        rows_n = (count + cols - 1) // cols
        k = 3
        out = [[(62, 125, 86, 255)] * (cols * W * k) for _ in range(rows_n * H * k)]
        for i, fr in enumerate(frs):
            ox, oy = (i % cols) * W * k, (i // cols) * H * k
            for y, row in enumerate(fr):
                for x, px in enumerate(row):
                    if px[3]:
                        for dy in range(k):
                            for dx in range(k):
                                out[oy + y * k + dy][ox + x * k + dx] = px
        write_png(Path(sys.argv[2]), cols * W * k, rows_n * H * k, out)
        return
    sheet = [[CLEAR] * (count * W) for _ in range(H)]
    for i, fr in enumerate(frs):
        for y in range(H):
            sheet[y][i * W:(i + 1) * W] = fr[y]
    write_png(ROOT / "characters" / "player_wardrobe.png", count * W, H, sheet)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["wardrobe"] = {"frames": count, "fps": FPS, "duration": DURATION, "thud": THUD, "stand": [STAND_X, STAND_G],
                       "door": [round(math.degrees(door_angle((i + 0.5) / FPS)), 1) for i in range(count)]}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("wardrobe sheet written,", count, "frames")


if __name__ == "__main__":
    main()
