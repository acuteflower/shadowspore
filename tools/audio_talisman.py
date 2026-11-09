#!/usr/bin/env python3
"""Synthesised placeholder sounds of the talismans (docs/talisman_konzept.md) -> assets/audio/talisman/:
equip_silver (a high, bright tick of a fine chain and a small bell), equip_gold (warmer, a soft ring), equip_voidsteel (dull, with a low violet hum), off (a short quiet
rustle of a chain), absorb (the Schweigtropfen swallow a blow: a deep short bell with a ring). Deterministic."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "talisman")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(23)

def T(sec): return np.arange(int(R * sec)) / R

def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.7
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")

def bell(f, t, decay):
    return np.sin(2 * np.pi * f * t) * np.exp(-t * decay) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * decay * 1.8)

def place(buf, x, at):
    i = int(R * at); n = min(len(x), len(buf) - i); buf[i:i + n] += x[:n]

def chain(n, start=0.0, gap=0.035, bright=1.0):
    buf = np.zeros(int(R * (start + gap * n + 0.2)))
    for k in range(n):
        tick = np.diff(lowpass(rng.standard_normal(int(R * 0.03)), 3), prepend=0) * np.exp(-T(0.03) * 140) * (0.5 + 0.5 * rng.random()) * bright
        place(buf, tick, start + k * gap)
    return buf

for name, f, tail in (("silver", 2637, 0.55), ("gold", 1760, 0.8), ("voidsteel", 880, 0.9)):
    t = T(tail + 0.3)
    x = np.zeros(len(t)); place(x, chain(5, 0.0, 0.03, 1.4 if name == "silver" else 0.9), 0.0)
    place(x, bell(f, T(tail), 7.0 if name != "voidsteel" else 4.0) * 0.7, 0.12)
    if name == "voidsteel":
        place(x, np.sin(2 * np.pi * 98 * T(0.9)) * np.exp(-T(0.9) * 3.0) * 0.5, 0.1)
    save("equip_" + name, x)
save("off", chain(4, 0.0, 0.045, 0.8))
t = T(1.1)
a = bell(220, t, 3.2) * 0.9 + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 4.0) * 0.6
a *= 1 - np.exp(-t * 400)
save("absorb", a)
