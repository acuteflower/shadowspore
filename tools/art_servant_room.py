#!/usr/bin/env python3
"""Ellie's room (the servants' quarter: data/interiors.json "personalraum", src/world/interiors.gd). Needs numpy and Pillow.
Stage 1: only the shell, floor (tools/servant_floor.py) and walls (tools/servant_wall.py), both in the world's stone ramp and built the same way. No furniture yet.

    python3 tools/art_servant_room.py [preview.png]     writes assets/interior/personalraum/*.png, the room's entry in data/interiors.json and, with an argument, a 3x preview.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import servant_floor  # noqa: E402
import servant_furniture as furn  # noqa: E402
import servant_wall  # noqa: E402
from stone_wear import PRESETS, Wear, parse  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent / "assets"
OUT = ROOT / "interior" / "personalraum"
DATA = ROOT.parent / "data" / "interiors.json"

FLOOR_W, FLOOR_H = 272, 160
SIDE_W, WALL_H, TOP_PAD, LIP_H = 16, 58, 14, 36
SHELL_W = FLOOR_W + 2 * SIDE_W
BACK_Y = TOP_PAD + WALL_H
FLOOR_Y = BACK_Y
FRONT_Y = FLOOR_Y + FLOOR_H - 22
ROOM_W, ROOM_H = SHELL_W, FRONT_Y + LIP_H + 6
DOOR_GAP = (208, 256)
WINDOW = (119, 26, 26, 26)  # x, y, w, h of the opening in the back wall: small, a little left of the middle (the room is 304 wide)
PERCH = (WINDOW[0] + WINDOW[2] // 2, WINDOW[1] + WINDOW[3] + 2)  # feet of the crow on the sill's top

# How worn the room is (tools/stone_wear.py: every knob 1.0 = the plain look, 0 = off). The walls carry the greenery in their joints; the floor, approved as it is, keeps its stones exactly and only gets more moss.
FLOOR_WEAR = Wear(moss=2.0, moss_hang=0.0)
WALL_WEAR = Wear(moss=2.6, moss_reach=1.2, moss_hang=1.0, chips=0.0)


def save(name, arr):
    Image.fromarray(arr).save(OUT / name)


def furnish(spec):
    """The furniture: pictures from tools/servant_furniture.py, their places in room px (a prop stands with its feet row on `pos`, so it sorts with the people), colliders, glow sheets and lights."""
    props, decals = [], []

    def put(pid, name, arr, feet, pos, solid=None, glow=False, sort=0):
        # `sort` moves the sort row (pos y) without moving the picture: pictures that lie on each other (a wall mount's board, tool and clips) keep their pixels and only differ in who is drawn first
        save(name, arr)
        prop = {"id": pid, "tex": name, "pos": [pos[0], pos[1] + sort], "feet": feet + sort}
        if solid:
            prop["solid"] = solid
        if glow:
            gname = name.replace(".png", "_glow.png")
            save(gname, hut_glow(arr))
            prop["glow"] = gname
        props.append(prop)

    wall_y = BACK_Y - 4  # where the foot of a wall mount stands: just above the contact shadow of the wall
    for tool, x, parts in (("broom", 70, furn.broom_mount() + (furn.broom_tool(),)), ("rake", 98, furn.rake_mount() + (furn.rake_tool(),))):
        if tool == "broom":
            back, clips, body = parts
        else:
            back, clips, body = parts[0], parts[1], parts[2]
        put(tool + "_mount", tool + "_mount.png", back, furn.MOUNT_G, (x, wall_y), sort=-1)
        put(tool, tool + ".png", body, furn.MOUNT_G, (x, wall_y))
        put(tool + "_clips", tool + "_clips.png", clips, furn.MOUNT_G, (x, wall_y), sort=1)
    shelf = furn.paint_picture(furn.shelf_arr(), 5, 10, 12, 13)
    put("shelf", "shelf.png", shelf, 32, (186, 57))
    bed, feet = furn.bed_arr()
    put("bed", "bed.png", bed, feet, (62, 128), solid=[70, 12, -35, -10])
    night, feet = furn.nightstand_arr()
    put("nightstand", "nightstand.png", night, feet, (40, 108), solid=[18, 8, -9, -6], glow=True)
    ward, feet = furn.wardrobe_arr()
    put("wardrobe", "wardrobe.png", ward, feet, (248, 92), solid=[46, 12, -23, -14])
    bucket, feet = furn.bucket_arr()
    put("bucket", "bucket.png", bucket, feet, (270, 124), solid=[12, 5, -6, -3])
    boots, feet = furn.boots_arr()
    put("boots", "boots.png", boots, feet, (100, 140))
    save("rug.png", furn.rug_arr())
    decals.append({"tex": "rug.png", "pos": [26, 138], "z": -4})
    spec["props"] = props
    spec["decals"] = decals
    spec["lights"] = [{"pos": [38, 92], "color": "#ffb468", "radius": 120, "squash": 0.8, "energy": 1.0, "flicker": 0.22}]


def hut_glow(arr):
    return furn.glow_of(arr)


def build(floor_wear=FLOOR_WEAR, wall_wear=WALL_WEAR):
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.png"):
        old.unlink()
    walk = [[(232, 128), (198, 96), (126, 66), (70, 40)], [(198, 96), (120, 92)], [(198, 96), (222, 136)]]
    floor = servant_floor.floor_img(FLOOR_W, FLOOR_H, seed=11, paths=walk, damp=((262, 18, 34), (14, 150, 22)), stains=((246, 40, 19, 11),), wear=floor_wear)
    save("floor.png", floor)
    save("wall.png", servant_wall.back_wall_img(SHELL_W, TOP_PAD, WALL_H, 4, wear=wall_wear, window=WINDOW))
    save("sky.png", servant_wall.sky_img(WINDOW[2], WINDOW[3]))
    save("side_l.png", servant_wall.side_img(True, BACK_Y + FLOOR_H + 6, SIDE_W, wear=wall_wear))
    save("side_r.png", servant_wall.side_img(False, BACK_Y + FLOOR_H + 6, SIDE_W, wear=wall_wear))
    save("front.png", servant_wall.front_img(SHELL_W, TOP_PAD, LIP_H - TOP_PAD, DOOR_GAP, wear=wall_wear))
    save("door.png", np.zeros((4, 4, 4), np.uint8))  # no door leaf yet
    spec = {
        "title": "Personalraum",
        "dir": "res://assets/interior/personalraum/",
        "size": [ROOM_W, ROOM_H],
        "floor": [SIDE_W, FLOOR_Y, FLOOR_W, FLOOR_H],
        "front_y": FRONT_Y,
        "surface": "stone",
        "door_locked": True,
        "ambient": {"day": "#dcd6e8", "night": "#4c4870"},
        "entry": [int(sum(DOOR_GAP) / 2), FRONT_Y - 12],
        "exit_door": {"id": "door", "pos": [int(sum(DOOR_GAP) / 2), FRONT_Y + 18], "leaf": [DOOR_GAP[0] - 4, FRONT_Y - 18]},
        "start": [112, 150],
        "shell": [
            {"tex": "floor.png", "pos": [SIDE_W, FLOOR_Y], "z": -6},
            {"tex": "sky.png", "pos": [WINDOW[0], WINDOW[1]], "z": -7},  # behind the wall and behind the crow (z -6) that flies out through the opening
            {"tex": "wall.png", "pos": [0, 0], "z": -5},
            {"tex": "side_l.png", "pos": [0, 0], "z": -5},
            {"tex": "side_r.png", "pos": [ROOM_W - SIDE_W, 0], "z": -5},
        ],
        "crows": [{"perch": list(PERCH), "exit": [PERCH[0] + 5, WINDOW[1] - 20]}],  # InteriorCrow: sits on the sill, flies out through the window when somebody comes near
        "walls": [
            [SIDE_W, 48, FLOOR_W, 28],
            [0, 40, 24, FLOOR_H + 60],
            [ROOM_W - 24, 40, 24, FLOOR_H + 60],
            [0, FRONT_Y + 10, DOOR_GAP[0], 30],
            [DOOR_GAP[1], FRONT_Y + 10, ROOM_W - DOOR_GAP[1], 30],
            [DOOR_GAP[0], FRONT_Y + 32, DOOR_GAP[1] - DOOR_GAP[0], 10],
        ],
    }
    furnish(spec)
    table = json.loads(DATA.read_text())
    table["personalraum"] = spec
    DATA.write_text(json.dumps(table, indent=1, ensure_ascii=False))
    return spec


def preview(path, spec):
    w, h = spec["size"]
    canvas = Image.new("RGBA", (w, h), (10, 6, 16, 255))
    for item in sorted(spec["shell"] + spec.get("decals", []), key=lambda i: i.get("z", 0)):
        canvas.alpha_composite(Image.open(OUT / item["tex"]).convert("RGBA"), tuple(item["pos"]))
    for prop in sorted(spec.get("props", []), key=lambda p: p["pos"][1]):  # furniture sorts by its feet row, glow sheets lie on top
        img = Image.open(OUT / prop["tex"]).convert("RGBA")
        at = (int(prop["pos"][0] - img.width / 2), int(prop["pos"][1] - prop["feet"]))
        canvas.alpha_composite(img, at)
        if "glow" in prop:
            canvas.alpha_composite(Image.open(OUT / prop["glow"]).convert("RGBA"), at)
    canvas.alpha_composite(Image.open(OUT / "front.png").convert("RGBA"), (0, spec["front_y"]))
    canvas.resize((w * 3, h * 3), Image.NEAREST).save(path)


if __name__ == "__main__":
    # python3 tools/art_servant_room.py [preview.png] [preset=neglected] [moss=3 cracks=0.5 ...]  (the knobs apply to floor and walls)
    args = sys.argv[1:]
    knobs = [a for a in args if "=" in a]
    pic = [a for a in args if "=" not in a]
    spec = build(parse(knobs, FLOOR_WEAR) if knobs else FLOOR_WEAR, parse(knobs, WALL_WEAR) if knobs else WALL_WEAR)
    print("wrote", OUT, "size", spec["size"])
    if pic:
        preview(Path(pic[0]), spec)
