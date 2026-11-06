"""River flora and stones: 32x40 frames, eight phases, six rows, foot (16,34).
One family with the other water plants (art_water_plants.py) and the land flora: the same GREEN ramp (lit from the top left), the same ink
outline round everything that stands or floats above the water (sedges, pads, rocks); only what lives under the surface (grasses, gravel)
is outline-free. Every emergent piece has a dark contact shadow and a teal waterline ripple at its foot."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_bank_details import GREEN, INK, hexc  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FW, FH = 32, 40
SEA = [hexc(c) for c in ('1f5a5a', '2a7a74', '3f9a8c', '62bcac', 'a4fff0')]
WATER_DARK = (20, 40, 46, 120)
RIPPLE = (110, 214, 200, 110)


def outline(im: Image.Image) -> None:
    src = im.copy()
    for y in range(FH):
        for x in range(FW):
            if src.getpixel((x, y))[3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < FW and 0 <= ny < FH and src.getpixel((nx, ny))[3]:
                    im.putpixel((x, y), INK)
                    break


def waterline(p: ImageDraw.ImageDraw, x0: int, x1: int, y: int = 34) -> None:
    """The dark contact shadow under a plant and two bright ripple dashes at its sides."""
    p.ellipse((x0, y - 1, x1, y + 2), fill=WATER_DARK)
    p.line((x0 - 2, y + 1, x0, y + 1), fill=RIPPLE)
    p.line((x1, y + 1, x1 + 2, y + 1), fill=RIPPLE)


def blade(p: ImageDraw.ImageDraw, x: int, h: int, lean: int, sway: int, ramp: list, head: bool = False) -> None:
    """A two-pixel blade: dark side, lit side to the top left, a pale tip; leaning and bending with the sway."""
    top = (x + lean + sway, 33 - h)
    mid = (x + lean // 2, 33 - h // 2)
    p.line([(x, 33), mid, top], fill=ramp[2], width=2)
    p.line([(x - 1, 33), (mid[0] - 1, mid[1]), (top[0] - 1, top[1] + 1)], fill=ramp[3])
    p.point((top[0], top[1] - 1), fill=ramp[4])
    if head:  # a small seed head on the tallest blades
        p.rectangle((top[0] - 1, top[1] - 3, top[0], top[1] - 1), fill=hexc('6b4a3a'))
        p.point((top[0] - 1, top[1] - 3), fill=hexc('94694c'))


sheet = Image.new('RGBA', (FW * 8, FH * 6))
for frame in range(8):
    sway = (0, 0, 1, 1, 1, 0, -1, -1)[frame]
    for row in range(6):
        im = Image.new('RGBA', (FW, FH)); p = ImageDraw.Draw(im)
        if row == 0:  # submerged grasses rooted in the bed: soft sea-green, no outline
            for x, h, lean in [(10, 8, -2), (13, 12, -1), (16, 10, 1), (19, 13, 2), (22, 7, 1)]:
                p.line([(x, 33), (x + lean // 2, 29), (x + lean + sway, 33 - h)], fill=SEA[1], width=2)
                p.line([(x, 31), (x + lean + sway, 33 - h)], fill=SEA[2])
                p.point((x + lean + sway, 33 - h), fill=SEA[3])
        elif row == 1:  # sedges at the shore: three-tone blades, a few seed heads
            waterline(p, 7, 25)
            for i, (x, h, lean) in enumerate([(9, 11, -2), (12, 16, -2), (15, 12, 0), (18, 17, 1), (21, 12, 2), (24, 9, 2)]):
                blade(p, x, h, lean, sway, GREEN[1:], head=i in (1, 3))
        elif row == 2:  # small wet moss rock
            waterline(p, 7, 25)
            p.polygon([(8, 31), (10, 26), (14, 24), (20, 25), (23, 29), (24, 33), (20, 34), (10, 34)], fill=hexc('3a4a52'))
            p.polygon([(10, 29), (12, 26), (16, 25), (20, 26), (21, 29), (17, 30)], fill=hexc('72869a'))
            p.line((12, 25, 17, 25), fill=GREEN[3]); p.point((15, 24), fill=GREEN[4])
            if frame in (1, 2, 3): p.line((17, 26, 19, 26), fill=hexc('a8bccc'))
        elif row == 3:  # flat moss-covered rock
            waterline(p, 4, 28)
            p.polygon([(4, 31), (7, 27), (12, 25), (23, 26), (27, 29), (28, 33), (24, 35), (6, 35)], fill=hexc('3a4a52'))
            p.polygon([(6, 30), (9, 27), (14, 26), (23, 27), (25, 30), (19, 31), (10, 31)], fill=hexc('6e8296'))
            p.polygon([(9, 27), (13, 25), (19, 26), (20, 27), (15, 28)], fill=GREEN[2])
            p.line((12, 26, 16, 26), fill=GREEN[4])
            if frame in (4, 5, 6): p.line((21, 28, 24, 29), fill=hexc('a8bccc'))
        elif row == 4:  # gravel cluster under the surface: no outline, a lit top edge
            p.ellipse((5, 32, 27, 35), fill=hexc('3a5a56'))
            for x, y, w, h in [(7, 30, 4, 3), (12, 28, 5, 4), (18, 30, 5, 3), (23, 31, 3, 2), (15, 32, 4, 2)]:
                p.ellipse((x, y, x + w, y + h), fill=hexc('6e8480'))
                p.line((x + 1, y, x + w - 1, y), fill=hexc('a4b4a6'))
            if frame in (0, 1): p.point((20, 30), fill=hexc('d0d4bc'))
        else:  # small anchored floating pads: ramp shading, a vein, a notch, a contact shadow
            for ox, oy, rx, ry, big in ((5, 29, 13, 5, 1), (17, 26, 9, 5, 0)):
                p.ellipse((ox, oy + 1, ox + rx, oy + ry + 1), fill=WATER_DARK)
                p.ellipse((ox + 1, oy, ox + rx - 1, oy + ry - 1), fill=GREEN[2])
                p.ellipse((ox + 2, oy, ox + rx - 3, oy + ry - 3), fill=GREEN[3])
                p.line((ox + 3, oy + 1, ox + rx - 5, oy + 1), fill=GREEN[4])
                p.line((ox + rx // 2, oy + ry // 2, ox + rx - 1, oy + ry // 2 + 1), fill=GREEN[0])  # the notch of the heart
                p.line((ox + 2, oy + ry - 2, ox + rx - 2, oy + ry - 2), fill=GREEN[1])
            if frame in (2, 3, 4): p.point((9, 29), fill=GREEN[5])
        if row in (1, 2, 3, 5):
            outline(im)
        sheet.alpha_composite(im, (frame * FW, row * FH))
output = ROOT / 'assets/water/river_details.png'
output.parent.mkdir(parents=True, exist_ok=True)
sheet.save(output)
if len(sys.argv) > 1:
    preview = Image.new('RGBA', sheet.size, '#28545a')
    preview.alpha_composite(sheet)
    preview.resize((sheet.width * 3, sheet.height * 3), Image.Resampling.NEAREST).save(sys.argv[1])
