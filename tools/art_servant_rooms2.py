#!/usr/bin/env python3
"""Two more servants' rooms next to Ellie's, along the hallway (data/interiors.json "flur_l1", left of hers, and "flur_l3", left of the corridor leading up). Their doors can be opened (E) and they lie under
shadow smoke until somebody steps in. The furniture is Ellie's (assets/interior/personalraum: the interior's `dir` stays there, so the bed, nightstand, wardrobe, mounts, boots and bucket are the same pictures)
put differently, plus a table, a stool and a plain shelf (tools/servant_furniture2.py); their floor and wall are made again with other seeds and the window in another place, no crow on the sill, no broom to take.
Called by tools/art_hallway.py, which writes them into the JSON before the hallway (the hallway's things must be drawn over their walls).
    python3 tools/art_servant_rooms2.py     writes assets/interior/flur_zimmer/*.png only"""
import copy
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_servant_room as room  # noqa: E402
import servant_floor  # noqa: E402
import servant_furniture as furn  # noqa: E402
import servant_furniture2 as furn2  # noqa: E402
import servant_wall  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "interior" / "flur_zimmer"
RES = "res://assets/interior/flur_zimmer/"
DATA = ROOT / "data" / "interiors.json"


def save(name, arr):
    Image.fromarray(arr).save(OUT / name)


def textures(tag, seed, window, damp, stains, paths):
    floor = servant_floor.floor_img(272, 160, seed=seed, paths=paths, damp=damp, stains=stains, wear=room.FLOOR_WEAR)[:room.FLOOR_H, 24:24 + room.FLOOR_W].copy()
    room.foot_shadow(floor, room.FRONT_Y - room.FLOOR_Y)
    save("floor_%s.png" % tag, floor)
    save("wall_%s.png" % tag, servant_wall.back_wall_img(room.SHELL_W, room.TOP_PAD, room.WALL_H, 4, seed=seed + 10, wear=room.WALL_WEAR, window=window))
    save("sky_%s.png" % tag, servant_wall.sky_img(window[2], window[3], seed=seed + 60))


def things():
    """The new pictures; returns their feet rows."""
    table, tf = furn2.table_arr()
    save("table.png", table)
    stool, sf = furn2.stool_arr()
    save("stool.png", stool)
    shelf, shf = furn2.shelf2_arr()
    save("shelf2.png", shelf)
    return {"table": (table.shape[0], tf), "stool": (stool.shape[0], sf), "shelf2": (shelf.shape[0], shf)}


def make_rooms():
    OUT.mkdir(parents=True, exist_ok=True)
    info = things()
    base = json.loads(DATA.read_text())["personalraum"]
    ellie = {p["id"]: p for p in base["props"]}

    def ours(pid, pos, **extra):
        p = copy.deepcopy(ellie[pid])
        p.pop("pickup", None)  # nothing to take here
        p["pos"] = list(pos)
        p.update(extra)
        return p

    def mount(tool, x):  # the three layers of a tool on its mount, same pictures, same sorting rows
        return [ours(tool + "_mount", (x, 67)), ours(tool, (x, 68)), ours(tool + "_clips", (x, 69))]

    def new(pid, tex, pos, feet, **extra):
        return {"id": pid, "tex": RES + tex, "pos": list(pos), "feet": feet, **extra}

    rooms = {}
    # ---- A: left of Ellie's. Her room the other way round: the bed on the right, the wardrobe on the left, the window further right; a table with a stool instead of the tools and the picture shelf.
    window = (150, 26, 26, 26)
    textures("a", 31, window, ((14, 150, 22),), ((40, 120, 17, 9),), [[(200, 100), (140, 60)]])
    props = [ours("wardrobe", (44, 92)), new("shelf2", "shelf2.png", (112, 57), info["shelf2"][1]), ours("bed", (218, 136)), ours("nightstand", (190, 96)),
             new("table", "table.png", (118, 134), info["table"][1], solid=[26, 12, -13, -10]), new("stool", "stool.png", (90, 146), info["stool"][1], solid=[10, 6, -5, -4]),
             ours("boots", (192, 152)), ours("bucket", (26, 152))]
    rooms["flur_l1"] = (window, "a", props, [{"tex": RES + "rug_a.png", "pos": [90, 120], "z": -4}], [{"pos": [188, 78], "color": "#ffb468", "radius": 110, "squash": 0.8, "energy": 1.0, "flicker": 0.22}],
                        [[60, 40], [200, 104]], -256)
    save("rug_a.png", furn.rug_arr(seed=83))
    # ---- B: left of the corridor. Less in it: a bed, a nightstand, a stool, a bucket and the broom on its mount (one nobody needs to take).
    window = (58, 26, 26, 26)
    textures("b", 53, window, ((250, 22, 30),), ((60, 130, 15, 8),), [[(200, 100), (170, 60)]])
    props = ours_list = [ours("bed", (150, 136)), ours("nightstand", (176, 96)), new("stool", "stool.png", (70, 128), info["stool"][1], solid=[10, 6, -5, -4]),
                         ours("bucket", (34, 152))] + mount("broom", 214)
    rooms["flur_l3"] = (window, "b", props, [], [{"pos": [174, 78], "color": "#ffb468", "radius": 110, "squash": 0.8, "energy": 1.0, "flicker": 0.22}], [[110, 50], [40, 130]], -1024)

    out = {}
    for key, (window, tag, props, decals, lights, eyes, offset) in rooms.items():
        spec = copy.deepcopy(base)
        for k in ("crows", "props", "decals", "lights", "shell", "start"):
            spec.pop(k, None)
        spec["title"] = "Zimmer"
        spec["adjacent"] = {"to": "personalraum", "offset": [offset, 0]}
        spec["joins"] = ["flur"]  # the same view as the hallway
        spec["backdrop"] = False
        spec["veiled"] = True
        spec["veil_z"] = 1
        spec["veil_height"] = 170  # the smoke stops above the wall and the door
        spec["veil_eyes"] = eyes
        spec["veil_soft"] = [0, 0, 0, 16]  # the smoke thins out ragged above the wall of the hallway (art_hallway.SOFT)
        spec["exit_door"] = {"id": "door", "pos": [192, 192], "leaf": [168, 170], "opens": True, "solid": [168, 174, 48, 32]}  # opens with E, nothing needed
        spec["shell"] = [
            {"tex": RES + "floor_%s.png" % tag, "pos": [room.SIDE_W, room.FLOOR_Y], "z": -6},
            {"tex": RES + "sky_%s.png" % tag, "pos": [window[0], window[1]], "z": -7},
            {"tex": RES + "wall_%s.png" % tag, "pos": [0, 0], "z": -5},
            {"tex": "side_l.png", "pos": [0, 0], "z": -5},
            {"tex": "side_r.png", "pos": [room.ROOM_W - room.SIDE_W, 0], "z": -5},
        ]
        spec["props"] = props
        spec["decals"] = decals
        spec["lights"] = lights
        out[key] = spec
    return out


if __name__ == "__main__":
    make_rooms()
    print("wrote", OUT)
