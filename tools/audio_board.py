#!/usr/bin/env python3
"""Synthesised placeholder sounds of the quest board -> assets/audio/board/: rustle_a/rustle_b (bark paper in the wind), tack (a pin pushed in), tear (a crow pulls a paper off), wet (rain on the papers),
bell (the rush notice, step 2), flip (a page turns, step 3). Placeholders, no external recordings."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "board")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(11)

def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.7
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")

def rustle(length, seed, rate):
    r = np.random.default_rng(seed)
    t = np.arange(int(R * length)) / R
    n = smooth(r.standard_normal(len(t)), 5) - smooth(r.standard_normal(len(t)), 60)
    flutter = (np.sin(2 * np.pi * rate * t + r.uniform(0, 6)) * 0.5 + 0.5) ** 2
    return n * flutter * np.sin(np.pi * t / length) ** 0.6

save("rustle_a", rustle(0.55, 1, 17))
save("rustle_b", rustle(0.4, 2, 23))
t = np.arange(int(R * 0.12)) / R
save("tack", (np.sin(2 * np.pi * 1700 * t) * 0.6 + np.sin(2 * np.pi * 620 * t)) * np.exp(-t * 70) + 0.3 * rng.standard_normal(len(t)) * np.exp(-t * 220))
t = np.arange(int(R * 0.35)) / R
tear = smooth(rng.standard_normal(len(t)), 3) * np.exp(-t * 7) * (0.6 + 0.4 * np.sin(2 * np.pi * 70 * t))
tear[: int(R * 0.03)] *= np.linspace(0, 1, int(R * 0.03))
save("tear", tear)
t = np.arange(int(R * 0.5)) / R
drops = np.zeros(len(t))
for k in range(14):
    at = int(rng.uniform(0, 0.45) * R)
    n = min(int(R * 0.04), len(t) - at)
    tt = np.arange(n) / R
    drops[at:at + n] += np.sin(2 * np.pi * rng.uniform(900, 1600) * tt) * np.exp(-tt * 120) * rng.uniform(0.3, 1)
save("wet", drops + 0.12 * smooth(rng.standard_normal(len(t)), 4) * np.exp(-t * 5))
t = np.arange(int(R * 1.4)) / R
bell = (np.sin(2 * np.pi * 740 * t) + 0.4 * np.sin(2 * np.pi * 740 * 2.76 * t)) * np.exp(-t * 3.2)
save("bell", bell * (1 - np.exp(-t * 400)))
save("flip", rustle(0.25, 5, 30))
print("wrote", out)
