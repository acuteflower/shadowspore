#!/usr/bin/env python3
"""Synthesized placeholders for the waystone statues (numpy + stdlib wave). Writes assets/audio/waystone/:
  swell.wav    a rising, shimmering drone (the statue wakes, ~5 s)
  crumble.wav  stone grains and dry growth letting go (the cracks and the ivy withering, ~2.5 s)
  chime_a/b/c  a crystal lighting up (three pitches of a glassy bell, ~2.2 s)
  bloom.wav    the moment of the flash: a deep resonant chord with an airy sparkle (~4 s)
  hum.wav      the quiet loop of an awakened statue (3.0 s, seamless)
Deterministic."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "waystone"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050


def band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(spec * ((f >= lo) & (f <= hi)), len(x))


def save(name, sig, level=0.8):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.int16(np.clip(sig, -1, 1) * 32767).tobytes())


def bell(t, f, decay, mod=1.4, depth=2.2):
    """A glassy FM bell: the modulator dies faster than the carrier."""
    m = np.sin(2 * np.pi * f * mod * t) * depth * np.exp(-t * decay * 1.7)
    return np.sin(2 * np.pi * f * t + m) * np.exp(-t * decay)


rng = np.random.default_rng(7)

# --- swell
n = int(RATE * 5.0)
t = np.arange(n) / RATE
env = (t / 5.0) ** 2.2 * np.minimum(1.0, (5.0 - t) / 0.4)
sig = np.zeros(n)
for f, a in ((55, 1.0), (82.4, 0.7), (110, 0.55), (164.8, 0.35), (220, 0.25)):
    sig += a * np.sin(2 * np.pi * f * t + 0.8 * np.sin(2 * np.pi * 0.3 * t))
shimmer = band(rng.normal(size=n), 2500, 7500) * (0.15 + 0.85 * (t / 5.0) ** 3) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t))
risers = np.sin(2 * np.pi * (220 + 440 * (t / 5.0) ** 2) * t) * (t / 5.0) ** 3 * 0.25
save("swell", (sig * 0.5 + shimmer * 0.5 + risers) * env, 0.75)

# --- crumble
n = int(RATE * 2.5)
t = np.arange(n) / RATE
sig = np.zeros(n)
for k in range(46):
    at = rng.uniform(0.0, 2.1) ** 1.2 * 0.95
    i0 = int(at * RATE)
    ln = int(RATE * rng.uniform(0.02, 0.07))
    tt = np.arange(ln) / RATE
    grain = band(rng.normal(size=ln), rng.uniform(900, 2600), 6000) * np.exp(-tt * rng.uniform(60, 130))
    grain += np.sin(2 * np.pi * rng.uniform(140, 320) * tt) * np.exp(-tt * 90) * 0.5
    sig[i0:i0 + ln] += grain * rng.uniform(0.25, 1.0) * (1.0 - at / 3.0)
sig += band(rng.normal(size=n), 3000, 9000) * np.exp(-t * 1.6) * 0.12
save("crumble", sig, 0.7)

# --- chimes
for name, f in (("chime_a", 659.3), ("chime_b", 880.0), ("chime_c", 1174.7)):
    n = int(RATE * 2.2)
    t = np.arange(n) / RATE
    sig = bell(t, f, 2.4) + 0.45 * bell(t, f * 2.0, 3.6, 1.0, 1.4) + 0.25 * bell(t, f * 3.01, 5.0, 1.0, 1.0)
    sig += band(rng.normal(size=n), 4000, 9000) * np.exp(-t * 18) * 0.08
    save(name, sig * np.minimum(1.0, t / 0.004), 0.7)

# --- bloom
n = int(RATE * 4.0)
t = np.arange(n) / RATE
sig = np.zeros(n)
for f, a in ((110.0, 1.0), (164.8, 0.8), (220.0, 0.7), (277.2, 0.5), (329.6, 0.45), (440.0, 0.3)):
    sig += a * (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.003 * t)) * np.exp(-t * (0.55 + f / 700.0))
sig *= np.minimum(1.0, t / 0.03)
sp = np.zeros(n)
for k in range(22):
    at = 0.05 + k * 0.09 + rng.uniform(0, 0.05)
    f = rng.choice([1318.5, 1568.0, 1760.0, 2093.0, 2637.0])
    i0 = int(at * RATE)
    tt = t[: n - i0]
    sp[i0:] += bell(tt, f, 6.0) * rng.uniform(0.08, 0.22)
whoosh = band(rng.normal(size=n), 600, 5000) * np.exp(-((t - 0.15) / 0.22) ** 2) * 0.5
save("bloom", sig * 0.6 + sp + whoosh, 0.8)

# --- hum loop: whole periods only so it joins seamlessly
n = int(RATE * 3.0)
t = np.arange(n) / RATE
sig = np.zeros(n)
for f, a in ((82.0, 0.6), (123.0, 0.35), (164.0, 0.3), (246.0, 0.14)):
    sig += a * np.sin(2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * (1 / 3.0) * t))  # 82 * 3 = 246 whole cycles: seamless
sig *= 0.75 + 0.25 * np.sin(2 * np.pi * (2 / 3.0) * t)
glass = bell(np.mod(t, 1.5), 1318.5, 3.5) * 0.06
save("hum", sig + glass, 0.35)
print("waystone audio written to", OUT)
