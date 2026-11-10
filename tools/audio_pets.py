#!/usr/bin/env python3
"""Synthesised placeholder sounds of the bond with wild birds (docs/pet_konzept.md) -> assets/audio/pets/ (numpy + stdlib, deterministic):
take (a dry little peck and a soft two-note chime: the bird takes food from her hand), up (a rising three-note shimmer: a new stage of trust),
refuse (a short dry flutter and a flick: it does not want that), notice (a quiet rustle and a questioning chirp: it has seen the food)."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "pets")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(41)


def T(sec): return np.arange(int(R * sec)) / R


def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.62
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def place(buf, x, at):
    i = int(R * at); n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]


def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")


def bell(f, sec, decay):
    t = T(sec)
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 9)) * np.exp(-t * decay) * np.minimum(1, t * 400)


def peck(strength=1.0):
    t = T(0.05)
    return np.diff(lowpass(rng.standard_normal(len(t)), 4), prepend=0) * np.exp(-t * 90) * strength * 3.0


def rustle(sec, gain=1.0):
    t = T(sec)
    n = lowpass(rng.standard_normal(len(t)), 5)
    return n * np.sin(np.pi * t / sec) ** 2 * (0.6 + 0.4 * np.sin(t * 2 * np.pi * 23)) * gain * 0.35


def chirp(f0, f1, sec, gain=1.0):
    t = T(sec); u = t / sec
    f = f0 + (f1 - f0) * u
    return np.sin(np.cumsum(f) * 2 * np.pi / R) * np.sin(np.pi * u) ** 0.8 * gain


x = np.zeros(int(R * 0.9))
place(x, peck(), 0.0); place(x, peck(0.7), 0.11)
place(x, bell(1568, 0.7, 6.5) * 0.45, 0.2); place(x, bell(2093, 0.6, 7.5) * 0.35, 0.32)
save("take", x)

x = np.zeros(int(R * 1.5))
for k, f in enumerate((1175, 1568, 2349)):
    place(x, bell(f, 1.0, 5.0) * (0.55 - k * 0.07), 0.0 + k * 0.14)
place(x, rustle(0.5, 0.5), 0.0)
save("up", x)

x = np.zeros(int(R * 0.55))
place(x, rustle(0.22, 1.2), 0.0)
place(x, np.diff(lowpass(rng.standard_normal(int(R * 0.04)), 3), prepend=0) * np.exp(-T(0.04) * 110) * 2.2, 0.2)
save("refuse", x)

x = np.zeros(int(R * 0.6))
place(x, rustle(0.25, 0.6), 0.0)
place(x, chirp(1500, 2100, 0.16, 0.5) * np.exp(-T(0.16) * 6), 0.2)
place(x, chirp(1900, 1700, 0.1, 0.35), 0.38)
save("notice", x)
# whistle: two falling-rising sweeps, airy (the call to the companion); mode: a short two-note tick; gift: a bright three-note glint
x = np.zeros(int(R * 0.75))
for at, a, b in ((0.0, 1900, 2700), (0.3, 2400, 1800)):
    w = chirp(a, b, 0.26, 0.8) * (1 + 0.12 * np.sin(T(0.26) * 2 * np.pi * 38))
    place(x, w + lowpass(rng.standard_normal(len(w)), 3) * 0.05 * np.sin(np.pi * np.linspace(0, 1, len(w))), at)
save("whistle", x)
x = np.zeros(int(R * 0.5))
place(x, bell(1319, 0.3, 11) * 0.6, 0.0); place(x, bell(1760, 0.3, 11) * 0.6, 0.11)
save("mode", x)
x = np.zeros(int(R * 1.0))
for k, f in enumerate((2093, 2637, 3136)):
    place(x, bell(f, 0.6, 8.0) * 0.4, 0.07 * k)
save("gift", x)
print("Wrote the seven pet sounds")
