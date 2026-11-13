#!/usr/bin/env python3
"""Synthesised sounds of the star mirror (Sternenspiegel, docs/raetsel_konzept.md 6b) -> assets/audio/stars/ (numpy, deterministic):
lift (a stone scraped off the earth and a breath of effort-free grit), set (a soft stone thunk in the grass), chime_0..5 (a star settles: a high glass
note with a long shimmer, one pitch per star), solved (the stars answer: a slow rising arpeggio over a deep swell, water rushing up).
    py -3 tools/audio_star_mirror.py"""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "stars")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(131)


def T(sec): return np.arange(int(R * sec)) / R


def save(name, x, peak=0.6):
    x = x / max(np.abs(x).max(), 1e-6) * peak
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def place(buf, x, at):
    i = int(R * at); n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]


def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")


def glass(f, sec, decay):
    t = T(sec)
    x = np.sin(2 * np.pi * f * t * (1 + 0.003 * np.sin(2 * np.pi * 5 * t))) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 5) + 0.12 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 12)
    return x * np.exp(-t * decay) * np.minimum(1, t * 500)


def thump(f0, sec, decay):
    t = T(sec)
    return np.sin(2 * np.pi * f0 * t * (1 - 0.3 * t / sec)) * np.exp(-t * decay)


t = T(0.5)
b = lowpass(rng.standard_normal(len(t)), 6) * np.exp(-t * 7) * 0.6
place(b, thump(110, 0.25, 20) * 0.5, 0.0)
save("lift", b, 0.4)

b = thump(85, 0.4, 16)
place(b, lowpass(rng.standard_normal(int(R * 0.12)), 4) * np.exp(-T(0.12) * 40) * 0.4, 0.0)
save("set", b, 0.5)

for i, f in enumerate((1318.5, 1480.0, 1568.0, 1760.0, 1975.5, 2093.0)):
    b = glass(f, 2.2, 1.8) + glass(f * 1.5, 2.2, 2.6) * 0.25
    save("chime_%d" % i, b, 0.38)

b = np.zeros(int(R * 4.0))
swell = T(3.6)
place(b, (np.sin(2 * np.pi * 65 * swell) + 0.5 * np.sin(2 * np.pi * 98 * swell)) * np.sin(np.pi * np.clip(swell / 3.6, 0, 1)) * 0.5, 0.0)
place(b, lowpass(rng.standard_normal(len(swell)), 30) * np.sin(np.pi * np.clip(swell / 3.6, 0, 1)) ** 2 * 0.4, 0.2)
for k, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 2093.0)):
    place(b, glass(f, 2.6, 1.4) * 0.45, 0.25 + k * 0.16)
save("solved", b, 0.6)
print("star mirror sounds written to", os.path.normpath(out))
