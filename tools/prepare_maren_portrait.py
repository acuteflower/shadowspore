"""Prepare Maren's transparent source on the shared 103x153 NPC art grid."""
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent
image = Image.open(ROOT/'docs/img/maren_portrait_source.png').convert('RGBA')
image = image.crop(image.getchannel('A').getbbox())
width = round(image.width * 153 / image.height)
image = image.resize((width,153),Image.Resampling.NEAREST)
if width >= 103:
    left=(width-103)//2
    image=image.crop((left,0,left+103,153))
else:
    canvas=Image.new('RGBA',(103,153));canvas.alpha_composite(image,((103-width)//2,0));image=canvas
alpha=image.getchannel('A').point(lambda x: 255 if x>=128 else 0)
image=image.convert('RGB').quantize(colors=30,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).convert('RGBA')
image.putalpha(alpha)
image.save(ROOT/'assets/ui/portrait_maren.png')
