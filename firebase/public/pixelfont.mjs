/**
 * PixelText: The game's 3x5 bitmap font rendered onto crisp pixel canvases.
 * Mirrored from the desktop launcher (pixelfont.js) for Shadowspore's web clearing.
 */
const GLYPHS = {
  A: ['010', '101', '111', '101', '101'],
  Ä: ['101', '010', '101', '111', '101'],
  B: ['110', '101', '110', '101', '110'],
  C: ['011', '100', '100', '100', '011'],
  D: ['110', '101', '101', '101', '110'],
  E: ['111', '100', '110', '100', '111'],
  F: ['111', '100', '110', '100', '100'],
  G: ['011', '100', '101', '101', '011'],
  H: ['101', '101', '111', '101', '101'],
  I: ['111', '010', '010', '010', '111'],
  J: ['001', '001', '001', '101', '010'],
  K: ['101', '101', '110', '101', '101'],
  L: ['100', '100', '100', '100', '111'],
  M: ['101', '111', '111', '101', '101'],
  N: ['101', '111', '111', '111', '101'],
  O: ['010', '101', '101', '101', '010'],
  Ö: ['101', '010', '101', '101', '010'],
  P: ['110', '101', '110', '100', '100'],
  Q: ['010', '101', '101', '111', '011'],
  R: ['110', '101', '110', '101', '101'],
  S: ['011', '100', '010', '001', '110'],
  T: ['111', '010', '010', '010', '010'],
  U: ['101', '101', '101', '101', '010'],
  Ü: ['101', '000', '101', '101', '010'],
  V: ['101', '101', '101', '101', '010'],
  W: ['101', '101', '111', '111', '101'],
  X: ['101', '101', '010', '101', '101'],
  Y: ['101', '101', '010', '010', '010'],
  Z: ['111', '001', '010', '100', '111'],
  0: ['111', '101', '101', '101', '111'],
  1: ['010', '110', '010', '010', '111'],
  2: ['110', '001', '010', '100', '111'],
  3: ['110', '001', '010', '001', '110'],
  4: ['101', '101', '111', '001', '001'],
  5: ['111', '100', '110', '001', '110'],
  6: ['011', '100', '111', '101', '111'],
  7: ['111', '001', '010', '010', '010'],
  8: ['111', '101', '111', '101', '111'],
  9: ['111', '101', '111', '001', '110'],
  '.': ['0', '0', '0', '0', '1'],
  ':': ['0', '1', '0', '1', '0'],
  '!': ['1', '1', '1', '0', '1'],
  '/': ['001', '001', '010', '100', '100'],
  '-': ['000', '000', '111', '000', '000'],
  '+': ['000', '010', '111', '010', '000'],
  '&': ['010', '101', '010', '101', '011'],
  ' ': ['00', '00', '00', '00', '00'],
};

function toCaps(text) {
  return String(text || '').replace(/ß/g, 'SS').toUpperCase();
}

export function renderPixelNode(node, text) {
  if (!node) return;
  if (typeof text === 'string') node.dataset.pxText = text;
  const raw = node.dataset.pxText ?? node.textContent;
  node.dataset.pxText = raw;

  const scale = Number(node.dataset.px || 2);
  const color = node.dataset.pxColor || '#ece4ff';
  const shadow = node.dataset.pxShadow === 'none' ? '' : (node.dataset.pxShadow || 'rgba(10,7,18,0.88)');

  const existing = node.querySelector(':scope > canvas.px-canvas');
  const canvas = existing || document.createElement('canvas');
  canvas.className = 'px-canvas';
  canvas.setAttribute('aria-hidden', 'true');
  paintPixelText(canvas, raw, { scale, color, shadow });

  if (!existing) {
    let sr = node.querySelector(':scope > .sr-only');
    if (!sr) {
      sr = document.createElement('span');
      sr.className = 'sr-only';
      node.textContent = '';
      node.append(canvas, sr);
    } else {
      node.prepend(canvas);
    }
    sr.textContent = raw;
  } else {
    const sr = node.querySelector(':scope > .sr-only');
    if (sr) sr.textContent = raw;
  }
}

export function paintPixelText(canvas, text, { scale = 2, color = '#ece4ff', shadow = 'rgba(10,7,18,0.88)' } = {}) {
  const s = Math.max(1, Math.round(scale));
  const upper = toCaps(text);
  const rows = 5;
  const padY = shadow ? 1 : 0;
  let totalW = 0;
  for (const ch of upper) {
    const g = GLYPHS[ch];
    totalW += (g ? g[0].length : 2) + 1;
  }
  totalW = Math.max(1, totalW - 1 + (shadow ? 1 : 0));

  canvas.width = totalW * s;
  canvas.height = (rows + padY) * s;
  canvas.style.width = `${canvas.width}px`;
  canvas.style.height = `${canvas.height}px`;

  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const drawPass = (fill, ox, oy) => {
    ctx.fillStyle = fill;
    let cx = 0;
    for (const ch of upper) {
      const g = GLYPHS[ch];
      if (!g) {
        cx += 3;
        continue;
      }
      for (let y = 0; y < g.length; y++) {
        for (let x = 0; x < g[y].length; x++) {
          if (g[y][x] === '1') {
            ctx.fillRect((cx + x + ox) * s, (y + oy) * s, s, s);
          }
        }
      }
      cx += g[0].length + 1;
    }
  };

  if (shadow) drawPass(shadow, 1, 1);
  drawPass(color, 0, 0);
}

export function hydratePixelText(root = document) {
  root.querySelectorAll('[data-px]').forEach((node) => renderPixelNode(node));
}
