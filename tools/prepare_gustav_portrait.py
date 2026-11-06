"""Prepare the transparent Imagegen portrait for the shared 103x153 dialogue grid."""
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent
image = Image.open(ROOT / 'docs/img/gustav_portrait_source.png').convert('RGBA')
image = image.crop(image.getchannel('A').getbbox())
width = round(image.width * 153 / image.height)
image = image.resize((width, 153), Image.Resampling.NEAREST)
left = (width - 103) // 2
image = image.crop((left, 0, left + 103, 153))
alpha = image.getchannel('A').point(lambda value: 255 if value >= 128 else 0)
image = image.convert('RGB').quantize(colors=30, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGBA')
image.putalpha(alpha)
image.save(ROOT / 'assets/ui/portrait_gustav.png')
