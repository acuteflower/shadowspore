// The night over the launcher, drawn like the game's main menu (menu_dark.gdshader):
// real pixel darkness at a quarter of the window's resolution, ordered-dithered between
// a few steps, creeping like smoke. Light sources hold pools open: the cursor and every
// element with data-light="radius" (data-light-color="r,g,b"). Spores are single pixels.
const prefersReduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const CELL = 4;
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((v) => (v + 0.5) / 16);
const NIGHT = [7, 4, 15];
const SPORES = [
  [154, 107, 255],
  [201, 166, 255],
  [95, 240, 208],
  [255, 211, 138],
];

export class Atmosphere {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.paused = false;
    this.dim = 0.9; // the night starts closed and opens on boot
    this.dimTarget = 0.36;
    this.flare = 0; // 0..1: the play stone's light swells over the clearing
    this.flareTarget = 0;
    this.mouse = { x: -9999, y: -9999, tx: -9999, ty: -9999, seen: false };
    this.t = 0;
    this.motes = [];
    window.addEventListener("resize", () => this.resize());
    window.addEventListener("pointermove", (e) => {
      this.mouse.tx = e.clientX;
      this.mouse.ty = e.clientY;
      if (!this.mouse.seen) {
        this.mouse.x = e.clientX;
        this.mouse.y = e.clientY;
        this.mouse.seen = true;
      }
    });
    document.addEventListener("pointerleave", () => (this.mouse.seen = false));
    this.resize();
    for (let i = 0; i < 46; i++) this.motes.push(this.spawn(true));
    this.last = performance.now();
    this.acc = 0;
    requestAnimationFrame((t) => this.frame(t));
  }

  resize() {
    // A hidden window can report 0 x 0 while it starts.
    this.w = Math.max(1, window.innerWidth);
    this.h = Math.max(1, window.innerHeight);
    this.cw = Math.ceil(this.w / CELL);
    this.ch = Math.ceil(this.h / CELL);
    this.canvas.width = this.cw;
    this.canvas.height = this.ch;
    this.image = this.ctx.createImageData(this.cw, this.ch);
  }

  spawn(anywhere = false) {
    const firefly = Math.random() < 0.3;
    return {
      x: Math.random() * this.cw,
      y: anywhere ? Math.random() * this.ch : this.ch + 2,
      vx: (Math.random() - 0.5) * 1.4,
      vy: -(0.6 + Math.random() * (firefly ? 1.2 : 2.6)),
      color: firefly ? (Math.random() < 0.6 ? SPORES[2] : SPORES[3]) : SPORES[(Math.random() * 2) | 0],
      phase: Math.random() * 6.28,
      blink: firefly ? 0.7 + Math.random() * 1.3 : 0,
      firefly,
    };
  }

  lights() {
    const out = [];
    const reduced = this.paused || prefersReduced();
    if (this.mouse.seen && !reduced) out.push({ x: this.mouse.x, y: this.mouse.y, r: 150, s: 0.55, c: [150, 110, 255] });
    for (const el of document.querySelectorAll("[data-light]")) {
      if (!el.offsetParent) continue;
      const b = el.getBoundingClientRect();
      if (!b.width) continue;
      const page = el.closest(".page");
      if (page && !page.classList.contains("is-active")) continue;
      let r = Number(el.dataset.light) || 160;
      let s = 0.85;
      if (el.id === "play-btn") {
        // a closed stone (game running, nothing to start) only glows faintly
        if (el.disabled && this.flare < 0.05) s *= 0.4;
        r *= 1 + this.flare * 5;
        s += this.flare * 0.4;
      }
      const c = (el.dataset.lightColor || "79,227,193").split(",").map(Number);
      out.push({ x: b.left + b.width / 2, y: b.top + b.height / 2, r, s, c });
    }
    return out;
  }

  frame(now) {
    requestAnimationFrame((t) => this.frame(t));
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    // 30 steps a second are plenty for a dithered night and spare the GPU.
    this.acc += dt;
    if (this.acc < 1 / 30) return;
    const step = this.acc;
    this.acc = 0;
    const reduced = this.paused || prefersReduced();
    if (!reduced) this.t += step;
    const m = this.mouse;
    m.x += (m.tx - m.x) * Math.min(1, step * 7);
    m.y += (m.ty - m.y) * Math.min(1, step * 7);
    this.dim += (this.dimTarget - this.dim) * Math.min(1, step * 2.2);
    this.flare += (this.flareTarget - this.flare) * Math.min(1, step * 1.6);

    const { cw, ch, image } = this;
    const data = image.data;
    const lights = this.lights().map((l) => ({
      x: l.x / CELL,
      y: l.y / CELL,
      inv: CELL / l.r,
      s: l.s,
      c: l.c,
    }));
    const t = this.t;
    const base = this.dim;
    const cx = cw * 0.46;
    const cy = ch * 0.5;
    const ex = 1 / (cw * 0.62);
    const ey = 1 / (ch * 0.62);
    for (let y = 0; y < ch; y++) {
      const row = y * cw;
      const by = (y & 3) * 4;
      const dyE = (y - cy) * ey;
      const smokeY = Math.sin(y * 0.071 - t * 0.21) * 2.1;
      for (let x = 0; x < cw; x++) {
        // light from every source, soft cubic fall-off
        let lit = 0;
        let lr = 0;
        let lg = 0;
        let lb = 0;
        for (let i = 0; i < lights.length; i++) {
          const L = lights[i];
          const dx = (x - L.x) * L.inv;
          const dy = (y - L.y) * L.inv * 1.25;
          const d2 = dx * dx + dy * dy;
          if (d2 >= 1) continue;
          const f = (1 - d2) * (1 - d2) * L.s;
          lit += f;
          lr += L.c[0] * f;
          lg += L.c[1] * f;
          lb += L.c[2] * f;
        }
        // darkness: base, the rim of the window, drifting smoke
        const dxE = (x - cx) * ex;
        const edge = dxE * dxE + dyE * dyE;
        const smoke = Math.sin(x * 0.052 + t * 0.17 + smokeY) * Math.sin(y * 0.043 - x * 0.021 + t * 0.11);
        let dark = base + edge * 0.42 + smoke * 0.07 - lit;
        if (dark < 0) dark = 0;
        else if (dark > 0.96) dark = 0.96;
        const level = dark * 5;
        const k = level | 0;
        const a = (k + (level - k > BAYER[by + (x & 3)] ? 1 : 0)) / 5;
        const o = (row + x) * 4;
        if (a > 0.01) {
          data[o] = NIGHT[0];
          data[o + 1] = NIGHT[1];
          data[o + 2] = NIGHT[2];
          data[o + 3] = a * 242;
        } else if (lit > 0.05) {
          // inside a pool of light: a faint tint of the light's colour, also dithered
          const glow = Math.min(0.5, lit * 0.32) * 4;
          const g = glow | 0;
          const ga = (g + (glow - g > BAYER[by + (x & 3)] ? 1 : 0)) / 4;
          data[o] = lr / lit;
          data[o + 1] = lg / lit;
          data[o + 2] = lb / lit;
          data[o + 3] = ga * 44;
        } else {
          data[o + 3] = 0;
        }
      }
    }

    // spores: single pixels drifting up, fireflies blink
    for (let i = 0; i < this.motes.length; i++) {
      const mo = this.motes[i];
      if (!reduced) {
        mo.x += (mo.vx + Math.sin(t * 0.7 + mo.phase) * 0.5) * step;
        mo.y += mo.vy * step;
      }
      if (mo.y < -2 || mo.x < -2 || mo.x > cw + 2) {
        this.motes[i] = this.spawn();
        continue;
      }
      let a = mo.firefly ? Math.max(0, Math.sin(t * mo.blink * 2 + mo.phase)) : 0.7;
      a *= Math.min(1, (mo.y / ch) * 4);
      if (a < 0.08) continue;
      const px = mo.x | 0;
      const py = mo.y | 0;
      if (px < 0 || py < 0 || px >= cw || py >= ch) continue;
      const o = (py * cw + px) * 4;
      data[o] = mo.color[0];
      data[o + 1] = mo.color[1];
      data[o + 2] = mo.color[2];
      data[o + 3] = 255 * a;
    }
    this.ctx.putImageData(image, 0, 0);
  }
}

