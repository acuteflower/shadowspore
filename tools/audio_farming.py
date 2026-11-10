#!/usr/bin/env python3
"""Synthesised placeholder sounds of farming (docs/farming.md) -> assets/audio/farming/ (numpy + stdlib, deterministic):
hoe_till (a dull chop and a crumbling of earth), hoe_scrape (a short dry rake), can_pour (a soft stream and a few drops),
plant (a quiet press of earth and a small rustle), harvest (a wet tug, the pop of the root and falling crumbs)."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "farming")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(77)


def T(sec): return np.arange(int(R * sec)) / R


def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.6
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def place(buf, x, at):
    i = int(R * at); n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]


def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")


def thud(f, sec, decay):
    t = T(sec)
    return np.sin(2 * np.pi * (f * (1 + 0.6 * np.exp(-t * 40))) * t) * np.exp(-t * decay)


def crumble(sec, gain=1.0, grains=22):
    x = np.zeros(int(R * sec))
    for _ in range(grains):
        at = rng.random() * sec * 0.9
        t = T(0.02 + rng.random() * 0.03)
        g = lowpass(rng.standard_normal(len(t)), int(3 + rng.random() * 5)) * np.exp(-t * 90)
        place(x, g * (0.3 + rng.random() * 0.7), at)
    return x * gain


def noise_env(sec, k, shape):
    t = T(sec)
    return lowpass(rng.standard_normal(len(t)), k) * shape(t / sec)


x = np.zeros(int(R * 0.6))
place(x, thud(95, 0.25, 22) * 0.9, 0.0)
place(x, noise_env(0.12, 3, lambda u: np.exp(-u * 6)) * 0.5, 0.0)
place(x, crumble(0.4, 0.8), 0.05)
save("hoe_till", x)

x = np.zeros(int(R * 0.35))
place(x, noise_env(0.3, 6, lambda u: np.sin(np.pi * u) ** 1.5) * 0.7, 0.0)
place(x, crumble(0.25, 0.4, 12), 0.04)
save("hoe_scrape", x)

x = np.zeros(int(R * 1.1))
place(x, noise_env(0.8, 14, lambda u: np.sin(np.pi * np.clip(u, 0, 1)) ** 0.7) * 0.55 * (0.7 + 0.3 * np.sin(T(0.8) * 2 * np.pi * 31)), 0.0)
for k, at in enumerate((0.7, 0.82, 0.95)):
    t = T(0.08)
    place(x, np.sin(2 * np.pi * (700 + 250 * k) * t * (1 + 0.8 * t)) * np.exp(-t * 55) * 0.25, at)
save("can_pour", x)

x = np.zeros(int(R * 0.4))
place(x, thud(120, 0.15, 30) * 0.4, 0.0)
place(x, noise_env(0.25, 7, lambda u: np.sin(np.pi * u) ** 2) * 0.35, 0.03)
place(x, crumble(0.2, 0.4, 8), 0.1)
save("plant", x)

x = np.zeros(int(R * 0.7))
place(x, noise_env(0.2, 9, lambda u: np.sin(np.pi * u)) * 0.55, 0.0)
t = T(0.09)
place(x, np.sin(2 * np.pi * 260 * t * (1 + 3.0 * t)) * np.exp(-t * 50) * 0.7, 0.2)
place(x, crumble(0.4, 0.7, 16), 0.24)
save("harvest", x)
print("farming sounds written to", os.path.abspath(out))
