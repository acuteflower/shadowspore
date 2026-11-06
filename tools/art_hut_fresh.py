#!/usr/bin/env python3
"""The hut after its renewal, drawn completely new (needs numpy): the same plum-violet fir and the same furniture as the old hut, but cleaned up and freshened,
not brand new: planed boards a little lighter and warmer, no moss, ivy, roots, cobwebs, holes, mushrooms or breakage; the roof closed, the window with two
whole shutters, the door whole, the beds and chairs mended, the rug without moth holes. It runs the same generators as tools/art_hut.py with the `fresh()` switch
of hut_lib turned on and writes assets/interior/hut/fresh/<same file names>; the game (`Hut.set_renewed`, `Interior.set_renewed`) swaps to them when the work
is done, whatever has no file there (herbs, lantern, flames, sunbeams) stays as it was.
    python3 tools/art_hut_fresh.py [preview.png]      (with an argument also a preview of the room and of the outside)"""
import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hut_lib  # noqa: E402

hut_lib.set_fresh()
import art_hut  # noqa: E402
import hut_outside as outside  # noqa: E402
import hut_props as props  # noqa: E402
import hut_room as room  # noqa: E402
from hut_lib import ROOT  # noqa: E402

OLD = ROOT / "interior" / "hut"
OUT = OLD / "fresh"
OUT.mkdir(parents=True, exist_ok=True)
art_hut.OUT = OUT


def main():
    put = art_hut.put
    put("floor", room.floor_arr(), glow=False)
    put("wall", room.back_wall_arr())
    put("side", room.side_arr())
    put("front", room.front_arr())
    put("door", room.door_arr(48, 40))
    put("hut_door", room.door_arr(34, 44, seed=23))
    sheet, _ = props.bed_frames()
    put("bed", sheet)
    for name, fn in (("table", props.table_arr), ("chair", props.chair_arr), ("cupboard", props.cupboard_arr), ("chest", props.chest_arr), ("barrel", props.barrel_arr),
                     ("crates", props.crates_arr), ("shelf", props.shelf_arr), ("rack", props.rack_arr), ("fireplace", props.fireplace_arr), ("pots", props.pots_arr),
                     ("rug", props.rug_arr)):
        arr, _ = fn()
        put(name, arr)
    stools = [props.stool_arr(v) for v in range(3)]
    sheet = np.zeros((30, 28 * 3, 4), np.uint8)
    for i, (arr, _) in enumerate(stools):
        sheet[:arr.shape[0], i * 28:i * 28 + arr.shape[1]] = arr[:30, :28]
    put("stool", sheet)
    ext, feet = outside.hut_arr()
    put("hut", ext)
    put("vane", outside.vane_arr(), glow=False)
    if outside.WINDOW_BOX:  # the lamp light that leaves the window (Hut draws it additive at night)
        hut_lib.save(OUT / "hut_window_light.png", hut_lib.window_spill(ext.shape[1], ext.shape[0], feet, outside.WINDOW_BOX))
    print(json.dumps(art_hut.SIZES))
    if len(sys.argv) > 1:  # the old files with the fresh ones laid over them, then the normal preview
        tmp = Path(tempfile.mkdtemp())
        for f in OLD.glob("*.png"):
            shutil.copy(f, tmp / f.name)
        for f in OUT.glob("*.png"):
            shutil.copy(f, tmp / f.name)
        for f in OLD.glob("*_glow.png"):
            if f.name not in {g.name for g in OUT.glob("*_glow.png")} and (OUT / f.name.replace("_glow", "")).exists():
                (tmp / f.name).unlink()
        art_hut.OUT = tmp
        art_hut.preview(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