/**
 * The group from the loading screen (assets/ui/loading_cast.png, data/loading.json):
 * Ellie, the knight, Gustav and Torben walk along a strip while the raven flies ahead.
 */
export class CastParade {
  constructor(canvas, sheetUrl) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.img = new Image();
    this.img.src = sheetUrl;
    this.running = false;
    this.cast = [
      { row: 0, count: 6, stride: 4.6 },
      { row: 1, count: 8, stride: 4.9 },
      { row: 2, count: 6, stride: 4.7 },
      { row: 3, count: 8, stride: 5.3 },
    ];
    this.scale = 1;
  }

  start() {
    if (this.running) return;
    this.running = true;
    // Start with the group already in view: the launch only takes a few seconds.
    this.x = Math.max(140, (this.canvas.getBoundingClientRect().width || 400) * 0.45);
    this.last = performance.now();
    requestAnimationFrame((t) => this.frame(t));
  }

  stop() {
    this.running = false;
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
  }

  frame(now) {
    if (!this.running) return;
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    const rect = this.canvas.getBoundingClientRect();
    const scale = 1;
    if (this.canvas.width !== Math.round(rect.width) || this.canvas.height !== Math.round(rect.height)) {
      this.canvas.width = Math.round(rect.width);
      this.canvas.height = Math.round(rect.height);
    }
    const { ctx } = this;
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    const speed = 36;
    this.x += speed * dt;
    const span = this.canvas.width + 4 * 34 + 80;
    if (this.x > span) this.x = -40;
    const ground = this.canvas.height - 2;
    if (this.img.complete && this.img.naturalWidth) {
      this.cast.forEach((c, i) => {
        const cx = this.x - i * 34;
        // One walk frame per `stride` pixels travelled, as in the game's loading screen.
        const f = ((Math.floor(cx / c.stride) % c.count) + c.count) % c.count;
        const x = Math.round(cx - 32 * scale);
        const y = Math.round(ground - 61 * scale);
        ctx.drawImage(this.img, f * 64, c.row * 64, 64, 64, x, y, 64 * scale, 64 * scale);
      });
      // The raven glides ahead, flapping now and then.
      const t = now / 1000;
      const flap = Math.floor(t * 8.2) % 8;
      const glide = Math.sin(t * 0.9) > 0.3;
      const bf = glide ? 8 + (Math.floor(t * 4) % 4) : flap;
      const bx = Math.round(this.x + 46);
      const by = Math.round(ground - 52 + Math.sin(t * 2.1) * 4);
      ctx.drawImage(this.img, bf * 64, 4 * 64, 64, 64, bx - 32, by - 32, 64, 64);
    }
    requestAnimationFrame((t) => this.frame(t));
  }
}
