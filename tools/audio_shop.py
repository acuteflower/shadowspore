#!/usr/bin/env python3
"""Synthesised placeholder sounds of the shop windows -> assets/audio/shop/: coin (two bright bell blips), tick (a soft wooden tap for choosing), done (a low warm chord for finished work), page (rustle of bark paper)."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "shop")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(7)

def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.7
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def bell(f, t, decay):
    return np.sin(2 * np.pi * f * t) * np.exp(-t * decay) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * decay * 1.8)

t = np.arange(int(R * 0.5)) / R
coin = bell(1568, t, 9)
t2 = np.arange(int(R * 0.5)) / R
second = bell(2093, t2, 8)
coin[int(R * 0.07):] += second[:len(coin) - int(R * 0.07)] * 0.9
save("coin", coin)
t = np.arange(int(R * 0.09)) / R
save("tick", (np.sin(2 * np.pi * 420 * t) + 0.5 * rng.standard_normal(len(t)) * np.exp(-t * 90)) * np.exp(-t * 55))
t = np.arange(int(R * 0.9)) / R
done = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * 3.2) for f in (196, 247, 294)) * (1 - np.exp(-t * 60))
save("done", done)
t = np.arange(int(R * 0.18)) / R
page = rng.standard_normal(len(t)) * np.exp(-t * 22) * (np.sin(2 * np.pi * 14 * t) * 0.5 + 0.5)
save("page", np.convolve(page, np.ones(6) / 6, mode="same"))
print("wrote", out)
