#!/usr/bin/env python3
"""The old hut of the story (needs numpy): the outside of the hut and everything of its inside (the first interior, see src/world/interiors.gd).
Everything wooden is built from ellipsoids with the heroine's / trees' / signpost's renderer (art_hero3d), so it is made like the rest of the world: the trunks'
violet-plum bark, rounded forms lit from the top left, four bands of shade, ink between the forms, painterly grain, moss, violet veins, teal shelf fungi.
The floor and the rug are rendered looking straight down, like the world's ground. Modules: hut_lib (palettes, helpers), hut_room (floor, walls, door), hut_props
(furniture and odd things), hut_outside (the hut from outside), hut_fx (flames, sunbeams, webs, drips).
    python3 tools/art_hut.py [preview.png]     writes assets/interior/hut/*.png (+ _glow sheets with only the emissive pixels, drawn unlit) and, with an argument,
                                               a preview of the room (positions from data/interiors.json) and the outside."""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hut_fx as fx  # noqa: E402
import hut_lib  # noqa: E402
import hut_outside as outside  # noqa: E402
import hut_props as props  # noqa: E402
import hut_room as room  # noqa: E402
from hut_lib import ROOT, glow_of, save, to_array  # noqa: E402

OUT = ROOT / "interior" / "hut"
OUT.mkdir(parents=True, exist_ok=True)
SIZES = {}


def put(name, arr, glow=True):
    save(OUT / f"{name}.png", arr)
    SIZES[name] = (arr.shape[1], arr.shape[0])
    if glow:
        g = glow_of(arr)
        if g[..., 3].any():
            save(OUT / f"{name}_glow.png", g)
            SIZES[name + "_glow"] = (arr.shape[1], arr.shape[0])
        elif (OUT / f"{name}_glow.png").exists():
            (OUT / f"{name}_glow.png").unlink()


def main():
    put("floor", room.floor_arr(), glow=False)
    put("wall", room.back_wall_arr())
    put("side", room.side_arr())
    put("front", room.front_arr())
    put("door", room.door_arr(48, 40))
    put("hut_door", room.door_arr(34, 44, seed=23))
    put("rays", fx.rays_arr(), glow=False)
    put("web", fx.webs_arr(), glow=False)
    sheet, feet = props.bed_frames()
    put("bed", sheet)
    for name, fn in (("table", props.table_arr), ("chair", props.chair_arr), ("cupboard", props.cupboard_arr), ("chest", props.chest_arr), ("barrel", props.barrel_arr),
                     ("crates", props.crates_arr), ("shelf", props.shelf_arr), ("rack", props.rack_arr), ("fireplace", props.fireplace_arr), ("herbs", props.herbs_arr),
                     ("lantern", props.lantern_arr), ("pots", props.pots_arr), ("rug", props.rug_arr)):
        arr, feet = fn()
        put(name, arr)
        SIZES[name + "_feet"] = feet
    stools = [props.stool_arr(v) for v in range(3)]
    stool_sheet = np.zeros((30, 28 * 3, 4), np.uint8)
    for i, (arr, _) in enumerate(stools):
        stool_sheet[:arr.shape[0], i * 28:i * 28 + arr.shape[1]] = arr[:30, :28]
    put("stool", stool_sheet)
    trunk, crown, feet = props.sapling_arrs()
    put("sapling", trunk)
    put("sapling_crown", crown)
    SIZES["sapling_feet"] = feet
    put("fire", fx.fire_frames(), glow=False)
    drip, splash = fx.drip_arr()
    put("drip", drip, glow=False)
    put("splash", splash, glow=False)
    ext, feet = outside.hut_arr()
    put("hut", ext)
    if outside.WINDOW_BOX:
        save(OUT / "hut_window_light.png", hut_lib.window_spill(ext.shape[1], ext.shape[0], feet, outside.WINDOW_BOX))
    SIZES["hut_feet"] = feet
    for old in ("shell.png", "shell_glow.png", "pot.png", "bed_empty.png"):
        if (OUT / old).exists():
            (OUT / old).unlink()
    print(json.dumps(SIZES))
    if len(sys.argv) > 1:
        preview(Path(sys.argv[1]))


def preview(path):
    data = json.loads((ROOT.parent / "data" / "interiors.json").read_text())["hut"]
    from hut_lib import load_png_arr
    w, h_ = data["size"]
    canvas = np.zeros((h_, w, 4), np.uint8)
    canvas[:] = (10, 6, 16, 255)

    def paste(arr, x, y, flip=False):
        if flip:
            arr = arr[:, ::-1]
        ah, aw = arr.shape[:2]
        for yy in range(ah):
            if not 0 <= y + yy < h_:
                continue
            for xx in range(aw):
                if 0 <= x + xx < w and arr[yy, xx, 3]:
                    a = arr[yy, xx, 3] / 255.0
                    canvas[y + yy, x + xx, :3] = arr[yy, xx, :3] * a + canvas[y + yy, x + xx, :3] * (1 - a)

    for item in data["shell"]:
        paste(load_png_arr(OUT / item["tex"]), item["pos"][0], item["pos"][1], item.get("flip", False))
    for decal in data.get("decals", []):
        paste(load_png_arr(OUT / decal["tex"]), decal["pos"][0], decal["pos"][1], decal.get("flip", False))
    items = sorted(data["props"], key=lambda p: p["pos"][1])
    for p in items:
        tex = load_png_arr(Path(p["tex"].replace("res://assets/", str(ROOT) + "/")) if p["tex"].startswith("res://") else OUT / p["tex"])
        frames = p.get("frames", 1)
        fw = tex.shape[1] // frames
        frame = tex[:, fw * p.get("frame", 0):fw * (p.get("frame", 0) + 1)]
        paste(frame, int(p["pos"][0] - fw / 2), int(p["pos"][1] - p.get("feet", frame.shape[0])))
        if "crown" in p:
            paste(load_png_arr(OUT / p["crown"]["tex"]), int(p["pos"][0] - fw / 2), int(p["pos"][1] - p.get("feet", frame.shape[0])))
    paste(load_png_arr(OUT / "front.png"), 0, data["front_y"])
    paste(load_png_arr(OUT / "door.png"), data["exit_door"]["leaf"][0], data["exit_door"]["leaf"][1])
    save(path, canvas)
    ext = load_png_arr(OUT / "hut.png")
    bg = np.zeros_like(ext)
    bg[:] = (58, 110, 70, 255)
    a = ext[..., 3:4] / 255.0
    save(path.with_name(path.stem + "_outside.png"), (ext * a + bg * (1 - a)).astype(np.uint8))


if __name__ == "__main__":
    main()
