"""Higgsfield dialogue portrait templates -> game portraits (103x153, hard alpha, 30 colours, light on the left).
py -3 tools/art_portraits_hf.py   (sources: assets/ui/sources/higgsfield/<id>.png, magenta #FF00FF background)
writes assets/ui/portrait_<id>.png and docs/img/portraits_hf.png"""
import os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/ui/sources/higgsfield")
W, H, COLORS = 103, 153, 30
OUTLINE = np.array([0x1f, 0x1d, 0x30], np.float32)

def convert(name):
    a = np.asarray(Image.open(os.path.join(SRC, name + ".png")).convert("RGB")).astype(np.float32)
    # magenta key: R and B high, G low (soft edges included)
    key = (a[..., 0] > 170) & (a[..., 2] > 170) & (a[..., 1] < 110)
    fg = ~key
    rgb = a.copy(); rgb[key] = OUTLINE        # background becomes outline colour so edges stay dark
    img = Image.fromarray(rgb.astype(np.uint8)).resize((W, H), Image.BOX)
    mask = Image.fromarray((fg * 255).astype(np.uint8)).resize((W, H), Image.BOX)
    m = np.asarray(mask) >= 128
    q = img.quantize(COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = np.zeros((H, W, 4), np.uint8); out[..., :3] = np.asarray(q); out[..., 3] = np.where(m, 255, 0)
    res = Image.fromarray(out, "RGBA")
    res.save(os.path.join(ROOT, f"assets/ui/portrait_{name}.png"))
    cols = len({tuple(p) for p in out[m][:, :3].tolist()})
    top = np.where(m.any(1))[0][0]
    print(name, "colors", cols, "top row", top, "bottom filled", bool(m[-1].any()))
    return res

names = ["torben", "maren", "esma", "morwenna"]
res = [convert(n) for n in names]
sheet = Image.new("RGBA", (W * 2 * 4 + 50, H * 2 + 20), (34, 28, 48, 255))
for i, r in enumerate(res):
    sheet.alpha_composite(r.resize((W * 2, H * 2), Image.NEAREST), (10 + i * (W * 2 + 10), 10))
sheet.convert("RGB").save(os.path.join(ROOT, "docs/img/portraits_hf.png"))
