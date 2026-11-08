#!/usr/bin/env python3
"""Contact sheet of the wear presets (tools/stone_wear.py) on the floor and wall of Ellie's room: python3 tools/preview_stone_wear.py out.png"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_servant_room as room  # noqa: E402
import servant_floor  # noqa: E402
import servant_wall  # noqa: E402
from stone_wear import PRESETS  # noqa: E402


def cell(wear):
    walk = [[(232, 128), (198, 96), (126, 66), (70, 40)], [(198, 96), (120, 92)], [(198, 96), (222, 136)]]
    floor = servant_floor.floor_img(room.FLOOR_W, room.FLOOR_H, seed=11, paths=walk, damp=((262, 18, 34), (14, 150, 22)), stains=((246, 40, 19, 11),), wear=wear)
    wall = servant_wall.back_wall_img(room.SHELL_W, room.TOP_PAD, room.WALL_H, 4, wear=wear)
    img = Image.new("RGBA", (room.SHELL_W, 76 + 84), (10, 6, 16, 255))
    img.alpha_composite(Image.fromarray(floor).crop((0, 0, room.FLOOR_W, 84)), (room.SIDE_W, room.BACK_Y))
    img.alpha_composite(Image.fromarray(wall), (0, 0))
    return img


def main(path):
    names = list(PRESETS)
    cols, scale, pad = 2, 2, 14
    cw, ch = room.SHELL_W * scale, 160 * scale
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (cw + pad) + pad, rows * (ch + pad + 14) + pad), (22, 18, 34, 255))
    draw = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        x, y = pad + (i % cols) * (cw + pad), pad + (i // cols) * (ch + pad + 14)
        draw.text((x, y), name.upper(), fill=(220, 214, 240, 255))
        sheet.alpha_composite(cell(PRESETS[name]).resize((cw, ch), Image.NEAREST), (x, y + 14))
    sheet.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "stone_wear.png")
