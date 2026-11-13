#!/usr/bin/env python3
"""Synthesised sounds of the root weave (Wurzelgeflecht, docs/raetsel_konzept.md 6a) -> assets/audio/weave/ (numpy, deterministic):
tone_0..5 (a glass note per trial rune, a pentatonic row: the cube that was touched), pulse (a dry creak of wood running down a root),
rise (earth tearing and a stone grinding up), out (the heart is put out: a heavy thump under a falling hum), withdraw (the Wächterin's three
notes falling, roots slithering back), refuse (the thorns: a dry rasp), bloom (a seed opens: a rising shimmer), solved (the full chord and a thump).
    py -3 tools/audio_root_weave.py"""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "weave")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(97)


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


def glass(f, sec, decay, shimmer=0.004):
    t = T(sec)
    wob = 1.0 + shimmer * np.sin(2 * np.pi * 5.5 * t)
    x = np.sin(2 * np.pi * f * t * wob) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 6) + 0.15 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 14)
    return x * np.exp(-t * decay) * np.minimum(1, t * 600)


def noise(sec, k=1):
    x = rng.standard_normal(len(T(sec)))
    return lowpass(x, k) if k > 1 else x


def thump(f0, sec, decay):
    t = T(sec)
    return np.sin(2 * np.pi * f0 * t * (1 - 0.35 * t / sec)) * np.exp(-t * decay)


ROW = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]  # C D E G A C
for i, f in enumerate(ROW):
    b = glass(f, 1.1, 3.6) + glass(f * 0.5, 1.1, 5.0) * 0.25
    save("tone_%d" % i, b, 0.42)

# pulse: a short run of dry creaks
b = np.zeros(int(R * 0.34))
for k in range(5):
    c = noise(0.03, 3) * np.exp(-T(0.03) * 90)
    place(b, c * (1.0 - k * 0.15), 0.02 + k * 0.055)
place(b, thump(140, 0.3, 18) * 0.4, 0.0)
save("pulse", b, 0.35)

# rise: earth tears, a stone grinds up
t = T(1.0)
grind = lowpass(noise(1.0), 40) * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * t)) * np.sin(np.pi * np.clip(t / 0.9, 0, 1))
b = grind
for k in range(9):
    place(b, noise(0.04, 2) * np.exp(-T(0.04) * 70) * 0.5, rng.uniform(0.05, 0.8))
place(b, thump(70, 0.5, 9) * 0.9, 0.78)
save("rise", b, 0.5)

# out: the heart goes dark
t = T(1.6)
hum = (np.sin(2 * np.pi * 220 * t * (1 - 0.3 * t / 1.6)) + 0.4 * np.sin(2 * np.pi * 330 * t * (1 - 0.3 * t / 1.6))) * np.exp(-t * 1.8)
b = hum * 0.5
place(b, thump(55, 1.0, 5) * 1.2, 0.18)
place(b, thump(48, 0.8, 6) * 0.8, 0.55)
save("out", b, 0.62)

# withdraw: the three notes falling and roots slithering back
b = np.zeros(int(R * 1.8))
for i, f in enumerate((1318.5, 988.0, 784.0)):
    place(b, glass(f, 1.0, 4.0) * 0.6, i * 0.2)
place(b, lowpass(noise(1.4), 25) * np.sin(np.pi * np.clip(T(1.4) / 1.4, 0, 1)) * 0.5, 0.2)
save("withdraw", b, 0.45)

# refuse: a dry rasp of thorns
t = T(0.4)
b = lowpass(noise(0.4), 2) * np.exp(-t * 9) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 38 * t)))
place(b, thump(90, 0.2, 25) * 0.3, 0.0)
save("refuse", b, 0.4)

# bloom: a seed opens
t = T(1.2)
b = np.zeros(len(t))
for k, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):
    place(b, glass(f, 0.9, 4.5) * 0.4, k * 0.07)
place(b, lowpass(noise(0.8), 8) * np.sin(np.pi * np.clip(T(0.8) / 0.8, 0, 1)) * 0.15, 0.0)
save("bloom", b, 0.42)

# solved: the full chord and a thump
b = np.zeros(int(R * 3.2))
for f in (261.63, 329.63, 392.0, 523.25, 659.25, 783.99):
    place(b, glass(f, 3.0, 1.1) * 0.35, 0.05)
place(b, thump(60, 1.2, 4) * 0.9, 0.0)
save("solved", b, 0.62)
print("weave sounds written to", os.path.normpath(out))
