/**
 * Night & Light Atmosphere + CastParade ported from launcher/src/fx.js.
 * Renders at quarter-resolution pixel scale with 4x4 Bayer ordered dithering,
 * cursor lantern glow, [data-light] emitters, rising void/life spores, and
 * pauses cleanly when off-screen or when reduced motion is active.
 */

const CELL = 4;
const BAYER4 = [
  0 / 16, 8 / 16, 2 / 16, 10 / 16,
  12 / 16, 4 / 16, 14 / 16, 6 / 16,
  3 / 16, 11 / 16, 1 / 16, 9 / 16,
  15 / 16, 7 / 16, 13 / 16, 5 / 16,
];

const MOTES = [
  [139, 92, 255],
  [79, 227, 193],
  [242, 195, 107],
  [220, 200, 255],
];

function hash2(x, y) {
  let n = Math.imul(x, 374761393) + Math.imul(y, 668265263);
  n = (n ^ (n >>> 13)) * 1274126177;
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}

function noise2(x, y) {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const xf = x - xi;
  const yf = y - yi;
  const u = xf * xf * (3 - 2 * xf);
  const v = yf * yf * (3 - 2 * yf);
  const a = hash2(xi, yi);
  const b = hash2(xi + 1, yi);
  const c = hash2(xi, yi + 1);
  const d = hash2(xi + 1, yi + 1);
  return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v;
}

export class Atmosphere {
  constructor(canvas, container = canvas.parentElement) {
    this.canvas = canvas;
    this.container = container || document.body;
    this.ctx = canvas.getContext('2d', { willReadFrequently: false });
    this.pointer = { x: -9999, y: -9999, active: false };
    this.lights = [];
    this.motes = [];
    this.cw = 0;
    this.ch = 0;
    this.image = null;
    this.t = 0;
    this.last = 0;
    this.mood = 'night';
    this.paused = false;
    this.visible = true;
    this.reduced = false;
    this.frameHandle = 0;
    this.lastDraw = 0;

    this.resize();
    this.bindEvents();
  }

