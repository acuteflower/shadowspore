#!/usr/bin/env python3
"""The hallway in front of Ellie's room (data/interiors.json "flur"). The same cut stone as the room (tools/servant_floor.py, servant_wall.py) but tended: hardly any moss, no cracks, hardly any chips. A long
carpet in the dark blue of the fortress runs through the middle from wall to wall, unbroken: a border of dark blue with a thin gold line, a woven field with a chain of diamonds, a soft shadow on the stone.
The hallway lies right under the room (`adjacent`, its floor starts where the room's floor ends, under the lip of the front wall, so it is seen through the doorway and under the room's wall)
and is `veiled`: it lies under shadow smoke until somebody steps in (Interior.lift_veil). It is seven rooms long: five to the left of Ellie's room (the third of them is the opening of the corridor that leads up,
"flur_gang": a narrow room open to the hallway, as deep as a room, its own veil), one to the right. Above it stand `fake` rooms of her size (the same front wall and door as hers, the door shut for good,
the room behind it under smoke that never lifts): "flur_l4", "flur_l3", "flur_l2", "flur_l1", "flur_r1".
    python3 tools/art_hallway.py [preview.png]     writes assets/interior/flur/*.png, the room's entry in data/interiors.json and, with an argument, a 3x preview"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import servant_floor  # noqa: E402
import servant_wall  # noqa: E402
import art_hallway_props as things  # noqa: E402
import art_servant_room as room  # noqa: E402
import art_servant_rooms2 as rooms2  # noqa: E402
import art_saal as hall  # noqa: E402
from stone_wear import Wear  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "interior" / "flur"
DATA = ROOT / "data" / "interiors.json"
ROOM_W = 256  # a room's width
ROOMS = 7  # the hallway is as long as seven rooms
ELLIE = 5  # Ellie's room: the sixth from the left
ROOM_X = ELLIE * ROOM_W
GANG = 2  # the slot whose "door" is the opening of the corridor leading up
GANG_W = 128  # the corridor's rect: 16 px side walls and a floor of 96
GANG_BAND = 72  # the back wall at the corridor's end (cap 14 + face 58), the floor starts below it
SAAL_BOTTOM = -120  # the entrance hall's south edge in room px (above the row of the rooms)
GANG_OPEN0, GANG_OPEN_H = 76, 64  # the opening in the corridor's east wall into the hall's west aisle (corridor px)
GANG_Y = SAAL_BOTTOM - hall.H + hall.OPEN_Y0 - GANG_OPEN0  # the corridor's top edge in room px: its opening lies right beside the opening of the hall's west wall
GANG_H = 192 - GANG_Y  # it reaches from the hallway up to its end wall
GANG_FLOOR_H = GANG_H
GANG_X = GANG * ROOM_W + 192 - GANG_W // 2  # its left edge in hall px: the opening lies where a door would
W = ROOMS * ROOM_W
SIDE = 16
FLOOR_W, FLOOR_H = W - 2 * SIDE, 88  # the floor runs from the room's floor (y 192 in the room) 88 px down
LIFT = 22  # the side walls reach up this far over the front wall of the room (the lower wall lies over the upper one)
CAP, FACE = 14, 22  # the front wall like the room's: its lit top and its face
H = FLOOR_H + CAP + FACE
OFFSET = (-ROOM_X, 192)
CARPET_Y, CARPET_H = 38, 26  # the carpet's rows in the floor: the middle of what is seen (the first 14 rows lie under the room's wall)

TENDED = Wear(moss=0.12, moss_reach=1.0, moss_hang=0.0, cracks=0.0, chips=0.1, pocks=0.5, stains=0.2, wash=0.3, grime=0.7, wide_joints=0.4, polish=1.0, moss_spots=())

# the dark blue of the fortress (nothing to do with Valdric's order): dark to light, and its thin gold
WINE = [(8, 12, 30), (18, 28, 62), (30, 48, 98), (46, 72, 132)]
GOLD = [(88, 62, 30), (156, 120, 56), (214, 176, 96)]
INK = (6, 8, 20)


def hsh(x, y, seed):
    return ((x * 73856093 ^ y * 19349663 ^ seed * 83492791) % 1000) / 1000.0


def weave(w):
    """The woven carpet as a strip (CARPET_H rows, w columns, RGBA); the ends of a strip are cut at the same place, between two diamonds."""
    h = CARPET_H
    strip = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            u = (x + (28 - (w % 28)) // 2 + 14) % 28  # the pattern repeats every 28 px
            if y == 0 or y == h - 1:  # the outline
                col = INK
            elif y in (1, h - 2):  # the dark outer band, with a lit top edge
                col = WINE[0] if y == h - 2 else WINE[1]
            elif y in (2, h - 3):
                col = GOLD[1] if (x + y) % 2 == 0 else GOLD[0]  # the thin gold line, woven
            elif y in (3, 4, h - 5, h - 4):
                col = WINE[1] if (x + y) % 2 == 0 else WINE[2]
            else:  # the field: a chain of diamonds
                fy = y - (h // 2)
                d = abs(u - 14) + abs(fy) * 1.6
                if abs(d - 9.5) < 0.9:
                    col = GOLD[2] if (x + y) % 2 == 0 else GOLD[1]  # the diamond's gold line
                elif d < 8.6:
                    col = WINE[1] if (x + y) % 2 == 0 else WINE[0]  # inside it: dark
                    if abs(u - 14) + abs(fy) < 2.5:
                        col = GOLD[1] if (x + y) % 2 == 0 else GOLD[0]  # a small gold stud in the middle
                elif abs(u) % 28 in (0, 27) and abs(fy) < 3:  # between two diamonds a small cross-stitch
                    col = GOLD[1]
                else:
                    col = WINE[2] if (x + y) % 2 == 0 else WINE[3]
                    if hsh(x, y, 5) > 0.96:
                        col = WINE[1]  # a thread out of place
            if hsh(x, y, 9) > 0.985 and y not in (0, h - 1):
                col = tuple(min(255, c + 22) for c in col)  # worn threads
            strip[y, x, :3] = col
            strip[y, x, 3] = 255
    return strip


def carpet(floor, y0):
    """Lays the long carpet over the floor (in place) from wall to wall at row y0: its shadow first, then the woven cloth."""
    h, w = CARPET_H, floor.shape[1]
    for x in range(w):  # a soft shadow on the stone, below and a hair above
        for dy, k in ((h, 0.45), (h + 1, 0.22), (-1, 0.18)):
            floor[y0 + dy, x, :3] = (floor[y0 + dy, x, :3] * (1.0 - k)).astype(np.uint8)
    floor[y0:y0 + h, :, :] = weave(w)


def carpet_up(floor, x0, y_top, y_end):
    """The same carpet turned to run up the corridor from the long one (it ends at row y_end, the long carpet's top edge) to y_top, with a small fringe at its far end; its shadow falls to the right."""
    h = CARPET_H
    strip = np.rot90(weave(y_end - y_top)).copy()  # the lit edge of the weave is now on the left
    strip[0, :, :3] = INK
    strip[1, ::2, :3] = GOLD[1]
    for y in range(y_top, y_end):
        for dx, k in ((h, 0.45), (h + 1, 0.22), (-1, 0.18)):
            floor[y, x0 + dx, :3] = (floor[y, x0 + dx, :3] * (1.0 - k)).astype(np.uint8)
    floor[y_top:y_end, x0:x0 + h, :] = strip


BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
SHADE = np.array([22, 16, 40])  # the cool dark the shadows fall to
WALL_FOOT = 14  # the first row of the floor below the room's front wall (the wall covers the rows above it)
DOORS = [(i * ROOM_W + 152, i * ROOM_W + 200) for i in range(ROOMS) if i != GANG]  # the doorways in floor columns (the gap of a room's front wall, x 168..216, minus the side wall)


def shade_by(floor, x, y, amount):
    """Darkens one floor pixel by `amount` (0..1), in the three steps of a dither, so the shadow stays pixel art."""
    k = min(3, int(amount * 4.0 + BAYER[y % 4, x % 4]))
    floor[y, x, :3] = (floor[y, x, :3] * (1.0 - 0.2 * k) + SHADE * 0.2 * k).astype(np.uint8)


def transitions(floor):
    """The places where the floor meets something: the room's wall (its foot lies in shadow, the doorway is a worn threshold slab, so the room's floor and this one do not just butt together) and the
    left wall (the light comes from the top left, so the wall on that side throws its shadow across the floor)."""
    h, w = floor.shape[:2]
    pal = servant_wall.PAL
    for d0, d1 in DOORS:  # the threshold: one long slab through the wall, lit on its top and left, dark at its foot
        for y in range(0, WALL_FOOT):
            for x in range(d0, d1):
                k = 3 + int(BAYER[y % 4, x % 4] * 1.4) - (1 if hsh(x, y, 3) > 0.9 else 0)
                floor[y, x, :3] = pal[max(2, min(4, k))]
        floor[0:WALL_FOOT, d0:d0 + 1, :3] = pal[5]
        floor[WALL_FOOT - 1, d0:d1, :3] = pal[1]
        floor[0:WALL_FOOT, d1 - 1, :3] = pal[2]
    for x in range(w):  # the foot of the wall (none where the corridor opens: the floor runs on)
        if GANG_X + 16 - SIDE <= x < GANG_X + GANG_W - 16 - SIDE:
            continue
        door = any(d0 - 2 <= x < d1 + 2 for d0, d1 in DOORS)
        for r in range(WALL_FOOT, WALL_FOOT + 20):
            f = (1.0 - (r - WALL_FOOT) / 20.0) ** 1.6 * (0.55 if door else 0.95)
            shade_by(floor, x, r, f)
    for r in range(12):  # the hallway's own south wall: its foot lies in shadow too (the wall's top edge has a dark line)
        for x in range(w):
            shade_by(floor, x, h - 1 - r, (1.0 - r / 12.0) ** 1.5 * 0.85)
    for y in range(h):  # the left wall's shadow
        for x in range(0, 9):
            shade_by(floor, x, y, (1.0 - x / 9.0) ** 1.5 * 0.7)


def gang_transitions(floor):
    """The corridor's floor: the back wall's foot and the left wall throw their shadows."""
    h, w = floor.shape[:2]
    for r in range(14):  # the foot of the back wall
        for x in range(w):
            shade_by(floor, x, GANG_BAND + r, (1.0 - r / 14.0) ** 1.6 * 0.85)
    for y in range(h):
        for x in range(0, 9):
            shade_by(floor, x, y, (1.0 - x / 9.0) ** 1.5 * 0.7)


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    # one floor of stones for the hallway and the corridor above it (so the joints run on across their seam), cut into the two pictures afterwards
    big = servant_floor.floor_img(FLOOR_W, GANG_FLOOR_H + FLOOR_H + 6, seed=23, paths=(), damp=(), stains=(), wear=TENDED)[:GANG_FLOOR_H + FLOOR_H]
    cx0 = GANG_X + 16 - SIDE  # the corridor's floor in floor columns
    cx1 = cx0 + GANG_W - 32
    carpet_up(big, (cx0 + cx1) // 2 - CARPET_H // 2, GANG_BAND + 8, GANG_FLOOR_H + CARPET_Y)  # up the middle to the end wall
    floor = big[GANG_FLOOR_H:].copy()
    carpet(floor, CARPET_Y)
    transitions(floor)
    Image.fromarray(floor).save(OUT / "floor.png")
    gang = big[:GANG_FLOOR_H, cx0:cx1].copy()
    gang_transitions(gang)
    Image.fromarray(gang).save(OUT / "gang_floor.png")
    Image.fromarray(servant_wall.back_wall_img(GANG_W, 14, 58, 4, seed=29, wear=TENDED)).save(OUT / "gang_wall.png")  # the end wall
    o0, o1 = GANG_OPEN0, GANG_OPEN0 + GANG_OPEN_H  # the opening in the east wall: two strips of floor through the 32 px of wall (this corridor's and the hall's)
    Image.fromarray(big[o0:o1, cx1:cx1 + 16].copy()).save(OUT / "gang_gap.png")
    Image.fromarray(big[o0:o1, cx1 + 16:cx1 + 32].copy()).save(OUT / "saal_gap.png")
    hall.make()  # the entrance hall behind the arch (tools/art_saal.py)
    for name, left in (("side_l.png", True), ("side_r.png", False)):
        side = servant_wall.side_img(left, H + LIFT, SIDE, seed=35, wear=TENDED)
        side[0:2, :, :3] = servant_wall.PAL[0]  # where it comes out over the room's wall: a joint
        Image.fromarray(side).save(OUT / name)
        gside = servant_wall.side_img(left, GANG_FLOOR_H + 6, SIDE, seed=35, wear=TENDED)
        if not left:
            hall.cut_gap(gside, GANG_OPEN0, GANG_OPEN_H)
        Image.fromarray(gside).save(OUT / ("gang_" + name))
    front = servant_wall.front_img(W, CAP, FACE, gap=(W - 3, W - 2), seed=47, wear=TENDED)
    front[:, W - 3:, :] = front[:, W - 5:W - 4, :]  # no doorway: the gap the generator wants is filled with the stone beside it
    Image.fromarray(front).save(OUT / "front.png")
    lip = servant_wall.front_img(ROOM_W, room.TOP_PAD, room.LIP_H - room.TOP_PAD, (GANG_X + 16 - GANG * ROOM_W, GANG_X + GANG_W - 16 - GANG * ROOM_W), wear=room.WALL_WEAR)  # the wall of the rooms, with the wide opening
    Image.fromarray(lip).save(OUT / "front_gang.png")
    gap = [ROOM_X + 168, ROOM_X + 216]  # the doorway of Ellie's room, in hall px
    spec = {
        "title": "Flur",
        "dir": "res://assets/interior/flur/",
        "size": [W, H],
        "adjacent": {"to": "personalraum", "offset": list(OFFSET)},
        "joins": ["flur_gang", "flur_saal"],  # the corridor and the entrance hall share the view with the hallway
        "backdrop": False,
        "veiled": True,
        "veil_z": 1,
        "veil_top": LIFT,  # the smoke also lies over the front walls of the rooms above (their doors show only once the hallway is open) ...
        "veil_cut": {"y": 14, "gap": gap, "x": [ROOM_X, ROOM_X + ROOM_W], "soft": 14},  # ... except Ellie's own wall and door
        "veil_eyes": [[120, 70], [620, 40], [1000, 64], [1560, 50]],
        "ambient": {"day": "#dcd6e8", "night": "#4c4870"},
        "entry": [ROOM_X + 128, 40],
        "start": [ROOM_X + 128, 40],
        "shell": [
            {"tex": "floor.png", "pos": [SIDE, 0], "z": -6},
            {"tex": "side_l.png", "pos": [0, -LIFT], "sorted": True},
            {"tex": "side_r.png", "pos": [W - SIDE, -LIFT], "sorted": True},
        ],
        "front": {"tex": "front.png", "pos": [0, FLOOR_H]},
        "walls": [[0, 0, SIDE + 8, H], [W - SIDE - 8, 0, SIDE + 8, H], [0, FLOOR_H + 10, W, H - FLOOR_H - 10]],
    }
    info = things.make()
    spec["props"], spec["lights"] = furnish(info)
    table = {k: v for k, v in json.loads(DATA.read_text()).items() if not k.startswith("flur")}
    eyes = {"flur_l4": [[70, 60], [190, 112]], "flur_l3": [[150, 44], [60, 100]], "flur_l2": [[70, 60], [190, 112]], "flur_l1": [[120, 36], [200, 92]], "flur_r1": [[58, 104], [168, 54]]}
    real = rooms2.make_rooms()  # two of them are real rooms (tools/art_servant_rooms2.py): flur_l3 and flur_l1
    for slot, key in ((0, "flur_l4"), (1, "flur_l3"), (3, "flur_l2"), (4, "flur_l1"), (6, "flur_r1")):
        table[key] = real[key] if key in real else fake_room((slot - ELLIE) * ROOM_W, eyes[key], SOFT)  # they hang on Ellie's room and are built BEFORE the hallway, so the hallway's things are drawn over their walls
    table["personalraum"]["smoke_backdrop"] = True  # the free space round the rooms in the veil's smoke
    table["flur_gang"] = gang_room(info)
    table["flur_saal"] = saal_room(info)
    table["flur"] = spec
    DATA.write_text(json.dumps(table, indent=1, ensure_ascii=False))
    return spec


def gang_room(info):
    """The corridor that leads up from the hallway, where the third room's door would be: 96 px of floor between two side walls, the carpet running up its middle to a back wall with a flag between two torches.
    Its east wall is the west wall of the entrance hall's aisle; the corridor ends in a doorway in it (the opening, where the carpet side of the hall begins). It is veiled like the hallway (its own smoke,
    lifted when somebody steps in) and shares the view with it."""
    inner = GANG_W // 2
    lip_y = 170 - GANG_Y  # the lip of the rooms' wall, in the corridor's own px
    torch = {"color": "#ffb25e", "radius": 120, "energy": 0.9}
    o0, o1 = GANG_OPEN0, GANG_OPEN0 + GANG_OPEN_H
    return {
        "title": "Gang",
        "dir": "res://assets/interior/flur/",
        "size": [GANG_W, GANG_H],
        "adjacent": {"to": "personalraum", "offset": [GANG_X - ROOM_X, GANG_Y]},
        "backdrop": False,
        "veiled": True,
        "veil_z": 1,
        "veil_soft": [0, 0, 0, 30],  # at its mouth, where it meets the hallway, the smoke thins out ragged
        "veil_eyes": [[34, 190], [92, 330]],
        "ambient": {"day": "#dcd6e8", "night": "#4c4870"},
        "entry": [inner, GANG_H - 20],
        "start": [inner, GANG_H - 20],
        "shell": [
            {"tex": "gang_floor.png", "pos": [16, 0], "z": -6},
            {"tex": "gang_gap.png", "pos": [GANG_W - SIDE, o0], "z": -6},
            {"tex": "gang_wall.png", "pos": [0, 0], "z": -5},
            {"tex": "gang_side_l.png", "pos": [0, 0], "z": -5},
            {"tex": "gang_side_r.png", "pos": [GANG_W - SIDE, 0], "z": -5},
        ],
        "front": [{"tex": "front_gang.png", "pos": [GANG * ROOM_W - GANG_X, lip_y]}],  # the wall of the rooms beside the opening
        "props": [
            {"id": "flag0", "tex": "flag.png", "pos": [inner, GANG_BAND + 0.4], "feet": info["flag"]},
            {"id": "torch0", "tex": "torch.png", "glow": "torch_glow.png", "pos": [inner - 34, GANG_BAND + 0.4], "feet": info["torch"], "light": torch},
            {"id": "torch1", "tex": "torch.png", "glow": "torch_glow.png", "pos": [inner + 34, GANG_BAND + 0.4], "feet": info["torch"], "light": torch},
        ],
        "walls": [[0, 0, GANG_W, GANG_BAND + 4], [0, GANG_BAND, 24, GANG_H - GANG_BAND], [GANG_W - 24, GANG_BAND, 24, o0 - GANG_BAND], [GANG_W - 24, o1, 24, GANG_H - o1],
                  [GANG * ROOM_W - GANG_X, lip_y + 10, GANG_X + 16 - GANG * ROOM_W, 30], [GANG_W - 16, lip_y + 10, GANG * ROOM_W + ROOM_W - GANG_X - GANG_W + 16, 30]],  # the wall of the rooms beside the opening
    }


def saal_room(info):
    """The entrance hall (tools/art_saal.py has the layout): its west wall lies right beside the corridor's east wall, and the corridor comes in from the SIDE through an opening in the two walls (the corridor runs up along the hall); a floor of stone with a runner in each aisle,
    pillars between the aisles and the nave, the nave ending in a broad flight of steps she can climb to a second level (a plain platform), the big carpet running up to it, a locked door at the end of each aisle, torches and flags. Veiled like the rest."""
    s = hall
    flag, torch = info["flag"], info["torch"]
    light = {"color": "#ffb25e", "radius": 150, "energy": 0.95}
    props = []
    for row, cx in (("w", s.X_NAVE0 - 16), ("e", s.X_NAVE1 + 16)):
        for i, y in enumerate(s.PILLAR_Y):
            props.append({"id": "pillar_%s%d" % (row, i), "tex": "saal_pillar.png", "pos": [cx, y], "feet": 354, "solid": [34, 14, -17, -14], "fades": True})
    for i, cx in enumerate((s.X_WEST_C, s.X_EAST_C)):  # a torch each side of the locked doors
        for j, dx in enumerate((-34, 34)):
            props.append({"id": "torch_%d%d" % (i, j), "tex": "torch.png", "glow": "torch_glow.png", "pos": [cx + dx, s.BASE + 0.4], "feet": torch, "light": light})
    for i, dx in enumerate((-72, 0, 72)):  # flags on the north wall above the platform
        props.append({"id": "flag_%d" % i, "tex": "flag.png", "pos": [s.X_MID + dx, s.BASE + 0.4], "feet": flag})
    for i, dx in enumerate((-150, 150)):  # and a torch on either side of the steps' top
        props.append({"id": "torch_s%d" % i, "tex": "torch.png", "glow": "torch_glow.png", "pos": [s.X_MID + dx, s.BASE + 0.4], "feet": torch, "light": light})
    doors = [{"id": "door_%s" % k, "tex": "saal_door.png", "leaf": [cx - 28, s.BASE - 52], "pos": [cx, s.BASE + 14], "sorted": True, "locked_text": "Die Tür ist wohl verschlossen."}
             for k, cx in (("w", s.X_WEST_C), ("e", s.X_EAST_C))]
    return {
        "title": "Eingangssaal",
        "dir": "res://assets/interior/flur/",
        "size": [s.W, s.H],
        "adjacent": {"to": "personalraum", "offset": [GANG_X - ROOM_X + GANG_W, SAAL_BOTTOM - s.H]},  # its west wall lies right beside the corridor's east wall
        "backdrop": False,
        "veiled": True,
        "veil_z": 1,
        "veil_height": s.H + s.WALL,  # the smoke also lies over the south wall, which hangs below the hall's rect
        "veil_eyes": [[60, 220], [350, 140], [640, 380], [350, 640]],
        "ambient": {"day": "#dcd6e8", "night": "#4c4870"},
        "entry": [s.X_WEST_C, s.H - 30],
        "start": [s.X_WEST_C, s.H - 30],
        "shell": [
            {"tex": "saal_floor.png", "pos": [s.SIDE, s.BASE], "z": -6},
            {"tex": "saal_gap.png", "pos": [0, s.OPEN_Y0], "z": -6},
            {"tex": "saal_wall_n.png", "pos": [0, 0], "z": -5},
            {"tex": "saal_platform.png", "pos": [s.X_NAVE0 - 16, s.BASE], "z": -6},  # the second level at the top of the steps
            {"tex": "saal_platform_wall.png", "pos": [s.X_NAVE0 - 32, s.BASE], "z": -5},
            {"tex": "saal_platform_wall.png", "pos": [s.X_NAVE1 + 16, s.BASE], "z": -5},
            {"tex": "saal_riser.png", "pos": [s.X_NAVE0 - 16, s.WALL_FOOT], "z": -6},  # the platform's front edge beside the steps
            {"tex": "saal_riser.png", "pos": [s.X_MID + s.STAIRS_W // 2, s.WALL_FOOT], "z": -6},
            {"tex": "saal_stairs.png", "pos": [s.X_MID - s.STAIRS_W // 2, s.WALL_FOOT], "z": -6},
            {"tex": "saal_side_l.png", "pos": [0, 0], "z": -5},
            {"tex": "saal_side_r.png", "pos": [s.W - s.SIDE, 0], "z": -5},
        ],
        "front": [{"tex": "saal_wall_s.png", "pos": [0, s.H]}],  # the south wall (hangs below the hall's rect, under its smoke)
        "doors": doors,
        "props": props,
        "walls": [[0, 40, s.W, 36], [0, 40, s.SIDE, s.OPEN_Y0 - 40], [0, s.OPEN_Y0 + s.OPEN_H, s.SIDE, s.H - s.OPEN_Y0 - s.OPEN_H + 32], [s.W - s.SIDE, 40, s.SIDE, s.H], [s.X_NAVE0 - 32, 76, 16, s.WALL_FOOT - 76 + 24], [s.X_NAVE1 + 16, 76, 16, s.WALL_FOOT - 76 + 24], [s.X_NAVE0 - 16, s.WALL_FOOT, 56, 24], [s.X_MID + s.STAIRS_W // 2, s.WALL_FOOT, 56, 24], [0, s.H, s.W, 32]],  # the platform's side walls and the risers beside the steps stop her; the steps themselves are open
    }


WALL_FOOT_Y = 14.4  # the foot of the rooms' front wall in hall px (the wall sorts by it; what hangs on it sorts just behind the people)
DOOR_XS = [i * ROOM_W + 192 for i in range(ROOMS)]  # the middle of every door
TORCH_XS = [(DOOR_XS[i] + DOOR_XS[i + 1]) // 2 for i in range(ROOMS - 1)]  # a light between every two doors ...
FLAG_XS = sorted([(DOOR_XS[i] + TORCH_XS[i]) // 2 for i in range(ROOMS - 1)] + [(TORCH_XS[i] + DOOR_XS[i + 1]) // 2 for i in range(ROOMS - 1)])  # ... and a flag half way between a light and a door


def furnish(info):
    """The props of the hallway: wall things (torches, flags) stand on the wall's foot, benches under the torches, a jar at each end."""
    props, lights = [], []
    for i, x in enumerate(TORCH_XS):
        props.append({"id": "torch%d" % i, "tex": "torch.png", "glow": "torch_glow.png", "pos": [x, WALL_FOOT_Y], "feet": info["torch"],
                      "light": {"color": "#ffb25e", "radius": 150, "energy": 0.95}})
        bench_h, bench_feet = info["bench"]
        props.append({"id": "bench%d" % i, "tex": "bench.png", "pos": [x, 86], "feet": bench_feet, "solid": [50, 8, -25, -8],
                      "seats": [[-13, -6, 6, 0, -14], [13, -6, 6, 0, -14]]})  # two places, facing north (E sits her down, RestComponent)
    for i, x in enumerate(FLAG_XS):
        props.append({"id": "flag%d" % i, "tex": "flag.png", "pos": [x, WALL_FOOT_Y], "feet": info["flag"]})
    jar_h, jar_feet = info["jar"]
    for i, x in enumerate((50, W - 50)):
        props.append({"id": "jar%d" % i, "tex": "jar.png", "pos": [x, 40], "feet": jar_feet, "solid": [12, 6, -6, -5]})
    return props, lights


SOFT = [0, 0, 0, 16]  # veil_soft of the rooms: the smoke thins out ragged above the wall of the hallway (not at the sides, where the next veil begins)


def fake_room(x, eyes, soft):
    """A room of Ellie's size above the hallway that cannot be entered: the front wall and the door are hers (assets/interior/personalraum), the door is locked for good (E rattles it and Ellie says it is locked,
    its blocker stays), the room behind lies under shadow smoke that never lifts (`fake`, `veil_height`: the smoke stops above the wall). Its rect ends where the hallway begins."""
    return {
        "title": "Zimmer",
        "dir": "res://assets/interior/personalraum/",
        "size": [ROOM_W, OFFSET[1]],
        "adjacent": {"to": "personalraum", "offset": [x, 0]},
        "backdrop": False,
        "veiled": True,
        "fake": True,
        "veil_z": 1,
        "veil_height": 170,
        "veil_soft": soft,
        "veil_eyes": eyes,
        "ambient": {"day": "#dcd6e8", "night": "#4c4870"},
        "entry": [192, 158],
        "shell": [],
        "front_y": 170,
        "exit_door": {"id": "door", "pos": [192, 192], "leaf": [168, 170], "opens": True, "locked_text": "Die Tür ist wohl verschlossen.", "solid": [168, 174, 48, 32]},  # E rattles it and she says so (Doorway.locked_text)
        "walls": [[0, 180, 168, 30], [216, 180, 40, 30]],
    }


def preview(path):
    canvas = Image.new("RGBA", (W, H), (10, 6, 16, 255))
    canvas.alpha_composite(Image.open(OUT / "floor.png").convert("RGBA"), (SIDE, 0))
    canvas.alpha_composite(Image.open(OUT / "side_l.png").convert("RGBA"), (0, -LIFT))
    canvas.alpha_composite(Image.open(OUT / "side_r.png").convert("RGBA"), (W - SIDE, -LIFT))
    canvas.alpha_composite(Image.open(OUT / "front.png").convert("RGBA"), (0, FLOOR_H))
    canvas.resize((W * 4, H * 4), Image.NEAREST).save(path)


if __name__ == "__main__":
    spec = build()
    print("wrote", OUT, spec["size"])
    if len(sys.argv) > 1:
        preview(Path(sys.argv[1]))
