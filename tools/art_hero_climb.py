"""Bake Ellie climbing a rim or a full rock face, with world-space hand and boot contacts."""
import json

import numpy as np

import art_hero3d as hero
from art_hero_emerge import timeline
from art_hero_rebuild import write_array
from art_hero_sit import render_atlas
from gen_art import ROOT

hero.FW, hero.FH, hero.GROUND_ROW = 60, 68, 63.0
FRAMES = 32

# Body travel in model units (height, forward). The pauses leave time to
# transfer her weight and move a hand or boot before the next pull.
RIM = [(0, (0, 0)), (.18, (0, 3)), (.28, (0, 3)), (.43, (6, 4)), (.52, (6, 4)),
       (.68, (12, 6)), (.80, (15, 11)), (.92, (15, 18)), (1, (15, 20))]
FACE = [(0, (0, 0)), (.18, (0, 3)), (.28, (0, 3)), (.43, (11, 4)), (.52, (11, 4)),
        (.68, (23, 6)), (.80, (36, 13)), (.92, (42, 25)), (1, (42, 32))]

# Local pelvis compression, chest lean and turn, hair lag and coat flare.
BODY = [(0, (0, 0, 0, 0, 0)), (.14, (-2.4, .21, -.08, .2, .01)),
        (.27, (-.6, .12, -.13, .5, .04)), (.43, (-1.7, .24, .08, 1.35, .10)),
        (.52, (-3.0, .21, -.11, .75, .08)), (.67, (-6.0, .53, -.09, 1.5, .14)),
        (.80, (-11, .86, .09, 2.1, .20)), (.90, (-6, .48, .05, 1.0, .10)),
        (1, (0, 0, 0, 0, 0))]


def sample(keys, t):
    return np.asarray(timeline(keys, t), dtype=float)


def render_pose(t, tall):
    up, forward = sample(FACE if tall else RIM, t)
    root = np.array((0.0, up, forward))
    drop, lean, twist, hair, flare = sample(BODY, t)

    # The first hold stays still as her torso rises. The right hand finds a
    # second hold while the left takes the load, then she leans over the lip.
    right_hold = (-8.0, 43.5, 10)
    left_hold = (7.3, 39.5, 11)
    right_lip = (-6.2, 49 if tall else 39, 12)
    left_lip = (6.2, 47 if tall else 38, 13)
    left = sample([(0, (5.6, 26.2, 2.1)), (.14, (6.3, 33, 7)), (.26, left_hold),
                   (.52, left_hold), (.57, (8.4, 43 if tall else 39, 8)),
                   (.63, left_lip), (.77, left_lip)], t)
    right = sample([(0, (-5.6, 26.2, 2.5)), (.09, (-6, 35, 6)), (.19, right_hold),
                    (.42, right_hold), (.47, (-8.4, 45 if tall else 41, 6.5)),
                    (.52, right_lip), (.78, right_lip)], t)
    let_go = float(timeline([(.77, 0.0), (.94, 1.0)], t))
    left = (left - root) * (1.0 - let_go) + np.array((5.6, 26.2, 2.1)) * let_go
    right = (right - root) * (1.0 - let_go) + np.array((-5.6, 26.2, 2.5)) * let_go

    # Each ankle stays at its own foothold while the other one advances.
    # After clearing the edge she steps up onto the plateau one foot at a time.
    high = 42.0 if tall else 15.0
    end = 32.0 if tall else 20.0
    left_step = (4.3, 15 if tall else 8, 8.0)
    right_step = (-4.4, 24 if tall else 12, 8.5)
    left_top = (3.3, high + 2.7, 15.0)
    right_top = (-3.0, high + 2.7, end + .6)
    foot_l = sample([(0, (2.5, 2.7, 0.0)), (.20, (2.5, 2.7, 0.0)),
                     (.29, left_step), (.59, left_step), (.70, (4.0, high + 5, 9.0)),
                     (.79, left_top), (.90, left_top), (.95, (3.1, high + 5.7, end - 5)),
                     (1, (2.6, high + 2.7, end))], t)
    foot_r = sample([(0, (-2.5, 2.7, 0.0)), (.37, (-2.5, 2.7, 0.0)),
                     (.51, right_step), (.70, right_step), (.82, (-4.0, high + 6, 13)),
                     (.89, right_top)], t)

    pose = hero.P(twist, lean, 0.0, (), right, left, (-twist * 2, -.25 * hair, -hair), flare)
    pose.update(both_arms=True, dy=drop, ankles=(foot_l - root, foot_r - root),
                pole_l=(1, -.35, -.5), pole_r=(-1, -.35, -.5), curl=hair * .13)
    return pose, [round(forward * hero.SCALE, 3), round(up * hero.SCALE * hero.COSP, 3)]


if __name__ == "__main__":
    clips = [[render_pose(i / (FRAMES - 1), tall) for i in range(FRAMES)] for tall in (False, True)]
    sheet, blood = render_atlas([pose for clip in clips for pose, _ in clip])
    for col in range(2 * FRAMES):
        i = col % FRAMES
        alpha = sheet[:, col * hero.FW:(col + 1) * hero.FW, 3]
        alpha[alpha == 70] = round(70 * max(0.0, 1.0 - i / 5, 1.0 - (FRAMES - 1 - i) / 5))
    write_array(ROOT / "characters" / "player_climb.png", sheet)
    write_array(ROOT / "characters" / "player_climb_blood.png", blood)
    motion = {"pitch_sine": round(hero.SINP, 5), "clips": [[move for _, move in clip] for clip in clips]}
    (ROOT.parent / "data" / "wall_climb.json").write_text(json.dumps(motion, separators=(",", ":")) + "\n")
