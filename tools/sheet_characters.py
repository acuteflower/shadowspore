"""Contact sheets: every playable/NPC character from all 8 sides (idle frame 0).
Usage: py -3 tools/sheet_characters.py   -> docs/img/character_sheets/<id>.png + all_front.png"""
import json, os
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs/img/character_sheets"); os.makedirs(OUT, exist_ok=True)
VIEWS = ["RECHTS", "VORN-RECHTS", "VORN", "VORN-LINKS", "LINKS", "HINTEN-LINKS", "HINTEN", "HINTEN-RECHTS"]
BG = (34, 28, 48, 255)
# id, title, sheet, frame w/h, idle column, rows
CH = []
def rig(n): return json.load(open(os.path.join(ROOT, f"data/{n}_rig.json")))
CH.append(("ellie", "ELLIE", "assets/characters/player.png", (48, 56), 12))
for n, t in [("adventurer", "VALDRIC (RITTER)"), ("gustav", "GUSTAV"), ("torben", "TORBEN"),
             ("maren", "MAREN"), ("witch", "ESMA (NEBELHEXE)")]:
    r = rig(n); CH.append((n, t, f"assets/characters/{n}.png", tuple(r["frame"]), r["clips"]["idle"]["start"]))
r = rig("morwenna"); CH.append(("morwenna", "MORWENNA (BOSS)", "assets/enemies/morwenna/morwenna_0.png", tuple(r["frame"]), r["clips"]["idle"]["start"]))
font = ImageFont.load_default()
fronts = []
for cid, title, path, (fw, fh), col in CH:
    im = Image.open(os.path.join(ROOT, path)).convert("RGBA")
    cells = [im.crop((col * fw, row * fh, col * fw + fw, row * fh + fh)) for row in range(8)]
    bbs = [c.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox() for c in cells]
    x0 = min(b[0] for b in bbs); y0 = min(b[1] for b in bbs); x1 = max(b[2] for b in bbs); y1 = max(b[3] for b in bbs)
    cw, ch = x1 - x0 + 6, y1 - y0 + 6
    cells = [c.crop((x0 - 3, y0 - 3, x1 + 3, y1 + 3)) for c in cells]
    sc = max(2, min(8, 330 // ch))
    tw, th = cw * sc, ch * sc
    W, H = tw * 4, (th + 22) * 2 + 34
    sheet = Image.new("RGBA", (W, H), BG); d = ImageDraw.Draw(sheet)
    d.text((8, 8), f"{title}  -  Ingame-Sprite, 8 Richtungen (x{sc}, Idle)", fill=(230, 220, 190, 255), font=font)
    for i, c in enumerate(cells):
        x, y = (i % 4) * tw, 34 + (i // 4) * (th + 22)
        sheet.alpha_composite(c.resize((tw, th), Image.NEAREST), (x, y + 18))
        d.text((x + 6, y + 4), f"{i}  {VIEWS[i]}", fill=(150, 220, 210, 255), font=font)
    sheet.convert("RGB").save(os.path.join(OUT, f"{cid}.png"))
    fronts.append((title, cells[2], sc))
    print(cid, sheet.size, "scale", sc)
# overview: every character from the front, same scale
S = 5; h = max(c.height for _, c, _ in fronts) * S; w = sum(c.width * S + 24 for _, c, _ in fronts)
ov = Image.new("RGBA", (w, h + 34), BG); d = ImageDraw.Draw(ov); x = 0
for t, c, _ in fronts:
    ov.alpha_composite(c.resize((c.width * S, c.height * S), Image.NEAREST), (x + 12, 34 + h - c.height * S))
    d.text((x + 12, 10), t, fill=(230, 220, 190, 255), font=font); x += c.width * S + 24
ov.convert("RGB").save(os.path.join(OUT, "all_front.png")); print("overview", ov.size)