  bindEvents() {
    this.onResize = () => {
      this.resize();
      if (this.paused || this.reduced) this.draw(this.t, true);
    };
    window.addEventListener('resize', this.onResize, { passive: true });

    window.addEventListener('pointermove', (e) => {
      const rect = this.canvas.getBoundingClientRect();
      this.pointer.x = (e.clientX - rect.left) / CELL;
      this.pointer.y = (e.clientY - rect.top) / CELL;
      this.pointer.active = e.clientY >= rect.top && e.clientY <= rect.bottom;
    }, { passive: true });

    window.addEventListener('pointerleave', () => {
      this.pointer.active = false;
    }, { passive: true });

    // Efficient Background Processing: pause canvas simulation when skipped/off-screen
    if ('contentVisibility' in document.documentElement.style && this.container) {
      this.container.addEventListener('contentvisibilityautostatechange', (e) => {
        this.setVisible(!e.skipped);
      });
    } else if ('IntersectionObserver' in window && this.container) {
      const io = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          this.setVisible(entry.isIntersecting);
        }
      }, { rootMargin: '180px' });
      io.observe(this.container);
    }

    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        this.stopLoop();
      } else if (this.visible && !this.paused && !this.reduced) {
        this.start();
      }
    });
  }

  setMood(mood) {
    this.mood = mood === 'day' ? 'day' : 'night';
    if (this.paused || this.reduced) this.draw(this.t, true);
  }

  setPaused(paused) {
    this.paused = !!paused;
    if (this.paused) {
      this.stopLoop();
      this.draw(this.t, true);
    } else if (this.visible && !this.reduced && !document.hidden) {
      this.start();
    }
  }

  setReduced(reduced) {
    this.reduced = !!reduced;
    if (this.reduced) {
      this.stopLoop();
      this.draw(this.t, true);
    } else if (this.visible && !this.paused && !document.hidden) {
      this.start();
    }
  }

  setVisible(visible) {
    this.visible = !!visible;
    if (!this.visible) {
      this.stopLoop();
    } else if (!this.paused && !this.reduced && !document.hidden) {
      this.start();
    }
  }

  measureLights() {
    const base = this.canvas.getBoundingClientRect();
    const out = [];
    document.querySelectorAll('[data-light]').forEach((el) => {
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height) return;
      const radius = Number(el.dataset.light || 200) / CELL;
      const raw = (el.dataset.lightColor || '139,92,255').split(',').map((n) => Number(n.trim()));
      out.push({
        x: (r.left - base.left + r.width / 2) / CELL,
        y: (r.top - base.top + r.height / 2) / CELL,
        radius,
        color: raw.length === 3 ? raw : [139, 92, 255],
      });
    });
    this.lights = out;
  }

  spawnMote(randomY = false) {
    return {
      x: Math.random() * (this.cw || 160),
      y: randomY ? Math.random() * (this.ch || 90) : (this.ch || 90) + Math.random() * 8,
      vx: (Math.random() - 0.5) * 4,
      vy: -(5 + Math.random() * 8),
      color: MOTES[(Math.random() * MOTES.length) | 0],
      firefly: Math.random() < 0.35,
      blink: 0.7 + Math.random() * 1.4,
      phase: Math.random() * Math.PI * 2,
    };
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    const cw = Math.max(48, Math.floor((rect.width || window.innerWidth) / CELL));
    const ch = Math.max(36, Math.floor((rect.height || window.innerHeight) / CELL));
    if (cw !== this.cw || ch !== this.ch) {
      this.cw = cw;
      this.ch = ch;
      this.canvas.width = cw;
      this.canvas.height = ch;
      this.image = this.ctx.createImageData(cw, ch);
      const count = Math.min(80, Math.max(24, Math.floor((cw * ch) / 480)));
      this.motes = Array.from({ length: count }, () => this.spawnMote(true));
    }
    this.measureLights();
  }

  start() {
    if (this.frameHandle || this.paused || this.reduced || !this.visible || document.hidden) {
      if (!this.frameHandle) this.draw(this.t, true);
      return;
    }
    this.measureLights();
    this.last = performance.now();
    this.lastDraw = 0;
    const tick = (now) => {
      this.frameHandle = 0;
      if (this.paused || this.reduced || !this.visible || document.hidden) return;
      if (now - this.lastDraw >= 32) {
        const dt = Math.min(0.08, (now - this.last) / 1000);
        this.last = now;
        this.lastDraw = now;
        this.t += dt;
        this.draw(this.t, false);
      }
      this.frameHandle = requestAnimationFrame(tick);
    };
    this.frameHandle = requestAnimationFrame(tick);
  }

  stopLoop() {
    if (this.frameHandle) {
      cancelAnimationFrame(this.frameHandle);
      this.frameHandle = 0;
    }
  }

  draw(t, staticFrame) {
    if (!this.ctx || !this.image) return;
    const { cw, ch, image } = this;
    const data = image.data;
    const isDay = this.mood === 'day';
    const baseR = isDay ? 18 : 10;
    const baseG = isDay ? 26 : 7;
    const baseB = isDay ? 20 : 18;
    const maxCover = isDay ? 0.56 : 0.92;
    const drift = staticFrame ? 0 : t * 0.24;

    if ((Math.floor(t * 2) % 3) === 0) this.measureLights();

    for (let y = 0; y < ch; y++) {
      const ny = y * 0.045;
      const vY = y / ch;
      const edgeY = Math.abs(vY - 0.5) * 1.45;
      for (let x = 0; x < cw; x++) {
        const o = (y * cw + x) * 4;
        const vX = x / cw;
        const edgeX = Math.abs(vX - 0.5) * 1.25;
        const vignette = Math.min(1, Math.hypot(edgeX, edgeY));
        const smoke = noise2(x * 0.045 + drift, ny - drift * 0.6);

        let light = 0;
        let tintR = 0;
        let tintG = 0;
        let tintB = 0;

        for (let i = 0; i < this.lights.length; i++) {
          const l = this.lights[i];
          const d = Math.hypot(x - l.x, y - l.y);
          if (d < l.radius) {
            const p = 1 - d / l.radius;
            const k = p * p;
            light += k * 0.85;
            tintR += l.color[0] * k;
            tintG += l.color[1] * k;
            tintB += l.color[2] * k;
          }
        }

        if (this.pointer.active) {
          const pr = 42;
          const d = Math.hypot(x - this.pointer.x, y - this.pointer.y);
          if (d < pr) {
            const k = (1 - d / pr);
            const kk = k * k;
            light += kk * 0.7;
            tintR += 79 * kk * 0.6;
            tintG += 227 * kk * 0.6;
            tintB += 193 * kk * 0.6;
          }
        }

        const cover = Math.max(0, Math.min(maxCover, vignette * 0.52 + smoke * 0.45 - light));
        const threshold = BAYER4[((y & 3) << 2) | (x & 3)];

        if (cover > threshold + 0.06) {
          const ga = Math.min(1, (cover - threshold) * 1.45);
          data[o] = baseR;
          data[o + 1] = baseG;
          data[o + 2] = baseB;
          data[o + 3] = Math.round(ga * (isDay ? 158 : 228));
        } else if (light > 0.14) {
          const ga = Math.min(1, light);
          data[o] = Math.min(255, Math.round(tintR / Math.max(0.4, light)));
          data[o + 1] = Math.min(255, Math.round(tintG / Math.max(0.4, light)));
          data[o + 2] = Math.min(255, Math.round(tintB / Math.max(0.4, light)));
          data[o + 3] = Math.round(ga * 36);
        } else {
          data[o + 3] = 0;
        }
      }
    }

    const step = staticFrame ? 0 : 0.032;
    for (let i = 0; i < this.motes.length; i++) {
      const mo = this.motes[i];
      if (!staticFrame) {
        mo.x += (mo.vx + Math.sin(t * 0.7 + mo.phase) * 0.5) * step;
        mo.y += mo.vy * step;
      }
      if (mo.y < -2 || mo.x < -2 || mo.x > cw + 2) {
        this.motes[i] = this.spawnMote(false);
        continue;
      }
      let a = mo.firefly ? Math.max(0, Math.sin(t * mo.blink * 2 + mo.phase)) : 0.78;
      a *= Math.min(1, (mo.y / ch) * 4);
      if (a < 0.08) continue;
      const px = mo.x | 0;
      const py = mo.y | 0;
      if (px < 0 || py < 0 || px >= cw || py >= ch) continue;
      const o = (py * cw + px) * 4;
      data[o] = mo.color[0];
      data[o + 1] = mo.color[1];
      data[o + 2] = mo.color[2];
      data[o + 3] = Math.round(255 * a);
    }

    this.ctx.putImageData(image, 0, 0);
  }
}

