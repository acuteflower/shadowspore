"""Bake compact 1x E-facing walk strips and companion bird flight frames for LoadingScreen.

Preserves original RGB shading (used by silhouette.gdshader for subtle moonlit
tonal sculpting) while stripping semi-transparent baked ground shadows and
aligning every walker's boot soles to a shared baseline.

No changes to character/wildlife sources. Run: python3 tools/art_loading.py
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CELL = (64, 64)
COLS = 12
ROWS = 5
FEET_X = 32
SOLE_Y = 61


def strip_shadow(tile: Image.Image, min_alpha: int = 140) -> Image.Image:
    out = tile.copy()
    alpha = out.getchannel("A").point(lambda a: 255 if a >= min_alpha else 0)
    out.putalpha(alpha)
    return out


def sole_row(frames: list[Image.Image]) -> int:
    bottom = 0
    for frame in frames:
        bbox = frame.getchannel("A").getbbox()
        if bbox is not None:
            bottom = max(bottom, bbox[3] - 1)
    return bottom


def main() -> None:
    sheet = Image.new("RGBA", (CELL[0] * COLS, CELL[1] * ROWS), (0, 0, 0, 0))
    cast = ["player", "adventurer", "gustav", "torben"]
    for row, name in enumerate(cast):
        source = Image.open(ROOT / f"assets/characters/{name}.png").convert("RGBA")
        if name == "player":
            size = (48, 56)
            feet_x = 24
            start, count = 0, 6
        else:
            rig = json.loads((ROOT / f"data/{name}_rig.json").read_text(encoding="utf-8"))
            size = (int(rig["frame"][0]), int(rig["frame"][1]))
            feet_x = int(rig["feet"][0])
            walk = rig["clips"]["walk"]
            start, count = int(walk["start"]), int(walk["count"])
        frames: list[Image.Image] = []
        for i in range(count):
            col = start + i
            crop = source.crop((col * size[0], 0, (col + 1) * size[0], size[1]))
            frames.append(strip_shadow(crop, 140))
        bottom = sole_row(frames)
        for i, clean in enumerate(frames):
            dx = FEET_X - feet_x
            dy = SOLE_Y - bottom
            cell_im = Image.new("RGBA", CELL, (0, 0, 0, 0))
            cell_im.alpha_composite(clean, (dx, dy))
            sheet.paste(cell_im, (i * CELL[0], row * CELL[1]))

    # Row 4: E-facing crow companion flight (cols 0..7 = flap 30..37, cols 8..11 = glide 50..53)
    corvid = Image.open(ROOT / "assets/wildlife/corvid.png").convert("RGBA")
    bird_cols = [30, 31, 32, 33, 34, 35, 36, 37, 50, 51, 52, 53]
    for i, src_col in enumerate(bird_cols):
        crop = corvid.crop((src_col * 48, 0, (src_col + 1) * 48, 48))
        clean = strip_shadow(crop, 100)
        cell_im = Image.new("RGBA", CELL, (0, 0, 0, 0))
        cell_im.alpha_composite(clean, (8, 8))
        sheet.paste(cell_im, (i * CELL[0], 4 * CELL[1]))

    out_path = ROOT / "assets/ui/loading_cast.png"
    sheet.save(out_path)
    print(f"Baked {out_path.relative_to(ROOT)} ({sheet.width}x{sheet.height}, 4 walkers + companion bird).")


if __name__ == "__main__":
    main()
