#!/usr/bin/env python3
"""Synthesised placeholder sounds of the wisp trail (Irrlichtspur, docs/raetsel_konzept.md section 1) -> assets/audio/wisp/ (numpy, deterministic):
wake (three rising glass notes: it wakes in its bowl), hop (a soft airy swish with a glassy tick: it darts on), call (a bell that swells: it waits),
scare (a high trembling chirp: it took fright), fizzle (a falling crackle: it has gone out), dive (a rising shimmer that plunges), bloom (a full
chord with a low thump: it sank into the ground and the light answers).
    py -3 tools/audio_wisp.py"""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "wisp")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(73)


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


def air(sec, k=30):
    return lowpass(rng.standard_normal(len(T(sec))), k)


# wake: three rising glass notes (the Wächterin's motif)
b = np.zeros(int(R * 1.6))
for i, f in enumerate((784.0, 988.0, 1318.5)):
    place(b, glass(f, 1.2, 3.2) * (0.7 + i * 0.15), i * 0.16)
save("wake", b)

# hop: a swish that swells and fades, a glassy tick on top
t = T(0.55)
sw = air(0.55, 18) * np.sin(np.pi * np.clip(t / 0.55, 0, 1)) ** 2
b = sw * 0.5
place(b, glass(1760.0, 0.3, 14) * 0.35, 0.03)
save("hop", b, 0.38)

# call: a bell that swells in and rings out
t = T(1.4)
b = glass(1046.5, 1.4, 2.4) * np.minimum(1, t * 6) + glass(1568.0, 1.4, 3.0) * 0.3 * np.minimum(1, t * 4)
save("call", b, 0.42)

# scare: a fast trembling chirp, falling at the end
t = T(0.42)
f = 2400 + 900 * np.sin(2 * np.pi * 22 * t) - 1200 * t
b = np.sin(2 * np.pi * np.cumsum(f) / R) * np.exp(-t * 7) * np.minimum(1, t * 900)
place(b, glass(2093.0, 0.3, 18) * 0.4, 0.0)
save("scare", b, 0.45)

# fizzle: a crackle that falls and thins out
t = T(1.1)
crack = (rng.random(len(t)) < 0.012 * np.exp(-t * 3)) * rng.standard_normal(len(t))
crack = lowpass(crack, 3) * 6
f = 1200 * np.exp(-t * 2.5) + 180
tone = np.sin(2 * np.pi * np.cumsum(f) / R) * np.exp(-t * 3.5) * 0.4
save("fizzle", crack + tone + air(1.1, 40) * np.exp(-t * 4) * 0.3, 0.45)

# dive: a rising shimmer, then a plunge
t = T(1.9)
f = np.where(t < 1.4, 600 + 900 * (t / 1.4) ** 2, 1500 - 1300 * ((t - 1.4) / 0.5))
b = np.sin(2 * np.pi * np.cumsum(f) / R) * np.minimum(1, t * 3) * np.where(t < 1.6, 1, np.exp(-(t - 1.6) * 9)) * 0.5
b += air(1.9, 10) * np.minimum(1, t / 1.6) ** 3 * np.where(t < 1.6, 1, np.exp(-(t - 1.6) * 12)) * 0.6
save("dive", b, 0.5)

# bloom: a low thump and a full chord that rings long
b = np.zeros(int(R * 3.2))
t = T(0.4)
place(b, np.sin(2 * np.pi * (70 - 30 * t) * t) * np.exp(-t * 9) * 1.4, 0.0)
for i, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5)):
    place(b, glass(f, 3.0, 1.3) * (0.5 if i < 3 else 0.32), 0.04 + i * 0.05)
save("bloom", b, 0.55)
print("wisp sounds written")