export class CastParade {
  constructor(canvas, sheetUrl, container = canvas.closest('.hero') || canvas.parentElement) {
    this.canvas = canvas;
    this.container = container || canvas;
    this.ctx = canvas.getContext('2d');
    this.img = new Image();
    this.img.src = sheetUrl;
    this.img.addEventListener('load', () => {
      if (this.paused || this.reduced) this.drawStatic();
    });
    this.cast = [
      { row: 0, count: 6, stride: 4.6 },
      { row: 1, count: 8, stride: 4.9 },
      { row: 2, count: 6, stride: 4.7 },
      { row: 3, count: 8, stride: 5.3 },
    ];
    this.x = 180;
    this.last = 0;
    this.paused = false;
    this.reduced = false;
    this.visible = true;
    this.frameHandle = 0;

    if ('contentVisibility' in document.documentElement.style && this.container) {
      this.container.addEventListener('contentvisibilityautostatechange', (e) => {
        this.setVisible(!e.skipped);
      });
    } else if ('IntersectionObserver' in window && this.container) {
      const io = new IntersectionObserver((entries) => {
        for (const entry of entries) this.setVisible(entry.isIntersecting);
      }, { rootMargin: '120px' });
      io.observe(this.container);
    }
  }

  setPaused(paused) {
    this.paused = !!paused;
    if (this.paused) {
      this.stopLoop();
      this.drawStatic();
    } else if (this.visible && !this.reduced) {
      this.start();
    }
  }

