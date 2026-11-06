#!/usr/bin/env python3
"""Writes the mine's props (tools/mine_props.py): assets/mine/props/<id>.png (+ <id>_glow.png with only the emissive pixels, drawn unlit),
assets/mine/rails.png (8 floor tiles) and data/mine_props.json (id -> texture, glow, feet row, size). `python3 tools/art_mine_props.py [contact_sheet.png]`.
Then `Godot --headless --import`."""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mine_props as p  # noqa: E402
import mine_props_deep as d  # noqa: E402
import mine_props_decor as c  # noqa: E402
from hut_lib import ROOT, glow_of, save, to_array, to_rows  # noqa: E402
from gen_art import write_png  # noqa: E402

OUT = ROOT / "mine" / "props"
BUILDERS = {
    "support_frame": p.support_frame_arr, "support_lamp": lambda: p.support_frame_arr(True), "post": p.post_arr,
    "lamp": lambda: p.lamp_arr(True), "lamp_dead": lambda: p.lamp_arr(False),
    "cart": lambda: p.cart_arr(False), "cart_loaded": lambda: p.cart_arr(True),
    "crates": p.crates_arr, "barrel": p.barrel_arr, "sacks": p.sacks_arr,
    "stairs_down": p.stairs_down_arr, "stairs_up": p.stairs_up_arr, "winch": p.winch_arr,
    "entrance": p.entrance_arr,
    "bunk": p.bunk_arr, "bones": p.bones_arr, "notes": p.notes_arr, "nest": p.nest_arr, "stalagmites": p.stalagmites_arr, "waysign": p.waysign_arr,
    "web": p.web_arr, "puddle_a": lambda: p.puddle_arr(44, 20, 5), "puddle_b": lambda: p.puddle_arr(28, 14, 6),
    "chest": p.treasure_chest_arr, "table": p.table_stool, "stool": p.stool_arr, "shelf": p.shelf_arr, "pots": p.pots_arr,
    "anvil": d.anvil_arr, "forge": d.forge_arr, "quench": d.quench_arr,
    "crystal_a": d.crystal_a_arr, "crystal_b": d.crystal_b_arr, "crystal_big": d.crystal_big_arr,
    "void_crack": d.void_crack_arr, "void_pod": d.void_pod_arr, "void_eyes": d.void_eyes_arr,
    "rubble_a": c.rubble_a_arr, "rubble_b": c.rubble_b_arr, "rubble_c": c.rubble_c_arr, "planks": c.planks_arr, "mushrooms": c.mushrooms_arr, "lantern_floor": c.lantern_arr,
    "pickaxe": c.pickaxe_arr, "bucket": c.bucket_arr, "rope": c.rope_arr, "ladder": c.ladder_arr, "chain": c.chain_arr,
}

FULL_GLOW = {"void_crack", "void_eyes"}  # flat decals that are light all over


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    table = {}
    arrays = {}
    for name, fn in BUILDERS.items():
        arr, feet = fn()
        save(OUT / f"{name}.png", arr)
        entry = {"tex": f"res://assets/mine/props/{name}.png", "feet": int(feet), "size": [arr.shape[1], arr.shape[0]]}
        g = arr.copy() if name in FULL_GLOW else glow_of(arr)
        if g[..., 3].any():
            save(OUT / f"{name}_glow.png", g)
            entry["glow"] = f"res://assets/mine/props/{name}_glow.png"
        elif (OUT / f"{name}_glow.png").exists():
            (OUT / f"{name}_glow.png").unlink()
        table[name] = entry
        arrays[name] = arr
    tiles = []
    (ROOT.parent / "data" / "mine_props.json").write_text(json.dumps(table, indent="\t") + "\n")
    print("wrote", len(BUILDERS), "props")
    if len(sys.argv) > 1:
        sheet(arrays, tiles, Path(sys.argv[1]))


def sheet(arrays, tiles, path):
    """All props side by side on a floor-coloured ground, 2x."""
    W = 960
    x, y, row_h = 6, 6, 0
    canvas = np.zeros((560, W, 4), np.uint8)
    canvas[:] = (62, 52, 62, 255)
    for name, arr in arrays.items():
        h_, w_ = arr.shape[:2]
        if x + w_ + 6 > W:
            x, y, row_h = 6, y + row_h + 6, 0
        if y + h_ > canvas.shape[0]:
            break
        for yy in range(h_):
            for xx in range(w_):
                if arr[yy, xx, 3]:
                    a = arr[yy, xx, 3] / 255.0
                    canvas[y + yy, x + xx, :3] = arr[yy, xx, :3] * a + canvas[y + yy, x + xx, :3] * (1 - a)
        x += w_ + 6
        row_h = max(row_h, h_)
    ty = y + row_h + 6
    for i, t in enumerate(tiles):
        for yy in range(16):
            for xx in range(16):
                if t[yy][xx][3] and ty + yy < canvas.shape[0]:
                    canvas[ty + yy, 6 + i * 18 + xx] = t[yy][xx]
    big = np.kron(canvas, np.ones((2, 2, 1), np.uint8))
    save(path, big)


if __name__ == "__main__":
    main()
