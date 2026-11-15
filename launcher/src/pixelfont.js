// The game's own 3x5 pixel font (src/ui/pixel_text.gd, PixelText), drawn crisp at
// integer scales. Upper case only; Ä Ö Ü carry their dots in the two rows above.
const GLYPHS = {
  A: [".X.", "X.X", "XXX", "X.X", "X.X"], B: ["XX.", "X.X", "XX.", "X.X", "XX."],
  C: [".XX", "X..", "X..", "X..", ".XX"], D: ["XX.", "X.X", "X.X", "X.X", "XX."],
  E: ["XXX", "X..", "XX.", "X..", "XXX"], F: ["XXX", "X..", "XX.", "X..", "X.."],
  G: [".XX", "X..", "X.X", "X.X", ".XX"], H: ["X.X", "X.X", "XXX", "X.X", "X.X"],
  I: ["XXX", ".X.", ".X.", ".X.", "XXX"], J: ["..X", "..X", "..X", "X.X", ".X."],
  K: ["X.X", "X.X", "XX.", "X.X", "X.X"], L: ["X..", "X..", "X..", "X..", "XXX"],
  M: ["X.X", "XXX", "XXX", "X.X", "X.X"], N: ["XX.", "X.X", "X.X", "X.X", "X.X"],
  O: [".X.", "X.X", "X.X", "X.X", ".X."], P: ["XX.", "X.X", "XX.", "X..", "X.."],
  Q: [".X.", "X.X", "X.X", "XX.", ".XX"], R: ["XX.", "X.X", "XX.", "X.X", "X.X"],
  S: [".XX", "X..", ".X.", "..X", "XX."], T: ["XXX", ".X.", ".X.", ".X.", ".X."],
  U: ["X.X", "X.X", "X.X", "X.X", "XXX"], V: ["X.X", "X.X", "X.X", "X.X", ".X."],
  W: ["X.X", "X.X", "XXX", "XXX", "X.X"], X: ["X.X", "X.X", ".X.", "X.X", "X.X"],
  Y: ["X.X", "X.X", ".X.", ".X.", ".X."], Z: ["XXX", "..X", ".X.", "X..", "XXX"],
  0: ["XXX", "X.X", "X.X", "X.X", "XXX"], 1: [".X.", "XX.", ".X.", ".X.", "XXX"],
  2: ["XXX", "..X", "XXX", "X..", "XXX"], 3: ["XXX", "..X", "XXX", "..X", "XXX"],
  4: ["X.X", "X.X", "XXX", "..X", "..X"], 5: ["XXX", "X..", "XXX", "..X", "XXX"],
  6: ["XXX", "X..", "XXX", "X.X", "XXX"], 7: ["XXX", "..X", "..X", ".X.", ".X."],
  8: ["XXX", "X.X", "XXX", "X.X", "XXX"], 9: ["XXX", "X.X", "XXX", "..X", "XXX"],
  ".": ["...", "...", "...", "...", ".X."], ",": ["...", "...", "...", ".X.", "X.."],
  ":": ["...", ".X.", "...", ".X.", "..."], "-": ["...", "...", "XXX", "...", "..."],
  "+": ["...", ".X.", "XXX", ".X.", "..."], "/": ["..X", "..X", ".X.", "X..", "X.."],
  ">": ["X..", ".X.", "..X", ".X.", "X.."], "%": ["X.X", "..X", ".X.", "X..", "X.X"],
  "!": [".X.", ".X.", ".X.", "...", ".X."], "?": ["XX.", "..X", ".X.", "...", ".X."],
  "&": [".X.", "X.X", ".X.", "X.X", ".XX"], "@": [".XX", "X.X", "XXX", "X..", ".XX"],
  _: ["...", "...", "...", "...", "XXX"], "*": ["X.X", ".X.", "XXX", ".X.", "X.X"],
  "·": ["...", "...", ".X.", "...", "..."], "'": [".X.", ".X.", "...", "...", "..."],
  "(": [".X.", "X..", "X..", "X..", ".X."], ")": [".X.", "..X", "..X", "..X", ".X."],
};
const ACCENTS = { Ä: "A", Ö: "O", Ü: "U" };
const ADVANCE = 4;
const HEIGHT = 7;

function normalize(text) {
  return String(text).replace(/ß/g, "SS").toUpperCase();
}

export function pixelWidth(text) {
  return Math.max(normalize(text).length * ADVANCE - 1, 0);
}

/** Paints `text` into `canvas` (resized to fit) at `scale` CSS pixels per font pixel. */
export function paintPixelText(canvas, text, { scale = 2, color = "#f1e6ff", shadow = "rgba(8,3,18,.85)", glow = "" } = {}) {
  const str = normalize(text);
  const pad = shadow ? 1 : 0;
  const w = (pixelWidth(str) + pad * 2) * scale;
  const h = (HEIGHT + pad * 2) * scale;
  const dpr = Math.max(1, Math.round(window.devicePixelRatio || 1));
  canvas.width = Math.max(1, w * dpr);
  canvas.height = h * dpr;
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr * scale, 0, 0, dpr * scale, 0, 0);
  ctx.clearRect(0, 0, w, h);
  const pixels = [];
  let x = 0;
  for (const ch of str) {
    const base = ACCENTS[ch] || ch;
    const rows = GLYPHS[base];
    if (rows) {
      for (let r = 0; r < 5; r++) for (let c = 0; c < 3; c++) if (rows[r][c] === "X") pixels.push([x + c, 2 + r]);
      if (ACCENTS[ch]) pixels.push([x, 0], [x + 2, 0]);
    }
    x += ADVANCE;
  }
  if (shadow) {
    ctx.fillStyle = shadow;
    for (const [px, py] of pixels) {
      ctx.fillRect(px, py, 1 + pad * 2, 1 + pad * 2);
    }
  }
  if (glow) {
    ctx.shadowColor = glow;
    ctx.shadowBlur = 3;
  }
  ctx.fillStyle = color;
  for (const [px, py] of pixels) ctx.fillRect(px + pad, py + pad, 1, 1);
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", text);
  canvas.title = "";
}

/** Upgrades every `[data-px]` element: its text becomes a pixel-font canvas. */
export function hydratePixelText(root = document) {
  for (const node of root.querySelectorAll("[data-px]")) renderPixelNode(node);
}

export function renderPixelNode(node, text) {
  const label = text ?? node.dataset.pxText ?? node.textContent.trim();
  node.dataset.pxText = label;
  const scale = Number(node.dataset.px) || 2;
  const color = node.dataset.pxColor || getComputedStyle(node).color || "#f1e6ff";
  let canvas = node.querySelector(":scope > canvas.px");
  if (!canvas) {
    node.textContent = "";
    canvas = document.createElement("canvas");
    canvas.className = "px";
    node.appendChild(canvas);
  }
  paintPixelText(canvas, label, {
    scale,
    color,
    shadow: node.dataset.pxShadow === "none" ? "" : node.dataset.pxShadow || "rgba(8,3,18,.85)",
    glow: node.dataset.pxGlow || "",
  });
}