  setReduced(reduced) {
    this.reduced = !!reduced;
    if (this.reduced) {
      this.stopLoop();
      this.drawStatic();
    } else if (this.visible && !this.paused) {
      this.start();
    }
  }

  setVisible(visible) {
    this.visible = !!visible;
    if (!this.visible) {
      this.stopLoop();
    } else if (!this.paused && !this.reduced) {
      this.start();
    }
  }

  start() {
    if (this.frameHandle || this.paused || this.reduced || !this.visible) {
      if (!this.frameHandle) this.drawStatic();
      return;
    }
    const w = this.canvas.getBoundingClientRect().width || 380;
    if (!this.x || this.x > w + 160) this.x = Math.max(148, w * 0.52);
    this.last = performance.now();
    const tick = (now) => {
      this.frameHandle = 0;
      if (this.paused || this.reduced || !this.visible) return;
      this.frame(now);
      this.frameHandle = requestAnimationFrame(tick);
    };
    this.frameHandle = requestAnimationFrame(tick);
  }

  stopLoop() {
    if (this.frameHandle) {
      cancelAnimationFrame(this.frameHandle);
      this.frameHandle = 0;
    }
  }

  syncCanvasSize() {
    const rect = this.canvas.getBoundingClientRect();
    const w = Math.max(240, Math.round(rect.width || 360));
    const h = Math.max(60, Math.round(rect.height || 66));
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
  }

  drawStatic() {
    this.syncCanvasSize();
    if (!this.img.complete || !this.img.naturalWidth) return;
    const { ctx } = this;
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    const ground = this.canvas.height - 2;
    const startX = Math.max(170, Math.min(this.canvas.width - 70, this.x || this.canvas.width * 0.56));
    this.cast.forEach((c, i) => {
      const cx = startX - i * 34;
      ctx.drawImage(this.img, 0, c.row * 64, 64, 64, Math.round(cx - 32), Math.round(ground - 61), 64, 64);
    });
    ctx.drawImage(this.img, 8 * 64, 4 * 64, 64, 64, Math.round(startX + 46 - 32), Math.round(ground - 52), 64, 64);
  }

  frame(now) {
    this.syncCanvasSize();
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    const { ctx } = this;
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    const speed = 34;
    this.x += speed * dt;
    const span = this.canvas.width + 4 * 34 + 72;
    if (this.x > span) this.x = -36;

    const ground = this.canvas.height - 2;
    if (this.img.complete && this.img.naturalWidth) {
      this.cast.forEach((c, i) => {
        const cx = this.x - i * 34;
        const f = ((Math.floor(cx / c.stride) % c.count) + c.count) % c.count;
        ctx.drawImage(this.img, f * 64, c.row * 64, 64, 64, Math.round(cx - 32), Math.round(ground - 61), 64, 64);
      });
      const t = now / 1000;
      const flap = Math.floor(t * 8.2) % 8;
      const glide = Math.sin(t * 0.9) > 0.3;
      const bf = glide ? 8 + (Math.floor(t * 4) % 4) : flap;
      const bx = Math.round(this.x + 46);
      const by = Math.round(ground - 52 + Math.sin(t * 2.1) * 4);
      ctx.drawImage(this.img, bf * 64, 4 * 64, 64, 64, bx - 32, by - 32, 64, 64);
    }
  }
}
