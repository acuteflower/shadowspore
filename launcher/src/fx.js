// Cosmetic motion: drifting spores and fireflies, a shadow that the cursor's light
// pushes back (like the game's main menu), and the loading-screen walkers.
const prefersReduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const SPORE_COLORS = ["#9a6bff", "#c9a6ff", "#5ff0d0", "#8af7e2", "#ff6ad5", "#ffd38a"];

export class Atmosphere {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.motes = [];
    this.mouse = { x: -9999, y: -9999, tx: -9999, ty: -9999, seen: false };
    this.t = 0;
    this.paused = false;
    this.dim = 1; // 1 = full shadow at the edges, lower on content pages
    this.dimTarget = 1;
    this.resize = this.resize.bind(this);
    window.addEventListener("resize", this.resize);
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
    for (let i = 0; i < 70; i++) this.motes.push(this.spawn(true));
    this.last = performance.now();
    requestAnimationFrame((t) => this.frame(t));
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.canvas.width = Math.round(this.w * dpr);
    this.canvas.height = Math.round(this.h * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  spawn(anywhere = false) {
    const firefly = Math.random() < 0.28;
    return {
      x: Math.random() * this.w,
      y: anywhere ? Math.random() * this.h : this.h + 10,
      vx: (Math.random() - 0.5) * 6,
      vy: -(4 + Math.random() * (firefly ? 6 : 14)),
      size: firefly ? 2 : Math.random() < 0.7 ? 1 : 2,
      color: firefly ? (Math.random() < 0.6 ? "#7ff5d6" : "#ffd58a") : SPORE_COLORS[(Math.random() * SPORE_COLORS.length) | 0],
      phase: Math.random() * Math.PI * 2,
      blink: firefly ? 0.6 + Math.random() * 1.4 : 0,
      firefly,
      life: 0,
    };
  }

  frame(now) {
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    const reduced = () => this.paused || prefersReduced();
    if (!reduced()) this.t += dt;
    const { ctx, w, h, mouse } = this;
    mouse.x += (mouse.tx - mouse.x) * Math.min(1, dt * 6);
    mouse.y += (mouse.ty - mouse.y) * Math.min(1, dt * 6);
    this.dim += (this.dimTarget - this.dim) * Math.min(1, dt * 3);
    ctx.clearRect(0, 0, w, h);

    if (!reduced()) {
      ctx.globalCompositeOperation = "lighter";
      for (let i = 0; i < this.motes.length; i++) {
        const m = this.motes[i];
        m.life += dt;
        const sway = Math.sin(this.t * 0.8 + m.phase) * 8;
        m.x += (m.vx + sway * 0.4) * dt;
        m.y += m.vy * dt;
        // The cursor's light stirs the air a little.
        if (mouse.seen) {
          const dx = m.x - mouse.x;
          const dy = m.y - mouse.y;
          const d2 = dx * dx + dy * dy;
          if (d2 < 120 * 120) {
            const f = (1 - Math.sqrt(d2) / 120) * 40 * dt;
            m.x += (dx / 60) * f;
            m.y += (dy / 60) * f;
          }
        }
        if (m.y < -10 || m.x < -20 || m.x > w + 20) {
          this.motes[i] = this.spawn();
          continue;
        }
        let a = Math.min(1, m.life / 1.5) * Math.min(1, (m.y / h) * 3);
        if (m.firefly) a *= 0.35 + 0.65 * Math.max(0, Math.sin(this.t * m.blink * 2 + m.phase));
        else a *= 0.55;
        const x = Math.round(m.x);
        const y = Math.round(m.y);
        ctx.globalAlpha = a * 0.22;
        ctx.fillStyle = m.color;
        ctx.fillRect(x - m.size, y - m.size, m.size * 3, m.size * 3);
        ctx.globalAlpha = a;
        ctx.fillRect(x, y, m.size, m.size);
      }
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";
    }

    // Shadow creeping in from the edges; the cursor holds a pool of light open.
    const edge = ctx.createRadialGradient(w * 0.42, h * 0.45, Math.min(w, h) * 0.25, w * 0.5, h * 0.5, Math.max(w, h) * 0.78);
    const breathe = 0.04 * Math.sin(this.t * 0.6);
    edge.addColorStop(0, "rgba(6,3,12,0)");
    edge.addColorStop(1, `rgba(6,3,12,${(0.62 + breathe) * this.dim})`);
    ctx.fillStyle = edge;
    ctx.fillRect(0, 0, w, h);
    if (mouse.seen && !reduced()) {
      ctx.globalCompositeOperation = "destination-out";
      const r = 190;
      const g = ctx.createRadialGradient(mouse.x, mouse.y, 0, mouse.x, mouse.y, r);
      g.addColorStop(0, "rgba(0,0,0,0.75)");
      g.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = g;
      ctx.fillRect(mouse.x - r, mouse.y - r, r * 2, r * 2);
      ctx.globalCompositeOperation = "lighter";
      const glow = ctx.createRadialGradient(mouse.x, mouse.y, 0, mouse.x, mouse.y, 120);
      glow.addColorStop(0, "rgba(140,100,255,0.07)");
      glow.addColorStop(1, "rgba(140,100,255,0)");
      ctx.fillStyle = glow;
      ctx.fillRect(mouse.x - 120, mouse.y - 120, 240, 240);
      ctx.globalCompositeOperation = "source-over";
    }
    requestAnimationFrame((t) => this.frame(t));
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
